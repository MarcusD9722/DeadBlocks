extends RefCounted
## The drawn world must have no holes: `-- --meshtest`. Meshes chunks of generated land and of
## land full of randomly placed built and natural blocks, the way a game does, and checks the
## drawn solid surface (rounded ground, cubes, boxes) is closed: no edge that only one triangle
## uses, apart from the bottom of the world; the natural trees, drawn as models since M4.6, are
## left out of it. Also counts rounded-ground triangles that are folded
## over (drawn facing away from their own normals). Prints MESHTEST lines and DONE fails=N.

const WorldScript := preload("res://scripts/world.gd")
const CH := 16

static var _seed := 0
static var _trees := 0


static func run(seed_v: int) -> void:
	SmoothMesher.init_tables()
	_seed = seed_v
	var fails := 0
	var gen := WorldGen.new(seed_v)
	var base := {}
	for z in range(-2, 3):
		for x in range(-2, 3):
			base[Vector2i(x, z)] = gen.generate(x, z)
	_trees = 0
	fails += _check("generated land", base, {})
	# The natural trees are drawn as models (M4.6), their blocks left out of the picture.
	var ok := _trees > 0
	print("MESHTEST %s generated land: %d trees drawn as models" % ["PASS" if ok else "FAIL", _trees])
	fails += 0 if ok else 1
	# Built and natural blocks mixed at random around the surface (walls, floors, logs, tunnels).
	var ids := [Blocks.AIR, Blocks.AIR, Blocks.AIR, Blocks.DIRT, Blocks.STONE, Blocks.GRASS, Blocks.PLANKS,
		Blocks.COBBLE, Blocks.LOG, Blocks.STONE_BRICK, Blocks.LEAVES, Blocks.TORCH, Blocks.BED, Blocks.SAND,
		# M4.2 shapes, in random states: half blocks, ramps, pillars, doors, hatches, boxes.
		Blocks.FRAME_HALF + 2, Blocks.FRAME_RAMP + 3, Blocks.FRAME_PILLAR + 1, Blocks.WOOD_DOOR, Blocks.IRON_DOOR_OPEN,
		Blocks.STEEL_HATCH, Blocks.WOOD_HATCH_OPEN, Blocks.WOOD_BOX, Blocks.IRON_WALL, Blocks.WOOD_FRAME]
	for trial in 3:
		var rng := RandomNumberGenerator.new()
		rng.seed = 77 + trial
		var mixed := {}
		var metas := {}
		for k in base:
			mixed[k] = (base[k] as PackedByteArray).duplicate()
			metas[k] = {}
		for k in mixed:
			var d: PackedByteArray = mixed[k]
			for z in CH:
				for x in CH:
					var h := gen.height_at(k.x * CH + x, k.y * CH + z)
					for y in range(maxi(1, h - 5), mini(63, h + 4)):
						if rng.randf() < 0.35:
							var i := x + z * CH + y * CH * CH
							d[i] = ids[rng.randi() % ids.size()]
							if Blocks.SHAPE[d[i]] >= Blocks.SH_HALF:
								metas[k][i] = rng.randi_range(0, 7)
		fails += _check("mixed blocks %d" % trial, mixed, metas)
	print("MESHTEST DONE fails=%d" % fails)


## Meshes the 3x3 chunks in the middle of `data` (5x5) as a drawn game would, then checks the
## middle chunk's surface. Returns the number of failed checks.
static func _check(what: String, data: Dictionary, metas: Dictionary) -> int:
	var w = WorldScript.new()
	w.seed_v = _seed
	var edges := {}
	var folded := 0
	var tris := 0
	for cz in range(-1, 2):
		for cx in range(-1, 2):
			var nb := []
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					nb.append(data[Vector2i(cx + dx, cz + dz)])
			nb.append(metas.get(Vector2i(cx, cz), {}))
			nb.append(Vector2i(cx, cz))
			var buf = w._build(nb)
			_trees += buf.trees.size()
			var o := Vector3(cx * CH, 0, cz * CH)
			var f: PackedVector3Array = buf.vfaces
			for i in range(0, f.size(), 3):
				_add_tri(edges, f[i] + o, f[i + 1] + o, f[i + 2] + o)
			if cx == 0 and cz == 0:
				for i in range(0, buf.t_idx.size(), 3):
					var a: Vector3 = buf.t_verts[buf.t_idx[i]]
					var b: Vector3 = buf.t_verts[buf.t_idx[i + 1]]
					var c: Vector3 = buf.t_verts[buf.t_idx[i + 2]]
					var n: Vector3 = buf.t_norms[buf.t_idx[i]] + buf.t_norms[buf.t_idx[i + 1]] + buf.t_norms[buf.t_idx[i + 2]]
					tris += 1
					if (b - a).cross(c - a).dot(n) > 0.0:
						folded += 1  # Godot's front faces wind clockwise: this one faces away
	w.free()
	var holes := 0
	var example := ""
	for e in edges:
		if edges[e] != 1:
			continue
		var m: Vector3 = (e[0] + e[1]) * 0.5
		if m.x < 0.0 or m.x > CH or m.z < 0.0 or m.z > CH or m.y < 1.5:
			continue  # another chunk's edge, or the bottom of the world
		holes += 1
		if example == "":
			example = " (e.g. %s - %s)" % [e[0], e[1]]
	var ok := holes == 0
	print("MESHTEST %s %s: %d open edges%s, %d of %d rounded triangles folded over" % [
		"PASS" if ok else "FAIL", what, holes, example, folded, tris])
	return 0 if ok else 1


static func _key(p: Vector3) -> Vector3:
	return p.snapped(Vector3(0.001, 0.001, 0.001))


static func _add_tri(edges: Dictionary, a: Vector3, b: Vector3, c: Vector3) -> void:
	var pts := [_key(a), _key(b), _key(c)]
	for i in 3:
		var p: Vector3 = pts[i]
		var q: Vector3 = pts[(i + 1) % 3]
		var e := [p, q] if _before(p, q) else [q, p]
		edges[e] = int(edges.get(e, 0)) + 1


static func _before(p: Vector3, q: Vector3) -> bool:
	if p.x != q.x:
		return p.x < q.x
	if p.y != q.y:
		return p.y < q.y
	return p.z < q.z
