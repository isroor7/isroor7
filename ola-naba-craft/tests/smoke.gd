# The starter's smoke test, carried forward to the chunked world and third-person players.
# Same behaviours: two viewports, shared world, mine/place, inventory isolation, crafting,
# eating, saving with a backup, restoring, pause, solo/stacked setups and per-player input.
extends SceneTree

const H := preload("res://tests/helpers.gd")
const B := preload("res://src/blocks.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, note: String) -> void:
	if not value:
		failures += 1
		push_error(note)
		print("  FAIL: ", note)

func run() -> void:
	var game = H.make_game(self, "smoke")
	game.start_game(true, false, 0, false)
	check(game.players.size() == 2 and game.huds.size() == 2, "Expected two viewports and HUDs")
	var p = game.players[0]
	var p2 = game.players[1]
	check(p.avatar == 0 and p2.avatar == 1, "Incorrect character assignment")
	check(p.keys() != p2.keys(), "Players must have independent keys")
	check(p.eye.get_world_3d() == p2.eye.get_world_3d(), "Players must share a world")
	check(p.eye.get_viewport() != p2.eye.get_viewport(), "Players must have separate cameras")
	await H.wait_loaded(self, game)
	for i in 40:
		await physics_frame
	check(p.is_on_floor(), "Expected player to land on terrain")
	p.pitch = -1.47
	p.sync_view()
	p.update_target()
	check(not p.target.is_empty(), "Mining ray missed the ground")
	var ground_id: int = p.target.id
	var drop_key: String = B.drops(ground_id)[0][0]
	check(p.use_block(false), "Could not mine the ground")
	for i in 90:
		await physics_frame
	check(p.inventory.count(drop_key) == 1, "Mined block was not collected (%s)" % drop_key)
	var had: int = p.inventory.count(drop_key)
	p.hotbar = 0
	p.yaw = PI / 2
	p.pitch = -0.9
	p.sync_view()
	var placed := false
	for attempt in 8:
		p.yaw += 0.7
		p.sync_view()
		if p.use_block(true):
			placed = true
			break
	check(placed, "Could not place the collected block")
	check(p.inventory.count(drop_key) == had - 1 and p2.inventory.count(drop_key) == 0, "Inventory decrement or player isolation failed")
	p.inventory.add("timber", 1)
	check(p.craft_planks() and p.inventory.count("timber") == 0 and p.inventory.count("planks") == 4, "Craft recipe failed")
	p.inventory.add("berries", 1)
	p.food = 10
	check(p.eat_canopy_berries() and p.food == 14, "Survival snack did not restore food")
	var cell := Vector3i(floori(p.position.x) + 2, floori(p.position.y) + 3, floori(p.position.z))
	check(game.map.change(cell, B.GLOWGLASS), "Could not set fixture block")
	check(game.save_world() and game.save_world(), "Save write or replacement failed")
	var backup: Dictionary = game.saves._read_json(game.saves.backup_path(game.world_id))
	check(game.saves.problem(backup) == "", "A prior save must be backed up")
	game.end_session()
	await process_frame
	game.continue_world()
	await H.wait_loaded(self, game)
	check(game.players.size() == 2 and not game.mode, "Save mode/layout did not restore")
	check(game.players[0].inventory.count("planks") == 4, "Player inventory was not restored")
	check(game.map.get_cell_item(cell) == B.GLOWGLASS, "Shared edited voxel was not restored")
	game.set_pause(true)
	check(game.pause_open and not game.players[0].controls and not game.players[1].controls, "Pause did not lock both players")
	game.set_pause(false)
	game.end_session()
	await process_frame
	game.start_game(false, true, 1, false)
	check(game.players.size() == 1 and game.players[0].avatar == 1 and game.players[0].creative, "Solo Creative/Naba setup failed")
	game.end_session()
	await process_frame
	game.start_game(true, true, 0, true)
	check(game.players.size() == 2 and game.panes is VBoxContainer, "Stacked Creative co-op setup failed")
	await H.wait_loaded(self, game)
	for i in 30:
		await physics_frame
	var a = game.players[0]
	var b = game.players[1]
	var old_a: Vector3 = a.position
	var old_b: Vector3 = b.position
	var move := InputEventKey.new()
	move.physical_keycode = KEY_I
	move.pressed = true
	Input.parse_input_event(move)
	await create_timer(.3).timeout
	move = InputEventKey.new()
	move.physical_keycode = KEY_I
	Input.parse_input_event(move)
	check(a.position.distance_to(old_a) < .01 and b.position.distance_to(old_b) > .1, "Simulated P2 movement should not move P1")
	game.end_session()
	await process_frame
	game.start_game(false, false, 0, false)
	check(game.players.size() == 1 and game.players[0].avatar == 0 and not game.mode, "Solo Survival/Ola setup failed")
	game.end_session()
	print("SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
