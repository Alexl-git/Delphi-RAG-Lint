<#
  run_v156_G32.ps1 -- 1.56 lane G32: math-single-overload (G-32) on
  tests\fixtures\v156\G32. A fixture line that must report carries "// FIRE <rule>"; every other line must
  stay silent, so each rule has firing and silent controls in one run. Both rules are OFF by default:
  the run also checks that a lint-all without --rule reports neither.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v156-g32-$PID"
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
$Fix = (Resolve-Path "$PSScriptRoot\..\fixtures\v156\G32").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$Src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $Src | Out-Null
Copy-Item "$Fix\*" $Src
$Db = Join-Path $WorkDir 'p.sqlite'
$Cfg = Join-Path $WorkDir 'cfg.json'
[IO.File]::WriteAllText($Cfg, '{}', [Text.Encoding]::ASCII)
& { $ErrorActionPreference = 'Continue'; & $Exe index $Src --db $Db 2>&1 | ForEach-Object { "$_" } } | Out-Null

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

# positive-control: Single context fires (FIRE lines); Double context, mixed args, unknown types, user Max stay silent
Write-Host 'THE RULE' -ForegroundColor Cyan
Compare-Rule 'math-single-overload'

Write-Host 'DEFAULT OFF' -ForegroundColor Cyan
$all = Get-Found @('lint-all', '--db', $Db, '--config', $Cfg)
$leak = @($all | Where-Object { $_ -match 'math-single-overload' })
Check 'the rule does not fire without --rule' ($leak.Count -eq 0) ($leak -join ', ')

Write-Host 'THE CATALOG' -ForegroundColor Cyan
$rulesTxt = (& { $ErrorActionPreference = 'Continue'; & $Exe rules --json 2>$null } | Where-Object { $_ -is [string] }) -join "`n"
foreach ($r in 'math-single-overload') {
  Check "rules lists $r" ($rulesTxt -match [regex]::Escape("`"$r`""))
}

if ($script:Failed) { Write-Host ("FAIL ({0} checks)" -f $script:Checks) -ForegroundColor Red; exit 1 }
Write-Host ("PASS ({0} checks)" -f $script:Checks) -ForegroundColor Green
exit 0
} finally {
  if (($WorkDir -like "$env:TEMP\drag-lint-v156-g32-$PID*") -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
