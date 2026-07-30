# Plan — #263: sequential sub-issues verdict + predecessor gate (PR 1 of 3 for #262)

## Context / problem framing

#262 retires the `stacked-prs` decomposition verdict: sequential decompositions become **ordered sub-issues**, serialized by tracker relationship rather than by unmerged branch stacking. This PR is step 1–2 of that epic — it lands the ordering **mechanism** and swaps the **verdict surface**. The execution-path and state-contract deletions are #265; the `{slice}` token retirement is #267.

Two halves, one PR (the operator re-consolidated 5 slices → 3 on 2026-07-30 under the decomposition-economy principle, because the gate tool alone has no consumer until the verdict swap):

- **Part 1 — the backstop.** A pure-logic `predecessor-gate.sh` extracts `Predecessor:`/`Successor:` body trailers and renders an ordering verdict. Ordering is normally enforced by *keeping blocked successors out of the queue* (#262 D-11: sequential sub-issues N>1 are created without `ready-for-dev`, and the operator labels the successor when merging the predecessor's PR). The gate exists only for the early-labeling case.
- **Part 2 — the verdict swap.** `intake-orchestrator` stops emitting `stacked-prs` and emits `sub-issues-sequential`; dev-pipeline Stage 1 gains the pre-claim reader and the `successorKey` state field; Stage 9 renders the operator-promotion line.

Commit ordering is **binding** (#262 Steps 1–2): Part 1 lands first and is additive-only, so the sweep is green at every commit boundary; the orchestrator verdict change and the Stage-1 reader land **together** so there is never a window where intake emits a verdict the pipeline cannot read.

## Assumptions

- The gate's only live input is an **early-labeled** successor arriving via the queue query. The routine path never produces a queued blocked issue, so a fail-open here is a degraded backstop, not a broken pipeline.
- Downstream stacked machinery (the `## Stacked-PR Outer Loop` in `stages/1-intake.md`, Stage-2 slice branching, Stage-9 retargeting, `max-pushed-slice.sh`, `start-slice.sh`, `slice-scope.sh`) becomes **dead code** after this PR and is deleted in #265. Leaving it in place is intentional; the sweep stays green because nothing this PR touches removes a file a preflight `exit 99` guard depends on.
- `tracker.keyPattern` supplies the adapter's key shape; the tool takes it as `KEY_PATTERN` (env) rather than reading config, matching the `BRANCH_PREFIX` seam.
- The eval fixture corpus (`docs/eval-fixtures/intake-orchestrator`, referenced by `run.sh`) is **not** in this repo, and CI is model-free. AC-8 is therefore graded at the rubric level; the paid re-baseline run is operator follow-up.

## Decision Ledger

No pre-flight `/plan-interview` ledger exists for this issue (`.claude/pipeline-state/263-ledger.md` absent), so these rows were authored in-pipeline. #262's own D-1…D-15 ledger is the parent decision record and is not restated here; these are the decisions this run had to take on top of it, all resolved at Stage-1 intake against the codebase.

| ID  | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | `successorKey` write interface — the spec names the field and its source but no command, and statectl has no generic setter | New subcommand `successor-key-set <issue> --key <key>`, matching the existing `*-set` family in the dispatch table (`target-repos-set`, `worktree-set`, `slice-partition-set`). Stage 1 calls it once after `init`. An absent trailer writes JSON `null` — explicitly present-and-null, so Stage 9's *iff non-null* read is total and pre-schema state files stay distinguishable by key absence | codebase-derived |
| D-2 | Malformed / duplicate trailers — `extract`'s line-omission encoding makes an unparseable trailer indistinguishable from an absent one, so the backstop fails open silently | Keep amendment R1's exit-0 contract. A `Predecessor:`/`Successor:` line whose value does not match `KEY_PATTERN` prints no line for that trailer, emits `[predecessor-gate] warning: unparseable <Kind> trailer: <raw>` on **stderr**, and still exits 0. Duplicates of the same kind: **last wins** (git trailer convention). Rationale: preserves R1 composability — the stage doc branches on printed lines, not on new exit codes — while making the fail-open visible in the run log. Proportionate because the gate is a backstop (D-11 never queues a blocked successor) | codebase-derived |
| D-3 | Unreadable predecessor state (404, transferred, cross-repo key, `gh` failure) — undefined branch on the one path the feature guards | Treated as **blocked**, identical to `open`: queue path advances to the next candidate, argument path rejects-and-stops with the reason on stderr. The read happens **pre-claim**, so no state file exists and `mark-failed` is unavailable — the pre-flight-gate posture applies, not the `failureContext` posture. **No new `failureContext.reason` enum value**, so the generated validators are untouched | codebase-derived |
| D-4 | Liveness scenario shape — AC-2/AC-6's "advances to the next queue candidate" has no executable production artifact, and "suite goes red with the gate deleted" describes an on-disk mutation the harness cannot perform | Scenarios assert the **mechanical shadow** per the suite's own declared scope boundary, driving the real `predecessor-gate.sh` and real `statectl`: `(pg-skip)` open predecessor → verdict 3, no state file; `(pg-go)` closed → verdict 0, state file + `claimed` receipt; `(pg-nv)` non-vacuity in the established `(ss6)`/`(ns3)` shape — the same path with only the predecessor state varied flips the outcome. No file deletion, no on-disk mutation of production code. The advance clause is discharged by the two-candidate composition, not by reimplementing Stage-1's queue loop in the harness | codebase-derived |
| D-5 | #262 D-15's self-contradictory "one home plus a lockstep row pinning the two skills' shared wording" — the manifest's comparators both require two live copies | Two live copies: canonical wording authored in `intake-orchestrator/SKILL.md`, mirrored in `decomposition-reviewer/SKILL.md`, pinned by a new **`verbatim`** manifest row with `LOCKSTEP-BEGIN/END decomposition-economy` markers in both files. "One home" reads as one canonical *author*, not one copy; "not a third copy" forbids a new third location | codebase-derived |
| D-6 | Status-enum swap blast radius — the fan-out reported the enum as code-generated, implying a regenerate-and-diff | Confirmed **not** required: `gen-statectl-validators.sh::parse_stage_markers()` extracts only each row's **first column** (the marker name), so the `intake` row's Statuses cell is documentation-only. Neither marker name changes, and there is no `valid_status` validator. The `(mk1)`/`(mk2)` selftest cases key on marker names and stay green. Swapping `stacked-prs-planned` → `split-into-sub-issues-sequential` is a prose cell edit in both copies | codebase-derived |
| D-7 | Fenced-code-block trailers — a `Predecessor:` line quoted inside a fenced example would be extracted | Deferred. The match is anchored to a strict full-line form, which already excludes the inline-backticked prose mentions that actually occur in these bodies; fence-state tracking is machinery the backstop does not earn. Recorded in the tool header as a known limitation | deferred |
| D-8 | Decomposition of this issue at intake | `no-split`, against the >10-file reconsider-split flag. Re-splitting along the Part-1/Part-2 seam would recreate exactly the consumer-less PR the operator's 5→3 consolidation removed; the risk is carried by the binding internal commit ordering instead | ticket-sourced — https://github.com/manoldonev/second-shift/issues/262 (Decomposition section, D-15 addendum) |

## Affected files/modules

**Part 1 — backstop (additive-only)**

- `plugins/dev-pipeline/skills/run/tools/predecessor-gate.sh` **[NEW]**
- `plugins/dev-pipeline/skills/run/tools/predecessor-gate-selftest.sh` **[NEW]**
- `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh` — additive scenarios only
- `plugins/dev-pipeline/skills/run/tools/tracker/README.md` — new operation row
- `plugins/dev-pipeline/skills/run/tools/tracker/github/README.md` — new concern row
- `plugins/dev-pipeline/skills/run/tools/tracker/jira/README.md` — new operation row (SKIP-with-note)

**Part 2 — verdict swap**

- `plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md` — frontmatter `description`, the three-question intro, caller-model prose, Step-0 dedup/resume guards, Step-4 verdict set, Step-5 self-check, Step-6 verdict branches, Brief persistence, Thresholds table + counterfactual prose, Issue Comment Format status list, What NOT to Do (D-15 rule), Dependency Analysis Step C prose
- `plugins/intake-toolkit/skills/decomposition-reviewer/SKILL.md` — D-15 mirrored rule + lockstep markers
- `scripts/lockstep-manifest.tsv` — new `decomposition-economy` row
- `plugins/dev-pipeline/skills/run/state-schema.md` — `successorKey` field, `intake` marker Statuses cell
- `plugins/dev-pipeline/skills/run/statectl.sh` — `cmd_successor_key_set()` **[NEW]** + dispatch entry
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` — `successor-key-set` cases
- `plugins/dev-pipeline/skills/run/SKILL.md` — one line added to the statectl CLI-surface listing (that listing enumerates every subcommand, so a new one is incomplete without it)
- `plugins/dev-pipeline/skills/run/stages/1-intake.md` — pre-claim gate on both pickup paths, body read moved pre-claim, verdict table, Step 1.D removal, cap line
- `plugins/dev-pipeline/skills/run/stages/9-open-pr.md` — successor-promotion line
- `plugins/intake-toolkit/evals/intake-orchestrator-eval/rubric.py` — verdict tokens, `expected.sub_issue_count`
- `plugins/intake-toolkit/evals/intake-orchestrator-eval/run.sh`, `run-structured.sh` — prompt verdict vocabulary
- `plugins/intake-toolkit/evals/intake-orchestrator-eval/smokes/gate-2-e2e-one-fixture.sh` — verdict regex
- `plugins/intake-toolkit/evals/intake-orchestrator-eval/FIXTURE-AUDIT.md`, `CLOSEOUT-BASELINE.md`, `FINAL-REPORT.md` — baseline prose

## Reuse inventory

- `plugins/dev-pipeline/skills/run/tools/max-pushed-slice.sh` — the env-seam + stdin-fixture precedent `predecessor-gate.sh` copies (documented `KEY_PATTERN` default, pure stdin, no network, `exit 2` on usage error). Reused as a *shape*, not imported.
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` `(mps)` section — the harness shape for the new selftest: a one-line helper piping fixture text, then `pass`/`fail` assertions. No `gh` mock.
- `plugins/dev-pipeline/skills/run/scenario-lib.sh` — `complete_stage` / `complete_run_vs` helpers already sourced by `scenario-liveness-selftest.sh`; the new scenarios reuse them for the claim-shape writes.
- `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh` `(ss6)` / `(ns3)` cases — the established non-vacuity idiom (vary one precondition, assert the outcome flips) that `(pg-nv)` follows.
- `scripts/check-lockstep-pairs.sh` — existing `verbatim` comparator and `LOCKSTEP-BEGIN/END` markdown marker form; the D-15 row adds data, no script change.
- `statectl.sh`'s `*-set` command family (`cmd_target_repos_set`, `cmd_worktree_set`) — `cmd_successor_key_set` **[NEW]** follows their arg-parse/validate/atomic-write structure.

No new shared helpers are introduced beyond `predecessor-gate.sh` itself.

## Implementation steps

**Commit 1 — `feat(dev-pipeline): predecessor-gate tool + selftest`**

1. Write `predecessor-gate.sh` **[NEW]**. `set -uo pipefail`, bash 3.2-compatible. Header documents the two modes, `KEY_PATTERN` (default `[0-9]+`), the exit table, and the D-7 fenced-block limitation.
   - `extract`: read stdin. For each of `Predecessor` / `Successor`, match the strict full-line form `^[[:space:]]*<Kind>:[[:space:]]*#?(<KEY_PATTERN>)[[:space:]]*$`, **last match wins**. Print `predecessor=<key>` / `successor=<key>`, omitting a line whose trailer is absent. A line matching `^[[:space:]]*<Kind>:` but failing the key match emits the D-2 stderr warning and prints nothing for that kind. Exit 0 always.
   - `verdict <state>`: `closed` → exit 0; `open` → exit 3; missing/other → usage error on stderr, exit 2.
   - No arguments to `extract`, no network, no `gh`.
2. Write `predecessor-gate-selftest.sh` **[NEW]** in the `(mps)` shape (see Test strategy).

**Commit 2 — `test(dev-pipeline): predecessor-gate liveness scenarios`**

3. Add `PRED_GATE="$HERE/tools/predecessor-gate.sh"` plus its `[[ -x ]] || exit 99` preflight alongside the existing ones, and the three scenarios `(pg-skip)` / `(pg-go)` / `(pg-nv)`. Extend the header's scenario list with a `predecessor` entry. **Additive only** — the stacked scenarios, the retired-tool preflights, and the `BLOCKED ON #211` block are untouched.

**Commit 3 — `docs(dev-pipeline): tracker predecessor-read operation rows`**

4. `tracker/README.md`: add a **predecessor-read** row to the operation table — github: "successor body read (folded into the queue query's `--json`, paid per candidate examined) feeding `predecessor-gate.sh extract`; conditional `gh api repos/{o}/{r}/issues/<predecessorKey>` state read, paid only when `extract` prints a predecessor key"; jira: *SKIP-with-note*, ordering operator-enforced (session-side MCP precedent). Also note `KEY_PATTERN` under the config list as `tracker.keyPattern`'s consumer.
5. `github/README.md`: concern row pointing at the new `plugins/dev-pipeline/skills/run/tools/predecessor-gate.sh` **[NEW]** + its selftest, written as a `../../`-relative link to match the sibling rows. `jira/README.md`: operation row stating the SKIP and that the trailer-rendering rule exists there only for the presented spec text.

**Commit 4 — `feat(intake-toolkit,dev-pipeline): sub-issues-sequential verdict + Stage-1 sequential reader`**

> Steps 6–13 land in **one** commit, not two. The Stage-4 plan review flagged that splitting the verdict swap from the reader contradicts this plan's own binding "land together" ordering claim; merging them removes the ambiguity instead of leaning on the PR boundary to satisfy it.

6. Orchestrator: frontmatter `description` and the intro's third question lose "stacked PRs" and gain "sequential sub-issues"; Step-4 verdict set becomes `no-split` | `sub-issues` (parallel) | `sub-issues-sequential`, the sequential bullet list inheriting the old stacked criteria (dependency chain, shared module, independently reviewable).
7. Step 6: replace the `stacked-prs` branch with `sub-issues-sequential` — creates ≤5 ordered sub-issues; **N>1 without the queue label**, each body carrying `Part of #<parent>`, verbatim ACs, the parent Brief's full reconciled QUARANTINE table + settled guardrails, `Predecessor:`/`Successor:` trailers rendered per `tracker.keyPattern`, and the line "queue when #<predecessor> is closed". Drop the `slicePartition` emission step. The parallel `sub-issues` branch keeps unconditional `ready-for-dev`.
8. Cap unification at 5: Thresholds table drops the stacked row; the counterfactual clause and the cap-gaming bullets each merge into one flavor-agnostic form. Brief persistence extends to the sequential verdict. The already-decomposed dedup becomes the `Part of #<parent>` search alone, label-agnostic; the `stacked-prs-planned` resume guard is removed. Status list in Issue Comment Format swaps the token.
9. D-15: replace the "Don't split for the sake of splitting" bullet in **What NOT to Do** with the run-cost-bias rule, wrapped in `<!-- LOCKSTEP-BEGIN decomposition-economy -->` / `END`. Mirror it verbatim over `decomposition-reviewer/SKILL.md`'s near-verbatim twin with the same markers, and add the `decomposition-economy` `verbatim` row to `scripts/lockstep-manifest.tsv`.

10. `state-schema.md`: document `successorKey` (nullable string, written at Stage 1 from the claimed issue's own `Successor:` trailer, read by Stage 9) and swap `stacked-prs-planned` → `split-into-sub-issues-sequential` in the `intake` marker's Statuses cell. No validator regeneration (D-6).
11. `statectl.sh`: add `cmd_successor_key_set()` **[NEW]** + its dispatch entry; accepts `--key <k>` or an explicit empty value writing `null`.
12. `stages/1-intake.md`: move the body read pre-claim and reuse it for the intake fan-out and the AC snapshot; insert the predecessor-gate call after `ISSUE_NUMBER` resolves and before the claim sequence's step 1, on **both** pickup paths. Queue path adds `body` to the query's `--json` and advances through the retained sorted candidates (bounded by the existing `--limit`, no re-query) to the first eligible, stopping with "no eligible issues in queue" when all are blocked; argument path rejects-and-stops. Add the `successor-key-set` call after `init`. Update the verdict table (`sub-issues` row's label becomes flavor-conditional, `sub-issues-sequential` row added, stacked row removed), the receipt/Brief/AC-snapshot verdict lists, the flavor-agnostic cap line, and delete Step 1.D's `slice-partition-set` persistence.
13. `stages/9-open-pr.md`: render "label #<successorKey> `ready-for-dev` when merging this PR" in the PR body and the run report when `successorKey` is non-null; render nothing when null.

**Commit 5 — `test(intake-toolkit): re-baseline the eval for the two sub-issue flavors`**

14. `rubric.py`: `expected.verdict` tokens become `no-split` / `sub-issues` / `sub-issues-sequential` / `escalate` / `skip-already-decomposed`; `expected.stacked_pr_count` retires in favor of `expected.sub_issue_count` covering both flavors; d2 scoring discriminates the two — a parallel verdict where sequential is expected is a wrong verdict (0), not a direction-right miss. The single ≤5 cap replaces the "not more than 3 stacked PRs" clause.
15. Update `run.sh` / `run-structured.sh` prompt vocabulary, the gate-2 smoke's verdict regex, and the three baseline docs' recorded token names.

## Test strategy

Verify-after (this is infrastructure and prose, not behavior inside an application surface). `commands.second-shift.unitTestScope` is `null`, so there is no mutation surface and the unit-test gate is `skip`.

**`predecessor-gate-selftest.sh` [NEW]** — `(mps)`-shaped, zero network, no `gh` mock. Helper pipes fixture text: `pg() { printf '%s\n' "$1" | bash "$GATE" extract 2>/dev/null; }`.

- `(pg1)` both trailers present → both lines, github `[0-9]+`.
- `(pg2)` predecessor only → only `predecessor=`; `(pg3)` successor only → only `successor=`.
- `(pg4)` neither → no output, exit 0.
- `(pg5)` `#` prefix optional — `#263` and `263` both yield `263`.
- `(pg6)` jira shape under `KEY_PATTERN='[A-Z]+-[0-9]+'` → `GH-540`.
- `(pg7)` cross-pattern isolation: a `GH-540` trailer under the github default is **not** extracted (and emits the D-2 warning).
- `(pg8)` malformed value (`Predecessor: #two`) → no line, exit 0, stderr carries `unparseable`.
- `(pg9)` duplicate trailers of one kind → last wins.
- `(pg10)` inline-backticked prose mention (`- \`Predecessor:\` trailers rendered …`) is **not** extracted — the anti-false-positive case, driven by this very issue's body shape.
- `(pg11)` `verdict closed` → 0; `(pg12)` `verdict open` → 3; `(pg13)` `verdict` with no arg → 2; `(pg14)` `verdict bogus` → 2; `(pg15)` unknown mode → 2.

**`scenario-liveness-selftest.sh`** — three composed scenarios driving the real tool and real `statectl`:

- `(pg-skip)` successor body with `Predecessor: #<A>`, A reported `open` → `verdict` exits 3; the harness performs no claim writes; assert **no state file** exists for the successor key (the not-picked-up shape — not the `failed`-terminal shape, and not the `sub-issues` carve-out shape).
- `(pg-go)` same body, A reported `closed` → `verdict` exits 0; the harness runs `init` + `comment-add --marker claimed`; assert the state file and the `claimed` receipt exist.
- `(pg-nv)` non-vacuity, `(ss6)` shape: assert `(pg-skip)`'s absent state file is caused by the gate, by showing the identical harness path with only the predecessor state flipped produces one. Paired with a second queued candidate whose own extract prints no predecessor and whose verdict path proceeds — the mechanical shadow of "advances to the next candidate".

**`statectl-selftest.sh`** — `successor-key-set` cases: writes the key; explicit-null form writes JSON `null`; the field round-trips through `get`; a terminal-state guard case consistent with the other `*-set` commands.

**Regression surface already in place** — `(mk1)`/`(mk2)` marker cases and the `gen-statectl-validators.sh` regenerate-and-diff drift check must stay green across the state-schema edit (they key on marker names, which do not change — D-6). `check-lockstep-pairs.sh` must go green on the new `decomposition-economy` row.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | `extract` honors both key shapes and all trailer combinations; `verdict` exits 0/3/2 | 1 | `(pg1)`–`(pg15)` in `predecessor-gate-selftest.sh` |
| AC-2 | selftest + three liveness scenarios pass with zero network; full sweep green | 1, 2, 3 | `(pg1)`–`(pg15)`; `(pg-skip)`, `(pg-go)`, `(pg-nv)`; the CLAUDE.md sweep |
| AC-3 | tracker README rows document both reads and both adapter postures | 4, 5 | — no test (infra-only) |
| AC-4 | orchestrator emits `sub-issues-sequential`; `stacked-prs` gone from the verdict vocabulary and Stage 1's reader | 6, 7, 8, 12 | `(pg-go)` composes the post-swap Stage-1 path; rubric token change in step 14 |
| AC-5 | sequential N>1 created without the queue label, carrying anchor, verbatim ACs, QUARANTINE table, trailers; parent Brief persisted | 7, 8 | `(pg10)` pins the trailer shape the rendering must produce (the rest is an agent-prose contract model-free CI cannot execute) |
| AC-6 | open-predecessor successor skipped pre-claim (no comment, no label swap, no state file); next candidate claimed; closed proceeds | 3, 12 | `(pg-skip)`, `(pg-go)`, `(pg-nv)` |
| AC-7 | `successorKey` recorded at Stage 1; Stage 9 renders the promotion line iff non-null | 10, 11, 12, 13 | `successor-key-set` cases in `statectl-selftest.sh` |
| AC-8 | eval discriminates the two sub-issue flavors | 14, 15 | — no test (infra-only) |

## Verification commands

```bash
# the repo's three sweeps (CLAUDE.md Verification)
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} env SKIP_STRESS=1 bash {}

# the directly-changed suites, run alone for a readable signal
bash plugins/dev-pipeline/skills/run/tools/predecessor-gate-selftest.sh
bash plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh
bash plugins/dev-pipeline/skills/run/statectl-selftest.sh

# the lockstep row added for D-15, and the statectl codegen drift check
bash scripts/check-lockstep-pairs.sh
bash plugins/dev-pipeline/skills/run/tools/gen-statectl-validators.sh > /tmp/statectl.new \
  && diff -u plugins/dev-pipeline/skills/run/statectl.sh /tmp/statectl.new

# AC-1 spot check against this issue's own body shape (the false-positive case)
gh api repos/{owner}/{repo}/issues/263 --jq .body \
  | bash plugins/dev-pipeline/skills/run/tools/predecessor-gate.sh extract
# expect exactly: successor=265
```

## Risks / rollback notes

- **Dead-code window.** After this PR the stacked *execution* path survives while its verdict producer is gone. Nothing dispatches it (intake can no longer emit `stacked-prs`), so it is unreachable rather than broken; #265 deletes it. Risk: an over-eager deletion here turns the sweep red via the retired-tool `exit 99` preflights. Mitigation: Part 1 is additive-only and the deletion inventory is explicitly out of scope.
- **Enum-copy drift.** `stacked-prs-planned` lives in two prose copies (`state-schema.md`, orchestrator `SKILL.md`). Both must swap together; only the second is a verdict the orchestrator can emit. Mitigation: step 8 and step 10 are in the same PR, and `(mk2)` marker-emission parity catches a *marker* mismatch (though not a status one — statuses are documentation-only).
- **Silent fail-open on a malformed trailer.** Accepted per D-2, bounded by the stderr warning and by D-11 keeping blocked successors out of the queue. Rollback: the gate is composed from a stage doc, so reverting the Stage-1 call site disables it without touching the tool.
- **Scenario vacuity.** The skip scenario asserts an *absence*, which passes trivially if the harness never writes. `(pg-nv)` exists precisely to make that failure mode visible; if it cannot be made to flip, the skip scenario is not trustworthy and must not be counted toward AC-2.
- **Rollback:** the whole PR is revert-safe — Part 1 is additive, and Part 2's edits are contained to prose, one statectl subcommand, and the eval rubric. No migrations, no config-version bump (that is #267).

## Out-of-scope

- Deleting the stacked execution path, state fields, `slice-set` / `slice-partition-set`, `max-pushed-slice.sh`, `start-slice.sh`, `slice-scope.sh`, plan-lint slice mode, Stage-8 slice mode, `scopeBase`, scope-completeness Step 4c, and the stacked e2e legs/fixture — all #265.
- The `{slice}` token retirement, the `configVersion` bump, the migration doc, and `config-lint` version bounds — all #267.
- Branch-from-predecessor topology (#262 D-10 explicitly rejects it for v1).
- Any change to the parallel `sub-issues` path beyond the cap unification and the `create-sub-tickets` label conditionality.
- Re-running the paid intake-orchestrator eval to regenerate baseline scores — operator follow-up; this PR changes the rubric and prompts only.
- Fence-aware trailer parsing (D-7).
