# Plan — the lane review: one session against the ticket and record

## 1. The review prompt

- [ ] 1.1 The recorded review prompt names no review-lead invocation, no panel declaration and no code-review.mjs staging, and carries the completeness and correctness instruction (plugins/dev-pipeline/skills/run/run-selftest.sh) [AC-1] [AC-7]
- [ ] 1.2 The recorded review prompt tells the session to read the ticket with gh issue view, and to stop with reason: ticket-unreadable when it cannot (plugins/dev-pipeline/skills/run/run-selftest.sh) [AC-2]
- [ ] 1.3 Rewrite review_prompt(): the completeness and correctness blocks, the ticket read, review-context.md, the design-fidelity seat, the cost-risk finding, the knowledge-base block, the policy_edited() list (plugins/dev-pipeline/skills/run/run.sh)

## 2. The verdict grammar and the environment reasons

- [ ] 2.1 verdict-check accepts line 3 reason: ticket-unreadable and reason: seat-unavailable, refuses an approve that carries one, and still parses a verdict with or without ## Panel (plugins/dev-pipeline/tools/verdict-check-selftest.sh) [AC-3]
- [ ] 2.2 A verdict with reason: ticket-unreadable or reason: seat-unavailable ends the run env-not-ready and spawns no BUILD; the knowledge-base block is the session's own (plugins/dev-pipeline/skills/run/run-verdict-selftest.sh) [AC-2] [AC-3]
- [ ] 2.3 Edit the verdict-grammar, verdict-style and kb-contributions blocks in both copies; verdict-check.sh and the scheduler's env-not-ready read the two new reasons (plugins/dev-pipeline/skills/run/run.sh, plugins/dev-pipeline/skills/review/SKILL.md, plugins/dev-pipeline/tools/verdict-check.sh, plugins/dev-pipeline/skills/run/run-selftest-lib.sh)

## 3. Kept behavior

- [ ] 3.1 verdict-check before and after posting, expectation tracing, the render rule, the build's account read last, the bot identity and the review status keep working (plugins/dev-pipeline/tools/verdict-check-selftest.sh, plugins/dev-pipeline/skills/run/run-verdict-selftest.sh, plugins/dev-pipeline/skills/run/run-rows-selftest.sh) [AC-4]

## 4. The review session's grants and spawn

- [ ] 4.1 The review allowlist lacks Workflow, Skill, Bash(find *), Bash(cp *), Bash(shasum *) and the review-context lint, keeps Agent, and the review spawn disables background tasks with its own Bash timeouts (plugins/dev-pipeline/skills/run/run-rows-selftest.sh, plugins/dev-pipeline/skills/run/run-selftest.sh) [AC-5]
- [ ] 4.2 Drop the grants and the background wait; spawn the review in the foreground; policy_edited() lists only the config and .claude/second-shift/ (plugins/dev-pipeline/skills/run/run.sh, plugins/dev-pipeline/skills/run/run-claim-selftest.sh)

## 5. The manual review skill

- [ ] 5.1 review/SKILL.md reads the ticket, reviews the diff itself in the shared completeness and correctness blocks, and loses the panel and Workflow steps (plugins/dev-pipeline/skills/review/SKILL.md)

## 6. The benchmark arm and the release checklist

- [ ] 6.1 Every bench arm, lane-review included, loads and formats through bench.py's own parse_arm and str.format (plugins/review-toolkit/evals/code-review-bench-eval/bench-arms-selftest.sh) [AC-9]
- [ ] 6.2 Add arms/lane-review.md with the shared correctness block; name it in the bench README and run.sh usage (plugins/review-toolkit/evals/code-review-bench-eval/arms/lane-review.md, plugins/review-toolkit/evals/code-review-bench-eval/README.md, plugins/review-toolkit/evals/code-review-bench-eval/run.sh)
- [ ] 6.3 The release checklist names lane-review instead of review-lead-lane (scripts/derive-release.sh, docs/releasing.md)
