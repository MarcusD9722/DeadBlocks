extends Node
## A picture of every zombie type side by side (night look in front, walking; Blood Moon look
## behind, standing) and an acid glob, then one of boars and other players' survivors (walking,
## swinging, holding things), for checking how they look: `-- --lineup --shots=DIR` with a real
## renderer.

const ZombieScript := preload("res://scripts/zombie.gd")
const AcidScript := preload("res://scripts/acid.gd")
const AnimalScript := preload("res://scripts/animal.gd")
const RemotePlayerScript := preload("res://scripts/net/remote_player.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _run() -> void:
	var g = G.game
	var w = G.world
	while g.state == "loading":
		await _wait(0.25)
	g.start_game()
	g.time = 10.0
	for m in get_tree().get_nodes_in_group("mobs"):
		m.queue_free()
	var o := Vector3i(floori(g.spawn_pos.x), 52, floori(g.spawn_pos.z))
	for z in range(-10, 9):
		for x in range(-8, 9):
			w.set_block(o + Vector3i(x, 0, z), Blocks.GRASS)
	await _wait(1.0)
	var types: Array = ZombieScript.TYPES
	var walkers := []
	for row in 2:
		for i in types.size():
			var v := ZombieScript.new()
			v.setup("night" if row == 0 else "horde", 1, types[i])
			v.view = true
			g.mobs.add_child(v)
			v.global_position = Vector3(o) + Vector3((i - 2.5) * 2.2 + 0.5, 1.0, 0.5 + row * 3.0)
			v.rotation.y = PI  # facing the camera
			if row == 0:
				walkers.append(v)
	var acid := AcidScript.new()
	acid.view = true
	g.mobs.add_child(acid)
	acid.global_position = Vector3(o) + Vector3(6.5, 2.2, -1.0)
	var p = G.player
	p.global_position = Vector3(o) + Vector3(0.5, 1.0, -7.5)
	p.velocity = Vector3.ZERO
	p.set_look(PI, -0.12)
	# The front row walks at its night speed (in place), the back row stands.
	# (big steps: a software renderer takes seconds per frame)
	for f in 12:
		await get_tree().process_frame
		p.global_position = Vector3(o) + Vector3(0.5, 1.0, -7.5)  # (slow frames: don't let it fall)
		p.velocity = Vector3.ZERO
		for v in walkers:
			v._pose(v.speed, 0.1)
	await _shot("lineup")
	for m in get_tree().get_nodes_in_group("mobs"):
		m.queue_free()
	acid.queue_free()
	# Boars (one walking) and survivors: walking with a pickaxe, chopping, standing with a torch.
	var boars := []
	for i in 2:
		var b := AnimalScript.new()
		b.view = true
		g.mobs.add_child(b)
		b.global_position = Vector3(o) + Vector3(-3.5 + i * 2.0, 1.0, 1.0)
		b.rotation.y = PI * (0.75 if i == 0 else 1.25)
		boars.append(b)
	var people := []
	var looks := [[Items.STONE_PICK, 4.4, 0], [Items.STONE_AXE, 0.0, Proto.F_SWING], [Blocks.TORCH, 0.0, 0], [0, 6.9, 0]]
	for i in looks.size():
		var rp := RemotePlayerScript.new()
		rp.net_id = i
		add_child(rp)
		rp.set_process(false)  # (driven from here, not by snapshots)
		rp.show_state(Vector3(o) + Vector3(1.0 + i * 1.6, 1.0, 1.5), 0.0, 0.0, looks[i][2], looks[i][0], 0.0)
		people.append(rp)
	for f in 10:
		await get_tree().process_frame
		p.global_position = Vector3(o) + Vector3(0.5, 1.0, -7.5)
		p.velocity = Vector3.ZERO
		boars[0]._pose(1.3, 0.1)
		boars[0].anim += 1.3 * 3.2 * 0.1
		boars[1]._pose(0.0, 0.1)
		for i in people.size():
			if people[i].rig != null:
				people[i]._animate_rig(looks[i][1], looks[i][2], false, 0.1)
	await _shot("lineup_others")
	get_tree().quit()


func _shot(name: String) -> void:
	var dir := G.arg_value("--shots=")
	if dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("SHOT " + name)
