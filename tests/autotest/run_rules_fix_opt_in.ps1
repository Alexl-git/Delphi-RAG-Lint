<#
  run_rules_fix_opt_in.ps1 -- `rules --json` marks the naming fixes
  `fix_opt_in`, and only them.

  THE DEFECT THIS PINS (owner report 2026-10-13, ORM3 COMMON\BASICS.PAS):
  the IDE built its "Fix all in unit (N)" count from `"fixable": true` alone.
  76 const-casing + 2 type-name-prefix findings made N = 78, and the run then
  reported "no fixable findings": the naming fixes rename a symbol everywhere
  it is used, so `lint --fix` applies them only when "autofix": [...] in
  drag-lint-lint.json opts them in. The catalog now says so per rule, from the
  same list the fixer reads (OPT_IN_FIX_RULE_IDS).

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:fail = $true }
}
Write-Host '== rules --json: fix_opt_in marks the naming fixes ==' -ForegroundColor Cyan
$rules = @((& (Resolve-Path $Exe).Path rules --json 2>$null | ConvertFrom-Json).rules)
Check 'catalog read' ($rules.Count -gt 100) "rules=$($rules.Count)"

$naming = @('const-casing','field-name-prefix','local-field-prefix','local-var-casing','method-pascalcase','param-name-prefix','type-name-prefix')
$optIn  = @($rules | Where-Object { $_.fix_opt_in -eq $true } | ForEach-Object { $_.id } | Sort-Object)
Check 'O1 every rule carries the field' (@($rules | Where-Object { $null -eq $_.PSObject.Properties['fix_opt_in'] }).Count -eq 0) ''
Check 'O2 exactly the seven naming fixes are opt-in' ((Compare-Object $optIn $naming) -eq $null) "got: $($optIn -join ',')"
Check 'O3 every opt-in rule is also fixable' (@($rules | Where-Object { $_.fix_opt_in -and -not $_.fixable }).Count -eq 0) ''
# CONTROL: the field must not swallow the ordinary fixes, or "Fix all" would be dead.
$plain = @($rules | Where-Object { $_.fixable -and -not $_.fix_opt_in } | ForEach-Object { $_.id })
Check 'C1 CONTROL: ordinary fixes stay plain (unused-local, redundant-parentheses)' `
  (($plain -contains 'unused-local') -and ($plain -contains 'redundant-parentheses')) "plain=$($plain.Count)"

# ONE FINDING ASKED FOR BY LINE AND RULE IS THE OPT-IN ("Fix it" in the IDE);
# a batch run still is not. Owner, 2026-10-13: "We can change them to PascalCase".
$work = Join-Path ([IO.Path]::GetTempPath()) ("draglint-optin-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
  $u = Join-Path $work 'uOptIn.pas'
  [IO.File]::WriteAllText($u, ((@'
unit uOptIn;

interface

const
  wrStr = 'x';

function Get: string;

implementation

function Get: string;
begin
  Result:= wrStr;
end;

end.
'@ -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
  $dpr = Join-Path $work 'OptIn.dpr'
  [IO.File]::WriteAllText($dpr, "program OptIn;`r`nuses`r`n  uOptIn in 'uOptIn.pas';`r`nbegin`r`nend.`r`n", [Text.Encoding]::ASCII)
  $db = Join-Path $work 'optin.sqlite'
  $ExeP = (Resolve-Path $Exe).Path
  & $ExeP index --project $dpr --db $db 2>&1 | Out-Null
  $line = @(& $ExeP lint $u --db $db --rule const-casing --json 2>$null | ConvertFrom-Json)[0].start_line
  Check 'P1 premise: wrStr is a const-casing finding' ($line -eq 6) "line=$line"
  $one   = (& $ExeP lint --file $u --db $db --fix --fix-line $line --fix-rule const-casing 2>&1 | Out-String)
  $batch = (& $ExeP lint --file $u --db $db --fix 2>&1 | Out-String)
  Check 'E1 --fix-line + --fix-rule on ONE naming finding is offered without the config opt-in' `
    ($one -match 'autofix: 1 fixable finding') (($one -split "`r?`n" | Where-Object { $_ -match 'autofix' }) -join ' | ')
  Check 'E2 CONTROL: a batch --fix still holds the naming fix back and says why' `
    (($batch -match 'no fixable findings') -and ($batch -match 'NOT opted in: const-casing')) (($batch -split "`r?`n" | Where-Object { $_ -match 'autofix|opted' }) -join ' | ')
  & $ExeP lint --file $u --db $db --fix --fix-line $line --fix-rule const-casing --apply 2>&1 | Out-Null
  $after = [IO.File]::ReadAllText($u)
  Check 'E3 --apply renames the declaration AND its use' `
    (($after -cmatch '(?m)^\s*WrStr = ') -and ($after -cmatch 'Result:= WrStr;') -and ($after -cnotmatch '\bwrStr\b')) ''
} finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
