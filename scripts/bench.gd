extends Node
## Server load benchmark:
## `-- --bench [--bench-secs=60] [--zombies=120] [--explorers=7] [--radius=6] [--only=horde,explore]
##   [--net-clients=8] [--out=FILE]`
## Simulates a Blood Moon horde against a walled base and players sprinting into new land, then
## reports how busy the main thread is. Run it on the server machine (the Raspberry Pi) to see
## whether it can host the game. tools/run_bench.sh runs it per physics setup; see docs/pi-benchmark.md.

const WorldScript := preload("res://scripts/world.gd")
const NetServerScript := preload("res://scripts/net/net_server.gd")
const SPRINT := 6.9
const FORT_R := 4

var secs := 60.0
var zombie_target := 120
var explorer_count := 7
var out_path := ""
var only: PackedStringArray = PackedStringArray()
var lines: PackedStringArray = PackedStringArray()
var tick_ms := 1000.0 / 60.0

var recording := false
## Main-thread work per frame in ms: from this node's first callback in the frame (it runs first in
## both physics and idle steps) to a deferred call queued twice, so it runs after the chunk results
## that worker threads queued during the frame.
var busy: PackedFloat32Array = PackedFloat32Array()
var frame_start_us := 0
var explorers: Array = []
var stall_frames := 0
var explorer_frames := 0
var max_backlog := 0
var zombie_min := 0
var zombie_max := 0
var sample_i := 0
var fort_cells: Array[Vector3i] = []
## Block ids the fort replaced, so it can be removed again after a siege.
var fort_old := {}
var explore_ms := -1.0
## --net-clients=N: also build every update a server sends N players (mob and player snapshots,
## 15 a second), so the load includes networking. Clients stand at the base and with the explorers.
var net_clients := 0
var net_bytes := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Run first in every physics and idle step so frame_start_us marks the start of the frame's work.
	process_physics_priority = -100000
	process_priority = -100000
	secs = _num_arg("--bench-secs=", secs)
	zombie_target = int(_num_arg("--zombies=", zombie_target))
	explorer_count = int(_num_arg("--explorers=", explorer_count))
	net_clients = int(_num_arg("--net-clients=", 0))
	out_path = G.arg_value("--out=")
	if out_path == "":
		out_path = "user://bench_results.txt"
	if G.arg_value("--only=") != "":
		only = G.arg_value("--only=").split(",")
	_run()


func _num_arg(prefix: String, def: float) -> float:
	var v := G.arg_value(prefix)
	return def if v == "" else float(v)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _out(s: String) -> void:
	lines.append(s)
	print(s)


# ------------------------------------------------------------ per-frame sampling

func _physics_process(_delta: float) -> void:
	if frame_start_us == 0:
		frame_start_us = Time.get_ticks_usec()
	if recording and net_clients > 0 and Engine.get_physics_frames() % 2 == 0:
		_net_updates()


func _net_updates() -> void:
	var mobs: Array = NetServerScript.mob_list(G.game.mobs)
	var tick := Engine.get_physics_frames()
	for i in net_clients:
		var pos: Vector3 = G.player.global_position
		if i > 0 and not explorers.is_empty():
			pos = explorers[(i - 1) % explorers.size()]["pos"]
		for pkt in NetServerScript.mob_packets(tick, pos, mobs):
			net_bytes += pkt.size()
		var s := Proto.writer(Proto.S_SNAP)
		s.put_u32(tick)
		s.put_u8(net_clients - 1)
		for j in net_clients - 1:
			Proto.put_player_record(s, j + 1, pos, 0.0, 0.0, 0)
		net_bytes += s.data_array.size()


func _process(delta: float) -> void:
	if frame_start_us == 0:
		frame_start_us = Time.get_ticks_usec()
	call_deferred("_frame_end", false)
	var p = G.player
	if p != null:
		p.health = p.max_health
		p.food = 100.0
	if not explorers.is_empty():
		# Explorers sprint outward but, like real players, stop while the chunk under them is not loaded yet.
		var pts := []
		for e in explorers:
			var pos: Vector3 = e["pos"]
			if G.world.is_ready_at(pos):
				pos += e["dir"] * SPRINT * delta
				e["pos"] = pos
			elif recording:
				stall_frames += 1
			if recording:
				explorer_frames += 1
			pts.append(pos)
		G.game.extra_stream_points = pts
	if recording:
		sample_i += 1
		if sample_i % 30 == 0:
			_sample_counts()


func _frame_end(requeued: bool) -> void:
	if not requeued:
		# Re-queue once so this lands behind deferred calls queued during the process step.
		call_deferred("_frame_end", true)
		return
	if recording and frame_start_us != 0:
		busy.append((Time.get_ticks_usec() - frame_start_us) / 1000.0)
	frame_start_us = 0


func _sample_counts() -> void:
	var backlog := 0
	for k in G.world.mesh_set:
		var c = G.world.chunks.get(k)
		if c == null or not c.ready:
			backlog += 1
	max_backlog = maxi(max_backlog, backlog)
	var zc := get_tree().get_nodes_in_group("zombies").size()
	zombie_min = mini(zombie_min, zc)
	zombie_max = maxi(zombie_max, zc)


# ------------------------------------------------------------ run

func _run() -> void:
	var g = G.game
	var w = G.world
	var tps := Engine.physics_ticks_per_second
	tick_ms = 1000.0 / float(tps)
	Engine.max_fps = tps
	while g.state == "loading":
		await _wait(0.25)
	g.start_game()
	g.player.max_health = 1000000.0
	_clear_mobs()
	var r := G.arg_value("--radius=")
	if r != "":
		w.render_radius = int(r)
		w._rebuild_order()
		w._unload_far()
	var t0 := Time.get_ticks_msec()
	while w.load_progress() < 0.999 and Time.get_ticks_msec() - t0 < 60000:
		await _wait(0.25)
	await _wait(1.0)

	_out("=== DEAD BLOCKS BENCH RESULTS ===")
	_out("machine: %s | %s | %d cores | Godot %s" % [OS.get_name(), _cpu_name(), OS.get_processor_count(), Engine.get_version_info()["string"]])
	_out("setup: physics %s at %d ticks/s | %s | chunk radius %d | chunk worker threads %d | %d s per scenario | seed %d" % [
		str(ProjectSettings.get_setting_with_override("physics/3d/physics_engine")), tps, "SERVER MODE" if G.server_mode else "full game",
		w.render_radius, _chunk_threads(), int(secs), g.seed_v])
	_out("build: %s %s | physics on its own thread: %s" % [
		"exported" if OS.has_feature("template") else "editor binary", "release" if not OS.is_debug_build() else "debug",
		"yes" if ProjectSettings.get_setting_with_override("physics/3d/run_on_separate_thread") else "no"])
	_micro()
	var idle_ms := await _scenario("idle", 10.0, 0, 0, 0.0)
	explore_ms = await _scenario("explore", secs, 0, explorer_count, idle_ms)
	await _scenario("horde", secs, zombie_target, 0, idle_ms)
	await _scenario("combined", secs, zombie_target, explorer_count, idle_ms)
	_out("memory: %s | chunks in memory: %d" % [_memory(), w.chunks.size()])
	_out("Load = share of one CPU core the game's main thread used. Under 50% = OK, under 85% = TIGHT, otherwise OVERLOADED.")
	_out("=== END ===")
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
		print("Results saved to ", ProjectSettings.globalize_path(out_path))
	else:
		print("Could not write results to ", out_path)
	get_tree().quit()


## How many chunk tasks can really run at once: world.gd queues up to max_tasks low-priority
## tasks, and Godot runs low-priority tasks on only part of its worker pool.
func _chunk_threads() -> int:
	var pool := int(ProjectSettings.get_setting("threading/worker_pool/max_threads"))
	if pool < 1:
		pool = OS.get_processor_count()
	var ratio := float(ProjectSettings.get_setting("threading/worker_pool/low_priority_thread_ratio"))
	return mini(G.world.max_tasks, clampi(int(pool * ratio), 1, maxi(1, pool - 1)))


## Process memory. Release exports report 0 for Godot's own counters, so read Linux's when we can.
func _memory() -> String:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f != null:
		# /proc files report a length of 0, so read line by line instead of all at once.
		var now := 0.0
		var peak := 0.0
		for _i in 200:
			var line := f.get_line()
			if line == "" and f.eof_reached():
				break
			if line.begins_with("VmRSS:"):
				now = float(line.split(":")[1].strip_edges().split(" ")[0]) / 1024.0
			elif line.begins_with("VmHWM:"):
				peak = float(line.split(":")[1].strip_edges().split(" ")[0]) / 1024.0
		return "%.0f MB now, %.0f MB peak (whole process)" % [now, peak]
	return "%.0f MB now, %.0f MB peak" % [OS.get_static_memory_usage() / 1048576.0, OS.get_static_memory_peak_usage() / 1048576.0]


func _cpu_name() -> String:
	var n := OS.get_processor_name()
	if n == "" and FileAccess.file_exists("/proc/device-tree/model"):
		var raw := FileAccess.get_file_as_bytes("/proc/device-tree/model")
		var end := raw.find(0)
		n = (raw if end < 0 else raw.slice(0, end)).get_string_from_utf8().strip_edges()
	return n if n != "" else "unknown CPU"


## Single-threaded cost of making one chunk, so machines can be compared directly.
func _micro() -> void:
	var g := WorldGen.new(G.game.seed_v)
	var w = G.world
	var n := 24
	var base := 4000
	var datas := {}
	var t0 := Time.get_ticks_usec()
	for i in n + 2:
		for j in 3:
			datas[Vector2i(base + i, base + j)] = g.generate(base + i, base + j)
	var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0 / float((n + 2) * 3)
	var bufs := []
	t0 = Time.get_ticks_usec()
	for i in range(1, n + 1):
		var k := Vector2i(base + i, base + 1)
		var nb := []
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				nb.append(datas[k + Vector2i(dx, dz)])
		bufs.append(w._make_buf(nb))
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0 / float(n)
	# The main-thread part (world.apply_mesh): render mesh, collision shape and lights, built far
	# away from play on throwaway chunks.
	var temp := []
	t0 = Time.get_ticks_usec()
	for i in bufs.size():
		var c = WorldScript.Chunk.new()
		w.apply_mesh(c, Vector2i(base + i, base + 10), bufs[i])
		temp.append(c)
	var upload_ms := (Time.get_ticks_usec() - t0) / 1000.0 / float(n)
	for c in temp:
		w._free_visual(c)
	_out("chunk cost: generate %.1f ms + build mesh %.1f ms (worker threads) + upload %.1f ms (main thread) = %.1f ms per chunk" % [
		gen_ms, build_ms, upload_ms, gen_ms + build_ms + upload_ms])


## Runs one scenario and returns its average main-thread ms per tick (-1 if skipped by --only).
func _scenario(name: String, dur: float, zombies: int, n_expl: int, idle_ms: float) -> float:
	if not only.is_empty() and not only.has(name) and name != "idle":
		return -1.0
	var g = G.game
	var w = G.world
	_clear_mobs()
	explorers.clear()
	g.extra_stream_points = []
	await _wait(2.0)
	# Drop terrain an earlier scenario's explorers loaded, so this one streams fresh land, and put
	# the player back where every scenario starts (zombie hits knock it around).
	w._unload_far(w.render_radius + 1)
	g.player.global_position = g.spawn_pos
	g.player.velocity = Vector3.ZERO
	await _wait(1.0)
	w._unload_far(w.render_radius + 1)
	if zombies > 0:
		_build_fort()
		g.day = 7
		g.time = 20.5
		g.horde_active = true
		g.was_night = true
		await _spawn_horde(zombies)
	else:
		g.day = 2
		g.time = 10.0
		g.horde_active = false
		g.was_night = false
	await _wait(0.5)
	var origin: Vector3 = g.player.global_position
	for i in n_expl:
		var a := TAU * float(i) / float(n_expl)
		explorers.append({"pos": origin, "dir": Vector3(cos(a), 0, sin(a))})

	busy.clear()
	net_bytes = 0
	stall_frames = 0
	explorer_frames = 0
	max_backlog = 0
	sample_i = 0
	var zc := get_tree().get_nodes_in_group("zombies").size()
	zombie_min = zc
	zombie_max = zc
	var gen0: int = w.gen_count
	var mesh0: int = w.mesh_count
	var ph0 := Engine.get_physics_frames()
	var t0 := Time.get_ticks_usec()
	recording = true
	var elapsed := 0.0
	while elapsed < dur:
		await _wait(1.0)
		elapsed = (Time.get_ticks_usec() - t0) / 1000000.0
		if zombies > 0:
			g.time = 20.5  # keep the Blood Moon going however long the run is
			_top_up(zombies)
	recording = false
	var wall := (Time.get_ticks_usec() - t0) / 1000000.0
	var ticks := Engine.get_physics_frames() - ph0
	var ticks_per_s := ticks / wall
	var total_ms := 0.0
	for v in busy:
		total_ms += v
	var load := total_ms / (wall * 1000.0)
	var per_tick := total_ms / maxf(1.0, float(ticks))
	var tps := Engine.physics_ticks_per_second

	var verdict := "OK"
	if load > 0.85 or ticks_per_s < tps * 0.95:
		verdict = "OVERLOADED"
	elif load > 0.5:
		verdict = "TIGHT"
	_out("[%s] %s | load %.0f%% of one core" % [name, verdict, load * 100.0])
	_out("  per tick: avg %.2f ms (budget %.1f ms) | per frame p95 %.2f ms, p99 %.2f, max %.2f | ticks/s %.1f of %d" % [
		per_tick, tick_ms, _pct(busy, 0.95), _pct(busy, 0.99), _pct(busy, 1.0), ticks_per_s, tps])
	if net_clients > 0:
		_out("  network: updates for %d players built every other tick | %.0f kbit/s sent in total, %.0f per player" % [
			net_clients, net_bytes * 8.0 / 1000.0 / wall, net_bytes * 8.0 / 1000.0 / wall / net_clients])
	if zombies > 0:
		var broken := 0
		for c in fort_cells:
			if w.get_blockv(c) == Blocks.AIR:
				broken += 1
		# Per-zombie cost = extra time over the same run without zombies (idle, or explore for combined).
		var base_ms := idle_ms
		if n_expl > 0:
			base_ms = explore_ms
		var each := ""
		if base_ms >= 0.0:
			each = " (about %.3f ms each per tick)" % (maxf(0.0, per_tick - base_ms) / maxf(1.0, float(zombie_max)))
		_out("  zombies alive: %d-%d%s | base wall blocks smashed: %d of %d" % [
			zombie_min, zombie_max, each, broken, fort_cells.size()])
	if n_expl > 0:
		var dist := 0.0
		for e in explorers:
			dist += Vector2(e["pos"].x - origin.x, e["pos"].z - origin.z).length()
		dist /= float(n_expl)
		_out("  explorers: %d sprinting | moved %.1f m/s of %.1f | waiting on chunks %.1f%% of the time" % [
			n_expl, dist / wall, SPRINT, 100.0 * stall_frames / maxf(1.0, explorer_frames)])
		_out("  chunks: %d generated (%.1f/s), %d meshed | most not-yet-ready chunks in range: %d" % [
			w.gen_count - gen0, (w.gen_count - gen0) / wall, w.mesh_count - mesh0, max_backlog])
	explorers.clear()
	g.extra_stream_points = []
	if zombies > 0:
		_clear_mobs()
		_remove_fort()
	return per_tick


func _clear_mobs() -> void:
	for m in get_tree().get_nodes_in_group("mobs"):
		m.queue_free()


## A ring of stone-brick wall around the player for the horde to smash.
func _build_fort() -> void:
	var p: Vector3 = G.player.global_position
	var c := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	fort_cells.clear()
	fort_old.clear()
	for dz in range(-FORT_R, FORT_R + 1):
		for dx in range(-FORT_R, FORT_R + 1):
			if maxi(absi(dx), absi(dz)) != FORT_R:
				continue
			for dy in range(-1, 3):
				var cell := c + Vector3i(dx, dy, dz)
				fort_old[cell] = G.world.get_blockv(cell)
				G.world.set_block(cell, Blocks.STONE_BRICK)
				fort_cells.append(cell)


## Put back whatever the fort replaced, so the next scenario starts from the same ground.
func _remove_fort() -> void:
	for cell in fort_old:
		G.world.set_block(cell, int(fort_old[cell]))
	fort_old.clear()


func _spawn_horde(n: int) -> void:
	var tries := 0
	while get_tree().get_nodes_in_group("zombies").size() < n and tries < 40:
		tries += 1
		_top_up(n)
		await _wait(0.25)


func _top_up(n: int) -> void:
	var have := get_tree().get_nodes_in_group("zombies").size()
	for i in mini(n - have, 30):
		var pos: Vector3 = G.game._find_ground(14.0, 34.0, false)
		if pos != Vector3.INF:
			G.game.spawn_zombie("horde", pos)


func _pct(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[clampi(int(ceil(q * s.size())) - 1, 0, s.size() - 1)]
