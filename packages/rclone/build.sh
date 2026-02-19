#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LOCK_FILE="$SCRIPT_DIR/source.lock"

if [ ! -f "$LOCK_FILE" ]; then
  echo "Missing lock file: $LOCK_FILE"
  exit 1
fi

# shellcheck disable=SC1090
. "$LOCK_FILE"

echo "Building rclone version: $VERSION (pinned)"

VERSION="$VERSION" \
SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
./rclone.SlackBuild

echo "rclone $VERSION built successfully"
