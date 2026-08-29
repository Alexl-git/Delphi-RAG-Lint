<#
  run_backlog_index_guard.ps1 -- the backlog is a database, so enumerate it and
  fail when the stated counts disagree with what is on disk.

  WHY THIS EXISTS. The backlog lived in FOUR places that disagreed:
  `docs\INBOX-*.md`, `docs\BACKLOG-editor-integration\` (six notes, invisible to
  EVERY count for weeks), `docs\OPEN-ITEMS.md` (which claimed 13 open / 121
  retired against a real 19 / 136 and did not know the second folder existed),
  and six `docs\BACKLOG-*.md`. A single planning pass over that state found FOUR
  dead premises -- items priced as future work that had already shipped.

  Nothing failed when a count drifted. That is the same "silence is the failure
  mode" this repo already solved once, for docs, with a guard. This is that
  guard for the backlog.

  WHAT IT DOES NOT DO: rename anything. `docs\BACKLOG-*.md` keeps its names
  because SIX TRACKED FILES reference those paths -- a source comment in
  `src\doc\DRagLint.Doc.Facts.pas`, two test headers, `skills\relint\SKILL.md`
  and two docs. The invisibility problem is solved by ENUMERATION, not by moving
  files and leaving dangling references.

  WHY IT SKIPS RATHER THAN FAILS ON A CLEAN CHECKOUT. Every backlog surface is
  gitignored (`.gitignore` lines 91-105, managed by `tools\untrack-internal-docs.ps1`),
  so a fresh clone has NO notes at all. A guard that failed there would fail for
  everyone but the owner. Absence is therefore a SKIP; drift is a FAIL.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  # Overridable so the guard can be pointed at a scratch copy -- which is how
  # its own positive control works. See SELF-TEST at the bottom.
  [string]$Root = "$PSScriptRoot\..\..\docs",
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  if ($Quiet) { if (-not $ok) { $script:fail = $true }; return }
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true }
}

$VALID = @('open','parked-owner','parked-ide-bound','parked-extractor-batch','blocked-repro','ideas')

if (-not (Test-Path $Root)) {
  if (-not $Quiet) { Write-Host "SKIP: no docs dir at $Root" -ForegroundColor Yellow }
  exit 0
}

$notes = @(Get-ChildItem -LiteralPath $Root -Filter 'INBOX-*.md' -File -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -ne 'INBOX-INDEX.md' })
$backs = @(Get-ChildItem -LiteralPath $Root -Filter 'BACKLOG-*.md' -File -ErrorAction SilentlyContinue)

if ($notes.Count -eq 0) {
  if (-not $Quiet) {
    Write-Host 'SKIP: no docs\INBOX-*.md on disk.' -ForegroundColor Yellow
    Write-Host '      The whole backlog is gitignored, so a clean checkout has none.' -ForegroundColor DarkGray
  }
  exit 0
}

$all = @($notes) + @($backs)
$byStatus = @{}
foreach ($v in $VALID) { $byStatus[$v] = 0 }

# ---- every note carries a machine-readable status --------------------------
$missing = @(); $badval = @()
foreach ($f in $all) {
  $head = (Get-Content -LiteralPath $f.FullName -TotalCount 3 -ErrorAction SilentlyContinue) -join "`n"
  if ($head -match 'dl:backlog\s+status=([a-z-]+)') {
    $st = $Matches[1]
    if ($VALID -contains $st) { $byStatus[$st]++ } else { $badval += ("{0} (status={1})" -f $f.Name, $st) }
  } else { $missing += $f.Name }
}
Check 'every backlog note carries a dl:backlog status header' ($missing.Count -eq 0) `
      ("missing on: " + ($missing -join ', '))
Check 'every status is one of the known values' ($badval.Count -eq 0) `
      (($badval -join ', ') + "  valid: $($VALID -join '|')")

# ---- the second inbox cannot be invisible ----------------------------------
# The folder holds six notes and belonged to no count for weeks. A pointer note
# in the enumerated set is what makes it impossible to miss again.
$eiDir = Join-Path $Root 'BACKLOG-editor-integration'
if (Test-Path $eiDir) {
  $ptr = @($notes | Where-Object { $_.Name -match 'editor-integration' })
  $eiN = @(Get-ChildItem -LiteralPath $eiDir -Filter '*.md' -File | Where-Object { $_.Name -ne 'README.md' }).Count
  Check "the editor-integration folder ($eiN note(s)) is represented by an INBOX pointer" `
        ($ptr.Count -ge 1) `
        'docs\BACKLOG-editor-integration\ exists but no INBOX-*editor-integration* note enumerates it'
}

# ---- the index states counts, and they must be DERIVED, not remembered -----
$idx = Join-Path $Root 'INBOX-INDEX.md'
if (Test-Path $idx) {
  $ihead = (Get-Content -LiteralPath $idx -Raw)
  if ($ihead -match 'dl:counts\s+total=(\d+)\s+open=(\d+)\s+retired=(\d+)') {
    $sTot = [int]$Matches[1]; $sOpen = [int]$Matches[2]; $sRet = [int]$Matches[3]
    $done = Join-Path $Root 'INBOX-Done'
    $rTot = $all.Count
    $rOpen = $byStatus['open']
    $rRet  = if (Test-Path $done) { @(Get-ChildItem -LiteralPath $done -Filter '*.md' -File).Count } else { 0 }
    Check "INBOX-INDEX total matches the enumeration ($rTot)"   ($sTot  -eq $rTot)  "index says $sTot, on disk $rTot"
    Check "INBOX-INDEX open count matches ($rOpen)"             ($sOpen -eq $rOpen) "index says $sOpen, on disk $rOpen"
    Check "INBOX-INDEX retired count matches ($rRet)"           ($sRet  -eq $rRet)  "index says $sRet, on disk $rRet"

    # ---- and now the numbers a HUMAN actually reads --------------------------
    # Session 47: the dl:counts comment above was RIGHT (27/8/138) while the two
    # visible headings said "25 notes on disk, 6 of them open" and "19 open
    # notes", and a third line inside the status table said open=6. Nothing
    # failed, because this guard only ever read the invisible comment -- which is
    # this repo's own "silence is the failure mode", reproduced inside the guard
    # written to prevent it. A count nobody can see being right is not the point;
    # the headline is what a planning pass reads.
    #
    # The patterns are deliberately STRICT. If someone rewords a heading the
    # guard fails and they update it -- that is cheaper than a heading that
    # drifts silently for another six sessions.
    $iNotes = @($notes).Count          # INBOX-*.md minus the index itself
    if ($ihead -match '(?m)^#\s+BACKLOG INDEX\s+--\s+(\d+)\s+notes on disk,\s+(\d+)\s+of them\s+`open`') {
      Check "the BACKLOG INDEX headline states the real total ($rTot)"  ([int]$Matches[1] -eq $rTot) `
            ("headline says $($Matches[1]), on disk $rTot")
      Check "the BACKLOG INDEX headline states the real open count ($rOpen)" ([int]$Matches[2] -eq $rOpen) `
            ("headline says $($Matches[2]), on disk $rOpen")
    } else {
      Check 'the BACKLOG INDEX headline states its counts in a checkable form' $false `
            'expected: # BACKLOG INDEX -- N notes on disk, M of them `open`'
    }
    if ($ihead -match '(?m)^#\s+INBOX index\s+--\s+(\d+)\s+notes,\s+(\d+)\s+of them\s+`open`') {
      Check "the INBOX index headline states the real note count ($iNotes)" ([int]$Matches[1] -eq $iNotes) `
            ("headline says $($Matches[1]), on disk $iNotes")
      Check "the INBOX index headline states the real open count ($rOpen)"  ([int]$Matches[2] -eq $rOpen) `
            ("headline says $($Matches[2]), on disk $rOpen")
    } else {
      Check 'the INBOX index headline states its counts in a checkable form' $false `
            'expected: # INBOX index -- N notes, M of them `open`'
    }

    # ---- the status table is a third copy of the same numbers ----------------
    # It said open=6 while the comment said 8. Every row is checked, not just
    # the one that happened to be wrong -- a guard that checks only the observed
    # failure is how the NEXT row drifts.
    $tableRows = 0; $tableBad = @()
    foreach ($v in $VALID) {
      # The table is inside a BLOCKQUOTE, so every row starts "> |", not "|".
      # Written as ^\| first; that matched nothing and the row count silently
      # read 0, which the $tableRows -eq $VALID.Count clause below is there to
      # catch -- a regex that matches nothing must FAIL, not pass vacuously.
      $rx = '(?m)^>?\s*\|\s*`' + [regex]::Escape($v) + '`\s*\|[^|]*\|\s*(\d+)\s*\|'
      if ($ihead -match $rx) {
        $tableRows++
        if ([int]$Matches[1] -ne $byStatus[$v]) { $tableBad += ("{0}: table {1}, on disk {2}" -f $v, $Matches[1], $byStatus[$v]) }
      }
    }
    $tableDetail = if ($tableRows -ne $VALID.Count) {
      "only $tableRows of $($VALID.Count) status rows matched in the table"
    } else { $tableBad -join '; ' }
    Check "the status table's per-status counts match ($tableRows row(s) checked)" `
          (($tableBad.Count -eq 0) -and ($tableRows -eq $VALID.Count)) $tableDetail
  } else {
    Check 'INBOX-INDEX.md carries a dl:counts line' $false `
          'expected: <!-- dl:counts total=N open=N retired=N --> so the counts can be CHECKED rather than trusted'
  }
}

if (-not $Quiet) {
  Write-Host ''
  Write-Host ('  enumerated {0} note(s): ' -f $all.Count) -NoNewline -ForegroundColor DarkGray
  Write-Host (($VALID | ForEach-Object { "$_=$($byStatus[$_])" }) -join '  ') -ForegroundColor DarkGray
}

# ---- SELF-TEST: the guard must be able to FAIL -----------------------------
# A count guard that cannot be made to fail is the vacuous-control failure this
# repo has documented twice in one week. So the guard plants a note with NO
# header in a scratch COPY and re-runs itself against it, expecting failure.
if (-not $Quiet) {
  $scratch = Join-Path $env:TEMP ('draglint_backlogguard_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
  New-Item -ItemType Directory -Path $scratch -Force | Out-Null
  try {
    foreach ($f in $all) { Copy-Item $f.FullName (Join-Path $scratch $f.Name) -Force }
    if (Test-Path $idx) { Copy-Item $idx (Join-Path $scratch 'INBOX-INDEX.md') -Force }
    Set-Content -LiteralPath (Join-Path $scratch 'INBOX-zz-synthetic-unstamped.md') `
                -Value "# a planted note with no dl:backlog header" -Encoding ascii
    & pwsh -NoProfile -File $PSCommandPath -Root $scratch -Quiet
    $childFailed = ($LASTEXITCODE -ne 0)
    Check 'POSITIVE CONTROL: a planted unstamped note makes this guard FAIL' $childFailed `
          'the guard passed against a deliberately broken tree -- it cannot detect drift'
  } finally {
    Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
  }
}

if ($script:fail) { if (-not $Quiet) { Write-Host 'FAIL' -ForegroundColor Red }; exit 1 }
if (-not $Quiet) { Write-Host 'PASS' -ForegroundColor Green }
exit 0
