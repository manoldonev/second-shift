# Tests No Longer Passing since Upgrading to v1.5.0

### Describe the bug

After upgrading axios from 1.4.0 to 1.5.0, tests that use network calls all fail consistently.

In my tests, I use Vitetest with Pretender intercepting network calls. None of my network tests pass with axios `1.5.0`. I get the following error messages:

```javascript
  code: 'ECONNREFUSED',
  errors: [
    Error: connect ECONNREFUSED 127.0.0.1:80
        at createConnectionError (node:net:1630:14)
        at afterConnectMultiple (node:net:1660:40) {
      errno: -61,
      code: 'ECONNREFUSED',
      syscall: 'connect',
      address: '127.0.0.1',
      port: 80
    },
    Error: connect ECONNREFUSED ::1:80
        at createConnectionError (node:net:1630:14)
        at afterConnectMultiple (node:net:1660:40) {
      errno: -61,
      code: 'ECONNREFUSED',
      syscall: 'connect',
      address: '::1',
      port: 80
    }
  ],
```

Can confirm this is from axios. Downgrading back to `1.4.0` resolves the problem. 


### To Reproduce

Using the last version of Pretender and an axios instance using v1.5.0, attempt to intercept a network call in a test environment, using Jest or Vitest.

### Expected behavior

Pretender should be able to intercept network calls in the test environment.

### Axios Version

1.5.0

### Node.js Version

20.4.0

### OS

Mac OS 13.4

### Additional Library Versions

```bash
Pretender 3.4.7
React 18.2.0
```

## Acceptance criteria

- AC-1: `getAdapter` returns a function handle as it is, and finds a named adapter in any letter case.
- AC-2: Given a list, `getAdapter` returns the first adapter that is available, and skips one that the environment does not support (`false`) or that the build does not hold (`null`).
- AC-3: When no adapter is available, the error says, for each adapter, whether the environment does not support it or the build does not hold it.
