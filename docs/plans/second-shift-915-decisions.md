# Intake receipt — #915: approval bound to its reviewed sha at merge time, as a commit status

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Mechanism | A commit status on the sha the bound verdict names, posted by `run.sh` at the bind point after the head-moved check (`run.sh` ~810, the `say "verdict: …"` line), never inside `verdict()`. No consumer CI workflow. Per the operator's "Decided" section of https://github.com/manoldonev/second-shift/issues/915 | ticket-sourced | fact |
| D-2 | Enforcement | Posted on every run; requiring it is the consumer's branch-protection choice; onboard writes no protection rules. Docs call it tamper-evident, never the gate of record (`docs/pipeline-manifesto.md:109-112`). Per https://github.com/manoldonev/second-shift/issues/915 | ticket-sourced | fact |
| D-3 | Status per outcome | `approve` → `success`; `needs-work` → `failure` (render-unavailable included: it is a needs-work verdict). `review-unbound`, `cost-spent`, `rounds-spent` and every other terminal post nothing new — a head without the status is what blocks a required check, and the manual review (D-6) fills it. A status from an earlier bound verdict stays on its own sha | user-answered | intent |
| D-4 | Context name, target URL, description copy | Context `second-shift/review` (deliberately not the retired `second-shift evidence`, so a stale requirement never gets quietly satisfied; doctor §6.5 keeps flagging it). Target URL = the verdict comment's `html_url`. Descriptions: `approved at this head — see the verdict` / `needs-work at this head — see the verdict` | user-answered | intent |
| D-5 | Identity and failure handling of the post | Posted with `$GH` (the bot when `BOT_OK=1`, else the operator's `gh`). A failed post never changes the terminal and never falls back to writing as the operator under a configured bot (`run.sh:163-168` rule); it is reported in the run block. Per https://github.com/manoldonev/second-shift/issues/915 | ticket-sourced | fact |
| D-6 | Manual `/dev-pipeline:review` | Step 8 also posts the same `second-shift/review` status (success/failure per D-3, D-4 copy, target = its own comment) on the sha in its `reviewed:` line, after the headRefOid re-check, through `gh-bot.sh` when `--status` is `ok`, plain `gh` otherwise | user-answered | intent |
| D-7 | GitHub App "Commit statuses: write" | `docs/onboarding.md:191-196` names it (issues+contents+commit statuses write). When a bot post fails with 403/404, the run-block line names the missing App permission. Doctor does not probe App permissions | user-answered | intent |
| D-8 | Jira tracker | Identical: the status is a code-host write, like the verdict comment (`plugins/dev-pipeline/skills/review/SKILL.md` tracker delta) | codebase-derived | fact |
| D-9 | Doctor | Reports whether the default branch requires `second-shift/review` — informational like the opt-out scan (`doctor.sh` §6), never `bad`; no gh / no auth / offline / no admin to read protection → "unknown". Per https://github.com/manoldonev/second-shift/issues/915 | ticket-sourced | fact |
| D-10 | Docs | `docs/migrations/v2-to-v3.md:144-148` "Nothing replaces them" points to the new status; `plugins/second-shift/templates/consumer/SECOND-SHIFT.md` inventory lists the status write; it and `docs/team-rollout.md` "What is a gate here" say how to require it in branch protection. Per https://github.com/manoldonev/second-shift/issues/915 | ticket-sourced | fact |
| D-11 | Selftests | Fake `gh` in `run-selftest.sh` logs `statuses/<sha>` posts; cases that fail without the change: posted on `HEAD_SHA` with D-3 state; through the bot under `FAKE_BOT`; nothing posted for a verdict voided by a moved head; a failed post leaves the terminal unchanged and is reported in the run block. Doctor case for the informational/unknown read. Per https://github.com/manoldonev/second-shift/issues/915 | ticket-sourced | fact |
| D-12 | Duplicate scan | `dup-scan.sh --issue 915` rc 0 — no candidates | codebase-derived | fact |
| D-13 | Run-block wording for the status result | The OR-1 default: one paragraph per bound verdict under the run-block table, `status: second-shift/review=<state> on <sha>` or `status: NOT posted (second-shift/review=<state> on <sha>) — <gh error>`, with `— the bot's GitHub App needs the 'Commit statuses: write' permission` appended when a bot post fails with HTTP 403/404. A run with a needs-work round lists both posts. Reason: the OR-1 default, settled at build; the state and sha are kept on a failed line so the human sees which head is missing its status | user-delegated | intent |
| D-14 | Doctor's line level and its protection read | `ok` when the default branch requires `second-shift/review`; a `note` (not a WARN) when it does not, and for "unknown". Read with plain read access: `repos/<r>/branches/<b>` (classic protection's required contexts and checks) plus `repos/<r>/rules/branches/<b>` (rulesets); either read failing is "unknown". Reason: not requiring it is a sanctioned consumer choice (D-2), so a WARN every run would nag; the admin-only protection endpoint would make most tokens "unknown", and a ruleset-only requirement would read as absent | user-delegated | intent |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Exact run-block wording for the status outcome (posted / not posted + reason, incl. the D-7 permission hint) | reversible-default-and-flag |

OR-1: default is one line under the run-block table, e.g. `status: second-shift/review=<state> on <sha>` or `status: NOT posted — <reason>`. Copy in a PR body, rewritten every run — cheap to change later.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Commit status on the approved head in the PR checks list | decided (D-3) |
| S-2 | Commit status on a needs-work head | decided (D-3) |
| S-3 | Head after review-unbound / handoff / budget stop (no status) | decided (D-3) |
| S-4 | Status context name, description and link as seen in the checks list and branch-protection picker | decided (D-4) |
| S-5 | Run block line when the post succeeds or fails | decided (D-13) |
| S-6 | Manual review's status | decided (D-6) |
| S-7 | Doctor's branch-protection line, incl. "unknown" | decided (D-9) |
| S-8 | Onboarding App-permission text | decided (D-7) |
| S-9 | Migration doc, SECOND-SHIFT.md inventory, team-rollout gate section | decided (D-10) |
| S-10 | Count-only suppressed findings from #914 | out-of-scope — the ticket excludes it: an auditability gap with no defect attached |

## Checks

- `bash plugins/dev-pipeline/skills/run/run-selftest.sh`
- `bash plugins/second-shift/skills/doctor/tools/doctor-selftest.sh`

## Design frames

Design: none — this repo sets no design.provider and the change renders no screen.
