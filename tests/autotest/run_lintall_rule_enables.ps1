<#
  run_lintall_rule_enables.ps1 -- `lint-all --rule <id>` means what
  `lint <file> --rule <id>` means (D4, docs\INBOX-defects-found-2026-09-23-rule-work.md).

  THE DEFECT, measured before the fix on the merged 1.17.0-alpha engine:
    * `lint <file> --rule magic-literal` reported the magic-literal finding --
      naming a rule opts an OFF-by-default rule back in for that run;
    * `lint-all --rule magic-literal` reported EVERYTHING ELSE (7 findings) and
      not the one rule asked for, which appeared only with --enable magic-literal
      as well. lint-all never read --rule except for ifdef-undefined-symbol.

  THE CONTRACT pinned here, for lint-all: --rule <id> (1) opts <id> in even when
  it ships OFF, and (2) narrows the report to <id>. Each assertion has its
  control: the bare run still omits the OFF rule (so (1) is not a default flip)
  and still reports the others (so (2) is not an empty run).

  Run from a NEUTRAL CWD, pwsh 7.
#>
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lintall-rule"
)
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
New-Item -ItemType Directory $WorkDir | Out-Null
$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir | Out-Null
[System.IO.File]::WriteAllText((Join-Path $srcDir 'uLaRule.pas'), ((@'
unit uLaRule;
interface
function IsHalf(const AValue: Double): Boolean;
procedure ReadsUnset;
implementation
function IsHalf(const AValue: Double): Boolean;
begin
  Result:= AValue = 1.5;
end;
procedure ReadsUnset;
var
  X, Y: Integer;
begin
  Y:= X + 1;
  Writeln(Y);
end;
end.
'@ -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)

$manifest = Join-Path $WorkDir 'manifest.drag-lint.json'
$mtext = '{' + [char]10 +
  '  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },' + [char]10 +
  '  "indexes": { "outDir": "out", "sections": [ { "name": "SecLaRule", "db": "larule.sqlite", "include": ["src"] } ] }' + [char]10 +
  '}'
[System.IO.File]::WriteAllText($manifest, $mtext, [System.Text.Encoding]::ASCII)
$db  = Join-Path $WorkDir 'out\larule.sqlite'
$pas = Join-Path $srcDir 'uLaRule.pas'
$nolib = Join-Path $WorkDir 'no-library.sqlite'

function FindingLines([string]$Out) {
  @($Out -split "`r?`n" | Where-Object { $_ -match '^\S.*:\d+:\d+\s+\[' })
}
function RulesIn([string]$Out) {
  @(FindingLines $Out | ForEach-Object { if ($_ -match '\]\s+([a-z0-9-]+):') { $Matches[1] } } | Sort-Object -Unique)
}
function LintAll([string[]]$Extra, [string]$Tag) {
  $argv = @('lint-all', '--db', $db, '--output', (Join-Path $WorkDir "report-$Tag.txt"), '--quiet') + $Extra
  return (& $Exe @argv 2>&1 | Out-String)
}

Push-Location C:\TEMP
try {
  & $Exe index --all --config $manifest --only SecLaRule --jobs 1 2>&1 | Out-Null
  if (-not (Test-Path $db)) { Write-Host "FATAL: index did not produce $db" -ForegroundColor Red; exit 2 }

  $bare   = LintAll @() 'bare'
  $offOne = LintAll @('--rule', 'magic-literal') 'off'
  $onOne  = LintAll @('--rule', 'float-equality-comparison') 'on'
  $single = & $Exe lint $pas --db $db --library-db $nolib --rule magic-literal --quiet 2>&1 | Out-String
} finally { Pop-Location }

Write-Host ''
Write-Host 'CONTROLS -- the bare run' -ForegroundColor Cyan
Check 'C1 bare lint-all reports findings (the run is alive)' ((FindingLines $bare).Count -ge 2) ("rules: " + ((RulesIn $bare) -join ' '))
Check 'C2 bare lint-all does NOT report magic-literal (it still ships OFF)' `
  ((RulesIn $bare) -notcontains 'magic-literal') 'RED here means the fix flipped a default, not honoured --rule'
Check 'C3 lint <file> --rule magic-literal reports it (the contract lint-all must match)' `
  ((RulesIn $single) -contains 'magic-literal') ''

Write-Host ''
Write-Host 'D4 -- lint-all --rule <OFF rule> opts it in' -ForegroundColor Cyan
Check 'D4a lint-all --rule magic-literal reports magic-literal' `
  ((RulesIn $offOne) -contains 'magic-literal') 'RED means lint-all still needs --enable as well'
Check 'D4b and reports NOTHING else' `
  (((RulesIn $offOne) | Where-Object { $_ -ne 'magic-literal' }).Count -eq 0) ("also: " + (((RulesIn $offOne) | Where-Object { $_ -ne 'magic-literal' }) -join ' '))
$singleLines = @(FindingLines $single | ForEach-Object { ($_ -replace '^.*?:(\d+:\d+)', '$1').Trim() } | Sort-Object)
$allLines    = @(FindingLines $offOne | ForEach-Object { ($_ -replace '^.*?:(\d+:\d+)', '$1').Trim() } | Sort-Object)
Check 'D4c the same finding lines as lint <file> --rule magic-literal' `
  (($singleLines -join '|') -eq ($allLines -join '|')) ("lint: " + ($singleLines -join ' / ') + "  lint-all: " + ($allLines -join ' / '))

Write-Host ''
Write-Host 'D4 -- lint-all --rule <ON rule> narrows' -ForegroundColor Cyan
Check 'D4d lint-all --rule float-equality-comparison reports it' `
  ((RulesIn $onOne) -contains 'float-equality-comparison') ''
Check 'D4e and reports nothing else (the bare run had other rules to leak)' `
  (((RulesIn $onOne) | Where-Object { $_ -ne 'float-equality-comparison' }).Count -eq 0) ("also: " + (((RulesIn $onOne) | Where-Object { $_ -ne 'float-equality-comparison' }) -join ' '))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
