I read the precedent, the corpus, and the CI wiring before planning. One blocker first.

## Blocker — the working tree is missing `plugins/`

All 374 files under `plugins/` and `.claude-plugin/` are deleted in the working tree (every entry in `git status` is a ` D`; there are no modifications). Three of the five corpus files live there, as does `scenario-liveness-selftest.sh`. I tried `git restore plugins` and `git checkout -- .` — both were denied by the permission layer, and this session is non-interactive so I cannot get approval here.

**I need you to run `git checkout -- .` (or approve it) before implementation starts.** Nothing is lost by it — every change in the tree is a deletion of a committed file. My measurements below were taken with `git show HEAD:<path>`, which works around the deletion for reading but not for editing.

---

## Plan of record

### Naming decision (mine, stated up front)

`scripts/check-gate-buckets.sh` + `scripts/gate-bucket-register.tsv` + `scripts/check-gate-buckets-selftest.sh`. Mirrors the `check-fail-open-shapes.sh` / `fail-open-sites.tsv` / `-selftest.sh` triple exactly. It lives in `scripts/` (not `plugins/dev-pipeline/tools/`) because it is a repo-wide CI guard whose corpus straddles `scripts/` and `plugins/`, and because AC-7 wires it into the repo-level `lint-and-selftests` job. "Buckets" rather than "classes" keeps it verbally distinct from `tools/gate-ablation-classes.tsv`, which the ticket is emphatic is *not* the key.

### Phase 0 — lane setup (producer: me, driving `lean-gate.sh`)

| # | Artifact | Where | Contents |
|---|---|---|---|
| 0.1 | `entry` + `claim` calls | tracker + `<issue>-run-id` cache | `bash G entry 636`, export `RUN_ID`, `bash G claim 636`. Label swap + bot-authored `lean-claimed` marker. Skip `claim` if re-entering. |
| 0.2 | Lane worktree | `<lean prefix>636` off the configured base | Cut before any edit. |

`bash G 1 636` prints the exact spec path it demands; I use that, not a guessed one.

### Phase 1 — the spec (producer: me; artifact 1.1)

**`docs/plans/second-shift-636-lean.md`** — written *before* code, at the path milestone 1 prints. Must contain:

- The `AC-1`…`AC-10` set restated as this lane's definition of done, plus a `## Decision Ledger` carrying any pre-flight `636-ledger.md` rows under their original `D-n` ids (projected with `ledger-carry-forward.sh`, not retyped).
- `Design: none — this slice ships a shell guard and a TSV; no rendered surface.`
- **Two decision rows recording measurement corrections to AC-3** (see "Measurement deltas" below) and **one recording my AC-7 reading**: the literal requirement is that *this* guard runs in the always-on job; wiring `tools/prose-blockers.sh check` is a different register (prose constructs, not gates) and I am treating it as out of scope, flagged not silently dropped.
- OR-1 and OR-2 recorded as taken at their `reversible-default-and-flag` defaults, with the flag text.

Then `bash G 1 636`.

### Phase 2 — implementation, in this order

**2.1 `scripts/gate-bucket-register.tsv`** (data first, so the guard is written against a real table).

Six tab-separated columns: `file <TAB> disposition <TAB> anchor <TAB> yield <TAB> why`— plus a header comment block. Header must state, per AC-8:
- the closed enum `gates-llm | gates-signal | gates-process | not-a-gate` and what each means;
- the anchor rule (distinctive substring of the site's **line text**, never a line number — the precedent's reasoning, restated);
- **every self-exclusion by name**: the helper *definitions* `lean-gate.sh:379 envfail()`, `:676 ticket_refuse()`, `:1583 fail_obligation()`, `:1751 fail_milestone()`, `:1791 block_milestone()`; `check-lean-chain.sh:193 fail()`, `:194 envfail()`, `:478 note_violation()`; `lean-evidence.sh:165 envfail()`, `:168 note_violation()`; `operator-override.sh:60 envfail()`; `orchestrate-lean.sh:324 terminal()` and `:336 envfail()` (the latter is a definition that *delegates* to `terminal … 2` and would otherwise enumerate as a live non-zero site);
- **the out-of-scope residual named**: the ~19 `scripts/`+`tools/` CI guards and the `.mjs` workflow gates, and the #631 pointer for any `gates-process` row whose consumer sits outside the lean lane;
- the AC-5 safety rule as prose next to the mechanism that enforces it.

Row population per OR-1's default: one row per site for `fail_milestone` / `block_milestone` / `ticket_refuse` / `fail_obligation` / `note_violation` / `fail` / `terminal`; **one row per class** for `envfail`, with narrower per-class anchors wherever a class splits across dispositions. Expect **~150–200 rows** against **~300 enumerated sites** — that is the honest number given the measurements below, not the ticket's implied scale.

**2.2 `scripts/check-gate-buckets.sh`** — the guard. Structure lifted from the precedent:

- `--list` prints `relpath<TAB>lineno<TAB>text`, sorted, exits 0, **checks nothing** (AC-2).
- `--help` uses the precedent's range-free `sed -n '2,/^# Exit code/p'` idiom.
- `enumerate()` — one `grep -rnE` per file with that file's own primitive alternation, then the named self-exclusions stripped by function-definition shape. `orchestrate-lean.sh`'s arm additionally requires a **non-zero second argument** to `terminal`, and separately enumerates `terminal … 0` sites so they land as `not-a-gate` rows rather than vanishing (AC-3).
- Three **independent** reds, each its own `fail()` call so they accumulate rather than short-circuit: (a) enumerated site with no covering row; (b) anchor present in no line of its file — drift; (c) row whose anchor covers **zero** enumerated sites.
- Row validation: field count exactly 5 (counted on the raw line, so an empty yield cell is legal and a missing one is not); disposition in the closed enum, unknown value is an error; `not-a-gate` rows must have a `why` naming which of *environment refusal / usage error / success path* it is.
- **AC-5, register-internal**: `gates-llm`, `gates-signal` and `not-a-gate` rows must have an **empty** yield cell; any row whose yield cell names a token from `OVERRIDE_GATES`/`OVERRIDE_SCOPES` must be `gates-process`. The two enums are read from `plugins/dev-pipeline/skills/build-lean/lean-evidence.sh:993-994` rather than re-declared — a third hand-kept copy is exactly what `check-lockstep-pairs.sh` exists to prevent.
- **AC-6**: every `gates-process` yield cell either matches an `OVERRIDE_GATES`/`OVERRIDE_SCOPES` token or matches `^unwired — .+`. Form only; no follow-up-ticket existence check.
- **AC-4**: the clean verdict line prints the covered-site count **per row**, so a loose anchor is visible.
- Exit code = violation count (doctor convention).

**2.3 `scripts/check-gate-buckets-selftest.sh`** — fixture trees under `mktemp`, each handed to the real guard as its repo root; no production file written; bash-3.2-safe; no `gh`, no network. Cases:

- `(g0)` **the real tree** — the same case the precedent uses to make the guard non-vacuous even before CI wiring.
- One case per AC-2 arm, each firing **alone**: undispositioned site; anchor drift; row covering zero sites.
- The all-green arm.
- AC-1: unknown disposition value is an error; `not-a-gate` with no "what it is instead" reason is an error.
- AC-5 both directions: a `gates-signal` row carrying a yield value reds; a row naming `intake-unqueued` typed anything but `gates-process` reds.
- AC-6: a `gates-process` row whose yield is neither an enum token nor `unwired — …` reds.
- AC-3 negative direction: `terminal … 0` **is** enumerated; every named helper definition is **not**.
- `--list` gates nothing (exit 0 on a fixture that would otherwise red).

### Phase 3 — obligations (AC-10 and the repo's standing ones)

| # | Artifact | Where |
|---|---|---|
| 3.1 | A row per new refusal reason string | `tools/gate-ablation-classes.tsv` — only if 2.2 emits reasons through a `lean-gate.sh` milestone. It does not today; the guard is a CI script. I will state that explicitly in the verdict record rather than leave the obligation looking unexamined. |
| 3.2 | Reconcile new fail-closed branches | `scripts/fail-open-sites.tsv` — the corpus files have **zero** rows there today. If 2.2 introduces a `\| grep -q` site, it gets a row; the target is a green `check-fail-open-shapes.sh`. |
| 3.3 | Scenario extension + a non-vacuity case | `plugins/dev-pipeline/skills/build-lean/scenario-liveness-selftest.sh` — for every verdict path touched. This slice adds a CI-boundary verdict, so the scenario asserts the guard's red reaches the composed merge-boundary refusal, plus one case that fails when the assertion is removed. |
| 3.4 | Three mutation-catalog rows | `tools/mutation-catalog.tsv` — one per independent red arm, the shape `fail-open-unclassified` / `-anchor-drift` / `-pgrep-leg` already establishes at lines 100-102. Each names the regression class it alone catches. |
| 3.5 | CI wiring | `.github/workflows/ci.yml`, job `lint-and-selftests` (line 17), as a step beside `check-lockstep-pairs.sh` (:143) and `check-eval-model-identity.sh` (:149). **Not** `pr-gates` (:228). |

### Phase 4 — docs (AC-9)

**4.1 `docs/pipeline-manifesto.md`**, the "Where a gate may yield" section (the bucket bullets sit at ~:127-135). Add the `gates-signal` bullet between `gates-llm` and `gates-process`, and a one-line pointer to `scripts/gate-bucket-register.tsv`. **Per P5 it states the principle and does not restate the enforcement** — no description of the three reds, no guard invocation.

### Phase 5 — verification, before the PR

```
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh
bash scripts/check-gate-buckets.sh          # and --list, committed into the verdict record
bash scripts/check-fail-open-shapes.sh
bash scripts/check-lockstep-pairs.sh
bash tools/mutation-sweep.sh                # diff-scoped; an unbaselined survivor is a red
```

Then `bash G 2 636` and `bash G 3 636`.

### Phase 6 — commit and PR

**6.1 Commits**, all through `bot-commit.sh`. The lead commit message carries **three** trailers:

- `feat(dev-pipeline): …` — per CLAUDE.md, a new capability in this repo is `feat:`, not `chore:`.
- `Changelog: …` — mandatory, `plugins/**` is touched by 3.3.
- **`Guard-mass: …`** — mandatory and easy to miss. `check-guard-budget.sh:38-42` classifies both `check-gate-buckets.sh` and `check-gate-buckets-selftest.sh` as guard mass by basename, so this PR increases it and reds without the trailer.

No version bump, no `CHANGELOG.md` edit — `check-frozen-files.sh` rejects both.

**6.2** Cost block via `pipeline-cost-block.sh --stateless --issue 636`; ready (non-draft) PR with summary, spec link, `Closes #636`, cost block in the description. Then `bash G mark 636`.

### Phase 7 — review and close-out

**7.1 `docs/plans/second-shift-636-lean-verdict.md`** — produced by a **separate** top-level session (`/dev-pipeline:review-lean <pr>`), never by me; P10 forbids the build run authoring its own evaluation. It carries the per-AC table and the live `--list` count as the AC-2 evidence.

**7.2** `bash G all 636`, then `bash G close-out 636` — one call, writes the cost row, replaces the stale block, posts the closing comment, asserts milestone 5, tears down the worktree. Leave the `claimed` label alone.

---

## Measurement deltas — AC-3's numbers are partly stale

I measured the corpus at HEAD. Four disagreements, all of which I will follow the tree on and record as decision rows in the spec:

1. **`check-lean-chain.sh` `envfail` is unnamed by AC-3** but has ~14 call sites (`:226, 392, 394, 396, 398, 401, 409, 426, 457, 559, 562, 572, 674, 860, 865`). AC-3's own rule — "names *every* refusal primitive per file rather than assuming one" — requires enumerating it. I will.
2. **`lean-evidence.sh` has no primitives listed in AC-3 at all**, despite the ticket's insistence that its inclusion "is not optional." Measured: `envfail` (23 occurrences) and `note_violation` (17). I will enumerate both.
3. **`check-lean-chain.sh` `fail`**: AC-3 says 2. I find one definition (`:193`) and **one** call site (`:475`). If AC-3 was counting occurrences including the definition, we agree; if it meant two call sites, the tree says otherwise.
4. **`orchestrate-lean.sh`'s success calls are not at `:764`/`:923`/`:982`.** `terminal … 0` today sits at `:849`, `:854`, `:955`, `:972`, `:1139`, `:1198` — six, not three, two of them the dry-run pair. Anchors are text so nothing breaks, but the register will carry six `not-a-gate` success-path rows rather than three.

None of these change the design; they change the row count, and they are exactly why AC-2 makes `--list` the denominator rather than any number written in a ticket.

Nothing implemented. Say the word on the `git checkout -- .` and I'll start at Phase 0.
