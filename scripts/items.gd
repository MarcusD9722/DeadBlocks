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
const WOOD_PICK := 110
const STONE_PICK := 111
const IRON_PICK := 112
const WOOD_AXE := 113
const STONE_AXE := 114
const IRON_AXE := 115
const WOOD_CLUB := 116
const STONE_SWORD := 117
const IRON_SWORD := 118

# Mining speed multiplier per tool tier (0 = bare hands)
const TIER_MULT := [1.0, 2.5, 4.0, 6.5]

const DATA := {
	100: {"name": "Stick"},
	101: {"name": "Coal"},
	102: {"name": "Iron Ingot"},
	103: {"name": "Raw Meat", "food": 15.0, "heal": 0.0},
	104: {"name": "Cooked Meat", "food": 40.0, "heal": 8.0},
	105: {"name": "Berries", "food": 10.0, "heal": 2.0},
	106: {"name": "Bandage", "food": 0.0, "heal": 30.0},
	107: {"name": "Plant Fiber"},
	110: {"name": "Wooden Pickaxe", "tool": "pick", "tier": 1, "dmg": 4.0},
	111: {"name": "Stone Pickaxe", "tool": "pick", "tier": 2, "dmg": 5.0},
	112: {"name": "Iron Pickaxe", "tool": "pick", "tier": 3, "dmg": 7.0},
	113: {"name": "Wooden Axe", "tool": "axe", "tier": 1, "dmg": 5.0},
	114: {"name": "Stone Axe", "tool": "axe", "tier": 2, "dmg": 7.0},
	115: {"name": "Iron Axe", "tool": "axe", "tier": 3, "dmg": 9.0},
	116: {"name": "Wooden Club", "tool": "weapon", "tier": 1, "dmg": 7.0},
	117: {"name": "Stone Sword", "tool": "weapon", "tier": 2, "dmg": 11.0},
	118: {"name": "Iron Sword", "tool": "weapon", "tier": 3, "dmg": 16.0},
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


static func is_consumable(id: int) -> bool:
	return info(id).has("food")
