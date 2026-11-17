<#
  run_v152_FIXLIB.ps1 -- 1.52 FIXLIB (ruling B9h): `lint <file> --fix` WITHOUT --fix-rule opens the library store, so the
  with-statement fixer (FixWith -> UnwithPlanFile) can resolve a class target's ancestors (TObject) instead of declining
  every class with unresolved-ancestor.

  Needs dcc: SKIPs when rsvars.bat or the platform library is missing. The fixture is tests\fixtures\refactor\unwith, copied
  under %TEMP%; line 48 of UwCases.pas is `with FOwner.Stable do` (a CLASS target), lines 70 / 129 / 186 are record targets.
  (a) a library DB (--library-db <lib>): the dry run plans an edit for the class with at line 48.
  (b) POSITIVE CONTROL / DECLINE: --library-db none: no edit for line 48 (unresolved-ancestor), while the record with at
      line 70 is still planned -- the run is alive, only the class is declined.
  (c) a real --fix-line 48 --apply with the library: exit 0, the with is gone, the result COMPILES, and the program prints
      what the untouched program printed.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-fixlib-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [string]$Rsvars    = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [switch]$KeepScratch
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Passed = 0
function Check($n, $ok, $d = '') {
  if ($ok) { Write-Host "  [PASS] $n" -ForegroundColor Green; $script:Passed++ }
  else { Write-Host "  [FAIL] $n" -ForegroundColor Red; if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library ($LibraryDb)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fixture = Join-Path $Repo 'tests\fixtures\refactor\unwith'
$ClassWithLine = 48
$RecordWithLine = 70

function New-Copy([string]$Name) {
  $d = Join-Path $WorkDir $Name
  [IO.Directory]::CreateDirectory($d) | Out-Null
  Copy-Item "$Fixture\*" $d -Recurse -Force
  return $d
}
function Invoke-Index([string]$Dir) {
  $env:UW_HIDDEN = ''
  $null = & $Exe index --project "$Dir\UwDemo.dproj" --db "$Dir\uw.sqlite" 2>&1
  $env:UW_HIDDEN = 'hidden'
  if ($LASTEXITCODE -ne 0) { throw "index failed in $Dir" }
}
function Build-And-Run([string]$Dir) {
  $bat = Join-Path $Dir '_b.bat'
  [IO.File]::WriteAllText($bat, "@echo off`r`ncall `"$Rsvars`"`r`ncd /d `"$Dir`"`r`nset UW_HIDDEN=hidden`r`nmsbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal UwDemo.dproj`r`n")
  $log = Join-Path $Dir '_b.log'
  Start-Process cmd.exe -ArgumentList '/c', $bat -RedirectStandardOutput $log -NoNewWindow -Wait
  $found = Get-ChildItem "$Dir\Win64\Debug\UwDemo.exe" -ErrorAction SilentlyContinue
  if (-not $found) { throw "the fixture did not build in $Dir, see $log" }
  return (& $found.FullName | Out-String)
}
function Invoke-Fix([string]$Dir, [string[]]$Extra) {
  $o = & $Exe lint "$Dir\UwCases.pas" --fix --db "$Dir\uw.sqlite" @Extra 2>&1 | Out-String
  $script:FixCode = $LASTEXITCODE
  return $o
}

try {
  [IO.Directory]::CreateDirectory($WorkDir) | Out-Null
  $env:UW_HIDDEN = 'hidden'
  $Base = New-Copy 'base'
  $Golden = Build-And-Run $Base
  Check 'baseline program runs' ($Golden -match 'field-chain 11 ') $Golden

  $D = New-Copy 'dry'
  Invoke-Index $D
  $Src = [IO.File]::ReadAllLines("$D\UwCases.pas")
  Check 'fixture: line 48 is the class with, line 70 the record with' (($Src[$ClassWithLine - 1] -match '^\s*with FOwner\.Stable do') -and ($Src[$RecordWithLine - 1] -match '^\s*with FPt do')) "$($Src[$ClassWithLine - 1]) | $($Src[$RecordWithLine - 1])"

  # (a) with a library DB the class with is planned
  $Out = Invoke-Fix $D @('--library-db', $LibraryDb)
  Check '(a) library DB: the class with (line 48) has an edit' ($Out -match "replace lines $ClassWithLine\.\.") $Out
  # (b) decline + positive control
  $Out = Invoke-Fix $D @('--library-db', 'none')
  Check '(b) no library: the class with (line 48) is declined' (-not ($Out -match "replace lines $ClassWithLine\.\.")) $Out
  Check '(b) POSITIVE CONTROL: no library, the record with (line 70) is still planned' ($Out -match "replace lines $RecordWithLine\.\.") $Out

  # (c) a real apply of the class with
  $A = New-Copy 'apply'
  Invoke-Index $A
  $Out = Invoke-Fix $A @('--library-db', $LibraryDb, '--fix-line', "$ClassWithLine", '--apply')
  Check '(c) --apply exits 0' ($script:FixCode -eq 0) "exit $script:FixCode`n$Out"
  $Now = [IO.File]::ReadAllLines("$A\UwCases.pas")
  Check '(c) the with at line 48 is gone' (-not ($Now[$ClassWithLine - 1] -match '^\s*with\b')) $Now[$ClassWithLine - 1]
  Check '(c) it is not a no-op: the file changed' ((Get-FileHash "$A\UwCases.pas").Hash -ne (Get-FileHash "$Fixture\UwCases.pas").Hash)
  $After = Build-And-Run $A
  Check '(c) the result compiles and prints what the untouched program printed' ($After -eq $Golden) $After
}
finally {
  $env:UW_HIDDEN = ''
  if (-not $KeepScratch -and (Test-Path $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "  (scratch kept: $WorkDir)" } }
}
Write-Host "run_v152_FIXLIB: $script:Passed passed" -ForegroundColor Cyan
if ($script:Failed) { exit 1 }
exit 0
