class_name Rig
extends Node3D
## A downloaded, animated model (assets/models: Quaternius, CC0) for a zombie, a boar or another
## player. Client only: the dedicated-server exports leave assets/ out, so nothing here is
## preloaded and `make` returns null when a model can't be loaded (the caller keeps its box model).
## Plays the model's animations by hand (`tick`): every frame up close, less often far away or
## off screen. Each copy has its own materials (the hit flash tints them), and palette cells of the
## texture can be painted over (zombie skins, glowing eyes).

## Animations that repeat; the others play once and hold their last frame.
const LOOPS := ["Idle", "Walk", "Run", "Run_Arms", "Crawl", "Armature|Idle"]
## The models' textures are palettes: 512x512 texels in cells of 16x16, one colour each.
const CELL := 16

static var _scenes := {}
static var _textures := {}
static var _headless := DisplayServer.get_name() == "headless"

## The imported scene (scaled), its animation player and skeleton.
var scene: Node3D
var player: AnimationPlayer
var skeleton: Skeleton3D
var mats: Array[StandardMaterial3D] = []
var current := ""
## A one-shot (attack, scream, death) is playing; movement animations wait for it.
var once := false
var _acc := 0.0
var _step := 0.0
var _lod_t := 0.0


## A copy of the model at path, scaled, or null if it can't be loaded. loops: extra animations
## that repeat for this model (say a survivor's swing).
static func make(path: String, scale: Vector3, loops: Array = []) -> Rig:
	var ps: PackedScene = _scenes.get(path)
	if ps == null:
		if not ResourceLoader.exists(path):
			return null
		ps = load(path) as PackedScene
		if ps == null:
			return null
		_scenes[path] = ps
	var r := Rig.new()
	r.scene = ps.instantiate() as Node3D
	r.scene.scale = scale
	r.add_child(r.scene)
	r.player = r.scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	r.skeleton = r.scene.find_child("Skeleton3D", true, false) as Skeleton3D
	if r.player != null:
		r.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		# (the animations are shared by every copy of the model; setting this again is harmless)
		for a in LOOPS + loops:
			if r.player.has_animation(a):
				r.player.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	for node in r.scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			if m is StandardMaterial3D:
				var own: StandardMaterial3D = m.duplicate()
				mi.set_surface_override_material(s, own)
				r.mats.append(own)
	return r


## Paint palette cells ({Vector2i cell: Color}) in other colours.
func recolor(cells: Dictionary) -> void:
	for m in mats:
		var src := m.albedo_texture
		if src == null:
			continue
		var key := "%s %s" % [src.resource_path, cells]
		var tex: Texture2D = _textures.get(key)
		if tex == null:
			var img := src.get_image()
			if img == null or img.is_empty():
				return  # (a headless game keeps no pictures)
			if img.is_compressed():
				img.decompress()
			img.clear_mipmaps()
			for c in cells:
				img.fill_rect(Rect2i(c.x * CELL, c.y * CELL, CELL, CELL), cells[c])
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
			_textures[key] = tex
		m.albedo_texture = tex


## Make palette cells glow ({Vector2i cell: Color}, say the eyes) at energy.
func glow(cells: Dictionary, energy: float) -> void:
	var key := "glow %s" % [cells]
	var tex: Texture2D = _textures.get(key)
	if tex == null:
		var img := Image.create(512, 512, false, Image.FORMAT_RGB8)
		for c in cells:
			img.fill_rect(Rect2i(c.x * CELL, c.y * CELL, CELL, CELL), cells[c])
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
		_textures[key] = tex
	for m in mats:
		m.emission_enabled = true
		m.emission = Color.BLACK  # (added to the texture's colour)
		m.emission_texture = tex
		m.emission_energy_multiplier = energy


## Small glowing balls (eyes) at points of the model at rest, following bone as it moves.
func glow_spots(bone: String, points: Array, radius: float, col: Color, energy: float) -> void:
	var key := "spot %s %s" % [col, energy]
	var mat: StandardMaterial3D = _textures.get(key)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color.BLACK
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = energy
		_textures[key] = mat
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var frame := attach(bone)
	for p in points:
		var mi := MeshInstance3D.new()
		mi.mesh = sphere
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		frame.add_child(mi)
		mi.position = p


## A node that follows bone and whose space is the model's own (unscaled) space as the mesh was
## bound to the skeleton: things put in it at model coordinates move with that bone (eyes, a
## boar's tusks).
func attach(bone: String) -> Node3D:
	var bi := skeleton.find_bone(bone)
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skeleton.add_child(ba)
	var frame := Node3D.new()
	ba.add_child(frame)
	# The skin's bind pose takes mesh space to the bone's space (the bone's rest pose can differ).
	for node in skeleton.find_children("*", "MeshInstance3D", false, false):
		var mi := node as MeshInstance3D
		if mi.skin == null:
			continue
		for i in mi.skin.get_bind_count():
			if mi.skin.get_bind_bone(i) == bi or mi.skin.get_bind_name(i) == bone:
				frame.transform = mi.skin.get_bind_pose(i) * _to_scene(mi).affine_inverse()
				return frame
	frame.transform = (_to_scene(skeleton) * skeleton.get_bone_global_rest(bi)).affine_inverse()
	return frame


## The transform from node's space to the imported scene's own space.
func _to_scene(node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != scene and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## Hide the meshes under bone attachments (the survivors' weapons); returns those attachments.
func strip_props() -> Array[BoneAttachment3D]:
	var out: Array[BoneAttachment3D] = []
	for node in scene.find_children("*", "BoneAttachment3D", true, false):
		for c in node.get_children():
			if c is MeshInstance3D:
				c.visible = false
		out.append(node as BoneAttachment3D)
	return out


## Loop a movement animation (idle, walk, run) at speed; it waits while a one-shot plays.
func move(anim: String, speed := 1.0) -> void:
	if player == null:
		return
	if once:
		if player.is_playing():
			return
		once = false
	if current != anim:
		current = anim
		player.play(anim, 0.25)
	player.speed_scale = speed


## Play an animation once from the start (attack, scream, death); it holds its last frame.
func play_once(anim: String, speed := 1.0, blend := 0.12) -> void:
	if player == null or not player.has_animation(anim):
		return
	current = anim
	once = true
	player.play(anim, blend)
	player.seek(0.0)
	player.speed_scale = speed


## Move the animation on: every frame up close, a few times a second far away or off screen
## (and rarely in a headless game, where nothing is drawn).
func tick(delta: float) -> void:
	if player == null:
		return
	_acc += delta
	_lod_t -= delta
	if _lod_t <= 0.0:
		_lod_t = 0.4
		_step = _lod_step()
	if _acc >= _step:
		player.advance(_acc)
		_acc = 0.0


func _lod_step() -> float:
	if _headless:
		return 0.5
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return 0.0
	var p := global_position + Vector3(0, 1, 0)
	var d := cam.global_position.distance_to(p)
	if d > 3.0 and not cam.is_position_in_frustum(p):
		return 0.2
	if d < 20.0:
		return 0.0
	return 1.0 / 30.0 if d < 45.0 else 1.0 / 12.0
