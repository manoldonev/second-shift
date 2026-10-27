# Calling print() on a property that is not a child node is not always caught

Outside a production build, the built-in printers throw `Calling \`print()\` on non-node object.`
when a printer calls `print()` on a property that does not hold a child node, so that a printer
cannot pass a string or a stray object to itself by mistake. Today each language carries its own
copy of that check at the top of its print function, which leaves gaps:

- The check only runs once the value is known to be set. `print("notAChild")` on a node that has
  no `notAChild` property returns `""` before any check runs, so the mistake only shows up on the
  input where the property happens to be present.
- Printers from plugins get no check at all, and each new language has to remember to add it.

```js
// A printer for a node { type: "root", text: "foo" } whose visitor keys are ["body"]
print("text");      // throws, as expected
print("notAChild"); // returns "" silently
```

## Acceptance criteria

- AC-1: Outside a production build, calling `print()` on a property that is not one of the node's child keys throws `Calling \`print()\` on non-node object.` for every printer, whether the property holds a value or is missing; a printer with no `getVisitorKeys` is checked against the node's own keys.
- AC-2: `print()` on a child key that the node does not have still prints nothing.
- AC-3: The built-in languages format as before with the check on.
