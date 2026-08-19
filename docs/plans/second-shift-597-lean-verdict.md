# lean review verdict — #597

verdict=needs-work
run_id: review-597-1
session_id: 3f4f4e7e-9bc5-4cac-9b01-0bef284a5d17
rounds: 1
pr: #601
reviewed_head: 405657aebedb7c714287a80a088793db9a3a2bc9
reviewed_patch_id: 79eb4344d6a86e76a6f74ed85ba4a9c41759db2d
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 1 (`review-597-1`), full branch diff `06e48be..405657a` — 11 files, +820/-14.
Panel: security, performance, maintainability, complexity, test-coverage,
scope-completeness (6/6 returned; none dark).

## Verdict: needs-work — one blocker, outside the AC set

The implementation is right and every AC is met. The blocker is that **this PR cannot merge
and no CI job has ever run on it.**

## Blocker

**B-1 — PR 601 is born unmergeable, so zero checks were ever queued.**
`git ls-remote origin 'refs/pull/601/*'` returns `refs/pull/601/head` and **no
`refs/pull/601/merge`** — GitHub never built the merge ref, so no `pull_request` workflow
was dispatched. `gh pr checks 601` says "no checks reported", which is the same string a
merely-early PR gives; the ls-remote is what tells them apart.

The conflict is one hunk, in `scripts/lockstep-manifest.tsv`: this branch appends the
`contribution-compare` row and comment block at EOF, and `#596` (merged into main as
`602b0f0`) appends `tier-alphabet-parse` at the same place. Adjacent-append, no semantic
overlap — a union resolution is correct.

Consequences, in order of weight:

1. **`pr-gates` has never graded this branch.** That job is the merge boundary this PR
   modifies. So has nothing else: the two selftest jobs, `mutation-sweep-pr`, the stock
   **bash-3.2 macOS lane**, and CI's shellcheck 0.9.0 (local is 0.11.0) all never ran. Every
   green in the PR body is a local claim.
2. **After the resolving merge, the lane's own milestone 4 will still red.** The scheduler
   and `build-lean` call the **installed** `lean-gate.sh` (dev-pipeline 9.0.1), which
   predates this fix. The merge boundary is fine — `pr-gates` runs the BRANCH's
   `check-lean-chain.sh` → `lean-evidence.sh`, so it gets the new tolerance — but the
   close-out's `bash G 4` does not. Same bootstrap as #363: invoke the branch's own copy,
   `bash <worktree>/plugins/dev-pipeline/skills/build-lean/lean-gate.sh 4 597`.

**Measured, not assumed — the approve would NOT have been void.** I resolved the conflict as
a union in a scratch worktree (merged head `bfe0a99`) and ran the branch's own predicate
across it:

| | value |
| --- | --- |
| patch-id at `405657a` (merge-base `06e48be`) | `79eb4344d6a8…` |
| patch-id at `bfe0a99` (merge-base `602b0f0`) | `644e041de223…` — **moved** |
| `contribution_delta(405657a → bfe0a99)` | **rc=0**, empty detail |

So the standing "a conflicting PR guarantees a void approve" rule does not apply here — this
PR is the thing that makes it not apply, and it works on itself. B-1 stands on (1) and (2),
not on void risk.

**Remedy** (one round either way): merge `origin/main`, resolve the manifest as a union, push
through `bot-commit.sh`. Round 2's `G delta` is then the merge commit alone.

## Warnings

**W-1 — the rc=2 fail-open swallows a class that is certainty, not doubt.**
`contribution_lines` returns 1 when `reviewed_head` is not a commit in the checkout, so
`contribution_delta` answers rc=2 and both callers pass. That condition has a name everywhere
else in this system: `lean-gate.sh`'s legacy arm and `check-lean-chain.sh:697` both call it
"the branch was rebased or force-pushed after the review" and refuse. Reachable at the
boundary on a modern record: `check-lean-chain.sh` guards only for an EMPTY `reviewed_head`,
then `delegate freshness` → `arm_freshness` → patch-id moved → rc=2 →
`inapplicable freshness reduced-strength` → **zero violations, `pr-gates` green**. Before this
PR that same state was a `note_violation`. `(s3)`/`(vb3)` assert it as passing, so it is
deliberate and tested — and it is squarely inside OR-1, whose default D-5 pins as
`user-answered`, which is why this is a warning and not a blocker. Worth splitting the two
cases later: "the merge-base would not resolve" is doubt; "the head the record names does not
exist here" is a known history rewrite.

**W-2 — the two new `verdict-progress-unreadable` branches have no covering case.**
`orchestrate-lean.sh:843,845` — both `progress_token` reads carry a `|| terminal
verdict-progress-unreadable 1 …` arm, and `(vr1)`/`(vr2)` only exercise the paths where both
reads succeed. New failure route, untested. (test-coverage-reviewer, confidence 80.)

## Suggestions

- **S-1** — `contribution_summary`'s `n == 0` branch prints "no affected line could be named"
  and the caller **still invalidates**, which is the inverse of AC-3/D-6 ("a path that cannot
  enumerate one does not invalidate"). Practically unreachable — git emits per-file sections
  in sorted path order, so a `cmp` difference implies some file's line list differs — and it
  errs closed. Either make it rc=2 or pin the unreachability in a comment.
- **S-2** — `contribution_lines` sees only `+`/`-` body lines, so a **mode change** (`old
  mode`/`new mode`, no hunk) and a **pure rename** produce no contribution at all. A
  post-review `chmod +x` therefore does not invalidate. Narrow, but this repo has been bitten
  by a dropped exec bit before.
- **S-3** — `arm_freshness` enters the escape hatch without checking `VERDICT_REVIEWED_HEAD`
  is non-empty. `check-lean-chain.sh` supplies that guard on the `pr-gates` path, but
  `lean-evidence.sh` is documented as separately fetchable by a consumer's CI, where it is
  the only reader. Same one-line shape as W-1.

## AC scoring — 7 / 7 satisfied

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 base advance leaves the verdict standing | satisfied | `(vb1)`, `(s2)`, `(lean-base-advance)`; plus the measured `contribution_delta` rc=0 across a real resolving merge of this very branch |
| AC-2 unmoved head spawns no REVIEW; rc=3 + m5 ends COMPLETE | satisfied | `(vr1)`/`(vr2)`; `verdict_rc`'s 3 and 2 route ahead of the spawn, and `progress_token` is `MAIN_ROOT`-anchored so it still reads after teardown — the actual F1 fix |
| AC-3 invalidation NAMES the affected lines | satisfied | `(vb2)`, `(s)` assert file + count + first offending `+`/`-` line inline. See S-1 for the unreachable `n == 0` corner |
| AC-4 compare `+`/`-` per file, each side against its own merge-base | satisfied | `contribution_lines` re-derives `merge-base("$2","$3")` per side; column-0 state machine, so `---`/`+++` headers and a removed `-- ` line are not mistaken for content. `check-lockstep-pairs.sh`: 23 pairs, 0 failed — the two copies are byte-identical |
| AC-5 regression guards reproduce the #583 sequence | satisfied | Three tiers, each with an explicit non-vacuity assertion against plain git: `(vb0)` (BOTH arms would have redded), `(s2a)`, `(vr4)`, and the composed leg's inline pid/inferred checks |
| AC-6 an uncomputable comparison stands and the line NAMES the fail-open | satisfied | `(vb3)` pins "FAILED OPEN"+"OR-1" on the declared arm; `(s3)` pins the boundary's `reduced-strength` channel. Both lines also state how to reverse it |
| AC-7 both SKILLs state the base-merge case | satisfied | `build-lean/SKILL.md` edited in place (no line growth); `review-lean/SKILL.md` +1 line, and it carries no cap — the 60-line cap is `run-lean/SKILL.md`, untouched |

## Verification run in this session (CI ran none of it)

| Check | Result |
| --- | --- |
| `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh` | rc=0 (local 0.11.0; **CI's 0.9.0 never ran**) |
| `jq empty` over every `*.json` | clean |
| `scripts/check-lockstep-pairs.sh` | 23 pairs, 0 failed — including `contribution-compare` |
| `tools/run-selftests.sh --exclude tools/install-topology-selftest.sh`, **no `SKIP_STRESS`** | **69 scored, 69 run, 0 failed**, rc=0 |
| The four touched suites, run alone and scored by case id | all rc=0; `(vb0)(vb1)(vb2)(vb3)(s)(s2a)(s2)(s3)(vr1)(vr2)(vr3)(vr4)(lean-base-advance)` all PASS |
| `/bin/bash -n` (3.2.57) on the three changed scripts | OK — syntax only; **the bash-3.2 execution lane never ran** |
| `tools/mutation-catalog.tsv` anchors on the 3 changed guards, `sed -E` as the sweep applies them, HEAD vs base | all still match — no re-anchoring obligation |
| `mutation-sweep-pr` | **never ran** — see B-1 |

## Strengths

- Every green case is paired with a non-vacuity assertion made against plain git, so a
  fixture that failed to reproduce the #583 state reds instead of reading as covered. `(vb0)`
  checks BOTH arms would have redded, which is the difference between this and a case that
  proves the arms were disabled.
- The shared predicate is one call site memoized behind `contribution_state`, so the two
  milestone-4 arms cannot answer differently — and the lockstep row makes the boundary's copy
  a checked contract rather than a hopeful duplicate.
- The comment on `contribution_lines` explains why a column-0 state machine rather than
  `/^[+-]/`, with the concrete failure (`-- ` in a markdown/shell repo). That is the kind of
  comment that survives the next edit.
- The scope discipline holds: OR-2 declines `render_patch_id` with a stated reason rather
  than widening, and the legacy SHA arm is left alone with the argument for why it is
  unreachable.
