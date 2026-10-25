extends Mob
## A Spitter's acid glob (M3). The Sim moves it in an arc each tick, in the order globs were spat:
## it hurts the first player it reaches, or eats into the first solid block it hits (queued like
## any zombie's block damage), and is gone after LIFE seconds. It has no collision body; clients
## see it through S_MOBS (Proto.MOB_ACID) as a small glowing blob.

const ACID_GRAVITY := 9.0
const SPEED := 13.0        # horizontal metres per second
const LIFE := 3.0

var vel := Vector3.ZERO
var dmg := 12.0
var block_dmg := 25.0
## The Spitter's id: block damage is queued under it, so the order stays the same every run.
var owner_id := 0
var life := LIFE


## The velocity that lands a glob thrown from `from` on `aim`.
static func launch_velocity(from: Vector3, aim: Vector3) -> Vector3:
	var flat := Vector2(aim.x - from.x, aim.z - from.z)
	var t := maxf(0.05, flat.length() / SPEED)
	return Vector3(flat.x / t, (aim.y - from.y + 0.5 * ACID_GRAVITY * t * t) / t, flat.y / t)


func _ready() -> void:
	set_physics_process(false)
	if G.server_mode:
		return
	model = Node3D.new()
	add_child(model)
	_box(model, Vector3(0.22, 0.22, 0.22), Vector3.ZERO, Color8(140, 230, 40), true)
	_box(model, Vector3(0.12, 0.12, 0.3), Vector3(0, 0, -0.16), Color8(110, 200, 30), true)


## One Sim step. Returns false once the glob is used up (hit something, or too old).
func step(delta: float, players: Array) -> bool:
	life -= delta
	if life <= 0.0:
		return false
	var from := global_position
	vel.y -= ACID_GRAVITY * delta
	var to := from + vel * delta
	global_position = to
	if vel.length() > 0.01:
		rotation.y = atan2(vel.x, vel.z)
	for p in players:
		if is_instance_valid(p) and not p.dead and _near_body(to, p.global_position):
			p.take_damage(dmg, from)
			return false
	var c := Vector3i(floori(to.x), floori(to.y), floori(to.z))
	if Blocks.is_solid(G.world.get_blockv(c)):
		G.sim.queue_block_damage(c, block_dmg, owner_id)
		return false
	return to.y > 0.0


## Within 0.55 m of a player's body (feet to head).
static func _near_body(p: Vector3, feet: Vector3) -> bool:
	var y := clampf(p.y, feet.y, feet.y + 1.8)
	return p.distance_to(Vector3(feet.x, y, feet.z)) < 0.55


func shootable() -> bool:
	return false


func net_kind() -> int:
	return Proto.MOB_ACID


func net_flags() -> int:
	return 0


func view_update(pos: Vector3, yaw: float, _flags: int, _delta: float) -> void:
	global_position = pos
	rotation.y = yaw
