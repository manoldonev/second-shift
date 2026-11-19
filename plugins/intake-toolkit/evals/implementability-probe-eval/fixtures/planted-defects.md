# Planted defects — answer key for `planted-record.md`

**Withhold this file from the probe.** `planted-record.md` is a finished decision record for
`underspecified-spec.md`, written with the defects below. The record round hands the probe the
record and the spec, and the probe must report each defect.

| ID | Expected report | The defect |
| --- | --- | --- |
| P-1 | `AC-1 departed — D-2`, and D-2 not under Guess-points | D-2 (`user-delegated`, Kind `intent`) prints nothing on a clean ledger. The spec's AC-1 says the output parses as JSON. A departure that an intent row records is settled, so listing it as a guess-point is a miss. |
| P-2 | AC-2 under Changed meaning | The `AC-2` Test intent line says the output reports the number of violations. The spec's AC-2 says each violation appears in the output. |
| P-3 | `AC-3 absent` | `ACs:` lists `AC-1 AC-2` only. Nothing covers the spec's AC-3 (byte-identical output without `--json`). |
| P-4 | a guess-point on D-3, with its fork | D-3 resolves the violation shape as "JSON-encoded", which picks neither of its two options (an object or a string per violation). |

## Scoring

Record per run: defects reported / 4, and whether P-1's departure was kept off the guess-point
list. Guess-points from the spec body that the record leaves open are not misses or extras of
this key; score them against `seeded-gaps.md` when you need to.

D-4's citation (`CLAUDE.md:1`) does not prove its fact. That is not planted, and a probe that
reports it is right.
