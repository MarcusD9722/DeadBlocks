extends Node
## Client networking. Lives under the G autoload, so the connection survives the scene reload
## that swaps the solo world for the server's world (G.start_client_session).
## Sends our movement 15 times a second and keeps a short history of everyone else's, which
## RemotePlayer nodes draw 100 ms in the past so movement looks smooth.

signal status(text: String, is_error: bool)
signal chat(from: String, text: String)
signal notice(text: String, col: Color)

const SEND_EVERY := 4          # physics ticks per movement update: 60 / 4 = 15 Hz
const INTERP_DELAY := 0.1      # seconds remote players are drawn in the past
const CONNECT_TIMEOUT := 12.0

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
var last_notice := ""
var my_net_id := 0
var is_admin := false
## net id -> {"name": String, "samples": Array of [time s, pos, yaw, pitch, flags]}
var others := {}
var move_id := 0
var _seq := 0
var _tick := 0
var _deadline := 0.0


func join(h: String, p: int, pname: String, pin_k: PackedByteArray, pw_k: PackedByteArray) -> void:
	leave()
	host = h
	port = p
	player_name = pname
	pin_key = pin_k
	password_key = pw_k
	reject_reason = ""
	last_notice = ""
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
	var err := peer.create_client(h, p, Proto.CHANNELS)
	if err != OK:
		state = "idle"
		status.emit("Could not start connecting to %s (error %d)." % [h, err], true)
		return
	mp.multiplayer_peer = peer
	state = "connecting"
	_deadline = Time.get_ticks_msec() / 1000.0 + CONNECT_TIMEOUT
	status.emit("Connecting to %s:%d..." % [h, p], false)


func leave() -> void:
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


func send_ready() -> void:
	_send(Proto.writer(Proto.C_READY).data_array)


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
			b.get_u16()
			b.get_utf8_string()
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
			status.emit("Logging in...", false)
		Proto.A_RESULT:
			var ok := b.get_u8()
			var reason := b.get_utf8_string()
			if ok == 1:
				mp.complete_auth(1)
				state = "waiting_welcome"
				status.emit("Joining...", false)
			else:
				reject_reason = reason
				state = "idle"
				call_deferred("leave")
				status.emit(reason, true)


func _on_connected() -> void:
	var sp := peer.get_peer(1) if peer != null else null
	if sp != null:
		sp.set_timeout(32, 5000, 15000)


func _on_failed() -> void:
	state = "idle"
	call_deferred("leave")
	if reject_reason != "":
		return
	status.emit("Could not reach the server at %s:%d. Check the address, that the server is running, and port forwarding for internet play." % [host, port], true)


func _on_server_gone() -> void:
	var was := state
	state = "idle"
	# Tear the connection down after this signal has finished.
	call_deferred("leave")
	if reject_reason != "":
		status.emit(reject_reason, true)
		return
	var why := last_notice if last_notice != "" else "Lost the connection to the server."
	if was == "online" or was == "waiting_welcome":
		G.end_client_session(why)
	else:
		status.emit(why, true)


func _process(_delta: float) -> void:
	if state == "connecting" and Time.get_ticks_msec() / 1000.0 > _deadline:
		leave()
		status.emit("No answer from %s:%d after %d seconds. Check the address and port forwarding." % [host, port, int(CONNECT_TIMEOUT)], true)


# ------------------------------------------------------------ game messages

func _on_packet(_id: int, data: PackedByteArray) -> void:
	if data.is_empty():
		return
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
				if o["samples"].size() > 16:
					o["samples"].pop_front()
		Proto.S_TIME:
			var day := b.get_u16()
			var t := b.get_float()
			var horde := b.get_u8() == 1
			var g = G.game
			if g != null and G.mode == "client" and g.world != null:
				g.day = day
				g.time = t
				g.horde_active = horde
				g.was_night = g.is_night()
		Proto.S_CHAT:
			var from := b.get_utf8_string()
			chat.emit(from, b.get_utf8_string())
		Proto.S_NOTICE:
			var text := b.get_utf8_string()
			var col := Color8(b.get_u8(), b.get_u8(), b.get_u8())
			last_notice = text
			notice.emit(text, col)
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
	_seq = (_seq + 1) & 0xffff
	var m := Proto.writer(Proto.C_MOVE)
	m.put_u8(move_id)
	m.put_u16(_seq)
	Proto.put_vec3(m, p.global_position)
	m.put_u16(Proto.yaw_to_u16(p.head.rotation.y))
	m.put_16(clampi(int(p.cam.rotation.x * 10000.0), -32767, 32767))
	m.put_u8(flags)
	_send(m.data_array, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, Proto.CH_STATE)


func _send(data: PackedByteArray, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE, ch := Proto.CH_CONTROL) -> void:
	if mp != null and peer != null and (state == "online" or state == "waiting_welcome"):
		mp.send_bytes(data, 1, mode, ch)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if peer != null:
			peer.close()
