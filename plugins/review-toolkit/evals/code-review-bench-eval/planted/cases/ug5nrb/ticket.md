# Custom elements support child component style tags

### What problem does this feature solve?

I encountered a scenario: I have a custom element component `A`, which uses another child component `B`, and `B` is a regular component, and in `B` I define a `style that contains `scoped` ` label.

But unfortunately the styling of the `B` component doesn't take effect.
(https://stackblitz.com/edit/vitejs-vite-gdj8cq?file=src/bwsy-ce-foo.ce.vue)
Unless I change the names of component A and component B to `*.ce.vue`, and use `defineCustomElement` to process them, and finally need to use `customElements.define` to register them. But in fact, I don't want to turn them all into custom elements. I want to directly reference `B` as a child component of `A` when `A` is a custom element.

### What does the proposed API look like?

When the component file name is `*.ce.vue`, if it is used as a child component of a custom element, it does not need to be registered as a custom element again, but can be used directly, and the `style` tag style can take effect

## Acceptance criteria

- AC-1: A regular component rendered as a child inside a custom element made with `defineCustomElement` has its `styles` added to the root custom element's shadow root, ahead of the root component's own styles, once per child component however many instances of it render.
- AC-2: An HMR reload of the custom element's root component or of a child component replaces that component's old style tags in the shadow root with the reloaded ones.
