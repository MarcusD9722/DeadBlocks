# M3 — Zombie rework: plan

Goal from DESIGN.md: the Blood Moon is grim and punishing, through **tougher zombie types** and a
horde shared out fairly between the players online; surviving it pays (**Blood Moon materials**
for top-tier crafting). Proximity-only aggression on normal days already shipped in 0.7.1.

Each step is its own release (0.9.0, 0.9.1, ...). Since 0.8.1 the games update themselves, so a
release is just the GitHub release plus `update.sh` on the Pi.

## Defaults chosen (Marcus can change any of these)
### The new zombie types
| Type | What it does | Health | Hits for | When |
|---|---|---|---|---|
| **Runner** | Very fast (faster than you walk, a bit slower than a sprint); thin and pale | 18 | 6 | Nights from day 2 (20% of night zombies, up to 35%), 25% of the Blood Moon |
| **Brute** | Slow and big (2.3 m); smashes blocks 4.5× as hard, hits hard and knocks you back | 110 | 18 | Blood Moons (10%), nights from day 10 (5%) |
| **Crawler** | Legless, crawls low: fits through 1-block gaps and under things | 16 | 7 | Nights from day 3 (15%), 15% of the Blood Moon |
| **Screamer** | Keeps its distance; when it spots you it screams and calls 4 zombies from out of sight (every 30 s, at most 3 times) | 22 | 4 | Blood Moons (8%), nights from day 5 (5%) |
| **Spitter** | Stays 6–12 m away and spits acid every 3 s: 12 damage to you, or eats into the block it hits (bases take damage from range) | 26 | 6 | Blood Moons from day 14 (10%), nights from day 12 (5%) |

Day zombies stay as they are. Everything else about noticing and chasing works as in 0.7.1.
Each type has its own look and sounds (a scream, a spit, a splash), all made in code like the rest.

### The Blood Moon horde
- **120 zombies at most, split evenly** between the players online: 1 player → 120, 2 → 60
  each, 3 → 40, … 8 → 15.
- **Players within 40 m of each other share one horde**: their shares add up, and the zombies
  come for the group.
- **Grows with the days:** the first Blood Moon (day 7) brings 40% of the share, day 14 brings
  70%, and day 21 on brings all of it. Solo, that's 48 zombies on day 7 and 120 from day 21
  (today's horde is about 30). The mix of types follows the table above. Gear doesn't count yet:
  there is no armour yet.
- When someone leaves or dies, the shares are worked out again, and their zombies go for
  whoever is nearest (the horde hunts everyone).

### Blood Moon loot
- Horde zombies drop **Blood Shards** to whoever kills them: half of the ordinary ones drop one,
  Screamers and Spitters drop 2, Brutes drop 3.
- New at the Forge: **Blood Steel Ingot** (1 Iron Ingot + 3 Blood Shards). At the Workbench:
  **Blood Steel Pickaxe / Axe** (tier 4, the fastest) and **Blood Steel Sword** (22 damage), and
  **Blood Brick** walls (twice as tough as Reinforced Wall).

## Steps
### M3.1 The new zombie types (0.9.0, built)
- `zombie.gd` grows the five types: stats, models, sounds, behaviour (a Crawler's low body; a
  Screamer's call and a Spitter's acid go through the Sim queue like block damage, so the result
  still doesn't depend on processing order).
- Acid globs are a mob kind of their own in `S_MOBS`, so clients see them fly. New mob kinds
  bump `Proto.PROTOCOL`.
- `/spawn runner|brute|crawler|screamer|spitter [n]` for admins.
- The night spawner mixes the types by day as in the table.
- **Tests:**
  - The region-order test spawns every type: Screamer calls and acid included, both orders give the same hash.
  - The new type test (`--typetest`), in arenas built in the air:
    - A Crawler gets through a 1-high tunnel untouched, while a walker has to smash it.
    - A Runner runs 20 m in about half a walker's time.
    - A Brute breaks a plank in 2 blows; a walker needs 6.
    - A Screamer calls zombies.
    - A Spitter's acid hits a player 10 m away and eats into a block.
  - The autotest spawns each type and checks it looks like itself. The fighter in the multiplayer test spawns each, and the second player sees them all.
  - `--lineup --shots=DIR` takes a picture of all of them.

### M3.2 The fair Blood Moon (0.9.1)
- The spawner works on groups of players: shares, grouping, the day scaling and the type mix.
- It spawns at the group's edge, 20–35 m out, every second until the group's number is alive.
- **Tests:**
  - 1, 2 and 3 players (two of them together): the right number of zombies around each group.
  - A leaving player's share moves to the others.

### M3.3 Blood Moon loot (0.9.2)
- Blood Shards, Blood Steel Ingot, the tier-4 tools, the sword and Blood Brick: items, icons,
  recipes and drops.
- **Tests:** kills drop shards to the killer; the recipes work at their stations.

### M3.4 Keeping the Pi fast
- Benchmark 120 zombies of the new mix, plus 7 explorers, here and on the Pi
  (`docs/pi-benchmark.md`).
- If the Pi goes over 70% in the worst case: run each region's zombie thinking on its own core
  (multi-core plan step 3, with movement still on the main thread).

## Done when
- Every type plays as described and every PC sees the same.
- A Blood Moon solo and with friends has the numbers above, and is survivable in a good base.
- Its loot makes the best gear.
- The Pi keeps up with 120 zombies.
