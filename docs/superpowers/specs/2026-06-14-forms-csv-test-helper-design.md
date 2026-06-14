# Test Helper CSV (form navigation map) - design

Date: 2026-06-14
Status: approved (brainstorming), pending implementation plan
Topic owner: drag-lint
Primary consumer: Micronite QA / testers (ORM3 CLIENT)

## 1. Goal

Add a drag-lint tool, callable from the **drag-lint IDE menu** (CLI as a bonus),
that emits a **test-helper CSV** for the currently active project. One row per
navigable form, describing what the form is and - the headline feature - **how a
tester reaches it from the application's main form**, with the actual button /
menu captions to click.

Motivation: Micronite will grow to 200+ forms whose unit names do not reveal how
to open them. Even experienced testers need navigation instructions to know which
form a row refers to. This tool automates the navigation-chain report.

## 2. CSV contract

One row per navigable form. Columns, in order:

| # | Column        | Source / meaning |
|---|---------------|------------------|
| 1 | `#`           | Sequential row number (1, 2, ...). |
| 2 | `Unit`        | The `.pas` unit name (paired with the form's `.dfm`). |
| 3 | `FormName`    | Design-time form Name (from `.dproj <Form>` / DFM header). |
| 4 | `PAS lines`   | Line count of the paired `.pas` file. |
| 5 | `Navigation`  | Path from the main form to this form, e.g. `frmMAIN -> 'Jobs' -> 'Open Drawing'`. |
| 6 | `Called From` | Distinct direct parent forms that launch this form, with caption if resolved; `;`-separated. |
| 7 | `Notes`       | Reserved. Blank for now (engine may add hints such as `unreachable`). |

CSV dialect: RFC 4180 - comma delimiter, fields quoted when they contain a comma,
quote, or newline; embedded quotes doubled. ANSI encoding (project convention).

## 3. Scope decisions (locked during brainstorming)

- **Caller:** IDE menu is the main entry point; a `forms-csv` CLI command is a
  bonus and the single tested entry to the engine.
- **Source of forms:** the active IDE project. The menu does a **Save-All first**;
  the report therefore reflects last-saved DFMs (acceptable for a test helper).
- **Row scope:** **forms and dialogs only** (`TForm` / ribbon-form / dialog
  descendants). Data modules (`TDataModule`) and frames (`TFrame`) are excluded.
- **Unresolved hops:** **keep the chain, mark the gap.** A hop with no captioned
  control renders as `(via <RoutineName>)` so the path stays connected end to end.
- **Path count:** one representative (shortest) path per form. Alternate entry
  points surface only via the `Called From` column.
- **Root/anchor:** auto-detected main form (Micronite client = `TfrmMAIN`,
  created in `CLIENT\Micronite2027.dpr`). `--root` overrides.

## 4. Architecture

Approach: the IDE menu shells out to `drag-lint.exe` (matches all existing menu
items), but the engine lives in its own unit so the CLI command is the single
entry to it. Upgradeable later to an in-process / live-buffer variant without
reworking the engine.

New unit: `src/.../DRagLint.FormsMap.pas` - the engine (inventory + graph + caption
resolver + path builder + CSV writer). Thin wiring in `DRagLint.CLI.pas`
(`DoFormsCsv`) and in the plugin menu (`DragLint.Plugin.Editor.pas`).

Reused: the recursive enclosing-routine resolution already proven in
`TSQLiteSymbolStore.FindTransitiveCallers` (`refs.start_line BETWEEN
symbols.start_line AND symbols.end_line`) - the same span-containment trick maps a
launch site to the routine that contains it.

### 4.1 Form inventory
From the active project: `.dproj <DCCReference>` entries carrying
`<Form>Name</Form>` + `<FormType>dfm</FormType>`, cross-checked against the `.dpr`
`Unit in '...' {Form}` list. Keep only `TForm` / ribbon-form / dialog descendants
(ancestry resolved from the index symbols); drop `TDataModule` and `TFrame`.
`FormName` taken from `<Form>` (fallback: DFM header `object <Name>: <Class>`).

### 4.2 Edge detector (form -> form graph)
For each form class `TfrmY`, find references to the class name in `refs`, then
**classify each by reading the referenced source line**:

- **Launch (creates an edge):**
  - named or default constructor: line contains `TfrmY.Create` (covers MDI named
    constructors such as `CreateForFolder`, confirmed in `uJobList.pas:1678`);
  - `Application.CreateForm(TfrmY, ...)`;
  - `.Show` / `.ShowModal` invoked on a variable of type `TfrmY`.
- **Ignore (not a launch):** `is TfrmY`, `as TfrmY`, `TfrmY(...)` casts,
  var/field/type declarations, and existence checks such as
  `MDIChildren[I] is TfrmBlueprint4` (`uJobList.pas:1665`).

For each launch site, resolve the **enclosing routine** `R` (span containment) and
`R`'s owning form class `X`. Emit edge `X --[R]--> Y` (carry the handler name `R`).

### 4.3 Caption resolver (DFM)
For an edge `X --[R]--> Y`: open `X.dfm` (text), find the control whose
`OnClick` / `OnExecute` / `OnDblClick` (etc.) equals `R`, read its `Caption`
(strip `&` accelerators). Resolve action indirection: if a control has
`Action = SomeAction` and no own handler, follow to the linked `TAction` - caption
from the action, real handler = the action's `OnExecute`.

Surfaces mined: `TMenuItem`, `TdxBarButton` / `TdxBarLargeButton` /
`TdxBarSubItem`, `TButton` / `TcxButton` / `TBitBtn` / `TSpeedButton`, `TAction`.

If no captioned control binds `R`, the hop renders as `(via R)` (keep-the-gap).

### 4.4 Path builder
BFS from the root form over the edge graph; shortest path to each `Y`. Cycle-safe
via a visited set. Render hops joined by ` -> `, each hop being the resolved
caption (`'Jobs'`) or `(via R)`. If `Y` is unreachable from the root, set
`Navigation = (no path from MAIN)` and rely on `Called From`.

### 4.5 Called From
Distinct direct predecessor forms of `Y` (the `X` set), each with its resolved
caption if available; `;`-separated. This is the one-hop, all-parents view that
complements the single representative `Navigation` path.

### 4.6 CSV writer
Assemble rows **sorted alphabetically by `FormName`** (stable, lets a tester find
a form fast); the `#` column is assigned after sorting. Apply the dialect from
section 2; write to `--out` (CLI) or a chosen path (IDE).

## 5. Entry points

CLI:

```
drag-lint forms-csv --project <X.dproj> [--out <file.csv>] [--root <TfrmMAIN>] [--db <index.sqlite>]
```

IDE menu: **drag-lint -> Generate Test Helper CSV...**
1. Save-All (so on-disk DFMs match the editor).
2. Resolve the active project's `.dproj` (ToolsAPI `GetActiveProject`).
3. Shell out to `drag-lint.exe forms-csv --project <that> --out <chosen>`.
4. Open the resulting CSV.

## 6. Root detection

Parse the `.dpr`: the first `Application.CreateForm(T<class>, ...)` whose class is
a form (skip data modules such as `dmStyles`) and which precedes `Application.Run`.
Micronite client yields `TfrmMAIN`. `--root` overrides for edge cases.

## 7. Limitations / caveats

- Reflects **last-saved** DFMs (the menu Save-Alls first to minimise surprise).
- Forms opened purely via a string/enum registry key (no class token at the call
  site) cannot be auto-linked -> `(no path from MAIN)`. Rare in Micronite, which
  uses direct constructors.
- **Text DFMs assumed** (confirmed for ORM3). Binary DFMs are out of scope.
- One representative path per form; alternates appear only in `Called From`.
- Caption resolution is best-effort over the listed surfaces; programmatically
  built menus / dynamically assigned handlers fall back to `(via R)`.

## 8. Testing strategy

- **Engine unit tests** against small fixtures: a synthetic index + DFM set with
  (a) a direct `ShowModal` chain, (b) an MDI named-constructor chain, (c) an
  action-indirection button, (d) an unresolved (code-only) hop, (e) an
  unreachable form, (f) a cycle. Assert the exact `Navigation` / `Called From`
  strings and CSV escaping.
- **CLI smoke test:** run `forms-csv` against the real ORM3 index + project; spot
  check `frmMAIN`, `frmBlueprint4` (MDI), and a known dialog.
- The CLI command is the test seam; the IDE menu is a thin shell over it.

## 9. Out of scope (YAGNI)

- Live unsaved-buffer DFM reading (the C variant) - deferred; Save-All covers it.
- Multiple / all navigation paths per form - `Called From` is enough.
- Data modules and frames as rows.
- Auto-filling the `Notes` column with anything beyond optional engine hints.
- Round-tripping captions back into the IDE (this is a one-way report).
