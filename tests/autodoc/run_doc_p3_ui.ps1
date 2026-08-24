<#
  run_doc_p3_ui.ps1 -- Auto-Document Phase 3, Task 12:
  the UI-affinity fact -- 'UI thread only -- touches FPanel'.

  POSITIVE FINDINGS ONLY, and assertion 4 is the one that matters most. The
  ABSENCE of this line means "no UI touch was DETECTED"; it must never be read,
  or rendered, as "this routine is thread-safe". A curated base-type list
  under-reports by construction -- a control type nobody has added yet simply
  goes unseen -- so a thread-safety claim built on it would be false exactly
  when it mattered. No block may ever contain the words "thread-safe" or
  "thread safe"; that check is cheap and permanent.

  THE FIXTURE DECLARES ITS OWN HIERARCHY so the test does not depend on the VCL
  or DevExpress being indexed. It covers BOTH resolution arms deliberately:
    FPanel   : TCustomPanel  -- the type name is ON the curated list  (direct)
    FDerived : TMyPanel      -- NOT on the list; reachable only through
                                type_ancestors -> TCustomPanel        (ancestry)
  If the ancestry arm ever regresses to the direct-name arm alone, assertion 2
  fails on its own while assertion 1 keeps passing, which is what makes the two
  worth separating.

  NoUi TOUCHES A NON-UI FIELD ON PURPOSE: it needs its own fact (a Writes:) so
  that it HAS a doc block, otherwise "no UI thread only line" would be the
  absence of a block rather than the absence of the fact.

  Runs from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$fx      = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\ui.pas')).Path

function Get-FileMd5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash }

# The contiguous run of ///-prefixed lines immediately above the FIRST line
# matching $declPattern. '' when the declaration is not found.
function Get-BlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return '' }
  $acc = New-Object System.Collections.Generic.List[string]
  for ($j = $idx - 1; $j -ge 0; $j--) {
    if ($lines[$j] -notmatch '^\s*///') { break }
    $acc.Insert(0, $lines[$j].Trim())
  }
  return [string]::Join("`n", $acc.ToArray())
}

# The 'UI thread only ...' line out of a block, /// stripped, or '' when absent.
function Get-UiLine([string]$block) {
  foreach ($l in ($block -split "`n")) {
    $t = ($l -replace '^\s*///\s?','' -replace '</?para>','')
    if ($t -match '^\s*(UI thread only.*)$') { return $Matches[1].Trim() }
  }
  return ''
}

function Get-StoredUi([string]$db, [string]$name) {
  $py = @"
import sqlite3
c = sqlite3.connect(r'$db')
r = c.execute('''SELECT f.ui_affinity FROM symbols s
                 JOIN symbol_facts f ON f.symbol_id = s.id
                 WHERE s.name = ?''', ('$name',)).fetchall()
if not r: print('<norow>')
else: print('<null>' if r[0][0] is None else r[0][0])
"@
  return ((python -c $py 2>&1) -join ' ').Trim()
}

Push-Location C:\TEMP
try {

Write-Host ''
Write-Host '=== ui.pas -- the UI-affinity fact ===' -ForegroundColor Cyan

$sc = Join-Path C:\TEMP 'draglint_docp3_ui'
if (Test-Path $sc) { Remove-Item $sc -Recurse -Force }
New-Item -ItemType Directory -Path $sc | Out-Null
$tgt = Join-Path $sc 'ui.pas'
$db  = Join-Path $sc 'u.sqlite'
Copy-Item $fx $tgt -Force

& $exePath index $sc --db $db 2>$null | Out-Null
Check 'index exits 0' ($LASTEXITCODE -eq 0)

# PRECONDITION: the two arms really are distinct -- FDerived's own type must NOT
# be a curated name, or assertion 2 would silently be a second copy of 1.
$pre = [IO.File]::ReadAllLines($tgt)
Check 'PRECONDITION: FPanel is typed with a CURATED name (direct arm)' `
  (@($pre | Where-Object { $_ -match 'FPanel: TCustomPanel;' }).Count -eq 1) ''
Check 'PRECONDITION: FDerived is typed TMyPanel, which is NOT a curated name (ancestry arm)' `
  (@($pre | Where-Object { $_ -match 'FDerived: TMyPanel;' }).Count -eq 1) ''

& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
Check 'apply exits 0' ($LASTEXITCODE -eq 0)
$md5Cycle1 = Get-FileMd5 $tgt
& $exePath index $sc --db $db 2>$null | Out-Null

$lines   = [IO.File]::ReadAllLines($tgt)
$blkUi   = Get-BlockAbove $lines '^\s*procedure TouchesUi;'
$blkAnc  = Get-BlockAbove $lines '^\s*procedure TouchesUiByAncestry;'
$blkNoUi = Get-BlockAbove $lines '^\s*procedure NoUi;'
Check 'de-vacuator: TouchesUi got a doc block'            ($blkUi   -ne '') ''
Check 'de-vacuator: TouchesUiByAncestry got a doc block'  ($blkAnc  -ne '') ''
Check 'de-vacuator: NoUi got a doc block (so a missing UI line is a real absence)' `
  ($blkNoUi -ne '') ''

# --- (1) direct arm: the type name is on the curated list. ------------------
$uiLine = Get-UiLine $blkUi
Check '1. TouchesUi renders a "UI thread only" line' ($uiLine -ne '') `
  ("block=" + ($blkUi -replace "`n",' | '))
Check '1. that line names FPanel' ($uiLine -match '\bFPanel\b') "got=[$uiLine]"

# --- (2) ancestry arm: the type reaches the list only via type_ancestors. ---
$ancLine = Get-UiLine $blkAnc
Check '2. TouchesUiByAncestry renders a "UI thread only" line (ANCESTRY arm)' ($ancLine -ne '') `
  ("block=" + ($blkAnc -replace "`n",' | '))
Check '2. that line names FDerived' ($ancLine -match '\bFDerived\b') "got=[$ancLine]"

# --- (3) a routine that touches no UI gets no line. -------------------------
Check '3. NoUi has NO "UI thread only" line' ((Get-UiLine $blkNoUi) -eq '') `
  ("block=" + ($blkNoUi -replace "`n",' | '))
Check '3. and the non-UI field FCount is never named as a UI touch' `
  (-not ((($uiLine + ' ' + $ancLine)) -match '\bFCount\b')) "ui=[$uiLine] anc=[$ancLine]"

# --- (4) THE NEVER-CLAIM GUARD. --------------------------------------------
$whole = [IO.File]::ReadAllText($tgt)
Check '4. no doc text anywhere claims "thread-safe" or "thread safe"' `
  (-not ($whole -match '(?i)thread[- ]safe')) ''

# --- (5) the column itself. -------------------------------------------------
$storedUi   = Get-StoredUi $db 'TouchesUi'
$storedNoUi = Get-StoredUi $db 'NoUi'
Check '5. symbol_facts.ui_affinity is non-empty for TouchesUi' `
  (($storedUi -ne '') -and ($storedUi -ne '<null>') -and ($storedUi -ne '<norow>')) "got=[$storedUi]"
Check '5. symbol_facts.ui_affinity is empty or NULL for NoUi' `
  (($storedNoUi -eq '') -or ($storedNoUi -eq '<null>') -or ($storedNoUi -eq '<norow>')) "got=[$storedNoUi]"

# --- (6) idempotency. -------------------------------------------------------
& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
Check '6. a second apply after a reindex is byte-identical' `
  ((Get-FileMd5 $tgt) -eq $md5Cycle1) ("c1=$md5Cycle1 c2=" + (Get-FileMd5 $tgt))

# --- ENCODING. --------------------------------------------------------------
$bytes = [IO.File]::ReadAllBytes($tgt)
Check 'ENCODING: the applied file is strict 7-bit ASCII' `
  (@($bytes | Where-Object { $_ -ge 128 }).Count -eq 0) ''
Check 'ENCODING: the applied file has no bare LF (CRLF throughout)' `
  (([regex]::Matches([IO.File]::ReadAllText($tgt), "(?<!`r)`n")).Count -eq 0) ''

}
finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
