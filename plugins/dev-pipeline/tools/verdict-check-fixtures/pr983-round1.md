verdict: needs-work
reviewed: 1be8b826dc56423f62d68b48e9ca6a2586678e59

## Decision record rows

The record is byte-identical at `7100d01b` and at the head (`git diff 7100d01b HEAD -- docs/plans/second-shift-979-decisions.md` is empty), so no row departed.

| Row | Score | Evidence |
| --- | --- | --- |
| D-1 watch primitive | honored | `run/SKILL.md:28-36`: one `Bash` call under `run_in_background` whose whole command is a bare `until grep -q 'detached run exited rc=' '<log>' \|\| ! kill -0 <pid> …; do sleep 30; done`, nothing after `done`, `Monitor` ruled out, `run.sh` untouched. Its pid matches `run.sh:277`'s printed `$!`, which is the wrapper that writes the exit line (the `nohup` → `perl` → `bash -c` exec chain keeps the pid). See W1 for a premise problem in the Monitor rejection. |
| D-2 when the watch ends | honored | `run/SKILL.md:37-43` has all three branches: exit line → step 4; no line and pid alive → re-arm, "a watch that ended is never the run's end"; no line and pid gone → report interrupted and stop. `run.sh:269-275` matches the stated premise: TERM/INT/HUP are trapped and forwarded, the wrapper waits until the child is gone, then echoes the exit line. Only SIGKILL of the wrapper leaves it out. All four cases of `A \|\| !B`: when the line lands just after `grep` and the pid is gone before `kill -0`, the loop ends with the line present, and the read-the-log step routes it to step 4. |
| D-3 144 root cause out of scope | honored | The diff holds no root-cause work and no hook or `run.sh` change. |
| D-4 no other restatement to change | honored | Only `run/SKILL.md` and the record changed; `docs/plans/second-shift-939-decisions.md:34` is untouched. Note N1: the row's "appears in prose only at…" misses `README.md:114` (and `CHANGELOG.md:1034`, which is frozen). README describes the log's last line, not the watch, and is still accurate, so "none to change" holds. |
| D-5 run.sh and tests | honored | `git diff --stat origin/main...HEAD` lists 2 files, with no `run.sh` and no selftest. No prose-presence guard was added, which is consistent with the writing-tests rules. |
| D-6 verb and trailer | honored | The PR title is `fix(dev-pipeline): the run skill names how to watch a detached run`. Commit `1be8b826` carries a `Changelog:` trailer naming the watch and the re-arm, with `Migration: none.` No frozen file is touched; `pr-gates` passes. |
| D-7 duplicate scan | honored | This is an intake-time fact with no obligation on the diff. It is the record's figure, not re-derived: my re-run of `dup-scan.sh --issue 979` was denied by this session's permission layer. |

Ticket #979's acceptance criterion ("step 3 names the watch primitive and the re-arm rule for a watch that ends early") is met at `run/SKILL.md:27-43`.

## Findings

**W1 — Warning (confidence 85), `plugins/dev-pipeline/skills/run/SKILL.md:28-36`: the named watch expires too, and step 3 sets no `timeout`.**
In this harness a `Bash` call under `run_in_background` is stopped when it reaches its `timeout` (the tool's contract: default 600000 ms, max 7200000 ms; at the limit the command is stopped and the session is re-invoked). Step 3 tells the session to issue the loop with no `timeout`, so a session that copies it gets the default. The watch then ends about every 10 minutes while the run is alive. D-2's re-arm branch keeps the run watched, so nothing is lost, but:
- a two-hour build costs about 12 wake-ups. D-1 rejected `Monitor` for "4+ wake-ups for a two-hour build, and an expiry is a routine event to tell apart from a dead run", and this primitive has the same property, only worse;
- the step's own line "Not a `Monitor`: it expires within 30 minutes, long before a run ends" implies the named loop does not expire, which is false as written.

Fix: name `timeout: 7200000` (the harness maximum) on the call, and say that a stop at that bound is the routine re-arm case for a run longer than two hours. This is statically traced from the tool's documented contract, not executed: my probe of the loop across separate Bash calls was denied by this session's permission layer. This is not a row violation (D-1's resolution is implemented as worded), but it is the defect the ticket exists to remove: a watch that ends while the run is alive.

**N1 — note.** See D-4: README.md:114 also states the log's last line. It needs no change.

**N2 — nit (confidence 60, suppressed).** Step 3 quotes the detach line as `detached: pid <pid> · log <log>`, but `run.sh:277` also prints `· its last line will be 'detached run exited rc=<n>'`. The quoted part is an accurate prefix and does no harm.

**Suppressed (below 80).** `kill -0` across separate Bash calls under a sandboxed harness could fail with EPERM and read as "pid gone" (confidence 40): no sandbox is configured in the user settings, and I could not probe it. PID reuse after a SIGKILL could keep the loop alive (confidence 30): it is an edge case and a human's read per D-2.

## review-lead (panel: pipeline default, scope-completeness only; no opt-ins taken)

The panel is the pipeline default: scope-completeness only. The record has no `review panel` row and this repo has no `reviewers.default[]`. I took no opt-in of my own: the diff is skill prose and a record, with no auth/tenancy/query, web-component or co-located-spec surface. The lead pass covered performance, maintainability, complexity, test coverage and security.

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Lead pass — ✅ | 0 | — |
| Performance | Lead pass — ✅ | 0 | — |
| Complexity | Lead pass — ✅ | 0 | — |
| Maintainability | Lead pass — ❌ | 1 (W1) | 85 |
| Test Coverage | Lead pass — ✅ (prose-only diff; D-5) | 0 | — |

Data provenance: none: the diff consumes no newly read persisted field. a11y and design-fidelity were not routed: no changed path matched the default `reviewers.webComponentGlobs` (`apps/web/**/*.{tsx,jsx}`), and the ticket has no design frames, so there was nothing to render.

**Ready to merge?** With fixes. W1 is a one-line change to step 3.

## Process notes

- The fan-out ran from the unmodified plugin-cache copy (`review-toolkit/10.1.0/workflows/code-review.mjs`, run `wf_50c54c00-ba6`), not a copy in the evidence directory: both `cp` and Write into `.claude/pipeline-state/run-979/…` were denied as sensitive-path edits by this session's permission layer.
- The scope reviewer returned approve after 2 tool uses. Its result stands, and the row scores above are my own reading.
- CI `selftests` and `lint-and-selftests` were still pending when I reviewed.

revised after reading the build's account: no score or finding changed. The PR body says the selftest sweep ran with "47 scored, 0 failed" using `env -u CLAUDE_CODE_SESSION_ID SKIP_STRESS=1 bash tools/run-selftests.sh …`. The scheduler lists that exact command among the build's permission denials, and `/tmp/sweep-979.log` does not exist on disk. The claim cannot be verified from the evidence here, so the PR's green rests on CI. The body states the departures (none) and rebuttals (none) consistently with the record.
