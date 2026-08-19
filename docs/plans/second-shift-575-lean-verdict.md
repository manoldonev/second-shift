# lean review verdict — #575

verdict=approve
run_id: review-575-1
session_id: 81c81360-25bc-4caf-ba2f-6abd0b5c5790
rounds: 1
pr: #600
reviewed_head: 262a3afc76f974b49ccfbd427feb2f45dbc0f328
reviewed_patch_id: 109764e0d3f61b3876b142e127441e71cc0c6c2c
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

## Verdict — approve (round 1)

Round 1 covered the whole branch diff (`06e48be..262a3af`, 4 files, +684/−95). No blockers.
Three warnings, all fail-open-in-principle rather than false-today; none makes a current
register row untrue and none is worth a round.

The clause does what the ticket asked and slightly more, and the widening is the good part:
because #574 fixed rows 56/61/63 by moving them into an *unchecked* class, a literal
two-arm implementation would have been born green on its own originating exhibit. D-3's
require-by-disposition / check-by-presence is what makes the guard bite on the shape that
produced it, and case `(cc)` pins that shape permanently.

### Findings

| # | Severity | Location | Finding |
| --- | --- | --- | --- |
| W1 | warning | `tools/capability-parity-check.sh:145` | The dispatch probe matches the successor's basename as a **substring**, so a `scriptPath` dispatch of `my-engine.mjs` satisfies a row claiming `engine.mjs`. Selftest `(ff)` asserts the broader contract ("a dispatch of a DIFFERENT engine does not satisfy this row") but fixtures it with `other.mjs`, a non-overlapping name, so it does not prove what its label claims. Latent only: no `.mjs` basename in `plugins/**` today is a suffix of another. |
| W2 | warning | `tools/capability-parity-check.sh:145` | An `.mjs` successor can satisfy **its own** dispatch probe: `plugins/dev-pipeline/workflows/*.mjs` is in the dispatch-site set and the successor file is not excluded from it, so an engine containing `scriptPath: "<its own basename>"` reads as reached with no caller. This follows AC-6 as written; the AC is what is loose. |
| W3 | warning | `tools/capability-parity-check.sh:228` | Comment made false by this diff: "The tab count is already known to be **exactly 3**" now sits three lines under a check that requires **4**. The code is right; the comment justifying the hand-split states the pre-#575 invariant. Untouched context line, so no CI catches it. |
| N1 | note | scope | The issue's `ported → something dispatches or executes it` arm is implemented for `.mjs` only; `.sh` / skill / agent reachability is deferred (D-6, "Out of scope") with **no follow-up issue linked**. Inert today — the register has zero `ported` rows — but nothing tracks it. |

W1 and W2 were **probed, not reasoned**: a sandbox copy of the guard went green on a row
claiming `engine.mjs` against a dispatcher naming `my-engine.mjs`, and green on a
`self.mjs` that was its own only dispatcher.

### Per-AC scoring (against the committed spec)

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — register carries a `successor` column | **satisfied** | 5 tab-separated cells, order `capability, paths, disposition, successor, note`; header documents the column, the comma-separated form and `-` as the sole none-token. The stages-file coverage clause is no longer described as live — line 53 narrates its #577 deletion, which is the honest form. |
| AC-2 — every row backfilled | **satisfied** | 37 rows: 16 `already-covered` + 6 `dropped` claiming a survivor = 22 tokens-bearing rows, 15 bare `-`. Every token resolves (guard is green on the real register). Spot-checked the mapping against each row's note: the tokens absent from their notes are all D-4 shapes — a skill/agent named by its `plugin:skill` id resolving to `SKILL.md`/agent file, or a milestone resolving to `lean-gate.sh`. No successor invented for a row that claims none. |
| AC-3 — shape lint moves to five cells | **satisfied** | `${#tabs} -ne 4` reds; the empty-cell clause now includes `successor`. Driven by `(f)` 4-field, `(g)` 6-field, `(h)` trailing-tab, `(o)` blank successor. |
| AC-4 — require by disposition | **satisfied** | `ported`/`already-covered` with `-` red; `(p)`/`(q)` both directions, `(r)` pins that `dropped` with `-` stays green so the require arm cannot quietly become universal. |
| AC-5 — check by presence | **satisfied** | Every non-`-` cell resolved token-by-token against the register's own tree root; one message per failing token. `(s)`/`(t)`/`(t2)` cover `already-covered`/`dropped`/`choreography`; `(u)` the second token; `(u2)` two messages; `(w)`/`(w2)` empty tokens; `(x)` mixed `-`; `(y)`/`(y2)` absolute and `..` rejected **on paths that do resolve**, so the rejection is proven to come from the rule. |
| AC-6 — dispatch probe for `.mjs` | **satisfied**, with W1/W2 | `(z)` green side, `(cc)` the #348 shape, `(dd)` harness-only dispatch excluded, `(ee)` prose mention, `(ff)` different engine, `(ff2)` recovery. Rooted at the register's tree with no `git` subcommand — verified by the suite running green in a plain `mktemp` sandbox. The needle/pathspec match #574's reproduce. W1/W2 are the two ways the probe can still go green for the wrong reason. |
| AC-7 — success line reports the successor work | **satisfied** | `OK — 37 capability row(s), every disposition in enum; 22 successor claim(s) resolved, 1 dispatch-probed, 15 row(s) claim none.` — byte-matches the spec's example. `(gg)` asserts the counts, which is what a silently-stopped clause could not survive. |
| AC-8 — selftest drives every new red path both ways | **satisfied** | 36 passed / 0 failed. All ten clauses AC-8 enumerates have a case, each red path has its green counterpart, and `(cc)` is the permanent #348 fixture. Re-ran the suite under stock `/bin/bash 3.2` — 36/36 — which matters here because #476 r1 found this same guard inert-and-fail-open under 3.2. |
| AC-9 — stale LIFETIME prose deleted | **satisfied** | No `STAGES_DIR` and no "coverage clause below" anywhere in the guard; the header now describes THE TWO HALVES and closes by naming #577 as the deletion. Selftest header now cites `(l)`/`(m)`, and case `(a)`'s label reads "real register is clean — shape, enum and every successor claim resolve" rather than the old stage-docs wording. |

Design fidelity: **not-applicable** — the spec has no `## Design` section and the repo
configures no `design.provider`, so there is nothing to arm and no disarm to justify.

### Re-verified on this checkout

- `tools/capability-parity-check.sh` → `OK — 37 capability row(s) … 22 successor claim(s) resolved, 1 dispatch-probed, 15 row(s) claim none.` (rc 0)
- `tools/capability-parity-check-selftest.sh` → **36 passed, 0 failed**, under both the ambient bash and stock `/bin/bash 3.2`
- `shellcheck -e SC1091,SC2015,SC2181` clean on both files
- CI on `262a3af`: `lint-and-selftests` ✅ · `selftests (macos, bash 3.2)` ✅ · `mutation-sweep-pr` ✅ · `pr-gates` ❌ — the sole failure is `[lean-evidence] ✗ no committed verdict record`, i.e. this record's own absence.
- Register liveness: `plugins/dev-pipeline/workflows/intake-review.mjs` is genuinely dispatched (`intake-toolkit/skills/decomposition-reviewer/SKILL.md`, `intake-orchestrator/SKILL.md`), so the one probed token is a real claim rather than a vacuous one.

### Coverage gaps this round

Two of six selected reviewers produced no usable result. Neither voids the round (four
returned), but both are declared rather than absorbed:

- **`test-coverage-reviewer` — dark** (`died-after-retry`: emitted no text on either attempt, turn-budget cap). Its domain is the one this PR is mostly made of, so I read `tools/capability-parity-check-selftest.sh` end to end myself, ran it on two bash versions, and probed the two fail-open holes above by hand.
- **`scope-completeness-reviewer` — dark in substance.** It returned `request-changes` with a single blocker whose own description reads *"Interim block; classification in progress"*, over nine scope items each marked *"not yet verified"*. That is an emit-deadline artifact, not a scope reading: scoring it as FAIL would report blockers nobody found, and scoring it Pass would certify a gate that never ran. I did the scope check in-session against issue #575 instead, over its own enumerated items:

  | Item | Score |
  | --- | --- |
  | S1 gate tests a disposition's truth, not just row shape | satisfied |
  | S2 `ported` successor exists | satisfied |
  | S3 `ported` successor is dispatched/executed | **partial** — `.mjs` only; `.sh`/skill/agent reachability deferred (D-6). Zero `ported` rows exist, so nothing is live. See N1. |
  | S4 `already-covered` survivor exists | satisfied |
  | S5 `already-covered` engine's `scriptPath` dispatch resolves | satisfied |
  | S6 `dropped`/`choreography` unchanged | **exceeded** — both are checked by presence (D-3), deliberately and for the reason that makes this ticket work |
  | S7 `ported`/`already-covered` must name a resolvable successor | satisfied |
  | S8 the vacuous `STAGES_DIR` coverage clause is addressed | **moot, verified** — #577 (`7620251`) deleted the clause; no `STAGES_DIR` survives in the guard |
  | S9 `main` fails rows 56/61/63 | **moot, verified** — #574 flipped them to `dropped`; the exhibit is preserved as fixture `(cc)` rather than as a live red, and no AC claims otherwise |

  Both moot items are the ticket being stale by construction — it was queued strictly after
  #574 and #577, which is exactly the sequencing that makes a ticket's own text describe a
  tree that no longer exists. The spec records both (D-12, D-13) rather than discovering them.

### Not routed

`a11y-reviewer` and the design-fidelity dimension were not selected: no changed path is a
web component (`stageParams.webComponentGlobs` unset, default `apps/web/**/*.{tsx,jsx}`).
`db-reviewer`, `pipeline-reviewer` and `unit-test-mutation-reviewer` had no triggering
surface. Panel verdicts: security ✅ (0 findings, 2 self-suppressed below threshold),
performance ✅, maintainability ✅, complexity ✅.
