# Add build.assetInlineExclude config

**Is your feature request related to a problem? Please describe.**

When building for production, the following line :
```html
<!-- index.html -->
<link rel="icon" type="image/png" href="favicon.png">
```

get transformed in this
```html
<!-- index.html -->
<link rel="icon" type="image/png" href="data:image/png;base64,...(not included)...">
```

Inlining the favicon png does not allow browser caching. I'd rather like it to not be inlined but keep inline feature for other files.

**Describe the solution you'd like**

Have a way to exclude some files from being inlined.

**A clear and concise description of what you want to happen.**

```js
// vite.config.js
export default {
  build: {
    assetInlineExclude: ['favicon.png']
  }
}
```

Would all assets except inline `favicon.png`.

**Describe alternatives you've considered**

Setting `build.assetInlineLimit: 0` disables asset inlining but I want to keep it for other files than favicon.png.

## Acceptance criteria

- AC-1: `build.assetsInlineLimit` also accepts a callback that gets the file path and content of each asset; when it returns `true` or `false` that decides whether the asset is inlined, and when it returns nothing the default size limit applies.
