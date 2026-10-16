# Decision record — #1068 dev-pipeline: the bot-id cache follows appName and never caches a 404

Receipt: v4

## Summary

`bot-commit.sh` gains a name cache beside its id cache. A changed `appName` is looked up again instead of hiding behind the cached id. A lookup that does not yield a numeric id is a failure: it is never cached, and it falls back to the repo default identity with a WARN. A failed cache write warns and no longer aborts the commit. The tracker README gains a note on renaming an App.

Open regions: none.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How the App name in commit metadata settles | Finish the rename. The App keeps its neutral name on GitHub. The operator updates the local `appName` by hand. Old commits stay as they are. The maintainer-local trace gate still denylists the old name. | user-answered | intent |
| D-2 | What this PR builds | A name cache, so a changed `appName` is looked up again instead of hiding behind the id cache. A README note on renaming an App. | user-answered | intent |
| D-3 | A cache mismatch with a failed lookup | A WARN naming the configured `appName`. A commit under the repo default identity. No cache write. The next commit retries. | user-answered | intent |
| D-4 | Where the name is cached | A new file beside the id cache, named by the build. The id file keeps the bare id, so an older `bot-commit.sh` sharing the git common dir still reads it. | user-answered | intent |
| D-5 | How far the guard reaches | A changed `appName` only. A rename on GitHub with `appName` left unchanged is out of scope. The README note tells whoever renames the App to edit `appName`. | user-answered | intent |
| D-6 | When the cached id is trusted | Only when the name cache's content equals `<configured appName> <id-file id>`, compared as one string. A trailing newline is ignored. Anything else, an unreadable file included, triggers a lookup. | user-answered | intent |
| D-7 | Test intent for AC-6 | Exempt. The README note is prose, and the repo rules out prose-presence guards. | user-answered | intent |
| D-8 | What counts as a valid id | Only a value matching `^[0-9]+$`, from the id file or from the lookup. A non-zero exit, empty output or a 404 body is a failed lookup. | user-answered | intent |
| D-9 | A failed cache write or read | A WARN naming the file. The wrapper never aborts on it. The commit goes ahead with the resolved id. | user-answered | intent |
| D-10 | Overlap with #1059 (dup-scan candidate, score 13) | Distinct work, already merged in #1073. It changed how `appName` is resolved and left the cache block alone. run: `gh issue view 1059 --json state --jq .state; git diff 31f7f93b d515facb -- plugins/dev-pipeline/tools/bot-commit.sh \| grep -c CACHE` → CLOSED, 0 | codebase-derived | fact |
| D-11 | Cutover on this repo | The operator writes `tracker.bot.app`, with the App's current name, into `.claude/second-shift.config.local.json`. The pull of #1073 left this checkout with no app block. run: `jq -r '.tracker.bot.app.appName // "none"' .claude/second-shift.config.json; ls .claude/second-shift.config.local.json` → none, No such file | codebase-derived | fact |
| D-12 | Changes to `install-gh-bot.sh` | None. It uses `appName` only for its default, its config read, a download message and the wrapper's comments. run: `grep -n APP_NAME plugins/dev-pipeline/tools/install-gh-bot.sh` → lines 38, 67, 111, 164, 168 | codebase-derived | fact |
| D-13 | A WARN on a successful lookup | None. The success path stays silent, as today. run: `grep -n '5c success' plugins/dev-pipeline/tools/bot-commit-selftest.sh` → 150: pass "5c success path is silent (no WARN)" | codebase-derived | fact |
| D-14 | The name cache's file name | `<git common dir>/second-shift-bot-user-name`, holding `<appName> <id>` with no trailing newline, the same form as the id file. Added in build: D-4 left the file name to the build. | user-delegated | intent |
| D-15 | The fake `gh` in `run-selftest-lib.sh` | It answers `api users/<login>` with a numeric id, as real `gh ... --jq .id` does. Added in build: its `{}` answer passed as an id before this change, so case (w2) of `run-bot-local-selftest.sh` went red once `bot-commit.sh` refused it. | user-delegated | intent |

Options weighed:
- D-1: accept the old name and drop it from the trace gate, or finish the rename. The operator chose finish the rename.
- D-2: a docs note only, nothing, derive the name from the id, or a name cache plus a docs note. The operator chose a name cache plus a docs note.
- D-3: WARN and commit as the repo default, or WARN and keep the cached id. The operator chose WARN and commit as the repo default.
- D-4: a sibling file, or one renamed file holding both values. The operator chose a sibling file.
- D-5: narrow the Goal, or re-verify on a TTL. The operator chose narrow the Goal.
- D-6: pair the name with the id, or accept the race between two writers. The operator chose pair them.
- D-7: exempt AC-6, or drop AC-6. The operator chose exempt.
- D-8: require a numeric id in this ticket, or file the 404 bug separately. The operator chose require a numeric id.
- D-9: WARN and still commit, or keep the write fatal. The operator chose WARN and still commit.

## Open Regions

No open regions. Every decision in scope is settled.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6 AC-7 AC-8

AC-1: a matching id file and name cache commit as `<appName>[bot]` with the cached id, with no `gh` call and no WARN
AC-2: a name cache for another name, with a lookup that yields a different id, commits with the new id and rewrites both files, with no WARN
AC-3: a mismatch whose `gh` stub exits 1 and prints GitHub's 404 JSON on stdout WARNs, commits as the repo default and leaves both files unchanged
AC-4: an id file with no name cache triggers a lookup, and the result decides between AC-2 and AC-3
AC-5: an id file holding non-numeric text, JSON or a carriage return is not used, and a lookup runs
AC-6: exempt — the README note is prose; no test can prove it
AC-7: a name cache whose id differs from the id file's, or an empty id file, triggers a lookup
AC-8: a directory at a cache file's path gives a WARN, and the commit still happens with exit 0

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Author name and email on bot commits | decided (D-6) |
| S-2 | stderr WARN on a failed lookup | decided (D-3) |
| S-3 | stderr WARN on a failed cache write | decided (D-9) |
| S-4 | README note on renaming an App | decided (D-2) |
| S-5 | Commits already on main | out-of-scope — history is not rewritten, per D-1. |
| S-6 | Comments in an already generated bot wrapper | decided (D-12) |

## Checks

- `bash plugins/dev-pipeline/tools/bot-commit-selftest.sh`

## Intake steps

Requirements: interviewed (feature) on a thin ticket with a key. spec-reviewer: 1 blocker and 6 gaps. The interview closed the blocker. The body resolved the gaps.

Split: not triggered. No epic label, one deliverable, and the register stayed under 10 material decisions.

Explore: done. Read `bot-commit.sh`, its selftest, `install-gh-bot.sh`, the tracker README, the git history of bot authors and #1059's merged diff.

Fan-out: ran — 25 items, see Fan-out

Dup-scan: 1 candidate, #1059 at score 13. It is distinct and already merged (D-10).

Post-merge scan: no post-merge AC

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: cache-state-matrix opus 6/6 · shared-cache-concurrency fable 4/6 · callers-and-cutover opus 6/6 · selftest-seam fable 4/6 · premortem fable 5/6
Tally: rows added 2 · snapshot claims overturned 1 · questions added 2

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | cache-state-matrix | Real `gh` prints the 404 or 401 JSON on stdout with rc=1; the selftest stub prints nothing (`bot-commit-selftest.sh:95-97`) | new | became D-8; shapes the AC-3 stub |
| F-2 | cache-state-matrix | A cold-cache 404 caches the JSON body as the id and commits with a junk email, no WARN (`bot-commit.sh` lookup line) | overturned (snapshot: "a failed lookup writes no cache") | became D-8 |
| F-3 | cache-state-matrix | Any id file passing `-s` is trusted, whatever it holds: CR, spaces, JSON reach the email | new | became D-8 and AC-5 |
| F-4 | cache-state-matrix | `<appName> <id>` cannot be split reliably, since `appName` is an unconstrained string (`schema/second-shift.config.schema.json:55`) | new | became D-6: compared as one string |
| F-5 | cache-state-matrix | A bare `read` of a file with no trailing newline returns 1 and aborts under `set -e` | new | became D-6: one-string compare, newline ignored |
| F-6 | cache-state-matrix | A failed cache write or an unreadable cache path aborts the wrapper with no commit (`bot-commit.sh:46`) | already-had | became D-9 |
| F-7 | shared-cache-concurrency | A failed id write is fatal, against the header's duty that the commit still happens (`bot-commit.sh:83`) | already-had | became D-9 |
| F-8 | shared-cache-concurrency | Record commits and build commits across lanes share one cache, and `run.sh` has no lane lock | not material | not material — D-6 pairing already covers mixed writers |
| F-9 | shared-cache-concurrency | Two sequential writes can leave a half-updated pair when the second write aborts | new | became D-9; the next commit re-looks |
| F-10 | shared-cache-concurrency | This machine holds a warm id cache and no name cache, so its first commit takes the lookup path | already-had | became D-11 |
| F-11 | callers-and-cutover | The ticket's cold-cache premise is false for real `gh`: a 404 body is cached, not a fallback | overturned (snapshot: "a failed lookup writes no cache") | became D-8 |
| F-12 | callers-and-cutover | Case 4's stub exits 1 with empty stdout, so a new case on it misses the real 404 shape | new | became D-8; shapes the AC-3 stub |
| F-13 | callers-and-cutover | Lane lookups run on the operator's `gh` login, and sessions read `appName` from a launch-time config copy (`run.sh:1597`) | new | became D-11: edit before the next lane run |
| F-14 | callers-and-cutover | Nothing in `run.sh`, the tools or CI reads a lane commit's author, so a fallback goes unnoticed | new | not material — out of scope, named in the ticket's Out |
| F-15 | callers-and-cutover | Both bot-enabled checkouts on this machine carry the old name with a warm id cache | already-had | became D-11 |
| F-16 | callers-and-cutover | Other `appName` readers never reach the commit identity; the README is the only doc touch point | already-had | became D-12 |
| F-17 | selftest-seam | AC-1, the old AC-5 and the empty-id half of AC-7 already pass against today's code | not material | not material — one suite file, judged whole |
| F-18 | selftest-seam | No shim both fails on demand and logs calls; `GH_SHIM_CALLS` is cleared only once (`bot-commit-selftest.sh:25`) | new | not material — a test detail for the build, no decision |
| F-19 | selftest-seam | The suite prints PASS/FAIL lines only, so the lane's check judges the whole file | not material | not material — the runner's default format |
| F-20 | selftest-seam | Case 9c checks only the id filename under the override root; it needs the new filename | new | not material — a test detail for the build |
| F-21 | premortem | After the install, a checkout left with the old name commits as the operator, and only a stderr WARN shows it | new | became D-11 |
| F-22 | premortem | The configured login 404s, and the cached id resolves to the renamed bot's login | already-had | became D-1 |
| F-23 | premortem | A denied id write today aborts with rc=1 and no commit, so the record commit ends the lane | already-had | became D-9 |
| F-24 | premortem | The shim returns one id for every login, so a lookup of the wrong name passes green (`bot-commit-selftest.sh:23-31`) | new | became D-8; AC-2 needs a per-login stub |
| F-25 | premortem | Without `gh auth`, every lookup fails and no cache is written, so every commit falls back | new | not material — accepted under D-4, stated in the body's sad paths |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Which way the App name in commit metadata settles | Finish the rename: keep the neutral GitHub name, update the local appName by hand, old commits stay |
    | D-2 | What the lane builds | A name cache so a changed appName is looked up, plus a README note on renaming an App |
    | D-3 | Mismatch and a failed lookup | WARN naming appName, commit under the repo default identity (the existing unresolvable-id path) |
    | D-4 | Where the name is cached | A sibling file; the id file stays the bare id for older readers |
    | D-5 | How far the guard reaches | A changed appName only; a GitHub-side rename with appName unchanged is out of scope |
    | D-6 | Pairing the name and the id | The name cache holds `<appName> <id>` and is trusted only when its id equals the id file's |
    | D-7 | AC-6 test intent | exempt — README prose |
    | D-8 | Cache write on a failed lookup | None — bot-commit.sh:179 writes only a non-empty id |
    | D-9 | WARN on a successful re-lookup | None — selftest case 5c keeps the success path silent |
    | D-10 | Missing or empty id file | Triggers a lookup, as the -s check at bot-commit.sh:174 does today |
    | D-11 | A failed cache write | Unresolved — under set -euo pipefail (bot-commit.sh:46) a failed redirect aborts before the commit |
    | D-12 | Cutover on this repo | Operator edits appName before installing the release; safe now, since a warm id cache uses appName only as the name |
    | D-13 | Interaction with #1059 | Independent — #1059 changes the config read, this change sits after APP_NAME resolves |
    | D-14 | install-gh-bot.sh | Untouched — appName only in messages and URLs |

</details>
