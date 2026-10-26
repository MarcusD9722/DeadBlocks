extends Node3D
## Game flow: world setup, day/night cycle, blood moon hordes, spawning, menus.

## Real minutes per in-game day (DESIGN.md: 30). Tests can override it with --day-minutes=N.
var day_minutes := 30.0

var state := "loading"
var day := 1
var time := 7.0
var seed_v := 0
## Which terrain generator this game's world uses (WorldGen versions, M4.7).
var gen_version := WorldGen.VERSION
var kills := 0
var horde_active := false
## Client: the server's clock is stopped (nobody playing, or our solo game is paused).
var clock_stopped := false
var was_night := false
var warned := {}
var spawn_timer := 2.0
var animal_timer := 1.0
var cave_timer := 3.0
var spawn_pos := Vector3.ZERO
## Positions the world keeps loaded besides the local player (benchmark explorers now, remote players later).
var extra_stream_points: Array = []

var gfx: Node
var world: Node3D
var player: CharacterBody3D
var mobs: Node3D
var hud: CanvasLayer

const ZombieScript := preload("res://scripts/zombie.gd")
const AnimalScript := preload("res://scripts/animal.gd")
const AcidScript := preload("res://scripts/acid.gd")
const ProjectileScript := preload("res://scripts/projectile.gd")
const RemotePlayerScript := preload("res://scripts/net/remote_player.gd")
const WorldScript := preload("res://scripts/world.gd")

## Client mode: other players' figures by net id.
var remote_players := {}
## Client mode: pictures of the mobs the server runs, by net id.
var mob_views := {}
## Pictures of the spears and arrows lying in the world (M4.3): ground id -> node.
var ground_views := {}
## The world map's picture (M4.4, client only).
var map_data: MapData = null
## Mob ids clients know mobs by (1-65535, wrapping).
var _next_mob_id := 1


func _ready() -> void:
	if G.has_arg("--version") or G.arg_value("--finish-update=") != "":
		state = "quitting"
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	seed_v = randi() % 1000000
	var sv := G.arg_value("--seed=")
	if sv != "":
		seed_v = int(sv)
	if G.arg_value("--day-minutes=") != "":
		day_minutes = maxf(0.1, float(G.arg_value("--day-minutes=")))
	# The terrain generator: a server's world says which (save.gd); a game that joins hears it from
	# the server; the title screen's world and the tests take the newest, or --worldgen=N.
	if G.arg_value("--worldgen=") != "":
		gen_version = clampi(int(G.arg_value("--worldgen=")), 1, WorldGen.VERSION)
	if G.mode == "client":
		seed_v = int(G.session["seed"])
		day_minutes = float(G.session["day_minutes"])
		gen_version = int(G.session.get("worldgen", WorldGen.VERSION))
	G.game = self
	if G.has_arg("--worldgen-hash") or G.has_arg("--savetest") or G.has_arg("--meshtest"):
		if G.has_arg("--savetest"):
			preload("res://scripts/tests/savetest.gd").run()
		elif G.has_arg("--meshtest"):
			preload("res://scripts/tests/meshtest.gd").run(seed_v, gen_version)
		else:
			preload("res://scripts/tests/worldgen_hash.gd").run(seed_v)
		state = "quitting"
		set_process(false)
		set_process_unhandled_input(false)
		get_tree().quit()
		return
	_setup_input()
	if G.mode == "server":
		_ready_server()
		return
	if G.wants_autojoin():
		# Joining from the command line: wait for the server's welcome before building any world.
		state = "connecting"
		hud = preload("res://scripts/hud.gd").new()
		add_child(hud)
		G.hud = hud
		hud.set_title_status("Connecting...")
		G.autojoin()
		return
	G.tex = Tex.new()
	if DisplayServer.get_name() != "headless":
		ToolModels.render_icons(G)  # the tools' icons, drawn from their 3D models (once per run)
	var sfx := preload("res://scripts/sfx.gd").new()
	add_child(sfx)
	G.sfx = sfx
	_setup_env()

	world = preload("res://scripts/world.gd").new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	G.world = world
	world.setup(seed_v, G.tex, gen_version)

	mobs = Node3D.new()
	mobs.name = "Mobs"
	mobs.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(mobs)

	var sim := preload("res://scripts/server/sim.gd").new()
	sim.name = "Sim"
	sim.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(sim)

	spawn_pos = _find_spawn()
	if G.mode == "client":
		spawn_pos = G.session["pos"]
		day = int(G.session["day"])
		time = float(G.session["time"])
		horde_active = bool(G.session["horde"])
		was_night = is_night()
	player = preload("res://scripts/player.gd").new()
	player.name = "Player"
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	G.player = player
	sim.add_player(player)
	player.global_position = spawn_pos
	player.spawn_point = spawn_pos
	player.set_look(randf() * TAU, -0.1)
	if G.mode == "client":
		player.spawn_point = G.session["spawn"]
		player.set_look(float(G.session["yaw"]), -0.1)

	hud = preload("res://scripts/hud.gd").new()
	add_child(hud)
	G.hud = hud
	player.inv.changed.connect(hud.refresh_inventory)
	_update_sky()
	if G.mode == "client":
		hud.hide_title()
		hud.show_loading_overlay(true)
		G.net.attach(world)
		G.net.ground_changed.connect(_sync_ground)
		_sync_ground()
		world.track_map = true
		map_data = MapData.new()
		map_data.name = "MapData"
		add_child(map_data)

	if G.has_arg("--bench"):
		var b := preload("res://scripts/bench.gd").new()
		add_child(b)
	elif G.has_arg("--regiontest"):
		var rt := preload("res://scripts/tests/regiontest.gd").new()
		add_child(rt)
	elif G.has_arg("--typetest"):
		var tt := preload("res://scripts/tests/typetest.gd").new()
		add_child(tt)
	elif G.has_arg("--lineup"):
		add_child(preload("res://scripts/tests/lineup.gd").new())
	elif G.has_arg("--scenery"):
		add_child(preload("res://scripts/tests/scenery.gd").new())


func _setup_input() -> void:
	Controls.setup()


## Dedicated server: the world, the Sim and networking, but no window, player, HUD or sky.
## Dedicated server: the saved world (or a new one), the Sim and networking, but no window,
## player, HUD or sky. --data=DIR (default user://server) and --world=NAME (default main) pick
## the save folder; --new-world starts over (the old world goes to backups/).
func _ready_server() -> void:
	var saver := preload("res://scripts/server/save.gd").new()
	saver.name = "Save"
	add_child(saver)
	var data_dir := G.arg_value("--data=")
	var wname := G.arg_value("--world=")
	if G.arg_value("--autosave=") != "":
		saver.autosave_s = maxf(1.0, float(G.arg_value("--autosave=")))
	if not saver.open(data_dir if data_dir != "" else "user://server", wname if wname != "" else "main", seed_v, G.has_arg("--new-world")):
		printerr("SERVER cannot start: " + saver.error)
		state = "quitting"
		get_tree().quit(1)
		return
	seed_v = saver.seed_v
	gen_version = saver.worldgen
	day = saver.day
	time = saver.time
	was_night = is_night()
	world = preload("res://scripts/world.gd").new()
	world.name = "World"
	add_child(world)
	G.world = world
	world.setup(seed_v, null, gen_version)
	var saved_chunks: Array = saver.load_chunks()
	for c in saved_chunks:
		world.preload_chunk(c[0], c[1], c[2])
	mobs = Node3D.new()
	mobs.name = "Mobs"
	add_child(mobs)
	var sim := preload("res://scripts/server/sim.gd").new()
	sim.name = "Sim"
	add_child(sim)
	spawn_pos = _find_spawn()
	var ns := preload("res://scripts/net/net_server.gd").new()
	ns.name = "NetServer"
	ns.saver = saver
	ns.accounts = saver.load_players()
	add_child(ns)
	G.net_server = ns
	ns.load_backpacks(saver.backpacks)
	ns.load_boxes(saver.boxes)
	ns.load_ground(saver.ground)
	ns.load_beds()
	ns.social.load_json(saver.allies, saver.tribes)
	state = "server"
	print("SERVER world \"%s\" in %s: %s, seed %d, day %d %02d:%02d, %d edited chunks, %d players" % [
		saver.world_name, saver.world_dir, "new" if saver.is_new else "loaded", seed_v, day, int(time),
		int((time - int(time)) * 60.0), saved_chunks.size(), ns.accounts.size()])
	if not saver.is_new:
		saver.backup("server start")
	if not ns.start():
		saver.release_lock()
		get_tree().quit(1)


func _setup_env() -> void:
	gfx = preload("res://scripts/gfx.gd").new()
	gfx.name = "Gfx"
	add_child(gfx)
	G.gfx = gfx


func _find_spawn() -> Vector3:
	var g := WorldGen.new(seed_v, gen_version)
	for r in range(0, 400, 3):
		for k in 16:
			var a := k * TAU / 16.0
			var x := int(round(cos(a) * r))
			var z := int(round(sin(a) * r))
			if g.spawn_ok(x, z):
				return Vector3(x + 0.5, g.height_at(x, z) + 1.02, z + 0.5)
	return Vector3(0.5, g.height_at(0, 0) + 2, 0.5)


# ------------------------------------------------------------ main loop

func _process(delta: float) -> void:
	match state:
		"server":
			world.update_centers(G.net_server.player_positions())
			# Time, spawning and the mobs stop while nobody is online (or a solo game is paused).
			if not G.net_server.world_paused:
				_tick_time(delta)
				if not G.has_arg("--no-spawns"):
					_server_spawner(delta)
			return
		"connecting", "quitting":
			return
		"loading":
			world.update_centers(_stream_points())
			var p: float = world.load_progress()
			hud.set_loading(p)
			if p >= 0.999 or (p > 0.55 and world.is_ready_at(spawn_pos) and _elapsed() > 25.0):
				if G.mode == "client":
					hud.show_loading_overlay(false)
					state = "title"
					start_game()
					G.net.send_ready()
				else:
					state = "title"
					hud.show_ready()
		"title":
			world.update_centers(_stream_points())
		"playing", "menu", "chat":
			world.update_centers(_stream_points())
			_tick_time(delta)
		"paused", "reconnecting":
			# Online, the pause menu doesn't stop the world.
			world.update_centers(_stream_points())
			if G.mode == "client":
				_tick_time(delta)
		"dead":
			world.update_centers(_stream_points())
			if G.mode == "client":
				_tick_time(delta)
	if G.mode == "client":
		_sync_remote_players()
		_sync_mob_views(delta)
	_update_sky(delta)


## Keep one picture per mob the server tells us about, placed where its snapshots say.
func _sync_mob_views(delta: float) -> void:
	for id in G.net.mobs:
		var v = mob_views.get(id)
		var kind: int = G.net.mobs[id]["kind"]
		if v != null and is_instance_valid(v) and v.net_kind() != kind:
			# It changed kind (horde zombies calm down at dawn): a new picture for the new kind.
			v.queue_free()
			v = null
		var smp: Array = G.net.mobs[id]["samples"]
		var blood: bool = not smp.is_empty() and (int(smp.back()[4]) & Proto.MF_BLOOD) != 0
		if v != null and is_instance_valid(v) and v is ZombieScript and v.type != "walker" and v.blood != blood:
			v.queue_free()  # a Blood Moon runner (say) calming down at dawn
			v = null
		if v == null or not is_instance_valid(v):
			if kind == Proto.MOB_BOAR:
				v = AnimalScript.new()
			elif kind == Proto.MOB_ACID:
				v = AcidScript.new()
			elif kind == Proto.MOB_PROJ:
				v = ProjectileScript.new()
				var f: int = int(smp.back()[4]) if not smp.is_empty() else 0
				v.item = Items.PROJECTILES[clampi(f & 63, 0, Items.PROJECTILES.size() - 1)]
			else:
				v = ZombieScript.new()
				if Proto.KIND_TYPES.has(kind):
					v.setup("horde" if blood else "night", day, Proto.KIND_TYPES[kind])
				else:
					v.setup(["day", "night", "horde"][kind], day)
			v.view = true
			v.net_id = id
			mobs.add_child(v)
			mob_views[id] = v
		var s: Dictionary = G.net.mob_sample(id)
		if not s.is_empty():
			v.view_update(s["pos"], s["yaw"], s["flags"], delta)
	for id in mob_views.keys():
		if not G.net.mobs.has(id):
			var gone = mob_views[id]
			if is_instance_valid(gone):
				if gone.net_kind() == Proto.MOB_ACID:
					G.sfx.play_at("splash", gone.global_position, -4.0)
				elif gone.net_kind() == Proto.MOB_PROJ and gone.visible:
					G.sfx.play_at("arrow", gone.global_position, -3.0)  # (your own shot sounds by itself)
				if gone.die_t < 0.0:
					gone.queue_free()
				# (a dead one finishes falling over and sinking away by itself)
			mob_views.erase(id)


## Show what lies in the world as G.net.ground says (spears and arrows that stuck, M4.3).
func _sync_ground() -> void:
	if G.net == null or mobs == null:
		return
	for id in ground_views.keys():
		if not G.net.ground.has(id):
			if is_instance_valid(ground_views[id]):
				ground_views[id].queue_free()
			ground_views.erase(id)
	for id in G.net.ground:
		if ground_views.has(id):
			continue
		var g: Dictionary = G.net.ground[id]
		var v := ToolModels.make_flying(int(g["item"]))
		if v == null:
			continue
		add_child(v)
		var yaw: float = g["yaw"]
		var pitch: float = g["pitch"]
		var d := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
		v.global_position = g["pos"]
		v.basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT)
		ground_views[id] = v


# ------------------------------------------------------------ standing on the drawn ground

## The ground is drawn rounded, but creatures stand on whole blocks (on the server too). So that
## they stand on what the player sees, each picture's model is lowered or raised to the drawn
## ground under its feet (world.VISUAL_LAYER), measured a quarter of the creatures per tick.
var _snap_i := 0


func _physics_process(_delta: float) -> void:
	if G.mode != "client" or world == null or not world.render:
		return
	_snap_i = (_snap_i + 1) % 4
	var space := get_world_3d().direct_space_state
	var i := 0
	for v in mob_views.values():
		i += 1
		if i % 4 == _snap_i and is_instance_valid(v) and v.die_t < 0.0 and v.net_kind() != Proto.MOB_ACID and v.net_kind() != Proto.MOB_PROJ:
			v.ground_target = _ground_offset(space, v, v.half * 0.5)
	for rp in remote_players.values():
		i += 1
		if i % 4 == _snap_i and is_instance_valid(rp) and rp.visible:
			rp.ground_target = _ground_offset(space, rp, 0.15)


## How far the drawn ground under it is above (+) or below (-) its feet: the highest of five
## points under its footprint. 0 while it is jumping or falling.
func _ground_offset(space: PhysicsDirectSpaceState3D, who, r: float) -> float:
	var pos: Vector3 = who.global_position
	var moved: float = absf(pos.y - who.snap_y)
	who.snap_y = pos.y
	if moved > 0.08:
		return 0.0
	var best := -INF
	for o in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		var from := pos + Vector3(o.x, 0.7, o.y)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -1.6, 0), WorldScript.VISUAL_LAYER)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			best = maxf(best, hit["position"].y)
	if best == -INF:
		return 0.0
	return clampf(best - pos.y, -0.75, 0.15)


## Keep one RemotePlayer figure per other player the server has told us about.
func _sync_remote_players() -> void:
	for id in G.net.others:
		if not remote_players.has(id):
			var rp := RemotePlayerScript.new()
			rp.net_id = id
			rp.name = "Remote%d" % id
			add_child(rp)
			remote_players[id] = rp
	for id in remote_players.keys():
		if not G.net.others.has(id):
			remote_players[id].queue_free()
			remote_players.erase(id)


var _t0 := Time.get_ticks_msec()


func _stream_points() -> Array:
	var pts: Array = [player.global_position]
	pts.append_array(extra_stream_points)
	return pts


func _elapsed() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0


func _input(event: InputEvent) -> void:
	Controls.note(event)


func _unhandled_input(event: InputEvent) -> void:
	if state == "chat":
		return
	# Esc is both "pause" and "ui_cancel"; the controller's Start pauses and B goes back.
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if state == "reconnecting":
			G.end_client_session("You left the server.")
		elif state == "playing":
			if event.is_action_pressed("pause"):
				pause()
		elif state == "menu":
			close_inventory()
		elif state == "paused":
			resume()
	elif event.is_action_pressed("chat"):
		if state == "playing" and G.mode == "client":
			open_chat()
	elif event.is_action_pressed("inventory"):
		if state == "playing":
			open_inventory()
		elif state == "menu" and hud.has_tabs() and hud.tab != "inventory":
			hud.show_tab("inventory")
		elif state == "menu":
			close_inventory()
	elif event.is_action_pressed("map"):
		# M4.4: the world map is a tab of the character screen.
		if state == "playing" and G.mode == "client":
			open_inventory()
			hud.show_tab("map")
		elif state == "menu" and hud.has_tabs() and hud.tab != "map":
			hud.show_tab("map")
		elif state == "menu":
			close_inventory()
	elif state == "menu" and event is InputEventJoypadButton and hud.has_tabs() and \
			(event.is_action_pressed("hotbar_prev") or event.is_action_pressed("hotbar_next")):
		hud.next_tab(-1 if event.is_action_pressed("hotbar_prev") else 1)  # LB / RB
	elif event.is_action_pressed("interact"):
		if state == "playing":
			player.interact()
		elif state == "menu":
			close_inventory()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F11:
				if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
				else:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			KEY_F6:
				if state == "playing" and G.mode == "client":
					G.net.send_chat("/dusk")  # admins only (in Play solo you are one)
			KEY_F7:
				if state == "playing" and G.mode == "client":
					G.net.send_chat("/bloodmoon")
	elif event is InputEventMouseButton and event.pressed:
		if state == "playing" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "playing" and (G.mode != "client" or G.solo):
		pause()


# ------------------------------------------------------------ states

func start_game() -> void:
	if state != "title":
		return
	state = "playing"
	hud.hide_title()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if G.solo and day == 1 and time < 7.5:
		hud.msg("Day 1. Gather wood, craft tools, and build shelter before 20:00.", Color(1, 1, 0.8))
		hud.msg("Hold left click on a tree to collect logs.", Color(0.7, 1, 0.7))
	elif G.solo:
		hud.msg("Welcome back. Day %d, %02d:%02d." % [day, int(time), int((time - int(time)) * 60.0)], Color(1, 1, 0.8))
	elif G.mode == "client":
		hud.msg("Joined %s. Press T to chat, Esc for the player list." % G.net.host, Color(0.8, 1, 0.8))


func pause() -> void:
	state = "paused"
	# Online the world keeps running for everyone, so only the menu opens; Play solo's server
	# stops its world.
	if G.solo:
		G.net.send_pause(true)
	elif G.mode != "client":
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_pause(true)


## The pause menu's "Die and Respawn": for being stuck in a hole or under the world. Until M2
## dying costs nothing; the server does the dying (/kill), the death screen follows.
func kill_self() -> void:
	if G.mode != "client":
		return
	resume()
	G.net.send_chat("/kill")


func resume() -> void:
	state = "playing"
	get_tree().paused = false
	if G.solo:
		G.net.send_pause(false)
	hud.show_pause(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Online: the connection dropped and NetClient is logging back in. The world stays on screen,
## but the player can't act until the server is back.
func on_connection_lost() -> void:
	match state:
		"chat":
			hud._close_chat()
		"menu":
			hud.show_inventory(false)
		"paused":
			hud.show_pause(false)
	if state in ["playing", "menu", "paused", "chat"]:
		state = "reconnecting"
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func on_reconnected(w: Dictionary) -> void:
	day = int(w["day"])
	time = float(w["time"])
	horde_active = bool(w["horde"])
	was_night = is_night()
	# The server puts us back where it last saw us; only snap there if we drifted (falling).
	var pos: Vector3 = w["pos"]
	if player.global_position.distance_to(pos) > 3.0:
		player.global_position = pos
		player.velocity = Vector3.ZERO
	if state == "reconnecting":
		state = "playing"
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.msg("Reconnected.", Color(0.7, 1, 0.7))
	G.net.send_ready()


func open_chat() -> void:
	state = "chat"
	hud.open_chat()


func close_chat() -> void:
	if state == "chat":
		state = "playing"


## The inventory screen: with the hand recipes (I), or with a station's own recipes (E on it;
## station is its name in crafting.gd).
func open_inventory(station := "") -> void:
	if state != "playing":
		return
	state = "menu"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_inventory(true, station)


## E on a storage box or bag (M4.2): the box screen; the server sends what's in it.
func open_box(p: Vector3i) -> void:
	if state != "playing":
		return
	state = "menu"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_box(true, p)
	G.net.request_open(p)


func close_inventory() -> void:
	if hud.box_at != Vector3i.MIN:
		G.net.request_close_box()
	state = "playing"
	hud.show_inventory(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func on_player_died() -> void:
	if state == "menu":
		hud.show_inventory(false)
	elif state == "chat":
		hud._close_chat()
	elif state == "paused":
		hud.show_pause(false)
	state = "dead"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_death(true)


## at_bed: wake up at our bed (if we have one; otherwise the server picks a random spot);
## whose: at that tribe member's bed instead (M4.4).
func respawn(at_bed := true, whose := "") -> void:
	if G.mode == "client":
		# The server answers with S_CORRECT (where) and S_STATS (alive).
		G.net.request_respawn(2 if whose != "" else (0 if at_bed else 1), whose)
		return
	player.respawn()
	on_respawned()


func on_respawned() -> void:
	hud.show_death(false)
	state = "playing"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Server: stop or restart every mob (and the zombie Sim) while nobody is online.
func set_mobs_paused(paused: bool) -> void:
	mobs.process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT
	G.sim.set_physics_process(not paused)


func mob_by_net_id(id: int) -> Node:
	for m in mobs.get_children():
		if m is Mob and (m.net_id & 0xffff) == id:
			return m
	return null


func _new_mob_id() -> int:
	var id := _next_mob_id
	_next_mob_id = _next_mob_id % 65535 + 1
	return id


func nearby_stations() -> Array:
	return world.stations_near(player.global_position + Vector3(0, 1, 0), Crafting.STATION_RADIUS)


func on_crafted(id: int) -> void:
	if id == Blocks.WORKBENCH and not warned.has("bench_made"):
		warned["bench_made"] = true
		hud.msg("Select the Workbench in your hotbar and place it (%s)." % Controls.key_name(Controls.key_of("use")), Color(0.7, 1, 0.7))


# ------------------------------------------------------------ time

func is_night() -> bool:
	return time >= 20.0 or time < 6.0


func is_horde_night() -> bool:
	return (time >= 20.0 and day % 7 == 0) or (time < 6.0 and day > 1 and (day - 1) % 7 == 0)


func days_until_horde() -> int:
	return (7 - day % 7) % 7


func horde_text() -> String:
	if horde_active:
		return "BLOOD MOON — survive until dawn"
	var d := days_until_horde()
	if d == 0:
		return "Blood Moon TONIGHT at 20:00"
	if d == 1:
		return "Blood Moon tomorrow night (Day %d)" % (day + 1)
	return "Next Blood Moon: Day %d (%d days)" % [day + d, d]


func _tick_time(delta: float) -> void:
	if G.mode == "client" and clock_stopped:
		return
	var prev := time
	time += delta * 24.0 / (day_minutes * 60.0)
	if time >= 24.0:
		time -= 24.0
		day += 1
	if prev < 18.0 and time >= 18.0:
		if day % 7 == 0:
			_say("The sky is turning red. The horde comes at 20:00 — fortify NOW.", Color(1, 0.4, 0.3))
			_sound("siren", -10.0)
		elif day == 1:
			_say("Sunset soon. Wall yourself in — zombies smash weak blocks.", Color(1, 0.85, 0.6))
	var night := is_night()
	if night and not was_night:
		_on_dusk()
	elif not night and was_night:
		_on_dawn()
	was_night = night


func _on_dusk() -> void:
	if is_horde_night():
		horde_active = true
		_say("BLOOD MOON — THE HORDE IS COMING", Color(1, 0.2, 0.15))
		_sound("siren", -2.0)
	else:
		_say("Night falls. The dead grow restless.", Color(0.75, 0.8, 1.0))


func _on_dawn() -> void:
	if horde_active:
		_say("Dawn. You survived the Blood Moon!", Color(1, 0.9, 0.5))
	else:
		_say("Dawn breaks. Day %d." % day, Color(1, 0.95, 0.8))
	horde_active = false
	# Zombies far from everyone go; the rest calm down into day zombies (no more red eyes, and
	# they only come for players who get close).
	for z in get_tree().get_nodes_in_group("zombies"):
		var near := false
		for p in G.sim.players:
			if is_instance_valid(p) and z.global_position.distance_to(p.global_position) <= 28.0:
				near = true
		if not near:
			z.queue_free()
		elif z.kind != "day" and not z.cave:
			z.become_day()  # (the cave's own stay as they are: it is always night down there)


## HUD message and sound, skipped on the dedicated server (no HUD, no audio).
func _say(text: String, col := Color(1, 1, 1)) -> void:
	if hud != null:
		hud.msg(text, col)


func _sound(sound: String, vol := 0.0) -> void:
	if G.sfx != null and G.mode != "server":
		G.sfx.play(sound, vol)


func skip_time(blood: bool) -> void:
	if blood:
		while day % 7 != 0:
			day += 1
		time = 19.95
		horde_active = false
		was_night = false
		_say("[Test] Jumped to Day %d, 19:57. Blood Moon in a few seconds." % day, Color(0.8, 0.8, 1))
	elif is_night():
		if time >= 20.0:
			day += 1
		time = 5.95
		_say("[Test] Skipped to 05:57 — dawn is near.", Color(0.8, 0.8, 1))
	else:
		time = 19.95
		_say("[Test] Skipped to 19:57 — night is near.", Color(0.8, 0.8, 1))
	_update_sky()


func _update_sky(delta := 0.0) -> void:
	if gfx == null:
		return
	gfx.update_sky(time, horde_active or (day % 7 == 0 and time >= 18.0), delta)


# ------------------------------------------------------------ spawning

## Server: the spawning rules around every player who is online and alive, with at most
## MAX_ZOMBIES zombies in the whole world.
const MAX_ZOMBIES := 120


func _server_spawner(delta: float) -> void:
	var ps: Array = G.net_server.alive_positions()
	spawn_timer -= delta
	animal_timer -= delta
	var zs := get_tree().get_nodes_in_group("zombies")
	var animals := get_tree().get_nodes_in_group("animals")
	for z in zs:
		if not _near_any(z.global_position, ps, 72.0):
			z.queue_free()
	for a in animals:
		if not _near_any(a.global_position, ps, 80.0):
			a.queue_free()
	if ps.is_empty():
		return
	var night := is_night()
	var cap := 2
	var interval := 9.0
	if night:
		cap = mini(5 + day, 16)
		interval = 3.0
	if horde_active:
		if spawn_timer <= 0.0:
			spawn_timer = 1.0
			_horde_spawner(ps, zs)
	elif spawn_timer <= 0.0:
		spawn_timer = interval
		var total := zs.size()
		for p in ps:
			if total >= MAX_ZOMBIES:
				break
			if _count_near(zs, p, 72.0) < cap:
				var mood := "night" if night else "day"
				if spawn_zombie(mood, Vector3.INF, p, zombie_type(mood, day, randf())) != null:
					total += 1
	# M4.7: zombies in the dark caves, day and night, more of them the deeper you are.
	cave_timer -= delta
	if cave_timer <= 0.0:
		cave_timer = 4.0
		for p in ps:
			_cave_spawner(p, zs)
	if animal_timer <= 0.0:
		animal_timer = 6.0
		if not night:
			for p in ps:
				if _count_near(animals, p, 80.0) < 6:
					_spawn_animal(p)


## The fair Blood Moon (docs/M3-plan.md, built in M4.7): 120 zombies at most, shared out evenly
## between the players alive; players within 40 m of each other are one group and share one
## horde (their shares add up). The first Blood Moon (day 7) brings 40% of it, day 14 70%,
## day 21 on all of it. Each second, every group short of its number gets up to two more, spawned
## 20-35 m out from the group's edge.
func _horde_spawner(ps: Array, zs: Array) -> void:
	var total := zs.size()
	for g in horde_plan(ps, day):
		var c: Vector3 = g["center"]
		var r: float = g["radius"]
		var want: int = g["want"]
		var have := 0
		for z in zs:
			if is_instance_valid(z) and z.kind == "horde" and Vector3(z.global_position.x - c.x, 0.0, z.global_position.z - c.z).length() <= r + 45.0:
				have += 1
		for k in mini(2, want - have):
			if total >= MAX_ZOMBIES:
				return
			var at := _find_ground(r + 20.0, r + 35.0, false, c)
			if at != Vector3.INF and spawn_zombie("horde", at, Vector3.INF, zombie_type("horde", day, randf())) != null:
				total += 1


## The Blood Moon's groups and how many zombies each should have on `d`: [{"center", "radius"
## (the group's edge from its center), "want"}, ...] for the players alive at ps.
static func horde_plan(ps: Array, d: int) -> Array:
	var out := []
	if ps.is_empty():
		return out
	var scale := 0.4 if d < 14 else (0.7 if d < 21 else 1.0)
	var share := float(MAX_ZOMBIES) / ps.size() * scale
	for g in player_groups(ps, 40.0):
		var c := Vector3.ZERO
		for p in g:
			c += p
		c /= g.size()
		var r := 0.0
		for p in g:
			r = maxf(r, Vector3(p.x - c.x, 0.0, p.z - c.z).length())
		out.append({"center": c, "radius": r, "want": roundi(share * g.size())})
	return out


## Players within `link` metres of each other (through others too) as groups: [[pos, ...], ...].
static func player_groups(ps: Array, link: float) -> Array:
	var group := PackedInt32Array()
	group.resize(ps.size())
	for i in ps.size():
		group[i] = i
	var changed := true
	while changed:
		changed = false
		for i in ps.size():
			for j in ps.size():
				if group[j] < group[i] and (ps[i] as Vector3).distance_to(ps[j]) <= link:
					group[i] = group[j]
					changed = true
	var out := {}
	for i in ps.size():
		if not out.has(group[i]):
			out[group[i]] = []
		out[group[i]].append(ps[i])
	return out.values()


## A player down in a cave (well under the ground above them) gets zombies out of the dark:
## 2 at once near the surface, up to 7 deep down, spawned 12-28 m away in the cave itself.
func _cave_spawner(p: Vector3, zs: Array) -> void:
	var pc := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	var under: int = world.surface_y(pc.x, pc.z) - pc.y
	if under < 8 or zs.size() >= MAX_ZOMBIES:
		return
	var cap := clampi(2 + int(under / 12.0) + (1 if p.y < 30.0 else 0), 2, 7)
	if _count_near(zs, p, 32.0) >= cap:
		return
	var spot := cave_spot(p)
	if spot != Vector3.INF:
		var z := spawn_zombie("night", spot, Vector3.INF, zombie_type("night", day, randf()))
		if z != null:
			z.cave = true


## A dark spot in a cave 12-28 m from p (level with it, give or take 10 blocks): air for two
## blocks over solid ground, with the ground's surface well above. INF if none is found.
func cave_spot(p: Vector3) -> Vector3:
	for attempt in 12:
		var a := randf() * TAU
		var d := randf_range(12.0, 28.0)
		var x := floori(p.x + cos(a) * d)
		var z := floori(p.z + sin(a) * d)
		var top: int = world.surface_y(x, z)
		var y0 := clampi(floori(p.y) - 10, 2, WorldGen.H - 3)
		var y1 := clampi(floori(p.y) + 10, 2, WorldGen.H - 3)
		for y in range(y0, y1 + 1):
			if y + 6 > top:
				break
			var at := Vector3(x + 0.5, y + 0.02, z + 0.5)
			if not world.is_ready_at(at):
				break
			if Blocks.is_solid(world.get_block(x, y - 1, z)) and world.get_block(x, y, z) == Blocks.AIR and world.get_block(x, y + 1, z) == Blocks.AIR:
				return at
	return Vector3.INF


static func _near_any(pos: Vector3, ps: Array, dist: float) -> bool:
	for p in ps:
		if pos.distance_to(p) <= dist:
			return true
	return false


static func _count_near(nodes: Array, p: Vector3, dist: float) -> int:
	var n := 0
	for m in nodes:
		if is_instance_valid(m) and m.global_position.distance_to(p) <= dist:
			n += 1
	return n


## Which type a new zombie is (M3, docs/M3-plan.md): day zombies are walkers; at night and in
## the Blood Moon the tougher types mix in as the days go by. `roll` is a random number in 0..1.
static func zombie_type(mood: String, d: int, roll: float) -> String:
	if mood == "day":
		return "walker"
	var odds: Array
	if mood == "horde":
		odds = [["runner", 0.25], ["crawler", 0.15], ["brute", 0.10], ["screamer", 0.08], ["spitter", 0.10 if d >= 14 else 0.0]]
	else:
		odds = [["runner", minf(0.20 + 0.02 * (d - 2), 0.35) if d >= 2 else 0.0], ["crawler", 0.15 if d >= 3 else 0.0],
			["screamer", 0.05 if d >= 5 else 0.0], ["brute", 0.05 if d >= 10 else 0.0], ["spitter", 0.05 if d >= 12 else 0.0]]
	var acc := 0.0
	for o in odds:
		acc += o[1]
		if roll < acc:
			return o[0]
	return "walker"


## A natural tree comes down (M4.6): ours as we fell it, someone else's from S_TREE. Shown once
## per tree (we already show the one we felled when the server tells everyone).
var _falling := {}

func tree_falls(root: Vector3i, yaw: float) -> void:
	if G.server_mode or G.world == null:
		return
	var now := Time.get_ticks_msec()
	if now - int(_falling.get(root, -100000)) < 8000:
		return
	_falling[root] = now
	if G.player != null and G.player.global_position.distance_to(Vector3(root)) > 120.0:
		return
	var t := Trees.at(G.world.gen(), root.x, root.z)
	if t.is_empty() or t["root"] != root:
		return
	var f := Trees.Falling.new()
	G.world.add_child(f)
	f.setup(t, yaw, G.sfx)


## Admins' /spawn: a mob 8-14 m from a player. A zombie type comes in tonight's mood.
func spawn_near(what: String, pos: Vector3) -> Node:
	if what == "boar":
		return _spawn_animal(pos, 8.0, 14.0)
	var p := _find_ground(8.0, 14.0, false, pos)
	if p == Vector3.INF:
		return null
	if ZombieScript.TYPES.has(what):
		var t := spawn_zombie("horde" if horde_active else "night", p, Vector3.INF, what)
		if t != null:
			t.hunting = true
		return t
	var z := spawn_zombie("day" if what == "zombie" else what, p)
	if z != null:
		z.hunting = true  # an admin's /spawn comes straight for them
	return z


func _find_ground(min_d: float, max_d: float, need_grass: bool, center := Vector3.INF) -> Vector3:
	if center == Vector3.INF:
		center = player.global_position
	for attempt in 8:
		var a := randf() * TAU
		var d := randf_range(min_d, max_d)
		var x := floori(center.x + cos(a) * d)
		var z := floori(center.z + sin(a) * d)
		var y: int = world.surface_y(x, z)
		if y < 0:
			continue
		var p := Vector3(x + 0.5, y + 1.02, z + 0.5)
		if not world.is_ready_at(p):
			continue
		var top: int = world.get_block(x, y, z)
		if top == Blocks.LEAVES:
			continue
		if need_grass and top != Blocks.GRASS:
			continue
		if Blocks.is_solid(world.get_block(x, y + 1, z)) or Blocks.is_solid(world.get_block(x, y + 2, z)):
			continue
		return p
	return Vector3.INF


func spawn_zombie(kind: String, at := Vector3.INF, near := Vector3.INF, type := "walker") -> Node:
	var p := at
	if p == Vector3.INF:
		p = _find_ground(16.0 if kind == "horde" else 22.0, 30.0 if kind == "horde" else 36.0, false, near)
	if p == Vector3.INF:
		return null
	var z := ZombieScript.new()
	z.setup(kind, day, type)
	z.net_id = _new_mob_id()
	G.sim.register_zombie(z)
	mobs.add_child(z)
	z.global_position = p
	return z


func _spawn_animal(near := Vector3.INF, min_d := 18.0, max_d := 40.0) -> Node:
	var p := _find_ground(min_d, max_d, true, near)
	if p == Vector3.INF:
		return null
	var a := AnimalScript.new()
	a.net_id = _new_mob_id()
	mobs.add_child(a)
	a.global_position = p
	return a
