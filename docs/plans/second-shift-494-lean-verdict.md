# lean review verdict — #494

verdict=approve
run_id: review-494-1
session_id: a1aeda51-7bd2-4590-b5a0-1ffbc94f3ca3
rounds: 1
pr: #504
reviewed_head: 8fac0bb1bfe1d6555913319f936d2fd79744eb82
reviewed_patch_id: fc5cdc40a255536204580e19649c6b7d7b504930
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Review round 1 — PR #504, issue #494

Range read: `4bc19cc..HEAD` (full branch diff — root round, nothing to inherit).
Panel: `review-lead` fan-out, 7 reviewers, **none dark**. Verdict: **approve**.

The change is small, precisely scoped, and its central claim is the one the diff actually
makes: milestone 1's `[ -f "$spec" ]` absence routes to a new `block_milestone` whose line kind
(`| milestone-1 | absent |`) cannot match the fixed string `attempt_count()` greps, while every
*content* failure in `cmd_1` — no `AC-n` (`:1735`), `design_state error` (`:1744`), the disarm
lock (`:1746`), an unresolved `pause-and-ask` (`:1752`) — still calls `fail_milestone`.

### Per-AC scoring (against the committed spec, `docs/plans/second-shift-494-lean.md`)

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 — absent vs content are distinct line kinds | **satisfied** | `lean-gate.sh:1733` `block_milestone`; the four content paths above unchanged on `fail_milestone`. Guarded by `(c3)`/`(c4)`. |
| AC-2 — absence does not increment `attempt_count()` | **satisfied** | `absent_count()` greps `\| milestone-N \| absent \|`, `attempt_count()` greps `\| milestone-N \| attempt \|`, both `-F`; neither line matches the other's pattern. `(c3)` asserts 3 absent / 0 attempts; `(c4)` asserts the full 3-attempt budget survives three absent calls. |
| AC-3 — absent kind capped at 10, 11th `rc=4` | **satisfied** | `ABSENT_BUDGET=10`; append-then-count-then-`-gt` ⇒ calls 1–10 return 1, the 11th returns 4 and records `absent-exhausted \| 11 calls`. `(c5)` drives the exact boundary. |
| AC-4 — step 3's call is free and still names the path | **satisfied** | Message is `no committed spec at $SPEC_REL`, byte-unchanged; asserted by the **pre-existing** case `(a1)`, which still passes. `SKILL.md` step 3 correctly needs no move. |
| AC-5 — selftest coverage, `(c1)` still green | **satisfied** | `(c3)` absent-lines + zero attempts, `(c4)` content failure still `1114`, `(c5)` the cap boundary, `(c6)` the `budget-exhausted` non-inflation, plus `(c7)` beyond the AC. `(c1)` — the deliberate milestone-4 control — unchanged and green. |
| AC-6 — `SKILL.md` names the second hard stop | **satisfied** | `build-lean/SKILL.md:36` now states the `absent` kind, that it spends no fix budget, and its bound of 10. Correctly carries **no** guard: CLAUDE.md forbids prose-presence greps. |
| AC-7 — composed liveness leg | **satisfied** | Leg 3c `(lean-absent)`: `all` reds, its `PRECHECK` pre-pass records **neither** kind, three direct calls give `111`/3 absent/0 attempts; then a content failure still reaches `1114` + a `budget-exhausted` terminal write + no `satisfied` line. `(lean-budget)` and `(lean-nv)` still green. |

Scope against the **issue**: the issue's AC-1..AC-5 all land; its "Out of scope: milestones 2–5"
is honored, and D-7/OR-1 records the milestone-4 deferral rather than silently taking it.
`scope-completeness-reviewer` independently returned **approve**.

### Verification evidence

CI on `8fac0bb`: `lint-and-selftests` **pass**, `mutation-sweep-pr` **pass**,
`selftests (macos, bash 3.2)` **pass**. `pr-gates` fails on exactly one assertion — the absent
verdict record this review is producing; frozen-files, changelog-trailer and pipeline-chain all
passed within it.

Locally, from this checkout of the reviewed head: `lean-gate-selftest.sh` green,
`scenario-liveness-selftest.sh` 87 passed / 0 failed, `shellcheck -e SC1091,SC2015,SC2181` clean.

**Hand probes.** The spec's D-8 states the mutation sweep cannot reach this code (`lean-gate.sh`'s
generic classes are at their 2-per-class quota above these edits), so every new assertion was
probed by hand in an isolated worktree. No survivors:

| Probe | Mutation | Killed by |
| --- | --- | --- |
| P1 | `block_milestone 1` → `fail_milestone 1` (the new catalog row's own flip) | `(b2) (c3) (c4) (c5) (c6) (c7)` |
| P2 | `ABSENT_BUDGET=10` → `11` | `(c5)` |
| P3 | `-gt` → `-ge` at the cap | `(c5)` |
| P4 | `absent-exhausted` → `absent-budget-exhausted` (D-5's trap) | `(c5) (c6) (c7)` |
| P5 | `absent_count` widened to sweep its own exhaustion lines | `(c7)` **only** |
| P6 | drop `block_milestone`'s `PRECHECK` guard | liveness `(lean-absent)` (`pre-pass absent=1`) |
| P7 | revert `count_in_progress` to the old one-liner | `(c3) (c6)` |

P5 is the notable one: it is caught by `(c7)` and nothing else, and it reproduces exactly the
defect `(c7)`'s comment predicts — the exhaustion record jumps `11 calls` → `13 calls`, skipping
12. The case earns its place. P6 confirms the `PRECHECK` half of AC-7 is non-vacuous, and P7
confirms the `count_in_progress` repair is load-bearing rather than incidental tidying: the old
`grep -cF … || echo 0` form emits `"0\n0"` on zero matches, so every new *did-not-move* assertion
would have failed with a correct-looking value for a reason unrelated to the gate.

### Findings

No blockers.

**Suggestions (non-blocking)**

- `[Unit-test mutation]` `lean-gate-selftest.sh:272` (confidence 80) — `(c6)` does not uniquely
  kill any mutant I could construct: on the D-5 rename it fires, but `(c5)`'s own
  `absent-exhausted` count assertion fails first (P4 confirms both fire together). Folding its
  assertion into `(c5)`'s `&&` chain would lose nothing. Kept non-blocking because AC-5 asks for
  the assertion explicitly and its present form satisfies that literally.
- `[Cross-cutting]` D-7's **OR-1** — milestone 4's identical `[ -f "$rec" ]` absence carries the
  same defect and is deferred with no tracker item. Once #494 closes, the deferral lives only in
  a spec file. Worth a follow-up issue so it has an owner; explicitly out of scope for this PR
  per the ticket's own "Out of scope", so it is not a blocker here.
- `lean-gate-selftest.sh:231` — the section header reads `(c3-c6)` but the block now runs
  through `(c7)`. Cosmetic.

**Pre-existing (not blocking this PR)**

- `[Unit-test mutation]` `lean-gate.sh:906` (confidence 85) — `block_milestone`'s stderr `warn`
  text (`absent N/10 — not a fix attempt`, and the exhaustion line) is not string-asserted. This
  is the established pattern, not a new gap: `fail_milestone`'s own `attempt N/3` warn is
  unasserted too. The operator-facing *reason* — the part that names the spec path — **is**
  asserted, at `(a1)`.

**Dismissed**

- `[Scope completeness]` `lean-gate.sh:1733` (confidence 95) — "uncommitted mutation probe left
  applied in the worktree". Correct observation, wrong author: that was this review session's own
  hand probe running concurrently in the shared checkout, not anything the PR contains. The
  reviewer itself scoped it right ("HEAD carries the correct `block_milestone` call, so this does
  not affect the diff under review"). Probes were moved to an isolated worktree, the checkout was
  restored, and the tree was verified byte-identical to `origin/claude/second-shift-494` before
  this record was written.

### Reviewer verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 1 (nit, dismissed) | 95 |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |
| Unit Test Mutation | Pass | 2 (minor) | 80–85 |

Not routed: `db-reviewer` (no DB layer), `pipeline-reviewer` (no async-worker surface), and
`a11y` + the design-fidelity dimension — no changed path matched
`stageParams.webComponentGlobs` (unset; resolved default `apps/web/**/*.{tsx,jsx}`) on a
shell-and-markdown diff.

Design fidelity: **not-applicable**. The spec declares `Design: none — this repo configures no
`design.provider``, and that disarm is justified: the repo's config carries no `design` key at
all, so there is no handoff, no render receipt, and no RS table to score.
