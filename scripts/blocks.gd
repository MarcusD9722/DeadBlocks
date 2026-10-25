class_name Blocks
extends RefCounted
## Block definitions. A block id is also its item id. The per-block tables (NAMES, TILES, SHAPE,
## SOLID, ...) are built from DEFS when the class loads.
##
## Blocks can carry a little state besides their id (world.gd keeps it per chunk, see
## world.block_meta): META_FACING (bits 0-1: 0 = +Z, 1 = +X, 2 = -Z, 3 = -X) for doors, hatches
## and ramps, and META_UPPER for the upper half (a door's top half; a half block or hatch in the
## top of its cell). An open door or hatch is its own block id, so whether something is solid
## always follows from the id alone (zombies, collision and the server's checks use only ids).

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const COBBLE := 4
const LOG := 5
const LEAVES := 6
const PLANKS := 7
const SAND := 8
const COAL_ORE := 9
const IRON_ORE := 10
const BEDROCK := 11
const WORKBENCH := 12
const FORGE := 13
const CAMPFIRE := 14
const TORCH := 15
const SPIKES := 16
const STONE_BRICK := 17
const BERRY_BUSH := 18
const REINFORCED := 19
const BACKPACK := 20
const BED := 21
## M4.1: the Blood Moon station, and the wall it makes (twice as tough as Reinforced Wall).
const BLOOD_FORGE := 22
const BLOOD_BRICK := 23
## M4.2: the structure tiers (each upgraded from the one before with a hammer). Planks are the
## second tier's full block.
const WOOD_FRAME := 24
const REINFORCED_WOOD := 25
const IRON_WALL := 26
const STEEL_WALL := 27
const BLOOD_WALL := 28
## ...and each tier as a half block, a ramp and a pillar (FRAME_HALF + tier, and so on).
const FRAME_HALF := 29
const FRAME_RAMP := 35
const FRAME_PILLAR := 41
## Doors (two blocks tall) and hatches, closed and open; storage boxes.
const WOOD_DOOR := 47
const WOOD_DOOR_OPEN := 48
const IRON_DOOR := 49
const IRON_DOOR_OPEN := 50
const STEEL_DOOR := 51
const STEEL_DOOR_OPEN := 52
const WOOD_HATCH := 53
const WOOD_HATCH_OPEN := 54
const IRON_HATCH := 55
const IRON_HATCH_OPEN := 56
const STEEL_HATCH := 57
const STEEL_HATCH_OPEN := 58
const WOOD_BOX := 59
const IRON_BOX := 60
const COUNT := 61

const SH_NONE := 0
const SH_CUBE := 1
const SH_CROSS := 2
## A smaller box inside the cell (sizes in BOX), with a whole tile on each face.
const SH_BOX := 3
## M4.2 shapes (boxes_of gives their boxes for a block's state; a ramp is drawn as a slope).
const SH_HALF := 4
const SH_PILLAR := 5
const SH_RAMP := 6
const SH_DOOR := 7
const SH_HATCH := 8

const META_FACING := 3
const META_UPPER := 4
## A door or hatch panel's thickness.
const PANEL := 0.18
## A door's upper half is drawn with the atlas tiles this much further on (its own picture: the
## lower half has the handle).
const DOOR_UPPER_TILES := 10

## The structure tiers, lowest first: the full block of each, and the names their shapes use.
const TIER_BLOCKS := [WOOD_FRAME, PLANKS, REINFORCED_WOOD, IRON_WALL, STEEL_WALL, BLOOD_WALL]
const TIER_NAMES := ["Frame", "Wooden", "Reinforced Wood", "Iron", "Steel", "Blood-forged"]
const _TIER_TILE := [30, 8, 31, 32, 33, 34]
const _TIER_HARD := [0.8, 2.5, 5.0, 10.0, 14.0, 18.0]
const _TIER_TOOL := ["axe", "axe", "axe", "pick", "pick", "pick"]
const _TIER_REQ := [0, 0, 0, 2, 3, 4]
const _TIER_ZHP := [25, 60, 200, 400, 700, 1300]

## [name, [top, side, bottom] atlas tiles, shape, solid, opaque, full, seconds to break by hand
## (-1 = never), tool that speeds it up, pickaxe tier needed to collect it, punishment from
## zombies before it breaks]. Logs are drawn as round trunks, so what is beside them shows.
const _BASE := [
	["Air", [0, 0, 0], SH_NONE, false, false, false, 0.0, "", 0, 0],
	["Grass", [0, 1, 2], SH_CUBE, true, true, true, 0.9, "shovel", 0, 30],
	["Dirt", [2, 2, 2], SH_CUBE, true, true, true, 0.8, "shovel", 0, 30],
	["Stone", [3, 3, 3], SH_CUBE, true, true, true, 6.0, "pick", 1, 120],
	["Cobblestone", [4, 4, 4], SH_CUBE, true, true, true, 6.0, "pick", 1, 100],
	["Log", [6, 5, 6], SH_CUBE, true, false, true, 3.0, "axe", 0, 80],
	["Leaves", [7, 7, 7], SH_CUBE, true, false, true, 0.35, "", 0, 10],
	["Planks", [8, 8, 8], SH_CUBE, true, true, true, 2.5, "axe", 0, 60],
	["Sand", [9, 9, 9], SH_CUBE, true, true, true, 0.8, "shovel", 0, 25],
	["Coal Ore", [10, 10, 10], SH_CUBE, true, true, true, 7.0, "pick", 1, 120],
	["Iron Ore", [11, 11, 11], SH_CUBE, true, true, true, 9.0, "pick", 2, 140],
	["Bedrock", [12, 12, 12], SH_CUBE, true, true, true, -1.0, "", 0, 99999],
	["Workbench", [13, 14, 8], SH_CUBE, true, true, true, 2.5, "axe", 0, 60],
	["Forge", [15, 16, 15], SH_CUBE, true, true, true, 6.0, "pick", 1, 120],
	["Campfire", [17, 17, 17], SH_CROSS, false, false, false, 1.0, "axe", 0, 20],
	["Torch", [18, 18, 18], SH_CROSS, false, false, false, 0.1, "", 0, 5],
	["Wood Spikes", [19, 19, 19], SH_CROSS, false, false, false, 1.0, "axe", 0, 60],
	["Stone Bricks", [20, 20, 20], SH_CUBE, true, true, true, 9.0, "pick", 1, 220],
	["Berry Bush", [21, 21, 21], SH_CROSS, false, false, false, 0.3, "", 0, 5],
	["Reinforced Wall", [22, 22, 22], SH_CUBE, true, true, true, 16.0, "pick", 2, 600],
	["Backpack", [23, 24, 23], SH_BOX, false, false, false, 0.5, "", 0, 99999],
	["Bed", [25, 26, 8], SH_BOX, true, false, false, 1.5, "axe", 0, 60],
	["Blood Forge", [27, 28, 27], SH_CUBE, true, true, true, 12.0, "pick", 2, 300],
	["Blood Brick", [29, 29, 29], SH_CUBE, true, true, true, 24.0, "pick", 3, 1200],
]
## SH_BOX blocks: [low corner, high corner] inside the cell.
const BOX := {BACKPACK: [Vector3(0.2, 0.0, 0.26), Vector3(0.8, 0.62, 0.74)], BED: [Vector3.ZERO, Vector3(1.0, 0.5, 1.0)],
	WOOD_BOX: [Vector3(0.06, 0.0, 0.1), Vector3(0.94, 0.82, 0.9)], IRON_BOX: [Vector3(0.06, 0.0, 0.1), Vector3(0.94, 0.82, 0.9)]}

## The crafting stations (E opens one) and the name their recipes use (crafting.gd).
const STATIONS := {WORKBENCH: "workbench", FORGE: "forge", CAMPFIRE: "campfire", BLOOD_FORGE: "bloodforge"}
## Storage boxes (E opens them) and how many slots each holds.
const BOX_SLOTS := {WOOD_BOX: 18, IRON_BOX: 27}
## Doors and hatches: closed id -> open id (and back).
const OPENS := {WOOD_DOOR: WOOD_DOOR_OPEN, IRON_DOOR: IRON_DOOR_OPEN, STEEL_DOOR: STEEL_DOOR_OPEN,
	WOOD_HATCH: WOOD_HATCH_OPEN, IRON_HATCH: IRON_HATCH_OPEN, STEEL_HATCH: STEEL_HATCH_OPEN}

static var NAMES: Array = []
static var TILES: Array = []
static var SHAPE: Array = []
static var SOLID: Array = []
static var OPAQUE: Array = []
## Solid full cubes (collision between neighbours is left out only between these).
static var FULL: Array = []
static var HARDNESS: Array = []
static var TOOL: Array = []
static var REQ_TIER: Array = []
static var ZHP: Array = []
## Hammer upgrades: block -> [the block it becomes, {item: count it costs}].
static var UPGRADE := {}
## Hammer repairs: block -> [item, count] one repair of zombie damage costs.
static var REPAIR := {}
## Open door or hatch -> its closed id (what it drops, and what toggles back).
static var CLOSED := {}


static func _static_init() -> void:
	for d in _BASE:
		_add(d)
	var shape_names := [["Half Block", SH_HALF], ["Ramp", SH_RAMP], ["Pillar", SH_PILLAR]]
	var full_names := ["Wood Frame", "", "Reinforced Wood", "Iron Wall", "Steel Wall", "Blood-forged Wall"]
	for t in range(0, 6):
		if t != 1:  # (planks are already there)
			_add([full_names[t], [_TIER_TILE[t], _TIER_TILE[t], _TIER_TILE[t]], SH_CUBE, true, true, true,
				_TIER_HARD[t], _TIER_TOOL[t], _TIER_REQ[t], _TIER_ZHP[t]])
	for sn in shape_names:
		for t in 6:
			_add(["%s %s" % [TIER_NAMES[t], sn[0]], [_TIER_TILE[t], _TIER_TILE[t], _TIER_TILE[t]], sn[1], true, false, false,
				_TIER_HARD[t] * 0.7, _TIER_TOOL[t], _TIER_REQ[t], _TIER_ZHP[t]])
	var metal := [["Wooden", 0, 120, 2.0, "axe", 0], ["Iron", 1, 350, 8.0, "pick", 2], ["Steel", 2, 650, 12.0, "pick", 3]]
	for m in metal:
		var tile: int = 35 + m[1]
		_add(["%s Door" % m[0], [tile, tile, tile], SH_DOOR, true, false, false, m[3], m[4], m[5], m[2]])
		_add(["%s Door (open)" % m[0], [tile, tile, tile], SH_DOOR, false, false, false, m[3], m[4], m[5], m[2]])
	for m in metal:
		var tile: int = 38 + m[1]
		_add(["%s Hatch" % m[0], [tile, tile, tile], SH_HATCH, true, false, false, m[3], m[4], m[5], m[2]])
		_add(["%s Hatch (open)" % m[0], [tile, tile, tile], SH_HATCH, false, false, false, m[3], m[4], m[5], m[2]])
	_add(["Wooden Box", [42, 41, 42], SH_BOX, true, false, false, 2.0, "axe", 0, 80])
	_add(["Iron Box", [44, 43, 44], SH_BOX, true, false, false, 8.0, "pick", 2, 300])
	assert(NAMES.size() == COUNT)
	for c in OPENS:
		CLOSED[OPENS[c]] = c
	# The upgrade chains and what they cost, in planks, ingots and shards.
	var full_cost := [{PLANKS: 2}, {PLANKS: 4}, {Items.IRON_INGOT: 2}, {Items.STEEL_INGOT: 2}, {Items.BLOOD_INGOT: 1}]
	var part_cost := [{PLANKS: 1}, {PLANKS: 2}, {Items.IRON_INGOT: 1}, {Items.STEEL_INGOT: 1}, {Items.BLOOD_INGOT: 1}]
	var repair := [[PLANKS, 1], [PLANKS, 1], [PLANKS, 2], [Items.IRON_INGOT, 1], [Items.STEEL_INGOT, 1], [Items.BLOOD_SHARD, 1]]
	for t in 6:
		var shapes := [TIER_BLOCKS[t], FRAME_HALF + t, FRAME_RAMP + t, FRAME_PILLAR + t]
		for s in 4:
			REPAIR[shapes[s]] = repair[t]
			if t < 5:
				var next := [TIER_BLOCKS[t + 1], FRAME_HALF + t + 1, FRAME_RAMP + t + 1, FRAME_PILLAR + t + 1]
				UPGRADE[shapes[s]] = [next[s], full_cost[t] if s == 0 or s == 2 else part_cost[t]]
	UPGRADE[COBBLE] = [STONE_BRICK, {COBBLE: 1}]
	UPGRADE[STONE_BRICK] = [REINFORCED, {Items.IRON_INGOT: 1}]
	UPGRADE[REINFORCED] = [BLOOD_BRICK, {Items.BLOOD_SHARD: 3}]
	UPGRADE[WOOD_DOOR] = [IRON_DOOR, {Items.IRON_INGOT: 3}]
	UPGRADE[IRON_DOOR] = [STEEL_DOOR, {Items.STEEL_INGOT: 3}]
	UPGRADE[WOOD_HATCH] = [IRON_HATCH, {Items.IRON_INGOT: 2}]
	UPGRADE[IRON_HATCH] = [STEEL_HATCH, {Items.STEEL_INGOT: 2}]
	UPGRADE[WOOD_BOX] = [IRON_BOX, {Items.IRON_INGOT: 2}]
	for id in [COBBLE, STONE_BRICK]:
		REPAIR[id] = [COBBLE, 1]
	REPAIR[REINFORCED] = [Items.IRON_INGOT, 1]
	REPAIR[BLOOD_BRICK] = [Items.BLOOD_SHARD, 1]
	for id in [WOOD_DOOR, WOOD_HATCH, WOOD_BOX, WORKBENCH, BED]:
		REPAIR[id] = [PLANKS, 1]
	for id in [IRON_DOOR, IRON_HATCH, IRON_BOX]:
		REPAIR[id] = [Items.IRON_INGOT, 1]
	for id in [STEEL_DOOR, STEEL_HATCH]:
		REPAIR[id] = [Items.STEEL_INGOT, 1]


static func _add(d: Array) -> void:
	NAMES.append(d[0])
	TILES.append(d[1])
	SHAPE.append(d[2])
	SOLID.append(d[3])
	OPAQUE.append(d[4])
	FULL.append(d[5])
	HARDNESS.append(d[6])
	TOOL.append(d[7])
	REQ_TIER.append(d[8])
	ZHP.append(d[9])


static func is_solid(id: int) -> bool:
	return id > 0 and id < COUNT and SOLID[id]


static func is_station(id: int) -> bool:
	return STATIONS.has(id)


static func is_door(id: int) -> bool:
	return id >= WOOD_DOOR and id <= STEEL_DOOR_OPEN


## What E does to it besides stations: doors and hatches open and close, boxes and bags open.
static func is_openable(id: int) -> bool:
	return OPENS.has(id) or CLOSED.has(id)


static func is_container(id: int) -> bool:
	return BOX_SLOTS.has(id) or id == BACKPACK


## Doors, hatches and ramps face the way the player looked when placing them.
static func has_facing(id: int) -> bool:
	return SHAPE[id] == SH_DOOR or SHAPE[id] == SH_HATCH or SHAPE[id] == SH_RAMP


## The item a block gives back (an open door or hatch is the closed one).
static func item_of(id: int) -> int:
	return CLOSED.get(id, id)


## The boxes [lo, hi] a block fills in its cell for its state (its picture, and for solid blocks
## its collision). [] for cubes, plants and air. A ramp's are steps under its slope.
static func boxes_of(id: int, meta: int) -> Array:
	var f := meta & META_FACING
	var up := (meta & META_UPPER) != 0
	match SHAPE[id]:
		SH_BOX:
			return [BOX[id]]
		SH_HALF:
			return [[Vector3(0, 0.5, 0), Vector3.ONE]] if up else [[Vector3.ZERO, Vector3(1, 0.5, 1)]]
		SH_PILLAR:
			return [[Vector3(0.25, 0, 0.25), Vector3(0.75, 1, 0.75)]]
		SH_RAMP:
			return [[Vector3.ZERO, Vector3(1, 0.5, 1)], rot_box([Vector3(0, 0.5, 0.5), Vector3.ONE], f)]
		SH_DOOR:
			# Closed: across the cell's near side (towards whoever placed it). Open: swung back
			# against its hinge side.
			if SOLID[id]:
				return [rot_box([Vector3.ZERO, Vector3(1, 1, PANEL)], f)]
			return [rot_box([Vector3.ZERO, Vector3(PANEL, 1, 1)], f)]
		SH_HATCH:
			if SOLID[id]:
				return [[Vector3(0, 1.0 - PANEL, 0), Vector3.ONE]] if up else [[Vector3.ZERO, Vector3(1, PANEL, 1)]]
			return [rot_box([Vector3(0, 0, 1.0 - PANEL), Vector3.ONE], f)]
	return []


## A box in a cell turned by facing f (quarter turns about the cell's upright middle).
static func rot_box(b: Array, f: int) -> Array:
	var a := rot_point(b[0], f)
	var c := rot_point(b[1], f)
	return [a.min(c), a.max(c)]


## Facing 0 looks along +Z; 1 along +X; 2 along -Z; 3 along -X.
static func rot_point(p: Vector3, f: int) -> Vector3:
	match f & 3:
		1:
			return Vector3(p.z, p.y, 1.0 - p.x)
		2:
			return Vector3(1.0 - p.x, p.y, 1.0 - p.z)
		3:
			return Vector3(1.0 - p.z, p.y, p.x)
	return p


## The facing (0-3) closest to a horizontal direction.
static func facing_of(dir: Vector3) -> int:
	if absf(dir.x) > absf(dir.z):
		return 1 if dir.x > 0.0 else 3
	return 0 if dir.z > 0.0 else 2
