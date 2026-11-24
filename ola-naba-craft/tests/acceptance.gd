# Headless checks for the brief's acceptance list. Run:
#   godot --headless --path . --script tests/acceptance.gd
# These exercise game logic only; they are not a substitute for playing on a real screen
# with real controllers.
extends SceneTree

const H := preload("res://tests/helpers.gd")
const B := preload("res://src/blocks.gd")
const Legacy := preload("res://src/legacy_v1.gd")
var failures := 0
var checks := 0
var game: Node

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(note)
		print("  FAIL: ", note)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func idle() -> Dictionary:
	return {"held": {}, "move": Vector2.ZERO, "look": Vector2.ZERO, "wheel": 0, "nav": Vector2i.ZERO}

func key(code: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)

func start(duo: bool, creative: bool, avatar := 0) -> void:
	game.start_game(duo, creative, avatar, false)
	await H.wait_loaded(self, game)
	await frames(30)

func stop() -> void:
	game.input_override.clear()
	game.end_session()
	await process_frame

func ground_cell(near: Vector3, dx: int, dz: int) -> Vector3i:
	var x := floori(near.x) + dx
	var z := floori(near.z) + dz
	return Vector3i(x, game.map.surface_y(x, z) - 1, z)

func run() -> void:
	game = H.make_game(self, "accept")
	for t in ["four_combos", "input_isolation", "gamepad_scoping", "shared_world_and_costs", "concurrent_mutation",
			"identity_persistence", "devices", "creative_isolation", "placement_safety", "respawn_and_bundle",
			"crafting_rules", "chunk_union", "saves_robustness", "v1_import"]:
		var before := failures
		await call("t_" + t)
		print("%s %s" % ["ok  " if failures == before else "FAIL", t])
	print("ACCEPTANCE: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

# All four session/rule combinations launch with a new world; Naba solo needs no second controller.
func t_four_combos() -> void:
	for combo in [[false, false, 0], [false, true, 0], [false, false, 1], [false, true, 1], [true, false, 0], [true, true, 0]]:
		await start(combo[0], combo[1], combo[2])
		var n := 2 if combo[0] else 1
		check(game.players.size() == n, "combo %s: player count" % str(combo))
		check(game.mode == combo[1], "combo %s: rules" % str(combo))
		check(game.players[0].avatar == (0 if combo[0] else combo[2]), "combo %s: avatar" % str(combo))
		if not combo[0]:
			check(game.router.slots.size() == 1 and game.router.slots[0].kb == "kb1", "solo uses player 1's devices only")
		for p in game.players:
			check(p.is_on_floor() or p.flying or p.in_water, "combo %s: %s landed" % [str(combo), p.display_name()])
		await stop()

# Player inputs alone never move the other player or their camera.
func t_input_isolation() -> void:
	await start(true, false)
	var a = game.players[0]
	var b = game.players[1]
	var pa: Vector3 = a.position
	var pb: Vector3 = b.position
	var ya: float = a.yaw
	var yb: float = b.yaw
	key(KEY_W, true)
	await create_timer(0.35).timeout
	key(KEY_W, false)
	await frames(5)
	check(a.position.distance_to(pa) > 0.3, "P1 W moves P1")
	check(b.position.distance_to(pb) < 0.01, "P1 W does not move P2")
	var m := InputEventMouseMotion.new()
	m.relative = Vector2(140, 0)
	Input.parse_input_event(m)
	await frames(3)
	check(absf(a.yaw - ya) > 0.1, "mouse turns P1's camera")
	check(absf(b.yaw - yb) < 0.0001, "mouse does not turn P2's camera")
	ya = a.yaw
	key(KEY_LEFT, true)
	await create_timer(0.25).timeout
	key(KEY_LEFT, false)
	await frames(3)
	check(absf(b.yaw - yb) > 0.1, "arrow keys turn P2's camera")
	check(absf(a.yaw - ya) < 0.0001, "arrow keys do not turn P1's camera")
	await stop()

# A controller only drives the player it is assigned to, with a radial deadzone.
func t_gamepad_scoping() -> void:
	await start(true, false)
	var a = game.players[0]
	var b = game.players[1]
	game.router.slots[1].pad = 7
	var pa: Vector3 = a.position
	var pb: Vector3 = b.position
	var small := InputEventJoypadMotion.new()
	small.device = 7
	small.axis = JOY_AXIS_LEFT_Y
	small.axis_value = -0.12
	Input.parse_input_event(small)
	await frames(20)
	check(b.position.distance_to(pb) < 0.02, "stick inside the deadzone does not move")
	var full := InputEventJoypadMotion.new()
	full.device = 7
	full.axis = JOY_AXIS_LEFT_Y
	full.axis_value = -1.0
	Input.parse_input_event(full)
	await frames(25)
	var back := InputEventJoypadMotion.new()
	back.device = 7
	back.axis = JOY_AXIS_LEFT_Y
	back.axis_value = 0.0
	Input.parse_input_event(back)
	await frames(3)
	check(b.position.distance_to(pb) > 0.3, "controller 7 moves P2")
	check(a.position.distance_to(pa) < 0.01, "controller 7 does not move P1")
	await stop()

# P1 removes a block, P2 sees it; P2 places one, it costs only P2's stock and survives a reload.
func t_shared_world_and_costs() -> void:
	await start(true, false)
	var a = game.players[0]
	var b = game.players[1]
	var cell := ground_cell(a.position, 3, 0)
	check(a.break_block(cell), "P1 can break a block")
	check(b.world == a.world and b.world.get_blockv(cell) == B.AIR, "P2 sees P1's edit in the same world")
	a.inventory.clear()
	b.inventory.clear()
	b.inventory.add("planks", 5)
	b.hotbar = 0
	b.target = {"cell": cell - Vector3i(0, 1, 0), "normal": Vector3i(0, 1, 0), "id": game.map.get_blockv(cell - Vector3i(0, 1, 0))}
	check(b.place_block(), "P2 can place a block")
	check(game.map.get_blockv(cell) == B.PLANKS, "P2's block is in the shared world")
	check(b.inventory.count("planks") == 4 and a.inventory.count("planks") == 0, "placing costs only P2's inventory")
	check(game.save_world(), "save")
	var id: String = game.world_id
	await stop()
	game.start_session(id, game.saves.load_world(id), true, false, 0)
	await H.wait_loaded(self, game)
	check(game.map.get_blockv(cell) == B.PLANKS, "P2's block persists after reload")
	check(game.players[1].inventory.count("planks") == 4, "P2's stock persists after reload")
	await stop()

# Two players acting on the same cell in the same frame make one mutation and one drop.
func t_concurrent_mutation() -> void:
	await start(true, false)
	var a = game.players[0]
	var b = game.players[1]
	var cell := ground_cell(a.position, 2, 1)
	var id: int = game.map.get_blockv(cell)
	a.inventory.clear()
	b.inventory.clear()
	var edits_before: int = (game.map.edits.get(game.map.chunk_of(cell.x, cell.z), {}) as Dictionary).size()
	var drops_before: int = game.drops.drops.size()
	var r1: bool = a.break_block(cell)
	var r2: bool = b.break_block(cell)
	check(r1 and not r2, "only the first break succeeds")
	check((game.map.edits.get(game.map.chunk_of(cell.x, cell.z), {}) as Dictionary).size() == edits_before + 1, "exactly one recorded edit")
	var drop_key: String = B.drops(id)[0][0]
	check(game.drops.drops.size() == drops_before + 1, "exactly one drop spawned")
	var spot := Vector3(cell) + Vector3(0.5, 0, 0.5)
	a.position = game.map.find_safe_spot(spot + Vector3(1, 0, 0), 3)
	b.position = game.map.find_safe_spot(spot + Vector3(-1, 0, 0), 3)
	await frames(120)
	check(a.inventory.count(drop_key) + b.inventory.count(drop_key) == 1, "the drop went to exactly one player (no duplication)")
	# both players placing into the same empty cell
	a.inventory.add("planks", 1)
	b.inventory.add("planks", 1)
	a.hotbar = a.inventory.slots.find(a.inventory.slots.filter(func(s): return s.get("id", "") == "planks")[0])
	b.hotbar = b.inventory.slots.find(b.inventory.slots.filter(func(s): return s.get("id", "") == "planks")[0])
	var below := cell - Vector3i(0, 1, 0)
	var t := {"cell": below, "normal": Vector3i(0, 1, 0), "id": game.map.get_blockv(below)}
	a.position = game.map.find_safe_spot(spot + Vector3(3, 0, 0), 3)
	b.position = game.map.find_safe_spot(spot + Vector3(-3, 0, 0), 3)
	a.target = t
	b.target = t
	var p1: bool = a.place_block()
	var p2: bool = b.place_block()
	check(p1 != p2, "only one of two simultaneous placements succeeds")
	check(a.inventory.count("planks") + b.inventory.count("planks") == 1, "only the successful placer paid")
	await stop()

# Character identity, camera, position, inventory and edits are kept per avatar, not array order.
func t_identity_persistence() -> void:
	await start(true, false)
	var a = game.players[0]
	var b = game.players[1]
	a.inventory.clear()
	b.inventory.clear()
	a.inventory.add("ember", 3)
	b.inventory.add("sunmetal", 2)
	a.yaw = 1.1
	a.pitch = -0.3
	b.yaw = -2.0
	b.pitch = 0.2
	await frames(10)
	var pos_b: Vector3 = b.position
	var pos_a: Vector3 = a.position
	check(game.save_world(), "save split world")
	var id: String = game.world_id
	await stop()
	game.start_session(id, game.saves.load_world(id), false, false, 1)
	await H.wait_loaded(self, game)
	var n = game.players[0]
	check(n.avatar == 1, "solo session uses Naba")
	check(n.position.distance_to(pos_b) < 1.0, "Naba's saved position restored in solo")
	check(absf(n.yaw - (-2.0)) < 0.001 and absf(n.pitch - 0.2) < 0.001, "Naba's camera restored")
	check(n.inventory.count("sunmetal") == 2 and n.inventory.count("ember") == 0, "Naba's own inventory, not Ola's")
	n.inventory.add("stick", 1)
	check(game.save_world(), "save solo session")
	await stop()
	var data: Dictionary = game.saves.load_world(id)
	check(data.players.has("ola") and data.players.has("naba"), "both records kept after a solo session")
	game.start_session(id, data, true, false, 0)
	await H.wait_loaded(self, game)
	check(game.players[0].avatar == 0 and game.players[0].inventory.count("ember") == 3, "Ola intact after Naba played solo")
	check(game.players[0].position.distance_to(pos_a) < 1.0 and absf(game.players[0].yaw - 1.1) < 0.001, "Ola's position and camera intact")
	check(game.players[1].inventory.count("stick") == 1, "Naba's solo progress shows in split")
	await stop()

# Device assignment, disconnect and rejoin never steal the other player's controller.
func t_devices() -> void:
	var r = game.router
	r.assign(1, [3])
	check(r.slots[0].pad == 3 and r.slots[0].mouse, "solo: first controller and keyboard/mouse")
	r.assign(2, [0])
	check(r.slots[1].pad == 0 and r.slots[0].pad == -1, "one controller in split goes to player 2")
	r.assign(2, [0, 1])
	check(r.slots[0].pad == 0 and r.slots[1].pad == 1, "two controllers in connection order")
	r.on_connection(1, false)
	check(r.slots[1].pad_lost and r.slots[0].pad == 0, "P2 disconnect only affects P2")
	check(r.offer_pad(0) == -1 and r.slots[0].pad == 0, "a button on P1's controller does not move it to P2")
	r.on_connection(1, true)
	check(r.slots[1].pad == 1 and not r.slots[1].pad_lost, "P2's controller rejoins P2")
	r.on_connection(1, false)
	check(r.offer_pad(5) == 1, "a new controller goes to the player who lost theirs")
	r.assign(2, [])
	check(r.slots[0].kb == "kb1" and r.slots[1].kb == "kb2", "no controllers: shared keyboard")
	await start(true, false)
	game.router.slots[1].pad = 4
	game.router.on_connection(4, false)
	check(game.device_warning(1) != "" and game.device_warning(0) == "", "only the affected player sees the warning")
	var b = game.players[1]
	var pb: Vector3 = b.position
	key(KEY_I, true)
	await create_timer(0.3).timeout
	key(KEY_I, false)
	await frames(3)
	check(b.position.distance_to(pb) > 0.3, "P2 keeps playing on the keyboard while the controller is away")
	await stop()

# Creative flight and stock never leak into Survival.
func t_creative_isolation() -> void:
	await start(false, true)
	var c = game.players[0]
	c.flying = true
	var snap: Dictionary = c.snapshot()
	check(snap.has("creative_inventory") and not snap.has("inventory"), "creative stock saved separately")
	await stop()
	await start(false, false)
	var s = game.players[0]
	s.restore({"flying": true, "creative_inventory": [{"id": "slate_brick", "n": 1}], "inventory": [{"id": "stick", "n": 2}]})
	check(not s.flying, "flight does not carry into Survival")
	check(s.inventory.count("slate_brick") == 0 and s.inventory.count("stick") == 2, "creative stock does not carry into Survival")
	game.session_data.players = {"ola": {"creative_inventory": [{"id": "slate_brick", "n": 1}]}}
	var data: Dictionary = game.world_data()
	check(data.players.ola.has("creative_inventory") and data.players.ola.has("inventory"), "saving keeps the other ruleset's stock untouched")
	await stop()

# Placing can never put a block inside either player (or a creature).
func t_placement_safety() -> void:
	await start(true, false)
	var a = game.players[0]
	var b = game.players[1]
	a.inventory.add("planks", 10)
	a.hotbar = a.inventory.slots.find(a.inventory.slots.filter(func(s): return s.get("id", "") == "planks")[0])
	var feet_b := Vector3i(floori(b.position.x), floori(b.position.y), floori(b.position.z))
	a.target = {"cell": feet_b - Vector3i(0, 1, 0), "normal": Vector3i(0, 1, 0), "id": B.SLATE}
	check(not a.place_block(), "cannot place into Naba's feet")
	a.target = {"cell": feet_b, "normal": Vector3i(0, 1, 0), "id": B.SLATE}
	check(not a.place_block(), "cannot place into Naba's head")
	var feet_a := Vector3i(floori(a.position.x), floori(a.position.y), floori(a.position.z))
	a.target = {"cell": feet_a - Vector3i(0, 1, 0), "normal": Vector3i(0, 1, 0), "id": B.SLATE}
	check(not a.place_block(), "cannot place into yourself")
	var spot: Vector3 = game.map.find_safe_spot(a.position + Vector3(4, 0, 4), 4)
	game.mobs.spawn("puffkin", spot)
	var cell := Vector3i(floori(spot.x), floori(spot.y), floori(spot.z))
	a.target = {"cell": cell - Vector3i(0, 1, 0), "normal": Vector3i(0, 1, 0), "id": B.SLATE}
	check(not a.place_block(), "cannot place into a creature")
	game.mobs.clear_all()
	await stop()

# Fainting leaves a keepsake bundle; respawn lands on a safe tile; the bundle can be recovered.
func t_respawn_and_bundle() -> void:
	await start(false, false)
	var a = game.players[0]
	a.inventory.clear()
	a.inventory.add("planks", 10)
	a.inventory.add("wood_pick", 1)
	var died_at: Vector3 = a.position
	a.invuln = 0.0
	check(a.take_damage(100, Vector3.INF, "fall"), "lethal damage lands")
	check(a.fainted > 0.0 and a.inventory.is_empty(), "fainting empties the inventory")
	var bundle: Dictionary = game.drops.bundle_for("ola")
	check(not bundle.is_empty() and bundle.items.size() == 2, "a keepsake bundle holds the items")
	await create_timer(3.4).timeout
	check(a.fainted <= 0.0 and a.health == 20, "respawned with full health")
	var f := Vector3i(floori(a.position.x), floori(a.position.y), floori(a.position.z))
	check(not game.map.is_solid(f.x, f.y, f.z) and not game.map.is_solid(f.x, f.y + 1, f.z), "respawn tile is free")
	check(game.map.is_solid(f.x, f.y - 1, f.z) and game.map.get_block(f.x, f.y, f.z) != B.WATER, "respawn tile has solid dry ground")
	a.position = game.map.find_safe_spot(bundle.pos, 3)
	await frames(20)
	check(a.inventory.count("planks") == 10 and a.inventory.count("wood_pick") == 1, "bundle recovered in full")
	check(game.drops.bundle_for("ola").is_empty(), "recovered bundle disappears")
	# a missing bedroll falls back to the world spawn
	a.has_bed = true
	a.bed = Vector3(died_at.x + 50, died_at.y, died_at.z)
	a.respawn()
	check(not a.has_bed, "missing bedroll is forgotten")
	await stop()

# Crafting consumes exactly the inputs, needs a bench where stated, and never half-crafts.
func t_crafting_rules() -> void:
	await start(false, false)
	var a = game.players[0]
	a.inventory.clear()
	a.inventory.add("planks", 2)
	check(not a.craft("wood_pick") and a.inventory.count("planks") == 2, "missing sticks: nothing consumed")
	a.inventory.add("stick", 2)
	a.inventory.add("planks", 1)
	check(a.craft("wood_pick"), "wood pick crafts by hand")
	check(a.inventory.count("planks") == 0 and a.inventory.count("stick") == 0 and a.inventory.count("wood_pick") == 1, "exact inputs consumed")
	a.inventory.add("slate", 3)
	a.inventory.add("stick", 2)
	check(not a.craft("slate_pick"), "slate pick needs a workbench")
	var c := Vector3i(floori(a.position.x) + 1, floori(a.position.y), floori(a.position.z) + 1)
	game.map.set_block(c.x, c.y, c.z, B.WORKBENCH)
	check(a.craft("slate_pick") and a.inventory.count("slate") == 0, "slate pick crafts at a workbench")
	a.inventory.clear()
	for i in 36:
		a.inventory.set_slot(i, {"id": "wood_blade", "n": 1, "d": 60})
	a.inventory.set_slot(0, {"id": "timber", "n": 1})
	check(not a.craft("planks") and a.inventory.count("timber") == 1, "no room: recipe refused, inputs kept")
	a.inventory.clear()
	a.inventory.add("planks", 7)
	a.hotbar = 0
	check(a.selected_key() == String(a.inventory.get_slot(0).id), "hotbar shows the inventory's first row")
	await stop()

# Chunks around both players stay loaded even when they walk far apart.
func t_chunk_union() -> void:
	await start(true, false)
	var a = game.players[0]
	var b = game.players[1]
	b.position = game.map.find_safe_spot(a.position + Vector3(260, 0, 0), 20)
	var t := 0.0
	var map = game.map
	var r: int = map.view_radius
	var ok := false
	while t < 60.0:
		await frames(30)
		t += 0.5
		ok = true
		for p in [a, b]:
			var pc: Vector2i = map.chunk_of(floori(p.position.x), floori(p.position.z))
			for dx in range(-2, 3):
				for dz in range(-2, 3):
					var ch = map.chunks.get(pc + Vector2i(dx, dz))
					if ch == null or ch.meshed_version < 0:
						ok = false
		if ok:
			break
	check(ok, "both players' surroundings are generated and meshed")
	var count_missing := func() -> int:
		var missing := 0
		for p in [a, b]:
			var pc: Vector2i = map.chunk_of(floori(p.position.x), floori(p.position.z))
			for dx in range(-r, r + 1):
				for dz in range(-r, r + 1):
					if dx * dx + dz * dz <= r * r and not map.chunks.has(pc + Vector2i(dx, dz)):
						missing += 1
		return missing
	t = 0.0
	while count_missing.call() > 0 and t < 90.0:
		await frames(30)
		t += 0.5
	check(count_missing.call() == 0, "both full views loaded at once (%d chunks missing)" % count_missing.call())
	await frames(240)
	check(count_missing.call() == 0, "nothing inside either view is unloaded while both play")
	await stop()

# Saves: rolling backup, fallback when damaged, refuses newer formats, rename/delete.
func t_saves_robustness() -> void:
	var s = game.saves
	var id: String = s.create("Robust", "survival", 7)
	check(id != "", "create world")
	var data: Dictionary = s.load_world(id)
	data["time"] = 123.0
	check(s.write(id, data), "second write")
	var f := FileAccess.open(s.world_path(id), FileAccess.WRITE)
	f.store_string("{broken")
	f.close()
	var back: Dictionary = s.load_world(id)
	check(not back.has("error") and back.get("restored_from_backup", false), "damaged save falls back to the backup")
	var newer := {"format": s.FORMAT, "version": 99, "rules": "survival", "edits": {}, "players": {}}
	f = FileAccess.open(s.world_path(id), FileAccess.WRITE)
	f.store_string(JSON.stringify(newer))
	f.close()
	var text := FileAccess.get_file_as_string(s.world_path(id))
	check(s.load_world(id).get("error", "") == "made by a newer version of the game", "newer format is refused")
	check(FileAccess.get_file_as_string(s.world_path(id)) == text, "refused save left untouched")
	var id2: String = s.create("Rename me", "creative", 9)
	check(s.rename(id2, "Lilac Hollow") and s.load_world(id2).name == "Lilac Hollow", "rename")
	check(s.list().any(func(w): return w.id == id2 and w.name == "Lilac Hollow"), "list shows the renamed world")
	check(s.delete(id2) and not DirAccess.dir_exists_absolute(s.root + "/" + id2), "delete removes the slot")

# A real starter (v1) save imports into a new slot and the v1 file is never modified.
func t_v1_import() -> void:
	var s = game.saves
	var legacy: String = s.legacy_paths[0]
	DirAccess.copy_absolute("res://tests/fixtures/world-v1.json", legacy)
	var before := FileAccess.get_file_as_bytes(legacy)
	var st: Dictionary = s.legacy_status()
	check(st.present and st.valid and st.imported_id == "", "v1 save detected")
	var id: String = s.import_legacy()
	check(id != "", "v1 import creates a slot")
	check(FileAccess.get_file_as_bytes(legacy) == before, "v1 file unchanged by import")
	check(s.legacy_status().imported_id == id, "import is remembered (no duplicate offers)")
	var data: Dictionary = s.load_world(id)
	check(data.rules == "survival" and data.players.has("ola") and data.players.has("naba"), "rules and both players migrated")
	var ola := {}
	for slot in data.players.ola.inventory:
		ola[slot.id] = int(ola.get(slot.id, 0)) + int(slot.n)
	check(ola.get("moss", 0) == 3 and ola.get("slate", 0) == 2 and ola.get("timber", 0) == 1 and ola.get("planks", 0) == 5, "Ola's v1 stock migrated")
	check(int(data.players.ola.health) == 16 and int(data.players.naba.food) == 12, "health and stamina mapped")
	game.start_session(id, data, true, false, 0)
	await H.wait_loaded(self, game)
	check(game.map.get_block(6, 11 + Legacy.Y_SHIFT, 2) == B.GLOWGLASS, "v1 edit (glowglass) present after import")
	check(game.map.get_block(0, 0 + Legacy.Y_SHIFT, 0) == B.AIR, "v1 removed block still removed")
	var cells: Dictionary = Legacy.v1_cells(40521, {})
	var same := 0
	var total := 0
	for c in cells:
		var cell: Vector3i = c
		if absi(cell.x) > 10 or absi(cell.z) > 10 or (cell.x == 0 and cell.y == 0 and cell.z == 0):
			continue
		total += 1
		if game.map.get_block(cell.x, cell.y + Legacy.Y_SHIFT, cell.z) == Legacy.V1_TO_V2[int(cells[c])]:
			same += 1
	check(total > 0 and same == total, "v1 island terrain reproduced (%d/%d cells)" % [same, total])
	await stop()
	var f := FileAccess.open(legacy, FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	var garbage := FileAccess.get_file_as_bytes(legacy)
	check(not s.legacy_status().valid and s.import_legacy() == "", "unreadable v1 save is not imported")
	check(FileAccess.get_file_as_bytes(legacy) == garbage, "unreadable v1 save left untouched")
