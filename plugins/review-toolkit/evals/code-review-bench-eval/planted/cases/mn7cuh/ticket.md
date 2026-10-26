# Linebreaks weirdly in long ES6 template strings with expressions

**Prettier 1.8.2**

```sh
# Options (if any):
--print-width=80
```

**Input:**

```jsx
class Quote {
    character = {
        name: 'Dorian'
    }

    text = `Yes, ${this.character.name}, you will always be fond of me. I represent to you all the sins you have never had the courage to commit.`
}
```

**Output:**

```jsx
class Quote {
  character = {
    name: "Dorian"
  };

  text = `Yes, ${
    this.character.name
  }, you will always be fond of me. I represent to you all the sins you have never had the courage to commit.`;
}
```

**Expected behavior:**

I would prefer a long string to _not_ get split into multiple lines, even if it contains expressions. When there are no expressions, Prettier correctly lets a long string go beyond the `print-width` limit.

I can't decide if this is a bug or a personal preference, but it's been creating weird hard to read code in our codebase. We can clean most of it up by simplifying our expressions, but there's only so short we can go.

## Acceptance criteria

- AC-1: `` let message = `this is a long message which contains an interpolation: ${format(data)} <- like this`; `` prints on one line, unchanged, even though it is wider than the print width.
- AC-2: An interpolation whose `${...}` already holds a line break in the source is still formatted as before and may break, while an interpolation without one in the same template literal stays on its line.
