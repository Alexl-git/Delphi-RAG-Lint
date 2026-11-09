<#
run_autocreate_project_db.ps1 -- a verb that needs a project's index builds it on first use
(1.44 C8, owner override 2026-11-05), within the limits below.

THE RULE. `query --name X --project App.dpr` with no --db and no index at the project's
own path (<project dir>\_D-RAG\App.sqlite) builds it fresh, saying so on ONE stderr line.

THE LIMITS, each an arm:
  A  deployed engine layout (exe under ...\third_party\dll-win64\): the index is built, one NOTE
  B  --no-create: nothing is built
  C  a private engine copy (any other folder): nothing is built, even with --project
  D  no project known (no --project): nothing is built anywhere
  E  an explicit --db: that path is used as given, nothing is built at the _D-RAG path
  F  race: another creator holds <db>.creating exclusively -> this run builds nothing, does not hang
  G  resolve-dbs --project never builds (read-only)
  H  usages --in finds the project itself: built on a deployed engine, one NOTE
  I  usages --in --no-create: nothing built, the 'no index yet' error stands
  J  usages --in on a private copy: nothing built
  K,L  the servers (lsp, serve) never build, even given --project on a deployed engine
  M  a build that times out AFTER writing the DB file says the index is INCOMPLETE (148 IX)
POSITIVE CONTROL: arm A shows the fixture CAN be built, so the nothing-built arms are not vacuous.

Usage: pwsh -NoProfile -File tests\autotest\run_autocreate_project_db.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint-autocreate-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) {'PASS'} else {'FAIL'}
  $color  = if ($Ok) {'Green'} else {'Red'}
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { Write-Host "  [FAIL] engine not found: $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$exeDir = Split-Path -Parent $Exe
try {
  $deployed = "$WorkDir\root\third_party\dll-win64"
  $private  = "$WorkDir\private"
  foreach ($d in @($deployed, $private)) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    Copy-Item $Exe "$d\drag-lint.exe" -Force  # exe-freshness: absent
    Get-ChildItem -Path $exeDir -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName "$d\$($_.Name)" -Force }
    if (Test-Path "$exeDir\rules") { Copy-Item "$exeDir\rules" "$d\rules" -Recurse -Force }
    # an own, empty manifest: the shared one names real project databases
    Write-Ascii "$d\drag-lint.json" '{"indexes":{"outDir":"out","sections":[]}}'
  }
  $cwd = "$WorkDir\cwd"; New-Item -ItemType Directory -Path $cwd -Force | Out-Null

  function New-Proj([string]$Name) {
    $p = "$WorkDir\$Name"; New-Item -ItemType Directory -Path $p -Force | Out-Null
    Write-Ascii "$p\uA.pas" "unit uA;`r`n`r`ninterface`r`n`r`nprocedure FooMarker;`r`n`r`nimplementation`r`n`r`nprocedure FooMarker;`r`nbegin`r`nend;`r`n`r`nend.`r`n"
    Write-Ascii "$p\App.dpr" "program App;`r`n`r`nuses`r`n  uA in 'uA.pas';`r`n`r`nbegin`r`n  FooMarker;`r`nend.`r`n"
    return $p
  }
  function Invoke-Q([string]$EngineDir, [string[]]$A) {
    $o = "$WorkDir\o.txt"; $e = "$WorkDir\e.txt"
    $engine = "$EngineDir\drag-lint.exe"  # exe-freshness: absent
    $p = Start-Process -FilePath $engine -ArgumentList $A -NoNewWindow -Wait -PassThru -WorkingDirectory $cwd `
           -RedirectStandardOutput $o -RedirectStandardError $e
    [pscustomobject]@{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText($e) }
  }
  function Db([string]$Proj) { "$Proj\_D-RAG\App.sqlite" }

  # A -- deployed layout builds
  $pa = New-Proj 'pa'
  $ra = Invoke-Q $deployed @('query', '--name', 'FooMarker', '--project', "$pa\App.dpr")
  Check 'A: deployed engine -- the project index was built at _D-RAG\App.sqlite' (Test-Path (Db $pa)) ("stderr=" + $ra.Err.Trim())
  Check 'A: exactly one NOTE says so' (([regex]::Matches($ra.Err, 'building it now')).Count -eq 1) ("stderr=" + $ra.Err.Trim())
  Check 'A: the query then finds the symbol' ($ra.Out -match 'FooMarker') ("stdout=" + $ra.Out.Trim())

  # B -- --no-create
  $pb = New-Proj 'pb'
  $rb = Invoke-Q $deployed @('query', '--name', 'FooMarker', '--project', "$pb\App.dpr", '--no-create')
  Check 'B: --no-create -- nothing built' (-not (Test-Path (Db $pb))) ("stderr=" + $rb.Err.Trim())

  # C -- private engine copy
  $pc = New-Proj 'pc'
  $rc = Invoke-Q $private @('query', '--name', 'FooMarker', '--project', "$pc\App.dpr")
  Check 'C: private engine copy -- nothing built' (-not (Test-Path (Db $pc))) ("stderr=" + $rc.Err.Trim())

  # D -- no project known
  $pd = New-Proj 'pd'
  $null = Invoke-Q $deployed @('query', '--name', 'FooMarker')
  Check 'D: no --project -- nothing built' (-not (Test-Path (Db $pd)) -and -not (Test-Path "$cwd\_D-RAG")) ''

  # E -- explicit --db
  $pe = New-Proj 'pe'
  $null = Invoke-Q $deployed @('query', '--name', 'FooMarker', '--project', "$pe\App.dpr", '--db', "$WorkDir\nowhere.sqlite")
  Check 'E: explicit --db -- the _D-RAG index was not built' (-not (Test-Path (Db $pe))) ''

  # F -- race: a lock held by another creator
  $pf = New-Proj 'pf'
  New-Item -ItemType Directory -Path "$pf\_D-RAG" -Force | Out-Null
  $lock = [IO.File]::Open("$pf\_D-RAG\App.sqlite.creating", [IO.FileMode]::Create, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  try {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $rf = Invoke-Q $deployed @('query', '--name', 'FooMarker', '--project', "$pf\App.dpr")
    Check 'F: another creator holds the lock -- nothing built' (-not (Test-Path (Db $pf))) ("stderr=" + $rf.Err.Trim())
    Check 'F: ... and the run did not hang' ($sw.Elapsed.TotalSeconds -lt 60) ("took " + [int]$sw.Elapsed.TotalSeconds + " s")
  } finally { $lock.Dispose() }

  # G -- resolve-dbs stays read-only
  $pg = New-Proj 'pg'
  $null = Invoke-Q $deployed @('resolve-dbs', '--project', "$pg\App.dpr")
  Check 'G: resolve-dbs --project never builds' (-not (Test-Path (Db $pg))) ''

  # H -- usages --in finds its project by itself: the same rule
  $ph = New-Proj 'ph'
  $rh = Invoke-Q $deployed @('usages', '--name', 'FooMarker', '--in', "$ph\uA.pas")
  Check 'H: usages --in on a deployed engine -- the owner project index was built' (Test-Path (Db $ph)) ("stderr=" + $rh.Err.Trim())
  Check 'H: exactly one NOTE says so' (([regex]::Matches($rh.Err, 'building it now')).Count -eq 1) ("stderr=" + $rh.Err.Trim())
  Check 'H: the answer comes from that index, exit 0' (($rh.Exit -eq 0) -and ($rh.Err -match 'usages: project ')) ("exit=" + $rh.Exit + " stderr=" + $rh.Err.Trim())

  # I -- usages --in --no-create: nothing built, the old "Create it" error stands
  $pi_ = New-Proj 'pi'
  $ri = Invoke-Q $deployed @('usages', '--name', 'FooMarker', '--in', "$pi_\uA.pas", '--no-create')
  Check 'I: usages --in --no-create -- nothing built, says how' ((-not (Test-Path (Db $pi_))) -and ($ri.Exit -eq 2) -and ($ri.Err -match 'no index yet')) ("exit=" + $ri.Exit + " stderr=" + $ri.Err.Trim())

  # J -- usages --in on a private engine copy
  $pj = New-Proj 'pj'
  $rj = Invoke-Q $private @('usages', '--name', 'FooMarker', '--in', "$pj\uA.pas")
  Check 'J: usages --in on a private engine copy -- nothing built' ((-not (Test-Path (Db $pj))) -and ($rj.Err -match 'no index yet')) ("stderr=" + $rj.Err.Trim())

  # K, L -- the servers are read-only: they must never create, with a project and a deployed engine.
  # stdin at EOF ends the session right after the start-up DB resolution.
  [IO.File]::WriteAllText("$WorkDir\empty.txt", '')
  foreach ($verb in @(@('K', 'lsp'), @('L', 'serve'))) {
    $ps = New-Proj ('p' + $verb[1])
    $o = "$WorkDir\so.txt"; $e = "$WorkDir\se.txt"
    $engine = "$deployed\drag-lint.exe"  # exe-freshness: absent
    $sp = Start-Process -FilePath $engine -ArgumentList @($verb[1], '--project', "$ps\App.dpr") -NoNewWindow -PassThru -WorkingDirectory $cwd `
            -RedirectStandardInput "$WorkDir\empty.txt" -RedirectStandardOutput $o -RedirectStandardError $e
    if (-not $sp.WaitForExit(60000)) { $sp.Kill($true) }
    Check ($verb[0] + ': ' + $verb[1] + ' --project on a deployed engine -- nothing built') (-not (Test-Path (Db $ps))) ("stderr=" + [IO.File]::ReadAllText($e).Trim())
  }

  # M -- 148 IX (144 qsmall "auto-create on a large project"): a build that does not finish in time
  # (REINDEX_TIMEOUT_MS = 10 min; the drag-lint self-index takes ~13 min idle) is terminated after the
  # parse wrote the DB file. It used to say nothing more, because "building it failed" was printed only
  # when NO file existed: the run, and every later one, read a half-built index as if complete.
  # Seams: the child inherits DRAGLINT_TEST_RESOLVE_DELAY_MS (holds its calls stage) and the parent
  # waits DRAGLINT_TEST_REINDEX_TIMEOUT_MS.
  $pm = New-Proj 'pm'
  $env:DRAGLINT_TEST_RESOLVE_DELAY_MS = '60000'; $env:DRAGLINT_TEST_REINDEX_TIMEOUT_MS = '6000'
  try { $rm = Invoke-Q $deployed @('query', '--name', 'FooMarker', '--project', "$pm\App.dpr") }
  finally { foreach ($v in 'DRAGLINT_TEST_RESOLVE_DELAY_MS', 'DRAGLINT_TEST_REINDEX_TIMEOUT_MS') { [Environment]::SetEnvironmentVariable($v, $null) } }
  Check 'M0: precondition -- the timed-out child left a DB file' (Test-Path (Db $pm)) ("stderr=" + $rm.Err.Trim())
  Check 'M1: a timed-out build says the index is INCOMPLETE and how to finish it' ($rm.Err -match 'INCOMPLETE.*drag-lint index --project') ("stderr=" + $rm.Err.Trim())
  # M2 -- 149 IC 647ea3ae2: the timeout line names the wait it really made (the 6 s seam), not the
  # 600 s REINDEX_TIMEOUT_MS constant. M0 is the control: the timeout path really ran.
  Check 'M2: the timeout line names the elapsed wait (~6 s), not the 600 s constant' (($rm.Err -match 'did not finish within [5-9] s') -and ($rm.Err -notmatch 'within 600 s')) ("stderr=" + $rm.Err.Trim())
  # O -- 149 IC (148 IX row): the auto-create caller's failure line names ITS verb, not 'rename:'.
  Check 'O: the timed-out auto-create names its own verb, not rename:' (($rm.Err -match 'auto-create: reindex failed') -and ($rm.Err -notmatch 'rename: reindex failed')) ("stderr=" + $rm.Err.Trim())
  # N -- 149 IC (148 IX row): every LATER reader of the half-built index is told so, not only the run
  # that built it. N0 is the control: the complete index of arm A draws no such note.
  $rn0 = Invoke-Q $deployed @('query', '--name', 'FooMarker', '--project', "$pa\App.dpr")
  Check 'N0: control -- a completed index draws no INCOMPLETE note' ($rn0.Err -notmatch 'INCOMPLETE') ("stderr=" + $rn0.Err.Trim())
  $rn = Invoke-Q $deployed @('query', '--name', 'FooMarker', '--project', "$pm\App.dpr")
  Check 'N1: a later reader of the half-built index is told it is INCOMPLETE' ($rn.Err -match 'INCOMPLETE') ("stderr=" + $rn.Err.Trim())
} finally {
  if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "  (cleanup: $_)" } }
}
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
