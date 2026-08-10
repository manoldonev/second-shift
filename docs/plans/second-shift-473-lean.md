# 473 — doctor and onboard prescribe a project-scope install that doctor's own detection says is unnecessary

## Problem

`doctor.sh`'s resolver accepts a **user**-scope record as satisfying the lockfile, but every
remediation string it prints prescribes a **project**-scope install. On a user-scope machine,
following the printed fix mints a redundant per-repo record that then rots behind the user
record — and `local-dev-refresh` Step 4 realigns it at a fresh version rather than reporting it
as redundant, rewriting the repo's committed `.claude/settings.json` on the way.

## Binding input

`.claude/pipeline-state/473-ledger.md` (pre-flight Decision Ledger, D-1…D-13). Its decisions are
the design; the ACs below encode them.

Open Regions: **OR-1** (whether install-record resolution follows the project-over-user
precedence `docs/team-rollout.md` documents for enablement) rides its ratified
reversible-default — prefer the project record; the WARN names both versions either way, so a
reversal is one `jq` expression and loses nothing. **OR-2** (whether doctor should reach beyond
the current repo to the multi-checkout case) is dispositioned `pause-and-ask` and is **not
decided here**: this change keeps doctor's existing current-repo remit. Widening it is a change
of remit and needs its own ticket.

## Acceptance criteria

**AC-1 — the shared helper.** `plugins/second-shift/skills/doctor/tools/scope-shadows.sh`
classifies, per `@second-shift` plugin id, whether a user-scope install record serves it and
whether a project-scope record at the target repo root is therefore redundant. It emits one
TAB-separated row per classified plugin, ordered by plugin id:

```
shadowed	<plugin>	<project-version>	<user-version>
user-served	<plugin>	-	<user-version>
```

Exit status is the machine-checkable signal: `0` when at least one `shadowed` row was emitted,
`1` when none was, `2` on a usage error. It requires no lockfile (D-1: `local-dev-refresh` is
machine-wide and runs in lockfile-less repos). Data source is `claude plugin list --json`,
overridable by `DOCTOR_PLUGIN_LIST_FILE`; the repo root defaults to the git toplevel and is
overridable by `DOCTOR_REPO_ROOT` and `--root` (D-11 — doctor's own injection convention, so a
child process inherits doctor's injections and the paired suite is hermetic). Optional
positional plugin names restrict the scan.

**AC-2 — only user-shadows-project.** A `local`-scope record never produces a row and never
makes a project record `shadowed`: local scope is the documented per-developer override lever,
and a deliberate override is not redundant (D-10).

**AC-3 — doctor reports the shadowed record.** For every `shadowed` row, `doctor.sh` §3 prints a
`WARN` naming both versions, prescribing `claude plugin uninstall <p>@second-shift --scope
project`, and carrying **inline** the caveat that this deletes the plugin's `enabledPlugins`
entry from the committed `.claude/settings.json`, with `git checkout -- .claude/settings.json &&
git status` as the recovery (D-4). `WARN`, never `FAIL`: the presence of a shadowed record does
not move doctor's exit code (D-3).

**AC-4 — the verdict describes the project record.** When both a user- and a project-scope
record exist for one plugin id at this root, doctor's version verdict is computed from the
**project** record, replacing `sort_by(.lastUpdated) | last` as the decider (D-2). The
redundancy is reported alongside it, never folded into it.

**AC-5 — the `behind` branch under a user-scope record.** When the resolved record is
user-scope, the fix is `claude plugin marketplace update second-shift && claude plugin update
<p>@second-shift` — a different verb, because `claude plugin install` no-ops as "already
installed" and `update` is the upgrade verb (D-6). When it is not user-scope, today's
`--scope project` install string is unchanged.

**AC-6 — the `ahead` branch under a user-scope record.** When the resolved record is user-scope,
the fix names the **marketplace registration ref** as the lever and cross-references the
ref-less-registration WARN doctor already prints, and prescribes **no reinstall**: with no
project pin behind a user-scope record, a reinstall re-serves the same newer version — a no-op
that reads as a fix (D-5). When it is not user-scope, today's string is unchanged.

**AC-7 — the bootstrap surfaces are untouched.** The two not-installed-anywhere branches of
`doctor.sh` keep `--scope project` verbatim (D-8: that branch *is* the fresh-clone bootstrap the
ticket's Out of scope blesses). `onboard/SKILL.md`'s CONTRIBUTING snippet,
`templates/consumer/second-shift-doctor.sh`, `docs/team-rollout.md` and `docs/onboarding.md`
keep their unconditional `--scope project` strings (D-9).

**AC-8 — `local-dev-refresh` Step 4 declines on a shadowed record.** Step 4's precondition is
the helper's **exit status**, not an instruction it is trusted to follow: a project-scope
straggler whose plugin the helper reports `shadowed` is declined and reported as redundant (with
the same uninstall command and caveat as AC-3), never uninstalled-and-reinstalled. Unshadowed
project stragglers keep today's realignment — that install *is* the pin contract (D-1).

**AC-9 — `onboard` Step 8 item 2 explains the user-scope record.** For a plugin the bundle needs
that is not installed at this project but that the helper reports `user-served` (or `shadowed`),
Step 8 item 2 prints `<p>: served at user scope (<version>) — no project install needed` in
place of the install command. A silent skip is indistinguishable from "nothing was missing"
(D-7).

**AC-10 — guards.** A new same-named behavioral suite,
`plugins/second-shift/skills/doctor/tools/scope-shadows-selftest.sh`, covers AC-1 and AC-2
against fixtures. `doctor-selftest.sh` gains scenarios for AC-3, AC-4, AC-5 and AC-6 over a new
plugin-list fixture carrying **both** a user and a project record for one plugin id — no
existing fixture does — with the shadow scenario's `lastUpdated` ordering set so that the
pre-change resolver would have graded the *other* record (D-12).

**AC-11 — doc.** Two skill `description` frontmatter lines enumerate behavior this change moves
and would otherwise go stale: `doctor/SKILL.md`'s list of detected conditions gains the
redundant project-scope record (AC-3), and `local-dev-refresh/SKILL.md`'s "fix project-scope
stragglers" gains the decline (AC-8).

## Out of scope

Removing project-scope support. Reaching beyond the current repo (OR-2). Changing which record
the Claude Code harness itself loads.
