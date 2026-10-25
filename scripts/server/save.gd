extends Node
## The server's save files (M1.5). Layout, under the data folder (--data=DIR, default user://server):
##   worlds/<world>/world.json          format, versions, seed, day, time, backpacks (M2),
##                                      storage boxes (M4.2)
##   worlds/<world>/players/<name>.json name, PIN hash, position, look, health, food, kills,
##                                      inventory, bed (M2), play time
##   worlds/<world>/chunks/<x>_<z>.bin  edited chunks: header + SHA-256 + zstd(16 KB of blocks)
##                                      + block states (M4.2, "DBC2"; "DBC1" files have none)
##   worlds/<world>/world.lock          refuses a second server on the same world
##   worlds/<world>/damaged/            files that failed their check (moved, never loaded)
##   backups/<world>-<date>.zip         copies of the world folder
##   control/*.cmd                      commands from dbctl: stop, save, backup, kick, reset-pin, say
##   status.json                        written every minute
## Writes are crash-safe: each file goes to .tmp, is flushed to disk (`sync`, Linux), then renamed
## over the old one. Saving copies the data on the main thread and writes on a worker thread.
## Zombies, animals, cracks and chat are not saved.

## 2 (M2): backpacks in world.json, and block ids older servers don't know.
## 3 (M4.2): block states in the chunk files (DBC2), storage boxes in world.json.
const FORMAT := 3
const CHUNK_MAGIC := "DBC2"
const CHUNK_MAGIC_V1 := "DBC1"
const LOCK_STALE_S := 90
const BACKUPS_KEEP := 20
const BACKUP_DAYS := 14

var data_dir := ""
var world_name := "main"
var world_dir := ""
var autosave_s := 60.0
## Set by open(): what the saved world says (or the new world's values).
var seed_v := 0
var day := 1
var time := 7.0
## world.json's "backpacks" and "boxes" as saved (NetServer reads them).
var backpacks: Array = []
var boxes: Array = []
## world.json's "ground" (M4.3): spears and arrows lying in the world.
var ground: Array = []
var is_new := false
var error := ""
var warnings: Array = []
var last_save_unix := 0
var last_save_ok := true

var _task := -1
var _task_result := {}
var _autosave_t := 0.0
var _lock_t := 0.0
var _control_t := 0.0
var _status_t := 0.0
var _last_backup_unix := 0
var _started_unix := 0
var _mutex := Mutex.new()


static func _sha(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()


func path(rel: String) -> String:
	return world_dir.path_join(rel)


## Prepare the folders, take the lock and read world.json. Returns false (with `error` set) when
## the server must not start.
func open(dir: String, world: String, new_seed: int, new_world := false) -> bool:
	data_dir = ProjectSettings.globalize_path(dir)
	world_name = world
	world_dir = data_dir.path_join("worlds").path_join(world_name)
	_started_unix = int(Time.get_unix_time_from_system())
	for d in [world_dir, path("players"), path("chunks"), data_dir.path_join("backups"), data_dir.path_join("control")]:
		DirAccess.make_dir_recursive_absolute(d)
	if not _take_lock():
		return false
	# Commands left from before this server started (a stop for a server that had crashed) are
	# stale: carrying them out now would stop this one at once.
	for cmd in read_control():
		print("SERVER ignoring an old control command: %s" % cmd)
	if not _open_world(new_seed, new_world):
		release_lock()
		return false
	return true


func _open_world(new_seed: int, new_world: bool) -> bool:
	_remove_tmp_files()
	if new_world and FileAccess.file_exists(path("world.json")):
		# Keep the old world in backups, then start over.
		backup("before-new-world")
		for sub in ["chunks", "players"]:
			for f in DirAccess.get_files_at(path(sub)):
				DirAccess.remove_absolute(path(sub).path_join(f))
		DirAccess.remove_absolute(path("world.json"))
	if not FileAccess.file_exists(path("world.json")):
		is_new = true
		seed_v = new_seed
		day = 1
		time = 7.0
		return save_world_meta(day, time)
	var meta = _read_json(path("world.json"))
	if meta == null:
		error = "%s is damaged. Restore the world from %s, or move it away to start a new world." % [path("world.json"), data_dir.path_join("backups")]
		return false
	if int(meta.get("format", 0)) > FORMAT:
		error = "This world was saved by a newer version of Dead Blocks (%s). Update the server first." % meta.get("game", "?")
		return false
	if int(meta.get("worldgen", 0)) != WorldGen.VERSION:
		error = "This world was made with terrain version %d, but this server builds version %d: it would look different. Use the matching server version." % [int(meta.get("worldgen", 0)), WorldGen.VERSION]
		return false
	seed_v = int(meta["seed"])
	day = int(meta.get("day", 1))
	time = float(meta.get("time", 7.0))
	backpacks = meta.get("backpacks", []) if meta.get("backpacks") is Array else []
	boxes = meta.get("boxes", []) if meta.get("boxes") is Array else []
	ground = meta.get("ground", []) if meta.get("ground") is Array else []
	return true


func save_world_meta(d: int, t: float) -> bool:
	var meta := {"format": FORMAT, "game": G.VERSION, "worldgen": WorldGen.VERSION, "seed": seed_v,
		"day": d, "time": t, "saved": int(Time.get_unix_time_from_system())}
	return _write_files([[path("world.json"), _json_bytes(meta)]])


## Every saved edited chunk, checked: [[key, data, meta], ...]. Damaged ones are moved to damaged/.
func load_chunks() -> Array:
	var out := []
	for f in DirAccess.get_files_at(path("chunks")):
		if not f.ends_with(".bin"):
			continue
		var full := path("chunks").path_join(f)
		var got := _read_chunk(full)
		if got.is_empty():
			_quarantine(full)
		else:
			out.append(got)
	return out


## Every saved player: {lower-case name: account dict as NetServer keeps it}.
func load_players() -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(path("players")):
		if not f.ends_with(".json"):
			continue
		var full := path("players").path_join(f)
		var p = _read_json(full)
		if p == null or not p.has("name"):
			_quarantine(full)
			continue
		var acc := {
			"name": str(p["name"]),
			"pin_key": Marshalls.base64_to_raw(str(p["pin"])) if str(p.get("pin", "")) != "" else PackedByteArray(),
			"fails": 0, "locked_until": 0.0,
			"pos": _vec(p.get("pos")), "yaw": float(p.get("yaw", 0.0)),
			"health": float(p.get("health", 100.0)), "food": float(p.get("food", 100.0)),
			"kills": int(p.get("kills", 0)), "bed": _bpos(p.get("bed")),
			"play_s": float(p.get("play_s", 0.0)), "inv": Inventory.new(),
		}
		var slots: Array = p.get("inv", [])
		for i in mini(slots.size(), Inventory.SIZE):
			var sl = slots[i]
			if sl is Array and sl.size() == 2 and int(sl[1]) > 0:
				acc["inv"].slots[i] = {"id": int(sl[0]), "n": int(sl[1])}
		out[acc["name"].to_lower()] = acc
	return out


static func _vec(v) -> Vector3:
	if v is Array and v.size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.INF


static func _bpos(v) -> Vector3i:
	if v is Array and v.size() == 3:
		return Vector3i(int(v[0]), int(v[1]), int(v[2]))
	return Vector3i.MIN


static func player_json(acc: Dictionary) -> Dictionary:
	var inv := []
	for sl in acc["inv"].slots:
		inv.append(null if sl == null else [int(sl["id"]), int(sl["n"])])
	var pos: Vector3 = acc["pos"]
	var bed: Vector3i = acc["bed"]
	var pin: PackedByteArray = acc["pin_key"]  # empty after a PIN reset
	return {"format": FORMAT, "name": acc["name"], "pin": Marshalls.raw_to_base64(pin) if not pin.is_empty() else "",
		"pos": [pos.x, pos.y, pos.z], "yaw": acc["yaw"], "health": acc["health"], "food": acc["food"],
		"kills": acc["kills"], "bed": null if bed == Vector3i.MIN else [bed.x, bed.y, bed.z], "play_s": acc.get("play_s", 0.0), "inv": inv}


func player_file(key: String) -> String:
	return path("players").path_join(key.validate_filename() + ".json")


static func chunk_file_name(k: Vector2i) -> String:
	return "%d_%d.bin" % [k.x, k.y]


# ------------------------------------------------------------ saving

## Save on a worker thread. `chunks`: [[key, data], ...] (the arrays are copies the main thread
## no longer changes); `players`: {key: account}; `extra`: more world.json keys (plain data).
## Returns false if a save is still running.
func save_async(d: int, t: float, chunks: Array, players: Dictionary, extra := {}) -> bool:
	if _task >= 0:
		return false
	var job := _job(d, t, chunks, players, extra)
	_task = WorkerThreadPool.add_task(_run_job.bind(job), false, "save")
	return true


## Save now, on this thread (stopping). Waits for a running save first.
func save_now(d: int, t: float, chunks: Array, players: Dictionary, extra := {}) -> bool:
	finish()
	var job := _job(d, t, chunks, players, extra)
	_run_job(job)
	return _collect(job)


func busy() -> bool:
	return _task >= 0


## Wait for a running save and report it.
func finish() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_collect(_task_result)


func _job(d: int, t: float, chunks: Array, players: Dictionary, extra: Dictionary) -> Dictionary:
	var pl := {}
	for key in players:
		pl[key] = player_json(players[key])  # plain data, safe to use on another thread
	return {"day": d, "time": t, "chunks": chunks, "players": pl, "extra": extra.duplicate(true), "ok": false, "ms": 0.0, "err": ""}


func _run_job(job: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var files := []
	for c in job["chunks"]:
		files.append([path("chunks").path_join(chunk_file_name(c[0])), _chunk_bytes(c[0], c[1], c[2])])
	for key in job["players"]:
		files.append([player_file(key), _json_bytes(job["players"][key])])
	var meta := {"format": FORMAT, "game": G.VERSION, "worldgen": WorldGen.VERSION, "seed": seed_v,
		"day": job["day"], "time": job["time"], "saved": int(Time.get_unix_time_from_system())}
	meta.merge(job["extra"])
	files.append([path("world.json"), _json_bytes(meta)])
	job["ok"] = _write_files(files)
	job["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	_mutex.lock()
	_task_result = job
	_mutex.unlock()


func _collect(job: Dictionary) -> bool:
	if job.is_empty():
		return true
	last_save_ok = job["ok"]
	if job["ok"]:
		last_save_unix = int(Time.get_unix_time_from_system())
		print("SERVER saved %d chunks and %d players in %.0f ms" % [job["chunks"].size(), job["players"].size(), job["ms"]])
	else:
		printerr("SERVER SAVE FAILED: %s" % job.get("err", "could not write the files"))
	return job["ok"]


## Called by NetServer every frame: is a background save done?
func poll() -> Dictionary:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_mutex.lock()
		var job := _task_result
		_mutex.unlock()
		_collect(job)
		return job
	return {}


## Write every file to .tmp, flush them to disk, then rename each over the old file.
func _write_files(files: Array) -> bool:
	var tmps := PackedStringArray()
	for f in files:
		var tmp: String = f[0] + ".tmp"
		var fa := FileAccess.open(tmp, FileAccess.WRITE)
		if fa == null:
			return false
		fa.store_buffer(f[1])
		fa.close()
		tmps.append(tmp)
	_sync(tmps)
	for f in files:
		if DirAccess.rename_absolute(f[0] + ".tmp", f[0]) != OK:
			return false
	# The renames themselves must reach the disk too.
	var dirs := {}
	for f in files:
		dirs[(f[0] as String).get_base_dir()] = true
	_sync(PackedStringArray(dirs.keys()))
	return true


## Godot never calls fsync; on Linux `sync FILE...` does (coreutils 8.24+).
static func _sync(paths: PackedStringArray) -> void:
	if OS.get_name() == "Linux" and not paths.is_empty():
		OS.execute("sync", paths)


static func _json_bytes(d: Dictionary) -> PackedByteArray:
	var text := JSON.stringify(d, "\t", true)
	return (text + "\n#sha256 " + _sha(text.to_utf8_buffer()).hex_encode() + "\n").to_utf8_buffer()


## The JSON in `file`, or null if it is missing, damaged or its checksum doesn't match.
static func _read_json(file: String):
	if not FileAccess.file_exists(file):
		return null
	var text := FileAccess.get_file_as_string(file)
	var at := text.rfind("\n#sha256 ")
	if at < 0:
		return null
	var body := text.substr(0, at)
	if _sha(body.to_utf8_buffer()).hex_encode() != text.substr(at + 9).strip_edges():
		return null
	var v = JSON.parse_string(body)
	return v if v is Dictionary else null


## DBC2: magic, key x, z s32, block bytes u32, zstd length u32, state count u32, SHA-256 of the
## blocks and the states, zstd(blocks), states (index u16, state u8 each).
static func _chunk_bytes(k: Vector2i, data: PackedByteArray, meta: Dictionary) -> PackedByteArray:
	var packed := data.compress(FileAccess.COMPRESSION_ZSTD)
	var ms := Proto.meta_bytes(meta)
	var b := StreamPeerBuffer.new()
	b.put_data(CHUNK_MAGIC.to_ascii_buffer())
	b.put_32(k.x)
	b.put_32(k.y)
	b.put_u32(data.size())
	b.put_u32(packed.size())
	b.put_u32(meta.size())
	b.put_data(_sha(data + ms))
	b.put_data(packed)
	b.put_data(ms)
	return b.data_array


## [key, data, meta] from a chunk file (DBC2, or DBC1 from before M4.2), or [] if it is damaged.
static func _read_chunk(file: String) -> Array:
	var raw := FileAccess.get_file_as_bytes(file)
	if raw.size() < 48:
		return []
	var magic := raw.slice(0, 4).get_string_from_ascii()
	var b := StreamPeerBuffer.new()
	b.data_array = raw
	b.seek(4)
	if magic == CHUNK_MAGIC_V1:
		var k1 := Vector2i(b.get_32(), b.get_32())
		var size1 := b.get_u32()
		var sha1: PackedByteArray = b.get_data(32)[1]
		if size1 != 16384:
			return []
		var data1 := raw.slice(48).decompress(size1, FileAccess.COMPRESSION_ZSTD)
		if data1.size() != size1 or _sha(data1) != sha1:
			return []
		return [k1, data1, {}]
	if magic != CHUNK_MAGIC or raw.size() < 56:
		return []
	var k := Vector2i(b.get_32(), b.get_32())
	var size := b.get_u32()
	var zlen := b.get_u32()
	var count := b.get_u32()
	var sha: PackedByteArray = b.get_data(32)[1]
	if size != 16384 or 56 + zlen + count * 3 != raw.size():
		return []
	var data := raw.slice(56, 56 + zlen).decompress(size, FileAccess.COMPRESSION_ZSTD)
	var ms := raw.slice(56 + zlen)
	if data.size() != size or _sha(data + ms) != sha:
		return []
	var meta := {}
	var mb := StreamPeerBuffer.new()
	mb.data_array = ms
	for i in count:
		var idx := mb.get_u16()
		meta[idx] = mb.get_u8()
	return [k, data, meta]


func _quarantine(file: String) -> void:
	DirAccess.make_dir_recursive_absolute(path("damaged"))
	var dest := path("damaged").path_join(file.get_file() + ".%d" % int(Time.get_unix_time_from_system()))
	DirAccess.rename_absolute(file, dest)
	var w := "Damaged save file %s was moved to %s and not loaded." % [file.get_file(), dest]
	warnings.append(w)
	printerr("SERVER WARNING: " + w)


## Leftover .tmp files from a save that was cut off. Usually the real file is still there and the
## .tmp is dropped. On Windows a rename removes the old file first, so a crash in between leaves
## only the .tmp: if it passes its check, it becomes the real file.
func _remove_tmp_files() -> void:
	for sub in ["", "players", "chunks"]:
		var d := path(sub) if sub != "" else world_dir
		for f in DirAccess.get_files_at(d):
			if not f.ends_with(".tmp"):
				continue
			var tmp := d.path_join(f)
			var real := tmp.trim_suffix(".tmp")
			var ok := false
			if not FileAccess.file_exists(real):
				ok = not _read_chunk(tmp).is_empty() if real.ends_with(".bin") else _read_json(tmp) != null
			if ok:
				DirAccess.rename_absolute(tmp, real)
				print("SERVER recovered %s from an unfinished save" % real.get_file())
			else:
				DirAccess.remove_absolute(tmp)


# ------------------------------------------------------------ lock, backups, control, status

## The lock file holds this server's process id and is rewritten every 10 s (dbctl's watchdog
## restarts a server whose lock goes quiet: it has stopped responding). It is left over
## from a crash if that process no longer exists, or if it hasn't been touched for LOCK_STALE_S;
## then it is taken over.
func _take_lock() -> bool:
	var lock := path("world.lock")
	if FileAccess.file_exists(lock):
		var age := int(Time.get_unix_time_from_system()) - FileAccess.get_modified_time(lock)
		var pid := int(FileAccess.get_file_as_string(lock).strip_edges().trim_prefix("pid "))
		var gone := pid > 0 and (pid == OS.get_process_id() or not _process_exists(pid))
		if age < LOCK_STALE_S and not gone:
			error = "Another server is already running this world (%s, process %d, updated %d s ago). Stop it first." % [lock, pid, age]
			return false
		print("SERVER taking over the lock of a server that is gone (process %d, %d s old)" % [pid, age])
	_touch_lock()
	return true


## Is process `pid` running? Linux: /proc; Windows: tasklist. Elsewhere we can't tell (true).
static func _process_exists(pid: int) -> bool:
	match OS.get_name():
		"Linux":
			return DirAccess.dir_exists_absolute("/proc/%d" % pid)
		"Windows":
			var out := []
			if OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/NH", "/FO", "CSV"], out) != 0:
				return true
			return ("\"%d\"" % pid) in "".join(out)
	return true


func _touch_lock() -> void:
	var f := FileAccess.open(path("world.lock"), FileAccess.WRITE)
	if f != null:
		f.store_string("pid %d\n" % OS.get_process_id())
		f.close()


func release_lock() -> void:
	DirAccess.remove_absolute(path("world.lock"))


## A zip of the world folder in backups/. Keeps the newest BACKUPS_KEEP plus one per day for
## BACKUP_DAYS days.
func backup(why: String) -> String:
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "-").replace("T", "-")
	var zip_path := data_dir.path_join("backups").path_join("%s-%s.zip" % [world_name, stamp])
	var n := 2
	while FileAccess.file_exists(zip_path):  # two in the same second
		zip_path = data_dir.path_join("backups").path_join("%s-%s-%d.zip" % [world_name, stamp, n])
		n += 1
	var zp := ZIPPacker.new()
	if zp.open(zip_path + ".tmp") != OK:
		printerr("SERVER could not write backup %s" % zip_path)
		return ""
	for sub in ["", "players", "chunks"]:
		var d := path(sub) if sub != "" else world_dir
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".tmp") or f == "world.lock":
				continue
			zp.start_file(f if sub == "" else sub + "/" + f)
			zp.write_file(FileAccess.get_file_as_bytes(d.path_join(f)))
			zp.close_file()
	zp.close()
	DirAccess.rename_absolute(zip_path + ".tmp", zip_path)
	_last_backup_unix = int(Time.get_unix_time_from_system())
	print("SERVER backup (%s): %s" % [why, zip_path])
	_prune_backups()
	return zip_path


func _prune_backups() -> void:
	var dir := data_dir.path_join("backups")
	var mine := []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with(world_name + "-") and f.ends_with(".zip"):
			mine.append(f)
	mine.sort()
	mine.reverse()  # newest first (the names sort by date)
	var days_kept := {}
	var now := int(Time.get_unix_time_from_system())
	for i in mine.size():
		var f: String = mine[i]
		var t := FileAccess.get_modified_time(dir.path_join(f))
		var day_key := Time.get_date_string_from_unix_time(t)
		var keep := i < BACKUPS_KEEP
		if not keep and now - t < BACKUP_DAYS * 86400 and not days_kept.has(day_key):
			keep = true
		if keep:
			days_kept[day_key] = true
		else:
			DirAccess.remove_absolute(dir.path_join(f))


## Commands dropped in control/ (by dbctl): one command per .cmd file. Returns them in order.
func read_control() -> Array:
	var dir := data_dir.path_join("control")
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.ends_with(".cmd"))
	files.sort()
	var out := []
	for f in files:
		var full := dir.path_join(f)
		out.append(FileAccess.get_file_as_string(full).strip_edges())
		DirAccess.remove_absolute(full)
	return out


func write_status(info: Dictionary) -> void:
	info["world"] = world_name
	info["version"] = G.VERSION
	info["uptime_s"] = int(Time.get_unix_time_from_system()) - _started_unix
	info["last_save"] = Time.get_datetime_string_from_unix_time(last_save_unix) if last_save_unix > 0 else ""
	info["last_save_ok"] = last_save_ok
	info["warnings"] = warnings
	_write_files([[data_dir.path_join("status.json"), (JSON.stringify(info, "\t") + "\n").to_utf8_buffer()]])


## Timers: lock refresh, control commands and status. NetServer drives autosave itself.
func tick(delta: float) -> Dictionary:
	var due := {}
	_lock_t -= delta
	if _lock_t <= 0.0:
		_lock_t = 10.0
		_touch_lock()
	_control_t -= delta
	if _control_t <= 0.0:
		_control_t = 1.0
		due["control"] = read_control()
	_status_t -= delta
	if _status_t <= 0.0:
		_status_t = 60.0
		due["status"] = true
	_autosave_t -= delta
	if _autosave_t <= 0.0:
		_autosave_t = autosave_s
		due["autosave"] = true
	return due


func hours_since_backup() -> float:
	return (Time.get_unix_time_from_system() - _last_backup_unix) / 3600.0
