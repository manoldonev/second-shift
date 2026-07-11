// design-faithful fixtures — PROJECT_TYPE_PROJECT handoff bundle.
//
// Real bytes captured live from the Acme handoff project
// (design_handoff_acme_redesign/) on 2026-06-20 via DesignSync get_file, curated to a
// faithful slice that exercises every extractor branch. Stored as exported strings so the
// whole module stays inert-lane (.mjs) and importable by node:test — no raw .css/.jsx files.

export const stylesCss = `
@import url('https://fonts.googleapis.com/css2?family=Inter+Tight:wght@400;500;600;700;800&family=JetBrains+Mono&display=swap');

body {
  font-family: 'Inter Tight', system-ui, -apple-system, sans-serif;
  background: var(--bg);
  color: var(--ink);
  font-size: 14px;
}
.mono { font-family: 'JetBrains Mono', ui-monospace, monospace; }

/* ====== COLD WORKSHOP — dark first ====== */
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
  --hi: oklch(0.74 0.16 152);
  --good: oklch(0.74 0.13 175);
  --mod: oklch(0.78 0.16 80);
  --low: oklch(0.72 0.18 50);
  --shadow: 0 8px 24px -12px oklch(0 0 0 / 0.6);
  --grid: oklch(1 0 0 / 0.06);
  color-scheme: dark;
}

/* ====== OUTDOOR COAT — light first, warm ====== */
.theme-warm {
  --bg: oklch(0.98 0.012 70);
  --surface: oklch(1 0 0);
  --ink: oklch(0.22 0.015 250);
  --accent: oklch(0.62 0.16 50);
  --hi: oklch(0.62 0.14 152);
  --sage: oklch(0.78 0.06 150);
  color-scheme: light;
}

.surface { background: var(--surface); border: 1px solid var(--line); border-radius: 14px; }
.row { display: flex; }
.col { display: flex; flex-direction: column; }
.gap-1 { gap: 4px; }
.gap-2 { gap: 8px; }
.gap-3 { gap: 12px; }
.gap-4 { gap: 16px; }
.seg { display: inline-flex; padding: 3px; background: var(--surface-2); border-radius: 10px; }
.act-row { transition: background 140ms ease; }
.act-row:hover { background: var(--surface-2); }
.nav-link:hover { color: var(--ink); }

/* accessibility */
button:focus-visible, a:focus-visible, .nav-link:focus-visible {
  outline: 2px solid var(--accent);
  outline-offset: 2px;
}
.skip-link { position: absolute; top: -40px; left: 8px; background: var(--accent); }
.skip-link:focus { top: 8px; }
.sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0,0,0,0); }

@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { animation-duration: 0.01ms !important; }
}
@media (max-width: 759px) {
  .surface { border-radius: 12px; }
  .verdict-cold > .row[style*="border-top"]:last-child {
    display: grid !important;
    grid-template-columns: repeat(2, 1fr) !important;
    gap: 16px !important;
  }
  button, .nav-link { min-height: 44px; }
}
`

// Verdict block + stats strip from screens/detail.jsx — a backtick-free real slice
// (semantic h1/p/button/strong, verdict-cold/verdict-warm variant pair, var(--token) refs).
export const detailJsx = `
// Activity Detail — the verdict moment
function ActivityDetail({ theme, mobile, onBack }) {
  const a = window.ACME_DATA.detail;
  return (
    <div style={{ maxWidth: 1320, margin: '0 auto', padding: '24px 28px 80px' }}>
      <button onClick={onBack} style={{ background: 'transparent', border: 0, color: 'var(--ink-3)', fontSize: 13 }}>
        ← Back to Activities
      </button>
      <div className={theme === 'warm' ? 'verdict-warm' : 'verdict-cold'} style={{ borderRadius: 18, padding: '30px 36px' }}>
        <div className="row center gap-2" style={{ color: 'var(--ink-3)', fontSize: 11, textTransform: 'uppercase' }}>
          <span>Verdict · Thursday · January 29</span>
          <span className="mono" style={{ color: 'var(--ink-4)' }}>{a.id}</span>
        </div>
        <div className="row between" style={{ alignItems: 'flex-end', marginTop: 14, gap: 32 }}>
          <div>
            <div style={{ color: 'var(--ink-3)', fontSize: 14 }}>We saw</div>
            <h1 style={{ margin: 0, fontSize: 76, fontWeight: 600, color: 'var(--ink)' }}>4× Tempo</h1>
            <p style={{ margin: '14px 0 0', fontSize: 16, color: 'var(--ink-2)' }}>
              Four reps of <strong style={{ color: 'var(--ink)' }}>7:45 at 254 W</strong> (86% FTP).
              <button style={{ background: 'transparent', border: 0, color: 'var(--ink-3)', textDecoration: 'underline' }}>This isn't right</button>
            </p>
          </div>
        </div>
        <div className="row" style={{ marginTop: 28, borderTop: '1px solid var(--line)', paddingTop: 22 }}>
          <div className="col gap-1"><span style={{ fontSize: 10 }}>Duration</span><span className="hero-num">45m</span></div>
          <div className="col gap-1"><span style={{ fontSize: 10 }}>Avg Power</span><span className="hero-num">218 W</span></div>
        </div>
      </div>
    </div>
  );
}
`

export const screenshots = [
  'design_handoff_acme_redesign/screenshots/activity-detail.png',
  'design_handoff_acme_redesign/screenshots/dashboard.png',
  'design_handoff_acme_redesign/screenshots/activities.png'
]
