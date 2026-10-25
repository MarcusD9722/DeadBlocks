class_name Proto
extends RefCounted
## The network protocol: message ids, binary layouts and the hashing used to log in.
## Every message is one type byte followed by little-endian fields (StreamPeerBuffer).
## Bump PROTOCOL whenever a layout changes; client and server must match exactly.

const PROTOCOL := 13
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
# World sync (see "Chunk subscriptions" below)
const S_SUB := 19        # seq u32, fresh count u16 + keys, wait count u16 + keys
const S_UNSUB := 20      # count u16 + keys
const S_CHUNK := 21      # (bulk channel) seq u32, key, size u32, zstd(16 KB block array), block states (see put_states)
const S_EDITS := 22      # seq u32, chunk count u16, per chunk: key, count u16, count x (index u16, block u8, state u8)
const S_INV := 23        # ack u16 (last request seq handled), 36 x (item u16, count u8)
const S_MSG := 24        # text, colour rgb u8 x3: a message in the middle of the screen
const S_ATE := 25        # item u16: the server took the food (plays the eating sound)
const S_MOBS := 26       # (unreliable) tick u32, origin key, count u8, count x mob record (see put_mob)
const S_STATS := 27      # health u8, max health u8, food u8, dead u8, kills u16: the server owns these
const S_HURT := 28       # amount u8, from 3xf32 (all 0 = no knockback): flash, sound, knockback
const S_CRACKS := 29     # count u16, count x (block pos, stage u8): zombies chipping at blocks
const S_BACKPACKS := 42  # count u8, count x (block pos, seconds left u16): your own backpacks
const S_BED := 43        # has u8, block pos: your bed (the death screen offers it)
const S_BOX := 44        # block pos, open u8 (0: closed, it's gone or out of reach), title, count u8,
                         # count x (item u16, count u8): a storage box or bag you have open (M4.2)
# M4.3: things lying in the world (a thrown spear, an arrow that missed), and hits you made.
const S_GROUND := 50     # count u16, count x ground record (see put_ground): new ones (all of them on joining)
const S_GROUND_GONE := 51  # count u16, count x id u16: picked up or fallen apart
const S_HIT := 52        # kind u8 (HIT_*): your arrow, bolt or spear hit something
# M4.4: your map, your pins, allies and tribes.
const S_MAP := 55        # count u16 + keys: chunks you have explored (all of them on joining, then new ones)
const S_PINS := 56       # count u8, count x (x s32, z s32, name): your map pins
const S_SOCIAL := 58     # players u8 x (name, net id u16 (0 offline), ping u16, rel u8 (R_*)),
                         # tribe u8 (0 none, 1: id u32, name, leader name),
                         # invites u8 x (tribe id u32, tribe name, from name)
# M4.5: experience and perks, and the armor you wear.
const S_PROGRESS := 60   # experience u32 (in all), count u8 x (perk id u8, rank u8)
const S_ARMOR := 61      # 4 x item u16: head, chest, legs, feet (0 = none)
# M4.6: a natural tree was felled (its blocks go as edits); everyone near sees it fall.
const S_TREE := 64       # block pos (the trunk's lowest log), fall direction u16 (yaw, 0-65535 = 0-2 pi)
# Client -> server
const C_MOVE := 30       # move id u8, seq u16, pos 3xf32, yaw u16, pitch s16, flags u8, hotbar slot u8
const C_READY := 31      # my chunks are loaded, count me as online
const C_CHAT := 32       # text (a leading "/" is a command)
# Requests the server checks. Each carries a seq u16; S_INV acknowledges the latest one handled.
const C_BREAK := 33      # seq, block pos, block id the client sees u8, hotbar slot u8 (the tool)
const C_PLACE := 34      # seq, block pos, block id u8, slot u8, block state u8 (facing, upper half)
const C_SWAP := 35       # seq, slot a u8, slot b u8
const C_CRAFT := 36      # seq, recipe index u8, times u8
const C_EAT := 37        # seq, slot u8
const C_ATTACK := 38     # seq, mob id u16, slot u8 (the weapon)
const C_FALL := 39       # damage u8 from a fall (movement is the client's)
const C_RESPAWN := 40    # where u8 (0 = at your bed, 1 = somewhere random, 2 = at a tribe member's bed), name (2: whose), after dying
const C_PAUSE := 41      # paused u8: the pause menu is open (a solo game's server stops its world)
# M4.2 (requests with a seq, like the ones above)
const C_USE := 45        # seq, block pos: open or close a door or hatch (E)
const C_UPGRADE := 46    # seq, block pos, slot u8 (the hammer): repair it, or upgrade it to the next tier
const C_OPEN := 47       # seq, block pos: open a storage box or bag (E); S_BOX answers
const C_BOX := 48        # seq, action u8 (0 take a box slot, 1 put an inventory slot in, 2 take everything), slot u8
const C_CLOSE := 49      # the box screen was closed
# M4.3
const C_SHOOT := 53      # seq, slot u8 (bow, crossbow or spear), power u8 (0-255), aim 3xf32
const C_PICKUP := 54     # seq, ground id u16 (E on a spear or arrow lying in the world)
# M4.4
const C_PIN := 57        # action u8 (0 add: x s32, z s32, name; 1 remove: index u8)
const C_SOCIAL := 59     # action u8 (SOC_*), name (a player), text (a tribe name, or a tribe id)
# M4.5
const C_PERK := 62       # perk id u8: spend a skill point on its next rank
const C_EQUIP := 63      # seq, action u8 (0 wear the armor in inventory slot, 1 take off armor slot), slot u8
const HIT_MOB := 1
const HIT_HEAD := 2
const HIT_KILL := 3
## C_SOCIAL actions (M4.4). Allies: ask, accept, decline, remove. Tribes: found (text = name),
## invite, join or refuse an invitation (text = tribe id), leave, kick, hand over the lead,
## rename (text); refresh asks for an S_SOCIAL (pings).
const SOC_ASK := 1
const SOC_ACCEPT := 2
const SOC_DECLINE := 3
const SOC_REMOVE := 4
const SOC_FOUND := 5
const SOC_INVITE := 6
const SOC_JOIN := 7
const SOC_REFUSE := 8
const SOC_LEAVE := 9
const SOC_KICK := 10
const SOC_LEAD := 11
const SOC_RENAME := 12
const SOC_REFRESH := 13
## S_SOCIAL relations (bits): an ally, in your tribe, you asked them, they asked you, online,
## away (their character stayed after they left), in a tribe (any), has a bed (a tribe member's
## bed you can respawn at).
const R_ALLY := 1
const R_TRIBE := 2
const R_ASKED := 4
const R_ASKS_YOU := 8
const R_ONLINE := 16
const R_AWAY := 32
const R_IN_TRIBE := 64
const R_BED := 128
const MAX_PINS := 50
## Map (M4.4): chunks within this many of a player's chunk count as explored.
const REVEAL_RADIUS := 5.5

# Player record flags
const F_SPRINT := 1
const F_FLASHLIGHT := 2
const F_DEAD := 4
const F_AIRBORNE := 8
const F_SWING := 16      # mining or hitting: other players see the arm swing
const F_AWAY := 32       # logged out: the character stays in the world for a while (M2)

## A few fixed chunks whose block data both sides hash at login: a different build that would
## generate different terrain (and so a different world) is refused with a clear message.
const TERRAIN_CHUNKS := [Vector2i(0, 0), Vector2i(1, -1), Vector2i(-2, 3), Vector2i(37, -91)]

const MAX_CHAT := 200

## Chunk subscriptions: the server tells each client which chunks around it are untouched
## (S_SUB "fresh": generate them from the seed) and which were edited ("wait": a copy follows
## as S_CHUNK). From then on it sends that client every edit to those chunks (S_EDITS). Edit
## batches are numbered; a chunk copy or subscription says which batch it already includes,
## so an edit can never be applied twice or on top of newer data.
const SUB_RADIUS := 9      # chunks around the player the server subscribes
const UNSUB_RADIUS := 11   # ...and unsubscribes beyond this
const CHUNK_BYTES := 16384 # 16 x 16 x 64 blocks
## Reach the server allows for breaking and placing (the player's is 5 m; slack for lag).
const REACH := 6.5
const MOB_REACH := 4.7     # hitting a mob (the player's is 3.2 m)
## Mobs within this distance of a player are in its S_MOBS.
const MOB_RANGE := 96.0
const MOBS_PER_PACKET := 100

# Mob kinds and flags in S_MOBS
const MOB_ZOMBIE := 0
const MOB_NIGHT := 1
const MOB_HORDE := 2
const MOB_BOAR := 3
## The M3 zombie types (walkers use MOB_ZOMBIE / NIGHT / HORDE), and a Spitter's acid glob.
const MOB_RUNNER := 4
const MOB_BRUTE := 5
const MOB_CRAWLER := 6
const MOB_SCREAMER := 7
const MOB_SPITTER := 8
const MOB_ACID := 9
## M4.3: an arrow, bolt or spear in flight. Its flags: the type (Items.PROJECTILES index) in bits
## 0-5, and MF_YOURS when the player receiving it shot it (their game already shows its own).
const MOB_PROJ := 10
const MF_YOURS := 128
const ZOMBIE_KINDS := {"runner": MOB_RUNNER, "brute": MOB_BRUTE, "crawler": MOB_CRAWLER, "screamer": MOB_SCREAMER, "spitter": MOB_SPITTER}
const KIND_TYPES := {MOB_RUNNER: "runner", MOB_BRUTE: "brute", MOB_CRAWLER: "crawler", MOB_SCREAMER: "screamer", MOB_SPITTER: "spitter"}
const MF_HURT := 1
const MF_ATTACK := 2
const MF_DEAD := 4
const MF_BLOOD := 8       # a Blood Moon zombie (red eyes, hunts everyone)
const MF_SCREAM := 16     # a Screamer screaming

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


## A tribe's name (M4.4): 3-24 letters, digits, spaces, _ - ' (not starting or ending with a space).
static func valid_tribe_name(n: String) -> bool:
	var re := RegEx.create_from_string("^[A-Za-z0-9_'-][A-Za-z0-9 _'-]{1,22}[A-Za-z0-9_'-]$")
	return re.search(n) != null and not n.contains("  ")


## A map pin's name: printable, at most 24 characters.
static func clean_pin_name(n: String) -> String:
	var out := ""
	for ch in n.strip_edges():
		if ch.unicode_at(0) >= 32:
			out += ch
	return out.left(24).strip_edges()

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


static func put_key(b: StreamPeerBuffer, k: Vector2i) -> void:
	b.put_32(k.x)
	b.put_32(k.y)


static func get_key(b: StreamPeerBuffer) -> Vector2i:
	var x := b.get_32()
	return Vector2i(x, b.get_32())


static func put_keys(b: StreamPeerBuffer, keys: Array) -> void:
	b.put_u16(keys.size())
	for k in keys:
		put_key(b, k)


static func get_keys(b: StreamPeerBuffer) -> Array:
	var out := []
	for i in b.get_u16():
		out.append(get_key(b))
	return out


## A block position: x s32, y u8, z s32.
static func put_bpos(b: StreamPeerBuffer, p: Vector3i) -> void:
	b.put_32(p.x)
	b.put_u8(clampi(p.y, 0, 255))
	b.put_32(p.z)


static func get_bpos(b: StreamPeerBuffer) -> Vector3i:
	var x := b.get_32()
	var y := b.get_u8()
	return Vector3i(x, y, b.get_32())


## 36 slots of (item u16, count u8); empty slots are (0, 0).
static func put_inventory(b: StreamPeerBuffer, slots: Array) -> void:
	for s in slots:
		if s == null:
			b.put_u16(0)
			b.put_u8(0)
		else:
			b.put_u16(int(s["id"]))
			b.put_u8(int(s["n"]))


static func get_inventory(b: StreamPeerBuffer) -> Array:
	var out := []
	for i in Inventory.SIZE:
		var id := b.get_u16()
		var n := b.get_u8()
		out.append(null if id == 0 or n == 0 else {"id": id, "n": n})
	return out


## Block states (M4.2): count u16, count x (index u16, state u8).
static func put_states(b: StreamPeerBuffer, meta: Dictionary) -> void:
	b.put_u16(meta.size())
	for i in meta:
		b.put_u16(int(i))
		b.put_u8(int(meta[i]))


static func get_states(b: StreamPeerBuffer) -> Dictionary:
	var meta := {}
	for i in b.get_u16():
		var idx := b.get_u16()
		meta[idx] = b.get_u8()
	return meta


## Block states as plain bytes, (index u16, state u8) each in index order (save files, hashes).
static func meta_bytes(meta: Dictionary) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	var keys := meta.keys()
	keys.sort()
	for i in keys:
		b.put_u16(int(i))
		b.put_u8(int(meta[i]))
	return b.data_array


static func pack_chunk(data: PackedByteArray) -> PackedByteArray:
	return data.compress(FileAccess.COMPRESSION_ZSTD)


static func unpack_chunk(packed: PackedByteArray) -> PackedByteArray:
	return packed.decompress(CHUNK_BYTES, FileAccess.COMPRESSION_ZSTD)


## True if 16-bit sequence number a is the same as or older than b (wraps around).
static func seq_le(a: int, b: int) -> bool:
	return ((b - a) & 0xffff) < 0x8000


## 11 bytes: id u16, kind u8, x s16 and z s16 (1/32 m from the origin chunk's corner),
## y u16 (1/64 m), yaw u8, flags u8.
static func put_mob(b: StreamPeerBuffer, origin: Vector2i, id: int, kind: int, pos: Vector3, yaw: float, flags: int) -> void:
	b.put_u16(id & 0xffff)
	b.put_u8(kind)
	b.put_16(clampi(roundi((pos.x - origin.x * 16) * 32.0), -32767, 32767))
	b.put_u16(clampi(roundi(pos.y * 64.0), 0, 65535))
	b.put_16(clampi(roundi((pos.z - origin.y * 16) * 32.0), -32767, 32767))
	b.put_u8(int(fposmod(yaw, TAU) / TAU * 256.0) & 0xff)
	b.put_u8(flags)


static func get_mob(b: StreamPeerBuffer, origin: Vector2i) -> Dictionary:
	var id := b.get_u16()
	var kind := b.get_u8()
	var x := b.get_16() / 32.0 + origin.x * 16
	var y := b.get_u16() / 64.0
	var z := b.get_16() / 32.0 + origin.y * 16
	var yaw := b.get_u8() / 256.0 * TAU
	return {"id": id, "kind": kind, "pos": Vector3(x, y, z), "yaw": yaw, "flags": b.get_u8()}


## Something lying in the world (M4.3): id u16, item u16, position 3xf32, yaw u16, pitch s16.
static func put_ground(b: StreamPeerBuffer, id: int, item: int, pos: Vector3, yaw: float, pitch: float) -> void:
	b.put_u16(id)
	b.put_u16(item)
	put_vec3(b, pos)
	b.put_u16(yaw_to_u16(yaw))
	b.put_16(clampi(int(pitch * 10000.0), -32767, 32767))


static func get_ground(b: StreamPeerBuffer) -> Dictionary:
	var id := b.get_u16()
	var item := b.get_u16()
	var pos := get_vec3(b)
	var yaw := u16_to_yaw(b.get_u16())
	return {"id": id, "item": item, "pos": pos, "yaw": yaw, "pitch": b.get_16() / 10000.0}


## 19 bytes: net id u16, position 3xf32, yaw u16, pitch s16, flags u8.
static func put_player_record(b: StreamPeerBuffer, net_id: int, pos: Vector3, yaw: float, pitch: float, flags: int, held := 0, armor := 0) -> void:
	b.put_u16(net_id)
	put_vec3(b, pos)
	b.put_u16(yaw_to_u16(yaw))
	b.put_16(clampi(int(pitch * 10000.0), -32767, 32767))
	b.put_u8(flags)
	b.put_u8(held)  # the item in their hand (from the server's copy of their inventory)
	b.put_u16(armor)  # what they wear (M4.5, armor_bits)


## The armor worn (4 item ids) as 3 bits per slot: its tier + 1, 0 for none.
static func armor_bits(worn: Array) -> int:
	var bits := 0
	for i in 4:
		var t := Items.armor_tier(int(worn[i])) if i < worn.size() else -1
		bits |= (t + 1) << (i * 3)
	return bits


## The tier worn in each slot (-1 for none) from armor_bits.
static func armor_tiers(bits: int) -> Array:
	var out := []
	for i in 4:
		out.append(((bits >> (i * 3)) & 7) - 1)
	return out


static func get_player_record(b: StreamPeerBuffer) -> Dictionary:
	var id := b.get_u16()
	var pos := get_vec3(b)
	var yaw := u16_to_yaw(b.get_u16())
	var pitch := b.get_16() / 10000.0
	var flags := b.get_u8()
	var held := b.get_u8()
	return {"id": id, "pos": pos, "yaw": yaw, "pitch": pitch, "flags": flags, "held": held, "armor": b.get_u16()}


static func _sha(s: String) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(s.to_utf8_buffer())
	return ctx.finish()
