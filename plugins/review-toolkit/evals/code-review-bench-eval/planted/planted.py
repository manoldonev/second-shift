#!/usr/bin/env python3
"""The planted mode of the code-review bench: does the lane's review catch what a plain review with the
ticket misses?

Each case under cases/ is a real upstream issue and its real fix, pinned by sha, with one planted defect
or none. The recipe builds each case outside the repo with no remote and reviews it with two arms:
`plain`, a plain prompt with the ticket and the same verdict output contract as the lane, and `lane`, the
lane's model-free gates and then the review prompt and scheduler input rendered from run.sh as merged. It
scores right, wrong, harm and noise per class and arm, with cost and wall time.

Subcommands, model-free unless named:
  check     the corpus's structure; CI runs it through corpus-selftest.sh
  render    build one case for one arm, run the lane's gates and render the arm's prompt
  review    render, then spawn the arm's session and collect its verdict (billed)
  score     score review records with a canned judge; score-selftest.sh drives it
  verify    build every case, check a runner case's expected stop, and print each ground-truth range at
            the head (network; npm for a runner case)
  run       the operator's recipe: the judge's calibration, the reviews, the judge, the report (billed); with
            --pilot, the plain arm on the pilot cases only, and no changelog row
  cases     right, wrong and noise per case, run and arm from a results file, and the right rate over a set of ids
"""
from __future__ import annotations

import argparse
import asyncio
import collections
import datetime as dt
import fnmatch
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

HERE = Path(__file__).resolve().parent
BENCH_DIR = HERE.parent
REPO = HERE.parents[4]
RUN_SH = REPO / "plugins" / "dev-pipeline" / "skills" / "run" / "run.sh"
TOOLS = REPO / "plugins" / "dev-pipeline" / "tools"
CLASSES = ("P1", "P2", "P3", "P4", "P5")
CONTROL = "control"
MIN_PER_CLASS, MIN_CONTROLS = 4, 5
LICENSES = ("MIT", "BSD-2-Clause", "BSD-3-Clause", "Apache-2.0", "ISC")
WINDOW = 3
MIN_CHANGED_LINES = 80
MAX_UPSTREAM_SHARE = 0.40
RUNNER_FORMAT = "jest-json"
EXPECT_STOPS = ("fails_without_change",)
PLAN_COVERAGE = TOOLS / "plan-coverage.sh"
STOP_RED_RE = re.compile(r"^RED: AC-\d+ — (.+?)::.+ passes on the record commit's tree ")
RUNNER_BIN_RE = re.compile(r"node_modules/\S+")
PATTERNS = ("rejects-held-input", "dead-guard", "two-hop-caller", "omitted-option")
# the cases that predate the size floor, the distraction rule and truth.pattern; every other case meets all three
FROZEN = frozenset("""
    a7t4yp b6r1vy c8w4tf e4u9ob f1h8ku f6t2gy g7s3hq h4n8qe h9x3cd j3q6mr j7m5ux k5e2hw k8w3dq m2g6wc n3f6wu
    n4d9sw o6z3fl q4m8zt r2n5ax r8b3kz s9b2ze t5j8ke u1c9nb v6d1ij w2k7np x5l9dn y2h6cv y8k1rv z8c2lm
""".split())
# P4 candidates that only a plain pilot reviews: checked like every case, but outside the counts, the cap and a normal run
PILOT = frozenset("""
    ba4kxe ce7nwr dh2qyu fm8tzo gj3wvs hq6lna jt9rme kx5vdb la2swf mn7cuh nw4ejk oy8ftq qb3hzm rc6giv sd9kwn tf2mxa
    ug5nrb vh8qsc wk3tyd xm6uze yn9vaf zq4wbg ar7xch bs2yei cu5zfj dv8agk ew3bhl fx6cim gy9djn hz4eko ib7flq jc2gmr
""".split())
ARMS = ("plain", "lane")
SENDBACK_SCORES = ("violated", "undeterminable")
CASE_ID_RE = re.compile(r"[a-z0-9]{6}")
CLASS_IN_ID_RE = re.compile(r"p[1-5]|ctl|ctrl")
SHA_RE = re.compile(r"[0-9a-f]{40}")
UPSTREAM_RE = re.compile(r"https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)\.git")
MARKER_RE = re.compile(
    r"(?i)\b(plant(s|ed|ing)?|ground[- ]truth|answer[- ]key|corpus|clean[- ]control|seeded|injected|sabotag\w*)\b|\bP[1-5]\b"
)
# the lane's session reaches the local gh by its bare name; any other gh, a remote or the network voids the run
LANE_BLIND_RE = re.compile(
    r'"name":\s*"(WebFetch|WebSearch)"|\bgh (api|repo|auth|browse|release|run|workflow|search)\b|\S/gh\b|git (fetch|pull|remote|push)|\bcurl |\bwget '
)
FUNC_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\(\) \{")
RUN_VARS = ("TEST_PATH_ERE", "FWC_TIMEOUT_DEFAULT", "FWC_GRACE", "FWC_TIMED_OUT", "FWC_TMP", "FWC_JUDGE",
            "PLAN_NOTES", "FWC_NOTES", "SEAM_SCRUB", "SCRUB_ENV")
RUN_NEEDS = ("plan_coverage", "fails_without_change", "review_input", "review_prompt", "review_allowlist", "inner_ms")
REVIEW_TIMEOUT_S = 3600
REVIEW_MAX_TURNS = 300
DISALLOWED = "AskUserQuestion,EnterWorktree,ExitWorktree"
FINDING_RE = re.compile(r"^- \[(blocker|note)\] ([BN]\d+) ?(.*)$")
LOC_RE = re.compile(r"([A-Za-z0-9_@./\[\]-]+\.[A-Za-z0-9]+):(\d+)(?:\s*[-–]\s*(\d+))?")
BARE_PATH_RE = re.compile(r"[A-Za-z0-9_@.\[\]-]*(?:/[A-Za-z0-9_@.\[\]-]+)*/[A-Za-z0-9_@\[\]-][A-Za-z0-9_@.\[\]-]*\.[A-Za-z0-9]+")


class JudgeFailed(RuntimeError):
    pass


class BuildError(RuntimeError):
    pass


def load_bench():
    spec = importlib.util.spec_from_file_location("bench", BENCH_DIR / "bench.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# --- the corpus ------------------------------------------------------------------------------

def load_case(d: Path) -> dict:
    case = json.loads((d / "case.json").read_text())
    case["id"], case["dir"] = d.name, d
    return case


def load_cases(root: Path) -> list[dict]:
    cases_dir = root / "cases"
    return [load_case(d) for d in sorted(cases_dir.iterdir()) if d.is_dir()] if cases_dir.is_dir() else []


def repo_slug(case: dict) -> str:
    return case["upstream"].rstrip("/").removesuffix(".git").rsplit("/", 1)[-1]


def upstream_key(case: dict) -> str:
    owner, name = case["upstream"].rstrip("/").removesuffix(".git").rsplit("/", 2)[-2:]
    return f"{owner}__{name}"


def record_rel(case: dict) -> str:
    return f"docs/plans/{repo_slug(case)}-{case['issue']}-decisions.md"


def plan_rel(case: dict) -> str:
    return f"docs/plans/{repo_slug(case)}-{case['issue']}-plan.md"


def read_ticket(case: dict) -> tuple[str, str]:
    text = (case["dir"] / "ticket.md").read_text()
    first, _, rest = text.partition("\n")
    return first.removeprefix("# ").strip(), rest.strip() + "\n"


def section(text: str, heading: str) -> str:
    out, on = [], False
    for line in text.splitlines():
        if re.match(r"^#+\s", line):
            if on:
                break
            on = re.match(rf"^#+\s+{re.escape(heading)}\s*$", line, re.I) is not None
            continue
        if on:
            out.append(line)
    return "\n".join(out)


def parse_patch(patch: str) -> dict[str, list[tuple[str, int, str]]]:
    """Every file the patch touches, with each hunk line as (kind, line number, text): `+` at its new-side
    number, `-` at its old-side number, and a context line twice, as ` +` and ` -`. A hunk is read by its
    header's counts, so a removed line that begins `-- ` is never taken for a file header."""
    files: dict[str, list[tuple[str, int, str]]] = {}
    lines = patch.split("\n")
    cur, i = None, 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("--- ") and i + 1 < len(lines) and lines[i + 1].startswith("+++ "):
            a, b = line[4:].strip(), lines[i + 1][4:].strip()
            cur = (b if b != "/dev/null" else a).split("\t")[0]
            cur = cur[2:] if cur[:2] in ("a/", "b/") else cur
            files.setdefault(cur, [])
            i += 2
            continue
        m = re.match(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", line)
        if m and cur is not None:
            old, olen, new, nlen = int(m[1]), int(m[2] or 1), int(m[3]), int(m[4] or 1)
            i += 1
            while i < len(lines) and (olen > 0 or nlen > 0):
                h = lines[i]
                if h.startswith("+"):
                    files[cur].append(("+", new, h[1:])); new += 1; nlen -= 1
                elif h.startswith("-"):
                    files[cur].append(("-", old, h[1:])); old += 1; olen -= 1
                elif h.startswith("\\"):
                    pass
                else:
                    files[cur].append((" +", new, h[1:])); files[cur].append((" -", old, h[1:]))
                    new += 1; old += 1; nlen -= 1; olen -= 1
                i += 1
            continue
        i += 1
    return files


def patch_files(patch: str) -> dict[str, list[tuple[str, int]]]:
    """Every file the patch touches, with the (side, line) pairs its hunks cover: `head` for an added or
    context line at its new-side number, `base` for a removed or context line at its old-side number."""
    return {f: [("head" if k.endswith("+") else "base", n) for k, n, _ in rows] for f, rows in parse_patch(patch).items()}


def added_text(patch: str, path: str) -> str:
    return "\n".join(t for k, _, t in parse_patch(patch).get(path, []) if k == "+")


def changed_lines(patch: str) -> int:
    return sum(1 for f, rows in parse_patch(patch).items() if not f.startswith("docs/plans/")
               for k, _, _ in rows if k in ("+", "-"))


def markers_in(text: str, truth: dict | None = None) -> list[str]:
    hits = sorted({m.group(0) for m in MARKER_RE.finditer(text)})
    desc = (truth or {}).get("description", "")
    if desc and desc.rstrip(".").lower() in text.lower():
        hits.append("the ground-truth description")
    return hits


def path_level(loc: dict) -> bool:
    return "start" not in loc and "end" not in loc


def near_truth(d: dict, locs: list[dict]) -> bool:
    """A finding on the distraction would reach the judge as a finding on the truth: the same file, and within
    WINDOW of a ranged location or anywhere in a path-level one, on either side, as in_range reads it."""
    for loc in locs:
        if not isinstance(loc, dict) or loc.get("file") != d["file"]:
            continue
        if path_level(loc):
            return True
        s, e = loc.get("start"), loc.get("end")
        if isinstance(s, int) and isinstance(e, int) and d["start"] <= e + WINDOW and d["end"] >= s - WINDOW:
            return True
    return False


def check_distractions(case: dict, touched: dict[str, list[tuple[str, int]]], bad) -> None:
    ds = case.get("distractions")
    if not ds:
        bad("case.json has no distractions")
        return
    locs = (case.get("truth") or {}).get("locations") or []
    for d in ds:
        if not isinstance(d, dict) or not d.get("file") or d.get("side") not in ("head", "base") \
                or not isinstance(d.get("start"), int) or not isinstance(d.get("end"), int) or not 1 <= d["start"] <= d["end"]:
            bad(f"distraction {d} is not {{file, start, end, side: head|base, why}} with start <= end")
            continue
        where = f"{d['file']}:{d['start']}-{d['end']}"
        why = str(d.get("why", "")).strip()
        if not why.endswith(".") or len(re.findall(r"[.!?](?:\s|$)", why)) != 1:
            bad(f"distraction {where} has no one-sentence why")
        if not any(s == d["side"] and d["start"] <= n <= d["end"] for s, n in touched.get(d["file"], [])):
            bad(f"distraction {where} falls inside no hunk of the patch")
        if near_truth(d, locs):
            bad(f"distraction {where} sits within {WINDOW} lines of a truth location")


def overlay_runners(cfg: dict) -> list:
    cmds = cfg.get("commands") if isinstance(cfg, dict) else None
    return [r for c in (cmds or {}).values() if isinstance(c, dict) for r in (c.get("testRunners") or [])]


def plan_tests(case: dict, patch: str) -> tuple[list[tuple[str, str, str, str]], str]:
    """The plan's tagged tests as run.sh's gate reads them: plan-coverage.sh --files on the case's record and
    the plan the patch adds, one (kind, AC, file, case) per tagged test. The second item names a failure."""
    with tempfile.TemporaryDirectory() as t:
        plan = Path(t) / "plan.md"
        plan.write_text(added_text(patch, plan_rel(case)) + "\n")
        r = subprocess.run(["bash", str(PLAN_COVERAGE), "--files", str(case["dir"] / "record.md"), str(plan)],
                           text=True, capture_output=True)
    if r.returncode:
        return [], f"plan-coverage.sh --files exits {r.returncode} on the plan: {(r.stdout + r.stderr).strip()[:300]}"
    rows = [tuple((l.split("\t") + ["", "", "", ""])[:4]) for l in r.stdout.splitlines() if l.strip()]
    return rows, ""


def check_runner(case: dict, cfg: dict, patch: str, bad) -> None:
    """A runner case names its expected stop and an overlay whose testRunners the gate can run; every other
    case names an overlay with none, so the gate never runs on it."""
    runners, stop, ov = overlay_runners(cfg), case.get("expect_stop"), case["overlay"]
    if stop is not None and stop not in EXPECT_STOPS:
        bad(f"expect_stop {stop!r} is not one of {', '.join(EXPECT_STOPS)}")
        return
    if runners and stop is None:
        bad(f"overlay {ov} declares testRunners, but case.json names no expect_stop")
        return
    if stop is not None and not runners:
        bad(f"case.json names expect_stop, but overlay {ov} declares no testRunners")
        return
    if not runners:
        return
    globs = []
    for i, r in enumerate(runners):
        if not isinstance(r, dict) or not str(r.get("command") or "").strip():
            bad(f"testRunners[{i}] of overlay {ov} has no command")
            continue
        if r.get("format") != RUNNER_FORMAT:
            bad(f"testRunners[{i}] of overlay {ov} has format {r.get('format')!r}, not {RUNNER_FORMAT}")
        globs += [g for g in r.get("when") or [] if isinstance(g, str)]
    if plan_rel(case) not in patch_files(patch) or not PLAN_COVERAGE.is_file():
        return
    tests, err = plan_tests(case, patch)
    if err:
        bad(err)
    for _, ac, f, c in tests:
        if not c:
            bad(f"the plan tags {f} for {ac} as a bare file, but a {RUNNER_FORMAT} runner judges named tests: name it as {f}::<case>")
        if not any(fnmatch.fnmatchcase(f, g) for g in globs):
            bad(f"the plan tags {f} for {ac}, which no when glob of overlay {ov}'s testRunners matches")


def check_case(case: dict, root: Path) -> list[str]:
    p, cid, d = [], case["id"], case["dir"]

    def bad(msg):
        p.append(f"{cid}: {msg}")

    if not CASE_ID_RE.fullmatch(cid):
        bad("the case id is not six lowercase letters or digits")
    elif CLASS_IN_ID_RE.search(cid):
        bad("the case id reads as a class name")
    if not UPSTREAM_RE.fullmatch(str(case.get("upstream", ""))):
        bad("upstream is not an https://github.com/<owner>/<repo>.git URL")
    for k in ("instance", "base_branch", "overlay", "commit"):
        if not str(case.get(k, "")).strip():
            bad(f"case.json has no {k}")
    if case.get("license") not in LICENSES:
        bad(f"license {case.get('license')!r} is not one of {', '.join(LICENSES)}")
    if not SHA_RE.fullmatch(str(case.get("base", ""))):
        bad("base is not a 40-hex sha")
    for k in ("issue", "pr"):
        if not isinstance(case.get(k), int):
            bad(f"{k} is not a number")
    if p:
        return p
    if case["instance"] not in (f"{upstream_key(case)}-{case['pr']}", f"{upstream_key(case)}-pr{case['pr']}"):
        bad(f"instance {case['instance']!r} is neither {upstream_key(case)}-{case['pr']} nor {upstream_key(case)}-pr{case['pr']}")
    if cid in PILOT and (case.get("truth") or {}).get("class") != "P4":
        bad("a pilot case is not P4")
    ov = root / "overlays" / case["overlay"]
    if not (ov / "review-context.md").is_file() or not (ov / "review-context.md").read_text().strip():
        bad(f"overlay {case['overlay']} has no review-context.md")
    cfg = {}
    try:
        cfg = json.loads((ov / "config.json").read_text())
        if cfg.get("configVersion") != 3:
            bad(f"overlay {case['overlay']}'s config.json is not configVersion 3")
    except (OSError, ValueError):
        bad(f"overlay {case['overlay']} has no readable config.json")

    ticket = d / "ticket.md"
    acs: set[str] = set()
    if not ticket.is_file():
        bad("no ticket.md")
    else:
        t = ticket.read_text()
        if not t.startswith("# "):
            bad("ticket.md does not start with a '# ' title line")
        acs = set(re.findall(r"^- (AC-\d+):", section(t, "Acceptance criteria"), re.M))
        if not acs:
            bad("ticket.md has no '## Acceptance criteria' block with '- AC-n:' items")
    rec = d / "record.md"
    rows: set[str] = set()
    if not rec.is_file():
        bad("no record.md")
    else:
        r = rec.read_text()
        rows = set(re.findall(r"^\| *(D-\d+) *\|", r, re.M))
        if not rows:
            bad("record.md has no '| D-n |' row")
        ti = section(r, "Test intent")
        m = re.search(r"^ACs:(.*)$", ti, re.M)
        if not m:
            bad("record.md has no '## Test intent' section with an 'ACs:' line")
        else:
            listed = set(re.findall(r"AC-\d+", m[1]))
            if not listed or listed - acs:
                bad(f"the Test intent lists {sorted(listed - acs) or 'no AC'} that the ticket does not define")
    patch_path = d / "patch.diff"
    touched: dict[str, list[tuple[str, int]]] = {}
    patch = ""
    if not patch_path.is_file() or not patch_path.read_text().strip():
        bad("no patch.diff")
    else:
        patch = patch_path.read_text()
        touched = patch_files(patch)
        if plan_rel(case) not in touched:
            bad(f"the patch does not add the plan at {plan_rel(case)}")
        elif not re.search(r"^- \[[ x]\] \d+\.\d+ .*\[AC-\d+\]\s*$", added_text(patch, plan_rel(case)), re.M):
            bad("the plan in the patch has no test task tagged to an AC")
        if record_rel(case) in touched:
            bad("the patch edits the record")
        if any(f == ".claude/second-shift.config.json" or f.startswith(".claude/second-shift/") for f in touched):
            bad("the patch edits the review configuration")

    truth = case.get("truth") or {}
    cls = truth.get("class")
    if cls not in (*CLASSES, CONTROL):
        bad(f"truth.class {cls!r} is not one of {', '.join((*CLASSES, CONTROL))}")
    elif cls != CONTROL:
        desc = str(truth.get("description", "")).strip()
        if not desc.endswith(".") or len(re.findall(r"[.!?](?:\s|$)", desc)) != 1:
            bad("truth.description is not one sentence")
        locs = truth.get("locations") or []
        if not locs:
            bad("truth has no locations")
        hit = outside = False
        for loc in locs:
            if loc.get("side") not in ("head", "base") or not loc.get("file"):
                bad(f"truth location {loc} is not {{file, side: head|base}} with an optional start <= end")
                continue
            if path_level(loc):
                continue
            if not isinstance(loc.get("start"), int) or not isinstance(loc.get("end"), int) or not 1 <= loc["start"] <= loc["end"]:
                bad(f"truth location {loc} is not {{file, side: head|base}} with an optional start <= end")
                continue
            lines = {n for s, n in touched.get(loc["file"], []) if s == loc["side"]}
            inside = any(loc["start"] <= n <= loc["end"] for n in lines)
            hit, outside = hit or inside, outside or not inside
        if locs and not hit:
            bad("no ranged truth location falls inside a hunk of the patch")
        if cid in PILOT and locs and not outside:
            bad("no ranged truth location falls outside every hunk of the patch, where the broken caller sits")
        if cls == "P2":
            if truth.get("row") not in rows:
                bad(f"truth.row {truth.get('row')!r} is not a D-n row of the record")
        elif "row" in truth:
            bad("only a P2 case names truth.row")
    if cls == "P4" and (cid not in FROZEN or "pattern" in truth):
        if truth.get("pattern") not in PATTERNS:
            bad(f"truth.pattern {truth.get('pattern')!r} is not one of {', '.join(PATTERNS)}")
    elif "pattern" in truth:
        bad("only a P4 case names truth.pattern")
    if cid not in FROZEN:
        if patch and changed_lines(patch) < MIN_CHANGED_LINES:
            bad(f"the patch changes {changed_lines(patch)} lines outside docs/plans/, fewer than {MIN_CHANGED_LINES}")
        check_distractions(case, touched, bad)
    elif "distractions" in case:
        check_distractions(case, touched, bad)
    check_runner(case, cfg, patch, bad)
    for name, text in (("the case id", cid), ("the commit subject", case["commit"]),
                       ("ticket.md", ticket.read_text() if ticket.is_file() else ""),
                       ("record.md", rec.read_text() if rec.is_file() else ""), ("patch.diff", patch)):
        hits = markers_in(text, truth if cls != CONTROL else None)
        if hits:
            bad(f"{name} carries a marker: {', '.join(hits)}")
    return p


def check_corpus(root: Path) -> tuple[list[str], dict[str, int], dict[str, int], dict[str, int]]:
    """The problems, then the scored corpus's class and P4 pattern counts, then the pilot cases' pattern counts."""
    everything = load_cases(root)
    problems: list[str] = []
    counts = {c: 0 for c in (*CLASSES, CONTROL)}
    patterns = {p: 0 for p in PATTERNS}
    pilot = {p: 0 for p in PATTERNS}
    for cid in sorted(PILOT - {c["id"] for c in everything}):
        problems.append(f"corpus: PILOT names {cid}, which has no case")
    for case in everything:
        problems += check_case(case, root)
        truth = case.get("truth") or {}
        if case["id"] in PILOT:
            if truth.get("pattern") in PATTERNS:
                pilot[truth["pattern"]] += 1
            continue
        if truth.get("class") in counts:
            counts[truth["class"]] += 1
        if truth.get("class") == "P4" and truth.get("pattern") in PATTERNS:
            patterns[truth["pattern"]] += 1
    cases = [c for c in everything if c["id"] not in PILOT]
    for c in CLASSES:
        if counts[c] < MIN_PER_CLASS:
            problems.append(f"corpus: class {c} has {counts[c]} cases, fewer than {MIN_PER_CLASS}")
    if counts[CONTROL] < MIN_CONTROLS:
        problems.append(f"corpus: {counts[CONTROL]} clean controls, fewer than {MIN_CONTROLS}")
    for p, n in patterns.items():
        if not n:
            problems.append(f"corpus: no P4 case has pattern {p}")
    for url, n in sorted(collections.Counter(c.get("upstream", "") for c in cases).items()):
        if n > MAX_UPSTREAM_SHARE * len(cases):
            problems.append(f"corpus: {url.removesuffix('.git')} holds {n} of {len(cases)} cases ({n / len(cases):.1%}), "
                            f"more than {MAX_UPSTREAM_SHARE:.0%}")
    notice = root / "NOTICE"
    text = notice.read_text() if notice.is_file() else ""
    for url in sorted({c.get("upstream", "") for c in everything}):
        if url and url.removesuffix(".git") not in text:
            problems.append(f"corpus: NOTICE does not name {url.removesuffix('.git')}")
    return problems, counts, patterns, pilot


# --- building a case -------------------------------------------------------------------------

GIT_CFG = ["-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", "-c", "init.defaultBranch=main",
           "-c", "core.autocrlf=false", "-c", "advice.detachedHead=false"]
GIT_ID = {"GIT_AUTHOR_NAME": "Contributor", "GIT_AUTHOR_EMAIL": "contributor@users.noreply.github.com",
          "GIT_COMMITTER_NAME": "Contributor", "GIT_COMMITTER_EMAIL": "contributor@users.noreply.github.com"}


def git(args, cwd: Path, env: dict | None = None, check: bool = True) -> str:
    r = subprocess.run(["git", *GIT_CFG, *args], cwd=cwd, env={**os.environ, **GIT_ID, **(env or {})},
                       text=True, capture_output=True)
    if check and r.returncode:
        raise BuildError(f"git {' '.join(map(str, args))}: {r.stderr.strip()[:400]}")
    return r.stdout.strip()


def base_store(case: dict, clones: Path) -> Path:
    """One bare repo per upstream, holding each base commit it was asked for at depth 1."""
    store = clones / upstream_key(case)
    if not store.exists():
        store.parent.mkdir(parents=True, exist_ok=True)
        git(["init", "-q", "--bare", str(store)], cwd=store.parent)
    ref = f"refs/bases/{case['base']}"
    if not git(["rev-parse", "-q", "--verify", ref], cwd=store, check=False):
        git(["fetch", "-q", "--depth", "1", "--no-tags", case["upstream"], f"{case['base']}:{ref}"], cwd=store)
    return store


def deps_dir(case: dict, clones: Path) -> Path:
    return clones / f"{upstream_key(case)}.deps" / case["base"]


def runner_bins(runners: list) -> list[str]:
    return sorted({b for r in runners if isinstance(r, dict) for b in RUNNER_BIN_RE.findall(str(r.get("command") or ""))})


def install_deps(case: dict, store: Path, clones: Path, dest: Path, bins: list[str]) -> None:
    """The dependencies of a runner whose binary lives under node_modules/, installed once per upstream and
    base from the base's package files, with network and no install scripts, then copied into the checkout,
    where git ignores them. A binary the install did not provide fails the build, so a gate never runs
    without its runner."""
    cache = deps_dir(case, clones)
    if not cache.is_dir():
        npm = shutil.which("npm")
        if not npm:
            raise BuildError(f"{case['id']}: the overlay declares testRunners, and no npm is on PATH to install them")
        part = cache.with_name(cache.name + ".partial")
        shutil.rmtree(part, ignore_errors=True)
        part.mkdir(parents=True)
        for name in ("package.json", "package-lock.json"):
            text = git(["show", f"refs/bases/{case['base']}:{name}"], cwd=store, check=False)
            if text:
                (part / name).write_text(text + "\n")
        if not (part / "package.json").is_file():
            raise BuildError(f"{case['id']}: the base {case['base']} has no package.json to install the runner from")
        r = subprocess.run([npm, "install", "--ignore-scripts", "--no-audit", "--no-fund"], cwd=part, text=True, capture_output=True)
        if r.returncode:
            raise BuildError(f"{case['id']}: npm install exited {r.returncode} in {part}: {(r.stdout + r.stderr).strip()[-400:]}")
        part.rename(cache)
    if (cache / "node_modules").is_dir():
        shutil.copytree(cache / "node_modules", dest / "node_modules", symlinks=True)
    (dest / ".git" / "info").mkdir(exist_ok=True)
    with (dest / ".git" / "info" / "exclude").open("a") as f:
        f.write("/node_modules/\n")
    missing = [b for b in bins if not (dest / b).exists()]
    if missing:
        raise BuildError(f"{case['id']}: the runner needs {', '.join(missing)}, which the install at {cache} did not provide")


def commit(dest: Path, subject: str, when: int) -> str:
    stamp = f"@{when} +0000"
    git(["commit", "-q", "--no-verify", "-m", subject], cwd=dest, env={"GIT_AUTHOR_DATE": stamp, "GIT_COMMITTER_DATE": stamp})
    return git(["rev-parse", "HEAD"], cwd=dest)


def build(case: dict, arm: str, dest: Path, clones: Path, root: Path) -> dict:
    """The case's checkout for one arm: the upstream base at depth 1, the overlay commit (review-context.md
    and the config, which origin/<base_branch> names), the record as its own commit for the lane only, then
    the patch. No remote, no FETCH_HEAD, no reflog."""
    if arm not in ARMS:
        raise BuildError(f"unknown arm {arm}")
    if dest.exists():
        raise BuildError(f"{dest} already exists")
    store = base_store(case, clones)
    dest.mkdir(parents=True)
    git(["init", "-q", str(dest)], cwd=dest.parent)
    git(["fetch", "-q", "--depth", "1", "--no-tags", str(store), f"refs/bases/{case['base']}"], cwd=dest)
    branch = f"fix-{case['issue']}"
    git(["checkout", "-q", "-b", branch, "FETCH_HEAD"], cwd=dest)
    t0 = int(git(["log", "-1", "--format=%ct"], cwd=dest))
    ov = root / "overlays" / case["overlay"]
    (dest / ".claude" / "second-shift").mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ov / "review-context.md", dest / ".claude" / "second-shift" / "review-context.md")
    shutil.copyfile(ov / "config.json", dest / ".claude" / "second-shift.config.json")
    git(["add", "-f", ".claude/second-shift/review-context.md", ".claude/second-shift.config.json"], cwd=dest)
    base = commit(dest, "chore: add the review configuration", t0 + 3600)
    git(["update-ref", f"refs/remotes/origin/{case['base_branch']}", base], cwd=dest)
    first = None
    if arm == "lane":
        rec = dest / record_rel(case)
        rec.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(case["dir"] / "record.md", rec)
        git(["add", "-f", record_rel(case)], cwd=dest)
        first = commit(dest, "docs: add the decision record", t0 + 7200)
    git(["apply", "--index", "--whitespace=nowarn", str(case["dir"] / "patch.diff")], cwd=dest)
    head = commit(dest, case["commit"], t0 + 10800)
    bins = runner_bins(overlay_runners(json.loads((ov / "config.json").read_text())))
    if bins:
        install_deps(case, store, clones, dest, bins)
    (dest / ".git" / "FETCH_HEAD").unlink(missing_ok=True)
    git(["reflog", "expire", "--expire=now", "--all"], cwd=dest)
    if git(["remote"], cwd=dest):
        raise BuildError(f"{dest} has a remote")
    return {"checkout": str(dest), "arm": arm, "branch": branch, "base": base, "first": first, "head": head,
            "record_rel": record_rel(case), "plan_rel": plan_rel(case)}


def bash_parses(chunk: str) -> bool:
    return subprocess.run(["bash", "-n"], input=chunk, text=True, capture_output=True).returncode == 0


def extract_run_functions(text: str) -> str:
    """Every function run.sh defines, and the globals they read, as text: run.sh runs its whole launch at
    the top level and has no source guard, so it is read, never sourced. A definition is one line when that
    line parses alone, else it runs to the first column-0 `}` after which the text parses."""
    lines = text.split("\n")
    out, names = [], set()
    for v in RUN_VARS:
        i = next((k for k, l in enumerate(lines) if l.startswith(f"{v}=")), None)
        if i is None:
            raise BuildError(f"run.sh no longer assigns {v}")
        j = i
        while not bash_parses("\n".join(lines[i:j + 1])):
            j += 1
            if j >= len(lines):
                raise BuildError(f"run.sh's assignment of {v} does not parse")
        out.extend(lines[i:j + 1])
    i = 0
    while i < len(lines):
        m = FUNC_RE.match(lines[i])
        if not m:
            i += 1
            continue
        if bash_parses(lines[i]):
            out.append(lines[i]); names.add(m[1]); i += 1
            continue
        j = i + 1
        while True:
            while j < len(lines) and lines[j] != "}":
                j += 1
            if j >= len(lines):
                raise BuildError(f"run.sh's {m[1]}() has no closing brace that parses")
            if bash_parses("\n".join(lines[i:j + 1])):
                break
            j += 1
        out.extend(lines[i:j + 1]); names.add(m[1]); i = j + 1
    missing = [n for n in RUN_NEEDS if n not in names]
    if missing:
        raise BuildError(f"run.sh no longer defines {', '.join(missing)}")
    body = "\n".join(out) + "\n"
    if not bash_parses(body):
        raise BuildError("the functions extracted from run.sh do not parse together")
    return body


def write_gh_state(case: dict, b: dict, ghdir: Path) -> None:
    owner, name = upstream_key(case).split("__", 1)
    title, body = read_ticket(case)
    ghdir.mkdir(parents=True, exist_ok=True)
    (ghdir / "issue.json").write_text(json.dumps({
        "number": case["issue"], "title": title, "body": body, "comments": [], "state": "OPEN", "labels": [],
        "url": f"https://github.com/{owner}/{name}/issues/{case['issue']}"}))
    (ghdir / "pr.json").write_text(json.dumps({
        "number": case["pr"], "title": "", "body": "", "state": "OPEN", "isDraft": True,
        "baseRefName": case["base_branch"], "headRefName": b["branch"], "headRefOid": b["head"],
        "author": {"login": "contributor"}, "url": f"https://github.com/{owner}/{name}/pull/{case['pr']}"}))
    (ghdir / "comments.json").write_text("[]")


def install_gh(bindir: Path) -> Path:
    bindir.mkdir(parents=True, exist_ok=True)
    gh = bindir / "gh"
    shutil.copyfile(HERE / "gh", gh)
    gh.chmod(0o755)
    return bindir


def render(case: dict, arm: str, work: Path, clones: Path, root: Path) -> dict:
    """Build the case under <work>/checkout and render the arm's prompt into <work>/state/review.prompt. For
    the lane, its gates run first; a gate that stops the case renders no prompt. Model-free."""
    state, scratch, ghdir = work / "state", work / "scratch", work / "gh"
    for d in (state, scratch):
        d.mkdir(parents=True, exist_ok=True)
    b = build(case, arm, work / "checkout", clones, root)
    out = {**b, "case": case["id"], "state": str(state), "scratch": str(scratch), "ghdir": str(ghdir),
           "prompt": str(state / "review.prompt"), "stopped": False, "gates": {}}
    if arm == "plain":
        tmpl = parse_arm(root / "arms" / "plain.md")
        title, body = read_ticket(case)
        text = tmpl["prompt"].format(title=title, body=body.rstrip("\n"), checkout=b["checkout"], base=b["base"],
                                     head=b["head"], scratch=scratch, out=scratch / "verdict.md")
        (state / "review.prompt").write_text(text)
        out.update(allow=tmpl.get("allow", "Read,Grep,Glob,Write,Bash(git *)"), out=str(scratch / "verdict.md"))
        return out
    write_gh_state(case, b, ghdir)
    funcs = state / "run-functions.sh"
    funcs.write_text(extract_run_functions(RUN_SH.read_text()))
    r = subprocess.run(["bash", str(HERE / "lane-render.sh"), str(funcs), b["checkout"], str(state), str(scratch),
                        str(case["issue"]), str(case["pr"]), case["base_branch"], repo_slug(case), b["branch"]],
                       text=True, capture_output=True)
    (state / "lane-render.log").write_text(r.stdout + r.stderr)
    gates = dict(kv.split("=", 1) for kv in (state / "gates.txt").read_text().split()) if (state / "gates.txt").exists() else {}
    out["gates"] = {k: int(v) for k, v in gates.items()}
    if r.returncode == 1:
        out["stopped"] = True
        return out
    if r.returncode != 0:
        raise BuildError(f"{case['id']}: lane-render.sh exited {r.returncode}: {(r.stdout + r.stderr)[-600:]}")
    shutil.copyfile(Path(b["checkout"]) / ".claude" / "second-shift.config.json", scratch / "second-shift.config.json")
    out.update(allow=(state / "review.allow").read_text().strip(), bash_ms=lane_bash_ms(funcs))
    return out


def lane_bash_ms(funcs: Path) -> str:
    return subprocess.run(["bash", "-c", f'. "$1"; inner_ms {REVIEW_TIMEOUT_S} 120', "_", str(funcs)],
                          text=True, capture_output=True, check=True).stdout.strip()


def parse_arm(path: Path) -> dict:
    text = path.read_text()
    meta, _, body = text.partition("\n---\n")
    arm = {"name": path.stem, "prompt": body.strip() + "\n"}
    for line in meta.splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            arm[k.strip()] = v.strip()
    return arm


# --- a verdict -------------------------------------------------------------------------------

def bare_path(first: str) -> str | None:
    for tok in first.split():
        tok = tok.replace("`", "").rstrip(".,:;)")
        if BARE_PATH_RE.fullmatch(tok):
            return tok
    return None


def parse_verdict(text: str) -> dict:
    lines = text.replace("\r", "").split("\n")
    m = re.match(r"^verdict: (approve|needs-work)\s*$", lines[0] if lines else "")
    v = {"verdict": m[1] if m else None, "rows": {}, "findings": [], "has_findings": False, "stray": []}
    sec = None
    for line in lines[1:]:
        h = re.match(r"^## (.+?)\s*$", line)
        if h:
            sec = h[1].lower()
            v["has_findings"] = v["has_findings"] or sec == "findings"
            continue
        if sec == "decision record rows":
            cells = [c.strip() for c in line.strip().strip("|").split("|")] if line.startswith("|") else []
            if len(cells) >= 2 and re.match(r"^D-\d+\b", cells[0]):
                v["rows"][cells[0].split()[0]] = (cells[1].split() or [""])[0].lower()
        elif sec == "findings":
            f = FINDING_RE.match(line)
            if f:
                first = re.sub(r"^\[[^\]]+\]\s*", "", f[3])
                loc = LOC_RE.search(first)
                path = loc[1] if loc else bare_path(first)
                v["findings"].append({
                    "severity": f[1], "id": f[2], "text": f[3].strip(),
                    "path": path.removeprefix("./") if path else None, "line": int(loc[2]) if loc else None,
                    "end": int(loc[3]) if loc and loc[3] else (int(loc[2]) if loc else None)})
            elif line.startswith("  ") and v["findings"]:
                v["findings"][-1]["text"] += " " + line.strip()
            elif line.strip() and line.strip() != "None.":
                v["stray"].append(line)
    return v


def plain_problems(v: dict) -> list[str]:
    p = []
    if not v["verdict"]:
        p.append("line 1 is not 'verdict: approve' or 'verdict: needs-work'")
    if not v["has_findings"]:
        p.append("no '## Findings' section")
    if v["stray"]:
        p.append(f"{len(v['stray'])} line(s) in '## Findings' are not findings")
    blockers = [f for f in v["findings"] if f["severity"] == "blocker"]
    if v["verdict"] == "approve" and blockers:
        p.append("an approve carries a [blocker]")
    if v["verdict"] == "needs-work" and not blockers:
        p.append("a needs-work carries no [blocker]")
    return p


def lane_problems(body: Path, record_head: Path, record_first: Path) -> list[str]:
    r = subprocess.run(["bash", str(TOOLS / "verdict-check.sh"), str(body), str(record_head), str(record_first)],
                       text=True, capture_output=True)
    if r.returncode == 0:
        return []
    return [l for l in (r.stdout + r.stderr).splitlines() if l.strip()] or [f"verdict-check.sh exited {r.returncode}"]


# --- scoring ---------------------------------------------------------------------------------

def path_matches(found: str | None, want: str) -> bool:
    return bool(found) and (found == want or found.endswith("/" + want) or found.removeprefix("a/").removeprefix("b/") == want)


def in_range(finding: dict, truth: dict) -> bool:
    for loc in truth.get("locations") or []:
        if not path_matches(finding.get("path"), loc["file"]):
            continue
        if path_level(loc):
            return True
        if finding.get("line") is not None and finding["line"] <= loc["end"] + WINDOW and finding["end"] >= loc["start"] - WINDOW:
            return True
    return False


def judged(finding: dict, truth: dict) -> bool:
    if in_range(finding, truth):
        return True
    return finding["severity"] == "blocker" and finding.get("path") is None \
        and any(path_level(loc) for loc in truth.get("locations") or [])


async def judge_findings(truth: dict, review: dict, judge) -> dict[str, bool]:
    """The judge runs on a finding only when its path:line falls inside a planted range, within the window,
    or its path names a path-level location's file. On a case with a path-level location, a [blocker] that
    names no path goes to the judge too."""
    if truth["class"] == CONTROL:
        return {}
    picks = [f for f in review.get("findings", []) if judged(f, truth)]
    verdicts = await asyncio.gather(*(judge(truth["description"], f["text"]) for f in picks))
    return {f["id"]: bool(ok) for f, ok in zip(picks, verdicts)}


def score_review(truth: dict, review: dict, matched: dict[str, bool]) -> dict:
    s = {"right": 0, "wrong": 0, "harm": 0, "noise": 0, "how": ""}
    cls = truth["class"]
    if review["status"] == "gate-stop":
        s["harm" if cls == CONTROL else "right"] = 1
        s["how"] = "gate"
        return s
    findings = review.get("findings", [])
    rows_back = [r for r, sc in (review.get("rows") or {}).items() if sc in SENDBACK_SCORES]
    blockers = [f for f in findings if f["severity"] == "blocker"]
    if cls == CONTROL:
        if blockers or rows_back:
            s["harm"], s["how"] = 1, "blocker" if blockers else "row"
        return s
    row = truth.get("row")

    def hit(f):
        return matched.get(f["id"], False) or (cls == "P2" and row and re.search(rf"\b{re.escape(row)}\b", f["text"]))

    if any(hit(f) for f in blockers):
        s["right"], s["how"] = 1, "blocker"
    elif cls == "P2" and row in rows_back:
        s["right"], s["how"] = 1, "row"
    elif cls == "P5" and any(hit(f) for f in findings if f["severity"] == "note"):
        s["right"], s["how"] = 1, "note"
    if review.get("verdict") == "approve" and not s["right"] and cls != "P5":
        s["wrong"] = 1
    s["noise"] = sum(1 for f in blockers if not hit(f))
    return s


def tally(cases: dict[str, dict], records: list[dict]) -> dict:
    """Per arm and run: each class's counts and the nets the gate reads. A run that is not scorable is
    counted apart and never as an approve."""
    arms: dict = {}
    for r in records:
        cls = cases[r["case"]]["truth"]["class"]
        run = arms.setdefault(r["arm"], {}).setdefault(str(r["run"]), {
            "classes": {c: {"n": 0, "right": 0, "wrong": 0, "harm": 0, "noise": 0, "unscorable": 0} for c in (*CLASSES, CONTROL)},
            "cost_usd": 0.0, "wall_s": 0})
        run["cost_usd"] += r.get("cost_usd") or 0
        run["wall_s"] = max(run["wall_s"], r.get("wall_s") or 0)
        c = run["classes"][cls]
        if "score" not in r:
            c["unscorable"] += 1
            continue
        c["n"] += 1
        for k in ("right", "wrong", "harm", "noise"):
            c[k] += r["score"][k]
    for runs in arms.values():
        for run in runs.values():
            cl = run["classes"]
            net = {k: cl[k]["right"] - cl[k]["wrong"] - cl[k]["harm"] for k in cl}
            run["net"] = sum(net.values())
            run["gate_net"] = run["net"] - net["P2"]
            run["p1_net"] = net["P1"]
    return arms


def gate(arms: dict) -> dict | None:
    if not all(a in arms for a in ARMS):
        return None
    lane, plain = arms["lane"].values(), arms["plain"].values()
    g = {"lane_worst": min(r["gate_net"] for r in lane), "plain_best": max(r["gate_net"] for r in plain),
         "lane_worst_p1": min(r["p1_net"] for r in lane), "plain_best_p1": max(r["p1_net"] for r in plain),
         "runs": {a: len(arms[a]) for a in ARMS}}
    g["pass"] = g["lane_worst"] > g["plain_best"] and g["lane_worst_p1"] > g["plain_best_p1"]
    return g


async def score_records(cases: dict[str, dict], records: list[dict], judge) -> list[dict]:
    for r in records:
        r.pop("score", None)
        if r["status"] not in ("ok", "gate-stop"):
            continue
        truth = cases[r["case"]]["truth"]
        r["matched"] = await judge_findings(truth, r, judge) if r["status"] == "ok" else {}
        r["score"] = score_review(truth, r, r["matched"])
    return records


def collect(arm: str, text: str | None, record_head: Path | None, record_first: Path | None) -> dict:
    """A review record from a verdict's text: parsed, and unscorable when it breaks the arm's contract
    (verdict-check.sh for the lane, the plain contract for plain)."""
    if text is None:
        return {"status": "no-verdict", "problems": ["no verdict was written"]}
    v = parse_verdict(text)
    problems = lane_problems_text(text, record_head, record_first) if arm == "lane" else plain_problems(v)
    return {"status": "unscorable" if problems else "ok", "problems": problems, "verdict": v["verdict"],
            "rows": v["rows"], "findings": v["findings"], "text": text}


def lane_problems_text(text: str, record_head: Path, record_first: Path) -> list[str]:
    with tempfile.TemporaryDirectory() as t:
        body = Path(t) / "verdict.md"
        body.write_text(text)
        return lane_problems(body, record_head, record_first)


def report(cases: dict[str, dict], arms: dict, g: dict | None) -> str:
    out = ["arm    run  class    n  right wrong harm noise unscorable"]
    for arm, runs in sorted(arms.items()):
        for n, run in sorted(runs.items()):
            for cls, c in run["classes"].items():
                out.append(f"{arm:<6} {n:>3}  {cls:<7} {c['n']:>2}  {c['right']:>5} {c['wrong']:>5} {c['harm']:>4} {c['noise']:>5} {c['unscorable']:>10}")
            out.append(f"{arm:<6} {n:>3}  net {run['net']}, without P2 {run['gate_net']}, P1 {run['p1_net']} · cost ${run['cost_usd']:.2f} · wall {run['wall_s']}s")
    if g:
        out.append(f"gate: {'pass' if g['pass'] else 'fail'} — lane's worst run {g['lane_worst']} vs plain's best {g['plain_best']} "
                   f"(without P2); on P1 {g['lane_worst_p1']} vs {g['plain_best_p1']}; runs lane {g['runs']['lane']}, plain {g['runs']['plain']}")
    return "\n".join(out)


def case_report(records: list[dict], ids: list[str]) -> str:
    """Per arm, never pooled: each case's right, wrong and noise per run, then the right rate over the given ids,
    or over every case the file holds. A record with no score, as tally counts it, leaves the denominator."""
    out = ["arm    case    run  right wrong noise"]
    for arm in sorted({r["arm"] for r in records}):
        rs = sorted((r for r in records if r["arm"] == arm), key=lambda r: (r["case"], r["run"]))
        for r in rs:
            s = r.get("score")
            out.append(f"{arm:<6} {r['case']:<7} {r['run']:>3}  " + (f"{s['right']:>5} {s['wrong']:>5} {s['noise']:>5}" if s
                                                                     else f"unscored ({r.get('status')})"))
        want = set(ids) or {r["case"] for r in rs}
        picked = [r for r in rs if r["case"] in want]
        scored = [r for r in picked if r.get("score")]
        right = sum(r["score"]["right"] for r in scored)
        rate = f"{right / len(scored):.0%}" if scored else "none scored"
        absent = sorted(want - {r["case"] for r in rs})
        out.append(f"{arm}: right {right} of {len(scored)} scored case-runs ({rate}) over {len(want)} cases; "
                   f"{len(picked) - len(scored)} unscored" + (f"; no record for {', '.join(absent)}" if absent else ""))
    return "\n".join(out)


# --- the sessions ----------------------------------------------------------------------------

def session_args(arm: str, r: dict, sid: str, model: str) -> list[str]:
    common = ["claude", "-p", "--session-id", sid, "-n", f"bench-{arm}-{r['case']}", "--model", model,
              "--permission-mode", "acceptEdits", "--permission-prompts", "none", "--setting-sources", "user,project,local",
              "--add-dir", r["checkout"], "--add-dir", r["scratch"], "--output-format", "json"]
    if arm == "lane":
        sets = {"env": {"CLAUDE_CODE_DISABLE_BACKGROUND_TASKS": "1", "BASH_DEFAULT_TIMEOUT_MS": r["bash_ms"], "BASH_MAX_TIMEOUT_MS": r["bash_ms"]}}
        return [*common, "--disallowedTools", DISALLOWED, "--settings", json.dumps(sets),
                "--allowedTools", r["allow"], "--max-turns", str(REVIEW_MAX_TURNS)]
    return [*common, "--disallowedTools", f"{DISALLOWED},WebFetch,WebSearch", "--allowedTools", r["allow"], "--max-turns", "150"]


def last_verdict_comment(ghdir: Path) -> str | None:
    try:
        comments = json.loads((ghdir / "comments.json").read_text())
    except (OSError, ValueError):
        return None
    bodies = [c.get("body", "") for c in comments if str(c.get("body", "")).startswith("verdict:")]
    return bodies[-1] + "\n" if bodies else None


async def review_one(case: dict, arm: str, run_no: int, work: Path, clones: Path, root: Path, bindir: Path,
                     model: str, timeout_s: int, sem, bench=None) -> dict:
    """Render, spawn the arm's session and collect what it wrote. The lane posts through the local gh; plain
    writes its verdict file."""
    async with sem:
        try:
            r = render(case, arm, work, clones, root)
        except BuildError as e:
            return {"arm": arm, "case": case["id"], "run": run_no, "status": "build-failed", "problems": [str(e)]}
        base = {"arm": arm, "case": case["id"], "run": run_no, "gates": r["gates"], "checkout": r["checkout"]}
        if r["stopped"]:
            return {**base, "status": "gate-stop"}
        sid = str(uuid.uuid4())
        env = {**os.environ}
        if arm == "lane":
            env.update(PATH=f"{bindir}{os.pathsep}{os.environ.get('PATH', '')}", GH_LOCAL_DIR=r["ghdir"],
                       SECOND_SHIFT_CONFIG=str(Path(r["scratch"]) / "second-shift.config.json"))
        out_path, err_path = Path(r["state"]) / "session.stdout", Path(r["state"]) / "session.stderr"
        base.update(session_stdout=str(out_path), session_stderr=str(err_path))
        started = dt.datetime.now(dt.timezone.utc)
        # The prompt is the session's stdin file, as run.sh gives it: `claude -p` waits only 3 s for piped
        # stdin, and under a full run's load a pipe written after the spawn can miss that.
        with Path(r["prompt"]).open("rb") as in_f, out_path.open("wb") as out_f, err_path.open("wb") as err_f:
            proc = await asyncio.create_subprocess_exec(
                *session_args(arm, r, sid, model), stdin=in_f, stdout=out_f, stderr=err_f,
                cwd=r["checkout"], env=env)
            try:
                await asyncio.wait_for(proc.wait(), timeout_s)
            except asyncio.TimeoutError:
                proc.kill()
                await proc.wait()
                return {**base, "status": "timeout", "session": sid}
        stdout = out_path.read_bytes()
        wall = round((dt.datetime.now(dt.timezone.utc) - started).total_seconds())
        envelope = {}
        if bench:
            text, envelope = bench.kit.extract_result_text(stdout)
            bench.kit.check_rate_limit(text, f"{arm}/{case['id']}")
            if "session limit" in text or "usage limit" in text:
                raise bench.kit.RateLimitedError(f"session limit in {arm}/{case['id']}: {text[:120]!r}")
        else:
            try:
                envelope = json.loads(stdout.decode(errors="replace").strip() or "{}")
            except ValueError:
                envelope = {}
        co = Path(r["checkout"])
        dirt = [l for l in git(["status", "--porcelain", "--ignored=no"], cwd=co).splitlines() if not l.startswith("?? .claude/")]
        if arm == "lane":
            text = last_verdict_comment(Path(r["ghdir"]))
            rec = collect(arm, text, co / record_rel(case), Path(r["scratch"]) / "record-at-first.md")
        else:
            out = Path(r["out"])
            rec = collect(arm, out.read_text() if out.exists() else None, None, None)
        viol = bench.blindness_violations(sid, root, Path(r["scratch"]), LANE_BLIND_RE if arm == "lane" else bench.BLIND_RE) if bench else []
        if dirt:
            rec["status"] = "modified-checkout"
        elif viol:
            rec["status"] = "voided-blindness"
        return {**base, **rec, "session": sid, "wall_s": wall, "cost_usd": envelope.get("total_cost_usd"),
                "num_turns": envelope.get("num_turns"), "violations": viol, "dirt": dirt[:20],
                "resolved_model": bench.resolved_model(envelope, model) if bench else model}


# --- the operator's recipe -------------------------------------------------------------------

def select_cases(cases: list[dict], ids: list[str], pilot: bool, pilot_ids: frozenset = PILOT) -> list[dict]:
    """The cases a run reviews: the pilot cases under --pilot, every other case without it, then --case."""
    wrong = sorted(i for i in set(ids) if (i in pilot_ids) != pilot)
    if wrong:
        raise ValueError(f"--case {', '.join(wrong)}: " + ("not a pilot case, and --pilot reviews only pilot cases" if pilot
                                                          else "a pilot case, which only --pilot reviews"))
    return [c for c in cases if (c["id"] in pilot_ids) == pilot and (not ids or c["id"] in ids)]


def run_arms(arms: list[str], pilot: bool) -> list[str]:
    if not pilot:
        return arms
    if "lane" in arms:
        raise ValueError("--pilot reviews with the plain arm only; drop --arm lane")
    return ["plain"]


def writes_row(no_record: bool, pilot: bool) -> bool:
    return not (no_record or pilot)


async def run_recipe(args, bench) -> None:
    root = Path(args.root)
    problems = check_corpus(root)[0]
    if problems:
        sys.exit("[planted] the corpus does not pass its check:\n  " + "\n  ".join(problems))
    try:
        cases = select_cases(load_cases(root), args.case, args.pilot)
    except ValueError as e:
        sys.exit(f"[planted] {e}")
    cache = Path(args.cache_dir).expanduser()
    started = dt.datetime.now(dt.timezone.utc)
    stamp = started.strftime("%Y%m%dT%H%M%SZ")
    work_root = cache / "runs" / stamp
    clones = cache / "bases"
    cfg = {"data": BENCH_DIR / "data", "cache": cache, "judge_prompt": (BENCH_DIR / "data" / "judge-prompt.md").read_text(),
           "judge_model": args.judge_model, "judge_timeout_s": args.judge_timeout_s}
    judge_sem = asyncio.Semaphore(args.judge_concurrency)
    print("[planted] calibrating the judge on the bench's dev set", flush=True)
    cal = await bench.calibrate(cfg, bench.load_prs(cfg["data"], "dev"), judge_sem)
    print(f"[planted] judge agreement with the published verdicts: {cal['agree']}/{cal['total']} = {cal['agreement']:.0%}", flush=True)
    if cal["agreement"] < args.min_agreement:
        sys.exit(f"[planted] judge agreement below {args.min_agreement:.0%}; no arm is reported")
    judge_fams = {bench.family(j) for j in cal["judge_resolved"]}
    sha = git(["rev-parse", "--short=7", "HEAD"], cwd=HERE)
    records: list[dict] = []
    if args.rescore:
        prior = json.loads(Path(args.rescore).read_text())
        sha = prior.get("sha") or args.sha or sys.exit(f"[planted] --rescore: {args.rescore} names no sha; pass --sha <the reviewed commit>")
        held = {c["id"] for c in cases}
        records = [r for r in prior["records"] if r["arm"] in args.arm and r["case"] in held]
        left = sum(1 for r in prior["records"] if r["arm"] in args.arm and r["case"] not in held)
        if left:
            print(f"[planted] --rescore: {left} record(s) name a case outside this run's cases and are left out", flush=True)
        ids = {r["case"] for r in records}
        cases = [c for c in cases if c["id"] in ids]
        for arm in sorted({r["arm"] for r in records}):
            print(f"\n=== arm {arm}: rescored from {Path(args.rescore).name} ===", flush=True)
    by_id = {c["id"]: c for c in cases}
    bindir = install_gh(work_root / "bin")
    sem = asyncio.Semaphore(args.concurrency)
    for arm in ([] if args.rescore else args.arm):
        print(f"\n=== arm {arm}: {len(cases)} cases x {args.runs} runs ===", flush=True)
        records += await asyncio.gather(*(
            review_one(c, arm, n, work_root / arm / f"{c['id']}-{n}", clones, root, bindir, args.reviewer_model,
                       args.reviewer_timeout_s, sem, bench)
            for c in cases for n in range(1, args.runs + 1)))
        write_results(cache, stamp, {"records": records, "calibration": cal, "sha": sha})
    rev_fams = {bench.family(r["resolved_model"]) for r in records if r.get("resolved_model")}
    if rev_fams & judge_fams and not args.allow_same_family:
        sys.exit(f"[planted] judge family {judge_fams} equals reviewer family {rev_fams}; set JUDGE_MODEL to the other family")

    async def judge(golden, cand):
        v = await bench.judge_pair(cfg, golden, cand, judge_sem)
        if v.get("error"):
            raise JudgeFailed(v.get("reasoning") or "the judge returned no verdict")
        return v["match"]

    results = write_results(cache, stamp, {"records": records, "calibration": cal, "sha": sha})
    try:
        await score_records(by_id, records, judge)
    except JudgeFailed as e:
        again = "--pilot --arm plain" if args.pilot else "--arm plain --arm lane"
        sys.exit(f"[planted] a judge call failed ({e}); no row is written. The reviews are kept: "
                 f"re-judge them with `planted.py run --rescore {results} {again}`")
    arms = tally(by_id, records)
    g = gate(arms)
    print("\n" + report(by_id, arms, g), flush=True)
    out = write_results(cache, stamp, {"records": records, "calibration": cal, "arms": arms, "gate": g, "sha": sha})
    for arm, runs in sorted(arms.items()):
        cl = [run["classes"] for run in runs.values()]
        segs = [f"mode=planted", f"agent={arm}", f"sha={sha}",
                f"model={'+'.join(sorted({r['resolved_model'] for r in records if r['arm'] == arm and r.get('resolved_model')})) or args.reviewer_model}",
                f"judge={'+'.join(cal['judge_resolved']) or args.judge_model}", f"cases={len(cases)}", f"runs={len(runs)}",
                "net=" + ",".join(str(r["net"]) for r in runs.values()),
                "gate_net=" + ",".join(str(r["gate_net"]) for r in runs.values()),
                "p1_net=" + ",".join(str(r["p1_net"]) for r in runs.values())]
        for c in (*CLASSES, CONTROL):
            tot = {k: sum(x[c][k] for x in cl) for k in ("n", "right", "wrong", "harm", "noise", "unscorable")}
            segs.append(f"{c}=" + (f"harm {tot['harm']}/{tot['n']}" if c == CONTROL else
                                   f"right {tot['right']} wrong {tot['wrong']} noise {tot['noise']} of {tot['n']}") + f", unscorable {tot['unscorable']}")
        segs += [f"calib={cal['agreement']:.0%}", f"wall={max(r['wall_s'] for r in runs.values())}s",
                 f"cost=${sum(r['cost_usd'] for r in runs.values()):.2f}", f"note=\"{args.note}\""]
        line = bench.kit.changelog_row(started, segs)
        if writes_row(args.no_record, args.pilot):
            bench.kit.append_changelog(root / "changelog.md", line)
        print(line.strip())
    if g:
        line = bench.kit.changelog_row(started, [
            "mode=planted", f"gate={'pass' if g['pass'] else 'fail'}", f"lane_worst={g['lane_worst']}", f"plain_best={g['plain_best']}",
            f"lane_worst_p1={g['lane_worst_p1']}", f"plain_best_p1={g['plain_best_p1']}",
            f"runs=lane {g['runs']['lane']}, plain {g['runs']['plain']}", f"note=\"{args.note}\""])
        if writes_row(args.no_record, args.pilot):
            bench.kit.append_changelog(root / "changelog.md", line)
        print(line.strip())
    if args.pilot:
        print(f"\n[planted] a pilot run writes no changelog row; read it per case with `planted.py cases {out}`")
    print(f"\n[planted] wrote {out}")


def write_results(cache: Path, stamp: str, doc: dict) -> Path:
    out = cache / f"planted-results-{stamp}.json"
    out.write_text(json.dumps(doc, indent=1, default=str))
    return out


# --- the subcommands -------------------------------------------------------------------------

def cmd_check(args) -> int:
    problems, counts, patterns, pilot = check_corpus(Path(args.root))
    for p in problems:
        print(f"check: {p}")
    if problems:
        return 1
    if not PLAN_COVERAGE.is_file():
        print(f"check: the runner cases' plan tags were not read: {PLAN_COVERAGE} is absent", file=sys.stderr)
    print("check: ok (" + ", ".join(f"{c} {n}" for c, n in counts.items()) + "; P4 patterns: "
          + ", ".join(f"{p} {n}" for p, n in patterns.items()) + ")")
    print(f"check: pilot {sum(pilot.values())} P4 (" + ", ".join(f"{p} {n}" for p, n in pilot.items()) + ")")
    return 0


def find_case(root: Path, cid: str) -> dict:
    d = root / "cases" / cid
    if not (d / "case.json").is_file():
        sys.exit(f"[planted] no case {cid} under {root / 'cases'}")
    return load_case(d)


def cmd_render(args) -> int:
    root = Path(args.root)
    out = render(find_case(root, args.case), args.arm, Path(args.dest), Path(args.clones), root)
    if args.arm == "lane":
        install_gh(Path(args.dest) / "bin")
        out["bin"] = str(Path(args.dest) / "bin")
    print(json.dumps(out, indent=1))
    return 0


def cmd_review(args) -> int:
    root, dest = Path(args.root), Path(args.dest)
    bench = None if args.no_bench else load_bench()
    rec = asyncio.run(review_one(find_case(root, args.case), args.arm, 1, dest / "work", Path(args.clones), root,
                                 install_gh(dest / "bin"), args.reviewer_model, args.reviewer_timeout_s, asyncio.Semaphore(1), bench))
    print(json.dumps(rec, indent=1, default=str))
    return 0


def cmd_score(args) -> int:
    root = Path(args.root)
    cases = {c["id"]: c for c in load_cases(root)}
    canned = {(j["golden"], j["candidate"]): bool(j["match"]) for j in json.loads(Path(args.judge).read_text())}
    calls = []

    async def judge(golden, cand):
        calls.append([golden, cand])
        return canned.get((golden, cand), False)

    records = []
    for r in json.loads(Path(args.reviews).read_text()):
        case = cases[r["case"]]
        if r.get("status") == "gate-stop":
            records.append(dict(r))
            continue
        rec_path = case["dir"] / "record.md"
        records.append({**r, **collect(r["arm"], r.get("text"), rec_path, rec_path)})
    asyncio.run(score_records(cases, records, judge))
    arms = tally(cases, records)
    g = gate(arms)
    print(json.dumps({"records": [{k: r.get(k) for k in ("arm", "case", "run", "status", "problems", "findings", "score")} for r in records],
                      "arms": arms, "gate": g, "judge_calls": calls}, indent=1))
    print(report(cases, arms, g), file=sys.stderr)
    return 0


def cmd_cases(args) -> int:
    print(case_report(json.loads(Path(args.results).read_text()).get("records") or [], args.case))
    return 0


def stop_problem(case: dict, b: dict) -> str:
    """Why the lane's stop is not the case's expected one: a stop on fails-without-the-change whose every red
    is a tagged test of a truth file passing on the record commit's tree. Empty when it is."""
    g = b["gates"]
    if not b["stopped"]:
        return "the lane did not stop"
    if g.get("plan_coverage") != 0:
        return f"the lane stopped on plan coverage (exit {g.get('plan_coverage')})"
    if g.get("fails_without_change") != 1:
        return f"fails without the change exited {g.get('fails_without_change')}"
    log = Path(b["state"]) / "fails-without-1.log"
    reds = [l for l in log.read_text().splitlines() if l.startswith("RED: ")] if log.is_file() else []
    if not reds:
        return f"{log} holds no RED line"
    files = {loc.get("file") for loc in case["truth"].get("locations") or []}
    for line in reds:
        m = STOP_RED_RE.match(line)
        if not m or m[1] not in files:
            return f"a red other than a tagged test of a truth file passing on the record commit's tree: {line[:300]}"
    return ""


def cmd_verify(args) -> int:
    """Both arms of every case, built and rendered with no model: the lane's gates, a marker scan of each
    rendered prompt, and each ground-truth range as the head and the base hold it."""
    root = Path(args.root)
    rc = 0
    for case in load_cases(root):
        if args.case and case["id"] not in args.case:
            continue
        truth = case["truth"]
        try:
            r = {arm: render(case, arm, Path(args.dest) / case["id"] / arm, Path(args.clones), root) for arm in ARMS}
        except BuildError as e:
            print(f"{case['id']}: BUILD FAILED: {e}")
            rc = 1
            continue
        b = r["lane"]
        print(f"=== {case['id']} {case['instance']} {truth['class']}: {truth.get('description', '')}")
        print(f"gates: {' '.join(f'{k}={v}' for k, v in b['gates'].items())}{' — STOPPED' if b['stopped'] else ''}")
        for arm in ARMS:
            p = Path(r[arm]["prompt"])
            hits = markers_in(p.read_text(), truth if truth["class"] != CONTROL else None) if p.exists() else []
            if hits:
                print(f"{arm} prompt carries a marker: {', '.join(hits)}")
                rc = 1
        if case.get("expect_stop"):
            why = stop_problem(case, b)
            print(f"expected stop {case['expect_stop']}: {'NOT met — ' + why if why else 'met'}")
            if why:
                rc = 1
        elif b["stopped"] or (b["gates"].get("plan_coverage") not in (0, None)):
            rc = 1
        for loc in truth.get("locations") or []:
            rev = b["head"] if loc["side"] == "head" else b["base"]
            if path_level(loc):
                held = git(["ls-tree", "--name-only", rev, "--", loc["file"]], cwd=Path(b["checkout"]), check=False)
                print(f"--- {loc['side']} {loc['file']}, the whole file{'' if held else ', which the ' + loc['side'] + ' does not hold'}")
                continue
            text = git(["show", f"{rev}:{loc['file']}"], cwd=Path(b["checkout"]), check=False).split("\n")
            print(f"--- {loc['side']} {loc['file']}:{loc['start']}-{loc['end']}")
            for n in range(loc["start"], loc["end"] + 1):
                print(f"{n:>5} {text[n - 1] if n <= len(text) else '<past the end of the file>'}")
    return rc


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=str(HERE), help="the corpus root: cases/, overlays/, arms/, NOTICE")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check")
    cache_default = os.path.join(os.environ.get("XDG_CACHE_HOME", "~/.cache"), "second-shift", "code-review-bench")
    for name in ("render", "review"):
        s = sub.add_parser(name)
        s.add_argument("--case", required=True)
        s.add_argument("--arm", choices=ARMS, required=True)
        s.add_argument("--dest", required=True)
        s.add_argument("--clones", default=os.path.expanduser(os.path.join(cache_default, "bases")))
        if name == "review":
            s.add_argument("--reviewer-model", default=os.environ.get("REVIEWER_MODEL"))
            s.add_argument("--reviewer-timeout-s", type=int, default=REVIEW_TIMEOUT_S)
            s.add_argument("--no-bench", action="store_true", help="skip the transcript scan and the rate-limit check")
    s = sub.add_parser("score")
    s.add_argument("--reviews", required=True)
    s.add_argument("--judge", required=True, help="canned judge answers: [{golden, candidate, match}]")
    s = sub.add_parser("verify")
    s.add_argument("--dest", required=True)
    s.add_argument("--case", action="append", default=[])
    s.add_argument("--clones", default=os.path.expanduser(os.path.join(cache_default, "bases")))
    s = sub.add_parser("run")
    s.add_argument("--arm", action="append", choices=ARMS, default=[])
    s.add_argument("--case", action="append", default=[], help="restrict to these case ids; repeatable")
    s.add_argument("--runs", type=int, default=3)
    s.add_argument("--concurrency", type=int, default=3)
    s.add_argument("--judge-concurrency", type=int, default=8)
    s.add_argument("--reviewer-model", default=os.environ.get("REVIEWER_MODEL"))
    s.add_argument("--judge-model", default=os.environ.get("JUDGE_MODEL"))
    s.add_argument("--allow-same-family", action="store_true")
    s.add_argument("--min-agreement", type=float, default=0.90)
    s.add_argument("--reviewer-timeout-s", type=int, default=REVIEW_TIMEOUT_S)
    s.add_argument("--judge-timeout-s", type=int, default=180)
    s.add_argument("--no-record", action="store_true")
    s.add_argument("--note", default="baseline")
    s.add_argument("--rescore", help="a planted-results-*.json: re-judge its stored reviews; no review is spawned")
    s.add_argument("--sha", help="with --rescore, the reviewed commit when the results file names none")
    s.add_argument("--pilot", action="store_true", help="review only the pilot cases, with the plain arm; no changelog row")
    s.add_argument("--cache-dir", default=cache_default)
    s = sub.add_parser("cases")
    s.add_argument("results", help="a planted-results-*.json")
    s.add_argument("--case", action="append", default=[], help="a case id the right rate covers; repeatable; default every case")
    args = ap.parse_args()
    if args.cmd == "check":
        return cmd_check(args)
    if args.cmd == "cases":
        return cmd_cases(args)
    if args.cmd == "render":
        return cmd_render(args)
    if args.cmd == "review":
        if not args.reviewer_model:
            sys.exit("[planted] REVIEWER_MODEL is required")
        return cmd_review(args)
    if args.cmd == "score":
        return cmd_score(args)
    if args.cmd == "verify":
        return cmd_verify(args)
    for m, name in ((args.reviewer_model, "REVIEWER_MODEL"), (args.judge_model, "JUDGE_MODEL")):
        if not m or not m.strip():
            sys.exit(f"[planted] {name} is empty")
    try:
        args.arm = run_arms(args.arm, args.pilot)
    except ValueError as e:
        sys.exit(f"[planted] {e}")
    if not args.arm:
        sys.exit("[planted] name at least one --arm")
    bench = load_bench()
    try:
        asyncio.run(run_recipe(args, bench))
    except bench.kit.RateLimitedError as e:
        sys.exit(f"[planted] {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
