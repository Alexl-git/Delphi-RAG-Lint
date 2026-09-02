# drag-lint index database schema (reference for external consumers)

This document describes the SQLite database that `drag-lint index` produces --
a durable, queryable index of a Delphi/Pascal codebase (symbols, references,
uses-clauses, type ancestry, DI bindings, and more). It is written for anyone
building a tool OTHER than drag-lint itself that wants to read this database
directly.

Current schema version at time of writing: **19** (`SCHEMA_VERSION` in
`src/storage/DRagLint.Storage.Schema.pas`). Recent additive changes:
v16 added the column `files.last_compiled_unix` (compiler-finding freshness;
see 2.1); v17 added `symbols.prop_access` (property-leaf assignability engine;
see 2.2); **v18 added the new `symbol_facts` table** -- per-routine analysis
facts (cyclomatic complexity + body LOC, own-field reads/writes, SQL tables
touched, paired-`.dfm` event wiring, returned-object ownership) surfaced by the
`document` managed block and `hover`; see 2.15; **v19 added four additive
columns to `symbol_facts`** (`mutates_params`, `ui_affinity`, `touches`,
`wiring`) -- see 2.15.

Schema history, one line per step:

- `17 -> 18`: new `symbol_facts` table.
- `18 -> 19`: four additive `symbol_facts` columns; the `>=` gate is unchanged;
  **`symbols.id` is reassigned by the full reindex** -- re-resolve by
  `qualified_name`, never by a cached id.

All facts in this document were cross-checked against the DDL in
`src/storage/DRagLint.Storage.SQLite.pas` and
`src/storage/DRagLint.Storage.Schema.pas`, and against a live index
(the ORM3 union DB `C:\Projects\DB\ORM3\drag-lint.sqlite`, retired and deleted
2026-08-09 in favour of one DB per project) **re-indexed with the v18 engine on
2026-07-23** (`schema_version = 18`, verified both via `drag-lint schema --db
<path> --format text` and a direct read-only `SELECT value FROM schema_meta
WHERE key='schema_version'` -- the two agree). The row counts in the "Table of
tables" below are from that 2026-07-23 v18 sample (836 files / 74151 symbols /
382358 refs). Counts drift as the codebase grows and every project/library DB
was re-indexed to v18 in the same pass -- always introspect a specific
`.sqlite` live (see below) rather than trusting these numbers.

New columns/tables are migration-safe: `CREATE TABLE IF NOT EXISTS` +
`ALTER TABLE ... ADD COLUMN` run on open, and the version gate is a `>=` check,
so a DB indexed by an OLDER engine simply lacks the newer table/columns (facts
read as absent, never wrong) until it is re-indexed with the v18 engine.

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

| Table | Rows (ORM3, v18 2026-07-23) | What it holds |
|---|---:|---|
| `schema_meta` | 1 | Schema version marker (key/value) |
| `files` | 836 | One row per indexed source file |
| `symbols` | 74151 | Every declared/defined code element (incl. params/locals at v14+) |
| `refs` | 382358 | Every reference (read/write/call/type-use/...) to a symbol |
| `call_edges` | 18801 | Resolved call-site -> target-symbol edges (subset of `refs`) |
| `unit_uses` | 14223 | Every `uses`-clause entry, resolved or not |
| `type_ancestors` | 1443 | Class/interface inheritance edges |
| `type_helpers` | 22 | Record/class helper -> target-type edges |
| `symbol_docs` | 4789 | Parsed XMLDoc/PasDoc/oneline doc comments per symbol |
| `symbol_facts` | 13267 | Per-routine analysis facts (complexity, reads/writes, SQL tables, DFM event, ownership; v19 adds mutated params, UI affinity, external surfaces, wiring) -- v18+; see 2.15 |
| `di_bindings` | 540 | Spring4D `RegisterType<T>.Implements<I>` DI registrations |
| `string_literals` | 40276 | Every string literal, with owning symbol/file |
| `symbol_trigrams` | 649557 | Trigram inverted index for fuzzy symbol search |
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
| `symbol_id` | INTEGER FK -> `symbols.id` (ON DELETE SET NULL) | The symbol being referenced, when the resolver is CERTAIN which one it is. Populated for `call` and `member-access` refs only -- see the note under the join list below |
| `file_id` | INTEGER FK -> `files.id` | File the reference occurs in |
| `kind` | TEXT | See value domain below |
| `name_text` | TEXT | Verbatim identifier text at the reference site |
| `start_line`/`start_col`/`end_line`/`end_col` | INTEGER | Reference span |
| `enclosing_symbol_id` | INTEGER FK -> `symbols.id` (v13+, ON DELETE SET NULL) | The innermost routine whose implementation body contains this ref; NULL if the ref is not inside any routine body |

**`kind` value domain** (free-form string set at each call site in the
parser; no enum backs it): `attribute`, `call`, `di-resolve`, `di-unresolved`,
`event-binding`, `member-access`, `read`, `sql_table_ref`, `type_use`, `write`.

`event-binding` is DFM/form-file references specifically; `sql_table_ref` comes
from the SQL parser; `member-access` is a dotted access, which since v20b is
also part of the universe `ResolveCallTargets` walks (see the block comment
above `REF_KIND_CALL` in `DRagLint.Core.Model.pas`).

Because no enum backs this column, **adding an `EmitRef` kind means adding it
here AND to `ColumnSemantics` in `DRagLint.CLI.pas`** -- `drag-lint schema`
declares this domain to consumers, and `tests\autotest\run_schema_semantics.ps1`
compares that declaration against a live `SELECT DISTINCT`. Both drifted before
2026-09-02, when the declaration listed only the five Pascal-expression kinds
and omitted everything the DFM, DI and SQL extractors emit. `symbols.kind` is
not exposed to this hazard: it is derived from `TSymbolKind`.

Join: `refs.symbol_id -> symbols.id`; `refs.file_id -> files.id`;
`refs.enclosing_symbol_id -> symbols.id`.

> **`refs.symbol_id` IS PARTIAL, AND THE PART MATTERS.** It was NULL on every
> row of every index until 2026-08-31 -- 0 of 543,482 on ORM3 CLIENT, all eight
> `kind` values -- while the join above was documented as though it worked.
> `ResolveCallTargets` now writes it from the same resolution that produces a
> call edge.
>
> **Only a CERTAIN edge earns one.** An ambiguous edge means the resolver found
> several plausible targets and declined to choose; writing one of them here
> would launder a guess into a fact, and the column's entire value is that a
> non-NULL means *this IS the declaration*.
>
> **Only `call` and `member-access` refs have one at all.** `read`, `write` and
> `type_use` are still NULL: the resolver knows a call's target because it is
> already computing it, but resolving the others is a new problem, not a
> write-back. Measured on this repo's own index: call 5,880 of 30,739,
> member-access 1,713 of 27,594, everything else 0.
>
> **So a NULL still means "not resolved", never "no such symbol"**, and a query
> that must cover every ref still has to name-join. The other identity columns
> remain the broader answer: `refs.receiver_text` (what a qualified ref hangs
> off, ~18% of rows) and `refs.enclosing_symbol_id` (which routine a bare ref
> sits in, ~91%).
>
> Writing this column is a RESOLVE-pass change, so it is stamped by
> `schema_meta.resolver_fingerprint`: an index built before it re-derives its
> edges on the next `index` run rather than keeping the old ones silently.

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

### 2.15 `symbol_facts`

Per-routine **analysis facts** (schema v18+), one row per documentable routine
symbol, keyed by `symbol_id`. Materialized at INDEX time by the facts analyzer
for routine kinds that have a body (`function` / `procedure` / `method` /
`constructor` / `destructor`); other symbol kinds get no row. Each fact is a
pure function of the routine's own identity + body (+ its paired `.dfm` for
`dfm_event`), so it is deterministic and reproducible. Rows are invalidated
automatically by `ON DELETE CASCADE` -- a routine's fact row dies when its
`symbols` row is replaced on the next per-file reindex. These facts back the
managed `<!-- drag-lint:auto -->` block emitted by `document` and the `hover`
popup (a single shared formatter renders both, so they cannot drift).

| Column | Type | Meaning |
|---|---|---|
| `symbol_id` | INTEGER PK, FK -> `symbols(id)` ON DELETE CASCADE | The routine this fact row describes. |
| `reads_fields` | TEXT (nullable) | CSV of the routine's OWN-CLASS instance fields it READS (first-occurrence order, capped at 8 with a trailing ` (+N more)`). NULL when none. Own-class only -- inherited fields are not tracked. |
| `writes_fields` | TEXT (nullable) | CSV of own-class instance fields it WRITES (assignment LHS + `Inc`/`Dec` targets), same cap/format. NULL when none. `var`/`out`-parameter writes are NOT detected (a field passed to a var param counts as a read). |
| `returns_owner` | TEXT (nullable) | Conservative returned-object ownership verdict: `new` (constructor result -- caller owns), `borrowed` (returns an own-field/param it does not own), or `self`. Emitted ONLY when every return site agrees unanimously; any mixed/unknown case -> NULL (absence over a wrong fact). NULL for non-object returns. |
| `cyclomatic` | INTEGER (nullable) | Cyclomatic complexity = 1 + count of decision points (`if` / `while` / `for` / `repeat` / `case` arms / `and` / `or`). Shared with the complexity lint rule. |
| `body_loc` | INTEGER (nullable) | Implementation body line count (`impl_end_line - impl_start_line`, clamped >= 0). |
| `dfm_event` | TEXT (nullable) | For a published method wired to a component event in the routine's PAIRED `.dfm`: `'ObjectName.EventProp'` (e.g. `Button1.OnClick`). NULL when not wired / no sibling `.dfm`. |
| `sql_reads` | TEXT (nullable) | CSV of SQL tables the routine READS (`FROM`/`JOIN`), best-effort from concatenated SQL string literals in the body; capped at 8. Dynamic / sub-query / CTE SQL is skipped (absence over a wrong table). NULL when none. |
| `sql_writes` | TEXT (nullable) | CSV of SQL tables WRITTEN (`INSERT INTO` / `UPDATE` / `DELETE FROM`), same best-effort/format. NULL when none. |
| `mutates_params` | TEXT (nullable) | **v19.** CSV of the `var`/`out` PARAMETERS the routine writes through, display-ready with each mode in parentheses -- `'pList (var), pReason (out)'`. Same cap/format as `reads_fields` (8 entries, then ` (+N more)`). Closes the gap named in `writes_fields` above. Claimed write shapes: a bare-identifier assignment LHS, an indexed LHS (`AList[0] := X`), and `Inc`/`Dec`. NOT claimed, by design: an ordinary call's var argument (`SetLength(AList, N)`) and a dot LHS (`AObj.F := X`). NULL when none. |
| `ui_affinity` | TEXT (nullable) | **v19.** CSV of the UI controls/globals the routine touches -- `'cxGrid1, Application'`. A field/local/parameter whose declared type is, or descends from, a curated VCL/DevExpress base type, plus bare `Application`/`Screen`. **POSITIVE FINDINGS ONLY:** NULL means "no UI touch was detected", NEVER "this routine is thread-safe" -- the curated list under-reports by construction. |
| `touches` | TEXT (nullable) | **v19.** External surfaces and transaction verbs, as CATEGORIES not call sites, in ONE column with a **`|` separator**: `'<resources>|<transactions>'`, e.g. `'file system, registry|starts, commits'`. Either side may be empty and the separator is still present (`'file system|'`, `'|starts, commits'`); NULL when both are. Resource words: `file system`, `registry`, `network`. Transaction words: `starts`, `commits`, `rolls back`. Both sides are emitted in that fixed order, never discovery order. |
| `wiring` | TEXT (nullable) | **v19, RESERVED / currently unpopulated** -- same status as `covered_by` below and for the same class of reason. The DI/ORM wiring fact is computed LAZILY at `document`/`hover` time by joining `di_bindings` / `orm_links` / `fb_relations` / `fb_columns`, because `orm_links` is written by a SEPARATE post-index pass (`orm-link`): an index-time value would be empty on every first index and would afterwards reference `symbols.id` values the reindex had already replaced. Rendered shape, for reference: `'di:IFolderService (singleton); ds:qryFolders -> FOLDERS (ID, NAME)'`. Do not rely on this column being filled. |
| `covered_by` | TEXT (nullable) | **RESERVED / currently unpopulated.** The "Covered by (tests)" fact is computed LAZILY at `document`/`hover` time from the live reverse-call graph (a test->routine edge is non-deterministic to persist per-file at index time), so the current engine leaves this column NULL. Do not rely on it being filled. |

Consumers: this table is purely additive -- pre-v18 tools that do not read it
are unaffected. A `.sqlite` produced by a pre-v18 engine has NO `symbol_facts`
table at all (the `>=` version gate + `CREATE TABLE IF NOT EXISTS` mean it
appears, empty, on the first v18 reindex). Treat a missing table or a NULL
column as "fact not available", never as a negative assertion.

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
