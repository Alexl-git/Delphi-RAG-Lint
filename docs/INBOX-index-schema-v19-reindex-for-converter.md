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

**Not yet rebuilt.** The Phase 3 rollout (plan Task 17) had not run when this message
was written, so **every DB on this machine is still at its previous version**. This
section will be filled in with the actual `schema_version` per DB once the reindex
completes; until then, introspect the specific `.sqlite` you are about to read:

```sql
SELECT value FROM schema_meta WHERE key = 'schema_version';
```

The DBs in scope for that rollout are the nine manifest entries plus `YADF.sqlite`
(v18) and `YADFOT.sqlite` (still v17).

## 7. Not relevant to the converter

- The comment-harvesting work (promoting `//` comments into managed `<summary>` tags),
  the `ddHarvestDrift` doc-drift finding, and the `Pure` / `Mutates:` /
  `UI thread only` / `Touches:` render lines. These change what `document` writes into
  `.pas` files; they change nothing the converter reads.
- The `Pure` line in particular is derived at render time and has no column at all.
