extends Node
## Dedicated-server networking (started by game.gd in server mode).
## Listens on UDP, logs players in (server password + name + PIN, proven with HMACs so neither
## crosses the network), keeps one ServerPlayer per player, sends everyone the others' movement
## 15 times a second, keeps clocks in sync, and runs chat and admin commands.
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
## Accounts by lower-case name: {name, pin_key, fails, locked_until, pos, yaw}. Kept in memory
## for now; M1.5 saves them.
var accounts := {}
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
	if acc != null:
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
	if acc == null:
		# First join with this name: unmask the PIN key and check it matches the proof.
		var pk := Proto.xor_bytes(pin_reg, Proto.hmac(password_key, nonce + "reg".to_utf8_buffer()))
		if pin_proof != Proto.hmac(pk, nonce):
			_reject(id, "Could not register that name. Please try again.")
			return
		acc = {"name": pname, "pin_key": pk, "fails": 0, "locked_until": 0.0, "pos": G.game.spawn_pos, "yaw": 0.0}
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
	sp.global_position = acc["pos"]
	sp.yaw = acc["yaw"]
	sp.last_good = acc["pos"]
	sp.last_move_ms = Time.get_ticks_msec()
	sp.last_recv_ms = Time.get_ticks_msec()
	players[id] = sp
	G.sim.add_player(sp)
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
	var acc = accounts.get(sp.player_name.to_lower())
	if acc != null:
		acc["pos"] = sp.last_good
		acc["yaw"] = sp.yaw
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
	if online_count() == 0:
		print("SERVER nobody online: time paused at day %d %s" % [G.game.day, _clock()])


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
				_send_to(id, _time_bytes())
				if online_count() == 1:
					print("SERVER %s is online: time running again" % sp.player_name)
		Proto.C_CHAT:
			_on_chat(sp, b.get_utf8_string().strip_edges().left(Proto.MAX_CHAT))


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
	if d > MOVE_SPEED_LIMIT * dt + MOVE_SLACK or not pos.is_finite():
		correct(sp, sp.last_good)
		return
	sp.last_good = pos
	sp.last_move_ms = now
	sp.global_position = pos
	sp.yaw = yaw
	sp.pitch = pitch
	sp.flags = flags
	sp.dead = (flags & Proto.F_DEAD) != 0


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
		_:
			_send_to(sp.peer_id, _notice_bytes("Commands: /players /dusk /bloodmoon /time <hour> /kick <name>", Color(0.8, 0.9, 1)))
			return
	print("SERVER %s used %s" % [sp.player_name, text])
	_broadcast(_time_bytes())
	_send_to(sp.peer_id, _notice_bytes("Done: " + text, Color(0.8, 0.9, 1)))


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
		mp.send_bytes(data, id, mode, ch)


func _broadcast(data: PackedByteArray, except := 0) -> void:
	for id in players:
		if id != except:
			mp.send_bytes(data, id, MultiplayerPeer.TRANSFER_MODE_RELIABLE, Proto.CH_CONTROL)


func _clock() -> String:
	var t: float = G.game.time
	return "%02d:%02d" % [int(t), int((t - int(t)) * 60.0)]


# ------------------------------------------------------------ per tick

func _physics_process(_delta: float) -> void:
	_tick += 1
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
	for to in ready_players:
		var s := Proto.writer(Proto.S_SNAP)
		s.put_u32(_tick)
		s.put_u8(ready_players.size() - 1)
		for p in ready_players:
			if p != to:
				Proto.put_player_record(s, p.net_id, p.global_position, p.yaw, p.pitch, p.flags)
		mp.send_bytes(s.data_array, to.peer_id, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, Proto.CH_STATE)


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
				mp.send_bytes(t, p.peer_id, MultiplayerPeer.TRANSFER_MODE_RELIABLE, Proto.CH_CONTROL)
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
			print("SERVER the host (%s) is gone; stopping" % hosted_by)
			get_tree().quit()


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
