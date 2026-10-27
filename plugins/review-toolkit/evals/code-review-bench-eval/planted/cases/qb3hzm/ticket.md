# Sourcemap for '...bootstrap.min.css' points to missing source files

### Describe the bug

I have Vite configured to include CSS source maps in dev:

```
export default defineConfig({
    ...
    css: {
        devSourcemap: true
    },
    ...
});
```

My Vue site's code, in `main.js`, imports Bootstrap's CSS like this:

```
import 'bootstrap/dist/css/bootstrap.min.css';
```

When I load a page on the site, Vite gives me the message:

> Sourcemap for "C:/Development/SPA/myApp/node_modules/bootstrap/dist/css/bootstrap.min.css" points to missing source files

React's default Webpack config doesn't seem to have the same problem when I import the Bootstrap minified CSS in the same way. I think it's because the Bootstrap `bootstrap.min.css.map` file, amongst its various source mappings, includes `"dist/css/bootstrap.css"`. This is apparently supposed to be interpreted relative to the `node_modules/bootstrap` root, but Vite interprets it relative to `bootstrap.min.css`, and so it looks for `bootstrap/dist/css/dist/css/bootstrap.css` and doesn't find it, causing the error.

### Reproduction

Configure Vite to include CSS sourcemaps, add Bootstrap to project, import it in Vue file

## Acceptance criteria

- AC-1: In dev, a stylesheet or JS module from a dependency whose sourcemap already carries `sourcesContent` for sources that are not on disk is served with that content kept, and Vite prints no "points to missing source files" warning for it.
- AC-2: A source whose `sourcesContent` entry is null is still read from the file on disk, and a source that is neither carried in the map nor on disk still prints the warning once.
