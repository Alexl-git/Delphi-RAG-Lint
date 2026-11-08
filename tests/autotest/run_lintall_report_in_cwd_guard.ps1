<#
  run_lintall_report_in_cwd_guard.ps1 -- without --output / --project, lint-all writes its
  lint-report-<date>.txt in the CURRENT directory, never beside the DB (148 IX, 144 qsmall).

  WHY. 144 qsmall ran lint-all against the real src\cli index and found lint-report-20261105.txt in the
  main tree's src\cli\_D-RAG: a report file beside a SHARED database, overwritten by every caller's run
  of the day.

    R1 the report is in the current directory                (RED before the fix)
    R2 nothing was written beside the DB                     (RED before the fix)
    R3 CONTROL: --output <file> still writes exactly there

  Scratch only (-WorkDir). pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-report-cwd-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name  $Detail" } else { Write-Host "FAIL  $Name  $Detail" -ForegroundColor Red; $script:Failed = $true }
}
function Invoke-Engine([string[]]$ArgList, [string]$Cwd) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  foreach ($a in $ArgList) { $psi.ArgumentList.Add($a) }
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $Cwd
  $p = [System.Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit(120000)) { try { $p.Kill($true) } catch { } }
  $p.WaitForExit()
  return @{ Code = $p.ExitCode; Text = $o.Result + $e.Result }
}

try {
  if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
  $Exe = (Resolve-Path $Exe).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $src = Join-Path $WorkDir 'src'; $dbDir = Join-Path $WorkDir 'shared\_D-RAG'; $cwd = Join-Path $WorkDir 'caller'
  foreach ($d in $src, $dbDir, $cwd) { New-Item -ItemType Directory $d -Force | Out-Null }
  $t = "unit RepUnit;`r`n`r`ninterface`r`n`r`nprocedure Noisy;`r`n`r`nimplementation`r`n`r`nprocedure Noisy;`r`nvar`r`n  Unused: Integer;`r`nbegin`r`nend;`r`n`r`nend.`r`n"
  [IO.File]::WriteAllText((Join-Path $src 'RepUnit.pas'), $t, [Text.Encoding]::ASCII)
  $db = Join-Path $dbDir 'rep.sqlite'
  $first = Invoke-Engine @('index', $src, '--db', $db) $WorkDir
  if ($first.Code -ne 0) { Write-Host "FATAL: setup index failed: $($first.Text)" -ForegroundColor Red; exit 2 }
  $stamp = Get-Date -Format 'yyyyMMdd'
  $name = "lint-report-$stamp.txt"

  $r = Invoke-Engine @('lint-all', '--db', $db) $cwd
  Check 'R1 the report is in the current directory' (Test-Path (Join-Path $cwd $name)) "exit=$($r.Code)"
  Check 'R2 nothing was written beside the DB' (-not (Test-Path (Join-Path $dbDir $name))) $dbDir

  $out = Join-Path $WorkDir 'explicit.txt'
  $null = Invoke-Engine @('lint-all', '--db', $db, '--output', $out) $cwd
  Check 'R3 CONTROL: --output writes exactly there' (Test-Path $out) $out
}
finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
if ($script:Failed) { Write-Host 'run_lintall_report_in_cwd_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lintall_report_in_cwd_guard: PASS'
exit 0
