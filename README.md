# UnRAID Slackware Packages

Auto-maintained Slackware packages for UnRAID, compatible with [un-get](https://github.com/ich777/un-get).

## Packages

- **Atuin** - Shell history manager
- **Chezmoi** - Dotfiles manager
- **just** - Command runner
- **restic** - Fast, secure backup program
- **rclone** - Cloud storage sync tool

## Installation

Add this repository to your un-get sources:

```bash
echo "https://raw.githubusercontent.com/0xjams/unraid-packages/refs/heads/main/slackware64/packages/ 0xjams-repo" >> /boot/config/plugins/un-get/sources.list
```

Then install packages:

```bash
un-get update
un-get install atuin
```

## Repository Structure

This repository follows the Slackware standard and uses pinned source locks for reproducible package builds.

## Reproducible builds

Each package has a lock file that pins immutable build inputs:

- `packages/atuin/source.lock`
- `packages/chezmoi/source.lock`
- `packages/just/source.lock`
- `packages/restic/source.lock`
- `packages/rclone/source.lock`

Each lock stores:

- exact release tag/version
- resolved commit SHA for the tag
- source artifact URL
- SHA256 of that artifact
- `SOURCE_DATE_EPOCH`

`./build-all.sh` refreshes lock files from GitHub latest releases by default, then builds from the newly pinned lock inputs.

### Update pinned versions

```bash
./scripts/update-locks.sh
```

### Add a new binary package

Use `add-package.sh` to scaffold a package and pin it from GitHub releases:

```bash
./scripts/add-package.sh <name> <owner/repo> '<asset-template>' [homepage] [short-description]
```

The asset template supports:

- `{{VERSION}}` (tag without leading `v`)
- `{{TAG}}` (full tag, such as `v1.2.3`)

Example (`rclone`):

```bash
./scripts/add-package.sh rclone rclone/rclone 'rclone-v{{VERSION}}-linux-amd64.zip' https://github.com/rclone/rclone 'cloud storage sync tool'
```

What this does automatically:

1. Creates `packages/<name>/` with `package.conf`, `build.sh`, `<name>.SlackBuild`, and `slack-desc`
2. Runs `./scripts/update-locks.sh` to generate/update `packages/<name>/source.lock`

Then follow this workflow:

1. **Review package config and lock pinning**
   - Confirm `packages/<name>/package.conf`
   - Confirm `packages/<name>/source.lock` (`RELEASE_TAG`, `SOURCE_COMMIT`, `SOURCE_SHA256`, `SOURCE_DATE_EPOCH`)
2. **Adjust extraction logic if needed**
   - The default deterministic builder expects tarball-style archives
   - If upstream ships another format (for example `.zip` or `.bz2`), customize `packages/<name>/<name>.SlackBuild`
3. **Build only the new package first**

```bash
cd packages/<name>
./build.sh
```

4. **Regenerate repository metadata**

```bash
cd ../..
SOURCE_DATE_EPOCH=$(python3 - <<'PY'
import glob

max_epoch = 0
for path in glob.glob('packages/*/source.lock'):
    with open(path, encoding='utf-8') as handle:
        for line in handle:
            if line.startswith('SOURCE_DATE_EPOCH='):
                max_epoch = max(max_epoch, int(line.strip().split('=', 1)[1]))
                break
print(max_epoch)
PY
) ./scripts/update-repo.sh
```

5. **Verify index entries**
   - Check `slackware64/packages/PACKAGES.TXT`
   - Check `slackware64/packages/CHECKSUMS.md5`
   - Check `slackware64/packages/FILELIST.TXT`

After the new package looks correct, run `./build-all.sh` for a full refresh when desired.

### Manual update pipeline (GitHub Actions)

This repository includes a manual two-step workflow for package updates:

1. **Discover Package Updates** (`.github/workflows/discover-updates.yml`)
   - Trigger manually from the Actions tab
   - Scans all packages, resolves latest releases, computes hashes, and writes `updates/proposal.json`
   - Creates/updates a PR from `automation/update-proposals` with `updates/discovery-summary.md`
2. **Apply Approved Updates** (`.github/workflows/apply-approved-updates.yml`)
   - Trigger manually after reviewing the proposal PR
   - Reads `updates/proposal.json`, applies only `selected: true` entries, builds packages, and regenerates metadata
   - Can run as `dry-run` or `commit`

Recommended flow:

1. Run **Discover Package Updates**
2. Review/edit `updates/proposal.json` in the proposal PR (toggle `selected`, adjust values if needed)
3. Run **Apply Approved Updates** with `proposal_ref=automation/update-proposals`
4. Review resulting PR changes and merge manually

If you decide not to proceed, close the proposal PR and no changes will land on `main`.

To build without refreshing locks (for strict reruns):

```bash
SKIP_LOCK_REFRESH=1 ./build-all.sh
```

### Verify reproducibility

```bash
./scripts/verify-reproducible.sh
```

### Verify a package hash

```bash
./scripts/verify-package-hash.sh <package-name> <hash> [sha256|md5|auto]
```

Example:

```bash
./scripts/verify-package-hash.sh atuin 4b305a9e2ea6fac087271b95f54a5b5291f4d70a63e986d96319b6e0e929b594
```

## Roadmap

- Monitor upstream releases and commit lock-file updates via GitHub Actions
- Build from pinned lock inputs and verify deterministic package hashes in CI

## Manual Building

To build packages manually:

```bash
cd packages/atuin
./build.sh
```
