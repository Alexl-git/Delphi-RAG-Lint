<#
  run_doc_p2_index.ps1 -- Auto-Document Phase 2, Task 2: index-time analyzer
  hook + invalidation proof.

  Indexes fixtures\docp2index\p2index.pas (one function, DoWork) ALONE first,
  then fixtures\docp2index\anchor.pas (one function, AnchorFunc) SECOND and
  SEPARATELY -- so anchor's symbol ids land strictly higher than DoWork's, and
  anchor is never reindexed again afterward. This engineers a REAL rowid
  change for DoWork across the edit+reindex below: SQLite's plain `INTEGER
  PRIMARY KEY` (no AUTOINCREMENT) reuses rowid 1 once a table is fully
  emptied, so a single-file DB would silently reindex DoWork onto the SAME id
  both times -- masking a broken ON DELETE CASCADE (PutSymbolFacts' UPSERT
  would just overwrite the same row regardless of whether the cascade fired).
  With anchor.pas's rows staying live in the `symbols` table throughout,
  DoWork's reinserted row is guaranteed a NEW id strictly higher than the
  current max -- see anchor.pas's own header comment for the same rationale.

  Via Python (stdlib sqlite3, C:\Python314\python, read-only `?mode=ro` open):
    1. BEFORE edit: assert exactly one symbol_facts row for DoWork (Present),
       total symbol_facts rows == 2 (DoWork + AnchorFunc -- the DB's whole
       routine-with-a-body count), no orphans.
    2. Edit p2index.pas (add a blank line right after `implementation`, which
       shifts DoWork's ImplStartLine/ImplEndLine down by one), then reindex
       p2index.pas ONLY (anchor.pas is not re-touched).
    3. AFTER edit: DoWork's CURRENT symbol id differs from its OLD one (the
       canary proving the rowid-reuse concern above didn't mask the test); a
       symbol_facts row exists for the NEW id (Present); NO symbol_facts row
       remains for the OLD id (the actual cascade / invalidation proof);
       total rows are still == 2 (no orphan, no duplicate).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$py = 'C:\Python314\python.exe'
if (-not (Test-Path $py)) {
  Write-Host '[SKIP] run_doc_p2_index: Python not found at C:\Python314' -ForegroundColor Yellow
  exit 0
}

$exePath    = (Resolve-Path $Exe).Path
$fixtureDir = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp2index')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp2index'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target       = Join-Path $scratch 'p2index.pas'
$anchorTarget = Join-Path $scratch 'anchor.pas'
$db           = Join-Path $scratch 'docp2index.sqlite'
Copy-Item (Join-Path $fixtureDir 'p2index.pas') $target       -Force
Copy-Item (Join-Path $fixtureDir 'anchor.pas')  $anchorTarget -Force

# Python query helper (stdlib sqlite3 only): two modes.
#   query.py <db> <routineName>          -> SYMID=/PRESENT=/TOTAL=/ROUTINE_COUNT=/ORPHANS=
#   query.py <db> --has-symid <id>       -> HAS_SYMID=0|1
# PRESENT/HAS_SYMID mirror ISymbolStore.GetSymbolFacts' Present contract: a
# symbol_facts row exists for that exact symbol_id (Task 2 writes an
# EMPTY-but-Present row, so "row exists" IS "Present" here). ORPHANS counts
# symbol_facts rows whose symbol_id no longer has a matching symbols row
# (must be 0 always -- that is the ON DELETE CASCADE invalidation contract).
$queryPy = @'
import sqlite3, sys

ROUTINE_KINDS = ("function", "procedure", "method", "constructor", "destructor")

def main():
    db = sys.argv[1]
    con = sqlite3.connect("file:{}?mode=ro".format(db), uri=True)
    cur = con.cursor()

    if sys.argv[2] == "--has-symid":
        symid = int(sys.argv[3])
        n = cur.execute("SELECT COUNT(*) FROM symbol_facts WHERE symbol_id = ?", (symid,)).fetchone()[0]
        print("HAS_SYMID={}".format(n))
        return

    name = sys.argv[2]
    ph = ",".join("?" for _ in ROUTINE_KINDS)
    row = cur.execute(
        "SELECT id FROM symbols WHERE name = ? AND kind IN ({}) "
        "AND impl_start_line IS NOT NULL AND impl_start_line > 0".format(ph),
        (name,) + ROUTINE_KINDS).fetchone()
    symid = row[0] if row else -1
    print("SYMID={}".format(symid))

    present = 0
    if symid >= 0:
        present = cur.execute("SELECT COUNT(*) FROM symbol_facts WHERE symbol_id = ?", (symid,)).fetchone()[0]
    print("PRESENT={}".format(present))

    total = cur.execute("SELECT COUNT(*) FROM symbol_facts").fetchone()[0]
    print("TOTAL={}".format(total))

    routine_count = cur.execute(
        "SELECT COUNT(*) FROM symbols WHERE kind IN ({}) "
        "AND impl_start_line IS NOT NULL AND impl_start_line > 0".format(ph),
        ROUTINE_KINDS).fetchone()[0]
    print("ROUTINE_COUNT={}".format(routine_count))

    orphans = cur.execute(
        "SELECT COUNT(*) FROM symbol_facts sf "
        "LEFT JOIN symbols s ON s.id = sf.symbol_id "
        "WHERE s.id IS NULL").fetchone()[0]
    print("ORPHANS={}".format(orphans))

main()
'@
$queryPyPath = Join-Path $scratch 'query.py'
[System.IO.File]::WriteAllText($queryPyPath, $queryPy, [System.Text.Encoding]::ASCII)

function Get-Snapshot([string]$name) {
  $out = & $py $queryPyPath $db $name 2>$null
  $h = @{}
  foreach ($ln in $out) {
    $m = [regex]::Match($ln, '^(\w+)=(-?\d+)$')
    if ($m.Success) { $h[$m.Groups[1].Value] = [int]$m.Groups[2].Value }
  }
  return $h
}
function Has-SymId([int]$symid) {
  $out = & $py $queryPyPath $db '--has-symid' $symid 2>$null
  $m = [regex]::Match(($out -join "`n"), 'HAS_SYMID=(\d+)')
  return ($m.Success -and [int]$m.Groups[1].Value -gt 0)
}

Push-Location C:\TEMP
try {
  # --- index p2index.pas ALONE first (gives DoWork the LOWER ids) ---
  & $exePath index $target --db $db 2>$null | Out-Null
  Check 'index p2index.pas exits 0' ($LASTEXITCODE -eq 0)

  # --- then index anchor.pas SEPARATELY (gives AnchorFunc HIGHER ids; never reindexed again) ---
  & $exePath index $anchorTarget --db $db 2>$null | Out-Null
  Check 'index anchor.pas exits 0' ($LASTEXITCODE -eq 0)

  $before = Get-Snapshot 'DoWork'
  Check 'DoWork: symbol found pre-edit'              ($before.SYMID -ge 0)
  Check 'DoWork: symbol_facts row PRESENT'            ($before.PRESENT -eq 1)
  Check 'DB: exactly 2 routine-with-body symbols'     ($before.ROUTINE_COUNT -eq 2)
  Check 'DB: exactly 2 symbol_facts rows'             ($before.TOTAL -eq 2)
  Check 'DB: no orphan symbol_facts rows'             ($before.ORPHANS -eq 0)
  $oldId = $before.SYMID

  # --- edit p2index.pas: add a blank line right after `implementation`, ---
  # --- shifting DoWork's ImplStartLine/ImplEndLine down by one.         ---
  $src = Get-Content $target -Raw
  $src = $src -replace '(?m)^implementation\r?\n', "implementation`r`n`r`n"
  [System.IO.File]::WriteAllText($target, $src, [System.Text.Encoding]::ASCII)

  # --- reindex p2index.pas ONLY (anchor.pas untouched -> its rows stay live, ---
  # --- forcing a genuinely NEW id for DoWork, never a reused old one).      ---
  & $exePath index $target --db $db 2>$null | Out-Null
  Check 'reindex p2index.pas exits 0' ($LASTEXITCODE -eq 0)

  $after = Get-Snapshot 'DoWork'
  Check 'DoWork: symbol found post-edit'                        ($after.SYMID -ge 0)
  Check 'DoWork: NEW id differs from OLD id (real reindex, not a no-op)' ($after.SYMID -ne $oldId)
  Check 'DoWork: symbol_facts row PRESENT for the NEW id'        ($after.PRESENT -eq 1)
  Check 'DB: still exactly 2 routine-with-body symbols'         ($after.ROUTINE_COUNT -eq 2)
  Check 'DB: still exactly 2 symbol_facts rows (no orphan/dup)' ($after.TOTAL -eq 2)
  Check 'DB: no orphan symbol_facts rows post-reindex'          ($after.ORPHANS -eq 0)
  Check "OLD id's symbol_facts row is GONE (ON DELETE CASCADE fired)" (-not (Has-SymId $oldId))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
