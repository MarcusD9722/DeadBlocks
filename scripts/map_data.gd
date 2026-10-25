class_name MapData
extends Node
## The world map's picture (M4.4, client only; `G.game.map_data`). The server says which chunks
## we have explored (NetClient.explored); each one is painted as 16 x 16 pixels, one per block
## column: the top block's colour, shaded by the slope and the height. A chunk the world has
## blocks for is painted from them (so buildings show); one we have no blocks for (explored in an
## earlier session, far away) from the seed, as the terrain was generated. The painting runs on a
## worker thread; the pixels go into textures of REGION x REGION chunks that the map draws.

const REGION := 8
const REGION_PX := REGION * 16
## Chunks per worker task.
const BATCH := 24
## Seconds between repaints of chunks whose blocks changed.
const DIRTY_EVERY := 0.5

## Region key -> {"img": Image, "tex": ImageTexture or null, "dirty": bool}.
var regions := {}
## Chunk key -> 1 (painted from the seed) or 2 (from the world's blocks).
var painted := {}
var _todo := {}            # chunk keys to paint (from blocks if the world has them)
var _task := -1
var _task_in: Array = []   # [[key, block data or empty], ...]
var _task_out: Array = []  # [[key, 16x16 RGBA8 bytes], ...]
var _seed := 0
var _dirty_t := 0.0


func _ready() -> void:
	_seed = G.game.seed_v
	G.net.map_grew.connect(_on_grew)
	_on_grew(G.net.explored.keys())


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _on_grew(keys: Array) -> void:
	for k in keys:
		_todo[k] = true


func _process(delta: float) -> void:
	var w = G.world
	if w == null:
		return
	_dirty_t -= delta
	if _dirty_t <= 0.0:
		_dirty_t = DIRTY_EVERY
		# Chunks the world generated, received or changed: paint them from their blocks.
		for k in w.map_dirty:
			if G.net.explored.has(k):
				_todo[k] = true
		w.map_dirty.clear()
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		for i in _task_out.size():
			var k: Vector2i = _task_out[i][0]
			_put(k, _task_out[i][1])
			painted[k] = 2 if not (_task_in[i][1] as PackedByteArray).is_empty() else 1
	if _todo.is_empty():
		return
	# The chunks nearest to us first (walking reveals them there).
	var c := Vector2i(floori(G.player.global_position.x / 16.0), floori(G.player.global_position.z / 16.0))
	var keys: Array = _todo.keys()
	if keys.size() > BATCH:
		keys.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
	_task_in = []
	for k in keys:
		if _task_in.size() >= BATCH:
			break
		_todo.erase(k)
		var d: PackedByteArray = w.chunk_data(k)
		if d.is_empty() and painted.has(k):
			continue  # (painted already, from blocks or the seed: nothing better to do now)
		_task_in.append([k, d])
	if _task_in.is_empty():
		return
	_task_out = []
	_task = WorkerThreadPool.add_task(_paint_batch.bind(_task_in, _task_out, _seed), false, "map")


## Worker thread: each chunk's 16 x 16 pixels.
static func _paint_batch(list: Array, out: Array, seed_v: int) -> void:
	var gen: WorldGen = null
	for e in list:
		var tops: PackedByteArray = e[1]
		if (e[1] as PackedByteArray).is_empty():
			if gen == null:
				gen = WorldGen.new(seed_v)
			tops = seed_tops(gen, e[0])
		else:
			tops = block_tops(e[1])
		out.append([e[0], pixels(tops)])


func _put(k: Vector2i, px: PackedByteArray) -> void:
	var rk := Vector2i(floori(k.x / float(REGION)), floori(k.y / float(REGION)))
	var r = regions.get(rk)
	if r == null:
		var img := Image.create_empty(REGION_PX, REGION_PX, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		r = {"img": img, "tex": null, "dirty": true}
		regions[rk] = r
	var tile := Image.create_from_data(16, 16, false, Image.FORMAT_RGBA8, px)
	(r["img"] as Image).blit_rect(tile, Rect2i(0, 0, 16, 16), Vector2i(k.x - rk.x * REGION, k.y - rk.y * REGION) * 16)
	r["dirty"] = true


## The texture of a region (made or brought up to date when the map draws it).
func region_tex(rk: Vector2i) -> Texture2D:
	var r = regions.get(rk)
	if r == null:
		return null
	if r["tex"] == null:
		r["tex"] = ImageTexture.create_from_image(r["img"])
		r["dirty"] = false
	elif r["dirty"]:
		(r["tex"] as ImageTexture).update(r["img"])
		r["dirty"] = false
	return r["tex"]


# ------------------------------------------------------------ painting

## Each column's top block and its height, from a chunk's blocks: 256 x (id, y).
static func block_tops(d: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(512)
	for i in 256:
		var y := WorldGen.H - 1
		while y > 0 and d[i + y * 256] == Blocks.AIR:
			y -= 1
		out[i * 2] = d[i + y * 256]
		out[i * 2 + 1] = y
	return out


## The same from the seed alone (no blocks): the ground, berry bushes and tree tops.
static func seed_tops(gen: WorldGen, k: Vector2i) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(512)
	var bx := k.x * 16
	var bz := k.y * 16
	for z in 16:
		for x in 16:
			var wx := bx + x
			var wz := bz + z
			var h := gen.height_at(wx, wz)
			var bio := gen.biome_at(wx, wz)
			var i := x + z * 16
			out[i * 2] = Blocks.SAND if bio == 2 else Blocks.GRASS
			out[i * 2 + 1] = h
			if bio != 2 and gen.hash2(wx + 913, wz - 271) % 1000 < 9:
				out[i * 2] = Blocks.BERRY_BUSH
				out[i * 2 + 1] = h + 1
	# Trees (as world_gen.gd grows them): leaves over their top.
	for tz in range(bz - 2, bz + 18):
		for tx in range(bx - 2, bx + 18):
			if not gen.tree_at(tx, tz):
				continue
			var th := gen.height_at(tx, tz)
			if th > WorldGen.H - 14:
				continue
			var top := th + 4 + gen.hash2(tz, tx) % 3
			for lz in range(-2, 3):
				for lx in range(-2, 3):
					var x := tx + lx - bx
					var z := tz + lz - bz
					if x < 0 or x > 15 or z < 0 or z > 15 or (absi(lx) == 2 and absi(lz) == 2):
						continue
					var i := x + z * 16
					var y := top + (1 if absi(lx) <= 1 and absi(lz) <= 1 else -1)
					if y > out[i * 2 + 1]:
						out[i * 2] = Blocks.LEAVES
						out[i * 2 + 1] = y
	return out


## 16 x 16 RGBA8 pixels from the tops: the block's colour, lighter facing north-west and
## higher up, darker the other way.
static func pixels(tops: PackedByteArray) -> PackedByteArray:
	var px := PackedByteArray()
	px.resize(1024)
	for z in 16:
		for x in 16:
			var i := x + z * 16
			var h := int(tops[i * 2 + 1])
			var hw := int(tops[(i - 1 if x > 0 else i + 1) * 2 + 1])
			var hn := int(tops[(i - 16 if z > 0 else i + 16) * 2 + 1])
			if x == 0:
				hw = 2 * h - hw  # (mirrored at the chunk's edge)
			if z == 0:
				hn = 2 * h - hn
			var shade := 1.0 + clampf(((h - hw) + (h - hn)) * 0.07, -0.3, 0.3)
			shade *= 0.8 + clampf((h - 18) / 30.0, 0.0, 1.0) * 0.35
			var c := color_of(tops[i * 2]) * shade
			px[i * 4] = clampi(int(c.r * 255.0), 0, 255)
			px[i * 4 + 1] = clampi(int(c.g * 255.0), 0, 255)
			px[i * 4 + 2] = clampi(int(c.b * 255.0), 0, 255)
			px[i * 4 + 3] = 255
	return px


static func color_of(id: int) -> Color:
	match id:
		Blocks.GRASS:
			return Color(0.38, 0.55, 0.26)
		Blocks.DIRT:
			return Color(0.48, 0.37, 0.25)
		Blocks.SAND:
			return Color(0.84, 0.77, 0.53)
		Blocks.STONE, Blocks.COBBLE, Blocks.COAL_ORE, Blocks.IRON_ORE, Blocks.BEDROCK:
			return Color(0.52, 0.52, 0.5)
		Blocks.LOG:
			return Color(0.42, 0.3, 0.17)
		Blocks.LEAVES:
			return Color(0.2, 0.38, 0.16)
		Blocks.BERRY_BUSH:
			return Color(0.42, 0.24, 0.32)
		Blocks.TORCH, Blocks.CAMPFIRE:
			return Color(1.0, 0.75, 0.35)
		Blocks.BED:
			return Color(0.75, 0.25, 0.22)
		Blocks.STONE_BRICK, Blocks.FORGE:
			return Color(0.62, 0.6, 0.58)
		Blocks.REINFORCED:
			return Color(0.5, 0.5, 0.55)
		Blocks.BLOOD_FORGE, Blocks.BLOOD_BRICK:
			return Color(0.55, 0.14, 0.12)
	# Built blocks: wood brown, iron and steel grey-blue, Blood-forged red (by their tier).
	var tier := Blocks.TIER_BLOCKS.find(id)
	for base in [Blocks.FRAME_HALF, Blocks.FRAME_RAMP, Blocks.FRAME_PILLAR]:
		if id >= base and id < base + 6:
			tier = id - base
	match id:
		Blocks.WOOD_DOOR, Blocks.WOOD_DOOR_OPEN, Blocks.WOOD_HATCH, Blocks.WOOD_HATCH_OPEN, Blocks.WOOD_BOX:
			tier = 1
		Blocks.IRON_DOOR, Blocks.IRON_DOOR_OPEN, Blocks.IRON_HATCH, Blocks.IRON_HATCH_OPEN, Blocks.IRON_BOX, \
				Blocks.STEEL_DOOR, Blocks.STEEL_DOOR_OPEN, Blocks.STEEL_HATCH, Blocks.STEEL_HATCH_OPEN:
			tier = 3
	match tier:
		0, 1, 2:
			return Color(0.66, 0.48, 0.28)
		3, 4:
			return Color(0.56, 0.6, 0.65)
		5:
			return Color(0.55, 0.14, 0.12)
	return Color(0.64, 0.5, 0.36)
