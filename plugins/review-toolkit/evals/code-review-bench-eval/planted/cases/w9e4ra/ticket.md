# CustomParseFormat: Issue with parsing dates in 'D-MM-YYYY' format

**Describe the bug**

```
import dayjs from 'dayjs';
import customParseFormat from 'dayjs/plugin/customParseFormat';

dayjs.extend(customParseFormat);

const date = dayjs('21-Dec-18', 'D-MMM-YY').toJSON()
// Date is Sun Jan 21 2018
```

**Expected behavior**
Date is Sun Dec 21 2018

**Information**
 - Day.js Version: v1.8.27 (The issue does not exist on v1.8.26)
 - OS: macOS Catalina
 - Node.js version: v12
 - Time zone: GMT+2 Central European Summer Time

## Acceptance criteria

- AC-1: With customParseFormat, `dayjs('21-Dec-18', 'D-MMM-YY')` is 21 December 2018, as Moment.js parses it.
- AC-2: `dayjs('21-December-18', 'D-MMMM-YY')` is 21 December 2018, as Moment.js parses it.
