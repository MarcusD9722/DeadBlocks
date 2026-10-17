# M1 plan: multiplayer foundation

Status: **approved by the owner; M1.1 done.** Merged from three independent drafts (simplest-first, performance-first, risk-first), each of which prototyped and measured parts of this in a scratch copy. Numbers marked *measured* come from those prototypes on the 4-core 2.1 GHz cloud machine unless they say "Pi".

## Goals
At the end of M1:
- Marcus's Raspberry Pi 5 runs a **dedicated Dead Blocks server 24/7** next to his Minecraft server.
- Up to **8 friends join over the internet** from a Windows `.exe` with a **name + personal PIN** and the server password.
- Everyone shares one world: building, mining, crafting, zombies, animals, Blood Moon, day/night.
- The world and every character are **saved** (autosave, crash-safe, backups), and **time stops while nobody is online**.
- The server is built so M3 can spread zombie work over all 4 cores (regions, ordered edit queue).
- Every step ends with a **Windows build** Marcus can try.

Not in M1: backpacks/beds/logout linger (M2), the Blood Moon split/merge rules and new zombie types (M3), loot/chests/locks (M4), pathfinding (M5).

## Architecture

### One project, four ways to start it
| Mode | How it starts | What it does |
|---|---|---|
| Dedicated server | `--server` (the Pi; also the Windows exe with `--headless -- --server`) | Runs the world: no window, HUD, textures, sounds, render meshes or mob models. Jolt Physics at **30 ticks/s**, `Engine.max_fps = 30`. |
| Client | Title screen → **Join server** | Draws the world, generates terrain itself from the seed, sends its own movement, asks the server for everything else. Physics at 60 Hz for the local player. |
| Host game | Title screen → **Host game** | The exe starts **a second copy of itself as a dedicated server** (`OS.create_process`, bound to 0.0.0.0) and then joins it as a client. Same server code as the Pi, so testing at home tests the real thing. The child server exits when its parent exits. |
| Play solo | Title screen → **Play solo** | Until step 7: today's single-player code, unchanged (the autotest keeps guarding it). From step 7: Host game bound to 127.0.0.1 with a random port and password, so solo runs on the same server code and the old path is removed. |

*Why a child process for Host/Solo:* the drafts that ran the server inside the client process needed a separate physics space and had to keep server code away from the `G.world`/`G.player` globals; a separate process removes that whole class of bugs for the cost of a second Godot process on the PC.

### Networking
- **ENet over UDP, port 24650**, through `ENetMultiplayerPeer` + `SceneMultiplayer`, used only for: the connection, the **auth handshake** (`auth_callback` / `send_auth` / `complete_auth`), and `send_bytes()` for our own binary messages.
- **No RPCs, MultiplayerSpawner or MultiplayerSynchronizer.** The server and the client have different node trees on purpose (the server has no visuals), and Godot's Variant encoding doubled the bytes and split snapshots into two UDP fragments (*measured*: 2568 B vs 1208 B for 120 zombies).
- All message layouts live in `scripts/net/protocol.gd` (a type byte + fixed little-endian fields, `PROTOCOL` version number) with a round-trip test per message.
- Channels: **0** reliable-ordered (control, edits, inventory, chat); **1** unreliable-ordered (snapshots down, movement up); **2** reliable bulk (saved chunk data), so a big chunk never delays control messages.
- ENet compression off (the range coder saved ~12% of bytes and cost ~0.9 ms of CPU per snapshot round, *measured*). Peer timeout 5–15 s.

### Who decides what
- **Server:** blocks and block damage, inventories, crafting, eating, health and food, all zombies and animals (AI + physics + spawning), combat damage, time / day / Blood Moon, saving, names.
- **Client:** its own movement, camera, stamina and mining-progress timer. The server keeps no physics body for players and sanity-checks each movement update (speed ≤ 1.6 × sprint + knockback, feet not inside blocks); a failure gets a teleport correction.
- Requests are checked on the server: break/place (reach 5 m + slack, expected block id, item in slot, no player/mob overlap, mining time), attack (reach, cooldown), craft (station within 4 blocks of where the server thinks you are). The client shows its own break/place immediately and rolls back if the server rejects it.
- Movement is client-trusted; that's fine for a password-protected friends server.

### What travels, and how often
- Server tick 30 Hz; a **snapshot every 2nd tick (15 Hz)**.
- Snapshot entity record = **10 bytes** (id, position at 1/64 m relative to a reference chunk, yaw, flags: kind / attacking / hurt / dead). Player records add pitch and held item. Packets are split at **≤ 1150 B** so they never fragment.
- Each client gets the entities within **96 m** (fog ends at 100 m). Clients draw remote entities ~100 ms in the past with interpolation.
- Movement up: 15 Hz, ~20 B. Reliable messages are batched once per tick: block edits (~3 B each, grouped per chunk), crack stages on change, inventory slot changes, health/food, time (every 5 s and on change), join/leave, chat.
- **Bandwidth** (*measured* worst case, all 8 players at one base with 120 zombies): about **1.3 Mbit/s** of server upload in total; ~0.2 Mbit/s when players are spread out. Marcus has ~400 Mbps fiber upload, so this is a non-issue; `snapshot_hz` stays configurable anyway.
- **Server CPU for networking** (*measured*): a snapshot round for 8 clients × 120 entities ≈ 0.35 ms; in the real benchmark with 8 networked clients the load moved from 44% to 45%.

## World sync and saving

### Terrain
- Clients and server generate the same terrain from the seed. *Measured* in two separate tests: up to 525 chunks (out to 50 km) and 20,000 raw noise samples are **bit-identical** between x86_64 Linux and the Pi's arm64 build. Windows could not be tested here.
- Safety net: at join the client sends a hash of a few fixed test chunks; a mismatch refuses the join with a clear "terrain mismatch" error instead of a silently different world. `WORLDGEN_VERSION` is checked too.
- **Modified chunks** are sent whole (zstd, ~0.6–1.5 KB, *measured*) on channel 2 when they come within range of a client; the client waits for that data before meshing them. Unmodified land costs nothing.
- All block changes (players, zombies, spikes) go through **one edit queue per tick**, applied in a fixed order (player requests in arrival order, then zombie hits by region and zombie id); the same batch becomes the network message.

### Save files (server)
```
~/deadblocks-server/
  server.cfg                 port, password, max_players=8, admins, day_minutes=30, autosave_s=60, snapshot_hz=15
  control/                   drop-box for stop / save / kick / reset-pin, checked once a second
  status.json                written every minute: players, zombies, load %, worst tick, last save
  worlds/main/
    world.json               format, game & worldgen version, seed, day, time, kills, next entity id
    players/<name>.json      name, PIN hash, position, look, health, food, inventory, spawn point, play time
    chunks/<cx>.<cz>.bin     header + CRC32 + zstd(16 KB block array)
    world.lock               refuses a second server on the same world
  backups/                   zip of worlds/main
```
- **Writes are crash-safe:** write `.tmp`, run `sync` (Godot never fsyncs, *measured* with strace), rename over the old file. *Measured:* 15 `kill -9`s during saving never produced a broken file.
- **Loads are checked:** stale `.tmp` files are removed, every file's checksum is verified, a save from a newer version is refused (so an old build can't overwrite it), older formats are migrated after a backup.
- **Autosave every 60 s** (the main thread only copies data; compression and writing run on a worker thread), plus: a player's file when they leave, everything when the server empties, and on stop.
- **Stopping must not use signals.** All three drafts measured that headless Godot dies instantly on SIGTERM/SIGINT/SIGHUP without running any save code. So the service stops through `dbctl stop`, which drops a file in `control/` and waits. A power cut loses at most the last minute.
- **Backups:** on every start, when the server empties (at most hourly), daily, and before every update. Keep the newest 20 plus one per day for 14 days.
- Not saved: zombies and animals (they respawn), crack damage, mining progress, chat.
- Solo and Host worlds live on the PC under `%APPDATA%\DeadBlocks\worlds\`, with Continue / New world on the title screen.

## Joining and players
- Title screen: **Play solo · Host game · Join server · Quit**. Join form: server address (`host` or `host:port`), **name**, **PIN**, server password, "remember me". Clear messages for: wrong password, wrong PIN, name already online, server full, version mismatch (with the download link), terrain mismatch, no answer ("check the address and port forwarding").
- **Auth handshake:** the server sends a random challenge; the client answers with HMAC proofs of the server password and of its PIN, so **neither travels over the internet in plain text.**
- **Names and PINs:** names are 3–16 letters, digits or `_`, unique ignoring case. The first join with a name claims it with the PIN the player typed (4–8 digits). The server stores only a hash of name + PIN. Five wrong PINs for a name lock that name for 5 minutes. A forgotten PIN: Marcus runs `dbctl reset-pin Bob`. Players should not reuse a real bank PIN.
- **Characters** are saved by name: position, look, health, food, inventory, spawn point. A new name starts at the world spawn with today's starter kit. Until M2, today's death rules stay (keep items, respawn at the spawn point).
- **Time pause:** "online" means joined and finished loading. When the last player leaves, the server saves, stops the clock, AI, spawning and food drain, and idles at ~1% of a core (*measured*). The first player back resumes it.
- In multiplayer **Esc never pauses** (Resume / Disconnect / Quit / player list with ping). **T** opens text chat. F6/F7 time skips become admin commands (`/dusk`, `/bloodmoon`, `/save`, `/kick`, `/players`) for the names listed in `server.cfg` (Marcus).

## Server performance
*Measured A/B in a prototype (cloud machine, Jolt at 30 ticks/s)*, main-thread load:

| Change | Horde, 120 zombies | Combined (+7 explorers) |
|---|---|---|
| today's code | 51–52% | 63% |
| + spatial-hash zombie spacing | 45% | |
| + server skips models, animation, sounds, hit flash | 38% | |
| + collision-only chunks, merged collision strips | 36% | |
| full server mode | 36% | **44%** |
| full server mode + 8 networked clients | 35% | **45%** |

- **Projection for the Pi:** horde 57% → ~40%, combined 82% → ~59% (to be confirmed by the Pi benchmark in step 1).
- Server chunk radius **5** (80 m, enough for the 72 m zombie despawn distance) instead of the client's 6.
- Ship the server as an **exported release build** (chunk generation ~10–19% faster than the editor binary, *measured*).
- **Physics on its own thread:** mixed results (one draft measured 55% → 50% and the chunk upload dropping from 2.7 to 0.4 ms; another saw no gain). It's tried on the Pi and kept on the server only if it gains ≥ 5%. It requires the player's mob raycast to move into `_physics_process` (otherwise 5000+ "space state is inaccessible" errors, *measured*).
- **Region skeleton for M3:** `server/sim.gd` runs each tick in a fixed order: apply requests → rebuild regions every 1 s (players within 64 m grouped; each zombie belongs to its nearest player's region) → per region: spatial hash, zombie "think" (reads only its region, writes wishes to an outbox) → apply the edit queue → move all mobs → snapshot. M3 turns the per-region loop into a WorkerThreadPool group task. A `--regiontest` runs two regions forwards and backwards and must give identical results.
- The live server logs a status line every minute: players, zombies, chunks, load %, worst tick, kbit/s per client.

## Deployment
### Builds
- `tools/build_release.sh` produces `DeadBlocks.exe` (Windows, ~109 MB, single file) and `DeadBlocksServer-linux-arm64.zip` (the 67 MB server plus the Pi scripts). Export presets: Windows Desktop, Linux arm64 server, Linux x86_64 server (for tests here).
- Builds are published as **GitHub Releases** on the public repo. This workspace may not be allowed to create releases; if it isn't, the files are sent to Marcus in the chat and he attaches them to a release on github.com (a two-minute drag and drop). Until the server is packaged (step 6), the Pi can run the server straight from its git checkout with the Godot binary it already has.
- The exe is unsigned: Windows SmartScreen shows "More info → Run anyway" the first time.
- A version check at join tells anyone with an old exe which version to download.

### On the Pi
- One-time install from the release zip: `install.sh` asks for the server password, writes `server.cfg`, installs the systemd service and backup timer, and starts the server. Updates: `update.sh` (backup → download → stop → swap → start, keeps the old binary for rollback).
- systemd service: `ExecStop = dbctl stop` (never a bare signal), `Restart=on-failure`, and `CPUWeight=200` so Dead Blocks wins when it and Minecraft are busy at the same moment.
- `dbctl status | save | stop | say | kick | reset-pin | backup`; logs with `journalctl -u deadblocks -f`.
- **Router (AT&T gateway at 192.168.1.254):** reserve the Pi's address, then Firewall → NAT/Gaming → add "Dead Blocks", **UDP 24650**, to the Pi. Minecraft keeps TCP 25565.
- **CGNAT check:** gateway "Broadband IPv4 address" vs `curl -4 ifconfig.me` on the Pi. If they differ, use the playit.gg relay agent on the Pi. Optional DuckDNS name in case AT&T changes the address.
- `docs/pi-server.md` walks Marcus through all of this step by step, like the benchmark guide.

## Testing
- **`tools/test_all.sh`**, the gate every step must pass here. It fails on any FAIL line, **any `ERROR`/`SCRIPT ERROR` log line** (the autotest alone missed 5000+ physics-thread errors and still said `fails=0`), a crash, a timeout or a missing DONE line. Stages:
  1. **autotest** (`--autotest --seed=4242`, fails=0, 0 error lines).
  2. **savetest**: save/load round trip identical; a flipped byte is detected and refused; newer formats refused; old formats migrated with a backup.
  3. **crash test**: server with 1 s autosave killed with `kill -9` ten times at random; every restart loads and loses at most one interval.
  4. **nettest**: a headless server plus headless bot clients on random local ports. Joins and every rejection reason; players see each other within 0.3 m within 300 ms; edits reach others within 250 ms; late joiners get every edit; two simultaneous breaks → one wins; zombies within 0.5 m of the server position; attack, kill and damage; Blood Moon for everyone; pause when empty; stop → restart restores everything; snapshots ≤ 1150 B; with 10% simulated packet loss zombies stay within 1 m.
  5. **regiontest**: regions processed in either order give identical results.
  6. **worldgen check**: x86_64 vs the arm64 export under qemu, 0 differences.
  7. **exports** build, and the arm64 server under qemu accepts a join from an x86 bot.
  8. **benchmark** quick run in server mode (smoke only; real performance is judged on the Pi).
- The Pi benchmark (`tools/run_bench.sh`) gains an "M1 server" setup and a networked-bots mode, so Pi numbers stay comparable with M0.

## Steps
Each step ends with test_all.sh green, a Windows build for Marcus, and DESIGN.md/CLAUDE.md updated.

### M1.1 Safety net and a lighter server (still single-player) — done
Result on the reference machine: server-mode horde 37%, combined 46% (targets 40% / 48%). On the Pi: horde 46% → **38%** and combined 63% → **57%** with physics on its own thread, which the dedicated server now uses (M0: 57% / 82%). The region-order test gives identical hashes in both orders (and different ones when the ordering rule is deliberately broken). Merged collision strips were left out (≈1–3 points in the prototype); revisit in M1.8 if needed.

- **Work:** test_all.sh with the error-line gate; Jolt everywhere (client 60 Hz, server 30 Hz); player raycast moved to `_physics_process`; version constants shown on the title screen; export presets and build_release.sh; worldgen check under qemu; server mode (no visuals, collision-only merged chunks, radius 5); spatial-hash spacing; the `server/sim.gd` + regions + edit queue skeleton (in single-player the local player is the only player); `--regiontest`; day length from a setting (30 min default); benchmark "M1 server" setup.
- **Done when:** test_all green; on this machine the server-mode horde is ≤ 40% and combined ≤ 48% (today 51% / 63%).
- **Marcus tries:** the new exe plays the same as before (zombie crowds still spread out; days are now 30 minutes). On the Pi: `git pull` and rerun the benchmark; the M1 server line should show roughly 40% horde / 60% combined.

### M1.2 Join and walk together
- **Work:** protocol.gd, ENet transport, challenge auth with password + name + PIN, the dedicated server's session list and clock, time pause when empty, remote players (blocky avatar + name tag, interpolated), title screen with Host / Join, error messages, chat, pause menu with player list; Host game launches the child server; terrain-hash check at join; nettest harness (join, auth, movement, pause).
- **Done when:** nettest join/auth/movement/pause pass; the x86 server and the arm64 server under qemu both accept joins; autotest still green.
- **Marcus tries:** Host game in one window, Join 127.0.0.1 from a second window, walk around and chat; a wrong password or PIN gives a clear message. Then an **early internet test**: run the server on the Pi from the git checkout (in tmux), join it from the PC over the LAN, do the CGNAT check, forward UDP 24650, and have one friend join. This also checks that Windows terrain matches the Pi's.

### M1.3 Building together
- **Work:** server-checked break / place / craft / eat / inventory moves; server-owned inventories (drops go to the right player); edit queue → batched edit messages; saved/modified chunk data for players arriving in an edited area; optimistic edits with rollback; crack stages.
- **Done when:** nettest edits/inventory pass, including the late joiner, the two-simultaneous-breaks case, and a 60 s soak of 3 bots × 5 edits/s ending with identical chunk hashes everywhere.
- **Marcus tries:** two windows (or a friend): build a hut in one and watch it appear in the other; craft at a workbench; leave, add blocks, rejoin and see them.

### M1.4 Zombies and animals online
- **Work:** zombie/animal code split into a server part (think + move, no visuals) and a client view (models, animation, groans, flash, death fall, driven by snapshot flags); per-player spawning with the current caps and a global ceiling of 120; zombies chase the nearest player in their region; combat (attack checks, damage and knockback to players, kill rewards); Blood Moon for everyone; admin commands.
- **Done when:** nettest zombie/combat/bandwidth/loss pass; with 8 bot clients the combined benchmark here is ≤ 50%; a 120 s Blood Moon soak with 3 bots runs clean.
- **Marcus tries:** Host + Join (or a friend), `/bloodmoon`, defend a wall together and watch both screens show the same zombies and cracks.

### M1.5 The world remembers
- **Work:** the save system above (crash-safe writes, checks, autosave 60 s on a worker thread, backups, world.lock, control-file stop); characters by name + PIN; `dbctl reset-pin`; Solo/Host worlds on the PC with Continue / New world; savetest and crash test.
- **Done when:** savetest and crash test pass; nettest stop → restart restores positions, inventories, edits and time, and time didn't move while the server was empty.
- **Marcus tries:** Host, build something, fill the hotbar, quit everything, start again: it's all there and the clock didn't move. Rejoin as Bob from the second window: Bob's things are back; a wrong PIN for Bob is refused.

### M1.6 The Pi server for real
- **Work:** release arm64 export; server zip with install.sh, update.sh, backup.sh, dbctl and the systemd units; `docs/pi-server.md` (install, router, CGNAT, DuckDNS, updates, backups, restore); GitHub Release (or hand-off to Marcus); benchmark with 7 networked bots; physics-thread decision from the Pi numbers.
- **Done when:** here, install.sh/update.sh pass a dry run and the arm64 server under qemu serves an x86 bot. On the Pi: the service is active, survives a reboot, and LAN + internet joins work.
- **Marcus tries:** follow docs/pi-server.md (~15 minutes), run the networked benchmark and paste the results, join from his PC and from a phone hotspot or a friend's PC.

### M1.7 Solo runs on the server code
- **Work:** Play solo becomes Host game bound to 127.0.0.1 (random port and password); the old single-player code paths are removed; the autotest drives a real client against the local server.
- **Done when:** autotest green in the new mode; solo worlds from M1.5 still load; frame time within 10% of before.
- **Marcus tries:** Play solo feels the same as before.

### M1.8 First friends evening
- **Work:** per-minute stats in the log (ping, loss, kbit/s per player, load, worst tick), `tools/pi/stats.sh` summary, fixes from the session, tuning of snapshot rate / interest range / chunk radius, final numbers into DESIGN.md.
- **Done when:** a session of 4+ players for 30+ minutes including a Blood Moon, with server load ≤ 70% and no ticks falling behind.
- **Marcus tries:** play an evening with friends, then paste the `stats.sh` output.

## Risks and how they're handled
| Risk | Handling |
|---|---|
| Pi CPU (82% worst case before networking) | Server diet first (step 1, measured −30%), release build, confirmed on the Pi in steps 1 and 6; M3 adds multi-core. If the Pi lands at 70–85% in M1.6, ship with a note; above 85%, temporarily lower the Blood Moon cap and ask Marcus. |
| Windows terrain differs from the Pi's (untested) | Join-time terrain hash gives a clear error; checked for real in M1.2's internet test. |
| Power cut / under-voltage (seen once on this Pi) | fsync'd atomic writes, checksummed files, refuse-to-overwrite on damage, 60 s autosave, rolling backups, official 27 W supply. |
| `systemctl stop` or a reboot kills Godot instantly | ExecStop runs `dbctl stop`; saving on the last disconnect; 60 s autosave. |
| CGNAT | Checked in M1.2; playit.gg relay as the fallback. |
| Physics-thread errors | Error-line gate in test_all.sh; raycast moved in step 1; thread used only on the server and only if the Pi gains ≥ 5%. |
| Breaking single-player during the refactor | The old path stays until M1.7 and the autotest gates every step. |
| Save format changes in M2–M4 | Format numbers, migrations, pre-migration backups, newer formats refused. |
| Friends with an old exe | Version check at join with the download link. |
| Cheating by friends | Movement is client-trusted with sanity checks; accepted for a private server. |
| This workspace can't publish releases | Builds are handed to Marcus in the chat to upload. |

## Defaults chosen (Marcus can change any of these)
- UDP port **24650**; **8** players max; server password in `server.cfg` (never in the repo).
- PIN: **4–8 digits**; 5 wrong tries lock that name for 5 minutes; Marcus can reset a PIN.
- Admins: **Marcus** only.
- Autosave every **60 s**; backups as above.
- Day length **30 minutes** (the code currently uses 12).
- Dead Blocks gets **CPU priority over Minecraft** when both are busy.
- **Play solo** and **Host game** stay in the exe alongside Join server.
- Simple **text chat** (T) is included.
- Until M2: keep today's death rules (keep your items, respawn at the world spawn).
