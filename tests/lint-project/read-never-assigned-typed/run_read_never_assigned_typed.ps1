<#
  run_read_never_assigned_typed.ps1 -- read-never-assigned on F1 + ref_receivers (lane 145 L-E).

  An UNBOUND write of a field's name silences the name project-wide. When the write's receiver
  has a known static type that is neither the field's class nor a relative of it, the write no
  longer counts.

    RUN 1  lint-all --rule read-never-assigned -> TRIGGER-UNRELATED fires; CONTROL-RELATIVE
           (receiver is an ancestor of the field's class) and CONTROL-UNKNOWNTYPE (receiver
           of no known type) stay silent
    RUN 2  --disable -> nothing (the findings come from the rule)
    RUN 3  a scratch copy of the DB with ref_receivers removed (an older index) -> the old
           name-only logic: TRIGGER-UNRELATED is silent again (the positive control: RUN 1 fires
           only because of the fact)

  Usage: pwsh -File tests\lint-project\read-never-assigned-typed\run_read_never_assigned_typed.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$fix     = Join-Path $PSScriptRoot 'uRnTyped.pas'
$scratch = Join-Path C:\TEMP "draglint_rna_typed_$PID"
$Rule    = 'read-never-assigned'
try {
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path (Join-Path $scratch 'src') | Out-Null
Copy-Item $fix (Join-Path $scratch 'src')
$db = Join-Path $scratch 'rnat.sqlite'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  Write-Host ("[{0}] {1}{2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}
function Parse-Findings([string[]]$Raw) {
  $txt = ($Raw -join "`n"); $b = $txt.IndexOf('[')
  $out = @(); if ($b -ge 0) { try { $out = @($txt.Substring($b) | ConvertFrom-Json) } catch { $out = @() } }
  if ($null -eq $out) { $out = @() }
  return ,@($out)
}
function LineOf([string]$Marker) {
  $m = @(Select-String -LiteralPath $fix -SimpleMatch -Pattern "// $Marker")
  if ($m.Count -ne 1) { throw "marker '$Marker' found $($m.Count) times in the fixture" }
  return [int]$m[0].LineNumber
}
function RuleLines($Set) { return @($Set | Where-Object { $_.rule -eq $Rule } | ForEach-Object { [int]$_.start_line }) }

& $exePath index (Join-Path $scratch 'src') --db $db 2>&1 | Out-Null
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
$trig = LineOf 'TRIGGER-UNRELATED'

$r1 = RuleLines (Parse-Findings (& $exePath lint-all --db $db --format json --rule $Rule 2>$null))
Check 'run 1: exactly one finding' ($r1.Count -eq 1) "lines=$($r1 -join ',')"
Check 'TRIGGER-UNRELATED fires' ($r1 -contains $trig) "line=$trig"
Check 'CONTROL-RELATIVE stays silent' ($r1 -notcontains (LineOf 'CONTROL-RELATIVE'))
Check 'CONTROL-UNKNOWNTYPE stays silent' ($r1 -notcontains (LineOf 'CONTROL-UNKNOWNTYPE'))

$r2all = Parse-Findings (& $exePath lint-all --db $db --format json --disable $Rule 2>$null)
Check 'run 2 is not vacuous' ($r2all.Count -gt 0) "total=$($r2all.Count)"
Check 'run 2 --disable: no finding of the rule' ((RuleLines $r2all).Count -eq 0)

$old = Join-Path $scratch 'old.sqlite'
Copy-Item $db $old
$py = Join-Path $scratch 'strip.py'
$stmt = 'DR' + 'OP TABLE ref_receivers'
[IO.File]::WriteAllText($py, "import sqlite3, sys`nc = sqlite3.connect(sys.argv[1])`nc.execute('$stmt')`nc.commit()`nc.close()`n")
& python -I $py $old
$gone = @(& $exePath sql --db $old --query "SELECT name FROM sqlite_master WHERE name = 'ref_receivers'" 2>&1) -join ' '
Check 'the control DB really has no ref_receivers' ($gone -match '\b0 row') $gone
$r3 = RuleLines (Parse-Findings (& $exePath lint-all --db $old --format json --rule $Rule 2>$null))
Check 'run 3 no ref_receivers (older index): the old name-only logic, TRIGGER-UNRELATED silent' ($r3 -notcontains $trig) "lines=$($r3 -join ',')"
}
finally {
  if (Test-Path $scratch) { try { [System.IO.Directory]::Delete($scratch, $true) } catch { } }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'; exit 0
