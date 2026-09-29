# drag-lint -- Install & Index Setup

drag-lint is a Delphi-native code index + IDE plugin: symbol-exact search, Find
Usages, hover/completion, diagnostics, and a graph viewer -- all over a local
SQLite index, no cloud, no Python/Node at runtime.

## 0. Pieces

| Artifact | What it is | Lives |
|---|---|---|
| `drag-lint.exe` | The engine (64-bit only): indexer, query CLI, and the LSP server the plugin talks to | `third_party\dll-win64\`, the BPL folder's sibling |
| `dclDragLintWizard.bpl` | The RAD Studio IDE plugin (menu, dock panel, hover, diagnostics) | `third_party\dll-win32\` |
| `library-Win32.sqlite` / `library-Win64.sqlite` | The shared **library** index (RTL/VCL/DevExpress/Spring4D/...), one per platform | `C:\Projects\.drag-lint\` (also read next to the BPL) |
| `drag_lint_graph.exe` | Standalone graph viewer | next to the BPL (already copied) |
| `DragLintGraph*.bpl` (x3) | Graph **component** packages (optional -- to drop the graph control on your own forms) | `Delphi-RAG-Lint-Graph\bin\Win32\` |

## 1. Install the IDE plugin

1. Make sure the Win64 engine is built into `third_party\dll-win64\drag-lint.exe`
   (`build\build_draglint_win64.bat` puts it there). The BPL is 32-bit because
   `bds.exe` is, but the engine is 64-bit only: the plugin runs
   `<BPL folder>\..\dll-win64\drag-lint.exe`, or the exe the **General** page
   names. Keep no `drag-lint.exe` beside the BPL -- the language-server spawn
   still falls back to one there when `dll-win64\` has none, and an old engine
   answers wrongly rather than failing. The plugin no longer pulls a staged
   exe from `C:\TEMP1\bpl_staging\` on load.
2. RAD Studio -> **Components -> Install Packages -> Add...** -> pick
   `third_party\dll-win32\dclDragLintWizard.bpl` -> OK.
3. You should get a top-level **drag-lint** menu and
   **View -> Tool Windows -> drag-lint** (the dock panel).

To update after a rebuild: **uninstall** the package first (it locks the BPL),
copy the fresh BPL over, reinstall. The plugin removes its own menu entries on
uninstall.

## 2. Settings (Tools -> Options -> Third Party -> drag-lint)

Open via **Tools -> Options -> Third Party -> drag-lint**, or from the plugin's
own menu: **drag-lint -> drag-lint Options...** (both land on the same dialog,
focused on the drag-lint pages). Settings are split across **four** nested
sub-pages -- General / Indexer / Linter / Editor -- so each page only ever
writes its own fields.

- **General** -- `drag-lint.exe` path (leave blank to use the Win64 exe in the
  BPL folder's sibling `dll-win64\`), the DB path template (default resolves `<projdir>\_D-RAG\
  <projname>.sqlite` for the active `.dproj`; the plugin also probes the
  pre-relocation flat `drag-lint.sqlite` next to or above the project as a
  fallback), workspace mode, and the auto-compile toggles
  (compile on save, compile the unsaved buffer on idle, compile once on
  project open, compile on switching to a `.pas` file, jump to Diagnostics
  after a compile).
- **Indexer** -- auto-index when a project opens, auto-reindex on save, scan
  libraries (RTL/VCL/DevExpress) on index, extra index DB paths (one per
  line), auto-discover sibling databases, and whether to include the
  exe-relative library database.
- **Linter** -- enable Run Diagnostics, run diagnostics automatically on save,
  enable inline markers (gutter + underline) plus the per-severity
  show-errors/warnings/hints/info toggles, and a **Doc generation** group with
  **Max return cases** (`docs.max_return_cases`) -- see the table below; this
  one field is NOT a registry setting.
- **Editor** -- Hover at Cursor, the hover tooltip (caret-based, 600ms dwell),
  Show Completion, Show Signature Help, and inline code lens (`[N callers]`).

All of the above except **Max return cases** are stored per-user in the
Windows registry (`HKEY_CURRENT_USER\Software\drag-lint\DelphiPlugin`).

For **per-project lint rules** (enable/disable/severity in
`drag-lint-lint.json`), right-click the project node in the **Project
Manager** and choose **"drag-lint: Project Rules..."** -- this activates that
project and opens the drag-lint dock's **Lint Options** tab scoped to it. You
can also hand-edit `drag-lint-lint.json`; see `rules/README.md`.

### Where to configure X

| Setting | Where (page / menu) | Backing store |
|---|---|---|
| `drag-lint.exe` path, DB path template, workspace mode, auto-compile toggles | **General** page | Registry (per-user) |
| Auto-index, auto-reindex on save, scan libraries, extra index DBs, auto-discover DBs, include library DB | **Indexer** page | Registry (per-user) |
| Enable diagnostics, auto-diagnostics on save, inline markers + severity toggles | **Linter** page | Registry (per-user) |
| **Max return cases** (`docs.max_return_cases`) | **Linter** page, "Doc generation" group | Manifest: project's `.drag-lint.json` (dotted, local override) if a project is open; otherwise the `drag-lint.json` (undotted) beside `drag-lint.exe` |
| Hover, hover tooltip, completion, signature help, code lens | **Editor** page | Registry (per-user) |
| Lint rule enable/disable/severity/thresholds | **Project Manager -> right-click project -> "drag-lint: Project Rules..."** (dock "Lint Options" tab) | Per-project `drag-lint-lint.json` |
| Index sections / global manifest settings (`sizeGuardMB`, `maxJobs`, ...) | Hand-edit | Manifest `drag-lint.json` (global, beside the exe) or a local `.drag-lint.json` override |

Note the naming: the **dotted** `.drag-lint.json` is always a **per-project
local override** (the CLI/plugin walk up from the project directory to find
it); the **undotted** `drag-lint.json` beside `drag-lint.exe` is the
**global** manifest. The Linter page's Max return cases field targets
whichever of the two applies to the current context (project open vs. no
project open) -- never the merged, effective view `TManifestIO.Load` computes
for indexing.

## 3. Create the index databases

drag-lint queries one or more `.sqlite` files. Two scopes matter:

### a) Per-project DB (deep -- enables Find Usages of variables)
```
drag-lint index "C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj" --db "C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite" --deep
```
- **The target declares the scan type.** A `.dpr`/`.dproj` target indexes exactly
  that project's **compile closure** (members + transitively-used project-local
  units + sibling `.dfm` + `{$I}` includes + the project file); units resolved
  through a Delphi Library/Browsing path and loose unreferenced files in the
  folder are excluded. A **folder** target indexes the whole tree instead.
- **Mode is separate from type:** `--recompile` (default, incremental) or
  `--rebuild` (from scratch).
- One DB per project is the current layout on this machine, and (since
  2026-08-11) each project's DB lives in a hidden `_D-RAG` folder **beside its
  own `.dproj`** rather than in a shared folder -- `<project folder>\_D-RAG\
  <project file base name>.sqlite`. The old per-repo union DBs were retired
  and deleted on 2026-08-09; the brief shared-folder layout that replaced them
  (`C:\Projects\.drag-lint\<Repo>-<Project>.sqlite`) was itself replaced on
  2026-08-11. In practice you rarely type this path by hand -- `index --all`
  (section c) derives it from the manifest.
- `--deep` records identifier **usages** (reads/writes/attributes), so Find
  Usages works for variables/components, not just calls. Use it for *your* code.
- Re-indexing is incremental (mtime+sha skip). To force a full rebuild after
  switching deep/shallow, use `--rebuild` (or delete the `.sqlite` first).

### b) Library DB (shallow -- definitions/calls, queried by the AI/hover)
```
drag-lint index --all --only Library --platform win32
drag-lint index --all --only Library --platform win64
```
- This is the per-platform build: a manifest section with
  `"source": "registry-libraries"` (see section c) expands into one database per
  listed platform, `library-Win32.sqlite` and `library-Win64.sqlite` under the
  manifest's `outDir`. Use the section name your manifest gives it.
- `drag-lint index --scan-libraries --db <file.sqlite>` (alias of
  `--scan-libraries-win`) needs no manifest, but it walks the **Win32 + Win64**
  Library/Browsing paths together into ONE database; `--platform` does not
  narrow it. Do not use it to fill the two per-platform files.
- Defaults **shallow** (no usage refs) -- usage refs would ~double the ~1.3 GB
  library DB, and you query libraries by *definition/call*, not usage.
- Includes `.inc` files (so include-file symbols like `csmRed` are findable).
- **One library DB per platform.** The IDE plugin looks for `library-Win32.sqlite`
  then `library-Win64.sqlite` beside the BPL, and still falls back to the legacy
  single-file `drag-lint-library.sqlite` if neither exists, so older installs keep
  working (`DRagLint.Plugin.DbResolver`). New installs should build the
  per-platform pair.

### c) One command for everything: `index --all`
drag-lint reads a named-index manifest (`drag-lint.json`, with `settings` +
`indexes` sections) that lives next to `drag-lint.exe`. **The release archive
does not ship one.** A source checkout does have `third_party\dll-win64\
drag-lint.json`, but that is this development machine's own manifest -- its
sections name `C:\Projects\...` roots -- not a template. Write your own, or
replace that file's `indexes` with your project and library roots: the format,
a minimal example and what each section type builds are in the root
[`INSTALL.md`](../INSTALL.md), section 2a "The manifest". Without a manifest,
`index --all` builds nothing and exits 0. Then:
```
drag-lint index --all              # build every configured index
drag-lint index --all --dry-run    # show the plan + timings only
```
`index --all` prunes `*BACKUP*` and `.scanignore`'d folders. Add
`--only <Sec1,Sec2>` to rebuild just named indexes, `--jobs <n>` to parallelize,
`--platform win32|win64` to pick the library set.

> Two ignore mechanisms exist, and they are different files:
>
> - **`.scanignore`** is a directory-prune **marker**: drop an empty
>   `.scanignore` file in any folder and a folder walk (`index <folder>`, a
>   folder or library section of `index --all`, `--scan-libraries`) skips it
>   and its whole subtree. Its contents are never read, and `--no-use-ignore`
>   does not turn it off.
> - **`.gitignore` / `.hgignore`** are the **pattern** files, read per folder
>   as the walk descends (glob lines, `#` comments, trailing `/` = folder only,
>   leading `!` re-includes; `.hgignore` regexp-syntax lines are skipped). They
>   are honoured by default; `--no-use-ignore` (or a manifest section's
>   `"useIgnoreFiles": false`) opts out.
>
> Either is useful for big vendor trees you don't query.

## 4. (Optional) Install the graph component packages
Build order: `DragLintGraph` -> `DragLintGraphDb` -> `DragLintGraphDcl`
(`Delphi-RAG-Lint-Graph\src\...`). Install `DragLintGraphDcl.bpl` to get
`TDragLintGraphControl` on the *Delphi-RAG-Lint* palette tab. The standalone
viewer (`drag_lint_graph.exe`) and the dock **Graph** tab's launcher work
without installing anything.

## 5. Verify
```
drag-lint query --name TStringList --db <yourdb>                    # exact symbol lookup
drag-lint query find-callers --name <YourComponent> --db <yourdb>   # all call-sites
```
In the IDE: open **View -> Tool Windows -> drag-lint**, dock it, check the
Structure / Find Usages tabs.
