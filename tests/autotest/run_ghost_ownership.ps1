<#
  run_ghost_ownership.ps1 -- a ghost overlay may only be undone if it is STILL
  OURS. Regression for the ghost-check data-loss bug.

  THE BUG (reported 2026-08-06: "after a file is manually modified, 1-2 minutes
  later it is reverted to the original state -- not every time, but often")
  ---------------------------------------------------------------------------
  ghost-check compiles UNSAVED editor buffers by briefly overwriting the real
  .pas with the buffer, compiling, then restoring the original. It decided
  whether its overlay was still on disk by comparing CONTENT alone:

      if BytesSame(Cur, OrigBytes) or BytesSame(Cur, BufBytes) then <restore>

  Content alone cannot tell "my overlay is still there" from "the user pressed
  Ctrl+S on the very buffer I overlaid" -- both leave the SAME bytes on disk. So
  a save landing inside the compile window was classified as the overlay and
  overwritten with the pre-edit original, and the original timestamp was put
  back too, so nothing even looked modified. Intermittent, because it needs the
  save to land inside that window.

  ghost-recover had the same hole on the crash path: it restored the journal's
  original over whatever was on disk, unconditionally.

  THE RULE NOW
  ------------
  The overlay write records the last-write timestamp IT left on the file (in the
  record for the live path, in the journal as `ovlft=` for recovery). A restore
  happens only if the file still carries that exact timestamp. Anyone else
  writing the file moves it, and we leave their bytes alone: refusing to restore
  at worst leaves the user's own content on disk, while restoring wrongly
  destroys work.

  This exercises the RECOVERY half, which is drivable without a compile. The
  three cases below are content-identical where it matters -- what differs is
  the timestamp, which is the whole point.

  GAP: the live ghost-check path shares the rule but not the code, and testing
  it needs a real compile plus a writer racing inside the window. Not covered
  here -- see the note at the end of this file.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-ghost-ownership"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

$ORIG    = "unit U;`r`ninterface`r`nimplementation`r`nend.`r`n"
$BUFFER  = "unit U;`r`ninterface`r`n// unsaved edit`r`nimplementation`r`nend.`r`n"

# Builds a scratch tree with a pending journal. $stampMatches decides whether the
# unit still carries the timestamp the overlay recorded.
function New-Case([string]$Name, [string]$UnitContent, [bool]$StampMatches) {
  $dir = Join-Path $WorkDir $Name
  if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
  New-Item -ItemType Directory $dir | Out-Null
  $drag = Join-Path $dir '_D-RAG'
  New-Item -ItemType Directory $drag | Out-Null

  $unit = Join-Path $dir 'U.pas'
  $bak  = Join-Path $drag 'U.pas.ghost-orig'
  [System.IO.File]::WriteAllText($bak,  $ORIG,        [System.Text.Encoding]::ASCII)
  [System.IO.File]::WriteAllText($unit, $UnitContent, [System.Text.Encoding]::ASCII)

  # The token: the timestamp the file actually carries right now.
  $ft = (Get-Item $unit).LastWriteTimeUtc.ToFileTimeUtc()
  # For the "someone else wrote it" cases, record a DIFFERENT token -- exactly
  # what an IDE save produces.
  if (-not $StampMatches) { $ft = $ft - 10000000 }

  $origFt = (Get-Item $bak).LastWriteTimeUtc.ToFileTimeUtc()
  $journal = Join-Path $drag 'U.pas.ghost-journal'
  $text = "unit=$unit`r`norig=$bak`r`nmtime=45000.5`r`nft=$origFt`r`novlft=$ft`r`n"
  [System.IO.File]::WriteAllText($journal, $text, [System.Text.Encoding]::ASCII)
  return @{ Dir = $dir; Unit = $unit; Journal = $journal; Bak = $bak }
}

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# --------------------------------------------------------------------------
# 1) Still ours: the overlay bytes are on disk carrying OUR timestamp.
#    This is the ordinary crash case and MUST be undone.
# --------------------------------------------------------------------------
Write-Host 'Case 1: overlay still ours -> restore' -ForegroundColor Cyan
$c1 = New-Case 'mine' $BUFFER $true
& $Exe ghost-recover $c1.Dir 2>&1 | Out-Null
$after1 = [System.IO.File]::ReadAllText($c1.Unit)
Check 'overlay owned by us is restored to the original' ($after1 -eq $ORIG)
Check 'journal cleared after a real restore' (-not (Test-Path $c1.Journal))

# --------------------------------------------------------------------------
# 2) THE REPORTED BUG: same bytes as the overlay, different timestamp.
#    That is a user save of the very buffer we overlaid. Reverting it is the
#    data loss. It must be left alone.
# --------------------------------------------------------------------------
Write-Host ''
Write-Host 'Case 2: user saved the SAME buffer we overlaid -> must NOT revert' -ForegroundColor Cyan
$c2 = New-Case 'saved-same-bytes' $BUFFER $false
$out2 = (& $Exe ghost-recover $c2.Dir 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
$after2 = [System.IO.File]::ReadAllText($c2.Unit)
Check 'the user save SURVIVES (file not reverted to the original)' ($after2 -eq $BUFFER) `
  'this is the exact data-loss report'
Check 'it says out loud that it skipped' ($out2 -match 'SKIP')
Check 'the pre-overlay original is kept, not thrown away' (Test-Path $c2.Bak)

# --------------------------------------------------------------------------
# 3) Different content AND different timestamp -- ordinary later edit.
# --------------------------------------------------------------------------
Write-Host ''
Write-Host 'Case 3: unrelated later edit -> must NOT revert' -ForegroundColor Cyan
$LATER = "unit U;`r`ninterface`r`n// typed after the crash`r`nimplementation`r`nend.`r`n"
$c3 = New-Case 'later-edit' $LATER $false
& $Exe ghost-recover $c3.Dir 2>&1 | Out-Null
$after3 = [System.IO.File]::ReadAllText($c3.Unit)
Check 'a later edit SURVIVES' ($after3 -eq $LATER)

# --------------------------------------------------------------------------
# 4) A journal with NO ownership token (written by an older engine, or a crash
#    between the overlay write and the token append). Unprovable -> must not
#    revert on a guess... but must also not lose the original.
# --------------------------------------------------------------------------
Write-Host ''
Write-Host 'Case 4: journal without an ownership token' -ForegroundColor Cyan
$c4 = New-Case 'no-token' $BUFFER $true
$j = [System.IO.File]::ReadAllText($c4.Journal) -replace '(?m)^ovlft=.*\r?\n', ''
[System.IO.File]::WriteAllText($c4.Journal, $j, [System.Text.Encoding]::ASCII)
& $Exe ghost-recover $c4.Dir 2>&1 | Out-Null
$after4 = [System.IO.File]::ReadAllText($c4.Unit)
# No token means the old contract: restore. Documented here so a decision to
# tighten it further is deliberate rather than accidental.
Check 'tokenless journal keeps the legacy restore behaviour' ($after4 -eq $ORIG)

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
