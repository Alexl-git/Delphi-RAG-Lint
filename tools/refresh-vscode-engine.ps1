<#
.SYNOPSIS
  Refresh the PRIVATE drag-lint engine copy that VS Code runs.

.DESCRIPTION
  WHY THIS EXISTS. A running Windows process holds an execute lock on its own
  image. The VS Code extension spawns `<serverPath> lsp --stdio` as a long-lived
  child, and in extension v1.2.2 `dragLint.serverPath` DEFAULTS to
  `third_party\dll-win64\drag-lint.exe` -- the exact file
  `build\build_draglint_win64.bat` stages into. So VS Code merely being open
  makes an engine build fail at staging, with the Delphi IDE closed and nothing
  in the message naming the holder.

  Measured 2026-08-31: PID 57928 `...\third_party\dll-win64\drag-lint.exe
  lsp --stdio`, parent `Code`. The build's own 45s kill-and-retry lost the race,
  because the client respawns eagerly.

  Extension v1.4.0 fixes this properly by running a private copy and shipping an
  "Update Engine Copy Now" command. That version is in this repo
  (`editors\vscode\drag-lint\package.json`) but is NOT what is installed, and no
  .vsix is packaged -- so this script gives v1.2.2 the same property by hand.

  THE HAZARD THIS SCRIPT EXISTS TO MANAGE, stated plainly: a private copy is a
  SECOND DEPLOYMENT, and a second deployment goes stale. A stale engine answers
  confidently with old rules, which is worse than one that fails loudly. Run this
  after any engine build whose behaviour you want VS Code to reflect.

  The Delphi IDE is NOT affected: its plugin resolves the engine beside the BPL
  in third_party\dll-win64, so release testing in RAD Studio still exercises the
  deployed build. Only VS Code reads the copy.

.PARAMETER Dest
  Where the private copy lives. Default %LOCALAPPDATA%\drag-lint-vscode-engine.
  Deliberately OUTSIDE the repo so no build, clean or git operation touches it.

.PARAMETER Kill
  Stop any engine process running out of the destination first. Without this a
  refresh hits the same execute lock it exists to avoid.
#>
[CmdletBinding()]
param(
  [string]$Source = "$PSScriptRoot\..\third_party\dll-win64",
  [string]$Dest   = "$env:LOCALAPPDATA\drag-lint-vscode-engine",
  [switch]$Kill
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Source)) { Write-Host "FATAL: source not found: $Source" -ForegroundColor Red; exit 2 }
$Source = (Resolve-Path $Source).Path
$srcExe = Join-Path $Source 'drag-lint.exe'
if (-not (Test-Path $srcExe)) { Write-Host "FATAL: no drag-lint.exe in $Source" -ForegroundColor Red; exit 2 }

if (-not (Test-Path $Dest)) { New-Item -ItemType Directory -Force $Dest | Out-Null }

# Stop only engines running FROM THE DESTINATION. Killing every drag-lint.exe
# would take out an unrelated indexing run, which is a 5-hour job to lose.
if ($Kill) {
  Get-CimInstance Win32_Process -Filter "Name='drag-lint.exe'" |
    Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($Dest, 'OrdinalIgnoreCase') } |
    ForEach-Object {
      Write-Host "  stopping PID $($_.ProcessId) ($($_.ExecutablePath))" -ForegroundColor DarkGray
      try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch {}
    }
  Start-Sleep -Milliseconds 600
}

$files = @('drag-lint.exe','drag-lint.json',
           'tree-sitter-delphi13.dll','tree-sitter-dfm.dll','tree-sitter.dll')

$copied = 0
foreach ($f in $files) {
  $s = Join-Path $Source $f
  if (-not (Test-Path $s)) { Write-Host "  WARN missing in source: $f" -ForegroundColor Yellow; continue }
  $ok = $false
  # Retry: the client can respawn between the kill above and the copy below.
  for ($i = 1; $i -le 10 -and -not $ok; $i++) {
    try { Copy-Item $s (Join-Path $Dest $f) -Force -ErrorAction Stop; $ok = $true }
    catch { Start-Sleep -Milliseconds 400 }
  }
  if ($ok) { $copied++ } else { Write-Host "  FAILED (locked): $f" -ForegroundColor Red }
}

# rules\ is not optional. An engine with an EMPTY rules directory opens cleanly
# and reports nothing, which reads as "your code is fine" -- the failure this
# repo has already hit twice under the heading "existence is not sufficiency".
$srcRules = Join-Path $Source 'rules'
$dstRules = Join-Path $Dest   'rules'
if (Test-Path $srcRules) {
  if (-not (Test-Path $dstRules)) { New-Item -ItemType Directory -Force $dstRules | Out-Null }
  Copy-Item (Join-Path $srcRules '*') $dstRules -Recurse -Force
}
$nRules = @(Get-ChildItem $dstRules -Filter *.json -ErrorAction SilentlyContinue).Count

Write-Host ''
Write-Host "private VS Code engine: $Dest" -ForegroundColor Cyan
Write-Host "  files copied : $copied of $($files.Count)"
Write-Host "  rule files   : $nRules"
if ($nRules -eq 0) { Write-Host '  ERROR: rules directory is EMPTY -- the engine would report nothing at all.' -ForegroundColor Red; exit 1 }

$v = & (Join-Path $Dest 'drag-lint.exe') --version 2>$null | Select-Object -First 1
Write-Host "  version      : $v"
Write-Host ''
Write-Host 'Set (once) in VS Code User settings:' -ForegroundColor DarkGray
Write-Host "  ""dragLint.serverPath"": ""$($Dest -replace '\\','\\')\\drag-lint.exe""" -ForegroundColor DarkGray
exit 0
