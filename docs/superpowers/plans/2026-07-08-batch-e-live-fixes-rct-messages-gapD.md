# Batch E Implementation Plan -- library-folders regression + RCT clickable Messages + fast access + ref-gap D + cleanup

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. AUTONOMOUS run -- no user check-ins.

**Goal:** Fix the empty Library/Browsing folder list, make the reverse call tree navigable via clickable IDE Messages, add fast (keyboard) access to it, index Self.-qualified field references (ref-gap D), and delete a dead fixture -- then cut v0.98.0-alpha.

**Architecture:** 6 tasks. Headless-testable where possible (CLI JSON field, ref-gap D); IDE-UI tasks gated by BPL build + a live-smoke checklist. Every task reuses an existing surface. Spec: `docs/superpowers/specs/2026-07-08-batch-e-live-fixes-rct-messages-gapD-design.md`.

**Tech Stack:** Delphi 13 (Studio 37), Win64 CLI + Win32 plugin BPL, tree-sitter, FireDAC/SQLite, PowerShell autotest, OTA (`IOTAMessageServices`, `IOTAKeyboardServices`).

## Global Constraints

- **Encoding (all `.pas`/`.dfm`/`.dpr`/`.dproj`/`.dpk`):** strict 7-bit ASCII, no BOM, CRLF. DocInsight comments ASCII.
- **DocInsight:** new/changed public surface gets `///` `<summary>`.
- **TDD** for headless tasks (T2a CLI json, T4 ref-gap D): failing test first, then green. IDE-UI tasks (T1, T2b, T3) are NOT headless-testable -- build gate + live-smoke only; do NOT fabricate UI tests.
- **Build:** `delphi-build` recipe. CLI = `src/cli/drag-lint.dproj` Win64; plugin = `src/delphi-plugin/dclDragLintWizard.dproj` Win32, RAD Studio (`bds.exe`) CLOSED. `BUILD_EXITCODE=0`, no `[dcc] Error`. Deploy CLI Win64 -> `third_party/dll-win64/drag-lint.exe` (+ `src/cli/Win64/Debug/`); BPL auto-deploys to `third_party/dll-win32/`.
- **Self-lint noise:** braces/brackets-in-comments + `'\'` char-literal "errors" are false positives; the real `dcc` compiler is the gate.
- **Commit cadence:** one source commit per task; final BPL/DCP in a `build(plugin):` commit.
- **Deferred (do NOT build):** ref-gap E (type-annotation/impl-header type refs); a guaranteed editor right-click submenu (T3b is failure-safe best-effort only).

---

## Task 1: Fix the empty Library/Browsing folders list (regression)

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.OptionsFrames.pas` (`TDLIndexerOptionsFrame`, the memo/group at ~439-451, and the group `FGrpLibIndex` creation ~414-420)

**Interfaces:** none new -- a layout/anchor fix.

**Root cause (from investigation):** commit `9d48f0a` gave `FGrpLibIndex` + `FMemoLibPaths` an `akBottom` anchor and grew the frame to ~752px; the IDE hosts the frame `Align=alClient` and shrinks it to the ~450px options client area, collapsing the `akTop+akBottom` memo's height to ~0 -> the list renders empty though `PopulateLibPaths` filled `Lines`. The data path is correct.

- [ ] **Step 1: Add a MinHeight floor to the memo (and group)**

After `FMemoLibPaths.Height := LH;` (line 444) and before/after the `Anchors` line (450), add:
```pascal
  { Regression fix (Batch E): the IDE hosts this frame Align=alClient and shrinks
    it to the (short) Options client area; with akBottom and no floor the memo's
    height collapsed to ~0 and the folder list rendered empty. A MinHeight floor
    keeps >= ~20 lines visible while still growing when the Options window is taller. }
  FMemoLibPaths.Constraints.MinHeight := LH;
```
And on the group (after `FGrpLibIndex` is created + sized, ~line 414-420), add a matching floor so the group itself can't crush its child:
```pascal
  FGrpLibIndex.Constraints.MinHeight := <the group's design height>; // e.g. LH + header/margins
```
(Use the group's actual design height constant in that code; if it's computed, set MinHeight to that same value.) Confirm `LH = 320` (~20 lines at the default font) satisfies the ">= 20 lines" ask; if `LH` is smaller, bump it to 320.

- [ ] **Step 2: Build the BPL + confirm 0 errors**

Run the `delphi-build` recipe for `src/delphi-plugin/dclDragLintWizard.dproj` (Win32, RAD Studio closed). Expected `BUILD_EXITCODE=0`, no `[dcc32 Error]`. (Do NOT commit the .bpl here -- deferred to Task 6.)

- [ ] **Step 3: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.OptionsFrames.pas
git commit -m "fix(plugin): Library/Browsing folder list no longer collapses to empty (MinHeight floor; >=20 lines, still resizable)"
```

- [ ] **Step 4: Record the live-smoke step** (for the handoff, user runs): Tools > Options > Third Party > drag-lint > Indexer -> the Library/Browsing list shows resolved folders, >= 20 lines visible; resizing the Options window grows/shrinks it without collapsing.

---

## Task 2a: Emit full source path + line per reverse-calltree node (CLI, headless)

**Files:**
- Modify: `src/report/DRagLint.Report.RCallTree.pas` (`TRCallNode` record + `Expand`)
- Modify: `src/cli/DRagLint.CLI.pas` (`BuildNodeJson` ~10104)
- Test: `tests/autotest/run_reverse_calltree.ps1` (extend)

**Interfaces:**
- Produces: `TRCallNode` gains `SiteFile: string` (absolute source path of this node's own file, i.e. where its call into its child lives) and `SiteLine: Integer` (the call-site line). JSON node gains `"file"` (absolute path) and `"line"` (int). `site` unchanged (back-compat). Consumed by Task 2b.

- [ ] **Step 1: Write the failing test**

Extend `tests/autotest/run_reverse_calltree.ps1`: after the existing `--format json` parse, assert each non-root node object has a `file` field that is an absolute path AND exists on disk, and a `line` field that is a positive integer equal to the `:N` suffix of that node's `site`. (Root's file/line may be empty/0 -- root has no call site; assert only non-root nodes.)
```powershell
# For each caller node in the tree (recurse the json): 
#   Check "$($n.qname) has file"  (Test-Path $n.file)
#   Check "$($n.qname) line matches site"  ($n.line -eq [int]($n.site -replace '^.*:',''))
```

- [ ] **Step 2: Run to verify it fails**

Run: `pwsh tests/autotest/run_reverse_calltree.ps1`
Expected: FAIL -- nodes have no `file`/`line` fields yet.

- [ ] **Step 3: Add SiteFile/SiteLine to the node record**

In `src/report/DRagLint.Report.RCallTree.pas`, extend `TRCallNode`:
```pascal
  TRCallNode = record
    QName   : string;
    Site    : string;            // unit:line of THIS node's call into its child; '' for root
    SiteFile: string;            // absolute source path of this node's own file (the call-site file); '' for root
    SiteLine: Integer;           // 1-based call-site line; 0 for root
    Cycle   : Boolean;
    Callers : TArray<TRCallNode>;
  end;
```

- [ ] **Step 4: Populate them in Expand**

In `Expand` (RCallTree.pas ~60-97): the node's own file is its symbol's file. After setting `Result.Site := ASite;`, add:
```pascal
    { The call site lives in THIS node's own file (it is the caller). SiteFile =
      the symbol's declaring file (full path); SiteLine parsed from ASite's :N. }
    var Sym := AStore.GetSymbolById(AId);
    Result.SiteFile := AStore.GetFilePath(Sym.FileId);
    if ASite <> '' then
    begin
      var CPos := LastDelimiter(':', ASite);
      if CPos > 0 then Result.SiteLine := StrToIntDef(Copy(ASite, CPos + 1, MaxInt), 0);
    end;
```
(`GetSymbolById` is already called on the next line for `QualifiedName` -- reuse one call: fetch `Sym` once, use `Sym.QualifiedName` and `Sym.FileId`.) Root (`ASite=''`) leaves SiteFile='' / SiteLine=0. Note: for the ROOT the SiteFile is still its own file (fine/harmless); the test only asserts non-root nodes.

- [ ] **Step 5: Emit the fields in BuildNodeJson**

In `src/cli/DRagLint.CLI.pas` `BuildNodeJson` (~10109-10115), after the `site` pair add:
```pascal
    Result.AddPair('file', ANode.SiteFile);
    Result.AddPair('line', TJSONNumber.Create(ANode.SiteLine));
```

- [ ] **Step 6: Build CLI Win64, deploy, run test to green**

Build `src/cli/drag-lint.dproj` (Win64), deploy exe to `src/cli/Win64/Debug/` + `third_party/dll-win64/drag-lint.exe`.
Run: `pwsh tests/autotest/run_reverse_calltree.ps1`
Expected: PASS (existing assertions + new file/line assertions).

- [ ] **Step 7: Commit**

```bash
git add src/report/DRagLint.Report.RCallTree.pas src/cli/DRagLint.CLI.pas tests/autotest/run_reverse_calltree.ps1
git commit -m "feat(reverse-calltree): emit absolute file + line per node in --format json (enables IDE Messages navigation)"
```

---

## Task 2b: New IDE action -- reverse call tree into the clickable Messages window

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.Editor.pas` (new `InvokeReverseCallTreeMessages` + a menu item; reuse `PostLintReportToMessages`/`DLRunReport`/`SliceJsonBracket`/`RunAndCaptureStdout`)

**Interfaces:**
- Consumes: `GetActiveProjectDb`, `DLAskQName`, `RunAndCaptureStdout` (decl :68), `SliceJsonBracket` (:454), the `IOTAMessageServices` pattern from `PostLintReportToMessages` (:3687-3725: `Supports(BorlandIDEServices, IOTAMessageServices, MS)`, `MS.AddToolMessage(FName, Rest, 'drag-lint', Line, Col)`, `MS.AddTitleMessage(...)`). Task 2a's json `file`/`line` fields.
- Produces: `procedure InvokeReverseCallTreeMessages(Sender: TObject);` (used by the menu + Task 3's keybinding).

- [ ] **Step 1: Implement InvokeReverseCallTreeMessages**

Model on `DLRunReport`'s async discipline (bg thread runs the exe; OTA calls marshalled to the main thread via `TThread.Queue`) and `PostLintReportToMessages`'s emit pattern. After `InvokeReverseCallTree` (~3107-3116) add:
```pascal
/// <summary>Reverse call tree for the symbol under the cursor, emitted to the IDE
/// Messages window: each node is a clickable AddToolMessage (double-click jumps to
/// the call site). Runs reverse-calltree --format json off-thread, then posts the
/// tree on the main thread. Complements InvokeReverseCallTree (which writes text to
/// an editor buffer).</summary>
procedure InvokeReverseCallTreeMessages(Sender: TObject);
```
Logic:
1. `Db := GetActiveProjectDb; if Db = '' then ShowMessage('drag-lint: no project index.'), Exit;`
2. `if not DLAskQName(Q) then Exit;`
3. On a background thread (mirror `DLRunReport`'s thread + 180s cap): `Out := RunAndCaptureStdout(DLExe64, Format('reverse-calltree --qname "%s" --db "%s" --depth 3 --format json', [Q, Db]))`.
4. `Slice := SliceJsonBracket(Out, '{', '}')`; parse with `TJSONObject.ParseJSONValue`. If nil -> queue a `ShowMessage`/title-message "no result" and exit.
5. In a `TThread.Queue` block (main thread -- OTA required): `Supports(BorlandIDEServices, IOTAMessageServices, MS)`; `MS.AddTitleMessage(Format('drag-lint: reverse call tree for %s', [Q]))`; recursively walk `root.callers`: for each node emit `MS.AddToolMessage(node.file, Format('%s%s <- %s', [Indent, parentQName, node.qname]), 'drag-lint', node.line, 0)` where `Indent` is 2 spaces per depth. (Semantics: `node` is a CALLER of `parent`; read as "parent is called by node". Pick clear text, e.g. `'%s calls %s'` from node's perspective -- node calls parent -- decide one and document it.) Guard: if `node.file=''` or doesn't exist, still emit a title/tool message with an empty filename (non-navigable) rather than skip, so the tree is complete.
6. Show the Messages window (the AddToolMessage/AddTitleMessage surfaces it; if an explicit show is needed, match how `PostLintReportToMessages` does it).

Keep `InvokeReverseCallTree` (text) intact.

- [ ] **Step 2: Add a menu item**

In the "Uses && Dependencies" submenu (`SubUses`, ~3826-3834), after the existing `'Reverse Call Tree (who calls this, N-deep)...'` item, add:
```pascal
  AddWrappedItem(SubUses, 'Reverse Call Tree (clickable, Messages window)...'    , InvokeReverseCallTreeMessages);
```

- [ ] **Step 3: Build the BPL + 0 errors**

Build `dclDragLintWizard.dproj` (Win32). `BUILD_EXITCODE=0`. (Do NOT commit the .bpl -- Task 6.)

- [ ] **Step 4: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.Editor.pas
git commit -m "feat(plugin): 'Reverse Call Tree (Messages)' action -- clickable nodes in the IDE Messages window"
```

- [ ] **Step 5: Live-smoke note** (handoff): menu -> Reverse Call Tree (Messages) -> the Messages window fills with the tree; each row double-clicks to the call site.

---

## Task 3: Fast access -- keybinding (3a) + best-effort editor popup (3b)

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.Keyboard.pas` (add a binding + handler) -- 3a
- Modify (best-effort, may skip): `src/delphi-plugin/DragLint.Plugin.EditViewNotifier.pas` -- 3b

### 3a -- keybinding (supported, the real deliverable)

**Interfaces:** consumes `InvokeReverseCallTreeMessages` (Task 2b). Taken chords: H,C,S,D,R,M,I,F,T,U (`Keyboard.pas:97-106`). Use **Ctrl+Alt+K** (free).

- [ ] **Step 1: Add the key handler + binding**

In `src/delphi-plugin/DragLint.Plugin.Keyboard.pas`: add a `ReverseCallTreeKey` proc (mirror `RenameKey` :156, which calls `InvokeRename(nil)` after an Enable* gate if applicable):
```pascal
procedure ReverseCallTreeKey(const Context: IOTAKeyContext; KeyCode: TShortcut;
  var BindingResult: TKeyBindingResult);
begin
  InvokeReverseCallTreeMessages(nil);
  BindingResult := krHandled;
end;
```
(Match the EXACT handler signature of the existing keys in this file -- copy `RenameKey`'s signature verbatim.) Then in `BindKeyboard` (after line 106) add:
```pascal
  BindingServices.AddKeyBinding( [ShortCut(Ord('K'), [ssCtrl, ssAlt])], ReverseCallTreeKey, nil);
```
Ensure `InvokeReverseCallTreeMessages` is reachable (the file already uses `InvokeRename` etc. from `DragLint.Plugin.Editor` via mutual implementation-section refs -- add it the same way).

- [ ] **Step 2: Build BPL + 0 errors.** (No headless test -- keybinding is IDE-only.)

- [ ] **Step 3: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.Keyboard.pas
git commit -m "feat(plugin): Ctrl+Alt+K -> reverse call tree (Messages) -- fast access without the top menu"
```

### 3b -- best-effort editor right-click submenu (failure-safe; SKIP if too fragile)

**IMPORTANT:** RAD Studio 37 has NO supported OTA API for the editor context menu. This is a fragile VCL splice -- it MUST be failure-safe (any exception/missing-handle swallowed, never crashes the plugin or blocks activation) and is a BONUS, not the deliverable (3a is). If it cannot attach safely, SKIP 3b and note it.

- [ ] **Step 1: Attempt the splice (guarded)**

In `TDragLintEditServicesNotifier` (`EditViewNotifier.pas:354`, which holds live `EditWindow` handles in `WindowActivated`/`EditorViewActivated` ~379/398): in a fully `try/except`-guarded helper, locate the active edit window's VCL `TPopupMenu` and add a "drag-lint" submenu with items wired to `InvokeHover`/`InvokeGoToDefinition`/`InvokeReverseCallTreeMessages`/`InvokeImpact`/`InvokeRename`. Wrap EVERYTHING: `try ... except {swallow -- best effort} end;`. If the popup/handle isn't found, no-op silently. Add it idempotently (don't duplicate the submenu on every activation -- guard by checking if already added). Comment clearly: `{ BEST-EFFORT / UNSUPPORTED: RAD 37 has no OTA editor-context-menu API; this splices a VCL popup item and self-disables on any failure. The supported entry points are Ctrl+Alt+K and the top drag-lint menu. }`

- [ ] **Step 2: Build BPL + 0 errors.** If the splice compiles + BPL builds, keep it. If it proves infeasible/unsafe to even compile cleanly, REVERT 3b and note "3b skipped -- editor popup not feasible; 3a keybinding is the fast-access path" in the report.

- [ ] **Step 3: Commit (only if 3b kept)**

```bash
git add src/delphi-plugin/DragLint.Plugin.EditViewNotifier.pas
git commit -m "feat(plugin): best-effort drag-lint submenu on the editor right-click (failure-safe; keybinding is the supported path)"
```

---

## Task 4: Ref-gap D -- index Self.-qualified field references

**Files:**
- Modify: `src/parser/DRagLint.Parser.Delphi13.pas` (the `exprDot` case ~1348-1354, under `EmitUsageRefs`)
- Test: `tests/autotest/run_self_field_refs.ps1`

**Interfaces:** under `--deep`, `Self.member` now emits a `read` ref for `member`. No new public signature.

**Gate (critical):** emit the `rhs` member ref ONLY when the `lhs` base is `Self` (`SameText(NodeText(lhs), 'Self')`). Ungated would flood the index with every `obj.Method`/`obj.Prop` access.

- [ ] **Step 1: Write the failing test**

Create `tests/autotest/run_self_field_refs.ps1` (model on `run_bare_rhs_refs.ps1`). Fixture: a class with a field `client`, a method body using `Self.client := X;` and `Y := Self.client;`, plus a negative control `other.Method` (a non-Self dotted access) and a plain `obj.Prop`.
```powershell
# index --deep. Assert (positive): refs table has >=1 row for name 'client' at the
#   Self.client sites (via find-callers/impact/direct refs SQL -- like run_bare_rhs_refs).
# Assert (negative, GUARD over-capture): 'Method'/'Prop' on the non-Self dotted access
#   did NOT gain a spurious member 'read' ref (only Self.member is captured).
```

- [ ] **Step 2: Run to verify it fails**

Run: `pwsh tests/autotest/run_self_field_refs.ps1`
Expected: FAIL -- `client` has no ref at the `Self.client` sites.

- [ ] **Step 3: Emit the gated rhs ref in the exprDot case**

In `src/parser/DRagLint.Parser.Delphi13.pas`, the `exprDot` case (~1348-1354). Current: emits `read` for `lhs` base, skips `rhs`. Add, after the existing lhs emit and before the recurse:
```pascal
    if NodeType = 'exprDot' then
    begin
      var L:= ANode.ChildByField('lhs');
      if (not L.IsNull) and (L.NodeType = 'identifier') then AState.EmitRef('read', NodeText(L, AState.Source), L);
      // Ref-gap D: capture the MEMBER of a Self.-qualified access (Self.field) as a
      // read of the field. Gated to lhs = Self so we do NOT flood refs with every
      // obj.Method / obj.Prop member access.
      if (not L.IsNull) and (L.NodeType = 'identifier') and SameText(Trim(NodeText(L, AState.Source)), 'Self') then
      begin
        var R:= ANode.ChildByField('rhs');
        if (not R.IsNull) and (R.NodeType = 'identifier') then AState.EmitRef('read', NodeText(R, AState.Source), R);
      end;
      for i:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(i), AState, AParentSymbolIdx, AParentQualifiedName);
      Exit;
    end;
```
(Match the existing `exprDot` handler's exact variable names/`NodeText` signature -- adapt to what's already there; the file uses `NodeText(node, AState.Source)`.)

- [ ] **Step 4: Build CLI Win64, deploy, run test to green**

Build + deploy. Run: `pwsh tests/autotest/run_self_field_refs.ps1` -> PASS (positive + negative).

- [ ] **Step 5: Blast-radius regression**

Run ref-consuming batteries (`run_reverse_calltree.ps1`, `run_deps_report.ps1`, `run_bare_rhs_refs.ps1`, `run_naming_prefix_autofix.ps1`) -> all PASS. Note the fixture refs-count delta (should be only the new Self.member reads).

- [ ] **Step 6: Commit**

```bash
git add src/parser/DRagLint.Parser.Delphi13.pas tests/autotest/run_self_field_refs.ps1
git commit -m "fix(index): emit a read ref for Self.-qualified field members under --deep (ref-gap D; gated to Self, no over-capture)"
```

---

## Task 5: Cleanup -- delete orphaned T52_options.dpr

**Files:**
- Delete: `tests/fixtures/T52_options.dpr` (+ its `.bat` if present)

- [ ] **Step 1: Confirm dead + delete**

Confirm no `.ps1`/battery/build references `T52_options` (grep). It references the singular `DragLint.Plugin.OptionsFrame` unit deleted in Batch D (verified dead in Batch D's final review). `git rm tests/fixtures/T52_options.dpr` (+ `.bat` if it exists). No build impact.

- [ ] **Step 2: Commit**

```bash
git rm tests/fixtures/T52_options.dpr   # + .bat if present
git commit -m "chore(tests): delete orphaned T52_options.dpr (referenced the deleted singular OptionsFrame unit)"
```

---

## Task 6: Wrap-up -- final build, battery, docs, v0.98 release, handoff

**Files:** `src/cli/DRagLint.CLI.pas` (VERSION), `CHANGELOG.md`, `README.md`, `docs/lint/BACKLOG.md`, AI docs; final BPL.

- [ ] **Step 1: Final builds.** CLI Win64 (Tasks 2a, 4) + Win32 BPL (Tasks 1, 2b, 3), RAD Studio closed, deploy both.

- [ ] **Step 2: Full battery on the deployed exe.** Run: `run_reverse_calltree.ps1`, `run_self_field_refs.ps1`, `run_bare_rhs_refs.ps1`, `run_naming_prefix_autofix.ps1`, `run_naming_autofix.ps1`, `run_deps_report.ps1`, `run_manifest.ps1`, `tests/autofix/run_fixable_catalog.ps1`. All PASS or STOP (BLOCKED).

- [ ] **Step 3: Version + CHANGELOG + README + BACKLOG + AI docs.**
  - `src/cli/DRagLint.CLI.pas:6` VERSION `0.97.0-alpha` -> `0.98.0-alpha`.
  - CHANGELOG v0.98 section: library-folders fix; reverse-calltree Messages (clickable) + Ctrl+Alt+K + the json file/line fields; ref-gap D (Self.-qualified field refs); note ref-gap E still deferred; the T52 cleanup; 3b best-effort status.
  - README: add the "Reverse Call Tree (Messages)" action + Ctrl+Alt+K to the menu/keybinding list.
  - BACKLOG `RESUME 2026-07-08 (LATEST-36)`: what shipped; the live-smoke checklist (T1 folders, T2b Messages nav, T3a keybinding, T3b right-click status); mark ref-gap D fixed + note field/type-prefix warning stays until E; deferred E + guaranteed-right-click.
  - AI docs: add the new action/keybinding if the IDE-action list is maintained there.

- [ ] **Step 4: Release v0.98.0-alpha.** Run `build/pack-lint-release.ps1 -Version 0.98.0-alpha` (RAD Studio closed) -> Win64+Win32 Release 0 err + zips. Verify `--version` = 0.98.0-alpha + re-run the battery on the Release exe. Release commit (VERSION+CHANGELOG+README+BACKLOG+AI docs). Separate `build(plugin):` commit for the Win32 BPL/DCP. Push main. Tag `v0.98.0-alpha`. `gh release create v0.98.0-alpha <win64.zip> <win32.zip> <bpl> --title ... --notes-file ... --latest`. Verify Latest + assets.

- [ ] **Step 5: Handoff.** Update auto-memory (MEMORY.md index + topic file -> LATEST-36) with the released state + the live-smoke checklist + deferred items (E, guaranteed right-click, 3b confirmation). Run the handoff skill. Report the final state.

---

## Notes on anchors verified during planning (do not re-investigate)

- **T1:** memo at `OptionsFrames.pas:439-451` (add `Constraints.MinHeight := LH` after :444); group `FGrpLibIndex` ~:414-420; `LH`=320 (~20 lines). Data path (`PopulateLibPaths` :515 -> `TProjectResolver.ResolveLibraryPaths`) is correct/unchanged.
- **T2a:** `TRCallNode` at `RCallTree.pas:14-19`; `Expand` at :60-97 (node's file = `AStore.GetFilePath(GetSymbolById(AId).FileId)`, reuse the one `GetSymbolById` call; SiteLine parsed from `ASite`'s `:N`); `BuildNodeJson` at `CLI.pas:10104-10116` (add `file`+`line` after `site`).
- **T2b:** clickable-message template `PostLintReportToMessages` at `Editor.pas:3687-3725` (`Supports(...IOTAMessageServices, MS)` + `MS.AddToolMessage(FName, Rest, 'drag-lint', Line, Col)` + `AddTitleMessage`); async runner `DLRunReport` :2878-2906; `RunAndCaptureStdout` :68/:1287; `SliceJsonBracket` :454 (slice `'{','}'` for the object root); `InvokeReverseCallTree` :3107; `SubUses` menu :3826-3834.
- **T3a:** `Keyboard.pas` `BindKeyboard` :95, bindings :97-106 (taken: H/C/S/D/R/M/I/F/T/U -> use **K**), key handlers e.g. `RenameKey` :156 (copy its exact signature); register :307-314.
- **T3b:** `TDragLintEditServicesNotifier` at `EditViewNotifier.pas:354`, live handles in `WindowActivated`/`EditorViewActivated` ~:379/398. NO supported OTA editor-menu API -> failure-safe VCL splice or SKIP.
- **T4:** `exprDot` case at `Delphi13.pas:~1348-1354` (add gated `rhs` emit when `lhs='Self'`); `EmitRef`/`NodeText(node, AState.Source)` idiom per the existing handler; `run_bare_rhs_refs.ps1` is the refs-SQL test template.
- **T5:** `tests/fixtures/T52_options.dpr` dead (Batch D verified) -> `git rm`.
