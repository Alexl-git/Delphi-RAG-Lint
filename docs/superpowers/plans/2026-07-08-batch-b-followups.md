# Batch B Follow-ups -- Implementation Plan

> For agentic workers: execute via superpowers:subagent-driven-development, task-by-task.

**Goal:** Fix two dogfooding-reported lint false positives (headless-testable) and add two IDE Options-page enrichments surfaced in live smoke.

## Global Constraints

- **Encoding:** all `.pas`/`.dfm` files strict 7-bit ASCII, CRLF, no BOM, no Unicode.
- **DocInsight:** new public surface gets `///` `<summary>`.
- **TDD where testable:** Tasks 1-2 (lint FPs) are headless-testable via the CLI and MUST get a failing test first, then green. Tasks 3-4 (IDE frames) are NOT headless-testable -- build gate + live smoke only; do NOT fabricate UI tests.
- **Build recipe:** CLI = `src/cli/drag-lint.dproj` Win64 Debug -> `src/cli/Win64/Debug/drag-lint.exe` (Tasks 1-2, via delphi-build skill). IDE BPL = `src/delphi-plugin/dclDragLintWizard.dproj` Win32, RAD Studio CLOSED (`Get-Process bds` empty) (Tasks 3-4). Both: `BUILD_EXITCODE=0`, no `[dcc] Error`.
- **Commit cadence:** one source commit per task; BPL/DCP in a separate `build(plugin):` commit; CLI exe redeploy noted.
- Reindex the DragLint self-index only if a later task queries the changed code.

---

## Task 1: Fix `doc-drift` false positive on class/type declarations

`doc-drift`'s param/return analysis runs for EVERY symbol; on a class type its "signature" is the ancestor/interface list (`(TFrame)`, `(TInterfacedObject, INTAAddInOptions)`), which is mis-parsed as a param list -> spurious `ddParamMissing` findings, and a wrong autofix (`<param name="TFrame">` stubs).

**Files:**
- Modify: `src/doc/DRagLint.Doc.Drift.pas` -- `Analyze` (the param/return block, findings 1-6, ~L417-463).
- Create/extend a test: `tests/autotest/run_doc_drift_typedecl.ps1`.

**Interfaces:**
- `TSymbolKind` routine values (from `src/core/DRagLint.Core.Model.pas:6`): `skProcedure, skFunction, skMethod, skConstructor, skDestructor`.
- Diagnostic verb: `drag-lint doc-drift --qname X --db PATH --json` (CLI dump of TDocDrift findings for one symbol; handler ~CLI.pas:8707).

- [ ] **Step 1 (RED): failing test.** Write `run_doc_drift_typedecl.ps1`: create a tiny fixture unit with a DOCUMENTED class that has an ancestor AND an implemented interface (mirror the report: `TX = class(TFrame)` with a `/// <summary>` and `TY = class(TInterfacedObject, ISomeIntf)`), index it into a temp DB, run `doc-drift --qname <TX> --json` and `--qname <TY> --json`, and assert NO `ddParamMissing` (and no `paramMissing`) finding names the ancestor/interface (`TFrame`, `TInterfacedObject`, `ISomeIntf`). Run against the current exe -> it should FAIL (the FP fires). Capture the RED output.
- [ ] **Step 2 (GREEN): gate the param/return block on routine kinds.** In `Analyze`, wrap findings 1-6 (the whole `ExtractParamList`-derived param + return section, ~L417-463 -- `ddParamRenamedOrRemoved`, `ddParamMissing`, `ddParamVolatileMode`, `ddReturnsButNoValue`, `ddValueButNoReturns`, `ddReturnTypeChanged`) in `if ASym.Kind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor] then begin ... end;`. A non-routine symbol (class/interface/record/type/const/var) has no params or return -> skip entirely. Keep any non-param drift checks (if any exist below the block) OUTSIDE the guard. Do NOT change the routine-path behavior (existing drift tests must still pass).
- [ ] **Step 3:** Build the CLI Win64 (delphi-build), redeploy to `src/cli/Win64/Debug/drag-lint.exe` (the test's default exe). Run `run_doc_drift_typedecl.ps1` -> PASS. Run the existing `run_drift.ps1` + any doc battery (`run_doc_returns.ps1`) -> still PASS (no routine-path regression).
- [ ] **Step 4:** Commit source `fix(doc-drift): skip param/return drift on non-routine symbols (no FP on class/interface decls)` + the test. (Trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.)

---

## Task 2: Fix `object-leak` false positive on owner-parented VCL components

`object-leak` flags `lbl := TLabel.Create(Self)` when `lbl` isn't separately stored/freed -- but a `TComponent` constructed with a non-nil `AOwner` is owned by that owner and freed on its teardown (no leak; an explicit Free would be a double-free). The escape lattice ignores the owner argument.

**Files:**
- Modify: `src/diagnostics/DRagLint.Diagnostics.FlowChecks.pas` -- the object-leak block (~L791-817) + the constructor-site recording loop (~L798-810).
- Create: `tests/autotest/run_object_leak_owned.ps1`.

**Interfaces:**
- `FlowChecks.Check(AFile; AStore: ISymbolStore = nil; AFileId ...)` -- store is nil-safe/optional.
- `AStore.IsDescendantOf(AClassName, AAncestorName, AFileId): Boolean` (`DRagLint.Storage.SQLite.pas:158`) -- test "is TComponent descendant".
- `ExprIsConstructor(rhsNode, Src)` classifies the constructor; you need the constructed TYPE NAME and the FIRST ARGUMENT node from that RHS. Inspect how `ExprIsConstructor` and nearby helpers pull the callee type + arg list (there is existing arg/type extraction in this unit -- reuse it; do NOT hand-roll a new parser).

- [ ] **Step 1 (RED): failing test.** Write `run_object_leak_owned.ps1`: fixture unit with a routine doing `lbl := TLabel.Create(Self); lbl.Parent := X;` where `lbl` is NOT stored in a field/array and NOT freed (mirror the report). Also include a genuine leak control: `p := TStringList.Create;` (no owner, TStringList is not a TComponent-with-owner... actually TStringList's Create has no owner) OR `c := TLabel.Create(nil);` -- something the rule SHOULD still flag. Index into a temp DB, run the object-leak diagnostic (via `lint --file <fixture> --db <db>` or the selftest path that surfaces object-leak; find the exact invocation the way the report did with `lint-all`). Assert: owner-parented `lbl` is NOT flagged; the genuine no-owner leak IS still flagged. Run against current exe -> FAILS (FP present). Capture RED.
- [ ] **Step 2 (GREEN): teach the analyzer that non-nil AOwner transfers ownership.** In the constructor-site loop (~L805), when the RHS is a constructor AND a store is available AND the constructed type `IsDescendantOf(TypeName, 'TComponent', AFileId)` AND the first constructor argument is present and is NOT the `nil` literal, treat that local as TRANSFERRED -- i.e. do NOT record it as a leak candidate (skip setting `CreateRow[Tgt]`), or mark it escaped so `EIn2[ExitIdx]` won't flag it. `Create(nil)` (explicit nil owner) and no-store paths keep the current behavior. Prefer the principled owner-argument test; the report's `.Parent :=` heuristic is a fallback ONLY if arg extraction proves infeasible (justify in the report if you fall back).
- [ ] **Step 3:** Build CLI Win64, redeploy exe. Run `run_object_leak_owned.ps1` -> PASS (owner-parented not flagged, genuine leak still flagged). Run the existing flow/lint battery (`run_smoke.ps1` or the lint battery that covers FlowChecks) -> no regression.
- [ ] **Step 4:** Commit `fix(object-leak): non-nil AOwner on a TComponent constructor transfers ownership (no FP on owner-parented components)` + test.

---

## Task 3: Indexer page -- read-only Library/Browsing folders + scope + time warning

The Indexer Options page has a `ScanLibraries` checkbox but shows nothing about WHICH folders get indexed or the time cost. Add a read-only display of the resolved Delphi Library + Browsing folders, a Win-vs-all-platforms scope choice, and a visible time warning. (Editable later -- design so a future edit path is easy, but this task is READ-ONLY.)

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.OptionsFrames.pas` -- `TDLIndexerOptionsFrame` (`BuildControls`/`LoadControls`).

**Interfaces / facts (VERIFY in code before building):**
- The CLI resolves Library + Browsing paths from the Delphi registry: `--scan-libraries-win` (Win32+Win64 Library+Browsing) and `--scan-libraries-all` (all platforms). See `DRagLint.CLI.pas:549-559`, and the resolver `ResolveLibraryPaths` / `TClosureResolver.Create(Resolver.ResolveLibraryPaths)` (CLI.pas:1130). Find the unit that actually reads the registry paths (a resolver in `src/resolver/` or similar) -- the plugin frame should reuse THAT resolver if it is linkable into the Win32 BPL, else read the same registry keys directly (HKCU Delphi 37 Library/Browsing Path) with a small self-contained reader.
- IMPORTANT linkability: if the CLI path-resolver unit pulls heavy CLI-only deps and won't link into the plugin BPL, read the registry directly in the frame (the Library/Browsing paths live under the RAD Studio 37 registry key, e.g. `HKCU\Software\Embarcadero\BDS\37.0\Library\<platform>` values `Search Path` / `Browsing Path`). Prefer reuse; fall back to a direct minimal registry read. Verify at build time.

- [ ] **Step 1:** Add to `TDLIndexerOptionsFrame.BuildControls` a "Library indexing" group containing: (a) a scope selector -- a small radio group or combobox: "Win32 + Win64 (Library + Browsing)" vs "All platforms" (maps to --scan-libraries-win vs --scan-libraries-all; persist the choice to a NEW `TDragLintSettings` boolean e.g. `ScanLibrariesAllPlatforms` ONLY IF a settings field is warranted -- otherwise leave scope display-only for now and note it; do NOT invent unused persistence). (b) a READ-ONLY multiline control (TMemo, ReadOnly:=True, or a TListBox) listing the resolved Library + Browsing folders for the selected scope. (c) a clearly visible WARNING label (distinct color/wording): "Indexing the full library (RTL + DevExpress + browsing paths) can take several minutes." Keep it consistent with the existing frame idiom (code-built, DLNew* helpers).
- [ ] **Step 2:** LoadControls populates the read-only folder list by resolving the paths (reused resolver or direct registry read). Guard for "registry not found / no paths" -> show a friendly placeholder line, never raise. If the frame adds a persisted scope boolean, wire it through `TDragLintSettings` + `LoadSettings`/`SaveSettings` (Settings.pas) AND the read-modify-write Save; if scope stays display-only this task, say so in the report.
- [ ] **Step 3:** Build the Win32 BPL (RAD Studio closed), 0 errors. (No headless test -- IDE UI.)
- [ ] **Step 4:** Commit `feat(plugin): Indexer page shows resolved Library/Browsing folders + scope + time warning (read-only)`.

---

## Task 4: Linter page -- "Edit lint rules (170+)..." button opening the dock Lint Options tab

The full per-rule catalog (enable/disable/severity/autofix, 170+ rules) lives on the dock's "Lint Options" tab (via `CreateEmbeddedLintOptions`), reachable through the Project Rules right-click. Make it discoverable from the Linter Options page via a button.

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.OptionsFrames.pas` -- `TDLLinterOptionsFrame` (`BuildControls` + a click handler).

**Interfaces:**
- `DragLint.Plugin.DockForm.ShowDragLintDockLintOptions` (exported; shows the dock + selects the Lint Options tab). Already used by the Project Rules menu (Task 4 of Batch B).

- [ ] **Step 1:** In `TDLLinterOptionsFrame.BuildControls`, add a group "Lint rules" with a short label ("The full list of 170+ lint rules -- enable/disable, severity, and auto-fix -- is edited per project on the drag-lint dock's Lint Options tab.") and a `TButton` "Edit lint rules (170+)...". Its `OnClick` calls `DragLint.Plugin.DockForm.ShowDragLintDockLintOptions` (add `DragLint.Plugin.DockForm` to the implementation uses if not present). Give the handler a DocInsight `<summary>` if it's a named method.
- [ ] **Step 2:** Build the Win32 BPL (RAD Studio closed), 0 errors.
- [ ] **Step 3:** Commit `feat(plugin): Linter page 'Edit lint rules...' button opens the dock Lint Options tab`.

---

## Task 5: Final BPL/CLI build + docs + BACKLOG

- [ ] Rebuild the final Win32 BPL (RAD Studio closed) carrying Tasks 3-4; deploy to `third_party/dll-win32/`. Rebuild the CLI Win64 carrying Tasks 1-2; deploy to `src/cli/Win64/Debug/` (and note whether `third_party/dll-win64/drag-lint.exe` should be refreshed).
- [ ] Update `docs/BACKLOG-lint-false-positives.md`: mark FP#1 + FP#2 FIXED (commit refs).
- [ ] Update `docs/lint/BACKLOG.md` LATEST resume block + the live-smoke checklist (Indexer library info + Linter rules button now present).
- [ ] BPL/DCP in a `build(plugin):` commit; report branch state (user drives push).

## Final verification
- [ ] `run_doc_drift_typedecl.ps1` + `run_object_leak_owned.ps1` PASS; existing drift/doc/lint batteries still PASS.
- [ ] Both BPL builds 0 errors; encoding clean on every touched `.pas`/`.dfm`.
- [ ] FP doc marked fixed; BACKLOG updated.
