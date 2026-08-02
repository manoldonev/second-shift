# second-shift #92 — bot wrapper resolves from config, never from the operator's shell

## Problem

When `tracker.bot.enabled` is true but the bot env var is unset, the SKILL.md
pre-flight gate aborts with an empty path:

```
[pre-flight] FAIL: bot wrapper missing or non-executable at
```

The wrapper is present; the gate never resolved it. Resolution lives in four
hand-copied ladders, and the pre-flight site has none. `tracker.bot.envVar` is
schema-declared and inert.

## Decision (locked — ledger `.claude/pipeline-state/92-ledger.md`)

| ID | Decision |
| --- | --- |
| D-1 | Make `tracker.bot.envVar` live (not delete) |
| D-2 | Single passthrough tool `tools/gh-bot.sh`, not a sourced prelude |
| D-3 | Convert all prose `$GH_BOT` write sites in this change |
| D-4 | `enabled` false/absent → gates skip bot check |
| D-5 | New `gh-bot-selftest.sh` + doctor `(d7)` extract-and-execute group |
| D-6 | Drop the install↔claim config-dir lockstep DROPPED note (one copy) |
| D-8 | Commit verb `feat(dev-pipeline):` |

## Scope

1. **`tools/gh-bot.sh`** — `--status` / `--path` / passthrough; three-rung ladder
   (configured envVar → wrapperPath → default); tokens
   `disabled|ok|unset-var|missing-file|not-executable`.
2. **Gates** — SKILL.md pre-flight `(1)` and `pipeline-doctor.sh` block 3 classify
   via `--status`; distinct remediations; `disabled` skips.
3. **Callers** — `claim-issue.sh`, `pipeline-cost-block.sh`, `install-gh-bot.sh`
   resolve via `gh-bot.sh --path` (no private ladder).
4. **Prose** — stage/skill write sites invoke the passthrough; Bot Identity docs
   the sanctioned form; drop the `cost-tracking-setup.md` "does not yet honor" note.
5. **Tests** — `gh-bot-selftest.sh` + doctor `(d7)`; no scenario-liveness (no
   terminal write).

## Acceptance Criteria

- **AC-1** `tools/gh-bot.sh` exists with three modes and the three-rung ladder;
  `--status` emits exactly one of the five tokens.
- **AC-2** Env var unset + resolvable wrapper → `--status` is `ok`; pre-flight
  passes; no branch renders an empty path.
- **AC-3** `unset-var`, `missing-file`, and `not-executable` each produce a
  distinct remediation in pre-flight and doctor block 3.
- **AC-4** `tracker.bot.enabled` false/absent → pre-flight and doctor block 3
  skip the bot check without failing.
- **AC-5** Configured `tracker.bot.envVar` is honored; no site hardcodes `GH_BOT`
  except as the documented default name.
- **AC-6** `claim-issue.sh`, `pipeline-cost-block.sh`, and `install-gh-bot.sh`
  contain no private wrapper-resolution ladder; lockstep stays green.
- **AC-7** No stage/skill prose depends on an ambient bot env var for a write;
  each write invokes the passthrough.
- **AC-8** `gh-bot-selftest.sh` covers the §5 cases; doctor carries `(d7)`;
  shellcheck + `*-selftest.sh` sweeps are green.
