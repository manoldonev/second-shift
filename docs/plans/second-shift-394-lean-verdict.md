# lean review verdict — #394

verdict=approve
run_id: review-394-2
session_id: cd630be3-37f7-441b-b614-203c90707a8c
rounds: 2
pr: #404
reviewed_head: 780ae79219241ef6572184a9f6ad62adc3db337b
reviewed_patch_id: d87b6a29de0c8508e469bd3b0b9d332118886917
inherited_patch_id: d83eea4fba63f1a6fca12fe4df50164b3707c0c8
inherited_from_verdict: c1effb36615cac45382c4fd812ecb3b71c604124
fidelity: not-applicable
model: unknown

## Round 2 — `lean/second-shift-394` (PR #404)

Range read: `c1effb3..HEAD` — the delta since the tree round 1 covered (patch `d83eea4fba63`),
inheriting the rest by reference to that record. Read wider than the range where it was
misleading: the range carries a merge of `origin/main`, so most of its 16 files are base-side
(#402's release bump, #403/#406, #405). The branch-owned delta is `3437da4` (the `subst()` fix)
plus the merge's own conflict resolutions in `780ae79`. The whole-branch diff against `origin/main`
was re-read for the two guards the merge touched.

Verdict **approve**: 9/9 ACs satisfied, **no blockers**, 4 warnings.

Verification re-run from this checkout, not taken on report: `shellcheck` rc=0, `jq empty` rc=0,
and the full 63-suite `*-selftest.sh` sweep **without `SKIP_STRESS`** under
`env -u CLAUDE_CODE_SESSION_ID` rc=0 — `lean-gate-selftest` all green, `check-lean-chain-selftest`
all green, `lean-reconcile-selftest` all green, `scenario-liveness` 73 passed / 0 failed — plus
`scripts/check-lockstep-pairs.sh` at 17 pairs / 0 failed. CI on this exact head (`780ae79`) is
green on both interpreter lanes —
`lint-and-selftests` (ubuntu, bash 5.2) and `selftests (macos, bash 3.2)` — which matters here
because the defect round 1 found is invisible to one of them. `pr-gates` red is the expected
pre-approve state; its sole cause is `verdict=needs-work, not approve` from the round-1 record.

### Round-1 blockers — both cleared

**B1 (`&` spliced back as the matched placeholder on bash ≥ 5.2) — fixed, and the kill
reproduced independently.** `subst()` walks the template, so there is no replacement layer to
interpret. Reverted it back to the three `${ecmd//\{…\}/…}` forms **write-through** (`cat` into
the file, never `mv`/`cp` — the 0755 bit is a precondition several suites gate on) and ran
`lean-gate-selftest.sh` under PATH bash **5.3.9**: **1 FAILURE, sole red `(dr2c)`**. Restored
write-through; `shasum -a 256` and mode byte-identical, `git status` empty. The teardown works:
`(di1)`/`(di2)`/`(dl4)` stayed green, so the kill is attributable to one case. Declining a
`tools/mutation-catalog.tsv` row is right — the mutant is vacuous on the macOS lane by
construction and would land there as a survivor for something that is not a regression.

**B2 (`Changelog: none.` on a migration-bearing change) — fixed, and verified through the real
release machinery.** Built the squash body GitHub will produce for a 5-commit PR and ran
`derive-release.sh`'s own `extract_trailers`, `render_bullet` and `extract_breaking` awk programs
over it: the four `none.` blocks drop, the accurate block renders in full **with its `Migration:`
line**, `BREAKING CHANGE:` extracts, and the level derives **3 — major**. The bump was handed to
the fix round without a ruling and the round ruled, which is what D-8's own principle asks for.

### Findings

| # | Class | Where | Finding |
| --- | --- | --- | --- |
| W1 | warning | `check-lean-chain-selftest.sh` `(X5)` | The merge made `(X5)`'s negative assertion structurally unfalsifiable, and its comment factually wrong. |
| W2 | warning | `tools/mutation-baseline.tsv:50` | The committed re-baseline row still carries round-1 W2's unqualified "unmoved" claim; the PR body was corrected, the row was not. |
| W3 | warning | `scripts/derive-release.sh` | Bump level derives from the **squash subject** (= the PR title), not from the branch's commit verbs. `feat:` on a plain-English-titled PR ships a patch. Pre-existing. |
| W4 | warning | `run-lean/SKILL.md` | Round-1 W3's residual: the 60-line cap still asserts nothing (42 lines / 972 words / longest line 492 chars). Deferral rationale accepted. |

---

#### W1 — the base merge silenced one of `(X5)`'s two guards, and left its comment wrong

`(X5)` is the case round 1 singled out: the one tree where a stale receipt is the *only* stale
artifact. It asserts two things — `rc=1` with `records rendered_from` (the kill), and the absence
of `file(s) changed between that commit and the PR head` (proof that no *other* freshness arm
fired). #406, merged into this branch at `780ae79`, gives the declared arm precedence:

```sh
if [[ -n "$VERDICT_REVIEWED_PATCH_ID" ]]; then
  echo "[lean-chain]   · freshness (inferred): skipped — record declares reviewed_patch_id …"
else
  … note_violation "… $n_stale file(s) changed between that commit and the PR head …"
```

That string has exactly one emission site (`scripts/check-lean-chain.sh:577`), inside the `else`.
`(X5)`'s record is written by the **5-argument** `write_verdict`, so it always carries
`reviewed_patch_id` and can never reach it. The clause reads as an active guard and is now dead —
it cannot fail for any change to the gate.

The case still holds: its positive assertion carries the kill, and AC-6's clause ("a stale
`rendered_from` reds") is satisfied. So this is a **coverage softening**, not an unmet AC. But the
comment above it now says something false about the code — "the verdict is the last commit and
**both freshness arms stay green**" — when only one arm runs at all. And the clause it replaced
was the one keeping `(X5)` honest about *which* arm reds: with it dead, a tree where the
**declared** arm also fired would still satisfy both surviving assertions, so `(X5)` can now pass
for a reason other than the receipt. The remedy is two lines — assert the skip positively
(`grep -q 'freshness (inferred): skipped'`, exactly the way #406's own `(W2)` does), negatively
assert the declared arm's `now hashes to`, and reword the comment.

Worth naming as a class rather than an incident: this is the second thing in this round created
by *taking the merge* rather than by writing code, after the `-h|--help` range. A mid-round base
merge can retire an assertion in code the merge did not touch, and nothing reds when it does.

#### W2 — the committed baseline row still overreaches where the PR body no longer does

`tools/mutation-baseline.tsv:50` (added by this branch) ends: "Every other operator on this
guard, and all five on lean-reconcile.sh and check-lean-chain.sh, were diffed against origin/main
and are unmoved". Enumerating every operator in `tools/mutation-operators.tsv` and diffing the
ordered matched-line lists `origin/main` → `HEAD`:

| guard | first ordinal at which the site list diverges |
| --- | --- |
| `lean-gate.sh` | `default` **2** (acknowledged, re-baselined), `cmp-eq` 4, `detector` 6, `logic` 15; `cmp-z` ordinal 1 differs by content (the help range), `fail-open` has no sites |
| `check-lean-chain.sh` | `cmp-z` 2, `logic` 2, `cmp-eq` 3, `detector` 15, `default` 22; `fail-open` unmoved |
| `lean-reconcile.sh` | `logic` 13 (the `header_key` parameterization inserts a line, shifting 14+); the other five unmoved |

So "all five … are unmoved" is false as written on both named guards, and there are six operators,
not five. What *is* true is the claim the baseline actually rests on: **inside the swept window
(`K_BUDGET=2`) every committed row's ordinal still indexes its own site** — verified row by row,
including all six `lean-reconcile.sh` rows, which sit on operators that are unmoved end to end.

The round-2 PR body states this correctly and at length. The committed row — the artifact a future
reader re-deriving the baseline will actually open — was not brought along. Same overreach round 1
raised as W2, in the one place it still lives. Not a blocker: no row is wrong, nothing reds, and
the two prose corrections the diff *did* make are both accurate (`lean-gate.sh` `default` ordinals
are now 1 `${GH:-gh}` comment, 2 `${CURL:-curl}` comment, 3 `GH_CLI="${GH:-gh}"`, exactly as the
row and the `retro-corpus.sh::default::2` correction say).

#### W3 — the bump derives from the PR title, so a `feat:` verb is decorative

Found while verifying B2's remedy. `derive-release.sh` scans `$LAST_TAG..HEAD` on the base and
tests `^feat(\(…\))?:` against each commit's **subject**. After a squash merge of a multi-commit
PR, that subject is the **PR title**, not any commit's. This PR's title is plain English, so
neither the `type!:` arm nor the `feat:` arm fires — its **major comes solely from the
`BREAKING CHANGE:` footer** in the body. Had the round settled on minor instead, it would have
shipped a **patch**.

Not hypothetical. PR #383 carried `feat(dev-pipeline): lean-gate milestone 3 runs the config's
extra verify lanes` on a commit, had the plain-English title `lean-gate milestone 3 runs the
config's extra verify lanes`, and released as **v3.8.1 → v3.8.2 — a patch**. CLAUDE.md's "Commit
verbs decide the version bump" table describes something the machinery does not do whenever the
PR title is not itself conventional, which the repo's own issue-title convention encourages.

Pre-existing, outside this PR's AC set, and this PR's own outcome is correct. Wants its own issue:
either read the trailers' commit subjects rather than the squash subject, or lint the PR title.

#### W4 — round-1 W3's residual, deliberately deferred

`run-lean/SKILL.md` is unchanged in this delta: **42 lines, 972 words, longest line 492
characters**. The `wc -l` cap still asserts nothing. The PR declines to fix it on the grounds that
re-expressing the cap in units unwrapping cannot defeat changes a lane-wide authoring contract
governing every future edit to that file — wider than this ticket's AC set. That reasoning is
sound and the deferral is stated up front rather than discovered afterwards, so it stays a
warning: round 1 classed the same defect a warning, and escalating a round-1 warning's residual to
a round-2 blocker inverts the prior round. Wants its own issue.

### Spec amendment — cleared, and the clearance is recorded because silence on this rule reads as an oversight

The delta amends `docs/plans/second-shift-394-lean.md`, which the lane treats as blocker-class
when a spec is bent to match the diff. It is not that here, on all three checks:

- **No AC lost a requirement.** `AC-2`'s text is byte-identical; every numbered AC is untouched.
- **The amendment came from a review finding, not from the diff.** Round-1 W1 asked in as many
  words for the "one escape this design must not leave open" phrasing to be softened so a later
  reader does not inherit it as a guarantee.
- **It scopes a claim about the mechanism, not the obligation.** The replacement paragraph says
  the lock binds within the worktree that armed the lane and names the residual (review-lean's
  unjustified-disarm blocker). The gate's behavior, and every case that pins it, is unchanged —
  the same wording landed in `design_was_armed`'s comment and the `(dl2)`/`(dl3)` preamble.

### Per-AC scoring — 9/9 satisfied

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 milestone-1 arming forms | **satisfied** | Untouched by the delta; inherited from round 1 and re-run here. `(dz1)`–`(dz7)` green, and the AND→OR executioner is still real: `(dz3)` reads the same armed spec through a config with no design axis and requires a silent unarmed pass. |
| AC-2 disarm state-lock | **satisfied** | `(dl1)`–`(dl5)` unchanged and green. The delta reworded the `(dl2)`/`(dl3)` preamble to say what the pair actually pins — the *within-worktree* lock — which is the W1 remedy, not a weakening: `(dl5)` still keeps the pair turning on the lock rather than on the wording. |
| AC-3 the render pass | **satisfied** | Every enumerated clause still lands (`(dr1)`–`(dr11)`, `(dr2a)`/`(dr2b)`). Round 1 scored this satisfied by its letter while carrying B1 as a separate blocker; B1 is now fixed at the substitution layer and `(dr2c)` guards it on `(dr2a)`'s call-log oracle — reproduced above as the sole red on bash 5.3.9 against the reverted mutant. |
| AC-4 idempotence | **satisfied** | `(di1)`/`(di1b)`/`(di2)` green. The delta's risk to this AC was the new `&`-bearing fixture leaking into them; the case's explicit teardown restores the canonical spec and re-renders, and the probe confirms it — reverting the fix reds `(dr2c)` **only**. |
| AC-5 the verdict key | **satisfied** | `(fd1)`–`(fd7)` unchanged and green, `(fd3)` still driving `fidelity:` through the real `--summary-file` body path. Independently exercised by this record: `--fidelity` is unavailable in the installed 3.8.4 gate, so this round wrote through the **branch's own** `lean-gate.sh`. |
| AC-6 the boundary arm | **satisfied** | All seven cases green under their new ids — `(X1)` vacuity guard, `(X2)` armed-with-no-receipt, `(X2b)` suffix non-shadowing, `(X3)` no fidelity, `(X4)` happy path with both exclusions, `(X5)` stale `rendered_from` under a fresh verdict, `(X6)` disarmed. The rename is complete: `git diff origin/main...HEAD -- scripts/check-lean-chain-selftest.sh` shows **zero deletions**, so #406's `(W0)`–`(W5)` block is intact and this branch purely appends; both `lockstep-manifest.tsv` citations are re-anchored, and no stale `(W)` citation survives outside the superseded round-1 record. Caveat W1. |
| AC-7 scenario legs | **satisfied** | The seven `(lean-design-*)` legs are untouched by the delta and green in the full sweep. |
| AC-8 docs | **satisfied** | The clause is "a `Changelog:` trailer is present on the branch" — present, and now also *accurate*, proved through the real release awk programs rather than by reading it. `docs/live-render.md` gains the literal-substitution guarantee alongside the unquoted-placeholder rule, which is the docs half of B1. `run-lean/SKILL.md` 42 ≤ 60 (W4). |
| AC-9 mutation | **satisfied** | Scored against CI's own PR-scoped sweep on this exact head, not the PR's sentence: survivors are `lean-gate.sh::{cmp-eq::1, default::1, default::2}`, `lean-reconcile.sh::{fail-open::2, cmp-eq::1, cmp-eq::2, detector::1, default::1, default::2}`, `check-lean-chain.sh::{cmp-eq::1, cmp-eq::2, cmp-z::1, default::1, default::2}` — **exactly the baseline set on all three guards, zero baseline-absent survivors**, with `check-lean-chain.sh::cmp-z::2` and `lean-gate.sh::cmp-z::1`/`::cmp-z::2` KILLED. Independently: `subst()` adds **zero** sites — all six operators on `lean-gate.sh` are byte-identical across the delta — so it re-keys nothing. Prose caveat W2. |

### What is genuinely good here

The round did not stop at the reported defect. Round 1 handed over a bug in a substitution layer;
the fix went to the layer, not to `shquote`, correctly rejected escaping (version-split in the
opposite direction), and — the part that is easy to skip — made the new case's **teardown part of
the case**, because `(dr2c)` writes the only ampersand-bearing fixture in the file and leaving it
standing would have made the kill unattributable across four cases. Declining a catalog row for a
platform-split mutant is the same discipline: a row there would red the macOS lane for something
that is not a regression.

The merge is the other thing worth naming. #406 rewrote the same guard mid-round and collided on
a case-id block; the resolution kept **both** contracts, recomputed the `-h|--help` range from the
merged header rather than picking a side (verified in both directions here: the header ends at 132
and `--help` prints 131 lines ending at the last header line), and renamed *this* branch's ids
because the incumbent's were already on `main` — then re-anchored the two `lockstep-manifest.tsv`
citations the rename rotted, which is the step that usually gets missed.

### Follow-ups (none blocking)

1. W1 — assert `(X5)`'s inferred-arm skip positively and fix the "both freshness arms" comment.
2. W2 — bring the committed baseline row's wording in line with the PR body's precise form.
3. W3 — the bump derives from the PR title; file it.
4. W4 — re-express `run-lean/SKILL.md`'s cap in units unwrapping cannot defeat; file it.

Everything not in the range above is inherited from the round-1 record at patch `d83eea4fba63`.
