I explored the repo before planning. Two findings change the shape of the plan, so I'll state them first, then give the plan of record in full.

## Finding 1 (blocking): four of the five in-scope corpus files are not in this checkout

The base commit is literally titled *"consumer repository at pinned base, kit not present."* There are 97 tracked files and no `plugins/` directory — and it is not gitignored (`grep -n plugins .gitignore` → nothing; `git ls-files | grep -c plugins` → 0).

| Scope file (ticket) | Present? |
| --- | --- |
| `scripts/check-lean-chain.sh` | **yes** (880 lines) |
| `plugins/dev-pipeline/skills/build-lean/lean-gate.sh` | no |
| `plugins/dev-pipeline/skills/build-lean/lean-evidence.sh` | no |
| `plugins/dev-pipeline/tools/operator-override.sh` | no |
| `plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh` | no |

Also absent: `scenario-liveness-selftest.sh` (AC-10), and `OVERRIDE_GATES`/`OVERRIDE_SCOPES` — the value set AC-5 and AC-6 check against — which live in the missing files. `check-lean-chain.sh:407` names the missing payload and `envfail`s on it.

This does not merely make the work harder; it makes the guard's central claim unsatisfiable on this tree. The design of record is "the enumerator's `--list` output **IS** the denominator." Over an absent file the enumeration is empty, so every register row for it reds as anchor drift (AC-2's third arm), and a guard written to tolerate an absent corpus file is exactly the vacuous coverage the ticket exists to prevent. Note the same is already true of the precedent: `scripts/fail-open-sites.tsv` carries rows naming `plugins/...` paths, and `check-fail-open-shapes.sh` reds on *"dispositioned file does not exist — the row is stale"*. I read that from the code — the sandbox declined to let me execute the guard, so I have not measured it.

**What I need:** the kit materialized at the pinned ref (submodule, `gh` fetch, sibling checkout, whatever this repo's mechanism is), or an explicit instruction to proceed with a smaller corpus. Everything below is the plan once the corpus is reachable; Step 0 is where it gets resolved, and §"If the corpus stays absent" says what I'd deliver instead.

## Finding 2: AC-3's primitive list is already incomplete for the one file I can measure

AC-3 names `note_violation` (18) and `fail` (2) for `check-lean-chain.sh`. Measured on this tree: `note_violation` defined at `:478` with 18 call sites ✓; `fail` defined at `:193` with **one** call site (`:475`); and a third refusal primitive AC-3 does not mention at all — **`envfail`**, defined at `:194` (`exit 2`), 16 occurrences including sites at `:401`, `:409`, `:425`.

`envfail` is exactly the class AC-1 created `not-a-gate` for, so this doesn't threaten the design — but it does mean AC-3's per-file lists are a starting hypothesis, not the specification. AC-3's own words are *"names **every** refusal primitive per file rather than assuming one"*, so the plan re-measures each file and treats a discrepancy with the ticket as a finding to record, not a number to transcribe.

---

# Plan of record

Names I'll use (chosen to avoid collision with `tools/gate-ablation-classes.tsv`, which the ticket warns is not the key; `check-*.sh` + directory-scoped same-stem selftest means mutation pairing resolves with no `tools/mutation-pair-map.tsv` row):

- guard `scripts/check-gate-buckets.sh`
- register `scripts/gate-bucket-sites.tsv`
- selftest `scripts/check-gate-buckets-selftest.sh`

I produce every artifact below unless noted. Order is production order.

**0. Corpus availability + branch.** Resolve Finding 1 with you; cut a work branch off `main`. No lean spec is committed — the `build-lean` harness isn't present to run, and `check-lean-chain.sh`'s applicability *is* a key-matched lean spec in the PR's own diff, so this lands as an ordinary contributor PR and that gate is not-applicable by construction. Flagging it rather than assuming it, since this repo is its own dogfooding canary.

**1. Measurement record (scratch, not committed).** Per file, grep out every refusal-primitive definition and its call sites; reconcile against AC-3's list; record discrepancies (Finding 2 is the first). This is what makes AC-3's "measured today" honest, and it's the evidence OR-1 needs — the `envfail` site count decides whether one-row-per-class actually prevents ~95 mechanical rows or is solving a non-problem.

**2. Enumerator half of `scripts/check-gate-buckets.sh`.** `--list` and `enumerate()` only, no checking. Per-file recipes, one per primitive; `orchestrate-lean.sh`'s `terminal` matched with a non-zero exit argument *and* the `:764`/`:923`/`:982` success calls enumerated (AC-3) so they land as `not-a-gate` rows rather than being filtered out of the denominator. Helper *definitions* self-excluded by name, precedent `check-fail-open-shapes.sh:69`. Output `relpath<TAB>lineno<TAB>text`, `LC_ALL=C sort`. `-h/--help` prints the header via a range-free `sed` as the precedent does.

**3. Header block of the guard (AC-8).** Why it exists; the denominator-is-the-output claim; the corpus; **every self-exclusion by name**; the residual named as residual — the ~19 `scripts/`+`tools/` CI guards, the `.mjs` workflow gates, agent contracts. An unstated exclusion is a hole in the claim, so this is written before the rows, not after.

**4. `scripts/gate-bucket-sites.tsv`,** authored against step 2's actual output. Columns `file <TAB> disposition <TAB> anchor <TAB> yield <TAB> why`. Closed enum `gates-llm | gates-signal | gates-process | not-a-gate`. Anchors are distinctive line **text**, never line numbers. `not-a-gate` rows state what the site is instead (environment refusal / usage error / success path). Own header restating columns, the three reds, AC-5/AC-6 rules, the residual, and "the count is not the contract."

**5. Checking legs of the guard.** Three independent reds (AC-2): undispositioned site; anchor matching nothing in its file (drift); row covering zero enumerated sites. Plus register-internal validation: unknown disposition (AC-1); malformed row; `not-a-gate` with no stated reason (AC-1); **AC-5** — `gates-llm`/`gates-signal`/`not-a-gate` must have an empty yield cell, and a yield cell naming an `OVERRIDE_GATES` value must be on a `gates-process` row; **AC-6** — every `gates-process` yield cell either names an `OVERRIDE_GATES`/`OVERRIDE_SCOPES` value or matches `^unwired — `, form only. Per-row covered-site count printed (AC-4). Exit code = violation count.

One design decision I'll take here and record: the guard **extracts** the `OVERRIDE_GATES`/`OVERRIDE_SCOPES` value set from its declaration site in the tree rather than hardcoding it, and reds if extraction yields nothing — hardcoding would let AC-5 go stale silently, and an empty extraction that read as "no violations" would be a fail-open of exactly the kind `check-fail-open-shapes.sh` exists to ban.

**6. `scripts/check-gate-buckets-selftest.sh`.** Precedent technique: fixture trees under `mktemp`, each with its own register, handed to the real guard as its repo root; no production file written; bash-3.2-safe, no network. Cases: **(g0) the real tree green** — the non-vacuity case, and the same pattern `check-fail-open-shapes-selftest.sh` uses at its `(g0)`; all-green fixture; each of AC-2's three arms **independently**; unknown disposition; `not-a-gate` with no reason; AC-5 both directions; AC-6 bad form; `--list` prints the denominator and checks nothing; covered-count is printed; and the negative direction — helper definitions are not enumerated, `terminal … 0` *is*.

**7. Real-tree green.** `bash scripts/check-gate-buckets.sh` exits 0 against the actual corpus. Iterate 4↔5 until it does.

**8. `.github/workflows/ci.yml`** — one step in the `lint-and-selftests` job, placed after `capability parity register (tools/capability-parity.tsv)` alongside `check-lockstep-pairs.sh` and `check-eval-model-identity.sh`, matching their comment style. **Not** in `pr-gates` (AC-7).

**9. `docs/pipeline-manifesto.md`** — the bucket list at `:134-138` gains `gates-signal` with its premise ("the fact is objective") and never-yields status, plus a pointer to the register. Per P5 the manifesto states the principle and does not restate the enforcement (AC-9).

**10. Obligations (AC-10), each reconciled and each *stated* even when it resolves to no change** — a silently skipped obligation is the failure mode this repo's whole register discipline exists to catch:
- `tools/gate-ablation-classes.tsv`: a row per new refusal reason. Expected to be **zero rows** — all 34 rows are `lean-gate.sh` milestones and this slice adds a CI guard, not a milestone refusal. I'll say so explicitly; if register work does add a fail-closed branch inside a corpus file, rows follow.
- `scripts/fail-open-sites.tsv`: I'll write the guard to introduce no new enumerated `| grep -q` shapes, then verify by diffing `check-fail-open-shapes.sh --list` before and after. Rows added only if the enumeration changes.
- `scenario-liveness-selftest.sh`: extend for every verdict path touched, with a non-vacuity case. Expected to be **not applicable** — this slice touches no lean-lane verdict path. Recorded as such, not skipped.
- `scripts/check-guard-budget.sh`: a new `check-*.sh` + `*-selftest.sh` is guard mass by `is_guard_path()`, so the branch **must** carry a `Guard-mass:` commit trailer with the delta and reason.
- `tools/selftest-suite-timings.tsv`: a row only if the new suite measures ≥9s.

**11. Verification, CLAUDE.md's recipe verbatim** plus the specific guards: `shellcheck -e SC1091,SC2015,SC2181` over all `*.sh`; `jq empty` over all `*.json`; `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`; `check-fail-open-shapes.sh`; `check-lockstep-pairs.sh`; `capability-parity-check.sh`; `check-guard-budget.sh origin/main`; diff-scoped mutation sweep over the new guard.

**12. Commit(s).** `feat(...)` per CLAUDE.md — the AI tooling *is* the product here, so `chore:` would silently downgrade the release. Trailers: `Guard-mass: <delta> — <reason>` and `Changelog: none` (this PR is outside `plugins/**`, but the trailer is free and always valid). **No** edit to `CHANGELOG.md`, `plugin.json` versions, or `marketplace.json` — frozen, and `check-frozen-files.sh` rejects it.

**13. PR.** Body carries `Part of #605` and `Closes #<this ticket>`; the residual restated for the reviewer; OR-1 and OR-2 recorded as the reversible defaults taken (one row per `envfail` class; `unwired` permitted indefinitely) with the measurement from step 1 backing OR-1. **You** review and merge.

## If the corpus stays absent

I would not ship a register over one file and call it coverage — the ticket names that failure mode by name. What I'd deliver instead: steps 2/3/5/6/8 in full (guard, header, all check legs, selftest with fixture-only cases), the register covering `check-lean-chain.sh` alone, and the guard's corpus list carrying the four absent files as a **hard red** — "corpus file not present; the register cannot be complete" — rather than an exclusion. That fails CI until the kit is present, which is the honest state. Say the word if you'd prefer that over waiting.

Stopping here — nothing implemented.
