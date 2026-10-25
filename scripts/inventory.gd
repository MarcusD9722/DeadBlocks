class_name Inventory
extends RefCounted
## 36 slots. Slots 0-8 are the hotbar.

signal changed

const SIZE := 36
var slots: Array = []


func _init() -> void:
	slots.resize(SIZE)


func add(id: int, n: int) -> int:
	n = add_to(slots, id, n)
	changed.emit()
	return n


## Put n of id into a list of slots (an inventory's, or a storage box's): onto stacks of the
## same thing first, then into empty slots. Returns how many didn't fit.
static func add_to(list: Array, id: int, n: int) -> int:
	var mx := Items.stack_max(id)
	for i in list.size():
		if n <= 0:
			break
		var s = list[i]
		if s != null and int(s["id"]) == id and int(s["n"]) < mx:
			var k := mini(n, mx - int(s["n"]))
			s["n"] = int(s["n"]) + k
			n -= k
	for i in list.size():
		if n <= 0:
			break
		if list[i] == null:
			var k := mini(n, mx)
			list[i] = {"id": id, "n": k}
			n -= k
	return n


func can_fit(id: int, n: int) -> bool:
	var mx := Items.stack_max(id)
	var space := 0
	for s in slots:
		if s == null:
			space += mx
		elif int(s["id"]) == id:
			space += mx - int(s["n"])
	return space >= n


func count(id: int) -> int:
	var c := 0
	for s in slots:
		if s != null and int(s["id"]) == id:
			c += int(s["n"])
	return c


func remove(id: int, n: int) -> bool:
	if count(id) < n:
		return false
	for i in range(SIZE - 1, -1, -1):
		if n <= 0:
			break
		var s = slots[i]
		if s != null and int(s["id"]) == id:
			var k := mini(n, int(s["n"]))
			s["n"] = int(s["n"]) - k
			n -= k
			if int(s["n"]) <= 0:
				slots[i] = null
	changed.emit()
	return true


func remove_at(i: int, n: int) -> void:
	var s = slots[i]
	if s == null:
		return
	s["n"] = int(s["n"]) - n
	if int(s["n"]) <= 0:
		slots[i] = null
	changed.emit()


func swap(a: int, b: int) -> void:
	var t = slots[a]
	slots[a] = slots[b]
	slots[b] = t
	changed.emit()


func id_at(i: int) -> int:
	var s = slots[i]
	return 0 if s == null else int(s["id"])


func clear() -> void:
	for i in SIZE:
		slots[i] = null
	changed.emit()
