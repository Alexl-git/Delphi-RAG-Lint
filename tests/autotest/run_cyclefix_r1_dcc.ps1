<#
  run_cyclefix_r1_dcc.ps1 -- E18 Task 5: a routine-call inversion (R1) plan, followed, COMPILES and
  the program behaves exactly as before. Needs RAD Studio (msbuild via rsvars).

  For each tree -- circular-demo (cycle 3, leaf DemoBlueprint.Interfaces), tests\fixtures\cyclefix\
  r1extend (existing R1Title.Untangle extended) and r1extend without that leaf (R1Title.Untangle
  created) -- the runner builds the untouched copy (msbuild, Win64 Debug) and keeps its stdout,
  plans `cycles --plan` on a second copy, applies the cycle with tools\follow-cycle-plan.ps1,
  builds it (BUILD_EXITCODE=0, no `error E` / `fatal F` line), runs it and compares stdout
  BYTE-FOR-BYTE with the untouched build's.

  POSITIVE CONTROL: the followed demo with the initialization assignment line removed still
  compiles, but the call through the nil pointer fails at run time -- its stdout must DIFFER.
  Without it, an output compare that cannot tell a broken inversion from a working one would pass.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-r1-dcc-$PID"
)
$ErrorActionPreference = 'Stop'
$RsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $RsVars)) { Write-Host 'SKIP: RAD Studio not installed' -ForegroundColor Yellow; exit 0 }
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
$Fx    = Join-Path $Repo 'tests\fixtures\cyclefix'
$Ascii = [Text.Encoding]::ASCII

function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}

function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}

# msbuild of pDproj (Win64 Debug); returns @{ Ok; Errors }.
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

# Runs the built program of pDproj; returns its stdout as bytes (base64, for an exact compare).
function Invoke-Program([string]$Dproj) {
  $exeP = Join-Path (Split-Path $Dproj) ('Win64\Debug\' + [IO.Path]::GetFileNameWithoutExtension($Dproj) + '.exe')
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait `
    -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [Convert]::ToBase64String([IO.File]::ReadAllBytes($o))
}

function Get-PlanFile([string]$Dproj, [string]$Tag) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project $Dproj --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  $o = Join-Path $WorkDir "plan-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--db', ('"' + $db + '"'), '--plan') `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "plan-$Tag.err")
  return @{ Exit = $p.ExitCode; File = $o }
}

# Untouched build + stdout, then plan / follow / build / run on a second copy.
function Test-Tree([string]$Tag, [string]$Src, [string]$DprojName, [int]$Cycle, [scriptblock]$Prepare) {
  Write-Host "== $Tag" -ForegroundColor Cyan
  $base = Join-Path $WorkDir "$Tag-base"; $edit = Join-Path $WorkDir "$Tag-edit"
  Copy-Tree $Src $base; Copy-Tree $Src $edit
  if ($Prepare) { & $Prepare $base; & $Prepare $edit }
  $b0 = Invoke-Build (Join-Path $base $DprojName)
  Check "$Tag 0 the untouched copy builds" $b0.Ok $b0.Errors
  $out0 = Invoke-Program (Join-Path $base $DprojName)
  $plan = Get-PlanFile (Join-Path $edit $DprojName) $Tag
  Check "$Tag 1 planned (exit 0)" ($plan.Exit -eq 0) "exit=$($plan.Exit)"
  $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $plan.File -Cycle $Cycle -Root $edit 2>&1 | Out-String
  Check "$Tag 2 the follower applies cycle $Cycle (exit 0)" ($LASTEXITCODE -eq 0) ($fo.Trim() -replace "`r?`n", ' | ')
  $b1 = Invoke-Build (Join-Path $edit $DprojName)
  Check "$Tag 3 the followed copy builds (BUILD_EXITCODE=0, no error E / fatal F)" $b1.Ok $b1.Errors
  $out1 = Invoke-Program (Join-Path $edit $DprojName)
  Check "$Tag 4 its stdout is byte-identical to the untouched build's" (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) ''
  return @{ Edit = $edit; Out0 = $out0 }
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $demo = Test-Tree 'demo' (Join-Path $Repo 'circular-demo') 'CircularDemo.dproj' 3 $null
  $null = Test-Tree 'r1extend' (Join-Path $Fx 'r1extend') 'R1Extend.dproj' 1 $null
  $dropLeaf = {
    param($Dir)
    [IO.File]::Delete((Join-Path $Dir 'R1Title.Untangle.pas'))
    $dpr = Join-Path $Dir 'R1Extend.dpr'
    Set-Text $dpr ([IO.File]::ReadAllText($dpr).Replace("  R1Title.Untangle in 'R1Title.Untangle.pas',`r`n", '').Replace("    Writeln('[main] style ', Ord(tsBold));`r`n", ''))
    $dpj = Join-Path $Dir 'R1Extend.dproj'
    Set-Text $dpj ([IO.File]::ReadAllText($dpj).Replace("        <DCCReference Include=`"R1Title.Untangle.pas`"/>`r`n", ''))
  }
  $null = Test-Tree 'r1create' (Join-Path $Fx 'r1extend') 'R1Extend.dproj' 1 $dropLeaf

  Write-Host '== positive control: the followed demo without the initialization assignment' -ForegroundColor Cyan
  $vm = Join-Path $demo.Edit 'DemoBlueprint.ViewModel.pas'
  $t = [IO.File]::ReadAllText($vm)
  Set-Text $vm ($t.Replace("  DemoBlueprintViewModelCreatePtr := DemoBlueprintViewModelCreate;`r`n", ''))
  Check 'pc0 the assignment line was removed' ([IO.File]::ReadAllText($vm) -ne $t) ''
  $bc = Invoke-Build (Join-Path $demo.Edit 'CircularDemo.dproj')
  Check 'pc1 it still compiles' $bc.Ok $bc.Errors
  $outC = Invoke-Program (Join-Path $demo.Edit 'CircularDemo.dproj')
  Check 'pc2 its stdout DIFFERS from the untouched build (the compare has teeth)' (($outC -ne '<no exe>') -and ($outC -cne $demo.Out0)) ''
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
