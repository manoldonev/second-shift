# gate-ablation.awk — the table generator behind tools/gate-ablation.sh (#609).
#
# Reads the reason-class map, the adjudication table and the verdict index in BEGIN, then walks the
# manifest-pinned progress records passed as arguments and emits the report's generated block.
#
# Portable across the awks this lane actually meets, which is not the same as one-true-awk
# portable: no asort, no ENDFILE, no mktime, and epoch conversion is days-from-civil arithmetic.
# A local run and BOTH macOS CI jobs share a single awk — the bash-3.2 lane shims the shell, not
# the toolchain — so a green pair there is evidence about one implementation. The job that gates
# the merge runs on ubuntu, where `awk` resolves through /etc/alternatives to GNU Awk 5.2.1. An
# edit here is unverified until that job is green; see the seeding note above report().
#
# Row grammar (lean-gate.sh's append_line / append_obligation):
#   TS | milestone-N | started |
#   TS | milestone-N | satisfied
#   TS | milestone-N | attempt | <reason>
#   TS | milestone-N | absent  | <reason>
#   TS | milestone-N | advisory | <text>
#   TS | milestone-N | obligation | <name> | met|unmet
#   TS | milestone-N | concluded | rc=<n>
#   TS | session | <uuid>
# A FIRING is an `attempt` or an `absent` row: those and only those are a gate refusing. `absent`
# is the same decision point recorded under a later schema that spends no fix budget (#609 F-5),
# so the two verbs are counted as one point and the split is reported rather than doubled.

function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function detrail(s) { s = trim(s); sub(/[ \t]*\|$/, "", s); return trim(s) }

# Days from 1970-01-01 (Howard Hinnant's civil_from_days, inverted). No mktime anywhere.
function days_from_civil(y, m, d,   era, yoe, doy, doe) {
  y -= (m <= 2)
  era = int((y >= 0 ? y : y - 399) / 400)
  yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}
function epoch(ts,   y, mo, d, h, mi, s) {
  if (ts !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/) return -1
  y  = substr(ts, 1, 4) + 0;  mo = substr(ts, 6, 2) + 0;  d = substr(ts, 9, 2) + 0
  h  = substr(ts, 12, 2) + 0; mi = substr(ts, 15, 2) + 0; s = substr(ts, 18, 2) + 0
  return days_from_civil(y, mo, d) * 86400 + h * 3600 + mi * 60 + s
}

function readfile(path, kind,   line, n, f) {
  while ((getline line < path) > 0) {
    if (line ~ /^[ \t]*#/ || trim(line) == "") continue
    n = split(line, f, "\t")
    if (kind == "classes") {
      if (n < 5) { err("classes table row has " n " fields, want 5: " line); }
      ncls++
      cls_gp[ncls] = trim(f[1]); cls_ms[ncls] = trim(f[2]); cls_ob[ncls] = trim(f[3])
      cls_pat[ncls] = f[4];      cls_lb[ncls] = trim(f[5])
      if (trim(f[3]) == "-") cls_ob[ncls] = ""
    } else if (kind == "adj") {
      if (n < 5) { err("adjudication table row has " n " fields, want 5: " line); }
      adj_dec[trim(f[1])]  = trim(f[2]); adj_fr[trim(f[1])]   = trim(f[3])
      adj_cite[trim(f[1])] = trim(f[4]); adj_note[trim(f[1])] = trim(f[5])
    } else if (kind == "verdict") {
      v_rounds[trim(f[1])] = trim(f[2]); v_inh[trim(f[1])] = trim(f[3]); v_rev[trim(f[1])] = trim(f[4])
    }
  }
  close(path)
}

# awk's `exit` does not leave the program — it runs END. Without this latch, END re-enters
# flush() on the same record and the diagnostic prints twice, which reads as two defects.
function err(msg) { print "[gate-ablation] \xe2\x9c\x97 " msg; ERRED = 1; exit 1 }

BEGIN {
  readfile(classes, "classes")
  readfile(adj, "adj")
  readfile(vindex, "verdict")
  if (ncls == 0) err("the reason-class table declares no decision points")
  nrec = 0
}

# ---------------------------------------------------------------- per-record buffering
FNR == 1 { if (cur != "") flush(); cur = FILENAME; rn = 0
           cur_id = FILENAME; sub(/^.*\//, "", cur_id); cur_issue = cur_id; sub(/-lean-progress\.md$/, "", cur_issue) }
{
  nf = split($0, a, " \\| ")
  if (nf < 2) next
  ts = trim(a[1]); if (epoch(ts) < 0) next
  rn++
  r_ts[rn] = epoch(ts); r_iso[rn] = ts; r_ms[rn] = ""; r_verb[rn] = ""; r_reason[rn] = ""; r_kind[rn] = ""
  if (a[2] == "session") { r_kind[rn] = "session"; next }
  if (a[2] !~ /^milestone-[0-9]+$/) { r_kind[rn] = "other"; next }
  r_kind[rn] = "milestone"; r_ms[rn] = substr(a[2], 11)
  r_verb[rn] = detrail(a[3])
  rest = ""
  for (i = 4; i <= nf; i++) rest = rest (rest == "" ? "" : " | ") a[i]
  r_reason[rn] = detrail(rest)
}
END { if (ERRED) exit 1; if (cur != "") flush(); if (ERRED) exit 1; report() }

# ---------------------------------------------------------------- scoring one record
function flush(   i, j, gp, key, k1, k2, dec, ms, reason, e, rw, mech, last4, idx) {
  nrec++
  recs[nrec] = cur_id
  # Record fidelity. Most records stop before the run does — the close-out happens in a later
  # session, or the lane ends at a handoff — so `no-response` below is largely a statement about
  # the record, not about the lane. These two counts are what keep that visible.
  for (i = 1; i <= rn; i++) {
    if (r_kind[i] != "milestone" || r_verb[i] != "satisfied") continue
    if (r_ms[i] == "4") { if (!seen4) { reach4++; seen4 = 1 } }
    if (r_ms[i] == "5") { if (!seen5) { reach5++; seen5 = 1 } }
  }
  seen4 = 0; seen5 = 0
  # the last milestone-4 firing is the only one a committed verdict record can speak to
  last4 = 0
  for (i = 1; i <= rn; i++)
    if (r_kind[i] == "milestone" && r_ms[i] == "4" && (r_verb[i] == "attempt" || r_verb[i] == "absent")) last4 = i
  for (i = 1; i <= rn; i++) {
    if (r_kind[i] != "milestone") continue
    if (r_verb[i] == "obligation") { n_oblig++; continue }
    if (r_verb[i] == "advisory") { n_advisory[r_ms[i]]++; n_advisory_tot++; continue }
    if (r_verb[i] != "attempt" && r_verb[i] != "absent") continue

    ms = r_ms[i]; reason = r_reason[i]
    gp = classify(ms, reason)
    if (gp == "") err(cur_id " " r_iso[i] ": milestone-" ms " reason matches no row in the reason-class table: " reason)
    if (granularity == "milestone") gp = "milestone-" ms

    k1 = cur_issue ":" gp; k2 = gp
    key = (k1 in adj_dec) ? k1 : ((k2 in adj_dec) ? k2 : "")
    if (key == "") err(cur_id " " r_iso[i] ": gate point '" gp "' has no row in the adjudication table (key '" k2 "' or '" k1 "')")
    dec = adj_dec[key]
    if (dec != "changed" && dec != "unchanged" && dec != "undetermined")
      err("adjudication row '" key "' carries decision '" dec "' (want changed|unchanged|undetermined)")

    mech = mechanical(i, ms, (i == last4))
    e = eval_span(i, ms); rw = rework_span(i, ms)

    nf_all++
    f_rec[nf_all] = cur_id; f_iso[nf_all] = r_iso[i]
    f_ms[nf_all] = ms; f_gp[nf_all] = gp; f_verb[nf_all] = r_verb[i]
    f_mech[nf_all] = mech; f_dec[nf_all] = dec; f_key[nf_all] = key
    f_repeat[nf_all] = is_repeat(i, ms, gp)

    fire[gp]++; fire_verb[gp " " r_verb[i]]++
    mech_n[gp " " mech]++; dec_n[gp " " dec]++
    if (e >= 0) { eval_s[gp] += e; eval_cov[gp]++ }
    if (rw >= 0) { rework_s[gp] += rw; rework_cov[gp]++ }
    if (dec == "changed" && !(gp in keep_when)) { keep_when[gp] = r_iso[i]; keep_key[gp] = key }
    if (adj_fr[key] == "yes") { false_red[gp]++; if (!(gp in fr_when)) { fr_when[gp] = r_iso[i]; fr_key[gp] = key } }
    if (f_repeat[nf_all]) repeat_n[gp]++
  }
  rn = 0
}
function classify(ms, reason,   i) {
  for (i = 1; i <= ncls; i++) {
    if (cls_ms[i] != ms) continue
    if (reason ~ cls_pat[i]) return cls_gp[i]
  }
  return ""
}

# `no-response`: nothing in the record evaluates this milestone again, so the run never answered
# the refusal. Otherwise a real content diff exists only where a verdict-record round boundary
# covers the interval (#609 D-a) — everywhere else the honest value is `unmeasured`.
function mechanical(i, ms, is_last4,   j, later, inh, rev) {
  # The committed observation is consulted FIRST, and deliberately outranks the local record's
  # silence: a progress record that simply ends (most of this corpus does — see the fidelity rows)
  # is weak evidence that nothing happened, while a verdict record's round chain is a positive,
  # committed statement that the branch's patch identity did or did not move.
  if (ms == "4" && is_last4 && (cur_issue in v_rounds) \
      && v_rounds[cur_issue] ~ /^[0-9]+$/ && v_rounds[cur_issue] + 0 >= 2) {
    inh = v_inh[cur_issue]; rev = v_rev[cur_issue]
    if (inh ~ /^[0-9a-f][0-9a-f]*$/ && length(inh) >= 12 && rev ~ /^[0-9a-f][0-9a-f]*$/ && length(rev) >= 12)
      return (inh == rev) ? "content-still" : "content-moved"
  }
  later = 0
  for (j = i + 1; j <= rn; j++)
    if (r_kind[j] == "milestone" && r_ms[j] == ms && (r_verb[j] == "started" || r_verb[j] == "satisfied") && r_ts[j] > r_ts[i]) { later = 1; break }
  return later ? "unmeasured" : "no-response"
}

function eval_span(i, ms,   j, s, c) {
  s = -1; c = -1
  for (j = i; j >= 1; j--) if (r_kind[j] == "milestone" && r_ms[j] == ms && r_verb[j] == "started") { s = r_ts[j]; break }
  for (j = i; j <= rn; j++) if (r_kind[j] == "milestone" && r_ms[j] == ms && r_verb[j] == "concluded") { c = r_ts[j]; break }
  if (s < 0 || c < 0 || c < s) return -1
  return c - s
}
function rework_span(i, ms,   j) {
  for (j = i + 1; j <= rn; j++)
    if (r_kind[j] == "milestone" && r_ms[j] == ms && r_verb[j] == "started" && r_ts[j] > r_ts[i]) return r_ts[j] - r_ts[i]
  return -1
}

# AC-4's upper-bound diagnostic: the same point re-firing with nothing else in the record between
# the two. Reaping (a re-issued call that never concluded) and idempotent re-invocation both land
# here, which is why it is an over-count and is labeled as one.
function is_repeat(i, ms, gp,   j, prev) {
  prev = 0
  for (j = i - 1; j >= 1; j--) {
    if (r_kind[j] == "session") return 0
    if (r_kind[j] != "milestone") continue
    if (r_ms[j] != ms) return 0
    if (r_verb[j] == "attempt" || r_verb[j] == "absent") { prev = j; break }
  }
  if (prev == 0) return 0
  return (classify(ms, r_reason[prev]) == gp || granularity == "milestone")
}

# ---------------------------------------------------------------- rendering

# Rendering only ever READS the counters. Saying so in code rather than relying on it matters:
# gawk 5.2.1 — the `awk` on the ubuntu job that gates the merge — corrupts its heap when a read is
# also what creates the row being read. `fire[gp] + 0` for a point that never fired creates the
# element and forces it to a number in one step, and that read lands on a node an earlier `printf`
# already released: an 8-byte heap-use-after-free in r_force_number, surfacing as exit 139 on Linux
# and 134 on macOS, mid-table and with the tail of the report silently missing. Seeding is the fix
# and also the honest description of the tables: every declared point has a row whether or not it
# fired, and each value seeded here is the zero that row already prints, so no cell moves.
function zero(arr, k) { if (!(k in arr)) arr[k] = 0 }
function seed_counters(   i, m, gp) {
  for (i = 1; i <= ncls; i++) {
    gp = cls_gp[i]
    zero(fire, gp);   zero(fire_verb, gp " attempt");    zero(fire_verb, gp " absent")
    zero(mech_n, gp " content-moved"); zero(mech_n, gp " content-still")
    zero(mech_n, gp " no-response");   zero(mech_n, gp " unmeasured")
    zero(dec_n, gp " changed"); zero(dec_n, gp " unchanged"); zero(dec_n, gp " undetermined")
    zero(eval_s, gp);  zero(eval_cov, gp); zero(rework_s, gp); zero(rework_cov, gp)
    zero(false_red, gp); zero(repeat_n, gp)
  }
  for (m = 1; m <= 5; m++) zero(n_advisory, m "")
}
function cell(n) { return (n + 0 == 0) ? "—" : n "" }
function spanc(gp, tot, cov) { return (cov + 0 == 0) ? "—" : (tot + 0) " (" (cov + 0) "/" fire[gp] ")" }

function report(   i, j, gp, n, order, tmp, cost, ranked, nranked, swapped) {
  seed_counters()
  print ""
  print "### Corpus"
  print ""
  print "| | |"
  print "| --- | --- |"
  print "| scored records (artifact schema) | " nrec " |"
  print "| firings scored | " nf_all " |"
  print "| declared decision points | " ncls " |"
  print "| `obligation` rows in the corpus | " (n_oblig + 0) " |"
  print "| `advisory` rows in the corpus | " (n_advisory_tot + 0) advisory_by_ms() " |"
  print "| records reaching `milestone-4 satisfied` | " (reach4 + 0) " |"
  print "| records reaching `milestone-5 satisfied` | " (reach5 + 0) " |"
  print "| corpus manifest | `docs/gate-ablation-manifest.tsv` |"
  print ""
  print "### Decision points"
  print ""
  print "Every point the reason-class table declares, whether or not it ever fired. `mechanical` and"
  print "`adjudicated` are the two labeled columns of AC-2; `eval s` and `rework s` are the measured"
  print "cost, each with the number of firings it could be measured over."
  print ""
  print "| gate point | ms | obligation | firings | attempt / absent | mechanical | adjudicated | eval s | rework s |"
  print "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"
  for (i = 1; i <= ncls; i++) {
    gp = cls_gp[i]
    if (granularity == "milestone") continue
    printf "| `%s` | %s | %s | %s | %s / %s | %s | %s | %s | %s |\n", \
      gp, cls_ms[i], (cls_ob[i] == "" ? "—" : "`" cls_ob[i] "`"), cell(fire[gp]), \
      cell(fire_verb[gp " attempt"]), cell(fire_verb[gp " absent"]), \
      mechsum(gp), decsum(gp), spanc(gp, eval_s[gp], eval_cov[gp]), spanc(gp, rework_s[gp], rework_cov[gp])
  }
  print ""
  print "### Firings"
  print ""
  print "Every firing in the corpus, with its citation. `record • milestone • timestamp` locates the"
  print "row; the records themselves are host-local and pinned by the manifest."
  print ""
  print "| # | citation | gate point | verb | mechanical | adjudicated | repeat |"
  print "| --- | --- | --- | --- | --- | --- | --- |"
  for (i = 1; i <= nf_all; i++)
    printf "| %d | `%s` • milestone-%s • `%s` | `%s` | %s | %s | %s | %s |\n", \
      i, f_rec[i], f_ms[i], f_iso[i], f_gp[i], f_verb[i], f_mech[i], f_dec[i], (f_repeat[i] ? "yes" : "—")
  print ""
  print "### Demotion candidates"
  print ""
  print "Points that fired and whose every firing is adjudicated as changing no merge decision."
  print "Ranked by that count, then by evaluation cost. A point with even one decision-changing"
  print "firing is not here — it is in the earn-your-keep table below — and neither is a point whose"
  print "firings are all `undetermined`, which the decision-points table above still counts."
  print ""
  print "`eval s` is the time the gate spent evaluating, summed over the firings it could be measured"
  print "over, and it is the secondary key. `rework s` is wall-clock between a firing and the next"
  print "evaluation of that milestone: it is reported because it is measured, but it swallows every"
  print "interval where the operator was simply away and so ranks nothing."
  print ""
  print "| rank | gate point | zero-decision-change firings | of total | undetermined | eval s | rework s |"
  print "| --- | --- | --- | --- | --- | --- | --- |"
  nranked = 0
  for (i = 1; i <= ncls; i++) {
    gp = cls_gp[i]
    if (fire[gp] + 0 == 0) continue
    if (dec_n[gp " changed"] + 0 > 0) continue
    if (dec_n[gp " unchanged"] + 0 == 0) continue
    nranked++; ranked[nranked] = gp
  }
  for (i = 1; i < nranked; i++) for (j = 1; j <= nranked - i; j++) {
    if (worse(ranked[j], ranked[j+1])) { tmp = ranked[j]; ranked[j] = ranked[j+1]; ranked[j+1] = tmp }
  }
  for (i = 1; i <= nranked; i++) {
    gp = ranked[i]
    printf "| %d | `%s` | %d | %d | %s | %s | %s |\n", i, gp, dec_n[gp " unchanged"] + 0, fire[gp] + 0, \
      cell(dec_n[gp " undetermined"]), spanc(gp, eval_s[gp], eval_cov[gp]), spanc(gp, rework_s[gp], rework_cov[gp])
  }
  if (nranked == 0) print "| — | none | — | — | — | — | — |"
  print ""
  print "### Never fired"
  print ""
  print "Declared decision points with zero firings across the corpus. A point that never fired is a"
  print "different finding from one that fires and changes nothing, so the two are not merged."
  print ""
  print "| gate point | ms | obligation |"
  print "| --- | --- | --- |"
  n = 0
  for (i = 1; i <= ncls; i++) {
    gp = cls_gp[i]
    if (fire[gp] + 0 > 0) continue
    n++
    printf "| `%s` | %s | %s |\n", gp, cls_ms[i], (cls_ob[i] == "" ? "—" : "`" cls_ob[i] "`")
  }
  if (n == 0) print "| — | — | — |"
  print ""
  print "### Earn-your-keep"
  print ""
  print "Points carrying at least one firing adjudicated as changing what shipped, with the dated"
  print "incident that earns the block."
  print ""
  print "| gate point | first decision-changing firing | adjudication row | what changed |"
  print "| --- | --- | --- | --- |"
  n = 0
  for (i = 1; i <= ncls; i++) {
    gp = cls_gp[i]
    if (!(gp in keep_when)) continue
    n++
    printf "| `%s` | `%s` | `%s` | %s |\n", gp, keep_when[gp], keep_key[gp], adj_note[keep_key[gp]]
  }
  if (n == 0) print "| — | — | — | — |"
  print ""
  print "### False reds — lower bound"
  print ""
  print "Counts only firings a committed record explicitly contradicts. It is a floor, not an"
  print "estimate: a refusal nothing committed speaks to is absent from this table rather than"
  print "assumed correct."
  print ""
  print "| gate point | firings | first | adjudication row | contradicted by |"
  print "| --- | --- | --- | --- | --- |"
  n = 0
  for (i = 1; i <= ncls; i++) {
    gp = cls_gp[i]
    if (!(gp in fr_when)) continue
    n++
    printf "| `%s` | %d | `%s` | `%s` | %s |\n", gp, false_red[gp] + 0, fr_when[gp], fr_key[gp], adj_cite[fr_key[gp]]
  }
  if (n == 0) print "| — | — | — | — | — |"
  printf "\n**Lower bound: %d %s.**\n", total_fr(), plural(total_fr())
  print ""
  print "### Repeat firings — upper bound"
  print ""
  print "The same point re-firing with no intervening evaluation of another milestone and no session"
  print "change. An over-count by construction: a reaped call that never concluded and an idempotent"
  print "re-invocation both land here, and neither is a second independent refusal."
  print ""
  print "| gate point | repeat firings | of total |"
  print "| --- | --- | --- |"
  n = 0
  for (i = 1; i <= ncls; i++) {
    gp = cls_gp[i]
    if (repeat_n[gp] + 0 == 0) continue
    n++
    printf "| `%s` | %d | %d |\n", gp, repeat_n[gp] + 0, fire[gp] + 0
  }
  if (n == 0) print "| — | — | — |"
  printf "\n**Upper bound: %d %s.**\n", total_repeat(), plural(total_repeat())
  print ""
}

function mechsum(gp,   s) {
  s = ""
  s = s part(gp, "content-moved", "moved");  s = s part(gp, "content-still", "still")
  s = s part(gp, "no-response", "no-response"); s = s part(gp, "unmeasured", "unmeasured")
  return (s == "") ? "—" : substr(s, 3)
}
function part(gp, k, label) { return (mech_n[gp " " k] + 0 == 0) ? "" : ", " (mech_n[gp " " k] + 0) " " label }
function decsum(gp,   s) {
  s = ""
  if (dec_n[gp " changed"] + 0)      s = s ", " (dec_n[gp " changed"] + 0) " changed"
  if (dec_n[gp " unchanged"] + 0)    s = s ", " (dec_n[gp " unchanged"] + 0) " unchanged"
  if (dec_n[gp " undetermined"] + 0) s = s ", " (dec_n[gp " undetermined"] + 0) " undetermined"
  return (s == "") ? "—" : substr(s, 3)
}
function worse(x, y,   ux, uy, cx, cy) {
  ux = dec_n[x " unchanged"] + 0; uy = dec_n[y " unchanged"] + 0
  if (ux != uy) return (ux < uy)
  # eval_s, not rework_s: the rework span is wall-clock between two gate calls and swallows every
  # interval where the operator was simply away, so it ranks nothing honestly. eval_s is the time
  # the gate itself spent evaluating, which is the cost removing the gate would actually return.
  cx = eval_s[x] + 0; cy = eval_s[y] + 0
  if (cx != cy) return (cx < cy)
  return (x > y)
}
function advisory_by_ms(   m, s, ks, i, n) {
  n = 0; s = ""
  for (m = 1; m <= 5; m++) if (n_advisory[m "" ] + 0 > 0) { s = s (s == "" ? "" : ", ") "milestone-" m ": " (n_advisory[m ""] + 0); n++ }
  return (n == 0) ? "" : " (" s ")"
}
function plural(n) { return (n + 0 == 1) ? "firing" : "firings" }
function total_fr(   gp, t) { t = 0; for (gp in false_red) t += false_red[gp]; return t }
function total_repeat(   gp, t) { t = 0; for (gp in repeat_n) t += repeat_n[gp]; return t }
