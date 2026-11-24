# Culled-face chunk mesher. Runs on worker threads: it only reads the arrays handed to it
# (Packed arrays are copy-on-write snapshots) and returns plain mesh arrays.
# Each face carries: COLOR.rgb = shade/AO tint (turquoise in shadow), COLOR.a = sky light,
# UV = face texture coords, UV2.x = texture layer, UV2.y = block light.
extends RefCounted

const B := preload("res://src/blocks.gd")
const CS := 16
const H := 96
const P := 8
const PW := CS + 2 * P
const SHADOW := Vector3(0.42, 0.62, 0.68)
const AO_CURVE := [0.46, 0.64, 0.82, 1.0]

const NORMALS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
# Corners listed counter-clockwise when seen from outside the face.
const CORNERS := [
	[Vector3i(1, 0, 0), Vector3i(1, 1, 0), Vector3i(1, 1, 1), Vector3i(1, 0, 1)],
	[Vector3i(0, 0, 1), Vector3i(0, 1, 1), Vector3i(0, 1, 0), Vector3i(0, 0, 0)],
	[Vector3i(0, 1, 1), Vector3i(1, 1, 1), Vector3i(1, 1, 0), Vector3i(0, 1, 0)],
	[Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 1), Vector3i(0, 0, 1)],
	[Vector3i(1, 0, 1), Vector3i(1, 1, 1), Vector3i(0, 1, 1), Vector3i(0, 0, 1)],
	[Vector3i(0, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(1, 0, 0)],
]
const SHADE := [0.86, 0.76, 1.0, 0.58, 0.92, 0.7]
const FACE_TEX := [1, 1, 0, 2, 1, 1]  # index into Blocks.TEX[id]: 0 top, 1 side, 2 bottom

static var _noff := PackedInt32Array()
static var _ao := []   # per face, per corner: PackedInt32Array [side1, side2, corner] index offsets
static var _uv := []   # per face, per corner: Vector2

static func _off(v: Vector3i) -> int:
	return v.x * PW * H + v.z * H + v.y

# Must run once on the main thread before any worker uses the mesher.
static func prepare() -> void:
	if not _noff.is_empty():
		return
	for f in 6:
		var n: Vector3i = NORMALS[f]
		_noff.append(_off(n))
		var axis := 0 if n.x != 0 else (1 if n.y != 0 else 2)
		var tangents := [0, 1, 2]
		tangents.erase(axis)
		var per_corner := []
		var uvs := []
		for c in CORNERS[f]:
			var corner: Vector3i = c
			var d1 := Vector3i.ZERO
			var d2 := Vector3i.ZERO
			d1[tangents[0]] = 1 if corner[tangents[0]] == 1 else -1
			d2[tangents[1]] = 1 if corner[tangents[1]] == 1 else -1
			per_corner.append(PackedInt32Array([_off(d1), _off(d2), _off(d1 + d2)]))
			if axis == 1:
				uvs.append(Vector2(corner.x, corner.z))
			elif axis == 0:
				uvs.append(Vector2(corner.z, 1 - corner.y))
			else:
				uvs.append(Vector2(corner.x, 1 - corner.y))
		_ao.append(per_corner)
		_uv.append(uvs)

static func _hash(x: int, y: int, z: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
	h = ((h ^ (h >> 13)) * 1274126177) & 0xffffff
	return float(h) / 16777216.0

# Output arrays live on the instance so appends modify them in place (packed arrays are
# copy-on-write values; appending through a Dictionary copy would silently drop data).
var sv := PackedVector3Array()
var suv := PackedVector2Array()
var suv2 := PackedVector2Array()
var sc := PackedColorArray()
var si := PackedInt32Array()
var tv := PackedVector3Array()
var tuv := PackedVector2Array()
var tuv2 := PackedVector2Array()
var tc := PackedColorArray()
var ti := PackedInt32Array()
var pad := PackedByteArray()
var ptop := PackedByteArray()
var light := PackedByteArray()
var has_light := false
var wx0 := 0
var wz0 := 0

# job: {chunks: Array[9] of PackedByteArray, tops: Array[9] of PackedByteArray, emitters: Array of
#       [px, y, pz, level] in padded coords, maxy: int, cx: int, cz: int}
func build(job: Dictionary) -> Dictionary:
	var chunks: Array = job.chunks
	var tops_src: Array = job.tops
	ptop.resize(PW * PW)
	for px in PW:
		var dx := -1 if px < P else (1 if px >= P + CS else 0)
		var lx := px - P - dx * CS
		for pz in PW:
			var dz := -1 if pz < P else (1 if pz >= P + CS else 0)
			var lz := pz - P - dz * CS
			var k := (dx + 1) * 3 + dz + 1
			var src: PackedByteArray = chunks[k]
			var start := (lx * CS + lz) * H
			pad.append_array(src.slice(start, start + H))
			ptop[px * PW + pz] = (tops_src[k] as PackedByteArray)[lx * CS + lz]
	var emitters: Array = job.emitters
	if not emitters.is_empty():
		_flood_light(emitters)
	var maxy: int = mini(int(job.maxy) + 1, H - 3)
	wx0 = int(job.cx) * CS
	wz0 = int(job.cz) * CS
	for px in range(P, P + CS):
		for pz in range(P, P + CS):
			var col_base := (px * PW + pz) * H
			for y in maxy + 1:
				var idx := col_base + y
				var id := pad[idx]
				if id == 0:
					continue
				var translucent: bool = B.TRANSLUCENT[id]
				for f in 6:
					if f == 3 and y == 0:
						continue
					var nidx := idx + _noff[f]
					var nid := pad[nidx]
					if B.OPAQUE[nid]:
						continue
					if translucent and (nid == id or (id == B.WATER and nid == B.GLOWGLASS)):
						continue
					_face(translucent, f, id, px - P, y, pz - P, idx, nidx)
	return {"solid": [sv, suv, suv2, sc, si], "clear": [tv, tuv, tuv2, tc, ti]}

func _flood_light(emitters: Array) -> void:
	has_light = true
	light.resize(PW * PW * H)
	var q := PackedInt32Array()
	for e in emitters:
		var i: int = (int(e[0]) * PW + int(e[2])) * H + int(e[1])
		if light[i] < int(e[3]):
			light[i] = int(e[3])
			q.append(i)
	var head := 0
	var step_x := PW * H
	while head < q.size():
		var i := q[head]
		head += 1
		var lv := light[i] - 1
		if lv <= 0:
			continue
		var y := i % H
		var col := i / H
		var px := col / PW
		var pz := col % PW
		var around := PackedInt32Array()
		if px > 0: around.append(i - step_x)
		if px < PW - 1: around.append(i + step_x)
		if pz > 0: around.append(i - H)
		if pz < PW - 1: around.append(i + H)
		if y > 0: around.append(i - 1)
		if y < H - 1: around.append(i + 1)
		for n in around:
			if B.OPAQUE[pad[n]] or light[n] >= lv:
				continue
			light[n] = lv
			q.append(n)

func _face(translucent: bool, f: int, id: int, x: int, y: int, z: int, idx: int, nidx: int) -> void:
	var bright: bool = B.EMIT[id] > 0
	var sky := 1.0
	var blk := 0.0
	if bright:
		blk = 1.0
	else:
		var top := ptop[nidx / H]
		var ny: int = y + NORMALS[f].y
		if ny < top:
			sky = clampf(1.0 - float(top - ny) * 0.14, 0.03, 1.0)
		if has_light:
			blk = float(light[nidx]) / float(B.MAX_LIGHT)
	var layer: int = B.TEX[id][FACE_TEX[f]]
	var top_y := 1.0
	if id == B.WATER and pad[idx + 1] != B.WATER:
		top_y = 0.875
	var flat: bool = bright or translucent
	var jitter := 1.0 if flat else 0.95 + 0.1 * _hash(wx0 + x, y, wz0 + z)
	var shade: float = 1.0 if bright else SHADE[f]
	var a0 := 3
	var a1 := 3
	var a2 := 3
	var a3 := 3
	if not flat:
		var offs: Array = _ao[f]
		a0 = _ao_at(nidx, offs[0])
		a1 = _ao_at(nidx, offs[1])
		a2 = _ao_at(nidx, offs[2])
		a3 = _ao_at(nidx, offs[3])
	var aos := [a0, a1, a2, a3]
	var corners: Array = CORNERS[f]
	var uvs: Array = _uv[f]
	var base := tv.size() if translucent else sv.size()
	for c in 4:
		var k: Vector3i = corners[c]
		var cy := top_y if k.y == 1 else 0.0
		var pos := Vector3(x + k.x, y + cy, z + k.z)
		var uv: Vector2 = uvs[c]
		if f != 2 and f != 3 and k.y == 1:
			uv.y = 1.0 - top_y
		var s: float = shade * AO_CURVE[aos[c]] * jitter
		var tint := SHADOW.lerp(Vector3.ONE, clampf(s, 0.0, 1.0)) * minf(s + 0.25, 1.05)
		var col := Color(tint.x, tint.y, tint.z, sky)
		if translucent:
			tv.append(pos)
			tuv.append(uv)
			tuv2.append(Vector2(layer, blk))
			tc.append(col)
		else:
			sv.append(pos)
			suv.append(uv)
			suv2.append(Vector2(layer, blk))
			sc.append(col)
	# Godot treats clockwise triangles as front faces, so the CCW corner list is emitted reversed.
	var tri: Array
	if a0 + a2 < a1 + a3:
		tri = [base + 1, base + 3, base + 2, base + 1, base, base + 3]
	else:
		tri = [base, base + 2, base + 1, base, base + 3, base + 2]
	for t in tri:
		if translucent:
			ti.append(t)
		else:
			si.append(t)

func _ao_at(nidx: int, o: PackedInt32Array) -> int:
	var s1: bool = B.OPAQUE[pad[nidx + o[0]]]
	var s2: bool = B.OPAQUE[pad[nidx + o[1]]]
	if s1 and s2:
		return 0
	var cc: bool = B.OPAQUE[pad[nidx + o[2]]]
	return 3 - int(s1) - int(s2) - int(cc)
