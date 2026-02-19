#!/usr/bin/env python3
import argparse
import json
import os
import pathlib
import subprocess
import sys


LOCK_KEYS = (
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


def write_lock_file(path, values):
    lines = [f"{key}={values.get(key, '')}" for key in LOCK_KEYS]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def compute_repo_epoch(repo_root):
    max_epoch = 0
    for lock_path in sorted((repo_root / "packages").glob("*/source.lock")):
        data = parse_kv_file(lock_path)
        raw_epoch = data.get("SOURCE_DATE_EPOCH", "0")
        try:
            epoch = int(raw_epoch)
        except ValueError:
            epoch = 0
        if epoch > max_epoch:
            max_epoch = epoch
    return max_epoch


def render_summary(results):
    lines = []
    lines.append("## Apply results")
    lines.append("")
    lines.append("| Package | Result | Details |")
    lines.append("| --- | --- | --- |")
    for result in results:
        lines.append(
            f"| `{result['name']}` | `{result['result']}` | {result['details']} |"
        )
    lines.append("")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(
        description="Apply approved package updates from proposal manifest."
    )
    parser.add_argument("--repo-root", default=".", help="Repository root path")
    parser.add_argument(
        "--proposal-path", default="updates/proposal.json", help="Proposal JSON path"
    )
    parser.add_argument(
        "--failure-policy",
        choices=("continue", "fail-fast"),
        default="continue",
        help="How to handle package build failures",
    )
    parser.add_argument(
        "--summary-path",
        default="updates/apply-summary.md",
        help="Output summary markdown path",
    )
    parser.add_argument(
        "--report-path",
        default="updates/apply-result.json",
        help="Output machine-readable report path",
    )
    args = parser.parse_args()

    repo_root = pathlib.Path(args.repo_root).resolve()
    proposal_path = repo_root / args.proposal_path
    summary_path = repo_root / args.summary_path
    report_path = repo_root / args.report_path
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)

    if not proposal_path.exists():
        print(f"Proposal file not found: {proposal_path}", file=sys.stderr)
        return 2

    with proposal_path.open("r", encoding="utf-8") as handle:
        proposal = json.load(handle)

    packages = proposal.get("packages", [])
    results = []
    any_failures = False
    successful_updates = 0

    for package in packages:
        name = package.get("name", "<unknown>")
        selected = bool(package.get("selected"))
        status = package.get("status", "")
        proposed = package.get("proposed", {})

        if not selected:
            results.append(
                {"name": name, "result": "skipped", "details": "not selected"}
            )
            continue

        if not proposed:
            results.append(
                {
                    "name": name,
                    "result": "failed",
                    "details": "selected but proposal has no lock values",
                }
            )
            any_failures = True
            if args.failure_policy == "fail-fast":
                break
            continue

        missing = [key for key in LOCK_KEYS if not str(proposed.get(key, "")).strip()]
        if missing:
            results.append(
                {
                    "name": name,
                    "result": "failed",
                    "details": f"missing proposed keys: {', '.join(missing)}",
                }
            )
            any_failures = True
            if args.failure_policy == "fail-fast":
                break
            continue

        package_dir = repo_root / "packages" / name
        lock_path = package_dir / "source.lock"
        build_script = package_dir / "build.sh"

        if not package_dir.exists() or not build_script.exists():
            results.append(
                {
                    "name": name,
                    "result": "failed",
                    "details": "missing package directory or build.sh",
                }
            )
            any_failures = True
            if args.failure_policy == "fail-fast":
                break
            continue

        original_lock = (
            lock_path.read_text(encoding="utf-8") if lock_path.exists() else ""
        )
        write_lock_file(lock_path, proposed)

        print(f"Building package: {name} (status: {status})")
        build = subprocess.run(["./build.sh"], cwd=package_dir, check=False)
        if build.returncode != 0:
            lock_path.write_text(original_lock, encoding="utf-8")
            results.append(
                {
                    "name": name,
                    "result": "failed",
                    "details": f"build failed with exit code {build.returncode}",
                }
            )
            any_failures = True
            if args.failure_policy == "fail-fast":
                break
            continue

        successful_updates += 1
        results.append(
            {
                "name": name,
                "result": "updated",
                "details": proposed.get("RELEASE_TAG", ""),
            }
        )

    if successful_updates > 0:
        epoch = compute_repo_epoch(repo_root)
        env = dict(os.environ)
        env["SOURCE_DATE_EPOCH"] = str(epoch)
        print(f"Updating repository metadata with SOURCE_DATE_EPOCH={epoch}")
        subprocess.run(["./scripts/update-repo.sh"], cwd=repo_root, env=env, check=True)
    else:
        print("No packages were updated; skipping repository metadata refresh.")

    summary = render_summary(results)
    summary_path.write_text(summary, encoding="utf-8")
    report = {
        "updated_count": successful_updates,
        "failed_count": len([r for r in results if r["result"] == "failed"]),
        "skipped_count": len([r for r in results if r["result"] == "skipped"]),
        "results": results,
    }
    report_path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    print(summary)
    print(f"Wrote summary: {summary_path}")
    print(f"Wrote report:  {report_path}")

    return 1 if any_failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
