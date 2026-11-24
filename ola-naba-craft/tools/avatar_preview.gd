extends SceneTree
const World := preload("res://src/voxel_world.gd")
const Avatar := preload("res://src/avatar.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var w := World.new()
	root.add_child(w)
	w.setup(40521)
	w.view_radius = 3
	var spot := w.find_safe_spot(Vector3(8, 0, 8))
	w.ensure_data(spot, 1)
	var B := load("res://src/blocks.gd")
	for x in range(-6, 7):
		for z in range(-4, 5):
			for y in range(-1, 6):
				var id: int = B.PLANKS if y == -1 else B.AIR
				if z == 4 and y >= 0:
					id = B.SLATE_BRICK
				w.set_block(int(spot.x) + x, int(spot.y) + y, int(spot.z) + z, id)
	while w.loaded_progress() < 1.0 or not w.pending_mesh.is_empty():
		w.update_streaming([spot])
		await process_frame
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#a9dce4")
	env.environment = e
	root.add_child(env)
	var poses := [[0, 0.0, false], [0, PI, false], [1, 0.0, true], [1, PI, true], [0, 0.6, false], [1, -0.6, false]]
	var i := 0
	for p in poses:
		var a := Avatar.new()
		root.add_child(a)
		a.build(p[0], p[2])
		a.position = spot + Vector3(-3.0 + i * 1.2, 0, 0)
		a.rotation.y = p[1]
		if i == 4:
			a.set_held("wood_pick")
		if i == 5:
			a.set_held("planks")
		a.animate(0.016, {"speed": 4.0 if i >= 4 else 0.0, "floor": true})
		for k in 8:
			a.animate(0.03, {"speed": 4.0 if i >= 4 else 0.0, "floor": true})
		i += 1
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = spot + Vector3(0.0, 1.5, -4.4)
	cam.look_at(spot + Vector3(0.0, 0.9, 0))
	cam.fov = 60
	cam.current = true
	for k in 6:
		await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	w.shutdown()
	quit(0)
