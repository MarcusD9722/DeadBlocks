#!/usr/bin/env bash
# Multiplayer test: starts a dedicated server and headless clients on this machine and checks
# login, refusals, movement sync, chat, admin commands, cheat correction, rejoining, crash
# recovery, the player limit, that the clock stops while nobody is online, riding out or
# reconnecting after a frozen server, building together, zombies, animals and a Blood Moon, and
# saving: restarts, crashes, damaged files and the control folder.
# NETTEST_SOAK_S sets the length of the 3-player building soak (default 20 s), NETTEST_HORDE_S
# that of the Blood Moon soak (default the same), NETTEST_CRASHES the number of kill -9 crashes
# in the saving test (default 3).
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
# Every test server saves into its own folder here, so they never share a world (or its lock).
rm -rf "${LOG_DIR:?}/data"
mkdir -p "$LOG_DIR/data"
PORT=$((30000 + RANDOM % 20000))
SOAK_S=${NETTEST_SOAK_S:-20}
HORDE_S=${NETTEST_HORDE_S:-$SOAK_S}
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
		grep -q "No answer from" "$log" && server_state
	fi
}

# A client couldn't reach the server: is it still running, and is it busy, waiting or stopped?
server_state() {
	echo "    server process $SPID:"
	ps -o pid=,stat=,pcpu=,etime= -p "$SPID" 2>/dev/null | sed 's/^/      /' || echo "      gone"
	for t in /proc/"$SPID"/task/*; do
		[ -r "$t/stat" ] && echo "      thread $(basename "$t"): state $(cut -d' ' -f3 "$t/stat") wchan $(cat "$t/wchan" 2>/dev/null)"
	done | head -12
	echo "      last log lines:"
	tail -3 "$LOG_DIR/server.log" | sed 's/^/        /'
	# Once per run: every thread's stack (under qemu these are qemu's own threads, which shows
	# whether the emulator or the game is stuck).
	if [ -z "${STACKS_DONE:-}" ] && command -v gdb > /dev/null && [ -d /proc/"$SPID" ]; then
		STACKS_DONE=1
		timeout 90 gdb -p "$SPID" -batch -ex "thread apply all bt 30" > "$LOG_DIR/server_stacks.txt" 2>&1
		echo "      thread stacks: $LOG_DIR/server_stacks.txt"
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

"${SERVER[@]}" --server --port=$PORT --data="$LOG_DIR/data/$PORT" --password=pw --max-players=2 --seed=4242 --test-log --no-spawns \
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
	# The connection times out after ~20 s, then the server waits 15 s for the host to return.
	for ((i = 0; i < 600; i++)); do
		kill -0 "$hpid" 2>/dev/null || break
		sleep 0.1
	done
	if ! kill -0 "$hpid" 2>/dev/null && grep -q "SERVER stopping (the host (hoster) is gone)" "$LOG_DIR/host_crash.log" \
		&& grep -q "^SERVER stopped$" "$LOG_DIR/host_crash.log"; then
		pass "the hosted server stopped by itself after the game crashed"
	else
		fail "the hosted server stopped by itself after the game crashed (pid $hpid)"
		kill "$hpid" 2>/dev/null
	fi
else
	fail "hosted a game for the crash test (see host_crash.log)"
	kill -9 $HC 2>/dev/null
fi

# 8. The server freezes (a Wi-Fi drop, an overloaded Pi): 8 s must not drop anyone; after 40 s
# the player is dropped, and gets back in by itself without reloading the world.
client stall_short alice 1234 pw stall
ST=$CPID
if wait_line "$LOG_DIR/stall_short.log" "NETTEST online" 90; then
	kill -STOP $SPID
	sleep 8
	kill -CONT $SPID
fi
wait $ST
report stall_short
client stall_long alice 1234 pw stall --nettest-stall=long
ST=$CPID
if wait_line "$LOG_DIR/stall_long.log" "NETTEST online" 90; then
	kill -STOP $SPID
	sleep 40
	kill -CONT $SPID
fi
wait $ST
report stall_long
if grep -q -E "alice (lost the connection \(nothing received|was replaced by a new sign-in)" "$LOG_DIR/server.log"; then
	pass "server logged why alice dropped"
else
	fail "server logged why alice dropped"
fi

# 9. Building together, on a second server with room for the soak players and admins for /give:
# mining and building seen by the other player, crafting at a workbench, eating, two players
# breaking the same block, a late joiner getting the edited chunks, and a soak test.
kill $SPID 2>/dev/null
PORT=$((PORT + 3))
"${SERVER[@]}" --server --port=$PORT --data="$LOG_DIR/data/$PORT" --password=pw --max-players=8 --seed=4242 --test-log --no-spawns \
	--admins=alice,soak1,soak2,soak3 > "$LOG_DIR/server_build.log" 2>&1 &
SPID=$!
if wait_line "$LOG_DIR/server_build.log" "listening on UDP" 120; then
	client builder alice 1234 pw builder
	A=$CPID
	client watcher bob 5678 pw watcher
	B=$CPID
	wait $A
	wait $B
	report builder
	report watcher
	built=$(sed -n 's/^NETTEST built_chunk=//p' "$LOG_DIR/builder.log")
	client builder_back alice 1234 pw join --nettest-has=110
	wait $CPID
	report builder_back
	client late carol 1111 pw late --nettest-expect="$built"
	wait $CPID
	report late
	pids=()
	for s in soak1 soak2 soak3; do
		client "$s" "$s" 1111 pw soak --nettest-soak="$SOAK_S"
		pids+=($CPID)
	done
	for pid in "${pids[@]}"; do wait "$pid"; done
	for s in soak1 soak2 soak3; do report "$s"; done
	grep -h "^NETTEST soak " "$LOG_DIR"/soak?.log | sed 's/^NETTEST /    /'
	grep -h "requests refused" "$LOG_DIR/server_build.log" | sed 's/^SERVER /    server: /'
else
	fail "building server started (see $LOG_DIR/server_build.log)"
fi

# 10. Zombies and animals: a fight seen by a second player (only the zombies the fighter spawns),
# then a Blood Moon with 3 players and the normal spawner on.
kill $SPID 2>/dev/null
PORT=$((PORT + 1))
"${SERVER[@]}" --server --port=$PORT --data="$LOG_DIR/data/$PORT" --password=pw --max-players=8 --seed=4242 --test-log --no-spawns \
	--admins=alice > "$LOG_DIR/server_fight.log" 2>&1 &
SPID=$!
if wait_line "$LOG_DIR/server_fight.log" "listening on UDP" 120; then
	client fighter alice 1234 pw fighter
	A=$CPID
	client zwatch bob 5678 pw zwatch
	B=$CPID
	wait $A
	wait $B
	report fighter
	report zwatch
else
	fail "fight server started (see $LOG_DIR/server_fight.log)"
fi
kill $SPID 2>/dev/null
PORT=$((PORT + 1))
"${SERVER[@]}" --server --port=$PORT --data="$LOG_DIR/data/$PORT" --password=pw --max-players=8 --seed=4242 --test-log \
	--admins=horde1,horde2,horde3 > "$LOG_DIR/server_mobs.log" 2>&1 &
SPID=$!
if wait_line "$LOG_DIR/server_mobs.log" "listening on UDP" 120; then
	pids=()
	for s in horde1 horde2 horde3; do
		client "$s" "$s" 1111 pw horde --nettest-soak="$HORDE_S"
		pids+=($CPID)
	done
	for pid in "${pids[@]}"; do wait "$pid"; done
	for s in horde1 horde2 horde3; do report "$s"; done
	grep -h "^NETTEST horde " "$LOG_DIR"/horde?.log | sed 's/^NETTEST /    /'
else
	fail "mob server started (see $LOG_DIR/server_mobs.log)"
fi

# 11. Saving. One world folder for all of these servers, saved every 2 s:
# - a clean stop from the control folder saves; the restart (with a different --seed, which a
#   saved world must ignore) gives back the player's place, items, blocks and the clock;
# - a second server can't open the same world;
# - repeated kill -9 crashes (some in the middle of a save) lose at most the last 2 s, the
#   world still loads, and the player's world matches the server's after reconnecting;
# - a damaged world.json stops the server with a clear message, a damaged chunk file is set
#   aside and the rest loads;
# - backup and reset-pin from the control folder.
kill $SPID 2>/dev/null
PORT=$((PORT + 1))
SAVE_DATA="$LOG_DIR/data/save"
CONTROL="$SAVE_DATA/control"
WORLD_DIR="$SAVE_DATA/worlds/main"
# save_server LOGNAME [extra args...]  (runs in the background, sets SPID)
save_server() {
	local log=$1
	shift
	"${SERVER[@]}" --server --port=$PORT --data="$SAVE_DATA" --password=pw --max-players=8 --test-log --no-spawns \
		--admins=alice,crash1 --autosave=2 "$@" > "$LOG_DIR/$log.log" 2>&1 &
	SPID=$!
}
# gone PID SECONDS: wait for a process to end
gone() {
	local i
	for ((i = 0; i < $2 * 10; i++)); do
		kill -0 "$1" 2>/dev/null || return 0
		sleep 0.1
	done
	return 1
}
# stop_cleanly LOGNAME: ask the server to stop through the control folder
stop_cleanly() {
	echo stop > "$CONTROL/stop.cmd"
	if gone "$SPID" 60 && grep -q "^SERVER stopped$" "$LOG_DIR/$1.log"; then
		pass "the server saved and stopped when asked ($1)"
	else
		fail "the server saved and stopped when asked ($1)"
		kill -9 "$SPID" 2>/dev/null
	fi
	wait "$SPID" 2>/dev/null
}
save_server server_save1 --seed=4242
if wait_line "$LOG_DIR/server_save1.log" "listening on UDP" 120; then
	client saver alice 1234 pw saver
	wait $CPID
	report saver
	saved=$(sed -n 's/^NETTEST saved //p' "$LOG_DIR/saver.log")
	s_pos=$(sed -n 's/.*pos=\([^ ]*\).*/\1/p' <<< "$saved")
	s_chunk=$(sed -n 's/.*chunk=\([^ ]*\).*/\1/p' <<< "$saved")
	s_hash=$(sed -n 's/.*hash=\([^ ]*\).*/\1/p' <<< "$saved")
	s_dirt=$(sed -n 's/.*dirt=\([^ ]*\).*/\1/p' <<< "$saved")
	sleep 3  # the clock stands still now; let it print once more
	clock1=$(sed -n 's/^TIME day=\([0-9]*\) time=\([0-9.]*\) online=0$/\1 \2/p' "$LOG_DIR/server_save1.log" | tail -1)
	stop_cleanly server_save1
	save_server server_save2 --seed=999
	if wait_line "$LOG_DIR/server_save2.log" "listening on UDP" 120; then
		if grep -q -E '^SERVER world "main" .*: loaded, seed 4242, .* 1 edited chunks, 1 players' "$LOG_DIR/server_save2.log"; then
			pass "the restarted server loaded the saved world (seed 4242, not 999)"
		else
			fail "the restarted server loaded the saved world: $(grep '^SERVER world' "$LOG_DIR/server_save2.log")"
		fi
		wait_line "$LOG_DIR/server_save2.log" "online=0" 10
		clock2=$(sed -n 's/^TIME day=\([0-9]*\) time=\([0-9.]*\) online=0$/\1 \2/p' "$LOG_DIR/server_save2.log" | head -1)
		if [ -n "$clock1" ] && [ "$clock1" = "$clock2" ]; then
			pass "the clock continues from where it was saved (day/time $clock2)"
		else
			fail "the clock continues from where it was saved (before: ${clock1:-none}, after: ${clock2:-none})"
		fi
		client save_back alice 1234 pw join --nettest-expect="$s_pos" --nettest-has=111 \
			--nettest-count=2:"$s_dirt" --nettest-hash="$s_chunk,$s_hash"
		wait $CPID
		report save_back
		# A second server on the same world must refuse to start.
		MAIN=$SPID
		PORT=$((PORT + 1))
		save_server server_save_dup --seed=4242
		if gone "$SPID" 60 && grep -q "Another server is already running this world" "$LOG_DIR/server_save_dup.log"; then
			pass "a second server can't open the same world"
		else
			fail "a second server can't open the same world (see server_save_dup.log)"
			kill -9 "$SPID" 2>/dev/null
		fi
		wait "$SPID" 2>/dev/null
		PORT=$((PORT - 1))
		SPID=$MAIN
	else
		fail "restarted save server (see $LOG_DIR/server_save2.log)"
	fi
	# Crashes: kill -9 the server CRASHES times while crash1 builds; restart it at once each time.
	CRASHES=${NETTEST_CRASHES:-3}
	client crasher crash1 1111 pw crasher --nettest-crashes=$CRASHES --nettest-soak=240
	CR=$CPID
	for ((r = 0; r < CRASHES; r++)); do
		if ! wait_line "$LOG_DIR/crasher.log" "NETTEST crasher online $r" 120; then
			fail "crasher back online after crash $r"
			break
		fi
		sleep $((3 + RANDOM % 4)).$((RANDOM % 10))
		kill -9 "$SPID" 2>/dev/null
		wait "$SPID" 2>/dev/null
		save_server "server_crash$((r + 1))" --seed=4242
		if ! wait_line "$LOG_DIR/server_crash$((r + 1)).log" "listening on UDP" 120; then
			fail "the server started again after crash $((r + 1)) (see server_crash$((r + 1)).log)"
			break
		fi
	done
	wait $CR
	report crasher
	grep -h "^NETTEST crasher:" "$LOG_DIR/crasher.log" | sed 's/^NETTEST /    /'
	grep -h "^SERVER taking over the lock" "$LOG_DIR"/server_crash*.log | head -1 | sed 's/^SERVER /    server: /'
	if grep -q "SERVER WARNING" "$LOG_DIR"/server_crash*.log; then
		fail "no damaged files after the crashes"
		grep -h "SERVER WARNING" "$LOG_DIR"/server_crash*.log | head -3 | sed 's/^/    /'
	else
		pass "no damaged files after $CRASHES crashes"
	fi
	stop_cleanly "server_crash$CRASHES"
	# Damage: first world.json (the server must refuse to start), then one chunk file.
	cp "$WORLD_DIR/world.json" "$LOG_DIR/world.json.good"
	printf '{"seed": 1, "day"' > "$WORLD_DIR/world.json"
	save_server server_damaged
	if gone "$SPID" 60 && grep -q "world.json is damaged. Restore the world from" "$LOG_DIR/server_damaged.log"; then
		pass "a damaged world.json stops the server with a clear message"
	else
		fail "a damaged world.json stops the server with a clear message (see server_damaged.log)"
		kill -9 "$SPID" 2>/dev/null
	fi
	wait "$SPID" 2>/dev/null
	cp "$LOG_DIR/world.json.good" "$WORLD_DIR/world.json"
	bad=$(ls "$WORLD_DIR/chunks" | head -1)
	n_chunks=$(ls "$WORLD_DIR/chunks" | wc -l)
	printf 'garbage' | dd of="$WORLD_DIR/chunks/$bad" bs=1 seek=60 conv=notrunc 2> /dev/null
	save_server server_save3
	if wait_line "$LOG_DIR/server_save3.log" "listening on UDP" 120; then
		if grep -q "Damaged save file $bad was moved to" "$LOG_DIR/server_save3.log" && [ -n "$(ls "$WORLD_DIR/damaged" 2>/dev/null)" ] \
			&& grep -q " $((n_chunks - 1)) edited chunks" "$LOG_DIR/server_save3.log"; then
			pass "a damaged chunk file was set aside and the other $((n_chunks - 1)) loaded"
		else
			fail "a damaged chunk file was set aside ($bad, $n_chunks chunks): $(grep -h 'SERVER world\|SERVER WARNING' "$LOG_DIR/server_save3.log")"
		fi
		# Control folder: a backup, and a PIN reset (alice signs in with a new PIN and keeps her things).
		n_backups=$(ls "$SAVE_DATA/backups" | wc -l)
		echo backup > "$CONTROL/b.cmd"
		if wait_line "$LOG_DIR/server_save3.log" "SERVER backup (asked for)" 15 && [ "$(ls "$SAVE_DATA/backups" | wc -l)" -gt "$n_backups" ]; then
			pass "backup from the control folder"
		else
			fail "backup from the control folder"
		fi
		echo "reset-pin alice" > "$CONTROL/r.cmd"
		if wait_line "$LOG_DIR/server_save3.log" "alice's PIN was reset" 15; then
			client pin_new alice 4321 pw join --nettest-has=111
			wait $CPID
			report pin_new
			client pin_old alice 1234 pw "reject:Wrong PIN for alice"
			wait $CPID
			report pin_old
		else
			fail "reset-pin from the control folder"
		fi
		if grep -q '"players"' "$SAVE_DATA/status.json" 2>/dev/null; then
			pass "status.json written"
		else
			fail "status.json written"
		fi
		stop_cleanly server_save3
	else
		fail "save server after damage (see $LOG_DIR/server_save3.log)"
	fi
else
	fail "save server started (see $LOG_DIR/server_save1.log)"
fi

for f in "$LOG_DIR"/server.log "$LOG_DIR"/server_build.log "$LOG_DIR"/server_fight.log "$LOG_DIR"/server_mobs.log \
	"$LOG_DIR"/server_save*.log "$LOG_DIR"/server_crash*.log "$LOG_DIR"/server_damaged.log "$LOG_DIR"/hold_*.log "$LOG_DIR"/host_crash.log; do
	if grep -q -E '^(ERROR|SCRIPT ERROR|USER ERROR)' "$f"; then
		fail "no errors in $(basename "$f")"
		grep -E '^(ERROR|SCRIPT ERROR|USER ERROR)' "$f" | head -5 | sed 's/^/    /'
	fi
done
kill $SPID 2>/dev/null
echo "NETTEST ALL DONE fails=$fails"
[ "$fails" -eq 0 ]
