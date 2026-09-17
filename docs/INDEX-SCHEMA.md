# drag-lint index database schema (reference for external consumers)

This document describes the SQLite database that `drag-lint index` produces --
a durable, queryable index of a Delphi/Pascal codebase (symbols, references,
uses-clauses, type ancestry, DI bindings, and more). It is written for anyone
building a tool OTHER than drag-lint itself that wants to read this database
directly.

Current schema version at time of writing: **23** (`SCHEMA_VERSION` in
`src/storage/DRagLint.Storage.Schema.pas`, verified 2026-09-17 against the
constant AND against the guard fixture index `run_generic_symbol_names.ps1`
builds -- previously this line had only ever been checked against the
constant). Recent additive changes:
**v23 added `symbols.generic_params` and `type_ancestors.ancestor_type_args`**
-- a generic type or method is now indexed under its BARE name with the
parameter list in its own column, and an ancestor edge carries the
instantiation's arguments (see 2.2 and 2.6);
**v21 added `refs.external_target`** -- the qualified name of a call target that
lives outside this DB, so a cross-database call stops looking like an unresolved
one (see 2.3); **v20 added `refs.receiver_text`** -- the call-site receiver
verbatim, so an unresolved call can still say what it hung off (2.3);
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
- `19 -> 20`: additive column `refs.receiver_text` -- the call-site receiver
  verbatim, so an unresolved call can still say what it hung off (see 2.3).
- `20 -> 21`: additive column `refs.external_target` -- the qualified name of a
  call target that lives outside this DB, so a cross-database call stops looking
  like an unresolved one (see 2.3).
- `21 -> 22`: additive columns `symbols.directives` (every routine directive,
  canonical lowercase, declaration order, space-joined) and
  `symbols.vis_explicit` (was a visibility keyword actually written for this
  member's section). Riding the same extractor bump: the DFM extractor now emits
  a `dfm-prop` row for EVERY value kind, not only string-valued properties, so
  colours, sets, numbers and booleans became text-searchable.
- `22 -> 23`: additive columns `symbols.generic_params` (the generic parameter
  list as written, `T: class` / `K, V`; NULL for a non-generic symbol) and
  `type_ancestors.ancestor_type_args` (the type arguments written on a heritage
  entry, `TFoo` in `class(TObjectList<TFoo>)`; NULL when named without
  arguments). **Behaviour change riding the extractor bump: `symbols.name` and
  `qualified_name` of a generic are now BARE** (`TList`, not `TList<T>`), and
  ancestor resolution filters candidates by arity before any scope rule -- a
  pre-v23 row still carries the list in its name until the next re-parse. A
  consumer that matched `name LIKE '%<%'` finds nothing on a v23 index; read
  `generic_params` instead. **This is the current version.**

All facts in this document were cross-checked against the DDL in
`src/storage/DRagLint.Storage.SQLite.pas` and
`src/storage/DRagLint.Storage.Schema.pas`, and against a live index:
**the `Micronite2027` CLIENT project index, re-indexed 2026-09-09 under
extractor 1.14.0-alpha** (`schema_version = 21`, verified both via
`drag-lint schema --db <path> --format text` and a direct read-only
`SELECT value FROM schema_meta` -- the two agree). The row counts in the
"Table of tables" below are from that sample.

**The sample is ONE PROJECT index, not an estate-wide total**, which matters for
reading the counts: it is a single Delphi application (707 files), so
`di_bindings` is 4 rather than the hundreds a server-side project shows, and the
`fb_*` / `compiler_findings` / `orm_links` tables are empty because their
optional ingest steps were not run against it. Counts drift with every reindex
-- always introspect a specific `.sqlite` live (see below) rather than trusting
these numbers. What is stable is the SHAPE: the table and column set for a given
`schema_version`.

New columns/tables are migration-safe: `CREATE TABLE IF NOT EXISTS` +
`ALTER TABLE ... ADD COLUMN` run on open, and the version gate is a `>=` check,
so a DB indexed by an OLDER engine simply lacks the newer table/columns (facts
read as absent, never wrong) until it is re-indexed with a current engine.

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

| Table | Rows (Micronite2027, v21 2026-09-09) | What it holds |
|---|---:|---|
| `schema_meta` | 5 | Version, fingerprints and scan type (key/value) -- see 2.14 |
| `files` | 707 | One row per indexed source file |
| `symbols` | 91423 | Every declared/defined code element (incl. params/locals at v14+) |
| `refs` | 543882 | Every reference (read/write/call/type-use/...) to a symbol |
| `call_edges` | 33113 | Resolved call-site -> target-symbol edges (subset of `refs`) |
| `unit_uses` | 10619 | Every `uses`-clause entry, resolved or not |
| `type_ancestors` | 1132 | Class/interface inheritance edges |
| `type_helpers` | 22 | Record/class helper -> target-type edges |
| `symbol_docs` | 4577 | Parsed XMLDoc/PasDoc/oneline doc comments per symbol |
| `symbol_facts` | 15905 | Per-routine analysis facts (complexity, reads/writes, SQL tables, DFM event, ownership; v19 adds mutated params, UI affinity, external surfaces, wiring) -- v18+; see 2.15 |
| `di_bindings` | 4 | Spring4D `RegisterType<T>.Implements<I>` DI registrations |
| `string_literals` | 98915 | Every string literal AND comment, with owning symbol/file |
| `symbol_trigrams` | 713676 | Trigram inverted index for fuzzy symbol search |
| `string_fts*` (10 tables) | varies | SQLite FTS5 shadow tables backing `query --text` -- two indexes (`string_fts` unicode61 + `string_fts_tri` trigram), five shadow tables each |
| `compiler_findings` | 0 (sample) | Ingested dcc32/dcc64/msbuild log findings |
| `fb_relations` | 0 (sample) | Live Firebird schema snapshot: tables |
| `fb_columns` | 0 (sample) | Live Firebird schema snapshot: columns |
| `fb_field_info` | 0 (sample) | Live Firebird `TFIELD` display/edit metadata snapshot |
| `fb_datasets` | 0 (sample) | Live Firebird dataset (`TFIBDataSet`-style) SQL snapshot |
| `fb_enum_values` | 0 (sample) | Live Firebird enum-domain value snapshot |
| `orm_links` | 0 (sample) | Cross-DB Delphi-symbol <-> SQL-symbol ORM link candidates |

Row counts marked "0 (sample)" are populated by optional ingest steps (compiler
log import, live Firebird connection snapshot, ORM link resolution) that were
not run against this particular sample DB; the tables always exist (created
by `CREATE TABLE IF NOT EXISTS` in the DDL) even when empty.

Note on `string_literals`: the table name understates it. It is the **searchable
text index**, and holds far more than quoted strings -- comment prose, doc
comments and DFM content all live here, separated by the `kind` column. That is
why its row count is large relative to the file count, and it is what lets
`query --text` find a phrase in a doc-comment or a DFM caption rather than only
in a string literal. Observed `kind` values in the sample:

| `kind` | Rows | What it is |
|---|---:|---|
| `literal` | 29023 | An ordinary quoted string in code |
| `doc` | 25629 | A `///` documentation comment |
| `comment` | 21111 | A `//`, `{ }` or `(* *)` comment |
| `dfm-prop` | 8926 | A property VALUE from a `.dfm` (captions, hints, SQL text) |
| `dfm-type` | 7084 | The component TYPE on a `.dfm` `object` line -- how you find every form holding a `TOvcTable` |
| `const` | 4595 | A declared string constant |
| `format` | 2491 | A `Format()` format string |
| `resourcestring` | 56 | A `resourcestring` declaration |

Filter on it with `query --text <phrase> --kind <kind>`, and note the boundary
this makes explicit: `--kind literal` returns only genuine string literals, so
code written against the pre-comment behaviour keeps working unchanged.

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
| `modifiers` | TEXT | The member's VISIBILITY word -- `private` / `strict private` / `protected` / `public` / `published` -- plus a mirrored ` message` for a message handler. NOT directives: it never held `virtual`/`override` markers, despite what this row claimed until v22. Four consumers equality-match it as the visibility word, which is why v22 put directives in their own column rather than here. |
| `directives` | TEXT | v22. Every routine directive, canonical lowercase, in declaration order, space-joined (`virtual overload stdcall`); `external` included. `'` when the routine declares none, and `'` for non-routine symbols. NULL only on a row written by a pre-v22 index. |
| `vis_explicit` | INTEGER | v22. 1 when a visibility keyword was written for this member's section, 0 for the unlabelled leading section of a class or record -- which under `$M+` is PUBLISHED while `modifiers` says `public` for both. NULL on a pre-v22 row, read back as 1. |
| `generic_params` | TEXT | v23. The generic parameter list exactly as written between `<` and `>` -- `T`, `K, V`, `T: class`, `I: IMicObject` -- for a generic class/interface/record/procedural type or a generic method. NULL (read back as `''`) for a non-generic symbol. `name` and `qualified_name` are BARE for a generic; the display form is `name<generic_params>`. Arity = the number of top-level comma-separated entries. |
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
| `receiver_text` | TEXT (v20+) | The call-site RECEIVER, verbatim as written left of the dot -- `''` for an unqualified call. What lets an unresolved call still say what it hung off. **`NULL` means "pre-v20 DB, never resolved by a v20 engine"**, which is a different claim from `''`; read it with `FindField`, not `FieldByName`, so an older DB yields `''` rather than raising |
| `external_target` | TEXT (v21+) | The qualified NAME of a call target that lives OUTSIDE this database -- the cross-DB case, where `symbol_id` cannot be filled because the symbol is not in this index at all. Without it an RTL/VCL call is indistinguishable from an unresolved one |

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
| `ancestor_name` | TEXT | Ancestor name as written in the heritage clause, WITHOUT any type-argument list (v23: `TObjectList` for `class(TObjectList<TFoo>)`; the list moves to `ancestor_type_args`) |
| `ancestor_type_args` | TEXT | v23. The type arguments written on this heritage entry (`TFoo`, `T`, `string, TBar`); NULL when the ancestor was named without arguments. Resolution prefers a candidate whose `generic_params` arity equals this list's arity; an argument-less edge keeps the pre-v23 behaviour. |
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

### 2.8 `member_accesses`

One row per `member-access` ref that names a PROPERTY or FIELD (2026-09-16,
resolver 1.3.0-alpha). Written by the calls resolve pass beside
`refs.symbol_id` (which points at the member) and cleared with `call_edges`.
The owner's ruling it encodes: a property READ is also a call to its read
accessor, a WRITE a call to its write accessor; a FIELD-backed accessor is a
read/write use of that field.

| Column | Type | Meaning |
|---|---|---|
| `ref_id` | INTEGER PK FK -> `refs.id` (ON DELETE CASCADE) | The access site |
| `member_symbol_id` | INTEGER FK -> `symbols.id` (ON DELETE CASCADE) | The property or field the source named |
| `mode` | TEXT | `read` or `write` (`:=` after the name, past any `[...]` indexer, is a write) |
| `accessor_symbol_id` | INTEGER FK -> `symbols.id` (ON DELETE SET NULL) | The getter/setter the mode resolves to; NULL when the declaration names none this resolver could find (absent clause, a dotted path, an unresolved name) |
| `accessor_kind` | TEXT | `method` (the ref ALSO owns a `call_edges` row targeting it -- `call_edges` stays routine-only) or `field` (no edge; the readers UNION this table in) |
| `receiver_type_symbol_id` | INTEGER FK -> `symbols.id` (ON DELETE SET NULL) | The type the receiver was typed to |

ADDITIVE: created by `Migrate` on any open, no `SCHEMA_VERSION` bump. Every
reader probes for it (`HasMemberAccesses`) and a not-yet-migrated DB answers as
before. Readers: `FindReferencesTo` (field-backed uses), `FindResolvedCallers`
(member and field-backed rows, with `mode`), `GetReferencedSymbolIds`.

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

`string_literals` holds one row per indexed TEXT SPAN in `.pas`/`.dfm` (and
`.sql`, subject to indexing convention) source, with owning file/symbol and
span. It backs `drag-lint query --text "<phrase>"`.

**THE TABLE NAME UNDERSTATES IT, AND HAS SINCE THE COMMENT CORPUS LANDED.** It
is no longer "one row per string literal": as of the 2026-09-08 extractor it
also holds **comment prose** (`//`, brace, paren-star) and **doc comments**
(`///`), and the TYPE token on a DFM `object` line. A consumer that reads the
name literally and filters on the assumption that every row is a quoted string
will silently mis-scope its results. Discriminate with `kind`, never with the
table name.

| Column | Type | Meaning |
|---|---|---|
| `id` | INTEGER PK | |
| `file_id` | INTEGER FK -> `files.id` (ON DELETE CASCADE) | |
| `symbol_id` | INTEGER FK -> `symbols.id` (ON DELETE SET NULL) | Owning symbol, when attributable |
| `source` | TEXT | Which kind of source file this literal came from (`pas`/`dfm`/`sql`) |
| `kind` | TEXT | Which KIND of text span this row is -- see the value domain below. This is the column that separates a quoted string from comment prose, and the only reliable way to scope a `--text` query |
| `owner_name` | TEXT | Human-readable owner label (e.g. component/property name for a DFM caption) |
| `text` | TEXT | The literal's text content |
| `start_line`/`start_col`/`end_line`/`end_col` | INTEGER | Span |

**`kind` value domain** (free-form string set at each emit site; no enum backs
it -- these are the values the current extractor writes):

| `kind` | `source` | What it is |
|---|---|---|
| `literal` | `pas` | An ordinary quoted string literal |
| `const` | `pas` | A declared constant's string value |
| `resourcestring` | `pas` | A `resourcestring` value |
| `format` | `pas` | A format string |
| `comment` | `pas` | **Comment prose** -- `//`, brace and paren-star comments |
| `doc` | `pas` | A `///` documentation comment |
| `dfm-prop` | `dfm` | A DFM property VALUE (captions, hints, ...) and component names |
| `dfm-type` | `dfm` | The TYPE on a DFM `object` line -- what answers "which forms hold a component of type X, and how many" |
| `sql-exception` | `sql` | A `CREATE EXCEPTION` message |

Filter with `--kind` on the query surface: `--kind literal` restores exactly what
`--text` returned BEFORE comments were indexed, `--kind comment` hunts prose,
`--kind dfm-type` enumerates component instances. Empty means no filter, which
is the default and returns everything.

Two caveats a consumer will otherwise hit:

* **Comment prose dominates the row count and barely moves the file size.**
  Measured 2026-09-08: comment text is ~96.6% of indexed text spans and grows
  the TEXT CORPUS ~29x, but the DATABASE by only ~1.5%. Sizing a DB from the
  row count of this table will be wrong by more than an order of magnitude.
* `sql-exception` messages are harvested from `MS*.sql` files by default (a
  migration-script convention); `--no-sql-ms` indexes every `.sql`.

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
pas|dfm|sql] [--kind <kind>] [--limit N]` instead of hand-rolling SQL against
them.

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

This is the table to check first (see section 1). The keys a current index
carries, read from the 2026-09-09 sample:

| `key` | Example value | Meaning |
|---|---|---|
| `schema_version` | `21` | The structural contract this document describes. Check it before reading anything else. |
| `indexer_fingerprint` | `v=1.14.0-alpha;schema=21;pp=1;plat=win64` | What PRODUCED the stored parses: extractor version, schema, preprocessor flag, platform. The engine re-parses a file when this no longer matches, so a consumer can use it to tell whether an index predates an extractor change. |
| `resolver_fingerprint` | `r=1.1.0-alpha;schema=21` | What produced the DERIVED edges (`call_edges`, `type_ancestors`, `type_helpers`, resolved `unit_uses`). Deliberately separate: when only this is stale the remedy is `index --resolve-only`, which re-derives edges from parses the index already holds instead of re-parsing anything. |
| `scan_type` | `project` or `library` | Which KIND of index this is -- a project's compile closure, or a folder/library tree. This is what makes a membership question answerable: in a `project` index a hit IS membership, and a miss IS non-membership. |
| `indexed_at_unix` | `1788972499` | When the index was last written, seconds since the Unix epoch. |

**Do not infer freshness from `indexed_at_unix` alone.** It says when the index
was written, not whether the files it describes have changed since. Compare the
fingerprints for "was this built by the current engine", and the per-file
`files.mtime_unix` / `files.sha256` columns for "has this file changed".
`files.indexed_at_fingerprint` records the fingerprint each individual file was
indexed under, which is what makes an incremental reindex able to re-parse only
the files an engine change actually invalidated.

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
