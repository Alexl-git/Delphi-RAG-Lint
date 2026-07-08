# drag-lint TTextEditApplier same-line column-DESC tiebreak test.
#
# TTextEditApplier.Apply (src/refactor/DRagLint.Refactor.TextEdit.pas) sorts
# edits back-to-front by line before applying them, so an edit above another
# doesn't invalidate the other's stored line/column offsets. Before this fix,
# two tekReplaceInLine edits on the SAME line compared equal (line-only sort),
# so TList.Sort left them in input order; applying the left-hand edit first
# shifted the line and corrupted the right-hand edit's stored columns. This
# test builds a tiny Win64 console harness (SameLineHarness.dpr) that links
# the pure unit and applies two same-line, differing-length replace edits.
#
# Usage: pwsh -File tests/autotest/run_textedit_sameline.ps1
[CmdletBinding()]
param(
    [string] $DprojDir = "$PSScriptRoot\fixtures\textedit",
    [string] $WorkDir  = "$env:TEMP\drag-lint-textedit-sameline"
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

# --- Build SameLineHarness.dpr (Win64 Debug) via rsvars + dcc64 wrapper bat ---
# A bare .dpr (no .dproj) cannot be built by msbuild ("project file could not
# be loaded"); use the dcc64 command-line compiler that rsvars.bat puts on
# PATH. DRagLint.Refactor.TextEdit uses DRagLint.Core.Model and
# DRagLint.Core.Interfaces (which in turn uses DRagLint.Preprocess.Types) --
# all pure units, no TreeSitter -- so the search path only needs src/core,
# src/refactor, src/preprocess. Pass -NS"System" to match the real .dproj's
# <DCC_Namespace>System;...</DCC_Namespace> so bare RTL unit names resolve.
$rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$srcDir  = "$PSScriptRoot\..\..\src"
$searchDirs = @('core','refactor','preprocess') | ForEach-Object { "$srcDir\$_" }
$uArgs   = "-U`"$($searchDirs -join ';')`" -NS`"System`""
$outDir     = "$DprojDir\Win64\Debug"
New-Item -ItemType Directory -Force $outDir | Out-Null
$batPath = "$WorkDir\build_harness.bat"
$logPath = "$WorkDir\build_harness.log"
$batLines = @(
    '@echo off'
    "call `"$rsvars`""
    "cd /d `"$DprojDir`""
    "dcc64 -CC $uArgs -E`"$outDir`" -N0`"$outDir`" SameLineHarness.dpr"
    'echo BUILD_EXITCODE=%ERRORLEVEL%'
)
$batBody = ($batLines -join "`r`n")
[System.IO.File]::WriteAllText($batPath, $batBody, [System.Text.Encoding]::ASCII)

$p = Start-Process cmd.exe -ArgumentList "/c", "`"$batPath`"" `
       -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" `
       -NoNewWindow -Wait -PassThru
$log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
$buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:')
Check 'SameLineHarness.dpr builds (Win64 Debug)' $buildOk (($log -split "`r?`n" | Select-Object -Last 8) -join ' | ')

$exe = "$outDir\SameLineHarness.exe"
if (-not $buildOk -or -not (Test-Path $exe)) {
    Write-Host "FATAL: harness exe not found at $exe -- see $logPath" -ForegroundColor Red
    Write-Host ''
    Write-Host 'FAIL' -ForegroundColor Red
    exit 1
}

$got = (& $exe 2>&1 | Out-String).Trim()
$expect = 'FIRST := X;'
Check 'Same-line edits apply back-to-front (right edit first)' ($got -eq $expect) "got='$got' expect='$expect'"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
