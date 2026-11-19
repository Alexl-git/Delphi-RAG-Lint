<#
  run_v152_GATE2_fixers.ps1 -- lane GATE2 (1.52): extract-method and create-enum-helper write through the compile
  gate BY DEFAULT, not only when --project is typed (E-COMPILEGATE-ADOPT-FIXERS).

  The project the gate builds: --project; else the database's own project (<dir>\_D-RAG\<base>.sqlite ->
  <dir>\<base>.dproj); else the nearest .dproj / .dpr, walking up from the edited unit's folder, that names the unit.
  No project found = REFUSED (no-project), exit 2, nothing written. --no-compile-gate writes unbuilt (the explicit
  opt-out, as for lint --fix).

  X1/X2/X3/X4 and E1/E2/E3/E5 are the RED on the 1.52 int tip (0a7ff9a55): there both verbs write unbuilt without
  --project. X5/X6/E4 are positive controls that pass on both engines.
  Needs dcc: SKIPs (exit 0) when rsvars.bat is missing.
#>
param(
  [string]$Exe    = '',
  [string]$Rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  ok   $Name" } else { $script:Failed = $true; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx  = (Resolve-Path "$PSScriptRoot\..\fixtures\refactor").Path
$Tmp = Join-Path $env:TEMP ('gate2_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null

function Tree-Hash([string]$Dir) {
  return (Get-ChildItem $Dir -Recurse -File | Where-Object { $_.Extension -notin '.sqlite', '.dcu', '.exe', '.rsm', '.map', '.drc', '.sqlite-wal', '.sqlite-shm', '.res', '.identcache', '.local', '.log', '.err', '.out' -and $_.FullName -notmatch '\\Win64\\|\\Win32\\|\\__history\\|\\__recovery\\' } |
      Sort-Object FullName | ForEach-Object { "$($_.Name)|$((Get-FileHash $_.FullName -Algorithm SHA1).Hash)" }) -join "`n"
}
# The narrowparam project plus Basic.pas (an extractable statement run and an enum TColor), listed in the .dpr.
#   Dirty  : NpRoot.pas does not compile (the baseline build fails).
#   Clash  : Basic.pas already declares the names the fixers create (Extracted, TColorHelper): the edit breaks the build.
#   DragDb : the DB lives at <dir>\_D-RAG\NarrowParam.sqlite (the database's own project).
function New-Fx([string]$Tag, [switch]$Dirty, [switch]$Clash, [switch]$DragDb) {
  $d = Join-Path $Tmp $Tag
  Copy-Item (Join-Path $Fx 'narrowparam') $d -Recurse
  $b = Join-Path $d 'Basic.pas'
  $t = [IO.File]::ReadAllText("$PSScriptRoot\..\refactor\extractmethod\Basic.pas") -replace "`r?`n", "`r`n"
  $iface = "type`r`n  TColor = (cRed, cGreen, cBlue);`r`n"
  if ($Clash) { $iface += "  TColorHelper = Integer;`r`nvar`r`n  Extracted: Integer;`r`n" }
  $t = $t.Replace("procedure P(a: Integer);`r`nimplementation", $iface + "procedure P(a: Integer);`r`nimplementation")
  [IO.File]::WriteAllText($b, $t, [Text.Encoding]::ASCII)
  $dpr = Join-Path $d 'NarrowParam.dpr'
  [IO.File]::WriteAllText($dpr, [IO.File]::ReadAllText($dpr).Replace("NpUse in 'NpUse.pas';", "NpUse in 'NpUse.pas',`r`n  Basic in 'Basic.pas';"), [Text.Encoding]::ASCII)
  if ($Dirty) { $np = Join-Path $d 'NpRoot.pas'; [IO.File]::WriteAllText($np, "this is not pascal`r`n" + [IO.File]::ReadAllText($np), [Text.Encoding]::ASCII) }
  $db = if ($DragDb) { [IO.Directory]::CreateDirectory((Join-Path $d '_D-RAG')) | Out-Null; Join-Path $d '_D-RAG\NarrowParam.sqlite' } else { Join-Path $d 'p.sqlite' }
  & { $ErrorActionPreference = 'Continue'; & $Exe index --project (Join-Path $d 'NarrowParam.dproj') --db $db --library-db none *> (Join-Path $Tmp "$Tag.index.log") }
  if ($LASTEXITCODE -ne 0) { throw "index $Tag exit $LASTEXITCODE" }
  $lines = $t -split "`r`n"
  $from = ([Array]::FindIndex($lines, [Predicate[string]] { param($l) $l -match 't := a \+ 1' })) + 1
  return @{ Dir = $d; Db = $db; Proj = (Join-Path $d 'NarrowParam.dproj'); Basic = $b; From = $from }
}
function Em($P) { return @('extract-method', '--file', $P.Basic, '--from-line', "$($P.From)", '--to-line', "$($P.From + 1)", '--name', 'Extracted', '--apply', '--rsvars', $Rsvars) }
function Run([string[]]$CliArgs) {
  $out = (& { $ErrorActionPreference = 'Continue'; & $Exe @CliArgs 2>&1 | ForEach-Object { "$_" } } | Out-String)
  return @{ Code = $LASTEXITCODE; Out = $out }
}
# Off the project: a .dproj / .dpr that no longer names Basic.pas, so no project builds it.
function Hide-Project($P) {
  foreach ($f in 'NarrowParam.dproj', 'NarrowParam.dpr') { [IO.File]::Move((Join-Path $P.Dir $f), (Join-Path $P.Dir "$f.off")) }
}

try {
  Write-Host 'extract-method'
  # X1: no --project, the unit's project does not build -> the gate refuses, nothing written
  $P = New-Fx 'x1' -Dirty
  $before = Tree-Hash $P.Dir
  $r = Run (@(Em $P))
  Write-Host ('  raw X1: exit {0}: {1}' -f $r.Code, (($r.Out.Trim() -split "`r?`n" | Select-Object -First 3) -join ' | '))
  Check 'X1 no --project, dirty project: exit 1, REFUSED (dirty-baseline), nothing written' (($r.Code -eq 1) -and ($r.Out -match 'REFUSED \(dirty-baseline\)') -and ((Tree-Hash $P.Dir) -ceq $before)) "exit $($r.Code); $($r.Out)"
  # X2: no --project, clean project -> gated write kept, the note names the project
  $P = New-Fx 'x2'
  $r = Run (@(Em $P))
  Check 'X2 no --project, clean project: exit 0, extracted, .BCK backup, note names NarrowParam.dproj' (($r.Code -eq 0) -and ([IO.File]::ReadAllText($P.Basic) -match 'procedure Extracted') -and (@(Get-ChildItem $P.Dir -Filter 'Basic.pas.BCK*').Count -ge 1) -and ($r.Out -match 'compile gate of NarrowParam\.dproj')) "exit $($r.Code); $($r.Out)"
  # X3: the extracted method's name is already declared -> after-build error -> rolled back
  $P = New-Fx 'x3' -Clash
  $before = Tree-Hash $P.Dir
  $r = Run (@(Em $P))
  Check 'X3 the fix breaks the build (E2004 in build 2): exit 1, rolled back, the source is byte-identical' (($r.Code -eq 1) -and ($r.Out -match 'E2004') -and ([IO.File]::ReadAllText($P.Basic) -notmatch 'procedure Extracted') -and ((Tree-Hash $P.Dir) -ceq $before)) "exit $($r.Code); $($r.Out)"
  # X4: no project names the unit -> REFUSED (no-project), exit 2, nothing written
  $P = New-Fx 'x4'
  Hide-Project $P
  $before = Tree-Hash $P.Dir
  $r = Run (@(Em $P))
  Check 'X4 no project builds the unit: exit 2, REFUSED (no-project), nothing written' (($r.Code -eq 2) -and ($r.Out -match 'REFUSED \(no-project\)') -and ($r.Out -match '--no-compile-gate') -and ((Tree-Hash $P.Dir) -ceq $before)) "exit $($r.Code); $($r.Out)"
  # X5: control -- --no-compile-gate writes unbuilt where X4 refused (a fresh copy: X4 must not depend on X5)
  $P = New-Fx 'x5'
  Hide-Project $P
  $r = Run ((@(Em $P)) + '--no-compile-gate')
  Check 'X5 control: --no-compile-gate writes unbuilt (exit 0, extracted)' (($r.Code -eq 0) -and ([IO.File]::ReadAllText($P.Basic) -match 'procedure Extracted')) "exit $($r.Code); $($r.Out)"
  # X6: control -- an explicit --project is still the gate (dirty -> refused)
  $P = New-Fx 'x6' -Dirty
  $r = Run ((@(Em $P)) + @('--project', $P.Proj))
  Check 'X6 control: explicit --project, dirty: exit 1, REFUSED (dirty-baseline)' (($r.Code -eq 1) -and ($r.Out -match 'REFUSED \(dirty-baseline\)')) "exit $($r.Code); $($r.Out)"

  Write-Host 'create-enum-helper'
  function Eh($P) { return @('create-enum-helper', '--qname', 'Basic.TColor', '--db', $P.Db, '--library-db', 'none', '--apply', '--rsvars', $Rsvars) }
  # E1: --db at <dir>\_D-RAG\NarrowParam.sqlite only, dirty project -> gated by the DB's project, refused
  $P = New-Fx 'e1' -Dirty -DragDb
  $before = Tree-Hash $P.Dir
  $r = Run (@(Eh $P))
  Write-Host ('  raw E1: exit {0}: {1}' -f $r.Code, (($r.Out.Trim() -split "`r?`n" | Select-Object -First 3) -join ' | '))
  Check 'E1 --db only (the DB''s project), dirty: exit 1, REFUSED (dirty-baseline), nothing written' (($r.Code -eq 1) -and ($r.Out -match 'REFUSED \(dirty-baseline\)') -and ((Tree-Hash $P.Dir) -ceq $before)) "exit $($r.Code); $($r.Out)"
  # E2: clean project, DB not under _D-RAG -> the project that names the unit gates it; written
  $P = New-Fx 'e2'
  $before = Tree-Hash $P.Dir
  $r = Run (@(Eh $P))
  Check 'E2 no --project, clean: exit 0, helper written, note names NarrowParam.dproj' (($r.Code -eq 0) -and ((Tree-Hash $P.Dir) -cne $before) -and ([IO.File]::ReadAllText($P.Basic) -match 'record helper for TColor') -and ($r.Out -match 'compile gate of NarrowParam\.dproj')) "exit $($r.Code); $($r.Out)"
  # E3: TColorHelper already declared -> the helper breaks the build -> rolled back
  $P = New-Fx 'e3' -Clash
  $before = Tree-Hash $P.Dir
  $r = Run (@(Eh $P))
  Check 'E3 the fix breaks the build (E2004 in build 2): exit 1, rolled back, the source is byte-identical' (($r.Code -eq 1) -and ($r.Out -match 'E2004') -and ((Tree-Hash $P.Dir) -ceq $before)) "exit $($r.Code); $($r.Out)"
  # E5: no project names the unit -> REFUSED (no-project), exit 2, nothing written
  $P = New-Fx 'e5'
  Hide-Project $P
  $before = Tree-Hash $P.Dir
  $r = Run (@(Eh $P))
  Check 'E5 no project builds the unit: exit 2, REFUSED (no-project), nothing written' (($r.Code -eq 2) -and ($r.Out -match 'REFUSED \(no-project\)') -and ((Tree-Hash $P.Dir) -ceq $before)) "exit $($r.Code); $($r.Out)"
  # E4: control -- --no-compile-gate writes unbuilt where E5 refused (a fresh copy)
  $P = New-Fx 'e4'
  Hide-Project $P
  $r = Run ((@(Eh $P)) + '--no-compile-gate')
  Check 'E4 control: --no-compile-gate writes unbuilt (exit 0, helper written)' (($r.Code -eq 0) -and ([IO.File]::ReadAllText($P.Basic) -match 'record helper for TColor')) "exit $($r.Code); $($r.Out)"
}
finally {
  Write-Host "scratch: $Tmp"
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS'
exit 0
