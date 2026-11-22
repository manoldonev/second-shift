Rows of the pass-1 completeness eval, one per arm and fixture, appended by `eval.py`. The format is in `README.md`.

2026-11-22T18:07:55.870655+00:00 | arm=pass-1 | fixture=tuning | sha=6926a186 | prompt=d9a7250b7e | model=claude-opus-5-5 | judge=claude-sonnet-5-5 | runs=5 | detect-A=5/5 (3,3,3,3,3) | false-claims=0.0 (unkeyed 0.2, per-rule 0.0) | tag=5/5 | voided=0 | turns=20/16.4 | wall=168s | cost=$5.55 | note="baseline; the plant-a cell"
2026-11-22T18:13:34.448368+00:00 | arm=pass-1 | fixture=tuning | sha=6926a186 | prompt=d9a7250b7e | model=claude-opus-5-5 | judge=claude-sonnet-5-5 | runs=5 | detect-B=5/5 (3,3,3,3,3) | clean-twin=5/5 | approve-twin=0/5 (false 0, per-rule 0, other 5) | false-claims=0.0 (unkeyed 0.0, per-rule 0.0) | tag=5/5 | voided=0 | turns=27/20.3 | wall=305s | cost=$14.80 | note="baseline; the plant-b and twin cells"
2026-11-22T18:29:05.106883+00:00 | arm=plain | fixture=tuning | sha=6926a186 | prompt=6dd0676ebf | model=claude-opus-5-5 | judge=claude-sonnet-5-5 | runs=5 | detect-A=5/5 (3,3,3,3,3) | clean-twin=5/5 | approve-twin=4/5 (false 0, per-rule 0, other 1) | false-claims=0.0 (unkeyed 0.0, per-rule 0.0) | tag=5/5 | voided=0 | turns=25/15.2 | wall=272s | cost=$10.36 | note="baseline"

Notes on the three rows of 2026-11-22 (`sha=6926a186`):

- The two `arm=pass-1` rows are one run set: the first cell ran alone so that the paths its sessions saw could be checked before the other cells started. No session's path named the eval, the arm or the variant, and every read stayed inside the run's tree.
- Hand read of all 25 drafts: the voted result matches the hand read in every run. Each of the 15 planted runs has a `[blocker]` that names the planted criterion (as not implemented on `plant-a`, as untested on `plant-b`), and no draft makes a false completeness claim.
- The one `unkeyed` claim (`pass-1`, `plant-a`, run 2, second finding) is a test-coverage note on a selftest title, not a claim about a criterion. By hand it is class `other`.
- `approve-twin=0/5` on `pass-1` is not a completeness result. All five twin drafts report the same correctness blocker in the comment-counting tool (a bot that is enabled with no app name is not excluded from the count). 6 of the 10 planted `pass-1` drafts report it too, and 1 of 5 `plain` twin drafts reports it as a note. Whether it is a true defect was not checked here.
- `detect-A` is 5/5 on both arms, so this fixture shows no difference between the arms, and it cannot show an improvement: it is at its ceiling.
- No prompt was tuned on this fixture before these rows.
