#!/bin/bash
#
# Download Perforce Helix Core Server binaries
#
# Usage: ./download.sh
#
# Downloads the official Helix Core Server package and installs
# the binaries (p4, p4d, p4p, p4broker) into helix-core-server-mac/.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$SCRIPT_DIR/helix-core-server-mac"
URL="https://filehost.perforce.com/perforce/r26.1/bin.macosx12arm64/helix-core-server.tgz"
TMP_DIR=$(mktemp -d)

trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading Helix Core Server..."
curl -fSL "$URL" -o "$TMP_DIR/helix-core-server.tgz"

echo "Extracting..."
tar -xzf "$TMP_DIR/helix-core-server.tgz" -C "$TMP_DIR"

for bin in p4 p4d p4p p4broker; do
    src=$(find "$TMP_DIR" -name "$bin" -type f | head -1)
    if [ -n "$src" ]; then
        cp "$src" "$DEST/$bin"
        chmod +x "$DEST/$bin"
        echo "  Installed: $bin"
    else
        echo "  WARNING: $bin not found in archive" >&2
    fi
done

echo "Done. Binaries installed in $DEST"
