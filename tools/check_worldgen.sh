#!/usr/bin/env bash
# Checks that the Raspberry Pi build generates exactly the same terrain as the PC: clients build
# terrain themselves from the seed, so any difference would put players in different worlds.
# Runs the editor (x86_64) and the exported arm64 server under qemu, and compares their hashes.
# Usage: GODOT=/path/to/godot ./tools/check_worldgen.sh   (export the arm64 server first)
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
ARM=build/server/DeadBlocksServer.arm64
if ! command -v qemu-aarch64-static >/dev/null || [ ! -d /usr/aarch64-linux-gnu ]; then
	echo "WORLDGEN SKIPPED: needs qemu-aarch64-static and /usr/aarch64-linux-gnu (apt: qemu-user-static libc6-arm64-cross)"
	echo "WORLDGEN CHECK DONE"
	exit 0
fi
[ -x "$ARM" ] || { echo "WORLDGEN FAIL: $ARM not found (run tools/build_release.sh)"; exit 1; }
pc=$("$GODOT" --headless --path . -- --worldgen-hash --seed=4242 2>&1 | sed -n 's/^WORLDGEN v[0-9]* chunks=.* hash=//p' | tr '\n' ' ')
pi=$(qemu-aarch64-static -L /usr/aarch64-linux-gnu "$ARM" --headless -- --worldgen-hash --seed=4242 2>&1 | sed -n 's/^WORLDGEN v[0-9]* chunks=.* hash=//p' | tr '\n' ' ')
echo "pc (x86_64 editor): $pc"
echo "pi (arm64 export):  $pi"
if [ -n "$pc" ] && [ "$pc" = "$pi" ]; then
	echo "WORLDGEN MATCH"
else
	echo "WORLDGEN FAIL: hashes differ or missing"
	exit 1
fi
echo "WORLDGEN CHECK DONE"
