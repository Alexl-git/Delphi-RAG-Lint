<#
  run_index_honours_gitignore.ps1 -- `index` honours .gitignore / .hgignore by
  DEFAULT, and --no-use-ignore turns that off.

  THE BUG (PLAN-autodoc-phaseC-2026-08-09, item B5; filed by YADF 2026-08-07)
  --------------------------------------------------------------------------------
  Five archived files under YADF's `.private\` were in the index -- including a
  whole pre-fork snapshot of YADF.Layout.pas that shares 30 routine names with
  the live unit. Since attribution renders a BASENAME, a reader could not tell
  which of the two a row meant, and every name-based bucket (callers, Used by,
  Covered by) drew on both.

  The review filed this as a missing feature ("an ignore-globs setting honoured
  by index"). It was not: a full .gitignore/.hgignore engine already existed, and
  `.private/` had been in YADF's .gitignore all along. The defect was a DEFAULT.
  Honouring ignore files was opt-in behind --use-ignore on the ad-hoc `index`
  path, while a manifest SECTION defaulted UseIgnoreFiles to True -- so the same
  product answered the same question two ways, and the path a human types was
  the one that ignored the repo's own rules.

  A repo's ignore file states which files are part of the repo, so honouring it
  is the conservative default. The opt-out exists for a tree whose ignore rules
  exclude sources that are nonetheless wanted in the index, and is asserted here
  so the escape hatch cannot rot.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-gitignore"
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
New-Item -ItemType Directory (Join-Path $WorkDir '.private') | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function Write-Unit([string]$Path, [string]$Name, [string]$Routine) {
  Write-Ascii $Path @"
unit $Name;

interface

function ${Routine}: Integer;

implementation

function ${Routine}: Integer;
begin
  Result := 1;
end;

end.
"@
}

# The archive shares its ROUTINE NAME with the live unit -- the exact shape that
# made YADF's caller lists ambiguous, since attribution renders a basename.
Write-Ascii (Join-Path $WorkDir '.gitignore') @'
.private/
*.bak.pas
'@
Write-Unit (Join-Path $WorkDir 'Live.pas')             'Live'    'SharedRoutine'
Write-Unit (Join-Path $WorkDir '.private\Live.pas')    'Live'    'SharedRoutine'
Write-Unit (Join-Path $WorkDir 'Old.bak.pas')          'OldBak'  'ArchivedOnly'

$py = Join-Path $WorkDir 'q.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
print(json.dumps({
  "paths":  [r[0] for r in c.execute("SELECT path FROM files ORDER BY path")],
  "shared": c.execute("SELECT COUNT(*) FROM symbols WHERE name='SharedRoutine'").fetchone()[0],
  "archived": c.execute("SELECT COUNT(*) FROM symbols WHERE name='ArchivedOnly'").fetchone()[0],
}))
c.close()
'@ | Set-Content $py -Encoding ascii
function Q([string]$Db) { (& python $py $Db) -join "`n" | ConvertFrom-Json }

Write-Host 'Default: .gitignore is honoured' -ForegroundColor Cyan
$db1 = Join-Path $WorkDir 'default.sqlite'
& $Exe index $WorkDir --db $db1 --quiet 2>&1 | Out-Null
$a = Q $db1
Check 'the live unit IS indexed' (@($a.paths | Where-Object { $_ -notmatch '\.private' -and $_ -match 'Live\.pas$' }).Count -eq 1) `
  ($a.paths -join ' | ')
Check 'the .private archive is NOT indexed' (@($a.paths | Where-Object { $_ -match '\.private' }).Count -eq 0) `
  ($a.paths -join ' | ')
Check 'a *.bak.pas glob rule is honoured too' (@($a.paths | Where-Object { $_ -match 'bak\.pas$' }).Count -eq 0)
Check 'the shared routine name resolves to ONE symbol, not two' ($a.shared -eq 1) `
  "SharedRoutine symbols=$($a.shared) -- two means a name-based bucket cannot tell the copies apart"
Check 'a routine that exists ONLY in the archive is absent entirely' ($a.archived -eq 0) `
  "ArchivedOnly symbols=$($a.archived) -- this is the phantom-caller shape B5 describes"

Write-Host ''
Write-Host 'Opt-out: --no-use-ignore restores the old behaviour' -ForegroundColor Cyan
$db2 = Join-Path $WorkDir 'optout.sqlite'
& $Exe index $WorkDir --db $db2 --no-use-ignore --quiet 2>&1 | Out-Null
$b = Q $db2
Check 'the .private archive IS indexed when opted out' (@($b.paths | Where-Object { $_ -match '\.private' }).Count -eq 1) `
  ($b.paths -join ' | ')
Check 'and the name collision is back (proving the default is what removed it)' ($b.shared -eq 2) `
  "SharedRoutine symbols=$($b.shared)"

Write-Host ''
Write-Host '--use-ignore still parses (existing scripts must not break)' -ForegroundColor Cyan
$db3 = Join-Path $WorkDir 'explicit.sqlite'
$out = & $Exe index $WorkDir --db $db3 --use-ignore --quiet 2>&1 | Out-String
$c = Q $db3
Check 'the flag is accepted and means the same as the default' `
  ((@($c.paths | Where-Object { $_ -match '\.private' }).Count -eq 0) -and ($out -notmatch 'nknown')) $out

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
