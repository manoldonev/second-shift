# lean review verdict — #490

verdict=approve
run_id: review-490-2
session_id: 94cb9db2-0acc-41be-91ee-01ab22522746
rounds: 2
pr: #491
reviewed_head: fd2450e580f1e3f7fe6b5adb5482c51ced015071
reviewed_patch_id: 5b3f87d523335b173a5bdd86105e06c38b5d52bb
inherited_patch_id: 5d1322d8980b7e41cef64a9900d0b40b164e2059
inherited_from_verdict: b83f48b17f137b9fef7deef88bb99b0b25a10413
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 2 · delta range `b83f48b..HEAD` (one commit, two files), inheriting the coverage of
patch `5d1322d8980b` per the round-1 record.

Round 1's single blocker is fixed, and fixed correctly: the committed rationale for AC-8 now
names the real collider, and I re-derived that mechanism from the source rather than taking the
record's word for it. The round also closed round 1's finding 4 — AC-8 went from a hand-run
rehearsal to a guard that reds on revert, which I probed. One warning remains, and it is
entirely in the PR body, which is now self-contradictory: its "ride along" section still states
the mechanism the same PR proves false four paragraphs later. That is a merge-boundary metadata
edit, not a commit and not a round.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | warning | PR body, `### A second, unrelated fix rides along` | The section still carries the exact mechanism round 1 falsified, verbatim: "the tool's shape-2 anchor `$HERE/../../../*/` globbing `$TMPDIR` itself" (the anchor is `$HERE/../../../*/*/agents`) and "a second instance of that same file stages its own plugin-shaped fixture as a `$TMPDIR` sibling and resolves for the first". The same body then says, under **AC-8 now has a guard that fails on revert**, that this was wrong and that the collider is `check-reviewer-references-selftest.sh` — a different suite. Both readings sit in one document, so a reader gets the false one first and unqualified. The trailing "Worth noting independently of this PR" paragraph inherits the same defect: "That divergence is what made a latent bug present as this branch's failure" is the install-topology conclusion the corrected D-7 downgrades to "merely widens the window". Fix is metadata-only — rewrite that section to match the committed D-7, which is already correct. |
| 2 | pre-existing | `orchestrate-lean.sh:86-96` | Carried forward from round 1 unchanged and untouched by this delta: a trailing value-less flag spins the parse loop (`shift 2` with `$#`=1 returns 1 without shifting). Present identically on the base branch for `--build-model`; the new flag inherits the shape rather than introducing it. Not this PR's debt. |

### What I verified rather than inherited

The corrected mechanism is not taken on trust — every load-bearing clause of the new D-7 and the
new B6 comment was re-derived from source in this checkout:

- **Shape 2's pattern.** `check-emit-deadline.sh:240` prints its own anchor as
  `$HERE/../../../*/*/agents`. From `$HERE = <mktemp>/lonely/scripts`, `$HERE/../../..` is
  `$TMPDIR`, so the glob is `$TMPDIR/*/*/agents` — any fixture one level below another suite's
  own `mktemp` root. The record's claim is exact.
- **The named collider is real and is a different suite.**
  `check-reviewer-references-selftest.sh:284` sets `QUALIFY_WRONG="$TMP/plugin-wrong-prefix"` and
  `cp -R "$FX/plugin"` into it; `fixtures/reviewer-references/plugin/` carries both
  `.claude-plugin/` and `agents/`. With `TMP=$(mktemp -d)`, that lands at
  `$TMPDIR/<tmp>/plugin-wrong-prefix/agents` — precisely shape 2's depth. So the exposure really
  is an ordinary `SELFTEST_JOBS=4` sweep, and install-topology really does only widen the window.
- **The isolation bounds the glob.** With `B6ROOT=$B6PARENT/iso`, `$HERE/../../..` resolves to
  `$B6PARENT`, whose sole child is the staged root — no `*/*/agents` match is reachable.

### Probe of the new guard (round 1's finding 4, now closed)

Run out-of-tree so the reviewed worktree stayed untouched: the whole `scripts/` dir copied to a
scratch path, with `B6ROOT="$B6PARENT/iso"` reverted to `B6ROOT="$B6PARENT"` — the exact revert
AC-8 claims B6 alone cannot catch.

- **mutant** (revert applied): `20 passed, 7 failed`. `B6c` fails with its own diagnostic —
  "the decoy resolved into B6's scan — the mktemp nesting no longer isolates it", naming
  `…/tmp.eSprNaALtx/plugin-decoy/agents`. **`B6` itself still PASSES.**
- **control** (same scratch path, line restored): `21 passed, 6 failed`. `B6c` passes.

The one case that moves between the two runs is `B6c`. The six failures common to both (B1–B5,
B8) are an artifact of running the suite outside a plugin tree and are present with and without
the mutant, so they carry no signal. This is the claim AC-8 makes, measured in both directions:
the revert reds `B6c` in a single process, with no concurrency and no rehearsal.

In the real tree, unmutated: `27 passed, 0 failed`, `B6c` included.

### Blast radius of the decoy B6c stages

Checked, because B6c deliberately creates a fixture of exactly the shape that broke B6, and it
lives until the EXIT trap fires. It is contained: only this suite invokes
`check-emit-deadline.sh`, its own B6/B6c run against the `iso`-nested root the decoy cannot
reach, later cases (B7, B9–B12) stage two or more levels below `$TMP` and are unaffected
(all green in the real-tree run), and a concurrently-running second copy of this file is
likewise `iso`-nested. `B6DECOYP` is cleaned in the extended trap at `:266`.

## AC scoring

AC-1 through AC-7 are untouched by this delta; their evidence is the round-1 record's, inherited
by reference to patch `5d1322d8980b`, and re-affirmed as still standing on this head.

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | Inherited. `--review-model-basis` parse arm, free text, no default, echoed per D-2. Round 1 probed it live: deleting the arm kills `(k1)`/`(k3)`/`(k6)`. |
| AC-2 | satisfied | Inherited. Refusal after the `[ -n "$REVIEW_MODEL" ]` check, exit 2, names the flag, interpolates the default. `if false` in its place kills `(k2)` alone. |
| AC-3 | satisfied (structurally; behaviorally unguarded) | Inherited, and the PR body states the gap plainly rather than papering it: substituting the literal `"opus"` for `REVIEW_MODEL_DEFAULT` survives the whole suite. Consistent with D-1's letter, which scopes AC-3 to the referent, not to a mutant. Recorded as a known limit, not a finding. |
| AC-4 | satisfied | Inherited. `(k5)` explicit default needs no basis; `(k6)` volunteered basis echoed; always-append kills `(k5)`, never-append kills `(k6)`. |
| AC-5 | satisfied | Inherited. `sed -n '2,62p'` window; D-6 verified in both directions — narrowing to `2,59p` and widening to `2,64p` each kill `(n)`. |
| AC-6 | satisfied | Inherited. `(k1)` carries the basis flag and still asserts `LEAN_RUN_MODEL: sonnet` reaches `spawn-2`. |
| AC-7 | satisfied | Inherited. `(k2)`–`(k6)` cover the refusal, the accepted departure, the untouched happy path, and AC-4's two claims. |
| AC-8 | satisfied | Now satisfied in full, including the clause this round added. The isolation holds (`$B6PARENT` bounds shape 2's glob, re-derived above); the same contract is still asserted; the suite is green serially and in both CI selftest jobs on this head; and the isolation is now itself guarded by `B6c`, which I probed — the revert reds `B6c` while B6 passes. The spec text was amended this round to require `B6c`, which is a **widening** at the prior round's recommendation, not a retrofit to match the diff: it adds an obligation the diff then meets, rather than deleting one it missed. |

## Also verified

- Panel: security, performance, maintainability, test-coverage, scope-completeness — **5/5
  approve, zero findings, none dark**. One suppressed note each from security (the new
  `$B6DECOYP` root is fixture-only and trap-cleaned) and scope-completeness.
- `shellcheck -e SC1091,SC2015,SC2181` clean on `check-emit-deadline-selftest.sh`.
- Mutation ordinals need no re-keying: the delta touches a *selftest* and a doc, not a guard, so
  no `${NAME:-value}` site order moved. `mutation-sweep-pr` green on `fd2450e`.
- Release hygiene: no frozen file in the delta; `fd2450e` carries `Changelog: none.`
- Round 1's finding 3 (verbless PR title deriving a patch instead of a minor) is **fixed** — the
  title now reads `feat(dev-pipeline): a downgraded review model now costs a stated reason`.
- Round 1's finding 2 (the "not fully characterised" claim) is **fixed** in the body's AC-8
  section. Finding 1 above is the part of the same body that was not brought along.
- CI on `fd2450e`: `lint-and-selftests`, `selftests (macos, bash 3.2)`, `mutation-sweep-pr` all
  green. `pr-gates` red on its **lean chain reconciliation** arm only, and only because the
  committed record still reads `verdict=needs-work` from round 1 — the arm says so in as many
  words. This record clears it.

## Before merge

Rewrite the PR body's `### A second, unrelated fix rides along` section (and the "Worth noting
independently of this PR" paragraph that follows it) to state the mechanism the committed D-7
already states. It is a body edit at the merge boundary — no commit, no new round, and it does
not touch the patch this record names.
