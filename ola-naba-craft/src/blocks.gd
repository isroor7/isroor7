# Block registry. Plain arrays so worker threads can read them without locks.
extends RefCounted

const AIR := 0
const MOSS := 1
const SOIL := 2
const SLATE := 3
const TIMBER := 4
const CANOPY := 5
const PLANKS := 6
const GLOWGLASS := 7
const SAND := 8
const WATER := 9
const BLOSSOM := 10
const EMBER_ORE := 11
const SUNMETAL_ORE := 12
const SLATE_BRICK := 13
const LANTERN := 14
const WORKBENCH := 15
const BEDROLL := 16
const DEEPSTONE := 17
const SANDSTONE := 18
const LILAC_MOSS := 19
const COUNT := 20

# Stable string keys. Saves and item stacks use these, never the numeric ids.
const KEYS := ["air", "moss", "soil", "slate", "timber", "canopy", "planks", "glowglass", "sand", "water",
	"blossom", "ember_ore", "sunmetal_ore", "slate_brick", "lantern", "workbench", "bedroll", "deepstone",
	"sandstone", "lilac_moss"]
const NAMES := ["Air", "Moss Turf", "Soil", "Slate", "Timber", "Canopy", "Planks", "Glowglass", "Dune Sand", "Water",
	"Blossom Canopy", "Ember Ore", "Sunmetal Ore", "Slate Bricks", "Ember Lantern", "Workbench", "Moss Bedroll",
	"Deepstone", "Sandstone", "Lilac Moss"]

# Collides with players and mobs.
const SOLID := [false, true, true, true, true, true, true, true, true, false,
	true, true, true, true, true, true, true, true, true, true]
# Hides the neighbour's face and darkens ambient occlusion.
const OPAQUE := [false, true, true, true, true, true, true, false, true, false,
	true, true, true, true, true, true, true, true, true, true]
# Drawn in the blended pass.
const TRANSLUCENT := [false, false, false, false, false, false, false, true, false, true,
	false, false, false, false, false, false, false, false, false, false]
# Stops sunlight for everything below it (leaves let light through).
const SKY_STOP := [false, true, true, true, true, false, true, false, true, false,
	false, true, true, true, true, true, true, true, true, true]
# Block light emitted (0-9). Light falls off one level per block.
const EMIT := [0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0]
const MAX_LIGHT := 9

# Seconds to break with the right tool at tier 1 speed. -1 means it cannot be mined.
const HARDNESS := [-1.0, 0.75, 0.6, 2.2, 2.0, 0.35, 1.6, 0.6, 0.6, -1.0,
	0.35, 2.8, 3.6, 2.6, 0.4, 1.6, 0.5, -1.0, 1.8, 0.75]
# Tool family that mines it quickly: "" none, "pick", "axe", "spade".
const TOOL := ["", "spade", "spade", "pick", "axe", "", "axe", "", "spade", "",
	"", "pick", "pick", "pick", "", "axe", "", "", "pick", "spade"]
# Minimum pick tier needed for a drop (0 = bare hands ok).
const MIN_TIER := [0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 2, 1, 0, 0, 0, 99, 1, 0]

# Texture layers for [top, side, bottom]; indices into Textures.LAYERS.
const TEX := [
	[0, 0, 0], [0, 1, 2], [2, 2, 2], [3, 3, 3], [5, 4, 5], [6, 6, 6], [7, 7, 7], [8, 8, 8], [9, 9, 9], [10, 10, 10],
	[11, 11, 11], [12, 12, 12], [13, 13, 13], [14, 14, 14], [15, 15, 15], [16, 17, 7], [18, 19, 7], [20, 20, 20],
	[22, 21, 22], [23, 24, 2],
]

# Sound family for dig/place feedback.
const SOUND := ["", "soft", "soft", "stone", "wood", "leaf", "wood", "glass", "sand", "",
	"leaf", "stone", "stone", "stone", "glass", "wood", "soft", "stone", "stone", "soft"]

static func key_to_id(key: String) -> int:
	return KEYS.find(key)

# Items dropped when the block is mined: Array of [item_key, count, chance].
static func drops(id: int) -> Array:
	match id:
		CANOPY, BLOSSOM:
			return [["berries", 1, 0.32], ["stick", 1, 0.28]]
		EMBER_ORE:
			return [["ember", 1, 1.0]]
		SUNMETAL_ORE:
			return [["sunmetal", 1, 1.0]]
		WATER, AIR, DEEPSTONE:
			return []
	return [[KEYS[id], 1, 1.0]]
