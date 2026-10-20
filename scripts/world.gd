extends Node3D
## Chunked block world. Terrain generation and meshing run on worker threads.

const CH := 16
const H := 64
const CH2 := 256
const BEACON_H := 48.0


class Chunk:
	var key := Vector2i.ZERO
	var data := PackedByteArray()
	var has_data := false
	var generating := false
	var meshing := false
	var mesh_ver := 0
	var built_ver := -1
	var node: MeshInstance3D = null
	var body: StaticBody3D = null
	var shape: CollisionShape3D = null
	var lights: Array = []
	var modified := false
	var ready := false


class MeshBuf:
	const CORNERS := [
		[Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)],
		[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0)],
		[Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
		[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1)],
		[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)],
	]
	const NORMALS := [Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	const SHADE := [1.0, 0.55, 0.8, 0.8, 0.9, 0.9]

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	var lights: Array = []
	var beacons: Array = []

	func face(dir: int, x: int, y: int, z: int, tile: int, solid: bool) -> void:
		var base := verts.size()
		var cs: Array = CORNERS[dir]
		var n: Vector3 = NORMALS[dir]
		var sh: float = SHADE[dir]
		var col := Color(sh, sh, sh)
		var o := Vector3(x, y, z)
		var tu := float(tile % 8) * 0.125
		@warning_ignore("integer_division")
		var tv := float(tile / 8) * 0.125
		for k in 4:
			var c: Vector3 = cs[k]
			verts.append(o + c)
			norms.append(n)
			cols.append(col)
			var u: float
			var v: float
			if dir < 2:
				u = c.x
				v = c.z
			elif dir < 4:
				u = c.z
				v = 1.0 - c.y
			else:
				u = c.x
				v = 1.0 - c.y
			uvs.append(Vector2(tu + 0.002 + u * 0.121, tv + 0.002 + v * 0.121))
		idx.append(base)
		idx.append(base + 1)
		idx.append(base + 2)
		idx.append(base)
		idx.append(base + 2)
		idx.append(base + 3)
		if solid:
			faces.append(o + cs[0])
			faces.append(o + cs[1])
			faces.append(o + cs[2])
			faces.append(o + cs[0])
			faces.append(o + cs[2])
			faces.append(o + cs[3])

	## An SH_BOX block: all six faces of the box lo..hi inside the cell, each showing the whole
	## tile ([top, side, bottom]). `solid` adds them to the collision faces too.
	func box(x: int, y: int, z: int, tl: Array, lo: Vector3, hi: Vector3, solid: bool) -> void:
		var o := Vector3(x, y, z)
		var ext := hi - lo
		for dir in 6:
			var tile: int = tl[0] if dir == 0 else (tl[2] if dir == 1 else tl[1])
			var tu := float(tile % 8) * 0.125
			@warning_ignore("integer_division")
			var tv := float(tile / 8) * 0.125
			var cs: Array = CORNERS[dir]
			var n: Vector3 = NORMALS[dir]
			var sh: float = SHADE[dir]
			var base := verts.size()
			var pts: Array[Vector3] = []
			for k in 4:
				var c: Vector3 = cs[k]
				var v3 := o + lo + c * ext
				pts.append(v3)
				verts.append(v3)
				norms.append(n)
				cols.append(Color(sh, sh, sh))
				var u: float
				var v: float
				if dir < 2:
					u = c.x
					v = c.z
				elif dir < 4:
					u = c.z
					v = 1.0 - c.y
				else:
					u = c.x
					v = 1.0 - c.y
				uvs.append(Vector2(tu + 0.002 + u * 0.121, tv + 0.002 + v * 0.121))
			idx.append(base)
			idx.append(base + 1)
			idx.append(base + 2)
			idx.append(base)
			idx.append(base + 2)
			idx.append(base + 3)
			if solid:
				faces.append(pts[0])
				faces.append(pts[1])
				faces.append(pts[2])
				faces.append(pts[0])
				faces.append(pts[2])
				faces.append(pts[3])

	func cross(x: int, y: int, z: int, tile: int) -> void:
		var o := Vector3(x, y, z)
		var tu := float(tile % 8) * 0.125
		@warning_ignore("integer_division")
		var tv := float(tile / 8) * 0.125
		var col := Color(0.95, 0.95, 0.95)
		var pairs := [[Vector3(0.15, 0, 0.15), Vector3(0.85, 0, 0.85)], [Vector3(0.85, 0, 0.15), Vector3(0.15, 0, 0.85)]]
		for pr in pairs:
			var a: Vector3 = pr[0]
			var b: Vector3 = pr[1]
			var p := [o + a, o + b, o + b + Vector3.UP, o + a + Vector3.UP]
			var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
			for side in 2:
				var base := verts.size()
				var order := [0, 1, 2, 3] if side == 0 else [0, 3, 2, 1]
				for k in order:
					verts.append(p[k])
					norms.append(Vector3.UP)
					cols.append(col)
					var q: Vector2 = uv[k]
					uvs.append(Vector2(tu + 0.002 + q.x * 0.121, tv + 0.002 + q.y * 0.121))
				idx.append(base)
				idx.append(base + 1)
				idx.append(base + 2)
				idx.append(base)
				idx.append(base + 2)
				idx.append(base + 3)


var render_radius := 6
## False in server mode: chunks get collision only (no render mesh, lights or crack overlays).
var render := true
## Tests: rebuild an edited chunk immediately instead of on a worker thread, so runs repeat exactly.
var sync_mesh := false
## Tests (server mode): make no collision bodies until flush_bodies(), which then makes them in
## chunk order. Physics results depend on the order bodies were made in, and worker threads
## finish chunks in a different order every run.
var defer_bodies := false
var _deferred_faces := {}  # chunk key -> collision faces
var seed_v := 0
var chunks := {}
var order: Array[Vector2i] = []
var mesh_set := {}
var centers: Array[Vector2i] = []
var tasks: Array[int] = []
var max_tasks := 4
var urgent: Array[Vector2i] = []
var material: StandardMaterial3D
var damage := {}
var crack_nodes := {}
var crack_mats: Array[StandardMaterial3D] = []
var crack_mesh: BoxMesh
## The light beam drawn above every backpack (one shared mesh and material).
var beacon_mesh: BoxMesh
var beacon_mat: StandardMaterial3D
var gen_count := 0
var mesh_count := 0
## Set whenever chunk work may have become possible, so _schedule can skip its full scan otherwise.
var sched_dirty := true
## Server: every block change is also appended here as [pos, id]; NetServer sends them out.
var record_edits := false
var edits_out: Array = []
## Server: edited chunks not saved since their last change (see server/save.gd).
var save_dirty := {}
## Server: crack stage changes as [pos, stage 0-3], sent to clients like edits.
var cracks_out: Array = []
var crack_stage := {}
## Client online: chunks come from the server's subscriptions (see Proto.SUB_RADIUS). Only
## "fresh" chunks are generated here; edited ones wait for the server's copy.
const SUB_FRESH := 1
const SUB_WAIT := 2
var remote := false
var sub_state := {}      # chunk key -> SUB_FRESH / SUB_WAIT
var sub_seq := {}        # chunk key -> last edit batch the chunk's data already includes
var pending := {}        # chunk key -> [[batch seq, block index, id], ...] for chunks without data yet


func setup(s: int, tex) -> void:
	seed_v = s
	render = not G.server_mode
	if G.server_mode:
		# 5 chunks (80 m) covers the 72 m zombie despawn distance.
		render_radius = 5
	if G.arg_value("--radius=") != "":
		render_radius = clampi(int(G.arg_value("--radius=")), 2, 12)
	max_tasks = clampi(OS.get_processor_count() - 2, 2, 8)
	material = StandardMaterial3D.new()
	if tex == null:
		return  # dedicated server: nothing is drawn
	material.albedo_texture = tex.atlas
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.roughness = 1.0
	material.metallic_specular = 0.0
	crack_mesh = BoxMesh.new()
	crack_mesh.size = Vector3(1.012, 1.012, 1.012)
	beacon_mesh = BoxMesh.new()
	beacon_mesh.size = Vector3(0.22, BEACON_H, 0.22)
	beacon_mat = StandardMaterial3D.new()
	beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beacon_mat.albedo_color = Color(1.0, 0.82, 0.3, 0.55)
	beacon_mat.disable_fog = true  # seen from as far as the chunk is drawn, day or night
	beacon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for t in tex.crack_tex:
		var m := StandardMaterial3D.new()
		m.albedo_texture = t
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.uv1_scale = Vector3(3, 2, 1)
		crack_mats.append(m)


func _exit_tree() -> void:
	for t in tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	tasks.clear()


# ------------------------------------------------------------ streaming

func update_center(pos: Vector3) -> void:
	update_centers([pos])


## Keep chunks loaded around every position in the list (one per player on a server).
func update_centers(positions: Array) -> void:
	var cs: Array[Vector2i] = []
	for pos in positions:
		var c := Vector2i(floori(pos.x / CH), floori(pos.z / CH))
		if not cs.has(c):
			cs.append(c)
	if cs != centers:
		centers = cs
		_rebuild_order()
		_unload_far()
	_reap()
	_schedule()


func _near_center(k: Vector2i, lim: int) -> bool:
	for c in centers:
		if absi(k.x - c.x) <= lim and absi(k.y - c.y) <= lim:
			return true
	return false


func _rebuild_order() -> void:
	order.clear()
	mesh_set.clear()
	var r1 := render_radius + 1
	# Each chunk is ranked by its distance to the nearest center.
	var best := {}
	for c in centers:
		for dz in range(-r1, r1 + 1):
			for dx in range(-r1, r1 + 1):
				var d2 := dx * dx + dz * dz
				if d2 <= r1 * r1 + 1:
					var k := Vector2i(c.x + dx, c.y + dz)
					if d2 < int(best.get(k, 1 << 30)):
						best[k] = d2
	# Bucket by squared distance so nearer chunks come first.
	var buckets := []
	buckets.resize(r1 * r1 + 2)
	for i in buckets.size():
		buckets[i] = []
	for k in best:
		buckets[best[k]].append(k)
	var mesh_lim := render_radius * render_radius + 1
	for d2 in buckets.size():
		for k in buckets[d2]:
			order.append(k)
			if d2 <= mesh_lim:
				mesh_set[k] = true
	sched_dirty = true


## Free chunks farther than lim chunks from every center (default: render radius + 3).
## Edited chunks keep their block data.
func _unload_far(lim := -1) -> void:
	if lim < 0:
		lim = render_radius + 3
	for key in chunks.keys():
		if not _near_center(key, lim):
			var c: Chunk = chunks[key]
			if c.generating or c.meshing:
				continue
			_free_visual(c)
			if c.modified:
				c.built_ver = -1
			else:
				chunks.erase(key)


func _free_visual(c: Chunk) -> void:
	if c.node != null:
		c.node.queue_free()
		c.node = null
	c.lights.clear()
	if c.body != null:
		c.body.queue_free()
		c.body = null
		c.shape = null
	_deferred_faces.erase(c.key)
	c.ready = false


func _reap() -> void:
	var i := tasks.size() - 1
	while i >= 0:
		if WorkerThreadPool.is_task_completed(tasks[i]):
			WorkerThreadPool.wait_for_task_completion(tasks[i])
			tasks.remove_at(i)
			sched_dirty = true
		i -= 1


func _schedule() -> void:
	var guard := 0
	while urgent.size() > 0 and tasks.size() < max_tasks + 2 and guard < 16:
		guard += 1
		var k: Vector2i = urgent.pop_front()
		if not _try_mesh(k):
			var c: Chunk = chunks.get(k)
			if c != null and c.meshing:
				urgent.append(k)
				break
	if not sched_dirty:
		return
	sched_dirty = false
	for k in order:
		if tasks.size() >= max_tasks:
			sched_dirty = true
			return
		var c: Chunk = chunks.get(k)
		if c == null:
			c = Chunk.new()
			c.key = k
			chunks[k] = c
		if not c.has_data:
			if not c.generating and (not remote or sub_state.get(k, 0) == SUB_FRESH):
				c.generating = true
				tasks.append(WorkerThreadPool.add_task(_task_gen.bind(k), false, "gen"))
		elif mesh_set.has(k):
			_try_mesh(k)


func _try_mesh(k: Vector2i) -> bool:
	var c: Chunk = chunks.get(k)
	if c == null or not c.has_data or c.meshing or c.built_ver >= c.mesh_ver:
		return false
	var n: Array = [chunks.get(k + Vector2i(1, 0)), chunks.get(k + Vector2i(-1, 0)), chunks.get(k + Vector2i(0, 1)), chunks.get(k + Vector2i(0, -1))]
	for nc in n:
		if nc == null or not nc.has_data:
			return false
	c.meshing = true
	var ver := c.mesh_ver
	tasks.append(WorkerThreadPool.add_task(_task_mesh.bind(k, ver, c.data, n[0].data, n[1].data, n[2].data, n[3].data), false, "mesh"))
	return true


func _task_gen(k: Vector2i) -> void:
	var g := WorldGen.new(seed_v)
	var d := g.generate(k.x, k.y)
	call_deferred("_gen_done", k, d)


func _gen_done(k: Vector2i, d: PackedByteArray) -> void:
	var c: Chunk = chunks.get(k)
	if c == null:
		c = Chunk.new()
		c.key = k
		chunks[k] = c
	c.generating = false
	sched_dirty = true
	if remote and (c.has_data or sub_state.get(k, 0) != SUB_FRESH):
		return  # the server's copy arrived meanwhile, or we're no longer subscribed
	c.data = d
	c.has_data = true
	gen_count += 1
	_apply_pending(c)


func _task_mesh(k: Vector2i, ver: int, d: PackedByteArray, px: PackedByteArray, nx: PackedByteArray, pz: PackedByteArray, nz: PackedByteArray) -> void:
	call_deferred("_mesh_done", k, ver, _make_buf(d, px, nx, pz, nz))


func _make_buf(d: PackedByteArray, px: PackedByteArray, nx: PackedByteArray, pz: PackedByteArray, nz: PackedByteArray) -> MeshBuf:
	if render:
		return _build(d, px, nx, pz, nz)
	var buf := MeshBuf.new()
	buf.faces = _build_collision(d, px, nx, pz, nz)
	return buf


## Server mode: the same scan as _build, but only the collision triangles of solid blocks.
## Faces between two full cubes are left out; a solid box (a bed) has all six of its own.
func _build_collision(d: PackedByteArray, px: PackedByteArray, nx: PackedByteArray, pz: PackedByteArray, nz: PackedByteArray) -> PackedVector3Array:
	var out := PackedVector3Array()
	var sol: Array = Blocks.FULL
	var shp: Array = Blocks.SHAPE
	for y in H:
		var yo := y * CH2
		for z in CH:
			var zo := z * CH + yo
			for x in CH:
				var i := x + zo
				if not sol[d[i]]:
					if Blocks.SOLID[d[i]] and shp[d[i]] == Blocks.SH_BOX:
						var bx: Array = Blocks.BOX[d[i]]
						for dir in 6:
							_quad(out, Vector3(x, y, z), dir, bx[0], bx[1])
					continue
				var o := Vector3(x, y, z)
				if y == H - 1 or not sol[d[i + CH2]]:
					_quad(out, o, 0)
				if y > 0 and not sol[d[i - CH2]]:
					_quad(out, o, 1)
				if not sol[d[i + 1] if x < CH - 1 else px[zo]]:
					_quad(out, o, 2)
				if not sol[d[i - 1] if x > 0 else nx[15 + zo]]:
					_quad(out, o, 3)
				if not sol[d[i + CH] if z < CH - 1 else pz[x + yo]]:
					_quad(out, o, 4)
				if not sol[d[i - CH] if z > 0 else nz[x + 15 * CH + yo]]:
					_quad(out, o, 5)
	return out


## Two collision triangles for one block face, with the same corners and winding as MeshBuf.face
## (of the box lo..hi inside the cell, for SH_BOX blocks).
func _quad(out: PackedVector3Array, o: Vector3, dir: int, lo := Vector3.ZERO, hi := Vector3.ONE) -> void:
	var cs: Array = MeshBuf.CORNERS[dir]
	var e := hi - lo
	out.append(o + lo + cs[0] * e)
	out.append(o + lo + cs[1] * e)
	out.append(o + lo + cs[2] * e)
	out.append(o + lo + cs[0] * e)
	out.append(o + lo + cs[2] * e)
	out.append(o + lo + cs[3] * e)


func _build(d: PackedByteArray, px: PackedByteArray, nx: PackedByteArray, pz: PackedByteArray, nz: PackedByteArray) -> MeshBuf:
	var buf := MeshBuf.new()
	var opq: Array = Blocks.OPAQUE
	var sol: Array = Blocks.SOLID
	var shp: Array = Blocks.SHAPE
	var tiles: Array = Blocks.TILES
	for y in H:
		var yo := y * CH2
		for z in CH:
			var zo := z * CH + yo
			for x in CH:
				var i := x + zo
				var b := d[i]
				if b == 0:
					continue
				var tl: Array = tiles[b]
				if shp[b] == 2:
					buf.cross(x, y, z, tl[1])
					if b == Blocks.TORCH or b == Blocks.CAMPFIRE:
						buf.lights.append(Vector3i(x, y, z))
					continue
				if shp[b] == Blocks.SH_BOX:
					var bx: Array = Blocks.BOX[b]
					buf.box(x, y, z, tl, bx[0], bx[1], sol[b])
					if b == Blocks.BACKPACK:
						buf.beacons.append(Vector3i(x, y, z))
					continue
				var solid: bool = sol[b]
				var leaf := b == Blocks.LEAVES
				var nb := d[i + CH2] if y < H - 1 else 0
				if nb == 0 or (not opq[nb] and not (leaf and nb == b)):
					buf.face(0, x, y, z, tl[0], solid)
				nb = d[i - CH2] if y > 0 else 11
				if nb == 0 or (not opq[nb] and not (leaf and nb == b)):
					buf.face(1, x, y, z, tl[2], solid)
				nb = d[i + 1] if x < CH - 1 else px[zo]
				if nb == 0 or (not opq[nb] and not (leaf and nb == b)):
					buf.face(2, x, y, z, tl[1], solid)
				nb = d[i - 1] if x > 0 else nx[15 + zo]
				if nb == 0 or (not opq[nb] and not (leaf and nb == b)):
					buf.face(3, x, y, z, tl[1], solid)
				nb = d[i + CH] if z < CH - 1 else pz[x + yo]
				if nb == 0 or (not opq[nb] and not (leaf and nb == b)):
					buf.face(4, x, y, z, tl[1], solid)
				nb = d[i - CH] if z > 0 else nz[x + 15 * CH + yo]
				if nb == 0 or (not opq[nb] and not (leaf and nb == b)):
					buf.face(5, x, y, z, tl[1], solid)
	return buf


func _mesh_done(k: Vector2i, ver: int, buf: MeshBuf) -> void:
	var c: Chunk = chunks.get(k)
	if c == null:
		return
	c.meshing = false
	sched_dirty = true
	if ver < c.built_ver:
		return
	if not _near_center(k, render_radius + 3):
		# Out of range now: drop the result but keep the chunk marked as needing a mesh,
		# so it is rebuilt if a player comes back before it is unloaded.
		_free_visual(c)
		c.built_ver = -1
		return
	c.built_ver = ver
	mesh_count += 1
	apply_mesh(c, k, buf)


## Main-thread part of finishing a chunk: render mesh, collision shape and lights.
## The benchmark also times this directly.
func apply_mesh(c: Chunk, k: Vector2i, buf: MeshBuf) -> void:
	var origin := Vector3(k.x * CH, 0, k.y * CH)
	if not render:
		if defer_bodies and c.body == null:
			_deferred_faces[k] = buf.faces
		else:
			_apply_collision(c, origin, buf.faces)
		c.ready = true
		return
	if c.node == null:
		c.node = MeshInstance3D.new()
		add_child(c.node)
		c.node.position = origin
	if buf.verts.size() > 0:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = buf.verts
		arr[Mesh.ARRAY_NORMAL] = buf.norms
		arr[Mesh.ARRAY_TEX_UV] = buf.uvs
		arr[Mesh.ARRAY_COLOR] = buf.cols
		arr[Mesh.ARRAY_INDEX] = buf.idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(0, material)
		c.node.mesh = am
	else:
		c.node.mesh = null
	_apply_collision(c, origin, buf.faces)
	for l in c.lights:
		if is_instance_valid(l):
			l.queue_free()
	c.lights.clear()
	for lp in buf.lights:
		var o := OmniLight3D.new()
		o.light_color = Color(1.0, 0.72, 0.42)
		o.omni_range = 8.0
		o.light_energy = 0.9
		o.omni_attenuation = 1.6
		c.node.add_child(o)
		o.position = Vector3(lp) + Vector3(0.5, 0.8, 0.5)
		c.lights.append(o)
	for bp in buf.beacons:
		var m := MeshInstance3D.new()
		m.mesh = beacon_mesh
		m.material_override = beacon_mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.node.add_child(m)
		m.position = Vector3(bp) + Vector3(0.5, 0.62 + BEACON_H * 0.5, 0.5)
		c.lights.append(m)
	c.ready = true


func _apply_collision(c: Chunk, origin: Vector3, faces: PackedVector3Array) -> void:
	if c.body == null:
		c.body = StaticBody3D.new()
		c.body.collision_layer = 1
		c.body.collision_mask = 0
		c.shape = CollisionShape3D.new()
		c.body.add_child(c.shape)
		add_child(c.body)
		c.body.position = origin
	if faces.size() > 0:
		var sh := ConcavePolygonShape3D.new()
		sh.set_faces(faces)
		c.shape.shape = sh
	else:
		c.shape.shape = null


## Tests: make the collision bodies held back by defer_bodies, in chunk order, and stop holding back.
func flush_bodies() -> void:
	defer_bodies = false
	var keys := _deferred_faces.keys()
	keys.sort()
	for k in keys:
		var c: Chunk = chunks.get(k)
		if c != null and c.body == null:
			_apply_collision(c, Vector3(k.x * CH, 0, k.y * CH), _deferred_faces[k])
	_deferred_faces.clear()


## Rebuild a chunk on the spot (sync_mesh). Needs the chunk and its four neighbours' data.
func _mesh_now(k: Vector2i) -> void:
	var c: Chunk = chunks.get(k)
	if c == null or not c.has_data or not c.ready:
		return
	var n: Array = [chunks.get(k + Vector2i(1, 0)), chunks.get(k + Vector2i(-1, 0)), chunks.get(k + Vector2i(0, 1)), chunks.get(k + Vector2i(0, -1))]
	for nc in n:
		if nc == null or not nc.has_data:
			return
	c.built_ver = c.mesh_ver
	mesh_count += 1
	apply_mesh(c, k, _make_buf(c.data, n[0].data, n[1].data, n[2].data, n[3].data))


# ------------------------------------------------------------ queries & edits

func load_progress() -> float:
	if mesh_set.is_empty():
		return 0.0
	var done := 0
	for k in mesh_set:
		var c: Chunk = chunks.get(k)
		if c != null and c.ready:
			done += 1
	return float(done) / float(mesh_set.size())


func get_block(x: int, y: int, z: int) -> int:
	if y < 0:
		return Blocks.BEDROCK
	if y >= H:
		return 0
	var c: Chunk = chunks.get(Vector2i(x >> 4, z >> 4))
	if c == null or not c.has_data:
		return 0
	return c.data[(x & 15) + (z & 15) * CH + y * CH2]


func get_blockv(p: Vector3i) -> int:
	return get_block(p.x, p.y, p.z)


func is_ready_at(pos: Vector3) -> bool:
	var c: Chunk = chunks.get(Vector2i(floori(pos.x) >> 4, floori(pos.z) >> 4))
	return c != null and c.ready


func surface_y(x: int, z: int) -> int:
	for y in range(H - 1, -1, -1):
		if Blocks.is_solid(get_block(x, y, z)):
			return y
	return -1


static func key_of(p: Vector3i) -> Vector2i:
	return Vector2i(p.x >> 4, p.z >> 4)


## Index of a block inside its chunk's data.
static func index_of(p: Vector3i) -> int:
	return (p.x & 15) + (p.z & 15) * CH + p.y * CH2


static func pos_of(k: Vector2i, idx: int) -> Vector3i:
	@warning_ignore("integer_division")
	return Vector3i(k.x * CH + (idx & 15), idx / CH2, k.y * CH + ((idx >> 4) & 15))


## Server start: an edited chunk from the save files (it is never generated).
func preload_chunk(k: Vector2i, data: PackedByteArray) -> void:
	var c := Chunk.new()
	c.key = k
	c.data = data
	c.has_data = true
	c.modified = true
	chunks[k] = c
	sched_dirty = true


## Server saving: the edited chunks changed since the last save, as [[key, data], ...] (the data
## arrays are copies: later edits don't change them). Forgets them as saved.
func take_unsaved() -> Array:
	var out := []
	for k in save_dirty:
		var c: Chunk = chunks.get(k)
		if c != null and c.has_data:
			out.append([k, c.data.duplicate()])
	save_dirty.clear()
	return out


func has_block_data(p: Vector3i) -> bool:
	var c: Chunk = chunks.get(key_of(p))
	return c != null and c.has_data


func is_modified(k: Vector2i) -> bool:
	var c: Chunk = chunks.get(k)
	return c != null and c.has_data and c.modified


func chunk_data(k: Vector2i) -> PackedByteArray:
	var c: Chunk = chunks.get(k)
	return c.data if c != null and c.has_data else PackedByteArray()


func set_block(p: Vector3i, id: int) -> bool:
	if p.y < 0 or p.y >= H:
		return false
	var k := Vector2i(p.x >> 4, p.z >> 4)
	var c: Chunk = chunks.get(k)
	if c == null or not c.has_data:
		return false
	var lx := p.x & 15
	var lz := p.z & 15
	c.data[lx + lz * CH + p.y * CH2] = id
	c.modified = true
	if record_edits:
		edits_out.append([p, id])
		save_dirty[k] = true
	_clear_damage(p)
	_dirty(k)
	if lx == 0:
		_dirty(k + Vector2i(-1, 0))
	elif lx == 15:
		_dirty(k + Vector2i(1, 0))
	if lz == 0:
		_dirty(k + Vector2i(0, -1))
	elif lz == 15:
		_dirty(k + Vector2i(0, 1))
	return true


func _dirty(k: Vector2i) -> void:
	var c: Chunk = chunks.get(k)
	if c == null:
		return
	c.mesh_ver += 1
	sched_dirty = true
	if sync_mesh:
		_mesh_now(k)
		return
	if not urgent.has(k):
		urgent.append(k)


## Zombies (and spikes wearing down) chip away at blocks. Returns true if it broke.
func damage_block(p: Vector3i, amount: float) -> bool:
	var id := get_blockv(p)
	if id <= 0 or id == Blocks.BEDROCK:
		return false
	var hp: float = Blocks.ZHP[id]
	var d: float = float(damage.get(p, 0.0)) + amount
	if d >= hp:
		set_block(p, 0)
		return true
	damage[p] = d
	_show_crack(p, d / hp)
	return false


func _show_crack(p: Vector3i, frac: float) -> void:
	var stage := clampi(int(frac * 4.0), 0, 3)
	if record_edits and int(crack_stage.get(p, -1)) != stage:
		crack_stage[p] = stage
		cracks_out.append([p, stage])
	if not render:
		return
	var n: MeshInstance3D = crack_nodes.get(p)
	if n == null:
		n = MeshInstance3D.new()
		n.mesh = crack_mesh
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(n)
		n.position = Vector3(p) + Vector3(0.5, 0.5, 0.5)
		crack_nodes[p] = n
	n.material_override = crack_mats[stage]


func _clear_damage(p: Vector3i) -> void:
	damage.erase(p)
	crack_stage.erase(p)
	var n = crack_nodes.get(p)
	if n != null:
		n.queue_free()
		crack_nodes.erase(p)


# ------------------------------------------------------------ online (client side)

## S_SUB: chunks the server now keeps us up to date on. Fresh ones we generate ourselves;
## edited ones ("wait") come as S_CHUNK.
func net_subscribe(seq: int, fresh: Array, wait: Array) -> void:
	for k in fresh:
		sub_state[k] = SUB_FRESH
		sub_seq[k] = seq
		var c: Chunk = chunks.get(k)
		if c != null and c.has_data and c.modified and not c.generating and not c.meshing:
			# Untouched on the server, but we hold edits (from before a reconnect, or a guess
			# the server never confirmed): start again from the seed.
			_free_visual(c)
			chunks.erase(k)
		pending.erase(k)
	for k in wait:
		sub_state[k] = SUB_WAIT
	sched_dirty = true


## S_UNSUB: the server stops sending edits for these chunks, so our copies would go stale.
func net_unsubscribe(keys: Array) -> void:
	for k in keys:
		sub_state.erase(k)
		sub_seq.erase(k)
		pending.erase(k)
		var c: Chunk = chunks.get(k)
		if c != null and not c.generating and not c.meshing and not _near_center(k, render_radius + 3):
			_free_visual(c)
			chunks.erase(k)


## S_CHUNK: the server's copy of an edited chunk, including every edit batch up to seq.
func net_chunk(seq: int, k: Vector2i, data: PackedByteArray) -> void:
	if not sub_state.has(k) or data.size() != CH2 * H:
		return
	var c: Chunk = chunks.get(k)
	if c == null:
		c = Chunk.new()
		c.key = k
		chunks[k] = c
	c.data = data
	c.has_data = true
	c.modified = true
	sub_state[k] = SUB_FRESH
	sub_seq[k] = seq
	_apply_pending(c)
	for kk in [k, k + Vector2i(1, 0), k + Vector2i(-1, 0), k + Vector2i(0, 1), k + Vector2i(0, -1)]:
		_dirty(kk)
	sched_dirty = true


## S_EDITS: one batch of block changes, grouped by chunk ([key, [[index, id], ...]]).
func net_edits(seq: int, groups: Array) -> void:
	for g in groups:
		var k: Vector2i = g[0]
		if not sub_state.has(k):
			continue
		var c: Chunk = chunks.get(k)
		if c == null or not c.has_data:
			if not pending.has(k):
				pending[k] = []
			for e in g[1]:
				pending[k].append([seq, e[0], e[1]])
			continue
		if seq <= int(sub_seq.get(k, -1)):
			continue  # already in our copy
		for e in g[1]:
			set_block(pos_of(k, e[0]), e[1])


## Edits that arrived before the chunk's data: apply the ones newer than the data.
func _apply_pending(c: Chunk) -> void:
	var list: Array = pending.get(c.key, [])
	pending.erase(c.key)
	var base := int(sub_seq.get(c.key, -1))
	for e in list:
		if e[0] > base:
			c.data[e[1]] = e[2]
			c.modified = true


## S_CRACKS: a zombie is chipping at this block.
func net_crack(p: Vector3i, stage: int) -> void:
	if get_blockv(p) == Blocks.AIR:
		return
	_show_crack(p, (stage + 0.5) / 4.0)
	if G.sfx != null:
		G.sfx.play_at("thud", Vector3(p) + Vector3(0.5, 0.5, 0.5), -2.0)


## A new session with the server (reconnect): it will subscribe us again from scratch.
func net_reset() -> void:
	sub_state.clear()
	sub_seq.clear()
	pending.clear()
	sched_dirty = true


## Tests: one hash over the chunks within r of chunk (cx, cz), to compare worlds.
func region_hash(cx: int, cz: int, r: int) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c: Chunk = chunks.get(Vector2i(cx + dx, cz + dz))
			if c == null or not c.has_data:
				ctx.update(("missing %d %d" % [cx + dx, cz + dz]).to_utf8_buffer())
			else:
				ctx.update(c.data)
	return ctx.finish().hex_encode().left(16)


func raycast(origin: Vector3, dir: Vector3, maxd: float) -> Dictionary:
	var p := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var sx := 1 if dir.x > 0 else -1
	var sy := 1 if dir.y > 0 else -1
	var sz := 1 if dir.z > 0 else -1
	var tdx := absf(1.0 / dir.x) if dir.x != 0.0 else INF
	var tdy := absf(1.0 / dir.y) if dir.y != 0.0 else INF
	var tdz := absf(1.0 / dir.z) if dir.z != 0.0 else INF
	var tmx := ((p.x + (1 if dir.x > 0 else 0)) - origin.x) / dir.x if dir.x != 0.0 else INF
	var tmy := ((p.y + (1 if dir.y > 0 else 0)) - origin.y) / dir.y if dir.y != 0.0 else INF
	var tmz := ((p.z + (1 if dir.z > 0 else 0)) - origin.z) / dir.z if dir.z != 0.0 else INF
	var n := Vector3i.ZERO
	var t := 0.0
	for i in 64:
		var b := get_block(p.x, p.y, p.z)
		if b != 0:
			return {"hit": true, "pos": p, "normal": n, "id": b, "dist": t}
		if tmx < tmy and tmx < tmz:
			t = tmx
			p.x += sx
			tmx += tdx
			n = Vector3i(-sx, 0, 0)
		elif tmy < tmz:
			t = tmy
			p.y += sy
			tmy += tdy
			n = Vector3i(0, -sy, 0)
		else:
			t = tmz
			p.z += sz
			tmz += tdz
			n = Vector3i(0, 0, -sz)
		if t > maxd:
			break
	return {"hit": false}


func stations_near(pos: Vector3, radius: int) -> Array:
	var found := []
	var c := Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))
	for y in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var b := get_block(c.x + x, c.y + y, c.z + z)
				if b == Blocks.WORKBENCH and not found.has("workbench"):
					found.append("workbench")
				elif b == Blocks.FORGE and not found.has("forge"):
					found.append("forge")
				elif b == Blocks.CAMPFIRE and not found.has("campfire"):
					found.append("campfire")
	return found
