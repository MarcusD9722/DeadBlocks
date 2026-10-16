extends Node3D
## Chunked block world. Terrain generation and meshing run on worker threads.

const CH := 16
const H := 64
const CH2 := 256


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
var gen_count := 0
var mesh_count := 0


func setup(s: int, tex) -> void:
	seed_v = s
	max_tasks = clampi(OS.get_processor_count() - 2, 2, 8)
	material = StandardMaterial3D.new()
	material.albedo_texture = tex.atlas
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.roughness = 1.0
	material.metallic_specular = 0.0
	crack_mesh = BoxMesh.new()
	crack_mesh.size = Vector3(1.012, 1.012, 1.012)
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
	var list := []
	for k in best:
		list.append([best[k], k])
	list.sort_custom(func(a, b): return a[0] < b[0])
	for e in list:
		order.append(e[1])
		if int(e[0]) <= render_radius * render_radius + 1:
			mesh_set[e[1]] = true


func _unload_far() -> void:
	var lim := render_radius + 3
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
	c.ready = false


func _reap() -> void:
	var i := tasks.size() - 1
	while i >= 0:
		if WorkerThreadPool.is_task_completed(tasks[i]):
			WorkerThreadPool.wait_for_task_completion(tasks[i])
			tasks.remove_at(i)
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
	for k in order:
		if tasks.size() >= max_tasks:
			return
		var c: Chunk = chunks.get(k)
		if c == null:
			c = Chunk.new()
			c.key = k
			chunks[k] = c
		if not c.has_data:
			if not c.generating:
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
	c.data = d
	c.has_data = true
	c.generating = false
	gen_count += 1


func _task_mesh(k: Vector2i, ver: int, d: PackedByteArray, px: PackedByteArray, nx: PackedByteArray, pz: PackedByteArray, nz: PackedByteArray) -> void:
	var buf := _build(d, px, nx, pz, nz)
	call_deferred("_mesh_done", k, ver, buf)


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
	if ver < c.built_ver:
		return
	c.built_ver = ver
	mesh_count += 1
	if not _near_center(k, render_radius + 3):
		return
	var origin := Vector3(k.x * CH, 0, k.y * CH)
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
	if c.body == null:
		c.body = StaticBody3D.new()
		c.body.collision_layer = 1
		c.body.collision_mask = 0
		c.shape = CollisionShape3D.new()
		c.body.add_child(c.shape)
		add_child(c.body)
		c.body.position = origin
	if buf.faces.size() > 0:
		var sh := ConcavePolygonShape3D.new()
		sh.set_faces(buf.faces)
		c.shape.shape = sh
	else:
		c.shape.shape = null
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
	c.ready = true


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
	var n = crack_nodes.get(p)
	if n != null:
		n.queue_free()
		crack_nodes.erase(p)


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
