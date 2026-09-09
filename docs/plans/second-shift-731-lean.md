# second-shift #731 — the pipeline drops its "lean" name

Branch base: `c6436a68` (`release: v12.4.5 (#820)`). Every figure below was re-measured at that
commit, per D-4; the ticket body's counts were taken at `2e15eac` and the pre-flight ledger's at
`55d49bfb`, and both are stale.

The **surface** is renamed; the **plumbing** is not. Skill directories, the words an operator reads,
and the two plugin descriptions move. File names (`lean-gate.sh`, `orchestrate-lean.sh`), `LEAN_*`
tokens, and the artifact families (`*-lean.md`, `*-lean-verdict.md`, `{issue}-lean-progress`, the
`lean-pr-marker` / `lean-claimed` tags) stay exactly as they are — those are slice 2, and slice 2 is
not authorized by this ticket (D-10).

One thing the ticket body does not carry and the pre-flight ledger added: `scripts/check-pipeline-chain.sh`
is deleted here (D-1), because "the pipeline" cannot be the vocabulary of record while a live CI gate
prints `non-pipeline change` as a class. That gate had been unsatisfiable since #348 removed the only
emitter of the stage trail it demands.

## Acceptance criteria

- **AC-1** — `plugins/dev-pipeline/skills/{run,build,review}/` exist and hold every file that lived
  under `{run,build,review}-lean/`, each with an unchanged file name and unchanged content apart from
  path references. Every path reference to the moved directories follows the move: selftests,
  `tools/mutation-catalog.tsv`, `tools/selftest-suite-timings.tsv`, `tools/selftest-cache-inputs.tsv`,
  `scripts/gate-buckets.tsv`, `docs/prose-blocker-triage.tsv`, `tools/capability-parity.tsv`,
  `.claude/settings.json`, the sibling-relative `../build-lean/…` loads in `orchestrate-lean.sh`, and
  the consumer CI template's `fetch_at_ref` path (D-15). Oracle: `git grep -n
  'skills/\(run\|build\|review\)-lean' -- ':!docs/plans/' ':!CHANGELOG.md'` returns only the three
  alias-stub directories of AC-2.
- **AC-2** — `/dev-pipeline:run-lean`, `/dev-pipeline:build-lean` and `/dev-pipeline:review-lean`
  still resolve, as `SKILL.md` stubs at the old paths whose entire body is a deprecation notice and a
  delegation to the new skill. Each stub is **9 lines**, under the 15-line bound. The `Changelog:`
  trailer names the alias window ("removed in the next major").
- **AC-3** — over the file set Scope item 4 declares (D-2) — `CLAUDE.md`, `.claude/SECOND-SHIFT.md`,
  `README.md`, `docs/**/*.md` and `plugins/dev-pipeline/**/*.md`, minus `docs/plans/` —
  `git grep -Iin 'lean lane\|lean-lane\|the lean\b'` returns **0** lines. It returned **60** at the
  branch base. The 4 classes outside that pathspec stay as they are, with reasons, per D-3.
- **AC-4** — `git grep -Iin '\blean PRs\?\b' -- ':!docs/plans/' ':!CHANGELOG.md'` returns **0** lines
  repo-wide. It returned **60** at the branch base. The ticket's literal spelling of this grep
  (`'lean PR\|lean PRs'`, unanchored, case-insensitive) is **unsatisfiable** and is restated here
  under D-4's licence to re-measure: it also matches `lean prefix`, `lean progress`, `LEAN PREFERENCE`
  and `clean PR`, none of which this ticket renames, which is why its base reading was 81 rather than
  60. And: `lean-evidence.sh`'s classification contract comment describes what it detects as a
  **pipeline PR** and names the `-lean.md` suffix as the *mechanism*, unrenamed.
- **AC-5** — `plugins/dev-pipeline/.claude-plugin/plugin.json`'s `description` and
  `.claude-plugin/marketplace.json`'s dev-pipeline `description` (D-5) contain no `lean`; `version` in
  the first and `metadata.version` in the second are untouched. Oracle: `scripts/check-frozen-files.sh`.
- **AC-6** — `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`
  is green, **and** `bash tools/install-topology-selftest.sh` is green on its own. The second is not
  optional here: this ticket changes how the plugin is laid out, which is the one class of change the
  nightly's last answer does not cover.
- **AC-7** — `tools/mutation-catalog.tsv`'s guard column points at the new paths: **48** of its **107**
  rows moved, the total row count is unchanged, and the row-id list is byte-identical to the base's
  (a path move is not a guard edit). The same holds for the other path-keyed registries:
  `tools/selftest-suite-timings.tsv` 5 rows, `tools/selftest-cache-inputs.tsv` 17,
  `scripts/gate-buckets.tsv` 151, `docs/prose-blocker-triage.tsv` 39 — each count preserved.
- **AC-8** — no file that already existed under `docs/plans/` is modified, and `CHANGELOG.md` is
  untouched. This spec and its verdict record are the only new files under `docs/plans/`.
- **AC-9** — `.claude/second-shift.config.json` (gitignored, this repo's dogfood config) needs no
  edit, verified by `--dry-run` against this ticket's own number after the rename lands locally. If it
  had needed one, that would be a migration note in the `Changelog:` trailer rather than a silent fix.
- **AC-10** — the vocabulary collision is resolved by deletion, not by a second-choice word (D-1):
  `scripts/check-pipeline-chain.sh`, `scripts/check-pipeline-chain-selftest.sh`, the `ci.yml` step that
  ran it and its 2 `tools/mutation-baseline.tsv` rows are gone. `scenario-liveness-selftest.sh`'s
  lane-routing leg is **rewritten, not deleted** (D-8): with one gate the two-gate "exactly one claims
  it" relation is vacuous, so `(lr1)`/`(lr2)`/`(lr3)` now assert the surviving gate's classification
  directly over one tree and one branch shape, moving only the diff. The deletion carries a base-tree
  mutation proof that it costs no coverage.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | "The pipeline" as the vocabulary of record collides with a live identifier. `scripts/check-pipeline-chain.sh` is wired at `ci.yml:326` beside `check-lean-chain.sh` at `:360`, and prints `non-pipeline change` and `lean-lane change — not applicable` as mutually exclusive classes | Free the word. Delete `scripts/check-pipeline-chain.sh`, `scripts/check-pipeline-chain-selftest.sh`, and the `ci.yml` step that runs it, in THIS ticket. Grounded: once applicable the gate demands a stage-marker comment trail that nothing has emitted since #348, so it is unsatisfiable-but-live. "The pipeline" then denotes one thing | user-answered |
| D-2 | AC-3's grep (241 lines, 90 files at `55d49bfb`) is far wider than Scope item 4's declared file list (158 lines) | Scope item 4 governs. AC-3's pathspec is amended to the files Scope 4 names — `CLAUDE.md`, `.claude/SECOND-SHIFT.md`, `docs/*.md`, `plugins/dev-pipeline/*.md`, the three SKILL.md bodies — and its target re-baselined to 158-to-zero. The 83-line overflow is named out of scope with reasons in D-3 | user-answered |
| D-3 | Which classes the 83-line AC-3 overflow is excluded as, and why | Out of scope, four classes, each because the string is not prose: (a) selftest assertion strings and `.tsv` registries — `capability-parity.tsv` 12, `gate-buckets.tsv` 2, `mutation-catalog.tsv` — where an edit is a guard edit that re-anchors catalog rows per CLAUDE.md; (b) `.github/workflows/ci.yml`, `.gitignore`, `schema/second-shift.config.schema.json` — machine-read or published contracts; (c) `plugins/second-shift/templates/consumer/**` — written INTO consumer repos, so a rename there is a consumer migration; (d) roughly 25 lines inside four sibling plugins (design-toolkit, audit-toolkit, intake-toolkit, review-toolkit) that this ticket's scope never names. All four are slice-2 candidates | user-delegated |
| D-4 | The ticket's AC baselines are stale at the branch base | The ACs carry re-measured numbers, not the `2e15eac` ones. AC-3 227 becomes 158 under the narrowed pathspec of D-2. AC-4 60 becomes 81. AC-7's "30 catalog rows" becomes 51 rows pointing into the three skill directories, plus 5 rows in `tools/selftest-suite-timings.tsv` and 17 in `tools/selftest-cache-inputs.tsv`. BUILD re-measures at its own base before committing the ACs rather than copying these | user-delegated |
| D-5 | `.claude-plugin/marketplace.json`'s dev-pipeline description also reads "gated by lean's five artifact milestones" — the ticket's own motivating quote — and neither Scope 3 nor AC-5 covers it | In scope. AC-5 extends to that description too. Only `metadata.version` is frozen in that file per CLAUDE.md, so the description is freely editable. It is the more visible of the two descriptions, being the marketplace front door | user-delegated |
| D-6 | `orchestrate-lean.sh` spawns the payload halves by literal skill-name string at lines 1388, 1389, 1414, 1525 and 1532, and a spawned headless session resolves against the INSTALLED plugin cache, not the branch | The spawn strings move to the new names. The spawn string and the skill directory ship in the same plugin version, so they can never be mismatched at runtime — an older installed cache runs an older `orchestrate-lean.sh` that spawns the older names. The alias stubs therefore cover human-typed invocations only, which is all they need to cover | user-delegated |
| D-7 | Alias stub shape under AC-2 | Three files at the old paths. Frontmatter keeps `name: run-lean` and friends — the harness binds `name` to the directory — with the description prefixed `DEPRECATED — use /dev-pipeline:run`. Body is one delegation line. Under 15 lines each, per AC-2 | user-delegated |
| D-8 | D-1's deletion reds `scenario-liveness-selftest.sh` at line 2561, whose "lane routing" leg hard-fails INSIDE the repo when either chain gate is absent, and orphans 2 rows in `tools/mutation-baseline.tsv` at lines 137 and 138 | The liveness leg is rewritten, not deleted: it asserts the surviving gate's classification directly — a lean PR is claimed, a non-lean prefix branch is unclaimed — rather than the two-gate "exactly one claims it" relation, which goes vacuous with one gate. The 2 baseline rows are dropped. Per CLAUDE.md the deletion carries a base-tree mutation proof that it costs no coverage | user-delegated |
| D-9 | Deleting the gate removes the only thing currently stopping a hand-cut `claude/second-shift-<n>` branch that carries no committed lean spec. `check-lean-chain.sh` will not claim it either, since `lean-evidence classify` keys on that spec | Accepted, and flagged under OR-2. The catch was accidental rather than designed — the gate reds such a branch on a missing stage trail, not on any deliberate rule — and restoring a deleted script from git is cheap, which is what makes this reversible rather than pause-worthy | user-delegated |
| D-10 | Whether slice 2 is authorized by this ticket | No. The ticket states its go/no-go is a separate call made after this merges. Not declared as an open region, because it needs no resolution for THIS build to proceed | codebase-derived |
| D-11 | Skill invocation spelling in all rewritten prose | Namespaced, always: `/dev-pipeline:run`, `/dev-pipeline:build`, `/dev-pipeline:review`. Per `docs/namespaces.md` rule 1, bare short forms do not resolve for plugin skills. That doc's own rule-1 example currently reads `dev-pipeline:run-lean` and is inside D-2's scope, so it moves with the rest | codebase-derived |
| D-12 | Whether `.claude/second-shift.config.json` needs an edit, per AC-9 | It does not. The dogfood config carries no `lean` token and no skill reference at all — verified by inspection. AC-9's `--dry-run` remains worth running, and is safe: `--dry-run` returns from `spawn` before resolving any skill name, at `orchestrate-lean.sh:1173` | codebase-derived |
| D-13 | Conventional-commit verb and bump level | `feat(dev-pipeline):`, minor. Per CLAUDE.md the verb is load-bearing here because the AI tooling IS the product, and per the ticket the aliases are what keep it non-breaking. Not `feat!` | codebase-derived |
| D-14 | Ratification of the `harness-internal` label | Parked under OR-1, owner: operator, before the ticket becomes ready-for-dev | deferred |
| D-15 | `plugins/second-shift/templates/consumer/second-shift-ci-check.sh` fetches `plugins/dev-pipeline/skills/build-lean/lean-evidence.sh` from the marketplace repo AT THE CONSUMER'S PINNED REF, and S-11 put the consumer templates out of scope | The PATH follows the move, per AC-1; S-11's carve-out was about prose, and a fetch path that 404s is not prose. No dual-path fallback: the script's own doctrine is that a moved path IS drift and must be reported, which makes pin-and-template a pair that moves together. The consequence is disclosed rather than absorbed — a consumer advancing its pin past this release must also refresh its vendored copy of that script, and that migration note goes in this ticket's `Changelog:` trailer and PR body, not slice 2's | codebase-derived |
| D-16 | Whether the four `docs/skill-ablation*.md` study records take the skill-name rename | No. They are pinned-measurement records — "`review-lean`'s SKILL.md, 127 lines at `8d5d0897`" — and the name is how a reader reaches the measured bytes with `git show`. Same class as `docs/plans/`, which AC-8 never rewrites. Their AC-3-pattern hits ARE fixed; only the skill-name mentions stay | codebase-derived |
| D-17 | Which words replace the retired ones, so the substitution is one rule rather than per-site taste | "the lean lane" and "lean-lane" become "the pipeline"; "a lean PR" becomes "a pipeline PR"; "the lean gate" becomes "the milestone gate"; "the lean session" becomes "the build session"; "the lean spec" becomes "the committed spec". Skill invocations are namespaced everywhere, per D-11. Where a comment names an IDENTIFIER it keeps naming it: `lean-gate.sh`, `lean-lanes.tsv`, `lean-pr-marker`, and the quoted commit subject at `lean-gate.sh:6452` are unchanged | codebase-derived |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The `harness-internal` label requires an operator `Ratified:` comment before ready-for-dev | resolved — the operator ratified on the issue, granting the deletion of `check-pipeline-chain.sh` and clearing the ticket for `ready-for-dev`. The ratification bar is a negative net diff, and this branch measures **-757 lines** (1143 inserted, 1900 deleted) |
| OR-2 | CI posture change on a public repo: after D-1's deletion, a hand-cut prefix branch carrying no committed spec is claimed by neither merge-boundary gate | resolved — took its stated default, reversible-default-and-flag. BUILD flags it in the PR body and does not pause. The catch was accidental rather than designed, and restoring one script plus its CI step is a `git revert` |

## Out of scope

- Slice 2 in full: file renames (`lean-gate.sh`, `orchestrate-lean.sh`, `lean-evidence.sh`,
  `lean-reconcile.sh`, `check-lean-chain.sh`, `reap-lean-fixtures.sh`, `.claude/lean-overrides.tsv`),
  `LEAN_*` env and variable names, LOCKSTEP block ids, and the artifact families in consumer repos.
  Its go/no-go is a separate call (D-10).
- The four AC-3 overflow classes of D-3: selftest assertion strings and `.tsv` registries,
  machine-read or published contracts (`ci.yml`, `.gitignore`, `schema/second-shift.config.schema.json`),
  the consumer templates' prose, and roughly 25 lines inside four sibling plugins.
- `docs/plans/` and `CHANGELOG.md`: never rewritten (AC-8).
- `design-toolkit` eval fixtures named `01-lean-spec-*`: the fixture name is the eval's record.
