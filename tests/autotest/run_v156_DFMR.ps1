# positive-control: dfm-god-handler
# positive-control: dfm-control-overlap
<#
  run_v156_DFMR.ps1 -- 1.56 lane DFM-R: dfm-god-handler (G-35) and dfm-control-overlap (G-36) on
  tests\fixtures\v156\DFMR (two form + unit pairs). Both rules are OFF by default and are switched on by config.
  Every rule is compared as an EXACT set of "<form file>:<line>"; each fixture holds firing controls and silent
  neighbours, so a rule that fires too much or too little fails. Positive controls: the Dispatch handler
  (5 bindings, 3 kinds) and the overlap of BtnB over BtnA fire; silent controls are the single-kind Row handlers,
  the 2-binding Pair handler, hidden / aligned / anchored / non-visual / stacked / backdrop-contained controls,
  and a 1 px border share. Also: the OFF defaults and the threshold option.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v156-dfmr-$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fix = (Resolve-Path "$PSScriptRoot\..\fixtures\v156\DFMR").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$Src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $Src | Out-Null
Copy-Item "$Fix\*" $Src
$OnCfg  = Join-Path $WorkDir 'on.json'
$Thr3   = Join-Path $WorkDir 'thr3.json'
$OffCfg = Join-Path $WorkDir 'off.json'
[IO.File]::WriteAllText($OnCfg, '{"enabled":["dfm-god-handler","dfm-control-overlap"]}', [Text.Encoding]::ASCII)
[IO.File]::WriteAllText($Thr3, '{"enabled":["dfm-god-handler"],"thresholds":{"dfm-god-handler":3}}', [Text.Encoding]::ASCII)
[IO.File]::WriteAllText($OffCfg, '{}', [Text.Encoding]::ASCII)

function Get-Found([string]$Rule, [string]$Cfg) {
  $out = @()
  foreach ($f in (Get-ChildItem $Src -Filter *.pas | Sort-Object Name)) {
    $argv = @('lint', $f.FullName, '--config', $Cfg, '--json')
    if ($Rule) { $argv += @('--rule', $Rule) }
    $raw = & { $ErrorActionPreference = 'Continue'; & $Exe @argv 2>$null }
    $txt = ($raw | Where-Object { $_ -is [string] }) -join "`n"
    $i = $txt.IndexOf('['); if ($i -lt 0) { continue }
    foreach ($x in @($txt.Substring($i) | ConvertFrom-Json | ForEach-Object { $_ })) {
      $r = if ($x.rule_id) { $x.rule_id } else { $x.rule }
      if ($Rule -and $r -ne $Rule) { continue }
      $p = if ($x.file_path) { $x.file_path } elseif ($x.path) { $x.path } else { $x.file }
      $out += ("{0}:{1} {2}" -f (Split-Path $p -Leaf), $x.start_line, $r)
    }
  }
  return ,@($out | Sort-Object -Unique)
}
function Compare-Rule([string]$Name, [string]$Rule, [string]$Cfg, [string[]]$Want) {
  $got = Get-Found $Rule $Cfg
  $w = @($Want | ForEach-Object { "$_ $Rule" } | Sort-Object)
  Check "$Name has firing controls" ($w.Count -gt 0)
  $missed = @($w | Where-Object { $got -notcontains $_ })
  $extra  = @($got | Where-Object { $w -notcontains $_ })
  Check "$Name fires exactly on its controls" (($missed.Count -eq 0) -and ($extra.Count -eq 0)) ("missed: $($missed -join ', ') extra: $($extra -join ', ')")
}

Write-Host 'THE RULES' -ForegroundColor Cyan
# positive-control: Dispatch (5 bindings, 3 event kinds) -- first binding line 4; Other has 4 bindings (below the default 5)
Compare-Rule 'dfm-god-handler default threshold' 'dfm-god-handler' $OnCfg @('GodForm.dfm:4')
# positive-control: the threshold option lowers the bar; Other (4 bindings, 2 kinds) now fires, Pair (2) and Row (1 kind) still do not
Compare-Rule 'dfm-god-handler threshold 3' 'dfm-god-handler' $Thr3 @('GodForm.dfm:4', 'GodForm.dfm:39')
# positive-control: BtnB over BtnA, EdtJ over BtnI, ChB over ChA inside a panel
Compare-Rule 'dfm-control-overlap' 'dfm-control-overlap' $OnCfg @('OverlapForm.dfm:10', 'OverlapForm.dfm:77', 'OverlapForm.dfm:112')

Write-Host 'DEFAULTS' -ForegroundColor Cyan
$all = Get-Found '' $OffCfg
$ids = @($all | ForEach-Object { ($_ -split ' ')[1] } | Sort-Object -Unique)
foreach ($off in 'dfm-god-handler', 'dfm-control-overlap') {
  Check "$off is OFF by default" ($ids -notcontains $off) ($ids -join ', ')
}

if ($script:Failed) { Write-Host "FAIL ($script:Passed passed)" -ForegroundColor Red; exit 1 }
Write-Host "PASS ($script:Passed checks)" -ForegroundColor Green
exit 0
} finally {
  if (($WorkDir -like "$env:TEMP\drag-lint-v156-dfmr-$PID*") -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}