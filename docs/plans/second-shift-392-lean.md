# lean-gate milestone 3 passes with zero verifying lanes and no explicit opt-out

Spec of record for issue #392. The definition of done is the `AC-n` set below.

## Problem

`lean-gate.sh` milestone 3 (`cmd_3`) skips every null fixed key (`lint`/`typecheck`/`test`)
with a printed notice and never reads `commands.<host>.allowUnverified`. A lean run invoked
from a repo whose config has no command table for the resolved host slug (or no config at
all — `REPO_SLUG` then defaults to `acme`) skips every lane and still calls `pass_milestone 3`,
reporting green having verified nothing. The staged lane already closed this same hole for
`verifyctl.sh`/`statectl.sh` (#98) and `preflight.sh` (#102); the lean lane never got the
matching guard.

No pre-flight ledger exists for this issue. Open regions: none — the issue states the
semantics mirror an existing contract (#98).

## Files in scope

`plugins/dev-pipeline/skills/run-lean/lean-gate.sh` (`cmd_3`), its selftest
(`lean-gate-selftest.sh`), `docs/config-schema.md`, and this spec.

**Deliberately NOT** `verifyctl.sh`/`statectl.sh`/`preflight.sh` — those already carry the
guard (#98/#102); this issue is the lean lane's independent copy of the same check against
its own config reader, not a refactor toward a shared implementation.

## Acceptance criteria

- **AC-1** (oracle — `lean-gate-selftest.sh`): a config with no `commands.<host>` entry (or no
  config file at all, so `REPO_SLUG` resolves the default `acme`) reds milestone 3, naming the
  resolved host slug, the config path read, and `allowUnverified`. The same fixture with
  `commands.<host>.allowUnverified: true` set instead passes, with a printed notice.
- **AC-2** (oracle — selftest): a config with exactly one fixed key (`lint`/`typecheck`/`test`)
  set to a real command leaves the guard inert — milestone 3 behaves exactly as before this
  change (no mention of `allowUnverified` in its output).
- **AC-3** (oracle — selftest): a config whose only verifying surface is a when-scoped
  `extraLanes` entry, evaluated against a diff that matches nothing, still passes — the guard
  keys on whether a verifying lane is *configured*, not whether it *ran*.
- **AC-4** (oracle — diff-scoped mutation sweep): the new guard's mutants are killed by the
  paired suite (`lean-gate-selftest.sh`); any generic survivor ordinal re-keyed by the edit is
  re-baselined in the same diff.
- **AC-5** (critic): `docs/config-schema.md`'s `allowUnverified` row names the lean gate
  (milestone 3) as a consumer, alongside the existing Stage-6/`preflight` mentions; the PR
  carries a `Changelog:` trailer.

## Design

### What counts as "configured"

Per the issue body: the fixed keys (`lint`/`typecheck`/`test`) and `extraLanes` — evaluated by
**array length**, not by whether a `when`-scoped entry ends up running on this diff (AC-3).
Setup `lanes[]` are INFRA-classed and do not count (they set up the environment; they do not
verify it). The mutation sweep is repo-carried (keyed on `tools/mutation-sweep.sh`'s presence
in the tree), not config, and stays out of the definition — its presence or absence neither
trips nor silences the guard, matching the staged lane's semantics where the `allowUnverified`
valve is inert as soon as any verifying lane is configured (#98).

### Where the check lands in `cmd_3`

`cmd_3` already loops the fixed keys (`lean-gate.sh:964-970`) and separately computes
`el_count`, the `extraLanes` array length, before running any of them
(`lean-gate.sh:977-983`). The fixed-keys loop gains one line: set a new `any_verifying=1` flag
the first time a key's command is non-empty (i.e., right after the existing null-skip
`continue`). Immediately after `el_count` is computed — before the `extraLanes` execution block
and before the mutation sweep — a new check runs:

```bash
if [ "$any_verifying" -eq 0 ] && [ "$el_count" -eq 0 ]; then
  local allow_unverified
  allow_unverified="$(cfg ".commands[\"$REPO_SLUG\"].allowUnverified" 'false')"
  if [ "$allow_unverified" = "true" ]; then
    say "milestone-3: no verifying lane configured for '$REPO_SLUG' ... allowUnverified opt-out is set (config: $CONFIG)."
    append_line "$(now_iso) | milestone-3 | skipped | no verifying lane configured — allowUnverified opt-out"
  else
    fail_milestone 3 "no verifying lane configured for '$REPO_SLUG' ... config read from $CONFIG. Configure a verify lane, or set commands.$REPO_SLUG.allowUnverified=true to declare the opt-out."
    return $?
  fi
fi
```

Placing it before the mutation sweep means a run with zero configured lanes and no opt-out
reds immediately rather than after spending a sweep run it was always going to discard —
`fail_milestone` returns before line 1037's `sweep=...` is reached. `cfg` already returns the
default (`false`) when `$CONFIG` does not exist at all (`lean-gate.sh:190-197`), so the
"no config file" and "config file present, key absent" cases share one code path and one test.

### Message contents (AC-1)

The red message names all three things the issue asks for: `$REPO_SLUG` (the resolved host
slug), `$CONFIG` (the path actually read), and the literal string `allowUnverified` (the
opt-out key) — mirroring `preflight.sh`'s existing wording for the same condition
(`tools/preflight.sh:346`). The green-with-notice path reuses the `append_line ... | skipped |
...` pattern the mutation-sweep-absent notice already uses two lines below it
(`lean-gate.sh:1043-1044`), so both "legitimate skip" notices in this function look alike.

### Docs (AC-5)

`docs/config-schema.md`'s `commands` row already lists `allowUnverified`'s Stage-6 and
`preflight` consumers (`docs/config-schema.md:9`); it gains a third clause naming the lean
gate's milestone 3, citing #392 the way the existing clause cites #98.

## Test strategy

Verify-after, in `lean-gate-selftest.sh` — the file's own convention (every AC is a case in
the shared behavioral suite, no co-located unit test). The shared fixture `$CFG`
(`lean-gate-selftest.sh:60-68`) currently configures zero fixed keys and no `extraLanes`, which
several existing cases downstream (`(i)`, `(o)`) rely on reaching milestone 3's *green* gate —
under the new guard that config would now red. `$CFG` gains `"allowUnverified": true` so those
pre-existing cases (about the mutation-sweep-absent notice, the dead `build` key, and a full
`all` sweep leaving the verdict record untouched — none of which are about this guard) continue
to exercise the code paths they were written for. A new case group derives configs from `$CFG`
with the opt-out stripped (AC-1), with one real key added (AC-2), and with a when-scoped,
diff-missing `extraLanes` entry added (AC-3).

## Out of scope

Refactoring `verifyctl.sh`/`preflight.sh` and `lean-gate.sh` onto one shared config reader —
the two lanes already read `second-shift.config.json` independently by design; this issue adds
the lean lane's own copy of a check the staged lane already has, not a merge of the two.
