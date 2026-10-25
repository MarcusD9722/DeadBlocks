class_name Controls
extends RefCounted
## Every action the game listens to, with its key or mouse button and its controller button (M4.1).
## The keys can be changed in Settings → Controls (saved in user://controls.cfg); the controller
## layout is fixed (Xbox names; other pads map onto it).

const FILE := "user://controls.cfg"
## Mouse buttons are stored as negative numbers among the keys.
const MOUSE_LEFT := -MOUSE_BUTTON_LEFT
const MOUSE_RIGHT := -MOUSE_BUTTON_RIGHT
const MOUSE_MIDDLE := -MOUSE_BUTTON_MIDDLE
## The actions Settings lists, in order: [action, what it does, default key].
const ACTIONS := [
	["move_forward", "Move forward", KEY_W],
	["move_back", "Move back", KEY_S],
	["move_left", "Move left", KEY_A],
	["move_right", "Move right", KEY_D],
	["jump", "Jump", KEY_SPACE],
	["sprint", "Sprint", KEY_SHIFT],
	["attack", "Mine / hit", MOUSE_LEFT],
	["use", "Place / eat / use", MOUSE_RIGHT],
	["interact", "Interact (stations, bags)", KEY_E],
	["inventory", "Inventory and crafting", KEY_I],
	["flashlight", "Flashlight", KEY_F],
	["chat", "Chat", KEY_T],
]
## Extra keys that always work besides the one in Settings.
const EXTRA_KEYS := {
	"move_forward": [KEY_UP], "move_back": [KEY_DOWN], "move_left": [KEY_LEFT], "move_right": [KEY_RIGHT],
	"chat": [KEY_ENTER], "pause": [KEY_ESCAPE],
}
## The controller: buttons, and [axis, direction] for sticks and triggers.
const PAD := {
	"move_forward": [[JOY_AXIS_LEFT_Y, -1.0]], "move_back": [[JOY_AXIS_LEFT_Y, 1.0]],
	"move_left": [[JOY_AXIS_LEFT_X, -1.0]], "move_right": [[JOY_AXIS_LEFT_X, 1.0]],
	"look_left": [[JOY_AXIS_RIGHT_X, -1.0]], "look_right": [[JOY_AXIS_RIGHT_X, 1.0]],
	"look_up": [[JOY_AXIS_RIGHT_Y, -1.0]], "look_down": [[JOY_AXIS_RIGHT_Y, 1.0]],
	"jump": [JOY_BUTTON_A], "sprint": [JOY_BUTTON_LEFT_STICK],
	"attack": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]], "use": [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"interact": [JOY_BUTTON_X], "inventory": [JOY_BUTTON_Y], "flashlight": [JOY_BUTTON_DPAD_UP],
	"hotbar_prev": [JOY_BUTTON_LEFT_SHOULDER], "hotbar_next": [JOY_BUTTON_RIGHT_SHOULDER],
	"pause": [JOY_BUTTON_START],
	# Menus: A presses, B goes back (the D-pad and the left stick already move between buttons).
	"ui_accept": [JOY_BUTTON_A], "ui_cancel": [JOY_BUTTON_B],
}
## What the controller does, for the Settings screen.
const PAD_HELP := "Controller: left stick move, right stick look, A jump, click the left stick to sprint, " \
	+ "right trigger mine / hit, left trigger place / use, X interact, Y inventory, LB / RB hotbar, " \
	+ "D-pad up flashlight, Start pause. In menus: D-pad or stick to move, A to press, B to go back."

static var _keys := {}
## The last input came from a controller (prompts show its buttons).
static var pad_in_use := false


## Make every action and give it its keys and buttons (once per run; a scene reload keeps them).
static func setup() -> void:
	if InputMap.has_action("interact"):
		return
	for a in ACTIONS:
		_keys[a[0]] = a[2]
	var cf := ConfigFile.new()
	if cf.load(FILE) == OK:
		for a in ACTIONS:
			var k = cf.get_value("keys", a[0], null)
			if k is int:
				_keys[a[0]] = k
	var names := []
	for a in ACTIONS:
		names.append(a[0])
	names.append_array(["look_left", "look_right", "look_up", "look_down", "hotbar_prev", "hotbar_next", "pause"])
	for n in names:
		if not InputMap.has_action(n):
			InputMap.add_action(n, 0.25)
	for n in PAD:
		for p in PAD[n]:
			InputMap.action_add_event(n, _pad_event(p))
	# The mouse wheel turns the hotbar.
	InputMap.action_add_event("hotbar_prev", _key_event(-MOUSE_BUTTON_WHEEL_UP))
	InputMap.action_add_event("hotbar_next", _key_event(-MOUSE_BUTTON_WHEEL_DOWN))
	InputMap.action_add_event("pause", _key_event(KEY_ESCAPE))
	for a in ACTIONS:
		_apply(a[0])


## Notes whether the player is on the controller or the keyboard and mouse (game.gd calls this).
static func note(e: InputEvent) -> void:
	if e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf(e.axis_value) > 0.4):
		pad_in_use = true
	elif e is InputEventKey or e is InputEventMouseButton:
		pad_in_use = false


## The key (or negative mouse button) an action is on.
static func key_of(action: String) -> int:
	return int(_keys.get(action, 0))


## Put an action on another key (or mouse button) and save it.
static func rebind(action: String, key: int) -> void:
	_keys[action] = key
	_apply(action)
	_save()


static func reset() -> void:
	for a in ACTIONS:
		_keys[a[0]] = a[2]
		_apply(a[0])
	_save()


## A key's name for the screen ("E", "Left mouse").
static func key_name(key: int) -> String:
	match key:
		MOUSE_LEFT:
			return "Left mouse"
		MOUSE_RIGHT:
			return "Right mouse"
		MOUSE_MIDDLE:
			return "Middle mouse"
	if key < 0:
		return "Mouse %d" % -key
	return OS.get_keycode_string(key)


## The key or mouse button an input event is, for rebinding (0 if it can't be one).
static func key_from_event(e: InputEvent) -> int:
	if e is InputEventKey and e.pressed and not e.echo:
		var k: int = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
		return 0 if k == KEY_ESCAPE else k
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			return 0
		return -e.button_index
	return 0


static func _apply(action: String) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			InputMap.action_erase_event(action, e)
	InputMap.action_add_event(action, _key_event(key_of(action)))
	for k in EXTRA_KEYS.get(action, []):
		InputMap.action_add_event(action, _key_event(k))


static func _save() -> void:
	var cf := ConfigFile.new()
	for a in ACTIONS:
		cf.set_value("keys", a[0], _keys[a[0]])
	cf.save(FILE)


static func _key_event(key: int) -> InputEvent:
	if key < 0:
		var m := InputEventMouseButton.new()
		m.button_index = -key as MouseButton
		return m
	var e := InputEventKey.new()
	e.physical_keycode = key as Key
	return e


static func _pad_event(p) -> InputEvent:
	if p is Array:
		var m := InputEventJoypadMotion.new()
		m.axis = p[0]
		m.axis_value = p[1]
		m.device = -1
		return m
	var b := InputEventJoypadButton.new()
	b.button_index = p
	b.device = -1
	return b
