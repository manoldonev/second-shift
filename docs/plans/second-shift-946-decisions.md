# Intake receipt — #946: minimize earlier verdict comments as outdated; retire the admission rule

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | What counts as a verdict comment | First line matches `^verdict: (approve\|needs-work)$`, the predicate `verdict()` already applies (`run.sh:690`); notices, failed-status comments and all other comments are never minimized | codebase-derived | fact |
| D-2 | Who minimizes on the lane path | The scheduler (`run.sh`), not the review session: `review_allowlist` grants no `gh api` and never the bot wrapper whole (`run.sh:554-559`) | codebase-derived | fact |
| D-3 | When `run.sh` minimizes | Only when a verdict binds: after `verdict()` returns and the head-moved check passes, beside `review_status` (`run.sh:1023`). A verdict voided by a moved head is minimized later, when a newer one binds; a run ending review-unbound minimizes nothing | user-answered | intent |
| D-4 | Whose earlier verdicts are minimized | Lane authors only: a Bot, or the account the poster writes with — the B10 author filter (`run.sh:679-689`). A stranger's verdict-shaped comment is left alone | user-answered | intent |
| D-5 | How the two posting paths share it | A shared helper `plugins/dev-pipeline/tools/minimize-verdicts.sh <pr> <kept-comment-id>` owns the predicate, the author filter, the earlier-than-kept selection and the GraphQL `minimizeComment` call with `classifier: OUTDATED`; `run.sh` calls it after D-3's bind, `skills/review/SKILL.md` step 8 calls it after the verdict comment is posted | user-answered | intent |
| D-6 | Identity for the minimize | `run.sh` passes `$GH` (the bot when `gh-bot.sh --status` is `ok`, `run.sh:198-201`); the skill uses the same `gh` it posted the verdict with (step 8). A failure is never retried as the user in the bot's place | codebase-derived | fact |
| D-7 | Where a failed minimize is surfaced | `run.sh`: one line in the run block (the `STATUS_NOTES` pattern, `run.sh:700-723`); never fatal; the run outcome and the commit status are unchanged. Manual skill: reported in the session output only, no PR comment — this narrows the ticket's "or a plain comment" acceptance line for the manual path | user-answered | intent |
| D-8 | Can minimizing unbind or rebind a verdict, incl. on `--resume` | No: `verdict()` reads only comments created inside the current review window (`run.sh:688`, window opened at the review spawn, `run.sh:1003`); every earlier verdict is outside it, `--resume` opens a new window, and the minimize runs after `verdict()` has returned. Whether minimizing touches `updated_at` therefore cannot matter | codebase-derived | fact |
| D-9 | Which verdicts are "earlier" | Every lane-authored verdict comment created before the kept one, including an earlier one in the same review window (two verdicts from one session, the I5 case, `run-selftest.sh:107`); the kept comment is the bound one on the lane path, the one just posted on the manual path | codebase-derived | fact |
| D-10 | Tests | The helper's own selftest covers the predicate (verdict vs non-verdict first lines), the author filter and the earlier-only selection; a `run-selftest.sh` case fails without the `run.sh` wiring (CLAUDE.md: a `run.sh` behavior change lands with a case that fails without it) | codebase-derived | fact |
| D-11 | Whether a bot 403 on minimize gets a permission hint | Default: no hint, the raw error is reported per D-7; build may add one only if the required GitHub App permission is verified from GitHub's docs (owner: build, under OR-1) | deferred | open |
| D-12 | Retire the admission rule in this item | Delete `CLAUDE.md`'s `**Admission.**` paragraph and the sentence "It writes the admission evidence into the ticket body and stops." in the same PR as the verdict minimize | user-answered | intent |
| D-13 | How wide the retirement goes | The whole consumer-evidence doctrine: also the thesis clause "We develop it against what consumer records show, never against this repo's own lane.", the opening line's "not as evidence: … consumer repos' committed records", and `review-context.md`'s dogfood/consumer-capability sentences and "re-adding needs consumer admission evidence" | user-answered | intent |
| D-14 | The manifesto's P4/P5 posture paragraph | Deleted: its only claim is that the admission rule enforces P4/P5 | user-answered | intent |
| D-15 | What the retirement leaves alone | `docs/plans/*` (history), the "Population: dogfood repo only" study-doc headers (they scope a measurement), `docs/consumer-eval.md` (the evaluation recipe); `docs/testing.md`'s admission sentence is deleted with the rule, per the amended ticket body | user-delegated | intent |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Which GitHub App permission `minimizeComment` needs for the bot (unverified at intake) | reversible-default-and-flag |

OR-1 is cheap to reverse: the default reports the raw error and changes no outcome (D-7), so adding or correcting a permission hint later is a one-line copy change.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | PR conversation after a later verdict binds in a lane run: earlier collapsed as outdated, bound one expanded | decided (D-3) |
| S-2 | PR conversation after a manual `/dev-pipeline:review` post | decided (D-5) |
| S-3 | PR conversation when a run ends review-unbound | decided (D-3) |
| S-4 | Non-verdict comments: head-moved notices, review-did-not-run notices, failed-status comments | decided (D-1) |
| S-5 | A stranger's verdict-shaped comment | decided (D-4) |
| S-6 | Run block when a minimize fails | decided (D-7) |
| S-7 | Manual review session output when a minimize fails | decided (D-7) |
| S-8 | Run outcome and the `second-shift/review` commit status when a minimize fails | decided (D-7) |
| S-9 | `CLAUDE.md` as every session loads it: no admission rule, no consumer-evidence doctrine | decided (D-12) |
| S-10 | `review-context.md` as review-lead reads it | decided (D-13) |
| S-11 | `docs/pipeline-manifesto.md` and `docs/testing.md` | decided (D-14) |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Fan-out

Fan-out: skipped — by the operator at the pre-flight notice: no reason given
