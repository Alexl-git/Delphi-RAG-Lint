<#
  run_cyclefix_f2047_baseline.ps1 -- W6 A4 (owner ruling 2026-10-25, "plan anyway"): the baseline gate of
  `cycles --fix` lets a run through when the baseline fails ONLY with `F2047 Circular unit reference`
  on a unit of the group being fixed (Part A); the build after the edit is then the only proof.

  Needs dcc: SKIPs (exit 0) when rsvars.bat is missing. Every project copy lives under %TEMP%.
  Fixture tests\fixtures\cyclefix\f2047clause: FaUnit <-> FbUnit both in the INTERFACE (F2047),
  IcUnit -> IdUnit (interface) with IdUnit -> IcUnit (implementation): a legal second group.
  (0) the raw baseline error line is printed first (inspect the shape before asserting on it).
  (a) `--unit faunit` dry run, no --no-compile: exit 0, baseline.status = f2047-in-group, verdict
      mechanical; the text run says `compile: baseline F2047 in this group`.
  (b) `--unit faunit --apply`: exit 0, no refusals, the sources changed, and the plan's own
      prediction held (no cycle left).
  CONTROLS (each refused today AND after, or must stay refused):
  (c) `--unit icunit` while the F2047 sits in the OTHER group: exit 1, a dirty-baseline refusal,
      no source written.
  (d) an unrelated E2003 masked behind the fatal (FzUnit): `--apply` rolls back with compile-error
      naming the E2003 line and the F2047 note; sources byte-identical.
  (e) a baseline with a NON-F2047 error beside the F2047 (an E2003 in FzUnit, compiled first):
      still the run-level dirty-baseline refusal (exit 1, refusals[0]).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-f2047-$PID",
  [string]$Rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
$ErrorActionPreference = 'Stop'; $script:Failed = $false; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fix = (Resolve-Path "$PSScriptRoot\..\fixtures\cyclefix\f2047clause").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
function Replace-Text([string]$Path, [string]$From, [string]$To) {
  $t = [IO.File]::ReadAllText($Path, [Text.Encoding]::ASCII)
  if (-not $t.Contains($From)) { throw "patch anchor not found in ${Path}: $From" }
  [IO.File]::WriteAllText($Path, $t.Replace($From, $To), [Text.Encoding]::ASCII)
}
function Get-SrcHash([string]$Dir) {
  return ((Get-ChildItem $Dir -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } | Sort-Object Name |
    ForEach-Object { '{0}={1}' -f $_.Name, (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ';')
}
function New-Proj([string]$Tag, [scriptblock]$Patch = $null) {
  $root = Join-Path $WorkDir $Tag
  New-Item -ItemType Directory $root | Out-Null
  Get-ChildItem $Fix -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) }
  if ($Patch) { & $Patch $root }
  $db = Join-Path $WorkDir "$Tag.sqlite"
  Push-Location $WorkDir
  try { $null | & $Exe index --project (Join-Path $root 'F2047Clause.dproj') --db $db --library-db none *> "$db.log" } finally { Pop-Location }
  return @{ Root = $root; Dproj = (Join-Path $root 'F2047Clause.dproj'); Db = $db }
}
function Run-Fix($P, [string[]]$Extra, [bool]$Json = $true) {
  $a = @('cycles', '--fix', '--project', $P.Dproj, '--db', $P.Db, '--library-db', 'none') + $Extra
  if ($Json) { $a += @('--format', 'json') }
  Push-Location $WorkDir
  try { $out = ($null | & $Exe @a 2>$null | Out-String); $code = $LASTEXITCODE } finally { Pop-Location }
  $j = $null; if ($Json) { try { $j = $out | ConvertFrom-Json } catch { } }
  return @{ Exit = $code; Out = $out; Json = $j }
}
function Kinds($r) {
  $k = @()
  foreach ($c in @($r.Json.cycles)) { foreach ($x in @($c.refusals)) { if ($x) { $k += $x.kind } } }
  foreach ($x in @($r.Json.refusals)) { if ($x) { $k += $x.kind } }
  return ,$k
}

$PBase = New-Proj 'base'
Check 'setup: fixture indexed' (Test-Path $PBase.Db) ''
# ---- (0) the raw shape
$r0 = Run-Fix $PBase @('--unit', 'ic', '--no-compile')
$raw = Run-Fix $PBase @('--unit', 'icunit')
Write-Host ("  raw baseline errors: " + (@($raw.Json.baseline.errors) -join ' || ')) -ForegroundColor DarkGray

Write-Host '== (a) dry run' -ForegroundColor Cyan
$sh = Join-Path $WorkDir 'a-shadow'
$a = Run-Fix $PBase @('--unit', 'faunit', '--shadow-out', $sh)
Check 'a: exit 0' ($a.Exit -eq 0) "exit=$($a.Exit) $($a.Out)"
Check 'a: baseline.status = f2047-in-group' ($a.Json.baseline.status -eq 'f2047-in-group') $a.Out
Check 'a: verdict mechanical' (@($a.Json.cycles)[0].verdict -eq 'mechanical') $a.Out
$at = Run-Fix $PBase @('--unit', 'faunit', '--shadow-out', (Join-Path $WorkDir 'a-shadow-txt')) $false
Check 'a: text run says the after-build is the only proof' ($at.Out -match '(?m)^compile: baseline F2047 in this group -- the build after the edit is the only proof') $at.Out

Write-Host '== (b) --apply' -ForegroundColor Cyan
$PApply = New-Proj 'apply'
$before = Get-SrcHash $PApply.Root
$b = Run-Fix $PApply @('--unit', 'faunit', '--apply')
Check 'b: exit 0' ($b.Exit -eq 0) "exit=$($b.Exit) $($b.Out)"
Check 'b: no refusal' ((Kinds $b).Count -eq 0) ((Kinds $b) -join ',')
Check 'b: the leaf was created and the sources changed' ((Test-Path (Join-Path $PApply.Root 'FaUnit.Untangle.pas')) -and ((Get-SrcHash $PApply.Root) -ne $before)) ''
Push-Location $WorkDir; try { $left = ($null | & $Exe cycles --db $PApply.Db --library-db none --f2047 | Out-String) } finally { Pop-Location }
Write-Host ('  cycles --f2047 after: ' + $left.Trim()) -ForegroundColor DarkGray
Check 'b: no F2047 group left after the edit' ($left -notmatch 'faunit') $left

Write-Host '== controls' -ForegroundColor Cyan
$c0 = Get-SrcHash $PBase.Root
$c = Run-Fix $PBase @('--unit', 'icunit')
Check 'c: F2047 in another group -> exit 1' ($c.Exit -eq 1) "exit=$($c.Exit) $($c.Out)"
Check 'c: a dirty-baseline refusal' ((Kinds $c) -contains 'dirty-baseline') ((Kinds $c) -join ',')
$c2 = Run-Fix $PBase @('--unit', 'icunit', '--apply')
Check 'c: --apply refused too, no source written' (($c2.Exit -eq 1) -and ((Get-SrcHash $PBase.Root) -eq $c0)) "exit=$($c2.Exit)"

$PMask = New-Proj 'masked' -Patch {
  param($r)
  [IO.File]::WriteAllText((Join-Path $r 'FzUnit.pas'), "unit FzUnit;`r`n`r`ninterface`r`n`r`nconst`r`n  FzValue = FzBogus;`r`n`r`nimplementation`r`n`r`nend.`r`n", [Text.Encoding]::ASCII)
  Replace-Text (Join-Path $r 'F2047Clause.dpr') "  IdUnit in 'IdUnit.pas';" "  IdUnit in 'IdUnit.pas',`r`n  FzUnit in 'FzUnit.pas';"
}
$m0 = Get-SrcHash $PMask.Root
$m = Run-Fix $PMask @('--unit', 'faunit', '--apply')
$mt = ($m.Out)
Check 'd: masked E2003 -> exit 1' ($m.Exit -eq 1) "exit=$($m.Exit) $mt"
Check 'd: compile-error naming the E2003 line and the F2047 note' ((Kinds $m) -contains 'compile-error' -and $mt -match 'E2003' -and $mt -match 'baseline already failed \(F2047\)') $mt
Check 'd: rolled back, sources byte-identical' ((Get-SrcHash $PMask.Root) -eq $m0) ''

$POther = New-Proj 'otherror' -Patch {
  param($r)
  [IO.File]::WriteAllText((Join-Path $r 'FzUnit.pas'), "unit FzUnit;`r`n`r`ninterface`r`n`r`nconst`r`n  FzValue = FzBogus;`r`n`r`nimplementation`r`n`r`nend.`r`n", [Text.Encoding]::ASCII)
  Replace-Text (Join-Path $r 'F2047Clause.dpr') "uses`r`n  FaUnit in 'FaUnit.pas',`r`n  FbUnit in 'FbUnit.pas',`r`n  IcUnit in 'IcUnit.pas',`r`n  IdUnit in 'IdUnit.pas';" "uses`r`n  FzUnit in 'FzUnit.pas',`r`n  FaUnit in 'FaUnit.pas',`r`n  FbUnit in 'FbUnit.pas',`r`n  IcUnit in 'IcUnit.pas',`r`n  IdUnit in 'IdUnit.pas';"
}
$e = Run-Fix $POther @('--unit', 'faunit')
Check 'e: a non-F2047 baseline error -> run-level dirty-baseline (exit 1)' (($e.Exit -eq 1) -and (@($e.Json.refusals)[0].kind -eq 'dirty-baseline') -and ($e.Json.baseline.status -eq 'error')) $e.Out

if ($script:Failed) { Write-Host "run_cyclefix_f2047_baseline: FAIL ($script:Passed passed)" -ForegroundColor Red; exit 1 }
Write-Host "run_cyclefix_f2047_baseline: PASS ($script:Passed checks)" -ForegroundColor Green; exit 0