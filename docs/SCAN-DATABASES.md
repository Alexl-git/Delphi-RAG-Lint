# drag-lint scan databases

The drag-lint scanner produces SQLite index files (one per scope). Each holds the
AST-exact symbols, references, uses-clauses, and docs for the code it covered.
They are read **immutable / read-only** by the CLI, the IDE plugin, and the graph
viewer (no `-wal`/`-shm` sidecars are created).

> **Paths below are examples from one development machine** (`C:\Projects\...`).
> Substitute your own project/library roots and DB locations -- there is
> nothing special about that drive layout. The GUI alternative to running
> `index`/`scan-all` by hand is the **Indexer** page under
> **Tools > Options > Third Party > drag-lint** (auto-index on open,
> auto-reindex on save, scan-libraries toggle, extra DB paths,
> auto-discover/include-library-DB toggles) -- see `docs/INSTALL.md`.

Schema: symbols (kind, name, qualified_name, signature, modifiers, **section**,
line/col), refs (`call` / `type_use` / `event-binding`, by name), **unit_uses**
(every uses-clause entry with section + resolved target file), symbol_docs.
As of the v0.41 scanner, symbols also include **`initialization` / `finalization`**
section markers per unit.

## Scan type and mode -- two independent axes

**Scan TYPE is declared by the target**, not chosen on the command line:

| Type | Declared by | Contains |
|---|---|---|
| **Project** | an `include` entry ending `.dpr` / `.dproj` | exactly the **compile closure**: the project's members + transitively-used project-local units + each unit's sibling `.dfm` + `{$I}` include files + the project file itself. Units on a Delphi **Library/Browsing** path are excluded (they belong to the library index); loose unreferenced files in the project folder are excluded. |
| **Library** | an `include` entry that is a **folder** (or `source: registry-libraries`) | every scannable file under the tree, subject to `exclude` / `includeOnly`. |

**MODE is chosen per run**, independently of type:

| Mode | Flag | Meaning |
|---|---|---|
| Recompile | `--recompile` (**default**) | incremental -- only files whose content hash changed are re-parsed, then the resolve passes re-run. |
| Rebuild | `--rebuild` | from scratch. A safety valve, not a correctness requirement: on the same input the two converge to identical content. |

## The current database set (this development machine)

**Since 2026-08-09 there is one DB per project.** They live under
`C:\Projects\.drag-lint\` and are named `<Repo>-<Project>.sqlite`.

| Database file | Scope / what it contains | Typical use |
|---|---|---|
| `C:\Projects\.drag-lint\ORM3-Micronite2027.sqlite` and seven siblings -- `ORM3-MicroniteMW1Service`, `ORM3-Interfaces`, `ORM3-TestMicroniteObjects`, `ORM3-MicroniteTests`, `ORM3-TestCachedUpdates`, `ORM3-PdfOcrImportTests`, `ORM3-TEST_uSetupDefaultsFrm` | The **Micronite ORM3** solution, one DB per `.dproj` compile closure. | Day-to-day ORM3 lookups; the graph viewer's main store. Cross-project questions need several `--db`. |
| `C:\Projects\.drag-lint\DragLint-Cli.sqlite` (+ `DragLint-Wizard`, `DragLint-Tests`, `DragLint-CorpusScan`) | drag-lint's **own** source, per project. | Self-index; replaces the deleted `Delphi-RAG-lint.sqlite`. |
| `C:\Projects\.drag-lint\TableTools-*.sqlite`, `OCRPDF-*.sqlite`, `DataCopy-*.sqlite`, `DragLintGraph-*.sqlite`, `Loader.sqlite`, `YADF*.sqlite` | The other repos, likewise one DB per project. | Replaces the deleted per-repo union DBs. |
| `C:\Projects\DB\SQL\drag-lint-sql.sqlite` | The **Firebird SQL** scripts under `C:\Projects\DB\SQL` (MS*.SQL): tables, columns, generators, triggers, procedures, views, exceptions, domains. | SQL DDL symbol search; SQL-side of cross-DB resolve. |
| `C:\Projects\.drag-lint\library-Win32.sqlite` / `library-Win64.sqlite` (and one per other registered platform) | The **RTL / VCL / DevExpress / Spring4D** library sources (everything on the Library/Browsing paths). | Resolving library types (e.g. `TObject`, `IInterface`, `TList`) for cross-DB jumps + hover. |

> **Deleted 2026-08-09 -- these files no longer exist**, and any document or
> script still naming them is stale: `C:\Projects\DB\ORM3\drag-lint.sqlite`
> (the ORM3 union DB), `Delphi-RAG-lint.sqlite`, `TableTools.sqlite`,
> `OCRPDF.sqlite`, `DataCopy.sqlite`, `Delphi-RAG-Lint-Graph.sqlite`,
> `M2022.sqlite`, `active-projects.sqlite`, `convrules-worktree.sqlite`,
> `library.sqlite`, `projects.sqlite`, `samples.sqlite`.

**Never guess a DB path -- ask the tool:**

```
drag-lint resolve-dbs --platform win64            REM every configured DB
drag-lint resolve-dbs --project C:\...\MyApp.dproj  REM the DB covering one project
drag-lint resolve-dbs --in C:\...\MyUnit.pas        REM the DB covering one file
```

## Which to pass to the viewer

```
drag_lint_graph.exe --db C:\Projects\.drag-lint\ORM3-Micronite2027.sqlite ^
                    --db C:\Projects\.drag-lint\library-Win64.sqlite
```

The first `--db` is the primary store; additional `--db` stores back it for
cross-DB type resolution (clicking a library type jumps into the library store).

## Rebuilding

Scanner exe: `drag-lint.exe` (this example machine keeps a Win64 build under
`third_party\dll-win64\` -- prefer Win64 for large DBs; it handles the
~1.4 GB whole-tree index without the Win32 build's OOM ceiling). One scope
per command:

```
drag-lint index C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj --db C:\Projects\.drag-lint\ORM3-Micronite2027.sqlite
drag-lint index C:\Projects\DB\SQL  --db C:\Projects\DB\SQL\drag-lint-sql.sqlite
drag-lint index --scan-libraries-win --db C:\Projects\.drag-lint\library-Win64.sqlite
REM  ...use --scan-libraries-all instead to also pull in Posix/iOS/Android/OSX source trees.
REM  (--scan-libraries is kept as a back-compat alias for --scan-libraries-win.)
```

A `.dproj`/`.dpr` target is a **project** scan (compile closure); a folder target
is a **library** scan (whole tree). Add `--rebuild` to force a from-scratch pass;
the default is `--recompile` (incremental).

Or drive all of the above from a single **named-index manifest**
(`drag-lint.json`, with `settings` + `indexes` sections) instead of one
command per scope:

```
drag-lint index --all              # build every configured index
drag-lint index --all --dry-run    # show the plan + timings only
drag-lint index --all --only <Sec1,Sec2>   # rebuild just named indexes
drag-lint index --all --jobs <n>           # parallelize
drag-lint index --all --platform win32|win64   # pick the library set
```

See `docs/INSTALL.md` section 3c for the manifest format.

Rebuild order matters for usability: the project DBs (seconds to ~1 min each)
and SQL (~10 s) finish fast; the library scan (~1 h per platform) is the long
pole. `index --all --jobs 0` parallelizes across sections.

> While a rebuild runs, the target `.sqlite` is deleted and recreated. If the
> graph viewer has that exact DB open, close it first so the file can be
> replaced, then reopen when the scope's "=== ... done ===" line appears in the log.
