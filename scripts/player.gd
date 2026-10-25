extends CharacterBody3D
## First-person survivor: movement, mining, building, combat, hunger, stamina.

const WALK := 4.4
const SPRINT := 6.9
const JUMP_V := 8.3
const GRAVITY := 26.0
const REACH := 5.0
const MOB_REACH := 3.2

var head: Node3D
var cam: Camera3D
var flashlight: SpotLight3D
var held: MeshInstance3D
var held_mat: StandardMaterial3D
var outline: MeshInstance3D
var mine_crack: MeshInstance3D
var sens := 0.0025
## Controller: look speed (radians a second at full tilt) and inverted up/down (Settings).
var stick_sens := 3.0
var invert_y := false
## Controller: clicking the left stick sprints until we stop going forward.
var sprint_latch := false
var _use_was := false
var _attack_was := false

var max_health := 100.0
var health := 100.0
var food := 100.0
var stamina := 100.0
var dead := false
var hurt_flash := 0.0
var inv: Inventory
var selected := 0
var target := {}
var mob_target: Node = null
var mine_pos := Vector3i(0, -999, 0)
var mine_progress := 0.0
var dig_snd := 0.0
var attack_cd := 0.0
var swing := 0.0
var air_min_vy := 0.0
var spawn_point := Vector3.ZERO
var sprinting := false
var held_id := -1
var hints := {}
var stuck_t := 0.0
## The camera's lag behind a step up a ledge (eases back to 0, so a step feels like a slope).
var step_cam := 0.0
const HEAD_Y := 1.62


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	floor_max_angle = deg_to_rad(50)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.6, 1.8, 0.6)
	cs.shape = bs
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)

	head = Node3D.new()
	head.position = Vector3(0, HEAD_Y, 0)
	add_child(head)
	cam = Camera3D.new()
	cam.fov = 75
	cam.near = 0.05
	cam.far = 400
	head.add_child(cam)
	cam.current = true

	flashlight = SpotLight3D.new()
	flashlight.spot_range = 30
	flashlight.spot_angle = 27
	flashlight.light_energy = 2.4
	flashlight.light_color = Color(1.0, 0.95, 0.85)
	flashlight.spot_attenuation = 0.8
	flashlight.position = Vector3(0.2, -0.15, 0)
	flashlight.visible = false
	cam.add_child(flashlight)

	held = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.2, 0.2)
	held.mesh = q
	held_mat = StandardMaterial3D.new()
	held_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	held_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	held_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	held_mat.no_depth_test = true
	held_mat.render_priority = 10
	held_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	held.material_override = held_mat
	held.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	held.position = Vector3(0.3, -0.24, -0.5)
	cam.add_child(held)

	outline = MeshInstance3D.new()
	outline.mesh = _wire_cube(0.503)
	var om := StandardMaterial3D.new()
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.albedo_color = Color(0.05, 0.05, 0.05, 0.75)
	om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline.material_override = om
	outline.top_level = true
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(outline)

	mine_crack = MeshInstance3D.new()
	mine_crack.top_level = true
	mine_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mine_crack.visible = false
	add_child(mine_crack)

	inv = Inventory.new()
	if G.gfx != null:
		sens = G.gfx.sens * 0.001
		flashlight.shadow_enabled = G.gfx.opt["shadows"] >= 1
		cam.fov = G.gfx.opt["fov"]


func _wire_cube(h: float) -> ImmediateMesh:
	var m := ImmediateMesh.new()
	var c := []
	for i in 8:
		c.append(Vector3(h if i & 1 else -h, h if i & 2 else -h, h if i & 4 else -h))
	var edges := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	for e in edges:
		m.surface_add_vertex(c[e[0]])
		m.surface_add_vertex(c[e[1]])
	m.surface_end()
	return m


func cur_id() -> int:
	return inv.id_at(selected)


func set_look(yaw: float, pitch: float) -> void:
	head.rotation.y = yaw
	cam.rotation.x = pitch


func look_at_mob(m: Node3D) -> void:
	var d := m.global_position + Vector3(0, 0.5, 0) - cam.global_position
	head.rotation.y = atan2(-d.x, -d.z)
	cam.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func select(i: int) -> void:
	selected = clampi(i, 0, 8)
	mine_progress = 0.0


# ------------------------------------------------------------ input

## Keys and buttons (controls.gd); placing and hitting are read in _process, so the controller's
## triggers work like mouse buttons.
func _unhandled_input(event: InputEvent) -> void:
	if dead or G.game.state != "playing":
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		head.rotation.y -= event.relative.x * sens
		cam.rotation.x = clampf(cam.rotation.x - event.relative.y * sens, -1.55, 1.55)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		select(event.keycode - KEY_1)
	elif event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
		G.sfx.play("click", -6.0)
	elif event.is_action_pressed("hotbar_prev"):
		select((selected + 8) % 9)
	elif event.is_action_pressed("hotbar_next"):
		select((selected + 1) % 9)
	elif event is InputEventJoypadButton and event.is_action_pressed("sprint"):
		sprint_latch = true


# ------------------------------------------------------------ movement

func _physics_process(delta: float) -> void:
	var st: String = G.game.state
	if dead or st == "loading" or st == "title":
		return
	# Aim is updated here, not in _process: the mob ray needs the physics space, which is only
	# safe to query during the physics step when physics runs on its own thread.
	if st == "playing":
		_update_target()
	if not G.world.is_ready_at(global_position):
		velocity = Vector3.ZERO
		return
	var can_move := st == "playing"
	var input := Vector2.ZERO
	if can_move:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Basis(Vector3.UP, head.rotation.y) * Vector3(input.x, 0, input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	if input.y >= -0.1:
		sprint_latch = false
	sprinting = can_move and (Input.is_action_pressed("sprint") or sprint_latch) and input.y < -0.1 and stamina > 1.0
	var spd := SPRINT if sprinting else WALK
	var accel := 14.0 if is_on_floor() else 4.0
	var w := clampf(accel * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, dir.x * spd, w)
	velocity.z = lerpf(velocity.z, dir.z * spd, w)
	if not is_on_floor():
		velocity.y = maxf(velocity.y - GRAVITY * delta, -55.0)
	elif can_move and Input.is_action_pressed("jump"):
		velocity.y = JUMP_V
		stamina = maxf(0.0, stamina - 2.0)
	var pre_vy := velocity.y
	if can_move and input != Vector2.ZERO:
		_step_up(dir)
	move_and_slide()
	if not is_on_floor():
		air_min_vy = minf(air_min_vy, velocity.y)
	else:
		air_min_vy = minf(air_min_vy, pre_vy)
		if air_min_vy < -14.5:
			if G.mode == "client":
				G.net.report_fall((-air_min_vy - 14.5) * 4.0)  # health is the server's
			else:
				take_damage((-air_min_vy - 14.5) * 4.0, Vector3.ZERO)
		air_min_vy = 0.0
	_unstick(delta)
	if global_position.y < -20.0 and G.mode != "client":
		# Online the server sees this and it counts as a death (the respawn brings us back).
		global_position = spawn_point
		velocity = Vector3.ZERO


## Walking into a ledge one block high (or a bed) with room above it: step up onto it, as on
## the rounded ground it looks like a slope. Grid checks only, like the zombies' hops.
func _step_up(dir: Vector3) -> void:
	if not is_on_floor() or dir.length() < 0.1:
		return
	var w = G.world
	var p := global_position
	var fy := floori(p.y + 0.05)
	if p.y - fy > 0.08:
		return  # not standing on a block's top
	var ahead := p + dir.normalized() * 0.45
	var c := Vector3i(floori(ahead.x), fy, floori(ahead.z))
	if c.x == floori(p.x) and c.z == floori(p.z):
		return
	var id: int = w.get_blockv(c)
	if not Blocks.is_solid(id):
		return
	var top := 1.0
	if Blocks.SHAPE[id] == Blocks.SH_BOX:
		top = Blocks.BOX[id][1].y
	for dy in range(1, 3):
		if Blocks.is_solid(w.get_blockv(c + Vector3i(0, dy, 0))):
			return
	var own := Vector3i(floori(p.x), fy, floori(p.z))
	if Blocks.is_solid(w.get_blockv(own + Vector3i(0, 2, 0))):
		return  # no room above our head to rise
	var rise := fy + top + 0.01 - p.y
	global_position.y += rise
	step_cam -= rise


## Stuck inside solid blocks (a glitch, or the world changed around us) for half a second:
## climb out to the first space above with room to stand.
func _unstick(delta: float) -> void:
	var w = G.world
	var feet := Vector3i(floori(global_position.x), floori(global_position.y + 0.1), floori(global_position.z))
	if not (Blocks.is_solid(w.get_blockv(feet)) and Blocks.is_solid(w.get_blockv(feet + Vector3i.UP))):
		stuck_t = 0.0
		return
	stuck_t += delta
	if stuck_t < 0.5:
		return
	stuck_t = 0.0
	for dy in range(1, 64):
		var f := feet + Vector3i(0, dy, 0)
		if not Blocks.is_solid(w.get_blockv(f)) and not Blocks.is_solid(w.get_blockv(f + Vector3i.UP)):
			global_position.y = f.y + 0.02
			velocity = Vector3.ZERO
			return


# ------------------------------------------------------------ per-frame

func _process(delta: float) -> void:
	if dead:
		_update_held()  # the backpack took everything: an empty hand
		return
	var st: String = G.game.state
	attack_cd -= delta
	hurt_flash = maxf(0.0, hurt_flash - delta * 1.5)
	step_cam = move_toward(step_cam, 0.0, delta * maxf(5.0, absf(step_cam) * 9.0))
	head.position.y = HEAD_Y + step_cam
	swing = maxf(0.0, swing - delta * 4.0)
	if st == "playing" or st == "menu" or st == "chat" or (st == "paused" and G.mode == "client"):
		if sprinting:
			stamina = maxf(0.0, stamina - 16.0 * delta)
		else:
			stamina = minf(100.0, stamina + 20.0 * delta)
	if st == "playing":
		_stick_look(delta)
		_buttons()
		_handle_mining(delta)
	else:
		mine_progress = 0.0
		outline.visible = false
		_use_was = true  # (a button still held as a menu closes does nothing)
		_attack_was = true
	_update_crack()
	_update_held()


## Controller: the right stick looks around (gently near the middle, for aiming).
func _stick_look(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look == Vector2.ZERO:
		return
	look *= look.length()
	var k := stick_sens * delta
	head.rotation.y -= look.x * k
	cam.rotation.x = clampf(cam.rotation.x - look.y * k * (-1.0 if invert_y else 1.0), -1.55, 1.55)


## Place / use and hit, on the press of the button (a mouse button or a controller trigger).
func _buttons() -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var use_now := Input.is_action_pressed("use") and captured
	if use_now and not _use_was:
		use_item()
	_use_was = use_now
	var attack_now := Input.is_action_pressed("attack") and captured
	if attack_now and not _attack_was:
		swing = 1.0
	_attack_was = attack_now


func _update_target() -> void:
	var origin := cam.global_position
	var fwd := -cam.global_transform.basis.z
	target = G.world.raycast(origin, fwd, REACH)
	mob_target = null
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + fwd * MOB_REACH, 2)
	var r := space.intersect_ray(q)
	if not r.is_empty():
		var md := origin.distance_to(r["position"])
		if not target.get("hit", false) or float(target["dist"]) > md:
			mob_target = r["collider"]
	if target.get("hit", false):
		outline.visible = true
		outline.global_position = Vector3(target["pos"]) + Vector3(0.5, 0.5, 0.5)
	else:
		outline.visible = false


func _break_time(id: int) -> float:
	return Rules.break_time(id, cur_id())


func _handle_mining(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not Input.is_action_pressed("attack"):
		mine_progress = 0.0
		return
	if mob_target != null and is_instance_valid(mob_target):
		if attack_cd <= 0.0:
			attack(mob_target)
		mine_progress = 0.0
		return
	if not target.get("hit", false):
		mine_progress = 0.0
		return
	var p: Vector3i = target["pos"]
	if p != mine_pos:
		mine_pos = p
		mine_progress = 0.0
	var id: int = target["id"]
	if Items.tool_type(cur_id()) == "hammer":
		_hammer(p, delta)
		return
	var bt := _break_time(id)
	if bt < 0.0:
		return
	mine_progress += delta / bt
	dig_snd -= delta
	if dig_snd <= 0.0:
		dig_snd = 0.24
		G.sfx.play("dig", -8.0)
	if mine_progress >= 1.0:
		break_block(p, id)
		mine_progress = 0.0


## Holding the button with a hammer: work on the block (repair or upgrade, hammer_text), then
## ask the server, which does it if we have the materials.
func _hammer(p: Vector3i, delta: float) -> void:
	var ht := hammer_text()
	if not ht[1]:
		mine_progress = 0.0
		return
	mine_progress += delta / Items.hammer_time(cur_id())
	dig_snd -= delta
	if dig_snd <= 0.0:
		dig_snd = 0.35
		G.sfx.play("hit", -8.0)
		swing = 1.0
	if mine_progress >= 1.0:
		mine_progress = 0.0
		G.net.request_upgrade(p, selected)
		G.sfx.play("place", -4.0)


func attack(mob: Node) -> void:
	G.net.request_attack(mob.net_id, selected)  # the server checks reach and deals the damage
	attack_cd = 0.45
	swing = 1.0
	G.sfx.play("hit", -3.0)


func break_block(p: Vector3i, id: int) -> void:
	G.world.clear_block(p)  # (and a door's other half)
	G.sfx.play("break", -4.0)
	# The block is gone on our screen right away; the server decides what drops (or puts the
	# block back if someone else got there first).
	G.net.request_break(p, id, selected)
	if id == Blocks.LOG and not hints.has("log"):
		hints["log"] = true
		G.hud.msg("Press %s for your inventory and crafting. Make Planks, then a Workbench." % Controls.key_name(Controls.key_of("inventory")), Color(0.7, 1, 0.7))


## The block state for placing `id` where we look: doors, hatches and ramps face our way; a half
## block or hatch goes in the top of its cell when placed against a ceiling or the upper half of
## a side.
func place_meta(id: int) -> int:
	var fwd := -cam.global_transform.basis.z
	var meta := 0
	if Blocks.has_facing(id):
		meta |= Blocks.facing_of(Vector3(fwd.x, 0, fwd.z))
	if Blocks.SHAPE[id] == Blocks.SH_HALF or Blocks.SHAPE[id] == Blocks.SH_HATCH:
		var n: Vector3i = target.get("normal", Vector3i.UP)
		var hit_y: float = cam.global_position.y + fwd.y * float(target.get("dist", 0.0))
		if n == Vector3i.DOWN or (n.y == 0 and hit_y - floorf(hit_y) > 0.5):
			meta |= Blocks.META_UPPER
	return meta


## E (interact): open the station we look at, open or close a door or hatch, open a storage box
## or a bag.
func interact() -> void:
	if not target.get("hit", false):
		return
	var id: int = target["id"]
	var p: Vector3i = target["pos"]
	if Blocks.is_station(id):
		G.game.open_inventory(Blocks.STATIONS[id])
	elif Blocks.is_openable(id):
		# Shown at once (both halves of a door); the server confirms or undoes it.
		var to: int = Blocks.OPENS.get(id, Blocks.CLOSED.get(id, id))
		var q: Vector3i = G.world.door_partner(p)
		G.world.set_block(p, to, G.world.block_meta(p))
		if q != Vector3i.MIN:
			G.world.set_block(q, to, G.world.block_meta(q))
		G.net.request_use(p)
		G.sfx.play("place", -6.0)
	elif Blocks.is_container(id):
		G.game.open_box(p)


## What E would do on what we look at ("" for nothing), for the prompt by the crosshair.
func interact_text() -> String:
	if not target.get("hit", false):
		return ""
	var id: int = target["id"]
	if Blocks.is_station(id):
		return "Open " + Blocks.NAMES[id]
	if Blocks.OPENS.has(id):
		return "Open the " + Blocks.NAMES[id].to_lower()
	if Blocks.CLOSED.has(id):
		return "Close the " + Blocks.NAMES[Blocks.CLOSED[id]].to_lower()
	if id == Blocks.BACKPACK:
		return "Open the bag"
	if Blocks.is_container(id):
		return "Open the " + Blocks.NAMES[id].to_lower()
	return ""


## Holding a hammer and looking at a block: what it would do ("" when it can't), and whether we
## have what it costs.
func hammer_text() -> Array:
	if Items.tool_type(cur_id()) != "hammer" or not target.get("hit", false):
		return ["", false]
	var id: int = target["id"]
	var p: Vector3i = target["pos"]
	if G.world.damage_of(p) > 0.0 and Blocks.REPAIR.has(id):
		var c: Array = Blocks.REPAIR[id]
		return ["Repair: %d %s (have %d)" % [c[1], Items.name_of(c[0]), inv.count(c[0])], inv.count(c[0]) >= c[1]]
	if not Blocks.UPGRADE.has(id):
		return ["%s can't be upgraded" % Blocks.NAMES[id], false]
	var up: Array = Blocks.UPGRADE[id]
	var ok := true
	var parts := []
	for item in up[1]:
		parts.append("%d %s (have %d)" % [int(up[1][item]), Items.name_of(int(item)), inv.count(int(item))])
		ok = ok and inv.count(int(item)) >= int(up[1][item])
	return ["Upgrade to %s: %s" % [Blocks.NAMES[up[0]], ", ".join(parts)], ok]


func use_item() -> void:
	var cur := cur_id()
	if cur <= 0:
		return
	if Items.is_consumable(cur):
		consume(cur)
	elif Items.is_block(cur) and target.get("hit", false):
		place(cur)


func consume(id: int) -> void:
	var d := Items.info(id)
	var f := float(d.get("food", 0.0))
	var h := float(d.get("heal", 0.0))
	if f > 0.0 and food >= 99.0 and (h <= 0.0 or health >= max_health):
		G.hud.msg("You're full.")
		return
	if f <= 0.0 and h > 0.0 and health >= max_health:
		G.hud.msg("You're already at full health.")
		return
	G.net.request_eat(selected)  # the server answers with S_ATE -> ate()


func ate(id: int) -> void:
	var d := Items.info(id)
	food = minf(100.0, food + float(d.get("food", 0.0)))
	health = minf(max_health, health + float(d.get("heal", 0.0)))
	G.sfx.play("eat", -4.0)


func place(id: int) -> bool:
	var n: Vector3i = target["normal"]
	if n == Vector3i.ZERO:
		return false
	return try_place(target["pos"] + n, id)


## Place block `id` (from the selected slot) at p, if nothing is in the way. meta: its state
## (facing, upper half); -1 works it out from where we look.
func try_place(p: Vector3i, id: int, meta := -1) -> bool:
	if G.world.get_blockv(p) != Blocks.AIR or p.y < 1 or p.y >= 63:
		return false
	var door := Blocks.is_door(id)
	if door and (p.y >= 62 or G.world.get_blockv(p + Vector3i.UP) != Blocks.AIR):
		G.hud.msg("A door needs two blocks of room.")
		return false
	if meta < 0:
		meta = place_meta(id)
	if Blocks.SHAPE[id] == Blocks.SH_CROSS and not Blocks.is_solid(G.world.get_blockv(p + Vector3i.DOWN)):
		G.hud.msg("That needs solid ground under it.")
		return false
	if Blocks.SOLID[id]:
		var bmin := Vector3(p)
		var bmax := bmin + Vector3(1, 2 if door else 1, 1)
		if _overlap(global_position + Vector3(-0.3, 0, -0.3), global_position + Vector3(0.3, 1.8, 0.3), bmin, bmax):
			return false
		for m in get_tree().get_nodes_in_group("mobs"):
			var mp: Vector3 = m.global_position
			if _overlap(mp + Vector3(-0.4, 0, -0.4), mp + Vector3(0.4, 1.9, 0.4), bmin, bmax):
				return false
	G.world.set_block(p, id, meta)
	if door:
		G.world.set_block(p + Vector3i.UP, id, meta | Blocks.META_UPPER)
	G.net.request_place(p, id, selected, meta)  # shown now; the server confirms or undoes it
	G.sfx.play("place", -4.0)
	swing = 1.0
	if id == Blocks.WORKBENCH and not hints.has("bench"):
		hints["bench"] = true
		G.hud.msg("Look at the Workbench and press %s to craft tools." % Controls.key_name(Controls.key_of("interact")), Color(0.7, 1, 0.7))
	return true


func _overlap(amin: Vector3, amax: Vector3, bmin: Vector3, bmax: Vector3) -> bool:
	return amin.x < bmax.x and amax.x > bmin.x and amin.y < bmax.y and amax.y > bmin.y and amin.z < bmax.z and amax.z > bmin.z


func take_damage(amount: float, from: Vector3) -> void:
	if dead:
		return
	health -= amount
	hurt_flash = 1.0
	G.sfx.play("hurt", -2.0)
	if from != Vector3.ZERO:
		var k := global_position - from
		k.y = 0.0
		if k.length() > 0.01:
			velocity += k.normalized() * 5.0
		velocity.y = maxf(velocity.y, 3.0)
	if health <= 0.0:
		health = 0.0
		die()


## Online: health, food and kills as the server has them.
func apply_stats(hp: int, f: int, is_dead: bool, k: int) -> void:
	health = hp
	food = f
	G.game.kills = k
	if is_dead and not dead:
		health = 0.0
		die()
	elif not is_dead and dead:
		dead = false
		stamina = 100.0
		velocity = Vector3.ZERO
		air_min_vy = 0.0
		G.game.on_respawned()


## Online: the server says we were hit (from = Vector3.ZERO: no knockback).
func hurt_effect(amount: int, from: Vector3) -> void:
	hurt_flash = 1.0
	G.sfx.play("hurt", -2.0)
	if from != Vector3.ZERO:
		var k := global_position - from
		k.y = 0.0
		if k.length() > 0.01:
			velocity += k.normalized() * clampf(3.0 + amount * 0.35, 4.0, 10.0)  # a Brute knocks you far
		velocity.y = maxf(velocity.y, 3.0)


func die() -> void:
	dead = true
	mine_progress = 0.0
	G.game.on_player_died()


func respawn() -> void:
	dead = false
	health = max_health
	food = maxf(food, 60.0)
	stamina = 100.0
	velocity = Vector3.ZERO
	global_position = spawn_point
	air_min_vy = 0.0


func _update_crack() -> void:
	if mine_progress > 0.02 and target.get("hit", false):
		mine_crack.visible = true
		mine_crack.mesh = G.world.crack_mesh
		mine_crack.material_override = G.world.crack_mats[clampi(int(mine_progress * 4.0), 0, 3)]
		mine_crack.global_position = Vector3(mine_pos) + Vector3(0.5, 0.5, 0.5)
	else:
		mine_crack.visible = false


func _update_held() -> void:
	var id := cur_id()
	var st: String = G.game.state
	if st == "loading" or st == "title":
		id = 0
	if id != held_id:
		held_id = id
		if id <= 0:
			held.visible = false
		else:
			held_mat.albedo_texture = G.tex.icon(id)
			held.visible = true
	var s := swing
	if mine_progress > 0.0:
		s = absf(sin(Time.get_ticks_msec() * 0.018))
	held.rotation = Vector3(deg_to_rad(-10.0 - s * 55.0), deg_to_rad(-20.0), deg_to_rad(8.0 + s * 10.0))
	held.position = Vector3(0.3, -0.24 + s * 0.05, -0.5 - s * 0.06)
