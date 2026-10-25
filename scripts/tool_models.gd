class_name ToolModels
extends RefCounted
## Rounded 3D models of the tools and weapons (M4.3), built here from smooth shapes (round
## handles and shafts, curved heads, lofted blades) with materials from shaders/tool.gdshader:
## wood and stone take the game's photo textures (G.tex), metals are plain colours. One shape per
## tool; its tier shows in the material (wood, stone, iron, steel, Blood Steel). Client only.
##
## A model's origin is where the hand holds it. Handles run up +Y with the head at the top and
## its working side (pick point, axe edge, hammer face) towards -Z. A spear's point is up +Y too.
## The bow stands along Y with its back towards -Z (its string on the +Z side, an arrow on it
## points -Z); the crossbow, arrows and bolts point -Z. make_flying turns any of them to point -Z.

const SHADER := preload("res://shaders/tool.gdshader")
const SIDES := 12
## Icons drawn from the models: pixels per icon, and the grid they are drawn in at once.
const ICON_PX := 64
const ICON_COLS := 8

## Materials: [texture ("block" or "terrain" array, "" none), layer, repeats per metre, tint,
## metallic, roughness, streak, glow].
const MATS := {
	"wood": ["block", 3, 1.0, Color(1.08, 1.0, 0.92), 0.0, 0.72, 0.0, Color(0, 0, 0)],
	"lightwood": ["block", 3, 1.0, Color(1.35, 1.22, 1.0), 0.0, 0.7, 0.0, Color(0, 0, 0)],
	"darkwood": ["block", 3, 1.0, Color(0.5, 0.36, 0.3), 0.0, 0.65, 0.0, Color(0, 0, 0)],
	"stone": ["terrain", 2, 2.5, Color(1.0, 1.0, 1.0), 0.0, 0.9, 0.0, Color(0, 0, 0)],
	"flint": ["terrain", 2, 4.0, Color(0.55, 0.55, 0.62), 0.0, 0.45, 0.0, Color(0, 0, 0)],
	"iron": ["", 0, 1.0, Color(0.42, 0.42, 0.44), 0.85, 0.5, 0.3, Color(0, 0, 0)],
	"steel": ["", 0, 1.0, Color(0.8, 0.82, 0.86), 1.0, 0.26, 0.2, Color(0, 0, 0)],
	"blood": ["", 0, 1.0, Color(0.5, 0.06, 0.08), 0.85, 0.3, 0.35, Color(0.22, 0.0, 0.02)],
	"leather": ["", 0, 1.0, Color(0.36, 0.22, 0.13), 0.0, 0.85, 0.5, Color(0, 0, 0)],
	"redleather": ["", 0, 1.0, Color(0.32, 0.06, 0.07), 0.0, 0.8, 0.5, Color(0, 0, 0)],
	"fiber": ["", 0, 1.0, Color(0.62, 0.55, 0.36), 0.0, 1.0, 0.6, Color(0, 0, 0)],
	"string": ["", 0, 1.0, Color(0.86, 0.83, 0.76), 0.0, 0.9, 0.0, Color(0, 0, 0)],
	"feather": ["", 0, 1.0, Color(0.9, 0.88, 0.84), 0.0, 1.0, 0.4, Color(0, 0, 0)],
	"redfeather": ["", 0, 1.0, Color(0.75, 0.16, 0.12), 0.0, 1.0, 0.4, Color(0, 0, 0)],
}
## A head's material by tier (0 = hand, 1 wood ... 5 Blood Steel).
const TIER_MAT := ["wood", "wood", "stone", "iron", "steel", "blood"]

## The photo textures the materials use (set by Tex when it loads them; null: plain colours).
static var block_tex: Texture2DArray = null
static var terrain_tex: Texture2DArray = null
static var _mats := {}
static var _parts := {}
## Icons drawn from the models once they are ready (render_icons): item id -> texture.
static var icons := {}
static var _icons_started := false


## Does this item have a 3D model (every tool, weapon and ammo; armor since M4.5, ArmorModels)?
static func has_model(id: int) -> bool:
	var d := Items.info(id)
	return d.has("tool") or d.has("ammo_of") or d.has("armor")


## A new copy of the item's model (null if it has none). `held`: the one in your own hand, drawn
## in front of the world.
static func make(id: int, held := false) -> Node3D:
	if not has_model(id):
		return null
	if not _parts.has(id):
		_parts[id] = _build(id)
	var root := Node3D.new()
	root.name = "Tool%d" % id
	for part in _parts[id]:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.material_override = material(part[1], held)
		if held:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	match id:
		Items.BOW:
			_add_strings(root, held)
			var nock := make(Items.STONE_ARROW, held)
			nock.name = "Nock"
			nock.visible = false
			root.add_child(nock)
			set_draw(root, 0.0)
		Items.CROSSBOW:
			_add_strings(root, held)
			var bolt := make(Items.IRON_BOLT, held)
			bolt.name = "Bolt"
			bolt.position = Vector3(0, 0.03, -0.17)
			root.add_child(bolt)
			set_loaded(root, true)
	return root


## The model turned to point -Z (for a spear or arrow in flight, or stuck in the ground), with its
## middle at the origin.
static func make_flying(id: int) -> Node3D:
	var m := make(id)
	if m == null:
		return null
	var pivot := Node3D.new()
	pivot.add_child(m)
	if Items.tool_type(id) == "spear":
		m.rotation.x = -PI * 0.5  # (+Y to -Z)
		m.position = Vector3(0, 0, 0.1)  # its middle (0.1 up the shaft from the hand) on the origin
	return pivot


## Where a tool or weapon in your own hand sits in front of the camera (camera space): a tool is
## seen from the side and swings down (`swing` 0..1); the bow is held out on the left, upright as
## it is drawn; the crossbow points ahead and kicks; a spear points ahead (thrusting as you hit)
## or is lifted over the shoulder to throw (`charge`).
static func held_pose(id: int, swing: float, draw: float, charge: float) -> Transform3D:
	var tilt := 0.0
	var roll := 0.0
	var yaw := 0.0
	var pos := Vector3.ZERO
	var size := 1.0
	if ArmorModels.has_model(id):
		# Armor (M4.5) is held out low in front, as if about to be put on.
		return Transform3D(Basis(Vector3.RIGHT, 0.35 - swing * 0.6) * Basis(Vector3.UP, PI + 0.4), Vector3(0.3, -0.38, -0.6))
	match Items.tool_type(id):
		"bow":
			# Just left of the crosshair, so the arrow on it points where you look.
			yaw = 0.1
			roll = 0.3 - 0.2 * draw
			pos = Vector3(-0.1 - 0.05 * draw, -0.08 + 0.02 * draw, -0.5 + 0.04 * draw)
			size = 0.8
		"crossbow":
			tilt = 0.05 + swing * 0.25
			pos = Vector3(0.14, -0.17 + swing * 0.02, -0.4 + swing * 0.07)
		"spear":
			tilt = -PI * 0.5 + (0.1 if charge > 0.0 else 0.3)
			yaw = 0.05
			if charge > 0.0:
				pos = Vector3(0.3, -0.1, -0.1 + 0.16 * charge)  # over the shoulder, drawn back
			else:
				pos = Vector3(0.26, -0.32, -0.3 - swing * 0.32)  # a thrust
		_:
			yaw = 1.3  # the head seen from the side, its point (or a blade's flat) towards us
			if Items.tool_type(id) == "shovel":
				yaw = 0.15  # the spade's face towards us
			roll = 0.42
			tilt = -0.3 - swing * 1.1
			pos = Vector3(0.38, -0.44 + swing * 0.05, -0.5 - swing * 0.06)
	# Turned to the side first, leaned over, then tipped forward (and down as it swings).
	var b := Basis(Vector3.RIGHT, tilt) * Basis(Vector3.BACK, roll) * Basis(Vector3.UP, yaw)
	return Transform3D(b.scaled(Vector3.ONE * size), pos)


## A bow's string and limbs drawn back by `draw` (0..1), with an arrow on it (arrow_id > 0).
static func set_draw(bow: Node3D, draw: float, arrow_id := 0) -> void:
	var limbs := bow.get_child(0) as Node3D
	if limbs != null:
		limbs.scale = Vector3(1.0, 1.0 - 0.06 * draw, 1.0 + 0.5 * draw)
	var tip := 0.62 * (1.0 - 0.06 * draw)
	var tz := 0.12 * (1.0 + 0.5 * draw)
	var nock := Vector3(0, 0, tz + 0.004 + draw * 0.42)
	_string(bow.get_node("S0"), Vector3(0, tip, tz), nock)
	_string(bow.get_node("S1"), Vector3(0, -tip, tz), nock)
	var a := bow.get_node("Nock") as Node3D
	a.visible = arrow_id > 0
	if arrow_id > 0:
		# The arrow lies on the side of the grip with its tail on the string.
		a.position = Vector3(0.018, 0.0, nock.z - 0.36)


## A crossbow drawn and loaded (a bolt on it), or with its string forward.
static func set_loaded(cb: Node3D, loaded: bool) -> void:
	var latch := Vector3(0, 0.025, -0.04 if loaded else -0.25)
	_string(cb.get_node("S0"), Vector3(0.29, 0.02, -0.25), latch)
	_string(cb.get_node("S1"), Vector3(-0.29, 0.02, -0.25), latch)
	(cb.get_node("Bolt") as Node3D).visible = loaded


static func _add_strings(root: Node3D, held: bool) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0011
	cyl.bottom_radius = 0.0011
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	for n in ["S0", "S1"]:
		var mi := MeshInstance3D.new()
		mi.name = n
		mi.mesh = cyl
		mi.material_override = material("string", held)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


## Stretch a unit cylinder (along Y) from a to b.
static func _string(mi: Node3D, a: Vector3, b: Vector3) -> void:
	var y := b - a
	var len := maxf(y.length(), 0.001)
	y /= len
	var x := y.cross(Vector3.FORWARD) if absf(y.z) < 0.9 else y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y * len, z), (a + b) * 0.5)


static func material(kind: String, held := false) -> ShaderMaterial:
	var key := "%s|%s" % [kind, held]
	if _mats.has(key):
		return _mats[key]
	var d: Array = MATS[kind]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var arr: Texture2DArray = block_tex if d[0] == "block" else (terrain_tex if d[0] == "terrain" else null)
	if arr != null:
		m.set_shader_parameter("tex", arr)
		m.set_shader_parameter("layer", float(d[1]))
	else:
		m.set_shader_parameter("layer", -1.0)
	m.set_shader_parameter("tex_scale", d[2])
	var t: Color = d[3]
	if arr == null and d[0] != "":
		t = t * (Color(0.55, 0.4, 0.26) if d[0] == "block" else Color(0.5, 0.5, 0.52))  # (no picture)
	m.set_shader_parameter("tint", Vector3(t.r, t.g, t.b))
	m.set_shader_parameter("metal", d[4])
	m.set_shader_parameter("rough", d[5])
	m.set_shader_parameter("streak", d[6])
	var g: Color = d[7]
	m.set_shader_parameter("glow", Vector3(g.r, g.g, g.b))
	m.set_shader_parameter("held", held)
	_mats[key] = m
	return m


# ---------------------------------------------------------------- the shapes

## The parts of an item's model: [[mesh, material], ...].
static func _build(id: int) -> Array:
	if ArmorModels.has_model(id):
		return ArmorModels.item_parts(id)
	var tier := Items.tier(id)
	var head: String = TIER_MAT[clampi(tier, 0, 5)]
	var handle := "darkwood" if tier == 5 else "wood"
	var chunky := 1.45 if tier == 2 else (1.25 if tier == 1 else 1.0)  # stone and wood are thicker
	var parts := []
	match id:
		Items.BOW:
			parts.append([_mesh(func(st): _bow_limbs(st)), "wood"])
			parts.append([_mesh(func(st): _rod(st, Vector3(0, -0.075, 0), Vector3(0, 0.075, 0), 0.021, 0.021)), "leather"])
			return parts
		Items.CROSSBOW:
			parts.append([_mesh(func(st): _crossbow_stock(st)), "wood"])
			parts.append([_mesh(func(st): _crossbow_prod(st)), "iron"])
			return parts
		Items.STONE_ARROW, Items.IRON_ARROW:
			var tip := "flint" if id == Items.STONE_ARROW else "iron"
			parts.append([_mesh(func(st): _rod(st, Vector3(0, 0, 0.35), Vector3(0, 0, -0.31), 0.0042, 0.0042)), "lightwood"])
			parts.append([_mesh(func(st): _arrow_head(st, -0.3, 0.06, 0.013 if id == Items.STONE_ARROW else 0.011)), tip])
			parts.append([_mesh(func(st): _vanes(st, 0.2, 0.33, 0.013, 3)), "feather" if id == Items.STONE_ARROW else "redfeather"])
			return parts
		Items.IRON_BOLT:
			parts.append([_mesh(func(st): _rod(st, Vector3(0, 0, 0.15), Vector3(0, 0, -0.12), 0.0055, 0.0055)), "lightwood"])
			parts.append([_mesh(func(st): _arrow_head(st, -0.115, 0.045, 0.0085)), "iron"])
			parts.append([_mesh(func(st): _vanes(st, 0.08, 0.15, 0.011, 2)), "leather"])
			return parts
	match Items.tool_type(id):
		"pick":
			parts.append([_mesh(func(st): _handle(st, 0.56)), handle])
			parts.append([_mesh(func(st): _pick_head(st, chunky)), head])
			if tier == 2:
				parts.append([_mesh(func(st): _lashing(st, 0.5, 0.034)), "fiber"])
		"axe":
			parts.append([_mesh(func(st): _handle(st, 0.56)), handle])
			parts.append([_mesh(func(st): _axe_head(st, chunky)), head])
			if tier == 2:
				parts.append([_mesh(func(st): _lashing(st, 0.49, 0.03)), "fiber"])
		"shovel":
			parts.append([_mesh(func(st): _handle(st, 0.62, true)), handle])
			parts.append([_mesh(func(st): _spade(st, chunky)), head])
		"hammer":
			parts.append([_mesh(func(st): _handle(st, 0.5)), handle])
			parts.append([_mesh(func(st): _hammer_head(st, tier)), head])
			if tier == 2:
				parts.append([_mesh(func(st): _lashing(st, 0.47, 0.03)), "fiber"])
		"spear":
			parts.append([_mesh(func(st): _spear_shaft(st, tier)), "wood"])
			if tier >= 2:
				parts.append([_mesh(func(st): _leaf(st, 0.86, 0.2, 0.032 if tier == 2 else 0.028, 0.012 if tier == 2 else 0.007)),
					"flint" if tier == 2 else head])
				parts.append([_mesh(func(st): _rod(st, Vector3(0, 0.8, 0), Vector3(0, 0.88, 0), 0.017, 0.016)), "fiber" if tier == 2 else head])
		"weapon":
			if id == Items.WOOD_CLUB:
				parts.append([_mesh(func(st): _club(st)), "wood"])
			else:
				parts.append([_mesh(func(st): _rod(st, Vector3(0, -0.07, 0), Vector3(0, 0.075, 0), 0.016, 0.015)),
					"redleather" if tier == 5 else "leather"])
				parts.append([_mesh(func(st): _sword_fittings(st)), "iron" if tier <= 3 else head])
				parts.append([_mesh(func(st): _blade(st, chunky)), head])
		_:
			parts.append([_mesh(func(st): _handle(st, 0.5)), handle])
	return parts


static func _mesh(f: Callable) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	f.call(st)
	return st.commit()


## A tool handle from just below the hand to `top`, with a rounded knob at the bottom (a shovel's
## has a crossbar grip there).
static func _handle(st: SurfaceTool, top: float, grip := false) -> void:
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for p in [[-0.145, 0.0], [-0.142, 0.012], [-0.135, 0.02], [-0.12, 0.021], [-0.1, 0.0185], [0.0, 0.017],
			[top * 0.5, 0.0165], [top - 0.02, 0.0175], [top, 0.017], [top + 0.006, 0.01], [top + 0.008, 0.0]]:
		path.append(Vector3(0, p[0], 0))
		radii.append(p[1])
	_tube(st, path, radii)
	if grip:
		_rod(st, Vector3(-0.055, -0.13, 0), Vector3(0.055, -0.13, 0), 0.016, 0.016)


## A pickaxe's head: a curved bar across the top of the handle, thick in the middle, a point in
## front (-Z) and a shorter one behind.
static func _pick_head(st: SurfaceTool, chunky: float) -> void:
	var path := PackedVector3Array()
	var sections := []
	var n := 17
	for i in n:
		var s := float(i) / (n - 1) * 2.0 - 1.0  # -1 front tip .. 1 back tip
		var z := s * (0.25 if s < 0.0 else 0.19)
		var y := 0.5 + 0.03 - 0.07 * s * s
		path.append(Vector3(0, y, z))
		var taper := pow(1.0 - absf(s), 0.75)
		var w := (0.006 + 0.022 * taper) * chunky
		var h := (0.004 + 0.03 * taper) * chunky
		if i == 0 or i == n - 1:
			w = 0.0005
			h = 0.0005
		sections.append(_ellipse(w, h))
	_loft(st, path, sections, Vector3.RIGHT)


## An axe's head: thick round the handle, flaring out to a thin, curved edge in front (-Z).
static func _axe_head(st: SurfaceTool, chunky: float) -> void:
	var path := PackedVector3Array()
	var sections := []
	var pts := [[0.045, 0.012, 0.02, 0.0], [0.04, 0.02, 0.028, 0.0], [0.02, 0.024, 0.032, 0.0], [0.0, 0.024, 0.034, 0.0],
		[-0.03, 0.016, 0.038, 0.004], [-0.06, 0.009, 0.05, 0.01], [-0.09, 0.005, 0.064, 0.016], [-0.115, 0.0025, 0.074, 0.02],
		[-0.128, 0.0012, 0.07, 0.02], [-0.132, 0.0005, 0.05, 0.02]]
	for p in pts:
		path.append(Vector3(0, 0.48, p[0] * (1.0 if chunky < 1.3 else 0.85)))
		sections.append(_rrect_offset(p[1] * chunky, p[2] * (1.0 if chunky < 1.3 else 0.8), minf(p[1] * chunky, p[2]) * 0.9, p[3]))
	_loft(st, path, sections, Vector3.RIGHT)


## A shovel's spade at the top of the handle: a socket, then a dished blade with a rounded point.
static func _spade(st: SurfaceTool, chunky: float) -> void:
	_rod(st, Vector3(0, 0.56, 0), Vector3(0, 0.64, 0), 0.021, 0.024)
	var path := PackedVector3Array()
	var sections := []
	var rows := [[0.62, 0.022], [0.66, 0.06], [0.7, 0.075], [0.76, 0.078], [0.8, 0.07], [0.83, 0.05], [0.85, 0.022], [0.858, 0.004]]
	for r in rows:
		path.append(Vector3(0, r[0], 0))
		sections.append(_plate(r[1], 0.016, 0.0045 * chunky))
	_loft(st, path, sections, Vector3.RIGHT)


## A hammer's head across the top: a mallet's fat wooden drum, a lump of stone, or a metal head
## with a broad face in front.
static func _hammer_head(st: SurfaceTool, tier: int) -> void:
	if tier <= 1:
		_rod(st, Vector3(0, 0.5, 0.085), Vector3(0, 0.5, -0.085), 0.045, 0.045, Vector3.RIGHT, 0.6)
	elif tier == 2:
		_blob(st, Vector3(0, 0.5, -0.01), Vector3(0.042, 0.038, 0.07))
	else:
		var path := PackedVector3Array()
		var sections := []
		for p in [[0.075, 0.012, 0.6], [0.07, 0.019, 0.7], [0.03, 0.022, 0.6], [0.0, 0.024, 0.6], [-0.04, 0.026, 0.6],
				[-0.07, 0.028, 0.5], [-0.085, 0.027, 0.4], [-0.09, 0.02, 0.3]]:
			path.append(Vector3(0, 0.49, p[0]))
			sections.append(_rrect_offset(p[1], p[1], p[1] * p[2], 0.0))
		_loft(st, path, sections, Vector3.RIGHT)


## A sword's crossguard and pommel.
static func _sword_fittings(st: SurfaceTool) -> void:
	_rod(st, Vector3(0, 0.085, 0.072), Vector3(0, 0.085, -0.072), 0.011, 0.011, Vector3.RIGHT)
	_blob(st, Vector3(0, -0.088, 0), Vector3(0.02, 0.022, 0.02))


## A sword's blade: wide and thin, flats facing ±X, tapering to a point.
static func _blade(st: SurfaceTool, chunky: float) -> void:
	var path := PackedVector3Array()
	var sections := []
	var length := 0.68 if chunky < 1.3 else 0.56
	var n := 12
	for i in n:
		var s := float(i) / (n - 1)
		var y := 0.09 + s * length
		var w := 0.027 - 0.006 * s
		if s > 0.8:
			w *= sqrt(maxf(0.0, 1.0 - (s - 0.8) / 0.2))
		var t := (0.0065 - 0.002 * s) * (1.8 if chunky > 1.3 else 1.0)
		if i == n - 1:
			w = 0.0005
			t = 0.0005
		path.append(Vector3(0, y, 0))
		sections.append(_ellipse(t, w))
	_loft(st, path, sections, Vector3.RIGHT)


## A wooden club: a handle swelling into a heavy rounded end, with a few knots.
static func _club(st: SurfaceTool) -> void:
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for p in [[-0.14, 0.0], [-0.135, 0.014], [-0.12, 0.02], [0.0, 0.018], [0.2, 0.024], [0.36, 0.036], [0.48, 0.046],
			[0.56, 0.047], [0.6, 0.04], [0.625, 0.026], [0.635, 0.0]]:
		path.append(Vector3(0, p[0], 0))
		radii.append(p[1])
	_tube(st, path, radii)
	for k in [[0.03, 0.4, 0.4], [-0.04, 0.48, 1.9], [0.0, 0.53, 3.6], [0.04, 0.3, 5.0]]:
		var a: float = k[2]
		_blob(st, Vector3(cos(a) * 0.04, k[1], sin(a) * 0.04), Vector3(0.012, 0.016, 0.012))


## A spear's shaft from the butt to just under the head; a wooden spear's own sharpened,
## fire-hardened point.
static func _spear_shaft(st: SurfaceTool, tier: int) -> void:
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var pts := [[-0.85, 0.0], [-0.845, 0.009], [-0.835, 0.0135], [0.0, 0.0145], [0.8, 0.0135]]
	if tier == 1:
		pts.append_array([[0.9, 0.012], [0.98, 0.007], [1.04, 0.0025], [1.05, 0.0]])
	else:
		pts.append_array([[0.86, 0.012], [0.865, 0.0]])
	for p in pts:
		path.append(Vector3(0, p[0], 0))
		radii.append(p[1])
	_tube(st, path, radii)


## A leaf-shaped blade (spear head) from y0 up `length`, its flats facing ±X.
static func _leaf(st: SurfaceTool, y0: float, length: float, width: float, thick: float) -> void:
	var path := PackedVector3Array()
	var sections := []
	var n := 10
	for i in n:
		var s := float(i) / (n - 1)
		var w := width * sin(PI * pow(s, 0.75)) + 0.012 * (1.0 - s)
		var t := thick * (1.0 - s * 0.7)
		if i == n - 1:
			w = 0.0005
			t = 0.0005
		path.append(Vector3(0, y0 + s * length, 0))
		sections.append(_ellipse(t, maxf(w, 0.001)))
	_loft(st, path, sections, Vector3.RIGHT)


## An arrowhead pointing -Z, its tip at z = tip_z.
static func _arrow_head(st: SurfaceTool, base_z: float, length: float, width: float) -> void:
	var path := PackedVector3Array()
	var sections := []
	for p in [[0.0, 0.005], [0.15, width], [0.35, width * 0.95], [0.7, width * 0.55], [1.0, 0.0005]]:
		path.append(Vector3(0, 0, base_z - p[0] * length))
		sections.append(_ellipse(maxf(p[1] * 0.3, 0.0012), p[1]))
	_loft(st, path, sections, Vector3.UP)


## Feathers round the tail of an arrow: `count` thin vanes from z0 to z1 (pointing -Z).
static func _vanes(st: SurfaceTool, z0: float, z1: float, height: float, count: int) -> void:
	for k in count:
		var a := TAU * k / count + 0.4
		var out := Vector3(cos(a), sin(a), 0)
		var side := Vector3(-sin(a), cos(a), 0)
		var r0 := 0.004
		var quad := [Vector3(0, 0, z0) + out * r0, Vector3(0, 0, z1) + out * r0,
			Vector3(0, 0, z1 - 0.01) + out * (r0 + height), Vector3(0, 0, z0 + (z1 - z0) * 0.45) + out * (r0 + height * 0.55)]
		for sgn in [1.0, -1.0]:  # (both sides of the feather)
			_tri(st, quad[0], quad[1], quad[2], side * sgn, side * sgn, side * sgn)
			_tri(st, quad[0], quad[2], quad[3], side * sgn, side * sgn, side * sgn)


## A bow's limbs: a curve from tip to tip with the tips towards the archer (+Z), thick at the grip.
static func _bow_limbs(st: SurfaceTool) -> void:
	var path := PackedVector3Array()
	var sections := []
	var n := 21
	for i in n:
		var s := float(i) / (n - 1) * 2.0 - 1.0
		path.append(Vector3(0, s * 0.62, 0.12 * s * s))
		var k := 1.0 - absf(s)
		var w := 0.009 + 0.012 * k
		var t := 0.006 + 0.009 * k
		if i == 0 or i == n - 1:
			w = 0.004
			t = 0.003
		sections.append(_ellipse(w, t))
	_loft(st, path, sections, Vector3.RIGHT)


## A crossbow's stock: along Z from the butt (+Z) to the front (-Z), deeper at the butt, with a
## trigger underneath.
static func _crossbow_stock(st: SurfaceTool) -> void:
	var path := PackedVector3Array()
	var sections := []
	for p in [[0.25, 0.024, 0.05, -0.035], [0.22, 0.026, 0.058, -0.04], [0.12, 0.022, 0.04, -0.025], [0.04, 0.018, 0.024, -0.006],
			[-0.1, 0.017, 0.02, 0.0], [-0.26, 0.019, 0.022, 0.0], [-0.3, 0.017, 0.02, 0.0], [-0.31, 0.01, 0.012, 0.0]]:
		path.append(Vector3(0, p[3], p[0]))
		sections.append(_rrect_offset(p[1], p[2], minf(p[1], p[2]) * 0.6, 0.0))
	_loft(st, path, sections, Vector3.RIGHT)
	_rod(st, Vector3(0, -0.02, 0.05), Vector3(0, -0.06, 0.065), 0.006, 0.005)


## A crossbow's prod (its bow) across the front, the tips curving back.
static func _crossbow_prod(st: SurfaceTool) -> void:
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var n := 15
	for i in n:
		var s := float(i) / (n - 1) * 2.0 - 1.0
		path.append(Vector3(s * 0.3, 0.02, -0.29 + 0.045 * s * s))
		radii.append(0.0035 if i == 0 or i == n - 1 else 0.007 + 0.006 * (1.0 - absf(s)))
	_tube(st, path, radii, Vector3.UP, Vector2(1.0, 0.7))


## Cord wound round the joint of a stone head and its handle.
static func _lashing(st: SurfaceTool, y: float, height: float) -> void:
	_rod(st, Vector3(0, y - height, 0), Vector3(0, y - height * 0.35, 0), 0.021, 0.021, Vector3.RIGHT, 0.4)
	_rod(st, Vector3(0, y + height * 0.35, 0), Vector3(0, y + height, 0), 0.021, 0.021, Vector3.RIGHT, 0.4)


# ---------------------------------------------------------------- building blocks

## A straight round rod from a to b (radius ra to rb) with rounded ends (`round`: how far the
## end bulges, as a part of the radius).
static func _rod(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, side := Vector3.RIGHT, round := 1.0) -> void:
	var d := (b - a).normalized()
	var ca := a + d * ra * round
	var cb := b - d * rb * round
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var steps := 4
	for k in steps:
		var phi := PI * 0.5 * k / steps  # 0 at the tip
		path.append(ca - d * ra * round * cos(phi))
		radii.append(ra * sin(phi))
	for k in 5:
		var f := float(k) / 4.0
		path.append(ca.lerp(cb, f))
		radii.append(lerpf(ra, rb, f))
	for k in range(1, steps + 1):
		var phi := PI * 0.5 * (steps - k) / steps
		path.append(cb + d * rb * round * cos(phi))
		radii.append(rb * sin(phi))
	_tube(st, path, radii, side if absf(d.dot(side)) < 0.9 else Vector3.UP)


## A rounded lump (an ellipsoid) with radii r.
static func _blob(st: SurfaceTool, c: Vector3, r: Vector3) -> void:
	var path := PackedVector3Array()
	var sections := []
	var n := 9
	for i in n:
		var a := PI * float(i) / (n - 1)
		path.append(c + Vector3(0, -r.y * cos(a), 0))
		var k := sin(a)
		sections.append(_ellipse(maxf(r.x * k, 0.0003), maxf(r.z * k, 0.0003)))
	_loft(st, path, sections, Vector3.RIGHT)


## A round tube along a path, radius radii[i] at path[i] (`squash` makes it oval).
static func _tube(st: SurfaceTool, path: PackedVector3Array, radii: PackedFloat32Array, side := Vector3.RIGHT, squash := Vector2.ONE) -> void:
	var sections := []
	for r in radii:
		var rr := maxf(r, 0.0003)
		sections.append(_ellipse(rr * squash.x, rr * squash.y))
	_loft(st, path, sections, side)


## Sections (2D outlines, all with the same number of points) placed along a path: each one's x
## along `side` (made square to the path), its y across.
static func _loft(st: SurfaceTool, path: PackedVector3Array, sections: Array, side: Vector3) -> void:
	var rings := []
	for i in path.size():
		var t := _tangent(path, i)
		var u := side - t * side.dot(t)
		if u.length() < 0.01:
			u = Vector3.UP - t * t.y
		u = u.normalized()
		var v := t.cross(u)
		var ring := PackedVector3Array()
		for q in sections[i]:
			ring.append(path[i] + u * q.x + v * q.y)
		rings.append(ring)
	_surface(st, rings, path)


static func _tangent(path: PackedVector3Array, i: int) -> Vector3:
	var a := path[maxi(i - 1, 0)]
	var b := path[mini(i + 1, path.size() - 1)]
	var t := b - a
	return t.normalized() if t.length() > 1e-6 else Vector3.UP


## A smooth surface through closed rings of points (normals from the grid, pointing away from each
## ring's centre); an open end gets a flat cap.
static func _surface(st: SurfaceTool, rings: Array, centers: PackedVector3Array) -> void:
	var nr := rings.size()
	var n: int = (rings[0] as PackedVector3Array).size()
	var nrm := []
	for i in nr:
		var ring: PackedVector3Array = rings[i]
		var prev: PackedVector3Array = rings[maxi(i - 1, 0)]
		var next: PackedVector3Array = rings[mini(i + 1, nr - 1)]
		var row := PackedVector3Array()
		for j in n:
			var da := ring[(j + 1) % n] - ring[(j - 1 + n) % n]
			var dl := next[j] - prev[j]
			var c := da.cross(dl)
			var out := ring[j] - centers[i]
			if c.length() < 1e-9:
				# A ring shrunk to a point (a tip): the normal is the way the path goes on.
				c = (centers[i] - centers[maxi(i - 1, 0)]) if i > 0 else (centers[0] - centers[1])
				if out.length() > 1e-6:
					c += out.normalized() * c.length() * 0.3
			elif out.length() > 1e-6 and c.dot(out) < 0.0:
				c = -c
			row.append(c.normalized() if c.length() > 1e-9 else Vector3.UP)
		nrm.append(row)
	for i in nr - 1:
		var a: PackedVector3Array = rings[i]
		var b: PackedVector3Array = rings[i + 1]
		var na: PackedVector3Array = nrm[i]
		var nb: PackedVector3Array = nrm[i + 1]
		for j in n:
			var j2 := (j + 1) % n
			_tri(st, a[j], b[j], b[j2], na[j], nb[j], nb[j2])
			_tri(st, a[j], b[j2], a[j2], na[j], nb[j2], na[j2])
	for end in [0, nr - 1]:
		var ring: PackedVector3Array = rings[end]
		if (ring[0] - centers[end]).length() < 0.0006:
			continue
		var cn := (centers[0] - centers[1]).normalized() if end == 0 else (centers[nr - 1] - centers[nr - 2]).normalized()
		for j in n:
			_tri(st, centers[end], ring[j], ring[(j + 1) % n], cn, cn, cn)


## Godot draws a triangle's front side where its corners go round clockwise: put each one's
## corners in the order that turns its front to the side its normals point to.
const FRONT_SIGN := -1.0


static func _tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, n0: Vector3, n1: Vector3, n2: Vector3) -> void:
	var g := (p1 - p0).cross(p2 - p0)
	if g.dot(n0 + n1 + n2) * FRONT_SIGN < 0.0:
		var t := p1
		p1 = p2
		p2 = t
		var tn := n1
		n1 = n2
		n2 = tn
	st.set_normal(n0)
	st.add_vertex(p0)
	st.set_normal(n1)
	st.add_vertex(p1)
	st.set_normal(n2)
	st.add_vertex(p2)


static func _ellipse(a: float, b: float, n := SIDES) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n:
		var t := TAU * k / n
		out.append(Vector2(a * cos(t), b * sin(t)))
	return out


## A rounded rectangle (half sizes w, h; corner radius r), moved by dy across, as SIDES points.
static func _rrect_offset(w: float, h: float, r: float, dy: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	r = minf(r, minf(w, h))
	var per := 3  # (SIDES / 4 points on each corner)
	var corners := [Vector2(w - r, h - r), Vector2(-(w - r), h - r), Vector2(-(w - r), -(h - r)), Vector2(w - r, -(h - r))]
	for c in 4:
		for k in per:
			var t := PI * 0.5 * (c + float(k) / (per - 1))
			out.append(corners[c] + Vector2(cos(t), sin(t)) * r + Vector2(0, dy))
	return out


## A shallow dished plate (a spade's cross-section): half width w, dish depth d, thickness t.
static func _plate(w: float, d: float, t: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var half := 6  # (SIDES / 2 on each face)
	for k in half:
		var x := w * cos(PI * float(k) / (half - 1))
		out.append(Vector2(x, d * (1.0 - pow(x / maxf(w, 1e-4), 2.0)) * 0.5 + t))
	for k in half:
		var x := w * cos(PI * (1.0 - float(k) / (half - 1)))
		out.append(Vector2(x, d * (1.0 - pow(x / maxf(w, 1e-4), 2.0)) * 0.5 - t))
	return out


# ---------------------------------------------------------------- icons

## Draw every model's icon once (a SubViewport with all of them in a grid, one frame), into
## `icons`. Only where something is drawn (game.gd: not on a server or headless); until then,
## and otherwise, the painted pixel icons stay.
static func render_icons(parent: Node) -> void:
	if _icons_started:
		return
	_icons_started = true
	var ids := []
	for id in Items.DATA:
		if has_model(int(id)):
			ids.append(int(id))
	var rows := ceili(ids.size() / float(ICON_COLS))
	var vp := SubViewport.new()
	vp.size = Vector2i(ICON_COLS * ICON_PX, rows * ICON_PX)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	parent.add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = rows * 1.0
	cam.position = Vector3(ICON_COLS * 0.5, -rows * 0.5, 10)
	vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, -0.5, 0)
	sun.light_energy = 1.3
	vp.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = 0.9
	# A sky for the metals to shine with (the background itself stays clear).
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.45, 0.55, 0.7)
	sm.sky_horizon_color = Color(0.75, 0.75, 0.78)
	sm.ground_bottom_color = Color(0.25, 0.22, 0.2)
	sm.ground_horizon_color = Color(0.5, 0.48, 0.45)
	sky.sky_material = sm
	e.sky = sky
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	for k in ids.size():
		var holder := Node3D.new()
		holder.position = Vector3(k % ICON_COLS + 0.5, -floorf(k / float(ICON_COLS)) - 0.5, 0)
		vp.add_child(holder)
		var m := make(ids[k])
		var pose := Node3D.new()
		holder.add_child(pose)
		pose.add_child(m)
		# Seen from the side, leaning so the head (or point) is at the top right. (Handles point
		# up +Y; arrows, bolts and the crossbow point -Z: turned the other way first.)
		var tt := Items.tool_type(ids[k])
		var ahead := tt == "crossbow" or Items.info(ids[k]).has("ammo_of")
		var turn := Basis(Vector3.UP, PI * 0.5)
		if tt == "crossbow":
			turn = Basis(Vector3.UP, -PI * 0.5)  # (its front to the right)
		elif ahead:
			turn = turn * Basis(Vector3.RIGHT, PI * 0.5)  # (its point up first, like a handle)
		pose.basis = Basis(Vector3.FORWARD, deg_to_rad(20.0 if tt == "crossbow" else 45.0)) * Basis(Vector3.RIGHT, 0.35) * turn
		if ArmorModels.has_model(ids[k]):
			pose.basis = Basis(Vector3.RIGHT, 0.3) * Basis(Vector3.UP, PI + 0.55)  # (armor: its front, from a little above)
		var box := _bounds(m, pose.transform)
		var s := 0.94 / maxf(box.size.x, box.size.y)
		holder.scale = Vector3.ONE * s
		pose.position = -box.get_center()
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	for k in ids.size():
		var r := Rect2i((k % ICON_COLS) * ICON_PX, floori(k / float(ICON_COLS)) * ICON_PX, ICON_PX, ICON_PX)
		var cell := img.get_region(r)
		cell.generate_mipmaps()
		icons[ids[k]] = ImageTexture.create_from_image(cell)
	vp.queue_free()


## The bounds of a model's meshes under `xf`.
static func _bounds(m: Node3D, xf: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	for c in m.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and c.visible:
			var b: AABB = (xf * (c as Node3D).transform) * (c as MeshInstance3D).mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
	return box
