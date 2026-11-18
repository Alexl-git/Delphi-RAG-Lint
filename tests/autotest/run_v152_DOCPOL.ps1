# run_v152_DOCPOL.ps1 -- lane v152 DOCPOL (ruling B2): missing-doc documents ALL real code.
#
#   m1  a DFM-bound handler WITH code (Button1Click) is a missing-doc finding   (RED on 1.51.1: R2c skipped it)
#   m2  an EMPTY DFM-bound handler (Button2Click) is NOT a finding
#   m3  control: an unbound undocumented method (Plain) IS a finding (the rule is live)
#   p1  doc-placeholder fires on the "Summary here ..." summary                  (RED: rule does not exist)
#   p2  control: the real summary (Real) is silent for doc-placeholder AND doc-malformed-summary
#   p3  doc-malformed-summary is OFF by default (no finding without --config)
#   p4  doc-malformed-summary fires on the declaration-shaped summary once enabled
#
# Fixtures: tests\lint\missing-doc-bound-handler.pas/.dfm, tests\lint\doc-placeholder.pas (copied to a scratch dir).
# Usage: pwsh -File run_v152_DOCPOL.ps1 -Exe <drag-lint.exe>
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-v152-docpol-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Fix  = (Resolve-Path (Join-Path $PSScriptRoot '..\lint')).Path
New-Item -ItemType Directory -Force $WorkDir | Out-Null
foreach ($f in 'missing-doc-bound-handler.pas', 'missing-doc-bound-handler.dfm', 'doc-placeholder.pas') { Copy-Item (Join-Path $Fix $f) $WorkDir -Force }
$db = Join-Path $WorkDir 'docpol.sqlite'
$cfgOn  = Join-Path $WorkDir 'on.json'
[IO.File]::WriteAllText($cfgOn, '{ "enabled": ["missing-doc", "doc-malformed-summary"] }', [Text.Encoding]::ASCII)

function LineOf([string]$File, [string]$Needle) {
  $i = 0
  foreach ($l in [IO.File]::ReadAllLines((Join-Path $WorkDir $File))) { $i++; if ($l.Contains($Needle)) { return $i } }
  throw "needle not in ${File}: $Needle"
}
function RunAll([string]$Cfg) {
  $a = @('lint-all', '--db', $db, '--json')
  if ($Cfg) { $a += @('--config', $Cfg) }
  $raw = (& $Exe @a 2>$null) -join "`n"
  $s = $raw.IndexOf('['); $e = $raw.LastIndexOf(']')
  if ($s -lt 0 -or $e -le $s) { return @() }
  return @(ConvertFrom-Json $raw.Substring($s, $e - $s + 1))
}
function Has($fs, $rule, $file, $line) { @($fs | Where-Object { $_.rule -eq $rule -and $_.file_path -like "*$file" -and $_.start_line -eq $line }).Count -gt 0 }

& $Exe index $WorkDir --db $db 2>&1 | Out-Null
$on  = RunAll $cfgOn
$off = RunAll ''
Write-Host ("  raw: {0} findings (on), {1} (default)" -f $on.Count, $off.Count)
Write-Host ("  rules seen (on): " + ((@($on | ForEach-Object { $_.rule }) | Sort-Object -Unique) -join ', '))

$b1 = LineOf 'missing-doc-bound-handler.pas' 'procedure Button1Click'
$b2 = LineOf 'missing-doc-bound-handler.pas' 'procedure Button2Click'
$pl = LineOf 'missing-doc-bound-handler.pas' 'procedure Plain;'
Check 'm1 bound handler with code: missing-doc fires' (Has $on 'missing-doc' 'missing-doc-bound-handler.pas' $b1)
Check 'm2 empty bound handler: silent' (-not (Has $on 'missing-doc' 'missing-doc-bound-handler.pas' $b2))
Check 'm3 control: unbound undocumented method fires' (Has $on 'missing-doc' 'missing-doc-bound-handler.pas' $pl)

$ph = LineOf 'doc-placeholder.pas' 'procedure Placeholder;'
$rl = LineOf 'doc-placeholder.pas' 'procedure Real;'
$mf = LineOf 'doc-placeholder.pas' 'procedure Malformed;'
# positive-control: doc-placeholder
Check 'p1 doc-placeholder fires on "Summary here ..."' (Has $off 'doc-placeholder' 'doc-placeholder.pas' $ph)
Check 'p2 real summary silent for both rules' (-not (Has $on 'doc-placeholder' 'doc-placeholder.pas' $rl) -and -not (Has $on 'doc-malformed-summary' 'doc-placeholder.pas' $rl))
Check 'p3 doc-malformed-summary OFF by default' (@($off | Where-Object { $_.rule -eq 'doc-malformed-summary' }).Count -eq 0)
# positive-control: doc-malformed-summary
Check 'p4 doc-malformed-summary fires once enabled' (Has $on 'doc-malformed-summary' 'doc-placeholder.pas' $mf)
Check 'p5 placeholder is not reported as malformed' (-not (Has $on 'doc-malformed-summary' 'doc-placeholder.pas' $ph))

Write-Host ("`nv152 DOCPOL: {0} passed, {1}" -f $script:Passed, $(if ($script:Failed) { 'FAILED' } else { 'ALL GREEN' }))
if ($script:Failed) { exit 1 }
