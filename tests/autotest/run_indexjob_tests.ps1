# IndexJobTests.dpr guard: builds the console test with dcc64 and runs it.
#
# Why: tests\IndexJobTests.dpr pins the save-time reindex command line, the coalesce key and
# the target-DB refusal rules (PLAN-lint-tree P4), but nothing in the autotest battery built or
# ran it. Also holds ONE static check the console test cannot make (QueueReindexJob lives in
# SaveNotifier, which needs ToolsAPI): a reindex job must NOT re-lint from its own OnDone,
# because JobQueue already calls GReindexDoneHook (-> RequestRelint) after every jkReindex job;
# doing both re-lints twice per save.
#
# Cannot pass vacuously: PASS needs exit 0 AND the exe's last line "N passed, 0 failed" with N
# at least MIN_TESTS, AND the static check, whose extractor is proven on a known-bad body first.
#
# Usage: pwsh -File tests/autotest/run_indexjob_tests.ps1
[CmdletBinding()]
param(
    [string] $WorkDir  = "$env:TEMP\drag-lint-indexjob-tests-$PID",
    [int]    $MinTests = 34
)
try {
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$testsDir = "$repo\tests"
New-Item -ItemType Directory -Force $WorkDir | Out-Null

# --- static check: no RequestRelint inside QueueReindexJob ---
function Get-QueueReindexBody([string] $Text) {
    $m = [regex]::Match($Text, '(?s)\nfunction QueueReindexJob\b.*?\r?\nend;')
    if ($m.Success) { $m.Value } else { '' }
}
function Test-NoRelintInBody([string] $Body) { ($Body -ne '') -and ($Body -match 'BuildProjectIndexJob') -and ($Body -notmatch 'RequestRelint') }
$bad = "`nfunction QueueReindexJob(a: string): Boolean;`nbegin`n  Job:= BuildProjectIndexJob(a);`n  Job.OnDone:= procedure begin RequestRelint; end;`nend;`n"
if (Test-NoRelintInBody (Get-QueueReindexBody $bad)) { Write-Host 'FAIL: static check cannot fail (positive control)' -ForegroundColor Red; exit 1 }
$src = [IO.File]::ReadAllText("$repo\src\delphi-plugin\DragLint.Plugin.SaveNotifier.pas")
$staticOk = Test-NoRelintInBody (Get-QueueReindexBody $src)
if (-not $staticOk) { Write-Host 'FAIL: QueueReindexJob re-lints in its own OnDone (double re-lint with GReindexDoneHook), or the body was not found' -ForegroundColor Red }

# --- build ---
$rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
. (Join-Path $PSScriptRoot 'lib\CliBuildPaths.ps1')
$uArgs  = (Get-CliDcc64Args).Args
$outDir = "$WorkDir\bin"; $dcuDir = "$WorkDir\dcu"
New-Item -ItemType Directory -Force $outDir, $dcuDir | Out-Null
$batPath = "$WorkDir\build_tests.bat"; $logPath = "$WorkDir\build_tests.log"
$batLines = @(
    '@echo off'
    "call `"$rsvars`""
    "cd /d `"$testsDir`""
    "dcc64 -CC -B $uArgs -E`"$outDir`" -N0`"$dcuDir`" -NU`"$dcuDir`" IndexJobTests.dpr"
    'echo BUILD_EXITCODE=%ERRORLEVEL%'
)
[IO.File]::WriteAllText($batPath, ($batLines -join "`r`n"), [Text.Encoding]::ASCII)
Start-Process cmd.exe -ArgumentList '/c', "`"$batPath`"" -RedirectStandardOutput $logPath `
    -RedirectStandardError "$logPath.err" -NoNewWindow -Wait | Out-Null
$log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
$testExe = "$outDir\IndexJobTests.exe"
if (($log -notmatch 'BUILD_EXITCODE=0') -or ($log -match 'Error:') -or -not (Test-Path $testExe)) {
    Write-Host "FAIL: IndexJobTests.dpr does not build -- see $logPath" -ForegroundColor Red
    ($log -split "`r?`n" | Select-String 'Error|Fatal' | Select-Object -First 10) | ForEach-Object { Write-Host "  $_" }
    exit 1
}

# --- run ---
$out = @(& $testExe 2>&1 | ForEach-Object { "$_" })
$code = $LASTEXITCODE
$out | Where-Object { $_ -match '^FAIL|passed' } | ForEach-Object { Write-Host $_ }
$last = ($out | Where-Object { $_ -match '^\d+ passed, \d+ failed$' } | Select-Object -Last 1)
$ok = $staticOk -and ($code -eq 0) -and ($last -match '^(\d+) passed, 0 failed$') -and ([int]$Matches[1] -ge $MinTests)
if ($ok) { Write-Host "PASS run_indexjob_tests ($last)" -ForegroundColor Green; exit 0 }
Write-Host "FAIL run_indexjob_tests (exit $code; '$last'; static=$staticOk; need >= $MinTests tests)" -ForegroundColor Red
exit 1
} catch {
    Write-Host "FAIL run_indexjob_tests: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}