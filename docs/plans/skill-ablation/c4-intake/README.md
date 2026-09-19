# c4-intake — `intake-orchestrator` and `intake-interviewer`, addendum 3

Numbers only, per [`docs/skill-ablation-addendum-3.md`](../../../skill-ablation-addendum-3.md):
no role text, detector or arm output lands here. The raw captures are in the private bench
repository at `ab44a0fc3b45cf9a2bb37504f3effc2986ebc5dd`, under `intake/results/2026-09-19/`; each
row's `sha256_16` is the first 16 hex digits of its capture's sha256.

Run 2026-09-19 on Claude Code 2.1.278, `--model opus` resolving to `claude-opus-5` in all 36
captures. The runner is `intake/run-arm.sh` at its registered hash, 12 runs at a time.

[`runs.tsv`](runs.tsv): one row per run. `classify_rc` is `tools/classify-capture.sh`'s exit (0 =
complete). `skill_calls` counts `Skill` tool calls naming the skill under test. `hits` is
`score.py`'s per-gap output, 1 = caught.

## Apparatus facts

- **36 of 36 runs valid**: exit 0, `classify_rc` 0, and every orchestrator capture carries a
  `CHILDREN` section. No re-run was needed.
- **Invocation delivered 18 of 18 kit runs** (bar: 2 of 3 per role); **0 of 18 bare runs**.
- **The orchestrator's fan-out ran in 9 of 9 kit runs**: one `spec-reviewer` and one
  `codebase-explorer` dispatch each, plus `implementability-probe` in 3. Kit orchestrator captures
  carry 2–4 `result` events against the bare arm's 1; the last one governs, as registered.
- **Mean wall-clock per run:** orchestrator kit 165 s, bare 63 s; interviewer kit 58 s, bare 43 s.
- The tool set was not restricted: no `--allowedTools` was passed, and none was registered.

## Tally (majority of 3 per role)

| skill | kit caught | bare caught | registered verdict | adjudicated |
| --- | --- | --- | --- | --- |
| `intake-orchestrator` | 6 / 6 | 6 / 6 | `delete` — bare ≥ kit and all 6 | `no basis — ceiling` |
| `intake-interviewer` | 6 / 6 | 6 / 6 | `delete` — bare ≥ kit and all 6 | `no basis — ceiling` |

Every gap was caught in 3 of 3 runs of both arms, not merely on majority. With both arms at the
ceiling, the comparison does not separate them. The operator ruled on the PR
(https://github.com/manoldonev/second-shift/pull/860#issuecomment-5742243801) that the result is
`no basis — ceiling`, not the registered rule's `delete`. The departure and its reasoning are in
`docs/skill-ablation.md` §3.

## Detector audit

The detectors are deterministic and govern. Every bare-arm match was read after scoring, and each
is a real catch — the bare sessions named the shared pricing helper, said the business settings
carry no default to take the new value from, named the mock handlers and seed, the toggle constants
file, and said that workstreams 2 and 3 of the template epic were already built.

The vacuous-child rows (O3) never scored through their *avoidance* path. The child detector matched
in every bare O3 run — on note lines the `CHILDREN` parser ran into when a run's `NOTES` header was
not a bare line, or on passing mentions of the existing "Archived" chip and "Show archived" switch.
Every O3 catch was therefore carried by the flag detector, and each flag match was read: every bare
run states in so many words that workstreams 2 and 3 are "already built" or "already done", and cuts
no child for either. One flag match in o3-bare-r1 is incidental (a sentence holding "archived" and
"already" about something else); the same run's explicit "already done" statement for archiving
stands independently, so the catch holds.
