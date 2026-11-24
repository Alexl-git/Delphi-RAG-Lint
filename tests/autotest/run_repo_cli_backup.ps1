<#
  run_repo_cli_backup.ps1 -- ALTERBK (1.54): `repo backup --connection`, `repo backup list`, `repo backup purge` driven on the
  built engine. The databases are SCRATCH files of a private embedded Firebird (lib\FirebirdEmbed.ps1); the engine is copied
  beside that private fbclient.dll, so it cannot reach a server. LOCALAPPDATA points into the scratch folder, so the user's own
  list of backups is never read or written.

  CASES
    C1  bad arguments: --repo with --connection, a bad --verify, purge without --keep, --keep 0 -> exit 1; another machine -> exit 1
    C2  `repo backup --repo` without --connection is still the text backup of the repository
    C3  `repo backup --connection`: verified file beside the database, total printed, no password; --json
    C4  --backup-dir wins over the project's backupDir, which wins over "beside the database"
    C5  list: the files with their state
    C6  purge: dry run deletes nothing; --apply deletes only old listed files; modified and foreign files stay; newest verified stays
  Run: pwsh -File tests\autotest\run_repo_cli_backup.ps1 [-Exe <drag-lint.exe>]
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
Write-Host '== repo backup (database) ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-repo-backup-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$savedFb = $env:FIREBIRD
$savedLocal = $env:LOCALAPPDATA
$env:LOCALAPPDATA = Join-Path $work 'local'
[IO.Directory]::CreateDirectory($env:LOCALAPPDATA) | Out-Null
$manifest = Join-Path $env:LOCALAPPDATA 'drag-lint\db-backups.json'
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
function Fbk([string]$dir) { @(Get-ChildItem -LiteralPath $dir -Filter *.fbk -ErrorAction SilentlyContinue) }
try {
  $pw = 'Zq7s3cr3tPw'
  $repo = Join-Path $work 'x.dlrepo'
  $null = Run @('repo', 'init', '--repo', $repo)
  $far = "Server=srv.invalid;Database=C:\x.fdb;User_Name=SYSDBA;Password=$pw"
  $r = Run @('repo', 'backup', '--connection', $far, '--repo', $repo)
  Check 'C1a --repo with --connection -> exit 1' (($r.Code -eq 1) -and ($r.Out -match '--repo does not go with')) $r.Out
  $r = Run @('repo', 'backup', '--connection', $far, '--verify', 'some')
  Check 'C1b a bad --verify -> exit 1' (($r.Code -eq 1) -and ($r.Out -match '--verify takes full')) $r.Out
  $r = Run @('repo', 'backup', '--connection', $far)
  Check 'C1c another machine -> exit 1, no password' (($r.Code -eq 1) -and ($r.Out -match 'not on this machine \(srv\.invalid\)') -and ($r.Out -notmatch $pw)) $r.Out
  $r = Run @('repo', 'backup', 'purge')
  $r2 = Run @('repo', 'backup', 'purge', '--keep', '0')
  $r3 = Run @('repo', 'backup', 'purge', '--keep', 'x', '--apply')
  Check 'C1d purge without a usable --keep -> exit 1' (($r.Code -eq 1) -and ($r.Out -match '--keep') -and ($r2.Code -eq 1) -and ($r3.Code -eq 1)) "$($r.Out)`n$($r2.Out)`n$($r3.Out)"
  Check 'C1e nothing of it wrote a list' (-not (Test-Path -LiteralPath $manifest))
  $r = Run @('repo', 'backup', '--repo', $repo)
  Check 'C2 without --connection it is the text backup of the repository' (($r.Code -eq 0) -and (Test-Path -LiteralPath "$repo.txt")) $r.Out
  $embed = New-FirebirdEmbed (Join-Path $work 'fb')
  if (-not $embed) { Write-Host 'SKIP C3-C6 no Firebird 4 on this machine'; if ($script:Failed) { exit 1 } else { exit 0 } }
  $env:FIREBIRD = $embed
  Get-ChildItem -LiteralPath (Split-Path $Exe) -File | Where-Object { $_.Extension -eq '.dll' -or $_.Name -eq 'drag-lint.exe' } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $embed }
  $script:Bin = Join-Path $embed 'drag-lint.exe'
  $dbDir = Join-Path $work 'db'
  [IO.Directory]::CreateDirectory($dbDir) | Out-Null
  $fdb = Join-Path $dbDir 'scratch.fdb'
  $sql = Join-Path $work 'create.sql'
  [IO.File]::WriteAllText($sql, @"
CREATE DATABASE '$fdb' USER 'SYSDBA' PAGE_SIZE 8192 DEFAULT CHARACTER SET UTF8;
CREATE TABLE T (ID INTEGER NOT NULL PRIMARY KEY, A VARCHAR(10));
COMMIT;
INSERT INTO T VALUES (1, 'a');
COMMIT;
"@)
  $null = & "$embed\isql.exe" -q -i $sql 2>&1
  $cs = "Database=$fdb;User_Name=SYSDBA;Password=$pw"
  $r = Run @('repo', 'backup', '--connection', $cs)
  $made = Fbk $dbDir
  Check 'C3a a verified backup beside the database, the total printed, no password' (($r.Code -eq 0) -and ($made.Count -eq 1) -and ($made[0].Name -match '(?i)^scratch-\d{8}-\d{9}\.fbk$') -and
    ($r.Out -match 'verified full: 1 table\(s\)') -and ($r.Out -match 'backups on disk: 1 file\(s\), \d+ bytes in total') -and ($r.Out -notmatch $pw)) $r.Out
  Check 'C3b only database and backup are in the folder' (@(Get-ChildItem -LiteralPath $dbDir).Count -eq 2) ((Get-ChildItem -LiteralPath $dbDir).Name -join ',')
  $r = Run @('repo', 'backup', '--connection', $cs, '--verify', 'quick', '--table', 't', '--json')
  $j = JsonOf $r
  Check 'C3c --json, quick' (($r.Code -eq 0) -and ($j.verified -eq 'quick') -and ($j.tables -eq 0) -and ($j.total_files -eq 2) -and (Test-Path -LiteralPath $j.file)) $r.Out
  Check 'C3d no password in the list' ((Test-Path -LiteralPath $manifest) -and ([IO.File]::ReadAllText($manifest) -notmatch $pw))
  $r = Run @('repo', 'backup', '--connection', "$cs;DropDatabase=Yes")
  Check 'C3e DropDatabase in --connection -> exit 1, the database is still there' (($r.Code -eq 1) -and ($r.Out -match 'DropDatabase is not allowed') -and (Test-Path -LiteralPath $fdb)) $r.Out
  # folders
  $proj = Join-Path $work 'proj'
  [IO.Directory]::CreateDirectory((Join-Path $proj '_D-RAG')) | Out-Null
  [IO.File]::WriteAllText((Join-Path $proj '_D-RAG\drag-lint-project.json'), '{ "backupDir": "..\\viaproject" }')
  [IO.File]::WriteAllText((Join-Path $proj 'App.dproj'), '<Project/>')
  $r = Run @('repo', 'backup', '--connection', $cs, '--project', (Join-Path $proj 'App.dproj'), '--verify', 'quick')
  Check 'C4a the backupDir of the project' (($r.Code -eq 0) -and ((Fbk (Join-Path $work 'viaproject')).Count -eq 1)) $r.Out
  $r = Run @('repo', 'backup', '--connection', $cs, '--project', (Join-Path $proj 'App.dproj'), '--backup-dir', (Join-Path $work 'viaflag'), '--verify', 'quick')
  Check 'C4b --backup-dir wins' (($r.Code -eq 0) -and ((Fbk (Join-Path $work 'viaflag')).Count -eq 1) -and ((Fbk (Join-Path $work 'viaproject')).Count -eq 1)) $r.Out
  # list: 4 backups: full, quick, quick (project), quick (flag)
  $l = JsonOf (Run @('repo', 'backup', 'list', '--json'))
  Check 'C5a list --json' ((@($l.backups).Count -eq 4) -and (@($l.backups | Where-Object { $_.state -eq 'ok' }).Count -eq 4) -and ($l.total_files -eq 4) -and ($l.manifest -eq $manifest)) ($l | ConvertTo-Json -Depth 4)
  $third = $l.backups[2].file
  [IO.File]::AppendAllText($third, 'x')
  $foreign = Join-Path $dbDir 'SCRATCH-20200101-000000000.fbk'
  [IO.File]::WriteAllText($foreign, 'a backup of somebody else')
  $r = Run @('repo', 'backup', 'list')
  Check 'C5b a modified file shows as changed; the foreign one is not listed' (($r.Code -eq 0) -and ($r.Out -match '(?m)changed$') -and ($r.Out -notmatch '20200101') -and ($r.Out -match '3 file\(s\)')) $r.Out
  $before = [IO.File]::ReadAllText($manifest)
  $r = Run @('repo', 'backup', 'purge', '--keep', '1')
  Check 'C6a dry run: nothing deleted, nothing written' (($r.Code -eq 0) -and ($r.Out -match 'dry run: nothing deleted') -and ($r.Out -match '(?m)^delete ') -and ([IO.File]::ReadAllText($manifest) -eq $before) -and
    (Test-Path -LiteralPath $l.backups[1].file)) $r.Out
  $r = Run @('repo', 'backup', 'purge', '--keep', '1', '--apply', '--dry-run')
  Check 'C6b --dry-run wins over --apply' (($r.Code -eq 0) -and (Test-Path -LiteralPath $l.backups[1].file)) $r.Out
  $r = Run @('repo', 'backup', 'purge', '--keep', '1', '--apply', '--json')
  $j = JsonOf $r
  $acts = (@($j.items) | ForEach-Object { $_.action }) -join ','
  Check 'C6c --apply: the newest stays, the modified one is skipped, the old quick one goes, the newest verified one stays' (($r.Code -eq 0) -and ($acts -eq 'keep,skip,delete,keep') -and
    -not (Test-Path -LiteralPath $l.backups[1].file) -and (Test-Path -LiteralPath $l.backups[0].file) -and (Test-Path -LiteralPath $third) -and (Test-Path -LiteralPath $l.backups[3].file)) "$acts`n$($r.Out)"
  Check 'C6d the foreign file and the database are untouched' ((Test-Path -LiteralPath $foreign) -and (Test-Path -LiteralPath $fdb))
} finally {
  $env:FIREBIRD = $savedFb
  $env:LOCALAPPDATA = $savedLocal
  try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "note: scratch folder kept: $work" }
}
if ($script:Failed) { Write-Host 'REPO BACKUP: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'REPO BACKUP: PASS' -ForegroundColor Green
exit 0
