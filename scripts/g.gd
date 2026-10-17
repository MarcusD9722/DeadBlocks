extends Node
## Global references shared by every system.

## Shown on the title screen; the M1.2 join check will compare it between client and server.
const VERSION := "0.2.0"
const BUILD_NAME := "M1.1"

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
## Set by --server-mode, by the dedicated server build (feature "dedicated_server"), and later by --server.
var server_mode := false


func _ready() -> void:
	args = OS.get_cmdline_user_args()
	server_mode = has_arg("--server-mode") or has_arg("--server") or OS.has_feature("dedicated_server")
	if server_mode:
		Engine.physics_ticks_per_second = 30
		Engine.max_fps = 30


func has_arg(a: String) -> bool:
	return args.has(a)


func arg_value(prefix: String) -> String:
	for a in args:
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""
