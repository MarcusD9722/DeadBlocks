extends Mob
## A zombie. Its mood (`kind`: day, night, horde) decides how far it notices players and how hard
## it hunts; its `type` (M3) decides its body and what it does:
##   walker    the plain zombie
##   runner    fast and fragile
##   brute     slow and huge: smashes blocks 4.5x as hard and hits hard
##   crawler   legless and low: fits through 1-block gaps
##   screamer  keeps its distance and screams, calling more zombies (at most 3 times)
##   spitter   keeps 6-12 m away and spits acid that hurts players and eats into blocks
## The Sim node ticks every zombie (sim_tick) in a fixed order; zombies have no _physics_process.
## On normal days and nights a zombie only notices a player who comes within notice_range (or
## hits it), and gives up beyond chase_range; the Blood Moon horde hunts everyone.

const AcidScript := preload("res://scripts/acid.gd")
const TYPES := ["walker", "runner", "brute", "crawler", "screamer", "spitter"]
## Per type: body width and height (m), health, damage to players and to blocks, and speed by
## mood (day, night, horde). The horde is a third tougher (see _apply).
const STATS := {
	"walker": {"w": 0.6, "h": 1.9, "hp": 30.0, "dmg": 8.0, "blk": 10.0, "spd": [1.7, 2.6, 3.5]},
	"runner": {"w": 0.5, "h": 1.85, "hp": 18.0, "dmg": 6.0, "blk": 6.0, "spd": [3.4, 5.2, 5.6]},
	"brute": {"w": 0.9, "h": 2.3, "hp": 110.0, "dmg": 18.0, "blk": 45.0, "spd": [1.2, 1.4, 1.8]},
	"crawler": {"w": 0.6, "h": 0.75, "hp": 16.0, "dmg": 7.0, "blk": 6.0, "spd": [1.5, 2.0, 2.6]},
	"screamer": {"w": 0.55, "h": 1.8, "hp": 22.0, "dmg": 4.0, "blk": 4.0, "spd": [1.8, 2.2, 2.8]},
	"spitter": {"w": 0.6, "h": 1.8, "hp": 26.0, "dmg": 6.0, "blk": 6.0, "spd": [1.6, 2.0, 2.4]},
}
const BASIC := "res://assets/models/zombies/Zombie_Basic.gltf"
const HULK := "res://assets/models/zombies/Zombie_Arm.gltf"
const CHUBBY := "res://assets/models/zombies/Zombie_Chubby.gltf"
## The downloaded models (assets/models/zombies, Quaternius, CC0) per type: the file, its size,
## how much thinner, and the colours painted over its skin and clothes (one picked per zombie).
const LOOKS := {
	"walker": {"file": BASIC, "scale": 1.38, "skin": ["6f8a5a", "7a8c63", "849072", "6b7d5c"], "cloth": ["3f5363", "4a4a3e", "5a3f36", "3e4a3a"]},
	"runner": {"file": BASIC, "scale": 1.34, "thin": 0.86, "skin": ["9aa39a", "a3a89b"], "cloth": ["6e2a26", "5c2622"]},
	"brute": {"file": HULK, "scale": 1.5, "skin": ["5f6e52", "66705a"], "cloth": ["3b3a33"]},
	"crawler": {"file": BASIC, "scale": 1.3, "skin": ["84906a", "7a845f"], "cloth": ["3f5363", "4a4a3e"]},
	"screamer": {"file": BASIC, "scale": 1.32, "thin": 0.9, "skin": ["b9bcae", "aeb3a6"], "cloth": ["3c3846"]},
	"spitter": {"file": CHUBBY, "scale": 1.12, "skin": ["8fa04a", "98a452"], "cloth": ["4b4636"]},
}
## Per model file: its palette cells (skin, clothes, eyes, the spitter's tongue) and how fast its
## walk and run cycles move (m/s at size 1 and normal rate), so the feet keep up with the ground.
## (The basic zombie's eye colour also outlines its shoes, so it gets glowing balls in its eye
## sockets instead: EYE_SPOTS, in the model's own space.)
const PARTS := {
	BASIC: {"skin": Vector2i(1, 6), "cloth": Vector2i(10, 6), "walk": 0.6, "run": 2.9},
	HULK: {"skin": Vector2i(1, 5), "cloth": Vector2i(2, 5), "eyes": Vector2i(0, 5), "walk": 0.6, "run": 2.9},
	CHUBBY: {"skin": Vector2i(1, 7), "cloth": Vector2i(2, 7), "eyes": Vector2i(0, 7), "tongue": Vector2i(6, 7), "walk": 0.6, "run": 3.3},
}
const EYE_SPOTS := [Vector3(-0.13, 1.07, 0.27), Vector3(0.13, 1.07, 0.27)]
const SCREAM_EVERY := 30.0
const SCREAMS := 3
const CALLED := 4          # zombies one scream calls
const SPIT_EVERY := 3.0
const ACID_DMG := 12.0
const ACID_BLOCK_DMG := 25.0

var kind := "day"
var type := "walker"
var speed := 2.4
var notice_range := 10.0
var chase_range := 20.0
## Noticed a player (came close, was hit, or was spawned by /spawn) and is after them.
var hunting := false
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
var scream_cd := 0.0
var screams := 0
var scream_anim := 0.0
var spit_cd := 0.0
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var voice: AudioStreamPlayer3D
var _day := 1
## Client: smoothed speed for the animations, and the last attack/scream level (a rise starts one).
var _spd := 0.0
var _last_attack := 0.0
var _last_scream := 0.0

## Set by Sim: processing order, region membership, and this zombie's own random numbers
## (so its choices don't depend on the order zombies are processed in).
var id := 0
var region = null
var rng := RandomNumberGenerator.new()


func setup(k: String, day: int, t := "walker") -> void:
	type = t if STATS.has(t) else "walker"
	_day = day
	_apply(k)
	hp = max_hp


## Mood and type into numbers. Walkers keep the numbers they had before M3 (day 30 hp, horde 40).
func _apply(k: String) -> void:
	kind = k
	blood = k == "horde"
	var s: Dictionary = STATS[type]
	var mood := 0 if k == "day" else (2 if blood else 1)
	speed = s["spd"][mood]
	if type == "walker" and mood == 1:
		speed += minf(_day * 0.05, 0.6)
	notice_range = [10.0, 16.0, 400.0][mood]
	chase_range = [20.0, 30.0, 400.0][mood]
	max_hp = roundf(s["hp"] * (4.0 / 3.0 if blood else 1.0))
	player_dmg = roundf(s["dmg"] * (1.375 if blood else 1.0))
	block_dmg = roundf(s["blk"] * (1.4 if blood else 1.0))


## Dawn after the Blood Moon (and after any night): back to a day zombie that only goes for
## players who come close. Clients see the change in S_MOBS and swap the picture.
func become_day() -> void:
	_apply("day")
	hp = minf(hp, max_hp)
	hunting = false


func _ready() -> void:
	set_physics_process(false)
	if not view:
		add_to_group("zombies")  # the Sim ticks these; views are moved by snapshots
	var s: Dictionary = STATS[type]
	tall = ceili(s["h"] - 0.01)
	_setup_body(s["w"], s["h"])
	groan_t = rng.randf_range(1.0, 7.0)
	scream_cd = rng.randf_range(0.5, 2.0)
	spit_cd = rng.randf_range(1.0, 2.0)
	if G.server_mode:
		return
	_build_model()
	voice = AudioStreamPlayer3D.new()
	voice.stream = G.sfx.streams["groan"]
	voice.max_distance = 34.0
	voice.unit_size = 5.0
	voice.volume_db = -2.0
	add_child(voice)
	voice.position.y = minf(1.6, s["h"] * 0.8)


func _build_model() -> void:
	if _use_rig(_make_rig()):
		rig.tick(randf() * 1.5)  # (not all in step)
		return
	var skin := Color8(120, 158, 86).lerp(Color8(96, 128, 74), randf())
	var shirts := [Color8(104, 94, 122), Color8(88, 104, 120), Color8(120, 82, 70), Color8(70, 92, 70), Color8(130, 120, 96)]
	var shirt: Color = shirts[randi() % shirts.size()]
	var pants := Color8(78, 74, 62)
	match type:
		"runner":
			skin = Color8(150, 160, 138)
			shirt = Color8(140, 44, 40)
		"brute":
			skin = Color8(92, 112, 76)
			shirt = skin.darkened(0.15)
			pants = Color8(64, 58, 50)
		"crawler":
			skin = Color8(132, 140, 104)
		"screamer":
			skin = Color8(176, 178, 160)
			shirt = Color8(60, 56, 70)
		"spitter":
			skin = Color8(150, 168, 70)
			shirt = Color8(96, 104, 60)
	if blood:
		skin = skin.lerp(Color8(110, 124, 80), 0.5)
	var eye := Color8(255, 40, 30) if blood else Color8(226, 226, 82)
	if type == "crawler":
		_build_crawler(skin, shirt, eye)
		return
	var thin := 0.8 if type == "runner" or type == "screamer" else 1.0
	_box(model, Vector3(0.5, 0.5, 0.5), Vector3(0, 1.62, 0), skin)
	_box(model, Vector3(0.11, 0.07, 0.02), Vector3(-0.12, 1.67, 0.255), eye, true)
	_box(model, Vector3(0.11, 0.07, 0.02), Vector3(0.12, 1.67, 0.255), eye, true)
	match type:
		"screamer":
			_box(model, Vector3(0.2, 0.16, 0.02), Vector3(0, 1.47, 0.255), Color8(30, 10, 14))  # the open mouth
			_box(model, Vector3(0.54, 0.5, 0.2), Vector3(0, 1.5, -0.2), Color8(30, 28, 30))   # long hair
		"spitter":
			_box(model, Vector3(0.2, 0.08, 0.02), Vector3(0, 1.47, 0.255), Color8(120, 220, 40), true)
			_box(model, Vector3(0.36, 0.22, 0.3), Vector3(0, 1.3, 0.06), Color8(150, 210, 60), true)  # the acid sac
		_:
			_box(model, Vector3(0.22, 0.05, 0.02), Vector3(0, 1.48, 0.255), Color8(40, 20, 20))
	_box(model, Vector3(0.5 * thin, 0.72, 0.28 * thin), Vector3(0, 1.01, 0), shirt)
	_box(model, Vector3(0.18, 0.14, 0.02), Vector3(0.08, 1.1, 0.145 * thin), Color8(110, 30, 30))
	leg_l = _pivot(model, Vector3(-0.125 * thin, 0.65, 0))
	leg_r = _pivot(model, Vector3(0.125 * thin, 0.65, 0))
	_box(leg_l, Vector3(0.24 * thin, 0.65, 0.26 * thin), Vector3(0, -0.325, 0), pants)
	_box(leg_r, Vector3(0.24 * thin, 0.65, 0.26 * thin), Vector3(0, -0.325, 0), pants)
	var arm := 0.3 if type == "brute" else 0.22 * thin
	arm_l = _pivot(model, Vector3(-0.25 * thin - arm * 0.5 - 0.01, 1.3, 0))
	arm_r = _pivot(model, Vector3(0.25 * thin + arm * 0.5 + 0.01, 1.3, 0))
	_box(arm_l, Vector3(arm, 0.7, arm), Vector3(0, -0.33, 0), skin)
	_box(arm_r, Vector3(arm, 0.7, arm), Vector3(0, -0.33, 0), skin)
	if type == "brute":
		model.scale = Vector3(1.35, 1.2, 1.35)
	elif blood:
		model.scale = Vector3.ONE * 1.06


## The downloaded model in this type's colours: Blood Moon zombies are redder and a little bigger
## with glowing red eyes, night zombies' eyes glow dimly.
func _make_rig() -> Rig:
	var look: Dictionary = LOOKS[type]
	var parts: Dictionary = PARTS[look["file"]]
	var sc: float = look["scale"] * (1.06 if blood else 1.0)
	var thin: float = look.get("thin", 1.0)
	var r := Rig.make(look["file"], Vector3(sc * thin, sc, sc * thin))
	if r == null:
		return null
	var skins: Array = look["skin"]
	var cloths: Array = look["cloth"]
	var skin := Color(skins[randi() % skins.size()])
	if blood:
		skin = skin.lerp(Color8(122, 58, 46), 0.4)
	var paint := {parts["skin"]: skin, parts["cloth"]: Color(cloths[randi() % cloths.size()])}
	var glows := {}
	if parts.has("tongue"):
		paint[parts["tongue"]] = Color8(150, 224, 58)
		glows[parts["tongue"]] = Color8(70, 140, 10)
	var eye := Color8(255, 30, 10) if blood else Color8(90, 90, 40)
	if blood or kind != "day":
		if parts.has("eyes"):
			glows[parts["eyes"]] = eye
		else:
			r.glow_spots("Head", EYE_SPOTS, 0.045, eye, 2.2 if blood else 1.0)
	r.recolor(paint)
	if not glows.is_empty():
		r.glow(glows, 2.2 if blood else 1.0)
	r.move("Crawl" if type == "crawler" else "Idle", 0.0 if type == "crawler" else 1.0)
	return r


## A crawler: the upper body lying flat, dragging itself on its arms.
func _build_crawler(skin: Color, shirt: Color, eye: Color) -> void:
	_box(model, Vector3(0.44, 0.42, 0.44), Vector3(0, 0.36, 0.5), skin)
	_box(model, Vector3(0.1, 0.06, 0.02), Vector3(-0.1, 0.4, 0.725), eye, true)
	_box(model, Vector3(0.1, 0.06, 0.02), Vector3(0.1, 0.4, 0.725), eye, true)
	_box(model, Vector3(0.5, 0.28, 0.72), Vector3(0, 0.2, 0.0), shirt)
	_box(model, Vector3(0.36, 0.2, 0.3), Vector3(0, 0.14, -0.48), Color8(78, 74, 62))
	arm_l = _pivot(model, Vector3(-0.3, 0.26, 0.3))
	arm_r = _pivot(model, Vector3(0.3, 0.26, 0.3))
	_box(arm_l, Vector3(0.16, 0.16, 0.6), Vector3(0, -0.1, 0.25), skin)
	_box(arm_r, Vector3(0.16, 0.16, 0.6), Vector3(0, -0.1, 0.25), skin)


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
	scream_cd -= delta
	spit_cd -= delta
	attack_anim = maxf(0.0, attack_anim - delta * 3.0)
	scream_anim = maxf(0.0, scream_anim - delta * 1.5)
	if not G.server_mode:
		_tick_flash(delta)
	var pl = _target()
	var to := Vector3.ZERO
	var hd := INF
	if pl != null:
		to = pl.global_position - global_position
		hd = Vector2(to.x, to.z).length()
	var chasing: bool = pl != null and hd < (chase_range if hunting else notice_range)
	if pl != null:
		hunting = chasing  # (no one to target yet, say before its first region: keep the mood)
	var dir := Vector3.ZERO
	if chasing:
		if hd > 0.85:
			dir = Vector3(to.x, 0, to.z) / hd
		if type == "screamer" or type == "spitter":
			dir = _keep_distance(dir, hd)
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
	# Hit the player when close and nothing solid in between (a crawler hits low).
	var reach := 1.8 if type == "brute" else 1.45
	if chasing and hd < reach and absf(to.y) < 1.9 and attack_cd <= 0.0:
		var mid: Vector3 = (global_position + pl.global_position) * 0.5 + Vector3(0, 0.45 if type == "crawler" else 1.5, 0)
		if not Blocks.is_solid(G.world.get_block(floori(mid.x), floori(mid.y), floori(mid.z))):
			pl.take_damage(player_dmg, global_position)
			attack_cd = 1.1
			attack_anim = 1.0
	if chasing and type == "screamer":
		_scream(pl, hd)
	elif chasing and type == "spitter":
		_spit(pl, to, hd)
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


## Screamers and spitters hang back: away when a player gets close, still at a middle distance,
## nearer when too far.
func _keep_distance(dir: Vector3, hd: float) -> Vector3:
	var far := 14.0 if type == "screamer" else 12.0
	if hd < 6.0:
		return -dir
	if hd < far:
		return Vector3.ZERO
	return dir


## Scream and call CALLED zombies to places 18-28 m around the player, out of sight (through the
## Sim, so it doesn't depend on processing order).
func _scream(pl, hd: float) -> void:
	if screams >= SCREAMS or scream_cd > 0.0 or hd > 24.0:
		return
	scream_cd = SCREAM_EVERY
	screams += 1
	scream_anim = 1.0
	var spots := []
	for i in CALLED:
		var a := rng.randf() * TAU
		var d := rng.randf_range(18.0, 28.0)
		spots.append(Vector2(pl.global_position.x + cos(a) * d, pl.global_position.z + sin(a) * d))
	G.sim.queue_call(id, spots, kind)


## Spit an acid glob at the player when there's a clear line (it flies in an arc; see acid.gd).
func _spit(pl, to: Vector3, hd: float) -> void:
	if spit_cd > 0.0 or hd < 3.0 or hd > 16.0:
		return
	var from := global_position + Vector3(0, 1.45, 0) + Vector3(to.x, 0, to.z).normalized() * 0.4
	var aim: Vector3 = pl.global_position + Vector3(0, 1.1, 0)
	if not _clear_line(from, aim):
		return
	spit_cd = SPIT_EVERY
	attack_anim = 1.0
	rotation.y = atan2(to.x, to.z)
	var mult := 1.375 if blood else 1.0
	G.sim.queue_spit(id, from, AcidScript.launch_velocity(from, aim), ACID_DMG * mult, ACID_BLOCK_DMG * mult)


## Nothing solid on the straight line from a to b.
static func _clear_line(a: Vector3, b: Vector3) -> bool:
	var n := ceili(a.distance_to(b) / 0.5)
	for i in range(1, n):
		var p := a.lerp(b, float(i) / n)
		if Blocks.is_solid(G.world.get_block(floori(p.x), floori(p.y), floori(p.z))):
			return false
	return true


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
	_pose(Vector2(rv.x, rv.z).length(), delta)


func _pose(spd: float, delta: float) -> void:
	if rig != null:
		_pose_rig(spd, delta)
		return
	var mv := minf(1.0, spd)
	var lift := sin(attack_anim * PI) * 0.9
	if type == "crawler":
		# Arms reach forward in turn, dragging the body.
		arm_l.rotation.x = sin(anim) * 0.5 * mv - lift * 0.5
		arm_r.rotation.x = -sin(anim) * 0.5 * mv - lift * 0.5
		return
	leg_l.rotation.x = sin(anim) * 0.7 * mv
	leg_r.rotation.x = -sin(anim) * 0.7 * mv
	if type == "screamer" and scream_anim > 0.0:
		arm_l.rotation.x = -PI * 0.9 * scream_anim
		arm_r.rotation.x = -PI * 0.9 * scream_anim
		return
	arm_l.rotation.x = -PI * 0.47 + sin(anim * 0.5) * 0.12 - lift
	arm_r.rotation.x = -PI * 0.47 - sin(anim * 0.5) * 0.12 - lift
	model.rotation.x = 0.2 * mv if type == "runner" else 0.0


## The model's animation for how fast it goes: idle, walk or run (a crawler always crawls), each
## played faster or slower to match the ground speed; attacks and screams play once over it.
func _pose_rig(spd: float, delta: float) -> void:
	_spd = lerpf(_spd, spd, minf(1.0, delta * 8.0))
	var parts: Dictionary = PARTS[LOOKS[type]["file"]]
	var sc: float = LOOKS[type]["scale"]
	if attack_anim > _last_attack and type != "crawler":
		rig.play_once("Idle_Attack" if type == "spitter" else "Punch", 1.8 if type == "spitter" else 1.3)
	elif scream_anim > _last_scream:
		rig.play_once("Idle_Attack", 1.0)
	_last_attack = attack_anim
	_last_scream = scream_anim
	if type == "crawler":
		rig.move("Crawl", clampf(_spd / (0.5 * sc), 0.0, 2.6))
	elif _spd < 0.2:
		rig.move("Idle")
	elif _spd < 1.9:
		rig.move("Walk", clampf(_spd / (parts["walk"] * sc), 0.6, 1.9))
	else:
		rig.move("Run", clampf(_spd / (parts["run"] * sc), 0.65, 1.6))
	rig.tick(delta)


## Dying (client view): the model plays its death animation (a crawler rolls onto its side); box
## models fall flat, arms going limp.
func _start_death() -> void:
	super()
	if rig != null:
		if type == "crawler":
			rig.move("Crawl", 0.0)
		else:
			rig.play_once("Death", 1.0, 0.1)


func _death_tilt() -> Vector3:
	if type == "crawler":
		return Vector3(0.0, 0.0, PI * 0.45 * (1.0 if net_id % 2 == 0 else -1.0))
	if rig != null:
		return Vector3.ZERO
	return super()


func _death_lift() -> float:
	if rig != null and type != "crawler":
		return 0.0
	return {"brute": 0.26, "crawler": 0.12}.get(type, 0.18)


func _death_pose(t: float, delta: float) -> void:
	super(t, delta)
	if arm_l == null or type == "crawler":
		return
	arm_l.rotation.x = lerpf(arm_l.rotation.x, -0.25, 0.12)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, -0.45, 0.12)
	arm_l.rotation.z = lerpf(arm_l.rotation.z, -0.35, 0.12)
	arm_r.rotation.z = lerpf(arm_r.rotation.z, 0.3, 0.12)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.15, 0.12)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, -0.1, 0.12)


func _on_hurt(attacker: Node) -> void:
	if attacker != null:
		hunting = true  # hit by a player: goes after the nearest one, as long as they stay in chase_range
	if not G.server_mode:
		G.sfx.play_at("zhurt", global_position + Vector3(0, minf(1.5, height), 0), -3.0)


func _on_death(attacker: Node) -> void:
	G.game.kills += 1
	# The player who landed the last hit (the local player, or a ServerPlayer online).
	if attacker != null and attacker.has_method("give"):
		if "kills" in attacker:
			attacker.kills += 1
		if attacker.has_method("add_xp"):
			attacker.add_xp(Skills.zombie_xp(type, kind))  # (M4.5)
		if rng.randf() < 0.6:
			attacker.give(Items.FIBER, rng.randi_range(1, 2))
		# Blood Moon loot: half the ordinary ones drop a Blood Shard, Screamers and Spitters 2,
		# Brutes 3.
		if blood:
			var shards: int = {"brute": 3, "screamer": 2, "spitter": 2}.get(type, 1 if rng.randf() < 0.5 else 0)
			if shards > 0:
				attacker.give(Items.BLOOD_SHARD, shards)


func net_kind() -> int:
	if type != "walker":
		return Proto.ZOMBIE_KINDS[type]
	return Proto.MOB_HORDE if blood else (Proto.MOB_NIGHT if kind == "night" else Proto.MOB_ZOMBIE)


func net_flags() -> int:
	var f := super()
	if attack_anim > 0.5:
		f |= Proto.MF_ATTACK
	if blood:
		f |= Proto.MF_BLOOD
	if scream_anim > 0.5:
		f |= Proto.MF_SCREAM
	return f


func _view_animate(delta: float, spd: float, rising: int) -> void:
	if rising & Proto.MF_ATTACK:
		attack_anim = 1.0
		if type == "spitter":
			G.sfx.play_at("spit", global_position + Vector3(0, 1.4, 0), -2.0)
	if rising & Proto.MF_SCREAM:
		scream_anim = 1.0
		G.sfx.play_at("scream", global_position + Vector3(0, 1.6, 0), 2.0)
	attack_anim = maxf(0.0, attack_anim - delta * 3.0)
	scream_anim = maxf(0.0, scream_anim - delta * 1.5)
	groan_t -= delta
	if groan_t <= 0.0:
		groan_t = randf_range(5.0, 12.0)
		voice.pitch_scale = randf_range(0.8, 1.15) * (0.85 if blood else 1.0) * (0.7 if type == "brute" else 1.0)
		voice.play()
	_pose(spd, delta)
