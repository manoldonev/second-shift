# second-shift #500 — the lane can re-enter a run it stopped itself

`orchestrate-lean.sh` documents every non-zero exit as recoverable: "the worktree and the claim
are left in place — the state a manual rescue needs. Pick the blocks up by hand, **or re-run once
the reject is fixed**." The re-run half is unreachable. Checklist step 2 swaps the queue label for
the claimed one, and `probe_intake` demands the queue label — so the lane consumes, at step 2, the
one token its own front door requires. Every run it stops lands in a state it cannot re-enter, and
a stopped run is exactly when re-entry is wanted.

The only working re-entry today is `--intake-attested`, whose own documentation disclaims it
("never a way to skip a github label that is simply absent") — documented, unenforced, and
therefore uncitable in a run record even when the attestation it carries is true.

Pre-flight receipt: `.claude/pipeline-state/500-ledger.md` (binding input; D-1…D-9, OR-1 there).

## Design

### S1 — `probe_intake` gains a re-entry arm

Preflight's github arm becomes a three-way decision, evaluated in this order:

| State on the tracker | Verdict |
| --- | --- |
| queue label present | `ok intake` — a fresh queued ticket, unchanged wording |
| claimed label present **AND** a bot-authored `lean-claimed` marker on the issue | `ok intake: re-entry` — accepted, naming the marker's run id |
| anything else | `FAIL intake` — unchanged wording, unchanged hand-back |

**The conjunction is the whole guard (D-1).** The claimed label alone is a human moving a card;
the marker alone is a stale claim on a ticket whose label was hand-reset. Only both together are
evidence that *this lane* wrote the state preflight is now reading back, which is what keeps AC-4
true: a ticket that was never intaken presents neither.

**Tracker-only, deliberately.** `orchestrate-lean.sh:13` says the scheduler may know "gate exit
codes and tracker state. Nothing else", and the `<issue>-run-id` cache is local state — reading it
would make preflight's answer depend on which machine is asking. It also reads exactly the artifact
`check-lean-chain.sh` evidence 3 already treats as authoritative, so re-entry and the merge boundary
agree on what a claim is.

**The read.** `gh api repos/{owner}/{repo}/issues/<n>/comments`, filtered
`.user.type == "Bot"` plus the `<!-- stage: lean-claimed -->` tag — the same trust filter the merge
boundary applies, for the same reason (issue comments are writable by any account on a public repo,
so an outsider could post a marker). D-7 left the call open pending measurement; measured here:

```
$ gh issue view 500 --json comments --jq '.comments[0].author'
{"login":"<bot-app>"}                                 # no .user.type, and the login is unsuffixed
$ gh api repos/{owner}/{repo}/issues/500/comments --jq '.[0].user | {login, type}'
{"login":"<bot-app>[bot]","type":"Bot"}               # carries it
```

So the arm uses `gh api`. The read is unwindowed — preflight has no PR to window at — and takes
`first`, matching what the merge boundary will hold this run's verdict against (D-6).

**A failed read rejects (D-8).** `probe_intake` already treats an unreadable label response as
`FAIL`; the comment read joins that same arm rather than falling back to local state on an outage.
Distinguishing "the read failed" from "no marker" matters: the second is a legitimate reject with
its own message, the first is an environment error the operator must fix before the answer means
anything.

**The accept is loud (D-9).** The line names re-entry and the run id the marker carries, rather
than reusing the queue-label `ok intake` wording — the scheduler's log is the operator's only
evidence for why preflight did not reject, and (per OR-1) the printed run id is what makes a
second lane on the same ticket visible rather than silent.

`CLAIMED_LABEL` is resolved from `.tracker.labels.claimed` with the same `in-progress` default
`lean-gate.sh:294` carries.

### S2 — `--intake-attested` is tightened to match its own documentation

Under `tracker.type: github` the flag becomes a usage refusal at exit 2, naming the reason and
pointing at the re-entry path. Under jira it is unchanged and still required. The flag's existing
doc sentence stands as written — it was always the contract; only the enforcement was missing.

It lands as an `envfail` immediately after `TRACKER_TYPE` resolves, not as a probe: this is knob
misuse, and the file's posture for knob misuse is already an `envfail` (`:166` review-model basis,
`:208` tracker.type). A probe would report it alongside the other two verdicts, which is the right
shape for "your tracker is in the wrong state" and the wrong shape for "you passed a flag that
does not apply here".

**AC-1 is what makes this viable rather than merely stricter (D-2).** The flag was being abused
because it was the only re-entry path; S1 supplies a real one, so closing the abuse costs nothing.

### S3 — the payload block stops asking for the label back

Two prose edits in `build-lean/SKILL.md`, both required for S1 to deliver anything end to end:

- **Step 1's queue-label confirm (D-3)** accepts the same two states preflight does. Without it the
  re-entry preflight now admits is rejected by the very block preflight spawns.
- **Step 2's claim (D-4)** is skipped when the run is already claimed, so re-entry makes zero
  tracker writes. `lean-gate.sh cmd_claim` and `claim-issue.sh` are untouched — the issue's
  out-of-scope line puts the claim mechanism itself off the table, and D-6 establishes that a
  duplicate marker would be harmless at the merge boundary anyway. This stops paying for the write;
  it is not repairing a break.

### S4 — the marker tag's third copy

`LEAN_CLAIM_MARKER_TAG` is lockstep-anchored between `lean-gate.sh` (writer) and its two
merge-boundary readers. This adds a fourth site, and deliberately **not** a lockstep row —
following the `lean-reconcile.sh` precedent already recorded in `scripts/lockstep-manifest.tsv`:
this is an operator-facing scheduler, not a merge-boundary gate, and a drifted tag here fails
**closed** (re-entry stops being recognized, loudly, on the next stopped run) rather than
silently weakening a boundary. The manifest comment is extended to name this second non-row and
say why, so the decision is visible rather than forgotten.

### What is out of scope

Per the issue: #492's in-process continuation loop (a different failure, neither subsuming the
other), whether an aborted run should release its claim, and the claim mechanism itself. Nothing
below touches `lean-gate.sh` or `claim-issue.sh`.

## Acceptance criteria

- **AC-1** — under `tracker.type: github`, preflight accepts a ticket carrying the claimed label
  **and** a bot-authored `lean-claimed` marker comment as a legal re-entry, and spawns the run.
  The evidence is read from the tracker only; the `<issue>-run-id` cache is not consulted.
- **AC-2** — re-entry requires no tracker write. Preflight's probe set stays read-only across a
  re-entered run, and `build-lean` step 2 skips the claim when the run is already claimed, so no
  label is re-swapped and the operator is never asked to restore one the lane consumed.
- **AC-3** — under github, `--intake-attested` is a usage refusal at exit 2 naming the reason and
  pointing at the re-entry path, with nothing spawned. Under jira it is unchanged and still
  carries the run. The flag's "never a way to skip a github label that is simply absent" sentence
  stands as written.
- **AC-4** — a ticket carrying neither the queue label nor claim evidence still rejects at exit 2
  with the existing hand-back message, and spawns nothing.
- **AC-5** — the claimed label *alone* rejects, and a `lean-claimed` marker that is not
  bot-authored is not claim evidence.
- **AC-6** — a failed comment read during the re-entry check rejects, naming the read that failed.
  Preflight never falls back to local state on a tracker outage.
- **AC-7** — the accepting line names re-entry and the run id the claim marker carries, in wording
  distinct from the queue-label accept.
- **AC-8** — `build-lean/SKILL.md` step 1's "confirm the queue label; a missing one is a reject"
  accepts the same two states preflight does, and step 2 carries the skip-when-already-claimed
  conditional. Both within the skill's 60-line cap.
- **AC-9** — doc AC. `run-lean/SKILL.md`'s exit-2 remedy and its "When it stops" paragraph no
  longer instruct the operator to re-label a ticket the lane itself claimed, and
  `orchestrate-lean.sh`'s `--help` header documents the re-entry arm and the tightened flag. The
  front door stays within its 60-line cap and `--help` still prints exactly the header.
- **AC-10** — `orchestrate-lean-selftest.sh` covers, at minimum: a fresh queued ticket accepted;
  a claimed-plus-marker ticket accepted as re-entry with the run id named; a ticket with neither
  rejected (the existing `(g1)` case, passing unchanged); the claimed label alone rejected; a
  non-bot marker rejected; a failed comment read rejected; `--intake-attested` under github
  refused at exit 2 with nothing spawned; `--intake-attested` under jira still carrying its run
  (the existing `(m2)` case, passing unchanged); and a re-entered run making zero tracker writes.
- **AC-11** — the `gh` fake in `orchestrate-lean-selftest.sh` gains the comment-trail arm, and the
  suite's existing anti-vacuity posture is preserved: the new absence-based cases are scored
  against a fixture proven to record, and the re-entry accept is scored on the *arm* (the run id
  in the log) rather than only on the exit code, which an unchanged tool could also produce by
  accepting for the wrong reason.
