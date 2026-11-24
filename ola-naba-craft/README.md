# Ola-Naba Craft | Godot Starter + Opus handoff

This is a playable desktop starter, not a finished Minecraft-equivalent. Unzip the folder first. For Opus: open this folder and give it **OPUS_PROMPT.md**. For a quick local run: open **project.godot** in Godot 4 (tested with 4.7.2) and press **F5**. The project has no add-on or network dependency. CLI after initial import:

```shell
godot --headless --editor --path . --import --quit
godot --path .
godot --headless --path . --script tests/smoke.gd
```

## Play the starter

Pick Solo as Ola, Solo as Naba, or local two-player. Choose Creative or Survival. In two-player, choose side-by-side or top/bottom. Both use one terrain; each has their own camera, selected block and stock.

| Action | Player 1 | Player 2 | Controller |
| --- | --- | --- | --- |
| Walk | WASD | IJKL | Left stick |
| Look | Mouse | Arrows | Right stick |
| Jump / fly up | Space | Enter | A / Cross |
| Fly down | Shift | P | B / Circle |
| Mine | Left click or Q | Comma | RB / R1 |
| Place | Right click or E | Period | LB / L1 |
| Next / previous block | Wheel or R/F | Slash / backslash | D-pad right / left |
| Craft 4 planks from 1 timber | T | M | Y / Triangle |
| Eat canopy berries to recover stamina | G | N | X / Square |
| Pause / save and exit | Esc | Esc | Start |

One connected pad goes to P2 in split-screen and P1 in solo. Two pads are assigned in connection order. In Creative every block is available and flying is enabled. In Survival mine Timber from a tree trunk for planks; a Canopy block can be consumed for +2 stamina. The prototype has a day/night cycle, stamina and respawn, but no mobs or full crafting interface yet.

**Save:** one local world slot with rolling backup. Esc → Save & Return, or autosave every 30 seconds. Continuing restores the saved team layout, mode, positions, inventories and block edits. New World warns before replacing the active slot when saved. Back up your save before experimenting with format changes.

## Included / not included

- Small seeded 3D terrain, seven block types, raycast mining/placement, co-op, starter rules for both modes, persistent edits and per-player state.
- Original logo (SVG and PNG), app icon, two portraits, two original simple voxel avatars; private refs excluded from runtime import. See `assets/ASSET_GUIDE.md`.
- Headless tests for dual cameras, shared world, raycast mine/place, stock isolation, crafting, stamina restoration, saving/loading and solo setup.
- No EXE, .app, console or mobile builds, online multiplayer, endless chunks, full crafting tree, mobs or production sound. The Opus brief details what to implement and verify next. No real controller or GPU performance data is asserted.
