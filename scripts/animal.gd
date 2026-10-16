extends Mob
## Wild boar. Wanders, runs when hurt, drops raw meat.

var wander_dir := Vector3.ZERO
var wander_t := 0.0
var flee_t := 0.0
var legs: Array[Node3D] = []


func _ready() -> void:
	hp = 20.0
	max_hp = 20.0
	add_to_group("animals")
	_setup_body(0.8, 0.9)
	var fur := Color8(112, 74, 52).lerp(Color8(84, 60, 44), randf())
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


func _physics_process(delta: float) -> void:
	if dead or not G.world.is_ready_at(global_position):
		return
	_tick_flash(delta)
	var dir := Vector3.ZERO
	var spd := 1.3
	if flee_t > 0.0:
		flee_t -= delta
		var away: Vector3 = global_position - G.player.global_position
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
	var rv := get_real_velocity()
	var mv := minf(1.0, Vector2(rv.x, rv.z).length())
	for i in legs.size():
		var s := 1.0 if i == 0 or i == 3 else -1.0
		legs[i].rotation.x = sin(anim * 1.4) * 0.6 * mv * s


func _on_hurt(_attacker: Node) -> void:
	flee_t = 5.0
	G.sfx.play_at("squeal", global_position + Vector3(0, 0.7, 0), -4.0)


func _on_death(attacker: Node) -> void:
	if attacker == G.player:
		G.player.give(Items.RAW_MEAT, 2 + (1 if randf() < 0.5 else 0))
