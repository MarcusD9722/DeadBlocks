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
- Friends connect **over the internet**. All players are on **Windows**.
- Joining: each player picks a name, the server has a password, characters are saved by name.
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

## Milestone plan
- **M0 — Setup & measurement**: GitHub repo; headless stress test (120 zombies + simulated players), run both here and on the Pi.
- **M1 — Multiplayer foundation**: server/client split, dedicated headless Pi server build (Linux ARM64) + Windows client build, join with name + password, server-side save/load with autosave, time pauses when empty. Clients generate terrain from the seed; the server only sends block edits.
- **M2 — Death & respawn**: backpack drop (10 min, anyone can loot), beds, random spawn points, 60 s logout linger.
- **M3 — Zombie rework**: proximity-only aggression on normal days, Blood Moon 120-zombie split with grouping, new zombie types, Blood Moon loot.
- **M4 — Exploration & loot**: distance-based danger scaling, ruins/POIs, chests, loot tables with rarity, 3-day refill, doors with locks/PIN.
- **M5 — Smarter zombies**: pathfinding toward the weakest part of a base.
