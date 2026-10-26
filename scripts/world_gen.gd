class_name WorldGen
extends RefCounted
## Deterministic terrain: hills, forests, deserts, caves, ores, trees, berry bushes.
## Safe to use from worker threads (each task makes its own instance).
##
## Two versions (a world keeps the one it was made with, saved in its world.json and sent to the
## games when they join): 1 (up to 0.18.0) fills the lowest 64 blocks, with gentle hills; 2
## (M4.7, 0.19.0) fills the 128-block world with mountains (snow on top), deep ground, long
## winding tunnels, rooms and ravines (`_carvers`), and ores by depth, the rare crystal at the
## bottom. Version 1 is kept exactly as it was.

const CH := 16
## The world's height (both versions; a version 1 world leaves the upper half to the sky).
const H := 128
## The newest version (what new worlds get). Bump whenever generation changes: clients and
## servers must build the same terrain.
const VERSION := 2
const V1_H := 64

var seed_v := 0
var version := VERSION
var n_height := FastNoiseLite.new()
var n_hill := FastNoiseLite.new()
var n_biome := FastNoiseLite.new()
var n_cave1 := FastNoiseLite.new()
var n_cave2 := FastNoiseLite.new()
var n_ore := FastNoiseLite.new()
# Version 2.
var n_mount := FastNoiseLite.new()
var n_ridge := FastNoiseLite.new()
var n_detail := FastNoiseLite.new()


func _init(s: int, v := VERSION) -> void:
	seed_v = s
	version = v
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
	if version >= 2:
		n_height.frequency = 0.006
		n_hill.frequency = 0.003
		n_mount.seed = s + 61
		n_mount.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n_mount.frequency = 0.0017
		n_mount.fractal_octaves = 2
		n_ridge.seed = s + 67
		n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n_ridge.frequency = 0.0055
		n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		n_ridge.fractal_octaves = 4
		n_detail.seed = s + 71
		n_detail.frequency = 0.06
		n_detail.fractal_type = FastNoiseLite.FRACTAL_NONE


func height_at(x: int, z: int) -> int:
	if version >= 2:
		return _height_v2(x, z)
	var h := 30.0 + n_height.get_noise_2d(x, z) * 9.0
	var m := n_hill.get_noise_2d(x, z)
	if m > 0.1:
		h += (m - 0.1) * 55.0
	return clampi(int(h), 6, V1_H - 12)


## Version 2: rolling land around 62, hills, and ridged mountains where n_mount rises (up to
## about 120; snow from SNOW_LINE).
func _height_v2(x: int, z: int) -> int:
	var h := 62.0 + n_height.get_noise_2d(x, z) * 11.0
	var hill := n_hill.get_noise_2d(x, z)
	if hill > 0.0:
		h += hill * hill * 60.0
	var mm := mountain_at(x, z)
	if mm > 0.0:
		var r := (n_ridge.get_noise_2d(x, z) + 1.0) * 0.5
		h += mm * (12.0 + r * r * 55.0)
	return clampi(int(h), 8, H - 6)


## How much (0..1) the land at (x, z) is mountains (version 2).
func mountain_at(x: int, z: int) -> float:
	return smoothstep(0.0, 0.38, n_mount.get_noise_2d(x, z))


## 0 = plains, 1 = forest, 2 = desert
func biome_at(x: int, z: int) -> int:
	if version >= 2 and mountain_at(x, z) > 0.3:
		var b2 := n_biome.get_noise_2d(x, z)
		return 1 if b2 < -0.12 else 0  # (no desert in the mountains)
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
	if version >= 2:
		return _tree_at_v2(x, z)
	var bio := biome_at(x, z)
	if bio == 2:
		return false
	var dens := 22 if bio == 1 else 4
	return hash2(x, z) % 1000 < dens


## Version 2: the same density, but not on bare rock, snow or steep ground. (generate also skips
## one whose ground a cave took away; Trees.standing finds that out, as nothing stands there.)
func _tree_at_v2(x: int, z: int) -> bool:
	var hv := hash2(x, z) % 1000
	if hv >= 22:
		return false
	var bio := biome_at(x, z)
	if bio == 2 or (bio == 0 and hv >= 4):
		return false
	var h := height_at(x, z)
	if h >= ROCK_LINE - 2:
		return false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if absi(height_at(x + d.x, z + d.y) - h) > 2:
			return false
	return true


## The highest ground a tree grows on (its leaves must fit under the top of the world).
func tree_max_ground() -> int:
	return (V1_H if version < 2 else H) - 14


## A good place to start or wake up: not desert, not up a mountain, no tree in the way, and
## (version 2) solid ground under you rather than a cave's mouth.
func spawn_ok(x: int, z: int) -> bool:
	if biome_at(x, z) == 2 or tree_near(x, z):
		return false
	var h := height_at(x, z)
	if version < 2:
		return h <= 42
	if h < 55 or h > 76:
		return false
	for y in range(h - 4, h + 1):
		if carved(x, y, z):
			return false
	return true


func tree_near(x: int, z: int) -> bool:
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			if tree_at(x + dx, z + dz):
				return true
	return false


func generate(cx: int, cz: int) -> PackedByteArray:
	if version >= 2:
		return _generate_v2(cx, cz)
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
			if bio != 2 and h + 1 < V1_H and hash2(wx + 913, wz - 271) % 1000 < 9:
				data[col + (h + 1) * CH * CH] = Blocks.BERRY_BUSH
	# Trees, including ones rooted in neighbouring chunks whose leaves reach in.
	for tz in range(bz - 2, bz + CH + 2):
		for tx in range(bx - 2, bx + CH + 2):
			if not tree_at(tx, tz):
				continue
			var th := height_at(tx, tz)
			if th > V1_H - 14:
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


# ------------------------------------------------------------ version 2 (M4.7)

## Bare rock from here up (and on steep ground), snow on top from SNOW_LINE (give or take 4).
const ROCK_LINE := 86
const SNOW_LINE := 97
## How far (in chunks) a cave system can reach from the chunk it starts in.
const CARVE_REACH := 4
## The carvers of every origin chunk, made once per process (worker threads share them).
static var _carve_cache := {}
static var _carve_mutex := Mutex.new()


func _generate_v2(cx: int, cz: int) -> PackedByteArray:
	var bx := cx * CH
	var bz := cz * CH
	# Heights with a border of one, for the slopes.
	var hm := PackedInt32Array()
	hm.resize(18 * 18)
	for z in 18:
		for x in 18:
			hm[x + z * 18] = height_at(bx + x - 1, bz + z - 1)
	var tops := PackedByteArray()
	var fills := PackedByteArray()
	var depth := PackedByteArray()
	var hs := PackedInt32Array()
	tops.resize(CH * CH)
	fills.resize(CH * CH)
	depth.resize(CH * CH)
	hs.resize(CH * CH)
	var hmin := H
	var hmax := 0
	for z in CH:
		for x in CH:
			var c := x + 1 + (z + 1) * 18
			var h := hm[c]
			var slope := maxi(maxi(absi(hm[c + 1] - h), absi(hm[c - 1] - h)), maxi(absi(hm[c + 18] - h), absi(hm[c - 18] - h)))
			var wx := bx + x
			var wz := bz + z
			var col := x + z * CH
			hs[col] = h
			hmin = mini(hmin, h)
			hmax = maxi(hmax, h)
			var snow := SNOW_LINE + int(n_detail.get_noise_2d(wx, wz) * 4.0)
			if h >= snow and slope <= 3:
				tops[col] = Blocks.SNOW
				fills[col] = Blocks.STONE
				depth[col] = 1
			elif h >= ROCK_LINE or slope >= 4:
				tops[col] = Blocks.STONE
				fills[col] = Blocks.STONE
				depth[col] = 1
			elif biome_at(wx, wz) == 2:
				tops[col] = Blocks.SAND
				fills[col] = Blocks.SAND
				depth[col] = 4
			else:
				tops[col] = Blocks.GRASS
				fills[col] = Blocks.DIRT
				depth[col] = 3 if h < 76 else 2
	# The ground, a layer at a time: below every column's surface it is all stone.
	var stone_layer := PackedByteArray()
	stone_layer.resize(CH * CH)
	stone_layer.fill(Blocks.STONE)
	var air_layer := PackedByteArray()
	air_layer.resize(CH * CH)
	var data := PackedByteArray()
	for y in H:
		if y > hmax:
			data.append_array(air_layer)
			continue
		var layer := stone_layer.duplicate() if y >= 3 and y < hmin - 4 else PackedByteArray()
		if layer.is_empty():
			layer.resize(CH * CH)
			for col in CH * CH:
				var h := hs[col]
				var id := 0
				if y == 0 or (y <= 2 and hash3(bx + (col & 15), y, bz + (col >> 4)) % 3 == 0):
					id = Blocks.BEDROCK
				elif y < h - depth[col]:
					id = Blocks.STONE
				elif y < h:
					id = fills[col]
				elif y == h:
					id = tops[col]
				layer[col] = id
		data.append_array(layer)
	_carve(data, cx, cz, hs)
	_veins(data, cx, cz)
	# Berry bushes on grass.
	for col in CH * CH:
		var h := hs[col]
		var i := col + h * CH * CH
		if data[i] == Blocks.GRASS and data[i + CH * CH] == 0 and hash2(bx + (col & 15) + 913, bz + (col >> 4) - 271) % 1000 < 9:
			data[i + CH * CH] = Blocks.BERRY_BUSH
	# Trees, including ones rooted in neighbouring chunks whose leaves reach in (not where a cave
	# took the ground away under the trunk).
	for tz in range(bz - 2, bz + CH + 2):
		for tx in range(bx - 2, bx + CH + 2):
			if not tree_at(tx, tz):
				continue
			var th := height_at(tx, tz)
			if th > tree_max_ground() or carved(tx, th, tz) or carved(tx, th + 1, tz):
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


## The caves carved through chunk (cx, cz): every cave system that starts within CARVE_REACH
## chunks and reaches this far. Nothing is carved in the bedrock layers.
func _carve(data: PackedByteArray, cx: int, cz: int, hs: PackedInt32Array) -> void:
	var bx := cx * CH
	var bz := cz * CH
	for oz in range(cz - CARVE_REACH, cz + CARVE_REACH + 1):
		for ox in range(cx - CARVE_REACH, cx + CARVE_REACH + 1):
			var sys: Dictionary = _carvers(ox, oz)
			var box: Rect2 = sys["box"]
			if not box.intersects(Rect2(bx - 1, bz - 1, CH + 2, CH + 2)):
				continue
			var sp: PackedFloat32Array = sys["spheres"]
			for k in range(0, sp.size(), 5):
				var px := sp[k] - bx
				var py := sp[k + 1]
				var pz := sp[k + 2] - bz
				var rh := sp[k + 3]
				var rv := sp[k + 4]
				if px + rh < 0.0 or px - rh > CH or pz + rh < 0.0 or pz - rh > CH:
					continue
				var x0 := maxi(0, floori(px - rh))
				var x1 := mini(CH - 1, floori(px + rh))
				var z0 := maxi(0, floori(pz - rh))
				var z1 := mini(CH - 1, floori(pz + rh))
				var y0 := maxi(3, floori(py - rv))
				var y1 := mini(H - 2, floori(py + rv))
				var ih := 1.0 / (rh * rh)
				var iv := 1.0 / (rv * rv)
				for y in range(y0, y1 + 1):
					var dy := y + 0.5 - py
					var ry := dy * dy * iv
					if ry >= 1.0:
						continue
					for z in range(z0, z1 + 1):
						var dz := z + 0.5 - pz
						for x in range(x0, x1 + 1):
							var dx := x + 0.5 - px
							if (dx * dx + dz * dz) * ih + ry < 1.0:
								data[x + z * CH + y * CH * CH] = 0
			var rv2: PackedFloat32Array = sys["ravines"]
			for k in range(0, rv2.size(), 5):
				var px := rv2[k] - bx
				var pz := rv2[k + 1] - bz
				var w := rv2[k + 2]
				var ybot := int(rv2[k + 3])
				if px + w < 0.0 or px - w > CH or pz + w < 0.0 or pz - w > CH:
					continue
				for z in range(maxi(0, floori(pz - w)), mini(CH - 1, floori(pz + w)) + 1):
					for x in range(maxi(0, floori(px - w)), mini(CH - 1, floori(px + w)) + 1):
						var dx := x + 0.5 - px
						var dz := z + 0.5 - pz
						var d := sqrt(dx * dx + dz * dz)
						if d >= w:
							continue
						# Narrower towards the bottom: a cell this far out is open from yc up.
						var yc := ybot + int((d / w) * (d / w) * 10.0)
						for y in range(maxi(3, yc), hs[x + z * CH] + 2):
							data[x + z * CH + y * CH * CH] = 0


## Is the cell (x, y, z) inside a cave (the same carvers as _carve)?
func carved(x: int, y: int, z: int) -> bool:
	if y < 3:
		return false
	var cx := x >> 4
	var cz := z >> 4
	var p := Vector3(x + 0.5, y + 0.5, z + 0.5)
	for oz in range(cz - CARVE_REACH, cz + CARVE_REACH + 1):
		for ox in range(cx - CARVE_REACH, cx + CARVE_REACH + 1):
			var sys: Dictionary = _carvers(ox, oz)
			if not (sys["box"] as Rect2).has_point(Vector2(p.x, p.z)):
				continue
			var sp: PackedFloat32Array = sys["spheres"]
			for k in range(0, sp.size(), 5):
				var dx := p.x - sp[k]
				var dy := p.y - sp[k + 1]
				var dz := p.z - sp[k + 2]
				if (dx * dx + dz * dz) / (sp[k + 3] * sp[k + 3]) + dy * dy / (sp[k + 4] * sp[k + 4]) < 1.0:
					return true
			var rv2: PackedFloat32Array = sys["ravines"]
			for k in range(0, rv2.size(), 5):
				var dx := p.x - rv2[k]
				var dz := p.z - rv2[k + 1]
				var w := rv2[k + 2]
				var d := sqrt(dx * dx + dz * dz)
				if d < w and y >= int(rv2[k + 3]) + int((d / w) * (d / w) * 10.0):
					return true
	return false


## The cave system that starts in origin chunk (ox, oz), if any: {"box": Rect2 (x, z) it can
## touch, "spheres": x, y, z, horizontal and vertical radius per carving step, "ravines": x, z,
## half width, bottom y, 0 per step}. Long winding tunnels (they wander, rise and fall a little
## and sometimes fork), a room where some start, now and then a big cavern, and rarely a ravine
## open to the sky. Made from the seed, the same everywhere.
func _carvers(ox: int, oz: int) -> Dictionary:
	var key := "%d,%d,%d" % [ox, oz, seed_v]
	_carve_mutex.lock()
	var got = _carve_cache.get(key)
	_carve_mutex.unlock()
	if got != null:
		return got
	var rng := RandomNumberGenerator.new()
	rng.seed = hash2(ox * 7 + 11, oz * 13 - 3) * 31 + 17
	var spheres := PackedFloat32Array()
	var ravines := PackedFloat32Array()
	var center := Vector2(ox * CH + 8, oz * CH + 8)
	var roll := rng.randi() % 100
	var systems := 2 if roll < 5 else (1 if roll < 22 else 0)
	for s in systems:
		var start := Vector3(ox * CH + rng.randf() * CH, rng.randf_range(10.0, 72.0), oz * CH + rng.randf() * CH)
		if rng.randf() < 0.25:
			_add_sphere(spheres, start, rng.randf_range(3.5, 7.0), rng.randf_range(2.2, 3.8))
		for t in rng.randi_range(1, 3):
			_worm(spheres, rng, start, rng.randi_range(40, 80), rng.randf_range(1.3, 2.4), center)
	if rng.randf() < 0.03:
		# A big cavern deep down, with a tunnel or two leading off.
		var c := Vector3(ox * CH + rng.randf() * CH, rng.randf_range(16.0, 40.0), oz * CH + rng.randf() * CH)
		_add_sphere(spheres, c, rng.randf_range(9.0, 14.0), rng.randf_range(4.5, 7.0))
		for t in 2:
			_worm(spheres, rng, c, rng.randi_range(40, 70), rng.randf_range(1.4, 2.2), center)
	if rng.randf() < 0.006:
		_ravine(ravines, rng, Vector3(ox * CH + rng.randf() * CH, rng.randf_range(22.0, 44.0), oz * CH + rng.randf() * CH), center)
	# What this system can touch.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k in range(0, spheres.size(), 5):
		lo = lo.min(Vector2(spheres[k] - spheres[k + 3], spheres[k + 2] - spheres[k + 3]))
		hi = hi.max(Vector2(spheres[k] + spheres[k + 3], spheres[k + 2] + spheres[k + 3]))
	for k in range(0, ravines.size(), 5):
		lo = lo.min(Vector2(ravines[k] - ravines[k + 2], ravines[k + 1] - ravines[k + 2]))
		hi = hi.max(Vector2(ravines[k] + ravines[k + 2], ravines[k + 1] + ravines[k + 2]))
	var box := Rect2(lo, hi - lo) if lo.x <= hi.x else Rect2(center, Vector2.ZERO)
	var sys := {"box": box, "spheres": spheres, "ravines": ravines}
	_carve_mutex.lock()
	if _carve_cache.size() > 20000:
		_carve_cache.clear()
	_carve_cache[key] = sys
	_carve_mutex.unlock()
	return sys


static func _add_sphere(out: PackedFloat32Array, p: Vector3, rh: float, rv: float) -> void:
	out.append_array(PackedFloat32Array([p.x, p.y, p.z, rh, rv]))


## A winding tunnel from p: `steps` blocks long, about radius r, staying within the reach of
## its origin chunk (center), sometimes forking.
func _worm(out: PackedFloat32Array, rng: RandomNumberGenerator, p: Vector3, steps: int, r: float, center: Vector2, fork := true) -> void:
	var yaw := rng.randf() * TAU
	var pitch := rng.randf_range(-0.3, 0.3)
	var dyaw := 0.0
	var dpitch := 0.0
	var limit := float(CARVE_REACH * CH - 4)
	for i in steps:
		var f := float(i) / steps
		var rr := r * (0.8 + 0.4 * sin(f * PI)) + 0.15 * sin(i * 0.4)
		_add_sphere(out, p, maxf(rr, 1.25), maxf(rr * 0.85, 1.2))
		p += Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch))
		pitch = pitch * 0.8 + dpitch * 0.1
		yaw += dyaw * 0.1
		dpitch = dpitch * 0.85 + rng.randf_range(-1.0, 1.0) * 0.6
		dyaw = dyaw * 0.8 + rng.randf_range(-1.0, 1.0) * 1.4
		if p.y < 8.0:
			pitch = absf(pitch) + 0.05
		elif p.y > 96.0:
			pitch = -absf(pitch) - 0.05
		if Vector2(p.x, p.z).distance_to(center) > limit:
			return
		if fork and i == steps / 2 and rng.randf() < 0.35:
			_worm(out, rng, p, steps / 2, r * 0.8, center, false)


## A ravine: a deep, narrow cut open to the sky, wandering a little.
func _ravine(out: PackedFloat32Array, rng: RandomNumberGenerator, p: Vector3, center: Vector2) -> void:
	var yaw := rng.randf() * TAU
	var steps := rng.randi_range(45, 75)
	var wmax := rng.randf_range(2.2, 3.6)
	var limit := float(CARVE_REACH * CH - 4)
	var dyaw := 0.0
	for i in steps:
		var f := float(i) / steps
		var w := 0.8 + (wmax - 0.8) * sin(f * PI)
		out.append_array(PackedFloat32Array([p.x, p.z, w, p.y + (1.0 - sin(f * PI)) * 14.0, 0.0]))
		p += Vector3(cos(yaw), 0.0, sin(yaw))
		yaw += dyaw * 0.05
		dyaw = dyaw * 0.9 + rng.randf_range(-1.0, 1.0) * 0.5
		if Vector2(p.x, p.z).distance_to(center) > limit:
			return


## Ore veins in the stone, by depth: coal from the middle up, iron lower down, and the rare
## crystal near the bottom. Each vein is a short random walk of cells; only stone turns to ore.
func _veins(data: PackedByteArray, cx: int, cz: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash2(cx * 5 - 101, cz * 3 + 77) * 7 + 3
	var kinds := [[Blocks.COAL_ORE, 16, 20, 104, 5, 11], [Blocks.IRON_ORE, 10, 5, 62, 3, 8]]
	var roll := rng.randi() % 100
	if roll < 40:
		kinds.append([Blocks.CRYSTAL_ORE, 2 if roll < 8 else 1, 3, 16, 2, 5])
	for k in kinds:
		for v in int(k[1]):
			var p := Vector3i(rng.randi() % CH, rng.randi_range(k[2], k[3]), rng.randi() % CH)
			for n in rng.randi_range(k[4], k[5]):
				if p.x >= 0 and p.x < CH and p.z >= 0 and p.z < CH and p.y >= 1 and p.y < H:
					var i := p.x + p.z * CH + p.y * CH * CH
					if data[i] == Blocks.STONE:
						data[i] = k[0]
				match rng.randi() % 3:
					0:
						p.x += 1 if rng.randi() % 2 == 0 else -1
					1:
						p.y += 1 if rng.randi() % 2 == 0 else -1
					_:
						p.z += 1 if rng.randi() % 2 == 0 else -1
