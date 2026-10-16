# Plan — #1068 the bot-id cache follows appName and never caches a 404

Decision record: [second-shift-1068-decisions.md](second-shift-1068-decisions.md)

## 1. Selftest cases

- [ ] 1.1 A matching id file and name cache commit with the cached id, with no gh call and no WARN (plugins/dev-pipeline/tools/bot-commit-selftest.sh) [AC-1]
- [ ] 1.2 A name cache for another name re-looks with a per-login gh stub, commits with the new id and rewrites both files (plugins/dev-pipeline/tools/bot-commit-selftest.sh) [AC-2]
- [ ] 1.3 A mismatch whose gh stub exits 1 with GitHub's 404 JSON on stdout WARNs, commits as the repo default and leaves both files unchanged (plugins/dev-pipeline/tools/bot-commit-selftest.sh) [AC-3]
- [ ] 1.4 An id file with no name cache looks the name up, for both a good and a failed lookup (plugins/dev-pipeline/tools/bot-commit-selftest.sh) [AC-4]
- [ ] 1.5 An id file holding text, JSON or a carriage return is not used, and a lookup runs (plugins/dev-pipeline/tools/bot-commit-selftest.sh) [AC-5]
- [ ] 1.6 A name cache whose id differs from the id file's, and an empty id file, trigger a lookup (plugins/dev-pipeline/tools/bot-commit-selftest.sh) [AC-7]
- [ ] 1.7 A directory at each cache file's path WARNs, and the commit still happens with the resolved id and exit 0 (plugins/dev-pipeline/tools/bot-commit-selftest.sh) [AC-8]

## 2. bot-commit.sh

- [ ] 2.1 Add the name cache beside the id cache, trust the id only on a whole-string match, require a numeric id, and make cache reads and writes non-fatal (plugins/dev-pipeline/tools/bot-commit.sh)

## 3. Docs

- [ ] 3.1 Add a note on renaming an App; AC-6 is exempt from a test under D-7 (plugins/dev-pipeline/tools/tracker/github/README.md)
