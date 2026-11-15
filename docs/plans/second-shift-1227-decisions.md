# Decision record — #1227 The release derivation gives every touched plugin a breaking commit's major and lists `Migration: none` under What breaks

Receipt: v4

## Summary

The release deriver gives a breaking commit's major only to the plugins its subject scope names. A commit that names none falls back to the path rule. `Migration: none` stops listing commits under What breaks, and every generated line carries its PR number once. A new frozen-file row guards the marketplace version, and the docs state the amended rules.

Open regions: none.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How a breaking commit names its plugins | The subject scope. Split it on commas. Each token must equal a `plugins/` directory name exactly, so `intake` names nothing. No `Breaking-Plugins:` trailer. | user-answered | intent |
| D-2 | A breaking commit whose scope names no plugin | The path rule applies: every plugin the commit touches takes the major. This covers a scopeless `!`, a footer-only verbless subject and a non-plugin scope such as `(ci)`. | user-answered | intent |
| D-3 | A scope that names a plugin the commit does not touch | Only named plugins the commit touches take the major. When no named plugin is touched, the D-2 fallback applies. An untouched plugin is never added to the changed set. | user-answered | intent |
| D-4 | Where the `**BREAKING:**` CHANGELOG line renders | Only under the plugins that take the major from that commit. Other touched plugins keep the commit's bullet without the BREAKING line. | user-answered | intent |
| D-5 | When a `Migration:` is a no-op | The text from `Migration:` to the end of its Changelog block, trimmed and lowercased, with one trailing period stripped, equals `none`. `none` followed by more prose is a real migration. | user-answered | intent |
| D-6 | What What-breaks renders for a commit | Each Changelog block with a real migration renders whole. No-op blocks never render. A non-breaking commit with only no-op blocks gets no entry. A breaking commit keeps its entry with its BREAKING prose. | user-answered | intent |
| D-7 | No-op Migration lines in CHANGELOG bullets | Unchanged. `render_bullet` keeps printing whole Changelog blocks, including `Migration: none.` lines. | user-answered | intent |
| D-8 | The marketplace max rule at `derive-release.sh:197-198` | It stays. AC-3 adds only the frozen-file gate. The max rule keeps a re-derive from going backwards after a failed tag publish, as plugin.json's rule at `:191` does. | user-answered | intent |
| D-9 | intake-toolkit in the held v18 release | It takes a patch, because b1763e05 names only review-toolkit. The deleted eval was never callable. The CLAUDE.md commit-verb section and `docs/releasing.md` say a breaking PR title must scope every plugin it breaks. | user-answered | intent |
| D-10 | The "derived bump" wording for `check-plugin-version-bumps.sh` | Reword it to what the script checks: a changed plugin's version string changed. The sites are `docs/releasing.md:85`, `ci.yml:300-301`, `ci.yml:314` and the script header. The script does not change. | user-answered | intent |
| D-11 | The migrations README | Add v16.0.0, v17.0.0 and v18.0.0 to the non-config majors list, each in the v13/v14 form: what broke, then what to do. Line 19 says a schema-breaking change bumps `configVersion`, not every breaking change. | user-answered | intent |
| D-12 | The ticket's AC block | It was rewritten on the tracker at intake to match D-1 to D-6, D-10 and D-11. The ids AC-1 to AC-5 are kept. Nothing else in the body changed. | user-answered | intent |
| D-13 | A test for AC-5 | AC-5 is exempt. It is doc and CI-label wording, and no test can prove prose. | user-answered | intent |
| D-14 | The PR-number sites and format | Three sites append ` (#N)` to a subject that already ends in `(#N)`. Strip the subject's trailing `(#N)` and keep the suffix, giving `- **subject** (#N)`, the selftest's hand-written form — run: `grep -nF ' (#$pr)' scripts/derive-release.sh` → 232, 320, 426 | codebase-derived | fact |
| D-15 | Where the bump and Migration rules are stated | All must match the new code: CLAUDE.md:59 and :70, `docs/releasing.md:29`, `:35-37` and `:17-19`, and the header at `derive-release.sh:20-38` — run: `grep -nE 'BREAKING CHANGE\|never the commit scope' CLAUDE.md docs/releasing.md scripts/derive-release.sh` → CLAUDE.md:59, :70, releasing.md:29, :36, derive-release.sh:23-24 | codebase-derived | fact |
| D-16 | Where the frozen-file list is stated | The marketplace row joins `docs/releasing.md:7-8`, `:76` and `:83`, the `check-frozen-files.sh` header and the `ci.yml` frozen-files step name — run: `grep -n 'frozen files guard' .github/workflows/ci.yml` → 290: plugin.json versions + CHANGELOG are release-owned | codebase-derived | fact |
| D-17 | The marketplace frozen row and its test | A hard row compares `metadata.version` at the merge base and at HEAD, like the plugin.json row. Its case goes in `derive-release-selftest.sh`, not a new suite — cited (convention): CLAUDE.md:117 | codebase-derived | fact |
| D-18 | How the fix reaches the held #1211 | A push to main re-derives `release/next` from main. Main's top CHANGELOG section is the tagged v17.14.1, so the stale v18 section is regenerated, not absorbed — run: `grep -nE '^ +branches' .github/workflows/release-pr.yml` → 18: branches: [main] | codebase-derived | fact |
| D-19 | The `ci.yml` edit and the frozen-files check | The edit trips only the advisory row, which never fails the check — run: `grep -n 'ADVISORY row' scripts/check-frozen-files.sh` → 40: deliberately does NOT touch `fails` | codebase-derived | fact |

Options weighed:
- D-1: Scope parsing, a `Breaking-Plugins:` trailer with scope fallback, or a trailer only. The operator chose scope parsing.
- D-2: Path-rule fallback, no major anywhere, or CI rejects the commit. The operator chose the path-rule fallback.
- D-3: Named and touched else fallback, named plugin only, or bump the untouched plugin. The operator chose named and touched else fallback.
- D-4: Only under majored plugins, or under every touched plugin. The operator chose only under majored plugins.
- D-5: Only an exact `none`, or a leading `none` plus a separator. The operator chose only an exact `none`.
- D-6: Whole blocks with a real migration, or only the migration text. The operator chose whole blocks.
- D-7: Leave CHANGELOG bullets, or strip no-op Migration lines. The operator chose to leave them.
- D-8: Gate only, or also remove the max rule. The operator chose gate only.
- D-9: Accept with a docs rule, accept without one, or deleted files force a major. The operator chose accept with a docs rule.
- D-10: Reword the docs, or make the script check the level. The operator chose to reword.
- D-11: Add v16, v17 and v18, or only v16 and v17. The operator chose all three and the line 19 fix.
- D-12: Rewrite the AC block, or let the record carry the change. The operator chose to rewrite it.
- D-13: Exempt, or not exempt. The operator chose exempt.

## Open Regions

No open regions. Every decision in scope is settled.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5

AC-1: a `chore(alpha)!:` commit touching alpha and beta majors alpha only, and beta's section has no BREAKING line. A footer-only commit majors every plugin it touches. A scope naming only untouched plugins falls back
AC-2: `Migration: none`, `none.`, mid-line `… Migration: none.` and two none blocks give no What-breaks entry. `none. <prose>` and a real migration render their whole blocks
AC-3: a branch that changes `metadata.version` in `.claude-plugin/marketplace.json` fails `check-frozen-files.sh`
AC-4: the CHANGELOG bullet, the What-breaks entry and the subject-only line each carry `(#N)` exactly once
AC-5: exempt — doc and CI-label wording; no test can prove prose

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | CHANGELOG plugin headings and bullets | decided (D-4) |
| S-2 | What-breaks block in the Release body and PR preview | decided (D-6) |
| S-3 | Subject-only list in the release PR body | decided (D-14) |
| S-4 | frozen-files rejection of a marketplace version edit | decided (D-17) |
| S-5 | releasing.md, CLAUDE.md and the migrations README | decided (D-15) |
| S-6 | release-PR job step name in `ci.yml` | decided (D-10) |
| S-7 | Doubled PR numbers in already-released CHANGELOG sections | out-of-scope — CHANGELOG.md is frozen for feature PRs. |
| S-8 | The stale configVersion sentence at CHANGELOG.md:4 | out-of-scope — only the release PR may edit CHANGELOG.md. |

## Checks

No ticket-specific checks. The configured checks cover this change.

## Intake steps

Requirements: the ticket body as written. spec-reviewer: needs spec work, with one blocker the ticket already handed to intake. The interview resolved it.

Split: not triggered. There is no epic label, and one script plus its docs is one PR.

Explore: done. Read derive-release.sh, its selftest, check-frozen-files.sh, check-plugin-version-bumps.sh, releasing.md, the migrations README and the breaking-commit history.

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
Lenses: history-replay opus 6/6 · in-flight-release fable 6/6 · version-consumers opus 5/6 · rule-surface fable 5/6 · premortem fable 6/6
Tally: rows added 4 · snapshot claims overturned 1 · questions added 4

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | history-replay | A replay gives 18.0.0. A scope rule drops four plugins to patch and keeps review-toolkit major (`derive-release.sh manifest`). | new | became D-1 |
| F-2 | history-replay | #1210, #1213 and #1225 reach What breaks only through `Migration: none.` (`derive-release.sh:324`). | already-had | became D-6 |
| F-3 | history-replay | Nine `!` subjects carry one plugin scope. Seven footer-only breaking commits have verbless subjects (`git log --first-parent`). | already-had | became D-2 |
| F-4 | history-replay | No commit carries `Breaking-Plugins:`, and b1763e05 deletes 13 intake-toolkit files (`git show b1763e05`). | new | became D-1 and D-9 |
| F-5 | history-replay | Comma scopes and near-miss scopes such as `intake` exist, so matching must be exact (`git log` census). | new | became D-1 |
| F-6 | history-replay | Real `Migration:` values include qualified nones carrying guidance, and some sit mid-line (`git log` census). | overturned (snapshot: "none followed by end of line or punctuation is a no-op") | became D-5 |
| F-7 | in-flight-release | The re-derive reads main only, and `release/next` equals the unpatched derive of main (`release-pr.yml:18`). | new | became D-18 |
| F-8 | in-flight-release | A scope stand-in re-derive keeps 18.0.0 and moves four plugins down. Both release-PR gates pass (scratch clone). | new | became D-11 |
| F-9 | in-flight-release | On main the v18 CHANGELOG section is regenerated, not absorbed (`derive-release.sh:257-268`). | new | became D-18 |
| F-10 | in-flight-release | Run on the `release/next` tree, the max rule pins the bled majors (`derive-release.sh:191`). | new | became D-8 |
| F-11 | in-flight-release | A level-only fix leaves the BREAKING line under patch headings (`derive-release.sh:245-247`). | already-had | became D-4 |
| F-12 | in-flight-release | A trailer-only rule derives 17.15.0 for #1211, and scope parsing derives 18.0.0 (scratch clone). | new | became D-1 |
| F-13 | version-consumers | `check-plugin-version-bumps.sh` compares version strings only (`check-plugin-version-bumps.sh:53`). | already-had | became D-10 |
| F-14 | version-consumers | Footer-only breaking commits are common, so a scope-only rule needs a ruling for them (`git log`). | already-had | became D-2 |
| F-15 | version-consumers | What-breaks and the subject-only list also double the PR number (`derive-release.sh:320`, `:426`). | already-had | became D-14 |
| F-16 | version-consumers | What-breaks prints whole Changelog paragraphs, whatever the commit's level (`derive-release.sh:333`). | already-had | became D-6 |
| F-17 | version-consumers | Every reader of the deriver's output keys on version strings, never on the level (doctor, run.sh, release-publish). | new | not material — no reader breaks |
| F-18 | rule-surface | The bump rule is stated in CLAUDE.md, releasing.md, the deriver header and the selftest labels (`grep`). | new | became D-15 |
| F-19 | rule-surface | No doc defines `Migration: none`, and `releasing.md:17-19` says every trailer reaches What breaks. | new | became D-15 |
| F-20 | rule-surface | 270 lines are exactly `Migration: none.`, and 74 add prose after `none` (`git log` census). | overturned (snapshot: "none followed by end of line or punctuation is a no-op") | became D-5 |
| F-21 | rule-surface | Only CLAUDE.md lists the marketplace version among the frozen files (`releasing.md:7-8`, `:83`, `ci.yml:290`). | new | became D-16 |
| F-22 | rule-surface | "Derived bump" appears in four places, and the README's line 19 overstates the configVersion rule. | new | became D-10 and D-11 |
| F-23 | premortem | Treating "none plus prose" as a no-op drops real operator instructions (ef5274d1, 39f5b533). | new | became D-5 |
| F-24 | premortem | A scope-only rule majors nothing for the single commits behind v12 to v15 (`derive-release.sh manifest`). | already-had | became D-2 |
| F-25 | premortem | Bullet rendering keys on touched paths, so the BREAKING line repeats under patch plugins (`derive-release.sh:305-308`). | already-had | became D-4 |
| F-26 | premortem | A per-line migration filter truncates wrapped migrations and misses mid-line ones (`git log` census). | new | became D-6 |
| F-27 | premortem | intake-toolkit takes a patch although b1763e05 deletes 13 of its files (`git show b1763e05`). | new | became D-9 |
| F-28 | premortem | The doubled PR number has three sites, and 631 released bullets keep it (`derive-release.sh:232`). | already-had | became D-14 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Mechanism naming the broken plugins | open question; lean: parse the subject scope (every `!` subject in history is plugin-scoped, 9/9; comma multi-scope already used 9 times) |
    | D-2 | Breaking commit that names no plugin (scopeless `!`, footer-only verbless title, non-plugin scope) | open question; lean: fall back to today's path rule (over-major is the safe side; 7 footer-only verbless breaking commits in history) |
    | D-3 | Where the `**BREAKING:**` CHANGELOG line renders | open question; lean: only under the plugins that take the major |
    | D-4 | Level for a touched-but-unnamed plugin | its type without the `!`: feat minor, else patch (ticket ruling) |
    | D-5 | Named plugin the commit does not touch | gets nothing; the deriver only versions content-changed plugins (derive-release.sh:138,158) |
    | D-6 | `Migration: none` matching rule | open question; lean: the value after `Migration:` is `none` followed by end of line or punctuation, case-insensitive; `none of ...` is a real migration |
    | D-7 | What renders under What breaks for a migration-bearing commit | open question; today the whole trailer block; lean: from the `Migration:` line to the end of its block |
    | D-8 | PR-number double sites | all three: render_bullet (:232), What-breaks (:320), no-trailer list (:426) |
    | D-9 | Marketplace freeze | new hard row in check-frozen-files.sh; case in derive-release-selftest.sh frozen section; releasing.md gates table and script header list it; the :197-198 max rule stays |
    | D-10 | check-plugin-version-bumps.sh: reword or check the level | open question; lean: reword docs and CI step name (the script's job is the cache key) |
    | D-11 | Migrations README non-config majors | v16 (#930) and v17 (#1028); v15 is the config major covered by v2-to-v3.md; open: whether v18 is listed now |
    | D-12 | ci.yml step rename trips the frozen-files workflow advisory | harmless, warn-only |

</details>
