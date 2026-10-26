# Missing parens for `ClassExpression` with decorators

**Prettier 2.5.1**

```sh
--parser babel
```

**Input:**

```jsx
(@f() class {});
```

**Output:**

```jsx
@f()
class {};

```

**Second Output:**

```jsx
SyntaxError: A class name is required. (2:7)
  1 | @f()
> 2 | class {};
    |       ^
  3 |
```

**Expected behavior:**

Should keep parens

## Acceptance criteria

- AC-1: A class expression with decorators keeps its parentheses as an expression statement, as a variable initializer, as a call argument, as the object of a member access and as a superclass, with the decorators and the class printed on their own indented lines inside the parentheses, so the output parses again.
- AC-2: With `semi: false`, a statement that starts with a parenthesized decorated class expression is printed with a leading `;` before the parenthesis.
- AC-3: With the babel-ts parser, `(@f<<T>(v: T) => void>() class {});` is printed with its parentheses kept.
