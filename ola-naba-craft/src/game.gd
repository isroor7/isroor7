extends Node

const Terrain := preload("res://src/terrain.gd")
const Player := preload("res://src/player.gd")
const LOGO := preload("res://assets/logo.png")
const NAMES := ["Ola", "Naba"]
const SAVE_VERSION := 1
var save_path := "user://world-v1.json"
var backup_path := "user://world-v1.backup.json"
var map: GridMap
var world: Node3D
var display: Control
var panes: BoxContainer
var huds: Array[Label] = []
var players: Array = []
var sun: DirectionalLight3D
var env: Environment
var menus: CanvasLayer
var banner: Label
var mode := false
var local_duo := false
var stacked := false
var solo_skin := 0
var day_time := 35.0
var age := 0.0
var pause_open := false
var pending_mouse: Array[bool] = []
var status := ""
var world_seed := 40521

func _ready() -> void:
	menus = CanvasLayer.new()
	menus.layer = 10
	add_child(menus)
	show_menu()

func wipe_menu() -> void:
	for child in menus.get_children():
		menus.remove_child(child)
		child.queue_free()

func show_menu() -> void:
	wipe_menu()
	var background := ColorRect.new()
	background.color = Color("#101d34")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menus.add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.custom_minimum_size = Vector2(565, 0)
	center.add_child(column)
	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.custom_minimum_size = Vector2(560, 168)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(logo)
	label(column, "LOCAL VOXEL SANDBOX  /  BUILD TOGETHER", 20, Color("#9be0e6"))
	var cast := HBoxContainer.new()
	cast.alignment = BoxContainer.ALIGNMENT_CENTER
	cast.add_theme_constant_override("separation", 16)
	column.add_child(cast)
	add_cast_badge(cast, preload("res://assets/ola.svg"), "OLA", Color("#9ce5ea"))
	add_cast_badge(cast, preload("res://assets/naba.svg"), "NABA", Color("#ffb7d0"))
	var choice := OptionButton.new()
	choice.add_item("Solo as Ola (navy & lilac)", 0)
	choice.add_item("Solo as Naba (rose)", 1)
	choice.add_item("Local co-op: Ola + Naba", 2)
	column.add_child(choice)
	var rules := OptionButton.new()
	rules.add_item("Creative   /   unlimited blocks & flight", 0)
	rules.add_item("Survival   /   gather, craft & manage stamina", 1)
	column.add_child(rules)
	var layout := CheckButton.new()
	layout.text = "Stack split-screen vertically (top / bottom)"
	column.add_child(layout)
	button(column, "NEW WORLD", func(): request_new_world(choice.selected == 2, rules.selected == 0, mini(choice.selected, 1), layout.button_pressed))
	var resume := button(column, "CONTINUE SAVED WORLD", func(): continue_world())
	resume.disabled = not FileAccess.file_exists(save_path) and not FileAccess.file_exists(backup_path)
	label(column, "OFFLINE  ·  KEYBOARD / MOUSE  ·  CONTROLLERS", 14, Color("#91a9c6"))
	banner = label(column, status, 16, Color("#ffce94"))
	choice.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func add_cast_badge(parent: Node, artwork: Texture2D, title: String, tint: Color) -> void:
	var stack := VBoxContainer.new()
	parent.add_child(stack)
	var badge := TextureRect.new()
	badge.texture = artwork
	badge.custom_minimum_size = Vector2(64, 64)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stack.add_child(badge)
	label(stack, title, 15, tint)

func label(parent: Node, value: String, size: int, tint: Color) -> Label:
	var item := Label.new()
	item.text = value
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", tint)
	parent.add_child(item)
	return item

func button(parent: Node, value: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = value
	item.custom_minimum_size.y = 40
	item.pressed.connect(action)
	parent.add_child(item)
	return item

func request_new_world(duo: bool, creative: bool, avatar: int, top_bottom: bool) -> void:
	if FileAccess.file_exists(save_path) or FileAccess.file_exists(backup_path):
		var dialog := ConfirmationDialog.new()
		dialog.title = "Start a new world?"
		dialog.dialog_text = "This prototype has one save slot. The new world will replace that slot when saved."
		menus.add_child(dialog)
		dialog.confirmed.connect(func(): start_game(duo, creative, avatar, top_bottom))
		dialog.canceled.connect(dialog.queue_free)
		dialog.popup_centered()
	else:
		start_game(duo, creative, avatar, top_bottom)

func start_game(duo: bool, creative: bool, avatar: int, top_bottom: bool, saved := {}) -> void:
	wipe_menu()
	local_duo = duo
	mode = creative
	stacked = top_bottom
	solo_skin = avatar
	day_time = float(saved.get("day_time", 35.0))
	world_seed = int(saved.get("seed", 40521))
	pause_open = false
	pending_mouse.clear()
	age = 0.0
	world = Node3D.new()
	add_child(world)
	map = Terrain.new()
	world.add_child(map)
	map.make_world(world_seed)
	map.restore(saved.get("edits", {}))
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3c6593")
	sky_mat.sky_horizon_color = Color("#a1d4e2")
	sky_mat.ground_horizon_color = Color("#a1d4e2")
	sky_mat.ground_bottom_color = Color("#526d88")
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c0d6ed")
	env.ambient_light_energy = 0.62
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -24, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 32
	world.add_child(sun)

	display = Control.new()
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(display)
	panes = VBoxContainer.new() if stacked else HBoxContainer.new()
	panes.add_theme_constant_override("separation", 4)
	panes.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.add_child(panes)
	var player_saves: Array = saved.get("players", [])
	for i in (2 if duo else 1):
		add_pane(i, i if duo else avatar, player_saves[i] if i < player_saves.size() else {})
	assign_pads()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func add_pane(index: int, avatar: int, data: Dictionary) -> void:
	var panel := SubViewportContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.stretch = true
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panes.add_child(panel)
	var port := SubViewport.new()
	port.world_3d = world.get_world_3d()
	port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	port.gui_disable_input = true
	panel.add_child(port)
	var camera := Camera3D.new()
	camera.fov = 75.0
	camera.far = 72.0
	port.add_child(camera)
	camera.current = true
	var p := Player.new()
	p.collision_layer = 2
	p.collision_mask = 3
	world.add_child(p)
	p.setup(index, avatar, mode, map, camera)
	if not data.is_empty():
		p.restore(data)
	players.append(p)
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(overlay)
	var cross := Label.new()
	cross.text = "+"
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cross.add_theme_font_size_override("font_size", 29)
	cross.add_theme_constant_override("outline_size", 4)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(cross)
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var hud := Label.new()
	hud.add_theme_font_size_override("font_size", 17)
	hud.add_theme_constant_override("outline_size", 5)
	hud.add_theme_color_override("font_color", Color("#c8f6fb") if avatar == 0 else Color("#ffd2e3"))
	hud.position = Vector2(16, 13)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(hud)
	huds.append(hud)

func assign_pads() -> void:
	var pads := Input.get_connected_joypads()
	for p in players:
		p.pad = -1
	if players.size() == 1 and not pads.is_empty():
		players[0].pad = pads[0]
	elif players.size() == 2 and pads.size() == 1:
		players[1].pad = pads[0]
	elif players.size() == 2 and pads.size() >= 2:
		players[0].pad = pads[0]
		players[1].pad = pads[1]

func _process(delta: float) -> void:
	if players.is_empty() or pause_open:
		return
	assign_pads()
	day_time = fposmod(day_time + delta, 220.0)
	var daylight := clampf(sin(day_time * TAU / 220.0) * .78 + .42, .10, 1.0)
	env.ambient_light_energy = .24 + daylight * .49
	sun.light_energy = daylight * 1.3
	env.background_energy_multiplier = .22 + daylight * .78
	for i in players.size():
		var p = players[i]
		var selected: int = p.hotbar
		var quantity: String = "∞" if mode else str(p.inventory[selected])
		var condition: String = "CREATIVE" if mode else ("HP %d/5  ·  Stamina %d/5" % [p.hp, p.stamina])
		huds[i].text = "%s   /   %s\n%d · %s × %s   /   ESC menu" % [NAMES[p.avatar], condition, selected + 1, Terrain.BLOCKS[selected], quantity]
	age += delta
	if age >= 30:
		age = 0
		save_world()

func _physics_process(_delta: float) -> void:
	if not pause_open and not players.is_empty():
		for place in pending_mouse:
			players[0].use_block(place)
	pending_mouse.clear()

func _unhandled_input(event: InputEvent) -> void:
	if players.is_empty():
		return
	if event.is_action_pressed("ui_cancel"):
		set_pause(not pause_open)
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		set_pause(not pause_open)
	elif not pause_open:
		if event is InputEventMouseMotion:
			players[0].look(event.relative.x * .003, event.relative.y * .003)
		elif event is InputEventMouseButton and event.pressed:
			match event.button_index:
				MOUSE_BUTTON_LEFT: pending_mouse.append(false)
				MOUSE_BUTTON_RIGHT: pending_mouse.append(true)
				MOUSE_BUTTON_WHEEL_UP: players[0].select_slot(-1)
				MOUSE_BUTTON_WHEEL_DOWN: players[0].select_slot(1)

func set_pause(flag: bool) -> void:
	pause_open = flag
	for p in players:
		p.controls = not flag
	wipe_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if flag else Input.MOUSE_MODE_CAPTURED
	if not flag:
		return
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.07, 0.13, .94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menus.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)
	label(column, "WORLD PAUSED", 31, Color("#8be8e7"))
	label(column, "P1  WASD / mouse / Space / Shift  ·  Q / E mine / place  ·  R / F slots  ·  T craft planks  ·  G snack", 15, Color.WHITE)
	if local_duo:
		label(column, "P2  IJKL / arrows / Enter / P  ·  , / . mine / place  ·  / / backslash slots  ·  M craft  ·  N snack", 15, Color.WHITE)
	label(column, "Pad: sticks move / look  ·  A jump/up, B down  ·  RB mine, LB place  ·  D-pad ←/→ slots  ·  Y craft  ·  X snack", 15, Color.WHITE)
	button(column, "RESUME", func(): set_pause(false)).grab_focus()
	button(column, "SAVE & RETURN TO TITLE", func():
		if save_world():
			end_session()
		else:
			banner.text = "Could not save; the world is still open.")
	banner = label(column, "", 16, Color("#ffce94"))

func end_session() -> void:
	players.clear()
	huds.clear()
	pending_mouse.clear()
	remove_child(display)
	display.queue_free()
	remove_child(world)
	world.queue_free()
	status = ""
	show_menu()

func save_world() -> bool:
	if players.is_empty():
		return false
	var snapshots := []
	for p in players:
		snapshots.append(p.snapshot())
	var data := {"version": SAVE_VERSION, "duo": local_duo, "creative": mode,
		"stacked": stacked, "solo_skin": solo_skin, "seed": world_seed, "day_time": day_time,
		"edits": map.edits, "players": snapshots}
	var temp := save_path + ".tmp"
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		return false
	var written := f.store_string(JSON.stringify(data))
	f.flush()
	var err := f.get_error()
	f.close()
	if not written or err != OK:
		return false
	if FileAccess.file_exists(save_path) and not read_save(save_path).is_empty():
		if DirAccess.copy_absolute(save_path, backup_path) != OK:
			return false
	return DirAccess.rename_absolute(temp, save_path) == OK

func read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.get("version", -1) != SAVE_VERSION:
		return {}
	if not parsed.get("players") is Array or not parsed.get("edits") is Dictionary:
		return {}
	if parsed.players.size() != (2 if parsed.get("duo", false) else 1):
		return {}
	for record in parsed.players:
		if not record is Dictionary:
			return {}
	return parsed

func continue_world() -> void:
	var data := read_save(save_path)
	if data.is_empty():
		data = read_save(backup_path)
	if data.is_empty():
		banner.text = "No compatible save found."
		return
	start_game(data.duo, data.creative, clampi(int(data.solo_skin), 0, 1), data.stacked, data)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not players.is_empty():
		save_world()
