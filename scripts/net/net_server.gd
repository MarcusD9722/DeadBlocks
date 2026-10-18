extends Node
## Dedicated-server networking (started by game.gd in server mode).
## Listens on UDP, logs players in (server password + name + PIN, proven with HMACs so neither
## crosses the network), keeps one ServerPlayer per player, sends everyone the others' movement
## 15 times a second, keeps clocks in sync, and runs chat and admin commands.
## It owns the world and every inventory: players ask to break, place, craft, eat and move
## items, the server checks and applies each request, and once a tick it sends every player the
## block changes in the chunks it subscribed them to (see Proto.SUB_RADIUS).
##
## Options (command line): --port=N --password=S --max-players=N --admins=Name,Name
##   --hosted-by=Name (Host game: stop once that player is gone) --test-log (print TIME lines)

const ServerPlayer := preload("res://scripts/server/server_player.gd")
const SNAP_EVERY := 2       # physics ticks per snapshot: 30 / 2 = 15 Hz
const TIME_EVERY := 5.0     # seconds between clock messages
const PIN_TRIES := 5        # wrong PINs before a name is locked
const PIN_LOCK_S := 300.0
const PW_TRIES := 3         # wrong passwords from one address before it is locked out
const PW_LOCK_S := 60.0
const MOVE_SPEED_LIMIT := 6.9 * 1.6  # m/s horizontal, sprint plus slack
const MOVE_SLACK := 2.0
## Host game: how long the server waits for its host to join, and to come back after leaving.
const HOST_JOIN_S := 60.0
const HOST_GONE_S := 15.0
const STATS_EVERY := 60.0   # seconds between "SERVER net:" lines in the log
const CHUNKS_PER_TICK := 4  # edited chunks sent in full per player per tick

var mp := SceneMultiplayer.new()
var peer := ENetMultiplayerPeer.new()
var port := Proto.DEFAULT_PORT
var password_key := PackedByteArray()
var max_players := Proto.MAX_PLAYERS
var admins: PackedStringArray = PackedStringArray()
var hosted_by := ""
var test_log := false

var _nonces := {}           # peer id -> nonce
var _live := {}             # peer ids with an open connection (logging in or playing)
var _pending := {}          # peer id -> account name (lower case), between login and connect
var players := {}           # peer id -> ServerPlayer
## Accounts by lower-case name: {name, pin_key, fails, locked_until, pos, yaw, health, food,
## kills, spawn, inv, play_s}. Loaded from and saved to players/<name>.json by `saver`.
var accounts := {}
## The save files (server/save.gd); null in tests that build a NetServer without saving.
var saver: Node = null
var _acc_dirty := {}
var _stopping := false
var _pw_fails := {}         # ip -> [count, first try ms]
var _next_net_id := 1
var _tick := 0
var _time_t := 0.0
var _log_t := 0.0
var _host_seen_ms := 0
var _stats_t := STATS_EVERY
var _sample_t := 0.0
var _host_joined := false
var _terrain := PackedByteArray()
## Number of the edit batch sent this tick; chunk copies say which batch they already include.
var _edit_seq := 0
var _rng := RandomNumberGenerator.new()
var _players_node: Node3D


func start() -> bool:
	if G.arg_value("--port=") != "":
		port = int(G.arg_value("--port="))
	password_key = Proto.password_key(G.arg_value("--password="))
	if G.arg_value("--max-players=") != "":
		max_players = clampi(int(G.arg_value("--max-players=")), 1, 32)
	for a in G.arg_value("--admins=").split(",", false):
		admins.append(a.strip_edges().to_lower())
	hosted_by = G.arg_value("--hosted-by=").to_lower()
	_host_seen_ms = Time.get_ticks_msec()
	test_log = G.has_arg("--test-log")
	_terrain = Proto.terrain_hash(G.game.seed_v)
	G.world.record_edits = true
	_rng.randomize()
	_players_node = Node3D.new()
	_players_node.name = "Players"
	G.game.add_child(_players_node)

	get_tree().set_multiplayer(mp)
	mp.auth_callback = _on_auth
	mp.auth_timeout = 10.0
	mp.server_relay = false
	mp.peer_authenticating.connect(_on_authenticating)
	mp.peer_connected.connect(_on_connected)
	mp.peer_disconnected.connect(_on_disconnected)
	mp.peer_authentication_failed.connect(_on_disconnected)
	mp.peer_packet.connect(_on_packet)
	# Spare slots for people being refused and for half-open attempts from reconnecting players.
	var err := peer.create_server(port, max_players + 8, Proto.CHANNELS)
	if err != OK:
		printerr("SERVER could not listen on UDP port %d (error %d). Is another server running?" % [port, err])
		return false
	mp.multiplayer_peer = peer
	print("SERVER Dead Blocks %s listening on UDP %d | seed %d | max players %d | admins %s" % [
		G.VERSION, port, G.game.seed_v, max_players, ", ".join(admins)])
	return true


func online_count() -> int:
	var n := 0
	for p in players.values():
		if p.is_ready:
			n += 1
	return n


## Where the players who could meet a zombie are (online and alive).
func alive_positions() -> Array:
	var out := []
	for p in players.values():
		if p.is_ready and not p.dead:
			out.append(p.global_position)
	return out


func player_positions() -> Array:
	var out := []
	for p in players.values():
		if p.is_ready:
			out.append(p.global_position)
	return out


# ------------------------------------------------------------ login

func _on_authenticating(id: int) -> void:
	_live[id] = true
	Proto.set_timeouts(peer.get_peer(id))
	var nonce := Crypto.new().generate_random_bytes(16)
	_nonces[id] = nonce
	var b := Proto.writer(Proto.A_CHALLENGE)
	b.put_u16(Proto.PROTOCOL)
	b.put_utf8_string(G.VERSION)
	b.put_data(nonce)
	b.put_64(G.game.seed_v)
	b.put_u16(WorldGen.VERSION)
	mp.send_auth(id, b.data_array)


func _on_auth(id: int, data: PackedByteArray) -> void:
	if data.is_empty() or data[0] != Proto.A_HELLO or not _nonces.has(id):
		_reject(id, "Unexpected login message.")
		return
	var nonce: PackedByteArray = _nonces[id]
	var b := Proto.reader(data)
	var proto := b.get_u16()
	var version := b.get_utf8_string()
	var pname := b.get_utf8_string().strip_edges()
	var pw_proof := Proto.get_bytes32(b)
	var pin_proof := Proto.get_bytes32(b)
	var pin_reg := Proto.get_bytes32(b)
	var terrain := Proto.get_bytes32(b)
	var ip := _ip_of(id)
	if proto != Proto.PROTOCOL or version != G.VERSION:
		_reject(id, "Version mismatch: the server runs Dead Blocks %s and you have %s. Download the matching version from github.com/MarcusD9722/DeadBlocks/releases" % [G.VERSION, version])
		return
	var pwf: Array = _pw_fails.get(ip, [0, 0])
	if pwf[0] >= PW_TRIES and Time.get_ticks_msec() - pwf[1] < PW_LOCK_S * 1000.0:
		_reject(id, "Too many wrong passwords. Wait a minute and try again.")
		return
	if pw_proof != Proto.hmac(password_key, nonce):
		if Time.get_ticks_msec() - pwf[1] > PW_LOCK_S * 1000.0:
			pwf = [0, Time.get_ticks_msec()]
		pwf[0] += 1
		_pw_fails[ip] = pwf
		_reject(id, "Wrong server password.")
		return
	_pw_fails.erase(ip)
	if not Proto.valid_name(pname):
		_reject(id, "Names are 3-16 letters, digits or _ (no spaces).")
		return
	if terrain != _terrain:
		_reject(id, "Terrain mismatch: your copy of the game builds a different world than the server. Make sure you both run version %s." % G.VERSION)
		return
	var key := pname.to_lower()
	var acc = accounts.get(key)
	var now := Time.get_ticks_msec() / 1000.0
	# An empty PIN key means the owner reset this name's PIN: the next sign-in sets a new one.
	var reset: bool = acc != null and (acc["pin_key"] as PackedByteArray).is_empty()
	if acc != null and not reset:
		if now < float(acc["locked_until"]):
			_reject(id, "Too many wrong PINs for %s. Try again in a few minutes." % acc["name"])
			return
		if pin_proof != Proto.hmac(acc["pin_key"], nonce):
			acc["fails"] = int(acc["fails"]) + 1
			if int(acc["fails"]) >= PIN_TRIES:
				acc["fails"] = 0
				acc["locked_until"] = now + PIN_LOCK_S
			_reject(id, "Wrong PIN for %s. (Forgot it? Ask the server owner to reset it.)" % acc["name"])
			return
		acc["fails"] = 0
	var replacing := _peer_of_name(key)
	if replacing == 0 and players.size() + _pending.size() >= max_players:
		_reject(id, "The server is full (%d players)." % max_players)
		return
	var pk := PackedByteArray()
	if acc == null or reset:
		# First join with this name: unmask the PIN key and check it matches the proof.
		pk = Proto.xor_bytes(pin_reg, Proto.hmac(password_key, nonce + "reg".to_utf8_buffer()))
		if pin_proof != Proto.hmac(pk, nonce):
			_reject(id, "Could not register that name. Please try again.")
			return
		_acc_dirty[key] = true
	if reset:
		acc["pin_key"] = pk
		print("SERVER %s set a new PIN" % acc["name"])
	elif acc == null:
		var inv := Inventory.new()
		inv.add(Items.BERRIES, 3)
		inv.add(Blocks.TORCH, 2)
		acc = {"name": pname, "pin_key": pk, "fails": 0, "locked_until": 0.0, "pos": G.game.spawn_pos, "yaw": 0.0, "inv": inv,
			"health": 100.0, "food": 100.0, "kills": 0, "spawn": G.game.spawn_pos, "play_s": 0.0}
		accounts[key] = acc
		print("SERVER new player %s" % pname)
	if replacing != 0:
		# Same name and correct PIN while still online (for example after a crash): the new
		# connection wins.
		print("SERVER %s signed in again; closing the old connection" % acc["name"])
		_send_to(replacing, _bye_bytes("You signed in from somewhere else."))
		players[replacing].leave_reason = "was replaced by a new sign-in"
		_remove_player(replacing)
		_disconnect_soon(replacing)
	_pending[id] = key
	var r := Proto.writer(Proto.A_RESULT)
	r.put_u8(1)
	r.put_utf8_string("")
	mp.send_auth(id, r.data_array)
	mp.complete_auth(id)


func _reject(id: int, reason: String) -> void:
	print("SERVER refused a login from %s: %s" % [_ip_of(id), reason])
	var r := Proto.writer(Proto.A_RESULT)
	r.put_u8(0)
	r.put_utf8_string(reason)
	mp.send_auth(id, r.data_array)
	_disconnect_soon(id)


## Disconnecting drops anything still queued for that peer, so wait a moment for the last
## message (a refusal reason, a kick notice) to arrive first.
func _disconnect_soon(id: int) -> void:
	get_tree().create_timer(0.3).timeout.connect(func():
		if _live.has(id):
			mp.disconnect_peer(id))


func _ip_of(id: int) -> String:
	var p := peer.get_peer(id)
	return p.get_remote_address() if p != null else "?"


func _peer_of_name(key: String) -> int:
	for id in players:
		if players[id].player_name.to_lower() == key:
			return id
	return 0


# ------------------------------------------------------------ sessions

func _on_connected(id: int) -> void:
	_nonces.erase(id)
	if not _pending.has(id):
		mp.disconnect_peer(id)
		return
	var key: String = _pending[id]
	_pending.erase(id)
	var acc: Dictionary = accounts[key]
	Proto.set_timeouts(peer.get_peer(id))
	var sp := ServerPlayer.new()
	sp.player_name = acc["name"]
	sp.peer_id = id
	sp.net_id = _next_net_id
	_next_net_id += 1
	sp.admin = admins.has(key)
	_players_node.add_child(sp)
	if acc["pos"] == Vector3.INF:
		acc["pos"] = G.game.spawn_pos
	if acc["spawn"] == Vector3.INF:
		acc["spawn"] = G.game.spawn_pos
	sp.global_position = acc["pos"]
	sp.yaw = acc["yaw"]
	sp.last_good = acc["pos"]
	sp.joined_ms = Time.get_ticks_msec()
	sp.last_move_ms = Time.get_ticks_msec()
	sp.last_recv_ms = Time.get_ticks_msec()
	sp.inv = acc["inv"]
	sp.inv_dirty = true
	sp.health = acc["health"]
	sp.food = acc["food"]
	sp.kills = acc["kills"]
	sp.spawn_point = acc["spawn"]
	sp.dead = sp.health <= 0.0
	players[id] = sp
	var w := Proto.writer(Proto.S_WELCOME)
	w.put_u16(sp.net_id)
	w.put_64(G.game.seed_v)
	w.put_u16(G.game.day)
	w.put_float(G.game.time)
	w.put_u8(1 if G.game.horde_active else 0)
	w.put_float(G.game.day_minutes)
	Proto.put_vec3(w, sp.global_position)
	w.put_float(sp.yaw)
	Proto.put_vec3(w, G.game.spawn_pos)
	w.put_u8(1 if sp.admin else 0)
	var others := []
	for p in players.values():
		if p != sp:
			others.append(p)
	w.put_u8(others.size())
	for p in others:
		w.put_u16(p.net_id)
		w.put_utf8_string(p.player_name)
	_send_to(id, w.data_array)
	var j := Proto.writer(Proto.S_JOIN)
	j.put_u16(sp.net_id)
	j.put_utf8_string(sp.player_name)
	_broadcast(j.data_array, id)
	_broadcast(_notice_bytes("%s joined the game." % sp.player_name, Color(0.8, 1, 0.8)), id)
	print("SERVER %s joined from %s (%d connected)" % [sp.player_name, _ip_of(id), players.size()])


func _on_disconnected(id: int) -> void:
	_live.erase(id)
	_nonces.erase(id)
	_pending.erase(id)
	_remove_player(id)


## Save where the player was, take them out of the world and tell everyone else.
func _remove_player(id: int) -> void:
	var sp = players.get(id)
	if sp == null:
		return
	players.erase(id)
	_store_account(sp)
	acc_play_time(sp)
	G.sim.remove_player(sp)
	sp.queue_free()
	var l := Proto.writer(Proto.S_LEAVE)
	l.put_u16(sp.net_id)
	_broadcast(l.data_array)
	# Players send movement 15 times a second, so a long silence means the connection died.
	var quiet: float = (Time.get_ticks_msec() - sp.last_recv_ms) / 1000.0
	var why: String = sp.leave_reason
	if why == "" and quiet > 3.0:
		why = "lost the connection (nothing received for %.1f s; ping was %d ms, packet loss %d%%)" % [quiet, sp.ping_ms, int(sp.loss_pct)]
		_broadcast(_notice_bytes("%s lost the connection." % sp.player_name, Color(1, 0.85, 0.7)))
	else:
		_broadcast(_notice_bytes("%s left the game." % sp.player_name, Color(1, 0.85, 0.7)))
	print("SERVER %s %s (%d connected)" % [sp.player_name, why if why != "" else "left", players.size()])
	if sp.refused > 0:
		var parts := []
		for k in sp.refuse_why:
			parts.append("%s %d" % [k, sp.refuse_why[k]])
		print("SERVER %s: %d of %d block requests refused this session (%s)" % [sp.player_name, sp.refused, sp.requests, ", ".join(parts)])
	if online_count() == 0 and not _stopping:
		print("SERVER nobody online: time paused at day %d %s" % [G.game.day, _clock()])
		G.game.set_mobs_paused(true)
		# Everything is quiet now: save it all, and back up (at most once an hour).
		save_world(false)
		if saver != null and saver.hours_since_backup() >= 1.0:
			saver.finish()
			saver.backup("server empty")
	elif not _stopping:
		save_world(false)  # their file now, not at the next autosave


# ------------------------------------------------------------ messages

func _on_packet(id: int, data: PackedByteArray) -> void:
	var sp = players.get(id)
	if sp == null or data.is_empty():
		return
	sp.last_recv_ms = Time.get_ticks_msec()
	var b := Proto.reader(data)
	match data[0]:
		Proto.C_MOVE:
			_on_move(sp, b)
		Proto.C_READY:
			if not sp.is_ready:
				sp.is_ready = true
				G.sim.add_player(sp)  # zombies can go after it now
				_send_to(id, _time_bytes())
				if online_count() == 1:
					print("SERVER %s is online: time running again" % sp.player_name)
					G.game.set_mobs_paused(false)
		Proto.C_FALL:
			sp.take_damage(float(b.get_u8()), Vector3.ZERO)
		Proto.C_RESPAWN:
			if sp.dead:
				sp.dead = false
				sp.health = 100.0
				sp.food = maxf(sp.food, 60.0)
				correct(sp, sp.spawn_point)
				print("SERVER %s respawned" % sp.player_name)
		Proto.C_CHAT:
			_on_chat(sp, b.get_utf8_string().strip_edges().left(Proto.MAX_CHAT))
		Proto.C_BREAK, Proto.C_PLACE, Proto.C_SWAP, Proto.C_CRAFT, Proto.C_EAT, Proto.C_ATTACK:
			_on_request(sp, data[0], b)


# ------------------------------------------------------------ building, crafting, eating

func _on_request(sp, type: int, b: StreamPeerBuffer) -> void:
	sp.last_seq = b.get_u16()
	sp.requests += 1
	# Always answer with the inventory, which also acknowledges the request: the client then
	# drops its own guess of what the request would do.
	sp.inv_dirty = true
	if not sp.is_ready:
		return
	match type:
		Proto.C_BREAK:
			var p := Proto.get_bpos(b)
			var expect := b.get_u8()
			_req_break(sp, p, expect, b.get_u8())
		Proto.C_PLACE:
			var p := Proto.get_bpos(b)
			var id := b.get_u8()
			_req_place(sp, p, id, b.get_u8())
		Proto.C_SWAP:
			var a := b.get_u8()
			var c := b.get_u8()
			if a < Inventory.SIZE and c < Inventory.SIZE:
				sp.inv.swap(a, c)
		Proto.C_CRAFT:
			var r := b.get_u8()
			_req_craft(sp, r, b.get_u8())
		Proto.C_EAT:
			_req_eat(sp, b.get_u8())
		Proto.C_ATTACK:
			var mob_id := b.get_u16()
			_req_attack(sp, mob_id, b.get_u8())


func _eye(sp) -> Vector3:
	return sp.global_position + Vector3(0, 1.62, 0)


func _in_reach(sp, p: Vector3i) -> bool:
	return _eye(sp).distance_to(Vector3(p) + Vector3(0.5, 0.5, 0.5)) <= Proto.REACH


## Undo the client's guess: resend the block as the server has it. `why` is counted for the log.
func _refuse(sp, p: Vector3i, why: String) -> void:
	sp.refused += 1
	sp.refuse_why[why] = int(sp.refuse_why.get(why, 0)) + 1
	if G.world.has_block_data(p):
		sp.fixes.append(p)


func _req_break(sp, p: Vector3i, expect: int, slot: int) -> void:
	var w = G.world
	var id: int = w.get_blockv(p)
	var why := _common_refusal(sp, p, slot)
	if why == "" and (id != expect or id <= 0):
		why = "block changed"
	var tool: int = sp.inv.id_at(slot)
	var bt := Rules.break_time(id, tool)
	var now := Time.get_ticks_msec()
	# Mining takes time; allow plenty of slack for lag, but not instant mining.
	if why == "" and (bt < 0.0 or now - sp.last_break_ms < bt * 350.0):
		why = "too fast"
	if why != "":
		_refuse(sp, p, why)
		return
	sp.last_break_ms = now
	w.set_block(p, Blocks.AIR)
	var got := Rules.collect(id, tool, _rng)
	if int(got["need_tier"]) > 0:
		_msg(sp, Rules.too_hard_text(got["need_tier"]), Color(1, 0.8, 0.5))
		return
	for d in got["items"]:
		if sp.inv.add(d[0], d[1]) > 0:
			_msg(sp, "Inventory full!", Color(1, 0.5, 0.4))


func _req_place(sp, p: Vector3i, id: int, slot: int) -> void:
	var w = G.world
	var why := _common_refusal(sp, p, slot)
	if why == "" and (sp.inv.id_at(slot) != id or not Items.is_block(id)):
		why = "not in that slot"
	elif why == "" and (p.y < 1 or p.y >= 63 or w.get_blockv(p) != Blocks.AIR):
		why = "space taken"
	var touching := false
	for d in [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		if w.get_blockv(p + d) != Blocks.AIR:
			touching = true
	if why == "" and (not touching or (Blocks.SHAPE[id] == Blocks.SH_CROSS and not Blocks.is_solid(w.get_blockv(p + Vector3i.DOWN)))):
		why = "nothing to build on"
	if why != "":
		_refuse(sp, p, why)
		return
	if Blocks.SOLID[id]:
		# Not inside another player. The builder checks itself: its own position here is a
		# little behind, and building a pillar under your own feet must work.
		var bmin := Vector3(p)
		for o in players.values():
			if o != sp and o.is_ready and not o.dead:
				var op: Vector3 = o.global_position
				if op.x + 0.3 > bmin.x and op.x - 0.3 < bmin.x + 1.0 and op.z + 0.3 > bmin.z and op.z - 0.3 < bmin.z + 1.0 \
						and op.y + 1.8 > bmin.y and op.y < bmin.y + 1.0:
					_refuse(sp, p, "player in the way")
					return
	sp.inv.remove_at(slot, 1)
	w.set_block(p, id)


func _common_refusal(sp, p: Vector3i, slot: int) -> String:
	if sp.dead:
		return "dead"
	if slot > 8:
		return "bad slot"
	if not G.world.has_block_data(p):
		return "chunk not loaded"
	if not _in_reach(sp, p):
		return "out of reach"
	return ""


func _req_craft(sp, idx: int, times: int) -> void:
	if idx >= Crafting.RECIPES.size():
		return
	var r: Dictionary = Crafting.RECIPES[idx]
	var stations: Array = G.world.stations_near(sp.global_position + Vector3(0, 1, 0), 4)
	var st: String = r["st"]
	if st != "" and not stations.has(st):
		_msg(sp, "You need to be near a %s for that." % Crafting.STATION_NAMES[st], Color(1, 0.8, 0.5))
		return
	for t in clampi(times, 1, 5):
		if not Crafting.can_craft(sp.inv, r, stations):
			break
		if not Crafting.craft(sp.inv, r):
			_msg(sp, "Inventory full!", Color(1, 0.5, 0.4))
			break


func _req_eat(sp, slot: int) -> void:
	if slot >= Inventory.SIZE:
		return
	var id: int = sp.inv.id_at(slot)
	if sp.dead or not Items.is_consumable(id):
		return
	var d := Items.info(id)
	var f := float(d.get("food", 0.0))
	var h := float(d.get("heal", 0.0))
	if f > 0.0 and sp.food >= 99.0 and (h <= 0.0 or sp.health >= 100.0):
		_msg(sp, "You're full.", Color(1, 1, 1))
		return
	if f <= 0.0 and h > 0.0 and sp.health >= 100.0:
		_msg(sp, "You're already at full health.", Color(1, 1, 1))
		return
	sp.inv.remove_at(slot, 1)
	sp.food = minf(100.0, sp.food + f)
	sp.health = minf(100.0, sp.health + h)
	var a := Proto.writer(Proto.S_ATE)
	a.put_u16(id)
	_send_to(sp.peer_id, a.data_array)


func _req_attack(sp, mob_id: int, slot: int) -> void:
	if sp.dead or slot > 8:
		return
	var now := Time.get_ticks_msec()
	if now - sp.last_attack_ms < 300:
		return  # the client's cooldown is 0.45 s; leave room for lag
	var mob = G.game.mob_by_net_id(mob_id)
	if mob == null or mob.dead:
		return
	if _eye(sp).distance_to(mob.global_position + Vector3(0, mob.height * 0.5, 0)) > Proto.MOB_REACH:
		return
	sp.last_attack_ms = now
	mob.hurt(Items.damage(sp.inv.id_at(slot)), sp.global_position, sp)


## A ServerPlayer was hit: tell its client (flash, sound, knockback).
func player_hurt(sp, amount: float, from: Vector3) -> void:
	var h := Proto.writer(Proto.S_HURT)
	h.put_u8(clampi(ceili(amount), 0, 255))
	Proto.put_vec3(h, from)
	_send_to(sp.peer_id, h.data_array)


func player_died(sp) -> void:
	print("SERVER %s died" % sp.player_name)
	_broadcast(_notice_bytes("%s died." % sp.player_name, Color(1, 0.6, 0.5)))


func tell(sp, text: String, col: Color) -> void:
	_msg(sp, text, col)


## Hunger and healing, like on a solo PC, and S_STATS whenever a shown number changes.
func _tick_players(delta: float) -> void:
	for sp in players.values():
		if not sp.is_ready:
			continue
		if not sp.dead:
			var sprint: bool = (sp.flags & Proto.F_SPRINT) != 0
			sp.food = maxf(0.0, sp.food - (0.065 + (0.12 if sprint else 0.0)) * delta)
			if sp.food <= 0.0:
				sp.health -= 1.0 * delta
				if sp.health <= 0.0:
					sp.health = 0.0
					sp.dead = true
					player_died(sp)
			elif sp.food > 45.0 and sp.health < 100.0:
				sp.health = minf(100.0, sp.health + 0.5 * delta)
		var shown := [ceili(sp.health), ceili(sp.food), sp.dead, sp.kills]
		if shown != sp.stats_sent:
			sp.stats_sent = shown
			var m := Proto.writer(Proto.S_STATS)
			m.put_u8(shown[0])
			m.put_u8(shown[1])
			m.put_u8(1 if sp.dead else 0)
			m.put_u16(sp.kills)
			_send_to(sp.peer_id, m.data_array)


func _msg(sp, text: String, col: Color) -> void:
	var m := Proto.writer(Proto.S_MSG)
	m.put_utf8_string(text)
	m.put_u8(int(col.r * 255))
	m.put_u8(int(col.g * 255))
	m.put_u8(int(col.b * 255))
	_send_to(sp.peer_id, m.data_array)


## Once a tick: subscriptions, edited chunks, this tick's block changes, and inventories.
func _flush_world() -> void:
	var w = G.world
	_edit_seq += 1
	var groups := {}  # chunk key -> [[block index, id], ...] in the order they happened
	for e in w.edits_out:
		var p: Vector3i = e[0]
		var k := Vector2i(p.x >> 4, p.z >> 4)
		if not groups.has(k):
			groups[k] = []
		groups[k].append([(p.x & 15) + (p.z & 15) * 16 + p.y * 256, e[1]])
	w.edits_out.clear()
	var cracks: Array = w.cracks_out
	w.cracks_out = []
	for sp in players.values():
		_update_subs(sp)
		_send_chunks(sp)
		_send_edits(sp, groups)
		if not cracks.is_empty():
			_send_cracks(sp, cracks)
		if sp.inv_dirty:
			sp.inv_dirty = false
			var m := Proto.writer(Proto.S_INV)
			m.put_u16(sp.last_seq)
			Proto.put_inventory(m, sp.inv.slots)
			_send_to(sp.peer_id, m.data_array)


func _update_subs(sp) -> void:
	var c := Vector2i(floori(sp.global_position.x / 16.0), floori(sp.global_position.z / 16.0))
	if c == sp.sub_center:
		return
	sp.sub_center = c
	var gone := []
	for k in sp.subs.keys():
		if maxi(absi(k.x - c.x), absi(k.y - c.y)) > Proto.UNSUB_RADIUS:
			sp.subs.erase(k)
			gone.append(k)
	if not gone.is_empty():
		sp.chunk_queue = sp.chunk_queue.filter(func(k): return sp.subs.has(k))
		var u := Proto.writer(Proto.S_UNSUB)
		Proto.put_keys(u, gone)
		_send_to(sp.peer_id, u.data_array)
	var fresh := []
	var wait := []
	var r := Proto.SUB_RADIUS
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var k := Vector2i(c.x + dx, c.y + dz)
			if sp.subs.has(k):
				continue
			sp.subs[k] = true
			if G.world.is_modified(k):
				wait.append(k)
			else:
				fresh.append(k)
	if fresh.is_empty() and wait.is_empty():
		return
	wait.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
	sp.chunk_queue.append_array(wait)
	var m := Proto.writer(Proto.S_SUB)
	m.put_u32(_edit_seq)
	Proto.put_keys(m, fresh)
	Proto.put_keys(m, wait)
	_send_to(sp.peer_id, m.data_array)


func _send_chunks(sp) -> void:
	var sent := 0
	while sent < CHUNKS_PER_TICK and not sp.chunk_queue.is_empty():
		var k: Vector2i = sp.chunk_queue.pop_front()
		if not sp.subs.has(k):
			continue
		var packed := Proto.pack_chunk(G.world.chunk_data(k))
		var m := Proto.writer(Proto.S_CHUNK)
		m.put_u32(_edit_seq)
		Proto.put_key(m, k)
		m.put_u32(packed.size())
		m.put_data(packed)
		_send_to(sp.peer_id, m.data_array, MultiplayerPeer.TRANSFER_MODE_RELIABLE, Proto.CH_BULK)
		sent += 1


func _send_cracks(sp, cracks: Array) -> void:
	var mine := cracks.filter(func(c): return sp.subs.has(Vector2i(c[0].x >> 4, c[0].z >> 4)))
	if mine.is_empty():
		return
	var m := Proto.writer(Proto.S_CRACKS)
	m.put_u16(mine.size())
	for c in mine:
		Proto.put_bpos(m, c[0])
		m.put_u8(c[1])
	_send_to(sp.peer_id, m.data_array)


func _send_edits(sp, groups: Dictionary) -> void:
	var mine := {}
	for k in groups:
		if sp.subs.has(k):
			mine[k] = groups[k].duplicate()
	# Refused requests: resend those blocks as they are now, after this tick's changes.
	for p in sp.fixes:
		var k := Vector2i(p.x >> 4, p.z >> 4)
		if sp.subs.has(k):
			if not mine.has(k):
				mine[k] = []
			mine[k].append([(p.x & 15) + (p.z & 15) * 16 + p.y * 256, G.world.get_blockv(p)])
	sp.fixes.clear()
	if mine.is_empty():
		return
	var m := Proto.writer(Proto.S_EDITS)
	m.put_u32(_edit_seq)
	m.put_u16(mine.size())
	for k in mine:
		Proto.put_key(m, k)
		m.put_u16(mine[k].size())
		for e in mine[k]:
			m.put_u16(e[0])
			m.put_u8(e[1])
	_send_to(sp.peer_id, m.data_array)


func _on_move(sp, b: StreamPeerBuffer) -> void:
	var mid := b.get_u8()
	b.get_u16()  # seq (unused for now)
	var pos := Proto.get_vec3(b)
	var yaw := Proto.u16_to_yaw(b.get_u16())
	var pitch := b.get_16() / 10000.0
	var flags := b.get_u8()
	if mid != sp.move_id:
		return  # sent before our last correction
	var now := Time.get_ticks_msec()
	var dt := maxf(0.2, (now - sp.last_move_ms) / 1000.0)
	var d := Vector2(pos.x - sp.last_good.x, pos.z - sp.last_good.z).length()
	var limit := MOVE_SPEED_LIMIT + (8.0 if now < sp.knock_until_ms else 0.0)
	if d > limit * dt + MOVE_SLACK or not pos.is_finite():
		correct(sp, sp.last_good)
		return
	sp.last_good = pos
	sp.last_move_ms = now
	sp.global_position = pos
	sp.yaw = yaw
	sp.pitch = pitch
	sp.flags = flags & ~Proto.F_DEAD  # the server decides who is dead


## Move a player (rejected movement, or later teleports). Moves already in flight are ignored.
func correct(sp, pos: Vector3) -> void:
	sp.move_id = (sp.move_id + 1) & 0xff
	sp.last_good = pos
	sp.last_move_ms = Time.get_ticks_msec()
	sp.global_position = pos
	var c := Proto.writer(Proto.S_CORRECT)
	c.put_u8(sp.move_id)
	Proto.put_vec3(c, pos)
	_send_to(sp.peer_id, c.data_array)


func _on_chat(sp, text: String) -> void:
	if text == "":
		return
	if text.begins_with("/"):
		_command(sp, text)
		return
	print("CHAT <%s> %s" % [sp.player_name, text])
	var c := Proto.writer(Proto.S_CHAT)
	c.put_utf8_string(sp.player_name)
	c.put_utf8_string(text)
	_broadcast(c.data_array)


func _command(sp, text: String) -> void:
	var parts := text.split(" ", false)
	var cmd := parts[0].to_lower()
	var g = G.game
	if cmd == "/players" or cmd == "/who":
		var names := []
		for p in players.values():
			names.append(p.player_name)
		_send_to(sp.peer_id, _notice_bytes("Online: " + ", ".join(names), Color(0.8, 0.9, 1)))
		return
	if cmd == "/hash" and parts.size() >= 4:
		# Tests: a fingerprint of the server's blocks around a chunk, to compare with a client's.
		var cx := int(parts[1])
		var cz := int(parts[2])
		var r := clampi(int(parts[3]), 0, 4)
		_send_to(sp.peer_id, _notice_bytes("HASH %d %d %d %s" % [cx, cz, r, G.world.region_hash(cx, cz, r)], Color(0.7, 0.7, 0.7)))
		return
	if not sp.admin:
		_send_to(sp.peer_id, _notice_bytes("Only admins can use %s." % cmd, Color(1, 0.6, 0.5)))
		return
	match cmd:
		"/dusk":
			g.skip_time(false)
		"/bloodmoon":
			g.skip_time(true)
		"/time":
			if parts.size() > 1:
				g.time = clampf(float(parts[1]), 0.0, 23.99)
		"/kick":
			if parts.size() > 1:
				var target := _peer_of_name(parts[1].to_lower())
				if target != 0:
					_send_to(target, _bye_bytes("You were kicked by %s." % sp.player_name))
					players[target].leave_reason = "was kicked by %s" % sp.player_name
					_disconnect_soon(target)
		"/save":
			save_world(false)
			_send_to(sp.peer_id, _notice_bytes("Saving the world.", Color(0.8, 0.9, 1)))
			return
		"/spawn":
			var what := parts[1].to_lower() if parts.size() > 1 else ""
			var n := clampi(int(parts[2]) if parts.size() > 2 else 1, 1, 50)
			if not what in ["zombie", "night", "horde", "boar"]:
				_send_to(sp.peer_id, _notice_bytes("Usage: /spawn zombie|night|horde|boar [count]", Color(1, 0.6, 0.5)))
				return
			var made := 0
			for i in n:
				if G.game.spawn_near(what, sp.global_position) != null:
					made += 1
			print("SERVER %s used %s" % [sp.player_name, text])
			_send_to(sp.peer_id, _notice_bytes("Spawned %d %s." % [made, what], Color(0.8, 0.9, 1)))
			return
		"/give":
			var id := _item_named(parts[1] if parts.size() > 1 else "")
			if id <= 0:
				_send_to(sp.peer_id, _notice_bytes("Usage: /give <item> [count], for example /give planks 20 or /give stone_pickaxe", Color(1, 0.6, 0.5)))
				return
			var n := clampi(int(parts[2]) if parts.size() > 2 else 1, 1, 999)
			var left: int = sp.inv.add(id, n)
			sp.inv_dirty = true
			print("SERVER %s used %s" % [sp.player_name, text])
			_send_to(sp.peer_id, _notice_bytes("Gave you %d %s." % [n - left, Items.name_of(id)], Color(0.8, 0.9, 1)))
			return
		_:
			_send_to(sp.peer_id, _notice_bytes("Commands: /players /dusk /bloodmoon /time <hour> /kick <name> /give <item> [count] /spawn <zombie|horde|boar> [count] /save", Color(0.8, 0.9, 1)))
			return
	print("SERVER %s used %s" % [sp.player_name, text])
	_broadcast(_time_bytes())
	_send_to(sp.peer_id, _notice_bytes("Done: " + text, Color(0.8, 0.9, 1)))


## "/give" item names: an id, or the name in lower case with _ for spaces ("stone_pickaxe").
func _item_named(s: String) -> int:
	s = s.strip_edges().to_lower()
	if s == "":
		return 0
	if s.is_valid_int():
		var id := int(s)
		return id if Items.name_of(id) != "?" and id != Blocks.AIR else 0
	var ids: Array = range(1, Blocks.COUNT)
	ids.append_array(Items.DATA.keys())
	for id in ids:
		var n := Items.name_of(id).to_lower().replace(" ", "_")
		# "plank" / "planks", "log" / "logs", "torch" / "torches"
		if n == s or n.trim_suffix("s") == s.trim_suffix("s") or n == s.trim_suffix("es"):
			return id
	return 0


func _notice_bytes(text: String, col: Color) -> PackedByteArray:
	var n := Proto.writer(Proto.S_NOTICE)
	n.put_utf8_string(text)
	n.put_u8(int(col.r * 255))
	n.put_u8(int(col.g * 255))
	n.put_u8(int(col.b * 255))
	return n.data_array


func _bye_bytes(reason: String) -> PackedByteArray:
	var b := Proto.writer(Proto.S_BYE)
	b.put_utf8_string(reason)
	return b.data_array


func _time_bytes() -> PackedByteArray:
	var t := Proto.writer(Proto.S_TIME)
	t.put_u16(G.game.day)
	t.put_float(G.game.time)
	t.put_u8(1 if G.game.horde_active else 0)
	t.put_u8(1 if online_count() == 0 else 0)
	return t.data_array


func _send_to(id: int, data: PackedByteArray, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE, ch := Proto.CH_CONTROL) -> void:
	if players.has(id) or _pending.has(id):
		_send_raw(id, data, mode, ch)


## Every send goes through here. When several players leave at once, ENet has already closed
## the others' connections before we hear about them, and sending to those is an error.
func _send_raw(id: int, data: PackedByteArray, mode: MultiplayerPeer.TransferMode, ch: int) -> void:
	if not _live.has(id):
		return
	var ep := peer.get_peer(id)
	if ep == null or ep.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return
	mp.send_bytes(data, id, mode, ch)


func _broadcast(data: PackedByteArray, except := 0) -> void:
	for id in players:
		if id != except:
			_send_raw(id, data, MultiplayerPeer.TRANSFER_MODE_RELIABLE, Proto.CH_CONTROL)


func _clock() -> String:
	var t: float = G.game.time
	return "%02d:%02d" % [int(t), int((t - int(t)) * 60.0)]


# ------------------------------------------------------------ per tick

func _physics_process(delta: float) -> void:
	_tick += 1
	_tick_players(delta)
	_flush_world()
	if _tick % SNAP_EVERY != 0:
		return
	var ready_players := []
	for p in players.values():
		if p.is_ready:
			ready_players.append(p)
	# Even alone, a player gets an (empty) snapshot: the steady stream is how clients notice
	# when the server goes quiet.
	if ready_players.is_empty():
		return
	var mobs := mob_list(G.game.mobs)
	for to in ready_players:
		var s := Proto.writer(Proto.S_SNAP)
		s.put_u32(_tick)
		s.put_u8(ready_players.size() - 1)
		for p in ready_players:
			if p != to:
				Proto.put_player_record(s, p.net_id, p.global_position, p.yaw, p.pitch, p.flags | (Proto.F_DEAD if p.dead else 0))
		_send_raw(to.peer_id, s.data_array, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, Proto.CH_STATE)
		_send_mobs(to, mobs)


func _send_mobs(to, mob_list: Array) -> void:
	for pkt in mob_packets(_tick, to.global_position, mob_list):
		_send_raw(to.peer_id, pkt, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, Proto.CH_STATE)


## Every mob's snapshot data, gathered once per round: [pos, id, kind, yaw, flags].
static func mob_list(mobs_root: Node) -> Array:
	var out := []
	for m in mobs_root.get_children():
		if m is Mob and m.net_id != 0:
			out.append([m.global_position, m.net_id, m.net_kind(), m.rotation.y, m.net_flags()])
	return out


## S_MOBS for a player at `pos`: every mob of `mobs` (from mob_list) within Proto.MOB_RANGE, in
## packets of up to Proto.MOBS_PER_PACKET (always at least one, so an empty view clears the
## client's list). Static so the benchmark can time it for many clients.
static func mob_packets(tick: int, pos: Vector3, mobs: Array) -> Array:
	var origin := Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
	var near := []
	var r2 := Proto.MOB_RANGE * Proto.MOB_RANGE
	for m in mobs:
		if (m[0] as Vector3).distance_squared_to(pos) <= r2:
			near.append(m)
	var out := []
	var i := 0
	while i < near.size() or out.is_empty():
		var n := mini(Proto.MOBS_PER_PACKET, near.size() - i)
		var s := Proto.writer(Proto.S_MOBS)
		s.put_u32(tick)
		Proto.put_key(s, origin)
		s.put_u8(n)
		for j in n:
			var m: Array = near[i + j]
			Proto.put_mob(s, origin, m[1], m[2], m[0], m[3], m[4])
		out.append(s.data_array)
		i += maxi(n, 1)
	return out


func _process(delta: float) -> void:
	_sample_t -= delta
	if _sample_t <= 0.0:
		_sample_t = 2.0
		_sample_connections()
	_stats_t -= delta
	if _stats_t <= 0.0:
		_stats_t = STATS_EVERY
		if not players.is_empty():
			var parts := []
			for p in players.values():
				parts.append("%s %d ms, loss %d%%" % [p.player_name, p.ping_ms, int(p.loss_pct)])
			print("SERVER net: " + " | ".join(parts))
	_time_t -= delta
	if _time_t <= 0.0:
		_time_t = TIME_EVERY
		var t := _time_bytes()
		for p in players.values():
			if p.is_ready:
				_send_raw(p.peer_id, t, MultiplayerPeer.TRANSFER_MODE_RELIABLE, Proto.CH_CONTROL)
	if test_log:
		_log_t -= delta
		if _log_t <= 0.0:
			_log_t = 2.0
			print("TIME day=%d time=%.4f online=%d" % [G.game.day, G.game.time, online_count()])
	if hosted_by != "":
		# The game that started this server kills it when it closes; this covers a crash.
		if _peer_of_name(hosted_by) != 0:
			_host_seen_ms = Time.get_ticks_msec()
			_host_joined = true
		elif Time.get_ticks_msec() - _host_seen_ms > (HOST_GONE_S if _host_joined else HOST_JOIN_S) * 1000.0:
			stop_server("the host (%s) is gone" % hosted_by)
	if saver != null:
		_save_tick(delta)


# ------------------------------------------------------------ saving

## The account as it should be saved: where the player is now, and how they're doing.
func _store_account(sp) -> void:
	var key: String = sp.player_name.to_lower()
	var acc = accounts.get(key)
	if acc == null:
		return
	acc["pos"] = sp.last_good
	acc["yaw"] = sp.yaw
	acc["health"] = sp.health
	acc["food"] = sp.food
	acc["kills"] = sp.kills
	_acc_dirty[key] = true


func acc_play_time(sp) -> void:
	var acc = accounts.get(sp.player_name.to_lower())
	if acc != null and sp.joined_ms > 0:
		acc["play_s"] = float(acc.get("play_s", 0.0)) + (Time.get_ticks_msec() - sp.joined_ms) / 1000.0
		sp.joined_ms = Time.get_ticks_msec()


## Save the world: edited chunks changed since the last save, every account that changed, and
## the clock. `now` = on this thread, waiting for the files (stopping); otherwise in the background.
func save_world(now: bool) -> bool:
	if saver == null:
		return false
	for sp in players.values():
		_store_account(sp)
	var accs := {}
	for key in _acc_dirty:
		if accounts.has(key):
			accs[key] = accounts[key]
	if not now and saver.busy():
		return false  # the next autosave picks these up
	_acc_dirty.clear()
	var chunks: Array = G.world.take_unsaved()
	if now:
		return saver.save_now(G.game.day, G.game.time, chunks, accs)
	_last_job_chunks = chunks
	_last_job_accs = accs.keys()
	return saver.save_async(G.game.day, G.game.time, chunks, accs)


var _last_job_chunks: Array = []
var _last_job_accs: Array = []


func _save_tick(delta: float) -> void:
	var done: Dictionary = saver.poll()
	if not done.is_empty() and not done["ok"]:
		# Writing failed (disk full?): keep everything marked unsaved so the next try has it.
		for c in _last_job_chunks:
			G.world.save_dirty[c[0]] = true
		for key in _last_job_accs:
			_acc_dirty[key] = true
	var due: Dictionary = saver.tick(delta)
	for cmd in due.get("control", []):
		_control(cmd)
	if due.has("autosave") and (online_count() > 0 or not G.world.save_dirty.is_empty() or not _acc_dirty.is_empty()):
		save_world(false)
	if due.has("status"):
		var names := []
		for p in players.values():
			names.append(p.player_name)
		saver.write_status({"players": names, "zombies": get_tree().get_nodes_in_group("zombies").size(),
			"day": G.game.day, "time": _clock(), "blood_moon": G.game.horde_active})


## Commands from dbctl (files in control/).
func _control(cmd: String) -> void:
	var parts := cmd.split(" ", false)
	if parts.is_empty():
		return
	print("SERVER control: %s" % cmd)
	match parts[0].to_lower():
		"stop":
			stop_server("asked to stop")
		"save":
			save_world(false)
		"backup":
			save_world(true)
			saver.backup("asked for")
		"kick":
			if parts.size() > 1:
				var target := _peer_of_name(parts[1].to_lower())
				if target != 0:
					_send_to(target, _bye_bytes("You were kicked by the server owner."))
					players[target].leave_reason = "was kicked by the server owner"
					_disconnect_soon(target)
		"reset-pin":
			if parts.size() > 1 and accounts.has(parts[1].to_lower()):
				accounts[parts[1].to_lower()]["pin_key"] = PackedByteArray()
				_acc_dirty[parts[1].to_lower()] = true
				print("SERVER %s's PIN was reset: their next sign-in sets a new one" % parts[1])
		"say":
			_broadcast(_notice_bytes("[Server] " + cmd.substr(4), Color(1, 0.9, 0.6)))


## Save everything, tell everyone, and quit. The only safe way to stop: headless Godot dies at
## once on SIGTERM / SIGINT without running any of this.
func stop_server(why: String) -> void:
	if _stopping:
		return
	_stopping = true
	print("SERVER stopping (%s)" % why)
	for id in players.keys():
		_send_to(id, _bye_bytes("The server is stopping. Your progress is saved."))
	if saver != null:
		for sp in players.values():
			acc_play_time(sp)
		var ok := save_world(true)
		saver.release_lock()
		print("SERVER stopped%s" % ("" if ok else " (SAVING FAILED)"))
	# Let the goodbye messages go out before the process ends.
	get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())


## Remember each player's ping and packet loss while the connection is alive, for the leave
## message and the "SERVER net:" log line.
func _sample_connections() -> void:
	for id in players:
		if not _live.has(id):
			continue
		var ep := peer.get_peer(id)
		if ep == null:
			continue
		var sp = players[id]
		sp.ping_ms = int(ep.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
		sp.loss_pct = ep.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) * 100.0 / ENetPacketPeer.PACKET_LOSS_SCALE
