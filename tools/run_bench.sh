#!/usr/bin/env bash
# Runs the server benchmark once per physics setup and prints one results block, also saved to
# bench_results/summary.txt. Usage (from anywhere):
#   GODOT=/path/to/godot ./tools/run_bench.sh [extra bench args, e.g. --bench-secs=30]
# Every run uses world seed 4242 so runs and machines are comparable (pass --seed=N to change it).
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
SAMPLER_PID=""
cleanup() {
	rm -f override.cfg
	if [ -n "$SAMPLER_PID" ]; then kill "$SAMPLER_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT
rm -f "$OUT_DIR"/bench_*.txt "$OUT_DIR"/log_*.txt "$OUT_DIR"/pi_*.txt "$OUT_DIR"/summary.txt

# On a Raspberry Pi, record CPU temperature and clock every 5 s while a run is going.
sample_pi() {
	while true; do
		echo "$(vcgencmd measure_temp | tr -dc '0-9.') $(vcgencmd measure_clock arm | cut -d= -f2)"
		sleep 5
	done
}

n=0
for setup in "${SETUPS[@]}"; do
	n=$((n + 1))
	engine="${setup%%|*}"
	tps="${setup##*|}"
	printf '[physics]\n3d/physics_engine="%s"\ncommon/physics_ticks_per_second=%s\n' "$engine" "$tps" > override.cfg
	echo "[$n/${#SETUPS[@]}] Running benchmark with $engine at $tps ticks/s (about 4 minutes)..."
	if command -v vcgencmd >/dev/null 2>&1; then
		sample_pi > "$OUT_DIR/pi_$n.txt" &
		SAMPLER_PID=$!
	fi
	rc=0
	timeout 900 "$GODOT" --headless --path . -- --bench --out="$OUT_DIR/bench_$n.txt" "$@" --seed=4242 \
		> "$OUT_DIR/log_$n.txt" 2>&1 || rc=$?
	if [ -n "$SAMPLER_PID" ]; then
		kill "$SAMPLER_PID" 2>/dev/null || true
		wait "$SAMPLER_PID" 2>/dev/null || true
		SAMPLER_PID=""
	fi
	rm -f override.cfg
	if [ ! -s "$OUT_DIR/bench_$n.txt" ]; then
		{
			echo "=== RUN $n ($engine at $tps ticks/s) FAILED, exit code $rc. Last lines of its log: ==="
			tail -n 30 "$OUT_DIR/log_$n.txt"
		} > "$OUT_DIR/bench_$n.txt"
	fi
	if [ -s "$OUT_DIR/pi_$n.txt" ]; then
		awk '{ if ($1 > t) t = $1; c = $2 / 1000000; if (lo == "" || c < lo) lo = c; if (c > hi) hi = c }
			END { printf "pi during this run: max temp %.1f C, CPU clock %d-%d MHz\n", t, lo, hi }' \
			"$OUT_DIR/pi_$n.txt" >> "$OUT_DIR/bench_$n.txt"
	fi
done

{
	echo "################ COPY EVERYTHING BELOW THIS LINE ################"
	cat "$OUT_DIR"/bench_*.txt
	if command -v vcgencmd >/dev/null 2>&1; then
		echo "pi: $(vcgencmd get_throttled) (0x0 = never throttled or under-voltage since boot)"
	fi
	echo "################ COPY EVERYTHING ABOVE THIS LINE ################"
} | tee "$OUT_DIR/summary.txt"
echo "These results are also saved in $OUT_DIR/summary.txt"
