# run_cyclefix_metaclass_value_dcc.ps1 -- lane 150 CY2 (150-CY-7b): a class of the cycle passed as a VALUE
# (System.Classes.RegisterClass(TMvJob)) across the edge mvapp -> mvjob, with neither class movable. The
# metaclass hand-over recipe is NOT built in 1.49 (design: docs\superpowers\specs\2026-11-09-cy-7b-metaclass-value.md);
# this guard pins the SAFE behaviour until it is: the edge is refused with a reason that names the value line,
# --fix refuses and leaves every file byte-identical. When the recipe lands, m2-m4 flip (update them then).
#
#   m0  the untouched fixture builds (real msbuild) and prints `[mv] TMvJob`      (the fixture is valid Delphi)
#   m1  `cycles` finds the 2-unit group mvjob <-> mvapp
#   m2  plan: no edge is cut; `mvapp -> mvjob` is refused naming `TMvJob` and MvApp.pas:20 (the value line)
#   m3  --fix --apply: exit 1, a refusal, every source file byte-identical
#   k1  positive control: without the value use (RegisterClass line removed) TMvApp no longer needs the cycle, the
#       plan cuts an edge and no refusal names MvApp.pas:20 -- the m2 assertions can fail
#
# Usage: pwsh -File run_cyclefix_metaclass_value_dcc.ps1 [-Exe <drag-lint.exe>] [-WorkDir <dir>] [-KeepWorkDir]
param(
  [string]$Exe     = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe") { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" } else { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }),
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-metaclassvalue-$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
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
  Write-Host '== m: the value use stays refused, safely' -ForegroundColor Cyan
  $B = New-Proj
  $b0 = Invoke-Build $B
  Check 'm0.1 the untouched fixture builds' $b0.Ok $b0.Errors
  $out0 = Invoke-Program $B
  Check 'm0.2 it prints [mv] TMvJob' ($out0 -match '\[mv\] TMvJob') $out0

  $P = New-Proj
  $c = Invoke-Cli $P @('cycles', '--db', $P.Db)
  Check 'm1 cycles finds mvjob <-> mvapp' ($c.Out -match '\[2 units\] (mvjob <-> mvapp|mvapp <-> mvjob)') $c.Out
  $plan = (Invoke-Cli $P @('cycles', '--plan', '--db', $P.Db)).Out
  Check 'm2.1 the plan cuts no edge' (($plan -match 'No edge of this cycle can be cut mechanically') -and ($plan -notmatch '\*\*cut by this plan\*\*')) $plan
  Check 'm2.2 mvapp -> mvjob is refused naming TMvJob at the value line MvApp.pas:20' ($plan -match '(?m)^- `mvapp -> mvjob`: `TMvJob` \(class\):.*`MvApp\.pas:20`') $plan
  $h0 = Get-SrcHash $P.Root
  $f = Invoke-Cli $P @('cycles', '--fix', '--apply', '--build-timeout', '1800', '--project', $P.Dproj, '--db', $P.Db, '--format', 'json')
  $j = $null; try { $j = $f.Out | ConvertFrom-Json } catch { }
  $kinds = @(); foreach ($cy in @($j.cycles)) { foreach ($x in @($cy.refusals)) { if ($x) { $kinds += $x.kind } } }; foreach ($x in @($j.refusals)) { if ($x) { $kinds += $x.kind } }
  Check 'm3.1 --fix --apply refuses (exit 1, a refusal)' (($f.Exit -eq 1) -and ($kinds.Count -gt 0)) "exit=$($f.Exit) kinds=$($kinds -join ',') $($f.Out)"
  Check 'm3.2 every source file is byte-identical' ((Get-SrcHash $P.Root) -eq $h0)

  Write-Host '== k: positive control' -ForegroundColor Cyan
  $K = New-Proj { param($r) Edit-Text (Join-Path $r 'MvApp.pas') "  RegisterClass(TMvJob);`n" '' }
  $kp = (Invoke-Cli $K @('cycles', '--plan', '--db', $K.Db)).Out
  Check 'k1 without the value use the plan cuts an edge and names no MvApp.pas:20 refusal (m2 can fail)' (($kp -match '\*\*cut by this plan\*\*') -and ($kp -notmatch '`MvApp\.pas:20`')) $kp
} finally {
  if (-not $KeepWorkDir) {
    for ($i = 0; ($i -lt 15) -and (Test-Path -LiteralPath $WorkDir); $i++) {
      try { [IO.Directory]::Delete($WorkDir, $true) } catch { Start-Sleep -Seconds 2 }
    }
  }
}
Write-Host ("run_cyclefix_metaclass_value_dcc: {0} ({1} checks)" -f ($(if ($script:Failed) { 'FAIL' } else { 'PASS' })), $script:Passed)
if ($script:Failed) { exit 1 } else { exit 0 }
