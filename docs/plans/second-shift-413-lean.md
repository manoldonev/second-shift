# 413 — run-lean branch names use a lean/ namespace instead of the staged lane's formula

Two defects in one surface: the lean lane re-roots the configured `tracker.branchPrefix` onto a
`lean/` namespace no other lane uses, and an unset `branchPrefix` falls through to the placeholder
`claude/acme-`. The fix is one branch formula shared with the staged lane — `<branchPrefix><key>` —
plus a resolver that fails rather than guessing when the prefix is unset.

Adopting the staged prefix collapses the two lanes into one namespace, so the lean/staged
**discriminator moves off the branch name onto the committed artifact**. Post-`#430` that
discriminator lives in one place, `plugins/dev-pipeline/skills/run-lean/lean-evidence.sh`, and both
merge-boundary gates route through it.

Binding input: `.claude/pipeline-state/413-ledger.md` rev 2 (`D-1`–`D-22`, `OR-2`).

## Scope

| Site | Change |
| --- | --- |
| `skills/run-lean/branch-prefix.sh` | **new.** The one prefix resolver: config when set, dominant-prefix detection otherwise, hard failure when neither resolves. |
| `skills/run-lean/lean-gate.sh` | `lean_branch_prefix()` and its `LOCKSTEP` block delete; the branch/PR-lookup name becomes `<branchPrefix><key>`, key lowercased under jira. |
| `skills/run/tools/retro-corpus.sh` | second copy of the derivation deletes; `open-prs` gains the artifact discriminator its namespace filter used to provide. |
| `skills/run-lean/lean-evidence.sh` | `lean_branch_prefix()`, its `LOCKSTEP` block and both mutual-non-prefix `envfail`s delete; `classify()` becomes artifact-only with branch-first key resolution; `LEAN_BRANCH_PREFIX` becomes a deprecation notice. |
| `scripts/check-lean-chain.sh` | its own `LEAN_BRANCH_PREFIX` env constant, refusal and mutual-non-prefix assertion delete; delegation unchanged. |
| `scripts/check-pipeline-chain.sh` | gains the mirror-image lean exclusion **by delegating** to `lean-evidence.sh classify`. |
| `scripts/lockstep-manifest.tsv` | the live `lean-branch-prefix` row deletes; the same-named DROPPED note is rewritten. |
| `.github/workflows/ci.yml` | `LEAN_BRANCH_PREFIX` deletes; the pipeline-chain step gains the PR context its delegation now reads. |
| `templates/consumer/second-shift-ci*.{yml,sh}` | consumer-side `LEAN_BRANCH_PREFIX` prose/wiring retires. |
| docs | `pipeline-manifesto.md` T0 note, `pipeline-retro/SKILL.md`'s PR-lookup recipe. |

**Out of scope.** The artifact suffixes keep the `-lean` token (`-lean.md`, `-lean-verdict.md`,
`-lean-renders.md`) — `D-5`. The deprecated staged lane's prose in `stages/2-worktree.md` is left
untouched — `D-1`.

## Decisions taken here

Three points the ledger brackets but does not spell out. Each is inside a region the ledger already
decided, so none is a `P9` intent gap.

1. **Dominance is strict plurality; a tie fails.** `D-2` fixes what counts as a vote and `D-4`
   ("fail, naming the candidates considered", provenance `user-delegated`) fixes the posture when
   detection "cannot resolve confidently". The unstated middle is what *confident* means: the
   winner is the unique prefix with the strictly highest vote count. Two prefixes tied at the top
   is not a winner, and neither is zero candidates — both take `D-4`'s failure path, which names
   every candidate and its count.
2. **`lean-evidence.sh` does not call the resolver, because it performs no detection.** `D-1`
   lists it among the live consumers of the prefix, but the consumer CI template fetches it as a
   *single file* at the pinned marketplace ref — it cannot source a sibling. It reads
   `PIPELINE_BRANCH_PREFIX` from the environment or the committed config exactly as it does today,
   which is the pre-existing env-or-config read and not a second copy of the dominant-prefix scan
   `AC-5` is about. Its existing refusal on an unresolvable prefix stays, with its rationale
   restated: it is now the key derivation (`D-14`) that needs the prefix, not the applicability arm.
3. **`retro-corpus.sh open-prs` reads the PR's own file list.** `D-12` extends the artifact
   discriminator to it, and the local checkout cannot supply that evidence — an *open* lean PR's
   spec is committed on the branch, never on the base — so a file test against the working tree
   would reject every candidate it exists to find. It comes from the same `gh pr list` call
   instead, via the `files` field.

## Acceptance criteria

**AC-1.** With `tracker.branchPrefix` set, every branch name the lean lane creates or looks up is
`<branchPrefix><key>`, byte-identical to what the staged lane's formula yields for the same key. No
`lean/` segment appears in any of them — the worktree branch, `mark`'s PR lookup, or milestone 5's.

**AC-2.** Under `tracker.type: jira` the key is lowercased in that name (`jdoe/` + `GH-540` →
`jdoe/gh-540`), matching the staged lane's jira rule.

**AC-3.** With `tracker.branchPrefix` unset and remote branches carrying a single dominant
`<prefix><key>` shape, both lanes resolve that prefix. `claude/acme-` is never written into a
branch name as a fallback.

**AC-4.** With `tracker.branchPrefix` unset and no dominant prefix — zero candidates, or two tied
at the top — resolution fails, and the message names every candidate it considered with its count.

**AC-5.** One detection implementation, called by both lanes (`lean-gate.sh`, `retro-corpus.sh`). A
second copy of the dominant-prefix scan in either is a regression.

**AC-6.** `lean-evidence.sh classify()` reports `applicable=1` for a lean PR whose head branch
carries the *staged* prefix, on the artifact arm alone, with no `LEAN_BRANCH_PREFIX` anywhere in its
environment. The spec that triggers it is key-matched (`*-<key>-lean.md`, non-fixture) — a PR
carrying some *other* ticket's lean spec does not classify. `check-lean-chain.sh` reaches the same
verdict through its existing delegation and no longer requires the constant either.

**AC-7.** `check-pipeline-chain.sh` reports not-applicable for that same PR, resolving it by
delegation, and is unchanged in its verdict for a staged PR carrying no lean spec. A delegation that
cannot run is an environment error, never a silent exemption.

**AC-8.** No second copy of the lean discriminator exists. The live `lean-branch-prefix` row in
`scripts/lockstep-manifest.tsv` is deleted along with both its `LOCKSTEP-BEGIN/END` blocks, the
same-named DROPPED note is rewritten to record that its subject retired (its stated compensating
control *was* the artifact arm this change makes sole), no new row is added, and
`check-lockstep.sh` passes.

**AC-9.** A PR opened on a legacy `lean/`-prefixed branch before this change still classifies as
lean: not pipeline-prefixed, so the key resolves from the body and the key-matched spec in its diff
carries it. Confirmed against real data, not asserted — `#420` (`lean/second-shift-417`) is the
shape.

**AC-10.** `classify()` resolves the key from the **branch suffix** when the head ref is
pipeline-prefixed and that suffix parses as a key; the `Closes`/`Part of` body scan is reached only
for a non-prefixed branch. A body whose first closing keyword names some other ticket cannot hand
the gate a phantom key on a prefixed branch.

**AC-11.** A `LEAN_BRANCH_PREFIX` still set by a consumer's workflow produces a deprecation notice
on stdout and is otherwise ignored. It is never an `envfail` — that would red every consumer's PRs
at their next pin bump over a now-inert constant.

**AC-12.** `retro-corpus.sh open-prs` selects lean PRs by the key-matched lean spec in the PR's own
file list, not by namespace, so a staged PR sharing the prefix is not swept in and reported
verdict-less.

**AC-13.** `.github/workflows/ci.yml` carries no `LEAN_BRANCH_PREFIX`, and its
`check-pipeline-chain.sh` step carries the PR context that step's new delegation reads
(`PR_BASE_REF`, `PR_HEAD_SHA`).

**AC-14.** The consumer surface `#430` ships carries no `LEAN_BRANCH_PREFIX` requirement:
`templates/consumer/second-shift-ci.yml`, `second-shift-ci-check.sh` and
`second-shift-ci-check-selftest.sh` are consistent with the payload's new contract.

**AC-15 (doc).** The prose these changes make stale is updated in the same diff:
`docs/pipeline-manifesto.md`'s T0 note (which names `LEAN_BRANCH_PREFIX` as a `pr-gates` constant),
`plugins/dev-pipeline/skills/pipeline-retro/SKILL.md`'s `gh pr list --head "lean/..."` recipe, and
the file headers on both chain gates.

**AC-16 (test).** Coverage lands at the tier the contract sits at, not merely per-file:
`branch-prefix-selftest.sh` for the resolver's own behavior (`AC-3`, `AC-4`), and a
`scenario-liveness-selftest.sh` scenario for each composed verdict path this change touches — a
lean PR on the shared prefix reaching the lean gate's terminal write, and the same PR being exempted
by the pipeline gate.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-2 | A consumer repo carrying open `lean/`-prefixed PRs when it bumps its marketplace pin past this change | reversible-default-and-flag |

Stated default: the artifact arm covers them (`AC-9` is that mechanism, verified against real data),
and nothing compatibility-shaped is built — a shipped legacy arm for a case no consumer is known to
have is dead code no lane can red on. The flag is `AC-11`'s deprecation notice. Reversal is additive
to `classify()` and touches no interface.
