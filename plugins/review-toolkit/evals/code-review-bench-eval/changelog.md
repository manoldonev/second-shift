# code-review-bench eval — run log

Append-only. One line per arm per run, written by `bench.py`. The `model=` field is the id the CLI
resolved for the reviewer and the key two rows are compared on; `judge=` is the resolved judge id,
`calib=` the judge's agreement with the published verdicts on that set, and `set=`/`prs=`/`runs=`
say what was measured. Compare rows only within one `set`. Older rows were produced before the
harness existed; their `note` says how.

2026-10-21T13:00:00+00:00 | agent=review-lead-standalone | sha=46ca2f44 | model=claude-fable-5-1 | judge=claude-opus-5-5 | set=dev | prs=10 | runs=1 | prec=0.34 | recall=0.62 | f1=0.44 | hc=25/36 | tp=34.0 | fp=65.0 | fn=21.0 | calib=95% | voided=0 | turns=51/36.6 | wall=780s | cost=$0.00 | note="pre-harness manual run; judge batched per arm (one Opus agent), calibration 52/55 on one published tool; specialist seats on their own tiers"
2026-10-21T13:00:00+00:00 | agent=tob-differential-review | sha=46ca2f44 | model=claude-fable-5-1 | judge=claude-opus-5-5 | set=dev | prs=10 | runs=1 | prec=0.44 | recall=0.75 | f1=0.55 | hc=31/36 | tp=41.0 | fp=52.0 | fn=14.0 | calib=95% | voided=0 | turns=0/0.0 | wall=0s | cost=$0.00 | note="pre-harness manual run; skill files read from upstream commit 123037ec by an agent, not the installed plugin; judge batched per arm"
2026-10-21T13:00:00+00:00 | agent=correctness-prototype | sha=46ca2f44 | model=claude-fable-5-1 | judge=claude-opus-5-5 | set=dev | prs=10 | runs=1 | prec=0.55 | recall=0.49 | f1=0.52 | hc=26/36 | tp=27.0 | fp=22.0 | fn=28.0 | calib=95% | voided=0 | turns=0/0.0 | wall=0s | cost=$0.00 | note="pre-harness manual run; a caller-trace-only prompt that is not an arm here; judge batched per arm"
2026-10-21T13:00:00+00:00 | agent=plain | sha=46ca2f44 | model=claude-fable-5-1 | judge=claude-opus-5-5 | set=dev | prs=10 | runs=1 | prec=0.44 | recall=0.67 | f1=0.53 | hc=29/36 | tp=37.0 | fp=47.0 | fn=18.0 | calib=95% | voided=0 | turns=0/0.0 | wall=0s | cost=$0.00 | note="pre-harness manual run; judge batched per arm"
