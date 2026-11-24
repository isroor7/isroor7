# Named world slots on disk. Each world lives in <root>/<id>/ as world.json (full data), a rolling
# world.backup.json (the previous good save) and meta.json (name, rules, dates for the list).
# Writes go to a temporary file first; the old save is copied to the backup before it is replaced.
extends RefCounted

const Legacy := preload("res://src/legacy_v1.gd")
const FORMAT := "ola-naba-craft-world"
const VERSION := 2
const LEGACY_PATH := "user://world-v1.json"
const LEGACY_BACKUP := "user://world-v1.backup.json"

var root := "user://worlds"
var legacy_paths := [LEGACY_PATH, LEGACY_BACKUP]

func _init(dir := "user://worlds", legacy := [LEGACY_PATH, LEGACY_BACKUP]) -> void:
	root = dir
	legacy_paths = legacy

func _dir(id: String) -> String:
	return root + "/" + id

func world_path(id: String) -> String:
	return _dir(id) + "/world.json"

func backup_path(id: String) -> String:
	return _dir(id) + "/world.backup.json"

func meta_path(id: String) -> String:
	return _dir(id) + "/meta.json"

func new_id() -> String:
	var base := "world-%d" % int(Time.get_unix_time_from_system())
	var id := base
	var n := 2
	while DirAccess.dir_exists_absolute(_dir(id)):
		id = "%s-%d" % [base, n]
		n += 1
	return id

# Returns metadata for every world, most recently played first.
func list() -> Array:
	var out := []
	var d := DirAccess.open(root)
	if d == null:
		return out
	for id in d.get_directories():
		var meta := _read_json(meta_path(id))
		if meta.is_empty():
			var full := load_world(id)
			if full.has("error"):
				meta = {"name": id, "error": full.error}
			else:
				meta = _meta_of(full)
		meta["id"] = id
		out.append(meta)
	out.sort_custom(func(a, b): return float(a.get("last_played", 0)) > float(b.get("last_played", 0)))
	return out

func _meta_of(data: Dictionary) -> Dictionary:
	return {"name": data.get("name", "World"), "rules": data.get("rules", "survival"), "seed": data.get("seed", 0),
		"created": data.get("created", 0), "last_played": data.get("last_played", 0), "version": data.get("version", VERSION),
		"day": int(float(data.get("time", 0)) / 600.0) + 1, "players": (data.get("players", {}) as Dictionary).keys(),
		"imported_from": data.get("imported_from", {})}

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

# Why a parsed world cannot be used ("" when it is fine).
static func problem(data: Dictionary) -> String:
	if data.is_empty():
		return "unreadable"
	if data.get("format", "") != FORMAT:
		return "not an Ola-Naba Craft world"
	var v := int(data.get("version", -1))
	if v > VERSION:
		return "made by a newer version of the game"
	if v < VERSION:
		return "old format"
	if not data.get("edits") is Dictionary or not data.get("players") is Dictionary:
		return "damaged"
	if not (data.get("rules", "") in ["creative", "survival"]):
		return "damaged"
	return ""

# Loads a world, falling back to its backup if the main file is damaged.
# Returns the data, or {"error": reason} without changing any file.
func load_world(id: String) -> Dictionary:
	var main := _read_json(world_path(id))
	var why := problem(main)
	if why == "":
		return main
	if why == "made by a newer version of the game":
		return {"error": why}
	var backup := _read_json(backup_path(id))
	if problem(backup) == "":
		backup["restored_from_backup"] = true
		return backup
	return {"error": why}

func write(id: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(_dir(id))
	data["format"] = FORMAT
	data["version"] = VERSION
	data["last_played"] = Time.get_unix_time_from_system()
	data.erase("restored_from_backup")
	var text := JSON.stringify(data)
	var temp := world_path(id) + ".tmp"
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		return false
	var ok := f.store_string(text)
	f.flush()
	var err := f.get_error()
	f.close()
	if not ok or err != OK:
		return false
	# keep the previous good save as the backup before replacing it
	if problem(_read_json(world_path(id))) == "":
		if DirAccess.copy_absolute(world_path(id), backup_path(id)) != OK:
			return false
	if DirAccess.rename_absolute(temp, world_path(id)) != OK:
		return false
	var mf := FileAccess.open(meta_path(id), FileAccess.WRITE)
	if mf:
		mf.store_string(JSON.stringify(_meta_of(data)))
		mf.close()
	return true

func create(name: String, rules: String, seed_value: int) -> String:
	var id := new_id()
	var data := {"name": name, "rules": rules, "seed": seed_value, "created": Time.get_unix_time_from_system(),
		"time": 40.0, "edits": {}, "players": {}, "session": {}}
	return id if write(id, data) else ""

func rename(id: String, name: String) -> bool:
	var data := load_world(id)
	if data.has("error"):
		return false
	data["name"] = name
	return write(id, data)

func delete(id: String) -> bool:
	var d := DirAccess.open(_dir(id))
	if d == null:
		return false
	for f in d.get_files():
		d.remove(f)
	return DirAccess.remove_absolute(_dir(id)) == OK

# ------------------------------------------------------------------ edits encoding

# {Vector2i: {local index: block}} -> {"cx,cz": [index, block, index, block, ...]}
static func encode_edits(edits: Dictionary) -> Dictionary:
	var out := {}
	for k in edits:
		var key: Vector2i = k
		var flat := []
		for idx in edits[k]:
			flat.append(int(idx))
			flat.append(int(edits[k][idx]))
		if not flat.is_empty():
			out["%d,%d" % [key.x, key.y]] = flat
	return out

static func decode_edits(data: Dictionary, block_count: int, chunk_volume: int) -> Dictionary:
	var out := {}
	for k in data:
		var parts := String(k).split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or not data[k] is Array:
			continue
		var flat: Array = data[k]
		var cells := {}
		for i in range(0, flat.size() - 1, 2):
			var idx := int(flat[i])
			var id := int(flat[i + 1])
			if idx >= 0 and idx < chunk_volume and id >= 0 and id < block_count:
				cells[idx] = id
		out[Vector2i(int(parts[0]), int(parts[1]))] = cells
	return out

# ------------------------------------------------------------------ starter (v1) saves

# The v1 file is only ever read. Importing creates a new slot and leaves v1 untouched.
func legacy_status() -> Dictionary:
	var path := ""
	for p in legacy_paths:
		if FileAccess.file_exists(p):
			path = p
			break
	if path == "":
		return {"present": false}
	var v1 := Legacy.read_v1(path)
	if v1.is_empty() and path == legacy_paths[0] and legacy_paths.size() > 1:
		var alt := Legacy.read_v1(legacy_paths[1])
		if not alt.is_empty():
			path = legacy_paths[1]
			v1 = alt
	var stamp := "%s|%d|%d" % [path, FileAccess.get_modified_time(path), FileAccess.get_file_as_bytes(path).size()]
	var imported := ""
	for w in list():
		if (w.get("imported_from", {}) as Dictionary).get("stamp", "") == stamp:
			imported = w.id
	return {"present": true, "valid": not v1.is_empty(), "path": path, "stamp": stamp, "imported_id": imported}

func import_legacy() -> String:
	var st := legacy_status()
	if not st.get("valid", false):
		return ""
	var v1 := Legacy.read_v1(st.path)
	var data := Legacy.convert(v1)
	data["edits"] = encode_edits(data.edits)
	data["name"] = "Starter world (imported)"
	data["created"] = Time.get_unix_time_from_system()
	data["imported_from"] = {"file": st.path, "stamp": st.stamp, "version": 1}
	var id := new_id()
	return id if write(id, data) else ""
