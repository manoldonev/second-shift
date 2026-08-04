# lean review verdict — #374

verdict=needs-work
run_id: review-374-1
session_id: 12c9d5e4-9cfd-4425-a08e-d59a30750615
rounds: 1
pr: #376
reviewed_head: 2fdf40c21b83d273b247828927c56e221ef75057
reviewed_patch_id: ce403d90ded404c5ee12bd9b7317e2f134c24d47
model: unknown

# Review round 1 — PR #376 (issue #374)

Three reporting/ordering fixes to the lean lane's gates. The mechanics are sound and the
oracles are real ones — a marker-file seam for "milestone 3's body never ran", a violation
count compared against printed lines, a word-boundary case for the region-id match. One
blocker: the diff changes the semantics of the command `SKILL.md`'s Resume section is built
on, and leaves that section saying something the diff made untrue, with no doc `AC-n`.

## Verification run (from this checkout of the PR head)

| Check | Result |
| --- | --- |
| `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh` | rc=0 |
| `jq empty` over every `*.json` | rc=0 |
| 49 `*-selftest.sh` suites, `-P 4`, **no `SKIP_STRESS`**, `env -u CLAUDE_CODE_SESSION_ID` | rc=0, 0 failures |
| `mutation-sweep.sh --mode pr --base origin/main` (advisory, local) | reproduced — see AC-12 |
| `check-changelog-trailer.sh origin/main` / `check-frozen-files.sh origin/main` | rc=0 / rc=0 |
| CI `pr-gates` | fails only on "no committed verdict record" — this record clears it |

## Findings

| # | Class | Where | Finding |
| --- | --- | --- | --- |
| B-1 | blocker | `plugins/dev-pipeline/skills/run-lean/SKILL.md` (Resume) | `all`'s pre-pass makes the documented resume instruction untrue, and no doc `AC-n` covers it |
| W-1 | warning | `lean-gate.sh:586` / `lean-gate-selftest.sh` | the new `tracker.type: jira` short-circuit in `check_pause_and_ask` is load-bearing and undriven |
| W-2 | warning | `lean-gate.sh:577` / `lean-gate-selftest.sh` (y4) | nothing pins that an **unratified** intent-gap record does *not* clear a `pause-and-ask` region |
| N-1 | note | spec AC-7 | the AC's subprocess enumeration is narrower than the pre-pass it describes |
| N-2 | note | `lean-gate.sh:568` (`pause_and_ask_ids`) | `$(NF-1)` assumes a trailing table pipe; a trailing-pipe-less GFM table fails open |
| N-3 | note | `lean-gate.sh:608-612` (`check_pause_and_ask`) | only the *first* unresolved region is reported, the ergonomic AC-3 demands of the pre-pass |

### B-1 — `all` no longer answers the question the Resume section sends operators to it with

`SKILL.md` still reads:

> ## Resume
> Re-read the progress file, `bash G all <issue>`, continue at the first unsatisfied milestone.

After this diff `all` cannot answer that whenever the verdict record is absent or reads
`needs-work` — which is its state throughout BUILD (steps 3-8) and through every fix round.
The pre-pass evaluates milestones 1 and 4 only, and milestone 4 is unsatisfiable by
construction until the review handoff lands, so `all` returns before milestones 2 and 3 are
evaluated at all.

Demonstrated on an identical fixture (spec present with an `AC-n`, no verdict record, milestone
2 genuinely unsatisfied), `main`'s gate against this branch's:

```
===== main: rc=1
    ✓ milestone-1 … ✓ milestone-2 … ✓ milestone-3: green gate
    ✗ milestone-4: no committed verdict record … (attempt 1/3)
    all: stopped at milestone-4 (rc=1)
  progress file: milestone-1 satisfied / milestone-2 satisfied / milestone-3 satisfied
                 / milestone-4 attempt
===== branch: rc=1
    ✓ milestone-1 (pre-pass) …
    ✗ milestone-4 (pre-pass): no committed verdict record …
    all: pre-pass found an already-unsatisfiable cheap assertion — stopping before milestone-3.
  progress file: (none)
```

The operator is pointed at milestone 4, which is never the first unsatisfied milestone at that
point in the lane, and the sweep records nothing.

What this is **not**: the mandated `all` call ("run it before step 9") happens after milestone 4
passes, so the pre-pass is clean there and the full progression runs — that path is unaffected.
`lean-reconcile.sh` reads only the progress file's `run_id`/`session_id` header keys, never the
`satisfied` lines, so nothing downstream breaks. The output is also self-describing ("stopping
before milestone-3"), so no one is silently misled. Losing the fix-budget attempt on `all` is
arguably a fix, not a regression — the file's own masthead names "diagnostic re-runs silently
inflate the fix-budget counter" as a hazard.

Why it is still a blocker rather than a warning: `SKILL.md`'s own non-negotiable list says
*"Doc updates are AC-scoped — a change that makes docs stale needs an explicit doc `AC-n`."*
This diff made a section of that very file stale, edited the file twice for a different AC
(AC-11), and shipped no doc `AC-n`. The rule exists for exactly the failure mode where nothing
breaks and the prose quietly stops being true. The remedy is small: amend the Resume paragraph
to say what `all` now reports before the handoff (and that milestones 2/3 are checked directly
while the verdict is outstanding), and carry it under a new doc `AC-n` — within the 60-line cap
the same way AC-11's edit was.

### W-1 — the jira short-circuit is undriven

`check_pause_and_ask` opens with `[ "$TRACKER_TYPE" = "jira" ] && return 0`. That guard is
load-bearing, not defensive: without it every jira-lane milestone-1 call would run
`gh issue view <JIRA-KEY>`, fail, and refuse — the function's failure branch prints a reason,
and a printed reason *is* the refusal. So deleting or inverting the line breaks milestone 1 for
the entire jira lane.

Every `CFG_JIRA` case in `lean-gate-selftest.sh` drives milestone **5** (plus `entry`/`claim`);
none calls milestone 1. Add one: `gate_cfg "$CFG_JIRA" … 1 "$JKEY"` against an issue fixture
carrying a `pause-and-ask` region, asserting rc=0 — proving the check is skipped rather than
merely happening not to fire.

### W-2 — the ratification bar on the intent-gap resolution arm is unpinned

`region_resolved` accepts a committed intent-gap record only when `ratified:` reads `yes`. (y4)
covers `ratified: yes`; (y2) covers the file being absent. Nothing covers the case the bar
exists for — a record present, naming the right region, reading `ratified: no`. That path is
indistinguishable from absence to every current case, so dropping the `ratified` conjunct
entirely would leave the suite green while an unratified record cleared a `pause-and-ask`
region — the inverse of the merge boundary's own `ratified: no` refusal (P9).

One fixture: write the gap file with `ratified: no`, assert rc=1 still naming `OR-1`.

### N-1 — AC-7's enumeration is narrower than the pre-pass it describes

AC-7 reads "no network call and no subprocess beyond `git`/`grep`/`jq` over committed files."
The pre-pass runs `cmd_1` and `cmd_4`, which also spawn `sed` (via `record_key`/`record_verdict`),
`head`, `wc`, `tr` and `cat` — every one of them pre-existing in `cmd_4`, which the spec's own
"What changes" mandates reusing verbatim under `PRECHECK=1`. So the AC as literally worded was
unsatisfiable by any implementation the spec permits.

I scored AC-7 **satisfied** on its binding clause — no network call, and every subprocess in the
same trivial cost class as the three named — and am recording the override rather than hiding
it. Verified directly: the pre-pass reaches no `$GH_CLI` call, and `cmd_1` under `PRECHECK=1`
skips `check_pause_and_ask`, which is the only network path milestone 1 has. Worth rewording the
AC on a future spec ("no network call and no subprocess beyond local text utilities over
committed files") so the next reader is not scoring an unsatisfiable letter.

### N-2 — `pause_and_ask_ids` assumes a trailing table pipe

`disp = $(NF-1)` lands on the disposition cell only when the row ends with `|`. GFM does not
require it; a table written `| OR-1 | Region | pause-and-ask` puts the disposition at `$NF` and
`$(NF-1)` is the Region text, so the row is silently skipped and the gate fails open. The
`interviewing-baseline` contract's canonical form does carry the trailing pipe, which is why
this is a note — but the failure direction is the unsafe one. Trimming the row and taking the
last non-empty cell would close it.

### N-3 — only the first unresolved region is reported

The `while … done <<< "$ids"` loop `return`s on the first region that fails `region_resolved`,
so an issue declaring two unresolved `pause-and-ask` regions costs two round-trips to discover
both. AC-8 is written in the singular so this is not an unmet criterion — but AC-3 asks exactly
this ergonomic of the pre-pass ("an operator fixing two cheap assertions should not need two
runs"), and the same argument applies here. Collect the reasons and emit them together.

## AC scoring

| AC | Kind | Score | Evidence |
| --- | --- | --- | --- |
| AC-1 | oracle | **satisfied** | (x1) repoints `commands.acme.test` at a `touch` marker; marker absent after a `needs-work` `all`. Proof by effect, not timing, as the AC demands. Independently reproduced. |
| AC-2 | oracle | **satisfied** | (x3) — clean pre-pass, marker present, rc=0. The green gate is not skippable via the pre-pass. |
| AC-3 | oracle | **satisfied** | (x2) — spec stripped of `AC-n` *and* verdict `needs-work`; both refusals printed from one run. |
| AC-4 | oracle | **satisfied** | (I2) — `needs-work` at a stale head: exactly 2 `✗` lines, freshness text present, all three arm-specific strings asserted absent. |
| AC-5 | oracle | **satisfied** | Preserved, which is what "still produces the refusal it does today" asks: (O1) inferred-stale, (R2) declared-stale, (R5) pinning that (R)'s records route to the SHA fallback — all green against the branch's own gate. The new short-circuit is guarded on `!= approve`, so it cannot reach them. |
| AC-6 | oracle | **satisfied** | Structural, not just fixture-deep: `note_violation()` is the single site that both prints `✗` and increments `violations`, and the summary echoes that counter. (I2) pins `2 evidence artifact(s) missing` against 2 printed lines; CI's own run on this PR shows `1` against 1. |
| AC-7 | critic | **satisfied** (letter overridden — see N-1) | No network call in the pre-pass: `cmd_4` reaches no `$GH_CLI`, and `cmd_1` under `PRECHECK=1` skips the only network path milestone 1 has. The `git`/`grep`/`jq` enumeration is narrower than the `cmd_4` body the spec mandates reusing. |
| AC-8 | oracle | **satisfied** | (y2) refuses naming `OR-1`; (y3) operator comment clears; (y3b) a Bot-authored comment does not; (y3c) `OR-10` does not satisfy `OR-1`; (y4) a ratified intent-gap record clears. |
| AC-9 | oracle | **satisfied** | (y5) — `reversible-default-and-flag` alone, rc=0. |
| AC-10 | oracle | **satisfied** | (y1), plus the fixture-wide `--issue-file` default that keeps every pre-existing milestone-1 case zero-network. |
| AC-11 | critic | **satisfied** | `SKILL.md` is 60 lines, unchanged from `main`; the two-tracker-writes rule is amended in place to name the operator's resolving comment as the third. Long lines are the file's pre-existing style (line 13 was 435 chars before this diff), so this is not cap-gaming. |
| AC-12 | oracle | **satisfied** | Reproduced from this checkout: `lean-gate.sh` 10/7/3, `check-lean-chain.sh` 12/6/6 — identical to the PR body's table, and both survivor ordinal sets match `tools/mutation-baseline.tsv` member-for-member. No re-baseline owed. |
| AC-13 | critic | **satisfied** | `check-changelog-trailer.sh origin/main` rc=0; two commits carry substantive `Changelog:` bodies, one `Changelog: none`. |

Sixteen `AC-n` references, thirteen distinct criteria, all thirteen satisfied. The blocker is
not an unmet `AC-n` — it is the lane rule the diff broke on its way past them.

## What is good here

- **(x1)'s seam is the right one.** "Milestone 3's body never ran" is exactly the assertion a
  timing-based test would fake; repointing the config's `test` command at a `touch` and
  asserting the marker's *absence* makes it observable.
- **(y3c)** — a comment naming `OR-10` must not resolve `OR-1`. That is the substring bug this
  check would otherwise have shipped with, caught in the diff that introduced it.
- **The fixture-wide `--issue-file` default**, in both `lean-gate-selftest.sh` and the
  scenario-liveness lean legs, with the argument-ordering reasoning written down (default first,
  so a caller's own flag is the later occurrence and wins). Growing `cmd_1` a network path would
  otherwise have quietly broken the "Zero network" property both suites promise.
- **AC-12 was actually done**, not asserted: the survivor sets are reported before *and* after
  the new coverage, which is the trap the AC's own closing sentence names.

## Verdict

`needs-work` — B-1. W-1 and W-2 are cheap and belong in the same round; the notes are yours to
take or leave.
