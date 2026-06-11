# drag-lint — Install & Index Setup

drag-lint is a Delphi-native code index + IDE plugin: symbol-exact search, Find
Usages, hover/completion, diagnostics, and a graph viewer — all over a local
SQLite index, no cloud, no Python/Node at runtime.

## 0. Pieces

| Artifact | What it is | Lives |
|---|---|---|
| `drag-lint.exe` | The engine: indexer, query CLI, and the LSP server the plugin talks to | next to the plugin BPL |
| `dclDragLintWizard.bpl` | The RAD Studio IDE plugin (menu, dock panel, hover, diagnostics) | `third_party\dll-win32\` |
| `drag-lint-library.sqlite` | The shared **library** index (RTL/VCL/DevExpress/Spring4D/…) | next to the BPL |
| `drag_lint_graph.exe` | Standalone graph viewer | next to the BPL (already copied) |
| `DragLintGraph*.bpl` (×3) | Graph **component** packages (optional — to drop the graph control on your own forms) | `Delphi-RAG-Lint-Graph\bin\Win32\` |

## 1. Install the IDE plugin

1. Make sure `drag-lint.exe` sits next to `dclDragLintWizard.bpl`
   (`C:\Projects\Delphi-RAG-lint\third_party\dll-win32\`). The plugin auto-pulls
   a newer staged exe from `C:\TEMP1\bpl_staging\` on load.
2. RAD Studio → **Components → Install Packages → Add…** → pick
   `third_party\dll-win32\dclDragLintWizard.bpl` → OK.
3. You should get a top-level **drag-lint** menu and
   **View → Tool Windows → drag-lint** (the dock panel).

To update after a rebuild: **uninstall** the package first (it locks the BPL),
copy the fresh BPL over, reinstall. The plugin removes its own menu entries on
uninstall.

## 2. Settings (Tools → Options → Third Party → drag-lint)

- **Exe path** — leave blank to use the `drag-lint.exe` next to the BPL.
- **DB path template** — how the plugin finds a project's DB. Default resolves a
  `drag-lint.sqlite` next to (or above) the active `.dproj`.
- **Include library DB** — also query `drag-lint-library.sqlite`.
- **Auto reindex on save** / **Auto diagnostics on save** — default on.

## 3. Create the index databases

drag-lint queries one or more `.sqlite` files. Two scopes matter:

### a) Per-project DB (deep — enables Find Usages of variables)
```
drag-lint index "C:\Projects\DB\ORM3" --db "C:\Projects\DB\ORM3\drag-lint.sqlite" --deep
```
- `--deep` records identifier **usages** (reads/writes/attributes), so Find
  Usages works for variables/components, not just calls. Use it for *your* code.
- Re-indexing is incremental (mtime+sha skip). To force a full rebuild after
  switching deep/shallow, delete the `.sqlite` first.

### b) Library DB (shallow — definitions/calls, queried by the AI/hover)
```
drag-lint index --scan-libraries --db "third_party\dll-win32\drag-lint-library.sqlite"
```
- Defaults **shallow** (no usage refs) — usage refs would ~double the ~1.3 GB
  library DB, and you query libraries by *definition/call*, not usage.
- Includes `.inc` files (so include-file symbols like `csmRed` are findable).

### c) One command for everything: `scan-all`
Create `C:\Projects\.drag-lint.json`:
```json
{ "scan": {
    "outDir": "C:\\Projects\\.drag-lint",
    "library": true,
    "projectsRoot": "C:\\Projects",
    "projects": [ "C:\\Projects\\DB\\ORM3", "C:\\Projects\\TableTools",
                  "C:\\Projects\\DB\\SQL", "C:\\Projects\\YADF" ]
} }
```
Then:
```
drag-lint scan-all          # builds library.sqlite (shallow) + active-projects.sqlite (deep)
                            # + projects.sqlite (deep, dedup'd vs the other two)
drag-lint scan-all --dry-run   # show the plan + timings only
```
`scan-all` prunes `*BACKUP*` folders, `.scanignore`'d folders, and only indexes
`MS*.SQL` among `.sql`. It reports per-dictionary timing.

> Drop an empty `.scanignore` file in any folder to exclude it (and its subtree)
> from `scan-all` / `index` — useful for big vendor trees you don't query.

## 4. (Optional) Install the graph component packages
Build order: `DragLintGraph` → `DragLintGraphDb` → `DragLintGraphDcl`
(`Delphi-RAG-Lint-Graph\src\…`). Install `DragLintGraphDcl.bpl` to get
`TDragLintGraphControl` on the *Delphi-RAG-Lint* palette tab. The standalone
viewer (`drag_lint_graph.exe`) and the dock **Graph** tab's launcher work
without installing anything.

## 5. Verify
```
drag-lint query --name TStringList --db <yourdb>      # exact symbol lookup
drag-lint usages --name <YourComponent> --db <yourdb> --deep-built-db
```
In the IDE: open **View → Tool Windows → drag-lint**, dock it, check the
Structure / Find Usages / Symbol Search tabs.
