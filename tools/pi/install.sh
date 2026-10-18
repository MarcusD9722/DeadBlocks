#!/usr/bin/env bash
# Installs (or updates) the Dead Blocks server on a Raspberry Pi 5 as a systemd service that
# starts with the Pi, restarts after a crash or when it stops responding, saves when stopped,
# and backs up daily.
#
# From the server zip (recommended, the faster release build):
#     ./install.sh
# From the git checkout, with the Godot binary from the benchmark guide:
#     ~/deadblocks/tools/pi/install.sh [--godot=~/godot/Godot_v4.7.2-stable_linux.arm64]
#
# The first install asks for the server password and the admin names and writes server.cfg.
# Options: --update (no questions: keep server.cfg, swap the program, restart; used by update.sh)
#          --home=DIR (server folder, default ~/deadblocks-server)   --port=N (default 24650)
# Test hooks: DB_SYSTEMCTL, DB_SUDO, DB_UNIT_DIR, DB_BIN_DIR, DB_ASSUME_ARCH, DB_SKIP_PORT_CHECK.
set -uo pipefail
SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DBH="$HOME/deadblocks-server"
GODOT=""
UPDATE=0
PORT=24650
for a in "$@"; do
	case "$a" in
		--update) UPDATE=1 ;;
		--home=*) DBH="${a#--home=}" ;;
		--godot=*) GODOT="${a#--godot=}" ;;
		--port=*) PORT="${a#--port=}" ;;
		*) echo "Unknown option: $a" >&2; exit 2 ;;
	esac
done
SUDO="${DB_SUDO-sudo}"
SYSTEMCTL="${DB_SYSTEMCTL:-$SUDO systemctl}"
UNIT_DIR="${DB_UNIT_DIR:-/etc/systemd/system}"
BIN_DIR="${DB_BIN_DIR:-/usr/local/bin}"
RUN_USER="$(id -un)"
say() { printf '\n== %s\n' "$*"; }
die() { printf '\nINSTALL FAILED: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || [ -n "${DB_SYSTEMCTL:-}" ] || die "run this as your normal user (not with sudo); it asks for sudo itself when it needs it."
[ "${DB_ASSUME_ARCH:-$(uname -m)}" = "aarch64" ] || die "this is for a 64-bit Raspberry Pi OS (aarch64); this machine is $(uname -m)."
command -v python3 > /dev/null || die "python3 is missing: sudo apt install -y python3"

# Where the program comes from.
if [ -f "$SRC/DeadBlocksServer.arm64" ]; then
	MODE=release
elif [ -f "$SRC/../../project.godot" ]; then
	MODE=git
	REPO="$(cd "$SRC/../.." && pwd)"
	if [ -z "$GODOT" ] && [ -f "$DBH/install.conf" ]; then
		GODOT=$(sed -n 's/^GODOT=//p' "$DBH/install.conf")
	fi
	GODOT="${GODOT:-$HOME/godot/Godot_v4.7.2-stable_linux.arm64}"
	GODOT="${GODOT/#\~/$HOME}"
	[ -x "$GODOT" ] || die "no Godot program at $GODOT (see docs/pi-benchmark.md step 3, or pass --godot=PATH)."
else
	die "run install.sh from the unzipped server package (next to DeadBlocksServer.arm64) or from the git checkout (tools/pi/install.sh)."
fi

if [ -f "$DBH/server.cfg" ]; then
	PORT=$(sed -n 's/^[[:space:]]*port[[:space:]]*=[[:space:]]*//p' "$DBH/server.cfg" | tail -1)
	PORT="${PORT:-24650}"
elif [ "$UPDATE" -eq 1 ]; then
	die "no server.cfg in $DBH: install first (without --update)."
fi

service_active() { $SYSTEMCTL is-active --quiet deadblocks 2>/dev/null; }

if [ "$UPDATE" -eq 0 ] && [ -z "${DB_SKIP_PORT_CHECK:-}" ] && ! service_active && ss -Huln 2>/dev/null | grep ":$PORT\b" > /dev/null; then
	die "something is already using UDP port $PORT, probably the server you started by hand in tmux.
Stop it first (it saves): echo stop > ~/.local/share/DeadBlocks/server/control/stop.cmd
(a server older than 0.5.0 saves nothing: tmux kill-session -t deadblocks), then run install.sh again."
fi

say "Installing the Dead Blocks server ($MODE build) into $DBH"
mkdir -p "$DBH"
put() {  # put SRC DEST MODE: copy so that a running copy of DEST is never changed in place
	cp "$1" "$2.new" && chmod "$3" "$2.new" && mv -f "$2.new" "$2"
}
if [ "$MODE" = release ]; then
	if [ -f "$DBH/DeadBlocksServer.arm64" ] && ! cmp -s "$SRC/DeadBlocksServer.arm64" "$DBH/DeadBlocksServer.arm64"; then
		cp -p "$DBH/DeadBlocksServer.arm64" "$DBH/DeadBlocksServer.arm64.old"
		echo "The previous version is kept as DeadBlocksServer.arm64.old (update.sh --rollback goes back to it)."
	fi
	put "$SRC/DeadBlocksServer.arm64" "$DBH/DeadBlocksServer.arm64" 755
	EXEC="$DBH/DeadBlocksServer.arm64 --headless -- --data=$DBH"
	printf 'MODE=release\n' > "$DBH/install.conf"
else
	echo "Preparing the project for $GODOT (a minute the first time)..."
	"$GODOT" --headless --path "$REPO" --import > "$DBH/import.log" 2>&1 || true
	EXEC="$GODOT --headless --path $REPO -- --server --data=$DBH"
	printf 'MODE=git\nREPO=%s\nGODOT=%s\n' "$REPO" "$GODOT" > "$DBH/install.conf"
fi
for f in dbctl update.sh install.sh deadblocks.service.in deadblocks-backup.service.in deadblocks-backup.timer.in \
	deadblocks-watchdog.service.in deadblocks-watchdog.timer.in; do
	put "$SRC/$f" "$DBH/$f" 755
done
if [ -f "$SRC/pi-server.md" ]; then cp "$SRC/pi-server.md" "$DBH/README.md"
elif [ "$MODE" = git ] && [ -f "$REPO/docs/pi-server.md" ]; then cp "$REPO/docs/pi-server.md" "$DBH/README.md"
fi

if [ ! -f "$DBH/server.cfg" ]; then
	say "Server settings"
	while true; do
		read -r -s -p "Server password (your friends type this to join): " pw1; echo
		read -r -s -p "The same password again: " pw2; echo
		if [ -z "$pw1" ]; then echo "The password can't be empty."
		elif [ "$pw1" != "$pw2" ]; then echo "Those weren't the same; try again."
		else break
		fi
	done
	read -r -p "Your name in the game; it gets the admin commands like /bloodmoon (more names: comma-separated) [Marcus]: " admins
	admins="${admins:-Marcus}"
	umask 077
	cat > "$DBH/server.cfg" <<CFG
# Dead Blocks server settings. After changing anything here: dbctl restart
port=$PORT
password=$pw1
admins=$admins
max_players=8
day_minutes=30
autosave_s=60
world=main
CFG
	umask 022
	echo "Written to $DBH/server.cfg (only you can read it)."
fi

# A world from running the server by hand (before this install) comes along.
OLD="$HOME/.local/share/DeadBlocks/server"
if [ ! -f "$DBH/worlds/main/world.json" ] && [ -f "$OLD/worlds/main/world.json" ]; then
	say "Bringing over the world you already played in ($OLD)"
	mkdir -p "$DBH/worlds"
	cp -a "$OLD/worlds/main" "$DBH/worlds/main"
	rm -f "$DBH/worlds/main/world.lock"
fi

say "Installing the service (asks for your password for sudo)"
tmp=$(mktemp -d)
for u in deadblocks.service deadblocks-backup.service deadblocks-backup.timer deadblocks-watchdog.service deadblocks-watchdog.timer; do
	sed -e "s|@USER@|$RUN_USER|g" -e "s|@HOME@|$DBH|g" -e "s|@EXEC@|$EXEC|g" "$SRC/$u.in" > "$tmp/$u"
	$SUDO install -m 644 "$tmp/$u" "$UNIT_DIR/$u" || die "could not write $UNIT_DIR/$u"
done
rm -rf "$tmp"
$SUDO ln -sf "$DBH/dbctl" "$BIN_DIR/dbctl" 2>/dev/null || true
$SYSTEMCTL daemon-reload
$SYSTEMCTL enable deadblocks.service deadblocks-backup.timer deadblocks-watchdog.timer > /dev/null 2>&1 || die "systemctl enable failed"
$SYSTEMCTL start deadblocks-backup.timer deadblocks-watchdog.timer > /dev/null 2>&1 || true
lock_pid() {  # the process id in the world's lock file, if that process is alive
	local pid
	pid=$(sed -n 's/^pid \([0-9]*\).*/\1/p' "$DBH/worlds/$(sed -n 's/^world=//p' "$DBH/server.cfg" | tail -1)/world.lock" 2>/dev/null)
	[ -n "$pid" ] && [ -d "/proc/$pid" ] && echo "$pid"
}
old_pid=$(lock_pid)
started=$(date +%s)
# restart = stop (the old server saves) + start; it also starts one that wasn't running.
$SYSTEMCTL restart deadblocks || die "the service did not start: dbctl status"

say "Starting"
ok=0
down=0
for _ in $(seq 1 120); do
	pid=$(lock_pid)
	# Up: a new process holds the world and has written its first status.json.
	if [ -n "$pid" ] && [ "$pid" != "$old_pid" ] && [ -f "$DBH/status.json" ] && [ "$(stat -c %Y "$DBH/status.json")" -ge "$started" ]; then
		ok=1
		break
	fi
	if service_active; then down=0; else down=$((down + 1)); fi
	[ "$down" -ge 8 ] && break  # it refused to start (or keeps crashing)
	sleep 1
done
if [ "$ok" -ne 1 ]; then
	DB_DATA="$DBH" "$DBH/dbctl" status
	die "the server didn't come up. The lines above say why."
fi
DB_DATA="$DBH" "$DBH/dbctl" status
lan=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -n "$lan" ] || lan="<this Pi's address>"
cat <<MSG

Done. The server runs now, starts with the Pi, and saves when stopped.
  In your house, join:  $lan:$PORT
  From outside:         <your public address>:$PORT, after forwarding UDP $PORT on the router to this Pi
  Control it with:      dbctl status | say | kick | reset-pin | backup | restore | stop | start | logs
  Update it with:       $DBH/update.sh
MSG
