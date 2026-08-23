# lean review verdict — #636

verdict=approve
run_id: review-636-2
session_id: e6728593-4990-406f-bac0-d8e5a68ebed3
rounds: 2
pr: #654
reviewed_head: 40a957cfb493a2f08afec8d717c083eb91edeb92
reviewed_patch_id: 62a2ec85f7f0b1fccec36880dadaa26b3e17fc40
inherited_patch_id: 588e6431c7c44b4a06563069ae7e90e6f29bfbe9
inherited_from_verdict: 35e0240d661b0440feb3742eb0c08054b32c6d48
fidelity: not-applicable
model: opus
capabilities: pr-marker

## Round 2 — `approve`

**Range read:** `35e0240..40a957c` (the single fix commit), inheriting the coverage of patch `588e6431c7c4` per `G delta`. Read wider than the range: the whole of `scripts/check-gate-buckets.sh`, the register's aggregate shape, and the five corpus files, because round 1's blocker was a claim about a *denominator* and only a re-derivation can falsify one.

**Panel:** security, performance, maintainability, complexity, test-coverage, scope-completeness — all six returned, none dark. Four `approve` with zero findings; test-coverage `approve-with-nits` (1 minor, kept — see warning 1); scope-completeness **PASS** (1 minor, trigger-absent note — see nit 1).
**Not routed:** a11y + design-fidelity — no changed path matched `stageParams.webComponentGlobs` (default `apps/web/**/*.{tsx,jsx}`). `unit-test-mutation-reviewer` not selected: no co-located unit-spec surface in this repo.

**Round 1's blocker is discharged, and I verified it the way it was found rather than by reading the diff.** Re-ran the derivation: the enumerator's regex against a deliberately broader one (command-position prefix dropped entirely, `${p}[[:space:]]`) and `comm` on the two. The broad set is 323 rows against the production 306; all **17** extra rows are false, and every one was read individually — 15 are the `envfail`/`fail` suffix collision in `check-lean-chain.sh` (already enumerated under the other key), one is a primitive mentioned in a trailing comment (`lean-gate.sh:3987`), one is `launch_note terminal "…"`, the argument position `(g18c)` exists to exclude. **No live refusal site is outside the denominator at this head**, and that holds independently of the prefix, which is the strongest form the claim can take.

Two further axes checked, both costing nothing here but measured rather than assumed: the trailing boundary (`([^A-Za-z0-9_]|$)` in place of `[[:space:]]`) produces the identical 306, and no enumerated site sits behind a `#` on its own line.

**Mechanical evidence (run at this head, in a checkout of it):** guard green — **306** sites / 5 files / **156** rows, per-row hits summing to exactly **306**; bucket split 143 / 139 / 21 / 3 = 306, so the PR body's table now adds up; `check-gate-buckets-selftest.sh` PASS, **32** assertions, **3.69s** (under the sweep's 5s slow bar, so the guard stays in the PR lane); diff-scoped `mutation-sweep --mode pr` **applied=10 killed=10 survived=0**, re-run cold with `MUTATION_SWEEP_CACHE=0`; `shellcheck -e SC1091,SC2015,SC2181` clean; `check-lockstep-pairs.sh` 29 anchors, 0 failed; `check-fail-open-shapes.sh` green (13 sites); `check-guard-budget.sh` green at delta **+738** (base 50543, HEAD 51281) — the body's figure exactly. CI at this head: `lint-and-selftests` pass, `mutation-sweep-pr` pass, `selftests (macos, bash 3.2)` pass. `pr-gates` fails only on the round-1 record still reading `verdict=needs-work`, which this record replaces.

**Every figure in the PR body was checked against the tree.** 306 sites, 156 rows, the four bucket counts, 32 assertions, 3.7s, applied=10/killed=10/survived=0, delta +738, "the widening adds exactly one site and removes none" (verified: `prod \ round-1-class` = `lean-gate.sh::envfail 420`, and `round-1-class \ prod` is empty), "per-row hits now sum EXACTLY to the denominator", and the three anchor-covers-several classes (the `envfail` classes measure 133 sites over 6 rows — the body's number). Round 1's nit 4 is fully discharged.

The slice is in good shape. Two warnings, both prose-or-fixture, neither an unmet `AC-n`.

## Findings

| # | Sev | Where | Finding |
| --- | --- | --- | --- |
| 1 | Warning | `scripts/check-gate-buckets-selftest.sh:73,333` | `CMDPOS` names ten reserved words; the positive cases exercise three. Deleting the other five is invisible to the entire suite — probe-confirmed. |
| 2 | Warning | `scripts/check-gate-buckets.sh:67-71` | The residual paragraph says "Two live instances" of helper-free refusals in `operator-override.sh`. There are four of the exact shape it cites, and five more of a sibling shape. |
| 3 | Nit | `scripts/gate-buckets.tsv` | The spec's `#631` citation clause is unexercised — trigger absent on my reading too, recorded so a human can confirm it. |
| 4 | Nit | PR body / spec OR-1 | Two counts that describe the tree loosely rather than wrongly. |

### 1 — Warning: three of ten command positions are asserted, and the suite header claims all of them

`CMDPOS` (`check-gate-buckets.sh:123`) accepts `! if then elif else while until do time coproc`. The new positive fixture `cmd_2` and `(g18e)`/`(g18g)` exercise **`then`, `else`, `do`**. The other seven have no fixture line.

Probed, not inferred — a mutated copy driven through the suite's own `GATE_BUCKETS_GUARD` override:

```
CMDPOS='(^|[;&|(){}])[[:space:]]*((!|if|then|else|do)[[:space:]]+)*'   # elif/while/until/time/coproc deleted
  → check-gate-buckets-selftest: PASS (32 assertions)
  → the guard on the real tree: 306 sites, rc=0
```

All 32 assertions green, the guard green on the real corpus. The PR-lane mutation sweep does not reach it either: its operator classes on this guard are `cmp-eq`, `cmp-z`, `logic`, `detector`, `default` — none mutates a regex alternation. So a one-token deletion re-opens, for that keyword, exactly the hole #636 exists to prevent, with every signal in the lane green.

For calibration, the two cases that *do* work: reverting `CMDPOS` to the round-1 class fires `(g18e)` and `(g18g)` by name, and deleting `else` alone fires them too — while the real-tree arm `(g0)` stays **green** in both cases (305 sites, rc=0), because the class row simply covers one fewer site. Those two cases are carrying the entire recipe, and they are worth what they cost. `(g18f)` is the weak one: the mutation it reads as guarding (`[[:space:]]+` → `[[:space:]]*`) leaves it green and leaves the tree at 306, so it is a near-miss illustration rather than an assertion with kill power.

The suite header states the stronger claim the fixture does not carry: *"(g18e-g): that a legitimately placed call IS enumerated from **every position** a command may start in, including after a reserved word."* Three positions, described as every one — which is structurally the round-1 warning about self-exclusion 3, now in the selftest header instead of the guard header.

**Why this is a warning and not a blocker.** Round 1's blocker was a live site outside the denominator: the completeness claim was false about the tree as it stood. This one is not — the enumeration is provably complete at this head, and no `AC-n` obliges per-keyword fixture coverage (`AC-2`'s suite clause binds the three disagreement arms plus the green arm, and all four are cased). It is a suite-strength gap against a future edit, and it should be closed — but not by spending a round.

**Remediation, ~4 lines:** extend `cmd_2` with an `elif` arm, a `while`/`until` arm, a `! <primitive>` line and a `time` line; bump the three expected counts (`g1c`, `g14`, `g18g`); and narrow the header's "every position" to what the cases cover. Note that fixing it on this branch voids this record and costs a round — a follow-up ticket is the cheaper route, and this finding is written to be liftable into one.

### 2 — Warning: the residual class is named, but its count is off by 4x

Round 1's warning 2 was that the header's residual said nothing about refusals made through no helper. The fix names the shape, which is the part that mattered — but attaches an enumeration that does not survive a grep:

> *"a refusal made through NO helper at all — an inline `echo "..." >&2; return 2`. **Two live instances**, both in operator-override.sh (the malformed-override-block and malformed-register-row refusals)"*

There are **four** of that exact shape in that file: `:441`+`:442` and `:467`+`:468` (the two named), plus `:476` and `:477` — two `case` arms of `override_active`'s persistent-register read, each an inline `echo "…" >&2; return 2` refusing an override whose expiry has fired or could not be evaluated. Those two are refusals of more consequence than the two named, not less: they red a run at the first consumer that consults the register. A sibling shape adds **five** more in the `lint` lane (`:500`, `:506`, `:516`, `:520`, `:521` — `echo "…" >&2; v=$((v + 1))`, returned as a count).

Nothing behaves differently: `AC-3` fixes this file's primitive list at `envfail`, so all nine are outside the denominator by construction, exactly as the header says of the class. The defect is that `AC-8`'s job is to let a reader tell an excluded surface from a forgotten one, and a reader who greps finds nine where the header says two — leaving `:476`/`:477` in precisely the "considered, or missed?" state the criterion forbids. Scored as a warning rather than against `AC-8`, because the residual is stated at the level of a *shape* and the shape is correctly named; it is the parenthetical census that is wrong. Drop the count and the two-item identification, or make them accurate.

### 3 — Nit: the `#631` clause has no site, on my reading as well

The spec's Out of scope says a `gates-process` row whose consumer sits outside the lean lane cites `#631`. No row does. I read the trigger as absent, agreeing with the scope reviewer: of the three `gates-process` rows, `lean-gate.sh::fail_milestone` (`spec-open-region`, consumed by `check_pause_and_ask`) and `orchestrate-lean.sh::terminal` (`intake-unqueued`, consumed by `probe_intake`) are lane-internal and wired, and `lean-evidence.sh::note_violation` reads `unwired — <reason>`, so it asserts no reachability that could be false. Recorded rather than scored: if a future row in `lean-evidence.sh` ever names a wired yield, the citation becomes owed and nothing mechanical will ask for it.

### 4 — Nit: two loose counts

The PR body describes `orchestrate-lean.sh`'s slug-keyed class as "two calls with one slug"; one slug (`terminal verdict-progress-unreadable 1`) is reached from **four** call paths. The class reading is right, the arity is a sample. And the spec's OR-1 row reads "5 rows over 132 sites" against a measured 6 rows / 133 — the policy it states (one row per class per file) is exactly what the tree implements; `orchestrate-lean.sh` simply carries two `envfail` classes (`env-`, `usage-`). Both are informative counts under `D-6`'s reading, not binding ones, and neither is in this round's delta.

## AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | satisfied | Closed enum enforced (`g6`); anchor/yield/why non-empty-checked (`g12`, `g12b`); `not-a-gate` `why` mechanically constrained to the three forms (`g11`). "Exactly one disposition" now holds arithmetically as well: per-row hits sum to 306 against 306 distinct sites, which with a green UNCL arm proves each site is claimed exactly once. |
| AC-2 | **satisfied** (was unsatisfied) | The enumeration half is fixed. `CMDPOS` spans the whole command-start class, and I re-derived the denominator independently: with the command-position prefix dropped entirely, the broad set adds 17 rows and all 17 are false. `lean-gate.sh:420` is now enumerated and dispositioned. The three disagreement arms still red independently (`g2`/`g3`/`g4`) and `--list` checks nothing (`g14`). Finding 1 is about the suite's reach, not the recipe's. |
| AC-3 | satisfied | All five files carry their full declared primitive set; definition lines self-excluded by the file's whole set (`g18d`). Finding 2 concerns refusals with no primitive, which this AC does not reach. |
| AC-4 | satisfied | One row per site is the default; the per-row covered count is printed unconditionally (`g1b`); zero-hit rows red, split between drift and outlived (`g3`/`g4`). Round 1's finding 3 is discharged — row 67's anchor is now its own site's full text, and the sum equals the denominator exactly. |
| AC-5 | satisfied | Both directions cased (`g7`/`g8`); the vocabulary is parsed from `operator-override.sh` at run time, and an empty one is exit 2 rather than a vacuous pass (`g16`). |
| AC-6 | satisfied | `-` on a `gates-process` row reds (`g9`); `unwired — <reason>` accepted (`g10`); form only. All three `gates-process` rows carry an accepted form. |
| AC-7 | satisfied | One step in `lint-and-selftests`, beside `check-lockstep-pairs.sh` and `check-eval-model-identity.sh`; unconditional on `pull_request`; not `pr-gates`. Green in CI at this head. |
| AC-8 | satisfied | Self-exclusion 3 now describes the class it implements, and its character set and reserved-word list match `CMDPOS` token for token — round 1's complaint is discharged. The residual paragraph names both shapes a primitive-keyed enumerator cannot close. Finding 2 is its census, not its coverage; finding 1's header over-claim is in the selftest, which this AC does not reach. |
| AC-9 | satisfied | `gates-signal` added with the not-total-predicate rationale, plus the register pointer; enforcement not restated (P5). |
| AC-10 | satisfied | No corpus file edited (`git diff --name-only origin/main...HEAD` names none of the five), so no new refusal reason and no `gate-ablation-classes.tsv` row owed. `check-fail-open-shapes.sh` green, no new row. No `lean-gate.sh` call site added, so no `scenario-liveness-selftest.sh` path touched. `Guard-mass:` trailer present on the fix commit; `check-guard-budget.sh` green at +738. |

**Design fidelity:** `not-applicable` — the spec arms no `## Design` section.

**Verdict: `approve`.** No blockers. Findings 1 and 2 are worth a follow-up ticket rather than a fourth round; fixing either on this branch voids this record.
