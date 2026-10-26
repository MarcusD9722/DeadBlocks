class_name MeshBuf
extends RefCounted
## A chunk's picture as it is built on a worker thread (world.gd _build): cubes, boxes, ramps,
## round log trunks, plants and leaves as vertex arrays, the smooth ground (SmoothMesher), and
## the models to put in it (trees, decor). Also the blocks' icons (ItemModels). Moved out of
## world.gd in M4.6.

const CORNERS := [
	[Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0)],
	[Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)],
]
const NORMALS := [Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
const DIRS := [Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

## Cubes, boxes and log trunks: uv across each face, uv2 = (Tex block layer, 1 for a round
## trunk), the colour's alpha is the sky light (SmoothMesher.sky_at).
var verts := PackedVector3Array()
var norms := PackedVector3Array()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var cols := PackedColorArray()
var idx := PackedInt32Array()
## Plants (crosses): the pixel atlas.
var p_verts := PackedVector3Array()
var p_norms := PackedVector3Array()
var p_uvs := PackedVector2Array()
var p_cols := PackedColorArray()
var p_idx := PackedInt32Array()
## Leaves: leafy faces a little outside the block and two planes through it.
var l_verts := PackedVector3Array()
var l_norms := PackedVector3Array()
var l_uvs := PackedVector2Array()
var l_cols := PackedColorArray()
var l_idx := PackedInt32Array()
var faces := PackedVector3Array()
## Drawn chunks: the ground as it is drawn (rounded ground, solid cubes, boxes and trunks),
## for standing creatures on what the player sees (VISUAL_LAYER, see game.gd).
var vfaces := PackedVector3Array()
var lights: Array = []
var beacons: Array = []
## Natural trees rooted in this chunk (M4.6): [Trees model, transform in the chunk, root],
## drawn as models; their logs and leaves are left out of the picture (_without_trees).
var trees: Array = []
## Decor rooted in this chunk (M4.6): [Decor model, transform in the chunk].
var decor: Array = []
## The smooth ground (SmoothMesher): material weights in the colour, uv, uv2.x and custom0, sky
## in uv2.y.
var t_verts := PackedVector3Array()
var t_norms := PackedVector3Array()
var t_cols := PackedColorArray()
var t_uv := PackedVector2Array()
var t_uv2 := PackedVector2Array()
## Snow and crystal weights (M4.7): 4 floats per vertex (ARRAY_CUSTOM0, RGBA float).
var t_custom := PackedFloat32Array()
var t_idx := PackedInt32Array()

static func face_uv(dir: int, c: Vector3) -> Vector2:
	if dir < 2:
		return Vector2(c.x, c.z)
	if dir < 4:
		return Vector2(c.z, 1.0 - c.y)
	return Vector2(c.x, 1.0 - c.y)

## A cube's face. `joined` (M4.6): the edges where the same face goes on in the next block
## (bits -x, +x, -y, +y, -z, +z), drawn without the rounded edge so a wall looks like one.
func face(dir: int, x: int, y: int, z: int, tile: int, solid: bool, lit := 1.0, joined := 0) -> void:
	box_face(dir, Vector3(x, y, z), Vector3.ZERO, Vector3.ONE, tile, solid, lit, joined)

## One face of the box lo..hi inside the cell at o, showing the whole picture of `tile`.
func box_face(dir: int, o: Vector3, lo: Vector3, hi: Vector3, tile: int, solid: bool, lit: float, joined := 0) -> void:
	var base := verts.size()
	var cs: Array = CORNERS[dir]
	var n: Vector3 = NORMALS[dir]
	var col := Color(1, 1, 1, lit)
	# uv2.y: 0 a plain face, 1 a round trunk, below 0 the joined edges (blocks.gdshader).
	var layer := Vector2(Tex.block_layer(tile), -float(joined + 1) / 64.0 if joined > 0 else 0.0)
	var ext := hi - lo
	for k in 4:
		var c: Vector3 = cs[k]
		verts.append(o + lo + c * ext)
		norms.append(n)
		cols.append(col)
		uvs.append(face_uv(dir, c))
		uv2s.append(layer)
	idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	if solid:
		for k in [0, 1, 2, 0, 2, 3]:
			vfaces.append(verts[base + k])

## An SH_BOX block: all six faces of the box lo..hi inside the cell ([top, side, bottom] tiles).
func box(x: int, y: int, z: int, tl: Array, lo: Vector3, hi: Vector3, solid: bool, lit := 1.0) -> void:
	for dir in 6:
		var tile: int = tl[0] if dir == 0 else (tl[2] if dir == 1 else tl[1])
		box_face(dir, Vector3(x, y, z), lo, hi, tile, solid, lit)

## A ramp: a wedge rising towards facing f (Blocks.rot_point), with the side tile on every face.
func ramp(x: int, y: int, z: int, tl: Array, f: int, lit: float) -> void:
	var o := Vector3(x, y, z)
	var col := Color(1, 1, 1, lit)
	var layer := Vector2(Tex.block_layer(tl[1]), 0.0)
	var quads := [
		[[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)], Vector3.DOWN],
		[[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)], Vector3.BACK],
		[[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)], Vector3(0, 1, -1).normalized()],
	]
	for q in quads:
		var base := verts.size()
		var n: Vector3 = Blocks.rot_point(q[1] + Vector3(0.5, 0, 0.5), f) - Vector3(0.5, 0, 0.5)
		for c in q[0]:
			verts.append(o + Blocks.rot_point(c, f))
			norms.append(n)
			cols.append(col)
			uvs.append(Vector2(c.x, 1.0 - (c.z if q[1] != Vector3.BACK else c.y)))
			uv2s.append(layer)
		_wind_outward(base, n)
	for side in [[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3.LEFT], [Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3.RIGHT]]:
		var base := verts.size()
		var n: Vector3 = Blocks.rot_point(side[3] + Vector3(0.5, 0, 0.5), f) - Vector3(0.5, 0, 0.5)
		for k in 3:
			var c: Vector3 = side[k]
			verts.append(o + Blocks.rot_point(c, f))
			norms.append(n)
			cols.append(col)
			uvs.append(Vector2(c.z, 1.0 - c.y))
			uv2s.append(layer)
		_tri_outward(base, n)

## A log as a round (eight-sided) trunk, with a cut end where no log continues it.
func trunk(x: int, y: int, z: int, tl: Array, cap_top: bool, cap_bottom: bool, lit: float, lit_top: float) -> void:
	const R := 0.42
	const SIDES := 8
	var c := Vector3(x + 0.5, y, z + 0.5)
	var col := Color(1, 1, 1, lit)
	var side_layer := Vector2(Tex.block_layer(tl[1]), 1.0)
	var end_layer := Vector2(Tex.block_layer(tl[0]), 1.0)
	var ring: Array[Vector3] = []
	for k in SIDES + 1:
		var a := (k + 0.5) * TAU / SIDES
		ring.append(Vector3(cos(a), 0.0, sin(a)))
	for k in SIDES:
		var base := verts.size()
		var a: Vector3 = ring[k]
		var b: Vector3 = ring[k + 1]
		var pts := [c + a * R, c + b * R, c + b * R + Vector3.UP, c + a * R + Vector3.UP]
		var ns := [a, b, b, a]
		var us := [k * 2.0 / SIDES, (k + 1) * 2.0 / SIDES]
		var quad_uv := [Vector2(us[0], 1), Vector2(us[1], 1), Vector2(us[1], 0), Vector2(us[0], 0)]
		for j in 4:
			verts.append(pts[j])
			norms.append(ns[j])
			cols.append(col)
			uvs.append(quad_uv[j])
			uv2s.append(side_layer)
		_wind_outward(base, (a + b).normalized())
	for top in [true, false]:
		if (top and not cap_top) or (not top and not cap_bottom):
			continue
		var yy := 1.0 if top else 0.0
		var n := Vector3.UP if top else Vector3.DOWN
		var ccol := Color(1, 1, 1, lit_top if top else lit)
		for k in SIDES:
			var base := verts.size()
			var pts := [c + Vector3(0, yy, 0), c + ring[k] * R + Vector3(0, yy, 0), c + ring[k + 1] * R + Vector3(0, yy, 0)]
			for p in pts:
				verts.append(p)
				norms.append(n)
				cols.append(ccol)
				uvs.append(Vector2(0.5 + (p.x - c.x) * 0.5 / R * 0.9, 0.5 + (p.z - c.z) * 0.5 / R * 0.9))
				uv2s.append(end_layer)
			_tri_outward(base, n)

## Index a quad (4 verts from base) so it faces `out` (Godot: front faces wind clockwise).
func _wind_outward(base: int, out: Vector3) -> void:
	var a := verts[base]
	var b := verts[base + 1]
	var c := verts[base + 2]
	var order := [0, 1, 2, 0, 2, 3]
	if (b - a).cross(c - a).dot(out) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for k in order:
		idx.append(base + k)
		vfaces.append(verts[base + k])

func _tri_outward(base: int, out: Vector3) -> void:
	var a := verts[base]
	var b := verts[base + 1]
	var c := verts[base + 2]
	var order := [0, 1, 2] if (b - a).cross(c - a).dot(out) <= 0.0 else [0, 2, 1]
	for k in order:
		idx.append(base + k)
		vfaces.append(verts[base + k])

func cross(x: int, y: int, z: int, tile: int, lit := 1.0) -> void:
	var o := Vector3(x, y, z)
	var tu := float(tile % 8) * 0.125
	@warning_ignore("integer_division")
	var tv := float(tile / 8) * 0.125
	var col := Color(0.95, 0.95, 0.95, lit)
	var pairs := [[Vector3(0.15, 0, 0.15), Vector3(0.85, 0, 0.85)], [Vector3(0.85, 0, 0.15), Vector3(0.15, 0, 0.85)]]
	for pr in pairs:
		var a: Vector3 = pr[0]
		var b: Vector3 = pr[1]
		var p := [o + a, o + b, o + b + Vector3.UP, o + a + Vector3.UP]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for side in 2:
			var base := p_verts.size()
			var order := [0, 1, 2, 3] if side == 0 else [0, 3, 2, 1]
			for k in order:
				p_verts.append(p[k])
				p_norms.append(Vector3.UP)
				p_cols.append(col)
				var q: Vector2 = uv[k]
				p_uvs.append(Vector2(tu + 0.002 + q.x * 0.121, tv + 0.002 + q.y * 0.121))
			p_idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

## A leaf block: leafy faces a little outside the block (`open` = the directions with no
## leaves next to it), and two planes through it unless leaves surround it. Pictures follow
## world positions, so neighbouring blocks continue each other.
func leaf(x: int, y: int, z: int, open: Array, lit: float) -> void:
	const OUT := 0.14
	var o := Vector3(x, y, z)
	var col := Color(1, 1, 1, lit)
	for dir in open:
		var n: Vector3 = NORMALS[dir]
		var cs: Array = CORNERS[dir]
		var base := l_verts.size()
		for k in 4:
			var c: Vector3 = cs[k]
			# Out from the block, and a little wider so the edges overlap their neighbours'.
			var p: Vector3 = o + c + n * OUT + (c - Vector3(0.5, 0.5, 0.5)) * (Vector3.ONE - n.abs()) * 0.24
			l_verts.append(p)
			l_norms.append(n)
			l_cols.append(col)
			l_uvs.append(_leaf_uv(dir, p))
		l_idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	if open.is_empty():
		return
	for pr in [[Vector3(0, 0, 0), Vector3(1, 0, 1)], [Vector3(1, 0, 0), Vector3(0, 0, 1)]]:
		var a: Vector3 = o + pr[0]
		var b: Vector3 = o + pr[1]
		var base := l_verts.size()
		var pts := [a + Vector3(0, -0.1, 0), b + Vector3(0, -0.1, 0), b + Vector3(0, 1.1, 0), a + Vector3(0, 1.1, 0)]
		for k in 4:
			var p: Vector3 = pts[k]
			l_verts.append(p)
			l_norms.append(Vector3(0.3, 0.9, 0.3).normalized())
			l_cols.append(col)
			l_uvs.append(Vector2((p.x + p.z) * 0.35, -p.y * 0.5))
		l_idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

static func _leaf_uv(dir: int, p: Vector3) -> Vector2:
	if dir < 2:
		return Vector2(p.x, p.z) * 0.5
	if dir < 4:
		return Vector2(p.z, -p.y) * 0.5
	return Vector2(p.x, -p.y) * 0.5
