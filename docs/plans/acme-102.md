# Plan — #102: non-JS stacks draft an all-null (false-green) table; setup-lane requirement undocumented

## Context / problem framing

`onboard`'s detection covers JS package managers plus a Makefile fallback only. For a Python
(pip/poetry/uv), bun, cargo, or go repo it correctly refuses to guess and drafts every
`commands.<id>` lane as `null`. Two gaps follow:

1. **False green at onboarding time.** An all-`null` table passes `config-lint`, `doctor`, and
   `preflight` — every lane prints `SKIP … not configured` — and `preflight.sh` still closes with
   `— pipeline-ready`. The adopter is told the pipeline is ready when nothing verifies.
2. **The setup-lane requirement is undocumented.** A fresh `git worktree add` checkout has no
   `.venv` / `node_modules` (gitignored), so verify cannot run until dependencies install. The
   mechanism for that is `commands.<id>.lanes[]` — fully implemented, but never drafted by
   `onboard` and never mentioned in the onboarding guide.

The *runtime* half is already shipped (#98): `statectl.sh` refuses `set-stage 6 --status completed`
when no verifying lane ran, and `commands.<id>.allowUnverified` is the sanctioned explicit opt-out.
This ticket adds the **early** signal — fired at onboarding, before a run ever reaches Stage 6 —
plus the missing documentation.

## Assumptions

- The Stage-6 gate and `allowUnverified` are merged on `main` and are not re-implemented here.
- `preflight.sh` is invoked by `onboard` as its final step, so a warning there reaches the adopter
  at exactly the moment the config is drafted.
- Exit-code semantics must not change: a mid-onboard repo with an unfinished table should warn,
  not hard-fail.

## Decision Ledger

| D-n | Decision | Provenance | Rationale |
| --- | --- | --- | --- |
| D-1 | Scope is the early signal only; no second opt-out mechanism | codebase-derived | #98 already ships the Stage-6 gate and `allowUnverified`; the issue body scopes itself to "the onboarding/guidance half" |
| D-2 | Verifying = non-null `lint`/`typecheck`/`test` or >=1 `extraLanes` entry | codebase-derived | Mirrors the shipped predicate in `statectl.sh` so the early warning cannot drift from the late gate |
| D-3 | The warning lives in `preflight.sh`, not `config-lint.sh` | codebase-derived | `config-lint.sh` has a binary exit contract and no WARN channel; adding one risks reddening consumer CI over a legitimately unfinished table |
| D-4 | The verdict line stops claiming `pipeline-ready` when the warning fires; exit code unchanged | codebase-derived | `warn()` does not increment `FAILS`, so a bare WARN would leave the exact false-green the issue reports |
| D-5 | The `lanes` stub lives in the JSONC review screen and the docs, never the emitted JSON | codebase-derived | `onboard` Step 4 writes pure JSON and `config-lint.sh` runs `jq empty` — a commented stub cannot persist in the file |
| D-6 | Extending detection to Python/bun/cargo/go is out of scope | codebase-derived | The issue endorses the refusal-to-guess and asks only to warn and document; detection coverage is a separate capability |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/tools/preflight.sh` — the aggregate warning + verdict line
- `plugins/dev-pipeline/skills/run/tools/preflight-selftest.sh` — AC-1/2/3 coverage
- `plugins/second-shift/skills/onboard/SKILL.md` — review-screen stub + amended key contract
- `docs/onboarding.md` — fresh-worktree dependency-install requirement

## Reuse inventory

- `warn()`, `say()`, `skipn()`, `hdr()` in `preflight.sh` — the existing severity vocabulary; the
  new message uses `warn()` verbatim rather than inventing a channel.
- `$HOST_ID` and `$CFG` — already resolved in `preflight.sh`'s Section 5; the predicate reads from
  the same two variables, no re-resolution.
- `commands.<id>.allowUnverified` — the shipped opt-out flag, reused as the suppression signal.
- `docs/config-schema.md` — the existing `lanes` reference; `docs/onboarding.md` points at it
  instead of duplicating the contract.
- No new helpers introduced.

Unverified references: none. Every path and function above was read in the worktree.

## Implementation steps

1. In `preflight.sh`, initialize an `UNVERIFIED=0` counter alongside the existing `FAILS=0`.
2. In Section 5, after the `extraLanes` loop and inside the `$HOST_ID`-present branch, compute the
   verifying-lane count per D-2 and read `allowUnverified`. When the count is `0` and the opt-out
   is not `true`, set `UNVERIFIED=1` and emit a `warn()` naming the count and the remedy
   (configure a lane, or set `allowUnverified` to make the opt-out explicit).
3. Change the verdict line so `— pipeline-ready` is printed only when `FAILS` is 0 **and**
   `UNVERIFIED` is 0; when `FAILS` is 0 but `UNVERIFIED` is 1, state plainly that the repo is not
   pipeline-ready and why. Leave `exit "$FAILS"` untouched.
4. Extend `preflight-selftest.sh` with three runs: an all-null table asserting the WARN fires and
   `pipeline-ready` is absent (AC-1); the same table with `allowUnverified: true` asserting silence
   (AC-2); a table with one verifying lane asserting silence (AC-3).
5. In `onboard/SKILL.md`, amend the `commands.<repo>` key contract to note that `lanes` is not an
   emitted key, and add a setup-lane line to the JSONC review screen example — shown as review-screen
   guidance in the object shape, with the emitted JSON unchanged.
6. In `docs/onboarding.md`, document the fresh-worktree dependency-install requirement: a worktree
   starts without installed dependencies, so a repo whose verify lanes need them must carry a
   `commands.<id>.lanes[]` setup entry, pointing at `docs/config-schema.md` for the field reference.

## Test strategy

Verify-after (infra/tooling change, no product behavior). The repo's model-free CI discovers
`*-selftest.sh` by glob, so the three new `preflight-selftest.sh` runs are the executable contract.
Each new run builds a fixture config, invokes `preflight.sh`, and greps the report for the presence
or absence of the warning and the `pipeline-ready` token.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Zero verifying lanes and no opt-out → WARN, and no `pipeline-ready` | 2, 3 | `preflight-selftest.sh` zero-lane run (AC-1) |
| AC-2 | `allowUnverified: true` → silent | 2 | `preflight-selftest.sh` opt-out run (AC-2) |
| AC-3 | At least one verifying lane → silent | 2 | `preflight-selftest.sh` configured-lane run (AC-3) |
| AC-4 | onboard surfaces a `lanes` stub; emitted JSON unchanged | 5 | — no test (covered-by-selftest) |
| AC-5 | Onboarding guide documents the fresh-worktree install requirement | 6 | — no test (non-functional) |

AC-4's emitted-JSON invariant is asserted indirectly: `onboard` emits no `lanes` key, so the
existing `config-lint` fixtures remain valid unchanged. AC-5 is prose.

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks / rollback notes

- **Warning fires on a legitimately-unfinished table mid-onboard.** Intended: that is the signal.
  It stays a WARN with an unchanged exit code, so onboarding is not blocked.
- **Predicate drift from the Stage-6 gate.** Mitigated by D-2 (same field set) and a comment at the
  call site naming `statectl.sh` as the source of truth. A future change to the Stage-6 predicate
  must update both; the selftests would not catch that, so the comment is the guard.
- **This repo's own config** sets `lint` and `test` non-null, so AC-3 holds here and its own
  preflight is unaffected.
- Rollback is a single revert; no state, schema, or config migration.

## Out-of-scope

- Extending `detect.sh` to Python/pip/poetry/uv, bun, cargo, or go (D-6) — separate issue.
- Any change to `config-lint.sh` exit semantics or a new WARN channel there (D-3).
- A second opt-out mechanism, or any change to the Stage-6 gate or `allowUnverified` (D-1).
- Emitting a `"lanes": []` placeholder into `.claude/second-shift.config.json` (D-5).
- Version bumps and `CHANGELOG.md` — derived at release time by `scripts/derive-release.sh`.
