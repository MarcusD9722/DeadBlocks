#!/usr/bin/env bash
# Multiplayer test: starts a dedicated server and headless clients on this machine and checks
# login, refusals, movement sync, chat, admin commands, cheat correction, rejoining, crash
# recovery, the player limit, and that the clock stops while nobody is online.
# Usage: GODOT=/path/to/godot ./tools/run_nettest.sh [SERVER PREFIX...]
#   The server runs as "$GODOT --headless --path . --" unless a prefix is given, for example
#   qemu-aarch64-static -L /usr/aarch64-linux-gnu build/server/DeadBlocksServer.arm64 --headless --
#   NETTEST_LOGS=DIR picks the log folder (default build/test_logs/nettest).
# Ends with "NETTEST ALL DONE fails=N".
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
LOG_DIR="${NETTEST_LOGS:-$PWD/build/test_logs/nettest}"
mkdir -p "$LOG_DIR"
rm -f "$LOG_DIR"/*.log
PORT=$((30000 + RANDOM % 20000))
fails=0
SERVER=("$GODOT" --headless --path . --)
[ $# -gt 0 ] && SERVER=("$@")
CLIENT=("$GODOT" --headless --path . --)

pass() { echo "NETTEST PASS $*"; }
fail() { echo "NETTEST FAIL $*"; fails=$((fails + 1)); }

# wait_line FILE TEXT SECONDS
wait_line() {
	local i
	for ((i = 0; i < $3 * 10; i++)); do
		grep -q -F -- "$2" "$1" 2>/dev/null && return 0
		sleep 0.1
	done
	return 1
}

# client LOGNAME NAME PIN PASSWORD ROLE [extra args...]  (runs in the background, sets CPID)
client() {
	local log=$1 name=$2 pin=$3 pw=$4 role=$5
	shift 5
	"${CLIENT[@]}" --connect=127.0.0.1:$PORT --name="$name" --pin="$pin" --password="$pw" \
		--nettest="$role" --radius=3 "$@" > "$LOG_DIR/$log.log" 2>&1 &
	CPID=$!
}

# finished LOGNAME: the client printed DONE with no failures
finished() {
	local log="$LOG_DIR/$1.log"
	grep -q "NETTEST DONE fails=0" "$log" && ! grep -q -E '^(ERROR|SCRIPT ERROR)' "$log"
}

report() {
	local log="$LOG_DIR/$1.log"
	if finished "$1"; then
		pass "$1"
	else
		fail "$1 (see $log)"
		grep -E "NETTEST (FAIL|status)|ERROR" "$log" | head -8 | sed 's/^/    /'
	fi
}

# time_values ONLINE: the clock values the server printed while ONLINE players were online
time_values() {
	sed -n "s/^TIME day=[0-9]* time=\([0-9.]*\) online=$1\$/\1/p" "$LOG_DIR/server.log"
}

cleanup() {
	kill $(jobs -p) 2>/dev/null
	wait 2>/dev/null
}
trap cleanup EXIT

"${SERVER[@]}" --server --port=$PORT --password=pw --max-players=2 --seed=4242 --test-log \
	--admins=alice > "$LOG_DIR/server.log" 2>&1 &
SPID=$!
if ! wait_line "$LOG_DIR/server.log" "listening on UDP" 120; then
	fail "server started (see $LOG_DIR/server.log)"
	echo "NETTEST ALL DONE fails=$fails"
	exit 1
fi
pass "server listening on UDP $PORT"

# 1. Two players walk, chat and see each other.
client alice alice 1234 pw a
A=$CPID
client bob bob 5678 pw b
B=$CPID
wait $A
wait $B
report alice
report bob
final=$(sed -n 's/^NETTEST final_pos=//p' "$LOG_DIR/alice.log")

# 2. Nobody online: the clock must stand still.
sleep 5
mapfile -t idle < <(time_values 0 | tail -2)
if [ ${#idle[@]} -eq 2 ] && [ "${idle[0]}" = "${idle[1]}" ]; then
	pass "clock stopped while nobody was online (${idle[1]})"
else
	fail "clock stopped while nobody was online (${idle[*]:-no TIME lines})"
fi

# 3. Alice comes back where she left, and the clock runs again.
client alice_rejoin alice 1234 pw join --nettest-expect="$final"
wait $CPID
report alice_rejoin
mapfile -t busy < <(time_values 1 | tail -2)
if [ ${#busy[@]} -eq 2 ] && awk "BEGIN{exit !(${busy[1]} > ${busy[0]})}"; then
	pass "clock ran while a player was online (${busy[0]} -> ${busy[1]})"
else
	fail "clock ran while a player was online (${busy[*]:-no TIME lines})"
fi

# 4. Logins the server must refuse, each with a clear reason.
client reject_password carol 1111 wrong "reject:Wrong server password"
wait $CPID
report reject_password
client reject_name "a b" 1111 pw "reject:Names are 3-16"
wait $CPID
report reject_name
client reject_pin alice 9999 pw "reject:Wrong PIN for alice"
wait $CPID
report reject_pin
client reject_version dave 1111 pw "reject:Version mismatch" --fake-version=0.0.1
wait $CPID
report reject_version
client reject_terrain dave 1111 pw "reject:Terrain mismatch" --fake-terrain
wait $CPID
report reject_terrain

# 5. Full server, then a crash: alice's game dies without saying goodbye and she rejoins at once.
client hold_alice alice 1234 pw hold
HA=$CPID
client hold_bob bob 5678 pw hold
HB=$CPID
if wait_line "$LOG_DIR/hold_alice.log" "NETTEST online" 90 && wait_line "$LOG_DIR/hold_bob.log" "NETTEST online" 90; then
	pass "two players holding the server"
else
	fail "two players holding the server (see hold_alice.log / hold_bob.log)"
fi
client reject_full carol 1111 pw "reject:The server is full"
wait $CPID
report reject_full
kill -9 $HA 2>/dev/null
wait $HA 2>/dev/null
client alice_after_crash alice 1234 pw join
wait $CPID
report alice_after_crash
if grep -q "alice signed in again" "$LOG_DIR/server.log"; then
	pass "server replaced the crashed session"
else
	fail "server replaced the crashed session"
fi
kill $HB 2>/dev/null
wait $HB 2>/dev/null

# 6. "Host game": the game starts its own server in the background, joins it, and the server
# stops when the game closes.
HPORT=$((PORT + 1))
"${CLIENT[@]}" --nettest=host --nettest-port=$HPORT --radius=3 > "$LOG_DIR/host.log" 2>&1
report host
hpid=$(sed -n 's/^NETTEST host_pid=//p' "$LOG_DIR/host.log")
for ((i = 0; i < 50; i++)); do
	[ -n "$hpid" ] && kill -0 "$hpid" 2>/dev/null || break
	sleep 0.1
done
if [ -n "$hpid" ] && ! kill -0 "$hpid" 2>/dev/null; then
	pass "the hosted server stopped with the game"
else
	fail "the hosted server stopped with the game (pid ${hpid:-unknown})"
	[ -n "$hpid" ] && kill "$hpid" 2>/dev/null
fi

# 7. The hosting game crashes: its server must notice the host is gone and stop by itself
# (otherwise it would keep the port busy and block hosting again).
"${CLIENT[@]}" --nettest=host --nettest-crash --nettest-port=$((PORT + 2)) --radius=3 > "$LOG_DIR/host_crash.log" 2>&1 &
HC=$!
if wait_line "$LOG_DIR/host_crash.log" "NETTEST online" 90; then
	hpid=$(sed -n 's/^NETTEST host_pid=//p' "$LOG_DIR/host_crash.log")
	kill -9 $HC 2>/dev/null
	wait $HC 2>/dev/null
	for ((i = 0; i < 450; i++)); do
		kill -0 "$hpid" 2>/dev/null || break
		sleep 0.1
	done
	if ! kill -0 "$hpid" 2>/dev/null && grep -q "the host (hoster) is gone; stopping" "$LOG_DIR/host_crash.log"; then
		pass "the hosted server stopped by itself after the game crashed"
	else
		fail "the hosted server stopped by itself after the game crashed (pid $hpid)"
		kill "$hpid" 2>/dev/null
	fi
else
	fail "hosted a game for the crash test (see host_crash.log)"
	kill -9 $HC 2>/dev/null
fi

for f in "$LOG_DIR"/server.log "$LOG_DIR"/hold_*.log "$LOG_DIR"/host_crash.log; do
	if grep -q -E '^(ERROR|SCRIPT ERROR|USER ERROR)' "$f"; then
		fail "no errors in $(basename "$f")"
		grep -E '^(ERROR|SCRIPT ERROR|USER ERROR)' "$f" | head -5 | sed 's/^/    /'
	fi
done
kill $SPID 2>/dev/null
echo "NETTEST ALL DONE fails=$fails"
[ "$fails" -eq 0 ]
