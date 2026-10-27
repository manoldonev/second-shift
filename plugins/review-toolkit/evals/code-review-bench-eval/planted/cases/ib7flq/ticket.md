# Prettier prints a trailing comma after type argument list even if the languages is `ts` in markdown

**Prettier 3.0.2**

```sh
--parser markdown
```

**Input:**

<!-- prettier-ignore -->
````markdown
```ts
const t = <T,>() => {};
```

```tsx
const t = <T,>() => {}
```
````

**Output:**

<!-- prettier-ignore -->
````markdown
```ts
const t = <T,>() => {};
```

```tsx
const t = <T,>() => {}
```

````

The second codeblock prints a trailing comma and it's the correct behavior, however the first codeblock should remove the trailing comma

**Expected behavior:**
The first codeblock should not have a trailing comma

## Acceptance criteria

- AC-1: In a Markdown file, a `ts` or `typescript` code block holding `const test = <T,>(value: T) => {};` prints `const test = <T>(value: T) => {};`.
- AC-2: A `tsx` code block holding the same line keeps `<T,>(value: T) => {}`, as it does today.
