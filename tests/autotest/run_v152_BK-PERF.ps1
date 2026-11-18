# run_v152_BK-PERF.ps1 -- lane BK-PERF (1.52) guards.
#   B17: lint-all --no-stand-down keeps a measurement run whole: a maintenance stand-down
#        (`shutdown --db <db>`) does not truncate it to PARTIAL / exit 4. Positive control:
#        the same run WITHOUT the flag still stands down with exit 4.
# Usage: run_v152_BK-PERF.ps1 [-Exe <drag-lint.exe>] [-WorkDir <dir>]
param(
  [string]$Exe = '',
  [string]$WorkDir = (Join-Path $env:TEMP ('dl-bkperf-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)))
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = (Join-Path $PSScriptRoot '..\..\src\cli\Win64\Debug\drag-lint.exe') }
$ErrorActionPreference = 'Stop'
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$script:Pass = 0; $script:Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "PASS $Name" -ForegroundColor Green }
  else { $script:Fail++; Write-Host "FAIL $Name  $Detail" -ForegroundColor Red }
}
function WriteAscii([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, [Text.Encoding]::ASCII) }
function WaitUntil([scriptblock]$Cond, [int]$Ms) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.ElapsedMilliseconds -lt $Ms) { if (& $Cond) { return $true }; Start-Sleep -Milliseconds 200 }
  return (& $Cond)
}
function Start-Lint([string[]]$LintArgs, [string]$Tag) {
  $out = Join-Path $WorkDir "$Tag.out"; $err = Join-Path $WorkDir "$Tag.err"
  $psi = [Diagnostics.ProcessStartInfo]::new($Exe)
  foreach ($a in $LintArgs) { $psi.ArgumentList.Add($a) }
  $psi.UseShellExecute = $false
  $psi.Environment['DRAGLINT_TEST_LINT_FILE_DELAY_MS'] = '300'
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $p = [Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  return [pscustomobject]@{ P = $p; Out = $o; Err = $e }
}

# ---- fixture: 40 trivial units, indexed into a private DB ----
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force $src | Out-Null
for ($i = 1; $i -le 40; $i++) {
  WriteAscii (Join-Path $src "PerfUnit$i.pas") ("unit PerfUnit$i;`r`n`r`ninterface`r`n`r`nprocedure P$i;`r`n`r`nimplementation`r`n`r`nprocedure P$i;`r`nbegin`r`nend;`r`n`r`nend.`r`n")
}
$db = Join-Path $WorkDir 'perf.sqlite'
& $Exe index $src --db $db *> (Join-Path $WorkDir 'index.log')
Check 'F0 fixture indexed' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"

Write-Host 'B17: lint-all --no-stand-down is not truncated by a stand-down' -ForegroundColor Cyan
$refOut = & $Exe lint-all --db $db 2>$null | Out-String
$refCode = $LASTEXITCODE
Check 'B17r reference run (undisturbed, no flag) finished, not stood down' ($refCode -ne 4) "exit $refCode"
foreach ($case in @(@{ Tag = 'ctl'; Flag = $false }, @{ Tag = 'nsd'; Flag = $true })) {
  $la = @('lint-all', '--db', $db)
  if ($case.Flag) { $la += '--no-stand-down' }
  $r = Start-Lint $la $case.Tag
  $null = WaitUntil { $r.P.HasExited -or ((Get-Process -Id $r.P.Id -EA SilentlyContinue) -and $r.P.TotalProcessorTime.TotalMilliseconds -gt 0) } 5000
  Start-Sleep -Milliseconds 2500   # well inside the scan (40 files x 300 ms)
  $sd = & $Exe shutdown --db $db --wait 5 2>&1 | Out-String
  $done = WaitUntil { $r.P.HasExited } 60000
  $code = if ($done) { $r.P.ExitCode } else { 'running' }
  $errT = $r.Err.Result
  if ($case.Flag) {
    Check 'B17a --no-stand-down: lint-all finished with the undisturbed run''s exit code (not the stand-down 4)' ($done -and ($code -eq $refCode)) "code=$code shutdown=[$sd] err=[$errT]"
    Check 'B17b --no-stand-down: no PARTIAL on stderr' ($errT -notmatch 'PARTIAL') $errT
    Check 'B17d --no-stand-down: stdout identical to the undisturbed run' ($r.Out.Result -eq $refOut) ''
    Check 'B17c --no-stand-down: no control pipe announced (a stand-down cannot reach it)' ($errT -notmatch 'control channel listening') $errT
  } else {
    Check 'B17p POSITIVE CONTROL: without the flag the same run stands down with exit 4' ($done -and ($code -eq 4)) "code=$code shutdown=[$sd]"
  }
}

Write-Host ''
Write-Host "run_v152_BK-PERF: $script:Pass pass, $script:Fail FAIL"
if ($script:Fail -gt 0) { exit 1 } else { exit 0 }
