<#
  run_rule_repeated_refused.ps1 -- a second, DIFFERENT --rule is a usage error (N-02).

  THE DEFECT. ParseArgs stored --rule in one string, so
  `lint <file> --rule unused-local --rule empty-except` silently ran ONLY
  empty-except: the first rule's findings vanished and the run looked clean
  for it. One --rule per run is the contract (--rule narrows execution and opts
  an OFF rule in, both per id), so a second id is refused loudly, exit 2.

    A. --rule X --rule Y (different) -> exit 2, stderr names both ids.
    B. POSITIVE CONTROL: --rule X alone reports X's finding (the fixture has one),
       so A's refusal is not a fixture that reports nothing anyway.
    C. --rule X --rule X (same id twice) is harmless and still runs.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rule-repeated-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$pas = Join-Path $WorkDir 'URep.pas'
[IO.File]::WriteAllText($pas, ((@'
unit URep;

interface

procedure Help;

implementation

procedure Help;
var
  Idle: Integer;
begin
end;

end.
'@ -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)

function LintRun([string[]]$Extra) {
  Push-Location $WorkDir
  try {
    $out = & $Exe lint $pas @Extra 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
  } finally { Pop-Location }
}

Write-Host 'B. CONTROL: one --rule reports its finding' -ForegroundColor Cyan
$b = LintRun @('--rule', 'unused-local')
Check 'B1 unused-local reported' ($b.Out -match 'URep\.pas:\d+:\d+\s+\[\w+\]\s+unused-local') "exit=$($b.Code)"

Write-Host ''
Write-Host 'A. two different --rule ids -> refused' -ForegroundColor Cyan
$a = LintRun @('--rule', 'unused-local', '--rule', 'empty-except')
Check 'A1 exit 2' ($a.Code -eq 2) "exit=$($a.Code)"
Check 'A2 names both ids' (($a.Out -match 'unused-local') -and ($a.Out -match 'empty-except') -and ($a.Out -match '--rule')) ''
Check 'A3 does not lint (no finding line)' (-not ($a.Out -match 'URep\.pas:\d+:\d+')) 'RED = the first --rule was silently dropped'

Write-Host ''
Write-Host 'C. the same id twice still runs' -ForegroundColor Cyan
$c = LintRun @('--rule', 'unused-local', '--rule', 'unused-local')
Check 'C1 not refused, finding reported' (($c.Code -ne 2) -and ($c.Out -match 'URep\.pas:\d+:\d+\s+\[\w+\]\s+unused-local')) "exit=$($c.Code)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\drag-lint-rule-repeated-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
