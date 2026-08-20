# dev-pipeline (fixture)

(The anonymous-executor tier note lived here until #574 retired mutation-gate.mjs and
its EXECUTOR_MODEL lockstep; the fixture doc stays because the resolver copies it.)

This fixture carries the same parsed `## Tier alphabet` table the shipped doc does — the guard
reads the `Tier` and `Dispatch token` columns from whichever dev-pipeline root it resolves, so a
fixture without one would make every case fail as UNPARSEABLE-ALPHABET rather than exercising the
check it is written for. Cases needing a custom alphabet copy this tree and rewrite the table.

## Tier alphabet

| Tier      | Dispatch token | Model             | Rationale               |
| --------- | -------------- | ----------------- | ----------------------- |
| reasoning | opus           | claude-opus-4-8   | Architectural reasoning |
| code      | sonnet         | claude-sonnet-4-6 | Fast, capable code gen  |
| emit      | haiku          | claude-haiku-4-5  | Transcription-only sink |
