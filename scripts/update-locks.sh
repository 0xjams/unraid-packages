#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

if command -v sha256sum >/dev/null 2>&1; then
  SHA256_BIN=sha256sum
elif command -v shasum >/dev/null 2>&1; then
  SHA256_BIN="shasum -a 256"
else
  echo "sha256 checksum tool not found (need sha256sum or shasum)."
  exit 1
fi

json_value() {
  local repo="$1"
  local expr="$2"
  python3 - "$repo" "$expr" <<'PY'
import json
import sys
import urllib.request

repo = sys.argv[1]
expr = sys.argv[2]
data = json.load(urllib.request.urlopen(f"https://api.github.com/repos/{repo}/releases/latest"))
print(data[expr])
PY
}

resolve_tag_commit() {
  local repo="$1"
  local tag="$2"
  python3 - "$repo" "$tag" <<'PY'
import json
import sys
import urllib.request

repo = sys.argv[1]
tag = sys.argv[2]
ref = json.load(urllib.request.urlopen(f"https://api.github.com/repos/{repo}/git/ref/tags/{tag}"))
obj = ref["object"]
sha = obj["sha"]
if obj["type"] == "tag":
    tag_obj = json.load(urllib.request.urlopen(obj["url"]))
    sha = tag_obj["object"]["sha"]
print(sha)
PY
}

iso_to_epoch() {
  local iso_timestamp="$1"
  python3 - "$iso_timestamp" <<'PY'
from datetime import datetime
import sys

print(int(datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00")).timestamp()))
PY
}

write_lock() {
  local package_dir="$1"
  local conf_file="$package_dir/package.conf"
  local lock_file="$package_dir/source.lock"
  local tmp_dir

  if [ ! -f "$conf_file" ]; then
    echo "Skipping $package_dir (missing package.conf)"
    return
  fi

  unset PRGNAM REPOSITORY ASSET_TEMPLATE BINARY_NAME HOMEPAGE

  # shellcheck disable=SC1090
  . "$conf_file"

  local package_name repo asset_template
  package_name=${PRGNAM:-$(basename "$package_dir")}
  repo=${REPOSITORY:-}
  asset_template=${ASSET_TEMPLATE:-}

  if [ -z "$repo" ] || [ -z "$asset_template" ]; then
    echo "Skipping $package_name: REPOSITORY and ASSET_TEMPLATE are required in package.conf"
    return
  fi

  local release_tag
  release_tag=$(json_value "$repo" "tag_name")
  local published_at
  published_at=$(json_value "$repo" "published_at")
  local source_commit
  source_commit=$(resolve_tag_commit "$repo" "$release_tag")

  local version="${release_tag#v}"
  local asset_name
  asset_name=$(printf '%s' "$asset_template" | sed "s/{{VERSION}}/$version/g; s/{{TAG}}/$release_tag/g")
  local source_url
  source_url="https://github.com/$repo/releases/download/$release_tag/$asset_name"

  tmp_dir=$(mktemp -d)

  curl -L --fail --silent --show-error -o "$tmp_dir/source.tar.gz" "$source_url"
  local source_sha256
  source_sha256=$($SHA256_BIN "$tmp_dir/source.tar.gz" | awk '{print $1}')
  local source_date_epoch
  source_date_epoch=$(iso_to_epoch "$published_at")

  cat > "$lock_file" <<EOF
VERSION=$version
RELEASE_TAG=$release_tag
SOURCE_REPOSITORY=$repo
SOURCE_COMMIT=$source_commit
SOURCE_URL=$source_url
SOURCE_SHA256=$source_sha256
SOURCE_DATE_EPOCH=$source_date_epoch
EOF

  rm -rf "$tmp_dir"
  echo "Updated $lock_file -> $version"
}

for package_dir in "$ROOT_DIR"/packages/*; do
  if [ -d "$package_dir" ]; then
    write_lock "$package_dir"
  fi
done
