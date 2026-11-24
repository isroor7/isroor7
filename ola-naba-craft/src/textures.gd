# Original 16x16 pixel textures for every block, painted in code, plus 32x32 item icons.
# Palette: warm golden light, muted turquoise shadow tones, pink and lilac accents.
extends RefCounted

const LAYERS := ["moss_top", "moss_side", "soil", "slate", "timber_side", "timber_top", "canopy", "planks",
	"glowglass", "sand", "water", "blossom", "ember_ore", "sunmetal_ore", "slate_brick", "lantern",
	"workbench_top", "workbench_side", "bedroll_top", "bedroll_side", "deepstone", "sandstone_side",
	"sandstone_top", "lilac_top", "lilac_side"]

static var _array: Texture2DArray
static var _images: Array[Image] = []
static var _icons := {}

static func block_images() -> Array[Image]:
	if _images.is_empty():
		for i in LAYERS.size():
			_images.append(_paint(i))
	return _images

static func block_array() -> Texture2DArray:
	if _array == null:
		var imgs: Array[Image] = []
		for img in block_images():
			var copy := img.duplicate() as Image
			copy.generate_mipmaps()
			imgs.append(copy)
		_array = Texture2DArray.new()
		_array.create_from_images(imgs)
	return _array

static func _c(hex: String) -> Color:
	return Color(hex)

static func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 91731 + seed_value * 7919
	return r

static func _speckle(img: Image, r: RandomNumberGenerator, cols: Array, weights: Array) -> void:
	for y in 16:
		for x in 16:
			var pick := r.randf()
			var acc := 0.0
			for i in cols.size():
				acc += weights[i]
				if pick <= acc:
					img.set_pixel(x, y, cols[i])
					break

static func _soil(img: Image, r: RandomNumberGenerator) -> void:
	_speckle(img, r, [_c("#a8744f"), _c("#96643f"), _c("#b8845a"), _c("#c9a37c")], [0.5, 0.28, 0.17, 0.05])

static func _slate(img: Image, r: RandomNumberGenerator) -> void:
	_speckle(img, r, [_c("#7f86a6"), _c("#717897"), _c("#8f96b5")], [0.55, 0.25, 0.2])
	# faint strata lines and cracks
	for x in 16:
		if r.randf() < 0.7:
			img.set_pixel(x, 5, _c("#6b7290"))
		if r.randf() < 0.5:
			img.set_pixel(x, 11, _c("#6b7290"))
	var cx := r.randi_range(2, 12)
	var cy := r.randi_range(2, 12)
	for i in 4:
		img.set_pixel(clampi(cx + i, 0, 15), clampi(cy + (i % 2), 0, 15), _c("#5d6382"))

static func _moss_band(img: Image, r: RandomNumberGenerator, cols: Array) -> void:
	for x in 16:
		var depth := 3 + r.randi_range(0, 2)
		for y in depth:
			img.set_pixel(x, y, cols[r.randi_range(0, cols.size() - 1)])
		if r.randf() < 0.35:
			img.set_pixel(x, depth, cols[2])

static func _paint(layer: int) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var r := _rng(layer)
	match LAYERS[layer]:
		"moss_top":
			_speckle(img, r, [_c("#93c35a"), _c("#a9d265"), _c("#7cae50"), _c("#d7e27c")], [0.42, 0.3, 0.24, 0.04])
			for i in 3:
				var fx := r.randi_range(1, 14)
				var fy := r.randi_range(1, 14)
				img.set_pixel(fx, fy, _c("#ffe08a"))
		"moss_side":
			_soil(img, r)
			_moss_band(img, r, [_c("#93c35a"), _c("#a9d265"), _c("#7cae50")])
		"soil":
			_soil(img, r)
		"slate":
			_slate(img, r)
		"timber_side":
			for x in 16:
				var base := _c("#9a6441") if x % 4 != 0 else _c("#78492f")
				for y in 16:
					var c := base
					if r.randf() < 0.18:
						c = _c("#ad744c")
					img.set_pixel(x, y, c)
		"timber_top":
			for y in 16:
				for x in 16:
					var d := Vector2(x - 7.5, y - 7.5).length()
					var c := _c("#dcab6e")
					if d > 6.6:
						c = _c("#8c5a3c")
					elif int(d) % 3 == 0:
						c = _c("#c08b55")
					img.set_pixel(x, y, c)
		"canopy":
			_speckle(img, r, [_c("#4fae84"), _c("#3f9673"), _c("#67c294"), _c("#2f7a63"), _c("#e8d27a")], [0.36, 0.26, 0.22, 0.13, 0.03])
		"planks":
			for y in 16:
				for x in 16:
					var c := _c("#d9a76a")
					if y % 4 == 3:
						c = _c("#b98552")
					elif r.randf() < 0.2:
						c = _c("#e7b97b")
					elif r.randf() < 0.08:
						c = _c("#c8955d")
					if (y / 4) % 2 == 0 and x == 11 and y % 4 != 3:
						c = _c("#b98552")
					if (y / 4) % 2 == 1 and x == 4 and y % 4 != 3:
						c = _c("#b98552")
					img.set_pixel(x, y, c)
		"glowglass":
			for y in 16:
				for x in 16:
					var edge := x == 0 or y == 0 or x == 15 or y == 15
					var c := Color(0.66, 0.94, 0.92, 0.3)
					if edge:
						c = _c("#4fc9c9")
					elif (x + y) % 9 == 0 and x > 2 and x < 9:
						c = Color(1, 1, 1, 0.75)
					img.set_pixel(x, y, c)
		"sand":
			_speckle(img, r, [_c("#f0d49a"), _c("#e4c387"), _c("#f8e2ad"), _c("#d9b478")], [0.5, 0.25, 0.17, 0.08])
		"water":
			for y in 16:
				for x in 16:
					var c := Color(0.25, 0.72, 0.77, 0.66)
					if (x + y * 2) % 11 == 0 or (x * 3 + y) % 13 == 0:
						c = Color(0.48, 0.86, 0.86, 0.72)
					img.set_pixel(x, y, c)
		"blossom":
			_speckle(img, r, [_c("#f29bc2"), _c("#c9a0ea"), _c("#ffd0e4"), _c("#d77aa8"), _c("#4fae84")], [0.34, 0.24, 0.16, 0.16, 0.1])
		"ember_ore", "sunmetal_ore":
			_slate(img, r)
			var hot := [_c("#ff8a6b"), _c("#ffc27a")] if LAYERS[layer] == "ember_ore" else [_c("#ffd25e"), _c("#fff1a8")]
			for i in 5:
				var ox := r.randi_range(1, 13)
				var oy := r.randi_range(1, 13)
				img.set_pixel(ox, oy, hot[0])
				img.set_pixel(ox + 1, oy, hot[1])
				img.set_pixel(ox, oy + 1, hot[0])
				if r.randf() < 0.5:
					img.set_pixel(ox + 1, oy + 1, _c("#5d6382"))
		"slate_brick":
			for y in 16:
				for x in 16:
					var row := y / 4
					var off := 4 if row % 2 == 1 else 0
					var mortar := y % 4 == 3 or (x + off) % 8 == 7
					var c := _c("#5f6283") if mortar else (_c("#8d8fb3") if r.randf() < 0.75 else _c("#9ea0c4"))
					if not mortar and y % 4 == 0:
						c = _c("#a7a9cc")
					img.set_pixel(x, y, c)
		"lantern":
			for y in 16:
				for x in 16:
					var frame := x < 2 or x > 13 or y < 2 or y > 13 or x == 7 or x == 8
					var c := _c("#3a3550") if frame else (_c("#fff0b8") if Vector2(x - 7.5, y - 7.5).length() < 4 else _c("#ffd27a"))
					if frame and (x == 0 or y == 0 or x == 15 or y == 15):
						c = _c("#5b4f73")
					img.set_pixel(x, y, c)
		"workbench_top":
			for y in 16:
				for x in 16:
					var c := _c("#d9a76a") if r.randf() < 0.8 else _c("#e7b97b")
					if x == 0 or y == 0 or x == 15 or y == 15:
						c = _c("#8c5a3c")
					elif x == 5 or x == 10 or y == 5 or y == 10:
						c = _c("#a06d45")
					img.set_pixel(x, y, c)
			img.set_pixel(12, 2, _c("#f48dab"))
			img.set_pixel(13, 2, _c("#f48dab"))
		"workbench_side":
			for y in 16:
				for x in 16:
					var c := _c("#c8955d") if r.randf() < 0.8 else _c("#d9a76a")
					if y < 3:
						c = _c("#8c5a3c")
					elif (x < 2 or x > 13) and y > 2:
						c = _c("#78492f")
					img.set_pixel(x, y, c)
			for i in 5:  # a little saw and hammer silhouette
				img.set_pixel(4 + i, 7, _c("#8d93b3"))
				img.set_pixel(4 + i, 8, _c("#6f7695") if i % 2 == 0 else _c("#8d93b3"))
			for i in 4:
				img.set_pixel(11, 6 + i, _c("#78492f"))
			img.set_pixel(10, 6, _c("#7f86a6"))
			img.set_pixel(12, 6, _c("#7f86a6"))
		"bedroll_top":
			for y in 16:
				for x in 16:
					var c := _c("#e78aa8") if (x + y) % 4 != 0 else _c("#f2a3bd")
					if y < 5:
						c = _c("#fbeee2") if r.randf() < 0.85 else _c("#efd8cb")
					if x == 0 or x == 15:
						c = _c("#c96b8c")
					img.set_pixel(x, y, c)
		"bedroll_side":
			for y in 16:
				for x in 16:
					var c := _c("#e78aa8")
					if y > 11:
						c = _c("#7cae50") if r.randf() < 0.7 else _c("#93c35a")
					elif y == 5:
						c = _c("#fbeee2")
					img.set_pixel(x, y, c)
		"deepstone":
			_speckle(img, r, [_c("#2b3048"), _c("#22263a"), _c("#3c4362"), _c("#5b4f73")], [0.5, 0.3, 0.16, 0.04])
		"sandstone_side":
			for y in 16:
				var band: Color = [_c("#e2b97c"), _c("#d6a96a"), _c("#ecc993")][(y / 3) % 3]
				for x in 16:
					img.set_pixel(x, y, band if r.randf() < 0.85 else _c("#c99a5e"))
		"sandstone_top":
			_speckle(img, r, [_c("#e6c085"), _c("#ddb577"), _c("#efcf98")], [0.6, 0.25, 0.15])
		"lilac_top":
			_speckle(img, r, [_c("#b79be0"), _c("#a789d6"), _c("#caaeea"), _c("#93c35a")], [0.42, 0.28, 0.22, 0.08])
			for i in 3:
				img.set_pixel(r.randi_range(1, 14), r.randi_range(1, 14), _c("#ffe08a"))
		"lilac_side":
			_soil(img, r)
			_moss_band(img, r, [_c("#b79be0"), _c("#a789d6"), _c("#caaeea")])
	return img

# ---------------------------------------------------------------- icons

static func icon(item_key: String) -> Texture2D:
	if _icons.has(item_key):
		return _icons[item_key]
	var Items := load("res://src/items.gd")
	var B := load("res://src/blocks.gd")
	var img: Image
	var info: Dictionary = Items.info(item_key)
	if info.get("kind", "") == "block":
		img = _cube_icon(int(info.block))
	else:
		img = _item_icon(item_key, info)
	var tex := ImageTexture.create_from_image(img)
	_icons[item_key] = tex
	return tex

static func _sample(layer: int, u: float, v: float) -> Color:
	var img: Image = block_images()[layer]
	return img.get_pixel(clampi(int(u * 16.0), 0, 15), clampi(int(v * 16.0), 0, 15))

static func _cube_icon(block: int) -> Image:
	var B := load("res://src/blocks.gd")
	var tex: Array = B.TEX[block]
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for py in 32:
		for px in 32:
			var p := Vector2(px + 0.5, py + 0.5)
			var col := Color(0, 0, 0, 0)
			# top face: origin (16,2), u along (14,7), v along (-14,7)
			var uv := _solve(p - Vector2(16, 2), Vector2(14, 7), Vector2(-14, 7))
			if _inside(uv):
				col = _sample(tex[0], uv.x, uv.y)
			else:
				uv = _solve(p - Vector2(2, 9), Vector2(14, 7), Vector2(0, 14))
				if _inside(uv):
					col = _sample(tex[1], uv.x, uv.y)
					col = Color(col.r * 0.78, col.g * 0.86, col.b * 0.9, col.a)
				else:
					uv = _solve(p - Vector2(16, 16), Vector2(14, -7), Vector2(0, 14))
					if _inside(uv):
						col = _sample(tex[1], uv.x, uv.y)
						col = Color(col.r * 0.6, col.g * 0.72, col.b * 0.8, col.a)
			if col.a > 0.0:
				col.a = max(col.a, 0.85)
			img.set_pixel(px, py, col)
	return img

static func _solve(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var det := a.x * b.y - a.y * b.x
	return Vector2((p.x * b.y - p.y * b.x) / det, (a.x * p.y - a.y * p.x) / det)

static func _inside(uv: Vector2) -> bool:
	return uv.x >= 0.0 and uv.x < 1.0 and uv.y >= 0.0 and uv.y < 1.0

static func _item_icon(key: String, info: Dictionary) -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var handle := _c("#8c5a3c")
	var tier_col := {1: _c("#d9a76a"), 2: _c("#8d93b3"), 3: _c("#ffd25e")}
	var head: Color = tier_col.get(int(info.get("tier", 1)), _c("#d9a76a"))
	var dark := head.darkened(0.3)
	var tool: String = info.get("tool", "")
	if tool != "":
		for i in 18:  # diagonal handle
			_dot(img, 7 + i, 25 - i, handle, 2)
		match tool:
			"pick":
				for i in 16:
					var x := 8 + i
					var y := 6 + int(abs(i - 8) * 0.45)
					_dot(img, x, y, head if i % 5 != 0 else dark, 3)
			"axe":
				for y in 4:
					for x in 9:
						_dot(img, 17 + x - y, 5 + y * 2, head if (x + y) % 6 != 0 else dark, 2)
			"spade":
				for y in 8:
					for x in 7:
						if abs(x - 3) <= 3 - y / 3:
							_dot(img, 20 + x, 3 + y, head if y < 6 else dark, 1)
			"blade":
				img.fill(Color(0, 0, 0, 0))
				for i in 16:
					_dot(img, 9 + i, 22 - i, head if i % 4 != 0 else dark, 2)
				for i in 6:
					_dot(img, 6 + i, 20 + int(i * 0.2), handle, 2)
				_dot(img, 8, 18, _c("#f48dab"), 2)
				_dot(img, 12, 24, _c("#f48dab"), 2)
		return img
	match key:
		"stick":
			for i in 18:
				_dot(img, 8 + i, 24 - i, handle, 2)
		"berries":
			for p in [Vector2i(10, 16), Vector2i(16, 13), Vector2i(19, 19), Vector2i(13, 21)]:
				for y in range(-3, 4):
					for x in range(-3, 4):
						if x * x + y * y <= 9:
							img.set_pixel(p.x + x, p.y + y, _c("#e4577f") if x + y < 2 else _c("#b8355f"))
				img.set_pixel(p.x - 1, p.y - 1, _c("#ffd0e4"))
			for i in 5:
				img.set_pixel(15 + i, 7 + i / 2, _c("#4fae84"))
		"ember", "sunmetal":
			var a := _c("#ff8a6b") if key == "ember" else _c("#ffd25e")
			var b := _c("#ffc27a") if key == "ember" else _c("#fff1a8")
			for y in range(-7, 8):
				for x in range(-7, 8):
					if abs(x) + abs(y) <= 7:
						img.set_pixel(16 + x, 16 + y, b if x + y < -2 else a)
			for y in range(-7, 8):
				img.set_pixel(16, 16 + y, a.darkened(0.25))
		_:
			img.fill(_c("#f48dab"))
	return img

static func _dot(img: Image, x: int, y: int, col: Color, size: int) -> void:
	for dy in size:
		for dx in size:
			var px := x + dx
			var py := y + dy
			if px >= 0 and py >= 0 and px < 32 and py < 32:
				img.set_pixel(px, py, col)
