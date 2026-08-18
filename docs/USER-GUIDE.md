# drag-lint — User Guide

Everything drag-lint does, from the IDE and the CLI. See `INSTALL.md` first.

## The dock panel — View → Tool Windows → drag-lint

A single dockable window (park it at the bottom like Grep Results) with tabs:

### Structure
- Lists every code element in the active file (units, classes, methods with
  **signatures**, properties, fields, enums…) plus a **Diagnostics** node.
- **Filter box + `regex` checkbox** at the top: type to filter on the fly.
  Plain text = substring (`grid` matches `dxDBGrid1`); tick **regex** for a
  regular expression. Filters over symbol name + qualified name; header shows
  `Code Elements (N of M)`. Double-click a row to jump to it.
- **Right-click a row** for: **Go to Declaration**, **Go to Implementation
  (body)** (jumps to the `TClass.Method` body, not just the interface line), and
  **Find Usages**.

### Find Usages
- Type a symbol, press **Enter**. Finds **all** references — including variable
  and property usages (`dxDBGrid1.DataSource := …`), not just calls — provided
  the project DB was built `--deep`.
- **Width selector** (Narrow / Wide / Very-wide):
  - *Narrow* — the declaration + every direct reference.
  - *Wide* — narrow + transitive-caller blast radius (depth 2).
  - *Very-wide* — narrow + transitive callers to a deeper depth.
- Results are grouped: Declaration / Reads / Writes / Calls / Type uses /
  Attributes / Event handlers / Impact. Double-click to navigate; the searched
  identifier is highlighted in snippets.

### Symbol Search
- Type to search across the resolved DBs (debounced). Double-click / Enter opens
  the symbol's source.

### Graph — its own dockable window
- **View → Tool Windows → drag-lint Graph** (or the *drag-lint Graph (dockable)*
  menu item) opens a dedicated dockable window with the **live graph embedded
  in-place** — so you can dock it beside the Structure window and keep both
  visible. (It hosts `drag_lint_graph.exe` as a child; single-click a node to
  jump to its source in the IDE.)

## Editor features (drag-lint menu)

- **Hover at Cursor** — Code-Insight-style popup: kind, full signature with
  parameter types and return type, **all overloads**. The dwell popup also
  appears automatically; it clears when you move ~1 line / ~3 chars away or
  leave the editor, and won't linger over other panes.
- **Show Completion**, **Show Signature Help**.
- **Rename Symbol…**, **Format with YADF**.
- **drag-lint Options...** -- opens the IDE's native **Tools > Options** dialog
  focused on the drag-lint pages (see "Settings" below). Replaces the old
  standalone "Settings..." modal, which has been removed.

## Settings

**drag-lint > drag-lint Options...** (or **Tools > Options > Third Party >
drag-lint** directly) opens four sub-pages:

- **General** -- `drag-lint.exe` path, DB path template, workspace mode, and
  the auto-compile toggles.
- **Indexer** -- auto-index/auto-reindex, scan libraries, extra index DB
  paths, auto-discover DBs, include library DB.
- **Linter** -- diagnostics + inline-marker toggles, plus **Max return cases**
  (how many distinct return cases AutoDoc's generated `<returns>` comment
  enumerates; manifest-backed, not a registry setting).
- **Editor** -- hover, hover tooltip, completion, signature help, code lens.

All fields are per-user (Windows registry) except Max return cases, which is
read from and written to the manifest (project-local `.drag-lint.json` when a
project is open, otherwise the global `drag-lint.json` beside the exe). See
`docs/INSTALL.md` for the full "Where to configure X" table.

### Per-project lint rules

Right-click a project node in the **Project Manager** and choose
**"drag-lint: Project Rules..."** to activate that project and open the
drag-lint dock's **Lint Options** tab, scoped to that project's
`drag-lint-lint.json` (enable/disable rules, set severities, thresholds,
profiles). You can also hand-edit the file directly -- see `rules/README.md`.

### Diagnostics on save
On save (auto, debounced) drag-lint republishes **lint warnings/infos** for the
file → gutter markers + squiggles + the Structure **Diagnostics** node.
(Reliable lint findings are auto-published; tree-sitter "syntax errors" are not,
because the grammar still false-positives on valid code — real syntax errors
come from the compiler / **Compile && Diagnose**.)

### Compile & Analysis (bottom of the menu)
**Compile && Diagnose** and **Compile Buffer (unsaved)** -- the two daily
actions.

### About (bottom of the menu)
Versions, connection health, **which indexes are actually in use**, configuration
warnings and process footprint, plus a **Diagnose Current State** report you can
copy into an issue. The diagnostic actions that used to sit under a
*Diagnostics & Tests* header -- Run Diagnostics, Run AST Checks, Lint Buffer,
Copy Diagnostics, Recover Buffer Files, Import Build Log, Open Plugin Log -- are
now buttons here.

If the menu caption reads **`drag-lint (!)`**, the LSP server is down; About's
Connections group says why. There is no longer a modal dialog for this.

## The CLI

`drag-lint <command> [args]`. Common ones:

| Command | What |
|---|---|
| `index <path> --db <f> [--deep\|--shallow]` | Build/update an index. Deep = capture usage refs. |
| `scan-all [--dry-run]` | Build the 3-dictionary layout from `.drag-lint.json`. |
| `query --name <X> --db <f>` | Exact symbol lookup (fuzzy fallback on a miss). |
| `query find-callers --name <X>` | Every site that references `<X>`. |
| `usages --name <X> --width narrow\|wide\|very-wide` | Grouped usages incl. reads/writes (deep DB). |
| `outline --file <f.pas> --format json` | All symbols in one file (kind/name/line). |
| `surface --qname <Foo.TBar>` | A class/record/interface's member surface. |
| `slice --qname <X>` / `context --task "modify <X>"` | Symbol-relevant source chunks / context bundle. |
| `impact --qname <X> [--depth N]` | Transitive-caller blast radius. |
| `graph --format dot\|mermaid` | Unit dependency graph. |
| `cycles [--edges]` | Circular unit deps; `--edges` shows the exact `uses` lines + move/layering candidates. |
| `uses-audit <unit.pas>` | Propose interface→implementation moves + unused units. |
| `uses-fix <unit.pas> --project <dproj> [--apply] [--remove-unused]` | Uses cleanup (dry-run default; `.bak` on apply). No `<unit>` = sweep report. **Verify is best-effort — do a full build after `--apply`.** |
| `check-unit <unit.pas> --project <dproj> [--shadow <dir>] [--resolve-uses]` | Real semantic errors for one unit (incl. unsaved buffer via `--shadow`). |
| `todos <path>` / `diff <dbA> <dbB>` | TODO scan / API-impact diff between two indexes. |
| `lint <path>` / `check-ast <path>` | Lint rules / tree-sitter syntax check. |

Add `--db <f>` (repeatable for multi-DB) and `--format json` where relevant.

### Deep vs shallow
- **Deep** (your projects): records identifier usages → Find Usages of
  variables/components works. ~doubles ref count; fine for project DBs.
- **Shallow** (libraries): definitions + calls + types only. Smaller, fast.
- Per-save reindex uses `--deep` so saved files keep their usage refs.

### Scan hygiene (applies to `index` folder scans + `scan-all`)
- `.scanignore` marker file → that folder + subtree skipped.
- Any `*BACKUP*` folder skipped.
- Among `.sql`, only `MS*.SQL` indexed (Firebird DDL; no SQL grammar needed).
- `.inc` include files **are** indexed (so include-file consts/types are found).
- `__history` / `.git` / `node_modules` pruned.

## Tips
- Exact lookups are ~sub-second; a fuzzy miss on the 1.5M-symbol library is
  ~0.2–1.7 s.
- Re-run `scan-all` after big code changes; everyday edits stay fresh via the
  per-save reindex.
