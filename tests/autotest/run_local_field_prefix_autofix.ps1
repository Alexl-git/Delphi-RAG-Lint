# Guard: local-field-prefix is autofixable -- it STRIPS the F off a local.
#
# Added 2026-08-16 after DataCopy.dpr:63/:64 (FHandle, FLastError) surfaced from
# the .dpr-scanning fix and the owner asked whether they could be auto-fixed.
# They could not: local-field-prefix declared fixable=false, while three rules
# that DID declare fixable=true refused to fix because naming autofix is opt-in.
#
# This is the mirror of the phase-2 prefix rules -- they ADD a missing prefix,
# this STRIPS one a local should never have worn -- and it is the safest rename
# in the family: a local's scope is one routine body, so no call site anywhere
# can be affected. It routes through BuildLocal with the same collision guard
# param-name-prefix uses.
#
# THREE THINGS ARE ASSERTED, and the last two are what stop this passing for the
# wrong reason:
#   * every occurrence is renamed, not just the declaration (a rename that
#     misses a use site produces code that does not compile, and the tool would
#     still report success);
#   * WITHOUT the opt-in nothing is applied -- naming fixes rewrite call sites,
#     so they must stay opt-in, and a fix that ignored that would be a
#     regression, not an improvement;
#   * a local named exactly the prefix, or one that would strip to a
#     digit-leading identifier, is LEFT ALONE rather than renamed to something
#     illegal.
#
# Usage: pwsh -File tests/autotest/run_local_field_prefix_autofix.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $RulesDir = "$PSScriptRoot\..\..\rules",
    [string] $WorkDir = "$env:TEMP\drag-lint-local-field-prefix"
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

$Fixture = @'
unit uLFP;
interface
procedure P;
implementation
procedure P;
var
  FHandle: Integer;
  FLastError: string;
  F: Integer;
  F1: Integer;
begin
  FHandle := 1;
  FLastError := 'x';
  F := 2;
  F1 := 3;
  Writeln(FHandle, FLastError, F, F1);
end;
end.
'@

function Setup([string]$Dir, [string]$ConfigJson) {
    if (Test-Path $Dir) { Get-ChildItem $Dir -File | Remove-Item -Force }
    New-Item -ItemType Directory -Force $Dir | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $Dir 'uLFP.pas'),
        (($Fixture -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII)
    if ($ConfigJson) { [System.IO.File]::WriteAllText((Join-Path $Dir 'cfg.json'), $ConfigJson, [System.Text.Encoding]::ASCII) }
    & $Exe index $Dir --db (Join-Path $Dir 'fx.sqlite') 2>&1 | Out-Null
}

# --- 1. OPTED IN: the rename happens, everywhere -----------------------------
$optIn = Join-Path $WorkDir 'optin'
Setup $optIn '{ "autofix": ["local-field-prefix"] }'
& $Exe lint-all --db (Join-Path $optIn 'fx.sqlite') --rules-dir $RulesDir `
      --config (Join-Path $optIn 'cfg.json') --rule local-field-prefix --fix --apply --no-backup 2>&1 | Out-Null
$after = [System.IO.File]::ReadAllText((Join-Path $optIn 'uLFP.pas'))

Check 'declaration renamed (FHandle -> Handle)' ($after -cmatch '(?m)^\s*Handle: Integer;')
Check 'declaration renamed (FLastError -> LastError)' ($after -cmatch '(?m)^\s*LastError: string;')
# Use sites matter more than the declaration: a rename that moves the decl and
# leaves a use behind yields code that does not compile, reported as success.
Check 'assignment site renamed' ($after -cmatch 'Handle := 1;')
Check 'expression/use site renamed' ($after -cmatch 'Writeln\(Handle, LastError')
Check 'no F-prefixed local survives' (-not ($after -cmatch '\bFHandle\b|\bFLastError\b'))

# ILLEGAL-RESULT GUARD -- 'F' would strip to '' and 'F1' to '1'. Both must stay.
Check 'a local named exactly the prefix is left alone' ($after -cmatch '(?m)^\s*F: Integer;')
Check 'a local stripping to a digit-leading name is left alone' ($after -cmatch '(?m)^\s*F1: Integer;')

# --- 2. NOT OPTED IN: nothing is applied (positive control) ------------------
$noOptIn = Join-Path $WorkDir 'nooptin'
Setup $noOptIn ''
$before2 = [System.IO.File]::ReadAllText((Join-Path $noOptIn 'uLFP.pas'))
$out2 = & $Exe lint-all --db (Join-Path $noOptIn 'fx.sqlite') --rules-dir $RulesDir `
             --rule local-field-prefix --fix --apply --no-backup 2>&1 | Out-String
$after2 = [System.IO.File]::ReadAllText((Join-Path $noOptIn 'uLFP.pas'))
# -ceq, NOT -eq: PowerShell string comparison is case-INSENSITIVE by default, and
# this fix changes only letter presence/case. A case-blind compare reported an
# applied rename as "unchanged" during triage.
Check 'without opt-in the file is untouched' ($before2 -ceq $after2)
Check 'and it SAYS why (not opted in)' ($out2 -match 'not opted in')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
