class_name Mob
extends CharacterBody3D
## Shared creature logic: models (downloaded and animated, `rig`, or boxes with rounded edges),
## walking, hopping up ledges, taking hits.

const GRAVITY := 26.0

var hp := 20.0
var max_hp := 20.0
var knock := Vector3.ZERO
var flash := 0.0
var dead := false
var anim := 0.0
var mats: Array[StandardMaterial3D] = []
var base_cols: Array[Color] = []
var model: Node3D
## The downloaded animated model (client only), or null with the box model.
var rig: Rig
var height := 1.8
var half := 0.3
## Cells of height the body needs: a crawler 1, most 2, a brute 3.
var tall := 2
## Online: the id clients know this mob by (S_MOBS).
var net_id := 0
## Client online: only a picture of a mob the server runs, moved by its snapshots.
var view := false
## Where the last hit came from (animals run away from it).
var last_from := Vector3.ZERO
var _view_last := Vector3.INF
var _view_flags := 0
var _dying := false
## Client view: the drawn (rounded) ground's height under it, relative to where the server says
## its feet are; game.gd measures it, the model eases to it so it stands on what the player sees.
var ground_target := 0.0
var ground_off := 0.0
var snap_y := INF
## Client view: seconds since it died (-1 while alive). It topples over, lies still, then sinks
## into the ground and is gone; it finishes even after the server has dropped it (game.gd).
var die_t := -1.0
var _fall := Vector3.ZERO
const FALL_S := 0.55
const LIE_S := 2.4
const SINK_S := 1.3


func _setup_body(w: float, h: float) -> void:
	collision_layer = 2
	collision_mask = 1
	height = h
	half = w * 0.5
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, h, w)
	cs.shape = bs
	cs.position = Vector3(0, h * 0.5, 0)
	add_child(cs)
	model = Node3D.new()
	add_child(model)
	add_to_group("mobs")


## Put the downloaded model in (its materials join the hit flash). False if it isn't there.
func _use_rig(r: Rig) -> bool:
	if r == null:
		return false
	rig = r
	model.add_child(r)
	for m in r.mats:
		mats.append(m)
		base_cols.append(m.albedo_color)
	return true


func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color, glow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = RoundBox.mesh(size)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	m.metallic_specular = 0.1
	if glow:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 2.0
	mi.material_override = m
	mats.append(m)
	base_cols.append(col)
	parent.add_child(mi)
	mi.position = pos
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	parent.add_child(p)
	p.position = pos
	return p


func feet_cell() -> Vector3i:
	return Vector3i(floori(global_position.x), floori(global_position.y + 0.05), floori(global_position.z))


## Walk in dir at spd. Returns true if something solid is blocking the way.
func walk(dir: Vector3, spd: float, delta: float) -> bool:
	velocity.x = dir.x * spd + knock.x
	velocity.z = dir.z * spd + knock.z
	knock = knock.move_toward(Vector3.ZERO, 14.0 * delta)
	if not is_on_floor():
		velocity.y = maxf(velocity.y - GRAVITY * delta, -50.0)
	var want := Vector2(dir.x, dir.z).length() * spd
	move_and_slide()
	if dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), minf(1.0, 10.0 * delta))
	var rv := get_real_velocity()
	var real_h := Vector2(rv.x, rv.z).length()
	anim += delta * real_h * 3.2
	if dir.length() < 0.1 or not is_on_floor():
		return false
	if real_h >= want * 0.4:
		return false
	# Blocked: hop up a single block if there is head room
	var f := feet_cell()
	var ahead := global_position + dir * (half + 0.45)
	var fp := Vector3i(floori(ahead.x), f.y, floori(ahead.z))
	var w = G.world
	if Blocks.is_solid(w.get_blockv(fp)) and not Blocks.is_solid(w.get_blockv(f + Vector3i(0, tall, 0))):
		var room := true
		for k in range(1, tall + 1):
			if Blocks.is_solid(w.get_blockv(fp + Vector3i(0, k, 0))):
				room = false
		if room:
			velocity.y = 8.2
			return false
	return true


## The block in the way: the highest solid cell the body needs in front of it. Failing that, a
## thin block the body is pressed against inside its own cells (a door or hatch closed across
## the far side of the cell the mob has walked into).
func blocking_cell(dir: Vector3) -> Vector3i:
	var f := feet_cell()
	var ahead := global_position + dir * (half + 0.45)
	var fp := Vector3i(floori(ahead.x), f.y, floori(ahead.z))
	var w = G.world
	for k in range(tall - 1, -1, -1):
		if Blocks.is_solid(w.get_blockv(fp + Vector3i(0, k, 0))):
			return fp + Vector3i(0, k, 0)
	var near := global_position + dir * (half + 0.05)
	var np := Vector3i(floori(near.x), f.y, floori(near.z))
	for k in range(tall - 1, -1, -1):
		var c := np + Vector3i(0, k, 0)
		var id: int = w.get_blockv(c)
		if Blocks.is_solid(id) and _shape_at(c, id, w.block_meta(c), near):
			return c
	return Vector3i(0, -999, 0)


## One of the cell's boxes is where the body pushes at `at` (not just a slab under its feet).
func _shape_at(c: Vector3i, id: int, meta: int, at: Vector3) -> bool:
	var feet := global_position.y + 0.05
	for b in Blocks.boxes_of(id, meta):
		var lo: Vector3 = Vector3(c) + b[0]
		var hi: Vector3 = Vector3(c) + b[1]
		if hi.y > feet and lo.y < feet + tall and at.x > lo.x - 0.1 and at.x < hi.x + 0.1 and at.z > lo.z - 0.1 and at.z < hi.z + 0.1:
			return true
	return false


func _tick_flash(delta: float) -> void:
	if flash <= 0.0:
		return
	flash = maxf(0.0, flash - delta * 4.0)
	for i in mats.size():
		mats[i].albedo_color = base_cols[i].lerp(Color(1, 0.15, 0.15), flash)


func hurt(dmg: float, from: Vector3, attacker: Node = null) -> void:
	if dead:
		return
	hp -= dmg
	flash = 1.0
	last_from = from
	if from != Vector3.ZERO:
		var k := global_position - from
		k.y = 0.0
		if k.length() > 0.01:
			knock = k.normalized() * 6.0
		velocity.y = 3.5
	_on_hurt(attacker)
	if hp <= 0.0:
		dead = true
		collision_layer = 0
		_on_death(attacker)
		var tw := create_tween()
		tw.tween_property(model, "rotation:x", -PI * 0.5, 0.35)
		tw.tween_interval(0.6)
		tw.tween_callback(queue_free)


func _on_hurt(_attacker: Node) -> void:
	pass


## Can an arrow, bolt or thrown spear hit it (M4.3)? Living creatures; not acid or projectiles.
func shootable() -> bool:
	return not dead and die_t < 0.0


## S_MOBS: the net id of the player it belongs to (a projectile's shooter), else 0.
func net_owner() -> int:
	return 0


## S_MOBS: what kind of mob this is (Proto.MOB_*).
func net_kind() -> int:
	return Proto.MOB_BOAR


func net_flags() -> int:
	var f := 0
	if flash > 0.3:
		f |= Proto.MF_HURT
	if dead:
		f |= Proto.MF_DEAD
	return f


## Client online: show the mob where the server says it is (called every frame, interpolated).
func view_update(pos: Vector3, yaw: float, flags: int, delta: float) -> void:
	if die_t >= 0.0:
		return  # lying where it fell
	var spd := 0.0
	if _view_last != Vector3.INF and delta > 0.0:
		spd = Vector2(pos.x - _view_last.x, pos.z - _view_last.z).length() / delta
	_view_last = pos
	global_position = pos
	rotation.y = yaw
	ground_off = move_toward(ground_off, ground_target, delta * 2.5)
	model.position.y = ground_off
	anim += delta * spd * 3.2
	var rising := flags & ~_view_flags
	_view_flags = flags
	if rising & Proto.MF_HURT:
		flash = 1.0
		_on_hurt(null)
	_tick_flash(delta)
	if flags & Proto.MF_DEAD:
		_start_death()
		return
	_view_animate(delta, spd, rising)


func _view_animate(_delta: float, _spd: float, _rising: int) -> void:
	pass


func _start_death() -> void:
	_dying = true
	die_t = 0.0
	collision_layer = 0
	_fall = _death_tilt()
	set_process(true)


## How the model ends up lying: most fall on their back, some on their face, a little turned.
func _death_tilt() -> Vector3:
	var r := (net_id * 2654435761) >> 7
	var x := -PI * 0.5 if r % 4 != 0 else PI * 0.5
	return Vector3(x, 0.0, (float(r % 7) - 3.0) * 0.08)


## How far the model rises as it tips over, so the body lies on the ground and not in it.
func _death_lift() -> float:
	return 0.18


## Limbs going limp while it falls (t: 0-1 through the fall), or the model's death animation.
func _death_pose(_t: float, delta: float) -> void:
	if rig != null:
		rig.tick(delta)


func _process(delta: float) -> void:
	if die_t < 0.0:
		set_process(false)
		return
	die_t += delta
	var t := clampf(die_t / FALL_S, 0.0, 1.0)
	var e := t * t  # speeding up as it goes over
	var bounce := 0.0
	if die_t > FALL_S and die_t < FALL_S + 0.3:
		bounce = sin((die_t - FALL_S) / 0.3 * PI) * 0.1
	model.rotation = Vector3(_fall.x * (e - bounce), model.rotation.y, _fall.z * e)
	var sink := maxf(0.0, die_t - FALL_S - LIE_S) / SINK_S
	model.position.y = ground_off + _death_lift() * e - sink * 0.9
	_death_pose(t, delta)
	_tick_flash(delta)
	if die_t > FALL_S + LIE_S + SINK_S:
		queue_free()


func _on_death(_attacker: Node) -> void:
	pass
