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


func _shot(name: String) -> void:
	var only := G.arg_value("--only=")
	if only != "" and not name.contains(only):
		return
	await _wait(1.5)
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
