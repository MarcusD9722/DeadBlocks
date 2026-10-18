#!/usr/bin/env bash
# Tests the Raspberry Pi server package without a Pi: unzips build/DeadBlocksServer-linux-arm64.zip,
# runs its install.sh with the answers piped in and a stand-in for systemctl that runs the
# installed unit's real ExecStart / ExecStop lines (under qemu on a PC), joins with a bot, uses
# dbctl, updates (and refuses a broken update), rolls back, stops, and restores a backup.
# Prints PIPKG PASS/FAIL lines and ends with "PIPKG DONE fails=N".
# Usage: GODOT=/path/to/godot ./tools/test_pi_package.sh   (after tools/build_release.sh)
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
ZIP="$PWD/build/DeadBlocksServer-linux-arm64.zip"
T="$PWD/build/test_logs/pi_package"
rm -rf "$T"
mkdir -p "$T/units" "$T/bin" "$T/state" "$T/home" "$T/pkg"
PORT=$((30000 + RANDOM % 20000))
DBH="$T/home/deadblocks-server"
LOG="$T/server.log"
fails=0
pass() { echo "PIPKG PASS $*"; }
fail() { echo "PIPKG FAIL $*"; fails=$((fails + 1)); }
check() { if eval "$1"; then pass "$2"; else fail "$2"; fi; }
wait_for() {  # wait_for SECONDS COMMAND...
	local secs=$1 i
	shift
	for ((i = 0; i < secs * 10; i++)); do
		"$@" && return 0
		sleep 0.1
	done
	return 1
}
cleanup() {
	[ -f "$T/state/deadblocks.pid" ] && kill -9 "$(cat "$T/state/deadblocks.pid")" 2>/dev/null
	kill $(jobs -p) 2>/dev/null
	wait 2>/dev/null
}
trap cleanup EXIT

[ -f "$ZIP" ] || { fail "no $ZIP (run tools/build_release.sh first)"; echo "PIPKG DONE fails=$fails"; exit 1; }
QEMU=""
[ "$(uname -m)" = aarch64 ] || QEMU="qemu-aarch64-static -L /usr/aarch64-linux-gnu"
# Every server program runs through this, under qemu; one with an extra "x" at the end plays a
# new version that answers --version but won't start (to test that update.sh rolls back by itself).
cat > "$T/run_server" <<SH
#!/usr/bin/env bash
[ "\$(tail -c 1 "\$1")" = x ] || exec $QEMU "\$@"
for a in "\$@"; do [ "\$a" = --version ] && { echo "Dead Blocks 9.9.9"; exit 0; }; done
echo "(test) this version refuses to start"
exit 1
SH
chmod +x "$T/run_server"
PREFIX="$T/run_server"

# The stand-in for systemctl: "start" runs the unit's ExecStart in the background (output to
# $LOG), "stop" runs its ExecStop and waits, like systemd with KillMode=mixed.
cat > "$T/systemctl" <<'SH'
#!/usr/bin/env bash
args=()
for a in "$@"; do case "$a" in --quiet|--no-pager) ;; *) args+=("$a") ;; esac; done
cmd="${args[0]}"
unit="${args[1]:-}"
unit="${unit%.service}"
pidf="$FAKE_STATE/$unit.pid"
running() { [ -f "$pidf" ] && kill -0 "$(cat "$pidf")" 2>/dev/null; }
start() {
	[ "$unit" = deadblocks ] || return 0
	running && return 0
	local line
	line=$(sed -n 's/^ExecStart=//p' "$FAKE_UNITS/deadblocks.service")
	$FAKE_PREFIX $line >> "$FAKE_LOG" 2>&1 &
	echo $! > "$pidf"
	echo "systemctl: started deadblocks ($!)" >> "$FAKE_STATE/calls"
}
stop() {
	[ "$unit" = deadblocks ] || return 0
	running || return 0
	local line i
	line=$(sed -n 's/^ExecStop=//p' "$FAKE_UNITS/deadblocks.service")
	$line
	for ((i = 0; i < 900; i++)); do
		running || return 0
		sleep 0.1
	done
	kill -9 "$(cat "$pidf")"
}
echo "systemctl $*" >> "$FAKE_STATE/calls"
case "$cmd" in
	daemon-reload|enable) exit 0 ;;
	is-active) running ;;
	start) start ;;
	stop) stop ;;
	restart) stop; start ;;
	status) running && echo "active" || echo "inactive" ;;
	*) exit 0 ;;
esac
SH
chmod +x "$T/systemctl"
export DB_SYSTEMCTL="$T/systemctl" DB_SUDO="" DB_UNIT_DIR="$T/units" DB_BIN_DIR="$T/bin" DB_ASSUME_ARCH=aarch64 \
	DB_SKIP_PORT_CHECK=1 DB_EXEC_PREFIX="$PREFIX" DB_LOG="$LOG" \
	FAKE_STATE="$T/state" FAKE_UNITS="$T/units" FAKE_LOG="$LOG" FAKE_PREFIX="$PREFIX"
pi() { HOME="$T/home" "$@"; }  # the Pi user's commands, with a home of their own
spid() { cat "$T/state/deadblocks.pid" 2>/dev/null; }
is_running() {  # (not a pipe into grep -q: with pipefail, dbctl's SIGPIPE would fail it)
	local out
	out=$(pi "$DBH/dbctl" status 2>/dev/null)
	grep -q "running (process" <<< "$out"
}
up_since() {  # up_since UNIX_TIME: a server is running that has written status.json since then
	is_running && [ -f "$DBH/status.json" ] && [ "$(stat -c %Y "$DBH/status.json")" -ge "$1" ]
}
bot() {  # bot LOGNAME NAME PIN ROLE [args]: a client joins the installed server
	local log=$1 name=$2 pin=$3 role=$4
	shift 4
	"$GODOT" --headless --path . -- --connect=127.0.0.1:$PORT --name="$name" --pin="$pin" --password=pw \
		--nettest="$role" --radius=3 "$@" > "$T/$log.log" 2>&1
	grep -q "NETTEST DONE fails=0" "$T/$log.log"
}

python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$ZIP" "$T/pkg"
PKG="$T/pkg/deadblocks-server"
check '[ -f "$PKG/DeadBlocksServer.arm64" ] && [ -f "$PKG/install.sh" ] && [ -f "$PKG/dbctl" ] && [ -f "$PKG/pi-server.md" ]' \
	"the zip holds the server, install.sh, dbctl and the guide"

# 1. First install: questions answered from a pipe (password twice, a typo first, admins).
printf 'pw\npx\npw\npw\nalice\n' | pi bash "$PKG/install.sh" --port=$PORT > "$T/install.log" 2>&1
rc=$?
check '[ $rc -eq 0 ] && grep -q "^Done. The server runs now" "$T/install.log"' "install.sh finished (exit $rc, see install.log)"
check 'grep -q "Those weren.t the same" "$T/install.log"' "a mistyped password is asked again"
check '[ "$(stat -c %a "$DBH/server.cfg")" = 600 ] && grep -q "^password=pw$" "$DBH/server.cfg" && grep -q "^admins=alice$" "$DBH/server.cfg" && grep -q "^port=$PORT$" "$DBH/server.cfg"' \
	"server.cfg written, readable only by its owner"
check 'grep -q "^ExecStart=$DBH/DeadBlocksServer.arm64 --headless -- --data=$DBH$" "$T/units/deadblocks.service" && grep -q "^ExecStop=$DBH/dbctl halt$" "$T/units/deadblocks.service" && grep -q "^User=$(id -un)$" "$T/units/deadblocks.service"' \
	"the service runs the server in its folder and stops it with dbctl halt"
check 'grep -q "^ExecStart=$DBH/dbctl backup$" "$T/units/deadblocks-backup.service" && [ -f "$T/units/deadblocks-backup.timer" ] && [ -L "$T/bin/dbctl" ]' \
	"the daily backup timer and the dbctl link are installed"
check 'grep -q "^ExecStart=$DBH/dbctl watchdog$" "$T/units/deadblocks-watchdog.service" && grep -q "^OnUnitActiveSec=15s$" "$T/units/deadblocks-watchdog.timer" && grep -q "enable .*deadblocks-watchdog.timer" "$T/state/calls"' \
	"the watchdog timer is installed and enabled"
check 'grep -q "SERVER settings from $DBH/server.cfg" "$LOG" && grep -q "listening on UDP $PORT" "$LOG" && grep -q "admins alice" "$LOG"' \
	"the server took its settings from server.cfg"
check '! grep -q "pw" <(grep "SERVER settings" "$LOG")' "the password isn't printed in the log"

# 2. Playing and dbctl.
check 'bot join alice 1234 join' "a player joins the installed server"
out=$(pi "$DBH/dbctl" status)
check 'grep -q "running (process" <<< "$out" && grep -q "version 0\." <<< "$out"' "dbctl status: running, with the version"
check 'pi "$DBH/dbctl" say hello there > /dev/null && wait_for 5 grep -q "SERVER control: say hello there" "$LOG"' "dbctl say"
check 'pi "$DBH/dbctl" backup > /dev/null && wait_for 10 grep -q "SERVER backup (asked for)" "$LOG"' "dbctl backup"
check 'pi "$DBH/dbctl" reset-pin alice > /dev/null && wait_for 5 grep -q "alice.s PIN was reset" "$LOG"' "dbctl reset-pin"
check 'bot pin_new alice 4321 join' "alice signs in with a new PIN"
check '[ "$(pi "$DBH/dbctl" version)" = "Dead Blocks $(sed -n "s/^const VERSION := \"\(.*\)\"/\1/p" scripts/g.gd)" ]' "dbctl version"

# 3. Updates: a broken package is refused without touching anything; a good one is installed.
mkdir -p "$T/broken/deadblocks-server"
cp "$PKG"/* "$T/broken/deadblocks-server/"
head -c 1000000 "$PKG/DeadBlocksServer.arm64" > "$T/broken/deadblocks-server/DeadBlocksServer.arm64"
(cd "$T/broken" && python3 -c 'import os, zipfile
with zipfile.ZipFile("broken.zip", "w") as z:
    for f in os.listdir("deadblocks-server"): z.write("deadblocks-server/" + f)')
before=$(spid)
pi "$DBH/update.sh" "$T/broken/broken.zip" > "$T/update_broken.log" 2>&1
rc=$?
check '[ $rc -ne 0 ] && grep -q "doesn.t run on this Pi; nothing was changed" "$T/update_broken.log" && [ "$(spid)" = "$before" ] && cmp -s "$PKG/DeadBlocksServer.arm64" "$DBH/DeadBlocksServer.arm64"' \
	"a broken update is refused and the server keeps running"
pi "$DBH/update.sh" "$ZIP" > "$T/update.log" 2>&1
rc=$?
check '[ $rc -eq 0 ] && grep -q "^Updated to" "$T/update.log" && [ "$(spid)" != "$before" ] && [ -f "$DBH/worlds/main/players/alice.json" ]' \
	"update.sh: backup, stop (saved), start again, world kept (exit $rc)"
check '[ "$(grep -c "^SERVER stopped$" "$LOG")" -ge 1 ] && [ "$(grep -c "SERVER backup (asked for)" "$LOG")" -ge 2 ]' "the update saved and backed up first"
cp "$DBH/DeadBlocksServer.arm64" "$DBH/DeadBlocksServer.arm64.old"
before=$(spid)
t0=$(date +%s)
pi "$DBH/update.sh" --rollback > "$T/rollback.log" 2>&1
rc=$?
check '[ $rc -eq 0 ] && wait_for 120 up_since $t0 && [ "$(spid)" != "$before" ]' "update.sh --rollback (exit $rc)"

# An update whose server won't start: update.sh must go back to the version before by itself.
mkdir -p "$T/bad/deadblocks-server"
cp "$PKG"/* "$T/bad/deadblocks-server/"
printf 'x' >> "$T/bad/deadblocks-server/DeadBlocksServer.arm64"
(cd "$T/bad" && python3 -c 'import os, zipfile
with zipfile.ZipFile("bad.zip", "w") as z:
    for f in os.listdir("deadblocks-server"): z.write("deadblocks-server/" + f)')
t0=$(date +%s)
pi "$DBH/update.sh" "$T/bad/bad.zip" > "$T/update_bad.log" 2>&1
rc=$?
check '[ $rc -ne 0 ] && grep -q "going back to 0\." "$T/update_bad.log" && grep -q "so the server runs 0\..* again" "$T/update_bad.log" && wait_for 120 up_since $t0 && cmp -s "$PKG/DeadBlocksServer.arm64" "$DBH/DeadBlocksServer.arm64"' \
	"an update that doesn't start goes back to the old version by itself (exit $rc)"

# The watchdog: a server whose lock has gone quiet (it is rewritten every 10 s) is killed, and
# systemd starts it again.
pid=$(spid)
check '! grep -q "not responded" <<< "$(pi "$DBH/dbctl" watchdog)" && kill -0 $pid' "the watchdog leaves a working server alone"
touch -d '-2 min' "$DBH/worlds/main/world.lock"
out=$(pi "$DBH/dbctl" watchdog)
check 'grep -q "has not responded for" <<< "$out" && wait_for 10 bash -c "! kill -0 $pid 2> /dev/null"' "the watchdog kills a server that stopped responding"
t0=$(date +%s)
pi "$DBH/dbctl" start > /dev/null  # what Restart=on-failure does
check 'wait_for 120 up_since $t0' "and it comes back"

# 4. Stop, offline backup, restore, start.
pid=$(spid)
pi "$DBH/dbctl" stop > "$T/stop.log" 2>&1
check '! kill -0 "$pid" 2>/dev/null && [ ! -f "$DBH/worlds/main/world.lock" ] && grep -q "Stopped (saved)" "$T/stop.log"' "dbctl stop: saved and stopped"
check 'pi "$DBH/dbctl" status > /dev/null; [ $? -ne 0 ]' "dbctl status says it's not running"
check 'grep -q "offline.zip" <<< "$(pi "$DBH/dbctl" backup)"' "dbctl backup while stopped zips the world itself"
touch "$DBH/worlds/main/marker"
pi "$DBH/dbctl" restore > "$T/restore.log" 2>&1
check '[ ! -f "$DBH/worlds/main/marker" ] && [ -f "$DBH/worlds/main/world.json" ] && ls -d "$DBH"/worlds/main.before-restore-* > /dev/null 2>&1' \
	"dbctl restore puts the newest backup back and keeps the old world"
t0=$(date +%s)
pi "$DBH/dbctl" start > /dev/null
check 'wait_for 120 up_since $t0 && bot join_after alice 4321 join' "dbctl start, and alice joins again (restored world)"
pi "$DBH/dbctl" stop > /dev/null

if grep -q -E '^(ERROR|SCRIPT ERROR|USER ERROR)' "$LOG"; then
	fail "no errors in the server log"
	grep -E '^(ERROR|SCRIPT ERROR|USER ERROR)' "$LOG" | head -5 | sed 's/^/    /'
fi
echo "PIPKG DONE fails=$fails"
[ "$fails" -eq 0 ]
