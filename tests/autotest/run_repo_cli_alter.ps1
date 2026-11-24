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
    L6  --safe-path: unchecked; --apply --select (with the plan line of the dry run) applies it and the data survive; --order moves a column
    L7  --hook micronite adds its notes; an unknown hook -> exit 1
    L10 an empty or missing value of --select / --hook / --order -> refused; an apply names what it left out
    A3  the --connection keys are checked before the repository is opened
    R7  --select all (file): everything except the drop; the drop by its own id
    R8  a widening with a view on the column: unchecked, the view named; --select takes it
    R9  --apply makes the backup first (verified, recorded, total printed); no usable backup folder / a failing restore / another
        machine -> exit 1, nothing changed; --verify quick; a bad --verify value; nothing to apply -> no backup
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
$savedLocal = $env:LOCALAPPDATA
$env:LOCALAPPDATA = Join-Path $work 'local'   # the list of backups of this run, never the user's
[IO.Directory]::CreateDirectory($env:LOCALAPPDATA) | Out-Null
$bk = Join-Path $work 'bk'
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
  $r2 = Run @('repo', 'alter-table', '--repo', $repo, '--table', 'T', '--direction', 'repo-to-db', '--connection', "$cs;DropDatabase=Yes")
  Check 'A3 the --connection keys are checked before anything is opened, the repository included' (($r2.Code -eq 1) -and ($r2.Out -match 'DropDatabase is not allowed')) $r2.Out
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
INSERT INTO T VALUES (1, 'abc', '7', 'u', 1);
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
  function Alter([string[]]$more) { Run (@('repo', 'alter-table', '--repo', $repo, '--table', 'T', '--direction', 'repo-to-db', '--connection', $cs, '--backup-dir', $bk) + $more) }
  function Backups { @(Get-ChildItem -LiteralPath $bk -Filter *.fbk -ErrorAction SilentlyContinue).Count }
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
  Check 'L2 dry run: DDL, a blocked reason, the dependent of an unchecked widening, exit 0, the database unchanged' (($r.Code -eq 0) -and ($r.Out -match 'ALTER TABLE "T" ALTER COLUMN "A" TYPE VARCHAR\(20\)') -and
    ($r.Out -match 'BLOCKED: refused-conversion') -and ($r.Out -match 'dependent: view V') -and ($r.Out -match 'dry run: nothing written') -and ((Shape) -eq $shape0)) "$(Shape)`n$($r.Out)"
  $r = Alter @('--apply', '--dry-run')
  Check 'L2b --dry-run wins over --apply' (($r.Code -eq 0) -and ($r.Out -match 'dry run: nothing written') -and ((Shape) -eq $shape0)) $r.Out
  $all = Join-Path $work 'all.txt'
  [IO.File]::WriteAllText($all, "all`r`n")
  $r = Alter @('--select', $all)
  Check 'L2c --select without --apply writes nothing' (($r.Code -eq 0) -and ($r.Out -match 'dry run: nothing written') -and ((Shape) -eq $shape0)) $r.Out
  $r = Alter @('--json')
  $j = JsonOf $r
  $a = @($j.changes | Where-Object { $_.target -eq 'T.A' })
  Check 'L3 --json: one object with direction, ddl, blocked; no password' (($r.Code -eq 0) -and ($j.direction -eq 'repo-to-db') -and ($j.dry_run -eq $true) -and ($j.blocked -eq 1) -and (@($j.changes | Where-Object { $_.target -eq 'T.U' })[0].dependents -contains 'view V') -and ($a.Count -eq 1) -and
    ($a[0].ddl[0] -eq 'ALTER TABLE "T" ALTER COLUMN "A" TYPE VARCHAR(20)') -and ($j.database -eq $fdb) -and ($r.Out -notmatch $pw)) $r.Out
  Check 'R9n no backup was made by dry runs' ((Backups) -eq 0) "$(Backups)"
  $bid = @($j.changes | Where-Object { $_.target -eq 'T.N' })[0].id
  $sel = Join-Path $work 'sel.txt'
  [IO.File]::WriteAllText($sel, "plan $($j.plan_hash)`r`n$bid`r`n")
  $r = Alter @('--apply', '--select', $sel)
  Check 'L5 a blocked id is refused, nothing written' (($r.Code -eq 1) -and ($r.Out -match 'is blocked') -and ((Shape) -eq $shape0)) $r.Out
  # R9: no backup, no apply
  $asFile = Join-Path $work 'afile'
  [IO.File]::WriteAllText($asFile, 'x')
  $r = Run @('repo', 'alter-table', '--repo', $repo, '--table', 'T', '--direction', 'repo-to-db', '--connection', $cs, '--backup-dir', $asFile, '--apply')
  Check 'R9a no usable backup folder -> exit 1, nothing changed' (($r.Code -eq 1) -and ($r.Out -match 'no backup, nothing applied') -and ((Shape) -eq $shape0)) "$(Shape)`n$($r.Out)"
  $r = Alter @('--apply', '--verify', 'maybe')
  Check 'R9b a bad --verify value -> exit 1, nothing changed' (($r.Code -eq 1) -and ($r.Out -match '--verify takes full') -and ((Shape) -eq $shape0)) $r.Out
  $r = Run @('repo', 'alter-table', '--repo', $repo, '--table', 'T', '--direction', 'repo-to-db', '--connection', "Server=srv.invalid;Database=C:\x.fdb;User_Name=SYSDBA;Password=$pw", '--apply')
  Check 'R9c another machine -> exit 1 before anything is opened, no password' (($r.Code -eq 1) -and ($r.Out -match 'not on this machine \(srv.invalid\)') -and ($r.Out -notmatch $pw)) $r.Out
  $broken = Join-Path $env:LOCALAPPDATA 'drag-lint\db-backups.json'
  [IO.Directory]::CreateDirectory((Split-Path $broken)) | Out-Null
  [IO.File]::WriteAllText($broken, 'no list')
  $r = Alter @('--apply')
  Check 'R9d a list of backups that cannot be read -> exit 1, nothing changed, the file kept' (($r.Code -eq 1) -and ($r.Out -match 'not readable') -and ((Shape) -eq $shape0) -and ([IO.File]::ReadAllText($broken) -eq 'no list')) $r.Out
  [IO.File]::Delete($broken)
  $r = Alter @('--apply')
  $list = (Run @('repo', 'backup', 'list', '--json')).Out | ConvertFrom-Json
  Check 'R9e --apply made one verified, recorded backup and printed the total' (((Backups) -eq 1) -and ($r.Out -match 'backup: .*\.fbk \(\d+ bytes, verified full: 2 table\(s\) and view\(s\) compared, 2 row\(s\)\)') -and
    ($r.Out -match 'backups on disk: 1 file\(s\)') -and (@($list.backups).Count -eq 1) -and ($list.backups[0].verified -eq 'full') -and ($list.backups[0].state -eq 'ok')) "$($r.Out)`n$($list | ConvertTo-Json -Depth 4)"
  Check 'R9f only the backup is left: the temporary database is gone' (@(Get-ChildItem -LiteralPath $bk).Count -eq 1) ((Get-ChildItem -LiteralPath $bk).Name -join ',')
  Check 'L4 --apply applies the checked change only' (($r.Code -eq 0) -and ($r.Out -match 'group direct: committed') -and ((Shape) -eq 'ID:8:0,A:37:20,N:37:10,U:37:10,X:8:0')) "$(Shape)`n$($r.Out)"
  $r = Alter @()
  $n0 = Backups
  $r0 = Alter @('--apply')
  Check 'R9g nothing to apply: no backup' (($r0.Code -eq 0) -and ((Backups) -eq $n0)) $r0.Out
  Check 'L4b a second dry run no longer lists it' (($r.Code -eq 0) -and ($r.Out -notmatch 'T\.A TYPE')) $r.Out
  $r = Alter @('--safe-path', '--json')
  $j = JsonOf $r
  $n = @($j.changes | Where-Object { $_.target -eq 'T.N' })[0]
  Check 'L6a --safe-path offers the change unchecked, the pre-scans ran' (($n.kind -eq 'safe-type') -and ($n.blocked -eq '') -and ($n.checked -eq $false) -and ($n.prechecks[0].count -eq 0)) $r.Out
  $r = Alter @('--safe-path', '--apply')
  Check 'L6b --apply alone does not take it' (($r.Code -eq 0) -and ((Shape) -match 'N:37:10')) $r.Out
  [IO.File]::WriteAllText($sel, "$($n.id)`r`n")
  $r = Alter @('--safe-path', '--apply', '--select', $sel)
  Check 'L6e --apply --select without the plan line of the dry run -> exit 1, nothing written' (($r.Code -eq 1) -and ($r.Out -match 'plan <hash>') -and ((Shape) -match 'N:37:10')) $r.Out
  [IO.File]::WriteAllText($sel, "plan 0123abcd`r`n$($n.id)`r`n")
  $r = Alter @('--safe-path', '--apply', '--select', $sel)
  Check 'L6f the plan line of another plan -> exit 1, nothing written' (($r.Code -eq 1) -and ($r.Out -match 'plan changed') -and ((Shape) -match 'N:37:10')) $r.Out
  [IO.File]::WriteAllText($sel, "plan $($j.plan_hash)`r`n$($n.id)`r`n")
  $r = Alter @('--safe-path', '--apply', '--select', $sel)
  Check 'L6c --apply --select converts it, position and values kept' (($r.Code -eq 0) -and ((Shape) -eq 'ID:8:0,A:37:20,N:8:0,U:37:10,X:8:0') -and ((Q 'SELECT ID || N FROM T ORDER BY ID') -eq '17,212')) "$(Shape) $(Q 'SELECT ID || N FROM T ORDER BY ID')`n$($r.Out)"
  $r = Alter @('--order', 'ID,X', '--apply')
  Check 'L6d --order moves the column' (($r.Code -eq 0) -and ((Shape) -eq 'ID:8:0,X:8:0,A:37:20,N:8:0,U:37:10')) "$(Shape)`n$($r.Out)"
  # R8: the view column, by --select
  $j = JsonOf (Alter @('--json'))
  $u = @($j.changes | Where-Object { $_.target -eq 'T.U' })[0]
  [IO.File]::WriteAllText($sel, "plan $($j.plan_hash)`r`n$($u.id)`r`n")
  $r = Alter @('--apply', '--select', $sel, '--verify', 'quick')
  Check 'R8 --select takes the widening of a column a view uses; the view still answers; --verify quick' (($r.Code -eq 0) -and ((Shape) -match 'U:37:30') -and ((Q 'SELECT COUNT(U) FROM V') -eq '2') -and
    ($r.Out -match 'verified quick\)')) "$(Shape)`n$($r.Out)"
  # R7: the repository loses X and widens A: all takes the widening, never the drop
  [IO.File]::WriteAllText($ddl, "CREATE TABLE T (ID INTEGER NOT NULL, A VARCHAR(25), N INTEGER, U VARCHAR(30), CONSTRAINT PK_T PRIMARY KEY (ID));`r`n")
  $null = Run @('repo', 'refresh-schema', '--ddl', $ddl, '--repo', $repo, '--apply')
  $j = JsonOf (Alter @('--json'))
  $drop = @($j.changes | Where-Object { $_.kind -eq 'drop' })
  if ($drop.Count -eq 1) {
    [IO.File]::WriteAllText($sel, "plan $($j.plan_hash)`r`nall`r`n")
    $r = Alter @('--apply', '--select', $sel, '--verify', 'quick')
    Check 'R7a all applies the rest and leaves the drop' (($r.Code -eq 0) -and ((Shape) -match 'X:8:0') -and ((Shape) -match 'A:37:25') -and ($r.Out -match 'not applied: ')) "$(Shape)`n$($r.Out)"
    $j = JsonOf (Alter @('--json'))
    $drop = @($j.changes | Where-Object { $_.kind -eq 'drop' })
    [IO.File]::WriteAllText($sel, "plan $($j.plan_hash)`r`n$($drop[0].id)`r`n")
    $r = Alter @('--apply', '--select', $sel, '--verify', 'quick')
    Check 'R7b the drop by its own id' (($r.Code -eq 0) -and ((Shape) -notmatch 'X:8:0')) "$(Shape)`n$($r.Out)"
  } else { Check 'R7 the plan offers the drop' $false ($j | ConvertTo-Json -Depth 5) }
  $r = Alter @('--hook', 'micronite')
  $r2 = Alter @('--hook', 'nope')
  Check 'L7 --hook micronite adds its notes; an unknown hook -> exit 1' (($r.Code -eq 0) -and ($r.Out -match 'update-orm --table T') -and ($r2.Code -eq 1) -and ($r2.Out -match 'generic, micronite')) "$($r.Out)`n$($r2.Out)"
  # an empty or missing value must not fall back to the default selection or to the generic hook
  [IO.File]::WriteAllText($ddl, "CREATE TABLE T (ID INTEGER NOT NULL, A VARCHAR(40), N INTEGER, U VARCHAR(30), X INTEGER, CONSTRAINT PK_T PRIMARY KEY (ID));`r`n")
  $r = Run @('repo', 'refresh-schema', '--ddl', $ddl, '--repo', $repo, '--apply')
  $shape1 = Shape
  $r = Alter @('--apply', '--select', '')
  Check 'L10 an empty --select -> refused, nothing written' (($r.Code -ne 0) -and ((Shape) -eq $shape1)) "$(Shape)`n$($r.Out)"
  $r = Alter @('--hook', '', '--apply')
  Check 'L10b an empty --hook -> exit 1, nothing written' (($r.Code -eq 1) -and ((Shape) -eq $shape1)) "$(Shape)`n$($r.Out)"
  $r = Alter @('--order', '--apply')
  Check 'L10c a flag in the place of a value -> exit 1' (($r.Code -eq 1) -and ((Shape) -eq $shape1)) "$(Shape)`n$($r.Out)"
  $r = Alter @('--apply')
  Check 'L10d positive control: the change was there to apply; what was left out is named' (($r.Code -eq 0) -and ((Shape) -match 'A:37:40') -and ($r.Out -match 'not applied: ')) "$(Shape)`n$($r.Out)"
  $cs0 = $cs
  $cs = "$cs0;OpenMode=OpenOrCreate"
  $r = Alter @()
  $cs = "$cs0;DropDatabase=Yes"
  $r2 = Alter @()
  $cs = $cs0
  Check 'L8 OpenMode / DropDatabase in --connection -> exit 1, the database is still there' (($r.Code -eq 1) -and ($r2.Code -eq 1) -and ((Q 'SELECT COUNT(*) FROM T') -eq '2')) "$($r.Out)`n$($r2.Out)"
  $cs = "$cs0;  dropdatabase = Yes"
  $r = Alter @()
  $cs = "$cs0`nFoo=1"
  $r2 = Alter @()
  $cs = $cs0
  Check 'L9 spaced lower-case DropDatabase and a line break in --connection -> exit 1 (shared FbConnString), the database is still there' (($r.Code -eq 1) -and ($r.Out -match 'DropDatabase is not allowed in --connection') -and ($r2.Code -eq 1) -and ($r2.Out -match 'line break is not allowed in --connection') -and ((Q 'SELECT COUNT(*) FROM T') -eq '2')) "$($r.Out)`n$($r2.Out)"
} finally {
  $env:FIREBIRD = $saved
  $env:LOCALAPPDATA = $savedLocal
  try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "note: scratch folder kept: $work" }
}
if ($script:Failed) { Write-Host 'REPO ALTER-TABLE: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'REPO ALTER-TABLE: PASS' -ForegroundColor Green
exit 0
