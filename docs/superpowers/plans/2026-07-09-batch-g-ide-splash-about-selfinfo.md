# Batch G -- IDE splash + About box with on-demand live self-info -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an IDE startup splash (icon + MIT + version) and a Help->About entry that fetches live `drag-lint.exe` self-info on a background thread (with a structured error block for self-diagnosis), backed by a new `drag-lint info --json` verb; prune the now-redundant `Test Connection` debug item. Release as v1.0.0-alpha.

**Architecture:** Two OTA surfaces registered in the wizard's `Register` proc (mirroring TableTools). Startup is 100% static (no exe call) so IDE launch is never blocked; the About memo's live block is fetched by a one-shot background thread after startup and swapped in. A new read-only `info` CLI verb (mirroring `schema`) returns the self-info JSON. build_date comes from `FileAge(ParamStr(0))` (VERIFIED; `{$I %DATE%}` does NOT compile in this toolchain).

**Tech Stack:** Delphi 13 (RAD Studio 37), VCL, Open Tools API (`IOTASplashScreenServices`, `IOTAAboutBoxServices`), `System.JSON`, tree-sitter (`PTSLanguage.Version`), PowerShell autotests.

## Global Constraints

- **Encoding:** all `.pas`/`.dfm`/`.rc` strict 7-bit ASCII, NO BOM, CRLF -- including `///` DocInsight comments.
- **DocInsight (CDD):** every new public type/method/verb gets a `///` spec-comment; comment and test must agree.
- **TDD:** the `info` verb gets a failing test first, run red, then green.
- **No exe call during IDE startup.** The splash + About *entry* use the static plugin version const only. The live exe fetch runs on a background thread AFTER `Register` returns.
- **build_date:** derive via `FileAge(ParamStr(0))` formatted `yyyy-mm-dd hh:nn:ss`. **Do NOT use `{$I %DATE%}`** -- it fails to compile here (`dcc32` reads it as an include directive: `F1026 File not found: '%DATE%.pas'`). Matches the existing `PluginBuildTag` `FileAge` idiom.
- **BPL build rule:** Win32 BPL via delphi-build recipe (rsvars -> cd -> msbuild, PowerShell `Start-Process -Wait`, log; check `BUILD_EXITCODE=0` + no `[dcc32 Error]`/`F2039`). **RAD Studio MUST be closed.**
- **PROCESS RULE (carried from Batch E incident):** a subagent MUST NEVER close the user's RAD Studio. If `bds.exe` is running / the BPL is locked (F2039), STOP and report BLOCKED. No `CloseMainWindow`/`taskkill`/IDE-terminating action.
- **CLI build:** Win64 Debug via rsvars+msbuild (`src/cli/drag-lint.dproj`, `/p:Platform=Win64`); deploy to `src/cli/Win64/Debug/drag-lint.exe` AND `third_party/dll-win64/drag-lint.exe`.
- **Subagent report length:** append "Report in under 200 words." to research/lookup prompts (not to structured-data-returning ones).
- **YAGNI:** no exe call at startup; no cross-session caching; reuse TableTools' icon (no new icon); no new dependency.

---

## File Structure

- `src/cli/DRagLint.CLI.pas` -- new `DoInfo` verb (mirrors `DoSchema`) + dispatch line + usage line.
- `tests/autotest/run_info_verb.ps1` -- headless `info --json` schema/fields test.
- `src/delphi-plugin/Micronite LOGO 4 32x32.ico` -- copied from TableTools.
- `src/delphi-plugin/DragLintSplash.rc` -- `SPLASH_ICON_1 ICON "Micronite LOGO 4 32x32.ico"`.
- `src/delphi-plugin/DragLintSplash.res` -- compiled from the `.rc` (build step / committed).
- `src/delphi-plugin/DragLint.Plugin.About.pas` -- NEW unit: splash registration, About entry, background self-info fetch, error-block formatting, teardown. Keeps `Wizard.pas` thin and the feature testable/isolated.
- `src/delphi-plugin/DragLint.Plugin.Wizard.pas` -- call `RegisterDragLintAbout` in `Register`, `UnregisterDragLintAbout` in teardown; `{$R 'DragLintSplash.res'}`.
- `src/delphi-plugin/DragLint.Plugin.Editor.pas` -- bump `PLUGIN_VERSION`; remove `Test Connection` menu item + `InvokeTestConnection`.
- `src/delphi-plugin/dclDragLintWizard.dpk` / `.dproj` -- add the new unit(s) to `contains`/DCCReference.
- Docs: CHANGELOG, README, AI-USAGE/AI-INDEX-FIRST (the `info` verb).

---

## PHASE 1 -- `drag-lint info --json` verb (headless, TDD)

### Task 1: `DoInfo` verb + headless test

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas`
- Test: `tests/autotest/run_info_verb.ps1`

**Interfaces:**
- Consumes: `VERSION` const (line 6); `FileAge`; `TJSONObject`; the tree-sitter `PTSLanguage.Version` helper (from `TreeSitter.pas`, via `tree_sitter_delphi13`/`tree_sitter_dfm` already declared in `src/lint/DRagLint.Lint.Linter.pas`); the FTS5 self-test logic (`DoSelfTestFts5`, ~line 11148).
- Produces: `function DoInfo(const AArgs: TArgs): Integer;` dispatched by `else if Args.Command = 'info' then Result:= DoInfo(Args)`. Emits `info/1` JSON on `--json`, human text otherwise. Exit 0.

- [ ] **Step 1: Write the failing test `tests/autotest/run_info_verb.ps1`**

```powershell
# run_info_verb.ps1 -- drag-lint info --json emits info/1 with the required self-info fields
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\..\third_party\dll-win64\drag-lint.exe'
$fail = 0
function Check($c,$m){ if(-not $c){Write-Host "FAIL: $m";$script:fail++}else{Write-Host "PASS: $m"} }

$json = & $exe info --json
$o = $json | ConvertFrom-Json
Check ($o.schema -eq 'info/1') 'schema is info/1'
Check ($o.name -eq 'drag-lint') 'name is drag-lint'
Check ($o.version -and $o.version.Length -ge 3) 'version present'
Check ($o.license -eq 'MIT') 'license is MIT'
Check ($o.build_date -match '^\d{4}-\d{2}-\d{2}') 'build_date looks like a date'
Check ($null -ne $o.tree_sitter) 'tree_sitter block present'
Check ($null -ne $o.capabilities) 'capabilities block present'
Check ($o.exe_path -and (Test-Path $o.exe_path)) 'exe_path resolves to a real file'
Check ($o.platform -eq 'Win64' -or $o.platform -eq 'Win32') 'platform is Win32|Win64'

# text form (no --json) must also work and not error
$txt = & $exe info
Check ($LASTEXITCODE -eq 0) 'info (text) exits 0'
Check ($txt -match 'MIT') 'text form mentions MIT'

if ($fail){Write-Host "RESULT: FAIL ($fail)";exit 1}else{Write-Host 'RESULT: PASS';exit 0}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `.\tests\autotest\run_info_verb.ps1` (native pwsh call, NOT `powershell -File` -- `$PSScriptRoot` collapses otherwise; known env quirk).
Expected: FAIL (`info` is not a known command yet -> non-JSON output / error).

- [ ] **Step 3: Implement `DoInfo`**

Add near `DoSchema` in `src/cli/DRagLint.CLI.pas`. Use the tree-sitter language version via the existing externals. To reach `tree_sitter_delphi13`/`tree_sitter_dfm` + the `.Version` helper, ensure the unit's uses includes the tree-sitter unit that declares them (grep: `src/lint/DRagLint.Lint.Linter.pas` declares `tree_sitter_dfm`; `TreeSitter.pas` provides `TTSLanguageHelper.Version`). If wiring the externals into CLI.pas is heavy, emit `"unknown"` for a grammar whose version cannot be obtained -- do NOT fabricate. Prefer the real version if reachable with a small `external 'tree-sitter-delphi13'` decl local to CLI.pas (mirroring how Linter.pas declares them).

```pascal
/// <summary>drag-lint info [--json] -- prints engine self-info: version, build
/// date (from the exe's own file timestamp), MIT license, description,
/// tree-sitter grammar versions, capabilities (FTS5, CLI verb count), the exe
/// path, and the build platform. Read-only; no DB, no side effects. --json emits
/// the stable schema "info/1"; without it, a human-readable block. Consumed by
/// the IDE About box.</summary>
/// <returns>0 always.</returns>
function DoInfo(const AArgs: TArgs): Integer;
var
  UseJson  : Boolean;
  BuildDate: string;
  Age      : TDateTime;
  ExePath  : string;
  Plat     : string;
  Fts5     : Boolean;
  TsDelphi : string;
  TsDfm    : string;
  JRoot, JTs, JCap: TJSONObject;
begin
  Result := 0;
  UseJson := AArgs.UseJson or SameText(AArgs.Format, 'json');
  ExePath := ParamStr(0);
  if FileAge(ExePath, Age) then BuildDate := FormatDateTime('yyyy-mm-dd hh:nn:ss', Age)
  else BuildDate := 'unknown';
  {$IFDEF WIN64} Plat := 'Win64'; {$ELSE} Plat := 'Win32'; {$ENDIF}
  Fts5 := ProbeFts5Available;            { small helper: try/except the FTS5 create, mirrors DoSelfTestFts5 }
  TsDelphi := TreeSitterGrammarVersion(@tree_sitter_delphi13);  { returns 'N' or 'unknown' }
  TsDfm    := TreeSitterGrammarVersion(@tree_sitter_dfm);

  if UseJson then
  begin
    JRoot := TJSONObject.Create;
    try
      JRoot.AddPair('schema', 'info/1');
      JRoot.AddPair('name', 'drag-lint');
      JRoot.AddPair('version', VERSION);
      JRoot.AddPair('build_date', BuildDate);
      JRoot.AddPair('license', 'MIT');
      JRoot.AddPair('description', 'symbol-aware index + RAG + lint for Delphi/Pascal');
      JTs := TJSONObject.Create;
      JTs.AddPair('delphi13', TsDelphi);
      JTs.AddPair('dfm', TsDfm);
      JRoot.AddPair('tree_sitter', JTs);
      JCap := TJSONObject.Create;
      JCap.AddPair('fts5', TJSONBool.Create(Fts5));
      JCap.AddPair('cli_verbs', TJSONNumber.Create(CLI_VERB_COUNT));  { small static const, see note }
      JRoot.AddPair('capabilities', JCap);
      JRoot.AddPair('exe_path', ExePath);
      JRoot.AddPair('platform', Plat);
      Writeln(JRoot.ToJSON);
    finally
      JRoot.Free;
    end;
  end
  else
  begin
    Writeln('drag-lint ', VERSION, '  (built ', BuildDate, ')');
    Writeln('License: MIT');
    Writeln('symbol-aware index + RAG + lint for Delphi/Pascal');
    Writeln('tree-sitter: delphi13 ', TsDelphi, ' / dfm ', TsDfm);
    Writeln('capabilities: FTS5=', BoolToStr(Fts5, True), ', CLI verbs=', CLI_VERB_COUNT);
    Writeln('exe: ', ExePath, '   platform: ', Plat);
  end;
end;
```

Helper `TreeSitterGrammarVersion` (put near DoInfo): calls the language's `ts_language_version` via the `PTSLanguage.Version` helper inside a try/except; returns the integer as a string or `'unknown'` on any failure. `ProbeFts5Available`: the try/except FTS5-create-and-match from `DoSelfTestFts5`, returning Boolean instead of printing. `CLI_VERB_COUNT`: a small `const` (approximate is fine -- e.g. `60`; this is informational, not load-bearing). Add local `external 'tree-sitter-delphi13'`/`'tree-sitter-dfm'` decls if not already visible in CLI.pas (mirror `DRagLint.Lint.Linter.pas`).

- [ ] **Step 4: Add the dispatch + usage lines**

Dispatch (near line 11512, after the `schema` branch):
```pascal
    else if Args.Command = 'info'              then Result:= DoInfo            (Args)
```
Usage (near the other verb usage `Writeln`s):
```pascal
  Writeln('  drag-lint info [--json]                              (engine self-info: version, build date, MIT, tree-sitter + capabilities; read-only)');
```

- [ ] **Step 5: Rebuild CLI Win64 Debug, deploy, run the test to green**

Build (delphi-build recipe, Win64). Deploy exe to `src/cli/Win64/Debug/` + `third_party/dll-win64/`.
Run: `.\tests\autotest\run_info_verb.ps1` -> `RESULT: PASS`.

- [ ] **Step 6: Regression -- run one existing test to confirm no dispatch breakage**

Run: `.\tests\autotest\run_reverse_calltree.ps1` -> still PASS.

- [ ] **Step 7: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/autotest/run_info_verb.ps1
git commit -m "feat(cli): drag-lint info [--json] verb -- engine self-info (version/build_date/MIT/tree-sitter/caps) for the IDE About box"
```

---

## PHASE 2 -- Icon resource + splash + About (BPL; live-smoke, no headless UI test)

> Every task below rebuilds the Win32 BPL. **PROCESS RULE: never close RAD Studio; if `bds.exe`/F2039, STOP and report BLOCKED.**

### Task 2: Icon resource + `.rc`/`.res` wiring

**Files:**
- Create: `src/delphi-plugin/Micronite LOGO 4 32x32.ico` (copied), `src/delphi-plugin/DragLintSplash.rc`, `src/delphi-plugin/DragLintSplash.res`
- Modify: `src/delphi-plugin/DragLint.Plugin.Wizard.pas` (`{$R 'DragLintSplash.res'}`)

**Interfaces:**
- Produces: a linked resource `SPLASH_ICON_1` (type ICON) in the BPL, loadable via `LoadImage(HInstance, 'SPLASH_ICON_1', IMAGE_ICON, ...)`.

- [ ] **Step 1: Copy the icon**

```bash
cp "C:/Projects/TableTools/Micronite LOGO 4 32x32.ico" "C:/Projects/Delphi-RAG-lint/src/delphi-plugin/Micronite LOGO 4 32x32.ico"
```

- [ ] **Step 2: Create `DragLintSplash.rc`** (ASCII, CRLF):

```
SPLASH_ICON_1 ICON "Micronite LOGO 4 32x32.ico"
```

- [ ] **Step 3: Compile the `.rc` to `.res`**

Use the RAD Studio resource compiler (rc/brcc32) via a wrapper, from `src/delphi-plugin/`:
```
brcc32 DragLintSplash.rc
```
(or `rc.exe /r DragLintSplash.rc`). Confirm `DragLintSplash.res` is produced. If `brcc32` isn't on PATH, load rsvars first (same wrapper pattern as the BPL build). Commit the `.res` (it's a build input referenced by `{$R}`).

- [ ] **Step 4: Reference the resource from the wizard unit**

In `DragLint.Plugin.Wizard.pas`, near the top of the implementation (after any existing `{$R}`), add:
```pascal
{$R 'DragLintSplash.res'}
```
(TableTools uses exactly this `{$R 'name.res'}` form.)

- [ ] **Step 5: Build the BPL (RAD Studio CLOSED), confirm the resource links**

delphi-build -> Win32, 0 errors. **If `bds.exe` running: STOP, report BLOCKED.** (Resource-link verification proper is the splash showing in-IDE -- a smoke item; here confirm 0 build errors with the `{$R}` present.)

- [ ] **Step 6: Commit**

```bash
git add "src/delphi-plugin/Micronite LOGO 4 32x32.ico" src/delphi-plugin/DragLintSplash.rc src/delphi-plugin/DragLintSplash.res src/delphi-plugin/DragLint.Plugin.Wizard.pas
git commit -m "build(plugin): add SPLASH_ICON_1 resource (reused TableTools icon) + {\$R} wiring for the IDE splash/About"
```

---

### Task 3: `DragLint.Plugin.About.pas` -- splash + About entry + background self-info + error block

**Files:**
- Create: `src/delphi-plugin/DragLint.Plugin.About.pas`
- Modify: `src/delphi-plugin/DragLint.Plugin.Wizard.pas` (call register/unregister), `dclDragLintWizard.dpk` + `.dproj` (add the unit)

**Interfaces:**
- Consumes: `SplashScreenServices`, `(BorlandIDEServices as IOTAAboutBoxServices)`, `PLUGIN_VERSION` (Editor.pas), `RunAndCaptureStdout` + `DLExe64` (Editor.pas interface -- the exe resolver + runner already used by the butterfly/RCT actions), `GetPluginLogPath`.
- Produces: `procedure RegisterDragLintAbout;` and `procedure UnregisterDragLintAbout;` (both parameterless, idempotent), called from `Wizard.Register` / teardown.

- [ ] **Step 1: Write the unit skeleton with DocInsight + the static registration**

Create `DragLint.Plugin.About.pas`. `RegisterDragLintAbout`:
1. Build the icon bitmap once (`LoadImage('SPLASH_ICON_1')` -> `TIcon` -> `TBitmap`); keep its `HBITMAP` for both surfaces.
2. Splash: `if Assigned(SplashScreenServices) then SplashScreenServices.AddPluginBitmap('drag-lint', Bmp.Handle, False, 'MIT', PLUGIN_VERSION);`
3. About: `if Supports(BorlandIDEServices, IOTAAboutBoxServices, ABS) then GAboutIndex := ABS.AddPluginInfo('drag-lint', StaticDescription, Bmp.Handle, False, 'MIT', PLUGIN_VERSION);` -- save `GAboutIndex: Integer` (module var, init `-1`).
4. `ForceDemandLoadState(dlDisable);` (so `Register` runs at startup for the splash).
5. Kick the background fetch (Step 3).

`StaticDescription` (a function): returns the static seed block:
```
drag-lint -- symbol-aware index + RAG + lint for Delphi/Pascal
License: MIT
Plugin: <PLUGIN_VERSION> (BPL built <FileAge(GetModuleName(HInstance))>)
Engine info: querying...
```

DocInsight `///` on both public procs (summary + remarks: "call from Register; startup-safe, no exe call on this thread").

- [ ] **Step 2: Background live-fetch + memo swap + error block**

`RegisterDragLintAbout` (end) starts a one-shot `TThread.CreateAnonymousThread` that:
- runs `RunAndCaptureStdout('"<DLExe64>" info --json', Out, 8000)`.
- On success + parseable JSON: format `LiveBlock` (engine version/build_date, exe path, platform, tree-sitter, caps, + `Plugin log: <GetPluginLogPath>`).
- On failure: format `ErrorBlock` per the spec (resolved path, exe-not-found / spawn-failed / non-zero-exit+stderr / timeout / unparseable-output, + log path).
- Marshal via `TThread.Queue` to the main thread: `if Assigned(ABS) and (GAboutIndex >= 0) then begin ABS.RemovePluginInfo(GAboutIndex); GAboutIndex := ABS.AddPluginInfo('drag-lint', StaticDescription-minus-"querying" + #13#10 + Block, Bmp.Handle, False, 'MIT', PLUGIN_VERSION); end`.

> **PLANNING CHECK (do this first in Task 3):** verify in a live IDE whether `RemovePluginInfo` + re-`AddPluginInfo` after startup actually updates the visible About entry in RAD 37. This cannot be confirmed headlessly. Because the batch is autonomous-until-smoke, implement the swap path AND guard it so that if it turns out not to refresh, the fallback (below) still delivers the requirement. Document the assumption in the report; the user's smoke test is the confirmation.
>
> **Fallback (if the swap doesn't refresh):** keep the About entry static (icon+MIT+version+static description), and add a Tools->drag-lint menu item **"About / Engine info..."** that runs `info --json` on click (backgrounded, ~200ms) and shows the live block + error block in a `ShowMessage`/dialog. This still satisfies "live exe info + error surfacing, no startup block." The plan's Task 5 (debug prune) removes `Test Connection` either way, since this dialog (or the About memo) covers it.

- [ ] **Step 3: Teardown**

`UnregisterDragLintAbout`: `if Assigned(ABS) and (GAboutIndex >= 0) then ABS.RemovePluginInfo(GAboutIndex); GAboutIndex := -1;` Free the retained bitmap. Idempotent (guard on `GAboutIndex >= 0`). (Splash entries are not removable -- that's fine, they're startup-only.)

- [ ] **Step 4: Wire into the package**

- `dclDragLintWizard.dpk`: add `DragLint.Plugin.About in 'DragLint.Plugin.About.pas'` to `contains`.
- `.dproj`: add the matching `<DCCReference Include="DragLint.Plugin.About.pas"/>`.
- (LESSON from Batch B: a unit in `.dproj` DCCReference but NOT `.dpk contains` + unreferenced does NOT compile. Both, plus the `Register`-proc call in Task 4, ensure it builds.)

- [ ] **Step 5: Build the BPL (RAD Studio CLOSED)**

delphi-build -> Win32, 0 errors. **If `bds.exe` running: STOP, report BLOCKED.**

- [ ] **Step 6: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.About.pas src/delphi-plugin/dclDragLintWizard.dpk src/delphi-plugin/dclDragLintWizard.dproj
git commit -m "feat(ide): splash + About box (static entry, backgrounded live exe self-info, structured error block)"
```

---

### Task 4: Wire register/unregister into the wizard + bump PLUGIN_VERSION

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.Wizard.pas`, `src/delphi-plugin/DragLint.Plugin.Editor.pas`

**Interfaces:**
- Consumes: `RegisterDragLintAbout`/`UnregisterDragLintAbout` (Task 3).

- [ ] **Step 1: Bump PLUGIN_VERSION to match the release**

In `DragLint.Plugin.Editor.pas` line 28, change `PLUGIN_VERSION = 'v0.40.5-alpha';` to `PLUGIN_VERSION = 'v1.0.0-alpha';`. (This is the stale const the About box surfaces; align it to the release version.)

- [ ] **Step 2: Call register in `Register`, unregister in teardown**

In `DragLint.Plugin.Wizard.pas` `Register` (after `RegisterPackageWizard`):
```pascal
  try RegisterDragLintAbout; except end;
```
In the wizard teardown (wherever `UnregisterDragLintOptions`/`UnregisterProjectMenu` are called -- `Wizard.Destroyed` + finalization), add:
```pascal
  try UnregisterDragLintAbout; except end;
```
Add `DragLint.Plugin.About` to the `Wizard.pas` uses.

- [ ] **Step 3: Build the BPL (RAD Studio CLOSED)**

delphi-build -> Win32, 0 errors. **If `bds.exe` running: STOP, report BLOCKED.**

- [ ] **Step 4: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.Wizard.pas src/delphi-plugin/DragLint.Plugin.Editor.pas
git commit -m "feat(ide): register splash/About in wizard Register + teardown; bump PLUGIN_VERSION v0.40.5->v1.0.0-alpha"
```

---

### Task 5: Prune the redundant `Test Connection` debug item

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.Editor.pas`

**Interfaces:**
- (removal only)

- [ ] **Step 1: Remove the menu item**

In `RegisterDragLintMenu` (Editor.pas ~4104), delete:
```pascal
  AddWrappedItem(RootMenu, 'Test Connection...'             , InvokeTestConnection );
```
Keep `Open Plugin Log` and all others.

- [ ] **Step 2: Remove `InvokeTestConnection` + its interface declaration**

Delete the `InvokeTestConnection` implementation and its interface-section `procedure InvokeTestConnection(Sender: TObject);` declaration. Grep first to confirm nothing else references it (Keyboard.pas, ProjectMenu.pas, etc.); if a keybinding references it, remove that too. If `PluginBuildTag` becomes unused after this removal, leave it (it may be used by the About static description / elsewhere -- grep to confirm; only remove if truly unreferenced).

- [ ] **Step 3: Build the BPL (RAD Studio CLOSED)**

delphi-build -> Win32, 0 errors (a clean build proves `InvokeTestConnection` had no remaining references). **If `bds.exe` running: STOP, report BLOCKED.**

- [ ] **Step 4: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.Editor.pas
git commit -m "refactor(ide): remove Test Connection debug item -- superseded by the About box live-info + error block"
```

---

## PHASE 3 -- Verify, docs, release

### Task 6: Battery + version bump + docs + consolidated BPL

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (VERSION), CHANGELOG, README, docs/AI-USAGE, docs/AI-INDEX-FIRST

- [ ] **Step 1: Run the full battery + the new test**

Run each (native pwsh), confirm `RESULT: PASS` / exit 0:
`run_info_verb.ps1`, `run_forward_calltree.ps1`, `run_naming_presets_roundtrip.ps1`, `run_reverse_calltree.ps1`, `run_self_field_refs.ps1`, `run_bare_rhs_refs.ps1`, `run_naming_prefix_autofix.ps1`, `run_naming_autofix.ps1`, `run_deps_report.ps1`, `run_manifest.ps1`, `tests/autofix/run_fixable_catalog.ps1`.

- [ ] **Step 2: Version bump v1.0.0-alpha**

`src/cli/DRagLint.CLI.pas` `VERSION` `'0.99.0-alpha'` -> `'1.0.0-alpha'`. Rebuild CLI Win64 Debug, confirm `drag-lint --version` = `1.0.0-alpha` AND `drag-lint info --json` version = `1.0.0-alpha`, deploy both locations.

- [ ] **Step 3: Docs**

- CHANGELOG: `## v1.0.0-alpha` section -- IDE splash + About box (live engine self-info + error block), new `info --json` verb, `Test Connection` removed.
- README: mention the startup splash + Help->About entry; add `info` to the CLI command list/section.
- AI-USAGE / AI-INDEX-FIRST: add `drag-lint info [--json]` to the verb list (read-only self-info; note it's what the IDE About box calls).

- [ ] **Step 4: Commit docs + version**

```bash
git add -A
git commit -m "chore(release): v1.0.0-alpha -- version bump + CHANGELOG/README/AI-docs for splash/About + info verb"
```

- [ ] **Step 5: Final Win32 BPL rebuild carrying all IDE changes (RAD Studio CLOSED)**

delphi-build -> Win32, 0 errors; confirm deploy to `third_party/dll-win32/`. **If `bds.exe` running: STOP, report BLOCKED.**

```bash
git add third_party/dll-win32
git commit -m "build(plugin): rebuild Win32 BPL carrying Batch G (splash/About + info verb + Test Connection removal)"
```

---

### Task 7: Final whole-branch review + release + YADF note (DRAFT)

- [ ] **Step 1: Final whole-branch review** (superpowers:requesting-code-review, most-capable model). Address Critical/Important; defer Minor with a note. Re-run affected tests after any fix.

- [ ] **Step 2: Pack + release** -- `pack-lint-release.ps1 -Version 1.0.0-alpha`; push `main`; tag `v1.0.0-alpha`; `gh release create` with both CLI zips + the Win32 BPL, marked Latest. (Follow the exact v0.99 release flow.)

- [ ] **Step 3: Write the YADF porting note as a DRAFT**

Write `C:\Projects\YADF\docs\PORT-ide-splash-and-about.md` (confirm the path with the user first; prior note at `PORT-tools-options-page.md`). Cover: the `Register`-proc splash + `ForceDemandLoadState` pattern; the icon `.rc` + `{$R 'name.res'}` wiring; the About entry + background-fetch/error-block pattern (and the swap-vs-menu-fallback finding); the `FileAge` build-date method + the `{$I %DATE%}` trap; the `info --json` verb shape for YADFOT's own exe; the debug-prune rationale. **Mark the note header "DRAFT -- pending user live-IDE smoke confirmation of drag-lint's splash/About."** Do NOT commit it in the YADF repo yet (prior note convention: written, not committed). Report the path to the user.

- [ ] **Step 4: Update BACKLOG resume-point + auto-memory** for the batch, listing the pending user smoke checklist and the YADF-note-finalization step.

---

## Live-IDE smoke checklist (USER runs; NOT headless) -- gates the YADF note finalization

- **Splash:** on IDE startup, the drag-lint logo + `drag-lint (MIT) v1.0.0-alpha` appears on the splash screen.
- **About static:** Help -> About -> drag-lint shows the icon, MIT, version, and the static description block.
- **About live:** after startup, the About memo shows the live engine block (exe version + build date + tree-sitter + caps + log path).
- **About error self-test:** temporarily rename/remove `drag-lint.exe` beside the BPL (and off PATH) -> the About memo (or the fallback menu dialog) shows the **error block** naming the resolved path + failure reason.
- **Debug menu:** `Test Connection...` is gone; `Open Plugin Log` + the rest still work.
- **(If the About-swap didn't refresh)**: the "About / Engine info..." menu item shows the live block/error block instead -- report which path was used.

---

## Self-Review notes

- **Spec coverage:** info verb (Task 1), icon/resource (Task 2), splash+About+error block (Task 3), wiring+version bump (Task 4), debug prune (Task 5), verify/docs/release (Task 6), review+release+YADF draft (Task 7). All spec sections mapped.
- **Verified-not-assumed:** `FileAge` build-date compiles+runs; `{$I %DATE%}` does NOT (both checked). `PTSLanguage.Version` exists for real tree-sitter versions. `PLUGIN_VERSION` is stale (`v0.40.5-alpha`) -> bumped. `Wizard.pas` already uses ToolsAPI. TableTools' `{$R 'name.res'}` + `AddPluginBitmap` + `ForceDemandLoadState` pattern is the proven precedent.
- **The one live-only uncertainty** (can About memo refresh after startup?) is handled with an implemented swap path PLUS a menu-dialog fallback, both satisfying the requirement; the user's smoke test picks the winner. This is called out in Task 3 and the smoke checklist.
- **Type consistency:** `DoInfo`/`info/1` schema fields match the test's assertions; `RegisterDragLintAbout`/`UnregisterDragLintAbout` defined in Task 3, called in Task 4; `GAboutIndex` init `-1`, guarded on teardown.
- **Process:** every BPL task carries the "never close RAD Studio -> BLOCKED" rule.
