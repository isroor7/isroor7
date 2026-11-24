# Device-scoped input for up to two local players. Each slot owns a keyboard profile ("kb1" left
# side + mouse, or "kb2" right side), optionally the mouse, and optionally one controller.
# A player's state is read only from their own devices, so one player's input never moves the other.
extends RefCounted

const ACTIONS := ["forward", "back", "left", "right", "jump", "down", "mine", "place", "next", "prev",
	"inventory", "use", "pause", "look_left", "look_right", "look_up", "look_down"]
const LABELS := {"forward": "Walk forward", "back": "Walk back", "left": "Walk left", "right": "Walk right",
	"jump": "Jump / fly up / select", "down": "Fly down / back", "mine": "Mine / attack", "place": "Place / use block",
	"next": "Next hotbar slot", "prev": "Previous hotbar slot", "inventory": "Inventory and crafting",
	"use": "Eat / use held item", "pause": "Pause", "look_left": "Look left", "look_right": "Look right",
	"look_up": "Look up", "look_down": "Look down"}
const REMAPPABLE := ["forward", "back", "left", "right", "jump", "down", "mine", "place", "next", "prev", "inventory", "use"]

const DEFAULT_KB1 := {"forward": [KEY_W], "back": [KEY_S], "left": [KEY_A], "right": [KEY_D], "jump": [KEY_SPACE],
	"down": [KEY_SHIFT], "mine": [KEY_Q], "place": [KEY_E], "next": [KEY_R], "prev": [KEY_F], "inventory": [KEY_C, KEY_TAB],
	"use": [KEY_G], "pause": [KEY_ESCAPE]}
const DEFAULT_KB2 := {"forward": [KEY_I], "back": [KEY_K], "left": [KEY_J], "right": [KEY_L], "jump": [KEY_ENTER],
	"down": [KEY_P], "mine": [KEY_COMMA], "place": [KEY_PERIOD], "next": [KEY_SLASH], "prev": [KEY_BACKSLASH],
	"inventory": [KEY_M], "use": [KEY_N], "pause": [KEY_ESCAPE], "look_left": [KEY_LEFT], "look_right": [KEY_RIGHT],
	"look_up": [KEY_UP], "look_down": [KEY_DOWN]}
# Controller buttons; "RT"/"LT" are the analog triggers.
const DEFAULT_PAD := {"jump": [JOY_BUTTON_A], "down": [JOY_BUTTON_B], "mine": [JOY_BUTTON_RIGHT_SHOULDER, "RT"],
	"place": [JOY_BUTTON_LEFT_SHOULDER, "LT"], "next": [JOY_BUTTON_DPAD_RIGHT], "prev": [JOY_BUTTON_DPAD_LEFT],
	"inventory": [JOY_BUTTON_Y], "use": [JOY_BUTTON_X], "pause": [JOY_BUTTON_START]}

class Slot:
	var kb := ""            # "kb1", "kb2" or ""
	var mouse := false
	var pad := -1
	var pad_lost := false   # their controller disconnected; waiting for it (or another free one)
	var lost_device := -1
	var mouse_delta := Vector2.ZERO
	var wheel := 0
	var mouse_buttons := {}  # pressed this frame from events (so clicks shorter than a frame still count)
	var sens_mouse := 1.0
	var sens_stick := 1.0
	var invert_y := false
	var deadzone := 0.2

var slots: Array = []
var bindings := {}   # profile -> action -> Array of codes

func _init() -> void:
	reset_bindings()

func reset_bindings() -> void:
	bindings = {"kb1": DEFAULT_KB1.duplicate(true), "kb2": DEFAULT_KB2.duplicate(true), "pad": DEFAULT_PAD.duplicate(true)}

func apply_settings(settings: Dictionary) -> void:
	var overrides: Dictionary = settings.get("bindings", {})
	for profile in overrides:
		if not bindings.has(profile):
			continue
		for action in overrides[profile]:
			if ACTIONS.has(action):
				var codes := []
				for code in overrides[profile][action]:
					codes.append(code if code is String else int(code))
				bindings[profile][action] = codes
	var per: Array = settings.get("players", [])
	for i in slots.size():
		if i < per.size():
			var p: Dictionary = per[i]
			slots[i].sens_mouse = clampf(float(p.get("sens_mouse", 1.0)), 0.2, 3.0)
			slots[i].sens_stick = clampf(float(p.get("sens_stick", 1.0)), 0.2, 3.0)
			slots[i].invert_y = bool(p.get("invert_y", false))
			slots[i].deadzone = clampf(float(p.get("deadzone", 0.2)), 0.05, 0.6)

# Default device assignment for a session. One controller in split screen goes to player 2.
func assign(count: int, pads: Array = Input.get_connected_joypads()) -> void:
	slots.clear()
	for i in count:
		slots.append(Slot.new())
	slots[0].kb = "kb1"
	slots[0].mouse = true
	if count == 1:
		if not pads.is_empty():
			slots[0].pad = pads[0]
	else:
		slots[1].kb = "kb2"
		if pads.size() == 1:
			slots[1].pad = pads[0]
		elif pads.size() >= 2:
			slots[0].pad = pads[0]
			slots[1].pad = pads[1]

func owner_of_pad(device: int) -> int:
	for i in slots.size():
		if slots[i].pad == device:
			return i
	return -1

# A controller button from a device nobody owns: give it to a slot waiting for one.
# Never takes a controller from the other player.
func offer_pad(device: int) -> int:
	if owner_of_pad(device) >= 0:
		return -1
	for i in slots.size():
		if slots[i].pad_lost:
			_give(i, device)
			return i
	# player 1 already has the keyboard and mouse, so a free controller goes to player 2 first
	for i in range(slots.size() - 1, -1, -1):
		if slots[i].pad < 0:
			_give(i, device)
			return i
	return -1

func _give(i: int, device: int) -> void:
	slots[i].pad = device
	slots[i].pad_lost = false
	slots[i].lost_device = -1

func swap_pads() -> void:
	if slots.size() == 2:
		var t: int = slots[0].pad
		slots[0].pad = slots[1].pad
		slots[1].pad = t

func on_connection(device: int, connected: bool) -> void:
	if connected:
		for i in slots.size():
			if slots[i].pad_lost and slots[i].lost_device == device:
				_give(i, device)
				return
	else:
		for i in slots.size():
			if slots[i].pad == device:
				slots[i].pad = -1
				slots[i].pad_lost = true
				slots[i].lost_device = device

func feed_event(event: InputEvent) -> void:
	for s in slots:
		if not s.mouse:
			continue
		if event is InputEventMouseMotion:
			s.mouse_delta += event.relative
		elif event is InputEventMouseButton and event.pressed:
			match event.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					s.wheel -= 1
				MOUSE_BUTTON_WHEEL_DOWN:
					s.wheel += 1
				MOUSE_BUTTON_LEFT:
					s.mouse_buttons["mine"] = true
				MOUSE_BUTTON_RIGHT:
					s.mouse_buttons["place"] = true

func _deadzone(v: Vector2, dz: float) -> Vector2:
	var l := v.length()
	if l < dz:
		return Vector2.ZERO
	return v / l * minf(1.0, (l - dz) / (1.0 - dz))

func _code_held(profile: String, code, pad: int) -> bool:
	if profile == "pad":
		if pad < 0:
			return false
		if code is String:
			var axis := JOY_AXIS_TRIGGER_RIGHT if code == "RT" else JOY_AXIS_TRIGGER_LEFT
			return Input.get_joy_axis(pad, axis) > 0.5
		return Input.is_joy_button_pressed(pad, int(code))
	return Input.is_physical_key_pressed(int(code))

# Reads one player's devices. Returns {held: {action: bool}, move: Vector2, look: Vector2,
# wheel: int, nav: Vector2i (menu navigation: d-pad, stick, movement keys)}.
func read(i: int, delta: float) -> Dictionary:
	var held := {}
	for a in ACTIONS:
		held[a] = false
	if i < 0 or i >= slots.size():
		return {"held": held, "move": Vector2.ZERO, "look": Vector2.ZERO, "wheel": 0, "nav": Vector2i.ZERO}
	var s: Slot = slots[i]
	if s.kb != "":
		var map: Dictionary = bindings[s.kb]
		for a in map:
			for code in map[a]:
				if _code_held(s.kb, code, -1):
					held[a] = true
	if s.pad >= 0:
		var map: Dictionary = bindings.pad
		for a in map:
			for code in map[a]:
				if _code_held("pad", code, s.pad):
					held[a] = true
	if s.mouse:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or s.mouse_buttons.has("mine"):
			held.mine = true
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or s.mouse_buttons.has("place"):
			held.place = true
		s.mouse_buttons.clear()
	var move := Vector2(float(held.right) - float(held.left), float(held.back) - float(held.forward))
	var look := Vector2(float(held.look_right) - float(held.look_left), float(held.look_down) - float(held.look_up)) * 2.4 * delta * s.sens_stick
	var nav := Vector2i(int(held.right) - int(held.left), int(held.back) - int(held.forward))
	if s.pad >= 0:
		var stick := _deadzone(Vector2(Input.get_joy_axis(s.pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(s.pad, JOY_AXIS_LEFT_Y)), s.deadzone)
		move += stick
		var rs := _deadzone(Vector2(Input.get_joy_axis(s.pad, JOY_AXIS_RIGHT_X), Input.get_joy_axis(s.pad, JOY_AXIS_RIGHT_Y)), s.deadzone)
		look += rs * rs.length() * 3.2 * delta * s.sens_stick
		var dpad := Vector2i(int(Input.is_joy_button_pressed(s.pad, JOY_BUTTON_DPAD_RIGHT)) - int(Input.is_joy_button_pressed(s.pad, JOY_BUTTON_DPAD_LEFT)),
			int(Input.is_joy_button_pressed(s.pad, JOY_BUTTON_DPAD_DOWN)) - int(Input.is_joy_button_pressed(s.pad, JOY_BUTTON_DPAD_UP)))
		if stick.length() > 0.6:
			dpad += Vector2i(roundi(stick.normalized().x), roundi(stick.normalized().y))
		nav = Vector2i(clampi(nav.x + dpad.x, -1, 1), clampi(nav.y + dpad.y, -1, 1))
	if s.mouse:
		look += s.mouse_delta * 0.0028 * s.sens_mouse
		s.mouse_delta = Vector2.ZERO
	if s.invert_y:
		look.y = -look.y
	var wheel := s.wheel
	s.wheel = 0
	return {"held": held, "move": move.limit_length(1.0), "look": look, "wheel": wheel, "nav": nav}

# Human-readable name of the first binding for an action on a player's main device.
func glyph(i: int, action: String, keys_only := false) -> String:
	if i < 0 or i >= slots.size():
		return action
	var s: Slot = slots[i]
	if s.pad >= 0 and bindings.pad.has(action):
		return pad_name(bindings.pad[action][0])
	if s.kb != "" and bindings[s.kb].has(action):
		if s.mouse and action == "mine" and not keys_only:
			return "Left click"
		if s.mouse and action == "place" and not keys_only:
			return "Right click"
		return OS.get_keycode_string(int(bindings[s.kb][action][0]))
	return action

static func pad_name(code) -> String:
	if code is String:
		return code
	match int(code):
		JOY_BUTTON_A: return "A / Cross"
		JOY_BUTTON_B: return "B / Circle"
		JOY_BUTTON_X: return "X / Square"
		JOY_BUTTON_Y: return "Y / Triangle"
		JOY_BUTTON_LEFT_SHOULDER: return "LB / L1"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB / R1"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_BACK: return "Back"
		JOY_BUTTON_DPAD_LEFT: return "D-pad left"
		JOY_BUTTON_DPAD_RIGHT: return "D-pad right"
		JOY_BUTTON_DPAD_UP: return "D-pad up"
		JOY_BUTTON_DPAD_DOWN: return "D-pad down"
		JOY_BUTTON_LEFT_STICK: return "L3"
		JOY_BUTTON_RIGHT_STICK: return "R3"
	return "Button %d" % int(code)

func device_label(i: int) -> String:
	if i < 0 or i >= slots.size():
		return ""
	var s: Slot = slots[i]
	var parts := []
	if s.kb == "kb1":
		parts.append("Keyboard left + mouse" if s.mouse else "Keyboard left")
	elif s.kb == "kb2":
		parts.append("Keyboard right")
	if s.pad >= 0:
		parts.append("Controller %d (%s)" % [s.pad + 1, Input.get_joy_name(s.pad)])
	if s.pad_lost:
		parts.append("controller disconnected")
	return " + ".join(parts)
