#!/usr/bin/env python3
"""Score code reviewers on the Martian Code Review Bench offline set.

One arm = one reviewer configuration (arms/<name>.md). For every PR of the chosen set the arm
reviews a blind, offline checkout and writes the comments it would post; a judge on the other
model family matches each comment against the PR's known bugs with the benchmark's own rule; the
run is scored as precision/recall/F1 and appended to changelog.md.

Before any arm is reported the judge is calibrated: it re-scores one published tool's comments
(data/calibration/) and must agree with that tool's published verdicts on >= 90% of the known
bugs. Below that the run stops, so a judge drift never reads as a reviewer change.
"""
from __future__ import annotations

import argparse
import asyncio
import csv
import datetime as dt
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
KIT = HERE.parent / "agent-eval-kit" / "run-eval.py"
GOLDEN_FILES = ("cal_dot_com.json", "discourse.json", "grafana.json", "keycloak.json", "sentry.json")
FAMILY_RE = re.compile(r"claude-([a-z]+)-")
SEVERE = ("High", "Critical")
BLIND_RE = re.compile(
    r'"name":\s*"(WebFetch|WebSearch)"|\bgh (api|pr|issue|repo)\b|git fetch|git pull|\bcurl |\bwget '
)


def load_kit():
    spec = importlib.util.spec_from_file_location("agent_eval_kit", KIT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


kit = load_kit()


# --- data ------------------------------------------------------------------------------------

def load_prs(data: Path, which: str) -> list[dict]:
    with (data / "prs.tsv").open() as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    if which != "all":
        rows = [r for r in rows if r["set"] == which]
    golden = {}
    for name in GOLDEN_FILES:
        for entry in json.loads((data / "golden" / name).read_text()):
            golden[entry["url"]] = entry["comments"]
    for r in rows:
        r["golden"] = golden[r["original_url"]]
    return rows


def parse_arm(path: Path) -> dict:
    text = path.read_text()
    meta, _, body = text.partition("\n---\n")
    arm = {"name": path.stem, "prompt": body.strip() + "\n"}
    for line in meta.splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            arm[k.strip()] = v.strip()
    arm.setdefault("spawn", "claude")
    return arm


def parse_findings(text: str) -> list[str]:
    items = []
    for m in re.finditer(r"^\s*\d+\.\s+(.*?)(?=^\s*\d+\.\s|\Z)", text, re.S | re.M):
        body = " ".join(m.group(1).split())
        if body:
            items.append(body)
    return items


# --- checkouts -------------------------------------------------------------------------------

def sh(args, cwd=None, check=True) -> str:
    return subprocess.run(args, cwd=cwd, check=check, text=True, capture_output=True).stdout.strip()


def ensure_checkout(pr: dict, cache: Path) -> Path:
    clone = cache / "clones" / pr["id"]
    wt = cache / "wt" / pr["id"]
    if not clone.exists():
        clone.parent.mkdir(parents=True, exist_ok=True)
        sh(["git", "clone", "-q", "--filter=blob:none", "--no-checkout", pr["clone_url"], str(clone)])
    for sha in (pr["base"], pr["head"]):
        if subprocess.run(["git", "cat-file", "-e", f"{sha}^{{commit}}"], cwd=clone).returncode != 0:
            sh(["git", "fetch", "-q", "origin", sha], cwd=clone)
    if not wt.exists():
        wt.parent.mkdir(parents=True, exist_ok=True)
        sh(["git", "worktree", "add", "-q", "--detach", str(wt), pr["head"]], cwd=clone)
    # the fork's default branch may have moved after the PR opened, so the recorded base is not
    # always the merge-base; the PR's diff is the merge-base diff, and that is what is reviewed
    mb = sh(["git", "merge-base", pr["base"], pr["head"]], cwd=clone, check=False)
    if not mb:
        raise RuntimeError(f"{pr['id']}: base and head share no history")
    if mb != pr["base"]:
        print(f"[bench] {pr['id']}: recorded base is not the merge-base; reviewing {mb[:10]}..{pr['head'][:10]}", flush=True)
        pr["base_recorded"], pr["base"] = pr["base"], mb
    # a run the limit killed mid-review leaves the CLI's own `.claude/` behind; that is not dirt
    dirt = [l for l in sh(["git", "status", "--porcelain", "--ignored=no"], cwd=wt).splitlines() if l.strip() != "?? .claude/"]
    if dirt:
        raise RuntimeError(f"{pr['id']}: checkout is dirty ({dirt[:3]}); remove {wt} and rerun")
    return wt


# --- reviewer spawn --------------------------------------------------------------------------

def resolved_model(envelope: dict, requested: str) -> str:
    usage = envelope.get("modelUsage") or {}
    if requested in usage:
        return requested
    hits = [m for m in usage if requested.lower() in m.lower()]
    if len(hits) == 1:
        return hits[0]
    if FAMILY_RE.search(requested):
        return requested
    return max(usage, key=lambda m: usage[m].get("inputTokens", 0)) if usage else requested


def family(model_id: str) -> str:
    m = FAMILY_RE.search(model_id)
    return m.group(1) if m else model_id


def find_transcripts(session_id: str) -> list[Path]:
    out = []
    for root in Path.home().glob(".claude*/projects"):
        out += list(root.glob(f"*/{session_id}.jsonl"))
        out += list(root.glob(f"*/{session_id}/subagents/*.jsonl"))
    return out


WRITE_TOOLS = ("Write", "Edit", "MultiEdit", "NotebookEdit")


def blindness_violations(session_id: str, data_dir: Path, scratch: Path | None = None) -> list[str]:
    """Scan the session's transcript (and its subagents') for a read of the answer key or a
    network reach. Only a tool's OPERATIVE field is read — a shell command, a path — never the
    content a Write carries: review-lead stages a script whose text names `gh issue view`, and a
    scan of that text would void every one of its runs."""
    hits = []
    for t in find_transcripts(session_id):
        for line in t.open(errors="replace"):
            if '"type":"tool_use"' not in line and '"type": "tool_use"' not in line:
                continue
            try:
                o = json.loads(line)
            except json.JSONDecodeError:
                continue
            for c in (o.get("message") or {}).get("content") or []:
                if c.get("type") != "tool_use":
                    continue
                name, inp = c.get("name"), c.get("input") or {}
                what = None
                if name in ("WebFetch", "WebSearch"):
                    what = f"{name} {json.dumps(inp)[:120]}"
                elif name == "Bash":
                    cmd = str(inp.get("command", ""))
                    if BLIND_RE.search(cmd) or str(data_dir) in cmd:
                        what = f"Bash {cmd[:160]}"
                elif name in WRITE_TOOLS:
                    fp = str(inp.get("file_path", ""))
                    if str(data_dir) in fp or (scratch and not fp.startswith(str(scratch)) and not fp.startswith("/tmp")):
                        what = f"{name} {fp}"
                elif name in ("Read", "Grep", "Glob"):
                    where = " ".join(str(inp.get(k, "")) for k in ("file_path", "path", "pattern"))
                    if str(data_dir) in where:
                        what = f"{name} {where[:160]}"
                if what:
                    hits.append(f"{t.name}: {what}")
    return hits


async def review_once(cfg, arm, pr, run_no, sem) -> dict:
    async with sem:
        wt = cfg["checkouts"][pr["id"]]
        scratch = Path(cfg["scratch"]) / arm["name"] / f"{pr['id']}-{run_no}"
        scratch.mkdir(parents=True, exist_ok=True)
        out = scratch / "findings.md"
        rules = cfg["rules"].format(checkout=wt, base=pr["base"], head=pr["head"], scratch=scratch, out=out)
        prompt = arm["prompt"].format(rules=rules, checkout=wt, base=pr["base"], head=pr["head"], scratch=scratch, out=out)
        sid = str(uuid.uuid4())
        allow = arm.get("allow", "Read,Grep,Glob,Write,Bash(git *)")
        args = [
            "claude", "-p", "--session-id", sid, "-n", f"bench-{arm['name']}-{pr['id']}",
            "--model", cfg["reviewer_model"],
            "--permission-mode", "acceptEdits", "--permission-prompts", "none",
            "--disallowedTools", "AskUserQuestion,EnterWorktree,ExitWorktree,WebFetch,WebSearch",
            "--setting-sources", "user,project,local",
            "--add-dir", str(scratch),
            "--allowedTools", allow, "--max-turns", str(cfg["max_turns"]),
            "--output-format", "json",
        ]
        if arm.get("plugin-dir"):
            # the arm measures this checkout's plugin, not the installed copy: --plugin-dir wins for a
            # namespaced skill of the same name (probed 2026-10-21)
            args += ["--plugin-dir", str((HERE / arm["plugin-dir"]).resolve())]
        env = {}
        if arm.get("bgwait"):
            args += ["--settings", json.dumps({"env": {"CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS": str(cfg["reviewer_timeout_s"] * 1000)}})]
            env["CLAUDE_CODE_DISABLE_BACKGROUND_TASKS"] = ""
        started = dt.datetime.now(dt.timezone.utc)
        proc = await asyncio.create_subprocess_exec(
            *args, stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE, cwd=wt, env={**os.environ, **env} if env else None,
        )
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(prompt.encode()), cfg["reviewer_timeout_s"])
        except asyncio.TimeoutError:
            proc.kill()
            return {"pr": pr["id"], "run": run_no, "status": "timeout", "candidates": []}
        wall = (dt.datetime.now(dt.timezone.utc) - started).total_seconds()
        text, envelope = kit.extract_result_text(stdout)
        kit.check_rate_limit(text, f"{arm['name']}/{pr['id']}")
        if "session limit" in text or "usage limit" in text:
            raise kit.RateLimitedError(f"session limit in {arm['name']}/{pr['id']}: {text[:120]!r}")
        status_lines = sh(["git", "status", "--porcelain", "--ignored=no"], cwd=wt).splitlines()
        if status_lines:
            sh(["git", "checkout", "-q", "--", "."], cwd=wt)
            sh(["git", "clean", "-qfd"], cwd=wt)
        # the CLI writes its own project state into its cwd; that is not the reviewer touching the code
        dirt = "\n".join(l for l in status_lines if l.strip() != "?? .claude/")
        viol = blindness_violations(sid, cfg["data"], scratch)
        cands = parse_findings(out.read_text()) if out.exists() else []
        status = "modified-checkout" if dirt else "voided-blindness" if viol else "ok" if out.exists() else "no-output"
        return {
            "pr": pr["id"], "run": run_no, "session": sid, "scratch": str(scratch), "wall_s": round(wall), "status": status,
            "dirt": dirt.splitlines()[:20], "violations": viol, "candidates": cands,
            "num_turns": envelope.get("num_turns"), "cost_usd": envelope.get("total_cost_usd"),
            "resolved_model": resolved_model(envelope, cfg["reviewer_model"]),
            "stderr": stderr.decode(errors="replace")[-400:],
        }


# --- judge -----------------------------------------------------------------------------------

def judge_cache_path(cache: Path, judge_model: str, golden: str, cand: str) -> Path:
    h = hashlib.sha256(f"{judge_model}\0{golden}\0{cand}".encode()).hexdigest()
    return cache / "judge" / h[:2] / f"{h}.json"


async def judge_pair(cfg, golden: str, cand: str, sem) -> dict:
    p = judge_cache_path(cfg["cache"], cfg["judge_model"], golden, cand)
    if p.exists():
        cached = json.loads(p.read_text())
        if not cached.get("error"):
            return cached
    async with sem:
        prompt = cfg["judge_prompt"].replace("{golden_comment}", golden).replace("{candidate}", cand)
        args = ["claude", "-p", "--model", cfg["judge_model"], "--tools", "", "--permission-mode", "bypassPermissions",
                "--disable-slash-commands", "--output-format", "json", "--no-session-persistence", prompt]
        verdict = None
        for _ in range(2):
            rc, stdout, _err = await kit.run_claude(args, cfg["judge_timeout_s"], cwd=HERE)
            text, envelope = kit.extract_result_text(stdout)
            kit.check_rate_limit(text, "judge")
            if "session limit" in text or "usage limit" in text:
                raise kit.RateLimitedError(f"session limit in the judge: {text[:120]!r}")
            m = re.search(r"\{.*\}", text, re.S)
            if m:
                try:
                    j = json.loads(m.group(0))
                    verdict = {"match": bool(j.get("match")), "confidence": float(j.get("confidence") or 0),
                               "reasoning": str(j.get("reasoning", ""))[:300],
                               "judge_resolved": resolved_model(envelope, cfg["judge_model"])}
                    break
                except (ValueError, TypeError):
                    continue
        if verdict is None:
            # never cached: an unparseable answer is the judge failing, not the pair not matching
            return {"match": False, "confidence": 0.0, "reasoning": "judge output unparseable", "error": True}
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(verdict))
        return verdict


async def judge_review(cfg, golden: list[dict], cands: list[str], sem) -> dict:
    gtexts = [g["comment"] for g in golden]
    pairs = [(gi, ci) for gi in range(len(gtexts)) for ci in range(len(cands))]
    results = await asyncio.gather(*(judge_pair(cfg, gtexts[gi], cands[ci], sem) for gi, ci in pairs))
    best = [None] * len(gtexts)
    best_conf = [0.0] * len(gtexts)
    cand_matched = [False] * len(cands)
    for (gi, ci), r in zip(pairs, results):
        if r["match"] and r["confidence"] > best_conf[gi]:
            best_conf[gi] = r["confidence"]
            best[gi] = ci
        if r["match"]:
            cand_matched[ci] = True
    judge_ids = {r.get("judge_resolved") for r in results if r.get("judge_resolved")}
    errors = sum(1 for r in results if r.get("error"))
    if errors:
        raise kit.RateLimitedError(f"{errors} of {len(results)} judge calls returned no verdict; the run is not scorable")
    return {"golden_matched": best, "candidate_matched": cand_matched, "judge_resolved": sorted(judge_ids)}


def score(golden: list[dict], judged: dict) -> dict:
    tp = sum(1 for x in judged["golden_matched"] if x is not None)
    fn = len(golden) - tp
    fp = sum(1 for m in judged["candidate_matched"] if not m)
    hc_tot = sum(1 for g in golden if g.get("severity") in SEVERE)
    hc_tp = sum(1 for g, x in zip(golden, judged["golden_matched"]) if g.get("severity") in SEVERE and x is not None)
    return {"tp": tp, "fp": fp, "fn": fn, "hc_tp": hc_tp, "hc_tot": hc_tot}


def prf(tp, fp, fn):
    p = tp / (tp + fp) if tp + fp else 0.0
    r = tp / (tp + fn) if tp + fn else 0.0
    f = 2 * p * r / (p + r) if p + r else 0.0
    return p, r, f


# --- calibration -----------------------------------------------------------------------------

async def calibrate(cfg, prs: list[dict], sem) -> dict:
    calib = {}
    for f in sorted((cfg["data"] / "calibration").glob("*.json")):
        calib.update(json.loads(f.read_text()))
    agree = total = 0
    disagreements = []
    judge_ids = set()
    for pr in prs:
        c = calib[pr["id"]]
        judged = await judge_review(cfg, [{"comment": g} for g in c["golden"]], c["candidates"], sem)
        judge_ids.update(judged["judge_resolved"])
        for gi, (ours, theirs) in enumerate(zip(judged["golden_matched"], c["golden_matched"])):
            total += 1
            if (ours is not None) == (theirs is not None):
                agree += 1
            else:
                disagreements.append(f"{pr['id']} golden#{gi}: harness={'match' if ours is not None else 'miss'} published={'match' if theirs is not None else 'miss'}")
    rate = agree / total if total else 0.0
    return {"agreement": rate, "agree": agree, "total": total, "disagreements": disagreements, "judge_resolved": sorted(judge_ids)}


# --- main ------------------------------------------------------------------------------------

async def main_async(args):
    data = HERE / "data"
    cache = Path(args.cache_dir).expanduser()
    cache.mkdir(parents=True, exist_ok=True)
    prs = load_prs(data, args.set)
    if args.smoke:
        prs = prs[:1]
        args.runs = 1
    for m, name in ((args.reviewer_model, "REVIEWER_MODEL"), (args.judge_model, "JUDGE_MODEL")):
        if not m or not m.strip():
            sys.exit(f"[bench] {name} is empty")
    cfg = {
        "data": data, "cache": cache, "scratch": cache / "scratch" / dt.datetime.now().strftime("%Y%m%dT%H%M%S"),
        "rules": (HERE / "rules.md").read_text(), "judge_prompt": (data / "judge-prompt.md").read_text(),
        "reviewer_model": args.reviewer_model.strip(), "judge_model": args.judge_model.strip(),
        "reviewer_timeout_s": args.reviewer_timeout_s, "judge_timeout_s": args.judge_timeout_s,
        "max_turns": args.max_turns, "checkouts": {},
    }
    judge_sem = asyncio.Semaphore(args.judge_concurrency)
    started = dt.datetime.now(dt.timezone.utc)
    sha = sh(["git", "rev-parse", "HEAD"], cwd=HERE)[:7]

    print(f"[bench] calibrating the judge on {len(prs)} PRs of the {args.set} set", flush=True)
    cal = await calibrate(cfg, prs, judge_sem)
    print(f"[bench] judge agreement with the published verdicts: {cal['agree']}/{cal['total']} = {cal['agreement']:.0%}", flush=True)
    if cal["agreement"] < args.min_agreement:
        for d in cal["disagreements"]:
            print("  " + d)
        sys.exit(f"[bench] judge agreement below {args.min_agreement:.0%}; no arm is reported")
    judge_fams = {family(j) for j in cal["judge_resolved"]}
    if args.calibration_only or (not args.arm and not args.rescore):
        return

    if args.arm:
        print(f"[bench] building {len(prs)} checkouts under {cache}", flush=True)
        for pr in prs:
            cfg["checkouts"][pr["id"]] = ensure_checkout(pr, cache)

    rev_sem = asyncio.Semaphore(args.concurrency)
    results_doc = {"started_at": started.isoformat(), "set": args.set, "prs": [p["id"] for p in prs],
                   "reviewer_model_requested": cfg["reviewer_model"], "judge_model_requested": cfg["judge_model"],
                   "calibration": cal, "arms": {}}
    if args.rescore:
        prior = json.loads(Path(args.rescore).read_text())
        if prior["set"] != args.set:
            sys.exit(f"[bench] --rescore: the results file is for the {prior['set']} set, not {args.set}")
        for arm_name, prior_arm in prior["arms"].items():
            arm = parse_arm(HERE / "arms" / f"{arm_name}.md")
            runs = []
            for r in prior_arm["runs"]:
                r = {k: v for k, v in r.items() if k not in ("judged", "score")}
                if r.get("session") and r["status"] in ("ok", "voided-blindness"):
                    viol = blindness_violations(r["session"], cfg["data"], Path(r["scratch"]) if r.get("scratch") else None)
                    r["violations"] = viol
                    r["status"] = "voided-blindness" if viol else "ok"
                runs.append(r)
            print(f"\n=== arm {arm_name}: rescored from {Path(args.rescore).name} ===", flush=True)
            # the prior run's source is what was measured, whatever the arm file says now
            results_doc["arms"][arm_name] = await report_arm(cfg, args, arm_name, arm, runs, prs, cal, judge_fams, judge_sem, started, sha,
                                                             src=prior_arm.get("src", "installed"))
    for arm_name in args.arm:
        arm = parse_arm(HERE / "arms" / f"{arm_name}.md")
        if arm.get("spawn") != "claude":
            print(f"[bench] arm {arm_name}: spawn kind {arm.get('spawn')} is not supported by this version; skipped")
            continue
        print(f"\n=== arm {arm_name}: {len(prs)} PRs x {args.runs} runs ===", flush=True)
        runs = await asyncio.gather(*(review_once(cfg, arm, pr, n, rev_sem) for pr in prs for n in range(1, args.runs + 1)))
        results_doc["arms"][arm_name] = await report_arm(cfg, args, arm_name, arm, list(runs), prs, cal, judge_fams, judge_sem, started, sha)

    out = HERE / f"results-{started.strftime('%Y%m%dT%H%M%SZ')}.json"
    out.write_text(json.dumps(results_doc, indent=1, default=str))
    print(f"\n[bench] wrote {out}")


async def report_arm(cfg, args, arm_name, arm, runs, prs, cal, judge_fams, judge_sem, started, sha, src=None):
    src = src or ("checkout" if arm.get("plugin-dir") else "installed")
    resolved = {r.get("resolved_model") for r in runs if r.get("resolved_model")}
    rev_fams = {family(m) for m in resolved}
    if rev_fams & judge_fams and not args.allow_same_family:
        sys.exit(f"[bench] judge family {judge_fams} equals reviewer family {rev_fams}; set JUDGE_MODEL to the other family")
    for r in runs:
        pr = next(p for p in prs if p["id"] == r["pr"])
        if r["status"] == "ok":
            judged = await judge_review(cfg, pr["golden"], r["candidates"], judge_sem)
            r["judged"] = judged
            r["score"] = score(pr["golden"], judged)
    ok = [r for r in runs if r["status"] == "ok"]
    n_runs = max(1, len({r["run"] for r in runs}))
    agg = {k: sum(r["score"][k] for r in ok) / n_runs for k in ("tp", "fp", "fn", "hc_tp", "hc_tot")}
    p, rc, f1 = prf(agg["tp"], agg["fp"], agg["fn"])
    turns = [r["num_turns"] for r in ok if r.get("num_turns") is not None]
    walls = [r["wall_s"] for r in ok if r.get("wall_s") is not None]
    cost = sum(r.get("cost_usd") or 0 for r in runs)
    voided = [r for r in runs if r["status"] != "ok"]
    line = kit.changelog_row(started, [
        f"agent={arm_name}", f"sha={sha}", f"src={src}",
        f"model={'+'.join(sorted(resolved)) or cfg['reviewer_model']}",
        f"judge={'+'.join(cal['judge_resolved']) or cfg['judge_model']}", f"set={args.set}", f"prs={len(prs)}", f"runs={n_runs}",
        f"prec={p:.2f}", f"recall={rc:.2f}", f"f1={f1:.2f}", f"hc={agg['hc_tp']:.0f}/{agg['hc_tot']:.0f}",
        f"tp={agg['tp']:.1f}", f"fp={agg['fp']:.1f}", f"fn={agg['fn']:.1f}", f"calib={cal['agreement']:.0%}",
        f"voided={len(voided)}", f"turns={max(turns) if turns else 0}/{(sum(turns)/len(turns)) if turns else 0:.1f}",
        f"wall={max(walls) if walls else 0}s", f"cost=${cost:.2f}", f"note=\"{args.note}\"",
    ])
    if not args.smoke and not args.no_record:
        kit.append_changelog(HERE / "changelog.md", line)
    print(line.strip(), flush=True)
    for r in voided:
        print(f"  voided: {r['pr']} run {r['run']}: {r['status']} {r.get('violations', [])[:2]}")
    return {"runs": runs, "src": src, "aggregate": agg, "precision": p, "recall": rc, "f1": f1, "row": line.strip()}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--eval-dir", type=Path, default=HERE)
    ap.add_argument("--arm", action="append", default=[], help="arms/<name>.md; repeatable")
    ap.add_argument("--set", choices=("dev", "heldout", "all"), default="dev")
    ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--concurrency", type=int, default=3)
    ap.add_argument("--judge-concurrency", type=int, default=8)
    ap.add_argument("--smoke", action="store_true", help="one PR, one run, nothing recorded")
    ap.add_argument("--calibration-only", action="store_true")
    ap.add_argument("--no-record", action="store_true", help="print the row, do not append it")
    ap.add_argument("--rescore", help="a results-*.json: re-run the blindness scan on its sessions' transcripts and re-judge its stored candidates; no review is spawned")
    ap.add_argument("--note", default="baseline")
    ap.add_argument("--reviewer-model", default=os.environ.get("REVIEWER_MODEL"))
    ap.add_argument("--judge-model", default=os.environ.get("JUDGE_MODEL"))
    ap.add_argument("--allow-same-family", action="store_true")
    ap.add_argument("--min-agreement", type=float, default=0.90)
    ap.add_argument("--max-turns", type=int, default=150)
    ap.add_argument("--reviewer-timeout-s", type=int, default=2400)
    ap.add_argument("--judge-timeout-s", type=int, default=180)
    ap.add_argument("--cache-dir", default=os.path.join(os.environ.get("XDG_CACHE_HOME", "~/.cache"), "second-shift", "code-review-bench"))
    args = ap.parse_args()
    try:
        asyncio.run(main_async(args))
    except kit.RateLimitedError as e:
        sys.exit(f"[bench] {e}")


if __name__ == "__main__":
    main()
