#!/usr/bin/env python3
"""Measure the completeness half of the lane's pass-1 review.

A fixture is a merged change and its ticket. Each variant is one head: the change as merged (the
twin), the change without one criterion's implementation (plant-a), and the change without that
criterion's test (plant-b). An arm is a prompt file. Every review is one `plain-review.sh run`,
which is what the lane and /dev-pipeline:review run. A judge on another model tier reads the
findings; the measures are counts of runs, and a row per arm goes to changelog.md.

Operator-run and model-billed. See README.md beside this file.
"""
from __future__ import annotations

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
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ARMS = {"pass-1": ("pass-1-review.md", ("plant-a", "plant-b", "twin")), "plain": ("plain-review.md", ("plant-a", "twin"))}
FINDINGS_RE = re.compile(r"^## Findings[ \t]*$", re.M)
READ_TOOLS = {"Read": ("file_path",), "Grep": ("path", "glob"), "Glob": ("path", "pattern")}
VOTES = 3
BAR = 0.8


def sh(args, cwd=None, check=True, env=None) -> str:
    return subprocess.run([str(a) for a in args], cwd=cwd, check=check, text=True, capture_output=True, env=env).stdout.strip()


def load(path: Path, name: str):
    if not path.is_file():
        sys.exit(f"[eval] {path} is missing: run this eval from a full checkout of the marketplace repo")
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def physical(p) -> str:
    return os.path.realpath(os.path.expanduser(str(p)))


def under(path: str, root: str) -> bool:
    return path == root or path.startswith(root.rstrip("/") + "/")


# --- findings --------------------------------------------------------------------------------

def findings_of(draft: str) -> list[str]:
    """The items of `## Findings`, each with its continuation lines, in order."""
    m = FINDINGS_RE.search(draft)
    if not m:
        return []
    items: list[str] = []
    for line in draft[m.end():].splitlines():
        if line.startswith("## "):
            break
        if line.startswith("- "):
            items.append(line)
        elif items and line.strip():
            items[-1] += "\n" + line
    return items


def as_int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def numbered(items: list[str]) -> str:
    return "\n".join(f"F{i}. {t}" for i, t in enumerate(items, 1)) or "(no findings)"


def criteria_text(key: dict) -> str:
    return "\n".join(f"{c['n']}. {('[' + c['id'] + '] ') if c.get('id') else ''}{c['text']}" for c in key["criteria"])


# --- fixture ---------------------------------------------------------------------------------

def git_env() -> dict:
    stamp = "2000-01-01T00:00:00Z"
    return {**os.environ, "GIT_AUTHOR_NAME": "eval", "GIT_AUTHOR_EMAIL": "eval@example.invalid", "GIT_COMMITTER_NAME": "eval",
            "GIT_COMMITTER_EMAIL": "eval@example.invalid", "GIT_AUTHOR_DATE": stamp, "GIT_COMMITTER_DATE": stamp}


def build_fixture(fdir: Path, repo_root: Path, cache: Path) -> dict:
    """Clone the fixture's repo into the cache and commit each planted variant there."""
    fx = json.loads((fdir / "fixture.json").read_text())
    fx["dir"] = fdir
    fx["key_doc"] = json.loads((fdir / fx["key"]).read_text())
    src = repo_root if fx["repo"] == "." else Path(os.path.expanduser(fx["repo"]))
    for sha in (fx["base"], fx["head"]):
        if subprocess.run(["git", "-C", str(src), "cat-file", "-e", f"{sha}^{{commit}}"], capture_output=True).returncode != 0:
            sys.exit(f"[eval] {src} does not hold commit {sha}; a shallow clone needs its full history fetched")
    clone = cache / "clone" / fx["label"]
    shutil.rmtree(clone, ignore_errors=True)
    clone.parent.mkdir(parents=True, exist_ok=True)
    sh(["git", "clone", "-q", "--no-checkout", src, clone])
    fx["clone"], fx["source"] = clone, src
    fx["shas"] = {}
    for name, v in fx["variants"].items():
        sh(["git", "checkout", "-q", "--detach", fx["head"]], cwd=clone)
        if v.get("patch"):
            sh(["git", "apply", "--whitespace=nowarn", (fdir / v["patch"]).resolve()], cwd=clone)
            sh(["git", "commit", "-qam", f"variant {name}"], cwd=clone, env=git_env())
        fx["shas"][name] = sh(["git", "rev-parse", "HEAD"], cwd=clone)
        for tok in v.get("leak_tokens", []):
            tree = subprocess.run(["git", "grep", "-lF", "-e", tok, fx["shas"][name], "--", ".", f":(exclude){fx['plans_dir']}"],
                                  cwd=clone, text=True, capture_output=True).stdout.strip()
            if tree:
                sys.exit(f"[eval] {fx['label']}/{name}: the token '{tok}' is still in the planted tree: {tree.splitlines()[:3]}")
    return fx


# --- the subject session ---------------------------------------------------------------------

def deny_paths(cfg, fx) -> list[str]:
    home = Path.home()
    cands = [home / "work", os.environ.get("TMPDIR", ""), "/private/tmp", home / ".cache" / "second-shift", cfg["root"], fx["dir"], fx["source"]]
    cands += sorted(home.glob(".claude")) + sorted(home.glob(".claude-*")) + list(cfg["deny_extra"])
    out: list[str] = []
    for c in cands:
        if not str(c).strip():
            continue
        p = physical(c)
        if p not in out:
            out.append(p)
    return out


def scan_transcript(kit_bench, session_id: str, run_dir: Path) -> dict:
    """Which files the session read. A Read, Grep or Glob that returned content from outside the
    run's tree and scratch is a violation; a refused one and a call to another tool are listed."""
    tree = physical(run_dir / "tree")
    allowed = (tree, physical(run_dir / "scratch"))
    transcripts = kit_bench.find_transcripts(session_id) if session_id else []
    res = {"transcripts": len(transcripts), "violations": [], "refused": [], "other_tools": [], "calls": 0}
    outside: dict[str, str] = {}
    errors: set[str] = set()
    for t in transcripts:
        for line in t.open(errors="replace"):
            try:
                o = json.loads(line)
            except json.JSONDecodeError:
                continue
            content = (o.get("message") or {}).get("content")
            if not isinstance(content, list):
                continue
            for c in content:
                if not isinstance(c, dict):
                    continue
                if c.get("type") == "tool_result" and c.get("is_error"):
                    errors.add(c.get("tool_use_id"))
                if c.get("type") != "tool_use":
                    continue
                name, inp = c.get("name"), c.get("input") or {}
                if name not in READ_TOOLS:
                    res["other_tools"].append(name)
                    continue
                res["calls"] += 1
                base = tree
                for k in READ_TOOLS[name]:
                    v = str(inp.get(k) or "")
                    if not v:
                        continue
                    literal = re.split(r"[*?\[{]", v, 1)[0]
                    p = os.path.realpath(os.path.join(base, literal))
                    if k == "path":
                        base = p
                    if not any(under(p, a) for a in allowed):
                        outside[c.get("id")] = f"{name} {k}={v[:160]}"
    for tid, what in outside.items():
        res["refused" if tid in errors else "violations"].append(what)
    return res


def run_dir_of(cfg, fx, arm: str, variant: str, n: int, tag: str) -> Path:
    return cfg["cache"] / "runs" / f"{fx['label']}-{arm}-{variant}-{n}{tag}"


def reserve(cfg, fx, arm: str, cells, tag: str) -> None:
    """Every run dir of a batch exists before its first session starts, so each session is denied the others'."""
    for variant, n in cells:
        run_dir_of(cfg, fx, arm, variant, n, tag).mkdir(parents=True, exist_ok=True)


async def review_once(cfg, fx, arm: str, variant: str, n: int, sem, tag: str = "") -> dict:
    run_dir = run_dir_of(cfg, fx, arm, variant, n, tag)
    rec = {"arm": arm, "variant": variant, "run": n, "status": "void", "why": "", "draft": ""}
    async with sem:
        if cfg["spent"] >= cfg["max_cost"]:
            rec["why"] = "not started: the cost ceiling was reached"
            rec["status"] = "skipped"
            return rec
        others = [physical(p) for p in (cfg["cache"] / "runs").glob("*") if p != run_dir]
        args = ["bash", str(cfg["tool"]), "run", "--worktree", str(fx["clone"]), "--base", fx["base"], "--head", fx["shas"][variant],
                "--out", str(run_dir), "--plans-dir", fx["plans_dir"], "--ticket", str(fx["dir"] / fx["ticket"]),
                "--model", cfg["reviewer_model"], "--prompt", str(cfg["prompts"] / ARMS[arm][0]), "--timeout", str(cfg["timeout_s"])]
        for d in cfg["deny"] + others:
            args += ["--deny-read", d]
        proc = await asyncio.create_subprocess_exec(*args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        _out, err = await proc.communicate()
        rec["rc"] = proc.returncode
        read = lambda f: (run_dir / f).read_text(errors="replace") if (run_dir / f).is_file() else ""
        text, envelope = cfg["kit"].extract_result_text(read("result.json").encode())
        rec.update(session=envelope.get("session_id"), cost_usd=envelope.get("total_cost_usd") or 0, num_turns=envelope.get("num_turns"),
                   wall_s=int(read("wall").strip() or 0), draft=read("verdict.md"),
                   resolved_model=cfg["bench"].resolved_model(envelope, cfg["reviewer_model"]) if envelope.get("modelUsage") else None)
        cfg["spent"] += rec["cost_usd"]
        if proc.returncode != 0:
            cfg["kit"].check_rate_limit(text + read("session.err"), f"{arm}/{variant}/{n}")
        rec["scan"] = scan_transcript(cfg["bench"], rec["session"], run_dir)
        if proc.returncode != 0:
            rec["why"] = (read("why").strip() or err.decode(errors="replace").strip()[-300:] or f"exit {proc.returncode}")
        elif arm == "pass-1" and not FINDINGS_RE.search(rec["draft"]):
            rec["why"] = "the draft has no findings block"
        elif not rec["scan"]["transcripts"]:
            rec["why"] = "no transcript was found, so the reads cannot be checked"
        elif rec["scan"]["violations"]:
            rec["why"] = "read outside its tree: " + "; ".join(rec["scan"]["violations"][:3])
        else:
            rec["status"] = "ok"
        if not cfg["keep"]:
            shutil.rmtree(run_dir, ignore_errors=True)
    print(f"[eval] {arm}/{variant}/{n}{tag}: {rec['status']} {rec['why']} (${rec['cost_usd']:.2f}, {rec.get('wall_s', 0)}s, {rec.get('num_turns')} turns)", flush=True)
    return rec


# --- the judge -------------------------------------------------------------------------------

async def judge_call(cfg, prompt: str, sem):
    args = [cfg["judge_bin"], "-p", "--model", cfg["judge_model"], "--tools", "", "--permission-mode", "bypassPermissions",
            "--disable-slash-commands", "--output-format", "json", "--no-session-persistence", prompt]
    async with sem:
        for _ in range(2):
            _rc, stdout, _err = await cfg["kit"].run_claude(args, cfg["judge_timeout_s"], cwd=cfg["cache"])
            text, envelope = cfg["kit"].extract_result_text(stdout)
            cfg["kit"].check_rate_limit(text, "judge")
            cfg["judge_cost"] += envelope.get("total_cost_usd") or 0
            if envelope.get("modelUsage"):
                cfg["judge_resolved"].add(cfg["bench"].resolved_model(envelope, cfg["judge_model"]))
            m = re.search(r"[\[{].*[\]}]", text, re.S)
            if m:
                try:
                    return json.loads(m.group(0))
                except ValueError:
                    continue
    raise cfg["kit"].RateLimitedError("a judge call returned no JSON twice; the run is not scorable (re-judge it with --rescore)")


async def judge_planted(cfg, kind: str, criterion: str, items: list[str], sem) -> dict:
    if not items:
        return {"votes": [], "passes": 0, "pass": False, "finding": None}
    tmpl = cfg["judge_planted"]["a" if kind == "unimplemented" else "b"]
    prompt = tmpl.replace("{criterion}", criterion).replace("{findings}", numbered(items))
    votes = await asyncio.gather(*(judge_call(cfg, prompt, sem) for _ in range(VOTES)))
    votes = [v if isinstance(v, dict) else {} for v in votes]
    passes = sum(1 for v in votes if v.get("pass") is True)
    named = Counter(str(v.get("finding")) for v in votes if v.get("pass") is True).most_common(1)
    return {"votes": votes, "passes": passes, "pass": passes * 2 > VOTES, "finding": named[0][0] if named else None}


async def judge_claims(cfg, key: dict, items: list[str], sem) -> dict:
    if not items:
        return {"votes": [], "claims": []}
    prompt = cfg["judge_claims"].replace("{criteria}", criteria_text(key)).replace("{findings}", numbered(items))
    votes = await asyncio.gather(*(judge_call(cfg, prompt, sem) for _ in range(VOTES)))
    votes = [v if isinstance(v, list) else [] for v in votes]
    claims = []
    for i in range(1, len(items) + 1):
        mine = [e for v in votes for e in v if isinstance(e, dict) and str(e.get("finding")) == f"F{i}"]
        kind, n_kind = (Counter(str(e.get("kind")) for e in mine).most_common(1) or [("", 0)])[0]
        if kind not in ("unimplemented", "untested") or n_kind * 2 <= VOTES:
            continue
        crit, n_crit = Counter(as_int(e.get("criterion")) for e in mine if e.get("kind") == kind).most_common(1)[0]
        claims.append({"finding": f"F{i}", "kind": kind, "criterion": crit if n_crit * 2 > VOTES and isinstance(crit, int) else None})
    return {"votes": votes, "claims": claims}


def classify(claim: dict, fx: dict, variant: str) -> str:
    """planted, per-rule, unkeyed or false; see README.md, "Claim classes"."""
    if claim["criterion"] is None:
        return "unkeyed"
    kind = fx["variants"][variant].get("kind")
    if kind and claim["criterion"] == fx["planted_criterion"] and (kind == "unimplemented" or claim["kind"] == "untested"):
        return "planted"
    row = next((c for c in fx["key_doc"]["criteria"] if c["n"] == claim["criterion"]), None)
    if row is None:
        return "unkeyed"
    if claim["kind"] == "untested" and not row.get("test"):
        return "per-rule"
    return "false"


async def judge_run(cfg, fx, rec, sem):
    items = findings_of(rec["draft"])
    rec["findings"] = items
    rec["verdict"] = (rec["draft"].splitlines() or [""])[0].strip()
    kind = fx["variants"][rec["variant"]].get("kind")
    if kind:
        crit = next(c for c in fx["key_doc"]["criteria"] if c["n"] == fx["planted_criterion"])
        rec["planted"] = await judge_planted(cfg, kind, f"{('[' + crit['id'] + '] ') if crit.get('id') else ''}{crit['text']}", items, sem)
        rec["detected"] = rec["verdict"] == "verdict: needs-work" and rec["planted"]["pass"]
    g3 = await judge_claims(cfg, fx["key_doc"], items, sem)
    rec["claim_votes"] = g3["votes"]
    rec["claims"] = [{**c, "class": classify(c, fx, rec["variant"])} for c in g3["claims"]]


# --- measures --------------------------------------------------------------------------------

def frac(runs, pred) -> str:
    return f"{sum(1 for r in runs if pred(r))}/{len(runs)}"


def n_class(r, cls) -> int:
    return sum(1 for c in r["claims"] if c["class"] == cls)


def measures(runs: list[dict]) -> list[str]:
    ok = [r for r in runs if r["status"] == "ok"]
    seg = []
    for variant, name in (("plant-a", "detect-A"), ("plant-b", "detect-B")):
        cell = [r for r in ok if r["variant"] == variant]
        if cell:
            seg.append(f"{name}={frac(cell, lambda r: r['detected'])} ({','.join(str(r['planted']['passes']) for r in cell)})")
    twin = [r for r in ok if r["variant"] == "twin"]
    if twin:
        seg.append(f"clean-twin={frac(twin, lambda r: n_class(r, 'false') == 0)}")
        rest = [r for r in twin if r["verdict"] != "verdict: approve"]
        false_n = sum(1 for r in rest if n_class(r, "false"))
        rule_n = sum(1 for r in rest if not n_class(r, "false") and r["findings"] and n_class(r, "per-rule") == len(r["findings"]))
        seg.append(f"approve-twin={frac(twin, lambda r: r['verdict'] == 'verdict: approve')} (false {false_n}, per-rule {rule_n}, other {len(rest) - false_n - rule_n})")
    if ok:
        mean = lambda cls: sum(n_class(r, cls) for r in ok) / len(ok)
        seg.append(f"false-claims={mean('false'):.1f} (unkeyed {mean('unkeyed'):.1f}, per-rule {mean('per-rule'):.1f})")
    det = [r for r in ok if r.get("detected")]

    def blocker(r) -> bool:
        m = re.fullmatch(r"F(\d+)", r["planted"]["finding"] or "")
        i = int(m.group(1)) if m else 0
        return 0 < i <= len(r["findings"]) and r["findings"][i - 1].startswith("- [blocker]")
    if det:
        seg.append(f"tag={frac(det, blocker)}")
    return seg


def report(cfg, fx, arm: str, runs: list[dict], started, note: str, record: bool) -> str:
    ok = [r for r in runs if r["status"] == "ok"]
    resolved = sorted({r["resolved_model"] for r in runs if r.get("resolved_model")})
    tiers = {cfg["bench"].family(m) for m in resolved} & {cfg["bench"].family(m) for m in cfg["judge_resolved"]}
    if tiers:
        sys.exit(f"[eval] the judge and the subject are both on the {sorted(tiers)} tier; set JUDGE_MODEL to another tier")
    turns = [r["num_turns"] for r in ok if r.get("num_turns") is not None]
    walls = [r["wall_s"] for r in ok if r.get("wall_s")]
    line = cfg["kit"].changelog_row(started, [
        f"arm={arm}", f"fixture={fx['label']}", f"sha={cfg['sha']}", f"prompt={cfg['blobs'][arm]}",
        f"model={'+'.join(resolved) or cfg['reviewer_model']}", f"judge={'+'.join(sorted(cfg['judge_resolved'])) or cfg['judge_model']}",
        f"runs={max((sum(1 for r in ok if r['variant'] == v) for v in ARMS[arm][1]), default=0)}",
        *measures(runs), f"voided={sum(1 for r in runs if r['status'] == 'void')}",
        f"turns={max(turns) if turns else 0}/{(sum(turns) / len(turns)) if turns else 0:.1f}", f"wall={max(walls) if walls else 0}s",
        f"cost=${sum(r.get('cost_usd') or 0 for r in runs):.2f}", f"note=\"{note}\"",
    ])
    if record:
        cfg["kit"].append_changelog(HERE / "changelog.md", line)
    print(line.strip(), flush=True)
    return line.strip()


# --- main ------------------------------------------------------------------------------------

def setup(args) -> dict:
    top = sh(["git", "-C", HERE, "rev-parse", "--show-toplevel"], check=False)
    if not top:
        sys.exit("[eval] this eval runs from a git checkout of the marketplace repo")
    root = Path(top)
    evals = root / "plugins" / "review-toolkit" / "evals"
    kit = load(evals / "agent-eval-kit" / "run-eval.py", "agent_eval_kit")
    bench = load(evals / "code-review-bench-eval" / "bench.py", "bench")
    plugin = HERE.parent.parent
    tool, prompts = plugin / "tools" / "plain-review.sh", plugin / "skills" / "run"
    under_test = [tool] + [prompts / ARMS[a][0] for a in ARMS]
    dirty = sh(["git", "-C", root, "status", "--porcelain", "--", *under_test], check=False)
    if dirty and not args.allow_dirty:
        sys.exit(f"[eval] the files under test have uncommitted changes, so a row would name the wrong commit:\n{dirty}")
    cache = Path(physical(args.cache_dir))
    (cache / "runs").mkdir(parents=True, exist_ok=True)
    cfg = {
        "kit": kit, "bench": bench, "root": root, "tool": tool, "prompts": prompts, "cache": cache,
        "reviewer_model": (args.reviewer_model or "").strip(), "judge_model": (args.judge_model or "").strip(),
        "judge_bin": os.environ.get("JUDGE_CLAUDE", "claude"), "judge_timeout_s": 180, "timeout_s": args.timeout_s,
        "judge_planted": {k: (HERE / f"judge-planted-{k}.md").read_text() for k in ("a", "b")},
        "judge_claims": (HERE / "judge-claims.md").read_text(), "judge_resolved": set(), "judge_cost": 0.0,
        "spent": 0.0, "max_cost": args.max_cost_usd, "keep": args.keep, "deny_extra": args.deny_read,
        "sha": sh(["git", "-C", root, "rev-parse", "--short", "HEAD"]),
        "blobs": {a: sh(["git", "-C", root, "hash-object", prompts / ARMS[a][0]])[:10] for a in ARMS},
    }
    for m, name in ((cfg["reviewer_model"], "REVIEWER_MODEL"), (cfg["judge_model"], "JUDGE_MODEL")):
        if not m:
            sys.exit(f"[eval] {name} is empty")
    return cfg


async def sanity(cfg, fx) -> int:
    """The judges against hand-written findings with known labels, before any real draft is read."""
    sem = asyncio.Semaphore(8)
    crit = next(c for c in fx["key_doc"]["criteria"] if c["n"] == fx["planted_criterion"])
    ctext = f"{('[' + crit['id'] + '] ') if crit.get('id') else ''}{crit['text']}"
    wrong = 0
    for case in json.loads((HERE / "judge-sanity.json").read_text())["cases"]:
        items = case["findings"]
        a = await judge_planted(cfg, "unimplemented", ctext, items, sem)
        b = await judge_planted(cfg, "untested", ctext, items, sem)
        g3 = await judge_claims(cfg, fx["key_doc"], items, sem)
        got = {"a": a["pass"], "b": b["pass"], "claims": sorted((c["finding"], c["kind"], c["criterion"]) for c in g3["claims"])}
        want = {"a": case["planted_a"], "b": case["planted_b"], "claims": sorted(tuple(c) for c in case["claims"])}
        got["claims"] = [list(c) for c in got["claims"]]
        want["claims"] = [list(c) for c in want["claims"]]
        good = got == want
        wrong += 0 if good else 1
        print(f"[sanity] {'ok  ' if good else 'WRONG'} {case['name']}: votes a={a['passes']} b={b['passes']}" + ("" if good else f"\n  want {want}\n  got  {got}\n  claim votes {g3['votes']}"), flush=True)
    print(f"[sanity] {wrong} wrong; judge={'+'.join(sorted(cfg['judge_resolved']))} cost=${cfg['judge_cost']:.2f}", flush=True)
    return 1 if wrong else 0


async def main_async(args) -> int:
    cfg = setup(args)
    fdir = Path(physical(Path(args.fixtures_dir) / args.fixture))
    fx = build_fixture(fdir, cfg["root"], cfg["cache"])
    print(f"[eval] fixture {fx['label']}: " + ", ".join(f"{k}={v[:10]}" for k, v in fx["shas"].items()), flush=True)
    if args.check_fixture:
        return 0
    if args.judge_sanity:
        return await sanity(cfg, fx)
    cfg["deny"] = deny_paths(cfg, fx)
    for d in cfg["deny"]:
        if under(str(cfg["cache"]), d):
            sys.exit(f"[eval] the cache {cfg['cache']} is inside the denied path {d}, so no session could read its tree; pass --cache-dir")
    started = dt.datetime.now(dt.timezone.utc)
    results_dir = Path(physical(args.results_dir))
    results_dir.mkdir(parents=True, exist_ok=True)
    out = results_dir / f"results-{started.strftime('%Y%m%dT%H%M%SZ')}.json"
    doc = {"started_at": started.isoformat(), "fixture": fx["label"], "sha": cfg["sha"], "prompts": cfg["blobs"],
           "reviewer_model_requested": cfg["reviewer_model"], "judge_model_requested": cfg["judge_model"], "deny": cfg["deny"], "arms": {}}
    save = lambda: out.write_text(json.dumps(doc, indent=1, default=str))
    judge_sem = asyncio.Semaphore(8)
    if args.rescore:
        prior = json.loads(Path(args.rescore).read_text())
        if prior["fixture"] != fx["label"]:
            sys.exit(f"[eval] --rescore: the results file is for the fixture {prior['fixture']}, not {fx['label']}")
        todo = {arm: [{k: v for k, v in r.items() if k in ("arm", "variant", "run", "status", "why", "draft", "rc", "session", "cost_usd", "num_turns", "wall_s", "resolved_model", "scan")}
                      for r in a["runs"]] for arm, a in prior["arms"].items()}
    else:
        sem = asyncio.Semaphore(args.concurrency)
        todo = {}
        for arm in args.arm:
            variants = [v for v in ARMS[arm][1] if v in fx["variants"] and (not args.variant or v in args.variant)]
            cells = [(v, n) for v in variants for n in range(1, args.runs + 1)]
            reserve(cfg, fx, arm, cells, "")
            runs = list(await asyncio.gather(*(review_once(cfg, fx, arm, v, n, sem) for v, n in cells)))
            again = [r for r in runs if r["status"] == "void"]
            reserve(cfg, fx, arm, [(r["variant"], r["run"]) for r in again], "-rerun")
            runs += list(await asyncio.gather(*(review_once(cfg, fx, arm, r["variant"], r["run"], sem, "-rerun") for r in again)))
            todo[arm] = runs
            doc["arms"][arm] = {"runs": runs, "unjudged": True}
            save()
    for arm, runs in todo.items():
        await asyncio.gather(*(judge_run(cfg, fx, r, judge_sem) for r in runs if r["status"] == "ok"))
        row = report(cfg, fx, arm, runs, started, args.note, record=not args.no_record)
        doc["arms"][arm] = {"runs": runs, "row": row}
        doc["judge_resolved"] = sorted(cfg["judge_resolved"])
        doc["judge_cost_usd"] = cfg["judge_cost"]
        save()
    print(f"[eval] wrote {out}; judge calls cost ${cfg['judge_cost']:.2f}", flush=True)
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fixture", default="tuning", help="a directory under --fixtures-dir")
    ap.add_argument("--fixtures-dir", default=str(HERE / "fixtures"))
    ap.add_argument("--results-dir", default=str(HERE))
    ap.add_argument("--arm", action="append", default=[], choices=sorted(ARMS))
    ap.add_argument("--variant", action="append", default=[], choices=("plant-a", "plant-b", "twin"))
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--concurrency", type=int, default=3)
    ap.add_argument("--max-cost-usd", type=float, default=90.0, help="no new review starts once the reviews cost this much")
    ap.add_argument("--timeout-s", type=int, default=2400)
    ap.add_argument("--note", default="baseline")
    ap.add_argument("--no-record", action="store_true", help="print the rows, do not append them")
    ap.add_argument("--check-fixture", action="store_true", help="build the variants and stop; model-free")
    ap.add_argument("--judge-sanity", action="store_true", help="run the judges on judge-sanity.json and stop")
    ap.add_argument("--rescore", help="a results-*.json: judge its stored drafts again; no review is spawned")
    ap.add_argument("--deny-read", action="append", default=[], help="one more path no session may read; repeatable")
    ap.add_argument("--allow-dirty", action="store_true", help="run with uncommitted changes in the files under test")
    ap.add_argument("--keep", action="store_true", help="keep each run's directory")
    ap.add_argument("--cache-dir", default=os.path.join(os.environ.get("XDG_CACHE_HOME") or "~/.cache", "pass-1-completeness-eval"))
    ap.add_argument("--reviewer-model", default=os.environ.get("REVIEWER_MODEL"))
    ap.add_argument("--judge-model", default=os.environ.get("JUDGE_MODEL"))
    args = ap.parse_args()
    if not (args.arm or args.check_fixture or args.judge_sanity or args.rescore):
        ap.error("name at least one --arm, or --check-fixture, --judge-sanity or --rescore")
    try:
        sys.exit(asyncio.run(main_async(args)))
    except Exception as e:
        if type(e).__name__ == "RateLimitedError":
            sys.exit(f"[eval] {e}")
        raise


if __name__ == "__main__":
    main()
