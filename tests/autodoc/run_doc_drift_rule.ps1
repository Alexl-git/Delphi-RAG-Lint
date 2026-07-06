<#
  run_doc_drift_rule.ps1 -- doc-drift lint rule + --fix (ADF Task 8).

  Exercises TDocLintRules.RunDocDrift through the store-backed `lint-all` path
  (doc-drift needs the whole symbol/doc graph, like missing-doc, so it can only
  run on the store-backed project command, never the bare per-file `lint`).

  Fixture: fixtures\docdrift\drift.pas (shared with the Task 6 engine test).
    * function F(New: Integer): string;
        doc <param name="Old"> renamed away -> ddParamRenamedOrRemoved (report-only)
        no <param> for the real sig param New -> ddParamMissing (FIXABLE)
    * procedure P;
        spurious <returns> on a procedure -> ddReturnsButNoValue (report-only)
    * function Lookup(Key: Integer): string;
        <exception cref="EFoo"> never raised -> ddExceptionNotRaised (report-only)
        function with no <returns> -> ddValueButNoReturns (FIXABLE)

  Part A -- report-all: `lint-all --db <db> --json` emits doc-drift findings for
  the renamed-param + spurious-returns + not-raised-exception signals.

  Part B -- fix the safe subset: `lint-all --db <db> --fix --apply` refreshes the
  managed facts block AND adds the missing <param name="New"> stub, but does NOT
  delete/rewrite the renamed <param name="Old"> prose (report-only -- preserved).

  Part C -- idempotency: a second `--fix --apply` is byte-identical AND a
  re-analysis (the doc-drift engine verb) reports no FIXABLE drift left.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docdrift\drift.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docdrift_rule'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'drift.pas'
$db     = Join-Path $scratch 'docdrift.sqlite'
Copy-Item $fixture $target -Force

# Extract the single pretty-printed JSON array from lint-all --json output (the
# array is preceded/followed by plain progress/summary text on other lines).
function Get-Findings($raw) {
  $arrStart = $raw.IndexOf('[')
  $arrEnd   = $raw.LastIndexOf(']')
  if ($arrStart -ge 0 -and $arrEnd -gt $arrStart) {
    return @(ConvertFrom-Json ($raw.Substring($arrStart, $arrEnd - $arrStart + 1)))
  }
  return @()
}

# Re-analyse one symbol through the engine verb; returns rows with .kind/.fixable.
function Get-Drift($qname) {
  $out = & $exePath doc-drift --qname $qname --db $db --json 2>$null
  $rows = @()
  foreach ($ln in $out) { $t = $ln.Trim(); if ($t.StartsWith('{')) { $rows += ($t | ConvertFrom-Json) } }
  return ,$rows
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # ---- Part A: report-all --------------------------------------------------
  $rawA = (& $exePath lint-all --db $db --json 2>$null) -join "`n"
  $findings = Get-Findings $rawA
  $drift = @($findings | Where-Object { $_.rule -eq 'doc-drift' })
  Check 'lint-all emits at least one doc-drift finding' ($drift.Count -ge 1)

  $msgs = @($drift | ForEach-Object { $_.message })
  Check 'reports the renamed param "Old" (report-only)'   (($msgs | Where-Object { $_ -like '*Old*' }).Count -ge 1)
  Check 'reports the spurious <returns> on procedure P'   (($msgs | Where-Object { $_ -like '*returns no value*' }).Count -ge 1)
  Check 'reports the never-raised <exception cref="EFoo">' (($msgs | Where-Object { $_ -like '*EFoo*' }).Count -ge 1)
  Check 'reports the missing <param> for sig param New'    (($msgs | Where-Object { $_ -like '*New*' }).Count -ge 1)

  # ---- Part B: fix the safe subset -----------------------------------------
  & $exePath lint-all --db $db --fix --apply --no-backup 2>$null | Out-Null
  $afterFix = Get-Content -Raw $target

  Check 'fix ADDED a managed <param name="New"> stub' ($afterFix -match '<param name="New">')
  Check 'fix refreshed a managed facts block'          ($afterFix -match 'drag-lint:auto BEGIN')
  # The renamed <param name="Old"> prose must be PRESERVED, not stripped/rewritten
  # (report-only signal -- a human decides whether to drop it). MergeComment keeps
  # it and only appends a "param no longer exists" flag comment.
  Check 'renamed <param name="Old"> prose is PRESERVED' ($afterFix -match '<param name="Old">')
  Check 'preserved Old param keeps its hand prose'      ($afterFix -match 'old parameter that was since renamed')
  Check 'Old param is FLAGGED, not deleted'             ($afterFix -match 'param no longer exists')

  # ---- Part C: idempotency -------------------------------------------------
  $before2 = Get-Content -Raw $target
  & $exePath lint-all --db $db --fix --apply --no-backup 2>$null | Out-Null
  $after2 = Get-Content -Raw $target
  Check '2nd --fix is byte-identical (idempotent)' ($before2 -eq $after2)

  # Re-index the now-repaired file, then re-analyse: NO fixable drift remains.
  & $exePath index $scratch --db $db 2>$null | Out-Null
  $fReanalyse = Get-Drift 'drift.F'
  $lReanalyse = Get-Drift 'drift.Lookup'
  $fixableLeft = @(($fReanalyse + $lReanalyse) | Where-Object { [bool]$_.fixable -eq $true })
  Check 'no FIXABLE drift remains after the fix (F + Lookup)' ($fixableLeft.Count -eq 0)
  # The renamed-param signal is report-only, so it correctly SURVIVES the fix.
  $renamedLeft = @($fReanalyse | Where-Object { $_.kind -eq 'ddParamRenamedOrRemoved' })
  Check 'renamed-param report-only signal survives (not auto-fixed)' ($renamedLeft.Count -ge 1)
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
