#!/bin/bash
# Repository metadata update script (deterministic)
set -euo pipefail

export LC_ALL=C
export TZ=UTC

REPO_DIR="slackware64/packages"
cd "$REPO_DIR"

shopt -s nullglob

if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
  BUILD_EPOCH="$SOURCE_DATE_EPOCH"
else
  BUILD_EPOCH=$(date -u +%s)
fi

DATE_HEADER=$(python3 - "$BUILD_EPOCH" <<'PY'
from datetime import datetime, timezone
import sys
epoch = int(sys.argv[1])
print(datetime.fromtimestamp(epoch, timezone.utc).strftime("%a %b %d %H:%M:%S UTC %Y"))
PY
)

packages=( *.txz )

if [ ${#packages[@]} -eq 0 ]; then
  echo "No .txz files found in $REPO_DIR"
  : > PACKAGES.TXT
  : > CHECKSUMS.md5
  : > FILELIST.TXT
  : > MANIFEST.bz2
  exit 0
fi

sorted_packages=$(printf '%s\n' "${packages[@]}" | sort)

echo "Generating PACKAGES.TXT..."
{
  echo "PACKAGES.TXT; $DATE_HEADER"
  echo ""
  for pkg in $sorted_packages; do
    COMPRESSED_SIZE=$(wc -c < "$pkg" | tr -d ' ')
    UNCOMPRESSED_SIZE=$(python3 - "$pkg" <<'PY'
import sys
import tarfile

size = 0
with tarfile.open(sys.argv[1], mode="r:xz") as archive:
    for member in archive.getmembers():
        if member.isfile():
            size += member.size
print(size)
PY
)

    DESCRIPTION=$(python3 - "$pkg" <<'PY'
import sys
import tarfile

with tarfile.open(sys.argv[1], mode="r:xz") as archive:
    try:
        text = archive.extractfile("./install/slack-desc").read().decode("utf-8", errors="replace")
    except Exception:
        try:
            text = archive.extractfile("install/slack-desc").read().decode("utf-8", errors="replace")
        except Exception:
            text = ""

lines = [line for line in text.splitlines() if line and not line.startswith("#")]
print("\n".join(lines))
PY
)

    echo "PACKAGE NAME: $pkg"
    echo "PACKAGE LOCATION: ./$pkg"
    echo "PACKAGE SIZE (compressed): $COMPRESSED_SIZE"
    echo "PACKAGE SIZE (uncompressed): $UNCOMPRESSED_SIZE"
    echo "PACKAGE DESCRIPTION:"
    if [ -n "$DESCRIPTION" ]; then
      printf '%s\n' "$DESCRIPTION"
    else
      echo "$pkg: Package description not available"
    fi
    echo ""
  done
} > PACKAGES.TXT

echo "Generating CHECKSUMS.md5..."
if command -v md5sum >/dev/null 2>&1; then
  md5sum $sorted_packages > CHECKSUMS.md5
else
  {
    for pkg in $sorted_packages; do
      printf '%s  %s\n' "$(md5 -q "$pkg")" "$pkg"
    done
  } > CHECKSUMS.md5
fi

echo "Generating MANIFEST.bz2..."
{
  for pkg in $sorted_packages; do
    echo "++=========================================="
    echo "||   Package: $pkg"
    echo "++=========================================="
    tar -tvf "$pkg"
    echo ""
  done
} | bzip2 > MANIFEST.bz2

echo "Generating FILELIST.TXT..."
FILELIST_DATE=$(python3 - "$BUILD_EPOCH" <<'PY'
from datetime import datetime, timezone
import sys
epoch = int(sys.argv[1])
print(datetime.fromtimestamp(epoch, timezone.utc).strftime("%b %d %Y"))
PY
)

{
  echo "$DATE_HEADER"
  echo ""
  echo "Here is the file list for https://github.com/0xjams/unraid-packages,"
  echo "maintained by <hi(at)0xjams(dot)com>"
  echo ""

  file_listing=$(printf '%s\n' "$sorted_packages" CHECKSUMS.md5 MANIFEST.bz2 PACKAGES.TXT | sort)
  for file in $file_listing; do
    SIZE=$(wc -c < "$file" | tr -d ' ')
    printf '%s\n' "-rw-r--r-- 1 root root $SIZE $FILELIST_DATE ./$file"
  done
} > FILELIST.TXT

echo "Repository metadata updated successfully!"
echo "Generated: PACKAGES.TXT, CHECKSUMS.md5, MANIFEST.bz2, FILELIST.TXT"
