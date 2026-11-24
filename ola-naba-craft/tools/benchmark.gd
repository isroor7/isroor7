# Frame-time benchmark for real hardware. Runs a Survival world solo and split-screen, turning the
# cameras for 20 seconds each after loading, and prints average / 95th percentile / worst frame times.
#   godot --path . --resolution 1280x720  --script tools/benchmark.gd
#   godot --path . --resolution 1920x1080 --script tools/benchmark.gd
# Results are also written to user://benchmark.txt. Do not run with --headless (nothing is drawn).
extends SceneTree
const H := preload("res://tests/helpers.gd")
var lines := []
func _initialize() -> void:
	call_deferred("run")
func measure(game, label: String, seconds := 20.0) -> void:
	var samples := PackedFloat32Array()
	var t := 0.0
	var last := Time.get_ticks_usec()
	while t < seconds:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		samples.append(ms)
		t += ms / 1000.0
		for p in game.players:
			p.yaw += ms / 1000.0 * 0.6
	samples.sort()
	var avg := 0.0
	for v in samples:
		avg += v
	avg /= samples.size()
	var line := "%s  %dx%d  avg %.2f ms (%.0f fps)  p95 %.2f ms  worst %.2f ms  chunks %d  GPU %s" % [label,
		root.get_visible_rect().size.x, root.get_visible_rect().size.y, avg, 1000.0 / avg,
		samples[int(samples.size() * 0.95)], samples[samples.size() - 1], game.map.chunks.size(), RenderingServer.get_video_adapter_name()]
	print(line)
	lines.append(line)
func run() -> void:
	var game = H.make_game(self, "bench")
	for split in [false, true]:
		game.start_game(split, false, 0, false)
		await H.wait_loaded(self, game, 60.0)
		for i in 120:
			await process_frame
		await measure(game, "split" if split else "solo ")
		game.end_session()
		await process_frame
	var f := FileAccess.open("user://benchmark.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(0)
