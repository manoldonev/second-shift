# Unexpected reactivity watching shallowReactive array

### Vue version

3.3.12

### Link to minimal reproduction

https://play.vuejs.org/#eNqNVE1zmzAQ/Ss7XMBTCk1yo8TTtM2hPSSdJJ0eQg4EFkwiSxpJ2O54+O9dSQYzHTfTE9Lu27dvP9A+uJIy2fQYZEGuK9VJAxpNL4GVvL0sAqOLYFnwbi2FMrAHhU0M96uSMbG9s2d96lxWpttgDNvSVKuYgrwBBmiUWENICcOCF7xipdbQCAH7ggOAVEKeZTP+XBvV8XYJl7NEURguPk748ww8iDBhSPbBMQuuDYjnlzMyc9zaJJGNmhznfzlGVyUYQ5Ir+DypLyB6tIyxC3+aB61R67JFTSFjsdHjAeGaEB1pY4gWcLn0JY+Biez1Kgp/WSwqoILaFhXWEMI7J/NraTBaWMYh9qE1osygKZnGmKw+WdNzr72XNUXcklzK5rt7lPD44SlxvU42JeuRVFv6hItttEiMuHf9dF1xzZxIy7omxhOEXv7UzkNknvqVogWii8G1ZJSGbgC5XObPvTFE+qliXfVKuzaXTFv3013B3iHSK9GzGm5uH8begFmhXzBUizz1ZMs8lf/kH9UT91VdW+KJ9z84HevqfPngoTrLU7o5a8/cl06sg837RijKFh1GG0PHa9wt6DNNuwgge8XfhHI+ErTfj04YhjxlnWdOHXWeznoXxPRT0tY1XZu8aMHpz3XTKIJKrGXHUN1KOxJKkh3mRD63xt+dzajeLoy3U6XV6wn7iyZVGR1+KNSoNlgEk8+UqkXj3df3N7ij8+Rci7pnhH7DeYdasN5q9LDPPa9J9gzn1H5zbw4t4oO+3hnkeizKCrXIweGLgF6TL2+UfpR7kVy4OFrOYPgDw/GuRw==

### Steps to reproduce

Click on `Update Obj1 (should NOT trigger the watcher)` and you will see the message of the watcher having triggered.

### What is expected?

That the watcher is not triggered since it is watching a `shallowReactive` array and has set `{ deep: false }`, so only should trigger when applying changes to the array

### What is actually happening?

It is triggeing also when props of objects in the array are changed

### Any additional comments?

https://github.com/vuejs/core/discussions/9900

In my case (open source vue project), is causing an extra overhead and lower performance since it is triggering and causing unwanted loop

## Acceptance criteria

- AC-1: `watch(source, cb, { deep: n })` with a number `n` calls `cb` for a change up to `n` levels below the source, and not for a change deeper than that, on a reactive object, a ref and an array.
- AC-2: `watch` on a `shallowReactive` source with no `deep` option, and `watch` on a reactive source with `deep: false`, call `cb` only for a change to the source's own properties.
