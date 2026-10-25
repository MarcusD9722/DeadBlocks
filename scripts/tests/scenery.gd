extends Node
## Pictures of the world for judging the graphics: `-- --scenery --shots=DIR [--gfx=0-3]` with a
## real renderer. A view over the land at noon, at dusk, at night with the flashlight and under a
## Blood Moon, a cave, a little plank hut lit by torches at night, and the building blocks (every
## tier in every shape; doors, hatches and boxes).

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
	if G.arg_value("--only=").begins_with("screens"):
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
	await _building(p, w, best)
	await _held(p, w, best)
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
	w.set_block(o + Vector3i(3, 0, 1), Blocks.WOOD_BOX)
	# (the door faces the way someone outside looks in: +Z)
	w.set_block(o + Vector3i(2, 0, 0), Blocks.WOOD_DOOR, 0)
	w.set_block(o + Vector3i(2, 1, 0), Blocks.WOOD_DOOR, Blocks.META_UPPER)
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
	w.set_block(o + Vector3i(2, 0, 0), Blocks.WOOD_DOOR_OPEN, 0)
	w.set_block(o + Vector3i(2, 1, 0), Blocks.WOOD_DOOR_OPEN, Blocks.META_UPPER)
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
## M4.2's building blocks at noon: the six tiers as pillars, ramps, half blocks and full blocks
## (front to back), then the doors, hatches and boxes in a plank wall.
func _building(p, w, best: Vector3i) -> void:
	w.sync_mesh = true
	var o := best + Vector3i(-14, 0, 6)
	o.y = w.surface_y(o.x + 5, o.z + 3) + 1
	for dz in range(-10, 12):
		for dx in range(-3, 15):
			w.set_block(o + Vector3i(dx, -1, dz), Blocks.COBBLE)
			for dy in range(0, 12):
				if w.get_blockv(o + Vector3i(dx, dy, dz)) != 0:
					w.set_block(o + Vector3i(dx, dy, dz), 0)
	for t in 6:
		var x := t * 2
		w.set_block(o + Vector3i(x, 0, 0), Blocks.FRAME_PILLAR + t)
		w.set_block(o + Vector3i(x, 0, 2), Blocks.FRAME_RAMP + t, 0)
		w.set_block(o + Vector3i(x, 0, 4), Blocks.FRAME_HALF + t)
		w.set_block(o + Vector3i(x, 1, 4), Blocks.FRAME_HALF + t, Blocks.META_UPPER)
		w.set_block(o + Vector3i(x, 0, 6), Blocks.TIER_BLOCKS[t])
		w.set_block(o + Vector3i(x, 1, 6), Blocks.TIER_BLOCKS[t])
	_clock(12.0)
	_place(p, Vector3(o) + Vector3(5.5, 2.5, -6.0), PI, -0.32)
	await _wait(2.0)
	await _shot("16_build_tiers")
	# Doors (wood closed, iron open, steel closed), hatches in the floor in front, two boxes.
	for t in 6:
		for dz in range(0, 7):
			for dy in range(0, 2):
				w.set_block(o + Vector3i(t * 2, dy, dz), 0)
	for dx in range(0, 11):
		for dy in range(0, 3):
			w.set_block(o + Vector3i(dx, dy, 4), Blocks.STONE_BRICK)
	var doors := [[Blocks.WOOD_DOOR, 1], [Blocks.IRON_DOOR_OPEN, 4], [Blocks.STEEL_DOOR, 7]]
	for d in doors:
		w.set_block(o + Vector3i(d[1], 0, 4), d[0], 0)
		w.set_block(o + Vector3i(d[1], 1, 4), d[0], Blocks.META_UPPER)
	var hatches := [[Blocks.WOOD_HATCH, 1], [Blocks.IRON_HATCH, 4], [Blocks.STEEL_HATCH_OPEN, 7]]
	for h in hatches:
		w.set_block(o + Vector3i(h[1], -1, 1), h[0], Blocks.META_UPPER)  # (flush with the floor)
	w.set_block(o + Vector3i(9, 0, 2), Blocks.WOOD_BOX)
	w.set_block(o + Vector3i(10, 0, 2), Blocks.IRON_BOX)
	_place(p, Vector3(o) + Vector3(5.5, 1.2, -4.0), PI, -0.22)
	await _wait(2.0)
	await _shot("17_build_doors")


## M4.3: tools and weapons in hand (3D models), the hotbar's icons drawn from them, and a spear
## and arrows stuck in the ground with one in flight.
func _held(p, w, best: Vector3i) -> void:
	var only := G.arg_value("--only=")
	if only != "" and not "18_held".contains(only):
		return
	_clock(11.0)
	_place(p, Vector3(best) + Vector3(0.5, 1.02, 0.5), 2.0, -0.12)
	var items := [Items.IRON_PICK, Items.STONE_AXE, Items.STEEL_SWORD, Items.BOW, Items.CROSSBOW, Items.IRON_SPEAR,
		Items.BLOOD_HAMMER, Items.STEEL_SHOVEL, Items.IRON_ARROW]
	for i in 9:
		p.inv.slots[i] = {"id": items[i], "n": 24 if i == 8 else 1}
	p.inv.changed.emit()
	var t0 := Time.get_ticks_msec()
	while ToolModels.icons.is_empty() and Time.get_ticks_msec() - t0 < 30000:
		await _wait(0.5)
	p.set_process(false)  # (holds the poses below still)
	var poses := [[0, "swing", 0.0, "18_held_1_pickaxe"], [0, "swing", 0.55, "18_held_2_pickaxe_swing"], [2, "swing", 0.0, "18_held_3_sword"],
		[3, "draw", 0.85, "18_held_4_bow_drawn"], [4, "loaded", 1.0, "18_held_5_crossbow"], [5, "charge", 0.7, "18_held_6_spear_throw"],
		[6, "swing", 0.0, "18_held_7_hammer"]]
	for pose in poses:
		p.select(pose[0])
		p.swing = pose[2] if pose[1] == "swing" else 0.0
		p.draw = pose[2] if pose[1] == "draw" else 0.0
		p.charge = pose[2] if pose[1] == "charge" else 0.0
		p.xbow_loaded = pose[1] == "loaded"
		p._update_held()
		await _shot(pose[3])
	p.select(8)
	p._update_held()
	# A spear and arrows stuck in the ground in front of us, and an arrow on its way.
	var fwd: Vector3 = -p.cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side: Vector3 = fwd.cross(Vector3.UP)
	var base: Vector3 = p.global_position + fwd * 3.2
	var stuck := [[Items.IRON_SPEAR, base + side * 0.6, 0.9], [Items.STONE_ARROW, base - side * 0.4, 0.7], [Items.IRON_ARROW, base - side * 0.9 + fwd * 0.5, 0.5]]
	for k in stuck.size():
		var at: Vector3 = stuck[k][1]
		at.y = w.surface_y(floori(at.x), floori(at.z)) + 1.0
		var yaw := atan2(-fwd.x, -fwd.z) + 0.4 * (k - 1)
		var pitch: float = -stuck[k][2]
		var d := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
		var half: float = 0.95 if k == 0 else 0.35
		G.net.ground[60000 + k] = {"id": 60000 + k, "item": stuck[k][0], "pos": at - d * (half - 0.15), "yaw": yaw, "pitch": pitch}
	G.game._sync_ground()
	var fly := preload("res://scripts/projectile.gd").new()
	fly.item = Items.STONE_ARROW
	fly.view = true
	G.game.mobs.add_child(fly)
	fly.global_position = p.cam.global_position + fwd * 2.2 + side * 0.9 + Vector3(0, 0.1, 0)
	fly.basis = Basis.looking_at(fwd + side * 0.4, Vector3.UP)
	p.set_look(atan2(-fwd.x, -fwd.z), -0.35)
	await _wait(1.0)
	await _shot("18_held_8_ground")
	p.set_process(true)


func _settings() -> void:
	G.hud.settings.open()
	await _shot("15_settings")
	G.hud.settings.close()


## The character screen's Map, Players and Tribe tabs (M4.4). No server runs here, so what it
## would send is set by hand: an explored patch of land around us, two pins, an ally standing
## nearby, a few other players, and a tribe we lead.
func _character_tabs(p) -> void:
	var n = G.net
	var c := Vector2i(floori(p.global_position.x / 16.0), floori(p.global_position.z / 16.0))
	for dz in range(-14, 15):
		for dx in range(-20, 21):
			if Vector2(dx, dz * 1.4).length() < 15.0 + sin(dx * 0.6) * 2.5 + cos(dz * 0.9) * 2.0:
				n.explored[c + Vector2i(dx, dz)] = true
	n.player_name = "Marcus"
	n.host = "pi-server"
	n.pins = [{"name": "Base", "x": floori(p.global_position.x) + 30, "z": floori(p.global_position.z) - 20},
		{"name": "Iron cave", "x": floori(p.global_position.x) - 140, "z": floori(p.global_position.z) + 60}]
	var now := Time.get_ticks_msec() / 1000.0
	n.others[901] = {"name": "Anna", "samples": [[now + 1000.0, p.global_position + Vector3(60, 0, 35), 0.0, 0.0, 0]]}
	n.social = [{"name": "Anna", "id": 901, "ping": 38, "rel": Proto.R_ALLY | Proto.R_TRIBE | Proto.R_ONLINE | Proto.R_BED | Proto.R_IN_TRIBE},
		{"name": "Ben", "id": 0, "ping": 64, "rel": Proto.R_ONLINE | Proto.R_ASKS_YOU},
		{"name": "Chris", "id": 0, "ping": 0, "rel": Proto.R_ALLY},
		{"name": "Dana", "id": 0, "ping": 91, "rel": Proto.R_ONLINE}]
	n.tribe = {"id": 1, "name": "The Survivors", "leader": "Marcus"}
	var md := MapData.new()
	G.game.add_child(md)
	G.game.map_data = md
	var t0 := Time.get_ticks_msec()
	while md.painted.size() < n.explored.size() and Time.get_ticks_msec() - t0 < 60000:
		await _wait(0.25)
	print("SCENERY map: %d of %d chunks painted" % [md.painted.size(), n.explored.size()])
	G.game.open_inventory()
	for t in ["map", "players", "tribe"]:
		G.hud.show_tab(t)
		await _shot("screens_6_%s" % t, 0.6)
	G.hud.show_tab("map")
	G.hud.map_panel.zoom = 0.7
	await _shot("screens_6_map_far", 0.6)
	G.game.close_inventory()


## `--only=screens`: the inventory (hand crafting), a workbench's and a Blood Forge's screens
## with the new tools in the bag, a storage box, the mallet's line under the crosshair, the
## Settings screen at its controls, and the E prompt.
func _screens(p, w, best: Vector3i) -> void:
	for id in [Items.WOOD_SHOVEL, Items.STONE_SHOVEL, Items.IRON_SHOVEL, Items.STEEL_SHOVEL, Items.BLOOD_SHOVEL,
			Items.STEEL_PICK, Items.STEEL_AXE, Items.STEEL_SWORD, Items.BLOOD_PICK, Items.BLOOD_AXE, Items.BLOOD_SWORD,
			Items.STEEL_INGOT, Items.BLOOD_INGOT, Blocks.BLOOD_FORGE, Blocks.BLOOD_BRICK]:
		p.inv.add(id, 1)
	p.inv.add(Items.BLOOD_SHARD, 12)
	p.inv.add(Blocks.PLANKS, 20)
	p.inv.add(Items.STICK, 8)
	w.sync_mesh = true  # the blocks set below show at once
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
	# The box screen (M4.2). No server runs here, so the box's contents are set as its answer would.
	var box := at + Vector3i(0, 0, 4)
	w.set_block(box, Blocks.WOOD_BOX)
	G.game.state = "menu"
	G.hud.show_box(true, box)
	var slots := []
	slots.resize(Blocks.BOX_SLOTS[Blocks.WOOD_BOX])
	var things := [[Blocks.PLANKS, 20], [Blocks.COBBLE, 12], [Items.IRON_INGOT, 5], [Blocks.TORCH, 8], [Items.BERRIES, 3],
		[Items.BLOOD_SHARD, 4], [Blocks.WOOD_DOOR, 1], [Items.STONE_HAMMER, 1]]
	for i in things.size():
		slots[i] = {"id": things[i][0], "n": things[i][1]}
	G.net.box_pos = box
	G.net.box_open = true
	G.net.box_title = Blocks.NAMES[Blocks.WOOD_BOX]
	G.net.box_slots = slots
	G.net.box_changed.emit()
	await _shot("screens_4_box", 0.5)
	G.hud.show_inventory(false)
	G.game.state = "playing"
	await _character_tabs(p)
	# The mallet on a wood frame: the line under the crosshair says what an upgrade costs.
	var fr := at + Vector3i(0, 0, -4)
	w.set_block(fr, Blocks.WOOD_FRAME)
	p.inv.slots[p.selected] = {"id": Items.WOOD_MALLET, "n": 1}
	p.inv.changed.emit()
	await _wait(0.5)
	eye = p.cam.global_position
	d = Vector3(fr) + Vector3(0.5, 0.5, 0.5) - eye
	p.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	await _wait(1.0)
	await _shot("screens_5_hammer", 0.5)
	G.hud.settings.open()
	var sc: ScrollContainer = G.hud.settings.find_children("*", "ScrollContainer", true, false)[0]
	await _wait(0.3)
	sc.scroll_vertical = 100000
	await _shot("screens_3_settings_controls", 0.5)
	G.hud.settings.close()
