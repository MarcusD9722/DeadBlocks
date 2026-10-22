extends Node
## Runs the zombies each physics tick in a fixed order, grouped into regions, so the result does not
## depend on processing order. That is what lets M3 run regions on separate cores.
##
## A tick:
##   1. Every REGION_EVERY seconds: group players into regions (players within REGION_LINK metres of each
##      other share one) and give every zombie the region of its nearest player.
##   2. Per region: a spatial hash of where its zombies are at the start of the tick.
##   3. Per region, zombies by id: think and move. Zombies only read the world and the start-of-tick
##      hash, and block damage is queued instead of applied.
##   4. Move the Spitters' acid globs (in the order they were spat), then make this tick's new
##      globs and the zombies Screamers called, sorted by zombie id.
##   5. Apply the queued block damage, sorted by zombie id.
## Animals still run their own _physics_process for now.

const REGION_LINK := 64.0
const REGION_EVERY := 1.0
const CELL := 1.0

class Region:
	var id := 0
	var players: Array = []
	var zombies: Array = []
	## Vector2i cell -> Array of [zombie id, Vector3 start-of-tick position]
	var grid := {}

## Things zombies can target: the local Player, and virtual players in tests and benchmarks
## (later: remote players). Each needs global_position, dead and take_damage(amount, from).
var players: Array = []
var regions: Array = []
## Tests: process regions in reverse order (results must not change).
var reverse_regions := false
var tick_count := 0
## Tests: stop moving zombies once tick_count reaches this (-1 = never).
var run_until := -1
## Every block hit applied so far, for tests: [x, y, z, amount, zombie id].
var edit_log: Array = []
var keep_edit_log := false

var _next_zombie_id := 1
var _region_t := 0.0
var _edits: Array = []
var _calls: Array = []     # [zombie id, seq, spots (Vector2 x/z), mood]
var _spits: Array = []     # [zombie id, seq, from, velocity, damage, block damage]
## Acid globs in flight, oldest first.
var acids: Array = []
## Counts for tests: acid globs spat, and zombies Screamers called.
var acids_made := 0
var zombies_called := 0


func _ready() -> void:
	G.sim = self


func add_player(p: Node) -> void:
	if not players.has(p):
		players.append(p)
	_region_t = 0.0


func remove_player(p: Node) -> void:
	players.erase(p)
	_region_t = 0.0


## Called before the zombie enters the tree: fixes its id (processing order) and its random seed.
func register_zombie(z: Node) -> void:
	z.id = _next_zombie_id
	_next_zombie_id += 1
	z.rng.seed = hash(z.id) ^ (G.game.seed_v * 2654435761)


## Zombie block hits wait here until every zombie has moved this tick.
func queue_block_damage(p: Vector3i, amount: float, zombie_id: int) -> void:
	_edits.append([zombie_id, _edits.size(), p, amount])


## A Screamer's call: walkers of `mood` come to these spots (x, z) after this tick.
func queue_call(zombie_id: int, spots: Array, mood: String) -> void:
	_calls.append([zombie_id, _calls.size(), spots, mood])


## A Spitter's acid glob, made after this tick.
func queue_spit(zombie_id: int, from: Vector3, vel: Vector3, dmg: float, block_dmg: float) -> void:
	_spits.append([zombie_id, _spits.size(), from, vel, dmg, block_dmg])


func _physics_process(delta: float) -> void:
	if run_until >= 0 and tick_count >= run_until:
		return
	var zombies := get_tree().get_nodes_in_group("zombies")
	_region_t -= delta
	if _region_t <= 0.0:
		_region_t = REGION_EVERY
		_rebuild_regions(zombies)
	else:
		_assign_new(zombies)
	var order := regions.duplicate()
	if reverse_regions:
		order.reverse()
	for r in order:
		_build_grid(r)
	for r in order:
		for z in r.zombies:
			if is_instance_valid(z) and not z.dead and z.is_inside_tree():
				z.sim_tick(delta)
	_tick_acids(delta)
	_flush_spits()
	_flush_calls()
	_flush_edits()
	tick_count += 1


func _live_players() -> Array:
	var out := []
	for p in players:
		if is_instance_valid(p) and p.is_inside_tree():
			out.append(p)
	return out


func _rebuild_regions(zombies: Array) -> void:
	var ps := _live_players()
	# Single-linkage grouping: players within REGION_LINK of any member join the region.
	var label := []
	label.resize(ps.size())
	label.fill(-1)
	var groups := []
	for i in ps.size():
		if label[i] >= 0:
			continue
		var members := [ps[i]]
		label[i] = groups.size()
		var k := 0
		while k < members.size():
			var a: Vector3 = members[k].global_position
			for j in ps.size():
				if label[j] < 0 and _hdist(a, ps[j].global_position) <= REGION_LINK:
					label[j] = groups.size()
					members.append(ps[j])
			k += 1
		groups.append(members)
	regions.clear()
	for gi in groups.size():
		var r := Region.new()
		r.id = gi
		r.players = groups[gi]
		regions.append(r)
	for z in zombies:
		z.region = null
	_assign_new(zombies)


## Give each zombie without a region the region of its nearest player, then keep each region's
## zombie list sorted by id.
func _assign_new(zombies: Array) -> void:
	var changed := false
	for z in zombies:
		if z.region != null and regions.has(z.region):
			continue
		var best = null
		var bd := INF
		for r in regions:
			for p in r.players:
				var d := _hdist(z.global_position, p.global_position)
				if d < bd:
					bd = d
					best = r
		z.region = best
		changed = true
	if not changed:
		return
	for r in regions:
		r.zombies.clear()
	for z in zombies:
		if z.region != null:
			z.region.zombies.append(z)
	for r in regions:
		r.zombies.sort_custom(func(a, b): return a.id < b.id)


func _build_grid(r: Region) -> void:
	r.grid.clear()
	for z in r.zombies:
		if not is_instance_valid(z) or z.dead:
			continue
		var p: Vector3 = z.global_position
		var c := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
		var cell = r.grid.get(c)
		if cell == null:
			r.grid[c] = [[z.id, p]]
		else:
			cell.append([z.id, p])


func _tick_acids(delta: float) -> void:
	if acids.is_empty():
		return
	var ps := _live_players()
	var keep := []
	for a in acids:
		if not is_instance_valid(a):
			continue
		if a.step(delta, ps):
			keep.append(a)
		else:
			a.queue_free()
	acids = keep


func _flush_spits() -> void:
	if _spits.is_empty():
		return
	_spits.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for s in _spits:
		var acid := preload("res://scripts/acid.gd").new()
		acid.owner_id = s[0]
		acid.vel = s[3]
		acid.dmg = s[4]
		acid.block_dmg = s[5]
		acid.net_id = G.game._new_mob_id()
		G.game.mobs.add_child(acid)
		acid.global_position = s[2]
		acids.append(acid)
		acids_made += 1
	_spits.clear()


## Called zombies come up out of the ground at the spots, if there is ground and room for them
## (and the world isn't full).
func _flush_calls() -> void:
	if _calls.is_empty():
		return
	_calls.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var w = G.world
	var count := get_tree().get_nodes_in_group("zombies").size()
	for c in _calls:
		for spot in c[2]:
			if count >= G.game.MAX_ZOMBIES:
				break
			var x := floori(spot.x)
			var z := floori(spot.y)
			var y: int = w.surface_y(x, z)
			if y < 0 or w.get_block(x, y, z) == Blocks.LEAVES:
				continue
			var at := Vector3(x + 0.5, y + 1.02, z + 0.5)
			if not w.is_ready_at(at) or Blocks.is_solid(w.get_block(x, y + 1, z)) or Blocks.is_solid(w.get_block(x, y + 2, z)):
				continue
			var zb = G.game.spawn_zombie(c[3], at)
			if zb != null:
				zb.hunting = true
				count += 1
				zombies_called += 1
	_calls.clear()


func _flush_edits() -> void:
	if _edits.is_empty():
		return
	_edits.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for e in _edits:
		var p: Vector3i = e[2]
		G.world.damage_block(p, e[3])
		if keep_edit_log:
			edit_log.append([p.x, p.y, p.z, e[3], e[0]])
	_edits.clear()


static func _hdist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
