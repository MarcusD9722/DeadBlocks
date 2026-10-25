extends "res://scripts/tests/nettest.gd"
## Automated playtest: `-- --autotest [--seed=4242] [--shots=DIR]`.
## Presses Play solo (a new world called "autotest", so the player's own solo world is left
## alone) and plays it through the real client against the game's own local server: mining,
## crafting at a workbench, a pickaxe, eating, a horde breaking a wall, fighting, death and
## respawn with the backpack, a Blood Moon and its dawn, boars, the pause menu stopping the
## world, and quitting and continuing with everything still there.
## Prints AUTOTEST PASS/FAIL lines and ends with `AUTOTEST DONE fails=N`.

const ZombieScript := preload("res://scripts/zombie.gd")

## The backpack from the night's death, left lying until after Save and Quit.
var _night_bp := Vector3i.MIN
## Our bed, the respawn point (placed after the workbench).
var _bed := Vector3i.MIN


func _ready() -> void:
	tag = "AUTOTEST"
	role = "autotest"
	super()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	check(await _until(func(): return G.game != null and is_instance_valid(G.game) and G.hud != null, 60.0), "the title screen is up")
	await _wait(1.0)
	await _shot("00_title")
	var err: String = await G.play_solo(true, "autotest")
	check(err == "", "Play solo started its server (%s)" % err)
	if not await _until(_playing, 120.0):
		check(false, "the solo game started (%s)" % ", ".join(_errors))
		await _finish()
		return
	print("LOAD_SECONDS %.1f seed=%d" % [(Time.get_ticks_msec() - t0) / 1000.0, G.game.seed_v])
	check(G.solo and G.mode == "client", "Play solo runs on its own server")
	await _play()
	await _continue_later()
	print("FPS ", Engine.get_frames_per_second())
	await _finish()


## Find the nearest block `id` within `radius` of the player whose middle is within `reach` of
## the camera (the server only lets us mine what we can reach).
func _find_block(id: int, radius: int, reach := 1e9) -> Vector3i:
	var c: Vector3 = G.player.global_position
	var eye: Vector3 = G.player.cam.global_position
	var best := Vector3i(0, -999, 0)
	var bd := 1e9
	for y in range(-6, 12):
		for z in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var p := Vector3i(floori(c.x) + x, floori(c.y) + y, floori(c.z) + z)
				if G.world.get_blockv(p) == id and (Vector3(p) + Vector3(0.5, 0.5, 0.5)).distance_to(eye) < reach:
					var d := Vector3(p).distance_to(c)
					if d < bd:
						bd = d
						best = p
	return best


func _play() -> void:
	var g = G.game
	var p = G.player
	var w = G.world
	check(await _until(func(): return p.is_on_floor(), 15.0), "standing on ground at spawn %s" % str(p.global_position))
	check(await _until(func(): return _count(Items.BERRIES) == 3 and _count(Blocks.TORCH) == 2, 10.0), "the server gave the starter kit")
	p.set_look(0.6, -0.12)
	await _wait(0.6)
	await _shot("01_day_view")

	# A log by hand: walk to the nearest tree first.
	var log_p := _find_block(Blocks.LOG, 24)
	check(log_p.y > -900, "found a tree near spawn")
	if log_p.y > -900:
		await _walk_to(Vector3(log_p) + Vector3(0.5, 0, 0.5), 2.5, 20.0)
		await _until(func(): return p.is_on_floor(), 5.0)
		log_p = _find_block(Blocks.LOG, 6, 5.5)
		check(log_p.y > -900, "a log within reach")
		if log_p.y > -900:
			_look_at(Vector3(log_p) + Vector3(0.5, 0.5, 0.5))
			p.break_block(log_p, Blocks.LOG)
			check(await _until(func(): return _server_count(Blocks.LOG) == 1, 5.0), "a log in the server's copy of our inventory")
			check(w.get_blockv(log_p) == Blocks.AIR, "the log is gone")

	# Crafting (M4.1): planks, sticks and the wooden tools by hand (I); station recipes only at
	# their station, whose screen E opens.
	G.net.send_chat("/give log 5")
	check(await _until(func(): return _count(Blocks.LOG) >= 6, 10.0), "/give works in solo (we're the admin)")
	G.net.request_craft(_recipe(Blocks.PLANKS), 4)
	G.net.request_craft(_recipe(Items.STICK), 1)
	check(await _until(func(): return _count(Blocks.PLANKS) == 14 and _count(Items.STICK) == 4, 5.0),
		"crafted planks and sticks (%d planks, %d sticks)" % [_count(Blocks.PLANKS), _count(Items.STICK)])
	G.net.request_craft(_recipe(Blocks.SPIKES), 1)
	await _wait(1.0)
	check(_count(Blocks.SPIKES) == 0, "no spikes without a workbench")
	G.net.request_craft(_recipe(Items.WOOD_PICK), 1)
	check(await _until(func(): return _count(Items.WOOD_PICK) == 1, 5.0), "a wooden pickaxe by hand")
	await _press(KEY_I)
	check(g.state == "menu" and G.hud.inv_station == "", "I opens the inventory")
	check(_recipes_shown().all(func(r): return r["st"] == "") and _recipes_shown().any(func(r): return int(r["out"]) == Items.WOOD_SHOVEL),
		"it lists the hand recipes only (the wooden shovel among them)")
	await _press(KEY_I)
	check(g.state == "playing", "I closes it")
	G.net.request_craft(_recipe(Blocks.WORKBENCH), 1)
	check(await _until(func(): return _count(Blocks.WORKBENCH) == 1, 5.0), "crafted a workbench")
	await _hold(Blocks.WORKBENCH)
	p.set_look(0.0, -1.1)
	await _wait(0.3)
	p._update_target()
	check(p.target.get("hit", false), "aiming at the ground")
	var bench_at := Vector3i(0, -1, 0)
	if p.target.get("hit", false):
		bench_at = p.target["pos"] + p.target["normal"]
	check(p.place(Blocks.WORKBENCH), "placed the workbench")
	check(await _until(func(): return _server_count(Blocks.WORKBENCH) == 0 and w.get_blockv(bench_at) == Blocks.WORKBENCH, 5.0), "the server placed it")
	check(g.nearby_stations().has("workbench"), "the workbench counts as nearby")
	_look_at(Vector3(bench_at) + Vector3(0.5, 0.5, 0.5))
	check(await _until(func(): return p.interact_text() == "Open Workbench", 2.0), "looking at it offers E (%s)" % p.interact_text())
	await _press(KEY_E)
	check(g.state == "menu" and G.hud.inv_station == "workbench", "E opens the workbench")
	check(_recipes_shown().size() > 10 and _recipes_shown().all(func(r): return r["st"] == "workbench"), "it lists the workbench's recipes")
	await _wait(0.3)
	await _shot("02_workbench")
	await _press(KEY_E)
	check(g.state == "playing", "E closes it")
	G.net.request_craft(_recipe(Items.STICK), 1)  # (the pickaxe took 2 of the 4)
	G.net.request_craft(_recipe(Blocks.SPIKES), 1)
	check(await _until(func(): return _count(Blocks.SPIKES) == 2, 5.0), "spikes at the workbench")

	await _building()
	await _ranged()

	# The controller (M4.1): the right stick looks, RB turns the hotbar, Y opens the inventory and
	# B closes it, the left stick walks.
	var yaw0: float = p.head.rotation.y
	_pad_axis(JOY_AXIS_RIGHT_X, 1.0)
	await _wait(0.5)
	_pad_axis(JOY_AXIS_RIGHT_X, 0.0)
	check(absf(p.head.rotation.y - yaw0) > 0.3, "the right stick turns us (%.2f rad)" % absf(p.head.rotation.y - yaw0))
	var sel0: int = p.selected
	await _pad_press(JOY_BUTTON_RIGHT_SHOULDER)
	check(p.selected == (sel0 + 1) % 9, "RB moves along the hotbar")
	await _pad_press(JOY_BUTTON_Y)
	check(g.state == "menu" and G.hud.inv_station == "", "Y opens the inventory")
	await _pad_press(JOY_BUTTON_B)
	check(g.state == "playing", "B closes it")
	var at0: Vector3 = p.global_position
	_pad_axis(JOY_AXIS_LEFT_Y, -1.0)
	await _wait(0.6)
	var walked: float = Vector2(p.global_position.x - at0.x, p.global_position.z - at0.z).length()
	_pad_axis(JOY_AXIS_LEFT_Y, 1.0)  # and back
	await _wait(0.6)
	_pad_axis(JOY_AXIS_LEFT_Y, 0.0)
	check(walked > 0.8 and Controls.pad_in_use, "the left stick walks us (%.2f m; the game knows a controller is in use)" % walked)
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await get_tree().process_frame
	check(Input.is_action_pressed("attack"), "the right trigger mines / hits")
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await get_tree().process_frame
	await _character()

	# A bed (M2): placing it makes it where we wake up after dying.
	G.net.send_chat("/give plant_fiber 3")
	await _until(func(): return _count(Items.FIBER) >= 3, 10.0)
	G.net.request_craft(_recipe(Blocks.BED), 1)
	check(await _until(func(): return _count(Blocks.BED) == 1, 5.0), "crafted a bed at the workbench")
	await _place_bed()
	check(_bed != Vector3i.MIN, "the bed is our respawn point (%s)" % _bed)
	if _bed != Vector3i.MIN:
		_look_at(Vector3(_bed) + Vector3(0.5, 0.25, 0.5))
		await _wait(0.4)
		await _shot("08_bed")

	# Stone with the pickaxe gives cobblestone.
	var stone_p := _find_block(Blocks.STONE, 6, 6.3)
	if stone_p.y < -900:
		# Dig a shaft beside us down to the stone under the dirt.
		await _hold(Items.WOOD_PICK)
		var col := _base() + Vector3i(1, 0, 0)
		for i in range(1, 8):
			var b := col + Vector3i(0, -i, 0)
			var id: int = w.get_blockv(b)
			if id == Blocks.STONE:
				break
			if id != Blocks.AIR:
				_look_at(Vector3(b) + Vector3(0.5, 0.5, 0.5))
				p.break_block(b, id)
				await _wait(p._break_time(id) + 0.4)
		stone_p = _find_block(Blocks.STONE, 6, 6.3)
		if stone_p.y < -900:
			print("AUTOTEST no stone: we stand at %s, the shaft at %s holds %s" % [p.global_position, col,
				range(0, 9).map(func(i): return Blocks.NAMES[w.get_blockv(col + Vector3i(0, -i, 0))])])
	check(stone_p.y > -900, "stone within reach")
	if stone_p.y > -900:
		await _hold(Items.WOOD_PICK)
		check(p._break_time(Blocks.STONE) < 3.0, "the pickaxe mines stone faster (%.2f s)" % p._break_time(Blocks.STONE))
		await _wait(p._break_time(Blocks.STONE) + 0.5)
		_look_at(Vector3(stone_p) + Vector3(0.5, 0.5, 0.5))
		p.break_block(stone_p, Blocks.STONE)
		check(await _until(func(): return _count(Blocks.COBBLE) == 1, 5.0), "stone drops cobblestone")

	# Eating: health and food are the server's, so first a fall to have something to heal.
	p.global_position += Vector3(0, 10, 0)
	check(await _until(func(): return p.health < 90.0, 8.0), "a fall hurts (health %.0f)" % p.health)
	await _until(func(): return p.is_on_floor(), 5.0)
	var hp_low: float = p.health
	await _hold(Items.BERRIES)
	p.consume(Items.BERRIES)
	check(await _until(func(): return p.health > hp_low and _count(Items.BERRIES) == 2, 5.0), "ate berries (health %.0f -> %.0f)" % [hp_low, p.health])
	g.open_inventory()
	await _wait(0.5)
	await _shot("02_inventory")
	g.close_inventory()

	# The pause menu stops the world (only in solo).
	g.pause()
	check(await _until(func(): return g.clock_stopped, 3.0), "the pause menu stops the clock")
	var t_paused: float = g.time
	await _wait(3.0)
	check(is_equal_approx(g.time, t_paused), "time stands still while paused (%.4f, %.4f)" % [t_paused, g.time])
	await _shot("03_paused")
	g.resume()
	check(await _until(func(): return not g.clock_stopped and g.time > t_paused, 8.0), "time runs again after Resume")

	# Boars: hunt one for meat (in daylight, before any zombies are about).
	var boars0: Array = _mob_ids([Proto.MOB_BOAR])
	G.net.send_chat("/spawn boar 3")
	check(await _until(func(): return _mob_ids([Proto.MOB_BOAR]).size() > boars0.size(), 10.0), "boars appear")
	var boars := _mob_ids([Proto.MOB_BOAR])
	boars.sort_custom(func(a, b): return _mob_dist(a) < _mob_dist(b))
	if not boars.is_empty():
		var meat0 := _count(Items.RAW_MEAT)
		G.net.send_chat("/give stone_sword")
		await _until(func(): return _count(Items.STONE_SWORD) == 1, 10.0)
		await _hold(Items.STONE_SWORD)
		check(await _hunt(boars[0], 40.0), "hunted down a boar")
		check(await _until(func(): return _count(Items.RAW_MEAT) > meat0, 5.0), "the boar drops raw meat")
		await _shot("07_boar")

	# Night: wall ourselves in with dirt; a horde breaks in, hurts us, and we fight back.
	G.net.send_chat("/give dirt 40")
	check(await _until(func(): return _count(Blocks.DIRT) >= 40 and _count(Items.STONE_SWORD) == 1, 10.0), "/give dirt (and we have the sword)")
	G.net.send_chat("/dusk")
	check(await _until(func(): return g.time >= 19.9, 10.0), "F6 / /dusk skips to the evening (%.2f)" % g.time)
	await _until(func(): return p.is_on_floor(), 5.0)
	p.global_position = Vector3(floori(p.global_position.x) + 0.5, p.global_position.y, floori(p.global_position.z) + 0.5)
	p.velocity = Vector3.ZERO
	await _wait(0.5)
	await _until(func(): return p.is_on_floor(), 5.0)
	# The boars from the hunt may stand where the wall goes (no block can be placed on a mob).
	await _clear_mobs()
	var ring: Array = await _wall_in()
	var solid := func(): return ring.filter(func(b): return w.get_blockv(b) != Blocks.AIR)
	check(solid.call().size() >= 14, "walled ourselves in (%d of 16 solid)" % solid.call().size())
	var walled: Array = solid.call()
	var before: Array = G.net.mobs.keys()
	var hp0: float = p.health
	G.net.send_chat("/spawn horde 4")
	check(await _until(func(): return _mob_ids([Proto.MOB_HORDE]).size() >= 3, 10.0), "a horde appears")
	await _wait(2.0)
	await _shot("04_night_horde")
	check(await _until(func(): return int(G.net.bytes_in.get(Proto.S_CRACKS, 0)) > 0, 75.0), "the horde cracks blocks")
	check(await _until(func(): return walled.any(func(b): return w.get_blockv(b) == Blocks.AIR) or p.health < hp0 or p.dead, 90.0),
		"the horde breaks through (or reaches us)")
	check(await _until(func(): return p.health < hp0 or p.dead, 60.0), "a zombie hurts us (health %.0f)" % p.health)
	if not p.dead:
		await _hold(Items.STONE_SWORD)
		var near := _mob_ids([Proto.MOB_HORDE]).filter(func(id): return not before.has(id))
		near.sort_custom(func(a, b): return _mob_dist(a) < _mob_dist(b))
		var kills0: int = g.kills
		if not near.is_empty():
			var won: bool = await _fight(near[0], 20.0)
			if p.dead:
				print("AUTOTEST the horde got us during the fight (the kill checks are in the network test)")
			else:
				check(won, "killed a horde zombie")
				check(await _until(func(): return g.kills > kills0, 5.0), "the kill is counted (%d)" % g.kills)
	# Dying and respawning: a 40 m fall always kills.
	if not p.dead:
		p.global_position += Vector3(0, 40, 0)
	check(await _until(func(): return p.dead, 15.0), "died (health %.0f)" % p.health)
	check(g.state == "dead", "the death screen shows")
	check(await _until(func(): return G.net.my_backpacks.size() == 1, 5.0), "dying drops a backpack (it's marked on screen)")
	_night_bp = _new_backpack([])
	check(w.get_blockv(_night_bp) == Blocks.BACKPACK, "the backpack is in the world (%s)" % _night_bp)
	check(await _until(func(): return _count(Items.STONE_SWORD) == 0 and _count(Items.WOOD_PICK) == 0, 5.0), "everything we carried went into it")
	await _wait(1.2)
	check("backpack" in G.hud.death_lbl.text, "the death screen says where our things are")
	await _shot("05_dead")
	await _wait(1.0)
	check(G.hud.death_bed.visible, "the death screen offers our bed")
	g.respawn()
	check(await _until(func(): return not p.dead and p.health >= 99.0 and g.state == "playing", 10.0), "respawned with full health")
	check(_bed != Vector3i.MIN and p.global_position.distance_to(Vector3(_bed) + Vector3(0.5, 0.5, 0.5)) < 2.5,
		"next to our bed (%.1f m away)" % p.global_position.distance_to(Vector3(_bed)))
	if _night_bp != Vector3i.MIN:
		_look_at(Vector3(_night_bp) + Vector3(0.5, 3.0, 0.5))
		await _wait(0.8)
		await _shot("10_backpack_beam")

	# Blood Moon, then dawn.
	G.net.send_chat("/bloodmoon")
	check(await _until(func(): return g.horde_active, 20.0), "F7 / /bloodmoon: the Blood Moon starts (day %d)" % g.day)
	check(await _until(func(): return _blood_ids().size() >= 4, 25.0), "the horde comes (%d)" % _blood_ids().size())
	p.set_look(PI, -0.05)
	await _wait(0.3)
	await _shot("06_blood_moon")
	if p.dead:
		g.respawn()
		await _until(func(): return g.state == "playing", 10.0)
	G.net.send_chat("/time 5.98")
	check(await _until(func(): return not g.horde_active, 20.0), "the horde ends at dawn")
	check(await _until(func(): return _blood_ids().is_empty(), 10.0),
		"the horde calms down into day zombies (%d still horde)" % _blood_ids().size())
	check(await _until(func(): return g.mob_views.values().all(func(v): return not is_instance_valid(v) or not v is ZombieScript or not v.blood), 5.0),
		"and they look like day zombies again")

	# The M3 zombie types: each comes when called and looks like itself.
	if p.dead:
		g.respawn()
		await _until(func(): return g.state == "playing", 10.0)
	await _clear_mobs()
	for t in NEW_TYPES:
		var kind: int = Proto.ZOMBIE_KINDS[t]
		G.net.send_chat("/spawn %s 1" % t)
		check(await _until(func(): return not _mob_ids([kind]).is_empty(), 10.0), "/spawn %s" % t)
		var ids := _mob_ids([kind])
		if ids.is_empty():
			continue
		var zid: int = ids[0]
		check(await _until(func(): return g.mob_views.has(zid) and is_instance_valid(g.mob_views[zid]) and g.mob_views[zid].type == t, 5.0),
			"a %s shows up looking like one" % t)
		if G.arg_value("--shots=") != "":
			var s: Dictionary = G.net.mob_sample(zid)
			if not s.is_empty():
				_look_at(s["pos"] + Vector3(0, 1.0, 0))
			await _wait(0.4)
			await _shot("11_" + t)
		await _clear_mobs()
		await _until(func(): return not G.net.mobs.has(zid), 3.0)

	# Stuck somewhere: the pause menu's Die and Respawn, falling out of the world, being buried.
	# Each death drops a backpack, which we pick up again.
	if p.dead:
		g.respawn()
		await _until(func(): return g.state == "playing", 10.0)
	var zs0: Array = _zombie_ids()
	var cleared: bool = await _clear_mobs()
	check(cleared and await _until(func(): return zs0.all(func(id): return not G.net.mobs.has(id)), 5.0),
		"/clear removes the zombies (%d of them)" % zs0.size())
	if G.net.bed == Vector3i.MIN:
		# The Blood Moon horde smashed it: a new one, so the respawns below stay close by.
		print("AUTOTEST the horde broke our bed: placing another")
		G.net.send_chat("/give bed")
		await _until(func(): return _count(Blocks.BED) == 1, 10.0)
		await _place_bed()
	G.net.send_chat("/give planks 7")
	await _until(func(): return _count(Blocks.PLANKS) == 7, 10.0)
	g.pause()
	g.kill_self()
	check(await _until(func(): return p.dead and g.state == "dead", 10.0), "Die and Respawn: we die")
	check(await _until(func(): return G.net.my_backpacks.size() == 2, 5.0), "a second backpack")
	var bp := _new_backpack([_night_bp])
	var left0: float = G.net.my_backpacks.filter(func(e): return e[0] == bp)[0][1] if bp != Vector3i.MIN else 0.0
	await _wait(2.0)
	var left1: float = G.net.my_backpacks.filter(func(e): return e[0] == bp)[0][1] if bp != Vector3i.MIN else 0.0
	check(left0 > 500.0 and left1 < left0 - 1.0, "its 10 minutes run down (%.0f s, then %.0f s)" % [left0, left1])
	g.respawn()
	check(await _until(func(): return not p.dead and g.state == "playing", 10.0), "and respawn")
	await _until(func(): return p.is_on_floor(), 5.0)
	await _mine_backpack(bp, 30.0, true)
	check(await _until(func(): return _count(Blocks.PLANKS) == 7 and G.net.my_backpacks.size() == 1 and w.get_blockv(bp) == Blocks.AIR, 5.0),
		"E on the backpack gives everything back (%d planks)" % _count(Blocks.PLANKS))
	G.net.send_chat("/give dirt 3")
	await _until(func(): return _count(Blocks.DIRT) == 3, 10.0)
	await _until(func(): return p.is_on_floor(), 5.0)
	var stood: Vector3 = p.global_position
	await _wait(0.3)  # our last position on the ground reaches the server
	p.global_position.y = -15.0
	check(await _until(func(): return p.dead, 10.0), "falling out of the world is a death, not falling forever")
	check(await _until(func(): return G.net.my_backpacks.size() == 2, 5.0), "it drops a backpack too")
	var vb := _new_backpack([_night_bp])
	var off := Vector2(vb.x + 0.5 - stood.x, vb.z + 0.5 - stood.z).length()
	check(vb.y >= 1 and Blocks.is_solid(w.get_blockv(vb + Vector3i.DOWN)) and off < 4.0,
		"on the ground where we last stood, not in the void (%s, %.1f m off)" % [vb, off])
	g.respawn()
	await _until(func(): return not p.dead and g.state == "playing", 10.0)
	await _until(func(): return p.is_on_floor(), 5.0)
	await _mine_backpack(vb)
	check(await _until(func(): return _count(Blocks.DIRT) == 3 and G.net.my_backpacks.size() == 1, 5.0), "and we get it back")
	var here := _base()
	var buried := Vector3i(0, -1, 0)
	for depth in range(3, 12):
		var cell := Vector3i(here.x, w.surface_y(here.x, here.z) - depth, here.z)
		if Blocks.is_solid(w.get_blockv(cell)) and Blocks.is_solid(w.get_blockv(cell + Vector3i.UP)):
			buried = cell
			break
	check(buried.y >= 0, "found solid ground to be buried in")
	if buried.y >= 0:
		p.global_position = Vector3(buried.x + 0.5, buried.y + 0.05, buried.z + 0.5)
		p.velocity = Vector3.ZERO
		var free := func():
			var f := Vector3i(floori(p.global_position.x), floori(p.global_position.y + 0.1), floori(p.global_position.z))
			return not Blocks.is_solid(w.get_blockv(f)) and not Blocks.is_solid(w.get_blockv(f + Vector3i.UP))
		check(await _until(free, 5.0), "buried in the ground, we climb out by ourselves")

## Admin /clear: every zombie and animal goes. True once the server says so.
func _clear_mobs() -> bool:
	var said := func() -> int: return _notices.filter(func(n): return String(n).begins_with("Removed ")).size()
	var n0: int = said.call()
	G.net.send_chat("/clear")
	return await _until(func(): return said.call() > n0, 10.0)


## Place the bed we hold on the ground behind us; sets _bed once the server says it's ours.
func _place_bed() -> void:
	var p = G.player
	await _hold(Blocks.BED)
	await _until(func(): return p.is_on_floor(), 5.0)
	for yaw in [PI, PI * 0.5, -PI * 0.5, 0.0]:
		p.set_look(yaw, -1.1)
		await _wait(0.3)
		p._update_target()
		if not p.target.get("hit", false):
			continue
		var at: Vector3i = p.target["pos"] + p.target["normal"]
		if p.place(Blocks.BED):
			if await _until(func(): return G.net.bed == at and G.world.get_blockv(at) == Blocks.BED, 5.0):
				_bed = at
				return


## Chase mob `id` and hit it until it dies (a boar runs away once it is hit).
func _hunt(id: int, secs: float) -> bool:
	var p = G.player
	var t0 := Time.get_ticks_msec()
	var ok := false
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		if not G.net.mobs.has(id):
			break  # gone without dying: it got away
		if int(G.net.mobs[id]["samples"].back()[4]) & Proto.MF_DEAD:
			ok = true
			break
		var s: Dictionary = G.net.mob_sample(id)
		if not s.is_empty():
			var d: Vector3 = s["pos"] - p.global_position
			var far := Vector2(d.x, d.z).length() > 2.2
			for a in ["move_forward", "sprint"]:
				if far:
					Input.action_press(a)
				else:
					Input.action_release(a)
			if far and p.is_on_floor() and p.get_real_velocity().length() < 1.0:
				Input.action_press("jump")
			else:
				Input.action_release("jump")
			_look_at(s["pos"] + Vector3(0, 0.5, 0))
			if _mob_dist(id) < 3.4:
				p.attack_cd = 0.0
				G.net.request_attack(id, p.selected)
		await _wait(0.35)
	for a in ["move_forward", "sprint", "jump"]:
		Input.action_release(a)
	return ok


## Save and quit to the title, then Play solo again: the same world continues.
func _continue_later() -> void:
	var g = G.game
	var game_id: int = g.get_instance_id()
	var p = G.player
	if p.dead:
		await _wait(1.0)
		g.respawn()
		await _until(func(): return g.state == "playing", 10.0)
	var pos: Vector3 = p.global_position
	var picks := _count(Items.WOOD_PICK)
	var planks := _count(Blocks.PLANKS)
	var day: int = g.day
	await _until(func(): return p.is_on_floor(), 5.0)
	pos = p.global_position
	await _wait(0.5)  # our last position reaches the server
	G.end_client_session("Your world is saved.")
	check(await _until(func(): return G.mode == "solo" and is_instance_valid(G.game) and G.game.get_instance_id() != game_id and G.hud != null, 20.0),
		"Save and Quit goes back to the title")
	check(G.host_pid == 0, "the solo server stopped")
	var info: Dictionary = G.world_info("autotest")
	check(int(info.get("day", 0)) == day, "the title knows the saved world (day %s)" % info.get("day", "?"))
	var err: String = await G.play_solo(false, "autotest")
	check(err == "", "Play solo again (%s)" % err)
	# A zombie left over from the night may have killed us just before we quit: then we come
	# back to the death screen, still in the same place.
	var back := func(): return G.net.is_online() and is_instance_valid(G.game) and G.game.state in ["playing", "dead"] and G.player != null
	if not await _until(back, 120.0):
		check(false, "the solo game started again (%s)" % ", ".join(_errors))
		return
	p = G.player
	check(G.game.day == day, "the same day (%d)" % G.game.day)
	check(p.global_position.distance_to(pos) < 1.5, "back where we left (off by %.2f m)" % p.global_position.distance_to(pos))
	check(await _until(func(): return _count(Items.WOOD_PICK) == picks and _count(Blocks.PLANKS) == planks, 10.0), "the same things in the inventory")
	# The night's backpack is still where it fell, with its time left, and has the sword in it.
	check(await _until(func(): return G.net.my_backpacks.any(func(e): return e[0] == _night_bp), 10.0), "the night's backpack is still there after Continue")
	check(G.world.get_blockv(_night_bp) == Blocks.BACKPACK, "and in the world")
	if G.game.state == "dead":
		G.game.respawn()
		await _until(func(): return G.game.state == "playing", 10.0)
	await _mine_backpack(_night_bp, 60.0)
	check(await _until(func(): return _count(Items.STONE_SWORD) == 1 and _count(Items.WOOD_PICK) == picks + 1, 5.0),
		"picked it up: the sword and the pickaxe are back")
	check(G.net.bed != Vector3i.MIN and G.world.get_blockv(G.net.bed) == Blocks.BED, "our bed is still our respawn point")
	check(G.net.pins.any(func(e): return e["name"] == "Autotest pin") and G.net.explored.size() >= 90,
		"the map pin and the explored map are still there (%d chunks)" % G.net.explored.size())

	# Without a bed we wake up somewhere random, on open ground (and not in the void).
	var bed: Vector3i = G.net.bed
	await _walk_to(Vector3(bed) + Vector3(0.5, 0, 0.5), 2.0, 60.0)
	_look_at(Vector3(bed) + Vector3(0.5, 0.25, 0.5))
	p.break_block(bed, Blocks.BED)
	check(await _until(func(): return G.net.bed == Vector3i.MIN and _count(Blocks.BED) == 1, 5.0), "breaking the bed: no respawn point any more")
	var died_at: Vector3 = p.global_position
	G.net.send_chat("/kill")
	check(await _until(func(): return p.dead and G.game.state == "dead", 10.0), "/kill")
	await _wait(1.2)
	check(not G.hud.death_bed.visible, "the death screen has no bed to offer")
	G.game.respawn(false)
	check(await _until(func(): return G.game.state == "playing" and G.world.is_ready_at(p.global_position), 30.0), "respawned, and the land there loads")
	await _shot("09_random_respawn")
	check(await _until(func(): return p.is_on_floor(), 15.0), "standing on the ground at %s" % p.global_position)
	var far := Vector2(p.global_position.x - died_at.x, p.global_position.z - died_at.z).length()
	var spawn: Vector3 = G.session["spawn"]
	var off := Vector2(p.global_position.x - spawn.x, p.global_position.z - spawn.z).length()
	check(off > 2.0 and Vector2(p.global_position.x, p.global_position.z).length() < 1010.0,
		"somewhere random within 1 km of the center, not the world spawn (%.0f m from where we died)" % far)
	await _wait(3.0)
	check(not p.dead and p.global_position.y > 1.0, "and still fine 3 s later")
	await _wait(1.0)


## The character screen (M4.4): M opens the map (the land around us painted, explored as the
## server says), pins go on it with the mouse's code path and the controller's A and X, LB / RB
## move between the tabs, a tribe is founded from the Tribe tab and left again, and I goes back
## to the Inventory tab and closes the screen.
func _character() -> void:
	var g = G.game
	var p = G.player
	var hud = G.hud
	await _press(KEY_M)
	check(g.state == "menu" and hud.tab == "map" and hud.pages["map"].is_visible_in_tree(), "M opens the map")
	var here := Vector2i(floori(p.global_position.x / 16.0), floori(p.global_position.z / 16.0))
	check(G.net.explored.size() >= 90 and G.net.explored.has(here), "the server says we explored %d chunks, this one too" % G.net.explored.size())
	check(await _until(func(): return g.map_data.painted.get(here, 0) == 2, 10.0), "the map has the chunk we are in, painted from its blocks")
	var rk := Vector2i(floori(here.x / float(MapData.REGION)), floori(here.y / float(MapData.REGION)))
	var img: Image = g.map_data.regions[rk]["img"] if g.map_data.regions.has(rk) else null
	var px := Vector2i(floori(p.global_position.x) - rk.x * MapData.REGION_PX, floori(p.global_position.z) - rk.y * MapData.REGION_PX)
	check(img != null and img.get_pixelv(px).a > 0.99, "with a coloured pixel where we stand (%s)" % (img.get_pixelv(px) if img != null else "no image"))
	var dark := Vector2i(here.x + 40, here.y)
	check(not G.net.explored.has(dark) and not g.map_data.painted.has(dark), "land 640 m away is still dark")
	await _wait(0.5)
	check(g.map_data.region_tex(rk) != null, "the map draws it")
	await _shot("03_map")
	var pins: int = G.net.pins.size()
	G.net.request_pin_add(floori(p.global_position.x) + 40, floori(p.global_position.z), "Autotest pin")
	check(await _until(func(): return G.net.pins.size() == pins + 1 and G.net.pins.back()["name"] == "Autotest pin", 5.0), "a named pin on the map")
	check(await _until(func(): return hud.map_panel.has_focus(), 2.0), "the map has the focus (for the controller)")
	await _pad_press(JOY_BUTTON_A)
	check(await _until(func(): return G.net.pins.size() == pins + 2, 5.0), "the controller's A adds a pin in the middle (%s)" % G.net.pins.back().get("name", ""))
	await _pad_press(JOY_BUTTON_X)
	check(await _until(func(): return G.net.pins.size() == pins + 1, 5.0) and g.state == "menu", "X removes it again (and doesn't close the map)")
	await _pad_press(JOY_BUTTON_RIGHT_SHOULDER)
	check(hud.tab == "players" and hud.players_list.get_child_count() >= 1, "RB goes to the Players tab (us in the list)")
	await _pad_press(JOY_BUTTON_RIGHT_SHOULDER)
	check(hud.tab == "tribe" and hud.tribe_name_btn.visible, "RB again: the Tribe tab, offering to found one")
	hud.tribe_name_edit.text = "Autotest Tribe"
	hud._tribe_name_pressed()
	check(await _until(func(): return G.net.tribe.get("name", "") == "Autotest Tribe" and G.net.tribe.get("leader", "") == G.net.player_name, 5.0),
		"founded a tribe from the Tribe tab")
	check(await _until(func(): return hud.tribe_leave_btn.visible and hud.tribe_name_btn.text.strip_edges() == "Rename", 2.0), "its leader can rename it or leave")
	await _wait(0.3)
	await _shot("04_tribe")
	G.net.send_chat("/t NT hello tribe")
	check(await _until(func(): return hud.chat_log.any(func(m): return "[Tribe] <%s> NT hello tribe" % G.net.player_name in str(m["text"])), 5.0), "tribe chat (/t)")
	hud.tribe_leave_btn.pressed.emit()
	check(await _until(func(): return G.net.tribe.is_empty(), 5.0), "left it again (the last one out ends it)")
	await _pad_press(JOY_BUTTON_LEFT_SHOULDER)
	check(hud.tab == "players", "LB goes back a tab")
	await _press(KEY_I)
	check(hud.tab == "inventory" and g.state == "menu", "I goes to the Inventory tab")
	await _press(KEY_I)
	check(g.state == "playing", "and I again closes the screen")


## Building (M4.2): a door both halves of which open and close with E, a storage box things go
## into and come back out of, and a mallet that upgrades a wood frame to planks and repairs the
## damage zombies (an admin's /damage) did.
func _building() -> void:
	var p = G.player
	var w = G.world
	var g = G.game
	for give in ["wooden_door", "wooden_box", "wood_frame 2", "wooden_mallet", "planks 10"]:
		G.net.send_chat("/give " + give)
	check(await _until(func(): return _count(Blocks.WOOD_DOOR) == 1 and _count(Blocks.WOOD_BOX) == 1 and _count(Blocks.WOOD_FRAME) == 2 \
		and _count(Items.WOOD_MALLET) == 1, 10.0), "/give the building things")
	# A door: two blocks tall, both halves open and close together.
	var door := _free_spot([])
	check(door != Vector3i.MIN, "room for a door (%s)" % door)
	if door == Vector3i.MIN:
		return
	await _hold(Blocks.WOOD_DOOR)
	_look_at(Vector3(door) + Vector3(0.5, 0.5, 0.5))
	check(p.try_place(door, Blocks.WOOD_DOOR), "placed a door")
	var up := door + Vector3i.UP
	check(await _until(func(): return _server_count(Blocks.WOOD_DOOR) == 0 and w.get_blockv(door) == Blocks.WOOD_DOOR and w.get_blockv(up) == Blocks.WOOD_DOOR \
		and (w.block_meta(up) & Blocks.META_UPPER) != 0, 5.0), "the server placed both halves of the door")
	await _until(func(): return p.target.get("pos", Vector3i.MIN) in [door, up], 2.0)
	check(p.interact_text() == "Open the wooden door", "looking at it offers E (%s)" % p.interact_text())
	await _press(KEY_E)
	check(await _until(func(): return w.get_blockv(door) == Blocks.WOOD_DOOR_OPEN and w.get_blockv(up) == Blocks.WOOD_DOOR_OPEN, 3.0), "E opens it, both halves")
	await _wait(1.0)
	check(w.get_blockv(door) == Blocks.WOOD_DOOR_OPEN, "and the server agrees")
	await _shot("03_door_open")
	await _press(KEY_E)
	check(await _until(func(): return w.get_blockv(door) == Blocks.WOOD_DOOR and w.get_blockv(up) == Blocks.WOOD_DOOR, 3.0), "E closes it again")
	await _wait(1.0)
	await _hash_check("doors and their facings match the server's", _chunk_of(door))
	# A storage box: put the planks in, take them out again.
	var box := _free_spot([door])
	check(box != Vector3i.MIN, "room for a box (%s)" % box)
	if box == Vector3i.MIN:
		return
	await _hold(Blocks.WOOD_BOX)
	check(p.try_place(box, Blocks.WOOD_BOX), "placed a storage box")
	await _until(func(): return _server_count(Blocks.WOOD_BOX) == 0 and w.get_blockv(box) == Blocks.WOOD_BOX, 5.0)
	_look_at(Vector3(box) + Vector3(0.5, 0.4, 0.5))
	await _until(func(): return p.target.get("pos", Vector3i.MIN) == box, 2.0)
	await _press(KEY_E)
	check(await _until(func(): return g.state == "menu" and G.net.box_open and G.net.box_pos == box and G.net.box_slots.size() == 18, 5.0),
		"E opens the box (%d slots)" % G.net.box_slots.size())
	var planks0 := _server_count(Blocks.PLANKS)
	G.hud._on_slot(_slot_of(Blocks.PLANKS))
	var in_box := func(): return G.net.box_slots.filter(func(st): return st != null and int(st["id"]) == Blocks.PLANKS).size()
	check(await _until(func(): return in_box.call() > 0 and _server_count(Blocks.PLANKS) < planks0, 5.0), "put planks in the box")
	await _shot("03_box")
	for i in G.net.box_slots.size():
		if G.net.box_slots[i] != null:
			G.hud._on_slot(-1 - i)
			break
	check(await _until(func(): return in_box.call() == 0 and _server_count(Blocks.PLANKS) == planks0, 5.0), "and took them out again")
	await _press(KEY_E)
	check(g.state == "playing", "E closes the box")
	# The mallet: a wood frame upgraded to planks (2 planks), then repaired (1 plank).
	var fr := _free_spot([door, box])
	check(fr != Vector3i.MIN, "room for a frame (%s)" % fr)
	if fr == Vector3i.MIN:
		return
	await _hold(Blocks.WOOD_FRAME)
	check(p.try_place(fr, Blocks.WOOD_FRAME), "placed a wood frame")
	await _until(func(): return w.get_blockv(fr) == Blocks.WOOD_FRAME and _server_count(Blocks.WOOD_FRAME) == 1, 5.0)
	await _hold(Items.WOOD_MALLET)
	_look_at(Vector3(fr) + Vector3(0.5, 0.5, 0.5))
	await _until(func(): return p.target.get("pos", Vector3i.MIN) == fr, 2.0)
	check(p.hammer_text()[1], "the mallet offers an upgrade (%s)" % p.hammer_text()[0])
	planks0 = _server_count(Blocks.PLANKS)
	check(await _hammer_until(fr, func(): return w.get_blockv(fr) == Blocks.PLANKS), "the mallet upgrades the frame to planks")
	check(await _until(func(): return _server_count(Blocks.PLANKS) == planks0 - 2, 3.0), "for 2 planks (%d -> %d)" % [planks0, _server_count(Blocks.PLANKS)])
	G.net.send_chat("/damage %d %d %d 30" % [fr.x, fr.y, fr.z])
	check(await _until(func(): return w.damage_of(fr) > 0.0, 5.0), "zombie damage shows on it")
	check(p.hammer_text()[0].begins_with("Repair"), "the mallet offers a repair (%s)" % p.hammer_text()[0])
	planks0 = _server_count(Blocks.PLANKS)
	check(await _hammer_until(fr, func(): return w.damage_of(fr) == 0.0), "the mallet repairs it")
	check(await _until(func(): return _server_count(Blocks.PLANKS) == planks0 - 1 and w.get_blockv(fr) == Blocks.PLANKS, 3.0), "for 1 plank")


## Work on a block with the hammer in hand until done() or 8 s: one full blow per hammer time,
## as holding the button does (the player's mining loop resets the progress while no button is
## held, so each blow is given at once).
func _hammer_until(b: Vector3i, done: Callable) -> bool:
	var p = G.player
	var secs: float = Items.hammer_time(p.cur_id())
	var t0 := Time.get_ticks_msec()
	while not done.call() and Time.get_ticks_msec() - t0 < 8000:
		if p.target.get("pos", Vector3i.MIN) == b:
			p._hammer(b, secs + 0.01)
		await _wait(secs)
	return done.call()


## M4.3: a spear thrown at the ground stays there and E picks it up again; a zombie shot with the
## bow (the crosshair marks every hit) and with the crossbow, which reloads by itself.
func _ranged() -> void:
	var p = G.player
	var g = G.game
	if p.dead:
		g.respawn()
		await _until(func(): return g.state == "playing", 10.0)
	var look := Vector2(p.head.rotation.y, p.cam.rotation.x)  # (looked at again at the end)
	await _ranged_shots()
	p.set_look(look.x, look.y)
	await _clear_mobs()


func _ranged_shots() -> void:
	var p = G.player
	await _clear_mobs()
	for give in ["wooden_spear", "bow", "stone_arrow 12", "crossbow", "iron_bolt 6"]:
		G.net.send_chat("/give " + give)
	check(await _until(func(): return _count(Items.WOOD_SPEAR) == 1 and _count(Items.BOW) == 1 and _count(Items.STONE_ARROW) >= 12 \
		and _count(Items.CROSSBOW) == 1 and _count(Items.IRON_BOLT) >= 6, 10.0), "/give the spear, bow, crossbow and their ammo")
	# The spear.
	var spot := _free_spot([])
	check(spot != Vector3i.MIN, "somewhere to throw a spear at (%s)" % spot)
	if spot == Vector3i.MIN:
		return
	await _hold(Items.WOOD_SPEAR)
	_look_at(Vector3(spot) + Vector3(0.5, 0.02, 0.5))
	var before: Array = G.net.ground.keys()
	p._shoot(Items.WOOD_SPEAR, 0.5)
	check(await _until(func(): return _server_count(Items.WOOD_SPEAR) == 0, 3.0), "the thrown spear left our hands")
	check(await _until(func(): return G.net.ground.keys().any(func(id): return not before.has(id)), 5.0),
		"it lies where it landed (%d things on the ground)" % G.net.ground.size())
	var gid := -1
	for id in G.net.ground:
		if not before.has(id):
			gid = id
	if gid < 0:
		return
	_look_at(G.net.ground[gid]["pos"])
	await _wait(0.3)
	check(p.interact_text() == "Pick up the Wooden Spear", "looking at it offers E (%s)" % p.interact_text())
	await _press(KEY_E)
	check(await _until(func(): return _count(Items.WOOD_SPEAR) == 1 and not G.net.ground.has(gid), 4.0), "E picks it up again")
	# The bow, at a zombie coming for us.
	var zid: int = await _target_zombie()
	check(zid != 0, "/spawn zombie, for target practice, and it comes into view")
	if zid == 0:
		return
	await _hold(Items.BOW)
	var arrows0 := _server_count(Items.STONE_ARROW)
	var hits := 0
	var killed := false
	for k in 10:
		if not _zombie_alive(zid):
			break
		_aim_at(zid)
		p.hit_mark = 0.0
		p._shoot(Items.BOW, 1.0)
		if await _until(func(): return p.hit_mark > 0.0, 1.5):
			hits += 1
			killed = killed or p.hit_kind == Proto.HIT_KILL
		await _wait(0.7)
	check(hits >= 1, "arrows hit the zombie (%d of them; the crosshair marked each)" % hits)
	check(await _until(func(): return _server_count(Items.STONE_ARROW) < arrows0, 3.0), "each shot took an arrow (%d -> %d)" % [arrows0, _server_count(Items.STONE_ARROW)])
	check(killed, "the arrows killed it")
	# The crossbow: it loads itself after a moment, a bolt a shot.
	await _clear_mobs()
	await _hold(Items.CROSSBOW)
	check(await _until(func(): return p.xbow_loaded, 4.0), "the crossbow loads itself")
	zid = await _target_zombie()
	if zid == 0 or not p.xbow_loaded:
		check(false, "a zombie for the crossbow")
		return
	var bolts0 := _server_count(Items.IRON_BOLT)
	var xhit := false
	for k in 4:
		await _until(func(): return p.xbow_loaded, 4.0)
		if not _zombie_alive(zid):
			break
		_aim_at(zid)
		p.hit_mark = 0.0
		p._shoot(Items.CROSSBOW, 1.0)
		if k == 0:
			check(not p.xbow_loaded, "shooting empties it")
		if await _until(func(): return p.hit_mark > 0.0, 1.5):
			xhit = true
			break
	check(xhit, "a bolt hits the zombie")
	check(await _until(func(): return _server_count(Items.IRON_BOLT) < bolts0, 3.0), "and the bolt is used up")
	await _clear_mobs()


## /spawn a zombie and wait until it is coming for us within 14 m with nothing in between. Its id,
## or 0.
func _target_zombie() -> int:
	var kinds := [Proto.MOB_ZOMBIE, Proto.MOB_NIGHT]
	var p = G.player
	# A zombie can land behind a tree or a hill and wander off: then try another (up to three).
	for attempt in 3:
		var before: Array = G.net.mobs.keys()
		G.net.send_chat("/spawn zombie 1")
		if not await _until(func(): return _mob_ids(kinds).any(func(id): return not before.has(id)), 10.0):
			continue
		var zid := 0
		for id in _mob_ids(kinds):
			if not before.has(id):
				zid = id
		var clear := func():
			if not _zombie_alive(zid) or _mob_dist(zid) > 14.0:
				return false
			var at: Vector3 = (G.net.mobs[zid]["samples"].back()[1] as Vector3) + Vector3(0, 1.1, 0)
			var eye: Vector3 = p.cam.global_position
			var hit: Dictionary = G.world.raycast(eye, (at - eye).normalized(), eye.distance_to(at))
			return not hit.get("hit", false)
		if await _until(clear, 20.0):
			return zid
		print("AUTOTEST zombie %d stayed out of sight, spawning another" % zid)
	return 0


func _zombie_alive(id: int) -> bool:
	return G.net.mobs.has(id) and not G.net.mobs[id]["samples"].is_empty() \
		and (int(G.net.mobs[id]["samples"].back()[4]) & Proto.MF_DEAD) == 0


## Look at a zombie's chest where it will be when an arrow gets there (a little ahead of it, and
## above for the drop).
func _aim_at(id: int) -> void:
	var smp: Array = G.net.mobs[id]["samples"]
	var at: Vector3 = smp.back()[1]
	var vel := Vector3.ZERO
	if smp.size() >= 2:
		var a: Array = smp[smp.size() - 2]
		var b: Array = smp.back()
		vel = ((b[1] as Vector3) - (a[1] as Vector3)) / maxf(0.02, float(b[0]) - float(a[0]))
	var d := at.distance_to(G.player.global_position)
	var t := d / 55.0 + 0.1
	_look_at(at + vel * t + Vector3(0, 1.1 + 4.9 * t * t, 0))
