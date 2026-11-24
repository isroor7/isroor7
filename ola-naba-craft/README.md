# Ola-Naba Craft

An offline, third-person voxel building and survival game for one or two players on one computer,
made with Godot 4. Play as **Ola** or **Naba**, alone in full screen or together in split screen,
in **Creative** (unlimited blocks, flight, no damage) or **Survival** (gather, craft, eat, build a
shelter and get through the night).

Everything in the game is original: code, pixel textures, characters, creatures, sounds, menus.
No sign-in, no internet, no purchases.

## Run it

1. Install [Godot 4.7.2](https://godotengine.org/download) (the project is tested with 4.7.2).
2. Open `project.godot` in Godot and press **F5**, or from a terminal:

```shell
godot --headless --editor --path . --import --quit   # first time only: import assets
godot --path .                                        # play
```

The game uses Godot's Compatibility renderer (OpenGL 3.3), so it runs on most GPUs, including
Apple silicon Macs and Windows gaming PCs.

## Play

**Title → Play → New world**: pick a name, Survival or Creative, and a seed (the same seed always
grows the same world). Open a world to choose how to play it:

| | Creative | Survival |
| --- | --- | --- |
| **Solo** | *Play as Ola* or *Play as Naba*, full screen | same |
| **Together** | *Play together · side by side* or *top and bottom* | same |

Both players share one world: each sees the other's building, digging, pickups and avatar
straight away, and has their own camera, HUD, hotbar, inventory and controls.

**Your first Survival day** (the in-game tutorial walks you through it; skip or replay it from the
pause menu):

1. Hold **Mine** on a tree trunk to collect Timber.
2. Open **Inventory** → **Crafting**: Timber → Planks, Planks → Sticks, then a **Wood Pick**.
3. Dig down to the grey **Slate** and mine it with the pick.
4. Before dusk, build walls and a roof. Lanterns (Ember + Stick) keep **Gloomlings** away.
5. Survive the night. Canopy Berries (from leaves) fill you up. A **Moss Bedroll** sets your
   respawn point and lets you sleep through the night.

If you faint, your things stay in a glowing **keepsake bundle** where you fell; a compass on your
HUD points back to it. You wake at your bedroll or the world spawn on a safe, dry spot.

## Controls

| Action | Player 1 | Player 2 (shared keyboard) | Controller |
| --- | --- | --- | --- |
| Walk | W A S D | I J K L | Left stick |
| Look | Mouse | Arrow keys | Right stick |
| Jump / swim / fly up | Space | Enter | A / Cross |
| Fly down, back out of menus | Shift | P | B / Circle |
| Mine / attack (hold) | Left click or Q | , | RB / R1 or RT |
| Place block / use workbench or bedroll | Right click or E | . | LB / L1 or LT |
| Hotbar next / previous | Wheel, R / F | / and \ | D-pad right / left |
| Inventory and crafting | C or Tab | M | Y / Triangle |
| Eat held food | G | N | X / Square |
| Pause (both players) | Esc | Esc | Start |
| Creative: fly | Double-tap jump | Double-tap jump | Double-tap A |
| Frame-time overlay | F3 | | |

Keys and controller buttons can be remapped in **Settings → Keys**. Each player has their own
look sensitivity, stick deadzone and invert-Y in **Settings → Player 1 / Player 2**.

**Who controls whom.** Solo: keyboard, mouse and the first controller all drive the one player.
Split screen: player 1 (Ola) has the left keyboard and the mouse; player 2 (Naba) has the right
keyboard. One controller goes to player 2; two controllers go to players 1 and 2 in connection
order. Before a split session starts, the *Who plays with what?* screen shows the assignment, lets
you swap controllers, and gives a free controller to a player when you press any button on it. If a
controller disconnects, only its player sees a notice and can keep using the keyboard; plugging it
back in (or pressing a button on any free controller) rejoins without taking the other player's.

**Pausing.** *Pause* stops the whole game for both players. Opening your own inventory only stops
you; the world and the other player keep going.

## Worlds and saves

Worlds live in Godot's user data folder:

- Windows: `%APPDATA%\Godot\app_userdata\Ola-Naba Craft\worlds\`
- macOS: `~/Library/Application Support/Godot/app_userdata/Ola-Naba Craft/worlds/`
- Linux: `~/.local/share/godot/app_userdata/Ola-Naba Craft/worlds/`

Each world is a folder with `world.json` (format version 2), `world.backup.json` (the previous
good save) and `meta.json`. Saves are written to a temporary file first and the old save is copied
to the backup before it is replaced; a damaged save opens from its backup. A save from a newer
version is refused and left untouched. Only the blocks you changed are stored; the rest regrows from
the seed. Player records are kept per character (`ola`, `naba`), so the same world works solo and in
split screen. The game autosaves every minute and when the window closes.

**Saves from the starter version** (`world-v1.json`) are never changed. The world list offers
*Import starter world*, which copies it into a new slot: the starter's island is rebuilt block for
block at the same spot, and both players' stock, health and stamina carry over. A starter save that
cannot be read is left alone and you can start a new world instead.

## Build the game

Export presets for **Windows**, **macOS** (universal, ad-hoc signed) and **Linux** are in
`export_presets.cfg`. Install the matching export templates (Editor → Manage Export Templates), then:

```shell
godot --headless --path . --export-release "Windows Desktop" build/windows/OlaNabaCraft.exe
godot --headless --path . --export-release "macOS" build/macos/OlaNabaCraft.zip
godot --headless --path . --export-release "Linux" build/linux/OlaNabaCraft.x86_64
```

Builds leave out `assets/references/`, `tests/`, `tools/` and docs. Check a build on the machine it
is for with its built-in self-test, which plays a throwaway world for a few seconds (kept apart from
your saves) and prints frame times:

```shell
OlaNabaCraft.exe -- --self-test                                          # Windows
"Ola-Naba Craft.app/Contents/MacOS/Ola-Naba Craft" -- --self-test       # macOS
```

The macOS build is ad-hoc signed, not notarized: the first time, right-click the app and choose
*Open*. Windows may show a SmartScreen prompt for an unsigned game.

## Tests and tools

```shell
godot --headless --path . --script tests/smoke.gd          # the starter's checks, carried forward
godot --headless --path . --script tests/acceptance.gd     # 131 checks against the brief
godot --headless --path . --script tests/first_night.gd    # scripted Survival first night
godot --path . --resolution 1920x1080 --script tools/benchmark.gd   # frame times on real hardware
```

Or run `tests/run_all.sh`. Headless tests check game logic; they do not replace playing on a real
screen with real controllers. See `BUILD_AND_TEST_REPORT.md` for what was and was not verified.

## Project layout

| Path | What it is |
| --- | --- |
| `src/game.gd` | sessions, split-screen panes, pause, day/night, tutorial, saving |
| `src/voxel_world.gd`, `world_gen.gd`, `chunk_mesher.gd` | chunked world, generation, meshing on worker threads, ray casts, collision |
| `src/player.gd`, `avatar.gd` | third-person player and the Ola/Naba voxel models |
| `src/input_router.gd` | device-scoped input, bindings, controller assignment |
| `src/inventory.gd`, `items.gd`, `blocks.gd` | stacks, items, recipes, block rules |
| `src/hud.gd`, `inventory_ui.gd`, `menus.gd` | per-player HUD and inventory, menus |
| `src/mobs.gd`, `drops.gd`, `audio.gd` | creatures, drops and bundles, synthesized sound |
| `src/saves.gd`, `settings.gd`, `legacy_v1.gd` | world slots, preferences, starter-save import |
| `src/textures.gd`, `voxel_model.gd`, `shaders/` | original pixel art painted in code, model builder, shaders |
| `tests/`, `tools/` | headless tests, screenshot and benchmark helpers |

Ola-Naba Craft is not affiliated with any console or game maker.
