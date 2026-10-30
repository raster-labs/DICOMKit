#!/usr/bin/env python3
"""Reuse successful focused PR CI only for the identical complete Git tree."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", required=True)
    parser.add_argument("--validation", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[1-9][0-9]*", args.run):
        raise ValueError("Expected a CI run ID")
    repository = os.environ["GITHUB_REPOSITORY"]
    def api(path):
        return json.loads(subprocess.check_output(
            ["gh", "api", "repos/" + repository + "/" + path], text=True))
    run = api("actions/runs/" + args.run)
    assert run["status"] == "completed" and run["conclusion"] == "success"
    assert run["event"] == "pull_request" and run["path"] == ".github/workflows/ci.yml"
    assert run["repository"]["full_name"].lower() == repository.lower()
    assert run["head_repository"]["id"] == run["repository"]["id"]
    head = run["head_sha"]
    assert re.fullmatch(r"[0-9a-f]{40}", head)
    tree = git("rev-parse", "HEAD^{tree}")
    assert git("rev-parse", head + "^{tree}") == tree, "Completed CI tree differs"
    subprocess.run(["git", "merge-base", "--is-ancestor", head, "HEAD"], check=True)
    assert not git("status", "--porcelain", "--untracked-files=no")
    attempt = run["run_attempt"]
    jobs = api(f"actions/runs/{args.run}/attempts/{attempt}/jobs?per_page=100")
    assert jobs["total_count"] == len(jobs["jobs"]), "Incomplete CI job listing"
    matches = [j for j in jobs["jobs"] if j["name"] == "Test on macOS 26 (Swift 6.4)"]
    assert len(matches) == 1
    job = matches[0]
    assert job["status"] == "completed" and job["conclusion"] == "success"
    steps = {step["name"]: step for step in job["steps"]}
    for name in ("Build and discover focused Debug test products", "Run focused tests (81 Core, 15 bounded input and 6 CLI)"):
        assert steps[name]["conclusion"] == "success", "Focused CI step did not pass: " + name
    validation = json.loads(args.validation.read_text())
    assert validation["validationCommit"] == git("rev-parse", "HEAD")
    assert validation["validationTree"] == tree
    validation["reusedCI"] = {
        "run": int(args.run), "attempt": attempt, "head": head, "tree": tree,
        "url": run["html_url"], "workflowPath": run["path"], "testJobId": job["id"],
        "testScope": "81 Core, 15 bounded-input and 6 CLI tests",
    }
    args.validation.write_text(json.dumps(validation, indent=2) + "\n")
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write("reuse=true\n")
    print(f"Reusing successful focused CI {args.run} for identical tree {tree}")


if __name__ == "__main__":
    main()
