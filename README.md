# UnRAID Slackware Packages

Auto-maintained Slackware packages for UnRAID, compatible with [un-get](https://github.com/ich777/un-get).

## Packages

- **Atuin** - Shell history manager
- **Chezmoi** - Dotfiles manager
- **just** - Command runner

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

```bash
./scripts/add-package.sh <name> <owner/repo> '<asset-template>' [homepage] [short-description]
```

Example for `just`:

```bash
./scripts/add-package.sh just casey/just 'just-{{VERSION}}-x86_64-unknown-linux-musl.tar.gz' https://github.com/casey/just 'command runner'
```

Then run:

```bash
./build-all.sh
```

Review and commit lock-file changes, then run:

```bash
./build-all.sh
```

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
