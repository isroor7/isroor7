# Chunked voxel world: block storage, edit tracking over the deterministic seed, background
# generation and meshing on the WorkerThreadPool, streaming around every player at once,
# voxel raycasts and box collision for players and creatures.
extends Node3D

const B := preload("res://src/blocks.gd")
const Gen := preload("res://src/world_gen.gd")
const Mesher := preload("res://src/chunk_mesher.gd")
const Textures := preload("res://src/textures.gd")
const SOLID_SHADER := preload("res://src/shaders/voxel_solid.gdshader")
const CLEAR_SHADER := preload("res://src/shaders/voxel_clear.gdshader")

const CS := 16
const H := 96
const SEA := 30
const BUILD_LIMIT := H - 4

class Chunk:
	var key: Vector2i
	var data: PackedByteArray
	var tops: PackedByteArray   # per column: (highest sky-stopping y) + 1, 0 when open to the sky
	var maxy := 0
	var version := 0
	var meshed_version := -1
	var solid_mi: MeshInstance3D
	var clear_mi: MeshInstance3D

var seed_value := 40521
var gen: Gen
var chunks := {}         # Vector2i -> Chunk
var edits := {}          # Vector2i -> {local index: block id}; the only world data that is saved
var emitters := {}       # Vector2i -> {local index: light level}
var pending_gen := {}    # Vector2i -> [task id, job]
var pending_mesh := {}   # Vector2i -> [task id, job]
var urgent := {}         # chunks edited this frame; remeshed before anything else
var view_radius := 6
var threaded := true
var max_tasks := 6
var apply_budget_ms := 5.0
var centers: Array = []
var solid_mat: ShaderMaterial
var clear_mat: ShaderMaterial
var _needed := {}
var _needed_sig := ""
var stats := {"generated": 0, "meshed": 0, "mesh_ms": 0.0}

func setup(world_seed: int, saved_edits := {}) -> void:
	seed_value = world_seed
	gen = Gen.new(world_seed)
	Mesher.prepare()
	edits.clear()
	emitters.clear()
	for k in saved_edits:
		var key: Vector2i = k
		var cell_map: Dictionary = saved_edits[k]
		edits[key] = cell_map.duplicate()
		for idx in cell_map:
			var level: int = B.EMIT[int(cell_map[idx])]
			if level > 0:
				_emitters_for(key)[int(idx)] = level
	solid_mat = ShaderMaterial.new()
	solid_mat.shader = SOLID_SHADER
	solid_mat.set_shader_parameter("tiles", Textures.block_array())
	clear_mat = ShaderMaterial.new()
	clear_mat.shader = CLEAR_SHADER
	clear_mat.set_shader_parameter("tiles", Textures.block_array())
	clear_mat.render_priority = 1

func set_daylight(daylight: float) -> void:
	for m in [solid_mat, clear_mat]:
		m.set_shader_parameter("daylight", daylight)

func _emitters_for(key: Vector2i) -> Dictionary:
	if not emitters.has(key):
		emitters[key] = {}
	return emitters[key]

static func chunk_of(x: int, z: int) -> Vector2i:
	return Vector2i(floori(float(x) / CS), floori(float(z) / CS))

static func local_index(x: int, y: int, z: int) -> int:
	return (posmod(x, CS) * CS + posmod(z, CS)) * H + y

# ------------------------------------------------------------------ block access

func get_block(x: int, y: int, z: int) -> int:
	if y < 0:
		return B.DEEPSTONE
	if y >= H:
		return B.AIR
	var ch: Chunk = chunks.get(chunk_of(x, z))
	if ch == null:
		return -1
	return ch.data[local_index(x, y, z)]

func get_blockv(p: Vector3i) -> int:
	return get_block(p.x, p.y, p.z)

func is_solid(x: int, y: int, z: int) -> bool:
	var id := get_block(x, y, z)
	return id < 0 or B.SOLID[id]

func is_loaded(x: int, z: int) -> bool:
	return chunks.has(chunk_of(x, z))

# Changes one block. Returns false when nothing changed (same block, outside the build range or
# not loaded), so two players editing the same cell in one frame produce exactly one mutation.
func set_block(x: int, y: int, z: int, id: int) -> bool:
	if y < 1 or y > BUILD_LIMIT or id < 0 or id >= B.COUNT:
		return false
	var key := chunk_of(x, z)
	var ch: Chunk = chunks.get(key)
	if ch == null:
		return false
	var idx := local_index(x, y, z)
	var old := ch.data[idx]
	if old == id:
		return false
	ch.data[idx] = id
	if not edits.has(key):
		edits[key] = {}
	edits[key][idx] = id
	_recompute_top(ch, posmod(x, CS), posmod(z, CS))
	if id != B.AIR:
		ch.maxy = maxi(ch.maxy, y)
	var light_changed: bool = B.EMIT[old] > 0 or B.EMIT[id] > 0
	if B.EMIT[old] > 0:
		_emitters_for(key).erase(idx)
	if B.EMIT[id] > 0:
		_emitters_for(key)[idx] = B.EMIT[id]
	_touch(key)
	var lx := posmod(x, CS)
	var lz := posmod(z, CS)
	var reach := B.MAX_LIGHT if light_changed else 1
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			if (dx == -1 and lx >= reach) or (dx == 1 and lx < CS - reach):
				continue
			if (dz == -1 and lz >= reach) or (dz == 1 and lz < CS - reach):
				continue
			_touch(key + Vector2i(dx, dz))
	return true

func _touch(key: Vector2i) -> void:
	var ch: Chunk = chunks.get(key)
	if ch != null:
		ch.version += 1
		urgent[key] = true

# Compatibility helpers kept from the starter's GridMap API.
func change(cell: Vector3i, kind: int) -> bool:
	return set_block(cell.x, cell.y, cell.z, kind)

func get_cell_item(cell: Vector3i) -> int:
	return get_block(cell.x, cell.y, cell.z)

func _recompute_top(ch: Chunk, lx: int, lz: int) -> void:
	var base := (lx * CS + lz) * H
	var top := 0
	for y in range(H - 1, -1, -1):
		if B.SKY_STOP[ch.data[base + y]]:
			top = y + 1
			break
	ch.tops[lx * CS + lz] = top

# ------------------------------------------------------------------ generation and meshing

static func _gen_job(job: Dictionary) -> void:
	var g := Gen.new(int(job.seed))
	var data: PackedByteArray = g.generate(int(job.cx), int(job.cz))
	var tops := PackedByteArray()
	tops.resize(CS * CS)
	var maxy := 0
	for c in CS * CS:
		var base := c * H
		for y in range(H - 1, -1, -1):
			var id := data[base + y]
			if id != B.AIR:
				maxy = maxi(maxy, y)
				if B.SKY_STOP[id]:
					tops[c] = y + 1
					break
	job["data"] = data
	job["tops"] = tops
	job["maxy"] = maxy

static func _mesh_job(job: Dictionary) -> void:
	var t := Time.get_ticks_usec()
	job["result"] = Mesher.new().build(job)
	job["usec"] = Time.get_ticks_usec() - t

func _integrate(key: Vector2i, job: Dictionary) -> void:
	var ch := Chunk.new()
	ch.key = key
	ch.tops = job.tops
	ch.maxy = int(job.maxy)
	var data: PackedByteArray = job.data
	var changes: Dictionary = edits.get(key, {})
	var columns := {}
	for idx in changes:
		var i := int(idx)
		data[i] = int(changes[idx])   # local buffer: one copy-on-write at most, then in place
		if int(changes[idx]) != B.AIR:
			ch.maxy = maxi(ch.maxy, i % H)
		columns[i / H] = true
	ch.data = data
	for c in columns:
		_recompute_top(ch, int(c) / CS, int(c) % CS)
	chunks[key] = ch
	stats.generated += 1
	# a new chunk changes its neighbours' border faces
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if dx != 0 or dz != 0:
				var n: Chunk = chunks.get(key + Vector2i(dx, dz))
				if n != null and n.meshed_version >= 0:
					n.version += 1

func _neighbours_ready(key: Vector2i) -> bool:
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if not chunks.has(key + Vector2i(dx, dz)):
				return false
	return true

func _mesh_input(key: Vector2i) -> Dictionary:
	var arrays := []
	var tops := []
	var lights := []
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var nkey := key + Vector2i(dx, dz)
			var n: Chunk = chunks[nkey]
			arrays.append(n.data)
			tops.append(n.tops)
			for idx in emitters.get(nkey, {}):
				var i := int(idx)
				var lx := i / H / CS
				var lz := (i / H) % CS
				var px := lx + Mesher.P + dx * CS
				var pz := lz + Mesher.P + dz * CS
				if px >= 0 and px < Mesher.PW and pz >= 0 and pz < Mesher.PW:
					lights.append([px, i % H, pz, int(emitters[nkey][idx])])
	var ch: Chunk = chunks[key]
	return {"chunks": arrays, "tops": tops, "emitters": lights, "maxy": ch.maxy, "cx": key.x, "cz": key.y, "version": ch.version}

func _apply_mesh(ch: Chunk, result: Dictionary) -> void:
	ch.solid_mi = _set_mesh(ch.solid_mi, result.solid, solid_mat, ch.key)
	ch.clear_mi = _set_mesh(ch.clear_mi, result.clear, clear_mat, ch.key)
	stats.meshed += 1

func _set_mesh(mi: MeshInstance3D, arrs: Array, mat: Material, key: Vector2i) -> MeshInstance3D:
	if (arrs[0] as PackedVector3Array).is_empty():
		if mi != null:
			mi.queue_free()
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = arrs[0]
	arrays[Mesh.ARRAY_TEX_UV] = arrs[1]
	arrays[Mesh.ARRAY_TEX_UV2] = arrs[2]
	arrays[Mesh.ARRAY_COLOR] = arrs[3]
	arrays[Mesh.ARRAY_INDEX] = arrs[4]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(key.x * CS, 0, key.y * CS)
		add_child(mi)
	mi.mesh = mesh
	return mi

func _free_chunk(key: Vector2i) -> void:
	var ch: Chunk = chunks.get(key)
	if ch == null:
		return
	for mi in [ch.solid_mi, ch.clear_mi]:
		if mi != null:
			mi.queue_free()
	chunks.erase(key)
	urgent.erase(key)

# Chunks every player needs, with the distance to the nearest player as priority.
func _compute_needed() -> void:
	var sig := str(view_radius)
	for c in centers:
		var p: Vector3 = c
		sig += "|" + str(chunk_of(floori(p.x), floori(p.z)))
	if sig == _needed_sig:
		return
	_needed_sig = sig
	_needed.clear()
	var r := view_radius
	for c in centers:
		var p: Vector3 = c
		var pc := chunk_of(floori(p.x), floori(p.z))
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var d := sqrt(dx * dx + dz * dz)
				if d > r + 0.5:
					continue
				var key := pc + Vector2i(dx, dz)
				_needed[key] = minf(_needed.get(key, 9999.0), d)
	# unload only what is far from every player (never anything inside either view)
	for key in chunks.keys():
		var keep := false
		for c in centers:
			var p: Vector3 = c
			var pc := chunk_of(floori(p.x), floori(p.z))
			if absi(key.x - pc.x) <= r + 2 and absi(key.y - pc.y) <= r + 2:
				keep = true
				break
		if not keep:
			_free_chunk(key)

func update_streaming(player_positions: Array) -> void:
	centers = player_positions
	if centers.is_empty():
		return
	_compute_needed()
	_collect_finished()
	var running := pending_gen.size() + pending_mesh.size()
	if running >= max_tasks and threaded:
		return
	# 1. data for needed chunks and their neighbours, nearest first
	var gen_wanted := []
	for key in _needed:
		var pr: float = _needed[key]
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var k: Vector2i = key + Vector2i(dx, dz)
				if not chunks.has(k) and not pending_gen.has(k):
					gen_wanted.append([pr + 0.01 * (absi(dx) + absi(dz)), k])
	# 2. meshes for needed chunks whose neighbours exist; edited chunks jump the queue
	var mesh_wanted := []
	for key in _needed:
		var ch: Chunk = chunks.get(key)
		if ch == null or pending_mesh.has(key) or ch.meshed_version == ch.version:
			continue
		if not _neighbours_ready(key):
			continue
		mesh_wanted.append([-1.0 if urgent.has(key) else float(_needed[key]), key])
	mesh_wanted.sort_custom(func(a, b): return a[0] < b[0])
	gen_wanted.sort_custom(func(a, b): return a[0] < b[0])
	var seen := {}
	for item in mesh_wanted:
		if running >= max_tasks and threaded:
			break
		_start_mesh(item[1])
		running += 1
	for item in gen_wanted:
		if running >= max_tasks and threaded:
			break
		if seen.has(item[1]):
			continue
		seen[item[1]] = true
		_start_gen(item[1])
		running += 1
	if not threaded:
		_collect_finished()

func _start_gen(key: Vector2i) -> void:
	var job := {"seed": seed_value, "cx": key.x, "cz": key.y}
	if threaded:
		pending_gen[key] = [WorkerThreadPool.add_task(_gen_job.bind(job), false, "gen"), job]
	else:
		_gen_job(job)
		_integrate(key, job)

func _start_mesh(key: Vector2i) -> void:
	var job := _mesh_input(key)
	urgent.erase(key)
	if threaded:
		pending_mesh[key] = [WorkerThreadPool.add_task(_mesh_job.bind(job), false, "mesh"), job]
	else:
		_mesh_job(job)
		_finish_mesh(key, job)

func _finish_mesh(key: Vector2i, job: Dictionary) -> void:
	var ch: Chunk = chunks.get(key)
	if ch == null:
		return
	stats.mesh_ms = lerpf(float(stats.mesh_ms), float(job.usec) / 1000.0, 0.1)
	if int(job.version) != ch.version:
		return  # edited while meshing; a fresh job will be scheduled
	_apply_mesh(ch, job.result)
	ch.meshed_version = int(job.version)

func _collect_finished() -> void:
	var t0 := Time.get_ticks_msec()
	for key in pending_gen.keys():
		var entry: Array = pending_gen[key]
		if WorkerThreadPool.is_task_completed(entry[0]):
			WorkerThreadPool.wait_for_task_completion(entry[0])
			pending_gen.erase(key)
			if not chunks.has(key):
				_integrate(key, entry[1])
	for key in pending_mesh.keys():
		if Time.get_ticks_msec() - t0 > apply_budget_ms:
			break
		var entry: Array = pending_mesh[key]
		if WorkerThreadPool.is_task_completed(entry[0]):
			WorkerThreadPool.wait_for_task_completion(entry[0])
			pending_mesh.erase(key)
			_finish_mesh(key, entry[1])

func wait_all() -> void:
	for key in pending_gen.keys():
		var entry: Array = pending_gen[key]
		WorkerThreadPool.wait_for_task_completion(entry[0])
		pending_gen.erase(key)
		if not chunks.has(key):
			_integrate(key, entry[1])
	for key in pending_mesh.keys():
		var entry: Array = pending_mesh[key]
		WorkerThreadPool.wait_for_task_completion(entry[0])
		pending_mesh.erase(key)
		_finish_mesh(key, entry[1])

# Never leave worker tasks running when the world goes away (quitting mid-load would hang).
func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	for key in pending_gen.keys():
		WorkerThreadPool.wait_for_task_completion(pending_gen[key][0])
	for key in pending_mesh.keys():
		WorkerThreadPool.wait_for_task_completion(pending_mesh[key][0])
	pending_gen.clear()
	pending_mesh.clear()

# Loads (generates) chunk data around a point right now, without meshing. Used for spawning
# and tests; safe because generation only touches this thread's own buffers.
func ensure_data(center: Vector3, radius := 1) -> void:
	var pc := chunk_of(floori(center.x), floori(center.z))
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var key := pc + Vector2i(dx, dz)
			if chunks.has(key):
				continue
			if pending_gen.has(key):
				WorkerThreadPool.wait_for_task_completion(pending_gen[key][0])
				var job: Array = pending_gen[key]
				pending_gen.erase(key)
				_integrate(key, job[1])
				continue
			var job := {"seed": seed_value, "cx": key.x, "cz": key.y}
			_gen_job(job)
			_integrate(key, job)

func loaded_progress() -> float:
	if _needed.is_empty():
		return 0.0
	var near := 0
	var done := 0
	for key in _needed:
		if _needed[key] <= 2.5:
			near += 1
			var ch: Chunk = chunks.get(key)
			if ch != null and ch.meshed_version >= 0:
				done += 1
	return float(done) / float(maxi(near, 1))

# ------------------------------------------------------------------ queries

func surface_y(x: int, z: int) -> int:
	for y in range(H - 1, 0, -1):
		var id := get_block(x, y, z)
		if id > 0 and B.SOLID[id]:
			return y + 1
	return SEA + 1

func sky_light(p: Vector3) -> float:
	var x := floori(p.x)
	var z := floori(p.z)
	var ch: Chunk = chunks.get(chunk_of(x, z))
	if ch == null:
		return 1.0
	var top := ch.tops[posmod(x, CS) * CS + posmod(z, CS)]
	var y := floori(p.y)
	return 1.0 if y >= top else clampf(1.0 - float(top - y) * 0.14, 0.03, 1.0)

func block_light(p: Vector3) -> float:
	var best := 0.0
	var pc := chunk_of(floori(p.x), floori(p.z))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := pc + Vector2i(dx, dz)
			var list: Dictionary = emitters.get(key, {})
			for idx in list:
				var i := int(idx)
				var wp := Vector3(key.x * CS + i / H / CS + 0.5, i % H + 0.5, key.y * CS + (i / H) % CS + 0.5)
				var lv := float(list[idx]) - wp.distance_to(p)
				best = maxf(best, lv / B.MAX_LIGHT)
	return clampf(best, 0.0, 1.0)

func near_light(p: Vector3, distance: float) -> bool:
	return block_light(p) * B.MAX_LIGHT > B.MAX_LIGHT - distance

# Voxel DDA ray cast. Returns {} or {cell, normal, id, distance}. Water is passed through.
func raycast(origin: Vector3, dir: Vector3, max_dist: float, min_dist := 0.0) -> Dictionary:
	dir = dir.normalized()
	var cell := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i(signi(int(signf(dir.x))), signi(int(signf(dir.y))), signi(int(signf(dir.z))))
	var t_delta := Vector3(INF if dir.x == 0 else absf(1.0 / dir.x), INF if dir.y == 0 else absf(1.0 / dir.y), INF if dir.z == 0 else absf(1.0 / dir.z))
	var t_max := Vector3(
		INF if dir.x == 0 else ((cell.x + 1 - origin.x) if dir.x > 0 else (origin.x - cell.x)) * t_delta.x,
		INF if dir.y == 0 else ((cell.y + 1 - origin.y) if dir.y > 0 else (origin.y - cell.y)) * t_delta.y,
		INF if dir.z == 0 else ((cell.z + 1 - origin.z) if dir.z > 0 else (origin.z - cell.z)) * t_delta.z)
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_dist:
		var id := get_block(cell.x, cell.y, cell.z)
		if id < 0:
			return {}
		if id != B.AIR and id != B.WATER and t >= min_dist:
			return {"cell": cell, "normal": normal, "id": id, "distance": t}
		if t_max.x < t_max.y and t_max.x < t_max.z:
			cell.x += step.x
			t = t_max.x
			t_max.x += t_delta.x
			normal = Vector3i(-step.x, 0, 0)
		elif t_max.y < t_max.z:
			cell.y += step.y
			t = t_max.y
			t_max.y += t_delta.y
			normal = Vector3i(0, -step.y, 0)
		else:
			cell.z += step.z
			t = t_max.z
			t_max.z += t_delta.z
			normal = Vector3i(0, 0, -step.z)
	return {}

func box_hits(lo: Vector3, hi: Vector3) -> bool:
	for x in range(floori(lo.x), floori(hi.x - 0.0001) + 1):
		for y in range(floori(lo.y), floori(hi.y - 0.0001) + 1):
			for z in range(floori(lo.z), floori(hi.z - 0.0001) + 1):
				if is_solid(x, y, z):
					return true
	return false

# Moves an upright box (feet at pos, half width hw, height h) by motion, axis by axis.
# Returns {pos, floor, wall, ceiling}.
func move_box(pos: Vector3, hw: float, h: float, motion: Vector3) -> Dictionary:
	var result := {"floor": false, "wall": false, "ceiling": false}
	var steps := maxi(1, ceili(maxf(absf(motion.x), maxf(absf(motion.y), absf(motion.z))) / 0.4))
	var part := motion / steps
	for s in steps:
		for axis in [1, 0, 2]:
			var amount: float = part[axis]
			if amount == 0.0:
				continue
			var next := pos
			next[axis] += amount
			if box_hits(next - Vector3(hw, 0, hw), next + Vector3(hw, h, hw)):
				if axis == 1:
					if amount < 0:
						result.floor = true
						next.y = floorf(pos.y + amount) + 1.0
						if box_hits(next - Vector3(hw, 0, hw), next + Vector3(hw, h, hw)):
							next.y = pos.y
					else:
						result.ceiling = true
						next.y = pos.y
				else:
					result.wall = true
					next[axis] = pos[axis]
				part[axis] = 0.0
			pos = next
	result["pos"] = pos
	return result

# A standing spot with solid ground, two free cells above and no water, searched in a spiral.
func find_safe_spot(near: Vector3, max_radius := 40) -> Vector3:
	ensure_data(near, 1)
	var cx := floori(near.x)
	var cz := floori(near.z)
	for i in max_radius * 6:
		var a := i * 2.399
		var r := 0.0 if i == 0 else sqrt(float(i)) * 1.6
		var x := cx + roundi(cos(a) * r)
		var z := cz + roundi(sin(a) * r)
		if not is_loaded(x, z):
			ensure_data(Vector3(x, 0, z), 0)
		var y := surface_y(x, z)
		var ground := get_block(x, y - 1, z)
		if ground == B.WATER or ground == B.CANOPY or ground == B.BLOSSOM or ground <= 0:
			continue
		if get_block(x, y, z) != B.AIR or get_block(x, y + 1, z) != B.AIR:
			continue
		return Vector3(x + 0.5, y, z + 0.5)
	return Vector3(cx + 0.5, H - 10, cz + 0.5)

func biome_name(p: Vector3) -> String:
	return Gen.BIOME_NAMES[gen.biome_at(floori(p.x), floori(p.z))]
