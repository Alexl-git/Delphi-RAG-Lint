<#
  run_sql_quoted_identifiers.ps1 -- D19: the SQL-script extractor dropped
  QUOTED column identifiers.

  THE DEFECT. DRagLint.Parser.Sql.ParseColumnList took a column's name as the
  leading run of [A-Za-z0-9_$]. A quoted identifier starts with '"', so the run
  was empty and the column was silently skipped. Quoted identifiers are exactly
  the reserved-word columns Firebird REQUIRES to be quoted, so the gap was
  systematic: C:\Projects\DB\SQL\MS1.SQL:2243 "ACTION" (IPCHART) and :3848
  "TABLE" (FOLDERCOUNT) had no sql_column row. CREATE TABLE "Name" was not
  recognised at all (the table regex accepted bare identifiers only).

  THE FIX, AND HOW A QUOTED NAME IS STORED. Firebird semantics: a quoted
  identifier is case-SENSITIVE and is stored in the metadata WITHOUT its
  quotes, exactly as written, with an embedded doubled quote ("") meaning one
  '"'. The extractor now stores symbols.name that way -- "ACTION" -> ACTION,
  "Mixed Case" -> Mixed Case, "Say""Hi" -> Say"Hi -- and qualified_name as
  <table>.<column> built from the stored forms. (An UNQUOTED name is stored as
  written in the script, not upper-cased; that is unchanged.)

  WHOLE-WORD SKIP (found while fixing D19, same routine): the table-level
  constraint skip was a bare PREFIX test, so real columns UNIQUE_FLAG and
  CONSTRAINT_NAME (MS1.SQL:3880, :1796, MScript2.SQL:1599, :1631) were dropped.
  It now matches CONSTRAINT/UNIQUE/CHECK/PRIMARY KEY/FOREIGN KEY as whole words.

  CONTROLS. ID / NAME (unquoted columns) and table IPCHART must PASS on the
  pre-fix engine: they prove the harness and the unquoted path.

  Run from a NEUTRAL CWD. pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}

$exePath = (Resolve-Path $Exe).Path
$work = Join-Path $env:TEMP ('draglint_sqlquoted_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
$db = Join-Path $work 'sqlquoted.sqlite'

$script = @'
/* D19 fixture -- quoted identifiers, Firebird dialect 3 */
CREATE TABLE IPCHART (
    ID               INTEGER NOT NULL,
    "ACTION"         D_INTEGER ,
    "Mixed Case"     VARCHAR(10),
    "Say""Hi"        INTEGER,
    NAME             VARCHAR(20),
    UNIQUE_FLAG      D_BOOLEAN,
    CONSTRAINT_NAME  D_FBNAME NOT NULL,
    CHECKED          INTEGER,
    CONSTRAINT PK_IPCHART PRIMARY KEY (ID),
    UNIQUE (NAME),
    CHECK (ID > 0)
);

CREATE TABLE "Quoted_Tab" (
    "TABLE"  D_STRTAG15 NOT NULL ,
    RECORDS  INTEGER
);
'@
$norm = $script -replace "`r`n", "`n" -replace "`n", "`r`n"
[IO.File]::WriteAllText((Join-Path $work 'MS_QUOTED.sql'), $norm, [Text.Encoding]::ASCII)

Push-Location $env:TEMP
try {
  & $exePath index $work --db $db 2>&1 | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

  $q = "select c.qualified_name, coalesce(c.signature,'') from symbols c join symbols t on t.id = c.parent_id where c.kind = 'sql_column' and t.kind = 'sql_table'"
  $j = (& $exePath sql --db $db --query $q --json 2>$null) -join "`n" | ConvertFrom-Json
  $cols = @{}
  foreach ($row in $j.rows) { $cols[[string]$row[0]] = [string]$row[1] }
  $tj = (& $exePath sql --db $db --query "select name from symbols where kind = 'sql_table'" --json 2>$null) -join "`n" | ConvertFrom-Json
  $tables = @($tj.rows | ForEach-Object { [string]$_[0] })

  function HasCol($qn, $sig) {
    # ContainsKey is case-insensitive on a PowerShell hashtable; the stored case is checked separately.
    $hit = @($cols.Keys | Where-Object { $_ -ceq $qn })
    Check "column $qn present (case exact)" ($hit.Count -eq 1) ("have: " + (($cols.Keys | Sort-Object) -join ', '))
    if ($hit.Count -eq 1) { Check "column $qn signature = '$sig'" ($cols[$hit[0]] -eq $sig) "actual='$($cols[$hit[0]])'" }
  }

  Write-Host 'CONTROLS (pass on the pre-fix engine):' -ForegroundColor Cyan
  Check 'table IPCHART present' ($tables -ccontains 'IPCHART') ("tables: " + ($tables -join ', '))
  HasCol 'IPCHART.ID'   'INTEGER NOT NULL'
  HasCol 'IPCHART.NAME' 'VARCHAR(20)'

  Write-Host 'D19 -- quoted identifiers kept, quotes stripped, case preserved:' -ForegroundColor Cyan
  HasCol 'IPCHART.ACTION'     'D_INTEGER'
  HasCol 'IPCHART.Mixed Case' 'VARCHAR(10)'
  HasCol 'IPCHART.Say"Hi'     'INTEGER'
  Check 'quoted table Quoted_Tab present, quotes stripped' ($tables -ccontains 'Quoted_Tab') ("tables: " + ($tables -join ', '))
  HasCol 'Quoted_Tab.TABLE'   'D_STRTAG15 NOT NULL'
  HasCol 'Quoted_Tab.RECORDS' 'INTEGER'
  Write-Host 'WHOLE-WORD constraint skip (same function, found while fixing D19):' -ForegroundColor Cyan
  HasCol 'IPCHART.UNIQUE_FLAG'     'D_BOOLEAN'
  HasCol 'IPCHART.CONSTRAINT_NAME' 'D_FBNAME NOT NULL'
  HasCol 'IPCHART.CHECKED'         'INTEGER'
  Check 'table-level CONSTRAINT/UNIQUE/CHECK clauses still emit no column' (@($cols.Keys | Where-Object { $_ -match '^IPCHART\.(CONSTRAINT|UNIQUE|CHECK|PK_)' -and $_ -notmatch '_FLAG|_NAME|CHECKED' }).Count -eq 0) ("have: " + (($cols.Keys | Sort-Object) -join ', '))
  Check 'no stored name keeps its quotes' (@($cols.Keys | Where-Object { $_ -match '^"|\."' }).Count -eq 0) ("have: " + (($cols.Keys | Sort-Object) -join ', '))
} finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
