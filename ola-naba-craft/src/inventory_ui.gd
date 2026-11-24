# One player's inventory / crafting / creative palette screen, drawn inside their own viewport.
# Opening it pauses only that player's controls; the world keeps running. Navigated with that
# player's own devices (stick, d-pad, movement keys), plus the mouse for the mouse owner.
extends Control

const Items := preload("res://src/items.gd")
const Textures := preload("res://src/textures.gd")

var player: Node
var game: Node
var tab := 0              # 0 inventory, 1 crafting (or palette in Creative)
var cursor := 0
var holding := -1         # inventory slot picked up for moving
var recipe_scroll := 0
var at_bench := false
var prev := {}
var nav_prev := Vector2i.ZERO
var nav_timer := 0.0
var accent := Color("#8be8e7")
var message := ""
var message_time := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func open(bench: bool) -> void:
	at_bench = bench
	tab = 1 if (bench or player.creative) else 0
	cursor = 0
	holding = -1
	prev = {"jump": true, "inventory": true, "place": true, "down": true}
	visible = true
	queue_redraw()

func tabs() -> Array:
	return ["Inventory", "Palette"] if player.creative else ["Inventory", "Crafting" + (" (Workbench)" if bench_ok() else "")]

func bench_ok() -> bool:
	return at_bench or player.near_bench()

func recipes() -> Array:
	var out := []
	for r in Items.RECIPES:
		out.append(r)
	return out

func item_count() -> int:
	if tab == 0:
		return 36
	if player.creative:
		return Items.PALETTE.size()
	return recipes().size()

func ui_scale() -> float:
	return clampf(minf(size.x / 660.0, size.y / 460.0), 0.5, 1.6)

func _sfx(name: String) -> void:
	if game and game.get("audio"):
		game.audio.play(name, 0.7)

# Called each frame by game.gd with this player's input only. Returns false when closed.
func handle(inp: Dictionary, delta: float) -> bool:
	message_time = maxf(0.0, message_time - delta)
	var held: Dictionary = inp.get("held", {})
	var pressed := {}
	for a in held:
		pressed[a] = held[a] and not prev.get(a, false)
	prev = held.duplicate()
	if pressed.get("inventory", false) or (pressed.get("down", false) and holding < 0):
		return false
	if pressed.get("down", false):
		holding = -1
	if pressed.get("mine", false):
		_switch_tab(1)
	if pressed.get("place", false):
		_switch_tab(-1)
	var nav: Vector2i = inp.get("nav", Vector2i.ZERO)
	if nav != nav_prev:
		nav_timer = 0.0
		nav_prev = nav
		if nav != Vector2i.ZERO:
			_move(nav)
	elif nav != Vector2i.ZERO:
		nav_timer += delta
		if nav_timer > 0.32:
			nav_timer = 0.2
			_move(nav)
	if pressed.get("jump", false):
		accept()
	queue_redraw()
	return true

func _switch_tab(d: int) -> void:
	tab = posmod(tab + d, 2)
	cursor = 0
	holding = -1
	_sfx("ui_move")

func _move(nav: Vector2i) -> void:
	var cols := 1 if (tab == 1 and not player.creative) else 9
	var n := item_count()
	var next := cursor + nav.x + nav.y * cols
	if cols == 1:
		next = cursor + nav.y
		if nav.x != 0:
			_switch_tab(nav.x)
			return
	cursor = clampi(next, 0, n - 1)
	_sfx("ui_move")

func _grid_slot(i: int) -> int:
	# grid rows 0-2 are storage (slots 9-35), row 3 is the hotbar (slots 0-8)
	return i + 9 if i < 27 else i - 27

func accept() -> void:
	if tab == 0:
		var slot := _grid_slot(cursor)
		if holding < 0:
			if not player.inventory.get_slot(slot).is_empty():
				holding = slot
				_sfx("ui_ok")
		else:
			player.inventory.move(holding, slot)
			holding = -1
			_sfx("ui_ok")
	elif player.creative:
		var key: String = Items.PALETTE[cursor]
		player.inventory.set_slot(player.hotbar, {"id": key, "n": 1})
		player.stats["palette"] = 1
		_flash("%s → hotbar slot %d" % [Items.display_name(key), player.hotbar + 1])
		_sfx("ui_ok")
	else:
		var r: Dictionary = recipes()[cursor]
		if player.craft(r.id, bench_ok()):
			_flash("Crafted %d %s" % [r.n, Items.display_name(r.out)])
		else:
			_flash(_why_not(r))
			_sfx("ui_back")

func _why_not(r: Dictionary) -> String:
	if r.station == "bench" and not bench_ok():
		return "Needs a Workbench nearby"
	for k in r.needs:
		if player.inventory.count(k) < int(r.needs[k]):
			return "Needs %d more %s" % [int(r.needs[k]) - player.inventory.count(k), Items.display_name(k)]
	return "No room in your inventory"

func _flash(text: String) -> void:
	message = text
	message_time = 2.2

# ------------------------------------------------------------------ layout and drawing

func _panel() -> Rect2:
	var s := ui_scale()
	var w := minf(size.x - 20 * s, 620 * s)
	var h := minf(size.y - 20 * s, 410 * s)
	return Rect2((size - Vector2(w, h)) / 2, Vector2(w, h))

func _cells() -> Array:
	var s := ui_scale()
	var p := _panel()
	var out := []
	var top := p.position + Vector2(16 * s, 64 * s)
	if tab == 0 or player.creative:
		var n := item_count()
		var cell := minf(46 * s, (p.size.x - 32 * s) / 9.0 - 4 * s)
		for i in n:
			var col := i % 9
			var row := i / 9
			var extra := 10 * s if (tab == 0 and row == 3) else 0.0
			out.append(Rect2(top + Vector2(col * (cell + 4 * s), row * (cell + 4 * s) + extra), Vector2(cell, cell)))
	else:
		var rows := int((p.size.y - 90 * s) / (26 * s))
		recipe_scroll = clampi(recipe_scroll, maxi(0, cursor - rows + 1), cursor)
		for i in item_count():
			var vis := i - recipe_scroll
			if vis < 0 or vis >= rows:
				out.append(Rect2())
			else:
				out.append(Rect2(top + Vector2(0, vis * 26 * s), Vector2(p.size.x * 0.48, 24 * s)))
	return out

func _text(pos: Vector2, text: String, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(ThemeDB.fallback_font, pos, text, align, width, fs, col)

func _draw() -> void:
	if player == null:
		return
	var s := ui_scale()
	var p := _panel()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.11, 0.45))
	draw_rect(p, Color(0.07, 0.1, 0.2, 0.95))
	draw_rect(p, accent.darkened(0.2), false, 2.0 * s)
	var names := tabs()
	for i in names.size():
		var tr := Rect2(p.position + Vector2(16 * s + i * 190 * s, 14 * s), Vector2(180 * s, 32 * s))
		draw_rect(tr, accent if i == tab else Color(0.16, 0.2, 0.32))
		_text(tr.position + Vector2(0, 22 * s), names[i], int(15 * s), Color("#0b1222") if i == tab else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)
	var cells := _cells()
	if tab == 0 or player.creative:
		for i in cells.size():
			var r: Rect2 = cells[i]
			draw_rect(r, Color(0.16, 0.2, 0.32))
			var key := ""
			var n := 0
			if tab == 0:
				var st: Dictionary = player.inventory.get_slot(_grid_slot(i))
				key = String(st.get("id", ""))
				n = int(st.get("n", 0))
				if _grid_slot(i) == holding:
					draw_rect(r, Color("#ffd27a"), false, 3 * s)
			else:
				key = Items.PALETTE[i]
			if key != "":
				draw_texture_rect(Textures.icon(key), r.grow(-5 * s), false)
				if n > 1 and not player.creative:
					_text(r.position + Vector2(r.size.x - 4 * s, r.size.y - 5 * s), str(n), int(12 * s), Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
			if i == cursor:
				draw_rect(r.grow(2 * s), accent, false, 3 * s)
		var sel := ""
		if tab == 0:
			sel = String(player.inventory.get_slot(_grid_slot(cursor)).get("id", ""))
		else:
			sel = Items.PALETTE[cursor]
		var help := "Select: %s   Move tab: %s / %s   Close: %s" % [_g("jump"), _g("place"), _g("mine"), _g("inventory")]
		if tab == 0:
			help = ("Place it: %s" % _g("jump") if holding >= 0 else "Pick up: %s" % _g("jump")) + "   Tabs: %s / %s   Close: %s" % [_g("place"), _g("mine"), _g("inventory")]
		_text(p.position + Vector2(16 * s, p.size.y - 40 * s), Items.display_name(sel) if sel != "" else "", int(15 * s), Color("#fff2d6"))
		_text(p.position + Vector2(16 * s, p.size.y - 16 * s), help, int(12 * s), Color(1, 1, 1, 0.7))
		if tab == 0:
			_text(cells[27].position - Vector2(0, 2 * s), "Hotbar", int(11 * s), Color(1, 1, 1, 0.6))
	else:
		var list := recipes()
		for i in cells.size():
			var r: Rect2 = cells[i]
			if r.size == Vector2.ZERO:
				continue
			var rec: Dictionary = list[i]
			var ok: bool = player.can_craft(rec.id, bench_ok())
			if i == cursor:
				draw_rect(r, accent.darkened(0.45))
			draw_texture_rect(Textures.icon(rec.out), Rect2(r.position + Vector2(2, 2) * s, Vector2(20, 20) * s), false)
			var label := "%s ×%d" % [Items.display_name(rec.out), rec.n]
			if rec.station == "bench":
				label += "  ⌂"
			_text(r.position + Vector2(28 * s, 17 * s), label, int(13 * s), Color.WHITE if ok else Color(1, 1, 1, 0.4))
		var rec: Dictionary = list[cursor]
		var gx := p.position + Vector2(p.size.x * 0.56, 70 * s)
		var cell := 40 * s
		_text(gx - Vector2(0, 10 * s), "Recipe", int(12 * s), Color(1, 1, 1, 0.6))
		for y in 3:
			for x in 3:
				var cr := Rect2(gx + Vector2(x * (cell + 4 * s), y * (cell + 4 * s)), Vector2(cell, cell))
				draw_rect(cr, Color(0.16, 0.2, 0.32))
				var ch: String = rec.pattern[y][x]
				if ch != " ":
					draw_texture_rect(Textures.icon(rec.legend[ch]), cr.grow(-4 * s), false)
		var arrow := gx + Vector2(3 * (cell + 4 * s) + 8 * s, cell * 1.5)
		_text(arrow + Vector2(0, 6 * s), "→", int(22 * s), accent)
		var out_r := Rect2(arrow + Vector2(28 * s, -cell / 2), Vector2(cell, cell))
		draw_rect(out_r, Color(0.16, 0.2, 0.32))
		draw_texture_rect(Textures.icon(rec.out), out_r.grow(-4 * s), false)
		var ny := gx.y + 3 * (cell + 4 * s) + 20 * s
		for k in rec.needs:
			var have: int = player.inventory.count(k)
			var need := int(rec.needs[k])
			_text(Vector2(gx.x, ny), "%s  %d / %d" % [Items.display_name(k), have, need], int(13 * s), Color("#8be8a0") if have >= need else Color("#ff9aa8"))
			ny += 18 * s
		if rec.station == "bench":
			_text(Vector2(gx.x, ny), "⌂ needs a Workbench nearby" + ("  ✓" if bench_ok() else ""), int(12 * s), Color("#ffd27a"))
		_text(p.position + Vector2(16 * s, p.size.y - 16 * s), "Craft: %s   Tabs: %s / %s   Close: %s" % [_g("jump"), _g("place"), _g("mine"), _g("inventory")], int(12 * s), Color(1, 1, 1, 0.7))
	if message_time > 0.0:
		_text(Vector2(p.position.x, p.position.y + p.size.y - 40 * s), message, int(15 * s), Color("#ffd27a", minf(1.0, message_time)), HORIZONTAL_ALIGNMENT_RIGHT, p.size.x - 16 * s)

func _g(action: String) -> String:
	if game and game.get("router"):
		return game.router.glyph(player.player_number, action, true)
	return action

func _gui_input(event: InputEvent) -> void:
	if not (game and game.has_method("owns_mouse") and game.owns_mouse(player.player_number)):
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p := _panel()
		var s := ui_scale()
		for i in 2:
			if Rect2(p.position + Vector2(16 * s + i * 190 * s, 14 * s), Vector2(180 * s, 32 * s)).has_point(event.position):
				if i != tab:
					_switch_tab(i - tab)
				accept_event()
				return
		var cells := _cells()
		for i in cells.size():
			if (cells[i] as Rect2).has_point(event.position):
				cursor = i
				accept()
				accept_event()
				queue_redraw()
				return
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and tab == 1:
		_move(Vector2i(0, 1))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP and tab == 1:
		_move(Vector2i(0, -1))
