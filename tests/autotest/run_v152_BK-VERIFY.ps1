<#
  run_v152_BK-VERIFY.ps1 -- lane v152 BK-VERIFY (battery blockers on the int tip, B05, U8).

  A  The rename test seam (DRAGLINT_RENAME_TEST_UNGATED=1) covers a fixture under the SYSTEM temp folder
     ([IO.Path]::GetTempPath(), which Windows reads from %TMP% first), not only C:\TEMP and %TEMP%.
     Before 1.52 BK-VERIFY, with %TEMP% = C:\TEMP and %TMP% = %LOCALAPPDATA%\Temp, a naming fix of a fixture
     built under GetTempPath() was refused [no-library] (run_const_casing_word_fix.ps1 failed that way).
       A0  premise: the fixture folder is outside C:\TEMP and outside %TEMP% (else the check is vacuous)
       A1  with the seam: the const-casing naming fix is written (declaration and use)
       A2  positive control: WITHOUT the seam the same fix is refused [no-library] and nothing is written
  B  The same seam lifts BK-GATE B23's no-project refusal of an indexed fix (the seam's guards have no .dproj):
       B2  control: seam OFF, an indexed redundant-as-tobject fix in a folder with no project is REFUSED (no-project)
       B1  seam ON: the same fix is written (Take(P);) -- RED before 1.52 BK-VERIFY (B23 ignored the seam)

  Usage: pwsh -File tests\autotest\run_v152_BK-VERIFY.ps1 [-Exe path\to\drag-lint.exe]
#>
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  [PASS] $Name" -ForegroundColor Green }
  else { Write-Host "  [FAIL] $Name $Detail" -ForegroundColor Red; $script:Fail++ }
}
$Exe = (Resolve-Path $Exe).Path
$Ascii = [Text.Encoding]::ASCII

Write-Host '== A: rename test seam under the system temp folder (%TMP%) ==' -ForegroundColor Cyan
$SavedTemp = $env:TEMP; $SavedTmp = $env:TMP; $SavedSeam = $env:DRAGLINT_RENAME_TEST_UNGATED
$TmpRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Temp'
$env:TEMP = 'C:\TEMP'
$env:TMP = $TmpRoot
$work = Join-Path $TmpRoot ('dl-bkverify-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
  Check 'A0 premise: fixture outside C:\TEMP and %TEMP%' (-not $work.StartsWith('C:\TEMP\', [StringComparison]::OrdinalIgnoreCase)) $work
  $Unit = @'
unit uSeamTmp;

interface

const
  StationType_Operator = 1;

function Total: Integer;

implementation

function Total: Integer;
begin
  Result:= StationType_Operator;
end;

end.
'@
  $u = Join-Path $work 'uSeamTmp.pas'
  $dpr = Join-Path $work 'SeamTmp.dpr'
  $db = Join-Path $work 's.sqlite'
  function Reset-Fixture {
    [IO.File]::WriteAllText($u, (($Unit -replace "`r`n", "`n") -replace "`n", "`r`n"), $Ascii)
    [IO.File]::WriteAllText($dpr, "program SeamTmp;`r`nuses`r`n  uSeamTmp in 'uSeamTmp.pas';`r`nbegin`r`nend.`r`n", $Ascii)
    if (Test-Path $db) { [IO.File]::Delete($db) }
    & { $ErrorActionPreference = 'Continue'; & $Exe index --project $dpr --db $db --library-db none 2>&1 | ForEach-Object { "$_" } } | Out-Null
  }
  function Fix-Line6 {
    (& { $ErrorActionPreference = 'Continue'; & $Exe lint --file $u --db $db --library-db none --fix --fix-line 6 --fix-rule const-casing --apply --no-compile-gate 2>&1 | ForEach-Object { "$_" } } | Out-String)
  }

  # A2 first: the positive control (no seam -> refused, file untouched). --library-db none on index and fix:
  # since 1.52 a missing --library-db falls back to the manifest platform library, which on a dev box exists
  # and lifts [no-library] -- the fixture must not depend on (or read) the machine's real library.
  Reset-Fixture
  $env:DRAGLINT_RENAME_TEST_UNGATED = $null
  $o = Fix-Line6
  $t = [IO.File]::ReadAllText($u)
  Check 'A2 control: without the seam the naming fix is refused [no-library], nothing written' `
    (($o -match 'refused \[no-library\]') -and ($t -cmatch 'StationType_Operator = 1;')) $o

  Reset-Fixture
  $env:DRAGLINT_RENAME_TEST_UNGATED = '1'
  $o = Fix-Line6
  $t = [IO.File]::ReadAllText($u)
  Check 'A1 with the seam under %TMP%: StationTypeOperator written at declaration and use' `
    (($t -cmatch '(?m)^\s*StationTypeOperator = 1;') -and ($t -cmatch 'Result:= StationTypeOperator;') -and ($t -cnotmatch 'StationType_Operator')) $o
} finally {
  $env:TEMP = $SavedTemp; $env:TMP = $SavedTmp; $env:DRAGLINT_RENAME_TEST_UNGATED = $SavedSeam
  if (Test-Path $work) { [IO.Directory]::Delete($work, $true) }
}

Write-Host '== B: the seam lifts the B23 no-project refusal ==' -ForegroundColor Cyan
$FxUnit = (Resolve-Path "$PSScriptRoot\..\fixtures\refactor\gatefix\GfUnit.pas").Path
$workB = Join-Path 'C:\TEMP' ('dl-bkverify-b-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $workB | Out-Null
try {
  $ub = Join-Path $workB 'GfUnit.pas'; $dbB = Join-Path $workB 'b.sqlite'
  function Fix-B {
    [IO.File]::Copy($FxUnit, $ub, $true)
    if (Test-Path $dbB) { [IO.File]::Delete($dbB) }
    & { $ErrorActionPreference = 'Continue'; & $Exe index $workB --db $dbB 2>&1 | ForEach-Object { "$_" } } | Out-Null
    $o = (& { $ErrorActionPreference = 'Continue'; & $Exe lint --in $ub --db $dbB --enable redundant-as-tobject --fix --fix-rule redundant-as-tobject --fix-line 27 --apply --no-backup 2>&1 | ForEach-Object { "$_" } } | Out-String)
    return @{ Code = $LASTEXITCODE; Out = $o; Line = ([IO.File]::ReadAllLines($ub)[26].Trim()) }
  }
  $env:DRAGLINT_RENAME_TEST_UNGATED = $null
  $r = Fix-B
  Check 'B2 control: seam OFF -> REFUSED (no-project), line 27 untouched' (($r.Out -match 'REFUSED \(no-project\)') -and ($r.Line -eq 'Take(P as TObject);')) "exit $($r.Code) line=$($r.Line) $($r.Out)"
  $env:DRAGLINT_RENAME_TEST_UNGATED = '1'
  $r = Fix-B
  Check 'B1 seam ON -> written (Take(P);), exit 0' (($r.Code -eq 0) -and ($r.Line -eq 'Take(P);')) "exit $($r.Code) line=$($r.Line) $($r.Out)"
} finally {
  $env:DRAGLINT_RENAME_TEST_UNGATED = $SavedSeam
  if (Test-Path $workB) { [IO.Directory]::Delete($workB, $true) }
}

Write-Host ''
if ($script:Fail -gt 0) { Write-Host "run_v152_BK-VERIFY: $($script:Fail) FAILED" -ForegroundColor Red; exit 1 }
Write-Host 'run_v152_BK-VERIFY: all passed' -ForegroundColor Green
exit 0
