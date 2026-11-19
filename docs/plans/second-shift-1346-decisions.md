# Decision record — #1346 A record for a caller-facing surface does not have to state its request and response shapes

Receipt: v4

## Summary

The Surface Inventory gets a third disposition, `contract (D-n)`, for an interface that other code calls or parses. The row it cites must state `Inputs:`, `Outputs:` and `Errors:`, and the lint checks that the labels are there. The lint also checks that a `cited (convention|adr)` path in that row exists in the repo. The definition of a surface widens to name these interfaces, and split.md gets one clarifying sentence.

Open regions: OR-1, the shape sentences do not count toward the 40-word cell guide. OR-2, the path check skips `cited (kb)`.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How a caller-facing surface is marked | A third Surface Inventory disposition, `contract (D-n)`. It marks the surface caller-facing and cites the D-n row that holds its shape. `decided` and `out-of-scope` stay unchanged. The table keeps three columns. | user-answered | intent |
| D-2 | What a contract's row must contain, and what the lint checks | The cited D-n Resolution carries an `Inputs:`, an `Outputs:` and an `Errors:` sentence. Each may read `none — <reason>`. The lint refuses a contract row whose cited row lacks one of the three labels. The lint refuses a contract row that cites an `open` row. | user-answered | intent |
| D-3 | Which surfaces count as caller-facing | Any interface that code outside the change calls or parses. This covers an HTTP endpoint, an SDK or library method, an event or message, a CLI or script interface (args, flags, exit codes) and machine-read output. The rule text names each kind. | user-answered | intent |
| D-4 | The empty form `No user-visible surface — this change renders nothing a user reads.` | The literal stays byte-identical. The rule text says the empty form is wrong when the change adds a caller-facing interface. The lint cannot detect that misuse. The writer's own marking stays a known limit. | user-answered | intent |
| D-5 | How "mirror X" resolves inside the repo | For a row that a contract surface cites, the lint checks that each `cited (convention\|adr)` path exists in the repo. A missing path is a violation. The path is the text before the `:line` suffix, relative to the repo root. | user-answered | intent |
| D-6 | split.md's quarantine of endpoints and field names | Add one sentence to split.md Step 1. The quarantine decides only whether the ticket author may dictate a shape. A caller-facing interface still gets a `contract` row, decided in the Interview. | user-answered | intent |
| D-7 | Where the shape must live to bind the build | In the cited D-n row, never in the S-n row. The build prompt treats only D-n rows as binding. run: `grep -c "Only the D-n rows bind" plugins/dev-pipeline/skills/run/run.sh` → 1 | codebase-derived | fact |
| D-8 | Which provenance counts as AC-2's human decider | `user-answered`, `user-delegated` and `ticket-sourced`. The Kind table already lists these three as intent provenance, so no new rule is needed. cited (convention): plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md:88 | codebase-derived | fact |
| D-9 | Receipt version | No version bump. The version table maps mandated sections. `contract` adds a disposition value, not a section, and older receipts never use it. cited (convention): plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md:394 | codebase-derived | fact |
| D-10 | Evidence form for a shape that a repo convention fixes | The existing Evidence rule applies: `run:` where a command can check the shape, else `cited (convention\|adr)`. AC-2's `cited (convention)` pointer is one of these forms. cited (convention): plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md:106 | codebase-derived | fact |
| D-11 | Files that carry the surface definition | interviewing-baseline SKILL.md (canonical) and plan-interview SKILL.md step 3, plus receipt.md's Surface Inventory and "Lint it" bullets and interview.md's Exit. run: `git grep -l "user or operator ends up looking at"` → plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md, plugins/intake-toolkit/skills/plan-interview/SKILL.md | codebase-derived | fact |
| D-12 | How the lint finds the repo root for the path check | From the receipt's own directory, through the git common dir. The config lookup already does this. run: `grep -n "rev-parse --path-format=absolute --git-common-dir" plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh` → 222 | codebase-derived | fact |
| D-13 | Where the new lint cases go | A block right after the surface-inventory block of ledger-lint-selftest.sh, through a `ct_lint` helper that calls `receipt_with`. Changed in build: `surface_receipt` fixes the ledger rows and writes outside a git checkout, and each contract case needs its own cited row and a receipt inside a git repo. | user-delegated | intent |
| D-14 | A contract's cited path that cannot resolve inside the repo | A violation, never a skip. An absolute path, a path with a `..` segment, and a receipt outside any git checkout each fail the lint with a named reason. Added in build: D-5 does not say what the check does when it cannot place a path in the repo, and a silent pass would reopen the out-of-repo route. | user-delegated | intent |

Options weighed:

- D-1: a 4th column with a v5 bump, a suffix after `decided (D-n)`, or a new disposition value. The operator chose the new value.
- D-3: AC-1's three kinds only, cross-service only, or any interface that other code calls or parses. The operator chose the widest.
- D-4: a new empty-form wording accepted beside the old one, or the old wording kept. The operator chose to keep it.
- D-5: rule text only, or a lint path check. The operator chose the path check.
- D-6: leave split.md alone, or add one sentence. The operator chose the sentence.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Word count of the `Inputs:` / `Outputs:` / `Errors:` sentences | reversible-default-and-flag |
| OR-2 | `cited (kb)` evidence in a contract's row | reversible-default-and-flag |

OR-1 default: the shape sentences do not count toward the 40-word cell guide, as evidence does not. The agent chose it. Reversing it is one sentence in receipt.md and the baseline.

OR-2 default: the path check skips `cited (kb)`, because a knowledge-base page is not a repo path. The agent chose it. Reversing it adds one refusal to the lint.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4

AC-1: a receipt whose contract row cites a D-n that lacks an `Inputs:`, `Outputs:` or `Errors:` sentence fails the lint
AC-2: a receipt whose contract row cites an `open` D-n row fails the lint
AC-3: a receipt whose contract row cites a D-n with a `cited (convention)` path that does not exist in the repo fails the lint
AC-4: a receipt with a contract row whose cited row carries all three labels and an existing path lints clean, with no new section

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Lint violation for a contract row missing a label | decided (D-2) |
| S-2 | Lint violation for a contract row citing an open row | decided (D-2) |
| S-3 | Lint violation for a cited path missing from the repo | decided (D-5) |
| S-4 | Surface definition text in the skill files | decided (D-3) |
| S-5 | The empty-form line and its rule text | decided (D-4) |
| S-6 | The split.md quarantine sentence | decided (D-6) |
| S-7 | Existing receipts and records with no contract row | decided (D-9) |

## Checks

- `bash plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh`

## Intake steps

Requirements: the ticket body as written. spec-reviewer found two blockers, the surface definition and the marker. The Interview resolved both.

Split: not triggered. No epic label and one deliverable.

Explore: done. Read the lint's surface check and selftest, the baseline contract, receipt.md, interview.md, split.md and run.sh's binding rule.

Fan-out: ran — 24 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC. A selftest proves each of the four ACs.

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: lint-and-receipt-versioning opus 4/6 · quarantine-versus-contract fable 5/6 · downstream-record-readers opus 5/6 · cold-implementability-walkthrough fable 5/6 · premortem fable 5/6
Tally: rows added 8 · snapshot claims overturned 1 · questions added 3

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | lint-and-receipt-versioning | A marker fits only in the Surface cell or after the disposition token; a 4th column fails arity (`ledger-lint.sh:534-536`). | new | became D-1 |
| F-2 | lint-and-receipt-versioning | A `decided` cell checks only its first D-n citation (`ledger-lint.sh:558`). | not material | not material — a contract row cites one D-n |
| F-3 | lint-and-receipt-versioning | A row with an id like `S-4c` is never read by the lint (`ledger-lint.sh:584`). | not material | not material — pre-existing id grammar gap, named to the operator |
| F-4 | lint-and-receipt-versioning | A caller-facing row scoped out as "mirror the public API create" lints clean (`ledger-lint.sh:569-572`). | new | became D-1 |
| F-5 | quarantine-versus-contract | split.md quarantines endpoints while plan-interview calls them material (`split.md:72-73`). | already-had | became D-6 |
| F-6 | quarantine-versus-contract | An author-dictated shape can enter unverified by three routes (`split.md:57-59`). | not material | not material — pre-existing, outside this ticket, named |
| F-7 | quarantine-versus-contract | A `cited (convention)` path outside the repo passes the lint (`ledger-lint.sh:256-266`). | new | became D-5 |
| F-8 | quarantine-versus-contract | A bare "mirror X" row lints green; one full shape took 69 words (`receipt.md:143-146`). | new | became OR-1 |
| F-9 | quarantine-versus-contract | The surface definition and empty form exclude a callee-only endpoint (`interviewing-baseline/SKILL.md:183`). | already-had | became D-3 and D-4 |
| F-10 | downstream-record-readers | The build treats only D-n rows as binding (`run.sh:1128`). | new | became D-7 |
| F-11 | downstream-record-readers | verdict-check.sh scores only D-n rows (`verdict-check.sh:43`). | new | became D-7 |
| F-12 | downstream-record-readers | An unescaped pipe in a build-edited row is never re-linted (`run.sh:1778-1779`). | not material | not material — pre-existing, named to the operator |
| F-13 | downstream-record-readers | scope-completeness-reviewer scores only intent rows (`scope-completeness-reviewer.md:102`). | not material | not material — pre-existing, named to the operator |
| F-14 | downstream-record-readers | The plain review cannot read the record (`plain-review.sh:2-3`). | not material | not material — by design |
| F-15 | cold-implementability-walkthrough | #1204's record left a tool's flag and exit codes undecided and linted clean (`docs/plans/second-shift-1204-decisions.md`). | new | became D-3 |
| F-16 | cold-implementability-walkthrough | `user-delegated` already satisfies intent provenance (`ledger-lint.sh:181`). | new | became D-8 |
| F-17 | cold-implementability-walkthrough | No inventory row in this repo is HTTP or SDK; caller surfaces are flags, exit codes, outputs (`docs/plans`). | overturned (snapshot: "HTTP, SDK method and event field sets") | became D-3 |
| F-18 | cold-implementability-walkthrough | One existing record cites a `cited (convention)` path missing at HEAD (`ledger-lint.sh:266`). | new | became D-5 |
| F-19 | cold-implementability-walkthrough | No intake step reads the finished record cold (`receipt.md:57-58`). | not material | not material — #1344 owns the probe input |
| F-20 | premortem | The writer may never apply the mark, and the empty form passes (`interviewing-baseline/SKILL.md:194-197`). | new | became D-4, as a stated limit |
| F-21 | premortem | A marked surface can pass on "mirror X" plus an out-of-repo pointer (`ledger-lint.sh:266`). | new | became D-5 |
| F-22 | premortem | A caller-facing row can cite an open row and lint clean (`ledger-lint.sh:565-571`). | new | became D-2 |
| F-23 | premortem | A shape outside a D row does not bind; inside one it meets the 40-word guide (`receipt.md:145-148`). | already-had | became D-2 and OR-1 |
| F-24 | premortem | A version-gated rule is waived by a lower declared version (`run.sh:1788`). | new | became D-9 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Definition of a surface | Widen it to contracts that other code calls. The empty form must not apply when the change adds one. Open: ask. |
    | D-2 | How a surface is marked caller-facing | Recommend a third disposition value `contract (D-n)`. It is additive, so no column change and no receipt version bump. Open: ask. |
    | D-3 | Where the shape text lives | Recommend labeled `Inputs:` / `Outputs:` / `Errors:` sentences in the cited D-n row, exempt from the 40-word cap. Open: ask. |
    | D-4 | Required fields per kind | HTTP: method, route, inputs, outputs, status codes. SDK method: inputs, return, errors thrown. Event: name, payload. Open: ask. |
    | D-5 | Who counts as another caller | Code across a process or package boundary: another service, a frontend, an SDK consumer. Open: ask. |
    | D-6 | Evidence form for a convention-fixed shape | `run:` where runnable, else `cited (convention)`, in this repo. The Evidence contract already says so. Fact. |
    | D-7 | "Mirror X" enforcement | Prose in interview.md and receipt.md, no lint grep. Open: ask. |
    | D-8 | split.md quarantine rule | Unchanged. It governs what a ticket author may dictate. Open: confirm as scope boundary. |
    | D-9 | Verification of AC-1 to AC-3 | AC-4 gets lint fixtures. AC-1 to AC-3 are prose; no prose-presence guards (docs/testing.md). Open: exempt or PM-n. |
    | D-10 | Sites that carry the definition | interviewing-baseline SKILL.md (canonical), receipt.md, interview.md, plan-interview SKILL.md step 3, ledger-lint.sh header and check D. Fact. |

</details>
