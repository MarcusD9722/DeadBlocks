# M2 — Death & respawn: plan

Goal from DESIGN.md: dying costs something, but you can always get your things back.
- On death you drop a **backpack containing everything**; **anyone** can pick it up; it
  **despawns after 10 minutes**; it has a **visible beacon**.
- Respawn at your **bed**, or at a **random spawn point** (within ~1 km of the center) without one.
- Logging out: your character stays in the world for **60 seconds**.

M2 ships as one release, **0.8.0**, built in three steps. Each step passes the full test gate
and is committed on its own.

## Defaults chosen (Marcus can change any of these)
- **Backpack**
  - A small pack sitting where you died, with a tall light beam above it. The beam shows through fog and at night, and you can see it from about 100 m.
  - Anyone picks it up by mining it (hold left click, half a second). Everything that fits goes into their inventory; anything left over stays in the pack.
  - Your own packs also show on your screen with the distance and the time left.
  - It lasts **10 minutes of play**: the clock stops while nobody is online, like the day clock. Zombies can't break it.
  - Fell out of the world? The pack lands where you last stood on the ground.
  - Nothing in your inventory: no pack. Dying twice before going back makes two packs.
- **Bed:** crafted at a Workbench from **3 Planks + 3 Plant Fiber**. It's a low, half-height block.
  - **Placing it makes it your respawn point.** Each player has one; placing a new bed moves it.
  - If anyone or any zombie breaks your bed, you're told, and you no longer have a respawn point.
- **Respawning:** the death screen offers **Respawn at your bed** (when you have one) and **Respawn somewhere random**.
  - A random spot is on open ground (not in a tree, a desert or on a mountain top) within **1 km** of the world's center (`respawn_radius` in server.cfg).
  - You can't move until the world around you has loaded.
- **New players** start at the world spawn as now, so a group of friends starts together.
- **Logging out:** your character stays **60 s** (`linger_s` in server.cfg). It stands where you left, its name tag reads "(away)", and zombies can still kill it.
  - **Changed in 0.8.2 (Marcus):** this applies only when the connection is lost (a crash or a network drop). Leaving through the menu or closing the game takes the character out at once.
  - If they do, the backpack drops and your next join starts on the death screen.
  - Joining again within the 60 s just continues.
  - No staying behind: when the server stops, when you're kicked, when you're already dead, or in Play solo (the PC's own server stops with the game anyway).
- **Blood Moon:** the horde hunts everyone, so a departed player's zombies go for whoever is nearest. The even 120-zombie split per player is M3.

## Steps
### M2.1 Backpack (built)
- **New block `BACKPACK`:**
  - Not solid, unbreakable by zombies, never in an inventory (placing one is refused), drops nothing by itself.
  - Drawn as a small box (new block shape `SH_BOX` with per-block box sizes, shared with the bed).
  - The client draws a beacon beam for each one, like the torch lights (rebuilt with the chunk).
- **Server:**
  - Dying (`player_died`) moves the whole inventory into `backpacks[cell] = {owner, slots, left}`. The cell is the nearest free one at the death spot, dropped to the ground; the last ground position is used for a fall out of the world.
  - Breaking a backpack gives its contents to the breaker (leftovers stay, and the block stays).
  - Despawn timer: the world must be running.
  - `S_BACKPACKS` lists your own packs (position, seconds left), sent on join and whenever they change.
  - The owner gets a message when someone else picks up their pack and when it falls apart.
- **Saving:** `world.json` gets `backpacks`; `Save.FORMAT` becomes 2, so older servers refuse the world instead of crashing on new block ids.
- **Client:**
  - The HUD marker for your own packs.
  - The death screen says your things are in your backpack.
- **Tests:**
  - autotest: the pack drops with everything, the inventory is empty, the marker shows, mining it gives everything back, and a fall out of the world drops the pack on solid ground.
  - Pair test: b picks up a's pack.
  - nettest: a short `--backpack-s` makes a pack fall apart.
  - savetest: backpacks round trip.

### M2.2 Beds and random respawns (built)
- **New block `BED`** (solid, half height, with real half-height collision) and its recipe.
- **Server:**
  - Placing your bed sets the account's `bed`. A `beds` index (position → owner) is checked against every block change, so a broken bed is noticed wherever it happens.
  - `C_RESPAWN` carries a choice: at the bed (a free spot next to it, else on top), or random (`respawn_radius`, flag `--respawn-radius`; 0 = the world spawn, which the older tests use).
  - `S_BED` tells the client whether it has a bed, for the death screen.
- **Client:**
  - The death screen's two buttons.
  - After a far respawn, the loading overlay shows until the chunk under you is ready.
- **Tests:**
  - autotest: craft and place a bed, die, respawn next to it, break it, die, respawn at a random spot far away standing on solid ground.
  - savetest: beds in player files.

### M2.3 Logout linger (built)
- **Server:**
  - A player whose connection was lost (since 0.8.2 only then: more than 3 s of silence before ENet gave up), whose record is alive and who wasn't kicked or replaced, moves to `lingering`, keeping its Sim record (zombies still target it), its chunks and its place in snapshots, with `F_AWAY`. The world keeps running for it.
  - After `linger_s` it's removed as today. A login with that name takes it over at once.
  - It can die: backpack and death as usual.
- **Client:** "(away)" on the name tag and in the pause menu's player list.
- **Tests (nettest):**
  - A leaves, B still sees A's figure marked away, and it's gone after a short `--linger-s`.
  - A rejoins within the time and continues.
  - Zombies kill A's lingering body; A rejoins on the death screen, and the pack is there.

## How it went
- **Admin `/clear`:** removes every zombie and animal. The tests use it so a respawn isn't straight into the horde that just killed you. It's handy for Marcus too.
- **Death screen:** shows your bed's button only when you have a bed. Without one it says that a Bed placed from a Workbench would bring you back there.
- **Respawning far away:** you see "Finding your way..." until the land under you has loaded, and you don't fall while it loads.
- **The multiplayer test** runs its servers with `--respawn-radius=0` and `--linger-s=0`, so its older scenarios behave as before. Separate sections test the backpack (in the pair test, `--backpack-s=30`) and logging out (its own server, `--linger-s=15`).

## Done when
- A death drops a beaconed backpack anyone can pick up, which falls apart after 10 minutes of play.
- A bed brings you back to it; without one you wake up somewhere random, nearby and safe.
- Losing the connection mid-fight leaves your character behind for a minute; leaving through the menu doesn't.
- **Marcus tries:** die on purpose, find your backpack by its beam, craft and place a bed, die again and wake up next to it. With his wife: one quits during a night fight, and the other sees the character stay for a minute.
