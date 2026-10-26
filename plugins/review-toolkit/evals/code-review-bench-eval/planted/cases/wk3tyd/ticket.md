# Caret in on-screen error output points to the wrong line

### Describe the bug

When there is a LESS compilation error and the error appears in the browser, the caret points to the wrong line:

![image](https://github.com/vitejs/vite/assets/10719780/7a2db786-788d-48fa-91d8-a0a74d87a52a)

In the scenario above, the problem is on line 14 (`display.less` is missing). The error message at the top is correct, and the horizontal (column) location of the caret seems correct, but it's off by one line. It's pointing to line 13 instead of line 14. This issue is 100% reproducible with any kind of LESS compilation error.

### Reproduction

N/A

### Steps to reproduce

Induce a LESS compilation error (e.g. missing import).

### System Info

```shell
System:
    OS: Windows 10 10.0.22621
    CPU: (8) x64 11th Gen Intel(R) Core(TM) i7-1185G7 @ 3.00GHz
    Memory: 4.77 GB / 15.71 GB
  Binaries:
    Node: 18.16.0 - C:\Program Files\Node.js\node.EXE
    npm: 9.8.0 - C:\Program Files\Node.js\npm.CMD
    pnpm: 8.6.10 - C:\Program Files\Node.js\pnpm.CMD
  Browsers:
    Edge: Spartan (44.22621.2215.0), Chromium (116.0.1938.69)
    Internet Explorer: 11.0.22621.1
  npmPackages:
    @vitejs/plugin-react: 4.0.4 => 4.0.4
    vite: 4.4.9 => 4.4.9
```

### Used Package Manager

pnpm

## Acceptance criteria

- AC-1: A code frame for a position at column 0 of a line puts the caret on that line, and a code frame for a position inside a line puts the caret under that column, for a numeric offset and for a line/column position.
- AC-2: A code frame for a source with CRLF line endings puts the caret on the line of the position.
- AC-3: A code frame given an end position underlines from the start to the end, on one line or across lines.
