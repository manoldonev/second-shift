# lean review verdict — #417

verdict=approve
run_id: review-417-1
session_id: efb1ce3f-3f27-40bb-b3d6-318d1778cf7b
rounds: 1
pr: #420
reviewed_head: 6dabc33aa9490825ee3a8347b5703ed2cd95004a
reviewed_patch_id: 1a28fff42ca2c6fcc6f4e882368692cd2e929983
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

## Round 1 — approve

Range read: `a2b158f..HEAD` (chain root — full branch diff, 13 files, +520/−62). Reviewed from a
checkout of the PR head. Design section unarmed (`docs/plans/second-shift-417-lean.md` declares no
`## Design`), so fidelity scores `not-applicable`.

The fix is right and it is pinned by fixtures that can actually fail. Three suites drive the **real**
hook from a **real** linked worktree, so the writer/reader agreement is asserted from both sides
rather than modelled — the mirror-harness failure mode CLAUDE.md names is avoided by construction.
No blockers. Four warnings, all accuracy-of-prose; none touches shipped behavior.

### Verification performed (reviewer-side, not inherited from the PR body)

| Check | Result |
| --- | --- |
| `shellcheck -e SC1091,SC2015,SC2181` over all `*.sh` | clean |
| `scripts/check-lockstep-pairs.sh` | 18 pairs, 0 failed (incl. the new `audit-ledger-dir` row) |
| Full selftest sweep, **no** `SKIP_STRESS`, `env -u CLAUDE_CODE_SESSION_ID`, `-P 4` | exit 0, 0 failures |
| CI's bash-3.2 lane replicated (`PATH` shimmed to stock `/bin/bash` 3.2) on the 3 changed suites | all green |
| `check-frozen-files.sh`, `check-changelog-trailer.sh` | clean / trailer present |

### Adversarial probes — each new assertion reverted against its own writer

Run in a throwaway extraction of the reviewed tree; every mutation asserted **applied** before its
suite verdict was read (a plain `sed` no-op reads as SURVIVED, which is how a vacuous probe hides).

| Probe | Mutation | Result |
| --- | --- | --- |
| A | hook reverted to `${CLAUDE_PROJECT_DIR:-$CWD}/.claude/audit` | `audit-selftest` 17/3 (Tests 10a, 10b, 11); `lean-gate` **(d5)** reds with the exact false-refusal text; `lean-reconcile` **(Q)** reds |
| B | `audit-history.sh` reverted to a bare `.claude/audit` | `audit-selftest` 19/1 — **Test 14 alone**; (d5)/(Q) unaffected |
| C | fallback arm misrouted (`root="$base"` → `"$base/nope"`) | `audit-selftest` 19/1 — **Test 12 alone** |

No assertion is decorative, and the reader-side fixtures are genuinely cross-plugin: reverting the
writer reds three suites in two plugins.

### Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 writer anchors on the main checkout, both common-dir forms | satisfied | Tests 10/11, (d5), (Q); all red under Probe A |
| AC-2 fallback is today's path, hook never blocks | satisfied | Test 12 (killed by Probe C alone), Test 13 (`rc=0` on an unresolvable dir). See Warning 1 on the AC's trailing generalization |
| AC-3 `audit-history.sh` resolves identically, held by a `verbatim` row | satisfied | `check-lockstep-pairs.sh` green; Test 14 is the sole guard on that half (Probe B) |
| AC-4 `/audit` + `QUERIES.md` + onboarding name the resolved dir | satisfied | `SKILL.md` steps 1/5, `QUERIES.md` both recipes, both `audit-history.sh` heredocs, the settings template |
| AC-5 `audit-selftest.sh` covers (a)(b)(c) against a throwaway repo | satisfied | Tests 10/12/11 respectively; fixture is a `mktemp` repo it owns — no probe run wrote into the live checkout |
| AC-6 the false refusal is pinned | satisfied | (d5); Probe A reproduces the original refusal verbatim |
| AC-7 the second reader is pinned on its DEFAULT path | satisfied | (Q) sets no `LEAN_AUDIT_DIR` (only the pre-existing lines 126/525 do) and reds under Probe A |
| AC-8 the location contract is stated where it was false | satisfied | `SETUP.md` anchoring + abandonment, `lean-reconcile.sh` env block, `Changelog:` trailer; no prose-presence guard added |
| AC-9 the mutation registry is re-keyed in this diff | satisfied | every claimed ordinal independently re-derived from the operators' own detector regexes at both revs — see below. Warning 4 is the summary paragraph, not the rows |

**AC-9, re-derived rather than taken on trust.** `audit-tool-calls.sh::default` — base has one site
(the code, L59); head has L68 (a comment) at ordinal 1 and the code at ordinal 2. Row added for the
prose site, none for the code site: correct. `audit-history.sh::cmp-z` — base ordinals 1/2 are L74/L90;
head ordinals 1/2 are the new resolution's own guards (L37/L46) and the old sites moved to 3/4, outside
`k=2`. `logic::2` — base L51, head L44, old site displaced to ordinal 4. `cmp-eq::1` — same site at both
revs. Kept rows (`fail-open::1/2`, `detector::1/2`, hook `logic::2`) are all ordinal-unmoved. The
`lean-reconcile.sh` header edit adds no operator site — its only operator-matching `+` line is the
pre-existing `sed -n '2,83p'`, a modified site rather than a new one.

### Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | warning | `docs/plans/second-shift-417-lean.md` OR-1 (and AC-2's last sentence) | The open region's justification is empirically false for two of the three layouts it names |
| 2 | warning | same, OR-2 | "Marginal" understates a now-measured ~+37% on the hook's own per-call cost |
| 3 | warning | `plugins/audit-toolkit/scripts/audit-selftest.sh` (Tests 10-14 header) | Cites `lean-reconcile-selftest.sh`'s **(N)**; the case that landed is **(Q)** |
| 4 | warning | `docs/plans/second-shift-417-lean.md` "Honest limit on the four removals" | Over-generalizes: one of the four is genuine new coverage, and the paragraph contradicts its own table |
| 5 | nit | PR title | No conventional prefix, so the derived release bullet carries no type/scope |

**1 — OR-1's "no worse off than before" does not hold for submodules or bare checkouts.** OR-1 takes
the D-6 ladder on the stated ground that "anything that does not resolve to a readable directory falls
back to today's path, so such a layout is no worse off than before this PR". Measured against the real
resolver, two of the three layouts it names *do* resolve — to a new place, not the fallback:

- submodule: `--git-common-dir` → `<super>/.git/modules/vendor`, so the ledger lands at
  `<super>/.git/modules/.claude/audit/` — **inside git's private directory**.
- bare checkout: `--git-common-dir` → `.`, so the ledger lands at `<parent-of-foo.git>/.claude/audit/`
  — **outside the repository entirely**, in whatever directory happens to contain it.

(The third, `.git`-file worktrees, *is* the linked-worktree case and is exercised.) Not a blocker: no
consumer topology is a submodule or a bare checkout, writer and readers still agree in both layouts so
nothing breaks functionally, and neither location is version-controlled. But the flag's whole
reversibility argument rests on a claim that is checkable in a minute and is wrong, and AC-2's "No new
failure mode for any layout" inherits the same over-reach. The fix is one corrected sentence — or, if
you want the claim to become true, one `case` arm rejecting a common-dir under `.git/`.

**2 — OR-2 is measurable, and the intuition behind "marginal" is the wrong one.** OR-2 declines to
measure on the reasoning that "the hook already spawns `jq` six times and `date` once per call, so this
is marginal". Measured on this machine (macOS, warm, 150 invocations × 3 rounds, same fixture repo,
base hook vs head hook): base 43–61 ms/call, head 60–78 ms/call — **+16 to +17 ms, ~+37%**. Isolated:
`git rev-parse --git-common-dir` ≈ 20 ms/op, the `cd`+`pwd` subshell ≈ 1 ms. So one `git` process costs
roughly a third of everything the hook already did — the six-`jq` comparison points the wrong way. In
absolute terms this is still nothing beside a model turn, and the spec correctly claims nothing, so no
action is required; but the flag can now be closed with a number instead of left open. Related and
pre-existing: `SETUP.md`'s unchanged "~1–2 ms" per-tool-call claim was already off by ~40× at base and
this PR widens the gap.

**3 — stale cross-reference.** The Tests 10-14 header comment tells the next reader the reconcile-side
fixture is `lean-reconcile-selftest.sh`'s **(N)**. `(N)` is the inheritance-chain case; the case that
landed here is **(Q)**. No lane can red on a comment, which is exactly why it is worth fixing in the
round that introduced it.

**4 — the mutation paragraph contradicts its own table.** The table scores `cmp-eq::1` as "killed —
**ordinal unmoved**; the new `/audit-history`-from-a-worktree case now asserts a non-zero session
count". The paragraph beneath then covers all four removals with "those mutants are now killed because
the `k=2` budget window moved onto the new resolution's guards, **not** because the regressions the old
rows described became caught. Their sites sit at ordinals 3-6 and are no longer swept at all." Re-derived:
`cmp-eq::1` keys the same guard at base (L52) and head (L76), it is still at ordinal 1, it is still
swept, and Test 14 is a real new assertion that kills it — so for that row the honest limit does not
apply and "no longer swept at all" is false. The error under-claims the PR's own coverage, and the
three `cmp-z`/`logic` rows it does describe are exactly right; scope the paragraph to those three.

**5 — nit.** `#414`/`#411` merged with `docs(...)`/`feat(...)` subjects; `#404`/`#407` merged bare, so
precedent runs both ways. The bump is unaffected either way (`fix:` → patch, bare subject → patch, via
`derive-release.sh`'s level ladder), and plugin attribution comes from changed paths, not the subject.
Purely a release-notes consistency call at merge time.

### Not findings — checked and cleared

- **Trailer handling across the squash.** Three `Changelog:` blocks reach the squashed body
  (`none.`, the real prose, `none.`). `render_bullet`'s paragraph-mode `awk` normalizes case, trailing
  whitespace and a trailing period before the no-op test, so both `none.` blocks drop and the real one
  renders. Ordering does not matter.
- **`check-plugin-version-bumps.sh` reds locally** for three plugins — it compares against tag `v4.0.0`
  and so reports main's drift, not this branch's. The job is gated to `head_ref == 'release/next'` in
  `ci.yml` and cannot fire on this PR. No frozen file is touched.
- **`/audit`'s doc snippet omits the hook's fallback branch** — in a non-git directory the snippet
  resolves `/.claude/audit` where the hook would use `<dir>/.claude/audit`. Unreachable for `/audit` in
  practice (it is repo-scoped, and the empty result routes to the Case A onboarding either way).
- **Reviewer panel** (security, performance, maintainability, complexity, test-coverage,
  scope-completeness): 6/6 approve, 0 blockers, 0 dark. Its one ≥80-confidence suppressed note is
  finding 3 above, reached independently.

### CI

No workflow run has ever been created for this PR — Actions has been stuck repo-wide (an unrelated
18:08 run sat `queued` for 40+ minutes). Not branch-specific and not attributable to this diff; the
merge boundary still owns the green gate. The local evidence above is what this round rests on.
