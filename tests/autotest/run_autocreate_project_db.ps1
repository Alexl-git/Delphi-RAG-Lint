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
    Copy-Item $Exe "$d\drag-lint.exe" -Force
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
    $p = Start-Process -FilePath "$EngineDir\drag-lint.exe" -ArgumentList $A -NoNewWindow -Wait -PassThru -WorkingDirectory $cwd `
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
} finally {
  if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "  (cleanup: $_)" } }
}
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
