#!/usr/bin/env python3
"""Generate a markdown coverage report from an xcresult bundle.

Usage: coverage_report.py <path.xcresult> <output.md>

Reads line-coverage via `xccov` and the test tally via `xcresulttool`,
then emits a PR-comment-ready markdown report: overall bar, app-code
metric (excluding generated + vendored sources), a spotlight on the
capture/session core, and a collapsible per-file table.
"""
import json
import os
import subprocess
import sys

BAR_WIDTH = 20

# Generated or vendored code — shown in the full table but excluded from
# the "app code" headline metric.
EXCLUDED_SUBSTRINGS = ("FlatBufferSchemas_generated.swift", "/Theater/")

# The load-bearing core: the capture stack and the actor/session layer.
SPOTLIGHT = [
    "CaptureEngine.swift",
    "RecordingPipeline.swift",
    "FrameStreamingCoordinator.swift",
    "CameraViewController.swift",
    "RemoteCamSession.swift",
    "MonitorActor.swift",
    "FrameStreamer.swift",
    "RemoteCmdFlatBuffers.swift",
]


def bar(fraction):
    filled = round(fraction * BAR_WIDTH)
    return "█" * filled + "░" * (BAR_WIDTH - filled)


def dot(fraction):
    if fraction >= 0.8:
        return "🟢"
    if fraction >= 0.5:
        return "🟡"
    return "🔴"


def pct(fraction):
    return f"{fraction * 100:.1f}%"


def test_tally(xcresult):
    """Best-effort test counts; xcresulttool interfaces vary by Xcode."""
    try:
        raw = subprocess.check_output(
            ["xcrun", "xcresulttool", "get", "test-results", "summary",
             "--path", xcresult, "--compact"],
            stderr=subprocess.DEVNULL)
        summary = json.loads(raw)
        total = summary.get("totalTestCount")
        passed = summary.get("passedTests")
        failed = summary.get("failedTests", 0)
        skipped = summary.get("skippedTests", 0)
        if total is None or passed is None:
            return None
        return total, passed, failed, skipped
    except (subprocess.CalledProcessError, json.JSONDecodeError, OSError):
        return None


def main():
    xcresult, out_path = sys.argv[1], sys.argv[2]

    report = json.loads(subprocess.check_output(
        ["xcrun", "xccov", "view", "--report", "--json", xcresult]))

    app = next((t for t in report.get("targets", [])
                if t.get("name", "").endswith(".app")), None)
    if app is None:
        sys.exit("No .app target found in coverage report")

    files = sorted(app.get("files", []),
                   key=lambda f: f.get("lineCoverage", 0), reverse=True)

    app_files = [f for f in files
                 if not any(s in f.get("path", "") for s in EXCLUDED_SUBSTRINGS)]
    covered = sum(f.get("coveredLines", 0) for f in app_files)
    executable = sum(f.get("executableLines", 0) for f in app_files)
    app_fraction = covered / executable if executable else 0.0
    overall = app.get("lineCoverage", 0.0)

    lines = []
    lines.append("## 📊 Test Coverage Report")
    lines.append("")

    tally = test_tally(xcresult)
    if tally:
        total, passed, failed, skipped = tally
        badge = "✅" if failed == 0 else "❌"
        tally_text = f"{badge} **{passed}/{total} tests passed**"
        if failed:
            tally_text += f" · 🔻 {failed} failed"
        if skipped:
            tally_text += f" · ⏭️ {skipped} skipped"
        lines.append(tally_text)
        lines.append("")

    lines.append("| Metric | Coverage | |")
    lines.append("|---|---|---|")
    lines.append(f"| **App code** (excl. generated + vendored Theater) "
                 f"| `{bar(app_fraction)}` **{pct(app_fraction)}** | {dot(app_fraction)} |")
    lines.append(f"| Whole target | `{bar(overall)}` {pct(overall)} | {dot(overall)} |")
    lines.append("")

    lines.append("### 🎥 Capture & session core")
    lines.append("")
    lines.append("| File | Coverage | Lines | |")
    lines.append("|---|---|---|---|")
    by_name = {f.get("name"): f for f in files}
    for name in SPOTLIGHT:
        f = by_name.get(name)
        if not f:
            continue
        frac = f.get("lineCoverage", 0.0)
        lines.append(f"| `{name}` | `{bar(frac)}` {pct(frac)} "
                     f"| {f.get('coveredLines', 0)}/{f.get('executableLines', 0)} "
                     f"| {dot(frac)} |")
    lines.append("")

    lines.append("<details>")
    lines.append(f"<summary>📁 Full report — {len(files)} files</summary>")
    lines.append("")
    lines.append("| File | Coverage | Lines | |")
    lines.append("|---|---|---|---|")
    for f in files:
        frac = f.get("lineCoverage", 0.0)
        name = f.get("name", "?")
        excluded = any(s in f.get("path", "") for s in EXCLUDED_SUBSTRINGS)
        suffix = " *(excluded from app-code metric)*" if excluded else ""
        lines.append(f"| `{name}`{suffix} | `{bar(frac)}` {pct(frac)} "
                     f"| {f.get('coveredLines', 0)}/{f.get('executableLines', 0)} "
                     f"| {dot(frac)} |")
    lines.append("")
    lines.append("</details>")
    lines.append("")

    sha = os.environ.get("GITHUB_SHA", "")[:7]
    server = os.environ.get("GITHUB_SERVER_URL", "")
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    if sha and repo and run_id:
        lines.append(f"_Generated from `{sha}` · "
                     f"[workflow run]({server}/{repo}/actions/runs/{run_id})_")
        lines.append("")

    with open(out_path, "w") as handle:
        handle.write("\n".join(lines))
    print(f"Wrote {out_path}")


if __name__ == "__main__":
    main()
