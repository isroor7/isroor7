# Shared setup for headless tests: an isolated save folder and settings file per test run.
extends RefCounted

static func wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		wipe(dir + "/" + sub)
		DirAccess.remove_absolute(dir + "/" + sub)
	for f in d.get_files():
		d.remove(f)

static func make_game(tree: SceneTree, tag: String) -> Node:
	var Saves := load("res://src/saves.gd")
	var root := "user://test-%s" % tag
	DirAccess.make_dir_recursive_absolute(root)
	wipe(root)
	var game = load("res://main.tscn").instantiate()
	game.settings_path = root + "/settings.json"
	tree.root.add_child(game)
	game.saves = Saves.new(root + "/worlds", [root + "/world-v1.json", root + "/world-v1.backup.json"])
	return game

static func wait_loaded(tree: SceneTree, game: Node, limit := 30.0) -> void:
	var t := 0.0
	while game.loading and t < limit:
		await tree.physics_frame
		t += 1.0 / 60.0
	game.map.wait_all()
