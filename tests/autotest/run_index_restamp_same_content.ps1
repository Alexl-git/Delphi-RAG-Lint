<#
  run_index_restamp_same_content.ps1 -- issue drag-lint#1 (2026-10-06).

  THE PROBLEM. A working-copy operation rewrote the dates of 1,138 ProjectA
  units without changing a byte. The up-to-date test needs mtime AND sha256 to
  match, so the next incremental runs re-parsed every one of them -- 31 minutes
  for ~600 files -- and each re-parse paid the FTS5 sync triggers per literal,
  twice over, because deleting a file's symbols first UPDATEd its literals
  (string_literals.symbol_id ON DELETE SET NULL) before they were deleted.

  WHAT THIS PINS.
    R1  a moved date over identical bytes is RE-STAMPED, not re-parsed, and the
        Done line says so; the stored mtime follows the disk.
    R2  the next run is a plain up-to-date skip (nothing left to re-stamp).
    R3  a real content change is still parsed (the sha is the content test).
    R4  --force-reparse still re-parses a file whose date moved: a forced run
        never takes the re-stamp shortcut.
    R5  an incremental run over MORE files than the live-trigger budget (16)
        defers the FTS5 triggers and rebuilds once: afterwards the text index
        answers for the NEW literals, not the old ones, the three sync triggers
        are back, and no rebuild is left pending.

  Usage: pwsh -File tests/autotest/run_index_restamp_same_content.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-index-restamp-$PID"
)
try {
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
function Write-Unit([string]$Dir, [string]$Name, [string]$Literal) {
  Write-Ascii (Join-Path $Dir "$Name.pas") @"
unit $Name;

interface

type
  T$Name = class(TObject)
  public
    function Run: string;
  end;

implementation

function T$Name.Run: string;
begin
  Result := '$Literal';
end;

end.
"@
}
function Index([string[]]$Extra) {
  $o = (@(& $Exe index $src --db $db --quiet @Extra 2>&1) | ForEach-Object { "$_" }) -join "`n"
  return @{ Out = $o; Code = $LASTEXITCODE }
}

$py = Join-Path $WorkDir 'sql.py'
Write-Ascii $py @'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
rows = con.execute(sys.argv[2]).fetchall()
if rows:
    print("\n".join("|".join("" if v is None else str(v) for v in r) for r in rows))
con.close()
'@
function Sql([string]$Q) { return ((python $py $db $Q) -join "`n").Trim() }
function MtimeUnix([string]$Path) {
  return [DateTimeOffset]::new((Get-Item $Path).LastWriteTimeUtc).ToUnixTimeSeconds()
}

$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null
$names = 1..20 | ForEach-Object { 'Unit{0:D2}' -f $_ }
foreach ($n in $names) { Write-Unit $src $n "old literal $n" }
$db = Join-Path $WorkDir 'restamp.sqlite'
$alpha = Join-Path $src 'Unit01.pas'

Write-Host 'step 0 -- full index' -ForegroundColor Cyan
$r0 = Index @()
Check 'step 0 exits 0' ($r0.Code -eq 0) $r0.Out
$syms0 = Sql 'SELECT COUNT(*) FROM symbols'

# --- R1: date moves, bytes do not. ---------------------------------------------
Write-Host ''
Write-Host 'R1 -- move one file''s date, keep its bytes' -ForegroundColor Cyan
(Get-Item $alpha).LastWriteTime = (Get-Item $alpha).LastWriteTime.AddHours(-30)
$r1 = Index @()
Check 'R1 exits 0' ($r1.Code -eq 0) $r1.Out
Check 'R1 nothing parsed' ($r1.Out -match 'parsed 0,') $r1.Out
Check 'R1 one file re-stamped' ($r1.Out -match '\(1 of them re-stamped') $r1.Out
Check 'R1 the ordinary counter still covers it (skipped 20 up-to-date)' ($r1.Out -match 'skipped 20 up-to-date') $r1.Out
$stored = Sql "SELECT mtime_unix FROM files WHERE path LIKE '%Unit01.pas'"
Check 'R1 the stored mtime follows the disk' ($stored -eq "$(MtimeUnix $alpha)") "stored=$stored disk=$(MtimeUnix $alpha)"
Check 'R1 the rows are untouched' ((Sql 'SELECT COUNT(*) FROM symbols') -eq $syms0) "symbols before=$syms0"

# --- R2: nothing left to do. -------------------------------------------------------
Write-Host ''
Write-Host 'R2 -- run again' -ForegroundColor Cyan
$r2 = Index @()
Check 'R2 exits 0' ($r2.Code -eq 0) $r2.Out
Check 'R2 plain up-to-date skip, no re-stamp' (($r2.Out -match 'skipped 20 up-to-date') -and ($r2.Out -notmatch 're-stamped')) $r2.Out

# --- R3: a real change is parsed. --------------------------------------------------
Write-Host ''
Write-Host 'R3 -- change one file''s bytes' -ForegroundColor Cyan
Write-Unit $src 'Unit01' 'changed literal Unit01'
$r3 = Index @()
Check 'R3 exits 0' ($r3.Code -eq 0) $r3.Out
Check 'R3 the changed file is parsed' (($r3.Out -match 'parsed 1,') -and ($r3.Out -notmatch 're-stamped')) $r3.Out

# --- R4: a forced run never re-stamps. ---------------------------------------------
Write-Host ''
Write-Host 'R4 -- move a date, then --force-reparse' -ForegroundColor Cyan
(Get-Item $alpha).LastWriteTime = (Get-Item $alpha).LastWriteTime.AddHours(-30)
$r4 = Index @('--force-reparse')
Check 'R4 exits 0' ($r4.Code -eq 0) $r4.Out
Check 'R4 every file re-parsed, none re-stamped' (($r4.Out -notmatch 're-stamped') -and ($r4.Out -notmatch 'skipped [1-9]')) $r4.Out

# --- R5: past the live budget the text index is deferred and rebuilt. ---------------
Write-Host ''
Write-Host 'R5 -- change all 20 files (over the 16-file live budget)' -ForegroundColor Cyan
foreach ($n in $names) { Write-Unit $src $n "fresh literal $n" }
$r5 = Index @()
Check 'R5 exits 0' ($r5.Code -eq 0) $r5.Out
Check 'R5 all 20 parsed (none skipped)' (($r5.Out -match 'Done\. Files: 20,') -and ($r5.Out -notmatch 'skipped [1-9]')) $r5.Out
$newHits = Sql "SELECT COUNT(*) FROM string_fts WHERE string_fts MATCH '""fresh literal""'"
$oldHits = Sql "SELECT COUNT(*) FROM string_fts WHERE string_fts MATCH '""old literal""'"
$triHits = Sql "SELECT COUNT(*) FROM string_fts_tri WHERE string_fts_tri MATCH '""esh lit""'"
Check 'R5 the word index finds the 20 new literals' ($newHits -eq '20') "hits=$newHits"
Check 'R5 the word index no longer finds the old ones' ($oldHits -eq '0') "hits=$oldHits"
Check 'R5 the trigram index finds the 20 new literals' ($triHits -eq '20') "hits=$triHits"
$trig = Sql "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND name LIKE 'string_literals%'"
Check 'R5 the three sync triggers are restored' ($trig -eq '3') "triggers=$trig"
$pending = Sql "SELECT COUNT(*) FROM schema_meta WHERE key='fts_rebuild_pending'"
Check 'R5 no rebuild left pending' ($pending -eq '0') "pending=$pending"

# --- R5 control: a small incremental run keeps the triggers live and stays correct. --
Write-Host ''
Write-Host 'R5 control -- change 2 files (inside the live budget)' -ForegroundColor Cyan
Write-Unit $src 'Unit01' 'small literal Unit01'
Write-Unit $src 'Unit02' 'small literal Unit02'
$r6 = Index @()
Check 'R6 exits 0' ($r6.Code -eq 0) $r6.Out
$small = Sql "SELECT COUNT(*) FROM string_fts WHERE string_fts MATCH '""small literal""'"
$fresh = Sql "SELECT COUNT(*) FROM string_fts WHERE string_fts MATCH '""fresh literal""'"
Check 'R6 the live triggers indexed the 2 new literals' ($small -eq '2') "hits=$small"
Check 'R6 and dropped the 2 replaced ones' ($fresh -eq '18') "hits=$fresh"

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
}
finally {
  if ($WorkDir -and (Test-Path $WorkDir)) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
}
