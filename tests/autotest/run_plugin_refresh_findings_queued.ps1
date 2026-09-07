<#
  run_plugin_refresh_findings_queued.ps1 -- session 74.

  THE DEFECT THIS PINS. `refresh-findings` was launched from the IDE plugin by
  a direct CreateProcessW call, detached and fire-and-forget, off both the
  SaveNotifier hook and the idle tick. Every sibling heavy path (yadfproject:,
  autodoc:, reindex:, lint-all:) already went through the R2 job queue; this one
  did not, so it had no job, hence no CoalesceKey, hence nothing that COULD
  coalesce.

  WHAT IT COST, measured from a live session: 32 detached spawns, ~20 of them
  inside 9 seconds. refresh-findings RECOMPILES UNITS, so each is real CPU. The
  LSP started into that load, its `initialize` took 101 s against a 45 s client
  timeout, and the user saw "LSP initialize handshake failed" -- about a
  handshake that had in fact succeeded.

  WHY THIS IS A SOURCE GUARD, WHICH IS NOT THE REPO'S NORMAL PREFERENCE. The
  wiring lives in an anonymous closure assigned to an IDE idle hook and in an
  OTA SaveNotifier callback; extracting either for a headless test would test a
  copy, not the wiring (the same argument the IDE/LSP plan makes for its own
  P3). What CAN be checked without an IDE is the property that actually failed:
  that this path builds a JOB rather than a process. A bypass is invisible at
  runtime -- it looks exactly like a path that simply has not fired yet -- which
  is how it survived a gating fix that everyone read as having closed it.

  Runs from anywhere, pwsh 7.
#>
[CmdletBinding()]
param([string]$Editor = "$PSScriptRoot\..\..\src\delphi-plugin\DragLint.Plugin.Editor.pas")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$path = (Resolve-Path $Editor).Path
$text = [IO.File]::ReadAllText($path)

# The body of `procedure EnqueueRefreshFindings ... end; // procedure`. Returns
# '' when the procedure is absent, so every body assertion fails loudly rather
# than vacuously passing on an empty string.
function Get-RefreshBody([string]$src) {
  $start = $src.IndexOf('procedure EnqueueRefreshFindings(')
  if ($start -lt 0) { return '' }
  $end = $src.IndexOf('end; // procedure', $start)
  if ($end -lt 0) { return '' }
  return $src.Substring($start, $end - $start)
}

Write-Host ''
Write-Host '=== the IDE refresh-findings path goes through the job queue ===' -ForegroundColor Cyan

$body = Get-RefreshBody $text

Check 'the procedure exists (guard is anchored to something real)' ($body -ne '')

# --- the bypass is gone -----------------------------------------------------
# Name AND mechanism, because either alone is escapable: a rename that kept
# CreateProcessW would pass the first, and keeping the old name while enqueuing
# would pass the second while leaving every doc and log-grep recipe stale.
Check 'the old bypassing name SpawnRefreshFindings is gone from the plugin source' `
  (-not $text.Contains('SpawnRefreshFindings'))
Check 'the refresh path does NOT call CreateProcessW (that WAS the bypass)' `
  ($body -ne '' -and (-not $body.Contains('CreateProcessW')))

# --- it builds a real, coalescing job ---------------------------------------
Check 'the refresh path enqueues onto the job queue' `
  ($body -ne '' -and $body.Contains('JobQueue.Enqueue'))
Check 'it sets a CoalesceKey, so a burst of saves collapses to one pending sweep' `
  ($body -ne '' -and $body -match "CoalesceKey\s*:=\s*'refresh-findings:'")
# Per-DATABASE: the collision being prevented is two sweeps writing
# compiler_findings in the same DB, so two projects resolving to one DB must
# share a key. A per-project or per-file key would look right and coalesce
# nothing that matters.
Check 'the CoalesceKey is keyed on the DATABASE, not the project or the file' `
  ($body -ne '' -and $body -match "CoalesceKey\s*:=\s*'refresh-findings:'\s*\+\s*LowerCase\(ADb\)")

# --- no call site slipped back onto a direct spawn --------------------------
$callSites = ([regex]::Matches($text, 'EnqueueRefreshFindings\(GetActiveProjectFile')).Count
Check 'both known call sites (save hook + idle tick) go through the enqueue path' `
  ($callSites -eq 2) "found $callSites"

# --- POSITIVE CONTROL -------------------------------------------------------
# Without this the whole file could be asserting against a procedure it failed
# to locate, or against substrings that can no longer appear for unrelated
# reasons. Re-running the same extraction over a DELIBERATELY BROKEN copy must
# flip the two load-bearing checks to false.
$broken = $text.Replace('JobQueue.Enqueue(Job);', 'CreateProcessW(nil, @CmdLineW[0], nil, nil, False, 0, nil, nil, SI, PI);')
$brokenBody = Get-RefreshBody $broken
Check 'POSITIVE CONTROL: a planted CreateProcessW in that body FAILS the bypass check' `
  ($brokenBody -ne '' -and $brokenBody.Contains('CreateProcessW'))
Check 'POSITIVE CONTROL: removing the enqueue FAILS the queue check' `
  ($brokenBody -ne '' -and (-not $brokenBody.Contains('JobQueue.Enqueue')))

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
