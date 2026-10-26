# Silence warning about dynamic import when a dynamically imported module is inlined.

### Description

Since https://github.com/vitejs/vite/pull/12850 a warning is generated when a dynamic import is alongside a static import. 

I dont think it makes sense to show this warning when `inlineDynamicImports` is set to true in the rollupOptions.output. The user is already aware that it wont be moved into a new chunk, because he explicitly used that option.

### Suggested solution

Disable the warning in such cases.

### Alternative

_No response_

### Additional context

_No response_

## Acceptance criteria

- AC-1: A build with `build.rollupOptions.output.inlineDynamicImports: true`, whose code imports a module both statically and dynamically, prints no "dynamic import will not move module into another chunk" warning.
