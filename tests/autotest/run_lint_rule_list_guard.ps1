<#
  run_lint_rule_list_guard.ps1 -- lane 148 RO items 1+2: `--rule` on a default-OFF rule enables it for
  the run, and `--rule a,b` takes a comma list (both enabled, report limited to the two, unknown id exit 2,
  --disable still wins).  Positive controls: each OFF rule is silent without --rule/--enable and
  reported with it; a third OFF rule (nil-comparison) stays out of a two-rule list.
  Usage: pwsh -File tests\autotest\run_lint_rule_list_guard.ps1 [-Exe <drag-lint.exe>] [-RulesDir <dir>]
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_rule_list_$PID"
)
$ErrorActionPreference = 'Stop'; $script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n)
  if (-not $ok) { if ($d) { Write-Host "      $d" }; $script:fail = $true }
}
function Ids($a) { @(($a | Out-String | ConvertFrom-Json) | % { $_.rule } | Sort-Object -Unique) -join ',' }
try {
  $exe = (Resolve-Path $Exe).Path; $rules = (Resolve-Path $RulesDir).Path
  $src = Join-Path $WorkDir 'src'; [void](New-Item -ItemType Directory -Path $src -Force)
  $pas = Join-Path $src 'uRuleList.pas'
  $text = @'
unit uRuleList;
interface
procedure Demo(O: TObject);
implementation
procedure Demo(O: TObject);
var X: Integer;
begin
  X:= 4242;
  if O = nil then X:= X + 977;
end;
end.
'@
  [IO.File]::WriteAllText($pas, (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
  $db = Join-Path $WorkDir 'g.sqlite'
  & $exe index $src --db $db --rules-dir $rules 2>&1 | Out-Null
  function L($more) { & $exe lint-all --db $db --rules-dir $rules --json @more 2>$null }
  Check 'control: OFF rules silent by default' ((Ids (L @())) -notmatch 'magic-literal|nil-comparison')
  Check 'control: --enable finds both' ((Ids (L @('--enable', 'magic-literal,nil-comparison'))) -match 'magic-literal' )
  Check 'item1: --rule on OFF rule returns it' ((Ids (L @('--rule', 'magic-literal'))) -eq 'magic-literal')
  Check 'item2: --rule a,b returns both' ((Ids (L @('--rule', 'magic-literal,nil-comparison'))) -eq 'magic-literal,nil-comparison')
  Check 'item2: list excludes a third OFF rule' ((Ids (L @('--rule', 'magic-literal,unused-local'))) -notmatch 'nil-comparison')
  Check 'item2: --disable still wins' ((Ids (L @('--rule', 'magic-literal,nil-comparison', '--disable', 'nil-comparison'))) -eq 'magic-literal')
  $null = L @('--rule', 'magic-literal,no-such-rule'); Check 'item2: unknown id in list exits 2' ($LASTEXITCODE -eq 2)
  $null = L @('--rule', 'no-such-rule'); Check 'unknown single id exits 2' ($LASTEXITCODE -eq 2)
}
finally { if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) } }
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
