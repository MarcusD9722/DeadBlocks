extends Node
## Global references shared by every system.

var game: Node = null
var world: Node3D = null
var player: CharacterBody3D = null
var hud: CanvasLayer = null
var tex = null
var sfx: Node = null
var args: PackedStringArray = PackedStringArray()


func _ready() -> void:
	args = OS.get_cmdline_user_args()


func has_arg(a: String) -> bool:
	return args.has(a)


func arg_value(prefix: String) -> String:
	for a in args:
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""
