class_name Blocks
extends RefCounted
## Block definitions. A block id is also its item id.

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
const COUNT := 22

const SH_NONE := 0
const SH_CUBE := 1
const SH_CROSS := 2
## A smaller box inside the cell (sizes in BOX), with a whole tile on each face.
const SH_BOX := 3

const NAMES := ["Air", "Grass", "Dirt", "Stone", "Cobblestone", "Log", "Leaves", "Planks", "Sand",
	"Coal Ore", "Iron Ore", "Bedrock", "Workbench", "Forge", "Campfire", "Torch", "Wood Spikes",
	"Stone Bricks", "Berry Bush", "Reinforced Wall", "Backpack", "Bed"]

# Atlas tiles as [top, side, bottom]
const TILES := [[0, 0, 0], [0, 1, 2], [2, 2, 2], [3, 3, 3], [4, 4, 4], [6, 5, 6], [7, 7, 7], [8, 8, 8],
	[9, 9, 9], [10, 10, 10], [11, 11, 11], [12, 12, 12], [13, 14, 8], [15, 16, 15], [17, 17, 17],
	[18, 18, 18], [19, 19, 19], [20, 20, 20], [21, 21, 21], [22, 22, 22], [23, 24, 23], [25, 26, 8]]

const SHAPE := [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 2, 1, 3, 3]
const SOLID := [false, true, true, true, true, true, true, true, true, true, true, true, true, true,
	false, false, false, true, false, true, false, true]
const OPAQUE := [false, true, true, true, true, true, false, true, true, true, true, true, true, true,
	false, false, false, true, false, true, false, false]
# Solid full cubes (collision between neighbours is left out only between these).
const FULL := [false, true, true, true, true, true, true, true, true, true, true, true, true, true,
	false, false, false, true, false, true, false, false]
# Seconds to break by hand. -1 = unbreakable.
const HARDNESS := [0.0, 0.9, 0.8, 6.0, 6.0, 3.0, 0.35, 2.5, 0.8, 7.0, 9.0, -1.0, 2.5, 6.0, 1.0,
	0.1, 1.0, 9.0, 0.3, 16.0, 0.5, 1.5]
# Tool that speeds up breaking.
const TOOL := ["", "", "", "pick", "pick", "axe", "", "axe", "", "pick", "pick", "", "axe", "pick",
	"axe", "", "axe", "pick", "", "pick", "", "axe"]
# Pickaxe tier needed to collect the block (0 = anything).
const REQ_TIER := [0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 2, 0, 0, 1, 0, 0, 0, 1, 0, 2, 0, 0]
# How much punishment the block takes from zombies before it breaks.
const ZHP := [0, 30, 30, 120, 100, 80, 10, 60, 25, 120, 140, 99999, 60, 120, 20, 5, 60, 220, 5, 600, 99999, 60]
## SH_BOX blocks: [low corner, high corner] inside the cell.
const BOX := {BACKPACK: [Vector3(0.2, 0.0, 0.26), Vector3(0.8, 0.62, 0.74)], BED: [Vector3.ZERO, Vector3(1.0, 0.5, 1.0)]}


static func is_solid(id: int) -> bool:
	return id > 0 and id < COUNT and SOLID[id]


static func is_station(id: int) -> bool:
	return id == WORKBENCH or id == FORGE or id == CAMPFIRE
