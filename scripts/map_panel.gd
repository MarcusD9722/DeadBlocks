extends Control
## The world map tab (M4.4): the explored land from MapData, dark where you haven't been, with
## you, your bed, your bags, your allies and tribe, and your own pins on it.
## Mouse: drag to move, wheel to zoom, right-click to add a pin (or remove the one under it).
## Controller (while the map has the focus): left stick moves, the triggers zoom, A adds a pin
## at the middle, X removes the pin there, clicking the right stick centers on you.

const ZOOM_MIN := 0.5      # pixels per block
const ZOOM_MAX := 8.0
const BG := Color(0.07, 0.08, 0.09)
const ALLY := Color(0.45, 0.75, 1.0)
const TRIBE := Color(0.45, 1.0, 0.55)
const PIN := Color(1.0, 0.4, 0.3)

## The block at the middle of the map, and pixels per block.
var center := Vector2.ZERO
var zoom := 2.0
var follow := true
var font: Font
var _dragging := false
var _drag_moved := 0.0
## The pin name field (a right-click opens it where the pin goes).
var name_box: PanelContainer
var name_edit: LineEdit
var _pin_at := Vector2i.ZERO


func _ready() -> void:
	font = ThemeDB.fallback_font
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	name_box = PanelContainer.new()
	name_box.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.12, 0.96)
	sb.border_color = Color(0.5, 0.55, 0.45)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	name_box.add_theme_stylebox_override("panel", sb)
	add_child(name_box)
	var hb := HBoxContainer.new()
	name_box.add_child(hb)
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size = Vector2(200, 34)
	name_edit.max_length = 24
	name_edit.placeholder_text = "Name this pin"
	name_edit.text_submitted.connect(func(_t): _add_pin())
	name_edit.gui_input.connect(func(e: InputEvent):
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			name_edit.accept_event()
			_close_name_box())
	hb.add_child(name_edit)
	var ok := Button.new()
	ok.text = "Add pin"
	ok.focus_mode = Control.FOCUS_ALL
	ok.pressed.connect(_add_pin)
	hb.add_child(ok)
	var no := Button.new()
	no.text = "Cancel"
	no.focus_mode = Control.FOCUS_ALL
	no.pressed.connect(_close_name_box)
	hb.add_child(no)


## The map tab opened: centered on you.
func opened() -> void:
	follow = true
	_close_name_box()
	if G.player != null:
		center = Vector2(G.player.global_position.x, G.player.global_position.z)
	grab_focus.call_deferred()


func center_on_me() -> void:
	follow = true
	center = Vector2(G.player.global_position.x, G.player.global_position.z)


func to_screen(x: float, z: float) -> Vector2:
	return size * 0.5 + (Vector2(x, z) - center) * zoom


func to_world(p: Vector2) -> Vector2:
	return center + (p - size * 0.5) / zoom


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if follow and G.player != null:
		center = Vector2(G.player.global_position.x, G.player.global_position.z)
	if has_focus():
		# The controller: the left stick moves the map, the triggers zoom.
		var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if mv.length() > 0.2:
			follow = false
			center += mv * delta * 600.0 / zoom
		var zi := Input.get_action_strength("attack") - Input.get_action_strength("use")
		if absf(zi) > 0.2 and Controls.pad_in_use:
			zoom = clampf(zoom * pow(2.0, zi * delta * 1.5), ZOOM_MIN, ZOOM_MAX)
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				var before := to_world(e.position)
				zoom = clampf(zoom * (1.25 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), ZOOM_MIN, ZOOM_MAX)
				if not follow:
					center += before - to_world(e.position)  # (zoom around the pointer)
			accept_event()
		elif e.button_index == MOUSE_BUTTON_LEFT:
			_dragging = e.pressed
			_drag_moved = 0.0
			if e.pressed:
				_close_name_box()
				grab_focus()
			accept_event()
		elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			_right_click(e.position)
			accept_event()
	elif e is InputEventMouseMotion and _dragging:
		_drag_moved += e.relative.length()
		if _drag_moved > 3.0:
			follow = false
			center -= e.relative / zoom
		accept_event()
	elif e is InputEventJoypadButton and e.pressed:
		match e.button_index:
			JOY_BUTTON_A:
				var c := to_world(size * 0.5)
				G.net.request_pin_add(floori(c.x), floori(c.y), "")
				accept_event()
			JOY_BUTTON_X:
				var i := pin_near(size * 0.5, 16.0)
				if i >= 0:
					G.net.request_pin_remove(i)
				accept_event()
			JOY_BUTTON_RIGHT_STICK:
				center_on_me()
				accept_event()
	elif e.is_action("ui_left") or e.is_action("ui_right") or e.is_action("ui_up") or e.is_action("ui_down"):
		accept_event()  # (the stick moves the map, not the focus)


## Right-click: remove the pin under the pointer, or name a new one there.
func _right_click(at: Vector2) -> void:
	var i := pin_near(at, 10.0)
	if i >= 0:
		G.hud.msg("Removed the pin %s." % G.net.pins[i]["name"], Color(1, 0.85, 0.7))
		G.net.request_pin_remove(i)
		return
	var w := to_world(at)
	_pin_at = Vector2i(floori(w.x), floori(w.y))
	name_edit.text = ""
	name_box.visible = true
	name_box.reset_size()
	name_box.position = (at + Vector2(12, -20)).clamp(Vector2.ZERO, size - name_box.size)
	name_edit.grab_focus()


func _add_pin() -> void:
	if name_box.visible:
		G.net.request_pin_add(_pin_at.x, _pin_at.y, name_edit.text)
	_close_name_box()


func _close_name_box() -> void:
	if name_box != null and name_box.visible:
		name_box.visible = false
		grab_focus()


## The pin within r pixels of a point on the map (-1: none).
func pin_near(at: Vector2, r: float) -> int:
	var best := -1
	var bd := r
	for i in G.net.pins.size():
		var p: Dictionary = G.net.pins[i]
		var d := to_screen(p["x"] + 0.5, p["z"] + 0.5).distance_to(at)
		if d <= bd:
			bd = d
			best = i
	return best


# ------------------------------------------------------------ drawing

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var md = G.game.map_data
	if md == null:
		return
	# The regions in view.
	var reg := float(MapData.REGION_PX)
	var lo := to_world(Vector2.ZERO)
	var hi := to_world(size)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if zoom >= 1.5 else CanvasItem.TEXTURE_FILTER_LINEAR
	for rz in range(floori(lo.y / reg), floori(hi.y / reg) + 1):
		for rx in range(floori(lo.x / reg), floori(hi.x / reg) + 1):
			var tex: Texture2D = md.region_tex(Vector2i(rx, rz))
			if tex != null:
				draw_texture_rect(tex, Rect2(to_screen(rx * reg, rz * reg), Vector2(reg, reg) * zoom), false)
	_draw_grid(lo, hi)
	# Bed, bags, pins, allies, you.
	if G.net.bed != Vector3i.MIN:
		_icon_marker(to_screen(G.net.bed.x + 0.5, G.net.bed.z + 0.5), G.tex.icon(Blocks.BED), "Your bed", Color(1, 0.75, 0.7))
	for e in G.net.my_backpacks:
		_icon_marker(to_screen(e[0].x + 0.5, e[0].z + 0.5), G.tex.icon(Blocks.BACKPACK), "Your bag", Color(1, 0.88, 0.45))
	for p in G.net.pins:
		var at := to_screen(p["x"] + 0.5, p["z"] + 0.5)
		_diamond(at, 7.0, PIN)
		_label(at + Vector2(0, -12), p["name"], PIN.lightened(0.3))
	for e in G.net.social:
		var rel: int = e["rel"]
		if rel & Proto.R_ALLY == 0 or e["id"] == 0:
			continue
		var s: Dictionary = G.net.interpolated(e["id"])
		if s.is_empty():
			continue
		var col := TRIBE if rel & Proto.R_TRIBE else ALLY
		if rel & Proto.R_AWAY:
			col.a = 0.5
		var at := to_screen(s["pos"].x, s["pos"].z)
		draw_circle(at, 6.0, Color(0, 0, 0, 0.7 * col.a))
		draw_circle(at, 4.5, col)
		_label(at + Vector2(0, -10), e["name"], col)
	if G.player != null:
		var me := to_screen(G.player.global_position.x, G.player.global_position.z)
		var yaw: float = G.player.head.rotation.y
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var side := Vector2(-fwd.y, fwd.x)
		var pts := PackedVector2Array([me + fwd * 11.0, me - fwd * 7.0 + side * 7.0, me - fwd * 3.0, me - fwd * 7.0 - side * 7.0])
		draw_colored_polygon(pts, Color(0, 0, 0, 0.8))
		var inner := PackedVector2Array()
		for q in pts:
			inner.append(me + (q - me) * 0.72)
		draw_colored_polygon(inner, Color(1, 1, 0.85))
	# The middle (where A puts a pin) on the controller, and where the pointer is.
	if Controls.pad_in_use and has_focus():
		var c := size * 0.5
		draw_line(c - Vector2(10, 0), c + Vector2(10, 0), Color(1, 1, 1, 0.8), 2.0)
		draw_line(c - Vector2(0, 10), c + Vector2(0, 10), Color(1, 1, 1, 0.8), 2.0)
	var mp := get_local_mouse_position()
	var info := ""
	if Rect2(Vector2.ZERO, size).has_point(mp) and not Controls.pad_in_use:
		var w := to_world(mp)
		info = "%d, %d" % [floori(w.x), floori(w.y)]
		if G.player != null:
			info += "   ·   %d m from you" % int(Vector2(G.player.global_position.x, G.player.global_position.z).distance_to(w))
	_text(Vector2(10, size.y - 12), info, 14, Color(1, 1, 1, 0.75))
	_scale_bar()


## Faint lines every 256 blocks (every 64 when zoomed in), so distances can be judged.
func _draw_grid(lo: Vector2, hi: Vector2) -> void:
	var step := 64.0 if zoom >= 2.0 else 256.0
	var col := Color(1, 1, 1, 0.06)
	for gx in range(ceili(lo.x / step), floori(hi.x / step) + 1):
		var x := to_screen(gx * step, 0).x
		draw_line(Vector2(x, 0), Vector2(x, size.y), col, 1.0)
	for gz in range(ceili(lo.y / step), floori(hi.y / step) + 1):
		var y := to_screen(0, gz * step).y
		draw_line(Vector2(0, y), Vector2(size.x, y), col, 1.0)


func _scale_bar() -> void:
	var metres := 10.0
	for m in [10.0, 25.0, 50.0, 100.0, 250.0, 500.0]:
		if m * zoom <= 140.0:
			metres = m
	var w := metres * zoom
	var p := Vector2(size.x - w - 16, size.y - 18)
	draw_line(p, p + Vector2(w, 0), Color(1, 1, 1, 0.8), 2.0)
	draw_line(p, p + Vector2(0, -6), Color(1, 1, 1, 0.8), 2.0)
	draw_line(p + Vector2(w, 0), p + Vector2(w, -6), Color(1, 1, 1, 0.8), 2.0)
	_text(p + Vector2(0, -10), "%d m" % int(metres), 13, Color(1, 1, 1, 0.8), w)


func _icon_marker(at: Vector2, tex: Texture2D, text: String, col: Color) -> void:
	draw_circle(at, 11.0, Color(0, 0, 0, 0.6))
	if tex != null:
		draw_texture_rect(tex, Rect2(at - Vector2(9, 9), Vector2(18, 18)), false)
	_label(at + Vector2(0, -14), text, col)


func _diamond(at: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r - 2), at + Vector2(r + 2, 0), at + Vector2(0, r + 2), at + Vector2(-r - 2, 0)]), Color(0, 0, 0, 0.75))
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]), col)


func _label(at: Vector2, text: String, col: Color) -> void:
	_text(at - Vector2(100, 0), text, 14, col, 200.0, HORIZONTAL_ALIGNMENT_CENTER)


func _text(at: Vector2, text: String, fsize: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	if text == "":
		return
	draw_string_outline(font, at, text, align, width, fsize, 4, Color(0, 0, 0, 0.8 * col.a))
	draw_string(font, at, text, align, width, fsize, col)
