extends Node
## Keeps the game at the server's version, like an online game's launcher: when a server runs
## another version (NetClient sees it in the login challenge), the game downloads that version's
## Windows zip from the GitHub release `v<version>`, puts the new exe next to itself, and hands
## over to it. The new exe (started headless with --finish-update=OLD_EXE) waits for the old one
## to close, copies itself over it, and starts it again; that game then joins the same server by
## itself (user://update/rejoin.cfg). Nothing is ever written over a running program.
##
## Only exported Windows games update (in the editor, or on Linux, the server's refusal shows as
## before). Tests: --update-url=URL (instead of GitHub), --update-target=FILE (instead of our own
## exe), --update-dry-run (stop once the new exe is in place), --finish-no-launch.

const RELEASES := "https://github.com/MarcusD9722/DeadBlocks/releases/download/"
const REJOIN_CFG := "user://update/rejoin.cfg"
const MIN_EXE_BYTES := 1000000

## idle -> downloading -> (ready: dry run) | handing_over; failed on an error.
var state := "idle"
var version := ""
var _http: HTTPRequest = null
var _zip := ""
var _shown_pct := -1


## Updating is possible here (an exported Windows game, or a test pointing at its own files).
func can_update() -> bool:
	if G.arg_value("--update-url=") != "":
		return true
	return OS.has_feature("template") and OS.get_name() == "Windows" and not G.server_mode


## The program to replace: our own exe (tests: --update-target).
static func target_exe() -> String:
	var t := G.arg_value("--update-target=")
	return t if t != "" else OS.get_executable_path()


## Where the new exe goes before it takes over: "DeadBlocks-update.exe" next to the game.
static func helper_exe(target: String) -> String:
	var base := target.get_file().get_basename()
	return target.get_base_dir().path_join(base + "-update." + target.get_extension() if target.get_extension() != "" else base + "-update")


## Get version `v` (the server's), then restart into it and join `rejoin` ({host, port, name,
## pin_key, password_key}) again.
func update_to(v: String, rejoin: Dictionary) -> void:
	if state == "downloading" or state == "handing_over":
		return
	var re := RegEx.create_from_string("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$")
	if re.search(v) == null:
		_fail("The server runs version \"%s\", which can't be downloaded automatically." % v)
		return
	version = v
	state = "downloading"
	_shown_pct = -1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://update"))
	_save_rejoin(rejoin)
	var base := G.arg_value("--update-url=")
	if base == "":
		base = RELEASES
	var url := "%sv%s/DeadBlocks-%s-windows.zip" % [base, v, v]
	_zip = ProjectSettings.globalize_path("user://update/DeadBlocks-%s-windows.zip" % v)
	if _http == null:
		_http = HTTPRequest.new()
		_http.use_threads = true
		_http.timeout = 900.0
		add_child(_http)
		_http.request_completed.connect(_on_downloaded)
	_http.download_file = _zip
	print("UPDATE the server runs %s (we have %s): downloading %s" % [v, G.VERSION, url])
	_say("The server runs Dead Blocks %s. Updating your game..." % v, false)
	var err := _http.request(url)
	if err != OK:
		_fail("Couldn't start the download (error %d)." % err)


func _process(_delta: float) -> void:
	if state != "downloading" or _http == null:
		return
	var total := _http.get_body_size()
	if total <= 0:
		return
	var pct := int(100.0 * _http.get_downloaded_bytes() / total)
	if pct >= _shown_pct + 5 or (pct == 100 and _shown_pct != 100):
		_shown_pct = pct
		_say("Updating to Dead Blocks %s...  %d%% of %d MB" % [version, pct, int(total / 1048576.0)], false)


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		var why := "nothing reached us (result %d)" % result if result != HTTPRequest.RESULT_SUCCESS else "the answer was %d" % code
		_fail("Couldn't download Dead Blocks %s (%s). Is there a GitHub release v%s with DeadBlocks-%s-windows.zip?" % [version, why, version, version])
		return
	_install()


## Unpack the exe from the zip, next to the game, and hand over to it.
func _install() -> void:
	var z := ZIPReader.new()
	if z.open(_zip) != OK:
		_fail("The download is damaged. Try again.")
		return
	var exe_name := ""
	for f in z.get_files():
		if f.to_lower().ends_with(".exe"):
			exe_name = f
	var data := z.read_file(exe_name) if exe_name != "" else PackedByteArray()
	z.close()
	DirAccess.remove_absolute(_zip)
	if data.size() < MIN_EXE_BYTES:
		_fail("The download has no game in it. Try again.")
		return
	var target := target_exe()
	var helper := helper_exe(target)
	var f := FileAccess.open(helper, FileAccess.WRITE)
	if f == null:
		_fail("Couldn't write next to the game (%s): is that folder read-only? Move the game folder to Documents and try again." % target.get_base_dir())
		return
	f.store_buffer(data)
	f.close()
	print("UPDATE %s is in place: %s (%d bytes)" % [version, helper, data.size()])
	if G.has_arg("--update-dry-run"):
		state = "ready"
		print("UPDATE ready %s" % helper)
		return
	# Does it start, and is it the version we want? (A program that prints nothing here, say
	# because Windows gave it no output, is trusted: it came from the release over HTTPS.)
	var out := []
	OS.execute(helper, ["--headless", "--", "--version"], out, true)
	var said := "".join(out)
	if said.contains("Dead Blocks ") and not said.contains("Dead Blocks " + version):
		DirAccess.remove_absolute(helper)
		_fail("The download isn't Dead Blocks %s (%s)." % [version, said.strip_edges()])
		return
	state = "handing_over"
	_say("Restarting into Dead Blocks %s..." % version, false)
	var pid := OS.create_process(helper, ["--headless", "--", "--finish-update=" + target])
	if pid <= 0:
		_fail("Couldn't start the new version (%s)." % helper)
		return
	G.net.leave()
	get_tree().quit()


func _save_rejoin(r: Dictionary) -> void:
	var cfg := ConfigFile.new()
	if not r.is_empty():
		cfg.set_value("rejoin", "host", r["host"])
		cfg.set_value("rejoin", "port", r["port"])
		cfg.set_value("rejoin", "name", r["name"])
		cfg.set_value("rejoin", "pin_key", Marshalls.raw_to_base64(r["pin_key"]))
		cfg.set_value("rejoin", "password_key", Marshalls.raw_to_base64(r["password_key"]))
	cfg.set_value("rejoin", "version", version)
	cfg.save(REJOIN_CFG)


func _fail(text: String) -> void:
	state = "failed"
	print("UPDATE failed: " + text)
	_say(text + " You can also download it from github.com/MarcusD9722/DeadBlocks/releases", true)


## Shown where the connection's messages go (the title screen's status line).
func _say(text: String, is_error: bool) -> void:
	if G.net != null:
		G.net.status.emit(text, is_error)


## The headless helper step (the new exe, started with --finish-update=OLD): wait until the old
## game has closed (its exe can be written again), copy ourselves over it, start it, and quit.
## If that can't be done, start ourselves as the game instead: the player gets the new version
## either way (from DeadBlocks-update.exe until the next update).
static func finish(target: String, launch: bool) -> void:
	var me := OS.get_executable_path()
	var data := FileAccess.get_file_as_bytes(me)
	var t0 := Time.get_ticks_msec()
	var f: FileAccess = null
	while data.size() >= MIN_EXE_BYTES and Time.get_ticks_msec() - t0 < 30000:
		f = FileAccess.open(target, FileAccess.WRITE)
		if f != null:
			break
		OS.delay_msec(250)
	var start := target
	if f == null:
		printerr("UPDATE could not replace %s: starting the new version from %s" % [target, me])
		start = me
	else:
		f.store_buffer(data)
		f.close()
		print("UPDATE copied the new version over %s" % target)
	if launch:
		OS.create_process(start, ["--", "--after-update"])


## The first start after an update: remove the helper (it may still be closing).
func cleanup_after_update() -> void:
	var helper := helper_exe(target_exe())
	for attempt in 40:
		if not FileAccess.file_exists(helper) or DirAccess.remove_absolute(helper) == OK:
			return
		await get_tree().create_timer(0.5).timeout
