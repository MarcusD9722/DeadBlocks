# Dead Blocks — Design Decisions

Living record of what has been decided. Update it whenever a decision changes.
CLAUDE.md covers how the code works; this file covers what the game should be.

## Pillars (in priority order)
1. **Exploration & loot** — the main reason to leave the base.
2. **Base defense** — matters most on Blood Moon nights.
3. Taming / creatures (ARK side) — later.

## Players & hosting
- **4–8 player co-op**, friendly fire **off**.
- **Dedicated server** on the owner's Raspberry Pi 5 (16 GB, 64-bit Raspberry Pi OS, mildly overclocked), running 24/7 off an **NVMe drive**.
- The same Pi may also run the owner's **Minecraft server**. Memory is not a concern (Dead Blocks peaked at ~1 GB in the benchmark); CPU is shared, so Dead Blocks should not assume it has all 4 cores. Advice given for Minecraft: Java edition on Paper (or Fabric + Lithium/C2ME), world pre-generated with Chunky, view-distance ~8 / simulation-distance ~6. Bedrock's official server does not run natively on ARM.
- Friends connect **over the internet**. All players are on **Windows**.
- Home connection: **AT&T fiber, ~400 Mbps upload**, so bandwidth is not a constraint (8 players + 120 zombies needs a few Mbit/s).
- Joining: each player picks a **name and a personal PIN**; the server also has a password. Characters are saved by name, and the PIN protects the name, so a player can log in from any PC.
- Builds reach players as **downloads on the public GitHub repo** (Releases): the Windows `.exe` for players and the Linux ARM64 server for the Pi.
- **Time stops when nobody is online.**
- Logging out: your character stays in the world for **60 seconds** after you disconnect. During a Blood Moon, your share of the horde moves to the nearest other player.

## Time
- A full in-game day lasts **30 real minutes**.
- A **Blood Moon** happens every 7th night (one every ~3.5 hours of play).

## Zombies
### Normal days and nights (6 of every 7)
- Moderate difficulty. Zombies **only chase when a player comes close**; otherwise they wander.
- These days are for gathering, building and re-supplying.

### Blood Moon (every 7th night) — grim and punishing
- **Global cap of 120 zombies**, split evenly between players online:
  1 player → 120, 2 → 60 each, 3 → 40 each, … 8 → 15 each.
- **Players close together share one combined horde**: their allocations merge and attack the group together.
- Every horde zombie hunts players (no proximity limit).
- Difficulty comes from **tougher zombie types**, not just numbers. Planned types:
  - **Runner** — fast.
  - **Brute** — heavy damage to blocks.
  - **Crawler** — fits through 1-block gaps.
  - **Screamer** — calls more zombies to its location.
  - **Spitter** — ranged acid that damages blocks.
- Hordes scale with player progression (day count and gear).
- **Reward for surviving**: horde zombies drop Blood Moon materials needed for top-tier crafting.

### Physics
- Keep Godot's full physics for zombies for now. Verify with a 120-zombie stress test on the Pi; fall back to cheaper block-grid collision only if needed.
- **Decided (M0): the server runs Jolt Physics at 30 ticks/s.** It is the only setup that kept a full 120-zombie Blood Moon at full speed on the Pi (see "Server performance" below). Godot's default physics cannot carry 120 zombies even on a desktop-class core.

## Death & respawn
- On death you drop a **backpack containing everything** (hotbar included).
- **Anyone** can pick it up. It **despawns after 10 real minutes**. It has a visible beacon.
- Respawn at your **bed**, or at a **random spawn point** if you have not placed one.

## World
- **Endless, procedurally generated world.** Chunks are generated only in a radius around each player and unloaded when players move away. Unvisited land does not exist until someone goes there.
- The save stores **only chunks players have changed** (compressed, ~1–2 KB each).
- **Difficulty rises with distance from the world center**, with no ceiling: harder zombies and better loot the further out you go.
- **Random spawn points stay within ~1 km of the center**, so new players start in the easy zone.
- Server load depends on how fast players move into unvisited land, not on world size. Measured cost: ~12.5 ms per chunk (generate + collision) on one 2.1 GHz cloud core; estimated 25–40 ms on a Pi 5 core. Worst case (8 players sprinting into new land at once) is roughly 1–1.5 of the Pi's 4 cores.
- Fast mounts (later) increase chunk-loading load; cap their speed or give them stamina limits.
- Position precision degrades very far from the center (~50–100+ km). If that ever matters, add a floating origin.
- Generated ruins / points of interest (cabins, gas stations, bunkers, crashed trucks, ruined towns) with loot containers and sleeping zombies. All original content.

## Loot
- Loot containers are **shared** and **refill every 3 in-game days**.
- **Rarity tiers** with random bonus stats on weapons and tools.
- Possible later: treasure maps, a trader at a safe outpost.

## Bases & ownership
- Chests and doors are **open to everyone by default**.
- A player can add a **lock / PIN code** to a door or chest to restrict it.

## Parked for later
- Taming and mounts (original creatures, no copyrighted names).
- Spell-card system, boss fights with dodge-roll, special ability moves (all original).
- Player level / skill system (would also feed horde scaling).

## Open items
- Owner to check whether the home connection is behind CGNAT (router WAN IP vs. public IP). This decides port forwarding vs. a relay such as playit.gg or Tailscale.
- World height is currently 64 blocks; may need raising for bunkers and multi-floor ruins.

## Server performance (M0)
Measured with `tools/run_bench.sh` (seed 4242, 60 s per scenario). "Load" is the share of one CPU core the game's main thread uses; the server falls behind above ~85%.

Reference machine: 4-core 2.1 GHz cloud Xeon (not the Pi).

| Setup | Explore: 7 players sprinting | Horde: 120 zombies | Combined |
|---|---|---|---|
| Godot physics, 60 ticks/s | 22% | 100% (only 45 of 60 ticks/s) | 99% |
| Jolt, 60 ticks/s | 23% | 83% | 98% |
| Jolt, 30 ticks/s | 17% | 43% | 58% |

- Zombie cost per tick: ~0.18 ms each with Godot physics, ~0.11 ms with Jolt. Most of it is `move_and_slide`; the O(n²) zombie spacing check adds ~0.04 ms each.
- Chunk cost: ~4.5 ms generate + ~8 ms mesh (worker threads) + ~2.5–3 ms upload on the main thread (mostly the collision shape). Chunk streaming kept up with 7 sprinting explorers in every setup (0% waiting).
- Chunk tasks are low-priority pool tasks; `project.godot` sets `threading/worker_pool/low_priority_thread_ratio=0.5` so 2 run at once on a 4-core Pi (the default allowed only 1).
The owner's Raspberry Pi 5 (stock 2.4 GHz, Minecraft server stopped, run on 2026-10-17):

| Setup | Explore: 7 players sprinting | Horde: 120 zombies | Combined |
|---|---|---|---|
| Godot physics, 60 ticks/s | 22% | 100% (only 31 of 60 ticks/s) | 100% (25 of 60 ticks/s) |
| Jolt, 60 ticks/s | 24% | 100% (50 of 60 ticks/s) | 100% (47 of 60 ticks/s) |
| **Jolt, 30 ticks/s** | **20%** | **57%, full speed** | **82%, full speed** |

- The Pi is ~1.8× slower than the reference machine for GDScript work (chunk cost 27–28 ms vs 15 ms) but only ~1.4× slower for zombies (0.155–0.174 ms each with Jolt), because physics is native code.
- Chunk streaming kept up with 7 sprinting explorers at Jolt@30 (0% waiting). Memory peaked at ~0.5 GB with Jolt.
- **Headroom is thin in the worst case** (82% with 120 zombies plus 7 explorers), and M1 adds networking on top. So the cheap zombie wins come first in M1: spatial-hash spacing instead of O(n²) (~25% of zombie cost), physics on its own thread, no render meshes on the server; then the multi-core steps below.
- CPU temperature reached 77 °C by the third run (the Pi 5 starts slowing itself at 80–85 °C). No throttling during the runs, but `get_throttled=0x50000` showed **under-voltage and throttling had happened since boot** (with Minecraft running), which points at the power supply. For a 24/7 server: official 27 W supply and an active cooler.

## Server multi-core plan
A Pi 5 has 4 cores. Today the simulation runs on one main thread, with chunk generation and meshing on 2 worker threads. The server must be designed from M1 so that work can spread over all cores; adding this later would be a rewrite.

Rules for the server design:
- **The world is simulated in independent regions.** A region is a group of players close together plus the area and zombies around them. This matches the Blood Moon rule that hordes split per player and merge when players group up: **one horde = one region**.
- **Regions never touch each other's state during a tick.** Anything that crosses regions (a player or zombie moving between them, chat, global time, saving) happens in a short single-threaded step between ticks. Regions merge when players come together and split when they separate.
- **Block edits go through one queue per tick**, applied in a fixed order, so two zombies hitting the same block never race.

Steps, in order of payoff:
1. **Chunk generation and meshing on worker threads**: done (M0). The server should also skip building render meshes and only build collision.
2. **Physics server on its own thread** (`physics/3d/run_on_separate_thread`): a project setting; measure it with the benchmark.
3. **One region per core**: when players are spread out, each region's zombies and AI run on a separate worker thread (WorkerThreadPool group task), in parallel.
4. **One big horde across cores**: for the worst case (all players at one base), split zombie *thinking* (target choice, spacing via a spatial hash, which block to hit) across threads, then apply moves in order. To also parallelise *movement*, replace `move_and_slide` with our own block-grid movement, because Godot's physics calls must stay on the main thread.

Expected gain: about **2.5–3×** more zombies on the same Pi, never a full 4×, because some work stays sequential and the Pi may share cores with Minecraft. The Pi benchmark results decide how soon step 4 is needed. Each step is checked with `tools/run_bench.sh`.

M1.1 (server mode: no visuals, collision-only chunks, radius 5, spatial-hash spacing, zombies ticked by region) on the reference machine, Jolt at 30 ticks/s: horde **37%** (was 42% for the same code without server mode, 43–51% in M0), combined **46%** (was 53%; M0 58–63%). On the owner's Pi 5 (2026-10-17, editor binary, Minecraft stopped):

| M1.1 server mode, Jolt @ 30 | Explore | Horde: 120 zombies | Combined |
|---|---|---|---|
| physics on the main thread | 21% | 46% (M0: 57%) | 63% (M0: 82%) |
| **physics on its own thread** | **19%** | **38%** | **57%** |

- ~~Decided: the dedicated server runs physics on its own thread~~ (`physics/3d/run_on_separate_thread.dedicated_server=true` in project.godot): −8 points on the horde, −6 combined, and the chunk collision upload leaves the main thread. The game client keeps physics on the main thread.
- **Changed in M1.6: the dedicated server runs physics on the main thread again**, like the game. The exported arm64 server (the only build with the physics thread) froze in about one in three full multiplayer test runs under qemu: every thread waiting on a lock inside the game, never with the physics thread off anywhere else. A frozen server on the Pi is much worse than the 6–8 points it saved, and 2–8 players leave plenty of headroom (63% combined in the worst case above, before the faster release build). M3's multi-core work is the way to win the CPU back. The server logs which mode it runs in ("SERVER physics runs on …"), and a watchdog restarts a server that stops responding (dbctl watchdog, every 15 s).
- The exported release build is faster again for GDScript work (chunk generate + mesh 6.4 ms vs 11.1 ms on the reference machine), so the real Pi server should land a little below these numbers.
- The Pi reached 80.7 °C on the second run (no throttling yet; the Pi 5 starts slowing itself around 80–85 °C). Better cooling is recommended for 24/7 use next to Minecraft.

## Milestone plan
- **M0 — Setup & measurement** (done): GitHub repo; headless stress test (120 zombies + simulated players), run both here and on the Pi. Result: Jolt @ 30 ticks/s.
- **M1 — Multiplayer foundation** (detailed plan: `docs/M1-plan.md`): server/client split, dedicated headless Pi server build (Linux ARM64) + Windows client build, join with name + password, server-side save/load with autosave, time pauses when empty. Clients generate terrain from the seed; the server only sends block edits. The server is built around independent regions (see "Server multi-core plan"), with physics on its own thread and no render meshes.
  - M1.1 (done): test gate, server mode, physics thread, regions. M1.2 (done): join over the network with name + PIN + password, see each other, chat, admin commands, Host game, time stops while nobody is online. M1.3 (done): building together — the server owns blocks and inventories, mining / building / crafting / eating online, late joiners get the edited chunks, admins can `/give`. M1.4 (done): zombies and boars run on the server and everyone sees the same ones; health and food are the server's; combat, cracks, Blood Moon for everyone, admins can `/spawn`. M1.5 (done): the server saves the world, every character and the clock (crash-safe, checked, autosave every 60 s, backups, a lock against two servers on one world, control files for stopping and admin jobs); Host game worlds are kept on the PC. M1.6 (done): the Pi server package — a zip with install.sh (systemd service that starts with the Pi, saves on stop, restarts after a crash, wins the CPU over Minecraft; daily backups), dbctl for everyday control, update.sh with automatic rollback, and docs/pi-server.md. M1.7 (done): Play solo runs the same server in the background on the PC (only reachable from the PC itself); the pause menu stops its world, solo worlds are saved with Continue / New world, and the autotest plays a solo game through the real client. Next: the big two-PC test, then M1.8 (first friends evening).
  - Decided in M1.2: signing in with a name that is still online (say after a crash) and the right PIN takes over that session instead of being refused. A hosted game's server stops when the game closes, or by itself 15 s after its host is gone.
  - Decided in 0.2.2 (after drops in the first Pi test): a connection counts as lost only after 15–30 s of silence, and the game then reconnects by itself for up to a minute, keeping the world on screen.
- **M2 — Death & respawn**: backpack drop (10 min, anyone can loot), beds, random spawn points, 60 s logout linger.
- **M3 — Zombie rework**: proximity-only aggression on normal days, Blood Moon 120-zombie split with grouping, new zombie types, Blood Moon loot. Hordes run one region per core; spacing uses a spatial hash; one big horde can be split across cores (multi-core plan steps 3–4).
- **M4 — Exploration & loot**: distance-based danger scaling, ruins/POIs, chests, loot tables with rarity, 3-day refill, doors with locks/PIN.
- **M5 — Smarter zombies**: pathfinding toward the weakest part of a base.
