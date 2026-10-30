# Plan — a directory-installed second-shift hands off to the marketplace copy

## 1. scope-shadows.sh reports the other-marketplace copy

- [ ] 1.1 Cases for the other-marketplace row: the copy alone and beside second-shift@second-shift, project scope at this root and at another root, a disabled record, the name filter and the unchanged exit status (plugins/second-shift/skills/doctor/tools/scope-shadows-selftest.sh) [AC-1] [AC-3]
- [ ] 1.2 Emit one other-marketplace row per second-shift record from another marketplace that loads at the root (plugins/second-shift/skills/doctor/tools/scope-shadows.sh)

## 2. doctor WARNs and orders the fix

- [ ] 2.1 Plugin-list fixtures holding second-shift@claude-plugins-official, with and without second-shift@second-shift, and at project scope (plugins/second-shift/skills/doctor/tools/doctor-fixtures)
- [ ] 2.2 Scenarios: WARN with the uninstall line and exit 0 while served, project-scope caution, exit 1 with install then uninstall when only the other copy is installed (plugins/second-shift/skills/doctor/tools/doctor-selftest.sh) [AC-2] [AC-3]
- [ ] 2.3 Read the other-marketplace rows: WARN per row while second-shift@second-shift is served, extend the not-installed FAIL otherwise (plugins/second-shift/skills/doctor/tools/doctor.sh)

## 3. onboard hand-off

- [ ] 3.1 Step 8 prints the user-scope install for second-shift and each uninstall line after the second-shift line (plugins/second-shift/skills/onboard/SKILL.md)
