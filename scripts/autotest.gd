extends "res://scripts/tests/nettest.gd"
## Automated playtest: `-- --autotest [--seed=4242] [--shots=DIR]`.
## Presses Play solo (a new world called "autotest", so the player's own solo world is left
## alone) and plays it through the real client against the game's own local server: mining,
## crafting at a workbench, a pickaxe, eating, a horde breaking a wall, fighting, death and
## respawn with the backpack, a Blood Moon and its dawn, boars, the pause menu stopping the
## world, and quitting and continuing with everything still there.
## Prints AUTOTEST PASS/FAIL lines and ends with `AUTOTEST DONE fails=N`.

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

	# Crafting: planks and sticks, nothing without a workbench, then a pickaxe at one.
	G.net.send_chat("/give log 5")
	check(await _until(func(): return _count(Blocks.LOG) >= 6, 10.0), "/give works in solo (we're the admin)")
	G.net.request_craft(_recipe(Blocks.PLANKS), 3)
	G.net.request_craft(_recipe(Items.STICK), 1)
	check(await _until(func(): return _count(Blocks.PLANKS) == 10 and _count(Items.STICK) == 4, 5.0),
		"crafted planks and sticks (%d planks, %d sticks)" % [_count(Blocks.PLANKS), _count(Items.STICK)])
	G.net.request_craft(_recipe(Items.WOOD_PICK), 1)
	await _wait(1.0)
	check(_count(Items.WOOD_PICK) == 0, "no pickaxe without a workbench")
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
	G.net.request_craft(_recipe(Items.WOOD_PICK), 1)
	check(await _until(func(): return _count(Items.WOOD_PICK) == 1, 5.0), "crafted a wooden pickaxe at the workbench")

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
	var ring: Array = await _wall_in()
	var solid := func(): return ring.filter(func(b): return w.get_blockv(b) != Blocks.AIR)
	check(solid.call().size() >= 14, "walled ourselves in (%d of 16 solid)" % solid.call().size())
	var walled: Array = solid.call()
	var before: Array = G.net.mobs.keys()
	G.net.send_chat("/spawn horde 4")
	check(await _until(func(): return _mob_ids([Proto.MOB_HORDE]).size() >= 3, 10.0), "a horde appears")
	await _wait(2.0)
	await _shot("04_night_horde")
	check(await _until(func(): return int(G.net.bytes_in.get(Proto.S_CRACKS, 0)) > 0, 75.0), "the horde cracks blocks")
	var hp0: float = p.health
	check(await _until(func(): return walled.any(func(b): return w.get_blockv(b) == Blocks.AIR) or p.health < hp0, 90.0),
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
	check(await _until(func(): return _mob_ids([Proto.MOB_HORDE]).size() >= 4, 25.0), "the horde comes (%d)" % _mob_ids([Proto.MOB_HORDE]).size())
	p.set_look(PI, -0.05)
	await _wait(0.3)
	await _shot("06_blood_moon")
	if p.dead:
		g.respawn()
		await _until(func(): return g.state == "playing", 10.0)
	G.net.send_chat("/time 5.98")
	check(await _until(func(): return not g.horde_active, 20.0), "the horde ends at dawn")
	check(await _until(func(): return _mob_ids([Proto.MOB_HORDE]).is_empty(), 10.0),
		"the horde calms down into day zombies (%d still horde)" % _mob_ids([Proto.MOB_HORDE]).size())
	check(await _until(func(): return g.mob_views.values().all(func(v): return not is_instance_valid(v) or v.net_kind() != Proto.MOB_HORDE), 5.0),
		"and they look like day zombies again")

	# Stuck somewhere: the pause menu's Die and Respawn, falling out of the world, being buried.
	# Each death drops a backpack, which we pick up again.
	if p.dead:
		g.respawn()
		await _until(func(): return g.state == "playing", 10.0)
	var zs0: Array = _mob_ids([Proto.MOB_ZOMBIE, Proto.MOB_NIGHT, Proto.MOB_HORDE])
	G.net.send_chat("/clear")
	check(await _until(func(): return _has_notice("Removed ") and zs0.all(func(id): return not G.net.mobs.has(id)), 10.0),
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
	await _mine_backpack(bp)
	check(await _until(func(): return _count(Blocks.PLANKS) == 7 and G.net.my_backpacks.size() == 1 and w.get_blockv(bp) == Blocks.AIR, 5.0),
		"mining the backpack gives everything back (%d planks)" % _count(Blocks.PLANKS))
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
