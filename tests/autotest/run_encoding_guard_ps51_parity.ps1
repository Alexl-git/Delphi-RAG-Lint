<#
  run_encoding_guard_ps51_parity.ps1 -- run_encoding_guard.ps1 must give the SAME verdict and
  scan the SAME files under Windows PowerShell 5.1 (powershell.exe) and pwsh 7 (1.52.2).

  Until 1.52.2 it did not: 5.1 ignores -Include under -LiteralPath (every file matched, so
  features\ rules\ skills\ SVG\ read as unaccounted directories -> FAIL) and its -Filter also
  matches 8.3 short names (5098 files scanned against 4993). Skips when either shell is absent.
#>
$ErrorActionPreference = 'Stop'
$guard = Join-Path $PSScriptRoot 'run_encoding_guard.ps1'
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$pw = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not (Test-Path $ps51) -or $null -eq $pw) { 'SKIP: needs both powershell.exe 5.1 and pwsh 7'; exit 0 }

function Invoke-Guard([string]$Shell, [string[]]$Pre) {
  $out = & { $ErrorActionPreference = 'Continue'; & $Shell @Pre -File $guard 2>&1 | ForEach-Object { "$_" } }
  $code = $LASTEXITCODE
  $scanned = ($out | Select-String 'files scanned \((\d+)\)' | Select-Object -First 1)
  [pscustomobject]@{
    Exit = $code
    Verdict = ($out | Where-Object { $_ -match '^ENCODING GUARD: ' } | Select-Object -Last 1)
    Scanned = if ($scanned) { [int]$scanned.Matches[0].Groups[1].Value } else { -1 }
    Fails = @($out | Where-Object { $_ -match '^\s*\[FAIL\]' })
  }
}

$a = Invoke-Guard $ps51 @('-NoProfile', '-ExecutionPolicy', 'Bypass')
$b = Invoke-Guard $pw.Source @('-NoProfile')
$fails = 0; $passes = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:passes++; "PASS $Name" } else { $script:fails++; "FAIL $Name $Detail" }
}
Check 'P1 same verdict' ($a.Verdict -eq $b.Verdict -and $a.Exit -eq $b.Exit) "5.1=[$($a.Verdict) exit $($a.Exit)] 7=[$($b.Verdict) exit $($b.Exit)] 5.1 fails: $($a.Fails -join ' | ')"
Check 'P2 same number of files scanned' ($a.Scanned -eq $b.Scanned -and $a.Scanned -gt 0) "5.1=$($a.Scanned) 7=$($b.Scanned)"
"run_encoding_guard_ps51_parity: $passes passed, $fails failed"
if ($fails -gt 0) { exit 1 }
exit 0
