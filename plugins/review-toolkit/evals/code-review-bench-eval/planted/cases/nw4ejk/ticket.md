# HMR re-transforms every importer of a changed module

When a module changes during dev, Vite invalidates the module and walks up to every importer
that does not accept the update, invalidating each one. Every invalidated importer is then
loaded and transformed again by the whole plugin pipeline on its next request, even when its own
source did not change and the only difference in its output is the `?t=` timestamp on the
import of the module that changed.

In a large app a one-line edit deep in the graph re-runs the full transform of a long chain of
importers on each save, which makes HMR updates slow.

## Acceptance criteria

- AC-1: When a module that another module imports with a static `import` changes, the importer is served with the import's timestamp updated and the new value shows in the page, without the importer's transform running again.
