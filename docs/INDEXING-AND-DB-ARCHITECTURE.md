# drag-lint indexing & database architecture

**Applies to:** drag-lint **1.1.0-alpha** · index **schema_version 17** ·
tree-sitter grammars delphi13 **14** / dfm **14**.
Verified 2026-07-15 against the live ORM3 index (`C:\Projects\DB\ORM3\drag-lint.sqlite`,
schema 16, 29 tables) and the engine at
`third_party\dll-win64\drag-lint.exe`; schema **v17** (`symbols.prop_access`,
see §6) verified 2026-07-20 against `SCHEMA_VERSION` in
`src/storage/DRagLint.Storage.Schema.pas` and the shipped exe's CLI usage
output -- the ORM3 sample DB above has not yet been re-indexed past v16, so
it still reads `prop_access = NULL`.

> **Version note.** This document explains *how indexing works and how the DBs
> fit together*. The per-table column reference lives in
> [INDEX-SCHEMA.md](INDEX-SCHEMA.md). If `drag-lint info` reports a **schema
> version above 17** or a **grammar version above 14**, treat the details below
> as possibly stale and re-verify with `drag-lint schema --db <file> --format json`
> and `drag-lint info --json` before trusting them -- then refresh this doc's
> header stamp. The stability contract (additive columns, `schema_meta` first) is
> in INDEX-SCHEMA.md section 1.

---

## 1. The big picture

drag-lint turns a Delphi/Pascal tree into **one SQLite file per logical
codebase** ("a DB"). Everything else -- query, LSP hover/go-to-def, lint,
call-graph, RAG context bundles -- is a *read* over one or more of those files.
The write path is owned exclusively by `drag-lint index`.

```
  source tree (.pas/.dpr/.dpk/.dfm/.sql)
        |
        v   tree-sitter parse (delphi13 / dfm grammars)  +  resolve passes
        |
  ┌─────────────────────┐        ┌──────────────────────────────────────┐
  │  drag-lint index     │  ───►  │  <name>.sqlite  (schema_version 17)  │
  │  (the ONLY writer)   │        │  symbols·refs·call_edges·unit_uses·  │
  └─────────────────────┘        │  type_ancestors·di_bindings·FTS·...  │
                                  └──────────────────────────────────────┘
        ▲                                        │  read-only
        │ manifest picks which trees             ▼
   drag-lint.json (named-DB config)      query · lsp · serve · lint · graph
```

Key properties:

- **One file, portable.** A DB is a single `.sqlite`. Copy it, ship it, open it
  read-only from any SQLite tool. Consumers must **never write** it.
- **Incremental.** Re-indexing a path updates only the files whose content hash
  changed, then re-runs the resolve passes (call-edge resolution, FTS trigger
  maintenance). A full rescan is rarely needed.
- **Multi-DB by design.** A machine holds many DBs (one per project + shared
  library DBs). The *manifest* decides which trees map to which DB; *consumers*
  auto-select the right set per platform.

---

## 2. What "indexing" actually does

`drag-lint index <path>` walks the tree and, per file:

1. **Parse** with the tree-sitter delphi13 grammar (`.pas/.dpr/.dpk`) or the dfm
   grammar (`.dfm`). SQL (`.sql`) has its own lighter path.
2. **Extract symbols** -- every declared/defined element: units, types,
   methods, properties, fields, consts, enum values, and (schema v14+) params
   and locals. Stored in `symbols`. Since schema v17, a `property` symbol also
   stamps `prop_access` (`ro`/`rw`/`wo`) captured from its own `read`/`write`
   accessor clause -- see §6.
3. **Extract references** -- every read/write/call/type-use of a symbol, into
   `refs`. Call sites that resolve to a target become `call_edges`.
4. **Extract structure** -- `unit_uses` (every uses-clause entry),
   `type_ancestors` (class/interface inheritance), `type_helpers` (record/class
   helpers), `di_bindings` (Spring4D registrations), `symbol_docs` (DocInsight
   XML comments).
5. **Extract text** -- string/message/caption/SQL-exception literals into
   `string_literals` + the **FTS5** tables (unicode61 + trigram), powering
   `query --text`. Also `symbol_trigrams` for fuzzy name search.
6. **Compiler findings** (optional) -- `compiler_findings` holds dcc/msbuild
   errors/warnings/hints per file, kept fresh by `refresh-findings` (see §5).

After the per-file pass, **resolve passes** run across the whole DB to turn
name-based refs into resolved `call_edges` and to attribute refs to their
enclosing symbol. This is why a partial re-index still re-resolves edges.

### Indexing commands (the common ones)

| Command | Purpose |
|---|---|
| `index <path> [--db F]` | Index a directory/file into DB `F` (incremental). |
| `index --project <x.dproj> [--db F]` | Index exactly a project's members. |
| `index --all [--only S1,S2] [--platform p] [--jobs n]` | Index every manifest section (or just the named ones). `--jobs 0` = all cores. |
| `index --all --dry-run [--json]` | Preview what would be indexed -- no writes. |
| `index --scan-libraries-win` | Index the RTL/VCL/DevExpress **library** paths (Win32+Win64). |
| `index --watch [--interval N]` | Re-index on file change (long-running). |
| `purge-locals --db F` | Size escape hatch: drop params/locals + VACUUM (call graph unchanged; re-inflated next index). |

---

## 3. The manifest: `drag-lint.json`

A machine's DBs are described by a **named-DB manifest**. On this box it lives
beside the engine: `third_party\dll-win64\drag-lint.json` (a copy also sits at
`C:\Projects\.drag-lint.json`, loaded as defaults). Shape:

```jsonc
{
  "settings": {
    "currentProjectsIndexing": "perProject",   // one DB per project
    "defaultPlatform": "Win32",
    "sizeGuardMB": 1500,                        // refuse to build a DB larger than this
    "enginePath": "auto",
    "maxJobs": 0
  },
  "indexes": {
    "outDir": "C:\\Projects\\.drag-lint",       // where non-absolute DBs land
    "exclude": ["*BACKUP*", "*_OLD*.pas", "* - Copy.pas", "Win64"],
    "sections": [
      { "name": "ORM3", "db": "C:\\Projects\\DB\\ORM3\\drag-lint.sqlite",
        "include": ["C:\\Projects\\DB\\ORM3"], "useIgnoreFiles": true },
      { "name": "SQL",  "db": "C:\\Projects\\DB\\SQL\\drag-lint-sql.sqlite",
        "include": ["C:\\Projects\\DB\\SQL"], "includeOnly": ["MS*.SQL"] },
      { "name": "DragLint", "db": "Delphi-RAG-lint.sqlite",
        "include": ["C:\\Projects\\Delphi-RAG-lint"] },
      { "name": "Library", "source": "registry-libraries",
        "platforms": ["Win32", "Win64"], "db": "library-{platform}.sqlite" }
      /* ...Loader, TableTools, OCRPDF, DragLintGraph... */
    ]
  }
}
```

- Each **section** maps a set of source roots (`include`, optionally filtered by
  `includeOnly`) to **one DB**. A DB path may be absolute or relative to
  `outDir`.
- `exclude` globs drop backup/copy/other-platform noise everywhere.
- The `Library` section is special: `source: registry-libraries` reads the RAD
  Studio Library/Browsing paths from the registry, and `{platform}` templating
  produces one DB per platform (`library-Win32.sqlite`, `library-Win64.sqlite`).
- `index --all` builds every section; `--only ORM3,SQL` builds a subset.

---

## 4. How consumers pick DBs (`resolve-dbs`)

Query/LSP/serve/graph do **not** hardcode a DB. When you don't pass `--db`, they
call the same resolver the manifest drives, filtered by platform. To see exactly
what they'd use:

```
drag-lint resolve-dbs --platform win64
```

On this box (win64) that yields, in order: the ORM3 project DB, the SQL DB, the
per-project DBs under `.drag-lint\` (Loader, TableTools, Delphi-RAG-lint,
DragLintGraph, OCRPDF), and the **Win64 library** DB. A consumer merges results
across all of them, so a symbol defined in the RTL resolves even when you query
from a project unit. You can still force a specific set with repeated `--db`.

**"Project" vs "external" boundary:** a DB is "yours" (project) if it was built
from your source roots; the library DB is "external". Some rules and reports use
this distinction (e.g. dead-code only within project DBs). See INDEX-SCHEMA.md
section 4 for the exact rule.

---

## 5. Compiler findings & freshness (schema v16)

`compiler_findings` stores dcc/msbuild diagnostics per file so the IDE gutter and
any consumer can show real compiler errors/warnings/hints -- not just the
tree-sitter lint. Freshness is tracked by **`files.last_compiled_unix`** (added
in schema v16).

- `refresh-findings --project <x> --db <F> [--full]` recompiles stale units
  (or ALL units with `--full`), clears+rewrites their `compiler_findings`, and
  stamps `last_compiled_unix`. `>=2` stale files -> full build; `1` ->
  incremental; `0` -> no-op.
- The IDE plugin spawns this on save/idle and via the **Full Compile Sweep**
  menu (which now auto-refreshes the open file's display when the sweep
  finishes -- 2026-07-15).
- **Which DB gets written matters:** the sweep must target the *same primary DB
  the LSP reads from* (the manifest-first project DB), not a per-project side
  DB. The plugin resolves this via `ResolveActiveIndexDbs[0]`.

---

## 6. Property-leaf assignability (schema v17)

`symbols.prop_access` (`'ro'` \| `'rw'` \| `'wo'`; NULL for non-properties and
for a bare property redeclaration that carries no own accessor clause)
records each property's real accessor shape, captured from its `read`/`write`
clause at parse time. Additive + migration-safe like every prior bump: an
existing `.sqlite` gets the column via `ALTER TABLE` on its next open and
reads `prop_access = NULL` until the file is actually re-indexed. Full column
reference: [INDEX-SCHEMA.md](INDEX-SCHEMA.md) section 2.2.

This is what powers the **proptree assignability engine**:

- `proptree`'s JSON output is now schema `proptree/2` -- additive over
  `proptree/1` -- with per-leaf `is_writable`, `visibility`, and
  `member_kind` (all default to today's back-compat values when absent, e.g.
  reading an un-re-indexed DB), plus a class-accurate concrete `type`. A new
  `proptree --min-visibility published|public` flag filters the emitted
  leaves by effective visibility (unset = all leaves, matching `proptree/1`).
- `convert-scaffold --surface dfm|pas` (default `dfm`) uses those same
  per-leaf fields to restrict auto-`#link` TARGETS to leaves that are
  genuinely assignable on that surface (read-only never auto-linked; `dfm`
  additionally requires the DFM-streamable published-property bar, `pas`
  relaxes to published+public including fields).

Field-by-field semantics, defaults, and worked examples:
[CONVERSION-RULES.md](CONVERSION-RULES.md).

---

## 7. Reading the DB directly (don't reinvent the reader)

- **Always check the version first:**
  `SELECT value FROM schema_meta WHERE key='schema_version';`
- **Introspect live, don't hardcode columns:**
  `drag-lint schema --db <F> --format json` walks `sqlite_master` +
  `PRAGMA table_info` + row counts -- it can never drift from the actual file.
- **Prefer the ready-made consumer** (`query`, `context`, `reverse-calltree`,
  `query --text`) over hand-rolled SQL: the resolve semantics (call-edge
  confidence, enclosing-symbol attribution, FTS tokenization) are non-trivial.
- Full column reference: **[INDEX-SCHEMA.md](INDEX-SCHEMA.md)**.

---

## 8. Operational quick reference

| I want to... | Do this |
|---|---|
| See engine + schema + grammar versions | `drag-lint info` (add `--json`) |
| Dump a DB's real structure | `drag-lint schema --db <F> --format text` |
| Rebuild all indexes | `drag-lint index --all --jobs 0` |
| Preview what would be indexed | `drag-lint index --all --dry-run` |
| Rebuild just one project's DB | `drag-lint index --all --only <Section>` |
| Reindex a changed folder incrementally | `drag-lint index <changedDir> --db <F>` |
| See which DBs a query will use | `drag-lint resolve-dbs --platform <p>` |
| Refresh compiler findings | `drag-lint refresh-findings --project <x> --db <F> [--full]` |
| Shrink an oversized DB | `drag-lint purge-locals --db <F>` |

> If a reindex errors "used by another process", an orphaned `drag-lint.exe` /
> `drag_lint_graph.exe` (or a running LSP) is holding the DB -- stop it first.
