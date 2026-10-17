extends Node
## Global references shared by every system, the play mode, and the network connection.

## Shown on the title screen; client and server must run the same version to play together.
const VERSION := "0.2.2"
const BUILD_NAME := "M1.2"

var game: Node = null
var world: Node3D = null
var player: CharacterBody3D = null
var hud: CanvasLayer = null
var sim: Node = null
var tex = null
var sfx: Node = null
var args: PackedStringArray = PackedStringArray()
## Server mode: simulate the world without anything only a player would see or hear
## (render meshes, lights, mob models, sounds). Physics runs at 30 ticks/s.
## Set by --server-mode, --server, and the dedicated server build (feature "dedicated_server").
var server_mode := false
## "solo" (play alone), "client" (joined a server), or "server" (dedicated server, no window).
var mode := "solo"
## Client mode: what the server told us when we joined (seed, position, clock, ...).
var session := {}
## Client networking; lives here so the connection survives the scene reload into the server's world.
var net: Node = null
## Dedicated server networking (server mode only).
var net_server: Node = null
## Shown on the title screen after a disconnect.
var title_notice := ""
## Host game: the background server process this game started.
var host_pid := 0
var _autojoin_done := false


func _ready() -> void:
	args = OS.get_cmdline_user_args()
	var test_run := has_arg("--autotest") or has_arg("--bench") or has_arg("--regiontest") or has_arg("--worldgen-hash")
	if has_arg("--server") or (OS.has_feature("dedicated_server") and not test_run):
		mode = "server"
	server_mode = mode == "server" or has_arg("--server-mode") or OS.has_feature("dedicated_server")
	if server_mode:
		Engine.physics_ticks_per_second = 30
		Engine.max_fps = 30
	net = preload("res://scripts/net/net_client.gd").new()
	net.name = "NetClient"
	add_child(net)
	net.fake_version = arg_value("--fake-version=")
	net.fake_terrain = has_arg("--fake-terrain")
	if has_arg("--nettest") or arg_value("--nettest=") != "":
		var t := preload("res://scripts/tests/nettest.gd").new()
		t.name = "NetTest"
		add_child(t)


func has_arg(a: String) -> bool:
	return args.has(a)


func arg_value(prefix: String) -> String:
	for a in args:
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


## Tests and power users: --connect=host[:port] --name=N --pin=P --password=S joins on startup.
func wants_autojoin() -> bool:
	return mode == "solo" and not _autojoin_done and arg_value("--connect=") != ""


func autojoin() -> void:
	_autojoin_done = true
	var hp := split_address(arg_value("--connect="))
	var pname := arg_value("--name=")
	join(hp[0], hp[1], pname, Proto.pin_key(pname, arg_value("--pin=")), Proto.password_key(arg_value("--password=")))


func join(host: String, port: int, pname: String, pin_key: PackedByteArray, password_key: PackedByteArray) -> void:
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
	stop_host()
	session = {}
	mode = "solo"
	title_notice = notice
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().call_deferred("reload_current_scene")


## Host game: start this same program as a dedicated server in the background, then join it.
## Closing the game stops the server; if the game crashes, the server notices the host is gone
## and stops by itself (--hosted-by).
func host_game(pname: String, pin: String, password: String, port: int) -> String:
	stop_host()
	var exe := OS.get_executable_path()
	var a := PackedStringArray()
	if OS.has_feature("editor"):
		a.append_array(["--path", ProjectSettings.globalize_path("res://")])
	# Its own log file, so it doesn't fight the game over godot.log.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://logs"))
	a.append_array(["--log-file", ProjectSettings.globalize_path("user://logs/host_server.log")])
	a.append_array(["--headless", "--", "--server", "--port=%d" % port, "--password=%s" % password,
		"--admins=%s" % pname, "--hosted-by=%s" % pname, "--seed=%d" % (randi() % 1000000)])
	host_pid = OS.create_process(exe, a)
	if host_pid <= 0:
		host_pid = 0
		return "Could not start the server process."
	# Give the server a moment to open its port; the client keeps retrying for a few seconds anyway.
	await get_tree().create_timer(1.5).timeout
	if not OS.is_process_running(host_pid):
		host_pid = 0
		return "The server stopped right away. Is something else using UDP port %d?" % port
	join("127.0.0.1", port, pname, Proto.pin_key(pname, pin), Proto.password_key(password))
	return ""


func stop_host() -> void:
	if host_pid > 0:
		OS.kill(host_pid)
		host_pid = 0


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		stop_host()
