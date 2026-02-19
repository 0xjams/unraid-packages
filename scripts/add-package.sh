#!/bin/bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <name> <repository> <asset-template> [homepage] [short-description]"
  echo "Example: $0 just casey/just 'just-{{VERSION}}-x86_64-unknown-linux-musl.tar.gz' https://github.com/casey/just 'command runner'"
  exit 1
fi

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

NAME="$1"
REPOSITORY="$2"
ASSET_TEMPLATE="$3"
HOMEPAGE="${4:-https://github.com/$REPOSITORY}"
SHORT_DESC="${5:-binary package}"

PKG_DIR="$ROOT_DIR/packages/$NAME"

if [ -d "$PKG_DIR" ]; then
  echo "Package already exists: $PKG_DIR"
  exit 1
fi

mkdir -p "$PKG_DIR"

cat > "$PKG_DIR/package.conf" <<EOF
PRGNAM=$NAME
REPOSITORY=$REPOSITORY
ASSET_TEMPLATE=$ASSET_TEMPLATE
BINARY_NAME=$NAME
HOMEPAGE=$HOMEPAGE
EOF

cat > "$PKG_DIR/build.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PACKAGE_NAME=$(basename "$SCRIPT_DIR")
LOCK_FILE="$SCRIPT_DIR/source.lock"

if [ ! -f "$LOCK_FILE" ]; then
  echo "Missing lock file: $LOCK_FILE"
  exit 1
fi

# shellcheck disable=SC1090
. "$LOCK_FILE"

echo "Building $PACKAGE_NAME version: ${VERSION} (pinned)"

VERSION="$VERSION" \
SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
./${PACKAGE_NAME}.SlackBuild

echo "$PACKAGE_NAME $VERSION built successfully"
EOF

cat > "$PKG_DIR/$NAME.SlackBuild" <<'EOF'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
"$SCRIPT_DIR/../../scripts/deterministic-slackbuild.sh" "$SCRIPT_DIR"
EOF

cat > "$PKG_DIR/slack-desc" <<EOF
# HOW TO EDIT THIS FILE:
# The "handy ruler" below makes it easier to edit a package description.
# Line up the first '|' above the ':' following the base package name, and
# the '|' on the right side marks the last column you can put a character in.
# You must make exactly 11 lines for the formatting to be correct.  It's also
# customary to leave one space after the ':' except on otherwise blank lines.

     |-----handy-ruler------------------------------------------------------|
$NAME: $NAME ($SHORT_DESC)
$NAME:
$NAME: Binary package for $NAME.
$NAME: Homepage: $HOMEPAGE
$NAME:
$NAME:
$NAME:
$NAME:
EOF

chmod +x "$PKG_DIR/build.sh" "$PKG_DIR/$NAME.SlackBuild"

"$ROOT_DIR/scripts/update-locks.sh"

echo "Added package '$NAME' in $PKG_DIR"
