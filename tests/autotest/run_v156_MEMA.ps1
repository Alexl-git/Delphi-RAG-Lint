<#
  run_v156_MEMA.ps1 -- 1.56 lane MEM-A: container-items-leak (G-01) on tests\fixtures\v156\MEMA.
  A fixture line that must report carries "// FIRE <rule>"; every other line must stay silent, so the rule has
  firing and silent controls in the same run. Also: the rule works without the index and is ON by default.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v156-mema-$PID"
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
$Fix = (Resolve-Path "$PSScriptRoot\..\fixtures\v156\MEMA").Path
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

# positive-control: container-items-leak
$Rule = 'container-items-leak'

Write-Host 'CATALOG' -ForegroundColor Cyan
$cat = (& { $ErrorActionPreference = 'Continue'; & $Exe rules --json 2>$null } | Where-Object { $_ -is [string] }) -join "`n"
Check "$Rule is in rules --json" ($cat -match ('"' + $Rule + '"'))

Write-Host 'WITH THE INDEX' -ForegroundColor Cyan
$want = Get-Wanted $Rule
$got  = Get-Found @('lint-all', '--db', $Db, '--config', $Cfg, '--rule', $Rule)
Check "$Rule has at least three firing controls" ($want.Count -ge 3) "$($want.Count)"
foreach ($w in $want) { Check "fires $w" ($got -contains $w) }
$extra = @($got | Where-Object { $want -notcontains $_ })
Check "$Rule is silent elsewhere" ($extra.Count -eq 0) ($extra -join ', ')
$twice = @($got | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
Check "$Rule reports a line once" ($twice.Count -eq 0) ($twice -join ', ')

Write-Host 'A FILE THE INDEX DOES NOT KNOW' -ForegroundColor Cyan
$Other = Join-Path $WorkDir 'other'
New-Item -ItemType Directory $Other | Out-Null
[IO.File]::WriteAllText((Join-Path $Other 'Lone.pas'), "unit Lone;`r`ninterface`r`nimplementation`r`nend.`r`n", [Text.Encoding]::ASCII)
$OtherDb = Join-Path $WorkDir 'other.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $Other --db $OtherDb 2>&1 | ForEach-Object { "$_" } } | Out-Null
$got = Get-Found @('lint', (Join-Path $Src 'MemaItems.pas'), '--db', $OtherDb, '--config', $Cfg, '--rule', $Rule)
$wantOne = @($want | Where-Object { $_ -like 'MemaItems.pas:*' })
Check "$Rule reports the same lines of MemaItems.pas without the index" ((($got | Sort-Object) -join ' ') -eq (($wantOne | Sort-Object) -join ' ')) ($got -join ', ')
$got = Get-Found @('lint', (Join-Path $Src 'MemaUser.pas'), '--db', $OtherDb, '--config', $Cfg, '--rule', $Rule)
Check "$Rule is silent on a class of another unit without the index" ($got.Count -eq 0) ($got -join ', ')

Write-Host 'DEFAULTS' -ForegroundColor Cyan
$default = Get-Found @('lint-all', '--db', $Db, '--config', $Cfg)
$n = @($default | Where-Object { $_ -like "* $Rule" }).Count
Check "$Rule is ON by default" (($want.Count -gt 0) -and ($n -eq $want.Count)) "$n findings"
$off = Get-Found @('lint-all', '--db', $Db, '--config', $Cfg, '--disable', $Rule)
$n = @($off | Where-Object { $_ -like "* $Rule" }).Count
Check "--disable turns $Rule off" ($n -eq 0) "$n findings"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  if (($WorkDir -like "$env:TEMP\drag-lint-v156-mema-$PID*") -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
