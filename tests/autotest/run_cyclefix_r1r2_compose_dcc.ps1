# run_cyclefix_r1r2_compose_dcc.ps1 -- lane 150 CY1 (150-CY-11): R1 (routine-call inversion) and R2 (member hand-over
# through an extracted interface) composed on ONE edge. Fixture: tests\fixtures\cyclefix\memberwrite (the R2 shape:
# DemoUIConnect tests / casts TDemoGagePort and reads Log / LastGage) patched so DemoUIConnect ALSO calls a free routine
# GageBeep(pTimes: Integer) of DemoGagePort inside OnData. 0 real sites (CYB census): fixture-only proof.
#
#   c0  the untouched (patched) fixture builds and prints the beep line
#   c1  RED on 1.49.0-alpha base: the edge is refused (`other-ref` -- GageBeep, which no interface carries); now the plan
#       cuts demouiconnect -> demogageport by member hand-over AND routine-call inversion of GageBeep, no edge-still-used
#   c2  --fix --apply: exit 0; DemoUIConnect calls GageBeepPtr and no longer uses DemoGagePort; builds; stdout
#       byte-identical; no cycle after a re-index
#   k1  refused: GageBeep's signature names a non-System type (TStrings): the composed leaf carries System types only
#   pc1 positive control: the applied tree with `GageBeepPtr := GageBeep;` removed still compiles; stdout DIFFERS
## Usage: pwsh -File run_cyclefix_r1r2_compose_dcc.ps1 [-Exe <drag-lint.exe>] [-WorkDir <dir>] [-KeepWorkDir]
param(
  [string]$Exe     = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe") { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" } else { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }),
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-r1r2-$PID",
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
$Name  = 'MemberWrite'
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
  Get-ChildItem (Join-Path $Repo 'tests\fixtures\cyclefix\memberwrite') -File |
    Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) }
  Edit-Text (Join-Path $root 'DemoGagePort.pas') "  end;`n`nimplementation" "  end;`n`n/// <summary>Beeps the gage.</summary>`n/// <param name=`"pTimes`">How often.</param>`nprocedure GageBeep(pTimes: Integer);`n`nimplementation"
  Edit-Text (Join-Path $root 'DemoGagePort.pas') "constructor TDemoGagePort.Create" "procedure GageBeep(pTimes: Integer);`nbegin`n  Writeln('beep ', pTimes);`nend;`n`nconstructor TDemoGagePort.Create"
  Edit-Text (Join-Path $root 'DemoUIConnect.pas') "    Log.Add('data ' + InBuf);" "    Log.Add('data ' + InBuf);`n    GageBeep(2);"
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
  Write-Host '== c: R1 + R2 on one edge' -ForegroundColor Cyan
  $B = New-Proj
  $b0 = Invoke-Build $B
  Check 'c0.1 the patched fixture builds' $b0.Ok $b0.Errors
  $out0 = Invoke-Program $B
  Check 'c0.2 it prints the beep line' ($out0 -match 'beep 2') $out0
  $P = New-Proj
  $plan = (Invoke-Cli $P @('cycles', '--plan', '--db', $P.Db, '--library-db', $LibraryDb)).Out
  Check 'c1.1 the plan cuts demouiconnect -> demogageport by member hand-over' ($plan -match 'Cut the edge `demouiconnect -> demogageport` by \*\*member hand-over') $plan
  Check 'c1.2 ... and routine-call inversion of GageBeep on the same edge, no edge-still-used' (($plan -match 'On the same edge, \*\*routine-call inversion\*\* of `GageBeep`') -and ($plan -notmatch 'refused: edge-still-used')) $plan
  $f = Invoke-Cli $P @('cycles', '--fix', '--apply', '--no-backup', '--build-timeout', '1800', '--project', $P.Dproj, '--db', $P.Db, '--library-db', $LibraryDb)
  Check 'c2.1 --fix --apply: exit 0 (the dcc gate passed)' ($f.Exit -eq 0) "exit=$($f.Exit) $($f.Out)"
  $ui = [IO.File]::ReadAllText((Join-Path $P.Root 'DemoUIConnect.pas'), $Ascii)
  Check 'c2.2 DemoUIConnect calls GageBeepPtr and no longer uses DemoGagePort' (($ui -match 'GageBeepPtr\(2\)') -and ($ui -notmatch '(?m)^\s*DemoGagePort[;,]')) $ui
  $b1 = Invoke-Build $P
  Check 'c2.3 the applied copy builds (independent msbuild)' $b1.Ok $b1.Errors
  $out1 = Invoke-Program $P
  Check 'c2.4 stdout byte-identical to the untouched build' (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) "before=[$out0] after=[$out1]"
  $null = Invoke-Cli $P @('index', '--project', $P.Dproj, '--db', $P.Db)
  $c1 = Invoke-Cli $P @('cycles', '--db', $P.Db)
  Check 'c2.5 no cycle after a re-index' ($c1.Out -match 'No circular unit dependencies found\.') $c1.Out

  Write-Host '== pc1: the pointer assignment removed' -ForegroundColor Cyan
  Edit-Text (Join-Path $P.Root 'DemoGagePort.pas') "  GageBeepPtr := GageBeep;`n" ''
  $bc = Invoke-Build $P
  Check 'pc1a it still compiles' $bc.Ok $bc.Errors
  $outC = Invoke-Program $P
  Check 'pc1b its stdout DIFFERS (the compare has teeth)' (($outC -ne '<no exe>') -and ($outC -cne $out0)) "after=[$outC]"

  Write-Host '== k1: a signature type the composed leaf cannot carry' -ForegroundColor Cyan
  $K = New-Proj { param($r)
    Edit-Text (Join-Path $r 'DemoGagePort.pas') 'procedure GageBeep(pTimes: Integer);' 'procedure GageBeep(pTimes: Integer; pLog: TStrings);'
    Edit-Text (Join-Path $r 'DemoUIConnect.pas') '    GageBeep(2);' '    GageBeep(2, nil);' }
  $kp = (Invoke-Cli $K @('cycles', '--plan', '--db', $K.Db, '--library-db', $LibraryDb)).Out
  Check 'k1 refused manual-edit naming TStrings, no composed cut' (($kp -match 'routine-call inversion and member hand-over on one edge: `GageBeep` names `TStrings`') -and ($kp -cnotmatch 'On the same edge, \*\*routine-call inversion')) $kp
} finally {
  if (-not $KeepWorkDir) {
    for ($i = 0; ($i -lt 15) -and (Test-Path -LiteralPath $WorkDir); $i++) {
      try { [IO.Directory]::Delete($WorkDir, $true) } catch { Start-Sleep -Seconds 2 }
    }
  }
}
Write-Host ("run_cyclefix_r1r2_compose_dcc: {0} ({1} checks)" -f ($(if ($script:Failed) { 'FAIL' } else { 'PASS' })), $script:Passed)
if ($script:Failed) { exit 1 } else { exit 0 }
