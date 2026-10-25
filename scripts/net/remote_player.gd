extends Node3D
## Another player as seen on this PC: a survivor (Quaternius' Zombie Apocalypse Kit, CC0; picked
## by player id, the blocky figure if the model isn't there) with a name tag, drawn where
## NetClient's snapshot history says they were 100 ms ago.

const SURVIVORS := ["Matt", "Lis", "Sam", "Shaun"]
## The survivors' walk and run cycles: ground speed (m/s) at normal rate, at the size used here.
const SCALE := 1.25
const WALK_SPEED := 1.55
const RUN_SPEED := 4.1

var net_id := 0
var rig: Rig
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
## The crossed icons (for things without a 3D model), and the tool or weapon model (M4.3).
var held_icons: Node3D
var held_model: Node3D = null
## How a tool model sits in the hand: along the grip of the survivor's own weapon (+Y of our
## models along its +Z), or upright in the blocky figure's hand.
var model_turn := Basis.IDENTITY
var _swing := 0.0
var _anim := 0.0
var _spd := 0.0
var _dead := false
var _last_pos := Vector3.INF
## The drawn ground's height under the feet (game.gd), so the figure stands on what we see.
var ground_target := 0.0
## What they wear (M4.5, Proto.armor_bits), as last put on the model.
var armor_bits := 0
var ground_off := 0.0
var snap_y := INF


func _ready() -> void:
	model = Node3D.new()
	add_child(model)
	var path := "res://assets/models/survivors/Characters_%s_SingleWeapon.gltf" % SURVIVORS[net_id % SURVIVORS.size()]
	rig = Rig.make(path, Vector3.ONE * SCALE, ["Slash"])
	var icon_parent: Node3D
	if rig != null:
		model.add_child(rig)
		rig.move("Idle")
		head = _pivot(model, Vector3(0, 1.42, 0))  # (only carries the flashlight)
		# What they hold goes where the model's own weapon was (hidden), along its handle.
		held = Node3D.new()
		var grips := rig.strip_props()
		if grips.is_empty():
			model.add_child(held)
		else:
			grips[0].add_child(held)
			held.transform = (grips[0].get_child(0) as Node3D).transform
		icon_parent = _pivot(held, Vector3(0, 0, 0.2))
		icon_parent.rotation.x = PI * 0.5
		model_turn = Basis(Vector3.RIGHT, PI * 0.5)
	else:
		_build_boxes()
		held = _pivot(arm_r, Vector3(0, -0.64, 0.14))  # in the hand, a little in front of it
		held.rotation.x = 0.5  # the top leans forward, like a tool in hand
		icon_parent = held
	# Two crossed icons, so it reads from every side.
	held_mat = StandardMaterial3D.new()
	held_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	held_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	held_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	held_mat.roughness = 1.0
	var size := 0.4 if rig != null else 0.5
	for turn in [0.0, PI * 0.5]:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(size, size)
		mi.mesh = q
		mi.material_override = held_mat
		mi.rotation.y = turn
		icon_parent.add_child(mi)
	held.visible = false
	held_icons = icon_parent
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


## The blocky figure (when the survivor models aren't there). Colours vary per player so friends
## are easy to tell apart.
func _build_boxes() -> void:
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


func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = RoundBox.mesh(size)
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
	var s: Dictionary = G.net.interpolated(net_id)
	if s.is_empty():
		visible = false
		return
	visible = true
	var away: bool = (int(s["flags"]) & Proto.F_AWAY) != 0
	label.text = o["name"] + (" (away)" if away else "")
	# M4.4: allies' names are blue and tribe members' green, and both show through walls;
	# other players' names only where they can be seen.
	var rel: int = G.net.relation(o["name"])
	var col := Color(0.45, 1, 0.55) if rel & Proto.R_TRIBE else (Color(0.55, 0.8, 1) if rel & Proto.R_ALLY else Color(1, 1, 1))
	col.a = 0.55 if away else 1.0
	label.modulate = col
	var through := rel & Proto.R_ALLY != 0
	if label.no_depth_test != through:
		label.no_depth_test = through
	show_state(s["pos"], s["yaw"], s["pitch"], s["flags"], o.get("held", 0), delta)
	wear(int(o.get("armor", 0)))


## M4.5: the armor they wear (Proto.armor_bits), on the survivor model.
func wear(bits: int) -> void:
	if bits == armor_bits or rig == null:
		return
	armor_bits = bits
	ArmorModels.dress(rig, Proto.armor_tiers(bits))


## Stand, turn and move the figure as a snapshot says (lineup.gd calls this directly).
func show_state(pos: Vector3, yaw: float, pitch: float, flags: int, hid: int, delta: float) -> void:
	global_position = pos
	ground_off = move_toward(ground_off, ground_target, delta * 2.5)
	model.position.y = ground_off
	# The player's camera yaw points down -Z; the model faces +Z, so turn it around.
	model.rotation.y = yaw + PI
	head.rotation.x = -pitch
	light.visible = (flags & Proto.F_FLASHLIGHT) != 0
	if hid != held_id:
		held_id = hid
		held.visible = hid > 0 and G.tex != null
		if held_model != null:
			held_model.queue_free()
			held_model = null
		if held.visible and ToolModels.has_model(hid):
			held_model = ToolModels.make(hid)
			held_model.basis = model_turn  # (at the figure's own scale, like the kit's weapons)
			held.add_child(held_model)
			_set_icons(false)
		elif held.visible:
			held_mat.albedo_texture = G.tex.icon(hid)
			_set_icons(true)
	var dead := (flags & Proto.F_DEAD) != 0
	var speed := 0.0
	if _last_pos != Vector3.INF and delta > 0.0:
		speed = Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length() / delta
	_last_pos = pos
	if rig != null:
		_animate_rig(speed, flags, dead, delta)
		return
	model.rotation.x = lerpf(model.rotation.x, -PI * 0.5 if dead else 0.0, minf(1.0, delta * 6.0))
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


## The survivor's animations: dying, chopping (mining or hitting), or idle, walk and run played
## at the rate that matches their speed.
func _animate_rig(speed: float, flags: int, dead: bool, delta: float) -> void:
	_spd = lerpf(_spd, speed, minf(1.0, delta * 8.0))
	if dead:
		if not _dead:
			rig.play_once("Death")
	elif (flags & Proto.F_SWING) != 0:
		rig.move("Slash", 1.5)
	elif _spd < 0.3:
		rig.move("Idle")
	elif _spd < 2.6:
		rig.move("Walk", clampf(_spd / WALK_SPEED, 0.6, 1.7))
	else:
		rig.move("Run", clampf(_spd / RUN_SPEED, 0.7, 1.8))
	_dead = dead
	rig.tick(delta)


func _set_icons(on: bool) -> void:
	for c in held_icons.get_children():
		if c is MeshInstance3D:
			c.visible = on
