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
##   builder      (admin) /give, mine, build a pillar, craft at a workbench it places, eat, move an
##                item, then race "watcher" to break the same block. Prints built_chunk=cx,cz
##   watcher      checks it sees the builder's blocks exactly as the server has them, and races
##   late         joins later: the edited chunks must arrive (--nettest-expect=cx,cz)
##   soak         (admin) 3 of these place and break blocks in one shared spot, 5 times a second
##                for --nettest-soak=S seconds; afterwards every world must match the server's

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
	elif role == "soak":
		limit = 120.0 + float(G.arg_value("--nettest-soak="))
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
	elif role == "builder":
		await _run_builder()
	elif role == "watcher":
		await _run_watcher()
	elif role == "late":
		await _run_late()
	elif role == "soak":
		await _run_soak()
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
	if G.arg_value("--nettest-has=") != "":
		var id := int(G.arg_value("--nettest-has="))
		check(await _until(func(): return _count(id) >= 1, 10.0), "kept its %s after leaving" % Items.name_of(id))
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
func _hash_check(what: String, c: Vector2i, r := 1) -> void:
	var prefix := "HASH %d %d %d " % [c.x, c.y, r]
	_notices = _notices.filter(func(n): return not String(n).begins_with(prefix))
	G.net.send_chat("/hash %d %d %d" % [c.x, c.y, r])
	var ok := await _until(func(): return _notices.any(func(n): return String(n).begins_with(prefix)), 10.0)
	await _wait(0.5)  # the edit batch of the same tick may still be on its way
	var server := ""
	for n in _notices:
		if String(n).begins_with(prefix):
			server = String(n).substr(prefix.length())
	var mine: String = G.world.region_hash(c.x, c.y, r)
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

	# Eating goes through the server; moving an item too.
	p.food = 50.0
	var bslot := _select(Items.BERRIES)
	p.consume(Items.BERRIES)
	check(await _until(func(): return p.food > 50.0 and _count(Items.BERRIES) == 2, 5.0), "ate berries (food %.0f)" % p.food)
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
