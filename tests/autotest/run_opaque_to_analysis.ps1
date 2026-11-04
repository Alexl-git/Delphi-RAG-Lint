# Guard: opaque-to-analysis (1.42 lane opaque, project-wide, OFF by default; INBOX-new-rules-from-graph-and-converter-facts C2).
#
# Fixture tests\lint-project\opaque-to-analysis:
#   lib\System.SysUtils.pas, lib\System.Classes.pas   stand-in platform library
#   proj\uOpaque.pas  TWorker.HitOpaque            -> FIRES (6 of 7: procedural values; the library Format is left out)
#                     TWorker.HitAtThreshold       -> FIRES (3 of 5 = exactly 60 percent, exactly 3 calls)
#                     TWorker.QuietJustBelowShare  -> silent (3 of 6 = 50 percent)
#                     TWorker.QuietLibraryOnly     -> silent (typed library receiver, project type inheriting a library member,
#                                                     inherited bare member, library head, casts, library routine, intrinsic)
#                     TWorker.QuietMostlyResolved  -> silent (3 of 11: not predominantly)
#                     TWorker.QuietTooFew          -> silent (2 of 2: below the minimum count)
#                     TWorker.QuietAllResolved     -> silent (nothing opaque)
# Runs: --rule (fires), default lint-all (OFF), --enable (ON), no library index (SILENT: every library call would read as opaque),
# and a project indexed WITH --library-db (stored external_target: the same two findings).
# Positive control: an engine without the rule reports 0 findings and fails the "fires" checks.
# Usage: pwsh -File tests/autotest/run_opaque_to_analysis.ps1 [-Exe <path>]
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
      [string]$WorkDir = "$env:TEMP\drag-lint-opaque-$PID")
$ErrorActionPreference = 'Stop'
$Rule = 'opaque-to-analysis'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok) {
  if ($Ok) { Write-Host "  [PASS] $Name" -ForegroundColor Green } else { Write-Host "  [FAIL] $Name" -ForegroundColor Red; $script:Failed = $true }
}
function Lint([string[]]$LintArgs) {
  $raw = & $Exe lint-all @LintArgs --format json 2>$null
  $txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
  $f = @(); if ($b -ge 0) { try { $f = @($txt.Substring($b) | ConvertFrom-Json) } catch { $f = @() } }
  return ,@($f | Where-Object { $_.rule -eq $Rule })
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$src = Join-Path $PSScriptRoot '..\lint-project\opaque-to-analysis'
New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  foreach ($d in 'proj', 'lib') {
    New-Item -ItemType Directory -Force (Join-Path $WorkDir $d) | Out-Null
    Get-ChildItem (Join-Path $src $d) -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $WorkDir $d) -Force }
  }
  $db  = Join-Path $WorkDir 'fx.sqlite'
  $lib = Join-Path $WorkDir 'lib.sqlite'
  & $Exe index (Join-Path $WorkDir 'lib') --db $lib 2>&1 | Out-Null
  Check 'library index exits 0' ($LASTEXITCODE -eq 0)
  & $Exe index (Join-Path $WorkDir 'proj') --db $db 2>&1 | Out-Null
  Check 'project index exits 0' ($LASTEXITCODE -eq 0)
  $pas = Get-Content (Join-Path $WorkDir 'proj\uOpaque.pas')
  $line = 0
  for ($i = 0; $i -lt $pas.Count; $i++) { if ($pas[$i] -match '^procedure TWorker\.HitOpaque') { $line = $i + 1 } }

  # positive-control: opaque-to-analysis
  $f = Lint @('--db', $db, '--db', $lib, '--rule', $Rule)
  $f | ForEach-Object { Write-Host ("    {0}:{1} {2}" -f (Split-Path $_.file_path -Leaf), $_.start_line, $_.message) -ForegroundColor DarkGray }
  Check 'positive: TWorker.HitOpaque fires' (@($f | Where-Object { $_.message -match 'HitOpaque' }).Count -eq 1)
  Check 'positive: TWorker.HitAtThreshold fires (3 of 5)' (@($f | Where-Object { $_.message -match 'HitAtThreshold: 3 of 5\b' }).Count -eq 1)
  Check 'finding sits on the implementation line' (@($f | Where-Object { [int]$_.start_line -eq $line }).Count -eq 1)
  Check 'negative: every Quiet* routine silent' (@($f | Where-Object { $_.message -match 'Quiet' }).Count -eq 0)
  Check 'exactly two findings' ($f.Count -eq 2)
  Check 'message states the numbers (6 of 7)' (@($f | Where-Object { $_.message -match 'HitOpaque: 6 of 7\b' }).Count -eq 1)
  Check 'message names the opaque calls' (@($f | Where-Object { $_.message -match 'ACb, FCb' }).Count -eq 1)
  Check 'message states what is blind' (@($f | Where-Object { $_.message -match 'impact' -and $_.message -match 'call tree' -and $_.message -match 'dead-code' }).Count -eq 2)
  Check 'severity is info' (($f.Count -gt 0) -and (@($f | Where-Object { $_.severity -ne 'info' }).Count -eq 0))

  $off = Lint @('--db', $db, '--db', $lib)
  Check 'negative: OFF by default in a plain lint-all' ($off.Count -eq 0)
  $on = Lint @('--db', $db, '--db', $lib, '--enable', $Rule)
  Check 'positive: --enable turns it on' ($on.Count -eq 2)

  $nolib = Lint @('--db', $db, '--library-db', 'none', '--rule', $Rule)
  Check 'negative: no library index -> silent' ($nolib.Count -eq 0)

  $dbx = Join-Path $WorkDir 'fxlib.sqlite'
  & $Exe index (Join-Path $WorkDir 'proj') --db $dbx --library-db $lib 2>&1 | Out-Null
  $ext = & $Exe sql --query "select count(*) from refs where external_target is not null" --db $dbx 2>$null | Select-Object -Skip 2 -First 1
  Check 'control: the --library-db index stored external_target rows' ([int]$ext -gt 0)
  $st = Lint @('--db', $dbx, '--db', $lib, '--rule', $Rule)
  Check 'stored external_target: the same two findings' ($st.Count -eq 2)
} finally { [IO.Directory]::Delete($WorkDir, $true) }
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }