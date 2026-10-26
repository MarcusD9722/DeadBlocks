class_name Skills
extends RefCounted
## Experience, levels and perks (M4.5), shared by the server (which owns them) and the client
## (which shows them and uses them for what it does itself: stamina, mining and hammer speed).
##
## Experience comes from kills (more for the tougher zombie types, more at night, twice as much
## from Blood Moon zombies), hunting boars, mining ore and upgrading blocks. Each level needs a
## little more than the last; each level after the first gives a skill point. A perk rank costs a
## point and needs a level (RANK_LEVEL). Levels, experience and perks are kept on death.

const MAX_LEVEL := 60
## Level needed for each rank of a perk (rank 1 at level 1, rank 5 at level 15).
const RANK_LEVEL := [1, 3, 6, 10, 15]

## Experience for killing a zombie of each type (a walker in the day's mood; night x1.5,
## Blood Moon x2), and for the other things that give some.
const ZOMBIE_XP := {"walker": 10, "runner": 20, "brute": 50, "crawler": 15, "screamer": 25, "spitter": 25}
const BOAR_XP := 15
const ORE_XP := {Blocks.COAL_ORE: 3, Blocks.IRON_ORE: 5, Blocks.CRYSTAL_ORE: 12}
const UPGRADE_XP := 3
const TREE_XP := 2

## The perks, by branch: id (on the network), key (in the save files), name, ranks, what a rank does.
const PERKS := [
	{"id": 1, "key": "brawler", "branch": "Fighting", "name": "Brawler", "max": 5, "text": "+10% damage with melee weapons and fists"},
	{"id": 2, "key": "marksman", "branch": "Fighting", "name": "Marksman", "max": 5, "text": "+10% damage with arrows, bolts and thrown spears"},
	{"id": 3, "key": "endurance", "branch": "Fighting", "name": "Endurance", "max": 3, "text": "+20% stamina, and sprinting tires you 10% less"},
	{"id": 4, "key": "tough", "branch": "Survival", "name": "Tough", "max": 5, "text": "+10 health"},
	{"id": 5, "key": "iron_gut", "branch": "Survival", "name": "Iron Gut", "max": 3, "text": "you get hungry 12% slower"},
	{"id": 6, "key": "healer", "branch": "Survival", "name": "Fast Healer", "max": 3, "text": "you heal 30% faster"},
	{"id": 7, "key": "miner", "branch": "Building", "name": "Miner", "max": 5, "text": "mine, dig and chop 10% faster"},
	{"id": 8, "key": "carpenter", "branch": "Building", "name": "Carpenter", "max": 3, "text": "the hammer works 15% faster"},
	{"id": 9, "key": "thrifty", "branch": "Building", "name": "Thrifty", "max": 3, "text": "a 15% chance that an upgrade costs nothing"},
]
const BRANCHES := ["Fighting", "Survival", "Building"]


## Experience needed to go from `level` to the next one.
static func xp_step(level: int) -> int:
	return 100 + 40 * (level - 1)


## Experience needed in all to reach `level`.
static func xp_for(level: int) -> int:
	var t := 0
	for l in range(1, level):
		t += xp_step(l)
	return t


static func level_of(xp: int) -> int:
	var l := 1
	while l < MAX_LEVEL and xp >= xp_for(l + 1):
		l += 1
	return l


## Skill points not spent yet.
static func points(xp: int, perks: Dictionary) -> int:
	var spent := 0
	for k in perks:
		spent += int(perks[k])
	return maxi(0, level_of(xp) - 1 - spent)


static func perk(key: String) -> Dictionary:
	for p in PERKS:
		if p["key"] == key:
			return p
	return {}


static func perk_by_id(id: int) -> Dictionary:
	for p in PERKS:
		if p["id"] == id:
			return p
	return {}


## Why the next rank of perk `key` can't be taken now ("" if it can).
static func cant_take(xp: int, perks: Dictionary, key: String) -> String:
	var p := perk(key)
	if p.is_empty():
		return "No such perk."
	var rank := int(perks.get(key, 0))
	if rank >= int(p["max"]):
		return "%s is at its highest rank." % p["name"]
	if level_of(xp) < RANK_LEVEL[rank]:
		return "Rank %d of %s needs level %d." % [rank + 1, p["name"], RANK_LEVEL[rank]]
	if points(xp, perks) <= 0:
		return "No skill points left. Kill zombies to level up."
	return ""


## Experience for killing a zombie of `type` in mood `kind` (day, night, horde).
static func zombie_xp(type: String, kind: String) -> int:
	var base := int(ZOMBIE_XP.get(type, 10))
	if kind == "horde":
		return base * 2
	if kind == "night":
		return int(base * 1.5)
	return base


# ------------------------------------------------------------ what the perks do

static func _rank(perks: Dictionary, key: String) -> int:
	return int(perks.get(key, 0))


static func melee_mult(perks: Dictionary) -> float:
	return 1.0 + 0.1 * _rank(perks, "brawler")


static func ranged_mult(perks: Dictionary) -> float:
	return 1.0 + 0.1 * _rank(perks, "marksman")


static func max_stamina(perks: Dictionary) -> float:
	return 100.0 * (1.0 + 0.2 * _rank(perks, "endurance"))


static func sprint_cost(perks: Dictionary) -> float:
	return 1.0 - 0.1 * _rank(perks, "endurance")


static func max_health(perks: Dictionary) -> float:
	return 100.0 + 10.0 * _rank(perks, "tough")


static func hunger_mult(perks: Dictionary) -> float:
	return 1.0 - 0.12 * _rank(perks, "iron_gut")


static func heal_mult(perks: Dictionary) -> float:
	return 1.0 + 0.3 * _rank(perks, "healer")


## Mining, digging and chopping speed (Rules.break_time divides by it).
static func mine_speed(perks: Dictionary) -> float:
	return 1.0 + 0.1 * _rank(perks, "miner")


static func hammer_speed(perks: Dictionary) -> float:
	return 1.0 + 0.15 * _rank(perks, "carpenter")


static func free_upgrade_chance(perks: Dictionary) -> float:
	return 0.15 * _rank(perks, "thrifty")
