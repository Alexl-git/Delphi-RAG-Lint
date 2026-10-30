<#
  run_preprocess_compiler_version.ps1 -- the index preprocesses for the Delphi
  the environment names, and {$IF CompilerVersion ...} is evaluated at all.

  THE PROBLEMS (evaluation on ProjectA, a Delphi 10.3 project, 2026-09-28):
    * the built-in defines were pinned to Delphi 13 -- VER370,
      compiler_version_37 -- whatever the project is built with, so a
      {$IFDEF VER330} branch of 10.3 code was never indexed;
    * CompilerVersion and RTLVersion were never given a VALUE. The evaluator
      reads an unknown identifier as False, so EVERY {$IF CompilerVersion >= N}
      took its ELSE branch, on every compiler.

  THE FIX (extractor 1.27.0-alpha). The CLI derives the target CompilerVersion
  from the RAD Studio root it resolves ($BDS first): ...\Studio\20.0 -> 33,
  ...\Studio\37.0 -> 37. The built-ins say VER<N>0 / compiler_version_<N>, and
  every profile carries CompilerVersion and RTLVersion as numbers. A non-default
  version joins the indexer fingerprint (`cv=`), so switching compilers
  re-parses.

  $BDS is set explicitly per run -- TStudioEnv reads it without an existence
  check, so the fake roots below are enough.

  Usage: pwsh -File tests/autotest/run_preprocess_compiler_version.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-compiler-version-$PID"
)
$savedBds = $env:BDS
try {
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
New-Item -ItemType Directory (Join-Path $WorkDir 'src') | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Ascii (Join-Path $WorkDir 'src\uCv.pas') @'
unit uCv;

interface

{$IF CompilerVersion >= 30}
procedure ModernApi;
{$ELSE}
procedure AncientApi;
{$IFEND}
{$IFDEF VER330}
procedure RioOnly;
{$ENDIF}
{$IFDEF VER370}
procedure FlorenceOnly;
{$ENDIF}

implementation

end.
'@

function IndexWith([string]$Bds, [string]$Name, [string[]]$Extra = @()) {
  $env:BDS = $Bds
  $db = Join-Path $WorkDir "$Name.sqlite"
  & $Exe index (Join-Path $WorkDir 'src') --db $db --quiet @Extra 2>&1 | Out-Null
  $code = $LASTEXITCODE
  $has = @{}
  foreach ($n in @('ModernApi', 'AncientApi', 'RioOnly', 'FlorenceOnly')) {
    & $Exe query --name $n --db $db --exact 2>&1 | Out-Null
    $has[$n] = ($LASTEXITCODE -eq 0)
  }
  return @{ Code = $code; Has = $has; Db = $db }
}

Write-Host 'BDS = ...\Studio\20.0 (Delphi 10.3)' -ForegroundColor Cyan
$rio = IndexWith 'C:\FakeEmbarcadero\Studio\20.0' 'rio'
Check 'index exits 0' ($rio.Code -eq 0) "exit=$($rio.Code)"
Check 'ASSERT: {$IF CompilerVersion >= 30} takes the THEN branch (ModernApi)' $rio.Has.ModernApi ''
Check 'ASSERT: ... and not the ELSE branch (AncientApi absent)' (-not $rio.Has.AncientApi) ''
Check 'ASSERT: VER330 is defined for a 10.3 root (RioOnly)' $rio.Has.RioOnly ''
Check 'ASSERT: VER370 is NOT defined for a 10.3 root (FlorenceOnly absent)' (-not $rio.Has.FlorenceOnly) ''

Write-Host ''
Write-Host 'BDS = ...\Studio\37.0 (Delphi 13)' -ForegroundColor Cyan
$flo = IndexWith 'C:\FakeEmbarcadero\Studio\37.0' 'florence'
Check 'index exits 0' ($flo.Code -eq 0) "exit=$($flo.Code)"
Check 'ASSERT: CompilerVersion is 37 -> ModernApi' ($flo.Has.ModernApi -and -not $flo.Has.AncientApi) ''
Check 'ASSERT: VER370, not VER330, for a 13 root' ($flo.Has.FlorenceOnly -and -not $flo.Has.RioOnly) ''

Write-Host ''
Write-Host 'BDS = ...\Studio\37.0 (Delphi 13 installed) + --target-compiler 10.3' -ForegroundColor Cyan
# x139: the explicit target beats the installed Delphi -- a 10.3 project indexed
# on a Delphi 13 box must still see VER330 / CompilerVersion 33.
$tc = IndexWith 'C:\FakeEmbarcadero\Studio\37.0' 'target103' @('--target-compiler', '10.3')
Check 'index exits 0' ($tc.Code -eq 0) "exit=$($tc.Code)"
Check 'ASSERT: --target-compiler 10.3 defines VER330 on a 13 box (RioOnly)' $tc.Has.RioOnly ''
Check 'ASSERT: ... and not VER370 (FlorenceOnly absent)' (-not $tc.Has.FlorenceOnly) ''
Check 'ASSERT: CompilerVersion 33 >= 30 -> ModernApi' ($tc.Has.ModernApi -and -not $tc.Has.AncientApi) ''
Write-Host ''
Write-Host 'fingerprint' -ForegroundColor Cyan
$py = Join-Path $WorkDir 'fp.py'
Write-Ascii $py @'
import sqlite3, sys
print(sqlite3.connect(sys.argv[1]).execute("select value from schema_meta where key='indexer_fingerprint'").fetchone()[0])
'@
$fpRio = ((python $py $rio.Db) -join '').Trim()
$fpFlo = ((python $py $flo.Db) -join '').Trim()
Check 'ASSERT: a 10.3 index is stamped cv=33' ($fpRio -match ';cv=33$') $fpRio
Check 'CONTROL: a Delphi 13 index keeps the stamp it always had (no cv= limb)' ($fpFlo -notmatch 'cv=') $fpFlo
$fpTc = ((python $py $tc.Db) -join '').Trim()
Check 'ASSERT: a --target-compiler 10.3 index is stamped cv=33' ($fpTc -match ';cv=33$') $fpTc

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
} finally {
  $env:BDS = $savedBds
  foreach ($d in @("$env:TEMP\drag-lint-compiler-version-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
