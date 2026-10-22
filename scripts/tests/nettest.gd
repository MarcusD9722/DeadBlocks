extends Node
## Network test client, started by tools/run_nettest.sh next to a real server:
## `-- --connect=127.0.0.1:PORT --name=N --pin=P --password=S --nettest=ROLE [--radius=3]`
## Prints NETTEST PASS/FAIL lines and ends with `NETTEST DONE fails=N`.
## Roles:
##   a, b         two players: walk, chat, check where they see each other and what they hold, try
##                an admin command, get a 30 m cheat jump corrected; "a" dies and "b" picks up its
##                backpack, and a second one falls apart (server --backpack-s=30). "a" must be an
##                admin. "a" leaves first and "b" checks that it saw the leave.
##   join         join and stay a few seconds; with --nettest-expect=x,y,z also check the start
##                position (where this name last left the server)
##   hold         join and stay online until killed (crash and full-server tests)
##   reject:TEXT  expect the server to refuse the login with a reason containing TEXT
##   screens      no --connect: screenshot the title, Join, Host and Play solo screens (with --shots=DIR)
##   host         no --connect: press "Host game" (port from --nettest-port=), check we're in
##                and the admin, then quit; the script checks the background server stopped too.
##                With --nettest-crash, stay until killed (the server must then stop by itself).
##   stall        join while the script freezes the server: for 8 s (must stay connected), or
##                with --nettest-stall=long for 40 s (must drop, show the reconnecting screen and
##                get back in by itself)
##   builder      (admin) /give, mine, build a pillar, craft at a workbench it places, eat, move an
##                item, then race "watcher" to break the same block. Prints built_chunk=cx,cz
##   watcher      checks it sees the builder's blocks exactly as the server has them, and races
##   late         joins later: the edited chunks must arrive (--nettest-expect=cx,cz)
##   soak         (admin) 3 of these place and break blocks in one shared spot, 5 times a second
##                for --nettest-soak=S seconds; afterwards every world must match the server's
##   fighter      (admin) spawns a zombie, gets hit, kills it; falls; walls itself in with dirt,
##                spawns a horde, sees the wall crack, dies and respawns
##   zwatch       walks away from the fighter and checks it sees the same zombie come and go
##   horde        (admin) 3 of these live through a Blood Moon for --nettest-soak=S seconds:
##                fight, die, respawn; report zombies seen and the bandwidth they cost
##   saver        (admin) builds a pillar, gets a pickaxe, then prints NETTEST saved ... with
##                what a restarted server must give back (join checks it: --nettest-expect,
##                --nettest-has, --nettest-count=ID:N, --nettest-hash=CX,CZ,HASH; --nettest-dead:
##                the character died while it was away, so it comes back on the death screen with
##                a backpack)
##   updater      with --fake-version, --update-url (a local stand-in for GitHub releases),
##                --update-target and --update-dry-run: the server runs another version, so the
##                game downloads that one and puts it next to the old one instead of being refused
##   linger       (admin) gets some planks, then waits for the script to kill it, like a crash
##                (its character stays: M2); with --nettest-zombies it first sets 4 hunting
##                zombies on itself
##   lwatch       watches alice: after her game crashes her character stays, marked away; when
##                she comes back and leaves through the menu it goes at once; after another
##                crash with zombies about, they kill the character
##   crasher      (admin) keeps building and breaking while the script kills and restarts the
##                server (--nettest-crashes=N times, at most --nettest-soak=S seconds; prints
##                NETTEST crasher online N each time it is back); then its world must match
##                the server's

var role := ""
## Printed in front of every result line (autotest.gd, built on this, prints AUTOTEST).
var tag := "NETTEST"
var fails := 0
var _errors: Array = []      # error statuses from NetClient
var _chats: Array = []       # [from, text]
var _notices: Array = []
var _done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if role == "":
		role = G.arg_value("--nettest=")
	G.net.status.connect(_on_status)
	G.net.chat.connect(func(from: String, text: String): _chats.append([from, text]))
	G.net.notice.connect(_on_notice)
	var limit := 150.0 if role == "hold" or G.has_arg("--nettest-crash") else 90.0
	if role == "a" or role == "b":
		limit = 200.0
	if role == "stall":
		limit = 240.0
	elif role == "soak" or role == "horde" or role == "crasher":
		limit = 120.0 + float(G.arg_value("--nettest-soak="))
	elif role == "fighter" or role == "zwatch":
		limit = 360.0
	elif role == "lwatch":
		limit = 300.0
	elif role == "autotest":
		limit = 600.0
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
		print("%s PASS %s" % [tag, what])
	else:
		fails += 1
		print("%s FAIL %s" % [tag, what])


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
	elif role == "builder":
		await _run_builder()
	elif role == "watcher":
		await _run_watcher()
	elif role == "late":
		await _run_late()
	elif role == "soak":
		await _run_soak()
	elif role == "fighter":
		await _run_fighter()
	elif role == "zwatch":
		await _run_zwatch()
	elif role == "horde":
		await _run_horde()
	elif role == "saver":
		await _run_saver()
	elif role == "crasher":
		await _run_crasher()
	elif role == "linger":
		await _run_linger()
	elif role == "updater":
		await _run_updater()
	elif role == "lwatch":
		await _run_lwatch()
	else:
		check(false, "known role (got '%s')" % role)
	await _finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	print("%s DONE fails=%d" % [tag, fails])
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
	if G.has_arg("--nettest-dead"):
		var dead := func(): return G.net.is_online() and G.game != null and is_instance_valid(G.game) and G.game.state == "dead"
		check(await _until(dead, 60.0), "comes back on the death screen (its character died while it was away)")
		check(await _until(func(): return G.net.my_backpacks.size() == 1, 5.0), "with a backpack where it died")
		await _wait(2.0)
		return
	if not await _until(_playing, 60.0):
		check(false, "joined the server (%s)" % ", ".join(_errors))
		return
	check(true, "joined the server")
	var e := _vec(G.arg_value("--nettest-expect="))
	if e != Vector3.INF:
		var got: Vector3 = G.session["pos"]
		check(got.distance_to(e) < 1.0, "starts where it left (off by %.2f m)" % got.distance_to(e))
	if G.arg_value("--nettest-has=") != "":
		var id := int(G.arg_value("--nettest-has="))
		check(await _until(func(): return _count(id) >= 1, 10.0), "kept its %s after leaving" % Items.name_of(id))
	if G.arg_value("--nettest-count=") != "":
		var ic := G.arg_value("--nettest-count=").split(":")
		check(await _until(func(): return _count(int(ic[0])) == int(ic[1]), 10.0), "has exactly %s %s (has %d)" % [ic[1], Items.name_of(int(ic[0])), _count(int(ic[0]))])
	if G.arg_value("--nettest-hash=") != "":
		var hp := G.arg_value("--nettest-hash=").split(",")
		var c := Vector2i(int(hp[0]), int(hp[1]))
		await _hash_check("the blocks are as they were saved", c)
		var mine: String = G.world.region_hash(c.x, c.y, 1)
		check(mine == hp[2], "the same blocks as before the restart (%s, then %s)" % [mine, hp[2]])
	await _wait(4.0)


func _run_updater() -> void:
	var up = G.updater
	check(await _until(func(): return up.state in ["ready", "failed"], 60.0), "the update finished (%s)" % up.state)
	check(up.state == "ready" and up.version == G.VERSION, "got the version the server runs (%s)" % up.version)
	var want := FileAccess.get_file_as_bytes(G.arg_value("--update-expect="))
	var got := FileAccess.get_file_as_bytes(G.UpdaterScript.helper_exe(G.UpdaterScript.target_exe()))
	check(want.size() > 0 and got == want, "the new program is in place next to the old one (%d bytes)" % got.size())
	var cfg := ConfigFile.new()
	check(cfg.load(G.UpdaterScript.REJOIN_CFG) == OK and cfg.get_value("rejoin", "host", "") == "127.0.0.1"
		and cfg.get_value("rejoin", "name", "") == G.arg_value("--name="), "it remembers which server to join again")
	check(_errors.is_empty() and not G.net.is_online(), "no refusal, and it didn't join with the old version (%s)" % ", ".join(_errors))


func _run_linger() -> void:
	if not await _until(_playing, 60.0):
		check(false, "joined the server (%s)" % ", ".join(_errors))
		return
	check(true, "joined the server")
	G.net.send_chat("/give planks 3")
	check(await _until(func(): return _count(Blocks.PLANKS) >= 3, 10.0), "got planks")
	if G.has_arg("--nettest-zombies"):
		G.net.send_chat("/spawn night 4")
		check(await _until(func(): return _mob_ids([Proto.MOB_NIGHT]).size() >= 3, 10.0), "zombies are coming")
	var at: Vector3 = G.player.global_position
	print("NETTEST linger pos=%.3f,%.3f,%.3f" % [at.x, at.y, at.z])
	await _wait(0.5)  # that position reaches the server
	print("NETTEST linger ready")
	await _wait(60.0)
	check(false, "was killed by the test script")


func _run_lwatch() -> void:
	if not await _until(_playing, 60.0):
		check(false, "joined the server (%s)" % ", ".join(_errors))
		return
	print("NETTEST online")
	var alice := func() -> int:
		for id in G.net.others:
			if G.net.others[id]["name"] == "alice":
				return id
		return 0
	var away := func() -> bool:
		var id: int = alice.call()
		return id != 0 and not G.net.others[id]["samples"].is_empty() and (int(G.net.others[id]["samples"].back()[4]) & Proto.F_AWAY) != 0
	var said := func(prefix: String) -> int: return _notices.filter(func(n): return String(n).begins_with(prefix)).size()
	# 1. alice's game crashes: her character stays, marked away.
	check(await _until(func(): return said.call("alice lost the connection.") >= 1, 120.0), "alice's game is gone")
	check(await _until(away, 3.0), "her character stays in the world, marked away")
	var rp = G.game.remote_players.get(alice.call())
	check(rp != null and "(away)" in rp.label.text, "its name tag says (away)")
	# 2. She comes back in time (the same character continues), then leaves through the menu:
	# her character goes at once.
	check(await _until(func(): return said.call("alice left the game.") >= 1, 90.0), "alice came back and left")
	var t0 := Time.get_ticks_msec()
	check(await _until(func(): return alice.call() == 0, 5.0), "leaving on purpose takes her character out at once (%.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("NETTEST lwatch gone")
	# 3. Her game crashes with zombies after her: they kill the character.
	check(await _until(func(): return _has_notice("alice died."), 90.0), "the zombies killed her character after her game was gone")
	check(await _until(func(): return alice.call() == 0, 40.0), "and it's gone from the world")
	print("NETTEST lwatch done")


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
	# What's in our hand shows in theirs: "a" holds a torch, "b" berries (the starter kit).
	await _until(func(): return _count(Blocks.TORCH) == 2 and _count(Items.BERRIES) == 3, 10.0)
	_select(Blocks.TORCH if role == "a" else Items.BERRIES)

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
	var expect_held: int = Items.BERRIES if role == "a" else Blocks.TORCH
	var held_of := func(): return int(G.net.others[oid].get("held", 0))
	check(await _until(func(): return held_of.call() == expect_held, 5.0), "sees what %s holds (%s)" % [other, Items.name_of(held_of.call())])
	check(rp != null and rp.held.visible, "draws it in their hand")
	if G.arg_value("--shots=") != "" and rp != null:
		await _walk_to(rp.global_position, 4.0, 8.0)  # close enough to see what they hold
		await _wait(0.5)
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

	# Backpacks (M2): "a" dies with things on it and "b" picks up the pack; a second one falls
	# apart by itself (this server runs with --backpack-s=30).
	if role == "a":
		G.net.send_chat("/give planks 5")
		await _until(func(): return _count(Blocks.PLANKS) == 5, 10.0)
		G.net.send_chat("/kill")
		check(await _until(func(): return p.dead and G.net.my_backpacks.size() == 1, 10.0), "/kill: dead, with a backpack marker")
		var bp := _new_backpack([])
		check(await _until(func(): return G.world.get_blockv(bp) == Blocks.BACKPACK, 5.0), "the backpack is in the world (%s)" % bp)
		check(_count(Blocks.PLANKS) == 0 and _count(Blocks.TORCH) == 0, "everything went into it")
		G.game.respawn()
		await _until(func(): return not p.dead, 10.0)
		G.net.send_chat("NT bp %d %d %d" % [bp.x, bp.y, bp.z])
		check(await _until(func(): return G.net.my_backpacks.is_empty() and G.world.get_blockv(bp) == Blocks.AIR, 45.0),
			"%s picked up my backpack (my marker is gone)" % other)
		G.net.send_chat("/give dirt 2")
		await _until(func(): return _count(Blocks.DIRT) == 2, 10.0)
		G.net.send_chat("/kill")
		check(await _until(func(): return p.dead and G.net.my_backpacks.size() == 1, 10.0), "died again: a second backpack")
		var bp2 := _new_backpack([])
		G.game.respawn()
		check(await _until(func(): return G.net.my_backpacks.is_empty() and G.world.get_blockv(bp2) == Blocks.AIR, 60.0),
			"left alone, it falls apart")
	else:
		check(await _until(func(): return _chat_from(other, "NT bp ") != "", 40.0), "%s says where its backpack is" % other)
		var v := _vec(_chat_from(other, "NT bp "))
		var bp := Vector3i(int(v.x), int(v.y), int(v.z))
		check(await _until(func(): return G.world.get_blockv(bp) == Blocks.BACKPACK, 10.0), "sees %s's backpack" % other)
		var torches := _count(Blocks.TORCH)
		await _mine_backpack(bp, 20.0)
		check(await _until(func(): return _count(Blocks.PLANKS) == 5 and _count(Blocks.TORCH) == torches + 2, 5.0),
			"mined it and got %s's things" % other)

	G.net.send_chat("NT checked")
	check(await _until(func(): return _chat_from(other, "NT checked") != "", 100.0), "%s finished its checks" % other)
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
	h._show_panel(h.solo_panel)
	await _wait(0.3)
	await _shot("5_solo")


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
	await _hash_check("after reconnecting, the blocks match the server's", _chunk_of(_base()))


# ------------------------------------------------------------ building together (M1.3)

func _count(id: int) -> int:
	return G.player.inv.count(id)


## The count in the server's copy of our inventory (without our own guesses on top).
func _server_count(id: int) -> int:
	var n := 0
	for sl in G.net.inv_slots:
		if sl != null and int(sl["id"]) == id:
			n += int(sl["n"])
	return n


## Hotbar slot holding `id`, selected; -1 if it isn't in the hotbar.
func _select(id: int) -> int:
	for i in 9:
		if G.player.inv.id_at(i) == id:
			G.player.select(i)
			return i
	return -1


## Hold `id` in the hand: select it in the hotbar, or (a full hotbar puts new things in the
## backpack) swap it into the selected slot first, as a player would. The selected slot, or -1.
func _hold(id: int) -> int:
	if _select(id) >= 0:
		return G.player.selected
	for i in range(9, Inventory.SIZE):
		if G.player.inv.id_at(i) == id:
			var slot: int = G.player.selected
			G.net.request_swap(i, slot)
			await _until(func(): return G.net.inv_slots[slot] != null and int(G.net.inv_slots[slot]["id"]) == id, 5.0)
			return slot
	return -1


## The player's position as a block, and the chunk it's in.
func _base() -> Vector3i:
	var p: Vector3 = G.player.global_position
	return Vector3i(floori(p.x), floori(p.y), floori(p.z))


static func _chunk_of(v: Vector3i) -> Vector2i:
	return Vector2i(v.x >> 4, v.z >> 4)


## Topmost block of a column near height y (within 3), if it's soft ground a hand can collect.
func _soft_ground(x: int, z: int, y: int) -> Vector3i:
	for yy in range(y + 3, y - 4, -1):
		var id: int = G.world.get_block(x, yy, z)
		if id != Blocks.AIR:
			if id in [Blocks.GRASS, Blocks.DIRT, Blocks.SAND]:
				return Vector3i(x, yy, z)
			return Vector3i(0, -1, 0)
	return Vector3i(0, -1, 0)


static func _drop_of(id: int) -> int:
	return Blocks.DIRT if id == Blocks.GRASS else id


## Ask the server for its fingerprint of the blocks around chunk c and compare it with ours.
## Asks up to 5 times: just after joining, the server may not have generated every chunk yet.
func _hash_check(what: String, c: Vector2i, r := 1) -> void:
	var prefix := "HASH %d %d %d " % [c.x, c.y, r]
	var ok := false
	var mine := ""
	var server := ""
	for attempt in 5:
		_notices = _notices.filter(func(n): return not String(n).begins_with(prefix))
		G.net.send_chat("/hash %d %d %d" % [c.x, c.y, r])
		ok = await _until(func(): return _notices.any(func(n): return String(n).begins_with(prefix)), 10.0)
		await _wait(0.5)  # the edit batch of the same tick may still be on its way
		for n in _notices:
			if String(n).begins_with(prefix):
				server = String(n).substr(prefix.length())
		mine = G.world.region_hash(c.x, c.y, r)
		if ok and mine == server:
			break
		await _wait(1.0)
	check(ok and mine == server, "%s (ours %s, server %s)" % [what, mine, server])


func _look_at(target: Vector3) -> void:
	var p = G.player
	var d: Vector3 = target - p.cam.global_position
	p.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))


func _recipe(out: int) -> int:
	for i in Crafting.RECIPES.size():
		if int(Crafting.RECIPES[i]["out"]) == out:
			return i
	return -1


func _run_builder() -> void:
	if not await _until(_playing, 60.0):
		check(false, "joined the server (%s)" % ", ".join(_errors))
		return
	check(await _until(func(): return _other_id() != 0, 30.0), "the watcher is here")
	check(await _until(func(): return _count(Items.BERRIES) == 3 and _count(Blocks.TORCH) == 2, 10.0), "got the starter kit from the server")
	var p = G.player
	var base := _base()
	var chunk := _chunk_of(base)
	print("NETTEST built_chunk=%d,%d" % [chunk.x, chunk.y])

	G.net.send_chat("/give dirt 20")
	check(await _until(func(): return _count(Blocks.DIRT) >= 20, 10.0), "admin /give dirt 20")

	# Mine three blocks of soft ground two steps away, by hand.
	var mined := []
	for x in [base.x + 2, base.x + 3]:
		for z in range(base.z - 2, base.z + 3):
			var g := _soft_ground(x, z, base.y - 1)
			if g.y >= 0 and mined.size() < 3:
				mined.append(g)
	check(mined.size() == 3, "found 3 blocks of soft ground to mine")
	var expect := {}  # drop item -> count we should end up with
	for b in mined:
		var d := _drop_of(G.world.get_blockv(b))
		expect[d] = int(expect.get(d, _count(d))) + 1
	for b in mined:
		p.break_block(b, G.world.get_blockv(b))
		await _wait(1.0)
	var got_drops := await _until(func():
		for id in expect:
			if _count(id) != expect[id]:
				return false
		return true, 5.0)
	check(got_drops, "mined 3 blocks, the server gave the drops %s" % [expect])
	check(mined.all(func(b): return G.world.get_blockv(b) == Blocks.AIR), "the mined blocks stay gone")

	# A pillar of dirt where the first block was.
	var dirt_before := _count(Blocks.DIRT)
	_select(Blocks.DIRT)
	var pillar: Vector3i = mined[0]
	for i in 3:
		check(p.try_place(pillar + Vector3i(0, i, 0), Blocks.DIRT), "placed dirt %d" % (i + 1))
		await _wait(0.3)
	check(await _until(func(): return _server_count(Blocks.DIRT) == dirt_before - 3, 5.0), "the server took 3 dirt for the pillar")
	check(_count(Blocks.DIRT) == dirt_before - 3, "the hotbar shows the same count")
	await _hash_check("our blocks match the server's", chunk)
	G.net.send_chat("NT built %d %d %d %d %d" % [chunk.x, chunk.y, pillar.x, pillar.y, pillar.z])
	check(await _until(func(): return _chat_from(G.net.others[_other_id()]["name"], "NT seen") != "", 30.0), "the watcher checked")

	# Crafting: nothing without a workbench, then planks, sticks, a workbench, a pickaxe at it.
	G.net.send_chat("/give logs 4")
	check(await _until(func(): return _count(Blocks.LOG) >= 4, 10.0), "admin /give logs 4 (plural name)")
	G.net.request_craft(_recipe(Items.WOOD_PICK), 1)
	await _wait(1.0)
	check(_count(Items.WOOD_PICK) == 0, "no pickaxe without a workbench")
	G.net.request_craft(_recipe(Blocks.PLANKS), 3)
	check(await _until(func(): return _count(Blocks.PLANKS) == 12, 5.0), "crafted 12 planks")
	G.net.request_craft(_recipe(Items.STICK), 1)
	G.net.request_craft(_recipe(Blocks.WORKBENCH), 1)
	check(await _until(func(): return _count(Items.STICK) == 4 and _count(Blocks.WORKBENCH) == 1, 5.0), "crafted sticks and a workbench")
	var bench := Vector3i(0, -1, 0)
	for z in range(base.z - 2, base.z + 3):
		var top: int = G.world.surface_y(base.x - 2, z)
		if top >= 0 and G.world.get_block(base.x - 2, top + 1, z) == Blocks.AIR and absi(top - base.y) <= 2:
			bench = Vector3i(base.x - 2, top + 1, z)
			break
	_select(Blocks.WORKBENCH)
	check(bench.y >= 0 and p.try_place(bench, Blocks.WORKBENCH), "placed the workbench")
	check(await _until(func(): return _server_count(Blocks.WORKBENCH) == 0, 5.0), "the server placed it")
	await _wait(0.3)
	G.net.request_craft(_recipe(Items.WOOD_PICK), 1)
	check(await _until(func(): return _count(Items.WOOD_PICK) == 1, 5.0), "crafted a wooden pickaxe at the workbench")
	if G.arg_value("--shots=") != "":
		G.game.open_inventory()
		await _wait(0.5)
		await _shot("inventory")
		G.game.close_inventory()

	# Eating goes through the server (health and food are its): a 10 m fall first, so we can eat.
	p.global_position += Vector3(0, 10, 0)
	check(await _until(func(): return p.health < 90.0, 8.0), "a fall hurt us (health %.0f)" % p.health)
	await _until(func(): return p.is_on_floor(), 5.0)
	var hp_low: float = p.health
	var bslot := _select(Items.BERRIES)
	p.consume(Items.BERRIES)
	check(await _until(func(): return p.health > hp_low and _count(Items.BERRIES) == 2, 5.0), "ate berries (health %.0f -> %.0f)" % [hp_low, p.health])
	G.net.request_swap(bslot, 20)
	check(await _until(func(): return G.net.inv_slots[20] != null and int(G.net.inv_slots[20]["id"]) == Items.BERRIES, 5.0), "moved the berries into the backpack")

	# Race: both players break the same block; only one may get it.
	var race := Vector3i(0, -1, 0)
	for z in range(base.z + 1, base.z + 4):
		var g := _soft_ground(base.x - 1, z, base.y - 1)
		if g.y >= 0:
			race = g
			break
	check(race.y >= 0, "found a block to race for")
	var rid: int = G.world.get_blockv(race)
	var before := _count(_drop_of(rid))
	G.net.send_chat("NT race %d %d %d" % [race.x, race.y, race.z])
	p.break_block(race, rid)
	var other: String = G.net.others[_other_id()]["name"]
	check(await _until(func(): return _chat_from(other, "NT racegot ") != "", 15.0), "the watcher raced too")
	await _wait(1.0)
	var mine := _count(_drop_of(rid)) - before
	var theirs := int(_chat_from(other, "NT racegot ").split(" ")[2])
	check(mine + theirs == 1, "two players broke the same block: exactly one got it (us %d, them %d)" % [mine, theirs])
	check(G.world.get_blockv(race) == Blocks.AIR, "the raced block is gone")
	await _hash_check("still the same blocks as the server", chunk)
	G.net.send_chat("NT done")
	await _wait(1.0)


func _run_watcher() -> void:
	if not await _until(_playing, 60.0):
		check(false, "joined the server (%s)" % ", ".join(_errors))
		return
	check(await _until(func(): return _other_id() != 0, 30.0), "the builder is here")
	var other: String = G.net.others[_other_id()]["name"]
	check(await _until(func(): return _chat_from(other, "NT built") != "", 60.0), "the builder built")
	var bp := _chat_from(other, "NT built").split(" ")
	var chunk := Vector2i(int(bp[2]), int(bp[3]))
	await _wait(0.5)
	await _hash_check("sees the builder's blocks exactly as the server has them", chunk)
	if G.arg_value("--shots=") != "" and bp.size() >= 7:
		_look_at(Vector3(int(bp[4]), int(bp[5]), int(bp[6])) + Vector3(0.5, 1.5, 0.5))
		await _wait(0.5)
		await _shot("pillar")
	G.net.send_chat("NT seen")
	check(await _until(func(): return _chat_from(other, "NT race ") != "", 60.0), "race started")
	var parts := _chat_from(other, "NT race ").split(" ")
	var race := Vector3i(int(parts[2]), int(parts[3]), int(parts[4]))
	var rid: int = G.world.get_blockv(race)
	var drop := _drop_of(rid) if rid != Blocks.AIR else Blocks.DIRT
	var before := _count(drop)
	if rid != Blocks.AIR:
		G.player.break_block(race, rid)
	await _wait(2.0)
	G.net.send_chat("NT racegot %d" % (_count(drop) - before))
	check(G.world.get_blockv(race) == Blocks.AIR, "the raced block is gone here too")
	check(await _until(func(): return _chat_from(other, "NT done") != "", 60.0), "the builder finished")


func _run_late() -> void:
	if not await _until(_playing, 60.0):
		check(false, "joined the server (%s)" % ", ".join(_errors))
		return
	var e := G.arg_value("--nettest-expect=").split(",")
	var chunk := Vector2i(int(e[0]), int(e[1])) if e.size() == 2 else _chunk_of(_base())
	await _wait(1.0)
	await _hash_check("a late joiner gets the edited chunks", chunk)


func _run_soak() -> void:
	if not await _until(_playing, 60.0):
		check(false, "joined the server (%s)" % ", ".join(_errors))
		return
	var secs := float(G.arg_value("--nettest-soak="))
	var me := G.arg_value("--name=")
	G.net.send_chat("/give dirt 200")
	check(await _until(func(): return _count(Blocks.DIRT) >= 200, 10.0), "admin /give dirt 200")
	check(await _until(func(): return G.net.others.size() >= 2, 60.0), "all three soak players are here")
	await _wait(1.0)
	var p = G.player
	var base := _base()
	var chunk := _chunk_of(base)
	var surf := {}
	for x in range(base.x + 2, base.x + 6):
		for z in range(base.z - 2, base.z + 2):
			surf[Vector2i(x, z)] = G.world.surface_y(x, z)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(me)
	var places := 0
	var breaks := 0
	var t_end := Time.get_ticks_msec() + secs * 1000.0
	while Time.get_ticks_msec() < t_end:
		# One edit every 0.2 s: try random spots until one can be broken or built on.
		for attempt in 20:
			var col: Vector2i = surf.keys()[rng.randi_range(0, surf.size() - 1)]
			var pos := Vector3i(col.x, surf[col] + rng.randi_range(1, 3), col.y)
			var id: int = G.world.get_blockv(pos)
			if id != Blocks.AIR:
				p.break_block(pos, id)
				breaks += 1
				break
			if G.world.get_blockv(pos + Vector3i.DOWN) != Blocks.AIR and _select(Blocks.DIRT) >= 0 and p.try_place(pos, Blocks.DIRT):
				places += 1
				break
		await _wait(0.2)
	print("NETTEST soak %s: %d places, %d breaks" % [me, places, breaks])
	check(places + breaks >= secs * 4.0, "kept editing (%d places, %d breaks)" % [places, breaks])
	G.net.send_chat("NT soakdone")
	var all_done := func():
		var n := 0
		for c in _chats:
			if c[1] == "NT soakdone":
				n += 1
		return n >= 3
	check(await _until(all_done, 60.0), "every soak player finished")
	await _wait(2.0)
	await _hash_check("after the soak, our world matches the server's", chunk)
	await _wait(2.0)


# ------------------------------------------------------------ zombies and animals (M1.4)

## Mob ids the server currently shows us, of the given kinds.
func _mob_ids(kinds: Array) -> Array:
	return G.net.mobs.keys().filter(func(id): return kinds.has(int(G.net.mobs[id]["kind"])))


func _mob_dist(id: int) -> float:
	var s: Dictionary = G.net.mob_sample(id)
	return 999.0 if s.is_empty() else (s["pos"] as Vector3).distance_to(G.player.global_position)


## Walk up to backpack `bp` and mine it (M2). Whoever mines it gets what's in it.
func _mine_backpack(bp: Vector3i, secs := 30.0) -> void:
	var target := Vector3(bp) + Vector3(0.5, 0.0, 0.5)
	await _walk_to(target, 2.0, secs)
	await _until(func(): return G.player.is_on_floor(), 3.0)
	_look_at(target + Vector3(0, 0.3, 0))
	if G.world.get_blockv(bp) == Blocks.BACKPACK:
		G.player.break_block(bp, Blocks.BACKPACK)


## Our own backpack that isn't in `known` (the newest one), or Vector3i.MIN.
func _new_backpack(known: Array) -> Vector3i:
	for e in G.net.my_backpacks:
		if not known.has(e[0]):
			return e[0]
	return Vector3i.MIN


## Walk (sprinting) toward a point for up to `secs`; true once within `near` metres.
func _walk_to(target: Vector3, near: float, secs: float) -> bool:
	var p = G.player
	var t0 := Time.get_ticks_msec()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var ok := false
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		var d: Vector3 = target - p.global_position
		if Vector2(d.x, d.z).length() <= near:
			ok = true
			break
		p.set_look(atan2(-d.x, -d.z), 0.0)
		if p.is_on_floor() and p.get_real_velocity().length() < 1.0:
			Input.action_press("jump")  # stuck on a ledge
		else:
			Input.action_release("jump")
		await _wait(0.1)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	Input.action_release("jump")
	return ok


## Hit mob `id` with the selected item until it's gone (or `secs` pass). True if it died.
func _fight(id: int, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		if not G.net.mobs.has(id) or (int(G.net.mobs[id]["samples"].back()[4]) & Proto.MF_DEAD):
			return true
		var s: Dictionary = G.net.mob_sample(id)
		if not s.is_empty():
			_look_at(s["pos"] + Vector3(0, 1.0, 0))
			if _mob_dist(id) < 3.4:
				G.player.attack_cd = 0.0
				G.net.request_attack(id, G.player.selected)
		await _wait(0.5)
	return false


func _run_fighter() -> void:
	if not await _until(_playing, 60.0):
		check(false, "joined the server (%s)" % ", ".join(_errors))
		return
	check(await _until(func(): return _other_id() != 0, 30.0), "the watcher is here")
	var other: String = G.net.others[_other_id()]["name"]
	check(await _until(func(): return _chat_from(other, "NT away") != "", 30.0), "the watcher walked away")
	var p = G.player
	G.net.send_chat("/give stone_sword")
	G.net.send_chat("/give dirt 40")
	check(await _until(func(): return _count(Items.STONE_SWORD) == 1 and _count(Blocks.DIRT) >= 40, 10.0), "admin /give sword and dirt")
	_select(Items.STONE_SWORD)

	# A fall, here at the spawn point where no tree is in the way: the movement is ours, the
	# damage the server's.
	await _until(func(): return p.is_on_floor(), 5.0)
	var hp_before: float = p.health
	p.global_position += Vector3(0, 12, 0)
	check(await _until(func(): return p.health < hp_before - 5.0, 8.0), "a 12 m fall hurts (health %.0f -> %.0f)" % [hp_before, p.health])
	await _until(func(): return p.is_on_floor(), 5.0)
	await _wait(1.0)  # healed a little? the zombie still has to hurt us below

	var before: Array = G.net.mobs.keys()
	var hurts0 := int(G.net.bytes_in.get(Proto.S_HURT, 0))
	G.net.send_chat("/spawn zombie 1")
	var fresh := func(): return _mob_ids([Proto.MOB_ZOMBIE]).filter(func(id): return not before.has(id))
	check(await _until(func(): return not fresh.call().is_empty(), 10.0), "a zombie appears")
	var zid: int = fresh.call()[0] if not fresh.call().is_empty() else 0
	print("NETTEST zombie_id=%d" % zid)
	G.net.send_chat("NT zombie %d" % zid)
	var d0 := _mob_dist(zid)
	# Without pathfinding (M5) a zombie behind a tree has to dig through, so only check that it
	# heads our way, then meet it.
	check(await _until(func(): return _mob_dist(zid) < d0 - 3.0, 20.0), "the zombie comes for us (from %.0f m)" % d0)
	# Meet it; if a tree or a ledge is in the way, keep going to where it is now (as a player would).
	# Without pathfinding a zombie that spawned in a bad spot may still never get to us: then a
	# fresh one somewhere else (up to 3).
	var hurt := func(): return int(G.net.bytes_in.get(Proto.S_HURT, 0)) > hurts0
	for attempt in 3:
		if attempt > 0:
			print("NETTEST zombie %d can't get to us: clearing it and spawning another" % zid)
			G.net.send_chat("/clear")
			await _until(func(): return not G.net.mobs.has(zid), 5.0)
			var known: Array = G.net.mobs.keys()
			G.net.send_chat("/spawn zombie 1")
			await _until(func(): return _mob_ids([Proto.MOB_ZOMBIE]).any(func(id): return not known.has(id)), 10.0)
			var got: Array = _mob_ids([Proto.MOB_ZOMBIE]).filter(func(id): return not known.has(id))
			if not got.is_empty():
				zid = got[0]
		var t_meet := Time.get_ticks_msec()
		var t_log := 0
		while not hurt.call() and Time.get_ticks_msec() - t_meet < 15000:
			var zs: Dictionary = G.net.mob_sample(zid)
			if Time.get_ticks_msec() - t_log > 2000 and not zs.is_empty():
				t_log = Time.get_ticks_msec()
				print("NETTEST meeting zombie %d: we are at %s, it is at %s (%.1f m, flags %d)" % [zid, p.global_position, zs["pos"], _mob_dist(zid), int(zs.get("flags", 0))])
			if not zs.is_empty() and _mob_dist(zid) > 1.2:
				await _walk_to(zs["pos"], 1.0, 2.0)
			else:
				await _wait(0.3)
		if hurt.call():
			break
	check(hurt.call(), "a zombie hurts us (health %.0f)" % p.health)
	check(await _fight(zid, 20.0), "killed the zombie")
	check(await _until(func(): return G.game.kills == 1, 5.0), "the server counted the kill (%d)" % G.game.kills)
	check(await _until(func(): return not G.net.mobs.has(zid), 5.0), "the dead zombie goes away")
	G.net.send_chat("NT zdone")


	# A dirt ring two high around us, then a horde: they must crack it.
	await _until(func(): return p.is_on_floor(), 5.0)
	var c := _base()
	# Stand in the middle of our block, or our own body blocks the cells around it. That can step
	# us off a ledge, so plan the wall once we stand still again.
	p.global_position = Vector3(c.x + 0.5, p.global_position.y, c.z + 0.5)
	p.velocity = Vector3.ZERO
	await _wait(0.5)
	await _until(func(): return p.is_on_floor(), 5.0)
	var ring: Array = await _wall_in()
	var walled := ring.filter(func(b): return G.world.get_blockv(b) != Blocks.AIR).size()
	check(walled >= 14, "walled ourselves in (%d of 16 around us are solid)" % walled)
	G.net.send_chat("/spawn horde 4")
	check(await _until(func(): return _mob_ids([Proto.MOB_HORDE]).size() >= 3, 10.0), "a horde appears")
	# Zombies that spawned behind a cliff dig their way over; any digging shows as cracks too.
	# (Up to 150 s: the arm64 server under qemu runs well behind real time.)
	var cracked := await _until(func(): return int(G.net.bytes_in.get(Proto.S_CRACKS, 0)) > 0, 150.0)
	check(cracked, "the horde cracks blocks")
	if not cracked:
		for id in _mob_ids([Proto.MOB_HORDE]):
			var hs: Dictionary = G.net.mob_sample(id)
			print("NETTEST horde zombie %d at %s, %.1f m away (we are at %s)" % [id, hs.get("pos"), _mob_dist(id), p.global_position])
	# Dying: a 40 m fall always kills (the horde might take a while to dig in).
	if not p.dead:
		p.global_position += Vector3(0, 40, 0)
	check(await _until(func(): return p.dead, 15.0), "died (health %.0f)" % p.health)
	check(G.game.state == "dead", "the death screen shows")
	# The horde is at the spawn point too: clear it first, or it kills us again right away.
	G.net.send_chat("/clear")
	check(await _until(func(): return _has_notice("Removed "), 10.0), "/clear")
	await _wait(1.0)
	G.game.respawn()
	check(await _until(func(): return not p.dead and p.health >= 99.0 and G.game.state == "playing", 10.0), "respawned with full health")
	check(p.global_position.distance_to(G.session["spawn"]) < 3.0, "respawned at the spawn point")
	G.net.send_chat("NT fdone")
	await _wait(1.0)
	print("NETTEST mob bytes: %d" % int(G.net.bytes_in.get(Proto.S_MOBS, 0)))


## A dirt ring two high around the block we stand on; returns its 16 cells. Like a player
## would: a cell over open air gets a block under it first, and cells the server refused
## ("nothing to build on" until a neighbour is there) are tried again.
func _wall_in() -> Array:
	var p = G.player
	var c := _base()
	await _hold(Blocks.DIRT)
	var ring := []
	for dy in [0, 1]:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			ring.append(Vector3i(c.x + d.x, c.y + dy, c.z + d.y))
	var w = G.world
	for attempt in 3:
		for b in ring:
			if w.get_blockv(b) != Blocks.AIR:
				continue
			var below: Vector3i = b + Vector3i.DOWN
			if b.y == c.y and w.get_blockv(below) == Blocks.AIR and w.get_blockv(below + Vector3i.DOWN) != Blocks.AIR:
				p.try_place(below, Blocks.DIRT)
				await _wait(0.1)
			p.try_place(b, Blocks.DIRT)
			await _wait(0.1)
		await _wait(1.0)  # the server's answers (and corrections) arrive
		if ring.all(func(b): return w.get_blockv(b) != Blocks.AIR):
			break
	return ring


func _run_zwatch() -> void:
	if not await _until(_playing, 60.0):
		check(false, "joined the server (%s)" % ", ".join(_errors))
		return
	check(await _until(func(): return _other_id() != 0, 30.0), "the fighter is here")
	var other: String = G.net.others[_other_id()]["name"]
	# Walk 40 m away, so the zombie goes for the fighter, not us.
	var start: Vector3 = G.player.global_position
	await _walk_to(start + Vector3(40, 0, 0), 2.0, 12.0)
	check(G.player.global_position.distance_to(start) > 25.0, "walked away (%.0f m)" % G.player.global_position.distance_to(start))
	G.net.send_chat("NT away")
	check(await _until(func(): return _chat_from(other, "NT zombie ") != "", 40.0), "the fighter spawned a zombie")
	var zid := int(_chat_from(other, "NT zombie ").split(" ")[2])
	check(await _until(func(): return G.net.mobs.has(zid), 5.0), "we see the same zombie (id %d)" % zid)
	check(await _until(func(): return _chat_from(other, "NT zdone") != "", 60.0), "the fighter killed it")
	check(await _until(func(): return not G.net.mobs.has(zid), 5.0), "it's gone for us too")
	check(await _until(func(): return _chat_from(other, "NT fdone") != "", 240.0), "the fighter finished")


func _run_horde() -> void:
	if not await _until(_playing, 60.0):
		check(false, "joined the server (%s)" % ", ".join(_errors))
		return
	var secs := float(G.arg_value("--nettest-soak="))
	var me := G.arg_value("--name=")
	G.net.send_chat("/give iron_sword")
	check(await _until(func(): return _count(Items.IRON_SWORD) == 1, 10.0), "admin /give sword")
	_select(Items.IRON_SWORD)
	check(await _until(func(): return G.net.others.size() >= 2, 60.0), "all three are here")
	if me == "horde1":
		G.net.send_chat("/bloodmoon")
	check(await _until(func(): return G.game.horde_active, 30.0), "the Blood Moon rises")
	var p = G.player
	var most := 0
	var deaths := 0
	var hits := 0
	var bytes0 := int(G.net.bytes_in.get(Proto.S_MOBS, 0))
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		most = maxi(most, G.net.mobs.size())
		if p.dead:
			deaths += 1
			await _wait(1.0)
			G.game.respawn()
			await _until(func(): return not p.dead, 10.0)
			continue
		var best := 0
		var bd := 3.4
		for id in _mob_ids([Proto.MOB_ZOMBIE, Proto.MOB_NIGHT, Proto.MOB_HORDE]):
			var d := _mob_dist(id)
			if d < bd:
				bd = d
				best = id
		if best != 0:
			G.net.request_attack(best, p.selected)
			hits += 1
		await _wait(0.5)
	var kbit := (int(G.net.bytes_in.get(Proto.S_MOBS, 0)) - bytes0) * 8.0 / 1000.0 / secs
	print("NETTEST horde %s: at most %d mobs in view, %d kills, %d deaths, %d swings, mob updates %.0f kbit/s" % [me, most, G.game.kills, deaths, hits, kbit])
	check(most >= 15, "the horde came (%d at once)" % most)
	check(most <= 120, "never more than 120 zombies")
	check(kbit < 400.0, "mob updates cost %.0f kbit/s" % kbit)


# ------------------------------------------------------------ saving (M1.5)

func _run_saver() -> void:
	if not await _until(_playing, 60.0):
		check(false, "joined the server (%s)" % ", ".join(_errors))
		return
	var p = G.player
	G.net.send_chat("/give dirt 10")
	G.net.send_chat("/give stone_pickaxe")
	check(await _until(func(): return _count(Blocks.DIRT) >= 10 and _count(Items.STONE_PICK) == 1, 10.0), "admin /give dirt and a pickaxe")
	var base := _base()
	var spot := Vector3i(base.x + 2, G.world.surface_y(base.x + 2, base.z) + 1, base.z)
	_select(Blocks.DIRT)
	for i in 3:
		p.try_place(spot + Vector3i(0, i, 0), Blocks.DIRT)
		await _wait(0.3)
	check(await _until(func(): return _server_count(Blocks.DIRT) == 7, 5.0), "built a pillar")
	await _wait(0.5)
	var chunk := _chunk_of(base)
	await _hash_check("blocks match before saving", chunk)
	var pos: Vector3 = p.global_position
	print("NETTEST saved pos=%.3f,%.3f,%.3f chunk=%d,%d hash=%s dirt=%d" % [pos.x, pos.y, pos.z, chunk.x, chunk.y,
		G.world.region_hash(chunk.x, chunk.y, 1), _count(Blocks.DIRT)])
	await _wait(1.0)


func _run_crasher() -> void:
	if not await _until(_playing, 60.0):
		check(false, "joined the server (%s)" % ", ".join(_errors))
		return
	var secs := float(G.arg_value("--nettest-soak="))
	var want := int(G.arg_value("--nettest-crashes="))
	var p = G.player
	G.net.send_chat("/give dirt 300")
	check(await _until(func(): return _count(Blocks.DIRT) >= 300, 10.0), "admin /give dirt 300")
	var base := _base()
	var chunk := _chunk_of(base)
	var surf := {}
	for x in range(base.x + 2, base.x + 5):
		for z in range(base.z - 1, base.z + 2):
			surf[Vector2i(x, z)] = G.world.surface_y(x, z)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var edits := 0
	var drops := 0
	var t_end := Time.get_ticks_msec() + secs * 1000.0
	var was_online := true
	var back_ms := Time.get_ticks_msec()
	print("NETTEST crasher online 0")
	# Edit until the server has gone away `want` times and we've been back 4 s, or time is up.
	while Time.get_ticks_msec() < t_end and (drops < want or Time.get_ticks_msec() - back_ms < 4000):
		if not G.net.is_online() or G.game.state != "playing":
			if was_online:
				drops += 1
			was_online = false
			await _wait(0.2)
			continue
		if not was_online:
			back_ms = Time.get_ticks_msec()
			print("NETTEST crasher online %d" % drops)
		was_online = true
		var col: Vector2i = surf.keys()[rng.randi_range(0, surf.size() - 1)]
		var pos := Vector3i(col.x, surf[col] + rng.randi_range(1, 2), col.y)
		var id: int = G.world.get_blockv(pos)
		if id != Blocks.AIR:
			p.break_block(pos, id)
			edits += 1
		elif G.world.get_blockv(pos + Vector3i.DOWN) != Blocks.AIR and _select(Blocks.DIRT) >= 0 and p.try_place(pos, Blocks.DIRT):
			edits += 1
		await _wait(0.25)
	print("NETTEST crasher: %d edits, lost the server %d times" % [edits, drops])
	check(drops >= maxi(want, 1), "the server went away and came back (%d times)" % drops)
	check(await _until(func(): return G.net.is_online() and G.game.state == "playing", 60.0), "back online at the end")
	await _wait(3.0)
	await _hash_check("after the crashes our blocks match the restarted server's", chunk)
