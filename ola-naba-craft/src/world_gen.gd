# Deterministic terrain generator. One instance per worker task: it holds its own noise objects,
# reads nothing shared and returns a fresh chunk buffer, so it is safe on any thread.
extends RefCounted

const B := preload("res://src/blocks.gd")
const CS := 16
const H := 96
const SEA := 30
const MEADOW := 0
const GROVE := 1
const DUNES := 2
const BIOME_NAMES := ["Golden Meadow", "Blossom Grove", "Amber Dunes"]

var seed_value := 0
var n_cont: FastNoiseLite
var n_hill: FastNoiseLite
var n_ridge: FastNoiseLite
var n_temp: FastNoiseLite
var n_moist: FastNoiseLite
var n_forest: FastNoiseLite
var n_cave_a: FastNoiseLite
var n_cave_b: FastNoiseLite
var n_cavern: FastNoiseLite

func _init(s: int) -> void:
	seed_value = s
	n_cont = _noise(s, 0.0035, 4)
	n_hill = _noise(s + 101, 0.017, 3)
	n_ridge = _noise(s + 202, 0.008, 1)
	n_temp = _noise(s + 303, 0.0024, 2)
	n_moist = _noise(s + 404, 0.0027, 2)
	n_forest = _noise(s + 505, 0.02, 1)
	n_cave_a = _noise(s + 606, 0.045, 1)
	n_cave_b = _noise(s + 707, 0.045, 1)
	n_cavern = _noise(s + 808, 0.028, 2)

static func _noise(s: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	if octaves > 1:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = octaves
	else:
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n

static func hash2(s: int, x: int, z: int) -> float:
	var h := (x * 374761393 + z * 668265263 + s * 1442695041) & 0xffffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
	h = h ^ (h >> 16)
	return float(h & 0xffffff) / 16777216.0

static func _smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

# Weights (meadow, grove, dunes) that sum to 1.
func biome_weights(x: int, z: int) -> Vector3:
	var t := n_temp.get_noise_2d(x, z)
	var m := n_moist.get_noise_2d(x, z)
	var dunes := _smooth(0.08, 0.26, t - m * 0.6)
	var grove := _smooth(0.06, 0.24, m - t * 0.4) * (1.0 - dunes)
	return Vector3(maxf(0.0, 1.0 - dunes - grove), grove, dunes)

func biome_at(x: int, z: int) -> int:
	var w := biome_weights(x, z)
	if w.z >= w.x and w.z >= w.y:
		return DUNES
	if w.y >= w.x:
		return GROVE
	return MEADOW

func height_at(x: int, z: int) -> int:
	var c := n_cont.get_noise_2d(x, z)
	var hills := n_hill.get_noise_2d(x, z)
	var r := 1.0 - absf(n_ridge.get_noise_2d(x, z))
	r = r * r * r
	var mount := _smooth(0.0, 0.45, c)
	var w := biome_weights(x, z)
	var base := SEA + 4.0 + c * 18.0
	var meadow_h := base + hills * 6.0 + r * mount * 26.0
	var grove_h := base + 3.0 + hills * 9.0 + r * mount * 18.0
	var dunes_h := SEA + 3.0 + c * 7.0 + absf(hills) * 6.0
	var h := meadow_h * w.x + grove_h * w.y + dunes_h * w.z
	return clampi(roundi(h), 4, H - 12)

func _is_cave(x: int, y: int, z: int) -> bool:
	var a := n_cave_a.get_noise_3d(x, y * 1.6, z)
	if a > 0.09 or a < -0.09:
		if y < 26 and n_cavern.get_noise_3d(x, y * 1.4, z) > 0.58:
			return true
		return false
	var b := n_cave_b.get_noise_3d(x, y * 1.6, z)
	return a * a + b * b < 0.0065

static func index(x: int, y: int, z: int) -> int:
	return (x * CS + z) * H + y

# Returns the block buffer for chunk (cx, cz), laid out column by column (y contiguous).
func generate(cx: int, cz: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(CS * CS * H)
	const M := 3
	var W := CS + M * 2
	var heights := PackedInt32Array()
	heights.resize(W * W)
	var biomes := PackedByteArray()
	biomes.resize(W * W)
	var x0 := cx * CS
	var z0 := cz * CS
	for lx in W:
		for lz in W:
			heights[lx * W + lz] = height_at(x0 + lx - M, z0 + lz - M)
			biomes[lx * W + lz] = biome_at(x0 + lx - M, z0 + lz - M)
	for x in CS:
		for z in CS:
			var wx := x0 + x
			var wz := z0 + z
			var h := heights[(x + M) * W + z + M]
			var biome := biomes[(x + M) * W + z + M]
			var wet := h <= SEA + 1
			var top_block := B.MOSS
			var under := B.SOIL
			var under_depth := 3
			if wet or biome == DUNES:
				top_block = B.SAND
				under = B.SAND if wet else B.SANDSTONE
				under_depth = 4
			elif biome == GROVE:
				top_block = B.LILAC_MOSS
			var base := (x * CS + z) * H
			for y in H:
				var id := B.AIR
				if y == 0 or (y == 1 and hash2(seed_value, wx * 3 + 1, wz * 7) < 0.5):
					id = B.DEEPSTONE
				elif y <= h:
					var d := h - y
					if d == 0:
						id = top_block
					elif d <= under_depth:
						id = under
					elif biome == DUNES and not wet and d <= under_depth + 4:
						id = B.SANDSTONE
					else:
						id = B.SLATE
					if y > 1 and not (wet and d < 6) and _is_cave(wx, y, wz):
						id = B.AIR
				elif y <= SEA:
					id = B.WATER
				data[base + y] = id
	_ores(data, cx, cz)
	_trees(data, heights, biomes, W, M, x0, z0)
	return data

func _vein(data: PackedByteArray, r: RandomNumberGenerator, ore: int, size: int, y_min: int, y_max: int) -> void:
	var x := r.randi_range(1, CS - 2)
	var y := r.randi_range(y_min, y_max)
	var z := r.randi_range(1, CS - 2)
	for i in size:
		if x >= 0 and x < CS and z >= 0 and z < CS and y > 1 and y < H:
			var idx := index(x, y, z)
			if data[idx] == B.SLATE:
				data[idx] = ore
		match r.randi_range(0, 5):
			0: x += 1
			1: x -= 1
			2: y += 1
			3: y -= 1
			4: z += 1
			_: z -= 1

func _ores(data: PackedByteArray, cx: int, cz: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(hash2(seed_value, cx * 31 + 7, cz * 17 - 3) * 2147483647.0)
	for i in 9:
		_vein(data, r, B.EMBER_ORE, r.randi_range(3, 7), 6, 58)
	for i in 4:
		_vein(data, r, B.SUNMETAL_ORE, r.randi_range(2, 5), 3, 26)

func _put(data: PackedByteArray, x: int, y: int, z: int, id: int, only_air: bool) -> void:
	if x < 0 or x >= CS or z < 0 or z >= CS or y <= 0 or y >= H:
		return
	var idx := index(x, y, z)
	if only_air and data[idx] != B.AIR:
		return
	data[idx] = id

func _trees(data: PackedByteArray, heights: PackedInt32Array, biomes: PackedByteArray, W: int, M: int, x0: int, z0: int) -> void:
	for lx in W:
		for lz in W:
			var biome := biomes[lx * W + lz]
			var h := heights[lx * W + lz]
			if biome == DUNES or h <= SEA + 1 or h > H - 16:
				continue
			var wx := x0 + lx - M
			var wz := z0 + lz - M
			var chance := 0.022 if biome == GROVE else (0.035 if n_forest.get_noise_2d(wx, wz) > 0.35 else 0.008)
			if hash2(seed_value, wx, wz) >= chance:
				continue
			var trunk := 4 + int(hash2(seed_value + 9, wx, wz) * 2.0) + (1 if biome == GROVE else 0)
			var top := h + trunk
			var leaf := B.BLOSSOM if biome == GROVE else B.CANOPY
			var lo := top - (3 if biome == GROVE else 2)
			for y in range(lo, top + 2):
				var radius := 1 if y >= top else 2
				for dx in range(-radius, radius + 1):
					for dz in range(-radius, radius + 1):
						if radius == 2 and absi(dx) == 2 and absi(dz) == 2 and hash2(seed_value + y, wx + dx, wz + dz) < 0.65:
							continue
						if y == top + 1 and absi(dx) + absi(dz) > 1:
							continue
						_put(data, wx + dx - x0, y, wz + dz - z0, leaf, true)
			for y in range(h + 1, top + 1):
				_put(data, wx - x0, y, wz - z0, B.TIMBER, false)
