<#
  stage-engine.ps1 -- the RECOVERY path for staging drag-lint.exe.

  build_draglint_win64.bat copies the freshly linked exe over the deployed one
  and, until now, gave up with:

      ERROR: failed to stage ...\third_party\dll-win64\drag-lint.exe

  That message names the FILE and not the HOLDER, which is why the real cause
  took several rebuild cycles to identify: a running process holds an EXECUTE
  LOCK on its own image, and the Delphi plugin spawns drag-lint.exe as a
  long-lived LSP child. So an IDE that is merely OPEN blocks the deploy -- the
  compile having succeeded moments earlier, which makes it read as something
  else entirely.

  WHY KILLING ALONE DOES NOT WORK
  -------------------------------
  Both clients respawn the server within about a second of it dying, so
  kill-then-copy loses the race. Measured against VS Code on 2026-08-27: it
  took a kill-loop running for the DURATION of the build to stage cleanly.

  So this does BOTH, in this order:

    1. writes the engine-hold sentinel (via the freshly built exe, which is
       not locked) so the IDE plugin will not RESPAWN;
    2. kills the processes actually running the target image;
    3. retries the copy with a short backoff.

  Step 1 is what makes step 2 stick. Neither works alone.

  WHY IT KILLS BY IMAGE PATH, NOT BY NAME
  ---------------------------------------
  Since extension v1.4 the VS Code client runs a PRIVATE COPY of the engine
  from its globalStorage, so a drag-lint.exe in the process list is not
  necessarily holding the file being staged. Killing by name would take down a
  VS Code session for no reason. Only processes whose ExecutablePath IS the
  target are holders, and only those are killed.

  IT REPORTS WHAT IT DID
  ----------------------
  Every holder is named -- PID and command line -- whether or not the recovery
  succeeds. The whole defect this addresses was a message that did not say who
  was to blame; replacing it with a recovery that also says nothing would fix
  half of it.

  Exit code: 0 when the file is staged, 1 when it is not.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string] $FreshExe,
  [Parameter(Mandatory = $true)] [string] $Target,
  [int] $TimeoutSec = 45,
  [int] $HoldSeconds = 120
)

$ErrorActionPreference = 'Stop'

function Try-Copy {
  try { Copy-Item -LiteralPath $FreshExe -Destination $Target -Force -ErrorAction Stop; return $true }
  catch { return $false }
}

# The ordinary path: nothing holds it and this is one copy.
if (Try-Copy) { exit 0 }

Write-Host ''
Write-Host 'drag-lint: staging blocked -- the target is locked. Diagnosing.' -ForegroundColor Yellow

function Get-Holders {
  # ExecutablePath is the authoritative "is this process running THAT file".
  # A name match would also catch the VS Code client, which since extension
  # v1.4 runs its own private copy and is not a holder.
  @(Get-CimInstance Win32_Process -Filter "Name='drag-lint.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.ExecutablePath -and ($_.ExecutablePath -ieq $Target) })
}

$holders = Get-Holders
if ($holders.Count -eq 0) {
  # Locked, but not by a drag-lint process. Antivirus, a backup agent, an
  # indexer or Explorer's thumbnailer can all do this. Say so rather than
  # implying the IDE is at fault -- and retry, because most of those are
  # transient.
  Write-Host '  no drag-lint.exe is running that image; the lock is something else' -ForegroundColor Yellow
  Write-Host '  (antivirus, a backup agent or an indexer will usually let go within seconds)'
} else {
  foreach ($h in $holders) {
    Write-Host ("  holder: PID {0}  {1}" -f $h.ProcessId, $h.CommandLine) -ForegroundColor Yellow
  }
}

# 1 -- stop the RESPAWN before stopping the process, or the kill loses the race.
if (Test-Path -LiteralPath $FreshExe) {
  try {
    & $FreshExe ide-release --seconds $HoldSeconds 2>$null | Out-Null
    Write-Host ("  asked the IDE plugin to hold off for {0}s (it respawns on its own afterwards)" -f $HoldSeconds)
  } catch {
    Write-Host "  could not write the engine hold: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

# 2 -- now the holders can be stopped without immediately coming back.
foreach ($h in $holders) {
  try { Stop-Process -Id $h.ProcessId -Force -ErrorAction Stop; Write-Host ("  stopped PID {0}" -f $h.ProcessId) }
  catch { Write-Host ("  could not stop PID {0}: {1}" -f $h.ProcessId, $_.Exception.Message) -ForegroundColor Yellow }
}

# 3 -- retry. A handle can outlive its process by a moment, and a non-drag-lint
# holder needs time to let go on its own.
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$attempt = 0
while ((Get-Date) -lt $deadline) {
  $attempt++
  Start-Sleep -Milliseconds 250
  if (Try-Copy) {
    Write-Host ("OK: staged after recovery ({0} attempt(s))" -f $attempt) -ForegroundColor Green
    exit 0
  }
}

Write-Host ''
Write-Host "ERROR: still could not stage $Target after ${TimeoutSec}s" -ForegroundColor Red
$still = Get-Holders
if ($still.Count) {
  foreach ($h in $still) { Write-Host ("  still held by PID {0}  {1}" -f $h.ProcessId, $h.CommandLine) -ForegroundColor Red }
  Write-Host '  close the Delphi IDE (or that process) and build again.' -ForegroundColor Red
} else {
  Write-Host '  no drag-lint process holds it; suspect antivirus, a backup agent or an indexer.' -ForegroundColor Red
  Write-Host '  Windows can name the holder: Resource Monitor > CPU > Associated Handles, search for drag-lint.exe' -ForegroundColor Red
}
exit 1
