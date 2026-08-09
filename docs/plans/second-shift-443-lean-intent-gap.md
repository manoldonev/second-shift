issue: 443
run_id: lean-443-20260809a
session_id: 4682a97a-87b5-4847-a7c5-82ba269ac4e6
region: undeclared
disposition: reversible-default-and-flag
ratified: no
ratified_by:

## Gap

**The decision: an unrelated harness fix rides this PR (AC-10).**

Milestone 3 red-lined on `lean-gate-selftest.sh` case `(k6)`, in a file this ticket does not
touch. Root cause: case `(d5)` invokes the gate's `entry` subcommand without `env -u RUN_ID`, and
`entry` is one of the three subcommands that PERSIST the run-id cache. An operator's exported
`RUN_ID` therefore seeds the fixture's cache; `(k6)`'s `cmd_mark` no-op test later resolves an id
no fixture marker carries, and falls through to the **live `$GH_BOT` write path** — a selftest one
step from posting a real PR comment. The suite is green in CI, which exports no `RUN_ID`, and red
for any operator who followed `run-lean` SKILL.md step 2 and kept theirs exported. Every sibling
`entry` case in that file already guards this; `(d5)` alone was missed.

The receipt covers gate OUTPUT CLASSES. It says nothing about the lean harness's own test
hermeticity, so whether that fix rides this PR or a separate ticket is not a call this run's
scope settles. **Reversible:** the fix is one commit (`905537a`) touching one call site in one
selftest, and lifting it onto its own PR costs a cherry-pick and a spec edit removing AC-10.

**A second, lesser call, flagged rather than ratified separately.** AC-7 requires that every arm
whose green-path assertion was removed keeps a kill criterion, and forbids demotion to a bare
exit-status assertion. Case `(V3b)` pinned the chain walk's printed LINK COUNT, which class (a)
now silences — and no replacement observable exists: an unbounded walk is provably the bounded
walk plus one self-link with an identical terminal state, so no exit code, violation message or
round attribution can separate the two readings. I read AC-7 at ARM granularity (the
inheritance-chain arm keeps `(V4)`/`(V5)`) and treated the search bound as a sub-behavior. AC-7's
own stated witness backs this: the site is `cmp-eq` ordinal 6 and sits outside the sweep's `K=2`
window, and a cold sweep over this branch (36 computed verdicts, zero cached) returned 12
survivors, all baseline-present, none absent. The interpretation is disclosed in the spec (D-5),
in the case comment, and in the PR body rather than left implicit.

## Disposition followed

Took the reversible default and flagged it: the harness fix is committed here, isolated in its
own commit, recorded as an explicit AC in the spec, and raised for ratification before the review
handoff rather than after. The alternative — leaving a known live-write path in a shipped
selftest so that this PR stays narrow — was rejected as the worse default, but it remains the
operator's call to reverse.
