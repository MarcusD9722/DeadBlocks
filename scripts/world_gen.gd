class_name WorldGen
extends RefCounted
## Deterministic terrain: hills, forests, deserts, caves, ores, trees, berry bushes.
## Safe to use from worker threads (each task makes its own instance).

const CH := 16
const H := 64
## Bump whenever generation changes: clients and servers must build the same terrain.
const VERSION := 1

var seed_v := 0
var n_height := FastNoiseLite.new()
var n_hill := FastNoiseLite.new()
var n_biome := FastNoiseLite.new()
var n_cave1 := FastNoiseLite.new()
var n_cave2 := FastNoiseLite.new()
var n_ore := FastNoiseLite.new()


func _init(s: int) -> void:
	seed_v = s
	n_height.seed = s
	n_height.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_height.frequency = 0.009
	n_height.fractal_octaves = 4
	n_hill.seed = s + 11
	n_hill.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_hill.frequency = 0.0035
	n_hill.fractal_octaves = 3
	n_biome.seed = s + 23
	n_biome.frequency = 0.0022
	n_biome.fractal_octaves = 2
	n_cave1.seed = s + 37
	n_cave1.frequency = 0.04
	n_cave1.fractal_type = FastNoiseLite.FRACTAL_NONE
	n_cave2.seed = s + 41
	n_cave2.frequency = 0.04
	n_cave2.fractal_type = FastNoiseLite.FRACTAL_NONE
	n_ore.seed = s + 53
	n_ore.frequency = 0.16
	n_ore.fractal_type = FastNoiseLite.FRACTAL_NONE


func height_at(x: int, z: int) -> int:
	var h := 30.0 + n_height.get_noise_2d(x, z) * 9.0
	var m := n_hill.get_noise_2d(x, z)
	if m > 0.1:
		h += (m - 0.1) * 55.0
	return clampi(int(h), 6, H - 12)


## 0 = plains, 1 = forest, 2 = desert
func biome_at(x: int, z: int) -> int:
	var b := n_biome.get_noise_2d(x, z)
	if b > 0.28:
		return 2
	if b < -0.12:
		return 1
	return 0


func hash2(x: int, z: int) -> int:
	var h := x * 374761393 + z * 668265263 + seed_v * 982451653
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7fffffff


func hash3(x: int, y: int, z: int) -> int:
	return hash2(x * 31 + y * 1013, z * 17 - y * 7919)


func tree_at(x: int, z: int) -> bool:
	var bio := biome_at(x, z)
	if bio == 2:
		return false
	var dens := 22 if bio == 1 else 4
	return hash2(x, z) % 1000 < dens


func tree_near(x: int, z: int) -> bool:
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			if tree_at(x + dx, z + dz):
				return true
	return false


func generate(cx: int, cz: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(CH * CH * H)
	data.fill(0)
	var bx := cx * CH
	var bz := cz * CH
	for z in CH:
		for x in CH:
			var wx := bx + x
			var wz := bz + z
			var h := height_at(wx, wz)
			var bio := biome_at(wx, wz)
			var top_id := Blocks.SAND if bio == 2 else Blocks.GRASS
			var fill_id := Blocks.SAND if bio == 2 else Blocks.DIRT
			var col := x + z * CH
			for y in h + 1:
				var id := Blocks.STONE
				if y == 0:
					id = Blocks.BEDROCK
				elif y <= 2 and hash3(wx, y, wz) % 3 == 0:
					id = Blocks.BEDROCK
				elif y == h:
					id = top_id
				elif y > h - 4:
					id = fill_id
				elif y > 3:
					var c1 := n_cave1.get_noise_3d(wx, y * 1.6, wz)
					var c2 := n_cave2.get_noise_3d(wx, y * 1.6, wz)
					if c1 * c1 + c2 * c2 < 0.010:
						continue
					if n_ore.get_noise_3d(wx, y, wz) > 0.70 and y < 54:
						id = Blocks.COAL_ORE
					elif y < 36 and n_ore.get_noise_3d(wx + 500, y, wz - 500) > 0.74:
						id = Blocks.IRON_ORE
				data[col + y * CH * CH] = id
			if bio != 2 and h + 1 < H and hash2(wx + 913, wz - 271) % 1000 < 9:
				data[col + (h + 1) * CH * CH] = Blocks.BERRY_BUSH
	# Trees, including ones rooted in neighbouring chunks whose leaves reach in.
	for tz in range(bz - 2, bz + CH + 2):
		for tx in range(bx - 2, bx + CH + 2):
			if not tree_at(tx, tz):
				continue
			var th := height_at(tx, tz)
			if th > H - 14:
				continue
			var trunk := 4 + hash2(tz, tx) % 3
			var top := th + trunk
			for ly in range(top - 2, top + 2):
				var rad := 2 if ly < top else 1
				for lz in range(-rad, rad + 1):
					for lx in range(-rad, rad + 1):
						if absi(lx) == rad and absi(lz) == rad and (ly >= top or hash3(tx + lx, ly, tz + lz) % 2 == 0):
							continue
						_put(data, bx, bz, tx + lx, ly, tz + lz, Blocks.LEAVES, false)
			for ty in range(th + 1, top):
				_put(data, bx, bz, tx, ty, tz, Blocks.LOG, true)
			_put(data, bx, bz, tx, th, tz, Blocks.DIRT, true)
	return data


func _put(data: PackedByteArray, bx: int, bz: int, wx: int, y: int, wz: int, id: int, overwrite: bool) -> void:
	var lx := wx - bx
	var lz := wz - bz
	if lx < 0 or lx >= CH or lz < 0 or lz >= CH or y < 0 or y >= H:
		return
	var i := lx + lz * CH + y * CH * CH
	if overwrite or data[i] == 0 or data[i] == Blocks.BERRY_BUSH:
		data[i] = id
