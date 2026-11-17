# v1511 THR (B14 + THRA decode): exception-escapes-thread must not fire on a TTask.Run lambda whose task is later
# Waited / Result-read / passed to WaitForAll (an un-waited task still fires: positive control); and a UTF-8-BOM
# file with an invalid byte must still get THRA findings (the lane decoded through EnsureUtf8Bytes).
# Usage: pwsh -File tests/autotest/run_v1511_THR_waited_task_bom.ps1 -Exe <exe> -DbPath <db copy>
[CmdletBinding()]
param(
    [string] $Exe = (Join-Path $PSScriptRoot '..\..\third_party\dll-win64\drag-lint.exe'),
    [string] $DbPath
)
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    Write-Host ("  [{0}] {1} {2}" -f $(if ($Ok) {'PASS'} else {'FAIL'}), $Name, $Detail)
    if (-not $Ok) { $script:Failed = $true }
}
# No -DbPath: lint the loose file with no --db (read-only; the battery passes neither flag).
$DbArgs = if ($DbPath) { @('--db', $DbPath) } else { @() }
if (-not $Exe -or -not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe"; exit 2 }
$Fix = Join-Path $PSScriptRoot 'fixtures\v1511-THR'
function Lines([string]$File, [string]$Rule, [string[]]$Extra) {
    $raw = (& $Exe lint $File --rule $Rule @DbArgs --json @Extra 2>$null) -join "`n"
    $arr = @()
    if ($raw.Trim().StartsWith("[")) { try { $arr = @($raw | ConvertFrom-Json) } catch { } }
    return @($arr | ForEach-Object { [int]$_.start_line })
}
# waited.pas: NotWaitedAssigned (line 57), NotWaitedBare (line 67) and WaitsOtherTask T (line 78) are the only hits
$w = Join-Path $Fix 'waited.pas'
$got = @(Lines $w 'exception-escapes-thread')
Write-Host "  lines: $($got -join ',')"
Check 'W1 waited / WaitForAll / chained-Wait lambdas are quiet' (-not ($got | Where-Object { $_ -lt 50 })) ''
Check 'P1 positive control: un-waited assigned task fires' ($got -contains 57)
Check 'P2 positive control: bare TTask.Run fires' ($got -contains 67)
Check 'P3 positive control: task A waited does not hide task T' ($got -contains 78)
Check 'P4 exactly three findings' ($got.Count -eq 3) "n=$($got.Count)"
$off = @(Lines $w 'exception-escapes-thread' @('--disable', 'exception-escapes-thread'))
Check 'P5 --disable silences them' ($off.Count -eq 0)
# BOM + invalid bytes cannot live in the repo (encoding guard), so the file is generated here
$b = Join-Path ([IO.Path]::GetTempPath()) ("dl-v1511-thr-bom-$PID.pas")
$txt = "unit bomthr;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`nuses`r`n  System.Classes;`r`n`r`n// copyright XX`r`nprocedure NotStarted;`r`nvar`r`n  T: TThread;`r`nbegin`r`n  T:= TThread.CreateAnonymousThread(`r`n    procedure`r`n    begin`r`n    end);`r`nend;`r`n`r`nend.`r`n"
$bytes = [Text.Encoding]::ASCII.GetBytes($txt)
$at = $txt.IndexOf('XX'); $bytes[$at] = 0xAE; $bytes[$at + 1] = 0xA9
[IO.File]::WriteAllBytes($b, [byte[]](0xEF,0xBB,0xBF) + $bytes)
$bom = @(Lines $b 'anonymous-thread-not-started')
Check 'B1 BOM + invalid byte file still gets anonymous-thread-not-started' ($bom.Count -ge 1) "n=$($bom.Count)"
[IO.File]::Delete($b)
if ($script:Failed) { Write-Host 'FAILED'; exit 1 }
Write-Host 'PASSED'; exit 0
