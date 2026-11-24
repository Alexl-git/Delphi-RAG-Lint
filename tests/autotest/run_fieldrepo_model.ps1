<#
  run_fieldrepo_model.ps1 -- FR-MODEL (1.53): the repository model v2 end to end.
  Part A builds + runs tests\fieldrepo\ModelTests.dpr (kinds/macros, migrate, exceptions, check, change set,
  layout events). Part B drives the engine: repo init -> restore model_kinds.txt -> repo check (exit 1, planted
  lines) -> repo backup (layout-event rows present) and migrate (dry run / apply / again) on a v1 file made by
  restoring golden.dlrepo.txt into a missing path.
  Run: pwsh -File tests\autotest\run_fieldrepo_model.ps1 [-Exe <drag-lint.exe>] [-SkipBuild]
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
Write-Host '== field repository model v2 ==' -ForegroundColor Cyan
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-repo-model-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
try {
  # ---- A: unit tests
  $bat = Join-Path $Repo 'build\_build_fieldrepo_model_tests_local.bat'
  $bin = Join-Path $Repo 'tests\fieldrepo\ModelTests.exe'
  if (-not $SkipBuild) {
    $blog = Join-Path $work 'build.log'
    Start-Process -FilePath cmd.exe -ArgumentList (('/c ' + [char]34 + [char]34 + $bat + [char]34 + ' > ' + [char]34 + $blog + [char]34 + ' 2>&1' + [char]34)) -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    Check 'A0 ModelTests build' (($bl -match 'BUILD_EXITCODE=0') -and ($bl -notmatch '\[dcc\w*\] Error|: error ')) $blog
  }
  $log = Join-Path $work 'run.log'
  & { $ErrorActionPreference = 'Continue'; & $bin *> $log }
  $code = $LASTEXITCODE
  Select-String -LiteralPath $log -Pattern '^FAIL' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
  $sum = Select-String -LiteralPath $log -Pattern '^SUMMARY ' | Select-Object -Last 1
  Check 'A1 ModelTests SUMMARY fail=0' (($code -eq 0) -and $sum -and ($sum.Line -match 'fail=0\b')) ($sum.Line)

  # ---- B: engine
  if (-not (Test-Path -LiteralPath $Exe)) { Check 'B0 engine exe exists' $false $Exe; throw 'no exe' }
  function Run([string[]]$a) {
    $o = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } }
    $out = ($o | ForEach-Object { "$_" }) -join "`n"
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
  }
  $fix = Join-Path $Repo 'tests\fixtures\fieldrepo'
  $x = Join-Path $work 'x.dlrepo'
  $r = Run @('repo', 'init', '--repo', $x)
  Check 'B1 repo init creates a schema-3 file' (($r.Code -eq 0) -and ((Run @('repo','info','--repo',$x)).Out -match 'schema_version: 3') -and ((Run @('repo','info','--repo',$x)).Out -match 'DL_LAYOUT_EVENTS: 0 rows') -and ((Run @('repo','info','--repo',$x)).Out -match 'DL_GRID_COLUMNS: 0 rows')) $r.Out
  $r = Run @('repo', 'restore', '--repo', $x, '--in', (Join-Path $fix 'model_kinds.txt'))
  Check 'B2 restore model_kinds.txt' ($r.Code -eq 0) $r.Out
  $r = Run @('repo', 'check', '--repo', $x)
  Check 'B3 repo check exits 1 with the planted lines' (($r.Code -eq 1) -and ($r.Out -match 'kind-flag-mismatch ORDERS.BADFLAG') -and ($r.Out -match 'CYC_A -> CYC_B -> CYC_A') -and ($r.Out -match 'WARN lookup-key-not-pk') -and ($r.Out -match 'layout-event-unknown-field') -and ($r.Out -match 'check: 6 findings \(5 errors, 1 warnings\)')) "exit=$($r.Code)`n$($r.Out)"
  $r = Run @('repo', 'check', '--repo', $x, '--json')
  $j = $null; try { $j = $r.Out | ConvertFrom-Json | ForEach-Object { $_ } } catch { }
  Check 'B3b repo check --json is valid, 6 findings' (($r.Code -eq 1) -and $j -and ($j.findings.Count -eq 6) -and ($j.warnings -eq 1)) "exit=$($r.Code)"
  $bk = Join-Path $work 'x.txt'
  $r = Run @('repo', 'backup', '--repo', $x, '--output', $bk)
  $txt = [IO.File]::ReadAllText($bk)
  Check 'B4 repo backup carries the layout-event rows and the exception' (($r.Code -eq 0) -and $txt.StartsWith('#DLREPO 3') -and $txt.Contains('[DL_LAYOUT_EVENTS ORDERS|PIC|TcxGridDBBandedTableView|OnCustomDrawCell]') -and $txt.Contains('[DL_EXCEPTIONS r1||ORDERS|PIC|DisplayWidth]')) "exit=$($r.Code)"

  # migrate on a v1 file
  $v1 = Join-Path $work 'v1.dlrepo'
  $r = Run @('repo', 'restore', '--repo', $v1, '--in', (Join-Path $fix 'golden.dlrepo.txt'))
  Check 'B5 restore of a #DLREPO 1 backup into a missing file creates a schema-1 file' (($r.Code -eq 0) -and ((Run @('repo','info','--repo',$v1)).Out -match 'schema_version: 1')) $r.Out
  $h1 = (Get-FileHash -LiteralPath $v1).Hash
  $r = Run @('repo', 'migrate', '--repo', $v1)
  Check 'B6 migrate dry run prints the plan and changes no byte' (($r.Code -eq 0) -and ($r.Out -match 'v1 -> v3: add DL_FIELDS_INFO.CALC_BODY, DOMAIN_NAME, CHAR_LENGTH, ONGETTEXT_BODY, ONSETTEXT_BODY, ONVALIDATE_BODY, ONCHANGE_BODY, GRID_DISPLAYTEXT_BODY, GRID_DRAWCELL_BODY, create DL_LAYOUT_EVENTS, DL_EXCEPTIONS, DL_DOMAINS, DL_CONSTRAINTS, DL_CONSTRAINT_COLUMNS, DL_GENERATORS, DL_GRID_COLUMNS, FIELD_KIND 2 for 0 ISCALCULATED rows, ALIGNMENT -2 to NULL in 0 rows, user_version 3') -and ($h1 -eq (Get-FileHash -LiteralPath $v1).Hash)) $r.Out
  $r = Run @('repo', 'restore', '--repo', $v1, '--in', (Join-Path $fix 'golden_v2.txt'), '--replace')
  Check 'B7 a #DLREPO 2 backup into a schema-1 file is refused (exit 2, migrate first)' (($r.Code -eq 2) -and ($r.Out -match 'migrate first')) "exit=$($r.Code) $($r.Out)"
  $r = Run @('repo', 'migrate', '--repo', $v1, '--apply')
  Check 'B8 migrate --apply writes the before-migrate backup and reaches schema 3' (($r.Code -eq 0) -and ($r.Out -match 'before-migrate backup: ') -and ((Run @('repo','info','--repo',$v1)).Out -match 'schema_version: 3') -and (@(Get-ChildItem $work -Filter 'v1.dlrepo.before-migrate-*.txt').Count -eq 1)) $r.Out
  $r = Run @('repo', 'migrate', '--repo', $v1, '--apply')
  Check 'B9 a second migrate says already at schema 3' (($r.Code -eq 0) -and ($r.Out -match 'already at schema 3')) $r.Out
  $r = Run @('repo', 'check', '--repo', $v1)
  Check 'B10 positive control: the migrated golden checks clean (exit 0, no kind mismatch)' (($r.Code -eq 0) -and ($r.Out -match 'check: clean')) "exit=$($r.Code) $($r.Out)"
  $r = Run @('repo', 'restore', '--repo', (Join-Path $work 'new2.dlrepo'), '--in', (Join-Path $fix 'golden_v2.txt'))
  Check 'B11 restore of a #DLREPO 2 backup into a missing file creates schema 2' (($r.Code -eq 0) -and ((Run @('repo','info','--repo',(Join-Path $work 'new2.dlrepo'))).Out -match 'schema_version: 2')) $r.Out
  # schema 2 -> 3
  $n2 = Join-Path $work 'new2.dlrepo'
  $o2 = Join-Path $work 'new2.txt'
  $null = Run @('repo', 'backup', '--repo', $n2, '--output', $o2)
  Check 'B13 a schema-2 file still backs up as #DLREPO 2, byte for byte' ([IO.File]::ReadAllText($o2) -ceq [IO.File]::ReadAllText((Join-Path $fix 'golden_v2.txt')))
  $h2 = (Get-FileHash -LiteralPath $n2).Hash
  $r = Run @('repo', 'migrate', '--repo', $n2)
  Check 'B14 v2 -> v3 dry run: plan, no byte changed' (($r.Code -eq 0) -and ($r.Out -match 'v2 -> v3: add DL_FIELDS_INFO\.ONGETTEXT_BODY, .* create DL_GRID_COLUMNS, ALIGNMENT -2 to NULL in 0 rows, move 0 Field events into columns, user_version 3') -and ($h2 -eq (Get-FileHash -LiteralPath $n2).Hash)) $r.Out
  $r = Run @('repo', 'migrate', '--repo', $n2, '--apply')
  $b2 = @(Get-ChildItem $work -Filter 'new2.dlrepo.before-migrate-*.txt')
  Check 'B15 v2 -> v3 apply: schema 3, the backup is the schema-2 text' (($r.Code -eq 0) -and ((Run @('repo','info','--repo',$n2)).Out -match 'schema_version: 3') -and ($b2.Count -eq 1) -and ([IO.File]::ReadAllText($b2[0].FullName) -ceq [IO.File]::ReadAllText((Join-Path $fix 'golden_v2.txt')))) $r.Out
  $r = Run @('repo', 'restore', '--repo', (Join-Path $work 'new3.dlrepo'), '--in', (Join-Path $fix 'golden_v3.txt'))
  Check 'B16 restore of a #DLREPO 3 backup into a missing file creates schema 3' (($r.Code -eq 0) -and ((Run @('repo','info','--repo',(Join-Path $work 'new3.dlrepo'))).Out -match 'schema_version: 3') -and ((Run @('repo','check','--repo',(Join-Path $work 'new3.dlrepo'))).Out -match 'check: clean')) $r.Out
  $r = Run @('repo', 'bogus', '--repo', $x)
  Check 'B12 the unknown-sub-verb message lists migrate and check' (($r.Code -eq 1) -and ($r.Out -match 'migrate, check')) $r.Out
} catch { Write-Host "ABORT: $_" -ForegroundColor Red; $script:Failed = $true }
finally { try { [IO.Directory]::Delete($work, $true) } catch { $null = $_ } }
if ($script:Failed) { Write-Host 'FIELDREPO MODEL: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'FIELDREPO MODEL: PASS' -ForegroundColor Green; exit 0