// design-faithful fixtures — PROJECT_TYPE_DESIGN_SYSTEM components.
//
// A minimal design-system preview: a @dsCard-marked component
// with two variants and a :hover state, plus a marker-less component to exercise the
// "missing @dsCard marker → skipped + diagnostic" path. Stored as exported strings.

// Has a first-line @dsCard marker → becomes a card.
export const probeButtonHtml = `<!-- @dsCard group="Probe" name="Probe Button" subtitle="Primary / secondary" -->
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<style>
  body { font-family: system-ui, sans-serif; background: #18181b; color: #fafafa; display: flex; gap: 16px; }
  .btn { padding: 8px 16px; border-radius: 999px; font-weight: 600; }
  .btn-primary { background: #22d3ee; color: #0a0a0a; }
  .btn-secondary { background: transparent; color: #fafafa; border: 1px solid #3f3f46; }
  .btn:focus-visible { outline: 2px solid #22d3ee; }
  .btn-primary:hover { filter: brightness(1.05); }
</style>
</head>
<body>
  <button class="btn btn-primary">Primary</button>
  <button class="btn btn-secondary" data-state="disabled">Secondary</button>
</body>
</html>
`

// No first-line @dsCard marker → must be skipped with a recorded diagnostic.
export const noMarkerHtml = `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><style>.card { border-radius: 8px; }</style></head>
<body>
  <section aria-label="orphan card"><h2>No marker here</h2></section>
</body>
</html>
`
