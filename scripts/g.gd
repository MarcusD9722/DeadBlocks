extends Node
## Global references shared by every system, the play mode, and the network connection.

## Shown on the title screen; client and server must run the same version to play together.
const VERSION := "0.14.0"
const BUILD_NAME := "Building"

var game: Node = null
var world: Node3D = null
var player: CharacterBody3D = null
var hud: CanvasLayer = null
var sim: Node = null
var tex = null
var sfx: Node = null
## The look of the world: sky, light, fog, graphics quality (gfx.gd). Null on a server.
var gfx: Node = null
var args: PackedStringArray = PackedStringArray()
## Server mode: simulate the world without anything only a player would see or hear
## (render meshes, lights, mob models, sounds). Physics runs at 30 ticks/s.
## Set by --server-mode, --server, and the dedicated server build (feature "dedicated_server").
var server_mode := false
## "solo" (the title screen's own world; the tests run in it too), "client" (joined a server,
## including Play solo's server on this PC), or "server" (dedicated server, no window).
var mode := "solo"
## Play solo: we're the only player on a server this game started (127.0.0.1); the pause menu
## stops its world.
var solo := false
## Client mode: what the server told us when we joined (seed, position, clock, ...).
var session := {}
## Client networking; lives here so the connection survives the scene reload into the server's world.
var net: Node = null
## Switches the game to the server's version when they differ (updater.gd).
var updater: Node = null
const UpdaterScript := preload("res://scripts/updater.gd")
## Joining the server again by ourselves after an update: a failure goes back to the title.
var rejoining := false
## Dedicated server networking (server mode only).
var net_server: Node = null
## Shown on the title screen after a disconnect.
var title_notice := ""
## Host game: the background server process this game started.
var host_pid := 0
var _autojoin_done := false


func _ready() -> void:
	args = OS.get_cmdline_user_args()
	if arg_value("--finish-update=") != "":
		# The new version, started by the old one to take its place (updater.gd).
		UpdaterScript.finish(arg_value("--finish-update="), not has_arg("--finish-no-launch"))
		get_tree().quit()
		return
	if has_arg("--version"):
		print("Dead Blocks %s" % VERSION)  # update.sh checks a new server program runs with this
		get_tree().quit()
		return
	var test_run := has_arg("--autotest") or has_arg("--bench") or has_arg("--regiontest") or has_arg("--typetest") or has_arg("--lineup") or has_arg("--scenery") or has_arg("--worldgen-hash") or has_arg("--savetest") or has_arg("--meshtest")
	if has_arg("--server") or (OS.has_feature("dedicated_server") and not test_run):
		mode = "server"
	server_mode = mode == "server" or has_arg("--server-mode") or OS.has_feature("dedicated_server")
	if mode == "server":
		_load_server_cfg()
	if server_mode:
		Engine.physics_ticks_per_second = 30
		Engine.max_fps = 30
	net = preload("res://scripts/net/net_client.gd").new()
	net.name = "NetClient"
	add_child(net)
	net.fake_version = arg_value("--fake-version=")
	net.fake_terrain = has_arg("--fake-terrain")
	updater = UpdaterScript.new()
	updater.name = "Updater"
	add_child(updater)
	if has_arg("--after-update"):
		print("UPDATE now running Dead Blocks %s" % VERSION)
		updater.cleanup_after_update()
	if has_arg("--nettest") or arg_value("--nettest=") != "":
		var t := preload("res://scripts/tests/nettest.gd").new()
		t.name = "NetTest"
		add_child(t)
	elif has_arg("--autotest"):
		# Lives here, not in the game scene, so it survives the reload into the solo game.
		var at := preload("res://scripts/autotest.gd").new()
		at.name = "AutoTest"
		add_child(at)


## server.cfg keys (written by tools/pi/install.sh) and the flags they stand for.
const CFG_FLAGS := {"port": "--port=", "password": "--password=", "max_players": "--max-players=",
	"admins": "--admins=", "day_minutes": "--day-minutes=", "autosave_s": "--autosave=", "world": "--world=",
	"seed": "--seed=", "respawn_radius": "--respawn-radius=", "backpack_s": "--backpack-s=",
	"linger_s": "--linger-s="}


## The server's settings file, <data folder>/server.cfg: "key=value" lines, # for comments.
## Flags given on the command line win over it.
func _load_server_cfg() -> void:
	var dir := arg_value("--data=")
	var file := (dir if dir != "" else "user://server").path_join("server.cfg")
	if not FileAccess.file_exists(file):
		return
	var used := PackedStringArray()
	for raw in FileAccess.get_file_as_string(file).split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#") or line.find("=") < 0:
			continue
		var key := line.left(line.find("=")).strip_edges()
		var value := line.substr(line.find("=") + 1).strip_edges()
		if not CFG_FLAGS.has(key):
			printerr("SERVER WARNING: unknown setting \"%s\" in %s" % [key, file])
			continue
		if arg_value(CFG_FLAGS[key]) != "":
			continue
		args.append(CFG_FLAGS[key] + value)
		used.append(key if key == "password" else "%s %s" % [key, value])
	print("SERVER settings from %s: %s" % [ProjectSettings.globalize_path(file), ", ".join(used)])


func has_arg(a: String) -> bool:
	return args.has(a)


func arg_value(prefix: String) -> String:
	for a in args:
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


## Tests and power users: --connect=host[:port] --name=N --pin=P --password=S joins on startup.
## After an update, the game joins the server it was joining (updater.gd's rejoin.cfg).
func wants_autojoin() -> bool:
	if mode != "solo" or _autojoin_done:
		return false
	return arg_value("--connect=") != "" or (has_arg("--after-update") and FileAccess.file_exists(UpdaterScript.REJOIN_CFG))


func autojoin() -> void:
	_autojoin_done = true
	if arg_value("--connect=") == "":
		var cfg := ConfigFile.new()
		cfg.load(UpdaterScript.REJOIN_CFG)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UpdaterScript.REJOIN_CFG))
		if not cfg.has_section_key("rejoin", "host"):
			end_client_session("Updated to Dead Blocks %s." % VERSION)
			return
		rejoining = true
		join(cfg.get_value("rejoin", "host"), int(cfg.get_value("rejoin", "port")), cfg.get_value("rejoin", "name"),
			Marshalls.base64_to_raw(cfg.get_value("rejoin", "pin_key")), Marshalls.base64_to_raw(cfg.get_value("rejoin", "password_key")))
		return
	var hp := split_address(arg_value("--connect="))
	var pname := arg_value("--name=")
	join(hp[0], hp[1], pname, Proto.pin_key(pname, arg_value("--pin=")), Proto.password_key(arg_value("--password=")))


func join(host: String, port: int, pname: String, pin_key: PackedByteArray, password_key: PackedByteArray) -> void:
	solo = false  # play_solo sets it again once its server is up
	net.join(host, port, pname, pin_key, password_key)


## "host" or "host:port" -> [host, port]
static func split_address(a: String) -> Array:
	a = a.strip_edges()
	var port := Proto.DEFAULT_PORT
	var i := a.rfind(":")
	if i > 0 and a.count(":") == 1:
		port = int(a.substr(i + 1))
		a = a.substr(0, i)
	return [a, port]


## Called by NetClient when the server's welcome arrives: reload into the server's world.
func start_client_session(welcome: Dictionary) -> void:
	session = welcome
	rejoining = false
	net.detach()
	mode = "client"
	get_tree().paused = false
	get_tree().call_deferred("reload_current_scene")


## Called by NetClient after it reconnected to the same world: carry on without reloading.
func resume_client_session(welcome: Dictionary) -> void:
	session = welcome
	if game != null and is_instance_valid(game):
		game.on_reconnected(welcome)


## Back to the title screen with a message (disconnect, kick, server stopped).
func end_client_session(notice: String) -> void:
	net.leave()
	net.detach()
	stop_host()
	session = {}
	mode = "solo"
	solo = false
	title_notice = notice
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().call_deferred("reload_current_scene")


## Host game: start this same program as a dedicated server in the background, then join it.
## Closing the game stops the server; if the game crashes, the server notices the host is gone
## and stops by itself (--hosted-by).
## The Host game and Play solo worlds live in this PC's game data folder (worlds/host,
## worlds/solo, backups/).
const HOST_WORLD := "host"
const SOLO_WORLD := "solo"
const SOLO_NAME := "Player"
const SOLO_PIN := "0000"


func host_game(pname: String, pin: String, password: String, port: int, new_world := false) -> String:
	var err: String = await _launch_server(pname, pin, password, port, HOST_WORLD, new_world, [])
	if err == "The server stopped right away.":
		err += " Is something else using UDP port %d, or another game hosting? (Details: %s)" % [
			port, ProjectSettings.globalize_path("user://logs/host_server.log")]
	return err


## Play solo: the same server as Host game, on this PC only (127.0.0.1, a random port and
## password), one player, and its world stops while the pause menu is open. The world is kept
## in worlds/solo (`world` is for the autotest's own).
func play_solo(new_world := false, world := SOLO_WORLD) -> String:
	var pw := ""
	for i in 16:
		pw += "abcdefghijkmnpqrstuvwxyz23456789"[randi() % 32]
	var err := ""
	for attempt in 3:  # a random port that happens to be taken: try another
		var port := 20000 + randi() % 40000
		err = await _launch_server(SOLO_NAME, SOLO_PIN, pw, port, world, new_world,
			["--solo", "--bind=127.0.0.1", "--max-players=1"])
		if err == "":
			solo = true
			return ""
	return err + " (Details: %s)" % ProjectSettings.globalize_path("user://logs/host_server.log")


func _launch_server(pname: String, pin: String, password: String, port: int, world: String, new_world: bool, extra: Array) -> String:
	stop_host()
	var exe := OS.get_executable_path()
	var a := PackedStringArray()
	if OS.has_feature("editor"):
		a.append_array(["--path", ProjectSettings.globalize_path("res://")])
	# Its own log file, so it doesn't fight the game over godot.log.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://logs"))
	a.append_array(["--log-file", ProjectSettings.globalize_path("user://logs/host_server.log")])
	var seed_arg := arg_value("--seed=")  # tests pick the seed; otherwise a new world gets a random one
	a.append_array(["--headless", "--", "--server", "--port=%d" % port, "--password=%s" % password,
		"--admins=%s" % pname, "--hosted-by=%s" % pname, "--seed=%s" % (seed_arg if seed_arg != "" else str(randi() % 1000000)),
		"--data=%s" % ProjectSettings.globalize_path("user://"), "--world=%s" % world])
	if arg_value("--day-minutes=") != "":
		a.append("--day-minutes=" + arg_value("--day-minutes="))
	if new_world:
		a.append("--new-world")
	a.append_array(PackedStringArray(extra))
	host_pid = OS.create_process(exe, a)
	if host_pid <= 0:
		host_pid = 0
		return "Could not start the server process."
	# Give the server a moment to open its port; the client keeps retrying for a few seconds anyway.
	await get_tree().create_timer(1.5).timeout
	if not OS.is_process_running(host_pid):
		host_pid = 0
		return "The server stopped right away."
	join("127.0.0.1", port, pname, Proto.pin_key(pname, pin), Proto.password_key(password))
	return ""


## Ask the hosted server to save and stop (a file in control/), and only kill it if it hasn't
## stopped after a few seconds.
func stop_host() -> void:
	if host_pid <= 0 or not OS.is_process_running(host_pid):
		host_pid = 0
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://control"))
	var f := FileAccess.open("user://control/stop-host.cmd", FileAccess.WRITE)
	if f != null:
		f.store_string("stop")
		f.close()
	for i in 50:
		if not OS.is_process_running(host_pid):
			break
		OS.delay_msec(100)
	if OS.is_process_running(host_pid):
		OS.kill(host_pid)
	host_pid = 0


## A Host game or Play solo world on this PC, if there is one: {day, time, saved (unix time)}.
static func world_info(world: String) -> Dictionary:
	var meta = preload("res://scripts/server/save.gd")._read_json(
		ProjectSettings.globalize_path("user://worlds").path_join(world).path_join("world.json"))
	return meta if meta != null else {}


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		stop_host()
