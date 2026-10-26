# `resolve.conditions` not working reliably on custom environment

### Describe the bug

I'm testing a custom environment like:

```js
  environments: {
    worker: {
      webCompatible: true,
      resolve: {
        conditions: ["worker"],
        noExternal: true,
      },
    },
```

and a package like:

```js
{
  "name": "test-dep-conditions",
  "private": true,
  "type": "module",
  "exports": {
    ".": {
      "worker": "./index.worker.js",
      "browser": "./index.browser.js",
      "default": "./index.default.js"
    }
  }
}
```

When importing such package both from default client environment and custom environment, custom environment side picks up `./index.browser.js` in some cases.

### Reproduction

https://github.com/hi-ogawa/reproductions/tree/main/vite-environment-resolve-condition

### Steps to reproduce

- open https://stackblitz.com/github/hi-ogawa/reproductions/tree/main/vite-environment-resolve-condition?file=src%2Fentry.tsx
  - shows `client: index.browser.js` correctly
- click `/worker` link
  - shows `worker: index.browser.js` but it's expected to show `worker: index.worker.js`
- go back and click `/custom1` link
  - shows `custom1: index.browser.js` but it's expected to show `custom1: index.custom1.js`
- kill server (Control+C) and restart
- click `/worker` link again
  - now it shows `worker: index.worker.js`
- go back and click `/custom1` link
  - shows `custom1: index.worker.js` but it's expected to show `custom1: index.custom1.js`

In this reproduction, I added three extra custom environments with and without `webCompatible: true`. It looks like resolution is cached by `webCompatible`, so for each `true/false` case, resolution depends on the order how they are resolved.

I also tested with the latest https://pkg.pr.new/vite@95020ab but the behavior seems to be same.

### System Info

```shell
(stackblitz)

  System:
    OS: Linux 5.0 undefined
    CPU: (8) x64 Intel(R) Core(TM) i9-9880H CPU @ 2.30GHz
    Memory: 0 Bytes / 0 Bytes
    Shell: 1.0 - /bin/jsh
  Binaries:
    Node: 18.20.3 - /usr/local/bin/node
    Yarn: 1.22.19 - /usr/local/bin/yarn
    npm: 10.2.3 - /usr/local/bin/npm
    pnpm: 8.15.6 - /usr/local/bin/pnpm
  npmPackages:
    vite: 6.0.0-beta.1 => 6.0.0-beta.1
```

### Used Package Manager

npm

## Acceptance criteria

- AC-1: In one dev server, a module runner for each environment that imports a package with per-condition exports gets the entry matching that environment's own `resolve.conditions` and `webCompatible`, whichever environment resolved the package first.
- AC-2: In the ssr environment, a CSS `@import` of the package resolves its `style` entry and a JS import of it resolves its default entry.
- AC-3: Building each environment with the package as input outputs the entry matching that environment's own `resolve.conditions` and `webCompatible`.
