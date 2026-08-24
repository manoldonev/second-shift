# #644 — measure every marketplace skill against a bare session, then cut what does not clear the bar

Parent #284. Operator-directed at the 2026-08-22 backlog recalibration ("keep the quality and drop
the bloatware"). Sibling of #641/#642/#643 in the delete-first program.

## Problem, restated in one line

The marketplace's value proposition is that its skills beat a bare session. That has never been
measured against the current model generation, and P6 obliges a re-measured basis rather than an
inherited one.

## What this slice is

A **pre-registered ablation**, not a harness. Three comparisons, each against a bare Claude Code
session with no second-shift plugins loaded. The pre-registration lands first and is never edited;
the results land after it; every verdict cites the losing arm's evidence.

Deliberately **not** in scope, per the ticket: building an eval harness. No new checked-in script,
no new selftest, no new guard. The measurement is operator-run, the commands are recorded verbatim
in the evidence, and the raw arm outputs are committed. #506 owns the elicitation harness gap and is
not a prerequisite.

## The bare arm — one transport, used by all three comparisons

```
printf '%s' "<prompt>" | env -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT \
  -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_BRIDGE_SESSION_ID -u CLAUDE_CODE_MESSAGING_SOCKET \
  -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_SSE_PORT -u CLAUDE_EFFORT -u CLAUDE_PID \
  claude -p --model opus --setting-sources '' [--allowedTools "Read,Grep,Glob"]
```

`--setting-sources ''` drops user/project/local settings, which is where `enabledPlugins` lives —
verified plugin-free by probe (`NO-SECOND-SHIFT-SKILLS`). The env scrub is [[selftest-env-leak]]
discipline: a build session's own spawn environment otherwise leaks into the child. `--bare` was
rejected — it demands `ANTHROPIC_API_KEY` and this machine authenticates by OAuth.

The repo's own `CLAUDE.md` still auto-loads in both arms. That is correct — it is the repository,
not the kit — but it is a **controlled confound** wherever an artifact `CLAUDE.md` itself mandates,
and every such item is scored non-discriminating rather than credited to either arm.

## Scope bound stated up front

An end-to-end bare **build** (ticket to mergeable PR) does not fit a collectible turn, and the
harness contract forbids starting work this session cannot collect. Comparison 1 therefore runs a
labelled **proxy** metric and, by the pre-registered rule, **cannot license a `keep`**. Comparisons
2 and 3 run outcome metrics the ticket names and can license any verdict. This is stated in the
pre-registration before any result, not discovered after.

## Acceptance Criteria

- **AC-1** (oracle) — `docs/skill-ablation-pre-registration.md` is committed **before** the first
  commit carrying any result, and names for each of the three comparisons: the outcome metric, the
  sample and its size, the scoring rule, and the keep / cut-to-delta / delete thresholds. Its
  landing order is checkable with `git log --format='%H %s' -- <path>` against the evidence commits.
- **AC-2** (proxy) — each comparison is run over exactly its pre-registered sample, with the raw
  arm outputs, the prompts, and the scoring committed under `docs/skill-ablation/`. Nothing scored
  is absent from that directory.
- **AC-3** (critic) — `docs/skill-ablation.md` records a verdict of `keep`, `cut-to-delta`, or
  `delete` for every comparison, each citing the losing arm's committed evidence by path. No
  comparison exits `undetermined`; the pre-registered default in the absence of a demonstrated win
  is `cut-to-delta`, which is what makes small-N terminate rather than abstain.
- **AC-4** (critic) — every surface this slice leaves standing records its re-measured P6 basis and
  the measurement date, in a form the next generation change can re-measure against.
- **AC-5** (oracle — selftest) — any deletion this slice executes leaves
  `bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh` green, with no
  orphaned selftest, agent contract, marketplace entry, or skill cross-reference left behind.
- **AC-6** (critic) — a `Changelog:` trailer on the branch, carrying `Migration:` if any shipped
  skill is removed.

## Do not touch

`plugins/*/.claude-plugin/plugin.json` `version`, `CHANGELOG.md`,
`.claude-plugin/marketplace.json` `metadata.version` — release artifacts, derived at release time.

## Decision Ledger

No pre-flight ledger exists for #644, so this table is the run's own; every row is grounded in
the ticket text or the codebase, never assumed.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Open region from the ticket body: delete a losing arm in-slice, or file a successor? | The ticket states the reversible default — delete-in-slice when the deletion is self-contained, flagged in the PR — and this run takes it. A deletion that is not self-contained (reaches a consumer-facing contract, or an entry point outside this repo's dogfood use) is filed instead, named in the report. | ticket-sourced |
| D-2 | What "bare" means operationally | Plugin-free, same repo, same model tier (`opus`), same working tree. Not a fresh config dir — that loses OAuth and would measure authentication, not scaffolding. | codebase-derived |
| D-3 | Where the burden of proof sits | On the skill. `keep` requires a demonstrated win; absence of evidence yields `cut-to-delta`, never `keep`. This is the rule that makes AC-1 and AC-3 consistent at the sample sizes actually reachable, and it is the only reading under which "roughly equal, but ours is more thorough" is a loss as the ticket demands. | ticket-sourced |
| D-4 | Comparison 3's oracle is kit-authored, which biases toward the incumbent | Only ledger rows with `user-answered` provenance are scored — those were ratified by the operator and consumed by a build, so an external party validated them as load-bearing. `codebase-derived` rows are kit-internal and excluded. | codebase-derived |
| D-5 | Whether the milestone gates are re-measured here | No. `docs/gate-ablation.md` measured them over a pinned 52-record corpus and is cited as inherited evidence with its pin named. Re-running it would spend the slice's budget reproducing a committed answer. What this slice adds for comparison 1 is the **skill** half, which that report does not cover. | codebase-derived |
| D-6 | No new script or selftest | The ticket excludes an eval harness, and a checked-in script here would owe a selftest under `CLAUDE.md` — machinery to measure whether there is too much machinery. Commands are recorded in the evidence instead. | ticket-sourced |
