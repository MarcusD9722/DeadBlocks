extends Control
## The Settings screen (title screen and pause menu): the graphics quality and each of its parts,
## brightness, light in caves, field of view, view distance, frame rate, window and mouse.
## Every change applies at once and is saved (gfx.gd, user://settings.cfg). Esc or Back closes it.

const Gfx := preload("res://scripts/gfx.gd")

var _rows := {}      # setting -> its control
var _values := {}    # setting -> the label showing a slider's value
var _busy := false   # filling the controls in; their signals are not the player's changes


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cc := CenterContainer.new()
	add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.1, 0.94)
	sb.border_color = Color(0.45, 0.2, 0.16)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	# Built before G.gfx exists when joining straight from the command line: names from the script.
	var g = Gfx
	_heading(grid, "Graphics")
	_choice(grid, "quality", "Quality", g.QUALITY_NAMES)
	_slider(grid, "brightness", "Brightness", 0, 100, 1, func(v): return "%d" % v)
	_slider(grid, "cave_light", "Light in caves and indoors", 0, 100, 1, func(v): return "%d" % v)
	_slider(grid, "view", "View distance", g.VIEW_MIN, g.VIEW_MAX, 1, func(v): return "%d m" % (v * 16))
	_slider(grid, "fov", "Field of view", 60, 110, 1, func(v): return "%d°" % v)
	_choice(grid, "shadows", "Shadows", g.SHADOW_NAMES)
	_check(grid, "ssao", "Ambient occlusion")
	_check(grid, "ssil", "Bounced light")
	_check(grid, "fog", "Volumetric fog")
	_choice(grid, "aa", "Anti-aliasing", g.AA_NAMES)
	_slider(grid, "render_scale", "Render scale", 50, 100, 5, func(v): return "%d%%" % v)
	_heading(grid, "Display")
	_choice(grid, "window", "Window", g.WINDOW_NAMES)
	_check(grid, "vsync", "V-Sync")
	var caps := []
	for c in g.FPS_CAPS:
		caps.append("Unlimited" if c == 0 else str(c))
	_choice(grid, "max_fps", "Frame rate limit", caps)
	_check(grid, "show_fps", "Show FPS")
	_heading(grid, "Controls")
	_slider(grid, "sens", "Mouse sensitivity", 0.5, 6.0, 0.1, func(v): return "%.1f" % v)
	var note := Label.new()
	note.text = "Render scale below 100% draws fewer pixels and sharpens them back up (faster)."
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.65, 0.68, 0.7))
	vb.add_child(note)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vb.add_child(row)
	row.add_child(_button("Reset to defaults", func():
		G.gfx.reset_settings()
		_fill()))
	row.add_child(_button("Back", close))


func open() -> void:
	if G.gfx == null:
		return
	_fill()
	visible = true


func close() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


## Show the current settings in the controls (a preset changes several at once).
func _fill() -> void:
	_busy = true
	var opt: Dictionary = G.gfx.opt
	for k in _rows:
		var c: Control = _rows[k]
		if c is OptionButton:
			c.select(Gfx.FPS_CAPS.find(opt[k]) if k == "max_fps" else int(opt[k]))
		elif c is CheckButton:
			c.set_pressed_no_signal(bool(opt[k]))
		elif c is HSlider:
			c.set_value_no_signal(opt[k])
			_values[k].text = _values[k].get_meta("fmt").call(opt[k])
	_busy = false


func _change(key: String, value) -> void:
	if _busy or G.gfx == null:
		return
	G.gfx.set_opt(key, value)
	if key == "quality" or Gfx.PRESETS[0].has(key):
		_fill()  # the preset's parts, or the quality now showing "Custom"


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	l.custom_minimum_size = Vector2(300, 0)
	return l


func _heading(grid: GridContainer, text: String) -> void:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.9, 0.45, 0.35))
	grid.add_child(l)
	grid.add_child(Control.new())


func _choice(grid: GridContainer, key: String, text: String, names: Array) -> void:
	grid.add_child(_label(text))
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.add_theme_font_size_override("font_size", 18)
	ob.custom_minimum_size = Vector2(300, 34)
	for n in names:
		ob.add_item(n)
	ob.item_selected.connect(func(i): _change(key, Gfx.FPS_CAPS[i] if key == "max_fps" else i))
	grid.add_child(ob)
	_rows[key] = ob


func _check(grid: GridContainer, key: String, text: String) -> void:
	grid.add_child(_label(text))
	var cb := CheckButton.new()
	cb.focus_mode = Control.FOCUS_NONE
	cb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cb.toggled.connect(func(on): _change(key, on))
	grid.add_child(cb)
	_rows[key] = cb


func _slider(grid: GridContainer, key: String, text: String, lo: float, hi: float, step: float, fmt: Callable) -> void:
	grid.add_child(_label(text))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.focus_mode = Control.FOCUS_NONE
	sl.custom_minimum_size = Vector2(230, 30)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := Label.new()
	val.custom_minimum_size = Vector2(70, 0)
	val.add_theme_font_size_override("font_size", 18)
	val.set_meta("fmt", fmt)
	# While dragging, applied when let go (view distance and render scale are costly to change
	# on every step); clicks and the mouse wheel apply at once.
	var apply := func(): _change(key, sl.value if step < 1.0 else int(sl.value))
	sl.value_changed.connect(func(v):
		val.text = fmt.call(v)
		if not sl.has_meta("dragging"):
			apply.call())
	sl.drag_started.connect(func(): sl.set_meta("dragging", true))
	sl.drag_ended.connect(func(_changed):
		sl.remove_meta("dragging")
		apply.call())
	hb.add_child(sl)
	hb.add_child(val)
	grid.add_child(hb)
	_rows[key] = sl
	_values[key] = val


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 42)
	b.add_theme_font_size_override("font_size", 19)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b
