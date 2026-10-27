# Prettier should format JSONC with trailing commas

- Right now, Prettier's default value of "trailingCommas" is "all", which is fantastic. Presumably, most people who use Prettier would agree with this, as the reasons for wanting trailing commas are compelling: better Git diffs, easier refactoring, and so on.
- For all the same reasons that we would want trailing commas in a JavaScript/TypeScript file, we also want to have trailing commas in JSONC files.
- However, Prettier does not insert trailing commas into JSONC files by default.

You could frame this problem as either:
1. a bug in Prettier (since the default value of "trailingCommas" is supposed to be "all"), or
2. a failure in Prettier parsing JSONC properly

Either way, this should be changed.

## Steps to Reproduce

```ts
mkdir test
cd test
npm init --yes
npm install prettier --save-dev
echo '{ "foo": "bar" }' > test.jsonc
npx prettier test.jsonc --write
cat test.jsonc
```

Observe that the formatted JSONC file does not have trailing commas.

## Current Hacky Workaround

Use the following custom Prettier config:

```
  overrides: [
    {
      files: ["**/*.jsonc"],
      options: {
        parser: "json5",
        quoteProps: "preserve",
      },
    },
```

Since JSONC is a subset of JSON5, this works properly. However, it is important that we also specify `quoteProps: "preserve"`, as the default value for `quoteProps` for JSON5 is "as-needed", which would unquote JSON properties, making it non-valid JSONC.

Obviously, having to use a custom Prettier config is really unfortunate, as one of the main ideas of using Prettier is that you shouldn't use your own custom config, you should just use all the default values. But this bug / bad default behavior prevents that.

Also, as a semi-related note, it was proposed that the default value for `quoteProps` in JSON5 would be changed in #4639. If a PR for that was accepted, then we could simplify the workaround slightly, although the ideal solution is to not to have to do a workaround to begin with.

## Summarizing Prior Discussion

This issue continues #5708.

The core issue is that Prettier does not have a separate parser for JSONC files, it just uses the JSON parser. Since the JSON parser works with comments, this "just works" some of the time, but crashes and burns when trailing commas are involved.

ikatyang says [here](https://github.com/prettier/prettier/issues/5708#issuecomment-452523700) that they considered making a JSONC parser, but this was confusing, as it was really just a trailing commas parser and not a comment parser. Which is definitely a valid concern!

However, five years have passed since that comment, and JSONC files have only become more prevalent in the ecosystem. For example, popular tools like [CSpell](https://github.com/streetsidesoftware/cspell) (code spell checker), [Knip](https://github.com/webpro/knip) (dead code finder), and [TypeDoc](https://github.com/TypeStrong/typedoc) (documentation generator) all support JSONC files by default ("cspell.jsonc", "knip.jsonc", and "typedoc.jsonc" respectively).

Thus, there is a more compelling reason for Prettier to support the JSONC format more robustly. To @ikatyang, and the rest of the Prettier team, can we revisit this decision? A dedicated parser for JSONC means that we can finally format JSONC files properly out of the box without having to use the dirty JSON5 hack specified above.

## Acceptance criteria

- AC-1: A new `jsonc` parser prints trailing commas in objects and arrays as the `trailingComma` option says (`none`, `es5`, `all`), so the default adds them.
- AC-2: With the `jsonc` parser every object key stays quoted, whatever `quoteProps` is set to.
- AC-3: With the `jsonc` parser strings are printed with double quotes, even when `singleQuote` is true.
- AC-4: Files of the JSON with Comments language (for example `.jsonc` files and `.swcrc`) are formatted with the `jsonc` parser by default.
