<#
  run_lint_rule_help.ps1 -- `--rule help` lists every rule, on every lint form
  (BACKLOG LINT-PROJECT-RULE-HELP).

  MEASURED before the fix: `lint --project P --rule help` answered ERROR unknown rule,
  exit 2, and --help named only unit-not-in-dpr for that form though unit-not-in-library
  runs there too. `lint-project --rule help`, or any typo, answered "0 finding(s)", exit 0.

  CHECKS
    1  POSITIVE CONTROL: the catalog is real (over 100 ids)
    2  lint --project --rule help: exit 0, every catalog id listed, none missing
    3  ...the project-level rules are listed apart, the rest are marked as needing a unit
    4  lint <file> --rule help: exit 0, every catalog id
    5  lint-project --rule help: exit 0, every catalog id
    6  --json form: rules[] = the catalog
    7  a real unknown rule stays exit 2, on lint and on lint-project
    8  every rule lint-project's own usage line names is accepted

  Usage: pwsh -File tests\autotest\run_lint_rule_help.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
. (Join-Path $PSScriptRoot 'exe-hint.ps1')
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:fail = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ("draglint_rule_help-{0}" -f $PID)
[IO.Directory]::CreateDirectory($scratch) | Out-Null
[IO.File]::WriteAllText("$scratch\uA.pas", "unit uA;`r`ninterface`r`nimplementation`r`nend.`r`n", [Text.Encoding]::ASCII)
[IO.File]::WriteAllText("$scratch\App.dpr", "program App;`r`nuses uA in 'uA.pas';`r`nbegin`r`nend.`r`n", [Text.Encoding]::ASCII)
$db = "$scratch\fx.sqlite"
$o = & $exePath index --project "$scratch\App.dpr" --db $db 2>&1
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $db)) { Write-Host "FATAL: fixture did not index: $($o | Select-Object -Last 2)" -ForegroundColor Red; Get-ExeStartFailureHint $LASTEXITCODE | Write-Host; exit 2 }

$catalog = @(((& $exePath rules --json 2>$null) -join "`n" | ConvertFrom-Json).rules.id)
Check '1 catalog is real' ($catalog.Count -gt 100) "count=$($catalog.Count)"

function Missing([string[]]$lines) {
  $have = @{}
  foreach ($l in $lines) { $have[$l.Trim()] = $true }
  return @($catalog | Where-Object { -not $have.ContainsKey($_) })
}

$out = @(& $exePath lint --project "$scratch\App.dpr" --rule help --db $db 2>$null); $code = $LASTEXITCODE
Check '2a lint --project --rule help: exit 0' ($code -eq 0) "exit=$code"
$m = Missing $out
Check '2b no catalog rule omitted' ($m.Count -eq 0) "missing $($m.Count): $($m | Select-Object -First 5)"
$text = $out -join "`n"
$ixProject = $text.IndexOf('unit-not-in-library'); $ixRest = $text.IndexOf('need a unit')
Check '3 project-level rules apart, before the rest' (($ixProject -ge 0) -and ($ixRest -gt $ixProject) -and ($text.IndexOf('unit-not-in-dpr') -lt $ixRest)) "project=$ixProject rest=$ixRest"

$out = @(& $exePath lint "$scratch\uA.pas" --rule help --db $db 2>$null); $code = $LASTEXITCODE
$m = Missing $out
Check '4 lint <file> --rule help' (($code -eq 0) -and ($m.Count -eq 0)) "exit=$code missing $($m.Count)"

$out = @(& $exePath lint-project --db $db --rule help 2>$null); $code = $LASTEXITCODE
$m = Missing $out
Check '5 lint-project --rule help' (($code -eq 0) -and ($m.Count -eq 0)) "exit=$code missing $($m.Count)"

$raw = (& $exePath lint --project "$scratch\App.dpr" --rule help --json --db $db 2>$null) -join "`n"
$doc = try { $raw | ConvertFrom-Json } catch { $null }
$diff = if ($doc) { @(Compare-Object @($doc.rules) $catalog) } else { @('no document') }
Check '6 --json rules[] = catalog' ($diff.Count -eq 0) "diff $($diff.Count) raw=$($raw.Substring(0, [Math]::Min(80, $raw.Length)))"

& $exePath lint "$scratch\uA.pas" --rule no-such-rule --db $db *> $null
Check '7a lint: unknown rule exit 2' ($LASTEXITCODE -eq 2) "exit=$LASTEXITCODE"
& $exePath lint-project --db $db --rule no-such-rule *> $null
Check '7b lint-project: unknown rule exit 2' ($LASTEXITCODE -eq 2) "exit=$LASTEXITCODE"

$entry = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\..\features\entries\lint-project.json'))
$named = [regex]::Match($entry, '--rule ([a-z|-]+)\]').Groups[1].Value -split '\|'
$rejected = @()
foreach ($r in $named) {
  & $exePath lint-project --db $db --rule $r *> $null
  if ($LASTEXITCODE -eq 2) { $rejected += $r }
}
Check "8 every rule lint-project names is accepted ($($named.Count))" (($named.Count -gt 5) -and ($rejected.Count -eq 0)) "rejected: $rejected"

[IO.Directory]::Delete($scratch, $true)
if ($script:fail) { Write-Host 'run_lint_rule_help: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lint_rule_help: PASS' -ForegroundColor Green
exit 0
