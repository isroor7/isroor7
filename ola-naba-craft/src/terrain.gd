extends GridMap

const RADIUS := 17
const BLOCKS := ["Moss", "Soil", "Slate", "Timber", "Canopy", "Planks", "Glowglass"]
const COLORS := ["#81ba71", "#a47b57", "#7d829b", "#a16640", "#46966d", "#d5a168", "#73dada"]
var edits := {}
var world_seed := 40521

func make_world(seed_value: int) -> void:
	clear()
	edits.clear()
	world_seed = seed_value
	cell_size = Vector3.ONE
	cell_center_x = false
	cell_center_y = false
	cell_center_z = false
	cell_octant_size = 8
	mesh_library = MeshLibrary.new()
	for i in BLOCKS.size():
		var mesh := BoxMesh.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(COLORS[i])
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.albedo_texture = tile(i)
		if i == 6:
			mat.emission_enabled = true
			mat.emission = Color("#38a0ab")
		mesh.material = mat
		mesh_library.create_item(i)
		mesh_library.set_item_name(i, BLOCKS[i])
		mesh_library.set_item_mesh(i, mesh)
		var offset := Transform3D(Basis.IDENTITY, Vector3(0.5, 0.5, 0.5))
		mesh_library.set_item_mesh_transform(i, offset)
		var shape := BoxShape3D.new()
		shape.size = Vector3.ONE
		mesh_library.set_item_shapes(i, [shape, offset])
	var noise := FastNoiseLite.new()
	noise.seed = world_seed
	noise.frequency = 0.095
	for x in range(-RADIUS, RADIUS + 1):
		for z in range(-RADIUS, RADIUS + 1):
			var h := roundi(noise.get_noise_2d(x, z) * 5.0)
			if absi(x) < 3 and absi(z) < 3:
				h = 0
			for y in range(-4, h + 1):
				set_cell_item(Vector3i(x, y, z), 0 if y == h else (1 if y >= h - 2 else 2))
			if (absi(x) > 4 or absi(z) > 4) and (x * 13 + z * 29 + world_seed) % 47 == 0:
				tree(Vector3i(x, h + 1, z))

func tile(kind: int) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + kind
	for y in 16:
		for x in 16:
			var shade := rng.randf_range(0.82, 1.0)
			if (kind == 3 and x % 4 == 0) or (kind == 5 and y % 5 == 0):
				shade *= 0.7
			if kind == 6 and ((x < 2 or x > 13) or (y < 2 or y > 13)):
				shade *= 0.5
			img.set_pixel(x, y, Color(shade, shade, shade))
	return ImageTexture.create_from_image(img)

func tree(base: Vector3i) -> void:
	for y in range(3):
		set_cell_item(base + Vector3i(0, y, 0), 3)
	for x in range(-1, 2):
		for z in range(-1, 2):
			set_cell_item(base + Vector3i(x, 3, z), 4)
	set_cell_item(base + Vector3i(0, 4, 0), 4)

func change(cell: Vector3i, kind: int) -> bool:
	if absi(cell.x) > RADIUS or absi(cell.z) > RADIUS or cell.y <= -4 or cell.y > 24:
		return false
	if kind < -1 or kind >= BLOCKS.size():
		return false
	set_cell_item(cell, kind)
	edits["%d,%d,%d" % [cell.x, cell.y, cell.z]] = kind
	return true

func restore(data: Dictionary) -> void:
	for key in data:
		var xyz := String(key).split(",")
		if xyz.size() == 3 and xyz[0].is_valid_int() and xyz[1].is_valid_int() and xyz[2].is_valid_int():
			change(Vector3i(int(xyz[0]), int(xyz[1]), int(xyz[2])), int(data[key]))
