# lean-reconcile.sh exits 2 before any check on a jira consumer

Spec of record for issue #388. The definition of done is the `AC-n` set below.

## Problem

`lean-reconcile.sh` hard-exits `2` on any `tracker.type: jira` consumer before a single
reconciliation check runs. Line 197 fetches the GitHub comment trail unconditionally; under
jira `$ISSUE` is a ticket key, the endpoint 404s, and the `|| { … exit 2; }` kills the script.

Fixing the endpoint would not help. #362 deliberately made jira `claim` write nothing
(`lean-gate.sh:676-680`), so a bot-authored `lean-claimed` comment **never exists** there.
Check (1)'s claim arm is unsatisfiable by construction.

`grep -n 'GH_CLI\|gh api\|COMMENTS'` returns hits at exactly one functional site — `:197`.
Every other check reads only git, the progress file, the verdict record and the audit ledger:

| Check | Reads | Works under jira? |
|---|---|---|
| (1) claim comment ↔ progress `run_id` agree | comment trail | **no** — no claim comment exists |
| (1b) verdict `run_id` ≠ build `run_id` (P10) | verdict record + progress file | yes |
| (2) review session distinct, has a live ledger | verdict record + audit dir | yes |
| (3) review ledger's first row precedes the verdict commit | ledger + git | yes |
| (4/5) `reviewed_patch_id` / `reviewed_head` coherence | verdict record + git | yes |
| (6) inheritance chain links resolve, each round a different session | git history of the record | yes |

So a jira consumer loses one arm to a structural absence and **five to an early `exit 2`** —
including the P10 authorship check, which is what the generation-must-not-author-evaluation
separation rests on and which needs no tracker at all.

#362's scope section asserted that jira `claim` persisting the run-id to the progress file
means "`lean-reconcile.sh` keeps its anchor". The anchor is persisted and check (1b) would read
it happily; the script never reaches it. #362 scoped its branch sites to `lean-gate.sh`'s three
milestones, and the reconciler is not a milestone, so the assumption was never exercised.

## Binding pre-flight input

`.claude/pipeline-state/388-ledger.md` is the intake receipt for this run and is binding. Its
nine decisions are transcribed below where they bear on the design. Four of them close choices
the issue left open (D-1 through D-4); three record repo constraints the issue does not mention
and which **extend its AC set** (D-5, D-6, D-7) — see AC-8, AC-9, AC-10 and the reading of AC-5.

Its declared open region on the exit code is **closed at intake by D-2**: exit 0, disclose in
the output. Two regions stay open — OR-1 (the disclosure's eventual shape under #353) and OR-2
(whether the re-keyed mutation ordinals are right, which only the nightly can confirm). Both are
`reversible-default-and-flag`; both defaults are applied below.

## Files in scope

`plugins/dev-pipeline/skills/run-lean/lean-reconcile.sh`, its selftest,
`plugins/dev-pipeline/skills/run-lean/SKILL.md`,
`plugins/dev-pipeline/skills/run/tools/tracker/README.md`, `tools/mutation-baseline.tsv`, and
this spec.

**Deliberately NOT `lean-gate.sh`** — it already resolves the adapter and needs no change, and
leaving it alone lets this run concurrently with in-flight lean PRs that edit it.
**Deliberately NOT `scripts/check-lean-chain.sh`** — the merge boundary stays dogfood-scoped per
#362; consumer-side enforcement is #359's. No new config key: `tracker.type` already exists, so
no `configVersion` migration.

## Acceptance criteria

- **AC-1** (oracle — selftest): under a jira fixture config with **no** `--comments-file` and no
  network, the script exits 0 on a complete evidence set, makes zero `gh` calls, and its output
  names the skipped claim-comment arm.
- **AC-2** (oracle — selftest): under the same jira fixture, each of (1b), (2), (3), (4/5), (6)
  still **fails** when its own evidence is broken — a build-identity verdict, a missing review
  ledger, a timestamp inversion, a mismatched `reviewed_patch_id`, and an unresolvable
  inheritance link. Proves the checks run rather than being skipped alongside the fetch.
- **AC-3** (oracle — selftest): the github arm is behaviorally unchanged — every existing
  `lean-reconcile-selftest.sh` case still passes, `--comments-file` included.
- **AC-4** (oracle — selftest): with `tracker.type` absent the script behaves exactly as github
  — the default is asserted, not assumed.
- **AC-5** (critic): `run-lean/SKILL.md`'s "both github-only … no backstop yet" is corrected to
  state what jira does and does not get, **net-zero or net-negative on that file's line count**
  (D-6); `tools/tracker/README.md` gains a **reconcile** row in the lean-lane table and has its
  now-falsified "No reconciliation backstop under jira yet" blockquote rewritten, not
  supplemented (D-7).
- **AC-6** (oracle — CI): frozen-files and changelog-trailer gates green; `Changelog:` trailer
  present.
- **AC-7** (critic): no consumer-identity or operator-identity tokens in code, fixtures or docs.
- **AC-8** (oracle — selftest): an **unrecognized** `tracker.type` is a loud environment error
  (rc=2) naming the offending value, mirroring `lean-gate.sh:224-227` (D-3).
- **AC-9** (oracle — selftest): `--comments-file` passed together with `tracker.type: jira` is a
  loud environment error (rc=2) rather than a silently ignored fixture (D-4).
- **AC-10** (oracle — sweep): the five `tools/mutation-baseline.tsv` rows keyed to this guard are
  re-keyed in this diff against the edited script, with the re-baseline reason recorded in each
  row (D-5). No `tools/mutation-catalog.tsv` or `tools/mutation-exclusions.tsv` row addresses
  this guard, so nothing re-anchors there.

## Design

### One resolution, one branch site

`lean-reconcile.sh` already has the `cfg` helper it needs (`:95-102`, used for `plansDir`,
`pipelineStateDir`, the host slug and `baseBranch`). It gains one resolution beside those:

```bash
TRACKER_TYPE="$(cfg '.tracker.type' 'github')"
case "$TRACKER_TYPE" in
  github|jira) : ;;
  *) envfail "unknown tracker.type '$TRACKER_TYPE' — expected 'github' or 'jira'." ;;
esac
```

and branches at exactly one site: check (1)'s comment fetch. **D-3** puts the enum here rather
than a bare default: `config-lint.sh:44,49` already constrains the key to that domain and
`lean-gate.sh:224-227` already rejects anything outside it, so two readers of one config key
agree about what it can be. Absent ⇒ `github` is retained as the fail-safe for a config that
never reached the lint (AC-4 asserts it rather than assuming it).

**D-1 — under jira the arm is skipped, not replaced.** No compensating build-side assertion is
added. The candidates are all self-attestation: the `claim | tracker=jira | no tracker write`
line `lean-gate.sh:678` appends is written by the same run whose honesty is in question, and
this script's own header (`:9-12`) rules self-reconciliation out as evidence. Check (1b) already
reads that file's `run_id`, so a claim-line grep would be a second read of one record, not a
second record. Everything the fetch feeds — the array shape check at `:203`, the bot-filter `jq`
at `:208-212`, and the `RUN_CLAIM` comparison at `:218-224` — is inside the branch. (1b) at
`:226-230` is outside it and runs on both arms unchanged.

**D-4 — `--comments-file` under jira is `envfail` rc=2**, not an ignored flag. A jira case that
passes a fixture and still goes green asserts nothing about that fixture while reading as
coverage, and nothing would red if a later edit re-enabled the fetch. The selftest gains a
second invoker without the flag, which AC-1's wording requires anyway.

### Disclosure (D-2, OR-1)

Exit 0 on a complete evidence set. An operator scripting on the exit code reads any non-zero as
"failed", so evidence *strength* is disclosed in prose, in two places:

- at the check-(1) site, a note naming the arm that did not run and why it cannot run here;
- on the final `reconciled:` line, a qualifier — so an operator who reads only the last line
  cannot mistake a jira reconcile for the github-strength attestation.

The failure line (`:401`) is left alone: a red reconcile's evidence strength is moot.

**OR-1's reversible default is applied as stated.** The format is local prose, not a
machine-readable envelope: #353 is still generalizing the gate-strength disclosure contract, and
pinning a shape before it settles would create a second authority. Reversing this is an edit to
two `say` strings in one file, and nothing parses either today.

### Header, help and the ordinals

The usage/seams block gains the jira behavior, which moves `--help`'s hand-maintained
`sed -n '2,67p'` (`:82`). **D-8**: no hand-lockstep hazard — selftest case (O) is
content-anchored (`Exit 0 = reconciled` present, `^set -uo pipefail` absent), so a stale range
reds from either direction.

**D-5 / OR-2 — the ordinals re-key.** `tools/mutation-baseline.tsv:51-55` carry five *generic*
survivor rows for this guard (`cmp-eq::1`, `default::1`, `default::2`, `detector::1`,
`fail-open::2`); ordinals are positional, so adding a `case` and a branch shifts them. They are
re-baselined in this diff. OR-2's reversible default is applied: re-key from a local advisory
sweep and carry the existing rows' own hedge — the sweep sandboxes HEAD, CI is the authority,
and a stale baseline row warns rather than reds, so being wrong costs a warning and a follow-up
commit.

### Docs (AC-5; D-6, D-7)

`run-lean/SKILL.md` is **exactly 60 lines**, its cap, asserted by `lean-gate-selftest.sh:216`.
The correction rewrites the existing integrity paragraph in place; it cannot append.

`tools/tracker/README.md` needs both halves: the lean-lane table (`:47-51`) gains a **reconcile**
row, and the blockquote at `:56-62` — which asserts "Both are github-only today … no machine
check ties them together" — is rewritten. Adding a row while leaving that assertion three lines
below it would ship a self-contradicting page.

## Out of scope

`scripts/check-lean-chain.sh`. Its claim-comment dependency is real and the same shape, but the
merge boundary is dogfood-scoped per #362 and its consumer-side counterpart is #359's; adapting
it here would widen a one-site fix into the second reader's contract. A jira consumer's merge
boundary therefore remains unadapted after this change, and the docs say so.
