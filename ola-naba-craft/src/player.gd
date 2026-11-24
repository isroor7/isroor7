extends CharacterBody3D

const P1 := [KEY_W, KEY_S, KEY_A, KEY_D, KEY_SPACE, KEY_SHIFT, KEY_Q, KEY_E, KEY_R, KEY_F, KEY_T, KEY_G]
const P2 := [KEY_I, KEY_K, KEY_J, KEY_L, KEY_ENTER, KEY_P, KEY_COMMA, KEY_PERIOD, KEY_SLASH, KEY_BACKSLASH, KEY_M, KEY_N]
const Terrain := preload("res://src/terrain.gd")
var player_number := 0
var avatar := 0
var creative := false
var terrain: GridMap
var eye: Camera3D
var body_art: Node3D
var yaw := 0.0
var pitch := -0.12
var hotbar := 0
var inventory := [0, 0, 0, 0, 0, 0, 0]
var hp := 5
var stamina := 5
var survival_clock := 0.0
var pad := -1
var prev := {}
var controls := true

func setup(which: int, skin: int, is_creative: bool, map: GridMap, camera: Camera3D) -> void:
	player_number = which
	avatar = skin
	creative = is_creative
	terrain = map
	eye = camera
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.29
	capsule.height = 1.65
	var coll := CollisionShape3D.new()
	coll.shape = capsule
	coll.position.y = 0.825
	add_child(coll)
	body_art = Node3D.new()
	add_child(body_art)
	var shirt := Color("#243c78") if avatar == 0 else Color("#f27ca9")
	var leg := Color("#ae99cf") if avatar == 0 else Color("#b83d71")
	var hair := Color("#d78fa2") if avatar == 0 else Color("#39272f")
	var skin_tone := Color("#f0aa7e")
	cube(Vector3(0,1.25,0), Vector3(.52,.52,.31), shirt)
	cube(Vector3(0,1.67,0), Vector3(.47,.42,.43), hair)
	cube(Vector3(0,1.65,-.211), Vector3(.32,.25,.03), skin_tone)
	for side in [-1, 1]:
		cube(Vector3(.10 * side,1.67,-.232), Vector3(.045,.04,.015), Color("#252133"))
		cube(Vector3(.18 * side,.55,0), Vector3(.22,.61,.24), leg)
		cube(Vector3(.18 * side,.18,-.025), Vector3(.24,.16,.29), Color("#f1d9e6"))
		cube(Vector3(.36 * side,1.16,0), Vector3(.18,.46,.22), shirt)
	if avatar == 0:
		cube(Vector3(0,1.46,-.19), Vector3(.40,.12,.08), hair)
	else:
		cube(Vector3(.07,1.75,-.222), Vector3(.31,.09,.03), hair)
	eye.cull_mask = eye.cull_mask & ~(1 << (player_number + 1))
	position = Vector3(-1.25 if player_number == 0 else 1.25, 2.0, 0.5)
	sync_view()

func cube(coord: Vector3, dimensions: Vector3, tint: Color) -> void:
	var part := MeshInstance3D.new()
	var model := BoxMesh.new()
	model.size = dimensions
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	model.material = mat
	part.mesh = model
	part.layers = 1 << (player_number + 1)
	part.position = coord
	body_art.add_child(part)

func keys() -> Array:
	return P1 if player_number == 0 else P2

func pressed(index: int) -> bool:
	return Input.is_physical_key_pressed(keys()[index])

func edge(id: String, down: bool) -> bool:
	var fired: bool = down and not prev.get(id, false)
	prev[id] = down
	return fired

func joy(button: int) -> bool:
	return pad >= 0 and Input.is_joy_button_pressed(pad, button)

func axis(index: int) -> float:
	if pad < 0:
		return 0.0
	var amount := Input.get_joy_axis(pad, index)
	return amount if absf(amount) > .2 else 0.0

func look(dx: float, dy: float) -> void:
	yaw -= dx
	pitch = clampf(pitch - dy, -1.47, 1.47)

func sync_view() -> void:
	eye.global_position = global_position + Vector3(0, 1.56, 0)
	eye.global_rotation = Vector3(pitch, yaw, 0)
	body_art.rotation.y = yaw

func _physics_process(delta: float) -> void:
	if not controls:
		return
	var mx := float(pressed(3)) - float(pressed(2)) + axis(JOY_AXIS_LEFT_X)
	var mz := float(pressed(1)) - float(pressed(0)) + axis(JOY_AXIS_LEFT_Y)
	var lx := axis(JOY_AXIS_RIGHT_X)
	var ly := axis(JOY_AXIS_RIGHT_Y)
	if player_number == 1:
		lx += float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
		ly += float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP))
	look(lx * 2.3 * delta, ly * 2.3 * delta)
	var wish := Vector3(mx, 0, mz).limit_length().rotated(Vector3.UP, yaw)
	velocity.x = wish.x * 5.6
	velocity.z = wish.z * 5.6
	if creative:
		velocity.y = (float(pressed(4) or joy(JOY_BUTTON_A)) - float(pressed(5) or joy(JOY_BUTTON_B))) * 5.1
	else:
		if not is_on_floor():
			velocity.y -= 19.0 * delta
		elif pressed(4) or joy(JOY_BUTTON_A):
			velocity.y = 6
		survival_clock += delta
		if survival_clock >= 36.0:
			survival_clock = 0
			if stamina > 0:
				stamina -= 1
			else:
				hp -= 1
	if global_position.y < -12 or hp <= 0:
		position = Vector3(-1.25 if player_number == 0 else 1.25, 2, .5)
		velocity = Vector3.ZERO
		hp = 5
		stamina = 5
	move_and_slide()
	sync_view()
	if edge("mine", pressed(6) or joy(JOY_BUTTON_RIGHT_SHOULDER)):
		use_block(false)
	if edge("place", pressed(7) or joy(JOY_BUTTON_LEFT_SHOULDER)):
		use_block(true)
	if edge("next", pressed(8) or joy(JOY_BUTTON_DPAD_RIGHT)):
		select_slot(1)
	if edge("prev", pressed(9) or joy(JOY_BUTTON_DPAD_LEFT)):
		select_slot(-1)
	if edge("craft", pressed(10) or joy(JOY_BUTTON_Y)):
		craft_planks()
	if edge("snack", pressed(11) or joy(JOY_BUTTON_X)):
		eat_canopy_berries()

func select_slot(offset: int) -> void:
	hotbar = posmod(hotbar + offset, Terrain.BLOCKS.size())

func craft_planks() -> bool:
	if creative or inventory[3] < 1:
		return false
	inventory[3] -= 1
	inventory[5] += 4
	return true

func eat_canopy_berries() -> bool:
	if creative or stamina >= 5 or inventory[4] < 1:
		return false
	inventory[4] -= 1
	stamina = mini(stamina + 2, 5)
	return true

func use_block(place: bool) -> bool:
	var from := eye.global_position
	var to := from - eye.global_basis.z * 5.4
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var normal: Vector3 = hit.normal
	var hit_point: Vector3 = hit.position
	var cell := terrain.local_to_map(terrain.to_local(hit_point + normal * (.06 if place else -.06)))
	if place:
		if terrain.get_cell_item(cell) != -1 or (not creative and inventory[hotbar] <= 0):
			return false
		var shape := BoxShape3D.new()
		shape.size = Vector3.ONE * .97
		var space := PhysicsShapeQueryParameters3D.new()
		space.shape = shape
		space.transform.origin = Vector3(cell) + Vector3.ONE * .5
		space.collision_mask = 2
		if not get_world_3d().direct_space_state.intersect_shape(space, 1).is_empty():
			return false
		if not terrain.change(cell, hotbar):
			return false
		if not creative:
			inventory[hotbar] -= 1
		return true
	var old: int = terrain.get_cell_item(cell)
	if old < 0 or not terrain.change(cell, -1):
		return false
	if not creative:
		inventory[old] += 1
	return true

func snapshot() -> Dictionary:
	return {"position": [position.x, position.y, position.z], "yaw": yaw,
		"pitch": pitch, "hotbar": hotbar, "inventory": inventory.duplicate(),
		"hp": hp, "stamina": stamina, "survival_clock": survival_clock}

func restore(data: Dictionary) -> void:
	var pos: Array = data.get("position", [])
	if pos.size() == 3:
		position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	yaw = float(data.get("yaw", 0.0))
	pitch = clampf(float(data.get("pitch", -.12)), -1.47, 1.47)
	hotbar = clampi(int(data.get("hotbar", 0)), 0, Terrain.BLOCKS.size() - 1)
	var stock: Array = data.get("inventory", [])
	if stock.size() == inventory.size():
		for i in stock.size():
			inventory[i] = maxi(0, int(stock[i]))
	hp = clampi(int(data.get("hp", 5)), 1, 5)
	stamina = clampi(int(data.get("stamina", 5)), 0, 5)
	survival_clock = clampf(float(data.get("survival_clock", 0)), 0, 36)
	sync_view()
