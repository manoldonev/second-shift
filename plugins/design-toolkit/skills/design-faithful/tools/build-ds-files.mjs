#!/usr/bin/env node
// design-faithful — offline build driver for the design-system push.
//
// Reads the repo's global token CSS, assembles the design-system card set
// (buildDesignSystem), diffs it against whatever is already in the output dir (planSync), applies
// the delta, and prints a manifest. This is the OFFLINE analogue of the live DesignSync push: it
// produces the exact components/<name>/index.html bytes a human/agent then pushes from an
// interactive session (see ../PUSH.md), and — run twice — demonstrates the delta-only idempotency
// AC without needing DesignSync auth.
//
// buildDesignSystem is domain-empty by default (token cards only); a consumer supplies its own
// component preview specs + token roles via the `previews`/`ramps`/`typeScale` inputs, sourced
// from its design-system reference. See fixtures/component-previews.mjs for a worked example.
//
// Usage:  node tools/build-ds-files.mjs <globals-css-path> [outDir]
//   globals-css-path — the repo's global token CSS file, as declared in the consumer repo's
//                      .claude/second-shift/design-tokens/*.md reference.
//   outDir defaults to <skill dir>/.out/design-system (gitignored).

import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync, readdirSync, statSync } from 'node:fs'
import { join, dirname, relative } from 'node:path'
import { fileURLToPath } from 'node:url'

import { buildDesignSystem } from '../lib/component-previews.mjs'
import { planSync } from '../lib/sync-plan.mjs'

const here = dirname(fileURLToPath(import.meta.url)) // …/design-faithful/tools
const GLOBALS = process.argv[2]
const outDir = process.argv[3] || join(here, '..', '.out', 'design-system')

if (!GLOBALS) {
  console.error('usage: node build-ds-files.mjs <globals-css-path> [outDir]')
  console.error("  globals-css-path — the repo's global token CSS file (see .claude/second-shift/design-tokens/*.md)")
  process.exit(1)
}

/** Recursively read an output dir into the {path,content}[] shape planSync expects. */
function readExisting(dir) {
  if (!existsSync(dir)) return []
  const out = []
  const walk = (abs) => {
    for (const entry of readdirSync(abs)) {
      const p = join(abs, entry)
      if (statSync(p).isDirectory()) walk(p)
      else out.push({ path: relative(dir, p).split('\\').join('/'), content: readFileSync(p, 'utf8') })
    }
  }
  walk(dir)
  return out
}

const globalsCss = readFileSync(GLOBALS, 'utf8')
const local = buildDesignSystem({ globalsCss })
const remote = readExisting(outDir)
const plan = planSync({ local, remote })

console.log(`design-faithful — design-system build`)
console.log(`  source : ${relative(process.cwd(), GLOBALS)}`)
console.log(`  outDir : ${relative(process.cwd(), outDir)}`)
console.log(`  plan   : ${plan.writes.length} write, ${plan.deletes.length} delete, ${plan.unchanged.length} unchanged`)

// Apply deletes (stale cards no longer emitted), then writes.
for (const path of plan.deletes) {
  rmSync(join(outDir, path), { force: true })
  console.log(`  - ${path}`)
}
for (const { path, content } of plan.writes) {
  const abs = join(outDir, path)
  mkdirSync(dirname(abs), { recursive: true })
  writeFileSync(abs, content)
  console.log(`  + ${path}`)
}

if (plan.writes.length === 0 && plan.deletes.length === 0) {
  console.log(`  ✓ no changes — design system already in sync (idempotent re-run)`)
}
console.log(`  ${local.length} cards total`)
