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

  $ruleArgs = @('--enable', 'string-equality-comparison,exhaustive-enum-case')
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
} finally {
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
