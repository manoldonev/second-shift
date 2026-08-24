I have the lane contracts and the precedent in hand. Here is the plan of record. **No code written yet.**

---

## Plan of record

### Preconditions I must resolve first (not artifacts, but they parameterize everything below)

- **The issue number `<N>`.** The ticket text never states it — it says only "Part of #605", routed by #611/#613. `gh` is not authorized in this session, so `<N>` is a lookup at pickup time. Every path below is parameterized on it.
- **Whether a pre-flight ledger `<N>-ledger.md` exists.** Per the lane, a pre-flight ledger is *binding input* and can override the issue's ACs — it is checked at step 4 of intake, not inferred. If one exists, its `user-answered`/`user-delegated` rows are projected with `ledger-carry-forward.sh` (plan rows are 4 columns), never retyped, and any row I don't carry becomes a `DEPARTURE — <reason>`.

---

### Phase 0 — pickup (artifacts: run records and a branch)

| # | Artifact | Where | Contents | Producer |
|---|---|---|---|---|
| 0.1 | Run-id cache + entry record | `<N>-run-id` (gitignored pipeline state) | `RUN_ID` exported first, then `bash G entry <N>` — idempotent, also sweeps dead lane worktrees | me, via `lean-gate.sh` |
| 0.2 | Claim marker + label swap | GitHub issue `<N>` | two bot-wrapper writes: queue→claimed label, `lean-claimed` marker comment | `bash G claim <N>` (bot identity) |
| 0.3 | Lane worktree + branch | `<lean prefix><N>`, cut from the configured base | — | me |

`bash G 1 <N>` then prints the exact spec path it demands; I do not guess it.

---

### Phase 1 — the spec (the one artifact that gates everything after it)

**1.1 `docs/plans/second-shift-<N>-lean.md`** — produced by me, committed before implementation.

Must contain:
- **The `AC-n` set.** I carry AC-1…AC-10 forward. This is the living definition of done; if scope moves, I amend it *before* milestone 5. Two amendments I expect to make at authoring time, both stated as ACs rather than discovered later:
  - **AC-3 is incomplete as written and I will widen it.** It names refusal primitives for four of the five in-scope files but names **none for `lean-evidence.sh`** — the file the ticket calls non-optional. I measured it: `lean-evidence.sh` defines `envfail`, `note_violation`, `inapplicable`, and `override_block_violation` (plus the `arm_*` callers). AC-3's own rule is "name **every** refusal primitive per file rather than assuming one", so the spec's AC-3 gets `lean-evidence.sh`'s measured primitive list added, with the measurement recorded. Silently shipping AC-3's four-file list would be exactly the vacuous coverage the ticket's `lean-evidence.sh` paragraph exists to prevent.
  - **The counts in AC-3 are re-measured at the branch head, not copied.** The ticket's "18 sites / 2 sites / `:764`/`:923`/`:982`" are figures from intake. A measured AC re-stales on every commit; I re-derive them after the last commit and amend, rather than restating intake's numbers.
- **A `## Decision Ledger`** (4-column plan rows), carrying any pre-flight rows under their original `D-n` ids, plus new rows for:
  - `D-a` **OR-1** — `envfail` sites dispositioned **one row per class**, with AC-4's covered-site count printed. `reversible-default-and-flag`, taking the ticket's stated default; flagged, not paused.
  - `D-b` **OR-2** — a `gates-process` row may stay `unwired` indefinitely. Default yes per AC-6.
  - `D-c` naming/siting: the register pair lives in `scripts/`, beside its precedent and beside the two guards AC-7 names as its CI neighbours (`check-lockstep-pairs.sh`, `check-eval-model-identity.sh`), **not** in `tools/` with the `gate-ablation-*` family — the ticket is explicit that `gate-ablation-classes.tsv` is not the key and shares no schema.
  - `D-d` the register **adopts** the triage record's `path::name` enforcer key unchanged (settled at intake; #610 D-5's reversibility is a licence, not an obligation).
- **No `## Design` section** unless `design.provider` is configured in the dogfood config; that config is untracked and shared across worktrees, so I read it rather than assume. Decide once — the disarm state-locks the moment milestone 3 arms.

**1.2** `bash G 1 <N>` green. That rc=0 is the only evidence milestone 1 passed.

---

### Phase 2 — implementation (five files touched, three of them new)

Order matters: the register is written *from the enumerator's output*, so the enumerator comes first.

**2.1 `scripts/check-gate-buckets.sh` (NEW)** — the guard, modelled directly on `check-fail-open-shapes.sh`.

- A header comment carrying, per AC-8: the five-file corpus; the **named residual** (the ~19 `scripts/`+`tools/` CI guards and the `.mjs` workflow gates, out of scope); and **every self-exclusion** stated individually — helper *definitions* that match their own shape, excluded by name the way the precedent does at `check-fail-open-shapes.sh:69`. An unstated exclusion is a hole in the denominator claim, so the header is load-bearing, not decoration.
- `enumerate()` — per-file, per-primitive shapes printing `relpath<TAB>lineno<TAB>text`, sorted. Per AC-3, `orchestrate-lean.sh`'s `terminal` is enumerated **only with a non-zero exit argument**, and its success calls are enumerated-and-dispositioned `not-a-gate`, not filtered out.
- `--list` prints the denominator and **checks nothing**, exiting 0 (AC-2).
- Three **independent** reds (AC-2), each its own `fail()` so a single run reports all three: undispositioned site; anchor matching nothing (drift); row covering zero live sites. Per AC-4 a row covering zero sites reds *as drift* — one row per site, but an anchor MAY cover several, and the **covered-site count is printed per row** so a loose anchor is visible rather than silent.
- **AC-5, the safety arm, register-internal**: a `gates-llm` / `gates-signal` / `not-a-gate` row MUST have an empty yield cell; a row whose yield cell names an `OVERRIDE_GATES` value MUST be `gates-process`. Both proximity readings were rejected at intake and I will not revisit them.
- **AC-6, form only**: every `gates-process` yield cell either names a value from `OVERRIDE_GATES`/`OVERRIDE_SCOPES` (`intake-unqueued spec-open-region` / `intake-attestation open-region-resolution`, defined at `lean-evidence.sh:993-994` and `operator-override.sh:182-183` — note these are a lockstep twin, which is why `lean-evidence.sh` is in the corpus) or reads `unwired — <reason>`. The guard checks the shape; it does not chase follow-up tickets.
- Unknown disposition = error, closed enum `gates-llm | gates-signal | gates-process | not-a-gate` (AC-1).
- Doctor convention: exit code = violation count.

**2.2 `scripts/gate-buckets.tsv` (NEW)** — the register, written **from `--list` output**, never from reading the diff.

- Columns: `file <TAB> disposition <TAB> anchor <TAB> yield <TAB> why`.
- Anchors on distinctive line **text**, never line numbers.
- Every `not-a-gate` row states what it *is* instead — environment refusal, usage error, success path (AC-1).
- Every `why` names the **mechanism** that makes the disposition true, not "looks fine".
- A `gates-process` row whose consumer sits outside the lean lane cites **#631** rather than pretending the path works.
- Its own header restates the "the `--list` output IS the denominator, and the count is not the contract" pair, as `fail-open-sites.tsv` does.

**2.3 `scripts/check-gate-buckets-selftest.sh` (NEW)** — auto-discovered by `tools/run-selftests.sh` (`find . -name '*-selftest.sh'`, `run-selftests.sh:327`), so no registration edit.

Cases, per AC-2 — **each arm independently, plus the all-green arm**, all against synthetic fixture trees in an isolated temp root, never the real repo:
undispositioned site · anchor drift · row covering no live site · unknown disposition value · **AC-5 violation both directions** (a `gates-signal` row carrying a yield; a row naming an override value but bucketed non-`gates-process`) · **AC-6 form violation** · a covered-count > 1 printing case · `--list` checks nothing · all-green. Per the lane's testing posture these must be **liveness** cases — each one has to red the guard when the guard's corresponding branch is broken, not merely execute it.

**2.4 `.github/workflows/ci.yml`** — one step, in the **always-on guard job** beside `check-lockstep-pairs.sh` (`ci.yml:143`) and `check-eval-model-identity.sh` (`ci.yml:149`). **Not** in `pr-gates` (AC-7), whose large env block this guard does not need. Same class as the `capability-parity-check.sh` step already there: a register whose guard needs an explicit invocation because the paired selftest only proves the guard works, never runs it against the real register.

**2.5 `docs/pipeline-manifesto.md`** — the bucket section (the `### Where a gate may yield…` block, currently two bullets: `gates-llm`, `gates-process`) gains **`gates-signal`** as a third bullet and a pointer to `scripts/gate-buckets.tsv`. Per P5 the manifesto states the principle; it does **not** restate the enforcement (AC-9). Note that this section is inside the trust-boundary chapter and may carry LOCKSTEP markers — I check `check-lockstep-pairs.sh` before editing, since an inline copy elsewhere must move byte-for-byte with it.

**2.6 AC-10 obligations — each one a determination I make and record, not an assumption**

- `tools/gate-ablation-classes.tsv` — a row per **new refusal reason**. My expectation is that this guard adds *no* new `lean-gate.sh` milestone refusal (it is a CI guard, not a lane gate), so **zero rows are owed**. That is a claim I must demonstrate and write into the spec, the way #613's verdict recorded "no `fail-open-sites.tsv` row is owed", rather than leave silent.
- `scripts/fail-open-sites.tsv` — my new fail-closed branches reconciled against it. If `check-gate-buckets.sh` contains any `| grep -q` site it must be dispositioned there, or converted to `checked_match`. Determined by running `check-fail-open-shapes.sh --list` on the branch, not by reading my own diff.
- `plugins/dev-pipeline/skills/build-lean/scenario-liveness-selftest.sh` — extended for **every verdict path touched, with a non-vacuity case**. Expectation: I touch no verdict path, so nothing is owed — again a recorded determination, not a silence.

**2.7 Commits** — through `bot-commit.sh`, re-passing identity on any `--amend`. Two mandatory trailers:
- `Changelog:` — CLAUDE.md:23 requires one on every `plugins/**` PR; `Changelog: none` if nothing is consumer-visible. Never edit `CHANGELOG.md` in a feature PR.
- **`Guard-mass:`** — `check-guard-budget.sh` classifies `check-*.sh` and `*-selftest.sh` as guard mass (`is_guard_path`, `check-guard-budget.sh:38-44`). This PR adds two such files, so mass *will* increase and the guard reds without the trailer. The trailer must state the delta and reason; the guard validates presence, not the number, so the number being honest is on me.

**2.8** `bash G 2 <N>` then `bash G 3 <N>` — green before any handoff. `bash G all <N>` before close-out, because a milestone satisfied before a fix round is stale.

---

### Phase 3 — the PR (produced by me)

A **ready, non-draft** PR containing: summary, spec link, `Closes #<N>` (unbackticked — a `Closes` in a code span is inert), and the cost block from `pipeline-cost-block.sh --stateless --issue <N>` appended to the description. No stage sections.

Then `bash G mark <N>` — here, at step 7, **not** at milestone 5: a PR comment fires no `pull_request` event, so a marker posted after the review's push is invisible to the CI run that gates the merge.

I hand off **without waiting for CI**. `pr-gates` cannot be green pre-handoff — the verdict record does not exist yet, so the verdict check is red by construction. Waiting on it is a guaranteed-red wait.

---

### Phase 4 — review (**produced outside this session — not mine**)

**`docs/plans/second-shift-<N>-lean-verdict.md`** is written by a separate top-level `/dev-pipeline:review-lean <pr>` session under its own identity. I dispatch no reviewer.

`bash G 4 <N>` passes only on a committed `verdict=approve` whose `reviewed_patch_id` **is** this branch's current patch. On `needs-work`: I fix **every** blocker, push, and request a **new** review context — never a resumed one. Any content pushed after an approve costs another round.

---

### Phase 5 — close-out and merge

`bash G close-out <N>` — one call, none of it mine to compose: it recomputes the published figure, writes the `cost-log.jsonl` row, replaces the stale cost block in the PR description, posts the single closing comment with the PR link and verdict-record reference, asserts milestone 5, and tears down the worktree (never the branch). I **leave the claimed label alone** — milestone 5 requires an open PR, so review is still in flight; the repo's unclaim workflow releases it on close.

**Merge is not mine.** I never merge without explicit per-action authorization from the operator, regardless of how green the PR is.

---

### Two things I am flagging, not pausing on

1. **AC-3's primitive list omits `lean-evidence.sh` entirely** while the ticket's scope section calls that file's inclusion non-optional. I am treating this as a drafting gap and widening AC-3 to the measured set (`envfail`, `note_violation`, `inapplicable`, `override_block_violation`), recording the measurement. If you intended `lean-evidence.sh` to be covered by anchors only and not by its own primitive enumeration, say so and I will re-cut AC-3 instead.
2. **Anchor drift is the design's known cost.** A register anchored on refusal-message *text* reds whenever a gate's wording changes — that is AC-2's drift arm working as specified, and it is a maintenance tax the precedent already pays. I am not designing around it; I mention it so the first drift red is read as the guard working, not as a bug.
