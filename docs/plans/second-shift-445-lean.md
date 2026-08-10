# An arm cannot enforce a contract its producer does not ship — #445

The merge boundary enforces arms that travel by **git ref**; the producer that satisfies them
travels by **versioned plugin install**. The two transports skew, both trees report the same
version, and no version-keyed check can observe it. So the producer stamps a **generation
token** into an artifact it already writes, and an arm enforces only when that stamp shows a
producer generation capable of the artifact the arm demands.

Built on #444's landed `since:` mechanism. Pre-flight receipt: `.claude/pipeline-state/445-ledger.md`
(binding).

## The mechanism

**The stamp rides the claim comment.** `lean-gate.sh cmd_claim` posts a bot-authored
`lean-claimed` comment on the issue on every github run, under *both* producer generations —
that is what makes reading a stamp off it non-circular. Reading it off the PR marker would be
circular (the marker is exactly the artifact the bound arm demands); reading it off the verdict
record would let the reviewed party soften a build-side arm (receipt D-2).

**One arm is bound: `arm_identity` → the `pr-marker` capability** (receipt D-4). The other arms
are unbound with the reason recorded in-file: `require_entry_attested` is same-generation by
construction, the claim `session_id` arm already degrades via `reduced-strength`, the `fidelity:`
reader is already anchored for records predating the key, and `arm_intent_gap`'s absence is
class (a).

**Ordering: `since:` first** (receipt D-6). A postdated run reports `postdated` and never reads a
stamp, so no issue fetch is paid on an exempt run — and exactly one class-(b) line is emitted per
arm.

**Union across claim comments** (receipt D-5): the arm enforces if *any* bot-authored claim
comment declares its capability. Intersection would let one stale pre-token claim comment
permanently disarm the arm for the whole issue.

**A closed vocabulary, mirrored in lockstep.** One `LOCKSTEP-BEGIN lean-producer-capabilities`
block carries the claim marker tag, the stamp key and the closed capability vocabulary. The
producer validates the subset it ships against that vocabulary; the reader validates the token
its arm requires against it. A one-sided rename therefore reds loudly on the side that renamed,
rather than silently emptying a set — the same posture `LEAN_OUTPUT_DISPOSITIONS` already takes.

## Acceptance criteria

- **AC-1** — WHEN a run's evidence carries no producer stamp THEN every arm bound to a capability
  reports `inert` via the class-(b) path and contributes zero violations.
- **AC-2** — WHEN the stamp shows a generation that declares the arm's capability THEN the arm
  enforces exactly as before.
- **AC-3** — WHEN the stamp shows a generation that does not declare the arm's capability THEN the
  arm reports `inert`, not a violation.
- **AC-4** — The producer stamps its generation token into both the claim comment and the verdict
  record, and a lockstep row binds the token's spelling across writer and reader.
- **AC-5** — A fixture pins the pre-token generation, so the inert path keeps a kill criterion
  after the next release makes stamped runs the norm.
- **AC-6** — A contributor-doc paragraph in `docs/testing.md` states the obligation: a new arm
  ships with its producer's capability stamp, its not-applicable path, and its silence-on-green.
  **Explicitly non-scored** — repo convention forbids prose-presence guards, and the enforcement
  lives in the mechanism above.
- **AC-7** — Under `tracker.type: jira` the identity arm is **not** capability-bound and enforces
  exactly as it does today. A jira run posts no claim comment at all, so no artifact both producer
  generations write exists there to carry a stamp; binding the arm to a stamp that can never be
  produced would disarm the strongest merge-boundary arm permanently for that adapter, which is a
  strictly larger harm than the transitional skew this ticket closes. The reason is recorded
  in-file, and this is the ticket's stated scope boundary rather than a defect of the mechanism.
- **AC-8** — WHEN the claim trail cannot be read at all (no fixture seam, no resolvable repo, or a
  failed fetch) THEN the bound arm reports `inert` rather than exiting on an environment error.
  A newly-required input or permission that reds every consumer whose committed workflow predates
  it is the same strand-an-innocent-PR defect the mechanism exists to close.
- **AC-9** — Every pre-existing case in the affected suites that asserts the identity arm
  **enforcing** still exercises the enforcing path: each supplies a stamped claim trail. A case
  that silently became an `inert` decline reads exactly as green as before and proves nothing.

## Deviations from the pre-flight receipt

- **D-3, two lockstep rows.** Shipped as stated (`lean-gate.sh` ↔ `lean-evidence.sh`, and
  `lean-gate.sh` ↔ `scripts/check-lean-chain.sh`), and earned rather than nominal: the shared
  block also hoists the `lean-claimed` marker tag, which `check-lean-chain.sh` genuinely reads.
  `lean-reconcile.sh` keeps its own unbound copy of that literal — it is an operator-run
  reconciler rather than a merge-boundary gate, and it carried an unbound copy before this
  ticket; binding it is out of scope.
- **AC-7 above** is new, and covers a surface the receipt's D-2 and D-4 did not reach.

## Open regions carried from the receipt

- **OR-1** — no sunset for the inert path; permanent until a human decides otherwise.
- **OR-2** — no pre-emptive mutation-exclusion row for the write-only verdict-record stamp. If the
  diff-scoped sweep produces a survivor on it, a row citing receipt D-7 is added rather than a
  silent baseline entry.
- **OR-3** — composes on top of #444's landed per-arm `since:` literals, ordered per D-6.
