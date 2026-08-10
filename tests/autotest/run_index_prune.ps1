<#
  run_index_prune.ps1 -- `index --prune` removes indexed files that no longer
  exist on disk, and removes NOTHING outside the folders it just walked.

  THE BUG (docs\INBOX-lint-scope-stale-files-and-project-members.md, bug 1)
  ------------------------------------------------------------------------
  The incremental walk adds new files and refreshes changed ones, but has no
  notion of a file that went away. After the user moved 10 retired units out of
  C:\Projects\DataCopy into Backup-20260805\ and re-indexed, the index still
  carried their rows -- and `lint-all` went on reporting roughly 249 of its 674
  findings against source files that DO NOT EXIST. Someone acting on those goes
  looking for a file that isn't there, and the counts used to judge "did the
  cleanup help?" are simply wrong.

  WHAT IS ASSERTED
  ----------------
  Pruning shipped OPT-IN first, and nothing ever passed the flag -- least of all
  the IDE reindex, which is the one path that reindexes constantly. Ghost rows
  went on outliving their files and every reference-derived answer
  (find-callers, unused-public-symbol, generated doc facts) was quietly computed
  against source that is not there. A flag nobody passes is not a fix, so a
  FOLDER walk now prunes BY DEFAULT and `--no-prune` is the opt-out.

  A single-FILE walk (`index <file.pas>`) still does not prune: the root is then
  the one file the caller named, so there is nothing to sweep.

  `--no-prune` opts out of OUT-OF-SCOPE EVICTION as well (see
  run_index_scope_eviction.ps1). "Not in scope" is a strictly wider predicate
  than "gone from disk" -- a vanished file is not in the walk's in-scope set
  either -- so an eviction that ignored the flag would delete the very rows the
  flag exists to protect, and group 1 below would go red for the right reason.

  THE SCOPE ASSERTION IS THE LOAD-BEARING ONE. A prune that walked one folder
  but purged rows for every other folder in a shared DB would be far worse than
  the bug it fixes, so the fixture deliberately indexes TWO folders into ONE db,
  deletes a file from EACH, then prunes with only the first folder in scope --
  and requires that the second folder's missing file survives untouched.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-index-prune by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-index-prune"
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

$main  = Join-Path $WorkDir 'main'
$other = Join-Path $WorkDir 'other'
New-Item -ItemType Directory $main  | Out-Null
New-Item -ItemType Directory $other | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# Each unit declares a distinctly-named routine so the dependent-row assertion
# can look for THAT symbol rather than counting rows.
function Write-Unit([string]$Dir, [string]$Name) {
  Write-Ascii (Join-Path $Dir "$Name.pas") @"
unit $Name;

interface

procedure Routine_$Name;

implementation

procedure Routine_$Name;
begin
end;

end.
"@
}

Write-Unit $main  'Keep1'
Write-Unit $main  'Keep2'
Write-Unit $main  'Gone'
Write-Unit $other 'OtherGone'

$db = Join-Path $WorkDir 'prune.sqlite'

# sqlite readers -- assert on the DB itself, not on a summary line the CLI prints.
$pyFiles = Join-Path $WorkDir 'files.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
rows = [r[0] for r in c.execute("SELECT path FROM files ORDER BY path")]
print(json.dumps(rows))
c.close()
'@ | Set-Content $pyFiles -Encoding ascii

$pySyms = Join-Path $WorkDir 'syms.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
rows = [r[0] for r in c.execute("SELECT name FROM symbols WHERE name LIKE 'Routine%' ORDER BY name")]
print(json.dumps(rows))
c.close()
'@ | Set-Content $pySyms -Encoding ascii

function Get-Files { @((& python $pyFiles $db) -join "`n" | ConvertFrom-Json) }
function Get-Syms  { @((& python $pySyms  $db) -join "`n" | ConvertFrom-Json) }
function HasLeaf([string[]]$Rows, [string]$Leaf) { return @($Rows | Where-Object { $_ -like "*\$Leaf" }).Count -ge 1 }

# ---------------------------------------------------------------------------
# BASELINE: both folders indexed into one DB.
# ---------------------------------------------------------------------------
Write-Host 'Baseline index (two folders, one DB)' -ForegroundColor Cyan
& $Exe index $main  --db $db --quiet 2>&1 | Out-Null
& $Exe index $other --db $db --quiet 2>&1 | Out-Null
$files0 = Get-Files
Check 'baseline indexed all 4 units' (
  (HasLeaf $files0 'Keep1.pas') -and (HasLeaf $files0 'Keep2.pas') -and
  (HasLeaf $files0 'Gone.pas')  -and (HasLeaf $files0 'OtherGone.pas')) "count=$($files0.Count)"
Check 'baseline has Gone.pas symbols' ((Get-Syms) -contains 'Routine_Gone')

# ---------------------------------------------------------------------------
# Delete one unit from EACH folder.
# ---------------------------------------------------------------------------
Remove-Item (Join-Path $main  'Gone.pas')
Remove-Item (Join-Path $other 'OtherGone.pas')

# ---------------------------------------------------------------------------
# 1) --no-prune is the explicit opt-out and must leave the vanished row.
#    Pruning shipped opt-in first and NOTHING ever passed the flag -- least of
#    all the IDE reindex -- so ghost rows kept outliving their files. A flag
#    nobody passes is not a fix, so a FOLDER walk now prunes by default and the
#    opt-out is what gets pinned here.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Re-index with --no-prune (explicit opt-out)' -ForegroundColor Cyan
& $Exe index $main --db $db --no-prune --quiet 2>&1 | Out-Null
$files1 = Get-Files
Check '--no-prune leaves the vanished file row alone' (HasLeaf $files1 'Gone.pas')

# ---------------------------------------------------------------------------
# 2) A plain folder walk prunes BY DEFAULT -- no flag passed. Still scoped to
#    $main only.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Re-index with NO flag (folder walk prunes by default), scoped to main\' -ForegroundColor Cyan
$out = & $Exe index $main --db $db --quiet 2>&1 | ForEach-Object { $_.ToString() }
$exit = $LASTEXITCODE
Check 'default-prune index exits 0' ($exit -eq 0) "exit=$exit"
Check 'it reports what it removed' (($out -join "`n") -match 'Gone\.pas')

$files2 = Get-Files
Check 'vanished file is GONE from the index'   (-not (HasLeaf $files2 'Gone.pas'))
Check 'surviving files are untouched'          ((HasLeaf $files2 'Keep1.pas') -and (HasLeaf $files2 'Keep2.pas'))

# The cascade: dropping the files row must take its symbols with it, or the
# rows are merely orphaned instead of removed.
$syms2 = Get-Syms
Check 'dependent symbols went with it'         ($syms2 -notcontains 'Routine_Gone')
Check 'surviving symbols are untouched'        (($syms2 -contains 'Routine_Keep1') -and ($syms2 -contains 'Routine_Keep2'))

# THE LOAD-BEARING ONE: other\ was not walked this run, so its missing file is
# none of this prune's business -- even though it is equally absent from disk.
Check 'a MISSING file OUTSIDE the walked root is NOT pruned' (HasLeaf $files2 'OtherGone.pas') `
  'indexing one folder must never purge the rest of a shared DB'

# ---------------------------------------------------------------------------
# 3) Idempotence: a second --prune with nothing to do changes nothing.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Second run (nothing left to remove)' -ForegroundColor Cyan
$out3 = & $Exe index $main --db $db --quiet 2>&1 | ForEach-Object { $_.ToString() }
Check 'second run reports nothing to remove' (($out3 -join "`n") -match 'no vanished files')
$files3 = Get-Files
Check 'second run changed nothing' ($files3.Count -eq $files2.Count) "$($files3.Count) vs $($files2.Count)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
