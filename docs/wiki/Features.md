# Features

Everything drag-lint does, grouped. Counts on this page were taken from the
running build (`drag-lint rules --json`), not written by hand.

Three surfaces expose these: the **CLI** (`drag-lint <verb>`), the **RAD Studio
plugin** (see [IDE Menu Reference](IDE-Menu-Reference)), and the **language
server** (`drag-lint lsp`).

---

## Indexing

The foundation. Everything below that says *(index)* reads what this produces.

| Feature | Command |
|---|---|
| Index a folder tree | `index <path>` |
| Index a project's **compile closure** -- members, transitively used units, sibling `.dfm`, `{$I}` includes | `index --project <file.dproj>` |
| Index the Delphi **Library + Browsing paths** for a platform | `index --scan-libraries-win`, `--scan-libraries-all` |
| Index everything in the manifest, optionally one section | `index --all [--only <Sections>]` |
| Incremental (default) vs full rebuild | `--recompile` / `--rebuild` |
| Re-parse everything after an engine upgrade | `--force-reparse` |
| Prune + evict files that left the disk or the scope | automatic; `--no-prune` for a dry look |
| Watch mode | `--watch [--interval N]` |
| Parallel walking | `--jobs <n>` |
| Cross-index resolution -- consult another index for calls this one cannot resolve | `--library-db <lib.sqlite>` |
| Per-file resume -- an interrupted walk continues where it stopped | automatic |
| Preprocessing -- per-config `{$IFDEF}` resolution before parsing | on by default; `--no-preprocess` |
| Show which databases a target resolves to | `resolve-dbs` |
| Schema inspection / migration | `schema`, `migrate-dbs` |

## Search and navigation *(index)*

| Feature | Command |
|---|---|
| Find a symbol by name or qualified name | `query --name` / `--qname` |
| **Text search over string literals** -- string constants, resourcestrings, DFM captions, SQL exception messages | `query --text "<phrase>"` |
| Who calls this | `query find-callers` (`--resolved` for precise call edges) |
| What does this call | `find-callees` |
| Class / interface ancestry, transitively | `query ancestors` |
| Resolve a type category (class, interface, float, string, ...) | `query typecat` |
| Type of the expression at a cursor position | `typeat <file>:<line>:<col>` |
| Find by documentation state | `query find --doc-tag / --no-docs` |
| Class helpers of a type | `helpers-of` |
| Shortest call path between two symbols | `call-path --from --to` |
| Symbol slice, class surface, context bundle | `slice`, `surface`, `context` |
| Hover card | `hover` |
| Which unit declares this symbol (and add it to `uses`) | `find-unit` |

## Linting

**173 rules. 22 have an auto-fix. 149 are on by default.**
119 are built-in checks; 54 are external tree-sitter `.scm` rules you can read
and extend in `rules\`.

Run `drag-lint rules` for the always-current catalogue, or
`drag-lint rules --category <name>`.

| Category | Rules | With auto-fix |
|---|---:|---:|
| bug-patterns | 51 | 5 |
| dead-code | 12 | 6 |
| complexity | 11 | - |
| refactoring | 11 | - |
| naming | 10 | 8 |
| platform | 10 | - |
| project-wide | 10 | - |
| security | 10 | - |
| data-flow | 9 | - |
| metrics | 8 | - |
| resource-lifetime | 8 | 1 |
| structure | 7 | - |
| other | 6 | - |
| documentation | 5 | 2 |
| firedac | 3 | - |
| review-markers | 2 | - |
| **Total** | **173** | **22** |

Scopes:

| Feature | Command |
|---|---|
| One file (no index needed) | `lint <path>` |
| A whole project -- adds project-wide rules, class metrics, duplicate code, documentation drift | `lint-all` |
| Project-wide rules only | `lint-project` |
| Restrict the report to one project's compile closure | `lint-all --project <.dproj>` |
| Machine-readable output | `--json`, and SARIF |
| Apply the fixable subset | `lint-all --fix` |

Suppression:

* `// drag-lint:ignore [rule-id ...]` -- silence a line.
* `// dl:ok <rule-id>@<hash> -- reason` -- a **reviewed marker**: it carries a
  hash of the line's code tokens and **re-reports itself if the code changes**,
  so a review cannot outlive the code it reviewed. Reindentation and case
  changes do not invalidate it.

## Documentation

DocInsight (`///` XML) comments, generated from the index rather than from
guesswork.

| Feature | Command |
|---|---|
| Document one symbol, a unit, a project, or everything | `document --qname / --unit / --project`, `document-all` |
| Stubs only, or fully populated facts | `--stubs` |
| Managed fact blocks -- callers, callees, used-in-units, raises, returns, wiring, see-also | automatic |
| Detect documentation that no longer matches the code | `doc-drift`, and the `doc-drift` lint rule |
| Strip generated blocks | `document --unit --strip` |
| Generate a doc comment for a symbol | `generate-docs` |
| Shared-unit markers, so several projects can document one unit without fighting | `shared-unit` |

## Refactoring and code generation

| Feature | Command |
|---|---|
| Rename a symbol or a parameter, index-wide | `rename` |
| Extract a method | `extract-method` |
| Safe delete (refuses when still referenced) | `safe-delete` |
| Add the missing unit for an undeclared identifier | `find-unit --apply` |
| Audit and fix `uses` clauses -- interface->implementation moves, unused units, **compiler-verified** | `uses-audit`, `uses-fix` |
| Reconcile project members against disk | `reconcile-project` |
| Generate an enum helper (`ToString`, parse, ...) | `create-enum-helper` |
| Generate a DUnitX / DUnit test stub | `generate-test` |
| Record a reviewed finding | `allow` |

## Component conversion

Rule-driven migration of legacy component types (for example Orpheus `TOvc*` to
DevExpress `cx`/`dx`).

| Feature | Command |
|---|---|
| Property/event assignability engine over the type tree | `proptree` |
| Scaffold a conversion rule from a real from/to pair | `convert-scaffold` |
| Validate a rulebook | `convert-validate` |
| Apply rules to a unit and its DFM | `convert-apply` |
| Visual rulebook editor | `ConvRulesEditor.exe` |

## Graphs and reports

| Feature | Command |
|---|---|
| Call graph, either direction, to a depth | `callgraph`, `reverse-calltree` |
| Butterfly view (callers + callees of one symbol) | `butterfly` |
| Dependency report | `deps-report`, `uses-report` |
| Uses cycles | `cycles` |
| Impact / blast radius of a change | `impact` |
| Dead code | `find-deadcode` |
| Top symbols by fan-in | `top` |
| TODO / FIXME scan | `todos` |
| Spring4D DI + DFM event wiring | `wiring` |
| Form hierarchy CSV for test helpers | `forms-csv` |
| Export to DOT / Mermaid / Obsidian / Delphi consts | `export`, `--format dot\|mermaid` |
| Interactive graph viewer | `drag_lint_graph.exe`, dockable in the IDE |

## Compiler integration

| Feature | Command |
|---|---|
| Compile a project or unit and fold the errors into findings | `compile-check`, `check-unit` |
| Compile the **unsaved editor buffer** ("ghost check") | IDE menu |
| Refresh stored compiler findings across a project | `refresh-findings` |
| Import an external build log | `import-log` |
| Preprocessor profile for a project/config | `pp-profile`, `preprocess-file` |

## Database and Firebird

| Feature | Command |
|---|---|
| Index `.sql` migration scripts, including `CREATE EXCEPTION` messages | `index` |
| Snapshot a live Firebird schema into an index | `fb-snapshot` |
| Link ORM classes to tables and fields to columns | `link-orm` |

## Editor integration

| Feature | How |
|---|---|
| **RAD Studio plugin** -- ~50 menu items, hover, dockable panel and graph | `dclDragLintWizard.bpl`; see [IDE Menu Reference](IDE-Menu-Reference) |
| **Language server** over stdio -- hover, go-to-definition, **find-references**, **workspace symbols**, completion, signature help | `drag-lint lsp` |
| VS Code extension | `editors\vscode\drag-lint\` |
| Neovim / Helix / any LSP client | point it at `drag-lint lsp` |
| HTTP/MCP server for agents | `serve` |
| Multi-project workspaces | `workspace add / index / status` |

## Maintenance and diagnostics

| Feature | Command |
|---|---|
| Which databases cover what | `resolve-dbs`, `info` |
| Library path drift after a third-party update | `library-drift` |
| Per-phase timing breakdown | `DRAGLINT_PROFILE=1` |
| Ambiguous call diagnosis | `ambiguous-calls` |
| Raw dumps for debugging | `dump-refs`, `dump-call-edges` |
| Index schema report | `schema` |

---

*Counts verified against v1.4.0-alpha. `drag-lint rules` is always the
authority -- this page can lag the catalogue.*
