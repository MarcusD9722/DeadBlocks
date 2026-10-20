extends RefCounted
## `-- --savetest`: the save files without a running server. A save/load round trip gives back
## the same chunks, players, backpacks, seed and clock; a damaged chunk or player file is set aside and the
## rest loads; a damaged world.json, a newer format and other terrain are refused; the lock keeps
## a second server out but a dead server's lock is taken over; leftover .tmp files are removed;
## backups hold the world and are pruned; control files are read in order.
## Prints SAVETEST PASS/FAIL lines and ends with `SAVETEST DONE fails=N`.

const SaveScript := preload("res://scripts/server/save.gd")

static var fails := 0


static func check(ok: bool, what: String) -> void:
	print("SAVETEST %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1


static func run() -> void:
	var dir := ProjectSettings.globalize_path("user://savetest")
	OS.execute("rm", ["-rf", dir])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	# A new world, and the lock.
	var s := _open(dir, 1234)
	check(s.error == "" and s.is_new and s.seed_v == 1234 and s.day == 1, "a new world starts on day 1 with the given seed")
	# Another live server (pid 1 always exists) holds the lock.
	var lock := dir.path_join("worlds/main/world.lock")
	_write(lock, "pid 1\n".to_utf8_buffer())
	var other := _open(dir, 1)
	check("Another server is already running this world" in other.error, "a second server is refused (%s)" % other.error)
	check(FileAccess.get_file_as_string(lock) == "pid 1\n", "and leaves the other server's lock alone")
	other.free()
	s._touch_lock()

	# Round trip.
	var chunks := []
	for k in [Vector2i(-3, 7), Vector2i(12, -1), Vector2i(0, 0)]:
		var d := PackedByteArray()
		d.resize(16384)
		for i in d.size():
			d[i] = rng.randi_range(0, 3) if i % 64 < 30 else 0  # stone-ish below, air above
		chunks.append([k, d])
	var bob := _account("Bob", rng)
	var reset := _account("Ann", rng)
	reset["pin_key"] = PackedByteArray()  # after `dbctl reset-pin`
	var packs := [{"pos": [5, 20, -7], "owner": "Bob", "left": 412.5, "inv": [[7, 5], null, [110, 1]]}]
	check(s.save_now(3, 19.5, chunks, {"bob": bob, "ann": reset}, {"backpacks": packs}), "save_now wrote the world")
	s.release_lock()
	s.free()

	s = _open(dir, 999)
	check(s.error == "" and not s.is_new and s.seed_v == 1234 and s.day == 3 and is_equal_approx(s.time, 19.5),
		"reload: seed 1234 (not 999), day 3, 19:30 (%d, %d, %.2f)" % [s.seed_v, s.day, s.time])
	var got := {}
	for c in s.load_chunks():
		got[c[0]] = c[1]
	var same := got.size() == chunks.size()
	for c in chunks:
		same = same and got.get(c[0], PackedByteArray()) == c[1]
	check(same, "the 3 chunks came back identical (%d loaded)" % got.size())
	var players := s.load_players()
	check(players.has("bob") and _same_account(players["bob"], bob), "Bob came back identical")
	check(players.has("ann") and players["ann"]["pin_key"].is_empty(), "a reset PIN stays reset")
	var bp: Dictionary = s.backpacks[0] if s.backpacks.size() == 1 else {}
	var bp_inv: Array = bp.get("inv", [])
	check(bp.get("owner") == "Bob" and bp.get("pos", []).map(func(v): return int(v)) == [5, 20, -7] and is_equal_approx(float(bp.get("left", 0)), 412.5)
		and bp_inv.size() == 3 and int(bp_inv[0][0]) == 7 and int(bp_inv[0][1]) == 5 and bp_inv[1] == null and int(bp_inv[2][0]) == 110,
		"the backpacks came back identical (%s)" % str(s.backpacks))

	# Background save, then damage: a flipped byte in a chunk, a cut player file.
	chunks[0][1][100] = 9
	check(s.save_async(3, 20.0, [chunks[0]], {"bob": bob}), "save_async started")
	var t0 := Time.get_ticks_msec()
	while s.busy() and Time.get_ticks_msec() - t0 < 10000:
		s.poll()
		OS.delay_msec(5)
	check(not s.busy() and s.last_save_ok, "save_async finished")
	var cfile := s.path("chunks").path_join(SaveScript.chunk_file_name(Vector2i(12, -1)))
	var raw := FileAccess.get_file_as_bytes(cfile)
	raw[raw.size() / 2] ^= 0x10
	_write(cfile, raw)
	var pfile := s.player_file("bob")
	raw = FileAccess.get_file_as_bytes(pfile)
	_write(pfile, raw.slice(0, raw.size() - 20))
	_write(s.path("chunks").path_join("5_5.bin.tmp"), PackedByteArray([1, 2, 3]))
	# A crash on Windows between removing the old file and renaming the new one into place.
	var afile := s.player_file("ann")
	DirAccess.rename_absolute(afile, afile + ".tmp")
	s.release_lock()
	s.free()

	s = _open(dir, 1)
	got.clear()
	for c in s.load_chunks():
		got[c[0]] = c[1]
	check(got.size() == 2 and not got.has(Vector2i(12, -1)) and got.get(Vector2i(-3, 7)) == chunks[0][1],
		"a flipped byte: that chunk is set aside, the others load (with the background save's edit)")
	players = s.load_players()
	check(not players.has("bob") and players.has("ann"), "a cut player file is set aside, the others load")
	check(FileAccess.file_exists(afile) and not FileAccess.file_exists(afile + ".tmp"), "a checked .tmp without its real file is recovered")
	var damaged := DirAccess.get_files_at(s.path("damaged"))
	check(damaged.size() == 2 and s.warnings.size() == 2, "both damaged files are in damaged/ and reported (%s)" % ", ".join(damaged))
	check(not FileAccess.file_exists(s.path("chunks").path_join("5_5.bin.tmp")), "a leftover .tmp file is removed")

	# Backups hold the world.
	var zip := s.backup("test")
	var zr := ZIPReader.new()
	var files := PackedStringArray()
	if zip != "" and zr.open(zip) == OK:
		files = zr.get_files()
		zr.close()
	check("world.json" in files and "chunks/-3_7.bin" in files and not "world.lock" in files,
		"a backup holds world.json and the chunks, not the lock (%s)" % ", ".join(files))
	var zip2 := s.backup("test")
	check(zip2 != "" and zip2 != zip and FileAccess.file_exists(zip), "a second backup in the same second keeps the first")
	s.release_lock()
	s.free()

	# World files the server must refuse.
	var meta_file := dir.path_join("worlds/main/world.json")
	var good := FileAccess.get_file_as_bytes(meta_file)
	var bad := good.duplicate()
	bad[10] ^= 0x01
	_write(meta_file, bad)
	s = _open(dir, 1)
	check("world.json is damaged" in s.error, "a damaged world.json is refused (%s)" % s.error)
	s.free()
	var text := good.get_string_from_utf8()
	var meta: Dictionary = JSON.parse_string(text.substr(0, text.rfind("\n#sha256 ")))
	var newer: Dictionary = meta.duplicate()
	newer["format"] = SaveScript.FORMAT + 1
	newer["game"] = "9.9.9"
	_write(meta_file, SaveScript._json_bytes(newer))
	s = _open(dir, 1)
	check("saved by a newer version of Dead Blocks (9.9.9)" in s.error, "a newer save format is refused (%s)" % s.error)
	s.free()
	var terrain: Dictionary = meta.duplicate()
	terrain["worldgen"] = WorldGen.VERSION + 1
	_write(meta_file, SaveScript._json_bytes(terrain))
	s = _open(dir, 1)
	check("terrain version" in s.error, "other terrain is refused (%s)" % s.error)
	s.free()
	_write(meta_file, good)

	# A lock left by a server that is gone is taken over, and so is one with our own process id
	# (a restart after a power cut can get the same id).
	_write(lock, "pid 999999\n".to_utf8_buffer())
	s = _open(dir, 1)
	check(s.error == "", "the lock of a server that is gone is taken over (%s)" % s.error)
	s.free()
	s = _open(dir, 1)
	check(s.error == "", "a lock with our own process id is taken over (%s)" % s.error)
	_write(lock, "pid 1\n".to_utf8_buffer())
	other = _open(dir, 1)
	check("Another server" in other.error, "a live lock is not (%s)" % other.error)
	other.free()
	s._touch_lock()
	_write(dir.path_join("control/x.cmd"), "stop".to_utf8_buffer())
	other = _open(dir, 1)
	check(other.error == "" and not FileAccess.file_exists(dir.path_join("control/x.cmd")), "a control command from before the start is ignored")
	other.free()

	# Control files, in order, each read once.
	_write(dir.path_join("control/b.cmd"), "kick bob\n".to_utf8_buffer())
	_write(dir.path_join("control/a.cmd"), "save".to_utf8_buffer())
	var cmds := s.read_control()
	check(cmds == ["save", "kick bob"] and s.read_control().is_empty(), "control commands read in order, once (%s)" % str(cmds))
	s.release_lock()
	s.free()

	# Pruning: the newest 20, plus one a day for 14 days.
	var p := SaveScript.new()
	p.data_dir = dir
	p.world_name = "p"
	var bdir := dir.path_join("backups")
	var now := int(Time.get_unix_time_from_system())
	var made := []
	for i in 22:  # today, a minute apart
		made.append(now - 3600 - i * 60)
	for d in [2, 3, 5]:  # one on each of three earlier days
		made.append(now - d * 86400)
	for d in [30, 31]:  # too old
		made.append(now - d * 86400)
	for t in made:
		var name := "p-%s.zip" % Time.get_datetime_string_from_unix_time(t, true).replace(":", "").replace(" ", "-")
		_write(bdir.path_join(name), PackedByteArray([0]))
		OS.execute("touch", ["-d", "@%d" % t, bdir.path_join(name)])
	p._prune_backups()
	var left := Array(DirAccess.get_files_at(bdir)).filter(func(f): return f.begins_with("p-"))
	check(left.size() == 23, "pruning keeps the newest 20 and one a day for 14 days (%d of 27 left)" % left.size())
	p.free()

	OS.execute("rm", ["-rf", dir])
	print("SAVETEST DONE fails=%d" % fails)


static func _open(dir: String, seed_v: int) -> SaveScript:
	var s := SaveScript.new()
	s.open(dir, "main", seed_v)
	return s


static func _account(name: String, rng: RandomNumberGenerator) -> Dictionary:
	var pin := PackedByteArray()
	for i in 32:
		pin.append(rng.randi_range(0, 255))
	var inv := Inventory.new()
	inv.slots[0] = {"id": Blocks.DIRT, "n": 37}
	inv.slots[4] = {"id": Items.STONE_PICK, "n": 1}
	inv.slots[35] = {"id": Blocks.TORCH, "n": 5}
	return {"name": name, "pin_key": pin, "fails": 0, "locked_until": 0.0,
		"pos": Vector3(-120.25, 33.0, 4096.5), "yaw": 1.25, "health": 61.5, "food": 12.25, "kills": 9,
		"bed": Vector3i(3, 31, -2), "play_s": 5400.0, "inv": inv}


static func _same_account(a: Dictionary, b: Dictionary) -> bool:
	for key in ["name", "pin_key", "yaw", "health", "food", "kills", "play_s"]:
		if a[key] != b[key]:
			print("SAVETEST   %s differs: %s vs %s" % [key, a[key], b[key]])
			return false
	if not (a["pos"] as Vector3).is_equal_approx(b["pos"]) or a["bed"] != b["bed"]:
		return false
	return a["inv"].slots == b["inv"].slots


static func _write(file: String, data: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	var f := FileAccess.open(file, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()
