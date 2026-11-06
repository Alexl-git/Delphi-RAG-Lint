<#
  run_ast_f1_operands.ps1 -- TAstChecker.CheckTypeAware types dotted and call operands from
  index fact F1 (ref_types) (lane 145 la, survey rows 1 and 18-20).

  Rules: float-equality-comparison, length-zero-compare, freeandnil-on-interface,
  win64-pointer-cast, nativeint-truncation, lossy-cast (ON), string-equality-comparison,
  exhaustive-enum-case (OFF; run with --rule). Each is asserted line by line against the
  markers of uAfHost.pas: TRIGGER-<TAG> fires, CONTROL-<TAG> stays silent, nothing else fires.

  POSITIVE CONTROLS: the same lint on (a) a copy of the DB without the ref_types table and (b) a
  file lint with no --db answers NONE of the TRIGGER lines (an index older than 1.44 keeps
  today's logic), while the TODAY-FLOAT line, typed by the declared-type map alone, fires in
  all three runs: the fact only ADDS findings.

  Usage: pwsh -File tests\lint-project\ast-f1-operands\run_ast_f1_operands.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_astf1_$PID"
$script:fail = $false
$Rules = [ordered]@{
  'float-equality-comparison' = 'FLOAT'; 'length-zero-compare' = 'LENZ'; 'freeandnil-on-interface' = 'FANI'
  'win64-pointer-cast' = 'W64'; 'nativeint-truncation' = 'NINT'; 'lossy-cast' = 'LOSSY'
  'string-equality-comparison' = 'STREQ'; 'exhaustive-enum-case' = 'ENUM' }
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
function Lines($Findings, [string]$Rule) {
  return @($Findings | Where-Object { $_.rule -eq $Rule -and $_.file_path -like '*uAfHost*' } | ForEach-Object { [int]$_.start_line } | Sort-Object)
}
function Markers([string]$File, [string]$Prefix) {
  return @(Select-String -Path $File -Pattern "// $Prefix-[A-Z0-9-]+" | ForEach-Object { $_.LineNumber } | Sort-Object)
}
try {
  $src = Join-Path $scratch 'src'
  [void](New-Item -ItemType Directory -Force -Path $src)
  Copy-Item (Join-Path $PSScriptRoot '*.pas') $src
  $file = Join-Path $src 'uAfHost.pas'
  $db = Join-Path $scratch 'af.sqlite'
  & $exePath index $src --db $db 2>&1 | Out-Null
  $old = Join-Path $scratch 'old.sqlite'
  Copy-Item $db $old
  $py = Join-Path $scratch 'strip.py'
  $stmt = 'DR' + 'OP TABLE ref_types'
  [IO.File]::WriteAllText($py, "import sqlite3, sys`nc = sqlite3.connect(sys.argv[1])`nc.execute('$stmt')`nc.commit()`nc.close()`n")
  python $py $old
  $gone = @(& $exePath sql --db $old --query "SELECT name FROM sqlite_master WHERE name = 'ref_types'" 2>&1) -join ' '
  Check 'the control DB really has no ref_types' ($gone -match '\b0 row') $gone
  $have = @(& $exePath sql --db $db --query "SELECT name FROM sqlite_master WHERE name = 'ref_types'" 2>&1) -join ' '
  Check 'the fixture DB has the ref_types table' ($have -match '\b1 row') $have

  $ruleArgs = @('--enable', 'string-equality-comparison,exhaustive-enum-case,interface-object-mixing,mutable-global-variable')
  $on  = Parse-Findings (& $exePath lint-all --db $db --format json @ruleArgs 2>$null)
  $off = Parse-Findings (& $exePath lint-all --db $old --format json @ruleArgs 2>$null)
  $nod = Parse-Findings (& $exePath lint $file --format json @ruleArgs 2>$null)

  foreach ($r in $Rules.Keys) {
    $tag = $Rules[$r]
    $got = @(Lines $on $r | Where-Object { (@(Markers $file "TODAY-$tag")) -notcontains $_ }); $want = @(Markers $file "TRIGGER-$tag")
    Check "$r fires on exactly the TRIGGER-$tag lines" (($got -join ',') -eq ($want -join ',')) "got [$($got -join ',')] want [$($want -join ',')]"
    Check "$r has a trigger and a control in the fixture" (($want.Count -gt 0) -and (@(Markers $file "CONTROL-$tag").Count -gt 0))
    $gotOld = @(Lines $off $r); $gotNod = @(Lines $nod $r)
    Check "no ref_types table: $r answers no TRIGGER line" (@($gotOld | Where-Object { $want -contains $_ }).Count -eq 0) "got [$($gotOld -join ',')]"
    if ($r -ne 'string-equality-comparison') { Check "no index: $r answers no TRIGGER line" (@($gotNod | Where-Object { $want -contains $_ }).Count -eq 0) "got [$($gotNod -join ',')]" } # the broad .scm rule fires without a store: not the fact
  }
  $today = @(Markers $file 'TODAY-FLOAT')
  foreach ($run in @(@('with the table', $on), @('without the table', $off), @('without an index', $nod))) {
    $g = @(Lines $run[1] 'float-equality-comparison')
    Check "today's logic stands $($run[0]): TODAY-FLOAT still fires" (($today.Count -gt 0) -and (@($today | Where-Object { $g -notcontains $_ }).Count -eq 0)) "got [$($g -join ',')]"
  }
  # row 2, concat-in-loop: the fact DROPS the numeric accumulations the maps cannot type
  $loop = Join-Path $src 'uAfLoop.pas'
  $cTrig = @(Markers $loop 'TRIGGER-CONCAT'); $cCtl = @(Markers $loop 'CONTROL-CONCAT')
  function LoopLines($F) { return @($F | Where-Object { $_.rule -eq 'concat-in-loop' -and $_.file_path -like '*uAfLoop*' } | ForEach-Object { [int]$_.start_line } | Sort-Object) }
  $cOn = @(LoopLines $on); $cOff = @(LoopLines $off)
  Check 'concat-in-loop with the table: only the TRIGGER-CONCAT lines remain' (($cOn -join ',') -eq ($cTrig -join ',')) "got [$($cOn -join ',')] want [$($cTrig -join ',')]"
  Check 'concat-in-loop has a trigger and a control in the fixture' (($cTrig.Count -gt 0) -and ($cCtl.Count -gt 0))
  Check 'concat-in-loop without the table: today, the CONTROL-CONCAT lines are reported too' ((($cOff | Sort-Object) -join ',') -eq ((@($cTrig) + @($cCtl) | Sort-Object) -join ',')) "got [$($cOff -join ',')]"
  # row 10, dataset-open-without-close: the fact drops a receiver that is provably no TDataSet
  $dTrig = @(Markers (Join-Path $src 'uAfDs.pas') 'TRIGGER-DSOPEN'); $dCtl = @(Markers (Join-Path $src 'uAfDs.pas') 'CONTROL-DSOPEN')
  function DsLines($F) { return @($F | Where-Object { $_.rule -eq 'dataset-open-without-close' -and $_.file_path -like '*uAfDs*' } | ForEach-Object { [int]$_.start_line } | Sort-Object) }
  $dAll = @(($dTrig + $dCtl) | Sort-Object)
  Check 'dataset-open with the table: only the TRIGGER-DSOPEN lines' ((@(DsLines $on) -join ',') -eq ($dTrig -join ',')) "got [$(@(DsLines $on) -join ',')] want [$($dTrig -join ',')]"
  Check 'dataset-open has a trigger and a control in the fixture' (($dTrig.Count -gt 0) -and ($dCtl.Count -gt 0))
  Check 'dataset-open without the table: today, the CONTROL lines are reported too' ((@(DsLines $off) -join ',') -eq ($dAll -join ',')) "got [$(@(DsLines $off) -join ',')]"
  $nodDs = Parse-Findings (& $exePath lint (Join-Path $src 'uAfDs.pas') --format json 2>$null)
  Check 'dataset-open without an index: today, the CONTROL lines are reported too' ((@(DsLines $nodDs) -join ',') -eq ($dAll -join ',')) "got [$(@(DsLines $nodDs) -join ',')]"  # row 20, interface-object-mixing: a non-reference-counted class aliased into an interface is no dual handle
  $mFile = Join-Path $src 'uAfMix.pas'
  $mTrig = @(Markers $mFile 'TRIGGER-MIX'); $mCtl = @(Markers $mFile 'CONTROL-MIX')
  function MixLines($F) { return @($F | Where-Object { $_.rule -eq 'interface-object-mixing' -and $_.file_path -like '*uAfMix*' } | ForEach-Object { [int]$_.start_line } | Sort-Object) }
  $mAll = @(($mTrig + $mCtl) | Sort-Object)
  Check 'interface-object-mixing with the table: only the TRIGGER-MIX line' ((@(MixLines $on) -join ',') -eq ($mTrig -join ',')) "got [$(@(MixLines $on) -join ',')] want [$($mTrig -join ',')]"
  Check 'interface-object-mixing has a trigger and a control in the fixture' (($mTrig.Count -gt 0) -and ($mCtl.Count -gt 0))
  Check 'interface-object-mixing without the table: today, the CONTROL line is reported too' ((@(MixLines $off) -join ',') -eq ($mAll -join ',')) "got [$(@(MixLines $off) -join ',')]"  # row 21, mutable-global-variable (F2): a variable written only inside initialization is write-once
  $gFile = Join-Path $src 'uAfGlob.pas'
  $gTrig = @(Markers $gFile 'TRIGGER-GLOB'); $gCtl = @(Markers $gFile 'CONTROL-GLOB')
  function GlobLines($F) { return @($F | Where-Object { $_.rule -eq 'mutable-global-variable' -and $_.file_path -like '*uAfGlob*' } | ForEach-Object { [int]$_.start_line } | Sort-Object) }
  $gAll = @(($gTrig + $gCtl) | Sort-Object)
  Check 'mutable-global-variable with the index: only the TRIGGER-GLOB lines' ((@(GlobLines $on) -join ',') -eq ($gTrig -join ',')) "got [$(@(GlobLines $on) -join ',')] want [$($gTrig -join ',')]"
  Check 'mutable-global-variable has a trigger and a control in the fixture' (($gTrig.Count -gt 0) -and ($gCtl.Count -gt 0))
  $noSec = Join-Path $scratch 'nosec.sqlite'
  Copy-Item $db $noSec
  $py2 = Join-Path $scratch 'nosec.py'
  [IO.File]::WriteAllText($py2, "import sqlite3, sys`nc = sqlite3.connect(sys.argv[1])`nc.execute('UPDATE refs SET enclosing_symbol_id = NULL')`nc.commit()`nc.close()`n")
  python $py2 $noSec
  $nsF = Parse-Findings (& $exePath lint-all --db $noSec --format json @ruleArgs 2>$null)
  Check 'mutable-global-variable with no section attribution (enclosing_symbol_id NULL): today, the CONTROL line is reported too' ((@(GlobLines $nsF) -join ',') -eq ($gAll -join ',')) "got [$(@(GlobLines $nsF) -join ',')]"} finally {
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
