# lean review verdict — #348

verdict=needs-work
run_id: review-348-3
session_id: a9092cec-70fa-4d4c-ac51-32676cf478d6
rounds: 3
pr: #568
reviewed_head: 469d37dfd9772304c1a9d608eabbec1e89a73f3d
reviewed_patch_id: bd8238bc7c30327dcb23098683a8239da9bcbf55
inherited_patch_id: c20ccc39703802f56efc473965de5abad6381356
inherited_from_verdict: 0a2046829083321ec388d5613efd58bf9638ff7a
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 3 over the delta `0a20468..HEAD` (15 files, +203/−82), inheriting rounds 1–2 by reference to
the committed round-2 record. Read wider than the range wherever the delta looked misleading: all
three orphan-check kinds whole-tree, the relative-link resolution at head **and** at the merge-base,
every `${CLAUDE_PLUGIN_ROOT}`-anchored path in the tree, and the two config surfaces AC-6 names.

**Both round-2 blockers and all four warnings are closed, verified individually rather than taken
from the PR body.** The AC-1 amendment is exactly true at this head — I re-ran all three kinds:

| Kind | Result at `469d37d` |
| --- | --- |
| 1 — path into the deleted tree | the seven declared classes and no eighth (37 `capability-parity.tsv` rows + 9 sites + `ci.yml`'s two denylist patterns) |
| 2 — the deleted command literal (`grep -rE '/dev-pipeline:run([^-a-zA-Z]|$)'`) | 10 hits, **all** in the three declared exemptions (`CHANGELOG.md`, `docs/migrations/v1-to-v2.md`, `docs/onboarding.md`) |
| 3 — relative-link resolution, head vs merge-base | 24 broken at head, 7 at `33e6187`; **22 new**, exactly the two declared classes (16 historical-corpus rows, 6 `state-schema.md`) and **zero shipped-doc rows**. The branch also *fixed* 5 of the base's 7. |

The `(env16)`/`(env16b)` re-homing is the best work in this delta and it is not decorative — I
mutation-probed it in an isolated worktree (22/22 green at head):

| Mutant | `(env16)` | `(env16b)` |
| --- | --- | --- |
| M1 — drop the total subtraction (`$wall - $pausedSecs` → `$wall`) | **kill** | **kill** |
| M2 — drop the per-stage overlap (`($ee-$ss) - $ov` → `($ee-$ss)`) | **kill** | survives |
| M3 — swap `effectiveTotalMin`/`wallMin` in the **text renderer only** | survives | **kill** |

Each case kills a mutant the other survives, so `(env16b)` is not the vacuous outer-guard shape.

The blockers below are new. Both are the same class as round 2's, at the two surfaces its sweep did
not reach — and one of them is a claim **this delta wrote** that is not true.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | **Blocker** | `.github/ISSUE_TEMPLATE/pipeline-aborted.yml:24` + `plugins/second-shift/skills/doctor/tools/doctor.sh:63-77` / **AC-6** | The rewritten template's required `state-excerpt` field says the lean progress record "**is included in the `--report` bundle** under 'pipeline-state excerpt'". It is not, and cannot be. `state_excerpt()` globs `"$dir"/*.json` only — the lean lane writes `<issue>-lean-progress.md` and no JSON at all — and then projects `{ticketKey, status, currentStage, failureContext}`, four staged-schema fields the lean lane never writes. Proved rather than argued: with a `DOCTOR_REPO_ROOT` containing only `42-lean-progress.md`, `doctor.sh --report` emits `no pipeline runs recorded (.claude/pipeline-state/ is empty or absent)`. So a lean-only consumer hitting the failure mode this template was **just retargeted at** (a milestone hard stop) is told to paste a bundle section that is empty. The tool's own comment at `:60` names the cause — "the state-file excerpt the feedback forms ask for is exactly the `.failureContext` **statectl** writes on a fail-fast abort" — a deleted tool, in a shipped `/second-shift:doctor` command, which is squarely AC-6. Remedy is either half: teach `state_excerpt()` to prefer `*-lean-progress.md` (tailing it, not `jq`-projecting it), or drop the template's bundle claim. The first is better — the abort path is the one this lane actually has. |
| 2 | **Blocker** | `schema/second-shift.config.schema.json` (18 descriptions), `docs/config-schema.md:9,13`, `docs/extending.md:97,130,273-296` / **AC-6** | The two config surfaces still describe the deleted lane as the live mechanism for keys that are **live under lean**. AC-6's own enumerated floor names `docs/{config-schema,extending}.md`, and round 2's amendment names this schema file by name — its `ticketTag` description is one of the seven sites this very commit fixed. The other 17 were left. On live keys: `.paths.plansDir` — "where **Stage 3** writes plan files … (Stage 3 reads the key)", while `lean-gate.sh`/`lean-reconcile.sh`/`retro-corpus.sh` are the readers; `.tracker.keyPattern` — "**statectl init** validates the key against this anchored pattern"; `.commands` — "null = lane not available in this repo (**verifyctl** must not select it)"; `.commands.*.lintAutofixes` — "(**verifyctl** LINT_AUTOFIX failure classification)" while `preflight.sh:286-308` is the real reader; `.commands.*.extraLanes` — "a lane blocks **Stage-6** completion or it does not exist"; `.commands.*.extraLanes[].failureClass` — "e.g. **verifyctl's** 2-attempt budget"; `.stageParams.inertPattern` — "**Stage-6** INERT-lane classifier override"; `.stageParams.webComponentGlobs` — "**Stage-8** web-component surface"; `.gates.mutation` — "**Stage-5** unit-test mutation gate", the key D-17 explicitly *kept*; `.tracker.labels` — "the **Stage-1** queue query". `.design.liveRender` is the sharpest: "Arms a repo-owned render command in **BOTH lanes**, with **DIFFERENT** failure postures. **Stage 5**: …" — there is one lane, and `docs/config-schema.md:13` repeats it verbatim ("in **both** lanes with **different failure postures**: Stage 5 degrades…"). This is not cosmetic: the file carries `$schema`, so these strings are what renders in a consumer's editor as the authoritative account of a key they are setting. |
| 3 | Warning | `schema/second-shift.config.schema.json` (`.stageWorkflows`, `.implementDelegates`, `.planGates`, `.planGates[].surface`) | The EP-6/7/8 **INERT** decision is declared and well-reasoned, and `docs/extending.md` §3.6–3.8 + the decision-guide table carry the banner. The schema does not — it still describes EP-6 as "a **BLOCKING stage sub-step** — dispatched AFTER the stage's built-in sub-steps and BEFORE the **stage-completion write**", with no cause named. The banner was applied to one of the two consumer-facing surfaces; a consumer's editor shows the other. Separate from finding 2 because the remedy differs: a banner, not a rewrite. |
| 4 | Warning | `docs/extending.md:273-296` | The worked example — "one block, every stage of the tier registered and auditable" — is stage-keyed end to end (`// Stage 4 — gate the PLAN`, `// Stage 5 — WRITE`, `// Stage 6 — RUN`, `// Stage 8 — REVIEW`). Two of its four blocks are the inert EPs; the other two (`extraLanes`, `reviewers.add`) are live under `lean-gate.sh` milestone 3 and review-lead. It sits *after* the §3.6–3.8 INERT banners and inherits none of them, so it reads as a live staged walkthrough. `:130`'s "`doc-routing.md` … for **Stage-7** doc updates" is the same class one line at a time. |
| 5 | Nit | `plugins/dev-pipeline/tools/config-lint.sh:105` | A **runtime error message** a consumer sees names a deleted tool: "npm swallows the `--fix` suffix **verifyctl** appends". The rule it enforces is still right (`lintAutofixes: true` + a plain `npm run` lint is a silent no-op) — only the actor is gone. Same class as finding 2, but in emitted text rather than a description. |
| 6 | Nit | `plugins/second-shift/skills/doctor/SKILL.md:15` | "pipeline RUNTIME issues (gh auth, node, labels, **statectl**)" — a deleted tool as an example in a shipped skill. Inert; one word. |

## Acceptance criteria

| AC | Verdict | Evidence |
| --- | --- | --- |
| **AC-1** — sweep green, shellcheck/jq clean, orphan check (all three kinds) | **satisfied** | CI at `469d37d`: `lint-and-selftests` pass 4m09s, `selftests (macos, bash 3.2)` pass 4m24s, `mutation-sweep-pr` pass. I re-ran all three orphan kinds myself; results in the table above. The amendment that added kinds 2 and 3 is round 2's *prescribed* remedy, and the claim it makes is now exactly what the checks return — including the honest "22-row residue in two declared classes" rather than a claim of empty. |
| **AC-2** — no register row names a deleted guard | **satisfied** | Registers clean at this head. `mutation-sweep-pr` computed **49 verdicts** (a real green, not the zero-verdict shape) — but it **deferred `stage-times.sh` and `stage-envelopes.sh` to nightly on the PR-lane cap**, and this delta edits `stage-times.sh`. So the round owns that evidence: I compared the `logic` and `default` operators' matched-site **sequences** between `0a20468` and `HEAD` — byte-identical, so the three baseline rows (`stage-times.sh::default::1`, `::default::2`, `::logic::2`) are not re-keyed. The paired suite only *gained* cases, and a killed mutant still listed in the baseline is a warn, never a red (`mutation-sweep.sh:41`). |
| **AC-3** — keep list, demotion register, D-3 override, pin in the body | **satisfied** | Unchanged from round 2. `v5.2.2` verified as the newest tag and genuinely stage-carrying. The at-merge half stays a merge precondition, which AC-3's wording licenses. |
| **AC-4** — frozen-files green; breaking verb; `Changelog:` + `Migration:` | **satisfied** | PR **title** is `feat(dev-pipeline)!: delete stage choreography from main` — the load-bearing surface under squash merge. `74562a0` carries the `BREAKING CHANGE:` footer and a `Changelog:` whose `Migration:` line names both the `v5.2.2` pin (with the re-confirm caveat) and the moved `config-lint.sh` path. |
| **AC-5** — `capability-parity-check.sh` green, coverage clause vacuous | **satisfied** | Re-run at this head: `note: … /skills/run/stages does not exist — the coverage clause is vacuous (expected once #348 has landed)` then `OK — 37 capability row(s)`. That note **is** the pass. |
| **AC-6** — every doc naming deleted machinery updated in the same diff | **unsatisfied** | Findings 1–4. AC-6's enumerated floor names `docs/config-schema.md` and `docs/extending.md` directly; the schema JSON is named in round 2's own amendment. The three docs round 1 blocked on (`pipeline-manifesto.md`, `config-schema.md` links, `README.md`) and the seven sites round 2 blocked on are all correctly closed — this is the same class one surface further out, at the config layer rather than the skills layer. |
| **AC-7** — `visualCapture` retirement follows the dead-key pattern | **satisfied** | Unchanged; nothing in the delta touches it. The scope reviewer independently re-verified the no-`configVersion`-bump precedent against `gates.costTracking` in v2.1.6 and found it sound. |

## Design fidelity

`not-applicable`. The spec disarms with `Design: none — no design.provider is configured for this
repo, and the diff has no UI surface`. Re-verified at this head rather than inherited: `design` and
`stageParams.webComponentGlobs` are both `null` in the effective config, and the delta is
`.md`/`.yml`/`.json`/`.sh`/`.mjs`-comment only with no UI surface. The disarm is justified.

## Panel

Six reviewers selected, six returned — **no dark reviewer, no coverage gap**. `db-reviewer`,
`pipeline-reviewer` and `unit-test-mutation-reviewer` were not triggered (no DB, no queue surface,
no co-located specs). `a11y-reviewer` and the design-fidelity dimension were not routed: no changed
path matched `stageParams.webComponentGlobs` (unset ⇒ default `apps/web/**/*.{tsx,jsx}`).

Security, performance, complexity, maintainability and test-coverage returned **clean, zero
findings**. `scope-completeness-reviewer` returned `request-changes`; its four findings are triaged
under "What is not a finding" below — none survives as a blocker, and it also self-reported that the
dispatch range I gave it was the round-3 delta rather than `origin/main`, which it corrected for
itself before classifying.

**All four findings above are the round's own.** Findings 1, 2 and 4 live in files the delta either
did not touch (`doctor.sh`, the schema's other 17 descriptions, `extending.md`) or touched at one
line while the defect sits elsewhere in the same file — structurally outside every diff-scoped
reviewer's window, which is the third round running that this PR's hardest finding has that shape.

## What is not a finding

- **The scope gate's S8 pin-location finding.** The issue asks for the concrete pin "in the P1/P2
  posture note"; `docs/pipeline-manifesto.md:50-56` deliberately records a pointer to the
  `Migration:` trailer instead, arguing a literal there would rot. That treatment **was round 1's
  remedy and round 2 reviewed and accepted it**; re-opening it now would be escalating a settled
  decision into a round-3 blocker. The substance is delivered and discoverable. Worth one line in
  the issue body at merge to close the wording gap — a merge act, not a round.
- **The scope gate's AC-1 `tools/*.tsv` finding.** Correct on the letter — `capability-parity.tsv`
  matches `tools/*.tsv` and still cites 17 deleted paths — and settled twice: the file's own header
  and `capability-parity-check.sh:29` state that its paths are permanent historical citations, not
  existence-checked, and re-keying them would destroy this deletion's audit trail. The committed
  spec's amended AC-1 declares the exclusion. The committed spec is the definition of done.
- **The three merge-time obligations** (the pin recorded on #348, the OR-2 FE canary, re-stamping
  `v5.2.2` if a `v5.2.3` lands first). All enumerated in the PR body as merge preconditions. A
  remedy that lives outside the tree is not a review round.
- **`pr-gates` red.** Read the log: the only failing arm is `lean-evidence` / `lean-chain` reporting
  `verdict record … reads 'verdict=needs-work'` — the round-2 record, which this round replaces.
  Every other check at this head is green.
- **`state-schema.md`'s six dead links.** Deliberate, and this round widened the banner to name all
  six — I verified the count independently: the resolver finds exactly six, and all six named
  siblings are genuinely absent from the tree.
- **The `ticketTag` three-site coupling.** Handled properly: `docs/config-schema.md:37,39`, the
  schema description and `run-lean/SKILL.md` all now state the advisory reading, and
  `scripts/lockstep-manifest.tsv:520` records the considered-and-**DROPPED** entry with its
  reasoning — the sanctioned treatment for a real coupling that is not byte-anchorable.
- **The tracker README rewrites.** I re-read all three whole rather than checking their links, which
  is the lesson round 2 wrote. They are accurate: `build-lean/SKILL.md` step 1 *is* the queue-label
  confirm and step 7 *is* the ready PR with `Closes #<issue>`; every `../`-relative script they cite
  resolves; the `${CLAUDE_PLUGIN_ROOT}/tools/gh-bot.sh` form is right for an installed consumer; and
  the `#the-lean-lane-dev-pipelinerun-lean` anchor `jira/README.md` uses resolves against the
  sibling's actual heading.
- **The 22-row link residue and the `${CLAUDE_PLUGIN_ROOT}/skills/run/` hits.** Every one lands in
  `CHANGELOG.md` or `docs/plans/` — the two declared exempt classes. Checked, not assumed.

## Verdict

`needs-work` — two blockers, both AC-6, both bounded.

Finding 1 is the one that matters, and it is small: the delta retargeted the abort template at the
lean lane and, in doing so, asserted a bundle contains something the bundle's producer cannot
produce. Teaching `state_excerpt()` to prefer `*-lean-progress.md` fixes the template, the shipped
`/second-shift:doctor` command, and the `statectl` comment at `doctor.sh:60` in one edit.

Finding 2 is volume, not difficulty — the same edit this commit already performed once, applied to
the other 17 descriptions and the two doc rows that mirror them.

The deletion remains careful work and the round-2 response was again genuinely good: it adopted the
three-reference-kinds diagnosis rather than the two remedies, widened AC-1 to carry it, re-read the
tracker docs whole instead of patching their links, and turned an orphaned fixture into two real
guards that I could not make vacuous. What is left is that same class one layer further out. The
skills layer now describes the surviving lane correctly; the **config** layer — the schema a
consumer's editor renders, and the doctor bundle a consumer pastes into a bug report — still
describes the deleted one.
