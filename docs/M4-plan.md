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

After 0.14.0 Marcus added ("I'm trying to make this into a real game now"):
- **M** opens a **world map** that is uncovered as you travel;
- **I** opens the inventory with more **tabs**: an **armor** screen to equip armor and clothes, a
  **players** tab (who's on the server, send an **ally request**; allies show on the map and as a
  waypoint with distance, like a dropped bag), a **skills** tab for skills and perks, and a
  **tribe** tab (like ARK's tribes, to add people to your journey);
- an **experience bar**: zombie kills level you up, and levels become points for the skill tree;
- tools and weapons reskinned as **rounded 3D models** from free sources, so they don't look blocky;
- away from the blocky Minecraft feel, towards **simple 3D**;
- a world that feels **alive** (villages and villagers, run-down towns with homes, shops and
  farms, streets with wrecked cars: M4.8 and M4.9 below).

This plan replaces the old "M4 — Exploration & loot" line in DESIGN.md (its ruins, loot tables,
refills and locks are part of M4.5 below). Each step is its own release; the games update
themselves, so a release is the GitHub release plus `update.sh` on the Pi.

## Order, and why

| Step | What | Why here |
|---|---|---|
| **M4.1** (0.13.0) | Controls, controller, crafting by station, tool tiers up to Blood Steel, shovels, Blood Moon loot, more rounding | Everything after it adds items, blocks and screens; the keys and the crafting split come first |
| **M4.2** (0.14.0) | Building: block format with room for many more blocks and their facing, structure tiers, hammer upgrades and repairs, doors, hatches, ramps, storage boxes, bags opened with E | Doors, ramps and tiers need the bigger block format; storage boxes are the base for all loot |
| **M4.3** (0.15.0, built) | Ranged weapons (spears thrown and picked up again, bow and arrows, crossbow and bolts) and **every tool and weapon as a rounded 3D model** | The new weapons need models anyway; the first step away from the blocky look |
| **M4.4** (0.16.0) | **Character screen and map**: I opens tabs (Inventory, Players, Tribe); M opens the world map, uncovered as you travel; ally requests and tribes, allies marked on the map and with waypoints | The tabs are the frame the next step fills; the map is wanted before the world grows |
| **M4.5** (0.17.0) | **Progress**: experience bar, levels, skill points and a first skill tree (Skills tab); armor and clothes (Armor tab) | Fills the character screen; gives zombie kills a purpose |
| **M4.6** (0.18.0) | **The look, away from Minecraft**: trees, bushes, grass and rocks as 3D models, items as 3D models on the ground, new icons, a cleaner HUD and menus | Before the deep world, so new worlds are made with it |
| **M4.7** (0.19.0) | Deep world: twice as tall, mountains, cave systems, ores by depth, zombies in caves, better clouds; the fair Blood Moon (old M3.2); a **living world**: more animals, birds, weather, ambient sound | New terrain is a new world, so it waits until the crafting, building and look it serves are in |
| **M4.8** (0.20.0) | Roads and towns: roads between towns, wrecked cars, run-down houses, shops and farms, loot containers with rarity and refills, sleeping zombies; then the Pi benchmark (old M3.4) | Needs the containers (M4.2) and the new terrain (M4.7) |
| **M4.9** (0.21.0) | Villages, farming and traders: settlements with fields, seeds and crops, new foods, villagers, traders who buy and sell | Needs towns and roads to sit on, and loot to trade |

The order is a proposal: any step can move up if Marcus wants it sooner (the map, the character
screen and progress need nothing from the world steps, and the towns could come before the deep
world if the world feeling alive matters most).

The old M3.3 (Blood Moon loot) is folded into M4.1. M5 (smarter zombies) stays after M4.

## Existing worlds (default)
- Up to M4.6 everything works in today's worlds, the Pi's included (whether old worlds' block
  trees turn into the new tree models is decided in M4.6; the aim is yes).
- M4.7 changes the terrain. Old worlds keep their terrain (the world remembers which generator made
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
| **Interact**: open or close a workbench, forge, campfire or Blood Forge; open a bag (M4.2: doors, hatches, boxes) | **E** | X |
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
- The hammer came in M4.2 together with the upgrades it does.

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

## M4.2 Building (0.14.0) — built

### Block format
- Block ids stay one byte (61 of 256 used, room enough until much later). A block can carry a
  little **state** besides its id: its facing (four ways) and whether it is the upper half (a
  door's top, a half block or hatch in the top of its cell). The states are kept per chunk only
  for the blocks that have one, so plain land costs nothing.
- An open door or hatch is its own block id, so whether something is solid follows from the id
  alone: zombies, collision and the server's checks did not change.
- Chunk saves (`DBC2`, save format 3) and the chunk and edit messages (protocol 9) carry the
  states. Old saves load as they are (`DBC1` chunks have no states).

### Structure tiers
| Tier | Full block | Zombie punishment | Upgrade to it costs (full block, ramp / half block, pillar) | Repair costs |
|---|---|---|---|---|
| 0 | Wood Frame | 25 | (made by hand: 1 plank + 2 sticks gives 2 frames) | 1 plank |
| 1 | Planks (Wooden) | 60 | 2 planks / 1 plank | 1 plank |
| 2 | Reinforced Wood | 200 | 4 planks / 2 planks | 2 planks |
| 3 | Iron Wall | 400 | 2 iron ingots / 1 iron ingot | 1 iron ingot |
| 4 | Steel Wall | 700 | 2 steel ingots / 1 steel ingot | 1 steel ingot |
| 5 | Blood-forged Wall | 1300 | 1 Blood Steel ingot | 1 Blood Shard |

- Every tier comes in four shapes: **full block, half block, ramp and pillar**, made as frames by
  hand (frame half blocks and pillars 4 at a time) and upgraded with a hammer. A shape takes as
  much punishment as its tier's full block.
- A ramp faces the way you look when you place it and you walk up it; a half block goes in the
  top of its cell when you place it against a ceiling or the upper half of a side.
- Mining an Iron block back needs a stone pickaxe or better to get it, Steel an iron one,
  Blood-forged a steel one (the same rule as the ores).
- The stone chain upgrades too: Cobblestone → Stone Bricks (1 cobblestone) → Reinforced Wall
  (1 iron ingot) → Blood Brick (3 Blood Shards).

### Hammers
- **Wooden Mallet** (by hand: 2 planks + 2 sticks), **Stone, Iron and Steel Hammers**
  (workbench), **Blood Steel Hammer** (Blood Forge). A better hammer works faster: one blow takes
  1.5 s with the mallet, 0.5 s with the Blood Steel hammer.
- Hold the mine button on a block: a damaged block is **repaired** (all its damage, for its repair
  cost); otherwise it is **upgraded** to the next tier with the materials from your inventory. The
  line under the crosshair says which, what it costs and what you have.
- The server checks the hammer, the reach, the materials and the time between blows.

### Doors, hatches, boxes
- **Doors** (wood, iron, steel; two blocks tall) and **hatches** (wood, iron, steel), made at the
  workbench. **E** opens and closes them, both halves together; a door won't close on another
  player. The closed panel sits on your side of the cell, an open one swings back against its
  side. Hammers upgrade wood → iron → steel.
- Zombies smash closed doors and hatches like walls (wood 120, iron 350, steel 650); breaking one
  half takes the whole door.
- **Storage boxes**: Wooden Box (18 slots, workbench: 6 planks + 2 sticks), Iron Box (27 slots;
  4 iron ingots, or a wooden box upgraded with 2). **E** opens the box screen next to your
  inventory: click a box slot to take it, an inventory slot to put it in, or Take everything.
  Boxes are the server's and shared: everyone sees the same contents at once. A box that is
  broken (by a player or a zombie) leaves its things in a bag on the spot.
- **Dropped bags** open with E into the same screen. A bag that is emptied is gone.

### Tests
- The autotest places a door (both halves, the E prompt, E opens and closes it, the server
  agrees), puts planks in a box and takes them out, upgrades a frame with the mallet and repairs
  it after `/damage`.
- The multiplayer test: a second player sees the builder's open door, opens the box and takes the
  planks, and the builder's open box screen empties at once.
- The zombie-type test: a walker smashes through a closed wooden door (12 blows; a plank wall
  takes 6).
- The mesh test builds random land full of every shape and facing and finds no holes; the save
  test round-trips block states and boxes and still reads `DBC1` chunks.

## M4.3 Ranged weapons and 3D tools (0.15.0) — built

### Weapons
| Weapon | Made | Use | Damage |
|---|---|---|---|
| Wooden Spear | by hand: 3 sticks | stab (left mouse, reaches 4.2 m instead of 3.2), or hold right-click and let go to throw (harder the longer you hold, full at 0.8 s) | stab 7, thrown up to 15 |
| Stone Spear | workbench: 3 sticks, 1 cobblestone, 1 plant fibre | the same | stab 10, thrown up to 22 |
| Iron Spear | workbench: 3 sticks, 1 iron ingot | the same | stab 14, thrown up to 30 |
| Bow | by hand: 3 sticks, 3 plant fibre | hold left mouse to draw (full in 0.9 s), let go to shoot | the arrow's, less if not fully drawn |
| Crossbow | workbench: 3 planks, 2 iron ingots, 3 plant fibre | click to shoot; it reloads itself in 1.6 s while you have bolts | the bolt's |
| Stone Arrow (6) | by hand: 2 sticks, 1 cobblestone, 1 plant fibre | | 12 |
| Iron Arrow (6) | workbench: 2 sticks, 1 iron ingot, 1 plant fibre | | 18 |
| Iron Bolt (6) | workbench: 2 sticks, 1 iron ingot | | 28 |

- A hit in the head (the top fifth of a standing zombie) does double damage.
- The bow and crossbow shoot the first arrows (or bolts) in your inventory, the hotbar first.
- The crosshair shows a mark for each hit (red in the head or for a kill); the ammo left shows
  under it, and a bar while you draw, hold a spear back or the crossbow reloads.
- Arrows and spears drop with distance (an arrow at full draw leaves at 58 m/s, a bolt at 62 m/s
  and drops less, a spear at up to 24 m/s).

### In the world
- Projectiles fly on the server, like the Spitter's acid, and everyone sees them; your own shot
  shows at once (your game flies its own copy).
- A thrown spear always stays: stuck where it landed, or at the feet of what it hit. An arrow or
  bolt that misses stays stuck in the block three times in five. **E** picks them up. Spears fall
  apart after 20 minutes, arrows and bolts after 5; they are saved with the world.

### Rounded 3D tools
- Every tool and weapon is a smooth 3D model built in code (`scripts/tool_models.gd`): round
  handles and shafts, curved pick heads, flared axe blades, dished spades, swords, a bow with a
  string that draws back, a crossbow that shows its bolt. The tier shows in the material: wood
  and stone use the game's photo textures (ambientCG), iron, steel and Blood Steel are metals.
- In your hand (drawn in front of the world, so it never sinks into a wall), in other players'
  hands, flying and lying in the world. Their icons are drawn from the models when the game starts.
- (Free packs were looked at first: Kenney's CC0 tools are blocky low-poly, and no pack had a bow
  or crossbow; models made in code match the textures and every tier.)

### Tests
- The autotest throws a spear at the ground, checks it lies there and that E picks it up, shoots a
  zombie with the bow until it dies (hits marked on the crosshair, an arrow a shot) and hits one
  with the crossbow, which loads itself.
- The multiplayer test: the builder throws a spear, the watcher sees it lying there and picks it
  up, and it is gone for the builder too.
- The save test round-trips a spear lying in the world.
- `--scenery --only=held` takes pictures of the weapons in hand, the new icons, and a spear and
  arrows stuck in the ground with one in flight.

## M4.4 Character screen and map (0.16.0) — outline
- **I opens the character screen**, with tabs along the top (mouse, or LB/RB on the controller):
  **Inventory** (today's screen with hand crafting), **Players**, **Tribe**; **Armor** and
  **Skills** join in M4.5. E on a station still opens the inventory with that station's recipes.
- **World map (M)**: a top-down picture of the land, uncovered around you as you travel (the rest
  stays dark). Each player's map is their own, kept by the server and saved with their account, so
  it follows them to another PC. Zoom and drag; markers for you, your bed, your bags, your allies
  and tribe; your own pins with a name. Towns, villages and traders appear on it once found.
- **Players tab**: who is on the server (name, ping, ally or tribe), **send an ally request**;
  the other player gets a prompt to accept or decline; remove an ally.
- **Allies** see each other on the map and as a **waypoint with the distance** on screen (like a
  dropped bag's marker), and their name tags show through walls.
- **Tribe tab** (like ARK): found a tribe with a name, invite players, leave, and the founder can
  remove members or hand over leadership. Tribe members are allies, plus: a tribe chat channel,
  respawning at any tribe bed, and (once locks come) tribe-only doors and boxes.
- Allies and tribes are kept by the server (world.json), and work the same in Play solo, Host
  game and on the Pi.

## M4.5 Progress: experience, skills, armor (0.17.0) — outline
- **Experience** from zombie kills (more for Runners, Brutes, Screamers and Spitters, more again
  for Blood Moon zombies), a little from other things later (hunting, building, quests). An
  **experience bar** on the HUD; each level needs a bit more than the last.
- **Every level gives a skill point** to spend in the **Skills tab**: a tree of perks in a few
  branches, for example fighting (melee damage, stamina), survival (health, slower hunger,
  faster healing), building (hammer speed, cheaper upgrades, mining speed) and later scavenging
  (better loot, M4.8).
- **Armor tab**: slots for head, chest, legs and feet, with your character shown. Armor from boar
  hide (leather: boars drop hide), iron, steel and Blood Steel, each tier blocking more damage;
  clothes in the same slots (warmth matters once the weather does, M4.7). Other players see your
  armor if the models allow it.
- Dying keeps your level and skills (only your things go into the bag).

## M4.6 The look, away from Minecraft (0.18.0) — outline
- The aim is a simple 3D look like 7 Days to Die: the world stays a grid underneath (mining,
  building and zombies breaking walls depend on it), but only built blocks look like blocks.
- **Trees as 3D models** (several kinds per biome): chop the trunk and the tree falls and gives
  logs. **Bushes, grass, flowers and rocks** as 3D models too; berry bushes with berries on them.
- Things on the ground (dropped items, thrown spears) as small 3D models.
- New item icons, a cleaner HUD and menus (no pixel font), built blocks with even softer edges.
- Free CC0 model packs again where they fit.

## M4.7 Deep world and a living world (0.19.0) — outline
- The world becomes **128 blocks tall**: real mountains with snow tops, valleys, and deep ground.
- **Caves** like Minecraft's: long winding tunnels, big caverns, ravines, underground lakes;
  coal near the top, iron deeper, a new rare ore at the bottom.
- **Zombies spawn in dark caves** (more of them deeper).
- **Clouds**: thicker, rounder, lit from inside at sunset, moving shadows on the ground.
- The fair Blood Moon from the M3 plan: the horde shared out by groups of players, spawned at each
  group's edge.
- **A living world**: more animals (deer, wolves, bears, birds), weather (rain, fog, storms),
  ambient sound (wind, birds, insects at night) and some music.

## M4.8 Roads and towns (0.20.0) — outline
- **Roads** connect towns across the world; **wrecked cars** along them can be searched.
- **Towns**: run-down houses, shops (a gas station, a grocery, a hardware store), farms and barns.
  Buildings have loot in boxes, cabinets, fridges and crates; better loot further from the center.
- Loot is **shared** and **refills every 3 in-game days**; **rarity** tiers (DESIGN.md).
- Sleeping zombies inside buildings.
- Then the Pi benchmark with the new world (the old M3.4).

## M4.9 Villages, farming and traders (0.21.0) — outline
- **Villages**: walled settlements of survivors with fields, safe from zombies, with villagers
  going about their day.
- **Farming**: seeds from villages and loot; till ground with a hoe, crops grow over in-game days
  (wheat, corn, potatoes, carrots, pumpkins). New foods: bread, corn bread, baked potato, stew.
- **Traders** in villages: buy and sell for **Scrap** (a coin made from scrap metal), stock that
  changes every few days.
