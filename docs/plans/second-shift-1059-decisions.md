# Decision record — #1059 dev-pipeline: this repo commits its config, keeping only the bot app identity machine-local

Receipt: v4

## Summary

This repo starts tracking `.claude/second-shift.config.json` without its `tracker.bot.app` block. The per-engineer `.claude/second-shift.config.local.json` may now carry the four app keys. `bot-commit.sh`, `run.sh` and `install-gh-bot.sh` read them from the main checkout's local file, so lane worktrees and session scratch copies still commit as the bot. `run.sh` warns at launch, without refusing, when the bot is enabled and no `appName` resolves.

Open regions: none.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Does `appName` stay out of the committed config? | Yes. All four `tracker.bot.app` keys stay local, so the tree gains no org-traceable token. Commit metadata already exposes the name. That exposure is #1068, outside this ticket. | user-answered | intent |
| D-2 | Do `tracker.bot.enabled`, `envVar` and `wrapperPath` stay committed? | Yes. A checkout with no wrapper then refuses at launch (`env-bot`), as an enabled but broken bot does today. | user-answered | intent |
| D-3 | Where do the local app keys live? | In `.claude/second-shift.config.local.json`, widened to allow `tracker.bot.app.*` beside `tracker.branchPrefix`. Every other key is still refused. | user-answered | intent |
| D-4 | How does `bot-commit.sh` find the local app keys? | It reads the main checkout's local file whichever config candidate wins. The main checkout is the git common dir's parent, honoring `SECOND_SHIFT_REPO_ROOT`. This covers the worktree copy, the scratch copy and the record commit. | user-answered | intent |
| D-5 | Which local file holds the app keys under a `SECOND_SHIFT_CONFIG` override? | Always the main checkout's file, in `run.sh`'s launch check, `bot-commit.sh` and `install-gh-bot.sh`. The `branchPrefix` override and the C6a validation stay on the file beside the config. | user-answered | intent |
| D-6 | How strict is the value check, and how do the keys merge? | Key names only, any value type, as config-lint treats the committed block. A local key overrides the same committed key, one key at a time. `tracker.bot.enabled` still comes from the committed config. | user-answered | intent |
| D-7 | What does `run.sh` do when the bot is enabled and no `appName` resolves? | It prints a launch warning that commits will land as the operator and names the fix. The run still starts. A refusal would break consumers that onboard leaves in that state. | user-answered | intent |
| D-8 | Where does the launch warning sit in `run.sh`? | Where `BOT_OK` is set, inside the block that runs when `RUN_GH` is unset. The build uses `bot-commit.sh` only when `BOT_OK` is 1. run: `grep -n 'BOT_OK=1\|"$BOT_OK" -eq 1' plugins/dev-pipeline/skills/run/run.sh` → 236 sets it inside the bot block; 1008 gates the bot-commit instruction on it | codebase-derived | fact |
| D-9 | How does `install-gh-bot.sh` resolve the app keys? | Flags first, then the main checkout's `.local.json`, then the committed config, then its defaults. It refuses when no source supplies `clientId`, naming all three sources. | user-answered | intent |
| D-10 | Which keys may the local file carry? | `tracker.branchPrefix` plus the four app keys config-lint already knows: `clientId`, `appName`, `privateKeyFilename`, `installationId`. run: `grep -c '"clientId","appName","privateKeyFilename","installationId"' plugins/dev-pipeline/tools/config-lint.sh` → 1 | codebase-derived | fact |
| D-11 | Which files state the branchPrefix-only rule and must change? | `run.sh`, `config-lint.sh`, `check-config-shadowing.sh`, the schema description, `docs/config-schema.md` and the onboard skill. run: `grep -l 'branchPrefix only\|tracker.branchPrefix and nothing else\|per-engineer tracker.branchPrefix override' plugins/dev-pipeline/skills/run/run.sh plugins/dev-pipeline/tools/config-lint.sh plugins/dev-pipeline/tools/check-config-shadowing.sh schema/second-shift.config.schema.json` → all 4; `grep -c 'It may hold nothing else' plugins/second-shift/skills/onboard/SKILL.md` → 1; docs: cited (convention): docs/config-schema.md:81 | codebase-derived | fact |
| D-12 | How far does the onboard skill change go? | A prose note only. Its per-engineer step allows `tracker.bot.app.*`, and a rerun keeps a resident app block. The onboard flow does not offer to write the block. | user-answered | intent |
| D-13 | What does the committed config contain? | The current config minus `tracker.bot.app`, produced with `jq 'del(.tracker.bot.app)'` from the session's scratch copy. run: `jq 'del(.tracker.bot.app)' .claude/second-shift.config.json > <dir>/.claude/second-shift.config.json; bash ~/.claude/plans/second-shift-trace-gate.sh <dir>` → rc=0 (rc=1 with the block kept) | codebase-derived | fact |
| D-14 | What does `.gitignore` look like after? | Line 26 and its comment block go, so the config is tracked. The local-file entry at line 34 stays. run: `git check-ignore -v .claude/second-shift.config.json .claude/second-shift.config.local.json` → .gitignore:26 and .gitignore:34 | codebase-derived | fact |
| D-15 | Does `gh-bot.sh` change? | No. It reads only `enabled`, `envVar` and `wrapperPath`, which stay committed. run: `grep -c 'tracker.bot.app' plugins/dev-pipeline/tools/gh-bot.sh` → 0 | codebase-derived | fact |
| D-16 | Where does the AC-2 selftest live? | A repo suite under `scripts/`, beside the other repo-hygiene checks. It reads `git show HEAD:.claude/second-shift.config.json`, so it checks only what is committed. | user-answered | intent |
| D-17 | How are the ACs tested beyond selftests? | AC-5 is unchecked, because `install-gh-bot.sh` has no selftest suite. The trace gate is private and runs as PM-1, not in CI. | user-answered | intent |
| D-18 | How is the one-time cutover handled? | The PR body lists the steps in order: save the app block, pull, install the release with the new readers, write the block into `.local.json`. PM-2 checks the first lane commit after it. | user-answered | intent |
| D-19 | What do the new messages say? | Each names the file, the key at fault and the fix, in the style of the existing terminal messages. cited (convention): plugins/dev-pipeline/skills/run/run.sh:198 | codebase-derived | fact |
| D-20 | Is the ticket split? | No. Every decision hangs off one mechanism, and the cutover order is settled in the PR body. | user-answered | intent |
| D-21 | Is a specialist review seat named? | No. The AC-2 selftest guards the leak mechanically, and the review picks its seats on judgment. | user-answered | intent |
| D-22 | What release kind is it? | A `feat:` PR title, because consumers gain app keys in the local file. The `Changelog:` trailer says so, with `Migration: none`. cited (convention): CLAUDE.md "Commit verbs decide the version bump" | codebase-derived | fact |
| D-23 | Does a `false` or `null` value in the local file count as setting its key? | Yes. `run.sh` and config-lint read every leaf path, so a local `"tracker":{"bot":{"enabled":false}}` is refused like any other key. Added in build: the old check used jq's `paths(scalars)`, which skips `false` and `null`, so that file passed both gates. | user-delegated | intent |

Options weighed:

- D-1: keep `appName` local, commit it and keep only the IDs local, or rename the App first. The operator chose to keep it local.
- D-2: keep the bot flags committed, or move them local too. The operator chose to keep them committed.
- D-3: widen `.local.json`, a new dedicated local file, or a file beside the wrapper. The operator chose to widen `.local.json`.
- D-4: `bot-commit.sh` reads from the main checkout, or `run.sh` merges the block into the scratch copy at launch. The operator chose the main checkout.
- D-5: app keys always from the main checkout, or every local read moved there. The operator chose app keys only.
- D-6: key names with a per-key merge, strings only with a per-key merge, or key names with a whole-block replace. The operator chose key names with a per-key merge.
- D-7: a launch warning, a breaking refusal, a `bot-commit.sh` failure, or `bot-commit.sh`'s warning alone. The operator first chose the refusal. After learning that onboard produces the state, the operator chose the warning.
- D-9: refuse on an empty `clientId`, or no guard. The operator chose the refusal.
- D-12: a prose note, or an onboard offer to write the block. The operator chose the prose note.
- D-16: a repo suite under `scripts/`, or a plugin selftest. The operator chose the repo suite.
- D-17: a data guard plus post-merge checks, or a new `install-gh-bot.sh` selftest too. The operator chose the data guard plus post-merge checks.
- D-18: steps in the PR body with a post-merge check, or a code guard. The operator chose the PR body.
- D-20: one PR, or a split at the release seam. The operator chose one PR.
- D-21: no extra seat, or the security seat. The operator chose no extra seat.

## Open Regions

No open regions. Every decision in scope is settled.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5

AC-1: with `tracker.bot.app` only in the main checkout's `.local.json`, `bot-commit.sh` commits as `<appName>[bot]` from a worktree whose committed config has no app block, and with `SECOND_SHIFT_CONFIG` at a copy of that config
AC-2: a `scripts/` selftest fails when the tracked `.claude/second-shift.config.json` is missing or carries `tracker.bot.app`
AC-3: with the bot enabled and no `appName` anywhere, `run.sh` prints the launch warning and the run still starts (a run*-selftest case)
AC-4: `run.sh` and `config-lint.sh` accept `tracker.bot.app.*` keys in `.local.json`, and both still refuse any other key besides `tracker.branchPrefix`
AC-5: unchecked — `install-gh-bot.sh` has no selftest suite, a named exception in CLAUDE.md

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | `run.sh` launch warning for an unresolved `appName` | decided (D-7) |
| S-2 | `run.sh` `env-config-local` message wording | decided (D-19) |
| S-3 | config-lint error for the local file | decided (D-10) |
| S-4 | `install-gh-bot.sh` refusal on an empty `clientId` | decided (D-9) |
| S-5 | `bot-commit.sh` WARN text and header comment | decided (D-4) |
| S-6 | Onboard skill step for the per-engineer file | decided (D-12) |
| S-7 | `docs/config-schema.md` and the schema description | decided (D-11) |
| S-8 | Consumer doctor template branch-prefix note | out-of-scope — it checks only that the local file is gitignored, which stays true. |
| S-9 | Doctor's relay of config-lint output | out-of-scope — it prints config-lint's lines unchanged. |
| S-10 | PR body cutover steps | decided (D-18) |
| S-11 | `.gitignore` comment block | decided (D-14) |
| S-12 | `Changelog:` trailer text | decided (D-22) |

## Checks

No ticket-specific checks. The configured checks cover this change.

## Intake steps

Requirements: the ticket body as written. spec-reviewer: not ready, with 2 blockers settled in the interview. The operator approved the amended body.

Split: not split. The register passed 10 decisions and returned here. The operator kept one PR, because every decision hangs off one mechanism.

Explore: done. Read `bot-commit.sh`, `gh-bot.sh`, `install-gh-bot.sh`, the config and bot blocks of `run.sh`, `config-lint.sh`, the onboard skill and the trace gate.

Fan-out: ran — 18 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: the trace-gate half of AC-2 moved to PM-1. PM-2 was added for the cutover.

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: config-resolution-census opus 5/6 · local-file-contract fable 2/6 · publication-boundary opus 4/6 · cutover-and-consumers fable 3/6 · premortem fable 4/6
Tally: rows added 1 · snapshot claims overturned 0 · questions added 3

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | config-resolution-census | Once the config is tracked, `bot-commit.sh` takes the worktree's own copy before the main checkout's (`bot-commit.sh:131-140`). | already-had | became D-4 |
| F-2 | config-resolution-census | Sessions commit through a scratch copy with no app block, so `bot-commit.sh` falls back with a WARN (`run.sh:1507-1508`). | already-had | became D-4 |
| F-3 | config-resolution-census | `run.sh` and config-lint both refuse `tracker.bot.app` in the local file today (`run.sh:197-198`). | already-had | became D-3 and D-11 |
| F-4 | config-resolution-census | A wrapper home would need a new `appName` reader, since `bot-commit.sh` never reads the wrapper (`install-gh-bot.sh:148-160`). | already-had | weighed under D-3 |
| F-5 | config-resolution-census | `gh-bot.sh` reads only `enabled`, `envVar` and `wrapperPath`, never the app block (`gh-bot.sh:39-71`). | already-had | became D-15 |
| F-6 | local-file-contract | A local file beside the scratch copy is never read, so the lookup must not depend on `SECOND_SHIFT_CONFIG` (`run.sh:1504-1508`). | already-had | became D-4 and D-5 |
| F-7 | local-file-contract | config-lint already passes a config without `tracker.bot.app` (`config-lint.sh:133-138`). | already-had | became D-16 |
| F-8 | publication-boundary | The trace gate runs neither in CI nor from a hook in this clone (`.gitignore:22-26`). | already-had | became D-17 |
| F-9 | publication-boundary | The trace gate's token list does not cover `installationId` (`~/.claude/plans/second-shift-trace-gate.sh`). | new | not material — all four keys go local anyway |
| F-10 | publication-boundary | A probe commit of the trimmed config passes config-lint and the frozen-files check, but needs a force-add (`.gitignore:26`). | not material | not material — D-14 removes the ignore line |
| F-11 | publication-boundary | AC-2's trace-gate half cannot be a CI selftest without committing the token list (`run.sh:197-198`). | already-had | became D-16 and D-17 |
| F-12 | cutover-and-consumers | A pull onto the tracking commit silently overwrites the ignored config and its app block (scratch `pull-probe.sh`). | new | became D-18 |
| F-13 | cutover-and-consumers | Without a new reader, both tools degrade to placeholders and `bot-commit.sh` commits as the repo default (`install-gh-bot.sh:36-40`). | already-had | became D-4 and D-9 |
| F-14 | cutover-and-consumers | The branchPrefix-only rule lives in two gates with their own selftests (`config-lint.sh:309-325`). | already-had | became D-11 |
| F-15 | premortem | A local-only app block makes every lane commit land under the operator (`run.sh:1395`). | already-had | became D-4 |
| F-16 | premortem | The onboard skill writes the local file as exactly the prefix object, so a rerun wipes an app block (`onboard/SKILL.md:284-287`). | new | became D-11 and D-12 |
| F-17 | premortem | `install-gh-bot.sh` keeps an empty `clientId` with no guard, and has no selftest suite (`install-gh-bot.sh:36-38`). | new | became D-9 and D-17 |
| F-18 | premortem | Committing `enabled: true` makes a wrapper-less checkout refuse at launch (`run.sh:231-236`). | new | became D-2 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Home for tracker.bot.app | open — recommend `.claude/second-shift.config.local.json`: already gitignored (.gitignore:34), already read by run.sh C6a, config-lint and the consumer doctor; the wrapper-config home has no JSON source and install-gh-bot needs the identity before the wrapper exists |
    | D-2 | How readers find the local home | open — recommend anchoring on the main checkout (git common dir), not beside the winning config: once committed, the worktree copy (bot-commit.sh:133) and the scratch copy (run.sh:1508) win and carry no appName |
    | D-3 | Precedence when both committed and local carry app keys | open — recommend local over committed, mirroring branchPrefix (run.sh:239-244) |
    | D-4 | Bot enabled but appName unresolvable at lane launch | open — today bot-commit WARNs and commits as the operator; run.sh C12 refuses an enabled-but-broken wrapper; recommend run.sh refuses the same way |
    | D-5 | enabled / envVar / wrapperPath stay committed | trace gate clean on the config minus tracker.bot.app (rc=0), dirty with it (rc=1) |
    | D-6 | AC-2's test | config-lint already passes a config without tracker.bot.app (config-lint.sh:133-138); the trace gate is private and cannot be a selftest — open |
    | D-7 | .gitignore end state | follows D-1: delete line 26 and its comment block (22-25) |
    | D-8 | Files that encode the branchPrefix-only rule | run.sh:191-205, config-lint.sh:309-325, check-config-shadowing.sh:36, docs/config-schema.md:67-89, schema description :36, consumer doctor template :29-41 |
    | D-9 | install-gh-bot precedence | flags > config today (install-gh-bot.sh:56-63); local layer slots between flags and committed |
    | D-10 | gh-bot.sh | no change: reads only enabled/envVar/wrapperPath, which stay committed |

</details>
