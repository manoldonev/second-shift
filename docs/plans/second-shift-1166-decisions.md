# Decision record — #1166 A directory-installed second-shift hands off to the marketplace copy

Receipt: v4

## Summary

A `second-shift` record from another marketplace, such as `second-shift@claude-plugins-official`, becomes visible to onboard and doctor. scope-shadows.sh reports it, onboard's hand-off prints its uninstall line, and doctor WARNs on it. With only the directory copy installed, doctor's existing FAIL tells the user to install the marketplace copy at user scope first, then uninstall the directory copy.

Open regions: none.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where onboard and doctor detect the directory copy | scope-shadows.sh gains a row kind for a `second-shift` record from another marketplace, carrying that marketplace and the record's scope. Onboard Step 8 and doctor both print the uninstall line from that row. The exit status keeps its meaning, so local-dev-refresh Step 4 is unaffected. | user-answered | intent |
| D-2 | Doctor when only the directory copy is installed | No separate WARN. The existing NOT-installed FAIL for `second-shift` names the D-3 install first, then the directory copy's uninstall. The WARN fires only while the marketplace copy is served (D-7). | user-answered | intent |
| D-3 | Install scope of the marketplace copy for a directory user | User scope, as the README's hand setup does: `claude plugin marketplace add manoldonev/second-shift`, then `claude plugin install second-shift@second-shift`. This applies to `second-shift` only when a directory record is present. Other plugins keep `--scope project`. | user-answered | intent |
| D-4 | A disabled directory record | It counts. A record with `enabled: false` still gets the WARN, because it is still installed. | user-answered | intent |
| D-5 | Scope on the uninstall line | `claude plugin uninstall second-shift@<marketplace> --scope <the record's scope>`. A project-scope record's line also carries doctor's committed-settings CAUTION — run: `claude plugin uninstall --help` → `Uninstall from scope: user, project, or local (default: "user")`; cited (convention): plugins/second-shift/skills/doctor/tools/doctor.sh:283 | codebase-derived | fact |
| D-6 | Which directory records count | Records that load at this repo: user, local, or project scope with `projectPath` equal to the repo root. This is the `RESOLVE_RECORD` filter. A project uninstall run here cannot remove another repo's record — run: `grep -n 'RESOLVE_RECORD=' plugins/second-shift/skills/doctor/tools/doctor.sh` → `223: ... (.projectPath // "") == $root or .scope=="user" or .scope=="local"` | codebase-derived | fact |
| D-7 | When the marketplace copy counts as served | When `RESOLVE_RECORD` returns a `second-shift@second-shift` record for this root. A version-drifted record is served and keeps its own drift FAIL — run: `grep -n 'RESOLVE_RECORD=' plugins/second-shift/skills/doctor/tools/doctor.sh` → `223: RESOLVE_RECORD='[.[] \| select(.id==$id and ...` | codebase-derived | fact |
| D-8 | Placement of onboard's uninstall line | Always after the Step 8 line for `second-shift`: its install line, or its "served at user scope" line. The trigger is the directory record, not the install line. | user-answered | intent |
| D-9 | The marketplace the record is compared against | `$MKT`, which is `second-shift` in both scripts. Any other marketplace suffix is a directory copy — run: `grep -n 'MKT="second-shift"' plugins/second-shift/skills/doctor/tools/doctor.sh plugins/second-shift/skills/doctor/tools/scope-shadows.sh` → `doctor.sh:32`, `scope-shadows.sh:29` | codebase-derived | fact |

Options weighed:
- D-1: a shared helper row in scope-shadows.sh, or a prompt-only onboard change with doctor-only tests. The operator chose the shared helper.
- D-2: an ordered fix on the existing FAIL, a WARN beside the FAIL, or a second FAIL. The operator chose the ordered fix.
- D-3: user scope as in the README, project scope as Step 8 prints, or the directory record's own scope. The operator chose user scope.
- D-4: every record, or enabled records only. The operator chose every record.
- D-8: always after the `second-shift` line, or only after an install line. The operator chose always.

## Open Regions

No open regions. Every decision in scope is settled.

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: scope-shadows.sh emits a row naming `second-shift`, the marketplace `claude-plugins-official` and the record's scope, with or without `second-shift@second-shift` beside it
AC-2: doctor exits 0 with a WARN carrying `claude plugin uninstall second-shift@claude-plugins-official --scope user` while `second-shift@second-shift` is served, and exits 1 with the ordered install-then-uninstall fix when only the directory copy is installed
AC-3: a plugin-list fixture holding a `second-shift@claude-plugins-official` record drives the new scope-shadows-selftest.sh and doctor-selftest.sh cases, and each case fails on the unchanged scripts

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Onboard hand-off, directory copy only | decided (D-3) |
| S-2 | Onboard hand-off, both copies installed | decided (D-8) |
| S-3 | Doctor output, both copies installed | decided (D-1) |
| S-4 | Doctor output, directory copy only | decided (D-2) |
| S-5 | Doctor output, project-scope directory record | decided (D-5) |
| S-6 | Doctor output, disabled directory record | decided (D-4) |
| S-7 | Doctor output, another repo's project-scope directory record | decided (D-6) |
| S-8 | SessionStart thin check, directory copy only | out-of-scope — its generic line already points to `/second-shift:doctor`, which carries the D-2 fix. |
| S-9 | doctor `--report` bundle | out-of-scope — it already dumps the raw plugin list, directory record included. |
| S-10 | local-dev-refresh Step 4 | out-of-scope — it reads only the scope-shadows exit status, which D-1 leaves unchanged. |
| S-11 | README and docs install text | out-of-scope — the directory listing is the entry point, and the hand-off carries the steps. |

## Checks

- `bash plugins/second-shift/skills/doctor/tools/scope-shadows-selftest.sh`
- `bash plugins/second-shift/skills/doctor/tools/doctor-selftest.sh`

## Intake steps

Requirements: the ticket body as written. spec-reviewer: two blockers and four gaps. The interview settled the blockers, and the code settled the gaps. The implementability probe raised seven guess-points, settled by D-1 to D-9.

Split: not split. The ticket has no epic label, and its one deliverable fits one PR.

Explore: done. Read doctor.sh, scope-shadows.sh, doctor-selftest.sh, onboard Step 6 and Step 8, the thin check and local-dev-refresh Step 4.

Fan-out: ran — 28 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no post-merge AC

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: cli-record-semantics opus 6/6 · every-reader-of-the-id fable 6/6 · bootstrap-session-lifecycle opus 5/6 · test-surface-and-verdict-rule fable 6/6 · premortem fable 5/6
Tally: rows added 2 · snapshot claims overturned 0 · questions added 1

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | cli-record-semantics | A plugin-list record has no marketplace field, so the marketplace comes from the id suffix (`claude plugin list --json`). | not material | not material — the id suffix is the obvious seam |
| F-2 | cli-record-semantics | A bare `claude plugin uninstall` removes only the user-scope record (`claude plugin uninstall --help`). | already-had | became D-5 |
| F-3 | cli-record-semantics | A bare uninstall of a project-only record fails with rc=1 (sandbox probe). | new | became D-5 |
| F-4 | cli-record-semantics | A project-scope uninstall rewrites the committed settings, as doctor's CAUTION says (`doctor.sh:283`). | already-had | became D-5 |
| F-5 | cli-record-semantics | Both copies coexist, and uninstalling the directory id leaves `second-shift@second-shift` intact (sandbox probe). | new | not material — confirms the ticket's premise, no choice |
| F-6 | cli-record-semantics | Uninstall deletes data keyed `<name>-<marketplace>`, so the pinned copy's data survives (`claude plugin uninstall --help`). | new | not material — the pinned copy's data is untouched |
| F-7 | every-reader-of-the-id | Doctor's per-plugin loop resolves only `<name>@second-shift`, so a directory record is invisible (`doctor.sh:234-246`). | already-had | became D-2 |
| F-8 | every-reader-of-the-id | scope-shadows.sh drops every record without the `@second-shift` suffix before classifying (`scope-shadows.sh:69`). | already-had | became D-1 |
| F-9 | every-reader-of-the-id | The SessionStart thin check reads only the `second-shift` cache dir (`second-shift-doctor.sh:8`). | already-had | out of scope as S-8 |
| F-10 | every-reader-of-the-id | `doctor --report` dumps the raw plugin list, and every other doctor reader keys on `@$MKT` (`doctor.sh:120`). | new | not material — out of scope as S-9 |
| F-11 | every-reader-of-the-id | The opt-out scan and local-dev-refresh both ignore other marketplaces by design (`doctor.sh:358`). | new | not material — out of scope as S-10 |
| F-12 | every-reader-of-the-id | Every hand-off text hardcodes `@second-shift`, and which record scopes trigger AC-1 is open (`onboard/SKILL.md:390`). | new | became D-6 |
| F-13 | bootstrap-session-lifecycle | Onboard run from the directory copy uses that copy's tools and templates (`onboard/SKILL.md:339`). | new | not material — a hand setup runs unpinned files too |
| F-14 | bootstrap-session-lifecycle | Onboard Step 8's helper sees no directory record and prints a project install (`scope-shadows.sh:67`). | already-had | became D-1 |
| F-15 | bootstrap-session-lifecycle | With only the directory copy, doctor FAILs and never names it (`doctor.sh:241`). | already-had | became D-2 |
| F-16 | bootstrap-session-lifecycle | The bare uninstall line works only for a user-scope record (`claude plugin uninstall --help`). | already-had | became D-5 |
| F-17 | bootstrap-session-lifecycle | An uninstalled copy's files stay on disk until restart, so the session keeps running (`.orphaned_at` marker). | new | not material — Step 8 already states the restart |
| F-18 | test-surface-and-verdict-rule | Onboard's hand-off is prose with no script emitter (`onboard/SKILL.md:390-398`). | already-had | became D-1 |
| F-19 | test-surface-and-verdict-rule | Doctor FAILs on the directory copy alone and goes green beside the marketplace copy (`doctor.sh:234-246`). | already-had | became D-2 |
| F-20 | test-surface-and-verdict-rule | A WARN never moves the exit code, and `shadowed-warn-only` is the rc-0 case pattern (`doctor-selftest.sh:177`). | new | shaped the AC-2 Test intent line |
| F-21 | test-surface-and-verdict-rule | "Served from the marketplace" is exactly `RESOLVE_RECORD` returning `second-shift@second-shift` (`doctor.sh:223-226`). | new | became D-7 |
| F-22 | test-surface-and-verdict-rule | The doctor cases need a fixture with the directory record, with and without the marketplace copy (`doctor-fixtures/`). | new | shaped the AC-3 Test intent line |
| F-23 | test-surface-and-verdict-rule | The onboard case's script is undecided: extend scope-shadows.sh or add an onboard tool (`scope-shadows-selftest.sh:17`). | already-had | became D-1 |
| F-24 | premortem | Following the project install, then the uninstall, leaves second-shift usable in one repo only (`README.md:46`). | new | became D-3 |
| F-25 | premortem | Doctor is silent on the directory copy beside the marketplace copy (`doctor.sh:234-246`). | already-had | became D-6 |
| F-26 | premortem | Committed templates come from the unpinned directory copy, and no check compares them (`onboard/SKILL.md:339`). | new | not material — a hand setup runs unpinned files too |
| F-27 | premortem | AC-3's onboard case has nothing to drive but a SKILL.md grep (`docs/testing.md:471`). | already-had | became D-1 |
| F-28 | premortem | The install scope for a directory user is undecided: user per README or project per Step 8 (`README.md:46`). | new | became D-3 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Where onboard's directory-copy detection lives | OPEN — shared helper beside scope-shadows.sh, called by onboard Step 8 and doctor (recommended: scope-shadows.sh exists for exactly this sharing), vs a prompt-only onboard change |
    | D-2 | Doctor behavior when only the directory copy is installed | OPEN — WARN beside the existing FAIL, suppress until the marketplace copy is in, or FAIL |
    | D-3 | Scope on the uninstall line | `--scope <record scope>`; uninstall defaults to user — run: `claude plugin uninstall --help` → default "user" |
    | D-4 | Project-scope directory record caveat | the uninstall line carries doctor's committed-settings CAUTION, as the shadowed WARN does (doctor.sh:288) |
    | D-5 | One WARN per record | one per record, doctor's per-row precedent (doctor.sh:285-289) |
    | D-6 | Disabled directory record | OPEN — still a copy left behind; recommend it counts |
    | D-7 | Directory record version | a commit sha, never semver-compared — run: `claude plugin list --json` → atlassian@claude-plugins-official b74220d41142 |
    | D-8 | Onboard placement | Step 8 item 2, after second-shift's install line or its "served at user scope" line |
    | D-9 | Doctor tests | new rows in doctor-selftest.sh's scenario table with a plugin-list fixture carrying second-shift@claude-plugins-official |
    | D-10 | SessionStart thin check | unchanged; it reads only the second-shift cache dir, so a directory-only user already reads as missing |

</details>
