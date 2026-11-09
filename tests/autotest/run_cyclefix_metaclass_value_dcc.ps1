# run_cyclefix_metaclass_value_dcc.ps1 -- lane 150 CY2 (150-CY-7b, design + fixture) / lane 150 CY1 (the recipe): a class
# of the cycle passed as a VALUE (System.Classes.RegisterClass(TMvJob)) across the edge mvapp -> mvjob, neither class
# movable. Design: docs\superpowers\specs\2026-11-09-cy-7b-metaclass-value.md. The METACLASS HAND-OVER cuts it: the leaf
# MvJob.Untangle declares `MvJobClass: TPersistentClass` (the formal type of RegisterClass's parameter, read from the
# platform library), MvJob's initialization assigns `MvJobClass := TMvJob;`, MvApp passes MvJobClass.
#
#   m0  the untouched fixture builds (real msbuild) and prints `[mv] TMvJob`      (the fixture is valid Delphi)
#   m1  `cycles` finds the 2-unit group mvjob <-> mvapp
#   m2  plan: `mvapp -> mvjob` is cut by **metaclass hand-over** (MvJobClass: TPersistentClass in MvJob.Untangle)
#   m3  --fix --apply: exit 0; MvApp passes MvJobClass; the applied copy builds; stdout byte-identical; no cycle
#       (RED on 1.49.0-alpha base: m2 / m3 refuse -- the value use was refused base-class)
#   k1  control (CY2): without the value use the plan cuts an edge and names no MvApp.pas:20 refusal
#   k2  refused: the value is passed in MvApp's INITIALIZATION section (runs before MvJob's may have assigned the
#       variable): init-order, no metaclass hand-over
#   pc1 positive control: the applied tree with the assignment `MvJobClass := TMvJob;` removed still compiles and its
#       stdout DIFFERS (the stdout compare has teeth)
## Usage: pwsh -File run_cyclefix_metaclass_value_dcc.ps1 [-Exe <drag-lint.exe>] [-WorkDir <dir>] [-KeepWorkDir]
param(
  [string]$Exe     = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe") { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" } else { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }),
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-metaclassvalue-$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $RsVars)) { Write-Host "SKIP: no rsvars.bat ($RsVars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library DB at $LibraryDb" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Ascii = [Text.Encoding]::ASCII
$Name  = 'MetaclassValue'
$script:N = 0

function Edit-Text([string]$Path, [string]$From, [string]$To) {
  $t = [IO.File]::ReadAllText($Path, $Ascii)
  $f = $From -replace "`r?`n", "`r`n"
  if (-not $t.Contains($f)) { throw "patch anchor not found in ${Path}: $From" }
  [IO.File]::WriteAllText($Path, $t.Replace($f, ($To -replace "`r?`n", "`r`n")), $Ascii)
}
function Get-SrcHash([string]$Dir) {
  return ((Get-ChildItem $Dir -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } | Sort-Object Name |
    ForEach-Object { '{0}={1}' -f $_.Name, (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ';')
}
# A private copy of the fixture, patched, indexed (the platform library as the engine's config names it).
function New-Proj([scriptblock]$Patch = $null) {
  $script:N++
  $root = Join-Path $WorkDir ("p{0}" -f $script:N)
  New-Item -ItemType Directory -Force $root | Out-Null
  Get-ChildItem (Join-Path $Repo 'tests\fixtures\cyclefix\metaclassvalue') -File |
    Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) }
  if ($Patch) { & $Patch $root }
  $db = "$root.sqlite"
  Push-Location $WorkDir
  try { $null | & $Exe index --project (Join-Path $root "$Name.dproj") --db $db *> "$db.log" } finally { Pop-Location }
  return @{ Root = $root; Dproj = (Join-Path $root "$Name.dproj"); Db = $db }
}
function Invoke-Cli($P, [string[]]$CliArgs) {
  Push-Location $WorkDir
  try { $out = ($null | & $Exe @CliArgs 2>$null | Out-String); $code = $LASTEXITCODE } finally { Pop-Location }
  return @{ Out = $out; Exit = $code }
}
function Invoke-Build($P) {
  $bat = "$($P.Root).build.bat"; $log = "$bat.log"
  $lines = @('@echo off', ('call "{0}"' -f $RsVars), ('cd /d "{0}"' -f $P.Root),
    ('msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal "{0}" > "{1}" 2>&1' -f $P.Dproj, $log),
    ('>> "{0}" echo BUILD_EXITCODE=%ERRORLEVEL%' -f $log))
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), $Ascii)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -NoNewWindow -Wait | Out-Null
  $text = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
  $errors = @([regex]::Matches($text, '(?m)^.*\b(error|fatal) [EF]\d{4}\b.*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
  return @{ Ok = ($text -match 'BUILD_EXITCODE=0') -and ($errors.Count -eq 0); Errors = ($errors -join ' | ') }
}
function Invoke-Program($P) {
  $exeP = Join-Path $P.Root "Win64\Debug\$Name.exe"
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [IO.File]::ReadAllText($o, $Ascii)
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  Write-Host '== m: the metaclass hand-over' -ForegroundColor Cyan
  $B = New-Proj
  $b0 = Invoke-Build $B
  Check 'm0.1 the untouched fixture builds' $b0.Ok $b0.Errors
  $out0 = Invoke-Program $B
  Check 'm0.2 it prints [mv] TMvJob' ($out0 -match '\[mv\] TMvJob') $out0

  $P = New-Proj
  $c = Invoke-Cli $P @('cycles', '--db', $P.Db)
  Check 'm1 cycles finds mvjob <-> mvapp' ($c.Out -match '\[2 units\] (mvjob <-> mvapp|mvapp <-> mvjob)') $c.Out
  $plan = (Invoke-Cli $P @('cycles', '--plan', '--db', $P.Db, '--library-db', $LibraryDb)).Out
  Check 'm2.1 the plan cuts mvapp -> mvjob by metaclass hand-over' (($plan -match 'Cut the edge `mvapp -> mvjob` by \*\*metaclass hand-over\*\*') -and ($plan -notmatch 'refused: edge-still-used')) $plan
  Check 'm2.2 the leaf declares MvJobClass: TPersistentClass and uses System.Classes' (($plan -match '(?m)^  MvJobClass: TPersistentClass;') -and ($plan -match '(?s)unit MvJob\.Untangle;.*uses\s+System\.Classes;')) $plan
  $f = Invoke-Cli $P @('cycles', '--fix', '--apply', '--no-backup', '--build-timeout', '1800', '--project', $P.Dproj, '--db', $P.Db, '--library-db', $LibraryDb)
  Check 'm3.1 --fix --apply: exit 0 (the dcc gate passed)' ($f.Exit -eq 0) "exit=$($f.Exit) $($f.Out)"
  $app = [IO.File]::ReadAllText((Join-Path $P.Root 'MvApp.pas'), $Ascii)
  Check 'm3.2 MvApp passes MvJobClass and no longer uses MvJob' (($app -match 'RegisterClass\(MvJobClass\);') -and ($app -notmatch '(?m)\bMvJob;')) $app
  $b1 = Invoke-Build $P
  Check 'm3.3 the applied copy builds (independent msbuild)' $b1.Ok $b1.Errors
  $out1 = Invoke-Program $P
  Check 'm3.4 stdout byte-identical to the untouched build' (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) "before=[$out0] after=[$out1]"
  $null = Invoke-Cli $P @('index', '--project', $P.Dproj, '--db', $P.Db, '--library-db', $LibraryDb)
  $c1 = Invoke-Cli $P @('cycles', '--db', $P.Db)
  Check 'm3.5 no cycle after a re-index' ($c1.Out -match 'No circular unit dependencies found\.') $c1.Out

  Write-Host '== pc1: the assignment removed' -ForegroundColor Cyan
  Edit-Text (Join-Path $P.Root 'MvJob.pas') "  MvJobClass := TMvJob;`n" ''
  $bc = Invoke-Build $P
  Check 'pc1a it still compiles' $bc.Ok $bc.Errors
  $outC = Invoke-Program $P
  Check 'pc1b its stdout DIFFERS (the compare has teeth)' (($outC -ne '<no exe>') -and ($outC -cne $out0)) "after=[$outC]"

  Write-Host '== k: controls' -ForegroundColor Cyan
  $K = New-Proj { param($r) Edit-Text (Join-Path $r 'MvApp.pas') "  RegisterClass(TMvJob);`n" '' }
  $kp = (Invoke-Cli $K @('cycles', '--plan', '--db', $K.Db, '--library-db', $LibraryDb)).Out
  Check 'k1 without the value use the plan cuts an edge and names no MvApp.pas:20 refusal' (($kp -match '\*\*cut by this plan\*\*') -and ($kp -notmatch '`MvApp\.pas:20`')) $kp
  $K2 = New-Proj { param($r) Edit-Text (Join-Path $r 'MvApp.pas') "`nend." "`ninitialization`n  RegisterClass(TMvJob);`n`nend." }
  $kp2 = (Invoke-Cli $K2 @('cycles', '--plan', '--db', $K2.Db, '--library-db', $LibraryDb)).Out
  Check 'k2 the value passed in MvApp''s initialization: refused init-order, no metaclass hand-over' (($kp2 -match 'refused: init-order') -and ($kp2 -notmatch '\*\*metaclass hand-over\*\*')) $kp2
} finally {
  if (-not $KeepWorkDir) {
    for ($i = 0; ($i -lt 15) -and (Test-Path -LiteralPath $WorkDir); $i++) {
      try { [IO.Directory]::Delete($WorkDir, $true) } catch { Start-Sleep -Seconds 2 }
    }
  }
}
Write-Host ("run_cyclefix_metaclass_value_dcc: {0} ({1} checks)" -f ($(if ($script:Failed) { 'FAIL' } else { 'PASS' })), $script:Passed)
if ($script:Failed) { exit 1 } else { exit 0 }
