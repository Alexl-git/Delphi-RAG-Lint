# drag-lint index database schema (reference for external consumers)

This document describes the SQLite database that `drag-lint index` produces --
a durable, queryable index of a Delphi/Pascal codebase (symbols, references,
uses-clauses, type ancestry, DI bindings, and more). It is written for anyone
building a tool OTHER than drag-lint itself that wants to read this database
directly.

Current schema version at time of writing: **17** (`SCHEMA_VERSION` in
`src/storage/DRagLint.Storage.Schema.pas`). v16 added the additive column
`files.last_compiled_unix` (compiler-finding freshness; see 2.1). v17 added
the additive column `symbols.prop_access` (property-leaf assignability
engine; see 2.2).

All facts in this document were originally verified against a live index
(`C:\Projects\DB\ORM3\drag-lint.sqlite`) at schema_version 15 (820 files /
64732 symbols / 231489 refs) via `drag-lint schema --db <path> --format json`,
and cross-checked against the DDL in `src/storage/DRagLint.Storage.SQLite.pas`
and `src/storage/DRagLint.Storage.Schema.pas`. That same sample DB was
re-checked 2026-07-20 -- both via `drag-lint schema --db ... --format json`
and via a direct read-only `SELECT value FROM schema_meta WHERE
key='schema_version'` (the two agree) -- and is now at **schema_version 16**
(it has been re-indexed at least once since the v15 pass; file/symbol/ref
counts have grown accordingly and are not restated here). The v17
`prop_access` column itself was verified against the DDL/migration code and
the shipped engine's CLI usage output, not against a re-indexed sample DB:
as of this writing the ORM3 sample has NOT been re-indexed with the v17
engine, so its `symbols` table has no `prop_access` column yet (confirmed via
`PRAGMA table_info(symbols)`) and will read NULL for every row once the
column is migrated in. This is expected: new columns are migration-safe
(`ALTER TABLE` runs on open; see the stability contract above), and
`prop_access` only back-fills for symbols that get re-extracted.

## 1. Purpose and stability contract

- The index is a single-file SQLite database (`.sqlite`). Open it **read-only**
  from another tool -- do not write to it; drag-lint owns the write path
  (incremental per-file reindexing, resolve passes, FTS trigger maintenance).
- **Tables and columns are stable within a schema version.** New columns are
  added additively (via `ALTER TABLE ... ADD COLUMN` in `Migrate()`, never by
  renaming or removing an existing column); new tables may appear across
  versions. A consumer should not assume anything about a FUTURE schema
  version beyond what is documented here.
- **Always check `schema_meta.schema_version` first**, before reading any
  other table:
  ```sql
  SELECT value FROM schema_meta WHERE key = 'schema_version';
  ```
  If the value is higher than what your tool was written against, tables/
  columns may have been added (harmless to ignore) or -- in a rare breaking
  migration -- semantics of an existing column could have changed; treat an
  unrecognized higher version as "verify before trusting."
- **Introspect programmatically instead of hardcoding column lists**: run
  `drag-lint schema --db <file.sqlite> --format json` (or `--format text` for
  a human-readable dump). This is a live, read-only walk of `sqlite_master` +
  `PRAGMA table_info` + row counts for every table in the DB -- it can never
  drift from what a given `.sqlite` file actually contains, unlike a doc.
  Usage:
  ```
  drag-lint schema --db <file.sqlite> [--format text|json] [--output <file>]
  ```
- The database is produced by `drag-lint index <path> --db <file.sqlite>`
  (see `USER-GUIDE.md` / `INSTALL.md` for indexing commands). This document
  only covers what to READ from it.

### Table of tables

| Table | Rows (ORM3 sample) | What it holds |
|---|---:|---|
| `schema_meta` | 1 | Schema version marker (key/value) |
| `files` | 820 | One row per indexed source file |
| `symbols` | 64732 | Every declared/defined code element (incl. params/locals at v14+) |
| `refs` | 231489 | Every reference (read/write/call/type-use/...) to a symbol |
| `call_edges` | 17911 | Resolved call-site -> target-symbol edges (subset of `refs`) |
| `unit_uses` | 13777 | Every `uses`-clause entry, resolved or not |
| `type_ancestors` | 1433 | Class/interface inheritance edges |
| `type_helpers` | 22 | Record/class helper -> target-type edges |
| `symbol_docs` | 4838 | Parsed XMLDoc/PasDoc/oneline doc comments per symbol |
| `di_bindings` | 540 | Spring4D `RegisterType<T>.Implements<I>` DI registrations |
| `string_literals` | 33899 | Every string literal, with owning symbol/file |
| `symbol_trigrams` | 535520 | Trigram inverted index for fuzzy symbol search |
| `string_fts*` (9 tables) | varies | SQLite FTS5 shadow tables backing `query --text` |
| `compiler_findings` | 0 (ORM3) | Ingested dcc32/dcc64/msbuild log findings |
| `fb_relations` | 0 (ORM3) | Live Firebird schema snapshot: tables |
| `fb_columns` | 0 (ORM3) | Live Firebird schema snapshot: columns |
| `fb_field_info` | 0 (ORM3) | Live Firebird `TFIELD` display/edit metadata snapshot |
| `fb_datasets` | 0 (ORM3) | Live Firebird dataset (`TFIBDataSet`-style) SQL snapshot |
| `fb_enum_values` | 0 (ORM3) | Live Firebird enum-domain value snapshot |
| `orm_links` | 0 (ORM3) | Cross-DB Delphi-symbol <-> SQL-symbol ORM link candidates |

Row counts marked "0 (ORM3)" are populated by optional ingest steps (compiler
log import, live Firebird connection snapshot, ORM link resolution) that were
not run against this particular sample DB; the tables always exist (created
by `CREATE TABLE IF NOT EXISTS` in the DDL) even when empty.

There is **no `params` or `local_vars` table.** As of v14 (D5), typed local
variables and parameters are stored as ordinary rows in `symbols` with
`kind = 'local_var'` / `kind = 'param'` respectively -- see section 2.2.

---

## 2. Core tables

### 2.1 `files`

One row per indexed source file (`.pas`, `.dfm`, `.sql`, or ingest-adjacent
`.json`/`.text` sources).

| Column | Type | Meaning |
|---|---|---|
| `id` | INTEGER PK | Referenced by `file_id` everywhere else |
| `path` | TEXT, UNIQUE | Full path as indexed (case as given on disk) |
| `mtime_unix` | INTEGER | File's mtime at parse time (staleness check) |
| `sha256` | TEXT | Content hash (staleness / dedupe) |
| `parsed_at` | INTEGER | Unix timestamp of the parse that produced this row |
| `language` | TEXT | Parser name for the file. Pascal source is `delphi13` (the `TDelphi13Parser.LanguageName`), NOT `pas`; DFM is `dfm`, SQL is `sql`, ingest sources are `json`/`text`. |
| `last_compiled_unix` | INTEGER (nullable, v16+) | Unix time of the last successful compile that covered this file; `NULL` = never compiled. A file is compiler-finding-STALE iff `last_compiled_unix IS NULL OR last_compiled_unix < mtime_unix`. Written by the `refresh-findings` verb. |

Join: every `file_id` foreign key elsewhere points here.

### 2.2 `symbols`

Every declared/defined code element: units, classes, interfaces, records,
enums (+ enum values), routines (procedure/function/method/constructor/
destructor), properties, fields, vars, consts, type aliases, forms,
components, SQL DDL objects (from `MS*.SQL` ingest), unit init/finalization
markers, and -- since v14 -- typed local variables and parameters.

| Column | Type | Meaning |
|---|---|---|
| `id` | INTEGER PK | Referenced by `symbol_id` everywhere else |
| `file_id` | INTEGER FK -> `files.id` | Declaring file |
| `parent_id` | INTEGER FK -> `symbols.id` | Enclosing symbol (e.g. a method's owning class; NULL at top level) |
| `kind` | TEXT | See value domain below |
| `name` | TEXT | Simple name |
| `qualified_name` | TEXT | `Unit.TType.Member`-style fully qualified name |
| `signature` | TEXT | Rendered signature (params + return type) for routines; may be blank for non-callables |
| `modifiers` | TEXT | Free-form modifier text (e.g. visibility/`virtual`/`override` markers as captured) |
| `section` | TEXT | `''` \| `'interface'` \| `'implementation'` (usable-from-other-units test; NOT the same value set as `unit_uses.section`) |
| `heritage` | TEXT (v11+) | Raw ancestor list text for class/interface symbols, e.g. `'TBar, IBaz'`; NULL for non-class/interface or no ancestors. Resolved into `type_ancestors` |
| `is_virtual` | INTEGER (v12+) | 1 when the method is virtually dispatched (`virtual`/`dynamic`/`override`), else 0/NULL |
| `start_line`/`start_col`/`end_line`/`end_col` | INTEGER | Declaration span |
| `impl_start_line`/`impl_end_line` | INTEGER (v9+) | Implementation body span (header..final `end`); 0/NULL when there is no body |
| `is_helper` | INTEGER (v15+) | 1 when this symbol is a record/class helper declaration (`... helper for T`) |
| `prop_access` | TEXT (v17+, nullable) | For a `property` symbol: `'ro'` (read-only accessor), `'rw'` (read+write), or `'wo'` (write-only) -- captured from that property's own `read`/`write` accessor clause at parse time. NULL for every non-property symbol, and for a property symbol whose OWN declaration carries no accessor clause (a bare redeclaration, e.g. `property Color;`) -- a consumer resolves that case via the nearest class ancestor's `prop_access` at query time (this is what the `proptree` verb's `is_writable` field does; the raw column is never denormalized/copied down). Also NULL on a `.sqlite` that has not been re-indexed since v17. |

**`kind` value domain** (exact strings written by the indexer; there is no
separate `kind_text` column -- `kind` IS the text form):
`unit`, `program`, `package`, `class`, `interface`, `record`, `enum`,
`enum_value`, `procedure`, `function`, `method`, `constructor`, `destructor`,
`property`, `field`, `var`, `const`, `type`, `form`, `component`, `sql_table`,
`sql_column`, `sql_index`, `sql_trigger`, `sql_generator`, `sql_procedure`,
`sql_view`, `sql_exception`, `sql_domain`, `sql_constraint`,
`initialization`, `finalization`, `local_var` (v14+), `param` (v14+).

There is **no `visibility` column.** Access-modifier / visibility
information, where captured, lives in the free-form `modifiers` text; there
is no normalized public/private/protected enum column at v15.

Join: `symbols.file_id -> files.id`; `symbols.parent_id -> symbols.id`
(self-join for containment, e.g. a method's `parent_id` is its class).

### 2.3 `refs`

One row per reference to a symbol (a read, write, call, type-use, etc. --
this is the "everywhere X is used" table, distinct from `call_edges` which
narrows to resolved calls only).

| Column | Type | Meaning |
|---|---|---|
| `id` | INTEGER PK | Referenced by `call_edges.ref_id` |
| `symbol_id` | INTEGER FK -> `symbols.id` (ON DELETE SET NULL) | The symbol being referenced, when resolved; NULL if the symbol was deleted/unresolved |
| `file_id` | INTEGER FK -> `files.id` | File the reference occurs in |
| `kind` | TEXT | See value domain below |
| `name_text` | TEXT | Verbatim identifier text at the reference site |
| `start_line`/`start_col`/`end_line`/`end_col` | INTEGER | Reference span |
| `enclosing_symbol_id` | INTEGER FK -> `symbols.id` (v13+, ON DELETE SET NULL) | The innermost routine whose implementation body contains this ref; NULL if the ref is not inside any routine body |

**`kind` value domain** (free-form string set at each call site in the
parser; no enum backs it): `type_use`, `call`, `di-resolve`, `di-unresolved`,
`read`, `write`, `attribute`, `event-binding` (the last is DFM/form-file
references specifically).

Join: `refs.symbol_id -> symbols.id`; `refs.file_id -> files.id`;
`refs.enclosing_symbol_id -> symbols.id`.

### 2.4 `call_edges`

One row per `refs` row that the resolver was able to pin to a concrete call
target. `ref_id` is the primary key, so a given ref resolves to at most one
edge (unlike `refs`, which includes every reference kind, not just calls).

| Column | Type | Meaning |
|---|---|---|
| `ref_id` | INTEGER PK, FK -> `refs.id` (ON DELETE CASCADE) | The call-site reference this edge resolves |
| `target_symbol_id` | INTEGER FK -> `symbols.id` (ON DELETE CASCADE) | The resolved call target |
| `confidence` | TEXT | `'certain'` (exactly one matching candidate) or `'ambiguous'` (more than one candidate on the type chain) |
| `receiver_type_symbol_id` | INTEGER FK -> `symbols.id` (ON DELETE SET NULL) | Statically known type of the call receiver, when available; used to disambiguate overloads/virtual dispatch |

Join: `call_edges.ref_id -> refs.id`; `call_edges.target_symbol_id ->
symbols.id`. To find "who calls symbol X", join `call_edges` ->
`target_symbol_id = X.id`, then `refs` on `ref_id` to get the call site's
file/line, then `refs.enclosing_symbol_id` to get the calling routine.

### 2.5 `unit_uses`

One row per entry in every `uses` clause across the codebase (one row per
`(file, section, unit_name)`). This is the table that answers "what does
file F use, and did it resolve to an indexed file."

| Column | Type | Meaning |
|---|---|---|
| `id` | INTEGER PK | |
| `file_id` | INTEGER FK -> `files.id` | The file containing this `uses` clause entry |
| `unit_name` | TEXT | Verbatim unit name as written (e.g. `System.SysUtils`) |
| `unit_name_norm` | TEXT | Lowercased trailing segment for join-friendly lookups (e.g. `sysutils`) |
| `section` | TEXT | `interface` \| `implementation` \| `program` \| `package` (distinct value set from `symbols.section` -- see 2.2) |
| `in_path` | TEXT | Text from an `in '...'` clause, if present; NULL otherwise |
| `target_file_id` | INTEGER FK -> `files.id` (ON DELETE SET NULL) | **See below -- this is the project/external boundary signal** |
| `start_line`/`start_col`/`end_line`/`end_col` | INTEGER | Span of the unit-name token in the `uses` clause |

**`target_file_id` is the key column for external-tool consumers:**
- **NULL / unresolved** -> the used unit was **not indexed** (its source
  file is not part of this database at all -- it is either genuinely
  external, e.g. a Windows API unit, or simply outside the indexed
  directory tree).
- **Non-NULL** -> a `files` row with that `id` exists in this same
  database. That does NOT automatically mean the unit is "project code" --
  see section 4: a resolved target can still be a library path (e.g. an
  Embarcadero RTL unit that happens to have been indexed too, such as a
  shared library-index DB).

Join: `unit_uses.file_id -> files.id` (the using file);
`unit_uses.target_file_id -> files.id` (the used file, when resolved).

### 2.6 `type_ancestors`

One row per direct heritage entry (one class/interface can have several,
e.g. `TFoo = class(TBar, IBaz)` produces two rows). Rebuilt from scratch each
resolve pass from `symbols.heritage`.

| Column | Type | Meaning |
|---|---|---|
| `symbol_id` | INTEGER FK -> `symbols.id` (ON DELETE CASCADE) | The class/interface symbol declaring this ancestor |
| `ordinal` | INTEGER | Position in the heritage list (0-based) |
| `ancestor_name` | TEXT | Verbatim ancestor name as written in the heritage clause |
| `ancestor_kind` | TEXT | Same value domain as `symbols.kind`, restricted to `class`/`interface` in practice |
| `ancestor_symbol_id` | INTEGER | Resolved ancestor's `symbols.id`; NULL when unresolved (external/RTL/by-name-only) |
| `ancestor_file_id` | INTEGER | File of the resolved ancestor, when resolved |

Join: `type_ancestors.symbol_id -> symbols.id`;
`type_ancestors.ancestor_symbol_id -> symbols.id` (NULL = unresolved, same
external-boundary idea as `unit_uses.target_file_id`).

### 2.7 `type_helpers`

One row per record/class helper declaration (`... helper for T`), linking
the helper to its target type. Added at v15; populated in the same resolve
pass as `type_ancestors`.

| Column | Type | Meaning |
|---|---|---|
| `helper_symbol_id` | INTEGER FK -> `symbols.id` (ON DELETE CASCADE) | The helper type's own symbol (also carries `is_helper = 1`) |
| `target_name` | TEXT | Verbatim target-type name from the `for` clause |
| `target_symbol_id` | INTEGER FK -> `symbols.id` (ON DELETE SET NULL) | Resolved target type's symbol; NULL when unresolved |
| `target_file_id` | INTEGER | File of the resolved target, when resolved |
| `helper_kind` | TEXT | Free-form (e.g. `record helper` / `class helper`, as captured) |

Join: `type_helpers.helper_symbol_id -> symbols.id`;
`type_helpers.target_symbol_id -> symbols.id`.

### 2.8 `symbol_docs`

One row per documented symbol (XMLDoc/DocInsight `///`, PasDoc, or one-line
comment forms), keyed 1:1 by `symbol_id`.

| Column | Type | Meaning |
|---|---|---|
| `symbol_id` | INTEGER PK, FK -> `symbols.id` (ON DELETE CASCADE) | The documented symbol |
| `format` | TEXT | `xmldoc` \| `pasdoc` \| `oneline` \| `loose` |
| `raw_block` | TEXT | Original comment text, verbatim, as fallback |
| `summary` | TEXT | Parsed `<summary>` (or equivalent) |
| `remarks` | TEXT | Parsed `<remarks>` |
| `returns_text` | TEXT | Parsed `<returns>` |
| `params_json` | TEXT | JSON array of parsed `<param name="...">` entries |
| `exceptions_json` | TEXT | JSON array of parsed `<exception cref="...">` entries |
| `example_text` | TEXT | Parsed `<example>`/similar |
| `seealso_json` | TEXT | JSON array of parsed `<seealso>` entries |
| `since_text` | TEXT | Parsed `<since>` (or equivalent) |
| `deprecated` | INTEGER | 1 when the doc marks the symbol deprecated |
| `start_line`/`end_line` | INTEGER | Span of the doc comment block itself |

Join: `symbol_docs.symbol_id -> symbols.id` (1:1; not every symbol has a row).

### 2.9 `di_bindings`

One row per resolved Spring4D `RegisterType<TImpl>.Implements<IIntf>`
registration.

| Column | Type | Meaning |
|---|---|---|
| `id` | INTEGER PK | |
| `file_id` | INTEGER FK -> `files.id` (ON DELETE CASCADE) | File containing the registration call |
| `interface_name` | TEXT | Verbatim interface name, including nested generics |
| `impl_name` | TEXT | Verbatim implementation class name |
| `lifetime` | TEXT | `singleton` \| `transient` \| `singleton-per-thread` |
| `start_line`/`start_col`/`end_line`/`end_col` | INTEGER | Span of the registration call |

Join: `di_bindings.file_id -> files.id`. There is no direct FK to `symbols`;
match `interface_name`/`impl_name` against `symbols.qualified_name`/`name`
if you need symbol-level linkage.

### 2.10 Firebird snapshot tables (`fb_*`) and `orm_links`

Optional Tier-2/Tier-3 tables populated by a live Firebird-connection
snapshot step and a subsequent ORM-link resolution step; all exist by
default (empty) even when those steps have not been run.

- **`fb_relations`** -- one row per Firebird table/view snapshotted
  (`name`, `owner`, `system_flag`, optional `sql_table_symbol_id` linking to
  a matched `symbols` row, `snapshot_at`).
- **`fb_columns`** -- one row per column of a snapshotted relation
  (`relation_id` FK -> `fb_relations.id`, `name`, `position`, Firebird field
  metadata: `field_type`/`field_length`/`field_scale`/`field_precision`/
  `nullable`/`default_value`, optional `sql_column_symbol_id`).
- **`fb_field_info`** -- Firebird `TFIELD`-style display/edit metadata
  snapshot (`display_label`, `display_format`, `edit_format`, `visible`,
  `read_only`, etc.), keyed by `field_name`/`table_name`.
- **`fb_datasets`** -- one row per snapshotted dataset definition (its
  `select_sql`/`update_sql`/`insert_sql`/`delete_sql`/`refresh_sql`, key
  field, update table name).
- **`fb_enum_values`** -- one row per Firebird enum-domain value
  (`enum_name`, `value_code`, `value_label`).
- **`orm_links`** -- cross-DB candidate links between a Delphi symbol and a
  SQL symbol (`delphi_symbol_id`/`delphi_db_index` and
  `sql_symbol_id`/`sql_db_index` are LOCAL ids into their respective `--db`
  stores in a multi-DB query, not globally unique; `confidence` REAL,
  `link_kind` e.g. `class_to_table`/`iface_to_table`/`field_to_column`).

These are specialist tables for Delphi<->SQL ORM tooling; most consumers
interested in "what code exists and how it's used" can ignore them.

### 2.11 `compiler_findings`

One row per finding extracted from an ingested `dcc32`/`dcc64`/`msbuild`
build log. `file_id` is set when the finding's path matched an indexed file
(else NULL, with the original text preserved in `raw_path`).

| Column | Type | Meaning |
|---|---|---|
| `id` | INTEGER PK | |
| `file_id` | INTEGER FK -> `files.id` (ON DELETE SET NULL) | Matched file, if any |
| `raw_path` | TEXT | Path exactly as it appeared in the build log |
| `code` | TEXT | Compiler message code (e.g. `E2003`, `H2077`) |
| `severity` | TEXT | As reported by the compiler (error/warning/hint) |
| `line_no`/`col_no` | INTEGER | Location in the source, if given |
| `message` | TEXT | Message text |
| `imported_at` | INTEGER | Unix timestamp of the log ingest |

### 2.12 `string_literals` and the FTS text tables

`string_literals` holds one row per string literal found in `.pas`/`.dfm`
(and `.sql`, subject to indexing convention) source, with owning
file/symbol and span. It backs `drag-lint query --text "<phrase>"`.

| Column | Type | Meaning |
|---|---|---|
| `id` | INTEGER PK | |
| `file_id` | INTEGER FK -> `files.id` (ON DELETE CASCADE) | |
| `symbol_id` | INTEGER FK -> `symbols.id` (ON DELETE SET NULL) | Owning symbol, when attributable |
| `source` | TEXT | Which kind of source file this literal came from (`pas`/`dfm`/`sql`) |
| `kind` | TEXT | Literal kind as captured (e.g. plain string literal vs. DFM caption) |
| `owner_name` | TEXT | Human-readable owner label (e.g. component/property name for a DFM caption) |
| `text` | TEXT | The literal's text content |
| `start_line`/`start_col`/`end_line`/`end_col` | INTEGER | Span |

The remaining text-search tables --
`string_fts`, `string_fts_config`, `string_fts_data`, `string_fts_docsize`,
`string_fts_idx`, `string_fts_tri`, `string_fts_tri_config`,
`string_fts_tri_data`, `string_fts_tri_docsize`, `string_fts_tri_idx` --
are **SQLite FTS5 virtual-table shadow tables** (an `fts5(unicode61)` index
and a parallel `fts5(trigram)` index, both `content='string_literals'`
external-content tables kept in sync by triggers on `string_literals`).
Do not query or write to these directly: `PRAGMA table_info` reports sparse/
untyped columns for them (SQLite manages their internal B-tree/segment
structure itself) and their row counts mirror `string_literals`' shape, not
independent data. Use the FTS5 `MATCH` query surface via
`drag-lint query --text "<phrase>" [--any-order] [--substring] [--source
pas|dfm|sql]` instead of hand-rolling SQL against them.

### 2.13 `symbol_trigrams`

Trigram inverted index over symbol names, populated lazily on first fuzzy
query for any DB missing it (so older `.sqlite` files upgrade transparently
without a forced full reindex).

| Column | Type | Meaning |
|---|---|---|
| `trigram` | TEXT | A 3-character slice of a symbol name (lowercased) |
| `symbol_id` | INTEGER FK -> `symbols.id` (ON DELETE CASCADE) | The symbol this trigram belongs to |

`PRIMARY KEY (trigram, symbol_id) WITHOUT ROWID`. This backs fuzzy
name-lookup fallback (`drag-lint query --name <approx>`); most consumers
should use the CLI query surface rather than querying this table directly.

### 2.14 `schema_meta`

Single-row-per-key metadata table.

| Column | Type | Meaning |
|---|---|---|
| `key` | TEXT PK | e.g. `schema_version` |
| `value` | TEXT | Its value (schema_version is stored as a stringified integer) |

This is the table to check first (see section 1).

---

## 3. Programmatic introspection

Do not hardcode a table/column list in a consuming tool if you can avoid it.
Run:
```
drag-lint schema --db <file.sqlite> --format json
```
which returns:
```json
{
  "schema_version": 16,
  "tables": [
    { "name": "files", "row_count": 820, "columns": [
      { "name": "id", "type": "INTEGER" },
      { "name": "path", "type": "TEXT" },
      ...
    ]},
    ...
  ]
}
```
This is generated live from `sqlite_master` + `PRAGMA table_info(<table>)` +
`SELECT COUNT(*)` for every table in the DB, opened strictly read-only (the
verb never calls `Migrate` and issues no DDL/INSERT/UPDATE) -- it is
guaranteed to match whatever the actual `.sqlite` file in front of you
contains, including any tables/columns this document has not yet been
updated to describe.

---

## 4. "Project" vs "external" -- the boundary rule

drag-lint deliberately has **no `is_external` boolean column anywhere**.
Whether a used unit counts as "part of the project" or "an external/library
dependency" is a judgment about a file PATH, not an intrinsic property
stored per-row -- so it is derived at query time rather than baked into the
schema. This keeps the schema stable across differing project layouts
(a shared library-index DB might contain both project and RTL files; a
project-only DB might have zero library files at all) instead of requiring
every consumer to agree on one definition up front.

**The rule, stated explicitly** (this is exactly what
`DRagLint.Report.Deps.IsLibraryPath` implements):

A path is a **library path** when its lowercased form contains any of:
`\embarcadero\`, `\program files`, or `\dcc\`.

Given a `unit_uses` row:
- If `target_file_id` is **NULL** (unresolved -- the unit was never
  indexed), the used unit is **external**.
- If `target_file_id` is **non-NULL**, look up the resulting `files.path`:
  - If that path is a **library path** (per the rule above) -> **external**.
  - Otherwise -> **in the project**.

The same resolved-vs-unresolved-vs-library-path logic applies to
`type_ancestors.ancestor_symbol_id`/`ancestor_file_id` and
`type_helpers.target_symbol_id`/`target_file_id`: a NULL resolved id means
the ancestor/helper-target type was not indexed (likely external); a
resolved id whose file is a library path is still external even though it
IS indexed.

### Use the ready-made consumer instead of reimplementing this

`drag-lint deps-report` already applies this exact rule and does the BFS/
rollup work for you -- classifying every external unit dependency, grouping
by RTL/DevExpress/Spring4D/FireDAC/other/unknown, and reporting per-external
"used by" project-unit lists plus the shortest import chain:
```
drag-lint deps-report --db <file.sqlite> [--db ...] [--depth N] [--edges]
  [--all-sources] [--name <pat>] [--format text|json|csv] [--output <file>]
```
Prefer this over re-deriving the boundary yourself unless you need a
different aggregation than it provides. If you do need to apply the rule
directly (e.g. inside your own SQL), the two functions to mirror are
`IsLibraryPath` (the exact substring test above) and `ClassifyDepsGroup`
(unit-name-prefix / resolved-path-based grouping), both in
`src/report/DRagLint.Report.Deps.pas`.

For introspecting the schema itself (rather than the dependency graph),
use `drag-lint schema` (section 3).
