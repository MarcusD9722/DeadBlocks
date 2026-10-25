extends Node
## Pictures of the world for judging the graphics: `-- --scenery --shots=DIR [--gfx=0-3]` with a
## real renderer. A view over the land at noon, at dusk, at night with the flashlight and under a
## Blood Moon, a cave, and a little plank hut lit by torches at night.

const ZombieScript := preload("res://scripts/zombie.gd")

var dir := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(name: String, settle := 1.5) -> void:
	var only := G.arg_value("--only=")
	if only != "" and not name.contains(only):
		return
	await _wait(settle)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("SHOT " + name)


func _clock(t: float, day := 1) -> void:
	var g = G.game
	g.day = day
	g.time = t
	g.horde_active = day % 7 == 0 and (t >= 20.0 or t < 5.0)


func _run() -> void:
	dir = G.arg_value("--shots=")
	var g = G.game
	var w = G.world
	while g.state == "loading":
		await _wait(0.25)
	g.start_game()
	for m in get_tree().get_nodes_in_group("mobs"):
		m.queue_free()
	var p = G.player
	var sp: Vector3 = g.spawn_pos
	# A hill-top view: the highest ground near the spawn.
	var best := Vector3i(floori(sp.x), w.surface_y(floori(sp.x), floori(sp.z)), floori(sp.z))
	for dz in range(-24, 25, 3):
		for dx in range(-24, 25, 3):
			var x := floori(sp.x) + dx
			var z := floori(sp.z) + dz
			var y: int = w.surface_y(x, z)
			if y > best.y and Blocks.SOLID[w.get_block(x, y, z)] and w.get_block(x, y, z) != Blocks.LEAVES and w.get_block(x, y, z) != Blocks.LOG:
				best = Vector3i(x, y, z)
	_place(p, Vector3(best) + Vector3(0.5, 1.02, 0.5), 0.6, -0.18)
	await _wait(3.0)
	_clock(12.0)
	if G.arg_value("--only=") == "screens":
		await _screens(p, w, best)  # (only the menus: quick)
		get_tree().quit()
		return
	await _shot("01_noon")
	_place(p, Vector3(best) + Vector3(0.5, 1.02, 0.5), 2.4, -0.3)
	await _shot("02_noon_other_way")
	_clock(18.9)
	_place(p, Vector3(best) + Vector3(0.5, 1.02, 0.5), 0.9, -0.12)
	await _shot("03_dusk")
	# Zombies in front of us for the night shots.
	var zs := []
	for i in 4:
		var at := Vector3(best) + Vector3(-2.0 + i * 1.4, 0.0, -6.0 - i % 2 * 2.0)
		var y: int = w.surface_y(floori(at.x), floori(at.z))
		var z := ZombieScript.new()
		z.setup("night", 1, ["walker", "runner", "brute", "spitter"][i])
		z.view = true
		g.mobs.add_child(z)
		z.global_position = Vector3(at.x, y + 1.0, at.z)
		z.rotation.y = 0.0
		zs.append(z)
	_place(p, Vector3(best) + Vector3(0.5, 1.02, 0.5), 0.0, -0.25)
	_clock(23.0)
	p.flashlight.visible = true
	await _shot("04_night_flashlight")
	for z in zs:
		z.queue_free()
	zs.clear()
	for i in 4:
		var at := Vector3(best) + Vector3(-2.0 + i * 1.4, 0.0, -6.0 - i % 2 * 2.0)
		var y: int = w.surface_y(floori(at.x), floori(at.z))
		var z := ZombieScript.new()
		z.setup("horde", 7, ["walker", "runner", "brute", "screamer"][i])
		z.view = true
		g.mobs.add_child(z)
		z.global_position = Vector3(at.x, y + 1.0, at.z)
		zs.append(z)
	p.flashlight.visible = false
	_clock(21.0, 7)
	await _shot("05_blood_moon")
	for z in zs:
		z.queue_free()
	await _cave(p, w, sp)
	await _hut(p, w, best)
	await _slope_and_death(p, w, best)
	await _settings()
	get_tree().quit()


func _place(p, at: Vector3, yaw: float, pitch: float) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.set_look(yaw, pitch)


## Inside a cave (the first big hollow found under the land), by day: it should be dark.
func _cave(p, w, sp: Vector3) -> void:
	_clock(12.0)
	for r in range(0, 40, 2):
		for dz in range(-r, r + 1, 2):
			for dx in range(-r, r + 1, 2):
				var x := floori(sp.x) + dx
				var z := floori(sp.z) + dz
				var top: int = w.surface_y(x, z)
				for y in range(8, top - 6):
					if w.get_block(x, y, z) == 0 and w.get_block(x, y + 1, z) == 0 and Blocks.is_solid(w.get_block(x, y - 1, z)) and _roomy(w, x, y, z):
						_place(p, Vector3(x + 0.5, y + 0.02, z + 0.5), 0.0, 0.0)
						await _wait(2.0)
						print("SCENERY cave at %s, player at %s, blocks at feet/head %d %d" % [Vector3i(x, y, z), p.global_position, w.get_blockv(Vector3i(p.global_position.floor())), w.get_blockv(Vector3i((p.global_position + Vector3(0, 1.62, 0)).floor()))])
						await _shot("06_cave_day")
						p.flashlight.visible = true
						await _shot("07_cave_flashlight")
						p.flashlight.visible = false
						for v in [[0, 50], [100, 50], [100, 80]]:
							G.gfx.set_opt("cave_light", v[0])
							G.gfx.set_opt("brightness", v[1])
							await _shot("07_cave_light%d_brightness%d" % v)
						G.gfx.reset_settings()
						return
	print("SCENERY no cave found")


func _roomy(w, x: int, y: int, z: int) -> bool:
	var n := 0
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			if w.get_block(x + dx, y + 1, z + dz) == 0:
				n += 1
	return n > 30


## A small plank hut with torches, at night.
func _hut(p, w, best: Vector3i) -> void:
	w.sync_mesh = true  # the edits below show at once
	var o := best + Vector3i(4, 1, 4)
	o.y = w.surface_y(o.x + 2, o.z + 2) + 1
	# A clearing: no trees between the camera and the hut.
	for dz in range(-9, 7):
		for dx in range(-3, 8):
			for dy in range(0, 14):
				var c := o + Vector3i(dx, dy, dz)
				if w.get_blockv(c) != 0:
					w.set_block(c, 0)
	for dz in range(0, 5):
		for dx in range(0, 5):
			w.set_block(o + Vector3i(dx, -1, dz), Blocks.COBBLE)
			for dy in range(0, 4):
				var wall := dx == 0 or dx == 4 or dz == 0 or dz == 4
				var door := dz == 0 and dx == 2 and dy < 2
				w.set_block(o + Vector3i(dx, dy, dz), Blocks.PLANKS if wall and not door else (Blocks.STONE_BRICK if dy == 3 else 0))
	w.set_block(o + Vector3i(1, 0, 3), Blocks.WORKBENCH)
	w.set_block(o + Vector3i(3, 0, 3), Blocks.TORCH)
	w.set_block(o + Vector3i(1, 0, -1), Blocks.TORCH)
	w.set_block(o + Vector3i(3, 0, -1), Blocks.CAMPFIRE)
	_clock(22.0)
	var cam := o + Vector3i(2, 0, -7)
	w.set_block(cam + Vector3i(0, -1, 0), Blocks.COBBLE)  # stand level with the hut
	_place(p, Vector3(cam) + Vector3(0.5, 0.02, 0.5), PI, -0.05)
	await _wait(2.0)
	print("SCENERY hut at %s (wall block %d), camera at %s looking %s" % [o, w.get_blockv(o + Vector3i(0, 1, 0)), p.global_position, -p.cam.global_transform.basis.z])
	await _shot("08_hut_night")
	_clock(11.0)
	await _shot("09_hut_day")


## Zombies on a hillside standing on the drawn (rounded) ground, then one dying: falling over,
## lying, sinking away. Their pictures are measured here as game.gd does for an online game.
func _slope_and_death(p, w, best: Vector3i) -> void:
	var g = G.game
	_clock(12.0)
	# The steepest drop near the hill top: stand zombies across it.
	var spot := best
	var drop := 0
	for dz in range(-12, 13):
		for dx in range(-12, 13):
			var x := best.x + dx
			var z := best.z + dz
			var y: int = w.surface_y(x, z)
			var y2: int = w.surface_y(x + 1, z)
			if y - y2 > drop and y - y2 <= 2 and Blocks.SOLID[w.get_block(x, y, z)] and w.get_block(x, y, z) != Blocks.LEAVES:
				drop = y - y2
				spot = Vector3i(x, y, z)
	var zs := []
	for i in 5:
		var at := Vector3(spot.x + 0.15 + i * 0.35, 0.0, spot.z + 0.5 + (i - 2) * 1.1)
		var y: int = w.surface_y(floori(at.x), floori(at.z))
		var z := ZombieScript.new()
		z.setup("night", 1, "walker")
		z.view = true
		z.net_id = 100 + i
		g.mobs.add_child(z)
		z.global_position = Vector3(at.x, y + 1.0, at.z)
		z.rotation.y = -PI * 0.5
		zs.append(z)
	_place(p, Vector3(spot.x + 6.5, w.surface_y(spot.x + 6, spot.z) + 1.02, spot.z + 0.5), PI * 0.5, -0.15)
	await _wait(1.0)
	await _shot("10_slope_blocks")
	for k in 2:
		await get_tree().physics_frame
		var space: PhysicsDirectSpaceState3D = g.get_world_3d().direct_space_state
		for z in zs:
			z.ground_target = g._ground_offset(space, z, z.half * 0.5)
	for z in zs:
		z.ground_off = z.ground_target
		z.model.position.y = z.ground_off
		print("SCENERY zombie at %.2f stands %.2f lower/higher on the drawn ground" % [z.global_position.x, z.ground_off])
	await _shot("11_slope_drawn_ground")
	var dying = zs[2]
	dying.view_update(dying.global_position, dying.rotation.y, Proto.MF_DEAD, 0.016)
	await _wait(0.25)
	await _shot("12_death_falling", 0.0)
	await _wait(1.0)
	await _shot("13_death_lying", 0.0)
	await _wait(2.2)
	await _shot("14_death_sinking", 0.0)
	for z in zs:
		if is_instance_valid(z):
			z.queue_free()


## The Settings screen over the game.
func _settings() -> void:
	G.hud.settings.open()
	await _shot("15_settings")
	G.hud.settings.close()


## `--only=screens`: the inventory (hand crafting), a workbench's and a Blood Forge's screens
## with the new tools in the bag, the Settings screen at its controls, and the E prompt.
func _screens(p, w, best: Vector3i) -> void:
	for id in [Items.WOOD_SHOVEL, Items.STONE_SHOVEL, Items.IRON_SHOVEL, Items.STEEL_SHOVEL, Items.BLOOD_SHOVEL,
			Items.STEEL_PICK, Items.STEEL_AXE, Items.STEEL_SWORD, Items.BLOOD_PICK, Items.BLOOD_AXE, Items.BLOOD_SWORD,
			Items.STEEL_INGOT, Items.BLOOD_INGOT, Blocks.BLOOD_FORGE, Blocks.BLOOD_BRICK]:
		p.inv.add(id, 1)
	p.inv.add(Items.BLOOD_SHARD, 12)
	p.inv.add(Blocks.PLANKS, 20)
	p.inv.add(Items.STICK, 8)
	var at := best + Vector3i(2, 1, 0)
	w.set_block(at, Blocks.WORKBENCH)
	w.set_block(at + Vector3i(0, 0, 2), Blocks.BLOOD_FORGE)
	w.set_block(at + Vector3i(0, 0, -2), Blocks.BLOOD_BRICK)
	await _wait(2.0)
	var eye: Vector3 = p.cam.global_position
	var d := Vector3(at) + Vector3(0.5, 0.5, 0.5) - eye
	p.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	await _wait(1.0)
	await _shot("screens_1_prompt", 0.5)
	for st in ["", "workbench", "bloodforge"]:
		G.game.open_inventory(st)
		await _shot("screens_2_%s" % ("inventory" if st == "" else st), 0.5)
		G.game.close_inventory()
	G.hud.settings.open()
	var sc: ScrollContainer = G.hud.settings.find_children("*", "ScrollContainer", true, false)[0]
	await _wait(0.3)
	sc.scroll_vertical = 100000
	await _shot("screens_3_settings_controls", 0.5)
	G.hud.settings.close()
