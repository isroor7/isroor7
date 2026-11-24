# Renders the world from a fixed camera (needs a display) and prints streaming timings.
extends SceneTree
const World := preload("res://src/voxel_world.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var w := World.new()
	root.add_child(w)
	w.setup(int(OS.get_environment("SEED") if OS.get_environment("SEED") != "" else "40521"))
	w.view_radius = 6
	var t0 := Time.get_ticks_msec()
	var center := Vector3(8, 0, 8)
	w.ensure_data(center, 0)
	var spot := w.find_safe_spot(center)
	print("spawn ", spot, " biome ", w.biome_name(spot))
	var frames := 0
	while w.loaded_progress() < 1.0 or not w.pending_mesh.is_empty() or not w.pending_gen.is_empty():
		w.update_streaming([spot])
		await process_frame
		frames += 1
		if frames > 3000:
			break
	print("loaded %d chunks, meshed %d in %d ms over %d frames; avg mesh job %.1f ms" % [w.chunks.size(), w.stats.meshed, Time.get_ticks_msec() - t0, frames, w.stats.mesh_ms])
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#9fd3e0")
	e.fog_enabled = true
	e.fog_light_color = Color("#f3dcc0")
	e.fog_density = 0.008
	env.environment = e
	root.add_child(env)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = spot + Vector3(-18, 16, 22)
	cam.look_at(spot + Vector3(6, -2, -6))
	cam.far = 300
	cam.current = true
	w.set_daylight(float(OS.get_environment("DAY") if OS.get_environment("DAY") != "" else "1.0"))
	for i in 10:
		await process_frame
	var out := OS.get_environment("SHOT_OUT")
	if out != "":
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
	w.shutdown()
	quit(0)
