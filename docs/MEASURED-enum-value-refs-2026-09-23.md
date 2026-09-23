# MEASURED -- enum-value-ref binding (2026-09-23)

Record of before/after measurements for the enum-value binding change
(`docs\superpowers\plans\2026-09-23-enum-value-ref-binding.md`). This file is
appended to by Tasks 1, 4, 5, 7 and 9. Every number below names the exact
command and database that produced it -- none are estimated or carried over
from the plan's stated expectations.

## Task 1 -- setup + baselines (engine 4ccd1779, no code change)

### Worktree

- `git -C C:\Projects\Delphi-RAG-lint-wt\enum-refs rev-parse --short HEAD` -> `4ccd1779`
- `git -C C:\Projects\Delphi-RAG-lint-wt\enum-refs status --short` -> empty (clean)
- Branch: `feat/enum-value-refs`

### Engine copy + version banner

Copied from `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\` into the
worktree's own `third_party\dll-win64\`: `drag-lint.exe`, `tree-sitter.dll`,
`tree-sitter-delphi13.dll`, `tree-sitter-dfm.dll`, `rules\` (recursive).

`drag-lint info --json` (worktree copy):

```
version=1.16.0-alpha  extractor_version=1.17.0-alpha  resolver_version=1.5.1-alpha
build_date=2026-09-22 19:05:55
```

Matches the expected banner exactly (1.16.0-alpha / 1.17.0-alpha / 1.5.1-alpha).

NOTE: the destination `third_party\dll-win64\` folder already contained
`dclDragLintWizard.bpl`, `dclDragLintWizard.dcp` and `drag-lint.json`
(timestamps 2026-09-23 01:21, i.e. before this task ran). These were not
copied by this task and were not touched -- flagged in the hand-back
"Incidental findings", not acted on here (out of this task's scope; the
brief names exactly 5 items to copy and says nothing about pre-existing
extras).

### Self-index (first parse)

Command:
```powershell
Start-Process -FilePath third_party\dll-win64\drag-lint.exe -ArgumentList index,--project,src\cli\drag-lint.dproj,--db,src\cli\_D-RAG\drag-lint.sqlite -WorkingDirectory <worktree root> -Wait -PassThru -NoNewWindow -RedirectStandardOutput <scratch>\selfindex-task1.log -RedirectStandardError <scratch>\selfindex-task1.err
```

- Exit code: **0**
- Compile closure: 131 file(s) (130 indexed + drag-lint.dpr itself with 0 symbols)
- `stage: calls -- done in 116.5s` (WHOLE-DB pass, 22603 edge(s) from 72345 call-site ref(s))
- `resolve: purity -- 2934 routine(s), 194 effect-free (7%), ... 0 gated, 2 pass(es)`
- Final line: `Done. Files: 130, Symbols: 23216, Refs: 185348, 219.36s`
- `0 errors` on every one of the 130 file lines in the log.

## Baseline, engine 4ccd1779

All commands run via `C:\Projects\Delphi-RAG-lint-wt\enum-refs\third_party\dll-win64\drag-lint.exe`.

### 1. `lint-all` baseline (worktree self-DB)

```
drag-lint lint-all --db src\cli\_D-RAG\drag-lint.sqlite --enable multiple-statements-per-line,magic-literal,commented-out-code --json
```

- Exit code 1 (normal: lint-all exits non-zero when findings > 0).
- STDOUT is a bare JSON array; parsed with `ConvertFrom-Json`, **`.Count` = 1246**.
- No staleness-note pollution observed in this run's STDOUT/JSON (the known
  engine defect noted in the brief did not manifest here; JSON parsed clean
  on the first attempt, `--format text` fallback was not needed).
- **Matches the plan's stated `main` baseline of 1246 exactly.**

### 2. M1 -- `cmdDelta` / `cmdTableLoad` (CLIENT, SERVER)

Query:
```sql
SELECT name_text, kind, (symbol_id IS NOT NULL) AS bound, COUNT(*) FROM refs
WHERE name_text IN ('cmdDelta','cmdTableLoad') GROUP BY name_text, kind, bound
```

CLIENT (`C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite`):

| name_text | kind | bound | count |
|---|---|---|---|
| cmdDelta | read | 0 | 38 |
| cmdTableLoad | read | 0 | 42 |

SERVER (`C:\Projects\DB\ORM3\SERVER\_D-RAG\MicroniteMW1Service.sqlite`):

| name_text | kind | bound | count |
|---|---|---|---|
| cmdDelta | read | 0 | 2 |
| cmdTableLoad | read | 0 | 2 |

**Matches the plan's expectation exactly** (CLIENT 42/38, SERVER 2/2, all bound=0).

### 3. Candidate universe -- self-index and CLIENT

Query:
```sql
SELECT r.kind, (r.symbol_id IS NOT NULL) AS bound, COUNT(*) FROM refs r
WHERE r.kind IN ('read','member-access')
  AND r.name_text COLLATE NOCASE IN (SELECT name FROM symbols WHERE kind='enum_value')
GROUP BY r.kind, bound
```

Self-index (`src\cli\_D-RAG\drag-lint.sqlite`):

| kind | bound | count |
|---|---|---|
| member-access | 0 | 17 |
| read | 0 | 1316 |

CLIENT:

| kind | bound | count |
|---|---|---|
| member-access | 0 | 8 |
| read | 0 | 6064 |

**DISAGREES with the plan's stated expectation** (plan says self-index
1,225 read + 17 member-access; CLIENT 6,044 read + 8). member-access counts
match exactly on both DBs; the `read` counts are higher than expected:
self-index measured **1316** (plan said 1,225, +91), CLIENT measured
**6064** (plan said 6,044, +20). Recording both, per instruction, without
adjusting the query or the fixture. Possible explanations not investigated
further here (out of Task 1 scope): the plan's numbers may have been taken
from a slightly different commit/index state, or from a DB re-resolved
since. This is a plain fact record, not a defect filed against drag-lint.

### 4. Rule-0 BEFORE -- duplicate `enum_value` groups

Query:
```sql
SELECT COUNT(*) AS dup_groups, IFNULL(SUM(c),0) AS dup_rows FROM (
  SELECT lower(qualified_name) q, start_line, end_line, COUNT(*) c
  FROM symbols WHERE kind='enum_value' GROUP BY q, start_line, end_line HAVING c > 1
)
```

| DB | dup_groups | dup_rows |
|---|---|---|
| self-index | 0 | 0 |
| CLIENT | 0 | 0 |
| library-Win64 | 6 | 12 |
| library-Win32 | 6 | 12 |

(library-Win32 required `--timeout-ms 120000`; default 10000ms cap was hit
once and the query re-run with the raised cap -- 7474ms actual. library-Win64
ran in 1483ms under the default cap.)

### 5. M4 -- no-collateral counts (self-index, CLIENT)

Query:
```sql
SELECT (SELECT COUNT(*) FROM call_edges) AS edges,
       (SELECT COUNT(*) FROM member_accesses) AS accesses,
       SUM(effect_free=1) AS proven, SUM(effect_free=0) AS not_proven,
       SUM(effect_free IS NULL) AS not_computed
FROM symbol_facts WHERE IFNULL(body_loc,0) > 0
```

| DB | edges | accesses | proven | not_proven | not_computed |
|---|---|---|---|---|---|
| self-index | 11592 | 11021 | 194 | 2740 | 0 |
| CLIENT | 20409 | 9311 | 2896 | 7254 | 0 |

These are the BEFORE values Task 4/5/7/9 must reproduce identically (M4 is
a "no collateral damage" check: the enum-value binding must not move any of
these five numbers).

Additional invariant check (not in the brief's Step-4 list, run because it
is a one-line sanity check for the same claim; enum values must never own a
call edge or a member-access row):

```sql
SELECT (SELECT COUNT(*) FROM call_edges ce JOIN symbols s ON s.id=ce.target_symbol_id WHERE s.kind='enum_value') AS bad_edges,
       (SELECT COUNT(*) FROM member_accesses ma JOIN symbols s ON s.id=ma.member_symbol_id WHERE s.kind='enum_value') AS bad_accesses
```

| DB | bad_edges | bad_accesses |
|---|---|---|
| self-index | 0 | 0 |
| CLIENT | 0 | 0 |

### 6. `write` negative control (CLIENT)

Query:
```sql
SELECT COUNT(*) AS total, SUM(symbol_id IS NOT NULL) AS bound FROM refs
WHERE kind='write' AND name_text COLLATE NOCASE IN (SELECT name FROM symbols WHERE kind='enum_value')
```

CLIENT: `total = 12, bound = 0`. **Matches the expected `bound = 0`** (the
plan did not state an expected `total`; recorded as measured).

### 7. `LotStatus_*` accounting (CLIENT)

Re-run 2026-09-23 (fix round 1) directly against CLIENT for this rewrite --
narrative below is generated from these two result sets, not from memory.

**Query A -- verbatim from the plan** (bare `_`, a SQLite single-character
wildcard, so it is NOT a literal underscore):
```sql
SELECT r.name_text, f.path, (r.symbol_id IS NOT NULL) AS bound, COUNT(*)
FROM refs r JOIN files f ON f.id=r.file_id
WHERE r.kind='read' AND r.name_text LIKE 'LotStatus_%'
GROUP BY r.name_text, f.path, bound ORDER BY 1,2
```
Result: 29 rows, all `bound = 0`, over **three files**:
`C:\Projects\DB\ORM3\CLIENT\uJobList.ViewModel.pas`,
`C:\Projects\DB\ORM3\COMMON\OBJECTS\iFOLDERS.PAS`, and
`C:\Projects\DB\ORM3\CLIENT\uJobList.pas` (a THIRD, distinct file from
`uJobList.ViewModel.pas` -- do not conflate the two). Per-name breakdown of
the wildcard-incidental (non-`LotStatus_<Suffix>`) matches, all `bound = 0`:

| name_text | file | count |
|---|---|---|
| LOTSTATUSCODE | uFOLDERS.PAS | 1 |
| LotStatusCodeDescription | iFOLDERS.PAS | 1 |
| LotStatusCodes | uJobList.pas | 3 |
| LotStatusCodes | iFOLDERS.PAS | 2 |
| LotStatusColors | uJobList.pas | 1 |
| LotStatusColors | iFOLDERS.PAS | 1 |

4 extra names, 6 rows, 9 occurrences total (3+2+1+1+1+1), spread across
`uFOLDERS.PAS`, `iFOLDERS.PAS` and `uJobList.pas` -- not "one hit each in
uFOLDERS.PAS and iFOLDERS.PAS" as the previous revision of this section
said; that sentence undercounted both the file set and the per-name totals
and is replaced by this table.

**Query B -- escaped underscore (Ruling R4)**, the form Task 7 compares
against, restricted to the real `LotStatus_<Suffix>` enum-value names:
```sql
SELECT r.name_text, f.path, (r.symbol_id IS NOT NULL) AS bound, COUNT(*)
FROM refs r JOIN files f ON f.id=r.file_id
WHERE r.kind='read' AND r.name_text LIKE 'LotStatus\_%' ESCAPE '\'
GROUP BY r.name_text, f.path, bound ORDER BY 1,2
```
Result: 23 rows, all `bound = 0`, **12 distinct names** (not the plan's
stated 11), over exactly two files
(`uJobList.ViewModel.pas`, `iFOLDERS.PAS`):

| name_text | uJobList.ViewModel.pas | iFOLDERS.PAS | total |
|---|---|---|---|
| LotStatus_CustAcWithCond | 2 | 3 | 5 |
| LotStatus_CustAccept | 2 | 3 | 5 |
| LotStatus_CustReject | 2 | 3 | 5 |
| LotStatus_InspAccept | 1 | 3 | 4 |
| LotStatus_InspDone | 1 | 3 | 4 |
| LotStatus_InspInProgress | 1 | 3 | 4 |
| LotStatus_InspNotStarted | 1 | 6 | 7 |
| LotStatus_InspReject | 1 | 3 | 4 |
| LotStatus_MRBAcNotify | 2 | 3 | 5 |
| LotStatus_MRBAcSortRework | 2 | 3 | 5 |
| LotStatus_MRBReject | 2 | 3 | 5 |
| LotStatus_Other | 0 | 2 | 2 |

12 names, 23 rows, 55 occurrences total, all `bound = 0` at 4ccd1779 --
this is the exact set and count Task 7 must reproduce (or explain the
delta from) after the binding lands, and it corrects the plan's "11 names"
statement to 12, confirmed by direct count rather than by re-asserting the
plan's number.

Both queries were run against CLIENT only (read-only `sql --query`); no
other DB was touched for this section.

### 8. `SELECT DISTINCT kind FROM symbols` (self-index) -- load-bearing for Task 3

```
class, const, constructor, destructor, enum, enum_value, field, finalization,
function, initialization, interface, local_var, method, param, procedure,
property, record, type, unit, var
```

20 distinct kinds. The three kinds the plan's SQL assumes are present
**verbatim**: `enum_value`, `const`, `var`. Task 3's readers should use
these exact literal strings.

## Corpus DB paths used (resolved via `drag-lint resolve-dbs`, not guessed)

| Name | Path |
|---|---|
| worktree self-index | `C:\Projects\Delphi-RAG-lint-wt\enum-refs\src\cli\_D-RAG\drag-lint.sqlite` |
| ORM3 CLIENT | `C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite` |
| ORM3 SERVER | `C:\Projects\DB\ORM3\SERVER\_D-RAG\MicroniteMW1Service.sqlite` |
| library-Win64 | `C:\Projects\.drag-lint\library-Win64.sqlite` |
| library-Win32 | `C:\Projects\.drag-lint\library-Win32.sqlite` |

## Summary table (headline numbers)

| Measurement | Value | Matches plan? |
|---|---|---|
| `lint-all` total (self-DB) | 1246 | YES (exact) |
| M1 CLIENT `cmdTableLoad`/`cmdDelta` bound | 0 / 0 (42, 38) | YES (exact) |
| M1 SERVER `cmdTableLoad`/`cmdDelta` bound | 0 / 0 (2, 2) | YES (exact) |
| Candidate universe self-index (read/member-access) | 1316 / 17 | member-access exact; read +91 vs plan's 1,225 |
| Candidate universe CLIENT (read/member-access) | 6064 / 8 | member-access exact; read +20 vs plan's 6,044 |
| Duplicate `enum_value` groups (self/CLIENT/lib64/lib32) | 0 / 0 / 6 / 6 | not stated by plan as an expected number; recorded |
| `write` negative control (CLIENT) | bound 0 of 12 | YES (bound=0 as required) |
| `LotStatus_*` accounting (CLIENT), verbatim query | 29 rows, all bound=0, 3 files (incl. 4 wildcard-incidental names) | plan's "11 names" not applicable to this query's raw output |
| `LotStatus_*` accounting (CLIENT), escaped query (Ruling R4) | 23 rows, 12 names, 55 occurrences, all bound=0, 2 files | disagrees on name count (12 not 11); bound=0 confirmed; this is Task 7's comparison set |

All commands, DBs and raw outputs are reproducible from this file alone.

## Fix round 1 (review finding on Section 7)

Reviewer finding: the Section 7 intro sentence contradicted its own
itemised list (named 2 files, list showed 3; said "one hit each", list
showed up to 5 occurrences per extra name). Fix: re-ran both the plan's
verbatim query and, per Ruling R4, the escaped-underscore query directly
against CLIENT and rewrote Section 7 from those two result sets (not from
memory or from the review text). The itemised list from the prior revision
was in fact correct on a per-row basis; only the summarizing prose was
wrong, and it has been replaced with per-name tables generated from the
re-run bytes. Section 7 now carries both the verbatim-plan query/result and
the escaped query/result (12 names, 23 rows, 55 occurrences, all bound=0),
labelled as such, per Ruling R4. No other section was touched.
