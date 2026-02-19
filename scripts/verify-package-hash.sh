#!/bin/bash
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "Usage: $0 <package-name> <hash> [sha256|md5|auto]"
  echo "Example: $0 atuin 4b305a9e2ea6fac087271b95f54a5b5291f4d70a63e986d96319b6e0e929b594"
  exit 1
fi

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PKG_DIR="$ROOT_DIR/slackware64/packages"

PACKAGE_NAME="$1"
INPUT_HASH=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
MODE="${3:-auto}"

if [ ! -d "$PKG_DIR" ]; then
  echo "Package directory not found: $PKG_DIR"
  exit 1
fi

if [ "$MODE" = "auto" ]; then
  case ${#INPUT_HASH} in
    64) MODE="sha256" ;;
    32) MODE="md5" ;;
    *)
      echo "Could not infer hash type from length ${#INPUT_HASH}."
      echo "Provide explicit mode: sha256 or md5"
      exit 1
      ;;
  esac
fi

case "$MODE" in
  sha256)
    if command -v sha256sum >/dev/null 2>&1; then
      HASH_CMD='sha256sum'
      HASH_READ_CMD='sha256sum'
    elif command -v shasum >/dev/null 2>&1; then
      HASH_CMD='shasum -a 256'
      HASH_READ_CMD='shasum -a 256'
    else
      echo "No SHA256 tool found (need sha256sum or shasum)."
      exit 1
    fi
    ;;
  md5)
    if command -v md5sum >/dev/null 2>&1; then
      HASH_CMD='md5sum'
      HASH_READ_CMD='md5sum'
    elif command -v md5 >/dev/null 2>&1; then
      HASH_CMD='md5 -q'
      HASH_READ_CMD='md5 -q'
    else
      echo "No MD5 tool found (need md5sum or md5)."
      exit 1
    fi
    ;;
  *)
    echo "Invalid mode: $MODE (use sha256, md5, or auto)"
    exit 1
    ;;
esac

matches=0
files=("$PKG_DIR"/"$PACKAGE_NAME"-*.txz)

if [ ! -e "${files[0]}" ]; then
  echo "No stored package files found for '$PACKAGE_NAME' in $PKG_DIR"
  exit 1
fi

echo "Checking $PACKAGE_NAME packages with $MODE..."

for file in "${files[@]}"; do
  filename=$(basename "$file")
  filehash=$(eval "$HASH_CMD \"$file\"" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')

  if [ "$filehash" = "$INPUT_HASH" ]; then
    version=$(python3 - "$filename" "$PACKAGE_NAME" <<'PY'
import re
import sys

filename = sys.argv[1]
name = re.escape(sys.argv[2])
pattern = rf'^{name}-(.*)-[^-]+-[0-9]+_unRAID\.txz$'
match = re.match(pattern, filename)
if match:
    print(match.group(1))
else:
    print("unknown")
PY
)
    echo "MATCH: $filename"
    echo "  version: $version"
    echo "  hash:    $filehash"
    matches=$((matches + 1))
  fi
done

if [ "$matches" -eq 0 ]; then
  echo "No matching stored version found for hash: $INPUT_HASH"
  exit 2
fi
