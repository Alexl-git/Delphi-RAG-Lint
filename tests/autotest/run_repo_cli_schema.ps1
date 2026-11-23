<#
  run_repo_cli_schema.ps1 -- FR-SCHEMA (1.53): `repo seed-fb` / `repo refresh-schema` as a change set, and
  `resolve-dbs --project` naming the repository, driven on the built engine. Offline: the schema comes from
  --ddl fixtures, no Firebird needed.

  CASES
    C1  seed-fb --ddl on an empty repository without --apply = DRY RUN: header + insert lines, no byte written
    C1b --dry-run wins over --apply: nothing written (positive control: C2, the same call without --dry-run)
    C2  seed-fb --ddl --apply writes (DL_FIELDS_INFO > 0, schema tables filled)
    C3  seed-fb again on a filled repository -> exit 1 (seed needs an empty one), nothing written
    C4  refresh-schema --ddl with a column removed: dry run prints the delete as (unchecked), header says 1 unchecked
    C5  refresh-schema --apply keeps the vanished row; --select <file> naming the delete removes it
    C6  --select naming an unknown id -> exit 1, nothing written
    C7  no source / two sources -> exit 1
    C8  a failed --connection never echoes the Password value (stdout + stderr); C8b / C8c = an error that WOULD show it, masked in any case, with a positive control
    C9  resolve-dbs --project: `repo: <path>` (stderr) and the json "repo" key; `none` without a repository
  Run: pwsh -File tests\autotest\run_repo_cli_schema.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '')
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
Write-Host '== repo seed-fb / refresh-schema as a change set ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-repo-schema-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
function Run([string[]]$a) {
  $o = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } }
  $out = ($o | ForEach-Object { "$_" }) -join "`n"
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}
# stdout and stderr kept apart: --json must leave stdout as ONE JSON document
function RunSplit([string[]]$a) {
  $ef = Join-Path $work ('e-' + [guid]::NewGuid().ToString('N') + '.txt')
  $o = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>$ef }
  $code = $LASTEXITCODE
  [pscustomobject]@{ Code = $code; Out = (($o | ForEach-Object { "$_" }) -join "`n"); Err = [IO.File]::ReadAllText($ef) }
}
function Fields($r) { $i = (Run @('repo', 'info', '--json', '--repo', $r)).Out | ConvertFrom-Json | ForEach-Object { $_ }; [int]$i.tables.DL_FIELDS_INFO }
try {
  $fix = Join-Path $Repo 'tests\fixtures\fieldrepo'
  $ddl = Join-Path $fix 'schema\ddl_basic.sql'
  $x = Join-Path $work 'x.dlrepo'
  $null = Run @('repo', 'init', '--repo', $x)
  $h0 = (Get-FileHash -LiteralPath $x).Hash
  $r = Run @('repo', 'seed-fb', '--ddl', $ddl, '--repo', $x)
  Check 'C1 seed-fb --ddl without --apply is a dry run (exit 0, change lines, no byte written)' (($r.Code -eq 0) -and ($r.Out -match 'direction db-to-repo, \d+ changes, 0 blocked, 0 unchecked') -and ($r.Out -match '\] insert DL_FIELDS_INFO CUSTOMER\|CITY') -and ($r.Out -match 'dry run: nothing written') -and ($h0 -eq (Get-FileHash -LiteralPath $x).Hash)) "exit=$($r.Code)`n$($r.Out)"
  $r = Run @('repo', 'seed-fb', '--ddl', $ddl, '--repo', $x, '--apply', '--dry-run')
  Check 'C1b --dry-run wins over --apply (exit 0, no byte written)' (($r.Code -eq 0) -and ($r.Out -match 'dry run: nothing written') -and ($h0 -eq (Get-FileHash -LiteralPath $x).Hash)) "exit=$($r.Code)`n$($r.Out)"
  $r = Run @('repo', 'seed-fb', '--ddl', $ddl, '--repo', $x, '--apply')
  Check 'C2 seed-fb --ddl --apply writes the fields' (($r.Code -eq 0) -and ($r.Out -match 'applied: \d+ changes') -and ((Fields $x) -gt 0)) "exit=$($r.Code)`n$($r.Out)"
  $n0 = Fields $x
  $h1 = (Get-FileHash -LiteralPath $x).Hash
  $r = Run @('repo', 'seed-fb', '--ddl', $ddl, '--repo', $x, '--apply')
  Check 'C3 seed-fb on a filled repository -> exit 1, nothing written' (($r.Code -eq 1) -and ($h1 -eq (Get-FileHash -LiteralPath $x).Hash)) "exit=$($r.Code)`n$($r.Out)"
  # a schema where CUSTOMER.CITY is gone
  $less = Join-Path $work 'less.sql'
  [IO.File]::WriteAllText($less, ((Get-Content -LiteralPath $ddl) | Where-Object { $_ -notmatch '^\s*CITY ' }) -join "`n")
  $r = Run @('repo', 'refresh-schema', '--ddl', $less, '--repo', $x)
  $del = [regex]::Match($r.Out, '\[(\d+)\] delete DL_FIELDS_INFO CUSTOMER\|CITY')
  Check 'C4 refresh dry run: the vanished column is a delete, (unchecked), counted in the header' (($r.Code -eq 0) -and $del.Success -and ($r.Out -match '\n  \(unchecked\)') -and ($r.Out -match ', 1 unchecked') -and ($h1 -eq (Get-FileHash -LiteralPath $x).Hash)) "exit=$($r.Code)`n$($r.Out)"
  $r = Run @('repo', 'refresh-schema', '--ddl', $less, '--repo', $x, '--apply')
  Check 'C5a refresh --apply keeps the vanished row' (($r.Code -eq 0) -and ((Fields $x) -eq $n0)) "exit=$($r.Code) fields=$(Fields $x) want=$n0`n$($r.Out)"
  $sel = Join-Path $work 'sel.txt'
  [IO.File]::WriteAllText($sel, "# delete the vanished column`n$($del.Groups[1].Value)`n")
  $r = Run @('repo', 'refresh-schema', '--ddl', $less, '--repo', $x, '--select', $sel)
  Check 'C5b refresh --select <file> naming the delete removes the row' (($r.Code -eq 0) -and ((Fields $x) -eq ($n0 - 1)) -and ($r.Out -match 'replacing')) "exit=$($r.Code) fields=$(Fields $x) want=$($n0 - 1)`n$($r.Out)"
  $h2 = (Get-FileHash -LiteralPath $x).Hash
  [IO.File]::WriteAllText($sel, "999`n")
  $r = Run @('repo', 'refresh-schema', '--ddl', $less, '--repo', $x, '--select', $sel)
  Check 'C6 --select with an unknown id -> exit 2 (v2 design: usage error), nothing written' (($r.Code -eq 2) -and ($h2 -eq (Get-FileHash -LiteralPath $x).Hash)) "exit=$($r.Code)`n$($r.Out)"
  $r = RunSplit @('repo', 'refresh-schema', '--ddl', $less, '--repo', $x, '--json')
  $jd = $null; try { $jd = $r.Out | ConvertFrom-Json | ForEach-Object { $_ } } catch { $null = $_ }
  Check 'C6b --json: stdout is exactly one JSON document, the dry-run notice goes to stderr' (($r.Code -eq 0) -and $jd -and ($jd.direction -eq 'db-to-repo') -and ($r.Err -match 'dry run: nothing written') -and ($r.Out -notmatch 'dry run')) "exit=$($r.Code)`n$($r.Out)"
  $y = Join-Path $work 'y.dlrepo'
  $null = Run @('repo', 'init', '--repo', $y)
  $r = RunSplit @('repo', 'seed-fb', '--ddl', $ddl, '--repo', $y, '--apply', '--json')
  $jd = $null; try { $jd = $r.Out | ConvertFrom-Json | ForEach-Object { $_ } } catch { $null = $_ }
  Check 'C6c --json with --apply: stdout is one JSON document, the applied lines go to stderr' (($r.Code -eq 0) -and $jd -and ($r.Err -match 'applied: \d+ changes') -and ($r.Out -notmatch 'applied:') -and ((Fields $y) -gt 0)) "exit=$($r.Code)`n$($r.Out)`n$($r.Err)"
  $r1 = Run @('repo', 'refresh-schema', '--repo', $x)
  $r2 = Run @('repo', 'refresh-schema', '--repo', $x, '--ddl', $ddl, '--connection', 'Database=localhost:nofile.fdb;User_Name=SYSDBA;Password=x')
  Check 'C7 no source / two sources -> exit 1' (($r1.Code -eq 1) -and ($r2.Code -eq 1) -and ($r1.Out -match 'exactly one source')) "$($r1.Code)/$($r2.Code)"
  $pw = 'Zq7s3cr3tPw'
  $r = Run @('repo', 'refresh-schema', '--repo', $x, '--connection', "Database=localhost:C:\no\such\dl-test.fdb;User_Name=SYSDBA;Password=$pw;DriverID=FB")
  Check 'C8 a failed connect exits 1 and never echoes the Password' (($r.Code -eq 1) -and (-not $r.Out.Contains($pw))) "exit=$($r.Code)`n$($r.Out)"
  # the driver id is echoed by FireDAC in the given and in UPPER case, so this output carries the password unless it is masked
  $conn = 'Database=localhost:C:\no\x.fdb;User_Name=SYSDBA;DriverID=' + $pw + ';Password='
  $r = Run @('repo', 'refresh-schema', '--repo', $x, '--connection', ($conn + $pw))
  Check 'C8b an error text holding the password is masked in any case' (($r.Code -eq 1) -and ($r.Out -match '\*\*\*') -and ($r.Out -notmatch $pw)) "exit=$($r.Code)`n$($r.Out)"
  $r = Run @('repo', 'refresh-schema', '--repo', $x, '--connection', ($conn + 'other'))
  Check 'C8c positive control: the same text shows when it is not the password' ($r.Out -cmatch $pw) "$($r.Out)"
  # a destructive FireDAC key is refused before anything is opened, the file survives, the password is never echoed
  $victim = Join-Path $work 'victim.fdb'
  [IO.File]::WriteAllBytes($victim, [byte[]](1..64))
  foreach ($k in 'OpenMode', 'CreateDatabase', 'DropDatabase', 'ConnectionDef', 'ConnectionDefName') {
    foreach ($sub in 'refresh-schema', 'seed-fb', 'import-fb') {
      $fresh = Join-Path $work ("fresh-$sub-$k.dlrepo")
      $null = Run @('repo', 'init', '--repo', $fresh)
      $r = Run @('repo', $sub, '--repo', $fresh, '--connection', "Database=$victim;User_Name=SYSDBA;Password=$pw;DriverID=FB;$k=Yes")
      Check "C8d $sub refuses $k (exit 1, names the key, no password, file survives)" (($r.Code -eq 1) -and ($r.Out -match [regex]::Escape($k)) -and (-not $r.Out.Contains($pw)) -and ((Get-Item -LiteralPath $victim).Length -eq 64)) "exit=$($r.Code)`n$($r.Out)"
    }
  }
  $r = Run @('fb-snapshot', '--db', (Join-Path $work 'sn.sqlite'), '--connection', "Database=$victim;User_Name=SYSDBA;Password=$pw;DriverID=FB;DropDatabase=Yes")
  Check 'C8e fb-snapshot refuses DropDatabase (non-zero exit, names the key, no password, file survives)' (($r.Code -ne 0) -and ($r.Out -match 'DropDatabase') -and (-not $r.Out.Contains($pw)) -and ((Get-Item -LiteralPath $victim).Length -eq 64)) "exit=$($r.Code)`n$($r.Out)"
  # resolve-dbs names the repository
  $loc = Join-Path $fix 'locate'
  $man = Join-Path $loc 'manifest.json'
  $mw = Join-Path $work 'manifest'
  [IO.Directory]::CreateDirectory($mw) | Out-Null
  Copy-Item -Path "$loc\*" -Destination $mw -Recurse -Force
  $r = Run @('resolve-dbs', '--project', (Join-Path $mw 'man\App.dproj'), '--config', (Join-Path $mw 'manifest.json'), '--json')
  $j = $null; try { $j = ($r.Out -split "`n" | Where-Object { $_ -like "{*" }) | ConvertFrom-Json | ForEach-Object { $_ } } catch { $null = $_ }
  Check 'C9a resolve-dbs --project --json carries the manifest repository' (($r.Code -eq 0) -and $j -and ($j.repo -like '*man.dlrepo')) "exit=$($r.Code)`n$($r.Out)"
  $r = Run @('resolve-dbs', '--project', (Join-Path $mw 'none\App.dproj'), '--config', (Join-Path $mw 'manifest.json'))
  Check 'C9b resolve-dbs --project without a repository says `repo: none`' (($r.Code -eq 0) -and ($r.Out -match 'repo: none')) "exit=$($r.Code)`n$($r.Out)"
} catch { Write-Host "ABORT: $_" -ForegroundColor Red; $script:Failed = $true }
finally { try { [IO.Directory]::Delete($work, $true) } catch { $null = $_ } }
if ($script:Failed) { Write-Host 'REPO CLI SCHEMA: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'REPO CLI SCHEMA: PASS' -ForegroundColor Green
exit 0
