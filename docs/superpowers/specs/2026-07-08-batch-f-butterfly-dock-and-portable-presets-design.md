# Batch F -- Butterfly call-graph dock tab + portable naming presets (design)

**Date:** 2026-07-08
**Status:** Approved (design); ready for implementation plan
**Prior art:** Batches A-E (v0.94 -> v0.98.0-alpha). This is the next autonomous
batch, targeting **v0.99.0-alpha**.
**Excluded (deferred, by user decision):** ref-gap E (type-annotation /
impl-header type refs -- SUPERVISED core-parser change, its own session);
Track 5.3 architectural charts (largest single item); Track 3 component
conversion. The two backlog "cleanup" candidates are **already done** (the
orphaned singular `OptionsFrame.pas` is gone; the Linter-page manifest write is
already `TEncoding.UTF8`).

---

## 1. Goal

Two independent, IDE-side features, both requiring a Win32 BPL rebuild and a
live-IDE smoke pass:

- **F1 (primary):** an in-Delphi **butterfly call-graph dock tab** -- callers
  above, callees below the root symbol -- rendered natively in the drag-lint
  dock, with **no** dependency on the external `drag_lint_graph` viewer. Driven
  by (a) an editor action + keybinding and (b) selecting a symbol in the
  existing Structure tab.
- **F2 (secondary):** **save-your-own naming presets**, persisted portably in
  `drag-lint.json` so they travel with the repo (and a future CLI feature could
  read them). Extends the existing Embarcadero/House/Custom combo on the dock
  Lint Options page.

Both reuse shipped engine primitives; **no new analysis engine** is introduced
(same policy as Track 5). The only new engine code is a thin forward-tree
builder that mirrors the shipped reverse-tree builder (see F1 data layer).

---

## 2. F1 -- Butterfly call-graph dock tab

### 2.1 Data layer

- **Callers (upper half):** reuse the shipped `BuildReverseCallTree`
  (`src/report/DRagLint.Report.RCallTree.pas`), which already returns a
  `TRCallTree` of `TRCallNode` records (QName, Site, SiteFile, SiteLine, Cycle,
  Callers) with cycle-guarding and a depth cap.
- **Callees (lower half):** the callees traversal already exists but is
  currently implemented *inline in the CLI* (`RenderCallGraphText` in
  `DRagLint.CLI.pas`, following `GetCallEdgesFromSymbol.TargetSymbolId`), not as
  a reusable engine record. **Add a thin `BuildForwardCallTree`** to
  `DRagLint.Report.RCallTree.pas`, mirroring `BuildReverseCallTree` exactly:
  same `TRCallNode` shape, same global-visited cycle policy, same depth cap, but
  following `GetCallEdgesFromSymbol` (outgoing) instead of
  `FindResolvedCallers` (incoming). Field reuse: for a forward node, `Callers`
  holds the *callees* (the record field name stays `Callers` to avoid churning
  the record; the renderer knows the direction). This keeps the dock tab's two
  halves rendering uniformly from one record type and gives F1 a
  **headless-testable** engine function.

> **Note carried to planning:** confirm `GetCallEdgesFromSymbol` returns call
> sites (unit:line) so forward nodes can populate `Site`/`SiteFile`/`SiteLine`
> for double-click navigation, exactly as reverse nodes do. `RenderCallGraphText`
> already recurses over it, so the data is present; the builder just needs to
> capture the site the way `Expand` does in `BuildReverseCallTree`.

### 2.2 UI

- A new tab `FTabButterfly` in `TDragLintDockFrame`
  (`DragLint.Plugin.DockForm.pas`), created via the existing `AddTab` +
  `TPageControl` pattern. Caption: **"Call Graph"**. (Slots in next to the
  already-declared-but-unused `FTabGraph`; do not disturb `FTabGraph`.)
- Inside the tab: a single read-only `TTreeView` copying `StructureForm`'s
  proven idiom -- `ReadOnly:=True`, `ShowLines:=True`, `HideSelection:=False`,
  `OnDblClick` navigation, an `OnMouseDown`/popup if useful. Structure:
  - A header line naming the root symbol (e.g. `Root: Unit.TFoo.Bar`).
  - Two top-level roots: **`Callers (N)`** and **`Callees (N)`**, each expanded
    to the depth cap.
  - Cycle re-encounters marked with the same `(cycle)` suffix convention used
    by the text / Messages reverse-calltree report.
- **Double-click a node** -> jump to that node's call site
  (`SiteFile`:`SiteLine`), reusing the navigation path proven by the Batch E
  `AddToolMessage` clickable-Messages flow (open the file + position the caret).
  The root and any node with an empty site are non-navigating.
- Empty states: if the root resolves but has zero callers and zero callees,
  show both roots with `(0)` rather than an error.

### 2.3 Invocation (both paths)

- **Editor action `InvokeButterfly`** (mirrors the shipped
  `InvokeReverseCallTreeMessages` in `DragLint.Plugin.Editor.pas`): resolve the
  symbol at the caret -> build the tree on a **background thread**
  (`RunAndCaptureStdout` of the CLI, or an in-process store query where the
  existing actions already do so -- follow whatever the reverse-calltree action
  does), marshal back via `TThread.Queue`, populate `FTabButterfly`, and select
  the tab so it surfaces. Bind to:
  - **Ctrl+Alt+B** keybinding (`DragLint.Plugin.Keyboard.pas`, alongside the
    existing H/C/S/D/I/R/F/T/K set; needs the Editor-unit forward decl the same
    way Ctrl+Alt+K did).
  - A **"Call Graph (Butterfly)..."** menu item under the existing
    *Uses & Dependencies* submenu.
- **Structure-tab-driven:** selecting a symbol node in the embedded
  `StructureForm` populates the butterfly tab with that symbol as root. Reuse
  `StructureForm`'s existing `EnumQNameForNode` (or equivalent selection->qname
  helper) to obtain the root qname, then call the same populate routine the
  editor action uses. This must **not** steal focus / self-select the dock (heed
  the Batch D T9 dock-focus lesson).

### 2.4 Process rule (carried from the Batch E incident)

Every BPL-building subagent prompt in this batch MUST include the explicit rule:
**"DO NOT close the user's RAD Studio. If the BPL is locked, STOP and report
BLOCKED."** No subagent may autonomously close the IDE to clear a lock.

---

## 3. F2 -- Save-your-own naming presets (portable, in `drag-lint.json`)

### 3.1 Storage / schema

Saved presets live in the manifest under a new key **`naming.presets`**: an
array of objects

```json
{
  "naming": {
    "presets": [
      {
        "name": "My house style",
        "values": {
          "param_prefix": "p", "field_prefix": "F", "class_prefix": "T",
          "exception_prefix": "E", "interface_prefix": "I", "pointer_prefix": "P",
          "method_case": "PascalCase", "local_case": "PascalCase"
        }
      }
    ]
  }
}
```

The 8 `values` keys are exactly the existing `NAMING_PRESET_PARAMS` bundle
columns in `DragLint.Plugin.LintOptionsFrame.pas` (param_prefix, field_prefix,
class_prefix, exception_prefix, interface_prefix, pointer_prefix, method_case,
local_case).

Persistence reuses the **existing** manifest read-modify-write path already used
for `docs.max_return_cases` in `DragLint.Plugin.OptionsFrames.pas`:

- `ManifestPathForWrite` chooses the dotted `.drag-lint.json` beside the
  `.dproj` when a project is open, else the undotted global `drag-lint.json`
  beside the **real** `drag-lint.exe` (via `DragLintExe`, never `ParamStr(0)`).
- Direct `System.JSON` RMW: read whole doc, `RemovePair`-before-`AddPair` on the
  `naming` object so re-saves don't duplicate, preserve all sibling keys
  (`docs`, `settings`, ...), write `Root.ToJSON` as `TEncoding.UTF8`.
- **No** `TManifestIO` dependency (matches how the Linter page already avoids it
  to prevent key merge/drop).

**Consequence (documented, acceptable):** with a project open, presets are
project-scoped (dotted file), identical to `max_return_cases` behaviour. Saving
with no project open writes the global manifest and makes the preset available
everywhere. This is consistent, not a bug.

### 3.2 UI (on the existing naming preset combo)

The combo in the dock Lint Options naming group currently lists **Embarcadero /
House / Custom**. It grows to:

`[ built-in presets ] + [ each saved preset, by name ] + [ Custom ]`

Add two small buttons beside the combo:

- **Save as...** -- `InputQuery` for a name, capture the current 8 field values,
  RMW into `naming.presets` (overwrite if the name already exists), refresh the
  combo, select the new entry.
- **Delete** -- remove the selected *saved* preset from `naming.presets`,
  refresh the combo. Disabled when a **built-in** or **Custom** is selected.

Behaviour:

- **Selecting** a saved preset applies its 8 values through the existing
  `ApplyPreset` / `FApplyingPreset`-guard path. Internally the preset source
  becomes: built-ins from the hardcoded `NAMING_PRESET_BUNDLES` array **plus**
  saved ones loaded from the manifest at frame load / after each Save/Delete.
- **`DetectAndSetPreset`** on load matches the current field values against
  built-ins **and** saved presets; falls back to **Custom** when nothing matches
  (unchanged fallback semantics).

### 3.3 Scope guard (YAGNI)

The CLI **reading** `naming.presets` is **out of scope** for this batch. We only
make the format portable so a future CLI feature *could* consume it. Batch F is
IDE-write + IDE-read only. Do not add a CLI verb or CLI parsing for presets.

---

## 4. Testing & verification

### 4.1 Headless-testable (automatable gates)

- **F1 forward-tree engine test** -- a PowerShell autotest for
  `BuildForwardCallTree` mirroring `run_reverse_calltree.ps1`: assert callees
  tree shape, depth cap, and cycle policy on a known fixture. (This is why we
  add the engine builder rather than only inline CLI code -- it gives F1 real
  headless teeth.)
- **F2 manifest round-trip test** -- a PowerShell autotest mirroring
  `run_docs_manifest_roundtrip.ps1`: write a `naming.presets` entry via the same
  direct-JSON RMW logic, read it back, assert the 8 values survive **and** that
  sibling keys (`docs`, `settings`) are preserved (RemovePair/AddPair teeth).
- **Full existing battery** re-run to confirm no regression (the ~8 scripts
  green in the last handoff: `run_reverse_calltree`, `run_self_field_refs`,
  `run_bare_rhs_refs`, `run_naming_prefix_autofix`, `run_naming_autofix`,
  `run_deps_report`, `run_manifest`, `run_fixable_catalog`).

### 4.2 NOT headless-testable -> user live-IDE smoke checklist

IDE OTA UI cannot be verified headlessly. The user runs these with the rebuilt
BPL loaded:

- **F1-a:** cursor on a symbol -> Ctrl+Alt+B -> the "Call Graph" dock tab
  surfaces with Callers/Callees populated for that symbol.
- **F1-b:** *Uses & Dependencies -> Call Graph (Butterfly)...* does the same.
- **F1-c:** select a symbol in the Structure tab -> the butterfly tab updates to
  that root (dock does NOT self-select / steal focus -- Batch D T9 watch).
- **F1-d:** double-click a caller and a callee node -> caret jumps to the call
  site; root / empty-site nodes do nothing.
- **F2-a:** set the 8 naming fields, **Save as...** "X" -> combo shows "X"
  selected; the manifest (`.drag-lint.json` or global) contains
  `naming.presets[X]`.
- **F2-b:** switch to Custom then back to "X" -> the 8 fields restore.
- **F2-c:** **Delete** "X" -> combo drops it; Delete disabled on built-ins /
  Custom.
- **F2-d:** reload the frame -> saved presets reappear from the manifest;
  editing a field flips the combo to Custom.

### 4.3 Build & release

- Win32 BPL rebuild via the delphi-build recipe (rsvars -> cd -> msbuild,
  PowerShell `Start-Process -Wait`, check `BUILD_EXITCODE=0` + no `[dcc] Error`),
  **RAD Studio CLOSED** (BPL lock). Deploy to `third_party/dll-win32/`.
- CLI Win64 Debug rebuild if `RCallTree.pas` changed (it does -- new
  `BuildForwardCallTree`); deploy to `src/cli/Win64/Debug/` +
  `third_party/dll-win64/`.
- Version bump `DRagLint.CLI.pas` `VERSION` `0.98.0-alpha` -> `0.99.0-alpha`;
  update CHANGELOG / README / AI docs.
- Final whole-branch opus review, then pack + GH release (both CLI zips + Win32
  BPL). **User drives `git push` and the release cut.**

---

## 5. Execution model

**superpowers:subagent-driven-development.** F1 and F2 are independent (disjoint
units, no shared state), so their engine/logic pieces build in parallel; the
single BPL rebuild + the combined live-smoke checklist happen once at the end.
Every BPL-building task prompt carries the "DO NOT close RAD Studio -> report
BLOCKED" rule (section 2.4).

### Units touched (indicative, confirmed in planning)

- **F1:** `src/report/DRagLint.Report.RCallTree.pas` (+`BuildForwardCallTree`);
  `DragLint.Plugin.DockForm.pas` (new `FTabButterfly` + populate routine);
  `DragLint.Plugin.Editor.pas` (`InvokeButterfly`); `DragLint.Plugin.Keyboard.pas`
  (Ctrl+Alt+B); `DragLint.Plugin.StructureForm.pas` (selection -> populate hook);
  menu wiring. New test `tests/autotest/run_forward_calltree.ps1`.
- **F2:** `DragLint.Plugin.LintOptionsFrame.pas` (combo + Save as.../Delete +
  manifest RMW for `naming.presets` + preset source merge +
  `DetectAndSetPreset`). New test `tests/autotest/run_naming_presets_roundtrip.ps1`.
- **Docs:** README (Call Graph tab + Ctrl+Alt+B + saved presets), CHANGELOG,
  AI-USAGE / AI-INDEX-FIRST (note presets are a manifest key; the butterfly is
  IDE-only, no CLI verb), INDEX-SCHEMA / manifest doc if it enumerates keys.

---

## 6. Out of scope / deferred (explicit)

- ref-gap E (type-annotation / impl-header type refs) -- SUPERVISED, own
  session; the field/type-prefix `--fix` warning STAYS until E lands.
- Track 5.3 architectural charts (layering / package maps / static butterfly
  chart export). **The butterfly *renderer* built here makes the eventual 5.3
  butterfly *chart* a smaller follow-up** -- same aggregation, different output.
- Track 3 component conversion (TOvc* -> cx/dx).
- CLI reading of `naming.presets`.
- A guaranteed editor right-click submenu (no supported OTA API in RAD 37 --
  keybinding + top menu are the entry points).
