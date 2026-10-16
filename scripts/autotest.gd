extends Node
## Automated playtest used during development: `-- --autotest [--shots=DIR]`

var shots_dir := ""
var fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	shots_dir = G.arg_value("--shots=")
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	if shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shots_dir + "/" + name + ".png")
	print("SHOT ", name)


func check(cond: bool, what: String) -> void:
	if cond:
		print("PASS ", what)
	else:
		fails += 1
		print("FAIL ", what)


func _find_block(id: int, radius: int) -> Vector3i:
	var c: Vector3 = G.player.global_position
	var best := Vector3i(0, -999, 0)
	var bd := 1e9
	for y in range(-6, 12):
		for z in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var p := Vector3i(floori(c.x) + x, floori(c.y) + y, floori(c.z) + z)
				if G.world.get_blockv(p) == id:
					var d := Vector3(p).distance_to(c)
					if d < bd:
						bd = d
						best = p
	return best


func _run() -> void:
	var g = G.game
	var p = G.player
	var w = G.world
	var t0 := Time.get_ticks_msec()
	while g.state == "loading":
		await _wait(0.25)
	print("LOAD_SECONDS ", (Time.get_ticks_msec() - t0) / 1000.0, " chunks=", w.chunks.size(), " seed=", g.seed_v)
	await _shot("00_title")
	g.start_game()
	await _wait(2.0)
	check(p.is_on_floor(), "player standing on ground at spawn " + str(p.global_position))
	var spawn: Vector3 = p.global_position

	# Count what the generator produced near spawn
	var counts := {}
	var cpos := Vector3i(floori(spawn.x), 0, floori(spawn.z))
	for y in 64:
		for z in range(-24, 24):
			for x in range(-24, 24):
				var b: int = w.get_block(cpos.x + x, y, cpos.z + z)
				counts[b] = counts.get(b, 0) + 1
	var names := []
	for k in counts:
		names.append("%s=%d" % [Blocks.NAMES[k], counts[k]])
	print("BLOCK_COUNTS ", ", ".join(names))

	p.set_look(0.6, -0.12)
	await _wait(0.6)
	await _shot("01_day_view")
	p.set_look(2.6, -0.05)
	await _wait(0.4)
	await _shot("02_day_view_b")

	# Mining a log by hand
	var log_p := _find_block(Blocks.LOG, 20)
	check(log_p.y > -900, "found a tree near spawn")
	if log_p.y > -900:
		p.break_block(log_p, Blocks.LOG)
		await _wait(0.3)
		check(w.get_blockv(log_p) == 0, "log removed from world")
		check(p.inv.count(Blocks.LOG) == 1, "log added to inventory")

	# Crafting chain
	p.inv.add(Blocks.LOG, 5)
	var st: Array = g.nearby_stations()
	for r in Crafting.RECIPES:
		if int(r["out"]) == Blocks.PLANKS:
			Crafting.craft(p.inv, r)
			Crafting.craft(p.inv, r)
			Crafting.craft(p.inv, r)
		if int(r["out"]) == Items.STICK:
			Crafting.craft(p.inv, r)
	check(p.inv.count(Blocks.PLANKS) == 10, "crafted planks (have %d)" % p.inv.count(Blocks.PLANKS))
	check(p.inv.count(Items.STICK) == 4, "crafted sticks")
	var bench_r: Dictionary = {}
	var pick_r: Dictionary = {}
	for r in Crafting.RECIPES:
		if int(r["out"]) == Blocks.WORKBENCH:
			bench_r = r
		if int(r["out"]) == Items.WOOD_PICK:
			pick_r = r
	check(not Crafting.can_craft(p.inv, pick_r, st), "pickaxe needs a workbench")
	check(Crafting.craft(p.inv, bench_r), "crafted workbench")

	# Place the workbench by aiming at the ground in front
	p.inv.swap(0, _slot_of(p.inv, Blocks.WORKBENCH))
	p.select(0)
	p.set_look(0.0, -1.1)
	await _wait(0.3)
	p._update_target()
	check(p.target.get("hit", false), "aiming at ground")
	var placed: bool = p.place(Blocks.WORKBENCH)
	check(placed, "placed workbench")
	await _wait(0.3)
	st = g.nearby_stations()
	check(st.has("workbench"), "workbench detected nearby")
	check(Crafting.craft(p.inv, pick_r), "crafted wooden pickaxe with bench")

	# Mine stone with the pickaxe
	var stone_p := _find_block(Blocks.STONE, 10)
	if stone_p.y > -900:
		p.select(_slot_of(p.inv, Items.WOOD_PICK))
		check(p._break_time(Blocks.STONE) < 3.0, "pickaxe mines stone faster (%.2fs)" % p._break_time(Blocks.STONE))
		p.break_block(stone_p, Blocks.STONE)
		check(p.inv.count(Blocks.COBBLE) == 1, "stone drops cobblestone")

	# Eating
	p.food = 50.0
	p.select(_slot_of(p.inv, Items.BERRIES))
	p.consume(Items.BERRIES)
	check(absf(p.food - 60.0) < 0.5, "eating berries restores food")

	# Inventory screen
	g.open_inventory()
	await _wait(0.5)
	await _shot("03_inventory")
	g.close_inventory()

	# Zombie wall test: wall of cobble between player and zombie
	var fwd := Vector3(0, 0, -1)
	p.set_look(0.0, -0.05)
	var base: Vector3 = p.global_position
	var fy := floori(base.y)
	var wall := []
	for dx in range(-2, 3):
		for dy in range(0, 2):
			var wp := Vector3i(floori(base.x) + dx, fy + dy, floori(base.z) - 3)
			w.set_block(wp, Blocks.PLANKS)
			wall.append(wp)
	await _wait(0.5)
	var zp := Vector3(floori(base.x) + 0.5, fy + 0.1, floori(base.z) - 6.5)
	for dy in range(0, 3):
		w.set_block(Vector3i(floori(zp.x), fy + dy, floori(zp.z)), 0)
		w.set_block(Vector3i(floori(zp.x), fy + dy, floori(zp.z) + 1), 0)
		w.set_block(Vector3i(floori(zp.x), fy + dy, floori(zp.z) + 2), 0)
	w.set_block(Vector3i(floori(zp.x), fy - 1, floori(zp.z)), Blocks.DIRT)
	w.set_block(Vector3i(floori(zp.x), fy - 1, floori(zp.z) + 1), Blocks.DIRT)
	w.set_block(Vector3i(floori(zp.x), fy - 1, floori(zp.z) + 2), Blocks.DIRT)
	await _wait(0.4)
	var z = g.spawn_zombie("night", zp)
	check(z != null, "spawned test zombie")
	g.time = 21.0
	g.was_night = true
	g._update_sky()
	p.flashlight.visible = true
	var hp0: float = p.health
	await _wait(3.0)
	await _shot("04_night_zombie_at_wall")
	var damaged := false
	for wp in wall:
		if w.damage.has(wp) or w.get_blockv(wp) == 0:
			damaged = true
	check(damaged, "zombie damaged the wall")
	await _wait(8.0)
	var broke := false
	for wp in wall:
		if w.get_blockv(wp) == 0:
			broke = true
	check(broke, "zombie broke through a wall block")
	for i in 6:
		if is_instance_valid(z):
			print("  t+%d zombie=%s player=%s hp=%.0f blocked_cells=%s" % [i, str(z.global_position), str(p.global_position), p.health, str(wall.map(func(q): return w.get_blockv(q)))])
		await _wait(1.0)
	check(p.health < hp0, "zombie reached and hurt the player (hp %.0f)" % p.health)
	if is_instance_valid(z):
		var zhp: float = z.hp
		p.attack(z)
		check(z.hp < zhp or z.dead, "player can hit zombie")
	await _shot("05_zombie_close")
	# Lights and defenses at night
	var here := Vector3i(floori(p.global_position.x), floori(p.global_position.y), floori(p.global_position.z))
	w.set_block(here + Vector3i(-2, 0, 1), Blocks.TORCH)
	w.set_block(here + Vector3i(2, 0, 1), Blocks.CAMPFIRE)
	w.set_block(here + Vector3i(0, 0, 3), Blocks.SPIKES)
	w.set_block(here + Vector3i(1, 0, 3), Blocks.SPIKES)
	p.flashlight.visible = false
	p.set_look(PI, -0.35)
	await _wait(1.0)
	await _shot("05b_torch_campfire_spikes")
	p.flashlight.visible = true

	# Blood moon
	p.health = 100.0
	g.skip_time(true)
	await _wait(5.0)
	check(g.horde_active, "blood moon started on day %d" % g.day)
	await _wait(6.0)
	var zc := get_tree().get_nodes_in_group("zombies").size()
	check(zc >= 4, "horde zombies spawning (%d)" % zc)
	p.set_look(PI, -0.05)
	await _wait(0.3)
	await _shot("06_blood_moon")

	# Dawn
	print("  state before dawn: ", g.state, " player dead=", p.dead)
	if p.dead:
		g.respawn()
	g.time = 5.98
	await _wait(2.0)
	check(not g.horde_active, "horde ends at dawn")
	g.time = 9.0
	g._update_sky()
	p.flashlight.visible = false
	await _wait(0.5)

	# Animals
	for i in 6:
		g._spawn_animal()
	await _wait(1.0)
	var an := get_tree().get_nodes_in_group("animals")
	check(an.size() > 0, "animals spawn (%d)" % an.size())
	if an.size() > 0:
		var a = an[0]
		var meat0: int = p.inv.count(Items.RAW_MEAT)
		a.hurt(25.0, p.global_position, p)
		await _wait(1.2)
		check(p.inv.count(Items.RAW_MEAT) > meat0, "boar drops raw meat")
		p.global_position = an[min(1, an.size() - 1)].global_position + Vector3(0, 0, 3)
		p.look_at_mob(an[min(1, an.size() - 1)])
		await _wait(0.6)
		await _shot("07_boar")

	print("FPS ", Engine.get_frames_per_second())
	print("AUTOTEST DONE fails=", fails)
	get_tree().quit()


func _slot_of(inv: Inventory, id: int) -> int:
	for i in Inventory.SIZE:
		if inv.id_at(i) == id:
			return i
	return 0
