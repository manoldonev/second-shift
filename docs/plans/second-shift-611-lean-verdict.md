# lean review verdict — #611

verdict=approve
run_id: review-611-1
session_id: e1d1ce00-dba2-4409-8c26-17b0a9c78d8e
rounds: 1
pr: #616
reviewed_head: 414a5a5a594b70b002ab9d962b78a99c6b4180ba
reviewed_patch_id: addc0b5883390a1345bf59e6901db15f6d81ea2b
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1 covered the whole branch diff (`f51f7d87..HEAD`, 7 files, +814/-14) — a root round with
nothing to inherit. Panel: security, performance, complexity, maintainability, test-coverage,
scope-completeness. All six returned; none went dark. No blockers.

The enforcement is well-placed and the reasoning in the file is unusually load-bearing: the cheap
arms run before the `$ISSUE`-derived name table (so a refusal cannot first create
`<typo>-run-id`), the tracker read runs once at the run boundary and after the attestation check,
the shape arm beats the tracker arm, and the run-id seed was correctly split off the resolve so a
refused boundary call leaves no identity behind. Library mode returns at 5620, before the dispatch
guard — no lib-mode socket. `--help`'s `sed -n '2,329p'` bound was verified against the real
header (328 lines, ending at the bash-3.2 note).

## Findings

| # | Sev | Where | Finding |
| --- | --- | --- | --- |
| 1 | Warning | `lean-gate.sh` `ticket_norm` | The jira lowercase arm is **unguarded**. Deleting it and running both suites: `lean-gate-selftest.sh` 501 pass / all green, `scenario-liveness-selftest.sh` 65 pass / 0 failed. Directly probed against a jira fixture on `claude/acme-77` with argument `ACME-77`: baseline `rc=0`; mutant `rc=10 — the argument names 'ACME-77', but this checkout is on 'claude/acme-77', whose key is 'acme-77'`. That is every jira lane run from its own worktree — the sanctioned shape — refusing, with 566 green assertions saying nothing. `tk14`/`tk14a` cover the *shape* arm's adapter-awareness; nothing covers the *cwd* arm's. Fix is one case: a jira config + a lane worktree on `claude/acme-<n>` + `entry ACME-<n>` expecting `rc=0`. |
| 2 | Warning | `lean-gate.sh` `cmd_claim` | Both `record_ticket_resolution` calls (the jira early-return arm and the github arm) are **unguarded** — deleted in the same mutant above, both suites still green. Every `\| ticket \|` row assertion (`tk8`, `tk9`, `tk10a`) drives `entry`. Low blast radius — on the ordinary path `entry` already wrote the row and the call dedupes — but AC-3's recording claim rests on `entry` alone today. |
| 3 | Suggestion | `lean-gate.sh` `require_ticket_live`, the comment read | `gh api … --paginate` emits one JSON document **per page**, so on a ticket with >30 comments the marker `jq` prints one length per page. Reproduced: `marker` becomes `1\n0`, `[ "$marker" -gt 0 ]` errors with `integer expression expected`, and the re-entry waiver is **denied** — refusing exactly the closed-ticket `entry` the waiver exists to admit, and printing `marker=1\n0` in the reason. Fail-closed, and this repo's tickets run 1–3 comments so it is unreachable today, but the fix is `--slurp` (or `jq -s add`). The sibling paths at 3093/3267/5301 at least assert `type == "array"`; this one has no shape guard. |
| 4 | Suggestion | `lean-gate.sh` ~910 | The comment says the marker filters are "the same two `check-lean-chain.sh` applies at the merge boundary". They are not identical: the chain gate matches `run_id:[[:space:]]*…` by regex, this matches `contains("<!-- run_id: " + $id + " -->")` by exact spacing. Both agree with today's producer at 2938–2942, so nothing is wrong now — but a producer whitespace change would keep the chain gate green while silently disabling this waiver. Either match the regex or narrow the comment. |
| 5 | Nit | `branch-prefix-selftest.sh:275,286` | Two conditions run 175 and 204 characters with runs of four literal spaces between clauses, where every other multi-clause `if` in the file uses backslash continuation. Reads as a collapsed line-wrap. (maintainability-reviewer, confidence 82 — the one panel finding above threshold.) |
| 6 | Note | `lean-gate.sh:301` | `LEAN_GATE_ANY_TREE` does not disarm the new cwd arm. That is consistent with its documented scope (`1`..`5`, `all`, `delta`, `verdict`), and the suites handle it correctly — but the header now under-describes the tree assertions, and an operator running `teardown A` from a shared checkout that happens to have lane branch B out will be refused where they previously were not. Designed trade per AC-4; the message names the remedy. |

Suppressed below threshold: `tracker.keyPattern` interpolated into `grep -E` (regex not command
injection, trusted repo-local config, matches pre-existing `bp_key_re` consumers, 50); `gh` stderr
echoed into refusal text (35); `--comments-file` substituting the comment trail on the waiver —
verbatim the pre-existing seam, and the label half still needs a live read (40);
`seed_run_id_cache` as a single-call-site wrapper (55, deliberate per its own comment).

## Acceptance criteria

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `ticket_key_valid` (adapter-aware, github narrower than `bp_key_re` by design) + `require_ticket_live`'s open check + the closed re-entry waiver gated on the claimed label AND this run's bot-authored marker; `claim` refused on the same evidence. `tk3a`, `tk3b`, `tk5`, `tk5a`, `tk5b`, `tk5c`, `tk14`, `tk14a`. |
| AC-2 | satisfied | `rc=10` on an absent argument for `entry`/`claim`, two messages by cwd, no tracker read on the refusal path. `tk1`, `tk1a`, `tk2`, `tk3c`. |
| AC-3 | satisfied | Inference legal only from a lane cwd; ticket + declared source recorded; enum and wrong-subcommand violations are `rc=2`. `tk8`, `tk9`, `tk10`, `tk10a`, `tk10b`, `tk11`, `tk11a`. Finding 2 narrows where the recording is *guarded*, not whether it happens. |
| AC-4 | satisfied | Disagreement refuses on all four bound subcommands; the milestone call from the same tree still exits 9; a non-work-branch cwd constrains nothing. `tk7-entry/claim/mark/teardown`, `tk7a`, `tk7b`, and the composed `(lean-ticket)` leg. |
| AC-5 | satisfied | Four named reasons, each ahead of any write; the unreadable arm fails closed and says so; the case-folded `could not resolve to` classification is right for the live lowercase wording. `tk3`, `tk4`, `tk5`, `tk6`, `tk6a`, plus `tk1a`/`tk13` for the no-write property. |
| AC-6 | satisfied | Five failure cases and both legal paths in a `(tk)` block of its own, driven through the exported `GH` stub; `bp_branch_key` covered by `(i1)`–`(i4)`, including the agreement-with-`bp_is_work_branch` case. Both suites network-free. |
| AC-7 | satisfied | Two lines under checklist step 1; SKILL.md is 49 lines, inside the 60-line cap. No prose-presence guard added. |
| AC-8 | satisfied | CI `lint-and-selftests` pass (4m45s) and `selftests (macos, bash 3.2)` pass (6m28s) on `414a5a5a`; `mutation-sweep-pr` pass. `pr-gates` fails only at the `lean chain reconciliation` arm, which is this record's absence. |

Repo conventions: no frozen file touched (no `plugin.json` version, no `CHANGELOG.md`, no
`marketplace.json`); `Changelog:` trailers present on all three commits; `feat(dev-pipeline):`
is the honest verb for a new capability in this repo.

Findings 1 and 2 are missing guards over correct code, not defects in it, and finding 3 is
unreachable at this repo's comment volumes — none of them is a blocker. Verdict: approve.

Design fidelity: not-applicable — the spec declares no `## Design` section and the repo
configures no `design.provider`.
