# Baseline

## Run 1 — 2026-08-03, opus, `underspecified-spec.md`

**5 / 5 seeded gaps reported. Class agreement 4 / 5. 4 extra guess-points, all grounded.**

| Seeded | Reported as | Class seeded → reported |
| --- | --- | --- |
| S-1 where the JSON goes, what happens to the human lines | G-3 | human → human |
| S-2 exit-code semantics under `--json` | G-2 | human → human |
| S-3 `--json` × `--receipt` | G-6 | human → human |
| S-4 `violate()` carries no id to serialize | G-1 | codebase → **human** |
| S-5 is the JSON a stable contract | G-9 | undecided → undecided |

**The one disagreement is the probe's, and it is right.** S-4 was keyed `codebase` on the
assumption that a repo convention would settle the violation-record shape. The probe checked and
found none — no other lint under `plugins/` or `scripts/` emits coded violations — so there is
nothing to derive from and the vocabulary is a decision somebody has to make. Per the README,
the key gets corrected, not the probe; the key's `codebase` row now reads as the weaker claim it
was.

**Extras (4):** the early-exit path having no defined row count; whether exit-2 usage failures
are in scope; per-violation location (and the `grep -n` change it forces through the arity
guard); jq versus hand-rolled escaping — that last one classified `codebase` with a resolved
answer and a residual fork named, which is the shape the agent doc asks for. None is padding:
each cites `file:line` and states two implementations that differ observably.

**Two facts the probe surfaced that the answer key did not have.** The live consumer
(`exitplan-ledger-gate.sh:78`) captures the lint's output as `2>&1`, so the stdout/stderr fork
in S-1 is not hypothetical — it breaks the one caller that exists. And that same hook has a
jq-absent allow-and-exit branch (`:53`), which a jq-dependent lint would silently change the
meaning of. Both were verified by hand after the run.

**Verdict:** the proxy rung fires. On a spec that a critic rung passes — stated goal, scope
boundary, ID'd testable ACs, deferred section — the probe returned four blocking forks and
declined to implement.

### Dispatch shape

Dispatched **by body**, not by registered name: `general-purpose` with
`agents/implementability-probe.md` (everything below its frontmatter) as the prompt, plus the
spec path and the read constraint. The agent ships in this same change, so no installed plugin
registers `intake-toolkit:implementability-probe` yet. Recorded because it is a real difference
from production dispatch: the frontmatter's `maxTurns: 15` was not enforced by the harness on
this run — the probe used 11 tool calls, inside the cap either way. Re-run by registered name
after the release that carries this plugin, and note it here if the number moves.

## Run 2 — 2026-11-19, opus, the record round added to the agent

Dispatched by body (`general-purpose`, the agent file below its frontmatter as the prompt), for the
same reason as run 1: the installed plugin does not yet carry the changed agent.

**Body round, `underspecified-spec.md`: 4 / 5 seeded gaps reported. Class agreement 3 / 4. 4 extras.**

| Seeded | Reported as | Class seeded → reported |
| --- | --- | --- |
| S-1 where the JSON goes, what happens to the human lines | G-3 | human → human |
| S-2 exit-code semantics under `--json` | G-4 | human → human |
| S-3 `--json` × `--receipt` | not reported; G-6 assumes the flags compose | — |
| S-4 `violate()` carries no id to serialize | G-1 | human → human |
| S-5 is the JSON a stable contract | G-7 | undecided → human |

One run per arm is inside agent variance, so the S-3 miss is a signal to re-run, not a measured
regression.

**Record round, the same spec plus a record written for this run with three planted defects:
3 / 3 reported, and the thin row too.** AC-1 departed by a `user-answered` row (reported
`departed — D-2`), AC-2's Test intent line changed to a count (reported under Changed meaning),
AC-3 missing from the `ACs:` line (reported `absent`), and a one-word Resolution (reported as a
guess-point with its fork). The probe also listed the operator's departure as a blocking
guess-point, which would re-ask a settled decision; the agent doc now says a departure a
`user-answered` row records is not a guess-point. The planted record is not committed.
