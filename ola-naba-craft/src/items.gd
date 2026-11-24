# Items, tools, food and crafting recipes. Item keys are stable strings used by saves.
extends RefCounted

const B := preload("res://src/blocks.gd")

const EXTRA := {
	"stick": {"name": "Stick", "kind": "material"},
	"berries": {"name": "Canopy Berries", "kind": "food", "food": 4},
	"ember": {"name": "Ember", "kind": "material"},
	"sunmetal": {"name": "Sunmetal", "kind": "material"},
	"wood_pick": {"name": "Wood Pick", "kind": "tool", "tool": "pick", "tier": 1, "durability": 60, "speed": 2.2, "damage": 2},
	"wood_axe": {"name": "Wood Hatchet", "kind": "tool", "tool": "axe", "tier": 1, "durability": 60, "speed": 2.2, "damage": 3},
	"wood_spade": {"name": "Wood Spade", "kind": "tool", "tool": "spade", "tier": 1, "durability": 60, "speed": 2.2, "damage": 1},
	"wood_blade": {"name": "Wood Blade", "kind": "tool", "tool": "blade", "tier": 1, "durability": 60, "speed": 1.0, "damage": 4},
	"slate_pick": {"name": "Slate Pick", "kind": "tool", "tool": "pick", "tier": 2, "durability": 140, "speed": 3.6, "damage": 3},
	"slate_axe": {"name": "Slate Hatchet", "kind": "tool", "tool": "axe", "tier": 2, "durability": 140, "speed": 3.6, "damage": 4},
	"slate_spade": {"name": "Slate Spade", "kind": "tool", "tool": "spade", "tier": 2, "durability": 140, "speed": 3.6, "damage": 2},
	"slate_blade": {"name": "Slate Blade", "kind": "tool", "tool": "blade", "tier": 2, "durability": 140, "speed": 1.0, "damage": 5},
	"sun_pick": {"name": "Sunmetal Pick", "kind": "tool", "tool": "pick", "tier": 3, "durability": 320, "speed": 6.0, "damage": 4},
	"sun_blade": {"name": "Sunmetal Blade", "kind": "tool", "tool": "blade", "tier": 3, "durability": 320, "speed": 1.0, "damage": 7},
}

# station: "hand" works anywhere, "bench" needs a Workbench within reach.
# pattern is the 3x3 picture shown in the crafting grid (keys in `legend`).
const RECIPES := [
	{"id": "planks", "out": "planks", "n": 4, "needs": {"timber": 1}, "station": "hand",
		"pattern": ["   ", " T ", "   "], "legend": {"T": "timber"}},
	{"id": "stick", "out": "stick", "n": 4, "needs": {"planks": 2}, "station": "hand",
		"pattern": [" P ", " P ", "   "], "legend": {"P": "planks"}},
	{"id": "workbench", "out": "workbench", "n": 1, "needs": {"planks": 4}, "station": "hand",
		"pattern": ["PP ", "PP ", "   "], "legend": {"P": "planks"}},
	{"id": "wood_pick", "out": "wood_pick", "n": 1, "needs": {"planks": 3, "stick": 2}, "station": "hand",
		"pattern": ["PPP", " S ", " S "], "legend": {"P": "planks", "S": "stick"}},
	{"id": "wood_axe", "out": "wood_axe", "n": 1, "needs": {"planks": 3, "stick": 2}, "station": "hand",
		"pattern": ["PP ", "PS ", " S "], "legend": {"P": "planks", "S": "stick"}},
	{"id": "wood_spade", "out": "wood_spade", "n": 1, "needs": {"planks": 1, "stick": 2}, "station": "hand",
		"pattern": [" P ", " S ", " S "], "legend": {"P": "planks", "S": "stick"}},
	{"id": "wood_blade", "out": "wood_blade", "n": 1, "needs": {"planks": 2, "stick": 1}, "station": "hand",
		"pattern": [" P ", " P ", " S "], "legend": {"P": "planks", "S": "stick"}},
	{"id": "lantern", "out": "lantern", "n": 4, "needs": {"ember": 1, "stick": 1}, "station": "hand",
		"pattern": [" E ", " S ", "   "], "legend": {"E": "ember", "S": "stick"}},
	{"id": "bedroll", "out": "bedroll", "n": 1, "needs": {"planks": 3, "moss": 3}, "station": "hand",
		"pattern": ["MMM", "PPP", "   "], "legend": {"M": "moss", "P": "planks"}},
	{"id": "slate_pick", "out": "slate_pick", "n": 1, "needs": {"slate": 3, "stick": 2}, "station": "bench",
		"pattern": ["LLL", " S ", " S "], "legend": {"L": "slate", "S": "stick"}},
	{"id": "slate_axe", "out": "slate_axe", "n": 1, "needs": {"slate": 3, "stick": 2}, "station": "bench",
		"pattern": ["LL ", "LS ", " S "], "legend": {"L": "slate", "S": "stick"}},
	{"id": "slate_spade", "out": "slate_spade", "n": 1, "needs": {"slate": 1, "stick": 2}, "station": "bench",
		"pattern": [" L ", " S ", " S "], "legend": {"L": "slate", "S": "stick"}},
	{"id": "slate_blade", "out": "slate_blade", "n": 1, "needs": {"slate": 2, "stick": 1}, "station": "bench",
		"pattern": [" L ", " L ", " S "], "legend": {"L": "slate", "S": "stick"}},
	{"id": "slate_brick", "out": "slate_brick", "n": 4, "needs": {"slate": 4}, "station": "bench",
		"pattern": ["LL ", "LL ", "   "], "legend": {"L": "slate"}},
	{"id": "glowglass", "out": "glowglass", "n": 2, "needs": {"sand": 2, "ember": 1}, "station": "bench",
		"pattern": [" E ", "DD ", "   "], "legend": {"E": "ember", "D": "sand"}},
	{"id": "sandstone", "out": "sandstone", "n": 2, "needs": {"sand": 4}, "station": "bench",
		"pattern": ["DD ", "DD ", "   "], "legend": {"D": "sand"}},
	{"id": "sun_pick", "out": "sun_pick", "n": 1, "needs": {"sunmetal": 3, "stick": 2}, "station": "bench",
		"pattern": ["UUU", " S ", " S "], "legend": {"U": "sunmetal", "S": "stick"}},
	{"id": "sun_blade", "out": "sun_blade", "n": 1, "needs": {"sunmetal": 2, "stick": 1}, "station": "bench",
		"pattern": [" U ", " U ", " S "], "legend": {"U": "sunmetal", "S": "stick"}},
]

# Blocks a creative palette offers (everything buildable).
const PALETTE := ["moss", "lilac_moss", "soil", "sand", "sandstone", "slate", "slate_brick", "timber", "planks",
	"canopy", "blossom", "glowglass", "lantern", "workbench", "bedroll", "ember_ore", "sunmetal_ore"]

static func info(key: String) -> Dictionary:
	if EXTRA.has(key):
		return EXTRA[key]
	var id := B.key_to_id(key)
	if id > 0 and id != B.WATER:
		return {"name": B.NAMES[id], "kind": "block", "block": id}
	return {}

static func exists(key: String) -> bool:
	return not info(key).is_empty()

static func display_name(key: String) -> String:
	return info(key).get("name", key)

static func stack_size(key: String) -> int:
	return 1 if info(key).get("kind", "") == "tool" else 64

static func block_of(key: String) -> int:
	var i := info(key)
	return int(i.block) if i.get("kind", "") == "block" else -1

static func recipe(id: String) -> Dictionary:
	for r in RECIPES:
		if r.id == id:
			return r
	return {}
