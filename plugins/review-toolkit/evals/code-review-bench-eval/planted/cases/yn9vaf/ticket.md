# .prettierrc.json and .prettierrc.toml reject a leading UTF-8 BOM

**Environments:**

- Prettier Version: 3.10.0-dev (commit 1a153120)
- Running Prettier via: CLI
- Runtime: Node.js v25.6.0
- Operating System: Windows 11 64-bit
- Prettier plugins (if any): None

**Steps to reproduce:**

Create a JavaScript file:

```js
// example.js
const message = "hello";
```

Create a `.prettierrc.json` file whose content is a leading UTF-8 BOM (U+FEFF) followed by `{"semi":false}` and a newline.

Run Prettier:

```console
node ./bin/prettier.cjs --config .prettierrc.json example.js
```

The same issue can be reproduced with TOML: a `.prettierrc.toml` whose content is a leading BOM followed by `semi = false`.

```console
node ./bin/prettier.cjs --config .prettierrc.toml example.js
```

For comparison, configuration files containing the same leading BOM work when using JSON5 or YAML.

**Expected behavior:**

Prettier should ignore a single leading UTF-8 BOM when reading textual configuration files and format the JavaScript file as:

```js
const message = "hello"
```

This would make the behavior consistent across JSON, TOML, JSON5, and YAML configuration files.

RFC 8259 also allows JSON parsers to ignore a leading BOM for interoperability:

https://www.rfc-editor.org/rfc/rfc8259.html#section-8.1

**Actual behavior:**

The JSON configuration exits with status code 2:

```text
Invalid configuration for file "example.js":
JSON Error in .prettierrc.json:
Unexpected token U+FEFF
```

The TOML configuration also exits with status code 2:

```text
Invalid configuration for file "example.js":
TOML Error in .prettierrc.toml:
Invalid TOML document: only letters, numbers, dashes and underscores are allowed in keys
```

## Acceptance criteria

- AC-1: A `.prettierrc.json` or `.prettierrc.toml` that starts with a UTF-8 BOM is read as the same configuration as the file without the BOM, so `prettier --config .prettierrc.json example.js` prints `const message = "hello"` with no error.
- AC-2: Every other textual configuration file Prettier reads (a package.json `prettier` key, `.prettierrc`, `.prettierrc.yml`, `.prettierrc.json5`) gives the same configuration with or without a leading BOM.
