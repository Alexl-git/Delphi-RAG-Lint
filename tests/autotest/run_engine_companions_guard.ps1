#Requires -Version 7
<#
  run_engine_companions_guard.ps1 -- pins lib\EngineCompanions.ps1 (Initialize-EngineCompanions).

  A fake repo (rules\, third_party\dll-win64\, docs\examples\convrules\, src\cli\Win64\Debug\ with
  a STALE rules\ copy, plus a decoy exe elsewhere) proves, in a scratch folder only:
    A  a build-output exe gets the tree-sitter dll, casts.castlib, sqlite3.dll and a rules\ mirror
       that equals the source set exactly (a changed file refreshed, an ORPHAN .scm removed).
    B  POSITIVE CONTROL: before the call the stale copy differs from the source (so A is not vacuous).
    C  NEGATIVE CONTROL: an exe that is NOT <Repo>\src\cli\Win64\Debug\drag-lint.exe (e.g. the
       deployed dll-win64 one) returns $false and its neighbours are not touched.
    D  a second call is a no-op (idempotent: returns $true, same file set).
#>
[CmdletBinding()]
param([string]$WorkDir = "$env:TEMP\drag-lint-engcomp-$PID")
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
. (Join-Path $PSScriptRoot 'lib\EngineCompanions.ps1')
try {
  [void](New-Item -ItemType Directory -Force -Path $WorkDir)
  $r = Join-Path $WorkDir 'repo'
  $dirs = 'rules', 'third_party\dll-win64', 'docs\examples\convrules', 'src\cli\Win64\Debug\rules'
  foreach ($d in $dirs) { [void](New-Item -ItemType Directory -Force -Path (Join-Path $r $d)) }
  Set-Content (Join-Path $r 'rules\a.scm') 'new-a' -Encoding ascii
  Set-Content (Join-Path $r 'rules\b.json') '{}' -Encoding ascii
  Set-Content (Join-Path $r 'third_party\dll-win64\tree-sitter-x.dll') 'dll' -Encoding ascii
  Set-Content (Join-Path $r 'docs\examples\convrules\casts.castlib') 'cast' -Encoding ascii
  $sq = Join-Path $WorkDir 'sqlite3.dll'; Set-Content $sq 'sq' -Encoding ascii
  $buildExe = Join-Path $r 'src\cli\Win64\Debug\drag-lint.exe'; Set-Content $buildExe 'exe' -Encoding ascii
  Set-Content (Join-Path $r 'src\cli\Win64\Debug\rules\a.scm') 'stale-a-longer' -Encoding ascii
  Set-Content (Join-Path $r 'src\cli\Win64\Debug\rules\orphan.scm') 'orphan' -Encoding ascii
  $decoy = Join-Path $r 'third_party\dll-win64\drag-lint.exe'; Set-Content $decoy 'exe' -Encoding ascii

  Check 'B control: stale copy differs from source before the call' ((Get-Content (Join-Path $r 'src\cli\Win64\Debug\rules\a.scm') -Raw).Trim() -ne 'new-a')
  $rc = Initialize-EngineCompanions -Exe $decoy -Repo $r -SqliteSrc $sq
  Check 'C decoy exe (not the build output) -> $false' ($rc -eq $false)
  Check 'C decoy neighbours untouched' (-not (Test-Path (Join-Path $r 'third_party\dll-win64\sqlite3.dll')) -and -not (Test-Path (Join-Path $r 'third_party\dll-win64\rules')))

  $rc = Initialize-EngineCompanions -Exe $buildExe -Repo $r -SqliteSrc $sq
  $ed = Join-Path $r 'src\cli\Win64\Debug'
  Check 'A build-output exe -> $true' ($rc -eq $true)
  Check 'A tree-sitter dll staged' (Test-Path (Join-Path $ed 'tree-sitter-x.dll'))
  Check 'A casts.castlib staged' (Test-Path (Join-Path $ed 'casts.castlib'))
  Check 'A sqlite3.dll staged' (Test-Path (Join-Path $ed 'sqlite3.dll'))
  Check 'A changed rule refreshed' ((Get-Content (Join-Path $ed 'rules\a.scm') -Raw).Trim() -eq 'new-a')
  Check 'A orphan rule removed' (-not (Test-Path (Join-Path $ed 'rules\orphan.scm')))
  $got = (Get-ChildItem (Join-Path $ed 'rules') | ForEach-Object Name | Sort-Object) -join ','
  Check 'A rules mirror equals source set' ($got -eq 'a.scm,b.json') $got
  $rc2 = Initialize-EngineCompanions -Exe $buildExe -Repo $r -SqliteSrc $sq
  Check 'D second call is idempotent' ($rc2 -eq $true -and ((Get-ChildItem (Join-Path $ed 'rules') | ForEach-Object Name | Sort-Object) -join ',') -eq 'a.scm,b.json')
}
finally {
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($script:Failed) { Write-Host 'ENGINE COMPANIONS GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ENGINE COMPANIONS GUARD: PASS' -ForegroundColor Green
