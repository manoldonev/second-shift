# second-shift #446 — the PR marker's session id must come from a recorded build session

## Problem

`lean-gate.sh mark` writes two identities into the PR marker. `run_id` comes from the
role-keyed build cache and cannot silently inherit a review identity; `session_id` is read
straight from the ambient environment:

```bash
echo "<!-- run_id: $RESOLVED_RUN_ID -->"                       # role-keyed cache
echo "<!-- session_id: ${CLAUDE_CODE_SESSION_ID:-unset} -->"   # whoever happens to be running
```

`session_id` is the *stronger* of the two comparisons `lean-evidence.sh`'s `arm_identity`
makes — `run_id` is agent-chosen, the session id is harness-assigned. So the one field that
cannot be talked around is the one taken from ambient state.

The failure mode is reached by following the documented recovery. A stranded marker only
becomes visible after the review's verdict-record push, so the operator runs `mark` by hand
from the **review** session; the marker then records the review session as the build session,
and `arm_identity`'s marker-session compare reports a correct, independent review as a P10
self-review. Recovery is worse than the fault: `mark` is idempotent on `run_id` alone, and the identity arm
compares against *every* marker, so neither re-running `mark` nor posting a second correct
marker clears it. The only remedy is deleting bot-authored evidence and hand-supplying an
identity string — the posture the P10 arms exist to remove.

## Approach

**The issue's first suggested direction is rejected (ledger D-2).** Resolving `session_id`
from the progress-file header would re-open a deliberately closed hole: the header is
seed-once and single-valued, so a second build session on the same PR — the case
`cmd_mark`'s D-4 idempotence exists for — would carry session 1's id on its marker and nothing
would catch it at session level.

Instead the build identity becomes a **set** (D-1). The progress file records every session
that legitimately built on this issue; `mark` keeps writing the **ambient** session id — the
correct value on every honest path, including a second build session — but **refuses** when
the ambient session is not in that set. A review session is therefore refused unconditionally,
with no committed verdict record needed and no evidence corrupted. A refusal is recoverable; a
mis-stamped marker is not.

Only the subcommands that may *establish* the build run id may *record* a session (D-3): the
`entry|claim` arm of the RUN_ID-persistence dispatch, for the reason already stated there —
"an EVALUATION must be able to read an identity, never to establish one". `mark` is a pure reader (D-4), so
the guard cannot whitelist itself; a review session running `bash G 4 <issue>` records nothing
(D-5), so it cannot whitelist itself either.

The set is the header's `session_id:` **union** the appended session rows (D-6). The header is
already the build identity by `cmd_verdict`'s own compare, so including it is the correct
definition rather than a compatibility shim — and it means a run in flight when this lands, whose
progress file has no session rows yet, is not stranded at `mark`.

Out of scope (parked as Open Regions in the pre-flight receipt): correcting markers already
mis-stamped on in-flight PRs (OR-1), write-time refusal of a second build session authoring
its own verdict (OR-2), and widening the idempotence guard to `(run_id, session_id)` (D-10 —
dropped: `arm_identity` compares every marker, so a corrective second marker buys a
duplicate comment and no recovery).

## Acceptance criteria

**AC-1** — The progress file carries a **build-session set**: the header's `session_id:` value
union every appended `<iso> | session | <id>` row. Values that are empty or the literal
`unset` are not members.

**AC-2** — `entry` records the ambient session into that set when it is not already a member.
The test is the session's **own** presence, independent of the per-run entry-attestation row
(`| entry | ledger=`), which short-circuits on `entry_row_present` — so a second build
session running the idempotent `entry` records its session even though it appends no second
attestation row (D-7).

**AC-3** — `claim` records the ambient session on the same own-presence test, under both
tracker adapters.

**AC-4** — No other subcommand records a session. Specifically `mark`, `1..5`, `all`, `delta`
and `verdict` append no session row (D-3, D-4, D-5). A review session running `bash G 4
<issue>` therefore leaves the set unchanged.

**AC-5** — `mark` refuses with a non-zero exit and posts **no** marker when the ambient session
is not a member of the build-session set. The refusal is evaluated before any PR lookup or
comment fetch, so it costs no network call and needs no committed verdict record.

**AC-6** — The refusal message names (a) the ambient session id in conflict, (b) every build
session id the harness itself recorded, and (c) the exact re-invocation
`CLAUDE_CODE_SESSION_ID=<id> bash G mark <issue>` (D-8). Printing the recorded id rather than
silently using it is the point: a genuine second build session keeps its own ambient id on its
own marker, while "hand-supply an identity string" becomes "copy the harness's own recorded
value".

**AC-7** — Fail closed (D-9). When no usable build session exists — no progress file, or a
header of `unset` with no session rows — `mark` refuses rather than writing a marker with
`session_id: unset`. An unset ambient session and an `unset` recorded id must **not** compare
equal and pass; the vacuity is guarded explicitly.

**AC-8** — When the check passes, `mark`'s marker body is unchanged: it still writes the
**ambient** `session_id`, so a second build session stamps its own identity and stays visible
at the merge boundary (D-4's case is preserved).

**AC-9** — The appended row is `<iso> | session | <id>` and does not contain the literal
`session_id:`, so it never enters the first-match race the header wins today (D-13). After any
number of session rows, `lean-gate.sh`'s `record_key session_id` and `lean-reconcile.sh`'s
`extract_key session_id` both still return the **header** value.

**AC-10** — Backward compatible for in-flight runs (D-6): a progress file whose header carries
a build session id and which has **no** session rows still marks successfully from that
session.

**AC-11** — Tested in `plugins/dev-pipeline/skills/run-lean/lean-gate-selftest.sh` with cases
covering AC-2 through AC-10, each setting `CLAUDE_CODE_SESSION_ID` explicitly (the sweep runs
with it unset), plus a row in `tools/mutation-catalog.tsv` anchoring the guard (D-14). No
`scenario-liveness-selftest.sh` scenario: D-12 keeps this off every verdict path, so the
"a new gate contract extends the liveness scenario" rule is not triggered.

**AC-12** — The pinned progress-file line-shape block in `lean-gate.sh`'s progress-file
primitives documents the session row alongside the existing three shapes, since that comment
is the schema two other readers are held to. No recovery section is added to `run-lean/SKILL.md` (D-15): the refusal
message is the documentation, and the file is capped at 60 lines by
`lean-gate-selftest.sh` case (f).

## Deviations

**Milestone 3 red twice before a green, neither red caused by this change.** Attempt 1 ran the
sweep the config carried at the time and returned `rc=1`; every suite the tree owns was then
re-run individually and all were green (`lean-gate`, `lean-reconcile`, `lean-evidence`,
`branch-prefix`, `e2e-replay`, `mutation-sweep`, `scenario-liveness` 82/82, and
`install-topology` 58 ran / 0 red), which points at contention — three other sessions were
running the same suites on this machine. Attempt 2 returned `rc=127`: the shared, gitignored
consumer config had been repointed mid-run at `tools/run-selftests.sh`, which existed only on
an unmerged branch. Both were resolved by merging `origin/main`, which had since landed that
runner and moved the `install-topology` guard to a nightly workflow.
