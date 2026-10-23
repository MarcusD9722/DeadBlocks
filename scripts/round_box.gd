class_name RoundBox
extends RefCounted
## Boxes with rounded edges for the creature and player models (one shared mesh per size).
## Thin parts (eyes, mouths) stay plain boxes.

const SEG := 3  # steps around each rounded edge

static var _cache := {}


static func mesh(size: Vector3) -> Mesh:
	var key := size.snapped(Vector3(0.001, 0.001, 0.001))
	if _cache.has(key):
		return _cache[key]
	var m: Mesh
	var r := minf(minf(size.x, size.y), size.z) * 0.22
	if r < 0.012:
		var bm := BoxMesh.new()
		bm.size = size
		m = bm
	else:
		m = _build(size * 0.5, r)
	_cache[key] = m
	return m


## Grid lines along one axis of half-size h: tighter around the rounded ends.
static func _coords(h: float, r: float) -> PackedFloat32Array:
	var c := PackedFloat32Array()
	for k in SEG + 1:
		c.append(-(h - r) - r * cos(PI * 0.5 * k / SEG))
	for k in SEG + 1:
		c.append((h - r) + r * sin(PI * 0.5 * k / SEG))
	return c


static func _build(h: Vector3, r: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var inner := h - Vector3(r, r, r)
	var cs := [_coords(h.x, r), _coords(h.y, r), _coords(h.z, r)]
	# Each face: the axis it faces along, its sign, and the two axes across it.
	for f in 6:
		var ax := f >> 1
		var sgn := 1.0 if f & 1 == 0 else -1.0
		var ua := (ax + 1) % 3
		var va := (ax + 2) % 3
		var cu: PackedFloat32Array = cs[ua]
		var cv: PackedFloat32Array = cs[va]
		var base := verts.size()
		for j in cv.size():
			for i in cu.size():
				var p := Vector3.ZERO
				p[ax] = h[ax] * sgn
				p[ua] = cu[i]
				p[va] = cv[j]
				var q := p.clamp(-inner, inner)
				var n := (p - q).normalized()
				verts.append(q + n * r)
				norms.append(n)
		var nu := cu.size()
		for j in cv.size() - 1:
			for i in nu - 1:
				var a := base + i + j * nu
				var b := a + 1
				var c := a + nu
				var d := c + 1
				# Clockwise seen from outside (Godot's front faces).
				if sgn > 0.0:
					idx.append_array(PackedInt32Array([a, d, b, a, c, d]))
				else:
					idx.append_array(PackedInt32Array([a, b, d, a, d, c]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am
