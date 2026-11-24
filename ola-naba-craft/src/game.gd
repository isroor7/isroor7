# Ola-Naba Craft: session orchestration. One simulation shared by up to two local players, each with
# their own camera, HUD, inventory screen and input devices. Global pause stops both players;
# an open inventory only stops its owner.
extends Node

const World := preload("res://src/voxel_world.gd")
const Player := preload("res://src/player.gd")
const Hud := preload("res://src/hud.gd")
const InvUI := preload("res://src/inventory_ui.gd")
const Drops := preload("res://src/drops.gd")
const Mobs := preload("res://src/mobs.gd")
const Audio := preload("res://src/audio.gd")
const Router := preload("res://src/input_router.gd")
const Saves := preload("res://src/saves.gd")
const Settings := preload("res://src/settings.gd")
const Menus := preload("res://src/menus.gd")
const Items := preload("res://src/items.gd")
const B := preload("res://src/blocks.gd")
const Gen := preload("res://src/world_gen.gd")
const NAMES := ["Ola", "Naba"]
const PROFILES := ["ola", "naba"]
const ACCENTS := [Color("#8be8e7"), Color("#ffb7d0")]
const DAY_LENGTH := 600.0
const DUSK := 330.0
const NIGHT := 390.0
const DAWN := 560.0

var settings: Dictionary
var saves: Saves
var router := Router.new()
var audio: Node
var menus: CanvasLayer
var ui: Menus
var settings_path := Settings.PATH

var world_id := ""
var session_data := {}
var map: Node
var world: Node3D
var drops: Node3D
var mobs: Node3D
var display: Control
var panes: BoxContainer
var loading_label: Label
var huds: Array = []
var inv_uis: Array = []
var players: Array = []
var highlights: Array = []
var previews: Array = []
var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var mode := false          # true = Creative
var local_duo := false
var stacked := false
var solo_skin := 0
var time := 40.0
var daylight := 1.0
var pause_open := false
var loading := false
var loading_time := 0.0
var autosave := 0.0
var world_spawn := Vector3.ZERO
var keep_assignment := false
var input_override := {}   # tests: player index -> scripted input used instead of devices
var status := ""

func _ready() -> void:
	settings = Settings.load_settings(settings_path)
	saves = Saves.new()
	audio = Audio.new()
	add_child(audio)
	menus = CanvasLayer.new()
	menus.layer = 10
	add_child(menus)
	ui = Menus.new(self)
	Input.joy_connection_changed.connect(_on_joy_connection)
	Settings.apply_video(settings)
	ui.title()

# ------------------------------------------------------------------ sessions

func session_active() -> bool:
	return not players.is_empty()

# Starter compatibility: start a fresh world (seed 40521) as one or two players.
func start_game(duo: bool, creative: bool, avatar: int, top_bottom: bool, saved := {}) -> void:
	var id := saves.create("Quick world", "creative" if creative else "survival", int(saved.get("seed", 40521)))
	start_session(id, saves.load_world(id), duo, top_bottom, avatar)

func continue_world() -> bool:
	var worlds := saves.list()
	for w in worlds:
		if w.has("error"):
			continue
		var data := saves.load_world(w.id)
		if data.has("error"):
			continue
		var sess: Dictionary = data.get("session", {})
		start_session(w.id, data, bool(sess.get("split", false)), bool(sess.get("stacked", false)),
			maxi(0, PROFILES.find(String(sess.get("solo_avatar", "ola")))))
		return true
	status = "No world to continue yet."
	return false

func start_session(id: String, data: Dictionary, split: bool, top_bottom: bool, solo_avatar: int) -> void:
	if session_active():
		end_session()
	ui.clear()
	world_id = id
	session_data = data.duplicate(true)
	mode = data.get("rules", "survival") == "creative"
	local_duo = split
	stacked = top_bottom
	solo_skin = clampi(solo_avatar, 0, 1)
	time = float(data.get("time", 40.0))
	pause_open = false
	autosave = 0.0
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	map = World.new()
	world.add_child(map)
	map.view_radius = int(settings.view_distance)
	map.setup(int(data.get("seed", 40521)), Saves.decode_edits(data.get("edits", {}), B.COUNT, World.CS * World.CS * World.H))
	_make_environment()
	drops = Drops.new()
	drops.world = map
	drops.game = self
	world.add_child(drops)
	mobs = Mobs.new()
	mobs.world = map
	mobs.game = self
	world.add_child(mobs)
	audio.attach_world(world)
	var sp = data.get("spawn")
	if sp is Array and sp.size() == 3:
		world_spawn = Vector3(float(sp[0]), float(sp[1]), float(sp[2]))
		map.ensure_data(world_spawn, 1)
	else:
		world_spawn = _find_land()
	display = Control.new()
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)
	panes = VBoxContainer.new() if stacked else HBoxContainer.new()
	panes.add_theme_constant_override("separation", 4)
	panes.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.add_child(panes)
	var count := 2 if split else 1
	if not keep_assignment or router.slots.size() != count:
		router.assign(count)
	keep_assignment = false
	router.apply_settings(settings)
	var records: Dictionary = data.get("players", {})
	for i in count:
		var avatar := i if split else solo_skin
		add_pane(i, avatar, records.get(PROFILES[avatar], {}))
	loading_label = Label.new()
	loading_label.text = "Growing the world…"
	loading_label.add_theme_font_size_override("font_size", 28)
	loading_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	display.add_child(loading_label)
	loading = true
	loading_time = 0.0
	if data.get("restored_from_backup", false):
		for p in players:
			p.say("The main save was damaged; loaded the backup copy", 6.0)
	_capture_mouse()

func _find_land() -> Vector3:
	var g: Gen = map.gen
	for i in 400:
		var a := i * 2.399
		var r := sqrt(float(i)) * 6.0
		var x := roundi(cos(a) * r) + 8
		var z := roundi(sin(a) * r) + 8
		var h := g.height_at(x, z)
		if h > Gen.SEA + 2 and h < 60 and g.biome_at(x, z) != Gen.DUNES:
			return map.find_safe_spot(Vector3(x, h, z), 12)
	return map.find_safe_spot(Vector3(8, 40, 8))

func add_pane(index: int, avatar: int, record: Dictionary) -> void:
	var panel := SubViewportContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.stretch = true
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panes.add_child(panel)
	var port := SubViewport.new()
	port.world_3d = world.get_world_3d()
	port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	port.gui_disable_input = true
	port.audio_listener_enable_3d = true
	panel.add_child(port)
	var camera := Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.08
	camera.far = float(map.view_radius * World.CS + 48)
	camera.cull_mask = 0xFFFFF & ~(1 << (12 + (1 - index)))
	port.add_child(camera)
	camera.current = true
	var p := Player.new()
	p.name = NAMES[avatar]
	world.add_child(p)
	p.setup(self, map, index, avatar, mode, camera, bool(settings.naba_tablet))
	if record.is_empty():
		p.position = map.find_safe_spot(world_spawn + Vector3(index * 1.6 - 0.8, 0, 0), 10)
		p.yaw = 0.5
	else:
		p.restore(record)
		map.ensure_data(p.position, 1)
		if map.box_hits(p.position - Vector3(Player.HW, 0, Player.HW), p.position + Vector3(Player.HW, Player.HEIGHT, Player.HW)):
			p.position = map.find_safe_spot(p.position, 12)
	p.fall_from = p.position.y
	p.sync_view()
	players.append(p)
	var hud := Hud.new()
	hud.player = p
	hud.game = self
	hud.accent = ACCENTS[avatar]
	panel.add_child(hud)
	huds.append(hud)
	var inv := InvUI.new()
	inv.player = p
	inv.game = self
	inv.accent = ACCENTS[avatar]
	inv.visible = false
	panel.add_child(inv)
	inv_uis.append(inv)
	highlights.append(_make_highlight(index))
	previews.append(_make_preview(index))

func _make_highlight(index: int) -> MeshInstance3D:
	var m := ImmediateMesh.new()
	var e := 1.004
	var pts := []
	for a in [Vector3(0, 0, 0), Vector3(e, 0, 0), Vector3(e, 0, e), Vector3(0, 0, e)]:
		pts.append(a)
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	for y in [0.0, e]:
		for i in 4:
			m.surface_add_vertex(pts[i] + Vector3(0, y, 0) - Vector3(0.002, 0.002, 0.002))
			m.surface_add_vertex(pts[(i + 1) % 4] + Vector3(0, y, 0) - Vector3(0.002, 0.002, 0.002))
	for i in 4:
		m.surface_add_vertex(pts[i] - Vector3(0.002, 0.002, 0.002))
		m.surface_add_vertex(pts[i] + Vector3(0, e, 0) - Vector3(0.002, 0.002, 0.002))
	m.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.06, 0.08, 0.16)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.layers = 1 << (12 + index)
	mi.visible = false
	world.add_child(mi)
	return mi

func _make_preview(index: int) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(ACCENTS[index if local_duo else solo_skin].r, ACCENTS[index if local_duo else solo_skin].g, ACCENTS[index if local_duo else solo_skin].b, 0.22)
	mat.no_depth_test = false
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.layers = 1 << (12 + index)
	mi.visible = false
	world.add_child(mi)
	return mi

func _make_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 18.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c0d6ed")
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = map.view_radius * World.CS * 0.55
	env.fog_depth_end = map.view_radius * World.CS * 0.98
	env.fog_sky_affect = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = false
	sun.light_energy = 0.0
	sun.sky_mode = DirectionalLight3D.SKY_MODE_SKY_ONLY
	world.add_child(sun)
	_update_sky()

func end_session() -> void:
	if not session_active() and world == null:
		return
	if map:
		map.shutdown()
	audio.detach_world()
	players.clear()
	huds.clear()
	inv_uis.clear()
	highlights.clear()
	previews.clear()
	if display:
		remove_child(display)
		display.queue_free()
		display = null
	if world:
		remove_child(world)
		world.queue_free()
		world = null
	map = null
	pause_open = false
	loading = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ------------------------------------------------------------------ main loop

func _physics_process(delta: float) -> void:
	if not session_active() or pause_open:
		return
	if loading:
		loading_time += delta
		map.update_streaming(_positions())
		var prog: float = map.loaded_progress()
		loading_label.text = "Growing the world…  %d%%" % int(prog * 100.0)
		if prog >= 1.0 or loading_time > 20.0:
			loading = false
			loading_label.visible = false
		return
	for i in players.size():
		var p = players[i]
		var inp: Dictionary = input_override[i] if input_override.has(i) else router.read(i, delta)
		if p.resting and ((inp.move as Vector2).length() > 0.2 or inp.held.get("jump", false)):
			p.resting = false
		if inv_uis[i].visible:
			if not inv_uis[i].handle(inp, delta):
				close_inventory(i)
			p.tick(delta, {})
		else:
			p.tick(delta, inp)
	map.update_streaming(_positions())
	drops.tick(delta, players, daylight)
	mobs.tick(delta, players, daylight, mode)
	_advance_time(delta)
	_tutorials()
	autosave += delta
	if autosave >= 60.0:
		autosave = 0.0
		save_world()

func _process(_delta: float) -> void:
	if not session_active():
		return
	for i in players.size():
		var p = players[i]
		var hl: MeshInstance3D = highlights[i]
		var pv: MeshInstance3D = previews[i]
		var show: bool = not p.target.is_empty() and p.fainted <= 0.0 and not inv_uis[i].visible
		hl.visible = show
		pv.visible = false
		if show:
			hl.position = Vector3(p.target.cell)
			if Items.block_of(p.selected_key()) >= 0 and p.target.id != B.WORKBENCH and p.target.id != B.BEDROLL:
				var cell: Vector3i = p.target.cell + p.target.normal
				var cur: int = map.get_blockv(cell)
				if (cur == B.AIR or cur == B.WATER) and not cell_occupied(cell):
					pv.visible = true
					pv.position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	_capture_mouse()

func _positions() -> Array:
	var out := []
	for p in players:
		out.append(p.position)
	return out

func _capture_mouse() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want: bool = session_active() and not pause_open and not loading and router.slots.size() > 0 \
		and not (inv_uis.size() > 0 and inv_uis[0].visible and router.slots[0].mouse)
	var m := Input.MOUSE_MODE_CAPTURED if want else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != m:
		Input.mouse_mode = m

# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if not session_active():
		return
	if not pause_open:
		router.feed_event(event)
	if event is InputEventJoypadButton and event.pressed:
		if router.owner_of_pad(event.device) < 0:
			var slot := router.offer_pad(event.device)
			if slot >= 0:
				players[slot].say("Controller connected to %s" % players[slot].display_name())
		if event.button_index == JOY_BUTTON_START:
			var owner := router.owner_of_pad(event.device)
			if owner >= 0 and inv_uis[owner].visible:
				close_inventory(owner)
			else:
				set_pause(not pause_open)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if not pause_open and inv_uis.size() > 0 and inv_uis[0].visible:
			close_inventory(0)
		elif not pause_open and inv_uis.size() > 1 and inv_uis[1].visible:
			close_inventory(1)
		else:
			set_pause(not pause_open)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		ui.back()

func _on_joy_connection(device: int, connected: bool) -> void:
	router.on_connection(device, connected)
	if not session_active():
		ui.refresh_devices()
		return
	for i in players.size():
		if connected and router.slots[i].pad == device:
			players[i].say("Controller reconnected")
		elif not connected and router.slots[i].pad_lost and router.slots[i].lost_device == device:
			players[i].say("Controller disconnected", 4.0)

func owns_mouse(i: int) -> bool:
	return i >= 0 and i < router.slots.size() and router.slots[i].mouse

func device_warning(i: int) -> String:
	if i < router.slots.size() and router.slots[i].pad_lost:
		return "Controller disconnected: press any button on a free controller to rejoin (keyboard still works)"
	return ""

func set_pause(flag: bool) -> void:
	pause_open = flag
	for p in players:
		p.controls = not flag
	if flag:
		ui.pause()
		audio.play("ui_ok")
	else:
		ui.clear()
	_capture_mouse()

func toggle_inventory(p: Node, bench: bool) -> void:
	var i: int = p.player_number
	if inv_uis[i].visible:
		close_inventory(i)
		return
	p.ui_open = true
	inv_uis[i].open(bench)
	audio.play("ui_ok", 0.6)
	_capture_mouse()

func close_inventory(i: int) -> void:
	inv_uis[i].visible = false
	var p = players[i]
	p.ui_open = false
	for a in Router.ACTIONS:
		p.prev[a] = true   # no accidental mine/place from the key that closed the screen
	audio.play("ui_back", 0.6)
	_capture_mouse()

# ------------------------------------------------------------------ world services

func cell_occupied(cell: Vector3i) -> bool:
	for p in players:
		if p.fainted <= 0.0 and p._overlaps(cell):
			return true
	return mobs != null and mobs.occupies(cell)

func on_block_changed(cell: Vector3i, old: int, new: int, _who: Node) -> void:
	var family: String = B.SOUND[new if new != B.AIR else old]
	audio.play_at("place" if new != B.AIR else "break", Vector3(cell) + Vector3(0.5, 0.5, 0.5), 0.9)
	if family != "" and new == B.AIR:
		audio.play_at("dig_" + family, Vector3(cell) + Vector3(0.5, 0.5, 0.5), 0.8)

func spawn_drops(cell: Vector3i, id: int) -> void:
	drops.spawn_block_drops(cell, id)

func spawn_item(key: String, n: int, pos: Vector3) -> void:
	drops.spawn(key, n, pos)

func on_player_fainted(p: Node, kind: String) -> void:
	var items: Array = p.inventory.drain()
	if not items.is_empty():
		var spot: Vector3 = p.position
		if map.box_hits(spot, spot + Vector3(0.1, 0.5, 0.1)) or spot.y < 2.0:
			spot = map.find_safe_spot(p.position, 16)
		drops.add_bundle(p.profile(), items, spot)
	var why := {"gloomling": "A Gloomling caught %s", "fall": "%s fell too far", "void": "%s fell out of the world"}
	for q in players:
		q.say(String(why.get(kind, "%s fainted")) % p.display_name(), 4.0)

func phase() -> float:
	return fposmod(time, DAY_LENGTH)

# A new day begins at sunrise (dawn), so "Day 2" starts when the first night ends.
func day_number() -> int:
	return int((time + (DAY_LENGTH - DAWN - 15.0)) / DAY_LENGTH) + 1

func is_night() -> bool:
	var t := phase()
	return t >= NIGHT - 20.0 and t < DAWN + 15.0

static func daylight_at(t: float) -> float:
	if t < DUSK:
		return 1.0
	if t < NIGHT:
		return lerpf(1.0, 0.12, smoothstep(0.0, 1.0, (t - DUSK) / (NIGHT - DUSK)))
	if t < DAWN:
		return 0.12
	return lerpf(0.12, 1.0, smoothstep(0.0, 1.0, (t - DAWN) / (DAY_LENGTH - DAWN)))

func clock_text() -> String:
	var t := phase()
	var part := "Morning"
	if t >= 150.0 and t < DUSK:
		part = "Afternoon"
	elif t >= DUSK and t < NIGHT:
		part = "Dusk"
	elif t >= NIGHT and t < DAWN:
		part = "Night"
	elif t >= DAWN:
		part = "Dawn"
	return "Day %d · %s" % [day_number(), part]

func _advance_time(delta: float) -> void:
	var before := phase()
	time += delta
	var now := phase()
	if before < DUSK and now >= DUSK:
		audio.play("dusk")
		for p in players:
			if not p.creative:
				p.say("Night is coming: build a shelter and light lanterns", 5.0)
	if before < DAWN + 15.0 and now >= DAWN + 15.0:
		audio.play("dawn")
		for p in players:
			p.stats.nights += 1
			p.say("Day %d. You made it through the night!" % day_number(), 5.0)
	daylight = daylight_at(now)
	_update_sky()

func _update_sky() -> void:
	if map == null or sky_mat == null:
		return
	map.set_daylight(daylight)
	var t := phase()
	var dusky := 0.0
	if t >= DUSK - 30.0 and t < NIGHT + 20.0:
		dusky = 1.0 - absf((t - (DUSK + NIGHT) / 2.0) / 60.0)
	elif t >= DAWN - 10.0:
		dusky = 1.0 - absf((t - (DAWN + 25.0)) / 35.0)
	dusky = clampf(dusky, 0.0, 1.0)
	var day_top := Color("#5fb3cf")
	var day_hor := Color("#f6dfb4")
	var night_top := Color("#0f1633")
	var night_hor := Color("#363569")
	var top := night_top.lerp(day_top, daylight)
	var hor := night_hor.lerp(day_hor, daylight).lerp(Color("#f0a6c0"), dusky * 0.7)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sky_mat.ground_bottom_color = top.darkened(0.3)
	env.fog_light_color = hor
	var ang := t / DAY_LENGTH * TAU
	sun.rotation = Vector3(-0.35 - sin(ang) * 0.9, 0.6, 0)
	sun.visible = daylight > 0.2

func try_rest(p: Node) -> void:
	if not is_night():
		p.say("Respawn point set. Rest here at night to sleep until morning")
		return
	p.resting = true
	for q in players:
		if q.fainted <= 0.0 and not q.resting:
			p.say("Respawn point set. Waiting for %s to rest too" % q.display_name())
			return
	time = floorf(time / DAY_LENGTH) * DAY_LENGTH + DAWN + 16.0
	for q in players:
		q.resting = false
		q.stats.nights += 1
		q.say("You rested until sunrise", 4.0)
	audio.play("dawn")

# ------------------------------------------------------------------ tutorial

func tutorial_steps(creative: bool) -> Array:
	if creative:
		return [
			{"text": "Choose any block", "hint": "Open %inventory% → Palette, then %jump% puts it in your hotbar", "done": func(p): return p.stats.get("palette", 0) > 0 or p.stats.placed > 0},
			{"text": "Build something", "hint": "%place% places a block, %mine% removes one", "done": func(p): return p.stats.placed >= 5},
			{"text": "Take off", "hint": "Double-tap %jump% to fly, hold %down% to descend", "done": func(p): return p.flying},
		]
	return [
		{"text": "Collect Timber", "hint": "Hold %mine% on a tree trunk until it breaks", "done": func(p): return p.inventory.count("timber") > 0 or p.inventory.count("planks") > 0},
		{"text": "Make Planks", "hint": "Open %inventory% → Crafting → Planks, then %jump%", "done": func(p): return p.inventory.count("planks") > 0 or p.inventory.count("wood_pick") > 0},
		{"text": "Craft a Wood Pick", "hint": "Make Sticks first; a pick is 3 Planks + 2 Sticks", "done": func(p): return p.inventory.count("wood_pick") > 0 or p.inventory.count("slate") > 0},
		{"text": "Mine some Slate", "hint": "Grey stone below the soil: hold %mine% with the pick selected", "done": func(p): return p.inventory.count("slate") > 0},
		{"text": "Build a shelter before dark", "hint": "Walls and a roof (%place%). Embers from ore make lanterns", "done": func(p): return is_night() or map.sky_light(p.head()) < 0.95},
		{"text": "Survive the first night", "hint": "Stay safe until sunrise. Berries from leaves fill you up", "done": func(p): return p.stats.nights >= 1},
	]

func _tutorials() -> void:
	for i in players.size():
		var p = players[i]
		var hud = huds[i]
		if p.tutorial_done:
			hud.tutorial_text = ""
			continue
		var steps := tutorial_steps(p.creative)
		while p.tutorial_step < steps.size() and steps[p.tutorial_step].done.call(p):
			p.tutorial_step += 1
			audio.play("ui_ok", 0.5)
		if p.tutorial_step >= steps.size():
			p.tutorial_done = true
			p.say("Tutorial complete. Replay it any time from the pause menu", 4.0)
			hud.tutorial_text = ""
			continue
		var st: Dictionary = steps[p.tutorial_step]
		hud.tutorial_text = "%d/%d  %s" % [p.tutorial_step + 1, steps.size(), st.text]
		var hint: String = st.hint
		for a in ["mine", "place", "jump", "down", "inventory"]:
			hint = hint.replace("%" + a + "%", router.glyph(i, a))
		hud.tutorial_hint = hint

func set_tutorial(i: int, replay: bool) -> void:
	if i >= players.size():
		return
	players[i].tutorial_done = not replay
	players[i].tutorial_step = 0

# ------------------------------------------------------------------ saving

func world_data() -> Dictionary:
	var data := session_data.duplicate(true)
	data.erase("restored_from_backup")
	data["edits"] = Saves.encode_edits(map.edits)
	var records: Dictionary = data.get("players", {})
	for p in players:
		var old: Dictionary = records.get(p.profile(), {})
		var snap: Dictionary = p.snapshot()
		# keep the other ruleset's inventory untouched (Creative stock never leaks into Survival)
		for k in ["inventory", "creative_inventory"]:
			if old.has(k) and not snap.has(k):
				snap[k] = old[k]
		records[p.profile()] = snap
	data["players"] = records
	data["time"] = time
	data["spawn"] = [world_spawn.x, world_spawn.y, world_spawn.z]
	data["entities"] = drops.to_save()
	data["session"] = {"split": local_duo, "stacked": stacked, "solo_avatar": PROFILES[solo_skin]}
	return data

func save_world() -> bool:
	if not session_active() or world_id == "":
		return false
	var data := world_data()
	if not saves.write(world_id, data):
		return false
	session_data = data
	return true

func save_settings() -> void:
	Settings.save_settings(settings, settings_path)
	Settings.apply_video(settings)
	router.apply_settings(settings)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and session_active():
		save_world()
		map.shutdown()
