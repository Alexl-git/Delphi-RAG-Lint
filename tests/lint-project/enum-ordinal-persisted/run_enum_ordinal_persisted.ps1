<#
  run_enum_ordinal_persisted.ps1 -- the `enum-ordinal-persisted` project lint
  rule (lane X6; spec docs\superpowers\specs\2026-10-25-three-lint-rules-design.md
  rule 2).

  An enum type fires when (1) an ordinal cast crosses its boundary -- cast-IN
  `TEnum(x)` (bound to the type since gap G1) or cast-OUT `Ord(v)` / `Byte(v)` /
  ... on a line with exactly one enum-bound ref -- (2) a persistence SINK from
  rules\enum-persist-sinks.txt is named in the SAME routine, and (3) at least
  one value has an IMPLICIT ordinal. One finding per type, at its declaration.

    RUN 1  bare `lint-all`  -> exactly the TRIGGER types (ON by default), none
                               of the CONTROL types; witness names the sink.
    RUN 3  TKindPinned unpinned in the scratch copy -> it fires (pin control).
    RUN 2  the same engine copied beside a sink table WITHOUT WriteBuffer
                            -> the two WriteBuffer triggers go silent and the
                               FieldByName trigger still fires (positive
                               control: the TABLE drives the finding).

  Line numbers come from the fixture's TRIGGER-* / CONTROL-* markers.
  `lint --json` is a BARE ARRAY whose line key is `start_line`.

  Usage: pwsh -File tests\lint-project\enum-ordinal-persisted\run_enum_ordinal_persisted.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$fixture = Join-Path $PSScriptRoot 'uEnumPersist.pas'
$scratch = Join-Path C:\TEMP "draglint_enum_ordinal_persisted_$PID"
$Rule    = 'enum-ordinal-persisted'
try {
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path (Join-Path $scratch 'src') | Out-Null
Copy-Item $fixture (Join-Path $scratch 'src')
$db = Join-Path $scratch 'enumpersist.sqlite'

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
function LineOf([string]$Marker) {
  $m = @(Select-String -LiteralPath $fixture -SimpleMatch -Pattern "// $Marker")
  if ($m.Count -ne 1) { throw "marker '$Marker' found $($m.Count) times in the fixture" }
  return [int]$m[0].LineNumber
}

& $exePath index (Join-Path $scratch 'src') --db $db 2>&1 | Out-Null
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$tOut = LineOf 'TRIGGER-OUT'; $tIn = LineOf 'TRIGGER-IN'; $tCom = LineOf 'TRIGGER-COMMENT'
$controls = @('CONTROL-PINNED', 'CONTROL-NOSINK', 'CONTROL-SPLIT')

# RUN 1 -- default lint-all: the rule is ON by default
$all = Parse-Findings (& $exePath lint-all --db $db --format json 2>$null)
$a = @($all | Where-Object { $_.rule -eq $Rule })
$a | ForEach-Object { Write-Host ("    {0}:{1} {2}" -f (Split-Path $_.file_path -Leaf), $_.start_line, $_.message) }
function MsgAt($Set, [int]$L) { $m = @($Set | Where-Object { [int]$_.start_line -eq $L }); if ($m.Count -eq 1) { return [string]$m[0].message }; return '' }
Check 'run 1 is not vacuous (lint-all returned findings)' ($all.Count -gt 0) "total=$($all.Count)"
Check 'run 1 exactly 3 findings' ($a.Count -eq 3) "count=$($a.Count)"
Check 'TRIGGER-OUT TKindOut (Ord -> WriteBuffer, 3 of 3 implicit)' (((MsgAt $a $tOut) -like '*TKindOut*Ord*WriteBuffer*SaveOut*') -and ((MsgAt $a $tOut) -like '*3 of 3*')) (MsgAt $a $tOut)
Check 'TRIGGER-IN TKindIn (cast-in, FieldByName sink)' (((MsgAt $a $tIn) -like '*TKindIn*FieldByName*LoadIn*') -and ((MsgAt $a $tIn) -like '*2 of 2*')) (MsgAt $a $tIn)
Check 'TRIGGER-COMMENT a commented-out "= N" is no pin (2 of 3)' ((MsgAt $a $tCom) -like '*TKindComment*2 of 3*') (MsgAt $a $tCom)
foreach ($c in $controls) {
  $l = LineOf $c
  Check "$c stays silent" ((MsgAt $a $l) -eq '') (MsgAt $a $l)
}

# RUN 2 -- positive control for the sink table: same engine, table without WriteBuffer
$eng = Join-Path $scratch 'engine'
New-Item -ItemType Directory -Path (Join-Path $eng 'rules') | Out-Null
$exeDir = Split-Path $exePath -Parent
Copy-Item $exePath $eng
Get-ChildItem $exeDir -Filter *.dll | ForEach-Object { Copy-Item $_.FullName $eng }
$tbl = Join-Path $repo 'rules\enum-persist-sinks.txt'
Check 'sink table is tracked in rules\' (Test-Path $tbl)
$kept = @(Get-Content $tbl | Where-Object { $_.Trim() -ne 'WriteBuffer' })
Check 'sink table names WriteBuffer (control is meaningful)' ($kept.Count -lt @(Get-Content $tbl).Count)
[IO.File]::WriteAllText((Join-Path $eng 'rules\enum-persist-sinks.txt'), (($kept -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
$b2 = Parse-Findings (& (Join-Path $eng 'drag-lint.exe') lint-all --db $db --format json --rule $Rule 2>$null)
$b = @($b2 | Where-Object { $_.rule -eq $Rule })
Check 'run 2 WriteBuffer removed -> TKindOut silent' ((MsgAt $b $tOut) -eq '') (MsgAt $b $tOut)
Check 'run 2 WriteBuffer removed -> TKindComment silent' ((MsgAt $b $tCom) -eq '') (MsgAt $b $tCom)
Check 'run 2 FieldByName still drives TKindIn' ((MsgAt $b $tIn) -like '*TKindIn*') "count=$($b.Count)"

# RUN 3 -- positive control for the pin clause: unpin TKindPinned in the scratch
# copy (same lines), reindex, and the SAME boundary now fires -- so run 1's
# silence on CONTROL-PINNED came from the pins, not from a missed cast.
$sc = Join-Path $scratch 'src\uEnumPersist.pas'
$txt = [IO.File]::ReadAllText($sc)
Check 'fixture spells the pinned list' ($txt.Contains('(kpA = 0, kpB = 1, kpC = 2)'))
[IO.File]::WriteAllText($sc, $txt.Replace('(kpA = 0, kpB = 1, kpC = 2)', '(kpA, kpB, kpC)'), [Text.Encoding]::ASCII)
& $exePath index (Join-Path $scratch 'src') --db $db 2>&1 | Out-Null
$p3 = Parse-Findings (& $exePath lint-all --db $db --format json --rule $Rule 2>$null)
$c3 = @($p3 | Where-Object { $_.rule -eq $Rule })
$lp = LineOf 'CONTROL-PINNED'
Check 'run 3 unpinned TKindPinned now fires (3 of 3)' ((MsgAt $c3 $lp) -like '*TKindPinned*Ord*WriteBuffer*3 of 3*') (MsgAt $c3 $lp)
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
} finally {
  if ($scratch -and (Test-Path $scratch)) { [System.IO.Directory]::Delete($scratch, $true) }
}
