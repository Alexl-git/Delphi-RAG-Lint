<#
  run_cyclefix_classref_dcc.ps1 -- 149-CY-7 (lane 149 CYA), the cycle-declared metaclass whose class can move:
  `TXClass = class of TX;` is a plain declaration, so Part A moves it into the leaf together with TX (pulled as its
  dependency). Tree: docs\examples\cycle-lab LabClsWidget / LabClsRegistry (the class is registered as a VALUE,
  `LabClsRegister(TLabClsWidget)`, in LabClsWidget's initialization; the registry's interface names the metaclass).

  ACCEPTED: the untouched copy builds and runs; the plan moves TLabClsWidgetClass and TLabClsWidget into
    LabClsWidget.Untangle (c1); `cycles --fix --apply` with the real dcc gate on a second copy (c2); the applied copy
    builds on its own (c3); stdout BYTE-identical (c4); no cycle after a re-index (c5).
  REFUSED (control k1): TX's body uses the registry, so TX cannot move -- the classref is refused with TX's reason
    (`it needs TLabClsWidget (class), which cannot move`), never moved alone.
  RED: engine 1.48.0-alpha refuses c1 with `a classref cannot be moved mechanically`.
#>
[CmdletBinding()]
param(
  [string]$Exe       = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe") { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" } else { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }),
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-classref-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
$RsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $RsVars)) { Write-Host 'SKIP: RAD Studio not installed' -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library DB at $LibraryDb" -ForegroundColor Yellow; exit 0 }
$script:Failed = $false
$script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Lab   = Join-Path $Repo 'docs\examples\cycle-lab'
$Ascii = [Text.Encoding]::ASCII

function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}
function Edit-File([string]$Path, [string]$Old, [string]$New) {
  $t = [IO.File]::ReadAllText($Path)
  $n = $t.Replace(($Old -replace "`r?`n", "`r`n"), ($New -replace "`r?`n", "`r`n"))
  if ($n -ceq $t) { throw "fixture edit did not apply in $Path : $Old" }
  Set-Text $Path $n
}

$Dpr = @'
program ClsLab;
{$APPTYPE CONSOLE}
uses
  LabClsRegistry in 'LabClsRegistry.pas',
  LabClsWidget in 'LabClsWidget.pas';
begin
  LabClsRunAll;
end.
'@

function New-Tree([string]$Dir) {
  New-Item -ItemType Directory -Force $Dir | Out-Null
  $units = @('LabClsRegistry', 'LabClsWidget')
  foreach ($u in $units) { Copy-Item (Join-Path $Lab "$u.pas") (Join-Path $Dir "$u.pas") -Force }
  Set-Text (Join-Path $Dir 'ClsLab.dpr') $Dpr
  $pj = [IO.File]::ReadAllText((Join-Path $Repo 'tests\fixtures\cyclefix\r1extend\R1Extend.dproj'))
  $pj = $pj.Replace('R1Extend', 'ClsLab').Replace('{5A1C7E94-2B6D-4F03-8C9A-7E3B1D0F2A85}', '{7C2E5A31-9D4B-4E86-A1F0-2B6D8E3C5A97}')
  $pj = [regex]::Replace($pj, '(?m)^\s*<DCCReference Include="[^"]+"/>\r?\n', '')
  $refs = ($units | ForEach-Object { "<DCCReference Include=`"$_.pas`"/>" }) -join "`r`n        "
  $pj = $pj.Replace('</DelphiCompile>', "</DelphiCompile>`r`n        $refs")
  Set-Text (Join-Path $Dir 'ClsLab.dproj') $pj
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
  $exeP = Join-Path (Split-Path $Dproj) 'Win64\Debug\ClsLab.exe'
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait `
    -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [IO.File]::ReadAllText($o, $Ascii)
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

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib

  Write-Host '== accepted: the metaclass moves with its class' -ForegroundColor Cyan
  $base = Join-Path $WorkDir 'c-base'; $edit = Join-Path $WorkDir 'c-edit'
  foreach ($d in $base, $edit) { New-Tree $d }
  $b0 = Invoke-Build (Join-Path $base 'ClsLab.dproj')
  Check 'c0 the untouched copy builds' $b0.Ok $b0.Errors
  $out0 = Invoke-Program (Join-Path $base 'ClsLab.dproj')
  $pt = Get-Plan (Join-Path $edit 'ClsLab.dproj') 'c-plan'
  Check 'c1 the plan moves TLabClsWidgetClass and TLabClsWidget into LabClsWidget.Untangle   (RED on 1.48.0: a classref cannot be moved mechanically)' (($pt -match '`TLabClsWidgetClass` -- \*\*classref\*\*') -and ($pt -match '`TLabClsWidget` -- \*\*class with methods\*\*') -and ($pt -match '(?s)TLabClsWidget = class.*TLabClsWidgetClass = class of TLabClsWidget;') -and ($pt -notmatch 'cannot be moved mechanically')) $pt
  $ap = Invoke-Apply (Join-Path $edit 'ClsLab.dproj') 'c-apply'
  Check 'c2 --fix --apply passes the dcc gate (exit 0)' ($ap.Exit -eq 0) ("exit=$($ap.Exit) " + ((($ap.Out + $ap.Err).Trim() -split "`r?`n" | Select-Object -Last 3) -join ' | '))
  Check 'c2b the leaf exists and declares both' ((Test-Path (Join-Path $edit 'LabClsWidget.Untangle.pas')) -and ([IO.File]::ReadAllText((Join-Path $edit 'LabClsWidget.Untangle.pas')) -match 'TLabClsWidgetClass = class of TLabClsWidget;')) ''
  $b1 = Invoke-Build (Join-Path $edit 'ClsLab.dproj')
  Check 'c3 the applied copy builds (independent msbuild)' $b1.Ok $b1.Errors
  $out1 = Invoke-Program (Join-Path $edit 'ClsLab.dproj')
  Check 'c4 stdout byte-identical to the untouched build''s' (($out0 -ne '<no exe>') -and ($out1 -ceq $out0) -and ($out0 -match 'widget runs')) "before=[$out0] after=[$out1]"
  $db2 = Invoke-Index (Join-Path $edit 'ClsLab.dproj') 'c-after'
  $left = (& $Exe cycles --db $db2 --library-db none 2>$null | Out-String)
  Check 'c5 no cycle after a re-index' ($left -match 'No circular unit dependencies') $left

  Write-Host '== control k1: the class cannot move (its body uses the registry)' -ForegroundColor Cyan
  $k = Join-Path $WorkDir 'k-edit'; New-Tree $k
  Edit-File (Join-Path $k 'LabClsWidget.pas') "  Writeln('[cls] widget runs');" "  Writeln('[cls] widget runs');`n  LabClsRegister(nil);"
  $pk = Get-Plan (Join-Path $k 'ClsLab.dproj') 'k-plan'
  Check 'k1 the classref is refused with its class''s reason, never moved alone' (($pk -match '`TLabClsWidgetClass` \(classref[^\n]*it needs `TLabClsWidget` \(class\), which cannot move') -and ($pk -notmatch '`TLabClsWidgetClass` -- \*\*classref\*\*')) (([regex]::Match($pk, '(?m)^.*TLabClsWidgetClass.*$').Value))
} finally {
  if ((-not $KeepWorkDir) -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
Write-Host ("run_cyclefix_classref_dcc: {0} ({1} checks)" -f ($(if ($script:Failed) { 'FAIL' } else { 'PASS' })), $script:Passed)
if ($script:Failed) { exit 1 } else { exit 0 }
