# v1511 ENC (B07): lint of a UTF-8-BOM file that carries an invalid UTF-8 byte must not die FATAL EEncodingError.
# Usage: pwsh -File tests/autotest/run_v1511_ENC_bom_invalid_byte.ps1 -Exe <exe> -DbPath <db copy>
[CmdletBinding()]
param(
    [string] $Exe,
    [string] $DbPath,
    [string] $WorkDir = "$env:TEMP\drag-lint-v1511-enc-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    Write-Host ("  [{0}] {1} {2}" -f $(if ($Ok) {'PASS'} else {'FAIL'}), $Name, $Detail)
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe"; exit 2 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$f = Join-Path $WorkDir 'BomBad.pas'
$lines = [Text.Encoding]::ASCII.GetBytes("unit BomBad;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`n// x")
$bytes = [byte[]](0xEF,0xBB,0xBF) + $lines + [byte[]](0xE9) + [Text.Encoding]::ASCII.GetBytes("y`r`n`r`nend.`r`n")
[IO.File]::WriteAllBytes($f, $bytes)
$out = (& $Exe lint $f --db $DbPath 2>&1 | Out-String)
$code = $LASTEXITCODE
Check 'no FATAL / EEncodingError' (($out -notmatch 'FATAL') -and ($out -notmatch 'EEncodingError')) ($out.Substring(0,[Math]::Min(120,$out.Length)))
Check 'exit code 0 or 1' (($code -eq 0) -or ($code -eq 1)) "exit=$code"
if ($script:Failed) { Write-Host 'FAILED'; exit 1 }
Write-Host 'PASSED'; exit 0
