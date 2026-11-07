<#
  run_t2_types.ps1 -- 1.46 lane t2: criticalsection-not-released uses the F1 receiver type: an Enter/Acquire on a
  receiver provably not a lock (TSemaphore) is not a lock acquire.

  Fixture markers (line comments): TRIGGER-T2-<X> = fires WITH the fact; CONTROL-T2-<X> = silent
  WITH the fact but fires on today's logic (the false positive the fact removes).
  Three runs per rule: the full index (exactly the TRIGGER lines), a copy with ref_types dropped,
  and `lint <file>` with no index. The last two must answer as today: every TRIGGER whose
  finding needs the fact is gone, every CONTROL fires again. A guard that passes with the
  rule off fails here: the TRIGGER lines are required.

  Usage: pwsh -File tests\lint-project\t2-types\run_t2_types.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_t2_$PID"
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}
function Parse-Findings([string[]]$Raw) {
  $txt = ($Raw -join "`n"); $b = $txt.IndexOf('[')
  $out = @(); if ($b -ge 0) { try { $out = @($txt.Substring($b) | ConvertFrom-Json) } catch { $out = @() } }
  if ($null -eq $out) { $out = @() }
  return ,@($out)
}
function ToLines($Findings, [string]$Rule) {
  return @($Findings | Where-Object { $_.rule -eq $Rule -and $_.file_path -like '*uT2Use*' } |
    ForEach-Object { [int]$_.start_line } | Sort-Object)
}
function Markers([string]$File, [string[]]$Prefixes) {
  $res = @()
  foreach ($p in $Prefixes) {
    $res += @(Select-String -Path $File -Pattern "// $p" | ForEach-Object { [int]$_.LineNumber })
  }
  return @($res | Sort-Object)
}
try {
  $src = Join-Path $scratch 'src'
  [void](New-Item -ItemType Directory -Force -Path $src)
  Copy-Item (Join-Path $PSScriptRoot '*.pas') $src
  $use = Join-Path $src 'uT2Use.pas'
  $db = Join-Path $scratch 't2.sqlite'
  & $exePath index $src --db $db 2>&1 | Out-Null
  $old = Join-Path $scratch 'old.sqlite'
  Copy-Item $db $old
  $py = Join-Path $scratch 'drop.py'
  [IO.File]::WriteAllText($py, "import sqlite3, sys`nc = sqlite3.connect(sys.argv[1])`nc.execute('DROP TABLE ref_types')`nc.commit()`nc.close()`n")
  python $py $old
  $gone = @(& $exePath sql --db $old --query "SELECT name FROM sqlite_master WHERE name = 'ref_types'" 2>&1) -join ' '
  Check 'the control DB really has no ref_types' ($gone -match '\b0 row') $gone

  # Today = the markers whose line the OLD logic reports (no fact): controls, and triggers that need no fact.
  $cases = @(
    @{ Rule = 'criticalsection-not-released'; Tag = 'LOCK'; Today = @('TRIGGER-T2-LOCK', 'CONTROL-T2-LOCK') }
  )
  foreach ($c in $cases) {
    $r = $c.Rule
    $want = @(Markers $use @("TRIGGER-T2-$($c.Tag)"))
    Check "$r has a trigger and a control in the fixture" (($want.Count -gt 0) -and (@(Markers $use @("CONTROL-T2-$($c.Tag)")).Count -gt 0))
    $full = @(ToLines (Parse-Findings (& $exePath lint-all --db $db --format json --rule $r 2>$null)) $r)
    Check "$r with the index fires exactly on the TRIGGER lines" (($full -join ',') -eq ($want -join ',')) "got [$($full -join ',')] want [$($want -join ',')]"
    $wantToday = @(Markers $use $c.Today)
    $noTbl = @(ToLines (Parse-Findings (& $exePath lint-all --db $old --format json --rule $r 2>$null)) $r)
    Check "$r with ref_types dropped answers as today" (($noTbl -join ',') -eq ($wantToday -join ',')) "got [$($noTbl -join ',')] want [$($wantToday -join ',')]"
    $noIdx = @(ToLines (Parse-Findings (& $exePath lint $use --format json --rule $r 2>$null)) $r)
    Check "$r with no index answers as today" (($noIdx -join ',') -eq ($wantToday -join ',')) "got [$($noIdx -join ',')] want [$($wantToday -join ',')]"
  }
} finally {
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
