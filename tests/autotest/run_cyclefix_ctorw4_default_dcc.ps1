<#
  run_cyclefix_ctorw4_default_dcc.ps1 -- 150-CY-10b (lane 150 CY1): the list whitelist w4 of `--ctor-wide` holds on the
  DEFAULT constructor inversion, without the flag. Fixture tests\fixtures\cyclefix\ctorw4 = the ctorwide TFolderWorker
  shape alone (Loader TFolderWorker's next blocker after 149-CY-10): a hub with `FWorkers: TObjectList<TW4Worker>` and
    a1 `FWorkers.Add(TW4Worker.Create(..))`        (the constructor result goes straight into a list that switches)
    a2 `FWorkers[I].Finished`                      (a member the class inherits from TThread, read through the list)
    a3 `FWorkers.OwnsObjects := True`              (the ownership switch names no element type)
    a4 `var FW: TW4Worker := FWorkers[0]`          (an inline slot that switches)
  the worker uses the hub back in its implementation (GHubTitle): one cycle W4Hub <-> W4.Worker.

  ACCEPTED without the flag: untouched copy built and run; `cycles --fix --apply` (real dcc gate) on a second copy;
  the list holds the base class, Add takes the pointer; the applied copy builds; the cycle is gone; stdout
  BYTE-identical.
  REFUSED without the flag: n3 `FWorkers.Extract(W)`, n4 `W := FWorkers.First` -- still off the whitelist.
  ONE AT A TIME: each of a1-a4 alone is what the default refused before (k1-k4: the tree minus the OTHER three
    shapes plans mechanical on the fixed engine; RED on 1.49.0-alpha base: every k refuses ctor-inversion-surface).
  POSITIVE CONTROL: pc1 the applied tree with the pointer assignment removed still compiles and its stdout DIFFERS.
#>
[CmdletBinding()]
param(
  [string]$Exe       = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe") { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" } else { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }),
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-ctorw4-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [switch]$NoBuild,
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
$RsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $RsVars)) { Write-Host 'SKIP: RAD Studio not installed' -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library DB at $LibraryDb" -ForegroundColor Yellow; exit 0 }
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fix   = Join-Path $Repo 'tests\fixtures\cyclefix\ctorw4'
$Ascii = [Text.Encoding]::ASCII
$Units = @('W4.Sink', 'W4.Worker', 'W4Hub')

function Edit-File([string]$Path, [string]$Old, [string]$New) {
  $t = [IO.File]::ReadAllText($Path)
  $n = $t.Replace(($Old -replace "`r?`n", "`r`n"), ($New -replace "`r?`n", "`r`n"))
  if ($n -ceq $t) { throw "fixture edit did not apply in $Path : $Old" }
  [IO.File]::WriteAllText($Path, $n, $Ascii)
}
function New-Tree([string]$Dir) {
  New-Item -ItemType Directory -Force $Dir | Out-Null
  Copy-Item (Join-Path $Fix '*') $Dir -Force
  $pj = [IO.File]::ReadAllText((Join-Path $Repo 'tests\fixtures\cyclefix\r1extend\R1Extend.dproj'))
  $pj = $pj.Replace('R1Extend', 'CtorW4').Replace('{5A1C7E94-2B6D-4F03-8C9A-7E3B1D0F2A85}', '{7C3E2A19-5D4B-4F8E-A1C6-0B9D8E7F6A54}')
  $pj = [regex]::Replace($pj, '(?m)^\s*<DCCReference Include="[^"]+"/>\r?\n', '')
  $refs = ($Units | ForEach-Object { "<DCCReference Include=`"$_.pas`"/>" }) -join "`r`n        "
  $pj = $pj.Replace('</DelphiCompile>', "</DelphiCompile>`r`n        $refs")
  [IO.File]::WriteAllText((Join-Path $Dir 'CtorW4.dproj'), ($pj -replace "`r?`n", "`r`n"), $Ascii)
}
function Invoke-Build([string]$Dproj) {
  $dir = Split-Path $Dproj
  $bat = Join-Path $WorkDir ('build-' + (Split-Path $dir -Leaf) + '.bat')
  $log = "$bat.log"
  $lines = @('@echo off', ('call "{0}"' -f $RsVars), ('cd /d "{0}"' -f $dir),
    ('msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal "{0}" > "{1}" 2>&1' -f $Dproj, $log),
    ('>> "{0}" echo BUILD_EXITCODE=%ERRORLEVEL%' -f $log))
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), $Ascii)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -NoNewWindow -Wait | Out-Null
  $text = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
  $errors = @([regex]::Matches($text, '(?m)^.*\b(error|fatal) [EF]\d{4}\b.*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
  return @{ Ok = ($text -match 'BUILD_EXITCODE=0') -and ($errors.Count -eq 0); Errors = ($errors -join ' | ') }
}
function Invoke-Program([string]$Dproj) {
  $exeP = Join-Path (Split-Path $Dproj) 'Win64\Debug\CtorW4.exe'
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait `
    -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [Convert]::ToBase64String([IO.File]::ReadAllBytes($o))
}
function Invoke-Index([string]$Dproj, [string]$Tag) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project $Dproj --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  return $db
}
function Get-Plan([string]$Dproj, [string]$Tag) {
  $db = Invoke-Index $Dproj $Tag
  $o = Join-Path $WorkDir "plan-$Tag.out"
  $null = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--db', ('"' + $db + '"'), '--plan', '--library-db', ('"' + $Lib + '"')) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "plan-$Tag.err")
  return [IO.File]::ReadAllText($o)
}
function Invoke-Apply([string]$Dproj, [string]$Tag) {
  $db = Invoke-Index $Dproj $Tag
  $o = Join-Path $WorkDir "apply-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--fix', '--apply', '--no-backup', '--build-timeout', '600', '--cycle', '1', '--project', ('"' + $Dproj + '"'),
      '--db', ('"' + $db + '"'), '--library-db', ('"' + $Lib + '"')) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "apply-$Tag.err")
  return @{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText((Join-Path $WorkDir "apply-$Tag.err")) }
}
function Get-CyclesText([string]$Dproj, [string]$Tag) {
  $db = Invoke-Index $Dproj $Tag
  return ((& $Exe cycles --db $db 2>&1) | Out-String)
}
function Get-Refusal([string]$Plan) { (([regex]::Match($Plan, '(?m)^.*refused:.*$').Value) -replace '^(.{0,300}).*$', '$1') }
$Mech = { param($pt) $pt.Contains('**Constructor inversion:** `TW4Worker.') -and -not $pt.Contains('Fix it: not available') }

$HubAdd   = '    for I := 1 to 2 do FWorkers.Add(TW4Worker.Create(I, FSink));'
$HubAddK  = "    for I := 1 to 2 do`n    begin`n      W := TW4Worker.Create(I, FSink);`n      FWorkers.Add(W);`n    end;"
$HubInh   = "      Writeln('[hub] ', W.ID, ' done ', W.Done, ' finished ', FWorkers[I].Finished);"
$HubInhK  = "      Writeln('[hub] ', W.ID, ' done ', W.Done, ' finished ', W.Finished);"
$HubOwn   = '    FWorkers.OwnsObjects := True;'
$HubVar   = "    var FW: TW4Worker := FWorkers[0];`n    Writeln('[hub] first ', FW.ID);"
$HubVarK  = "    W := FWorkers[0];`n    Writeln('[hub] first ', W.ID);"

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib

  Write-Host '== k: each w4 shape alone, no flag (the other three written the default-whitelist way)' -ForegroundColor Cyan
  $ks = @(
    @{ Tag = 'k1'; What = 'a1 Add(TX.Create(..))';   Keep = 'a1' },
    @{ Tag = 'k2'; What = 'a2 L[i].InheritedMember'; Keep = 'a2' },
    @{ Tag = 'k3'; What = 'a3 L.OwnsObjects := ..';  Keep = 'a3' },
    @{ Tag = 'k4'; What = 'a4 var S: TX := L[0]';    Keep = 'a4' }
  )
  foreach ($k in $ks) {
    $d = Join-Path $WorkDir "$($k.Tag)-edit"; New-Tree $d
    $h = Join-Path $d 'W4Hub.pas'
    if ($k.Keep -ne 'a1') { Edit-File $h $HubAdd $HubAddK }
    if ($k.Keep -ne 'a2') { Edit-File $h $HubInh $HubInhK }
    if ($k.Keep -ne 'a3') { Edit-File $h $HubOwn '' }
    if ($k.Keep -ne 'a4') { Edit-File $h $HubVar $HubVarK }
    $pt = Get-Plan (Join-Path $d 'CtorW4.dproj') $k.Tag
    Check "$($k.Tag) $($k.What) alone plans mechanical without the flag" (& $Mech $pt) (Get-Refusal $pt)
  }

  Write-Host '== acc: all four shapes, no flag' -ForegroundColor Cyan
  $edit = Join-Path $WorkDir 'acc-edit'; New-Tree $edit
  $pt = Get-Plan (Join-Path $edit 'CtorW4.dproj') 'acc-plan'
  Check 'acc1 the plan says mechanical, by constructor inversion of TW4Worker' (& $Mech $pt) (Get-Refusal $pt)
  if (-not $NoBuild) {
    $base = Join-Path $WorkDir 'acc-base'; New-Tree $base
    $b0 = Invoke-Build (Join-Path $base 'CtorW4.dproj')
    Check 'acc0 the untouched copy builds' $b0.Ok $b0.Errors
    $out0 = Invoke-Program (Join-Path $base 'CtorW4.dproj')
    Check 'acc0b the untouched run prints the hub lines' ($Ascii.GetString([Convert]::FromBase64String($out0)).Contains('[hub] first 1')) ''
    $ap = Invoke-Apply (Join-Path $edit 'CtorW4.dproj') 'acc-apply'
    Check 'acc2 --fix --apply passes the dcc gate (exit 0)' ($ap.Exit -eq 0) ("exit=$($ap.Exit) " + ((($ap.Out + $ap.Err).Trim() -split "`r?`n" | Select-Object -Last 4) -join ' | '))
    $hub = [IO.File]::ReadAllText((Join-Path $edit 'W4Hub.pas'))
    Check 'acc3 the list holds the base class and Add takes the pointer' ($hub.Contains('FWorkers.Add(NewTW4WorkerPtr(I, FSink))') -and ($hub -match 'TObjectList<TW4WorkerBase>')) ''
    Check 'acc4 Execute stays an override in the class' ([IO.File]::ReadAllText((Join-Path $edit 'W4.Worker.pas')).Contains('procedure Execute; override;')) ''
    $cy = Get-CyclesText (Join-Path $edit 'CtorW4.dproj') 'acc-after'
    Check 'acc5 the cycle is gone' ($cy -match 'No circular|0 circular|no circular') (($cy.Trim() -split "`r?`n" | Select-Object -First 2) -join ' | ')
    $b1 = Invoke-Build (Join-Path $edit 'CtorW4.dproj')
    Check 'acc6 the applied copy builds' $b1.Ok $b1.Errors
    $out1 = Invoke-Program (Join-Path $edit 'CtorW4.dproj')
    Check 'acc7 stdout byte-identical to the untouched build''s' (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) ''

    Write-Host '== positive control: the applied tree with the pointer assignment removed' -ForegroundColor Cyan
    Edit-File (Join-Path $edit 'W4.Worker.pas') '  NewTW4WorkerPtr := NewTW4Worker;' ''
    $bc = Invoke-Build (Join-Path $edit 'CtorW4.dproj')
    Check 'pc1a it still compiles' $bc.Ok $bc.Errors
    $outC = Invoke-Program (Join-Path $edit 'CtorW4.dproj')
    Check 'pc1b its stdout DIFFERS (the compare has teeth)' (($outC -ne '<no exe>') -and ($outC -cne $out0)) ''
  }

  $refused = @(
    @{ Tag = 'n3'; Why = 'the list handing an element out by Extract'; Old = $HubOwn; New = "    FWorkers.Extract(W);`n" + $HubOwn },
    @{ Tag = 'n4'; Why = 'the list handing an element out by First'; Old = $HubOwn; New = "    W := FWorkers.First;`n" + $HubOwn }
  )
  foreach ($r in $refused) {
    Write-Host "== refused without the flag: $($r.Why)" -ForegroundColor Cyan
    $d = Join-Path $WorkDir "$($r.Tag)-edit"; New-Tree $d
    Edit-File (Join-Path $d 'W4Hub.pas') $r.Old $r.New
    $pt = Get-Plan (Join-Path $d 'CtorW4.dproj') $r.Tag
    Check "$($r.Tag)1 the plan refuses ctor-inversion-surface naming W4Hub.pas" ($pt -match 'refused: ctor-inversion-surface -- .*W4Hub\.pas:') (Get-Refusal $pt)
  }
} finally {
  if ((-not $KeepWorkDir) -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
