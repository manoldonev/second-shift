# dayjs() instanceof dayjs = false

Hi,
I tried to replace moment with dayjs,but some old code have this condition:
```
if (aMomentDate instanceof moment) {
//do something
}
```
if this meet dayjs, it would be false and the `if` can not be enter.

after I found the problem , I tried this:
```
moment() instanceof moment
//true
```
and this:
```
dayjs() instanceof dayjs
//false
```

So, is it necessary to be fixed?

## Acceptance criteria

- AC-1: `dayjs() instanceof dayjs` is `true`.
- AC-2: `dayjs.isDayjs(dayjs())` stays `true`.
- AC-3: The API reference says that `instanceof` works, beside `dayjs.isDayjs`.
