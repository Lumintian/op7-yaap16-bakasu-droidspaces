#!/usr/bin/env python3
"""Add the ReSukiSU Manager artifact for the pinned commit to the Actions summary."""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from typing import Optional
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


RESUKI_REPOSITORY = "Baka-SU/BakaSU"
WORKFLOW_FILE = "build-manager.yml"
WORKFLOW_URL = (
    f"https://github.com/{RESUKI_REPOSITORY}/actions/workflows/{WORKFLOW_FILE}"
)
API_ROOT = "https://api.github.com"


class ApiError(RuntimeError):
    """Raised when GitHub's public API cannot be queried."""


def pinned_commit() -> str:
    pins = Path(__file__).resolve().parents[1] / "config" / "pins.sh"
    prefix = "RESUKI_COMMIT="
    for line in pins.read_text(encoding="utf-8").splitlines():
        if line.startswith(prefix):
            commit = line[len(prefix) :].strip()
            if re.fullmatch(r"[0-9a-f]{40}", commit):
                return commit
            break
    raise RuntimeError("config/pins.sh does not contain a valid RESUKI_COMMIT")


def get_json(url: str) -> dict:
    """Fetch JSON, retrying without the repository token for public API access."""
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "yaap16-resuki-release-link",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    tokens = [token, ""] if token else [""]
    last_error: Optional[Exception] = None

    for candidate in tokens:
        request_headers = dict(headers)
        if candidate:
            request_headers["Authorization"] = f"Bearer {candidate}"
        try:
            request = Request(url, headers=request_headers)
            with urlopen(request, timeout=30) as response:
                payload = json.load(response)
            if isinstance(payload, dict):
                return payload
            raise ApiError("GitHub API returned a non-object response")
        except HTTPError as error:
            last_error = error
            if not candidate or error.code not in (401, 403, 404):
                break
        except (URLError, TimeoutError, ValueError) as error:
            last_error = error
            break

    if isinstance(last_error, HTTPError):
        raise ApiError(f"GitHub API returned HTTP {last_error.code}") from last_error
    raise ApiError("GitHub API request failed") from last_error


def find_successful_run(commit: str) -> Optional[dict]:
    query = urlencode(
        {
            "head_sha": commit,
            "status": "success",
            "per_page": "100",
        }
    )
    endpoint = (
        f"{API_ROOT}/repos/{RESUKI_REPOSITORY}/actions/workflows/"
        f"{WORKFLOW_FILE}/runs?{query}"
    )
    runs = get_json(endpoint).get("workflow_runs", [])
    matches = [
        run
        for run in runs
        if isinstance(run, dict)
        and run.get("head_sha", "").lower() == commit
        and run.get("conclusion") == "success"
    ]
    matches.sort(
        key=lambda run: (
            run.get("run_started_at") or run.get("created_at") or "",
            int(run.get("id", 0)),
        ),
        reverse=True,
    )
    return matches[0] if matches else None


def find_release_artifact(run_id: int) -> Optional[dict]:
    endpoint = (
        f"{API_ROOT}/repos/{RESUKI_REPOSITORY}/actions/runs/"
        f"{run_id}/artifacts?per_page=100"
    )
    artifacts = get_json(endpoint).get("artifacts", [])
    candidates = [
        artifact
        for artifact in artifacts
        if isinstance(artifact, dict)
        and not artifact.get("expired", False)
        and artifact.get("name") == "Manager-release"
    ]
    if not candidates:
        return None
    return candidates[0]


def run_url(run_id: int) -> str:
    return f"https://github.com/{RESUKI_REPOSITORY}/actions/runs/{run_id}"


def artifact_url(run_id: int, artifact_id: int) -> str:
    return f"{run_url(run_id)}/artifacts/{artifact_id}"


def summary_text(
    commit: str,
    run: Optional[dict],
    artifact: Optional[dict],
    lookup_failed: bool,
) -> str:
    commit_url = f"https://github.com/{RESUKI_REPOSITORY}/commit/{commit}"
    lines = [
        "## ReSukiSU Manager release",
        "",
        f"- ReSukiSU commit: [`{commit}`]({commit_url})",
    ]

    if run is None:
        if lookup_failed:
            lines.append(
                "- Release lookup was unavailable; "
                f"[open the Build Manager workflow]({WORKFLOW_URL})."
            )
        else:
            lines.append(
                "- No successful Build Manager run was found for this commit; "
                f"[open the Build Manager workflow]({WORKFLOW_URL})."
            )
        return "\n".join(lines) + "\n"

    current_run_id = int(run["id"])
    run_number = run.get("run_number", current_run_id)
    run_link = run_url(current_run_id)
    lines.append(f"- Workflow run: [Build Manager #{run_number}]({run_link})")
    if artifact is None:
        lines.append(
            "- `Manager-release` is not available (it may have expired); "
            f"[open the workflow run]({run_link})."
        )
    else:
        artifact_id = int(artifact["id"])
        artifact_name = artifact.get("name", "Manager-release")
        lines.append(
            f"- Release artifact: [{artifact_name}]"
            f"({artifact_url(current_run_id, artifact_id)})"
        )
    return "\n".join(lines) + "\n"


def write_summary(text: str) -> None:
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY", "").strip()
    if not summary_path:
        print(text, end="")
        return
    with Path(summary_path).open("a", encoding="utf-8") as summary:
        summary.write("\n" + text)


def main() -> int:
    try:
        commit = pinned_commit()
    except (OSError, RuntimeError) as error:
        print(f"warning: cannot read ReSukiSU pin: {error}", file=sys.stderr)
        return 0

    run = None
    artifact = None
    lookup_failed = False
    try:
        run = find_successful_run(commit)
        if run is not None:
            try:
                artifact = find_release_artifact(int(run["id"]))
            except (ApiError, KeyError, TypeError, ValueError) as error:
                print(f"warning: cannot list ReSukiSU artifacts: {error}", file=sys.stderr)
    except (ApiError, KeyError, TypeError, ValueError) as error:
        lookup_failed = True
        print(f"warning: cannot find ReSukiSU workflow run: {error}", file=sys.stderr)

    write_summary(summary_text(commit, run, artifact, lookup_failed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
