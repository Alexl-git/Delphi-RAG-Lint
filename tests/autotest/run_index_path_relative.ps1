<#
  run_index_path_relative.ps1 -- one file on disk must be ONE row in `files`,
  whether the index root was given as an ABSOLUTE or a RELATIVE path.

  THE BUG (found 2026-09-02 on this repo's own dclDragLintWizard.sqlite)
  --------------------------------------------------------------------------------
  This is the third spelling in the same family as run_index_path_casing.ps1
  (PHASE C B6: mixed separators, then drive-letter case). B6 collapsed every
  spelling to one canonical form at the store boundary -- but NormalizeStoredPath
  only folds separators and the drive letter. It never makes the path ABSOLUTE:

      Result := StringReplace(APath, '/', '\', [rfReplaceAll]);
      if drive letter is lower-case then upper-case it

  So `drag-lint index src\delphi-plugin --db <db>` walks a RELATIVE root, hands
  the store `src\delphi-plugin\Foo.pas`, and:

    * FileIsUpToDate finds no row under that spelling  -> "not up to date"
    * OpenFileTx's UPDATE matches nothing              -> INSERT, a SECOND row
    * CanonicalizeFilePaths keys on the canonical path -> the relative and the
      absolute spellings hash to DIFFERENT keys, so the B6 merge never sees them
      as one file and never repairs the split

  Measured on this repo: a single `index src/delphi-plugin --db ...` run took
  dclDragLintWizard.sqlite from 65 files rows to 119 -- 54 duplicates, one for
  every file under that root. Every symbol and ref under them is duplicated too.

  THE PART THAT MAKES IT WORSE THAN THE CASING BUG. The reader's freshness
  check goes on reading the STALE absolute rows, so it keeps printing

      note: 5 of 119 indexed file(s) changed ... refresh with:
            drag-lint index <dir> --db <db>

  and the remedy it prints is the very command that caused the split. Following
  the advice a second time adds nothing but re-confirms the warning, so the user
  is told to reindex forever while `index` reports "skipped N up-to-date".
  CLAUDE.md itself spells that remedy with a relative directory.

  TWO ARMS, both needed -- same structure as the casing test.

  (1) PREVENTION -- indexing the same tree under both spellings yields one row,
      stored ABSOLUTE. Asserted in BOTH orders: a fix that absolutises only on
      write, while still matching byte-exactly, passes absolute-then-relative
      and fails relative-then-absolute.

  (2) MIGRATION -- split DBs already exist in the wild (this repo's wizard index
      was one). The duplicate is injected exactly as a pre-fix run left it, and
      the next WRITABLE open must merge it, keeping the FRESHER vintage.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-path-relative"
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
$WorkDir = (Resolve-Path $WorkDir).Path

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# Runs the exe with an EXPLICIT working directory. `&` inherits PowerShell's
# location, which is exactly the variable under test here, so it is pinned
# rather than assumed -- a relative root only means anything against a cwd.
function Invoke-Exe([string]$Cwd, [string[]]$ExeArgs) {
  $o = Join-Path $WorkDir 'out.txt'
  $e = Join-Path $WorkDir 'err.txt'
  $p = Start-Process -FilePath $Exe -ArgumentList $ExeArgs -WorkingDirectory $Cwd `
                     -NoNewWindow -Wait -PassThru `
                     -RedirectStandardOutput $o -RedirectStandardError $e
  return $p.ExitCode
}

$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir | Out-Null
Write-Ascii (Join-Path $srcDir 'RelUnit.pas') @'
unit RelUnit;

interface

procedure Routine_Relative;

implementation

procedure Routine_Relative;
begin
end;

end.
'@

# --- sqlite reader: assert on the DB itself, never on a CLI summary line ------
# Flat parallel lists, for the reason run_index_path_casing.ps1 gives: PowerShell
# unrolls a nested JSON array, so a one-row result would yield the row's first
# CHARACTER instead of its first FIELD.
$pyDb = Join-Path $WorkDir 'db.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
rows = list(c.execute("SELECT path, id FROM files ORDER BY path"))
print(json.dumps({
  "paths":   [r[0] for r in rows],
  "ids":     [r[1] for r in rows],
  "symbols": c.execute("SELECT COUNT(*) FROM symbols WHERE name = 'Routine_Relative'").fetchone()[0],
  "orphans": c.execute("SELECT COUNT(*) FROM symbols s LEFT JOIN files f ON f.id = s.file_id "
                       "WHERE f.id IS NULL").fetchone()[0],
}))
c.close()
'@ | Set-Content $pyDb -Encoding ascii
function Get-Db([string]$Path) { (& python $pyDb $Path) -join "`n" | ConvertFrom-Json }
function Paths($d) { ,@($d.paths) }
function Ids($d)   { ,@($d.ids)   }

# Injects the duplicate a pre-fix relative run used to create: a second files row
# spelled RELATIVE to $WorkDir, carrying a symbol of its own, offset from the
# current row's parsed_at by $AgeDelta seconds (negative = injected row is stale).
$pyInject = Join-Path $WorkDir 'inject.py'
@'
import sqlite3, sys, json, os
c = sqlite3.connect(sys.argv[1])
delta = int(sys.argv[2])
base  = sys.argv[3]
fid, path, parsed = c.execute("SELECT id, path, parsed_at FROM files LIMIT 1").fetchone()
other = os.path.relpath(path, base)
c.execute("INSERT INTO files(path, mtime_unix, sha256, parsed_at, language) "
          "VALUES (?, 1, 'injectedsha', ?, 'pascal')", (other, parsed + delta))
sid = c.execute("SELECT id FROM files WHERE path = ?", (other,)).fetchone()[0]
c.execute("INSERT INTO symbols(file_id, kind, name, qualified_name, "
          "start_line, start_col, end_line, end_col) "
          "VALUES (?, 'procedure', 'Routine_Relative', 'RelUnit.Routine_Relative', 1, 1, 1, 1)",
          (sid,))
c.commit()
print(json.dumps({"injected_file_id": sid, "injected_path": other}))
c.close()
'@ | Set-Content $pyInject -Encoding ascii

# ---------------------------------------------------------------------------
Write-Host 'Arm 1 -- prevention: absolute and relative roots, one row' -ForegroundColor Cyan

$dbA = Join-Path $WorkDir 'abs_then_rel.sqlite'
Invoke-Exe $WorkDir @('index', $srcDir, '--db', $dbA, '--quiet') | Out-Null
$a1 = Get-Db $dbA
Check 'absolute index writes exactly one files row' ((Paths $a1).Count -eq 1) "rows=$((Paths $a1).Count)"

Invoke-Exe $WorkDir @('index', 'src', '--db', $dbA, '--quiet') | Out-Null
$a2 = Get-Db $dbA
Check 're-indexing under a RELATIVE root does NOT add a row' ((Paths $a2).Count -eq 1) `
  "rows=$((Paths $a2).Count) -> $((Paths $a2) -join ' | ')"
Check 'the symbol was not duplicated' ($a2.symbols -eq 1) "Routine_Relative rows=$($a2.symbols)"
Check 'the stored path is ABSOLUTE' ((Paths $a2)[0] -match '^[A-Za-z]:\\') "path=$((Paths $a2)[0])"

# Reversed order. A fix that absolutises on write but still matches byte-exactly
# passes the block above and fails here: the stored row is relative and the
# incoming canonical absolute path finds nothing to update.
$dbB = Join-Path $WorkDir 'rel_then_abs.sqlite'
Invoke-Exe $WorkDir @('index', 'src', '--db', $dbB, '--quiet') | Out-Null
Invoke-Exe $WorkDir @('index', $srcDir, '--db', $dbB, '--quiet') | Out-Null
$b = Get-Db $dbB
Check 'relative-then-absolute also yields one row' ((Paths $b).Count -eq 1) `
  "rows=$((Paths $b).Count) -> $((Paths $b) -join ' | ')"
Check 'relative-first still ends up stored ABSOLUTE' ((Paths $b)[0] -match '^[A-Za-z]:\\') `
  "path=$((Paths $b)[0])"

# The reader's freshness warning is the user-visible half of the defect, and it
# only bites once the file has actually been EDITED after the absolute index:
# the relative run then writes a fresh row of its own and leaves the absolute
# row stale, so `index` reports "skipped N up-to-date" while every reader goes on
# warning "N file(s) changed ... refresh with: drag-lint index <dir>" -- naming
# the command that caused the split. Without the edit both rows are current and
# this arm would pass vacuously whether the bug is present or not.
$dbF = Join-Path $WorkDir 'freshness.sqlite'
Invoke-Exe $WorkDir @('index', $srcDir, '--db', $dbF, '--quiet') | Out-Null
Write-Ascii (Join-Path $srcDir 'RelUnit.pas') @'
unit RelUnit;

interface

procedure Routine_Relative;
procedure Routine_AddedLater;

implementation

procedure Routine_Relative;
begin
end;

procedure Routine_AddedLater;
begin
end;

end.
'@
Invoke-Exe $WorkDir @('index', 'src', '--db', $dbF, '--quiet') | Out-Null
$qOut = Join-Path $WorkDir 'q.txt'
$qP = Start-Process -FilePath $Exe -ArgumentList @('query', '--name', 'Routine_Relative', '--db', $dbF) `
  -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru -RedirectStandardOutput $qOut `
  -RedirectStandardError (Join-Path $WorkDir 'q.err.txt')
$qTxt = (Get-Content $qOut -Raw) + (Get-Content (Join-Path $WorkDir 'q.err.txt') -Raw)
# Both controls exist so the assertion below cannot pass by SILENCE. A crashed or
# empty `query` produces no "changed since" line either, which would read as a
# clean index; these pin that the reader actually ran and actually answered.
Check 'control: the reader ran and exited 0' ($qP.ExitCode -eq 0) "exit=$($qP.ExitCode)"
Check 'control: the reader found the symbol' ($qTxt -match 'Routine_Relative') `
  ("len=" + $qTxt.Length)
Check 'a freshly-indexed tree reports NO stale files to the reader' `
  ($qTxt -notmatch 'indexed file\(s\) changed') `
  ("note=" + (($qTxt -split "`n" | Where-Object { $_ -match 'changed since' } | Select-Object -First 1)))

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Arm 2 -- migration: an already-split DB is merged on next writable open' -ForegroundColor Cyan

$dbC = Join-Path $WorkDir 'split_stale.sqlite'
Invoke-Exe $WorkDir @('index', $srcDir, '--db', $dbC, '--quiet') | Out-Null
$inj = (& python $pyInject $dbC -3600 $WorkDir) -join "`n" | ConvertFrom-Json

$split = Get-Db $dbC
Check 'precondition: the DB is split across two rows' ((Paths $split).Count -eq 2) `
  "rows=$((Paths $split).Count)"
Check 'precondition: the injected row carries its own symbol' ($split.symbols -eq 2) `
  "Routine_Relative rows=$($split.symbols)"

Invoke-Exe $WorkDir @('index', $srcDir, '--db', $dbC, '--quiet') | Out-Null
$merged = Get-Db $dbC
Check 'the split is repaired to one row' ((Paths $merged).Count -eq 1) `
  "rows=$((Paths $merged).Count) -> $((Paths $merged) -join ' | ')"
Check 'the survivor is stored ABSOLUTE' ((Paths $merged)[0] -match '^[A-Za-z]:\\') `
  "path=$((Paths $merged)[0])"
Check 'the stale row''s dependent symbols went with it' ($merged.symbols -eq 1) `
  "Routine_Relative rows=$($merged.symbols)"
Check 'the STALE row is the one deleted' ((Ids $merged)[0] -ne $inj.injected_file_id) `
  "survivor id=$((Ids $merged)[0]), injected id=$($inj.injected_file_id)"
Check 'no orphaned symbol rows survive the merge' ($merged.orphans -eq 0) "orphans=$($merged.orphans)"

# Vintage, not spelling, decides the survivor: here the RELATIVE row is the
# fresher one, so IT must be kept (and then re-spelled absolute).
$dbD = Join-Path $WorkDir 'split_newer.sqlite'
Invoke-Exe $WorkDir @('index', $srcDir, '--db', $dbD, '--quiet') | Out-Null
$injD = (& python $pyInject $dbD 3600 $WorkDir) -join "`n" | ConvertFrom-Json
Check 'precondition: the newer-duplicate DB is split' ((Paths (Get-Db $dbD)).Count -eq 2) ''
Invoke-Exe $WorkDir @('index', $srcDir, '--db', $dbD, '--quiet') | Out-Null
$d = Get-Db $dbD
Check 'exactly one row survives the newer-duplicate case' ((Paths $d).Count -eq 1) `
  "rows=$((Paths $d).Count)"
Check 'the FRESHER row is the survivor, not the absolutely-spelled one' `
  ((Ids $d)[0] -eq $injD.injected_file_id) `
  "survivor id=$((Ids $d)[0]), injected (fresher) id=$($injD.injected_file_id)"
Check 'and it is rewritten to the absolute spelling' ((Paths $d)[0] -match '^[A-Za-z]:\\') `
  "path=$((Paths $d)[0])"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
