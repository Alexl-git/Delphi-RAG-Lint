# B07 -- 1.44 section rules + redundant-cast on Micronite: measurement recipe (1.52)

Status: RECIPE ONLY (lane BK-PERF, 2026-11-18). Run it AFTER the 1.52 re-parse is DONE and the
resolver re-derive has stamped the Micronite DB; not before (VERIFY3: on the pre-re-parse copy the
four init rules returned [] in 8m23s, so precision could not be measured).

Why it waits: the four rules read the `initialization` section refs that the 1.44 resolver
backfills (ResolveSectionEnclosing, `CMinSectionResolver = '1.20.0-alpha'` in
DRagLint.Lint.ProjectRules). A DB whose `resolver_fingerprint` is older, or one indexed before
the re-parse, answers UNKNOWN / nothing, which reads as "rule is silent", not "rule is precise".

## 0. Setup (private, read-only on every real DB)

```
$R   = 'C:\TEMP\claude\b07'                       # any private dir
$E   = "$R\engine\drag-lint.exe"                   # a COPY of the deployed 1.52 engine (+ rules\, DLLs)
$Lib = 'C:\Projects\.drag-lint\library-Win64.sqlite'
Copy-Item C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite "$R\Mic.sqlite"
```
Never run against the live DB and never `lint-all` without `--db` (a no-`--db` repro can write a
real project DB).

## 1. Gate: is the copy re-derived?

```
& $E sql --query "SELECT value FROM schema_meta WHERE key = 'resolver_fingerprint'" --db "$R\Mic.sqlite" --json
```
The value must start with `r=` and carry a version >= 1.20.0-alpha (1.52 stamps r=1.29.x).
If it is older: STOP, the re-derive did not reach this DB; do not report a count.

## 2. The four section rules

```
$rules = 'init-order-hazard,heavy-initialization,finalization-after-dependency,global-set-in-initialization-never-freed'
& $E lint-all --db "$R\Mic.sqlite" --library-db $Lib --rule $rules --json --no-stand-down > "$R\sect.json" 2> "$R\sect.err"
```
`--no-stand-down` (1.52 B17) keeps an engine stage / `shutdown` elsewhere from cutting the run to
PARTIAL (exit 4). Exit 0 or 1 is a whole run; exit 4 means it was NOT a whole run -- redo it.

Count per rule (lint --json is a bare ARRAY; the line field is `start_line`):
```
$f = Get-Content "$R\sect.json" -Raw | ConvertFrom-Json
$f | Group-Object rule_id | Select-Object Name, Count
```
Print the raw first finding before trusting any filter on its fields.

## 3. Precision (per rule)

* Take up to 20 findings per rule (all if fewer), spread over files (`Group-Object file_path`).
* For each, open the source at `start_line` and classify TP / FP / UNSURE with one line of reason
  (FP class names: "section idle", "unit not initialised by us", "ordering guaranteed by uses").
* Precision = TP / (TP + FP). Record UNSURE separately, never as TP.
* A rule still at [] after the gate in step 1 passed is a FINDING (rule or fact defect): file it
  as `docs\INBOX-b07-section-rules.md` with the query, the fingerprint and one unit that has an
  `initialization` section the rule should have seen.

## 4. redundant-cast stats

```
& $E lint-all --db "$R\Mic.sqlite" --library-db $Lib --rule redundant-cast --json --no-stand-down > "$R\rc.json" 2> "$R\rc.err"
$rc = Get-Content "$R\rc.json" -Raw | ConvertFrom-Json
$rc.Count
$rc | Group-Object file_path | Sort-Object Count -Descending | Select-Object -First 10 Count, Name
```
Sample 20 for precision as in step 3. Compare the total with the last recorded Micronite count
(VERIFY / v1511 FP-REMEASURE) and say whether the delta is explained by the re-parse.

## 5. Report

One block in the 1.52 owner page / ledger: fingerprint, wall time + machine load (median of 3 only
if a timing claim is made), per-rule count, precision with the sample size, every FP class seen,
and the INBOX path if one was filed. Delete `$R` afterwards (disk).
