#!/usr/bin/env bash
# The gate every change must pass. Each stage fails on a non-zero exit, a timeout, a missing DONE
# line, any FAIL line, or any ERROR / SCRIPT ERROR line in its log (the autotest alone can say
# fails=0 while thousands of errors scroll past).
# Usage: GODOT=/path/to/godot ./tools/test_all.sh [--quick]
#   --quick skips the exports, the Pi terrain check, the Pi server network test, the Pi package
#   test and the benchmark smoke run.
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

stage autotest "AUTOTEST DONE fails=0" 900 "$GODOT" --headless --path . -- --autotest --seed=4242
stage savetest "SAVETEST DONE fails=0" 120 "$GODOT" --headless --path . -- --savetest
stage regiontest_forward "REGIONTEST DONE" 600 "$GODOT" --headless --path . -- --regiontest --server-mode --seed=4242 --region-order=forward
stage regiontest_reverse "REGIONTEST DONE" 600 "$GODOT" --headless --path . -- --regiontest --server-mode --seed=4242 --region-order=reverse
h1=$(sed -n 's/^REGIONTEST order=.* hash=//p' "$LOG_DIR/regiontest_forward.log")
h2=$(sed -n 's/^REGIONTEST order=.* hash=//p' "$LOG_DIR/regiontest_reverse.log")
printf '%-24s' "regiontest_same_result"
if [ -n "$h1" ] && [ "$h1" = "$h2" ]; then echo "ok"; else echo "FAILED (forward $h1 vs reverse $h2)"; fails=$((fails + 1)); fi
stage typetest "TYPETEST DONE fails=0" 600 "$GODOT" --headless --path . -- --typetest --server-mode --seed=4242

# The full gate runs the 3-player building soak for 60 s, the Blood Moon soak for 120 s (the
# plan's targets) and 6 server crashes in the saving test; --quick 20 s, 20 s and 3 crashes.
SOAK_S=60
HORDE_S=120
CRASHES=6
[ "$QUICK" -eq 1 ] && SOAK_S=20 && HORDE_S=20 && CRASHES=3
stage nettest "NETTEST ALL DONE fails=0" 1800 env GODOT="$GODOT" NETTEST_LOGS="$LOG_DIR/nettest" NETTEST_SOAK_S=$SOAK_S NETTEST_HORDE_S=$HORDE_S \
	NETTEST_CRASHES=$CRASHES ./tools/run_nettest.sh

if [ "$QUICK" -eq 0 ]; then
	stage exports "Built version" 1800 env GODOT="$GODOT" ./tools/build_release.sh
	stage worldgen_pc_vs_pi "WORLDGEN CHECK DONE" 1200 env GODOT="$GODOT" ./tools/check_worldgen.sh
	# The same multiplayer test against the exported Raspberry Pi server (arm64, under qemu).
	if command -v qemu-aarch64-static >/dev/null && [ -d /usr/aarch64-linux-gnu ]; then
		stage nettest_pi_server "NETTEST ALL DONE fails=0" 1800 env GODOT="$GODOT" NETTEST_LOGS="$LOG_DIR/nettest_pi" NETTEST_SOAK_S=20 NETTEST_HORDE_S=30 NETTEST_CRASHES=3 \
			./tools/run_nettest.sh qemu-aarch64-static -L /usr/aarch64-linux-gnu build/server/DeadBlocksServer.arm64 --headless --
		# The Pi package: install.sh, dbctl and update.sh, with the arm64 server under qemu.
		stage pi_package "PIPKG DONE fails=0" 900 env GODOT="$GODOT" ./tools/test_pi_package.sh
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
