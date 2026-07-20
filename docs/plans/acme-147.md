# Plan: #147 — `ticket-sourced` provenance for operator decisions recorded in ticket comments

## Context / problem framing

The Decision Ledger provenance enum is closed at four values (`user-answered`, `user-delegated`, `codebase-derived`, `deferred`). Two behavioral sites additionally forbid the two user-provenance values from *originating* inside an autonomous run — they are legal only when hydrated verbatim from a pre-flight `.claude/pipeline-state/{issue}-ledger.md`:

- `plugins/dev-pipeline/skills/run/stages/3-write-plan.md:28` — "author the section in-pipeline with `codebase-derived` / `deferred` provenance ONLY".
- `plugins/dev-pipeline/skills/pipeline-retro/SKILL.md:57` — a `user-answered` / `user-delegated` row with no backing pre-flight ledger file is a **fabrication-class** finding.

The consequence: when an operator resolves scope in a ticket comment — a common and desirable path — a run that adopts those resolutions has no honest way to record where they came from. `user-answered` is fabrication-class without the backing file, `user-delegated` and `codebase-derived` are false, and `deferred` misrepresents a decision that was in fact made. Run `2026-07-20T115104Z-Mac-59511592` on #106 was correctly blocked at Stage 4 for exactly this, and unblocking it required a human hand-ratifying the comment into a pre-flight ledger.

This plan adds a fifth value, `ticket-sourced`, whose Resolution cell must cite the source comment by URL, and moves every lockstep mirror in the same commit.

## Assumptions

- **Option 1 is the requirement, not a decision to re-litigate.** The issue body states it with rationale ("Leaning (1): honest provenance beats a materialization fiction"). Option 2 (Stage-1 materialization of a pre-flight ledger) is explicitly out of scope. Because this is spec-given, it carries no ledger row.
- The literal token is `ticket-sourced` — the issue's own example, fixed here so the string is not renamed mid-review across eight sites.
- No version bump and no `CHANGELOG.md` edit: both are release-derived artifacts frozen in feature PRs (`CLAUDE.md`, `scripts/check-frozen-files.sh`).

## Decision Ledger

| ID  | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | Is the comment-URL citation lint-enforced, and in what shape? | Lint-enforced in `ledger-lint.sh`: a `ticket-sourced` row's Resolution cell must contain an `https://` URL. Tracker-neutral rather than a `github.com` pattern, because `schema/second-shift.config.schema.json` models `tracker.type` as github\|jira and a GitHub-specific regex would regress that genericity | codebase-derived |
| D-2 | Which sites move in lockstep with the canonical enum? | The eight verified sites in "Affected files" below. `plugins/intake-toolkit/hooks/exitplan-ledger-gate.sh` is deliberately NOT edited: it carries no provenance literal and shells out to `ledger-lint.sh`, so extending the lint covers the hook with zero changes | codebase-derived |
| D-3 | Which ticket comments may a run adopt as authoritative? | Contract rule in the canonical section: only comments whose `author_association` is `OWNER` / `MEMBER` / `COLLABORATOR`. Grounded in what is already available — Stage 1 reads issue comments via the REST payload that carries this field, so the rule needs no new infrastructure. Not lint-enforceable: `ledger-lint.sh` sees only the plan file, never the tracker | codebase-derived |
| D-4 | Precedence when a pre-flight ledger and a comment disagree | The pre-flight ledger row wins; conflicting or ambiguous comments resolve to `deferred` naming the conflict in the Resolution cell — the fallback the contract already prescribes for ungroundable decisions (`interviewing-baseline/SKILL.md`) | codebase-derived |

## Affected files / modules

**Canonical**

- `plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md` — the enum block behind `<!-- canonical: interviewing-baseline provenance enum — all mirrors keep verbatim -->`; add the fifth value, its citation rule, its adoption rule, and the precedence rule.

**Literal mirrors** (each carries `<!-- mirror of interviewing-baseline provenance enum — keep verbatim -->`)

- `plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh` — `PROVENANCE_ENUM` (line 35) + the header contract comment (line 15) + a new citation check.
- `plugins/review-toolkit/agents/plan-reviewer.md` — the closed-enum restatement (line 98).
- `plugins/design-toolkit/agents/figma-faithful-plan-reviewer.md` — the closed-enum restatement (line 88). **Not named in the issue**; found by grep on the shared mirror marker.

**Behavioral mirrors** (restrict which values may originate in-run — the load-bearing pair)

- `plugins/dev-pipeline/skills/run/stages/3-write-plan.md` — line 28's `codebase-derived` / `deferred` ONLY clause.
- `plugins/dev-pipeline/skills/pipeline-retro/SKILL.md` — line 57's in-pipeline provenance restriction + fabrication-class rule.

**Tests**

- `plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-fixtures/valid-ledger.md` — gains a `ticket-sourced` row.
- `plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh` — new positive/negative cases; the `(ll-c)` row-count assertion moves 4 → 5.

**Deliberately unchanged**

- `plugins/intake-toolkit/hooks/exitplan-ledger-gate.sh` — delegates to the lint (D-2).
- `plugins/intake-toolkit/skills/intake-interviewer/SKILL.md`, `plugins/intake-toolkit/skills/plan-interview/SKILL.md` — prose naming individual values in an interview context; neither restates the closed enum, and neither elicitation path produces `ticket-sourced` rows (they interview a live human).

## Reuse inventory

- `violate()` in `ledger-lint.sh` — the existing violation-accumulator; the new citation check reuses it rather than introducing a second error channel.
- `trim()` in `ledger-lint.sh` — the existing quoting-safe cell trimmer; the citation check reads the already-trimmed `$resolution` variable.
- `lint_rc()` in `ledger-lint-selftest.sh` — the existing exit-code capture helper; new cases reuse it.
- The `sed`-a-fixture-into-a-mutant idiom in `ledger-lint-selftest.sh` (cases `ll-e`..`ll-h`) — the negative citation case follows it.
- No new helpers introduced.

## Implementation steps

1. **Canonical contract** — in `plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md`, change "**Provenance closed enum** — exactly these four values" to five, add the `ticket-sourced` bullet defining it (adopted from a ticket comment; Resolution must cite the comment URL; only `OWNER`/`MEMBER`/`COLLABORATOR` comments are adoptable), and add the precedence rule (D-4) to the **Rules** list. Add a `ticket-sourced` row to the illustrative table.
2. **`ledger-lint.sh`** — extend `PROVENANCE_ENUM` to include `ticket-sourced`; update the check-3 header comment (line 15) to list five values; add the citation check inside the row loop: when `$provenance` is `ticket-sourced` and `$resolution` contains no `https://`, `violate` with a message naming the row and the requirement.
3. **`plan-reviewer.md` / `figma-faithful-plan-reviewer.md`** — update both verbatim enum restatements to the five-value set, keeping the `assumed` is never legal clause.
4. **`3-write-plan.md`** — amend line 28 so in-pipeline authoring permits `codebase-derived` / `deferred` / `ticket-sourced`, with `ticket-sourced` requiring the cited comment URL; keep the prohibition on `user-answered` / `user-delegated` originating in-run.
5. **`pipeline-retro/SKILL.md`** — amend line 57's audit rule the same way: `ticket-sourced` joins the legal in-pipeline set, and a `ticket-sourced` row whose Resolution cites no URL becomes the fabrication-class finding (the un-cited row is the fabrication risk, not the value itself).
6. **Fixture** — add `| D-5 | ... | ... https://... | ticket-sourced |` to `ledger-lint-fixtures/valid-ledger.md`.
7. **Selftest** — update `(ll-c)` to expect `5 ledger row(s)`; add `(ll-l)` positive (a cited `ticket-sourced` row lints clean, covered by `ll-a` on the extended fixture) and `(ll-m)` negative (strip the URL from the `ticket-sourced` row → exit 1, violation names the citation requirement).

## Test strategy

Verify-after (infra/docs change; the only executable surface is `ledger-lint.sh`, which has an existing selftest). No mutation-resistant unit-test work: `commands.second-shift.unitTestScope` is `null`, so this repo has no mutation surface and the gate skips.

The selftest is the real gate. Two cases carry the new behavior:

- **Positive** — the extended fixture (now five rows, one `ticket-sourced` with an `https://` citation) must still exit 0. This is `(ll-a)` widened, plus the `(ll-c)` count assertion.
- **Negative** — a mutant that removes the URL from the `ticket-sourced` Resolution cell must exit 1 with a violation naming the citation requirement. Without this case the citation check could be a no-op and every test would still pass.

The existing `(ll-e)` `assumed` mutant continues to prove the enum stays closed — the change adds a value, it does not open the enum.

## Acceptance-criteria traceability

The Stage-1 intent snapshot is **empty** — the issue carries no `AC-n` section — so the IDs below are `derived`, not authoritative. Stage 8's scope-completeness gate runs in prose-vs-diff fallback mode.

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 (derived) | A ledger row with `ticket-sourced` + a cited URL lints clean | 2, 6 | `ll-a`, `ll-c` |
| AC-2 (derived) | A `ticket-sourced` row with no URL is a lint violation | 2, 7 | `ll-m` |
| AC-3 (derived) | The enum literal is identical across canonical + all three literal mirrors | 1, 2, 3 | `grep` in Verification |
| AC-4 (derived) | An in-pipeline Stage-3 plan may carry `ticket-sourced` without tripping Stage 4 or the retro audit | 4, 5 | `grep` in Verification |
| AC-5 (derived) | The enum stays closed — `assumed` still fails | 2 | `ll-e` |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}

# AC-3: the five-value enum is verbatim across canonical + literal mirrors (expect 4 hits)
grep -rc 'user-answered | user-delegated | codebase-derived | deferred | ticket-sourced' \
  plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md \
  plugins/review-toolkit/agents/plan-reviewer.md \
  plugins/design-toolkit/agents/figma-faithful-plan-reviewer.md
grep -n "PROVENANCE_ENUM=" plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh

# AC-4: both behavioral sites now permit the value in-run
grep -n 'ticket-sourced' plugins/dev-pipeline/skills/run/stages/3-write-plan.md \
  plugins/dev-pipeline/skills/pipeline-retro/SKILL.md
```

## Risks / rollback notes

- **Lockstep drift** is the standing risk of this design: five files restate the enum as a string literal and nothing mechanically enforces agreement. This change does not fix that (out of scope) — it moves all of them together and relies on the `<!-- mirror ... keep verbatim -->` markers. The AC-3 grep above is the manual guard.
- **Widened trust surface.** `ticket-sourced` lets a ticket comment become a lint-blessed design decision inside an autonomous run, where previously user-provenance required a local file a human wrote. Mitigations: the mandatory URL citation makes every such row auditable, the `author_association` rule (D-3) excludes drive-by commenters, and the always-draft PR posture keeps a human review hop before merge. The residual risk is a maintainer-authored comment being over-read by a run — visible in the cited row at review time.
- **Rollback** is a clean revert: the change is additive (one enum value, one lint check, doc text). Reverting restores the four-value enum; any plan already carrying a `ticket-sourced` row would then fail lint, which is the correct loud failure.

## Out-of-scope

- Option 2 — Stage-1 materialization of a pre-flight ledger from a comment.
- Mechanically enforcing lockstep across the mirror set (e.g. generating the mirrors from the canonical block, as `gen-statectl-validators.sh` does for statectl's enums). Worth a follow-up; not this ticket.
- Teaching `intake-interviewer`'s ledger-seed emission to produce `ticket-sourced` rows — that path interviews a live human, so `user-answered` / `user-delegated` remain correct there.
- Any version bump or `CHANGELOG.md` entry (release-derived; frozen in feature PRs).
