<#
  run_repo_cli_alter.ps1 -- TT-ALTER (1.54): `repo alter-table` driven on the built engine. The live cases use a
  SCRATCH Firebird database created here through a private embedded engine (lib\FirebirdEmbed.ps1): the engine is copied
  beside that private fbclient.dll, so it cannot reach a server.

  CASES
    A1  no --table / no --direction / wrong direction / no --connection / no repository -> exit 1, the reason on stderr
    A2  a failed connect exits 1 and never echoes the password (A2c control: the same text shows when it is no secret)
    L0  the scratch database and its repository (seed-fb --ddl, then refresh-schema --ddl) exist
    L1  an unchanged table = 0 changes, exit 0
    L2  dry run (no --apply): change set + DDL + blocked reasons, exit 0, the database unchanged
    L2b --dry-run wins over --apply; L2c --select without --apply writes nothing
    L3  --json: one object, direction, ddl, blocked; no password in it
    L4  --apply: the checked change is applied, exit 0; a second dry run no longer lists it
    L5  --apply --select with a blocked id -> exit 1, nothing written
    L6  --safe-path: unchecked; --apply --select applies it and the data survive; --order moves a column
    L7  --hook micronite adds its notes; an unknown hook -> exit 1
    L8  OpenMode / DropDatabase in --connection -> exit 1, the database is still there
  Run: pwsh -File tests\autotest\run_repo_cli_alter.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '')
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
. (Join-Path $PSScriptRoot 'lib\FirebirdEmbed.ps1')
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $(if ($ok) { '' } else { $d })) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
Write-Host '== repo alter-table ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-repo-alter-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$saved = $env:FIREBIRD
$script:Bin = $Exe
function Run([string[]]$a) {
  $o = & $script:Bin @a 2>&1
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
function JsonOf($r) {
  $line = @($r.Out -split "`n" | Where-Object { $_.StartsWith('{') })
  if ($line.Count -eq 0) { return $null }
  return ($line[-1] | ConvertFrom-Json)
}
try {
  $repo = Join-Path $work 'x.dlrepo'
  $null = Run @('repo', 'init', '--repo', $repo)
  $cs = 'Database=localhost:C:\no\such\x.fdb;User_Name=SYSDBA;Password=pw'
  $r = Run @('repo', 'alter-table', '--repo', $repo, '--direction', 'repo-to-db', '--connection', $cs)
  Check 'A1a no --table -> exit 1' (($r.Code -eq 1) -and ($r.Out -match 'exactly one table')) $r.Out
  $r = Run @('repo', 'alter-table', '--repo', $repo, '--table', 'T', '--connection', $cs)
  Check 'A1b no --direction -> exit 1' (($r.Code -eq 1) -and ($r.Out -match 'repo-to-db')) $r.Out
  $r = Run @('repo', 'alter-table', '--repo', $repo, '--table', 'T', '--direction', 'db-to-repo', '--connection', $cs)
  Check 'A1c another direction -> exit 1' (($r.Code -eq 1) -and ($r.Out -match 'repo-to-db')) $r.Out
  $r = Run @('repo', 'alter-table', '--repo', $repo, '--table', 'T', '--direction', 'repo-to-db')
  Check 'A1d no --connection -> exit 1' (($r.Code -eq 1) -and ($r.Out -match 'give --connection')) $r.Out
  $r = Run @('repo', 'alter-table', '--repo', (Join-Path $work 'none.dlrepo'), '--table', 'T', '--direction', 'repo-to-db', '--connection', $cs)
  Check 'A1e no repository -> exit 1' (($r.Code -eq 1) -and ($r.Out -match 'does not exist')) $r.Out
  $embed = New-FirebirdEmbed (Join-Path $work 'fb')
  if (-not $embed) { Write-Host 'SKIP L no Firebird 4 on this machine'; if ($script:Failed) { exit 1 } else { exit 0 } }
  $env:FIREBIRD = $embed
  # the engine beside the private client, with its own DLLs
  Get-ChildItem -LiteralPath (Split-Path $Exe) -File | Where-Object { $_.Extension -eq '.dll' -or $_.Name -eq 'drag-lint.exe' } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $embed }
  $script:Bin = Join-Path $embed 'drag-lint.exe'
  $fdb = Join-Path $work 'scratch.fdb'
  $sql = Join-Path $work 'create.sql'
  [IO.File]::WriteAllText($sql, @"
CREATE DATABASE '$fdb' USER 'SYSDBA' PAGE_SIZE 8192 DEFAULT CHARACTER SET UTF8;
CREATE TABLE T (ID INTEGER NOT NULL PRIMARY KEY, A VARCHAR(10), N VARCHAR(10), U VARCHAR(10), X INTEGER);
CREATE VIEW V AS SELECT U FROM T;
COMMIT;
INSERT INTO T VALUES (1, 'abc', '007', 'u', 1);
INSERT INTO T VALUES (2, 'def', '12', 'u', 2);
COMMIT;
"@)
  $null = & "$embed\isql.exe" -q -i $sql 2>&1
  $pw = 'Zq7s3cr3tPw'
  $cs = "Database=$fdb;User_Name=SYSDBA;Password=$pw"
  function Q([string]$q) {
    $f = Join-Path $work 'q.sql'
    [IO.File]::WriteAllText($f, "SET HEADING OFF;`r`n$q;`r`n")
    ((& "$embed\isql.exe" -q -i $f -user SYSDBA $fdb 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join ',')
  }
  function Shape { Q "SELECT TRIM(RF.RDB`$FIELD_NAME) || ':' || L.RDB`$FIELD_TYPE || ':' || COALESCE(L.RDB`$CHARACTER_LENGTH, 0) FROM RDB`$RELATION_FIELDS RF JOIN RDB`$FIELDS L ON L.RDB`$FIELD_NAME = RF.RDB`$FIELD_SOURCE WHERE RF.RDB`$RELATION_NAME = 'T' ORDER BY RF.RDB`$FIELD_POSITION" }
  function Alter([string[]]$more) { Run (@('repo', 'alter-table', '--repo', $repo, '--table', 'T', '--direction', 'repo-to-db', '--connection', $cs) + $more) }
  $same = Join-Path $work 'same.sql'
  [IO.File]::WriteAllText($same, "CREATE TABLE T (ID INTEGER NOT NULL, A VARCHAR(10), N VARCHAR(10), U VARCHAR(10), X INTEGER, CONSTRAINT PK_T PRIMARY KEY (ID));`r`n")
  $r = Run @('repo', 'seed-fb', '--ddl', $same, '--repo', $repo, '--apply')
  $shape0 = Shape
  Check 'L0 scratch database and repository' (($r.Code -eq 0) -and ($shape0 -eq 'ID:8:0,A:37:10,N:37:10,U:37:10,X:8:0')) "$shape0`n$($r.Out)"
  $r = Alter @()
  Check 'L1 an unchanged table = 0 changes, exit 0' (($r.Code -eq 0) -and ($r.Out -match 'direction repo-to-db, 0 changes')) $r.Out
  # A2: FireDAC echoes the driver id, so this text carries the password unless it is masked
  $r = Run @('repo', 'alter-table', '--repo', $repo, '--table', 'T', '--direction', 'repo-to-db', '--connection', "Database=$fdb;User_Name=SYSDBA;DriverID=$pw;Password=$pw")
  Check 'A2 an error text holding the password is masked' (($r.Code -eq 1) -and ($r.Out -match '\*\*\*') -and ($r.Out -notmatch $pw)) $r.Out
  $r = Run @('repo', 'alter-table', '--repo', $repo, '--table', 'T', '--direction', 'repo-to-db', '--connection', "Database=$fdb;User_Name=SYSDBA;DriverID=$pw;Password=other")
  Check 'A2c positive control: the same text shows when it is not the password' ($r.Out -match $pw) $r.Out
  # the repository now wants A wider, N numeric, U wider (a view uses it)
  $ddl = Join-Path $work 'want.sql'
  [IO.File]::WriteAllText($ddl, "CREATE TABLE T (ID INTEGER NOT NULL, A VARCHAR(20), N INTEGER, U VARCHAR(30), X INTEGER, CONSTRAINT PK_T PRIMARY KEY (ID));`r`n")
  $r = Run @('repo', 'refresh-schema', '--ddl', $ddl, '--repo', $repo, '--apply')
  Check 'L0b the repository wants something else' ($r.Code -eq 0) $r.Out
  $r = Alter @()
  Check 'L2 dry run: DDL, two blocked reasons, exit 0, the database unchanged' (($r.Code -eq 0) -and ($r.Out -match 'ALTER TABLE "T" ALTER COLUMN "A" TYPE VARCHAR\(20\)') -and
    ($r.Out -match 'BLOCKED: refused-conversion') -and ($r.Out -match 'BLOCKED: dependency: view V') -and ($r.Out -match 'dry run: nothing written') -and ((Shape) -eq $shape0)) "$(Shape)`n$($r.Out)"
  $r = Alter @('--apply', '--dry-run')
  Check 'L2b --dry-run wins over --apply' (($r.Code -eq 0) -and ($r.Out -match 'dry run: nothing written') -and ((Shape) -eq $shape0)) $r.Out
  $all = Join-Path $work 'all.txt'
  [IO.File]::WriteAllText($all, "all`r`n")
  $r = Alter @('--select', $all)
  Check 'L2c --select without --apply writes nothing' (($r.Code -eq 0) -and ($r.Out -match 'dry run: nothing written') -and ((Shape) -eq $shape0)) $r.Out
  $r = Alter @('--json')
  $j = JsonOf $r
  $a = @($j.changes | Where-Object { $_.target -eq 'T.A' })
  Check 'L3 --json: one object with direction, ddl, blocked; no password' (($r.Code -eq 0) -and ($j.direction -eq 'repo-to-db') -and ($j.dry_run -eq $true) -and ($j.blocked -eq 2) -and ($a.Count -eq 1) -and
    ($a[0].ddl[0] -eq 'ALTER TABLE "T" ALTER COLUMN "A" TYPE VARCHAR(20)') -and ($j.database -eq $fdb) -and ($r.Out -notmatch $pw)) $r.Out
  $bid = @($j.changes | Where-Object { $_.target -eq 'T.U' })[0].id
  $sel = Join-Path $work 'sel.txt'
  [IO.File]::WriteAllText($sel, "$bid`r`n")
  $r = Alter @('--apply', '--select', $sel)
  Check 'L5 a blocked id is refused, nothing written' (($r.Code -eq 1) -and ($r.Out -match 'is blocked') -and ((Shape) -eq $shape0)) $r.Out
  $r = Alter @('--apply')
  Check 'L4 --apply applies the checked change only' (($r.Code -eq 0) -and ($r.Out -match 'group direct: committed') -and ((Shape) -eq 'ID:8:0,A:37:20,N:37:10,U:37:10,X:8:0')) "$(Shape)`n$($r.Out)"
  $r = Alter @()
  Check 'L4b a second dry run no longer lists it' (($r.Code -eq 0) -and ($r.Out -notmatch 'T\.A TYPE')) $r.Out
  $r = Alter @('--safe-path', '--json')
  $j = JsonOf $r
  $n = @($j.changes | Where-Object { $_.target -eq 'T.N' })[0]
  Check 'L6a --safe-path offers the change unchecked, the pre-scans ran' (($n.kind -eq 'safe-type') -and ($n.blocked -eq '') -and ($n.checked -eq $false) -and ($n.prechecks[0].count -eq 0)) $r.Out
  $r = Alter @('--safe-path', '--apply')
  Check 'L6b --apply alone does not take it' (($r.Code -eq 0) -and ((Shape) -match 'N:37:10')) $r.Out
  [IO.File]::WriteAllText($sel, "$($n.id)`r`n")
  $r = Alter @('--safe-path', '--apply', '--select', $sel)
  Check 'L6c --apply --select converts it, position and values kept' (($r.Code -eq 0) -and ((Shape) -eq 'ID:8:0,A:37:20,N:8:0,U:37:10,X:8:0') -and ((Q 'SELECT ID || N FROM T ORDER BY ID') -eq '17,212')) "$(Shape) $(Q 'SELECT ID || N FROM T ORDER BY ID')`n$($r.Out)"
  $r = Alter @('--order', 'ID,X', '--apply')
  Check 'L6d --order moves the column' (($r.Code -eq 0) -and ((Shape) -eq 'ID:8:0,X:8:0,A:37:20,N:8:0,U:37:10')) "$(Shape)`n$($r.Out)"
  $r = Alter @('--hook', 'micronite')
  $r2 = Alter @('--hook', 'nope')
  Check 'L7 --hook micronite adds its notes; an unknown hook -> exit 1' (($r.Code -eq 0) -and ($r.Out -match 'update-orm --table T') -and ($r2.Code -eq 1) -and ($r2.Out -match 'generic, micronite')) "$($r.Out)`n$($r2.Out)"
  $cs0 = $cs
  $cs = "$cs0;OpenMode=OpenOrCreate"
  $r = Alter @()
  $cs = "$cs0;DropDatabase=Yes"
  $r2 = Alter @()
  $cs = $cs0
  Check 'L8 OpenMode / DropDatabase in --connection -> exit 1, the database is still there' (($r.Code -eq 1) -and ($r2.Code -eq 1) -and ((Q 'SELECT COUNT(*) FROM T') -eq '2')) "$($r.Out)`n$($r2.Out)"
} finally {
  $env:FIREBIRD = $saved
  try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "note: scratch folder kept: $work" }
}
if ($script:Failed) { Write-Host 'REPO ALTER-TABLE: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'REPO ALTER-TABLE: PASS' -ForegroundColor Green
exit 0
