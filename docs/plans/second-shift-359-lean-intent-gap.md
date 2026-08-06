issue: 359
run_id: lean-359-a
session_id: 7563f6ea-6eb4-48c9-9b67-02ba31144621
region: undeclared
disposition: reversible-default-and-flag
ratified: no
ratified_by:

## Gap

D-3 in the pre-flight receipt places the PR build-identity marker's write **at milestone 5**,
on the reasoning that "the PR exists by then". Implementation showed that placement cannot
work, and the receipt could not have known it because the fact is about GitHub's event model
rather than about this repo:

**A PR comment fires no `pull_request` event, so it never re-runs the merge-boundary job.** The
last CI run on a lean PR is the review session's verdict-record push (checklist step 8);
nothing pushes after it. A marker first written at milestone 5 is therefore invisible to the
run that gates the merge, and every lean PR would sit red until an operator re-ran the job by
hand. Measured on this repo: PRs #414, #411 and #407 each merged with `pr-gates` green as their
final run, and `main` carries no branch protection — so that green is maintainer discipline,
which a permanently-red gate erodes rather than enforces.

The decision the receipt does not cover is therefore **when the writer fires**, not whether it
ships (D-3 settles that) nor where its code lives (D-3 settles that too: `lean-gate.sh`).

## Disposition followed

Took the reversible default and flagged it. The writer ships in `lean-gate.sh` exactly as D-3
requires, exposed as a `mark <issue>` subcommand that:

- fires at **checklist step 7**, immediately after the PR is opened — the earliest point at
  which D-3's own stated justification ("the PR exists") holds, and before the review session's
  push, so the marker is present for the CI run that gates the merge;
- is re-called by `cmd_5`, so D-3's milestone-5 placement is still honored literally and a run
  that skipped step 7 still ends up marked;
- is **idempotent by identity** — a marker carrying this run's id suppresses the write, while a
  different build session on the same PR still posts its own (D-4).

Reversible: the step-7 call is one line in `SKILL.md` and one `cmd_mark` invocation. Removing
it leaves the milestone-5 write D-3 specified, unchanged and still correct — the consequence is
the manual CI re-run described above, not a broken gate.
