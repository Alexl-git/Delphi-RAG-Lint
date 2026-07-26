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
  managed facts block, but does NOT delete/rewrite the renamed <param name="Old">
  prose (report-only -- preserved). v(ADP3 T3) update: it also does NOT add a
  <param name="New"> stub anymore -- omit-when-empty forbids ever emitting an
  empty <param>, and no harvester exists to fill one with real content, so
  ddParamMissing's "fix" is now a no-op for this shape (see Part C).

  Part C -- idempotency: a second `--fix --apply` is byte-identical. v(ADP3 T3)
  update: a re-analysis now shows Lookup's fixable drift fully resolved (its
  mined return filled <returns>), but F's ddParamMissing SURVIVES the fix --
  permanently, by design, since no auto-fix can ever satisfy it once params are
  never harvested. This is a known, reported design tension (ddParamMissing's
  Fixable=true classification in DRagLint.Doc.Drift.pas predates T3 and is now
  stale for a param with no hand-written description anywhere); left unchanged
  here as out of this task's scope -- see the T3 report.

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

  # v(ADP3 T3): omit-when-empty means the fix can no longer add a <param>
  # skeleton -- "New" has no hand-written description anywhere, and no
  # harvester for params exists (or ever will -- see the T3 report), so a
  # managed <param> could never gain content. The ddParamMissing FIXABLE
  # classification (DRagLint.Doc.Drift.pas) predates T3 and is now stale for
  # this shape -- see the T3 report's flagged design tension. This assertion
  # documents the actual (new) behavior rather than papering over it.
  Check 'v(ADP3 T3): fix does NOT add a <param name="New"> stub (nothing to say)' `
    ($afterFix -notmatch '<param name="New">')
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

  # Re-index the now-repaired file, then re-analyse.
  & $exePath index $scratch --db $db 2>$null | Out-Null
  $fReanalyse = Get-Drift 'drift.F'
  $lReanalyse = Get-Drift 'drift.Lookup'

  # v(ADP3 T3) update: Lookup's ddValueButNoReturns WAS resolved -- it has a
  # real mined return case (IntToStr(Key)), so the fix filled its <returns>
  # tag with content, same as before T3. F's ddParamMissing ("New" has no
  # hand-written description anywhere) is now STRUCTURALLY UNFIXABLE: T3
  # forbids ever emitting an empty <param> skeleton, and per the spec params
  # are never harvested, so no auto-fix can ever satisfy this finding again
  # -- it correctly SURVIVES as a standing signal for a human. This was
  # anticipated by neither the drift engine nor this test before T3; see the
  # T3 report's flagged design tension (ddParamMissing's Fixable=true
  # classification in DRagLint.Doc.Drift.pas is now stale for this shape,
  # left unchanged as an out-of-scope follow-up).
  $lFixableAfter = @($lReanalyse | Where-Object { [bool]$_.fixable -eq $true })
  Check 'Lookup: no fixable drift remains (ddValueButNoReturns was resolved by the mined-return fix)' `
    ($lFixableAfter.Count -eq 0)
  $fFixableAfter = @($fReanalyse | Where-Object { [bool]$_.fixable -eq $true })
  Check 'v(ADP3 T3): F''s ddParamMissing SURVIVES the fix -- exactly one, permanently unfixable' `
    ($fFixableAfter.Count -eq 1 -and $fFixableAfter[0].kind -eq 'ddParamMissing')

  # The renamed-param signal is report-only, so it correctly SURVIVES the fix.
  $renamedLeft = @($fReanalyse | Where-Object { $_.kind -eq 'ddParamRenamedOrRemoved' })
  Check 'renamed-param report-only signal survives (not auto-fixed)' ($renamedLeft.Count -ge 1)
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
