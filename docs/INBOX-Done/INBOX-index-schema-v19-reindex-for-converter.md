> **RETIRED to INBOX-Done/ on 2026-08-15.** DISCHARGED: a one-off reindex request for schema v19, same as its v18 sibling.
>
> Original note follows unchanged.

# INBOX -> component-conversion workstream: index is now schema v19 (2026-08-03)

**For:** whoever works on the component converter (`convert-apply`, `convert-validate`,
`convert-scaffold`, the convrules editor, and the `proptree` engine that feeds them).
**From:** the Auto-Document Phase 3 session, 2026-08-03.
**TL;DR:** schema **19** adds four **additive columns** to the existing `symbol_facts`
table. Nothing was removed or renamed and the version gate is still a `>=` check --
but **`symbols.id` is reassigned by the full reindex, so re-resolve by
`qualified_name` and do not trust cached ids.** This is the same thing that bit you at
v18; it is first on the list for that reason.

## 1. READ THIS ONE FIRST -- `symbols.id` is reassigned again

A full reindex re-creates every `symbols` row, so any `symbols.id` the converter
persisted or cached across sessions (property-tree caches, id-keyed maps, saved
convrules that stored ids) is stale the moment the reindex runs. **Re-resolve
everything by `qualified_name` at query time.** Nothing else in this message is as
likely to cost you a debugging session.

## 2. Schema 18 -> 19: four additive columns on `symbol_facts`

| Column | Value shape | What it is |
|---|---|---|
| `mutates_params` | `'AList (var), AReason (out)'` | The `var`/`out` PARAMETERS a routine writes through. Capped at 8, then ` (+N more)`. |
| `ui_affinity` | `'cxGrid1, Application'` | UI controls/globals the routine touches. **Positive findings only** -- see below. |
| `touches` | `'file system, registry\|starts, commits'` | External surfaces and transaction verbs, **one column with a `\|` separator**. Either side may be empty and the separator is still present (`'file system\|'`, `'\|starts, commits'`). |
| `wiring` | *(reserved, reads NULL)* | Rendered shape `'di:IFolderService (singleton); ds:qryFolders -> FOLDERS (ID, NAME)'`, but computed at render time -- see section 4. |

Nothing was removed or renamed; the gate stays `>=`. **A consumer issuing `SELECT *`
against `symbol_facts` now gets four extra columns** -- select by name if column
position matters to your code. Full reference: `docs/INDEX-SCHEMA.md` section **2.15**,
updated this session.

**`ui_affinity` is positive findings only.** An empty value means "no UI touch was
detected", it does **not** mean "this routine is thread-safe". The curated base-type
list under-reports by construction, so do not build a negative claim on its absence.

## 3. `wiring` may be directly useful to you

The wiring fact surfaces exactly two things the conversion analysis already cares
about:

- **Spring4D DI bindings** -- `di:<interface> (<lifetime>)`, i.e. what a class is
  registered as and with what lifetime. Sourced from `di_bindings`, which is populated
  during `index`.
- **Dataset-to-table links** -- `ds:<symbol> -> <RELATION> (<COL>, <COL>)`, joining
  `orm_links` -> `fb_relations` -> `fb_columns`.

If you want it programmatically rather than through the doc block, the two new
`ISymbolStore` readers are `FindDiBindingsForImpl(implName)` (the reverse of the
existing `FindImplementationsOf`) and `FindOrmDatasetLinks(symbolId)`.

## 4. Do NOT read `symbol_facts.wiring` from the DB -- it is reserved

The column exists but is **never written**, exactly like `covered_by`. The fact is
computed lazily at `document` / `hover` time, because `orm_links` is produced by a
**separate post-index pass** (the `orm-link` command, which starts with a `DELETE` and
rebuilds). An index-time value would be empty on every first index, and afterwards it
would reference `symbols.id` values the reindex had already replaced. Query the two
readers above, or the underlying tables, rather than the column.

Note also that **no index on this machine currently has a single `orm_links` row** --
ORM3, the SQL DB and drag-lint's own test DB all read zero. The `ds:` half will stay
silent until the `orm-link` pass is actually run.

## 5. `document --strip` now exists, and doc comments are marker-owned

Relevant to anything of yours that reads or writes DocInsight comments:

- Every tag drag-lint owns carries `<!-- drag-lint:auto -->`; the facts block is fenced
  by `<!-- drag-lint:auto BEGIN -->` / `<!-- drag-lint:auto END -->`.
- **A tag without the marker is never touched.** A tag with it is regenerated on every
  run -- editing text inside a marked tag will be overwritten.
- `document --unit <f> --strip --apply` removes the engine's own blocks and marked tags
  and leaves every other byte alone. If your tooling ever needs to see a file's
  hand-written documentation without drag-lint's contribution, that is the switch.

## 6. Which DBs are at v19

**Done -- all nine manifest DBs were rebuilt on 2026-08-03** with drag-lint
`1.2.2-alpha` (Win64). Every one reads `schema_version = 19` and carries populated
values in the three writable new columns.

| Section | DB file | `schema_version` | symbols | `symbol_facts` rows | non-empty `mutates_params` / `ui_affinity` / `touches` |
|---|---|---|---|---|---|
| `ORM3` | `drag-lint.sqlite` | 19 | 74,230 | 13,267 | 355 / 302 / 463 |
| `SQL` | `drag-lint-sql.sqlite` | 19 | 4,631 | 0 | 0 / 0 / 0 |
| `Loader` | `Loader.sqlite` | 19 | 7,824 | 463 | 13 / 80 / 105 |
| `TableTools` | `TableTools.sqlite` | 19 | 1,280 | 152 | 6 / 4 / 10 |
| `DragLint` | `Delphi-RAG-lint.sqlite` | 19 | 20,653 | 3,586 | 177 / 60 / 326 |
| `DragLintGraph` | `Delphi-RAG-Lint-Graph.sqlite` | 19 | 2,362 | 399 | 20 / 1 / 14 |
| `OCRPDF` | `OCRPDF.sqlite` | 19 | 505 | 53 | 3 / 3 / 10 |
| `Library[Win32]` | `library-Win32.sqlite` | 19 | 2,295,181 | 418,255 | 9,826 / 14,701 / 755 |
| `Library[Win64]` | `library-Win64.sqlite` | 19 | 2,160,051 | 396,099 | 9,084 / 14,583 / 717 |

`SQL`'s zero is correct, not a gap: that DB indexes `MS*.SQL` migration scripts only
(4,631 symbols, all `sql_table` / `sql_column` / `sql_procedure` / `sql_trigger` /
`sql_domain` / `sql_generator`). `symbol_facts` is produced per **Pascal routine**, so
a DB with no Pascal has no fact rows.

`wiring` reads 0 non-empty in every DB. That is **by design** -- see section 4; do not
read it as a rebuild failure.

`YADF.sqlite` and `YADFOT.sqlite` are not manifest sections and were not part of this
rollout; introspect them before use.

### 6a. `--force-reparse` is MANDATORY on this upgrade -- read before you reindex

The v18 -> v19 migration adds the columns but **does not repopulate them**. An ordinary
incremental `index` run skips every file whose `path + mtime + sha` is unchanged, so its
`symbol_facts` rows are never rewritten and all four new columns stay NULL. Before the
force-reparse, `library-Win64.sqlite` was already stamped v19 and had the columns, with
**0 of 398,055 rows populated** -- a consumer querying it would have concluded "no
routine in the RTL mutates a var parameter".

The command actually used (three concurrent processes, ~3.6 h wall clock for the two
library platforms on 9 cores):

```
drag-lint index --all --config third_party\dll-win64\drag-lint.json ^
  --only ORM3,SQL,Loader,TableTools,DragLint,DragLintGraph,OCRPDF --jobs 3 --force-reparse
drag-lint index --all --config third_party\dll-win64\drag-lint.json --only Library --platform win32 --jobs 2 --force-reparse
drag-lint index --all --config third_party\dll-win64\drag-lint.json --only Library --platform win64 --jobs 4 --force-reparse
```

`--jobs` needs `--config`. `--only <Section>` plus `--platform` splits the two library
platforms into separate processes writing separate DBs, which is safe -- SQLite locking
is per-DB.

**If you ever see an empty new column, check whether the DB was force-reparsed before
concluding the fact does not apply.**

### 6b. One DB had to be deleted and rebuilt -- the migration is not atomic

`ORM3\drag-lint.sqlite` was found stamped `schema_version = 19` while `symbol_facts`
still had only the v18 columns. Because the version gate is `>=`, the migration never
retried, and **every open of that DB then failed hard**:

```
FATAL: ESQLiteNativeException: [FireDAC][Phys][SQLite] ERROR:
       table symbol_facts has no column named mutates_params
```

The only recovery was to delete the file and index from scratch (the pre-existing
`-shm` / `-wal` siblings suggest the earlier run was interrupted mid-migration). Filed
as a defect: `docs/INBOX-schema-migration-not-atomic.md`. If a DB of yours FATALs this
way, do not try to repair it -- delete and rebuild.

## 7. Not relevant to the converter

- The comment-harvesting work (promoting `//` comments into managed `<summary>` tags),
  the `ddHarvestDrift` doc-drift finding, and the `Pure` / `Mutates:` /
  `UI thread only` / `Touches:` render lines. These change what `document` writes into
  `.pas` files; they change nothing the converter reads.
- The `Pure` line in particular is derived at render time and has no column at all.
