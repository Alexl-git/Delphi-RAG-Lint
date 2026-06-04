# drag-lint scan databases

The drag-lint scanner produces SQLite index files (one per scope). Each holds the
AST-exact symbols, references, uses-clauses, and docs for the code it covered.
They are read **immutable / read-only** by the CLI, the IDE plugin, and the graph
viewer (no `-wal`/`-shm` sidecars are created).

Schema: symbols (kind, name, qualified_name, signature, modifiers, **section**,
line/col), refs (`call` / `type_use` / `event-binding`, by name), **unit_uses**
(every uses-clause entry with section + resolved target file), symbol_docs.
As of the v0.41 scanner, symbols also include **`initialization` / `finalization`**
section markers per unit.

| Database file | Scope / what it contains | Approx size | Typical use |
|---|---|---|---|
| `C:\Projects\DB\ORM3\drag-lint.sqlite` | The **Micronite ORM3** project only (CLIENT + SERVER + COMMON + PACKAGE + COMMON\OBJECTS). ~810 files, ~50k symbols. | ~33 MB | Day-to-day ORM3 lookups; the graph viewer's main store. |
| `C:\Projects\DB\SQL\drag-lint-sql.sqlite` | The **Firebird SQL** scripts under `C:\Projects\DB\SQL` (MS*.SQL): tables, columns, generators, triggers, procedures, views, exceptions, domains. | ~16 MB | SQL DDL symbol search; SQL-side of cross-DB resolve. |
| `C:\Projects\Delphi-RAG-lint\third_party\dll-win32\drag-lint-library.sqlite` | The **RTL / VCL / DevExpress / Spring4D** library sources (everything on the scan-libraries path). ~1.57M symbols. | ~1.1 GB | Resolving library types (e.g. `TObject`, `IInterface`, `TList`) for cross-DB jumps + hover. |
| `C:\Projects\drag-lint-all.sqlite` | The **entire `C:\Projects` tree** in one index (every project's source; `__history` / `.git` / `node_modules` backups excluded). ~43k files, ~2.4M symbols. | ~1.4 GB | Cross-project "where is X anywhere" searches; the broadest store. The slowest to rebuild (several hours). |

## Which to pass to the viewer

```
drag_lint_graph.exe --db C:\Projects\DB\ORM3\drag-lint.sqlite ^
                    --db C:\Projects\Delphi-RAG-lint\third_party\dll-win32\drag-lint-library.sqlite
```

The first `--db` is the primary store; additional `--db` stores back it for
cross-DB type resolution (clicking a library type jumps into the library store).

## Rebuilding

Scanner exe: `C:\Projects\Delphi-RAG-lint\third_party\dll\drag-lint.exe` (Win32).
One scope per command:

```
drag-lint index C:\Projects\DB\ORM3 --db C:\Projects\DB\ORM3\drag-lint.sqlite
drag-lint index C:\Projects\DB\SQL  --db C:\Projects\DB\SQL\drag-lint-sql.sqlite
drag-lint index --scan-libraries    --db C:\Projects\Delphi-RAG-lint\third_party\dll-win32\drag-lint-library.sqlite
drag-lint index C:\Projects         --db C:\Projects\drag-lint-all.sqlite
```

Rebuild order matters for usability: ORM3 (~1 min) and SQL (~10 s) finish fast;
the library (~1 h) and especially the whole-tree `drag-lint-all` (several hours)
are the long poles. The convenience script `C:\TEMP1\reindex-initfin.sh` runs all
four in that order and logs to `C:\TEMP1\reindex-initfin.log`.

> While a rebuild runs, the target `.sqlite` is deleted and recreated. If the
> graph viewer has that exact DB open, close it first so the file can be
> replaced, then reopen when the scope's "=== ... done ===" line appears in the log.
