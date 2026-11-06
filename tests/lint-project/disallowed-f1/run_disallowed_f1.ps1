<#
  run_disallowed_f1.ps1 -- disallowed-method on the project index (lane 145 li).

  Policy (disallowed.config.json): bare `Sleep`, and `TStringList.LoadFromFile`.
  TRIGGER-DISM-* lines must fire, CONTROL-DISM-* lines must stay silent, nothing else fires:
    BARE    Sleep(10)              textual hit, unbound: fires with and without the index
    OWNER   Obj.Sleep(10)          the index binds it to TWorker.Sleep (a member): silent WITH the index
    RECV    List.LoadFromFile(..)  List is a TStringList by ref_types: fires WITH the index only
    CONTROL Mine.LoadFromFile(..)  Mine is a TMyList: silent
  POSITIVE CONTROL: the same lint on a DB with refs.symbol_id nulled and ref_types dropped (an old
  index) and with NO --db answers as the textual rule always did: OWNER fires, RECV does not.

  Usage: pwsh -File tests\lint-project\disallowed-f1\run_disallowed_f1.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_disallowedf1_$PID"
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
function Lines([object[]]$Findings) {
  return @($Findings | Where-Object { $_.rule -eq 'disallowed-method' } | ForEach-Object { [int]$_.start_line } | Sort-Object)
}
function Marker([string]$File, [string]$Tag) {
  return @(Select-String -Path $File -Pattern "// $Tag" | ForEach-Object { $_.LineNumber } | Sort-Object)
}
try {
  $src = Join-Path $scratch 'src'
  [void](New-Item -ItemType Directory -Force -Path $src)
  Copy-Item (Join-Path $PSScriptRoot 'uDfUse.pas') $src
  $cfg = Join-Path $PSScriptRoot 'disallowed.config.json'
  $file = Join-Path $src 'uDfUse.pas'
  $db = Join-Path $scratch 'df.sqlite'
  & $exePath index $src --db $db 2>&1 | Out-Null

  $bare  = @(Marker $file 'TRIGGER-DISM-BARE')
  $recv  = @(Marker $file 'TRIGGER-DISM-RECV')
  $owner = @(Marker $file 'CONTROL-DISM-OWNER')
  $mine  = @(Marker $file 'CONTROL-DISM-RECV')
  Check 'fixture has triggers and controls' (($bare.Count -eq 1) -and ($recv.Count -eq 1) -and ($owner.Count -eq 1) -and ($mine.Count -eq 1)) ''

  $with = Lines (Parse-Findings (& $exePath lint $file --db $db --config $cfg --json 2>$null))
  $want = @($bare + $recv | Sort-Object)
  Check 'with the index: exactly the TRIGGER lines fire (Obj.Sleep and Mine.LoadFromFile silent)' (($with -join ',') -eq ($want -join ',')) "got [$($with -join ',')] want [$($want -join ',')]"

  $py = Join-Path $scratch 'edit.py'
  [IO.File]::WriteAllText($py, "import sqlite3, sys`nc = sqlite3.connect(sys.argv[1])`nfor s in sys.argv[2:]:`n    c.execute(s)`nc.commit()`nc.close()`n")
  $noTypes = Join-Path $scratch 'notypes.sqlite'
  Copy-Item $db $noTypes
  python $py $noTypes 'DROP TABLE ref_types'
  $gone = @(& $exePath sql --db $noTypes --query "SELECT name FROM sqlite_master WHERE name = 'ref_types'" 2>&1) -join ' '
  Check 'the control DB really has no ref_types' ($gone -match '\b0 row') $gone
  $r1 = Lines (Parse-Findings (& $exePath lint $file --db $noTypes --config $cfg --json 2>$null))
  $w1 = @($bare)
  Check 'no ref_types (index older than 1.44): the binding still silences Obj.Sleep, RECV is not added' (($r1 -join ',') -eq ($w1 -join ',')) "got [$($r1 -join ',')] want [$($w1 -join ',')]"
  $old = Join-Path $scratch 'old.sqlite'
  Copy-Item $db $old
  python $py $old 'DROP TABLE ref_types' 'UPDATE refs SET symbol_id = NULL'
  $without = Lines (Parse-Findings (& $exePath lint $file --db $old --config $cfg --json 2>$null))
  $today = @($bare + $owner | Sort-Object)
  Check 'no ref_types and no bound refs: textual answer as today' (($without -join ',') -eq ($today -join ',')) "got [$($without -join ',')] want [$($today -join ',')]"
  $noidx = Lines (Parse-Findings (& $exePath lint $file --config $cfg --json 2>$null))
  Check 'no --db: textual answer as today' (($noidx -join ',') -eq ($today -join ',')) "got [$($noidx -join ',')] want [$($today -join ',')]"
}
finally {
  if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAILED'; exit 1 } else { Write-Host 'ALL PASS'; exit 0 }
