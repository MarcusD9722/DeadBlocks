extends Node3D
## Chunked block world. Terrain generation and meshing run on worker threads.

const CH := 16
const H := 64
const CH2 := 256
const BEACON_H := 48.0
## Collision layer of the drawn ground (clients only; nothing collides with it, it is only for
## measuring where the rounded ground is). Layers 1-3 are blocks, mobs and the player.
const VISUAL_LAYER := 8


class Chunk:
	var key := Vector2i.ZERO
	var data := PackedByteArray()
	## Block state besides the id (Blocks.META_*), only where it isn't 0: block index -> meta.
	var meta := {}
	var has_data := false
	var generating := false
	var meshing := false
	var mesh_ver := 0
	var built_ver := -1
	var node: MeshInstance3D = null
	var body: StaticBody3D = null
	var shape: CollisionShape3D = null
	var vbody: StaticBody3D = null
	var vshape: CollisionShape3D = null
	var lights: Array = []
	## The chunk's tree models (M4.6): one MultiMeshInstance3D per model, and where each tree
	## is in them: root -> [MultiMeshInstance3D, instance, transform] (lean_tree).
	var trees: Array = []
	var tree_slots := {}
	## Grass, flowers, rocks and berry bushes (M4.6, Decor): [MultiMeshInstance3D, big], ...
	var decor: Array = []
	var modified := false
	var ready := false


var render_radius := 6
## False in server mode: chunks get collision only (no render mesh, lights or crack overlays).
var render := true
var _headless := DisplayServer.get_name() == "headless"
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
## Finished meshes waiting to go into the world ([key, version, MeshBuf]), and the main-thread
## time per frame for putting them in.
var _done_q: Array = []
const APPLY_BUDGET_US := 3000
var max_tasks := 4
var urgent: Array[Vector2i] = []
## Cubes, boxes and trunks (shaders/blocks.gdshader).
var material: Material
## The smooth ground's material (shaders/terrain.gdshader).
var terrain_material: ShaderMaterial
## Leaves (shaders/leaves.gdshader) and plants (shaders/plants.gdshader, the pixel atlas).
var leaf_material: ShaderMaterial
var plant_material: ShaderMaterial
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
## M4.4 (client): chunks whose blocks arrived or changed, for the map (MapData repaints them).
var track_map := false
var map_dirty := {}
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
	elif G.gfx != null and DisplayServer.get_name() != "headless":
		render_radius = G.gfx.view_radius()  # the graphics quality's view distance
	if G.arg_value("--radius=") != "":
		render_radius = clampi(int(G.arg_value("--radius=")), 2, 12)
	max_tasks = clampi(OS.get_processor_count() - 2, 2, 8)
	if tex == null:
		material = StandardMaterial3D.new()
		return  # dedicated server: nothing is drawn
	SmoothMesher.init_tables()
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://shaders/blocks.gdshader")
	bm.set_shader_parameter("albedo_tex", tex.block_albedo)
	bm.set_shader_parameter("normal_tex", tex.block_normal)
	material = bm
	leaf_material = ShaderMaterial.new()
	leaf_material.shader = preload("res://shaders/leaves.gdshader")
	leaf_material.set_shader_parameter("albedo_tex", tex.leaves_albedo)
	plant_material = ShaderMaterial.new()
	plant_material.shader = preload("res://shaders/plants.gdshader")
	plant_material.set_shader_parameter("atlas", tex.atlas)
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = preload("res://shaders/terrain.gdshader")
	terrain_material.set_shader_parameter("albedo_tex", tex.terrain_albedo)
	terrain_material.set_shader_parameter("normal_tex", tex.terrain_normal)
	if G.gfx != null:
		set_min_light(G.gfx.min_light())
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
	_drain_done()
	_schedule()


## Settings: ambient light left in caves and under roofs.
func set_min_light(v: float) -> void:
	for m in [material, terrain_material, leaf_material, plant_material]:
		if m is ShaderMaterial:
			m.set_shader_parameter("min_light", v)


## The graphics quality changed the view distance.
func set_render_radius(r: int) -> void:
	if r == render_radius or G.arg_value("--radius=") != "":
		return
	render_radius = r
	_rebuild_order()
	_unload_far()


func _near_center(k: Vector2i, lim: int) -> bool:
	for c in centers:
		if absi(k.x - c.x) <= lim and absi(k.y - c.y) <= lim:
			return true
	return false


func _rebuild_order() -> void:
	order.clear()
	mesh_set.clear()
	var r1 := render_radius + (2 if render else 1)
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
			if d2 <= mesh_lim:
				mesh_set[k] = true
	for d2 in buckets.size():
		for k in buckets[d2]:
			# Drawn chunks need all eight neighbours (SmoothMesher); collision only the four sides.
			if mesh_set.has(k) or not render or _next_to_mesh(k):
				order.append(k)
	sched_dirty = true


func _next_to_mesh(k: Vector2i) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if mesh_set.has(k + Vector2i(dx, dz)):
				return true
	return false


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
	c.trees.clear()  # (children of c.node)
	c.tree_slots.clear()
	c.decor.clear()
	if c.body != null:
		c.body.queue_free()
		c.body = null
		c.shape = null
	if c.vbody != null:
		c.vbody.queue_free()
		c.vbody = null
		c.vshape = null
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
	var nb := _neighbours(k)
	if nb.is_empty():
		return false
	c.meshing = true
	var ver := c.mesh_ver
	tasks.append(WorkerThreadPool.add_task(_task_mesh.bind(k, ver, nb), false, "mesh"))
	return true


## The block data of chunk k and its neighbours, nb[(dz + 1) * 3 + dx + 1] (all eight when the
## chunk is drawn, the four sides for collision only), or [] if one isn't there yet.
func _neighbours(k: Vector2i) -> Array:
	var nb := []
	nb.resize(9)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if not render and dx != 0 and dz != 0:
				continue
			var nc: Chunk = chunks.get(k + Vector2i(dx, dz))
			if nc == null or not nc.has_data:
				return []
			nb[(dz + 1) * 3 + dx + 1] = nc.data
	nb.append(chunks[k].meta.duplicate())  # nb[9]: this chunk's block states (a copy for the worker)
	nb.append(k)  # nb[10]: which chunk
	return nb


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
	c.meta = {}
	c.has_data = true
	gen_count += 1
	_apply_pending(c)
	if track_map:
		map_dirty[k] = true


func _task_mesh(k: Vector2i, ver: int, nb: Array) -> void:
	call_deferred("_mesh_done", k, ver, _make_buf(nb))


func _make_buf(nb: Array) -> MeshBuf:
	if render:
		return _build(nb)
	var buf := MeshBuf.new()
	buf.faces = _build_collision(nb[4], nb[5], nb[3], nb[7], nb[1], nb[9])
	return buf


## Server mode: the same scan as _build, but only the collision triangles of solid blocks.
## Faces between two full cubes are left out; a solid box (a bed, a half block, a closed door)
## has all six of each of its boxes.
func _build_collision(d: PackedByteArray, px: PackedByteArray, nx: PackedByteArray, pz: PackedByteArray, nz: PackedByteArray, meta: Dictionary) -> PackedVector3Array:
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
					if Blocks.SOLID[d[i]] and shp[d[i]] >= Blocks.SH_BOX:
						for bx in Blocks.boxes_of(d[i], int(meta.get(i, 0))):
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


func _build(nb: Array) -> MeshBuf:
	var buf := MeshBuf.new()
	var meta: Dictionary = nb[9]
	# Collision is whole blocks, the same as on the server (the rounding is only drawn).
	buf.faces = _build_collision(nb[4], nb[5], nb[3], nb[7], nb[1], meta)
	var gen := WorldGen.new(seed_v)  # (a worker thread: its own)
	nb = _without_trees(nb, buf, gen)  # (the trees are drawn as models)
	var sky := SmoothMesher.build(nb, buf)
	var bins := _ground_bins(buf)
	var d: PackedByteArray = nb[4]
	var px: PackedByteArray = nb[5]
	var nx: PackedByteArray = nb[3]
	var pz: PackedByteArray = nb[7]
	var nz: PackedByteArray = nb[1]
	var opq: Array = Blocks.OPAQUE
	var shp: Array = Blocks.SHAPE
	var tiles: Array = Blocks.TILES
	var nat: Array = SmoothMesher.NAT
	var dirs: Array = MeshBuf.DIRS
	for y in H:
		var yo := y * CH2
		for z in CH:
			var zo := z * CH + yo
			for x in CH:
				var i := x + zo
				var b := d[i]
				if b == 0 or nat[b]:
					continue  # natural ground is part of the smooth surface
				var tl: Array = tiles[b]
				if b == Blocks.BERRY_BUSH:
					var gy := _ground_y(buf, bins, x + 0.5, z + 0.5, y + 0.6)
					var yaw := float(gen.hash2(x + k_x(nb), z + k_z(nb)) % 628) / 100.0
					buf.decor.append([Decor.BERRY, Transform3D(Basis(Vector3.UP, yaw), Vector3(x + 0.5, y if is_nan(gy) else gy, z + 0.5))])
					continue
				if shp[b] == 2:
					buf.cross(x, y, z, tl[1], SmoothMesher.sky_at(sky, x, y, z))
					if b == Blocks.TORCH or b == Blocks.CAMPFIRE:
						buf.lights.append(Vector3i(x, y, z))
					continue
				if shp[b] == Blocks.SH_RAMP:
					buf.ramp(x, y, z, tl, int(meta.get(i, 0)) & Blocks.META_FACING, SmoothMesher.sky_at(sky, x, y + 1, z))
					continue
				if shp[b] >= Blocks.SH_BOX:
					if shp[b] == Blocks.SH_DOOR and (int(meta.get(i, 0)) & Blocks.META_UPPER) != 0:
						tl = [tl[0] + Blocks.DOOR_UPPER_TILES, tl[1] + Blocks.DOOR_UPPER_TILES, tl[2] + Blocks.DOOR_UPPER_TILES]
					for bx in Blocks.boxes_of(b, int(meta.get(i, 0))):
						buf.box(x, y, z, tl, bx[0], bx[1], Blocks.SOLID[b], SmoothMesher.sky_at(sky, x, y + 1, z))
					if b == Blocks.BACKPACK:
						buf.beacons.append(Vector3i(x, y, z))
					continue
				var leaf := b == Blocks.LEAVES
				var solid: bool = Blocks.SOLID[b] and not leaf
				var nbs := [
					d[i + CH2] if y < H - 1 else 0,
					d[i - CH2] if y > 0 else 11,
					d[i + 1] if x < CH - 1 else px[zo],
					d[i - 1] if x > 0 else nx[15 + zo],
					d[i + CH] if z < CH - 1 else pz[x + yo],
					d[i - CH] if z > 0 else nz[x + 15 * CH + yo],
				]
				if b == Blocks.LOG:
					buf.trunk(x, y, z, tl, nbs[0] != Blocks.LOG, nbs[1] != Blocks.LOG,
						SmoothMesher.sky_at(sky, x, y, z), SmoothMesher.sky_at(sky, x, y + 1, z))
					continue
				if leaf:
					var open := []
					for dir in 6:
						if nbs[dir] != Blocks.LEAVES:
							open.append(dir)
					buf.leaf(x, y, z, open, SmoothMesher.sky_at(sky, x, y + 1, z))
					continue
				for dir in 6:
					var nbk: int = nbs[dir]
					# A face shows next to air, see-through blocks and the (rounded) natural ground.
					if nbk == 0 or nat[nbk] or (not opq[nbk] and not (leaf and nbk == b)):
						var dv: Vector3i = dirs[dir]
						var tile: int = tl[0] if dir == 0 else (tl[2] if dir == 1 else tl[1])
						buf.face(dir, x, y, z, tile, solid, SmoothMesher.sky_at(sky, x + dv.x, y + dv.y, z + dv.z),
							_joined(nb, b, x, y, z, dir) if opq[b] else 0)
	for i in buf.t_idx:
		buf.vfaces.append(buf.t_verts[i])
	_decorate(nb, buf, bins, gen)
	return buf


## Which edges of block b's face `dir` at (x, y, z) go on into the same face of a neighbour of
## the same kind (MeshBuf.face's `joined` bits): that neighbour is there and its face shows too.
static func _joined(nb: Array, b: int, x: int, y: int, z: int, dir: int) -> int:
	var n: Vector3i = MeshBuf.DIRS[dir]
	var bits := 0
	for k in 6:
		var e: Vector3i = MeshBuf.DIRS[k]
		if e.x * n.x + e.y * n.y + e.z * n.z != 0:
			continue  # (along the face's own normal)
		var q := Vector3i(x, y, z) + e
		if _nb_block(nb, q.x, q.y, q.z) != b:
			continue
		var over := _nb_block(nb, q.x + n.x, q.y + n.y, q.z + n.z)
		if over != 0 and Blocks.OPAQUE[over] and not SmoothMesher.NAT[over]:
			continue  # (its face is covered)
		# DIRS order is +y -y +x -x +z -z; the bits go -x +x -y +y -z +z.
		bits |= [8, 4, 2, 1, 32, 16][k]
	return bits


static func k_x(nb: Array) -> int:
	return (nb[10] as Vector2i).x * CH


static func k_z(nb: Array) -> int:
	return (nb[10] as Vector2i).y * CH


## Grass, flowers and stones on the land (M4.6, Decor), on the drawn ground of each column whose
## top is open to the sky: picked from the seed, so they come back the same.
func _decorate(nb: Array, buf: MeshBuf, bins: Array, gen: WorldGen) -> void:
	var d: PackedByteArray = nb[4]
	var bx := k_x(nb)
	var bz := k_z(nb)
	for z in CH:
		for x in CH:
			var y := H - 1
			while y > 0 and d[x + z * CH + y * CH2] == 0:
				y -= 1
			var top := d[x + z * CH + y * CH2]
			if y >= H - 1 or not SmoothMesher.NAT[top]:
				continue
			var model := Decor.pick(gen, bx + x, bz + z, top, gen.biome_at(bx + x, bz + z) if top == Blocks.GRASS else 0)
			if model < 0:
				continue
			var sp := Decor.spot(gen, bx + x, bz + z, model)
			var gy := _ground_y(buf, bins, x + sp[0], z + sp[1], y + 1.6)
			if is_nan(gy) or gy < y - 0.6:
				continue
			var b := Basis(Vector3.UP, sp[2]).scaled(Vector3.ONE * float(sp[3]))
			buf.decor.append([model, Transform3D(b, Vector3(x + sp[0], gy - 0.04, z + sp[1]))])


## The drawn ground's triangles (SmoothMesher) by the columns they cover: 256 lists of the first
## index of each triangle in buf.t_idx, for _ground_y.
static func _ground_bins(buf: MeshBuf) -> Array:
	var bins := []
	bins.resize(CH * CH)
	for i in bins.size():
		bins[i] = PackedInt32Array()
	var v := buf.t_verts
	var idx := buf.t_idx
	for t in range(0, idx.size(), 3):
		var a := v[idx[t]]
		var b := v[idx[t + 1]]
		var c := v[idx[t + 2]]
		var x0 := clampi(floori(minf(a.x, minf(b.x, c.x))), 0, CH - 1)
		var x1 := clampi(floori(maxf(a.x, maxf(b.x, c.x))), 0, CH - 1)
		var z0 := clampi(floori(minf(a.z, minf(b.z, c.z))), 0, CH - 1)
		var z1 := clampi(floori(maxf(a.z, maxf(b.z, c.z))), 0, CH - 1)
		for zz in range(z0, z1 + 1):
			for xx in range(x0, x1 + 1):
				bins[xx + zz * CH].append(t)
	return bins


## The height of the drawn ground at (x, z) in the chunk: the highest upward-facing triangle there
## that is not above `below` (NAN if none).
static func _ground_y(buf: MeshBuf, bins: Array, x: float, z: float, below: float) -> float:
	var col := clampi(floori(x), 0, CH - 1) + clampi(floori(z), 0, CH - 1) * CH
	var best := NAN
	var v := buf.t_verts
	var idx := buf.t_idx
	for t in bins[col]:
		var a := v[idx[t]]
		var b := v[idx[t + 1]]
		var c := v[idx[t + 2]]
		var d := (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
		if absf(d) < 1e-6:
			continue  # (seen edge-on from above)
		var u := ((x - a.x) * (c.z - a.z) - (c.x - a.x) * (z - a.z)) / d
		var w := ((b.x - a.x) * (z - a.z) - (x - a.x) * (b.z - a.z)) / d
		if u < -0.001 or w < -0.001 or u + w > 1.002:
			continue
		var n := (b - a).cross(c - a)
		if absf(n.y) < 0.3 * n.length():
			continue  # (too steep to stand anything on)
		var y := a.y + u * (b.y - a.y) + w * (c.y - a.y)
		if y <= below and (is_nan(best) or y > best):
			best = y
	return best


## The block data the picture is made from (M4.6): nb with the natural trees that still stand
## (Trees) taken out, as air, so the ground, cubes and leaves are drawn as if they were not
## there; the trees rooted in this chunk go into buf.trees, to be drawn as models. Collision
## still comes from nb itself. A chunk's data is copied only when a tree is taken out of it.
func _without_trees(nb: Array, buf: MeshBuf, gen: WorldGen) -> Array:
	var out := nb.duplicate()
	var k: Vector2i = nb[10]
	var bx := k.x * CH
	var bz := k.y * CH
	var block := func(c: Vector3i) -> int: return _nb_block(nb, c.x - bx, c.y, c.z - bz)
	var copied := {}
	# Trees whose cells reach the middle chunk or the SmoothMesher.P blocks it reads around it.
	var reach := SmoothMesher.P + 2
	for tz in range(bz - reach, bz + CH + reach):
		for tx in range(bx - reach, bx + CH + reach):
			var t := Trees.at(gen, tx, tz)
			if t.is_empty() or not Trees.standing(t, block):
				continue
			for c in Trees.cells(gen, t):
				var cell: Vector3i = c[0]
				var lx := cell.x - bx
				var lz := cell.z - bz
				if cell.y < 0 or cell.y >= H or lx < -CH or lx >= 2 * CH or lz < -CH or lz >= 2 * CH:
					continue
				var cx := floori(lx / 16.0)
				var cz := floori(lz / 16.0)
				var ci := (cz + 1) * 3 + cx + 1
				var d: PackedByteArray = out[ci]
				if d.is_empty():
					continue
				var i := (lx - cx * CH) + (lz - cz * CH) * CH + cell.y * CH2
				if d[i] != (Blocks.LOG if c[1] else Blocks.LEAVES):
					continue
				if not copied.has(ci):
					d = d.duplicate()
					copied[ci] = true
				d[i] = 0
				out[ci] = d
			if tx >= bx and tx < bx + CH and tz >= bz and tz < bz + CH:
				buf.trees.append([t["model"], Trees.xform(t, Vector3(bx, 0, bz)), t["root"]])
	return out


## A block in the 3 x 3 chunks around (nb), by its position in the middle chunk's coordinates.
static func _nb_block(nb: Array, lx: int, y: int, lz: int) -> int:
	if y < 0 or y >= H:
		return 0
	var cx := floori(lx / 16.0)
	var cz := floori(lz / 16.0)
	if absi(cx) > 1 or absi(cz) > 1:
		return 0
	var data = nb[(cz + 1) * 3 + cx + 1]
	if data == null or (data as PackedByteArray).is_empty():
		return 0
	return (data as PackedByteArray)[(lx - cx * CH) + (lz - cz * CH) * CH + y * CH2]


func _mesh_done(k: Vector2i, ver: int, buf: MeshBuf) -> void:
	if render:
		_done_q.append([k, ver, buf])  # put in the world a few at a time (_drain_done)
		return
	_finish_mesh(k, ver, buf)


## Drawn chunks: finished meshes go into the world within a small time budget per frame, so
## streaming new land never stalls a frame (or the game's network replies) for long.
func _drain_done() -> void:
	var t0 := Time.get_ticks_usec()
	while not _done_q.is_empty():
		var d: Array = _done_q.pop_front()
		_finish_mesh(d[0], d[1], d[2])
		if Time.get_ticks_usec() - t0 > APPLY_BUDGET_US:
			break


func _finish_mesh(k: Vector2i, ver: int, buf: MeshBuf) -> void:
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
	var am := ArrayMesh.new()
	if buf.t_verts.size() > 0:
		var ta := []
		ta.resize(Mesh.ARRAY_MAX)
		ta[Mesh.ARRAY_VERTEX] = buf.t_verts
		ta[Mesh.ARRAY_NORMAL] = buf.t_norms
		ta[Mesh.ARRAY_COLOR] = buf.t_cols
		ta[Mesh.ARRAY_TEX_UV] = buf.t_uv
		ta[Mesh.ARRAY_TEX_UV2] = buf.t_uv2
		ta[Mesh.ARRAY_INDEX] = buf.t_idx
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ta)
		am.surface_set_material(am.get_surface_count() - 1, terrain_material)
	if buf.verts.size() > 0:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = buf.verts
		arr[Mesh.ARRAY_NORMAL] = buf.norms
		arr[Mesh.ARRAY_TEX_UV] = buf.uvs
		arr[Mesh.ARRAY_TEX_UV2] = buf.uv2s
		arr[Mesh.ARRAY_COLOR] = buf.cols
		arr[Mesh.ARRAY_INDEX] = buf.idx
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(am.get_surface_count() - 1, material)
	for part in [[buf.l_verts, buf.l_norms, buf.l_uvs, buf.l_cols, buf.l_idx, leaf_material],
			[buf.p_verts, buf.p_norms, buf.p_uvs, buf.p_cols, buf.p_idx, plant_material]]:
		if (part[0] as PackedVector3Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = part[0]
		arr[Mesh.ARRAY_NORMAL] = part[1]
		arr[Mesh.ARRAY_TEX_UV] = part[2]
		arr[Mesh.ARRAY_COLOR] = part[3]
		arr[Mesh.ARRAY_INDEX] = part[4]
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(am.get_surface_count() - 1, part[5])
	c.node.mesh = am if am.get_surface_count() > 0 else null
	_apply_collision(c, origin, buf.faces)
	if not _headless:
		_apply_visual_ground(c, origin, buf.vfaces)  # (nothing is shown in a headless game)
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
	_apply_trees(c, buf)
	_apply_decor(c, buf)
	for bp in buf.beacons:
		var m := MeshInstance3D.new()
		m.mesh = beacon_mesh
		m.material_override = beacon_mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.node.add_child(m)
		m.position = Vector3(bp) + Vector3(0.5, 0.62 + BEACON_H * 0.5, 0.5)
		c.lights.append(m)
	c.ready = true


## The chunk's trees as models (M4.6): one MultiMesh per model kind.
func _apply_trees(c: Chunk, buf: MeshBuf) -> void:
	for n in c.trees:
		if is_instance_valid(n):
			n.queue_free()
	c.trees.clear()
	c.tree_slots.clear()
	if _headless or buf.trees.is_empty():
		return
	var by_model := {}
	for t in buf.trees:
		if not by_model.has(t[0]):
			by_model[t[0]] = []
		by_model[t[0]].append(t)
	for model in by_model:
		var mesh := Trees.mesh(model)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var list: Array = by_model[model]
		mm.instance_count = list.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		for j in list.size():
			mm.set_instance_transform(j, list[j][1])
			c.tree_slots[list[j][2]] = [mmi, j, list[j][1]]
		c.node.add_child(mmi)
		c.trees.append(mmi)


## The chunk's decor (M4.6): one MultiMesh per Decor model; the small things are drawn only
## within plant_range (Settings: Grass and flowers), the big ones further.
func _apply_decor(c: Chunk, buf: MeshBuf) -> void:
	for e in c.decor:
		if is_instance_valid(e[0]):
			e[0].queue_free()
	c.decor.clear()
	if _headless or buf.decor.is_empty():
		return
	var by_model := {}
	for t in buf.decor:
		if not by_model.has(t[0]):
			by_model[t[0]] = []
		by_model[t[0]].append(t[1])
	for model in by_model:
		var mesh := Decor.mesh(model)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var list: Array = by_model[model]
		mm.instance_count = list.size()
		for j in list.size():
			mm.set_instance_transform(j, list[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var big := Decor.is_big(model)
		if not big:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.node.add_child(mmi)
		var e := [mmi, big, model == Decor.BERRY]
		_decor_range(e)
		c.decor.append(e)


## How far grass and flowers are drawn (0: not at all); the bushes and rocks go twice as far,
## the berry bushes (blocks you can pick) always.
var plant_range := 56.0

func set_plant_range(r: float) -> void:
	plant_range = r
	for k in chunks:
		for e in (chunks[k] as Chunk).decor:
			_decor_range(e)


func _decor_range(e: Array) -> void:
	var mmi: MultiMeshInstance3D = e[0]
	if not is_instance_valid(mmi):
		return
	if e[2]:
		return
	var r := maxf(plant_range * 2.0, 64.0) if e[1] else plant_range
	mmi.visible = r > 0.0
	# (Measured to the middle of the chunk: half a chunk more, so nearby ones never pop.)
	mmi.visibility_range_end = r + 11.0
	mmi.visibility_range_end_margin = 6.0


## A standing tree leans by `angle` about `axis` through its foot (the tree being chopped
## shakes; angle 0 stands it up again).
func lean_tree(root: Vector3i, axis: Vector3, angle: float) -> void:
	var c: Chunk = chunks.get(Vector2i(root.x >> 4, root.z >> 4))
	if c == null or not c.tree_slots.has(root):
		return
	var slot: Array = c.tree_slots[root]
	if not is_instance_valid(slot[0]):
		return
	var xf: Transform3D = slot[2]
	if angle != 0.0 and axis != Vector3.ZERO:
		var foot := Vector3(root.x & 15, root.y, root.z & 15) + Vector3(0.5, 0.0, 0.5)
		xf = Transform3D(Basis(axis.normalized(), angle), foot) * Transform3D(Basis.IDENTITY, -foot) * xf
	(slot[0] as MultiMeshInstance3D).multimesh.set_instance_transform(slot[1], xf)


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


func _apply_visual_ground(c: Chunk, origin: Vector3, faces: PackedVector3Array) -> void:
	if c.vbody == null:
		c.vbody = StaticBody3D.new()
		c.vbody.collision_layer = VISUAL_LAYER
		c.vbody.collision_mask = 0
		c.vshape = CollisionShape3D.new()
		c.vbody.add_child(c.vshape)
		add_child(c.vbody)
		c.vbody.position = origin
	if faces.size() > 0:
		var sh := ConcavePolygonShape3D.new()
		sh.set_faces(faces)
		c.vshape.shape = sh
	else:
		c.vshape.shape = null


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
	var nb := _neighbours(k)
	if nb.is_empty():
		return
	c.built_ver = c.mesh_ver
	mesh_count += 1
	apply_mesh(c, k, _make_buf(nb))


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
func preload_chunk(k: Vector2i, data: PackedByteArray, meta := {}) -> void:
	var c := Chunk.new()
	c.key = k
	c.data = data
	c.meta = meta
	c.has_data = true
	c.modified = true
	chunks[k] = c
	sched_dirty = true


## Server saving: the edited chunks changed since the last save, as [[key, data, meta], ...]
## (copies: later edits don't change them). Forgets them as saved.
func take_unsaved() -> Array:
	var out := []
	for k in save_dirty:
		var c: Chunk = chunks.get(k)
		if c != null and c.has_data:
			out.append([k, c.data.duplicate(), c.meta.duplicate()])
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


func chunk_meta(k: Vector2i) -> Dictionary:
	var c: Chunk = chunks.get(k)
	return c.meta if c != null and c.has_data else {}


## The block state of the block at p besides its id (Blocks.META_*; 0 for most blocks).
func block_meta(p: Vector3i) -> int:
	if p.y < 0 or p.y >= H:
		return 0
	var c: Chunk = chunks.get(Vector2i(p.x >> 4, p.z >> 4))
	if c == null or c.meta.is_empty():
		return 0
	return int(c.meta.get((p.x & 15) + (p.z & 15) * CH + p.y * CH2, 0))


func set_block(p: Vector3i, id: int, meta := 0) -> bool:
	if p.y < 0 or p.y >= H:
		return false
	var k := Vector2i(p.x >> 4, p.z >> 4)
	var c: Chunk = chunks.get(k)
	if c == null or not c.has_data:
		return false
	var lx := p.x & 15
	var lz := p.z & 15
	var i := lx + lz * CH + p.y * CH2
	c.data[i] = id
	if meta != 0:
		c.meta[i] = meta
	else:
		c.meta.erase(i)
	c.modified = true
	if record_edits:
		edits_out.append([p, id, meta])
		save_dirty[k] = true
	if track_map:
		map_dirty[k] = true
	_clear_damage(p)
	_dirty(k)
	# The smooth ground near a chunk border is shaped by blocks up to SmoothMesher.P away.
	var reach := SmoothMesher.P if render else 0
	var ex := -1 if lx <= reach else (1 if lx >= 15 - reach else 0)
	var ez := -1 if lz <= reach else (1 if lz >= 15 - reach else 0)
	if ex != 0:
		_dirty(k + Vector2i(ex, 0))
	if ez != 0:
		_dirty(k + Vector2i(0, ez))
	if ex != 0 and ez != 0:
		_dirty(k + Vector2i(ex, ez))
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


## The other half of a door (two blocks tall), or Vector3i.MIN if p isn't a door's.
func door_partner(p: Vector3i) -> Vector3i:
	var id := get_blockv(p)
	if not Blocks.is_door(id):
		return Vector3i.MIN
	var q := p + (Vector3i.DOWN if block_meta(p) & Blocks.META_UPPER else Vector3i.UP)
	return q if get_blockv(q) == id else Vector3i.MIN


## Take a block out, and the other half with it if it was a door's.
func clear_block(p: Vector3i) -> void:
	var q := door_partner(p)
	set_block(p, Blocks.AIR)
	if q != Vector3i.MIN:
		set_block(q, Blocks.AIR)


## Server: blocks zombies (or spikes) broke this tick, as [pos, id] (NetServer turns a broken
## storage box into a bag with its things).
var destroyed: Array = []


## Zombies (and spikes wearing down) chip away at blocks. Returns true if it broke.
func damage_block(p: Vector3i, amount: float) -> bool:
	var id := get_blockv(p)
	if id <= 0 or id == Blocks.BEDROCK:
		return false
	var hp: float = Blocks.ZHP[id]
	var d: float = float(damage.get(p, 0.0)) + amount
	if d >= hp:
		clear_block(p)
		if record_edits:
			destroyed.append([p, id])
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


## A hammer's repair: the block is whole again.
func repair_block(p: Vector3i) -> void:
	if record_edits and crack_stage.has(p):
		cracks_out.append([p, -1])
	_clear_damage(p)


## How damaged the block at p is (0 whole, 1 about to break).
func damage_of(p: Vector3i) -> float:
	var id := get_blockv(p)
	if not damage.has(p) or id <= 0:
		return 0.0
	return float(damage[p]) / float(Blocks.ZHP[id])


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
func net_chunk(seq: int, k: Vector2i, data: PackedByteArray, meta := {}) -> void:
	if not sub_state.has(k) or data.size() != CH2 * H:
		return
	var c: Chunk = chunks.get(k)
	if c == null:
		c = Chunk.new()
		c.key = k
		chunks[k] = c
	c.data = data
	c.meta = meta
	c.has_data = true
	c.modified = true
	sub_state[k] = SUB_FRESH
	sub_seq[k] = seq
	_apply_pending(c)
	if track_map:
		map_dirty[k] = true
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			_dirty(k + Vector2i(dx, dz))  # the smooth ground of all eight neighbours reads this chunk
	sched_dirty = true


## S_EDITS: one batch of block changes, grouped by chunk ([key, [[index, id, meta], ...]]).
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
				pending[k].append([seq, e[0], e[1], e[2]])
			continue
		if seq <= int(sub_seq.get(k, -1)):
			continue  # already in our copy
		for e in g[1]:
			set_block(pos_of(k, e[0]), e[1], e[2])


## Edits that arrived before the chunk's data: apply the ones newer than the data.
func _apply_pending(c: Chunk) -> void:
	var list: Array = pending.get(c.key, [])
	pending.erase(c.key)
	var base := int(sub_seq.get(c.key, -1))
	for e in list:
		if e[0] > base:
			c.data[e[1]] = e[2]
			if e[3] != 0:
				c.meta[e[1]] = e[3]
			else:
				c.meta.erase(e[1])
			c.modified = true


## S_CRACKS: a zombie is chipping at this block (stage 255: it was repaired).
func net_crack(p: Vector3i, stage: int) -> void:
	if stage == 255:
		_clear_damage(p)
		return
	var id := get_blockv(p)
	if id == Blocks.AIR:
		return
	damage[p] = (stage + 0.5) / 4.0 * float(Blocks.ZHP[id])  # (about: a hammer can see it needs a repair)
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
				if not c.meta.is_empty():
					ctx.update(Proto.meta_bytes(c.meta))  # (doors' and ramps' facings too)
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
				if Blocks.STATIONS.has(b) and not found.has(Blocks.STATIONS[b]):
					found.append(Blocks.STATIONS[b])
	return found
