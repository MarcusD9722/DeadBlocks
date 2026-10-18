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
| `g.gd` | Autoload `G`. Global refs (game, world, player, hud, sim, tex, sfx), command-line args (plus `server.cfg` on a server, `_load_server_cfg`), `VERSION`, and `server_mode` (`--server-mode`, `--server`, or the dedicated-server export): no render meshes, lights, mob models or sounds, physics at 30 ticks/s. `mode` is solo / client / server. Holds the client connection (`G.net`, survives the scene reload into the server's world), `host_game` (starts a background server process and joins it) and `start/end_client_session` |
| `game.gd` | Game states (loading/title/playing/menu/chat/paused/dead, plus connecting and server), day-night cycle and sky, Blood Moon, zombie and animal spawning, input bindings. Server mode: `_ready_server` (world + Sim + NetServer, no player/HUD). Client mode: seed, clock and position come from the server's welcome; keeps a RemotePlayer per other player and a mob view per mob (`_sync_mob_views`). Server: `_server_spawner` around every online player (max 120 zombies), `set_mobs_paused` while nobody is online, `spawn_near` for `/spawn` |
| `world.gd` | Chunked voxel world (16×64×16 chunks). Keeps chunks loaded around one or more centers (`update_centers`, one per player). Terrain generation and meshing run on WorkerThreadPool. Also holds raycasts, set_block, zombie block damage with crack overlays, and the torch/campfire lights. Server: `record_edits` collects every block change for NetServer. Client online (`remote`): only chunks the server subscribed as fresh are generated; edited ones arrive as copies (`net_subscribe/net_chunk/net_edits`) |
| `world_gen.gd` | Deterministic terrain: hills, plains/forest/desert biomes, caves, coal/iron ore, trees, berry bushes |
| `blocks.gd` | Block ids and per-block tables (atlas tiles, shape, solid, opaque, hardness, tool, required pick tier, zombie HP). **Block id = item id** |
| `items.gd` | Non-block items (ids ≥ 100): tools, weapons, food |
| `inventory.gd` | 36-slot inventory. Slots 0–8 are the hotbar |
| `rules.gd` | `class_name Rules`: break time and drops, shared by solo play and the server so they always agree |
| `crafting.gd` | Recipe list. Each recipe needs an optional station (workbench/forge/campfire) within 4 blocks |
| `player.gd` | Movement, mining, placing, combat, hunger/stamina/health, held item, flashlight. Online, `break_block` / `try_place` / `consume` / `attack` send requests and show the result at once; the server's answer replaces the guess. Health and food come from the server (`apply_stats`, `hurt_effect`); falls are reported |
| `mob.gd` | Base creature: blocky box models, walking, hopping ledges, knockback, hit flash. Online: `net_id`, `net_kind/net_flags` for S_MOBS, and `view` mode (client pictures moved by `view_update`) |
| `zombie.gd` | Day/night/horde variants. Ticked by the Sim (`sim_tick`), not by `_physics_process`. Chases the nearest player in its region, smashes blocking cells (queued through the Sim), takes damage from wood spikes |
| `animal.gd` | Boar: wanders, flees from the last hit, drops raw meat to whoever killed it |
| `hud.gd` | HUD, inventory/crafting screen, title menu (Play solo / Host / Join forms; remembered in `user://client.cfg` as hashes only), pause (player list and ping online), death screen, chat box and chat log |
| `tex.gd` | Procedural 16×16 texture atlas and item icons |
| `sfx.gd` | Procedural sound effects |
| `autotest.gd` | Automated playtest, run with `-- --autotest` |
| `bench.gd` | Server load benchmark (Blood Moon horde, explorers streaming chunks), run with `-- --bench` |
| `net/protocol.gd` | `class_name Proto`: message ids and binary layouts, login hashing (HMAC proofs of password and PIN), name/PIN rules, terrain hash. Bump `PROTOCOL` when a layout changes |
| `net/net_server.gd` | Dedicated server networking: ENet listen, login checks and refusals, one ServerPlayer per player, 15 Hz snapshots, clock messages, chat and admin commands (`/dusk /bloodmoon /time /kick /give /spawn /players`; `/hash` for tests), movement sanity check with corrections, `--hosted-by` stop for Host game. Saving through `saver` (autosave, a leaving player's file, everything when the server empties, control-folder commands, `stop_server` = the only clean stop). Owns blocks, inventories, health and food: checks break/place/craft/eat/swap/attack requests (refusal reasons are logged when a player leaves), runs hunger and healing (`_tick_players`), and once a tick (`_flush_world`) updates chunk subscriptions, sends edited chunks, edit batches, crack stages and inventories; mob updates (`mob_packets`) go out with the player snapshots |
| `net/net_client.gd` | Client networking (`G.net`): connect + login, welcome → `G.start_client_session`, other players' snapshot history and interpolation (100 ms behind), 15 Hz movement up, chat. After a dropped connection it logs back in by itself for 60 s (`reconnecting`); the same world continues via `G.resume_client_session`. Sends block/inventory requests, keeps the server's inventory plus unacknowledged guesses, and feeds world messages to the world (queued until `attach`) |
| `net/remote_player.gd` | Another player's blocky figure with a name tag and flashlight |
| `server/server_player.gd` | The server's record of a connected player (Sim player record once it is ready): health, food, kills, inventory, subscriptions; zombies hit it through `take_damage` |
| `server/save.gd` | Node `Save`: the server's save files under the data folder (`--data`, default `user://server`): `worlds/<world>/` world.json, players/, chunks/, world.lock, damaged/; backups/ (zips, pruned); control/ (`*.cmd`: stop, save, backup, kick, reset-pin, say); status.json. Crash-safe writes (.tmp, `sync`, rename), SHA-256 on every file, damaged files moved aside, newer formats and other terrain refused. Saves on a worker thread (`save_async`/`poll`) or at once (`save_now`, stopping) |
| `server/sim.gd` | Node `Sim` (`G.sim`). Each physics tick: groups players into regions, builds each region's spatial hash, ticks zombies region by region in id order, then applies queued block damage sorted by zombie id. Holds the list of player records zombies can target |
| `server/virtual_player.gd` | Stand-in player for tests and benchmarks (zombies can target it; damage is only counted) |
| `tests/regiontest.gd` | `-- --regiontest`: two besieged groups; prints a hash that must not depend on region order |
| `tests/worldgen_hash.gd` | `-- --worldgen-hash`: one hash over many chunks and raw noise, to compare builds on different CPUs |
| `tests/nettest.gd` | `-- --nettest=ROLE`: bot client roles for `tools/run_nettest.sh` (a/b pair, join, hold, reject:TEXT, host, stall, builder/watcher, late, soak, fighter/zwatch, horde, saver, crasher, screens) |
| `tests/savetest.gd` | `-- --savetest`: the save files without a server (round trip, damaged files, refusals, lock, backups, control files) |

Outside `scripts/`: `tools/test_all.sh` is the test gate; `tools/run_nettest.sh` is the multiplayer test; `tools/build_release.sh` builds the Windows exe, the Linux servers and the Pi server package into `build/`; `tools/pi/` holds the Pi package's scripts (`install.sh`, `update.sh`, `dbctl`, systemd unit templates `*.in`) and `docs/pi-server.md` is the owner's guide for it; `tools/test_pi_package.sh` tests that package here (qemu, a stand-in for systemctl); `tools/check_worldgen.sh` compares PC and Pi terrain; `tools/run_bench.sh` runs the benchmark once per physics setup; `docs/pi-benchmark.md` is the owner's step-by-step guide for running it on the Raspberry Pi. `docs/M1-plan.md` is the multiplayer plan (architecture, protocol, saving, steps M1.1–M1.8).

## Run / test / build
Replace `godot` with the path to the Godot 4.7.2 executable (on Windows, `Godot_v4.7.2-stable_win64_console.exe` shows console output).

- **Play from the editor:** open `project.godot` in Godot and press F5.
- **The test gate — run before every commit:** `GODOT=<path> ./tools/test_all.sh` (about 20 minutes; `--quick` skips the exports, the Pi checks and the benchmark, about 12 minutes). It runs the autotest, the save test, the region-order test both ways, the multiplayer test, the exports, the PC-vs-Pi terrain check (arm64 export under `qemu-aarch64-static`), the multiplayer test against the arm64 server under qemu, the Pi package test, and a short benchmark. A stage fails on a FAIL line, **any `ERROR`/`SCRIPT ERROR` line**, a crash, a timeout or a missing DONE line. Logs: `build/test_logs/`.
- **Automated playtest (headless):**
  `godot --headless --path . -- --autotest --seed=4242`
  It prints PASS/FAIL lines and ends with `AUTOTEST DONE fails=N`. Seed 4242 is the reference seed and should give `fails=0`. On some other seeds the "zombie damaged/broke the wall" checks fail because the zombie walks around the short test wall. That is a test limitation, not a game bug.
- **Screenshots:** add `--shots=<absolute dir>` and run with a real renderer instead of `--headless`.
- **Server benchmark:** `GODOT=<path to godot> ./tools/run_bench.sh` (5 setups, about 22 minutes; `BENCH_SETUPS=m1` runs only the 2 M1 server setups, about 9 minutes; add `--bench-secs=8` for a quick check). It runs `-- --bench` once per setup on seed 4242, with a temporary `override.cfg` choosing the physics engine, tick rate and physics thread; the M1 setups add `--server-mode`. It prints a results block and saves it to `bench_results/summary.txt`. A single run: `godot --headless --path . -- --bench --seed=4242 [--bench-secs=60] [--zombies=120] [--explorers=7] [--radius=6] [--only=horde] [--net-clients=8]` (`--net-clients` also builds the updates a server sends that many players). Don't run two benchmarks or other heavy work at the same time, or the timings are meaningless.
- **Builds:** `GODOT=<path> ./tools/build_release.sh` exports `build/DeadBlocks.exe` (Windows), a zipped copy, `build/server/DeadBlocksServer.{arm64,x86_64}` (dedicated-server exports, which start in server mode), and `build/DeadBlocksServer-linux-arm64.zip` (the Pi package; no version in its name, so `update.sh` can fetch `releases/latest/download/` from GitHub). Needs the 4.7.2 export templates (Editor → Manage Export Templates → Download). The .pck is embedded, so each result is a single file.
- **Multiplayer test:** `GODOT=<path> ./tools/run_nettest.sh` (about 11 minutes; it freezes the server with SIGSTOP to test reconnecting and `kill -9`s it to test saving; `NETTEST_SOAK_S=60` lengthens the building soak and `NETTEST_HORDE_S=120` the Blood Moon soak, both default 20 s; `NETTEST_CRASHES=N` sets the number of crashes, default 3): a local server plus headless bot clients; prints NETTEST PASS/FAIL lines and `NETTEST ALL DONE fails=N`. Logs: `build/test_logs/nettest/`. Pass a server command prefix to test an exported server instead (see the script header).
- **Dedicated server:** `godot --headless --path . -- --server --password=S --admins=Marcus [--port=24650] [--max-players=8] [--seed=N] [--data=DIR] [--world=NAME] [--autosave=S] [--new-world]`. Settings can also come from `DIR/server.cfg` (`key=value`: port, password, admins, max_players, day_minutes, autosave_s, world, seed; flags win). The world is saved in DIR (default `user://server`) under `worlds/NAME` (default `main`); `--seed` only applies to a new world; `--new-world` backs up the old one and starts over. **Stop it with `echo stop > DIR/control/stop.cmd`** (it saves and quits): Ctrl+C or `kill` end headless Godot at once without saving. Join from the game's title screen (Join server), or `-- --connect=host[:port] --name=N --pin=P --password=S` to skip the menu.
- **Screenshots of the menus and an online session:** run under `xvfb-run` with `--rendering-driver opengl3` and `--nettest=screens --shots=<dir>` (title/Join/Host), or `--nettest=b --shots=<dir>` as the second bot next to a server and an `a` bot.
- **Other flags:** `--version` (print "Dead Blocks X.Y.Z" and quit; update.sh uses it), `--server-mode` (simulate like the server), `--day-minutes=N` (default 30), `--radius=N` (chunk radius), `--no-spawns` (server: mobs only from `/spawn`, for tests).

## Testing shortcuts in-game
- F6 skips to dusk or dawn.
- F7 jumps to the Blood Moon (day 7, 19:57).
- Online, F6/F7 send `/dusk` and `/bloodmoon` (admins only).

## Rules for server-side code
- **No physics space queries outside `_physics_process`** (raycasts, shape queries, `direct_space_state`). With physics on its own thread they fail; the test gate's ERROR-line check catches it.
- **Zombie code must not depend on processing order.** In `sim_tick`, read the world and the region's start-of-tick spatial hash only; queue block damage with `G.sim.queue_block_damage(...)` instead of calling `world.damage_block`; use the zombie's own `rng`, never `randf()`. The region-order test checks this.
- **Network messages are our own binary layouts in `net/protocol.gd`** (no RPCs or Synchronizers). Any layout change bumps `Proto.PROTOCOL`, and any release bumps `G.VERSION`: the server refuses other versions at login.
- **Online, the server owns blocks and inventories.** Change blocks on the server through `world.set_block` (it records the edit for clients); never change a client's world or inventory except from server messages or as a guess the server will confirm or undo. Drops and break times come from `Rules`, so solo and server agree.
- Server code runs without a HUD, textures, sounds or a local player (`G.hud`, `G.tex`, `G.sfx`, `G.player` are null): guard UI and sound calls (see `game._say` / `game._sound`).
- **Stopping goes through `NetServer.stop_server`** (control file `stop`, the Host game's watchdog): headless Godot dies instantly on SIGTERM/SIGINT without running any GDScript, so nothing can be saved from a signal. Anything new the server must remember goes into `save_world` (and, if it is per player, `_store_account` and `Save.player_json` / `load_players`).
- `ENetMultiplayerPeer.get_peer(id)` prints an ERROR for a peer that has gone; the server keeps its own `_live` set. `OS.is_process_running` only works for this process's own children.

## Design & roadmap
**Read `DESIGN.md` before starting work.** It records the owner's decisions (4–8 player co-op on a Raspberry Pi 5 dedicated server, Blood Moon rules, death/backpack rules, loot, world) and the milestone plan (M0–M5). Keep it up to date when decisions change.

Other notes:
- Mashup features the owner asked for must be **original**: no copyrighted characters, names or assets. The ideas are a Wizard101-like spell-card system, Elden Ring-like boss fights with dodge-roll, and Naruto-like ability moves. These are parked for later.
- Better art. The owner is fine with the pixel style, and could supply sprites or textures later.
