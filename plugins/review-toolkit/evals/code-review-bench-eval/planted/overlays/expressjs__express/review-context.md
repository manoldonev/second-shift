# Review context — Express 4

Express is a web framework for Node.js. `lib/` holds the framework: `application.js` (the
app), `request.js` and `response.js` (the extensions of Node's request and response), and
`router/` (the router, its routes and its layers).

## Conventions

- Express 4 supports every Node.js version its `engines` field names, back to 0.10. Code in
  `lib/` uses `var` and `function` expressions. It never uses `let`, `const`, arrow functions,
  classes or template literals.
- A public API keeps its signature and its behavior for every input it accepted before,
  unless the change is a documented major-version break.

## Tests

Mocha, under `test/`, one file per API (`test/res.location.js`, `test/req.hostname.js`). A
test builds an app with `express()` and drives it with supertest's `request(app)`.
