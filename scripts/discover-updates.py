#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request


REQUIRED_LOCK_KEYS = (
    "VERSION",
    "RELEASE_TAG",
    "SOURCE_REPOSITORY",
    "SOURCE_COMMIT",
    "SOURCE_URL",
    "SOURCE_SHA256",
    "SOURCE_DATE_EPOCH",
)


def parse_kv_file(path):
    data = {}
    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            data[key.strip()] = value.strip()
    return data


def github_json(url, token=None):
    request = urllib.request.Request(url)
    request.add_header("Accept", "application/vnd.github+json")
    request.add_header("X-GitHub-Api-Version", "2022-11-28")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def resolve_tag_commit(repository, tag, token=None):
    ref_url = f"https://api.github.com/repos/{repository}/git/ref/tags/{tag}"
    ref = github_json(ref_url, token=token)
    ref_obj = ref["object"]
    sha = ref_obj["sha"]
    if ref_obj.get("type") == "tag":
        tag_obj = github_json(ref_obj["url"], token=token)
        sha = tag_obj["object"]["sha"]
    return sha


def sha256_of_url(url):
    hasher = hashlib.sha256()
    with urllib.request.urlopen(url) as response:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            hasher.update(chunk)
    return hasher.hexdigest()


def summarize(packages):
    lines = []
    lines.append("## Proposed package updates")
    lines.append("")
    lines.append("| Package | Current | Proposed | Status | Selected |")
    lines.append("| --- | --- | --- | --- | --- |")
    for pkg in packages:
        current = pkg.get("current", {}).get("RELEASE_TAG", "-")
        proposed = pkg.get("proposed", {}).get("RELEASE_TAG", "-")
        selected = "yes" if pkg.get("selected") else "no"
        lines.append(
            f"| `{pkg['name']}` | `{current}` | `{proposed}` | `{pkg['status']}` | {selected} |"
        )

    lines.append("")
    lines.append("### Review instructions")
    lines.append("")
    lines.append(
        "- Edit `updates/proposal.json` in this PR branch if you want to change selections or override values."
    )
    lines.append(
        "- Keep `selected: true` only for packages you want to apply in the next step."
    )
    lines.append(
        "- Run the **Apply Approved Updates** workflow with this branch as `proposal_ref`."
    )
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(
        description="Discover package updates and write a proposal manifest."
    )
    parser.add_argument("--repo-root", default=".", help="Repository root path")
    parser.add_argument(
        "--proposal-path",
        default="updates/proposal.json",
        help="Output proposal JSON path",
    )
    parser.add_argument(
        "--summary-path",
        default="updates/discovery-summary.md",
        help="Output markdown summary path",
    )
    args = parser.parse_args()

    repo_root = pathlib.Path(args.repo_root).resolve()
    packages_root = repo_root / "packages"
    proposal_path = repo_root / args.proposal_path
    summary_path = repo_root / args.summary_path
    proposal_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.parent.mkdir(parents=True, exist_ok=True)

    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")

    packages = []
    if not packages_root.exists():
        print(f"Missing packages directory: {packages_root}", file=sys.stderr)
        return 1

    for package_dir in sorted(packages_root.iterdir()):
        if not package_dir.is_dir():
            continue
        name = package_dir.name
        conf_file = package_dir / "package.conf"
        lock_file = package_dir / "source.lock"

        entry = {
            "name": name,
            "path": f"packages/{name}",
            "selected": False,
            "status": "error",
            "reason": "",
            "current": {},
            "proposed": {},
        }

        try:
            if not conf_file.exists():
                entry["reason"] = "missing package.conf"
                packages.append(entry)
                continue
            conf = parse_kv_file(conf_file)
            repository = conf.get("REPOSITORY", "")
            asset_template = conf.get("ASSET_TEMPLATE", "")
            if not repository or not asset_template:
                entry["reason"] = "REPOSITORY and ASSET_TEMPLATE are required"
                packages.append(entry)
                continue

            current_lock = parse_kv_file(lock_file) if lock_file.exists() else {}
            entry["current"] = {
                key: current_lock.get(key, "") for key in REQUIRED_LOCK_KEYS
            }

            release = github_json(
                f"https://api.github.com/repos/{repository}/releases/latest",
                token=token,
            )
            release_tag = release["tag_name"]
            published_at = release["published_at"]
            version = release_tag[1:] if release_tag.startswith("v") else release_tag
            asset_name = asset_template.replace("{{VERSION}}", version).replace(
                "{{TAG}}", release_tag
            )
            source_url = f"https://github.com/{repository}/releases/download/{release_tag}/{asset_name}"
            source_sha256 = sha256_of_url(source_url)
            source_commit = resolve_tag_commit(repository, release_tag, token=token)

            from datetime import datetime

            source_date_epoch = int(
                datetime.fromisoformat(published_at.replace("Z", "+00:00")).timestamp()
            )

            proposed = {
                "VERSION": version,
                "RELEASE_TAG": release_tag,
                "SOURCE_REPOSITORY": repository,
                "SOURCE_COMMIT": source_commit,
                "SOURCE_URL": source_url,
                "SOURCE_SHA256": source_sha256,
                "SOURCE_DATE_EPOCH": str(source_date_epoch),
            }
            entry["proposed"] = proposed

            if (
                current_lock.get("RELEASE_TAG") == release_tag
                and current_lock.get("SOURCE_SHA256") == source_sha256
            ):
                entry["status"] = "up_to_date"
                entry["reason"] = "already pinned to latest release"
                entry["selected"] = False
            else:
                entry["status"] = "candidate_ready"
                entry["reason"] = "new release available"
                entry["selected"] = True

        except urllib.error.HTTPError as exc:
            entry["status"] = "error"
            entry["reason"] = f"http error {exc.code}: {exc.reason}"
        except Exception as exc:  # noqa: BLE001
            entry["status"] = "error"
            entry["reason"] = str(exc)

        packages.append(entry)

    proposal = {
        "schema_version": 1,
        "base_branch": "main",
        "packages": packages,
    }

    with proposal_path.open("w", encoding="utf-8") as handle:
        json.dump(proposal, handle, indent=2, sort_keys=True)
        handle.write("\n")

    summary = summarize(packages)
    with summary_path.open("w", encoding="utf-8") as handle:
        handle.write(summary)

    print(summary)
    print(f"Wrote proposal: {proposal_path}")
    print(f"Wrote summary:  {summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
