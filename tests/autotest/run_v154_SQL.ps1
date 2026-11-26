<#
  run_v154_SQL.ps1 -- 1.54 lane SQL: sql-param-mismatch, query-in-loop and the ParamByName part of
  field-by-name-in-loop, on tests\fixtures\v154\SQL. A fixture line that must report carries "// FIRE <rule>";
  every other line must stay silent, so each rule has firing and silent controls in the same run.
  Also: lint on a file the index does not know, and the option that switches the ParamByName part on.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v154-sql-$PID"
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
$Fix = (Resolve-Path "$PSScriptRoot\..\fixtures\v154\SQL").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$Src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $Src | Out-Null
Copy-Item "$Fix\*" $Src
$Db = Join-Path $WorkDir 'p.sqlite'
$OffCfg = Join-Path $WorkDir 'off.json'
$OnCfg  = Join-Path $WorkDir 'on.json'
[IO.File]::WriteAllText($OffCfg, '{}', [Text.Encoding]::ASCII)
[IO.File]::WriteAllText($OnCfg, '{"thresholds":{"field-by-name-in-loop.param_by_name":1}}', [Text.Encoding]::ASCII)
& { $ErrorActionPreference = 'Continue'; & $Exe index $Src --db $Db 2>&1 | ForEach-Object { "$_" } } | Out-Null

# "file:line rule" of every finding of $Rules; $Verb lint-all (index) or lint (one file, no index)
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
function Compare-Rule([string]$Rule, [string]$Cfg) {
  $want = Get-Wanted $Rule
  $got  = Get-Found @('lint-all', '--db', $Db, '--config', $Cfg, '--rule', $Rule)
  Check "$Rule has firing controls" ($want.Count -gt 0)
  foreach ($w in $want) { Check "fires $w" ($got -contains $w) }
  $extra = @($got | Where-Object { $want -notcontains $_ })
  Check "$Rule is silent elsewhere" ($extra.Count -eq 0) ($extra -join ', ')
}

Write-Host 'WITH THE INDEX' -ForegroundColor Cyan
# positive-control: sql-param-mismatch
Compare-Rule 'sql-param-mismatch' $OffCfg
# positive-control: query-in-loop
Compare-Rule 'query-in-loop' $OffCfg
Compare-Rule 'field-by-name-in-loop' $OnCfg

# 1.55 QIL (owner Q8): query-in-loop is ON by default -- no --rule, no --enable, an empty config
$def = Get-Found @('lint-all', '--db', $Db, '--config', $OffCfg)
$wantQ = Get-Wanted 'query-in-loop'
$gotQ = @($def | Where-Object { $_ -like '* query-in-loop' })
Check 'query-in-loop fires with no --rule and no --enable (default ON)' (($wantQ.Count -gt 0) -and (@($wantQ | Where-Object { $gotQ -notcontains $_ }).Count -eq 0)) ("want $($wantQ.Count) got $($gotQ.Count)")

Write-Host 'THE OPTION' -ForegroundColor Cyan
$off = Get-Found @('lint-all', '--db', $Db, '--config', $OffCfg, '--rule', 'field-by-name-in-loop')
Check 'ParamByName part is off by default, FieldByName is not' (($off.Count -eq 1) -and ($off[0] -like 'ArrayDml.pas:30 *')) ($off -join ', ')
$on = Get-Found @('lint-all', '--db', $Db, '--config', $OnCfg, '--rule', 'field-by-name-in-loop')
Check 'a loop with FieldByName is reported once (its fix must not be offered twice)' (@($on | Where-Object { $_ -like 'ArrayDml.pas:30 *' }).Count -eq 1) ($on -join ', ')

Write-Host 'A FILE THE INDEX DOES NOT KNOW' -ForegroundColor Cyan
$Other = Join-Path $WorkDir 'other'
New-Item -ItemType Directory $Other | Out-Null
[IO.File]::WriteAllText((Join-Path $Other 'Lone.pas'), "unit Lone;`r`ninterface`r`nimplementation`r`nend.`r`n", [Text.Encoding]::ASCII)
$OtherDb = Join-Path $WorkDir 'other.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $Other --db $OtherDb 2>&1 | ForEach-Object { "$_" } } | Out-Null
$noix = Get-Found @('lint', (Join-Path $Src 'ParamCases.pas'), '--db', $OtherDb, '--config', $OffCfg, '--rule', 'sql-param-mismatch')
$all = Get-Wanted 'sql-param-mismatch'   # assigned first: piping the call would pass the array as ONE object
$wantLocal = @($all | Where-Object { $_ -like 'ParamCases*' })
Check 'the fixture has five local cases' ($wantLocal.Count -eq 5) "$($wantLocal.Count)"
$missed = @($wantLocal | Where-Object { $noix -notcontains $_ })
Check 'locals are judged without the index, the constant of another unit is not' ($missed.Count -eq 1) "missed: $($missed -join ', ') got: $($noix -join ', ')"
$extra = @($noix | Where-Object { $wantLocal -notcontains $_ })
Check 'and nothing else is' ($extra.Count -eq 0) ($extra -join ', ')
$m = Get-Found @('lint', (Join-Path $Src 'DataMod.pas'), '--db', $OtherDb, '--config', $OffCfg, '--rule', 'sql-param-mismatch')
Check 'form datasets need the index' ($m.Count -eq 0) ($m -join ', ')
$m = Get-Found @('lint', (Join-Path $Src 'DataMod.pas'), '--db', $Db, '--config', $OffCfg, '--rule', 'sql-param-mismatch')
Check 'positive control: lint with the index reports them' ($m.Count -eq 2) ($m -join ', ')

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  if (($WorkDir -like "$env:TEMP\drag-lint-v154-sql-$PID*") -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
