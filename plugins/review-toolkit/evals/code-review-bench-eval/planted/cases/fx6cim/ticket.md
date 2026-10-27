# Resolve conditions that Vite adds on its own cannot be turned off

When Vite resolves a package's `exports` or `imports` field, it always adds the `module`
condition and the `production` or `development` condition for the current mode, on top of
`resolve.conditions`. For server environments it also replaces the configured conditions with
a separate internal list for externalized dependencies, and it switches the `browser` handling
on and off through an internal `webCompatible` flag instead of the configured conditions.

As a result a user cannot drop one of these conditions for an environment: a custom
environment that sets `resolve.conditions: ['custom1']` still matches `module`, `development`
or `production` entries of a dependency, and an environment's resolution cannot be described by
its config alone. The behaviour differs between dev with an inlined dependency, dev with an
externalized one, and build.

## Acceptance criteria

- AC-1: In dev, an environment that sets its own `resolve.conditions` and `externalConditions` resolves a dependency's `exports` through exactly those conditions plus `import` or `require` and `default`, both when the dependency is inlined and when it is externalized.
- AC-2: In build, the same environments resolve the same `exports` entries as in dev.
- AC-3: An ssr environment that keeps the default conditions resolves a dependency whose `exports` has no `node` entry to its `default` entry, and a worker environment with `conditions: ['worker']` to its `worker` entry.
