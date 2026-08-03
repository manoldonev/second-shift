# Seeded gaps — answer key for `underspecified-spec.md`

**Withhold this file from the probe.** It exists so an operator can score a probe run without
re-deriving what was deliberately left out. Every gap below is a real fork: two defensible
implementations that produce observably different artifacts.

The fixture spec is otherwise well-formed on purpose — it has a stated goal, a scope boundary,
ID'd testable ACs, and a deferred section. A reviewer rung would pass it. That is the point: the
probe measures discovery coverage, not spec hygiene, and the two come apart.

| ID | Class | The fork |
| --- | --- | --- |
| S-1 | human | **Where the JSON goes, and what happens to the human lines.** `--json` could replace stdout, or write to a path, or emit JSON on stdout while the existing `ledger-lint: N ledger row(s)` / `OK` lines keep printing — the third breaks every caller that pipes stdout to `jq`. The spec says "emits JSON" and nothing else. |
| S-2 | human | **Exit code semantics under `--json`.** Today a violation exits 1. A machine-readable mode can keep that, or exit 0 on "a report was successfully produced" and let the caller read `violations`. Both are common; CI callers break differently under each. AC-1/AC-2 constrain the document, never the exit code. |
| S-3 | human | **Whether `--json` composes with `--receipt`.** The receipt mode reports open regions as well as ledger rows. If the two flags combine, open-region violations need a place in the schema; if they do not, the combination has to be rejected rather than silently emitting a half-report. |
| S-4 | human | **The violation record has no id to serialize.** `violate()` takes a single English string; nothing in the script carries a rule id or the offending `D-n` as data. "Enough for a caller to act on it without reading English" therefore requires either widening `violate()`'s signature at every call site or re-parsing the message it already built — and then minting the vocabulary itself. *(Keyed `codebase` originally, on the assumption that some other lint in the repo had settled a violation-record shape to copy. Run 1 checked and found none; corrected per the README's rule that a probe defending a class with a citation beats the key.)* |
| S-5 | undecided | **Is the JSON a stable contract?** If callers outside this repo may consume it, the schema needs a version key and a change discipline; if it is an internal convenience, it can change freely. Nobody has decided, and the answer changes what ships. |

## Scoring

A probe run **reports** a seeded gap when its output names the same fork — not necessarily the
same class, and not in the same words. Judge on the fork, since that is what makes a gap
actionable.

Record per run: gaps reported / 5, class agreement, and the count of extra guess-points. Extras
are not automatically wrong (the fixture is a real spec against a real script, so real gaps
outside the seeded set exist), but a large extra count against a small hit count is the
padding failure mode the agent doc warns about.
