<#
  run_v156_FP1.ps1 -- 1.56 lane FP-1: false-positive fixes found by triage of the new MEM/OO rules on real
  code. Fixtures in tests\fixtures\v156\FP1. A fixture line that must report carries "// FIRE <rule>"; every
  other line must stay silent, so each fixed rule has a firing control (positive control) beside its silent case.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v156-fp1-$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Checks = 0
function Check($n, $ok, $d = '') {
  $script:Checks++
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fix = (Resolve-Path "$PSScriptRoot\..\fixtures\v156\FP1").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$Src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $Src | Out-Null
Copy-Item "$Fix\*" $Src
$Db = Join-Path $WorkDir 'p.sqlite'
$Cfg = Join-Path $WorkDir 'cfg.json'
[IO.File]::WriteAllText($Cfg, '{}', [Text.Encoding]::ASCII)
& { $ErrorActionPreference = 'Continue'; & $Exe index $Src --db $Db 2>&1 | ForEach-Object { "$_" } } | Out-Null

$FixedRules = @('field-could-be-local', 'ambiguous-unit-reference')
function Get-Found([string[]]$Argv) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe @Argv --json 2>$null }
  $txt = ($raw | Where-Object { $_ -is [string] }) -join "`n"
  $i = $txt.IndexOf('['); if ($i -lt 0) { return @() }
  return ,@($txt.Substring($i) | ConvertFrom-Json | ForEach-Object { $_ } | ForEach-Object {
    $r = if ($_.rule_id) { $_.rule_id } else { $_.rule }
    $p = if ($_.file_path) { $_.file_path } elseif ($_.path) { $_.path } else { $_.file }
    "{0}:{1} {2}" -f (Split-Path $p -Leaf), $_.start_line, $r })
}
function Get-Wanted([string]$Rule) {
  return ,@(Get-ChildItem $Src -Filter *.pas | ForEach-Object { $f = $_; $n = 0
    [IO.File]::ReadAllLines($f.FullName) | ForEach-Object { $n++; if ($_ -match "// FIRE $Rule\b") { "{0}:{1} {2}" -f $f.Name, $n, $Rule } } })
}
function Compare-Rule([string]$Rule) {
  $want = Get-Wanted $Rule
  $got  = Get-Found @('lint-all', '--db', $Db, '--config', $Cfg, '--rule', $Rule)
  Check "$Rule has firing controls" ($want.Count -gt 0)
  foreach ($w in $want) { Check "fires $w" ($got -contains $w) }
  $extra = @($got | Where-Object { $want -notcontains $_ })
  Check "$Rule is silent elsewhere" ($extra.Count -eq 0) ($extra -join ', ')
}

# positive-control: field-could-be-local (WriteOnly.pas), ambiguous-unit-reference (uAmbUse.pas: KOther differs)
Write-Host 'FIXED RULES' -ForegroundColor Cyan
foreach ($r in $FixedRules) { Compare-Rule $r }

Write-Host 'THE CATALOG' -ForegroundColor Cyan
$rulesTxt = (& { $ErrorActionPreference = 'Continue'; & $Exe rules --json 2>$null } | Where-Object { $_ -is [string] }) -join "`n"
foreach ($r in $FixedRules) {
  Check "rules lists $r" ($rulesTxt -match [regex]::Escape("`"$r`""))
}

if ($script:Failed) { Write-Host ("FAIL ({0} checks)" -f $script:Checks) -ForegroundColor Red; exit 1 }
Write-Host ("PASS ({0} checks)" -f $script:Checks) -ForegroundColor Green
exit 0
} finally {
  if (($WorkDir -like "$env:TEMP\drag-lint-v156-fp1-$PID*") -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
