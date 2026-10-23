# gggg not working correctly

**Describe the bug**
gggg not returns week year, but just a year
The same functionality in moment js works correctly

```javascript
const dayjs = require('dayjs');
const moment = require('moment')
const weekOfYear = require('dayjs/plugin/weekOfYear');
const weekYear = require('dayjs/plugin/weekYear');
const advancedFormat = require('dayjs/plugin/advancedFormat');
require('dayjs/locale/en-gb')
dayjs.locale('en-gb')

dayjs.extend(weekYear)
dayjs.extend(weekOfYear)
dayjs.extend(advancedFormat)
console.log(dayjs().toString())
console.log(dayjs().format('gggg-ww'))
console.log(moment().locale('en-gb').format('gggg-ww'))
```

**Expected behavior**
Sun, 03 Jan 2021 20:38:27 GMT
2020-53
2020-53

**Result**
Sun, 03 Jan 2021 20:38:27 GMT
**_2021-53_**
2020-53

**Information**
 - Day.js Version 1.10.1
 - OS: linux
 - Browser chrome 87
 - Time zone: UTC+3 (Europe/Moscow)

## Acceptance criteria

- AC-1: With a locale whose week year starts on the week of January 4th (`en-gb`), a day in early January that falls in the last week of the previous year has that previous year as its `weekYear()`, as Moment.js returns.
