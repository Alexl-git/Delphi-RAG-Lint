# drag-lint plugin DB-resolution probe test ("Code Elements 0" fix).
#
# PickProjectDb (src/delphi-plugin/DRagLint.Plugin.DbProbe.pas) chooses the
# on-disk index DB for a project's own directory: the settings-template file
# (<projdir>\drag-lint.sqlite) if it exists and is non-empty, else the
# project-name file (<projdir>\<projname>.sqlite) if it exists and is
# non-empty, else ''. This test builds a tiny Win64 console harness
# (DbProbeHarness.dpr) that links the pure unit + DRagLint.Plugin.Settings
# and exercises all three cases against fixture files in a temp dir.
#
# Usage: pwsh -File tests/autotest/run_dbresolver_probe.ps1
[CmdletBinding()]
param(
    [string] $DprojDir = "$PSScriptRoot\fixtures\dbprobe",
    [string] $WorkDir  = "$env:TEMP\drag-lint-dbresolver-probe"
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

# --- Build DbProbeHarness.dpr (Win64 Debug) via rsvars + dcc64 wrapper bat ---
# A bare .dpr (no .dproj) cannot be built by msbuild ("project file could not
# be loaded"); use the dcc64 command-line compiler that rsvars.bat puts on
# PATH, pointed at the plugin source dir so it finds DRagLint.Plugin.Settings
# and DRagLint.Plugin.DbProbe.
$rsvars    = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$pluginDir = "$PSScriptRoot\..\..\src\delphi-plugin"
$outDir    = "$DprojDir\Win64\Debug"
New-Item -ItemType Directory -Force $outDir | Out-Null
$batPath = "$WorkDir\build_harness.bat"
$logPath = "$WorkDir\build_harness.log"
$batLines = @(
    '@echo off'
    "call `"$rsvars`""
    "cd /d `"$DprojDir`""
    "dcc64 -CC -U`"$pluginDir`" -E`"$outDir`" -N0`"$outDir`" DbProbeHarness.dpr"
    'echo BUILD_EXITCODE=%ERRORLEVEL%'
)
$batBody = ($batLines -join "`r`n")
[System.IO.File]::WriteAllText($batPath, $batBody, [System.Text.Encoding]::ASCII)

$p = Start-Process cmd.exe -ArgumentList "/c", "`"$batPath`"" `
       -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" `
       -NoNewWindow -Wait -PassThru
$log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
$buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:')
Check 'DbProbeHarness.dpr builds (Win64 Debug)' $buildOk (($log -split "`r?`n" | Select-Object -Last 8) -join ' | ')

$exe = "$outDir\DbProbeHarness.exe"
if (-not $buildOk -or -not (Test-Path $exe)) {
    Write-Host "FATAL: harness exe not found at $exe -- see $logPath" -ForegroundColor Red
    Write-Host ''
    Write-Host 'FAIL' -ForegroundColor Red
    exit 1
}

# --- Fixture DB files (SQLite header not required -- PickProjectDb only checks Exists+Size>0) ---
$projDir = "$WorkDir\MyProj"
New-Item -ItemType Directory $projDir | Out-Null
$projPath = "$projDir\MyProj.dproj"
Set-Content -Path $projPath -Value 'placeholder' -Encoding ascii
$template = '<projdir>\drag-lint.sqlite'
$templateFile = "$projDir\drag-lint.sqlite"
$byNameFile   = "$projDir\MyProj.sqlite"

function RunHarness([string]$ProjPath, [string]$Template) {
    (& $exe $ProjPath $Template 2>&1 | Out-String).Trim()
}

# CASE A: only <projname>.sqlite present, non-empty -> chosen over absent template file
if (Test-Path $templateFile) { Remove-Item $templateFile -Force }
if (Test-Path $byNameFile)   { Remove-Item $byNameFile -Force }
Set-Content -Path $byNameFile -Value 'nonempty' -Encoding ascii
$outA = RunHarness $projPath $template
Check 'CASE A: only <projname>.sqlite -> chosen' ($outA -like '*MyProj.sqlite') "got='$outA'"

# CASE B: both present -> template file still wins (back-compat)
Set-Content -Path $templateFile -Value 'nonempty' -Encoding ascii
$outB = RunHarness $projPath $template
Check 'CASE B: both present -> template wins' ($outB -like '*drag-lint.sqlite') "got='$outB'"

# CASE C: neither present -> '' (empty output)
Remove-Item $templateFile -Force
Remove-Item $byNameFile -Force
$outC = RunHarness $projPath $template
Check 'CASE C: neither present -> empty' ($outC -eq '') "got='$outC'"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
