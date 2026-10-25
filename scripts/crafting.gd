class_name Crafting
extends RefCounted

## Recipes by where they are made (M4.1): "" by hand (the I screen), or at a station (E on it).
const STATION_NAMES := {"workbench": "Workbench", "forge": "Forge", "campfire": "Campfire", "bloodforge": "Blood Forge"}
## A station counts as at hand within this many blocks (player, server and the station screen).
const STATION_RADIUS := 5

const RECIPES := [
	# By hand: the basics and the wooden tools.
	{"out": Blocks.PLANKS, "n": 4, "needs": {Blocks.LOG: 1}, "st": ""},
	{"out": Items.STICK, "n": 4, "needs": {Blocks.PLANKS: 2}, "st": ""},
	{"out": Blocks.WORKBENCH, "n": 1, "needs": {Blocks.PLANKS: 4}, "st": ""},
	{"out": Blocks.TORCH, "n": 4, "needs": {Items.STICK: 1, Items.COAL: 1}, "st": ""},
	{"out": Blocks.CAMPFIRE, "n": 1, "needs": {Blocks.LOG: 2, Items.STICK: 2}, "st": ""},
	{"out": Items.BANDAGE, "n": 1, "needs": {Items.FIBER: 3}, "st": ""},
	{"out": Items.WOOD_CLUB, "n": 1, "needs": {Blocks.PLANKS: 2, Items.STICK: 1}, "st": ""},
	{"out": Items.WOOD_PICK, "n": 1, "needs": {Blocks.PLANKS: 3, Items.STICK: 2}, "st": ""},
	{"out": Items.WOOD_AXE, "n": 1, "needs": {Blocks.PLANKS: 3, Items.STICK: 2}, "st": ""},
	{"out": Items.WOOD_SHOVEL, "n": 1, "needs": {Blocks.PLANKS: 2, Items.STICK: 2}, "st": ""},
	# Workbench: stone, iron and steel tools and weapons, building blocks, the other stations.
	{"out": Items.STONE_PICK, "n": 1, "needs": {Blocks.COBBLE: 3, Items.STICK: 2}, "st": "workbench"},
	{"out": Items.STONE_AXE, "n": 1, "needs": {Blocks.COBBLE: 3, Items.STICK: 2}, "st": "workbench"},
	{"out": Items.STONE_SHOVEL, "n": 1, "needs": {Blocks.COBBLE: 2, Items.STICK: 2}, "st": "workbench"},
	{"out": Items.STONE_SWORD, "n": 1, "needs": {Blocks.COBBLE: 2, Items.STICK: 1}, "st": "workbench"},
	{"out": Items.IRON_PICK, "n": 1, "needs": {Items.IRON_INGOT: 3, Items.STICK: 2}, "st": "workbench"},
	{"out": Items.IRON_AXE, "n": 1, "needs": {Items.IRON_INGOT: 3, Items.STICK: 2}, "st": "workbench"},
	{"out": Items.IRON_SHOVEL, "n": 1, "needs": {Items.IRON_INGOT: 2, Items.STICK: 2}, "st": "workbench"},
	{"out": Items.IRON_SWORD, "n": 1, "needs": {Items.IRON_INGOT: 2, Items.STICK: 1}, "st": "workbench"},
	{"out": Items.STEEL_PICK, "n": 1, "needs": {Items.STEEL_INGOT: 3, Items.STICK: 2}, "st": "workbench"},
	{"out": Items.STEEL_AXE, "n": 1, "needs": {Items.STEEL_INGOT: 3, Items.STICK: 2}, "st": "workbench"},
	{"out": Items.STEEL_SHOVEL, "n": 1, "needs": {Items.STEEL_INGOT: 2, Items.STICK: 2}, "st": "workbench"},
	{"out": Items.STEEL_SWORD, "n": 1, "needs": {Items.STEEL_INGOT: 2, Items.STICK: 1}, "st": "workbench"},
	{"out": Blocks.SPIKES, "n": 2, "needs": {Items.STICK: 4, Blocks.PLANKS: 1}, "st": "workbench"},
	{"out": Blocks.BED, "n": 1, "needs": {Blocks.PLANKS: 3, Items.FIBER: 3}, "st": "workbench"},
	{"out": Blocks.STONE_BRICK, "n": 4, "needs": {Blocks.COBBLE: 4}, "st": "workbench"},
	{"out": Blocks.REINFORCED, "n": 2, "needs": {Blocks.STONE_BRICK: 2, Items.IRON_INGOT: 1}, "st": "workbench"},
	{"out": Blocks.FORGE, "n": 1, "needs": {Blocks.COBBLE: 8}, "st": "workbench"},
	{"out": Blocks.BLOOD_FORGE, "n": 1, "needs": {Blocks.STONE_BRICK: 8, Items.IRON_INGOT: 4, Items.BLOOD_SHARD: 10}, "st": "workbench"},
	# Forge: smelting.
	{"out": Items.IRON_INGOT, "n": 1, "needs": {Blocks.IRON_ORE: 1, Items.COAL: 1}, "st": "forge"},
	{"out": Items.STEEL_INGOT, "n": 1, "needs": {Items.IRON_INGOT: 2, Items.COAL: 2}, "st": "forge"},
	{"out": Items.BLOOD_INGOT, "n": 1, "needs": {Items.STEEL_INGOT: 1, Items.BLOOD_SHARD: 3}, "st": "forge"},
	# Campfire: cooking.
	{"out": Items.COOKED_MEAT, "n": 1, "needs": {Items.RAW_MEAT: 1}, "st": "campfire"},
	# Blood Forge: the Blood Steel tools and weapons, Blood Brick.
	{"out": Items.BLOOD_PICK, "n": 1, "needs": {Items.BLOOD_INGOT: 3, Items.STICK: 2}, "st": "bloodforge"},
	{"out": Items.BLOOD_AXE, "n": 1, "needs": {Items.BLOOD_INGOT: 3, Items.STICK: 2}, "st": "bloodforge"},
	{"out": Items.BLOOD_SHOVEL, "n": 1, "needs": {Items.BLOOD_INGOT: 2, Items.STICK: 2}, "st": "bloodforge"},
	{"out": Items.BLOOD_SWORD, "n": 1, "needs": {Items.BLOOD_INGOT: 2, Items.STICK: 1}, "st": "bloodforge"},
	{"out": Blocks.BLOOD_BRICK, "n": 4, "needs": {Blocks.STONE_BRICK: 4, Items.BLOOD_INGOT: 1}, "st": "bloodforge"},
]


## The recipes made at station (or "" by hand), in list order.
static func recipes_for(station: String) -> Array:
	var out := []
	for r in RECIPES:
		if r["st"] == station:
			out.append(r)
	return out


static func has_items(inv: Inventory, r: Dictionary) -> bool:
	var needs: Dictionary = r["needs"]
	for id in needs:
		if inv.count(int(id)) < int(needs[id]):
			return false
	return true


static func can_craft(inv: Inventory, r: Dictionary, stations: Array) -> bool:
	var st: String = r["st"]
	if st != "" and not stations.has(st):
		return false
	return has_items(inv, r)


static func craft(inv: Inventory, r: Dictionary) -> bool:
	if not inv.can_fit(int(r["out"]), int(r["n"])):
		return false
	var needs: Dictionary = r["needs"]
	for id in needs:
		inv.remove(int(id), int(needs[id]))
	inv.add(int(r["out"]), int(r["n"]))
	return true
