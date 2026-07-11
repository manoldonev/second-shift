# Dev Pipeline Hooks

Reference for the hooks in `.claude/settings.json` that support the dev-pipeline.
SKILL.md keeps only a short summary pointing here.

## 1. PreToolUse — pre-commit type-check (blocking)

Runs the configured type-check command (config `commands.<host>.typecheck`) before every `git commit` **that stages JS/TS-relevant files** (`.ts/.tsx/.js/.jsx/.mjs/.cjs/.json` or `yarn.lock` — the script checks `git diff --cached --name-only` and passes docs/shell-only commits through immediately). This is a fast incremental type-check gate — it catches type errors at commit time rather than waiting for Stage 6's full verify suite. The staged-path awareness also lets pipeline worktrees with inert diffs (Stage 6 verification matrix) commit without a `node_modules` install.

The `needs_typecheck()` predicate also carves out the **inert `.claude/**/\*.{mjs,cjs}`Workflow scripts**: a commit whose only JS/TS-relevant paths are those scripts skips the type-check (they have zero`tsconfig`/`eslint`/`jest` coverage — the inert set is defined once in [`tools/is-inert-diff.sh`](./tools/is-inert-diff.sh), the single source of truth, and the hook carve-out stays in lockstep with it). Any real `.ts/.tsx/.js/.jsx/.json`/`yarn.lock`, or any `.mjs`/`.cjs`**outside**`.claude/`(e.g.`apps/web/next.config.mjs`), still gates. The lockstep and the embedded copy below are both asserted by [`tools/pre-commit-typecheck-selftest.sh`](./tools/pre-commit-typecheck-selftest.sh) (wired into `pipeline-doctor.sh`).

**Matcher coverage:** each hook has TWO entries — `Bash(git commit *)` AND `Bash(git -c * commit *)`. The second exists because the dev-pipeline's bot-identity commits (`git -c user.name=... -c user.email=... commit`) do not match the first pattern; before it was added, every pipeline commit silently bypassed both gates.

### `.claude/settings.json` configuration

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "if": "Bash(git commit *)",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pre-commit-typecheck.sh",
            "timeout": 120,
            "statusMessage": "Running type-check pre-commit gate..."
          },
          {
            "type": "command",
            "if": "Bash(git -c * commit *)",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pre-commit-typecheck.sh",
            "timeout": 120,
            "statusMessage": "Running type-check pre-commit gate (bot-identity commit)..."
          },
          {
            "type": "command",
            "if": "Bash(git commit *)",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/scripts/check-reviewer-references.sh",
            "timeout": 15,
            "statusMessage": "Checking review-toolkit:review-lead reviewer-name registry consistency..."
          },
          {
            "type": "command",
            "if": "Bash(git -c * commit *)",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/scripts/check-reviewer-references.sh",
            "timeout": 15,
            "statusMessage": "Checking review-toolkit:review-lead reviewer-name registry consistency (bot-identity commit)..."
          }
        ]
      }
    ]
  }
}
```

The two hook entries are independent — the type-check's `permissionDecision: "deny"` does **not** short-circuit the registry-lockstep check. Both can deny on the same commit; both error messages surface. Order is a UX preference (type-check first because it's the heavier developer-facing failure).

### `hooks/pre-commit-typecheck.sh`

Plugin-shipped (fires via `hooks/hooks.json` on `git commit`); must be `chmod +x`. Config-aware: the type-check command comes from the consumer repo's `.claude/second-shift.config.json` (`commands.<host>.typecheck`), and the hook fails **open** in any repo that has not onboarded a typecheck lane.

```bash
#!/bin/bash

# needs_typecheck: read newline-delimited staged paths on stdin; return 0 (gate —
# run type-check) when a type-check is warranted, 1 (skip) otherwise.
#
# The type-check gates only commits that stage JS/TS-relevant files (sources, json
# config, lockfile). Skip when there is no JS/TS surface at all (docs/shell-only —
# also saves ~30s on every docs commit), OR when every JS/TS-relevant staged path
# is an inert .claude/**/*.{mjs,cjs} Workflow script. Those scripts live outside the
# yarn workspace tree and are referenced by no tsconfig/eslint/jest config, so
# type-check gives them zero coverage — gating on them is pure wasted node_modules
# install + run. This mirrors the Stage-6 inert lane; the inert set is defined once in
# the dev-pipeline skill's tools/is-inert-diff.sh (the single source of truth), and
# the .claude/**/*.{mjs,cjs} pattern below is kept in lockstep with it (asserted by
# pre-commit-typecheck-selftest.sh).
# A .mjs/.cjs OUTSIDE .claude/ (e.g. apps/web/next.config.mjs) is not inert and
# still gates.
needs_typecheck() {
  local relevant
  relevant=$(grep -E '(\.(ts|tsx|js|jsx|mjs|cjs|json)$|^yarn\.lock$)')
  [ -z "$relevant" ] && return 1
  # Gate iff at least one JS/TS-relevant path is NOT an inert .claude script.
  printf '%s\n' "$relevant" | grep -qvE '^\.claude/.*\.(mjs|cjs)$'
}

# When sourced (e.g. by pre-commit-typecheck-selftest.sh) expose needs_typecheck and
# stop before the gate body — which reads the hook event JSON from /dev/stdin and
# would otherwise block. Executed directly, BASH_SOURCE[0] == $0 and this is skipped.
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then return 0 2>/dev/null; fi

CWD=$(jq -r '.cwd' < /dev/stdin)
cd "$CWD" || exit 1

# Static context: the typecheck command comes from the consumer repo's
# .claude/second-shift.config.json (host repo = the topology.repos entry with
# path "."; override: SECOND_SHIFT_CONFIG). No repo, no config, or a null
# typecheck command => nothing to gate — fail OPEN (the repo has not onboarded
# a typecheck lane; a plugin-shipped hook must not block commits in arbitrary repos).
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
CFG="${SECOND_SHIFT_CONFIG:-$ROOT/.claude/second-shift.config.json}"
[ -f "$CFG" ] || exit 0
HOST=$(jq -r '.topology.repos | to_entries[] | select(.value.path == ".") | .key' "$CFG" 2>/dev/null | head -n1)
[ -n "$HOST" ] || exit 0
TYPECHECK_CMD=$(jq -r --arg h "$HOST" '.commands[$h].typecheck // empty' "$CFG" 2>/dev/null)
[ -n "$TYPECHECK_CMD" ] || exit 0

if ! git diff --cached --name-only | needs_typecheck; then
  exit 0
fi

if ! bash -c "$TYPECHECK_CMD" 2>&1; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "type-check failed — fix type errors before committing."
    }
  }'
  exit 0
fi

exit 0
```

### Scope

The full verify suite (`format`, `lint`, `type-check`, `test`) runs at stage boundaries in Stage 7. This hook is intentionally scoped to `type-check` only — it must be fast enough to not slow down the commit-per-chunk workflow in Stage 6.

If the hook denies a commit during Stage 6, fix the type error before retrying. Do not remove the hook to work around failures.

## 2. Stop — session-end type-check (informational)

Runs the configured type-check command (config `commands.<host>.typecheck`) at the end of every Claude Code session (the example below uses `yarn tsc --noEmit --pretty 2>&1 | head -30`). Unlike the PreToolUse hook, this one does **not** block — it just surfaces any lingering type errors before the session closes.

### `.claude/settings.json` configuration

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "yarn tsc --noEmit --pretty 2>&1 | head -30",
            "timeout": 120,
            "statusMessage": "Type-checking before finishing..."
          }
        ]
      }
    ]
  }
}
```

### Scope

The Stop hook has **no** `matcher` or `if` filter — it runs on every session end, regardless of whether the dev-pipeline was involved. Developers doing unrelated work in this repo will see the type-check output at session close. This is intentional: it catches type regressions before they escape the session, not just pipeline-driven ones.

The first 30 lines of output are shown (the `head -30` cap) so a broken tsc run doesn't flood the session summary.
