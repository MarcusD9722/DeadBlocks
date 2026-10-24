class_name Tex
extends RefCounted
## Paints every block texture and item icon in code, pixel by pixel.

const TS := 16
const COLS := 8
const NUM_TILES := 27

var atlas_img: Image
var atlas: ImageTexture
var icons := {}
var crack_tex: Array[ImageTexture] = []
## The smooth ground's materials (SmoothMesher layers): albedo, and normals with the height map
## in blue. From assets/textures (CC0 photo textures, tools/make_textures.py); painted from noise
## if those are missing.
var terrain_albedo: TextureLayered
var terrain_normal: TextureLayered
const TERRAIN_PX := 256
## Built blocks (cubes, boxes, log trunks): one array layer per atlas tile they use.
var block_albedo: TextureLayered
var block_normal: TextureLayered
## Leaves: a tile of leaves with see-through gaps.
var leaves_albedo: Texture2D
var leaves_normal: Texture2D
## Atlas tile -> block array layer (the order of tools/make_textures.py's blocks list).
const BLOCK_LAYERS := {4: 0, 5: 1, 6: 2, 8: 3, 13: 4, 14: 5, 15: 6, 16: 7, 20: 8, 22: 9, 25: 10, 26: 11, 23: 12, 24: 13}
static var layer_of_tile := PackedInt32Array()


func _init() -> void:
	atlas_img = Image.create(TS * COLS, TS * COLS, false, Image.FORMAT_RGBA8)
	atlas_img.fill(Color(0, 0, 0, 0))
	for t in NUM_TILES:
		_paint(t)
	atlas = ImageTexture.create_from_image(atlas_img)
	for id in range(1, Blocks.COUNT):
		var tile: int = Blocks.TILES[id][1]
		@warning_ignore("integer_division")
		var img := atlas_img.get_region(Rect2i((tile % COLS) * TS, (tile / COLS) * TS, TS, TS))
		icons[id] = ImageTexture.create_from_image(img)
	for id in Items.DATA.keys():
		icons[int(id)] = ImageTexture.create_from_image(_item_icon(int(id)))
	for s in 4:
		crack_tex.append(ImageTexture.create_from_image(_crack(s)))
	if not _load_assets():
		_terrain()


func icon(id: int) -> Texture2D:
	return icons.get(id)


# ---------------------------------------------------------------- helpers

func _c(r: int, g: int, b: int, a: int = 255) -> Color:
	return Color8(r, g, b, a)


func _var(rng: RandomNumberGenerator, c: Color, amt: float) -> Color:
	var k := rng.randf_range(-amt, amt)
	return Color(clampf(c.r + k, 0, 1), clampf(c.g + k, 0, 1), clampf(c.b + k, 0, 1), c.a)


func _px(t: int, x: int, y: int, c: Color) -> void:
	@warning_ignore("integer_division")
	atlas_img.set_pixel((t % COLS) * TS + x, (t / COLS) * TS + y, c)


func _fill(t: int, r: RandomNumberGenerator, base: Color, amt: float, speck := Color(0, 0, 0, 0), speck_p := 0.0) -> void:
	for y in TS:
		for x in TS:
			var c := _var(r, base, amt)
			if speck_p > 0.0 and r.randf() < speck_p:
				c = _var(r, speck, amt * 0.5)
			_px(t, x, y, c)


func _planks(t: int, r: RandomNumberGenerator) -> void:
	for y in TS:
		for x in TS:
			@warning_ignore("integer_division")
			var board := y / 4
			var c := _c(170, 134, 84) if board % 2 == 0 else _c(158, 123, 76)
			if y % 4 == 3:
				c = _c(110, 82, 50)
			if x == (board * 7 + 3) % 16:
				c = _c(120, 90, 56)
			_px(t, x, y, _var(r, c, 0.03))


func _stone(t: int, r: RandomNumberGenerator) -> void:
	_fill(t, r, _c(128, 128, 128), 0.035, _c(104, 104, 104), 0.14)


func _bricks(t: int, r: RandomNumberGenerator, base: Color, mortar: Color) -> void:
	for y in TS:
		for x in TS:
			@warning_ignore("integer_division")
			var row := y / 4
			var off := 4 if row % 2 == 1 else 0
			var c := base
			if y % 4 == 3 or (x + off) % 8 == 7:
				c = mortar
			_px(t, x, y, _var(r, c, 0.03))


func _ore(t: int, r: RandomNumberGenerator, col: Color) -> void:
	for k in 5:
		var cx := r.randi_range(2, 13)
		var cy := r.randi_range(2, 13)
		for j in r.randi_range(4, 7):
			var x := clampi(cx + r.randi_range(-1, 1), 0, 15)
			var y := clampi(cy + r.randi_range(-1, 1), 0, 15)
			_px(t, x, y, _var(r, col, 0.06))


# ---------------------------------------------------------------- tiles

func _paint(t: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 7919 * (t + 3)
	var grass := _c(96, 160, 56)
	var dirt := _c(134, 96, 67)
	match t:
		0:
			_fill(t, r, grass, 0.05, _c(74, 132, 42), 0.12)
		1:
			_fill(t, r, dirt, 0.045, _c(110, 78, 54), 0.1)
			for x in TS:
				var e := 3 + r.randi_range(0, 2)
				for y in e:
					_px(t, x, y, _var(r, grass, 0.05))
				if r.randf() < 0.5:
					_px(t, x, e, _var(r, _c(74, 132, 42), 0.04))
		2:
			_fill(t, r, dirt, 0.045, _c(110, 78, 54), 0.12)
		3:
			_stone(t, r)
		4:
			_cobble(t, r, 0.42, 0.6)
		5:
			for y in TS:
				for x in TS:
					var c := _c(112, 84, 52) if x % 4 != 0 else _c(84, 62, 38)
					if (x + y * 3) % 11 == 0:
						c = _c(90, 66, 40)
					_px(t, x, y, _var(r, c, 0.03))
		6:
			for y in TS:
				for x in TS:
					var d := Vector2(x - 7.5, y - 7.5).length()
					var c: Color
					if d > 6.8:
						c = _c(92, 68, 42)
					elif int(d * 1.2) % 2 == 0:
						c = _c(170, 132, 84)
					else:
						c = _c(146, 110, 68)
					_px(t, x, y, _var(r, c, 0.025))
		7:
			for y in TS:
				for x in TS:
					var c := _var(r, _c(62, 128, 46), 0.08)
					var roll := r.randf()
					if roll < 0.12:
						c = Color(0, 0, 0, 0)
					elif roll < 0.27:
						c = _var(r, _c(46, 98, 34), 0.04)
					_px(t, x, y, c)
		8:
			_planks(t, r)
		9:
			_fill(t, r, _c(220, 207, 160), 0.035, _c(200, 186, 140), 0.1)
		10:
			_stone(t, r)
			_ore(t, r, _c(34, 34, 36))
		11:
			_stone(t, r)
			_ore(t, r, _c(214, 160, 118))
		12:
			_fill(t, r, _c(62, 62, 64), 0.09, _c(30, 30, 32), 0.25)
		13:
			_planks(t, r)
			for y in TS:
				for x in TS:
					if x == 0 or y == 0 or x == 15 or y == 15:
						_px(t, x, y, _var(r, _c(90, 64, 38), 0.02))
					elif x == 7 or y == 7:
						_px(t, x, y, _var(r, _c(122, 90, 54), 0.02))
		14:
			_planks(t, r)
			for x in range(2, 9):
				for y in range(4, 8):
					_px(t, x, y, _var(r, _c(178, 178, 184), 0.03))
				if x % 2 == 0:
					_px(t, x, 8, _c(150, 150, 156))
			for y in range(4, 7):
				_px(t, 9, y, _c(80, 56, 32))
				_px(t, 10, y, _c(80, 56, 32))
			for y in range(5, 14):
				_px(t, 12, y, _c(84, 60, 36))
			for x in range(10, 15):
				for y in range(3, 6):
					_px(t, x, y, _var(r, _c(140, 140, 148), 0.03))
		15:
			_fill(t, r, _c(92, 92, 96), 0.04, _c(70, 70, 74), 0.2)
			for y in range(3, 13):
				for x in range(3, 13):
					if x % 3 == 0 or y % 3 == 0:
						_px(t, x, y, _c(40, 40, 44))
					else:
						_px(t, x, y, _var(r, _c(222, 112, 40), 0.08))
		16:
			_bricks(t, r, _c(112, 110, 108), _c(70, 68, 66))
			for y in range(6, 14):
				for x in range(4, 12):
					var c := _c(28, 22, 22)
					if y >= 10:
						c = _c(255, 214, 90) if r.randf() < 0.45 else _c(232, 110, 34)
					_px(t, x, y, c)
		17:
			for x in range(1, 15):
				for y in range(12, 16):
					var c := _c(100, 72, 44)
					if x <= 1 or x >= 14:
						c = _c(152, 116, 70)
					_px(t, x, y, _var(r, c, 0.03))
			for y in range(2, 12):
				var w := (y - 1) * 0.55
				for x in range(2, 14):
					var dx := absf(x + 0.5 - 8.0)
					if dx < w * (0.65 + r.randf() * 0.4):
						var c := _c(255, 226, 110) if dx < w * 0.35 else _c(240, 120, 40)
						_px(t, x, y, c)
		18:
			for y in range(6, 16):
				_px(t, 7, y, _c(118, 86, 50))
				_px(t, 8, y, _c(92, 66, 38))
			for y in range(2, 6):
				for x in range(6, 10):
					var inner := x >= 7 and x <= 8 and y >= 3
					_px(t, x, y, _c(255, 236, 140) if inner else _c(250, 150, 50))
			_px(t, 7, 1, _c(250, 150, 50))
			_px(t, 8, 1, _c(250, 150, 50))
		19:
			for x in range(1, 15):
				_px(t, x, 11, _c(96, 70, 42))
			for s in 4:
				var cx: int = [2, 6, 10, 13][s]
				var h := 9 + r.randi_range(0, 5)
				for k in h:
					var y := 15 - k
					var half := 1 if k < h - 3 else 0
					for x in range(cx - half, cx + half + 1):
						if x < 0 or x > 15:
							continue
						var c := _c(150, 112, 66) if x <= cx else _c(118, 86, 50)
						if k >= h - 2:
							c = _c(205, 175, 125)
						_px(t, x, y, _var(r, c, 0.03))
		20:
			_bricks(t, r, _c(140, 140, 142), _c(92, 92, 94))
		21:
			for y in TS:
				for x in TS:
					var dx := (x + 0.5 - 8.0) / 7.5
					var dy := (y + 0.5 - 9.5) / 6.5
					if dx * dx + dy * dy < 1.0 and r.randf() > 0.08:
						_px(t, x, y, _var(r, _c(56, 118, 42), 0.07))
			for k in 8:
				var bx := r.randi_range(3, 11)
				var by := r.randi_range(5, 13)
				_px(t, bx, by, _c(196, 32, 44))
				_px(t, bx + 1, by, _c(170, 24, 36))
				_px(t, bx, by + 1, _c(170, 24, 36))
				_px(t, bx + 1, by + 1, _c(150, 20, 30))
				_px(t, bx, by, _c(255, 130, 130))
		22:
			for y in TS:
				for x in TS:
					var c := _c(118, 126, 138)
					if x == 0 or y == 0 or x == 15 or y == 15:
						c = _c(70, 74, 82)
					elif x == y or x + y == 15:
						c = _c(88, 94, 104)
					_px(t, x, y, _var(r, c, 0.025))
			for p in [Vector2i(2, 2), Vector2i(13, 2), Vector2i(2, 13), Vector2i(13, 13)]:
				_px(t, p.x, p.y, _c(196, 200, 210))
		23:
			# Backpack, top: canvas with the flap's seam and a carry loop.
			_fill(t, r, _c(124, 100, 62), 0.035, _c(104, 82, 50), 0.15)
			for x in TS:
				_px(t, x, 11, _c(84, 64, 38))
			for x in range(5, 11):
				_px(t, x, 4, _c(62, 46, 30))
				_px(t, x, 5, _c(62, 46, 30))
		24:
			# Backpack, sides: a flap over the top, a front pocket and two straps with buckles.
			_fill(t, r, _c(124, 100, 62), 0.035, _c(104, 82, 50), 0.15)
			for y in range(0, 5):
				for x in TS:
					_px(t, x, y, _var(r, _c(96, 76, 46), 0.03))
			for x in TS:
				_px(t, x, 5, _c(70, 54, 34))
			for y in range(8, 14):
				for x in range(3, 13):
					var c := _c(110, 88, 54)
					if y == 8 or y == 13 or x == 3 or x == 12:
						c = _c(78, 60, 36)
					_px(t, x, y, _var(r, c, 0.03))
			for x in [4, 11]:
				for y in range(0, 9):
					_px(t, x, y, _c(58, 44, 28))
				_px(t, x, 6, _c(206, 194, 150))
				_px(t, x, 7, _c(176, 164, 122))
		25:
			# Bed, top: a pillow at one end, a red blanket with a turned-down sheet, a wooden rim.
			for y in TS:
				for x in TS:
					var c := _c(168, 44, 40)
					if y < 5:
						c = _c(240, 236, 228) if x > 2 and x < 13 and y > 0 and y < 4 else _c(198, 192, 180)
					elif y == 5:
						c = _c(226, 220, 206)
					elif (x + y) % 6 == 0:
						c = _c(146, 34, 32)
					if x == 0 or x == 15:
						c = _c(120, 88, 52)
					_px(t, x, y, _var(r, c, 0.025))
		26:
			# Bed, sides (drawn half height): blanket over a wooden frame.
			for y in TS:
				for x in TS:
					var c := _c(168, 44, 40) if y < 7 else _c(150, 112, 68)
					if y == 7:
						c = _c(110, 80, 48)
					elif y >= 8 and (y == 15 or x == 0 or x == 15):
						c = _c(104, 76, 44)
					_px(t, x, y, _var(r, c, 0.025))


func _cobble(t: int, r: RandomNumberGenerator, lo: float, hi: float) -> void:
	var pts: Array[Vector2] = []
	var shades: Array[float] = []
	for i in 9:
		pts.append(Vector2(r.randf() * 16.0, r.randf() * 16.0))
		shades.append(r.randf_range(lo, hi))
	for y in TS:
		for x in TS:
			var d1 := 999.0
			var d2 := 999.0
			var best := 0
			var p := Vector2(x + 0.5, y + 0.5)
			for i in pts.size():
				for ox in [-16.0, 0.0, 16.0]:
					for oy in [-16.0, 0.0, 16.0]:
						var d := p.distance_to(pts[i] + Vector2(ox, oy))
						if d < d1:
							d2 = d1
							d1 = d
							best = i
						elif d < d2:
							d2 = d
			var c: Color
			if d2 - d1 < 1.15:
				c = _var(r, Color(0.28, 0.28, 0.28), 0.03)
			else:
				var s := shades[best]
				c = _var(r, Color(s, s, s), 0.035)
			_px(t, x, y, c)


# ---------------------------------------------------------------- icons

func _ipx(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < 16 and y >= 0 and y < 16:
		img.set_pixel(x, y, c)


func _line(img: Image, x0: float, y0: float, x1: float, y1: float, c: Color, w: int) -> void:
	for i in 41:
		var t := i / 40.0
		var x := int(round(lerpf(x0, x1, t)))
		var y := int(round(lerpf(y0, y1, t)))
		for ox in w:
			for oy in w:
				@warning_ignore("integer_division")
				_ipx(img, x + ox - w / 2, y + oy - w / 2, c)


func _disc(img: Image, cx: float, cy: float, rad: float, c: Color) -> void:
	for y in 16:
		for x in 16:
			if Vector2(x + 0.5 - cx, y + 0.5 - cy).length() <= rad:
				img.set_pixel(x, y, c)


func _item_icon(id: int) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var handle := _c(104, 76, 44)
	var tiers := {1: _c(164, 124, 74), 2: _c(132, 132, 138), 3: _c(218, 222, 230)}
	match id:
		Items.STICK:
			_line(img, 3, 13, 12, 3, _c(96, 70, 42), 2)
			_line(img, 3, 12, 11, 3, _c(140, 104, 62), 1)
		Items.COAL:
			_disc(img, 8, 8.5, 5.5, _c(38, 38, 40))
			_disc(img, 6, 6, 1.4, _c(96, 96, 104))
			_ipx(img, 10, 10, _c(80, 80, 88))
			_ipx(img, 9, 5, _c(80, 80, 88))
		Items.IRON_INGOT:
			for y in range(6, 12):
				for x in range(3, 14):
					var c := _c(205, 208, 215)
					if y == 6:
						c = _c(238, 240, 244)
					elif y == 11 or x == 3 or x == 13:
						c = _c(150, 152, 160)
					img.set_pixel(x, y, c)
		Items.RAW_MEAT:
			_disc(img, 8, 8.5, 5.8, _c(200, 70, 80))
			_disc(img, 7, 7.5, 2.5, _c(236, 150, 150))
			_line(img, 12, 4, 14, 2, _c(240, 235, 220), 2)
		Items.COOKED_MEAT:
			_disc(img, 8, 8.5, 5.8, _c(140, 82, 42))
			_disc(img, 7, 7.5, 2.2, _c(176, 108, 56))
			_line(img, 12, 4, 14, 2, _c(240, 235, 220), 2)
		Items.BERRIES:
			_line(img, 7, 2, 10, 4, _c(60, 130, 50), 2)
			for p in [Vector2(5.5, 9), Vector2(10.5, 9), Vector2(8, 12.5), Vector2(8, 6.5)]:
				_disc(img, p.x, p.y, 2.4, _c(190, 30, 45))
				_ipx(img, int(p.x) - 1, int(p.y) - 1, _c(255, 140, 140))
		Items.BANDAGE:
			_line(img, 3, 12, 12, 3, _c(236, 236, 228), 4)
			_line(img, 4, 12, 12, 4, _c(205, 205, 196), 1)
			for k in range(6, 10):
				_ipx(img, 7, k, _c(200, 40, 40))
				_ipx(img, 8, k, _c(200, 40, 40))
				_ipx(img, k, 7, _c(200, 40, 40))
				_ipx(img, k, 8, _c(200, 40, 40))
		Items.FIBER:
			_line(img, 4, 14, 7, 2, _c(150, 170, 80), 1)
			_line(img, 7, 14, 9, 2, _c(120, 150, 60), 1)
			_line(img, 10, 14, 12, 3, _c(170, 180, 90), 1)
			_line(img, 5, 9, 11, 9, _c(110, 90, 50), 1)
		_:
			var info := Items.info(id)
			var tool: String = str(info.get("tool", ""))
			var col: Color = tiers.get(int(info.get("tier", 1)), _c(200, 200, 200))
			if tool == "pick":
				_line(img, 3, 13, 10, 6, handle, 2)
				_line(img, 5, 3, 13, 11, col, 2)
				_ipx(img, 4, 3, col.darkened(0.3))
				_ipx(img, 13, 12, col.darkened(0.3))
			elif tool == "axe":
				_disc(img, 11.5, 4.8, 3.4, col)
				_disc(img, 12.3, 4.0, 1.4, col.lightened(0.2))
				_line(img, 3, 13, 10, 6, handle, 2)
			elif id == Items.WOOD_CLUB:
				_line(img, 3, 13, 11, 5, _c(130, 96, 56), 3)
				_disc(img, 11.5, 4.5, 2.7, _c(152, 114, 68))
			else:
				_line(img, 5, 11, 13, 3, col, 2)
				_line(img, 6, 10, 13, 3, col.lightened(0.25), 1)
				_line(img, 3, 8, 7, 12, _c(90, 70, 40), 1)
				_line(img, 2, 14, 5, 11, handle, 2)
	return img


func _crack(s: int) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 99
	for k in (s + 1) * 3:
		var a := r.randf() * TAU
		var ln := r.randf_range(3.0, 8.0)
		var x0 := 8.0 + r.randf_range(-3.0, 3.0)
		var y0 := 8.0 + r.randf_range(-3.0, 3.0)
		_line(img, x0, y0, x0 + cos(a) * ln, y0 + sin(a) * ln, Color(0, 0, 0, 0.8), 1)
	return img


# ---------------------------------------------------------------- photo textures

static func block_layer(tile: int) -> int:
	if layer_of_tile.is_empty():
		layer_of_tile.resize(64)
		layer_of_tile.fill(3)  # planks for anything without its own picture
		for t in BLOCK_LAYERS:
			layer_of_tile[t] = BLOCK_LAYERS[t]
	return layer_of_tile[tile]


func _load_assets() -> bool:
	block_layer(0)  # fill the table on the main thread
	var d := "res://assets/textures/"
	terrain_albedo = load(d + "terrain_albedo.jpg")
	terrain_normal = load(d + "terrain_normal.jpg")
	block_albedo = load(d + "blocks_albedo.jpg")
	block_normal = load(d + "blocks_normal.jpg")
	leaves_albedo = load(d + "leaves_albedo.png")
	leaves_normal = load(d + "leaves_normal.jpg")
	return terrain_albedo != null and terrain_normal != null and block_albedo != null and leaves_albedo != null


# ---------------------------------------------------------------- smooth ground

## One seamless noise image as bytes (0-255), TERRAIN_PX square.
func _noise(sd: int, type: int, freq: float, octaves := 3, cell_ret := -1) -> PackedByteArray:
	var n := FastNoiseLite.new()
	n.seed = sd
	n.noise_type = type
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	if cell_ret >= 0:
		n.cellular_return_type = cell_ret
	var img := n.get_seamless_image(TERRAIN_PX, TERRAIN_PX, false, false, 0.1, true)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


## The seven ground materials, painted from noise: grass, dirt, stone, sand, coal ore, iron ore,
## bedrock (the order of SmoothMesher's layers).
func _terrain() -> void:
	var N := TERRAIN_PX * TERRAIN_PX
	var fine := _noise(11, FastNoiseLite.TYPE_VALUE, 0.35, 1)
	var blades := _noise(12, FastNoiseLite.TYPE_CELLULAR, 0.09, 1, FastNoiseLite.RETURN_DISTANCE)
	var patch := _noise(13, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, 3)
	var fbm := _noise(14, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.03, 5)
	var cracks := _noise(15, FastNoiseLite.TYPE_CELLULAR, 0.018, 2, FastNoiseLite.RETURN_DISTANCE2_SUB)
	var pebbles := _noise(16, FastNoiseLite.TYPE_CELLULAR, 0.05, 1, FastNoiseLite.RETURN_DISTANCE)
	var cellv := _noise(17, FastNoiseLite.TYPE_CELLULAR, 0.05, 1, FastNoiseLite.RETURN_CELL_VALUE)
	var spots := _noise(18, FastNoiseLite.TYPE_CELLULAR, 0.03, 1, FastNoiseLite.RETURN_DISTANCE)
	var spotv := _noise(19, FastNoiseLite.TYPE_CELLULAR, 0.03, 1, FastNoiseLite.RETURN_CELL_VALUE)
	var albs: Array[Image] = []
	var nrms: Array[Image] = []
	for layer in 7:
		var rgba := PackedByteArray()
		rgba.resize(N * 4)
		var hgt := PackedByteArray()
		hgt.resize(N)
		for i in N:
			var f := fine[i] / 255.0
			var pa := patch[i] / 255.0
			var fb := fbm[i] / 255.0
			var col: Color
			var h: float
			match layer:
				0:  # grass: blades over darker roots, with drier patches
					var bl := 1.0 - blades[i] / 255.0
					h = clampf(bl * 0.75 + f * 0.25, 0.0, 1.0)
					col = Color(0.13, 0.25, 0.07).lerp(Color(0.36, 0.55, 0.17), h)
					col = col.lerp(Color(0.48, 0.5, 0.2), smoothstep(0.55, 0.85, pa) * 0.55)
				1:  # dirt with small stones
					var pb := pebbles[i] / 255.0
					var stone := 1.0 - smoothstep(0.18, 0.3, pb)
					h = clampf(fb * 0.5 + f * 0.2 + stone * 0.5, 0.0, 1.0)
					col = Color(0.24, 0.16, 0.1).lerp(Color(0.42, 0.3, 0.19), fb * 0.7 + f * 0.3)
					col = col.lerp(Color(0.42, 0.38, 0.33).lerp(Color(0.3, 0.27, 0.24), cellv[i] / 255.0), stone)
				2, 4, 5, 6:  # rock (and the ores and bedrock in it)
					var cr := smoothstep(0.0, 0.12, cracks[i] / 255.0)
					h = clampf(fb * 0.7 + f * 0.15 + cr * 0.25 - (1.0 - cr) * 0.3, 0.0, 1.0)
					var lo := Color(0.3, 0.3, 0.31)
					var hi := Color(0.58, 0.57, 0.56)
					if layer == 6:
						lo = Color(0.1, 0.1, 0.11)
						hi = Color(0.3, 0.3, 0.32)
					col = lo.lerp(hi, fb * 0.75 + f * 0.25)
					col = col.lerp(col * 0.45, 1.0 - cr)
					if layer == 4 or layer == 5:
						var sp := spots[i] / 255.0
						var on := (1.0 - smoothstep(0.22, 0.36, sp)) * float(spotv[i] > 70)
						var ore := Color(0.06, 0.06, 0.07).lerp(Color(0.16, 0.16, 0.18), f) if layer == 4 \
							else Color(0.62, 0.4, 0.24).lerp(Color(0.85, 0.62, 0.42), f)
						col = col.lerp(ore, on)
						h = lerpf(h, 0.85 + f * 0.15, on)
				3:  # sand: fine grains and wind ripples
					@warning_ignore("integer_division")
					var y := float(i / TERRAIN_PX)
					var rip := 0.5 + 0.5 * sin(y * 0.3 + fb * 9.0)
					h = clampf(rip * 0.45 + f * 0.4 + fb * 0.15, 0.0, 1.0)
					col = Color(0.66, 0.58, 0.4).lerp(Color(0.85, 0.77, 0.56), h)
			var o := i * 4
			rgba[o] = int(clampf(col.r, 0.0, 1.0) * 255.0)
			rgba[o + 1] = int(clampf(col.g, 0.0, 1.0) * 255.0)
			rgba[o + 2] = int(clampf(col.b, 0.0, 1.0) * 255.0)
			rgba[o + 3] = int(h * 255.0)
			hgt[i] = int(h * 255.0)
		var a := Image.create_from_data(TERRAIN_PX, TERRAIN_PX, false, Image.FORMAT_RGBA8, rgba)
		a.convert(Image.FORMAT_RGB8)
		a.generate_mipmaps()
		albs.append(a)
		var nm := Image.create_from_data(TERRAIN_PX, TERRAIN_PX, false, Image.FORMAT_L8, hgt)
		nm.convert(Image.FORMAT_RGBA8)
		nm.bump_map_to_normal_map([3.0, 4.0, 5.0, 2.5, 5.0, 5.0, 6.0][layer])
		for j in N:  # the height map goes into blue, as in the photo textures
			@warning_ignore("integer_division")
			var py := j / TERRAIN_PX
			var c := nm.get_pixel(j % TERRAIN_PX, py)
			nm.set_pixel(j % TERRAIN_PX, py, Color(c.r, c.g, hgt[j] / 255.0))
		nm.convert(Image.FORMAT_RGB8)
		nm.generate_mipmaps(true)
		nrms.append(nm)
	var ta := Texture2DArray.new()
	ta.create_from_images(albs)
	terrain_albedo = ta
	var tn := Texture2DArray.new()
	tn.create_from_images(nrms)
	terrain_normal = tn
