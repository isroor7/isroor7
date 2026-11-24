# Ola and Naba as chunky voxel characters: head, torso, separate arms and legs on pivots,
# original nearest-filtered skins painted here, and procedural idle/walk/jump/mine/use animation.
extends Node3D

const VM := preload("res://src/voxel_model.gd")
const Items := preload("res://src/items.gd")
const Textures := preload("res://src/textures.gd")
const OLA := 0
const NABA := 1
const ATLAS := Vector2(64, 64)

var who := OLA
var head: Node3D
var torso: Node3D
var arm_r: Node3D
var arm_l: Node3D
var leg_r: Node3D
var leg_l: Node3D
var hand_r: Node3D
var held: MeshInstance3D
var held_key := ""
var tablet: Node3D
var mat: ShaderMaterial
var held_mat: ShaderMaterial
var phase := 0.0
var swing := 0.0
var use_pulse := 0.0
var flash_left := 0.0
var flash_color := Color(1, 0.35, 0.45)

static var _skins := {}

static func c(hex: String, glow := false) -> Color:
	var col := Color(hex)
	if glow:
		col.a = 0.8
	return col

func build(character: int, show_tablet := false) -> void:
	who = character
	mat = VM.material(skin(character))
	held_mat = VM.material(null)
	torso = _part(Vector3(0, 0.625, 0), 0, 16, 8, 10, 5, Vector3(-4, 0, -2.5))
	head = _part(Vector3(0, 1.25, 0), 0, 0, 8, 8, 8, Vector3(-4, 0, -4))
	if who == OLA:
		_part_on(torso, Vector3(0, 0.36, 0), 32, 0, 10, 4, 6, Vector3(-5, 0, -3))  # hijab drape over the shoulders
	else:
		_part_on(head, Vector3(0, 0.12, 0.25), 32, 10, 3, 6, 3, Vector3(-1.5, -2, 0))  # tied ponytail
	arm_r = _part(Vector3(0.34, 1.2, 0), 26, 16, 3, 10, 4, Vector3(-1.5, -9, -2))
	arm_l = _part(Vector3(-0.34, 1.2, 0), 40, 16, 3, 10, 4, Vector3(-1.5, -9, -2))
	leg_r = _part(Vector3(0.125, 0.625, 0), 0, 32, 4, 10, 5, Vector3(-2, -10, -2.5))
	leg_l = _part(Vector3(-0.125, 0.625, 0), 18, 32, 4, 10, 5, Vector3(-2, -10, -2.5))
	hand_r = Node3D.new()
	hand_r.position = Vector3(0, -0.56, -0.05)
	arm_r.add_child(hand_r)
	held = MeshInstance3D.new()
	held.material_override = held_mat
	held.visible = false
	hand_r.add_child(held)
	if who == NABA:
		tablet = _part_on(arm_l, Vector3(0.02, -0.5, -0.2), 36, 32, 6, 1, 4, Vector3(-3, 0, -2))
		tablet.rotation = Vector3(-1.2, 0.0, 0.0)
		tablet.visible = show_tablet

func _part(pivot: Vector3, u: int, v: int, w: int, h: int, d: int, lo: Vector3) -> Node3D:
	return _part_on(self, pivot, u, v, w, h, d, lo)

func _part_on(parent: Node3D, pivot: Vector3, u: int, v: int, w: int, h: int, d: int, lo: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position = pivot
	var mi := MeshInstance3D.new()
	mi.mesh = VM.box(u, v, w, h, d, lo, ATLAS)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	parent.add_child(node)
	return node

func set_tablet(on: bool) -> void:
	if tablet:
		tablet.visible = on

func set_held(item_key: String) -> void:
	if item_key == held_key:
		return
	held_key = item_key
	if item_key == "":
		held.visible = false
		return
	var info := Items.info(item_key)
	held.visible = true
	if info.get("kind", "") == "block":
		var B := load("res://src/blocks.gd")
		var img: Image = Textures.block_images()[B.TEX[int(info.block)][1]]
		held.mesh = VM.cube(Vector3(0.26, 0.26, 0.26), Vector3.ZERO)
		held_mat.set_shader_parameter("skin", ImageTexture.create_from_image(img))
		held.position = Vector3(0, -0.06, -0.12)
		held.rotation = Vector3(0.3, 0.6, 0)
	else:
		held.mesh = VM.slab(0.5, 0.04)
		held_mat.set_shader_parameter("skin", Textures.icon(item_key))
		held.position = Vector3(0, 0.12, -0.22)
		held.rotation = Vector3(0, PI / 2, -0.75)

func set_light(daylight: float, sky: float, block: float) -> void:
	for m in [mat, held_mat]:
		m.set_shader_parameter("daylight", daylight)
		m.set_shader_parameter("sky_light", sky)
		m.set_shader_parameter("block_light", block)

func hurt_flash(col := Color(1, 0.35, 0.45)) -> void:
	flash_left = 0.35
	flash_color = col

# state: speed (horizontal m/s), floor (bool), mining (bool), flying (bool), pitch (rad)
func animate(delta: float, state: Dictionary) -> void:
	var speed: float = state.get("speed", 0.0)
	var moving := clampf(speed / 4.5, 0.0, 1.0)
	phase += delta * (4.0 + speed * 1.6)
	swing = lerpf(swing, moving, minf(1.0, delta * 10.0))
	var s := sin(phase) * 0.75 * swing
	var breathe := sin(Time.get_ticks_msec() * 0.0025) * 0.025
	var airborne := not bool(state.get("floor", true)) and not bool(state.get("flying", false))
	leg_r.rotation.x = s
	leg_l.rotation.x = -s
	arm_l.rotation.x = -s * 0.8 + (-0.5 if airborne else 0.0)
	arm_l.rotation.z = -0.06 - breathe
	var right := s * 0.8
	if airborne:
		right = -0.5
		leg_r.rotation.x = -0.35
		leg_l.rotation.x = 0.25
	if bool(state.get("flying", false)):
		leg_r.rotation.x = 0.15
		leg_l.rotation.x = 0.1
	if bool(state.get("mining", false)):
		right = -1.3 + sin(Time.get_ticks_msec() * 0.016) * 0.65
	if use_pulse > 0.0:
		use_pulse = maxf(0.0, use_pulse - delta * 4.0)
		right = lerpf(right, -1.25, use_pulse)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, right, minf(1.0, delta * 18.0))
	arm_r.rotation.z = 0.06 + breathe
	torso.position.y = 0.625 + breathe * 0.4
	head.position.y = 1.25 + breathe * 0.4
	head.rotation.x = clampf(float(state.get("pitch", 0.0)) * 0.6, -0.6, 0.5)
	if tablet and tablet.visible:
		arm_l.rotation.x = lerpf(arm_l.rotation.x, -0.9, 0.7)
	if flash_left > 0.0:
		flash_left -= delta
		var a := clampf(flash_left / 0.35, 0.0, 1.0) * 0.65
		for m in [mat, held_mat]:
			m.set_shader_parameter("flash", Color(flash_color.r, flash_color.g, flash_color.b, a))

func pulse_use() -> void:
	use_pulse = 1.0

# ------------------------------------------------------------------ skins

static func skin(character: int) -> ImageTexture:
	if _skins.has(character):
		return _skins[character]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if character == OLA:
		_paint_ola(img)
	else:
		_paint_naba(img)
	var tex := ImageTexture.create_from_image(img)
	_skins[character] = tex
	return tex

static func _cross(x: int, y: int) -> bool:
	var px := x % 4
	var py := (y + 2 * ((x / 4) % 2)) % 4
	return (px == 1 and py >= 0 and py <= 2) or (py == 1 and px >= 0 and px <= 2)

static func _paint_ola(img: Image) -> void:
	var hijab := c("#d88ba5")
	var hijab_d := c("#bf6f8c")
	var hijab_l := c("#eaa8be")
	var skin_c := c("#c98b62")
	var skin_d := c("#b47750")
	var navy := c("#2b3270")
	var navy_d := c("#212656")
	var navy_l := c("#39438a")
	var lav := c("#b9a3d9")
	var lav_d := c("#a38dc6")
	var cream := c("#f6e9ef")
	var shoe := c("#8e7798")
	var cyan := c("#6ff3ff", true)
	var face := ["HHHHHHHH", "HHLLLLHH", "HHSSSSHH", "HSSSSSSH", "HSESSESH", "HSBSSBSH", "HSSMMSSH", "HHSSSSHH"]
	VM.paint_box(img, 0, 0, 8, 8, 8, func(f: String, x: int, y: int, w: int, h: int) -> Color:
		if f == "front":
			match face[y][x]:
				"S": return skin_c
				"E": return c("#2e1f2b")
				"B": return c("#d99079")
				"M": return c("#9c4f62")
				"L": return hijab_l
			return hijab if (x + y) % 5 != 0 else hijab_d
		if f == "top":
			return hijab_l if (x + y) % 3 != 0 else hijab
		if f == "left" or f == "right":
			return hijab_d if x == 3 and y > 2 else (hijab if y % 4 != 3 else hijab_d)
		return hijab if (x * 2 + y) % 7 != 0 else hijab_d)
	VM.paint_box(img, 32, 0, 10, 4, 6, func(f: String, x: int, y: int, w: int, h: int) -> Color:
		if f == "front":
			return hijab_l if abs(x - 4.5) < 2.5 - y * 0.6 else (hijab if (x + y) % 4 != 0 else hijab_d)
		return hijab if (x + y) % 4 != 0 else hijab_d)
	VM.paint_box(img, 0, 16, 8, 10, 5, func(f: String, x: int, y: int, w: int, h: int) -> Color:
		if y == h - 1:
			return navy_d
		if f == "front" and (x == 2 or x == 5) and y > 3 and y % 3 == 0:
			return navy_l
		return navy if (x + y * 3) % 7 != 0 else navy_d)
	for arm in [[26, true], [40, false]]:
		var with_light: bool = arm[1]
		VM.paint_box(img, arm[0], 16, 3, 10, 4, func(f: String, x: int, y: int, w: int, h: int) -> Color:
			if f == "bottom" or (f != "top" and y >= h - 2):
				return skin_c if y < h - 1 else skin_d
			if f == "top":
				return navy_l
			if y == h - 3:
				return cyan if with_light else navy_d
			return navy if (x + y) % 5 != 0 else navy_d)
	for leg in [0, 18]:
		VM.paint_box(img, leg, 32, 4, 10, 5, func(f: String, x: int, y: int, w: int, h: int) -> Color:
			if f == "bottom" or (f != "top" and y >= h - 2):
				return shoe if y < h - 1 else shoe.darkened(0.2)
			if f == "top":
				return lav_d
			return cream if _cross(x, y) else (lav if (x + y) % 6 != 0 else lav_d))

static func _paint_naba(img: Image) -> void:
	var hair := c("#2a2130")
	var hair_l := c("#3e3250")
	var sheen := c("#4c5378")
	var skin_c := c("#c78559")
	var skin_d := c("#b07148")
	var pink := c("#f27ca9")
	var pink_d := c("#d9608f")
	var white := c("#f7eef3")
	var white_d := c("#e6d4df")
	var star := c("#e4577f")
	var star_l := c("#ffd0e4")
	var shorts := c("#e86aa0")
	var face := ["HHHHHHHH", "HHGGHHHH", "HHHHHHSS", "HHHHSSSS", "HSESSESS", "HSBSSBSH", "SSSMMSSS", "SSSSSSSS"]
	VM.paint_box(img, 0, 0, 8, 8, 8, func(f: String, x: int, y: int, w: int, h: int) -> Color:
		if f == "front":
			match face[y][x]:
				"S": return skin_c
				"E": return c("#2a1d24")
				"B": return c("#d78a72")
				"M": return c("#a3505f")
				"G": return sheen
			return hair if (x + y) % 4 != 0 else hair_l
		if (f == "left" or f == "right") and y >= 4 and y <= 5 and x >= 2 and x <= 3:
			return skin_d
		if (f == "left" or f == "right") and y == 6 and x == 3:
			return c("#ffd25e")
		if f == "top":
			return sheen if x == 3 or x == 4 else hair
		return hair if (x * 3 + y) % 5 != 0 else hair_l)
	VM.paint_box(img, 32, 10, 3, 6, 3, func(f: String, x: int, y: int, w: int, h: int) -> Color:
		if y == 0 or f == "top":
			return pink
		return hair if (x + y) % 3 != 0 else hair_l)
	var star_rows := ["..#..", "..#..", "#####", ".###.", ".#.#.", "#...#"]
	VM.paint_box(img, 0, 16, 8, 10, 5, func(f: String, x: int, y: int, w: int, h: int) -> Color:
		if f == "front" and y == 0 and x >= 2 and x <= 5:
			return c("#3a2433")
		if f == "front" and y >= 3 and y <= 8 and x >= 2 and x <= 6:
			var ch: String = star_rows[y - 3][x - 2]
			if ch == "#":
				return star_l if y == 5 and x == 4 else star
		if y < 3:
			return pink if (x + y) % 6 != 0 else pink_d
		return white if (x + y) % 7 != 0 else white_d)
	var beads := [c("#f27ca9"), c("#ffe08a"), c("#7fe0e6"), c("#c9a0ea")]
	for arm in [[26, false], [40, true]]:
		var bracelet: bool = arm[1]
		VM.paint_box(img, arm[0], 16, 3, 10, 4, func(f: String, x: int, y: int, w: int, h: int) -> Color:
			if f == "top":
				return pink
			if y < 2:
				return white
			if y == 2:
				return pink
			if bracelet and y == h - 3:
				return beads[(x + (0 if f == "front" else 2)) % 4]
			return skin_c if (y < h - 1 or f == "top") else skin_d)
	for leg in [0, 18]:
		VM.paint_box(img, leg, 32, 4, 10, 5, func(f: String, x: int, y: int, w: int, h: int) -> Color:
			if f == "top":
				return shorts
			if f == "bottom":
				return white_d
			if y < 4:
				return shorts if (x + y) % 5 != 0 else pink_d
			if y < 8:
				return skin_c if y != 7 else skin_d
			if y == 8:
				return pink if f == "front" or x % 2 == 0 else white
			return white_d)
	VM.paint_box(img, 36, 32, 6, 1, 4, func(f: String, x: int, y: int, w: int, h: int) -> Color:
		if f == "top" and x >= 1 and x <= 4 and y >= 1 and y <= 2:
			return c("#cfeffd", true)
		if f == "top" and (x == 0 or x == 5) and y == 3:
			return c("#f7f2f5")
		return c("#7ccf4a") if (x + y) % 3 != 0 else c("#5ea838"))
