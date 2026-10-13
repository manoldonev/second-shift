# Intake receipt — #1032 intake-toolkit: intake consults a consumer-declared knowledge source

Receipt: v2

## Intake steps

Requirements: the ticket body as written (parent #1017) — spec-reviewer: needs-revision, 2 blockers (pre-#1028 wiring) re-pointed in the slice body, 5 gaps resolved from the code, 7 questions carried to the Interview
Split: split into #1032, #1033 (sequential) — this receipt is #1032's
Explore: done — the receipt lint and its fixtures, the /intake stage files, run.sh's record embed and section reader, verdict-check, the review-context section lint and catalog, the extension manifest, the fan-out script's args and agent tools
Fan-out: ran once for the #1017 split — 18 items touch this slice, see Fan-out
Dup-scan: no candidates at or above threshold 12
Post-merge scan: no post-merge AC in #1032 (PM-1 lives in #1033)
Sizing: opus

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which /intake stage dispatches the provider | Requirements' last act, once the ticket body exists (its title and ACs fill the question), before Split, codebase-explorer, the fan-out and any Interview question; on a rough input it follows Requirements' own interview. Once per intake: a new row in the gates table of `intake/SKILL.md`. On a split it runs on the parent before Split, and every slice receipt carries the whole answer. A stop-and-restart dispatches it again (no file carries it across). | user-answered | intent |
| D-2 | OR-2: section-lint ownership and reader tokens | Extend review-toolkit's `check-review-context-sections.sh` and `section-catalog.txt`: `intake-context.md` becomes a second target, and the catalog gains a declared set of non-reviewer reader tokens that `reader_effective` knows, so a missing section reports its real reader instead of being dropped silently. This slice adds the token for the /intake session; #1033 adds the one for review-lead's lead pass, which writes the sink block. Doctor's existing `--report` call then covers the new file. | user-answered | intent |
| D-3 | What a failed dispatch records | `Knowledge source: failed — <the first line of the tool's error>`: an unresolved agent type's error continues with every installed agent's name, which must not reach a committed receipt. A declared section that is malformed (no `Provider:` line, or two) is not dispatched and records `Knowledge source: failed — <what is malformed>`; intake continues either way. | user-answered | intent |
| D-4 | How the answer reaches the build | `run.sh`'s build prompt, which embeds the whole record under "They are binding", says that `## Knowledge source` and `## Fan-out` are context, not binding; a `run-selftest.sh` case fails without the sentence. | user-answered | intent |
| D-5 | May the operator skip the dispatch | No skip form. A consumer opts out by declaring no section (`Knowledge source: none declared`). | user-answered | intent |
| D-6 | A `Knowledge source:` key in `## Intake steps` | No key: the mandated section records the outcome; `INTAKE_STEP_KEYS` is unchanged. | user-answered | intent |
| D-7 | A provider answer that contradicts the code | Asked, never a silent pick (AC-6). The fact's row says which side this ticket follows and carries a fixed marker naming the page and which side is behind: `kb-conflict: <kb-page> (kb stale)` (the page is out of date) or `kb-conflict: <kb-page> (kb ahead)` (the page states a direction the code has not reached). The interviewing-baseline and the Interview stage state the marker; #1033's review reads it. | user-answered | intent |
| D-8 | Embedding the provider's answer in the receipt | A `Provider: <plugin>:<agent>` line naming who answered, then the whole answer indented four spaces, as the Fan-out snapshot is. | user-answered | intent |
| D-9 | What the lint accepts in `## Knowledge source` (AC-13) | Exactly one of: the `Provider:` line followed by a non-empty answer indented four spaces; `Knowledge source: none declared`; `Knowledge source: failed — <text>`. A violation: an empty section, any other unindented line in it, a `Knowledge source:` line outside those two forms. `Sources:` is not required: the answer stays opaque. | user-answered | intent |
| D-10 | What a consumer writes in intake-context.md's `## Knowledge source` | Two key lines: `Provider: <plugin>:<agent>` (the namespaced agent type) and `Question: <text>`, free text that may use the placeholders `{title}` and `{acceptance-criteria}`. | user-answered | intent |
| D-11 | OR-1: who in the fan-out sees the answer | A new `intake-fanout.mjs` argument threaded only into the lens writer's prompt; the lenses and refuters stay blind to it and check against code. A cross-plugin edit to review-toolkit. | user-answered | intent |
| D-12 | An onboard scaffold for intake-context.md | None: `docs/extension-points.md` carries a placeholder example (AC-12); onboard is unchanged. | user-answered | intent |
| D-13 | Receipt version of the new section | `Knowledge source` is mandated from v3, a new row in the `receipt-versions` LOCKSTEP table in `ledger-lint.sh` and `interviewing-baseline` — run: `bash plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh --receipt-version` → 2 | codebase-derived | fact |
| D-14 | v2 literals the bump must review outside the lockstep | run: `grep -rlE '^Receipt: v2\|receipt is v2' plugins` → run-selftest.sh, intake/receipt.md, interviewing-baseline/SKILL.md, ledger-lint-fixtures/valid-receipt.md | codebase-derived | fact |
| D-15 | Where the cited-reason enum lives | One code site plus prose mirrors (interviewing-baseline's codebase-derived definition and "Evidence", intake/receipt.md "Lint it"), none lockstep-checked — run: `grep -n "^CITED_REASON_ENUM" plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh` → 229:CITED_REASON_ENUM='convention\|adr' | codebase-derived | fact |
| D-16 | Who can dispatch the provider | The interactive /intake session: the fan-out's lens writer, lenses and refuter carry no Agent tool — run: `grep -h '^tools:' plugins/review-toolkit/agents/intake-lens.md plugins/review-toolkit/agents/intake-lens-writer.md plugins/review-toolkit/agents/intake-refuter.md` → tools: Read, Grep, Glob, Bash (×3) | codebase-derived | fact |
| D-17 | An existing intake-side extension loader | None: intake-context.md is the first file intake-toolkit reads under .claude/second-shift — run: `grep -rn '\.claude/second-shift/' plugins/intake-toolkit \| grep -vc selftest` → 0 | codebase-derived | fact |
| D-18 | Dispatch sad paths D-3 does not name | A `Question:` line missing or doubled is malformed like a `Provider:` one (D-10 makes both key lines required): not dispatched, `failed — <what is malformed>`. An empty answer records `failed — the provider returned an empty answer` (D-9's provider form needs a non-empty answer); a session with no Agent tool records `failed — Agent tool unavailable in this session`. Reason: each is a failure D-3's form already covers, named so the build does not guess. | user-delegated | intent |
| D-19 | How the catalog names a section's file and a non-reviewer reader (D-2's shape) | An optional fourth catalog column names the file (`review-context.md` when absent, or `intake-context.md`); a non-reviewer reader is declared on a `reader: <token> \| <what reads it>` line, and this slice's token is `intake`. A target's sections count toward coverage only when its file exists, so a repo with no intake-context.md is not reported degraded. Reason: keeps every existing row and the review-context lockstep unchanged; #1033 adds its token as one more `reader:` line. | user-delegated | intent |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Receipt `## Knowledge source` carrying the provider's answer | decided (D-8) |
| S-2 | Receipt `## Knowledge source` with no provider declared | decided (D-9) |
| S-3 | Receipt `## Knowledge source` after a failed or malformed dispatch | decided (D-3) |
| S-4 | The consumer authoring intake-context.md from the docs example | decided (D-10) |
| S-5 | Doctor's output for intake-context.md (manifest and section report) | decided (D-2) |
| S-6 | The build prompt's framing of the record | decided (D-4) |
| S-7 | The operator's conflict question when the answer contradicts the code | decided (D-7) |
| S-8 | The fan-out lens writer's prompt | decided (D-11) |
| S-9 | Onboarding | decided (D-12) |
| S-10 | Receipt `## Knowledge source` after a malformed `Question:` line, an empty answer or no Agent tool | decided (D-18) |

## Checks

- `bash scripts/check-lockstep-pairs.sh`

## Fan-out

Run: shared with the #1017 split — slices #1032, #1033
Refuter: cross (opus/fable alternating)
Lenses: receipt-embedding-parsers opus 4/6 · intake-stage-sequencing fable 4/6 · dispatch-runtime-trust opus 5/6 · evidence-provenance-readers fable 2/6 · premortem fable 5/6
Tally: rows added 3 · snapshot claims overturned 0 · questions added 2

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | receipt-embedding-parsers | ledger-lint reads ledger, region and surface rows from the whole file; an unindented answer's rows count as the receipt's (`ledger-lint.sh:376`) | already-had | became D-8 |
| F-2 | receipt-embedding-parsers | An unindented `Receipt:` line in the answer makes run.sh refuse with the wrong cause (`run.sh:430-432`, `:1049`) | already-had | became D-8 |
| F-3 | receipt-embedding-parsers | Any unindented heading in the answer cuts the section for every reader (`run.sh:396`, `ledger-lint.sh:186`) | already-had | became D-8 |
| F-4 | receipt-embedding-parsers | The v3 bump touches v2 literals and enum mirrors no lockstep holds | new | became D-14, D-15 |
| F-5 | intake-stage-sequencing | "Before the first question" has no single stage position (`requirements.md:3-5`, `explore.md:10-13`) | already-had | became D-1 |
| F-6 | intake-stage-sequencing | On a split, each slice receipt carries the section, as with Fan-out (`receipt.md:114-120`) | already-had | became D-1 |
| F-7 | intake-stage-sequencing | A return to Split re-feeds issueBody; a restart has no carrier for the answer (`SKILL.md:56-67,85-92`) | new | became D-1 |
| F-8 | intake-stage-sequencing | A skip has no slot at Explore and the lint's skip grammar is Fan-out-only (`ledger-lint.sh:170-171`) | already-had | became D-5 |
| F-9 | dispatch-runtime-trust | An unresolved agent type's error lists every installed agent, so a verbatim error leaks the inventory | new | became D-3 |
| F-11 | dispatch-runtime-trust | The build prompt embeds the whole record as binding (`run.sh:644-645`) | new | became D-4 |
| F-12 | dispatch-runtime-trust | verdict-check and the lint read unindented `\| D-n \|` rows anywhere in the record (`verdict-check.sh:23-24`) | already-had | became D-8 |
| F-13 | dispatch-runtime-trust | Fan-out agents carry no Agent tool and the script has no slot for the answer (`intake-fanout.mjs:61`) | new | became D-16, D-11 |
| F-14 | evidence-provenance-readers | The lint checks a cited source's form, never that it exists (`ledger-lint.sh:238-254`) | not material | not material — the ticket states the lint checks the form only; the verbatim Sources list is the trail |
| F-15 | evidence-provenance-readers | An Intake-steps key outside the closed list is silently ignored (`ledger-lint.sh:171`) | already-had | became D-6 |
| F-16 | premortem | An unindented answer fails the lint four ways or leaks into verdict scoring | already-had | became D-8 |
| F-17 | premortem | The four-space indent keeps the answer out of every column-0 scan and whole for section_of | already-had | became D-8 |
| F-19 | premortem | A non-reviewer reader token in the catalog is dropped silently from the degraded-readers report (`check-review-context-sections.sh:216-220`) | new | became D-2 |
| F-20 | premortem | intake-context.md on a pin older than the manifest row fails doctor closed | not material | not material — every new extension file lands this way; the manifest row ships in the same release |

### Snapshot

    | ID | Slice | Decision | Resolution (pre-pool) |
    | --- | --- | --- | --- |
    | D-1 | #1032 | Which /intake stage dispatches the provider | open — lean: Requirements' last act, once the ticket body exists, before Split, codebase-explorer, the fan-out and any Interview question |
    | D-2 | #1032 | May the operator skip the dispatch | open — lean: no skip form; the consumer's opt-out is `none declared` |
    | D-3 | #1032 | Embedding the verbatim answer | indent four spaces, as the Fan-out snapshot is |
    | D-4 | #1032 | `Knowledge source:` key in `## Intake steps` | open — lean: no new key |
    | D-5 | #1032 | Split rule | one dispatch per intake, on the parent before Split; each slice receipt carries the whole answer |
    | D-6 | #1032 | OR-1 order vs the lens writer | follows D-1: the answer exists before Explore, handed to the fan-out in its issueBody |
    | D-7 | #1032 | OR-2 section-lint ownership | open, pause-and-ask |
    | D-8 | #1032 | Receipt version | `Knowledge source` is a v3 row (current max v2) |
    | D-9 | #1032 | `kb` cited reason sites | ledger-lint.sh CITED_REASON_ENUM + messages; interviewing-baseline; intake/receipt.md |
    | D-10 | #1032 | First intake-side extension file | intake-toolkit reads nothing under .claude/second-shift today |
    | D-11 | #1032 | Provider name form | namespaced `<plugin>:<agent>`, read from the consumer's section |
    | D-12 | #1033 | Manual /dev-pipeline:review emits the contributions line | open — lean: yes, parity with run.sh's prompt |
    | D-13 | #1033 | Sink section's catalog reader token | depends on OR-2 |
    | D-14 | #1033 | OR-3 standalone review-lead | default as stated |
    | D-15 | #1033 | Record with no answer (none/failed/older receipt) | change gaps only |
