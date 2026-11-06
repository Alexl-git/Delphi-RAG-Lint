<#
  run_usages_project_context.ps1 -- `usages --name X --in <file>` with no --db finds
  the unit's context (owner Q2, 2026-11-04, BACKLOG USAGES-PROJECT-CONTEXT).

  CHECKS
    A  project file in the folder, DB exists: answers from it, stderr names the project
    B  project file in an ancestor folder lists the unit: same
    C  project exists, no DB: exit 2, prints the exact index command, empty stdout
    D  two projects list the unit: exit 2, both named, nothing guessed
    E  no project, only library units: library DB answers, stderr says assumed platform
    F  no project, a non-library unit used: exit 2, names that unit, asks for the project
    G  POSITIVE CONTROL no --in, no --db: still exit 2
    H  POSITIVE CONTROL explicit --db beats all of it: exit 0, no context note
    I  a file that does not exist: exit 2
    J  library source under a project nobody indexed: the library answers
    K  a unit the library holds: what it uses is not questioned

  Usage: pwsh -File tests\autotest\run_usages_project_context.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
. (Join-Path $PSScriptRoot 'exe-hint.ps1')
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:fail = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ("draglint_usages_ctx-{0}" -f $PID)

function Put([string]$rel, [string]$text) {
  $p = Join-Path $scratch $rel
  [IO.Directory]::CreateDirectory((Split-Path $p)) | Out-Null
  [IO.File]::WriteAllText($p, ($text -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
  return $p
}
function UnitText([string]$name, [string]$uses = '') {
  $u = if ($uses) { "uses $uses;`n" } else { '' }
  return "unit $name;`ninterface`n${u}type`n  T$name = class end;`nimplementation`nend.`n"
}
function DprText([string]$name, [string]$units) { "program $name;`nuses $units;`nbegin`nend.`n" }
function Index([string]$proj, [string]$db) {
  $o = & $exePath index --project $proj --db $db 2>&1
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $db)) { Write-Host "FATAL: fixture $proj did not index: $($o | Select-Object -Last 2)" -ForegroundColor Red; Get-ExeStartFailureHint $LASTEXITCODE | Write-Host; exit 2 }
}
function Ask([string[]]$a) {
  $errFile = Join-Path $scratch 'stderr.txt'
  Push-Location $scratch
  $script:out = (& $exePath usages @a 2>$errFile) -join "`n"
  $script:code = $LASTEXITCODE
  Pop-Location
  $script:err = [IO.File]::ReadAllText($errFile)
}

# A: project beside the unit, indexed
$uA = Put 'a\uA.pas' (UnitText 'uA')
$pA = Put 'a\AppA.dpr' (DprText 'AppA' "uA in 'uA.pas'")
Index $pA (Join-Path $scratch 'a\_D-RAG\AppA.sqlite')
# B: project in an ancestor folder
$uB = Put 'b\src\uB.pas' (UnitText 'uB')
$pB = Put 'b\AppB.dpr' (DprText 'AppB' "uB in 'src\uB.pas'")
Index $pB (Join-Path $scratch 'b\_D-RAG\AppB.sqlite')
# C: project with no index
$uC = Put 'c\uC.pas' (UnitText 'uC')
$pC = Put 'c\AppC.dpr' (DprText 'AppC' "uC in 'uC.pas'")
# D: a unit two projects list
$uD = Put 'd\uD.pas' (UnitText 'uD')
$pD1 = Put 'd\AppD1.dpr' (DprText 'AppD1' "uD in 'uD.pas'")
$pD2 = Put 'd\AppD2.dpr' (DprText 'AppD2' "uD in 'uD.pas'")
Index $pD1 (Join-Path $scratch 'd\_D-RAG\AppD1.sqlite')
Index $pD2 (Join-Path $scratch 'd\_D-RAG\AppD2.sqlite')
# E / F: no project; a library index holding LibBase
$uLibBase = Put 'lib\LibBase.pas' (UnitText 'LibBase')
$uLibIf = Put 'lib\LibIf.pas' (UnitText 'LibIf' 'uOtherPlatformOnly')
$pL = Put 'lib\LibHolder.dpr' (DprText 'LibHolder' "LibBase in 'LibBase.pas', LibIf in 'LibIf.pas'")
$libDb = Join-Path $scratch 'libindex\lib.sqlite'
[IO.Directory]::CreateDirectory((Split-Path $libDb)) | Out-Null
Index $pL $libDb
$uE = Put 'lone\uLone.pas' (UnitText 'uLone' 'LibBase')
$uF = Put 'lone2\uOrphan.pas' (UnitText 'uOrphan' 'LibBase, uMissing')

Ask @('--name', 'TuA', '--in', $uA)
Check 'A1 exit 0' ($code -eq 0) "exit=$code err=$err"
Check 'A2 answers from the project DB' ($out -match 'declarations: 1') "out=$out"
Check 'A3 stderr names the project and DB' (($err -match 'AppA\.dpr') -and ($err -match 'AppA\.sqlite')) "err=$err"

Ask @('--name', 'TuB', '--in', $uB)
Check 'B project in an ancestor folder' (($code -eq 0) -and ($out -match 'declarations: 1') -and ($err -match 'AppB\.dpr')) "exit=$code out=$out err=$err"

# --no-create: without it a deployed engine now builds the index (1.44 C8, run_autocreate_project_db arm H).
Ask @('--name', 'TuC', '--in', $uC, '--json', '--no-create')
Check 'C1 no DB: exit 2' ($code -eq 2) "exit=$code err=$err"
Check 'C2 prints the create command' (($err -match 'index --project') -and ($err -match 'AppC\.dpr') -and ($err -match '_D-RAG.AppC\.sqlite')) "err=$err"
Check 'C3 stdout stays empty (it is the document)' ($out -eq '') "out=$out"

Ask @('--name', 'TuD', '--in', $uD)
Check 'D1 two projects: exit 2' ($code -eq 2) "exit=$code"
Check 'D2 both named' (($err -match 'AppD1') -and ($err -match 'AppD2')) "err=$err"

Ask @('--name', 'TLibBase', '--in', $uE, '--library-db', $libDb)
Check 'E1 library unit: exit 0' ($code -eq 0) "exit=$code err=$err"
Check 'E2 library DB answers' ($out -match 'declarations: 1') "out=$out"
Check 'E3 stderr says library + assumed platform' (($err -match 'library unit') -and ($err -match 'assumed platform')) "err=$err"

Ask @('--name', 'TLibBase', '--in', $uF, '--library-db', $libDb)
Check 'F1 non-library use: exit 2' ($code -eq 2) "exit=$code"
Check 'F2 names the unit, not the library one' (($err -match 'uMissing') -and ($err -notmatch 'LibBase[,:]')) "err=$err"
Check 'F3 asks for the project' ($err -match 'project') "err=$err"

# The holder project plays the vendor's build project: it lists the unit, nobody indexed it.
Ask @('--name', 'TLibBase', '--in', $uLibBase, '--library-db', $libDb)
Check 'J library source under an unindexed project: library answers' (($code -eq 0) -and ($out -match 'declarations: 1') -and ($err -match 'library unit')) "exit=$code out=$out err=$err"
Ask @('--name', 'TLibIf', '--in', $uLibIf, '--library-db', $libDb)
Check 'K a unit the library holds is not asked about what it uses' (($code -eq 0) -and ($err -notmatch 'uOtherPlatformOnly')) "exit=$code err=$err"

Ask @('--name', 'TuA')
Check 'G no --in, no --db: exit 2' ($code -eq 2) "exit=$code"

Ask @('--name', 'TuA', '--db', (Join-Path $scratch 'a\_D-RAG\AppA.sqlite'), '--in', $uD)
Check 'H1 explicit --db wins' (($code -eq 0) -and ($out -match 'declarations: 1')) "exit=$code out=$out"
Check 'H2 no context note' ($err -notmatch 'AppD') "err=$err"

Ask @('--name', 'TuA', '--in', (Join-Path $scratch 'nope\uNope.pas'))
Check 'I missing file: exit 2' (($code -eq 2) -and ($err -match 'not found')) "exit=$code err=$err"

[IO.Directory]::Delete($scratch, $true)
if ($script:fail) { Write-Host 'run_usages_project_context: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_usages_project_context: PASS' -ForegroundColor Green
exit 0
