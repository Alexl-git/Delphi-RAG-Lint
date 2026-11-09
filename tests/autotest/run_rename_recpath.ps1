<#
  run_rename_recpath.ps1 -- RF 150 (146 b1 residual): a record-constant field path off the library.

  A record constant whose field path walks off the project into a library record AND through an array level
  (`CWrap: TWrap = (Sh: (Pts: ((X: 1; Y: 2))))`, Sh: TLibShape, Pts: array of TLibPoint) leaves its leaf refs `X`/`Y` unbound with no
  type text (146 b1 "named-array record field path off the library"): renaming a project field X refused [receiver-untyped]. The field ref one
  step up the same path (`Pts`) IS bound to the library, so the proof knows the leaf is a library record's field and decides it "other".
  PLAN-ONLY: the library records exist in the stub library only (no real RTL record has this shape), nothing is compiled.

  POSITIVE CONTROLS: p1 the project's own TMine.X is still edited (const CMine), p2 the same shape off a type NO index holds (TNoSuchLib)
  stays refused [receiver-untyped].
  RED on the 1.49.0-alpha base build (lane RF): the two CWrap sites refuse.  Needs RAD Studio; SKIPs (exit 0) without it. Works under %TEMP%.

  Usage: pwsh -File tests\autotest\run_rename_recpathation.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-recpath-$PID",
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
$Fx   = Join-Path $Repo 'tests\fixtures\refactor\rename_recpath'
$Stub = Join-Path $Repo 'tests\fixtures\refactor\rename\libstub'
$Ascii = [Text.Encoding]::ASCII
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$script:N = 0

function Build-Lab([string]$Root) {
  $bat = "$Root.bld.bat"
  [IO.File]::WriteAllText($bat, "@echo off`r`ncall `"$RsVars`"`r`ncd /D `"$Root`"`r`nmsbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal RpRen.dproj`r`nexit /b %ERRORLEVEL%`r`n", $Ascii)
  $p = Start-Process cmd.exe -ArgumentList "/c `"$bat`"" -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$Root.bld.log" -RedirectStandardError "$Root.bld.err"
  return ($p.ExitCode -eq 0)
}
function Stdout-Of([string]$Root) {
  $x = Get-ChildItem $Root -Recurse -Filter RpRen.exe | Sort-Object LastWriteTime -Descending | Select-Object -First 1
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
    $pj = Join-Path $root 'RpRen.dproj'
    $x = [IO.File]::ReadAllText($pj, $Ascii).Replace('<DCCReference Include="RpUse.pas"/>', "<DCCReference Include=`"RpUse.pas`"/><DCCReference Include=`"$Extra`"/>")
    [IO.File]::WriteAllText($pj, $x, $Ascii)
  }
  $db = "$root.sqlite"
  Push-Location $WorkDir
  try { $null | & $Exe index --project (Join-Path $root 'RpRen.dproj') --db $db --library-db none *> "$db.log" } finally { Pop-Location }
  return @{ Root = $root; Dproj = (Join-Path $root 'RpRen.dproj'); Db = $db; Types = (Join-Path $root 'RpTypes.pas') }
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

# The miniature platform library (plan-only fixture: the stub is the only place the library records exist).
$libDir = Join-Path $WorkDir 'libsrc'
New-Item -ItemType Directory -Force $libDir | Out-Null
Copy-Item "$Fx\libsrc\*.pas" $libDir
$script:Lib = Join-Path $WorkDir 'lib.sqlite'
Push-Location $WorkDir; try { $null | & $Exe index $libDir --db $script:Lib --library-db none *> "$script:Lib.log" } finally { Pop-Location }

function New-RpLab {
  $root = Join-Path $WorkDir 'rp'
  New-Item -ItemType Directory -Force $root | Out-Null
  Copy-Item "$Fx\*.pas", "$Fx\*.dpr", "$Fx\*.dproj" $root
  $db = "$root.sqlite"
  Push-Location $WorkDir
  try { $null | & $Exe index --project (Join-Path $root 'RpRen.dproj') --db $db --library-db $script:Lib *> "$db.log" } finally { Pop-Location }
  return @{ Root = $root; Dproj = (Join-Path $root 'RpRen.dproj'); Db = $db; Types = (Join-Path $root 'RpTypes.pas') }
}
$p = New-RpLab
$pl = Plan $p 'RpTypes.TMine.X' 'Xx'
$cw = @($pl.Json.refusals | Where-Object { $_.why -cmatch '"TWrap\.' })
$cg = @($pl.Json.refusals | Where-Object { $_.why -cmatch '"TGhostWrap\.' })
Check 'plan ran (JSON)' ($pl.Exit -eq 0 -and $null -ne $pl.Json) $pl.Out
Check 'c1 the library-walk sites (CWrap X x2) are decided, not refused' ($cw.Count -eq 0) ($cw | Out-String)
Check 'p1 the project field itself is edited (decl + CMine)' (@($pl.Edits).Count -ge 2) ("edits=" + @($pl.Edits).Count)
Check 'p2 the same path off an unknown type stays refused [receiver-untyped]' ($cg.Count -ge 1 -and $cg[0].kind -eq 'receiver-untyped') ($cg | Out-String)
Check 'p2 nothing else is refused' (@($pl.Json.refusals).Count -eq $cg.Count) ($pl.Out)

if (-not $KeepWorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
Write-Host ("rename-recpath: {0} passed, {1} failed" -f $script:Passed, $script:FailCount)
if ($script:Failed) { exit 1 }