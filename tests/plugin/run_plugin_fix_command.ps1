<#
  run_plugin_fix_command.ps1 -- 1.52.2 FIXIDE: the IDE "Fix it" for a with rule names --project.

  1. Builds and runs FixCommandTests.dpr over src\delphi-plugin\DragLint.Plugin.FixCommand.pas.
  2. POSITIVE CONTROL: the same test over a stub that builds the old command (no --project, no refusal); it MUST fail.
  3. Source anchors: FixMarker and StructureForm build the command through the unit and pass the active project.
  Usage: pwsh -File tests\plugin\run_plugin_fix_command.ps1 [-SrcDir <src\delphi-plugin>]
#>
[CmdletBinding()]
param(
  [string]$SrcDir  = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-fixcmd-build-$PID"
)
if (-not $SrcDir) { $SrcDir = "$PSScriptRoot\..\..\src\delphi-plugin" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n, $d)
  if (-not $ok) { $script:Failed = $true }
}
$SrcDir = (Resolve-Path $SrcDir).Path
$Repo   = (Resolve-Path "$PSScriptRoot\..\..").Path
$Dpr    = Join-Path $Repo 'tests\FixCommandTests.dpr'
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rs)) { Write-Host "FATAL: rsvars not found: $rs" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
[void][IO.Directory]::CreateDirectory($WorkDir)

function Invoke-Test([string]$Tag, [string]$UnitDir) {
  $out = Join-Path $WorkDir $Tag
  $dcu = Join-Path $out 'dcu'
  [void][IO.Directory]::CreateDirectory($dcu)
  $bat = Join-Path $out 'build.bat'
  $lines = @('@echo off', ('call "{0}"' -f $rs), ('cd /d "{0}"' -f (Split-Path $Dpr -Parent)),
             ('dcc64 -B -Q -E"{0}" -N0"{1}" -U"{2}" FixCommandTests.dpr' -f $out, $dcu, $UnitDir),
             'echo BUILD_EXITCODE=%ERRORLEVEL%')
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  $log = Join-Path $out 'build.log'
  [void](Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log `
          -RedirectStandardError "$log.err" -NoNewWindow -Wait -PassThru)
  $b = Get-Content $log -Raw
  if ($b -notmatch 'BUILD_EXITCODE=0') { Write-Host $b; Write-Host "FATAL: $Tag compile failed" -ForegroundColor Red; exit 2 }
  $r = & { $ErrorActionPreference = 'Continue'; & (Join-Path $out 'FixCommandTests.exe') 2>&1 | ForEach-Object { "$_" } } | Out-String
  $rc = $LASTEXITCODE
  Write-Host $r.TrimEnd()
  return $rc
}

Write-Host '== 1. the unit =='
$rc = Invoke-Test 'real' $SrcDir
Check 'FixCommandTests over the real unit' ($rc -eq 0) "exit $rc"

Write-Host '== 2. positive control: the old command (no --project, no refusal) must FAIL =='
$stubDir = Join-Path $WorkDir 'stub'
[void][IO.Directory]::CreateDirectory($stubDir)
$real = [IO.File]::ReadAllText((Join-Path $SrcDir 'DragLint.Plugin.FixCommand.pas'))
$impl = $real.IndexOf("`r`nimplementation`r`n")
if ($impl -lt 0) { Write-Host 'FATAL: no implementation section' -ForegroundColor Red; exit 2 }
$stubBody = @'

implementation

uses
  System.SysUtils,
  System.StrUtils;

function FixRuleNeedsProject(const pRule: string): Boolean;
begin
  Result:= False;
end;

function FixCommandLine(const pExe, pFileName, pDb, pRule: string; pLine1: Integer; pApply: Boolean;
  const pProject: string): string;
begin
  Result:= Format('"%s" lint --in "%s" --db "%s" --fix --fix-line %d --fix-rule "%s"%s',
    [pExe, pFileName, pDb, pLine1, pRule, IfThen(pApply, ' --apply', '')]);
end;

function FixBlockedReason(const pRule, pProject: string): string;
begin
  Result:= '';
end;

end.
'@
$stub = $real.Substring(0, $impl) + ($stubBody -replace "`r?`n", "`r`n")
[IO.File]::WriteAllText((Join-Path $stubDir 'DragLint.Plugin.FixCommand.pas'), $stub, [Text.Encoding]::ASCII)
$rcStub = Invoke-Test 'stub' $stubDir
Check 'positive control: the stub (old behaviour) fails the test' ($rcStub -ne 0) "exit $rcStub"

Write-Host '== 3. source anchors =='
$fm = [IO.File]::ReadAllText((Join-Path $SrcDir 'DragLint.Plugin.Cmd.FixMarker.pas'))
$sf = [IO.File]::ReadAllText((Join-Path $SrcDir 'DragLint.Plugin.StructureForm.pas'))
$dpk = [IO.File]::ReadAllText((Join-Path $SrcDir 'dclDragLintWizard.dpk'))
Check 'FixMarker uses the unit and passes the active project' (($fm -match 'DragLint\.Plugin\.FixCommand') -and ($fm -match 'GetActiveProjectFilePath') -and ($fm -match 'FixBlockedReason\('))
Check 'StructureForm routes the with rules through the project branch' (($sf -match 'FixRuleNeedsProject\(ND\.Code\)') -and ($sf -match 'FixBlockedReason|NOT run'))
Check 'the package contains the unit' ($dpk -match "DragLint\.Plugin\.FixCommand in 'DragLint\.Plugin\.FixCommand\.pas'")

if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASSED' -ForegroundColor Green
