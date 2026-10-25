extends Mob
## An arrow, bolt or thrown spear (M4.3). On the server the Sim moves it each tick, like a
## Spitter's acid: it hurts the first zombie or animal on its way (twice as hard in the head) or
## stops in the first solid block, where a spear, and most arrows, stay for whoever picks them up
## (NetServer.add_ground). It has no collision body. Clients see it through S_MOBS
## (Proto.MOB_PROJ), turned the way it flies; whoever shot it sees their own copy at once
## (`local`: it flies by itself and stops where it hits; the server's copy is hidden for them).

const LIFE := 6.0
## Metres per second per second, and from its middle to its tip, by kind.
const FALL := {"arrow": 9.8, "bolt": 6.0, "spear": 9.8}
const HALF := {"arrow": 0.35, "bolt": 0.16, "spear": 0.95}

var item := Items.STONE_ARROW
var vel := Vector3.ZERO
var dmg := 10.0
## The ServerPlayer who shot it (server): the kill and its loot are theirs.
var shooter: Node = null
var life := LIFE
## The shooter's own picture (client), moving by itself.
var local := false
var _last := Vector3.INF
var _stop_t := -1.0
var _rng := RandomNumberGenerator.new()


static func kind_of(id: int) -> String:
	if Items.tool_type(id) == "spear":
		return "spear"
	return "bolt" if Items.info(id).get("ammo_of", "") == "bolt" else "arrow"


## How fast it leaves (m/s), by what it is and how hard it was shot or thrown (0..1).
static func speed(id: int, power: float) -> float:
	match kind_of(id):
		"bolt":
			return 62.0
		"spear":
			return 9.0 + 15.0 * power
	return 18.0 + 40.0 * power


static func damage(id: int, power: float) -> float:
	match kind_of(id):
		"spear":
			return float(Items.info(id).get("throw", 10.0)) * (0.4 + 0.6 * power)
		"bolt":
			return Items.damage(id)
	return Items.damage(id) * (0.3 + 0.7 * power)


func _ready() -> void:
	set_physics_process(local)
	_rng.seed = hash(net_id)
	if G.server_mode:
		return
	model = Node3D.new()
	add_child(model)
	var m := ToolModels.make_flying(item)
	if m != null:
		model.add_child(m)
	_face(vel)


func shootable() -> bool:
	return false


func net_kind() -> int:
	return Proto.MOB_PROJ


func net_flags() -> int:
	return maxi(0, Items.projectile_type(item)) & 63


func net_owner() -> int:
	return shooter.net_id if shooter != null and is_instance_valid(shooter) else 0


## One Sim step (server). Returns false once it has hit something or is too old.
func step(delta: float) -> bool:
	life -= delta
	if life <= 0.0:
		return false
	var from := global_position
	vel.y -= FALL[kind_of(item)] * delta
	var to := from + vel * delta
	var bh := _block_hit(from, to)
	var mh := _mob_hit(from, to if bh.is_empty() else bh[1])
	if not mh.is_empty():
		_hit_mob(mh[0], mh[1], from)
		return false
	if not bh.is_empty():
		_stick(bh[1])
		return false
	global_position = to
	_face(vel)
	return to.y > -8.0


## The shooter's own copy (client): fly until something stops it, as the server's does.
func _physics_process(delta: float) -> void:
	if _stop_t >= 0.0:
		_stop_t -= delta
		if _stop_t < 0.0:
			queue_free()
		return
	life -= delta
	var from := global_position
	vel.y -= FALL[kind_of(item)] * delta
	var to := from + vel * delta
	var bh := _block_hit(from, to)
	var mh := _mob_hit(from, to if bh.is_empty() else bh[1])
	if life <= 0.0 or not mh.is_empty():
		if not mh.is_empty():
			G.sfx.play_at("arrow", mh[1], -2.0)
		queue_free()
		return
	if not bh.is_empty():
		global_position = _rest_point(bh[1])
		_stop_t = 0.7  # the server's copy (if it didn't break) lies there from now on
		G.sfx.play_at("arrow", bh[1], -2.0)
		return
	global_position = to
	_face(vel)


## A client's picture of the server's projectile (not your own: that one is hidden).
func view_update(pos: Vector3, _yaw: float, flags: int, _delta: float) -> void:
	if _last != Vector3.INF and pos.distance_to(_last) > 0.001:
		_face(pos - _last)
	_last = pos
	global_position = pos
	visible = (flags & Proto.MF_YOURS) == 0


func _face(dir: Vector3) -> void:
	if dir.length() < 0.001:
		return
	var d := dir.normalized()
	basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT)


## The first solid block between a and b: [part of the way, the last point before it], or [].
func _block_hit(a: Vector3, b: Vector3) -> Array:
	var n := maxi(1, ceili(a.distance_to(b) / 0.12))
	var w = G.world
	if Blocks.is_solid(w.get_block(floori(a.x), floori(a.y), floori(a.z))):
		return [0.0, a]
	for k in range(1, n + 1):
		var p := a.lerp(b, float(k) / n)
		if Blocks.is_solid(w.get_block(floori(p.x), floori(p.y), floori(p.z))):
			return [float(k - 1) / n, a.lerp(b, float(k - 1) / n)]
	return []


## The first zombie or animal the path from a to b passes through: [mob, the point], or [].
func _mob_hit(a: Vector3, b: Vector3) -> Array:
	var best := []
	var best_d := INF
	var wide := 0.18 if kind_of(item) == "spear" else 0.1
	var mid := (a + b) * 0.5
	var reach := a.distance_to(b) * 0.5 + 3.0
	for m in get_parent().get_children():
		if not (m is Mob) or m == self or not m.shootable():
			continue
		var feet: Vector3 = m.global_position
		if feet.distance_to(mid) > reach:
			continue
		var c := Geometry3D.get_closest_points_between_segments(a, b, feet + Vector3(0, 0.05, 0), feet + Vector3(0, m.height, 0))
		if c[0].distance_to(c[1]) < m.half + wide:
			var d := a.distance_to(c[0])
			if d < best_d:
				best_d = d
				best = [m, c[0]]
	return best


func _hit_mob(m: Node, at: Vector3, from: Vector3) -> void:
	var head: bool = m.height > 1.2 and at.y > m.global_position.y + m.height * 0.8
	var who = shooter if shooter != null and is_instance_valid(shooter) else null
	m.hurt(dmg * (2.0 if head else 1.0), from, who)
	if G.net_server == null:
		return
	if who != null:
		G.net_server.shot_hit(who, Proto.HIT_KILL if m.dead else (Proto.HIT_HEAD if head else Proto.HIT_MOB))
	if kind_of(item) == "spear":
		# The spear falls at its feet.
		var feet: Vector3 = m.global_position
		var flat := Vector3(vel.x, 0.0, vel.z)
		G.net_server.add_ground(item, Vector3(feet.x, floorf(feet.y) + 0.06, feet.z), flat if flat.length() > 0.01 else Vector3.FORWARD)


func _stick(at: Vector3) -> void:
	# A spear always stays; an arrow or bolt breaks two times in five.
	if G.net_server != null and (kind_of(item) == "spear" or _rng.randf() < 0.6):
		G.net_server.add_ground(item, _rest_point(at), vel)


## Where its middle rests when its tip has gone a little into the block beyond `at`.
func _rest_point(at: Vector3) -> Vector3:
	var d := vel.normalized()
	return at + d * 0.08 - d * (HALF[kind_of(item)] - 0.06)
