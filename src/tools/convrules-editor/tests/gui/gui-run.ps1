# gui-run.ps1 -- the ONE way to run a GUI driver under gui-lock (GUILOCK: runners ignored the -Acquire timeout).
# Usage: gui-run.ps1 -Driver <drive-*.ps1> [-Owner <name>] [-LockWaitMin 10] [-TimeoutMin 15] [-LockFile <path>] [-DriverArgs <string[]>]
# 1. gui-lock -Acquire -MaxWaitMin LockWaitMin. Exit 1 from it (TIMEOUT) is FINAL here: no retry loop; this script
#    exits 3 ("LOCK-TIMEOUT") and the caller must report the proof BLOCKED, not loop.
# 2. Runs the driver as a child process; past TimeoutMin the child's whole process TREE is killed (exit 4, "DRIVER-TIMEOUT").
# 3. Always releases the lock. Exit: the driver's own exit code, 3 or 4.
param([Parameter(Mandatory)][string]$Driver, [string]$Owner = 'gui-run', [double]$LockWaitMin = 10, [double]$TimeoutMin = 15,
      [string]$LockFile = 'C:\TEMP\claude\lanes\gui.lock', [string[]]$DriverArgs = @())
$ErrorActionPreference = 'Stop'
$lock = Join-Path $PSScriptRoot 'gui-lock.ps1'
$ps = (Get-Process -Id $PID).Path
$out = & $ps -NoProfile -File $lock -Acquire -Owner $Owner -LockFile $LockFile -MaxWaitMin $LockWaitMin
if ($LASTEXITCODE -ne 0) { Write-Output "LOCK-TIMEOUT: $($out -join ' ')"; exit 3 }
$code = 0
try {
  $argl = @('-NoProfile', '-File', $Driver) + $DriverArgs
  $p = Start-Process -FilePath $ps -ArgumentList $argl -PassThru -NoNewWindow
  if (-not $p.WaitForExit([int]($TimeoutMin * 60000))) {
    & taskkill.exe /PID $p.Id /T /F | Out-Null
    Write-Output "DRIVER-TIMEOUT after $TimeoutMin min; process tree $($p.Id) killed"
    $code = 4
  } else { $code = $p.ExitCode }
} finally {
  & $ps -NoProfile -File $lock -Release -Owner $Owner -LockFile $LockFile | Out-Null
}
exit $code