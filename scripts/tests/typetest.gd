extends Node
## Zombie-type test (M3): `-- --typetest --server-mode --seed=4242`. In arenas built of stone in
## the air (so the terrain plays no part), each type shows what it is for, next to a stand-in
## player (scripts/server/virtual_player.gd):
##   crawler   gets through a 1-block-high tunnel without breaking anything; a walker has to smash
##   runner    covers 20 m much faster than a walker
##   brute     breaks a plank wall block in 2 blows (a walker needs 6)
##   screamer  calls zombies once it sees a player
##   spitter   hits a player 10 m away with acid; acid that hits a wall eats into the block
## Prints TYPETEST PASS/FAIL lines and ends with `TYPETEST DONE fails=N`.

const VirtualPlayer := preload("res://scripts/server/virtual_player.gd")
const AcidScript := preload("res://scripts/acid.gd")
const TICK := 1.0 / 30.0

var fails := 0
var _base := Vector3i.ZERO
var _next_x := 0
var _vps: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func check(ok: bool, what: String) -> void:
	print("TYPETEST %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _run() -> void:
	var g = G.game
	var w = G.world
	var sim = G.sim
	sim.keep_edit_log = true
	while g.state == "loading":
		await _wait(0.25)
	g.start_game()
	g.time = 12.0
	sim.remove_player(G.player)  # only the stand-ins count
	for m in get_tree().get_nodes_in_group("mobs"):
		m.queue_free()
	var sp: Vector3 = g.spawn_pos
	_base = Vector3i(floori(sp.x) + 60, 50, floori(sp.z))
	g.extra_stream_points = [Vector3(_base) + Vector3(20, 0, 0)]
	var t0 := Time.get_ticks_msec()
	await _wait(1.0)
	while w.load_progress() < 1.0 and Time.get_ticks_msec() - t0 < 180000:
		await _wait(0.25)
	w.sync_mesh = true  # blocks set below get their collision at once

	await _tunnel("crawler")
	await _tunnel("walker")
	var t_run: float = await _race("runner")
	var t_walk: float = await _race("walker")
	check(t_run > 0.0 and (t_walk < 0.0 or t_run < t_walk * 0.7), "a Runner covers 20 m much faster than a walker (%.1f s against %.1f s)" % [t_run, t_walk])
	var b_brute: int = await _wall("brute")
	var b_walk: int = await _wall("walker")
	check(b_brute == 2, "a Brute breaks a plank in %d blows (2 expected)" % b_brute)
	check(b_walk == 6, "a walker needs %d blows (6 expected)" % b_walk)
	await _door()
	await _screamer()
	await _spitter()
	_blood_loot()
	print("TYPETEST DONE fails=%d" % fails)
	get_tree().quit(0 if fails == 0 else 1)


## Stands in for the player who lands the last hit: counts what the kill gives.
class Looter extends Node:
	var got := {}

	func give(id: int, n: int) -> void:
		got[id] = int(got.get(id, 0)) + n


## Blood Moon loot (M4.1): Blood Moon zombies drop Blood Shards to their killer (a Brute 3, a
## Screamer or Spitter 2, half the others 1); the same zombies on a normal night drop none.
func _blood_loot() -> void:
	_clear()
	var at := Vector3(_arena()) + Vector3(0.5, 1.0, 0.5)
	var expect := {"brute": 3, "screamer": 2, "spitter": 2}
	for mood in ["horde", "night"]:
		for type in ["brute", "screamer", "spitter"]:
			var looter := Looter.new()
			var z = G.game.spawn_zombie(mood, at, Vector3.INF, type)
			z.hurt(9999.0, at + Vector3(1, 0, 0), looter)
			var n: int = looter.got.get(Items.BLOOD_SHARD, 0)
			var want: int = expect[type] if mood == "horde" else 0
			check(n == want, "a %s %s drops %d Blood Shards (%d expected)" % [mood, type, n, want])
			looter.free()
	var shards := 0
	for i in 40:
		var looter := Looter.new()
		var z = G.game.spawn_zombie("horde", at, Vector3.INF, "walker")
		z.hurt(9999.0, at + Vector3(1, 0, 0), looter)
		shards += int(looter.got.get(Items.BLOOD_SHARD, 0))
		looter.free()
	check(shards > 8 and shards < 32, "about half of 40 horde walkers drop a shard (%d)" % shards)


## A fresh arena along +x, 8 blocks to the side of the last one: returns its floor's first cell.
func _arena() -> Vector3i:
	_clear()
	var o := _base + Vector3i(0, 0, _next_x)
	_next_x += 8
	return o


func _clear() -> void:
	for z in get_tree().get_nodes_in_group("zombies"):
		z.queue_free()
	for a in G.sim.acids:
		if is_instance_valid(a):
			a.queue_free()
	G.sim.acids.clear()
	for vp in _vps:
		G.sim.remove_player(vp)
		vp.queue_free()
	_vps.clear()
	G.sim.edit_log.clear()


func _fill(a: Vector3i, b: Vector3i, id: int) -> void:
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
			for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
				G.world.set_block(Vector3i(x, y, z), id)


## A corridor one block wide along +x from o: stone floor at o.y, walls, open `h` blocks high
## (a stone ceiling above), `length` long, closed at both ends.
func _corridor(o: Vector3i, length: int, h: int) -> void:
	_fill(o + Vector3i(-1, 0, -1), o + Vector3i(length, h + 1, 1), Blocks.STONE)
	_fill(o + Vector3i(0, 1, 0), o + Vector3i(length - 1, h, 0), Blocks.AIR)


func _stand_in(at: Vector3) -> Node3D:
	var vp := VirtualPlayer.new()
	G.game.add_child(vp)
	vp.global_position = at
	G.sim.add_player(vp)
	_vps.append(vp)
	return vp


func _zombie(type: String, at: Vector3) -> Node:
	var z = G.game.spawn_zombie("night", at, Vector3.INF, type)
	z.hunting = true
	return z


func _ticks(secs: float, until := Callable()) -> void:
	var n := int(secs / TICK)
	for i in n:
		await get_tree().physics_frame
		if until.is_valid() and until.call():
			return


## A 1-block-high tunnel between a zombie and a stand-in: a crawler gets through untouched; a
## walker has to smash its way.
func _tunnel(type: String) -> void:
	var o := _arena()
	_corridor(o, 16, 2)
	_fill(o + Vector3i(4, 2, 0), o + Vector3i(11, 2, 0), Blocks.STONE)  # the tunnel: room for 1 block only
	var vp := _stand_in(Vector3(o) + Vector3(14.5, 1.0, 0.5))
	_zombie(type, Vector3(o) + Vector3(1.5, 1.02, 0.5))
	await _ticks(20.0, func(): return vp.hits > 0)
	var smashed: int = G.sim.edit_log.size()
	if type == "crawler":
		check(vp.hits > 0 and smashed == 0, "a Crawler gets through a 1-block-high tunnel without breaking anything (%d hits, %d blows)" % [vp.hits, smashed])
	else:
		check(smashed > 0, "a walker can't: it has to smash the tunnel (%d blows, %d hits)" % [smashed, vp.hits])


## 20 m of open corridor: seconds until the zombie first hits the stand-in (-1: never).
func _race(type: String) -> float:
	var o := _arena()
	_corridor(o, 26, 3)
	var vp := _stand_in(Vector3(o) + Vector3(22.5, 1.0, 0.5))
	_zombie(type, Vector3(o) + Vector3(1.5, 1.02, 0.5))
	var t0: int = G.sim.tick_count
	await _ticks(20.0, func(): return vp.hits > 0)
	return (G.sim.tick_count - t0) * TICK if vp.hits > 0 else -1.0


## A plank wall across a corridor: blows it takes to break the first wall block (-1: none broke).
func _wall(type: String) -> int:
	var o := _arena()
	_corridor(o, 14, 3)
	var wall := []
	for y in range(1, 4):
		wall.append(o + Vector3i(5, y, 0))
		G.world.set_block(o + Vector3i(5, y, 0), Blocks.PLANKS)
	var vp := _stand_in(Vector3(o) + Vector3(10.5, 1.0, 0.5))
	_zombie(type, Vector3(o) + Vector3(1.5, 1.02, 0.5))
	var broke := func(): return wall.any(func(c): return G.world.get_blockv(c) == Blocks.AIR)
	await _ticks(30.0, broke)
	for c in wall:
		if G.world.get_blockv(c) == Blocks.AIR:
			return G.sim.edit_log.filter(func(e): return Vector3i(e[0], e[1], e[2]) == c).size()
	return -1


## A closed wooden door across a corridor (M4.2): a walker smashes it like a wall, but it takes
## more blows than a plank, and both halves go together.
func _door() -> void:
	var o := _arena()
	_corridor(o, 14, 2)
	var lo := o + Vector3i(5, 1, 0)
	var f: int = Blocks.facing_of(Vector3(-1, 0, 0))
	G.world.set_block(lo, Blocks.WOOD_DOOR, f)
	G.world.set_block(lo + Vector3i.UP, Blocks.WOOD_DOOR, f | Blocks.META_UPPER)
	var vp := _stand_in(Vector3(o) + Vector3(10.5, 1.0, 0.5))
	_zombie("walker", Vector3(o) + Vector3(1.5, 1.02, 0.5))
	var gone := func(): return G.world.get_blockv(lo) == Blocks.AIR and G.world.get_blockv(lo + Vector3i.UP) == Blocks.AIR
	await _ticks(60.0, func(): return vp.hits > 0)
	var blows: int = G.sim.edit_log.filter(func(e): return Vector3i(e[0], e[1], e[2]) in [lo, lo + Vector3i.UP]).size()
	check(gone.call() and vp.hits > 0 and blows > 6, "a walker smashes a wooden door, both halves (%d blows, %d hits)" % [blows, vp.hits])


## Every chunk within r m of c (on the ground plane) has loaded.
func _land_ready(c: Vector3, r: float) -> bool:
	for dz in range(-int(r), int(r) + 1, 8):
		for dx in range(-int(r), int(r) + 1, 8):
			if not G.world.is_ready_at(c + Vector3(dx, 0, dz)):
				return false
	return true


## A Screamer that sees a player calls zombies.
func _screamer() -> void:
	var o := _arena()
	_fill(o + Vector3i(-2, 0, -3), o + Vector3i(16, 0, 3), Blocks.STONE)
	_stand_in(Vector3(o) + Vector3(12.5, 1.0, 0.5))
	# Called zombies come up only on land that has loaded (18-28 m around the stand-in).
	var t0 := Time.get_ticks_msec()
	while not _land_ready(Vector3(o) + Vector3(12.5, 0, 0.5), 30.0) and Time.get_ticks_msec() - t0 < 30000:
		await _wait(0.25)
	var called0: int = G.sim.zombies_called
	_zombie("screamer", Vector3(o) + Vector3(1.5, 1.02, 0.5))
	await _ticks(8.0, func(): return G.sim.zombies_called > called0)
	check(G.sim.zombies_called - called0 >= 2, "a Screamer that sees a player calls zombies (%d came)" % (G.sim.zombies_called - called0))


## A Spitter hits a player 10 m away with acid; a glob thrown into a wall eats into the block.
func _spitter() -> void:
	var o := _arena()
	_fill(o + Vector3i(-2, 0, -3), o + Vector3i(16, 0, 3), Blocks.STONE)
	var vp := _stand_in(Vector3(o) + Vector3(11.5, 1.0, 0.5))
	var acids0: int = G.sim.acids_made
	_zombie("spitter", Vector3(o) + Vector3(1.5, 1.02, 0.5))
	await _ticks(10.0, func(): return vp.hits > 0)
	check(vp.hits > 0 and G.sim.acids_made > acids0, "a Spitter's acid hits a player 10 m away (%d globs, %d hits)" % [G.sim.acids_made - acids0, vp.hits])
	var o2 := _arena()
	var cell := o2 + Vector3i(4, 2, 0)
	G.world.set_block(cell, Blocks.PLANKS)
	var from := Vector3(o2) + Vector3(0.5, 2.5, 0.5)
	G.sim.queue_spit(9999, from, AcidScript.launch_velocity(from, Vector3(cell) + Vector3(0.5, 0.5, 0.5)), 12.0, 25.0)
	await _ticks(3.0, func(): return not G.sim.edit_log.is_empty())
	var hit: Array = G.sim.edit_log.filter(func(e): return Vector3i(e[0], e[1], e[2]) == cell)
	check(not hit.is_empty() and is_equal_approx(float(hit[0][3]), 25.0), "acid eats into the block it hits (%s)" % str(hit))
