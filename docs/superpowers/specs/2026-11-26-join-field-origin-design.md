# Join datasets: the table of every field (field-origin step 1) -- design 2026-11-26

Status: built on lane/v1541-origin (1.54.1). Goals: `2026-11-25-cross-table-fields-goals-DRAFT.md` (N1, order step 1;
owner Q4 = A). Survey and method: `C:\TEMP\claude\lanes\v154\MEMSURVEY\REPORT.md` (step 1: +258 calc, +179 lookup in
M2022). Field repository: `2026-11-22-field-repository-v2-design.md` section 9, rulings `2026-11-23-field-repository-v3-rulings.md`
R1 ("joins: not designed yet" -- this is that design, for joins only).

## 1. Problem

`repo read-dfm` gives a dataset ONE table: UpdateOptions.UpdateTableName, TableName, or a SELECT over one table.
A SELECT over several tables (a join) was `UNRESOLVED (the SQL reads N tables: ...)`. Its DATA fields already got a
table per field (select list, then Origin), but its calc and lookup fields got none, so they were never read:
in M2022 that is 456 calc and 179 lookup fields on 59 join datasets.

The unit is the FIELD, not the dataset: one join row holds columns of several tables.

## 2. Rules

### 2.1 Data field of a join: table and column (in this order)

1. **Select list**, by the name the field gets (alias, else column; a column repeated without an alias is `NAME_1`,
   `NAME_2`, ... in list order, as BDE and FireDAC name it -- `Po.P0, Pt.P0` gives the fields `P0` and `P0_1`):
   * `Q.COL` / `Q.COL AS NAME` -- Q is an alias or a table name of the FROM clause (`"X.DB"` forms cleaned as today);
   * unqualified `COL` -- the ONE FROM table whose schema facts (repository rows with a column type) have COL;
     when a FROM table has no schema facts, or two have COL, it is unresolved (`COL is in 2 tables of the FROM: A B` /
     `the repository has no schema facts for X`);
   * an expression -- `computed by the SQL` (no table, as today).
2. **Star expansion** (`*`, `Q.*`), only when no select-list item has the name: the star tables are the FROM tables
   (`*`) or the one table Q names. One star table: that table. Several: the ONE whose schema facts have the column; the
   Origin decides when it names one of them. A name in two star tables without an Origin is unresolved, never "the first
   in list order" (the survey took the first; the engine does not pick).
3. **Origin** (the persistent field's `Origin` property) in its three forms: `"X.DB".COL`, `ALIAS."X.DB".COL`, bare
   `COL`; the unquoted `X.DB.COL` is read as `"X.DB".COL`. The qualifier must name a FROM table (alias or table name).
   Bare `COL` is treated like an unqualified select item (2.1.1, second bullet).
4. **Conflict**: when the select list and the Origin both name a column and they differ, the field is unresolved with
   `conflict: the select list says T1.C1, Origin says T2.C2` -- reported, never picked. (Survey: 0 conflicts in 2,155.)

Single-table datasets are unchanged: their table is the dataset's table; the conflict check applies to them too.

### 2.2 Lookup field of a join

Its table is the table of its KeyFields: every key field (`A;B` = several) is a field of the dataset; all of them must
resolve (2.1) to ONE table. SOURCEKEY = the column of the key field(s) in that table. Several tables, or a key field
without a table: unresolved with the reason (`the key fields come from 2 tables: A B`). The multi-field key stays BLOCKED
as today (one-column SOURCEKEY).

### 2.3 Calc / internal-calc field of a join

Its table is the ONE table of everything its calc code reads of the dataset (the OnCalcFields slice that computes it,
`TDfmrBody.FieldsUsed`):

* a data field -> its table (2.1); a lookup -> its table (2.2); another calc field -> the table fields IT reads, breadth
  first; a calc field already visited adds nothing (cycle guard), so `A := B + X; B := A + Y` over one table is that table;
* the condition of an `if` / `if-else` whose branches only assign OTHER calc fields (cut from this field's slice) is not
  read by this field (M2022 CompStats.qryTools.LongTool);
* one table -> the field is read into that table; macros name the columns (`{{QTY}}` for `O.Qty AS OQ`);
* several tables -> unresolved `the calc code reads 2 tables: A B` (survey step 5, a policy question: where does a
  two-table calc live -- OUT here);
* a field without a table, no code, no field read, a cycle -> unresolved with that reason.

A blocked body still gives its table when the slice was found (the blocked text is reported, not stored).

### 2.4 Event code (OnGetText, OnValidate, ...) of a join field

Stored only when every dataset field the code reads has the owning field's table; otherwise the body is BLOCKED
(`the code reads fields of another table: X`). A macro of a join must never name a column of another table.

## 3. Output

* Dataset line: `qryJoin (TQuery) -> JOIN ORDERS TOOLS: 2 data, 3 calc, ...` (the FROM tables in order); the dataset is
  no longer counted as unresolved.
* `  no table column: A, B` as before (every field without a table), then for a join one line per field:
  `  no table: B: <reason>`.
* New summary line after `calc bodies:`: `joins: N datasets; X calc, Y lookup, Z data fields with a table; W without`.
* `--json`: per dataset `join` (array of tables) and `noTable` (array of `{field, why}`); totals `joins`
  (`{datasets, calc, lookup, data, without}`).

## 4. Deliberately out

* Memory tables, bulk copies, field-by-field copies, AssignRecord (survey steps 2-4, `memtables`): next steps.
* Calc over SEVERAL tables (step 5): reported, not placed.
* Lost kbmMemTable AttachedTo links (step 6): user hint, later.
* Run-time SQL that replaces the DFM's SQL (24 M2022 joins): not followed; the DFM text is what is read.
* Path roles (N3), relation list (N2), formulas and bindings (N4), the SQL composer (section 10 of the goals): later.
* A DB schema read during read-dfm: schema facts come from the repository only (`repo refresh-schema` / `seed-fb`).

## 5. Tests

`tests\autotest\run_v1541_ORIGIN.ps1`, fixtures `tests\fixtures\fieldrepo\origin\` (uJoin.dfm / .pas):
O1 per-field data origin (alias, table name, Origin three forms, unquoted `X.DB.COL`, `NAME_1` repeats), O2 conflict
reported, O3 calc of one table read with column macros, O4 calc over two tables unresolved, O5 calc using another calc,
O6 calc with no code / reading a computed column / a cycle without and with a table field / the condition of a cut
`if-else`, O7 lookup by key table, key fields in two tables unresolved,
O8 star and unqualified columns with and without schema facts, O9 event code reading another table blocked,
O10 join line, totals and JSON, O11 the old fixture (`uOrders.dfm` qryJoin) now a join.

## 6. Measured (M2022, read-only, 2026-11-26)

Dry run of `repo read-dfm` over the same 182 DFMs as the TT-DFMREAD run (list from the index), on a migrated COPY of the
TT-DFMREAD repository (no schema facts; hash unchanged after the run). 914 datasets (the survey's 956 minus the 42 the
index does not list as datasets).

| | 1.54.0 | this design | survey step 1 |
|---|---|---|---|
| unresolved datasets | 372 | 245 (= the survey's 245 no-SQL datasets) | - |
| join datasets | (unresolved) | 127; 59 with calc / lookup | 59 with calc / lookup |
| calc fields of joins with a table | 0 | 213 | 258 |
| lookup fields of joins with a table | 0 | 179 | 179 |
| data fields of joins with a table | 4,714 | 4,795 (+81: `NAME_1` repeats) | - |

Per field against `MEMSURVEY\calc_fields.csv` (323 join calc fields with code): 211 agree on ONE table, and in all 211
the table is the survey's; 60 of 60 SEVERAL agree; 3 of 5 none-used agree; all 179 lookups agree on the table.
Where they differ the engine is stricter, never different:

* 36 survey ONE, engine SEVERAL: ToolTrack.qryToolTrack 22, GroupControl.qryTools 7, TPCReport.qryCertificat 3,
  IPTrack / PTrack / ProcChartWide.qryRSTools and OperationAnalysis.qryTools 1 each. Checked for ToolTrack: the slice
  reads the key fields of `dmlSystem2.tblToolStatL.FindKey([... OperID, ToolID, PosID, CParamSet])` (ToolTrack.pas:2948),
  which come from TOOLFLDR and TOOLGR12; the survey counted FindKey / Locate arguments as keys of ANOTHER dataset, not as
  own inputs. Such bodies read another dataset (survey question C, "keyed lookup"), so they are not one-table code anyway.
  The other 14 were not inspected (INFERRED: the same kind).
* 11 survey ONE, engine `reads X, which has no table` (all ToolTrack.qryToolTrack): calc fields reading a calc field the
  engine cannot place, e.g. DueInStr reads LifeValP.
* 2 survey none-used, engine ONE: the slice names a field the survey did not see (FieldByName).

Unqualified columns: 21 data fields of joins say `not qualified and the repository has no schema facts`; with a
refreshed schema (`repo refresh-schema`) they resolve or are reported ambiguous. The survey used the persistent fields of
resolved TTables as its column list; the engine uses only repository schema facts (section 4).

DRAGLINT_EXTRACTOR_VERSION: unchanged (the reader runs over DFM text and unit text at read time; no index change).
