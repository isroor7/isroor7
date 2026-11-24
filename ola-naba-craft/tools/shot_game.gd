# Renders a gameplay screenshot (needs a display). Env: SHOT_OUT, SPLIT=1, STACKED=1, CREATIVE=1,
# TIME=<seconds into the day>, INV=1 (open player 1's inventory), MENU=title|pause.
extends SceneTree
const H := preload("res://tests/helpers.gd")
func _initialize() -> void:
	call_deferred("run")
func env(k: String, d := "") -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d
func run() -> void:
	var game = H.make_game(self, "shot")
	if env("MENU") == "title":
		for i in 10:
			await process_frame
		root.get_texture().get_image().save_png(env("SHOT_OUT"))
		quit(0)
		return
	game.start_game(env("SPLIT") == "1", env("CREATIVE") == "1", int(env("AVATAR", "0")), env("STACKED") == "1")
	await H.wait_loaded(self, game)
	game.time = float(env("TIME", "60"))
	for p in game.players:
		p.yaw = float(env("YAW", "0.4"))
		p.pitch = -0.28
	if game.players.size() > 1:
		var a = game.players[0]
		var b = game.players[1]
		b.position = game.map.find_safe_spot(a.position + Vector3(2.5, 0, -3.0), 6)
		b.yaw = a.yaw + PI * 0.85
		b.inventory.add("wood_pick", 1)
		a.inventory.add("planks", 24)
		a.inventory.add("berries", 3)
		b.inventory.add("timber", 5)
		b.hotbar = 0
	for i in 90:
		await physics_frame
	if env("INV") == "1":
		game.toggle_inventory(game.players[0], false)
		game.inv_uis[0].tab = 1
	if env("MENU") == "pause":
		game.set_pause(true)
	if env("GLOOM") == "1":
		var p = game.players[0]
		var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
		game.mobs.spawn("gloomling", game.map.find_safe_spot(p.position + fwd * 4.0, 4))
		game.mobs.spawn("puffkin", game.map.find_safe_spot(p.position + fwd * 5.0 + Vector3(2, 0, 0), 4))
	for i in 30:
		await process_frame
	var t0 := Time.get_ticks_usec()
	for i in 30:
		await process_frame
	print("frame ms (software GL): %.1f" % ((Time.get_ticks_usec() - t0) / 30000.0))
	root.get_texture().get_image().save_png(env("SHOT_OUT"))
	game.end_session()
	quit(0)
