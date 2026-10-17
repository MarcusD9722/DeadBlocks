# Dead Blocks — project notes for Claude Code

A first-person 3D voxel **zombie survival craft** game. The design blends three games:
- **Minecraft**: a block world you can mine and build in, plus crafting.
- **7 Days to Die**: zombies smash through blocks, with a Blood Moon horde every 7th night.
- **ARK**: wildlife to hunt now, with taming and creatures planned.

The owner (Marcus) playtests on Windows and gives feedback. Each round of work should end with a new Windows build he can run.

## Tech
- **Godot 4.7.2 (standard build, not .NET)**, using the GL Compatibility renderer and **Jolt Physics**. The game runs physics at 60 ticks/s; server mode runs it at 30 (decided in M0, see DESIGN.md).
- Everything is GDScript. There are **no asset files**: block textures, item icons and crack overlays are painted in code (`tex.gd`), and every sound is synthesized at startup (`sfx.gd`).
- `main.tscn` is the only scene. `game.gd` builds every other node in code.
- Indent with tabs and use typed GDScript where possible.

## File map (`scripts/`)
| File | What it does |
|---|---|
| `g.gd` | Autoload `G`. Global refs (game, world, player, hud, sim, tex, sfx), command-line args, `VERSION`, and `server_mode` (`--server-mode`, or the dedicated-server export): no render meshes, lights, mob models or sounds, physics at 30 ticks/s |
| `game.gd` | Game states (loading/title/playing/menu/paused/dead), day-night cycle and sky, Blood Moon, zombie and animal spawning, input bindings |
| `world.gd` | Chunked voxel world (16×64×16 chunks). Keeps chunks loaded around one or more centers (`update_centers`, one per player). Terrain generation and meshing run on WorkerThreadPool. Also holds raycasts, set_block, zombie block damage with crack overlays, and the torch/campfire lights |
| `world_gen.gd` | Deterministic terrain: hills, plains/forest/desert biomes, caves, coal/iron ore, trees, berry bushes |
| `blocks.gd` | Block ids and per-block tables (atlas tiles, shape, solid, opaque, hardness, tool, required pick tier, zombie HP). **Block id = item id** |
| `items.gd` | Non-block items (ids ≥ 100): tools, weapons, food |
| `inventory.gd` | 36-slot inventory. Slots 0–8 are the hotbar |
| `crafting.gd` | Recipe list. Each recipe needs an optional station (workbench/forge/campfire) within 4 blocks |
| `player.gd` | Movement, mining, placing, combat, hunger/stamina/health, held item, flashlight |
| `mob.gd` | Base creature: blocky box models, walking, hopping ledges, knockback, hit flash |
| `zombie.gd` | Day/night/horde variants. Ticked by the Sim (`sim_tick`), not by `_physics_process`. Chases the nearest player in its region, smashes blocking cells (queued through the Sim), takes damage from wood spikes |
| `animal.gd` | Boar: wanders, flees, drops raw meat |
| `hud.gd` | HUD, inventory/crafting screen, title/pause/death screens |
| `tex.gd` | Procedural 16×16 texture atlas and item icons |
| `sfx.gd` | Procedural sound effects |
| `autotest.gd` | Automated playtest, run with `-- --autotest` |
| `bench.gd` | Server load benchmark (Blood Moon horde, explorers streaming chunks), run with `-- --bench` |
| `server/sim.gd` | Node `Sim` (`G.sim`). Each physics tick: groups players into regions, builds each region's spatial hash, ticks zombies region by region in id order, then applies queued block damage sorted by zombie id. Holds the list of player records zombies can target |
| `server/virtual_player.gd` | Stand-in player for tests and benchmarks (zombies can target it; damage is only counted) |
| `tests/regiontest.gd` | `-- --regiontest`: two besieged groups; prints a hash that must not depend on region order |
| `tests/worldgen_hash.gd` | `-- --worldgen-hash`: one hash over many chunks and raw noise, to compare builds on different CPUs |

Outside `scripts/`: `tools/test_all.sh` is the test gate; `tools/build_release.sh` builds the Windows exe and the Linux servers into `build/`; `tools/check_worldgen.sh` compares PC and Pi terrain; `tools/run_bench.sh` runs the benchmark once per physics setup; `docs/pi-benchmark.md` is the owner's step-by-step guide for running it on the Raspberry Pi. `docs/M1-plan.md` is the multiplayer plan (architecture, protocol, saving, steps M1.1–M1.8).

## Run / test / build
Replace `godot` with the path to the Godot 4.7.2 executable (on Windows, `Godot_v4.7.2-stable_win64_console.exe` shows console output).

- **Play from the editor:** open `project.godot` in Godot and press F5.
- **The test gate — run before every commit:** `GODOT=<path> ./tools/test_all.sh` (about 4 minutes; `--quick` skips exports, the Pi terrain check and the benchmark, about 2 minutes). It runs the autotest, the region-order test both ways, the exports, the PC-vs-Pi terrain check (arm64 export under `qemu-aarch64-static`), and a short benchmark. A stage fails on a FAIL line, **any `ERROR`/`SCRIPT ERROR` line**, a crash, a timeout or a missing DONE line. Logs: `build/test_logs/`.
- **Automated playtest (headless):**
  `godot --headless --path . -- --autotest --seed=4242`
  It prints PASS/FAIL lines and ends with `AUTOTEST DONE fails=N`. Seed 4242 is the reference seed and should give `fails=0`. On some other seeds the "zombie damaged/broke the wall" checks fail because the zombie walks around the short test wall. That is a test limitation, not a game bug.
- **Screenshots:** add `--shots=<absolute dir>` and run with a real renderer instead of `--headless`.
- **Server benchmark:** `GODOT=<path to godot> ./tools/run_bench.sh` (5 setups, about 22 minutes; `BENCH_SETUPS=m1` runs only the 2 M1 server setups, about 9 minutes; add `--bench-secs=8` for a quick check). It runs `-- --bench` once per setup on seed 4242, with a temporary `override.cfg` choosing the physics engine, tick rate and physics thread; the M1 setups add `--server-mode`. It prints a results block and saves it to `bench_results/summary.txt`. A single run: `godot --headless --path . -- --bench --seed=4242 [--bench-secs=60] [--zombies=120] [--explorers=7] [--radius=6] [--only=horde]`. Don't run two benchmarks or other heavy work at the same time, or the timings are meaningless.
- **Builds:** `GODOT=<path> ./tools/build_release.sh` exports `build/DeadBlocks.exe` (Windows), a zipped copy, and `build/server/DeadBlocksServer.{arm64,x86_64}` (dedicated-server exports, which start in server mode). Needs the 4.7.2 export templates (Editor → Manage Export Templates → Download). The .pck is embedded, so each result is a single file.
- **Other flags:** `--server-mode` (simulate like the server), `--day-minutes=N` (default 30).

## Testing shortcuts in-game
- F6 skips to dusk or dawn.
- F7 jumps to the Blood Moon (day 7, 19:57).

## Rules for server-side code
- **No physics space queries outside `_physics_process`** (raycasts, shape queries, `direct_space_state`). With physics on its own thread they fail; the test gate's ERROR-line check catches it.
- **Zombie code must not depend on processing order.** In `sim_tick`, read the world and the region's start-of-tick spatial hash only; queue block damage with `G.sim.queue_block_damage(...)` instead of calling `world.damage_block`; use the zombie's own `rng`, never `randf()`. The region-order test checks this.

## Design & roadmap
**Read `DESIGN.md` before starting work.** It records the owner's decisions (4–8 player co-op on a Raspberry Pi 5 dedicated server, Blood Moon rules, death/backpack rules, loot, world) and the milestone plan (M0–M5). Keep it up to date when decisions change.

Other notes:
- Mashup features the owner asked for must be **original**: no copyrighted characters, names or assets. The ideas are a Wizard101-like spell-card system, Elden Ring-like boss fights with dodge-roll, and Naruto-like ability moves. These are parked for later.
- Better art. The owner is fine with the pixel style, and could supply sprites or textures later.
