# Unified Search Tab (IDE plugin) - Design

**Date:** 2026-06-23
**Component:** RAD Studio IDE plugin (`src/delphi-plugin`), dockable "drag-lint" panel.
**Goal:** Add a single, human-oriented **Search** tab to the dockable panel: a *kind* dropdown + a query field + one clickable results grid. It is a friendly front-end over the existing `drag-lint` query commands (`query --name`, `query --text`, `usages`), with click-to-jump navigation and a clean empty state (no diagnostic dumps).

## Motivation

The panel already has **Find Usages** and **Symbol Search** tabs, each hard-wired to one command. In practice users hit the 0-results path and see only the `== DEBUG ==` diagnostic block (Find Usages) or a bare "0 result(s)" (Symbol Search) - usually because they searched a symbol the index does not capture (locals/params) or no project DB was resolved. This design adds one discoverable Search tab that exposes the main query modes behind a dropdown and fails gracefully, and removes the debug dump from the existing Find Usages tab.

## Non-goals

- Not removing the existing Find Usages / Symbol Search tabs (decided later, based on usage). Their query/parse logic is unchanged except the empty-state cleanup.
- Not adding async/threaded queries. Queries run synchronously with a timeout, matching the existing forms (sub-second in practice).
- Not indexing locals/parameters or comments - out of scope of the index.
- No new CLI commands; this is purely a plugin UI over existing commands.

## UI layout

A `TCustomFrame`-free embed function `CreateEmbeddedSearch(AOwner: TComponent; AParent: TWinControl)` builds, top to bottom:

1. **Toolbar row (`TPanel`, alTop)** - the always-visible "simple" controls:
   - `Kind` (`TComboBox`, csDropDownList): **Symbol | Text | Usages**.
   - Query `TEdit` (alClient): placeholder "type, then Enter".
   - `Search` (`TButton`, alRight).
   - `Advanced` toggle (`TCheckBox` or small `TSpeedButton`, alRight): shows/hides row 2.
2. **Advanced row (`TPanel`, alTop, `Visible := False` by default)** - optional refinements; its controls' relevance follows the Kind:
   - Kind = **Symbol**: a `Kind filter` combo - Any / Method / Type or Class / Field or Var / Const / Property / Unit.
   - Kind = **Text**: a `Mode` combo - Phrase / Substring / Any-word; a `Source` combo - All / pas / dfm / sql.
   - Kind = **Usages**: a `Width` combo - Narrow / Wide / Very-wide.
   - Irrelevant controls for the current Kind are hidden/disabled. Switching Kind reconfigures this row.
3. **Results `TListView` (vsReport, alClient, RowSelect, FullRowSelect, ReadOnly, HideSelection=False)** - columns adapt to the active Kind (see Result model).
4. **Status `TLabel` (alBottom)** - "Type to search." / "Searching." / "N result(s)" / empty-state hint / error.

"Simple mode" = Advanced collapsed (just Kind + field + Search). "Advanced mode" = Advanced expanded; no separate toggle of dropdown contents is needed.

### Run trigger

- **Enter** in the query field, or the **Search** button, runs the query for the current Kind + refinements.
- For Kind = **Symbol** only, a 300 ms debounce on `OnChange` also runs it live (cheap; matches the old Symbol Search feel). Text and Usages run on Enter/button only (they can be heavier and a substring/usages query per keystroke is wasteful).
- Changing any Advanced control re-runs the current query if the field is non-empty.

## Search kind -> command mapping

All commands are spawned with the resolver's DB args: `ResolveActiveIndexDbs(LoadSettings)` -> one `--db "path"` per entry, exactly as the existing tabs. All use `--json` / `--format json` for robust parsing (no fragile text scraping).

| Kind | Command | Notes |
|------|---------|-------|
| Symbol | `query --name "<q>" <dbs> --json` | client-side filter by the Kind-filter combo |
| Text | `query --text "<q>" [--substring|--any-order] [--source pas|dfm|sql] <dbs> --json` | dogfoods the v0.58 text-constant index |
| Usages | `usages --name "<q>" --width <w> <dbs> --format json` | grouped JSON flattened into rows |

Timeouts: Symbol/Text 15000 ms; Usages 30000 ms.

## Result model (one flat grid + Category column)

A single internal record drives the grid so navigation is uniform:

```
TSearchRow = record
  Category : string ;  // 'Symbol' / 'Text' / 'Decl' / 'Read' / 'Write' / 'Call' / 'Type' / 'Attr' / 'Event' / 'Impact'
  ColA     : string ;  // primary text (name / matched text / detail)
  ColB     : string ;  // secondary (kind / source / qname)
  FilePath : string ;  // absolute path for navigation ('' = not navigable, e.g. Impact summary)
  Line     : Integer;  // 1-based; 0 = not navigable
end;
```

Columns shown adapt to Kind (the ListView columns are rebuilt when Kind changes):

- **Symbol**: `Name | Kind | Location` <- ColA=name, ColB=kind, Location=`file:line` from `query --name` rows (`name`, `kind`, `file`, `start_line`). Client-side kind filter maps the combo to drag-lint kind strings:
  - Method -> {method, function, procedure, constructor, destructor}
  - Type/Class -> {class, record, interface, enum, type}
  - Field/Var -> {field, var}
  - Const -> {const}; Property -> {property}; Unit -> {unit, program, package}; Any -> no filter.
- **Text**: `Text | Source | Location` <- ColA=text, ColB=source (or `source/kind`), Location=`file:start_line` from `query --text` rows (`text`, `source`, `kind`, `file_path`, `start_line`).
- **Usages**: `Category | Detail | Location` <- one row per entry across `declarations/reads/writes/calls/types/attributes/events`; `Category` from the group, Detail = `qname` (declarations) or `ExtractFileName(file)`, Location = `file:line`. `impact[]` becomes non-navigable summary rows ("depth N: C callers across U units").

Parsing is done by pure functions (testable without the IDE):
`ParseNameJson(s): TArray<TSearchRow>`, `ParseTextJson(s): TArray<TSearchRow>`, `ParseUsagesJson(s): TArray<TSearchRow>`. These live in a unit with no VCL/ToolsAPI dependency so DUnitX can exercise them.

## Navigation

Single-click selects; **double-click or Enter** on a navigable row opens the source and jumps: reuse the existing `OpenSourceAt(FilePath, Line)` (from `DragLint.Plugin.HoverForm`) which the embedded Symbol Search already uses. Rows with empty `FilePath`/`Line<=0` (Impact summaries) do nothing.

## Empty state and errors (replaces the debug dump)

- Spawn failed (exit < 0): status = `drag-lint not found or failed to start`.
- Non-zero exit / unparseable output: status = `drag-lint error (exit N)`; if stdout starts with `ERROR`, show its first line.
- Zero results: status = `No matches for "<q>"` plus a context hint:
  - no DB resolved (resolver list empty): `No project index found - run Tools > drag-lint > Lint Buffer, or set the exe/DB in settings.`
  - Symbol kind, query looks like a param/local (A- or F-prefixed, or single short token): `drag-lint indexes types, methods, fields, properties and consts - not local variables or parameters.`
  - Text kind, substring < 3 chars: `--substring needs >= 3 characters; try Any-word.`
- **No** command line / raw stdout / resolver-state dumps in normal use. (A single optional "Copy diagnostics" affordance MAY be added later; not in this scope.)

**Hard invariant:** the results grid and status line NEVER display raw JSON, command lines, or diagnostic dumps - only parsed, human-readable rows (Category/Kind + text, clickable to jump) and short status/error lines. Even when the output cannot be parsed, show a one-line error, never the raw payload. This is a checkable acceptance criterion.

### Find Usages cleanup (in scope)

Remove the `== DEBUG (v0.40.5) ==` and `== DEBUG: resolver state ==` blocks from `TDragLintUsagesForm.RunQuery` (UsagesForm.pas ~654-705). Replace with the same clean single-line empty-state + the existing scope hint (keep the helpful "looks like a parameter/field" hint; drop the command/output/FDbPaths/resolver dumps).

## Code structure

- **New** `src/delphi-plugin/DragLint.Plugin.SearchParse.pas` (System-only deps - **no VCL, no ToolsAPI** - so a DUnitX console runner can import it):
  - the `TSearchRow` record (above).
  - the three pure functions `ParseNameJson`, `ParseTextJson`, `ParseUsagesJson` (use only `System.SysUtils`/`System.JSON`/`System.Generics.Collections`).
  - the kind-filter mapping helper (combo label -> set of drag-lint kind strings).
- **New** `src/delphi-plugin/DragLint.Plugin.SearchForm.pas`:
  - `procedure CreateEmbeddedSearch(AOwner: TComponent; AParent: TWinControl);`
  - internal handler class (owns controls, runs queries, fills grid) modeled on `TSymbolSearchHandler`; calls into `SearchParse` for all parsing so the form holds only UI + orchestration.
- **New shared** `src/delphi-plugin/DragLint.Plugin.ProcRun.pas`: extract the duplicated `RunCapture`/`RunCaptureStdout` stdout-capture helper (identical in UsagesForm and SymbolSearchForm) into one exported `function RunCaptureStdout(const ACmdLine: string; out AOutput: string; ATimeoutMs: Integer): Integer;`. Update UsagesForm and SymbolSearchForm to use it (delete their private copies). Avoids a third duplicate.
- **DockForm** (`DragLint.Plugin.DockForm.pas`): add `FTabSearch2 := AddTab('Search');` and `CreateEmbeddedSearch(Self, FTabSearch2);` in `HandleInitTimer` (guarded like the others). Place the Search tab first or second per preference (default: after Structure, before Find Usages).
- **Package**: add the new unit(s) to `dclDragLintWizard.dpk`/`.dproj` (a new unit needs BOTH the `.dpk`/`.dpr` contains/uses AND the `.dproj <DCCReference>`, else F2613).

## Testing

- **DUnitX (no IDE needed):** unit-test the pure parsers against captured JSON fixtures (the exact shapes are recorded in this spec):
  - `query --name --json`: array of `{kind,name,qualified_name,file,start_line,...}`.
  - `query --text --json`: array of `{file_path,start_line,source,kind,text,enclosing,...}`.
  - `usages --format json`: `{declarations[],reads[],writes[],calls[],types[],attributes[],events[],impact[]}` with per-entry `file/line/col` (and `qname` on declarations).
  - Assert row count, Category, ColA/ColB, FilePath/Line; and the kind-filter mapping (Method matches function/procedure/etc.).
- **Manual IDE checklist** (append to `docs/TEST-CHECKLIST.md`): build+install BPL; open the Search tab; for each Kind run a known query and confirm results + double-click navigation; confirm empty-state shows a hint (not a dump); confirm Advanced reveals the right refinements per Kind.

## Risks / open items

- Synchronous spawn blocks the IDE UI thread up to the timeout. Acceptable (matches existing; queries are fast); threading is a future enhancement.
- `query --name` is exact-name; fuzzy/substring symbol matching is a possible later addition (the index has `FindSymbolsFuzzy`, but no CLI flag exposes it yet). Out of scope.
- Column rebuild on Kind change must clear `TListView.Columns` and re-add; verify no flicker/leak.

## Version

Plugin/CLI version bump is not required for a plugin-only UI addition; if a release is cut, note "unified Search tab" under the next alpha.
