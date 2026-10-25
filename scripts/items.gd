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
## M4.3: spears (stab, or hold right-click to throw), the bow and the crossbow, and their ammo.
const WOOD_SPEAR := 137
const STONE_SPEAR := 138
const IRON_SPEAR := 139
const BOW := 140
const CROSSBOW := 141
const STONE_ARROW := 142
const IRON_ARROW := 143
const IRON_BOLT := 144
## M4.5: hide from boars (leather armor), and armor: ARMOR_FIRST + tier * 4 + slot, the tiers
## padded, leather, iron, steel, Blood Steel and the slots head, chest, legs, feet.
const BOAR_HIDE := 145
const ARMOR_FIRST := 150
const ARMOR_SLOTS := ["head", "chest", "legs", "feet"]
const ARMOR_SLOT_NAMES := ["Head", "Chest", "Legs", "Feet"]
const ARMOR_TIERS := ["Padded", "Leather", "Iron", "Steel", "Blood Steel"]
## How much of a zombie's (or acid's) damage a whole set of each tier stops, in percent; a head
## piece gives a fifth of it, the chest two fifths, legs a quarter, feet the rest.
const ARMOR_SET := [10.0, 22.0, 38.0, 52.0, 66.0]
const ARMOR_SHARE := [0.2, 0.4, 0.25, 0.15]

## What can fly (thrown or shot): its index here is the projectile's type on the network.
const PROJECTILES := [STONE_ARROW, IRON_ARROW, IRON_BOLT, WOOD_SPEAR, STONE_SPEAR, IRON_SPEAR]
## Seconds to draw the bow fully; the crossbow's reload; holding a spear back to throw it hard.
const BOW_DRAW_S := 0.9
const CROSSBOW_RELOAD_S := 1.6
const SPEAR_CHARGE_S := 0.8
## Reach for hitting a mob: a spear reaches further than other things in hand.
const REACH := 3.2
const SPEAR_REACH := 4.2

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
	# "throw": damage of a thrown spear at full strength; "ammo": what a bow or crossbow shoots;
	# "ammo_of": what an arrow or bolt is shot from, and "dmg" its damage at full draw.
	137: {"name": "Wooden Spear", "tool": "spear", "tier": 1, "dmg": 7.0, "throw": 15.0},
	138: {"name": "Stone Spear", "tool": "spear", "tier": 2, "dmg": 10.0, "throw": 22.0},
	139: {"name": "Iron Spear", "tool": "spear", "tier": 3, "dmg": 14.0, "throw": 30.0},
	140: {"name": "Bow", "tool": "bow", "tier": 1, "dmg": 3.0, "ammo": "arrow"},
	141: {"name": "Crossbow", "tool": "crossbow", "tier": 3, "dmg": 4.0, "ammo": "bolt"},
	142: {"name": "Stone Arrow", "ammo_of": "arrow", "dmg": 12.0},
	143: {"name": "Iron Arrow", "ammo_of": "arrow", "dmg": 18.0},
	144: {"name": "Iron Bolt", "ammo_of": "bolt", "dmg": 28.0},
	145: {"name": "Boar Hide"},
	# Armor (M4.5): "armor" is the slot (0 head, 1 chest, 2 legs, 3 feet), "atier" the tier.
	150: {"name": "Padded Hood", "armor": 0, "atier": 0},
	151: {"name": "Padded Vest", "armor": 1, "atier": 0},
	152: {"name": "Padded Leggings", "armor": 2, "atier": 0},
	153: {"name": "Padded Boots", "armor": 3, "atier": 0},
	154: {"name": "Leather Cap", "armor": 0, "atier": 1},
	155: {"name": "Leather Jacket", "armor": 1, "atier": 1},
	156: {"name": "Leather Pants", "armor": 2, "atier": 1},
	157: {"name": "Leather Boots", "armor": 3, "atier": 1},
	158: {"name": "Iron Helmet", "armor": 0, "atier": 2},
	159: {"name": "Iron Chestplate", "armor": 1, "atier": 2},
	160: {"name": "Iron Leggings", "armor": 2, "atier": 2},
	161: {"name": "Iron Boots", "armor": 3, "atier": 2},
	162: {"name": "Steel Helmet", "armor": 0, "atier": 3},
	163: {"name": "Steel Chestplate", "armor": 1, "atier": 3},
	164: {"name": "Steel Leggings", "armor": 2, "atier": 3},
	165: {"name": "Steel Boots", "armor": 3, "atier": 3},
	166: {"name": "Blood Steel Helmet", "armor": 0, "atier": 4},
	167: {"name": "Blood Steel Chestplate", "armor": 1, "atier": 4},
	168: {"name": "Blood Steel Leggings", "armor": 2, "atier": 4},
	169: {"name": "Blood Steel Boots", "armor": 3, "atier": 4},
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
	if d.has("tool") or d.has("armor"):
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


## Reach for hitting a mob with this in hand.
static func reach(id: int) -> float:
	return SPEAR_REACH if tool_type(id) == "spear" else REACH


## The bow or crossbow's ammo ("arrow", "bolt"), or "".
static func ammo_kind(id: int) -> String:
	return str(info(id).get("ammo", ""))


## The inventory slot whose ammo a bow or crossbow shoots next: the first slot holding arrows
## (or bolts), the hotbar first. -1 if there is none. The client and the server pick alike.
static func ammo_slot(inv, tool: int) -> int:
	var kind := ammo_kind(tool)
	if kind == "":
		return -1
	for i in Inventory.SIZE:
		var id: int = inv.id_at(i)
		if id > 0 and str(info(id).get("ammo_of", "")) == kind:
			return i
	return -1


## Armor (M4.5): which slot it goes in (-1: not armor), its tier, and how much damage it stops.
static func armor_slot(id: int) -> int:
	return int(info(id).get("armor", -1))


static func armor_tier(id: int) -> int:
	return int(info(id).get("atier", -1))


static func armor_def(id: int) -> float:
	var s := armor_slot(id)
	if s < 0:
		return 0.0
	return ARMOR_SET[armor_tier(id)] * ARMOR_SHARE[s]


## The share of damage the worn armor stops (0..0.8), from the four slots' item ids.
static func armor_total(worn: Array) -> float:
	var t := 0.0
	for id in worn:
		t += armor_def(int(id))
	return minf(0.8, t / 100.0)


## Can it be thrown or shot (an arrow, a bolt, a spear)?
static func projectile_type(id: int) -> int:
	return PROJECTILES.find(id)
