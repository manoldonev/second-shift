# Interview — the fourth stage of `/intake`

Read by `/intake-toolkit:intake` only. The Interview settles the ticket's load-bearing decisions
with the operator — one at a time, each with a grounded recommendation — and ends with a Decision
Ledger, its Open Regions and a Surface Inventory, in memory, for the Receipt. On a split it runs
once **per slice**.

## The protocol

The interview itself is `plan-interview`'s protocol, steps 2 to 5: read
`$SKILL_DIR/../plan-interview/SKILL.md` and follow its **materiality bar** (what the user gets
first, then how it is built, and data provenance), its rule that the ticket's candidate fixes are
input rather than the option set, its **surface enumeration**, its **traversal** choice, and its
**What NOT to do**. `interviewing-baseline` owns the loop rules. This file adds only what is
specific to an intake ticket.

## What the register starts from

- **Requirements' rows.** A rough input arrives with the rows its interview already settled
  (`user-answered`, `user-delegated`, `deferred`). They are settled: never re-ask one, and carry it
  into the ledger as it stands.
- **Requirements' open gaps** — spec-reviewer findings only the operator can close. Each is a
  question here.
- **Explore's snapshot and the pool items that pass the materiality bar.** Each surviving item is a
  row, an option, a probed fact or a question.
- **Split's outcome** — on a split, the slice's own scope, the decisions the parent already took for
  every slice (the brief's guardrails and quarantine tags), and the seam items the pool raised for
  this slice.

## Per ticket, per slice

**On a split** the interview runs for each slice in turn — the slices without a receipt, on a
restart. A slice's register holds only what moves that slice; a decision the parent already took
is cited, not re-asked. Its pool items are the ones Explore sorted to it, and its `## Fan-out`
lists exactly those and names the shared run (`receipt.md`).

## Back to Split

When the register passes about **10 material decisions**, the ticket is likely a decomposition the
classification missed: say so, stop interviewing, and return the ticket to Split (`split.md`) with
the register so far. Split's decision then reshapes what is interviewed; the rows already settled
stay settled. A ticket that has already been through Split does not return there a second time —
escalate instead.

The fan-out already ran on the unsplit ticket by then, and its lenses never saw the seams. So:

- **Split decides "not split"** → no new fan-out; the interview resumes on the pool it has.
- **Split creates slices** → the sequence goes on to Explore, which runs the split's one fan-out on
  the parent plus the slice list (`explore.md`, "After a return from the Interview"). The pre-split
  pool is superseded: its items already settled as rows stay settled, and each slice receipt names
  the earlier run on its `Run:` line.

## Escalation

Stop and present what you understood, what is blocking, the options and one clear question when
the operator's answers contradict each other or the code and rechecking does not resolve it, or
when the register is implausibly **thin** for the scope (a page of rendered-output criteria
answered by a handful of transport decisions has been mis-scoped — the surfaces are where the
missing rows are; widen).

The answer's provenance follows its channel: given **in the session** → `user-answered`; given **in
a ticket comment**, because the operator chose to answer later and the question was posted →
`ticket-sourced`, the Resolution citing the comment's URL.

## Exit

The Interview is done when the register is empty **and** every surface is accounted for — each
material decision carrying a non-`assumed` provenance, each surface decided by a row or out of
scope with a reason. Trivial work exits at once with both explicit empty forms. Nothing is written
to disk here: the Receipt writes the record.
