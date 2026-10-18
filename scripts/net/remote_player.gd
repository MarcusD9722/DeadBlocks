extends Node3D
## Another player as seen on this PC: a blocky figure with a name tag, drawn where NetClient's
## snapshot history says they were 100 ms ago.

var net_id := 0
var model: Node3D
var head: Node3D
var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var label: Label3D
var light: SpotLight3D
## What they hold, in their right hand: two crossed icons, so it reads from every side.
var held: Node3D
var held_mat: StandardMaterial3D
var held_id := 0
var _swing := 0.0
var _anim := 0.0
var _last_pos := Vector3.INF


func _ready() -> void:
	model = Node3D.new()
	add_child(model)
	# Colours vary per player so friends are easy to tell apart.
	var rng := RandomNumberGenerator.new()
	rng.seed = net_id * 7919
	var shirt := Color.from_hsv(rng.randf(), 0.55, 0.75)
	var skin := Color8(232, 190, 150).lerp(Color8(120, 80, 55), rng.randf())
	var pants := Color8(50, 58, 82)
	head = _pivot(model, Vector3(0, 1.42, 0))
	_box(head, Vector3(0.48, 0.48, 0.48), Vector3(0, 0.22, 0), skin)
	_box(head, Vector3(0.1, 0.06, 0.02), Vector3(-0.11, 0.26, 0.245), Color8(30, 30, 40))
	_box(head, Vector3(0.1, 0.06, 0.02), Vector3(0.11, 0.26, 0.245), Color8(30, 30, 40))
	_box(model, Vector3(0.5, 0.72, 0.28), Vector3(0, 1.04, 0), shirt)
	leg_l = _pivot(model, Vector3(-0.125, 0.68, 0))
	leg_r = _pivot(model, Vector3(0.125, 0.68, 0))
	_box(leg_l, Vector3(0.24, 0.68, 0.26), Vector3(0, -0.34, 0), pants)
	_box(leg_r, Vector3(0.24, 0.68, 0.26), Vector3(0, -0.34, 0), pants)
	# The figure faces +Z, so its right hand is on the -X side.
	arm_l = _pivot(model, Vector3(0.37, 1.36, 0))
	arm_r = _pivot(model, Vector3(-0.37, 1.36, 0))
	_box(arm_l, Vector3(0.22, 0.7, 0.22), Vector3(0, -0.33, 0), shirt.darkened(0.15))
	_box(arm_r, Vector3(0.22, 0.7, 0.22), Vector3(0, -0.33, 0), shirt.darkened(0.15))
	held = _pivot(arm_r, Vector3(0, -0.64, 0.14))  # in the hand, a little in front of it
	held_mat = StandardMaterial3D.new()
	held_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	held_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	held_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	held_mat.roughness = 1.0
	for turn in [0.0, PI * 0.5]:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.5, 0.5)
		mi.mesh = q
		mi.material_override = held_mat
		mi.rotation.y = turn
		held.add_child(mi)
	held.rotation.x = 0.5  # the top leans forward, like a tool in hand
	held.visible = false
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	# Same size on screen at any distance, so friends far away can still be read.
	label.fixed_size = true
	label.pixel_size = 0.0007
	label.font_size = 40
	label.outline_size = 10
	label.position = Vector3(0, 2.25, 0)
	add_child(label)
	light = SpotLight3D.new()
	light.spot_range = 24
	light.spot_angle = 27
	light.light_energy = 2.0
	light.visible = false
	light.position = Vector3(0.2, 0.25, -0.2)
	head.add_child(light)
	light.rotation.y = PI


func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	mi.material_override = m
	parent.add_child(mi)
	mi.position = pos


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	parent.add_child(p)
	p.position = pos
	return p


func _process(delta: float) -> void:
	var o = G.net.others.get(net_id)
	if o == null:
		return
	label.text = o["name"]
	var s: Dictionary = G.net.interpolated(net_id)
	if s.is_empty():
		visible = false
		return
	visible = true
	var pos: Vector3 = s["pos"]
	global_position = pos
	# The player's camera yaw points down -Z; the model faces +Z, so turn it around.
	model.rotation.y = s["yaw"] + PI
	head.rotation.x = -s["pitch"]
	var flags: int = s["flags"]
	light.visible = (flags & Proto.F_FLASHLIGHT) != 0
	var hid: int = o.get("held", 0)
	if hid != held_id:
		held_id = hid
		held.visible = hid > 0 and G.tex != null
		if held.visible:
			held_mat.albedo_texture = G.tex.icon(hid)
	var dead := (flags & Proto.F_DEAD) != 0
	model.rotation.x = lerpf(model.rotation.x, -PI * 0.5 if dead else 0.0, minf(1.0, delta * 6.0))
	var speed := 0.0
	if _last_pos != Vector3.INF and delta > 0.0:
		speed = Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length() / delta
	_last_pos = pos
	_anim += delta * speed * 2.6
	var mv := minf(1.0, speed / 3.0)
	leg_l.rotation.x = sin(_anim) * 0.7 * mv
	leg_r.rotation.x = -sin(_anim) * 0.7 * mv
	arm_l.rotation.x = -sin(_anim) * 0.5 * mv
	# Mining or hitting: the right arm chops up and down.
	if (flags & Proto.F_SWING) != 0:
		_swing += delta * 14.0
		arm_r.rotation.x = -0.9 - absf(sin(_swing)) * 0.9
	else:
		_swing = 0.0
		arm_r.rotation.x = sin(_anim) * 0.5 * mv
