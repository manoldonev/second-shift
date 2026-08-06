# lean review verdict — #423

verdict=needs-work
run_id: review-423-1
session_id: 0457b055-aab0-43bd-ac2f-18bde612e6be
rounds: 1
pr: #428
reviewed_head: a6961e810a06e9dcc8de3f48dfb0d792b5e60056
reviewed_patch_id: fd2c5c480c8b0dfaaae1043fcabbb0f9897106ed
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

# Review round 1 — PR #428 (issue #423)

Range read: `a2b158f..HEAD` — the whole branch diff (chain root, nothing to inherit).
Panel: security, performance, maintainability, complexity, test-coverage,
scope-completeness — all six returned live, none dark.

**Verdict: needs-work.** One blocker: the suite does not cover AC-1's blockers-exclusion
clause, and the gap is demonstrable rather than theoretical. Everything else in the diff is
correct and well-argued; the code itself does not touch `blockers`.

## Blocker

**B1 — `plugins/second-shift/templates/consumer/second-shift-unclaim-selftest.sh`: AC-1's
"`.tracker.labels.blockers` is **not** touched" has no killer in the suite, so AC-8 is
unsatisfied.**

AC-8 requires the selftest to cover every arm of AC-1 through AC-4. AC-1's final sentence is
an arm — the negative one, and the one D-1 spent its longest paragraph justifying. No
assertion can fail on it, because **no fixture issue carries a blockers-vocabulary label**.

Probed on a copy of the tool, never in the reviewed tree:

| mutant added to `second-shift-unclaim.sh` | suite result |
| --- | --- |
| `release_one "needs-spec-work" \|\| FAILED=1` | **0 failure(s) — SURVIVED** |
| `for b in epic needs-intake-review needs-spec-work needs-plan-review; do release_one "$b" \|\| FAILED=1; done` | **0 failure(s) — SURVIVED** |
| `release_one "bug" \|\| FAILED=1` (a label the fixtures *do* carry) | 2 red: `C7 … exactly one api call, and not a DELETE`, `C8 … exactly one DELETE` |

The third row is what makes this a fixture gap and not an un-failable assertion: the
machinery already reds correctly the moment the over-stripped label is one the stub returns.
So this is not the class C11 was deleted for — a killer demonstrably exists, the suite just
cannot see it.

Remedy is small: put a blockers-vocabulary label into a fixture (e.g.
`CARRIES_BOTH_DEFAULT` gaining `{"name":"epic"}`) and assert no DELETE targets it. Re-probe
with the two surviving mutants above and confirm each now reds.

Why this is a blocker and not a nit: the whole of D-1's reasoning is that the blockers list
is consumer-redefinable and must never be stripped, and a regression that starts stripping it
ships green today. The PR's own evidence section claims 28/28 killed and that every assertion
was probed — that claim holds for every assertion that exists; the gap is a requirement with
no assertion at all.

## Warnings (not blocking)

**W1 — the two unclaim workflow YAMLs are an unguarded copy pair, and nothing records the
decision.** `.github/workflows/unclaim-on-close.yml` and
`plugins/second-shift/templates/consumer/second-shift-unclaim.yml` carry byte-identical
`on:` trigger, `permissions:` block and `env:` block; they differ only in `name:`, the
checkout pin (v5 / v4, matching existing precedent) and the invoked script path. D-10
correctly removed the wiring greps, but the PR body's "no copy pair needing a
`lockstep-manifest.tsv` row" reasons about the *script*, which genuinely has one copy — it
does not address the YAML pair, which is new with this PR and is the first template workflow
with a near-twin under `.github/workflows/`. CLAUDE.md routes exactly this case to the
manifest, and a `verbatim` row over the three shared blocks is available; a **DROPPED** note
with the reasoning is the cheaper alternative. Either makes the decision visible. Not a
blocker: no AC requires it, and the drift is second-order.

**W2 — `[Maintainability, confidence 82]` both YAMLs name the step `release the claimed
label`, but two labels are released.** `.github/workflows/unclaim-on-close.yml:46` and
`plugins/second-shift/templates/consumer/second-shift-unclaim.yml:39`, plus the comment above
each. The script's own header is explicit ("WHICH LABELS. The two RUN-STATE roles, claimed
and queue"), so the step name is the only place that still reads single-label.

## Suggestion

**S1 — `second-shift-unclaim.sh:108` reads labels unpaginated.** `gh api
repos/{owner}/{repo}/issues/$ISSUE/labels` returns the first page (30) only, so on an issue
carrying more than 30 labels a run-state label on page 2 reads as absent and is silently not
released. Not realistic for this repo; `--paginate` would close it outright.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | Both roles resolved, defaults `in-progress` / `ready-for-dev`, `blockers` untouched in code; seam is `${SECOND_SHIFT_CONFIG:-…}` / `${SECOND_SHIFT_REPO_ROOT:-$(git rev-parse --show-toplevel)}` as specified. Absent/keyless/unparseable config all fall through — C2/C3/C4, and my wrong-literal mutants on each default red 4 and 6 assertions. |
| AC-2 | satisfied | Three arms exit 0 with zero calls and a named arm (C5/C6/C7). Falsifying either arm's condition reds its case. Labels read once at `unclaim.sh:108`, before any write. |
| AC-3 | satisfied | `jq -rn --arg s … '$s\|@uri'` at `unclaim.sh:123`; C9 pins encoded-and-never-raw. Replacing `encoded` with the raw label reds 9 assertions. |
| AC-4 | satisfied | 404 tolerance (dropping it reds C10 twice); other failures exit 1 (C11); worst-wins — dropping either `\|\| FAILED=1` reds 7; read failure exits 1 (flipping it to `exit 0` reds C13); usage exits 2 (flipping to 0 reds C14+C15). |
| AC-5 | satisfied | `issues: [closed]`, `permissions: {contents: read, issues: write}`, `GH_TOKEN: ${{ github.token }}`, checkout, template script run in place, issue number env-borne — no `${{ }}` in the `run:` body. |
| AC-6 | satisfied | Same trigger/permissions/token/env discipline; calls `.claude/tools/second-shift-unclaim.sh`. |
| AC-7 | satisfied | One question at Step 3 item 9 — no second prompt; Step 7 item 3 copies both verbatim (source is `100755`, matching `second-shift-ci-check.sh`); Step 8 item 6 lists the pair; the write boundary and the read-and-write requirement are both stated; non-github skips the unclaim half. |
| **AC-8** | **unsatisfied** | Hermetic, `gh` stubbed on PATH recording argv, per-label failure control, argv **and** exit-code assertions, zero YAML greps — all hold. AC-1's blockers arm is uncovered (B1). |
| AC-9 | satisfied | `run-lean/SKILL.md` step 9 no longer instructs the drop and names where it now happens; file is 42 lines against the 60-line cap. Schema descriptions rewritten with no `configVersion` change. Both `SECOND-SHIFT.md` copies plus `docs/onboarding.md` and `docs/team-rollout.md` updated. |
| AC-10 | satisfied | `.claude/prose-budget.baseline.tsv` is not in the diff at all, so nothing was regenerated. `--report` gives **19 FAIL at `a2b158f` and 19 on this branch**; both touched rows were already FAIL at base (`run-lean/SKILL.md` 972→1000, `onboard/SKILL.md` 3187→3431). No row this change introduced is over budget. |
| AC-11 | satisfied | `unclaim.sh:73-79` — says this repo runs on the jq defaults because its config is gitignored, and names the symptom (the stale label, on the next close). |
| AC-12 | satisfied | PR body's OR-1 section: unverified, why it cannot be verified pre-merge, the post-merge verification step, and the `pull_request: [closed]` reversal. |
| AC-13 | satisfied | `check-workflows-selftest.sh` walks `plugins/second-shift/templates/consumer/*.yml`; run here: **7 ok, 0 failed**. |

Design fidelity: **not-applicable** — the spec has no `## Design` section and arms no `RS-n`
render states.

## Verification I ran, from this checkout

- Full selftest sweep, `-P 4`, **without** `SKIP_STRESS`, `CLAUDE_CODE_SESSION_ID` unset —
  `rc=0`, zero `✗`.
- `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh`, `jq empty` over every `*.json` —
  both clean.
- `second-shift-unclaim-selftest.sh` — 25/25 green.
- `check-workflows-selftest.sh` — 7 ok, 0 failed.
- Diff-scoped mutation sweep, `--mode pr --base a2b158f`, re-run with
  `MUTATION_SWEEP_CACHE=0` so no verdict was inherited from the build session:
  `applied=8 killed=8 survived=0`.
- 17 hand-built mutants beyond the sweep's operator set, on a copy of the tool: 16 killed,
  1 survivor — B1.

**CI has produced zero check runs for this branch** (0 check-runs on all four commits;
`mergeStateStatus: BLOCKED`). That is the GitHub Actions major outage, not a defect in this
PR — the repo has created no run of any kind since 2026-08-06T20:27Z, and the PR opened at
21:15Z. It does mean nothing here has been observed in the canonical `ubuntu-latest`
environment, so the local runs above are the only evidence, and the local mutation sweep
prints its own ADVISORY banner for that reason. The next round should read CI once Actions
recovers.

## Strengths

- The assertion pruning is the real work in this diff and it is honest: three rounds of it,
  with the deleted cases named and the reason each was un-failable given (`C11` unreachable
  with an empty read body; the folded `C14` pair staying green through the very mutant it
  existed to catch). That is the discipline the repo asks for, applied against the author's
  own tests.
- `C17` is the case that matters most and the one easiest to omit — both env seams unset,
  inside a throwaway git repo, so the two `${VAR:-…}` default expansions and the `rev-parse`
  fallback are exercised on the production path instead of being pinned away by every other
  case.
- Read-once-then-delete with per-label failure isolation and a worst-wins exit is the right
  shape: the common case (an issue carrying neither label) costs one call and no tolerated
  errors, and a token that can clear one label but not the other cannot report a half-cleared
  issue as done.
- Extending `check-workflows-selftest.sh` to parse the consumer templates is a genuine
  addition, not a consolation for the removed pins — it is a parse, it fails for a reason a
  diff reader would not see, and it closes a gap where a malformed template surfaced only in
  somebody else's repo.
