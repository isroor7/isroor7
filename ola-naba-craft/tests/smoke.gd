extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, note: String) -> void:
	if not value:
		failures += 1
		push_error(note)

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.save_path = "user://smoke-test.json"
	game.backup_path = "user://smoke-test.backup.json"
	game.start_game(true, false, 0, false)
	check(game.players.size() == 2 and game.huds.size() == 2, "Expected two viewports and HUDs")
	var p = game.players[0]
	var p2 = game.players[1]
	check(p.avatar == 0 and p2.avatar == 1, "Incorrect character assignment")
	check(p.keys() != p2.keys(), "Players must have independent keys")
	check(p.eye.get_world_3d() == p2.eye.get_world_3d(), "Players must share a world")
	check(p.eye.get_viewport() != p2.eye.get_viewport(), "Players must have separate cameras")
	await create_timer(.45).timeout
	p.pitch = -1.47
	p.sync_view()
	await physics_frame
	await process_frame
	check(p.is_on_floor(), "Expected player to land on terrain")
	check(p.use_block(false), "Mining ray missed the ground")
	check(p.inventory[0] == 1, "Mined block not collected")
	p.position = Vector3(-.35, 1.0, .5)
	p.yaw = PI / 2
	p.pitch = -1.10
	p.sync_view()
	await create_timer(.10).timeout
	check(p.use_block(true), "Could not place collected block")
	check(p.inventory[0] == 0 and p2.inventory[0] == 0, "Inventory decrement or player isolation failed")
	p.inventory[3] = 1
	check(p.craft_planks() and p.inventory[3] == 0 and p.inventory[5] == 4, "Craft recipe failed")
	p.inventory[4] = 1
	p.stamina = 2
	check(p.eat_canopy_berries() and p.stamina == 4, "Survival snack did not replenish stamina")
	var position_key := Vector3i(6, 11, 2)
	check(game.map.change(position_key, 6), "Could not set fixture block")
	check(game.save_world() and game.save_world(), "Save write or replacement failed")
	check(not game.read_save(game.backup_path).is_empty(), "A prior save must be backed up")
	game.end_session()
	await process_frame
	game.continue_world()
	check(game.players.size() == 2 and not game.mode, "Save mode/layout did not restore")
	check(game.players[0].inventory[5] == 4, "Player inventory was not restored")
	check(game.map.get_cell_item(position_key) == 6, "Shared edited voxel was not restored")
	game.set_pause(true)
	check(game.pause_open and not game.players[0].controls and not game.players[1].controls, "Pause did not lock both players")
	game.end_session()
	await process_frame
	game.start_game(false, true, 1, false)
	check(game.players.size() == 1 and game.players[0].avatar == 1 and game.players[0].creative, "Solo Creative/Naba setup failed")
	game.end_session()
	await process_frame
	game.start_game(true, true, 0, true)
	check(game.players.size() == 2 and game.panes is VBoxContainer, "Stacked Creative co-op setup failed")
	var a = game.players[0]
	var b = game.players[1]
	var old_a: Vector3 = a.position
	var old_b: Vector3 = b.position
	var move := InputEventKey.new()
	move.physical_keycode = KEY_I
	move.pressed = true
	Input.parse_input_event(move)
	await create_timer(.15).timeout
	move = InputEventKey.new()
	move.physical_keycode = KEY_I
	Input.parse_input_event(move)
	check(a.position.distance_to(old_a) < .01 and b.position.distance_to(old_b) > .1,
		"Simulated P2 movement should not move P1")
	game.end_session()
	await process_frame
	game.start_game(false, false, 0, false)
	check(game.players.size() == 1 and game.players[0].avatar == 0 and not game.mode, "Solo Survival/Ola setup failed")
	print("SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
