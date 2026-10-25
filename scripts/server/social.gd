extends RefCounted
## Allies and tribes on the server (M4.4). NetServer owns one (`social`) and hands it C_SOCIAL.
##
## Allies are pairs of players who asked and accepted: they see each other on the map and as a
## waypoint, and each other's name tags through walls. A tribe (like ARK's) has a name, a leader
## and members: members are allies of each other, have a tribe chat (/t) and can respawn at any
## member's bed. Anyone in a tribe can invite; the leader can remove members, hand over the lead
## and rename it. A leader who leaves passes the lead on; the last one out ends the tribe.
## Allies and tribes are saved in world.json; requests and invitations only last while the
## server runs.

var ns: Node
## Lower-case name -> {other lower-case name: true}, both ways.
var allies := {}
## Ally requests: target -> {asker: true}.
var asks := {}
## Tribe id -> {"name", "leader": lower-case name, "members": [lower-case names, oldest first]}.
var tribes := {}
var tribe_of := {}
## Invitations: target -> {tribe id: inviter}.
var invites := {}
var _next_tribe := 1


func _init(server: Node) -> void:
	ns = server


func _shown(key: String) -> String:
	var acc = ns.accounts.get(key)
	return acc["name"] if acc != null else key


func is_ally(a: String, b: String) -> bool:
	if a == b:
		return false
	if allies.has(a) and allies[a].has(b):
		return true
	return tribe_of.has(a) and tribe_of.get(a) == tribe_of.get(b, -1)


func same_tribe(a: String, b: String) -> bool:
	return a != b and tribe_of.has(a) and tribe_of.get(a) == tribe_of.get(b, -1)


func _sp_of(key: String):
	var id: int = ns._peer_of_name(key)
	return ns.players[id] if id != 0 else null


func _online(key: String) -> bool:
	return _sp_of(key) != null


func _tell(key: String, text: String, col := Color(0.75, 0.9, 1)) -> void:
	var sp = _sp_of(key)
	if sp != null:
		ns._msg(sp, text, col)


func _note(key: String, text: String, col := Color(0.75, 0.9, 1)) -> void:
	var sp = _sp_of(key)
	if sp != null:
		ns._send_to(sp.peer_id, ns._notice_bytes(text, col))


func _tribe_note(tid: int, text: String, except := "") -> void:
	for m in tribes[tid]["members"]:
		if m != except:
			_note(m, text, Color(0.6, 1, 0.65))


# ------------------------------------------------------------ requests

func on_request(sp, action: int, who: String, text: String) -> void:
	var me: String = sp.player_name.to_lower()
	var them := who.strip_edges().to_lower()
	var why := ""
	match action:
		Proto.SOC_REFRESH:
			send(sp)
			return
		Proto.SOC_ASK:
			why = _ask(me, them)
		Proto.SOC_ACCEPT:
			why = _accept(me, them)
		Proto.SOC_DECLINE:
			if asks.has(me) and asks[me].erase(them):
				_note(them, "%s said no to being allies." % _shown(me), Color(1, 0.8, 0.6))
		Proto.SOC_REMOVE:
			if asks.has(them):
				asks[them].erase(me)
			if allies.has(me) and allies[me].erase(them):
				allies[them].erase(me)
				_note(them, "%s is no longer your ally." % _shown(me), Color(1, 0.8, 0.6))
				_note(me, "%s is no longer your ally." % _shown(them), Color(1, 0.8, 0.6))
				print("SERVER %s and %s are no longer allies" % [_shown(me), _shown(them)])
		Proto.SOC_FOUND:
			why = _found(me, text.strip_edges())
		Proto.SOC_INVITE:
			why = _invite(me, them)
		Proto.SOC_JOIN:
			why = _join(me, int(text))
		Proto.SOC_REFUSE:
			var tid := int(text)
			if invites.has(me) and invites[me].has(tid):
				var from: String = invites[me][tid]
				invites[me].erase(tid)
				_note(from, "%s said no to joining your tribe." % _shown(me), Color(1, 0.8, 0.6))
		Proto.SOC_LEAVE:
			if tribe_of.has(me):
				_tribe_note(tribe_of[me], "%s left the tribe." % _shown(me), me)
				_note(me, "You left the tribe %s." % tribes[tribe_of[me]]["name"], Color(1, 0.8, 0.6))
				print("SERVER %s left the tribe %s" % [_shown(me), tribes[tribe_of[me]]["name"]])
				leave_tribe(me)
		Proto.SOC_KICK:
			why = _kick(me, them)
		Proto.SOC_LEAD:
			why = _lead(me, them)
		Proto.SOC_RENAME:
			why = _rename(me, text.strip_edges())
	if why != "":
		ns._msg(sp, why, Color(1, 0.65, 0.5))
	send_all()


func _ask(me: String, them: String) -> String:
	if them == me or not ns.accounts.has(them):
		return "There is nobody called %s here." % them
	if is_ally(me, them):
		return "%s is your ally already." % _shown(them)
	if asks.has(me) and asks[me].has(them):
		return _accept(me, them)  # they asked first: that's a yes from both
	if not _online(them):
		return "%s is not online." % _shown(them)
	if not asks.has(them):
		asks[them] = {}
	asks[them][me] = true
	_tell(them, "%s wants to be your ally. Answer in the Players tab." % _shown(me))
	_note(them, "%s wants to be your ally (Players tab)." % _shown(me))
	_note(me, "You asked %s to be allies." % _shown(them))
	return ""


func _accept(me: String, them: String) -> String:
	if not (asks.has(me) and asks[me].has(them)):
		return "%s hasn't asked you." % _shown(them)
	asks[me].erase(them)
	if asks.has(them):
		asks[them].erase(me)
	for pair in [[me, them], [them, me]]:
		if not allies.has(pair[0]):
			allies[pair[0]] = {}
		allies[pair[0]][pair[1]] = true
	_note(me, "You and %s are allies now." % _shown(them), Color(0.6, 1, 0.65))
	_note(them, "You and %s are allies now." % _shown(me), Color(0.6, 1, 0.65))
	print("SERVER %s and %s are allies" % [_shown(me), _shown(them)])
	return ""


func _found(me: String, tname: String) -> String:
	if tribe_of.has(me):
		return "You are in a tribe already. Leave it first."
	if not Proto.valid_tribe_name(tname):
		return "A tribe's name is 3-24 letters, digits or spaces."
	if _tribe_named(tname) != 0:
		return "There is a tribe called %s already." % tname
	var tid := _next_tribe
	_next_tribe += 1
	tribes[tid] = {"name": tname, "leader": me, "members": [me]}
	tribe_of[me] = tid
	invites.erase(me)
	_note(me, "You founded the tribe %s. Invite players in the Players tab." % tname, Color(0.6, 1, 0.65))
	print("SERVER %s founded the tribe %s" % [_shown(me), tname])
	return ""


func _tribe_named(tname: String) -> int:
	for tid in tribes:
		if (tribes[tid]["name"] as String).to_lower() == tname.to_lower():
			return tid
	return 0


func _invite(me: String, them: String) -> String:
	if not tribe_of.has(me):
		return "Found a tribe first (Tribe tab)."
	if not _online(them) or them == me:
		return "%s is not online." % _shown(them)
	if tribe_of.has(them):
		return "%s is in a tribe already." % _shown(them)
	var tid: int = tribe_of[me]
	if not invites.has(them):
		invites[them] = {}
	invites[them][tid] = me
	_note(them, "%s invites you to the tribe %s (Tribe tab)." % [_shown(me), tribes[tid]["name"]], Color(0.6, 1, 0.65))
	_tell(them, "%s invites you to the tribe %s. Answer in the Tribe tab." % [_shown(me), tribes[tid]["name"]])
	_note(me, "You invited %s to the tribe." % _shown(them), Color(0.6, 1, 0.65))
	return ""


func _join(me: String, tid: int) -> String:
	if not (invites.has(me) and invites[me].has(tid)) or not tribes.has(tid):
		return "That invitation is gone."
	if tribe_of.has(me):
		return "You are in a tribe already. Leave it first."
	invites.erase(me)
	_tribe_note(tid, "%s joined the tribe." % _shown(me))
	tribes[tid]["members"].append(me)
	tribe_of[me] = tid
	_note(me, "You joined the tribe %s." % tribes[tid]["name"], Color(0.6, 1, 0.65))
	print("SERVER %s joined the tribe %s" % [_shown(me), tribes[tid]["name"]])
	return ""


func _kick(me: String, them: String) -> String:
	if not tribe_of.has(me) or tribes[tribe_of[me]]["leader"] != me:
		return "Only the tribe's leader can remove members."
	if them == me or tribe_of.get(them, -1) != tribe_of[me]:
		return "%s is not in your tribe." % _shown(them)
	var tid: int = tribe_of[me]
	_tribe_note(tid, "%s was removed from the tribe." % _shown(them), them)
	_note(them, "%s removed you from the tribe %s." % [_shown(me), tribes[tid]["name"]], Color(1, 0.8, 0.6))
	print("SERVER %s removed %s from the tribe %s" % [_shown(me), _shown(them), tribes[tid]["name"]])
	leave_tribe(them)
	return ""


func _lead(me: String, them: String) -> String:
	if not tribe_of.has(me) or tribes[tribe_of[me]]["leader"] != me:
		return "Only the tribe's leader can hand over the lead."
	if them == me or tribe_of.get(them, -1) != tribe_of[me]:
		return "%s is not in your tribe." % _shown(them)
	tribes[tribe_of[me]]["leader"] = them
	_tribe_note(tribe_of[me], "%s leads the tribe now." % _shown(them))
	return ""


func _rename(me: String, tname: String) -> String:
	if not tribe_of.has(me) or tribes[tribe_of[me]]["leader"] != me:
		return "Only the tribe's leader can rename it."
	if not Proto.valid_tribe_name(tname):
		return "A tribe's name is 3-24 letters, digits or spaces."
	var other := _tribe_named(tname)
	if other != 0 and other != tribe_of[me]:
		return "There is a tribe called %s already." % tname
	tribes[tribe_of[me]]["name"] = tname
	_tribe_note(tribe_of[me], "The tribe is called %s now." % tname)
	return ""


## Take a player out of their tribe: the lead passes to the oldest member, and an empty tribe ends.
func leave_tribe(key: String) -> void:
	if not tribe_of.has(key):
		return
	var tid: int = tribe_of[key]
	tribe_of.erase(key)
	var t: Dictionary = tribes[tid]
	(t["members"] as Array).erase(key)
	if (t["members"] as Array).is_empty():
		print("SERVER the tribe %s ended" % t["name"])
		tribes.erase(tid)
		for k in invites:
			invites[k].erase(tid)
	elif t["leader"] == key:
		t["leader"] = t["members"][0]
		_tribe_note(tid, "%s leads the tribe now." % _shown(t["leader"]))


## Tribe chat (/t text): to every member online.
func tribe_chat(sp, text: String) -> void:
	var me: String = sp.player_name.to_lower()
	if not tribe_of.has(me):
		ns._msg(sp, "You are not in a tribe.", Color(1, 0.65, 0.5))
		return
	print("CHAT [%s] <%s> %s" % [tribes[tribe_of[me]]["name"], sp.player_name, text])
	_tribe_note(tribe_of[me], "[Tribe] <%s> %s" % [sp.player_name, text])


## A player's ask and invitations go when they leave (the ones they got stay for their return).
func player_left(key: String) -> void:
	for k in asks:
		asks[k].erase(key)


# ------------------------------------------------------------ S_SOCIAL

## Everyone the player should see in the Players tab: everyone online or left behind, plus
## allies and tribe members who are offline.
func send(sp) -> void:
	var me: String = sp.player_name.to_lower()
	var keys := {}
	for p in ns.players.values():
		keys[p.player_name.to_lower()] = p
	for k in ns.lingering:
		if not keys.has(k):
			keys[k] = ns.lingering[k]
	for k in allies.get(me, {}):
		if not keys.has(k):
			keys[k] = null
	if tribe_of.has(me):
		for k in tribes[tribe_of[me]]["members"]:
			if not keys.has(k):
				keys[k] = null
	keys.erase(me)
	var m := Proto.writer(Proto.S_SOCIAL)
	var list := keys.keys()
	list.sort()
	m.put_u8(mini(list.size(), 255))
	for k in list.slice(0, 255):
		var p = keys[k]
		var rel := 0
		if is_ally(me, k):
			rel |= Proto.R_ALLY
		if same_tribe(me, k):
			rel |= Proto.R_TRIBE
			var bed: Vector3i = ns.accounts[k]["bed"] if ns.accounts.has(k) else Vector3i.MIN
			if bed != Vector3i.MIN:
				rel |= Proto.R_BED
		if asks.has(k) and asks[k].has(me):
			rel |= Proto.R_ASKED
		if asks.has(me) and asks[me].has(k):
			rel |= Proto.R_ASKS_YOU
		if tribe_of.has(k):
			rel |= Proto.R_IN_TRIBE
		if p != null:
			rel |= Proto.R_AWAY if p.peer_id == 0 else Proto.R_ONLINE
		m.put_utf8_string(_shown(k))
		m.put_u16(p.net_id if p != null else 0)
		m.put_u16(clampi(p.ping_ms if p != null and p.peer_id != 0 else 0, 0, 65535))
		m.put_u8(rel)
	if tribe_of.has(me):
		var t: Dictionary = tribes[tribe_of[me]]
		m.put_u8(1)
		m.put_u32(tribe_of[me])
		m.put_utf8_string(t["name"])
		m.put_utf8_string(_shown(t["leader"]))
	else:
		m.put_u8(0)
	var inv: Dictionary = invites.get(me, {})
	var tids := inv.keys().filter(func(t): return tribes.has(t))
	m.put_u8(tids.size())
	for tid in tids:
		m.put_u32(tid)
		m.put_utf8_string(tribes[tid]["name"])
		m.put_utf8_string(_shown(inv[tid]))
	ns._send_to(sp.peer_id, m.data_array)


func send_all() -> void:
	for p in ns.players.values():
		send(p)


# ------------------------------------------------------------ saving (world.json)

func allies_json() -> Array:
	var out := []
	for a in allies:
		for b in allies[a]:
			if a < b:
				out.append([a, b])
	return out


func tribes_json() -> Array:
	var out := []
	for tid in tribes:
		var t: Dictionary = tribes[tid]
		out.append({"id": tid, "name": t["name"], "leader": t["leader"], "members": (t["members"] as Array).duplicate()})
	return out


func load_json(ally_list: Array, tribe_list: Array) -> void:
	for e in ally_list:
		if e is Array and e.size() == 2:
			var a := str(e[0]).to_lower()
			var b := str(e[1]).to_lower()
			if a == b:
				continue
			for pair in [[a, b], [b, a]]:
				if not allies.has(pair[0]):
					allies[pair[0]] = {}
				allies[pair[0]][pair[1]] = true
	for e in tribe_list:
		if not (e is Dictionary and e.get("members") is Array):
			continue
		var tid := int(e.get("id", 0))
		if tid <= 0 or tribes.has(tid):
			continue
		var members := []
		for k in e["members"]:
			var key := str(k).to_lower()
			if not tribe_of.has(key) and not members.has(key):
				members.append(key)
		if members.is_empty():
			continue
		var leader := str(e.get("leader", "")).to_lower()
		if not members.has(leader):
			leader = members[0]
		tribes[tid] = {"name": str(e.get("name", "Tribe")), "leader": leader, "members": members}
		for key in members:
			tribe_of[key] = tid
		_next_tribe = maxi(_next_tribe, tid + 1)
