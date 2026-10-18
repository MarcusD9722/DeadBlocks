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
var title_menu: VBoxContainer
var solo_btn: Button
var join_panel: VBoxContainer
var host_panel: VBoxContainer
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
var pause_players: Label
var pause_quit: Button
var pause_leave: Button
var chat_edit: LineEdit
var chat_log: Array = []
var _pause_refresh_t := 0.0
const CLIENT_CFG := "user://client.cfg"
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
	_build_chat()
	slot_btns.resize(36)
	slot_lbls.resize(36)
	G.net.status.connect(_on_net_status)
	G.net.chat.connect(_on_chat)
	G.net.notice.connect(_on_notice)


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
	solo_btn = _button("Play solo", func(): G.game.start_game())
	solo_btn.disabled = true
	solo_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title_menu.add_child(solo_btn)
	for e in [["Host game", func(): _show_panel(host_panel)], ["Join server", func(): _show_panel(join_panel)], ["Quit", func(): get_tree().quit()]]:
		var b := _button(e[0], e[1])
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		title_menu.add_child(b)

	join_panel = _panel(vb, "JOIN A SERVER")
	f_addr = _field(join_panel, "Server address", "e.g. 192.168.1.50 or myserver.duckdns.org", false)
	f_name = _field(join_panel, "Your name", "3-16 letters, digits or _", false)
	f_pin = _field(join_panel, "Your PIN", "4-8 digits; protects your name", true)
	f_pw = _field(join_panel, "Server password", "from the server owner", true)
	f_remember = CheckBox.new()
	f_remember.text = "Remember me on this PC"
	f_remember.button_pressed = true
	f_remember.focus_mode = Control.FOCUS_NONE
	join_panel.add_child(f_remember)
	_panel_buttons(join_panel, "Join", _on_join_pressed)

	host_panel = _panel(vb, "HOST A GAME ON THIS PC")
	h_name = _field(host_panel, "Your name", "3-16 letters, digits or _", false)
	h_pin = _field(host_panel, "Your PIN", "4-8 digits; protects your name", true)
	h_pw = _field(host_panel, "Password for friends", "they type this to join (can be empty)", true)
	h_port = _field(host_panel, "Port", str(Proto.DEFAULT_PORT), false)
	var lan := _lan_addresses()
	var note := _label("Friends on your home network join with %s.\nFor internet play, forward UDP port %d on your router to this PC.\nThe world resets when you stop hosting (saving comes in M1.5)." % [
		"this PC's address: " + ", ".join(lan) if not lan.is_empty() else "this PC's local address", Proto.DEFAULT_PORT], 15, Color(0.75, 0.78, 0.8))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host_panel.add_child(note)
	_panel_buttons(host_panel, "Host", _on_host_pressed)

	var how := _label("Gather. Craft. Build walls. Every night they come — every 7th night the horde comes.", 18, Color(0.8, 0.8, 0.8))
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(how)
	var ctl := _label(CONTROLS, 16, Color(0.7, 0.72, 0.7))
	ctl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ctl)
	title_info = [how, ctl]
	_load_client_cfg()
	if G.title_notice != "":
		_set_status(G.title_notice, true)
		G.title_notice = ""
	title_root.visible = true


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
	title_menu.visible = p == null
	join_panel.visible = p == join_panel
	host_panel.visible = p == host_panel


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
	var err: String = await G.host_game(pname, pin, h_pw.text, port)
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
		_set_status("Loading the server's world...  %d%%" % int(p * 100.0), false)
	else:
		solo_btn.text = "Play solo   (generating world %d%%)" % int(p * 100.0)


func show_ready() -> void:
	solo_btn.disabled = false
	solo_btn.text = "Play solo"


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
	chat_edit.placeholder_text = "Say something (Enter to send, Esc to cancel). Admins: /give planks 20, /dusk, /bloodmoon, /time 12, /kick name"
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
	pause_leave = _button("Leave Server", func(): G.end_client_session("You left the server."))
	row.add_child(pause_leave)
	pause_quit = _button("Quit Game", func(): get_tree().quit())
	row.add_child(pause_quit)
	pause_players = _label("", 18, Color(0.85, 0.95, 0.85))
	pause_players.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(pause_players)
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
	var online := G.mode == "client"
	pause_leave.visible = online
	pause_players.visible = online
	seed_lbl.text = "World seed: %d" % G.game.seed_v
	if online:
		seed_lbl.text += "   ·   The world keeps running while this menu is open."
	_refresh_pause_players()


## Online: who is playing, refreshed while the pause menu is open.
func _refresh_pause_players() -> void:
	if not pause_root.visible or G.mode != "client":
		return
	var names: Array = [G.net.player_name + " (you)"]
	for id in G.net.others:
		names.append(G.net.others[id]["name"])
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
	elif G.mode == "client":
		G.net.request_swap(i, p.selected)
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
	if G.mode == "client":
		# The server crafts; "+N item" shows when its inventory update arrives.
		if Crafting.can_craft(p.inv, r, G.game.nearby_stations()):
			G.sfx.play("craft", -4.0)
			G.game.on_crafted(int(r["out"]))
		G.net.request_craft(Crafting.RECIPES.find(r), times)
		return
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
	for m in chat_log:
		m["t"] += delta
	_pause_refresh_t -= delta
	if _pause_refresh_t <= 0.0:
		_pause_refresh_t = 1.0
		_refresh_pause_players()
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
	if G.game == null or G.player == null:
		return
	var st: String = G.game.state
	if st == "loading" or st == "title" or st == "connecting":
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

	if G.mode == "client":
		_draw_online(vs)


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
	var line := "%d online   ·   %d ms" % [G.net.others.size() + 1, G.net.ping_ms()]
	_text(Vector2(vs.x - 320, 34), line, 16, Color(0.8, 1, 0.8, 0.8), HORIZONTAL_ALIGNMENT_RIGHT, 300)
	var quiet: float = G.net.quiet_s()
	if quiet > 1.5:
		_text(Vector2(vs.x - 420, 56), "No answer from the server for %d s" % int(quiet), 16,
			Color(1, 0.5, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, 400)
