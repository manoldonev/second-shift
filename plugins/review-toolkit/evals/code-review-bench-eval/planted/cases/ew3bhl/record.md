# Decision record — #13967 Silence warning about dynamic import when a dynamically imported module is inlined.

## Summary

The build reporter skips its check for ineffective dynamic imports when the build inlines dynamic
imports, since no dynamic import moves a module into its own chunk then.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | When the warning is skipped | When dynamic imports are inlined for the output; the check still runs for every other build. | user-answered | intent |
| D-2 | Several outputs in rollupOptions.output | Vite builds use one output config here, so the first entry of an array decides. | user-answered | intent |
| D-3 | What the tests cover | A dynamic-import-inline playground that sets inlineDynamicImports and imports one module both statically and dynamically; the test reads the build log. | user-answered | intent |

## Test intent

ACs: AC-1

AC-1: the build log of the dynamic-import-inline playground does not contain dynamic import will not move module into another chunk
