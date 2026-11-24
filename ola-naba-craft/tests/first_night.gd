# Scripted Survival run of the first-night loop through the real controls:
# timber → planks → sticks → wood pick → slate → shelter → survive until morning.
# The script positions the player next to a tree (standing in for walking there) and aims the
# camera; every game action goes through held/pressed input with real mining times, real crafting
# and real placement rules. Naba stays outside in the open as a control to show the night threat.
# Run: godot --headless --path . --script tests/first_night.gd
extends SceneTree

const H := preload("res://tests/helpers.gd")
const B := preload("res://src/blocks.gd")
var failures := 0
var game: Node
var log_lines := []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, note: String) -> void:
	if not value:
		failures += 1
		push_error(note)
	print("  %s %s" % ["ok  " if value else "FAIL", note])

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func inp(held := {}) -> Dictionary:
	return {"held": held, "move": Vector2.ZERO, "look": Vector2.ZERO, "wheel": 0, "nav": Vector2i.ZERO}

func aim_at(p, point: Vector3) -> void:
	for k in 5:
		var origin: Vector3 = p.head() if k == 0 else p.eye.global_position
		var d := (point - origin).normalized()
		p.yaw = atan2(-d.x, -d.z)
		p.pitch = clampf(asin(clampf(d.y, -1.0, 1.0)), -1.47, 1.3)
		p.sync_view()

# Holds Mine on a block until it breaks. Returns seconds taken, or -1.
func mine(p, cell: Vector3i, limit := 15.0) -> float:
	var t := 0.0
	aim_at(p, Vector3(cell) + Vector3(0.5, 0.5, 0.5))
	game.input_override[p.player_number] = inp({"mine": true})
	while game.map.get_blockv(cell) != B.AIR and t < limit:
		aim_at(p, Vector3(cell) + Vector3(0.5, 0.5, 0.5))
		await physics_frame
		t += 1.0 / 60.0 * Engine.time_scale
	game.input_override[p.player_number] = inp()
	await frames(2)
	return t if game.map.get_blockv(cell) == B.AIR else -1.0

# Stands the player on the nearest free, solid-floored cell to a point (standing in for walking there).
func stand_near(p, point: Vector3) -> void:
	var map = game.map
	var best := Vector3.INF
	var c := Vector3i(floori(point.x), floori(point.y), floori(point.z))
	for dx in range(-4, 5):
		for dy in range(-3, 4):
			for dz in range(-4, 5):
				var cell := c + Vector3i(dx, dy, dz)
				if map.get_blockv(cell) != B.AIR or map.get_blockv(cell + Vector3i(0, 1, 0)) != B.AIR:
					continue
				var below: int = map.get_blockv(cell - Vector3i(0, 1, 0))
				if below <= 0 or not B.SOLID[below]:
					continue
				var pos := Vector3(cell) + Vector3(0.5, 0, 0.5)
				if pos.distance_to(point) < best.distance_to(point) or best == Vector3.INF:
					best = pos
	if best != Vector3.INF:
		p.position = best
		p.velocity = Vector3.ZERO

func select(p, key: String) -> bool:
	for i in 9:
		if p.inventory.get_slot(i).get("id", "") == key:
			p.hotbar = i
			return true
	# move it into the hotbar like the inventory screen does
	for i in range(9, 36):
		if p.inventory.get_slot(i).get("id", "") == key:
			p.inventory.move(i, 8)
			p.hotbar = 8
			return true
	return false

func run() -> void:
	game = H.make_game(self, "night")
	game.start_game(true, false, 0, false)
	await H.wait_loaded(self, game)
	await frames(30)
	var ola = game.players[0]
	var naba = game.players[1]
	var map = game.map
	ola.inventory.clear()
	naba.inventory.clear()
	# 1. find a tree near the spawn and stand beside its trunk
	var trunk := Vector3i.ZERO
	var found := false
	for r in range(2, 48):
		for dx in range(-r, r + 1):
			for dz in [-r, r]:
				for pair in [[dx, dz], [dz, dx]]:
					var x := floori(ola.position.x) + int(pair[0])
					var z := floori(ola.position.z) + int(pair[1])
					var y: int = map.surface_y(x, z)
					for yy in range(y - 10, y):
						if map.get_block(x, yy, z) == B.TIMBER and map.get_block(x, yy - 1, z) != B.TIMBER and not found:
							trunk = Vector3i(x, yy, z)
							found = true
		if found:
			break
	check(found, "a tree exists near the spawn")
	stand_near(ola, Vector3(trunk) + Vector3(0.5, 0.5, 0.5))
	await frames(20)
	# 2. collect timber with bare hands (hold Mine)
	var t0: float = await mine(ola, trunk)
	check(t0 > 1.5, "timber takes real time by hand (%.1f s)" % t0)
	for k in range(1, 3):
		if map.get_blockv(trunk + Vector3i(0, k, 0)) == B.TIMBER:
			await mine(ola, trunk + Vector3i(0, k, 0))
	await frames(30)
	# walk over to wherever the timber landed
	for d in game.drops.drops.duplicate():
		if d.key == "timber" and game.drops.drops.has(d):
			stand_near(ola, d.pos)
			await frames(60)
	var timber: int = ola.inventory.count("timber")
	check(timber >= 2, "collected timber (%d)" % timber)
	# 3. craft planks, sticks and a wood pick: exact inputs consumed
	# leaves broken on the way may have dropped bonus sticks or berries, so compare before/after
	var planks0: int = ola.inventory.count("planks")
	check(ola.craft("planks") and ola.craft("planks"), "two batches of planks")
	check(ola.inventory.count("planks") == planks0 + 8 and ola.inventory.count("timber") == timber - 2, "2 timber became 8 planks")
	var sticks0: int = ola.inventory.count("stick")
	check(ola.craft("stick"), "sticks")
	check(ola.inventory.count("stick") == sticks0 + 4 and ola.inventory.count("planks") == planks0 + 6, "2 planks became 4 sticks")
	var p1: int = ola.inventory.count("planks")
	var s1: int = ola.inventory.count("stick")
	check(ola.craft("wood_pick"), "wood pick")
	check(ola.inventory.count("planks") == p1 - 3 and ola.inventory.count("stick") == s1 - 2 and ola.inventory.count("wood_pick") == 1, "pick took exactly 3 planks + 2 sticks")
	# 4. dig straight down with the pick until slate
	ola.position = map.find_safe_spot(ola.position + Vector3(3, 0, 3), 6)
	await frames(30)
	check(select(ola, "wood_pick"), "pick in hand")
	var surface := floori(ola.position.y)
	var dug := 0
	while ola.inventory.count("slate") == 0 and dug < 14:
		var below := Vector3i(floori(ola.position.x), floori(ola.position.y) - 1, floori(ola.position.z))
		var id: int = map.get_blockv(below)
		if id == B.WATER or id == B.DEEPSTONE:
			break
		await mine(ola, below)
		await frames(40)
		dug += 1
	check(ola.inventory.count("slate") > 0, "mined slate with the wood pick after %d blocks" % dug)
	# keep digging so the shelter is at least three blocks deep
	while surface - floori(ola.position.y) < 3:
		var below := Vector3i(floori(ola.position.x), floori(ola.position.y) - 1, floori(ola.position.z))
		await mine(ola, below)
		await frames(40)
	await frames(60)
	# 5. roof over the pit using a block from the inventory (press Place)
	var feet := Vector3i(floori(ola.position.x), floori(ola.position.y), floori(ola.position.z))
	var roof := feet + Vector3i(0, 2, 0)
	var block_key := ""
	for k in ["soil", "moss", "lilac_moss", "slate", "planks", "sand"]:
		if ola.inventory.count(k) > 0:
			block_key = k
			break
	check(block_key != "" and select(ola, block_key), "a block to build with")
	var placed := false
	for side in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var wall: Vector3i = roof + side
		if B.SOLID[maxi(0, map.get_blockv(wall))] and map.get_blockv(roof) == B.AIR:
			for attempt in 3:
				# aim at the wall face that touches the roof cell
				aim_at(ola, Vector3(wall) + Vector3(0.5, 0.5, 0.5) - Vector3(side) * 0.49)
				await frames(2)
				game.input_override[0] = inp({"place": true})
				await frames(2)
				game.input_override[0] = inp()
				await frames(10)
				if map.get_blockv(roof) != B.AIR:
					placed = true
					break
		if placed:
			break
	check(placed, "roofed the pit with %s" % block_key)
	await frames(10)
	check(map.sky_light(ola.head()) < 0.95, "the shelter has a roof")
	check(ola.tutorial_step >= 4, "tutorial reached the shelter step (step %d)" % (ola.tutorial_step + 1))
	# 6. Naba waits outside in the open
	naba.position = map.find_safe_spot(Vector3(trunk) + Vector3(-12, 0, 8), 8)
	# 7. the night, sped up. Creature spawning is seeded so the run is repeatable; one Gloomling
	# is placed near Naba at nightfall so the outdoor danger is checked every run.
	game.mobs.rng.seed = 4242
	game.time = game.DUSK - 5.0
	Engine.time_scale = 6.0
	var start_day: int = game.day_number()
	var morning: float = floorf(game.time / game.DAY_LENGTH) * game.DAY_LENGTH + game.DAWN + 20.0
	var max_gloom := 0
	var naba_min := 20
	var ola_min := 20
	var t := 0.0
	var placed_near_naba := false
	while game.time < morning:
		await physics_frame
		if not placed_near_naba and game.is_night():
			placed_near_naba = true
			game.mobs.spawn("gloomling", naba.position + Vector3(1.6, 0.2, 0))
		t += 1.0 / 60.0
		max_gloom = maxi(max_gloom, game.mobs.mobs.filter(func(m): return m.kind == "gloomling").size())
		naba_min = mini(naba_min, naba.health)
		ola_min = mini(ola_min, ola.health)
		if t > 120.0:
			break
	Engine.time_scale = 1.0
	await frames(30)
	print("  night: %.0f s real time, up to %d gloomlings, Ola lowest health %d, Naba lowest %d (fainted %d times)" % [t, max_gloom, ola_min, naba_min, naba.stats.faints])
	check(max_gloom > 0, "gloomlings came out at night")
	check(naba_min < 20 or naba.stats.faints > 0, "the night is dangerous outside (Naba was hurt)")
	check(ola.stats.faints == 0 and ola.health > 0, "Ola survived the night in her shelter")
	check(ola.stats.nights >= 1 and game.day_number() == start_day + 1, "morning came: day %d" % game.day_number())
	check(ola.tutorial_done, "Ola's tutorial completed")
	game.time = morning + 20.0   # full daylight
	await frames(150)
	check(game.mobs.mobs.filter(func(m): return m.kind == "gloomling").size() == 0, "gloomlings gone after sunrise")
	game.end_session()
	print("FIRST NIGHT: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
