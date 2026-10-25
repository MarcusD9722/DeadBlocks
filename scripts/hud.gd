extends CanvasLayer
## Heads-up display, inventory + crafting screen, title, pause and death screens.


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
var death_bed: Button
var death_random: Button
## M4.4: "Respawn at <tribe member>'s bed" buttons, and whose they are now.
var death_tribe: HBoxContainer
var _death_tribe_names := []
var title_menu: VBoxContainer
var solo_btn: Button
var join_panel: VBoxContainer
var host_panel: VBoxContainer
var solo_panel: VBoxContainer
var s_world: Label
var s_new: CheckBox
var title_info: Array = []
var f_addr: LineEdit
var f_name: LineEdit
var f_pin: LineEdit
var f_pw: LineEdit
var f_remember: CheckBox
var h_name: LineEdit
var h_pin: LineEdit
var h_pw: LineEdit
var h_port: LineEdit
var h_new: CheckBox
var h_world: Label
var pause_players: Label
var pause_quit: Button
var pause_leave: Button
var pause_respawn: Button
var chat_edit: LineEdit
var chat_log: Array = []
var _pause_refresh_t := 0.0
const CLIENT_CFG := "user://client.cfg"
var style_slot: StyleBoxFlat
var style_sel: StyleBoxFlat
## The Settings screen (settings_panel.gd), opened from the title screen and the pause menu.
var settings: Control
## The labels showing the keys (title and pause screens), refreshed after a key changes.
var ctl_labels: Array[Label] = []
## The station whose recipes the inventory screen shows ("" = hand crafting).
var inv_station := ""
var inv_help: Label
var inv_title: Label
## The right side of the inventory screen: crafting, or (M4.2) a storage box or bag.
var craft_panel: VBoxContainer
var box_panel: VBoxContainer
var box_title_lbl: Label
var box_btns: Array[Button] = []
var box_lbls: Array[Label] = []
## The box or bag shown (Vector3i.MIN: the screen shows crafting).
var box_at := Vector3i.MIN
## M4.4: the character screen's tabs (I: Inventory, M: Map; LB / RB on the controller).
const TABS := [["inventory", "Inventory"], ["armor", "Armor"], ["skills", "Skills"], ["map", "Map"], ["players", "Players"], ["tribe", "Tribe"]]
const PAGE_SIZE := Vector2(1080, 560)
var tab := "inventory"
var tab_bar: HBoxContainer
var tab_btns := {}
var tab_hint: Label
var pages := {}
var map_panel: Control
var map_pins_lbl: Label
var players_list: VBoxContainer
var players_head: Label
var tribe_box: VBoxContainer
## Below the tribe's list: the name field with "Found a tribe" or (the leader) "Rename", and
## "Leave the tribe".
var tribe_name_edit: LineEdit
var tribe_name_btn: Button
var tribe_leave_btn: Button
var _social_t := 0.0
## M4.5: the Skills tab (a card per perk: key -> {rank, next, btn}) and the Armor tab (the four
## worn slots, the armor in your bag, the character picture).
var skills_head: Label
var skills_bar: ProgressBar
var skill_cards := {}
var armor_btns: Array[Button] = []
var armor_lbls: Array[Label] = []
var armor_total_lbl: Label
var armor_bag: GridContainer
var armor_view: SubViewportContainer
var armor_preview: Node3D


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font
	_apply_theme()
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
	_build_chat()
	settings = preload("res://scripts/settings_panel.gd").new()
	add_child(settings)  # last, so it covers the title and pause screens
	slot_btns.resize(36)
	slot_lbls.resize(36)
	G.net.status.connect(_on_net_status)
	G.net.chat.connect(_on_chat)
	G.net.notice.connect(_on_notice)
	G.net.box_changed.connect(_on_box_changed)
	G.net.social_changed.connect(_on_social_changed)
	G.net.pins_changed.connect(_on_pins_changed)
	G.net.progress_changed.connect(_on_progress)
	G.net.armor_changed.connect(_refresh_armor)


func _style(bg: Color, border: Color, w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(w)
	s.set_corner_radius_all(6)
	return s


## M4.6: one look for every menu (the whole window's theme): dark rounded buttons and fields,
## with a warm edge on the one the controller (or the keyboard) is on.
func _apply_theme() -> void:
	var t := Theme.new()
	var box := func(bg: Color, border: Color, w: int) -> StyleBoxFlat:
		var sb := _style(bg, border, w)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 14.0
		sb.content_margin_right = 14.0
		sb.content_margin_top = 6.0
		sb.content_margin_bottom = 6.0
		sb.anti_aliasing = true
		return sb
	t.set_stylebox("normal", "Button", box.call(Color(0.19, 0.2, 0.23, 0.95), Color(1, 1, 1, 0.16), 1))
	t.set_stylebox("hover", "Button", box.call(Color(0.27, 0.28, 0.32, 0.97), Color(1, 1, 1, 0.3), 1))
	t.set_stylebox("pressed", "Button", box.call(Color(0.08, 0.09, 0.1, 0.95), Color(1, 0.85, 0.5, 0.6), 1))
	t.set_stylebox("hover_pressed", "Button", box.call(Color(0.1, 0.11, 0.12, 0.95), Color(1, 0.85, 0.5, 0.7), 1))
	t.set_stylebox("disabled", "Button", box.call(Color(0.1, 0.1, 0.11, 0.6), Color(1, 1, 1, 0.05), 1))
	var focus: StyleBoxFlat = box.call(Color(0, 0, 0, 0), Color(1, 0.84, 0.45, 0.95), 2)
	focus.draw_center = false
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", Color(0.92, 0.92, 0.88))
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_focus_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", Color(1, 0.9, 0.65))
	t.set_color("font_hover_pressed_color", "Button", Color(1, 0.9, 0.65))
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	t.set_stylebox("normal", "LineEdit", box.call(Color(0.07, 0.08, 0.09, 0.92), Color(1, 1, 1, 0.16), 1))
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_stylebox("read_only", "LineEdit", box.call(Color(0.07, 0.08, 0.09, 0.6), Color(1, 1, 1, 0.08), 1))
	t.set_stylebox("panel", "PanelContainer", box.call(Color(0.08, 0.09, 0.1, 0.9), Color(1, 1, 1, 0.08), 1))
	t.set_stylebox("panel", "Panel", box.call(Color(0.08, 0.09, 0.1, 0.9), Color(1, 1, 1, 0.08), 1))
	get_tree().root.theme = t


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
	b.focus_mode = Control.FOCUS_ALL  # (a controller moves between buttons)
	b.pressed.connect(cb)
	return b


## The keys, as the title and pause screens show them (they can be changed in Settings).
static func controls_text() -> String:
	var k := func(a: String) -> String: return Controls.key_name(Controls.key_of(a))
	return ("%s%s%s%s move   ·   %s jump   ·   %s sprint   ·   Mouse look\n" % [k.call("move_forward"), k.call("move_left"),
		k.call("move_back"), k.call("move_right"), k.call("jump"), k.call("sprint")]) + \
		("%s: mine / hit (hold to mine)   ·   %s: place, eat, use   ·   1-9 / wheel: hotbar\n" % [k.call("attack"), k.call("use")]) + \
		("%s: open workbench, forge, campfire, bag   ·   %s: inventory, players, tribe   ·   %s: map   ·   %s: flashlight\n" % [k.call("interact"),
		k.call("inventory"), k.call("map"), k.call("flashlight")]) + \
		"Esc: pause   ·   F11: fullscreen   ·   F6: skip to night/dawn (testing)   ·   F7: jump to Blood Moon (testing)\n" + \
		"Controller works too (see Settings → Controls)."


func refresh_controls_text() -> void:
	for l in ctl_labels:
		l.text = controls_text()


## Give the first visible button (or field) under root the focus, so a controller can start there.
func focus_first(root: Node) -> void:
	for c in root.find_children("*", "BaseButton", true, false) + root.find_children("*", "LineEdit", true, false):
		var ctl := c as Control
		if ctl.is_visible_in_tree() and ctl.focus_mode != Control.FOCUS_NONE and not (ctl is BaseButton and ctl.disabled):
			ctl.grab_focus.call_deferred()
			return


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
	var vb := _center(title_root)
	var t := _label("DEAD BLOCKS", 92, Color(0.85, 0.2, 0.15))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 12)
	vb.add_child(t)
	var sub := _label("Zombie Survival Craft   ·   Version %s (%s)" % [G.VERSION, G.BUILD_NAME], 24, Color(0.85, 0.85, 0.8))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	title_status = _label("", 22, Color(0.95, 0.95, 0.7))
	title_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_status.custom_minimum_size = Vector2(900, 0)
	vb.add_child(title_status)

	title_menu = VBoxContainer.new()
	title_menu.alignment = BoxContainer.ALIGNMENT_CENTER
	title_menu.add_theme_constant_override("separation", 10)
	vb.add_child(title_menu)
	solo_btn = _button("Play solo", func(): _show_panel(solo_panel))
	solo_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title_menu.add_child(solo_btn)
	for e in [["Host game", func(): _show_panel(host_panel)], ["Join server", func(): _show_panel(join_panel)], ["Settings", func(): settings.open()], ["Quit", func(): get_tree().quit()]]:
		var b := _button(e[0], e[1])
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		title_menu.add_child(b)

	solo_panel = _panel(vb, "PLAY SOLO")
	s_world = _label("", 18, Color(0.85, 0.95, 0.7))
	s_world.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	solo_panel.add_child(s_world)
	s_new = CheckBox.new()
	s_new.text = "Start a new world (the old one is kept in backups)"
	solo_panel.add_child(s_new)
	var snote := _label("Your world is saved on this PC. Esc pauses the game.", 15, Color(0.75, 0.78, 0.8))
	snote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	solo_panel.add_child(snote)
	_panel_buttons(solo_panel, "Play", _on_solo_pressed)

	join_panel = _panel(vb, "JOIN A SERVER")
	f_addr = _field(join_panel, "Server address", "e.g. 192.168.1.50 or myserver.duckdns.org", false)
	f_name = _field(join_panel, "Your name", "3-16 letters, digits or _", false)
	f_pin = _field(join_panel, "Your PIN", "4-8 digits; protects your name", true)
	f_pw = _field(join_panel, "Server password", "from the server owner", true)
	f_remember = CheckBox.new()
	f_remember.text = "Remember me on this PC"
	f_remember.button_pressed = true
	join_panel.add_child(f_remember)
	_panel_buttons(join_panel, "Join", _on_join_pressed)

	host_panel = _panel(vb, "HOST A GAME ON THIS PC")
	h_name = _field(host_panel, "Your name", "3-16 letters, digits or _", false)
	h_pin = _field(host_panel, "Your PIN", "4-8 digits; protects your name", true)
	h_pw = _field(host_panel, "Password for friends", "they type this to join (can be empty)", true)
	h_port = _field(host_panel, "Port", str(Proto.DEFAULT_PORT), false)
	h_world = _label("", 16, Color(0.85, 0.95, 0.7))
	h_world.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host_panel.add_child(h_world)
	h_new = CheckBox.new()
	h_new.text = "Start a new world (the old one is kept in backups)"
	host_panel.add_child(h_new)
	var lan := _lan_addresses()
	var note := _label("Friends on your home network join with %s.\nFor internet play, forward UDP port %d on your router to this PC.\nThe world is saved on this PC and continues next time you host." % [
		"this PC's address: " + ", ".join(lan) if not lan.is_empty() else "this PC's local address", Proto.DEFAULT_PORT], 15, Color(0.75, 0.78, 0.8))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host_panel.add_child(note)
	_panel_buttons(host_panel, "Host", _on_host_pressed)

	var how := _label("Gather. Craft. Build walls. Every night they come — every 7th night the horde comes.", 18, Color(0.8, 0.8, 0.8))
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(how)
	var ctl := _label(controls_text(), 16, Color(0.7, 0.72, 0.7))
	ctl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ctl)
	ctl_labels.append(ctl)
	title_info = [how, ctl]
	_load_client_cfg()
	if G.title_notice != "":
		_set_status(G.title_notice, true)
		G.title_notice = ""
	title_root.visible = true
	focus_first(title_menu)


## This PC's addresses on the home network (what friends in the same house type to join).
static func _lan_addresses() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or (a.begins_with("172.") and int(a.split(".")[1]) >= 16 and int(a.split(".")[1]) <= 31):
			out.append(a)
	return out


func _panel(parent: Control, heading: String) -> VBoxContainer:
	var p := VBoxContainer.new()
	p.add_theme_constant_override("separation", 8)
	p.visible = false
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(p)
	var h := _label(heading, 22, Color(0.85, 0.95, 0.7))
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(h)
	return p


func _field(parent: Control, text: String, hint: String, secret: bool) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := _label(text, 18)
	l.custom_minimum_size = Vector2(190, 0)
	row.add_child(l)
	var e := LineEdit.new()
	e.placeholder_text = hint
	e.secret = secret
	e.custom_minimum_size = Vector2(380, 36)
	e.add_theme_font_size_override("font_size", 18)
	row.add_child(e)
	return e


func _panel_buttons(panel: VBoxContainer, ok_text: String, ok: Callable) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var b := _button(ok_text, ok)
	b.custom_minimum_size = Vector2(180, 44)
	row.add_child(b)
	var back := _button("Back", func(): _show_panel(null))
	back.custom_minimum_size = Vector2(180, 44)
	row.add_child(back)


func _show_panel(p: Control) -> void:
	_set_status("", false)  # an old error doesn't belong to the next form
	if p == host_panel:
		_world_choice(G.HOST_WORLD, h_world, h_new)
	elif p == solo_panel:
		_world_choice(G.SOLO_WORLD, s_world, s_new)
	title_menu.visible = p == null
	join_panel.visible = p == join_panel
	host_panel.visible = p == host_panel
	solo_panel.visible = p == solo_panel
	focus_first(title_menu if p == null else p)


## "Your world continues: day 3, 14:20 (saved Oct 18, 21:05)", or that a new one will be made.
func _world_choice(world: String, label: Label, new_box: CheckBox) -> void:
	var info: Dictionary = G.world_info(world)
	new_box.button_pressed = false
	new_box.visible = not info.is_empty()
	if info.is_empty():
		label.text = "A new world will be made."
		return
	var t := float(info.get("time", 7.0))
	# Saved times are UTC; show them in this PC's time zone.
	var local := int(info.get("saved", 0)) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(local)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	label.text = "Your world continues: day %d, %02d:%02d (saved %s %d, %02d:%02d)" % [int(info.get("day", 1)), int(t),
		int((t - int(t)) * 60.0), months[int(d["month"]) - 1], int(d["day"]), int(d["hour"]), int(d["minute"])]


func _set_status(text: String, is_error: bool) -> void:
	title_status.text = text
	title_status.add_theme_color_override("font_color", Color(1, 0.55, 0.45) if is_error else Color(0.95, 0.95, 0.7))


func set_title_status(text: String) -> void:
	_set_status(text, false)


func _on_net_status(text: String, is_error: bool) -> void:
	if title_root.visible:
		_set_status(text, is_error)
	elif is_error:
		msg(text, Color(1, 0.55, 0.45))


func _on_join_pressed() -> void:
	var addr := f_addr.text.strip_edges()
	var pname := f_name.text.strip_edges()
	var pin := f_pin.text.strip_edges()
	if addr == "":
		_set_status("Type the server's address.", true)
		return
	if not Proto.valid_name(pname):
		_set_status("Names are 3-16 letters, digits or _ (no spaces).", true)
		return
	var cfg := ConfigFile.new()
	cfg.load(CLIENT_CFG)
	var same: bool = cfg.get_value("join", "address", "") == addr and str(cfg.get_value("join", "name", "")).to_lower() == pname.to_lower()
	var pin_k: PackedByteArray
	if pin == "" and same and cfg.has_section_key("join", "pin_key"):
		pin_k = Marshalls.base64_to_raw(cfg.get_value("join", "pin_key"))
	elif Proto.valid_pin(pin):
		pin_k = Proto.pin_key(pname, pin)
	else:
		_set_status("Your PIN must be 4-8 digits.", true)
		return
	var pw_k: PackedByteArray
	if f_pw.text == "" and same and cfg.has_section_key("join", "password_key"):
		pw_k = Marshalls.base64_to_raw(cfg.get_value("join", "password_key"))
	else:
		pw_k = Proto.password_key(f_pw.text)
	cfg.set_value("join", "address", addr)
	cfg.set_value("join", "name", pname)
	cfg.set_value("join", "remember", f_remember.button_pressed)
	if f_remember.button_pressed:
		# Only hashes are kept, never the PIN or password themselves.
		cfg.set_value("join", "pin_key", Marshalls.raw_to_base64(pin_k))
		cfg.set_value("join", "password_key", Marshalls.raw_to_base64(pw_k))
	else:
		for k in ["pin_key", "password_key"]:
			if cfg.has_section_key("join", k):
				cfg.erase_section_key("join", k)
	cfg.save(CLIENT_CFG)
	var hp := G.split_address(addr)
	G.join(hp[0], hp[1], pname, pin_k, pw_k)


func _on_host_pressed() -> void:
	var pname := h_name.text.strip_edges()
	var pin := h_pin.text.strip_edges()
	var port := Proto.DEFAULT_PORT
	if h_port.text.strip_edges() != "":
		port = int(h_port.text)
	if not Proto.valid_name(pname):
		_set_status("Names are 3-16 letters, digits or _ (no spaces).", true)
		return
	if not Proto.valid_pin(pin):
		_set_status("Your PIN must be 4-8 digits.", true)
		return
	if port < 1024 or port > 65535:
		_set_status("The port must be a number from 1024 to 65535.", true)
		return
	var cfg := ConfigFile.new()
	cfg.load(CLIENT_CFG)
	cfg.set_value("host", "name", pname)
	cfg.set_value("host", "port", port)
	cfg.save(CLIENT_CFG)
	_set_status("Starting the server...", false)
	var err: String = await G.host_game(pname, pin, h_pw.text, port, h_new.button_pressed)
	if err != "":
		_set_status(err, true)


func _on_solo_pressed() -> void:
	_set_status("Starting your world...", false)
	var err: String = await G.play_solo(s_new.button_pressed)
	if err != "":
		_set_status(err, true)


func _load_client_cfg() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CLIENT_CFG) != OK:
		return
	f_addr.text = cfg.get_value("join", "address", "")
	f_name.text = cfg.get_value("join", "name", "")
	f_remember.button_pressed = cfg.get_value("join", "remember", true)
	if cfg.has_section_key("join", "pin_key"):
		f_pin.placeholder_text = "saved (leave empty)"
	if cfg.has_section_key("join", "password_key"):
		f_pw.placeholder_text = "saved (leave empty)"
	h_name.text = cfg.get_value("host", "name", "")
	var hp = cfg.get_value("host", "port", Proto.DEFAULT_PORT)
	h_port.text = str(hp)


func set_loading(p: float) -> void:
	if G.mode == "client":
		_set_status("Loading %s...  %d%%" % ["your world" if G.solo else "the server's world", int(p * 100.0)], false)


## The title screen's own world is ready (nothing to do: Play solo starts its own server).
func show_ready() -> void:
	pass


## Client mode: just the logo and a loading line while the server's world is built.
func show_loading_overlay(on: bool) -> void:
	title_root.visible = on
	title_menu.visible = false
	join_panel.visible = false
	host_panel.visible = false
	for c in title_info:
		c.visible = false


func hide_title() -> void:
	title_root.visible = false


# ------------------------------------------------------------ chat

func _build_chat() -> void:
	chat_edit = LineEdit.new()
	chat_edit.visible = false
	chat_edit.placeholder_text = "Say something (Enter to send, Esc to cancel). /t message: your tribe only. Admins: /give planks 20, /dusk, /time 12"
	chat_edit.max_length = Proto.MAX_CHAT
	chat_edit.add_theme_font_size_override("font_size", 18)
	chat_edit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_edit.position = Vector2(20, -150)
	chat_edit.custom_minimum_size = Vector2(900, 36)
	add_child(chat_edit)
	chat_edit.text_submitted.connect(_on_chat_submit)
	chat_edit.gui_input.connect(_on_chat_key)


func open_chat() -> void:
	chat_edit.text = ""
	chat_edit.position = Vector2(20, canvas.size.y - 220)
	chat_edit.visible = true
	chat_edit.grab_focus()


func _close_chat() -> void:
	chat_edit.visible = false
	chat_edit.release_focus()
	G.game.close_chat()


func _on_chat_submit(text: String) -> void:
	G.net.send_chat(text)
	_close_chat()


func _on_chat_key(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		chat_edit.accept_event()
		_close_chat()


func _on_chat(from: String, text: String) -> void:
	_add_chat("<%s> %s" % [from, text], Color(1, 1, 1))


func _on_notice(text: String, col: Color) -> void:
	_add_chat(text, col)


func _add_chat(text: String, col: Color) -> void:
	chat_log.append({"text": text, "col": col, "t": 0.0})
	if chat_log.size() > 40:
		chat_log.pop_front()


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
	pause_respawn = _button("Die and Respawn", func(): G.game.kill_self())
	row.add_child(pause_respawn)
	pause_leave = _button("Leave Server", func(): G.end_client_session("Your world is saved." if G.solo else "You left the server."))
	row.add_child(pause_leave)
	row.add_child(_button("Settings", func(): settings.open()))
	pause_quit = _button("Quit Game", func(): get_tree().quit())
	row.add_child(pause_quit)
	pause_players = _label("", 18, Color(0.85, 0.95, 0.85))
	pause_players.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(pause_players)
	var ctl := _label(controls_text(), 16, Color(0.8, 0.82, 0.8))
	ctl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ctl)
	ctl_labels.append(ctl)
	seed_lbl = _label("", 14, Color(0.6, 0.6, 0.6))
	seed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(seed_lbl)


func show_pause(on: bool) -> void:
	pause_root.visible = on
	pause_respawn.visible = G.mode == "client"  # stuck somewhere? back to your spawn point
	var online := G.mode == "client" and not G.solo
	pause_leave.visible = G.mode == "client"
	pause_leave.text = "Save and Quit to Title" if G.solo else "Leave Server"
	pause_players.visible = online
	seed_lbl.text = "World seed: %d" % G.game.seed_v
	if online:
		seed_lbl.text += "   ·   The world keeps running while this menu is open."
	elif G.solo:
		seed_lbl.text += "   ·   Your world is saved on this PC."
	_refresh_pause_players()
	if on:
		refresh_controls_text()
		focus_first(pause_root)


## Online: who is playing, refreshed while the pause menu is open.
func _refresh_pause_players() -> void:
	if not pause_root.visible or G.mode != "client" or G.solo:
		return
	var names: Array = [G.net.player_name + " (you)"]
	for id in G.net.others:
		var o: Dictionary = G.net.others[id]
		var away: bool = not o["samples"].is_empty() and (int(o["samples"].back()[4]) & Proto.F_AWAY) != 0
		names.append(o["name"] + (" (away)" if away else ""))
	pause_players.text = "Online (%d):  %s\nServer %s:%d   ·   Ping %d ms" % [names.size(), ", ".join(names),
		G.net.host, G.net.port, G.net.ping_ms()]


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
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vb.add_child(row)
	death_bed = _button("Respawn at your bed", func(): G.game.respawn(true))
	row.add_child(death_bed)
	death_random = _button("Respawn somewhere random", func(): G.game.respawn(false))
	row.add_child(death_random)
	death_tribe = HBoxContainer.new()
	death_tribe.alignment = BoxContainer.ALIGNMENT_CENTER
	death_tribe.add_theme_constant_override("separation", 16)
	vb.add_child(death_tribe)


func show_death(on: bool) -> void:
	death_root.visible = on
	if on:
		_death_text()
		focus_first(death_root)


## The S_BACKPACKS for this death can arrive a moment after the death itself, so this is
## refreshed while the death screen shows.
func _death_text() -> void:
	var t := "You made it to Day %d   ·   Zombies killed: %d\n" % [G.game.day, G.game.kills]
	var packs: Array = G.net.my_backpacks if G.net != null else []
	if packs.is_empty():
		t += "You had nothing on you. Your base is where you left it."
	else:
		var mins := ceili(float(packs[packs.size() - 1][1]) / 60.0)
		t += "Everything you carried is in your backpack where you died.\nFollow the marker and get it back within %d minute%s. Anyone can pick it up!" % [mins, "" if mins == 1 else "s"]
	var has_bed: bool = G.mode == "client" and G.net.bed != Vector3i.MIN
	death_bed.visible = has_bed
	death_random.text = "Respawn somewhere random" if G.mode == "client" else "Respawn"
	if G.mode == "client" and not has_bed:
		t += "\n\nNo bed: you wake up somewhere random. Craft a Bed at a Workbench and place it to respawn there."
	death_lbl.text = t
	# Tribe members' beds (M4.4).
	var names := []
	if G.mode == "client":
		for e in G.net.social:
			if e["rel"] & Proto.R_TRIBE and e["rel"] & Proto.R_BED and names.size() < 4:
				names.append(e["name"])
	if names != _death_tribe_names:
		_death_tribe_names = names
		for c in death_tribe.get_children():
			c.queue_free()
		for nm in names:
			death_tribe.add_child(_button("Respawn at %s's bed" % nm, func(): G.game.respawn(true, nm)))


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
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	panel.add_child(main)
	tab_bar = HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 6)
	main.add_child(tab_bar)
	var tab_on := _style(Color(0.2, 0.25, 0.17, 1.0), Color(0.75, 0.9, 0.5), 2)
	var tab_off := _style(Color(0.13, 0.14, 0.15, 1.0), Color(0.28, 0.3, 0.3), 1)
	var tab_hover := _style(Color(0.18, 0.2, 0.2, 1.0), Color(0.5, 0.55, 0.5), 1)
	for t in TABS:
		var tb := Button.new()
		tb.text = t[1]
		tb.toggle_mode = true
		tb.focus_mode = Control.FOCUS_ALL
		tb.custom_minimum_size = Vector2(124, 40)
		tb.add_theme_font_size_override("font_size", 18)
		tb.add_theme_stylebox_override("normal", tab_off)
		tb.add_theme_stylebox_override("hover", tab_hover)
		tb.add_theme_stylebox_override("pressed", tab_on)
		tb.add_theme_stylebox_override("hover_pressed", tab_on)
		tb.add_theme_color_override("font_pressed_color", Color(0.9, 1, 0.75))
		tb.add_theme_color_override("font_hover_pressed_color", Color(0.9, 1, 0.75))
		tb.pressed.connect(show_tab.bind(t[0]))
		tab_bar.add_child(tb)
		tab_btns[t[0]] = tb
	tab_hint = _label("", 14, Color(0.7, 0.7, 0.7))
	tab_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tab_bar.add_child(tab_hint)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 28)
	hb.custom_minimum_size = PAGE_SIZE
	main.add_child(hb)
	pages["inventory"] = hb
	pages["armor"] = _build_armor_page()
	pages["skills"] = _build_skills_page()
	pages["map"] = _build_map_page()
	pages["players"] = _build_players_page()
	pages["tribe"] = _build_tribe_page()
	for k in ["armor", "skills", "map", "players", "tribe"]:
		pages[k].visible = false
		main.add_child(pages[k])

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
	var help := _label("Click a hotbar slot to select it. Click a backpack item\nto swap it into the selected hotbar slot (controller: A).", 14, Color(0.7, 0.7, 0.7))
	left.add_child(help)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	hb.add_child(right)
	craft_panel = right
	inv_title = _label("CRAFTING", 22, Color(0.85, 0.95, 0.7))
	right.add_child(inv_title)
	station_lbl = _label("", 14, Color(0.75, 0.8, 0.85))
	station_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	station_lbl.custom_minimum_size = Vector2(500, 0)
	right.add_child(station_lbl)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(500, 440)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(sc)
	var pad := MarginContainer.new()  # (room for the scroll bar beside the Craft buttons)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 16)
	sc.add_child(pad)
	recipe_box = VBoxContainer.new()
	recipe_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_box.add_theme_constant_override("separation", 6)
	pad.add_child(recipe_box)
	inv_help = _label("", 14, Color(0.7, 0.7, 0.7))
	right.add_child(inv_help)

	# A storage box or bag (M4.2): its slots; click one to take it, click your own to put it in.
	box_panel = VBoxContainer.new()
	box_panel.add_theme_constant_override("separation", 8)
	box_panel.custom_minimum_size = Vector2(500, 0)
	box_panel.visible = false
	hb.add_child(box_panel)
	box_title_lbl = _label("", 22, Color(0.85, 0.95, 0.7))
	box_panel.add_child(box_title_lbl)
	var bgrid := GridContainer.new()
	bgrid.columns = 9
	box_panel.add_child(bgrid)
	for i in 36:
		var b := _make_slot(-1 - i)
		bgrid.add_child(b)
	var take := _button("Take everything", func(): G.net.request_box(2, 0))
	take.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box_panel.add_child(take)
	var bhelp := _label("Click something in the box to take it, or something of yours to put it in.\n%s or Esc to close." % "E", 14, Color(0.7, 0.7, 0.7))
	bhelp.name = "BoxHelp"
	box_panel.add_child(bhelp)


## A slot-looking button (an icon in a square).
func _slot_button() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(56, 56)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_constant_override("icon_max_width", 38)
	b.add_theme_stylebox_override("normal", style_slot)
	b.add_theme_stylebox_override("hover", style_sel)
	b.add_theme_stylebox_override("pressed", style_sel)
	return b


func _make_slot(i: int) -> Button:
	var b := _slot_button()
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
	if i < 0:
		box_btns.append(b)  # (a box slot: -1 - its index)
		box_lbls.append(l)
		return b
	if slot_btns.size() < 36:
		slot_btns.resize(36)
		slot_lbls.resize(36)
	slot_btns[i] = b
	slot_lbls[i] = l
	return b


func _on_slot(i: int) -> void:
	var p = G.player
	if i < 0:
		G.net.request_box(0, -1 - i)  # take it out of the box
	elif box_at != Vector3i.MIN:
		G.net.request_box(1, i)  # put it in
	elif i < 9:
		p.select(i)
	else:
		G.net.request_swap(i, p.selected)
	G.sfx.play("click", -8.0)
	refresh_inventory()


## The box screen (M4.2): your inventory beside the storage box or bag at p, filled in when the
## server's S_BOX arrives.
func show_box(on: bool, p := Vector3i.MIN) -> void:
	box_at = p if on else Vector3i.MIN
	craft_panel.visible = not on
	box_panel.visible = on
	inv_root.visible = on
	tab_bar.visible = false
	_show_page("inventory")
	if on:
		box_title_lbl.text = "Opening..."
		for b in box_btns:
			b.visible = false
		(box_panel.get_node("BoxHelp") as Label).text = "Click something in the box to take it, or something of yours to put it in.\n%s or Esc to close." % Controls.key_name(Controls.key_of("interact"))
		refresh_inventory()
		slot_btns[G.player.selected].grab_focus.call_deferred()


## S_BOX arrived: show what the box holds (or close the screen if it is gone).
func _on_box_changed() -> void:
	if box_at == Vector3i.MIN or G.net.box_pos != box_at:
		return
	if not G.net.box_open:
		G.game.close_inventory()
		msg("It's gone.", Color(1, 0.8, 0.5))
		return
	box_title_lbl.text = G.net.box_title.to_upper()
	for i in box_btns.size():
		var b: Button = box_btns[i]
		b.visible = i < G.net.box_slots.size()
		if not b.visible:
			continue
		var st = G.net.box_slots[i]
		b.icon = null if st == null else G.tex.icon(int(st["id"]))
		box_lbls[i].text = "" if st == null or int(st["n"]) <= 1 else str(st["n"])
		b.tooltip_text = "" if st == null else Items.name_of(int(st["id"]))
	refresh_inventory()


## station: "" for your own inventory (hand crafting) with the character screen's tabs, or the
## station opened with E (no tabs).
func show_inventory(on: bool, station := "") -> void:
	inv_root.visible = on
	box_at = Vector3i.MIN
	craft_panel.visible = true
	box_panel.visible = false
	tab_bar.visible = station == ""
	_show_page("inventory")
	if on:
		inv_station = station
		inv_title.text = "HAND CRAFTING" if station == "" else Crafting.STATION_NAMES[station].to_upper()
		var close_key := Controls.key_of("inventory" if station == "" else "interact")
		inv_help.text = "Shift + Craft makes up to 5.   %s or Esc to close." % Controls.key_name(close_key)
		refresh_inventory()
		slot_btns[G.player.selected].grab_focus.call_deferred()


func refresh_inventory() -> void:
	if not inv_root.visible:
		return
	if has_tabs() and tab == "armor":
		_refresh_armor()  # (the armor in the bag)
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
	if box_at != Vector3i.MIN:
		return  # (the box screen has no recipes)
	var stations: Array = G.game.nearby_stations()
	if inv_station == "":
		station_lbl.text = "Look at a Workbench, Forge, Campfire or Blood Forge and press %s for what it makes." % Controls.key_name(Controls.key_of("interact"))
	elif stations.has(inv_station):
		station_lbl.text = {"workbench": "Stone, iron and steel tools and weapons, building blocks and the other stations.",
			"forge": "Smelting: ore and coal into ingots.", "campfire": "Cooking.",
			"bloodforge": "Blood Steel tools and weapons, and Blood Brick."}[inv_station]
	else:
		station_lbl.text = "The %s is gone." % Crafting.STATION_NAMES[inv_station]
	# The focused Craft button is rebuilt below: give the focus back to the same recipe's.
	var focus_recipe := -1
	var fo := get_viewport().gui_get_focus_owner()
	if fo != null and fo.has_meta("recipe"):
		focus_recipe = int(fo.get_meta("recipe"))
	for c in recipe_box.get_children():
		recipe_box.remove_child(c)
		c.queue_free()
	var ready_list := []
	var rest := []
	for r in Crafting.recipes_for(inv_station):
		if Crafting.can_craft(p.inv, r, stations):
			ready_list.append(r)
		else:
			rest.append(r)
	for r in ready_list + rest:
		var row := _recipe_row(r, stations)
		recipe_box.add_child(row)
		var btn: Button = row.get_child(row.get_child_count() - 1)
		if int(btn.get_meta("recipe")) == focus_recipe:
			btn.grab_focus.call_deferred()


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
	var rl := _label(req, 13, Color(0.75, 0.78, 0.75) if ok else Color(1.0, 0.6, 0.55))
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rl.custom_minimum_size = Vector2(320, 0)
	vb.add_child(rl)
	var btn := Button.new()
	btn.text = "Craft"
	btn.disabled = not ok
	btn.focus_mode = Control.FOCUS_ALL
	btn.custom_minimum_size = Vector2(84, 38)
	btn.set_meta("recipe", Crafting.RECIPES.find(r))
	btn.pressed.connect(_on_craft.bind(r))
	row.add_child(btn)
	return row


func _on_craft(r: Dictionary) -> void:
	var p = G.player
	var times := 5 if Input.is_key_pressed(KEY_SHIFT) else 1
	# The server crafts; "+N item" shows when its inventory update arrives.
	if Crafting.can_craft(p.inv, r, G.game.nearby_stations()):
		G.sfx.play("craft", -4.0)
		G.game.on_crafted(int(r["out"]))
	G.net.request_craft(Crafting.RECIPES.find(r), times)


# ------------------------------------------------------------ Skills and Armor (M4.5)

## Experience came in: "+N XP" with the pickups, and the Skills tab follows.
func _on_progress(gained: int) -> void:
	if gained > 0:
		pickup("+%d XP" % gained)
	if has_tabs() and tab == "skills":
		_refresh_skills()


func _build_skills_page() -> Control:
	var vb := _page("SKILLS")
	skills_head = _label("", 18, Color(1, 0.93, 0.6))
	vb.add_child(skills_head)
	skills_bar = ProgressBar.new()
	skills_bar.custom_minimum_size = Vector2(PAGE_SIZE.x, 14)
	skills_bar.show_percentage = false
	skills_bar.add_theme_stylebox_override("background", _style(Color(0.05, 0.05, 0.06), Color(0.3, 0.3, 0.3), 1))
	skills_bar.add_theme_stylebox_override("fill", _style(Color(0.85, 0.7, 0.25), Color(0.85, 0.7, 0.25), 0))
	vb.add_child(skills_bar)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(cols)
	var card_style := _style(Color(0.13, 0.14, 0.15, 1.0), Color(0.28, 0.3, 0.3), 1)
	card_style.set_content_margin_all(8)
	for br in Skills.BRANCHES:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(350, 0)
		col.add_theme_constant_override("separation", 8)
		cols.add_child(col)
		col.add_child(_label(br.to_upper(), 18, Color(0.85, 0.95, 0.7)))
		for pk in Skills.PERKS:
			if pk["branch"] != br:
				continue
			var card := PanelContainer.new()
			card.add_theme_stylebox_override("panel", card_style)
			col.add_child(card)
			var cv := VBoxContainer.new()
			cv.add_theme_constant_override("separation", 2)
			card.add_child(cv)
			var top := HBoxContainer.new()
			cv.add_child(top)
			var nm := _label(pk["name"], 17)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			top.add_child(nm)
			var rank := _label("", 17, Color(1, 0.85, 0.4))
			top.add_child(rank)
			var desc := _label("Each rank: " + pk["text"] + ".", 13, Color(0.78, 0.8, 0.78))
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc.custom_minimum_size = Vector2(330, 0)
			cv.add_child(desc)
			var row := HBoxContainer.new()
			cv.add_child(row)
			var nxt := _label("", 13, Color(0.7, 0.72, 0.7))
			nxt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(nxt)
			var id: int = pk["id"]
			var btn := _small_button("  Learn  ", func(): G.net.request_perk(id))
			btn.set_meta("key", "perk:%d" % id)
			row.add_child(btn)
			skill_cards[pk["key"]] = {"rank": rank, "next": nxt, "btn": btn}
	var foot := _label("Every level gives a skill point; levels and skills stay when you die. Experience comes from zombies (more from " +
		"Runners, Brutes, Screamers and Spitters, more at night, twice as much in a Blood Moon), boars, ore and upgrading blocks.", 13, Color(0.7, 0.7, 0.7))
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.custom_minimum_size = Vector2(PAGE_SIZE.x, 0)
	vb.add_child(foot)
	return vb


func _refresh_skills() -> void:
	var xp: int = G.net.xp
	var lv := Skills.level_of(xp)
	var pts := Skills.points(xp, G.net.perks)
	var into := xp - Skills.xp_for(lv)
	var step := Skills.xp_step(lv)
	if lv >= Skills.MAX_LEVEL:
		skills_head.text = "LEVEL %d (the highest)   ·   Skill points: %d" % [lv, pts]
		skills_bar.value = 100.0
	else:
		skills_head.text = "LEVEL %d   ·   %d / %d XP to level %d   ·   Skill points: %d" % [lv, into, step, lv + 1, pts]
		skills_bar.value = 100.0 * into / step
	for pk in Skills.PERKS:
		var c: Dictionary = skill_cards[pk["key"]]
		var r := int(G.net.perks.get(pk["key"], 0))
		var mx := int(pk["max"])
		(c["rank"] as Label).text = "●".repeat(r) + "○".repeat(mx - r)
		var why := Skills.cant_take(xp, G.net.perks, pk["key"])
		var btn: Button = c["btn"]
		btn.disabled = why != ""
		if r >= mx:
			(c["next"] as Label).text = "All ranks learned."
		elif Skills.level_of(xp) < Skills.RANK_LEVEL[r]:
			(c["next"] as Label).text = "Rank %d needs level %d." % [r + 1, Skills.RANK_LEVEL[r]]
		elif pts <= 0:
			(c["next"] as Label).text = "Rank %d: needs a skill point." % (r + 1)
		else:
			(c["next"] as Label).text = "Rank %d ready to learn." % (r + 1)


func _build_armor_page() -> Control:
	var hb := HBoxContainer.new()
	hb.custom_minimum_size = PAGE_SIZE
	hb.add_theme_constant_override("separation", 24)
	armor_view = SubViewportContainer.new()
	armor_view.stretch = true
	armor_view.custom_minimum_size = Vector2(300, 540)
	hb.add_child(armor_view)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 10)
	mid.custom_minimum_size = Vector2(360, 0)
	hb.add_child(mid)
	mid.add_child(_label("WORN", 22, Color(0.85, 0.95, 0.7)))
	for i in 4:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		mid.add_child(row)
		var b := _slot_button()
		b.pressed.connect(func(): G.net.request_equip(1, i))
		row.add_child(b)
		armor_btns.append(b)
		var l := _label("", 16)
		l.custom_minimum_size = Vector2(280, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		armor_lbls.append(l)
	armor_total_lbl = _label("", 17, Color(1, 0.93, 0.6))
	armor_total_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	armor_total_lbl.custom_minimum_size = Vector2(340, 0)
	mid.add_child(armor_total_lbl)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	hb.add_child(right)
	right.add_child(_label("ARMOR IN YOUR BAG", 22, Color(0.85, 0.95, 0.7)))
	armor_bag = GridContainer.new()
	armor_bag.columns = 6
	right.add_child(armor_bag)
	var help := _label("Click a piece to put it on, or a worn one to take it off. Right-click armor in your hand puts it on too.\n\n" +
		"Padded armor (plant fibre) is made by hand; leather (boar hide), iron and steel at a Workbench; Blood Steel at the Blood Forge. " +
		"Armor stops part of what zombies and acid do (not falls), and you keep it on when you die.", 13, Color(0.7, 0.7, 0.7))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(360, 0)
	right.add_child(help)
	return hb


func _refresh_armor() -> void:
	if armor_bag == null:
		return
	var worn: Array = G.net.armor
	for i in 4:
		var id := int(worn[i])
		armor_btns[i].icon = G.tex.icon(id) if id > 0 else null
		armor_btns[i].tooltip_text = Items.name_of(id) if id > 0 else ""
		armor_lbls[i].text = "%s:  %s" % [Items.ARMOR_SLOT_NAMES[i], "%s  (%.0f%%)" % [Items.name_of(id), Items.armor_def(id)] if id > 0 else "nothing"]
	armor_total_lbl.text = "Your armor stops %d%% of the damage zombies and acid do." % roundi(Items.armor_total(worn) * 100.0)
	# The bag's armor: rebuilt (it is short), keeping the focus on the same slot's button.
	var fo := get_viewport().gui_get_focus_owner()
	var focus_slot := int(fo.get_meta("inv_slot")) if fo != null and fo.has_meta("inv_slot") and armor_bag.is_ancestor_of(fo) else -1
	for c in armor_bag.get_children():
		armor_bag.remove_child(c)
		c.queue_free()
	var inv = G.player.inv
	for i in Inventory.SIZE:
		var id: int = inv.id_at(i)
		if Items.armor_slot(id) < 0:
			continue
		var b := _slot_button()
		b.icon = G.tex.icon(id)
		b.tooltip_text = "%s (%.0f%%)" % [Items.name_of(id), Items.armor_def(id)]
		b.set_meta("inv_slot", i)
		b.pressed.connect(func(): G.net.request_equip(0, i))
		armor_bag.add_child(b)
		if i == focus_slot:
			b.grab_focus.call_deferred()
	if armor_bag.get_child_count() == 0:
		armor_bag.add_child(_label("None yet.", 15, Color(0.7, 0.7, 0.7)))
	_dress_preview()


## The character picture on the Armor tab: our survivor (as other players see us) in our armor,
## turning slowly. Made the first time the tab shows.
func _dress_preview() -> void:
	if armor_view == null or G.game == null:
		return
	if armor_preview == null:
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.transparent_bg = true
		vp.msaa_3d = Viewport.MSAA_2X
		armor_view.add_child(vp)
		var cam := Camera3D.new()
		cam.fov = 34.0
		vp.add_child(cam)
		cam.position = Vector3(0, 1.25, 3.6)
		cam.look_at_from_position(cam.position, Vector3(0, 0.98, 0))
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(-0.6, 0.5, 0)
		vp.add_child(sun)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_CLEAR_COLOR
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.7, 0.7, 0.75)
		var sky := Sky.new()
		var sm := ProceduralSkyMaterial.new()
		sm.sky_top_color = Color(0.45, 0.55, 0.7)
		sm.ground_bottom_color = Color(0.25, 0.22, 0.2)
		sky.sky_material = sm
		e.sky = sky
		e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.environment = e
		vp.add_child(env)
		armor_preview = Node3D.new()
		vp.add_child(armor_preview)
		var who: String = G.game.RemotePlayerScript.SURVIVORS[G.net.my_net_id % G.game.RemotePlayerScript.SURVIVORS.size()]
		var rig := Rig.make("res://assets/models/survivors/Characters_%s_SingleWeapon.gltf" % who, Vector3.ONE * 1.25, [])
		if rig != null:
			armor_preview.add_child(rig)
			rig.strip_props()
			rig.move("Idle")
			armor_preview.set_meta("rig", rig)
	var r = armor_preview.get_meta("rig", null)
	if r != null:
		ArmorModels.dress(r, Proto.armor_tiers(Proto.armor_bits(G.net.armor)))


# ------------------------------------------------------------ the character screen's tabs (M4.4)

## The tabs show (I or M); not for a station's or a box's screen.
func has_tabs() -> bool:
	return inv_root.visible and tab_bar.visible


func show_tab(t: String) -> void:
	if not has_tabs():
		return
	_show_page(t)
	match t:
		"inventory":
			refresh_inventory()
			slot_btns[G.player.selected].grab_focus.call_deferred()
		"armor":
			_refresh_armor()
			focus_first(pages[t])
		"skills":
			_refresh_skills()
			focus_first(pages[t])
		"map":
			map_panel.opened()
			_on_pins_changed()
		"players", "tribe":
			G.net.request_social(Proto.SOC_REFRESH)
			_on_social_changed()
			focus_first(pages[t])


## LB / RB: the tab before or after this one.
func next_tab(d: int) -> void:
	var i := 0
	for j in TABS.size():
		if TABS[j][0] == tab:
			i = j
	show_tab(TABS[(i + d + TABS.size()) % TABS.size()][0])


func _show_page(t: String) -> void:
	tab = t
	for k in pages:
		pages[k].visible = k == t
		(tab_btns[k] as Button).set_pressed_no_signal(k == t)
	tab_hint.text = ("LB / RB: switch tabs" if Controls.pad_in_use else "%s inventory   ·   %s map   ·   Esc closes" % [
		Controls.key_name(Controls.key_of("inventory")), Controls.key_name(Controls.key_of("map"))])


func _page(heading: String) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = PAGE_SIZE
	vb.add_theme_constant_override("separation", 8)
	if heading != "":
		vb.add_child(_label(heading, 22, Color(0.85, 0.95, 0.7)))
	return vb


func _small_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(cb)
	return b


func _build_map_page() -> Control:
	var vb := _page("")
	map_panel = preload("res://scripts/map_panel.gd").new()
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.custom_minimum_size = Vector2(PAGE_SIZE.x, 480)
	vb.add_child(map_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	row.add_child(_small_button("  Center on me  ", func(): map_panel.center_on_me()))
	var help := _label("Drag to move   ·   Wheel to zoom   ·   Right-click: add a pin, or remove the one under it\n" +
		"Controller: left stick moves, triggers zoom, A adds a pin in the middle, X removes it, right stick centers", 13, Color(0.7, 0.7, 0.7))
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(help)
	map_pins_lbl = _label("", 14, Color(1, 0.7, 0.6))
	row.add_child(map_pins_lbl)
	return vb


func _on_pins_changed() -> void:
	if map_pins_lbl != null:
		map_pins_lbl.text = "Pins: %d / %d" % [G.net.pins.size(), Proto.MAX_PINS]


func _build_players_page() -> Control:
	var vb := _page("PLAYERS")
	players_head = _label("", 14, Color(0.75, 0.8, 0.85))
	players_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(players_head)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	players_list = VBoxContainer.new()
	players_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_list.add_theme_constant_override("separation", 6)
	sc.add_child(players_list)
	return vb


func _build_tribe_page() -> Control:
	var vb := _page("TRIBE")
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	tribe_box = VBoxContainer.new()
	tribe_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tribe_box.add_theme_constant_override("separation", 8)
	sc.add_child(tribe_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	tribe_name_edit = LineEdit.new()
	tribe_name_edit.custom_minimum_size = Vector2(300, 36)
	tribe_name_edit.max_length = 24
	tribe_name_edit.add_theme_font_size_override("font_size", 17)
	tribe_name_edit.text_submitted.connect(func(_t): _tribe_name_pressed())
	row.add_child(tribe_name_edit)
	tribe_name_btn = _small_button("", _tribe_name_pressed)
	row.add_child(tribe_name_btn)
	tribe_leave_btn = _small_button("  Leave the tribe  ", func(): G.net.request_social(Proto.SOC_LEAVE))
	row.add_child(tribe_leave_btn)
	return vb


## The name field's button: found a tribe with that name, or (its leader) rename it.
func _tribe_name_pressed() -> void:
	var nm := tribe_name_edit.text.strip_edges()
	if nm == "":
		return
	G.net.request_social(Proto.SOC_FOUND if G.net.tribe.is_empty() else Proto.SOC_RENAME, "", nm)
	tribe_name_edit.text = ""


func _on_social_changed() -> void:
	if not has_tabs():
		return
	if tab == "players":
		_refresh_players()
	elif tab == "tribe":
		_refresh_tribe()


## What a relation looks like in the lists.
static func _status_text(e: Dictionary) -> String:
	var rel: int = e["rel"]
	if rel & Proto.R_ONLINE:
		return "Online   ·   %d ms" % int(e["ping"])
	if rel & Proto.R_AWAY:
		return "Away (their character is still here)"
	return "Offline"


## Empty a list before it is rebuilt, remembering which of its buttons had the focus so
## _refocus can give it back.
func _clear(box: Container) -> void:
	var fo := get_viewport().gui_get_focus_owner()
	var key := ""
	if fo != null and box.is_ancestor_of(fo):
		key = str(fo.get_meta("key", ""))
	box.set_meta("refocus", key)
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _refocus(box: Container) -> void:
	var key: String = box.get_meta("refocus", "")
	box.set_meta("refocus", "")
	if key == "":
		return
	for b in box.find_children("*", "BaseButton", true, false):
		if b.get_meta("key", "") == key:
			(b as Control).grab_focus.call_deferred()
			return
	focus_first(box)


func _row(box: Container, cells: Array, buttons: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for c in cells:
		var l := _label(c[0], c[2] if c.size() > 2 else 17, c[1])
		l.custom_minimum_size = Vector2(c[3] if c.size() > 3 else 230, 0)
		l.clip_text = true
		row.add_child(l)
	for b in buttons:
		var btn := _small_button("  %s  " % b[0], b[1])
		btn.set_meta("key", b[2])
		row.add_child(btn)
	box.add_child(row)


func _refresh_players() -> void:
	_clear(players_list)
	var n := 1
	for e in G.net.social:
		if e["rel"] & (Proto.R_ONLINE | Proto.R_AWAY):
			n += 1
	players_head.text = ("%d playing on %s:%d.   " % [n, G.net.host, G.net.port] if not G.solo else "Play solo: nobody else is here.   ") + \
		"Allies see each other on the map and on screen (with the distance), and their names show through walls. Tribe members are allies too."
	_row(players_list, [[G.net.player_name + " (you)", Color(1, 1, 0.85)], ["Online   ·   %d ms" % maxi(0, G.net.ping_ms()), Color(0.75, 0.8, 0.75), 15, 260],
		[("Tribe: " + G.net.tribe["name"]) if not G.net.tribe.is_empty() else "", Color(0.6, 1, 0.65), 15, 300]], [])
	for e in G.net.social:
		var rel: int = e["rel"]
		var nm: String = e["name"]
		var what := ""
		var col := Color(1, 1, 1)
		var btns := []
		if rel & Proto.R_TRIBE:
			what = "Tribe member"
			col = Color(0.6, 1, 0.65)
		elif rel & Proto.R_ALLY:
			what = "Ally"
			col = Color(0.6, 0.85, 1)
			btns.append(["Remove ally", func(): G.net.request_social(Proto.SOC_REMOVE, nm), "rm:" + nm])
		elif rel & Proto.R_ASKS_YOU:
			what = "Wants to be your ally"
			col = Color(1, 0.95, 0.6)
			btns.append(["Accept", func(): G.net.request_social(Proto.SOC_ACCEPT, nm), "ok:" + nm])
			btns.append(["Decline", func(): G.net.request_social(Proto.SOC_DECLINE, nm), "no:" + nm])
		elif rel & Proto.R_ASKED:
			what = "Ally request sent"
			col = Color(0.8, 0.8, 0.8)
		elif rel & Proto.R_ONLINE:
			btns.append(["Ask to be allies", func(): G.net.request_social(Proto.SOC_ASK, nm), "ask:" + nm])
		if not G.net.tribe.is_empty() and rel & Proto.R_ONLINE and not rel & Proto.R_IN_TRIBE:
			btns.append(["Invite to tribe", func(): G.net.request_social(Proto.SOC_INVITE, nm), "inv:" + nm])
		_row(players_list, [[nm, col], [_status_text(e), Color(0.75, 0.8, 0.75), 15, 260], [what, col, 15, 200]], btns)
	_refocus(players_list)


func _refresh_tribe() -> void:
	_clear(tribe_box)
	var t: Dictionary = G.net.tribe
	if t.is_empty():
		var intro := _label("You are not in a tribe. Found one and invite your friends from the Players tab:\n" +
			"tribe members are allies, have their own chat (type /t and a message) and can respawn at each other's beds.", 16, Color(0.85, 0.88, 0.85))
		tribe_box.add_child(intro)
		tribe_name_edit.visible = true
		tribe_name_edit.placeholder_text = "Tribe name (3-24 letters)"
		tribe_name_btn.visible = true
		tribe_name_btn.text = "  Found a tribe  "
		tribe_leave_btn.visible = false
		if not G.net.invites.is_empty():
			tribe_box.add_child(_label("INVITATIONS", 18, Color(0.85, 0.95, 0.7)))
		for inv in G.net.invites:
			var tid := str(inv["id"])
			_row(tribe_box, [["%s invites you to %s" % [inv["from"], inv["name"]], Color(0.6, 1, 0.65), 17, 520]],
				[["Join", func(): G.net.request_social(Proto.SOC_JOIN, "", tid), "join:" + tid],
				["No thanks", func(): G.net.request_social(Proto.SOC_REFUSE, "", tid), "refuse:" + tid]])
		_refocus(tribe_box)
		return
	var lead: bool = t["leader"] == G.net.player_name
	tribe_box.add_child(_label(str(t["name"]).to_upper(), 26, Color(0.6, 1, 0.65)))
	tribe_box.add_child(_label("Leader: %s   ·   Tribe chat: type /t and a message   ·   Invite players from the Players tab" % t["leader"], 15, Color(0.8, 0.85, 0.8)))
	tribe_box.add_child(_label("MEMBERS", 18, Color(0.85, 0.95, 0.7)))
	_row(tribe_box, [[G.net.player_name + " (you)", Color(1, 1, 0.85)], ["Leader" if lead else "", Color(0.75, 0.8, 0.75), 15, 260],
		["Has a bed" if G.net.bed != Vector3i.MIN else "No bed", Color(0.75, 0.8, 0.75), 15, 200]], [])
	for e in G.net.social:
		var rel: int = e["rel"]
		if not rel & Proto.R_TRIBE:
			continue
		var nm: String = e["name"]
		var btns := []
		if lead:
			btns.append(["Make leader", func(): G.net.request_social(Proto.SOC_LEAD, nm), "lead:" + nm])
			btns.append(["Remove", func(): G.net.request_social(Proto.SOC_KICK, nm), "kick:" + nm])
		_row(tribe_box, [[nm, Color(0.6, 1, 0.65)], [("Leader   ·   " if nm == t["leader"] else "") + _status_text(e), Color(0.75, 0.8, 0.75), 15, 260],
			["Has a bed" if rel & Proto.R_BED else "No bed", Color(0.75, 0.8, 0.75), 15, 200]], btns)
	tribe_name_edit.visible = lead
	tribe_name_edit.placeholder_text = "A new name for the tribe"
	tribe_name_btn.visible = lead
	tribe_name_btn.text = "  Rename  "
	tribe_leave_btn.visible = true
	_refocus(tribe_box)


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
	for m in chat_log:
		m["t"] += delta
	_pause_refresh_t -= delta
	if _pause_refresh_t <= 0.0:
		_pause_refresh_t = 1.0
		_refresh_pause_players()
		if death_root.visible:
			_death_text()
	if has_tabs() and tab == "armor" and armor_preview != null:
		armor_preview.rotation.y += delta * 0.6
		var r = armor_preview.get_meta("rig", null)
		if r != null:
			r.tick(delta)
	if has_tabs() and tab == "players":
		# Pings: ask the server again every few seconds while the list shows.
		_social_t -= delta
		if _social_t <= 0.0:
			_social_t = 3.0
			G.net.request_social(Proto.SOC_REFRESH)
	canvas.queue_redraw()


# ------------------------------------------------------------ drawing

func _text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	canvas.draw_string(font, pos + Vector2(2, 2), s, align, width, size, Color(0, 0, 0, col.a * 0.75))
	canvas.draw_string(font, pos, s, align, width, size, col)


## A rounded box on the HUD (cached style boxes: the HUD redraws every frame).
var _boxes := {}

func _rbox(r: Rect2, bg: Color, radius := 8, border := Color(0, 0, 0, 0), bw := 0) -> void:
	var key := "%s|%d|%s|%d" % [bg, radius, border, bw]
	var sb: StyleBoxFlat = _boxes.get(key)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(radius)
		sb.border_color = border
		sb.set_border_width_all(bw)
		sb.anti_aliasing = true
		_boxes[key] = sb
	canvas.draw_style_box(sb, r)


## A vital as a slim rounded bar with its icon (M4.6): `icon` heart, food or stamina.
func _bar(pos: Vector2, w: float, icon: String, value: String, frac: float, col: Color) -> void:
	_icon(pos + Vector2(9, 8), icon, col)
	var r := Rect2(pos + Vector2(24, 2), Vector2(w - 24, 12))
	_rbox(r, Color(0, 0, 0, 0.45), 6)
	if frac > 0.0:
		_rbox(Rect2(r.position + Vector2(2, 2), Vector2(maxf((r.size.x - 4) * clampf(frac, 0, 1), 8.0), 8)), col, 4)
	if value != "":
		_text(Vector2(pos.x + w + 8, pos.y + 13), value, 14, Color(1, 1, 1, 0.85))


## The little pictures beside the vitals, drawn from shapes.
func _icon(c: Vector2, kind: String, col: Color) -> void:
	match kind:
		"heart":
			canvas.draw_circle(c + Vector2(-3, -2), 3.6, col)
			canvas.draw_circle(c + Vector2(3, -2), 3.6, col)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-6.4, -0.8), c + Vector2(6.4, -0.8), c + Vector2(0, 6.5)]), col)
		"food":
			canvas.draw_line(c + Vector2(-6, 5), c + Vector2(-1, 0), Color(0.95, 0.92, 0.85), 2.4)
			canvas.draw_circle(c + Vector2(-6.5, 5.5), 1.8, Color(0.95, 0.92, 0.85))
			canvas.draw_circle(c + Vector2(2, -2), 5.0, col)
		_:
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(1.5, -7), c + Vector2(-5, 1), c + Vector2(-0.5, 1),
				c + Vector2(-2, 7), c + Vector2(5, -1.5), c + Vector2(0.5, -1.5)]), col)


## Our own backpacks: an icon with the distance and the time left, over the pack (at the side of
## the screen when it's behind us).
func _draw_backpack_markers(vs: Vector2) -> void:
	var cam: Camera3D = G.player.cam
	for e in G.net.my_backpacks:
		var wp := Vector3(e[0]) + Vector3(0.5, 1.2, 0.5)
		var dist: float = G.player.global_position.distance_to(wp)
		var at := _marker_at(cam, wp, vs)
		var left := int(e[1])
		var col := Color(1, 0.88, 0.45) if left > 60 else Color(1, 0.45, 0.35)
		canvas.draw_texture_rect(G.tex.icon(Blocks.BACKPACK), Rect2(at - Vector2(14, 30), Vector2(28, 28)), false)
		@warning_ignore("integer_division")
		var mins := left / 60
		_text(at + Vector2(-70, 14), "%d m  ·  %d:%02d" % [int(dist), mins, left % 60], 15, col, HORIZONTAL_ALIGNMENT_CENTER, 140)


## Where a marker for a point in the world goes: over it, kept on the screen, or at the side
## of the screen when it is behind us.
func _marker_at(cam: Camera3D, wp: Vector3, vs: Vector2) -> Vector2:
	if cam.is_position_behind(wp):
		var local: Vector3 = cam.global_transform.affine_inverse() * wp
		return Vector2(40.0 if local.x < 0.0 else vs.x - 40.0, vs.y * 0.45)
	return cam.unproject_position(wp).clamp(Vector2(40, 70), vs - Vector2(40, 130))


## M4.4: allies (blue) and tribe members (green) further than a few metres away, with the
## distance, and our map pins (smaller, without a height).
func _draw_waypoints(vs: Vector2) -> void:
	var cam: Camera3D = G.player.cam
	var me: Vector3 = G.player.global_position
	for e in G.net.social:
		var rel: int = e["rel"]
		if rel & Proto.R_ALLY == 0 or e["id"] == 0:
			continue
		var smp: Dictionary = G.net.interpolated(e["id"])
		if smp.is_empty():
			continue
		var pos: Vector3 = smp["pos"]
		var dist := me.distance_to(pos)
		if dist < 8.0:
			continue  # (close by, the name tag is enough)
		var col := Color(0.45, 1, 0.55) if rel & Proto.R_TRIBE else Color(0.5, 0.78, 1)
		if rel & Proto.R_AWAY:
			col.a = 0.55
		var at := _marker_at(cam, pos + Vector3(0, 2.0, 0), vs)
		canvas.draw_circle(at, 7.0, Color(0, 0, 0, 0.6 * col.a))
		canvas.draw_circle(at, 5.0, col)
		_text(at + Vector2(-90, -12), e["name"], 15, col, HORIZONTAL_ALIGNMENT_CENTER, 180)
		_text(at + Vector2(-90, 24), "%d m" % int(dist), 14, col, HORIZONTAL_ALIGNMENT_CENTER, 180)
	for p in G.net.pins:
		var flat := Vector2(p["x"] + 0.5 - me.x, p["z"] + 0.5 - me.z).length()
		if flat < 4.0 or flat > 2000.0:
			continue
		var at := _marker_at(cam, Vector3(p["x"] + 0.5, me.y + 1.6, p["z"] + 0.5), vs)
		var col := Color(1, 0.55, 0.45, 0.85)
		canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -6), at + Vector2(6, 0), at + Vector2(0, 6), at + Vector2(-6, 0)]), col)
		_text(at + Vector2(-90, -10), "%s  ·  %d m" % [p["name"], int(flat)], 13, col, HORIZONTAL_ALIGNMENT_CENTER, 180)


## Ranged weapons (M4.3): a mark on the crosshair when a shot hits (red in the head or for a
## kill), the ammo left, and a bar while the bow is drawn, a spear held back or the crossbow
## reloading.
func _draw_ranged(p, c: Vector2, vs: Vector2) -> void:
	if p.hit_mark > 0.0:
		var a := clampf(p.hit_mark / 0.35, 0.0, 1.0)
		var hc := Color(1, 1, 1, a) if p.hit_kind == Proto.HIT_MOB else Color(1, 0.25, 0.2, a)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				canvas.draw_line(c + Vector2(sx, sy) * 7.0, c + Vector2(sx, sy) * 14.0, hc, 2.5)
	var cur: int = p.cur_id()
	var tt := Items.tool_type(cur)
	var bar := -1.0
	if tt == "bow" or tt == "crossbow":
		var slot := Items.ammo_slot(p.inv, cur)
		var txt := "No arrows" if tt == "bow" else "No bolts"
		if slot >= 0:
			var ammo: int = p.inv.id_at(slot)
			txt = "%d %s" % [p.inv.count(ammo), Items.name_of(ammo)]
		_text(Vector2(0, c.y + 74), txt, 16, Color(1, 1, 1, 0.85) if slot >= 0 else Color(1, 0.6, 0.5, 0.9), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		if tt == "bow" and p.draw > 0.0:
			bar = p.draw
		elif tt == "crossbow" and not p.xbow_loaded and slot >= 0:
			bar = 1.0 - clampf(p.xbow_t / Items.CROSSBOW_RELOAD_S, 0.0, 1.0)
	elif tt == "spear" and p.charge > 0.0:
		bar = p.charge
	if bar >= 0.0:
		var full := bar >= 0.999
		canvas.draw_rect(Rect2(c + Vector2(-32, 18), Vector2(64, 6)), Color(0, 0, 0, 0.6))
		canvas.draw_rect(Rect2(c + Vector2(-31, 19), Vector2(62 * bar, 4)), Color(1, 0.85, 0.4, 0.95) if full else Color(1, 1, 1, 0.9))


func _draw_hud() -> void:
	if G.game == null or G.player == null:
		return
	var st: String = G.game.state
	if st == "loading" or st == "title" or st == "connecting":
		return
	var p = G.player
	var vs := canvas.size
	if G.gfx != null and G.gfx.opt["show_fps"]:
		_text(Vector2(vs.x - 130, 28), "%d FPS" % Engine.get_frames_per_second(), 18, Color(0.85, 1.0, 0.7))
	if p.hurt_flash > 0.0:
		canvas.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.6, 0.0, 0.0, 0.3 * p.hurt_flash))
	if p.health < 30.0 and not p.dead:
		var pulse := 0.08 + 0.06 * sin(Time.get_ticks_msec() * 0.006)
		canvas.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.5, 0.0, 0.0, pulse))

	var c := vs * 0.5
	if st == "playing" and not G.world.is_ready_at(p.global_position):
		# Just respawned far away (or teleported): the land is still loading.
		canvas.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.06, 0.08, 0.85))
		_text(Vector2(0, c.y), "Finding your way...", 30, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if st == "playing":
		canvas.draw_rect(Rect2(c - Vector2(1, 9), Vector2(2, 18)), Color(1, 1, 1, 0.85))
		canvas.draw_rect(Rect2(c - Vector2(9, 1), Vector2(18, 2)), Color(1, 1, 1, 0.85))
		var it: String = p.interact_text()
		if it != "":
			var key := "X" if Controls.pad_in_use else Controls.key_name(Controls.key_of("interact"))
			_text(Vector2(0, c.y + 50), "[%s]  %s" % [key, it], 18, Color(1, 1, 0.85, 0.95), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		var ht: Array = p.hammer_text()
		if ht[0] != "":
			# Holding a hammer: what holding the button on this block does, and its cost.
			_text(Vector2(0, c.y + 74), ht[0], 17, Color(0.75, 1, 0.75, 0.95) if ht[1] else Color(1, 0.7, 0.5, 0.95), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		if p.mine_progress > 0.0:
			canvas.draw_rect(Rect2(c + Vector2(-32, 18), Vector2(64, 6)), Color(0, 0, 0, 0.6))
			canvas.draw_rect(Rect2(c + Vector2(-31, 19), Vector2(62 * clampf(p.mine_progress, 0, 1), 4)), Color(1, 1, 1, 0.9))
		_draw_ranged(p, c, vs)

	if G.net != null and not G.net.my_backpacks.is_empty() and not p.dead:
		_draw_backpack_markers(vs)
	if G.mode == "client" and st == "playing":
		_draw_waypoints(vs)

	# Hotbar (M4.6: rounded slots on a soft strip; the one in hand stands up a little)
	var sz := 56.0
	var gap := 6.0
	var total := 9 * sz + 8 * gap
	var x0 := (vs.x - total) * 0.5
	var y0 := vs.y - sz - 16.0
	_rbox(Rect2(x0 - 8, y0 - 6, total + 16, sz + 14), Color(0, 0, 0, 0.22), 14)
	for i in 9:
		var sel: bool = i == p.selected
		var r := Rect2(x0 + i * (sz + gap), y0 - (4.0 if sel else 0.0), sz, sz)
		if sel:
			_rbox(r, Color(0.22, 0.2, 0.15, 0.78), 10, Color(1, 0.85, 0.5, 0.95), 2)
		else:
			_rbox(r, Color(0.05, 0.06, 0.07, 0.55), 10, Color(1, 1, 1, 0.1), 1)
		var s = p.inv.slots[i]
		if s != null:
			canvas.draw_texture_rect(G.tex.icon(int(s["id"])), r.grow(-6 if sel else -8), false)
			if int(s["n"]) > 1:
				_text(r.position + Vector2(0, sz - 6), str(s["n"]), 15, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT, sz - 6)
		_text(r.position + Vector2(6, 15), str(i + 1), 11, Color(1, 1, 1, 0.75 if sel else 0.4))
	var cur: int = p.cur_id()
	if cur > 0:
		_text(Vector2(x0, y0 - 26), Items.name_of(cur), 18, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, total)
	if G.mode == "client" or G.has_arg("--scenery"):
		_draw_xp(x0, y0, total)

	# Vitals (M4.6: slim bars with their icons on a soft panel, bottom left)
	var bx := 22.0
	var by := vs.y - 34.0
	_rbox(Rect2(bx - 10, by - 58, 300, 82), Color(0, 0, 0, 0.22), 12)
	_bar(Vector2(bx, by - 48), 240, "heart", str(int(ceilf(p.health))), p.health / p.max_health, Color(0.86, 0.22, 0.2))
	_bar(Vector2(bx, by - 24), 240, "food", str(int(ceilf(p.food))), p.food / 100.0, Color(0.9, 0.58, 0.2))
	_bar(Vector2(bx, by), 240, "stamina", "", p.stamina / p.max_stamina(), Color(0.9, 0.84, 0.32))

	# Clock + horde countdown, on a soft panel with the sun or the moon
	var g = G.game
	var hh := int(g.time)
	var mm := int((g.time - hh) * 60.0)
	var ht: String = g.horde_text()
	var hcol := Color(0.85, 0.85, 0.8)
	if g.horde_active:
		hcol = Color(1, 0.25, 0.2, 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.004)))
	elif g.days_until_horde() <= 1:
		hcol = Color(1, 0.55, 0.4)
	var pw := maxf(250.0, font.get_string_size(ht, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 60.0)
	_rbox(Rect2(12, 12, pw, 66 if not p.flashlight.visible else 84), Color(0, 0, 0, 0.3), 12)
	if g.is_night():
		var moon := PackedVector2Array()  # (a crescent: round on the left, hollow on the right)
		for k in 13:
			var a := PI * 0.5 + PI * k / 12.0
			moon.append(Vector2(34, 36) + Vector2(cos(a), sin(a)) * 9.0)
		for k in 13:
			var a := PI * 1.5 - PI * k / 12.0
			moon.append(Vector2(34, 36) + Vector2(cos(a) * 4.5, sin(a) * 9.0))
		canvas.draw_colored_polygon(moon, Color(0.85, 0.88, 1.0) if not g.horde_active else Color(1, 0.3, 0.25))
	else:
		canvas.draw_circle(Vector2(34, 36), 7.5, Color(1, 0.86, 0.4))
		for k in 8:
			var a := TAU * k / 8.0
			canvas.draw_line(Vector2(34, 36) + Vector2(cos(a), sin(a)) * 10.0, Vector2(34, 36) + Vector2(cos(a), sin(a)) * 13.0, Color(1, 0.86, 0.4), 2.0)
	_text(Vector2(56, 44), "DAY %d   %02d:%02d" % [g.day, hh, mm], 24, Color(1, 1, 1))
	_text(Vector2(24, 68), ht, 16, hcol)
	if p.flashlight.visible:
		_text(Vector2(24, 88), "Flashlight on", 14, Color(1, 1, 0.8, 0.7))

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

	if G.mode == "client":
		_draw_online(vs)


## M4.5: the experience bar just above the hotbar, with the level beside it.
func _draw_xp(x0: float, y0: float, total: float) -> void:
	var xp: int = G.net.xp
	var lv := Skills.level_of(xp)
	var frac := 1.0 if lv >= Skills.MAX_LEVEL else float(xp - Skills.xp_for(lv)) / Skills.xp_step(lv)
	var r := Rect2(x0, y0 - 16, total, 5)
	_rbox(r, Color(0, 0, 0, 0.5), 3)
	if frac > 0.0:
		_rbox(Rect2(r.position, Vector2(maxf(total * clampf(frac, 0.0, 1.0), 5.0), 5)), Color(0.95, 0.78, 0.3, 0.95), 3)
	_text(Vector2(x0 - 66, y0 + 4), "LV %d" % lv, 15, Color(1, 0.88, 0.45, 0.95))
	if Skills.points(xp, G.net.perks) > 0:
		_text(Vector2(x0 + total + 14, y0 + 4), "+%d" % Skills.points(xp, G.net.perks), 15, Color(1, 0.88, 0.45, 0.95))


## Online: the chat log above the health bars, and players / ping at the top right.
func _draw_online(vs: Vector2) -> void:
	var chatting: bool = G.game.state == "chat"
	var y := vs.y - 240.0
	var shown := 0
	for i in range(chat_log.size() - 1, -1, -1):
		var m = chat_log[i]
		var a := 1.0
		if not chatting:
			if m["t"] > 14.0:
				break
			a = 1.0 if m["t"] < 12.0 else 1.0 - (m["t"] - 12.0) / 2.0
		var col: Color = m["col"]
		col.a = a
		var w := font.get_string_size(m["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		canvas.draw_rect(Rect2(16, y - 20, minf(w + 10, 640), 26), Color(0, 0, 0, 0.35 * a))
		_text(Vector2(20, y), m["text"], 18, col, HORIZONTAL_ALIGNMENT_LEFT, 630)
		y -= 26.0
		shown += 1
		if shown >= (12 if chatting else 6):
			break
	if G.game.state == "reconnecting":
		canvas.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.45))
		_text(Vector2(0, vs.y * 0.42), "Connection lost. Reconnecting...  %d s" % int(G.net.reconnect_s()), 34,
			Color(1, 0.8, 0.5), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_text(Vector2(0, vs.y * 0.42 + 40), "The game keeps trying for a minute.   Esc: back to the title", 18,
			Color(0.9, 0.9, 0.9), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		return
	if not G.solo:
		var line := "%d online   ·   %d ms" % [G.net.others.size() + 1, G.net.ping_ms()]
		_text(Vector2(vs.x - 320, 34), line, 16, Color(0.8, 1, 0.8, 0.8), HORIZONTAL_ALIGNMENT_RIGHT, 300)
	var quiet: float = G.net.quiet_s()
	if quiet > 1.5:
		_text(Vector2(vs.x - 420, 56), "No answer from the server for %d s" % int(quiet), 16,
			Color(1, 0.5, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, 400)
