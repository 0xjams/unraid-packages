#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PKG_DIR="$ROOT_DIR/slackware64/packages"

hash_packages() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$PKG_DIR"/*.txz | awk '{print $1"  "$2}' | sort
  else
    shasum -a 256 "$PKG_DIR"/*.txz | awk '{print $1"  "$2}' | sort
  fi
}

echo "Running first pinned build..."
"$ROOT_DIR/build-all.sh"
FIRST_HASHES=$(hash_packages)

echo "Running second pinned build..."
SKIP_LOCK_REFRESH=1 "$ROOT_DIR/build-all.sh"
SECOND_HASHES=$(hash_packages)

if [ "$FIRST_HASHES" != "$SECOND_HASHES" ]; then
  echo "Reproducibility check failed: package hashes differ between runs."
  diff -u <(printf '%s\n' "$FIRST_HASHES") <(printf '%s\n' "$SECOND_HASHES") || true
  exit 1
fi

echo "Reproducibility check passed."
printf '%s\n' "$SECOND_HASHES"
