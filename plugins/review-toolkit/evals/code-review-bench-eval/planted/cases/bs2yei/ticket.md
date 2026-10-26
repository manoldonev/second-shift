# Improve template literal expression print in embeded language

**Prettier 3.7.2**
[Playground link](https://prettier.io/playground/#N4Igxg9gdgLgprEAuc0DOMAEBDTBeTAAwDMAbOADwFoATASwCc4wY7olMASYU6AcwD6kKDV5RBw0fyHQp4mSMwB+TAB1UpAK4BbKFSYA3OAzRx1mDushbd6gL6FVUJ0+EZMAI3yYwaNI6gAOjBSbD9gFxgySlpGZlZ2HwgbKG4xCVlMADIszHSFGmzc-MllNRB9OCMTMxALcvsAbic7JwDXdCwwbwALGG1SdpgAHnoDAD406VKcvOnM2ZKF4vnFRdXClXVK6tNzSxB7YYB6MfG2kAAaEAgABwSoNGRQbAYGCAB3AAVXhCeUbAGCB0GhXEAeBjYMAAazgMAAythtHAADJ0KBwZDEbCkUzXCAeABW8QA6pDbsgQLcmKYGEYwRCobCEbcoei+MgYAxNHBrqZtHROdzeSBKLdjHRkbAcQB5cWQmAQBhfCBoOgPSkIUHXMUSqUwHEAFWMUFedDg-2xuJFavE5AAipoIPAsTi8SBCWgKPD2Q6nS6kFb3QBHf1wL7vW7-EBhKgYuA0BNgrnYOikdkAYQg2m02EpUGgmL5vrgAEEYFy6B5NPAvsY0RjXdbrn0BiSeuqLaywHB4X91XQDOqAJ6U3xPa4GHkASRECARYAYdHupZE8Jgw-ITfd1NVcDJ2ApKGpFuM9Ou6NpMAj2D4ue3ItZNQYlI82A8cFIYOp6JgJJBMA9MgAAcAAM1xMKGcQ3neeaBm6IoGh4-40IByAAEzXJopiGu+loITq2gfjQiY0Ci2DiJot5wAAYkquYVuylLYDWEBgp6FAAEKQjCcKIsiDaYvB1p2HYQA)

```sh
--parser babel
--arrow-parens avoid
--trailing-comma none
```

**Input:**

```jsx
const a = `flex-direction: ${long_condlong_condlong_condlong_cond ? "column-reverse" : "column"}`


const b = css`
.class{
	flex-direction: column${long_cond && long_cond && long_cond ? "-reverse" : ""};
}
`

const c = html`
	<div>${long_cond && long_cond && long_cond && long_cond && long_cond ? "-reverse" : ""}</div>
`
```

**Output:**

```jsx
const a = `flex-direction: ${long_condlong_condlong_condlong_cond ? "column-reverse" : "column"}`;

const b = css`
  .class {
    flex-direction: column${long_cond && long_cond && long_cond
        ? "-reverse"
        : ""};
  }
`;

const c = html`
  <div>
    ${long_cond && long_cond && long_cond && long_cond && long_cond
      ? "-reverse"
      : ""}
  </div>
`;
```

**Expected output:**

```jsx
const a = `flex-direction: ${long_condlong_condlong_condlong_cond ? "column-reverse" : "column"}`;

const b = css`
  .class {
    flex-direction: column${long_cond && long_cond && long_cond ? "-reverse" : ""};
  }
`;

const c = html`
  <div>
    ${long_cond && long_cond && long_cond && long_cond && long_cond ? "-reverse": ""}
  </div>
`;
```

**Why?**

Should not break the ternay like it's in js.

Original issue https://github.com/prettier/prettier/issues/5886

## Acceptance criteria

- AC-1: An interpolation written on one line inside an embedded CSS template (`css`, styled-components, `<style jsx>`) stays on one line, even past printWidth, as it does in a plain template literal.
- AC-2: An interpolation written on one line inside an embedded HTML template (the `html` tag or a `/* HTML */` comment) stays on one line.
- AC-3: An interpolation that already spans lines inside an embedded template breaks at its `${` and `}` and is indented one level from the line it starts on, as in a plain template literal.
