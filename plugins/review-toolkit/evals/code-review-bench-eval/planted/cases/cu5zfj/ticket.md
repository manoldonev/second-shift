# Vue 3 SFC Compiler function call with semicolon bug.

### Vue version

3.2.47

### Link to minimal reproduction

https://github.com/houd1ni/vue-issues

### Steps to reproduce

- npm i
- npm run dev
- open in a browser (mine is ff latest).
- See the console.

At first glance, it is a sfc compiler stuff.
If it is a vite's issue, I'd open it there and close here, though.

### What is expected?

Clean console, Compo.vue output with its' hello.

### What is actually happening?

It is crashing because the compiler removes semicolons and moves ;(window) after a function call.

![image](https://user-images.githubusercontent.com/7501201/222035769-c2e719c7-9278-4cbd-bf55-e040ee0488d4.png)


### System Info

```shell
ff111.0b3 @ win10x64 intel 12100 w 32GbDDR43200.
node v19.2.0
```


### Any additional comments?

😭

## Acceptance criteria

- AC-1: A `<script setup>` written without semicolons, with `const props = defineProps(...)` and `const emit = defineEmits(...)` between a call and an IIFE, compiles with every statement in its place, `const props = __props` and `const emit = __emit`, so the IIFE is not chained onto the call before it.
- AC-2: `defineEmits` assigned to any name compiles to that name assigned from `__emit` in place, and `setup` receives the emit function as `emit: __emit`.
- AC-3: With props destructure enabled, a destructured `defineProps` inside a multi-variable declaration is removed and the other declarators compile unchanged.
