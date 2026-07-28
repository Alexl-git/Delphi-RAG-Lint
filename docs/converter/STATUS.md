# Converter Editor -- STATUS / resume

**Branch:** `feat/converter-editor` (worktree `C:\Projects\Delphi-RAG-lint-converter`,
from `main@cf372f8`). **UNPUSHED** -- user holds push. Working tree: `sample.rules`
has the user's live TabcToggleBtn->TcxButton test data (229 lines) -- do NOT revert it.

Design: `docs/converter/2026-07-20-converter-editor-unit-replacement-design.md`
Plan:   `docs/converter/2026-07-20-converter-editor-unit-replacement-plan.md`

## DONE + committed (all verified)

| Commit | What | Verified |
|---|--------|------|
| `6666d1f`..`ff6b91a` | Milestone 1 -- `#use`/`#useswap`, auto-derive, Unit Rules tab, docs | model 125/0, autotest 26/0 |
| `d4070a1` | wait-cursor (hourglass on heavy handlers) + Auto-Match GLOBAL last-segment uniqueness (kills garbage pairings) | model 125/0 |
| `f65fb9c` | proptree `--refs-as-leaves`: referenced TComponent props are leaves, not expanded (owned TPersistent still expands). Editor passes the flag. | proptree autotest 20/0; TcxButton 6208->4539 |
| `4c50ef5` | tests resolve drag-lint.exe from THIS checkout (worktree-relative), not a hardcoded sibling | model 125/0 |

Builds: editor + CLI clean. Suites: model **125/0**, convert-rules **26/0**, proptree **20/0**.

**Recovered (my error, fixed):** an earlier `git checkout -- sample.rules` reverted
the user's saved matches; restored from `sample.rules.bak.2`. The Save button is
correct (backup .bak -> SaveCompleteToString ASCII/CRLF -> validate; drops only
#convert blocks with ZERO #link as scratch).

## OPEN DECISION (evidence-gated on user re-test)

The To-tree is now correct but still large (**4539 leaves** at the editor's default
depth, which truncates at depth 4). Deep OWNED DevExpress internals
(LookAndFeel 1745 / Painter 1093 / ViewInfo 680) dominate. Depth-cap is OUT (user's
real matches are 4-5 deep; going deeper explodes: depth5=28k, depth6=56k, times out).
The two principled cures, pending user's re-test verdict:
- **pragmatic denylist** -- proptree stops expanding known internal base types
  (`*Painter`, `*ViewInfo`, `TcxLookAndFeel*`). Quick, DevExpress-specific.
- **published-only** -- index per-property visibility (schema + RE-INDEX all
  libraries; visibility is NOT stored today -- `GetClassSurface` derives it by
  re-parsing source sections) then proptree filters to published. Correct, big.

## NEXT SESSION -- user's new requests (2026-07-20)

**Session 2026-07-20b (this session):** items **1 + 3 DONE** (editor-only; built +
staged `third_party/dll-win64/ConvRulesEditor.exe`, model suite still **125/0**).
Item **2 is BLOCKED** at the index level (property accessors are not indexed -- see
its note). Change is confined to `ConvRules.MainForm.pas` (UI only; `sample.rules`
untouched). Await user re-test.

### 1. Window / grid / pool sizing -- DONE 2026-07-20b (UI, `ConvRules.MainForm.pas` BuildUI)
Shipped: window 1100->1600; grid gains `goColSizing` (drag-resizeable columns) +
wider cols (From/To 330, cast 110); pool panel 280->400 with its controls anchored
akRight so they stretch; two new pool buttons (item 3) fit above Assign/Unassign.
- Widen the window (Width 1100 -> ~1550-1650).
- **Grid columns RESIZEABLE**: add `goColSizing` to `FGrid.Options`.
- Widen From/To grid columns; make the grid's client area WIDER THAN the sum of its
  column widths (currently cols sum ~590 inside a ~436 client -> clipped). Options:
  widen the middle client region (shrink left/right or grow window) and/or set
  column widths to fit with margin.
- Widen the right **pool** panel (`PoolPanel.Width` 280 -> ~360-400) and the
  library left panel as needed.
- Files: `ConvRules.MainForm.pas` BuildUI (`Width`, `LeftPanel.Width`,
  `PoolPanel.Width`, `FGrid.ColWidths[]`, `FGrid.Options + [goColSizing]`).

### 2. Filter INVALID / impossible To (target) leaves -- BLOCKED (index has no accessors)
> **BLOCKER found 2026-07-20b:** the index does NOT store property `read`/`write`
> accessors. A property Symbol's `Signature` is TYPE-ONLY (`: HWND`, `: string`,
> or empty) -- verified against `library-Win64.sqlite`: across 841 `Caption` rows
> and every `Handle` row, ZERO signatures carry a `read`/`write` token. So
> writability CANNOT be derived from the current index. The real fix needs the
> tree-sitter property extractor to capture the accessor clause into the symbol
> (schema/extract change) THEN a full RE-INDEX of the library DBs (Win64 lib is
> ~1.8 GB) -- i.e. the same "big" bucket as the published-only option under OPEN
> DECISION. Options: (a) do the indexer change + re-index (correct, big); (b) a
> pragmatic editor-side denylist of well-known read-only names (Handle, ComObject,
> ComponentCount, ...) -- quick but brittle, may hide a valid same-named target;
> (c) defer until the indexer work lands. NOT implemented this session.
>
> **HANDED OFF to the engine team (2026-07-20b):** thorough evidence-based design in
> `docs/converter/2026-07-20-proptree-assignability-engine-handoff.md` (copy dropped
> in the engine checkout `C:\Projects\Delphi-RAG-lint\docs\lint\`). Refined finding:
> only **writability** needs a re-index; **visibility** (in `modifiers`:
> published/public) and **concrete polymorphic type** (`TcxCheckBox.Properties` ->
> `TcxCheckBoxProperties` already captured) are proptree/CLI plumbing, NO re-index.
> Contract = proptree/2 JSON (`is_writable`, `visibility`), back-compat defaults.
>
> **2026-07-21: ENGINE SHIPPED proptree/2 (v17) + editor WIRED.** TPropLeaf gains
> IsWritable/Visibility/MemberKind; GetProptree passes `--min-visibility`; RefreshPool
> hides read-only + tags PAS-only; DFM/PAS surface combo; Auto-Match/DoAssign skip
> read-only; 30 s watchdog in RunCapture. Model suite 126/0/3-skip. BUT two engine
> blockers remain (see `docs/converter/2026-07-21-proptree-v17-integration-blockers.md`):
> (1) v17 dropped `--refs-as-leaves` -> some controls' proptree explodes/times out
> (TcxCheckBox); (2) v17 exe HARD-refuses pre-v17 project DBs -> ORM3 needs a v17
> re-index for the unit-picker/fill features. Editor works today for library targets.

- **Read-only leaves are not valid assignment targets** (e.g. `...Handle`). A To
  path is only usable if the FINAL segment is WRITABLE (and every intermediate
  segment READable). `cxButton.LookAndFeel.Painter.ClockGlass.Handle := x` won't
  compile because Handle is read-only.
- Needs proptree to expose per-leaf **read/write** (the property Signature carries
  `read`/`write` specifiers; check whether the indexer captures them, or parse the
  signature). Add e.g. `is_writable` to proptree/1 JSON; the editor's To pool
  (`RefreshPool`) then excludes non-writable leaves (or greys + blocks Assign).
- This ALSO overlaps the deep-internals noise (denylist / published-only above);
  read-only filtering + denylist together would cut most of the useless deep paths.
- Files (engine): `src/report/DRagLint.Convert.PropTree.pas` (emit writability),
  `src/cli/DRagLint.CLI.pas` (JSON field). Editor: `ConvRules.Engine.pas`
  (`TPropLeaf` gains a flag, ParseProptreeJson reads it), `ConvRules.MainForm.pas`
  (`RefreshPool` filter + `DoAssign` guard).

### 3. To-search helper buttons -- DONE 2026-07-20b (UI, `ConvRules.MainForm.pas`)
Shipped both: **"Find in From by name"** (`DoFindInFrom`) selects the From-grid row
whose last-segment name matches the highlighted pool leaf; **"Only this type" /
"Show all types"** (`DoOnlyType` + `FPoolTypeFilter`, applied in `RefreshPool`,
auto-cleared on block load) toggles the pool to one type. Helper fns `TypeOfCell` /
`LeafNameOf` added beside `PathOfGridCell`.

Original spec (for reference):
Next to the pool search box (`FPoolFind`), for the currently highlighted pool leaf:
- **"Find in From by name"** button -- copy the highlighted To leaf's bare name into
  a From-side filter and select/scroll the matching From grid row (align From<->To by
  name).
- **"Only <type>" button** -- filter the pool to leaves whose TYPE matches the
  highlighted leaf's type (e.g. highlight `Popup: Boolean` -> show only Boolean
  To leaves). Extend `RefreshPool`'s filter to accept an optional type constraint;
  the button toggles it from the highlighted leaf's `TPropLeaf.TypeName`.
- Files: `ConvRules.MainForm.pas` (pool panel buttons, `RefreshPool` type-filter,
  a From-grid select-by-name helper).

## Build / test quick ref
- Editor: `dcc64 -B ConvRulesEditor.dpr` in `src/tools/convrules-editor/` (worktree
  paths; the repo `build/_build_convrules_editor.bat` hardcodes the MAIN checkout --
  use a worktree wrapper, e.g. in the session scratchpad).
- Tests: `dcc64 -B -NS... ConvRulesModelTests.dpr` in `.../tests/`; run exe ->
  `model-tests: N pass / 0 fail`.
- CLI: `build/build_draglint_win64.bat` (relative-path safe) -> stages
  `third_party/dll-win64/drag-lint.exe`.
- Autotests: `tests/autotest/run_proptree.ps1` / `run_convert_rules.ps1`
  `-Exe <deployed drag-lint.exe>` (the `src/cli/Win64/Debug/` copy crashes -- missing
  tree-sitter DLL beside it). Both flip `$ErrorActionPreference='Continue'` for the
  exe's `(loaded defaults)` stderr note.

## Phase 2 (later, unchanged)
`convert-apply` executes `#use`/`#useswap` on a real `uses` clause (normalization
already implemented pure in `ConvRules.Units.NormalizeUnitSets`). Then DFM inventory,
value/enum casts, AI apply-by-name.
