<#
  run_live_lint_failure_keeps_findings.ps1 -- a live lint run that did NOT
  finish (timeout, spawn failure, cancel) must not publish an empty set.

  THE DEFECT THIS PINS (2026-11-01, ORM3 COMMON\BASICS.PAS)

    TLintDiagnosticProvider.GetDiagnostics returned [] when the engine child
    timed out (RunCaptureStdoutCancellable -> PROCRUN_TIMED_OUT_EXIT_CODE), and
    the runner published that [] as dlpLive. The live set wins the gutter BY
    PRESENCE (run_diag_producer_overlays.ps1), so the zero hid the LSP's 15
    findings for the same file. Telemetry: `lint: spawn FAILED` -> `aggregated
    0 diag(s)` -> `Update[live] BASICS.PAS: 0 -> 0` while publishDiagnostics had
    delivered 15. A run that did not finish is NO answer, not an answer of zero.

  STATIC, like run_diag_producer_overlays.ps1: the BPL has no headless harness.
  F1  the provider marks a failed run (LintExit < 0) on its thread.
  F2  the runner clears the mark before AggregateDiagnostics and reads it after.
  F3  the publish is skipped when the run failed, and still happens otherwise.
#>
[CmdletBinding()]
param(
  [string]$Dir = "$PSScriptRoot\..\..\src\delphi-plugin",
  [string]$Exe = ''   # accepted for battery uniformity; static guard
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
$livePath = Join-Path $Dir 'DragLint.Plugin.LiveDiagnostics.pas'
if (-not (Test-Path $livePath)) { Write-Host "FATAL: not found: $livePath" -ForegroundColor Red; exit 2 }
$live = Get-Content $livePath -Raw

Write-Host 'A live lint that did not finish publishes nothing' -ForegroundColor Cyan
Check 'F1  a per-thread failure mark is declared' ($live -match 'threadvar\s+GLintRunFailed\s*:\s*Boolean')
$fail = [regex]::Match($live, 'if\s+LintExit\s*<\s*0\s+then\s+begin(.*?)Exit;', 'Singleline').Groups[1].Value
Check 'F1  the LintExit < 0 branch sets it' ($fail -match 'GLintRunFailed\s*:=\s*True') ("branch: {0} chars" -f $fail.Length)
$thr = [regex]::Match($live, 'TThread\.CreateAnonymousThread\(.*?PublishToCache\(FilePath,\s*Diags\)', 'Singleline').Value
Check 'F2  runner thread located' ([bool]$thr)
Check 'F2  the mark is cleared before AggregateDiagnostics' ($thr -match 'GLintRunFailed\s*:=\s*False;\s*(?:\{[^}]*\}\s*)*Diags\s*:=\s*AggregateDiagnostics')
Check 'F2  the mark is read into a captured local after it' ($thr -match '(?s)Diags\s*:=\s*AggregateDiagnostics\(Ctx\);.*?RunFailed\s*:=\s*GLintRunFailed')
Check 'F3  the publish is guarded by the failed run' ($thr -match '(?s)else\s+if\s+RunFailed\s+then.*?else\s+begin\s+PublishToCache\(FilePath,\s*Diags\)')

if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
