class_name Proto
extends RefCounted
## The network protocol: message ids, binary layouts and the hashing used to log in.
## Every message is one type byte followed by little-endian fields (StreamPeerBuffer).
## Bump PROTOCOL whenever a layout changes; client and server must match exactly.

const PROTOCOL := 2
const DEFAULT_PORT := 24650
const MAX_PLAYERS := 8
## ENet channels: 0 reliable control messages, 1 unreliable snapshots and movement,
## 2 reliable bulk data (saved chunks, from M1.3), so big transfers never delay control messages.
const CH_CONTROL := 0
const CH_STATE := 1
const CH_BULK := 2
const CHANNELS := 3

# Login, exchanged inside SceneMultiplayer's authentication step.
const A_CHALLENGE := 1   # S->C: protocol u16, game version, nonce[16], seed s64, worldgen version u16
const A_HELLO := 2       # C->S: protocol u16, game version, name, pw_proof[32], pin_proof[32], pin_reg[32], terrain[32]
const A_RESULT := 3      # S->C: ok u8, reason
# Server -> client
const S_WELCOME := 10    # your net id u16, seed s64, day u16, time f32, horde u8, day_minutes f32,
                         # pos 3xf32, yaw f32, spawn 3xf32, admin u8, players u8 x (net id u16, name)
const S_JOIN := 11       # net id u16, name
const S_LEAVE := 12      # net id u16
const S_SNAP := 13       # tick u32, count u8, count x player record (see put_player_record)
const S_TIME := 14       # day u16, time f32, horde u8, paused u8
const S_CHAT := 15       # from name, text
const S_NOTICE := 16     # text, colour rgb u8 x3
const S_CORRECT := 17    # move id u8, pos 3xf32: the server moved you (teleport or a rejected move)
const S_BYE := 18        # reason: the server is about to close this connection (kick, signed in elsewhere)
# Client -> server
const C_MOVE := 30       # move id u8, seq u16, pos 3xf32, yaw u16, pitch s16, flags u8
const C_READY := 31      # my chunks are loaded, count me as online
const C_CHAT := 32       # text (a leading "/" is a command)

# Player record flags
const F_SPRINT := 1
const F_FLASHLIGHT := 2
const F_DEAD := 4
const F_AIRBORNE := 8

## A few fixed chunks whose block data both sides hash at login: a different build that would
## generate different terrain (and so a different world) is refused with a clear message.
const TERRAIN_CHUNKS := [Vector2i(0, 0), Vector2i(1, -1), Vector2i(-2, 3), Vector2i(37, -91)]

const MAX_CHAT := 200

## ENet gives up on a connection after this much silence (ms): at least TIMEOUT_MIN_MS, at most
## TIMEOUT_MAX_MS. Generous, so a Wi-Fi hiccup doesn't drop anyone (Minecraft waits 30 s too).
const TIMEOUT_MIN_MS := 15000
const TIMEOUT_MAX_MS := 30000


static func set_timeouts(p: ENetPacketPeer) -> void:
	if p != null:
		p.set_timeout(32, TIMEOUT_MIN_MS, TIMEOUT_MAX_MS)


static func password_key(password: String) -> PackedByteArray:
	return _sha("deadblocks-password|" + password)


static func pin_key(player_name: String, pin: String) -> PackedByteArray:
	return _sha("deadblocks-pin|" + player_name.to_lower() + "|" + pin)


static func hmac(key: PackedByteArray, msg: PackedByteArray) -> PackedByteArray:
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key, msg)


static func xor_bytes(a: PackedByteArray, b: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(a.size())
	for i in a.size():
		out[i] = a[i] ^ b[i % b.size()]
	return out


static func terrain_hash(seed_v: int) -> PackedByteArray:
	var g := WorldGen.new(seed_v)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for c in TERRAIN_CHUNKS:
		ctx.update(g.generate(c.x, c.y))
	return ctx.finish()


static func valid_name(n: String) -> bool:
	var re := RegEx.create_from_string("^[A-Za-z0-9_]{3,16}$")
	return re.search(n) != null


static func valid_pin(p: String) -> bool:
	var re := RegEx.create_from_string("^[0-9]{4,8}$")
	return re.search(p) != null


static func writer(type: int) -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.put_u8(type)
	return b


static func reader(data: PackedByteArray) -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	b.seek(1)
	return b


static func put_vec3(b: StreamPeerBuffer, v: Vector3) -> void:
	b.put_float(v.x)
	b.put_float(v.y)
	b.put_float(v.z)


static func get_vec3(b: StreamPeerBuffer) -> Vector3:
	var x := b.get_float()
	var y := b.get_float()
	var z := b.get_float()
	return Vector3(x, y, z)


static func put_bytes32(b: StreamPeerBuffer, data: PackedByteArray) -> void:
	var d := data.duplicate()
	d.resize(32)
	b.put_data(d)


static func get_bytes32(b: StreamPeerBuffer) -> PackedByteArray:
	var r: Array = b.get_data(32)
	if r[0] != OK:
		return PackedByteArray()
	return r[1]


static func yaw_to_u16(yaw: float) -> int:
	return int(fposmod(yaw, TAU) / TAU * 65535.0) & 0xffff


static func u16_to_yaw(v: int) -> float:
	return v / 65535.0 * TAU


## 19 bytes: net id u16, position 3xf32, yaw u16, pitch s16, flags u8.
static func put_player_record(b: StreamPeerBuffer, net_id: int, pos: Vector3, yaw: float, pitch: float, flags: int) -> void:
	b.put_u16(net_id)
	put_vec3(b, pos)
	b.put_u16(yaw_to_u16(yaw))
	b.put_16(clampi(int(pitch * 10000.0), -32767, 32767))
	b.put_u8(flags)


static func get_player_record(b: StreamPeerBuffer) -> Dictionary:
	var id := b.get_u16()
	var pos := get_vec3(b)
	var yaw := u16_to_yaw(b.get_u16())
	var pitch := b.get_16() / 10000.0
	var flags := b.get_u8()
	return {"id": id, "pos": pos, "yaw": yaw, "pitch": pitch, "flags": flags}


static func _sha(s: String) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(s.to_utf8_buffer())
	return ctx.finish()
