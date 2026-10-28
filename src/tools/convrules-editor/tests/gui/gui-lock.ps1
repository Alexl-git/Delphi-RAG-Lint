# Serialises GUI driver runs across parallel agents (one desktop, one clipboard).
# The lock is the FILE C:\TEMP\claude\lanes\gui.lock, created with CreateNew; its content is "<owner> <iso time>".
# Usage:  gui-lock.ps1 -Acquire -Owner <name> [-LockFile <path>] [-MaxWaitMin 90]   (waits)
#         gui-lock.ps1 -Release -Owner <name> [-LockFile <path>]
# DRV-4: a holder that took the lock through this script is kept alive by a HEARTBEAT: -Acquire starts a
# detached `-Beat` process that touches the file every BeatSec seconds while it still names the owner, and the
# owner line carries the marker "hb=<BeatSec>". A waiter takes a marked lock over ONLY when the heartbeat is
# stale (file untouched for StaleSec, default 120 s = 4 missed beats) -- a 38-minute run is safe while it beats.
# A lock WITHOUT the marker (made by hand, CreateNew, no heartbeat) keeps the old rule: stale after 60 min.
# (A PID check cannot work: each agent tool call is a short-lived shell.)
param([switch]$Acquire, [switch]$Release, [switch]$Beat, [string]$Owner = 'unknown',
      [string]$LockFile = 'C:\TEMP\claude\lanes\gui.lock', [int]$BeatSec = 30, [int]$StaleSec = 120,
      [int]$UnmarkedStaleMin = 60, [double]$MaxWaitMin = 90, [string]$Token = '')
function NamesOwner { try { return ((Get-Content -LiteralPath $LockFile -ErrorAction Stop) -like "$Owner *") } catch { return $false } }
# LOCKBEAT: a heartbeat serves ONE acquire. It keeps beating only while the lock still starts with that
# acquire's own token (owner + acquire time): a release, or a re-acquire under the same owner name, ends it.
# Before this, every acquire's heartbeat matched by owner name alone and lived on, so a runner killed mid-run left
# a lock that never went stale.
function HoldsToken { try { return ((Get-Content -LiteralPath $LockFile -TotalCount 1 -ErrorAction Stop).StartsWith($Token)) } catch { return $false } }
if ($Beat) {
  if ($Token -eq '') { exit 2 }
  while (HoldsToken) { try { (Get-Item -LiteralPath $LockFile).LastWriteTime = Get-Date } catch {}; Start-Sleep -Seconds $BeatSec }
  exit 0
}
if ($Acquire) {
  $deadline = (Get-Date).AddMinutes($MaxWaitMin)
  $mine = "$Owner $(Get-Date -Format o) hb=$BeatSec"
  while ($true) {
    $got = $false; $how = ''
    try {
      [IO.Directory]::CreateDirectory((Split-Path -Parent $LockFile)) | Out-Null
      try { $fs = [IO.File]::Open($LockFile, [IO.FileMode]::CreateNew); $b = [Text.Encoding]::ASCII.GetBytes($mine); $fs.Write($b, 0, $b.Length); $fs.Close(); $got = $true; $how = 'ACQUIRED' }
      catch [IO.IOException] {
        $was = Get-Content -LiteralPath $LockFile -ErrorAction Stop
        $ageSec = ((Get-Date) - (Get-Item -LiteralPath $LockFile).LastWriteTime).TotalSeconds
        $marked = "$was" -match ' hb=\d+'
        if (($marked -and $ageSec -gt $StaleSec) -or ((-not $marked) -and $ageSec -gt ($UnmarkedStaleMin * 60))) {
          [IO.File]::WriteAllText($LockFile, "$mine (stale takeover, silent $([int]$ageSec) s; was: $was)")
          $got = $true; $how = "ACQUIRED (stale, silent $([int]$ageSec) s, marked=$marked)"
        }
      }
    } catch {}
    if ($got) {
      Start-Process -WindowStyle Hidden -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile', '-File', $PSCommandPath, '-Beat', '-Owner', $Owner, '-LockFile', $LockFile, '-BeatSec', $BeatSec, '-Token', "`"$mine`"") | Out-Null
      # ATOMLOCK: the lock is held, so no other driver's editor can be mid-start: reclaim VCL atoms leaked by killed editors.
      try { . "$PSScriptRoot\vcl-atoms.ps1"; Write-Output (VclAtomsReclaim) } catch { Write-Output "vcl-atoms: reclaim failed: $($_.Exception.Message)" }
      Write-Output "$how by $Owner"; exit 0
    }
    if ((Get-Date) -gt $deadline) { Write-Output "TIMEOUT held by $(Get-Content -LiteralPath $LockFile -ErrorAction SilentlyContinue)"; exit 1 }
    Start-Sleep -Seconds 10
  }
}
if ($Release) {
  if ((Test-Path -LiteralPath $LockFile) -and (NamesOwner)) { [IO.File]::Delete($LockFile); Write-Output "RELEASED by $Owner" } else { Write-Output "NOT HELD by $Owner" }
}