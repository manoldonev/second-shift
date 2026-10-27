# Line breaks in multiline strings aren't replaced with `literalline` and confuse `fits`

Note that it's not about template literals. It's about normal string literals with escaped line breaks.

**Prettier 2.7.1**

```sh
--parser babel
```

**Input:**

```jsx
const loremIpsumFooBazBar1 = 'Multiline string\
         Multiline string\
'

const loremIpsumFooBazBar2 = 'Multiline string\
         Multiline string\
         Multiline string'

```

**Output:**

```jsx
const loremIpsumFooBazBar1 = "Multiline string\
         Multiline string\
";

const loremIpsumFooBazBar2 =
  "Multiline string\
         Multiline string\
         Multiline string";

```

**Expected behavior:**

Formatting style shouldn't change when more lines are added.

## Acceptance criteria

- AC-1: A JavaScript string literal with escaped line breaks is laid out the same way however many lines it spans: in `const name = '...'`, the two-line and the three-line string both move to their own line after `=`, under the default options and under `trailingComma: "all"`, and the continuation lines keep their content and indentation.
- AC-2: A Flow or TypeScript string literal type with escaped line breaks formats without changing the string's content, and a Flow one moves to its own line after `=` whether it spans two or three lines.
