# Lean spec — #237: unset `worktreesDir` silently disables the Stage-10 intake-pin backstop

## Context

`topology.repos.<host>.worktreesDir` is documented as optional with a default of
`../<repo>-worktrees` (`schema/second-shift.config.schema.json`), and `config-lint.sh`
never requires it. The bug is that the implementation never actually applies that
documented default at three of its four call sites — `stages/1-intake.md` Step 1.P (the
intake-pin), `stages/2-worktree.md`'s single-repo worktree-add block, and
`stages/10-cleanup.md`'s intake-pin backstop all interpolate `${WORKTREES_DIR}` with
**no derivation shown anywhere in the doc**. Only the be-fe-pair loop in
`stages/2-worktree.md` derives it correctly (`jq ... // empty` + a `../${r}-worktrees`
fallback). An undefined `${WORKTREES_DIR}` expands to empty, so
`"${WORKTREES_DIR}/intake-pin-${ISSUE_NUMBER}"` composes `/intake-pin-<n>` — a
filesystem-root path. Stage 10 swallows the resulting `git worktree remove` failure
behind `2>/dev/null || true`, which is how run #230 reached `status: completed` and
still left `intake-pin-230` on disk.

`tools/preflight.sh`'s advisory report independently guesses a THIRD, different default
(`.claude/worktrees`) for the same key — evidence the resolution rule has never had one
home.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Which option from the issue | (b) — documented default resolution (already specified in the JSON schema) plus a hard guard against ever composing an empty/root path. Not (a) (making the key required): a breaking change for every existing consumer, this repo's own config included. | issue #237 comment, operator triage 2026-07-29 |
| D-2 | Single source of truth mechanism | A new real, testable script, `tools/resolve-worktrees-dir.sh` — not a lockstep-manifest.tsv pairing of prose copies. The duplication here is bash-in-markdown with no interpreter until an agent runs it; extracting it to an actual script makes it both single-homed AND directly selftest-able (`docs/testing.md`'s "per-tool behavioral selftest" tier), which a lockstep row (byte-identical-prose enforcement only) cannot give AC-4. | codebase-derived |
| D-3 | Default value | `../<repoId>-worktrees` — already the documented schema default and already the be-fe-pair loop's existing fallback; the fix generalizes it to the host repo path (`.`) instead of inventing a new default. | codebase-derived (schema field description) |
| D-4 | Call-site scope | All FIVE existing inline derivations route through the one script: the be-fe-pair loop (replacing its own `jq // empty` + fallback), Stage-1's pin, Stage-2's single-repo worktree-add, Stage-2's statectl-persist block (a separate bash fence from the worktree-add — re-derives rather than relying on cross-block variable persistence, matching the doc's existing pattern for `$TOPO`), and Stage-10's cleanup. `preflight.sh`'s advisory per-repo loop also switches to it, closing the third-default drift. | codebase-derived |
| D-5 | Failure-context reason | Stage-1 resolution failure reuses the existing `non-main-base-autonomous` reason (already covers "the detached pin-worktree creation failed" in this same step); Stage-2 resolution failure reuses the existing `worktree-creation-failed` reason (already covers `git worktree add` failure in the same block). No new reason enum value / `state-schema.md` row needed. | codebase-derived |

## Acceptance Criteria

- AC-1: `tools/resolve-worktrees-dir.sh` is added: given a config path and an optional
  repo id (defaulting to auto-detecting the host repo, the `topology.repos` entry with
  `path == "."`), it prints the resolved worktrees dir on stdout and exits 0 when the
  key is present OR absent (documented default applied); it prints nothing to stdout,
  a named reason to stderr, and exits non-zero when resolution cannot succeed at all
  (unreadable config, no matching repo entry) — never a silent empty result.
- AC-2: With `worktreesDir` absent from config, Stage 10's intake-pin cleanup either
  removes the pin at the default-resolved path, or — only if the resolution call itself
  fails — reports why on stderr instead of unconditionally swallowing the outcome via
  `2>/dev/null || true`. Same predicate for Stage 1's pin creation and Stage 2's
  worktree creation (single-repo and be-fe-pair): neither ever attempts to operate at
  an absolute root path; each resolves the documented default or fails closed with a
  message naming the unresolvable repo.
- AC-3: The resolution rule is single-homed in `tools/resolve-worktrees-dir.sh`. Every
  current call site — the be-fe-pair loop, Stage-1's pin, Stage-2's single-repo
  worktree-add, Stage-2's statectl-persist block, Stage-10's cleanup, and
  `preflight.sh`'s advisory report — calls it via
  `${CLAUDE_PLUGIN_ROOT}/skills/run/tools/resolve-worktrees-dir.sh`; none retain their
  own inline `jq ... worktreesDir` derivation or an independently-guessed default.
- AC-4: `tools/resolve-worktrees-dir-selftest.sh` drives `resolve-worktrees-dir.sh`
  against fixture configs: key present (returned verbatim), key absent (the documented
  `../<repoId>-worktrees` default), and an unresolvable repo (no `topology.repos` entry
  with `path=="."`, or an explicit repo id absent from config) — the last case asserts
  non-zero exit, empty stdout, and a stderr reason, i.e. it would have caught the exact
  swallowed-failure gap in the issue (no call site could previously observe "resolution
  failed"; it only ever silently interpolated empty).
- AC-5: shellcheck, jq, and the full `*-selftest.sh` sweep stay green (repo
  verification standard, CLAUDE.md).

## Out of scope

- Making `worktreesDir` a required config key (option (a), explicitly rejected by the
  operator's triage decision, D-1).
- Deleting the already-leaked `intake-pin-230` / `intake-pin-82` worktrees on the
  maintainer's machine — local operational cleanup, not a code change this PR ships.
- Any change to `config-lint.sh`'s allowed-keys set — `worktreesDir` stays optional and
  already appears there.
