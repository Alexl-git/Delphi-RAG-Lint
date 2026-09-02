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
  # DEFAULTS TO THE PATH THE INSTALLED EXTENSION ACTUALLY RUNS FROM.
  # It used to default to %LOCALAPPDATA%\drag-lint-vscode-engine, which on
  # 2026-09-02 was a THIRD copy nobody read: the two live engine processes were
  # running from globalStorage, and the LOCALAPPDATA copy was two days stale and
  # referenced by nothing. Refreshing a directory no client reads, and reporting
  # success for it, is the same defect as the version line below.
  [string]$Dest   = "$env:APPDATA\Code\User\globalStorage\drag-lint.drag-lint\engine",
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

function Sha16($p) {
  if (-not (Test-Path $p)) { return '(absent)' }
  try { return (Get-FileHash $p -Algorithm SHA256).Hash.Substring(0,16).ToLower() } catch { return '(unreadable)' }
}

$copied  = 0
$failed  = @()
$missing = @()

# RETRY BUDGET, and 10 attempts was not one. The VS Code client respawns its
# engine eagerly, so the copy races the respawn -- the same race
# build_draglint_win64.bat fights, and on 2026-09-02 that build reported
# "staged after recovery (153 attempt(s))". Ten tries at 400ms gave up after
# four seconds and the refresh silently did nothing.
$deadline = (Get-Date).AddSeconds(45)

foreach ($f in $files) {
  $s = Join-Path $Source $f
  $d = Join-Path $Dest   $f
  if (-not (Test-Path $s)) { Write-Host "  WARN missing in source: $f" -ForegroundColor Yellow; $missing += $f; continue }
  $ok = $false
  do {
    try { Copy-Item $s $d -Force -ErrorAction Stop; $ok = $true }
    catch { Start-Sleep -Milliseconds 250 }
  } while ((-not $ok) -and ((Get-Date) -lt $deadline))

  # VERIFY BY CONTENT. A successful Copy-Item is not proof the destination now
  # matches: a partial write, or a copy that silently landed elsewhere, both
  # look like success. Compare hashes and say so.
  if ($ok) {
    $hs = Sha16 $s; $hd = Sha16 $d
    if ($hs -ne $hd) { $ok = $false; Write-Host "  FAILED (content mismatch after copy): $f  src=$hs dst=$hd" -ForegroundColor Red }
  }

  if ($ok) { $copied++ } else { $failed += $f; Write-Host "  FAILED (locked): $f" -ForegroundColor Red }
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

# THE VERSION LINE IS PRINTED ONLY ON A REFRESH THAT ACTUALLY HAPPENED, and the
# hash is printed beside it.
#
# `--version` is read from the DESTINATION. When the copy failed that is the
# STALE engine reporting its own version -- and because a product version moves
# far less often than the binary does, it prints exactly what a successful
# refresh would print. On 2026-09-02 this script copied 1 of 5 files, failed on
# drag-lint.exe itself, printed "version : drag-lint 1.9.0-alpha", and exited 0.
# The one field a reader would check was guaranteed to look right.
#
# The sha256 prefix is the fix for that, suggested by the YADF session after it
# identified three engine copies on one machine -- 34,021,745 / 33,972,632 /
# 33,862,113 bytes, three distinct builds, ALL reporting "1.9.0-alpha". A
# version string cannot tell those apart; sixteen hex characters can.
if ($failed.Count -gt 0) {
  Write-Host ''
  Write-Host "  REFRESH FAILED -- $($failed.Count) file(s) could not be replaced: $($failed -join ', ')" -ForegroundColor Red
  Write-Host '  The destination still holds the OLD engine. No version is reported, because' -ForegroundColor Red
  Write-Host '  it would be the old one and would look like success.' -ForegroundColor Red
  Write-Host "  src drag-lint.exe : $(Sha16 (Join-Path $Source 'drag-lint.exe'))" -ForegroundColor DarkGray
  Write-Host "  dst drag-lint.exe : $(Sha16 (Join-Path $Dest   'drag-lint.exe'))" -ForegroundColor DarkGray
  Write-Host '  Close VS Code (or run its "Update Engine Copy Now" command) and retry.' -ForegroundColor Yellow
  exit 1
}

$v = & (Join-Path $Dest 'drag-lint.exe') --version 2>$null | Select-Object -First 1
Write-Host "  version      : $v"
Write-Host "  sha256       : $(Sha16 (Join-Path $Dest 'drag-lint.exe'))  (matches source)"
Write-Host ''
Write-Host 'Set (once) in VS Code User settings:' -ForegroundColor DarkGray
Write-Host "  ""dragLint.serverPath"": ""$($Dest -replace '\\','\\')\\drag-lint.exe""" -ForegroundColor DarkGray
exit 0
