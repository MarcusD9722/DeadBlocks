extends Node
## Client networking. Lives under the G autoload, so the connection survives the scene reload
## that swaps the solo world for the server's world (G.start_client_session).
## Sends our movement 15 times a second and keeps a short history of everyone else's, which
## RemotePlayer nodes draw 100 ms in the past so movement looks smooth.
## If the connection drops while playing, it keeps logging back in for up to a minute; when the
## server answers with the same world, play simply continues (G.resume_client_session).
## The server owns blocks and inventories: break / place / craft / eat / move requests go to it,
## our own break or place shows at once as a guess, and the server's answer (edits, fixes, the
## inventory) replaces the guess.

signal status(text: String, is_error: bool)
signal chat(from: String, text: String)
signal notice(text: String, col: Color)

const SEND_EVERY := 4          # physics ticks per movement update: 60 / 4 = 15 Hz
const INTERP_DELAY := 0.1      # seconds remote players are drawn in the past
const CONNECT_TIMEOUT := 12.0
const RECONNECT_S := 60.0      # how long to keep trying after the connection drops
const RETRY_EVERY := 3.0

var mp: SceneMultiplayer = null
var peer: ENetMultiplayerPeer = null
var host := ""
var port := Proto.DEFAULT_PORT
var player_name := ""
var pin_key := PackedByteArray()
var password_key := PackedByteArray()
## Tests only: pretend to be another version, or to build different terrain.
var fake_version := ""
var fake_terrain := false
## idle -> connecting -> waiting_welcome -> online
var state := "idle"
var reject_reason := ""
## Why the server is closing our connection (kicked, signed in elsewhere): no reconnecting then.
var bye_reason := ""
var reconnecting := false
var _lost_at := 0.0
var _retry_at := 0.0
## When the last message from the server arrived (it sends 15 a second while we're online).
var last_recv := 0.0
var my_net_id := 0
var is_admin := false
## net id -> {"name": String, "samples": Array of [time s, pos, yaw, pitch, flags]}
var others := {}
var move_id := 0
var _seq := 0
var _tick := 0
## The world this client keeps in sync (set by game.gd once the server's world exists); world
## messages that arrive before that (during the scene reload) wait in _world_queue.
var world_target: Node = null
var _world_queue: Array = []
## The inventory as the server last sent it, and our guesses since: [seq, "remove", slot] or
## [seq, "swap", a, b], replayed on top until the server acknowledges that request.
var inv_slots: Array = []
var _inv_known := false
## Mobs the server runs, by id: {"kind", "seen": time s, "samples": [[time, pos, yaw, flags], ...]}.
var mobs := {}
## Bytes received per message type, for tests and the stats line.
var bytes_in := {}
## Our own backpacks (S_BACKPACKS): [[block pos, seconds left], ...], counted down while the
## world runs, for the marker on screen.
var my_backpacks: Array = []
## Our bed (S_BED), Vector3i.MIN without one: the death screen offers to wake up there.
var bed := Vector3i.MIN
var _req_seq := 0
var _guesses: Array = []
var _deadline := 0.0


func join(h: String, p: int, pname: String, pin_k: PackedByteArray, pw_k: PackedByteArray) -> void:
	host = h
	port = p
	player_name = pname
	pin_key = pin_k
	password_key = pw_k
	reconnecting = false
	_connect()


func _connect() -> void:
	_close()
	reject_reason = ""
	bye_reason = ""
	others.clear()
	move_id = 0
	mp = SceneMultiplayer.new()
	peer = ENetMultiplayerPeer.new()
	get_tree().set_multiplayer(mp)
	mp.auth_callback = _on_auth
	mp.auth_timeout = 10.0
	mp.peer_packet.connect(_on_packet)
	mp.connected_to_server.connect(_on_connected)
	mp.connection_failed.connect(_on_failed)
	mp.server_disconnected.connect(_on_server_gone)
	var err := peer.create_client(host, port, Proto.CHANNELS)
	if err != OK:
		state = "idle"
		_retry_at = _now() + RETRY_EVERY
		_status("Could not start connecting to %s (error %d)." % [host, err], true)
		return
	Proto.set_timeouts(peer.get_peer(1))
	mp.multiplayer_peer = peer
	state = "connecting"
	_deadline = _now() + CONNECT_TIMEOUT
	_status("Connecting to %s:%d..." % [host, port], false)


## Stop playing online: close the connection and don't reconnect.
func leave() -> void:
	reconnecting = false
	_close()


func _close() -> void:
	mobs.clear()
	if peer != null:
		peer.close()
	if mp != null:
		mp.multiplayer_peer = null
	peer = null
	mp = null
	state = "idle"
	others.clear()


func is_online() -> bool:
	return state == "online"


## Seconds since the server was last heard from (0 when not online).
func quiet_s() -> float:
	return _now() - last_recv if state == "online" else 0.0


## Seconds since the connection dropped, while reconnecting.
func reconnect_s() -> float:
	return _now() - _lost_at if reconnecting else 0.0


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Status for the title screen; while reconnecting it only goes to the log.
func _status(text: String, is_error: bool) -> void:
	print("NET ", text)
	if not reconnecting:
		status.emit(text, is_error)


func send_ready() -> void:
	_send(Proto.writer(Proto.C_READY).data_array)


## game.gd: the client world exists now; feed it what arrived meanwhile.
func attach(w: Node) -> void:
	world_target = w
	w.remote = true
	var q := _world_queue
	_world_queue = []
	for data in q:
		_on_world_packet(data)
	_apply_inventory()


func detach() -> void:
	world_target = null
	_world_queue.clear()


func _world_ready() -> bool:
	return world_target != null and is_instance_valid(world_target)


func _next_seq() -> int:
	_req_seq = (_req_seq + 1) & 0xffff
	return _req_seq


func request_break(p: Vector3i, expect: int, slot: int) -> void:
	var m := Proto.writer(Proto.C_BREAK)
	m.put_u16(_next_seq())
	Proto.put_bpos(m, p)
	m.put_u8(expect)
	m.put_u8(slot)
	_send(m.data_array)


func request_place(p: Vector3i, id: int, slot: int) -> void:
	var seq := _next_seq()
	var m := Proto.writer(Proto.C_PLACE)
	m.put_u16(seq)
	Proto.put_bpos(m, p)
	m.put_u8(id)
	m.put_u8(slot)
	_send(m.data_array)
	_guesses.append([seq, "remove", slot])
	_apply_inventory()


func request_swap(a: int, b: int) -> void:
	var seq := _next_seq()
	var m := Proto.writer(Proto.C_SWAP)
	m.put_u16(seq)
	m.put_u8(a)
	m.put_u8(b)
	_send(m.data_array)
	_guesses.append([seq, "swap", a, b])
	_apply_inventory()


func request_craft(recipe: int, times: int) -> void:
	var m := Proto.writer(Proto.C_CRAFT)
	m.put_u16(_next_seq())
	m.put_u8(recipe)
	m.put_u8(times)
	_send(m.data_array)


func request_attack(mob_id: int, slot: int) -> void:
	var m := Proto.writer(Proto.C_ATTACK)
	m.put_u16(_next_seq())
	m.put_u16(mob_id & 0xffff)
	m.put_u8(slot)
	_send(m.data_array)


func report_fall(damage: float) -> void:
	var m := Proto.writer(Proto.C_FALL)
	m.put_u8(clampi(ceili(damage), 1, 255))
	_send(m.data_array)


func request_respawn(at_bed: bool) -> void:
	var m := Proto.writer(Proto.C_RESPAWN)
	m.put_u8(0 if at_bed else 1)
	_send(m.data_array)


## Solo game: the pause menu opened or closed (the server stops or restarts the world).
func send_pause(on: bool) -> void:
	var m := Proto.writer(Proto.C_PAUSE)
	m.put_u8(1 if on else 0)
	_send(m.data_array)


## Where to draw a mob right now (like interpolated() for players). Empty if unknown.
func mob_sample(id: int) -> Dictionary:
	var o = mobs.get(id)
	if o == null or o["samples"].is_empty():
		return {}
	var s: Array = o["samples"]
	var t := Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	if t <= s[0][0]:
		return _sample(s[0])
	for i in range(s.size() - 1):
		var a: Array = s[i]
		var b: Array = s[i + 1]
		if t <= b[0]:
			var f := clampf((t - a[0]) / maxf(0.001, b[0] - a[0]), 0.0, 1.0)
			return {"pos": (a[1] as Vector3).lerp(b[1], f), "yaw": lerp_angle(a[2], b[2], f), "pitch": 0.0, "flags": b[4]}
	return _sample(s[s.size() - 1])


func request_eat(slot: int) -> void:
	var m := Proto.writer(Proto.C_EAT)
	m.put_u16(_next_seq())
	m.put_u8(slot)
	_send(m.data_array)


## The player's inventory = the server's copy plus our guesses not yet acknowledged.
func _apply_inventory() -> void:
	var p = G.player
	if not _inv_known or G.mode != "client" or p == null or not is_instance_valid(p):
		return
	var slots := []
	for sl in inv_slots:
		slots.append(null if sl == null else sl.duplicate())
	for g in _guesses:
		if g[1] == "remove":
			var sl = slots[g[2]]
			if sl != null:
				sl["n"] = int(sl["n"]) - 1
				if int(sl["n"]) <= 0:
					slots[g[2]] = null
		else:
			var t = slots[g[2]]
			slots[g[2]] = slots[g[3]]
			slots[g[3]] = t
	p.inv.slots = slots
	p.inv.changed.emit()


func _on_inventory(b: StreamPeerBuffer) -> void:
	var ack := b.get_u16()
	var slots := Proto.get_inventory(b)
	_guesses = _guesses.filter(func(g): return not Proto.seq_le(g[0], ack))
	if _inv_known and G.hud != null and is_instance_valid(G.hud):
		# "+3 Planks" for whatever the server added (drops, crafting, /give).
		var before := _counts(inv_slots)
		var after := _counts(slots)
		for id in after:
			var gained: int = after[id] - int(before.get(id, 0))
			if gained > 0:
				G.hud.pickup("+%d %s" % [gained, Items.name_of(id)])
	inv_slots = slots
	_inv_known = true
	_apply_inventory()


static func _counts(slots: Array) -> Dictionary:
	var c := {}
	for sl in slots:
		if sl != null:
			c[int(sl["id"])] = int(c.get(int(sl["id"]), 0)) + int(sl["n"])
	return c


func _on_world_packet(data: PackedByteArray) -> void:
	var w = world_target
	var b := Proto.reader(data)
	match data[0]:
		Proto.S_SUB:
			var seq := b.get_u32()
			var fresh := Proto.get_keys(b)
			w.net_subscribe(seq, fresh, Proto.get_keys(b))
		Proto.S_UNSUB:
			w.net_unsubscribe(Proto.get_keys(b))
		Proto.S_CHUNK:
			var seq := b.get_u32()
			var k := Proto.get_key(b)
			var size := b.get_u32()
			var packed: PackedByteArray = b.get_data(size)[1]
			w.net_chunk(seq, k, Proto.unpack_chunk(packed))
		Proto.S_EDITS:
			var seq := b.get_u32()
			var groups := []
			for i in b.get_u16():
				var k := Proto.get_key(b)
				var list := []
				for j in b.get_u16():
					var idx := b.get_u16()
					list.append([idx, b.get_u8()])
				groups.append([k, list])
			w.net_edits(seq, groups)


func send_chat(text: String) -> void:
	var t := text.strip_edges().left(Proto.MAX_CHAT)
	if t == "":
		return
	var c := Proto.writer(Proto.C_CHAT)
	c.put_utf8_string(t)
	_send(c.data_array)


func ping_ms() -> int:
	if peer == null:
		return -1
	var sp := peer.get_peer(1)
	if sp == null:
		return -1
	return int(sp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


## Where to draw another player right now: interpolated between the two snapshots around
## (now - INTERP_DELAY). Empty if we have nothing for them yet.
func interpolated(net_id: int) -> Dictionary:
	var o = others.get(net_id)
	if o == null or o["samples"].is_empty():
		return {}
	var s: Array = o["samples"]
	var t := Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	if t <= s[0][0]:
		return _sample(s[0])
	for i in range(s.size() - 1):
		var a: Array = s[i]
		var b: Array = s[i + 1]
		if t <= b[0]:
			var f := clampf((t - a[0]) / maxf(0.001, b[0] - a[0]), 0.0, 1.0)
			return {"pos": (a[1] as Vector3).lerp(b[1], f), "yaw": lerp_angle(a[2], b[2], f),
				"pitch": lerpf(a[3], b[3], f), "flags": b[4]}
	return _sample(s[s.size() - 1])


func _sample(a: Array) -> Dictionary:
	return {"pos": a[1], "yaw": a[2], "pitch": a[3], "flags": a[4]}


# ------------------------------------------------------------ login

func _on_auth(_id: int, data: PackedByteArray) -> void:
	if data.is_empty():
		return
	var b := Proto.reader(data)
	match data[0]:
		Proto.A_CHALLENGE:
			var server_proto := b.get_u16()
			var server_version := b.get_utf8_string()
			var mine := fake_version if fake_version != "" else G.VERSION
			if (server_proto != Proto.PROTOCOL or server_version != mine) and G.updater != null and G.updater.can_update():
				_switch_version(server_version)
				return
			var nonce: PackedByteArray = b.get_data(16)[1]
			var seed_v := b.get_64()
			var wg_version := b.get_u16()
			var h := Proto.writer(Proto.A_HELLO)
			h.put_u16(Proto.PROTOCOL)
			h.put_utf8_string(fake_version if fake_version != "" else G.VERSION)
			h.put_utf8_string(player_name)
			Proto.put_bytes32(h, Proto.hmac(password_key, nonce))
			Proto.put_bytes32(h, Proto.hmac(pin_key, nonce))
			Proto.put_bytes32(h, Proto.xor_bytes(pin_key, Proto.hmac(password_key, nonce + "reg".to_utf8_buffer())))
			var terrain := PackedByteArray()
			if wg_version == WorldGen.VERSION and not fake_terrain:
				terrain = Proto.terrain_hash(seed_v)
			Proto.put_bytes32(h, terrain)
			mp.send_auth(1, h.data_array)
			_status("Logging in...", false)
		Proto.A_RESULT:
			var ok := b.get_u8()
			var reason := b.get_utf8_string()
			if ok == 1:
				mp.complete_auth(1)
				state = "waiting_welcome"
				_status("Joining...", false)
			else:
				reject_reason = reason
				state = "idle"
				call_deferred("_close")
				if reconnecting:
					# The server is back but won't take us (restarted with another password or version).
					reconnecting = false
					G.call_deferred("end_client_session", reason)
				else:
					_join_failed(reason)


## The server runs another version than ours: get that one (updater.gd) instead of being refused.
## In the middle of a game (the server restarted with an update), back to the title first.
func _switch_version(v: String) -> void:
	var rejoin := {"host": host, "port": port, "name": player_name, "pin_key": pin_key, "password_key": password_key}
	var in_game := reconnecting
	reconnecting = false
	G.rejoining = false
	call_deferred("_close")
	if in_game:
		G.call_deferred("end_client_session", "The server was updated to Dead Blocks %s. Updating your game..." % v)
	G.updater.update_to(v, rejoin)


## A join that can't go on. When the game joined by itself after an update, back to the title.
func _join_failed(text: String) -> void:
	_status(text, true)
	if G.rejoining:
		G.rejoining = false
		G.call_deferred("end_client_session", text)


func _on_connected() -> void:
	if peer != null:
		Proto.set_timeouts(peer.get_peer(1))


func _on_failed() -> void:
	state = "idle"
	call_deferred("_close")
	_retry_at = _now() + RETRY_EVERY
	if reject_reason != "":
		return
	_status("Could not reach the server at %s:%d. Check the address, that the server is running, and port forwarding for internet play." % [host, port], true)


func _on_server_gone() -> void:
	var was := state
	state = "idle"
	# Tear the connection down after this signal has finished.
	call_deferred("_close")
	if reject_reason != "":
		_status(reject_reason, true)
		return
	if bye_reason != "":
		print("NET the server closed the connection: ", bye_reason)
		reconnecting = false
		G.call_deferred("end_client_session", bye_reason)
		return
	if was == "online" or reconnecting:
		if not reconnecting:
			reconnecting = true
			_lost_at = _now()
			print("NET lost the connection to %s:%d: nothing received for %.1f s, ping was %d ms; reconnecting" % [
				host, port, _now() - last_recv, _last_ping])
			if G.game != null and is_instance_valid(G.game):
				G.game.on_connection_lost()
		_retry_at = _now() + 1.0
		return
	if was == "waiting_welcome":
		G.call_deferred("end_client_session", "Lost the connection to the server.")
	else:
		_status("Lost the connection to the server.", true)


var _last_ping := 0
var _ping_t := 0.0


func _process(delta: float) -> void:
	var now := _now()
	if state == "connecting" and now > _deadline:
		_close()
		_retry_at = now + RETRY_EVERY
		_join_failed("No answer from %s:%d after %d seconds. Check the address and port forwarding." % [host, port, int(CONNECT_TIMEOUT)])
	if state == "online":
		_ping_t -= delta
		if _ping_t <= 0.0:
			_ping_t = 1.0
			_last_ping = ping_ms()
	if not my_backpacks.is_empty() and G.game != null and not G.game.clock_stopped:
		for e in my_backpacks:
			e[1] = maxf(0.0, float(e[1]) - delta)
	# Mobs the server stopped mentioning are gone (despawned, dead, or out of range).
	for id in mobs.keys():
		if now - float(mobs[id].get("seen", 0.0)) > 1.0:
			mobs.erase(id)
	if reconnecting and state == "idle" and now >= _retry_at:
		if now - _lost_at > RECONNECT_S:
			reconnecting = false
			print("NET gave up reconnecting after %d s" % int(RECONNECT_S))
			G.end_client_session("Lost the connection to the server, and it didn't come back within a minute.")
		else:
			print("NET reconnecting (%.0f s since the connection dropped)" % (now - _lost_at))
			_connect()


# ------------------------------------------------------------ game messages

func _on_packet(_id: int, data: PackedByteArray) -> void:
	if data.is_empty():
		return
	last_recv = _now()
	bytes_in[data[0]] = int(bytes_in.get(data[0], 0)) + data.size()
	var b := Proto.reader(data)
	match data[0]:
		Proto.S_WELCOME:
			var w := {}
			w["net_id"] = b.get_u16()
			w["seed"] = b.get_64()
			w["day"] = b.get_u16()
			w["time"] = b.get_float()
			w["horde"] = b.get_u8() == 1
			w["day_minutes"] = b.get_float()
			w["pos"] = Proto.get_vec3(b)
			w["yaw"] = b.get_float()
			w["spawn"] = Proto.get_vec3(b)
			w["admin"] = b.get_u8() == 1
			var n := b.get_u8()
			for i in n:
				var id := b.get_u16()
				others[id] = {"name": b.get_utf8_string(), "samples": []}
			my_net_id = w["net_id"]
			is_admin = w["admin"]
			state = "online"
			# A new session: the server subscribes us and sends the inventory from scratch.
			_guesses.clear()
			_inv_known = false
			my_backpacks.clear()
			bed = Vector3i.MIN
			if reconnecting:
				reconnecting = false
				print("NET reconnected after %.1f s" % (_now() - _lost_at))
				if G.mode == "client" and int(G.session.get("seed", -1)) == int(w["seed"]) and _world_ready():
					world_target.net_reset()
					G.resume_client_session(w)
					return
			print("NET joined %s:%d as %s" % [host, port, player_name])
			G.start_client_session(w)
		Proto.S_JOIN:
			var id := b.get_u16()
			others[id] = {"name": b.get_utf8_string(), "samples": []}
		Proto.S_LEAVE:
			others.erase(b.get_u16())
		Proto.S_SNAP:
			b.get_u32()
			var n := b.get_u8()
			var now := Time.get_ticks_msec() / 1000.0
			for i in n:
				var r := Proto.get_player_record(b)
				var o = others.get(r["id"])
				if o == null:
					o = {"name": "?", "samples": []}
					others[r["id"]] = o
				o["samples"].append([now, r["pos"], r["yaw"], r["pitch"], r["flags"]])
				o["held"] = r["held"]
				if o["samples"].size() > 16:
					o["samples"].pop_front()
		Proto.S_TIME:
			var day := b.get_u16()
			var t := b.get_float()
			var horde := b.get_u8() == 1
			var stopped := b.get_u8() == 1
			var g = G.game
			if g != null and G.mode == "client" and g.world != null:
				g.day = day
				g.time = t
				g.horde_active = horde
				g.was_night = g.is_night()
				g.clock_stopped = stopped
		Proto.S_CHAT:
			var from := b.get_utf8_string()
			chat.emit(from, b.get_utf8_string())
		Proto.S_NOTICE:
			var text := b.get_utf8_string()
			var col := Color8(b.get_u8(), b.get_u8(), b.get_u8())
			notice.emit(text, col)
		Proto.S_BYE:
			bye_reason = b.get_utf8_string()
		Proto.S_SUB, Proto.S_UNSUB, Proto.S_CHUNK, Proto.S_EDITS:
			if _world_ready():
				_on_world_packet(data)
			else:
				_world_queue.append(data)
		Proto.S_INV:
			_on_inventory(b)
		Proto.S_MSG:
			var text := b.get_utf8_string()
			var col := Color8(b.get_u8(), b.get_u8(), b.get_u8())
			if G.hud != null and is_instance_valid(G.hud):
				G.hud.msg(text, col)
		Proto.S_ATE:
			b.get_u16()
			if G.sfx != null:
				G.sfx.play("eat", -4.0)
		Proto.S_MOBS:
			b.get_u32()
			var origin := Proto.get_key(b)
			var now := _now()
			for i in b.get_u8():
				var r := Proto.get_mob(b, origin)
				var o = mobs.get(r["id"])
				if o == null or o["kind"] != r["kind"]:
					o = {"kind": r["kind"], "samples": []}
					mobs[r["id"]] = o
				o["seen"] = now
				var smp: Array = o["samples"]
				if smp.is_empty() or now > smp[smp.size() - 1][0]:
					smp.append([now, r["pos"], r["yaw"], 0.0, r["flags"]])
					if smp.size() > 16:
						smp.pop_front()
		Proto.S_STATS:
			var hp := b.get_u8()
			var food := b.get_u8()
			var dead := b.get_u8() == 1
			var kills := b.get_u16()
			if G.player != null and is_instance_valid(G.player) and G.mode == "client":
				G.player.apply_stats(hp, food, dead, kills)
		Proto.S_HURT:
			var amount := b.get_u8()
			var from := Proto.get_vec3(b)
			if G.player != null and is_instance_valid(G.player) and G.mode == "client":
				G.player.hurt_effect(amount, from)
		Proto.S_CRACKS:
			if _world_ready():
				for i in b.get_u16():
					var p := Proto.get_bpos(b)
					world_target.net_crack(p, b.get_u8())
		Proto.S_BACKPACKS:
			my_backpacks.clear()
			for i in b.get_u8():
				var p := Proto.get_bpos(b)
				my_backpacks.append([p, float(b.get_u16())])
		Proto.S_BED:
			var has := b.get_u8() == 1
			var bp := Proto.get_bpos(b)
			bed = bp if has else Vector3i.MIN
		Proto.S_CORRECT:
			move_id = b.get_u8()
			var pos := Proto.get_vec3(b)
			var p = G.player
			if p != null and is_instance_valid(p):
				p.global_position = pos
				p.velocity = Vector3.ZERO


func _physics_process(_delta: float) -> void:
	if state != "online":
		return
	_tick += 1
	if _tick % SEND_EVERY != 0:
		return
	var p = G.player
	var g = G.game
	if p == null or not is_instance_valid(p) or g == null or g.state == "loading":
		return
	var flags := 0
	if p.sprinting:
		flags |= Proto.F_SPRINT
	if p.flashlight.visible:
		flags |= Proto.F_FLASHLIGHT
	if p.dead:
		flags |= Proto.F_DEAD
	if not p.is_on_floor():
		flags |= Proto.F_AIRBORNE
	if p.swing > 0.05 or p.mine_progress > 0.0:
		flags |= Proto.F_SWING
	_seq = (_seq + 1) & 0xffff
	var m := Proto.writer(Proto.C_MOVE)
	m.put_u8(move_id)
	m.put_u16(_seq)
	Proto.put_vec3(m, p.global_position)
	m.put_u16(Proto.yaw_to_u16(p.head.rotation.y))
	m.put_16(clampi(int(p.cam.rotation.x * 10000.0), -32767, 32767))
	m.put_u8(flags)
	m.put_u8(p.selected)
	_send(m.data_array, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, Proto.CH_STATE)


func _send(data: PackedByteArray, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE, ch := Proto.CH_CONTROL) -> void:
	if mp == null or peer == null or not (state == "online" or state == "waiting_welcome"):
		return
	# ENet may have closed the connection already, before we hear about it.
	var sp := peer.get_peer(1)
	if sp != null and sp.get_state() == ENetPacketPeer.STATE_CONNECTED:
		mp.send_bytes(data, 1, mode, ch)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if peer != null:
			peer.close()
