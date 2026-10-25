class_name Trees
extends RefCounted
## The world's natural trees (M4.6). They are found from the seed exactly as world_gen.gd grows
## them, so every world has them, old ones too. A tree is still made of blocks (its trunk logs
## and its leaves: collision, zombies, the server and the map go by those), but it is drawn as
## one 3D model (Quaternius' Stylized Nature MegaKit, CC0), and chopping any part of it fells
## the whole tree. Shared by the server (felling) and the client (drawing, mining time); the
## models are only loaded on a client (`mesh`; never preloaded: the server has no assets/).

## The models: [file, height in the model's own metres]. Broadleaf trees first, then pines.
const MODELS := [
	["CommonTree_1", 7.26], ["CommonTree_2", 7.64], ["CommonTree_3", 9.43], ["CommonTree_4", 9.44], ["CommonTree_5", 7.01],
	["Pine_1", 7.32], ["Pine_2", 7.38], ["Pine_3", 7.39], ["Pine_4", 10.24], ["Pine_5", 8.72],
]
const PINES := 5
const DIR := "res://assets/models/nature/"

static var _meshes := {}
static var _gens := {}


## The world generator for a seed (made once; main thread).
static func gen_for(seed_v: int) -> WorldGen:
	if not _gens.has(seed_v):
		_gens[seed_v] = WorldGen.new(seed_v)
	return _gens[seed_v]


## The tree growing on column (tx, tz), as world_gen.gd makes it ({} if none): root (its lowest
## trunk log), top (the trunk is root.y .. top - 1, leaves from top - 2 to top + 1), trunk
## (length), model (MODELS index), yaw, scale.
static func at(gen: WorldGen, tx: int, tz: int) -> Dictionary:
	if not gen.tree_at(tx, tz):
		return {}
	var th := gen.height_at(tx, tz)
	if th > WorldGen.H - 14:
		return {}
	var trunk := 4 + gen.hash2(tz, tx) % 3
	var h := gen.hash2(tx * 7 + 3, tz * 13 - 5)
	# Forests are half pines; the plains mostly broadleaf trees.
	var pine := (h >> 4) % 100 < (50 if gen.biome_at(tx, tz) == 1 else 15)
	var model := (PINES if pine else 0) + h % 5
	var height := trunk + 2.4 + float((h >> 8) % 100) / 100.0
	return {"root": Vector3i(tx, th + 1, tz), "top": th + trunk, "trunk": trunk, "model": model,
		"yaw": float((h >> 12) % 628) / 100.0, "scale": height / float(MODELS[model][1])}


## Every cell of the tree, as world_gen.gd fills it: [[cell, is_log], ...] (a leaf cell only
## holds leaves where the ground left room for them).
static func cells(gen: WorldGen, t: Dictionary) -> Array:
	var out := []
	var r: Vector3i = t["root"]
	var top: int = t["top"]
	for ly in range(top - 2, top + 2):
		var rad := 2 if ly < top else 1
		for lz in range(-rad, rad + 1):
			for lx in range(-rad, rad + 1):
				if absi(lx) == rad and absi(lz) == rad and (ly >= top or gen.hash3(r.x + lx, ly, r.z + lz) % 2 == 0):
					continue
				if lx == 0 and lz == 0 and ly < top:
					continue  # (the trunk)
				out.append([Vector3i(r.x + lx, ly, r.z + lz), false])
	for ty in range(r.y, top):
		out.append([Vector3i(r.x, ty, r.z), true])
	return out


## Is the tree still standing? All its trunk logs are there (`block` gives the block at a cell).
## One a player chopped at before M4.6 is drawn as blocks again.
static func standing(t: Dictionary, block: Callable) -> bool:
	var r: Vector3i = t["root"]
	for y in range(r.y, int(t["top"])):
		if block.call(Vector3i(r.x, y, r.z)) != Blocks.LOG:
			return false
	return true


## The standing natural tree the log or leaves at p belong to ({} if none).
static func tree_of(gen: WorldGen, p: Vector3i, block: Callable) -> Dictionary:
	var id: int = block.call(p)
	if id != Blocks.LOG and id != Blocks.LEAVES:
		return {}
	var reach := 0 if id == Blocks.LOG else 2
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var t := at(gen, p.x + dx, p.z + dz)
			if t.is_empty() or not standing(t, block):
				continue
			for c in cells(gen, t):
				if c[0] == p and (c[1] == (id == Blocks.LOG)):
					return t
	return {}


## Seconds to fell a tree with `tool` (an axe helps, as with logs), at the player's `speed`.
static func fell_time(t: Dictionary, tool: int, speed := 1.0) -> float:
	return Rules.break_time(Blocks.LOG, tool, speed) * (0.5 + 0.25 * int(t["trunk"]))


## What a felled tree gives: [[item, count], ...].
static func drops(t: Dictionary, rng: RandomNumberGenerator) -> Array:
	return [[Blocks.LOG, int(t["trunk"]) + 1], [Items.STICK, rng.randi_range(1, 3)], [Items.FIBER, rng.randi_range(1, 3)]]


## Where the model stands (the chunk's own coordinates: `origin` is the chunk's corner).
static func xform(t: Dictionary, origin := Vector3.ZERO) -> Transform3D:
	var r: Vector3i = t["root"]
	var b := Basis(Vector3.UP, float(t["yaw"])).scaled(Vector3.ONE * float(t["scale"]))
	return Transform3D(b, Vector3(r) + Vector3(0.5, -0.12, 0.5) - origin)


## A model as one mesh with its materials (client only; loaded the first time).
static func mesh(model: int) -> Mesh:
	if _meshes.has(model):
		return _meshes[model]
	var m := merged_mesh(DIR + MODELS[model][0] + ".gltf")
	_meshes[model] = m
	return m


## All the meshes of a model scene as one ArrayMesh in the scene's space, its materials kept.
static func merged_mesh(path: String) -> Mesh:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate() as Node3D
	var parts := inst.find_children("*", "MeshInstance3D", true, false)
	if parts.size() == 1 and _to_root(parts[0], inst).is_equal_approx(Transform3D.IDENTITY):
		var only: Mesh = (parts[0] as MeshInstance3D).mesh  # (as imported, with its levels of detail)
		inst.free()
		return only
	var out := ArrayMesh.new()
	for node in parts:
		var mi := node as MeshInstance3D
		var xf := _to_root(mi, inst)
		for si in mi.mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.create_from(mi.mesh, si)
			st.set_material(mi.get_active_material(si))
			var arr := st.commit_to_arrays()
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in vs.size():
				vs[i] = xf * vs[i]
				if ns.size() > i:
					ns[i] = (xf.basis * ns[i]).normalized()
			arr[Mesh.ARRAY_VERTEX] = vs
			arr[Mesh.ARRAY_NORMAL] = ns
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(out.get_surface_count() - 1, mi.get_active_material(si))
	inst.free()
	return out


static func _to_root(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != root and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## A felled tree coming down (client only): it tips over away from whoever felled it, faster
## and faster, crashes into the ground, lies a moment and sinks away.
class Falling extends Node3D:
	const FALL := 1.8
	const LIE := 2.2
	const SINK := 1.4
	var axis := Vector3.RIGHT
	var dir := Vector3.FORWARD
	var height := 6.0
	var most := deg_to_rad(84.0)
	var t := 0.0
	var landed := false
	var sfx: Node = null

	## tr: the tree (Trees.at), yaw: the way it falls (0 = +Z), sounds: G.sfx (or null).
	func setup(tr: Dictionary, yaw: float, sounds: Node) -> void:
		sfx = sounds
		dir = Vector3(sin(yaw), 0.0, cos(yaw))
		axis = Vector3.UP.cross(dir).normalized()
		var foot: Vector3 = Vector3(tr["root"]) + Vector3(0.5, -0.12, 0.5)
		position = foot
		var mi := MeshInstance3D.new()
		mi.mesh = Trees.mesh(int(tr["model"]))
		mi.transform = Trees.xform(tr, foot)
		add_child(mi)
		height = float(tr["trunk"]) + 3.0
		if sfx != null:
			sfx.play_at("creak", foot + Vector3(0, 2, 0), -2.0)

	func _process(delta: float) -> void:
		t += delta
		var a := 0.0
		if t < FALL:
			a = most * pow(t / FALL, 2.4)
		else:
			if not landed:
				landed = true
				_crash()
			var b := t - FALL
			a = most - deg_to_rad(5.0) * sin(PI * minf(b / 0.35, 1.0)) * exp(-b * 2.0)
			if b > LIE:
				position.y -= delta * 2.2 / SINK
			if b > LIE + SINK:
				queue_free()
				return
		basis = Basis(axis, a)

	func _crash() -> void:
		var at := position + dir * height * 0.65 + Vector3(0, 0.6, 0)
		if sfx != null:
			sfx.play_at("timber", at, 2.0)
		# A burst of leaves where the crown hits.
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.amount = 40
		p.lifetime = 1.6
		p.explosiveness = 0.9
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 1.6
		p.direction = Vector3.UP
		p.spread = 70.0
		p.initial_velocity_min = 1.5
		p.initial_velocity_max = 3.5
		p.gravity = Vector3(0, -3.0, 0)
		p.damping_min = 1.0
		p.damping_max = 2.0
		p.angular_velocity_min = -200.0
		p.angular_velocity_max = 200.0
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.2
		var q := QuadMesh.new()
		q.size = Vector2(0.14, 0.1)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.32, 0.5, 0.2)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		q.material = m
		p.mesh = q
		get_parent().add_child(p)
		p.global_position = at
		p.emitting = true
		p.finished.connect(p.queue_free)
