# Multiple files for --ignore-path

I use the [--ignore-path](https://prettier.io/docs/en/cli.html#--ignore-path) argument and point it to an exhaustive `.gitignore` file. It's great that I don't have to duplicate the list of ignored files.

However, there are a couple of files I'd like to exclude from prettifying but still want to commit. Is there any way to specify an additonal `.prettierignore` file so that I can add files without copying the entire `.gitignore`?

## Acceptance criteria

- AC-1: `--ignore-path` can be passed more than once, and a file that any of the given ignore files lists is skipped by `--list-different`, `--check` and `--debug-check`; an ignore file that does not exist is skipped without an error.
- AC-2: `prettier --help ignore-path` and the full `--help` say that several values are accepted and show the default as `[.prettierignore]`.
