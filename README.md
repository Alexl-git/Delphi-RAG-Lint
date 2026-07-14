# drag-lint

[![Release](https://img.shields.io/github/v/release/Alexl-git/Delphi-RAG-Lint?include_prereleases)](https://github.com/Alexl-git/Delphi-RAG-Lint/releases)
[![License](https://img.shields.io/github/license/Alexl-git/Delphi-RAG-Lint)](LICENSE)

> **⚠️ Alpha / work in progress.** This is an early alpha under active, daily
> development — expect rough edges, unfinished corners, and breaking changes
> between versions. It is shared early so the Delphi community can try it and
> shape it. **Feedback and suggestions are very welcome** — please open an
> [Issue](https://github.com/Alexl-git/Delphi-RAG-Lint/issues) with ideas, bugs,
> or "I wish it could…". Not yet recommended for unattended/production use.

A symbol-aware retrieval + lint + refactoring + IDE-integration tool for Delphi.
Pure Object Pascal at runtime -- no Python, Node, or Rust. No cloud AI.

**Use it as:** CLI tool &middot; LSP server (Zed / VS Code) &middot; MCP server (Claude / Cursor) &middot; RAD Studio 13 plugin.

**→ Driving it from an AI agent? See [docs/AI-USAGE.md](docs/AI-USAGE.md)** — copy-paste instructions so your AI uses drag-lint over CLI or MCP (and reads ~10-60x fewer tokens than opening whole units).

Built on [`tree-sitter-delphi13`](https://github.com/Alexl-git/tree-sitter-delphi13)
(sibling project) and a vendored Pascal binding for libtree-sitter.

**Companion:** [`Delphi-RAG-Lint-Graph`](https://github.com/Alexl-git/Delphi-RAG-Lint-Graph)
— a standalone VCL viewer (Win64) that turns this index into an interactive symbol
graph: UML class boxes, a **Code Flow View** that renders your DocInsight comments,
a **Where-Used** caller list, search with Back/Forward history, and **editor-sync**
(the graph follows the active unit in RAD Studio). Click-to-jump back into the IDE.

---

## Screenshots

### Out-of-process compiler intelligence, inside the IDE
Live diagnostics come from compiling your buffer in a **spawned** process — even
unsaved code — so the IDE never freezes. The Structure panel and a dockable code
graph sit beside the editor.

![drag-lint live diagnostics in RAD Studio with a docked code graph](docs/Images/IDE_Out_of_process_compilation.png)

### Your DocInsight `///` comments, in Help Insight
`<summary>` and `<remarks>` render natively in the IDE's Help Insight tooltip.

![A DocInsight doc-comment shown in the IDE Help Insight tooltip](docs/Images/IDE_DOCInsight.png)

### Code Flow View
Trace a routine's calls as a flowchart — each box carries its DocInsight summary
(here `TCompileChecker.Run`).

![Code Flow View of TCompileChecker.Run with DocInsight summaries on each box](docs/Images/Graph_Calls_out.png)

### UML class view, with doc on hover
Search a type to see its members (visibility glyphs + full signatures); hover a
member for its DocInsight doc.

![UML class box for TCompileChecker with a member doc tooltip](docs/Images/Graph_Find.png)

### Where Used
A precise, clickable list of a symbol's callers — 7 callers of
`ResolveActiveIndexDbs` — beside its unit's call graph.

![Where-Used caller list for ResolveActiveIndexDbs in the graph viewer](docs/Images/Graph_Who_uses.png)

### AST-exact symbol query (CLI)
`drag-lint query --name TCompileChecker --json` returns every match with kind,
qualified name, section, file and precise line/impl ranges — no comment or
string-literal noise.

![drag-lint query --json output for TCompileChecker](docs/Images/DRAG-Lint.exe_query_example1.png)

### Find callers, with source context (CLI)
`drag-lint query find-callers` lists every caller (7 here) with the surrounding
source lines.

![drag-lint find-callers output with code context](docs/Images/DRAG-Lint.exe_query_example2_Find_Callers.png)

### Semantic compile-check from the CLI
`drag-lint check-unit` compiles a unit in its project's context and reports
findings (here: clean).

![drag-lint check-unit clean result](docs/Images/DRAG-Lint.exe_query_example2.png)

---

## Quick start

### Standalone CLI

1. Download the [latest release](https://github.com/Alexl-git/Delphi-RAG-Lint/releases)
   (`drag-lint.exe` + `tree-sitter*.dll`).
2. Put them in the same directory.
3. Index a Delphi project:
   ```
   drag-lint index C:\Projects\MyApp --db myapp.sqlite
   ```
4. Query symbols:
   ```
   drag-lint query --name TFoo --db myapp.sqlite
   drag-lint surface --qname Unit.TFoo --db myapp.sqlite
   drag-lint impact --qname Unit.TFoo.DoBar --db myapp.sqlite
   ```

### Indexing the Delphi RTL/VCL libraries

To build one index over everything Delphi itself knows about - the IDE's
**Library** and **Browsing** search paths, read straight from the registry,
deduplicated, with `$(BDS)` / `$(Platform)` macros expanded - use the
`--scan-libraries-*` flags (no project or path needed):

```
drag-lint index --scan-libraries-win --db Library.sqlite   # Win32 + Win64 (default)
drag-lint index --scan-libraries-all --db Library.sqlite   # every registered platform
```

- **`--scan-libraries-win`** covers the IDE's native targets (Win32 + Win64).
  Because the RTL / VCL / FMX `.pas` source is shared across platforms, this
  already captures essentially all library source. (`--scan-libraries` is kept
  as a back-compat alias for this.)
- **`--scan-libraries-all`** enumerates **every** platform subkey under
  `...\BDS\37.0\Library` (Android*, iOS*, Linux64, OSX*, Win64x, ...). On top of
  the Win set it pulls in the platform-specific source trees - `source\rtl\posix`,
  `source\rtl\ios`, `posix\osx` - so symbols like `Posix.*`, `iOSapi.*`,
  `Macapi.*` and `Androidapi.*` resolve too.

Both probe HKCU + HKLM in both the 32- and 64-bit registry views and fold the
results into a single deduplicated folder set. Add `--dry-run` to print the
resolved folder list without indexing.

### I installed new 3rd-party components. How to rebuild the library index

When you install a new third-party package (DevExpress, TMS, Raize, Async
Professional, ...), its component installer registers its source/DCU folders on
the IDE's **Library** and **Browsing** search paths. The library index does
**not** update itself - it is a snapshot of those paths from the last scan, so
symbols from the new components stay unresolved until you rebuild it.

**1. Confirm what's missing (optional but quick).** `library-drift` lists every
registry root that is not yet in the index and exits non-zero if there's drift -
run it right after installing to see the new folders:

```
drag-lint library-drift                       # active platform
drag-lint library-drift --platform win64      # a specific platform
```

Any `MISSING: <path>` line is a component folder the current index doesn't cover.

**2. Rebuild the library index.** Pick whichever matches how your indexes are
managed:

- **This repo's managed indexes (recommended here).** The `Library` section of
  the named-DB manifest (`third_party/dll-win64/drag-lint.json`) has
  `"source": "registry-libraries"` and rebuilds both platform DBs
  (`C:\Projects\.drag-lint\library-Win32.sqlite` /
  `library-Win64.sqlite`) straight from the registry. Rebuild **only** that
  section - no need to touch the project indexes:

  ```
  drag-lint index --all --only Library            # both platforms, from the manifest
  drag-lint index --all --only Library --dry-run  # preview: prints the two target DBs first
  ```

- **A standalone library DB (no manifest).** Re-run the same `--scan-libraries-*`
  scan that first built it, pointing at the same `--db` file (it is rebuilt in
  place):

  ```
  drag-lint index --scan-libraries-win --db Library.sqlite   # Win32 + Win64
  drag-lint index --scan-libraries-all --db Library.sqlite   # every registered platform
  ```

**3. Verify.** Re-run `library-drift` - it should now report **0 missing** (exit
0). If a folder still shows as `MISSING`, the component didn't register that path
on the IDE search paths; add it under **Tools -> Options -> Language -> Delphi ->
Library** (Library or Browsing path) for the right platform, then rebuild again.

Notes:

- **Close nothing / rebuild anytime** - this is a CLI (`.exe`) scan; RAD Studio
  can stay open. If the target `.sqlite` is locked, an orphaned `drag-lint.exe`
  is holding it - stop that process (not the IDE) and retry.
- **After rebuilding, restart the IDE plugin's LSP** (or reopen the project) so
  the running plugin picks up the refreshed `library-*.sqlite`. The CLI sees the
  new DB immediately.
- The scan reads the RTL/VCL/FMX and third-party **source** paths; components
  shipped as DCU-only still resolve for uses/dependency purposes but won't have
  browsable source bodies.

### Untangling unit dependencies (cycles + uses cleanup)

Find circular unit dependencies and the exact `uses` lines that form them:

```
drag-lint cycles --db myapp.sqlite --edges
```

Each cycle lists its `A uses B [interface|implementation]` edges, marks the
**interface** edges as move-to-implementation candidates, and flags layering
inversions (e.g. a COMMON unit reaching into CLIENT). Add **`--causes`** to
pinpoint the *specific symbols* in `A`'s interface that force the dependency on
`B` (the types/vars/methods to move or extract) — with the line numbers, and an
honest note where the index couldn't resolve a reference.

Or generate a full **followable refactoring playbook** that a junior dev (or a
small model) can execute:

```
drag-lint cycles --db myapp.sqlite --plan > cycle-plan.md
```

Per cycle it gives the files, the load-bearing symbols (use site **and**
declaration site, with line numbers), an auto-classified fix (*extract the shared
contract*, or *invert the dependency* for layering inversions), numbered steps,
and a verify command. Build after each cycle and re-run `cycles` to confirm.

> **Worked example:** [docs/examples/circular-uses-demo/](docs/examples/circular-uses-demo/)
> is a tiny compiling two-unit cycle, with the exact `--edges` / `--causes` /
> `--plan` output drag-lint produces for it captured verbatim in
> [REPORT.md](docs/examples/circular-uses-demo/REPORT.md). (`circular-uses` is
> also a built-in lint rule, **on by default**, so `lint-project` flags cycles
> automatically.)

Then propose and apply the
cleanup, **verified by the compiler** so it never breaks the build:

```
drag-lint uses-audit MyUnit.pas --db myapp.sqlite                       # propose
drag-lint uses-fix --project MyApp.dproj --db myapp.sqlite              # dry-run sweep report
drag-lint uses-fix MyUnit.pas --project MyApp.dproj --db myapp.sqlite --apply   # apply (.bak backup)
```

> **Caveat (important):** `uses-fix`'s per-unit verify is **best-effort, not a
> faithful full-build check** — a single-unit `dcc` compile can reuse a stale
> `.dcu` (masking a real error) or abort on an RTL dependency. Treat
> `cycles`/`uses-audit` as **advisory** (they pinpoint candidates, and the index
> can miss refs like `set` types), and **always do a full project build** after
> `--apply` (revert from `.bak` if it fails). Reliable bulk cleanup needs
> full-project-build verification, not per-unit compiles.

### Third-party dependency report

See which external/library units the project leans on — RTL, DevExpress,
Spring4D, and anything not in your own tree:

```
drag-lint deps-report --db myapp.sqlite                 # rollup (text)
drag-lint deps-report --db myapp.sqlite --edges --format csv
```

Per external unit it reports which project units import it, how many, the
shortest uses-path, and a library grouping; `--edges` gives the flat
project-unit → external-unit list. A unit is "external" when it isn't indexed
or resolves to a library path (RTL / installed packages).

### Component conversion

Plan AND APPLY a component/type migration (`TDBEdit` -> `TcxDBEdit`, or any
`TPersistent`-rooted pair) from the REAL, AST-exact property trees of both types.
`proptree` enumerates a type's deep property tree; `convert-scaffold`
auto-drafts a validated reFind-superset rules file from both trees;
`convert-validate` checks a rules file's paths against those trees -- catching
typos that reFind's blind PCRE cannot; and `convert-apply` rewrites the real
`.pas` + `.dfm` files (dry-run by default, `--apply` to write for real, with
automatic `.BCK<n>` backups + a `recovery.txt` unless `--no-backup`). The usual
workflow: `convert-scaffold` -> `convert-validate` -> `convert-apply` (dry-run,
review the plan) -> `convert-apply --apply`. Full DSL reference, the 5
conversion surfaces, and the safety scheme: **[docs/CONVERSION-RULES.md](docs/CONVERSION-RULES.md)**.

### Consuming the index from another tool

The SQLite index is documented for external consumers in
[docs/INDEX-SCHEMA.md](docs/INDEX-SCHEMA.md) — every table, the
project-vs-external boundary, and the stability contract. Introspect any index
live with:

```
drag-lint schema --db myapp.sqlite --format json        # schema_version + tables + columns + row counts
```

### Semantic errors without a full build

`check-unit` compiles a single unit in its project's context, so you get real
compiler errors (e.g. `E2003 Undeclared identifier`) fast -- and on the
**unsaved** buffer via a shadow overlay:

```
drag-lint check-unit MyUnit.pas --project MyApp.dproj --platform win64 \
          --db myapp.sqlite --resolve-uses
```

`--resolve-uses` turns an undeclared identifier into a fix: *"add unit X to the
uses clause."*

### LSP server (Zed / VS Code)

Point your editor's LSP config at `drag-lint.exe lsp --db <path>.sqlite`.
The server speaks JSON-RPC over stdio.

Capabilities: hover, definition, references, completion, signatureHelp,
diagnostics (publishDiagnostics on didSave), workspaceSymbols.

### MCP server (Claude / Cursor)

Add to your MCP config (e.g. `~/.claude/claude_desktop_config.json`):

```json
{
  "drag-lint": {
    "command": "drag-lint.exe",
    "args": ["serve", "--db", "C:\\Projects\\MyApp\\.drag-lint.sqlite"]
  }
}
```

14+ tools are then available to Claude: `find_symbol`, `find_callers`,
`get_symbol_doc`, `get_context_bundle`, `rename_symbol`, `run_compile_check`,
and more (see [MCP tools](#mcp-tools-14) below).

### RAD Studio 13 plugin

1. Build the BPL:
   ```
   msbuild src/delphi-plugin/dclDragLintWizard.dproj /p:Platform=Win64 /p:Config=Debug
   ```
   Or download `dclDragLintWizard.bpl` from the latest GitHub release.
2. In RAD Studio: **Component > Install Packages > Add** -- browse to the BPL.
3. Restart RAD Studio.
4. The **Tools > drag-lint** menu now has 12+ entries. Settings live under
   **Tools > Options > Third Party > drag-lint** as four pages (General /
   Indexer / Linter / Editor); per-project lint rules are reachable via a
   **"drag-lint: Project Rules..."** right-click on the project node in the
   Project Manager.
5. On IDE startup, the drag-lint logo + version appear on the RAD Studio
   splash screen. **Help > About > drag-lint** shows an entry with live
   engine self-info (version, build date, tree-sitter versions,
   capabilities, exe path, plugin log location), fetched from `drag-lint.exe`
   on a background thread so it never blocks IDE startup; if the exe call
   fails, the entry shows a structured diagnostic error block instead.

---

## Features

### CLI (~25 commands)

| Command | Description |
|---------|-------------|
| `index <path>` | Parse and index a Delphi project into SQLite |
| `index --scan-libraries-win` | Index the IDE's Win32+Win64 Library + Browsing paths (from the registry) |
| `index --scan-libraries-all` | Same, but every registered platform (adds Posix/iOS/Android/OSX source) |
| `query --name <name>` | Find symbols by name (fuzzy) |
| `query --text "<phrase>"` | Search indexed string content -- messages, captions, exception text (never identifiers). Flags: `--any-order`, `--substring`, `--source pas\|dfm\|sql`, `--limit N`, `--json`. SQL `CREATE EXCEPTION` messages are indexed from `MS*.sql` files only by default (`--no-sql-ms` to index every `.sql`). |
| `surface --qname <qname>` | Show the full source surface of a symbol |
| `slice --qname <qname>` | Extract the call-slice reachable from a symbol |
| `impact --qname <qname>` | Show everything that would be affected by changing a symbol |
| `wiring --qname <IIntf\|TForm>` | Spring4D DI wiring edges (impl class + lifetime + resolve-sites) and DFM event handlers (`--coverage` lists unresolved DI registrations) |
| `hover --file <f> --line <n> --col <c>` | Hover info at a source position |
| `rename --qname <q> --new-name <n>` | Preview or apply a symbol rename |
| `generate-docs --qname <q>` | Generate an XML doc-comment stub |
| `generate-test --qname <q>` | Generate a test-method stub |
| `find-deadcode` | List symbols with no callers outside their own unit |
| `compile-check <dproj>` | Run msbuild and store diagnostics in the DB |
| `refresh-findings --project <dproj> --db <db>` | Recompile only stale units (save-time newer than last compile) and refresh stored compiler findings per file, so DCC hints stay current even for clean unchanged units; `--full` forces a full build. Spawned by the IDE on save/idle and by the "Full Compile Sweep" menu |
| `check-unit <unit.pas>` | Compile one unit in project context (semantic errors; `--shadow` for unsaved buffers, `--resolve-uses` to suggest the missing unit) |
| `cycles` | Circular unit dependencies (`--edges` shows edges + move/layering candidates) |
| `uses-audit <unit.pas>` | Propose interface→implementation moves + unused units |
| `uses-fix <unit.pas> --project <dproj>` | Compiler-verified uses cleanup (move/remove; dry-run by default, `--apply`) |
| `find-unit --name <X> --in <file>` | Add the unit that declares `X` to `<file>`'s `uses` clause (`--apply` to write) |
| `import-log <log>` | Import a saved msbuild log into the DB |
| `format <file>` | Format a .pas file with the YADF formatter |
| `check-ast <file>` | Run tree-sitter lint rules without compiling |
| `lint <file>` | Run all built-in + external .scm rules |
| `query find-callers --name <n>` | List every call-site for a symbol (with source context) |
| `workspace index` | Index all projects in a workspace config |
| `workspace status` | Show per-project file counts |
| `workspace add <dproj>` | Add a project to the workspace config |
| `context --task "verb qname"` | Emit a compact context bundle for AI prompts (e.g. `--task "modify Unit.TFoo.Bar"`) -- doc + surface + the target's body, ~10-60x leaner than the source |
| `check-unit ... --shadow` | Compile an **unsaved** buffer (overlay) and report errors -- the CLI side of the IDE's ghost-compile |
| `ghost-check <dproj> --overlays <manifest>` | Compile a project with one or more units' unsaved content overlaid (multi-unit), restoring every file byte-for-byte; powers the IDE's live ghost-compile |
| `ghost-recover` | Restore any files left overlaid by a crash mid-ghost-check (`_D-RAG` journal) |
| `bench-context <dir>` | Benchmark context bundle throughput |
| `forms-csv --project <dproj> --db <db>` | Test-helper CSV: one row per form with the button/menu path from the main form (`Navigation`), the forms that open it (`Called From`), unit + line count (`--out <f.csv>`, `--root <TfrmMAIN>`) |
| `butterfly --qname X [--depth N] [--format dot\|mermaid\|text\|json]` | Composes a symbol's callers (upward wing) + callees (downward wing) into one chart -- static-export counterpart to the in-IDE butterfly tab (`--output <f>`, default format `dot`) |
| `proptree --qname X [--depth N] [--no-to-persistent] [--format text\|json]` | Recursive deep-property enumerator: flattened dotted paths of a class's own + inherited properties, recursing into class-typed types down to `TPersistent` (depth cap 6; JSON schema `proptree/1`). Foundation for component conversion -- see [docs/CONVERSION-RULES.md](docs/CONVERSION-RULES.md) |
| `convert-scaffold --from F --to T [--out <f>]` | Auto-generate a VALID reFind-superset conversion-rules file from the real F/T property trees: concrete `#link` where one source matches by leaf-name+type, `???` for ambiguities, `DROPPED` notes for orphaned source props |
| `convert-validate --rules <f> [--from F] [--to T] [--print-parsed]` | Parse + validate a reFind-superset conversion-rules DSL; checks `#link`/`#default` paths against the real property trees (exit 0 valid / 1 errors / 2 bad args) |
| `convert-apply --unit F.pas --rules <f> --db <db> [--only Name1,Name2,...] [--apply] [--no-backup]` | Rewrites all 5 conversion surfaces for the `.dfm` component instances matching a `#convert` rule: `.pas` declaration retype, `.pas` uses-add, `.dfm` object-block re-emit, `.pas` property/event access-site rewrite, and runtime-creator retype + `{ TODO: verify creator }` marker. Dry-run (preview, no writes) by default; `--apply` writes for real with `.BCK<n>` backups + a `recovery.txt` unless `--no-backup` |
| `lsp [--db <db>]` | Start the LSP server (stdio) |
| `serve [--db <db>]` | Start the MCP server (stdio) |
| `info [--json]` | Engine self-info: version, build date, tree-sitter versions, capabilities (FTS5, CLI verb count), exe path, platform -- read-only, no DB. What the IDE Help>About box calls |
| `--version` | Print version |
| `--help` | Print help |

### MCP tools (14+)

| Tool | Description |
|------|-------------|
| `find_symbol` | Search the index by name |
| `find_callers` | List all call-sites for a symbol |
| `get_symbol_doc` | Retrieve the doc-comment for a symbol |
| `get_context_bundle` | Compact context bundle for AI consumers |
| `rename_symbol` | Preview or apply a symbol rename |
| `run_compile_check` | Trigger msbuild and return diagnostics |
| `import_log` | Import a saved build log |
| `run_ast_checks` | Run AST lint rules on a file |
| `format_file` | Format a source file with YADF |
| `get_surface` | Full source surface of a symbol |
| `get_impact` | Call-impact set for a symbol |
| `get_wiring` | Spring4D DI edges + DFM event handlers for an interface or form |
| `get_slice` | Reachable call-slice |
| `workspace_status` | Workspace project/file summary |
| `workspace_index` | Re-index all workspace projects |

### Lint rule pack (130+ rules)

Run `drag-lint rules` for the authoritative, always-current catalog (built-in +
external `.scm`, 130+ and growing). The table below is a small sample of the
built-in rules:

| Rule id | Severity | Description |
|---------|----------|-------------|
| `writeln-in-source` | info | Direct `WriteLn` -- use a logger |
| `goto-statement` | warning | `goto` considered harmful |
| `with-statement` | info | `with` makes scope ambiguous |
| `nested-with` | warning | Nested `with` -- scope ambiguity compounds |
| `empty-procedure-body` | info | Empty `begin..end` block |
| `large-magic-number` | info | Unaliased numeric literal |
| `case-magic-numbers` | info | Integer literal as `case` label |
| `string-equality-comparison` | info | `=` comparison on string expressions |
| `parser-error` | error | Tree-sitter `ERROR` node (malformed syntax) |
| `compiler-magic-comments` | info | TODO/FIXME/HACK/XXX in a comment |
| `assert-call` | info | `Assert()` -- ensure descriptive second argument |
| `boolean-comparison-true` | info | `X = True` or `X = False` -- redundant |
| `redundant-as-tobject` | info | `(X as TObject)` -- every object is already TObject |
| `inherited-bare` | info | Bare `inherited;` -- verify it calls the right ancestor |

Drop custom `.scm` + `.json` pairs in the `rules/` directory; see
[rules/README.md](rules/README.md) for the schema.

### RAD Studio plugin

**`drag-lint` menu** (top-level on the main menu bar -- falls back under Tools -- with ~30 items organized into submenus): Hover at Cursor, Show Completion, 
Show Signature Help, Run Diagnostics, Rename Symbol, Compile & Diagnose, Import Build Log,
Format with YADF, Show Structure, Run AST Checks, Find Usages, Symbol Search, dockable 
panels (Structure / Usages / Graph), Generate Test Helper CSV..., 
**Uses & Dependencies** submenu (cycles, uses-audit, uses-fix, reconcile, wiring, impact, reverse call tree,
**Call Graph (Butterfly)...**), 
**Reverse Call Tree (clickable, Messages window)** -- posts the N-deep upward
call tree for the symbol under the cursor as clickable rows in the IDE
Messages window (double-click a row to jump to that call site), 
**Call Graph dock tab** -- callers above and callees below the symbol as a
navigable tree (double-click a node to jump to file:line); open it via
Ctrl+Alt+B, the Uses & Dependencies menu item above, or right-click a symbol
in the Structure tab -> "Show in Call Graph", 
**Inspect Symbol** submenu (surface, slice, type-at-cursor), 
**Code Quality** submenu (dead code, undocumented, TODOs, compiler hints, top symbols),
**Generate & Export** submenu (docs, tests, enums, graph, Obsidian),
**Index & Maintenance** submenu, plus diagnostics & test tools, and
**drag-lint Options...** (opens Tools > Options focused on the drag-lint
pages).

**Keystroke bindings** (registered via `IOTAKeyBindingServices`):

| Shortcut | Action |
|----------|--------|
| Ctrl+Alt+H | Hover at Cursor |
| Ctrl+Alt+C | Show Completion |
| Ctrl+Alt+S | Show Signature Help |
| Ctrl+Alt+D | Run Diagnostics |
| Ctrl+Alt+I | In-editor diagnostic hint popup |
| Ctrl+Alt+R | Rename Symbol |
| Ctrl+Alt+F | Find Usages |
| Ctrl+Alt+T | Symbol Search |
| Ctrl+Alt+K | Reverse Call Tree (clickable, Messages window) |
| Ctrl+Alt+B | Call Graph (Butterfly) |

**In-editor diagnostics**: gutter dot markers + wavy underlines via
`IOTAEditViewNotifier.BeforeDrawLine`. Severity colours from the IDE colour
scheme registry.

**Ghost-compile (live, out-of-process)**: as you type, drag-lint compiles your
**unsaved** buffer(s) in a *spawned* process and surfaces real compiler errors
(e.g. `E2003 Undeclared identifier`) in the gutter -- without saving, and without
ever freezing the IDE. Fires automatically on idle and on tab-switch, with
multi-unit overlays so edits across several open units are all seen. Files are
restored byte-for-byte (crash-safe via a recovery journal).

**Hover tooltip** (v0.35): a 200ms timer shows `Application.HintWindow` with
the diagnostic message when the cursor is stable for 600ms over a row that has
a diagnostic. Caret-based (not pixel-precise). Toggle via Settings.

**Code lens** (v0.32): dim grey `[N callers]` text next to method declarations.

**Structure form** (v0.30): floating `fsStayOnTop` form showing the symbol
tree of the active file, updated on view activation.

**Find Usages form** (v0.33): `Ctrl+Alt+F` prompts for a symbol name; shows
callers grouped by file in a TTreeView; double-click jumps the editor.

**Symbol Search form** (v0.33): `Ctrl+Alt+T` debounced live search over the
indexed symbol table; Enter navigates the editor to the selected location.

**Native Tools > Options pages** (v0.30, split into four in Batch B): four
pages -- General / Indexer / Linter / Editor -- under Tools > Options > Third
Party > drag-lint, each backed by `INTAAddInOptions`. **All plugin settings
(exe path, DB template, indexer/linter/editor toggles) live here** -- edit a
value, click OK, and the next hover / lint / index action picks it up (no IDE
restart needed). Reopen them anytime via **drag-lint > drag-lint Options...**.
Per-project lint rules (`drag-lint-lint.json`) are edited from the drag-lint
dock's Lint Options tab, reachable via **Project Manager right-click a project >
"drag-lint: Project Rules..."**. That tab now has a **naming-convention preset
selector** (v0.97) -- pick *Embarcadero* (`AValue` params) or *House*
(`pMyParam` / `FMyField` / `TMyClass`) to bulk-set the naming rules, or *Custom*
to hand-tune them. The combo also lists **your own saved presets** (v0.99):
tune the 8 naming values, click **Save as...** and give it a name, and it's
added to the combo alongside the built-ins; **Delete** removes a saved preset
(built-ins and Custom cannot be deleted). Saved presets persist per-project in
`drag-lint-lint.json` under a top-level `naming.presets` array -- IDE-written
only; the CLI does not yet read this key.

---

## Architecture

```
drag-lint.exe
  |
  +-- CLI dispatch (DRagLint.CLI)
  |     |
  |     +-- Indexer (DRagLint.Core.Indexer)
  |     |     +-- tree-sitter-delphi13.dll  (Delphi 13 grammar)
  |     |     +-- tree-sitter-dfm.dll        (DFM grammar)
  |     |     +-- tree-sitter.dll            (libtree-sitter runtime)
  |     |     +-- SQLite storage
  |     |
  |     +-- Query / Surface / Impact / Slice
  |     +-- Lint (rule runner over .scm files)
  |     +-- Refactor (rename, doc stubs, test stubs, YADF format)
  |     +-- Compiler diagnostics (msbuild integration)
  |     +-- Workspace (multi-project shared DB)
  |
  +-- LSP server (DRagLint.LSP.Server) -- stdio JSON-RPC
  |
  +-- MCP server (DRagLint.MCP.Server) -- stdio JSON-RPC
  |
  +-- CLI context bundler (DRagLint.Context.Bundler)

dclDragLintWizard.bpl  (Delphi IDE plugin)
  +-- Wizard / menu / keystrokes / EditViewNotifier
  +-- LSP client -> drag-lint.exe lsp
  +-- DiagnosticCache -> in-editor markers + hover tooltip
  +-- CodeLensCache -> inline [N callers]
  +-- Structure / Refactor / Usages / SymbolSearch forms
  +-- Options (INTAAddInOptions, 4 pages: General/Indexer/Linter/Editor)
  +-- Project Manager menu (per-project "Project Rules..." -> Lint Options dock)
```

All three entry-points (CLI, LSP, MCP) call the same indexer, query, lint,
and refactor engine. The IDE plugin is a thin wrapper around the LSP client
plus direct CLI calls for features the LSP protocol doesn't cover.

---

## Building from source

Prerequisites:
- RAD Studio 13 Florence (37.0) with Win64 target
- `tree-sitter-delphi13` DLLs in `third_party/dll/`

Build the CLI:
```
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
msbuild drag-lint.dproj /p:Config=Release /p:Platform=Win64
```

Build the IDE plugin:
```
msbuild src/delphi-plugin/dclDragLintWizard.dproj /p:Config=Debug /p:Platform=Win64
```

Run the test suite (batch files in `tests/fixtures/`):
```
tests\fixtures\T61_hovertracker.bat
tests\fixtures\T62_lint_rules_v035.bat
tests\fixtures\T56_lint_rules_v032.bat
:: ... etc.
```

PowerShell smoke scripts in `tests/autotest/` exercise the built exe end to end:
```
pwsh -File tests/autotest/run_smoke.ps1       # CLI + LSP server smoke
pwsh -File tests/autotest/run_formsmap.ps1    # forms-csv navigation-map smoke (fixture project)
```

---

## Version history

See [CHANGELOG.md](CHANGELOG.md) for the detailed history (v0.16 through
v0.44-alpha, 2026-05-28 → 2026-06-14). Development continues daily (currently
**v0.46-alpha** on the `feat/*` branches): graph viewer on Win64 (UML / Code Flow
/ Where-Used / editor-sync), out-of-process ghost-compile, and manifest-driven
multi-DB resolution.

---

## License

MIT. See [LICENSE](LICENSE).
