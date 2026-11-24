# Asset guide

## Files in this folder

- `logo.svg` / `logo.png`: the game's original mark (vector and 1800×540 PNG), used on the title screen.
- `icon.svg`: the app icon (twin-colour isometric block).
- `ola.svg` / `naba.svg`: original character badges, used on the title screen.
- `references/Ola-navy.jpeg`, `references/Naba-pink.jpeg`: **private** pixel-art references for the two
  characters. They are ignored by Godot (`.gdignore`), by git (`.gitignore`) and by every export preset
  (`exclude_filter`). Never ship them, publish them, earn money from them, or upload them anywhere.

## Art made in code

Everything else the game shows is drawn by its own code at startup, in an original palette of warm
golden light, muted turquoise shadows and pink/lilac accents:

- Block textures (16×16, nearest-filtered): `src/textures.gd`, one painter per texture layer.
- Item icons (blocks drawn as isometric cubes, tools, food and materials): `src/textures.gd`.
- Ola and Naba skins (64×64 box-unwrap atlases) and their voxel bodies: `src/avatar.gd`.
  - Ola: rose hijab with a drape over the shoulders, navy long-sleeved top with a glowing cyan cuff,
    lavender trousers with a cream cross pattern, mauve shoes.
  - Naba: dark swept fringe with a rose-tied ponytail, gold earrings, rose and white T-shirt with an
    **original pixel star** (no commercial shirt marks), pink shorts, white and rose sneakers, a bead
    bracelet and an optional green creative tablet (Settings → Video).
- Creatures (Gloomling, Puffkin), keepsake bundle and held/dropped items: `src/mobs.gd`, `src/drops.gd`.
- Sound effects: synthesized from noise and tones in `src/audio.gd` (no recordings, no samples).

To change a texture or a character's look, edit the painter function and run the game; there is no
separate asset pipeline to update.
