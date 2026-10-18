# Running the server benchmark on the Raspberry Pi

This measures whether the Pi can run the Dead Blocks server. It simulates:
- a Blood Moon: 120 zombies attacking a walled base,
- 7 players sprinting into new land in different directions,
- both at the same time.

It runs five times, once per setup, and takes about **22 minutes** in total: the three setups from M0, then the M1 server without and with physics on its own thread. To run only the two M1 setups (about **9 minutes**), put `BENCH_SETUPS=m1 ` in front of the run command in step 4. Every run uses the same world (seed 4242), so the numbers can be compared with other machines.

## What you need
- Raspberry Pi 5 with **64-bit** Raspberry Pi OS.
- Internet access and about 1 GB of free space.
- A cooler on the Pi. Without one it slows itself down when hot, and the numbers come out worse than they really are.

You can type these commands on the Pi directly or over SSH.

## 1. Install the tools
```bash
sudo apt update
sudo apt install -y git unzip wget tmux
```

## 2. Download the game code
**If the GitHub repository is public**, this is all you need:
```bash
git clone https://github.com/MarcusD9722/DeadBlocks ~/deadblocks
```

**If the repository is private**, the Pi has to sign in to GitHub once first:
```bash
sudo apt install -y gh
gh auth login
```
Pick **GitHub.com**, then **HTTPS**, then answer **Yes** to "authenticate Git", then **Login with a web browser**.
1. It shows an 8-character code and says *Press Enter to open github.com in your browser*. Press **Enter** on the Pi.
2. If it then says it **failed to open a web browser**, that's fine. On your phone or PC, open https://github.com/login/device, sign in, and type the code.
3. Wait until the Pi prints **Logged in as …**, then run:
```bash
gh repo clone MarcusD9722/DeadBlocks ~/deadblocks
```

## 3. Download Godot for the Pi
```bash
mkdir -p ~/godot && cd ~/godot
wget https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.arm64.zip
unzip Godot_v4.7.2-stable_linux.arm64.zip
chmod +x Godot_v4.7.2-stable_linux.arm64
```

## 4. Run the benchmark
If you're on SSH, start `tmux` first, so the run survives if your connection drops:
```bash
tmux
```
Then:
```bash
cd ~/deadblocks
GODOT=~/godot/Godot_v4.7.2-stable_linux.arm64 ./tools/run_bench.sh
```
Leave the Pi alone while it runs, since other heavy programs skew the numbers. It prints `[1/5]`, `[2/5]` … as it goes. To stop it early, press **Ctrl+C**.

## 5. Send back the results
The results block is long, and scrolling up inside tmux doesn't work the normal way. So when the run finishes:
1. Type `exit` to leave tmux (only if you started it).
2. Show the saved results:
   ```bash
   cat ~/deadblocks/bench_results/summary.txt
   ```
3. Copy everything between the two `####### COPY …` lines and paste it to Claude.

If a run crashed, its section says **FAILED** and includes the error. Paste that as it is, too.

## Running it again later
Steps 1–3 are only needed the first time. To run the latest version of the benchmark again:
```bash
cd ~/deadblocks
git pull
```
Then go straight to step 4.

If your copy was cloned from the old `m0-stress-test` branch, switch it to `main` once, first: `git fetch origin && git checkout main`.

## If something goes wrong
- **"Permission denied" on `run_bench.sh`:** run `chmod +x tools/run_bench.sh` and try again.
- **SSH dropped mid-run:** log back in and run `tmux attach`.
- **Shorter test run:** add `--bench-secs=20` at the end of the run command. The numbers get noisier, and the combined scenario comes out a little optimistic.

## Reading the results
- **load:** how much of one CPU core the game's main thread used. Under 50% is **OK**, 50–85% is **TIGHT**, and over 85% is **OVERLOADED**, meaning the server falls behind and the game slows down for everyone.
- **ticks/s:** how many simulation steps per second the server managed. It should match the target (60 or 30).
- **chunk cost:** time to create one piece of terrain, split into the part done on background threads and the part done on the main thread. Comparing these between machines shows how much faster or slower the Pi is.
- **waiting on chunks:** how often a sprinting player would have to wait for terrain to load. Ideally 0%.
- **pi during this run:** the hottest the CPU got, its top clock speed, and whether it **throttled**, meaning it slowed itself down because of heat or a weak power supply. The clock dropping during quiet moments is normal. Only `throttled: YES` is a problem; if you see it, improve the cooling or use the official 27 W power supply and run it again.
