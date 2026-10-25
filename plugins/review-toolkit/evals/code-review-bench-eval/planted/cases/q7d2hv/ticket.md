# Can't use generic prop type when definition includes intersection with generic params?

### Vue version

3.3.4

### Link to minimal reproduction

https://play.vuejs.org/#eNqFUbFOwzAQ/ZWTBwJSaRamNI3EgsSGRMXkJW6urYXjs2ynVRTl3zmHQCMGOtnne/feu+dBPDu3PncoClGGvdcuQsDYOTC1PW6liEGKSloA3TryEV6IXiO2cPDUQrbO5zpRZAm2JxsiHIhgC0M6C3hagap9AdkJjaFsBTp86KCVwQKi7xDGjbTSlvm3PqtxwZzO1BEn7fJH9fyotG3YFhNLATl3y3wB5TLE3qSroqaHIU2rev959NTZpgBluGC5ZNQQm7qcdMTpYZwszNNiJRab3Qgn9g5TMNeVbdcq9JvEOTXfqcU3Ty6Uu4pRO7hj5CIGRWSwtgkvbYMHbWf4dZD5q+r+4f+cGn3mjMKJLuzul59Nzh8y2YNxLHNG/g1PjF+nxbYT

### Steps to reproduce

```
type Foo = { foo: number; }
type SomeProps<T> = T & { isVisible: boolean }
```

### What is expected?

this should be valid typescript:

https://www.typescriptlang.org/play?#code/C4TwDgpgBAYg9nKBeKBvKAzBAuKA7AVwFsAjCAJygF8AoUSKAZTiIgAVy4wBnAHgBUAfMij8oAMjRQAltwBqs6SQA2EXCQSqAhnmo0AxnDzdgmHExbtOPXvDjCU6LHFwBmADQz5ilWqjByAmgqAG4aaQwoAApnADpZBW4lVQBKKENjOFVY5TgAcxiEFJCgA

### What is actually happening?

compile error:

```
1:55:02 AM [vite] Internal server error: [@vue/compiler-sfc] Unresolvable type reference or unsupported built-in utility type

/testdir/src/FooItem.vue
1  |  <script setup lang="ts">
2  |  type Foo = { foo: number }
3  |  type SomeProps<T> = T & { isVisible: boolean }
   |                      ^
4  |
5  |  defineProps<SomeProps<Foo>>()
  Plugin: vite:vue
  File: /testdir/src/FooItem.vue
      at ScriptCompileContext.error (/testdir/node_modules/.pnpm/@vue+compiler-sfc@3.3.4/node_modules/@vue/compiler-sfc/dist/compiler-sfc.cjs.js:15841:11)
      at innerResolveTypeElements (/testdir/node_modules/.pnpm/@vue+compiler-sfc@3.3.4/node_modules/@vue/compiler-sfc/dist/compiler-sfc.cjs.js:17966:20)
      at resolveTypeElements (/testdir/node_modules/.pnpm/@vue+compiler-sfc@3.3.4/node_modules/@vue/compiler-sfc/dist/compiler-sfc.cjs.js:17902:35)
      at resolveRuntimePropsFromType (/testdir/node_modules/.pnpm/@vue+compiler-sfc@3.3.4/node_modules/@vue/compiler-sfc/dist/compiler-sfc.cjs.js:19312:20)
```

### Any additional comments?

I'm not actually sure if I'm characterizing this correctly, but it seems like the sfc compiler cannot handle props whose type intersects one of its own generic parameters.

## Acceptance criteria

- AC-1: `defineProps<SomeProps<Foo>>()` with `type SomeProps<T> = T & { isVisible: boolean }` compiles, and the runtime props hold Foo's props and `isVisible`.
- AC-2: A generic type alias or interface given as the props type resolves each of its type parameters to the argument at that position, also when it is declared in an imported file or is written in terms of another generic alias.
