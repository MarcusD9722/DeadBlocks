# M4 — Survival depth: plan

Marcus asked (after 0.12.0) for:
- the world rounded and smoothed a bit more;
- controller support and new keys: **E** opens and closes what you look at (workbench, forge,
  campfire, doors, dropped bags), **I** opens your own inventory with basic crafting;
- crafting by station: wood things by hand, stone and iron tools and weapons at the workbench,
  Blood Moon tools and weapons at a **Blood Forge**;
- more building blocks with upgrade tiers like 7 Days to Die (wood → reinforced wood → iron →
  steel → blood-forged), a **hammer** to repair and upgrade, a **shovel** for dirt;
- better clouds, taller mountains, big Minecraft-like caves with ores, zombies in caves;
- thrown spears you can pick up again, a bow, a crossbow;
- villages with farms and new foods, villagers who trade, roads with wrecked cars to loot, run-down
  houses, shops, farms and towns with loot in boxes and cabinets.

This plan replaces the old "M4 — Exploration & loot" line in DESIGN.md (its ruins, loot tables,
refills and locks are part of M4.5 below). Each step is its own release; the games update
themselves, so a release is the GitHub release plus `update.sh` on the Pi.

## Order, and why

| Step | What | Why here |
|---|---|---|
| **M4.1** (0.13.0) | Controls, controller, crafting by station, tool tiers up to Blood Steel, shovels, Blood Moon loot, more rounding | Everything after it adds items, blocks and screens; the keys and the crafting split come first |
| **M4.2** (0.14.0) | Building: block format with room for many more blocks and their facing, structure tiers, hammer upgrades and repairs, doors, hatches, ramps, storage boxes, bags opened with E | Doors, ramps and tiers need the bigger block format; storage boxes are the base for all loot |
| **M4.3** (0.15.0) | Ranged weapons: spears (thrown, picked up again), bow and arrows, crossbow and bolts | Needs only the server's projectiles (the spitter's acid already flies) |
| **M4.4** (0.16.0) | Deep world: twice as tall, mountains, cave systems, ores by depth, zombies in caves, better clouds; the fair Blood Moon (old M3.2) | New terrain is a new world, so it waits until the crafting and building it serves are in |
| **M4.5** (0.17.0) | Roads and towns: roads between towns, wrecked cars, run-down houses, shops and farms, loot containers with rarity and refills, sleeping zombies; then the Pi benchmark (old M3.4) | Needs the containers (M4.2) and the new terrain (M4.4) |
| **M4.6** (0.18.0) | Villages, farming and traders: settlements with fields, seeds and crops, new foods, traders who buy and sell | Needs towns and roads to sit on, and loot to trade |

The old M3.3 (Blood Moon loot) is folded into M4.1. M5 (smarter zombies) stays after M4.

## Existing worlds (default)
- Up to M4.3 everything works in today's worlds, the Pi's included.
- M4.4 changes the terrain. Old worlds keep their terrain (the world remembers which generator made
  it, and the server sends that to the games), so the Pi world goes on as it is. Mountains, caves,
  roads, towns and villages appear only in a **new world** (`dbctl` / `--new-world`, the old one
  goes to backups).

## M4.1 Controls and crafting (0.13.0) — built

### Keys (all of these can be changed in Settings → Controls)
| Action | Key | Controller |
|---|---|---|
| Move / look | W A S D, mouse | left stick / right stick |
| Jump / sprint | Space / Shift | A / click the left stick |
| Mine, hit | left mouse (hold) | right trigger (hold) |
| Place, eat, use | right mouse | left trigger |
| **Interact**: open or close a workbench, forge, campfire or Blood Forge; pick up a bag (later: doors, boxes) | **E** | X |
| **Inventory** with basic crafting | **I** | Y |
| Hotbar | 1–9, mouse wheel | LB / RB |
| Flashlight | F | D-pad up |
| Chat | T or Enter | — |
| Pause | Esc | Start |

- Right-click no longer opens stations: it places a block against them like against any block.
- Menus work with the controller: the D-pad or left stick moves between buttons, A presses, B goes
  back. Stick look speed has its own setting.

### Crafting by station
- **I — your inventory**: hand crafting only. Planks, sticks, torches, bandages, the campfire,
  the workbench, and the wooden tools: pickaxe, axe, shovel and club.
- **Workbench** (E): stone and iron tools and weapons, steel tools and weapons, building blocks,
  spikes, beds, the forge, and the Blood Forge.
- **Forge** (E): smelting. Iron Ingot (iron ore + coal), **Steel Ingot** (2 iron ingots + 2 coal),
  **Blood Steel Ingot** (1 steel ingot + 3 Blood Shards).
- **Campfire** (E): cooking.
- **Blood Forge** (new station, made at the workbench from 8 stone bricks, 4 iron ingots and
  10 Blood Shards): the Blood Steel tools and weapons, and **Blood Brick** walls.
- A station's screen lists its own recipes next to your inventory; your inventory screen lists the
  hand recipes.

### Tools and weapons
| Tier | Material | Mining speed | Made at |
|---|---|---|---|
| 1 | Wood | 2.5× | hand |
| 2 | Stone | 4× | workbench |
| 3 | Iron | 6.5× | workbench |
| 4 | Steel | 9× | workbench |
| 5 | Blood Steel | 12× | Blood Forge |

- Every tier has a pickaxe, an axe and a **shovel** (new: digs grass, dirt and sand faster).
- Weapons: Wooden Club (7 damage), Stone Sword (11), Iron Sword (16), **Steel Sword** (19),
  **Blood Steel Sword** (24).
- The hammer comes in M4.2 together with the upgrades it does.

### Blood Moon loot (from the M3 plan)
- Horde zombies drop **Blood Shards** to whoever kills them: half of the ordinary ones drop one,
  Screamers and Spitters drop 2, Brutes drop 3.
- **Blood Brick** walls (Blood Forge) take twice the punishment of a Reinforced Wall.

### Rounder
- The natural ground rounds its corners further and fills small hollows a bit more, and it is
  smoothed one pass more. Tunnels and doorways still look about as big as they are.
- Built blocks get wider rounded edges.

### Tests
- The autotest presses I and E (a workbench), checks which recipes each screen lists, crafts by
  hand and at the workbench, is refused a workbench recipe away from one, and picks up a bag with E.
- The autotest drives the player with controller input (both sticks, a trigger, RB, Y and B).
- The multiplayer test crafts by hand and at a workbench; the server refuses station recipes
  without the station nearby and says why.
- The zombie-type test kills Blood Moon and ordinary Brutes, Screamers and Spitters and 40 horde
  walkers, and counts the Blood Shards.
- The mesh test still finds no holes in the rounder ground.
- `--scenery --only=screens` takes pictures of the new screens.

## M4.2 Building (0.14.0) — outline
- **Block format:** blocks become 16-bit (room for thousands of block kinds) with a few bits for
  facing and open/closed; chunk saves, chunk messages and edits change with it (save format 3,
  protocol bump; old saves are converted when loaded).
- **Structure tiers** (each takes more punishment than the one before): Wood Frame (cheap, quick
  to place) → Wood → Reinforced Wood → Iron → Steel → Blood-forged. Each tier in several shapes:
  full block, half block, ramp, pillar.
- **Hammer** (stone, iron, steel, Blood Steel): hit a block to upgrade it to the next tier using
  the materials in your inventory, or to repair zombie damage with its own material.
- **Doors and hatches** (wood, iron, steel), opened and closed with E; zombies smash them like
  walls. Locks and PIN codes (DESIGN.md) come later.
- **Storage boxes** (wood, iron), opened with E, shared like the rest of the world.
- **Dropped bags** open with E into the same box screen (take one thing or everything).

## M4.3 Ranged weapons (0.15.0) — outline
- **Spears** (wood, stone, iron): stab, or hold right-click to throw; a thrown spear sticks where
  it lands and is picked up again with E.
- **Bow** with arrows (stone, iron tips), **crossbow** with bolts: hold to draw, release to shoot;
  arrows that miss can sometimes be picked up again.
- Projectiles fly on the server (like the spitter's acid) and everyone sees them.

## M4.4 Deep world (0.16.0) — outline
- The world becomes **128 blocks tall**: real mountains with snow tops, valleys, and deep ground.
- **Caves** like Minecraft's: long winding tunnels, big caverns, ravines, underground lakes;
  coal near the top, iron deeper, a new rare ore at the bottom.
- **Zombies spawn in dark caves** (more of them deeper).
- **Clouds**: thicker, rounder, lit from inside at sunset, moving shadows on the ground.
- The fair Blood Moon from the M3 plan: the horde shared out by groups of players, spawned at each
  group's edge.

## M4.5 Roads and towns (0.17.0) — outline
- **Roads** connect towns across the world; **wrecked cars** along them can be searched.
- **Towns**: run-down houses, shops (a gas station, a grocery, a hardware store), farms and barns.
  Buildings have loot in boxes, cabinets, fridges and crates; better loot further from the center.
- Loot is **shared** and **refills every 3 in-game days**; **rarity** tiers (DESIGN.md).
- Sleeping zombies inside buildings.
- Then the Pi benchmark with the new world (the old M3.4).

## M4.6 Villages, farming and traders (0.18.0) — outline
- **Villages**: walled settlements of survivors with fields, safe from zombies.
- **Farming**: seeds from villages and loot; till ground with a hoe, crops grow over in-game days
  (wheat, corn, potatoes, carrots, pumpkins). New foods: bread, corn bread, baked potato, stew.
- **Traders** in villages: buy and sell for **Scrap** (a coin made from scrap metal), stock that
  changes every few days.
