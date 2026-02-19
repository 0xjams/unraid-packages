#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_EPOCH=0

if [ "${SKIP_LOCK_REFRESH:-0}" != "1" ]; then
  echo "Refreshing source locks from latest GitHub releases..."
  "$ROOT_DIR/scripts/update-locks.sh"
fi

echo "Building all packages..."

for package_dir in "$ROOT_DIR"/packages/*; do
  if [ ! -d "$package_dir" ] || [ ! -f "$package_dir/build.sh" ] || [ ! -f "$package_dir/source.lock" ]; then
    continue
  fi

  package_name=$(basename "$package_dir")

  pkg_epoch=$(python3 - "$package_dir/source.lock" <<'PY'
import sys

lock_path = sys.argv[1]
epoch = 0
with open(lock_path, encoding="utf-8") as handle:
    for line in handle:
        if line.startswith("SOURCE_DATE_EPOCH="):
            epoch = int(line.strip().split("=", 1)[1])
            break
print(epoch)
PY
)

  if [ "$pkg_epoch" -gt "$REPO_EPOCH" ]; then
    REPO_EPOCH="$pkg_epoch"
  fi

  echo "Building package: $package_name"
  (
    cd "$package_dir"
    ./build.sh
  )
done

echo "Updating repository metadata..."
SOURCE_DATE_EPOCH="$REPO_EPOCH" ./scripts/update-repo.sh

echo "All packages built successfully!"
echo ""
echo "To test locally:"
echo "  cd slackware64/packages"
echo "  python3 -m http.server 8000"
echo ""
echo "Repository structure:"
find slackware64/packages -type f -exec ls -lh {} \;
