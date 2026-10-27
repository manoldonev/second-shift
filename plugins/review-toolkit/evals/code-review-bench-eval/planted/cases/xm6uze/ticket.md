# Got wrong url when importing some svg files

### Describe the bug

**This problem only occurs in prod mode.**

There are two svg files in reproduction that are imported in the same way, but get different results

```ts
import url_01_url from "./assets/01.svg?url";
import url_02_url from "./assets/02.svg?url";
```

```txt
01: /assets/01-CAOkh7Dq.svg
02: data:image/svg+xml,%3csvg%20xmlns='http://www.
```

### Reproduction

https://github.com/hungtcs/vite-svg-assets-reproduction/blob/master/src/main.tsx

### Steps to reproduce

```shell
git clone git@github.com:hungtcs/vite-svg-assets-reproduction.git
cd vite-svg-assets-reproduction
pnpm run build
pnpm run preview
```

### System Info

```shell
System:
  OS: macOS 14.6.1
  CPU: (8) arm64 Apple M3
  Memory: 67.17 MB / 24.00 GB
  Shell: 5.9 - /bin/zsh
Binaries:
  Node: 22.6.0
  npm: 10.8.2
  pnpm: 9.7.0
Browsers:
  Chrome: 128.0.6613.119
  Safari: 17.6
npmPackages:
  @vitejs/plugin-react: ^4.3.1 => 4.3.1
  vite: ^5.4.1 => 5.4.3
```

### Used Package Manager

pnpm

## Acceptance criteria

- AC-1: In dev, an SVG under `build.assetsInlineLimit` that CSS references with `url()` or `image-set()` becomes a `data:image/svg+xml` URL, the same as in build.
- AC-2: In dev, a small SVG from the source tree that JS imports by a relative path becomes a `data:image/svg+xml` URL, and a `#fragment` the code appends to it still works.
- AC-3: Editing an inlined SVG in dev sends an HMR update whose new value is a different data URL, with no `?t=` query appended to it.
- AC-4: An SVG that an `assetsInlineLimit` callback excludes keeps its file URL in dev, and after an edit the update carries a `?t=` timestamp.
