<#
  run_doc_drift_rule.ps1 -- doc-drift lint rule + --fix (ADF Task 8).

  Exercises TDocLintRules.RunDocDrift through the store-backed `lint-all` path
  (doc-drift needs the whole symbol/doc graph, like missing-doc, so it can only
  run on the store-backed project command, never the bare per-file `lint`).

  Fixture: fixtures\docdrift\drift.pas (shared with the Task 6 engine test).
    * function F(New: Integer): string;
        doc <param name="Old"> renamed away -> ddParamRenamedOrRemoved (report-only)
        no <param> for the real sig param New -> ddParamMissing (report-only as of
          v(ADP3 T3) -- see the follow-up note below; was FIXABLE before this fix)
    * procedure P;
        spurious <returns> on a procedure -> ddReturnsButNoValue (report-only)
    * function Lookup(Key: Integer): string;
        <exception cref="EFoo"> never raised -> ddExceptionNotRaised (report-only)
        function with no <returns> -> ddValueButNoReturns (FIXABLE)

  v(ADP3 T3) FOLLOW-UP FIX (post-task-3 review): omit-when-empty means the engine
  can never again add a description-less <param> stub, so ddParamMissing's
  Fixable=true was a FALSE PROMISE the original Task 3 commit left standing --
  a person running `--fix` would see the finding survive FOREVER and reasonably
  conclude the tool was broken. Fixed in DRagLint.Doc.Drift.pas: ddParamMissing's
  MakeFinding call now passes Fixable=False (report-only), with a comment naming
  Task 3 as the cause. Consequence discovered while updating this test: F's ONLY
  drift was ddParamRenamedOrRemoved (always report-only) + ddParamMissing (now
  report-only too), so F now has ZERO fixable signals -- FixEditsForDocDrift's
  AnyFix gate (DRagLint.Lint.DocRules.pas) skips a decl with none, so F is no
  longer touched by `--fix` AT ALL: no facts-block refresh, and no "param no
  longer exists" flag on "Old" either (that flag was always a side effect of
  MergeComment running for SOME fixable reason, never its own independent
  action). This is the correct, narrower behavior -- `--fix` should only touch
  what it can mechanically resolve -- not a new problem: F was only ever
  "getting" a facts-block refresh and the Old-flag as an incidental side effect
  of the now-corrected false Fixable claim. ddFactsBlockStale does NOT pick up
  the slack for F: it only fires when a managed facts block ALREADY exists and
  differs from a fresh render ("a doc with no managed block is not 'stale', it
  simply has none" -- see TDocDrift.Analyze's own comment), and F has no facts
  block at all.

  Part A -- report-all: `lint-all --db <db> --json` emits doc-drift findings for
  the renamed-param + spurious-returns + not-raised-exception + missing-param
  signals (missing-param is still REPORTED, just no longer fixable).

  Part B -- fix the safe subset: `lint-all --db <db> --fix --apply` refreshes
  Lookup's managed facts block + <returns> stub. F is now byte-identical to the
  ORIGINAL fixture (no fixable signal at all -- see the follow-up note above),
  so its renamed <param name="Old"> prose survives trivially (untouched), NOT
  because of a preserve-and-flag mechanism (that no longer runs for F).

  Part C -- idempotency: a second `--fix --apply` is byte-identical. A
  re-analysis shows BOTH F and Lookup have zero fixable drift remaining --
  Lookup because its mined return resolved ddValueButNoReturns; F because its
  only two signals (renamed param, missing param) are both report-only by
  design now.

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
  # PHASE C B7 (user ruling 2026-08-09): "If method doesn't have params and they
  # are reported then it is an error." A <param> naming a parameter the signature
  # does not declare left doc-drift for its own id at ERROR severity -- the rest
  # of doc-drift reports documentation that is INCOMPLETE, this reports
  # documentation that is FALSE. So it is looked for under the new id, and the
  # severity is asserted, because moving it without pinning the severity would
  # lose the whole point of the split.
  $notInSig = @($findings | Where-Object { $_.rule -eq 'doc-param-not-in-signature' })
  Check 'reports the renamed param "Old" as doc-param-not-in-signature' `
    ((@($notInSig | ForEach-Object { $_.message }) | Where-Object { $_ -like '*Old*' }).Count -ge 1)
  Check '... at ERROR severity' `
    (($notInSig.Count -gt 0) -and (@($notInSig | Where-Object { $_.severity -ne 'error' }).Count -eq 0)) `
    ("severities: " + ((@($notInSig | ForEach-Object { $_.severity }) | Sort-Object -Unique) -join ','))
  Check 'reports the spurious <returns> on procedure P'   (($msgs | Where-Object { $_ -like '*returns no value*' }).Count -ge 1)
  Check 'reports the never-raised <exception cref="EFoo">' (($msgs | Where-Object { $_ -like '*EFoo*' }).Count -ge 1)
  Check 'reports the missing <param> for sig param New (still reported, just not fixable)' (($msgs | Where-Object { $_ -like '*New*' }).Count -ge 1)

  # F's own span (unit header through its declaration line) -- captured BEFORE
  # the fix so it can be compared against the SAME span after. Scoped to F
  # deliberately: Lookup (elsewhere in the same file) DOES get fixed, so a
  # whole-file byte comparison would wrongly fail even though F itself is 100%
  # untouched.
  function GetSpanThroughF([string[]]$lines) {
    $idx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*function F\(New: Integer\): string;\s*$') { $idx = $i; break } }
    if ($idx -lt 0) { return $null }
    return ($lines[0..$idx] -join "`n")
  }
  $beforeFLines = [IO.File]::ReadAllLines($target)
  $beforeFSpan  = GetSpanThroughF $beforeFLines

  # ---- Part B: fix the safe subset -----------------------------------------
  & $exePath lint-all --db $db --fix --apply --no-backup 2>$null | Out-Null
  $afterFix = Get-Content -Raw $target
  $afterFLines = [IO.File]::ReadAllLines($target)
  $afterFSpan  = GetSpanThroughF $afterFLines

  # v(ADP3 T3) + follow-up fix: F has NO fixable signal anymore (its only two
  # findings, ddParamRenamedOrRemoved and ddParamMissing, are both report-only
  # now), so FixEditsForDocDrift's AnyFix gate skips F entirely -- its OWN span
  # must be byte-identical to before the fix (Lookup, elsewhere in the same
  # file, DOES still get fixed -- ddValueButNoReturns -- so the file AS A
  # WHOLE legitimately changes; only F's own span is asserted untouched here).
  Check 'follow-up fix: F is completely untouched (no fixable signal at all)' `
    ($null -ne $beforeFSpan -and $null -ne $afterFSpan -and $afterFSpan -ceq $beforeFSpan)
  Check 'v(ADP3 T3): fix does NOT add a <param name="New"> stub anywhere (nothing to say)' `
    ($afterFix -notmatch '<param name="New">')
  Check 'fix refreshed Lookup''s managed facts block' ($afterFix -match 'drag-lint:auto BEGIN')
  # The renamed <param name="Old"> prose survives TRIVIALLY now (F is untouched
  # entirely), not via the old preserve-and-flag mechanism -- see the header note.
  Check 'renamed <param name="Old"> prose is PRESERVED (F untouched)' ($afterFix -match '<param name="Old">')
  Check 'preserved Old param keeps its hand prose'      ($afterFix -match 'old parameter that was since renamed')
  Check 'follow-up fix: Old param is NOT flagged (F is never regenerated -- no fixable signal to trigger it)' `
    ($afterFix -notmatch 'param no longer exists')

  # ---- Part C: idempotency -------------------------------------------------
  $before2 = Get-Content -Raw $target
  & $exePath lint-all --db $db --fix --apply --no-backup 2>$null | Out-Null
  $after2 = Get-Content -Raw $target
  Check '2nd --fix is byte-identical (idempotent)' ($before2 -eq $after2)

  # Re-index the now-repaired file, then re-analyse.
  & $exePath index $scratch --db $db 2>$null | Out-Null
  $fReanalyse = Get-Drift 'drift.F'
  $lReanalyse = Get-Drift 'drift.Lookup'

  # v(ADP3 T3) follow-up fix: BOTH F and Lookup now show zero FIXABLE drift --
  # Lookup because its mined return resolved ddValueButNoReturns (unchanged
  # from before T3); F because ddParamMissing is now correctly report-only
  # (Fixable=False), so it was never counted as "fixable" to begin with.
  $lFixableAfter = @($lReanalyse | Where-Object { [bool]$_.fixable -eq $true })
  Check 'Lookup: no fixable drift remains (ddValueButNoReturns was resolved by the mined-return fix)' `
    ($lFixableAfter.Count -eq 0)
  $fFixableAfter = @($fReanalyse | Where-Object { [bool]$_.fixable -eq $true })
  Check 'follow-up fix: F has no fixable drift remaining either (ddParamMissing is report-only)' `
    ($fFixableAfter.Count -eq 0)
  # ddParamMissing itself must still be REPORTED (just not fixable) -- a human
  # still needs to see it to know "New" has no <param> tag.
  $fParamMissing = @($fReanalyse | Where-Object { $_.kind -eq 'ddParamMissing' })
  Check 'follow-up fix: ddParamMissing on F still reported (report-only, not silenced)' `
    ($fParamMissing.Count -ge 1 -and -not [bool]$fParamMissing[0].fixable)

  # The renamed-param signal is report-only, so it correctly SURVIVES the fix.
  $renamedLeft = @($fReanalyse | Where-Object { $_.kind -eq 'ddParamRenamedOrRemoved' })
  Check 'renamed-param report-only signal survives (not auto-fixed)' ($renamedLeft.Count -ge 1)
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
