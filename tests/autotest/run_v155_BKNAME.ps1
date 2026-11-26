<#
  run_v155_BKNAME.ps1 -- BKNAME (1.55): the name of a database backup. `repo backup --connection` and the backup
  `repo alter-table --apply` make DLFR_BACKUP_<database>_<yyyymmdd>_<hhnnss>.fbk; --backup-name <name> chooses another name
  (a name, not a path; .fbk added; an existing file is never overwritten); `repo backup purge` still deletes backups
  recorded under the old name form (<database>-yyyymmdd-hhnnsszzz.fbk), the new form and a chosen name.
  The pure name rules and the purge plan are in tests\fieldrepo\BackupTests.dpr (run_fieldrepo_backup.ps1, section N).

  CASES
    B1  --backup-name with a path, a drive, an empty value, on backup and alter-table; on list / purge -> exit 1, nothing written
    B2  default name on disk; --backup-name mine -> mine.fbk, recorded; again -> exit 1 "exists already", file untouched
    B3  purge --apply: an old-form entry, a default-named one and the chosen-name one are all deleted, the newest stays
    B4  alter-table --apply --backup-name <name> makes <name>.fbk
  Run: pwsh -File tests\autotest\run_v155_BKNAME.ps1 [-Exe <drag-lint.exe>]
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
Write-Host '== BKNAME: database backup names ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v155-bkname-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$savedFb = $env:FIREBIRD
$savedLocal = $env:LOCALAPPDATA
$env:LOCALAPPDATA = Join-Path $work 'local'
[IO.Directory]::CreateDirectory($env:LOCALAPPDATA) | Out-Null
$manifest = Join-Path $env:LOCALAPPDATA 'drag-lint\db-backups.json'
$script:Bin = $Exe
function Run([string[]]$a) {
  $o = & { $ErrorActionPreference = 'Continue'; & $script:Bin @a 2>&1 | ForEach-Object { "$_" } }
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
function JsonOf($r) {
  $line = @($r.Out -split "`n" | Where-Object { $_.StartsWith('{') })
  if ($line.Count -eq 0) { return $null }
  return ($line[-1] | ConvertFrom-Json | ForEach-Object { $_ })
}
function Fbk([string]$dir) { @(Get-ChildItem -LiteralPath $dir -Filter *.fbk -ErrorAction SilentlyContinue) }
try {
  $pw = 'Zq7s3cr3tPw'
  $repo = Join-Path $work 'x.dlrepo'
  $null = Run @('repo', 'init', '--repo', $repo)
  $cs0 = "Database=C:\no\such\x.fdb;User_Name=SYSDBA;Password=$pw"
  $n = 0
  foreach ($bad in @('a\b', 'a/b', 'C:x', '..\x', '   ', '.fbk', 'a*b', 'a.')) {
    $n++
    $r = Run @('repo', 'backup', '--connection', $cs0, '--backup-name', $bad)
    $r2 = Run @('repo', 'alter-table', '--repo', $repo, '--table', 'T', '--direction', 'repo-to-db', '--connection', $cs0, '--backup-name', $bad)
    Check "B1.$n a bad name '$bad' is refused by both verbs, nothing written" (($r.Code -eq 1) -and ($r.Out -match '--backup-name') -and ($r2.Code -eq 1) -and ($r2.Out -match '--backup-name') -and
      -not (Test-Path -LiteralPath $manifest) -and ($r.Out -notmatch $pw) -and ($r2.Out -notmatch $pw)) "$($r.Out)`n$($r2.Out)"
  }
  $r = Run @('repo', 'backup', 'list', '--backup-name', 'x')
  $r2 = Run @('repo', 'backup', 'purge', '--keep', '1', '--backup-name', 'x')
  Check 'B1x list and purge do not take --backup-name' (($r.Code -eq 1) -and ($r2.Code -eq 1) -and -not (Test-Path -LiteralPath $manifest)) "$($r.Out)`n$($r2.Out)"
  $embed = New-FirebirdEmbed (Join-Path $work 'fb')
  if (-not $embed) { Write-Host 'SKIP B2-B4 no Firebird 4 on this machine'; if ($script:Failed) { exit 1 } else { exit 0 } }
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
  $null = & { $ErrorActionPreference = 'Continue'; & "$embed\isql.exe" -q -i $sql 2>&1 | ForEach-Object { "$_" } }
  $cs = "Database=$fdb;User_Name=SYSDBA;Password=$pw"
  # B2
  $r = Run @('repo', 'backup', '--connection', $cs, '--verify', 'quick', '--json')
  $j1 = JsonOf $r
  Check 'B2a the default name' (($r.Code -eq 0) -and ((Split-Path $j1.file -Leaf) -match '^DLFR_BACKUP_scratch_\d{8}_\d{6}\.fbk$')) $r.Out
  $r = Run @('repo', 'backup', '--connection', $cs, '--verify', 'quick', '--backup-name', 'mine', '--json')
  $j2 = JsonOf $r
  Check 'B2b --backup-name mine -> mine.fbk beside the database, recorded as chosen' (($r.Code -eq 0) -and ((Split-Path $j2.file -Leaf) -eq 'mine.fbk') -and (Test-Path -LiteralPath (Join-Path $dbDir 'mine.fbk')) -and
    ([IO.File]::ReadAllText($manifest) -match '"named":\s*true')) $r.Out
  $size = (Get-Item -LiteralPath (Join-Path $dbDir 'mine.fbk')).Length
  $r = Run @('repo', 'backup', '--connection', $cs, '--verify', 'quick', '--backup-name', 'MINE.FBK')
  Check 'B2c the same name again -> exit 1, the file is untouched, nothing more recorded' (($r.Code -eq 1) -and ($r.Out -match 'exists already') -and ((Get-Item -LiteralPath (Join-Path $dbDir 'mine.fbk')).Length -eq $size) -and
    (@((Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json).backups).Count -eq 2)) $r.Out
  $other = Join-Path $work 'elsewhere'
  $r = Run @('repo', 'backup', '--connection', $cs, '--verify', 'quick', '--backup-name', 'in-dir.fbk', '--backup-dir', $other)
  Check 'B2d --backup-dir still picks the folder' (($r.Code -eq 0) -and (Test-Path -LiteralPath (Join-Path $other 'in-dir.fbk'))) $r.Out
  # B3: an entry under the old name form, made by copying a real backup
  $old = Join-Path $dbDir 'scratch-20200101-000000000.fbk'
  Copy-Item -LiteralPath $j1.file -Destination $old
  (Get-Item -LiteralPath $old).LastWriteTimeUtc = (Get-Item -LiteralPath $j1.file).LastWriteTimeUtc
  $m = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
  $e = $m.backups | Where-Object { $_.file -eq $j1.file } | Select-Object -First 1
  $copy = $e | ConvertTo-Json | ConvertFrom-Json
  $copy.file = $old
  $copy.created_utc = '2020-01-01T00:00:00.000Z'
  $m.backups = @($m.backups) + @($copy)
  [IO.File]::WriteAllText($manifest, ($m | ConvertTo-Json -Depth 6))
  $r = Run @('repo', 'backup', '--connection', $cs, '--verify', 'quick', '--json')
  $j3 = JsonOf $r
  $r = Run @('repo', 'backup', 'purge', '--keep', '1', '--apply', '--json', '--connection', $cs)
  $p = JsonOf $r
  $gone = @(@($old, $j1.file, $j2.file, (Join-Path $other 'in-dir.fbk')) | Where-Object { -not (Test-Path -LiteralPath $_) }).Count
  Check 'B3 purge deletes the old-form, the default-named and the chosen-name backups; the newest stays (purge is per database, whatever the folder)' (($r.Code -eq 0) -and ($gone -eq 4) -and (Test-Path -LiteralPath $j3.file)) $r.Out
  # B4: alter-table
  $ddl = Join-Path $work 'repo.sql'
  [IO.File]::WriteAllText($ddl, "CREATE TABLE T (ID INTEGER NOT NULL, A VARCHAR(20), CONSTRAINT PK_T PRIMARY KEY (ID));`r`n")
  $null = Run @('repo', 'seed-fb', '--ddl', $ddl, '--repo', $repo, '--apply')
  $bk = Join-Path $work 'bk'
  $r = Run @('repo', 'alter-table', '--repo', $repo, '--table', 'T', '--direction', 'repo-to-db', '--connection', $cs, '--backup-dir', $bk, '--backup-name', 'before-alter', '--verify', 'quick', '--apply')
  Check 'B4 alter-table --apply --backup-name makes before-alter.fbk' (($r.Code -eq 0) -and (Test-Path -LiteralPath (Join-Path $bk 'before-alter.fbk')) -and ($r.Out -match 'before-alter\.fbk')) $r.Out
} finally {
  $env:FIREBIRD = $savedFb
  $env:LOCALAPPDATA = $savedLocal
  try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "note: scratch folder kept: $work" }
}
if ($script:Failed) { Write-Host 'BKNAME: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'BKNAME: PASS' -ForegroundColor Green
exit 0