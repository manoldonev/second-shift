# TypeError in HTML parser when parsing a custom element followed by a prototype

**Prettier 3.0.3**
[Playground link](https://prettier.io/playground/#N4Igxg9gdgLgprEAuEAeSUDOMBOBXMGCHAPgAccIiYyBPOCEAGhAjJgEtpNlQBDHJQDuABQEIeKPgBshfWjxYAjHHzABrODADKfALZwAMhyhxkAMxmY4y1Rq3ayakwHNkuPDZDW9Hd-i9MV2k4AEU8KjMkS2lrFgArTAAPbWCwiPgLKy8ARwy4EUoySRA+TABaUzgAExrmEFw+DmlXAGEIPT0+ZFLpaXqgqBcQgEEYXA4lPHgROBxjUyzYrwALGD1pAHUVjnhMJzA4bQldjgA3XdoesExFEDPPAEkoWthtMBwOdhGX7RhaEJLOIgCgQaybVRkHoUODWHBnMwsExwmCFPguLpArxOHBwnprDb1CgmGCbDjVGArZAADgADCwcHA8hxGWiMd1otkWDA+EoyRSqUgAEwsPDWAAqvMkMWBcD0ShqtWqhj4Qzw6LgADFiF1xq4enxpowAL7GoA)

```sh
# Options (if any):
```

**Input:**

```html
<constructor>prototpyeo
```

**Output:**

```jsx
TypeError: u(A).getContentType is not a function. (In 'u(A).getContentType()', 'u(A).getContentType' is undefined)
o@https://prettier.io/lib/plugins/html.js:17:16572
_consumeTagOpen@https://prettier.io/lib/plugins/html.js:17:6729
tokenize@https://prettier.io/lib/plugins/html.js:17:511
As@https://prettier.io/lib/plugins/html.js:16:27954
parse@https://prettier.io/lib/plugins/html.js:17:16590
ks@https://prettier.io/lib/plugins/html.js:19:14585
Bs@https://prettier.io/lib/plugins/html.js:19:17013
@https://prettier.io/lib/standalone.js:25:13319
```

**Expected behavior:**

The parser either throws an expected error "invalid HTML", or it reasonably parses the input without error.

Discovered via https://github.com/jasikpark/fuzz-prettier, my messy attempt at fuzzing prettier and its plugin formatters, hope this is helpful 👍

## Acceptance criteria

- AC-1: Formatting HTML whose element is named after an `Object.prototype` property (`constructor`, `hasOwnProperty`, `isPrototypeOf`, `propertyIsEnumerable`, `toLocaleString`, `toString`, `valueOf`) completes without a TypeError.
- AC-2: Such an element is printed like any other unknown inline element, with its text kept on the same line, for example `<constructor>constructor</constructor>`.
