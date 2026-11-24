# One player's heads-up display, drawn inside that player's own viewport and scaled to it,
# so the crosshair, hotbar and status stay inside each half of the screen at 720p and 1080p.
extends Control

const Items := preload("res://src/items.gd")
const Textures := preload("res://src/textures.gd")
const HEART := [".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."]
const BERRY := ["..#...", ".##.#.", "######", "######", ".####.", "..##.."]

var player: Node
var game: Node
var accent := Color("#8be8e7")
var last_slot := -1
var slot_name_time := 0.0
var tutorial_text := ""
var tutorial_hint := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	if player and player.hotbar != last_slot:
		last_slot = player.hotbar
		slot_name_time = 1.6
	slot_name_time = maxf(0.0, slot_name_time - delta)
	queue_redraw()

func ui_scale() -> float:
	return clampf(minf(size.y / 620.0, size.x / 560.0), 0.55, 1.7)

func _text(pos: Vector2, text: String, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var font := ThemeDB.fallback_font
	draw_string_outline(font, pos, text, align, width, fs, maxi(2, fs / 5), Color(0.04, 0.06, 0.12, 0.85))
	draw_string(font, pos, text, align, width, fs, col)

func _pixels(origin: Vector2, rows: Array, px: float, col: Color, empty := Color(0, 0, 0, 0)) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] == "#":
				draw_rect(Rect2(origin + Vector2(x, y) * px, Vector2(px, px)), col)
			elif empty.a > 0.0 and row[x] == "#":
				draw_rect(Rect2(origin + Vector2(x, y) * px, Vector2(px, px)), empty)

func _draw() -> void:
	if player == null:
		return
	var s := ui_scale()
	var fs := int(15 * s)
	var center := size / 2.0
	# damage vignette
	if player.hurt_flash > 0.0:
		var a: float = player.hurt_flash * 0.45
		var band := 60.0 * s
		for i in 6:
			var t := float(i) / 6.0
			var col := Color(0.95, 0.3, 0.45, a * (1.0 - t))
			var inset := band * t
			draw_rect(Rect2(inset, inset, size.x - inset * 2, band / 6.0), col)
			draw_rect(Rect2(inset, size.y - inset - band / 6.0, size.x - inset * 2, band / 6.0), col)
			draw_rect(Rect2(inset, inset, band / 6.0, size.y - inset * 2), col)
			draw_rect(Rect2(size.x - inset - band / 6.0, inset, band / 6.0, size.y - inset * 2), col)
	if player.fainted > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.15, 0.72))
		_text(Vector2(0, center.y - 10 * s), "%s fainted" % player.display_name(), int(30 * s), Color("#ffd2e3"), HORIZONTAL_ALIGNMENT_CENTER, size.x)
		_text(Vector2(0, center.y + 26 * s), "Waking up in %d…  Your things are in a keepsake bundle where you fell." % ceili(player.fainted), int(15 * s), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		return
	if player.resting:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.15, 0.55))
		_text(Vector2(0, center.y), "Resting… waiting for everyone to rest", int(18 * s), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	# crosshair
	var c := 9.0 * s
	var w := maxf(2.0, 2.0 * s)
	for r in [Rect2(center.x - c, center.y - w / 2, c * 2, w), Rect2(center.x - w / 2, center.y - c, w, c * 2)]:
		draw_rect(r.grow(1.5), Color(0.04, 0.06, 0.12, 0.6))
		draw_rect(r, Color(1, 1, 1, 0.92))
	if player.mine_progress > 0.01 and not player.creative:
		draw_arc(center, 16 * s, -PI / 2, -PI / 2 + TAU * clampf(player.mine_progress, 0, 1), 32, accent, 3.0 * s)
	if not player.target.is_empty():
		var B := load("res://src/blocks.gd")
		var tname: String = B.NAMES[int(player.target.id)]
		if not player.creative and not player.can_harvest(int(player.target.id)):
			tname += "  (needs a better pick)"
		_text(Vector2(0, center.y + 36 * s), tname, int(12 * s), Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	elif player.target_mob != null:
		_text(Vector2(0, center.y + 36 * s), String(player.target_mob.kind).capitalize(), int(12 * s), Color("#ffd2e3"), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	# hotbar
	var slot := 46.0 * s
	var gap := 4.0 * s
	var bar_w := slot * 9 + gap * 8
	var bar := Vector2(center.x - bar_w / 2, size.y - slot - 14 * s)
	draw_rect(Rect2(bar - Vector2(6, 6) * s, Vector2(bar_w + 12 * s, slot + 12 * s)), Color(0.06, 0.09, 0.18, 0.62))
	for i in 9:
		var r := Rect2(bar + Vector2(i * (slot + gap), 0), Vector2(slot, slot))
		draw_rect(r, Color(0.16, 0.2, 0.32, 0.75))
		var st: Dictionary = player.inventory.get_slot(i)
		if not st.is_empty():
			draw_texture_rect(Textures.icon(String(st.id)), r.grow(-5 * s), false)
			if player.creative:
				pass
			elif int(st.n) > 1:
				_text(r.position + Vector2(slot - 4 * s, slot - 5 * s), str(st.n), int(13 * s), Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, -1)
			if st.has("d"):
				var maxd := float(Items.info(String(st.id)).get("durability", 1))
				var f := clampf(float(st.d) / maxd, 0, 1)
				draw_rect(Rect2(r.position + Vector2(5 * s, slot - 7 * s), Vector2((slot - 10 * s), 3 * s)), Color(0, 0, 0, 0.6))
				draw_rect(Rect2(r.position + Vector2(5 * s, slot - 7 * s), Vector2((slot - 10 * s) * f, 3 * s)), Color("#8be8a0").lerp(Color("#ff8a6b"), 1.0 - f))
		if i == player.hotbar:
			draw_rect(r.grow(2 * s), accent, false, 3.0 * s)
	var sel: String = player.selected_key()
	if slot_name_time > 0.0 and sel != "":
		_text(Vector2(0, bar.y - (34 if not player.creative else 14) * s), Items.display_name(sel), int(14 * s), Color(1, 1, 1, minf(1.0, slot_name_time)), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	# health and food
	if not player.creative:
		var px := maxf(1.0, round(2.4 * s))
		for i in 10:
			var hp: int = player.health - i * 2
			var pos := bar + Vector2(i * 8.5 * px, -9 * px)
			_pixels(pos, HEART, px, Color(0.1, 0.1, 0.18, 0.7))
			if hp >= 2:
				_pixels(pos, HEART, px, Color("#ff7a9a"))
			elif hp == 1:
				_pixels(pos, HEART.slice(0, 3), px, Color("#ff7a9a"))
			var fd: int = player.food - i * 2
			var fpos := bar + Vector2(bar_w - (i + 1) * 8.5 * px, -9 * px)
			_pixels(fpos, BERRY, px, Color(0.1, 0.1, 0.18, 0.7))
			if fd >= 2:
				_pixels(fpos, BERRY, px, Color("#c9a0ea"))
			elif fd == 1:
				_pixels(fpos, BERRY.slice(3, 6), px, Color("#c9a0ea"))
	# status line
	var mode_text := "Creative" if player.creative else "Survival"
	var head := "%s  ·  %s" % [player.display_name(), mode_text]
	if game and game.has_method("clock_text"):
		head += "  ·  " + game.clock_text()
	_text(Vector2(14, 24) * s, head, fs, accent)
	if player.flying:
		_text(Vector2(14 * s, size.y - 80 * s), "Flying  (double-tap jump to land)", int(12 * s), Color.WHITE)
	if game and game.has_method("device_warning"):
		var warn: String = game.device_warning(player.player_number)
		if warn != "":
			draw_rect(Rect2(Vector2(0, center.y - 80 * s), Vector2(size.x, 34 * s)), Color(0.08, 0.1, 0.2, 0.8))
			_text(Vector2(0, center.y - 57 * s), warn, int(15 * s), Color("#ffce94"), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	# tutorial
	if tutorial_text != "":
		var box_w := minf(size.x - 28 * s, 420 * s)
		var box := Rect2(Vector2(14 * s, 34 * s), Vector2(box_w, 58 * s))
		draw_rect(box, Color(0.06, 0.09, 0.18, 0.72))
		draw_rect(Rect2(box.position, Vector2(4 * s, box.size.y)), Color("#ffd27a"))
		_text(box.position + Vector2(14 * s, 22 * s), tutorial_text, int(14 * s), Color("#fff2d6"), HORIZONTAL_ALIGNMENT_LEFT, box_w - 20 * s)
		_text(box.position + Vector2(14 * s, 44 * s), tutorial_hint, int(12 * s), Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_LEFT, box_w - 20 * s)
	# keepsake bundle compass
	if game and game.get("drops") and not player.creative:
		var b: Dictionary = game.drops.bundle_for(player.profile())
		if not b.is_empty():
			var to: Vector3 = b.pos - player.position
			var ang: float = atan2(to.x, -to.z) + player.yaw
			var p := Vector2(size.x - 60 * s, 70 * s)
			var tip := p + Vector2(sin(ang), -cos(ang)) * 16 * s
			draw_line(p, tip, Color("#ffd25e"), 4 * s)
			draw_circle(tip, 4 * s, Color("#ffd25e"))
			_text(Vector2(p.x - 80 * s, p.y + 32 * s), "Bundle %d m" % roundi(to.length()), int(12 * s), Color("#ffd25e"), HORIZONTAL_ALIGNMENT_CENTER, 160 * s)
	if player.notice_time > 0.0:
		_text(Vector2(0, bar.y - 52 * s), player.notice, int(16 * s), Color(1, 1, 1, minf(1.0, player.notice_time)), HORIZONTAL_ALIGNMENT_CENTER, size.x)
