# Build and test report

Environment: Godot 4.7.2 (official), Ubuntu 24.04 container, 4 CPU cores, **no GPU**, no physical
controllers, no Windows or macOS machine. Rendering checks used Mesa llvmpipe (software OpenGL) on
a virtual X display.

## Baseline (the supplied starter)

`tests/smoke.gd` on the unmodified starter: **SMOKE: PASS (0 failures)**.

## Automated tests (current code)

| Suite | Result | What it covers |
| --- | --- | --- |
| `tests/smoke.gd` | **PASS** (0 failures) | The starter's checks carried to the new code: two viewports and HUDs, shared world, separate cameras, landing, mine → pickup, place → stock decrement, P1/P2 stock isolation, crafting, eating, save + backup, continue restores layout/stock/edits, pause locks both, solo Creative Naba, stacked split, P2 key moves only P2, solo Survival Ola |
| `tests/acceptance.gd` | **PASS** (131 checks, 0 failures) | All six solo/split × Creative/Survival launches; keyboard, mouse, arrow-key and controller input each move or turn only their own player; stick deadzone; P1 breaks → P2 sees it; P2 places → costs only P2 and survives reload; simultaneous break/place on one cell → one mutation, one drop, one payer; identity, camera, position and stock kept per avatar across solo/split reloads; controller assignment, disconnect, rejoin, no stealing; Creative stock/flight never reach Survival; placing into either player or a creature is refused; faint → keepsake bundle → safe respawn → bundle recovered; exact crafting consumption, bench rules, no half-crafts; local inventory pauses only its owner and blocks edits; remapped keys and invert-Y; flight collides with walls; both players' views stay loaded 260 blocks apart; damaged save → backup, newer format refused untouched, rename/delete; a **real starter v1 save** imports into a new slot with the island rebuilt cell for cell and the v1 file byte-identical afterwards, and an unreadable v1 file is left untouched |
| `tests/first_night.gd` | **PASS**, 3 of 3 consecutive runs | Survival through the real controls: hold Mine on a tree (2.0 s by hand) → timber picked up → 2 timber → 8 planks → 4 sticks → wood pick (exactly 3 planks + 2 sticks consumed) → dig to slate with the pick → roof the pit → night (sped up 6×): Gloomlings spawn, Ola stays at 20/20 health in the shelter, Naba outside faints → day 2 → Gloomlings gone, tutorial complete |

The first-night script places the player beside the tree and next to dropped items instead of
steering a walk there, and sets the clock to dusk; every game action goes through held/pressed
input with the game's real rules. Creature spawning is seeded in that run so it is repeatable.

Headless tests check logic. They are **not** a substitute for playing on a real screen with real
controllers.

## Visual checks (software rendering)

Rendered and inspected: title screen; split screen side by side at 1280×720 (each player's camera,
HUD, hotbar, hearts, food and tutorial inside their own half); top/bottom split at 1920×1080;
Crafting screen in one player's pane while the other keeps playing; night lighting; creatures at night
with lantern and glowglass light; Ola and Naba from front and back, walking and holding items;
pause menu; exported Linux build's title screen and gameplay.

## Builds

| Platform | Export | Launch check | Notes |
| --- | --- | --- | --- |
| Linux x86_64 | ✓ 74 MB, single file | **✓** `--self-test` PASS at 1280×720 and 1920×1080 (Xvfb, llvmpipe) | Not a target platform; used to prove the export path end to end |
| Windows x86_64 | ✓ 110 MB `.exe`, data embedded | **Not verified** | Wine 9.0 aborted before the game started in this container (`free(): invalid pointer`); no Windows machine available |
| macOS universal (Intel + Apple silicon) | ✓ 61 MB `.zip`, ad-hoc signed `.app` | **Not verified** | No Mac available; not notarized (right-click → Open the first time) |

Each build was scanned for the private reference images and test files: none are included. Build
outputs are not committed (`build/` is git-ignored). Because Windows and macOS launches were not
verified, those builds are not presented as packaged releases; export them with the commands in
the README and confirm each with `-- --self-test` on the target machine.

## Performance

**Real GPUs: not benchmarked.** No M4 Max or Windows gaming PC was available, so the 60 fps target
at 720p/1080p is unconfirmed. To measure on real hardware: press **F3** in game for a live
frame-time overlay, or run `tools/benchmark.gd` (solo and split, prints average / 95th percentile /
worst frame times and writes `user://benchmark.txt`), or run a build with `-- --self-test`.

Numbers from this container, for orientation only (CPU software rasterizer, not representative of
any GPU):

| Measurement | Value |
| --- | --- |
| Chunk mesh job (worker thread, GDScript) | about 15 ms average |
| Initial load, 193 chunks at view distance 6 | about 3.8 s |
| Split screen 1280×720, llvmpipe | 70 to 130 ms per frame |
| Self-test, exported Linux build, llvmpipe | 71 ms avg (720p), 76 ms avg (1080p) |

Design choices for frame budget: generation and meshing run on the WorkerThreadPool; the main thread
only uploads finished meshes within a 5 ms budget per frame; culled faces only, no node per block;
edits in one frame are batched into one remesh per chunk; one shared material for all terrain.
Greedy meshing was not added because it could not be profiled on real GPUs here.

## Acceptance checklist

| Requirement | Status |
| --- | --- |
| Four session/rule combinations launch; Naba solo needs no second controller | Done, tested |
| Player input never moves the other player or camera | Done, tested (keyboard, mouse, arrows, simulated controller) |
| P1 edit visible to P2; P2 placement persists and costs only P2 | Done, tested |
| Concurrent attempts → one mutation, no duplicated items | Done, tested |
| Identity, camera, position, inventory, edits kept on save, reopen, disconnect | Done, tested (disconnect via simulated events) |
| Creative flight/stock never carry into Survival | Done, tested |
| First-night Survival loop without cheats | Done, tested by script; not yet played by a human tester on hardware |
| Crafting consumes correct inputs; hotbar matches inventory | Done, tested |
| Placing never traps an avatar; safe respawn | Done, tested |
| Real GPU tests at 720p/1080p, 60 fps | **Not benchmarked** (tools provided) |
| Real controller validation (two pads, hot-plug) | **Not done** (logic tested with simulated input events) |
| Windows and macOS executables launch-verified | **Not done** (exported only) |

## Changes from the brief

- Third-person cameras for both players (requested by the user, replacing first-person hands and
  sleeves). Your own avatar hides from your camera only when the camera is squeezed against your head.

## Known limitations

- Water does not flow; there are no doors; the day is 10 minutes (about 3 minutes of night).
- Creatures are not saved; night spawning recreates them.
- Puffkins cannot be harmed (they hop away), by design.
- Typing a world name or seed needs a keyboard; the defaults let controller players skip it.
- Rules are fixed per world (a Creative world stays Creative).
- Sound effects only; no music. Split-screen 3D sound uses Godot's default per-viewport listeners.
- The game shares Godot's user-data folder name with the starter ("Ola-Naba Craft") so that starter
  saves can be found and imported; the v1 files are only ever read.
