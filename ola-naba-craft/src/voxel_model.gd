# Builds textured boxes for characters, creatures, drops and held items.
# Skin textures use a box unwrap: for a part of w x h x d pixels at (u, v) the faces sit at
#   top (u+d, v)  bottom (u+d+w, v)  right (u, v+d)  front (u+d, v+d)  left (u+d+w, v+d)  back (u+2d+w, v+d)
# Models face -Z (Godot's forward), so the character's right hand is +X.
extends RefCounted

const ENTITY_SHADER := preload("res://src/shaders/voxel_entity.gdshader")
const PX := 1.0 / 16.0

static func material(skin: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ENTITY_SHADER
	m.set_shader_parameter("skin", skin)
	return m

# A box of w x h x d texture pixels (1 px = 1/16 block). `lo` is the corner offset of the box
# relative to the pivot, in pixels. Returns a mesh whose UVs index an atlas of atlas_size.
static func box(u: int, v: int, w: int, h: int, d: int, lo: Vector3, atlas_size: Vector2, scale := PX) -> ArrayMesh:
	var x0 := lo.x * scale
	var y0 := lo.y * scale
	var z0 := lo.z * scale
	var x1 := x0 + w * scale
	var y1 := y0 + h * scale
	var z1 := z0 + d * scale
	var faces := [
		# rect in atlas (x, y, w, h), corners TL TR BR BL as seen from outside, normal
		[Rect2(u + d, v + d, w, h), [Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3(x0, y0, z0), Vector3(x1, y0, z0)], Vector3(0, 0, -1)],
		[Rect2(u + 2 * d + w, v + d, w, h), [Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3(x0, y0, z1)], Vector3(0, 0, 1)],
		[Rect2(u, v + d, d, h), [Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1)], Vector3(1, 0, 0)],
		[Rect2(u + d + w, v + d, d, h), [Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3(x0, y0, z0)], Vector3(-1, 0, 0)],
		[Rect2(u + d, v, w, d), [Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(x1, y1, z0)], Vector3(0, 1, 0)],
		[Rect2(u + d + w, v, w, d), [Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x0, y0, z0)], Vector3(0, -1, 0)],
	]
	return _build(faces, atlas_size)

# A box whose every face shows the whole texture (blocks held in hand, dropped items).
static func cube(size: Vector3, center: Vector3) -> ArrayMesh:
	var lo := center - size / 2.0
	var hi := center + size / 2.0
	var r := Rect2(0, 0, 1, 1)
	var faces := [
		[r, [Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z)], Vector3(0, 0, -1)],
		[r, [Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z)], Vector3(0, 0, 1)],
		[r, [Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z)], Vector3(1, 0, 0)],
		[r, [Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, lo.y, lo.z)], Vector3(-1, 0, 0)],
		[r, [Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z)], Vector3(0, 1, 0)],
		[r, [Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z)], Vector3(0, -1, 0)],
	]
	return _build(faces, Vector2(1, 1))

# A flat item (tool, stick...) as a thin slab showing the icon on both sides.
static func slab(size: float, thickness: float) -> ArrayMesh:
	var h := size / 2.0
	var t := thickness / 2.0
	var full := Rect2(0, 0, 1, 1)
	var edge := Rect2(0.5, 0, 0.02, 1)
	var faces := [
		[full, [Vector3(-h, h, -t), Vector3(h, h, -t), Vector3(h, -h, -t), Vector3(-h, -h, -t)], Vector3(0, 0, -1)],
		[Rect2(1, 0, -1, 1), [Vector3(h, h, t), Vector3(-h, h, t), Vector3(-h, -h, t), Vector3(h, -h, t)], Vector3(0, 0, 1)],
	]
	return _build(faces, Vector2(1, 1))

static func _build(faces: Array, atlas: Vector2) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for f in faces:
		var r: Rect2 = f[0]
		var c: Array = f[1]
		var base := verts.size()
		var uv := [Vector2(r.position.x, r.position.y), Vector2(r.position.x + r.size.x, r.position.y),
			Vector2(r.position.x + r.size.x, r.position.y + r.size.y), Vector2(r.position.x, r.position.y + r.size.y)]
		for i in 4:
			verts.append(c[i])
			normals.append(f[2])
			uvs.append(uv[i] / atlas)
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# Paints every face of a box region with painter.call(face, x, y, face_w, face_h) -> Color.
# face is one of "top", "bottom", "right", "front", "left", "back".
static func paint_box(img: Image, u: int, v: int, w: int, h: int, d: int, painter: Callable) -> void:
	var rects := {"top": Rect2i(u + d, v, w, d), "bottom": Rect2i(u + d + w, v, w, d),
		"right": Rect2i(u, v + d, d, h), "front": Rect2i(u + d, v + d, w, h),
		"left": Rect2i(u + d + w, v + d, d, h), "back": Rect2i(u + 2 * d + w, v + d, w, h)}
	for face in rects:
		var r: Rect2i = rects[face]
		for y in r.size.y:
			for x in r.size.x:
				img.set_pixel(r.position.x + x, r.position.y + y, painter.call(face, x, y, r.size.x, r.size.y))
