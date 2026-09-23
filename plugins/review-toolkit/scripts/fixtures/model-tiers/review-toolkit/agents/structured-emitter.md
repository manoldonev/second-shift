---
name: structured-emitter
description: Fixture stand-in for the transcription-only schema sink. Exists so the selftest can cover a dispatch that re-states its tier INLINE (model: 'haiku') inside a workflow file whose scalar default is a different tier.
tools: []
model: haiku
effort: low
maxTurns: 2
---

Fixture agent. Not dispatched; only its `model:` frontmatter is read.
