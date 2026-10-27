# Decision record — #7941 Custom elements support child component style tags

## Summary

A regular child component used inside a custom element made with `defineCustomElement` gets its
styles added to the custom element's shadow root when it mounts, so a `*.ce.vue` component can use
other `*.ce.vue` components as plain children instead of registering each as a custom element.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where a child component's styles go | Into the root custom element's shadow root as `<style>` tags, prepended so the root component's own styles come last and win. | user-answered | intent |
| D-2 | How often a child's styles are added | Once per child component definition per custom element, however many instances render. | user-answered | intent |
| D-3 | When the styles are added | When the child component mounts, through an interface the custom element exposes on the component instance, so `runtime-core` does not import from `runtime-dom`. | user-answered | intent |
| D-4 | HMR of a child component | The reloaded child's old style tags are removed from the shadow root and its new styles are added when it mounts again. | user-answered | intent |
| D-5 | A custom element with `shadowRoot: false` | Its styles are not applied, and the existing dev warning stays. | user-answered | intent |
| D-6 | What the tests cover | `customElement.spec.ts`: the root's styles with an HMR reload, and child styles across two instances, their order and two HMR reloads of the child. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: a custom element whose root renders a child component twice has the child's two style tags once, before the root's style tag, in its shadow root
AC-2: after an HMR reload of the root or of the child, the shadow root holds the reloaded style tags and none of the old ones
