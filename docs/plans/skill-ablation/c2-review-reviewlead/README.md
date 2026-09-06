# Comparison 2 evidence — the `review-lead`-loaded re-measurement

A **sibling** of [`../c2-review/`](../c2-review/), not a revision of it. Arm 2b's directory stays
byte-frozen: it is a correct description of what the pinned run produced under the construction it
names, and no file from one construction should be mistakable for a file from the other.

Registered in advance at
[`docs/skill-ablation-addendum-2.md`](../../../skill-ablation-addendum-2.md); results reported into
[`docs/skill-ablation.md`](../../../skill-ablation.md) §2 and §5.

- `ablated-control-654-review.md` — the control arm: the full unablated 127-line `review-lean` at
  `8d5d0897`, against C2-a (#654 @ `cfba102`), n=3, every replicate verbatim under its own `## r<n>`
  heading. It records the realised invocation, the per-run apparatus table, both void-condition
  adjudications, and the `--allowedTools` observation.
- `ablation-units.tsv` — the machine-readable per-unit result.

**There are no `ablated-U-5-` or `ablated-R-3-` files, and that is the result.** The arm exited
`no basis` at the control, so under §C — *a void control does not proceed to the ablation runs* —
the two ablated arms were never launched. Recording an empty file per arm would suggest a run that
produced nothing; there was no run.

## What was measured, in one paragraph

Arm 2b scored U-5 and R-3 `no-effect` under a harness that never loaded `review-lead`, and #800
kept both units on that inherited caveat rather than a measurement. This arm re-ran arm 2b's frozen
harness with exactly one addition — `--plugin-dir <the shipping review-toolkit>` — so that
`review-lead` was **discoverable**. It was: every run's `init` event lists
`review-toolkit:review-lead`, all 18 reviewer agents, and both the `Skill` and `Task` tools. No run
used any of them. Availability was delivered; invocation was not, 0 of 3, against a bar of 2 of 3
registered before the runs.

The finding-void condition cleared independently — the control reproduced the C2-a ground-truth
blocker in 2 of 3 runs — so the exit is owed to the delivery condition alone, not to a control that
could not review.

## The commands

No runner script is checked in, per the standing rule at [`../README.md`](../README.md). The
realised invocation is in `ablated-control-654-review.md`; the reproduction path is:

```bash
# 1. throwaway clone, detached at the sample's head
git clone --no-checkout <this repo> /private/tmp/c2b803/clone
git -C /private/tmp/c2b803/clone checkout --detach cfba1022

# 2. the apparatus: the SHIPPING review-toolkit, copied verbatim so it cannot move under the batch
cp -R plugins/review-toolkit /private/tmp/c2b803/review-toolkit   # git tree 549b0d1768

# 3. the subject: the pinned SKILL, unablated for the control
git show 8d5d0897:plugins/dev-pipeline/skills/review-lean/SKILL.md > skill-control.md
#    each ablated arm would be that file with one registered line range deleted:
#      sed '48,55d'    -> U-5        sed '110,114d'  -> R-3

# 4. the prompt: SKILL text, then prompt-template.txt verbatim, then the pinned diff
git -C /private/tmp/c2b803/clone diff dfd68a47..cfba1022 > diff.txt
cat skill-control.md ../c2-review/prompt-template.txt diff.txt > prompts/control.txt

# 5. the run — see ablated-control-654-review.md for the full env scrub
# 6. every capture is classified before it is read
bash tools/classify-capture.sh <capture>
```

Assembled-prompt sha256, so a re-run can prove it fed the same bytes:

| arm | prompt | sha256 |
| --- | --- | --- |
| control | 116853 B | `e8b0c82b13e84f6f2b5b2e668254ab29dde0ad2d828a42b1c9b7994416337269` |
| U-5 (assembled, never run) | 116158 B | `ec438834186300b28e95a1f287316ae7f208742cedc42b2093c6e777b5f84ac3` |
| R-3 (assembled, never run) | 116376 B | `2b278c9cda97d5a376a3cd9575ef80c24c4e111799f9496470a1d826424e89f3` |

The two ablated prompts were assembled before the control was adjudicated and are hashed here so
the *reason* they were not run is checkable: the arm stopped at the control, not for want of a
prompt.

## Bounds of this construction

- **The whole `review-toolkit` plugin loads**, not `review-lead` alone — three skills and 18
  agents. It is the minimal loadable unit that makes `review-lead` functional; a trimmed plugin dir
  would measure something that does not ship. So this arm cannot attribute anything to `review-lead`
  alone.
- **The construction is deliberately not era-consistent.** The measured `review-lean` text is pinned
  at `8d5d0897` and the sample at `cfba102`, while the loaded implementation is current. Loading the
  clone's own `review-toolkit` was rejected at registration: its `review-lead` predates #730 and
  carries no rule naming R-3, which would have re-created the confound one layer down.
- **Cross-batch comparison against arm 2b is a sighting, not a score.** The two controls differ by
  one flag but are days and two CLI versions apart (2.1.241 → 2.1.263), and §C already recorded that
  its own three control runs disagreed with each other.
