# drag-lint pure .pas/.dfm sibling-pairing test (project-coherence reconcile, Task 1).
#
# PairDfmSiblings (src/core/DRagLint.Project.Members.pas) pairs each .pas path
# with its sibling .dfm (same base name, same directory) when that .dfm exists
# on disk. This test builds a tiny Win64 console harness (MembersHarness.dpr)
# that links the pure unit and exercises it against two on-disk fixtures:
# uWithForm.pas (has a sibling .dfm) and uNoForm.pas (does not).
#
# Usage: pwsh -File tests/autotest/run_members.ps1
[CmdletBinding()]
param(
    [string] $DprojDir = "$PSScriptRoot\fixtures\members",
    [string] $WorkDir  = "$env:TEMP\drag-lint-members"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# --- Build MembersHarness.dpr (Win64 Debug) via rsvars + dcc64 wrapper bat ---
# A bare .dpr (no .dproj) cannot be built by msbuild ("project file could not
# be loaded"); use the dcc64 command-line compiler that rsvars.bat puts on
# PATH. DRagLint.Project.Members is pure (System.SysUtils + System.IOUtils
# only) so the search path only needs src/core.
$rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$srcDir  = "$PSScriptRoot\..\..\src"
$searchDirs = @('core') | ForEach-Object { "$srcDir\$_" }
$uArgs   = "-U`"$($searchDirs -join ';')`""
$outDir     = "$DprojDir\Win64\Debug"
New-Item -ItemType Directory -Force $outDir | Out-Null
$batPath = "$WorkDir\build_harness.bat"
$logPath = "$WorkDir\build_harness.log"
$batLines = @(
    '@echo off'
    "call `"$rsvars`""
    "cd /d `"$DprojDir`""
    "dcc64 -CC $uArgs -E`"$outDir`" -N0`"$outDir`" MembersHarness.dpr"
    'echo BUILD_EXITCODE=%ERRORLEVEL%'
)
$batBody = ($batLines -join "`r`n")
[System.IO.File]::WriteAllText($batPath, $batBody, [System.Text.Encoding]::ASCII)

$p = Start-Process cmd.exe -ArgumentList "/c", "`"$batPath`"" `
       -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" `
       -NoNewWindow -Wait -PassThru
$log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
$buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:')
Check 'MembersHarness.dpr builds (Win64 Debug)' $buildOk (($log -split "`r?`n" | Select-Object -Last 8) -join ' | ')

$exe = "$outDir\MembersHarness.exe"
if (-not $buildOk -or -not (Test-Path $exe)) {
    Write-Host "FATAL: harness exe not found at $exe -- see $logPath" -ForegroundColor Red
    Write-Host ''
    Write-Host 'FAIL' -ForegroundColor Red
    exit 1
}

$withFormPas = "$DprojDir\uWithForm.pas"
$noFormPas   = "$DprojDir\uNoForm.pas"
$withFormDfm = "$DprojDir\uWithForm.dfm"

$out = (& $exe $withFormPas $noFormPas 2>&1 | Out-String).Trim()
$lines = @($out -split "`r?`n")
Check 'harness returns 2 lines' ($lines.Count -eq 2) "got $($lines.Count): $out"

if ($lines.Count -ge 2) {
    $l1 = $lines[0] -split '\|'
    $l2 = $lines[1] -split '\|'
    Check 'member 1 UnitPath correct' ($l1[0] -eq $withFormPas) $l1[0]
    Check 'member 1 DfmPath correct'  ($l1[1] -eq $withFormDfm) $l1[1]
    Check 'member 1 HasDfm true'      ($l1[2] -eq 'True')       $l1[2]
    Check 'member 2 UnitPath correct' ($l2[0] -eq $noFormPas)   $l2[0]
    Check 'member 2 DfmPath empty'    ([string]::IsNullOrEmpty($l2[1])) "'$($l2[1])'"
    Check 'member 2 HasDfm false'     ($l2[2] -eq 'False')      $l2[2]
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
