# loop varible is undefined in inline anonymous function in template

### Vue version

latest

### Link to minimal reproduction

https://play.vuejs.org/#eNqFUcFOwzAM/RUrl7bS1gqOoxsDCRDiAAc4LTuUkqKKNIkaDyFV+XecZmXdijQpBz/7xX5+7tiNMen3TrAFy1E0RhYoVlwB5LWStRJzFBY9BkDxg0vObt8eOAuZtRVSlDivaikslUIWIO6gT4FLYLmCbsgDVLqFuNTKYs8AXQVmMiYBSP0ZR0URzfrqdaqKRiRXB4Ybwn0QRme98GPpg+rnJ84megO894gz/zvPRh7ktmxrg2AF7gzhujG6RXjsm7/63lWrG5qdZoec9zKo4SrsSbvAEnyspUgJDYXRdCL859lZt0ZdY86KgrOpY2QRvTwL29AebMaO9U5v/75D1ArWpazLLzJKNDXG0UgwXWavdwGbDvy0BVyAmw3xJbgtrcLZqutMq41N/SGcy7PQ+9Tsqd1h7/4v2fMhKlL84lG8iXyvaJsMJC/vj3NHgDgn1916M8YmuF91Vv1F

### Steps to reproduce

Click `BUG`, you will see console output:
```
aa undefined
```

### What is expected?

output should be:
```
aa 1
aa 2
```

### What is actually happening?

```
aa undefined
```

### System Info

_No response_

### Any additional comments?

_No response_

## Acceptance criteria

- AC-1: A variable declared by a `for (const item of list)` loop inside an inline arrow-function event handler in a template compiles as the loop variable itself, not as `_ctx.item`, so the handler sees each item.
- AC-2: The variables of an array-destructured loop, `for (const [item, index] of entries)`, inside an inline arrow-function handler also compile as local variables, not as `_ctx` properties.
