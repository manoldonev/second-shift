# Add support async handlers

Hi folks,

I had an idea to support catching errors in an async function without an 'unhandledPromiseRejectionError'.

This gives developers the freedom to throw again but also means they don't have to do the following pattern.

```javascript
async function (req, res, next) {
  let result;
  try {
    result = await something();
  } catch (err) {
    next(err);
  }
  res.send(result);
}
```

They can instead do:
```javascript
async function (req, res, next) {
  res.send(await something());
}
```

PR done as an idea: #3695

## Acceptance criteria

- AC-1: An async request handler that throws passes its error to `next`, so the route's error handlers run and the request handlers after it are skipped.
- AC-2: An async error handler that throws passes its error to the next error handler.
