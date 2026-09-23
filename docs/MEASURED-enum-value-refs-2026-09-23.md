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