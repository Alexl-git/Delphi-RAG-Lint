<#
  run_v155_XTABLE.ps1 -- lane XTABLE slice X1 (1.55): cross-table fields, repository schema 4
  (design docs\superpowers\specs\2026-11-26-cross-table-fields-design.md section 2).
  Part A builds + runs tests\fieldrepo\CrossTableTests.dpr (schema 4, migrate 3 -> 4, #DLREPO 4, ALIAS.FIELD macros,
  dependency closure, repo check rules). Part B drives the engine: repo init (schema 4), restore of the clean fixture
  xtable_v4.txt checks clean, a planted copy names input-path-broken and input-alias-undeclared, a #DLREPO 3 file
  migrates to 4 (dry run changes no byte), the backup round trip is byte-identical.
  Run: pwsh -File tests\autotest\run_v155_XTABLE.ps1 [-Exe <drag-lint.exe>] [-SkipBuild]
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$SkipBuild)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
Write-Host '== v1.55 XTABLE: cross-table fields, schema 4 ==' -ForegroundColor Cyan
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
} catch { Write-Host "ABORT: $_" -ForegroundColor Red; $script:Failed = $true }
finally { try { [IO.Directory]::Delete($work, $true) } catch { $null = $_ } }
if ($script:Failed) { Write-Host 'V155 XTABLE: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'V155 XTABLE: PASS' -ForegroundColor Green; exit 0
