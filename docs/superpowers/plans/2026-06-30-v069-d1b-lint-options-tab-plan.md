# v0.69 D1b -- IDE "Lint Options" dock tab -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **MANUAL GATE:** the plugin BPL only builds with **RAD Studio CLOSED** (BPL lock), and the tab can only be verified by a **human clicking through it in the IDE**. Task 5 is a manual checklist the user runs. Confirm `bds.exe` is not running before any BPL build.

**Goal:** Add a 4th drag-lint dock tab, "Lint Options", that loads the rule catalog via `drag-lint rules --json`, shows rules grouped by category with tri-state section checkboxes + per-rule checkboxes + inline parameter editors + a counts header, and reads/writes the active project's `drag-lint-lint.json`.

**Architecture:** A new VCL `TFrame` (`TLintOptionsFrame`, `src\delphi-plugin\DragLint.Plugin.LintOptionsFrame.pas`) parented into a new `TTabSheet` via the dock's `AddTab`. The frame shells out to the CLI (`ProcRun.RunCaptureStdout` -> `drag-lint rules --json`), parses the catalog with `System.JSON`, renders a scrollable list of category `TGroupBox`es each holding a tri-state header `TCheckBox` + per-rule `TCheckBox`es + inline editors (`TSpinEdit`/`TEdit`/`TComboBox`), and round-trips the project `drag-lint-lint.json`. The CLI stays the consumer of record; the tab only edits JSON. Pure config-JSON logic lives in a headless-testable helper (`DRagLint.Lint.ConfigWriter`, reusing `DRagLint.Lint.Config` for reads); the visual frame + OTAPI project-dir lookup are IDE-bound.

**Tech Stack:** Delphi 13 (Studio 37), plain VCL (`Vcl.StdCtrls`/`Vcl.ComCtrls`/`Vcl.ExtCtrls`/`Vcl.Samples.Spin`), ToolsAPI (OTAPI), `System.JSON`, the design-time BPL `dclDragLintWizard`, Win64 `dcc64`/`msbuild`.

## Global Constraints

- **Encoding (every `.pas`/`.dpr`/`.dpk`):** strict 7-bit ASCII, CRLF, no BOM. Normalize touched files + byte-verify before commit. `.md` may keep pre-existing non-ASCII. `.dproj`/`.dpk` are project files -- keep their existing line endings.
- **Pascal comments:** never `}` or nested `{` inside a `{ }` comment.
- **DocInsight:** `///` `<summary>` on every new public type/method.
- **VERSION is NOT bumped in D1b.** But D1b is the LAST v0.69 piece -- after it lands, the v0.69 RELEASE (VERSION `0.69.0-alpha` in `src\cli\DRagLint.CLI.pas:6` + CHANGELOG date + tag + GitHub prerelease) is a SEPARATE user-gated step, not part of this plan.
- **BPL BUILD RULE:** RAD Studio (`bds.exe`) MUST be closed before building the BPL (`_bpl_build.bat`) or deploying (`deploy-staged.bat`). The plugin runs in the **32-bit IDE load location `third_party\dll-win32`** (deploy target), even though the CLI exe is Win64 -- do not confuse the two. `_bpl_build.bat` builds Win64; the `.dproj` also stages the BPL/DCP to `C:\TEMP1\bpl_staging\`, which `deploy-staged.bat` copies to `third_party\dll-win32`.
- **Do NOT `git add`** the built `.bpl`/`.dcp`/`.exe` (all `*.exe`/`*.bpl`/`*.dcp` are build artifacts; `.gitignore` covers `*.exe`/`*.dll` -- confirm `.bpl`/`.dcp` too and add ignores if missing). Commit SOURCE ONLY.
- **New unit needs BOTH** the `.dpk` `contains` clause AND a `.dproj` `<DCCReference>` -- for BOTH new units (`DragLint.Plugin.LintOptionsFrame` and `DRagLint.Lint.ConfigWriter`, the latter with a `..\lint\` relative path).
- **VCL controls only** (no DevExpress in the plugin). Mirror `DragLint.Plugin.OptionsFrame.pas` (TFrame, dynamically-built controls, no `.dfm`).
- **`drag-lint rules --json` shape** (the frame consumes): `{ "rules":[{id,category,title,default_severity,default_enabled(bool),source,params:[{name,type("int"|"string"|"stringlist"|"bool"),default}]}], "summary":{total,categories,per_category:[{category,count}]} }`.
- **`drag-lint-lint.json` shape** (the frame round-trips): `disabled[]`, `enabled[]`, `severity{id:str}`, `thresholds{name:int}`, `naming{type_prefix{class,exception,interface,pointer}, field_prefix, param_prefix, method_case, local_case, const_case[], keyword_case, min_identifier_len, short_identifier_check("true"/"false" STRING), hungarian_prefixes[]}`, `profiles{}`. NOTE `short_identifier_check` is a JSON STRING `"true"`/`"false"`, not a bool.

---

## Key surface facts (from the plugin-surface map -- use these verbatim)

- **Dock:** `TDragLintDockFrame` (`DragLint.Plugin.DockForm.pas:65`), `FPages: TPageControl`. `function AddTab(const ACaption: string): TTabSheet` (line ~128) returns a `TTabSheet` that IS the parent `TWinControl`. Tabs created in `Create` (`FTabStruct := AddTab('Structure')` ...), content populated one tick later in `HandleInitTimer` via `CreateEmbeddedXxx(Self, FTabXxx)`.
- **Frame template:** `TDragLintOptionsFrame = class(TFrame)` (`DragLint.Plugin.OptionsFrame.pas`) -- all controls built dynamically in `BuildControls`; `Load`/`Save` methods; instantiated + reparented + `Load` called. No `.dfm`. Uses `TGroupBox`/`TCheckBox`/`TEdit`/`TButton`/`TLabel`. For a scrollable list add a `TScrollBox` (alClient, AutoScroll True) as the parent of the dynamic category sections.
- **Process runner:** `function RunCaptureStdout(const ACmdLine: string; out AOutput: string; ATimeoutMs: Integer): Integer` (`DragLint.Plugin.ProcRun.pas`) -- exit code, -1 spawn fail, CREATE_NO_WINDOW.
- **Exe resolution (inline copy, per existing pattern):**
  ```pascal
  function ResolveExe: string;
  begin
    Result := LoadSettings.ExePath;
    if (Result = '') or not FileExists(Result) then
      Result := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
    if not FileExists(Result) then Result := 'drag-lint.exe';
  end;
  ```
- **OTAPI active project dir (inline, `uses ToolsAPI`):**
  ```pascal
  function GetActiveProjDir: string;
  var MS: IOTAModuleServices; PG: IOTAProjectGroup; PR: IOTAProject;
  begin
    Result := '';
    try
      if not Supports(BorlandIDEServices, IOTAModuleServices, MS) then Exit;
      if MS = nil then Exit;
      PG := MS.MainProjectGroup;         if PG = nil then Exit;
      PR := PG.ActiveProject;            if PR = nil then Exit;
      Result := ExtractFilePath(PR.FileName);
    except
      Result := '';
    end;
  end;
  ```
- **BPL build:** `_bpl_build.bat` (rsvars + msbuild Win64 Debug `src\delphi-plugin\dclDragLintWizard.dproj`). **Deploy:** `deploy-staged.bat` (RAD Studio CLOSED -> copies `C:\TEMP1\bpl_staging\dclDragLintWizard.{bpl,dcp}` -> `third_party\dll-win32`).
- **Add a unit to the package:** `.dpk` `contains`: `DragLint.Plugin.LintOptionsFrame in 'DragLint.Plugin.LintOptionsFrame.pas',` (+ `{LintOptionsFrame: TFrame}` only if it had a `.dfm` -- it will NOT; build controls dynamically). `.dproj`: `<DCCReference Include="DragLint.Plugin.LintOptionsFrame.pas"/>`. For `DRagLint.Lint.ConfigWriter`: `.dpk` `DRagLint.Lint.ConfigWriter in '..\lint\DRagLint.Lint.ConfigWriter.pas',` + `.dproj` `<DCCReference Include="..\lint\DRagLint.Lint.ConfigWriter.pas"/>`.
- **Headless test seam:** `DRagLint.Lint.Config` (reads) + `DRagLint.Lint.ConfigWriter` (new, writes) + `DRagLint.Lint.RuleCatalog` are pure (System.JSON, no OTAPI/VCL) -> console-testable (mirror `tests\fixtures\T59_workspace_config.dpr`). The frame's OTAPI + visual parts are IDE-only; a `dcc64 -U<plugin> -U<IDELIB>` COMPILE-SMOKE (mirror `tests\fixtures\T52_options.dpr` / `T52_options.bat`) is the only automatable check for the frame unit.

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `src/lint/DRagLint.Lint.ConfigWriter.pas` | pure `TLintConfig -> drag-lint-lint.json` serializer + toggle helpers (read via existing `TLintConfig.Load`) | Create |
| `src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas` | the `TLintOptionsFrame` VCL frame + `CreateEmbeddedLintOptions` + OTAPI project-dir | Create |
| `src/delphi-plugin/DragLint.Plugin.DockForm.pas` | add `FTabLintOptions` + `AddTab('Lint Options')` + `CreateEmbeddedLintOptions` call | Modify |
| `src/delphi-plugin/dclDragLintWizard.dpk` + `.dproj` | register both new units | Modify |
| `tests/fixtures/T63_lint_config_roundtrip.dpr` (+ `.bat`) | console round-trip test of ConfigWriter | Create |
| `tests/fixtures/T64_lint_options_compile.dpr` (+ `.bat`) | compile-smoke of the frame unit | Create |
| `CHANGELOG.md`, `docs/lint/MISSING-FEATURES.md` (section 13) | docs | Modify |

---

## Task 1: `DRagLint.Lint.ConfigWriter` -- pure config serializer + toggle helpers (console-testable)

**Files:**
- Create: `src/lint/DRagLint.Lint.ConfigWriter.pas`
- Create: `tests/fixtures/T63_lint_config_roundtrip.dpr`, `tests/fixtures/T63_lint_config_roundtrip.bat`

**Interfaces:**
- Produces (all pure `System.JSON`, no OTAPI/VCL):
  - `TLintConfigWriter.ToJson(const ACfg: TLintConfig): string;` -- serialize the full config (disabled/enabled/severity/thresholds/naming) to pretty JSON matching the shape `TLintConfig.Load` reads (incl. `short_identifier_check` as a `"true"/"false"` STRING).
  - `TLintConfigWriter.SetRuleDisabled(var ACfg: TLintConfig; const AId: string; ADisabled: Boolean);` -- add/remove `AId` from the `disabled` list (and, for an off-by-default rule being enabled, add to `enabled`).
  - `TLintConfigWriter.SetThreshold(var ACfg: TLintConfig; const AName: string; AValue: Integer);`
  - `TLintConfigWriter.SetSeverity(var ACfg: TLintConfig; const AId, ASeverity: string);`
  - Naming setters that write the `naming` block fields.
  - `TLintConfigWriter.LoadOrDefault(const APath: string): TLintConfig;` -- thin wrapper over `TLintConfig.Load(APath,'')` (returns defaults if the file is absent).
  - `TLintConfigWriter.SaveToFile(const APath: string; const ACfg: TLintConfig);` -- ANSI/CRLF/no-BOM write of `ToJson`.
  - **NOTE:** `TLintConfig`'s fields are `strict private` (`FDisabled`/`FSevNames`/... in `DRagLint.Lint.Config.pas`). The writer CANNOT read them directly. Task 1 Step 3 adds minimal **public read accessors** to `TLintConfig` (`function DisabledIds: TArray<string>; function EnabledIds: TArray<string>; function SeverityPairs: TArray<TPair<string,string>>; function ThresholdPairs: TArray<TPair<string,Integer>>;` + expose `Naming`) OR makes the writer a friend by adding the serialize method to `TLintConfig` itself. **DECISION for the implementer:** add the accessors to `TLintConfig` (smaller blast radius than moving logic); the writer consumes them.

- [ ] **Step 1: Write the failing console round-trip test**

Create `tests/fixtures/T63_lint_config_roundtrip.dpr` (mirror `T59_workspace_config.dpr`): write a sample `drag-lint-lint.json` (disabled `["magic-number"]`, thresholds `{too-many-parameters:3}`, severity `{object-leak:error}`, naming `{param_prefix:"p", short_identifier_check:true, keyword_case:""}`), `LoadOrDefault` it, assert the fields, flip a few via the setters (`SetRuleDisabled(cfg,'deep-nesting',true)`, `SetThreshold(cfg,'too-many-parameters',9)`), `SaveToFile` to a temp path, re-`LoadOrDefault`, and assert the round-trip preserved everything (incl. `short_identifier_check` staying a `"true"` string that re-parses to `True`). Print `t63: N pass / M fail`. Create the `.bat` mirroring `T59`'s (dcc64 `-U..\..\src\lint -U..\..\src\core`).

- [ ] **Step 2: Run -- confirm build failure** (`DRagLint.Lint.ConfigWriter` missing). `cmd /c tests\fixtures\T63_lint_config_roundtrip.bat` -> BUILD FAILED.

- [ ] **Step 3: Add public read accessors to `TLintConfig`** (in `DRagLint.Lint.Config.pas`) and implement `DRagLint.Lint.ConfigWriter`. The serializer must emit exactly the keys `Load` reads; the setters mutate the (now-accessor-backed) local copy. Full code: the serializer builds a `TJSONObject` with `disabled`/`enabled` `TJSONArray`s, `severity`/`thresholds` `TJSONObject`s, and a nested `naming` object (with `type_prefix` sub-object, `const_case`/`hungarian_prefixes` arrays, and `short_identifier_check` as `TJSONString('true'/'false')`), then `Root.Format` (pretty) -> string; `SaveToFile` writes it as ANSI bytes with CRLF. (The implementer writes the complete unit from these contracts; keep it pure `System.JSON`/`System.IOUtils`.)

- [ ] **Step 4: Run -- confirm GREEN.** `cmd /c tests\fixtures\T63_lint_config_roundtrip.bat` -> `t63: N pass / 0 fail`.

- [ ] **Step 5: Commit.** `git add src/lint/DRagLint.Lint.Config.pas src/lint/DRagLint.Lint.ConfigWriter.pas tests/fixtures/T63_lint_config_roundtrip.dpr tests/fixtures/T63_lint_config_roundtrip.bat` + `git commit -m "feat(config): TLintConfigWriter serializer + read accessors (v0.69 D1b)"`.

---

## Task 2: `TLintOptionsFrame` -- the VCL frame (catalog load + render + config round-trip)

**Files:**
- Create: `src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas`
- Create: `tests/fixtures/T64_lint_options_compile.dpr`, `tests/fixtures/T64_lint_options_compile.bat`

**Interfaces:**
- Consumes: `DRagLint.Lint.ConfigWriter` (Task 1); `ProcRun.RunCaptureStdout`.
- Produces: `TLintOptionsFrame = class(TFrame)` with `constructor Create(AOwner)`, `procedure ReloadCatalogAndConfig;`, `procedure Save;`; and `procedure CreateEmbeddedLintOptions(AOwner: TComponent; AParent: TWinControl);` (Task 3 wires it in).

The frame's structure (build ALL controls dynamically in the constructor -- no `.dfm`):
1. A top `TPanel`(alTop) with a counts `TLabel` (`N rules across M categories, K enabled`) + a "Reload" `TButton`.
2. A `TScrollBox`(alClient, AutoScroll=True) hosting one `TGroupBox` per category (caption = category name).
3. Per category: a header tri-state `TCheckBox` (State cbChecked/cbUnchecked/cbGrayed reflecting all/none/some rules enabled) that select/deselect the whole group `OnClick`; then per rule a `TCheckBox` (checked = enabled = NOT in `disabled`), plus, when the rule has params, an inline editor per param: `TSpinEdit` (type `int`), `TComboBox` (naming casing enums / a curated list) or `TEdit` (string/stringlist).
4. `ReloadCatalogAndConfig`: `RunCaptureStdout('"<exe>" rules --json', out, 15000)` -> parse -> read the active project's `drag-lint-lint.json` via `TLintConfigWriter.LoadOrDefault(GetActiveProjDir + 'drag-lint-lint.json')` -> set each checkbox's checked/param-editor value from `default_enabled` overlaid by the config; recompute each section's tri-state + the counts header.
5. On any checkbox/editor change: mutate the in-memory `TLintConfig` via the ConfigWriter setters and `SaveToFile` back to the project's `drag-lint-lint.json` (debounced or on a "Save" button -- the implementer picks; a "Save" button is simpler + safer than autosave). Keep OTAPI (`GetActiveProjDir`) as the ONLY OTAPI dependency, isolated in one function so the frame's core (catalog parse + config apply) stays testable.

- [ ] **Step 1: Write the compile-smoke test.** Create `tests/fixtures/T64_lint_options_compile.dpr` (mirror `T52_options.dpr`): `program T64; uses DragLint.Plugin.LintOptionsFrame; begin Writeln('OK'); end.` + `T64_lint_options_compile.bat` (mirror `T52_options.bat`: `dcc64 -U<plugin-src> -U<IDELIB>` so VCL + ToolsAPI DCUs resolve without a running IDE).
- [ ] **Step 2: Run -- confirm build failure** (frame unit missing).
- [ ] **Step 3: Implement the frame** per the structure above -- complete dynamic control construction, catalog JSON parse (`System.JSON`), config overlay, tri-state computation, param editors, and the OTAPI project-dir + ConfigWriter save. Isolate `GetActiveProjDir` (OTAPI) in one function; everything else is plain VCL + JSON.
- [ ] **Step 4: Run the compile-smoke -- confirm it compiles** (`OK`). This proves the unit compiles against VCL+ToolsAPI+ConfigWriter without a running IDE. (It does NOT run the UI -- that is the Task 5 manual gate.)
- [ ] **Step 5: Commit.** `git add src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas tests/fixtures/T64_lint_options_compile.dpr tests/fixtures/T64_lint_options_compile.bat` + `git commit -m "feat(plugin): TLintOptionsFrame (catalog + config round-trip) (v0.69 D1b)"`.

---

## Task 3: Wire the tab into the dock + register both units in the package

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.DockForm.pas`
- Modify: `src/delphi-plugin/dclDragLintWizard.dpk` + `dclDragLintWizard.dproj`

- [ ] **Step 1:** In `DragLint.Plugin.DockForm.pas`: add `DragLint.Plugin.LintOptionsFrame` to `uses`; add `FTabLintOptions: TTabSheet;` to the private fields; in `Create` add `FTabLintOptions := AddTab('Lint Options');` (after the existing `AddTab` calls); in `HandleInitTimer` add `CreateEmbeddedLintOptions(Self, FTabLintOptions);` (alongside the other `CreateEmbeddedXxx` calls).
- [ ] **Step 2:** Register BOTH new units in `dclDragLintWizard.dpk` `contains` (`DRagLint.Lint.ConfigWriter in '..\lint\DRagLint.Lint.ConfigWriter.pas',` and `DragLint.Plugin.LintOptionsFrame in 'DragLint.Plugin.LintOptionsFrame.pas',`) AND in `dclDragLintWizard.dproj` (`<DCCReference Include="..\lint\DRagLint.Lint.ConfigWriter.pas"/>` and `<DCCReference Include="DragLint.Plugin.LintOptionsFrame.pas"/>`). If `DRagLint.Lint.Config`/`DRagLint.Lint.RuleCatalog` are not already in the package (the frame/writer use them), add them too (relative `..\lint\` paths).
- [ ] **Step 3: Commit (source only).** `git add src/delphi-plugin/DragLint.Plugin.DockForm.pas src/delphi-plugin/dclDragLintWizard.dpk src/delphi-plugin/dclDragLintWizard.dproj` + `git commit -m "feat(plugin): wire Lint Options tab into the dock + register units (v0.69 D1b)"`.

---

## Task 4: Build the BPL (RAD Studio closed) + fix compile errors

- [ ] **Step 1: Confirm RAD Studio is closed.** `Get-Process bds -ErrorAction SilentlyContinue` must return nothing. If it is running, STOP and ask the user to close it.
- [ ] **Step 2: Build the BPL.** Run `_bpl_build.bat` via `Start-Process -Wait` redirected to a scratchpad log; read the tail. Expected: `Build succeeded`, no `[dcc64] Error`/`E2xxx`/`F2xxx`. Fix any compile errors in the new units (missing `uses`, VCL control property names, ToolsAPI interface names) and rebuild until clean. Also run the two console tests (T63, T64) to confirm they still pass.
- [ ] **Step 3: Commit any compile fixes (source only).** `git commit -am "fix(plugin): BPL compile fixes for Lint Options tab (v0.69 D1b)"` (only if there were fixes).

---

## Task 5: MANUAL in-IDE gate (the USER runs this) + docs

This task is a checklist for the human; it cannot be automated (no UI test harness).

- [ ] **Step 1: Deploy the BPL.** With RAD Studio CLOSED, run `deploy-staged.bat` (copies the freshly built `dclDragLintWizard.{bpl,dcp}` from `C:\TEMP1\bpl_staging\` into `third_party\dll-win32`). If the build did not stage to `C:\TEMP1\bpl_staging\`, copy the BPL/DCP from the `.dproj` Win32 output (`third_party\dll-win32`) or adjust `deploy-staged.bat`'s source path -- verify the staged BPL timestamp is fresh.
- [ ] **Step 2: Reopen RAD Studio** with a real project open (e.g. ORM3 `Micronite2027.dproj`).
- [ ] **Step 3: Open the drag-lint dock** and confirm a 4th tab **"Lint Options"** appears next to Structure / Search / Find Usages.
- [ ] **Step 4: Verify the catalog loads** -- the tab shows rules grouped by category with a header line like `115 rules across 12 categories, K enabled`. If empty, the exe path / `rules --json` call failed (check `ResolveExe` + that the `rules/` folder sits next to the deployed exe).
- [ ] **Step 5: Toggle a rule** (e.g. uncheck `float-equality-comparison`), toggle a **section tri-state** (uncheck a whole category -> it grays/unchecks all its rules), edit a **param** (set `too-many-parameters` threshold to 9), edit a **naming field** (set a prefix). Save.
- [ ] **Step 6: Confirm the round-trip** -- open the project's `drag-lint-lint.json` on disk and verify it now contains the `disabled` entry, the `thresholds` value, and the `naming` change; re-open the tab and confirm it reflects the saved state. Run `drag-lint lint <a file> --config <that json>` and confirm the disabled rule no longer fires.
- [ ] **Step 7 (docs, agent-writable):** update `CHANGELOG.md` (v0.69 in-progress: "Added (IDE -- D1b): a 4th dock tab 'Lint Options' that loads `drag-lint rules --json` and round-trips the project `drag-lint-lint.json`"); update `docs/lint/MISSING-FEATURES.md` (mark the D1 Lint Options tab item done; the deferred in-IDE Refactor tab stays in section 13). Also decide the D1a follow-up: whether `undeclared-identifier` (index-only) belongs in the catalog -- either add it to the registry or note the exclusion. Commit docs.

---

## Self-Review (completed by plan author)

**Spec coverage (v0.69 spec section 1b):** 4th dock tab via `AddTab` (Task 3); shells out to `drag-lint rules --json` (Task 2); grouped-by-category collapsible sections + tri-state section checkbox + per-rule checkbox (Task 2); inline param editors driven by the catalog `params` (Task 2); counts header (Task 2); reads/writes the active project `drag-lint-lint.json` (Tasks 1-2); OTAPI project-dir isolated + core kept host-agnostic for future `drag-lint-config.exe` hosting (Task 2); BPL manual-test gate (Tasks 4-5). ✓

**Placeholder note (context-constrained):** Tasks 1 and 2 give complete CONTRACTS + the exact surface signatures/snippets (AddTab, OTAPI, ProcRun, ConfigWriter, the two JSON shapes, the .dpk/.dproj wiring, the build/deploy recipe) but describe the ConfigWriter serializer body and the frame's dynamic-control rendering loop as specified algorithms rather than line-by-line code -- a deliberate deviation from the usual no-placeholder rule, made because this plan was written near a context ceiling. The next-session implementer (fresh context) has every integration fact needed; the two bodies are standard `System.JSON` serialization + dynamic-VCL construction. If re-planning with headroom, expand Task 1 Step 3 and Task 2 Step 3 into full code.

**Type/name consistency:** `TLintConfigWriter.ToJson/SetRuleDisabled/SetThreshold/SetSeverity/LoadOrDefault/SaveToFile`; `TLintOptionsFrame.Create/ReloadCatalogAndConfig/Save`; `CreateEmbeddedLintOptions(AOwner,AParent)`; `GetActiveProjDir`; `RunCaptureStdout`; the `rules --json` + `drag-lint-lint.json` key names -- consistent across tasks.

**Known risks:** (1) `TLintConfig` fields are `strict private` -> Task 1 adds public accessors (blast radius: the Config unit only; existing callers unaffected). (2) the BPL deploy source (`C:\TEMP1\bpl_staging\` vs the `.dproj` Win32 output) must be reconciled at Task 5 Step 1. (3) the frame is only compile-smoke-tested headlessly; correctness of the UI is the manual gate. (4) whether `DRagLint.Lint.Config`/`.RuleCatalog` are already in the BPL package must be checked (Task 3 Step 2).
