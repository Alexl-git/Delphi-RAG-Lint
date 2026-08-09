<#
  run_index_path_casing.ps1 -- one file on disk must be ONE row in `files`,
  whatever case the drive letter was spelled with on the command line.

  THE BUG (PLAN-autodoc-phaseC-2026-08-09, item B6; filed by YADF 2026-08-07)
  --------------------------------------------------------------------------------
  `files.path` carries a case-SENSITIVE UNIQUE, and the write path matched it
  byte-exactly:

      UPDATE files SET ... WHERE path = :path      <- FQUpsertFile
      SELECT id FROM files WHERE path = :path

  Windows paths are case-INSENSITIVE, and a differently-cased drive letter is
  trivially produced by a shell, a script, or an IDE plugin. So a second index
  run spelled `c:\...` did not UPDATE the `C:\...` row -- it INSERTED a second
  one. In the real YADF index that put 929 of 5,920 symbols (15.7%) on two rows
  for a single file, with STALE line numbers on one and fresh ones on the other,
  and no staleness signal anywhere: the DB looks freshly built because the
  *other* row is current. `context`, `query` and LSP goto then land on wrong
  lines.

  Note the asymmetry that hid it: the READ path (FQFindFileId) has always been
  case-tolerant (`path = :p OR LOWER(path) = LOWER(:p)`), so every query kept
  answering. Only the WRITE path was byte-exact.

  TWO ARMS, and both are needed.

  (1) PREVENTION -- indexing the same file under both casings yields one row,
      stored with an upper-case drive letter, and does not double the symbols.
      Asserted in BOTH orders: a fix that only upper-cased on write, while still
      matching byte-exactly, passes upper-then-lower and fails lower-then-upper.

  (2) MIGRATION -- double-indexed corpora ALREADY EXIST in the wild (YADF's is
      one), and no amount of write-path fixing repairs a DB that is already
      split. The duplicate is injected directly here, exactly as a pre-fix run
      left it, and the next WRITABLE open must merge it: the stale row goes, its
      dependent symbols go with it (FK cascade), and the survivor is the FRESHER
      vintage -- not merely whichever row was spelled canonically. The last case
      pins that ordering by making the NON-canonical row the fresher one.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-path-casing"
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir | Out-Null
Write-Ascii (Join-Path $srcDir 'CasingUnit.pas') @'
unit CasingUnit;

interface

procedure Routine_Casing;

implementation

procedure Routine_Casing;
begin
end;

end.
'@

# The two spellings of the SAME directory. Test-Path and GetFullPath treat them
# as one; `files.path` did not.
$upperRoot = $srcDir.Substring(0,1).ToUpper() + $srcDir.Substring(1)
$lowerRoot = $srcDir.Substring(0,1).ToLower() + $srcDir.Substring(1)
if ($upperRoot -ceq $lowerRoot) {
  Write-Host "FATAL: WorkDir has no drive letter to re-case: $srcDir" -ForegroundColor Red; exit 2
}

# --- sqlite readers: assert on the DB itself, never on a CLI summary line -----
# Flat, parallel lists rather than a list of rows: PowerShell unrolls a nested
# JSON array when it is piped, and a one-row result then yields the row's first
# CHARACTER instead of its first FIELD.
$pyDb = Join-Path $WorkDir 'db.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
rows = list(c.execute("SELECT path, id FROM files ORDER BY path"))
print(json.dumps({
  "paths":   [r[0] for r in rows],
  "ids":     [r[1] for r in rows],
  "symbols": c.execute("SELECT COUNT(*) FROM symbols WHERE name = 'Routine_Casing'").fetchone()[0],
  "orphans": c.execute("SELECT COUNT(*) FROM symbols s LEFT JOIN files f ON f.id = s.file_id "
                       "WHERE f.id IS NULL").fetchone()[0],
}))
c.close()
'@ | Set-Content $pyDb -Encoding ascii
function Get-Db([string]$Path) { (& python $pyDb $Path) -join "`n" | ConvertFrom-Json }
# The leading comma is load-bearing: PowerShell ENUMERATES a returned collection,
# so a one-row result would come back as a bare string and `[0]` would index its
# first CHARACTER rather than the first row.
function Paths($d) { ,@($d.paths) }
function Ids($d)   { ,@($d.ids)   }

# Injects the duplicate the pre-fix write path used to create: a second files row
# spelled with a lower-case drive, carrying a symbol of its own, and offset from
# the current row's parsed_at by $AgeDelta seconds (negative = the injected row is
# the STALE vintage, as YADF's id=161 was).
$pyInject = Join-Path $WorkDir 'inject.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
delta = int(sys.argv[2])
fid, path, parsed = c.execute("SELECT id, path, parsed_at FROM files LIMIT 1").fetchone()
other = path[0].lower() + path[1:]
c.execute("INSERT INTO files(path, mtime_unix, sha256, parsed_at, language) "
          "VALUES (?, 1, 'injectedsha', ?, 'pascal')", (other, parsed + delta))
sid = c.execute("SELECT id FROM files WHERE path = ?", (other,)).fetchone()[0]
c.execute("INSERT INTO symbols(file_id, kind, name, qualified_name, "
          "start_line, start_col, end_line, end_col) "
          "VALUES (?, 'procedure', 'Routine_Casing', 'CasingUnit.Routine_Casing', 1, 1, 1, 1)",
          (sid,))
c.commit()
print(json.dumps({"injected_file_id": sid, "injected_path": other}))
c.close()
'@ | Set-Content $pyInject -Encoding ascii

# ---------------------------------------------------------------------------
Write-Host 'Arm 1 -- prevention: two casings, one row' -ForegroundColor Cyan

$dbA = Join-Path $WorkDir 'upper_then_lower.sqlite'
& $Exe index $upperRoot --db $dbA --quiet 2>&1 | Out-Null
$a1 = Get-Db $dbA
Check 'first index writes exactly one files row' ((Paths $a1).Count -eq 1) "rows=$((Paths $a1).Count)"

& $Exe index $lowerRoot --db $dbA --quiet 2>&1 | Out-Null
$a2 = Get-Db $dbA
Check 're-indexing under the other drive casing does NOT add a row' ((Paths $a2).Count -eq 1) `
  "rows=$((Paths $a2).Count) -> $((Paths $a2) -join ' | ')"
Check 'the symbol was not duplicated' ($a2.symbols -eq 1) "Routine_Casing rows=$($a2.symbols)"
Check 'the stored path carries an UPPER-CASE drive letter' `
  ((Paths $a2)[0] -cmatch '^[A-Z]:\\') "path=$((Paths $a2)[0])"

# Reversed order. A fix that upper-cases on write but still matches byte-exactly
# passes the block above and fails here: the stored row is 'c:\...' and the
# incoming canonical 'C:\...' finds nothing to update.
$dbB = Join-Path $WorkDir 'lower_then_upper.sqlite'
& $Exe index $lowerRoot --db $dbB --quiet 2>&1 | Out-Null
& $Exe index $upperRoot --db $dbB --quiet 2>&1 | Out-Null
$b = Get-Db $dbB
Check 'lower-then-upper also yields one row' ((Paths $b).Count -eq 1) `
  "rows=$((Paths $b).Count) -> $((Paths $b) -join ' | ')"
Check 'lower-first still ends up canonically spelled' ((Paths $b)[0] -cmatch '^[A-Z]:\\') `
  "path=$((Paths $b)[0])"

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Arm 2 -- migration: an already-split DB is merged on next writable open' -ForegroundColor Cyan

$dbC = Join-Path $WorkDir 'split_stale.sqlite'
& $Exe index $upperRoot --db $dbC --quiet 2>&1 | Out-Null
$inj = (& python $pyInject $dbC -3600) -join "`n" | ConvertFrom-Json

$split = Get-Db $dbC
Check 'precondition: the DB is split across two rows' ((Paths $split).Count -eq 2) `
  "rows=$((Paths $split).Count)"
Check 'precondition: the injected row carries its own symbol' ($split.symbols -eq 2) `
  "Routine_Casing rows=$($split.symbols)"

& $Exe index $upperRoot --db $dbC --quiet 2>&1 | Out-Null
$merged = Get-Db $dbC
Check 'the split is repaired to one row' ((Paths $merged).Count -eq 1) `
  "rows=$((Paths $merged).Count) -> $((Paths $merged) -join ' | ')"
Check 'the survivor is canonically spelled' ((Paths $merged)[0] -cmatch '^[A-Z]:\\') `
  "path=$((Paths $merged)[0])"
Check 'the stale row''s dependent symbols went with it' ($merged.symbols -eq 1) `
  "Routine_Casing rows=$($merged.symbols)"
Check 'the STALE row is the one deleted' ((Ids $merged)[0] -ne $inj.injected_file_id) `
  "survivor id=$((Ids $merged)[0]), injected id=$($inj.injected_file_id)"
Check 'no orphaned symbol rows survive the merge' ($merged.orphans -eq 0) "orphans=$($merged.orphans)"

# Vintage, not spelling, decides the survivor: here the NON-canonical row is the
# fresher one, so IT must be the row that is kept (and then re-spelled). The
# assertion is on the row ID, not on any column value: the index run that
# triggers the merge goes on to notice the survivor's mtime/sha do not match the
# file on disk and re-parses it, which legitimately rewrites every other column.
$dbD = Join-Path $WorkDir 'split_newer.sqlite'
& $Exe index $upperRoot --db $dbD --quiet 2>&1 | Out-Null
$injD = (& python $pyInject $dbD 3600) -join "`n" | ConvertFrom-Json
Check 'precondition: the newer-duplicate DB is split' ((Paths (Get-Db $dbD)).Count -eq 2) ''
& $Exe index $upperRoot --db $dbD --quiet 2>&1 | Out-Null
$d = Get-Db $dbD
Check 'exactly one row survives the newer-duplicate case' ((Paths $d).Count -eq 1) `
  "rows=$((Paths $d).Count)"
Check 'the FRESHER row is the survivor, not the canonically-spelled one' `
  ((Ids $d)[0] -eq $injD.injected_file_id) `
  "survivor id=$((Ids $d)[0]), injected (fresher) id=$($injD.injected_file_id)"
Check 'and it is rewritten to the canonical spelling' ((Paths $d)[0] -cmatch '^[A-Z]:\\') `
  "path=$((Paths $d)[0])"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
