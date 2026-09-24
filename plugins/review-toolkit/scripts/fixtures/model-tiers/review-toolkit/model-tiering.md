# review-toolkit (fixture)

This fixture carries the same parsed `## Tier alphabet` table the shipped doc does — the guard
reads the `Tier` and `Dispatch token` columns from the review-toolkit plugin root it is pointed
at (SECOND_SHIFT_PLUGIN_ROOT), so a fixture without one would make every case fail as
UNPARSEABLE-ALPHABET rather than exercising the check it is written for. Cases needing a custom
alphabet copy this tree and rewrite the table.

## Tier alphabet

| Tier      | Dispatch token | Model             | Rationale               |
| --------- | -------------- | ----------------- | ----------------------- |
| reasoning | opus           | claude-opus-4-8   | Architectural reasoning |
| code      | sonnet         | claude-sonnet-4-6 | Fast, capable code gen  |
| emit      | haiku          | claude-haiku-4-5  | Transcription-only sink |
