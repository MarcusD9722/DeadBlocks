class_name Decor
extends RefCounted
## The small things on the land (M4.6, client only, picture only): grass, flowers, clover, ferns,
## plants, mushrooms, bushes and the odd rock on the grass, pebbles and rocks on sand and bare
## stone, and the berry bush block drawn as a bush with berries on it. Where they grow comes from
## the world's seed (`pick`), so every player sees the same; nothing collides with them. Models
## from Quaternius' Stylized Nature MegaKit (CC0), loaded only on a client (`mesh`).

## [file, size, big]: size scales the model to our metres (with a little variation each);
## big ones (bushes, rocks) cast shadows and are drawn further away than the small ones.
const MODELS := [
	["Grass_Common_Short", 0.42, false], ["Grass_Wispy_Short", 0.4, false],
	["Grass_Common_Tall", 0.34, false], ["Grass_Wispy_Tall", 0.32, false],
	["Flower_3_Single", 0.3, false], ["Flower_4_Single", 0.27, false],
	["Flower_3_Group", 0.3, false], ["Flower_4_Group", 0.25, false],
	["Clover_1", 0.32, false], ["Clover_2", 0.3, false],
	["Fern_1", 0.36, false], ["Plant_1", 0.36, false], ["Plant_7", 0.45, false],
	["Mushroom_Common", 0.42, false],
	["Pebble_Round_1", 0.75, false], ["Pebble_Round_2", 0.75, false], ["Pebble_Round_3", 0.75, false],
	["Pebble_Round_4", 0.75, false], ["Pebble_Round_5", 0.75, false],
	["Bush_Common", 0.5, true], ["Rock_Medium_1", 0.3, true], ["Rock_Medium_2", 0.32, true],
	["Rock_Medium_3", 0.28, true],
	["", 1.0, true],  # the berry bush (made in code, BERRY)
	["", 1.0, true],  # the crystal lamp (a block, made in code, LAMP; M4.7)
]
const GRASS := 0
const FLOWER := 4
const CLOVER := 8
const FERN := 10
const PLANT := 11
const MUSHROOM := 13
const PEBBLE := 14
const BUSH := 19
const ROCK := 20
const BERRY := 23
const LAMP := 24
const DIR := "res://assets/models/nature/"

static var _meshes := {}


## What grows on top of the block `top` at column (x, z) (the cell above is open air), as a
## MODELS index or -1. `biome` is WorldGen.biome_at there.
static func pick(gen: WorldGen, x: int, z: int, top: int, biome: int) -> int:
	var h := gen.hash2(x * 3 + 11, z * 5 - 7) % 1000
	var v := gen.hash2(z + 101, x - 37)
	match top:
		Blocks.GRASS:
			if biome == 1:  # forest: ferns, mushrooms, fewer flowers
				if h < 230:
					return GRASS + (v % 4 if v % 3 == 0 else v % 2)
				if h < 236:
					return FLOWER + v % 4
				if h < 256:
					return CLOVER + v % 2
				if h < 306:
					return FERN
				if h < 320:
					return PLANT + v % 2
				if h < 332:
					return MUSHROOM
				if h < 340:
					return BUSH
				if h < 343:
					return ROCK + v % 3
				return -1
			if h < 250:
				return GRASS + (v % 4 if v % 3 == 0 else v % 2)
			if h < 272:
				return FLOWER + v % 4
			if h < 297:
				return CLOVER + v % 2
			if h < 302:
				return FERN
			if h < 312:
				return PLANT + v % 2
			if h < 316:
				return BUSH
			if h < 319:
				return ROCK + v % 3
		Blocks.SAND:
			if h < 25:
				return PEBBLE + v % 5
			if h < 30:
				return ROCK + v % 3
		Blocks.STONE, Blocks.COBBLE:
			if h < 30:
				return PEBBLE + v % 5
			if h < 45:
				return ROCK + v % 3
	return -1


## Where in its column a thing stands and how it is turned and sized: [x offset, z offset, yaw,
## scale] (offsets 0.15-0.85 in the cell).
static func spot(gen: WorldGen, x: int, z: int, model: int) -> Array:
	var a := gen.hash2(x * 17 - 5, z * 23 + 9)
	var fx := 0.15 + 0.7 * float(a % 100) / 100.0
	var fz := 0.15 + 0.7 * float((a >> 8) % 100) / 100.0
	if model == BUSH or model >= ROCK:
		fx = 0.5 + (fx - 0.5) * 0.4  # (big ones near the middle)
		fz = 0.5 + (fz - 0.5) * 0.4
	var yaw := float((a >> 16) % 628) / 100.0
	var s: float = MODELS[model][1] * (0.85 + 0.3 * float((a >> 4) % 100) / 100.0)
	return [fx, fz, yaw, s]


static func is_big(model: int) -> bool:
	return MODELS[model][2]


## A model as one mesh (client only; loaded the first time).
static func mesh(model: int) -> Mesh:
	if _meshes.has(model):
		return _meshes[model]
	var m: Mesh = _berry_bush() if model == BERRY else (_lamp() if model == LAMP else Trees.merged_mesh(DIR + MODELS[model][0] + ".gltf"))
	_meshes[model] = m
	return m


## The berry bush block: a small bush with red berries on it, standing on the cell's floor.
static func _berry_bush() -> Mesh:
	var bush := Trees.merged_mesh(DIR + "Bush_Common_Flowers.gltf")
	if bush == null:
		return null
	var s := 0.46
	var out := ArrayMesh.new()
	var box := bush.get_aabb()
	var sx := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), Vector3(0, -box.position.y * s - 0.02, 0))
	for si in bush.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(bush, si, sx)
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, bush.surface_get_material(si))
	var berry := SphereMesh.new()
	berry.radius = 0.042
	berry.height = 0.084
	berry.radial_segments = 8
	berry.rings = 4
	var st := SurfaceTool.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var c := sx * box.get_center()
	var r := box.size * 0.5 * s * 0.9
	for i in 16:
		var a := rng.randf() * TAU
		var e := rng.randf_range(0.05, 1.1)
		var d := Vector3(cos(a) * cos(e), sin(e), sin(a) * cos(e))
		st.append_from(berry, 0, Transform3D(Basis.IDENTITY, c + d * r))
	st.commit(out)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.06, 0.12)
	m.roughness = 0.3
	m.metallic_specular = 0.7
	out.surface_set_material(out.get_surface_count() - 1, m)
	return out


## The crystal lamp block (M4.7): a small iron cage on the floor round a glowing crystal.
static func _lamp() -> Mesh:
	var out := ArrayMesh.new()
	var iron := SurfaceTool.new()
	iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	ToolModels._rod(iron, Vector3(0, 0.0, 0), Vector3(0, 0.05, 0), 0.19, 0.19, Vector3.RIGHT, 0.3)
	ToolModels._rod(iron, Vector3(0, 0.54, 0), Vector3(0, 0.6, 0), 0.16, 0.12, Vector3.RIGHT, 0.4)
	ToolModels._rod(iron, Vector3(0, 0.6, 0), Vector3(0, 0.66, 0), 0.03, 0.03)
	for k in 4:
		var a := TAU * k / 4.0 + PI * 0.25
		var c := Vector3(cos(a), 0.0, sin(a)) * 0.15
		ToolModels._rod(iron, c + Vector3(0, 0.04, 0), c + Vector3(0, 0.56, 0), 0.016, 0.016)
	iron.commit(out)
	out.surface_set_material(0, ToolModels.material("iron"))
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	ItemModels._lump(glow, Vector3(0, 0.3, 0), Vector3(0.07, 0.2, 0.07), 11)
	ItemModels._lump(glow, Vector3(0.05, 0.18, 0.03), Vector3(0.04, 0.1, 0.04), 12)
	glow.commit(out)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.7, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.45, 0.68, 1.0)
	m.emission_energy_multiplier = 2.2
	m.roughness = 0.15
	out.surface_set_material(1, m)
	return out
