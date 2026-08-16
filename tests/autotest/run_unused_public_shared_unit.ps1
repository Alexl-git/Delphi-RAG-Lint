# Guard: unused-public-symbol must not call a SHARED unit's API dead.
#
# docs\INBOX-unused-public-symbol-lies-on-shared-units.md.
#
# IsReferenced asks ONE project's index. YADF/YADFOT/YADFSetup are three projects
# over one source folder, so a routine defined in a shared unit and called only
# from a sibling is unreferenced HERE and very much alive. Measured 2026-08-16:
# 5 of 6 YADF findings were false that way (SaveOptionsToIni alone has 10 caller
# refs in sibling DBs).
#
# The rule does NOT suppress on shared units, and that is the point worth
# guarding: the one genuine finding in that set lived in the SAME shared unit as
# the false ones, so skipping shared units would have swapped a false positive
# for a false negative in one file. The finding stands; the message carries the
# caveat and names the siblings from the unit's own dl:shared header; severity
# drops to hint so an unanswerable question cannot block a true-zero run.
#
# BOTH BRANCHES ARE ASSERTED. Checking only the shared case would pass against a
# build that rewrote every unused-public-symbol message unconditionally.
#
# Usage: pwsh -File tests/autotest/run_unused_public_shared_unit.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-unused-public-shared"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null

# uShared: header declares TWO owning projects -> the index cannot prove dead.
# uSolo:   no dl:shared header -> the single-project answer IS authoritative.
# Both export exactly one unreferenced routine, so the ONLY difference between
# the two findings is the shared-unit caveat.
$files = @{
  'uShared.pas' = @'
unit uShared;   // dl:shared AlphaProj, BetaProj
interface
procedure SharedOrphan;
implementation
procedure SharedOrphan;
begin
end;
end.
'@
  'uSolo.pas' = @'
unit uSolo;
interface
procedure SoloOrphan;
implementation
procedure SoloOrphan;
begin
end;
end.
'@
  'AlphaProj.dpr' = @'
program AlphaProj;
uses uShared in 'uShared.pas', uSolo in 'uSolo.pas';
begin
end.
'@
  'AlphaProj.dproj' = '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><PropertyGroup><MainSource>AlphaProj.dpr</MainSource></PropertyGroup><ItemGroup><DCCReference Include="uShared.pas"/><DCCReference Include="uSolo.pas"/></ItemGroup></Project>'
}
foreach ($k in $files.Keys) {
  [System.IO.File]::WriteAllText((Join-Path $WorkDir $k), (($files[$k] -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII)
}

$db = Join-Path $WorkDir 'fx.sqlite'
& $Exe index $WorkDir --db $db 2>&1 | Out-Null
Check 'index exits 0' ($LASTEXITCODE -eq 0)
$out = & $Exe lint-all --project (Join-Path $WorkDir 'AlphaProj.dproj') --db $db 2>&1 | Out-String

$shared = ($out -split "`n" | Where-Object { $_ -match 'SharedOrphan' }) -join ' '
$solo   = ($out -split "`n" | Where-Object { $_ -match 'SoloOrphan'   }) -join ' '
Write-Host ("  shared: {0}" -f $shared.Trim()) -ForegroundColor DarkGray
Write-Host ("  solo  : {0}" -f $solo.Trim())   -ForegroundColor DarkGray

# PRECONDITION -- both routines must actually be reported, or every arm below is
# vacuous. The rule fires only on unreferenced exported unit-level routines.
Check 'the SHARED unit orphan is still reported (not suppressed)' ($shared -ne '')
Check 'the SOLO unit orphan is reported'                          ($solo   -ne '')

# THE FIX -- shared unit: caveated wording, siblings named, severity hint.
Check 'shared: does NOT claim "possible dead public API"' (-not ($shared -match 'possible dead public API'))
Check 'shared: says it is not referenced WITHIN THIS PROJECT' ($shared -match 'not referenced within this project')
Check 'shared: names the sibling projects from the dl:shared header' `
    (($shared -match 'AlphaProj') -and ($shared -match 'BetaProj'))
Check 'shared: severity downgraded to hint' ($shared -match '\[hint\]')

# POSITIVE CONTROL -- a NON-shared unit must keep the original wording and
# severity. Without this arm, a build that rewrote every message unconditionally
# would pass everything above.
Check 'solo: KEEPS the original "possible dead public API" wording' ($solo -match 'possible dead public API')
Check 'solo: severity stays info'                                   ($solo -match '\[info\]')
Check 'solo: carries no shared-unit caveat' (-not ($solo -match 'not referenced within this project'))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
