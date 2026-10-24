class_name SmoothMesher
extends RefCounted
@warning_ignore_start("integer_division")
## Smooth terrain: natural ground (grass, dirt, stone, sand, ores, bedrock) is drawn as one
## rounded surface made with surface nets; built blocks stay cubes (world.gd). Only the picture
## changes: collision, mining, zombies and the server still use whole blocks, so the rounding is
## kept small (corners are cut by up to CUT_MAX, hollows filled by at most FILL_MAX, so a dug
## 1x2 tunnel still looks about as big as it is).
##
## Each block is one sample (solid or not) at its centre. Every 2x2x2 group of samples that is
## neither all solid nor all air gets one vertex near the block corner in its middle, and every
## pair of neighbouring samples where a natural block meets air gets a quad joining the four
## vertices around it. The chunk reads P blocks of its eight neighbours, so vertices, smoothing,
## normals and sky light along a chunk border come out the same in both chunks.

const CH := 16
const H := 64
const CH2 := 256
const P := 4
const W := CH + 2 * P   # columns across, neighbours included
const NC := W - 1       # vertex cells across
const NC2 := NC * NC
const FILL_MAX := 0.2
const CUT_MAX := 0.45
const RELAX := 2
const LAMBDA := 0.5
## How deep under cover (blocks) the sky's light fades out.
const SKY_DEPTH := 9.0
const MASK63 := 0x7FFFFFFFFFFFFFFF

## Terrain material layers (the shader's texture array).
const L_GRASS := 0
const L_DIRT := 1
const L_STONE := 2
const L_SAND := 3
const L_COAL := 4
const L_IRON := 5
const L_BEDROCK := 6

## Per block id: drawn smooth (natural ground).
static var NAT := []
## Per block id: counts as solid for the shape of the ground (natural and built full blocks, so
## the ground meets a wall instead of curving away under it).
static var FIELD := []
static var LAYER := []
## Per 8-corner mask: [displacement from the block corner, unit direction towards the solid].
static var _disp := []
static var _grad := []
static var _bit := {}


## Called once on the main thread before any chunk is meshed.
static func init_tables() -> void:
	if not _disp.is_empty():
		return
	NAT.resize(Blocks.COUNT)
	FIELD.resize(Blocks.COUNT)
	LAYER.resize(Blocks.COUNT)
	for id in Blocks.COUNT:
		NAT[id] = id in [Blocks.GRASS, Blocks.DIRT, Blocks.STONE, Blocks.SAND, Blocks.COAL_ORE, Blocks.IRON_ORE, Blocks.BEDROCK]
		FIELD[id] = Blocks.FULL[id] and id != Blocks.LEAVES
		LAYER[id] = {Blocks.GRASS: L_GRASS, Blocks.DIRT: L_DIRT, Blocks.STONE: L_STONE, Blocks.SAND: L_SAND,
			Blocks.COAL_ORE: L_COAL, Blocks.IRON_ORE: L_IRON, Blocks.BEDROCK: L_BEDROCK}.get(id, -1)
	for i in 64:
		_bit[1 << i] = i
	var corners: Array[Vector3] = []
	for c in 8:
		corners.append(Vector3(c & 1, (c >> 2) & 1, (c >> 1) & 1))
	for m in 256:
		var sum := Vector3.ZERO
		var n := 0
		var g := Vector3.ZERO
		for c in 8:
			if m & (1 << c):
				g += corners[c] - Vector3(0.5, 0.5, 0.5)
			for b in [1, 2, 4]:
				if c & b == 0 and bool(m & (1 << c)) != bool(m & (1 << (c | b))):
					sum += (corners[c] + corners[c | b]) * 0.5
					n += 1
		var d := Vector3.ZERO
		if n > 0:
			d = sum / n - Vector3(0.5, 0.5, 0.5)
		if g.length() > 0.001:
			g = g.normalized()
		_disp.append(_limit(d, g))
		_grad.append(g)


## Keep a vertex from cutting into the solid more than CUT_MAX or filling the air more than
## FILL_MAX (measured towards the solid side), and inside its cell.
static func _limit(d: Vector3, g: Vector3) -> Vector3:
	var s := d.dot(g)
	if s < -FILL_MAX:
		d += g * (-FILL_MAX - s)
	elif s > CUT_MAX:
		d -= g * (s - CUT_MAX)
	return d.clamp(Vector3(-0.5, -0.5, -0.5), Vector3(0.5, 0.5, 0.5))


## nb: the nine chunks' block data, nb[(dz + 1) * 3 + dx + 1] (4 = this chunk). Fills the
## terrain arrays of buf (world.gd MeshBuf) and returns the open-sky heights per column
## (see sky_at), which the cube faces use too.
static func build(nb: Array, buf) -> PackedFloat32Array:
	var nat: Array = NAT
	var field: Array = FIELD
	var opq: Array = Blocks.OPAQUE
	var fm := PackedInt64Array()
	var nm := PackedInt64Array()
	var top := PackedInt32Array()
	var colc := PackedInt32Array()
	var colb := PackedInt32Array()
	fm.resize(W * W)
	nm.resize(W * W)
	top.resize(W * W)
	colc.resize(W * W)
	colb.resize(W * W)
	# Nothing above the highest non-air layer of each chunk needs reading.
	var ytop := PackedInt32Array()
	ytop.resize(9)
	for ci in 9:
		var d: PackedByteArray = nb[ci]
		if d.is_empty():
			continue
		var t := H
		while t > 0 and d.slice((t - 1) * CH2, t * CH2).count(0) == CH2:
			t -= 1
		ytop[ci] = t
	for pz in W:
		var lz := pz - P
		var cz := 0 if lz >= 0 and lz < CH else (-1 if lz < 0 else 1)
		for px in W:
			var lx := px - P
			var cx := 0 if lx >= 0 and lx < CH else (-1 if lx < 0 else 1)
			var ci := (cz + 1) * 3 + cx + 1
			var d: PackedByteArray = nb[ci]
			var base := (lx & 15) + (lz & 15) * CH
			var f := 0
			var n := 0
			var t := 0
			var i := base
			for y in ytop[ci]:
				var b := d[i]
				i += CH2
				if b == 0:
					continue
				if field[b]:
					f |= 1 << y
				if nat[b]:
					n |= 1 << y
				if opq[b]:
					t = y + 1
			var col := px + pz * W
			fm[col] = f
			nm[col] = n
			top[col] = t
			colc[col] = ci
			colb[col] = base
	# Open-sky height per column: the lowest the sky reaches it from up to 2 columns away
	# (each column of distance counts as one block deeper), so light reaches into cave mouths.
	var rows := PackedFloat32Array()
	rows.resize(W * W)
	for pz in W:
		for px in W:
			var best := 99.0
			for dx in range(maxi(-2, -px), mini(3, W - px)):
				best = minf(best, top[px + dx + pz * W] + absi(dx))
			rows[px + pz * W] = best
	var sky := PackedFloat32Array()
	sky.resize(W * W)
	for pz in W:
		for px in W:
			var best := 99.0
			for dz in range(maxi(-2, -pz), mini(3, W - pz)):
				best = minf(best, rows[px + (pz + dz) * W] + absi(dz))
			sky[px + pz * W] = best

	# Vertices: one per mixed 2x2x2 group that holds a natural block.
	var keys := PackedInt32Array()  # vertex index per cell, -1 for none
	keys.resize(NC2 * H)
	keys.fill(-1)
	var vpos := PackedVector3Array()
	var vlat := PackedVector3Array()
	var vgrad := PackedVector3Array()
	var vmask := PackedInt32Array()
	var vkey := PackedInt32Array()
	var vpin := PackedByteArray()
	var bits: Dictionary = _bit
	var disp: Array = _disp
	var grad: Array = _grad
	for ck in NC:
		for ci in NC:
			var c0 := ci + ck * W
			var a := fm[c0]
			var b := fm[c0 + 1]
			var c := fm[c0 + W]
			var e := fm[c0 + W + 1]
			var all_ := a & b & c & e
			all_ &= all_ >> 1
			var any_ := a | b | c | e
			any_ |= any_ >> 1
			var na := nm[c0] | nm[c0 + 1] | nm[c0 + W] | nm[c0 + W + 1]
			na |= na >> 1
			var cells := any_ & ~all_ & na & MASK63
			# Next to a built block (natural blocks only are drawn smooth): the vertex stays on the
			# block corner, so the ground meets the cube's edge with no gap.
			var built := (a & ~nm[c0]) | (b & ~nm[c0 + 1]) | (c & ~nm[c0 + W]) | (e & ~nm[c0 + W + 1])
			built |= built >> 1
			while cells != 0:
				var lb := cells & -cells
				cells ^= lb
				var y: int = bits[lb]
				var m := ((a >> y) & 1) | (((b >> y) & 1) << 1) | (((c >> y) & 1) << 2) | (((e >> y) & 1) << 3) \
					| (((a >> y) & 2) << 3) | (((b >> y) & 2) << 4) | (((c >> y) & 2) << 5) | (((e >> y) & 2) << 6)
				var lat := Vector3(ci - P + 1, y + 1, ck - P + 1)
				var key := ci + ck * NC + y * NC2
				keys[key] = vpos.size()
				var pin := (built >> y) & 1
				vpos.append(lat if pin else lat + disp[m])
				vpin.append(pin)
				vlat.append(lat)
				vgrad.append(grad[m])
				vmask.append(m)
				vkey.append(key)
	var nv := vpos.size()

	# Smoothing: each vertex moves part of the way to the middle of its neighbours, within limits.
	for it in RELAX:
		var next := PackedVector3Array()
		next.resize(nv)
		for v in nv:
			if vpin[v]:
				next[v] = vlat[v]
				continue
			var key := vkey[v]
			var ci := key % NC
			var ck := (key / NC) % NC
			var sum := Vector3.ZERO
			var n := 0
			var o := -1
			if ci > 0:
				o = keys[key - 1]
				if o >= 0:
					sum += vpos[o]
					n += 1
			if ci < NC - 1:
				o = keys[key + 1]
				if o >= 0:
					sum += vpos[o]
					n += 1
			if ck > 0:
				o = keys[key - NC]
				if o >= 0:
					sum += vpos[o]
					n += 1
			if ck < NC - 1:
				o = keys[key + NC]
				if o >= 0:
					sum += vpos[o]
					n += 1
			if key >= NC2:
				o = keys[key - NC2]
				if o >= 0:
					sum += vpos[o]
					n += 1
			if key + NC2 < keys.size():
				o = keys[key + NC2]
				if o >= 0:
					sum += vpos[o]
					n += 1
			var p := vpos[v]
			if n > 0:
				p = p.lerp(sum / n, LAMBDA)
			next[v] = vlat[v] + _limit(p - vlat[v], vgrad[v])
		vpos = next

	# Quads: where a natural block meets air. Every quad adds to its corners' normals; only the
	# quads of this chunk's own blocks are drawn.
	var vnorm := PackedVector3Array()
	vnorm.resize(nv)
	var quads := PackedInt32Array()
	for v in nv:
		var m := vmask[v]
		var key := vkey[v]
		var ci := key % NC
		var ck := (key / NC) % NC
		var y := key / NC2
		var s7 := (m >> 7) & 1
		for axis in 3:
			var other := 6 if axis == 0 else (3 if axis == 1 else 5)
			if ((m >> other) & 1) == s7:
				continue
			# The solid one of the two samples, and the other three vertices around the edge.
			var sx := ci + 1
			var sy := y + 1
			var sz := ck + 1
			var k1: int
			var k2: int
			var k3: int
			if axis == 0:
				if s7 == 0:
					sx = ci
				if ck >= NC - 1:
					continue
				k1 = key + NC2
				k2 = key + NC2 + NC
				k3 = key + NC
			elif axis == 1:
				if s7 == 0:
					sy = y
				if ci >= NC - 1 or ck >= NC - 1:
					continue
				k1 = key + 1
				k2 = key + 1 + NC
				k3 = key + NC
			else:
				if s7 == 0:
					sz = ck
				if ci >= NC - 1:
					continue
				k1 = key + 1
				k2 = key + 1 + NC2
				k3 = key + NC2
			if not ((nm[sx + sz * W] >> sy) & 1):
				continue  # a built block: its cube face is drawn instead
			if k2 >= keys.size():
				continue
			var i1: int = keys[k1]
			var i2: int = keys[k2]
			var i3: int = keys[k3]
			if i1 < 0 or i2 < 0 or i3 < 0:
				continue
			var fwd := (s7 == 1) != (axis == 1)
			if not fwd:
				var t := i1
				i1 = i3
				i3 = t
			var nrm := -(vpos[i2] - vpos[v]).cross(vpos[i3] - vpos[i1])
			vnorm[v] += nrm
			vnorm[i1] += nrm
			vnorm[i2] += nrm
			vnorm[i3] += nrm
			var lx := sx - P
			var lz := sz - P
			if lx >= 0 and lx < CH and lz >= 0 and lz < CH:
				quads.append(v)
				quads.append(i1)
				quads.append(i2)
				quads.append(i3)

	# The drawn vertices, with their materials (the natural blocks around them) and sky light.
	var out := PackedInt32Array()  # drawn index per vertex, -1 until used
	out.resize(nv)
	out.fill(-1)
	var used := PackedInt32Array()
	for v in quads:
		if out[v] < 0:
			out[v] = used.size()
			used.append(v)
	var nu := used.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	verts.resize(nu)
	norms.resize(nu)
	cols.resize(nu)
	uv.resize(nu)
	uv2.resize(nu)
	var layers: Array = LAYER
	var wts := PackedFloat32Array()
	wts.resize(7)
	for u in nu:
		var v := used[u]
		var key := vkey[v]
		var ci := key % NC
		var ck := (key / NC) % NC
		var y := key / NC2
		wts.fill(0.0)
		var total := 0.0
		for corner in 8:
			var col := ci + (corner & 1) + (ck + ((corner >> 1) & 1)) * W
			var yy := y + ((corner >> 2) & 1)
			if (nm[col] >> yy) & 1:
				var d: PackedByteArray = nb[colc[col]]
				var l: int = layers[d[colb[col] + yy * CH2]]
				var add := 3.0 if l == L_COAL or l == L_IRON else 1.0
				wts[l] += add
				total += add
		if total <= 0.0:
			total = 1.0
			wts[L_STONE] = 1.0
		var inv := 1.0 / total
		var c0 := ci + ck * W
		var open := (sky[c0] + sky[c0 + 1] + sky[c0 + W] + sky[c0 + W + 1]) * 0.25
		verts[u] = vpos[v]
		norms[u] = vnorm[v].normalized()
		cols[u] = Color(wts[0] * inv, wts[1] * inv, wts[2] * inv, wts[3] * inv)
		uv[u] = Vector2(wts[4] * inv, wts[5] * inv)
		uv2[u] = Vector2(wts[6] * inv, clampf(1.0 - (open - (y + 1)) / SKY_DEPTH, 0.0, 1.0))
	var idx := PackedInt32Array()
	idx.resize(quads.size() / 4 * 6)
	var t := 0
	for q in range(0, quads.size(), 4):
		var a := out[quads[q]]
		var b := out[quads[q + 1]]
		var c := out[quads[q + 2]]
		var e := out[quads[q + 3]]
		# Split along the shorter diagonal.
		if verts[a].distance_squared_to(verts[c]) <= verts[b].distance_squared_to(verts[e]):
			idx[t] = a
			idx[t + 1] = b
			idx[t + 2] = c
			idx[t + 3] = a
			idx[t + 4] = c
			idx[t + 5] = e
		else:
			idx[t] = a
			idx[t + 1] = b
			idx[t + 2] = e
			idx[t + 3] = b
			idx[t + 4] = c
			idx[t + 5] = e
		t += 6
	buf.t_verts = verts
	buf.t_norms = norms
	buf.t_cols = cols
	buf.t_uv = uv
	buf.t_uv2 = uv2
	buf.t_idx = idx
	return sky


## Sky light (0-1) at a block cell of this chunk (x, z may be -P..CH+P-1), from build's heights.
static func sky_at(sky: PackedFloat32Array, x: int, y: int, z: int) -> float:
	var px := clampi(x + P, 0, W - 1)
	var pz := clampi(z + P, 0, W - 1)
	return clampf(1.0 - (sky[px + pz * W] - y) / SKY_DEPTH, 0.0, 1.0)
