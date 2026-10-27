<#
  run_compliance_profile.ps1 -- guard for the BUILT-IN compliance profiles
  (--profile cwe | cert | misra | cwe-top25). Plan: docs\superpowers\plans\
  2026-10-27-rule-gaps-and-compliance-plan.md section 4.1.3 and lane K2.

  A built-in profile enables the rules labelled under that standard, disables every other rule
  and floors the selected rules' severity at `warning`; a user-defined profile of the same name
  in drag-lint-lint.json wins. Every check runs against the exe given as -Exe and the rules\ of
  THIS tree (--rules-dir).

  Positive : --profile cwe on hardcoded-credential.pas  -> >= 1 finding at >= warning.
  Negative : --profile cwe on type-name-prefix.pas      -> 0 findings (unlabelled rule off).
  Control  : the same file without a profile            -> >= 1 finding (the negative is not vacuous).
  Override : a temp config naming its own profile `cwe` -> the built-in set is NOT applied.
  Other    : cwe-top25 keeps sql-injection-concat (CWE-89) and drops hardcoded-credential (CWE-798); misra drops the latter.
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$exe = (Resolve-Path $Exe).Path
$rulesDir = Join-Path $repo "rules"
$fail = 0
function Assert($name, $cond) {
  if ($cond) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
}
function Run([string]$file, [string[]]$extra) {
  $out = & $exe lint --json --rules-dir $rulesDir @extra (Join-Path $repo "tests\lint\$file") 2>$null
  return @(($out -join "`n") | ConvertFrom-Json)
}

$base = Run 'type-name-prefix.pas' @()
Assert "control: type-name-prefix.pas has findings without a profile (got $($base.Count))" ($base.Count -ge 1)
$neg = Run 'type-name-prefix.pas' @('--profile', 'cwe')
Assert "--profile cwe on type-name-prefix.pas: 0 findings (got $($neg.Count))" ($neg.Count -eq 0)

$pos = Run 'hardcoded-credential.pas' @('--profile', 'cwe')
$hit = @($pos | Where-Object { $_.rule -eq 'hardcoded-credential' -and $_.severity -in @('warning', 'error') })
Assert "--profile cwe on hardcoded-credential.pas: >= 1 finding at >= warning (got $($hit.Count))" ($hit.Count -ge 1)

$top = Run 'hardcoded-credential.pas' @('--profile', 'cwe-top25')
Assert "--profile cwe-top25 drops hardcoded-credential (CWE-798 is not in the 2025 Top 25)" (@($top | Where-Object { $_.rule -eq 'hardcoded-credential' }).Count -eq 0)
$topPos = Run 'sql-injection-concat.pas' @('--profile', 'cwe-top25')
Assert "--profile cwe-top25 keeps sql-injection-concat (CWE-89, rank 2)" (@($topPos | Where-Object { $_.rule -eq 'sql-injection-concat' }).Count -ge 1)
$mis = Run 'hardcoded-credential.pas' @('--profile', 'misra')
Assert "--profile misra drops hardcoded-credential (no MISRA label)" (@($mis | Where-Object { $_.rule -eq 'hardcoded-credential' }).Count -eq 0)

# Override: the user's own profile `cwe` wins over the built-in one.
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("compl-prof-" + [Guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Path $tmp | Out-Null
  $cfg = Join-Path $tmp 'drag-lint-lint.json'
  [IO.File]::WriteAllText($cfg, '{"profiles": {"cwe": {"disabled": ["hardcoded-credential"]}}}')
  $ovA = Run 'hardcoded-credential.pas' @('--config', $cfg, '--profile', 'cwe')
  Assert "override: user profile cwe disables hardcoded-credential" (@($ovA | Where-Object { $_.rule -eq 'hardcoded-credential' }).Count -eq 0)
  $ovB = Run 'type-name-prefix.pas' @('--config', $cfg, '--profile', 'cwe')
  Assert "override: built-in set NOT applied (type-name-prefix still reports, got $($ovB.Count))" ($ovB.Count -ge 1)
} finally {
  [IO.Directory]::Delete($tmp, $true)
}

Write-Host ""
if ($fail -gt 0) { Write-Host "$fail check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host "compliance profile guard: all checks passed"
exit 0
