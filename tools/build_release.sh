#!/usr/bin/env bash
# Builds everything players and the Pi need into build/:
#   build/DeadBlocks.exe                    Windows game (single file)
#   build/DeadBlocks-<version>-windows.zip   the same, zipped for download
#   build/server/DeadBlocksServer.arm64      Raspberry Pi server (single file)
#   build/server/DeadBlocksServer.x86_64     PC Linux server, for tests
#   build/DeadBlocksServer-linux-arm64.zip   the Pi server package: the arm64 server, install.sh,
#                                            update.sh, dbctl, the systemd units and the guide
#                                            (docs/pi-server.md), in a deadblocks-server/ folder
# Usage: GODOT=/path/to/godot ./tools/build_release.sh
# Needs the Godot 4.7.2 export templates (Windows x86_64, Linux arm64 and x86_64) installed.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
version=$(sed -n 's/^const VERSION := "\(.*\)"/\1/p' scripts/g.gd)
mkdir -p build/server
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
export_one() {
	echo "Exporting $1 -> $2"
	if ! "$GODOT" --headless --path . --export-release "$1" "$2" > "build/export_$(basename "$2").log" 2>&1 || [ ! -s "$2" ]; then
		echo "Export of $1 failed; see build/export_$(basename "$2").log" >&2
		exit 1
	fi
}
export_one "Windows Desktop" build/DeadBlocks.exe
export_one "Linux Server arm64" build/server/DeadBlocksServer.arm64
export_one "Linux Server x86_64" build/server/DeadBlocksServer.x86_64
rm -f "build/DeadBlocks-$version-windows.zip"
(cd build && zip -q -9 "DeadBlocks-$version-windows.zip" DeadBlocks.exe)
# The Pi package. Its name has no version, so update.sh can always fetch
# releases/latest/download/DeadBlocksServer-linux-arm64.zip.
pkg=build/pkg/deadblocks-server
rm -rf build/pkg build/DeadBlocksServer-linux-arm64.zip
mkdir -p "$pkg"
cp build/server/DeadBlocksServer.arm64 tools/pi/install.sh tools/pi/update.sh tools/pi/dbctl tools/pi/*.in "$pkg/"  # *.in: the systemd units
cp docs/pi-server.md "$pkg/pi-server.md"
chmod 755 "$pkg/DeadBlocksServer.arm64" "$pkg/install.sh" "$pkg/update.sh" "$pkg/dbctl"
(cd build/pkg && zip -q -r -9 ../DeadBlocksServer-linux-arm64.zip deadblocks-server)
rm -rf build/pkg
echo "Built version $version:"
ls -la build/DeadBlocks.exe "build/DeadBlocks-$version-windows.zip" build/server/DeadBlocksServer.* build/DeadBlocksServer-linux-arm64.zip
