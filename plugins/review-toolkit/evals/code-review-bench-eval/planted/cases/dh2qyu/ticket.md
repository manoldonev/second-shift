# Accessing env variables from index.html

### Describe the bug

I try to insert html tag by environment variable condition and use `vite-plugin-html` for it. But Vite behaviour is weird

### Reproduction

https://github.com/xSorc/test-vite-index-env

1.
This code works only in build
```html
<% if (import.meta.env.VITE_SHOW_TAG === '1') { %>
  works
<% } %>
```
During server i have this error
```
[vite] Internal server error: Cannot use 'import.meta' outside a module while compiling ejs
If the above error is not helpful, you may want to try EJS-Lint:
https://github.com/RyanZim/EJS-Lint
Or, if you meant to create an async function, pass `async: true` as an option.
```

2.
This code works only in dev server
```
// vite.config.ts
require('dotenv').config();
// index.html
<% if (process.env.VITE_SHOW_TAG === '1') { %>
  works
<% } %>
```
But during build this doesn't work, because Vite replace `process.env` with this:
```
<% if (({}).VITE_SHOW_TAG === '1') { %>
  works
<% } %>
```

3. The only option that works in both server and build is this:

```
// vite.config.ts
require('dotenv').config();
// index.html
<% if (process.env['VITE_SHOW_TAG'] === '1') { %>
  works
<% } %>
```

I suppose that first or second variant should works

### System Info

```node
  System:
    OS: Windows 10 10.0.19042
    CPU: (6) x64 Intel(R) Core(TM) i5-8600K CPU @ 3.60GHz
    Memory: 9.13 GB / 15.94 GB
  Binaries:
    Node: 14.15.3 - C:\Program Files\nodejs\node.EXE
    Yarn: 1.22.10 - ~\AppData\Roaming\npm\yarn.CMD
    npm: 6.14.9 - C:\Program Files\nodejs\npm.CMD
  Browsers:
    Edge: Spartan (44.19041.423.0), Chromium (90.0.818.42)
    Internet Explorer: 11.0.19041.1
  npmPackages:
    vite: 2.2.1 => 2.2.1
```

## Acceptance criteria

- AC-1: A `%VITE_NAME%` placeholder in an html file, in text or inside an attribute value, is replaced with the value of `VITE_NAME` from the `.env` file, in dev and in build.
- AC-2: A `%NAME%` placeholder is replaced with the value of an `import.meta.env.NAME` key set through `define`.
- AC-3: `%PROD%` and `%DEV%` are replaced with `true` or `false` to match the command.
