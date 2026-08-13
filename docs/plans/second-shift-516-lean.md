# #516 — intake scans for duplicates before a ticket becomes eligible to run

Two tickets described one defect. Both cleared intake, both carried the queue label, both
became eligible, and both were run — one of them finishing nothing. Nothing in the intake
path ever looked at what was already queued.

This adds that look: a deterministic scan at every intake-role exit, over the tickets that
are actually eligible or in flight, whose output is a ranked proposal for a reader to judge.

## Approach

A shell tool plus a paired selftest, with the three intake exits wired to it — not SKILL
prose. The tier map routes prose to no guard and forbids prose-presence guards, so a
prose-only slice would ship unverifiable.

`plugins/intake-toolkit/skills/plan-interview/tools/dup-scan.sh`, beside `ledger-lint.sh`.
That directory is already the de-facto home for cross-skill intake tooling: `ledger-lint.sh`
lives there and `intake-orchestrator` invokes it through
`${CLAUDE_PLUGIN_ROOT}/skills/plan-interview/tools/…`. Putting the second such tool anywhere
else would invent a convention to hold one file.

**The scorer is mechanical, and that is the point.** Title-token overlap (lowercased,
stopworded, crudely de-pluralized) plus body-symbol overlap over four closed classes — file
paths with a known extension, long flags, exit/return codes, and cross-references to other
items. Not agent judgment over raw prose and not the tracker's own relevance search: both are
unguardable, and a scan whose verdict no fixture can pin is a scan nobody can tell has broken.

```
score = TITLE_WEIGHT * |shared title tokens| + |shared body symbols|
```

Titles outweigh bodies because in a single-product tracker the bodies converge — nearly every
ticket here names the same handful of scripts — while two titles sharing three content words
is rare.

**Calibration (OR-1).** Measured against the pair that motivated the ticket, scored inside the
queue they were actually filed into:

| Subject | Candidate | Score | Verdict |
| --- | --- | --- | --- |
| #500 | #502 | **16** | the true duplicate |
| #500 | #514 | 8 | related, distinct — the nearest non-duplicate |
| #500 | everything else queued | ≤ 3 | unrelated |
| #502 | #500 | **16** | symmetric |

`THRESHOLD=12` sits in the 8–16 gap; `TITLE_WEIGHT=3`. Both are one constant each and both
are flags. The measurement is not a comment — `corpus-live.json` is that real corpus, frozen
as a fixture, and the selftest asserts both halves of the separation, so retuning the constant
without re-reading the measurement reds the suite.

**Known limit, stated rather than discovered later.** The scorer measures textual overlap. It
would not have surfaced #503 against #516 (score 3) even though those two touch the same file —
the bodies genuinely share almost no text. Same-file collision detection is a different
predicate and is not in scope here.

## Acceptance criteria

- **AC-1** — Intake surfaces likely duplicates among open queue-labeled tickets before a new
  one is labeled. `dup-scan.sh` fetches the open corpus, ranks it against the subject, and
  emits every candidate at or above the threshold.
- **AC-2** — A suspected duplicate is reported as a decision for a reader, never auto-closed.
  The tool makes no tracker write of any kind, and its report names the three verdicts a
  reader may reach and states that nothing is closed on its output.
- **AC-3** — The corpus is open tickets carrying the queue label **or** the claimed label. A
  claim consumes the queue label, so a queue-only corpus is blind to work already in flight;
  the union is de-duplicated by number, so a ticket carrying both is scored once, and the
  subject itself is excluded when it is already a filed item.
- **AC-4** — The verdict is an exit code: `0` no candidates, `10` candidates found, `2`
  usage/IO/tracker error. A failed `gh`, an unparseable config, or a non-array tracker
  response exits `2` — never `0`. "Could not look" and "looked and found nothing" are
  different answers.
- **AC-5** — Under `tracker.type: jira` the tool prints an explicit not-applicable line naming
  that the tracker has no queue label, exits `0`, and makes no tracker call at all.
- **AC-6** — The threshold, the title weight and the corpus limit are flags over stated
  defaults; `--explain` prints the whole ranked corpus so a retune is a measurement. A corpus
  clipped by the limit warns rather than reading as complete.
- **AC-7** — The three intake-role exits (`intake-orchestrator`, `intake-interviewer`,
  `plan-interview` pre-flight) run the scan before the ticket is labeled or handed off, and
  each **hard-stops on rc `2`**: the queue label is not applied and nothing is handed off, so
  `queue-labeled ⇒ scanned` stays a true invariant. (Operator resolution of OR-2.)
- **AC-8** — When the scan returns `10`, the exit records one Decision Ledger row per judged
  candidate in the receipt it already emits. A `0` scan records nothing — padding the register
  with a clean result is what `interviewing-baseline` forbids.
- **AC-9** — `dup-scan-selftest.sh` guards the above against a tracker stubbed on `PATH`,
  covering each exit-code arm, the claimed-half corpus, the union de-duplication, the
  self-exclusion, the config-driven label vocabulary, the jira arm's silence, report
  determinism, and both halves of the calibration.
- **AC-10** — Documentation is updated where this change makes it stale: the intake-toolkit
  plugin manifest's description, and `docs/testing.md`'s account of what the intake tools
  guard. No other doc describes this surface.

## Out of scope

- **The lane's preflight.** Both acceptance criteria name intake; `orchestrate-lean.sh`
  carries its own rc taxonomy and re-entry admission, and by the time the lane runs the
  operator has already committed a build session. The diff stays inside
  `plugins/intake-toolkit/` and its docs.
- **Auto-closing, auto-linking, or any tracker write.** AC-2, and the reason the tool has no
  write path to remove later.
- **Same-file collision detection** — see the known limit above.

## Decision Ledger

The binding input is the intake receipt at `.claude/pipeline-state/516-ledger.md` (D-1…D-10,
OR-1, OR-2). It is reproduced here only where it constrains the build; nothing below overrides
it.

| ID  | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | Tool location | `skills/plan-interview/tools/`, beside `ledger-lint.sh` — the existing cross-skill intake-tool directory, already reached from `intake-orchestrator` by that path. | codebase-derived |
| D-2 | Threshold and title weight | `THRESHOLD=12`, `TITLE_WEIGHT=3`, from the measurement above; both flag-overridable, per OR-1's reversible default. | codebase-derived |
| D-3 | Intake exit behavior on rc `2` | Hard-stop: no queue label, no hand-off, non-zero exit reporting rc and reason. | user-answered |
| D-4 | Corpus size cap | `--limit 100` per label query, with an explicit warning when a query returns exactly the limit — a silent cap reads as coverage. | codebase-derived |
