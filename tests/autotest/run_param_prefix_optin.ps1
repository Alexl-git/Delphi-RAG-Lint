<#
  run_param_prefix_optin.ps1 -- owner ruling 2026-11-20 (card D): the param-name-prefix
  rename fix is OPT-IN. The rule stays ON for detection; its fix runs ONLY when the
  rule is named (--rule param-name-prefix, --enable param-name-prefix or
  --fix-rule param-name-prefix) -- NEVER in a blanket lint-all --fix --apply.

  CASE BLANKET : lint-all --fix --apply            -> unprefixed params UNCHANGED
  CASE RULE    : lint-all --rule param-name-prefix --fix --apply -> renamed
  CASE ENABLE  : lint-all --enable param-name-prefix --fix --apply -> renamed
  CASE FIXRULE : lint-all --fix --fix-rule param-name-prefix --apply -> renamed
  CASE DETECT  : the rule still reports (detection stays on by default)
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-param-prefix-optin-$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$env:DRAGLINT_RENAME_TEST_UNGATED = '1'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

$Body = @'
unit UNITNAME;
interface
procedure Plain(Count: Integer);
implementation
procedure Plain(Count: Integer);
begin
  Count:= Count + 1;
end;
end.
'@
function New-Case([string]$Name) {
  $dir = Join-Path $WorkDir $Name
  $src = Join-Path $dir 'src'
  New-Item -ItemType Directory $src | Out-Null
  $file = Join-Path $src "$Name.pas"
  $norm = ($Body -replace 'UNITNAME', $Name) -replace "`r`n", "`n" -replace "`n", "`r`n"
  [IO.File]::WriteAllText($file, $norm, [Text.Encoding]::ASCII)
  $cfg = Join-Path $dir 'cfg.json'
  [IO.File]::WriteAllText($cfg, '{}', [Text.Encoding]::ASCII)
  $db = Join-Path $dir 'p.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $Exe index $src --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
  return [pscustomobject]@{ File = $file; Db = $db; Cfg = $cfg }
}
function Run-Fix($c, [string[]]$Extra) {
  & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $c.Db --config $c.Cfg @Extra --fix --apply --no-compile-gate --no-backup --quiet 2>&1 | ForEach-Object { "$_" } } | Out-Null
  return (Get-Content -Raw $c.File)
}
$renamed = 'procedure Plain\(pCount: Integer\);[\s\S]*pCount:= pCount \+ 1;'

Write-Host 'CASE DETECT: rule still reports by default' -ForegroundColor Cyan
$d = New-Case 'detect'
$raw = & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $d.Db --config $d.Cfg --rule param-name-prefix --json 2>$null }
Check 'DETECT: param-name-prefix reports Count' ((($raw | Where-Object { $_ -is [string] }) -join "`n") -match 'Count')

Write-Host 'CASE BLANKET: lint-all --fix --apply' -ForegroundColor Cyan
$b = New-Case 'blanket'
$a = Run-Fix $b @()
Check 'BLANKET: Count NOT renamed' ($a -cmatch 'procedure Plain\(Count: Integer\);' -and $a -cnotmatch 'pCount') $a

Write-Host 'CASE RULE: --rule param-name-prefix' -ForegroundColor Cyan
$a = Run-Fix (New-Case 'byrule') @('--rule', 'param-name-prefix')
Check 'RULE: Count renamed to pCount' ($a -cmatch $renamed) $a

Write-Host 'CASE ENABLE: --enable param-name-prefix' -ForegroundColor Cyan
$a = Run-Fix (New-Case 'byenable') @('--enable', 'param-name-prefix')
Check 'ENABLE: Count renamed to pCount' ($a -cmatch $renamed) $a

Write-Host 'CASE FIXRULE: --fix-rule param-name-prefix' -ForegroundColor Cyan
$a = Run-Fix (New-Case 'byfixrule') @('--fix-rule', 'param-name-prefix')
Check 'FIXRULE: Count renamed to pCount' ($a -cmatch $renamed) $a

if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0
} catch { Write-Host "FATAL: $_" -ForegroundColor Red; exit 2 }
