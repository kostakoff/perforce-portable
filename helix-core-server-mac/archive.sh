#!/bin/bash
#
# Archive helix-core-server-mac directory into ../archives/
#
# Usage: ./archive.sh
#
# Creates a timestamped .tar.gz backup of the current directory.
# Useful before upgrading to a new P4 version.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCHIVE_DIR="$SCRIPT_DIR/../archives"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ARCHIVE_NAME="helix-core-server-mac-$TIMESTAMP.tar.gz"

mkdir -p "$ARCHIVE_DIR"

echo "Archiving helix-core-server-mac ..."
tar -czf "$ARCHIVE_DIR/$ARCHIVE_NAME" --exclude='.DS_Store' -C "$SCRIPT_DIR/.." "helix-core-server-mac"

ls -lh "$ARCHIVE_DIR/$ARCHIVE_NAME"
