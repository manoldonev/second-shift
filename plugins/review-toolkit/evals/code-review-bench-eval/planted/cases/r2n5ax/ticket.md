# dayjs.duration().humanize() international

My code:
```
import dayjs from 'dayjs'
import duration from 'dayjs/plugin/duration'
import relativeTime from 'dayjs/plugin/relativeTime'
import localeData from 'dayjs/plugin/localeData'

import 'dayjs/locale/zh-cn'

dayjs.extend(duration)
dayjs.extend(relativeTime)
dayjs.extend(localeData)

dayjs.locale('zh-cn')

dayjs.duration(24 * 60 * 60 * 1000).humanize() // return ' a day'
```
How to make "humanize()" return a Chinese string? I need your help, thanks.

## Acceptance criteria

- AC-1: A duration created with `dayjs.duration()` takes the global locale that `dayjs.locale()` set, so `humanize()` speaks that locale: after `dayjs.locale('fr')`, `dayjs.duration(1, 'minutes').humanize(true)` returns `dans une minute`.
