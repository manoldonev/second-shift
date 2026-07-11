// design-faithful — emit + sync-plan tests (#200 push direction).
//
// Zero external deps (node:test + node:assert) — the .claude/ tooling convention (mirrors
// lib/extractor.test.mjs). Run: node --test .claude/skills/design-faithful/lib/emit.test.mjs

import { test } from 'node:test'
import assert from 'node:assert/strict'

import { dsCardMarker, emitCard, escAttr } from './emit-card.mjs'
import { tokenRootCss, emitTokenCards, TOKEN_RAMPS } from './emit-tokens.mjs'
import { buildDesignSystem, COMPONENT_PREVIEWS, typeScaleCard } from './component-previews.mjs'
import { planSync } from './sync-plan.mjs'
import { parseDsCard } from './html-markup.mjs'

// A trimmed but real slice of apps/web/src/app/globals.css: the leading brace-less @tailwind
// lines (which pollute the first selector), the dark-first :root,.theme-cold ramp, AND the
// .theme-cold.lighten light-mode block (whose values must NOT leak into the emitted :root).
const GLOBALS_FIXTURE = `@tailwind base;
@tailwind components;
@tailwind utilities;

/* Cold Workshop tokens */
:root,
.theme-cold {
  --bg: oklch(0.18 0.01 240);
  --surface: oklch(0.21 0.011 240);
  --surface-2: oklch(0.24 0.012 240);
  --surface-3: oklch(0.28 0.013 240);
  --ink: oklch(0.96 0.005 240);
  --ink-2: oklch(0.78 0.012 240);
  --ink-3: oklch(0.55 0.012 240);
  --ink-4: oklch(0.40 0.012 240);
  --line: oklch(0.30 0.012 240);
  --line-2: oklch(0.36 0.013 240);
  --accent: oklch(0.74 0.13 215);
  --accent-soft: oklch(0.74 0.13 215 / 0.18);
  --accent-ink: oklch(0.20 0.02 215);
  --hi: oklch(0.74 0.16 152);
  --good: oklch(0.74 0.13 175);
  --mod: oklch(0.78 0.16 80);
  --low: oklch(0.72 0.18 50);
  --shadow: 0 1px 0 oklch(1 0 0 / 0.04) inset, 0 8px 24px -12px oklch(0 0 0 / 0.6);
  --grid: oklch(1 0 0 / 0.06);
  --radius: 0.75rem;
}

.theme-cold.lighten {
  --bg: oklch(0.97 0.005 240);
  --surface: oklch(1 0 0);
  --ink: oklch(0.18 0.01 240);
}
`

test('dsCardMarker omits empty fields and escapes quotes', () => {
  assert.equal(dsCardMarker({ group: 'Tokens', name: 'Surfaces' }), '<!-- @dsCard group="Tokens" name="Surfaces" -->')
  // empty/absent subtitle omitted
  assert.equal(dsCardMarker({ name: 'X', subtitle: '' }), '<!-- @dsCard name="X" -->')
  assert.equal(escAttr('a "b" <c>'), 'a &quot;b&quot; &lt;c&gt;')
})

test('emitCard produces a valid first-line @dsCard marker that round-trips through parseDsCard', () => {
  const { path, content } = emitCard({
    group: 'Composites',
    name: 'Demo',
    subtitle: 'one / two',
    slug: 'demo-card',
    tokenCss: ':root { --bg: oklch(0.18 0.01 240); }',
    body: '<button>Hi</button>'
  })
  assert.equal(path, 'components/demo-card/index.html')
  // marker is line 1
  assert.match(content.split('\n')[0], /^<!-- @dsCard /)
  const card = parseDsCard(content)
  assert.deepEqual(card, { group: 'Composites', name: 'Demo', subtitle: 'one / two' })
})

test('emitCard marker round-trips even with a quoted subtitle (no corruption)', () => {
  const { content } = emitCard({
    group: 'G',
    name: 'N',
    subtitle: 'He said "go"',
    slug: 'quoted',
    body: '<i>x</i>'
  })
  const card = parseDsCard(content)
  // The escaped form is the locked behavior; the key point is group/name are NOT clobbered
  // by the embedded quote and subtitle parses as a single field.
  assert.equal(card.group, 'G')
  assert.equal(card.name, 'N')
  assert.equal(card.subtitle, 'He said &quot;go&quot;')
  assert.ok(!/subtitle="[^"]*"[a-z]/.test(content), 'marker not split into spurious keys')
})

test('emitCard rejects a non-kebab slug and a missing name', () => {
  assert.throws(() => emitCard({ name: 'X', slug: 'Bad Slug', body: '' }), /kebab-case/)
  assert.throws(() => emitCard({ slug: 'ok', body: '' }), /name is required/)
})

test('tokenRootCss takes the dark-first ramp only — no .lighten leak', () => {
  const root = tokenRootCss(GLOBALS_FIXTURE)
  assert.match(root, /^:root \{/)
  // dark-first value present
  assert.match(root, /--bg: oklch\(0\.18 0\.01 240\);/)
  // light-mode override value absent (the .lighten --bg / --surface must not leak in)
  assert.ok(!root.includes('oklch(0.97 0.005 240)'), '.lighten --bg leaked')
  assert.ok(!root.includes('oklch(1 0 0)'), '.lighten --surface leaked')
  // --bg appears exactly once (no duplicate from the second theme)
  assert.equal((root.match(/--bg:/g) || []).length, 1)
})

test('emitTokenCards emits one card per present ramp with valid markers and inline OKLch', () => {
  const cards = emitTokenCards(GLOBALS_FIXTURE)
  assert.equal(cards.length, TOKEN_RAMPS.length) // fixture defines every ramp
  for (const c of cards) {
    const card = parseDsCard(c.content)
    assert.equal(card.group, 'Tokens')
    assert.match(c.path, /^components\/tokens-[a-z]+\/index\.html$/)
    assert.match(c.content, /oklch\(/)
    assert.match(c.content, /:root \{/)
  }
  // surfaces ramp swatches reference the real token names
  const surfaces = cards.find((c) => c.path.includes('tokens-surfaces'))
  assert.match(surfaces.content, /var\(--surface-2\)/)
})

test('vibe ramp renders --radius/--shadow as demo boxes, not colour chips', () => {
  const cards = emitTokenCards(GLOBALS_FIXTURE)
  const vibe = cards.find((c) => c.path.includes('tokens-vibe'))
  assert.ok(vibe, 'vibe card emitted')
  assert.match(vibe.content, /border-radius: var\(--radius\)/)
  assert.match(vibe.content, /box-shadow: var\(--shadow\)/)
})

test('buildDesignSystem yields unique cards = token ramps + type scale + component previews', () => {
  const files = buildDesignSystem({ globalsCss: GLOBALS_FIXTURE })
  // +1 for the authored Type scale card (the "type scale" scope item, not a globals.css ramp)
  assert.equal(files.length, TOKEN_RAMPS.length + 1 + COMPONENT_PREVIEWS.length)
  const paths = files.map((f) => f.path)
  assert.equal(new Set(paths).size, paths.length, 'card slugs are unique')
  for (const f of files) {
    assert.match(f.path, /^components\/[a-z0-9-]+\/index\.html$/)
    // every card is self-contained: inline :root tokens + OKLch values
    assert.match(f.content, /:root \{/)
    assert.match(f.content, /oklch\(/)
  }
})

test('the "type scale" scope item is emitted as a Tokens card', () => {
  const card = typeScaleCard(tokenRootCss(GLOBALS_FIXTURE))
  assert.equal(card.path, 'components/tokens-type-scale/index.html')
  const parsed = parseDsCard(card.content)
  assert.equal(parsed.group, 'Tokens')
  assert.equal(parsed.name, 'Type scale')
  // renders concrete font sizes + the mono numerics family the design system uses
  assert.match(card.content, /font-size:18px/)
  assert.match(card.content, /var\(--font-jetbrains-mono/)
  // and it is present in the assembled set
  const files = buildDesignSystem({ globalsCss: GLOBALS_FIXTURE })
  assert.ok(files.some((f) => f.path === 'components/tokens-type-scale/index.html'))
})

test('planSync: unchanged source is a no-op (AC2 idempotency)', () => {
  const local = buildDesignSystem({ globalsCss: GLOBALS_FIXTURE })
  const plan = planSync({ local, remote: local })
  assert.deepEqual(plan.writes, [])
  assert.deepEqual(plan.deletes, [])
  assert.equal(plan.unchanged.length, local.length)
})

test('planSync: cold start (absent/empty remote) writes everything, deletes nothing', () => {
  const local = buildDesignSystem({ globalsCss: GLOBALS_FIXTURE })
  const cold = planSync({ local }) // remote omitted
  assert.equal(cold.writes.length, local.length)
  assert.deepEqual(cold.deletes, [])
  const empty = planSync({ local, remote: [] })
  assert.equal(empty.writes.length, local.length)
})

test('planSync: a changed body is the only write; a stale remote component is deleted', () => {
  const local = buildDesignSystem({ globalsCss: GLOBALS_FIXTURE })
  // remote = local, but one card mutated + one extra stale card + one non-components artifact
  const remote = local.map((f) => ({ ...f }))
  const target = remote.find((f) => f.path === 'components/button/index.html')
  target.content = target.content + '\n<!-- drift -->'
  remote.push({ path: 'components/removed-old/index.html', content: '<!-- @dsCard name="Old" -->\n' })
  remote.push({ path: '_ds_manifest.json', content: '{"stale":true}' })

  const plan = planSync({ local, remote })
  assert.deepEqual(
    plan.writes.map((w) => w.path),
    ['components/button/index.html']
  )
  assert.ok(plan.deletes.includes('components/removed-old/index.html'), 'stale card deleted')
  assert.ok(!plan.deletes.includes('_ds_manifest.json'), 'non-components artifact never deleted')
})
