# 613 — An attended-session affordance with a per-decision recorded operator override

Part of #605. Slice one of the epic's ratified mechanism: **affordance plus record**. An ambient
attended signal unlocks only the affordance to _pause and ask_ instead of reject; any actual
yield additionally requires a per-decision recorded operator answer. The signal alone never
unlocks anything — a session that could assert its own attendance could turn off its own gates.

## Trust posture (stated up front — it is the design)

Nothing in-session is tamper-proof; the repo's trust boundary already says so, and this mechanism
does not pretend otherwise.

- The **affordance token** is tamper-evident only. Forging it buys a pause, never a yield.
- The **override record** is the yield's evidence, at the intent-gap ratification trust level:
  session-writable, committed, PR-visible, merge-boundary-validated, repudiable at review.
- The residual — a local gate whose code is edited to skip its own yield bookkeeping — is the
  standing local-gate posture, caught at review as a diff. It is stated in the design doc rather
  than papered over.

## Deliverables

### 1. `plugins/dev-pipeline/tools/operator-override.sh` (new) + `-selftest.sh`

One binary owns both halves. Its `gate:` enum is **closed to this slice's two consumers**, so
wiring a third gate is a code change here, not a config knob — that is what keeps the reader
private to the gate (AC-6) while still giving the two consumers one implementation rather than
two copies of a parser.

| Sub | Does |
| --- | --- |
| `attend` | mint this session's token (operator-run) |
| `state` | resolve `attended` / `headless` and print the reason |
| `record` | append an override block to the per-issue record; refuses unless attended |
| `check` | the yield predicate a consumer calls: does a matching, unexpired override exist |
| `lint` | well-formedness / expiry / identity binding over a record or the register |

**Attendance resolution**, first rule that fires wins:

1. `LEAN_ATTEND_MODE=headless` → `headless (marked-headless)`. Any **other** value is an
   environment error (rc 2): `attended` is deliberately not self-assertable.
2. no `CLAUDE_CODE_SESSION_ID` → `headless (no-session-identity)`.
3. no ambient `RUN_ID` → `headless (no-run-identity)`.
4. no token at `<mainRoot>/<pipelineStateDir>/attend-<session-id>.token` → `headless (no-token)`.
5. token unreadable, or missing either identity key → `headless (corrupt-token)`.
6. token's `session_id:` differs from the ambient one → `headless (session-mismatch)`.
7. token's `run_id:` differs from the ambient one → `headless (run-mismatch)`.
8. otherwise `attended`.

`attend` refuses without both identities, printing the `export RUN_ID=…` remedy — which is the
same export build-lean's step 2 already requires, not a new ceremony. Staleness is therefore
**structural**: the token binds to run identity, and there is no wall-clock TTL, which would
import the BSD/GNU `stat`/`date` and bash-3.2 portability hazards this repo has been bitten by. A
scheduler-spawned `claude -p` payload gets a fresh session id, so an operator's token can never
read attended inside one; rule 1 is the independent second belt.

**Record schema** — `<plansDir>/<slug>-<issue>-lean-override.md`, mirroring the intent-gap record.
One file per issue, N blocks (one per decision, because a single first-match header cannot name
two gates):

```
## Override <n>
gate: <intake-unqueued | spec-open-region>
scope: <intake-attestation | open-region-resolution>
issue: <n>
region: <OR-n, or `none` when the gate is not region-scoped>
run_id: <the run this override is bound to>
session_id: <the session that recorded it>
expiry: run
recorded_at: <ISO-8601>
decision: <the operator's stated decision, one line>

### Operator answer
> <verbatim quote of the operator's in-chat answer>
```

Keys are read first-match **within a block**. `expiry: run` is the default and means _not
persistent_. Authority is the closed `scope` enum — never an identity; actor identity comes from
the commit and PR trail.

**Central register** — `.claude/lean-overrides.tsv`, for the rare persistent class only. A
repo-wide append-per-run register is rejected as conflict-by-construction; this one is safe
precisely because persistent rows are rare. Hand-edited and reviewed as a diff, like
`scripts/fail-open-sites.tsv`. Columns: `gate`, `scope`, `region`, `expiry`, `justification`.
`expiry` grammar is the single form `until-issue:<N>` — a condition, not a clock, so no date
arithmetic is involved. A row whose issue is closed is **expired**; an expired row, a row with an
empty justification, an unknown enum value, or a non-`until-issue:` expiry refuses at read (rc 2)
and reds the next run at the first consumer that consults it.

### 2. Flagship consumer one — the scheduler's unintaken-ticket path

`plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh`:

- `spawn()` marks its payloads headless (`LEAN_ATTEND_MODE=headless` alongside the existing
  `env -u RUN_ID -u LEAN_RUN_MODEL` scrub), and the var joins both `SEAM_SCRUB` copies so a
  configured command lane never inherits it.
- `probe_intake` gains a **third accepting state** after the existing two: an `intake-unqueued`
  override that `check` resolves. No re-labelling — the tracker is untouched.
- The reject keeps its message text verbatim and adds one `attendance:` line. Attended, it
  additionally prints the exact `operator-override.sh record …` command and names in-session
  intake as the remedy.
- The reject becomes **distinguishable and resumable**: when the unintaken-ticket probe is the
  only failing one, the scheduler exits `3` as `preflight-rejected-resumable`. Every other
  preflight refusal stays exit 2.
- The scheduler binary stays non-interactive; the concurrent probes are untouched in shape.
- `check` rc 2 (unreadable or malformed) is a FAIL — fail-closed, as preflight already is.

`SKILL.md`'s exit-code table records the new code.

### 3. Flagship consumer two — the spec gate's pause-and-ask open region

`plugins/dev-pipeline/skills/build-lean/lean-gate.sh`, `region_resolved` and its refusal:

- A **third** resolution artifact joins the non-bot tracker comment and the ratified intent-gap
  record: a `spec-open-region` override whose `region:` names this id.
- Attended, the refusal prints the exact record-writing command; the gate itself never turns
  interactive — it runs under headless spawns as its normal case.
- Headless, the refusal text is unchanged, and the tracker-comment route still works under both.

### 4. Merge boundary

`lean-evidence.sh` gains an `override` arm (portable and tracker-agnostic, so it belongs to the
payload rather than to the github-only wrapper); `scripts/check-lean-chain.sh` delegates to it.
The arm validates **every present** override record — well-formedness, expiry, identity binding —
and refuses a malformed or expired one. Absence is class (a): most runs record no override.

### 5. Docs

`docs/pipeline-manifesto.md` states the mechanism's trust posture and the residual above.
`docs/testing.md` gains whatever the new suites need declared.

## Acceptance Criteria

- **AC-1** — An absent, corrupt, or run-mismatched (stale) affordance token reads as headless. A
  selftest case proves a forged token unlocks nothing but the pause affordance: the yield path
  still refuses without a record.
- **AC-2** — The override record binds to gate identity, run identity, the operator's stated
  decision, and its authority scope; a yield with no matching record is refused even when the
  affordance token is present. Per-run is the default; persistence requires expiry; expired or
  unjustified rows red the next run.
- **AC-3** — The unintaken-ticket path: the reject exits with a distinguishable resumable reason
  naming in-session intake as the attended remedy, and preflight re-accepts after intake with no
  re-labelling; headless, the reject decision and its message text are unchanged, plus a separate
  line reporting the resolved attendance state. Selftest covers both arms.
- **AC-4** — The pause-and-ask open-region path: the refusal prints the exact record-writing
  command; a record quoting the operator's stated answer satisfies the gate on re-run, where
  today only an out-of-band tracker comment does; the tracker-comment route still works. Headless
  unchanged. Selftest covers both arms.
- **AC-5** — Every recorded override is reconcilable after the fact: the record names the gate,
  the run, the decision, and the authority scope; in-gate, the yield path refuses to proceed
  before the record exists; the merge-boundary chain check validates every present override
  record and refuses a malformed or expired one. The local-gate residual is stated in the design
  doc.
- **AC-6** — No gate other than the two flagship consumers changes behavior in this slice. The
  record reader stays private to the gate: its `gate:` enum admits only the two consumers. New
  fail-closed branches are reconciled against `scripts/fail-open-sites.tsv` in the same PR.
- **AC-7** — A liveness scenario in `skills/build-lean/scenario-liveness-selftest.sh` covers the
  milestone-1 verdict path the open-region override touches, and `docs/pipeline-manifesto.md`
  carries the trust posture AC-5 requires.

## Decision Ledger

Rows D-1 to D-6 are carried from the pre-flight receipt at
`.claude/pipeline-state/613-ledger.md`. D-6 was `deferred` to OR-1 and is resolved here at build,
within the D-1/D-2/D-3/D-4 constraints; D-7 onward are this build's own.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Mechanism shape | Affordance plus record: the attended token unlocks only the pause-and-ask affordance; any actual yield additionally requires a per-decision recorded operator answer. The token alone never unlocks a yield, and a forged token buys nothing but the pause. | user-answered |
| D-2 | Record persistence | Per-run by default (bound to one RUN_ID); a persistent row is legal only with an explicit expiry condition; an expired or unjustified row reds the next run's entry. | user-answered |
| D-3 | Record trust posture | Session-writable, boundary-validated: the refusal prints the exact record-writing command; the session may run it only quoting the operator's stated in-chat answer; the record is committed, PR-visible, merge-boundary-validated and repudiable at review — the intent-gap ratification trust level. | user-answered |
| D-4 | Record location and semantics | Per-run overrides in a per-issue committed record file mirroring the intent-gap-record pattern; the rare persistent class in a small central expiry-gated register (a repo-wide append-per-run register is rejected as conflict-by-construction). Authority is a closed scope enum, never an identity — actor identity comes from the commit and PR trail. Token staleness is structural (run-identity binding), never wall-clock. | codebase-derived |
| D-5 | Consumer-one sizing | The scheduler binary stays non-interactive and its concurrent probes are untouched; the unintaken-ticket reject exits with a distinguishable resumable reason and preflight re-accepts after in-session intake with no re-labelling — the delta is the named resumable exit plus the recorded decision, not an interactive scheduler. | codebase-derived |
| D-6 | Override record schema detail | Resolved at build, closing OR-1: the per-issue record is a markdown file of `## Override n` blocks with per-block first-match header keys (gate, scope, issue, region, run_id, session_id, expiry, recorded_at, decision) plus a quoted operator answer; authority scope is the two-value enum intake-attestation and open-region-resolution; the register's expiry grammar is the single condition form naming a tracking issue. | user-delegated |
| D-7 | What the token binds to | Both identities, and both are required: the session id makes staleness structural across a spawned payload, the run id is what D-2's per-run scoping is stated against. `attend` refuses without either rather than degrading to a weaker binding. | codebase-derived |
| D-8 | Whether an env var may assert attendance | No — only the headless value is honored; any other value is an environment error. An honored positive value would be the self-asserted attendance the epic forbids. | codebase-derived |
| D-9 | One binary or a reader copied into each consumer | One binary invoked as a subprocess, with a closed gate enum. Two parser copies would be the dual-declaration smell this repo already names, and the closed enum is what keeps the reader private to the gate rather than a public seam. | codebase-derived |
| D-10 | Record file shape | One file per issue holding N blocks, not one file per decision. A single first-match header cannot bind two gates in one run, and a per-decision path scheme would need glob discovery at the boundary. | codebase-derived |
| D-11 | Where a pre-lane override record is written | Into the repo root of the caller, with a printed carry-forward line when that root is not the lane branch. Automating the carry would change the entry gate's behavior, which AC-6 forbids in this slice. | user-delegated |
| D-12 | Which side of the merge boundary validates the record | The portable evidence payload, since the record is tracker-agnostic; the github-only wrapper only delegates, as it already does for ratification. | codebase-derived |
| D-13 | Exit code for the resumable reject | A new code, applied only when the unintaken probe is the sole failure, so an operator and a wrapper can both distinguish resumable from terminal without parsing prose. | user-delegated |

## Out of scope

Wiring any further gates-process gate; the severity/impact axis and amendment governance; the
scheduler role-hint and mid-run round extension.
