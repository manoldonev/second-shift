# figma-faithful-spec-reviewer eval — run log

Append-only. One line per run, written by `agent-eval-kit/run-eval.py`. The `model=` field is the
key two rows are compared on — see `../../../review-toolkit/evals/agent-eval-kit/README.md`.
2026-08-30T14:40:05.844330+00:00 | agent=design-toolkit:figma-faithful-spec-reviewer | sha=d078707 | model=claude-opus-5 | score=20.0% | d1=0% d2=0% d3=100% | runs=1 | cost=$0.34 | note="smoke-704"
2026-08-30T14:41:41.066547+00:00 | agent=design-toolkit:figma-faithful-spec-reviewer | sha=fee85c8 | model=claude-opus-5 | score=64.2% | d1=64% d2=62% d3=67% | runs=12 | cost=$5.51 | note="704-baseline-pre-ac4"
2026-08-30T14:55:40.669279+00:00 | agent=design-toolkit:figma-faithful-spec-reviewer | sha=fee85c8 | model=claude-opus-5 | score=72.5% | d1=72% d2=71% d3=75% | runs=12 | cost=$5.72 | note="704-baseline-pre-ac4-fx-v2"
