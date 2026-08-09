# Gate arms declare when their contract took effect — issue #444

## Problem

An arm merged after a PR opened is enforced against that PR. The build session that opened it
had already finished and could not have satisfied a contract that did not yet exist. The
remedy is a per-arm cutoff: an arm declares the instant its contract took effect, and a run
whose observation point precedes that instant is outside the arm's window rather than in
violation of it.

The cutoff is an explicit `since:` literal, never derived from commit history — a derived date
advances whenever the arm's lines are reformatted or rebased, which fails **open**.

## Scope

Three surfaces, three different cutoff sources and three different strictness postures:

| Surface | Cutoff source | Absent-input posture |
| --- | --- | --- |
| `lean-evidence.sh` PR-marker identity arm | `PR_CREATED_AT` | report `postdated`, never `envfail` |
| `scripts/check-lean-chain.sh` | `PR_CREATED_AT` | unchanged — its existing hard requirement stays |
| `lean-gate.sh` `require_entry_attested` | branch first-commit **author** date at merge-base | fail closed (D-5) |

`check-lean-chain.sh` is **not edited** (D-1): its only own arm is the issue-side claim
identity, which carries no cutoff, and the PR-marker arm it enforces is delegated to the
payload.

Author date, not committer date, in the gate: a rebase rewrites committer dates, so an old
branch rebased today would postdate its cutoff and start refusing — recreating the exact
stranding this work removes.

All date conversion goes through git (`TZ=UTC git log --date=format-local:...`), then plain
string compare on the Z-normalized forms (D-8). No `date` invocation is on the comparison
path, so the BSD/GNU `date -d` / `date -r` split never arises and bash 3.2 needs no special
case.

## Acceptance Criteria

- **AC-1** — WHEN the run's cutoff precedes an arm's `since:` THEN the arm reports the
  `postdated` disposition via the class-(b) path and contributes zero violations.
- **AC-2** — WHEN the run's cutoff is at or after the arm's `since:` THEN the arm enforces
  exactly as before.
- **AC-3** — WHEN `PR_CREATED_AT` is absent THEN every `since:`-bearing arm in
  `lean-evidence.sh` reports `postdated` and the payload does not exit with an environment
  error. `check-lean-chain.sh` keeps its existing hard requirement.
- **AC-4** — `lean-evidence.sh` accepts `PR_CREATED_AT`, and
  `plugins/second-shift/templates/consumer/second-shift-ci.yml` supplies it.
- **AC-5** — The PR-marker identity arm carries `since: 2026-08-08T17:05:14Z`; the
  entry-attestation precondition carries `since: 2026-08-07T13:22:51Z`. The issue-side claim
  identity arm carries no `since:`.
- **AC-6** — WHEN a branch's first-commit author date precedes the entry precondition's
  `since:` THEN `require_entry_attested` does not refuse and writes no entry row.
- **AC-7** — WHEN that date is at or after the `since:` THEN the refusal fires unchanged,
  including its existing second-cause wording.
- **AC-8** — Timestamp comparison is correct under bash 3.2 and across a non-UTC committer
  offset, proven by a case driving each.
- **AC-9** — `scenario-liveness-selftest.sh` covers both new verdict paths: the entry
  precondition's de-block, and the payload identity arm's `postdated` exemption surviving
  delegation through the merge boundary. `check-lean-chain-selftest.sh` additionally composes
  the one property no other suite can see — that the payload's cutoff-bearing arm and the
  issue-side claim arm, which carries none, have different windows over the same verdict.
- **AC-10** — The two forced comparator copies are recorded as a **DROPPED** entry in
  `scripts/lockstep-manifest.tsv` with the reasoning for why no relation in that file fits.
- **AC-11** — Mutation obligations land in this diff: re-keyed generic survivor ordinals for
  the two edited guards are re-baselined in `tools/mutation-baseline.tsv`, and any
  `tools/mutation-catalog.tsv` row addressing them is re-anchored.

## Decisions carried from the pre-flight ledger

The pre-flight receipt at `.claude/pipeline-state/444-ledger.md` is binding input; D-1..D-14
and OR-1/OR-2 are adopted as written. The load-bearing ones for a reader of the diff:

- **D-3** — a `since:` is a plain per-arm shell constant beside the arm it governs, with the
  ISO literal in its value and a comment naming the merge it anchors to.
- **D-4** — in `arm_identity`, the cutoff test runs **before** the `BOT_ENABLED` test, so a
  run that is both pre-cutoff and bot-less reports `postdated`, not `reduced-strength`.
- **D-5** — an unresolvable merge-base in `require_entry_attested` is its own `envfail`, not a
  fifth cause on the existing refusal.
- **D-6** — the AC-6 de-block announces itself with one plain `[lean-gate] note:` stderr line,
  not with a third copy of the disposition vocabulary.
- **D-10** — the disposition vocabulary does not change; `postdated` is already a member.
- **D-14** — AC-5's `+1s` offset on the PR-marker literal is deliberate and must not be
  normalized to its merge's second.

**OR-1** — a `PR_CREATED_AT` that does not normalize is treated as absent: report `postdated`
and additionally name the unparseable value on stderr.

**OR-2** — an empty commit range means the branch was cut now, which is at or after any
cutoff, so enforce. Confirmed during build: `claim` legitimately runs before the first commit
on every run, from the main checkout, and the fail-closed direction is still correct there —
`entry` is always available to run, so nothing is stranded.
