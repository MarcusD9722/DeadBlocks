extends Node3D
## Game flow: world setup, day/night cycle, blood moon hordes, spawning, menus.

## Real minutes per in-game day (DESIGN.md: 30). Tests can override it with --day-minutes=N.
var day_minutes := 30.0

var state := "loading"
var day := 1
var time := 7.0
var seed_v := 0
var kills := 0
var horde_active := false
var was_night := false
var warned := {}
var spawn_timer := 2.0
var animal_timer := 1.0
var spawn_pos := Vector3.ZERO
## Natural zombie/animal spawning. The benchmark turns it off to control the mob count itself.
var spawner_enabled := true
## Positions the world keeps loaded besides the local player (benchmark explorers now, remote players later).
var extra_stream_points: Array = []

var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var world: Node3D
var player: CharacterBody3D
var mobs: Node3D
var hud: CanvasLayer

const ZombieScript := preload("res://scripts/zombie.gd")
const AnimalScript := preload("res://scripts/animal.gd")
const RemotePlayerScript := preload("res://scripts/net/remote_player.gd")

## Client mode: other players' figures by net id.
var remote_players := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	seed_v = randi() % 1000000
	var sv := G.arg_value("--seed=")
	if sv != "":
		seed_v = int(sv)
	if G.arg_value("--day-minutes=") != "":
		day_minutes = maxf(0.1, float(G.arg_value("--day-minutes=")))
	if G.mode == "client":
		seed_v = int(G.session["seed"])
		day_minutes = float(G.session["day_minutes"])
	G.game = self
	if G.has_arg("--worldgen-hash"):
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
	var sfx := preload("res://scripts/sfx.gd").new()
	add_child(sfx)
	G.sfx = sfx
	_setup_env()

	world = preload("res://scripts/world.gd").new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	G.world = world
	world.setup(seed_v, G.tex)

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
		spawner_enabled = false
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
	player.inv.add(Items.BERRIES, 3)
	player.inv.add(Blocks.TORCH, 2)

	hud = preload("res://scripts/hud.gd").new()
	add_child(hud)
	G.hud = hud
	player.inv.changed.connect(hud.refresh_inventory)
	_update_sky()
	if G.mode == "client":
		hud.hide_title()
		hud.show_loading_overlay(true)

	if G.has_arg("--autotest"):
		var t := preload("res://scripts/autotest.gd").new()
		add_child(t)
	elif G.has_arg("--bench"):
		var b := preload("res://scripts/bench.gd").new()
		add_child(b)
	elif G.has_arg("--regiontest"):
		var rt := preload("res://scripts/tests/regiontest.gd").new()
		add_child(rt)


func _setup_input() -> void:
	var binds := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT],
	}
	for action in binds:
		if InputMap.has_action(action):
			continue  # already set up before a scene reload
		InputMap.add_action(action)
		for k in binds[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)


## Dedicated server: the world, the Sim and networking, but no window, player, HUD or sky.
func _ready_server() -> void:
	world = preload("res://scripts/world.gd").new()
	world.name = "World"
	add_child(world)
	G.world = world
	world.setup(seed_v, null)
	mobs = Node3D.new()
	mobs.name = "Mobs"
	add_child(mobs)
	var sim := preload("res://scripts/server/sim.gd").new()
	sim.name = "Sim"
	add_child(sim)
	spawn_pos = _find_spawn()
	# Zombies and animals come online in M1.4.
	spawner_enabled = false
	var ns := preload("res://scripts/net/net_server.gd").new()
	ns.name = "NetServer"
	add_child(ns)
	G.net_server = ns
	state = "server"
	if not ns.start():
		get_tree().quit(1)


func _setup_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 8.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 55.0
	env.fog_depth_end = 100.0
	env.fog_depth_curve = 1.5
	env.fog_sky_affect = 0.0
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.5
	add_child(sun)


func _find_spawn() -> Vector3:
	var g := WorldGen.new(seed_v)
	for r in range(0, 400, 3):
		for k in 16:
			var a := k * TAU / 16.0
			var x := int(round(cos(a) * r))
			var z := int(round(sin(a) * r))
			if g.biome_at(x, z) == 2:
				continue
			var h := g.height_at(x, z)
			if h > 42:
				continue
			if g.tree_near(x, z):
				continue
			return Vector3(x + 0.5, h + 1.02, z + 0.5)
	return Vector3(0.5, 60, 0.5)


# ------------------------------------------------------------ main loop

func _process(delta: float) -> void:
	match state:
		"server":
			world.update_centers(G.net_server.player_positions())
			# Time stops while nobody is online.
			if G.net_server.online_count() > 0:
				_tick_time(delta)
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
			_spawner(delta)
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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if state == "chat":
			return
		match event.keycode:
			KEY_T, KEY_ENTER:
				if state == "playing" and G.mode == "client":
					open_chat()
			KEY_ESCAPE:
				if state == "reconnecting":
					G.end_client_session("You left the server.")
				elif state == "playing":
					pause()
				elif state == "menu":
					close_inventory()
				elif state == "paused":
					resume()
			KEY_E, KEY_TAB:
				if state == "playing":
					open_inventory()
				elif state == "menu":
					close_inventory()
			KEY_F11:
				if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
				else:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			KEY_F6:
				if state == "playing":
					if G.mode == "client":
						G.net.send_chat("/dusk")
					else:
						skip_time(false)
			KEY_F7:
				if state == "playing":
					if G.mode == "client":
						G.net.send_chat("/bloodmoon")
					else:
						skip_time(true)
	elif event is InputEventMouseButton and event.pressed:
		if state == "playing" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "playing" and G.mode != "client":
		pause()


# ------------------------------------------------------------ states

func start_game() -> void:
	if state != "title":
		return
	state = "playing"
	hud.hide_title()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if G.mode == "client":
		hud.msg("Joined %s. Press T to chat, Esc for the player list." % G.net.host, Color(0.8, 1, 0.8))
		hud.msg("Test build: building, crafting and zombies come online in the next builds.", Color(1, 0.9, 0.6))
		return
	hud.msg("Day 1. Gather wood, craft tools, and build shelter before 20:00.", Color(1, 1, 0.8))
	hud.msg("Hold left click on a tree to collect logs.", Color(0.7, 1, 0.7))


func pause() -> void:
	state = "paused"
	# Online the world keeps running for everyone, so only the menu opens.
	if G.mode != "client":
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_pause(true)


func resume() -> void:
	state = "playing"
	get_tree().paused = false
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


func open_inventory() -> void:
	if state != "playing":
		return
	state = "menu"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_inventory(true)


func close_inventory() -> void:
	state = "playing"
	hud.show_inventory(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func on_player_died() -> void:
	if state == "menu":
		hud.show_inventory(false)
	state = "dead"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_death(true)


func respawn() -> void:
	player.respawn()
	hud.show_death(false)
	state = "playing"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func nearby_stations() -> Array:
	return world.stations_near(player.global_position + Vector3(0, 1, 0), 4)


func on_crafted(id: int) -> void:
	if id == Blocks.WORKBENCH and not warned.has("bench_made"):
		warned["bench_made"] = true
		hud.msg("Select the Workbench in your hotbar and right-click to place it.", Color(0.7, 1, 0.7))


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
	_update_sky()


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
	for z in get_tree().get_nodes_in_group("zombies"):
		var near := false
		for p in G.sim.players:
			if is_instance_valid(p) and z.global_position.distance_to(p.global_position) <= 28.0:
				near = true
		if not near:
			z.queue_free()


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


func _update_sky() -> void:
	if env == null:
		return
	var t := time
	var day_f := clampf(smoothstep(5.0, 7.0, t) - smoothstep(18.5, 20.5, t), 0.0, 1.0)
	var dusk_f := maxf(0.0, 1.0 - absf(t - 19.0) / 1.6) + maxf(0.0, 1.0 - absf(t - 6.0) / 1.6)
	dusk_f = clampf(dusk_f, 0.0, 1.0)
	var blood := horde_active or (day % 7 == 0 and t >= 18.0)
	if day_f > 0.35:
		var ang := clampf((t - 6.0) / 12.0 * PI, 0.12, PI - 0.12)
		sun.rotation = Vector3(-ang, deg_to_rad(35.0), 0.0)
		sun.light_color = Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.62, 0.38), dusk_f)
		sun.light_energy = 1.15 * day_f
	else:
		var mt := fmod(t - 18.0 + 24.0, 24.0)
		var ang2 := clampf(mt / 12.0 * PI, 0.25, PI - 0.25)
		sun.rotation = Vector3(-ang2, deg_to_rad(-20.0), 0.0)
		sun.light_color = Color(1.0, 0.35, 0.3) if blood else Color(0.6, 0.7, 1.0)
		sun.light_energy = (0.32 if blood else 0.2) * (1.0 - day_f)
	var top_day := Color(0.3, 0.52, 0.9)
	var hor_day := Color(0.66, 0.78, 0.92)
	var hor_dusk := Color(0.95, 0.55, 0.35)
	var top_night := Color(0.02, 0.03, 0.08)
	var hor_night := Color(0.07, 0.09, 0.16)
	if blood:
		top_night = Color(0.14, 0.0, 0.02)
		hor_night = Color(0.5, 0.06, 0.04)
		hor_dusk = Color(0.85, 0.2, 0.1)
	var top := top_night.lerp(top_day, day_f)
	var hor := hor_night.lerp(hor_day, day_f).lerp(hor_dusk, dusk_f * 0.75)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sky_mat.ground_bottom_color = top.darkened(0.4)
	env.fog_light_color = hor
	var amb_day := Color(0.62, 0.68, 0.8)
	var amb_night := Color(0.34, 0.1, 0.08) if blood else Color(0.2, 0.24, 0.42)
	env.ambient_light_color = amb_night.lerp(amb_day, day_f)
	env.ambient_light_energy = lerpf(0.35, 0.65, day_f)


# ------------------------------------------------------------ spawning

func _spawner(delta: float) -> void:
	if player.dead or not spawner_enabled:
		return
	spawn_timer -= delta
	animal_timer -= delta
	var zs := get_tree().get_nodes_in_group("zombies")
	for z in zs:
		if z.global_position.distance_to(player.global_position) > 72.0:
			z.queue_free()
	var night := is_night()
	var cap := 2
	var interval := 9.0
	if horde_active:
		cap = 22 + mini(day, 28)
		interval = 1.0
	elif night:
		cap = mini(5 + day, 16)
		interval = 3.0
	if spawn_timer <= 0.0:
		spawn_timer = interval
		if zs.size() < cap:
			var kind := "horde" if horde_active else ("night" if night else "day")
			spawn_zombie(kind)
	if animal_timer <= 0.0:
		animal_timer = 6.0
		if not night and get_tree().get_nodes_in_group("animals").size() < 6:
			_spawn_animal()
	for a in get_tree().get_nodes_in_group("animals"):
		if a.global_position.distance_to(player.global_position) > 80.0:
			a.queue_free()


func _find_ground(min_d: float, max_d: float, need_grass: bool) -> Vector3:
	for attempt in 8:
		var a := randf() * TAU
		var d := randf_range(min_d, max_d)
		var x := floori(player.global_position.x + cos(a) * d)
		var z := floori(player.global_position.z + sin(a) * d)
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


func spawn_zombie(kind: String, at := Vector3.INF) -> Node:
	var p := at
	if p == Vector3.INF:
		p = _find_ground(16.0 if kind == "horde" else 22.0, 30.0 if kind == "horde" else 36.0, false)
	if p == Vector3.INF:
		return null
	var z := ZombieScript.new()
	z.setup(kind, day)
	G.sim.register_zombie(z)
	mobs.add_child(z)
	z.global_position = p
	return z


func _spawn_animal() -> void:
	var p := _find_ground(18.0, 40.0, true)
	if p == Vector3.INF:
		return
	var a := AnimalScript.new()
	mobs.add_child(a)
	a.global_position = p
