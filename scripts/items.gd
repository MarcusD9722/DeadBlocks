class_name Items
extends RefCounted
## Non-block items. Ids below Blocks.COUNT are blocks.

const STICK := 100
const COAL := 101
const IRON_INGOT := 102
const RAW_MEAT := 103
const COOKED_MEAT := 104
const BERRIES := 105
const BANDAGE := 106
const FIBER := 107
const STEEL_INGOT := 108
## Dropped by Blood Moon zombies (M4.1, the old M3 plan's Blood Moon loot).
const BLOOD_SHARD := 109
const WOOD_PICK := 110
const STONE_PICK := 111
const IRON_PICK := 112
const WOOD_AXE := 113
const STONE_AXE := 114
const IRON_AXE := 115
const WOOD_CLUB := 116
const STONE_SWORD := 117
const IRON_SWORD := 118
const BLOOD_INGOT := 120
const STEEL_PICK := 121
const STEEL_AXE := 122
const STEEL_SWORD := 123
const BLOOD_PICK := 124
const BLOOD_AXE := 125
const BLOOD_SWORD := 126
const WOOD_SHOVEL := 127
const STONE_SHOVEL := 128
const IRON_SHOVEL := 129
const STEEL_SHOVEL := 130
const BLOOD_SHOVEL := 131
## M4.2: hammers upgrade blocks to the next tier and repair zombie damage (hold to work).
const WOOD_MALLET := 132
const STONE_HAMMER := 133
const IRON_HAMMER := 134
const STEEL_HAMMER := 135
const BLOOD_HAMMER := 136
## How fast each hammer tier works (seconds = HAMMER_S / speed).
const HAMMER_SPEED := [1.0, 1.0, 1.5, 2.0, 2.6, 3.2]
const HAMMER_S := 1.5

## Mining speed multiplier per tool tier (0 = bare hands): wood, stone, iron, steel, Blood Steel.
const TIER_MULT := [1.0, 2.5, 4.0, 6.5, 9.0, 12.0]
const TIER_NAMES := ["", "wooden", "stone", "iron", "steel", "Blood Steel"]

const DATA := {
	100: {"name": "Stick"},
	101: {"name": "Coal"},
	102: {"name": "Iron Ingot"},
	103: {"name": "Raw Meat", "food": 15.0, "heal": 0.0},
	104: {"name": "Cooked Meat", "food": 40.0, "heal": 8.0},
	105: {"name": "Berries", "food": 10.0, "heal": 2.0},
	106: {"name": "Bandage", "food": 0.0, "heal": 30.0},
	107: {"name": "Plant Fiber"},
	108: {"name": "Steel Ingot"},
	109: {"name": "Blood Shard"},
	120: {"name": "Blood Steel Ingot"},
	110: {"name": "Wooden Pickaxe", "tool": "pick", "tier": 1, "dmg": 4.0},
	111: {"name": "Stone Pickaxe", "tool": "pick", "tier": 2, "dmg": 5.0},
	112: {"name": "Iron Pickaxe", "tool": "pick", "tier": 3, "dmg": 7.0},
	113: {"name": "Wooden Axe", "tool": "axe", "tier": 1, "dmg": 5.0},
	114: {"name": "Stone Axe", "tool": "axe", "tier": 2, "dmg": 7.0},
	115: {"name": "Iron Axe", "tool": "axe", "tier": 3, "dmg": 9.0},
	116: {"name": "Wooden Club", "tool": "weapon", "tier": 1, "dmg": 7.0},
	117: {"name": "Stone Sword", "tool": "weapon", "tier": 2, "dmg": 11.0},
	118: {"name": "Iron Sword", "tool": "weapon", "tier": 3, "dmg": 16.0},
	121: {"name": "Steel Pickaxe", "tool": "pick", "tier": 4, "dmg": 8.0},
	122: {"name": "Steel Axe", "tool": "axe", "tier": 4, "dmg": 11.0},
	123: {"name": "Steel Sword", "tool": "weapon", "tier": 4, "dmg": 19.0},
	124: {"name": "Blood Steel Pickaxe", "tool": "pick", "tier": 5, "dmg": 10.0},
	125: {"name": "Blood Steel Axe", "tool": "axe", "tier": 5, "dmg": 13.0},
	126: {"name": "Blood Steel Sword", "tool": "weapon", "tier": 5, "dmg": 24.0},
	127: {"name": "Wooden Shovel", "tool": "shovel", "tier": 1, "dmg": 4.0},
	128: {"name": "Stone Shovel", "tool": "shovel", "tier": 2, "dmg": 5.0},
	129: {"name": "Iron Shovel", "tool": "shovel", "tier": 3, "dmg": 6.0},
	130: {"name": "Steel Shovel", "tool": "shovel", "tier": 4, "dmg": 7.0},
	131: {"name": "Blood Steel Shovel", "tool": "shovel", "tier": 5, "dmg": 8.0},
	132: {"name": "Wooden Mallet", "tool": "hammer", "tier": 1, "dmg": 5.0},
	133: {"name": "Stone Hammer", "tool": "hammer", "tier": 2, "dmg": 7.0},
	134: {"name": "Iron Hammer", "tool": "hammer", "tier": 3, "dmg": 9.0},
	135: {"name": "Steel Hammer", "tool": "hammer", "tier": 4, "dmg": 11.0},
	136: {"name": "Blood Steel Hammer", "tool": "hammer", "tier": 5, "dmg": 13.0},
}


static func is_block(id: int) -> bool:
	return id > 0 and id < Blocks.COUNT


static func name_of(id: int) -> String:
	if is_block(id):
		return Blocks.NAMES[id]
	if DATA.has(id):
		return DATA[id]["name"]
	return "?"


static func info(id: int) -> Dictionary:
	if DATA.has(id):
		return DATA[id]
	return {}


static func stack_max(id: int) -> int:
	if is_block(id):
		return 99
	var d := info(id)
	if d.has("tool"):
		return 1
	if d.has("food"):
		return 20
	return 99


static func tool_type(id: int) -> String:
	return str(info(id).get("tool", ""))


static func tier(id: int) -> int:
	return int(info(id).get("tier", 0))


static func damage(id: int) -> float:
	return float(info(id).get("dmg", 3.0))


## Seconds a hammer takes for one upgrade or repair.
static func hammer_time(id: int) -> float:
	return HAMMER_S / HAMMER_SPEED[clampi(tier(id), 0, 5)]


static func is_consumable(id: int) -> bool:
	return info(id).has("food")
