# Title, worlds, settings, controls, credits and pause screens. Every screen is a column of
# focusable buttons, so it works with a d-pad/stick and A/B as well as mouse and keyboard.
extends Node

const Router := preload("res://src/input_router.gd")
const Settings := preload("res://src/settings.gd")
const LOGO := preload("res://assets/logo.png")
const OLA_BADGE := preload("res://assets/ola.svg")
const NABA_BADGE := preload("res://assets/naba.svg")
const NAVY := Color("#101d34")
const TEAL := Color("#8be8e7")
const ROSE := Color("#ffb7d0")
const GOLD := Color("#ffce94")

var game: Node
var theme: Theme
var back_action := Callable()
var root: Control
var banner: Label
var capture := {}            # remap in progress: {profile, action, button}
var devices_refresh := Callable()
var settings_section := "video"

func _init(g: Node) -> void:
	game = g
	g.add_child(self)
	theme = _make_theme()

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#1b2b4b")
	normal.border_color = Color("#2f4a73")
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(10)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = ROSE
	focus.set_border_width_all(3)
	focus.bg_color = Color("#243a63")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#2d4f7e")
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("#141f36")
	disabled.border_color = Color("#1f2c45")
	for type in ["Button", "OptionButton", "CheckButton", "LineEdit"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, focus)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_color("font_color", type, Color("#eaf6fe"))
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(1, 1, 1, 0.35))
	t.set_stylebox("read_only", "LineEdit", disabled)
	t.set_color("font_color", "Label", Color("#dce9f5"))
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color("#2f4a73")
	slider.set_content_margin_all(4)
	t.set_stylebox("slider", "HSlider", slider)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = TEAL
	t.set_stylebox("grabber_area", "HSlider", grabber)
	t.set_stylebox("grabber_area_highlight", "HSlider", grabber)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.1, 0.2, 0.92)
	panel.border_color = Color("#2f4a73")
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(10)
	panel.set_content_margin_all(22)
	t.set_stylebox("panel", "PanelContainer", panel)
	return t

func clear() -> void:
	capture = {}
	devices_refresh = Callable()
	back_action = Callable()
	for c in game.menus.get_children():
		game.menus.remove_child(c)
		c.queue_free()
	root = null

func back() -> void:
	if not capture.is_empty():
		return
	if back_action.is_valid():
		game.audio.play("ui_back")
		back_action.call()

# A screen: full-rect background (or a dim veil over the game) with a centered column.
func _screen(dim := false, width := 560.0) -> VBoxContainer:
	clear()
	root = Control.new()
	root.theme = theme
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.menus.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.11, 0.82) if dim else NAVY
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	if not dim:
		_decorate(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Vector2(0, 0)
	scroll.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(width, 0)
	center.add_child(col)
	scroll.ready.connect(func(): center.custom_minimum_size = scroll.size)
	return col

func _decorate(bg: ColorRect) -> void:
	# a few floating blocks in the logo's colours
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 14:
		var r := ColorRect.new()
		var s := rng.randf_range(10, 26)
		r.size = Vector2(s, s)
		r.color = [Color("#fce598"), Color("#5bdadf"), Color("#f48dab"), Color("#c9a0ea")][i % 4]
		r.color.a = 0.13
		r.anchor_left = rng.randf()
		r.anchor_top = rng.randf()
		r.anchor_right = r.anchor_left
		r.anchor_bottom = r.anchor_top
		r.rotation = rng.randf_range(-0.4, 0.4)
		bg.add_child(r)

func label(parent: Node, text: String, size := 18, col := Color("#dce9f5"), align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l

func button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	b.pressed.connect(func():
		game.audio.play("ui_ok", 0.7)
		action.call())
	b.focus_entered.connect(func(): game.audio.play("ui_move", 0.4))
	parent.add_child(b)
	return b

func _focus_later(c: Control) -> void:
	(func():
		if is_instance_valid(c) and c.is_inside_tree():
			c.grab_focus()).call_deferred()

func _focus_first(col: Control) -> void:
	for c in col.find_children("*", "BaseButton", true, false):
		if not (c as BaseButton).disabled:
			_focus_later((c as Control))
			return

# ------------------------------------------------------------------ title

func title() -> void:
	var col := _screen(false, 600)
	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.custom_minimum_size = Vector2(600, 180)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	col.add_child(logo)
	label(col, "BUILD TOGETHER  ·  SURVIVE THE NIGHT", 18, TEAL)
	var cast := HBoxContainer.new()
	cast.alignment = BoxContainer.ALIGNMENT_CENTER
	cast.add_theme_constant_override("separation", 28)
	col.add_child(cast)
	for c in [[OLA_BADGE, "OLA", TEAL], [NABA_BADGE, "NABA", ROSE]]:
		var stack := VBoxContainer.new()
		cast.add_child(stack)
		var badge := TextureRect.new()
		badge.texture = c[0]
		badge.custom_minimum_size = Vector2(72, 72)
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		stack.add_child(badge)
		label(stack, c[1], 15, c[2])
	button(col, "Play", worlds)
	button(col, "Settings", func(): settings_screen(title))
	button(col, "Controls", func(): controls_screen(title))
	button(col, "Credits", credits)
	button(col, "Quit", func(): game.get_tree().quit())
	banner = label(col, game.status, 16, GOLD)
	label(col, "Offline · no account · keyboard, mouse and controllers", 13, Color("#91a9c6"))
	back_action = Callable()
	_focus_first(col)

# ------------------------------------------------------------------ worlds

func worlds() -> void:
	var col := _screen(false, 640)
	label(col, "Worlds", 34, TEAL)
	var legacy: Dictionary = game.saves.legacy_status()
	if legacy.get("present", false):
		if not legacy.get("valid", false):
			label(col, "An old starter save was found but could not be read. It was left exactly as it was.", 15, GOLD)
		elif legacy.get("imported_id", "") == "":
			label(col, "A save from the starter version was found. Import copies it into a new world slot; the old file is never changed.", 15, GOLD)
			button(col, "Import starter world", func():
				var id: String = game.saves.import_legacy()
				if id == "":
					game.status = "Import failed; nothing was changed."
					worlds()
				else:
					world_detail(id))
	button(col, "+ New world", new_world)
	var list: Array = game.saves.list()
	if list.is_empty():
		label(col, "No worlds yet. Make one to start.", 16)
	for w in list:
		var text := "%s   ·   %s" % [w.get("name", "World"), "Creative" if w.get("rules", "") == "creative" else "Survival"]
		if w.has("error"):
			text = "%s   ·   cannot open (%s)" % [w.get("name", w.id), w.error]
		else:
			text += "   ·   Day %d   ·   %s" % [int(w.get("day", 1)), _date(float(w.get("last_played", 0)))]
		var id: String = w.id
		var b := button(col, text, func(): world_detail(id))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button(col, "Back", title)
	banner = label(col, game.status, 15, GOLD)
	game.status = ""
	back_action = title
	_focus_first(col)

func _date(unix: float) -> String:
	if unix <= 0:
		return "never played"
	var d := Time.get_datetime_dict_from_unix_time(int(unix))
	return "%04d-%02d-%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]

func world_detail(id: String) -> void:
	var data: Dictionary = game.saves.load_world(id)
	var col := _screen(false, 600)
	if data.has("error"):
		label(col, "This world cannot be opened: %s." % data.error, 18, GOLD)
		label(col, "Its files were left untouched.", 15)
		button(col, "Delete this world…", func(): _confirm_delete(id, "this world"))
		button(col, "Back", worlds)
		back_action = worlds
		_focus_first(col)
		return
	var name: String = data.get("name", "World")
	label(col, name, 32, TEAL)
	var rules := "Creative: unlimited blocks, flight, no damage" if data.rules == "creative" else "Survival: gather, craft and get through the night"
	label(col, rules, 16)
	var present := (data.get("players", {}) as Dictionary).keys()
	label(col, "Seed %d · Day %d · Saved characters: %s" % [int(data.seed), int(float(data.get("time", 0)) / 600.0) + 1, ", ".join(present.map(func(k): return String(k).capitalize())) if not present.is_empty() else "none yet"], 14, Color("#91a9c6"))
	if data.get("imported_from", {}).has("file"):
		label(col, "Imported from the starter save. The original file is unchanged.", 13, Color("#91a9c6"))
	button(col, "Play as Ola", func(): game.start_session(id, game.saves.load_world(id), false, false, 0))
	button(col, "Play as Naba", func(): game.start_session(id, game.saves.load_world(id), false, false, 1))
	button(col, "Play together · side by side", func(): devices_screen(id, false))
	button(col, "Play together · top and bottom", func(): devices_screen(id, true))
	button(col, "Rename", func(): rename_screen(id, name))
	button(col, "Delete…", func(): _confirm_delete(id, name))
	button(col, "Back", worlds)
	back_action = worlds
	_focus_first(col)

func _confirm_delete(id: String, name: String) -> void:
	confirm("Delete \"%s\"? This removes the world and its backup for good." % name, "Delete world", func():
		game.saves.delete(id)
		game.status = "Deleted %s." % name
		worlds(), func(): world_detail(id))

func rename_screen(id: String, current: String) -> void:
	var col := _screen(false, 520)
	label(col, "Rename world", 28, TEAL)
	var edit := LineEdit.new()
	edit.text = current
	edit.max_length = 40
	edit.custom_minimum_size.y = 44
	col.add_child(edit)
	button(col, "Save name", func():
		if edit.text.strip_edges() != "":
			game.saves.rename(id, edit.text.strip_edges())
		world_detail(id))
	button(col, "Cancel", func(): world_detail(id))
	back_action = func(): world_detail(id)
	_focus_later(edit)

func new_world() -> void:
	var col := _screen(false, 560)
	label(col, "New world", 32, TEAL)
	label(col, "Name", 15, Color("#91a9c6"), HORIZONTAL_ALIGNMENT_LEFT)
	var names := ["Golden Meadow", "Lilac Hollow", "Turquoise Shore", "Honey Hills", "Rosewood Vale", "Amber Dunes"]
	var name_edit := LineEdit.new()
	name_edit.text = "%s %d" % [names[randi() % names.size()], game.saves.list().size() + 1]
	name_edit.custom_minimum_size.y = 44
	name_edit.max_length = 40
	col.add_child(name_edit)
	var rules := ["survival"]
	var rules_row := HBoxContainer.new()
	rules_row.add_theme_constant_override("separation", 10)
	col.add_child(rules_row)
	var surv := button(rules_row, "● Survival", func(): pass)
	var crea := button(rules_row, "○ Creative", func(): pass)
	surv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crea.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surv.pressed.connect(func():
		rules[0] = "survival"
		surv.text = "● Survival"
		crea.text = "○ Creative")
	crea.pressed.connect(func():
		rules[0] = "creative"
		surv.text = "○ Survival"
		crea.text = "● Creative")
	label(col, "Seed (same seed, same world)", 15, Color("#91a9c6"), HORIZONTAL_ALIGNMENT_LEFT)
	var seed_edit := LineEdit.new()
	seed_edit.text = str(randi() % 999999)
	seed_edit.custom_minimum_size.y = 44
	col.add_child(seed_edit)
	button(col, "Create world", func():
		var s := int(seed_edit.text) if seed_edit.text.is_valid_int() else seed_edit.text.hash()
		var id: String = game.saves.create(name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "World", rules[0], s)
		if id == "":
			game.status = "Could not create the world folder."
			worlds()
		else:
			world_detail(id))
	button(col, "Back", worlds)
	back_action = worlds
	_focus_later(surv)

# ------------------------------------------------------------------ device assignment for split

func devices_screen(id: String, top_bottom: bool) -> void:
	game.router.assign(2)
	game.router.apply_settings(game.settings)
	var col := _screen(false, 640)
	label(col, "Who plays with what?", 30, TEAL)
	label(col, "Press any button on a free controller to hand it to a player without one. A single controller goes to Naba (player 2).", 15)
	var info := VBoxContainer.new()
	col.add_child(info)
	devices_refresh = func():
		for c in info.get_children():
			c.queue_free()
		for i in 2:
			label(info, "%s (player %d):  %s" % [["Ola", "Naba"][i], i + 1, game.router.device_label(i)], 17, [TEAL, ROSE][i], HORIZONTAL_ALIGNMENT_LEFT)
	devices_refresh.call()
	button(col, "Swap controllers between players", func():
		game.router.swap_pads()
		devices_refresh.call())
	button(col, "Start", func():
		game.keep_assignment = true
		game.start_session(id, game.saves.load_world(id), true, top_bottom, 0))
	button(col, "Back", func(): world_detail(id))
	label(col, "Ola: keyboard left side (WASD) and mouse. Naba: keyboard right side (IJKL, arrows) when no controller.", 13, Color("#91a9c6"))
	back_action = func(): world_detail(id)
	_focus_first(col)

func refresh_devices() -> void:
	if devices_refresh.is_valid():
		devices_refresh.call()

func _input(event: InputEvent) -> void:
	if not capture.is_empty():
		_capture_input(event)
		return
	if devices_refresh.is_valid() and event is InputEventJoypadButton and event.pressed and event.button_index != JOY_BUTTON_A:
		if game.router.owner_of_pad(event.device) < 0 and game.router.offer_pad(event.device) >= 0:
			devices_refresh.call()

# ------------------------------------------------------------------ settings

func settings_screen(on_back: Callable, dim := false) -> void:
	var col := _screen(dim, 640)
	label(col, "Settings", 30, TEAL)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	col.add_child(tabs)
	var s: Dictionary = game.settings
	var leave := func():
		game.save_settings()
		on_back.call()
	for sec in [["video", "Video"], ["audio", "Audio"], ["p1", "Player 1"], ["p2", "Player 2"], ["keys", "Keys"]]:
		var key: String = sec[0]
		var b := button(tabs, sec[1], func():
			settings_section = key
			settings_screen(on_back, dim))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if key == settings_section:
			b.add_theme_color_override("font_color", ROSE)
			_focus_later(b)
	match settings_section:
		"video":
			_slider(col, "View distance (chunks)", 3, 12, 1, float(s.view_distance), func(v): s.view_distance = int(v))
			_check(col, "Fullscreen", bool(s.fullscreen), func(v): s.fullscreen = v)
			_check(col, "V-Sync", bool(s.vsync), func(v): s.vsync = v)
			_check(col, "Split screen top/bottom by default", bool(s.stacked), func(v): s.stacked = v)
			_check(col, "Naba carries her green tablet", bool(s.naba_tablet), func(v): s.naba_tablet = v)
			label(col, "View distance applies the next time a world opens.", 13, Color("#91a9c6"))
		"audio":
			_slider(col, "Volume", 0, 1, 0.05, float(s.master_volume), func(v):
				s.master_volume = v
				AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.001))))
		"p1", "p2":
			var pi := 0 if settings_section == "p1" else 1
			var ps: Dictionary = s.players[pi]
			if pi == 0:
				_slider(col, "Mouse sensitivity", 0.2, 3.0, 0.05, float(ps.sens_mouse), func(v): ps.sens_mouse = v)
			_slider(col, "Stick / arrow-key look speed", 0.2, 3.0, 0.05, float(ps.sens_stick), func(v): ps.sens_stick = v)
			_slider(col, "Stick deadzone", 0.05, 0.6, 0.01, float(ps.deadzone), func(v): ps.deadzone = v)
			_check(col, "Invert vertical look", bool(ps.invert_y), func(v): ps.invert_y = v)
		"keys":
			_remap_list(col)
	button(col, "Done", leave)
	back_action = leave

func _slider(parent: Node, text: String, lo: float, hi: float, step: float, value: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := label(row, "", 16, Color("#dce9f5"), HORIZONTAL_ALIGNMENT_LEFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = value
	sl.custom_minimum_size = Vector2(240, 32)
	sl.focus_mode = Control.FOCUS_ALL
	row.add_child(sl)
	l.text = "%s: %s" % [text, str(snappedf(value, step))]
	sl.value_changed.connect(func(v):
		l.text = "%s: %s" % [text, str(snappedf(v, step))]
		on_change.call(v))

func _check(parent: Node, text: String, value: bool, on_change: Callable) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = value
	c.custom_minimum_size.y = 40
	c.toggled.connect(func(v): on_change.call(v))
	parent.add_child(c)

func _remap_list(col: Node) -> void:
	label(col, "Choose an action, then press the new key or controller button. Escape cancels.", 14, Color("#91a9c6"))
	for profile in [["kb1", "Player 1 keyboard"], ["kb2", "Player 2 keyboard"], ["pad", "Controllers"]]:
		label(col, profile[1], 18, TEAL, HORIZONTAL_ALIGNMENT_LEFT)
		for action in Router.REMAPPABLE:
			var codes: Array = game.router.bindings[profile[0]].get(action, [])
			var shown := "—"
			if not codes.is_empty():
				shown = Router.pad_name(codes[0]) if profile[0] == "pad" else OS.get_keycode_string(int(codes[0]))
			var b := button(col, "%s:  %s" % [Router.LABELS[action], shown], func(): pass)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var prof: String = profile[0]
			var act: String = action
			b.pressed.connect(func():
				capture = {"profile": prof, "action": act, "button": b}
				b.text = "%s:  press a %s…" % [Router.LABELS[act], "controller button" if prof == "pad" else "key"])
	button(col, "Reset all controls to defaults", func():
		game.settings.bindings = {}
		game.router.reset_bindings()
		settings_screen(back_action, false))

func _capture_input(event: InputEvent) -> void:
	var prof: String = capture.profile
	var code = null
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			capture = {}
			settings_screen(back_action, game.session_active())
			get_viewport().set_input_as_handled()
			return
		if prof != "pad":
			code = int(event.physical_keycode)
	elif event is InputEventJoypadButton and event.pressed and prof == "pad":
		code = int(event.button_index)
	if code == null:
		return
	get_viewport().set_input_as_handled()
	var act: String = capture.action
	var codes: Array = game.router.bindings[prof].get(act, []).duplicate()
	if codes.is_empty():
		codes = [code]
	else:
		codes[0] = code
	game.router.bindings[prof][act] = codes
	if not game.settings.bindings.has(prof):
		game.settings.bindings[prof] = {}
	game.settings.bindings[prof][act] = codes
	capture = {}
	game.save_settings()
	settings_screen(back_action, game.session_active())

# ------------------------------------------------------------------ info screens

func controls_screen(on_back: Callable) -> void:
	var col := _screen(false, 760)
	label(col, "Controls", 30, TEAL)
	var rows := [
		["Action", "Player 1", "Player 2 (shared keyboard)", "Controller"],
		["Walk", "W A S D", "I J K L", "Left stick"],
		["Look", "Mouse", "Arrow keys", "Right stick"],
		["Jump / swim / fly up", "Space", "Enter", "A / Cross"],
		["Fly down, close menus", "Shift", "P", "B / Circle"],
		["Mine / attack (hold)", "Left click or Q", ",", "RB / R1 or RT"],
		["Place / use block", "Right click or E", ".", "LB / L1 or LT"],
		["Hotbar", "Wheel, 1-9 via R / F", "/ and \\", "D-pad left / right"],
		["Inventory and crafting", "C or Tab", "M", "Y / Triangle"],
		["Eat held food", "G", "N", "X / Square"],
		["Pause", "Esc", "Esc", "Start"],
		["Creative: fly", "Double-tap jump", "Double-tap jump", "Double-tap A"],
	]
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)
	for r in rows.size():
		for c in rows[r]:
			label(grid, c, 15, TEAL if r == 0 else Color("#dce9f5"), HORIZONTAL_ALIGNMENT_LEFT)
	label(col, "Keys and buttons can be changed in Settings → Keys.", 14, Color("#91a9c6"))
	button(col, "Back", on_back)
	back_action = on_back
	_focus_first(col)

func credits() -> void:
	var col := _screen(false, 620)
	label(col, "Credits", 30, TEAL)
	label(col, "Ola-Naba Craft", 22, GOLD)
	label(col, "Starring Ola and Naba.", 16)
	label(col, "Game code, pixel art, textures, creatures, characters and sound effects are original and made for this game in code. No assets from other games are used.", 15)
	label(col, "Logo and character badges: the Ola-Naba Craft starter pack.", 15)
	label(col, "Built with Godot Engine (MIT licence, godotengine.org).", 15)
	label(col, "Not affiliated with or endorsed by any console or game maker.", 13, Color("#91a9c6"))
	button(col, "Back", title)
	back_action = title
	_focus_first(col)

# ------------------------------------------------------------------ pause and confirm

func pause() -> void:
	var col := _screen(true, 520)
	label(col, "Paused", 32, TEAL)
	label(col, "%s  ·  %s" % [game.session_data.get("name", "World"), game.clock_text()], 15, Color("#91a9c6"))
	button(col, "Resume", func(): game.set_pause(false))
	button(col, "Save now", func():
		banner.text = "Saved." if game.save_world() else "Could not save; check disk space.")
	button(col, "Settings", func(): settings_screen(func(): pause(), true))
	button(col, "Controls", func(): controls_screen(func(): pause()))
	for i in game.players.size():
		var p = game.players[i]
		var idx: int = i
		if p.tutorial_done:
			button(col, "Replay tutorial for %s" % p.display_name(), func():
				game.set_tutorial(idx, true)
				game.set_pause(false))
		else:
			button(col, "Skip tutorial for %s" % p.display_name(), func():
				game.set_tutorial(idx, false)
				game.set_pause(false))
	button(col, "Save and return to title", func():
		if game.save_world():
			game.end_session()
			title()
		else:
			banner.text = "Could not save, so the world is still open.")
	button(col, "Return to title without saving…", func():
		confirm("Leave without saving? Changes since the last save (autosave runs every minute) will be lost.", "Leave without saving", func():
			game.end_session()
			title(), func(): pause()))
	banner = label(col, "", 15, GOLD)
	back_action = func(): game.set_pause(false)
	_focus_first(col)

func confirm(text: String, yes_text: String, on_yes: Callable, on_no: Callable) -> void:
	var col := _screen(game.session_active(), 520)
	label(col, text, 18, GOLD)
	var no := button(col, "Cancel", on_no)
	button(col, yes_text, on_yes)
	back_action = on_no
	_focus_later(no)
