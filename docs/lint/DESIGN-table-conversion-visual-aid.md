# Design note: table conversion via a visual rule-authoring aid

Status: **idea / not scheduled.** Captured 2026-07-10 from a user observation
during the VARINSP button-conversion work. This is the escalation path from the
current property-remap `convert-apply` to *structural* table conversion
(`TOvcTable` -> unbound `TcxGrid`). See also `docs/TCXGRID-UNBOUND-GUIDE.md`
(the target-side how-to) and `docs/CONVERSION-RULES.md` / `docs/AI-CONVERT-RUNBOOK.md`
(the current engine).

## The observation

The Orpheus `TOvcTable` structure is close to an unbound `TcxGrid`: both are a
**fixed grid of typed cells with per-column definitions**. If we build a *visual
aid* for authoring conversion rules, a human could map the table structure once
and the engine could convert most tables mechanically from that map.

## Why the structures line up

| Concept | Orpheus `TOvcTable` | Unbound `TcxGrid` |
|---------|---------------------|-------------------|
| The grid | `TOvcTable` | `TcxGrid` + `TcxGridTableView` (+ `TcxGridLevel`) |
| A column | `TOvcTCColHead` + a cell-type object | `TcxGridColumn` + `Properties`/RepositoryItem |
| Header text | `TOvcTCColHead` caption | `Column.Caption` |
| Cell type | which `TOvcTC*` class is attached | which `TcxXxxEditProperties` |
| Fixed rows | table row count | `DataController.RecordCount` |
| Cell data | `OnGetCellData` / stored array | `DataController.Values[r,c]` |

Cell-type family mapping (mirrors the `docs/TCXGRID-UNBOUND-GUIDE.md` table):

| Orpheus cell type | cxGrid column editor |
|-------------------|----------------------|
| `TOvcTCString` | `TcxTextEditProperties` |
| `TOvcTCSimpleField` / `TOvcSimpleField` | `TcxSpinEditProperties` / `TcxTextEditProperties` |
| `TOvcTCBitMap` | `TcxImageProperties` |
| `TOvcTCColHead` | -> the column's `Caption` (not a column of its own) |
| in-cell button | `TcxButtonEditProperties` |

## Why it is NOT just a bigger property-remap (the honest gaps)

The current `convert-apply` is a **property-remap** engine: it rewrites one
component's properties into another's, surface by surface. An OVC-table -> cxGrid
conversion is a **structural transformation**, which is different in three ways:

1. **Cardinality change (split/merge).** One `TOvcTable` + N `TOvcTCColHead` + N
   cell-type objects (all separate DFM sub-components) collapse into ONE
   `TcxGridTableView` with N *columns*. That is the many-objects -> one-object-with-
   a-collection reshape currently listed as the DEFERRED "split/merge" case. The
   engine's 1:1 `#convert` rule model cannot express it yet.
2. **Data feed is code, not DFM.** OVC tables supply data via `OnGetCellData` /
   `OnGetCellAttributes` handlers in the `.pas`. The cxGrid equivalent is
   `DataController.Values[r,c]` population -- different *code*, not a property. The
   engine can scaffold the column structure but cannot auto-translate arbitrary
   `OnGetCellData` logic (that is the deferred expression-interpreter territory).
3. **Runtime wiring with no analog.** `TOvcController` ties the tables together;
   there is no cx equivalent, so that part is drop + manual.

## The idea: a visual rule-authoring aid (not an auto-solver)

The proposal is NOT that the engine solves the above automatically. It is a
**visual tool** where a human maps the table structure interactively, and the tool
then emits the structural conversion rules + scaffolds the column-creation code:

- Show the source `TOvcTable`'s columns (each `TOvcTCColHead` + its cell type) as
  a flat list / grid.
- Let the user assign each source column -> a target `TcxGridColumn` with a chosen
  editor type (defaulted from the cell-type mapping table above; overridable).
- Emit: (a) a NEW *structural* rule kind that says "this `TOvcTable` becomes a
  `TcxGrid`+view with these N columns" and (b) scaffolded Object Pascal that
  builds the columns in code (per `docs/TCXGRID-UNBOUND-GUIDE.md`).
- Flag the parts that need a human: the `OnGetCellData` -> `Values[r,c]` data feed
  and any `TOvcController` wiring (leave a TODO, like surface #5 does today).

This is the same tool already noted as the DEFERRED "**IDE model-editor + T-side
property-search navigator**" -- but EXTENDED from single-component property mapping
to **whole-table structural mapping**. The engine gains a new *structural* rule
kind (grid + column collection) on top of today's leaf `#link` rules.

## What this needs before it is buildable

1. A **structural rule kind** in the DSL (one source component -> one target +
   a generated column collection). This is the split/merge foundation.
2. **`proptree`-for-tables**: enumerate a `TOvcTable`'s columns + cell types from
   the index/DFM (the sub-object children), not just scalar properties.
3. The **column-scaffold code emitter** (reuse `docs/TCXGRID-UNBOUND-GUIDE.md`'s
   patterns).
4. The **visual editor** itself (the deferred IDE model-editor; own brainstorm).
5. Explicit, honest **TODO markers** for the data-feed + controller parts the tool
   cannot translate -- "most tables", not "all tables", and never a silent gap.

## The real value proposition (user's framing)

The goal is NOT 100% automation. It is **eliminating the visual tedium**:
redrawing a `TcxGrid`, adding every column, wiring each cell's editor type, and
setting headers is hours of click-work PER TABLE. Auto-generating grid + columns +
editor types + headers from the existing `TOvcTable` turns "redraw the whole thing
by hand" into "review the generated columns + write the data feed." That is the
~80% that is pure tedium.

## Must be a REPEATABLE pipeline, not a one-off

There are **10-20 tables** to convert (VARINSP alone has 34 `TOvcTable`
instances). The tool only pays off if it is repeatable. Design implication: the
helper must be **parameterized per table** (read structure -> emit scaffold),
never hand-tuned each run, or the time saving evaporates. The deliverable is
therefore THREE things, not one:

1. A **helper** (CLI verb or engine call) that reads a `TOvcTable`'s structure
   from the index/DFM (columns, cell types, headers) and emits the cxGrid +
   column scaffold code. Parameterized by table qname/instance.
2. A **documented procedure** (a per-table runbook, like `AI-CONVERT-RUNBOOK.md`):
   run the helper -> review generated columns -> write the `Values[r,c]` data feed
   -> compile -> next table.
3. **Run it 10-20 times.** The per-table human cost must stay small and constant;
   if table #15 is as much work as table #1, the pipeline has failed.

## Verdict

Tractable, and a natural escalation once the current non-table conversion is
proven. It would convert **most** tables' *structure* mechanically and hand the
human the *data-feed* rewrite -- a large time saving over a full hand-port
(critical at 10-20 tables), with no silent correctness loss (everything
untranslatable is a visible TODO). Do NOT start it until: (a) the non-table
VARINSP conversion compiles clean, and (b) the split/merge structural-rule
foundation is designed. Belongs after the current milestone, with its own
brainstorm -- and that brainstorm must treat the REPEATABLE PIPELINE (helper +
procedure + run x20) as the primary requirement, not the single-table demo.

## OPEN brainstorm questions (the tool was brainstormed but NOT spec'd)

This tool ("transfer editor" / "component replacement package") was discussed
across the 2026-07-14 session and PAUSED TWICE (first for the uMain crash, then
to build the fresh-compiler-findings feature). The strategic decisions above are
settled; the following DESIGN questions were raised but never answered -- resume
the brainstorm here (superpowers:brainstorming):

1. **Host (the most design-shaping question).** Where does the editor live?
   - In-IDE dock (Delphi BPL, like the Lint Options / Butterfly tabs) -- native,
     sees the live project, but OTA UI not headless-testable + BPL rebuilds.
   - Standalone VCL app (a drag-lint GUI exe reading the index DBs, writing
     .rules) -- full UI control, reuses the engine, launchable from the IDE menu.
   - CLI-driven localhost web UI (CLI emits property trees as JSON, a browser UI
     does the drag-map, posts back rules) -- cross-platform, fast to iterate, no
     BPL, but a new delivery mechanism drag-lint lacks today.
   - (TUI was considered + rejected as the weakest fit for a drag-heavy task.)
   The AskUserQuestion for this was posed but the user pivoted before answering.

2. **Interaction model.** Flatten the source's deep property tree to a flat list;
   auto-assign unambiguous source->target leaves by name+type; present the
   remainder as a GRID; a **T-side property navigator WITH SEARCH** (type "font"
   -> jump to `Style.Default.Font` instead of walking each level -- the antidote
   to the proptree explosion that made hand-authoring impractical).

3. **Output.** Emits the same `conversion.rules` DSL that `convert-apply`
   consumes (so the editor is a front-end to the existing engine, not a new
   engine). Stored as DSL text; a growing rules LIBRARY seeds a new pair from a
   similar one.

## Why this jumped the queue (the trigger)

The VARINSP button conversion (`TabcToggleBtn`->`TcxButton`) proved that even a
SINGLE non-table component needs human judgment, not a mechanical remap:
`Layout`/`Style` are Orpheus enums with no cx equivalent; `Picture.Data` maps to
cx `Glyph`/`TdxSmartGlyph` (different property + type); `Images` ->
`OptionsImage.Images`; and `convert-scaffold` explodes to thousands of nested
paths (TcxButton reaches Automation/Colors/Parent/... trees). Hand-authoring
those rules is exactly the tedium this tool removes -- so the user chose to build
the editor BEFORE finishing the VARINSP conversion. The editor is therefore
needed for BOTH the (deferred) table conversions AND the current non-table ones.
Full session reasoning:
`wiki/entities/DragLint_Linter-indexer-fixes-and-fresh-findings-reasoning-2026-07-14.md`.
