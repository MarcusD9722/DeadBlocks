extends Mob
## Wild boar. Wanders, runs when hurt, drops raw meat.

## The model: Quaternius' pig (Farm Animals, CC0) in boar colours with tusks. It comes with an
## idle animation only, so its legs are swung here when it walks.
const PIG := "res://assets/models/animals/Pig.fbx"
const PIG_LEGS := ["FrontUpLeg.R", "BackUpLeg.L", "FrontUpLeg.L", "BackUpLeg.R"]

var wander_dir := Vector3.ZERO
var wander_t := 0.0
var flee_t := 0.0
var legs: Array[Node3D] = []
## The pig model's leg bones and their rest rotations.
var _bones: Array[int] = []
var _rests: Array[Quaternion] = []


func _ready() -> void:
	hp = 20.0
	max_hp = 20.0
	if view:
		set_physics_process(false)  # moved by the server's snapshots
	else:
		add_to_group("animals")
	_setup_body(0.8, 0.9)
	if not G.server_mode:
		_build_model()


func _build_model() -> void:
	var fur := Color8(112, 74, 52).lerp(Color8(84, 60, 44), randf())
	var r := Rig.make(PIG, Vector3.ONE * 0.2)
	if r != null:
		r.mats[0].albedo_color = fur.darkened(0.12)  # body
		r.mats[1].albedo_color = Color8(52, 38, 30)  # snout and hooves
		_add_tusks(r)
		for b in PIG_LEGS:
			var i := r.skeleton.find_bone(b)
			_bones.append(i)
			_rests.append(r.skeleton.get_bone_rest(i).basis.get_rotation_quaternion())
		_use_rig(r)
		rig.tick(randf() * 3.0)
		return
	_box(model, Vector3(0.66, 0.55, 1.05), Vector3(0, 0.62, 0), fur)
	_box(model, Vector3(0.5, 0.12, 0.8), Vector3(0, 0.95, -0.05), fur.darkened(0.25))
	_box(model, Vector3(0.44, 0.42, 0.4), Vector3(0, 0.7, 0.68), fur.lightened(0.05))
	_box(model, Vector3(0.24, 0.17, 0.08), Vector3(0, 0.62, 0.9), Color8(176, 120, 110))
	_box(model, Vector3(0.05, 0.12, 0.05), Vector3(-0.15, 0.56, 0.88), Color8(235, 230, 210))
	_box(model, Vector3(0.05, 0.12, 0.05), Vector3(0.15, 0.56, 0.88), Color8(235, 230, 210))
	_box(model, Vector3(0.06, 0.06, 0.02), Vector3(-0.12, 0.8, 0.885), Color8(20, 20, 20))
	_box(model, Vector3(0.06, 0.06, 0.02), Vector3(0.12, 0.8, 0.885), Color8(20, 20, 20))
	_box(model, Vector3(0.1, 0.14, 0.06), Vector3(-0.17, 0.95, 0.6), fur.darkened(0.2))
	_box(model, Vector3(0.1, 0.14, 0.06), Vector3(0.17, 0.95, 0.6), fur.darkened(0.2))
	for p in [Vector3(-0.2, 0.36, 0.33), Vector3(0.2, 0.36, 0.33), Vector3(-0.2, 0.36, -0.33), Vector3(0.2, 0.36, -0.33)]:
		var pv := _pivot(model, p)
		_box(pv, Vector3(0.16, 0.36, 0.16), Vector3(0, -0.18, 0), fur.darkened(0.15))
		legs.append(pv)


## Two tusks by the snout, following the head as it moves.
func _add_tusks(r: Rig) -> void:
	var frame := r.attach("Head")
	var ivory := StandardMaterial3D.new()
	ivory.albedo_color = Color8(236, 228, 204)
	ivory.roughness = 0.6
	for side in [-1.0, 1.0]:
		var t := MeshInstance3D.new()
		t.mesh = RoundBox.mesh(Vector3(0.28, 1.0, 0.28))
		t.material_override = ivory
		frame.add_child(t)
		t.position = Vector3(side * 0.5, 1.85, 4.15)
		t.rotation = Vector3(-0.45, 0.0, side * -0.35)


## Dying (client view): a boar falls over onto its side.
func _death_tilt() -> Vector3:
	return Vector3(0.0, 0.0, PI * 0.5 * (1.0 if net_id % 2 == 0 else -1.0))


func _death_lift() -> float:
	return 0.3


func _physics_process(delta: float) -> void:
	if dead or not G.world.is_ready_at(global_position):
		return
	_tick_flash(delta)
	var dir := Vector3.ZERO
	var spd := 1.3
	if flee_t > 0.0:
		flee_t -= delta
		var away: Vector3 = global_position - last_from
		away.y = 0.0
		dir = away.normalized()
		spd = 5.2
	else:
		wander_t -= delta
		if wander_t <= 0.0:
			wander_t = randf_range(2.0, 7.0)
			wander_dir = Vector3.ZERO if randf() < 0.45 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		dir = wander_dir
	if walk(dir, spd, delta) and flee_t <= 0.0:
		wander_t = 0.0
	if not G.server_mode:
		var rv := get_real_velocity()
		_pose(Vector2(rv.x, rv.z).length(), delta)


func _pose(spd: float, delta: float) -> void:
	if rig != null:
		if spd < 0.15:
			rig.move("Armature|Idle")
			rig.tick(delta)
			return
		# Walking: the idle animation waits (it would hold the legs still) and the legs swing.
		rig.current = ""
		var a := sin(anim * 1.4) * 0.5 * minf(1.0, spd)
		for i in _bones.size():
			var s := 1.0 if i < 2 else -1.0
			rig.skeleton.set_bone_pose_rotation(_bones[i], _rests[i] * Quaternion(Vector3.RIGHT, a * s))
		return
	var mv := minf(1.0, spd)
	for i in legs.size():
		var s := 1.0 if i == 0 or i == 3 else -1.0
		legs[i].rotation.x = sin(anim * 1.4) * 0.6 * mv * s


func _view_animate(delta: float, spd: float, _rising: int) -> void:
	_pose(spd, delta)


func _on_hurt(_attacker: Node) -> void:
	flee_t = 5.0
	if not G.server_mode:
		G.sfx.play_at("squeal", global_position + Vector3(0, 0.7, 0), -4.0)


func _on_death(attacker: Node) -> void:
	if attacker != null and attacker.has_method("give"):
		attacker.give(Items.RAW_MEAT, 2 + (1 if randf() < 0.5 else 0))
		attacker.give(Items.BOAR_HIDE, 1 + (1 if randf() < 0.5 else 0))  # (leather armor, M4.5)
	if attacker != null and attacker.has_method("add_xp"):
		attacker.add_xp(Skills.BOAR_XP)
