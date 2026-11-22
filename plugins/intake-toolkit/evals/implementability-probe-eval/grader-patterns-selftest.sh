#!/usr/bin/env bash
# Selftest for the notes-file-not-read pattern of case.yaml. It reads the pattern from the case
# file and runs it on tool calls as a run's trace holds them: a call that reads the interview notes
# must match, and a search that only excludes docs/plans must not.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

command -v node >/dev/null 2>&1 || {
  echo "grader-patterns-selftest: FAIL — node is required to run the case's regex." >&2
  exit 1
}

CASE_FILE="$HERE/case.yaml" node - <<'EOF'
const fs = require('fs');
const text = fs.readFileSync(process.env.CASE_FILE, 'utf8');
const found = text.match(/- name: notes-file-not-read\n(?:    .*\n)*?    pattern: '(.*)'\n/);
if (!found) {
  console.log('  ✗ case.yaml holds no notes-file-not-read pattern');
  console.log('\ngrader-patterns-selftest: 1 FAILURE(S)');
  process.exit(1);
}
const pattern = new RegExp(found[1]);
const bash = (command) =>
  JSON.stringify({ type: 'tool_use', id: 'x', name: 'Bash', input: { command, description: 'd' } });
const tool = (name, input) => JSON.stringify({ type: 'tool_use', id: 'x', name, input });
const notes = 'docs/plans/ledger-lint-json-interview-notes.md';

const reads = [
  ['a Read of the notes file', tool('Read', { file_path: `/tmp/e/home/cwd/${notes}` })],
  ['a Grep over docs/plans', tool('Grep', { pattern: 'exit', path: '/tmp/e/home/cwd/docs/plans' })],
  ['cat of the notes file', bash(`cat ${notes}`)],
  ['cat of the quoted notes file', bash(`cat "${notes}"`)],
  ['head of every file in docs/plans', bash('cd x && head -50 docs/plans/*.md')],
  ['grep -r over docs/plans/', bash('grep -rn exit docs/plans/')],
  ['grep -r over the absolute docs/plans', bash('grep -rn "exit" /tmp/e/home/cwd/docs/plans | head')],
];
const notReads = [
  ['cat of the ticket and the record', bash('cat docs/plans/ledger-lint-json-ticket.md && cat docs/plans/ledger-lint-json-decisions.md')],
  ['a listing of docs/plans', bash('ls docs/plans/')],
  ['grep -v docs/plans', bash('grep -rn "1024" --include=*.md . | grep -v CHANGELOG | grep -v docs/plans | head')],
  ['grep -v of the quoted docs/plans/', bash('grep -rn "ledger-lint" . | grep -v "docs/plans/" | head')],
  ['--exclude-dir=docs/plans', bash('grep -rn x . --exclude-dir=docs/plans')],
  ['a ripgrep glob that excludes docs/plans', bash('rg -n x -g "!docs/plans/**" .')],
  ['grep -v of the notes file name', bash('grep -rn x . | grep -v interview-notes')],
  ['a Grep whose glob excludes docs/plans', tool('Grep', { pattern: 'x', glob: '!docs/plans/**' })],
  ['a Read of the record', tool('Read', { file_path: '/tmp/e/home/cwd/docs/plans/ledger-lint-json-decisions.md' })],
  ['a tool result that names the notes file', JSON.stringify({ type: 'tool_result', content: notes })],
];

let fails = 0;
const check = (want, [label, line]) => {
  const got = pattern.test(line);
  if (got === want) { console.log(`  ✓ ${label}: ${want ? 'counts as a read' : 'does not count'}`); return; }
  console.log(`  ✗ ${label}: ${got ? 'counts as a read' : 'does not count'}`);
  fails += 1;
};
reads.forEach((c) => check(true, c));
notReads.forEach((c) => check(false, c));

console.log('');
if (fails === 0) { console.log('grader-patterns-selftest: ALL PASS'); } else {
  console.log(`grader-patterns-selftest: ${fails} FAILURE(S)`);
  process.exit(1);
}
EOF
