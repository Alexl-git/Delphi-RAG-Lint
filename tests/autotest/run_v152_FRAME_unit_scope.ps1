<#
  run_v152_FRAME_unit_scope.ps1 -- 1.52 D1 "Disable in this unit" (FRAME handover 2).

  A "rule_overrides": { "<rule>": { "exclude_units": ["<Unit>"] } } entry in the lint config
  drops that rule's findings in that unit, in BOTH `lint` (DoLint) and `lint-all` is covered by
  the same helper (DropUnitExcludedFindings). This runner drives `lint` on a fixture unit:
    1. baseline (no overrides): the fixture yields at least one finding; its first rule = R.
    2. exclude R in the fixture unit -> no R finding left (the fix).
    3. positive control: exclude R in ANOTHER unit -> the R finding stays.
    4. positive control: exclude ANOTHER rule in the fixture unit -> the R finding stays.
  Against an engine without the call site (1.51) check 2 FAILS.

  Usage: pwsh -File tests\autotest\run_v152_FRAME_unit_scope.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $Root 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path $Exe)) { Write-Host "SKIP: engine not found: $Exe"; exit 0 }

$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v152-unitscope-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void](New-Item -ItemType Directory -Force $Work)
$Unit = 'UnitScopeFixture'
$Pas = Join-Path $Work "$Unit.pas"
$Src = @(
  "unit $Unit;", '', 'interface', '', 'procedure DoIt(A, B, C: Integer);', '', 'implementation', '',
  'uses SysUtils;', '',
  'procedure DoIt(A, B, C: Integer);', 'var', '  X: Integer;', 'begin',
  '  try', '    X:= A div 0;', '  except', '  end;',
  '  with TStringList.Create do Free;', 'end;', '', 'end.', '')
[IO.File]::WriteAllText($Pas, ($Src -join "`r`n"), [Text.Encoding]::ASCII)

$Pass = 0; $Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  PASS  $Name" } else { $script:Fail++; Write-Host "  FAIL  $Name  $Detail" }
}
function RunLint([string]$CfgJson) {
  $Cfg = Join-Path $Work 'cfg.json'
  [IO.File]::WriteAllText($Cfg, $CfgJson, [Text.Encoding]::ASCII)
  Push-Location $Work
  try { $Out = & { $ErrorActionPreference = 'Continue'; & $Exe lint $Pas --config $Cfg --json 2>$null } } finally { Pop-Location }
  $Txt = ($Out -join "`n")
  if ($Txt.Trim() -eq '') { return ,@() }
  $J = $Txt | ConvertFrom-Json | ForEach-Object { $_ }
  if ($J -is [array]) { return ,@($J) }
  if ($null -ne $J.findings) { return ,@($J.findings) }
  return ,@($J)
}
function RuleOf($F) { if ($null -ne $F.rule_id) { return [string]$F.rule_id } return [string]$F.rule }

try {
  $Base = RunLint '{}'
  Check 'baseline: fixture yields a finding' ($Base.Count -gt 0) "count=$($Base.Count)"
  if ($Base.Count -eq 0) { throw 'no baseline finding; cannot continue' }
  $R = RuleOf $Base[0]
  Check 'baseline: the finding carries a rule id' ($R -ne '') ''
  $BaseR = @($Base | Where-Object { (RuleOf $_) -eq $R }).Count
  Write-Host "  rule R = $R ($BaseR finding(s))"

  $Excl = RunLint ('{ "rule_overrides": { "' + $R + '": { "exclude_units": ["' + $Unit + '"] } } }')
  $ExclR = @($Excl | Where-Object { (RuleOf $_) -eq $R }).Count
  Check 'exclude R in this unit -> no R finding' ($ExclR -eq 0) "got $ExclR"
  Check 'exclude R in this unit -> other rules unchanged' (($Excl.Count) -eq ($Base.Count - $BaseR)) "got $($Excl.Count), want $($Base.Count - $BaseR)"

  $Other = RunLint ('{ "rule_overrides": { "' + $R + '": { "exclude_units": ["SomeOtherUnit"] } } }')
  Check 'control: exclude R in another unit -> R stays' (@($Other | Where-Object { (RuleOf $_) -eq $R }).Count -eq $BaseR) ''

  $OtherRule = RunLint ('{ "rule_overrides": { "no-such-rule-xyz": { "exclude_units": ["' + $Unit + '"] } } }')
  Check 'control: exclude another rule in this unit -> R stays' (@($OtherRule | Where-Object { (RuleOf $_) -eq $R }).Count -eq $BaseR) ''
}
catch { $Fail++; Write-Host "  FAIL  exception: $($_.Exception.Message)" }
finally { try { [IO.Directory]::Delete($Work, $true) } catch { } }

Write-Host "$Pass passed, $Fail failed"
if ($Fail -gt 0) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
