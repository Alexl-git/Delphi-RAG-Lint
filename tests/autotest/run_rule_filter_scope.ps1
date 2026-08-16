# Guard: --rule must cover BOTH rule registries, and must actually filter.
#
# docs\INBOX-lint-rule-filter-leaks-other-rules.md.
#
# drag-lint has two rule registries -- ~90 built-in AST checks and 56 external
# .scm/.json query rules -- and `--rule` knew only the first:
#
#   * validation was a hand-kept `and (AArgs.Rule <> '<id>')` chain of built-ins,
#     so `--rule bare-except` (a rule the tool ships and reports on every run)
#     was rejected as "unknown", and the error printed a "known:" list that did
#     not contain it;
#   * the query-rule pass appended its findings UNCONDITIONALLY, so
#     `--rule write-only-local` returned bare-except findings and no
#     write-only-local ones. Output shrank, so the filter looked like it worked.
#
# The second is the dangerous half: a filter that returns the WRONG rule is worse
# than one that returns nothing, because the caller believes the answer.
#
# Usage: pwsh -File tests/autotest/run_rule_filter_scope.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $RulesDir = "$PSScriptRoot\..\..\rules",
    [string] $WorkDir = "$env:TEMP\drag-lint-rule-filter-scope"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null

# Fixture carries findings for BOTH a query rule (bare-except) and a built-in
# (write-only-local). A file with only one of them cannot tell a working filter
# from a broken one -- that mistake produced a false "no difference" reading
# while this defect was being triaged.
$Body = @'
unit uRuleFilter;
interface
procedure P;
implementation
procedure P;
var
  Unused: Integer;
begin
  Unused := 1;
  try
    Writeln('a');
  except
    Writeln('b');
  end;
end;
end.
'@
$file = Join-Path $WorkDir 'uRuleFilter.pas'
[System.IO.File]::WriteAllText($file, (($Body -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII)

function RuleIds([string]$Text) {
  ,@([regex]::Matches($Text, '\[(?:info|hint|warning|error)\]\s+([a-z0-9-]+):') |
     ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}

$unfiltered = & $Exe lint $file --rules-dir $RulesDir 2>&1 | Out-String
$idsAll = RuleIds $unfiltered
Write-Host ("  unfiltered rule ids: {0}" -f ($idsAll -join ',')) -ForegroundColor DarkGray

# PRECONDITION -- if the fixture stops producing a query-rule finding, every arm
# below would pass vacuously. Assert the raw material exists first.
Check 'fixture yields a QUERY-rule finding (bare-except) with no filter' ($idsAll -contains 'bare-except')

# THE DEFECT, half 1 -- a query rule id must be accepted, not called "unknown".
$q = & $Exe lint $file --rule bare-except --rules-dir $RulesDir 2>&1 | Out-String
Check 'a query-rule id is accepted by --rule' (-not ($q -match 'unknown rule'))
Check 'filtering to a query rule returns ONLY that rule' `
    (((RuleIds $q) -join ',') -eq 'bare-except') ("got: " + ((RuleIds $q) -join ','))

# THE DEFECT, half 2 -- filtering to a BUILT-IN must not leak query-rule findings.
$b = & $Exe lint $file --rule write-only-local --rules-dir $RulesDir 2>&1 | Out-String
$idsB = RuleIds $b
Check 'filtering to a built-in does NOT leak query-rule findings' (-not ($idsB -contains 'bare-except')) `
    ("got: " + ($idsB -join ','))
Check 'every id returned under --rule write-only-local IS write-only-local' `
    (@($idsB | Where-Object { $_ -ne 'write-only-local' }).Count -eq 0) ("got: " + ($idsB -join ','))

# The error path must describe the WHOLE catalogue, not one registry.
$u = & $Exe lint $file --rule no-such-rule-xyz --rules-dir $RulesDir 2>&1 | Out-String
$uExit = $LASTEXITCODE
Check 'an unknown rule still exits 2' ($uExit -eq 2) "exit=$uExit"
Check 'the known-rules list includes QUERY rules' ($u -match 'bare-except')
Check 'the known-rules list includes BUILT-IN rules' ($u -match 'write-only-local')
$declared = [regex]::Match($u, 'known rules \((\d+)\)').Groups[1].Value
Check 'the known-rules list is bigger than the old hand-kept built-in list (~90)' `
    ([int]$declared -gt 100) "declared=$declared"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
