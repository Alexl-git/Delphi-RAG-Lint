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

  METHOD
    1. Copy the subject DB twice (A and B) -- the real index is never written.
    2. Remove the same N files' rows from BOTH copies, so both runs face an
       IDENTICAL delta and those files are re-indexed as new.
    3. Index into A normally (the scoped path may engage) and into B with
       DRAGLINT_NO_SCOPED_RESOLVE=1 (whole database, always).
    4. Compare call_edges EXACTLY -- a sorted digest of (ref_id,
       target_symbol_id, kind) -- plus row counts, and report both timings.

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
         [-DeleteFiles 12]
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Dproj,
    # NOTE: -DbPath, not -Db. Under [CmdletBinding()] PowerShell adds the common
  # parameters and 'Db' is an ambiguous prefix of -Debug's alias, so -Db is
  # rejected before the script ever runs.
  [Parameter(Mandatory=$true)][string]$DbPath,
  [int]$DeleteFiles = 12,
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
db, n = sys.argv[1], int(sys.argv[2])
con = sqlite3.connect(db); c = con.cursor()
# INVALIDATE THE STORED HASH -- do not delete the file row.
#
# Deleting the row makes the file NEW, so the run declares type names it did
# not withdraw, FScopeTypesBefore != FScopeTypesAfter, and ScopedResolveIsSound
# declines. Both sides then take the whole-database pass and the A/B compares
# whole against whole -- it passes while proving nothing. (Observed, first
# attempt at this harness.)
#
# Blanking sha256 instead makes the file merely CHANGED. It is re-parsed from
# identical content, so the same type names come back out and the gate holds --
# which is the ordinary --recompile shape the scoped pass is built for.
rows = c.execute("SELECT id, path FROM files WHERE lower(path) LIKE '%.pas' "
                 "ORDER BY path LIMIT ?", (n,)).fetchall()
for fid, path in rows:
    c.execute("UPDATE files SET sha256='force-reparse' WHERE id=?", (fid,))
con.commit()
print("invalidated %d file hash(es)" % len(rows))
for _, p in rows[:3]:
    print("   " + p)
con.close()
'@ | Set-Content $py -Encoding ascii

Write-Host "creating an identical delta in both copies ..." -ForegroundColor Cyan
& python $py $dbA $DeleteFiles
& python $py $dbB $DeleteFiles | Out-Null

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

function RunIndex([string]$Cfg, [string]$Log, [bool]$NoScoped) {
  $env:DRAGLINT_NO_SCOPED_RESOLVE = $(if ($NoScoped) { '1' } else { $null })
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  & $exePath index --all --config $Cfg --only AbSection --jobs 1 *> $Log
  $sw.Stop()
  Remove-Item Env:\DRAGLINT_NO_SCOPED_RESOLVE -ErrorAction SilentlyContinue
  return $sw.Elapsed.TotalSeconds
}

Push-Location C:\TEMP
try {
  Write-Host "A: scoped path allowed ..." -ForegroundColor Cyan
  $secA = RunIndex $cfgA (Join-Path $Work 'a.log') $false
  Write-Host "B: DRAGLINT_NO_SCOPED_RESOLVE=1 (whole database) ..." -ForegroundColor Cyan
  $secB = RunIndex $cfgB (Join-Path $Work 'b.log') $true
} finally { Pop-Location }

# VACUITY GUARD. If A did not actually take the scoped path there is nothing to
# compare, and the digests will match for the uninteresting reason. The most
# common cause is a subject DB whose fingerprint is stale: the run then re-parses
# EVERY file, blows the one-in-three limit, and declines scoping. Reindex the
# subject DB once and re-run.
$aScoped = $null -ne (Select-String -Path (Join-Path $Work 'a.log') -Pattern 'starting SCOPED pass' | Select-Object -First 1)
if (-not $aScoped) {
  Write-Host ''
  Write-Host '  *** VACUOUS: run A did NOT take the scoped path, so this proves nothing. ***' -ForegroundColor Red
  $why = (Select-String -Path (Join-Path $Work 'a.log') -Pattern 'whole database because' | Select-Object -First 1)
  if ($why) { Write-Host ("      {0}" -f $why.Line.Trim()) -ForegroundColor Red }
  Write-Host '      Most likely the subject DB fingerprint is stale -- reindex it, then re-run.' -ForegroundColor Red
}

# --- 4. compare ------------------------------------------------------------
$cmp = Join-Path $Work 'cmp.py'
@'
import sqlite3, sys, hashlib
def digest(db):
    con = sqlite3.connect('file:%s?mode=ro' % db.replace('\\','/'), uri=True)
    c = con.cursor()
    n = c.execute("SELECT COUNT(*) FROM call_edges").fetchone()[0]
    h = hashlib.sha256()
    # The REAL column list -- confirmed with PRAGMA table_info, not assumed.
    # receiver_type_symbol_id is in the digest on purpose: the scoped pass also
    # updates receivers, so an equivalence check that ignored it would pass while
    # the two runs disagreed about exactly the thing scoping touches.
    for row in c.execute("SELECT ref_id, target_symbol_id, confidence, "
                         "receiver_type_symbol_id FROM call_edges "
                         "ORDER BY ref_id, target_symbol_id"):
        h.update(repr(row).encode())
    con.close()
    return n, h.hexdigest()
na, ha = digest(sys.argv[1])
nb, hb = digest(sys.argv[2])
print("A  call_edges=%-9d digest=%s" % (na, ha[:20]))
print("B  call_edges=%-9d digest=%s" % (nb, hb[:20]))
print("EQUIVALENT" if ha == hb else "*** DIFFERENT ***")
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
