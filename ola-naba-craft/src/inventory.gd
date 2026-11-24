# One player's stacked inventory: 36 slots, the first 9 are the hotbar.
# A slot is {} when empty or {"id": item key, "n": count, "d": durability left (tools only)}.
extends RefCounted

const Items := preload("res://src/items.gd")
const SIZE := 36
const HOTBAR := 9

var slots: Array = []

func _init() -> void:
	clear()

func clear() -> void:
	slots.clear()
	for i in SIZE:
		slots.append({})

func get_slot(i: int) -> Dictionary:
	return slots[i] if i >= 0 and i < SIZE else {}

func set_slot(i: int, value: Dictionary) -> void:
	slots[i] = value.duplicate() if not value.is_empty() and int(value.get("n", 0)) > 0 else {}

func count(id: String) -> int:
	var total := 0
	for s in slots:
		if s.get("id", "") == id:
			total += int(s.n)
	return total

func is_empty() -> bool:
	for s in slots:
		if not s.is_empty():
			return false
	return true

# Adds items, filling existing stacks first, then empty slots (hotbar first).
# Returns how many did not fit.
func add(id: String, n: int, durability := -1) -> int:
	if n <= 0 or not Items.exists(id):
		return n
	var max_stack := Items.stack_size(id)
	if max_stack > 1:
		for s in slots:
			if s.get("id", "") == id and int(s.n) < max_stack:
				var put := mini(n, max_stack - int(s.n))
				s.n = int(s.n) + put
				n -= put
				if n == 0:
					return 0
	for i in SIZE:
		if slots[i].is_empty():
			var put := mini(n, max_stack)
			var entry := {"id": id, "n": put}
			var info := Items.info(id)
			if info.get("kind", "") == "tool":
				entry["d"] = durability if durability > 0 else int(info.durability)
			slots[i] = entry
			n -= put
			if n == 0:
				return 0
	return n

func can_add(id: String, n: int) -> bool:
	var room := 0
	var max_stack := Items.stack_size(id)
	for s in slots:
		if s.is_empty():
			room += max_stack
		elif s.id == id and max_stack > 1:
			room += max_stack - int(s.n)
	return room >= n

# Removes n of an item across stacks. All or nothing.
func remove(id: String, n: int) -> bool:
	if n <= 0:
		return true
	if count(id) < n:
		return false
	for i in range(SIZE - 1, -1, -1):
		var s: Dictionary = slots[i]
		if s.get("id", "") == id:
			var take := mini(n, int(s.n))
			s.n = int(s.n) - take
			n -= take
			if int(s.n) <= 0:
				slots[i] = {}
			if n == 0:
				break
	return true

# Removes one from a specific slot; returns the item key taken or "".
func take_one(i: int) -> String:
	var s: Dictionary = slots[i]
	if s.is_empty():
		return ""
	var id: String = s.id
	s.n = int(s.n) - 1
	if int(s.n) <= 0:
		slots[i] = {}
	return id

func swap(a: int, b: int) -> void:
	var t: Dictionary = slots[a]
	slots[a] = slots[b]
	slots[b] = t

# Moves or merges slot a into slot b (inventory screen).
func move(a: int, b: int) -> void:
	if a == b:
		return
	var sa: Dictionary = slots[a]
	var sb: Dictionary = slots[b]
	if not sa.is_empty() and not sb.is_empty() and sa.id == sb.id and Items.stack_size(sa.id) > 1:
		var room := Items.stack_size(sa.id) - int(sb.n)
		var put := mini(room, int(sa.n))
		sb.n = int(sb.n) + put
		sa.n = int(sa.n) - put
		if int(sa.n) <= 0:
			slots[a] = {}
		return
	swap(a, b)

# Wears a tool by one use. Returns true when it broke.
func wear(i: int) -> bool:
	var s: Dictionary = slots[i]
	if s.is_empty() or not s.has("d"):
		return false
	s.d = int(s.d) - 1
	if int(s.d) <= 0:
		slots[i] = {}
		return true
	return false

func to_save() -> Array:
	var out := []
	for s in slots:
		out.append(s.duplicate())
	return out

func from_save(data: Array) -> void:
	clear()
	for i in mini(data.size(), SIZE):
		var s = data[i]
		if s is Dictionary and s.has("id") and Items.exists(String(s.id)) and int(s.get("n", 0)) > 0:
			var entry := {"id": String(s.id), "n": mini(int(s.n), Items.stack_size(String(s.id)))}
			if s.has("d"):
				entry["d"] = maxi(1, int(s.d))
			elif Items.info(entry.id).get("kind", "") == "tool":
				entry["d"] = int(Items.info(entry.id).durability)
			slots[i] = entry

# Everything as a flat list of stacks (for keepsake bundles).
func drain() -> Array:
	var out := []
	for i in SIZE:
		if not slots[i].is_empty():
			out.append(slots[i])
			slots[i] = {}
	return out
