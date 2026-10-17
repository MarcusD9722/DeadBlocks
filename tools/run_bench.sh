#!/usr/bin/env bash
# Runs the server benchmark once per physics setup and prints one results block, also saved to
# bench_results/summary.txt. Usage (from anywhere):
#   GODOT=/path/to/godot ./tools/run_bench.sh [extra bench args, e.g. --bench-secs=30]
#   BENCH_SETUPS=m1 GODOT=... ./tools/run_bench.sh    only the two M1 server setups (about 9 minutes)
# Every run uses world seed 4242 so runs and machines are comparable (pass --seed=N to change it).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT_DIR="$PWD/bench_results"
mkdir -p "$OUT_DIR"

echo "Importing project..."
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

# Each setup is "physics engine|physics ticks per second|extra args|physics thread (yes/no)".
# override.cfg applies one setup for one run and is always removed afterwards. The first three are
# the M0 setups (kept so results stay comparable); the last two are the M1 server (Jolt at 30
# ticks/s in server mode), without and with physics on its own thread.
M0_SETUPS=("GodotPhysics3D|60||no" "Jolt Physics|60||no" "Jolt Physics|30||no")
M1_SETUPS=("Jolt Physics|30|--server-mode|no" "Jolt Physics|30|--server-mode|yes")
if [ "${BENCH_SETUPS:-all}" = "m1" ]; then
	SETUPS=("${M1_SETUPS[@]}")
else
	SETUPS=("${M0_SETUPS[@]}" "${M1_SETUPS[@]}")
fi
SAMPLER_PID=""
cleanup() {
	rm -f override.cfg
	if [ -n "$SAMPLER_PID" ]; then kill "$SAMPLER_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT
# Exit on Ctrl+C, a closed terminal or kill, so the EXIT cleanup always runs.
trap 'exit 130' INT
trap 'exit 129' HUP
trap 'exit 143' TERM
rm -f "$OUT_DIR"/bench_*.txt "$OUT_DIR"/log_*.txt "$OUT_DIR"/pi_*.txt "$OUT_DIR"/summary.txt

# On a Raspberry Pi, record CPU temperature, clock and the current throttling bits every 5 s while
# a run is going. Bits 0x1-0x8 mean under-voltage, frequency capped, throttled, soft temperature limit.
sample_pi() {
	while true; do
		local t
		t=$(vcgencmd get_throttled | cut -d= -f2)
		echo "$(vcgencmd measure_temp | tr -dc '0-9.') $(vcgencmd measure_clock arm | cut -d= -f2) $(( t & 0xF ))"
		sleep 5
	done
}

# Allow each run three times --bench-secs (default 60) plus 10 minutes for loading and setup.
secs=60
for a in "$@"; do
	case "$a" in --bench-secs=*) secs="${a#--bench-secs=}" ;; esac
done
limit=$(( ${secs%.*} * 3 + 600 ))

n=0
for setup in "${SETUPS[@]}"; do
	n=$((n + 1))
	IFS='|' read -r engine tps extra thread <<< "$setup"
	thread_on=false
	[ "$thread" = "yes" ] && thread_on=true
	printf '[physics]\n3d/physics_engine="%s"\ncommon/physics_ticks_per_second=%s\n3d/run_on_separate_thread=%s\n' \
		"$engine" "$tps" "$thread_on" > override.cfg
	label="$engine at $tps ticks/s${extra:+ ($extra)}"
	if [ "$thread_on" = true ]; then label="$label + physics thread"; fi
	echo "[$n/${#SETUPS[@]}] Running benchmark with $label (about 4 minutes)..."
	if command -v vcgencmd >/dev/null 2>&1; then
		sample_pi > "$OUT_DIR/pi_$n.txt" &
		SAMPLER_PID=$!
	fi
	rc=0
	# shellcheck disable=SC2086 # $extra is empty or one flag
	timeout --foreground "$limit" "$GODOT" --headless --path . -- --bench --out="$OUT_DIR/bench_$n.txt" $extra "$@" --seed=4242 \
		> "$OUT_DIR/log_$n.txt" 2>&1 || rc=$?
	if [ -n "$SAMPLER_PID" ]; then
		kill "$SAMPLER_PID" 2>/dev/null || true
		wait "$SAMPLER_PID" 2>/dev/null || true
		SAMPLER_PID=""
	fi
	rm -f override.cfg
	if [ ! -s "$OUT_DIR/bench_$n.txt" ]; then
		why="exit code $rc"
		if [ "$rc" -eq 124 ]; then why="TIMED OUT after $limit s"; fi
		{
			echo "=== RUN $n ($label) FAILED, $why. Last lines of its log: ==="
			tail -n 30 "$OUT_DIR/log_$n.txt"
		} > "$OUT_DIR/bench_$n.txt"
	fi
	if [ -s "$OUT_DIR/pi_$n.txt" ]; then
		awk '{ if ($1 > t) t = $1; c = $2 / 1000000; if (c > hi) hi = c; if ($3 != 0) thr = 1 }
			END { printf "pi during this run: max temp %.1f C, top CPU clock %d MHz, throttled: %s\n", t, hi, thr ? "YES" : "no" }' \
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
