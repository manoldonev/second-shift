# Vite inlines icon resources that should not be inlined

### Describe the bug

When Vite asset-ifies `<link>` resources it applies the default assetsInlineLimit for JS without considering whether it makes sense to inline the resource in HTML.

One issue this causes is in site icons. If a site icon is small enough, instead of just putting it in /assets with a cache buster (which can be desirable for site icons), Vite will inline it into the document.

This is a problem since now site icons are downloaded inline with every page request which is problematic for a number of reasons:
- Site icons are a low priority but now must be downloaded before critical page content
- The data now comes that comes with every page load on a likely uncacheable request instead of allowing the browser to cache the icon
- All site icons are downloaded, even if its an icon the browser would not have downloaded (unsupported file type, media query, unused size)

Manifests are also inlined, but that bug was reported in #5962.

### Reproduction

https://github.com/dantman/vite-excessive-inline-resources-bug

### Used Package Manager

npm

## Acceptance criteria

- AC-1: In a build, a `<link rel="icon">` or `<link rel="apple-touch-icon">` in index.html whose file is under `build.assetsInlineLimit` is emitted as a hashed file under `assets/`, not inlined as a data URL.
- AC-2: In a build, a `<link rel="manifest">` in index.html is emitted as a hashed file under `assets/`, not inlined as a data URL.
