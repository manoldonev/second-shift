I've surveyed the precedent, the corpus, the CI wiring, and the obligation surfaces. Here is the plan of record.

## Assumptions I'm proceeding under

- **This ticket is `#636`** (branch `claude/second-shift-636` exists; worktree is `wt-abl-636`). Every artifact name below keys off that. If it's a different number, only filenames and the `Closes` trailer change.
- **No production file in the corpus gets edited.** The register is a TSV + guard that *reads* the five files. That keeps the `override-record-reader` LOCKSTEP block (`lean-evidence.sh:989-1088` ≡ `operator-override.sh:178-277`, held **verbatim**) untouched — an anchor comment added to one copy would red `check-lockstep-pairs.sh`.
- The checkout has 72 uncommitted `SKILL.md`/agent deletions unrelated to this work. I'll leave them alone and, if a suite reds on them, say so rather than fold them into this change.

## Three measured deltas from AC-3's primitive list — I proceed, and record them

AC-3 says "names **every** refusal primitive per file rather than assuming one" and then lists what was "measured today". My measurement disagrees with the list in three places. AC-3's governing sentence beats its own snapshot, so these are BUILD-side resolutions, not a pause:

| # | AC-3 says | Measured | Resolution |
|---|---|---|---|
| 1 | `lean-evidence.sh` — **absent from the list entirely** | `envfail` (`:165`), `note_violation` (`:168`), 42 candidate lines | Enumerate both. The Scope section calls its inclusion "not optional"; AC-3 just didn't restate it. |
| 2 | `check-lean-chain.sh`: `note_violation` + `fail` only | also `envfail` (`:194`), **15 lines** | Enumerate `envfail`. Omitting it would leave 15 refusals outside the denominator — the exact vacuity this slice exists to prevent. |
| 3 | `orchestrate-lean.sh`: `terminal` with non-zero exit | `envfail() { terminal "$1" 2 "$2"; }` (`:336`), **16 call sites** | Enumerate `envfail` as a second primitive there. A `terminal`-only recipe misses every site that refuses *through* the wrapper. |

One open judgment I'll settle in the spec's ledger, not silently: `lean-evidence.sh:187 inapplicable()` is an arm-skipped record, not a refusal. If I exclude it, AC-8 requires the exclusion be **stated in the guard header** — an unstated exclusion is a hole in the "output IS the denominator" claim.

---

# Plan of record

### 1. `docs/plans/second-shift-636-lean.md` — the committed spec
**Produced by:** me (build session), first, before any code. **Gated by:** `lean-gate.sh` milestone 1.

Contains: AC-1…AC-10 restated as individually-satisfiable criteria; a **Decision Ledger** whose rows carry provenance (`ratified` for everything in "Settled at intake — do not re-litigate"; `derived` for the design calls below); the three AC-3 deltas above as ledger rows; OR-1 and OR-2 recorded as `reversible-default-and-flag` with the defaults taken; `Design: none` (disarms milestone 3's render lane).

Design calls the ledger will carry:

- **Names.** Guard `scripts/check-gate-buckets.sh`, register `scripts/gate-bucket-register.tsv`, selftest `scripts/check-gate-buckets-selftest.sh` — sited in `scripts/` alongside the precedent pair, not in `tools/`.
- **Columns** (AC-1): `file ⇥ disposition ⇥ anchor ⇥ yield ⇥ why`. Five, where the precedent has four; the `yield` cell is the new one and is what AC-5/AC-6 check.
- **The guard derives the override vocabulary, never restates it.** It greps `OVERRIDE_GATES=`/`OVERRIDE_SCOPES=` out of `operator-override.sh:182-183` at runtime. A hardcoded third copy would be a new lockstep obligation for no benefit.
- **OR-1 default:** one row per `envfail` *class* per file, with AC-4's covered-count printed, so ~95 mechanical rows don't drown the register.
- **Enforcer key:** adopts `path::name` unchanged, per the intake settlement.

### 2. `scripts/gate-bucket-register.tsv` — the register
**Produced by:** me, authored against the guard's own `--list` output.

- Closed disposition enum: `gates-llm | gates-signal | gates-process | not-a-gate`.
- Header records (AC-8): the out-of-scope residual **named** — the ~19 `scripts/`+`tools/` CI guards and the `.mjs` workflow gates — and **every** self-exclusion (helper definition lines by name; `inapplicable` if excluded).
- The 8 points AC-identified as neither-fits — `m2/frozen-files`, `m2/changelog-trailer`, `m3/{lint,typecheck,test,extra-lane,setup-lane,no-verify-lane}` — land as `gates-signal`, each `why` naming the mechanism (an objective build/tree fact), not "looks fine".
- `not-a-gate` rows state what they are instead: environment refusal, usage error, or success path (`orchestrate-lean.sh:764/923/982`).
- Any `gates-process` row whose consumer sits outside the lean lane **cites #631** rather than pretending the path works.

### 3. `scripts/check-gate-buckets.sh` — the guard
**Produced by:** me. Exit code = violation count (doctor convention, per precedent).

- `--list` prints `file ⇥ line ⇥ text`, checks nothing, **exits 0 even on a dirty tree** (AC-2).
- Corpus: the five named files, literally. Primitives per file as measured above; helper **definition** lines self-excluded by name, as `check-fail-open-shapes.sh:69` does.
- Anchors are distinctive line **text**, never line numbers. `hits > 0` semantics, matching the precedent.
- Reds, each independently: unclassified site · anchor drift · row covering zero live sites · unknown disposition · malformed row · missing register.
- **AC-5 (register-internal safety arm):** `gates-llm`/`gates-signal`/`not-a-gate` ⇒ yield cell MUST be empty; a yield cell naming an `OVERRIDE_GATES`/`OVERRIDE_SCOPES` value ⇒ disposition MUST be `gates-process`.
- **AC-6:** every `gates-process` yield matches a known override value **or** `unwired — <reason>`. Form only; no follow-up-ticket existence check.
- **AC-4:** clean output prints the covered-site count per row, so a loose anchor is visible rather than silent.
- Writes no `producer | grep -q` shapes (uses `grep -qF -- … file`), so **zero `fail-open-sites.tsv` rows are owed** — a claim I'll verify by running the precedent guard, not assert.

### 4. `scripts/check-gate-buckets-selftest.sh` — behavioral coverage
**Produced by:** me. Fixture trees under `mktemp`, real guard as its repo root, no production file written. bash-3.2-safe, no `gh`, no network; reaches CI by the `*-selftest.sh` glob.

Cases: the **real tree** clean (the case without which the guard would only ever grade fixtures) · all-green fixture · unclassified site · anchor drift · row covering zero sites · unknown disposition · malformed row · missing register · AC-5 arm A (`gates-llm` with a non-empty yield) · AC-5 arm B (an override value on a non-process row) · AC-6 form violation · `not-a-gate` with no "what it is instead" · definition-line self-exclusion · covered-count printing · `--list` is the denominator and moves when a site is added · `--list` exits 0 · `--help` · `TMPDIR` unset.

### 5. `.github/workflows/ci.yml` — CI wiring (AC-7)
One step in the **`lint-and-selftests`** job, immediately after `eval-harness model identity` (`:148-149`) — the always-on guard job that already runs `check-lockstep-pairs.sh` and `check-eval-model-identity.sh`. **Not** `pr-gates`.

### 6. `docs/pipeline-manifesto.md` — the principle (AC-9)
Adds a `gates-signal` bullet to the bucket list at `:132-138` and a pointer to the register. Per P5 it states the principle and does **not** restate the enforcement.

### 7. Obligations paid (AC-10) — each **stated**, including the zeros
- `tools/gate-ablation-classes.tsv`: expected **zero** rows owed — the guard is a CI check, not a `lean-gate.sh` milestone, and all 33 rows are lean-gate milestones. Stated in the verdict rather than silently skipped.
- `scripts/fail-open-sites.tsv`: reconciled by running `check-fail-open-shapes.sh`; expected zero rows owed, per the design call in §3.
- `scenario-liveness-selftest.sh`: a composed leg over the **real** corpus and the **real** guard — a refusal added to a corpus copy reds the guard — plus its **non-vacuity** twin (same tree, row added, green). Fixture-shape cases stay in §4; only the composed path goes here.

### 8. Verification, then the commit
`shellcheck -e SC1091,SC2015,SC2181` over all `.sh` · `jq empty` over all `.json` · `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`.

Commit: `feat: …`, carrying **both** trailers —
- `Changelog:` (or `Changelog: none` if nothing lands under `plugins/**`, which is the current expectation);
- **`Guard-mass:`** — non-optional. `check-guard-budget.sh` classifies both `check-*.sh` and `*-selftest.sh` as guard mass, so this PR raises it and reds without the trailer.

### 9. The PR
Body carries `Closes #636`, links `docs/plans/second-shift-636-lean.md`, and reports the **actual `--list` denominator count**. Not a draft (m5 refuses one).

### 10. `docs/plans/second-shift-636-lean-verdict.md` — the verdict record
**Produced by the review session, in a separate context — not by me.** P10, and `m4/identity` mechanically refuses a build session authoring its own approve verdict. AC-by-AC disposition table. Then close-out: the closing comment on the issue referencing the verdict record, and the build-identity stamp.

---

Two things worth your call before I start: the **`#636` assumption**, and whether the three AC-3 deltas should be resolved as I've proposed (enumerate them, record in the ledger) or bounced back to intake. Everything else follows from what's already settled.
