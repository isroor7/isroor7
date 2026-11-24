# Claude Opus 5.5 — Build Ola-Naba Craft

You are the lead gameplay engineer and art director. Open this extracted folder as your working project. Read `README.md`, `project.godot`, `src/`, `tests/smoke.gd`, and `assets/ASSET_GUIDE.md` before changing code. Run the supplied Godot project and smoke test as your baseline. Build a playable desktop game in the repository, not a design document, a menu mockup, or a video. Continue from the included vertical slice unless you can demonstrate a concrete technical problem. Preserve its working behavior with tests. Do not delete or silently migrate a user's existing saves.

## Product

**Ola-Naba Craft** is an offline, first-person, 3D voxel-building and survival game for Windows and macOS. Recreate the feel of classic Minecraft-style play: a block snaps precisely into the world grid; mining, building, wandering, gathering, crafting and finding shelter all feel immediate. Use original code, visuals, UI, item designs, enemies, sound, textures and title treatment. Do not import or trace Minecraft textures, skins, menus, wordmark, music, characters, source code or game files. Give the world its own bright, handcrafted identity: warm golden light, muted turquoise shadows, and pink/lilac accents. Do not add a PS5 logo or imply a shipped console version.

## Characters and branding

- **Ola**: navy top, rose-toned hijab, patterned lavender trousers, cyan light accent, from the navy/blue reference. Keep her hijab, outfit and silhouette consistent in menu art, third person and the other player's view.
- **Naba**: dark swept fringe tied at the back, rose clothes and white/rose sneakers; green creative tablet as an optional cosmetic accessory. Redesign any recognizable commercial shirt mark as an original pixel star. Never swap palettes, faces or outfits.
- Keep the distinct chunky character proportions. Add voxel models with head, torso, separate arms/legs and original nearest-filter textures. Animate idle, walk, jump, mining and held-item use. The player sees matching sleeves/hands in first person, not their own face inside the camera.
- Use `assets/logo.svg` and `assets/logo.png` as the game's original mark. Use the included portrait icons and icon SVG. Do not bundle private portrait references in release builds, earn money from those reference photos, or upload them to an external service as part of this task.

## One world, four combinations

| Session | Creative | Survival |
| --- | --- | --- |
| Solo | Play full-screen as either Ola or Naba. | Play full-screen as either Ola or Naba. |
| Local Split Screen | Ola and Naba build simultaneously in one save. | Ola and Naba survive simultaneously in one save. |

- The default split is left/right with optional top/bottom. **One simulation, two cameras, two HUDs, two input assignments and two inventories.** Either player immediately sees the other's edits, actions, picked-up drops and avatar. They can walk in opposite directions and keep playing; no shared camera, controller mirroring or player-2 duplicate overlay. Crosshair and hotbar stay within each viewport at 720p and 1080p. Keep pause semantics explicit: global pause stops both, a local inventory only stops that user's controls.
- Minimum input: keyboard/mouse + controller, two controllers, and shared-keyboard fallback. Use device-scoped events, deadzone, remapping, sensitivity, invert-Y and disconnect/rejoin without stealing the other slot. Build select/join flows usable without a mouse. For one controller in split, default it to P2 unless reassigned. Keep each player's camera and inventory independent.
- **Creative:** unlimited blocks, place/break, block palette, fly/descend, no health/stamina damage. Flight respects solid blocks; no accidental edit from inside UI.
- **Survival:** finite resources, inventory, crafting, durability, health, food, day/night and original simple NPCs. Make the first loop playable: collect timber → craft planks and a basic tool → mine slate → build a shelter → survive the first night. Add legible damage feedback, safe spawn/respawn and a clear path to recovering items. Do not require sign-in, Internet or monetization.

## Implementation order

1. **Stabilize the current starter:** run and retain the smoke test. Verify two controllers, mixed input, independent inventory, both split orientations, avatar visibility, placement collision (no blocks inside either player), and responsive menus. Fix any current blockers before expanding.
2. **Make the voxel world scale:** seeded dirt/stone/trees plus two original biomes, caves and ores. Replace the starter's small GridMap with chunk data and culled-face/greedy mesh design if profiling warrants it. Load the union of both players' active chunks; do not unload chunks in either view. Batch dirty edits at boundaries. Keep meshing/render work within frame budgets and never create a Node per block. Store only changed cells over the deterministic seed. Separate authored lighting and block-vfx palettes from mechanics.
3. **Finish the game loop:** clear tutorial (skip/replay), responsive mining progress, held tool animation, block placement preview, collision, crafting grid with known recipes, stacked inventory, consumables, damage/respawn, original nighttime threats and noncommercial SFX. Keep visual noise low; each cue corresponds to a game action.
4. **Worlds and release:** add named world slots, confirm destructive operations, format version plus compatible migration and fallback backup. Test the same save in solo and split; key player records by avatar/profile rather than array order. If a v1 save cannot be migrated, leave it untouched and offer a clear separate new slot. Add controller-friendly main menu, settings, credits, export config and builds for platforms you actually test. Keep raw refs and editor cache out of build artifacts.

## Acceptance checks

- With a new world, all four session/rules combinations launch. Naba in Solo does not require controller two. Player inputs alone do not move the other player or their camera.
- In Split, P1 removes a block and P2 sees the change. P2 places a block, it persists on reload, and it costs only P2's survival inventory. Concurrent attempts yield one atomic world mutation and never duplicate an item.
- Both slots retain character identity, camera, position, inventory and world edits on save, reopen and device disconnect. Creative flight and infinite stocks do not carry into Survival.
- A Survival tester can complete the full first-night cycle without cheats. Crafting consumes the correct inputs, the hotbar matches inventory, placing cannot trap either avatar, and respawn uses a safe tile.
- Observe real GPU/render tests at 720p and 1080p. Target stable 60 fps on the M4 Max and a typical Windows gaming PC at sensible settings; provide measured frame times or report “not benchmarked.” Run headless regression tests, but do not equate headless tests with actual screen/controller validation.
- Deliver source, setup instructions, controls, assets, tests and a short build/test report. Package desktop executables only where export and launch were verified. Do not claim work is complete if a remaining requirement is not implemented or tested.

Start now by reporting the baseline test result, then implement the working game in this folder. Keep a playable checkpoint after each phase.
