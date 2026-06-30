# v0.68 -- Naming + Dead-code + referenced-never-set Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 12 near-zero-FP, enabled-by-default rules -- 7 configurable naming rules, 4 dead/redundant-code rules, and the final data-flow rule `referenced-never-set` -- closing MISSING-FEATURES #1, the #2 tail, and #3.

**Architecture:** Naming rules are config-driven built-ins in a new `DRagLint.Diagnostics.NamingChecks` unit, parameterized by a `TNamingConfig` parsed from a new `naming` block in `drag-lint-lint.json` (defaults = this repo's CLAUDE.md conventions). The AST dead-code rules + `referenced-never-set` go in a new `DRagLint.Diagnostics.DeadCodeChecks` unit (`lint <file>` path). The index-backed dead-code rules extend `DRagLint.Lint.ProjectRules` (store path). All findings flow through the v0.66 `FinalizeAndOutput` tail (config severity/disable already apply).

**Tech Stack:** Object Pascal (Delphi 13 / RAD Studio 37.0), tree-sitter-delphi13, `System.JSON`. Win64 (`dcc64`). Tests are the existing `tests/lint` (`.pas` + `.expected`) and `tests/lint-project` (DB) harnesses.

**Spec:** `docs/superpowers/specs/2026-06-30-v068-naming-deadcode-design.md` (read it first).

## Global Constraints

- **Encoding:** every `.pas`/`.dpr` is strict 7-bit ASCII, CRLF, no BOM, zero Unicode. `Edit`/`Write` emit LF -- normalize each touched `.pas`/`.dpr` to CRLF+UTF8-no-BOM before committing (PowerShell: read text, `-replace "`r`n","`n" -replace "`n","`r`n"`, write with `UTF8Encoding($false)`). **Never put a `}` or a nested `{` inside a `{ }` comment** -- it closes the comment early and is a real dcc64 syntax error (hit in v0.67).
- **DocInsight:** `///` XML doc-comments on every new public type/method.
- **TDD:** failing fixture first (RED), implement (GREEN). The harness is the test: `tests/lint/<name>.pas` + `<name>.pas.expected` where `.expected` lines are `<rule-id> <line>` (must fire at line) / `!<rule-id>` (must NOT fire anywhere) / `none` (zero findings). Run `pwsh -File tests\lint\run_lint_tests.ps1 -Filter "<glob>"`.
- **Build recipe (delphi-build skill):** write `scratchpad\build_cli.bat` -- `call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"` / `cd /d c:\Projects\Delphi-RAG-lint\src\cli` / `msbuild /t:Build /p:Config=Debug /p:Platform=Win64 drag-lint.dproj > "%TEMP%\dlbuild.log" 2>&1` / `echo BUILD_EXITCODE=%ERRORLEVEL% >> ...` -- run from PowerShell `Start-Process -FilePath cmd.exe -ArgumentList "/c","<bat>" -Wait`, read the log: pass iff `BUILD_EXITCODE=0` and no `[dcc64 Error]`. Then deploy: copy `src\cli\Win64\Debug\drag-lint.exe` -> `third_party\dll-win64\drag-lint.exe`. Do NOT use the MCP build tool; do NOT `cmd /c build.bat` from the Bash tool.
- **New unit registration:** a new `.pas` compiled into the CLI needs BOTH a `uses ... in '..\diagnostics\Unit.pas',` line in `src/cli/drag-lint.dpr` AND a `<DCCReference Include="..\diagnostics\Unit.pas"/>` in `src/cli/drag-lint.dproj` (mirror the `DRagLint.Diagnostics.AstChecks` entries).
- **Built-in CLI wiring (4 sites, per new `lint <file>` rule id):** (1) the `DoLint` `--rule` allow-list chain (`(AArgs.Rule <> '<id>') and`, near CLI.pas ~4476); (2) the help string's known-rules list (~4486); (3) the `DoLint` dispatch (call the checker, filter `if (AArgs.Rule='') or (AArgs.Rule=F.RuleId)`); (4) the `DoLintAll` dispatch (per-file loop, ~5379 region). The v0.67 `length-zero-compare` commit (`b9d154c`) is the canonical worked example of all four.
- **Confirmed tree-sitter node kinds** (authoritative walkers: `src/parser/DRagLint.Parser.Delphi13.pas` at the cited lines): `declType` (line 886, wraps a type's name + body), `declClass` (451), `declIntf` (485), `declEnum` (517), `declField` (907), `declProc` (898, method header), `defProc` (986, method body), `declArg` (param), `declVar` (788/2665 usage), `declConst` (960/1165), `declSection` (949), `unit` (859), `program` (869/876). Read those walkers for exact `ChildByField` names before coding each rule -- do not assume field names.
- **Finding shape:** `TLintFinding` from `DRagLint.Core.Model` -- `RuleId, FilePath: string; StartLine, StartCol, EndLine, EndCol: Integer; Severity, Message: string`. Emit `Default(TLintFinding)` then set fields; `StartLine := Integer(P.Row)+1; StartCol := Integer(P.Column)+1` from a node's `StartPoint`. The v0.67 length-zero block in `AstChecks.CheckTypeAware` (~line 1620) is the canonical emit template.
- **Severity:** naming/casing rules `info`; `identical-then-else`, `referenced-never-set`, `unused-*` `warning`. All enabled by default (emit unconditionally; the config `disabled` list silences via `FinalizeAndOutput`).
- **Harness gate:** `pwsh -File tests\lint\run_lint_tests.ps1` currently **94/94**; must stay green (add `!<rule>` to any existing fixture that newly fires).
- **FP policy:** when a name's category can't be determined syntactically, do NOT report.

---

## Task 1: `TNamingConfig` + `naming` config block

**Files:**
- Modify: `src/lint/DRagLint.Lint.Config.pas` (add `TNamingConfig`, parse `naming`, expose on `TLintConfig`)
- Modify: `src/cli/DRagLint.CLI.pas` (`LoadLintConfig` already builds `TLintConfig`; no change needed beyond Task 2's checker call)
- Test: `tests/lintconfig/LintConfigTests.dpr` (extend the existing console test)

**Interfaces:**
- Produces: `TNamingConfig` record with fields `ClassPrefix, ExceptionPrefix, InterfacePrefix, PointerPrefix, FieldPrefix, ParamPrefix: string; MethodCase, LocalCase: string; ConstCase: TArray<string>;` and a class default `TNamingConfig.Default: TNamingConfig` (the CLAUDE.md conventions). `TLintConfig` gains a public `Naming: TNamingConfig` field, populated by `Load`.

- [ ] **Step 1: Write the failing config test**

In `tests/lintconfig/LintConfigTests.dpr`, add a `TestNaming` procedure and call it from the main block:

```pascal
procedure TestNaming;
var
  Cfg: TLintConfig;
  Path: string;
begin
  // 1. No config -> defaults match the repo conventions.
  Cfg:= TLintConfig.Load('', '');
  Check('naming default class prefix T', Cfg.Naming.ClassPrefix = 'T');
  Check('naming default field prefix F', Cfg.Naming.FieldPrefix = 'F');
  Check('naming default param prefix p', Cfg.Naming.ParamPrefix = 'p');
  Check('naming default method PascalCase', Cfg.Naming.MethodCase = 'PascalCase');

  // 2. Override: disable param prefix, change field prefix.
  Path:= TPath.Combine(TPath.GetTempPath, 'dl-naming.json');
  TFile.WriteAllText(Path,
    '{ "naming": { "param_prefix": "", "field_prefix": "Fld" } }', TEncoding.UTF8);
  try
    Cfg:= TLintConfig.Load(Path, '');
    Check('naming param prefix disabled (empty)', Cfg.Naming.ParamPrefix = '');
    Check('naming field prefix overridden', Cfg.Naming.FieldPrefix = 'Fld');
    Check('naming class prefix still default', Cfg.Naming.ClassPrefix = 'T');
  finally
    if TFile.Exists(Path) then TFile.Delete(Path);
  end;
end;
```

- [ ] **Step 2: Run the test (RED)**

Run: `pwsh -File tests\lintconfig\run_lintconfig_tests.ps1`
Expected: BUILD FAILED (`TLintConfig` has no `Naming` field / `TNamingConfig` undefined).

- [ ] **Step 3: Add `TNamingConfig` and parse it**

In `src/lint/DRagLint.Lint.Config.pas` interface, add before `TLintConfig`:

```pascal
  /// <summary>Configurable naming conventions read from the drag-lint-lint.json
  /// "naming" block. Empty-string prefixes disable that prefix check; empty
  /// ConstCase disables const casing. Defaults match the project conventions
  /// (TMyClass / EMyException / IMyIntf / PMyType / FMyField / pMyParam, PascalCase).</summary>
  TNamingConfig = record
    ClassPrefix, ExceptionPrefix, InterfacePrefix, PointerPrefix: string;
    FieldPrefix, ParamPrefix: string;
    MethodCase, LocalCase   : string;        // 'PascalCase' | 'UPPER_CASE' | 'camelCase'
    ConstCase               : TArray<string>;
    class function Default: TNamingConfig; static;
  end;
```

Add `Naming: TNamingConfig;` as a public field of `TLintConfig`.

In the implementation, add:

```pascal
class function TNamingConfig.Default: TNamingConfig;
begin
  Result.ClassPrefix    := 'T';
  Result.ExceptionPrefix:= 'E';
  Result.InterfacePrefix:= 'I';
  Result.PointerPrefix  := 'P';
  Result.FieldPrefix    := 'F';
  Result.ParamPrefix    := 'p';
  Result.MethodCase     := 'PascalCase';
  Result.LocalCase      := 'PascalCase';
  Result.ConstCase      := ['PascalCase', 'UPPER_CASE'];
end;
```

In `TLintConfig.Load`, initialise `Result.Naming := TNamingConfig.Default;` right after `Result := Default(TLintConfig);` (so even the no-file path has conventions). Then, inside the block that parses the root object (after the `thresholds` parse, before the profile merge), add:

```pascal
    if Root.GetValue('naming') is TJSONObject then
    begin
      var NJ: TJSONObject:= Root.GetValue('naming') as TJSONObject;
      // string scalars: absent -> keep default; present (incl. "") -> override
      procedure SetStr(const AKey: string; var ATarget: string);
      begin
        if NJ.GetValue(AKey) <> nil then ATarget:= NJ.GetValue(AKey).Value;
      end;
      if NJ.GetValue('type_prefix') is TJSONObject then
      begin
        var TP: TJSONObject:= NJ.GetValue('type_prefix') as TJSONObject;
        if TP.GetValue('class')     <> nil then Result.Naming.ClassPrefix    := TP.GetValue('class').Value;
        if TP.GetValue('exception') <> nil then Result.Naming.ExceptionPrefix:= TP.GetValue('exception').Value;
        if TP.GetValue('interface') <> nil then Result.Naming.InterfacePrefix:= TP.GetValue('interface').Value;
        if TP.GetValue('pointer')   <> nil then Result.Naming.PointerPrefix  := TP.GetValue('pointer').Value;
      end;
      SetStr('field_prefix', Result.Naming.FieldPrefix);
      SetStr('param_prefix', Result.Naming.ParamPrefix);
      SetStr('method_case',  Result.Naming.MethodCase);
      SetStr('local_case',   Result.Naming.LocalCase);
      if NJ.GetValue('const_case') is TJSONArray then
      begin
        Result.Naming.ConstCase:= nil;
        for var V in (NJ.GetValue('const_case') as TJSONArray) do
          Result.Naming.ConstCase:= Result.Naming.ConstCase + [V.Value];
      end;
    end;
```

> Note: `SetStr` is a nested procedure inside `Load`; if the compiler rejects the nested-proc-with-var-param-capture form, inline the four `if NJ.GetValue(...) <> nil then ...` checks instead. The behaviour is: an absent key keeps the default; a present key (including `""`) overrides -- so `"param_prefix": ""` disables that check.

- [ ] **Step 4: Run the test (GREEN)**

Run: `pwsh -File tests\lintconfig\run_lintconfig_tests.ps1`
Expected: all checks pass (report the new count).

- [ ] **Step 5: Normalize + commit**

Normalize `src/lint/DRagLint.Lint.Config.pas` and `tests/lintconfig/LintConfigTests.dpr`. Commit:

```bash
git add src/lint/DRagLint.Lint.Config.pas tests/lintconfig/
git commit -m "feat(config): TNamingConfig + naming block in drag-lint-lint.json (defaults = repo conventions)"
```

---

## Task 2: `NamingChecks` -- prefix rules (`type-name-prefix`, `field-name-prefix`, `param-name-prefix`)

**Files:**
- Create: `src/diagnostics/DRagLint.Diagnostics.NamingChecks.pas`
- Modify: `src/cli/drag-lint.dpr` + `src/cli/drag-lint.dproj` (register the unit)
- Modify: `src/cli/DRagLint.CLI.pas` (4-site wiring for the 3 rule ids; pass `Cfg.Naming` + optional store)
- Test: `tests/lint/type-name-prefix.pas`(+`.expected`), `field-name-prefix.pas`, `param-name-prefix.pas`, and negative fixtures

**Interfaces:**
- Consumes: `TNamingConfig` (Task 1), `ISymbolStore` (optional, for exception ancestry), `TLintFinding`.
- Produces: `class function TNamingChecker.Check(const AFile: string; const ANaming: TNamingConfig; const AStore: ISymbolStore = nil; AFileId: Int64 = 0): TArray<TLintFinding>;` -- emits ids `type-name-prefix`, `field-name-prefix`, `param-name-prefix` (Task 3 extends the same function with the casing/unit ids).

- [ ] **Step 1: Write failing fixtures (RED)**

`tests/lint/type-name-prefix.pas`:
```pascal
unit tnp;
interface
type
  Widget = class            // should fire: class without T prefix
  end;
  TGadget = class           // clean
  end;
  IThing = interface        // clean
  end;
  BadThing = interface      // should fire: interface without I prefix
  end;
implementation
end.
```
`tests/lint/type-name-prefix.pas.expected`:
```
type-name-prefix 4
type-name-prefix 9
```
(Confirm exact lines/cols against the actual parse during GREEN; adjust the `.expected` line numbers to the emitted ones.)

`tests/lint/field-name-prefix.pas`:
```pascal
unit fnp;
interface
type
  TFoo = class
  private
    Count: Integer;         // should fire: field without F prefix
    FName: string;          // clean
  end;
implementation
end.
```
`.expected`: `field-name-prefix 7`

`tests/lint/param-name-prefix.pas`:
```pascal
unit pnp;
interface
procedure Go(Value: Integer; pName: string);  // 'Value' fires; 'pName' clean
implementation
procedure Go(Value: Integer; pName: string);
begin
end;
end.
```
`.expected`: `param-name-prefix 3` (the interface decl; verify whether the impl `declArg` also fires -- if both fire, assert both lines).

- [ ] **Step 2: Run (RED)**

Run: `pwsh -File tests\lint\run_lint_tests.ps1 -Filter "*name-prefix*"`
Expected: FAIL (rules don't exist; fixtures produce no such findings).

- [ ] **Step 3: Create the NamingChecks unit (prefix rules)**

Create `src/diagnostics/DRagLint.Diagnostics.NamingChecks.pas`. Structure: parse the file once (use `DRagLint.Diagnostics.ParseCache.TAstParseCache` like the other checkers -- read how `AstChecks.CheckTypeAware` obtains its tree/`Src`), walk the AST, emit findings. Use the confirmed node kinds. Algorithm per rule:

- **type-name-prefix:** walk `declType` nodes; for each, get the type name identifier and the body node. If body is `declClass` -> require `ClassPrefix` (unless it is an exception class: when `AStore<>nil` and the class ancestry reaches `Exception` via `AStore.IsDescendantOf`, require `ExceptionPrefix` instead; when `AStore=nil`, just require `ClassPrefix`). If body is `declIntf` -> require `InterfacePrefix`. If the type is a pointer type (`^T` / `type P = ^X`) -> require `PointerPrefix`. Skip when the relevant prefix is `''`. "Requires prefix X" = the name must start with X followed by an uppercase letter (so `TFoo` ok, `Tfoo`/`Things` not -- use `StartsWith(Prefix)` AND next char is `A..Z`; a name equal to the prefix alone does not satisfy).
- **field-name-prefix:** walk `declField` inside a `declClass`; require `FieldPrefix`. **Guard:** skip auto-generated published component fields -- a `declField` in the published section of a form/frame class whose type starts `T` (the DFM `Name: TType;` dump). Detect "published": the `declField` under a `declSection` with no explicit visibility keyword at the top of the class (the implicit published section) on a class descending from `TComponent`/form -- conservatively, skip `declField` whose own type identifier names a known VCL control OR when the class is a form (`= class(TForm)` / `TFrame`). If detecting published reliably is hard with no store, the minimal guard is: skip a `declField` whose declared type starts with `T` AND is in the first (implicit) section -- document the heuristic.
- **param-name-prefix:** walk `declArg` nodes; for each parameter name, require `ParamPrefix` (skip `Self`; skip when `ParamPrefix=''`). Emit once per offending param. To avoid double-reporting the interface decl AND the impl, prefer emitting from `declProc` headers only (or de-dup by (line,col)).

Use a shared helper `function HasPrefix(const AName, APrefix: string): Boolean;` (prefix non-empty, `AName` starts with it, and the char after the prefix is `A..Z`). Emit `info` severity. Message examples: `'Type "%s" should start with the "%s" prefix'`, `'Field "%s" should start with the "%s" prefix'`, `'Parameter "%s" should start with the "%s" prefix'`.

> Read `AstChecks.CheckTypeAware` (the `CollectDecls`/walk structure + `NodeStr` + emit) and the parser walkers (`Delphi13.pas` declClass@451 / declField@907 / declProc@898 / declArg) for the exact `ChildByField` names. Do NOT assume field names -- verify against a real parse (`drag-lint check-ast <fixture> --format json` shows positions).

- [ ] **Step 4: Register the unit + wire the 3 rule ids**

Add to `drag-lint.dpr` (after the `DRagLint.Diagnostics.AstChecks` line): `DRagLint.Diagnostics.NamingChecks in '..\diagnostics\DRagLint.Diagnostics.NamingChecks.pas',`. Add the matching `<DCCReference>` to `drag-lint.dproj`.

In `CLI.pas`: add `DRagLint.Diagnostics.NamingChecks` to the implementation `uses`. Wire the 3 ids at the 4 sites (allow-list, help, DoLint dispatch, DoLintAll dispatch). In `DoLint`, after the `CheckTypeAware` block, add (note `Cfg` is the `TLintConfig` already loaded for thresholds via `LoadLintConfig`):

```pascal
      if (AArgs.Rule = '') or (AArgs.Rule = 'type-name-prefix') or (AArgs.Rule = 'field-name-prefix') or (AArgs.Rule = 'param-name-prefix') then
        for F in DRagLint.Diagnostics.NamingChecks.TNamingChecker.Check(AArgs.Path, Cfg.Naming) do
          if (AArgs.Rule = '') or (AArgs.Rule = F.RuleId) then Findings:= Findings + [F];
```

In `DoLintAll` (the per-file loop), add the same with the store: `TNamingChecker.Check(PasPath, Cfg.Naming, Store, Store.FindFileIdByPath(PasPath))`. Add the 3 ids to the allow-list chain and the help string.

- [ ] **Step 5: Build + deploy + run fixtures (GREEN)**

Invoke delphi-build, deploy exe. Run `pwsh -File tests\lint\run_lint_tests.ps1 -Filter "*name-prefix*"`. Adjust each `.expected` to the actually-emitted line numbers (verify the emit lands on the type/field/param name node). Then run the FULL harness `pwsh -File tests\lint\run_lint_tests.ps1` -- must stay green; if any existing fixture newly fires a naming rule, add `!<id>` to its `.expected` (or fix the fixture's names).

- [ ] **Step 6: Normalize + commit**

Normalize all touched `.pas`/`.dpr`. Commit:
```bash
git add src/diagnostics/DRagLint.Diagnostics.NamingChecks.pas src/cli/drag-lint.dpr src/cli/drag-lint.dproj src/cli/DRagLint.CLI.pas tests/lint/*name-prefix*
git commit -m "feat(naming): type/field/param name-prefix rules (config-driven built-ins)"
```

---

## Task 3: `NamingChecks` -- casing + unit-name rules

**Files:**
- Modify: `src/diagnostics/DRagLint.Diagnostics.NamingChecks.pas` (extend `Check` with 4 more ids)
- Modify: `src/cli/DRagLint.CLI.pas` (wire `method-pascalcase`, `const-casing`, `local-var-casing`, `unit-name-matches-file`)
- Test: `tests/lint/method-pascalcase.pas`, `const-casing.pas`, `local-var-casing.pas`, `unit-name-matches-file.pas` (+ `.expected`)

**Interfaces:**
- Extends `TNamingChecker.Check` to also emit `method-pascalcase`, `const-casing`, `local-var-casing`, `unit-name-matches-file`.

- [ ] **Step 1: Write failing fixtures (RED)** -- one per rule. Examples:

`unit-name-matches-file.pas` (the unit name deliberately differs from the file base name):
```pascal
unit WrongName;
interface
implementation
end.
```
`.expected`: `unit-name-matches-file 1`

`method-pascalcase.pas`:
```pascal
unit mpc;
interface
procedure doThing;   // camelCase -> fires
procedure DoOther;   // clean
implementation
procedure doThing; begin end;
procedure DoOther; begin end;
end.
```
`.expected`: `method-pascalcase 3`

`local-var-casing.pas`:
```pascal
unit lvc;
interface
implementation
procedure P;
var
  FCount: Integer;     // local carrying the field prefix -> smell, fires
  ok: Integer;         // lowercase start -> fires (not PascalCase)
  Good: Integer;       // clean
begin
  FCount:= 0; ok:= 0; Good:= 0;
end;
end.
```
`.expected`: assert the two firing lines (verify during GREEN).

`const-casing.pas`: a const that is neither PascalCase nor UPPER_CASE (e.g. `mixed_thing = 1;`) fires; `MaxRows = 1` and `MAX_ROWS = 1` are clean.

- [ ] **Step 2: Run (RED)** -- `pwsh -File tests\lint\run_lint_tests.ps1 -Filter "*casing*"` and `... -Filter "method-pascalcase*"` and `... -Filter "unit-name*"`. Expected FAIL.

- [ ] **Step 3: Implement the casing helpers + 4 rules**

Add to `NamingChecks`:
- `function IsPascalCase(const S: string): Boolean;` -- first char `A..Z`, no underscores, not all-caps-with-underscores.
- `function IsUpperSnake(const S: string): Boolean;` -- only `A..Z`, `0..9`, `_`, at least one letter.
- `function MatchesCase(const S, ACase: string): Boolean;` -- dispatch on `'PascalCase'|'UPPER_CASE'|'camelCase'`.
- `function MatchesAnyCase(const S: string; const ACases: TArray<string>): Boolean;`

Rules:
- **method-pascalcase:** walk `declProc` (skip operator overloads if any); require `MatchesCase(name, ANaming.MethodCase)`. Skip when `MethodCase=''`.
- **const-casing:** walk `declConst`; require `MatchesAnyCase(name, ANaming.ConstCase)`. Skip when `ConstCase` empty.
- **local-var-casing:** walk `declVar` that are inside a `defProc` body (locals, not unit-level or fields); require `MatchesCase(name, ANaming.LocalCase)` AND name must NOT start with `FieldPrefix`/`ParamPrefix` (when those are non-empty). Skip when `LocalCase=''`.
- **unit-name-matches-file:** read the `unit` node's name identifier; compare case-insensitively to `ChangeFileExt(ExtractFileName(AFile), '')`. If different, emit one finding at the unit name. (Skip `program`/`library`.)

- [ ] **Step 4: Wire the 4 ids** at the 4 CLI sites (extend the Task 2 `if (AArgs.Rule='') or ...` condition to include the new ids; they come from the same `TNamingChecker.Check` call, so only the allow-list + help + the dispatch `or`-condition need the new ids).

- [ ] **Step 5: Build + deploy + GREEN** -- fixtures pass (tune `.expected` lines); full harness stays green.

- [ ] **Step 6: Normalize + commit**
```bash
git commit -am "feat(naming): method/const/local casing + unit-name-matches-file rules"
```

---

## Task 4: `DeadCodeChecks` -- `unused-parameter` + `identical-then-else`

**Files:**
- Create: `src/diagnostics/DRagLint.Diagnostics.DeadCodeChecks.pas`
- Modify: `src/cli/drag-lint.dpr` + `.dproj` (register)
- Modify: `src/cli/DRagLint.CLI.pas` (wire 2 ids; Task 5 adds the 3rd)
- Test: `tests/lint/unused-parameter.pas` (+ guard fixtures), `identical-then-else.pas` (+ `.expected`)

**Interfaces:**
- Produces: `class function TDeadCodeChecker.Check(const AFile: string): TArray<TLintFinding>;` -- emits `unused-parameter`, `identical-then-else` (Task 5 adds `referenced-never-set`).

- [ ] **Step 1: Failing fixtures (RED)**

`unused-parameter.pas` (positive + guards):
```pascal
unit up;
interface
type
  TBase = class
    procedure Go(Used, Unused: Integer); virtual;
  end;
  TDer = class(TBase)
    procedure Go(Used, Unused: Integer); override;   // override: Unused must NOT fire
  end;
procedure Plain(A, B: Integer);                      // B never read -> fires
implementation
procedure Plain(A, B: Integer); begin WriteLn(A); end;
procedure TBase.Go(Used, Unused: Integer); begin WriteLn(Used); end;  // base virtual: Unused fires? decide: virtual non-override still fires
procedure TDer.Go(Used, Unused: Integer); begin WriteLn(Used); end;   // override: must NOT fire
end.
```
`.expected`: assert `unused-parameter` fires for `Plain.B` and does NOT fire for `TDer.Go.Unused`. (Use `unused-parameter <line>` for the positive and rely on the guard for the negative; add a separate `unused-parameter-override.pas` with ONLY an override method and `.expected` = `!unused-parameter` for a clean negative gate.)

`identical-then-else.pas`:
```pascal
unit ite;
interface
implementation
procedure P(C: Boolean; var X: Integer);
begin
  if C then X:= 1 else X:= 1;   // identical branches -> fires
  if C then X:= 1 else X:= 2;   // clean
end;
end.
```
`.expected`: `identical-then-else 6`

- [ ] **Step 2: Run (RED)** -- `pwsh -File tests\lint\run_lint_tests.ps1 -Filter "unused-parameter*"` and `... -Filter "identical-then-else*"`. Expected FAIL.

- [ ] **Step 3: Implement**

- **unused-parameter:** for each `defProc` (impl body): collect its `declArg` parameter names; collect every identifier read in the body; flag a parameter name never read. **Guards:** skip if the method header has `override`/`virtual` is NOT enough -- specifically skip `override` methods, interface-method implementations, and methods with the `message` directive or `external`/`assembler` bodies (these must keep the signature). Detect `override`: the `declProc`/`defProc` header's `procAttribute` child includes `kOverride` (see how `AstChecks.CheckVirtualInConstructor` reads `kVirtual/kDynamic/kOverride`). Skip `var`/`out` params (caller-visible side effects). Skip `Self`. `warning` severity.
- **identical-then-else:** find `ifElse` nodes (the if-with-else form -- see the v0.62 grammar note: if-with-else is a separate `ifElse` node with `then:`/`else:` fields). Compare the normalized source text of the `then` branch and the `else` branch (trim + collapse whitespace via `NodeStr`); if identical, emit at the `if` node. `warning`.

- [ ] **Step 4: Register unit + wire 2 ids** (4 sites each). DoLint dispatch:
```pascal
      if (AArgs.Rule = '') or (AArgs.Rule = 'unused-parameter') or (AArgs.Rule = 'identical-then-else') then
        for F in DRagLint.Diagnostics.DeadCodeChecks.TDeadCodeChecker.Check(AArgs.Path) do
          if (AArgs.Rule = '') or (AArgs.Rule = F.RuleId) then Findings:= Findings + [F];
```
Mirror in DoLintAll; add ids to allow-list + help.

- [ ] **Step 5: Build + deploy + GREEN** -- fixtures pass (incl. the override negative gate); full harness green.

- [ ] **Step 6: Normalize + commit**
```bash
git add src/diagnostics/DRagLint.Diagnostics.DeadCodeChecks.pas src/cli/drag-lint.dpr src/cli/drag-lint.dproj src/cli/DRagLint.CLI.pas tests/lint/unused-parameter* tests/lint/identical-then-else*
git commit -m "feat(deadcode): unused-parameter (override/interface/message-guarded) + identical-then-else"
```

---

## Task 5: `DeadCodeChecks` -- `referenced-never-set` (single-unit field def-use)

**Files:**
- Modify: `src/diagnostics/DRagLint.Diagnostics.DeadCodeChecks.pas` (add `referenced-never-set` to `Check`)
- Modify: `src/cli/DRagLint.CLI.pas` (wire the id)
- Test: `tests/lint/referenced-never-set.pas` (+ negative/guard fixtures)

**Interfaces:** extends `TDeadCodeChecker.Check` to also emit `referenced-never-set`.

- [ ] **Step 1: Failing fixtures (RED)**

`referenced-never-set.pas`:
```pascal
unit rns;
interface
type
  TThing = class
  strict private
    FNeverSet: Integer;     // read in DoIt, never assigned anywhere -> fires
    FOk: Integer;           // written in Init, read in DoIt -> clean
    procedure Init;
    function DoIt: Integer;
  end;
implementation
procedure TThing.Init;
begin
  FOk:= 5;
end;
function TThing.DoIt: Integer;
begin
  Result:= FNeverSet + FOk;
end;
end.
```
`.expected`: `referenced-never-set` at the `FNeverSet` declaration line (verify line during GREEN).

`referenced-never-set-published.pas` (guard: a form's published field read-but-not-written must NOT fire):
```pascal
unit rnsp;
interface
uses Vcl.Forms, Vcl.StdCtrls;
type
  TForm1 = class(TForm)
    Label1: TLabel;         // published, DFM-streamed -> must NOT fire even if only read
    procedure Use;
  end;
implementation
procedure TForm1.Use;
begin
  Label1.Caption:= 'x';     // reads Label1, never assigns it
end;
end.
```
`.expected`: `!referenced-never-set`

- [ ] **Step 2: Run (RED)** -- `pwsh -File tests\lint\run_lint_tests.ps1 -Filter "referenced-never-set*"`. Expected FAIL (positive doesn't fire).

- [ ] **Step 3: Implement (single-unit whole-class field def-use)**

In `TDeadCodeChecker.Check`: build, per class declared in the unit, the set of its field names (from `declField` under the class, recording each field's declaration line + visibility). Then walk ALL method bodies (`defProc`) whose owning class is that class, and classify each reference to a field name as **write** (it is the base of an assignment target -- reuse the assignment-target detection: an identifier that is the `lhs` of an assignment, or `FField.Sub := ...` where `FField` is the base, or passed as a `var`/`out` argument) or **read** (any other mention). A field with `>=1 read` and `0 writes` -> emit `referenced-never-set` at its declaration, `warning`.

**Guards:** only `private`/`strict private` fields (skip `protected`/`public`); **skip** if the class descends from a form/frame/`TComponent` OR the field is in the implicit published section (DFM-streamed) -- mirror the field-name-prefix published guard from Task 2; skip a field with an initializer. When in doubt, do not flag.

> Reuse the M2 assignment-base logic: see `DRagLint.Analysis.*` / the `AssignmentBaseIndex` notes (the engine already classifies "is this identifier an assignment target, including `Result.f := ` / `a[i] := ` partial defines"). For a self-contained single-unit pass you only need: is the field identifier the base of an assignment LHS, or a `var`/`out` actual arg. Implement that directly with the `assignment` node's `lhs` field + the `:=` form; you do not need the full CFG.

- [ ] **Step 4: Wire the id** (add `referenced-never-set` to the Task 4 dispatch `or`-condition, the allow-list, and the help).

- [ ] **Step 5: Build + deploy + GREEN** -- positive fires at `FNeverSet`, published guard `!referenced-never-set` holds; full harness green.

- [ ] **Step 6: Normalize + commit**
```bash
git commit -am "feat(dataflow): referenced-never-set -- whole-class field read-but-never-written (single-unit, private-only, form-guarded)"
```

---

## Task 6: store-backed dead-code -- `unused-private-member` + `unused-unit-in-uses`

**Files:**
- Modify: `src/lint/DRagLint.Lint.ProjectRules.pas` (add two store-backed checks to `TProjectLintRules`)
- Modify: `src/cli/DRagLint.CLI.pas` (`DoLintAll`/project path -- these run with a store, like `unused-public-symbol`)
- Test: `tests/lint-project/unused-private/` (DB fixture: index a small project, then `lint-all --db` / `check-ast --db`), mirroring `tests/lint-project/objleak-interproc/run_objleak_interproc.ps1`

**Interfaces:**
- Consumes: `ISymbolStore`. Produces: two new methods on `TProjectLintRules` (e.g. `CheckUnusedPrivateMembers(AStore): TArray<TLintFinding>`, `CheckUnusedUnitsInUses(AStore): TArray<TLintFinding>`), emitted ids `unused-private-member`, `unused-unit-in-uses` (`warning`).

- [ ] **Step 1: Failing DB fixture (RED)**

Create `tests/lint-project/unused-private/` with a tiny 2-unit project: one unit declares a `private` method/field that nothing references, and a `uses` clause naming a unit whose symbols are never used. Write `run_unused_private.ps1` mirroring `tests/lint-project/objleak-interproc/run_objleak_interproc.ps1`: build/locate the exe, `drag-lint index <dir> --db <tmp.sqlite>`, then `drag-lint lint-all --db <tmp.sqlite>` (or `check-ast <unit> --db`), assert the two ids appear for the unused symbols and do NOT appear for used ones. Run it -> RED.

- [ ] **Step 2: Implement (read `unused-public-symbol` first as the template)**

Read `TProjectLintRules.Run` and its `unused-public-symbol` implementation in `src/lint/DRagLint.Lint.ProjectRules.pas` -- it already enumerates symbols and queries the store for references. 
- **unused-private-member:** same query, filtered to `private`/`strict private` visibility symbols (methods/fields/consts/nested types) with zero references. Guards: skip published; skip RTTI-streamed; skip if any ref. 
- **unused-unit-in-uses:** for each unit, for each unit named in its `uses`, check whether any symbol exported by that used-unit is referenced by the using unit (the store has the resolved uses-graph + refs). Flag a used-unit with zero referenced symbols. Guards: skip a small allow-list of known side-effect/operator/helper units; conservative when the unit can't be resolved.
Wire both into `TProjectLintRules.Run` so they run on the existing store path (no new CLI dispatch site if `Run` is already called in `DoLintAll`; otherwise add the call next to `unused-public-symbol`).

- [ ] **Step 3: Build + deploy + GREEN** -- `pwsh -File tests\lint-project\unused-private\run_unused_private.ps1` passes; the standalone `lint <file>` harness (no store) is unaffected (94+ green).

- [ ] **Step 4: Normalize + commit**
```bash
git add src/lint/DRagLint.Lint.ProjectRules.pas src/cli/DRagLint.CLI.pas tests/lint-project/unused-private/
git commit -m "feat(deadcode): unused-private-member + unused-unit-in-uses (store-backed project rules)"
```

---

## Task 7: docs, CHANGELOG, MISSING-FEATURES, real-code sanity

**Files:** `CHANGELOG.md`, `docs/lint/MISSING-FEATURES.md`, `rules/README.md`, `src/cli/DRagLint.CLI.pas` (VERSION)

- [ ] **Step 1:** Bump `VERSION` in `src/cli/DRagLint.CLI.pas` to `'0.68.0-alpha'`.
- [ ] **Step 2:** Add a `## v0.68.0-alpha` CHANGELOG section (top): the 7 naming rules + the `naming` config block, the 4 dead-code rules, `referenced-never-set`; note all enabled-by-default, naming `info` / dead-code+dataflow `warning`, the per-check disable via empty config values + the `disabled` list.
- [ ] **Step 3:** Update `docs/lint/MISSING-FEATURES.md`: mark section #1 items shipped (`[x]`), the four #2 items shipped, and `referenced-never-set` in #3 `[x]`; bump the coverage % and refresh "highest-leverage next" (the remaining #2 deferred items + cast rules #4 + autofix #12).
- [ ] **Step 4:** Add a `## Naming conventions (v0.68)` section to `rules/README.md` documenting the `naming` block schema + defaults + how to disable a single check.
- [ ] **Step 5: Real-code sanity** -- run the deployed exe `lint` on `C:\Projects\DB\ORM3\CLIENT\AssignTools2.ViewModel.pas` (and one form unit) and spot-check the new naming/dead-code findings are accurate (near-zero-FP). Capture a few in the commit message. If a rule is noisy on real code, tighten its guard before shipping.
- [ ] **Step 6: Commit + publish v0.68.0-alpha** -- normalize, commit docs; then (if on a branch) merge to `main`, `pwsh -File build\pack-lint-release.ps1 -Version 0.68.0-alpha`, `git tag v0.68.0-alpha`, push main + tag, `gh release create v0.68.0-alpha --repo Alexl-git/Delphi-RAG-Lint --prerelease --notes-file <changelog-section> <win64-zip> <win32-zip>`.

---

## Self-Review

**Spec coverage:** Task 1 = config (#spec 3); Tasks 2-3 = the 7 naming rules (#spec 4); Tasks 4-5 = the 4 AST dead-code + referenced-never-set (#spec 5/6, the `lint <file>` ones); Task 6 = the 2 store-backed dead-code rules (#spec 5); Task 7 = severity/docs/DoD (#spec 7/9/11). The deferred non-goals (#spec 8) are correctly absent. The exception-ancestry store-optional path (#spec 4 rule 1 / #spec 2) is in Task 2 Step 3 + the `Check(... AStore ...)` signature.

**Placeholder scan:** fixture `.expected` line numbers are marked "verify/tune during GREEN" deliberately (tree-sitter emit positions must be confirmed against a real parse, per the project's standing lesson) -- this is an instruction, not a placeholder. Algorithms are specified with node kinds + the template to copy; no "implement later".

**Type consistency:** `TNamingChecker.Check(AFile, ANaming, AStore=nil, AFileId=0)` and `TDeadCodeChecker.Check(AFile)` are used identically at every dispatch site; `TNamingConfig` field names (`ClassPrefix`/`FieldPrefix`/`ParamPrefix`/`MethodCase`/`LocalCase`/`ConstCase`) match between Task 1 (definition) and Tasks 2-3 (consumption). Rule ids are spelled identically in fixtures, dispatch, allow-list, and help.

**Note on emit-position verification:** every fixture task says to tune `.expected` line numbers to the actually-emitted positions during GREEN and to re-run the FULL harness, adding `!<id>` guards where an existing fixture newly fires -- this is the safety net for the naming rules running on all 94 existing fixtures.
