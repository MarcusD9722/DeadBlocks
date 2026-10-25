class_name ArmorModels
extends RefCounted
## Armor as 3D models (M4.5, client only): the item on its own (its icon is drawn from it, like a
## tool's, see ToolModels), and the pieces a survivor wears (other players, and your own picture
## on the Armor tab). Made of smooth shapes with ToolModels' primitives and materials; the tier
## shows in the material: padded cloth, leather, iron, steel, Blood Steel.
##
## The worn pieces are fitted to the survivor models (assets/models/survivors, all built alike):
## each hangs on a bone (Rig.attach) in the model's own coordinates, where it faces +Z, the head
## spans about y 0.98..1.50 and the legs are short.

## A piece's material by tier.
const TIER_MAT := ["fiber", "leather", "iron", "steel", "blood"]
## Worn pieces: [bone, mirrored for the other side's bone or ""].
const BONES := [["Head", ""], ["Torso", ""], ["Hips", ""], ["LowerLeg.L", "LowerLeg.R"], ["Foot.L", "Foot.R"]]

static var _parts := {}
static var _worn := {}


static func has_model(id: int) -> bool:
	return Items.armor_slot(id) >= 0


## The item model's parts for ToolModels.make: [[mesh, material], ...]. Laid out like a tool's,
## upright, front towards -Z.
static func item_parts(id: int) -> Array:
	var t := Items.armor_tier(id)
	var mat: String = TIER_MAT[t]
	var parts := []
	match Items.armor_slot(id):
		0:
			parts.append([ToolModels._mesh(func(st): _dome(st, Vector3.ZERO, Vector3(0.13, 0.12, 0.14), t)), mat])
			if t >= 2:
				parts.append([ToolModels._mesh(func(st): _band(st, Vector3(0, 0.005, 0), Vector3(0.137, 0.028, 0.147))), mat])
				parts.append([ToolModels._mesh(func(st): _crest(st, Vector3(0, 0.0, 0), 0.13, 0.12, 0.14)), mat])
			elif t == 1:
				parts.append([ToolModels._mesh(func(st): _visor(st, Vector3(0, 0.01, -0.12), 0.1)), "darkwood"])
		1:
			parts.append([ToolModels._mesh(func(st): _shell(st, Vector3.ZERO, 0.0, 0.34, 0.17, 0.12, 0.2)), mat])
			if t >= 2:
				for sx in [-1.0, 1.0]:
					parts.append([ToolModels._mesh(func(st): ToolModels._blob(st, Vector3(0.19 * sx, 0.31, 0), Vector3(0.07, 0.045, 0.1))), mat])
		2:
			parts.append([ToolModels._mesh(func(st): _shell(st, Vector3(0, 0.29, 0), 0.0, 0.07, 0.15, 0.09, 0.15)), mat])
			for sx in [-1.0, 1.0]:
				parts.append([ToolModels._mesh(func(st): ToolModels._rod(st, Vector3(0.075 * sx, 0.32, 0), Vector3(0.105 * sx, 0.0, 0.01), 0.068, 0.044)), mat])
		_:
			for sx in [-1.0, 1.0]:
				parts.append([ToolModels._mesh(func(st): _boot(st, Vector3(0.07 * sx, 0, 0), 1.0)), mat])
	return parts


## The pieces a survivor wears for a slot and tier: [[mesh, material, bone index in BONES, mirrored], ...].
static func worn_parts(slot: int, tier: int) -> Array:
	var key := "%d/%d" % [slot, tier]
	if _worn.has(key):
		return _worn[key]
	var mat: String = TIER_MAT[tier]
	var out := []
	match slot:
		0:
			# The rim above the eyes (they are at about y 1.2), over the forehead to the back.
			var c := Vector3(0, 1.31, -0.145)
			var r := Vector3(0.29, 0.24 if tier > 0 else 0.27, 0.29)
			out.append([ToolModels._mesh(func(st): _dome(st, c, r, tier)), mat, 0, false])
			if tier >= 2:
				out.append([ToolModels._mesh(func(st): _band(st, c + Vector3(0, 0.0, 0), Vector3(r.x + 0.012, 0.045, r.z + 0.012))), mat, 0, false])
				out.append([ToolModels._mesh(func(st): _crest(st, c, r.x, r.y, r.z)), mat, 0, false])
			elif tier == 1:
				out.append([ToolModels._mesh(func(st): _visor(st, c + Vector3(0, 0.0, r.z - 0.02), 0.26)), "darkwood", 0, false])
		1:
			# Round the jacket: the survivors' chests reach z 0.09 at the front and -0.41 at the back.
			out.append([ToolModels._mesh(func(st): _shell(st, Vector3(0, 0.63, -0.18), 0.0, 0.37, 0.275, 0.275, 0.295)), mat, 1, false])
			if tier >= 2:
				for sx in [-1.0, 1.0]:
					out.append([ToolModels._mesh(func(st): ToolModels._blob(st, Vector3(0.27 * sx, 0.97, -0.16), Vector3(0.12, 0.07, 0.19))), mat, 1, false])
		2:
			out.append([ToolModels._mesh(func(st): _shell(st, Vector3(0, 0.41, -0.14), 0.0, 0.24, 0.29, 0.215, 0.29)), mat, 2, false])
			out.append([ToolModels._mesh(func(st): ToolModels._rod(st, Vector3(0.14, 0.29, -0.135), Vector3(0.143, 0.05, -0.13), 0.125, 0.115)), mat, 3, false])
			out.append([ToolModels._mesh(func(st): ToolModels._rod(st, Vector3(-0.14, 0.29, -0.135), Vector3(-0.143, 0.05, -0.13), 0.125, 0.115)), mat, 3, true])
		_:
			for sx in [1.0, -1.0]:
				out.append([ToolModels._mesh(func(st): _worn_boot(st, sx)), mat, 4, sx < 0.0])
	_worn[key] = out
	return out


## Put the armor (`tiers`: the tier worn per slot, -1 none) on a survivor: pieces on its bones,
## made once per rig and slot and swapped when the tier changes.
static func dress(rig: Rig, tiers: Array) -> void:
	if rig == null or rig.skeleton == null:
		return
	var holders: Dictionary = rig.get_meta("armor", {})
	var shown: Array = rig.get_meta("armor_tiers", [-1, -1, -1, -1])
	if not rig.has_meta("armor"):
		rig.set_meta("armor", holders)
	for slot in 4:
		var t := int(tiers[slot]) if slot < tiers.size() else -1
		if t == int(shown[slot]):
			continue
		for n in holders.get(slot, []):
			(n as Node).queue_free()
		holders[slot] = []
		if t >= 0:
			for part in worn_parts(slot, t):
				var bones: Array = BONES[part[2]]
				var bone: String = bones[1] if part[3] else bones[0]
				var frame: Node3D = rig.attach(bone)
				var mi := MeshInstance3D.new()
				mi.mesh = part[0]
				mi.material_override = ToolModels.material(part[1])
				frame.add_child(mi)
				holders[slot].append(frame.get_parent())  # (the BoneAttachment3D holding it)
		shown[slot] = t
	rig.set_meta("armor_tiers", shown)


# ------------------------------------------------------------ shapes

## A helmet's dome over centre c (its rim there), radii r; a padded hood (tier 0) is rounder and
## comes lower at the back.
static func _dome(st: SurfaceTool, c: Vector3, r: Vector3, tier: int) -> void:
	var path := PackedVector3Array()
	var sections := []
	var n := 8
	var low := 0.35 if tier == 0 else 0.12  # how far below the rim it starts
	for i in n + 1:
		var a := -low + (PI * 0.5 + low) * float(i) / n  # from below the rim to the top
		var y := sin(a)
		var k := cos(a)
		path.append(c + Vector3(0, r.y * y, 0))
		sections.append(_ring(maxf(r.x * k, 0.0004), maxf(r.z * k, 0.0004)))
	ToolModels._loft(st, path, sections, Vector3.RIGHT)


## A band round a helmet's rim (half height r.y).
static func _band(st: SurfaceTool, c: Vector3, r: Vector3) -> void:
	var path := PackedVector3Array([c - Vector3(0, r.y, 0), c - Vector3(0, r.y * 0.4, 0), c + Vector3(0, r.y * 0.4, 0), c + Vector3(0, r.y, 0)])
	var sections := [_ring(r.x - 0.006, r.z - 0.006), _ring(r.x, r.z), _ring(r.x, r.z), _ring(r.x - 0.006, r.z - 0.006)]
	ToolModels._loft(st, path, sections, Vector3.RIGHT)


## A ridge over a metal helmet, front to back.
static func _crest(st: SurfaceTool, c: Vector3, rx: float, ry: float, rz: float) -> void:
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 9:
		var a := PI * float(i) / 8.0
		path.append(c + Vector3(0, ry * sin(a) + 0.004, -rz * cos(a)) * Vector3(1, 1.02, 1.02))
		radii.append(rx * 0.07 * sin(a) + 0.002)
	ToolModels._tube(st, path, radii, Vector3.RIGHT, Vector2(1.0, 0.6))


## A leather cap's short visor at the front (z+), width w.
static func _visor(st: SurfaceTool, c: Vector3, w: float) -> void:
	var path := PackedVector3Array([c + Vector3(-w * 0.5, 0, 0), c + Vector3(0, 0, w * 0.1), c + Vector3(w * 0.5, 0, 0)])
	var sections := [_ring(w * 0.12, 0.006), _ring(w * 0.2, 0.008), _ring(w * 0.12, 0.006)]
	ToolModels._loft(st, path, sections, Vector3.BACK)


## A body shell (chest piece, the hips of leggings) from y0 up to y1 around centre c: a rounded
## box of half width w and half depth d, a little wider at the top (shoulders) by `flare`.
static func _shell(st: SurfaceTool, c: Vector3, y0: float, y1: float, w: float, d: float, wtop: float) -> void:
	var path := PackedVector3Array()
	var sections := []
	var n := 6
	for i in n + 1:
		var f := float(i) / n
		path.append(c + Vector3(0, lerpf(y0, y1, f), 0))
		var ww := lerpf(w, wtop, f * f)
		var dd := d * (1.0 - 0.15 * f * f)
		var shrink := 0.82 if i == 0 or i == n else 1.0  # (rounded at both ends)
		sections.append(_rrect(ww * shrink, dd * shrink, minf(ww, dd) * 0.6))
	ToolModels._loft(st, path, sections, Vector3.RIGHT)


## A boot: the shaft round the ankle and the foot forward (+Z), size s (1 = the item's).
static func _boot(st: SurfaceTool, c: Vector3, s: float) -> void:
	ToolModels._rod(st, c + Vector3(0, 0.055, -0.02) * s, c + Vector3(0, 0.12, -0.03) * s, 0.04 * s, 0.042 * s)
	ToolModels._blob(st, c + Vector3(0, 0.03, 0.035) * s, Vector3(0.042, 0.032, 0.085) * s)


## A worn boot round a survivor's foot (side sx: 1 left, -1 right): the foot reaches from z -0.22
## to 0.12 and up to y 0.1.
static func _worn_boot(st: SurfaceTool, sx: float) -> void:
	ToolModels._blob(st, Vector3(0.143 * sx, 0.05, -0.045), Vector3(0.1, 0.078, 0.2))
	ToolModels._rod(st, Vector3(0.143 * sx, 0.07, -0.14), Vector3(0.143 * sx, 0.2, -0.14), 0.11, 0.115)


## An oval as ToolModels' sections are (x across, y the other way).
static func _ring(a: float, b: float) -> PackedVector2Array:
	return ToolModels._ellipse(a, b)


static func _rrect(w: float, h: float, r: float) -> PackedVector2Array:
	return ToolModels._rrect_offset(w, h, r, 0.0)
