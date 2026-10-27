# Allow to specify filename of emitted CSS when `build.cssCodeSplit: false`

### Clear and concise description of the problem

When building in library mode for a `.js` file that imports styles, Vite generates a `style.css` file in the target directory alongside the `.js` file.

Using [build.lib.fileName](https://vitejs.dev/config/#build-lib) we can already specify the filename for the `.js` file. Currently there seems to be no way to specify the filename for the `.css` file, as it always defaults to `style.css`.

### Suggested solution

Maybe a `build.lib.fileNameCSS` option?

### Alternative

A workaround is renaming the `style.css` in a `postbuild` script. But this isn't ideal since it involves yet another build step, and doing it in Vite itself would be more coherent.

### Additional context

_No response_

## Acceptance criteria

- AC-1: In library mode, when neither `build.lib.cssFileName` nor a string `build.lib.fileName` is set, the emitted CSS file is named after the `name` in package.json, with any npm scope removed.
- AC-2: `build.lib.cssFileName` sets the name of the emitted CSS file.
- AC-3: When `build.lib.cssFileName` is not set and `build.lib.fileName` is a string, the CSS file takes that name, for a single entry and for an array of entries.
- AC-4: A library build with CSS emits one CSS file named after the package for a single entry and for several entries, and one CSS file per entry when CSS code splitting is on.
