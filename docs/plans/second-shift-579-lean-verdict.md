# lean review verdict — #579

verdict=approve
run_id: review-579-1
session_id: 7e3b46e9-9fa8-4393-88bb-bb633e7cf683
rounds: 1
pr: #589
reviewed_head: 23fe93618dc9986c57c7fb6404356b200a9bfa8a
reviewed_patch_id: 65f0570e9c14972cbaabf44b5e8c132f450f8de1
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1 — `review-579-1`. Range: **full branch diff** (`d344956..HEAD`, root round, nothing to
inherit). Reviewed head `23fe936`, from the PR-head checkout.

**Verdict: approve.** Zero blockers. Every one of AC-1…AC-10 is **satisfied**, and every load-bearing
number in the spec and PR body was **re-derived independently in this round** rather than read.

## Reviewer panel

6 selected, **6 returned, 0 dark**. All approve, zero findings above threshold.

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |

Not routed: `db-reviewer`, `pipeline-reviewer` (no DB or queue surface); `a11y-reviewer` and the
design-fidelity dimension (no changed path matches `stageParams.webComponentGlobs` — the key is
absent, so the shipped default `apps/web/**/*.{tsx,jsx}` applies and this repo has no web
surface); `unit-test-mutation-reviewer` (no co-located unit specs — this tree's mutation surface is
shell guards, reviewed here directly).

**Fidelity: not-applicable.** The spec has no `## Design` section and the repo config declares no
`design.provider`, so the design-sighted arm has nothing to score.

## The round's own work

The panel found nothing, so the record below is what this round did itself. Site enumeration is
**byte-identical base→head** (2810 site-instances over the whole guard universe, all six operators,
`diff` empty), which is what makes every ordinal claim below pure arithmetic on one rule change
rather than a measurement entangled with edited guards.

**The baseline transformation, recomputed from scratch.** Enumerating every in-universe guard at
`d344956` with each operator's own ERE, resolving each of the 142 generic baseline rows to the line
its ordinal names, and re-deriving the post-exclusion ordinal:

| Claim | PR body | Re-derived here |
| --- | --- | --- |
| Generic rows deleted, all comment sites | 41 | **41**, and all 41 resolve to a `^[[:space:]]*#` line |
| Rows re-keyed | 6, all `::2 → ::1` | **the same 6, all `::2 → ::1`** |
| Rows whose key and note are untouched | 95 | **95**, notes byte-identical (0 altered) |
| `catalog::` rows | untouched | **28 → 28, byte-identical** |
| Generic rows at head | 108 | **108** = 142 − 41 + 7 |
| New rows reusing a key that existed on `main` | 6 of 7 | **6**; the 7th, `orchestrate-lean.sh::default::2`, is genuinely new |

Every "now names" cell in the PR body's reused-key table matches the recomputation line-for-line
(`lean-gate.sh::default::1` base line 219 comment → head line 298 `GH_CLI="${GH:-gh}"`, and so on).
No unbaselined row changed ordinal.

**AC-5's two residues, re-measured.** 4 of the 142 generic rows sit on a code line containing `#` —
and they are exactly the four the body characterises: one genuine trailing comment
(`check-config-shadowing.sh::logic::1`), plus `$#`, a `sed 's#…#…#'` delimiter and a `grep -E '^# '`
pattern. For the heredoc residue I ran a heredoc tracker over all **70** distinct excluded lines:
**0** sit inside an unclosed heredoc, so "0 such lines in today's swept universe" holds under a
mechanical check, not only by hand classification.

**AC-4 and AC-7, statically.** Both `orchestrate-lean.sh` line-251 sites (`fail-open::1`,
`detector::1`) are comment lines at base and vanish at head. Operator×guard pairs whose sites are
*entirely* comments: **6, across 6 guards** — the same six the report's `sites_comment_only` cells
name in CI.

**AC-6, both hand-reverts reproduced.** Ran `tools/mutation-sweep-selftest.sh` three times in an
isolated worktree at the reviewed head:

| Implementation | `(am)` result |
| --- | --- |
| Shipped | **all cases passed** (rc=0) |
| Probe A — exclusion line deleted (1-line diff, `bash -n` clean) | `(am1)` `1/1/cg.sh::fail-open::1`, plus `(am2) (am3) (am4)` — **4 failures** |
| Probe B — filter moved inside the loop as a post-increment `continue` | `(am1)` `1/1/cg.sh::fail-open::3`, plus `(am3) (am4)` — **3 failures** |

Byte-for-byte the two reds the PR body records. The half that matters for AC-1 reproduces too:
under Probe B, **`(am2)` — the `mutants_applied`/`sites_beyond_budget` assertion — passes.** Only
the survivor ordinal separates the correct filter from the in-loop skip, which is precisely why the
AC forbids resting on `mutants_applied`.

**AC-10's two kills, verified by applying the operators' own flips.** Each mutant was spliced into a
separate isolated worktree, one line changed (`diff | grep -c '^<'` = 1), `bash -n` clean:

- `scripts/check-lean-chain.sh::default::2` (line 362, `[[ -n "${PIPELINE_BRANCH_PREFIX:-}" ]]`) →
  new `(K)` **reds**, and the output shows the `rc=2` arriving from `lean-evidence`'s envfail:
  `neither PIPELINE_BRANCH_PREFIX nor a committed tracker.branchPrefix is resolvable`. I then
  reverted `(K)` to its pre-fix rc-only form under the *same* mutant: **suite all green**. That is
  the survivor claim proved in both directions, not just the fix asserted.
- `check-review-context-sections.sh::cmp-eq::2` (line 296) → **2 failures**, matching the claim.

Ordinal 1 of that same guard is line 295, `coverage_line   # exit-neutral informational line` —
this change's own AC-5 residue, live and correctly baselined.

**AC-8's mechanics.** The `# environment: … / # k=2` header block is byte-identical to `main`'s;
123 rows (95 generic + 28 catalog) are byte-identical; all 6 re-keys carry the base note **verbatim**
with `RE-KEYED for #579:` prepended, checked by string containment rather than by eye. No re-seed.

**Report-shape safety.** All four `emit_row` call sites take the ninth argument (`deferred-to-nightly`,
`excluded`, the unrun-`swept` path, the swept path) — a missed one would emit an 8-field row and
break `--mode merge`'s byte-wise header compare. `report_row()`'s `$5/$6/$7` and `report_beyond()`'s
`$8` are unmoved; `(ak4)` was updated to pin the new header tail. The sweep runs under `set -uo
pipefail` with no `-e`, so the filtering `grep -vE`'s exit 1 on a fully-excluded operator is
correctly inert, and the empty-`SITES` path still degenerates to a no-op loop.

**No guard goes dark.** Across the whole universe, **0** guards lose every site to the exclusion.
Mutants inside the `k=2` window move 519 → 504: −43 unkillable comment sites, +28 real code sites.

## CI on the reviewed head

`lint-and-selftests` pass · `selftests (macos, bash 3.2)` pass · `mutation-sweep-pr` pass ·
`pr-gates` fail **on the missing verdict record only** (`✗ no committed verdict record (a file named
*-579-lean-verdict.md)`), which is the expected pre-review state.

**The confirming full sweep has landed, and it confirms.** Run
[32183958721](https://github.com/manoldonev/second-shift/actions/runs/32183958721) —
`workflow_dispatch`, `headSha` `23fe936`, byte-equal to the reviewed head — concluded **failure** on
exactly two shards, with exactly two `RED:` lines:
`doctor.sh::cmp-z::1` and `capability-parity-check.sh::logic::2`. Both are the two the PR body
pre-declared as **not from this change**, and I confirmed that independently: at base, `doctor.sh`
`cmp-z` enumerates lines 80/82/84 and `capability-parity-check.sh` `logic` enumerates 47/75/99, with
**no comment among them**, so both ordinals are unchanged by the exclusion. Nothing this change armed
survives. **#585 / PR 588 has since merged**, closing both. Its edit to `orchestrate-lean.sh` is
comment-only and it touches no baseline row, so this branch's ordinals and baseline still hold
against current `main` — under this very change, a comment-only edit re-keys nothing.

## Acceptance criteria

| AC | Score | Basis |
| --- | --- | --- |
| **AC-1** | satisfied | Filter at `tools/mutation-sweep.sh:1592`, between the enumerating `grep -nE --` (1567) and the `while read` (1601). Probe B is the falsifier: the in-loop variant produces `::3` and reds `(am1)`. |
| **AC-2** | satisfied | 41 rows deleted, each independently resolved to a comment line. |
| **AC-3** | satisfied | 6 re-keyed in the same diff, named individually in the body; recomputation returns the identical set. |
| **AC-4** | satisfied | Both line-251 sites confirmed comments at base; the cited nightly log names them as re-verified serial survivors, and this branch's sweep no longer emits either id. |
| **AC-5** | satisfied | 4 / 142 trailing-`#` rows and 0 heredoc-payload lines, both re-measured here. |
| **AC-6** | satisfied | Case `(am)` asserts the survivor ordinal; both hand-reverts reproduced with the recorded output, and `(am2)` passing under Probe B is what makes the ordinal assertion load-bearing. |
| **AC-7** | satisfied | Ninth column appended last, all four emit sites updated, `(ak3)`/`(am3)` discriminate all-comment from no-site; 6 all-comment pairs confirmed statically and in CI. |
| **AC-8** | satisfied | Header byte-unchanged, 123 rows byte-identical, notes preserved verbatim across the re-keys. |
| **AC-9** | satisfied | `mutation-operators.tsv` header, `docs/testing.md` (new paragraph + `k=2` passage re-derived, with the two surviving examples checked as non-comment) and `CLAUDE.md`. |
| **AC-10** | satisfied | 2 kills verified by hand-applying each operator's own flip, 7 baselined rows each carrying a per-site rationale, and the dispatched sweep on the exact head naming no survivor this change created. |

The spec was amended in the code commit (`e3bb2b0`): AC-9 gained a third surface, AC-10 was added.
Diffed across its own commits, the hunk is **pure addition** — no AC weakened or removed — so it is
the strengthening case, not the banned retrofit.

## Warnings (should fix — not blocking; none costs a round)

**1. [PR body] AC-8's note accounting is off by 3, and one clause over-reaches.** The body reads
"15 of those carried hand-written rationale … `main` carries 36 hand-written notes; 21 survive here".
Measured: `main` carries **36** ✓, head carries **28** ✓ — but the split is **18 deleted / 18
surviving from base**, plus **3** re-keyed rows that were seed-noted at base and became hand-written
only by the `RE-KEYED for #579:` prefix, plus **7** new (18+3+7 = 28). The "21 survive" figure counts
those 3 as survivors of a set they were never in. Separately, "every one of them was rationale *for
why a comment cannot be killed*" holds for 11 of the 18; the other 7 carry the generic
`seeded for #303 from a local advisory sweep (macOS); confirm at the first nightly`, which says
nothing about comments. The AC itself — no re-seed, rationale not flattened — is satisfied either
way; this is the descriptive paragraph, not the mechanism.

**2. [PR body] The confirming-sweep sentence is stale.** "A confirming full sweep … is in flight; its
verdict is appended here when it lands" — it landed, and the verdict is favourable (see above).
Worth appending, both because the body promises it and because the run is the strongest single piece
of AC-10 evidence on the exact reviewed head.

**3. [`docs/testing.md:580`] The closing "Two obligations" paragraph still states the re-key
obligation unconditionally** — "Editing a guard re-keys its generic survivor ordinals, so that PR
re-baselines those rows in its own diff" — while `CLAUDE.md`'s twin sentence was relaxed *in this
same diff* to "editing a guard's CODE … Comment lines are not sites, so a comment-only edit re-keys
nothing." `docs/testing.md` is the surface `CLAUDE.md` defers to ("Full contract"), and the relaxation
is load-bearing right now: #543's re-key evidence is what it unblocks. The correct rule *is* stated
in this file, in the new "A comment line is not a site" paragraph ~100 lines above, and
`mutation-operators.tsv`'s header is unambiguous — so this is a residual restatement, not a missing
contract, which is why it is a warning and not an AC-9 miss. One clause closes it.
