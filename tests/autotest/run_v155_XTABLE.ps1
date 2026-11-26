<#
  run_v155_XTABLE.ps1 -- lane XTABLE slice X1 (1.55): cross-table fields, repository schema 4
  (design docs\superpowers\specs\2026-11-26-cross-table-fields-design.md section 2).
  Part A builds + runs tests\fieldrepo\CrossTableTests.dpr (schema 4, migrate 3 -> 4, #DLREPO 4, ALIAS.FIELD macros,
  dependency closure, repo check rules). Part B drives the engine: repo init (schema 4), restore of the clean fixture
  xtable_v4.txt checks clean, a planted copy names input-path-broken and input-alias-undeclared, a #DLREPO 3 file
  migrates to 4 (dry run changes no byte), the backup round trip is byte-identical.
  Slice X2 (design 3.2): Part C builds + runs tests\fieldrepo\RelationGraphTests.dpr (one path, ambiguous, stored /
  form / default rules, keyless parent, depth, roles, loader). Part D drives `repo paths` on
  xtable\xtable_paths_v4.txt and the MICRONITEV6A counts: on a COPY of -V6aRepo, else of a repository seeded
  read-only from -V6aConnection (skipped, and said so, when neither is reachable); the original is checked unchanged.
  Run: pwsh -File tests\autotest\run_v155_XTABLE.ps1 [-Exe <drag-lint.exe>] [-SkipBuild] [-V6aRepo <file>]
       [-V6aConnection <Firebird connection string>]
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$SkipBuild, [string]$V6aRepo = '',
  [string]$V6aConnection = 'Database=C:\Projects\DB\SQL\MICRONITEV6A.FDB;User_Name=SYSDBA;Password=masterkey;DriverID=FB;Server=localhost')
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
Write-Host '== v1.55 XTABLE: cross-table fields, schema 4 + relation paths ==' -ForegroundColor Cyan
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-xtable-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
try {
  # ---- A: unit tests
  $bat = Join-Path $Repo 'build\_build_fieldrepo_xtable_tests_local.bat'
  $bin = Join-Path $Repo 'tests\fieldrepo\CrossTableTests.exe'
  if (-not $SkipBuild) {
    $blog = Join-Path $work 'build.log'
    Start-Process -FilePath cmd.exe -ArgumentList (('/c ' + [char]34 + [char]34 + $bat + [char]34 + ' > ' + [char]34 + $blog + [char]34 + ' 2>&1' + [char]34)) -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    Check 'A0 CrossTableTests build' (($bl -match 'BUILD_EXITCODE=0') -and ($bl -notmatch '\[dcc\w*\] Error|: error ')) $blog
  }
  $log = Join-Path $work 'run.log'
  & { $ErrorActionPreference = 'Continue'; & $bin *> $log }
  $code = $LASTEXITCODE
  Select-String -LiteralPath $log -Pattern '^FAIL' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
  $sum = Select-String -LiteralPath $log -Pattern '^SUMMARY ' | Select-Object -Last 1
  Check 'A1 CrossTableTests SUMMARY fail=0' (($code -eq 0) -and $sum -and ($sum.Line -match 'fail=0\b')) ($sum.Line)

  # ---- B: engine
  if (-not (Test-Path -LiteralPath $Exe)) { Check 'B0 engine exe exists' $false $Exe; throw 'no exe' }
  function Run([string[]]$a) {
    $o = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } }
    $out = ($o | ForEach-Object { "$_" }) -join "`n"
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
  }
  $fix = Join-Path $Repo 'tests\fixtures\fieldrepo'
  $clean = Join-Path $fix 'xtable\xtable_v4.txt'
  $x = Join-Path $work 'x.dlrepo'
  $r = Run @('repo', 'init', '--repo', $x)
  $info = (Run @('repo', 'info', '--repo', $x)).Out
  Check 'B1 repo init creates a schema-4 file with the three cross-table tables' (($r.Code -eq 0) -and ($info -match 'schema_version: 4') -and ($info -match 'DL_RELATIONS: 0 rows') -and ($info -match 'DL_RELATION_COLUMNS: 0 rows') -and ($info -match 'DL_FIELD_INPUTS: 0 rows')) $info
  $r = Run @('repo', 'restore', '--repo', $x, '--in', $clean)
  Check 'B2 restore of the clean fixture' ($r.Code -eq 0) $r.Out
  $r = Run @('repo', 'check', '--repo', $x)
  Check 'B3 positive control: the IPCHART -> INSPRSLT -> MSCLIST fixture checks clean' (($r.Code -eq 0) -and ($r.Out -match 'check: clean')) "exit=$($r.Code) $($r.Out)"
  $bk = Join-Path $work 'x.txt'
  $r = Run @('repo', 'backup', '--repo', $x, '--output', $bk)
  Check 'B4 backup of the restored fixture is byte-identical, #DLREPO 4' (($r.Code -eq 0) -and ([IO.File]::ReadAllText($bk) -ceq [IO.File]::ReadAllText($clean)) -and [IO.File]::ReadAllText($bk).StartsWith('#DLREPO 4')) $r.Out

  $bad = Join-Path $work 'bad.txt'
  $txt = [IO.File]::ReadAllText($clean)
  $planted = $txt.Replace('PATH=FK_IPCHART_INSP>FK_INSP_MSC', 'PATH=FK_INSP_MSC').Replace('{{MSC.DECIMALS}}', '{{X.DECIMALS}}')
  Check 'B5 the planted copy differs from the fixture (positive control of the plant)' ($planted -cne $txt)
  [IO.File]::WriteAllText($bad, $planted, [Text.Encoding]::ASCII)
  $y = Join-Path $work 'y.dlrepo'
  $null = Run @('repo', 'restore', '--repo', $y, '--in', $bad)
  $r = Run @('repo', 'check', '--repo', $y)
  Check 'B6 the planted copy: exit 1, input-path-broken and input-alias-undeclared named' (($r.Code -eq 1) -and ($r.Out -match 'ERROR input-path-broken input IPCHART\.FTRNAME MSC') -and ($r.Out -match 'ERROR input-alias-undeclared IPCHART\.FTRNAME')) "exit=$($r.Code)`n$($r.Out)"
  $r = Run @('repo', 'check', '--repo', $y, '--json')
  $j = $null; try { $j = $r.Out | ConvertFrom-Json } catch { }
  Check 'B7 repo check --json lists both codes' (($r.Code -eq 1) -and $j -and (@($j.findings | Where-Object { $_.code -eq 'input-path-broken' }).Count -eq 1) -and (@($j.findings | Where-Object { $_.code -eq 'input-alias-undeclared' }).Count -eq 1)) "exit=$($r.Code)"

  # schema 3 -> 4
  $v3 = Join-Path $work 'v3.dlrepo'
  $r = Run @('repo', 'restore', '--repo', $v3, '--in', (Join-Path $fix 'golden_v3.txt'))
  Check 'B8 a #DLREPO 3 backup into a missing file creates schema 3' (($r.Code -eq 0) -and ((Run @('repo','info','--repo',$v3)).Out -match 'schema_version: 3')) $r.Out
  $h3 = (Get-FileHash -LiteralPath $v3).Hash
  $r = Run @('repo', 'migrate', '--repo', $v3)
  Check 'B9 v3 -> v4 dry run: three CREATEs, nothing else, no byte changed' (($r.Code -eq 0) -and ($r.Out -match 'v3 -> v4: create DL_RELATIONS, DL_RELATION_COLUMNS, DL_FIELD_INPUTS, ALIGNMENT -2 to NULL in 0 rows, user_version 4') -and ($h3 -eq (Get-FileHash -LiteralPath $v3).Hash)) $r.Out
  $r = Run @('repo', 'migrate', '--repo', $v3, '--apply')
  $b3 = @(Get-ChildItem $work -Filter 'v3.dlrepo.before-migrate-*.txt')
  Check 'B10 v3 -> v4 apply: schema 4, the backup is the schema-3 text, check clean' (($r.Code -eq 0) -and ((Run @('repo','info','--repo',$v3)).Out -match 'schema_version: 4') -and ($b3.Count -eq 1) -and ([IO.File]::ReadAllText($b3[0].FullName) -ceq [IO.File]::ReadAllText((Join-Path $fix 'golden_v3.txt'))) -and ((Run @('repo','check','--repo',$v3)).Out -match 'check: clean')) $r.Out
  $r = Run @('repo', 'migrate', '--repo', $v3, '--apply')
  Check 'B11 a second migrate says already at schema 4' (($r.Code -eq 0) -and ($r.Out -match 'already at schema 4')) $r.Out
  # ---- C: X2 unit tests (relation graph + path finder)
  $bat = Join-Path $Repo 'build\_build_fieldrepo_relgraph_tests_local.bat'
  $bin = Join-Path $Repo 'tests\fieldrepo\RelationGraphTests.exe'
  if (-not $SkipBuild) {
    $blog = Join-Path $work 'build-x2.log'
    Start-Process -FilePath cmd.exe -ArgumentList (('/c ' + [char]34 + [char]34 + $bat + [char]34 + ' > ' + [char]34 + $blog + [char]34 + ' 2>&1' + [char]34)) -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    Check 'C0 RelationGraphTests build' (($bl -match 'BUILD_EXITCODE=0') -and ($bl -notmatch '\[dcc\w*\] Error|: error | Error: ')) $blog
  }
  $log = Join-Path $work 'run-x2.log'
  & { $ErrorActionPreference = 'Continue'; & $bin *> $log }
  $code = $LASTEXITCODE
  Select-String -LiteralPath $log -Pattern '^FAIL' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
  $sum = Select-String -LiteralPath $log -Pattern '^SUMMARY ' | Select-Object -Last 1
  Check 'C1 RelationGraphTests SUMMARY fail=0' (($code -eq 0) -and $sum -and ($sum.Line -match 'fail=0\b')) ($sum.Line)

  # ---- D: repo paths
  $p = Join-Path $work 'p.dlrepo'
  $null = Run @('repo', 'restore', '--repo', $p, '--in', (Join-Path $fix 'xtable\xtable_paths_v4.txt'))
  $r = Run @('repo', 'paths', '--repo', $p, '--from', 'IPCHART', '--to', 'MSCLIST')
  Check 'D1 two paths IPCHART -> MSCLIST: listed with aliases MSCLIST / MSCLIST_2, ambiguous, exit 0' (($r.Code -eq 0) -and ($r.Out -match '\(depth 3\): 2 path\(s\)') -and ($r.Out -match '(?m)^  1 MSCLIST: IPCHART -\(FK_IPCHART_IINSP FK IINSPID=ID\)-> IINSP') -and ($r.Out -match '(?m)^  2 MSCLIST_2: IPCHART -\(FK_IPCHART_INSP ') -and ($r.Out -match 'choice: ambiguous')) "exit=$($r.Code)`n$($r.Out)"
  $r = Run @('repo', 'paths', '--repo', $p, '--from', 'IPCHART', '--to', 'INSPRSLT')
  Check 'D2 one path is taken: choice single' (($r.Code -eq 0) -and ($r.Out -match ': 1 path\(s\)') -and ($r.Out -match 'choice: single, path 1')) $r.Out
  $r = Run @('repo', 'paths', '--repo', $p, '--from', 'IPCHART', '--to', 'NOKEY')
  Check 'D3 an FK onto a parent with no key is no edge: 0 paths, exit 1' (($r.Code -eq 1) -and ($r.Out -match ': 0 path\(s\)') -and ($r.Out -match 'choice: none')) "exit=$($r.Code) $($r.Out)"
  $r = Run @('repo', 'paths', '--repo', $p, '--from', 'FOLDERS', '--to', 'OPTRLIST')
  Check 'D4 roles: the stored IS_DEFAULT (renamed FOLDERS_CLOSER) decides' (($r.Code -eq 0) -and ($r.Out -match 'FOLDERS_CLOSER FK CLOSEDBY=ID default') -and ($r.Out -match 'choice: default, path 2')) $r.Out
  $r = Run @('repo', 'paths', '--repo', $p, '--from', 'IPCHART', '--to', 'OPTRLIST')
  Check 'D5 a confirmed FORM relation is an edge (XQ6)' (($r.Code -eq 0) -and ($r.Out -match 'IPCHART_OPTRLIST FORM OPERID=ID')) $r.Out
  $r = Run @('repo', 'paths', '--repo', $p, '--from', 'IPCHART', '--to', 'MSCLIST', '--depth', '1')
  Check 'D6 depth limit: --depth 1 finds no 2-step path' (($r.Code -eq 1) -and ($r.Out -match '\(depth 1\): 0 path\(s\)')) "exit=$($r.Code) $($r.Out)"
  $r = Run @('repo', 'paths', '--repo', $p, '--from', 'IPCHART', '--to', 'MSCLIST', '--json')
  $j = $null; try { $j = ($r.Out -split "`n" | Where-Object { $_.StartsWith('{') }) | ConvertFrom-Json } catch { }
  Check 'D7 --json: paths with alias, path and steps; choice ambiguous, chosen 0' (($r.Code -eq 0) -and $j -and (@($j.paths).Count -eq 2) -and ($j.paths[1].alias -eq 'MSCLIST_2') -and ($j.paths[1].path -eq 'FK_IPCHART_INSP>FK_INSP_MSC') -and ($j.paths[1].steps[0].parent_key -eq 'PK_INSPRSLT') -and ($j.choice -eq 'ambiguous') -and ($j.chosen -eq 0)) $r.Out
  $r = Run @('repo', 'paths', '--repo', $p, '--stats')
  Check 'D8 --stats on the fixture: 7 edges, 2 not edges, depth 2 = 7 pairs / 2 ambiguous' (($r.Code -eq 0) -and ($r.Out -match 'relations=7 not-edges=2') -and ($r.Out -match 'depth 2: pairs 7, more than one path 2')) $r.Out
  $r = Run @('repo', 'paths', '--repo', $p, '--from', 'IPCHART')
  Check 'D9 usage: --from without --to exits 2' ($r.Code -eq 2) "exit=$($r.Code) $($r.Out)"
  $r = Run @('repo', 'paths', '--repo', $p, '--stats', '--depth', '0')
  Check 'D10 usage: --depth 0 exits 2' ($r.Code -eq 2) "exit=$($r.Code) $($r.Out)"

  # MICRONITEV6A (design 3.2 measured check): the draft's pairs 274 / 1,089 / 1,653; more than one path 10 / 332 /
  # 1,165 with the two-column key FK_PROBLEMS12 counted ONCE (the draft's 11 / 334 / 1,168 counted it per column).
  $orig = $V6aRepo
  if (-not $orig) {
    $fdb = [regex]::Match($V6aConnection, 'Database=([^;]+)').Groups[1].Value
    if ($fdb -and (Test-Path -LiteralPath $fdb)) {
      $orig = Join-Path $work 'v6a.dlrepo'
      $null = Run @('repo', 'init', '--repo', $orig)
      $s = Run @('repo', 'seed-fb', '--connection', $V6aConnection, '--repo', $orig, '--apply')
      if ($s.Code -ne 0) { $orig = '' }
    }
  }
  if (-not $orig) { Write-Host '[SKIP] D11 MICRONITEV6A counts: no -V6aRepo and the database is not reachable' -ForegroundColor Yellow }
  else {
    $before = (Get-Item -LiteralPath $orig) | ForEach-Object { "$($_.Length) $($_.LastWriteTimeUtc.Ticks)" }
    $copy = Join-Path $work 'v6a-copy.dlrepo'
    Copy-Item -LiteralPath $orig -Destination $copy
    $r = Run @('repo', 'paths', '--repo', $copy, '--stats')
    Check 'D11 MICRONITEV6A: 297 relations; pairs 274 / 1089 / 1653; more than one path 10 / 332 / 1165' (($r.Code -eq 0) -and ($r.Out -match 'relations=297 not-edges=0') -and ($r.Out -match 'depth 1: pairs 274, more than one path 10\b') -and ($r.Out -match 'depth 2: pairs 1089, more than one path 332\b') -and ($r.Out -match 'depth 3: pairs 1653, more than one path 1165\b')) $r.Out
    $after = (Get-Item -LiteralPath $orig) | ForEach-Object { "$($_.Length) $($_.LastWriteTimeUtc.Ticks)" }
    Check 'D12 the original repository is unchanged (size + mtime)' ($before -eq $after) "$before / $after"
  }
} catch { Write-Host "ABORT: $_" -ForegroundColor Red; $script:Failed = $true }
finally { try { [IO.Directory]::Delete($work, $true) } catch { $null = $_ } }
if ($script:Failed) { Write-Host 'V155 XTABLE: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'V155 XTABLE: PASS' -ForegroundColor Green; exit 0
