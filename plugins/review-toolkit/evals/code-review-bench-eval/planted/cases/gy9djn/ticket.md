# [3.4.0, 3.4.1] Regression on decorators + async + jsdoc

**Prettier 3.4.0 (Also tested on 3.4.1)**

```sh
--parser typescript
--print-width 120
--single-quote
--trailing-comma es5
```

**Input:**

```tsx
const myDecorator = (target, propertyKey, descriptor) => {
  console.log(descriptor.value);
}

class myClass {
  @myDecorator
  /**
   * The method description
   *
  */
  async myMethod(foo: Foo, bar: Bar) {
    console.log(foo);
  }
}
```

**Output:**

```tsx
const myDecorator = (target, propertyKey, descriptor) => {
  console.log(descriptor.value);
};

class myClass {
  @myDecorator
  async /**
   * The method description
   *
   */
  myMethod(foo: Foo, bar: Bar) {
    console.log(foo);
  }
}
```

**Expected output:**

```tsx
No change
```

**Why?**

The `async` keyword gets hoisted above the jsdoc. Even worse, next prettier run adds a `;` after it, breaking the syntax :D

## Acceptance criteria

- AC-1: A block comment on its own line between a decorator and a class method, a JSDoc block included, is printed on its own line after the decorator and before the method's `async`, `public`, `static`, `protected` or `*`, and formatting that output again leaves it unchanged.
- AC-2: A line comment after a decorator, a block comment on the decorator's line or between `async` and the method name, and a comment before an undecorated abstract method are printed where they are printed today.
