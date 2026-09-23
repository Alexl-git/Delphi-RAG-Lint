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
Result: 29 rows, all `bound = 0`. File union taken from the two tables
below (Query B's file columns plus the incidental-match table's file
column), de-duplicated: `uJobList.ViewModel.pas` + `iFOLDERS.PAS` (Query B
table) union `uFOLDERS.PAS` + `iFOLDERS.PAS` + `uJobList.pas` (incidental
table below) = **4 distinct files** (`iFOLDERS.PAS` appears in both tables
and is counted once): `uJobList.ViewModel.pas`, `iFOLDERS.PAS`,
`uJobList.pas`, `uFOLDERS.PAS`. Note `uJobList.pas` and
`uJobList.ViewModel.pas` are two DIFFERENT files -- do not conflate them.
Per-name breakdown of the wildcard-incidental (non-`LotStatus_<Suffix>`)
matches, all `bound = 0`:

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
| `LotStatus_*` accounting (CLIENT), verbatim query | 29 rows, all bound=0, 4 files (incl. 4 wildcard-incidental names) | plan's "11 names" not applicable to this query's raw output |
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

## Fix round 2 (Query A file count undercounted)

Reviewer finding: the round-1 fix said Query A's result spans "three
files" but omitted `uFOLDERS.PAS`, which the document's own incidental-match
table and a later sentence both already named. Fix: no new SQL was run (no
DB access needed or made this round). The file-count sentence was rewritten
to derive its answer from the two tables already in the document -- Query
B's table (files `uJobList.ViewModel.pas`, `iFOLDERS.PAS`) unioned with the
incidental-match table (files `uFOLDERS.PAS`, `iFOLDERS.PAS`,
`uJobList.pas`), de-duplicating the shared `iFOLDERS.PAS` -- giving **4**
distinct files, not 3. Corrected at two sites: the Query A headline
sentence (Section 7) and the Summary table's verbatim-query row (now
"4 files"). Query B's "two files" statement was left untouched per the
reviewer's independent verification.

Sweep of the whole of Section 7 and the Summary table for any other
prose count/file-list not matching the table it summarises:
- Incidental-match sentence ("4 extra names, 6 rows, 9 occurrences ...
  spread across uFOLDERS.PAS, iFOLDERS.PAS and uJobList.pas") -- checked
  against the 6-row incidental table: 4 distinct names, 6 rows, occurrences
  1+1+3+2+1+1=9, 3 distinct files. Matches. No change.
- Query B headline ("23 rows, ... 12 distinct names ... two files") --
  checked against the 12-row Query B table: 12 names, 2 file columns, 23
  rows (12 names x up to 2 files each, one name -- LotStatus_Other -- has
  only 1 nonzero file). Matches. No change (also the one Ruling-R4 item the
  reviewer said was already independently verified correct).
- "12 names, 23 rows, 55 occurrences total" closing sentence -- checked by
  summing the Query B table's `total` column: 5+5+5+4+4+4+7+4+5+5+5+2 = 55.
  Matches. No change.
- Summary table's other rows (lint-all, M1 CLIENT/SERVER, candidate
  universe, duplicate groups, write negative control) -- each checked
  against its own detailed table/result earlier in the document. All
  match. No change.

Result of the sweep: **nothing else found.** The only wrong prose in
Section 7 / the Summary table was the Query A file-count sentence and its
mirror in the Summary table row, both already fixed above; every other
prose count checked against its table matched exactly.

## Task 4 -- the store stream, the NULL-own-universe, the write branch

Engine built from this worktree at Task 4 (`drag-lint info`: version
1.16.0-alpha, extractor 1.17.0-alpha, resolver 1.5.1-alpha -- the resolver
number moves in Task 5, not here). All commands via
`C:\Projects\Delphi-RAG-lint-wt\enum-refs\third_party\dll-win64\drag-lint.exe`.

### A note on the Task 1 baseline, which this task could NOT reuse verbatim

M4 is a "no collateral" check, and it is only valid when the two sides differ
by ONE thing. Task 1's self-index numbers (edges 11592, accesses 11021,
proven 194 / not_proven 2740 / not_computed 0) were taken from a full index of
the tree as it stood at `4ccd1779`. Tasks 2 and 3 then ADDED source to that
same tree, and the self-index indexes this repository's own code -- so those
five numbers had already moved before Task 4 changed anything (measured
immediately before this task's first edit: 11620 / 11095 / 194 / 2750 / 0).
Comparing Task 4's result against Task 1's would therefore have measured
"Tasks 2+3 wrote code", not "the enum stream had no collateral".

The A/B actually run is the one that isolates the engine:

| step | engine | command | stored parses |
|---|---|---|---|
| M4_A | pre-change copy kept in the scratchpad (resolver 1.5.1-alpha, no enum stream) | `index --project src\cli\drag-lint.dproj --db src\cli\_D-RAG\drag-lint.sqlite --resolve-only` | unchanged |
| M4_B | this task's build | the SAME command | the SAME parses (`--resolve-only` skips the walk) |

Both runs exited 0 and both reported `2 file(s) WITHHELD` (the two units this
task edits, whose source no longer matched the index at that moment).

### M4 -- no collateral (self-index)

| run | edges | accesses | proven | not_proven | not_computed |
|---|---|---|---|---|---|
| M4_A (old engine) | 11137 | 10366 | 187 | 2757 | 0 |
| M4_B (new engine) | 11137 | 10366 | 187 | 2757 | 0 |

Every column is equal across the two rows, and both runs reported the same
`21493 edge(s) from 65719 call-site ref(s)` on the calls line. M4 is
IDENTICAL under the comparison that isolates this change.

### Invariants and the negative control (self-index, after M4_B)

```sql
SELECT (SELECT COUNT(*) FROM call_edges ce JOIN symbols s ON s.id=ce.target_symbol_id WHERE s.kind='enum_value') AS bad_edges,
       (SELECT COUNT(*) FROM member_accesses ma JOIN symbols s ON s.id=ma.member_symbol_id WHERE s.kind='enum_value') AS bad_accesses
```

| bad_edges | bad_accesses |
|---|---|
| 0 | 0 |

`write` negative control on the self-index: `total = 0, bound = 0` (the
self-index has no `write` ref whose name is an enum-value name at all, so the
control is vacuous here and CLIENT's `total = 12, bound = 0` from Task 1
remains the load-bearing instance; Task 7 re-measures it).

### M3 preliminary -- the `enum-values:` line (self-index)

Whole-database run (M4_B), verbatim:

```
resolve: calls      enum-values: 1232 bound of 1232 bare read(s) + 9 qualified; declined not-visible 0, ambiguous 0, shadowed 0; duplicate groups collapsed 0 (decisive 0); unit-level shadow decls 450
```

Bound state of the candidate universe immediately after that run:

| kind | bound | count |
|---|---|---|
| read | 1 | 1232 |
| read | 0 | 93 |
| member-access | 1 | 9 |
| member-access | 0 | 8 |

The 93 unbound `read` rows are the ones inside the two WITHHELD files, which
the stream is excluded from by `AStaleWhere`; the subsequent incremental
reindex (which reparsed exactly those two files) bound them, reporting
`enum-values: 93 bound of 93 bare read(s) + 0 qualified; declined not-visible
0, ambiguous 0, shadowed 0; duplicate groups collapsed 0 (decisive 0);
unit-level shadow decls 450`. 1232 + 93 = 1325, which is the whole `read`
candidate count on this database.

`unit-level shadow decls 450` is the R3(c) fail-open assertion required by the
task brief, and it agrees with the direct count of the set:

| kind | parent kind | count |
|---|---|---|
| const | unit | 311 |
| var | unit | 139 |
| const | class | 6 (correctly excluded) |
| var | class | 22 (correctly excluded) |

311 + 139 = 450.

### EXPLAIN QUERY PLAN for the enum stream's SELECT (self-index)

```
drag-lint sql --db src\cli\_D-RAG\drag-lint.sqlite --query "EXPLAIN QUERY PLAN SELECT refs.id, refs.file_id, refs.name_text, refs.enclosing_symbol_id, refs.start_line, refs.start_col FROM refs WHERE refs.kind = 'read' AND refs.name_text COLLATE NOCASE IN (SELECT name FROM symbols WHERE kind = 'enum_value')"
```

| id | parent | detail |
|---|---|---|
| 3 | 0 | `SEARCH refs USING INDEX idx_refs_name_nocase (name_text=?)` |
| 7 | 0 | `LIST SUBQUERY 1` |
| 9 | 7 | `SCAN symbols` |

`idx_refs_name_nocase` carries the name test, as the plan-pin note predicted.

### Guard state after Task 4

```
PASS: 1, 2, 3, 4, 5, 6, 7, 8, 10, 12
FAIL: 9, 11, 13
```

9 and 11 are RED by the plan's own ordering (Tasks 6 and 8). 13 is RED for a
reason this task found and did NOT work around -- see below.

### Check 13's MECHANISM assertion cannot be satisfied by this fixture

Check 13's OUTCOME half is GREEN (A1 in fixture B binds to
`uEnumDecl.TCmd.cmdLoad` despite the duplicate). Its MECHANISM half asserts
that the `enum-values:` line reports `collapsed >= 1`, and it reports 0.

The cause is in the fixture's own data, not in the store stream. Measured
directly against the fixture DB `C:\TEMP\draglint_enum_value_refs_bind\b.sqlite`:

| table | row |
|---|---|
| `files` | 1 = `B\uEnumDecl.pas`, 2 = `B\uEnumUse.pas`, 3 = `B\dup\uEnumDecl.pas` |
| `unit_uses` | one row: file_id 2, unit_name `uEnumDecl`, **target_file_id 1** |
| `symbols` (enum_value `cmdLoad`) | id 3 in file 1; id 21 in file 3 |

`TCallResolver.CandInScope` is built from `GetUnitScopeEdges`, which reads
`unit_uses` by RESOLVED `target_file_id`. The single uses row binds to file 1
only, so R1 makes exactly ONE of the two twins visible from file 2,
`Visible` has length 1, and `CollapseIdenticalEnumCopies` returns at its
`if Length(AVisible) < 2 then Exit` guard without ever forming a group.

Rule 0 is therefore unreachable on this fixture through the bare-read path,
and no change confined to the store could make it reachable. The guard's own
header anticipated the converse risk ("the OUTCOME assertion would be green
even with rule 0 absent, if `unit_uses` happened to resolve to exactly one
copy") -- that is precisely what the fixture does. The guard was NOT weakened
and the resolver's R1 was NOT widened to force it green; it is handed on as a
finding.

### CollapseDecisive -- carried finding from Task 3's review, resolved

The fix chosen is the FIRST of the two offered: `CollapseDecisive` is now
counted on EVERY path, so `TEnumResolveStats`' documented meaning stays true;
the alternative (narrowing the documented meaning to "Shape A only") was not
taken. It is incremented inside `CollapseIdenticalEnumCopies` itself --
`if (Length(AVisible) > 1) and (Keep.Count = 1)` -- rather than at a call
site, so the bare-read path and rung 3c's `Unit.value` path both contribute
and the two counters cannot drift apart again. The call-site increment in
`ResolveEnumValueRead` and its now-unused `Before` local were removed.

### Lint (self-index reindexed incrementally first)

```
drag-lint lint --file <abs path> --db src\cli\_D-RAG\drag-lint.sqlite --enable multiple-statements-per-line,magic-literal,commented-out-code --json
```

| file | findings on lines this task added |
|---|---|
| `src\storage\DRagLint.Storage.SQLite.pas` | 0 |
| `src\index\DRagLint.Index.CallResolver.pas` | 0 |

Two were found and resolved before that state was reached:

1. `field-by-name-in-loop` on the new stream -- FIXED by binding the six
   `TField` references once outside the loop.
2. `local-field-prefix` x6 on those cached locals (`FId`...) -- FIXED by
   renaming them `FldId`...`FldCol`.
3. `sql-injection-concat` on the NULL-own-universe `ExecSQL` -- ANNOTATED
   `// dl:ok sql-injection-concat@dd1f` (hash produced by `drag-lint allow
   --fix-line --fix-rule`, not hand-written), with the reason that `Where` is
   SQL this pass built and cannot be parameterised: the scope predicate names
   a temp table and the stale predicate an IN-list of file ids.

CAUTION for later tasks, recorded because it cost a measurement here: a
RELATIVE `--file` path is resolved against the process's working directory,
and this session's default working directory is a DIFFERENT worktree. A first
before/after comparison run that way silently linted `purity-v2`'s copy of the
same unit and reported "identical counts, zero new findings" -- which was true
of a file this task never touched. Every lint figure above was taken with an
ABSOLUTE path.

## Task 5 -- resolver 1.6.0-alpha: surface, baseline, forward references

Engine rebuilt from this worktree at Task 5 (`build\build_draglint_win64.bat`,
Win64 Debug, staged to `third_party\dll-win64\`). `drag-lint info --json` after
the build:

```
version=1.16.0-alpha  extractor_version=1.17.0-alpha  resolver_version=1.6.0-alpha
build_date=2026-09-23 04:10:11
```

`DRAGLINT_EXTRACTOR_VERSION` and `SCHEMA_VERSION` are unchanged (1.17.0-alpha,
23), as U4 requires.

### Resolver-version guard: the hash was RECOMPUTED, not carried

The guard was run three times, from a neutral cwd (`C:\TEMP`) against
`-Repo C:\Projects\Delphi-RAG-lint-wt\enum-refs`:

| run | state of the tree | exit | what it said |
|---|---|---|---|
| before any Task 5 edit | Task 4's tree | 1 | `ResolveEnumValueRefs` UNCLASSIFIED, and `resolve changed but DRAGLINT_RESOLVER_VERSION did NOT` |
| after the manifest + constant edits, baseline not yet touched | -- | 0 | `resolve changed AND the version was bumped -- 1.5.1-alpha -> 1.6.0-alpha`, printing the line to store |
| after the baseline was written | final | 0 | `resolve surface unchanged -- version=1.6.0-alpha` |

The pinned line is the one the SECOND run printed:

```
1.6.0-alpha|95080b86976b780299f60f1f3e4c5fec372170db4b3fb980b23feca790aadec6
```

It is not any of the three hashes recorded earlier on this branch
(`6d13893c...`, `f3ffa3a3...`, `2674da43...`), all of which are superseded, nor
the 1.5.1-alpha line it replaces (`8d1034e8...`). The baseline carries exactly
one active line; the guard asserts that shape and passed.

### Self-index reindex (incremental, worktree root as cwd)

```
drag-lint index --project <wt>\src\cli\drag-lint.dproj --db <wt>\src\cli\_D-RAG\drag-lint.sqlite
```

Exit code 0. `Done. Files: 130, Symbols: 23351, Refs: 186472, skipped 128
up-to-date, 118.13s`; `0 errors` on every reparsed file line. The calls stage
ran WHOLE-DB, as a resolver bump requires:

```
resolve: calls      starting WHOLE-DB pass over all 130 indexed file(s)
resolve: calls      ... whole database because the call-edge set is missing or incomplete, so there is no delta to update
resolve: calls      22731 edge(s) from 72758 call-site ref(s), WHOLE DB  [106.5s, clear 0.0s, maps 0.0s]
```

**Deviation from the task brief, recorded rather than smoothed over.** The brief
expected the line `resolver: edges were derived by 1.5.1-alpha, this build is
1.6.0-alpha`. It was NOT printed, and the whole-DB pass was attributed to a
different (also true) condition. The reason is mechanical, not a defect: that
sentence is emitted by a read-side advisory in `src\cli\DRagLint.CLI.pas:1876-1881`,
which compares `schema_meta.resolver_fingerprint` against the running build when
a store is OPENED -- it is not the calls stage's own decision text. On an
`index` run the stage prints its own reason and then re-stamps. The stamp did
move, which is the fact that matters:

```
schema_meta.resolver_fingerprint = r=1.6.0-alpha;schema=23
```

### M3 (self-index, 1.6.0-alpha) -- the `enum-values:` line, verbatim

```
resolve: calls      enum-values: 1325 of 1325 bare read(s) bound (Shape A); 9 qualified bound (Shape B); declined (both streams) not-visible 0, ambiguous 0, shadowed 0; duplicate groups collapsed 0 (decisive 0); unit-level shadow decls 450
resolve: calls      enum-values: total bound 1334 = 1325 + 9 (resolver and store agree)
```

Candidate universe on the same database immediately after that run:

| kind | bound | rows |
|---|---|---|
| `read` | 1 | 1325 |
| `member-access` | 1 | 9 |
| `member-access` | 0 | 8 |

Reading only that table: every `read` candidate row is bound (there is no
`read` / bound 0 row at all), and of the qualified candidates 9 are bound and 8
are not, i.e. 17 in total. The stage line's `1325` and `9` are the same two
numbers, so the log and the stored rows agree. Task 4 measured the same
database at 1232 + 93 bare reads (the 93 were inside two WITHHELD files) and 9
qualified; 1232 + 93 = 1325, so this run's single whole-DB figure is the same
population, now bound in one pass.

Declines are 0 on all three reasons here, which is a property of THIS corpus
(the self-index has 0 cross-kind collisions), not evidence that the decline
paths are dead -- the guard's fixture exercises them (check 6 and check 12,
which report `shadowed 2` and `ambiguous 1` respectively).

### M4 again (self-index) -- no collateral

Same query as Task 1 and Task 4, run immediately before and immediately after
this task's reindex:

| point | edges | accesses | proven | not_proven | not_computed |
|---|---|---|---|---|---|
| before the 1.6.0-alpha reindex | 11626 | 11115 | 194 | 2751 | 0 |
| after the 1.6.0-alpha reindex | 11626 | 11115 | 194 | 2751 | 0 |

Every column in the second row equals the column above it, so M4 HELD across
the resolver bump and its whole-DB re-resolve. (These five numbers differ from
Task 4's M4_A/M4_B pair -- 11137 / 10366 / 187 / 2757 / 0 -- because Task 4's
A/B was run against a partially withheld index; the comparison that matters is
before-vs-after within one task, and both tasks' comparisons are internally
consistent.)

Enum-value invariant on the same database after the reindex:

| bad_edges | bad_accesses |
|---|---|
| 0 | 0 |

No enum value owns a `call_edges` row or a `member_accesses` row (U3).

### Bound-by-kind across the whole self-index (the numbers INDEX-SCHEMA.md now carries)

```sql
SELECT kind, COUNT(*) AS total, SUM(symbol_id IS NOT NULL) AS bound FROM refs GROUP BY kind
```

| kind | rows | bound |
|---|---|---|
| `call` | 37563 | 8093 |
| `member-access` | 35195 | 14047 |
| `read` | 76954 | 1325 |
| `type_use` | 20078 | 0 |
| `write` | 16682 | 0 |

Five kinds appear; this index has no `event-binding` and no `attribute` rows,
so those two are absent rather than zero-bound. The `read` row's 1325 is the
same number as the M3 table's bound `read` count, which is the check that no
non-enum `read` acquired a binding.

### Guards

| guard | result |
|---|---|
| `run_resolver_version_guard.ps1` | PASS (exit 0) |
| `run_schema.ps1` | PASS (exit 0); `SCHEMA_VERSION = 23` unmoved |
| `run_encoding_guard.ps1` | PASS (exit 0) |
| `run_docs_sync_guard.ps1` | PASS (exit 0) |
| `run_forward_stub_pairing.ps1` | PASS (exit 0) |
| `run_forward_stub_is_not_a_class.ps1` | PASS (exit 0) |
| `run_extractor_version_guard.ps1` | FAIL (exit 1) -- expected, see below |
| `tests\callresolve\run_enum_value_refs_bind.ps1` | `PASS: 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 13` / `FAIL: 9, 11` -- unchanged from Task 4's end state |

`run_extractor_version_guard.ps1` was NOT cleared by this task, and could not
have been: its surface is `$roots = @('src\parser', 'src\preprocess',
'src\index')` (line 61 of the guard), and NONE of this task's six changed files
is under those roots -- `git diff --name-only` lists `CHANGELOG.md`,
`docs/INDEX-SCHEMA.md`, `src/core/DRagLint.Core.ForwardStub.pas`,
`src/core/DRagLint.Core.Model.pas`, `tests/resolver-surface.txt`,
`tests/resolver-version.baseline`. So the red predates Task 5 (Task 3 edited
`src\index\DRagLint.Index.CallResolver.pas`, which IS on that surface), and it
is red for a second, independent reason recorded at the branch point:
`docs\INBOX-symbolfacts-stale-since-e71abafb.md`, owner-pending.
`DRAGLINT_EXTRACTOR_VERSION` was deliberately not bumped -- a bump costs a
~3h17m full re-parse of every database for a change that alters no extraction.

### Lint on the changed units (absolute paths)

```
drag-lint lint --file <abs> --db <abs> --enable multiple-statements-per-line,magic-literal,commented-out-code --json
```

| file | findings total | findings on lines this task changed |
|---|---|---|
| `src\core\DRagLint.Core.ForwardStub.pas` | 0 | 0 |
| `src\core\DRagLint.Core.Model.pas` | 18 | 0 |

The changed lines in `Model.pas` are 130-131 and 134-144 (`git diff -U0`
hunks `@@ -130 +130,2 @@` and `@@ -133 +134,11 @@`). Every one of the 18
findings anchors outside that range: line 1 (`unit-too-large`), line 157
(`review-marker-unused`), 958-961, and 2203-2371. No `dl:ok` marker was added
by this task.

## Task 6 -- R-B churn shape: MEASURED, and the spec's premise is FALSE

The brief asked this section to describe the churn as "each bound site's entry
loses its ` ?` suffix". **That premise does not survive measurement, and neither
does its replacement in ruling R9 ("not observably changed at all").** Both are
recorded here with the evidence, because the owner is sizing a regeneration on
this number.

### Method

A/B on a REAL corpus, not the four-unit fixture: drag-lint's own self-index
(`src\cli\_D-RAG\drag-lint.sqlite`, 130 files, 270 `enum_value` symbols,
re-resolved at resolver 1.6.0-alpha). Same DB, same product version
(1.16.0-alpha), two engines differing ONLY in the `ValueArm`:

* BEFORE -- `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe` (2026-09-22, no value arm)
* AFTER  -- `...\enum-refs\third_party\dll-win64\drag-lint.exe` (this task's build)

`document --qname <value> --db <db>`, **DRY RUN, never `--apply`.**

### What actually changes

| Property | BEFORE | AFTER | Verdict |
|---|---|---|---|
| ` ?` suffixes on the `Used by:` line | 0 | 0 | unchanged **for these four** -- see the CORRECTION below: a PARTIALLY bound value gains them |
| `CalledFromTotal` (the `(+N more)` count) | e.g. 13 / 9 / 62 | 13 / 9 / 62 | **unchanged** |
| the DISTINCT caller SET | -- | -- | **unchanged** (proved below) |
| WHICH 5 entries are rendered | first-5 by name-bucket insertion | first-5 by resolved-bucket insertion | **CHANGES** |

So for these four, the answer is none of the four offered outcomes: entries do not
lose ` ?`, none are removed, and it is not "no change at all". **The churn on a
FULLY BOUND value is a re-WINDOWING: the same N callers, the same total, a
different 5 of them shown.**

**This does not generalise to a partially bound value, and the CORRECTION section
below is the qualification** -- there, ` ?` markers APPEAR (0 -> N). These four
sampled values happen to have no unfoldable unverified reader.

### Why -- the mechanism, read out of the code rather than guessed

Two facts compose:

1. `Doc.Facts.Build`'s `AMaxCallers` contract (`DRagLint.Doc.Facts.pas:709`):
   "at most this many distinct resolved/unverified callers are kept **(same
   first-seen order as the underlying dedupe)**, truncated; `CalledFromTotal`
   always carries the true distinct count". The cap is applied in INSERTION
   order, and `JoinRefs` sorts only the survivors. Default 5.
2. `AddDistinct` is first-seen-wins on `(Display, Location)`, and resolved rows
   are inserted BEFORE the name bucket. Before this task an enum value had an
   EMPTY resolved bucket, so insertion order was the name bucket's
   `ORDER BY f.path, r.start_line`. It is now `FindResolvedCallers`' own
   `ORDER BY <confidence>, encl_qname` for the bound sites, then the rest.

The ` ?` half of the spec's premise fails for a third, independent reason:
`JoinRefs` (`DRagLint.Doc.Regions.pas:2359`) computes
`Mixed := AnyCertain and AnyUncertain` and renders ` ?` ONLY on a mixed list. An
enum value's list was uniformly `unverified` before (so: suppressed, plain) and
is uniformly `certain` after for a fully-bound value (so: still plain). There was
no ` ?` to lose.

### Proof that the caller SET is unchanged (the dedupe held)

The task's named risk was that `ValueArm`'s `Display`/`Location` might diverge
from `FindUnresolvedNameCallers`', breaking the `(Display, Location)` dedupe and
double-listing the caller. Set difference on `TSymbolKind.skClass` (62 distinct
callers, the widest in the index), my arm's rows EXCEPT the name bucket's rows:

```
0 row(s)
```

Zero rows unique to the value arm. The two computations agree, which is also why
guard check 10 ("names `uEnumUse.UseIt` EXACTLY once, never twice") stays green.

### Size of the regeneration -- UPPER BOUND 44 of 270 blocks

A value whose distinct-caller count is <= the cap renders identically whatever the
insertion order, because all entries survive and `JoinRefs` sorts them. So only
values with MORE than 5 distinct callers can re-window:

| self-index | count |
|---|---|
| `enum_value` symbols | 270 |
| ... with at least one bound read | 252 |
| ... with > 5 distinct callers (window CAN change) | **44** |
| ... with <= 5 (render provably identical) | 208 |

**44 is an upper bound, not a count**, and that was checked rather than assumed:
`TSymbolKind.skTypeAlias` has 16 distinct callers (so it is inside the 44) and
still rendered BYTE-IDENTICAL, because its first 5 happened to coincide. Three of
the four values sampled did change: `efUnknown` (13 callers), `tekReplaceInLine`
(9), `skClass` (62).

ORM3 CLIENT/SERVER could NOT be measured: those indexes are read-only to this
task and are still resolved at 1.5.1-alpha, so they have no enum bindings to
render until `index --all --resolve-only` runs.

### CORRECTION (fix round 1): there is a SECOND channel, and 44 does not bound it

The paragraph that stood here said the churn "cannot change a ` ?` marker". **That
was wrong, and it was wrong by over-generalising the four sampled values into a
modal claim.** The sample stands (4 values, 0 -> 0 observed); the generalisation
does not.

`FindUnresolvedNameCallers` (`SQLite.pas:5956-5968`) matches on bare
`r.name_text = :n COLLATE NOCASE` and excludes only refs that own a `call_edges`
row -- **it does not exclude refs this binder just bound** -- then hard-codes
`R.Confidence := 'unverified'` (`:5995`). `AddDistinct` folds only on
`(Display, Location)`. So any name-bucket row whose `(encl_qname, file)` pair the
resolved bucket does NOT also produce SURVIVES as unverified.

One survivor is enough: `AnyCertain` becomes True where the list was uniformly
unverified, `Mixed := AnyCertain and AnyUncertain` flips **False -> True**, and
` ?` is appended to every unverified entry. **The markers do not disappear -- they
APPEAR, 0 -> N.** This is the same `Mixed` argument used above, carried one step
further than the original text carried it.

Two ordinary shapes guarantee survivors:

* a read of a **different same-named enum value** in another enum type -- the
  name bucket matches it, the resolver can never bind it to this symbol;
* a read of THIS value the resolver **declined** (R1 visibility, R2 two
  candidates, R3 shadowing), in a routine with no other bound read of it.

**So the two channels are independent and differently bounded:**

| Channel | What changes | Bound |
|---|---|---|
| 1. re-windowing | which 5 of N render; set, total and markers unchanged | **<= 44 of 270** here |
| 2. marker appearance | ` ?` count 0 -> N on a PARTIALLY bound value | **NOT bounded by 44** |

Channel 2 fires at ANY caller count, including at or below the cap, so an
affected block is outside the 44 AND outside the "208 render provably identical"
set. And a ` ?` IS a re-qualification of a fact, so "no fact added, removed or
re-qualified" is true of channel 1 only.

**Measured for channel 2 on this index: 0 occurrences.** Over-approximating the
name bucket (no reach filter, no self-reference filter, so survivors can only be
over-counted) still yields zero enum values with an unfoldable unverified reader
-- every enum value in drag-lint's own source is fully bound. **That is a property
of this corpus, not a bound on the channel.** A corpus carrying declined reads or
same-named values in sibling enums -- ORM3 is the obvious candidate, and it could
not be measured here -- will show a non-zero count.

### Consequence for the owner

Channel 1 is cosmetic and bounded at 44 for this index. Channel 2 changes what a
block CLAIMS about its own certainty and is unbounded by this measurement, though
it measures 0 here.

Recommended fold, unchanged from the plan: run the one owed `document --apply`
together with the `Pure` -> `Effect-free (proven)` regeneration
(`docs\MEASURED-purity-v2-2026-09-21.md`, Phase 2 runbook), **after** the library
re-resolve, so every corpus is regenerated exactly once.

**Task 9 expectation -- corrected.** Count `doc-drift` findings on enum-value
blocks, but do NOT treat 44 as a ceiling: 44 bounds channel 1 only, and a
channel-2 block can legitimately push the total above it. A count above 44 is
therefore NOT by itself a regression; confirm which channel produced the excess
(a ` ?` count that moved 0 -> N is channel 2) before reading it as one.

**Read this together with Task 7's channel-2 measurement below (section "R-B autodoc churn,
re-measured on CLIENT").** Task 7 measured channel 2 at 3 of 18 on CLIENT and traced ALL
THREE to the single WITHHELD file `uPipeClientConnection.pas`. So this guidance inverts if
that unit is reindexed before Task 9 runs: with the file fresh, CLIENT's channel-2 count
plausibly returns to 0 and a channel-2 excess would no longer be the available explanation
for a total above 44. Task 9 should record whether the reindex happened first.

## Task 7 -- corpus re-resolved under 1.6.0-alpha; projects only (libraries owner-gated)

**Engine:** `C:\Projects\Delphi-RAG-lint-wt\enum-refs\third_party\dll-win64\drag-lint.exe`
(product 1.16.0-alpha, resolver 1.6.0-alpha). All paths absolute; PowerShell only.

**TRAP, stated first.** The 33 project DBs are now resolved at `r=1.6.0-alpha;schema=23`
while the MAIN tree's deployed engine is still 1.5.1-alpha. Any `index` run issued from
the main tree before merge + redeploy sees a resolver-version mismatch, re-derives every
edge with the OLD resolver, and DROPS every enum-value binding recorded below.

### Scope actually run (owner ruling: "projects now, libraries after merge")

The manifest (`third_party\dll-win64\drag-lint.json`) has **34** sections, of which
**33** are non-`Library`. The brief said 35; the section list was read from the manifest,
not copied, and 33 is the number passed to `--only`.

| Run | Sections | Mode | Exit | Elapsed |
|---|---|---|---|---|
| A (all non-Library) | 33 | `index --all --resolve-only --jobs 2` | 0, `parallel build: 33/33 sections OK` | 294 s |
| B (attribution re-run) | ORM3-Micronite2027 | `--jobs 1`, merged stdout+stderr | 0 | 155 s |
| C (attribution re-run) | ORM3-MicroniteMW1Service | `--jobs 1`, merged | 0 | 111 s |
| D (attribution re-run) | the other 31 | `--jobs 1`, merged | 0 | 278 s |

**Where the evidence lives.** Every number in this section is reproducible from the SQL
quoted inline below against the databases named above -- the logs are corroboration, not the
only record. The raw run logs were moved out of the session-scoped scratchpad to
`C:\TEMP\claude\enum-refs-task7\`: `resolve-projects.log` (run A, stdout),
`resolve-combined.log` (run A, stdout+stderr concatenated), `resolve-orm3.log` (run B,
CLIENT, merged), `resolve-server.log` (run C), `resolve-rest.log` (run D, the other 31),
`resolve1.bat` (the wrapper), and the four `doc-before-*` / `doc-after-*` churn captures.

Runs B-D exist because `--jobs 2` writes the stage lines to **stderr** and the section
banners to **stdout**, so with two workers no `enum-values:` line can be attributed to a
section from the logs. Re-resolving is idempotent; B-D reproduced run A's counters exactly.

**No section reported a lock.** Four main-tree `serve` daemons were live throughout
(PIDs 13712 CLIENT, 22224 SERVER, 18400 library-Win64, 20032 SQL, all
`C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe`, started 2026-09-22
20:59). **Nothing was killed.** They did not block the writes.

**Library sections: NOT RUN -- pending owner-gated pass, sequenced after merge + redeploy.**
`library-Win64.sqlite` and `library-Win32.sqlite` both still read
`resolver_fingerprint = r=1.5.1-alpha;schema=23`. The commands a later operator runs, from
the MAIN tree after the redeploy, one platform per run, blocking and logged:

```
<main>\third_party\dll-win64\drag-lint.exe index --all --resolve-only --jobs 2 --only Library --platform win64
<main>\third_party\dll-win64\drag-lint.exe index --all --resolve-only --jobs 2 --only Library --platform win32
```

### Evidence that each section re-resolved

The brief's expected line `resolver: edges were derived by 1.5.1-alpha, this build is
1.6.0-alpha` is **not** printed by the calls stage (Task 5 established it as a read-side
advisory on store OPEN). The three facts that were checked instead, on every section:

1. `Resolver changed since this DB was resolved (r=1.5.1-alpha;schema=23 ->
   r=1.6.0-alpha;schema=23): re-deriving every edge.`
2. a WHOLE-DB calls pass (`resolve: calls starting WHOLE-DB pass over all N indexed file(s)`);
3. an `enum-values:` line, and afterwards
   `schema_meta.resolver_fingerprint = r=1.6.0-alpha;schema=23`.

Fingerprint sweep over the 33 project DBs: **33 of 33** read `r=1.6.0-alpha;schema=23`,
0 read anything else.

### Per-section counters (from the serial merged logs)

`A` = bare reads bound / bare-read candidates (Shape A). `B` = qualified bound (Shape B).
`NV/AM/SH` = declined not-visible / ambiguous / shadowed. `C(D)` = duplicate groups
collapsed (decisive). `SD` = unit-level shadow decls. `W` = files WITHHELD.

| Section | A bound | A cand | B | NV | AM | SH | C(D) | SD | W |
|---|---|---|---|---|---|---|---|---|---|
| ORM3-Micronite2027 (CLIENT) | 5983 | 6036 | 0 | 53 | 0 | 0 | 0 (0) | 1141 | 1 |
| ORM3-MicroniteMW1Service (SERVER) | 1970 | 3454 | 0 | 1484 | 0 | 0 | 0 (0) | 814 | 0 |
| ORM3-Interfaces | 84 | 84 | 0 | 0 | 0 | 0 | 0 (0) | 3 | 0 |
| ORM3-TestMicroniteObjects | 902 | 902 | 0 | 0 | 0 | 0 | 0 (0) | 213 | 0 |
| ORM3-MicroniteTests | 584 | 590 | 67 | 0 | 3 | 3 | 0 (0) | 331 | 0 |
| ORM3-TestCachedUpdates | 0 | 0 | 0 | 0 | 0 | 0 | 0 (0) | 0 | 0 |
| ORM3-PdfOcrImportTests | 64 | 70 | 67 | 0 | 3 | 3 | 0 (0) | 189 | 0 |
| ORM3-TEST_uSetupDefaultsFrm | 608 | 608 | 0 | 0 | 0 | 0 | 0 (0) | 713 | 1 |
| SQL | 0 | 0 | 0 | 0 | 0 | 0 | 0 (0) | 0 | 0 |
| Loader | 9 | 9 | 0 | 0 | 0 | 0 | 0 (0) | 1566 | 0 |
| TableTools-TableTools370P | 48 | 48 | 0 | 0 | 0 | 0 | 0 (0) | 661 | 0 |
| TableTools-MemTableFieldWizard | 0 | 0 | 0 | 0 | 0 | 0 | 0 (0) | 3 | 0 |
| DragLint-Cli (MAIN tree self-index) | 835 | 835 | 0 | 0 | 0 | 0 | 0 (0) | 403 | 14 |
| DragLint-Wizard | 333 | 333 | 0 | 0 | 0 | 0 | 0 (0) | 254 | 5 |
| DragLint-Tests | 3 | 3 | 0 | 0 | 0 | 0 | 0 (0) | 17 | 3 |
| DragLint-CorpusScan | 5 | 5 | 0 | 0 | 0 | 0 | 0 (0) | 18 | 0 |
| DragLintGraph-Viewer | 227 | 227 | 0 | 0 | 0 | 0 | 0 (0) | 38 | 0 |
| DragLintGraph-Pkg | 121 | 121 | 0 | 0 | 0 | 0 | 0 (0) | 22 | 0 |
| DragLintGraph-DbPkg | 54 | 54 | 0 | 0 | 0 | 0 | 0 (0) | 1 | 0 |
| DragLintGraph-Dcl | 121 | 121 | 0 | 0 | 0 | 0 | 0 (0) | 19 | 0 |
| DragLintGraph-Tests | 182 | 182 | 0 | 0 | 0 | 0 | 0 (0) | 24 | 0 |
| OCRPDF-App | 0 | 0 | 0 | 0 | 0 | 0 | 0 (0) | 0 | 0 |
| OCRPDF-TestPDFFragments | 0 | 0 | 0 | 0 | 0 | 0 | 0 (0) | 6 | 0 |
| DataCopy-App | 169 | 169 | 0 | 0 | 0 | 0 | 0 (0) | 186 | 0 |
| DataCopy-SortTest | 0 | 0 | 0 | 0 | 0 | 0 | 0 (0) | 1 | 0 |
| YADF | 128 | 128 | 0 | 0 | 0 | 0 | 0 (0) | 11 | 0 |
| YADFOT | 132 | 132 | 0 | 0 | 0 | 0 | 0 (0) | 22 | 1 |
| YADFSetup | 137 | 137 | 0 | 0 | 0 | 0 | 0 (0) | 12 | 1 |
| YADF-GuardTest | 128 | 128 | 0 | 0 | 0 | 0 | 0 (0) | 9 | 1 |
| YADF-OptionsTest | 65 | 65 | 0 | 0 | 0 | 0 | 0 (0) | 1 | 0 |
| DataCopy-Tests | 168 | 168 | 0 | 0 | 0 | 0 | 0 (0) | 231 | 8 |
| DragLint-ConvRulesEditor | 196 | 196 | 0 | 0 | 0 | 0 | 0 (0) | 61 | 3 |
| DragLint-ConvRulesTests | 187 | 187 | 0 | 0 | 0 | 0 | 0 (0) | 27 | 3 |

Counts derived from that table only, by parsing the table's own pipe-delimited cells rather
than by eye (this sentence is the one place on the branch where a prose count beside a table
has been wrong twice, and the first revision of it got the row count wrong a third time):
33 rows; the `W` column is non-zero on **11** rows -- ORM3-Micronite2027 (1),
ORM3-TEST_uSetupDefaultsFrm (1), DragLint-Cli (14), DragLint-Wizard (5), DragLint-Tests (3),
YADFOT (1), YADFSetup (1), YADF-GuardTest (1), DataCopy-Tests (8), DragLint-ConvRulesEditor (3),
DragLint-ConvRulesTests (3) -- and sums to **41** withheld files; the `C(D)` column is `0 (0)` on all 33 rows; `AM` and
`SH` are non-zero on exactly **2** rows (ORM3-MicroniteTests and ORM3-PdfOcrImportTests,
3 and 3 each); `B` is non-zero on the same 2 rows (67 each); `NV` is non-zero on exactly
**2** rows (CLIENT 53, SERVER 1484).

Two further sums taken from the same parse, offered as internal cross-checks rather than as
new facts: `A cand` totals **14992** and `A bound` totals **13443**, and
14992 - 13443 = 1549 = 1537 (`NV`) + 6 (`AM`) + 6 (`SH`), so every bare-read candidate the
stage saw is either bound or carried by one of the three decline counters. `A bound`'s 13443
is also, independently, the "bare reads bound to an unscoped value" figure in the R5 table
below -- the same population counted by a different query.

**`DragLint-Cli` is the MAIN tree's self-index** (`C:\Projects\Delphi-RAG-lint\src\cli\
_D-RAG\drag-lint.sqlite`), not the worktree self-index Tasks 1/4/5 measured
(`...\enum-refs\src\cli\_D-RAG\drag-lint.sqlite`). The worktree self-index is not a
manifest section and was NOT touched by this run; its Task 5 numbers stand unchanged
(M3 1325 + 9; M4 11626 / 11115 / 194 / 2751 / 0, re-read after this run and identical).
The two must not be conflated: 835 of 835 with 14 withheld is a different database.

**`enum-shadow-set: WARNING -- the unit-level const/var shadow set is EMPTY` fired on 3
sections** -- ORM3-TestCachedUpdates, SQL, OCRPDF-App. Each of those three has `A cand = 0`
in the table above, so no binding was made under the fail-open and the warning is inert
on this run. It is still a warning worth watching on a section that does bind.

### WITHHELD files -- read this BEFORE any bind count

`ClearCallEdges` NULLs `refs.symbol_id` unconditionally, while the enum stream is narrowed
by the stale predicate and does not re-derive those refs. So a section's bind count can be
short because it is STALE, not because the resolver declined. Per section, the `W` column
above. On CLIENT the effect is exactly measurable:

| CLIENT accounting | value |
|---|---|
| candidate `read` universe at Task 1 (4ccd1779) | 6064 |
| bare-read candidates the stage actually saw | 6036 |
| difference -- refs inside the 1 WITHHELD file | 28 |
| bound | 5983 |
| declined (not-visible) | 53 |

5983 + 53 + 28 = 6064, so every Task-1 candidate is accounted for.

The withheld file is `C:\Projects\DB\ORM3\CLIENT\uPipeClientConnection.pas`.

**ORM3 CLIENT is a SHARED database and this run left it degraded. The command that restores
it:** a normal incremental project index re-parses the drifted unit and re-derives its edges
(`index --project` is the documented form; verified against `--help` and
`resolve-dbs --project C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj`, which returns the DB
path below; NOT run by this task, which was scoped to `--resolve-only`):

```
<engine> index --project C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj --db C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite
```

Add `--dry-run` first to preview. **Which `<engine>` matters**: run it with the WORKTREE
engine and CLIENT keeps `r=1.6.0-alpha`; run it with the main tree's 1.5.1-alpha engine
before merge + redeploy and it also re-resolves the enum bindings away (the trap at the top
of this section). The same command with each section's own `.dproj`/`.sqlite` restores the
other 10 withheld-bearing sections in the `W` column above.

**And the loss is WIDER than the enum arm.** `ClearCallEdges`' own comment already documents
that it NULLs `refs.symbol_id` for stale files' refs, which is the enum-stream half. What the
CLIENT M4 table further down shows is that the file's `call_edges` and `member_accesses` rows
go too, and that `symbol_facts.effect_free` moves with them -- 4 routines fell from `proven`
to `not_proven`. So a whole-DB resolve over ANY index carrying stale files degrades the
purity result for EVERY consumer of that database, not just the enum arm and not just this
branch. That is why it is filed as an engine defect
(`docs\INBOX-resolve-only-clears-stale-file-edges.md`) and not only as a note here.

**The withheld predicate is mtime-based and misses content-only drift.** A SHA256 sweep of
every indexed file against `files.sha256`. The row list comes from the index (note
`--limit`: the default cap is 200 rows and the tool DOES announce it with
`-- ROW CAP REACHED at 200 rows; there are more. Pass --limit N.`, so a sweep written
without it silently covers only the first 200 files -- an operator error, not a tool defect):

```powershell
& $exe sql --db $db --limit 5000 --format json --query "SELECT id, path, sha256, mtime_unix FROM files"
# then, per row:  (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower() -ne $sha256
```

| DB | files rows | SHA mismatches | reported WITHHELD |
|---|---|---|---|
| CLIENT | 625 | 3 | 1 |
| SERVER | 470 | 2 | 0 |

Of CLIENT's 3, only `uPipeClientConnection.pas` also has a differing `mtime_unix`
(1789379662 stored vs 1790142302 on disk) and only that one was withheld.
`uMain.ViewModel.pas` and `SOFTWID.PAS` have byte-identical mtimes and different content,
and were silently re-resolved from stale parses. SERVER's `uMicFactory.pas` differs by one
second of mtime and was not withheld either. 622 of CLIENT's 625 files hash-match, so the
stored `sha256` is the plain file SHA256 and the mismatches are real content drift.

### M1 -- `cmdDelta` / `cmdTableLoad` (the reproducing query)

```sql
SELECT name_text, kind, (symbol_id IS NOT NULL) AS bound, COUNT(*) FROM refs
WHERE name_text IN ('cmdDelta','cmdTableLoad') GROUP BY name_text, kind, bound
```

CLIENT:

| name_text | kind | bound | count |
|---|---|---|---|
| cmdDelta | read | 1 | 38 |
| cmdTableLoad | read | 1 | 42 |

SERVER:

| name_text | kind | bound | count |
|---|---|---|---|
| cmdDelta | read | 1 | 2 |
| cmdTableLoad | read | 1 | 2 |

Both tables have **4 rows in total and no `bound = 0` row**, so there is no `bound = 0`
row to explain by rule. Baseline at 4ccd1779 was the same four (name, kind, count) triples
with `bound = 0`; only the `bound` column moved.

### Candidate universe after the re-resolve

| DB | kind | bound | rows |
|---|---|---|---|
| CLIENT | member-access | 0 | 8 |
| CLIENT | read | 0 | 81 |
| CLIENT | read | 1 | 5983 |
| SERVER | member-access | 0 | 4 |
| SERVER | read | 0 | 1484 |
| SERVER | read | 1 | 1970 |

CLIENT has no bound `member-access` row and SERVER has none either: **neither CLIENT nor
SERVER binds a single qualified (Shape B) reference.**

### Every `bound = 0` row explained, by rule

The previous revision of this heading said "every `bound = 0` **read**", which quietly
scoped out the 12 unbound `member-access` rows in the table above and attached no rule to
any of them. They are explained here.

**The 12 unbound qualified rows (CLIENT 8, SERVER 4) are all one construct.** Read back with
their `receiver_text`, every one of the 12 is `TStringSplitOptions.None`, in
`BASICSF.pas` (4 sites, in both DBs) and `GAGEFRM2.PAS` (4 sites, CLIENT only), e.g.
`Tokens := tstr.Split([';'], '"', '"', TStringSplitOptions.None);`.

**Checked, not assumed, and it is NOT the same shape Task 5 found.** Task 5's 8 unbound
qualified refs on the self-index were type-ALIAS receivers. These are not aliases: the
receiver type is simply **absent from the project database**. `SELECT ... FROM symbols WHERE
name COLLATE NOCASE = 'TStringSplitOptions'` returns **0 rows** on CLIENT and 3 rows on
`library-Win64` (`System.SysUtils.TStringSplitOptions` is the relevant one). The only
project-side `enum_value` named `None` is `MSCTYPES.TImportFileState.None`, an unrelated
enum in an unrelated unit -- which is exactly what a bind here would have attached an RTL
`TStringSplitOptions.None` to.

**So the decline is correct and necessary, and its rule is rung 3c, not R1/R2/R3.** The
qualified stream resolves the receiver first; a receiver that resolves to nothing in this
database ends the candidate there, before visibility, ambiguity or shadowing is consulted.
That is why the decline counters read `ambiguous 0, shadowed 0` on CLIENT and SERVER and why
CLIENT's `not-visible 53` equals its bare-read shortfall exactly, with no qualified decline
folded in: these 12 are counted by no counter. The same "never reaches R1-R3" outcome as
Task 5's 8, reached by a different cause (cross-index receiver, not alias receiver).

The rest of this section covers the unbound `read` rows.

**CLIENT -- 81 unbound reads.** 28 are in the WITHHELD file and were never offered to the
resolver (not a decline). The remaining 53 are the stage's `not-visible` count, and all 53
are R1 declines that a naive name join would have got WRONG:

| declining site | name(s) | occurrences | why R1 is right |
|---|---|---|---|
| `uJobList.ViewModel.pas` | 11 `LotStatus_*` | 17 | reads the unit's OWN `const LotStatus_*`; it has no `uses` edge to `iFOLDERS` at all (queried `unit_uses`: 0 rows matching `%folder%`) |
| `uIPCHART.PAS` | fM1..fM4 | 16 | the only `enum_value` twins are `INSPFLDR.Messages.TFLDRMessageID.fm1..fm4`, a different unit |
| 13 CLIENT/COMMON units | mtError, mtWarning | 20 | the only `enum_value` twins are `iLoggingServiceP.TMessageType.*`; these sites are reading VCL `TMsgDlgType` |

17 + 16 + 20 = 53, and 53 + 28 = 81, so the table accounts for every unbound read.

**SERVER -- 1484 unbound reads, 7 distinct names:**

| name | occurrences | files |
|---|---|---|
| CmdNextID | 1463 | 133 |
| mtWarning | 4 | 2 |
| fM4 | 4 | 1 |
| fM3 | 4 | 1 |
| fM2 | 4 | 1 |
| fM1 | 4 | 1 |
| mtError | 1 | 1 |

Those seven rows sum to 1484. `CmdNextID` alone is 1463 of them and is the single most
load-bearing decline on the whole corpus: it is declared as a **field**
(`TDataService_<TABLE>_SERVER.CmdNextID`) in well over 100 server units, and exactly once
as an `enum_value` (`Pipes.Protocol.TCommandID.cmdNextID`). Of 1598 refs to that name,
**2 bound** -- both in `Pipes.Commands.pas` and `Pipes.Protocol.pas`, the two units that
genuinely see `TCommandID` -- and 1596 did not. R1 prevented ~1463 wrong bindings here.

### The `LotStatus_*` accounting (CLIENT), escaped query

`LIKE 'LotStatus\_%' ESCAPE '\'` (the plan's bare `_` is a single-character wildcard and
also sweeps in `LotStatusCodes`, `LotStatusColors`, `LOTSTATUSCODE`,
`LotStatusCodeDescription`, which are not enum values).

The two data columns are `occurrences (bound flag)` -- the parenthesised value is the
`bound` column of the group-by, 0 or 1, **not a count**, so it must not be summed.

| name_text | uJobList.ViewModel.pas: occurrences (bound flag) | iFOLDERS.PAS: occurrences (bound flag) |
|---|---|---|
| LotStatus_CustAcWithCond | 2 (0) | 3 (1) |
| LotStatus_CustAccept | 2 (0) | 3 (1) |
| LotStatus_CustReject | 2 (0) | 3 (1) |
| LotStatus_InspAccept | 1 (0) | 3 (1) |
| LotStatus_InspDone | 1 (0) | 3 (1) |
| LotStatus_InspInProgress | 1 (0) | 3 (1) |
| LotStatus_InspNotStarted | 1 (0) | 6 (1) |
| LotStatus_InspReject | 1 (0) | 3 (1) |
| LotStatus_MRBAcNotify | 2 (0) | 3 (1) |
| LotStatus_MRBAcSortRework | 2 (0) | 3 (1) |
| LotStatus_MRBReject | 2 (0) | 3 (1) |
| LotStatus_Other | -- | 2 (1) |

23 rows; **12** distinct names (Task 1's 12, not the plan's 11); 11 names appear in
`uJobList.ViewModel.pas` for 17 occurrences, all `bound = 0`; 12 names appear in
`iFOLDERS.PAS` for 38 occurrences, all `bound = 1`; 17 + 38 = 55, matching Task 1's 55.

`symbols` confirms the shape: 11 of the 12 names are declared BOTH as a `const` in
`uJobList.ViewModel` and as an `enum_value` in `iFOLDERS.LotStatusCodes`; `LotStatus_Other`
has no `const` twin. The unit that sees only the enum binds; the unit that owns the const
declines. **That is the plan's predicted outcome.**

**But it is decided by R1, not R3, and that matters.** The stage line reports
`shadowed 0` for CLIENT. `uJobList.ViewModel.pas` has no `uses` edge to `iFOLDERS`, so R1
(visibility) rejects the candidate before R3 (shadowing) is ever consulted. The 12
`LotStatus_*` collisions therefore exercise **R1**, and R3 gets no exercise on CLIENT at all.

### What R1/R2/R3 actually got exercised by, corpus-wide

Reading only the per-section table above: `NV` is non-zero on 2 sections (1537 declines
total), `AM` and `SH` are non-zero on 2 sections (3 + 3 each). So:

* **R1 is heavily and decisively exercised** -- 1537 declines, spot-checked correct in
  three independent shapes (a local const, a same-named field in 133 units, a VCL enum).
  This is the discriminating evidence the branch needed: a naive name join would have
  written 1537 wrong bindings.
* **R2 and R3 are exercised only by ORM3-MicroniteTests and ORM3-PdfOcrImportTests**, at
  3 ambiguous + 3 shadowed each, against the vendored DUnitX sources both sections share.
  That is thin. The branch's confidence in R2/R3 still rests mostly on the guard fixture.
* The declines are NOT zero, so the "zero declines would discriminate nothing" concern
  does not apply to R1. It does still apply to R2/R3.

### Does the corpus exercise rung 3c's TYPE arm?

**Yes.** CLIENT and SERVER bind 0 qualified refs, so they do not. The 67 qualified
bindings in ORM3-MicroniteTests (and the same 67 in ORM3-PdfOcrImportTests) were read back
with their source lines:

| receiver kind | count | examples |
|---|---|---|
| TYPE receiver | 65 | `TTestResultType.Pass`, `TLogLevel.Error`, `TDUnitXExitBehavior.Continue`, `TDunitXConsoleMode.Verbose` |
| UNIT receiver | 2 | `DUnitX.Types.exExact`, `DUnitX.Types.exDescendant` (`DUnitX.TestFramework.pas:122-123`) |

65 + 2 = 67. The TYPE arm is exercised 65 times per section on real code -- the opposite
of the self-index, where all 9 qualified bindings carried a UNIT receiver.

### R5 -- scoped enums (`{$SCOPEDENUMS ON}`)

Measured across all 33 project DBs: for every bound **bare** read, the declaring
`enum_value`'s file was text-scanned and the last `{$SCOPEDENUMS ON|OFF}` before the
declaration line taken as the state.

| metric | value |
|---|---|
| distinct enum values with a bound bare read | 1758 |
| ... declared under `{$SCOPEDENUMS ON}` | **0** |
| bare reads bound to a scoped value | **0** |
| bare reads bound to an unscoped value | 13443 |

**Positive control**, because a zero is a claim about the detector first: of 1185 distinct
indexed `.pas` files across the 33 project DBs, exactly **1** contains
`{$SCOPEDENUMS ON}` -- `C:\Projects\DUnitX\Source\DUnitX.TestFramework.pas`, which toggles
ON at line 100, OFF at 106, ON again at 244. `TLogLevel` (102-104), `TTestResultType`
(246-251), `TDUnitXExitBehavior` (484-485) and `TDunitXConsoleMode` (489-491) all sit
inside an ON region. Every one of the 65 refs bound to those 14 values is a
`member-access` with a non-empty receiver; the 4 bare `read` refs naming those values are
`bound = 0`. So the detector can see the one scoped file in the corpus, and the answer is
still zero.

**No `docs\INBOX-enum-binding-scoped-enums.md` was filed**: the exposure measured 0 on the
whole project corpus, which is the opposite of non-trivial. The hazard is real in the
abstract (the extractor still does not record scopedness) and would need re-measuring
against the LIBRARY indexes, where RTL/VCL scoped enums are common.

### R7 -- reads inside a routine that contains a `with` block (CLIENT)

Candidate reads joined to `refs.enclosing_symbol_id`, the enclosing symbol's
`impl_start_line..impl_end_line` scanned for a `with ` token.

| population | bound | declined | total |
|---|---|---|---|
| enclosing routine contains `with ` | 178 | 9 | 187 |
| enclosing routine does not | 5771 | 72 | 5843 |

187 + 5843 = 6030; the candidate universe is 6064, so 34 candidate reads have no enclosing
symbol and are in neither row. **178 bound reads sit inside a `with`-bearing routine** and
could in principle be naming a `with` receiver's member rather than the enum value.

Top ten enclosing routines by candidate-read count:

| routine | candidate reads |
|---|---|
| uAutoTest.RunAutoTest | 24 |
| uINSPRSLT.TmcINSPRSLT.ResultAdvisory | 14 |
| uJobList.ViewModel.TJobListViewModel.LoadAll | 11 |
| uJobList.ViewModel.TJobListViewModel.LoadAllAsync | 10 |
| Blueprint4.TfrmBlueprint4.FormShow | 9 |
| uSetupDefaultsFrm.TdlgSetupDefaults.PopulateFromRec | 8 |
| Blueprint4.ViewModel.TBlueprint_ViewModel.ImportLK | 8 |
| uMain.ViewModel.TMainViewModel.LoadFolders | 6 |
| MSCTYPES.DimSpec_StrReprf | 6 |
| z19Slct.TZ19slctFrm.ApplySelections | 5 |

Filed for the owner as `docs\INBOX-enum-binding-inside-with.md` (untracked). **No rule was
added -- R7 is a stated non-goal of this branch.**

### Rule 0 -- duplicate `enum_value` groups (owner ruling 4, the audit)

```sql
SELECT COUNT(*) AS dup_groups, IFNULL(SUM(c),0) AS dup_rows FROM (
  SELECT lower(qualified_name) q, start_line, end_line, COUNT(*) c
  FROM symbols WHERE kind='enum_value' GROUP BY q, start_line, end_line HAVING c > 1)
```

`collapsed 0 (decisive 0)` on **all 33** sections (the `C(D)` column above). Independently,
the duplicate-group query above returns `dup_groups = 0` on **all 33** project DBs, so there was
nothing for rule 0 to collapse and the counters could not have been anything but zero.
**The collapse was decisive nowhere. That is the recorded answer, not a disappointment** --
it matches the prior finding that rule 0 is structurally inert, and the only DBs that ever
showed duplicate groups (library-Win64/Win32, 6 groups each at Task 1) are exactly the two
not re-resolved here.

### M4 -- no collateral

| DB | point | edges | accesses | proven | not_proven | not_computed |
|---|---|---|---|---|---|---|
| CLIENT | before | 20409 | 9311 | 2896 | 7254 | 0 |
| CLIENT | after | 20343 | 9281 | 2892 | 7258 | 0 |
| SERVER | before | 25793 | 14836 | 2818 | 5284 | 0 |
| SERVER | after | 25793 | 14836 | 2818 | 5284 | 0 |
| worktree self-index | before | 11626 | 11115 | 194 | 2751 | 0 |
| worktree self-index | after | 11626 | 11115 | 194 | 2751 | 0 |

**SERVER and the worktree self-index are identical column for column. CLIENT is not, and
it is not rounded away here.** CLIENT lost 66 `call_edges`, 30 `member_accesses`, and moved
4 routines from `proven` to `not_proven`.

The cause is the WITHHELD file, and it is the opposite of what the log line claims:

| CLIENT file | call refs | member-access refs | call_edges owned | member_accesses owned |
|---|---|---|---|---|
| uMain.ViewModel.pas (sha drift, NOT withheld) | 106 | 111 | 34 | 32 |
| uPipeClientConnection.pas (WITHHELD) | 161 | 42 | **0** | **0** |

The withheld file now owns **zero** edges and **zero** accesses despite 161 call refs, and
66 - 0 and 30 - 0 are exactly CLIENT's M4 deltas. The log says withheld files' "call edges
and receivers were left alone"; they were in fact CLEARED and then not re-derived. SERVER,
which withheld nothing, moved nothing -- which is the control showing the resolver bump
itself is collateral-free.

### Invariants and the `write` negative control -- all 33 DBs

Swept over every project DB, as one query per DB over the list from
`drag-lint resolve-dbs --platform Win64` with `Library` excluded:

```sql
SELECT (SELECT COUNT(*) FROM call_edges ce JOIN symbols s ON s.id=ce.target_symbol_id
          WHERE s.kind='enum_value') AS bad_edges,
       (SELECT COUNT(*) FROM member_accesses ma JOIN symbols s ON s.id=ma.member_symbol_id
          WHERE s.kind='enum_value') AS bad_acc,
       (SELECT COUNT(*) FROM refs WHERE kind='write'
          AND name_text COLLATE NOCASE IN (SELECT name FROM symbols WHERE kind='enum_value')) AS wr_total,
       (SELECT IFNULL(SUM(symbol_id IS NOT NULL),0) FROM refs WHERE kind='write'
          AND name_text COLLATE NOCASE IN (SELECT name FROM symbols WHERE kind='enum_value')) AS wr_bound,
       (SELECT COUNT(*) FROM (SELECT lower(qualified_name) q, start_line, end_line, COUNT(*) c
          FROM symbols WHERE kind='enum_value' GROUP BY q, start_line, end_line HAVING c>1)) AS dup_groups
```

| check | result |
|---|---|
| `call_edges` whose target is an `enum_value` | 0 on 33 of 33 |
| `member_accesses` whose member is an `enum_value` | 0 on 33 of 33 |
| `write` refs naming an enum value, `bound` | 0 on 33 of 33 |

`write` totals are non-zero on two DBs only -- CLIENT 12 (Task 1 measured 12) and SERVER
145 -- and bound is 0 on both, so the negative control holds where it can actually fail.

### R-B autodoc churn, re-measured on CLIENT (Task 6 could not)

`document --qname <v> --db <CLIENT>`, **DRY RUN, never `--apply`**, same CLIENT DB, two
engines differing only in the value arm: BEFORE
`C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe`, AFTER the worktree
engine. The BEFORE engine prints a one-line read-side resolver advisory on a 1.6.0-stamped
DB; that line is stripped before comparison (it was the ENTIRE diff on the first two
samples and would otherwise have been read as churn).

**Channel 1 -- re-windowing.** CLIENT has 592 `enum_value` symbols, 224 with at least one
bound read, and **45** with more than 5 distinct enclosing callers, so 45 is the upper
bound on blocks whose rendered window can move. Confirmed on real blocks: `mtError`,
`mtWarning`, `mtInfo` and `cmdLoad` each render a DIFFERENT first five while the
`(+N more)` total is unchanged (`+625`, `+76`, `+412`, `+133` before and after).

**Channel 2 -- marker appearance.** An over-approximating SQL query (no reach filter, so it
can only over-count) predicted **18** partially bound values. Running the A/B on all 18:

| outcome | count |
|---|---|
| rendered differently at all | 18 of 18 |
| gained a ` ?` marker (0 -> N) | **3 of 18** |

The 3 are `Pipes.Protocol.TCommandID.cmdGoodbye`, `...rspDenied` and `...cmdHello`, each
0 -> 1. **This is the first non-zero measurement of channel 2 anywhere** -- Task 6 measured
0 on the self-index and predicted ORM3 would be non-zero. The surviving unverified reader
in all three cases lives in `uPipeClientConnection.pas`, the WITHHELD file, whose reads
were cleared and never re-bound; a fourth value with a survivor in the same file
(`rspOK`, 317 callers) does NOT gain a marker because its survivor falls outside the
5-entry window. So on CLIENT channel 2 is entirely an artefact of the withheld file, and
reindexing that one unit would plausibly return it to 0.

### Open concerns handed forward

1. **Withheld files clear edges they do not re-derive** (CLIENT M4 delta, and all 3
   channel-2 instances). The log line's wording ("left alone") is wrong about what happens.
   The damage is not confined to the enum arm -- `symbol_facts.effect_free` moved too, so it
   degrades purity for every consumer of the database. **CLIENT is a shared DB and is left
   degraded by this task**; the restoring command is written out under "WITHHELD files"
   above, and the engine defect is filed as
   `docs\INBOX-resolve-only-clears-stale-file-edges.md`.
2. **The withheld predicate is mtime-only** and missed 2 of 3 content-drifted files on
   CLIENT and 1 of 2 on SERVER.
3. **R2/R3 remain thinly exercised on real code** -- 3 + 3 declines on two sections that
   share one vendored dependency.
4. **The library sections are still at 1.5.1-alpha** and must be run once from the main
   tree after merge + redeploy.
