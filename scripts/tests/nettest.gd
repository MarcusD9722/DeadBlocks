extends Node
## Network test client, started by tools/run_nettest.sh next to a real server:
## `-- --connect=127.0.0.1:PORT --name=N --pin=P --password=S --nettest=ROLE [--radius=3]`
## Prints NETTEST PASS/FAIL lines and ends with `NETTEST DONE fails=N`.
## Roles:
##   a, b         two players: walk, chat, check where they see each other, try an admin command,
##                get a 30 m cheat jump corrected. "a" must be an admin. "a" leaves first and "b"
##                checks that it saw the leave.
##   join         join and stay a few seconds; with --nettest-expect=x,y,z also check the start
##                position (where this name last left the server)
##   hold         join and stay online until killed (crash and full-server tests)
##   reject:TEXT  expect the server to refuse the login with a reason containing TEXT
##   screens      no --connect: screenshot the title, Join and Host screens (with --shots=DIR)
##   host         no --connect: press "Host game" (port from --nettest-port=), check we're in
##                and the admin, then quit; the script checks the background server stopped too.
##                With --nettest-crash, stay until killed (the server must then stop by itself).
##   stall        join while the script freezes the server: for 8 s (must stay connected), or
##                with --nettest-stall=long for 40 s (must drop, show the reconnecting screen and
##                get back in by itself)

var role := ""
var fails := 0
var _errors: Array = []      # error statuses from NetClient
var _chats: Array = []       # [from, text]
var _notices: Array = []
var _done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	role = G.arg_value("--nettest=")
	G.net.status.connect(_on_status)
	G.net.chat.connect(func(from: String, text: String): _chats.append([from, text]))
	G.net.notice.connect(_on_notice)
	var limit := 150.0 if role == "hold" or G.has_arg("--nettest-crash") else 90.0
	if role == "stall":
		limit = 240.0
	get_tree().create_timer(limit, true, false, true).timeout.connect(_on_timeout)
	_run.call_deferred()


func _on_status(text: String, is_error: bool) -> void:
	print("NETTEST status: ", text)
	if is_error:
		_errors.append(text)


func _on_notice(text: String, _col: Color) -> void:
	print("NETTEST notice: ", text)
	_notices.append(text)


func check(cond: bool, what: String) -> void:
	if cond:
		print("NETTEST PASS ", what)
	else:
		fails += 1
		print("NETTEST FAIL ", what)


## With --shots=DIR and a real display: save a screenshot.
func _shot(shot_name: String) -> void:
	var dir := G.arg_value("--shots=")
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [dir, role, shot_name])
	print("SHOT ", shot_name)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


## Waits until cond() is true; false if it took longer than timeout seconds.
func _until(cond: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > timeout * 1000.0:
			return false
		await _wait(0.1)
	return true


func _playing() -> bool:
	var g = G.game
	return G.net.is_online() and g != null and is_instance_valid(g) and g.state == "playing" \
		and G.player != null and is_instance_valid(G.player)


func _other_id() -> int:
	for id in G.net.others:
		return id
	return 0


## Text of the first chat message from `from` starting with `prefix` ("" if none yet).
func _chat_from(from: String, prefix: String) -> String:
	for c in _chats:
		if c[0] == from and String(c[1]).begins_with(prefix):
			return c[1]
	return ""


func _has_notice(part: String) -> bool:
	for n in _notices:
		if part in n:
			return true
	return false


static func _vec(s: String) -> Vector3:
	var p := s.replace(",", " ").split(" ", false)
	if p.size() < 3:
		return Vector3.INF
	return Vector3(float(p[p.size() - 3]), float(p[p.size() - 2]), float(p[p.size() - 1]))


func _run() -> void:
	print("NETTEST role=%s name=%s" % [role, G.arg_value("--name=")])
	if role.begins_with("reject:"):
		await _run_reject(role.substr(7))
	elif role == "a" or role == "b":
		await _run_pair()
	elif role == "join":
		await _run_join()
	elif role == "hold":
		await _run_hold()
	elif role == "screens":
		await _run_screens()
	elif role == "host":
		await _run_host()
	elif role == "stall":
		await _run_stall()
	else:
		check(false, "known role (got '%s')" % role)
	await _finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	print("NETTEST DONE fails=%d" % fails)
	G.net.leave()
	await _wait(0.3)
	get_tree().quit(0 if fails == 0 else 1)


func _on_timeout() -> void:
	if _done:
		return
	check(false, "finished in time (role %s)" % role)
	_finish()


func _run_reject(text: String) -> void:
	var answered := await _until(func(): return not _errors.is_empty() or _playing(), 30.0)
	var got := ", ".join(_errors) if not _errors.is_empty() else ("joined" if _playing() else "no answer")
	check(answered and not _playing() and text in got, "login refused with '%s' (got: %s)" % [text, got])


func _run_join() -> void:
	if not await _until(_playing, 60.0):
		check(false, "joined the server (%s)" % ", ".join(_errors))
		return
	check(true, "joined the server")
	var e := _vec(G.arg_value("--nettest-expect="))
	if e != Vector3.INF:
		var got: Vector3 = G.session["pos"]
		check(got.distance_to(e) < 1.0, "starts where it left (off by %.2f m)" % got.distance_to(e))
	await _wait(4.0)


func _run_hold() -> void:
	if not await _until(_playing, 60.0):
		check(false, "joined the server (%s)" % ", ".join(_errors))
		return
	print("NETTEST online")
	await _wait(140.0)
	check(false, "was stopped by the test script")


func _run_pair() -> void:
	var me := G.arg_value("--name=")
	if not await _until(_playing, 60.0):
		check(false, "joined the server and loaded the world (%s)" % ", ".join(_errors))
		return
	check(true, "joined the server and loaded the world")
	check(G.net.my_net_id > 0, "got a net id")
	check(G.net.is_admin == (role == "a"), "admin flag is right")
	if not await _until(func(): return _other_id() != 0 and not G.net.others[_other_id()]["samples"].is_empty(), 30.0):
		check(false, "sees the other player")
		return
	var oid := _other_id()
	var other: String = G.net.others[oid]["name"]
	check(true, "sees the other player (%s)" % other)

	# Walk (hopping over anything in the way), stop, and tell the other player where we ended up.
	var p = G.player
	var start: Vector3 = p.global_position
	var yaw := 0.0 if role == "a" else PI * 0.5
	for attempt in 4:
		# Blocked by a tree or a cliff? Turn and try another way.
		p.set_look(yaw + attempt * PI * 0.5, 0.0)
		Input.action_press("move_forward")
		Input.action_press("jump")
		await _wait(2.0)
		Input.action_release("move_forward")
		Input.action_release("jump")
		if Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length() > 4.0:
			break
	await _wait(1.5)
	var mine: Vector3 = p.global_position
	check(Vector2(mine.x - start.x, mine.z - start.z).length() > 2.0, "walked (%.1f m)" % start.distance_to(mine))
	G.net.send_chat("NT pos %.3f %.3f %.3f" % [mine.x, mine.y, mine.z])

	# Where does the other player say they are, and is that where we draw them?
	check(await _until(func(): return _chat_from(other, "NT pos ") != "", 20.0), "chat from %s arrived" % other)
	check(await _until(func(): return _chat_from(me, "NT pos ") != "", 5.0), "own chat came back from the server")
	await _wait(0.6)
	var theirs := _vec(_chat_from(other, "NT pos "))
	var seen: Dictionary = G.net.interpolated(oid)
	var off := 99.0 if seen.is_empty() or theirs == Vector3.INF else (seen["pos"] as Vector3).distance_to(theirs)
	check(off < 0.75, "sees %s where they are (off by %.2f m)" % [other, off])
	var rp = G.game.remote_players.get(oid)
	var drawn := 99.0 if rp == null or theirs == Vector3.INF else (rp.global_position as Vector3).distance_to(theirs)
	check(drawn < 0.75, "draws %s there (off by %.2f m)" % [other, drawn])
	if G.arg_value("--shots=") != "" and rp != null:
		p.look_at_mob(rp)
		await _wait(0.5)
		await _shot("1_other_player")
		G.game.open_chat()
		await _wait(0.2)
		await _shot("2_chat")
		G.hud._close_chat()
		G.game.pause()
		await _wait(1.2)
		await _shot("3_pause")
		G.game.resume()

	# Admin commands: "a" skips to dusk for everyone; "b" may not.
	if role == "a":
		G.net.send_chat("/dusk")
		check(await _until(func(): return _has_notice("Done: /dusk"), 10.0), "admin command /dusk accepted")
		G.net.send_chat("NT dusk")
	else:
		G.net.send_chat("/dusk")
		check(await _until(func(): return _has_notice("Only admins"), 10.0), "non-admin /dusk refused")
		var got_dusk := await _until(func(): return _chat_from(other, "NT dusk") != "", 20.0)
		var t: float = G.game.time
		check(got_dusk and t >= 19.9 and t < 20.5, "the admin's /dusk reached this player (time %.2f)" % t)

	# Cheat: jump 30 m sideways. The server refuses the move and puts us back.
	var before: Vector3 = p.global_position
	var mid0: int = G.net.move_id
	p.global_position = before + Vector3(30, 0, 0)
	check(await _until(func(): return G.net.move_id != mid0, 5.0), "server corrected a 30 m jump")
	await _wait(0.3)
	check(p.global_position.distance_to(before) < 1.5, "back in place after the correction (off by %.2f m)" % p.global_position.distance_to(before))
	await _wait(1.0)

	G.net.send_chat("NT checked")
	check(await _until(func(): return _chat_from(other, "NT checked") != "", 30.0), "%s finished its checks" % other)
	var fin: Vector3 = p.global_position
	print("NETTEST final_pos=%.3f,%.3f,%.3f" % [fin.x, fin.y, fin.z])
	if role == "b":
		check(await _until(func(): return not G.net.others.has(oid), 20.0), "%s left the list after quitting" % other)
		check(await _until(func(): return _has_notice("%s left the game." % other), 5.0), "got the leave notice")
	else:
		await _wait(0.5)


func _run_screens() -> void:
	check(await _until(func(): return G.game != null and G.game.state == "title", 120.0), "reached the title screen")
	var h = G.hud
	await _wait(0.5)
	await _shot("1_title")
	h._show_panel(h.join_panel)
	h.f_addr.text = "203.0.113.7"
	h.f_name.text = "Marcus"
	await _wait(0.3)
	await _shot("2_join")
	h._set_status("Wrong PIN for Marcus. (Forgot it? Ask the server owner to reset it.)", true)
	await _wait(0.3)
	await _shot("3_join_error")
	h._show_panel(h.host_panel)
	await _wait(0.3)
	await _shot("4_host")


func _run_host() -> void:
	check(await _until(func(): return G.game != null and G.game.state == "title", 120.0), "reached the title screen")
	var err: String = await G.host_game("hoster", "4321", "pw", int(G.arg_value("--nettest-port=")))
	check(err == "" and G.host_pid > 0, "started the server process (%s)" % err)
	print("NETTEST host_pid=%d" % G.host_pid)
	if not await _until(_playing, 60.0):
		check(false, "joined the hosted game (%s)" % ", ".join(_errors))
		return
	check(true, "joined the hosted game")
	check(G.net.is_admin, "the host is an admin")
	if G.has_arg("--nettest-crash"):
		print("NETTEST online")  # the script kills this game now
		await _wait(140.0)
		check(false, "was stopped by the test script")
	await _wait(1.0)


func _run_stall() -> void:
	if not await _until(_playing, 60.0):
		check(false, "joined the server (%s)" % ", ".join(_errors))
		return
	var game_id: int = G.game.get_instance_id()
	print("NETTEST online")
	if G.arg_value("--nettest-stall=") != "long":
		# The script freezes the server for 8 s.
		check(await _until(func(): return G.net.quiet_s() > 5.0, 60.0), "noticed the server went quiet")
		var back := await _until(func(): return G.net.reconnecting or (G.net.is_online() and G.net.quiet_s() < 0.5), 30.0)
		check(back and not G.net.reconnecting, "rode out an 8 s server freeze without dropping")
		return
	# The script freezes the server for 40 s.
	if await _until(func(): return G.net.quiet_s() > 3.0, 30.0):
		await _shot("quiet")
	check(await _until(func(): return G.net.reconnecting, 60.0), "noticed the connection dropped")
	check(G.game.state == "reconnecting", "shows the reconnecting screen")
	await _shot("reconnecting")
	check(await _until(func(): return not G.net.reconnecting and _playing(), 90.0), "reconnected by itself")
	check(is_instance_valid(G.game) and G.game.get_instance_id() == game_id, "kept the same world (no reload)")
	await _wait(2.0)
	check(G.net.quiet_s() < 1.0, "server messages flowing again")
