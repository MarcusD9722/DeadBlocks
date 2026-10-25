class_name ItemModels
extends RefCounted
## The other items as 3D models (M4.6, client only), like the tools' (ToolModels): sticks, coal,
## ingots, meat, berries, the bandage, plant fibre, Blood Shards and boar hide. Their icons are
## drawn from them, and you hold them in your hand as models. Also the blocks' icons: each block
## drawn as a little block with its photo textures (`block_mesh`), its shape too (half blocks,
## ramps, pillars, doors, hatches, boxes).


## Items with a model here, and how their icon is turned: true = leaning like a tool's handle.
const ITEMS := {
	Items.STICK: true, Items.FIBER: true, Items.COAL: false, Items.IRON_INGOT: false,
	Items.STEEL_INGOT: false, Items.BLOOD_INGOT: false, Items.RAW_MEAT: false,
	Items.COOKED_MEAT: false, Items.BERRIES: false, Items.BANDAGE: false,
	Items.BLOOD_SHARD: true, Items.BOAR_HIDE: false,
}

static var _block_mat: ShaderMaterial = null


static func has_model(id: int) -> bool:
	return ITEMS.has(id)


## Leaning like a tool in its icon (long things), or seen from a little above?
static func leans(id: int) -> bool:
	return ITEMS.get(id, false)


## The model's parts for ToolModels.make: [[mesh, material], ...], about the size of the thing,
## its middle near the origin.
static func parts(id: int) -> Array:
	var out := []
	match id:
		Items.STICK:
			out.append([ToolModels._mesh(func(st): _bent(st, [Vector3(0.0, -0.17, 0.0), Vector3(0.008, -0.05, 0.0), Vector3(-0.004, 0.06, 0.0), Vector3(0.01, 0.17, 0.0)], 0.012, 0.008)), "wood"])
			out.append([ToolModels._mesh(func(st): ToolModels._rod(st, Vector3(0.0, 0.02, 0.0), Vector3(0.055, 0.085, 0.01), 0.006, 0.004)), "wood"])
		Items.FIBER:
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			for k in 9:
				var a := TAU * k / 9.0
				var r := 0.012 + 0.008 * rng.randf()
				var top := Vector3(cos(a) * r * 2.4, 0.15 + rng.randf() * 0.04, sin(a) * r * 2.4)
				var bottom := Vector3(cos(a) * r * 2.0, -0.15 - rng.randf() * 0.03, sin(a) * r * 2.0)
				out.append([ToolModels._mesh(func(st): _bent(st, [bottom, Vector3(cos(a) * r, 0.0, sin(a) * r), top], 0.0035, 0.002)), "fiber"])
			out.append([ToolModels._mesh(func(st): ToolModels._rod(st, Vector3(0, -0.012, 0), Vector3(0, 0.012, 0), 0.026, 0.026, Vector3.RIGHT, 0.3)), "string"])
		Items.COAL:
			out.append([ToolModels._mesh(func(st): _lump(st, Vector3(0.0, 0.0, 0.0), Vector3(0.05, 0.042, 0.048), 1)), "coal"])
			out.append([ToolModels._mesh(func(st): _lump(st, Vector3(0.058, -0.012, 0.03), Vector3(0.034, 0.03, 0.032), 2)), "coal"])
			out.append([ToolModels._mesh(func(st): _lump(st, Vector3(-0.04, -0.016, 0.05), Vector3(0.03, 0.026, 0.028), 3)), "coal"])
		Items.IRON_INGOT, Items.STEEL_INGOT, Items.BLOOD_INGOT:
			var mat := "iron" if id == Items.IRON_INGOT else ("steel" if id == Items.STEEL_INGOT else "blood")
			out.append([ToolModels._mesh(func(st): _ingot(st)), mat])
		Items.RAW_MEAT:
			# A steak: the fat along one side, a round of bone through it.
			out.append([ToolModels._mesh(func(st): ToolModels._blob(st, Vector3(0.0, 0.0, 0.0), Vector3(0.1, 0.03, 0.072))), "meat"])
			out.append([ToolModels._mesh(func(st): ToolModels._blob(st, Vector3(-0.072, -0.001, 0.0), Vector3(0.036, 0.027, 0.062))), "fat"])
			out.append([ToolModels._mesh(func(st): ToolModels._rod(st, Vector3(0.035, -0.031, 0.01), Vector3(0.035, 0.031, 0.01), 0.014, 0.014, Vector3.RIGHT, 0.2)), "bone"])
		Items.COOKED_MEAT:
			out.append([ToolModels._mesh(func(st): ToolModels._blob(st, Vector3(0.04, 0.0, 0.0), Vector3(0.075, 0.055, 0.058))), "cooked"])
			out.append([ToolModels._mesh(func(st): ToolModels._rod(st, Vector3(-0.02, 0.0, 0.0), Vector3(-0.125, 0.0, 0.0), 0.014, 0.012)), "bone"])
			out.append([ToolModels._mesh(func(st): ToolModels._blob(st, Vector3(-0.13, 0.013, 0.0), Vector3(0.018, 0.018, 0.018))), "bone"])
			out.append([ToolModels._mesh(func(st): ToolModels._blob(st, Vector3(-0.13, -0.013, 0.0), Vector3(0.018, 0.018, 0.018))), "bone"])
		Items.BERRIES:
			for c in [Vector3(0, 0, 0), Vector3(0.052, -0.006, 0.018), Vector3(-0.046, -0.008, 0.022), Vector3(0.01, -0.008, -0.05), Vector3(0.018, 0.04, 0.008)]:
				out.append([ToolModels._mesh(func(st): ToolModels._blob(st, c, Vector3(0.03, 0.03, 0.03))), "berry"])
			out.append([ToolModels._mesh(func(st): ToolModels._blob(st, Vector3(-0.02, 0.05, -0.03), Vector3(0.045, 0.006, 0.02))), "leaf"])
			out.append([ToolModels._mesh(func(st): ToolModels._rod(st, Vector3(0.018, 0.06, 0.008), Vector3(0.0, 0.1, -0.01), 0.004, 0.003)), "darkwood"])
		Items.BANDAGE:
			out.append([ToolModels._mesh(func(st): ToolModels._rod(st, Vector3(-0.055, 0.0, 0.0), Vector3(0.055, 0.0, 0.0), 0.045, 0.045, Vector3.UP, 0.12)), "cloth"])
			out.append([ToolModels._mesh(func(st): _strip(st)), "cloth"])
		Items.BLOOD_SHARD:
			out.append([ToolModels._mesh(func(st): _lump(st, Vector3(0.0, 0.0, 0.0), Vector3(0.032, 0.11, 0.03), 4)), "shard"])
			out.append([ToolModels._mesh(func(st): _lump(st, Vector3(0.035, -0.06, 0.01), Vector3(0.018, 0.05, 0.018), 5)), "shard"])
			out.append([ToolModels._mesh(func(st): _lump(st, Vector3(-0.03, -0.07, -0.01), Vector3(0.016, 0.04, 0.016), 6)), "shard"])
		Items.BOAR_HIDE:
			out.append([ToolModels._mesh(func(st): _pelt(st)), "hide"])
	return out


# ------------------------------------------------------------ shapes

## A round rod along the points of `path` (tapering from r0 to r1), with rounded ends.
static func _bent(st: SurfaceTool, path: Array, r0: float, r1: float) -> void:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var n := path.size()
	var d0: Vector3 = (path[1] - path[0]).normalized()
	var d1: Vector3 = (path[n - 1] - path[n - 2]).normalized()
	pts.append(path[0] - d0 * r0 * 0.6)
	radii.append(0.0)
	for i in n:
		pts.append(path[i])
		radii.append(lerpf(r0, r1, float(i) / (n - 1)))
	pts.append(path[n - 1] + d1 * r1 * 0.6)
	radii.append(0.0)
	ToolModels._tube(st, pts, radii)


## A rough lump with flat faces (coal, a shard): a jittered icosahedron of radii r.
static func _lump(st: SurfaceTool, c: Vector3, r: Vector3, seed_v: int) -> void:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var f := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var p := []
	for q in v:
		p.append(c + (q as Vector3).normalized() * r * rng.randf_range(0.78, 1.12))
	for tri in f:
		var a: Vector3 = p[tri[0]]
		var b: Vector3 = p[tri[1]]
		var e: Vector3 = p[tri[2]]
		var n := (b - a).cross(e - a).normalized()
		if n.dot((a + b + e) / 3.0 - c) < 0.0:
			n = -n
		ToolModels._tri(st, a, b, e, n, n, n)


## An ingot: a bar narrower on top, with softly rounded ends (along X).
static func _ingot(st: SurfaceTool) -> void:
	var path := PackedVector3Array()
	var sections := []
	var xs := [-0.085, -0.082, -0.074, 0.074, 0.082, 0.085]
	var ks := [0.02, 0.75, 1.0, 1.0, 0.75, 0.02]
	for i in xs.size():
		path.append(Vector3(xs[i], 0.0, 0.0))
		var sec := PackedVector2Array()
		for q in ToolModels._rrect_offset(0.042, 0.02, 0.008, 0.0):
			var top := (q.y + 0.02) / 0.04  # 0 at the bottom, 1 on top
			sec.append(Vector2(q.x * lerpf(1.0, 0.72, top), q.y) * ks[i])
		sections.append(sec)
	ToolModels._loft(st, path, sections, Vector3.BACK)


## A boar's hide: a thin, uneven skin, folded over a little at one end.
static func _pelt(st: SurfaceTool) -> void:
	var path := PackedVector3Array()
	var sections := []
	var widths := [0.05, 0.095, 0.08, 0.1, 0.092, 0.085, 0.104, 0.075, 0.045]
	for i in widths.size():
		var f := float(i) / (widths.size() - 1)
		var x := -0.15 + 0.3 * f
		path.append(Vector3(x, 0.03 * f * f, 0.012 * sin(f * 9.0)))
		sections.append(ToolModels._rrect_offset(widths[i], 0.006, 0.005, 0.0))
	ToolModels._loft(st, path, sections, Vector3.BACK)


## The loose end of a bandage, unrolled a little from the bottom of the roll.
static func _strip(st: SurfaceTool) -> void:
	var path := PackedVector3Array()
	var sections := []
	for i in 6:
		var f := float(i) / 5.0
		path.append(Vector3(0.0, -0.045 + 0.004 * f, 0.02 + f * 0.09))
		sections.append(ToolModels._rrect_offset(0.052, 0.003, 0.002, 0.0))
	ToolModels._loft(st, path, sections, Vector3.RIGHT)


# ------------------------------------------------------------ blocks (their icons)

## Can this block's icon be drawn as a 3D block? (Plants, torches and leaves keep their pictures.)
static func block_has_model(id: int) -> bool:
	if id <= 0 or id >= Blocks.COUNT or Blocks.item_of(id) != id or id == Blocks.BACKPACK or id == Blocks.LEAVES:
		return false
	return Blocks.SHAPE[id] != Blocks.SH_CROSS and Blocks.SHAPE[id] != Blocks.SH_NONE


## The natural ground's blocks take the ground's pictures (Tex.terrain_albedo layers, as
## SmoothMesher.LAYER): [top, sides, bottom].
const GROUND := {Blocks.GRASS: [0, 1, 1], Blocks.DIRT: [1, 1, 1], Blocks.STONE: [2, 2, 2], Blocks.SAND: [3, 3, 3],
	Blocks.COAL_ORE: [4, 4, 4], Blocks.IRON_ORE: [5, 5, 5], Blocks.BEDROCK: [6, 6, 6]}
static var _ground_mats := {}


## The block as meshes with the world's block material (a door two cells tall); `tex`: G.tex.
static func block_parts(id: int, tex) -> Array:
	if GROUND.has(id):
		var out := []
		for g in 3:
			var dirs: Array = [[0], [2, 3, 4, 5], [1]][g]
			var b := MeshBuf.new()
			for dir in dirs:
				b.face(dir, 0, 0, 0, 0, false)
			out.append([_arrays_mesh(b), _ground_material(tex, GROUND[id][g])])
		return out
	var buf := MeshBuf.new()
	var tl: Array = Blocks.TILES[id]
	var shape: int = Blocks.SHAPE[id]
	if id == Blocks.LOG:
		buf.trunk(0, 0, 0, tl, true, true, 1.0, 1.0)
	elif shape == Blocks.SH_CUBE:
		for dir in 6:
			buf.face(dir, 0, 0, 0, tl[0] if dir == 0 else (tl[2] if dir == 1 else tl[1]), false)
	elif shape == Blocks.SH_RAMP:
		buf.ramp(0, 0, 0, tl, 2, 1.0)
	else:
		for b in Blocks.boxes_of(id, 2):
			buf.box(0, 0, 0, tl, b[0], b[1], false)
		if shape == Blocks.SH_DOOR:
			var up := [tl[0] + Blocks.DOOR_UPPER_TILES, tl[1] + Blocks.DOOR_UPPER_TILES, tl[2] + Blocks.DOOR_UPPER_TILES]
			for b in Blocks.boxes_of(id, 2 | Blocks.META_UPPER):
				buf.box(0, 1, 0, up, b[0], b[1], false)
	if buf.verts.is_empty():
		return []
	return [[_arrays_mesh(buf), block_material(tex)]]


static func _arrays_mesh(buf: MeshBuf) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = buf.verts
	arr[Mesh.ARRAY_NORMAL] = buf.norms
	arr[Mesh.ARRAY_TEX_UV] = buf.uvs
	arr[Mesh.ARRAY_TEX_UV2] = buf.uv2s
	arr[Mesh.ARRAY_COLOR] = buf.cols
	arr[Mesh.ARRAY_INDEX] = buf.idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


## A plain material showing one layer of the ground's pictures.
static func _ground_material(tex, layer: int) -> Material:
	if not _ground_mats.has(layer):
		var m := StandardMaterial3D.new()
		var arr: TextureLayered = tex.terrain_albedo
		if arr != null and layer < arr.get_layers():
			m.albedo_texture = ImageTexture.create_from_image(arr.get_layer_data(layer))
		m.roughness = 0.92
		_ground_mats[layer] = m
	return _ground_mats[layer]


## The block material for icons: as the world's, with the rounded edges in the model's own space.
static func block_material(tex) -> ShaderMaterial:
	if _block_mat == null:
		_block_mat = ShaderMaterial.new()
		_block_mat.shader = preload("res://shaders/blocks.gdshader")
		_block_mat.set_shader_parameter("albedo_tex", tex.block_albedo)
		_block_mat.set_shader_parameter("normal_tex", tex.block_normal)
		_block_mat.set_shader_parameter("own_space", true)
		_block_mat.set_shader_parameter("min_light", 1.0)
	return _block_mat
