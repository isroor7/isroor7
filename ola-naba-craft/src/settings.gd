# Player preferences saved to user://settings.json (never inside a world save).
extends RefCounted

const PATH := "user://settings.json"
const DEFAULTS := {
	"view_distance": 6,
	"fullscreen": false,
	"vsync": true,
	"master_volume": 0.8,
	"stacked": false,
	"naba_tablet": true,
	"players": [
		{"sens_mouse": 1.0, "sens_stick": 1.0, "invert_y": false, "deadzone": 0.2},
		{"sens_mouse": 1.0, "sens_stick": 1.0, "invert_y": false, "deadzone": 0.2},
	],
	"bindings": {},
}

static func load_settings(path := PATH) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			for k in parsed:
				if out.has(k) and typeof(parsed[k]) == typeof(out[k]):
					out[k] = parsed[k]
				elif out.has(k) and (parsed[k] is float or parsed[k] is int) and (out[k] is float or out[k] is int):
					out[k] = parsed[k]
	out.view_distance = clampi(int(out.view_distance), 3, 12)
	while (out.players as Array).size() < 2:
		out.players.append(DEFAULTS.players[0].duplicate())
	return out

static func save_settings(s: Dictionary, path := PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(s, "\t"))
	f.close()
	return true

static func apply_video(s: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if s.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if s.vsync else DisplayServer.VSYNC_DISABLED)
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(float(s.master_volume), 0.0, 1.0)))
