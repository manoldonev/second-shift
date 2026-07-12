#!/usr/bin/env python3
"""
Generic Claude Code agent eval harness.

Agnostic to the specific agent under test. Invokes any named agent via
`claude -p --agent <name>` against a directory of fixtures and scores each
output via an LLM judge configured per eval instance.

To create a new eval:
  1. Make a directory for it under a plugin's evals/ (e.g.
     plugins/<plugin>/evals/my-agent-eval/).
  2. Drop a rubric.py into it defining JUDGE_SYSTEM and MAX_POINTS.
  3. Drop fixtures (*.md + *.expected.json pairs) into a fixtures directory
     (flat layout) OR a directory-per-fixture layout with issue-body.md +
     expected.json + optional mock-*.txt + optional mock-env/ per dir.
  4. Invoke this script with --agent-name, --rubric, --fixtures-dir, --eval-dir.

See ../agent-eval-kit/README.md (relative to your eval dir) for details.
"""

import argparse
import asyncio
import datetime as dt
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path


def load_rubric(rubric_path: Path):
    """Dynamically import a rubric module; return (JUDGE_SYSTEM, MAX_POINTS)."""
    spec = importlib.util.spec_from_file_location("rubric", rubric_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    if not hasattr(mod, "JUDGE_SYSTEM") or not hasattr(mod, "MAX_POINTS"):
        raise RuntimeError(
            f"{rubric_path} must define JUDGE_SYSTEM (str) and MAX_POINTS (dict[str,int])"
        )
    if not isinstance(mod.MAX_POINTS, dict) or not all(
        isinstance(v, int) and v > 0 for v in mod.MAX_POINTS.values()
    ):
        raise RuntimeError("MAX_POINTS must be dict[str, positive int]")
    return mod.JUDGE_SYSTEM, dict(mod.MAX_POINTS)


def parse_args():
    p = argparse.ArgumentParser(description="Generic Claude Code agent eval harness")
    p.add_argument("--agent-name", required=True,
                   help="The --agent value to pass to claude CLI (e.g. plan-reviewer)")
    p.add_argument("--rubric", type=Path, required=True,
                   help="Python file defining JUDGE_SYSTEM and MAX_POINTS")
    p.add_argument("--fixtures-dir", type=Path, required=True,
                   help="Directory containing *.md + *.expected.json pairs (flat) "
                        "OR a directory-per-fixture layout")
    p.add_argument("--eval-dir", type=Path, required=True,
                   help="Where to write results-*.json and changelog.md")
    p.add_argument("--repo-root", type=Path,
                   help="Repo root (defaults to `git rev-parse --show-toplevel`)")
    p.add_argument("--reviewer-user-prompt-template",
                   default="Review the content at {fixture_path}. Run ID: {run_id}",
                   help="Jinja-like template with {fixture_path} and {run_id} for the reviewer user prompt")
    p.add_argument("--judge-agent-name", default="eval-judge",
                   help="Name under which the inline judge agent is registered")
    p.add_argument("--judge-description", default="Scores agent outputs on the supplied rubric")
    p.add_argument("--model", default="claude-opus-4-7",
                   help="Default model for reviewer and judge (override per-role below)")
    p.add_argument("--reviewer-model", default=None,
                   help="Override --model for the reviewer invocation")
    p.add_argument("--judge-model", default=None,
                   help="Override --model for the judge invocation")
    p.add_argument("--effort", default="high")
    p.add_argument("--agents-template", type=Path, default=None,
                   help="Path to a JSON template for the --agents flag. Tokens like "
                        "{{canned_xxx}} are substituted from each fixture's mock-xxx.txt. "
                        "Only used with directory-per-fixture layouts.")
    p.add_argument("--fake-gh-shim", type=Path, default=None,
                   help="Path to a shim script that replaces `gh` on PATH during each run. "
                        "Defaults to <kit-dir>/fake-gh if unset and a fixture supplies mock-env/.")
    p.add_argument("--runs-per-fixture", type=int, default=6)
    p.add_argument("--concurrency", type=int, default=4)
    p.add_argument("--note", type=str, default="baseline")
    p.add_argument("--smoke", action="store_true",
                   help="One fixture × one run, useful for harness validation")
    p.add_argument("--max-budget-usd", type=float, default=5.0,
                   help="Per-CLI-invocation budget cap")
    p.add_argument("--reviewer-timeout-s", type=float, default=900.0)
    p.add_argument("--judge-timeout-s", type=float, default=400.0)
    return p.parse_args()


# Substrings in CLI output that indicate a quota/rate-limit stop.
# If ANY appears in reviewer or judge text, abort the whole run — further
# calls will only burn quota with no signal.
RATE_LIMIT_MARKERS = (
    "You've hit your limit",
    "You have hit your limit",
    "You've reached your",
    "resets at",
)


class RateLimitedError(RuntimeError):
    pass


def git_toplevel(cwd: Path) -> Path:
    out = subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"], cwd=cwd, text=True,
    ).strip()
    return Path(out)


def load_fixtures(fixtures_dir: Path, repo_root: Path):
    """Load fixtures. Supports two layouts:

    1. **Flat** (plan-reviewer compat): `<fixtures_dir>/<name>.md` +
       `<fixtures_dir>/<name>.expected.json` sibling files.
    2. **Directory-per-fixture**: each subdirectory of `fixtures_dir` is one
       fixture, containing `issue-body.md`, `expected.json`, optional
       `mock-*.txt` files (for --agents-template substitution keyed as
       `canned_<stem-with-hyphens-as-underscores>`), and optional `mock-env/`
       directory (contents copied into the per-run PATH-override tmpdir).

    Raises if `fixtures_dir` contains neither layout. If both layouts are
    present, prefers directory-per-fixture and warns on stderr about the
    ambiguity.
    """
    if not fixtures_dir.exists():
        raise RuntimeError(f"Fixtures dir does not exist: {fixtures_dir}")
    md_files = [p for p in fixtures_dir.glob("*.md") if p.is_file()]
    subdirs = [
        d for d in fixtures_dir.iterdir()
        if d.is_dir() and (d / "expected.json").exists()
    ]
    if subdirs and md_files:
        print(f"WARN: {fixtures_dir} has both flat and directory fixtures; "
              f"using directory layout only.", file=sys.stderr)
    if subdirs:
        return _load_directory_fixtures(subdirs, repo_root)
    if md_files:
        return _load_flat_fixtures(fixtures_dir, md_files, repo_root)
    raise RuntimeError(
        f"No fixtures found in {fixtures_dir}: expected either *.md + "
        f"*.expected.json pairs OR subdirectories containing expected.json"
    )


def _load_flat_fixtures(fixtures_dir: Path, md_files: list[Path], repo_root: Path):
    fixtures = []
    for md in sorted(md_files):
        expected_path = md.with_suffix(".expected.json")
        if not expected_path.exists():
            raise RuntimeError(f"Missing {expected_path}")
        md_content = md.read_text()
        expected = json.loads(expected_path.read_text())
        try:
            rel = str(md.relative_to(repo_root))
        except ValueError:
            rel = str(md)
        fixtures.append({
            "name": md.stem,
            "path": rel,
            "content": md_content,
            "expected": expected,
            "mocks": {},
            "mock_env_dir": None,
        })
    return fixtures


def _mock_key_for_file(stem: str) -> str:
    """Turn `mock-spec-review` into `canned_spec_review`."""
    base = stem
    if base.startswith("mock-"):
        base = base[len("mock-"):]
    return "canned_" + base.replace("-", "_")


def _load_directory_fixtures(subdirs: list[Path], repo_root: Path):
    fixtures = []
    for d in sorted(subdirs):
        body_path = d / "issue-body.md"
        expected_path = d / "expected.json"
        if not body_path.exists():
            raise RuntimeError(f"Missing {body_path}")
        body = body_path.read_text()
        expected = json.loads(expected_path.read_text())
        mocks = {}
        for mock in sorted(d.glob("mock-*.txt")):
            mocks[_mock_key_for_file(mock.stem)] = mock.read_text()
        mock_env = d / "mock-env"
        mock_env_dir = mock_env if mock_env.is_dir() else None
        try:
            rel = str(body_path.relative_to(repo_root))
        except ValueError:
            rel = str(body_path)
        fixtures.append({
            "name": d.name,
            "path": rel,
            "content": body,
            "expected": expected,
            "mocks": mocks,
            "mock_env_dir": mock_env_dir,
        })
    return fixtures


def build_agents_json(template_path: Path, mocks: dict[str, str]) -> str:
    """Load `template_path`, substitute {{canned_xxx}} tokens from `mocks`,
    return the resulting JSON string. Values are inserted as JSON-escaped
    strings so no matter what's in the mock text, the result is valid JSON."""
    text = template_path.read_text()
    for key, val in mocks.items():
        # Escape the value for embedding inside a JSON string literal.
        # json.dumps wraps in double quotes — strip them so we can paste
        # the escaped body into an existing `"..."` slot in the template.
        escaped = json.dumps(val)[1:-1]
        text = text.replace("{{" + key + "}}", escaped)
    # Validate resulting JSON parses.
    try:
        json.loads(text)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Agents template rendered to invalid JSON: {e}\n{text[:500]}")
    return text


def setup_mock_env(mock_env_dir: Path, fake_gh_shim: Path) -> tuple[str, str]:
    """Create a per-run tmpdir with the mock-env contents + fake-gh shim copied
    in. Returns (tmpdir_path, writes_log_path). Caller is responsible for
    removing the tmpdir afterwards."""
    tmpdir = tempfile.mkdtemp(prefix="eval-mock-")
    # Copy everything from the fixture's mock-env/ in
    for f in mock_env_dir.iterdir():
        if f.is_file():
            shutil.copy(f, Path(tmpdir) / f.name)
    # Copy the shim into tmpdir as `gh` so it shadows the real gh on PATH
    shim_dst = Path(tmpdir) / "gh"
    shutil.copy(fake_gh_shim, shim_dst)
    shim_dst.chmod(0o755)
    # Writes log starts empty
    writes_log = Path(tmpdir) / "writes.log"
    writes_log.write_text("")
    return tmpdir, str(writes_log)


async def run_claude(args, timeout_s: float, cwd: Path, env_override: dict | None = None):
    """Invoke `claude` CLI with a HARD wall-clock kill at timeout_s."""
    env = None
    if env_override:
        env = {**os.environ, **env_override}
    proc = await asyncio.create_subprocess_exec(
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        cwd=cwd,
        env=env,
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


def check_rate_limit(text: str, where: str):
    for marker in RATE_LIMIT_MARKERS:
        if marker in text:
            raise RateLimitedError(
                f"Rate limit detected in {where}: {marker!r}. "
                f"Aborting — re-run after quota reset."
            )


def format_reviewer_prompt(template: str, fixture: dict, run_id: str) -> str:
    """Substitute run_id + fixture_path + issue metadata (from mock-env/
    issue-view.json if present) into `template`. Missing placeholders
    default to empty string so templates can ask for optional fields."""
    from collections import defaultdict

    mock_env = fixture.get("mock_env_dir")
    issue_data: dict = {}
    if mock_env:
        iv = mock_env / "issue-view.json"
        if iv.exists():
            try:
                issue_data = json.loads(iv.read_text())
            except json.JSONDecodeError:
                issue_data = {}

    comments_list = issue_data.get("comments", []) or []
    if comments_list:
        comments_text = "\n---\n".join(c.get("body", "") for c in comments_list)
    else:
        comments_text = "(no prior comments)"

    labels = issue_data.get("labels", []) or []
    labels_text = ", ".join(l.get("name", "") for l in labels) if labels else "(none)"

    fields = {
        "run_id": run_id,
        "fixture_path": fixture.get("path", ""),
        "fixture_content": fixture.get("content", ""),
        "issue_number": str(issue_data.get("number", 0)),
        "issue_title": issue_data.get("title", ""),
        "issue_labels": labels_text,
        "issue_body": issue_data.get("body", fixture.get("content", "")),
        "issue_comments": comments_text,
        "issue_state": issue_data.get("state", "OPEN"),
    }
    return template.format_map(defaultdict(str, fields))


async def invoke_reviewer(cfg, fixture, run_id, sem):
    agent_name = cfg["agent_name"]
    prompt = format_reviewer_prompt(cfg["reviewer_template"], fixture, run_id)
    extra_args = []
    # If an --agents template is configured AND this fixture has mocks, build
    # the per-run --agents JSON by substituting the fixture's mock text.
    if cfg["agents_template"] is not None and fixture.get("mocks"):
        agents_json = build_agents_json(cfg["agents_template"], fixture["mocks"])
        extra_args += ["--agents", agents_json]

    args = [
        "claude", "-p",
        "--agent", agent_name,
        "--model", cfg["reviewer_model"],
        "--effort", cfg["effort"],
        "--permission-mode", "bypassPermissions",
        "--disable-slash-commands",
        "--output-format", "json",
        "--no-session-persistence",
        "--max-budget-usd", str(cfg["budget"]),
        *extra_args,
        prompt,
    ]
    async with sem:
        t0 = dt.datetime.now()
        rc, stdout, stderr = await run_claude(
            args, timeout_s=cfg["reviewer_timeout_s"], cwd=cfg["cwd"],
        )
        elapsed = (dt.datetime.now() - t0).total_seconds()
    text, envelope = extract_result_text(stdout)
    check_rate_limit(text, f"reviewer run {run_id}")

    return {
        "run_id": run_id,
        "returncode": rc,
        "elapsed_s": elapsed,
        "output_text": text,
        "cost_usd": envelope.get("total_cost_usd"),
        "tokens_in": envelope.get("input_tokens"),
        "tokens_out": envelope.get("output_tokens"),
        "stderr": stderr.decode(errors="replace")[-2000:] if rc != 0 else "",
        "timed_out": rc == -9 or rc < 0,
    }


async def invoke_judge_once(cfg, fixture, reviewer_text, sem, retry_note=""):
    judge_agents = {
        cfg["judge_name"]: {
            "description": cfg["judge_desc"],
            "prompt": cfg["judge_system"],
        }
    }
    user_prompt = (
        f"{retry_note}"
        f"<fixture_path>\n{fixture['path']}\n</fixture_path>\n\n"
        f"<fixture_content>\n{fixture['content']}\n</fixture_content>\n\n"
        f"<expected>\n{json.dumps(fixture['expected'], indent=2)}\n</expected>\n\n"
        f"<reviewer_output>\n{reviewer_text}\n</reviewer_output>\n\n"
        "Return ONLY the JSON object described in the rubric."
    )
    args = [
        "claude", "-p",
        "--agents", json.dumps(judge_agents),
        "--agent", cfg["judge_name"],
        "--model", cfg["judge_model"],
        "--effort", cfg["effort"],
        "--tools", "",
        "--permission-mode", "bypassPermissions",
        "--disable-slash-commands",
        "--output-format", "json",
        "--no-session-persistence",
        "--max-budget-usd", str(cfg["budget"]),
        user_prompt,
    ]
    async with sem:
        t0 = dt.datetime.now()
        rc, stdout, stderr = await run_claude(
            args, timeout_s=cfg["judge_timeout_s"], cwd=cfg["cwd"],
        )
        elapsed = (dt.datetime.now() - t0).total_seconds()
    text, envelope = extract_result_text(stdout)
    check_rate_limit(text, "judge call")
    return {
        "returncode": rc,
        "elapsed_s": elapsed,
        "raw_text": text,
        "cost_usd": envelope.get("total_cost_usd"),
        "stderr": stderr.decode(errors="replace")[-2000:] if rc != 0 else "",
    }


async def invoke_judge(cfg, fixture, reviewer_text, sem):
    result = await invoke_judge_once(cfg, fixture, reviewer_text, sem)
    parsed = parse_judge_json(result["raw_text"])
    if parsed is None or not valid_judge_shape(parsed, cfg["max_points"]):
        retry = await invoke_judge_once(
            cfg, fixture, reviewer_text, sem,
            retry_note="PREVIOUS RESPONSE WAS NOT VALID JSON. "
                       "RETURN ONLY THE JSON OBJECT, NO PROSE, NO MARKDOWN FENCES.\n\n",
        )
        parsed = parse_judge_json(retry["raw_text"])
        result["retry"] = retry
    result["parsed"] = parsed
    return result


def valid_judge_shape(d, max_points):
    if not isinstance(d, dict):
        return False
    required = set(max_points.keys())
    return required.issubset(d.keys())


def parse_judge_json(text):
    if not text:
        return None
    c = text.strip()
    c = re.sub(r"^```(?:json)?\s*", "", c)
    c = re.sub(r"\s*```$", "", c)
    try:
        return json.loads(c)
    except json.JSONDecodeError:
        pass
    match = re.search(r"\{[\s\S]*\}", c)
    if not match:
        return None
    try:
        return json.loads(match.group(0))
    except json.JSONDecodeError:
        return None


def score_run(judge, max_points, max_total):
    """Return (points, max_total, per_dim)."""
    parsed = judge.get("parsed") if judge else None
    per = {k: None for k in max_points}
    if not parsed:
        return 0, max_total, per
    pts = 0
    for k, mx in max_points.items():
        v = parsed.get(k)
        if not isinstance(v, int):
            per[k] = None
            continue
        v = max(0, min(mx, v))
        per[k] = v
        pts += v
    return pts, max_total, per


async def run_fixture(cfg, fixture, runs, rev_sem, judge_sem):
    max_points = cfg["max_points"]
    max_total = cfg["max_total"]

    async def one(i):
        run_id = f"{fixture['name']}-{i}-{uuid.uuid4().hex[:8]}"
        print(f"  [{fixture['name']}] start {i+1}/{runs} ({run_id})", flush=True)
        reviewer = await invoke_reviewer(cfg, fixture, run_id, rev_sem)
        print(f"  [{fixture['name']}] reviewer done {i+1}/{runs} "
              f"({reviewer['elapsed_s']:.1f}s, rc={reviewer['returncode']}, "
              f"${reviewer.get('cost_usd') or 0:.3f})", flush=True)
        if reviewer["returncode"] != 0 or not reviewer["output_text"]:
            return {
                "run_id": run_id, "index": i,
                "reviewer": reviewer,
                "judge": {"parsed": None, "error": "reviewer failed"},
                "points": 0, "max": max_total,
                "per_dim": {k: None for k in max_points},
            }
        judge = await invoke_judge(cfg, fixture, reviewer["output_text"], judge_sem)
        pts, mx, per = score_run(judge, max_points, max_total)
        print(f"  [{fixture['name']}] judge done {i+1}/{runs} -> {pts}/{mx} "
              f"{ {k: per[k] for k in per if per[k] is not None} }", flush=True)
        return {
            "run_id": run_id, "index": i,
            "reviewer": reviewer, "judge": judge,
            "points": pts, "max": mx, "per_dim": per,
        }
    return await asyncio.gather(*(one(i) for i in range(runs)))


def compute_summary(runs, max_points):
    total_pts = sum(r["points"] for r in runs)
    total_max = sum(r["max"] for r in runs)
    overall_pct = (total_pts / total_max * 100) if total_max else 0.0
    per_dim = {}
    for k, mx in max_points.items():
        scored = [r["per_dim"][k] for r in runs if r["per_dim"][k] is not None]
        if not scored:
            per_dim[k] = {"pct": None, "avg": None, "max": mx, "n": 0}
            continue
        total = sum(scored)
        avg = total / len(scored)
        per_dim[k] = {
            "pct": (avg / mx * 100) if mx else None,
            "avg": avg, "max": mx, "n": len(scored),
        }
    return overall_pct, per_dim


async def main():
    args = parse_args()

    judge_system, max_points = load_rubric(args.rubric)
    max_total = sum(max_points.values())

    repo_root = args.repo_root or git_toplevel(Path.cwd())
    eval_dir = args.eval_dir.resolve()
    eval_dir.mkdir(parents=True, exist_ok=True)
    changelog = eval_dir / "changelog.md"

    fixtures = load_fixtures(args.fixtures_dir, repo_root)
    if args.smoke:
        fixtures = fixtures[:1]
        args.runs_per_fixture = 1
    print(f"Loaded {len(fixtures)} fixtures, {args.runs_per_fixture} runs each "
          f"(rubric max={max_total})", flush=True)

    try:
        agent_sha = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=repo_root, text=True,
        ).strip()[:7]
    except Exception:
        agent_sha = "unknown"

    reviewer_model = args.reviewer_model or args.model
    judge_model = args.judge_model or args.model

    # Resolve fake-gh shim path. If not set and any fixture uses mock_env_dir,
    # default to sibling `fake-gh` next to this script.
    fake_gh_shim = args.fake_gh_shim
    if fake_gh_shim is None and any(f.get("mock_env_dir") for f in fixtures):
        fake_gh_shim = Path(__file__).resolve().parent / "fake-gh"
        if not fake_gh_shim.exists():
            raise RuntimeError(
                f"Fixtures use mock-env/ but no --fake-gh-shim provided and "
                f"default shim {fake_gh_shim} does not exist"
            )
    if fake_gh_shim and not fake_gh_shim.exists():
        raise RuntimeError(f"--fake-gh-shim path does not exist: {fake_gh_shim}")

    cfg = {
        "agent_name": args.agent_name,
        "reviewer_template": args.reviewer_user_prompt_template,
        "judge_system": judge_system,
        "judge_name": args.judge_agent_name,
        "judge_desc": args.judge_description,
        "reviewer_model": reviewer_model,
        "judge_model": judge_model,
        "effort": args.effort,
        "agents_template": args.agents_template,
        "fake_gh_shim": fake_gh_shim,
        "budget": args.max_budget_usd,
        "reviewer_timeout_s": args.reviewer_timeout_s,
        "judge_timeout_s": args.judge_timeout_s,
        "max_points": max_points,
        "max_total": max_total,
        "cwd": repo_root,
    }

    rev_sem = asyncio.Semaphore(args.concurrency)
    judge_sem = asyncio.Semaphore(args.concurrency)

    started_at = dt.datetime.now(dt.timezone.utc)

    all_runs = []
    per_fixture = {}
    try:
        for fixture in fixtures:
            print(f"\n=== Fixture: {fixture['name']} ===", flush=True)
            runs = await run_fixture(cfg, fixture, args.runs_per_fixture, rev_sem, judge_sem)
            per_fixture[fixture["name"]] = {"runs": runs, "expected": fixture["expected"]}
            for r in runs:
                r["_fixture"] = fixture["name"]
            all_runs.extend(runs)
    except RateLimitedError as e:
        print(f"\n!!! ABORTING: {e}", flush=True)

    finished_at = dt.datetime.now(dt.timezone.utc)
    if not all_runs:
        print("No runs completed — nothing to summarize.", flush=True)
        sys.exit(1)

    overall_pct, per_dim = compute_summary(all_runs, max_points)

    per_fixture_summary = {}
    for name, data in per_fixture.items():
        f_pct, f_dim = compute_summary(data["runs"], max_points)
        per_fixture_summary[name] = {
            "pct": f_pct, "per_dim": f_dim,
            "expected_verdict": data["expected"].get("expected_verdict"),
        }

    ts = started_at.strftime("%Y%m%dT%H%M%SZ")
    out_path = eval_dir / f"results-{ts}.json"
    doc = {
        "started_at": started_at.isoformat(),
        "finished_at": finished_at.isoformat(),
        "agent_name": args.agent_name,
        "agent_sha": agent_sha,
        "note": args.note,
        "reviewer_model": reviewer_model,
        "judge_model": judge_model,
        "effort": args.effort,
        "runs_per_fixture": args.runs_per_fixture,
        "num_fixtures": len(fixtures),
        "rubric_max": max_total,
        "max_points": max_points,
        "overall_pct": overall_pct,
        "per_dim": per_dim,
        "per_fixture": per_fixture_summary,
        "detail": per_fixture,
    }
    out_path.write_text(json.dumps(doc, indent=2, default=str))
    print(f"\nWrote {out_path}", flush=True)

    total_cost = sum(
        (r["reviewer"].get("cost_usd") or 0) +
        (r["judge"].get("cost_usd") or 0 if isinstance(r["judge"], dict) else 0)
        for r in all_runs
    )

    dim_fmt = " ".join(
        f"{k.split('_')[0]}={_pct(per_dim[k]['pct'])}" for k in max_points
    )
    line = (
        f"{started_at.isoformat()} | agent={args.agent_name} | sha={agent_sha} | "
        f"model={reviewer_model} | "
        f"score={overall_pct:.1f}% | {dim_fmt} | "
        f"runs={len(all_runs)} | cost=${total_cost:.2f} | note=\"{args.note}\"\n"
    )
    with changelog.open("a") as f:
        f.write(line)
    print(line.strip(), flush=True)

    print("\n=== SUMMARY ===")
    print(f"Overall: {overall_pct:.1f}% ({sum(r['points'] for r in all_runs)}/{sum(r['max'] for r in all_runs)})")
    for k, stats in per_dim.items():
        pct = _pct(stats["pct"])
        print(f"  {k:30s} {pct}  (avg={stats['avg']:.2f}/{stats['max']}, n={stats['n']})")
    print("\nPer-fixture:")
    for name, s in per_fixture_summary.items():
        print(f"  {name:45s} {s['pct']:.1f}%  (expected: {s['expected_verdict']})")
    print(f"\nTotal cost: ${total_cost:.2f}")


def _pct(v):
    return "N/A" if v is None else f"{v:.0f}%"


if __name__ == "__main__":
    asyncio.run(main())
