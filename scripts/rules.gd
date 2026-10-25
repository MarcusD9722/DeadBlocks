class_name Rules
extends RefCounted
## Game rules shared by solo play, the client's instant feedback and the server's checks, so
## all three always agree: how long a block takes to break and what it drops.


## Seconds to break block `id` holding item `tool` (-1 = unbreakable).
static func break_time(id: int, tool: int) -> float:
	var hard: float = Blocks.HARDNESS[id]
	if hard < 0.0:
		return -1.0
	var mult := 1.0
	if Items.tool_type(tool) != "" and Items.tool_type(tool) == Blocks.TOOL[id]:
		mult = Items.TIER_MULT[Items.tier(tool)]
	return maxf(0.05, hard / mult)


## What breaking block `id` with `tool` gives: {"items": [[id, n], ...], "need_tier": 0}.
## need_tier > 0 means the block was too hard to collect with that tool (nothing drops).
static func collect(id: int, tool: int, rng: RandomNumberGenerator) -> Dictionary:
	var req: int = Blocks.REQ_TIER[id]
	if req > 0 and (Items.tool_type(tool) != "pick" or Items.tier(tool) < req):
		return {"items": [], "need_tier": req}
	var drops := []
	match id:
		Blocks.GRASS:
			drops = [[Blocks.DIRT, 1]]
		Blocks.STONE:
			drops = [[Blocks.COBBLE, 1]]
		Blocks.COAL_ORE:
			drops = [[Items.COAL, rng.randi_range(1, 2)]]
		Blocks.LEAVES:
			var r := rng.randf()
			if r < 0.28:
				drops = [[Items.FIBER, 1]]
			elif r < 0.42:
				drops = [[Items.STICK, 1]]
		Blocks.BERRY_BUSH:
			drops = [[Items.BERRIES, 2], [Items.FIBER, 1]]
		_:
			drops = [[id, 1]]
	return {"items": drops, "need_tier": 0}


static func too_hard_text(tier: int) -> String:
	return "Too hard to collect. You need a %s pickaxe." % Items.TIER_NAMES[clampi(tier, 1, 5)]
