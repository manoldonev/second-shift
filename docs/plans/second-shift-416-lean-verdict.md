# lean review verdict — #416

verdict=approve
run_id: review-416-2
session_id: f474ff10-a0ee-41d0-b5da-5ca980a85a3a
rounds: 2
pr: #422
reviewed_head: d861aced7d638663019bfed75b9fba386070a8b5
reviewed_patch_id: 1b79a7ae86827b5bc1b3f04a0a2da8b2038e790c
inherited_patch_id: 479246a9ee21e922172224cc1f940f9a98393ece
inherited_from_verdict: 4d5c0d943bd1b9f470bac74db04ae85bc4a6ca35
fidelity: not-applicable
model: unknown

Round 2, inheriting round 1's coverage of patch `479246a9ee21` — `bash G delta 416` printed
`4d5c0d9..HEAD` (11 files, +179/-30). Round 1's record
([`second-shift-416-lean-verdict.md`](docs/plans/second-shift-416-lean-verdict.md)) was read first;
each of its three blockers is scored below against the delta, and every `AC-n` is scored against the
whole spec. Panel: test-coverage and maintainability, on the delta only (round 1 ran the full six
and every one of them approved, so the marginal value here is in the two dimensions the fix
actually moved). Both returned; every finding below is reproduced locally.

Design fidelity: **not-applicable** — the spec declares no `## Design` section and this repo
configures no `design.provider`, so step 5b does not arm.

## Verdict: approve — 0 blockers

### The three round-1 blockers, each closed and each proven here

**B1 — the frozen `run_id: unset` header. CLOSED.** `heal_progress_run_id` rewrites the
placeholder from `ensure_progress_file`, gated on the BUILD CACHE agreeing with the resolved id.
Reproduced end to end on a scratch github fixture, running the branch gate and the round-1 gate
(`4d5c0d9`) side by side over SKILL.md's own ordering — `entry` with no `RUN_ID`, then the export,
then the run:

```
BASE (4d5c0d9)   header after step 1: run_id: unset   ... and it never moves again
BRANCH           header after step 1: run_id: unset
  (a) milestone call carrying an ad-hoc RUN_ID, identity NOT established  -> run_id: unset
  (b) after `claim` establishes the identity, the next milestone writer   -> run_id: lean-99-a
  (c) a fresh `entry` once the cache holds it                             -> run_id: lean-99-a
  (d) a `verdict` call under a REVIEW identity                            -> run_id: unset
```

(a) and (d) are the two leaks AC-13 forbids, and neither is reachable. (a) is not vacuous: that
milestone call did reach the writer — it appended `| milestone-1 | attempt | no committed spec …`
— so the cache compare, not the absence of a write, is what held the header.

**B2 — `doctor.sh` could not see `.claude/settings.json`. CLOSED.** The opt-out scan loops
`"$SETTINGS" "$LOCAL_SETTINGS" "$USER_SETTINGS"` now, matching what this same PR's
`audit_toolkit_opted_out()` already did — the self-disagreement that made B2 cheap to prove is
gone. `settings-optout-committed.json` is `settings-green.json` with one boolean flipped, so the
new scenario's "only the file moves" is literally true.

**B3 — five arm-count statements. CLOSED, by dropping the counts rather than re-pinning them.**
`lean-reconcile.sh`'s two range statements, both `tracker/README.md` sites and
`lean-reconcile-selftest.sh`'s `(P)` prose now read "every other check" / "all but one". A
repo-wide grep for count-and-range shapes over `plugins/ docs/ scripts/ tools/` finds one
survivor, `lean-reconcile-selftest.sh:543` ("proves checks (2)-(6) RAN") — and it is *accurate on
this branch*: arms run (1)…(6), so (2)-(6) names exactly the tracker-independent set. It was the
stale one at the base, where arms stopped at (5). Nothing owed.

**The spec amendments tighten, they do not excuse.** AC-5 and AC-10 gained the file-independence
the round-1 proof showed was missing, AC-12 gained the arm-count obligation, and AC-13 is new. Each
adds an obligation the diff then meets; none loosens an `AC-n` so an unmet one could score. The
amendment landed in the same commit as the fix, and milestone 5 has not run at all — the build's
progress file records milestones 1, 2 and 3 — so "before milestone 5" is unambiguous here.

## Warnings

**W1 — AC-13's mechanism sentence is false on the github adapter, which is the default.**
`docs/plans/second-shift-416-lean.md:151` and `lean-gate.sh:630` both say the header is rewritten by
"the first call to ESTABLISH an identity". Only the **jira** arm of `cmd_claim` does that
(`lean-gate.sh:844` — `ensure_progress_file; append_line …`). The github arm swaps the label and
posts the marker comment and never touches the progress file, while the identity IS established for
it, at the dispatch (`:352`-`:360`), adapter-blind. So on a github run the heal lands at the first
milestone, not at `claim`. **This PR's own build run shows it**: issue #416 carries the bot
`lean-claimed` comment (`run_id: lean-416-a`) while `416-lean-progress.md` carries no `| claim |`
line at all — the github arm wrote nothing there.

Nothing behaves wrong: no reader opens the header between `claim` and milestone 1, and
`lean-reconcile.sh` is an operator's pre-merge check long after milestone 5. AC-13's headline —
"the progress header's `run_id` cannot freeze" — holds in all four directions probed above, which is
why this is not a blocker. But the sentence is the one a future reader will reason about ordering
from, and it is the second time in this ticket that a claim about *which subcommand writes a record
first* turned out to be adapter-specific. Independently found by the maintainability reviewer, which
called it a blocker; scored down here because the contract holds and only its description does not.

**W2 — the heal writes through a fixed-name temp file.** `lean-gate.sh:648` uses
`"$PROGRESS_FILE.heal"` where the same file reaches for `mktemp -t lean-claim.XXXXXX` (`:866`) for
the analogous write-then-rename. Two gate invocations on one issue — a retry launched over a stuck
process, an operator running `bash G 4` beside a run — can interleave `awk`/`mv` on that one path.
Single-actor-per-issue is the norm and this is the pipeline's own assumption elsewhere, so it is a
deviation from the file's idiom rather than a live bug.

**W3 — `ensure_progress_file` now returns the heal's exit status.** Previously it always fell out of
an `if` at 0; now a failed `mv` (full disk, read-only state dir) returns `rm`'s code. All six call
sites (`:683`, `:707`, `:812`, `:844`, `:1356`, plus `append_line`) ignore it today, so this is
latent. A trailing `return 0` would keep it that way.

**W4 — `(ea7)`'s new positive assertion pins which verdict diagnostic fires first.**
`grep -qF '[lean-gate] verdict:'` matches only `envfail` output; every `warn` refusal in
`cmd_verdict` prints `[lean-gate] ✗ verdict:` and would NOT match. The case passes today by reaching
the patch-identity `envfail` at `:2002`. It discriminates correctly — the precondition's own refusal
carries the `✗` and the `no entry attestation` string the case still forbids — but a fixture drift
that made a `warn` path fire first would red it while the D-5 exemption it tests still worked. The
round-1 remedy (`rc != 2`) was worse, and this was the right call; the residue is worth knowing.

**W5 — `review-lean` step 4 still over-attributes rc 2.** "An exit 2 here means no entry attestation
is READABLE" — `exit 2` is `envfail`'s general code, and `delta` reaches it for "not in a git repo",
"cannot resolve the main checkout from …", and "unknown tracker.type" among others
(`lean-gate.sh:169`-`:256`). Strictly better than the round-1 text it replaces, and the message on
screen names its own cause; the sentence is the part that is absolute.

**W6 — the refusal's new second-cause sentence has no fixture.** `lean-gate.sh:2337`'s "Or the
record is simply out of reach…" line is asserted nowhere; `(ea3)` pins the remedy string one line
above it. Pinning a second message literal would be more of the same class rather than new
coverage, so this is a note, not a request.

## Acceptance criteria

| AC | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | One `ledger=`/`lines=`/`session=` row, guarded by `entry_row_present`, shape pinned in the primitives block. `(ea1)`/`(ea2)`; `(ea12)` re-asserts single-row on the healing call. |
| AC-2 | satisfied | `audit_toolkit_opted_out()` picks the wording, the ledger predicate decides. `(ea8)`/`(ea9)`/`(ea10)`. Unchanged this round. |
| AC-3 | satisfied | `require_entry_attested` at the dispatch (`:2340`), exit 2, remedy, no `attempt` line, `entry`/`verdict` exempt. The amended second-cause sentence ships at `:2335` (W6). `(ea3)`/`(ea5)`/`(ea6)`/`(ea7)`. |
| AC-4 | satisfied | Arm (6) at `lean-reconcile.sh:477`, presence-only, no adapter branch. |
| AC-5 | **satisfied** (was unsatisfied) | The scan reads `$SETTINGS`. Verified by re-applying `doctor-optout-committed-file` from the catalog with `sed -E` against a pristine copy: `doctor-selftest.sh` rc 1, and the ONLY case that reds is `opt-out-committed` — so the new scenario is the sole killer, not a restatement of `opt-out`. |
| AC-6 | satisfied | Onboard step 2 + step 6. Its doctor claim, and `docs/onboarding.md`'s, and the `8e9a7af` release bullet's, are all true now that AC-5 is. |
| AC-7 | satisfied | `(ea1)`–`(ea4)`, including the D-13 milestone-4 backstop paired red/green. |
| AC-8 | satisfied | Every lean leg acquires its row by calling the gate; `(lean-entry)` composes the refusal at `all` and at a single milestone with the fix budget untouched. |
| AC-9 | satisfied | `(Q)`'s pair reds without the row and greens with it. |
| AC-10 | satisfied | Three scenarios: `opt-out` (FAIL), `opt-out-lane-off` (the surviving `warn`), `opt-out-committed` (same FAIL, other file). The last pair differs by one boolean and one filename. |
| AC-11 | satisfied | Six rows. Round 1 verified four; I re-applied both new ones verbatim with the sweep's own `sed -E`, non-no-op both, against a pristine copy: `doctor-optout-committed-file` → rc 1 (killer: `opt-out-committed`), `lean-gate-runid-heal` → rc 2 (killers: `(ea12)` and `(n10)`). No baseline re-key owed — round 1 established that by site identity, and this round's edits land below every swept site. |
| AC-12 | satisfied | The three originally-named doc sites plus the five arm-count statements, dropped rather than re-pinned. `Changelog:` trailers state the no-grandfather rollout; `Changelog: none.` is the sanctioned no-op form (`derive-release.sh:239`-`:242`), so the four docs commits ship no bullets. |
| AC-13 | satisfied | The freeze is closed in all four directions probed above, and the guard is the cache compare — verified by deleting it, which reds `(ea11)`, and reds it *first*: without `(ea11)`'s milestone call the header is still `unset` when `(ea12)` runs, so `(ea12)` alone would not catch that mutant. Its mechanism *sentence* over-describes the github path (W1); the property it names holds. |

## Verification I ran

- Full selftest sweep, all **63** suites, `-P 4`, **without** `SKIP_STRESS`, with
  `env -u CLAUDE_CODE_SESSION_ID -u RUN_ID -u LEAN_RUN_MODEL -u GH_BOT`: **rc 0**, zero `FAIL:`
  lines, zero `✗`. (`xargs` propagates non-zero under `-P`, so rc 0 is the whole-sweep claim.)
- `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh`: clean. `jq empty` over every `*.json`:
  clean.
- `check-frozen-files.sh a2b158f`: clean. `check-changelog-trailer.sh a2b158f`: OK.
- `prose-budget.sh`: **19 FAILs**, the same count round 1 measured at the base and on the branch.
  `review-lean/SKILL.md`, the file this round edits, has no baseline row (`NEW (add to baseline)`),
  so the edit adds no FAIL. `run-lean/SKILL.md` is 42 lines, inside its 60-line cap.
- **Targeted mutation probes on the round-2 assertions**, beyond the two catalog rows, because a
  new assertion that never reds is decorative: deleting the cache compare at `lean-gate.sh:646`
  reds `(ea11)` (and `(ea12)` behind it — but only because `(ea11)` ran first and left the header
  stamped; on its own `(ea12)` would still see `unset` and pass, so that mutant's coverage
  originates with `(ea11)`). Gating `verdict` in the dispatch list at `:2340` reds `(ea7)` and
  nothing else. Removing the heal call reds `(ea12)` and `(n10)` while `(ea11)` correctly survives,
  since a header that never heals is a header that stayed `unset`. Three mutants, three distinct
  originating cases; the worktree was byte-restored and re-checked after each.
- The B1 repro above ran the round-1 gate and the branch gate against one fixture, so the
  before/after is the same tree.
- **CI still cannot be read**: `gh pr checks 422` reports *"no checks reported on the
  'lean/second-shift-416' branch"* — zero check runs have ever been created for this PR, the same
  account-level Actions runner outage round 1 hit. Everything above is local evidence; no lane on
  this PR has been observed green in CI, and this approve is given on that basis.
- W2 was found by the maintainability reviewer; W1 independently by it and by me; W4/W5/W6 are
  mine. The test-coverage reviewer returned approve with two nits, both subsumed above.

## Strengths

- Two mutation probes SURVIVED during the build and the **code** moved, not the record — a `-s`
  test behind the cache compare and a first-match counter in the heal's `awk`, both deleted as
  unreachable. The one line that still survives by construction is labelled in the source as a cost
  guard so a later sweep does not read it as a coverage hole. That is the honest handling of a
  survivor, and it is rarer than it should be.
- `attest_at` losing its optional run-id parameter is the real fix for B1's second half. The helper
  now drives `entry` with `RUN_ID` unset — the ordering every honest run is in — so the suite can no
  longer be green on a header the field would never see. The jira claim case `(n10)` consequently
  became a heal assertion, which is why deleting the heal reds two cases and not one.
- `opt-out-committed` moves exactly one variable. Its fixture is `settings-green.json` with a single
  boolean flipped, so the pair isolates the file rather than confounding it with content.
- Dropping the arm counts instead of re-pinning them applies #414's remedy on the file #414 fixed,
  which is the only version of that fix that survives the next arm.
