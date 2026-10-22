# Running the Dead Blocks server on the Raspberry Pi

This sets the Pi up as the always-on Dead Blocks server: it starts by itself when the Pi boots,
starts again if it crashes or stops responding, saves the world every minute and whenever it
stops, and keeps daily backups. It takes about 15 minutes. You type the commands on the Pi, directly or over SSH.

The Minecraft server can keep running next to it. When both are busy at the same moment, Dead
Blocks gets the CPU first.

## What you need
- The Raspberry Pi 5 with **64-bit** Raspberry Pi OS (the same Pi as the benchmark).
- A release on GitHub that has **DeadBlocksServer-linux-arm64.zip** attached, next to the Windows
  zip. (Or the zip on your PC: see "No release?" in step 2.)
- **Best: an Ethernet cable from the Pi to the AT&T gateway.** On Wi-Fi, the Pi lost 19% of its
  packets in our test, and that is what made players drop. If the Pi has to stay on Wi-Fi, do
  step 7 at least.

## 1. Stop the server you started by hand
If the old server is still running in tmux, stop it first; otherwise the new one can't use the
port.
```bash
tmux ls
```
If that lists a `deadblocks` session:
- If that server is version **0.5.0 or newer**, let it save first:
  ```bash
  echo stop > ~/.local/share/DeadBlocks/server/control/stop.cmd
  ```
  Wait until `tmux ls` no longer shows it (a few seconds).
- If it is **older** (0.4.0 and before saved nothing anyway):
  ```bash
  tmux kill-session -t deadblocks
  ```

## 2. Get the server
```bash
sudo apt install -y unzip curl python3
cd ~
curl -fLO https://github.com/MarcusD9722/DeadBlocks/releases/latest/download/DeadBlocksServer-linux-arm64.zip
unzip -o DeadBlocksServer-linux-arm64.zip -d ~/dead-blocks-download
```
**No release?** On your Windows PC, open PowerShell in the folder with the zip and copy it over
(use your Pi's address and user name):
```powershell
scp DeadBlocksServer-linux-arm64.zip marcus@192.168.1.245:~/
```
Then run only the `unzip` line above on the Pi.

## 3. Install
```bash
~/dead-blocks-download/deadblocks-server/install.sh
```
It asks two things:
1. **The server password**, twice. Your friends type it in Join server. It isn't shown while you
   type.
2. **Your name in the game.** That name gets the admin commands (`/bloodmoon`, `/dusk`, `/give`,
   `/spawn`, `/kick`, ...). Just press Enter for `Marcus`. More names: `Marcus,Wife`.

It may ask for your Pi password once (for `sudo`), to install the service. At the end it prints
`Done. The server runs now`, plus the address to join. The server lives in `~/deadblocks-server`
from now on; you can delete `~/dead-blocks-download` and the zip.

If you played on a server you started by hand with version 0.5.0 or newer, install.sh brings that
world along.

## 4. Join
- At home: in the game, **Join server** with address `192.168.1.245` (the address install.sh
  printed), your name, your PIN and the server password.
- From outside your house, friends need step 5.

## 5. Router: let friends in from outside
On the AT&T gateway (open http://192.168.1.254 in a browser; the device access code is on the
gateway's sticker):
1. **Firewall → NAT/Gaming**. Under *Service*, choose **Custom Services** and add: name
   `Dead Blocks`, protocol **UDP**, port **24650** to **24650**. Save.
2. Back on NAT/Gaming, pick the `Dead Blocks` service, under *Needed by Device* choose the Pi, and
   press **Add**.
3. The Minecraft forward stays as it is; both can point at the same Pi.

Friends join with your public address (Google "what is my IP" on a PC at home) and the same
password. Each friend picks their own name and a PIN of 4–8 digits on their first join (not a
bank PIN). Their character is saved under that name.

If you move the Pi to Ethernet later, it gets a new address: see step 7, and point both the
Minecraft and the Dead Blocks forwards at the new one.

## 6. Everyday commands
| Command | What it does |
|---|---|
| `dbctl status` | Running? Who's online, day and time, last save |
| `dbctl say Blood moon tonight!` | A message to everyone in the game |
| `dbctl kick Bob` | Throw Bob out (he can join again) |
| `dbctl reset-pin Bob` | Bob forgot his PIN: the PIN he types on his next join becomes his new one |
| `dbctl save` | Save now (it also saves every minute by itself) |
| `dbctl backup` | Save a copy of the world now (one is made every day at 05:00 too) |
| `dbctl backups` | List the backups |
| `dbctl restore` | Put the newest backup back (it stops and starts the server; the world as it was is kept next to it) |
| `dbctl restore main-2026-10-20-050000.zip` | Put a particular backup back |
| `dbctl stop` / `dbctl start` / `dbctl restart` | Stop (saves first), start, restart |
| `dbctl logs` | Watch what the server says (Ctrl+C to leave) |

**Rebooting or unplugging the Pi:** `sudo reboot` is fine; the server saves while the Pi shuts
down and starts again by itself. Pulling the plug loses at most the last minute of play.

**Settings** (password, admin names, port, max players) are in `~/deadblocks-server/server.cfg`.
After changing it: `dbctl restart`. You can also add these lines:
- `respawn_radius=1000`: how far from the world's center you can wake up without a bed (`0` = always at the world spawn).
- `linger_s=60`: how long a character stays in the world after its player's game crashed or lost the connection (`0` = not at all). Leaving through the menu always takes it out at once.
- `backpack_s=600`: how many seconds of play a dropped backpack lasts.

## 7. Wi-Fi: Ethernet, or at least no power saving
**With a cable (best):** plug the Pi into the gateway. Then:
```bash
hostname -I
```
The first address is the new one (Ethernet gets a different one than Wi-Fi). On the gateway,
under **Home Network → IP Allocation**, give the Pi that address permanently, then update the
Minecraft and Dead Blocks forwards (step 5) to it. Friends' addresses don't change (they use your
public address). You can then turn the Pi's Wi-Fi off:
`sudo nmcli radio wifi off`.

**Staying on Wi-Fi:** turn off Wi-Fi power saving, which makes the Pi drop packets:
```bash
printf '[connection]\nwifi.powersave = 2\n' | sudo tee /etc/NetworkManager/conf.d/wifi-powersave-off.conf
sudo systemctl restart NetworkManager
```
Then check: `ping -c 50 192.168.1.254` should end with **0% packet loss**.

## 8. Updating
When there's a new release on GitHub:
```bash
~/deadblocks-server/update.sh
```
It backs up the world, downloads the newest server, checks that it runs on this Pi, stops the
server (which saves), swaps the program and starts it again. If the new version doesn't start,
it goes back to the old one by itself.

**Players don't download anything** (from game version 0.8.1 on). When they join, the game sees
that the server runs another version, downloads that one from GitHub, restarts and joins again
by itself. This needs the release to be tagged exactly `v` + the version (for example `v0.8.2`),
with `DeadBlocks-0.8.2-windows.zip` attached. So make the GitHub release first, then run
`update.sh`.

- From a zip you copied to the Pi: `~/deadblocks-server/update.sh ~/DeadBlocksServer-linux-arm64.zip`
- Back to the version before: `~/deadblocks-server/update.sh --rollback`

## If something's wrong
- **`dbctl status` says NOT running:** it shows the last log lines, which say why. Common ones:
  - *world.json is damaged*: run `dbctl restore` (the newest backup) and `dbctl start`.
  - *could not listen on UDP port 24650*: something else uses the port; is the hand-started server
    still running in tmux (step 1)?
  - *saved by a newer version*: you went back to an older server; run `update.sh` again.
- **"No answer from the server" in the game:** check `dbctl status` on the Pi; at home, use the
  Pi's local address; from outside, check the forward (step 5).
- **A warning about a damaged save file:** that one file was set aside in
  `~/deadblocks-server/worlds/main/damaged/` and the rest of the world loaded. If something is
  missing, `dbctl restore` an older backup.
- **"watchdog: … restarting it"** in the log: the server stopped responding, so it was
  restarted from its last save (at most a minute lost). If you see this, paste the log lines
  around it to Claude: `journalctl -u deadblocks -u deadblocks-watchdog --since today | grep -B30 watchdog`.
- **The full log:** `journalctl -u deadblocks --since today`.

## Where everything is
```
~/deadblocks-server/
  DeadBlocksServer.arm64      the server (DeadBlocksServer.arm64.old: the one before the last update)
  server.cfg                  settings
  dbctl, update.sh            the tools above (dbctl also works from anywhere)
  worlds/main/                the world: world.json, players/, chunks/
  backups/                    zips of the world, newest 20 plus one a day for 14 days
  status.json                 what dbctl status shows, written every minute
```
The service is `/etc/systemd/system/deadblocks.service`, plus `deadblocks-backup.timer` for the
daily backup and `deadblocks-watchdog.timer`, which checks every 15 s that the server still
responds.

**Installed from the git checkout instead?** `~/deadblocks/tools/pi/install.sh` installs the same
service using the Godot program from the benchmark guide (`~/godot/...`) and the code in
`~/deadblocks`; `update.sh` then pulls the newest code with git. The zip is faster on the Pi (it
is a release build), so prefer it.
