# drag-lint pure name-recasing synthesizer test (naming autofix, phase 1).
#
# SynthesizeCasedName (src/refactor/DRagLint.Refactor.NamingFix.pas) re-cases
# an identifier to a target TNameStyle WITHOUT changing its letters or
# inserting separators. StyleFromConfigText maps the TNamingConfig textual
# vocabulary ('PascalCase' | 'camelCase' | 'UPPER_CASE') to TNameStyle. This
# test builds a tiny Win64 console harness (NameSynthHarness.dpr) that links
# the pure unit and exercises the brief's test-case table.
#
# Usage: pwsh -File tests/autotest/run_naming_synth.ps1
[CmdletBinding()]
param(
    [string] $DprojDir = "$PSScriptRoot\fixtures\namesynth",
    [string] $WorkDir  = "$env:TEMP\drag-lint-naming-synth"
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

# --- Build NameSynthHarness.dpr (Win64 Debug) via rsvars + dcc64 wrapper bat ---
# A bare .dpr (no .dproj) cannot be built by msbuild ("project file could not
# be loaded"); use the dcc64 command-line compiler that rsvars.bat puts on
# PATH. DRagLint.Refactor.NamingFix's implementation section uses
# DRagLint.Refactor.Rename (for the rename engine), which in turn uses
# TreeSitter -- so the full CLI dproj search path (incl. third_party
# delphi-tree-sitter) IS genuinely needed here, not optional. TreeSitter.pas
# has a bare `uses SysUtils` (not `System.SysUtils`); the real .dproj resolves
# that via <DCC_Namespace>System;...</DCC_Namespace>, which the CLI compiler's
# defaults don't include -- pass -NS"System" to match, or the bare `SysUtils`
# reference fails to resolve even though the RTL itself is on the path.
$rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$srcDir  = "$PSScriptRoot\..\..\src"
$searchDirs = @(
    'preprocess','core','context','diagnostics','doc','forms','index','lint',
    'lsp','mcp','output','parser','project','query','refactor','report',
    'resolver','sql','storage','workspace','analysis'
) | ForEach-Object { "$srcDir\$_" }
$searchDirs += "$PSScriptRoot\..\..\third_party\delphi-tree-sitter"
$uArgs   = "-U`"$($searchDirs -join ';')`" -NS`"System`""
$outDir     = "$DprojDir\Win64\Debug"
New-Item -ItemType Directory -Force $outDir | Out-Null
$batPath = "$WorkDir\build_harness.bat"
$logPath = "$WorkDir\build_harness.log"
$batLines = @(
    '@echo off'
    "call `"$rsvars`""
    "cd /d `"$DprojDir`""
    "dcc64 -CC $uArgs -E`"$outDir`" -N0`"$outDir`" NameSynthHarness.dpr"
    'echo BUILD_EXITCODE=%ERRORLEVEL%'
)
$batBody = ($batLines -join "`r`n")
[System.IO.File]::WriteAllText($batPath, $batBody, [System.Text.Encoding]::ASCII)

$p = Start-Process cmd.exe -ArgumentList "/c", "`"$batPath`"" `
       -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" `
       -NoNewWindow -Wait -PassThru
$log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
$buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:')
Check 'NameSynthHarness.dpr builds (Win64 Debug)' $buildOk (($log -split "`r?`n" | Select-Object -Last 8) -join ' | ')

$exe = "$outDir\NameSynthHarness.exe"
if (-not $buildOk -or -not (Test-Path $exe)) {
    Write-Host "FATAL: harness exe not found at $exe -- see $logPath" -ForegroundColor Red
    Write-Host ''
    Write-Host 'FAIL' -ForegroundColor Red
    exit 1
}

# DRagLint.Refactor.Rename (pulled in transitively via NamingFix's
# implementation uses) links TreeSitterLib, which loads tree-sitter*.dll at
# runtime -- copy the matching Win64 Debug DLLs next to the harness exe (same
# ones the real CLI build produces in src/cli/Win64/Debug) or the harness
# fails at process load with "cannot open shared object file", not a Pascal
# error.
$dllSrcDir = "$PSScriptRoot\..\..\src\cli\Win64\Debug"
foreach ($dll in @('tree-sitter.dll','tree-sitter-delphi13.dll','tree-sitter-dfm.dll')) {
    $src = Join-Path $dllSrcDir $dll
    if (Test-Path $src) { Copy-Item $src -Destination $outDir -Force }
}

function RunHarness([string]$OldName, [string]$ConfigCase) {
    (& $exe $OldName $ConfigCase 2>&1 | Out-String).Trim()
}

# Test-case table (from the Task 5 brief, Step 1)
$cases = @(
    @{ Name = 'doThing PascalCase -> DoThing';               Old = 'doThing';  Style = 'PascalCase'; Expect = 'DoThing' }
    @{ Name = 'DoThing PascalCase -> DoThing (idempotent)';   Old = 'DoThing';  Style = 'PascalCase'; Expect = 'DoThing' }
    @{ Name = 'MyValue camelCase -> myValue';                 Old = 'MyValue';  Style = 'camelCase';  Expect = 'myValue' }
    @{ Name = 'maxCount UPPER_CASE -> MAXCOUNT (pure recase)';Old = 'maxCount'; Style = 'UPPER_CASE'; Expect = 'MAXCOUNT' }
    @{ Name = 'X PascalCase -> X (single-char)';               Old = 'X';        Style = 'PascalCase'; Expect = 'X' }
)

foreach ($c in $cases) {
    $got = RunHarness $c.Old $c.Style
    Check $c.Name ($got -eq $c.Expect) "got='$got' expect='$($c.Expect)'"
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
