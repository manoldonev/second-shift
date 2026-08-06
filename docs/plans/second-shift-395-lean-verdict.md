# lean review verdict — #395

verdict=approve
run_id: review-395-1
session_id: c5bd33ff-b8f1-43ba-9669-e835878703f1
rounds: 1
pr: #399
reviewed_head: fc02151955ef1f0def3b4e9c0fbfebf35c4c58a8
reviewed_patch_id: 4128dc2f408b6ad681e7b232c42638683fbb352e
inherited_patch_id: none
inherited_from_verdict: none
model: unknown

## Verdict: approve (round 1)

Full-branch read — `lean-gate.sh delta 395` printed the FULL range (`3eb0e53..HEAD`,
nothing verifiable to inherit), so this round covers both changed files with no
inheritance.

Prose-only diff: 47 added lines across the committed spec and a 7-line tracker-delta
blockquote on `review-lean`'s SKILL.md. No gate script, workflow, or selftest touched.

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — tracker-delta note documents jira key resolution in place of `Closes #N` | **satisfied** | `review-lean/SKILL.md:17-22`. The note names `Closes [<KEY>]` under `### Jira Items` and cites checklist step `(2)` — the step that carries the `Closes #N` reading (line 30-31). Claim verified against two independent sources, not just against `run-lean`'s wording: the jira adapter's **PR ticket reference** row (`run/tools/tracker/jira/README.md`) and `lean-gate.sh`'s own `jira_items_section()` parser, which matches `^#+[[:space:]]+jira items$` case-insensitively. |
| AC-2 — note confirms the step-8 findings comment is unaffected by `tracker.writes: false`, and states no other checklist step differs | **satisfied** | Both clauses present verbatim at `SKILL.md:19-21`. The findings-comment claim is correct: step 8 posts a **PR** comment, and the jira adapter's read-only contract binds Atlassian writes and issue-comment writes, not the PR surface. The "no other checklist step differs" clause is literally present and substantively holds for steps 1–6; one imprecision at step 7 is recorded as a warning below, not a blocker. |
| AC-3 — prose-only; no gate script or selftest touched; existing suites stay green | **satisfied** | `git diff --stat origin/main...HEAD` = 2 files, both `.md`, +47/-0; no `.sh`/`.mjs`/`.yml`. CI on `fc02151`: `lint-and-selftests` **pass**, `selftests (macos, bash 3.2)` **pass**. Local corroboration from the PR-head checkout with `env -u CLAUDE_CODE_SESSION_ID` (a bare sweep leaks the session id and is not CI-equivalent): `shellcheck` rc=0, `jq empty` rc=0, all `*-selftest.sh` at `-P 4` **without** `SKIP_STRESS` rc=0. `stack-generality-lint.sh` OK. |
| AC-4 — `Changelog:` trailer on the commit | **satisfied** | `fc02151` carries a multi-line `Changelog:` trailer describing the consumer-visible delta, closing `Migration: none.` |

`pr-gates` is red on `fc02151`, and that is **not** a defect in this patch. Reproduced
locally with the job's full env: the single failing arm is `✗ no committed verdict record
(a file named *-395-lean-verdict.md)` — the artifact this round produces. Every other arm
is green, including `✓ spec: docs/plans/second-shift-395-lean.md (4 AC-n reference(s))`
and `✓ claim: bot-authored lean-claimed comment on #395 within the PR-open window`.

## Findings

| # | Severity | Location | Finding |
| --- | --- | --- | --- |
| 1 | Warning | `review-lean/SKILL.md:17-21` vs `:54-58`, `:26-29` | "No other checklist step differs" is marginally over-broad. Steps 1 and 7 both name **the merge boundary** (`scripts/check-lean-chain.sh`) as an enforcement point that recomputes the patch hash and refuses a stale or mis-identified record. `tracker/README.md` states in terms that that gate "remains **github-only**: it keys off the bot-authored `lean-claimed` comment, which this adapter posts none of. A jira run therefore has an operator-run backstop and no automated one." So on the tracker axis those two steps *do* lose an enforcement point under jira. Held to warning rather than blocker for a specific reason: the same gate also carries a `CONSUMER UNPORTABILITY` banner ("second-shift-only … Do not ship this to the consumer CI template"), so its absence is primarily a **dogfood-vs-consumer** axis, not a github-vs-jira one — a github *consumer* has no merge boundary either. Naming it as a jira delta would imply it fires for github consumers, which is also false. No operator action changes either way: `lean-reconcile.sh` keeps five of six arms under jira, including the P10 authorship check the independence contract rests on. |
| 2 | Warning | `review-lean/SKILL.md:17` | The disclaimer scopes itself to "The checklist below", where `run-lean`'s counterpart reads "The checklist **and rules** below". `review-lean` is the file that actually has a `## Rules that are not negotiable` section, and its first bullet makes the same github-only claim finding 1 describes — a hand-written record "reds at `scripts/check-lean-chain.sh` anyway" (`:66-67`). Dropping "and rules" leaves the one section with an adapter-sensitive claim outside the note's declared scope. Same root cause as finding 1; fixable by restoring the two words. |

Neither warning blocks. Both are precision-of-prose observations on a claim whose
operative content — how to resolve the issue key, and that step 8 is unaffected — is
correct and independently verified.

## Panel

`review-lead` over the full range. Routing: 47 lines / 2 files ⇒ **Small**; the changed
SKILL.md is the pipeline's own execution surface, so the trivial-inert lane was correctly
not taken. Spawned security, performance, maintainability (core, Small) plus
scope-completeness (issue referenced, never depth-suppressed). Effective registry = the
plugin panel; the repo config declares no `reviewers` block.

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Maintainability | Pass | 0 | — |

No reviewer went dark. a11y and the design-fidelity dimension were **not routed** — no
changed path matched `stageParams.webComponentGlobs` (`apps/web/**/*.{tsx,jsx}`); a
prose-only diff on a plugin skill is the expected shape, not a coverage gap.

Suppressed (below threshold, recorded for visibility): security-reviewer, confidence 40 —
the issue key being sourced from PR-body text is attacker-influenceable in principle, but
this restates the pre-existing github pattern for jira and the key is consumed as a lookup
argument, never interpolated into a shell or query. No new exposure.

Both findings above are the orchestrator's own cross-cutting read, not a reviewer's; they
are labeled as such and neither was escalated from a subagent classification.

## Strengths

- The note is **verifiable rather than merely mirrored**: every claim it makes lands on a
  real mechanism — `jira_items_section()` in `lean-gate.sh` really does parse that heading,
  and `cmd_delta`/`cmd_verdict` really do carry no `TRACKER_TYPE` branch, which is what
  makes the PR body's "the gate itself is adapter-insensitive" true rather than hopeful.
- It resolves the harder half of the gap explicitly instead of by omission. Stating that
  the step-8 findings comment is a **PR** write and therefore outside `tracker.writes:
  false` closes exactly the ambiguity that would otherwise make a jira reviewer skip the
  one step that hands findings back to the build session.
- Scope discipline: the spec's "Prose-only change: no gate script or selftest edit" is
  honored exactly, and it correctly declines to add a prose-presence grep — which
  `CLAUDE.md` bans outright and which would have read as coverage while guarding nothing.
