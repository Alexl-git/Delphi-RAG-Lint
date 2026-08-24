<#
  scoped-resolve-ab.ps1 -- A/B equivalence harness for the scoped call-target
  resolve.

  INBOX-incremental-index-hangs-on-large-db. The open half of that note is
  relaxing ScopedResolveIsSound's type-equality gate so that ADDING units to an
  index stops forcing a whole-database calls resolve (~37 min on a 2 GB index).
  That is correctness-sensitive: the scoped pass must produce EXACTLY the edges
  the whole-database pass would.

  DRAGLINT_NO_SCOPED_RESOLVE is the hatch that makes this an A/B of ONE binary
  over ONE corpus, so the compiler is not an uncontrolled variable.

  TWO DELTA SHAPES, AND ONLY ONE OF THEM IS THE OPEN QUESTION
  -----------------------------------------------------------
  -Mode Change (default) is the ordinary --recompile shape: the same type names
  come back out, so today's gate ALREADY allows scoping. It measures the prize
  (4.2x on ORM3, 2026-08-17) but it cannot test a relaxed gate, because the gate
  it exercises was never closed.

  -Mode Add is the shape the open item is about: file rows are DELETED, so those
  files are re-indexed as genuinely NEW and the run declares type names it never
  withdrew. Today's gate DECLINES that, which is why running -Mode Add against
  an unmodified build is expected to print *** VACUOUS ***. That vacuous banner
  is the POSITIVE CONTROL: it proves the mode really produces the addition shape
  and that the gate really is what stands in the way. Only with
  -AllowAdditions (which sets DRAGLINT_SCOPED_RESOLVE_ADDITIONS on run A) does
  the comparison become meaningful.

  METHOD
    1. Copy the subject DB twice (A and B) -- the real index is never written.
    2. Apply the SAME delta to both copies, so both runs face an IDENTICAL one.
    3. Index into A normally (the scoped path may engage) and into B with
       DRAGLINT_NO_SCOPED_RESOLVE=1 (whole database, always).
    4. Compare call_edges EXACTLY -- a sorted digest of (ref_id,
       target_symbol_id, confidence, receiver_type_symbol_id) -- plus row counts,
       and report both timings.

  WHY A COPY AND A SCRATCH MANIFEST: `index <dir> --db <project db>` is the
  folder-scan-onto-a-project-DB shape this repo forbids (it changes what the
  section owns). The scratch manifest reuses the project's own .dproj, so both
  runs build the SAME closure the real section would.

  READ THE RESULT HONESTLY: equal digests prove the two passes AGREE on this
  corpus and this delta. They do not prove the gate is safe to relax in general
  -- that argument lives in the note. A DIFFERENCE is decisive the other way.

  Usage:
    pwsh -File tools\perf\scoped-resolve-ab.ps1 `
         -Dproj C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj `
         -DbPath C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite `
         [-DeleteFiles 12] [-Mode Change|Add] [-AllowAdditions]
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Dproj,
    # NOTE: -DbPath, not -Db. Under [CmdletBinding()] PowerShell adds the common
  # parameters and 'Db' is an ambiguous prefix of -Debug's alias, so -Db is
  # rejected before the script ever runs.
  [Parameter(Mandatory=$true)][string]$DbPath,
  [int]$DeleteFiles = 12,
  # Change = blank sha256 (files are CHANGED; today's gate already allows scoping).
  # Add    = delete the file rows (files are NEW; today's gate declines).
  [ValidateSet('Change','Add')][string]$Mode = 'Change',
  # Sets DRAGLINT_SCOPED_RESOLVE_ADDITIONS on run A. Without it, -Mode Add is
  # expected to be VACUOUS -- that is the control, not a failure.
  [switch]$AllowAdditions,
  # Which relaxation to measure.
  #   widened    = the real behaviour: additions allowed, and the member names
  #                reachable through each added type pulled into the scope.
  #   permissive = the widening switched OFF. KNOWN UNSOUND -- it drops inherited
  #                edges (tests\autotest\pending_scoped_resolve_additions.ps1
  #                pins exactly that). An instrument for showing the channel is
  #                real, never a setting to run for real work.
  [ValidateSet('widened','permissive')][string]$AdditionsMode = 'widened',
  [string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Work = 'C:\TEMP\draglint_scoped_ab'
)

$ErrorActionPreference = 'Stop'
$exePath = (Resolve-Path $Exe).Path
if (-not (Test-Path $DbPath)) { throw "subject DB not found: $DbPath" }
if (-not (Test-Path $Dproj)) { throw "project file not found: $Dproj" }

if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
New-Item -ItemType Directory -Path $Work | Out-Null

$dbA = Join-Path $Work 'a.sqlite'
$dbB = Join-Path $Work 'b.sqlite'
Write-Host ("copying {0:N0} MB x2 ..." -f ((Get-Item $DbPath).Length / 1MB)) -ForegroundColor Cyan
Copy-Item $DbPath $dbA; Copy-Item $DbPath $dbB

# --- 2. identical delta in both copies -------------------------------------
$py = Join-Path $Work 'delta.py'
@'
import sqlite3, sys
db, n, mode = sys.argv[1], int(sys.argv[2]), sys.argv[3]
con = sqlite3.connect(db)
# CASCADES ARE OFF BY DEFAULT IN PYTHON'S SQLITE. Without this pragma a DELETE
# FROM files leaves every symbol and ref of that file behind, and 'Add' mode
# would simulate nothing at all -- it would just corrupt the copy.
con.execute("PRAGMA foreign_keys=ON")
c = con.cursor()
# The same N files in both copies -- deterministic order, so A and B face an
# identical delta.
rows = c.execute("SELECT id, path FROM files WHERE lower(path) LIKE '%.pas' "
                 "ORDER BY path LIMIT ?", (n,)).fetchall()
if mode == 'change':
    # CHANGED, NOT NEW. The file is re-parsed from identical content, so the
    # same type names come back out and the type-equality gate holds -- the
    # ordinary --recompile shape the scoped pass was built for.
    for fid, path in rows:
        c.execute("UPDATE files SET sha256='force-reparse' WHERE id=?", (fid,))
    verb = "invalidated %d file hash(es)" % len(rows)
else:
    # NEW. Deleting the row makes the file unknown to the index, so re-indexing
    # it ADDS type names that were never withdrawn: FScopeTypesBefore is empty
    # and FScopeTypesAfter is not. That is exactly the shape today's gate
    # declines, and exactly the shape the open item wants to allow.
    #
    # The cascades matter and are the reason for the pragma above:
    #   symbols.file_id  -> CASCADE   (the file's declarations go)
    #   refs.file_id     -> CASCADE   (its refs go)
    #   call_edges.ref_id / .target_symbol_id -> CASCADE
    #   call_edges.receiver_type_symbol_id    -> SET NULL
    # so edges FROM untouched files INTO these files also disappear, which is
    # what makes this a faithful stand-in for "these units were never indexed".
    before = c.execute("SELECT COUNT(*) FROM call_edges").fetchone()[0]
    for fid, path in rows:
        c.execute("DELETE FROM files WHERE id=?", (fid,))
    after = c.execute("SELECT COUNT(*) FROM call_edges").fetchone()[0]
    verb = "deleted %d file row(s); call_edges %d -> %d" % (len(rows), before, after)
con.commit()
print(verb)
for _, p in rows[:3]:
    print("   " + p)
con.close()
'@ | Set-Content $py -Encoding ascii

$deltaMode = $Mode.ToLower()
Write-Host "creating an identical delta in both copies (mode=$deltaMode) ..." -ForegroundColor Cyan
& python $py $dbA $DeleteFiles $deltaMode
& python $py $dbB $DeleteFiles $deltaMode | Out-Null

# --- 3. one scratch manifest per copy --------------------------------------
function WriteCfg([string]$Path, [string]$DbPath) {
@"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 4096, "enginePath": "auto", "maxJobs": 1 },
  "indexes": {
    "outDir": "$((Split-Path $DbPath -Parent) -replace '\\','\\')",
    "sections": [
      { "name": "AbSection", "db": "$((Split-Path $DbPath -Leaf))", "include": ["$($Dproj -replace '\\','\\')"] }
    ]
  }
}
"@ | Set-Content $Path -Encoding ascii
}
$cfgA = Join-Path $Work 'a.json'; WriteCfg $cfgA $dbA
$cfgB = Join-Path $Work 'b.json'; WriteCfg $cfgB $dbB

function RunIndex([string]$Cfg, [string]$Log, [bool]$NoScoped, [string]$Additions) {
  # BOTH hatches are cleared first. They are process-global, and a leftover from
  # run A silently turns run B into a repeat of it -- an A/B that compares a
  # thing with itself and reports EQUIVALENT.
  Remove-Item Env:\DRAGLINT_NO_SCOPED_RESOLVE        -ErrorAction SilentlyContinue
  Remove-Item Env:\DRAGLINT_SCOPED_RESOLVE_ADDITIONS -ErrorAction SilentlyContinue
  if ($NoScoped)              { $env:DRAGLINT_NO_SCOPED_RESOLVE        = '1' }
  if ($Additions -ne '')      { $env:DRAGLINT_SCOPED_RESOLVE_ADDITIONS = $Additions }
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  & $exePath index --all --config $Cfg --only AbSection --jobs 1 *> $Log
  $sw.Stop()
  Remove-Item Env:\DRAGLINT_NO_SCOPED_RESOLVE        -ErrorAction SilentlyContinue
  Remove-Item Env:\DRAGLINT_SCOPED_RESOLVE_ADDITIONS -ErrorAction SilentlyContinue
  return $sw.Elapsed.TotalSeconds
}

Push-Location C:\TEMP
try {
  # 'widened' is the engine's DEFAULT for any non-empty value, so it is passed as
  # '1' rather than as the word -- the engine only special-cases 'permissive'.
  $aAdd   = if (-not $AllowAdditions)          { ''           }
            elseif ($AdditionsMode -eq 'widened') { '1'        }
            else                                  { $AdditionsMode }
  $aLabel = if ($AllowAdditions) { "A: scoped allowed, DRAGLINT_SCOPED_RESOLVE_ADDITIONS=$AdditionsMode ..." }
            else                 { 'A: scoped path allowed ...' }
  Write-Host $aLabel -ForegroundColor Cyan
  $secA = RunIndex $cfgA (Join-Path $Work 'a.log') $false $aAdd
  Write-Host "B: DRAGLINT_NO_SCOPED_RESOLVE=1 (whole database) ..." -ForegroundColor Cyan
  $secB = RunIndex $cfgB (Join-Path $Work 'b.log') $true ''
} finally { Pop-Location }

# VACUITY GUARD. If A did not actually take the scoped path there is nothing to
# compare, and the digests will match for the uninteresting reason. The most
# common cause is a subject DB whose fingerprint is stale: the run then re-parses
# EVERY file, blows the one-in-three limit, and declines scoping. Reindex the
# subject DB once and re-run.
#
# ONE CASE WHERE VACUOUS IS THE POINT: -Mode Add without -AllowAdditions. There
# the decline IS the result being measured, so it is reported as a control that
# PASSED -- but only when it declined for the type-name reason. A decline for
# any other reason (stale fingerprint, the 1-in-3 limit) would look identical
# from outside while proving something else entirely, which is the exact way a
# control goes quietly worthless.
$aLog     = Join-Path $Work 'a.log'
$aScoped  = $null -ne (Select-String -Path $aLog -Pattern 'starting SCOPED pass' | Select-Object -First 1)
$aWhyLine = (Select-String -Path $aLog -Pattern 'whole database because' | Select-Object -First 1)
$aWhy     = if ($aWhyLine) { $aWhyLine.Line.Trim() } else { '' }
$isControl = ($Mode -eq 'Add') -and (-not $AllowAdditions)

if (-not $aScoped) {
  Write-Host ''
  if ($isControl) {
    $onTypeNames = $aWhy -match 'changed the set of declared type names|withdrew the declared type name'
    if ($onTypeNames) {
      Write-Host '  CONTROL PASSED: run A declined scoping, and for the reason under test.' -ForegroundColor Green
      Write-Host ("      {0}" -f $aWhy) -ForegroundColor Green
      Write-Host '      Re-run with -AllowAdditions to compare scoped against whole database.' -ForegroundColor Green
    } else {
      Write-Host '  *** CONTROL INVALID: A declined, but NOT on the type-name gate. ***' -ForegroundColor Red
      Write-Host ("      {0}" -f $aWhy) -ForegroundColor Red
      Write-Host '      This run measures that other reason, not the open item. Fix it and re-run.' -ForegroundColor Red
    }
  } else {
    Write-Host '  *** VACUOUS: run A did NOT take the scoped path, so this proves nothing. ***' -ForegroundColor Red
    if ($aWhy) { Write-Host ("      {0}" -f $aWhy) -ForegroundColor Red }
    Write-Host '      Most likely the subject DB fingerprint is stale -- reindex it, then re-run.' -ForegroundColor Red
  }
} elseif ($isControl) {
  Write-Host ''
  Write-Host '  *** CONTROL FAILED: A took the SCOPED path with no -AllowAdditions. ***' -ForegroundColor Red
  Write-Host '      Either the delta is not the addition shape, or the gate is already relaxed.' -ForegroundColor Red
}

# --- 4. compare ------------------------------------------------------------
$cmp = Join-Path $Work 'cmp.py'
@'
import sqlite3, sys, hashlib
def rows(db):
    con = sqlite3.connect('file:%s?mode=ro' % db.replace('\\','/'), uri=True)
    c = con.cursor()
    n = c.execute("SELECT COUNT(*) FROM call_edges").fetchone()[0]
    # IDENTIFY EVERY ROW BY SOURCE POSITION, NEVER BY ROWID.
    #
    # The first version of this digested (ref_id, target_symbol_id) directly.
    # That is safe in -Mode Change, where rows are updated in place, and WRONG in
    # -Mode Add: the deleted files are re-INSERTED and take fresh ids, so two
    # runs that agree perfectly about the code can still disagree about the
    # integers -- a *** DIFFERENT *** that means nothing and costs an afternoon.
    # (path, line, col, name) and the target's qualified_name are what the two
    # passes actually have to agree on, and they survive re-numbering. This is
    # the same key tests\autotest\run_scoped_resolve_equivalence.ps1 uses.
    #
    # receiver_type is in the digest on purpose: the scoped pass also updates
    # receivers, so a check that ignored it would pass while the two runs
    # disagreed about exactly the thing scoping touches.
    out = c.execute("""
            SELECT f.path, r.start_line, r.start_col, r.name_text,
                   COALESCE(s.qualified_name, '?'),
                   COALESCE(e.confidence, ''),
                   COALESCE(rt.qualified_name, '<NULL>')
              FROM call_edges e
              JOIN refs    r  ON r.id  = e.ref_id
              JOIN files   f  ON f.id  = r.file_id
              LEFT JOIN symbols s  ON s.id  = e.target_symbol_id
              LEFT JOIN symbols rt ON rt.id = e.receiver_type_symbol_id
             ORDER BY f.path, r.start_line, r.start_col, r.name_text""").fetchall()
    con.close()
    return n, out

def digest(db):
    n, out = rows(db)
    h = hashlib.sha256()
    for row in out:
        h.update(repr(row).encode())
    return n, h.hexdigest()

na, ha = digest(sys.argv[1])
nb, hb = digest(sys.argv[2])
print("A  call_edges=%-9d digest=%s" % (na, ha[:20]))
print("B  call_edges=%-9d digest=%s" % (nb, hb[:20]))
if ha == hb:
    print("EQUIVALENT")
else:
    print("*** DIFFERENT ***")
    # A bare mismatch is not actionable, and the residual channel this harness
    # exists to probe (an edge INHERITED from an untouched ancestor) shows up as
    # rows present in B and absent from A. Name them.
    ra, rb = set(rows(sys.argv[1])[1]), set(rows(sys.argv[2])[1])
    onlyB, onlyA = sorted(rb - ra), sorted(ra - rb)
    print("   in B (whole DB) but NOT in A (scoped): %d" % len(onlyB))
    for x in onlyB[:10]:
        print("      " + " | ".join(str(i) for i in x))
    print("   in A but NOT in B: %d" % len(onlyA))
    for x in onlyA[:10]:
        print("      " + " | ".join(str(i) for i in x))
'@ | Set-Content $cmp -Encoding ascii

Write-Host ''
Write-Host '=== scoped vs whole-database calls resolve ===' -ForegroundColor Cyan
& python $cmp $dbA $dbB
Write-Host ''
"  A (scoped allowed) : {0,8:N1} s" -f $secA
"  B (whole database) : {0,8:N1} s" -f $secB
Write-Host ''
Write-Host '  which shape each run actually took (from its own announce line):' -ForegroundColor Cyan
foreach ($p in @(@{n='A';f=Join-Path $Work 'a.log'}, @{n='B';f=Join-Path $Work 'b.log'})) {
  $line = (Select-String -Path $p.f -Pattern 'starting (WHOLE-DB|SCOPED) pass' | Select-Object -First 1)
  "    {0}: {1}" -f $p.n, $(if ($line) { $line.Line.Trim() } else { '(no announce line -- old binary?)' })
  $why = (Select-String -Path $p.f -Pattern 'whole database because' | Select-Object -First 1)
  if ($why) { "       {0}" -f $why.Line.Trim() }
}
Write-Host ''
Write-Host "  logs + copies: $Work" -ForegroundColor DarkGray
