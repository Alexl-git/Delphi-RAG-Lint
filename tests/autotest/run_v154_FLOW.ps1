<#
  run_v154_FLOW.ps1 -- 1.54 lane FLOW: the eight rules of docs\wiki\v154-flow-rules.md on tests\fixtures\v154\FLOW.
  A fixture line that must report carries "// FIRE <rule>"; every other line must stay silent, so each rule has
  firing and silent controls in the same run. Also: which rules need the index, and the OFF rules.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v154-flow-$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fix = (Resolve-Path "$PSScriptRoot\..\fixtures\v154\FLOW").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$Src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $Src | Out-Null
Copy-Item "$Fix\*" $Src
$Db  = Join-Path $WorkDir 'p.sqlite'
$Cfg = Join-Path $WorkDir 'cfg.json'
[IO.File]::WriteAllText($Cfg, '{}', [Text.Encoding]::ASCII)
& { $ErrorActionPreference = 'Continue'; & $Exe index $Src --db $Db 2>&1 | ForEach-Object { "$_" } } | Out-Null

# "file:line rule" of every finding of the run
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
    Get-Content $f.FullName | ForEach-Object { $n++; if ($_ -match "// FIRE $Rule\b") { "{0}:{1} {2}" -f $f.Name, $n, $Rule } } })
}

# positive-control: managed-result-read-first
# positive-control: same-variable-two-var-params
# positive-control: address-of-nested-routine
# positive-control: var-param-never-written
# positive-control: value-param-assigned
# positive-control: constant-return
# positive-control: redundant-field-init
# positive-control: absolute-overlay
$AllRules = 'managed-result-read-first', 'same-variable-two-var-params', 'address-of-nested-routine', 'var-param-never-written',
  'value-param-assigned', 'constant-return', 'redundant-field-init', 'absolute-overlay'
$NeedIndex = 'same-variable-two-var-params', 'var-param-never-written', 'constant-return'
$OffRules  = 'var-param-never-written', 'value-param-assigned', 'constant-return', 'redundant-field-init', 'absolute-overlay'

Write-Host 'WITH THE INDEX' -ForegroundColor Cyan
foreach ($rule in $AllRules) {
  $want = Get-Wanted $rule
  $got  = Get-Found @('lint-all', '--db', $Db, '--config', $Cfg, '--rule', $rule)
  Check "$rule has at least three firing controls" ($want.Count -ge 3) "$($want.Count)"
  foreach ($w in $want) { Check "fires $w" ($got -contains $w) }
  $extra = @($got | Where-Object { $want -notcontains $_ })
  Check "$rule is silent elsewhere" ($extra.Count -eq 0) ($extra -join ', ')
  $twice = @($got | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
  Check "$rule reports a line once" ($twice.Count -eq 0) ($twice -join ', ')
}

Write-Host 'A FILE THE INDEX DOES NOT KNOW' -ForegroundColor Cyan
$Other = Join-Path $WorkDir 'other'
New-Item -ItemType Directory $Other | Out-Null
[IO.File]::WriteAllText((Join-Path $Other 'Lone.pas'), "unit Lone;`r`ninterface`r`nimplementation`r`nend.`r`n", [Text.Encoding]::ASCII)
$OtherDb = Join-Path $WorkDir 'other.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $Other --db $OtherDb 2>&1 | ForEach-Object { "$_" } } | Out-Null
foreach ($rule in $AllRules) {
  $want = Get-Wanted $rule
  $file = ($want[0] -split ':')[0]
  $want = @($want | Where-Object { $_ -like "${file}:*" })
  $got  = Get-Found @('lint', (Join-Path $Src $file), '--db', $OtherDb, '--config', $Cfg, '--rule', $rule)
  if ($NeedIndex -contains $rule) { Check "$rule is silent without the index" ($got.Count -eq 0) ($got -join ', ') }
  else {
    Check "$rule reports the same lines of $file without the index" ((($got | Sort-Object) -join ' ') -eq (($want | Sort-Object) -join ' ')) ($got -join ', ')
  }
}

Write-Host 'DEFAULTS' -ForegroundColor Cyan
$default = Get-Found @('lint-all', '--db', $Db, '--config', $Cfg)
foreach ($rule in $AllRules) {
  $n = @($default | Where-Object { $_ -like "* $rule" }).Count
  if ($OffRules -contains $rule) { Check "$rule is OFF by default" ($n -eq 0) "$n findings" }
  else { Check "$rule is ON by default" ($n -eq (Get-Wanted $rule).Count) "$n findings" }
}
$on = Get-Found @('lint-all', '--db', $Db, '--config', $Cfg, '--enable', ($OffRules -join ','))
foreach ($rule in $OffRules) {
  $n = @($on | Where-Object { $_ -like "* $rule" }).Count
  Check "--enable turns $rule on" ($n -eq (Get-Wanted $rule).Count) "$n findings"
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  if (($WorkDir -like "$env:TEMP\drag-lint-v154-flow-*") -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
