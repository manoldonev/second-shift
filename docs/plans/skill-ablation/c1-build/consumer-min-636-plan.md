I've surveyed the repo. Before the plan, one blocking fact and two flags.

**The checkout is not usable as-is.** 706 tracked files are deleted in the working tree (unstaged), including four of the five in-scope files — all of `plugins/` and all of `docs/plans/` are gone. `scripts/check-lean-chain.sh` is the only scope file on disk. The files exist in `HEAD` (I read them via `git show`), so step 0 is `git restore` of the deletions. I have not touched the tree.

**Two more flags:** (a) I'm inferring the ticket is **#636** from the working directory name — I'll confirm against the tracker at claim time, since `lean-gate.sh entry` takes the issue number and refuses a wrong one. (b) The precedent this ticket names as its pattern of record, `check-fail-open-shapes.sh`, **is not wired into any workflow** — it exists only behind its own selftest. AC-7 requires my guard to be wired. I'll ship it wired and record the precedent's gap as a residual rather than fix it.

---

# Plan of record — #636

## Phase 0 — pickup

| # | Artifact | Produced by | Contents |
|---|---|---|---|
| 0.1 | Restored working tree | me, `git restore -- .` | Recreates the 706 deleted tracked files from `HEAD`. Nothing is overwritten (they are absent, not modified). |
| 0.2 | Ticket confirmation | me, `gh issue view <n>` | Confirms the number and that intake is paid off — queue label present, or claimed label + a bot-authored `lean-claimed` marker (re-entry). A missing one is a reject, not a prompt. |
| 0.3 | `RUN_ID` export + `<issue>-run-id` cache | `bash G entry <issue>` then `bash G claim <issue>` | `entry` sweeps dead lane worktrees and validates the key; `claim` makes the two bot writes — label swap and the `lean-claimed` marker. These are the tracker-side evidence `check-lean-chain.sh:613` reads at the merge boundary. |
| 0.4 | Lane worktree on `lean/<issue>` | me | Cut from the configured base. Every later gate call runs with `cd` in the same shell invocation. |

## Phase 1 — the spec (milestone 1)

**1.1 `docs/plans/second-shift-636-lean.md`** — mine, and the living definition of done. Path is `lean-gate.sh`'s to print (`$PLANS_DIR/$REPO_SLUG-$ISSUE-lean.md`), not mine to choose. Must contain:

- **AC-1 … AC-10**, carried from the ticket as numbered criteria (milestone 1 reds on zero `AC-n`).
- **`## Decision Ledger`** — `D-n` rows, four columns, ledger-lint-clean. The intake-settled items enter as bound rows, not re-litigated: the fourth enum value `not-a-gate`; AC-5 being register-internal; the `path::name` key adopted unchanged; the five-file corpus with `lean-evidence.sh` non-optional. Plus my own new decisions: the file names (1.2 below) and reading the yield enum from source rather than hardcoding it.
- **`## Open Regions`** — OR-1 and OR-2 as `| ID | Region | Disposition |` rows, both `reversible-default-and-flag`, each with the default taken as written and stated. Neither pauses milestone 1 (`lean-gate-selftest.sh` `(y5)` pins that).
- **`Design: none — <reason>`** (no rendered surface; this is a shell guard and a TSV). The disarm state-locks once milestone 3 arms, so it is decided here.
- A **residual** section naming what is out: the ~19 `scripts/`+`tools/` CI guards, the `.mjs` workflow gates, demotion (#622's axis), non-lane attendance reachability (#631), agent-contract prose.

**1.2 Names decided here** (recorded as a `D-n`, mirroring the precedent's placement in `scripts/`):

- `scripts/check-gate-buckets.sh` — the guard
- `scripts/gate-buckets.tsv` — the register
- `scripts/check-gate-buckets-selftest.sh` — the suite

"Buckets", not "classes", deliberately: `tools/gate-ablation-classes.tsv` already exists, is a different key, and the ticket goes out of its way to say so.

**1.3 `bash G 1 <issue>`** → rc=0 is the only evidence milestone 1 passed.

*If a decision arises here that the ticket's receipt never covered, that is a P9 intent-gap record at `docs/plans/second-shift-636-lean-intent-gap.md`, ratified before the review handoff — `lean-gate.sh:4169` refuses a handoff over one still reading `ratified: no`.*

## Phase 2 — implementation (milestone 2/3)

Produced by me, in this order. **No file in the five-file corpus is edited** — they are read-only inputs to the enumerator, and the self-exclusion is by name inside the guard, as `check-fail-open-shapes.sh:68` does.

**2.1 `scripts/check-gate-buckets.sh`** (new)

- **Header prose** (AC-8): why the register exists; the three buckets plus `not-a-gate` and why the fourth value is what makes the enum closable; **the corpus** (the five files, named); **every self-exclusion, stated** — the helper *definitions* (`fail_milestone`/`envfail`/`ticket_refuse`/`fail_obligation`/`block_milestone`/`note_violation`/`fail`/`terminal`), comment lines, this guard and its selftest, `*.tsv` and `docs/plans/`; and **the out-of-scope residual**. An unstated exclusion is a hole in the denominator claim, so the header is load-bearing, not decoration.
- **`enumerate()`** — per-file primitive lists, not one assumed primitive (AC-3). Prints `path::primitive <TAB> line <TAB> text`, LC_ALL=C sorted. Must match inline `|| envfail …` and `&& fail …` forms, not just line-initial calls — I measured `operator-override.sh` and its `envfail` sites are predominantly inline, so a line-anchored recipe would silently enumerate zero there.
- **`--list`** prints that and exits 0, checking nothing. **That output IS the denominator**; no count is promised in prose.
- **`--help`** via the range-free `sed -n '2,/^# Exit code/p'` idiom, so header edits cannot leak `set -uo pipefail`.
- **Legs, each an independent red** (AC-2):
  1. enumerated site claimed by no row → *unclassified*
  2. row whose anchor no longer appears in its file → *anchor drift*
  3. row whose anchor covers **zero** enumerated sites → *drift; the row outlived its site* (AC-4)
  4. unknown bucket value → error (AC-1, closed enum)
  5. **AC-5, register-internal**: `gates-llm` / `gates-signal` / `not-a-gate` MUST carry an empty yield cell; a yield cell naming an `OVERRIDE_GATES`/`OVERRIDE_SCOPES` value MUST be `gates-process`
  6. **AC-6, form only**: a `gates-process` yield is either an enum value or `unwired — <reason>` — never "does a follow-up ticket exist"
  7. **AC-1**: a `not-a-gate` row's `why` states what it is instead — environment refusal, usage error, or success path
- **Covered-site count printed per row** (AC-4), so a loose anchor that would swallow a future refusal is visible rather than silent.
- **The yield enum is read from `plugins/dev-pipeline/tools/operator-override.sh:182-183` at runtime**, not hardcoded — an unreadable source is an error, never an empty enum that passes vacuously. This is the one place I extend the precedent, and it gets its own `D-n`.
- Exit code = violation count (doctor convention). bash-3.2-safe; `awk` values passed via `ENVIRON`, never `-v`, for the same backslash reason `check-fail-open-shapes.sh:135-139` documents.

**2.2 `scripts/gate-buckets.tsv`** (new) — the register.

- Header block modelled on `fail-open-sites.tsv`: the column contract, the **closed** enum, "the anchor is text, never a line number, and here is why", and **"THE COUNT IS NOT THE CONTRACT"** — `--list` is the denominator and this file must cover it exactly.
- Columns: `key(path::primitive) <TAB> bucket <TAB> anchor <TAB> yield <TAB> why`. The key adopts the triage record's `path::name` format unchanged, per intake.
- Rows: one per enumerated site (AC-4), with **OR-1's default applied** — `envfail` sites get one row per class rather than ~95 mechanical rows, and AC-4's covered-count printing is what keeps that honest.
- Section comments grouping by bucket, so a reader sees the shape: the merge-boundary verdict/identity/ratification/patch-id arms in `lean-evidence.sh` and `check-lean-chain.sh` as `gates-llm`; the eight the ticket names (`m2/frozen-files`, `m2/changelog-trailer`, `m3/lint`, `m3/typecheck`, `m3/test`, `m3/extra-lane`, `m3/setup-lane`, `m3/no-verify-lane`) as `gates-signal`; `intake-unqueued` and `spec-open-region` as the only two wired `gates-process` rows, every other `gates-process` row `unwired — <reason>`; `not-a-gate` for `operator-override.sh`'s usage/environment refusals and `orchestrate-lean.sh`'s success-path `terminal … 0` calls at `:764`/`:923`/`:982`.
- A `gates-process` row whose consumer sits outside the lean lane **cites #631** rather than pretending the path works.

**2.3 `scripts/check-gate-buckets-selftest.sh`** (new) — fixture trees under `mktemp`, each handed to the real guard as its repo root; no production file written; no `gh`, no network. One case per AC-2 arm (unclassified / drift / row-outlived-its-site), one per AC-5 direction (wrong-bucket-carries-yield, yield-value-in-wrong-bucket), one per AC-1 and AC-6 form check, the covered-count print, **and the all-green arm**. Plus negative cases pinning what the recipe must **not** enumerate — helper definitions, comments — because a scanner that reds on its own definitions gets baselined away in a week. Glob-discovered; no registration needed. Directory-scoped same-stem naming satisfies the mutation sweep's universe rule with no `mutation-pair-map.tsv` row.

**2.4 `.github/workflows/ci.yml`** — one step in the always-on guard job (the one carrying `check-lockstep-pairs.sh` at `:143` and `check-eval-model-identity.sh` at `:149`), with the comment those steps carry explaining why a register guard needs an explicit invocation. **Not** `pr-gates` (AC-7).

**2.5 `docs/pipeline-manifesto.md`** — the bucket list at the section *"Where a gate may yield to a present human, and where it may not"* gains `gates-signal` between the two existing entries, and a pointer to `scripts/gate-buckets.tsv`. Per P5 it states the principle and does **not** restate the enforcement.

**2.6 Obligation reconciliation (AC-10)** — three checks, each of which may legitimately come out *nil*, and a nil result is stated with its evidence rather than silently skipped (this is exactly how `docs/plans/second-shift-613-lean-verdict.md:130` discharged the same clause):

- `tools/gate-ablation-classes.tsv` — a row per **new refusal reason**. I expect nil: `lean-gate.sh`'s milestone 2 runs only `check-frozen-files.sh` and `check-changelog-trailer.sh`, and AC-7 puts this guard in CI, not in a milestone lane. If that holds, the plan records "no row owed, because no gate emits a new reason" with the grep behind it.
- `scripts/fail-open-sites.tsv` — new fail-closed branches reconciled. The guard adds `| grep` sites; any that match the `pipeline` leg's shape get a row, otherwise `check-fail-open-shapes.sh` is re-run and its unchanged site count recorded as the evidence.
- `plugins/dev-pipeline/skills/build-lean/scenario-liveness-selftest.sh` — extended for **every verdict path touched**, with a non-vacuity case. Expect nil if the corpus stays read-only as designed; **if any production edit creeps in, this is not optional** and the scenario extension lands with it.

**2.7 Commits** — through `bot-commit.sh` (identity re-passed on any `--amend`). Trailers:

- `Guard-mass: +<n> — <reason>`. **Mandatory**: `check-guard-budget.sh`'s `is_guard_path()` counts `check-*.sh` and `*-selftest.sh`, so both new files are guard mass and the PR reds without it.
- `Changelog: …` or `Changelog: none`.
- Verb `feat(...)` — a new capability, per CLAUDE.md's "use the honest verb"; typing it `chore:` silently downgrades the release.

**2.8 `bash G 2` then `bash G 3`** — rc=0 each. Local verification first, the CLAUDE.md recipe:

```
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh
```

plus the two register-specific runs that are the actual proof: `bash scripts/check-gate-buckets.sh --list` (the denominator) and `bash scripts/check-gate-buckets.sh` (green against the real tree).

## Phase 3 — handoff

| # | Artifact | Produced by |
|---|---|---|
| 3.1 | Cost block | `pipeline-cost-block.sh --stateless --issue <issue>` — derived, never reconstructed |
| 3.2 | **Ready (non-draft) PR** | me: summary, spec link, `Closes #<issue>`, cost block in the description, **OR-1/OR-2 defaults flagged in the body** as `reversible-default-and-flag` requires, and the precedent-is-unwired observation recorded as a residual |
| 3.3 | Bot PR marker | `bash G mark <issue>` — at step 7, not at milestone 5: a comment posted after the review's push fires no `pull_request` event and is invisible to the gating CI run |

## Phase 4 — review (**not mine**)

**4.1 `docs/plans/second-shift-636-lean-verdict.md`** — authored by a **separate top-level session**, `/dev-pipeline:review-lean <pr>`, with its own `run_id` and `session_id`. I dispatch no reviewer and interpret no finding. `check-lean-chain.sh:636`/`:641` red if the build run or build session authored it (P10).

`bash G 4 <issue>` passes only on a committed `verdict=approve` whose `reviewed_patch_id` **is** this branch's current patch. On `needs-work`: fix every blocker, push, request a **new** review context — never a resumed one. Any content pushed after an approve reopens milestone 4.

## Phase 5 — close-out and merge

- `bash G all <issue>` — re-evaluates everything against the current tree. Mandatory before close-out; a milestone satisfied before a fix round is stale.
- `bash G close-out <issue>` — one call, none of it mine to compose: recomputes the published figure, writes the `cost-log.jsonl` row, replaces the stale PR cost block, posts the single closing comment, asserts milestone 5, tears down the worktree (never the branch). The claimed label stays; the unclaim workflow releases it on close.
- **Merge boundary** — `lean-chain reconciliation` (ci.yml:337) → `check-lean-chain.sh` → `lean-evidence.sh` for the verdict/identity/ratification/patch-id arms; `pr-gates`; `mutation-sweep-pr`; both selftest jobs; `guard budget guard`; and the new guard step from 2.4 running against the real tree.

---

**Definition of done:** `check-gate-buckets.sh` exits 0 against the real tree, its `--list` output is fully covered by `gate-buckets.tsv`, each of the three disagreement arms plus both AC-5 directions reds independently under the selftest, the step is green in CI's guard job, and the manifesto names `gates-signal` without restating the enforcement.

Stopping here as instructed — nothing implemented, nothing written, tree untouched.
