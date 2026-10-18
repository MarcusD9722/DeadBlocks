#!/usr/bin/env bash
# Updates the Dead Blocks server installed by install.sh. It backs up the world, gets the new
# version, checks that it runs on this Pi, stops the server (which saves), swaps the program and
# starts it again. If the new version doesn't start, it goes back to the old one by itself.
#
#   ~/deadblocks-server/update.sh                  the newest GitHub release
#   ~/deadblocks-server/update.sh FILE.zip         a server zip you copied to the Pi
#   ~/deadblocks-server/update.sh --rollback       back to the version before the last update
# Installed from the git checkout instead? Then it pulls the newest code with git.
set -uo pipefail
DBH="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
URL="https://github.com/MarcusD9722/DeadBlocks/releases/latest/download/DeadBlocksServer-linux-arm64.zip"
ARG="${1:-}"
SYSTEMCTL="${DB_SYSTEMCTL:-sudo systemctl}"
die() { printf '\nUPDATE FAILED: %s\n' "$*" >&2; exit 1; }
[ -f "$DBH/install.conf" ] || die "$DBH has no install.conf: install with install.sh first."
MODE=$(sed -n 's/^MODE=//p' "$DBH/install.conf")
DBCTL=(env DB_DATA="$DBH" "$DBH/dbctl")

wait_up() {  # wait_up SINCE: until a server is running that has written status.json since then
	for _ in $(seq 1 120); do
		if "${DBCTL[@]}" status > /dev/null 2>&1 && [ "$(stat -c %Y "$DBH/status.json" 2>/dev/null || echo 0)" -ge "$1" ]; then
			return 0
		fi
		sleep 1
	done
	return 1
}

if [ "$MODE" = git ]; then
	REPO=$(sed -n 's/^REPO=//p' "$DBH/install.conf")
	GODOT=$(sed -n 's/^GODOT=//p' "$DBH/install.conf")
	[ "$ARG" = "--rollback" ] && die "installed from git: go back with git (git -C $REPO log, git -C $REPO checkout <commit>), then $REPO/tools/pi/install.sh --update"
	echo "Backing up the world..."
	"${DBCTL[@]}" backup
	echo "Getting the newest code..."
	git -C "$REPO" pull --ff-only || die "git pull failed (see above); nothing was changed."
	exec "$REPO/tools/pi/install.sh" --update --home="$DBH" --godot="$GODOT"
fi

if [ "$ARG" = "--rollback" ]; then
	[ -f "$DBH/DeadBlocksServer.arm64.old" ] || die "there is no previous version (DeadBlocksServer.arm64.old) to go back to."
	echo "Going back to the previous version..."
	"${DBCTL[@]}" backup
	$SYSTEMCTL stop deadblocks
	mv "$DBH/DeadBlocksServer.arm64" "$DBH/DeadBlocksServer.arm64.rolled-back"
	mv "$DBH/DeadBlocksServer.arm64.old" "$DBH/DeadBlocksServer.arm64"
	mv "$DBH/DeadBlocksServer.arm64.rolled-back" "$DBH/DeadBlocksServer.arm64.old"
	since=$(date +%s)
	$SYSTEMCTL start deadblocks || die "the service did not start: dbctl status"
	wait_up "$since" || { "${DBCTL[@]}" status; die "the previous version didn't start either; the lines above say why."; }
	"${DBCTL[@]}" status
	exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if [ -z "$ARG" ] || [[ "$ARG" == http* ]]; then
	echo "Downloading ${ARG:-$URL} ..."
	curl -fL --progress-bar -o "$work/server.zip" "${ARG:-$URL}" || die "the download failed. If the repository is private, download
DeadBlocksServer-linux-arm64.zip on your PC, copy it to the Pi (for example:
scp DeadBlocksServer-linux-arm64.zip $(id -un)@$(hostname -I 2>/dev/null | awk '{print $1}'):~/ ) and run: $0 ~/DeadBlocksServer-linux-arm64.zip"
else
	[ -f "$ARG" ] || die "no such file: $ARG"
	cp "$ARG" "$work/server.zip"
fi
python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$work/server.zip" "$work/x" || die "that file isn't a working zip."
NEW=$(dirname "$(find "$work/x" -name install.sh -path '*deadblocks-server*' | head -1)")
[ -f "$NEW/DeadBlocksServer.arm64" ] || die "that zip has no DeadBlocksServer.arm64 in it."
chmod +x "$NEW/DeadBlocksServer.arm64" "$NEW/install.sh"
new_version=$(${DB_EXEC_PREFIX:-} "$NEW/DeadBlocksServer.arm64" --headless -- --version 2>/dev/null | sed -n 's/^Dead Blocks //p' | head -1)
[ -n "$new_version" ] || die "the new server program doesn't run on this Pi; nothing was changed."
old_version=$("${DBCTL[@]}" version | sed -n 's/^Dead Blocks //p')
echo "Installed: ${old_version:-unknown}. New: $new_version."
echo "Backing up the world..."
"${DBCTL[@]}" backup
if ! "$NEW/install.sh" --update --home="$DBH"; then
	if [ -f "$DBH/DeadBlocksServer.arm64.old" ]; then
		echo
		echo "The new version didn't start; going back to $old_version."
		"$0" --rollback && die "version $new_version did not start, so the server runs $old_version again. Nothing was lost."
	fi
	die "version $new_version did not start (dbctl logs shows why)."
fi
echo
echo "Updated to $new_version. Players need the same version of the game: the server tells anyone with another one."
