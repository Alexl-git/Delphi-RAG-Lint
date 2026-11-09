<#
  run_rename_delegation.ps1 -- RF 150: `rename` follows an `implements` DELEGATION.

  `property Impl: TBare read FImpl implements IFoo` (TBare does NOT list IFoo): the compiler answers IFoo.Bar with TBare.Bar by
  name, so renaming IFoo.Bar must rename TBare.Bar too. Before this lane the dispatch group held only the interface method and
  TFull.Bar (a class that lists IFoo): the plan was clean and the rename broke the build. A delegate type that is not one
  project class declaring the name is refused ([implements-unindexed]).

  POSITIVE CONTROLS: c1 stdout is identical to the untouched build (the gate compiles TBare.Bar renamed), p1 the unrelated
  TOther.Bar stays, p2 a delegate property whose class lacks the member is refused (without the fix: clean plan).
  RED on the 1.49.0-alpha base build (lane RF): TBare.Bar not in the plan, no refusal.
  Needs RAD Studio; SKIPs (exit 0) without it. Works under %TEMP%.

  Usage: pwsh -File tests\autotest\run_rename_delegation.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-deleg-$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0; $script:FailCount = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:FailCount++; if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $RsVars)) { Write-Host "SKIP: no rsvars.bat ($RsVars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fx   = Join-Path $Repo 'tests\fixtures\refactor\rename_deleg'
$Stub = Join-Path $Repo 'tests\fixtures\refactor\rename\libstub'
$Ascii = [Text.Encoding]::ASCII
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$script:N = 0

function Build-Lab([string]$Root) {
  $bat = "$Root.bld.bat"
  [IO.File]::WriteAllText($bat, "@echo off`r`ncall `"$RsVars`"`r`ncd /D `"$Root`"`r`nmsbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal DelRen.dproj`r`nexit /b %ERRORLEVEL%`r`n", $Ascii)
  $p = Start-Process cmd.exe -ArgumentList "/c `"$bat`"" -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$Root.bld.log" -RedirectStandardError "$Root.bld.err"
  return ($p.ExitCode -eq 0)
}
function Stdout-Of([string]$Root) {
  $x = Get-ChildItem $Root -Recurse -Filter DelRen.exe | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $x) { return '<no exe>' }
  return (& $x.FullName 2>&1 | Out-String)
}
function New-Lab([string]$Extra = '') {
  $script:N++
  $root = Join-Path $WorkDir ("p{0}" -f $script:N)
  New-Item -ItemType Directory -Force $root | Out-Null
  Copy-Item "$Fx\*.pas", "$Fx\*.dpr", "$Fx\*.dproj" $root
  if ($Extra) {
    # an unbuilt extra unit: indexed through the project, never compiled
    Copy-Item (Join-Path $Fx "extra\$Extra") $root
    $pj = Join-Path $root 'DelRen.dproj'
    $x = [IO.File]::ReadAllText($pj, $Ascii).Replace('<DCCReference Include="DelUse.pas"/>', "<DCCReference Include=`"DelUse.pas`"/><DCCReference Include=`"$Extra`"/>")
    [IO.File]::WriteAllText($pj, $x, $Ascii)
  }
  $db = "$root.sqlite"
  Push-Location $WorkDir
  try { $null | & $Exe index --project (Join-Path $root 'DelRen.dproj') --db $db --library-db none *> "$db.log" } finally { Pop-Location }
  return @{ Root = $root; Dproj = (Join-Path $root 'DelRen.dproj'); Db = $db; Types = (Join-Path $root 'DelTypes.pas') }
}
function Plan($P, [string]$Q, [string]$To) {
  Push-Location $WorkDir
  try { $o = ($null | & $Exe rename --kind symbol --name $Q --to $To --db $P.Db --library-db $script:Lib --plan --json 2>$null | Out-String); $c = $LASTEXITCODE } finally { Pop-Location }
  $j = $null; try { $j = $o | ConvertFrom-Json } catch { }
  return @{ Exit = $c; Json = $j; Out = $o; Kinds = @($j.refusals | ForEach-Object { $_.kind }); Edits = @($j.edits) }
}
function Apply($P, [string]$Q, [string]$To) {
  Push-Location $WorkDir
  try { $o = ($null | & $Exe rename --kind symbol --name $Q --to $To --db $P.Db --library-db $script:Lib --project $P.Dproj --build-timeout 600 --apply --no-backup 2>&1 | Out-String); $c = $LASTEXITCODE } finally { Pop-Location }
  return @{ Exit = $c; Out = $o }
}
function Text-Of([string]$Path) { return [IO.File]::ReadAllText($Path, $Ascii) }

$libDir = Join-Path $WorkDir 'libsrc'
New-Item -ItemType Directory -Force $libDir | Out-Null
Copy-Item "$Stub\LibStub.pas" $libDir
$script:Lib = Join-Path $WorkDir 'lib.sqlite'
Push-Location $WorkDir; try { $null | & $Exe index $libDir --db $script:Lib --library-db none *> "$script:Lib.log" } finally { Pop-Location }
$base = New-Lab
Check 'fixture compiles untouched' (Build-Lab $base.Root) (Get-Content "$($base.Root).bld.log" -Tail 8 | Out-String)
$Expected = Stdout-Of $base.Root
Check 'fixture prints' ($Expected -match 'bare bar' -and $Expected -match 'full bar')

Write-Host '--- c1 IFoo.Bar through the delegation'
$p = New-Lab
$pl = Plan $p 'DelTypes.IFoo.Bar' 'Baz'
Check 'c1 plan: no refusal' ($pl.Exit -eq 0 -and $pl.Json -and @($pl.Json.refusals).Count -eq 0) $pl.Out
Check 'c1 plan: the delegate class member is in the group' (@($pl.Json.group) -contains 'DelTypes.TBare.Bar') ($pl.Json.group -join ',')
$a = Apply $p 'DelTypes.IFoo.Bar' 'Baz'
Check 'c1 apply: through the gate, exit 0' ($a.Exit -eq 0 -and $a.Out -match 'compile gate') $a.Out
Check 'c1 stdout identical to the untouched build' ((Stdout-Of $p.Root) -ceq $Expected) (Stdout-Of $p.Root)
$t = Text-Of $p.Types
Check 'c1 TBare.Bar renamed (declaration and implementation)' ($t.Contains('procedure Baz;') -and $t.Contains('procedure TBare.Baz;') -and -not $t.Contains('procedure TBare.Bar;'))

Write-Host '--- p1 an unrelated Bar stays'
$p = New-Lab 'DelOther.pas'
$pl = Plan $p 'DelTypes.IFoo.Bar' 'Baz'
Check 'p1 plan: no refusal' ($pl.Exit -eq 0 -and @($pl.Json.refusals).Count -eq 0) $pl.Out
Check 'p1 plan: TOther.Bar is not in the group' (-not (@($pl.Json.group) -contains 'DelOther.TOther.Bar')) ($pl.Json.group -join ',')

Write-Host '--- p2 a delegate class that lacks the member is refused'
$p = New-Lab 'DelMiss.pas'
$pl = Plan $p 'DelTypes.IFoo.Bar' 'Baz'
Check 'p2 plan names [implements-unindexed]' ($pl.Exit -eq 0 -and $pl.Kinds -contains 'implements-unindexed') $pl.Out

if (-not $KeepWorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
Write-Host ("rename-delegation: {0} passed, {1} failed" -f $script:Passed, $script:FailCount)
if ($script:Failed) { exit 1 }