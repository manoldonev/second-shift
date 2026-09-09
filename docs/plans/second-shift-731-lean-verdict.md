# lean review verdict — #731

verdict=approve
run_id: review-731-1
session_id: 4f6d03a0-a983-4f45-bfbd-b36be747d2b0
rounds: 1
pr: #829
reviewed_head: acc47746f6ccfe5807bf019a36d9aa15c510a5f7
reviewed_patch_id: 378f609376635ed714119586fadebbbcf3c16657
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer,review-toolkit:security-reviewer,review-toolkit:pipeline-reviewer
model: opus
capabilities: pr-marker

## Summary

Round 1, full-branch range (`bash G delta 731` printed `c6436a68..HEAD`, FULL — nothing to
inherit). 103 files, 1262 insertions / 1900 deletions, net **-757**.

This is a surface rename with one deletion attached, and both halves hold up. All 14 files under
`skills/{run,build,review}-lean/` moved to `skills/{run,build,review}/` with **git modes
byte-identical** (100755/100644 preserved on every one — the classic `mv` +x loss did not happen),
and **zero logic changed**: every non-comment changed line in `lean-gate.sh` (16),
`lean-evidence.sh` (4), `lean-reconcile.sh` (1) and `branch-prefix.sh` (0) is a user-facing message
string. `orchestrate-lean.sh`'s only code edits are the two sibling loads
(`$SCRIPT_DIR/../build/lean-gate.sh`, `../build/branch-prefix.sh`) and the five literal spawn
strings, all of which resolve under the new layout.

The deletion of `scripts/check-pipeline-chain.sh` is **authorized**: the maintainer's ratification
comment on #731 (`manoldonev`, 2026-09-09T08:54:00Z — four minutes before the build claimed at
08:58:45Z) grants it by name, states the bar (negative net diff) and records the two consequences.
That same comment is also where AC-3's pathspec was narrowed and AC-4's baseline corrected, which
is why the committed spec's D-2 carries `user-answered` provenance.

**The AC-10 coverage-transfer claim is the load-bearing one, and I re-measured it rather than
taking it.** Both mutants AC-10 names were re-applied by me in an **isolated worktree detached at `acc47746`** (not the reviewed one), each verified non-vacuous by diffing the mutated file before running. **Control first:** all three surviving suites are green on the unmutated head (rc=0, rc=0, rc=0). **M1** (the key-matched `case` at `lean-evidence.sh:948` replaced by an unconditional `key_spec="$f"; break`) is killed by all three — `scenario-liveness` rc=1 with `(lr3)` failing, `check-lean-chain-selftest` rc=1 on `(D)`, `lean-evidence-selftest` rc=2 on `(d)`/`(z2)`. **M2** (`APPLICABLE=1` → `0` on the resolved-key arm at :959) is killed by all three and reproduces the spec's cited figures **exactly**: `scenario-liveness` **rc=4** with **`(lr1)` among the failing cases**, `check-lean-chain-selftest` **rc=75**, `lean-evidence-selftest` **rc=72**. So the claim that survives D-18's correction — every kill the deleted suite provided is still provided — holds, and the rewritten lane-routing leg is non-vacuous in both directions: `(lr1)` dies under M2, `(lr3)` under M1.

AC-6 needed real work, because CI does not cover it. `install-topology` is `skipping` on this PR
lane and milestone 3 concluded in 68s (the cached lane), so neither is evidence. I ran
`bash tools/install-topology-selftest.sh` directly at the reviewed head: **53 ran, 53 passed,
3 skipped, 0 red** — and every moved suite (`skills/build/lean-gate-selftest.sh`,
`skills/build/scenario-liveness-selftest.sh`, `skills/run/orchestrate-lean-selftest.sh`, …) passed
*from the staged install cache under the new layout*, which is the strongest available evidence
that the plugin re-layout is sound. The 3 skips are the standing repo-only-artifact skips
(`config-lint`'s schema lockstep, `operator-override`'s `(m6)`, `check-review-context-sections`),
unrelated to this change.

**A local red I chased down rather than reported.** My first sweep came back with 4 failing suites
(`lean-gate` rc=12, `scenario-liveness` rc=4, `orchestrate-lean` rc=2, `operator-override` rc=1).
That was this review session's own environment: `LEAN_ATTEND_MODE=headless` and
`LEAN_RUN_MODEL=opus` were exported into it. Re-run with `env -u` on both, all four are **rc=0**.
CI at the identical head agrees.

One warning and three notes below; nothing that blocks. The scope gate's `block` is dismissed on a
verified factual error — see "Dismissed findings".

## Findings

| # | severity | file | finding |
| --- | --- | --- | --- |
| W1 | warning | `.github/workflows/ci.yml:283` | **This diff orphaned a CI constant and left the comment above it stale.** `PIPELINE_PLAN_PATTERN: docs/plans/acme-{issueKey}.md` had exactly one consumer, the `check-pipeline-chain.sh` this PR deletes. Measured at head: `git grep -n 'PIPELINE_PLAN_PATTERN'` over the whole tree (minus `docs/plans/`, `CHANGELOG.md`) returns **one line — its own definition**. Neither `check-lean-chain.sh` nor `lean-evidence.sh` reads it, and no guard covers it (`grep -rn PIPELINE_PLAN_PATTERN scripts/ tools/ plugins/` is empty), so nothing will ever red on it. Its sibling `PIPELINE_BRANCH_PREFIX` **is** still live (`lean-evidence.sh:504`, with the `envfail` at :511 and the resolved-prefix echo at :1482), so this is one dead key, not two. The comment block at :270–283 that introduces them now misstates the tree in two ways: it calls them "CI-visible copies of **two** runtime-config values", and it says "**Neither** chain gate classifies on the branch name any more: **both** delegate to lean-evidence.sh" — there is one chain gate. Not a blocker: a dead `env:` key has no runtime effect, CI is green, and no AC covers it (AC-10 names "the `ci.yml` step that ran it", which *is* gone; D-3(b) puts `ci.yml` prose out of the AC-3 sweep). But it is precisely the class of residue this ticket exists to remove, in the one file `check-frozen-files.sh` raised its advisory about. One-line delete plus two comment sentences. |
| N1 | note | issue #731 (body) | The issue **body** still carries the pre-amendment AC-3 and AC-4. The amendment is real and authoritative — the maintainer's 08:54:00Z comment narrows AC-3's pathspec and names the four excluded classes, and the committed spec records it as D-2/D-3 with `user-answered` provenance — but a reader who opens #731 after merge and stops at the body will measure AC-3 at 108 lines and AC-4's literal grep at 16, and conclude the merged work missed its own criteria. This is what tripped `scope-completeness-reviewer` into a blocker (below). The lane's designed shape is that the ledger amends and the body is not rewritten, so this is a note on the artifact trail, not a defect in the diff. |
| N2 | note | `plugins/dev-pipeline/skills/build/lean-evidence.sh` (AC-4) | AC-4 does not just re-baseline the ticket's grep, it **re-spells** it — `'lean PR\|lean PRs'` (unanchored) becomes `'\blean PRs\?\b'`. That is more than D-4's "re-measure at your own base" licence on its face. It is nonetheless the right call and is disclosed in AC-4's own text: I confirmed the ticket's literal form is unsatisfiable, matching `clean PR`, `lean prefix`, `lean progress`, `boolean prefix` and `LEAN PREFERENCE` — none of which this ticket renames — and that the anchored form returns **0 at head, 60 at base**. The substantive requirement is met, and the amendment was written down rather than smoothed over. Flagged only so the departure is on the record as a *disclosed* one. |
| N4 | note | `docs/plans/second-shift-731-lean.md` (AC-10) | AC-10 cites one rc triple — "`scenario-liveness-selftest.sh` (rc=4, `(lr1)` among the failing cases), `check-lean-chain-selftest.sh` (rc=75) and `lean-evidence-selftest.sh` (rc=72)" — for a sentence that says **both** mutants are killed. Re-measured, that triple is **M2's specifically**; M1 is also killed by all three but yields rc=1 / rc=1 / rc=2, and its failing liveness case is `(lr3)`, not `(lr1)`. The claim the numbers support is true and I verified it for both mutants; only the attribution of the figures is loose. Worth one line because D-18's whole point was replacing an asserted claim with a measured one, so its evidence should say which measurement it is. |
| N3 | note | `.claude/SECOND-SHIFT.md:23` | The mechanical substitution left one tautology: "`` `/dev-pipeline:run` (the lane's front door, invoked as `/dev-pipeline:run`) ``". The base read `` `run-lean` (… invoked as `/dev-pipeline:run-lean`) `` — a bare skill name and then its invocation — and rewriting the first half to the namespaced form made the parenthetical restate it. I swept the whole changed set for artifacts of this shape and this is the only one. Cosmetic. |

## Consequences accepted, not findings

- **Consumer migration is a hard red, by design (D-15).** A consumer that advances its
  second-shift pin past this release without re-running `/second-shift:onboard` has a vendored
  `second-shift-ci-check.sh` fetching `skills/build-lean/lean-evidence.sh` at the new ref → 404 →
  `exit >= 1`. There is deliberately no dual-path fallback, because the script's own doctrine is
  that a moved path IS drift. This is carried in the `Changelog:` trailer's `Migration:` line and
  in the PR body. Worth naming here because the alias stubs — the stated reason this is a minor
  and not a major — do **not** cover this axis; the skill surface stays compatible while the
  vendored CI copy does not.
- **OR-2's gap is real and disclosed.** After the deletion, a hand-cut `claude/second-shift-<n>`
  branch carrying no committed spec is claimed by no chain gate. The catch it loses was
  accidental (a missing stage trail, an artifact of the lane deleted in #348), the operator took
  the reversible-default, and `docs/pipeline-manifesto.md:252` records it in the tree.

## Dismissed findings

`review-toolkit:scope-completeness-reviewer` returned `block`. Its blocker and one major rest on a
premise I checked and found false, so neither stands:

- **BLOCKER "AC-3 returns 108 lines, not zero" (conf 98) — dismissed.** Its stated ground is that
  the narrowing "lives in the build's own artifact, not in the issue body, and the issue carries no
  explicit deferral with rationale". The narrowing is in an **operator write on the tracker**: the
  maintainer's ratification comment of 2026-09-09T08:54:00Z, from `manoldonev`, four minutes before
  the build claimed the ticket and on a different identity axis from the bot's markers. It narrows
  AC-3 to Scope item 4's file set and names all four excluded classes with reasons. The reviewer
  read the body without its comments. Scored against the amended criterion, which is also the one
  the committed spec declares, AC-3 measures **0 at head / 60 at base** — exactly the figures the
  spec states.
- **MAJOR "a CI gate is deleted with no authorization in the issue" (conf 90) — dismissed**, same
  root cause. The ratification comment authorizes the deletion explicitly and by name, resolves
  OR-1, and states the bar it is judged on.
- **MAJOR "AC-4 as written is not met" (conf 88) — downgraded to N2.** Correct on the facts,
  wrong on severity: the re-spelling is disclosed in the spec and the substantive requirement is
  measurably met.
- **MAJOR "AC-6 not verified within the review budget" (conf 85) — resolved.** It was the
  reviewer's budget, not the branch's gap. Both halves are green; see the Summary.
- **MINOR "AC-1's 'unchanged content apart from path references' departs" (conf 82) — dismissed.**
  The `scenario-liveness-selftest.sh` lane-routing rewrite is not an unauthorized departure; it is
  what **AC-10 and D-8 mandate**, and the deletion it follows from is authorized.

A departure from AC-1's literal wording does stand, but a different one than the reviewer named:
the prose sweep also ran through **shell comments**, which no AC's pathspec covers (AC-3 is
`.md`-only). That is D-17's substitution rule applied consistently, AC-1's own declared oracle is
the path grep and it returns 0, so I score it satisfied and note the superset here.

## Oracles run

Exact commands, kept out of the table cells below because the record's own parser splits on `|`.
All run from a checkout of the reviewed head `acc47746`; base is `c6436a68`.

```
# O-1 (AC-1) — must return zero
git grep -n 'skills/\(run\|build\|review\)-lean' -- ':!docs/plans/' ':!CHANGELOG.md'
    head: 0 lines

# O-3 (AC-3) — the D-2 pathspec, must return zero
git grep -Iin 'lean lane\|lean-lane\|the lean\b' -- CLAUDE.md .claude/SECOND-SHIFT.md README.md \
    'docs/*.md' 'plugins/dev-pipeline/*.md' ':!docs/plans/*'
    head: 0 lines      base: 60 lines
  (git's 'docs/*.md' pathspec recurses; the 'docs/**/*.md' spelling reads 20 at base and is the wrong form for git)

# O-4 (AC-4) — anchored form, must return zero
git grep -Iin '\blean PRs\?\b' -- ':!docs/plans/' ':!CHANGELOG.md'
    head: 0 lines      base: 60 lines

# O-5 (AC-5)
bash scripts/check-frozen-files.sh c6436a68
    clean; 1 advisory (the .github/workflows/** edit)

# O-9 (AC-9) — the gitignored dogfood config
grep -in 'lean\|skills/' .claude/second-shift.config.json
    no matches

# O-6 (AC-6) second half — the one CI skips on the PR lane
bash tools/install-topology-selftest.sh
    rc=0 — "53 ran, 53 passed, 3 skipped, 0 red"
```

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | Declared oracle **O-1** returns **0** at head. All 14 files present under the new dirs and absent from the old (10 `build/`, 3 `run/`, 1 `review/`), file names unchanged, `git ls-tree` modes byte-identical base→head. No logic changed: non-comment changed lines are 16 in `lean-gate.sh`, 4 in `lean-evidence.sh`, 1 in `lean-reconcile.sh`, 0 in `branch-prefix.sh` — every one a message string. Path references verified individually: `.claude/settings.json:5` → `skills/build/lean-gate.sh`; `orchestrate-lean.sh:247,824` → `../build/…`; `check-lean-chain.sh` `PAYLOAD` default → `skills/build/lean-evidence.sh`; `second-shift-ci-check.sh:163` `fetch_at_ref` → `skills/build/lean-evidence.sh`; `review/SKILL.md:14` names the sibling `build/`; the five `orchestrate-lean.sh` spawn strings are `/dev-pipeline:{build,review}`. Registries in AC-7. Departure noted above: shell **comments** were swept too, beyond "path references"; the AC's own oracle passes. |
| AC-2 | satisfied | Three stubs at the old paths, **9 lines each** (bound is 15), each `SKILL.md`-only in its directory. Frontmatter keeps `name: run-lean` / `build-lean` / `review-lean` per D-7, description prefixed `DEPRECATED — use /dev-pipeline:<new>`, body one delegation line. The `Changelog:` trailer on `e2b5a58a` names the window verbatim: "still resolve as deprecated aliases for one minor and are removed in the next major". |
| AC-3 | satisfied | Oracle **O-3** (the D-2 pathspec) → **0** at head, **60** at `c6436a68`. Matches the spec's stated 60-to-zero exactly. The narrowing is the operator's, on the issue, pre-claim — see Dismissed findings. |
| AC-4 | satisfied | Oracle **O-4** (anchored) → **0** at head, **60** at base. Second half holds: `lean-evidence.sh` keeps `LEAN_SPEC_SUFFIX='-lean.md'` (:575) unrenamed as the mechanism while its contract prose says "pipeline PR" (:862, :877, :955, :1455). The grep re-spelling is a disclosed departure — N2. |
| AC-5 | satisfied | `plugins/dev-pipeline/.claude-plugin/plugin.json` `description` and `.claude-plugin/marketplace.json`'s dev-pipeline `description` both contain no `lean`; the marketplace one now reads "gated by five artifact milestones", retiring the ticket's own motivating quote. `version` (12.4.4) and `metadata.version` (12.4.5) are byte-identical to `c6436a68`. Declared oracle **O-5** → **clean**, 1 advisory (the `ci.yml` edit, fast feedback not enforcement). CI `pr-gates` "frozen files guard" step: success at `acc47746`. |
| AC-6 | satisfied | **Both halves, both green.** (i) The sweep: cited from CI at the identical head `acc47746` rather than re-run — `lint-and-selftests` (job 102418143488) step "run all selftests" success, log line `[run-selftests] summary: 78 scored, 78 run, 0 served from cache, 0 failed`; `selftests (macos, bash 3.2)` (job 102418143210) identical, 0 failed. `0 served from cache` makes CI's `--cache-dir` behaviorally a cold run, and CI omits `SKIP_STRESS=1`, so it is strictly stronger than the recipe. My own local run of the exact recipe agrees once the session's leaked `LEAN_ATTEND_MODE`/`LEAN_RUN_MODEL` are scrubbed. (ii) The non-optional half: oracle **O-6**, run by me directly at the reviewed head → **rc=0, "53 ran, 53 passed, 3 skipped, 0 red"**, with every moved suite passing from the staged install cache under the new layout. CI could not supply this — its `install-topology` jobs are `skipping` on the PR lane. |
| AC-7 | satisfied | `tools/mutation-catalog.tsv`: **107** data rows at base and head; rows whose **guard column** is under the three skill dirs = **48** at both; row-id list byte-identical (`cut -f1` diff empty), so no guard was re-anchored. The 51-vs-48 gap is accounted for: 3 further rows changed their *mutant expression*, not their guard (`config-shadowing-drop-row`, `stack-generality-filewide`, `ci-check-evidence-path` — each embeds a skill path inside its sed). Both of those that CI's `mutation-sweep-pr` reports as survivors are **pre-existing baseline rows**, present identically at `c6436a68` and head, so no new survivor. Other registries, moved-row count and total preserved: `selftest-suite-timings.tsv` **5**, `selftest-cache-inputs.tsv` **17**, `gate-buckets.tsv` **151**, `prose-blocker-triage.tsv` **39**. |
| AC-8 | satisfied | `git diff --name-status c6436a68..HEAD -- docs/plans/ CHANGELOG.md` returns exactly one line: `A docs/plans/second-shift-731-lean.md`. No pre-existing plan file modified; `CHANGELOG.md` untouched. This verdict record is the second permitted new file. |
| AC-9 | satisfied | `.claude/second-shift.config.json` (gitignored, shared across this clone's worktrees) carries no `lean` token and no skill reference at all — oracle **O-9** returns nothing, and its complete key set is `$schema`, `configVersion`, `tracker.*`, `topology.*`, `commands.*`. That is direct and dispositive evidence for "needs no edit". I deliberately did **not** run the AC's named `--dry-run` confirmation: invoking `orchestrate-lean.sh` from a review session is the one shape this lane forbids, and the file's own content proves the claim more strongly than a call that returns before resolving a skill name (D-12). No `Migration:` note was owed on this axis and none is claimed. |
| AC-10 | satisfied | Deletion set confirmed: `scripts/check-pipeline-chain.sh` and `scripts/check-pipeline-chain-selftest.sh` gone (`delete mode 100755` on both), the `ci.yml` step that ran it gone, and its 2 `tools/mutation-baseline.tsv` rows gone — and the build also decremented a neighbouring baseline row's survivor count from "fiv[e]" to "fou[r]", so that register's own arithmetic stayed true. The `ci.yml` edit is 3 hunks and removes only that step: the frozen-files and changelog-trailer steps are intact, no `needs:`/`permissions:` change, and CI's actionlint step is green at this head. The lane-routing leg is rewritten, not dropped, and now pins the classifier's two discriminators separately — `(lr1)` suffix+key-match → claimed, `(lr2)` no suffix → unclaimed, `(lr3)` suffix but another ticket's key → unclaimed. **The coverage-transfer claim I re-measured myself rather than taking**: control green on all three suites, and both mutants killed by all three at head — M2 reproducing the spec's `rc=4` / `rc=75` / `rc=72` and its `(lr1)` exactly. See the Summary and N4. I did **not** re-run the base-tree half (that the deleted suite killed both at `c6436a68`); it supports only D-18's self-correction, which makes the ticket's claim weaker and more honest, and the merge-relevant half is the head side, which is verified in full. |
