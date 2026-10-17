extends Node
## Region-order test: `-- --regiontest --server-mode --seed=4242 [--region-order=reverse]`
## Two groups of zombies besiege two walled stand-in players 300 m apart for a fixed number of
## physics ticks. It prints a hash of where every zombie ended up and of every block hit, in order.
## The hash must be the same whether the Sim processes regions forwards or in reverse
## (tools/test_all.sh runs both and compares) — the rule M3's multi-core regions rely on.

const TICKS := 600
const PER_GROUP := 60
const VirtualPlayer := preload("res://scripts/server/virtual_player.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _run() -> void:
	var g = G.game
	var w = G.world
	var sim = G.sim
	var order := "reverse" if G.arg_value("--region-order=") == "reverse" else "forward"
	sim.reverse_regions = order == "reverse"
	sim.keep_edit_log = true
	while g.state == "loading":
		await _wait(0.25)
	g.start_game()
	g.spawner_enabled = false
	g.time = 12.0
	for m in get_tree().get_nodes_in_group("mobs"):
		m.queue_free()
	var base: Vector3 = g.spawn_pos
	var centers := [base + Vector3(150, 0, 0), base + Vector3(-150, 0, 0)]
	g.extra_stream_points = centers
	var t0 := Time.get_ticks_msec()
	await _wait(1.0)
	while w.load_progress() < 1.0 and Time.get_ticks_msec() - t0 < 180000:
		await _wait(0.25)
	if w.load_progress() < 1.0:
		print("REGIONTEST FAIL world did not finish loading")
		print("REGIONTEST DONE")
		get_tree().quit()
		return
	# From here on, edited chunks are rebuilt on the spot, not on worker threads, so both runs see
	# exactly the same collision at exactly the same tick.
	w.sync_mesh = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var vps := []
	for c in centers:
		var x := floori(c.x)
		var z := floori(c.z)
		var y: int = w.surface_y(x, z)
		var vp := VirtualPlayer.new()
		g.add_child(vp)
		vp.global_position = Vector3(x + 0.5, y + 1.0, z + 0.5)
		sim.add_player(vp)
		vps.append(vp)
		_ring(Vector3i(x, y + 1, z))
	for vp in vps:
		for i in PER_GROUP:
			var a := rng.randf() * TAU
			var d := rng.randf_range(10.0, 22.0)
			var px := floori(vp.global_position.x + cos(a) * d)
			var pz := floori(vp.global_position.z + sin(a) * d)
			var py: int = w.surface_y(px, pz)
			g.spawn_zombie("horde", Vector3(px + 0.5, py + 1.02, pz + 0.5))
	sim.run_until = sim.tick_count + TICKS
	while sim.tick_count < sim.run_until:
		await get_tree().physics_frame
	await get_tree().physics_frame

	var zs := get_tree().get_nodes_in_group("zombies")
	zs.sort_custom(func(a, b): return a.id < b.id)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var parts := PackedStringArray()
	for z in zs:
		var p: Vector3 = z.global_position
		parts.append("%d:%.4f,%.4f,%.4f:%.3f" % [z.id, p.x, p.y, p.z, z.hp])
	for e in sim.edit_log:
		parts.append("e%d,%d,%d:%.4f:%d" % e)
	var hits := 0
	for vp in vps:
		hits += vp.hits
		parts.append("h%d" % vp.hits)
	ctx.update("\n".join(parts).to_utf8_buffer())
	var broken := 0
	for e in sim.edit_log:
		if w.get_block(e[0], e[1], e[2]) == Blocks.AIR:
			broken += 1
	print("REGIONTEST order=%s ticks=%d zombies=%d regions=%d edits=%d blocks_now_air=%d hits=%d hash=%s" % [
		order, TICKS, zs.size(), sim.regions.size(), sim.edit_log.size(), broken, hits, ctx.finish().hex_encode()])
	print("REGIONTEST DONE")
	get_tree().quit()


## A ring of plank wall around a stand-in player, so the zombies have something to break.
func _ring(c: Vector3i) -> void:
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			if maxi(absi(dx), absi(dz)) != 4:
				continue
			for dy in range(-1, 3):
				G.world.set_block(c + Vector3i(dx, dy, dz), Blocks.PLANKS)
