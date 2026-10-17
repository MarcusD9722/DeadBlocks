#!/usr/bin/env bash
# The gate every change must pass. Each stage fails on a non-zero exit, a timeout, a missing DONE
# line, any FAIL line, or any ERROR / SCRIPT ERROR line in its log (the autotest alone can say
# fails=0 while thousands of errors scroll past).
# Usage: GODOT=/path/to/godot ./tools/test_all.sh [--quick]
#   --quick skips the exports, the Pi terrain check, the Pi server network test and the benchmark
#   smoke run.
# Logs: build/test_logs/<stage>.log. Don't run benchmarks at the same time.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
LOG_DIR="$PWD/build/test_logs"
mkdir -p "$LOG_DIR"
rm -f "$LOG_DIR"/*.log
QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1
fails=0

# stage NAME DONE_TEXT SECONDS command...
stage() {
	local name=$1 done_text=$2 secs=$3
	shift 3
	local log="$LOG_DIR/$name.log" rc=0 why=""
	printf '%-24s' "$name"
	timeout --foreground "$secs" "$@" > "$log" 2>&1 || rc=$?
	[ "$rc" -eq 124 ] && why="timed out after ${secs}s" || { [ "$rc" -ne 0 ] && why="exit code $rc"; }
	grep -q -F "$done_text" "$log" || why="${why:+$why, }no '$done_text' line"
	grep -q -E '^FAIL |^[A-Z]+ FAIL|fails=[1-9]' "$log" && why="${why:+$why, }FAIL lines"
	grep -q -E '^(ERROR|SCRIPT ERROR|USER ERROR)' "$log" && why="${why:+$why, }ERROR lines"
	if [ -z "$why" ]; then
		echo "ok"
	else
		echo "FAILED ($why) - see $log"
		fails=$((fails + 1))
	fi
}

"$GODOT" --headless --path . --import > "$LOG_DIR/import.log" 2>&1 || true

stage autotest "AUTOTEST DONE fails=0" 600 "$GODOT" --headless --path . -- --autotest --seed=4242
stage regiontest_forward "REGIONTEST DONE" 600 "$GODOT" --headless --path . -- --regiontest --server-mode --seed=4242 --region-order=forward
stage regiontest_reverse "REGIONTEST DONE" 600 "$GODOT" --headless --path . -- --regiontest --server-mode --seed=4242 --region-order=reverse
h1=$(sed -n 's/^REGIONTEST order=.* hash=//p' "$LOG_DIR/regiontest_forward.log")
h2=$(sed -n 's/^REGIONTEST order=.* hash=//p' "$LOG_DIR/regiontest_reverse.log")
printf '%-24s' "regiontest_same_result"
if [ -n "$h1" ] && [ "$h1" = "$h2" ]; then echo "ok"; else echo "FAILED (forward $h1 vs reverse $h2)"; fails=$((fails + 1)); fi

stage nettest "NETTEST ALL DONE fails=0" 900 env GODOT="$GODOT" NETTEST_LOGS="$LOG_DIR/nettest" ./tools/run_nettest.sh

if [ "$QUICK" -eq 0 ]; then
	stage exports "Built version" 1800 env GODOT="$GODOT" ./tools/build_release.sh
	stage worldgen_pc_vs_pi "WORLDGEN CHECK DONE" 1200 env GODOT="$GODOT" ./tools/check_worldgen.sh
	# The same multiplayer test against the exported Raspberry Pi server (arm64, under qemu).
	if command -v qemu-aarch64-static >/dev/null && [ -d /usr/aarch64-linux-gnu ]; then
		stage nettest_pi_server "NETTEST ALL DONE fails=0" 1500 env GODOT="$GODOT" NETTEST_LOGS="$LOG_DIR/nettest_pi" \
			./tools/run_nettest.sh qemu-aarch64-static -L /usr/aarch64-linux-gnu build/server/DeadBlocksServer.arm64 --headless --
	fi
	stage bench_smoke "=== END ===" 900 "$GODOT" --headless --path . -- --bench --server-mode --bench-secs=4 --seed=4242 --out="$LOG_DIR/bench_smoke.txt"
fi

echo
if [ "$fails" -eq 0 ]; then
	echo "TEST_ALL PASSED"
else
	echo "TEST_ALL FAILED: $fails stage(s)"
	exit 1
fi
