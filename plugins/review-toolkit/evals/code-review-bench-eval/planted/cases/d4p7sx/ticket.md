# .format('YYYY') returns less than 4 digits for years < 1000

According to the [documentation](https://day.js.org/docs/en/parse/string-format#list-of-all-available-parsing-tokens), `YYYY` should return the 4-digit year. However, if the year is smaller than 1000 it returns a year with less than 4 digits.

For example, `dayjs('0202-01-01').format('YYYY-MM-DD')` returns `202-01-01`, which is to my understanding an invalid ISO date. It should return `0202-01-01` instead.

## Acceptance criteria

- AC-1: `YYYY` pads the year to four digits with zeros: `dayjs('0202-01-01').format('YYYY-MM-DD')` returns `0202-01-01`.
- AC-2: `YY` is unchanged: it returns the last two digits of the year.
