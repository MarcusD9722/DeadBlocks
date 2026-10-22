extends Node
## A picture of every zombie type side by side (night look in front, Blood Moon look behind) and
## an acid glob, for checking how they look: `-- --lineup --shots=DIR` with a real renderer.

const ZombieScript := preload("res://scripts/zombie.gd")
const AcidScript := preload("res://scripts/acid.gd")


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
	for row in 2:
		for i in types.size():
			var v := ZombieScript.new()
			v.setup("night" if row == 0 else "horde", 1, types[i])
			v.view = true
			g.mobs.add_child(v)
			v.global_position = Vector3(o) + Vector3((i - 2.5) * 2.2 + 0.5, 1.0, 0.5 + row * 3.0)
			v.rotation.y = PI  # facing the camera
	var acid := AcidScript.new()
	acid.view = true
	g.mobs.add_child(acid)
	acid.global_position = Vector3(o) + Vector3(6.5, 2.2, -1.0)
	var p = G.player
	p.global_position = Vector3(o) + Vector3(0.5, 1.0, -7.5)
	p.velocity = Vector3.ZERO
	p.set_look(PI, -0.12)
	await _wait(2.0)
	var dir := G.arg_value("--shots=")
	if dir != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("lineup.png"))
		print("SHOT lineup")
	get_tree().quit()
