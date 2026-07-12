# security-reviewer eval changelog

Append-only one-liner-per-run log. The harness writes a row each time
`run.sh` finishes (`agent-eval-kit/run-eval.py` `compute_summary` →
`changelog.open("a")`). Use `git diff results-*.json` against the prior keep
commit for full per-run detail (results files are gitignored — they live
only in the engineer's working tree).

Format:
`<iso-timestamp> | agent=<name> | sha=<7> | score=<%.1f%%> | <dim shortform> | runs=<N> | cost=$<x.xx> | note="<note>"`

2026-05-08T13:14:28.391979+00:00 | agent=security-reviewer | sha=95b87c3 | score=100.0% | d1=100% d2=100% d3=100% d4=100% d5=100% | runs=1 | cost=$1.27 | note="smoke-test"
2026-05-08T13:16:54.288359+00:00 | agent=security-reviewer | sha=95b87c3 | score=86.4% | d1=84% d2=81% d3=96% d4=78% d5=100% | runs=72 | cost=$64.09 | note="baseline"
2026-05-08T13:49:27.670998+00:00 | agent=security-reviewer | sha=bf95c49 | score=96.5% | d1=96% d2=96% d3=97% d4=96% d5=100% | runs=72 | cost=$57.98 | note="round-1-calibration"
2026-05-08T14:16:46.834149+00:00 | agent=security-reviewer | sha=f228069 | score=100.0% | d1=100% d2=100% d3=100% d4=100% d5=100% | runs=54 | cost=$42.43 | note="round-2-multitenant-trigger"
