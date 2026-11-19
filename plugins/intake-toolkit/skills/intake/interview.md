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
  into the ledger as it stands. The one exception is a row that contradicts a sentence of the
  parent's text: it is asked again ("The parent ticket" below).
- **Requirements' open gaps** — spec-reviewer findings only the operator can close. Each is a
  question here.
- **Explore's snapshot.** Questions go to the operator once the snapshot is written, before the
  pool is in (`explore.md`, "Snapshot, then the interview, then the pool").
- **The pool items, when the workflow completes.** Each item you checked from its pointer that
  passes the materiality bar is a row, an option, a probed fact or a question. An item about a
  question you asked before you read the pool is tagged `already-had`.
- **The knowledge source's answer**, when Requirements got one ("The knowledge source" below).
- **The parent ticket's body and the siblings' keys and summaries**, under jira, when the issue has
  a parent ("The parent ticket" below).
- **Split's outcome** — on a split, the slice's own scope, the decisions the parent already took for
  every slice (the brief's guardrails and quarantine tags), and the seam items the pool raised for
  this slice.

## The knowledge source

The provider's answer is evidence, read beside the code, never in place of it
(`interviewing-baseline`, "Knowledge source"):

- **A fact the answer states and the code does not contradict** is adopted as a `codebase-derived`
  row citing `cited (kb): <kb-page>`, `<kb-page>` copied from the answer's `Sources:` list. Where a
  command can check it, run the command instead and record `run:` evidence.
- **A fact where the answer and the code disagree** is asked, never picked silently. Put both
  sides to the operator, with your recommendation. The row is `user-answered` — or `deferred`
  under a `pause-and-ask` region when the operator parks it — never `codebase-derived` citing
  `kb`. It says which side this ticket follows and carries the fixed marker, naming the page and
  which side is behind: `kb-conflict: <kb-page> (kb stale)` when the page is out of date,
  `kb-conflict: <kb-page> (kb ahead)` when the page states a direction the code has not reached.
- **A gap the answer reports** is a question like any other, when it passes the materiality bar.

## A late finding

A pool item can contradict an answer the operator already gave, `user-answered` or
`user-delegated`. Show the item beside the earlier answer and ask that one question once more. The
second answer stands. This is the one exception to "never re-ask" (`interviewing-baseline`, rules 5
and 6).

Tag the item `already-had`. When the second answer changes the row, its disposition reads
`became D-n` and the row gains `From: F-n`. The tag keeps the row out of the tally's `rows added`.

## The parent ticket

Under jira, the parent's text and the siblings' summaries are context. They rank below the issue's
own text (`interviewing-baseline`, "Precedence when sources disagree"):

- **A row whose resolution contradicts a sentence of the parent's text** goes to the operator as
  a question. Quote the sentence. This holds whatever settled the row: a Requirements answer, the
  issue, the code, the pool, the knowledge source or your own recommendation. Where the issue's
  text is the other side, recommend the issue's text. The answer is `user-answered`.
- **A scope exclusion in the issue** ("not in this ticket") is checked against the siblings'
  summaries. When no sibling owns the excluded work, ask the operator who does.
- **A fact the parent or a sibling states and the issue does not contradict** may enter as a
  `ticket-sourced` row of Kind `fact`. Its Resolution quotes the sentence and cites that ticket by
  URL (`https://<site>/browse/<KEY>`).

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

The fan-out ran, or still runs, on the unsplit ticket by then, and its lenses never saw the seams.
So:

- **Split decides "not split"** → no new fan-out; the interview resumes on the pool it has, or
  takes the pool when the run completes.
- **Split creates slices** → the sequence goes on to Explore, which stops an unread run and
  discards it, then runs the split's one fan-out on the parent plus the slice list (`explore.md`,
  "After a return from the Interview"). The pre-split pool is superseded: its items already settled
  as rows stay settled, and each slice receipt names the earlier run on its `Run:` line.

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

The Interview does not close until the pool is read, or the run has ended in its skipped or failed
form. It is done when the register is empty **and** every surface is accounted for — each
material decision carrying a non-`assumed` provenance, each surface decided by a row or out of
scope with a reason. A surface that other code calls or parses is a `contract`: its row states the
inputs, the outputs and the errors (`interviewing-baseline`, "The Surface Inventory"). Trivial work exits at once with both explicit empty forms. Nothing is written
to disk here: the Receipt writes the record.
