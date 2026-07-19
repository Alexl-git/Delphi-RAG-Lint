# drag-lint project-coherence delta test (project-coherence reconcile, Task 2).
#
# DRagLint.Project.Coherence (src/core/DRagLint.Project.Coherence.pas) computes,
# for a set of TProjectMember records, whether each is coherent with the DB:
# Indexed (has a files row), IndexFresh (files.mtime_unix matches the on-disk
# mtime, computed the SAME way the indexer stores it), and CompiledFresh
# (files.last_compiled_unix >= files.mtime_unix). This test builds a tiny
# Win64 console harness (CoherenceHarness.dpr) that links the real
# TSQLiteSymbolStore, seeds a temp DB with two real on-disk fixtures (reusing
# the Task 1 members fixtures uWithForm.pas / uNoForm.pas), and exercises
# ComputeCoherence/IsIncoherent against three TProjectMember cases: fully
# coherent, compile-stale (last_compiled_unix left NULL), and never-indexed
# (absent).
#
# Usage: pwsh -File tests/autotest/run_coherence.ps1
[CmdletBinding()]
param(
    [string] $FixtureDir = "$PSScriptRoot\fixtures\coherence",
    [string] $MembersDir = "$PSScriptRoot\fixtures\members",
    [string] $WorkDir    = "$env:TEMP\drag-lint-coherence"
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

# --- Build CoherenceHarness.dpr (Win64 Debug) via rsvars + dcc64 wrapper bat ---
# A bare .dpr (no .dproj) cannot be built by msbuild ("project file could not
# be loaded"); use the dcc64 command-line compiler that rsvars.bat puts on
# PATH. Needs src/core (Model, Interfaces, Project.Members, Project.Coherence)
# and src/storage (Storage.SQLite, which pulls in FireDAC -- resolved via the
# IDE's default Library Path, same as every other console harness in this repo).
$rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$srcDir  = "$PSScriptRoot\..\..\src"
$searchDirs = @('core', 'storage', 'preprocess', 'query', 'index') | ForEach-Object { "$srcDir\$_" }
$uArgs   = "-U`"$($searchDirs -join ';')`""
$outDir     = "$FixtureDir\Win64\Debug"
New-Item -ItemType Directory -Force $outDir | Out-Null
$batPath = "$WorkDir\build_harness.bat"
$logPath = "$WorkDir\build_harness.log"
$batLines = @(
    '@echo off'
    "call `"$rsvars`""
    "cd /d `"$FixtureDir`""
    "dcc64 -CC $uArgs -E`"$outDir`" -N0`"$outDir`" CoherenceHarness.dpr"
    'echo BUILD_EXITCODE=%ERRORLEVEL%'
)
$batBody = ($batLines -join "`r`n")
[System.IO.File]::WriteAllText($batPath, $batBody, [System.Text.Encoding]::ASCII)

$p = Start-Process cmd.exe -ArgumentList "/c", "`"$batPath`"" `
       -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" `
       -NoNewWindow -Wait -PassThru
$log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
$buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:')
Check 'CoherenceHarness.dpr builds (Win64 Debug)' $buildOk (($log -split "`r?`n" | Select-Object -Last 12) -join ' | ')

$exe = "$outDir\CoherenceHarness.exe"
if (-not $buildOk -or -not (Test-Path $exe)) {
    Write-Host "FATAL: harness exe not found at $exe -- see $logPath" -ForegroundColor Red
    Write-Host ''
    Write-Host 'FAIL' -ForegroundColor Red
    exit 1
}

$db              = "$WorkDir\coherence.sqlite"
$freshPas        = "$MembersDir\uWithForm.pas"
$staleCompilePas = "$MembersDir\uNoForm.pas"
$absentPas       = "$WorkDir\does-not-exist\uGhost.pas"

$out = (& $exe $db $freshPas $staleCompilePas $absentPas 2>&1 | Out-String).Trim()
$lines = @($out -split "`r?`n")
foreach ($line in $lines) {
    if ($line -match '^\s*(PASS|FAIL)\s') {
        $ok = $line -match '^\s*PASS'
        Check $line.Trim() $ok
    }
}
Check 'harness overall exit code 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE out=$out"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
