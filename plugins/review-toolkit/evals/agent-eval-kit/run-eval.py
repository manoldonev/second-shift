"""
Shared helpers for the eval harnesses that drive the `claude` CLI: a hard-timeout subprocess
runner, the CLI's JSON envelope parser, quota-stop detection and the append-only changelog row.

Loaded by path through importlib (the hyphenated filename is not importable by name); see
README.md beside this file.
"""

from __future__ import annotations

import asyncio
import datetime as dt
import json
import re
from pathlib import Path


# Substrings in CLI output that indicate a quota/rate-limit stop. Any one of them in a session's
# text aborts the whole run: further calls only burn quota with no signal.
RATE_LIMIT_MARKERS = (
    "You've hit your limit",
    "You have hit your limit",
    "You've reached your",
    "resets at",
    "session limit",
    "usage limit",
)


class RateLimitedError(RuntimeError):
    pass


async def run_claude(args, timeout_s: float, cwd: Path):
    """Invoke `claude` CLI with a HARD wall-clock kill at timeout_s."""
    proc = await asyncio.create_subprocess_exec(
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        cwd=cwd,
    )

    async def _kill_after(t):
        await asyncio.sleep(t)
        if proc.returncode is None:
            proc.kill()

    watchdog = asyncio.create_task(_kill_after(timeout_s))
    try:
        stdout, stderr = await proc.communicate()
    finally:
        watchdog.cancel()
        try:
            await watchdog
        except (asyncio.CancelledError, Exception):
            pass
    return proc.returncode, stdout, stderr


def extract_result_text(stdout: bytes):
    raw = stdout.decode(errors="replace").strip()
    if not raw:
        return "", {}
    try:
        envelope = json.loads(raw)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}\s*$", raw, re.DOTALL)
        if not match:
            return raw, {"parse_error": True}
        try:
            envelope = json.loads(match.group(0))
        except json.JSONDecodeError:
            return raw, {"parse_error": True}
    text = envelope.get("result") or envelope.get("text") or ""
    return text, envelope


def changelog_row(started_at: dt.datetime, segments: list[str]) -> str:
    """One append-only changelog line: the ISO start time, then `k=v` segments joined by ` | `."""
    return f"{started_at.isoformat()} | " + " | ".join(segments) + "\n"


def append_changelog(changelog: Path, line: str) -> None:
    with changelog.open("a") as f:
        f.write(line)


def check_rate_limit(text: str, where: str):
    for marker in RATE_LIMIT_MARKERS:
        if marker in text:
            raise RateLimitedError(
                f"Rate limit detected in {where}: {marker!r}. "
                f"Aborting — re-run after quota reset."
            )
