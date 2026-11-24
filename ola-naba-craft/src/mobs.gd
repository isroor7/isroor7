# Original creatures. Gloomlings come out at night in Survival, chase the nearest player, keep away
# from lantern light and dissolve at dawn. Puffkins are harmless daytime critters that hop around.
extends Node3D

const VM := preload("res://src/voxel_model.gd")
const B := preload("res://src/blocks.gd")
const KINDS := {
	"gloomling": {"hw": 0.36, "h": 1.15, "hp": 10, "speed": 3.1, "damage": 3},
	"puffkin": {"hw": 0.3, "h": 0.72, "hp": 4, "speed": 1.5, "damage": 0},
}
const MAX_GLOOM_PER_PLAYER := 5
const MAX_PUFF_PER_PLAYER := 3

var world: Node
var game: Node
var mobs: Array = []   # {kind, pos, vel, hp, yaw, node, mat, floor, attack_cd, hurt_t, wander, wander_t, fade}
var spawn_clock := 0.0
var rng := RandomNumberGenerator.new()
static var _skins := {}

func _skin(kind: String) -> ImageTexture:
	if _skins.has(kind):
		return _skins[kind]
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if kind == "gloomling":
		var body := Color("#2c2f52")
		var body_l := Color("#3a3d6b")
		var belly := Color("#4a4f86")
		var eye := Color("#6ff3ff", 0.8)
		var crystal := Color("#c9a0ea", 0.8)
		VM.paint_box(img, 0, 0, 12, 10, 12, func(f: String, x: int, y: int, w: int, h: int) -> Color:
			if f == "front" and y == 3 and (x == 3 or x == 4 or x == 7 or x == 8):
				return eye
			if f == "front" and y == 4 and (x == 3 or x == 8):
				return eye
			if f == "front" and y >= 6 and x >= 3 and x <= 8:
				return belly
			return body if (x * 3 + y * 5) % 7 != 0 else body_l)
		VM.paint_box(img, 48, 0, 3, 4, 3, func(f: String, x: int, y: int, w: int, h: int) -> Color:
			return crystal)
		VM.paint_box(img, 48, 8, 3, 3, 3, func(f: String, x: int, y: int, w: int, h: int) -> Color:
			return body_l)
	else:
		var fur := Color("#fbeee2")
		var fur_d := Color("#f2d9c8")
		VM.paint_box(img, 0, 0, 10, 8, 10, func(f: String, x: int, y: int, w: int, h: int) -> Color:
			if f == "front" and y == 3 and (x == 3 or x == 6):
				return Color("#2a1d24")
			if f == "front" and y == 5 and (x == 2 or x == 7):
				return Color("#f48dab")
			if f == "front" and y == 5 and (x == 4 or x == 5):
				return Color("#c96b8c")
			return fur if (x + y * 2) % 5 != 0 else (fur_d if (x + y) % 3 != 0 else Color("#ffe08a")))
		VM.paint_box(img, 48, 0, 2, 3, 2, func(f: String, x: int, y: int, w: int, h: int) -> Color:
			return Color("#f48dab") if f == "front" else fur)
	var tex := ImageTexture.create_from_image(img)
	_skins[kind] = tex
	return tex

func spawn(kind: String, pos: Vector3) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var mat := VM.material(_skin(kind))
	var atlas := Vector2(64, 32)
	var parts := []
	if kind == "gloomling":
		parts = [[0, 0, 12, 10, 12, Vector3(-6, 3, -6)], [48, 0, 3, 4, 3, Vector3(-1.5, 13, -1.5)],
			[48, 8, 3, 3, 3, Vector3(-5, 0, -1.5)], [48, 8, 3, 3, 3, Vector3(2, 0, -1.5)]]
	else:
		parts = [[0, 0, 10, 8, 10, Vector3(-5, 0, -5)], [48, 0, 2, 3, 2, Vector3(-4, 8, -1)], [48, 0, 2, 3, 2, Vector3(2, 8, -1)]]
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = VM.box(p[0], p[1], p[2], p[3], p[4], p[5], atlas)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var info: Dictionary = KINDS[kind]
	var m := {"kind": kind, "pos": pos, "vel": Vector3.ZERO, "hp": int(info.hp), "yaw": rng.randf() * TAU, "node": root,
		"mat": mat, "floor": false, "attack_cd": 0.0, "hurt_t": 0.0, "wander": Vector3.ZERO, "wander_t": 0.0, "fade": 0.0}
	root.position = pos
	mobs.append(m)
	return m

func count_near(kind: String, p: Vector3, radius: float) -> int:
	var n := 0
	for m in mobs:
		if m.kind == kind and (m.pos as Vector3).distance_to(p) < radius:
			n += 1
	return n

func _try_spawn(players: Array, daylight: float, creative: bool) -> void:
	for p in players:
		var night := daylight < 0.3
		var kind := "gloomling" if night else "puffkin"
		if kind == "gloomling" and creative:
			continue
		var cap := MAX_GLOOM_PER_PLAYER if night else MAX_PUFF_PER_PLAYER
		if count_near(kind, p.position, 40.0) >= cap:
			continue
		var a := rng.randf() * TAU
		var r := rng.randf_range(16.0, 30.0)
		var x := floori(p.position.x + cos(a) * r)
		var z := floori(p.position.z + sin(a) * r)
		if not world.is_loaded(x, z):
			continue
		var y: int = world.surface_y(x, z)
		var ground: int = world.get_block(x, y - 1, z)
		if ground == B.WATER or ground == B.CANOPY or ground == B.BLOSSOM or ground <= 0:
			continue
		var pos := Vector3(x + 0.5, y, z + 0.5)
		if world.sky_light(pos + Vector3(0, 0.5, 0)) < 0.9:
			continue
		if kind == "gloomling":
			if world.block_light(pos + Vector3(0, 0.5, 0)) > 0.2:
				continue
			var too_close := false
			for q in players:
				if q.position.distance_to(pos) < 12.0:
					too_close = true
			if too_close:
				continue
		elif ground != B.MOSS and ground != B.LILAC_MOSS:
			continue
		spawn(kind, pos)

func tick(delta: float, players: Array, daylight: float, creative: bool) -> void:
	spawn_clock -= delta
	if spawn_clock <= 0.0:
		spawn_clock = 2.0
		_try_spawn(players, daylight, creative)
	for i in range(mobs.size() - 1, -1, -1):
		var m: Dictionary = mobs[i]
		if _update(m, delta, players, daylight, creative):
			m.node.queue_free()
			mobs.remove_at(i)

# Returns true when the creature should be removed.
func _update(m: Dictionary, delta: float, players: Array, daylight: float, creative: bool) -> bool:
	var info: Dictionary = KINDS[m.kind]
	var pos: Vector3 = m.pos
	var far := true
	for p in players:
		if p.position.distance_to(pos) < 72.0:
			far = false
	if far:
		return true
	m.attack_cd = maxf(0.0, m.attack_cd - delta)
	m.hurt_t = maxf(0.0, m.hurt_t - delta)
	var wish := Vector3.ZERO
	var speed: float = info.speed
	if m.kind == "gloomling":
		var sky: float = world.sky_light(pos + Vector3(0, 0.6, 0))
		if (daylight > 0.45 and sky > 0.6) or creative:
			m.fade += delta
			if m.fade > 1.2:
				if game and game.get("audio"):
					game.audio.play_at("puff", pos, 0.8)
				return true
		var best = null
		var best_d := 22.0
		for p in players:
			if p.fainted > 0.0 or p.creative:
				continue
			var d: float = p.position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = p
		if best != null:
			var to: Vector3 = best.position - pos
			to.y = 0
			wish = to.normalized()
			if to.length() < 1.25 and absf(best.position.y - pos.y) < 1.6 and m.attack_cd <= 0.0:
				m.attack_cd = 1.0
				best.take_damage(int(info.damage), pos, "gloomling")
				wish = Vector3.ZERO
		else:
			wish = _wander(m, delta)
		# lantern light keeps them back
		var ahead := pos + wish * 0.8 + Vector3(0, 0.5, 0)
		if world.block_light(ahead) > 0.4:
			wish = -wish * 0.6
	else:
		wish = _wander(m, delta)
		if m.hurt_t > 0.0:
			speed *= 2.4
	var vel: Vector3 = m.vel
	vel.x = lerpf(vel.x, wish.x * speed, minf(1.0, delta * 8.0))
	vel.z = lerpf(vel.z, wish.z * speed, minf(1.0, delta * 8.0))
	vel.y = maxf(vel.y - 26.0 * delta, -40.0)
	var res: Dictionary = world.move_box(pos, info.hw, info.h, vel * delta)
	pos = res.pos
	if res.floor:
		vel.y = 0.0
		if res.wall and wish.length() > 0.1:
			vel.y = 8.0  # hop up a one-block ledge
		elif m.kind == "puffkin" and wish.length() > 0.1 and rng.randf() < delta * 1.5:
			vel.y = 5.0
	m.vel = vel
	m.pos = pos
	if wish.length() > 0.1:
		m.yaw = lerp_angle(m.yaw, atan2(-wish.x, -wish.z), minf(1.0, delta * 8.0))
	var node: Node3D = m.node
	node.position = pos
	node.rotation.y = m.yaw
	var squash := 1.0 + sin(Time.get_ticks_msec() * 0.008 + pos.x) * 0.04
	node.scale = Vector3(1.0 / squash, squash, 1.0 / squash) * (1.0 - clampf(m.fade, 0.0, 1.0) * 0.7)
	var mat: ShaderMaterial = m.mat
	mat.set_shader_parameter("daylight", daylight)
	mat.set_shader_parameter("sky_light", world.sky_light(pos + Vector3(0, 0.5, 0)))
	mat.set_shader_parameter("block_light", world.block_light(pos + Vector3(0, 0.5, 0)))
	mat.set_shader_parameter("flash", Color(1, 1, 1, 0.6 if m.hurt_t > 0.2 else 0.0))
	return pos.y < -20.0

func _wander(m: Dictionary, delta: float) -> Vector3:
	m.wander_t -= delta
	if m.wander_t <= 0.0:
		m.wander_t = rng.randf_range(1.5, 4.0)
		var a := rng.randf() * TAU
		m.wander = Vector3(cos(a), 0, sin(a)) if rng.randf() < 0.65 else Vector3.ZERO
	return m.wander

# Closest creature hit by a ray, within reach of the player's head.
func ray_pick(origin: Vector3, dir: Vector3, max_d: float, head: Vector3, reach: float):
	var best = null
	var best_t := max_d
	for m in mobs:
		var info: Dictionary = KINDS[m.kind]
		var p: Vector3 = m.pos
		var lo := p - Vector3(info.hw, 0, info.hw)
		var hi := p + Vector3(info.hw, info.h, info.hw)
		var t := _ray_box(origin, dir, lo, hi)
		if t >= 0.0 and t < best_t and (origin + dir * t).distance_to(head) <= reach + 0.5:
			best_t = t
			best = m
	return best

static func _ray_box(o: Vector3, d: Vector3, lo: Vector3, hi: Vector3) -> float:
	var tmin := -INF
	var tmax := INF
	for a in 3:
		if absf(d[a]) < 1e-6:
			if o[a] < lo[a] or o[a] > hi[a]:
				return -1.0
		else:
			var t1 := (lo[a] - o[a]) / d[a]
			var t2 := (hi[a] - o[a]) / d[a]
			tmin = maxf(tmin, minf(t1, t2))
			tmax = minf(tmax, maxf(t1, t2))
	if tmax < maxf(tmin, 0.0):
		return -1.0
	return maxf(tmin, 0.0)

# Returns true if the hit counted (the attacker's weapon wears).
func hurt(m, damage: int, from: Vector3) -> bool:
	if m == null or not mobs.has(m):
		return false
	var away: Vector3 = m.pos - from
	away.y = 0
	m.vel += away.normalized() * 5.0 + Vector3(0, 4.0, 0)
	m.hurt_t = 0.35
	if m.kind == "puffkin":
		m.wander = away.normalized()
		m.wander_t = 2.0
		return false
	m.hp -= damage
	if game and game.get("audio"):
		game.audio.play_at("gloom", m.pos, 0.7)
	if m.hp <= 0:
		if game and game.has_method("spawn_item"):
			if rng.randf() < 0.5:
				game.spawn_item("ember", 1, m.pos + Vector3(0, 0.4, 0))
		if game and game.get("audio"):
			game.audio.play_at("puff", m.pos, 0.9)
		m.node.queue_free()
		mobs.erase(m)
	return true

func occupies(cell: Vector3i) -> bool:
	for m in mobs:
		var info: Dictionary = KINDS[m.kind]
		var p: Vector3 = m.pos
		if cell.x + 1 > p.x - info.hw and cell.x < p.x + info.hw and cell.y + 1 > p.y and cell.y < p.y + info.h \
				and cell.z + 1 > p.z - info.hw and cell.z < p.z + info.hw:
			return true
	return false

func clear_all() -> void:
	for m in mobs:
		m.node.queue_free()
	mobs.clear()
