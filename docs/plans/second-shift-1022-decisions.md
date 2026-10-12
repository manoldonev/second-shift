# Intake receipt — #1022 the receipt records every intake step and run.sh lints it at launch

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Older receipts under the launch lint | A `Receipt: v<N>` line; a section is mandated only from the version that introduced it; no line = v1; `## Intake steps` starts at v2. Options weighed: version plus an upgrade at launch; re-run intake; lint only the scheduler-read core at launch. Asked before the fan-out pool, on the operator's instruction | user-answered | intent |
| D-2 | A version above what the lint knows | The lint fails; run.sh refuses under a named slug (run.sh:49, "a failed read is never a pass") | user-delegated | intent |
| D-3 | Where the version table lives | In ledger-lint.sh; interviewing-baseline names each section's starting version, in lockstep. Options weighed: a separate table file read by both | user-delegated | intent |
| D-4 | Where the version line goes | Exactly once, before the first `##` heading; two lines, or one inside a section, fail. Options weighed: first line only; anywhere | user-delegated | intent |
| D-5 | Step keys and order | Requirements, Split, Explore, Fan-out, Dup-scan, Post-merge scan, Sizing (decided at the parent epic's intake, #1016) | user-answered | intent |
| D-6 | A section title used twice | A named violation; today the lint emits none and both readers take the first copy — run: `ledger-lint.sh --receipt <receipt with ## Checks twice, first empty>` → only "Checks has no command" | user-answered | intent |
| D-7 | Where run.sh lints | Parked under OR-1 | deferred | open |
| D-8 | Records already committed on the lane branch | Not re-linted — run: `sed -n 935p plugins/dev-pipeline/skills/run/run.sh` → "record: already committed on $BRANCH — the receipt on disk is not consulted" | codebase-derived | fact |
| D-9 | Refusal slugs and exit codes | `env-receipt-invalid` (lint rc 1) exits 3; `env-receipt-lint-unavailable` (any other result) exits 2; both added to exit_code_for, the header comment and SKILL.md's table. Options weighed: reuse env-no-record for the invalid case | user-answered | intent |
| D-10 | How run.sh finds and trusts the lint | The ENABLED intake-toolkit: env override, else installPath from `claude plugin list --json`; `ledger-lint.sh --receipt-version` prints the highest version it knows; refuse when the probe fails or is lower than the receipt's version. Options weighed: the LOCKSTEP sibling-plugin-root resolver plus the probe; a bundled lint copy | user-answered | intent |
| D-11 | run-selftest's receipt fixture | A full receipt-shape rewrite of the one fixture writer, keeping the 4-column D-1 text case (a) greps for — run: `ledger-lint.sh --receipt <copy of run-selftest.sh:175's fixture>` → "FAIL — 7 violation(s)" | codebase-derived | fact |
| D-12 | Receipts from intake-orchestrator and intake-interviewer until slice 2 | They fail the launch lint; the refusal says rerun plan-interview (decided at #1016) | user-answered | intent |
| D-13 | What the `Sizing:` line records | The weight intake decided; applying the label is a tracker write after the lint, not a receipt step. Options weighed: drop the line; size before writing | user-answered | intent |
| D-14 | A stale remote ref skipping the disk receipt | Filed separately as #1024; this ticket relies on committed_record_exists as it is. Options weighed: fold it in; note only | user-answered | intent |
| D-15 | The ExitPlanMode hook | Unaffected: the new checks sit in receipt mode, and the hook runs the lint without --receipt — run: `sed -n 78p plugins/intake-toolkit/hooks/exitplan-ledger-gate.sh` → `if out=$("$LINT" "$target" 2>&1); then` | codebase-derived | fact |
| D-16 | Keyed-line grammar | Parked under OR-2 | deferred | open |
| D-17 | Duplicate scan | No candidates — run: `dup-scan.sh --issue 1022` → "no candidates at or above threshold 12" | codebase-derived | fact |
| D-18 | Which receipt versions the duplicate-title check (D-6) covers | Every version, v1 included: it is a validity rule, not a mandated section, so D-1's version gate does not apply — a v1 receipt with a title used twice already carries a section no reader reads. Added at BUILD, no row covered it | user-delegated | intent |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The launch lint's exact place in run.sh's phase-3 preflight | reversible-default-and-flag |
| OR-2 | The `## Intake steps` grammar | reversible-default-and-flag |

OR-1 default: after the design check (run.sh:939) and before the claim, so the run-selftest cases that assert env-design-undeclared keep their refusal; moving it is a line move. OR-2 default: found with section_of, the reader run.sh uses; one non-bulleted `Key: outcome` line per key, each key exactly once, in order, with a non-empty, non-dash outcome; no sub-heading inside the section; a trailing CR tolerated; the key spelled `Dup-scan` (receipts on disk also use "Duplicate scan"). Tightening or loosening a rule is a regex edit with a selftest case.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The receipt's `Receipt:` line and `## Intake steps` section | decided (D-1) |
| S-2 | run.sh's refusal output for an invalid receipt | decided (D-9) |
| S-3 | run.sh's refusal output when the lint cannot be trusted | decided (D-10) |
| S-4 | SKILL.md's exit-code table | decided (D-9) |
| S-5 | ledger-lint's `--receipt-version` output | decided (D-10) |
| S-6 | The ExitPlanMode hook's output | decided (D-15) |

## Checks

- `bash tools/install-topology-selftest.sh`

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: reader-parity fable 4/6 · launch-sequencing fable 6/6 · cross-plugin-discovery opus 6/6 · grammar-and-live-receipts fable 6/6 · premortem fable 3/6
Tally: rows added 6 · snapshot claims overturned 1 · questions added 4

The snapshot was written after the completion notice previewed the first pool items; D-1 was asked before the pool, on the operator's instruction.

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | reader-parity | The lint locates sections three ways that disagree on heading variants | new | became D-16 |
| F-2 | reader-parity | A duplicated title yields only the first copy, and no violation names it | already-had | became D-6 |
| F-3 | reader-parity | A sub-heading truncates the section; CRLF carries a CR into key lines | new | became D-16 |
| F-4 | reader-parity | The ExitPlanMode hook runs the lint without --receipt | new | became D-15 |
| F-5 | launch-sequencing | The only clean placement is between run.sh:936 and phase 4 | already-had | became D-7 |
| F-6 | launch-sequencing | Exit 3 needs the slug taxonomy edited in three places | new | became D-9 |
| F-7 | launch-sequencing | A stale remote ref makes run.sh skip the disk receipt | new | became D-14 |
| F-8 | launch-sequencing | run.sh has no path to the lint; an existing sibling resolver exists | new | became D-10 |
| F-9 | launch-sequencing | The selftest fixture fails the lint with 7 violations | new | became D-11 |
| F-10 | launch-sequencing | The lint and run.sh already agree on the first copy of a duplicated title | already-had | became D-6 |
| F-11 | cross-plugin-discovery | A fixed hop finds the lint in a checkout and misses it in the cache | new | became D-10 |
| F-12 | cross-plugin-discovery | The sibling resolver takes the highest cached version, not the enabled one | overturned (snapshot: "candidate: the fan-out staging lookup (find by name, sort -V, tail -1)") | became D-10 |
| F-13 | cross-plugin-discovery | rc 127, 126 and 2 must not read as "receipt bad" | new | became D-9 |
| F-14 | cross-plugin-discovery | An older lint passes silently; the lint has no version flag | new | became D-10 |
| F-15 | cross-plugin-discovery | Exit codes come from the slug; receipt checks sit where RECORD_SOURCE=receipt | new | became D-9 |
| F-16 | cross-plugin-discovery | install-topology-selftest, excluded from the default sweep, catches a checkout-only lookup | new | became the Checks line |
| F-17 | grammar-and-live-receipts | Two heading grammars; a nested heading shadows a later section | new | became D-16 |
| F-18 | grammar-and-live-receipts | The Key: regex accepts duplicates and misses bulleted keys | new | became D-16 |
| F-19 | grammar-and-live-receipts | The fixture rewrite is a full receipt-shape upgrade | new | became D-11 |
| F-20 | grammar-and-live-receipts | A mandatory section flips the passing receipts to FAIL | not material | not material — D-1 keeps v1 receipts passing |
| F-21 | grammar-and-live-receipts | Step outcomes are spelled differently across receipts today | new | became D-16 |
| F-22 | grammar-and-live-receipts | run.sh resolves tools only in its own plugin | already-had | became D-10 |
| F-23 | premortem | A new env-* slug exits 2 unless exit_code_for changes | new | became D-9 |
| F-24 | premortem | A lint before the design check preempts cases that assert env-design-undeclared | new | became D-7 |
| F-25 | premortem | The Sizing line is written before sizing happens | new | became D-13 |

### Snapshot

    # #1022 snapshot — register before the fan-out pool (internal)
    
    Written after the completion notice's preview showed the first pool items (the snapshot was due before it); contents are the pre-notice register only.
    
    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Receipt version | `Receipt: v<N>` line; a section is mandated only from the version that introduced it; no line = v1; `## Intake steps` starts at v2 (user-answered, before the pool) |
    | D-2 | Version above what the lint knows | Refuse under a named slug (user-delegated) |
    | D-3 | Where the version table lives | In ledger-lint.sh; interviewing-baseline names starting versions in lockstep (user-delegated) |
    | D-4 | Where the line goes | Exactly once, before the first `##` heading (user-delegated) |
    | D-5 | Step keys and order | Requirements, Split, Explore, Fan-out, Dup-scan, Post-merge scan, Sizing (from #1016 D-5) |
    | D-6 | Duplicate-title check | The lint rejects a section title that duplicates another (from #1016 D-5) |
    | D-7 | Where run.sh lints | Before the claim, on a disk receipt only; committed records not re-linted (from #1016 D-2/D-3) — exact line unexplored |
    | D-8 | Refusal exit code and slug | Ticket says exit 3 — slug taxonomy unexplored |
    | D-9 | Lint missing or unrunnable | Refuse under a named slug — run.sh:49 |
    | D-10 | How run.sh finds the lint across plugins | Unexplored; candidate: the fan-out staging lookup (find by name, sort -V, tail -1) |
    | D-11 | run-selftest fixtures | Upgrade every receipt fixture to pass the lint |
    | D-12 | Interim until slice 2 | Receipts from intake-orchestrator/intake-interviewer fail the launch lint; refusal says rerun plan-interview (accepted in #1016) |
