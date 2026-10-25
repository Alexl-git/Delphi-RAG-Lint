<#
  run_cyclefix_instmethod_dcc.ps1 -- plan B2 (R2m, lane W6-cyc4, owner ruling 2026-10-25): the member
  hand-over plan that carries INSTANCE methods as interface methods, followed, COMPILES, and the
  program behaves exactly as before -- including VIRTUAL DISPATCH: the program runs a descendant
  (TDemoGagePortEx, in InstMethod.dpr) that overrides Reset, and after the cut the consumer calls
  Reset through the extracted interface. Needs RAD Studio (msbuild via rsvars) and the platform
  library DB.

  Tree: tests\fixtures\cyclefix\instmethod (Mark, Touch: static; Reset: virtual with a default
  parameter; GetNamePath: override of TPersistent.GetNamePath). The runner builds an untouched
  copy (msbuild, Win64 Debug) and keeps its stdout, plans `cycles --plan` on a second copy,
  applies cycle 1 with tools\follow-cycle-plan.ps1, checks the cycle is GONE (`cycles` on a
  re-index), builds it (BUILD_EXITCODE=0, no `error E` / `fatal F` line), runs it and compares
  stdout BYTE-FOR-BYTE. The untouched output must show the descendant's Reset ran, so the
  identical output after the cut proves the interface call still dispatches to the override.

  POSITIVE CONTROL: the followed tree with `procedure Reset` taken out of the leaf interface must
  NOT compile (the consumer's `Reset(3)` binds to the interface, nowhere else) -- so the build
  check can fail.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-instmethod-dcc-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
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
$Fixture = Join-Path $Repo 'tests\fixtures\cyclefix\instmethod'
$Ascii = [Text.Encoding]::ASCII

function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}

function New-Tree([string]$Dir) {
  New-Item -ItemType Directory -Force $Dir | Out-Null
  Get-ChildItem $Fixture -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $Dir $_.Name) -Force }
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
  $exeP = Join-Path (Split-Path $Dproj) 'Win64\Debug\InstMethod.exe'
  if (-not (Test-Path $exeP)) { return @{ B64 = '<no exe>'; Text = '' } }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait `
    -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  $b = [IO.File]::ReadAllBytes($o)
  return @{ B64 = [Convert]::ToBase64String($b); Text = $Ascii.GetString($b) }
}

function Invoke-Cycles([string]$Dproj, [string]$Tag, [string[]]$Extra) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project $Dproj --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  $o = Join-Path $WorkDir "cycles-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList (@('cycles', '--db', ('"' + $db + '"')) + $Extra) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "cycles-$Tag.err")
  return @{ Exit = $p.ExitCode; File = $o; Text = [IO.File]::ReadAllText($o) }
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib
  $base = Join-Path $WorkDir 'base'; $work = Join-Path $WorkDir 'edit'
  New-Tree $base; New-Tree $work

  Write-Host '== instmethod: plan, follow, compile, run' -ForegroundColor Cyan
  $b0 = Invoke-Build (Join-Path $base 'InstMethod.dproj')
  Check '0 the untouched copy builds' $b0.Ok $b0.Errors
  $out0 = Invoke-Program (Join-Path $base 'InstMethod.dproj')
  Check '1 the untouched program runs the DESCENDANT Reset and the override GetNamePath' (
    $out0.Text.Contains('reset 3 (descendant)') -and $out0.Text.Contains('path gageport') -and -not $out0.Text.Contains('(base)')) ($out0.Text.Trim() -replace "`r?`n", ' | ')
  $plan = Invoke-Cycles (Join-Path $work 'InstMethod.dproj') 'plan' @('--plan', '--library-db', ('"' + $Lib + '"'))
  Check '2 planned (exit 0) by member hand-over, the methods carried' (($plan.Exit -eq 0) -and
    $plan.Text.Contains('by **member hand-over through an extracted interface**') -and
    $plan.Text.Contains('    procedure Reset(const pCount: Integer = 1);')) "exit=$($plan.Exit)"
  $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $plan.File -Cycle 1 -Root $work 2>&1 | Out-String
  Check '3 the follower applies cycle 1 (exit 0)' ($LASTEXITCODE -eq 0) ($fo.Trim() -replace "`r?`n", ' | ')
  $after = Invoke-Cycles (Join-Path $work 'InstMethod.dproj') 'after' @('--library-db', 'none')
  Check '4 the cycle is gone after a re-index' ($after.Text -match 'No circular unit dependencies found\.') ($after.Text.Trim() -replace "`r?`n", ' | ')
  $b1 = Invoke-Build (Join-Path $work 'InstMethod.dproj')
  Check '5 the followed copy builds (BUILD_EXITCODE=0, no error E / fatal F)' $b1.Ok $b1.Errors
  $out1 = Invoke-Program (Join-Path $work 'InstMethod.dproj')
  Check '6 its stdout is byte-identical to the untouched build''s (the override still runs)' (
    ($out0.B64 -ne '<no exe>') -and ($out1.B64 -ceq $out0.B64)) ($out1.Text.Trim() -replace "`r?`n", ' | ')

  Write-Host '== positive control: Reset taken out of the leaf interface' -ForegroundColor Cyan
  $leaf = Join-Path $work 'DemoGagePort.Untangle.pas'
  $t = [IO.File]::ReadAllText($leaf)
  $t2 = $t.Replace("    procedure Reset(const pCount: Integer = 1);`r`n", '')
  Set-Text $leaf $t2
  Check 'pc0 the interface line was removed' ($t2 -ne $t) ''
  $bc = Invoke-Build (Join-Path $work 'InstMethod.dproj')
  Check 'pc1 it does NOT compile (the build check has teeth; Reset binds through the interface)' (-not $bc.Ok) $bc.Errors
} finally {
  if (-not $KeepWorkDir -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
