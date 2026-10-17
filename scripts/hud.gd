extends CanvasLayer
## Heads-up display, inventory + crafting screen, title, pause and death screens.

const CONTROLS := "WASD move   ·   Space jump   ·   Shift sprint   ·   Mouse look\n" + \
	"Left click: mine / attack (hold to mine)   ·   Right click: place, eat, use station\n" + \
	"1-9 / wheel: hotbar   ·   E: inventory & crafting   ·   F: flashlight\n" + \
	"Esc: pause   ·   F11: fullscreen   ·   F6: skip to night/dawn (testing)   ·   F7: jump to Blood Moon (testing)"

var canvas: Control
var font: Font
var msgs: Array = []
var pickups: Array = []

var title_root: Control
var title_status: Label
var inv_root: Control
var slot_btns: Array = []
var slot_lbls: Array = []
var recipe_box: VBoxContainer
var station_lbl: Label
var pause_root: Control
var seed_lbl: Label
var death_root: Control
var death_lbl: Label
var style_slot: StyleBoxFlat
var style_sel: StyleBoxFlat


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font
	style_slot = _style(Color(0.16, 0.17, 0.19, 0.95), Color(0.32, 0.34, 0.36), 1)
	style_sel = _style(Color(0.2, 0.24, 0.18, 0.95), Color(0.85, 0.95, 0.6), 2)
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	canvas.draw.connect(_draw_hud)
	_build_inventory()
	_build_pause()
	_build_death()
	_build_title()
	slot_btns.resize(36)
	slot_lbls.resize(36)


func _style(bg: Color, border: Color, w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(w)
	s.set_corner_radius_all(4)
	return s


func _label(text: String, size: int, col := Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _overlay(alpha: float) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, alpha)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	return root


func _center(root: Control) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(cc)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	cc.add_child(vb)
	return vb


# ------------------------------------------------------------ screens

func _build_title() -> void:
	title_root = _overlay(0.55)
	title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in title_root.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := _center(title_root)
	vb.get_parent().mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := _label("DEAD BLOCKS", 92, Color(0.85, 0.2, 0.15))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 12)
	vb.add_child(t)
	var sub := _label("Zombie Survival Craft   ·   Version %s (%s)" % [G.VERSION, G.BUILD_NAME], 24, Color(0.85, 0.85, 0.8))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	vb.add_child(Control.new())
	title_status = _label("Generating world...", 28, Color(0.95, 0.95, 0.7))
	title_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title_status)
	vb.add_child(Control.new())
	var how := _label("Gather. Craft. Build walls. Every night they come — every 7th night the horde comes.", 18, Color(0.8, 0.8, 0.8))
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(how)
	var ctl := _label(CONTROLS, 16, Color(0.7, 0.72, 0.7))
	ctl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ctl)
	title_root.visible = true


func set_loading(p: float) -> void:
	title_status.text = "Generating world...  %d%%" % int(p * 100.0)


func show_ready() -> void:
	title_status.text = "Click anywhere to start"


func hide_title() -> void:
	title_root.visible = false


func _build_pause() -> void:
	pause_root = _overlay(0.6)
	var vb := _center(pause_root)
	var t := _label("PAUSED", 56)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	row.add_child(_button("Resume", func(): G.game.resume()))
	row.add_child(_button("Quit Game", func(): get_tree().quit()))
	var sens_row := HBoxContainer.new()
	sens_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sens_row.add_theme_constant_override("separation", 12)
	vb.add_child(sens_row)
	sens_row.add_child(_label("Mouse sensitivity", 18))
	var sl := HSlider.new()
	sl.min_value = 0.5
	sl.max_value = 6.0
	sl.step = 0.1
	sl.value = 2.5
	sl.custom_minimum_size = Vector2(260, 24)
	sl.focus_mode = Control.FOCUS_NONE
	sl.value_changed.connect(func(v): G.player.sens = v * 0.001)
	sens_row.add_child(sl)
	var ctl := _label(CONTROLS, 16, Color(0.8, 0.82, 0.8))
	ctl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ctl)
	seed_lbl = _label("", 14, Color(0.6, 0.6, 0.6))
	seed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(seed_lbl)


func show_pause(on: bool) -> void:
	pause_root.visible = on
	seed_lbl.text = "World seed: %d" % G.game.seed_v


func _build_death() -> void:
	death_root = _overlay(0.55)
	death_root.get_child(0).color = Color(0.35, 0.0, 0.0, 0.55)
	var vb := _center(death_root)
	var t := _label("YOU DIED", 80, Color(0.95, 0.25, 0.2))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	death_lbl = _label("", 22)
	death_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(death_lbl)
	var b := _button("Respawn", func(): G.game.respawn())
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(b)


func show_death(on: bool) -> void:
	death_root.visible = on
	if on:
		death_lbl.text = "You made it to Day %d   ·   Zombies killed: %d\nYou keep your items. Your base is where you left it." % [G.game.day, G.game.kills]


# ------------------------------------------------------------ inventory & crafting

func _build_inventory() -> void:
	inv_root = _overlay(0.5)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	inv_root.add_child(cc)
	var panel := PanelContainer.new()
	var sb := _style(Color(0.09, 0.1, 0.11, 0.97), Color(0.36, 0.42, 0.3), 2)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 28)
	panel.add_child(hb)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	hb.add_child(left)
	left.add_child(_label("BACKPACK", 22, Color(0.85, 0.95, 0.7)))
	var grid := GridContainer.new()
	grid.columns = 9
	left.add_child(grid)
	for i in range(9, 36):
		grid.add_child(_make_slot(i))
	left.add_child(_label("HOTBAR", 18, Color(0.85, 0.95, 0.7)))
	var hgrid := GridContainer.new()
	hgrid.columns = 9
	left.add_child(hgrid)
	for i in range(0, 9):
		hgrid.add_child(_make_slot(i))
	var help := _label("Click a hotbar slot to select it. Click a backpack item\nto swap it into the selected hotbar slot.", 14, Color(0.7, 0.7, 0.7))
	left.add_child(help)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	hb.add_child(right)
	right.add_child(_label("CRAFTING", 22, Color(0.85, 0.95, 0.7)))
	station_lbl = _label("", 14, Color(0.75, 0.8, 0.85))
	right.add_child(station_lbl)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(500, 440)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(sc)
	recipe_box = VBoxContainer.new()
	recipe_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_box.add_theme_constant_override("separation", 6)
	sc.add_child(recipe_box)
	right.add_child(_label("Shift + Craft makes up to 5.   E or Esc to close.", 14, Color(0.7, 0.7, 0.7)))


func _make_slot(i: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(56, 56)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_constant_override("icon_max_width", 38)
	b.add_theme_stylebox_override("normal", style_slot)
	b.add_theme_stylebox_override("hover", style_sel)
	b.add_theme_stylebox_override("pressed", style_sel)
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.offset_right = -5
	l.offset_bottom = -2
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	b.add_child(l)
	b.pressed.connect(_on_slot.bind(i))
	if slot_btns.size() < 36:
		slot_btns.resize(36)
		slot_lbls.resize(36)
	slot_btns[i] = b
	slot_lbls[i] = l
	return b


func _on_slot(i: int) -> void:
	var p = G.player
	if i < 9:
		p.select(i)
	else:
		p.inv.swap(i, p.selected)
	G.sfx.play("click", -8.0)
	refresh_inventory()


func show_inventory(on: bool) -> void:
	inv_root.visible = on
	if on:
		refresh_inventory()


func refresh_inventory() -> void:
	if not inv_root.visible:
		return
	var p = G.player
	for i in 36:
		var s = p.inv.slots[i]
		var b: Button = slot_btns[i]
		var l: Label = slot_lbls[i]
		if s == null:
			b.icon = null
			l.text = ""
			b.tooltip_text = ""
		else:
			b.icon = G.tex.icon(int(s["id"]))
			l.text = str(s["n"]) if int(s["n"]) > 1 else ""
			b.tooltip_text = Items.name_of(int(s["id"]))
		b.add_theme_stylebox_override("normal", style_sel if i == p.selected else style_slot)
	var stations: Array = G.game.nearby_stations()
	if stations.is_empty():
		station_lbl.text = "Hand crafting only. Place a Workbench to unlock tools."
	else:
		var names := []
		for s in stations:
			names.append(Crafting.STATION_NAMES[s])
		station_lbl.text = "Nearby: " + ", ".join(names)
	for c in recipe_box.get_children():
		c.queue_free()
	var ready_list := []
	var rest := []
	for r in Crafting.RECIPES:
		if Crafting.can_craft(p.inv, r, stations):
			ready_list.append(r)
		else:
			rest.append(r)
	for r in ready_list + rest:
		recipe_box.add_child(_recipe_row(r, stations))


func _recipe_row(r: Dictionary, stations: Array) -> Control:
	var p = G.player
	var ok := Crafting.can_craft(p.inv, r, stations)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var ic := TextureRect.new()
	ic.texture = G.tex.icon(int(r["out"]))
	ic.custom_minimum_size = Vector2(38, 38)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(ic)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 0)
	row.add_child(vb)
	var n := int(r["n"])
	var nm := _label(Items.name_of(int(r["out"])) + (" x%d" % n if n > 1 else ""), 17, Color(1, 1, 1) if ok else Color(0.7, 0.7, 0.7))
	vb.add_child(nm)
	var parts := []
	var needs: Dictionary = r["needs"]
	for id in needs:
		parts.append("%d %s (have %d)" % [int(needs[id]), Items.name_of(int(id)), p.inv.count(int(id))])
	var req := ", ".join(parts)
	var st: String = r["st"]
	if st != "":
		req += "   ·   at " + Crafting.STATION_NAMES[st]
	var rl := _label(req, 13, Color(0.75, 0.78, 0.75) if ok else Color(1.0, 0.6, 0.55))
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rl.custom_minimum_size = Vector2(320, 0)
	vb.add_child(rl)
	var btn := Button.new()
	btn.text = "Craft"
	btn.disabled = not ok
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(84, 38)
	btn.pressed.connect(_on_craft.bind(r))
	row.add_child(btn)
	return row


func _on_craft(r: Dictionary) -> void:
	var p = G.player
	var times := 5 if Input.is_key_pressed(KEY_SHIFT) else 1
	var made := 0
	for k in times:
		if not Crafting.can_craft(p.inv, r, G.game.nearby_stations()):
			break
		if not Crafting.craft(p.inv, r):
			msg("Inventory full!", Color(1, 0.5, 0.4))
			break
		made += 1
	if made > 0:
		G.sfx.play("craft", -4.0)
		pickup("+%d %s" % [made * int(r["n"]), Items.name_of(int(r["out"]))])
		G.game.on_crafted(int(r["out"]))
	refresh_inventory()


# ------------------------------------------------------------ messages

func msg(text: String, col := Color(1, 1, 1)) -> void:
	msgs.append({"text": text, "col": col, "t": 0.0})
	if msgs.size() > 5:
		msgs.pop_front()


func pickup(text: String) -> void:
	pickups.append({"text": text, "t": 0.0})
	if pickups.size() > 6:
		pickups.pop_front()


func _process(delta: float) -> void:
	for m in msgs:
		m["t"] += delta
	msgs = msgs.filter(func(m): return m["t"] < 7.0)
	for m in pickups:
		m["t"] += delta
	pickups = pickups.filter(func(m): return m["t"] < 2.5)
	canvas.queue_redraw()


# ------------------------------------------------------------ drawing

func _text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	canvas.draw_string(font, pos + Vector2(2, 2), s, align, width, size, Color(0, 0, 0, col.a * 0.75))
	canvas.draw_string(font, pos, s, align, width, size, col)


func _bar(pos: Vector2, w: float, label: String, frac: float, col: Color) -> void:
	canvas.draw_rect(Rect2(pos, Vector2(w, 18)), Color(0, 0, 0, 0.55))
	canvas.draw_rect(Rect2(pos + Vector2(2, 2), Vector2((w - 4) * clampf(frac, 0, 1), 14)), col)
	_text(pos + Vector2(7, 14), label, 13, Color(1, 1, 1, 0.95))


func _draw_hud() -> void:
	if G.game == null:
		return
	var st: String = G.game.state
	if st == "loading" or st == "title":
		return
	var p = G.player
	var vs := canvas.size
	if p.hurt_flash > 0.0:
		canvas.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.6, 0.0, 0.0, 0.3 * p.hurt_flash))
	if p.health < 30.0 and not p.dead:
		var pulse := 0.08 + 0.06 * sin(Time.get_ticks_msec() * 0.006)
		canvas.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.5, 0.0, 0.0, pulse))

	var c := vs * 0.5
	if st == "playing":
		canvas.draw_rect(Rect2(c - Vector2(1, 9), Vector2(2, 18)), Color(1, 1, 1, 0.85))
		canvas.draw_rect(Rect2(c - Vector2(9, 1), Vector2(18, 2)), Color(1, 1, 1, 0.85))
		if p.mine_progress > 0.0:
			canvas.draw_rect(Rect2(c + Vector2(-32, 18), Vector2(64, 6)), Color(0, 0, 0, 0.6))
			canvas.draw_rect(Rect2(c + Vector2(-31, 19), Vector2(62 * clampf(p.mine_progress, 0, 1), 4)), Color(1, 1, 1, 0.9))

	# Hotbar
	var sz := 58.0
	var gap := 4.0
	var total := 9 * sz + 8 * gap
	var x0 := (vs.x - total) * 0.5
	var y0 := vs.y - sz - 16.0
	for i in 9:
		var r := Rect2(x0 + i * (sz + gap), y0, sz, sz)
		var sel: bool = i == p.selected
		canvas.draw_rect(r, Color(0, 0, 0, 0.55))
		canvas.draw_rect(r, Color(1, 1, 0.8, 0.95) if sel else Color(1, 1, 1, 0.22), false, 3.0 if sel else 1.0)
		var s = p.inv.slots[i]
		if s != null:
			canvas.draw_texture_rect(G.tex.icon(int(s["id"])), r.grow(-9), false)
			if int(s["n"]) > 1:
				_text(r.position + Vector2(0, sz - 6), str(s["n"]), 16, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT, sz - 5)
		_text(r.position + Vector2(4, 14), str(i + 1), 11, Color(1, 1, 1, 0.45))
	var cur: int = p.cur_id()
	if cur > 0:
		_text(Vector2(x0, y0 - 12), Items.name_of(cur), 18, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, total)

	# Vitals
	var bx := 20.0
	var by := vs.y - 34.0
	_bar(Vector2(bx, by - 48), 240, "HEALTH  %d" % int(ceilf(p.health)), p.health / p.max_health, Color(0.8, 0.18, 0.16))
	_bar(Vector2(bx, by - 24), 240, "FOOD  %d" % int(ceilf(p.food)), p.food / 100.0, Color(0.85, 0.55, 0.15))
	_bar(Vector2(bx, by), 240, "STAMINA", p.stamina / 100.0, Color(0.85, 0.8, 0.25))

	# Clock + horde countdown
	var g = G.game
	var hh := int(g.time)
	var mm := int((g.time - hh) * 60.0)
	_text(Vector2(20, 38), "DAY %d    %02d:%02d" % [g.day, hh, mm], 26, Color(1, 1, 1))
	var ht: String = g.horde_text()
	var hcol := Color(0.85, 0.85, 0.8)
	if g.horde_active:
		hcol = Color(1, 0.25, 0.2, 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.004)))
	elif g.days_until_horde() <= 1:
		hcol = Color(1, 0.55, 0.4)
	_text(Vector2(20, 64), ht, 18, hcol)
	if p.flashlight.visible:
		_text(Vector2(20, 88), "Flashlight on", 14, Color(1, 1, 0.8, 0.7))

	# Messages
	var my := 120.0
	for m in msgs:
		var a := 1.0 if m["t"] < 5.0 else maxf(0.0, 1.0 - (m["t"] - 5.0) / 2.0)
		var col: Color = m["col"]
		col.a = a
		_text(Vector2(0, my), m["text"], 22, col, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		my += 30.0
	var py := y0 - 44.0
	for i in range(pickups.size() - 1, -1, -1):
		var m = pickups[i]
		var a := 1.0 if m["t"] < 1.8 else maxf(0.0, 1.0 - (m["t"] - 1.8) / 0.7)
		_text(Vector2(vs.x - 260, py), m["text"], 18, Color(0.85, 1.0, 0.75, a))
		py -= 24.0
