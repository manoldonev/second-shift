# 636 — Classify every lean-lane gate as `gates-llm`, `gates-signal` or `gates-process`, with a coverage guard

Part of #605 (item 2). Routed here by #611's plan and #613's out-of-scope list.

`docs/pipeline-manifesto.md` defines the yield buckets in prose and #613 shipped the yield
mechanism. What does not exist is any statement of **which gate is which**, and nothing reds when
a new gate joins the lane unclassified. This slice adds the countable classification: a register
TSV over a shape-enumerated denominator, and a guard that reds on each way the two can disagree.

**Not** more yielding. No gate's behavior changes. Every file in the corpus is read, never edited.

## What ships

| Artifact | Role |
| --- | --- |
| `scripts/check-gate-buckets.sh` | the enumerator **and** the guard. `--list` prints the denominator and checks nothing. |
| `scripts/gate-buckets.tsv` | the register: one disposition per enumerated site. |
| `scripts/check-gate-buckets-selftest.sh` | per-tool behavioral suite — one case per red arm, plus the all-green arm. |
| `.github/workflows/ci.yml` | one step in the always-on guard job. |
| `docs/pipeline-manifesto.md` | `gates-signal` added to the bucket section, with a pointer to the register. |

## The corpus — five files

`plugins/dev-pipeline/skills/build-lean/lean-gate.sh`, `scripts/check-lean-chain.sh`,
`plugins/dev-pipeline/skills/build-lean/lean-evidence.sh`,
`plugins/dev-pipeline/tools/operator-override.sh`,
`plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh`.

`lean-evidence.sh`'s inclusion is not optional: `check-lean-chain.sh` delegates the
verdict/identity/freshness/ratification arms to it, so a register that classified the chain
script's own `fail` sites and delegated the rest would be the vacuous coverage this slice exists
to prevent.

## Acceptance Criteria

- **AC-1** — `scripts/gate-buckets.tsv` declares, for every enumerated site, exactly one
  disposition over the **closed** enum `gates-llm | gates-signal | gates-process | not-a-gate`,
  plus a text anchor, a yield cell and a `why` naming the mechanism that makes the disposition
  true. An unknown disposition is an error. A `not-a-gate` row's `why` states what the site is
  instead, over the closed set `environment refusal | usage error | success path`, checked
  mechanically.

- **AC-2** — the guard enumerates from the tree by shape and exits non-zero on each of three
  disagreements **independently**: an enumerated site no row claims; a row whose anchor matches
  nothing in its file (drift); a row covering no live enumerated site. `--list` prints the
  denominator and checks nothing. `check-gate-buckets-selftest.sh` covers each arm plus the
  all-green arm.

- **AC-3** — the enumerator names **every** refusal primitive per file rather than assuming one:
  `lean-gate.sh` → `fail_milestone`, `block_milestone`, `fail_obligation`, `ticket_refuse`,
  `envfail`; `check-lean-chain.sh` → `note_violation`, `fail`, `envfail`;
  `lean-evidence.sh` → `note_violation`, `envfail`; `operator-override.sh` → `envfail`;
  `orchestrate-lean.sh` → `terminal` (**every** call, including the exit-0 success calls, which
  are dispositioned `not-a-gate`) and `envfail`. Helper *definitions* that match the shape are
  self-excluded by name — the exclusion is by the file's whole declared primitive set, not just
  the primitive being enumerated, because `orchestrate-lean.sh`'s `envfail()` is one line that
  calls `terminal`. Every exclusion is stated in the script header.

- **AC-4** — row granularity is **one row per enumerated site**, and an anchor MAY cover several
  sites (`hits > 0`, the precedent's counting rule). The guard prints the covered-site count per
  row, so a loose anchor that would swallow a future refusal is visible rather than silent. A row
  covering zero sites reds as drift.

- **AC-5** — the safety arm is **register-internal**. A `gates-llm`, `gates-signal` or
  `not-a-gate` row MUST carry the empty yield cell `-`; a row whose yield cell names an
  `OVERRIDE_GATES` value MUST be `gates-process`. The enum is read from
  `operator-override.sh` at run time, never copied into the guard — a third copy would owe a
  lockstep marker.

- **AC-6** — every `gates-process` row's yield cell either names its
  `OVERRIDE_GATES`/`OVERRIDE_SCOPES` value or reads `unwired — <reason>`. The guard checks the
  **form**, never the existence of a follow-up ticket.

- **AC-7** — the guard runs in CI on every PR, in the always-on guard job that already runs
  `check-lockstep-pairs.sh` and `check-eval-model-identity.sh`. **Not** `pr-gates`.

- **AC-8** — the script header records the out-of-scope residual (the ~19 `scripts/`+`tools/` CI
  guards and the `.mjs` workflow gates) and every self-exclusion, plus the one residual a shape
  enumerator cannot close: a *newly named* refusal primitive in a corpus file is not enumerated
  until it is declared. A reader can tell an excluded surface from a forgotten one.

- **AC-9** — `docs/pipeline-manifesto.md`'s bucket section gains `gates-signal` and a pointer to
  the register. Per P5 the manifesto states the principle; it does not restate the enforcement.

- **AC-10** — obligations paid, each with its evidence:
  - `tools/gate-ablation-classes.tsv` — a row per **new refusal reason**. This slice adds none:
    no corpus file is edited, so no gate emits a reason it did not emit before. Evidence:
    the PR diff touches no corpus file.
  - `scripts/fail-open-sites.tsv` — the new script's own branches reconciled. Evidence:
    `check-fail-open-shapes.sh` green with no new row, or a row added.
  - `plugins/dev-pipeline/skills/build-lean/scenario-liveness-selftest.sh` — extended for every
    verdict path touched. This slice touches none: the guard is a CI step, it composes into no
    lean-gate verdict, and AC-7 settles that it is not wired into `pr-gates` or a milestone.
    Evidence: the diff adds no call site inside `lean-gate.sh`.
  - `Guard-mass:` commit trailer — the new guard and its selftest grow guard/test shell mass, so
    `scripts/check-guard-budget.sh` requires the trailer.

## Out of scope

Demoting any gate. The severity/impact axis and amendment governance (#622). Non-lane attendance
reachability (#631) — a `gates-process` row whose consumer sits outside the lean lane cites #631
rather than pretending the path works. The `scripts/`+`tools/` CI guards and the `.mjs` workflow
gates. Widening the prose census to agent contracts.

## Open Regions — resolved with their defaults, flagged here

Both were dispositioned `reversible-default-and-flag` at intake, which flags rather than pauses.

| id | region | default taken | flag |
| --- | --- | --- | --- |
| OR-1 | are `envfail` sites dispositioned individually or by one anchor per class? | one row per class per file — 5 rows over 132 sites | AC-4's covered-count print is what keeps it visible; each row's `why` names the exit-2 contract that makes the whole class an environment refusal |
| OR-2 | may a `gates-process` row stay `unwired` indefinitely? | yes, per AC-6 | only two yield values exist today and both are intake-side, so most `gates-process` rows are legitimately `unwired`; the epic owns any wiring follow-up |

## Decision Ledger

| id | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Where the register and guard live | `scripts/`, beside `check-fail-open-shapes.sh` + `fail-open-sites.tsv`, the pattern of record this slice copies. Named `gate-buckets` rather than `gate-classes` so nothing reads as a rename of `tools/gate-ablation-classes.tsv`, which the ticket states is NOT the key. Source: https://github.com/manoldonev/second-shift/issues/636 | ticket-sourced |
| D-2 | The row key | `<repo-relative-path>::<refusal-primitive>`, adopting `docs/prose-blocker-triage.tsv`'s existing `path::name` enforcer key unchanged. Settled at intake; #610 D-5's reversibility licence is not an obligation. Source: https://github.com/manoldonev/second-shift/issues/636 | ticket-sourced |
| D-3 | The empty yield cell | `-`, the repo's established empty form (`prose-blockers.sh` tests `$5 == "-"`). A literally empty TSV cell is invisible to a reader and indistinguishable from a column-count mistake. | codebase-derived |
| D-4 | Where the `OVERRIDE_GATES` enum comes from | Parsed from `operator-override.sh` at run time. Copying it would make a third copy of a value that already carries a lockstep twin in `lean-evidence.sh`, and owe a marker. | codebase-derived |
| D-5 | Enumerating `terminal` | Every call, not only the non-zero-exit ones. AC-3 requires the exit-0 calls to be enumerated and dispositioned `not-a-gate`; a shape enumerator that pre-filtered them would also hide a future refusal that reused the shape. Source: https://github.com/manoldonev/second-shift/issues/636 | ticket-sourced |
| D-6 | The stale counts in the ticket's AC-3 | The ticket measured `check-lean-chain.sh::fail` at 2 sites and `lean-gate.sh::block_milestone` at 2; the tree carries 1 of each today. AC-2/AC-4 make the guard's own `--list` output the denominator, so the counts are informative, not binding — no DEPARTURE row is owed. | codebase-derived |
| D-7 | OR-1 | Default taken: one row per `envfail` class per file. See the Open Regions table. Source: https://github.com/manoldonev/second-shift/issues/636 | ticket-sourced |
| D-8 | OR-2 | Default taken: `unwired` is indefinitely legal. See the Open Regions table. Source: https://github.com/manoldonev/second-shift/issues/636 | ticket-sourced |
