<#
  run_reparse_libraries_guard.ps1 -- pins tools\reparse-libraries.ps1, the bump
  re-parse runner (owner ruling Q5, 1.43): libraries in parallel and alone,
  projects only after them, catch-up last, one summary file with an ETA.

  It drives the real script against a stub engine (a .bat), so no index is written
  and no engine runs. The stub records START/END per call. The ordering checker
  has its own positive control: fed the 1.42 shape (projects beside the libraries)
  it must report a violation.
#>
param([string]$Scratch = '')

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$runner = Join-Path $repo 'tools\reparse-libraries.ps1'
if ($Scratch -eq '') { $Scratch = Join-Path ([IO.Path]::GetTempPath()) "reparse_guard_$PID" }
[void][IO.Directory]::CreateDirectory($Scratch)

$fails = 0; $passes = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:passes++; "PASS $Name" }
  else { $script:fails++; "FAIL $Name $Detail" }
}

$stub = Join-Path $Scratch 'stub-engine.bat'
$stubText = @'
@echo off
setlocal
if "%1"=="resolve-dbs" ( echo ["C:\\x\\library-%3.sqlite"] & exit /b 0 )
if "%1"=="sql" ( echo {"rows":[[7000]]} & exit /b 0 )
set NAME=catchup
echo %* | findstr /c:"--only Library" >nul && set NAME=library
echo %* | findstr /c:"--only P1" >nul && set NAME=projects
set PLAT=
echo %* | findstr /c:"win32" >nul && set PLAT=win32
echo %* | findstr /c:"win64" >nul && set PLAT=win64
if "%NAME%" NEQ "library" set PLAT=
>>"%STUB_CALLS%" echo START %NAME% %PLAT% %*
echo   C:\a\One.pas -^> 14 symbols, 3 refs, 0 errors
echo   C:\a\Two.dfm -^> 1 symbols, 0 refs, 0 errors
ping -n 4 127.0.0.1 >nul
echo   stage: calls -- started 12:00:00
ping -n 3 127.0.0.1 >nul
echo === Library [X] -^> C:\x\l.sqlite : files=2 symbols=15 refs=3 walked=2 attempted=2 up-to-date=0 committed=2 [1.0s, 4 attempted/min] ===
>>"%STUB_CALLS%" echo END %NAME% %PLAT%
if "%STUB_FAIL%"=="%PLAT%" if not "%PLAT%"=="" exit /b 7
exit /b 0
'@
[IO.File]::WriteAllText($stub, ($stubText -replace "`r?`n", "`r`n"), (New-Object Text.ASCIIEncoding))

# Violations of the Q5 order in a START/END call list.
function Get-OrderViolations([string[]]$Calls) {
  $v = @()
  $firstLibEnd = -1; $lastLibEnd = -1; $projStart = -1; $projEnd = -1; $cuStart = -1; $libStarts = @()
  for ($i = 0; $i -lt $Calls.Count; $i++) {
    $c = $Calls[$i]
    if ($c -match '^START library') { $libStarts += $i }
    if ($c -match '^END library') { if ($firstLibEnd -lt 0) { $firstLibEnd = $i }; $lastLibEnd = $i }
    if ($c -match '^START projects') { $projStart = $i }
    if ($c -match '^END projects') { $projEnd = $i }
    if ($c -match '^START catchup') { $cuStart = $i }
  }
  if ($libStarts.Count -ne 2) { $v += "library starts=$($libStarts.Count), expected 2" }
  foreach ($s in $libStarts) { if ($firstLibEnd -ge 0 -and $s -gt $firstLibEnd) { $v += 'libraries not parallel: one started after another ended' } }
  if ($projStart -ge 0 -and $projStart -lt $lastLibEnd) { $v += 'projects started before the libraries ended' }
  if ($cuStart -ge 0 -and $cuStart -lt $projEnd) { $v += 'catch-up started before the projects ended' }
  return $v
}

function Invoke-Runner([string]$Tag, [string]$FailPlat = '', [string[]]$Extra = @('-AllowBusy')) {
  $out = Join-Path $Scratch $Tag
  [void][IO.Directory]::CreateDirectory($out)
  $calls = Join-Path $out 'calls.txt'
  if (Test-Path $calls) { [IO.File]::Delete($calls) }
  $env:STUB_CALLS = $calls
  $env:STUB_FAIL = $FailPlat
  $shell = (Get-Process -Id $PID).Path
  $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$runner`"", '-Engine', "`"$stub`"", '-OutDir', "`"$out`"",
    '-WorkDir', "`"$Scratch`"", '-ProjectsCsv', 'P1,P2', '-PollSec', '1') + $Extra
  $p = Start-Process $shell -ArgumentList $argList -PassThru -WindowStyle Hidden
  [void]$p.Handle
  $seen = @{}
  $sum = Join-Path $out 'SUMMARY.txt'
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt 120) {
    if (Test-Path $sum) {
      try {
        $first = [IO.File]::ReadAllLines($sum) | Select-Object -First 1
        if ($first -match 'phase=(\w+)') { $key = $Matches[1]; $all = [IO.File]::ReadAllLines($sum); if (-not $seen.ContainsKey($key) -or $first -match 'eta=\d') { $seen[$key] = $all } }
      } catch { }
    }
    Start-Sleep -Milliseconds 300
  }
  if (-not $p.HasExited) { $p.Kill(); return [pscustomobject]@{ Exit = -1; Calls = @(); Summary = @(); Seen = $seen } }
  $p.WaitForExit()
  [pscustomobject]@{
    Exit = $p.ExitCode
    Calls = if (Test-Path $calls) { @([IO.File]::ReadAllLines($calls)) } else { @() }
    Summary = if (Test-Path $sum) { @([IO.File]::ReadAllLines($sum)) } else { @() }
    Seen = $seen
  }
}

# Positive control of the checker: the 1.42 shape.
$shape142 = @('START library win32', 'START library win64', 'START projects', 'END projects', 'END library win64', 'END library win32', 'START catchup')
Check 'control: the 1.42 order is a violation' (@(Get-OrderViolations $shape142).Count -gt 0)
Check 'control: serial libraries are a violation' (@(Get-OrderViolations @('START library win32', 'END library win32', 'START library win64', 'END library win64')).Count -gt 0)

# A: the happy path.
$r = Invoke-Runner 'ok'
Check 'A1 exit 0' ($r.Exit -eq 0) "exit=$($r.Exit)"
$v = @(Get-OrderViolations $r.Calls)
Check 'A2 Q5 order: libraries parallel, then projects, then catch-up' ($v.Count -eq 0 -and $r.Calls.Count -eq 8) (($v -join '; ') + " calls=$($r.Calls.Count)")
Check 'A3 library args' (@($r.Calls | Where-Object { $_ -match '^START library win32 index --all --only Library --platform win32 --jobs 1' }).Count -eq 1) ($r.Calls -join ' | ')
Check 'A4 project args carry the section list' (@($r.Calls | Where-Object { $_ -match '^START projects .*--only P1,P2' }).Count -eq 1) ($r.Calls -join ' | ')
Check 'A5 last summary line is the done marker' ($r.Summary[-1] -ceq 'REPARSE DONE') ($r.Summary -join ' | ')
Check 'A6 first summary line says phase=done' ($r.Summary[0] -match '^REPARSE phase=done ')
$lib = $r.Seen['libraries']
Check 'A7 mid-run line: libraries phase carries a dated ETA' ($null -ne $lib -and $lib[0] -match 'eta=\d{4}-\d\d-\d\dT\d\d:\d\d \(left ') ($lib -join ' | ')
Check 'A8 mid-run progress counts stdout files against the DB total' ($null -ne $lib -and (($lib -join "`n") -match 'parsed 2/7000')) ($lib -join ' | ')
Check 'A9 mid-run: projects are waiting while libraries run' ($null -ne $lib -and (($lib -join "`n") -match '(?m)^projects\s+waiting')) ($lib -join ' | ')

# D: -Platforms through `pwsh -File` arrives as ONE comma string (wave 151 incident, O10): the script splits it.
$r = Invoke-Runner 'commas' '' @('-AllowBusy', '-Platforms', 'win32,win64')
$v = @(Get-OrderViolations $r.Calls)
Check 'D1 one comma string = two parallel libraries, exit 0' ($r.Exit -eq 0 -and $v.Count -eq 0 -and $r.Calls.Count -eq 8) ("exit=$($r.Exit) " + ($v -join '; ') + " calls=$($r.Calls.Count)")
Check 'D2 each platform got its own library call' (@($r.Calls | Where-Object { $_ -match '^START library win32 index --all --only Library --platform win32 ' }).Count -eq 1 -and @($r.Calls | Where-Object { $_ -match '^START library win64 index --all --only Library --platform win64 ' }).Count -eq 1) ($r.Calls -join ' | ')
# B: a failed library stops the run before the projects.
$r = Invoke-Runner 'fail' 'win64'
Check 'B1 exit 1' ($r.Exit -eq 1) "exit=$($r.Exit)"
Check 'B2 projects never started' (@($r.Calls | Where-Object { $_ -match '^START (projects|catchup)' }).Count -eq 0) ($r.Calls -join ' | ')
Check 'B3 the other library still ran to its end' (@($r.Calls | Where-Object { $_ -match '^END library win32' }).Count -eq 1) ($r.Calls -join ' | ')
Check 'B4 the summary names the failure' (($r.Summary[-1] -match '^REPARSE FAILED in phase libraries: library-win64=7') -and ($r.Summary -notcontains 'REPARSE DONE')) ($r.Summary -join ' | ')

# C: alone means alone. A renamed cmd.exe is a process that looks like a busy engine.
$fakeDir = Join-Path $Scratch 'busy'
[void][IO.Directory]::CreateDirectory($fakeDir)
$fake = Join-Path $fakeDir 'drag-lint.exe'
[IO.File]::Copy((Join-Path $env:SystemRoot 'System32\cmd.exe'), $fake, $true)
$busy = Start-Process $fake -ArgumentList 'index', '/c', 'ping -n 60 127.0.0.1' -PassThru -WindowStyle Hidden
try {
  $r = Invoke-Runner 'busy' '' @()
  Check 'C1 refuses with exit 3' ($r.Exit -eq 3) "exit=$($r.Exit)"
  Check 'C2 nothing was started' ($r.Calls.Count -eq 0) ($r.Calls -join ' | ')
  Check 'C3 the summary says why' ($r.Summary[0] -match '^REPARSE REFUSED') ($r.Summary -join ' | ')
  $r = Invoke-Runner 'busyok' '' @('-AllowBusy')
  Check 'C4 -AllowBusy runs and records it' ($r.Exit -eq 0 -and (($r.Summary -join "`n") -match 'NOT ALONE')) ($r.Summary -join ' | ')
} finally {
  if (-not $busy.HasExited) { & taskkill /PID $busy.Id /T /F 2>&1 | Out-Null }
}

"run_reparse_libraries_guard: $passes passed, $fails failed"
if ($fails -gt 0) { exit 1 }
exit 0
