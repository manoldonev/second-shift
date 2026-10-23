# `dayjs.updateLocale` does not support setting `invalidDate` string

I am migrating a project from Moment.js to Day.js, but this project relies on `updateLocale` to display nullish dates as `-`. I see that Day.js always returns the same constant string when a date is invalid: https://github.com/iamkun/dayjs/blob/0fdac93ff2531542301b76952be9b084b2e2dfa0/src/index.js#L254

Are there any plans to allow this string to be overridden in Day.js? And in the meantime, what's a good workaround?

Below I compare the behavior of Moment.js and Day.js
```js
> const dayjs = require("dayjs");
undefined

> const moment = require("moment");
undefined

> moment(null).format()
'Invalid date'

> dayjs(null).format()
'Invalid Date'

> moment.updateLocale('en', { invalidDate: "-" })
Locale {
  ...
}

> moment(null).format()
'-'

> const updateLocale = require("dayjs/plugin/updateLocale");
undefined

> dayjs.extend(updateLocale);
[Function: v] {
  ...
}

> dayjs.updateLocale('en', { invalidDate: "-" });
{
  name: 'en',
  weekdays: [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday'
  ],
  months: [
    'January',   'February',
    'March',     'April',
    'May',       'June',
    'July',      'August',
    'September', 'October',
    'November',  'December'
  ],
  invalidDate: '-'
}

> dayjs(null).format()
'Invalid Date'
```

## Acceptance criteria

- AC-1: After `dayjs.updateLocale('en', { invalidDate: 'bad date' })`, `format()` of an invalid date returns `bad date`, as Moment.js does.
