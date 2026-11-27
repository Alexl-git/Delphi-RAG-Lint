# run_v156_FA2_cfg.ps1 -- v156 lane FA-2: the ELSE part of an except block is in the flow graph
# (DRagLint.Analysis.Cfg), so the data-flow walk emits rows from it. Fixture
# tests\fixtures\v156-fa2-cfg\uExceptElse.pas, rows read with `sql --json` (rows are positional:
# mapped onto columns[].name). POSITIVE CONTROL: the row of the `on` handler beside the else part
# exists on every engine, so a run that reads no rows at all cannot pass.
# Usage: pwsh -File tests\autotest\run_v156_FA2_cfg.ps1 [-Exe <drag-lint.exe>]
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
$exePath = (Resolve-Path $Exe).Path
$fx   = Join-Path $repo 'tests\fixtures\v156-fa2-cfg'
$src  = [IO.File]::ReadAllLines((Join-Path $fx 'uExceptElse.pas'))
$tmp  = Join-Path $env:TEMP "v156fa2cfg_$PID"
[void][IO.Directory]::CreateDirectory($tmp)
$db   = Join-Path $tmp 'fx.sqlite'
$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name  $Detail"; $script:fail++ }
}
function LineOf([string]$Marker) {
  for ($i = 0; $i -lt $src.Length; $i++) { if ($src[$i].Contains("{ $Marker }")) { return $i + 1 } }
  throw "marker $Marker not in the fixture"
}
function Rows([string]$Query) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $exePath sql --db $db --json --query $Query 2>$null }
  $doc = ($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ }
  $names = @($doc.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in $doc.rows) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $names.Count; $i++) { $o[$names[$i]] = $r[$i] }
    $out += [pscustomobject]$o
  }
  return ,@($out)
}
function Has($Rows, [string]$Marker, [string]$DstKind, [string]$SrcName) {
  $ln = LineOf $Marker
  return (@($Rows | Where-Object { $_.dst_line -eq $ln -and $_.dst_kind -eq $DstKind -and $_.src_kind -eq 'param' -and $_.src_name -eq $SrcName }).Count -eq 1)
}
Push-Location $env:TEMP
try {
  & { $ErrorActionPreference = 'Continue'; & $exePath index $fx --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
  $rows = Rows 'SELECT dst_kind, dst_line, dst_name, src_kind, src_name FROM data_flows ORDER BY dst_line, dst_col'
  $rows | ForEach-Object { Write-Host ("  {0} line {1} {2} <- {3} {4}" -f $_.dst_kind, $_.dst_line, $_.dst_name, $_.src_kind, $_.src_name) }
  Check 'POSITIVE CONTROL: the on-handler argument row exists' (Has $rows 'M-ON' 'arg' 'P')
  Check 'else part: its call argument has a row' (Has $rows 'M-ELSE' 'arg' 'P')
  Check 'else part with two statements: the first has a row' (Has $rows 'M-ELSE-FIRST' 'arg' 'P')
  Check 'else part with two statements: the second has a row' (Has $rows 'M-ELSE-SECOND' 'arg' 'Q')
  # a 'result' row is positioned at the routine, not at the assignment: P reaches Result only in the else part
  Check 'else part: a Result assignment has a row' (@($rows | Where-Object { $_.dst_kind -eq 'result' -and $_.src_kind -eq 'param' -and $_.src_name -eq 'P' }).Count -eq 1)
} finally { Pop-Location }
Write-Host ("v156 FA-2 cfg: {0} failure(s)" -f $fail)
exit $fail
