---
name: library-conformance
description: 'Shared procedure for the design-fidelity reviewers: how an override, a wrapper prop or a justification comment in a diff is checked against the UI library the repo has installed — the bounded reads, which theme applies, the dispositions, the evidence rule, severities and the summary lines. Loaded by figma-faithful-reviewer and design-faithful-reviewer through their skills: frontmatter.'
---

# Library conformance

An override, a wrapper prop and a justification comment are each a claim about the UI library the
repo has installed. Check each claim against the installed source. The design-system reference and
your memory of the library are not evidence: the installed version is what renders. Each reviewer
that loads this skill names its own stack's override forms; everything else about the check is
here.

## Reads, bounded

Read installed source only for diff lines that carry an override, a wrapper prop or a claim about
the library. An import with none of those needs no installed read.

1. Resolve the import the way the repo resolves it: a workspace package, a path alias in `tsconfig`
   or the bundler config, or `node_modules/<package>`. Do this for the repo's wrapper package and
   for the base library it wraps (MUI, Radix, Kendo, …) where the wrapper defers to it.
2. Read the version from that package's installed `package.json`.
3. Open the compiled component of the wrapper (`dist`, `esm`, or `src` of a workspace package). A
   type declaration never shows which element a prop lands on; the compiled JS does.
4. **Theme layers.** Grep every override layer of the theme — the wrapper's `styleOverrides`,
   `defaultProps` and variant tables, a theme `overrides` module, a `cva` table, and any per-theme
   set merged over a base set — for the component's override key (`Mui<Name>`, `k-<name>`, or the
   repo library's equivalent) **and for the key of the root it renders** (Paper, InputBase,
   FormControl, OutlinedInput, …), then open those files. A theme file reached only through the
   component's import name is not enough: composition and a two-layer merge put the applied value
   in another file.

Batch the `Glob`/`Grep` for the diff's imports into one or two calls, and open each installed file
once. A file still unread when your deadline arrives is a named gap in `summary` —
`unable to verify — pointer needed: <file>` — never a pass and never a finding.

When no installed source is on disk for the libraries the diff uses, write this line once, in the
prose and in `summary`: `Installed source not present; library conformance not checked.` Do not
repeat it per override. It is not a finding, an approve stays possible, and the other rules still
apply.

## Which theme applies

An override the component applies itself — its own styles, its own variant table, a style the
wrapper merges in its own file — applies wherever the component renders and needs no mount check.

An override that lives in a theme module reached through a provider applies only where that
provider is mounted. When the repo's design-system reference states which theme a surface mounts,
cite that statement. Otherwise read the app entry — the file that mounts the root `ThemeProvider`
or its equivalent. When neither tells you which theme the screen renders under, do not flag a
claim that depends on it.

## Dispositions

For each override the diff adds over a library component, decide from the installed source:

- **redundant** — the library already applies it: a theme override, a default prop, a variant, or
  the component's own styles;
- **prop exists** — a prop or variant of the component does the same thing;
- **necessary** — the library does not do it.

**Condition rule.** The cited line must apply under the diff's variant, size, state and breakpoint
condition. A value the theme sets only under another variant, size, state or breakpoint is not
redundant, and a variant that would also change other properties is not `prop exists`. When the
condition does not hold, suppress.

**Wrapper prop routing.** For each prop the diff passes to a wrapper, check in the compiled wrapper
that it reaches the element the caller means. A prop the wrapper drops, or routes to another
element, is wrapper-API misuse: an `aria-label` that lands on the FormControl root instead of the
input or combobox; a caller `whiteSpace` that replaces the one an `ellipsis` prop sets, so the
ellipsis is lost. The accessibility reviewer may report the same line; the overlap is accepted.

**Justification comments.** A comment in the diff that says what the library does or does not do
("the library exports no media-query hook", "the menu paper sits at `zIndex` 1") is a claim to
verify, never a waiver. Open the installed source and check it.

## Evidence and severity

A library-conformance finding is flagged at full confidence (90-100) only with the installed
`path:line` that proves it. Without that line it is not flagged. Doubt does not lower the score;
the installed line is the whole test.

| Class | Severity |
| --- | --- |
| A redundant or prop-exists override | Warning |
| A justification comment the installed source contradicts | Warning |
| A wrapper prop the wrapper drops or routes to the wrong element | Warning |

A dropped or misrouted wrapper prop changes behavior, and it is still a Warning: the fidelity seat
is design-blind, it does not block on behavior, and the human who reads the verdict decides.

Each finding sits on the diff line, and its `Evidence:` cites the installed `path:line` that
proves it. For a false comment, say that the comment is false and cite the line that disproves it.
`Recommendation:` says to drop the override, use the prop or variant, pass the prop the way the
wrapper forwards it, or correct the comment.

## Summary lines

For each override you checked, write one line: the override, its disposition (redundant, prop
exists or necessary) and the installed `path:line`. These lines are not findings and do not count
against the verdict. A redundant or prop-exists override also gets its Warning finding.

The source-absent line, each gap line and the per-override lines go in the prose **and** in
`summary`. A line that sits only in the prose never reaches the lead: review-lead carries
`summary` into its Review Summary.
