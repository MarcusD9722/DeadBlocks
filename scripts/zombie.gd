extends Mob
## Chases the nearest player in its region, hops ledges and smashes through whatever is in the way.
## The Sim node ticks every zombie (sim_tick) in a fixed order; zombies have no _physics_process.

var speed := 2.4
var chase_range := 30.0
var player_dmg := 8.0
var block_dmg := 10.0
var blood := false
var attack_cd := 0.0
var block_cd := 0.0
var stuck_t := 0.0
var groan_t := 0.0
var wander_dir := Vector3.ZERO
var wander_t := 0.0
var attack_anim := 0.0
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var voice: AudioStreamPlayer3D

## Set by Sim: processing order, region membership, and this zombie's own random numbers
## (so its choices don't depend on the order zombies are processed in).
var id := 0
var region = null
var rng := RandomNumberGenerator.new()


func setup(kind: String, day: int) -> void:
	match kind:
		"day":
			speed = 1.7
			chase_range = 16.0
		"night":
			speed = 2.6 + minf(day * 0.05, 0.6)
			chase_range = 34.0
		"horde":
			speed = 3.5
			chase_range = 400.0
			hp = 40.0
			player_dmg = 11.0
			block_dmg = 14.0
			blood = true
	max_hp = hp


func _ready() -> void:
	set_physics_process(false)
	if not blood:
		hp = 30.0
		max_hp = 30.0
	add_to_group("zombies")
	_setup_body(0.6, 1.9)
	groan_t = rng.randf_range(1.0, 7.0)
	if G.server_mode:
		return
	_build_model()
	voice = AudioStreamPlayer3D.new()
	voice.stream = G.sfx.streams["groan"]
	voice.max_distance = 34.0
	voice.unit_size = 5.0
	voice.volume_db = -2.0
	add_child(voice)
	voice.position.y = 1.6


func _build_model() -> void:
	var skin := Color8(120, 158, 86).lerp(Color8(96, 128, 74), randf())
	if blood:
		skin = Color8(110, 124, 80)
	var shirts := [Color8(104, 94, 122), Color8(88, 104, 120), Color8(120, 82, 70), Color8(70, 92, 70), Color8(130, 120, 96)]
	var shirt: Color = shirts[randi() % shirts.size()]
	var pants := Color8(78, 74, 62)
	var eye := Color8(255, 40, 30) if blood else Color8(226, 226, 82)
	_box(model, Vector3(0.5, 0.5, 0.5), Vector3(0, 1.62, 0), skin)
	_box(model, Vector3(0.11, 0.07, 0.02), Vector3(-0.12, 1.67, 0.255), eye, true)
	_box(model, Vector3(0.11, 0.07, 0.02), Vector3(0.12, 1.67, 0.255), eye, true)
	_box(model, Vector3(0.22, 0.05, 0.02), Vector3(0, 1.48, 0.255), Color8(40, 20, 20))
	_box(model, Vector3(0.5, 0.72, 0.28), Vector3(0, 1.01, 0), shirt)
	_box(model, Vector3(0.18, 0.14, 0.02), Vector3(0.08, 1.1, 0.145), Color8(110, 30, 30))
	leg_l = _pivot(model, Vector3(-0.125, 0.65, 0))
	leg_r = _pivot(model, Vector3(0.125, 0.65, 0))
	_box(leg_l, Vector3(0.24, 0.65, 0.26), Vector3(0, -0.325, 0), pants)
	_box(leg_r, Vector3(0.24, 0.65, 0.26), Vector3(0, -0.325, 0), pants)
	arm_l = _pivot(model, Vector3(-0.37, 1.3, 0))
	arm_r = _pivot(model, Vector3(0.37, 1.3, 0))
	_box(arm_l, Vector3(0.22, 0.7, 0.22), Vector3(0, -0.33, 0), skin)
	_box(arm_r, Vector3(0.22, 0.7, 0.22), Vector3(0, -0.33, 0), skin)
	if blood:
		model.scale = Vector3.ONE * 1.06


## The nearest living player in this zombie's region, or null.
func _target():
	if region == null:
		return null
	var best = null
	var bd := INF
	for p in region.players:
		if not is_instance_valid(p) or p.dead:
			continue
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length_squared()
		if d < bd:
			bd = d
			best = p
	return best


func sim_tick(delta: float) -> void:
	if not G.world.is_ready_at(global_position):
		return
	attack_cd -= delta
	block_cd -= delta
	groan_t -= delta
	if not G.server_mode:
		_tick_flash(delta)
	var pl = _target()
	var to := Vector3.ZERO
	var hd := INF
	if pl != null:
		to = pl.global_position - global_position
		hd = Vector2(to.x, to.z).length()
	var chasing: bool = pl != null and hd < chase_range
	var dir := Vector3.ZERO
	if chasing:
		if hd > 0.85:
			dir = Vector3(to.x, 0, to.z) / hd
	else:
		wander_t -= delta
		if wander_t <= 0.0:
			wander_t = rng.randf_range(2.0, 6.0)
			wander_dir = Vector3.ZERO if rng.randf() < 0.35 else Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU)
		dir = wander_dir
	if chasing:
		dir += _spacing()
		if dir.length() > 1.0:
			dir = dir.normalized()
	var cell := feet_cell()
	var in_spikes: bool = G.world.get_blockv(cell) == Blocks.SPIKES
	var spd := speed * (0.35 if in_spikes else 1.0) * (1.0 if chasing else 0.45)
	var blocked := walk(dir, spd, delta)
	if blocked and chasing:
		stuck_t += delta
		if stuck_t > 0.35 and block_cd <= 0.0:
			var bc := blocking_cell(dir)
			if bc.y > -900:
				G.sim.queue_block_damage(bc, block_dmg, id)
				block_cd = 1.0
				attack_anim = 1.0
				if not G.server_mode:
					G.sfx.play_at("thud", Vector3(bc) + Vector3(0.5, 0.5, 0.5), -2.0)
	else:
		stuck_t = 0.0
	# Hit the player when close and nothing solid in between
	if chasing and hd < 1.45 and absf(to.y) < 1.9 and attack_cd <= 0.0:
		var mid: Vector3 = (global_position + pl.global_position) * 0.5 + Vector3(0, 1.5, 0)
		if not Blocks.is_solid(G.world.get_block(floori(mid.x), floori(mid.y), floori(mid.z))):
			pl.take_damage(player_dmg, global_position)
			attack_cd = 1.1
			attack_anim = 1.0
	if in_spikes:
		hp -= 7.0 * delta
		flash = maxf(flash, 0.35)
		G.sim.queue_block_damage(cell, 3.0 * delta, id)
		if hp <= 0.0:
			hurt(0.0, Vector3.ZERO, null)
	if G.server_mode:
		return
	if groan_t <= 0.0:
		groan_t = rng.randf_range(5.0, 12.0)
		voice.pitch_scale = rng.randf_range(0.8, 1.15) * (0.85 if blood else 1.0)
		voice.play()
	_animate(delta)


## Push away from zombies closer than 0.8 m, using where everyone stood at the start of this tick.
func _spacing() -> Vector3:
	var push := Vector3.ZERO
	if region == null:
		return push
	var me := global_position
	var cx := floori(me.x)
	var cz := floori(me.z)
	for gz in range(cz - 1, cz + 2):
		for gx in range(cx - 1, cx + 2):
			var cell = region.grid.get(Vector2i(gx, gz))
			if cell == null:
				continue
			for e in cell:
				if e[0] == id:
					continue
				var d: Vector3 = me - e[1]
				d.y = 0.0
				var l := d.length()
				if l < 0.8 and l > 0.001:
					push += d / l * (0.8 - l)
	return push


func _animate(delta: float) -> void:
	var rv := get_real_velocity()
	var mv := minf(1.0, Vector2(rv.x, rv.z).length())
	leg_l.rotation.x = sin(anim) * 0.7 * mv
	leg_r.rotation.x = -sin(anim) * 0.7 * mv
	attack_anim = maxf(0.0, attack_anim - delta * 3.0)
	var lift := sin(attack_anim * PI) * 0.9
	arm_l.rotation.x = -PI * 0.47 + sin(anim * 0.5) * 0.12 - lift
	arm_r.rotation.x = -PI * 0.47 - sin(anim * 0.5) * 0.12 - lift


func _on_hurt(_attacker: Node) -> void:
	if not G.server_mode:
		G.sfx.play_at("zhurt", global_position + Vector3(0, 1.5, 0), -3.0)


func _on_death(attacker: Node) -> void:
	G.game.kills += 1
	if attacker == G.player and randf() < 0.6:
		G.player.give(Items.FIBER, randi_range(1, 2))
