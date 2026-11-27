<#
  run_v156_OOB2.ps1 -- 1.56 lane OOB-2: dunitx-attribute-hygiene (G-26) and variant-in-loop (G-30) on
  tests\fixtures\v156\OOB2. A fixture line that must report carries "// FIRE <rule>"; every other line must
  stay silent, so each rule has firing and silent controls in the same run. Also: which rule needs the
  index (G-26 reads the attributes table), and the OFF rule (G-30).
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v156-oob2-$PID"
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
. (Join-Path $PSScriptRoot 'lib\EngineCompanions.ps1')
[void](Initialize-EngineCompanions -Exe $Exe)
$Exe = (Resolve-Path $Exe).Path
$Fix = (Resolve-Path "$PSScriptRoot\..\fixtures\v156\OOB2").Path
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

# positive-control: dunitx-attribute-hygiene
# positive-control: variant-in-loop
$AllRules  = 'dunitx-attribute-hygiene', 'variant-in-loop'
$NeedIndex = 'dunitx-attribute-hygiene'
$OffRules  = 'variant-in-loop'

Write-Host 'WITH THE INDEX' -ForegroundColor Cyan
foreach ($rule in $AllRules) {
  $want = Get-Wanted $rule
  $arg  = @('lint-all', '--db', $Db, '--config', $Cfg, '--rule', $rule)
  if ($OffRules -contains $rule) { $arg += @('--enable', $rule) }
  $got  = Get-Found $arg
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
  $arg  = @('lint', (Join-Path $Src $file), '--db', $OtherDb, '--config', $Cfg, '--rule', $rule)
  if ($OffRules -contains $rule) { $arg += @('--enable', $rule) }
  $got  = Get-Found $arg
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
  if (($WorkDir -like "$env:TEMP\drag-lint-v156-oob2-$PID*") -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
