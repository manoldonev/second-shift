# lean review verdict — #348

verdict=needs-work
run_id: review-348-2
session_id: c9356284-c208-4d7c-825f-f9062b5fe24b
rounds: 2
pr: #568
reviewed_head: 74562a06658deab7442a99cf0a7d7034d68b0160
reviewed_patch_id: c20ccc39703802f56efc473965de5abad6381356
inherited_patch_id: d558b5da579f293ff16d22427b603b714ba19675
inherited_from_verdict: ae7c47c850317021e0810d26ac4398d5e93b7970
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 2 over the delta `ae7c47c..HEAD` (11 files, +78/−30), inheriting round 1's coverage of
`33e6187..7047b83` by reference to the committed round-1 record. Read wider than the range where
the delta looked misleading: the whole-tree orphan sweep, the relative-link resolution over every
shipped `.md`, and the pin literal against the tag list are branch-wide reads, because a deletion's
blast radius is not diff-shaped.

**All five round-1 blockers are closed, and all six warnings with them.** Verified individually, not
taken from the PR body — see the closure table. The commit that closed them is careful work: it
adopted round 1's reasoning rather than just its remedies, and the AC-1 restatement is now exactly
true (I ran the check as specified and got precisely the seven declared classes, no eighth).

The blockers below are new, and they are the same defect one more layer out. AC-1's orphan check is
a **path-prefix grep for `skills/run/`**. This change broke three kinds of reference, and that key
only sees the first:

| Kind of reference | Caught by the `skills/run/` grep? |
| --- | --- |
| a **path** into the deleted tree | yes — swept clean, twice |
| a **slash command** (`/dev-pipeline:run`) | **no** — the token contains no path |
| a **relative link** whose depth changed under relocation | **no** — the link text is unchanged; only its resolution moved |

Both blockers are instances of AC-6 as this round amended it — and the amendment names both classes
by name ("shipped plugin docs whose copy-pasteable commands … moved", "relocated-verbatim docs whose
sibling links no longer resolve"). Neither is exotic: one lands in a file whose sibling this very
commit fixed, the other in two files this commit opened.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | **Blocker** | 5 tracked files / **AC-6** | The deleted **slash command** `/dev-pipeline:run` is still advertised in shipped, consumer-facing artifacts. `plugins/second-shift/templates/consumer/SECOND-SHIFT.md:15` is the sharpest: it is the onboard template **copied into every consumer repo**, and it lists `` `run` (the 10-stage ticket→PR state machine, invoked as `/dev-pipeline:run`, deprecated — kept as an ablation/rollback lane) `` among dev-pipeline's skills. From this release on that skill does not exist, so onboard writes a false skill inventory into every repo it touches. `plugins/dev-pipeline/tools/tracker/jira/README.md:37` is the second sharp one — the **pickup row of the JIRA adapter contract** reads `(/dev-pipeline:run GH-540)`; under jira there is no queue, so that row *is* the documented entry point, and it names a command that is gone. Its sibling `tools/tracker/README.md` **was** fixed in this same commit; the `jira/` copy relocated at `similarity index 100%` and was not re-read — precisely the failure mode `74562a0`'s own message documents for four other relocated docs. Also: `plugins/second-shift/skills/onboard/SKILL.md:155` ("the first `/dev-pipeline:run` pre-flight will fail until one exists"), `plugins/dev-pipeline/skills/pipeline-retro/SKILL.md:3` (the frontmatter `description:` — the string the harness shows in the skill listing — "Run after a `/dev-pipeline:run` run completes (or aborts)"), and `.claude/SECOND-SHIFT.md:23`, this repo's own tracked dogfood record. **Three of the five are files this branch already edits** (`onboard/SKILL.md`, `pipeline-retro/SKILL.md`, `tracker/jira/README.md` each have one commit on the branch) — the sweep opened them and missed the line, because it was looking for a path. Lower-stakes sixth site, same class: `.github/ISSUE_TEMPLATE/pipeline-aborted.yml:17`'s placeholder. Remedy: re-point all six, and widen AC-1's check to the command literal alongside the path prefix. |
| 2 | **Blocker** | `plugins/dev-pipeline/tools/tracker/README.md:42,46,55` / **AC-6** | Three markdown links that **resolved before the move and do not now**, in the file round-1 warning 8 was about — half-swept. `[lean-gate.sh](../../../build-lean/lean-gate.sh)` (`:42`) and `[lean-reconcile.sh](../../../build-lean/lean-reconcile.sh)` (`:46`, `:55`) were correct from `skills/run/tools/tracker/` (`../../../` reached `skills/`); from `tools/tracker/` the same text resolves to `plugins/build-lean/`. **The targets survive** — `plugins/dev-pipeline/skills/build-lean/lean-{gate,reconcile}.sh` are both present — so this is pure relocation-depth rot, fixable by re-pointing, and it is not the "no path to re-point to" case that earned `state-schema.md` a banner. Verified against the base: `git cat-file -e 33e6187:plugins/dev-pipeline/skills/build-lean/lean-gate.sh` resolves, so the links worked at `33e6187` and this branch broke them. This file is the tracker adapter contract that `build-lean/SKILL.md`, `review-lean/SKILL.md` and `lean-gate.sh` all send readers to. (Its fourth broken link, `../../../../../docs/context-model.md`, was **already broken at the base** — pre-existing, not yours.) |
| 3 | Warning | `plugins/dev-pipeline/tools/tracker/github/README.md`, `.../jira/README.md` | The same relocation left four links pointing into the **deleted** tree — `github/README.md` → `../../../SKILL.md`, `../../../stages/1-intake.md`, `../../../stages/9-open-pr.md`; `jira/README.md` → `../../../stages/2-worktree.md`. All four resolved at `33e6187` (verified), so this branch broke them. Unlike finding 2 there is nothing to re-point *to*, which is exactly the situation `state-schema.md` was given a historical banner for in this same commit — and the reasoning that earned it one applies here verbatim. These two got neither a banner nor a note, so a future reader will try to "fix" links that exist to name what was removed. Not a blocker only because the adapter contract's *substance* is unaffected; the treatment should match its sibling's. |
| 4 | Warning | `plugins/dev-pipeline/tools/stage-times-fixtures/acme-89-pause.json:2` | Relocated at `R100` with a stale copy-pasteable command in its `_fixture` field: `Read it with: STATECTL_STATE_DIR=docs/eval-fixtures bash .claude/skills/run/tools/stage-times.sh acme-89-pause`. Two of the three parts are wrong — `stage-times.sh` moved to `plugins/dev-pipeline/tools/` (its own `:18` usage line **was** correctly re-pointed to `${CLAUDE_PLUGIN_ROOT}/tools/stage-times.sh` in this branch), and `docs/eval-fixtures` does not exist (that half was already stale at base). Same class as round-1 warnings 6–8, one instance further out. Nothing executes the string, and `stage-times.sh` itself is properly covered (`stage-envelopes-selftest.sh` is its external executor, and `tools/mutation-pair-map.tsv:28` records that) — so this is documentation rot, not a coverage hole. |
| 5 | Nit | `plugins/dev-pipeline/skills/pipeline-retro/SKILL.md:37` | `S=../dev-pipeline/statectl.sh` — a dead assignment to a deleted script, in an operator-facing copy-paste block. Inert and honestly declared (the PR body says the `era: "stage"` arm "assigns `S=` but reads the historical corpus as raw state JSON via `cat`/`jq` — it never calls `statectl`", which I verified: `$S` is referenced nowhere in the file). Worth deleting rather than keeping, because the line immediately below it — `bash ../dev-pipeline/tools/stage-times.sh` — **was** re-pointed by `61a85b7`, so the same pass touched this block and left a reader the impression that `statectl.sh` is still resolvable. |
| 6 | Nit | `plugins/dev-pipeline/workflows/null-reviewer-selftest.mjs:25` | "Mirrors the conventions of `statectl-selftest.sh`" — names a file this PR deletes, with no `#348` annotation, unlike the dozen other such comments in the tree (`check-bounded-exploration-selftest.sh:277,290,293`, `text-contract-selftest.sh:44`, `check-model-tiers.sh:53,373,398`, `diff-range-selftest.sh:109`, `pipeline-doctor.sh:426` all say so explicitly). Its `:28` sibling line **was** fixed by this commit (round-1 nit 11), so the file was open. One clause. |

## Acceptance criteria

| AC | Verdict | Evidence |
| --- | --- | --- |
| **AC-1** — sweep green, shellcheck/jq clean, orphan check | **satisfied** | CI at this head: `lint-and-selftests` pass 3m43s, `selftests (macos, bash 3.2)` pass 5m37s, `mutation-sweep-pr` pass (29s — correct, this delta contains no `.sh` guard to sweep). I re-ran the orphan check **exactly as AC-1 now specifies** (`*-selftest.sh` + `tools/*.tsv` + `scripts/*.tsv` + `lockstep-manifest.tsv` + `.github/workflows/*.yml`, literal `skills/run/`): the hit set is `capability-parity.tsv`×37 (class 1), `capability-parity-check-selftest.sh:42,51,195` (class 2), `is-inert-diff-selftest.sh:74` + `pre-commit-typecheck-selftest.sh:73,74` (class 3), `pipeline-doctor-selftest.sh:687,693` (class 4), `check-bounded-exploration-selftest.sh:389` + `workflows-mjs-selftest.sh:13` (class 5), `ci.yml:168,174` (class 6) — **exactly the seven declared classes with no eighth**, and the body's "9 hits outside the two exemptions" is exact. Round-1 finding 10 is fully closed: the claim now says what the check verifies. Findings 1–2 are **not** scored here — a slash command and a link depth are not paths, so AC-1's oracle cannot see them by construction; they are AC-6's. |
| **AC-2** — no register row names a deleted guard | **satisfied** | Re-verified independently at this head: every `skills/run` token in `mutation-{baseline,catalog,pair-map}.tsv` is `skills/run-lean/`, not the deleted `skills/run/`. Both prose-budget baselines carry **zero** `skills/run/` rows — the row-by-row re-pointing the spec claims is real, and #561's `prose-budget-shell.baseline.tsv` is re-keyed too. |
| **AC-3** — keep list, demotion register, D-3 override, pin in the body | **satisfied** | All present from round 1 and unchanged. Pin literal now verified rather than accepted: `v5.2.2` is the newest tag **and** carries `plugins/dev-pipeline/skills/run` (`git ls-tree -d v5.2.2` resolves), so it is genuinely the last stage-carrying release. The at-merge half (recording it on #348, re-confirming no later release landed) stays a merge precondition, which AC-3's own wording licenses. |
| **AC-4** — frozen-files green; breaking verb; `Changelog:` + `Migration:` naming the pin and the moved `config-lint.sh` | **satisfied** | Round-1 blocker 2 closed on both halves, in the place that matters. The **PR title** is `feat(dev-pipeline)!: delete stage choreography from main` — load-bearing, because this repo squash-merges and `derive-release.sh:141` matches `^[a-z]+(\([^)]*\))?!:` against the squash subject, which is the title. `74562a0` additionally carries a `BREAKING CHANGE:` footer and a real `Changelog:` trailer whose `Migration:` line names **v5.2.2** and the `skills/run/tools/config-lint.sh` → `tools/config-lint.sh` move. Frozen half holds: `marketplace.json` and `plugin.json` both still read `5.2.2` (main's), `CHANGELOG.md` untouched. |
| **AC-5** — `capability-parity-check.sh` green, coverage clause vacuous | **satisfied** | Unchanged from round 1 and structurally intact: `capability-parity-check.sh:55` still resolves `STAGES_DIR="$ROOT/plugins/dev-pipeline/skills/run/stages"`, which is absent, so the clause reports vacuous rather than violated — the success condition its LIFETIME note declares. |
| **AC-6** — every doc naming deleted machinery updated in the same diff | **unsatisfied** | Findings 1 and 2. The three docs AC-6 names **by name** that round 1 blocked on — `docs/pipeline-manifesto.md`, `docs/config-schema.md`, `README.md` — are all correctly fixed (verified: every relative link in all three resolves, the manifesto's P1/P2 posture is rewritten past tense with the pin re-pointed at the `Migration:` trailer, and `config-schema.md:21`'s dead `stages/6-verify.md` link now points at the surviving `LOCKSTEP-BEGIN seam-scrub` block in `lean-gate.sh:3016`, which exists). What is unmet is the **class** this round's own amendment brought into AC-6: a shipped template and a shipped adapter contract still advertise the deleted command, and a relocated adapter contract's links no longer resolve. |
| **AC-7** — `visualCapture` retirement follows the dead-key pattern | **satisfied** | Unchanged from round 1; nothing in the delta touches it. |

## Design fidelity

`not-applicable`. The spec disarms with `Design: none — no design.provider is configured for this
repo, and the diff has no UI surface`. Re-verified at this head rather than inherited: `jq
'{design, webGlobs: .stageParams.webComponentGlobs}'` on the effective config returns `null` for
both, and the round-2 delta is `.md`/`.yml`/`.mjs`-comment only. The disarm is justified.

## Panel

Six reviewers selected, six returned — no dark reviewer, no coverage gap. `db-reviewer`,
`pipeline-reviewer` and `unit-test-mutation-reviewer` were not triggered (no DB, no queue surface,
no co-located specs). `a11y-reviewer` and the design-fidelity dimension were not routed: no changed
path matched `stageParams.webComponentGlobs` (unset, so the default `apps/web/**/*.{tsx,jsx}`).

Security, performance, maintainability, complexity and test-coverage returned clean.
`scope-completeness-reviewer` returned `request-changes` and independently found finding 1 — its
gate is hard, but it stands on its merits: I confirmed all five sites with `git ls-files
--error-unmatch` and re-read each in context, and it undercounted by one (`pipeline-aborted.yml`).
Finding 2 is the round's own; so are 3, 4, 5 and 6. Finding 2 is the one the panel structurally
could not reach — `tools/tracker/github/README.md` and `jira/README.md` are `R100` relocations with
zero content delta, so they appear in no diff-scoped reviewer's window at all, and `tracker/README.md`
appeared only as its two `gh-bot.sh` lines.

## What is not a finding

- **The spec amendment.** A spec amended to match the diff is a blocker; this is the opposite
  shape. Diffed across its own commits: AC-1's restatement is round-1 finding 10's **prescribed
  remedy** (round 1 wrote "the claim is over-stated" and the amendment states what is verified), and
  AC-6 was **widened**, bringing four files previously outside its enumerated list into scope. An
  amendment that makes the definition of done stricter and more honest is licensed. It is also what
  makes findings 1 and 2 scoreable against AC-6 at all.
- **`pr-gates` red.** The `lean chain reconciliation` arm reporting `verdict record … reads
  'verdict=needs-work'` — the round-1 record, which this round replaces. It names its own reason.
  Every other check is green.
- **The pin not yet on #348, and the OR-2 FE canary.** Both are AC-3/D-11 **merge preconditions**,
  already enumerated in the PR body. A remedy that lives outside the tree is not a review round.
- **The D-3 `statectl` override and the `visualCapture` no-bump.** Re-verified, both grounded,
  both flagged rather than silent — round 1's assessment stands and the scope reviewer reached it
  independently. Deleting `statectl.sh` costs `pipeline-retro`'s stage-era arm nothing: it reads the
  historical corpus through `cat`/`jq` (finding 5 is only the dead `S=` line left behind).
- **`state-schema.md`'s six dead links.** Deliberate, and the banner this commit added says so —
  every sibling it links is deleted, so there is no path to re-point to. Verified the banner's
  claims rather than taking them: `statectl.sh`, `verifyctl.sh`, `plan-scope-paths.sh`,
  `gen-statectl-validators.sh` and `plan-lint.sh` are all genuinely absent from the tree.
- **Four other broken links in shipped docs.** `tracker/README.md → ../../../../../docs/context-model.md`,
  `pipeline-retro/SKILL.md → ../../agents/retro-scorer.md` and `→ ../dev-pipeline/eval-criteria.md`,
  `review-lead-eval/README.md → ../../../docs/eval-fixtures/review-lead/` — all four verified broken
  **at `33e6187`** too. Pre-existing, not this PR's to fix.

## Verdict

`needs-work` — two blockers, both AC-6, both cheap. Finding 1 is six one-line edits plus widening
AC-1's check to the command literal. Finding 2 is three link paths in one file (`../../../build-lean/`
→ `../../skills/build-lean/`). Finding 3 is a banner copied from the one `state-schema.md` already
carries.

The deletion itself remains careful, and the round-1 response was genuinely good work — five of five
blockers and six of six warnings closed, each by understanding the finding rather than pattern-matching
the remedy, and AC-1's honesty fix is exactly right. What is left is not a new class of mistake; it is
the same class at the two reference kinds a path-prefix grep cannot see. Widening the check is worth
more than fixing the six sites, because the next relocation will have the same blind spot.
