<#
  run_cyclefix_r2_dcc.ps1 -- E18 Task 6: a member hand-over (R2) plan, followed, COMPILES and the
  program behaves exactly as before. Needs RAD Studio (msbuild via rsvars) and the platform
  library DB (R2 reads class ancestry from it).

  For each tree -- circular-demo (cycle 2: a TComponent receiver cast as is, a TObject receiver
  cast through TComponent), the memberwrite pair without its write (leaf DemoGagePort.Untangle
  created and registered), tests\fixtures\cyclefix\r2extend (the existing leaf extended) and
  r2extend with an empty leaf (ExtendLeaves' At=0 anchor) -- the runner builds the untouched copy
  (msbuild, Win64 Debug) and keeps its stdout, plans `cycles --plan` on a second copy, applies the
  cycle with tools\follow-cycle-plan.ps1, builds it (BUILD_EXITCODE=0, no `error E` / `fatal F`
  line), runs it and compares stdout BYTE-FOR-BYTE with the untouched build's.

  The engine never opens the real library: -LibraryDb is copied into the $PID scratch dir and the
  copy is passed with --library-db; check z1 compares size + mtime of the real library DBs.

  POSITIVE CONTROL: the followed demo with GetLastGage returning 0 still compiles, but its stdout
  must DIFFER -- an output compare that cannot tell a wrong getter from a right one would pass.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-r2-dcc-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite'
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
$Fx    = Join-Path $Repo 'tests\fixtures\cyclefix'
$Ascii = [Text.Encoding]::ASCII

function Get-LibStamp {
  return (@(Get-ChildItem 'C:\Projects\.drag-lint' -Filter 'library-*.sqlite' -ErrorAction SilentlyContinue |
    Sort-Object Name | ForEach-Object { '{0}={1}@{2:o}' -f $_.Name, $_.Length, $_.LastWriteTimeUtc }) -join ' ')
}

function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}

function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}

# Replaces pOld by pNew in one file of a copy (CRLF); False when nothing changed.
function Edit-File([string]$Path, [string]$Old, [string]$New) {
  $t = [IO.File]::ReadAllText($Path)
  $n = $t.Replace(($Old -replace "`r?`n", "`r`n"), ($New -replace "`r?`n", "`r`n"))
  Set-Text $Path $n
  return ($n -ne $t)
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
    -ArgumentList @('cycles', '--db', ('"' + $db + '"'), '--plan', '--library-db', ('"' + $Lib + '"')) `
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
  Check "$Tag 1 planned (exit 0), cut by member hand-over" (($plan.Exit -eq 0) -and [IO.File]::ReadAllText($plan.File).Contains('by **member hand-over through an extracted interface**')) "exit=$($plan.Exit)"
  $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $plan.File -Cycle $Cycle -Root $edit 2>&1 | Out-String
  Check "$Tag 2 the follower applies cycle $Cycle (exit 0)" ($LASTEXITCODE -eq 0) ($fo.Trim() -replace "`r?`n", ' | ')
  $b1 = Invoke-Build (Join-Path $edit $DprojName)
  Check "$Tag 3 the followed copy builds (BUILD_EXITCODE=0, no error E / fatal F)" $b1.Ok $b1.Errors
  $out1 = Invoke-Program (Join-Path $edit $DprojName)
  Check "$Tag 4 its stdout is byte-identical to the untouched build's" (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) ''
  return @{ Edit = $edit; Out0 = $out0 }
}

$Stamp0 = Get-LibStamp
New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib
  Check 's0 the platform library was copied into the scratch dir' ((Get-Item $Lib).Length -eq (Get-Item $LibraryDb).Length) $Lib

  $demo = Test-Tree 'demo' (Join-Path $Repo 'circular-demo') 'CircularDemo.dproj' 2 $null
  $dropWrite = {
    param($Dir)
    $null = Edit-File (Join-Path $Dir 'DemoUIConnect.pas') "    LastGage := 0; // <-- a WRITE through the with: an interface of reads cannot carry it`n" ''
  }
  $null = Test-Tree 'r2create' (Join-Path $Fx 'memberwrite') 'MemberWrite.dproj' 1 $dropWrite
  $null = Test-Tree 'r2extend' (Join-Path $Fx 'r2extend') 'R2Extend.dproj' 1 $null
  $emptyLeaf = {
    param($Dir)
    $null = Edit-File (Join-Path $Dir 'DemoGagePort.Untangle.pas') "type`n  /// <summary>The unit a gage reads in.</summary>`n  TDemoGageUnit = (guMillimetre, guInch);`n`n" ''
    $null = Edit-File (Join-Path $Dir 'R2Extend.dpr') "    Writeln('[main] unit ', Ord(guInch));`n" ''
  }
  $null = Test-Tree 'r2at0' (Join-Path $Fx 'r2extend') 'R2Extend.dproj' 1 $emptyLeaf

  Write-Host '== positive control: the followed demo with GetLastGage returning 0' -ForegroundColor Cyan
  $gp = Join-Path $demo.Edit 'DemoGagePort.pas'
  Check 'pc0 the getter body was changed' (Edit-File $gp "function TDemoGagePort.GetLastGage: Integer;`nbegin`n  Result := FLastGage;" "function TDemoGagePort.GetLastGage: Integer;`nbegin`n  Result := 0;") ''
  $bc = Invoke-Build (Join-Path $demo.Edit 'CircularDemo.dproj')
  Check 'pc1 it still compiles' $bc.Ok $bc.Errors
  $outC = Invoke-Program (Join-Path $demo.Edit 'CircularDemo.dproj')
  Check 'pc2 its stdout DIFFERS from the untouched build (the compare has teeth)' (($outC -ne '<no exe>') -and ($outC -cne $demo.Out0)) ''
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
$Stamp1 = Get-LibStamp
Check 'z1 the real library DBs are unchanged (size + mtime)' ($Stamp0 -eq $Stamp1) "before [$Stamp0] after [$Stamp1]"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
