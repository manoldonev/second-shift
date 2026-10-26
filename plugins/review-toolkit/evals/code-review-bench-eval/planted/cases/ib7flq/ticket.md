# Prettier formatting is inconsistent when using escaping in string

**Prettier 3.0.3**

```sh
--parser babel
```

**Input:**

<!-- prettier-ignore -->
```jsx
export const MSG_GENERIC_OPERATION_FAILURE_BODY =
   goog.getMsg('That\'s all we know');
```

**Output:**

<!-- prettier-ignore -->
```jsx
export const MSG_GENERIC_OPERATION_FAILURE_BODY = goog.getMsg(
  "That's all we know",
);
```

**Second Output:**

<!-- prettier-ignore -->
```jsx
export const MSG_GENERIC_OPERATION_FAILURE_BODY =
  goog.getMsg("That's all we know");
```

## Acceptance criteria

- AC-1: `export const MSG_GENERIC_OPERATION_FAILURE_BODY_2 = goog.getMsg("That\'s all we know");` formats exactly like the same declaration with `"That's all we know"`: the line breaks after `=` and the call stays on one line.
- AC-2: Formatting that declaration a second time gives the same output as the first time, with `trailingComma` set to `all` and to `es5`.
