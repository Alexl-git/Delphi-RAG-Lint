# drag-lint code-built menu reader: console unit tests (tests\MenuTreeTests.dpr).
#
# Compiles MenuTreeTests.dpr with dcc64 exactly as run_coherence.ps1 compiles
# its harness (search path + unit scopes read from src\cli\drag-lint.dproj),
# indexes the tests\fixtures\menutree fixture into a SCRATCH DB with an explicit
# --db (never a live index), indexes a second scratch COPY in which the item
# helper AddItem is renamed PutItem everywhere (spec 11 control 4), and runs the
# exe with both DBs.
#
# Cannot pass vacuously: PASS needs exit code 0 AND the exe's own last line
# "menutree-tests: N passed, 0 failed" with N at least MIN_TESTS; a harness that
# crashed, printed nothing or ran fewer tests than it should fails.
#
# Usage: pwsh -File tests/autotest/run_menu_tree_tests.ps1 [-Exe <drag-lint.exe>]
[CmdletBinding()]
param(
    [string] $Exe        = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $FixtureDir = "$PSScriptRoot\..\fixtures\menutree",
    [string] $WorkDir    = "$env:TEMP\drag-lint-menu-tree-tests-$PID",
    [int]    $MinTests   = 65
)
try {
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$testsDir = (Resolve-Path "$PSScriptRoot\..").Path
$fixture  = (Resolve-Path $FixtureDir).Path

# --- scratch fixture DB, and the renamed-helper copy (control 4) ---
$db = "$WorkDir\fixture.sqlite"
& $Exe index --project "$fixture\MenuTreeFixture.dproj" --db $db *> "$WorkDir\index.log"
if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: fixture index failed (exit $LASTEXITCODE), see $WorkDir\index.log" -ForegroundColor Red; exit 2 }
$renamed = "$WorkDir\renamed"
Copy-Item -LiteralPath $fixture -Destination $renamed -Recurse
$b = "$renamed\MT.Builder.pas"
$txt = [IO.File]::ReadAllText($b)
$txt2 = [regex]::Replace($txt, '\bAddItem\b', 'PutItem')
if ($txt2 -eq $txt) { Write-Host 'FATAL: rename control changed nothing' -ForegroundColor Red; exit 2 }
[IO.File]::WriteAllText($b, $txt2, [Text.ASCIIEncoding]::new())
$dbRenamed = "$WorkDir\renamed.sqlite"
& $Exe index --project "$renamed\MenuTreeFixture.dproj" --db $dbRenamed *> "$WorkDir\index-renamed.log"
if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: renamed-copy index failed (exit $LASTEXITCODE)" -ForegroundColor Red; exit 2 }

# --- build the test exe ---
$rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
. (Join-Path $PSScriptRoot 'lib\CliBuildPaths.ps1')
$uArgs  = (Get-CliDcc64Args).Args
$outDir = "$WorkDir\bin"
New-Item -ItemType Directory -Force $outDir | Out-Null
$batPath = "$WorkDir\build_tests.bat"
$logPath = "$WorkDir\build_tests.log"
$batLines = @(
    '@echo off'
    "call `"$rsvars`""
    "cd /d `"$testsDir`""
    "dcc64 -CC $uArgs -E`"$outDir`" -N0`"$outDir`" MenuTreeTests.dpr"
    'echo BUILD_EXITCODE=%ERRORLEVEL%'
)
[IO.File]::WriteAllText($batPath, ($batLines -join "`r`n"), [Text.Encoding]::ASCII)
Start-Process cmd.exe -ArgumentList '/c', "`"$batPath`"" -RedirectStandardOutput $logPath `
    -RedirectStandardError "$logPath.err" -NoNewWindow -Wait | Out-Null
$log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
$testExe = "$outDir\MenuTreeTests.exe"
if (($log -notmatch 'BUILD_EXITCODE=0') -or ($log -match 'Error:') -or -not (Test-Path $testExe)) {
    Write-Host "FAIL: MenuTreeTests.dpr does not build -- see $logPath" -ForegroundColor Red
    ($log -split "`r?`n" | Select-String 'Error|Fatal' | Select-Object -First 10) | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Copy-TreeSitterDlls -Dest $outDir | Out-Null

# --- run ---
$out = @(& $testExe $db $fixture $dbRenamed 2>&1 | ForEach-Object { "$_" })
$code = $LASTEXITCODE
$out | ForEach-Object { Write-Host $_ }
$last = ($out | Where-Object { $_ -match '^menutree-tests:' } | Select-Object -Last 1)
$ok = ($code -eq 0) -and ($last -match '^menutree-tests: (\d+) passed, 0 failed$') -and ([int]$Matches[1] -ge $MinTests)
Write-Host ''
if ($ok) { Write-Host "PASS run_menu_tree_tests ($last)" -ForegroundColor Green; exit 0 }
Write-Host "FAIL run_menu_tree_tests (exit $code; '$last'; need >= $MinTests tests)" -ForegroundColor Red
exit 1
} catch {
    Write-Host "FAIL run_menu_tree_tests: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
