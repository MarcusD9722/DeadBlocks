#!/usr/bin/env bash
# Runs the server benchmark once per 3D physics engine and prints both results.
# Usage (from anywhere):
#   GODOT=/path/to/godot ./tools/run_bench.sh [extra bench args, e.g. --bench-secs=30]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT_DIR="$PWD/bench_results"
mkdir -p "$OUT_DIR"

echo "Importing project..."
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

# Each setup is "physics engine|physics ticks per second". override.cfg applies one setup
# for one run and is always removed afterwards.
SETUPS=("GodotPhysics3D|60" "Jolt Physics|60" "Jolt Physics|30")
trap 'rm -f override.cfg' EXIT
rm -f "$OUT_DIR"/bench_*.txt "$OUT_DIR"/log_*.txt
n=0
for setup in "${SETUPS[@]}"; do
	n=$((n + 1))
	engine="${setup%%|*}"
	tps="${setup##*|}"
	printf '[physics]\n3d/physics_engine="%s"\ncommon/physics_ticks_per_second=%s\n' "$engine" "$tps" > override.cfg
	echo "[$n/${#SETUPS[@]}] Running benchmark with $engine at $tps ticks/s (about 4 minutes)..."
	"$GODOT" --headless --path . -- --bench --out="$OUT_DIR/bench_$n.txt" "$@" > "$OUT_DIR/log_$n.txt" 2>&1 || true
	rm -f override.cfg
done

echo
echo "################ COPY EVERYTHING BELOW THIS LINE ################"
cat "$OUT_DIR"/bench_*.txt 2>/dev/null || echo "No results found. See $OUT_DIR/log_*.txt"
if command -v vcgencmd >/dev/null 2>&1; then
	echo "pi: $(vcgencmd measure_temp) | $(vcgencmd measure_clock arm) | $(vcgencmd get_throttled)"
fi
echo "################ COPY EVERYTHING ABOVE THIS LINE ################"
