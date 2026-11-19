# v152 FPS: three FP/FN fixes, each RED-first with a control twin.
#  1 exception-escapes-thread: inline `var T := TTask.Run(..)` later Waited / WaitForAll'd is quiet;
#    un-waited inline twins still fire (tests\lint\exception-escapes-thread-inline-var.pas).
#  2 duplicate-code: a clone starting on the closing `end;` of a different statement is anchored on the
#    first statement after it (tests\lint\duplicate-code-end-anchor.pas).
#  3 RefTypeRules.DescentOf: a class whose library base TFrame is a homonym answers tdUnknown, never tdNo,
#    so blocking-call-in-main-thread keeps the spelling verdict; unique-base twins stay tdYes / tdNo
#    (fixtures\v152-FPS: a scratch library index + project index are built here).
# Usage: pwsh -File tests/autotest/run_v152_FPS.ps1 -Exe <exe> [-Work <scratch dir>]
[CmdletBinding()]
param(
    [string] $Exe = '',
    [string] $Work = (Join-Path ([IO.Path]::GetTempPath()) "dl-v152-fps-$PID")
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = (Join-Path $PSScriptRoot '..\..\src\cli\Win64\Debug\drag-lint.exe') }
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    Write-Host ("  [{0}] {1} {2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $Detail)
    if (-not $Ok) { $script:Failed = $true }
}
if (-not $Exe -or -not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe"; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Lint = Join-Path $PSScriptRoot '..\lint'
$Fix = Join-Path $PSScriptRoot 'fixtures\v152-FPS'
$null = New-Item -ItemType Directory -Force $Work
Push-Location $Work
try {
    function Lines([string[]]$LintArgs) {
        $raw = (& { $ErrorActionPreference = 'Continue'; & $Exe lint @LintArgs --json 2>$null }) -join "`n"
        $arr = @()
        if ($raw.Trim().StartsWith('[')) { try { $arr = @(($raw | ConvertFrom-Json) | ForEach-Object { $_ }) } catch { } }
        return @($arr | ForEach-Object { [int]$_.start_line })
    }

    Write-Host '1 exception-escapes-thread: inline var task'
    $f1 = Join-Path $Lint 'exception-escapes-thread-inline-var.pas'
    $g1 = @(Lines @($f1, '--rule', 'exception-escapes-thread'))
    Write-Host "  lines: $($g1 -join ',')"
    Check 'T1 inline var T := TTask.Run; T.Wait is quiet' (-not ($g1 -contains 20))
    Check 'T2 inline typed var passed to TTask.WaitForAll is quiet' (-not ($g1 -contains 30))
    Check 'T3 control: un-waited inline var fires' ($g1 -contains 40)
    Check 'T4 control: un-waited inline typed var fires' ($g1 -contains 50)

    Write-Host '2 duplicate-code: no anchor on end;'
    $f2 = Join-Path $Lint 'duplicate-code-end-anchor.pas'
    $c2 = Join-Path $Lint 'duplicate-code-end-anchor.config.json'
    $g2 = @(Lines @($f2, '--rule', 'duplicate-code', '--config', $c2))
    Write-Host "  lines: $($g2 -join ',')"
    Check 'D1 not anchored on the closing end; (35)' (-not ($g2 -contains 35))
    Check 'D2 control: the clone is still reported, on its first statement (36)' ($g2 -contains 36)
    $c0 = Join-Path $Lint 'duplicate-code.config.json'
    $g0 = @(Lines @((Join-Path $Lint 'duplicate-code.pas'), '--rule', 'duplicate-code', '--config', $c0))
    Check 'D3 control: a clone that starts on a header keeps its anchor (20)' ($g0 -contains 20) "lines=$($g0 -join ',')"

    Write-Host '3 DescentOf on a library homonym TFrame'
    $lib = Join-Path $Work 'fps-lib.sqlite'
    $prj = Join-Path $Work 'fps-proj.sqlite'
    foreach ($d in @($lib, $prj)) { if (Test-Path $d) { [IO.File]::Delete($d) } }
    $null = & { $ErrorActionPreference = 'Continue'; & $Exe index (Join-Path $Fix 'lib') --db $lib 2>&1 | ForEach-Object { "$_" } }
    $null = & { $ErrorActionPreference = 'Continue'; & $Exe index (Join-Path $Fix 'proj') --db $prj --library-db $lib 2>&1 | ForEach-Object { "$_" } }
    $f3 = Join-Path $Fix 'proj\uFpsFrames.pas'
    $g3 = @(Lines @($f3, '--db', $prj, '--library-db', $lib, '--rule', 'blocking-call-in-main-thread'))
    Write-Host "  lines: $($g3 -join ',')"
    Check 'R1 class(TFrame) with a homonym TFrame is not proven a non-frame: fires (39)' ($g3 -contains 39)
    Check 'R2 control: unique base that descends TCustomFrame fires (44)' ($g3 -contains 44)
    Check 'R3 control: unique base proven not a form/frame stays quiet (49)' (-not ($g3 -contains 49))
    $g3n = @(Lines @($f3, '--rule', 'blocking-call-in-main-thread'))
    Check 'R4 control: without an index the spelling decides (all three fire)' ($g3n.Count -eq 3) "n=$($g3n.Count)"
}
finally {
    Pop-Location
}
if ($script:Failed) { Write-Host 'FAILED'; exit 1 }
Write-Host 'PASSED'; exit 0