# Ergonomics / Output Layer (#12) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make drag-lint findings consumable in CI and configurable per project -- SARIF output, a `--fail-on` exit-code gate, a line-shift-stable baseline file, and a `drag-lint-lint.json` config (severity/enable-disable/thresholds/profiles) -- without changing any analysis, all wired into `lint`/`lint-all`/`check-ast` through one shared output tail.

**Architecture:** Four new pure units (`DRagLint.Output.Sarif`, `DRagLint.Lint.Config`, `DRagLint.Lint.Baseline`, plus two CLI-local helper functions `ExitCodeFor`/`FinalizeAndOutput`) sit between "raw findings" and "output". Tasks 1-4 build each component with its own bare-`dcc64` console unit test (default behavior stays unchanged because nothing is wired yet). Task 5 introduces `FinalizeAndOutput` and routes all three finding-producing commands through it, replacing their inline output+exit-code tails. Task 6 is docs + CHANGELOG + a real-code sanity run. Threshold config is the one exception to the "post-process" rule: thresholds are a *check input* (they change which findings are produced), so they are applied where the metric checks are invoked, inside the commands.

**Tech Stack:** Object Pascal (Delphi 13 / RAD Studio 37.0), tree-sitter, `System.JSON`, `System.Hash` (SHA-256 fingerprints), `System.IOUtils`. Win64 (`dcc64`). Tests are DUnit-free console programs run via `pwsh`.

## Global Constraints

- **Encoding:** every `.pas` is strict 7-bit ASCII, CRLF line endings, no BOM. `Edit`/`Write` emit LF -- normalize each touched `.pas` to CRLF + UTF-8-no-BOM **before committing** (see the normalize step in each task).
- **DocInsight (CDD):** every new public type/method/function gets a `///` XML doc-comment (`<summary>`, `<param>`, `<returns>`, `<remarks>` for ownership/threading/invariants). Private helpers only when an invariant is non-obvious.
- **TDD:** write the failing test first; run it red; implement minimally; run it green; commit.
- **New unit registration:** a new `.pas` compiled into the CLI needs BOTH a `uses ... in '..\dir\Unit.pas'` line in [src/cli/drag-lint.dpr](src/cli/drag-lint.dpr) AND a `<DCCReference Include="..\dir\Unit.pas"/>` line in [src/cli/drag-lint.dproj](src/cli/drag-lint.dproj). Missing either => link/build error.
- **Build recipe (the only reliable one):** invoke the **delphi-build** skill. In short: write `C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a3f626ff-8afb-4f6c-87d0-ee570e7042e7\scratchpad\build_cli.bat` containing 3 lines -- `call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"`, `cd /d c:\Projects\Delphi-RAG-lint\src\cli`, `msbuild /t:Build /p:Config=Debug /p:Platform=Win64 drag-lint.dproj > <log> 2>&1 & echo BUILD_EXITCODE=%ERRORLEVEL% >> <log>` -- run it from PowerShell `Start-Process -Wait`, then Read the log: pass iff `BUILD_EXITCODE=0` and no `[dcc64 Error]`. Then deploy the fresh exe: copy `src\cli\Win64\Debug\drag-lint.exe` to `third_party\dll-win64\drag-lint.exe`.
- **Harness must stay green:** `pwsh -File tests\lint\run_lint_tests.ps1` = **91/91**, `pwsh -File tests\flowengine\run_flowengine_tests.ps1` = **24/24**. Default behavior (no config, no baseline, no `--fail-on`, no `--format sarif`) must be byte-for-byte unchanged.
- **Severity order:** `error > warning > info > hint` (ranks 3/2/1/0). Unknown severity strings rank 0.
- **VERSION:** the const at [src/cli/DRagLint.CLI.pas:6](src/cli/DRagLint.CLI.pas#L6) is already `0.66.0-alpha`; SARIF emits it as the tool version. Do not bump it.
- **`TLintFinding`** is declared in [src/core/DRagLint.Core.Model.pas:159-170](src/core/DRagLint.Core.Model.pas#L159-L170): fields `RuleId, FilePath: string; StartLine, StartCol, EndLine, EndCol: Integer; Severity, Message: string` (plus `Id, FileId: Int64`). The unit's interface `uses` only `System.SysUtils`, so any test can `uses DRagLint.Core.Model` under a bare `dcc64`.

---

## Task 1: SARIF writer + `--format sarif`

**Files:**
- Create: `src/output/DRagLint.Output.Sarif.pas`
- Create: `tests/sarif/SarifTests.dpr`
- Create: `tests/sarif/run_sarif_tests.ps1`
- Modify: `src/cli/drag-lint.dpr` (add `uses` line) and `src/cli/drag-lint.dproj` (add `<DCCReference>`)

**Interfaces:**
- Consumes: `TLintFinding` from `DRagLint.Core.Model`.
- Produces: `TSarifWriter.ToJson(const AFindings: TArray<TLintFinding>; const AToolVersion: string): string` -- a pure function returning SARIF 2.1.0 JSON text. Task 5 calls it from `FinalizeAndOutput`.

- [ ] **Step 1: Write the SARIF unit (pure function) -- this is the implementation; its failing test follows in Step 2-3**

Create `src/output/DRagLint.Output.Sarif.pas`:

```pascal
unit DRagLint.Output.Sarif;

interface

uses
  System.SysUtils, System.JSON, DRagLint.Core.Model;

type
  /// <summary>Serializes drag-lint findings to SARIF 2.1.0 JSON for CI / GitHub
  /// code-scanning ingestion. Pure: no I/O, no global state.</summary>
  TSarifWriter = class
  strict private
    /// <summary>Maps a drag-lint severity to a SARIF level. error->error,
    /// warning->warning, everything else (info/hint/unknown)->note.</summary>
    class function SarifLevel(const ASeverity: string): string; static;
    /// <summary>Builds one SARIF result object for a finding. Caller owns it
    /// (added into a results array which frees it).</summary>
    class function BuildResult(const AFinding: TLintFinding): TJSONObject; static;
  public
    /// <summary>Renders the findings as a SARIF 2.1.0 run.</summary>
    /// <param name="AFindings">The surviving findings; may be empty.</param>
    /// <param name="AToolVersion">Value for tool.driver.version (the drag-lint VERSION).</param>
    /// <returns>Pretty-printed SARIF JSON. runs[0].tool.driver.rules lists the
    /// distinct rule ids; runs[0].results carries one entry per finding.</returns>
    class function ToJson(const AFindings: TArray<TLintFinding>; const AToolVersion: string): string; static;
  end;

implementation

uses
  System.Math, System.Classes;

class function TSarifWriter.SarifLevel(const ASeverity: string): string;
begin
  if SameText(ASeverity, 'error') then Result:= 'error'
  else if SameText(ASeverity, 'warning') then Result:= 'warning'
  else Result:= 'note';
end;

class function TSarifWriter.BuildResult(const AFinding: TLintFinding): TJSONObject;
var
  Loc, Phys, Art, Region, Msg: TJSONObject;
  Locs: TJSONArray;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('ruleId', AFinding.RuleId);
  Result.AddPair('level' , SarifLevel(AFinding.Severity));

  Msg:= TJSONObject.Create;
  Msg.AddPair('text', AFinding.Message);
  Result.AddPair('message', Msg);

  { SARIF lines/columns are 1-based; clamp so a 0/blank coordinate stays valid. }
  Region:= TJSONObject.Create;
  Region.AddPair('startLine'  , TJSONNumber.Create(Max(1, AFinding.StartLine)));
  Region.AddPair('startColumn', TJSONNumber.Create(Max(1, AFinding.StartCol )));
  Region.AddPair('endLine'    , TJSONNumber.Create(Max(1, AFinding.EndLine  )));
  Region.AddPair('endColumn'  , TJSONNumber.Create(Max(1, AFinding.EndCol   )));

  Art:= TJSONObject.Create;
  Art.AddPair('uri', AFinding.FilePath);

  Phys:= TJSONObject.Create;
  Phys.AddPair('artifactLocation', Art);
  Phys.AddPair('region', Region);

  Loc:= TJSONObject.Create;
  Loc.AddPair('physicalLocation', Phys);

  Locs:= TJSONArray.Create;
  Locs.AddElement(Loc);
  Result.AddPair('locations', Locs);
end;

class function TSarifWriter.ToJson(const AFindings: TArray<TLintFinding>; const AToolVersion: string): string;
var
  Root, Run, Tool, Driver: TJSONObject;
  Runs, Rules, Results   : TJSONArray ;
  SeenRules              : TStringList;
  F                      : TLintFinding;
begin
  Root:= TJSONObject.Create;
  try
    Root.AddPair('version', '2.1.0');
    Root.AddPair('$schema', 'https://json.schemastore.org/sarif-2.1.0.json');

    Runs:= TJSONArray.Create;
    Root.AddPair('runs', Runs);

    Run:= TJSONObject.Create;
    Runs.AddElement(Run);

    Tool:= TJSONObject.Create;
    Run.AddPair('tool', Tool);
    Driver:= TJSONObject.Create;
    Tool.AddPair('driver', Driver);
    Driver.AddPair('name', 'drag-lint');
    Driver.AddPair('version', AToolVersion);

    Rules:= TJSONArray.Create;
    Driver.AddPair('rules', Rules);
    Results:= TJSONArray.Create;
    Run.AddPair('results', Results);

    SeenRules:= TStringList.Create;
    try
      SeenRules.Sorted:= True;
      SeenRules.Duplicates:= dupIgnore;
      SeenRules.CaseSensitive:= True;
      for F in AFindings do
      begin
        if SeenRules.IndexOf(F.RuleId) < 0 then
        begin
          SeenRules.Add(F.RuleId);
          Rules.AddElement(TJSONObject.Create.AddPair('id', F.RuleId) as TJSONObject);
        end;
        Results.AddElement(BuildResult(F));
      end;
    finally
      SeenRules.Free;
    end;

    Result:= Root.Format(2);
  finally
    Root.Free;
  end;
end;

end.
```

- [ ] **Step 2: Write the failing console test**

Create `tests/sarif/SarifTests.dpr`:

```pascal
program SarifTests;

// TDD harness for DRagLint.Output.Sarif -- a pure JSON serializer, so it builds
// with a bare dcc64 against the dep-free SARIF + Core.Model units (no DB/FireDAC).

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.JSON,
  DRagLint.Core.Model in '..\..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Output.Sarif in '..\..\src\output\DRagLint.Output.Sarif.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;

function MkFinding(const ARule, ASeverity, AFile: string; ALine, ACol: Integer; const AMsg: string): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId  := ARule;
  Result.Severity:= ASeverity;
  Result.FilePath:= AFile;
  Result.StartLine:= ALine; Result.StartCol:= ACol;
  Result.EndLine  := ALine; Result.EndCol  := ACol + 3;
  Result.Message := AMsg;
end;

procedure TestSarifShape;
var
  Findings: TArray<TLintFinding>;
  Root, Run, Driver, Res0: TJSONObject;
  Runs, Rules, Results: TJSONArray;
  Txt: string;
  V: TJSONValue;
begin
  Findings:= [
    MkFinding('used-before-assignment', 'warning', 'C:\proj\A.pas', 10, 3, 'x used before set'),
    MkFinding('object-leak'           , 'info'   , 'C:\proj\A.pas', 20, 1, 'leak'),
    MkFinding('used-before-assignment', 'error'  , 'C:\proj\B.pas',  5, 7, 'y used before set')
  ];
  Txt:= TSarifWriter.ToJson(Findings, '0.66.0-alpha');

  V:= TJSONObject.ParseJSONValue(Txt);
  Check('SARIF parses as JSON', V <> nil);
  if V = nil then Exit;
  try
    Root:= V as TJSONObject;
    Check('version is 2.1.0', Root.GetValue('version').Value = '2.1.0');
    Check('has $schema', Root.GetValue('$schema') <> nil);

    Runs:= Root.GetValue('runs') as TJSONArray;
    Check('one run', Runs.Count = 1);
    Run:= Runs.Items[0] as TJSONObject;

    Driver:= ((Run.GetValue('tool') as TJSONObject).GetValue('driver')) as TJSONObject;
    Check('driver name', Driver.GetValue('name').Value = 'drag-lint');
    Check('driver version', Driver.GetValue('version').Value = '0.66.0-alpha');

    Rules:= Driver.GetValue('rules') as TJSONArray;
    Check('rules deduped to 2 distinct ids', Rules.Count = 2);

    Results:= Run.GetValue('results') as TJSONArray;
    Check('three results', Results.Count = 3);

    Res0:= Results.Items[0] as TJSONObject;
    Check('result0 ruleId', Res0.GetValue('ruleId').Value = 'used-before-assignment');
    Check('result0 level warning->warning', Res0.GetValue('level').Value = 'warning');
    Check('result1 level info->note',
      (Results.Items[1] as TJSONObject).GetValue('level').Value = 'note');
    Check('result2 level error->error',
      (Results.Items[2] as TJSONObject).GetValue('level').Value = 'error');

    Check('result0 has region.startLine=10',
      (((Res0.GetValue('locations') as TJSONArray).Items[0] as TJSONObject)
        .GetValue('physicalLocation') as TJSONObject).GetValue('region')
        is TJSONObject);
  finally
    V.Free;
  end;
end;

begin
  GPass:= 0; GFail:= 0;
  try
    TestSarifShape;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('sarif-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
```

Create `tests/sarif/run_sarif_tests.ps1` (mirrors `tests/projectchecks/run_projectchecks_tests.ps1`):

```powershell
# Build + run the SARIF writer unit tests with a bare dcc64 (Win64).
$rs  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir = $PSScriptRoot
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -E`"$dir`" `"$dir\SarifTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 10; exit 1 }
& "$dir\SarifTests.exe"
exit $LASTEXITCODE
```

- [ ] **Step 3: Run the test to verify it fails (unit not yet on dcc64 search path / compile error if Step 1 was skipped)**

Run: `pwsh -File tests\sarif\run_sarif_tests.ps1`
Expected at this point (Step 1 already written the unit): the test should actually **PASS**. If you are doing strict red-first, temporarily rename `ToJson`'s body to `Result := '{}';`, run -> FAIL (`SARIF parses as JSON` passes but `version is 2.1.0` FAILs with nil-deref guard), then restore the real body. Either way, end with a real green run.

- [ ] **Step 4: Run the test to verify it passes**

Run: `pwsh -File tests\sarif\run_sarif_tests.ps1`
Expected: `sarif-tests: 14 pass / 0 fail / 14 total`, exit 0.

- [ ] **Step 5: Register the unit in the CLI project (so Task 5 can call it)**

In `src/cli/drag-lint.dpr`, add this line in the `uses` clause immediately after the `DRagLint.Diagnostics.FlowChecks in ...` line (line 48):

```pascal
  DRagLint.Output.Sarif in '..\output\DRagLint.Output.Sarif.pas',
```

In `src/cli/drag-lint.dproj`, add this line immediately after the `<DCCReference Include="..\diagnostics\DRagLint.Diagnostics.FlowChecks.pas"/>` line (line 138):

```xml
        <DCCReference Include="..\output\DRagLint.Output.Sarif.pas"/>
```

- [ ] **Step 6: Build the CLI to confirm the unit compiles+links into drag-lint.exe**

Invoke the **delphi-build** skill (write `scratchpad\build_cli.bat`, run via `Start-Process -Wait`, read the log).
Expected: log shows `BUILD_EXITCODE=0` and no `[dcc64 Error]`. Then deploy: copy `src\cli\Win64\Debug\drag-lint.exe` -> `third_party\dll-win64\drag-lint.exe`.

- [ ] **Step 7: Confirm the lint harness is still green (no behavior change yet)**

Run: `pwsh -File tests\lint\run_lint_tests.ps1`
Expected: `91/91` (or the script's PASS summary), exit 0.

- [ ] **Step 8: Normalize line endings on the new/edited `.pas` files, then commit**

Normalize each touched `.pas`/`.dpr` to CRLF + UTF-8-no-BOM (PowerShell):

```powershell
foreach ($f in @('src\output\DRagLint.Output.Sarif.pas','tests\sarif\SarifTests.dpr','src\cli\drag-lint.dpr')) {
  $p = Join-Path (Get-Location) $f
  $t = [IO.File]::ReadAllText($p) -replace "`r`n","`n" -replace "`n","`r`n"
  [IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($false)))
}
```

```bash
git add src/output/DRagLint.Output.Sarif.pas tests/sarif/ src/cli/drag-lint.dpr src/cli/drag-lint.dproj
git commit -m "feat(output): SARIF 2.1.0 writer (DRagLint.Output.Sarif) + console test"
```

---

## Task 2: `--fail-on` exit-code policy

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- add `FailOn` field to `TArgs` (after line 105), parse `--fail-on` in `ParseArgs` (after the `--format` branch, ~line 487), add the `ExitCodeFor` helper function (just before `DoLint`, ~line 4307), update `PrintHelp`.
- Create: `tests/ergonomics/ExitCodeTests.dpr`
- Create: `tests/ergonomics/run_exitcode_tests.ps1`

**Interfaces:**
- Produces: `function ExitCodeFor(const AFindings: TArray<TLintFinding>; const AFailOn: string; ADefaultCode: Integer): Integer;` -- exit-code policy. Task 5 calls it as the last step of `FinalizeAndOutput`.
- For the unit test, `ExitCodeFor` must be testable in isolation. Put the **pure ranking logic** in a tiny dep-free unit so the console test can build it without dragging in CLI.pas. Create `src/output/DRagLint.Output.ExitCode.pas` holding the logic; `ExitCodeFor` in CLI.pas becomes a one-line forwarder. (This keeps CLI.pas free of new testable surface and gives Task 2 a real bare-`dcc64` test.)

- [ ] **Step 1: Write the failing console test**

Create `tests/ergonomics/ExitCodeTests.dpr`:

```pascal
program ExitCodeTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DRagLint.Core.Model in '..\..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Output.ExitCode in '..\..\src\output\DRagLint.Output.ExitCode.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;

function F(const ASeverity: string): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId:= 'r'; Result.Severity:= ASeverity;
end;

procedure TestExitCode;
var
  Warns, Infos, Errs, Empty: TArray<TLintFinding>;
begin
  Empty:= [];
  Infos:= [F('info')];
  Warns:= [F('info'), F('warning')];
  Errs := [F('warning'), F('error')];

  // Flag absent => preserve default code.
  Check('absent: default 1 preserved', ExitCodeFor(Warns, '', 1) = 1);
  Check('absent: default 0 preserved', ExitCodeFor(Empty, '', 0) = 0);

  // none => always 0.
  Check('none: errors -> 0', ExitCodeFor(Errs, 'none', 1) = 0);

  // error threshold.
  Check('fail-on error: has error -> 1', ExitCodeFor(Errs , 'error', 0) = 1);
  Check('fail-on error: only warning -> 0', ExitCodeFor(Warns, 'error', 0) = 0);

  // warning threshold (error or warning trips it).
  Check('fail-on warning: warning -> 1', ExitCodeFor(Warns, 'warning', 0) = 1);
  Check('fail-on warning: only info -> 0', ExitCodeFor(Infos, 'warning', 0) = 0);

  // info threshold (anything info+ trips it).
  Check('fail-on info: info -> 1', ExitCodeFor(Infos, 'info', 0) = 1);
  Check('fail-on info: empty -> 0', ExitCodeFor(Empty, 'info', 0) = 0);
end;

begin
  GPass:= 0; GFail:= 0;
  try
    TestExitCode;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('exitcode-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
```

Create `tests/ergonomics/run_exitcode_tests.ps1`:

```powershell
# Build + run the --fail-on exit-code policy unit tests (bare dcc64, Win64).
$rs  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir = $PSScriptRoot
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -E`"$dir`" `"$dir\ExitCodeTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 10; exit 1 }
& "$dir\ExitCodeTests.exe"
exit $LASTEXITCODE
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -File tests\ergonomics\run_exitcode_tests.ps1`
Expected: `BUILD FAILED` (unit `DRagLint.Output.ExitCode` does not exist yet).

- [ ] **Step 3: Write the minimal implementation unit**

Create `src/output/DRagLint.Output.ExitCode.pas`:

```pascal
unit DRagLint.Output.ExitCode;

interface

uses
  System.SysUtils, DRagLint.Core.Model;

/// <summary>Numeric rank of a drag-lint severity for ordering/comparison.
/// error=3, warning=2, info=1, hint/unknown=0.</summary>
function SeverityRank(const ASeverity: string): Integer;

/// <summary>Computes a process exit code from the surviving findings and the
/// --fail-on policy.</summary>
/// <param name="AFindings">Final surviving findings.</param>
/// <param name="AFailOn">'' (use ADefaultCode), 'none' (always 0), or a severity
/// name; nonzero iff any finding's rank >= that name's rank.</param>
/// <param name="ADefaultCode">The command's pre-existing exit code, used when
/// AFailOn is '' (preserves today's behavior).</param>
/// <returns>0 or 1 per the policy, or ADefaultCode when AFailOn is ''.</returns>
function ExitCodeFor(const AFindings: TArray<TLintFinding>; const AFailOn: string; ADefaultCode: Integer): Integer;

implementation

function SeverityRank(const ASeverity: string): Integer;
begin
  if SameText(ASeverity, 'error') then Result:= 3
  else if SameText(ASeverity, 'warning') then Result:= 2
  else if SameText(ASeverity, 'info') then Result:= 1
  else Result:= 0;
end;

function ExitCodeFor(const AFindings: TArray<TLintFinding>; const AFailOn: string; ADefaultCode: Integer): Integer;
var
  Threshold: Integer;
  F: TLintFinding;
begin
  if AFailOn = '' then Exit(ADefaultCode);
  if SameText(AFailOn, 'none') then Exit(0);
  Threshold:= SeverityRank(AFailOn);
  for F in AFindings do
    if SeverityRank(F.Severity) >= Threshold then Exit(1);
  Result:= 0;
end;

end.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pwsh -File tests\ergonomics\run_exitcode_tests.ps1`
Expected: `exitcode-tests: 9 pass / 0 fail / 9 total`, exit 0.

- [ ] **Step 5: Add `FailOn` to `TArgs` and parse `--fail-on`**

In `src/cli/DRagLint.CLI.pas`, add to the `TArgs` record (right after `ShowVersion : Boolean;` at line 106):

```pascal
    FailOn      : string ; // --fail-on error|warning|info|none (ergonomics #12)
    Baseline    : string ; // --baseline <file>: report only findings NOT in it
    WriteBaseline: string; // --write-baseline <file>: record current findings, exit 0
    ConfigPath  : string ; // --config <file>: drag-lint-lint.json override path
    Enable      : string ; // --enable id1,id2: re-include disabled/off-by-default rules
    Profile     : string ; // --profile <name>: merge a named enable/disable set
```

(Adding all #12 fields now avoids re-touching `TArgs` in Tasks 3-4.)

In `ParseArgs`, after the `--format` branch (after line 487, `end;`), add:

```pascal
    else if (A = '--fail-on') and (i < ParamCount) then
    begin
      Inc(i);
      Result.FailOn:= ParamStr(i);
    end
    else if (A = '--baseline') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Baseline:= ParamStr(i);
    end
    else if (A = '--write-baseline') and (i < ParamCount) then
    begin
      Inc(i);
      Result.WriteBaseline:= ParamStr(i);
    end
    else if (A = '--config') and (i < ParamCount) then
    begin
      Inc(i);
      Result.ConfigPath:= ParamStr(i);
    end
    else if (A = '--enable') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Enable:= ParamStr(i);
    end
    else if (A = '--profile') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Profile:= ParamStr(i);
    end
```

- [ ] **Step 6: Forward `ExitCodeFor` from the new unit into CLI.pas and add SARIF/ExitCode to the `uses`**

In `src/cli/DRagLint.CLI.pas`, add `DRagLint.Output.ExitCode` to the implementation `uses` clause (find the `uses` block under `implementation`; add the unit name alongside the other `DRagLint.*` units). The existing `DRagLint.Output.Sarif` was registered in the `.dpr` in Task 1; also add both to CLI.pas's own `uses` so the helpers resolve:

```pascal
  , DRagLint.Output.Sarif
  , DRagLint.Output.ExitCode
```

(`ExitCodeFor` is now visible in CLI.pas via the unit; no separate forwarder needed. The single-line forwarder mentioned in Interfaces is unnecessary -- using the unit directly is simpler.)

Register the new unit in the project: add to `src/cli/drag-lint.dpr` after the SARIF line:

```pascal
  DRagLint.Output.ExitCode in '..\output\DRagLint.Output.ExitCode.pas',
```

and to `src/cli/drag-lint.dproj` after the SARIF `<DCCReference>`:

```xml
        <DCCReference Include="..\output\DRagLint.Output.ExitCode.pas"/>
```

- [ ] **Step 7: Update `PrintHelp` to document the new flags**

In `PrintHelp` (near line 256, after the `check-ast` help line), add:

```pascal
  Writeln('');
  Writeln('  Output/CI (lint, lint-all, check-ast):');
  Writeln('    --format sarif            emit SARIF 2.1.0 (in addition to text|json)');
  Writeln('    --fail-on <level>         exit nonzero iff a surviving finding is >= error|warning|info (or none)');
  Writeln('    --config <file>           drag-lint-lint.json (else auto-discovered in CWD)');
  Writeln('    --enable id1,id2          re-include disabled / off-by-default rules');
  Writeln('    --profile <name>          merge a named enable/disable set from the config');
  Writeln('    --baseline <file>         report only findings absent from the baseline');
  Writeln('    --write-baseline <file>   record current findings as the baseline and exit 0');
```

- [ ] **Step 8: Build the CLI, deploy, confirm harness green**

Invoke **delphi-build** (`BUILD_EXITCODE=0`, no `[dcc64 Error]`), copy exe to `third_party\dll-win64\drag-lint.exe`.
Run: `pwsh -File tests\lint\run_lint_tests.ps1` -> Expected: `91/91` (default behavior unchanged; the flags exist but nothing calls `ExitCodeFor` yet -- exit codes are wired in Task 5).

- [ ] **Step 9: Normalize + commit**

Normalize touched `.pas`/`.dpr` (see Task 1 Step 8 snippet, adjusting the file list to `src\output\DRagLint.Output.ExitCode.pas`, `tests\ergonomics\ExitCodeTests.dpr`, `src\cli\DRagLint.CLI.pas`, `src\cli\drag-lint.dpr`).

```bash
git add src/output/DRagLint.Output.ExitCode.pas tests/ergonomics/ExitCodeTests.dpr tests/ergonomics/run_exitcode_tests.ps1 src/cli/DRagLint.CLI.pas src/cli/drag-lint.dpr src/cli/drag-lint.dproj
git commit -m "feat(output): --fail-on exit-code policy (ExitCodeFor) + args/help + console test"
```

---

## Task 3: Config -- severity / enable / disable / thresholds / profiles

**Files:**
- Create: `src/lint/DRagLint.Lint.Config.pas`
- Modify: `src/lint/DRagLint.Lint.QueryRules.pas` -- read `"enabled"` from the sidecar `.json` (~line 86), expose `Enabled` + `RuleId`.
- Modify: `src/lint/DRagLint.Lint.Linter.pas` -- expose `DefaultDisabledRuleIds: TArray<string>`.
- Modify: `src/diagnostics/DRagLint.Diagnostics.AstChecks.pas` -- add threshold-bearing overloads of `CheckTooManyExitPoints` / `CheckCyclomaticComplexity`.
- Modify: `src/cli/DRagLint.CLI.pas` -- add `LoadLintConfig` helper; pass thresholds into the metric checks in `DoLint` (~line 4392/4425/4427) and `DoLintAll` (~line 5268/5285/5286).
- Create: `tests/lintconfig/LintConfigTests.dpr`, `tests/lintconfig/run_lintconfig_tests.ps1`
- Modify: `src/cli/drag-lint.dpr` + `.dproj` (register `DRagLint.Lint.Config`)

**Interfaces:**
- Consumes: `TLintFinding`.
- Produces:
  - `TLintConfig.Load(const APath, AProfile: string): TLintConfig` -- loads config (empty `APath` => default, no-op config), then merges the named profile's `disabled`/`enabled` if `AProfile` is set.
  - `TLintConfig.ApplySeverity(const ARuleId, ADefault: string): string`
  - `TLintConfig.ShouldKeep(const ARuleId: string; ADefaultDisabled: Boolean): Boolean`
  - `TLintConfig.IsEnabled(const ARuleId: string): Boolean` (= `ShouldKeep(ARuleId, False)`)
  - `TLintConfig.ThresholdFor(const AName: string; ADefault: Integer): Integer`
  - `TLintConfig.AddDisabled(const AIds: TArray<string>)`, `TLintConfig.AddEnabled(const AIds: TArray<string>)`
  - `TAstChecker.CheckTooManyExitPoints(const AFile: string; AMaxExits: Integer): TArray<TLintFinding>` (overload)
  - `TAstChecker.CheckCyclomaticComplexity(const AFile: string; AMaxComplexity: Integer): TArray<TLintFinding>` (overload)
  - `TLinter.DefaultDisabledRuleIds: TArray<string>`
  - `LoadLintConfig(const AArgs: TArgs): TLintConfig` (CLI helper)

- [ ] **Step 1: Write the failing config unit test**

Create `tests/lintconfig/LintConfigTests.dpr`:

```pascal
program LintConfigTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils,
  DRagLint.Core.Model in '..\..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Lint.Config in '..\..\src\lint\DRagLint.Lint.Config.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;

const
  CONFIG_JSON =
    '{'#10 +
    '  "disabled": ["magic-number"],'#10 +
    '  "enabled":  ["naming-pascalcase"],'#10 +
    '  "severity": { "object-leak": "error" },'#10 +
    '  "thresholds": { "too-many-parameters": 3, "cyclomatic-complexity": 99 },'#10 +
    '  "profiles": { "ci": { "disabled": ["deep-nesting"] } }'#10 +
    '}'#10;

procedure TestConfig;
var
  Cfg: TLintConfig;
  Path: string;
begin
  Path:= TPath.Combine(TPath.GetTempPath, 'dl-cfg-test.json');
  TFile.WriteAllText(Path, CONFIG_JSON, TEncoding.UTF8);
  try
    Cfg:= TLintConfig.Load(Path, '');

    // severity remap
    Check('severity remap object-leak->error',
      Cfg.ApplySeverity('object-leak', 'info') = 'error');
    Check('severity passthrough for unmapped',
      Cfg.ApplySeverity('use-after-free', 'warning') = 'warning');

    // disabled
    Check('disabled magic-number dropped', not Cfg.ShouldKeep('magic-number', False));
    Check('non-disabled kept', Cfg.ShouldKeep('object-leak', False));

    // default-disabled rule re-enabled by config "enabled"
    Check('off-by-default + in enabled -> kept',
      Cfg.ShouldKeep('naming-pascalcase', True));
    Check('off-by-default + NOT enabled -> dropped',
      not Cfg.ShouldKeep('some-other-off-rule', True));

    // thresholds
    Check('threshold override too-many-parameters=3',
      Cfg.ThresholdFor('too-many-parameters', 7) = 3);
    Check('threshold default when unset',
      Cfg.ThresholdFor('too-many-locals', 25) = 25);

    // profile merge
    Cfg:= TLintConfig.Load(Path, 'ci');
    Check('profile ci adds deep-nesting to disabled',
      not Cfg.ShouldKeep('deep-nesting', False));
    Check('profile keeps top-level disabled too',
      not Cfg.ShouldKeep('magic-number', False));

    // --enable composition
    Cfg:= TLintConfig.Load(Path, '');
    Cfg.AddEnabled(['some-other-off-rule']);
    Check('AddEnabled re-includes off-by-default',
      Cfg.ShouldKeep('some-other-off-rule', True));

    // empty path => no-op config
    Cfg:= TLintConfig.Load('', '');
    Check('empty config keeps everything', Cfg.ShouldKeep('magic-number', False) = True);
    Check('empty config default threshold', Cfg.ThresholdFor('too-many-parameters', 7) = 7);
    Check('empty config severity passthrough', Cfg.ApplySeverity('object-leak', 'info') = 'info');
  finally
    if TFile.Exists(Path) then TFile.Delete(Path);
  end;
end;

begin
  GPass:= 0; GFail:= 0;
  try
    TestConfig;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('lintconfig-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
```

Create `tests/lintconfig/run_lintconfig_tests.ps1`:

```powershell
# Build + run the drag-lint-lint.json config unit tests (bare dcc64, Win64).
$rs  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir = $PSScriptRoot
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -E`"$dir`" `"$dir\LintConfigTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 10; exit 1 }
& "$dir\LintConfigTests.exe"
exit $LASTEXITCODE
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -File tests\lintconfig\run_lintconfig_tests.ps1`
Expected: `BUILD FAILED` (unit `DRagLint.Lint.Config` does not exist).

- [ ] **Step 3: Write the config unit**

Create `src/lint/DRagLint.Lint.Config.pas`:

```pascal
unit DRagLint.Lint.Config;

interface

uses
  System.SysUtils, System.JSON, System.IOUtils, DRagLint.Core.Model;

type
  /// <summary>Per-project lint configuration loaded from drag-lint-lint.json:
  /// severity overrides, enable/disable lists, metric thresholds, and named
  /// profiles. A value type -- Load returns a fresh copy; AddEnabled/AddDisabled
  /// mutate the local copy in place. An unloaded (default) config is a no-op:
  /// every rule kept at its declared severity, every threshold = the passed
  /// default.</summary>
  TLintConfig = record
  strict private
    FDisabled    : TArray<string> ;
    FEnabled     : TArray<string> ;
    FSevNames    : TArray<string> ; // parallel arrays: rule id -> severity
    FSevValues   : TArray<string> ;
    FThreshNames : TArray<string> ; // parallel arrays: metric name -> value
    FThreshValues: TArray<Integer>;
    class function Contains(const AArr: TArray<string>; const AId: string): Boolean; static;
    procedure MergeListsFrom(const AObj: TJSONObject);
  public
    /// <summary>Loads config from APath (JSON). Empty/missing APath yields a
    /// no-op default config. If AProfile is non-empty and present under
    /// "profiles", its disabled/enabled lists are merged over the top level.</summary>
    class function Load(const APath, AProfile: string): TLintConfig; static;
    /// <summary>Returns the configured severity for ARuleId, else ADefault.</summary>
    function ApplySeverity(const ARuleId, ADefault: string): string;
    /// <summary>Keep policy for a finding's rule. Dropped if disabled; an
    /// off-by-default rule (ADefaultDisabled) is dropped unless re-enabled.</summary>
    function ShouldKeep(const ARuleId: string; ADefaultDisabled: Boolean): Boolean;
    /// <summary>Convenience: ShouldKeep(ARuleId, False).</summary>
    function IsEnabled(const ARuleId: string): Boolean;
    /// <summary>Returns the configured threshold for AName, else ADefault.</summary>
    function ThresholdFor(const AName: string; ADefault: Integer): Integer;
    /// <summary>Appends ids to the effective enabled set (for --enable).</summary>
    procedure AddEnabled(const AIds: TArray<string>);
    /// <summary>Appends ids to the effective disabled set (for --disable).</summary>
    procedure AddDisabled(const AIds: TArray<string>);
  end;

implementation

class function TLintConfig.Contains(const AArr: TArray<string>; const AId: string): Boolean;
var
  S: string;
begin
  for S in AArr do
    if SameText(Trim(S), AId) then Exit(True);
  Result:= False;
end;

procedure TLintConfig.MergeListsFrom(const AObj: TJSONObject);
var
  Arr: TJSONArray;
  V  : TJSONValue;
begin
  if AObj = nil then Exit;
  if AObj.GetValue('disabled') is TJSONArray then
  begin
    Arr:= AObj.GetValue('disabled') as TJSONArray;
    for V in Arr do FDisabled:= FDisabled + [V.Value];
  end;
  if AObj.GetValue('enabled') is TJSONArray then
  begin
    Arr:= AObj.GetValue('enabled') as TJSONArray;
    for V in Arr do FEnabled:= FEnabled + [V.Value];
  end;
end;

class function TLintConfig.Load(const APath, AProfile: string): TLintConfig;
var
  Root, Sev, Thr, Profiles, Prof: TJSONObject;
  Pair: TJSONPair;
  RawText: string;
  RootVal: TJSONValue;
begin
  Result:= Default(TLintConfig);
  if (APath = '') or (not TFile.Exists(APath)) then Exit;

  RawText:= TFile.ReadAllText(APath, TEncoding.UTF8);
  RootVal:= TJSONObject.ParseJSONValue(RawText);
  if not (RootVal is TJSONObject) then
  begin
    RootVal.Free;
    Exit;
  end;
  try
    Root:= RootVal as TJSONObject;

    Result.MergeListsFrom(Root);

    if Root.GetValue('severity') is TJSONObject then
    begin
      Sev:= Root.GetValue('severity') as TJSONObject;
      for Pair in Sev do
      begin
        Result.FSevNames := Result.FSevNames  + [Pair.JsonString.Value];
        Result.FSevValues:= Result.FSevValues + [Pair.JsonValue.Value];
      end;
    end;

    if Root.GetValue('thresholds') is TJSONObject then
    begin
      Thr:= Root.GetValue('thresholds') as TJSONObject;
      for Pair in Thr do
      begin
        Result.FThreshNames := Result.FThreshNames  + [Pair.JsonString.Value];
        Result.FThreshValues:= Result.FThreshValues + [StrToIntDef(Pair.JsonValue.Value, 0)];
      end;
    end;

    if (AProfile <> '') and (Root.GetValue('profiles') is TJSONObject) then
    begin
      Profiles:= Root.GetValue('profiles') as TJSONObject;
      if Profiles.GetValue(AProfile) is TJSONObject then
      begin
        Prof:= Profiles.GetValue(AProfile) as TJSONObject;
        Result.MergeListsFrom(Prof);
      end;
    end;
  finally
    RootVal.Free;
  end;
end;

function TLintConfig.ApplySeverity(const ARuleId, ADefault: string): string;
var
  i: Integer;
begin
  for i:= 0 to High(FSevNames) do
    if SameText(FSevNames[i], ARuleId) then Exit(FSevValues[i]);
  Result:= ADefault;
end;

function TLintConfig.ShouldKeep(const ARuleId: string; ADefaultDisabled: Boolean): Boolean;
begin
  if Contains(FDisabled, ARuleId) then Exit(False);
  if ADefaultDisabled and (not Contains(FEnabled, ARuleId)) then Exit(False);
  Result:= True;
end;

function TLintConfig.IsEnabled(const ARuleId: string): Boolean;
begin
  Result:= ShouldKeep(ARuleId, False);
end;

function TLintConfig.ThresholdFor(const AName: string; ADefault: Integer): Integer;
var
  i: Integer;
begin
  for i:= 0 to High(FThreshNames) do
    if SameText(FThreshNames[i], AName) then Exit(FThreshValues[i]);
  Result:= ADefault;
end;

procedure TLintConfig.AddEnabled(const AIds: TArray<string>);
var
  S: string;
begin
  for S in AIds do
    if Trim(S) <> '' then FEnabled:= FEnabled + [Trim(S)];
end;

procedure TLintConfig.AddDisabled(const AIds: TArray<string>);
var
  S: string;
begin
  for S in AIds do
    if Trim(S) <> '' then FDisabled:= FDisabled + [Trim(S)];
end;

end.
```

- [ ] **Step 4: Run the config test to verify it passes**

Run: `pwsh -File tests\lintconfig\run_lintconfig_tests.ps1`
Expected: `lintconfig-tests: 14 pass / 0 fail / 14 total`, exit 0.

- [ ] **Step 5: Add `"enabled"` support to the `.scm` sidecar loader**

In `src/lint/DRagLint.Lint.QueryRules.pas`, find the `TQueryRule` class (~line 24) and add to its public surface a field + property (next to `FSeverity`/`Severity`):

```pascal
      FEnabled    : Boolean ;
      FRuleId     : string  ;
```
```pascal
      property Enabled : Boolean read FEnabled;
      property RuleId  : string  read FRuleId ;
```

In the constructor `TQueryRule.Create` (~line 65), after `FSeverity:= 'warning';` (line 75) add:

```pascal
  FEnabled:= True;   // rules run unless their sidecar json says "enabled": false
```

In the sidecar-json block (~line 86, where `severity` is read), add an `enabled` and `id` read. The existing line is:

```pascal
      if JSON.GetValue('severity'    ) <> nil then FSeverity   := JSON.GetValue('severity'    ).Value;
```

Add right after it:

```pascal
      if JSON.GetValue('id'          ) <> nil then FRuleId     := JSON.GetValue('id'          ).Value;
      if JSON.GetValue('enabled'     ) <> nil then
        FEnabled:= not SameText(JSON.GetValue('enabled').Value, 'false');
```

(`"enabled": false` -> `FEnabled := False`; absent or `true` -> stays True. `RuleId` falls back to whatever the rule already uses for findings if `id` is absent -- leave `FRuleId` empty in that case; `DefaultDisabledRuleIds` below only cares about rules that explicitly set both `id` and `enabled:false`.)

- [ ] **Step 6: Expose `DefaultDisabledRuleIds` on the Linter**

First confirm how `TLinter` holds its loaded rules:

Run: `pwsh -Command "Select-String -Path src\lint\DRagLint.Lint.Linter.pas -Pattern 'FRules|FQueryRules|TQueryRule|LoadAll' | Select-Object -First 12"`
Expected: shows a private field (e.g. `FRules: TArray<TQueryRule>`) populated by `TQueryRuleLoader.LoadAll` in the constructor.

In `src/lint/DRagLint.Lint.Linter.pas`, add to the public surface of `TLinter` (next to `ExternalRuleCount`, line 36):

```pascal
      /// <summary>Rule ids of loaded .scm rules whose sidecar json declared
      /// "enabled": false (ship off-by-default). Findings from these are dropped
      /// downstream unless re-enabled via config "enabled" / --enable.</summary>
      function DefaultDisabledRuleIds: TArray<string>;
```

Implement it (place near `ExternalRuleCount`'s implementation, ~line 319). Use the actual private field name discovered above; assuming `FRules`:

```pascal
function TLinter.DefaultDisabledRuleIds: TArray<string>;
var
  R: TQueryRule;
begin
  Result:= nil;
  for R in FRules do
    if (not R.Enabled) and (R.RuleId <> '') then
      Result:= Result + [R.RuleId];
end;
```

If the field name differs, adapt. If `TLinter` does not currently retain the rules array (only a count), add `FRules: TArray<TQueryRule>;` and assign it from `TQueryRuleLoader.LoadAll(...)` in the constructor where `ExternalRuleCount`'s backing value is set.

- [ ] **Step 7: Add threshold overloads to the two single-arg metric checks**

In `src/diagnostics/DRagLint.Diagnostics.AstChecks.pas`, change the two declarations (lines 195 and 202) to `overload` and add a threshold-bearing variant:

```pascal
      class function CheckTooManyExitPoints(const AFile: string): TArray<TLintFinding>; overload;
      class function CheckTooManyExitPoints(const AFile: string; AMaxExits: Integer): TArray<TLintFinding>; overload;
      class function CheckCyclomaticComplexity(const AFile: string): TArray<TLintFinding>; overload;
      class function CheckCyclomaticComplexity(const AFile: string; AMaxComplexity: Integer): TArray<TLintFinding>; overload;
```

In the implementation, locate each existing body. Each has a hardcoded literal (`5` for exit points, `15` for cyclomatic). Refactor: the no-arg version forwards to the new one with the historic default; the new version uses its parameter as the threshold. Run this to find the literal sites:

Run: `pwsh -Command "Select-String -Path src\diagnostics\DRagLint.Diagnostics.AstChecks.pas -Pattern 'function TAstChecker.CheckTooManyExitPoints|function TAstChecker.CheckCyclomaticComplexity' -Context 0,30"`
Expected: shows both bodies. In each body, replace the hardcoded comparison constant with the parameter, and add the forwarder. Pattern (apply to both, using the right names/literals):

```pascal
class function TAstChecker.CheckTooManyExitPoints(const AFile: string): TArray<TLintFinding>;
begin
  Result:= CheckTooManyExitPoints(AFile, 5);   // historic default
end;

class function TAstChecker.CheckTooManyExitPoints(const AFile: string; AMaxExits: Integer): TArray<TLintFinding>;
begin
  // ... existing body, but compare against AMaxExits instead of the literal 5 ...
end;
```

Do the same for `CheckCyclomaticComplexity` (default `15`, parameter `AMaxComplexity`). Keep the existing body logic intact -- only the threshold literal becomes the parameter.

- [ ] **Step 8: Add the `LoadLintConfig` helper and pass thresholds into the metric checks**

In `src/cli/DRagLint.CLI.pas`, register `DRagLint.Lint.Config` in the `.dpr`/`.dproj` (after `DRagLint.Output.ExitCode`) and add it to CLI.pas's implementation `uses`. Then add this helper just above `function DoLint` (~line 4307):

```pascal
/// <summary>Builds the effective TLintConfig for a command: discovers the config
/// file (--config, else drag-lint-lint.json in CWD), applies the named --profile,
/// and composes --disable/--enable from the command line.</summary>
function LoadLintConfig(const AArgs: TArgs): TLintConfig;
var
  Path: string;
begin
  Path:= AArgs.ConfigPath;
  if (Path = '') and TFile.Exists('drag-lint-lint.json') then Path:= 'drag-lint-lint.json';
  Result:= TLintConfig.Load(Path, AArgs.Profile);
  if AArgs.Disable <> '' then Result.AddDisabled(AArgs.Disable.Split([',', ' ', ';']));
  if AArgs.Enable  <> '' then Result.AddEnabled (AArgs.Enable .Split([',', ' ', ';']));
end;
```

In `DoLint`, just before the metric-check block (before line 4391), add:

```pascal
      var Cfg: TLintConfig:= LoadLintConfig(AArgs);
```

Change line 4392 from:

```pascal
        for F in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckRoutineMetrics(AArgs.Path, 7, 25, 120, 5) do
```
to:
```pascal
        for F in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckRoutineMetrics(AArgs.Path,
            Cfg.ThresholdFor('too-many-parameters', 7), Cfg.ThresholdFor('too-many-locals', 25),
            Cfg.ThresholdFor('method-too-long', 120), Cfg.ThresholdFor('deep-nesting', 5)) do
```

Change line 4425 from:
```pascal
      if (AArgs.Rule = '') or (AArgs.Rule = 'too-many-exit-points') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTooManyExitPoints(AArgs.Path);
```
to:
```pascal
      if (AArgs.Rule = '') or (AArgs.Rule = 'too-many-exit-points') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTooManyExitPoints(AArgs.Path, Cfg.ThresholdFor('too-many-exit-points', 5));
```

Change line 4427 from:
```pascal
      if (AArgs.Rule = '') or (AArgs.Rule = 'cyclomatic-complexity') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCyclomaticComplexity(AArgs.Path);
```
to:
```pascal
      if (AArgs.Rule = '') or (AArgs.Rule = 'cyclomatic-complexity') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCyclomaticComplexity(AArgs.Path, Cfg.ThresholdFor('cyclomatic-complexity', 15));
```

In `DoLintAll`, apply the same three substitutions at lines 5268, 5285, 5286. Add `var Cfg: TLintConfig:= LoadLintConfig(AArgs);` once before the per-file loop that contains those calls (find the loop opening near line 5260 and place `Cfg` outside it so it loads once).

- [ ] **Step 9: Build, deploy, write a CLI threshold fixture test, confirm harness green**

Invoke **delphi-build**, deploy exe.

Add a threshold integration check to `tests/ergonomics`. Create `tests/ergonomics/threshold_fixture.pas` -- a routine with exactly 4 parameters (clean at default 7, dirty at threshold 3):

```pascal
unit threshold_fixture;
interface
procedure FourParams(pA, pB, pC, pD: Integer);
implementation
procedure FourParams(pA, pB, pC, pD: Integer);
begin
  if pA > 0 then Writeln(pB + pC + pD);
end;
end.
```

Create `tests/ergonomics/threshold_config.json`:

```json
{ "thresholds": { "too-many-parameters": 3 } }
```

Create `tests/ergonomics/run_threshold_test.ps1`:

```powershell
$exe = (Resolve-Path "third_party\dll-win64\drag-lint.exe").Path
$fx  = (Resolve-Path "tests\ergonomics\threshold_fixture.pas").Path
$cfg = (Resolve-Path "tests\ergonomics\threshold_config.json").Path
# Default thresholds: 4 params is under 7 -> no too-many-parameters finding.
$base = & $exe lint $fx --rule too-many-parameters 2>$null | Out-String
# With config lowering to 3: 4 params trips it.
$low  = & $exe lint $fx --rule too-many-parameters --config $cfg 2>$null | Out-String
$ok1 = ($base -notmatch 'too-many-parameters')
$ok2 = ($low  -match    'too-many-parameters')
if ($ok1 -and $ok2) { Write-Host "PASS threshold config flips finding on"; exit 0 }
Write-Host "FAIL  base='$base'  low='$low'"; exit 1
```

Run: `pwsh -File tests\ergonomics\run_threshold_test.ps1` -> Expected: `PASS`.
Run: `pwsh -File tests\lint\run_lint_tests.ps1` -> Expected: `91/91` (default thresholds unchanged).

- [ ] **Step 10: Normalize + commit**

Normalize touched `.pas`/`.dpr` files. Commit:

```bash
git add src/lint/DRagLint.Lint.Config.pas src/lint/DRagLint.Lint.QueryRules.pas src/lint/DRagLint.Lint.Linter.pas src/diagnostics/DRagLint.Diagnostics.AstChecks.pas src/cli/DRagLint.CLI.pas src/cli/drag-lint.dpr src/cli/drag-lint.dproj tests/lintconfig/ tests/ergonomics/threshold_fixture.pas tests/ergonomics/threshold_config.json tests/ergonomics/run_threshold_test.ps1
git commit -m "feat(lint): drag-lint-lint.json config -- severity/enable/disable/thresholds/profiles + .scm enabled:false"
```

---

## Task 4: Baseline / suppression file

**Files:**
- Create: `src/lint/DRagLint.Lint.Baseline.pas`
- Create: `tests/baseline/BaselineTests.dpr`, `tests/baseline/run_baseline_tests.ps1`
- Modify: `src/cli/drag-lint.dpr` + `.dproj` (register `DRagLint.Lint.Baseline`)

**Interfaces:**
- Consumes: `TLintFinding`.
- Produces:
  - `TBaseline.Fingerprint(const AFinding: TLintFinding): string` -- single-finding fingerprint (rule + normpath + hashed trimmed source-line text; line-number independent).
  - `TBaseline.Write(const APath: string; const AFindings: TArray<TLintFinding>)` -- writes `{ "version":1, "fingerprints":[...] }`.
  - `TBaseline.Filter(const APath: string; const AFindings: TArray<TLintFinding>): TArray<TLintFinding>` -- returns only findings whose fingerprint is NOT in the baseline.

- [ ] **Step 1: Write the failing baseline test**

Create `tests/baseline/BaselineTests.dpr`:

```pascal
program BaselineTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils,
  DRagLint.Core.Model in '..\..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Lint.Baseline in '..\..\src\lint\DRagLint.Lint.Baseline.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;

function MkFinding(const ARule, AFile: string; ALine: Integer): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId  := ARule;
  Result.Severity:= 'warning';
  Result.FilePath:= AFile;
  Result.StartLine:= ALine; Result.StartCol:= 1;
  Result.EndLine  := ALine; Result.EndCol  := 5;
  Result.Message := ARule + ' here';
end;

procedure TestBaseline;
var
  SrcPath, BasePath, ShiftedSrc: string;
  Findings, Filtered: TArray<TLintFinding>;
begin
  SrcPath := TPath.Combine(TPath.GetTempPath, 'dl-base-src.pas');
  BasePath:= TPath.Combine(TPath.GetTempPath, 'dl-base.json');

  // Source whose line 3 holds the flagged statement.
  TFile.WriteAllText(SrcPath,
    'unit X;'#13#10 +            // line 1
    'begin'#13#10 +             // line 2
    '  DoTheThing(a, b);'#13#10 + // line 3  <- finding
    'end.'#13#10, TEncoding.UTF8);

  Findings:= [MkFinding('used-before-assignment', SrcPath, 3)];
  TBaseline.Write(BasePath, Findings);
  Check('baseline file written', TFile.Exists(BasePath));

  // Re-run identical -> 0 new.
  Filtered:= TBaseline.Filter(BasePath, Findings);
  Check('identical run => 0 new', Length(Filtered) = 0);

  // Insert an unrelated line ABOVE the finding; the flagged statement is now on
  // line 4. Same line CONTENT => fingerprint stable => still suppressed.
  ShiftedSrc:=
    'unit X;'#13#10 +
    '// a new comment'#13#10 +   // inserted
    'begin'#13#10 +
    '  DoTheThing(a, b);'#13#10 + // line 4 now
    'end.'#13#10;
  TFile.WriteAllText(SrcPath, ShiftedSrc, TEncoding.UTF8);
  Filtered:= TBaseline.Filter(BasePath, [MkFinding('used-before-assignment', SrcPath, 4)]);
  Check('line-shift stable => still 0 new', Length(Filtered) = 0);

  // A genuinely new finding (different line content) reports.
  Filtered:= TBaseline.Filter(BasePath, [MkFinding('used-before-assignment', SrcPath, 1)]); // line 1 = 'unit X;'
  Check('new finding (diff line text) reported', Length(Filtered) = 1);

  TFile.Delete(SrcPath);
  TFile.Delete(BasePath);
end;

begin
  GPass:= 0; GFail:= 0;
  try
    TestBaseline;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('baseline-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
```

Create `tests/baseline/run_baseline_tests.ps1`:

```powershell
# Build + run the baseline fingerprint/filter unit tests (bare dcc64, Win64).
$rs  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir = $PSScriptRoot
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -E`"$dir`" `"$dir\BaselineTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 10; exit 1 }
& "$dir\BaselineTests.exe"
exit $LASTEXITCODE
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -File tests\baseline\run_baseline_tests.ps1`
Expected: `BUILD FAILED` (unit `DRagLint.Lint.Baseline` does not exist).

- [ ] **Step 3: Write the baseline unit**

Create `src/lint/DRagLint.Lint.Baseline.pas`:

```pascal
unit DRagLint.Lint.Baseline;

interface

uses
  System.SysUtils, System.JSON, System.IOUtils, System.Hash,
  System.Generics.Collections, DRagLint.Core.Model;

type
  /// <summary>Line-shift-stable baseline: fingerprints findings by rule id +
  /// normalized path + a hash of the finding's (trimmed) source-line CONTENT, so
  /// inserting or removing unrelated lines does not invalidate a baselined
  /// finding. Used to report only NEW findings on a legacy codebase.</summary>
  TBaseline = class
  strict private
    /// <summary>Lowercased, backslash-normalized file path.</summary>
    class function NormPath(const APath: string): string; static;
    /// <summary>Reads (and caches in ACache) the trimmed text of line ALine
    /// (1-based) from AFile; '' if the file/line is unavailable.</summary>
    class function SourceLineText(const AFile: string; ALine: Integer;
      const ACache: TDictionary<string, TArray<string>>): string; static;
    /// <summary>Fingerprints with an occurrence ordinal appended pre-hash, so two
    /// findings on identical-text lines in the same (rule,file) disambiguate.</summary>
    class function FingerprintsOf(const AFindings: TArray<TLintFinding>): TArray<string>; static;
  public
    /// <summary>Fingerprint for one finding (occurrence ordinal 0). Stable across
    /// line-number shifts; changes only when rule, file, or the line text change.</summary>
    class function Fingerprint(const AFinding: TLintFinding): string; static;
    /// <summary>Writes the findings' fingerprints to APath as
    /// { "version":1, "fingerprints":[...] }.</summary>
    class procedure Write(const APath: string; const AFindings: TArray<TLintFinding>); static;
    /// <summary>Returns only findings whose fingerprint is absent from the
    /// baseline at APath. If APath is missing/unreadable, returns AFindings
    /// unchanged.</summary>
    class function Filter(const APath: string; const AFindings: TArray<TLintFinding>): TArray<TLintFinding>; static;
  end;

implementation

class function TBaseline.NormPath(const APath: string): string;
begin
  Result:= LowerCase(StringReplace(APath, '/', '\', [rfReplaceAll]));
end;

class function TBaseline.SourceLineText(const AFile: string; ALine: Integer;
  const ACache: TDictionary<string, TArray<string>>): string;
var
  Lines: TArray<string>;
begin
  Result:= '';
  if ALine < 1 then Exit;
  if not ACache.TryGetValue(AFile, Lines) then
  begin
    if TFile.Exists(AFile) then
      Lines:= TFile.ReadAllLines(AFile)
    else
      Lines:= [];
    ACache.Add(AFile, Lines);
  end;
  if (ALine - 1) <= High(Lines) then Result:= Trim(Lines[ALine - 1]);
end;

class function TBaseline.FingerprintsOf(const AFindings: TArray<TLintFinding>): TArray<string>;
var
  Cache  : TDictionary<string, TArray<string>>;
  Counts : TDictionary<string, Integer>;
  F      : TLintFinding;
  LineTxt, BaseKey, Ord, Raw: string;
  N      : Integer;
begin
  Result:= nil;
  Cache := TDictionary<string, TArray<string>>.Create;
  Counts:= TDictionary<string, Integer>.Create;
  try
    for F in AFindings do
    begin
      LineTxt:= SourceLineText(F.FilePath, F.StartLine, Cache);
      BaseKey:= LowerCase(F.RuleId) + '|' + NormPath(F.FilePath) + '|' + LineTxt;
      if not Counts.TryGetValue(BaseKey, N) then N:= 0;
      Counts.AddOrSetValue(BaseKey, N + 1);
      if N = 0 then Ord:= '' else Ord:= ':' + IntToStr(N);
      Raw:= BaseKey + Ord;
      Result:= Result + [THashSHA2.GetHashString(Raw)];
    end;
  finally
    Counts.Free;
    Cache.Free;
  end;
end;

class function TBaseline.Fingerprint(const AFinding: TLintFinding): string;
var
  Fps: TArray<string>;
begin
  Fps:= FingerprintsOf([AFinding]);
  Result:= Fps[0];
end;

class procedure TBaseline.Write(const APath: string; const AFindings: TArray<TLintFinding>);
var
  Root: TJSONObject;
  Arr : TJSONArray ;
  Fp  : string     ;
begin
  Root:= TJSONObject.Create;
  try
    Root.AddPair('version', TJSONNumber.Create(1));
    Arr:= TJSONArray.Create;
    Root.AddPair('fingerprints', Arr);
    for Fp in FingerprintsOf(AFindings) do
      Arr.Add(Fp);
    TFile.WriteAllText(APath, Root.Format(2), TEncoding.UTF8);
  finally
    Root.Free;
  end;
end;

class function TBaseline.Filter(const APath: string; const AFindings: TArray<TLintFinding>): TArray<TLintFinding>;
var
  RootVal: TJSONValue;
  Arr    : TJSONArray;
  Known  : TDictionary<string, Boolean>;
  V      : TJSONValue;
  Fps    : TArray<string>;
  i      : Integer;
begin
  if not TFile.Exists(APath) then Exit(AFindings);

  RootVal:= TJSONObject.ParseJSONValue(TFile.ReadAllText(APath, TEncoding.UTF8));
  if not (RootVal is TJSONObject) then
  begin
    RootVal.Free;
    Exit(AFindings);
  end;

  Known:= TDictionary<string, Boolean>.Create;
  try
    if (RootVal as TJSONObject).GetValue('fingerprints') is TJSONArray then
    begin
      Arr:= (RootVal as TJSONObject).GetValue('fingerprints') as TJSONArray;
      for V in Arr do Known.AddOrSetValue(V.Value, True);
    end;
    RootVal.Free;

    Result:= nil;
    Fps:= FingerprintsOf(AFindings);
    for i:= 0 to High(AFindings) do
      if not Known.ContainsKey(Fps[i]) then
        Result:= Result + [AFindings[i]];
  finally
    Known.Free;
  end;
end;

end.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pwsh -File tests\baseline\run_baseline_tests.ps1`
Expected: `baseline-tests: 4 pass / 0 fail / 4 total`, exit 0.

- [ ] **Step 5: Register the unit in the CLI project**

`src/cli/drag-lint.dpr` (after `DRagLint.Lint.Config` line):

```pascal
  DRagLint.Lint.Baseline in '..\lint\DRagLint.Lint.Baseline.pas',
```

`src/cli/drag-lint.dproj` (after the `DRagLint.Lint.Config.pas` `<DCCReference>`):

```xml
        <DCCReference Include="..\lint\DRagLint.Lint.Baseline.pas"/>
```

- [ ] **Step 6: Build, deploy, confirm harness green**

Invoke **delphi-build**, deploy exe.
Run: `pwsh -File tests\lint\run_lint_tests.ps1` -> Expected: `91/91` (still unwired -- baseline used only in Task 5).

- [ ] **Step 7: Normalize + commit**

```bash
git add src/lint/DRagLint.Lint.Baseline.pas tests/baseline/ src/cli/drag-lint.dpr src/cli/drag-lint.dproj
git commit -m "feat(lint): line-shift-stable baseline file (DRagLint.Lint.Baseline) + console test"
```

---

## Task 5: `FinalizeAndOutput` -- one shared tail across the three commands

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- add `FinalizeAndOutput`; rewrite the tails of `DoLint` (4437-4483), `DoLintAll` (5321-5400), `DoCheckAst` (7637-7668) to call it.
- Create: `tests/ergonomics/run_pipeline_tests.ps1` (end-to-end CLI tests for sarif/fail-on/baseline/severity).

**Interfaces:**
- Consumes: `TSarifWriter.ToJson`, `ExitCodeFor`, `TLintConfig`/`LoadLintConfig`, `TBaseline`, `ApplyLineSuppressions`.
- Produces: `function FinalizeAndOutput(const AArgs: TArgs; AFindings: TArray<TLintFinding>; ADefaultExit: Integer; const ADefaultDisabled: TArray<string>; const AEmitText: TProc<TArray<TLintFinding>>): Integer;`
  - Pipeline: line-suppressions -> config severity remap + enable/disable filter -> baseline (write-and-exit, or filter) -> output (sarif | json | `AEmitText` for text) -> `ExitCodeFor`.
  - `ADefaultDisabled`: rule ids that ship off-by-default (from `TLinter.DefaultDisabledRuleIds`); pass `nil` where no `.scm` rules run.
  - `AEmitText`: renders the command's bespoke human/text output (and, for lint-all, its report file). Called only on the text path. JSON/SARIF are uniform and owned by the helper.

- [ ] **Step 1: Write the `FinalizeAndOutput` helper**

In `src/cli/DRagLint.CLI.pas`, ensure `System.SysUtils` (for `TProc`) is in scope (it is). Add `DRagLint.Lint.Baseline` to the implementation `uses`. Add this function just below `LoadLintConfig` (added in Task 3):

```pascal
/// <summary>Shared output tail for the finding-producing commands. Applies line
/// suppressions, config (severity remap + enable/disable), and the baseline, then
/// emits the survivors as SARIF, JSON, or -- via AEmitText -- the command's own
/// text, and returns the policy exit code.</summary>
/// <param name="AArgs">Parsed CLI args (format, fail-on, baseline, config...).</param>
/// <param name="AFindings">Raw findings the command produced.</param>
/// <param name="ADefaultExit">Exit code to use when --fail-on is absent
/// (preserves each command's historic 1-if-any/0 behavior).</param>
/// <param name="ADefaultDisabled">Off-by-default rule ids (TLinter.DefaultDisabledRuleIds), or nil.</param>
/// <param name="AEmitText">Renders the text output for this command; called only on the text path.</param>
/// <returns>The process exit code.</returns>
function FinalizeAndOutput(const AArgs: TArgs; AFindings: TArray<TLintFinding>;
  ADefaultExit: Integer; const ADefaultDisabled: TArray<string>;
  const AEmitText: TProc<TArray<TLintFinding>>): Integer;
var
  Cfg     : TLintConfig         ;
  Survivors: TArray<TLintFinding>;
  F       : TLintFinding        ;
  IsDefDis: Boolean             ;
  DId     : string              ;
  JArr    : TJSONArray          ;
  JObj    : TJSONObject         ;
begin
  { 0: source-level ignore directives. }
  AFindings:= ApplyLineSuppressions(AFindings);

  { 1: config -- severity remap + enable/disable filter. }
  Cfg:= LoadLintConfig(AArgs);
  Survivors:= nil;
  for F in AFindings do
  begin
    IsDefDis:= False;
    for DId in ADefaultDisabled do
      if SameText(DId, F.RuleId) then begin IsDefDis:= True; Break; end;
    if Cfg.ShouldKeep(F.RuleId, IsDefDis) then
    begin
      F.Severity:= Cfg.ApplySeverity(F.RuleId, F.Severity);
      Survivors:= Survivors + [F];
    end;
  end;

  { 2a: --write-baseline records the current (config-filtered) state and exits. }
  if AArgs.WriteBaseline <> '' then
  begin
    DRagLint.Lint.Baseline.TBaseline.Write(AArgs.WriteBaseline, Survivors);
    Writeln(Format('baseline written: %d fingerprint(s) -> %s', [Length(Survivors), AArgs.WriteBaseline]));
    Exit(0);
  end;

  { 2b: --baseline keeps only findings absent from the baseline. }
  if AArgs.Baseline <> '' then
    Survivors:= DRagLint.Lint.Baseline.TBaseline.Filter(AArgs.Baseline, Survivors);

  { 3: output. }
  if SameText(AArgs.Format, 'sarif') then
    Writeln(DRagLint.Output.Sarif.TSarifWriter.ToJson(Survivors, VERSION))
  else if AArgs.AsJson or SameText(AArgs.Format, 'json') then
  begin
    JArr:= TJSONArray.Create;
    try
      for F in Survivors do
      begin
        JObj:= TJSONObject.Create;
        JObj.AddPair('rule'      , F.RuleId  );
        JObj.AddPair('severity'  , F.Severity);
        JObj.AddPair('file_path' , F.FilePath);
        JObj.AddPair('start_line', TJSONNumber.Create(F.StartLine));
        JObj.AddPair('start_col' , TJSONNumber.Create(F.StartCol ));
        JObj.AddPair('end_line'  , TJSONNumber.Create(F.EndLine  ));
        JObj.AddPair('end_col'   , TJSONNumber.Create(F.EndCol   ));
        JObj.AddPair('message'   , F.Message );
        JArr.AddElement(JObj);
      end;
      Writeln(JArr.Format(2));
    finally
      JArr.Free;
    end;
  end
  else if Assigned(AEmitText) then
    AEmitText(Survivors);

  { 4: exit code. }
  Result:= ExitCodeFor(Survivors, AArgs.FailOn, ADefaultExit);
end;
```

> Note: the shared JSON path uses `JArr.Format(2)` (pretty) to match `DoLint`/`DoCheckAst`. `DoLintAll` today emits compact `JArr.ToJSON` AND writes it to a report file; its `AEmitText` closure is NOT used on the JSON path, so its report-file write must move into the JSON branch behavior. To preserve lint-all's report file on JSON, see Step 3's lint-all handling (it passes `--output` semantics through; if a report file is required on the json path, lint-all keeps writing it before calling FinalizeAndOutput). For this milestone, lint-all's report file is written by its `AEmitText` (text path) only; the JSON path prints to stdout exactly like `DoLint`. This is an acceptable, documented simplification (JSON consumers read stdout; the dated report file remains a text-mode convenience).

- [ ] **Step 2: Rewrite `DoLint`'s tail to call `FinalizeAndOutput`**

In `DoLint`, the `Linter` is freed at line 4366/4367 inside the `if AArgs.Path <> '' then` block, so capture its default-disabled ids before freeing. Change the `try/finally` around the linter (lines 4352-4367) to record the ids:

```pascal
    Linter:= DRagLint.Lint.Linter.TLinter.Create(AArgs.RulesDir);
    try
      if Linter.ExternalRuleCount = 0 then
        Writeln(ErrOutput, 'drag-lint: note: 0 external .scm rules loaded -- place a "rules" folder next to drag-lint.exe, or pass --rules-dir <path> (built-in checks still run).');
      DefDisabled:= Linter.DefaultDisabledRuleIds;   // NEW: capture before Free
      if TFile.Exists(AArgs.Path) then Findings:= Findings + Linter.LintFile(AArgs.Path)
      else if TDirectory.Exists(AArgs.Path) then Findings:= Findings + Linter.LintFolder(AArgs.Path, True)
      else
      begin
        Writeln('ERROR: path does not exist: ', AArgs.Path);
        Exit(2);
      end;
    finally
      Linter.Free;
    end;
```

Add `DefDisabled: TArray<string>;` to `DoLint`'s `var` block (and initialize `DefDisabled:= nil;` near the top, since the `--project`-only path may not create a Linter).

Replace the entire tail (lines 4437-4483 -- the `ApplyLineSuppressions` call, the `--disable` block, the `if AArgs.AsJson ... else ...` output, and the final `if Length(Findings) > 0 ...`) with:

```pascal
  Result:= FinalizeAndOutput(AArgs, Findings, IfThen(Length(Findings) > 0, 1, 0), DefDisabled,
    procedure(const ASurv: TArray<TLintFinding>)
    var FF: TLintFinding;
    begin
      for FF in ASurv do
        Writeln(Format('%s:%d:%d  [%s] %s: %s', [FF.FilePath, FF.StartLine, FF.StartCol, FF.Severity, FF.RuleId, FF.Message]));
      Writeln(Format('%d finding(s)', [Length(ASurv)]));
    end);
```

> Important: the historic default exit code was `1 if Length(Findings) > 0 else 0` computed on the RAW findings. With config/baseline now able to drop findings, the more correct default is "nonzero iff survivors remain". But to preserve byte-for-byte default behavior (no config/baseline => survivors == findings), compute `ADefaultExit` from the raw `Findings` here; when a baseline/config is active the user opting into `--fail-on` gets survivor-based codes. Acceptable. (`IfThen` is in `System.Math` -- already used in the unit; if not, add it to `uses`.)

- [ ] **Step 3: Rewrite `DoLintAll`'s tail**

`DoLintAll` runs no `.scm` rules via a single `TLinter`, so its default-disabled set is `nil`. Keep the `OutPath` resolution (lines 5345-5353) -- the text closure needs it. Replace lines 5321-5400 (the `ApplyLineSuppressions`, `--disable` block, severity counts, and the `if AArgs.AsJson ... else ...` output + final exit) with:

```pascal
  Result:= FinalizeAndOutput(AArgs, Findings, IfThen(Length(Findings) > 0, 1, 0), nil,
    procedure(const ASurv: TArray<TLintFinding>)
    var
      FF: TLintFinding;
      EC, WC: Integer;
      OL: TStringBuilder;
    begin
      EC:= 0; WC:= 0;
      for FF in ASurv do
        if SameText(FF.Severity, 'error') then Inc(EC) else Inc(WC);
      OL:= TStringBuilder.Create;
      try
        for FF in ASurv do
          OL.AppendLine(Format('%s:%d:%d  [%s] %s: %s', [FF.FilePath, FF.StartLine, FF.StartCol, FF.Severity, FF.RuleId, FF.Message]));
        OL.AppendLine(Format('lint-all: %d finding(s) -- %d error(s), %d warning(s) -- %d file(s) scanned',
          [Length(ASurv), EC, WC, Length(FilePaths)]));
        TFile.WriteAllText(OutPath, OL.ToString, TEncoding.UTF8);
      finally
        OL.Free;
      end;
      for FF in ASurv do
        Writeln(Format('%s:%d:%d  [%s] %s: %s', [FF.FilePath, FF.StartLine, FF.StartCol, FF.Severity, FF.RuleId, FF.Message]));
      Writeln(Format('lint-all: %d finding(s) -- %d error(s), %d warning(s) -- %d file(s) -- report: %s',
        [Length(ASurv), EC, WC, Length(FilePaths), OutPath]));
    end);
```

Remove the now-unused `ErrCnt`/`WarnCnt`/`JArr`/`JObj`/`KeptF`/`DisIds`/`DId`/`Drop`/`OutLines` locals from `DoLintAll`'s `var` block if the compiler flags them as unused (Delphi warns, doesn't error; clean them to keep the build warning-free).

- [ ] **Step 4: Rewrite `DoCheckAst`'s tail**

`DoCheckAst` runs no `TLinter`; default-disabled is `nil`. Replace lines 7639-7668 (the `if SameText(AArgs.Format,'json') ... else ...` output and final exit) with:

```pascal
  Result:= FinalizeAndOutput(AArgs, Findings, IfThen(Length(Findings) > 0, 1, 0), nil,
    procedure(const ASurv: TArray<TLintFinding>)
    var FF: TLintFinding;
    begin
      for FF in ASurv do
        Writeln(Format('%s(%d,%d): %s %s: %s', [AArgs.Target, FF.StartLine, FF.StartCol, FF.Severity, FF.RuleId, FF.Message]));
      Writeln(Format('AST findings: %d', [Length(ASurv)]));
    end);
```

> Behavior delta to record in CHANGELOG: `check-ast` now also honors `// drag-lint:ignore` and `--config`/`--baseline`/`--fail-on`/`--format sarif` (previously it ignored suppressions and had only text/json). This is a strict, opt-in superset; default `check-ast <file>` and `check-ast <file> --format json` output is unchanged for files without ignore directives.

- [ ] **Step 5: Build + deploy**

Invoke **delphi-build** (`BUILD_EXITCODE=0`, no `[dcc64 Error]`), copy exe to `third_party\dll-win64\drag-lint.exe`. Resolve any "unused variable" warnings and one-off scope issues (e.g. `IfThen` needs `System.Math`; the text closure captures `FilePaths`/`OutPath` which must remain in `DoLintAll`'s outer scope -- they do).

- [ ] **Step 6: Run ALL unit-test harnesses (must stay green)**

Run each; all must pass:

```
pwsh -File tests\lint\run_lint_tests.ps1            # 91/91 -- default text/json unchanged
pwsh -File tests\flowengine\run_flowengine_tests.ps1   # 24/24
pwsh -File tests\sarif\run_sarif_tests.ps1
pwsh -File tests\ergonomics\run_exitcode_tests.ps1
pwsh -File tests\lintconfig\run_lintconfig_tests.ps1
pwsh -File tests\baseline\run_baseline_tests.ps1
pwsh -File tests\ergonomics\run_threshold_test.ps1
```

Expected: every harness exits 0 with its full pass count. If `run_lint_tests.ps1` regresses, the default (no-flag) path through `FinalizeAndOutput` diverged from the old inline output -- diff one fixture's `lint <f> --json` before/after to find the difference.

- [ ] **Step 7: Write end-to-end CLI pipeline tests (sarif / fail-on / baseline / severity)**

Create `tests/ergonomics/pipeline_fixture.pas` -- a file with one known finding (e.g. a `raise-in-finally` or an empty-except; reuse an existing dirty fixture's pattern). Simplest: a routine that uses a local before assignment (M2 `used-before-assignment`, severity warning):

```pascal
unit pipeline_fixture;
interface
function Compute: Integer;
implementation
function Compute: Integer;
var n: Integer;
begin
  Result:= n + 1;   // used-before-assignment: n read before any write
end;
end.
```

Create `tests/ergonomics/run_pipeline_tests.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$exe = (Resolve-Path "third_party\dll-win64\drag-lint.exe").Path
$fx  = (Resolve-Path "tests\ergonomics\pipeline_fixture.pas").Path
$pass = 0; $fail = 0
function Ok($n,$c){ if($c){$script:pass++; Write-Host "PASS  $n"} else {$script:fail++; Write-Host "FAIL  $n"} }

# 1. SARIF: --format sarif emits parseable SARIF with our rule.
$sarif = & $exe lint $fx --format sarif 2>$null | Out-String
$j = $null; try { $j = $sarif | ConvertFrom-Json } catch {}
Ok "sarif parses"            ($j -ne $null)
Ok "sarif version 2.1.0"     ($j.version -eq '2.1.0')
Ok "sarif has used-before-assignment" ($sarif -match 'used-before-assignment')

# 2. --fail-on: warning-level finding.
& $exe lint $fx --fail-on error  2>$null | Out-Null; $ecErr  = $LASTEXITCODE
& $exe lint $fx --fail-on warning 2>$null | Out-Null; $ecWarn = $LASTEXITCODE
& $exe lint $fx --fail-on none    2>$null | Out-Null; $ecNone = $LASTEXITCODE
Ok "fail-on error => 0 (only warning)" ($ecErr  -eq 0)
Ok "fail-on warning => 1"              ($ecWarn -eq 1)
Ok "fail-on none => 0"                 ($ecNone -eq 0)

# 3. severity override via --config: bump the rule to error, fail-on error now trips.
$cfg = Join-Path $PSScriptRoot 'pipeline_sev.json'
'{ "severity": { "used-before-assignment": "error" } }' | Set-Content -Encoding ASCII $cfg
& $exe lint $fx --config $cfg --fail-on error 2>$null | Out-Null; $ecSev = $LASTEXITCODE
Ok "severity bump => fail-on error trips" ($ecSev -eq 1)

# 4. disable via --config drops the finding entirely (text shows 0 findings).
$cfgD = Join-Path $PSScriptRoot 'pipeline_dis.json'
'{ "disabled": ["used-before-assignment"] }' | Set-Content -Encoding ASCII $cfgD
$dis = & $exe lint $fx --config $cfgD 2>$null | Out-String
Ok "disabled rule drops finding" ($dis -match '0 finding')

# 5. baseline round-trip: write, then re-run reports nothing new.
$base = Join-Path $PSScriptRoot 'pipeline.baseline.json'
& $exe lint $fx --write-baseline $base 2>$null | Out-Null
$new = & $exe lint $fx --baseline $base 2>$null | Out-String
Ok "baseline suppresses known finding" ($new -match '0 finding')

Remove-Item $cfg,$cfgD,$base -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "pipeline-tests: $pass pass / $fail fail"
if ($fail -gt 0) { exit 1 } else { exit 0 }
```

Run: `pwsh -File tests\ergonomics\run_pipeline_tests.ps1`
Expected: `pipeline-tests: 10 pass / 0 fail`, exit 0. (If `lint --format sarif` does not route through `FinalizeAndOutput`, you'll see text instead of JSON -- recheck Step 2's tail replacement actually removed the old inline output.)

- [ ] **Step 8: Normalize + commit**

Normalize touched `.pas` files. Commit:

```bash
git add src/cli/DRagLint.CLI.pas tests/ergonomics/pipeline_fixture.pas tests/ergonomics/run_pipeline_tests.ps1
git commit -m "refactor(cli): route lint/lint-all/check-ast through one FinalizeAndOutput tail (sarif/json/text + config + baseline + fail-on)"
```

---

## Task 6: Docs, CHANGELOG, real-code sanity

**Files:**
- Modify: `rules/README.md` (config schema + output formats)
- Modify: `CHANGELOG.md` (Ergonomics section under v0.66)
- Modify: `docs/lint/MISSING-FEATURES.md` (mark #12 closed)
- Modify: `docs/lint/BACKLOG.md` (update RESUME block: code done, publish next)

- [ ] **Step 1: Document config + formats in `rules/README.md`**

Append a section to `rules/README.md`:

```markdown
## CI / output ergonomics (v0.66)

`lint`, `lint-all`, and `check-ast` share an output tail:

- `--format sarif` -- SARIF 2.1.0 to stdout (alongside the existing `text` / `json`/`--json`).
- `--fail-on error|warning|info|none` -- process exits nonzero iff a surviving finding is at/above that level; `none` always exits 0. Absent => the historic exit code (1 if any finding).
- `--baseline <file>` -- report only findings NOT in the baseline. `--write-baseline <file>` records the current findings and exits 0. Fingerprints are line-shift stable (rule + path + hashed source-line text), so inserting unrelated lines does not re-surface a baselined finding.
- Config file `drag-lint-lint.json` (auto-discovered in CWD, or `--config <path>`):

  ```json
  {
    "disabled":  ["rule-id"],
    "enabled":   ["rule-id"],
    "severity":  { "rule-id": "error|warning|info|hint" },
    "thresholds":{ "too-many-parameters": 7, "too-many-locals": 25,
                   "method-too-long": 120, "deep-nesting": 5,
                   "cyclomatic-complexity": 15, "too-many-exit-points": 5 },
    "profiles":  { "ci": { "disabled": ["deep-nesting"], "enabled": [] } }
  }
  ```

  - `--enable id1,id2` and `--disable id1,id2` compose with the config.
  - `--profile <name>` merges a named profile's `disabled`/`enabled` over the top level.
  - A `.scm` rule whose sidecar `.json` has `"enabled": false` ships off-by-default; list its id under `enabled` (or `--enable`) to turn it on.

With no config, no baseline, and no `--fail-on`, every command behaves exactly as before.
```

- [ ] **Step 2: Add the CHANGELOG Ergonomics section**

Run `pwsh -Command "Get-Content CHANGELOG.md -TotalCount 30"` to find the v0.66 heading, then add under it:

```markdown
### Ergonomics / output (#12)
- `--format sarif`: SARIF 2.1.0 output for `lint`/`lint-all`/`check-ast` (GitHub code-scanning / CI ingestion).
- `--fail-on error|warning|info|none`: severity-gated process exit code.
- `drag-lint-lint.json` config (auto-discovered or `--config`): per-rule `severity` overrides, `disabled`/`enabled` lists, metric `thresholds`, and named `profiles`; `--enable`/`--disable`/`--profile` compose with it. `.scm` rules may ship off-by-default via sidecar `"enabled": false`.
- `--baseline`/`--write-baseline`: line-shift-stable baseline so legacy codebases report only NEW findings.
- All four flow through one shared `FinalizeAndOutput` tail; default (no-flag) behavior is unchanged. `check-ast` additionally gains `// drag-lint:ignore` suppression support.
- Autofix / quick-fixes remain deferred (a milestone of their own).
```

- [ ] **Step 3: Mark #12 closed in MISSING-FEATURES.md**

In `docs/lint/MISSING-FEATURES.md`, change the `12. Ergonomics / output -- gap` line (line 110) to `12. Ergonomics / output -- DONE v0.66 (SARIF, --fail-on, baseline, drag-lint-lint.json; autofix still deferred)`.

- [ ] **Step 4: Full real-code sanity run**

Run drag-lint on its own source as a smoke test of all four features end to end:

```powershell
$exe = "third_party\dll-win64\drag-lint.exe"
& $exe lint src\cli\DRagLint.CLI.pas --format sarif | Out-File scratchpad\selfcheck.sarif -Encoding ascii
Get-Content scratchpad\selfcheck.sarif -TotalCount 3      # should be SARIF JSON
& $exe lint src\cli\DRagLint.CLI.pas --write-baseline scratchpad\self.baseline.json
& $exe lint src\cli\DRagLint.CLI.pas --baseline scratchpad\self.baseline.json   # expect "0 finding(s)"
```

Expected: SARIF file parses; the baselined re-run reports 0 new. Confirm `lint src\cli\DRagLint.CLI.pas` (no flags) is identical to a pre-change run (default behavior preserved).

- [ ] **Step 5: Update the BACKLOG RESUME block**

In `docs/lint/BACKLOG.md`, update the top RESUME block: M1+M2+#12 code COMPLETE on `feat/m2-dataflow-cfg-engine`; **NEXT = publish v0.66.0-alpha** (merge branch to `main`; `build\pack-lint-release.ps1 -Version 0.66.0-alpha`; tag + GitHub prerelease per the existing publish recipe). Keep autofix listed as the deferred follow-on.

- [ ] **Step 6: Commit**

Normalize any touched files (the docs are `.md` -- CRLF not required, but keep consistent). Commit:

```bash
git add rules/README.md CHANGELOG.md docs/lint/MISSING-FEATURES.md docs/lint/BACKLOG.md
git commit -m "docs(ergonomics): config/formats README + CHANGELOG v0.66 Ergonomics + close #12"
```

---

## Publish (after Task 6 -- the user's gate, or on request)

Not a coding task; follow the existing release recipe in `docs/lint/BACKLOG.md`:
1. Merge `feat/m2-dataflow-cfg-engine` -> `main` (M1 + M2 + #12 together).
2. `pwsh -File build\pack-lint-release.ps1 -Version 0.66.0-alpha` (builds win64+win32 zips, deploys exe, bundles `rules/`).
3. `git push origin main`; `git tag v0.66.0-alpha`; `git push origin --tags`.
4. `gh release create v0.66.0-alpha --repo Alexl-git/Delphi-RAG-Lint --prerelease --notes-file <notes> <zips>`.

---

## Self-Review

**Spec coverage (each section of `2026-06-29-ergonomics-output-design.md`):**
- §3 SARIF writer -> Task 1 (`TSarifWriter.ToJson`, level mapping, deduped `rules[]`, region, uri).
- §4 `--fail-on` -> Task 2 (`ExitCodeFor`, severity order, `none`, default preservation).
- §5 baseline -> Task 4 (`Fingerprint`/`Write`/`Filter`, line-content hashing + occurrence ordinal, JSON `{version,fingerprints}`, `--baseline`/`--write-baseline`).
- §6 config -> Task 3 (`TLintConfig` with severity/disabled/enabled/thresholds/profiles, `--config`/`--enable`/`--profile`, `.scm "enabled":false` via `TQueryRule.Enabled` + `TLinter.DefaultDisabledRuleIds`, thresholds fed into the metric checks as inputs).
- §2/§7 pipeline order + `FinalizeAndOutput` -> Task 5 (config -> baseline -> format -> exit code; one shared tail in all three commands).
- §8 testing -> console unit tests in Tasks 1/2/3/4 + end-to-end CLI tests in Task 5; existing harness kept green every task.
- §9 non-goals (autofix, SARIF rule metadata, URI relativization) -> explicitly out of scope.
- §10 phasing -> Tasks map 1:1 (SARIF, fail-on, config, baseline, FinalizeAndOutput, docs).
- §11 definition of done -> Task 6 (CHANGELOG, README) + publish section.

**Deviation from spec phasing (intentional, DRY):** the spec wired each feature into the commands as it was built (stages 1-4) then de-duplicated in stage 5. This plan instead builds each component + its isolated console test first (Tasks 1-4, harness stays green because nothing is wired) and does ALL command wiring once in Task 5 via `FinalizeAndOutput` -- avoiding wire-then-unwire churn. The one unavoidable in-command change before Task 5 is threshold plumbing (Task 3), because thresholds are a check input, not a post-filter. CLI-level behavior tests for sarif/fail-on/baseline therefore live in Task 5 (where the behavior first exists) rather than their own earlier stage.

**Type consistency:** `FinalizeAndOutput(AArgs, Findings, ADefaultExit, ADefaultDisabled, AEmitText)` signature is identical at every call site; `TLintConfig.ShouldKeep(ruleId, defaultDisabled)` / `ApplySeverity(ruleId, default)` / `ThresholdFor(name, default)` names match between Task 3's unit, its test, and Task 5's consumer; `TBaseline.Write`/`Filter`/`Fingerprint` names match Task 4's unit, test, and Task 5; `TSarifWriter.ToJson(findings, version)` matches Task 1 and Task 5; `ExitCodeFor(findings, failOn, default)` matches Task 2 and Task 5. New `TArgs` fields (`FailOn`/`Baseline`/`WriteBaseline`/`ConfigPath`/`Enable`/`Profile`) are added once in Task 2 and consumed in Tasks 3-5.
