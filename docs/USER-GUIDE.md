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
- **Settings…**.

### Diagnostics on save
On save (auto, debounced) drag-lint republishes **lint warnings/infos** for the
file → gutter markers + squiggles + the Structure **Diagnostics** node.
(Reliable lint findings are auto-published; tree-sitter "syntax errors" are not,
because the grammar still false-positives on valid code — real syntax errors
come from the compiler / **Compile && Diagnose**.)

### Diagnostics & Tests (bottom of the menu)
Run Diagnostics, Run AST Checks, Lint Buffer, Compile && Diagnose, Import Build
Log, Test Connection, Open Plugin Log.

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
