<#
  run_test_project_rule_scoping.ps1 -- two rules that fired on shapes no caller
  could fix, both reported by DataCopy on 2026-08-31.

  WHY BOTH LIVE IN ONE RUNNER. They are the same defect class, not the same
  rule: a check whose stated remedy is unavailable to the code it fires on.
  Keeping the pair together keeps that argument in one place, and each section
  below carries its own positive control so neither can pass vacuously.

  ---------------------------------------------------------------- SECTION 1 --
  `method-pascalcase` on DUnitX test methods -- 330 findings on one test
  project, 71% of its entire report.

  `Subject_does_the_thing` is not a style lapse in an xUnit suite: the runner
  PRINTS the method name, so the underscores ARE the failure report. 330 `dl:ok`
  markers would each record something untrue about the code, and the owner's
  standing rule is that a finding count in the thousands is itself the defect --
  fix the code or fix the RULE, never annotate around it.

  SCOPED BY THE ATTRIBUTE, NOT BY THE PROJECT. A blunter "skip test projects"
  would also silence genuine casing lapses in test HELPERS, which is why the
  negative control below is the load-bearing assertion: an UNATTRIBUTED badly
  named method in the very same class must still be reported.

  THE GRAMMAR WAS PROBED, NOT ASSUMED (tools\dumpnode), and the first
  implementation was wrong: the node is `rttiAttributes` (PLURAL, one named
  child of the declProc holding every attribute), and there is NO node type
  `attribute` in a parsed unit at all. A bare `[Test]` arrives as `identifier`;
  a parameterised `[TestCase('a','1,2')]` arrives as `exprCall`. Matching only
  identifiers would silently miss every TestCase, so both are asserted.

  ---------------------------------------------------------------- SECTION 2 --
  `unsafe-shellexecute` on CreateProcess -- the rule was UNSATISFIABLE.

  It tested only "is lpCommandLine a string literal", ignoring argument 0
  (lpApplicationName) entirely, and shipped the advice "validate or use a fixed
  literal" at severity ERROR. A fixed literal is not available to any caller
  that passes a path, so the only exit was an annotation -- and an `error` that
  is always annotated teaches people to ignore errors.

  MEASURED BEFORE THE FIX, against the shipped binary: BOTH the cmd.exe form and
  the lpApplicationName form fired, which is what confirmed the reporter's
  suspicion that their proposed rewrite would not clear the rule.

  The axis is the SHELL, not the literal:
    * lpApplicationName NON-NIL -> the program is named directly and
      lpCommandLine is argument data. Ordinary argument passing. SILENT.
    * lpApplicationName NIL     -> Windows parses the program out of the command
      line, so a runtime-built line chooses the program. REPORTED, and reported
      with the stronger message when the line names an interpreter.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_test_project_scoping"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Emit([string]$name, [string]$text) {
  [System.IO.File]::WriteAllText((Join-Path $WorkDir $name),
    (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

Emit 'uTestsFixture.pas' @'
unit uTestsFixture;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TMyTests = class
  public
    [Test]
    procedure Widget_does_the_thing;
    [Test]
    [TestCase('a','1,2')]
    procedure Other_case_here;
    [Setup]
    procedure Before_each_one;
    procedure plain_helper_bad_name;
    procedure PlainHelper;
  end;
implementation
procedure TMyTests.Widget_does_the_thing; begin end;
procedure TMyTests.Other_case_here; begin end;
procedure TMyTests.Before_each_one; begin end;
procedure TMyTests.plain_helper_bad_name; begin end;
procedure TMyTests.PlainHelper; begin end;
end.
'@

Emit 'uProcLaunch.pas' @'
unit uProcLaunch;
interface
uses Winapi.Windows, System.SysUtils;
procedure ViaShell(const ACommandLine: string);
procedure ViaAppName(const AArgs: string);
implementation

procedure ViaShell(const ACommandLine: string);
var LCmd: string; LStart: TStartupInfo; LProc: TProcessInformation;
begin
  LCmd:= 'cmd.exe /c ' + ACommandLine + ' >nul 2>&1';
  UniqueString(LCmd);
  if not CreateProcess(nil, PChar(LCmd), nil, nil, False, 0, nil, nil, LStart, LProc) then Exit;
end;

procedure ViaAppName(const AArgs: string);
var LCmd: string; LExe: string; LStart: TStartupInfo; LProc: TProcessInformation;
begin
  LExe:= 'C:\Windows\System32\icacls.exe';
  LCmd:= 'icacls ' + AArgs;
  UniqueString(LCmd);
  if not CreateProcess(PChar(LExe), PChar(LCmd), nil, nil, False, 0, nil, nil, LStart, LProc) then Exit;
end;

end.
'@

Write-Host ''
Write-Host 'run_test_project_rule_scoping -- checks whose remedy the caller could not perform' -ForegroundColor Cyan

Push-Location C:\TEMP
try {
  $naming = & $Exe lint (Join-Path $WorkDir 'uTestsFixture.pas') 2>&1 | Out-String
  $procAll = & $Exe lint (Join-Path $WorkDir 'uProcLaunch.pas')  2>&1 | Out-String
} finally { Pop-Location }

# SECTION 2 ASSERTS ON unsafe-shellexecute ONLY, and must be filtered to it.
#
# $procAll is the WHOLE report for the fixture, and the fixture necessarily
# contains an absolute path -- `LExe:= 'C:\Windows\System32\icacls.exe'` is the
# non-nil lpApplicationName the whole section exists to test. Since ruling 2
# (2026-09-02) a literal that reaches no modelled sink reports at `info` under
# hardcoded-absolute-path, and that finding QUOTES the literal. So the arm
# `-not ($proc -match 'icacls\.exe|ViaAppName')` began failing on a finding from
# an unrelated rule, while unsafe-shellexecute behaved exactly as intended.
#
# A guard that greps a whole lint report cannot survive any rule gaining a
# severity tier. Filter to the rule under test, then match.
$proc = (($procAll -split "`n") | Where-Object { $_ -match 'unsafe-shellexecute' }) -join "`n"

Write-Host ''
Write-Host 'SECTION 1 -- method-pascalcase must not fire on DUnitX test methods' -ForegroundColor Cyan
Check 'a bare [Test] method is exempt' `
  (-not ($naming -match 'Widget_does_the_thing')) `
  'the DUnitX runner prints this name; underscores are the failure report'
Check 'a [TestCase(...)] method is exempt -- it parses as exprCall, not identifier' `
  (-not ($naming -match 'Other_case_here')) `
  'RED means only bare identifier attributes are matched, so every TestCase is missed'
Check 'a [Setup] method is exempt' `
  (-not ($naming -match 'Before_each_one')) ''

Write-Host ''
Write-Host 'SECTION 1 POSITIVE CONTROL -- the rule must still work' -ForegroundColor Cyan
Check 'an UNATTRIBUTED badly-named method in the SAME class is still reported' `
  ($naming -match 'plain_helper_bad_name') `
  'RED means the exemption disabled the rule rather than scoping it -- every assertion above would then pass for the wrong reason'
Check 'and the report names it as method-pascalcase' `
  ($naming -match 'method-pascalcase') ''

Write-Host ''
Write-Host 'SECTION 2 -- unsafe-shellexecute turns on the SHELL, not on the literal' -ForegroundColor Cyan
Check 'CreateProcess with a NON-NIL lpApplicationName is silent' `
  (-not ($proc -match 'icacls\.exe|ViaAppName')) `
  'ordinary argument passing; the old rule fired here and left the caller no achievable fix'
$shellHits = ([regex]::Matches($proc, 'unsafe-shellexecute')).Count
Check 'exactly ONE unsafe-shellexecute finding remains' ($shellHits -eq 1) "got $shellHits"

Write-Host ''
Write-Host 'SECTION 2 POSITIVE CONTROL -- the real injection must still fire' -ForegroundColor Cyan
Check 'the cmd.exe form with a nil lpApplicationName is still reported' `
  ($proc -match 'unsafe-shellexecute') `
  'RED means the fix silenced the rule outright'
Check 'and the message names the interpreter and the achievable remedy' `
  ($proc -match 'command interpreter' -and $proc -match 'lpApplicationName') `
  '"validate or use a fixed literal" was advice no caller taking a path could follow'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
