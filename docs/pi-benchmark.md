# Running the server benchmark on the Raspberry Pi

This measures whether the Pi can run the Dead Blocks server. It simulates:
- a Blood Moon: 120 zombies attacking a walled base,
- 7 players sprinting into new land in different directions,
- both at the same time.

It runs three times, once per physics setup, and takes about **13 minutes** in total. Nothing is installed system-wide except a few standard packages.

## What you need
- Raspberry Pi 5 with **64-bit** Raspberry Pi OS.
- Internet access and about 1 GB of free space.
- A cooler on the Pi. Without one it slows itself down when hot, and the numbers come out worse than they really are.

You can type these commands on the Pi directly or over SSH.

## 1. Install the tools
```bash
sudo apt update
sudo apt install -y git unzip wget gh tmux
```

## 2. Sign in to GitHub
The repository is private, so the Pi needs to sign in once:
```bash
gh auth login
```
Pick **GitHub.com**, then **HTTPS**, then answer **Yes** to "authenticate Git", then **Login with a web browser**. It shows an 8-character code. On your phone or PC, open https://github.com/login/device, sign in, and enter the code.

## 3. Download the game code
```bash
gh repo clone MarcusD9722/deadblocks ~/deadblocks -- --branch m0-stress-test
```
(Once the benchmark is merged into `main`, leave off everything after `~/deadblocks`.)

## 4. Download Godot for the Pi
```bash
mkdir -p ~/godot && cd ~/godot
wget https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.arm64.zip
unzip Godot_v4.7.2-stable_linux.arm64.zip
chmod +x Godot_v4.7.2-stable_linux.arm64
```

## 5. Run the benchmark
If you're on SSH, start `tmux` first, so the run survives if your connection drops:
```bash
tmux
```
Then:
```bash
cd ~/deadblocks
GODOT=~/godot/Godot_v4.7.2-stable_linux.arm64 ./tools/run_bench.sh
```
Leave the Pi alone while it runs, since other heavy programs skew the numbers. It prints `[1/3]`, `[2/3]` and `[3/3]` as it goes.

## 6. Send back the results
When it finishes, copy everything between the two `####### COPY …` lines and paste it to Claude. The same results are saved in `~/deadblocks/bench_results/`.

## If something goes wrong
- **"Permission denied" on `run_bench.sh`:** run `chmod +x tools/run_bench.sh` and try again.
- **"No results found":** send the last 40 lines of the first log: `tail -n 40 ~/deadblocks/bench_results/log_1.txt`
- **SSH dropped mid-run:** log back in and run `tmux attach`.
- **Shorter test run:** add `--bench-secs=20` at the end of the run command. The numbers get noisier.

## Reading the results
- **load:** how much of one CPU core the game's main thread used. Under 50% is **OK**, 50–85% is **TIGHT**, and over 85% is **OVERLOADED**, meaning the server falls behind and the game slows down for everyone.
- **ticks/s:** how many simulation steps per second the server managed. It should match the target (60 or 30).
- **chunk cost:** time to create one piece of terrain. Comparing this number between machines shows how much faster or slower the Pi is.
- **waiting on chunks:** how often a sprinting player would have to wait for terrain to load. Ideally 0%.
