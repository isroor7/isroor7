# Item drops lying in the world and keepsake bundles left where a player fainted.
# Everything here runs on the main thread in one pass, so a drop is collected by exactly one
# player: two players reaching it in the same frame cannot both receive it.
extends Node3D

const Items := preload("res://src/items.gd")
const B := preload("res://src/blocks.gd")
const VM := preload("res://src/voxel_model.gd")
const Textures := preload("res://src/textures.gd")

var world: Node
var game: Node
var drops: Array = []     # {key, n, d, pos, vel, age, node}
var bundles: Array = []   # {owner, items, pos, node}
var _mats := {}
var _bundle_mat: ShaderMaterial

func _material(key: String) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var info := Items.info(key)
	var tex: Texture2D
	if info.get("kind", "") == "block":
		tex = ImageTexture.create_from_image(Textures.block_images()[B.TEX[int(info.block)][1]])
	else:
		tex = Textures.icon(key)
	var m := VM.material(tex)
	_mats[key] = m
	return m

func spawn(key: String, n: int, pos: Vector3, durability := -1, toss := true) -> void:
	if n <= 0 or not Items.exists(key):
		return
	var mi := MeshInstance3D.new()
	var info := Items.info(key)
	mi.mesh = VM.cube(Vector3(0.26, 0.26, 0.26), Vector3(0, 0.13, 0)) if info.get("kind", "") == "block" else VM.slab(0.42, 0.04)
	mi.material_override = _material(key)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var vel := Vector3(randf_range(-1.2, 1.2), 3.4, randf_range(-1.2, 1.2)) if toss else Vector3.ZERO
	drops.append({"key": key, "n": n, "d": durability, "pos": pos, "vel": vel, "age": 0.0, "node": mi})

func spawn_block_drops(cell: Vector3i, block_id: int) -> void:
	for entry in B.drops(block_id):
		if randf() <= float(entry[2]):
			spawn(entry[0], int(entry[1]), Vector3(cell) + Vector3(0.5, 0.3, 0.5))

func tick(delta: float, players: Array, daylight: float) -> void:
	for i in range(drops.size() - 1, -1, -1):
		var d: Dictionary = drops[i]
		d.age += delta
		var vel: Vector3 = d.vel
		var pos: Vector3 = d.pos
		var collector = null
		if d.age > 0.4:
			var best := 2.6
			for p in players:
				if p.fainted > 0.0 or p.creative:
					continue
				var dist: float = (p.position + Vector3(0, 0.6, 0)).distance_to(pos)
				if dist < best and p.inventory.can_add(d.key, 1):
					best = dist
					collector = p
		if collector != null:
			var to: Vector3 = collector.position + Vector3(0, 0.7, 0) - pos
			if to.length() < 0.9:
				var left: int = collector.inventory.add(d.key, int(d.n), int(d.d))
				if game and game.get("audio"):
					game.audio.play("pickup")
				if left <= 0:
					d.node.queue_free()
					drops.remove_at(i)
					continue
				d.n = left
			vel = to.normalized() * 7.0
			pos += vel * delta
		else:
			vel.y -= 18.0 * delta
			var res: Dictionary = world.move_box(pos, 0.12, 0.25, vel * delta)
			pos = res.pos
			if res.floor:
				vel = Vector3(vel.x * 0.6, 0.0, vel.z * 0.6)
			if res.wall:
				vel.x = 0.0
				vel.z = 0.0
		d.vel = vel
		d.pos = pos
		var node: MeshInstance3D = d.node
		node.position = pos + Vector3(0, 0.1 + sin(d.age * 3.0) * 0.06, 0)
		node.rotation.y = d.age * 1.6
		var m: ShaderMaterial = node.material_override
		m.set_shader_parameter("daylight", daylight)
		if d.age > 900.0:
			node.queue_free()
			drops.remove_at(i)
	for i in range(bundles.size() - 1, -1, -1):
		var b: Dictionary = bundles[i]
		b.node.rotation.y += delta * 0.8
		b.node.position = b.pos + Vector3(0, 0.25 + sin(Time.get_ticks_msec() * 0.003) * 0.08, 0)
		for p in players:
			if p.fainted > 0.0 or (p.profile() != b.owner and _owner_present(players, b.owner)):
				continue
			if p.position.distance_to(b.pos) < 1.6:
				var keep := []
				for s in b.items:
					var left: int = p.inventory.add(String(s.id), int(s.n), int(s.get("d", -1)))
					if left > 0:
						var rest: Dictionary = s.duplicate()
						rest.n = left
						keep.append(rest)
				if game and game.get("audio"):
					game.audio.play("craft")
				p.say("Keepsake bundle recovered" if keep.is_empty() else "Bundle partly recovered: make room for the rest")
				b.items = keep
				if keep.is_empty():
					b.node.queue_free()
					bundles.remove_at(i)
				break

func _owner_present(players: Array, owner: String) -> bool:
	for p in players:
		if p.profile() == owner:
			return true
	return false

func add_bundle(owner: String, items: Array, pos: Vector3) -> void:
	if items.is_empty():
		return
	var root := Node3D.new()
	add_child(root)
	if _bundle_mat == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			for x in 16:
				var c := Color("#e78aa8") if (x + y) % 5 != 0 else Color("#c96b8c")
				if y < 4:
					c = Color("#ffd25e", 0.8)
				img.set_pixel(x, y, c)
		_bundle_mat = VM.material(ImageTexture.create_from_image(img))
	var bag := MeshInstance3D.new()
	bag.mesh = VM.cube(Vector3(0.5, 0.45, 0.5), Vector3(0, 0.22, 0))
	bag.material_override = _bundle_mat
	root.add_child(bag)
	var beam := MeshInstance3D.new()
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(0.08, 6.0, 0.08)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(1.0, 0.82, 0.45, 0.45)
	beam_mesh.material = bm
	beam.mesh = beam_mesh
	beam.position.y = 3.2
	root.add_child(beam)
	bundles.append({"owner": owner, "items": items, "pos": pos, "node": root})

func bundle_for(owner: String) -> Dictionary:
	for b in bundles:
		if b.owner == owner:
			return b
	return {}

func clear_all() -> void:
	for d in drops:
		d.node.queue_free()
	for b in bundles:
		b.node.queue_free()
	drops.clear()
	bundles.clear()

func to_save() -> Dictionary:
	var ds := []
	for d in drops:
		ds.append({"key": d.key, "n": d.n, "d": d.d, "pos": [d.pos.x, d.pos.y, d.pos.z]})
	var bs := []
	for b in bundles:
		bs.append({"owner": b.owner, "items": b.items, "pos": [b.pos.x, b.pos.y, b.pos.z]})
	return {"drops": ds, "bundles": bs}

func from_save(data: Dictionary) -> void:
	clear_all()
	for d in data.get("drops", []):
		if d is Dictionary and d.get("pos") is Array and (d.pos as Array).size() == 3:
			spawn(String(d.key), int(d.n), Vector3(float(d.pos[0]), float(d.pos[1]), float(d.pos[2])), int(d.get("d", -1)), false)
	for b in data.get("bundles", []):
		if b is Dictionary and b.get("pos") is Array and (b.pos as Array).size() == 3 and b.get("items") is Array:
			var items := []
			for s in b.items:
				if s is Dictionary and Items.exists(String(s.get("id", ""))) and int(s.get("n", 0)) > 0:
					items.append(s)
			add_bundle(String(b.owner), items, Vector3(float(b.pos[0]), float(b.pos[1]), float(b.pos[2])))
