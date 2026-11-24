extends SceneTree
const World := preload("res://src/voxel_world.gd")
const Mobs := preload("res://src/mobs.gd")
const Avatar := preload("res://src/avatar.gd")
const B := preload("res://src/blocks.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var w := World.new()
	root.add_child(w)
	w.setup(40521)
	w.view_radius = 3
	var spot := w.find_safe_spot(Vector3(8, 0, 8))
	w.ensure_data(spot, 1)
	for x in range(-6, 7):
		for z in range(-4, 6):
			for y in range(-1, 6):
				w.set_block(int(spot.x) + x, int(spot.y) + y, int(spot.z) + z, B.MOSS if y == -1 else B.AIR)
	w.set_block(int(spot.x) + 4, int(spot.y), int(spot.z) + 2, B.LANTERN)
	w.set_block(int(spot.x) - 4, int(spot.y), int(spot.z) + 3, B.GLOWGLASS)
	while w.loaded_progress() < 1.0 or not w.pending_mesh.is_empty():
		w.update_streaming([spot])
		await process_frame
	var night := OS.get_environment("NIGHT") == "1"
	var day := 0.12 if night else 1.0
	w.set_daylight(day)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#1c2147") if night else Color("#a9dce4")
	env.environment = e
	root.add_child(env)
	var mobs := Mobs.new()
	mobs.world = w
	root.add_child(mobs)
	var g1 = mobs.spawn("gloomling", spot + Vector3(-1.5, 0, 1.5))
	var g2 = mobs.spawn("gloomling", spot + Vector3(1.2, 0, 2.5))
	var p1 = mobs.spawn("puffkin", spot + Vector3(2.8, 0, 0.5))
	g1.yaw = 0.3
	g2.yaw = -0.5
	p1.yaw = 0.8
	var a := Avatar.new()
	root.add_child(a)
	a.build(0)
	a.position = spot + Vector3(-3.2, 0, 0.2)
	a.rotation.y = -0.6
	a.set_held("wood_blade")
	for m in mobs.mobs:
		m.node.position = m.pos
		m.node.rotation.y = m.yaw
		for k in ["daylight", "sky_light", "block_light"]:
			pass
		m.mat.set_shader_parameter("daylight", day)
	a.set_light(day, 1.0, 0.0)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = spot + Vector3(0, 1.8, -4.6)
	cam.look_at(spot + Vector3(0, 0.6, 1.0))
	cam.fov = 62
	cam.current = true
	for k in 6:
		await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	w.shutdown()
	quit(0)
