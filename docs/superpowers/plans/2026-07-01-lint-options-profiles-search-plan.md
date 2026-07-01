# Lint Options: full-config profiles + rule search -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the "Lint Options" IDE tab save/load COMPLETE named profiles (enable/disable + severity + thresholds + naming) via an editable combo, and live-filter the rule list with a search box.

**Architecture:** Two config-layer changes (console-testable, pure `System.JSON`) plus two VCL-frame changes (compile-smoke + human gate). `TLintConfig.Load` gains full-profile override; `TLintConfigWriter` gains `ListProfileNames`/`SaveToProfile`; the frame gains a profile combo (retargeting the existing Save button) and a search filter (re-render from the cached catalog JSON). Spec: `docs/superpowers/specs/2026-07-01-lint-options-profiles-search-design.md`.

**Tech Stack:** Delphi 13 (Studio 37), `System.JSON`, plain VCL (`Vcl.StdCtrls` `TComboBox`/`TEdit`), the design-time BPL `dclDragLintWizard` (Win32), dcc64 console tests.

## Global Constraints

- **Encoding (every `.pas`/`.dpr`):** strict 7-bit ASCII, CRLF, no BOM. Editor writes LF -> normalize + byte-verify each touched file (`0` bytes > 127). `.md` may keep pre-existing non-ASCII. `.dproj`/`.dpk` keep existing line endings.
- **Pascal comments:** never a bare `}` or nested `{` inside a `{ }` comment.
- **DocInsight:** `///` `<summary>` on every new public type/method.
- **`TDictionary` inserts use `AddOrSetValue`**, never `Dict[key] := value` (SetItem raises "Item not found" on a missing key).
- **Profile override semantics (Part A):** a profile REPLACES the base per top-level key it defines (`disabled`/`enabled` lists replaced; `severity`/`thresholds` maps replaced; `naming` fields present overridden); keys the profile OMITS inherit base. `short_identifier_check` is a JSON STRING "true"/"false" in a profile too.
- **BUILD IS WIN32:** the IDE is 32-bit; build the plugin `Platform=Win32` -> outputs to `third_party\dll-win32` (the IDE's load path). `_bpl_build.bat` already does Win32. RAD Studio must be CLOSED to overwrite the loaded BPL; build to a scratch `DCC_BplOutput` to verify while the IDE is open.
- **New dock content is a code-built `TForm`+`CreateNew`** (already true for `TLintOptionsFrame`); resolve the engine via the Win64-preferring `ResolveExe` (already in place).
- **Commit SOURCE ONLY** (no `.exe`/`.bpl`/`.dcp`/`.dcu`).

---

## Task 1: `TLintConfig.Load` -- full-profile override (console-testable)

**Files:**
- Modify: `src/lint/DRagLint.Lint.Config.pas`
- Create: `tests/fixtures/T65_profile_apply.dpr`, `tests/fixtures/T65_profile_apply.bat`

**Interfaces:**
- Produces: unchanged public signature `class function TLintConfig.Load(const APath, AProfile: string): TLintConfig; static;` but with full-profile override behavior. New PRIVATE helpers on `TLintConfig`: `procedure ApplyConfigObject(const AObj: TJSONObject; AReplace: Boolean);` and `procedure ApplyNamingObject(const ANaming: TJSONObject);`.
- Consumes: existing strict-private fields `FDisabled/FEnabled/FSevNames/FSevValues/FThreshNames/FThreshValues` + public `Naming`.

- [ ] **Step 1: Write the failing console test.**
Create `tests/fixtures/T65_profile_apply.dpr` (mirror `tests/fixtures/T59_workspace_config.dpr` structure -- `{$APPTYPE CONSOLE}`, a manual `Pass/Fail` counter, print `t65: N pass / M fail`):
```pascal
program T65_profile_apply;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils, DRagLint.Lint.Config;
var Pass, Fail: Integer;
procedure Check(ACond: Boolean; const AMsg: string);
begin if ACond then Inc(Pass) else begin Inc(Fail); Writeln('FAIL: ', AMsg); end; end;
var Tmp: string; Base, Prof: TLintConfig;
begin
  Pass:= 0; Fail:= 0;
  Tmp:= TPath.Combine(TPath.GetTempPath, 't65.json');
  TFile.WriteAllText(Tmp,
    '{'#10 +
    '  "disabled": ["magic-number"],'#10 +
    '  "thresholds": { "deep-nesting": 5, "too-many-parameters": 7 },'#10 +
    '  "naming": { "param_prefix": "", "min_identifier_len": 3 },'#10 +
    '  "profiles": {'#10 +
    '    "strict": {'#10 +
    '      "disabled": ["float-equality-comparison"],'#10 +
    '      "thresholds": { "deep-nesting": 2 },'#10 +
    '      "naming": { "param_prefix": "p", "short_identifier_check": "true" }'#10 +
    '    }'#10 +
    '  }'#10 +
    '}');
  { base (no profile) }
  Base:= TLintConfig.Load(Tmp, '');
  Check(not Base.IsEnabled('magic-number'), 'base disables magic-number');
  Check(Base.ThresholdFor('deep-nesting', 99) = 5, 'base deep-nesting=5');
  Check(Base.ThresholdFor('too-many-parameters', 99) = 7, 'base tmp=7');
  Check(Base.Naming.ParamPrefix = '', 'base param_prefix empty');
  Check(Base.Naming.ShortIdentifierCheck = False, 'base short-check off');
  { profile "strict" overrides }
  Prof:= TLintConfig.Load(Tmp, 'strict');
  Check(not Prof.IsEnabled('float-equality-comparison'), 'profile disables float-eq');
  Check(Prof.IsEnabled('magic-number'), 'profile REPLACES disabled -> magic-number back on');
  Check(Prof.ThresholdFor('deep-nesting', 99) = 2, 'profile overrides deep-nesting=2');
  Check(Prof.ThresholdFor('too-many-parameters', 99) = 7, 'omitted threshold inherits base=7');
  Check(Prof.Naming.ParamPrefix = 'p', 'profile naming param_prefix=p');
  Check(Prof.Naming.ShortIdentifierCheck = True, 'profile short-check TRUE (string parsed)');
  Check(Prof.Naming.MinIdentifierLen = 3, 'omitted naming field inherits base=3');
  TFile.Delete(Tmp);
  Writeln(Format('t65: %d pass / %d fail', [Pass, Fail]));
end.
```
Create `tests/fixtures/T65_profile_apply.bat` mirroring `tests/fixtures/T63_lint_config_roundtrip.bat` (the WORKING pattern: `call rsvars.bat` then a SEPARATE `dcc64` line -- NOT the `&&`-chained form; `-U..\..\src\lint -U..\..\src\core`; gate on the output containing `0 fail`).

- [ ] **Step 2: Run -- confirm it FAILS.** `cd "$(git rev-parse --show-toplevel)" && cmd /c "tests\fixtures\T65_profile_apply.bat"` -> the "profile REPLACES disabled" / "profile overrides deep-nesting=2" / naming assertions FAIL (current `Load` only appends disabled/enabled from a profile, ignores its thresholds/naming).

- [ ] **Step 3: Refactor `Load` + add the helpers.** In `DRagLint.Lint.Config.pas`:
  1. Add to the `strict private` section: `procedure ApplyConfigObject(const AObj: TJSONObject; AReplace: Boolean);` and `procedure ApplyNamingObject(const ANaming: TJSONObject);`.
  2. Move the existing top-level parsing of `severity`/`thresholds`/`naming` (currently inline in `Load`, ~lines 135-188) and the `disabled`/`enabled` handling into `ApplyConfigObject`:
```pascal
procedure TLintConfig.ApplyConfigObject(const AObj: TJSONObject; AReplace: Boolean);
var Pair: TJSONPair; V: TJSONValue;
begin
  if AObj = nil then Exit;
  if AObj.GetValue('disabled') is TJSONArray then
  begin
    if AReplace then FDisabled:= nil;
    for V in (AObj.GetValue('disabled') as TJSONArray) do FDisabled:= FDisabled + [V.Value];
  end;
  if AObj.GetValue('enabled') is TJSONArray then
  begin
    if AReplace then FEnabled:= nil;
    for V in (AObj.GetValue('enabled') as TJSONArray) do FEnabled:= FEnabled + [V.Value];
  end;
  if AObj.GetValue('severity') is TJSONObject then
  begin
    if AReplace then begin FSevNames:= nil; FSevValues:= nil; end;
    for Pair in (AObj.GetValue('severity') as TJSONObject) do
    begin FSevNames:= FSevNames + [Pair.JsonString.Value]; FSevValues:= FSevValues + [Pair.JsonValue.Value]; end;
  end;
  if AObj.GetValue('thresholds') is TJSONObject then
  begin
    if AReplace then begin FThreshNames:= nil; FThreshValues:= nil; end;
    for Pair in (AObj.GetValue('thresholds') as TJSONObject) do
    begin FThreshNames:= FThreshNames + [Pair.JsonString.Value]; FThreshValues:= FThreshValues + [StrToIntDef(Pair.JsonValue.Value, 0)]; end;
  end;
  if AObj.GetValue('naming') is TJSONObject then
    ApplyNamingObject(AObj.GetValue('naming') as TJSONObject);
end;
```
  3. `ApplyNamingObject` = the EXISTING naming-parse block body (the `type_prefix`/`field_prefix`/.../`hungarian_prefixes` reads at current lines ~157-187), verbatim, operating on the passed `NJ` (field-wise override; no replace flag needed).
  4. Rewrite `Load` to:
```pascal
Result:= Default(TLintConfig);
Result.Naming:= TNamingConfig.Default;
if (APath = '') or (not TFile.Exists(APath)) then Exit;
RawText:= TFile.ReadAllText(APath, TEncoding.UTF8);
RootVal:= TJSONObject.ParseJSONValue(RawText);
if not (RootVal is TJSONObject) then begin RootVal.Free; Exit; end;
try
  Root:= RootVal as TJSONObject;
  Result.ApplyConfigObject(Root, False);   { top-level (empty start; append == set) }
  if (AProfile <> '') and (Root.GetValue('profiles') is TJSONObject) then
  begin
    Profiles:= Root.GetValue('profiles') as TJSONObject;
    if Profiles.GetValue(AProfile) is TJSONObject then
      Result.ApplyConfigObject(Profiles.GetValue(AProfile) as TJSONObject, True);  { profile overrides }
  end;
finally
  RootVal.Free;
end;
```
  Delete the now-dead `MergeListsFrom` method (or keep it only if still referenced; the new path replaces it). Keep every existing public method (`ApplySeverity`/`ShouldKeep`/`IsEnabled`/`ThresholdFor`/`AddEnabled`/`AddDisabled` + the D1b read accessors/mutators) UNCHANGED.

- [ ] **Step 4: Run -- confirm GREEN.** `cmd /c "tests\fixtures\T65_profile_apply.bat"` -> `t65: 12 pass / 0 fail`. Normalize + ASCII-verify `Config.pas` + the `.dpr`.

- [ ] **Step 5: Regression + commit.** Re-run `tests\fixtures\T63_lint_config_roundtrip.bat` (`35 pass / 0 fail`) to confirm the refactor didn't break the top-level round-trip. Then `git add src/lint/DRagLint.Lint.Config.pas tests/fixtures/T65_profile_apply.dpr tests/fixtures/T65_profile_apply.bat` + `git commit -m "feat(config): profiles override full config (thresholds/naming/severity), not just enable/disable"`.

---

## Task 2: `TLintConfigWriter` -- `ListProfileNames` + `SaveToProfile` (console-testable)

**Files:**
- Modify: `src/lint/DRagLint.Lint.ConfigWriter.pas`
- Modify: `tests/fixtures/T63_lint_config_roundtrip.dpr` (add profile assertions)

**Interfaces:**
- Produces:
  - `class function ListProfileNames(const APath: string): TArray<string>; static;`
  - `class procedure SaveToProfile(const APath, AName: string; const ACfg: TLintConfig); static;`
  - New private helpers: `class function BuildOwnedObject(const ACfg: TLintConfig): TJSONObject; static;` (the object `ToJson` builds) and `class procedure WriteAnsiCrlf(const APath, AJson: string); static;` (the normalize+ANSI-bytes write currently inline in `SaveToFile`).
- Consumes: Task 1's schema (a profile object holds the same owned keys).

- [ ] **Step 1: Write the failing test additions.** In `tests/fixtures/T63_lint_config_roundtrip.dpr`, after the existing assertions, add a block:
```pascal
{ --- profiles (Task 2) --- }
var PPath: string:= TPath.Combine(TPath.GetTempPath, 't63_prof.json');
TFile.WriteAllText(PPath,
  '{ "thresholds": { "deep-nesting": 5 },'#10 +
  '  "profiles": { "keep": { "disabled": ["x"] } } }');
var PCfg: TLintConfig:= TLintConfigWriter.LoadOrDefault(PPath);
TLintConfigWriter.SetThreshold(PCfg, 'deep-nesting', 9);
TLintConfigWriter.SaveToProfile(PPath, 'strict', PCfg);   { write current cfg as profile "strict" }
var Names: TArray<string>:= TLintConfigWriter.ListProfileNames(PPath);
Check((Length(Names) = 2), 't63: two profiles after save');   { keep + strict }
{ re-read raw: base thresholds preserved, other profile preserved, new profile has the value }
var Raw: string:= TFile.ReadAllText(PPath);
Check(Pos('"keep"', Raw) > 0, 't63: existing profile keep preserved');
Check(Pos('"strict"', Raw) > 0, 't63: new profile strict written');
{ loading with the profile applies its thresholds }
var Applied: TLintConfig:= TLintConfig.Load(PPath, 'strict');
Check(Applied.ThresholdFor('deep-nesting', 0) = 9, 't63: profile strict deep-nesting=9');
TFile.Delete(PPath);
```
(Adjust the pass/fail counter total accordingly.) Update the `.bat` if needed (no path change).

- [ ] **Step 2: Run -- confirm it FAILS** (`ListProfileNames`/`SaveToProfile` missing -> build error).

- [ ] **Step 3: Implement.** In `DRagLint.Lint.ConfigWriter.pas`:
  1. Factor `BuildOwnedObject`: move `ToJson`'s object construction (current lines 94-140, building `Root` with disabled/enabled/severity/thresholds/naming) into `class function BuildOwnedObject(const ACfg): TJSONObject;` returning the un-freed `Root`. `ToJson` becomes: `Root:= BuildOwnedObject(ACfg); try Result:= Root.Format(2); finally Root.Free; end;`.
  2. Factor `WriteAnsiCrlf`: move `SaveToFile`'s normalize+bytes+write tail (current lines 281-288) into `class procedure WriteAnsiCrlf(const APath, AJson: string);`. `SaveToFile` calls it with its merged `Json`.
  3. `ListProfileNames`:
```pascal
class function TLintConfigWriter.ListProfileNames(const APath: string): TArray<string>;
var Root, Profs: TJSONObject; RootVal: TJSONValue; Pair: TJSONPair;
begin
  Result:= nil;
  if not TFile.Exists(APath) then Exit;
  RootVal:= TJSONObject.ParseJSONValue(TFile.ReadAllText(APath));
  if not (RootVal is TJSONObject) then begin RootVal.Free; Exit; end;
  try
    Root:= RootVal as TJSONObject;
    if Root.GetValue('profiles') is TJSONObject then
    begin
      Profs:= Root.GetValue('profiles') as TJSONObject;
      for Pair in Profs do Result:= Result + [Pair.JsonString.Value];
    end;
  finally RootVal.Free; end;
end;
```
  4. `SaveToProfile` -- set one member of the `profiles` object, preserving base + other profiles:
```pascal
class procedure TLintConfigWriter.SaveToProfile(const APath, AName: string; const ACfg: TLintConfig);
var Root, Profs, Owned: TJSONObject; RootVal: TJSONValue;
begin
  { start from existing file, or a fresh object }
  Root:= nil; RootVal:= nil;
  if TFile.Exists(APath) then
  begin
    try RootVal:= TJSONObject.ParseJSONValue(TFile.ReadAllText(APath)); except RootVal:= nil; end;
    if RootVal is TJSONObject then Root:= RootVal as TJSONObject
    else begin RootVal.Free; RootVal:= nil; end;
  end;
  if Root = nil then Root:= TJSONObject.Create;
  try
    { ensure a "profiles" object }
    if not (Root.GetValue('profiles') is TJSONObject) then
    begin
      Root.RemovePair('profiles').Free;   { removes+frees a non-object "profiles" if present; nil-safe on absent }
      Profs:= TJSONObject.Create;
      Root.AddPair('profiles', Profs);
    end
    else
      Profs:= Root.GetValue('profiles') as TJSONObject;
    { set profiles.<AName> := owned config (replace if present) }
    Profs.RemovePair(AName).Free;         { nil-safe; frees the old member if any }
    Owned:= BuildOwnedObject(ACfg);
    Profs.AddPair(AName, Owned);
    WriteAnsiCrlf(APath, Root.Format(2));
  finally
    Root.Free;   { frees the whole tree incl. Profs + Owned }
  end;
end;
```
  NOTE: `TJSONObject.RemovePair` returns the removed pair (or `nil`); `nil.Free` is a safe no-op in Delphi, so `RemovePair(x).Free` is safe when absent. Verify this compiles; if `RemovePair` on an absent key returns `nil` and the chained `.Free` is undesirable, guard with a local. Add `ListProfileNames`/`SaveToProfile`/`BuildOwnedObject`/`WriteAnsiCrlf` to the class declaration (public / private as noted) with DocInsight on the two public ones.

- [ ] **Step 4: Run -- confirm GREEN.** `cmd /c "tests\fixtures\T63_lint_config_roundtrip.bat"` -> all pass / `0 fail`. Normalize + ASCII-verify `ConfigWriter.pas` + `T63*.dpr`.

- [ ] **Step 5: Commit.** `git add src/lint/DRagLint.Lint.ConfigWriter.pas tests/fixtures/T63_lint_config_roundtrip.dpr` + `git commit -m "feat(config): TLintConfigWriter.ListProfileNames + SaveToProfile (merge-preserving)"`.

---

## Task 3: Tab -- profile combo + retargeted Save (compile-smoke)

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas`

**Interfaces:**
- Consumes: Task 1 `TLintConfig.Load(path, profile)`; Task 2 `ListProfileNames`/`SaveToProfile`; existing `ResolveExe`/`GetActiveProjDir`/`RenderCatalog`/`ReloadCatalogAndConfig`/`Save`.
- Produces: no new unit-level API; internal state + a combo control.

- [ ] **Step 1: Add state + the combo, wire load-on-select.**
  1. Private fields: `FProfile: string;` (active profile; `''` = base) and store the active config as a field `FCfg: TLintConfig;` (so search re-render in Task 4 reuses it). Add `FCboProfile: TComboBox;` and a helper `procedure ReloadProfileList;` (fills `FCboProfile.Items` with `(base)` + `TLintConfigWriter.ListProfileNames(CfgPath)`), and `function CfgPath: string;` (`IncludeTrailingPathDelimiter(GetActiveProjDir) + 'drag-lint-lint.json'`, `''` guard).
  2. In `BuildControls` top panel, add a labeled `TComboBox` (`Style := csDropDown` -- EDITABLE) placed next to the counts/Reload/Save controls (mirror the existing control construction in `BuildControls`; use `Vcl.StdCtrls`). `OnSelect := ProfileSelected`.
  3. `procedure ProfileSelected(Sender: TObject);` -- set `FProfile` from the combo text (`'(base)'` -> `''`), then call `ReloadCatalogAndConfig` (which must load config via `FProfile`).
  4. In `ReloadCatalogAndConfig`, change the config load to honor `FProfile`: `FCfg := TLintConfig.Load(CfgPath, FProfile);` (replacing the current `LoadOrDefault`), and after a successful catalog load call `ReloadProfileList` so the combo reflects on-disk profiles. Render using `FCfg`.

- [ ] **Step 2: Retarget the Save button.** In `Save` (currently builds a `TLintConfig` from the controls then `SaveToFile(CfgPath, cfg)`), change ONLY the destination:
```pascal
var Target: string:= Trim(FCboProfile.Text);
if (Target = '') or SameText(Target, '(base)') then
  TLintConfigWriter.SaveToFile(CfgPath, Cfg)          { base config }
else
begin
  TLintConfigWriter.SaveToProfile(CfgPath, Target, Cfg);
  FProfile:= Target;
  ReloadProfileList;                                  { include a newly-created name }
  FCboProfile.ItemIndex:= FCboProfile.Items.IndexOf(Target);
end;
```
  Keep the existing build-config-from-controls logic (`SetRuleDisabled`/`SetRuleEnabled`/`SetThreshold`/`cfg.Naming.*` etc.) unchanged; only the write destination branches.

- [ ] **Step 3: Compile-smoke.** `cd "$(git rev-parse --show-toplevel)" && cmd /c "tests\fixtures\T64_lint_options_compile.bat"` -> `OK` / `PASS`. Normalize + ASCII-verify the frame.

- [ ] **Step 4: Commit.** `git add src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas` + `git commit -m "feat(plugin): Lint Options profile combo (load-on-select) + Save retargets to base/profile"`.

---

## Task 4: Tab -- rule search filter (compile-smoke)

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas`

- [ ] **Step 1: Add the search box + filter.**
  1. Private field `FSearch: string;` and `FEdtSearch: TEdit;`.
  2. In `BuildControls` top panel, add a labeled `TEdit` (`OnChange := SearchChanged`), mirroring the existing control construction.
  3. `procedure SearchChanged(Sender: TObject);` -- `FSearch := Trim(FEdtSearch.Text); if FHasData then RenderCatalog(FCatalogJSON);` (re-render from the CACHED JSON -- no CLI re-call).
  4. In `RenderCatalog`, add a filter predicate applied to BOTH passes (the measure pass and the create pass): a rule is included iff `FSearch = ''` OR `ContainsText(Rule.Id, FSearch)` OR `ContainsText(Rule.Title, FSearch)` (`System.StrUtils.ContainsText` = case-insensitive). Skip non-matching rules; a category whose rules all filter out contributes no group box (the existing two-pass height/stack logic then operates only on the surviving rules -- categories with zero matches are naturally absent because `CatNames`/`CatHeights` are only populated for included rules). Ensure `System.StrUtils` is in the `uses`.

- [ ] **Step 2: Compile-smoke.** `cmd /c "tests\fixtures\T64_lint_options_compile.bat"` -> `OK` / `PASS`. Normalize + ASCII-verify.

- [ ] **Step 3: Commit.** `git add src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas` + `git commit -m "feat(plugin): Lint Options live rule search (filters by id/title)"`.

---

## Task 5: Build the Win32 BPL + docs + human gate

**Files:**
- Modify: `CHANGELOG.md`
- (build artifacts -- NOT committed)

- [ ] **Step 1: Build Win32 to a scratch dir (RAD Studio may stay open) + verify.** Write/reuse a wrapper that runs `msbuild /t:Build /p:Config=Debug /p:Platform=Win32 /p:DCC_BplOutput=<scratch> /p:DCC_DcpOutput=<scratch> src\delphi-plugin\dclDragLintWizard.dproj` via PowerShell `Start-Process -Wait` with output to a log. Expect `Build succeeded`, `0 Error(s)`. Fix any compile errors in the frame/config units and rebuild until clean. Also re-run T63/T64/T65 console tests.

- [ ] **Step 2: CHANGELOG.** Add under the in-progress release: "Added (IDE): Lint Options tab now saves/loads COMPLETE named profiles (enable/disable + thresholds + naming) via an editable profile combo; `drag-lint lint --profile <name>` applies a profile's full settings. Added a live rule search box (filters by id/title)." Commit docs.

- [ ] **Step 3 (USER manual gate -- controller deploys, user click-tests):** With RAD Studio CLOSED, deploy the scratch Win32 BPL/DCP into `third_party\dll-win32` (copy). User reopens RAD Studio and verifies: (a) the profile combo lists `(base)` + any profiles; typing a new name + Save creates `profiles.<name>` in `drag-lint-lint.json` (base + other profiles preserved); selecting a profile loads its settings; (b) `drag-lint lint --profile <name>` reflects a profile's threshold/naming change; (c) typing in Search live-filters the rule list by id/title, clearing restores all. Any failure -> fix-forward.

---

## Self-Review (plan author)

**Spec coverage:** Part A (full-profile override) -> Task 1; Part B (`ListProfileNames`/`SaveToProfile`) -> Task 2; Part C profile combo + retargeted Save -> Task 3, search -> Task 4; build/deploy/gate -> Task 5. CLI `--profile` full-apply is automatic via Task 1's `Load` (no CLI code change) and is asserted by T65 + the human gate. All covered.

**Placeholders:** config-layer tasks (1-2) carry complete code; UI tasks (3-4) give exact fields, handlers, the Save-retarget branch, and the filter predicate, with dynamic-control construction delegated to the existing `BuildControls`/`RenderCatalog` patterns in the same file (deliberate, consistent with the D1b plan -- the implementer has the frame as reference).

**Type/name consistency:** `ApplyConfigObject(obj, replace)` / `ApplyNamingObject(naming)`; `ListProfileNames(path)` / `SaveToProfile(path, name, cfg)` / `BuildOwnedObject(cfg)` / `WriteAnsiCrlf(path, json)`; frame `FProfile`/`FCfg`/`FSearch`/`FCboProfile`/`FEdtSearch`/`CfgPath`/`ReloadProfileList`/`ProfileSelected`/`SearchChanged` -- consistent across tasks.

**Known risks:** (1) `RemovePair(x).Free` on an absent key -- verify Delphi returns `nil` and `nil.Free` is a no-op (Task 2 Step 3 note); if not, guard with a local. (2) `csDropDown` combo `OnSelect` fires on dropdown pick but not on free-typed text -- that's intended (typing sets the Save target; only an explicit dropdown selection loads). (3) search re-render rebuilds up to ~115 rows per keystroke -- acceptable at this scale; if it flickers, the implementer may add a short debounce (not required).
