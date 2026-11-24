# One local player: third-person camera, voxel box collision, mining with progress and tool tiers,
# placement that never traps anyone, survival stats, fainting and safe respawn.
# Driven by game.gd once per physics frame with that player's own input only.
extends Node3D

const B := preload("res://src/blocks.gd")
const Items := preload("res://src/items.gd")
const Inventory := preload("res://src/inventory.gd")
const Avatar := preload("res://src/avatar.gd")
const Router := preload("res://src/input_router.gd")
const NAMES := ["Ola", "Naba"]
const PROFILES := ["ola", "naba"]
const HW := 0.3
const HEIGHT := 1.8
const EYE := 1.55
const REACH := 5.0
const MAX_HEALTH := 20
const MAX_FOOD := 20
const WALK := 4.6
const FLY := 9.0
const GRAVITY := 26.0
const JUMP := 8.2
const CREATIVE_START := ["moss", "planks", "slate_brick", "glowglass", "timber", "blossom", "sand", "lantern", "lilac_moss"]

var game: Node
var world: Node
var player_number := 0
var avatar := 0
var creative := false
var eye: Camera3D
var body: Node3D
var yaw := 0.0
var pitch := -0.25
var body_yaw := 0.0
var velocity := Vector3.ZERO
var on_floor := false
var flying := false
var in_water := false
var health := MAX_HEALTH
var food := MAX_FOOD
var inventory = Inventory.new()
var hotbar := 0
var controls := true      # false while the whole game is paused
var ui_open := false      # this player's own inventory is open: only their controls stop
var bench_open := false
var cam_dist := 3.8
var cam_actual := 3.8
var target := {}
var target_mob = null    # a creature record (Dictionary) from mobs.ray_pick, or null
var mine_cell := Vector3i(0, -999, 0)
var mine_progress := 0.0
var mining := false
var place_cd := 0.0
var attack_cd := 0.0
var dig_sound_cd := 0.0
var invuln := 0.0
var food_clock := 0.0
var regen_clock := 0.0
var starve_clock := 0.0
var fall_from := 0.0
var fainted := 0.0
var has_bed := false
var bed := Vector3.ZERO
var resting := false
var last_jump := -10.0
var prev := {}
var hurt_flash := 0.0
var notice := ""
var notice_time := 0.0
var tutorial_step := 0
var tutorial_done := false
var light_clock := 0.0
var stats := {"mined": 0, "placed": 0, "crafted": 0, "nights": 0, "faints": 0}

func setup(g: Node, w: Node, which: int, skin: int, is_creative: bool, camera: Camera3D, show_tablet := false) -> void:
	game = g
	world = w
	player_number = which
	avatar = skin
	creative = is_creative
	eye = camera
	body = Avatar.new()
	add_child(body)
	body.build(avatar, show_tablet)
	body_yaw = yaw
	if creative:
		for i in CREATIVE_START.size():
			inventory.set_slot(i, {"id": CREATIVE_START[i], "n": 1})
	sync_view()

func display_name() -> String:
	return NAMES[avatar]

func profile() -> String:
	return PROFILES[avatar]

# Starter compatibility: the keyboard keys this player's default layout uses.
func keys() -> Array:
	var src: Dictionary = Router.DEFAULT_KB1 if player_number == 0 else Router.DEFAULT_KB2
	var out := []
	for a in src:
		if a != "pause":
			out.append_array(src[a])
	return out

func is_on_floor() -> bool:
	return on_floor

func head() -> Vector3:
	return position + Vector3(0, EYE, 0)

func selected_key() -> String:
	return String(inventory.get_slot(hotbar).get("id", ""))

func select_slot(offset: int) -> void:
	hotbar = posmod(hotbar + offset, Inventory.HOTBAR)

func say(text: String, seconds := 2.5) -> void:
	notice = text
	notice_time = seconds

# ------------------------------------------------------------------ per-frame update

func tick(delta: float, inp: Dictionary) -> void:
	place_cd = maxf(0.0, place_cd - delta)
	attack_cd = maxf(0.0, attack_cd - delta)
	invuln = maxf(0.0, invuln - delta)
	hurt_flash = maxf(0.0, hurt_flash - delta * 2.0)
	notice_time = maxf(0.0, notice_time - delta)
	if fainted > 0.0:
		fainted -= delta
		if fainted <= 0.0:
			respawn()
		sync_view()
		return
	var held: Dictionary = inp.get("held", {})
	var pressed := {}
	for a in held:
		pressed[a] = held[a] and not prev.get(a, false)
	prev = held.duplicate()
	var move: Vector2 = inp.get("move", Vector2.ZERO)
	var look: Vector2 = inp.get("look", Vector2.ZERO)
	if not controls or ui_open:
		held = {}
		pressed = {}
		move = Vector2.ZERO
		look = Vector2.ZERO
	yaw -= look.x
	pitch = clampf(pitch - look.y, -1.47, 1.3)
	var wheel: int = inp.get("wheel", 0)
	if controls and not ui_open:
		if pressed.get("next", false) or wheel > 0:
			select_slot(1)
		if pressed.get("prev", false) or wheel < 0:
			select_slot(-1)
		if pressed.get("jump", false):
			var now := Time.get_ticks_msec() / 1000.0
			if creative and now - last_jump < 0.32:
				flying = not flying
				say("Flying" if flying else "Walking", 1.2)
			last_jump = now
	_move(delta, move, held)
	update_target()
	mining = false
	if held.get("mine", false):
		_mine_or_attack(delta, pressed.get("mine", false))
	else:
		mine_progress = maxf(0.0, mine_progress - delta * 2.0)
	if pressed.get("place", false) or (held.get("place", false) and place_cd <= 0.0):
		place_cd = 0.26
		interact_or_place(held.get("down", false))
	if pressed.get("use", false):
		use_item()
	if pressed.get("inventory", false) and game and game.has_method("toggle_inventory"):
		game.toggle_inventory(self, false)
	if not creative:
		_survival(delta)
	sync_view()
	body.set_held(selected_key())
	var hspeed := Vector2(velocity.x, velocity.z).length()
	body.animate(delta, {"speed": hspeed, "floor": on_floor or in_water, "mining": mining, "flying": flying, "pitch": pitch})
	light_clock -= delta
	if light_clock <= 0.0 and world:
		light_clock = 0.2
		var daylight: float = game.daylight if game and "daylight" in game else 1.0
		body.set_light(daylight, world.sky_light(head()), world.block_light(head()))

func _move(delta: float, mv: Vector2, held: Dictionary) -> void:
	var wish := Vector3(mv.x, 0, mv.y).rotated(Vector3.UP, yaw)
	in_water = world.get_block(floori(position.x), floori(position.y + 0.5), floori(position.z)) == B.WATER
	if flying:
		var up := float(held.get("jump", false)) - float(held.get("down", false))
		velocity = velocity.lerp(Vector3(wish.x * FLY, up * 7.0, wish.z * FLY), minf(1.0, delta * 10.0))
	else:
		var speed := WALK * (0.55 if in_water else 1.0)
		var grip := 14.0 if (on_floor or in_water) else 4.0
		velocity.x = lerpf(velocity.x, wish.x * speed, minf(1.0, delta * grip))
		velocity.z = lerpf(velocity.z, wish.z * speed, minf(1.0, delta * grip))
		if in_water:
			velocity.y -= 9.0 * delta
			if held.get("jump", false):
				velocity.y = minf(velocity.y + 32.0 * delta, 3.6)
			velocity.y = maxf(velocity.y, -3.2)
		else:
			velocity.y -= GRAVITY * delta
			if held.get("jump", false) and on_floor:
				velocity.y = JUMP
			velocity.y = maxf(velocity.y, -48.0)
	var was_floor := on_floor
	var res: Dictionary = world.move_box(position, HW, HEIGHT, velocity * delta)
	position = res.pos
	on_floor = res.floor
	if res.floor and velocity.y < 0.0:
		velocity.y = 0.0
	if res.ceiling and velocity.y > 0.0:
		velocity.y = 0.0
	if wish.length() > 0.1:
		body_yaw = lerp_angle(body_yaw, atan2(-wish.x, -wish.z), minf(1.0, delta * 12.0))
	if on_floor or in_water or flying:
		if on_floor and not was_floor and not creative and not in_water:
			var drop := fall_from - position.y
			if drop > 3.6:
				take_damage(int(drop - 3.0) * 2, Vector3.INF, "fall")
		fall_from = position.y
	else:
		fall_from = maxf(fall_from, position.y)
	if position.y < -16.0:
		if creative:
			position = world.find_safe_spot(position)
			velocity = Vector3.ZERO
		else:
			take_damage(MAX_HEALTH * 2, Vector3.INF, "void")

# Third-person shoulder camera that slides in instead of passing through blocks.
func sync_view() -> void:
	if eye == null:
		return
	var h := head()
	var fwd := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var pivot := h + right * 0.42 + Vector3(0, 0.18, 0)
	if world and world.is_solid(floori(pivot.x), floori(pivot.y), floori(pivot.z)):
		pivot = h
	var dist := cam_dist
	if world:
		var hit: Dictionary = world.raycast(pivot, -fwd, cam_dist + 0.3)
		if not hit.is_empty():
			dist = clampf(float(hit.distance) - 0.3, 0.25, cam_dist)
	cam_actual = dist
	eye.global_position = pivot - fwd * dist
	eye.global_rotation = Vector3(pitch, yaw, 0)
	if mining or place_cd > 0.15:
		body_yaw = lerp_angle(body_yaw, yaw, 0.5)
	elif absf(angle_difference(body_yaw, yaw)) > 1.4:
		body_yaw = lerp_angle(body_yaw, yaw, 0.08)  # idle: turn to roughly face where the camera looks
	body.rotation.y = body_yaw
	# hide your own avatar from your own camera only when the camera is squeezed into your head
	var bit := 1 << (player_number + 10)
	_set_layers(body, bit)
	eye.cull_mask = (eye.cull_mask | bit) if dist > 0.8 else (eye.cull_mask & ~bit)

func _set_layers(node: Node, bit: int) -> void:
	if node is VisualInstance3D and node.layers != bit:
		node.layers = bit
	for c in node.get_children():
		_set_layers(c, bit)

func aim() -> Array:
	return [eye.global_position, -eye.global_basis.z]

func update_target() -> void:
	var a := aim()
	var origin: Vector3 = a[0]
	var fwd: Vector3 = a[1]
	var hit: Dictionary = world.raycast(origin, fwd, cam_actual + REACH, maxf(0.0, cam_actual - 0.6))
	if not hit.is_empty():
		var center := Vector3(hit.cell) + Vector3(0.5, 0.5, 0.5)
		if center.distance_to(head()) > REACH + 0.9:
			hit = {}
	target = hit
	target_mob = null
	if game and game.get("mobs") != null:
		var max_d: float = float(hit.distance) if not hit.is_empty() else cam_actual + REACH
		target_mob = game.mobs.ray_pick(origin, fwd, max_d, head(), REACH)

# ------------------------------------------------------------------ mining and placing

func held_tool() -> Dictionary:
	var info := Items.info(selected_key())
	return info if info.get("kind", "") == "tool" else {}

func can_harvest(id: int) -> bool:
	var need: int = B.MIN_TIER[id]
	if need == 0:
		return true
	var tool := held_tool()
	return tool.get("tool", "") == "pick" and int(tool.get("tier", 0)) >= need

func mine_speed(id: int) -> float:
	var tool := held_tool()
	var speed := 1.0
	if B.TOOL[id] != "" and tool.get("tool", "") == B.TOOL[id]:
		speed = float(tool.speed)
	if not can_harvest(id):
		speed *= 0.3
	return speed

func _mine_or_attack(delta: float, just_pressed: bool) -> void:
	if target_mob != null:
		if attack_cd <= 0.0:
			attack_cd = 0.45
			body.pulse_use()
			var tool := held_tool()
			var dmg: int = int(tool.get("damage", 1))
			if game.mobs.hurt(target_mob, dmg, position):
				if not tool.is_empty():
					_wear()
		return
	if target.is_empty():
		mine_progress = 0.0
		return
	mining = true
	var cell: Vector3i = target.cell
	if creative:
		if just_pressed or place_cd <= 0.0:
			place_cd = 0.22
			break_block(cell)
		return
	if cell != mine_cell:
		mine_cell = cell
		mine_progress = 0.0
	var id: int = world.get_blockv(cell)
	if id <= 0 or B.HARDNESS[id] < 0.0:
		return
	mine_progress += delta * mine_speed(id) / float(B.HARDNESS[id])
	dig_sound_cd -= delta
	if dig_sound_cd <= 0.0:
		dig_sound_cd = 0.26
		if game and game.get("audio"):
			game.audio.play_at("dig_" + B.SOUND[id], Vector3(cell), 0.6)
	if mine_progress >= 1.0:
		mine_progress = 0.0
		break_block(cell)

# Removes a block now. In Survival the drops spawn in the world (anyone may pick them up).
func break_block(cell: Vector3i) -> bool:
	var id: int = world.get_blockv(cell)
	if id <= 0 or id == B.WATER or B.HARDNESS[id] < 0.0:
		return false
	var harvest := can_harvest(id)
	var used_tool := not held_tool().is_empty()
	if not world.set_block(cell.x, cell.y, cell.z, B.AIR):
		return false
	stats.mined += 1
	if not creative:
		if harvest and game and game.has_method("spawn_drops"):
			game.spawn_drops(cell, id)
		if used_tool:
			_wear()
	if game and game.has_method("on_block_changed"):
		game.on_block_changed(cell, id, B.AIR, self)
	body.pulse_use()
	return true

func _wear() -> void:
	if inventory.wear(hotbar):
		say("Your tool broke")
		if game and game.get("audio"):
			game.audio.play("break_tool")

func cell_blocked(cell: Vector3i) -> bool:
	if game and game.has_method("cell_occupied"):
		return game.cell_occupied(cell)
	return _overlaps(cell)

func _overlaps(cell: Vector3i) -> bool:
	return cell.x + 1 > position.x - HW and cell.x < position.x + HW and cell.y + 1 > position.y and \
		cell.y < position.y + HEIGHT and cell.z + 1 > position.z - HW and cell.z < position.z + HW

func interact_or_place(sneaking := false) -> bool:
	if target.is_empty():
		return use_item()
	var id: int = target.id
	if not sneaking:
		if id == B.WORKBENCH and game and game.has_method("toggle_inventory"):
			game.toggle_inventory(self, true)
			return true
		if id == B.BEDROLL:
			return rest_at(target.cell)
	if Items.info(selected_key()).get("kind", "") == "food":
		return use_item()
	return place_block()

func place_block() -> bool:
	if target.is_empty():
		return false
	var key := selected_key()
	var block := Items.block_of(key)
	if block < 0:
		return false
	var cell: Vector3i = target.cell + target.normal
	var cur: int = world.get_blockv(cell)
	if cur != B.AIR and cur != B.WATER:
		return false
	if B.SOLID[block] and cell_blocked(cell):
		return false
	if not world.set_block(cell.x, cell.y, cell.z, block):
		return false
	if not creative:
		inventory.take_one(hotbar)
	stats.placed += 1
	body.pulse_use()
	if game and game.has_method("on_block_changed"):
		game.on_block_changed(cell, cur, block, self)
	return true

# Starter compatibility: act on the targeted block immediately (mine or place).
func use_block(place: bool) -> bool:
	update_target()
	if target.is_empty():
		return false
	return place_block() if place else break_block(target.cell)

func use_item() -> bool:
	var info := Items.info(selected_key())
	if info.get("kind", "") == "food":
		if creative or food >= MAX_FOOD:
			say("You are not hungry", 1.5)
			return false
		inventory.take_one(hotbar)
		food = mini(MAX_FOOD, food + int(info.food))
		body.pulse_use()
		if game and game.get("audio"):
			game.audio.play("eat")
		return true
	return false

func eat_canopy_berries() -> bool:
	if creative or food >= MAX_FOOD or not inventory.remove("berries", 1):
		return false
	food = mini(MAX_FOOD, food + int(Items.info("berries").food))
	return true

# Crafting: consumes exactly the recipe inputs, or nothing at all.
func can_craft(recipe_id: String, at_bench := false) -> bool:
	var r := Items.recipe(recipe_id)
	if r.is_empty() or creative:
		return false
	if r.station == "bench" and not (at_bench or near_bench()):
		return false
	for k in r.needs:
		if inventory.count(k) < int(r.needs[k]):
			return false
	return inventory.can_add(r.out, int(r.n))

func craft(recipe_id: String, at_bench := false) -> bool:
	if not can_craft(recipe_id, at_bench):
		return false
	var r := Items.recipe(recipe_id)
	for k in r.needs:
		inventory.remove(k, int(r.needs[k]))
	inventory.add(r.out, int(r.n))
	stats.crafted += 1
	if game and game.get("audio"):
		game.audio.play("craft")
	return true

func craft_planks() -> bool:
	return craft("planks")

func near_bench() -> bool:
	var c := Vector3i(floori(position.x), floori(position.y), floori(position.z))
	for x in range(-3, 4):
		for y in range(-2, 4):
			for z in range(-3, 4):
				if world.get_block(c.x + x, c.y + y, c.z + z) == B.WORKBENCH:
					return true
	return false

func rest_at(cell: Vector3i) -> bool:
	has_bed = true
	bed = Vector3(cell) + Vector3(0.5, 1.0, 0.5)
	if game and game.has_method("try_rest"):
		game.try_rest(self)
	else:
		say("Respawn point set")
	return true

# ------------------------------------------------------------------ survival

func _survival(delta: float) -> void:
	food_clock += delta * (1.5 if mining else 1.0)
	if food_clock >= 30.0:
		food_clock = 0.0
		food = maxi(0, food - 1)
	if food >= 16 and health < MAX_HEALTH:
		regen_clock += delta
		if regen_clock >= 3.5:
			regen_clock = 0.0
			health += 1
	elif food == 0:
		starve_clock += delta
		if starve_clock >= 5.0:
			starve_clock = 0.0
			if health > 2:
				health -= 1
				hurt_flash = 1.0
				say("You are starving: eat berries")

func take_damage(amount: int, from := Vector3.INF, kind := "hit") -> bool:
	if creative or fainted > 0.0 or invuln > 0.0 or amount <= 0:
		return false
	health -= amount
	invuln = 0.6
	hurt_flash = 1.0
	body.hurt_flash()
	if from != Vector3.INF:
		var away := position - from
		away.y = 0
		velocity += away.normalized() * 6.0 + Vector3(0, 4.5, 0)
	if game and game.get("audio"):
		game.audio.play("hurt")
	if health <= 0:
		faint(kind)
	return true

func faint(kind := "hit") -> void:
	health = 0
	fainted = 3.0
	stats.faints += 1
	velocity = Vector3.ZERO
	if game and game.has_method("on_player_fainted"):
		game.on_player_fainted(self, kind)

func respawn() -> void:
	var spot: Vector3 = game.world_spawn if game and "world_spawn" in game else position
	if has_bed:
		if world.get_block(floori(bed.x), floori(bed.y - 1.0), floori(bed.z)) == B.BEDROLL:
			spot = bed
		else:
			has_bed = false
			say("Your bedroll is gone; back to the world spawn")
	position = world.find_safe_spot(spot, 30)
	velocity = Vector3.ZERO
	health = MAX_HEALTH
	food = maxi(food, 14)
	fall_from = position.y
	invuln = 2.5
	fainted = 0.0
	sync_view()

# ------------------------------------------------------------------ save data

func snapshot() -> Dictionary:
	var data := {"avatar": profile(), "position": [position.x, position.y, position.z], "yaw": yaw, "pitch": pitch,
		"hotbar": hotbar, "health": health, "food": food, "flying": flying, "tutorial_step": tutorial_step,
		"tutorial_done": tutorial_done, "stats": stats.duplicate()}
	data["creative_inventory" if creative else "inventory"] = inventory.to_save()
	if has_bed:
		data["bed"] = [bed.x, bed.y, bed.z]
	return data

func restore(data: Dictionary) -> void:
	var pos: Array = data.get("position", [])
	if pos.size() == 3:
		position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		fall_from = position.y
	yaw = float(data.get("yaw", 0.0))
	pitch = clampf(float(data.get("pitch", -0.2)), -1.47, 1.3)
	hotbar = clampi(int(data.get("hotbar", 0)), 0, Inventory.HOTBAR - 1)
	health = clampi(int(data.get("health", MAX_HEALTH)), 1, MAX_HEALTH)
	food = clampi(int(data.get("food", MAX_FOOD)), 0, MAX_FOOD)
	flying = creative and bool(data.get("flying", false))
	tutorial_step = int(data.get("tutorial_step", 0))
	tutorial_done = bool(data.get("tutorial_done", false))
	var key := "creative_inventory" if creative else "inventory"
	if data.get(key) is Array:
		inventory.from_save(data[key])
	var b = data.get("bed")
	if b is Array and b.size() == 3:
		has_bed = true
		bed = Vector3(float(b[0]), float(b[1]), float(b[2]))
	var st = data.get("stats")
	if st is Dictionary:
		for k in st:
			stats[k] = int(st[k])
	body_yaw = yaw
	sync_view()
