<#
  run_v151_STY_fixes.ps1 -- lane STY autofix guard (boolean-assign-if).
  The fix replaces `if C then V := True else V := False` by `V := C` (and the negated
  form by `V := not (C)`). Apply test = real bytes written, compared with the
  expected file; the fixed unit must still compile (dcc64) and the rule must be
  quiet afterwards. Positive control: the unfixed fixture does report the rule.
  Usage: pwsh -File tests\autotest\run_v151_STY_fixes.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = (Join-Path $PSScriptRoot '..\..\src\cli\Win64\Debug\drag-lint.exe') }
$ErrorActionPreference = 'Stop'
$exePath = (Resolve-Path $Exe).Path
$fxDir = Join-Path $PSScriptRoot '..\autofix\fixtures\boolean-assign-if'
$scratch = Join-Path $env:TEMP ("v151_sty_fix_" + $PID)
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$fail = 0
function Check([string]$Name, [bool]$Ok) {
  if ($Ok) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name" -ForegroundColor Red; $script:fail++ }
}
try {
  $src = Join-Path $fxDir 'basic.pas'
  $exp = Join-Path $fxDir 'basic.fixed.pas'
  $tgt = Join-Path $scratch 'basic.pas'
  Copy-Item $src $tgt -Force
  $before = & $exePath lint $tgt --enable boolean-assign-if --json 2>$null | Out-String | ConvertFrom-Json
  Check 'control: unfixed fixture reports boolean-assign-if x4' (@($before | Where-Object { $_.rule -eq 'boolean-assign-if' }).Count -eq 4)
  & $exePath lint --file $tgt --fix --apply --no-backup --enable boolean-assign-if 2>&1 | Out-Null
  $got = [IO.File]::ReadAllText($tgt) -replace "`r`n", "`n"
  $want = [IO.File]::ReadAllText($exp) -replace "`r`n", "`n"
  Check 'applied bytes equal the expected fixed unit' ($got -eq $want)
  $after = & $exePath lint $tgt --enable boolean-assign-if --json 2>$null | Out-String | ConvertFrom-Json
  Check 'fixed unit no longer reports the rule' (@($after | Where-Object { $_.rule -eq 'boolean-assign-if' }).Count -eq 0)
  $dcc = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
  if (Test-Path $dcc) {
    $lib = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\lib\win64\release'
    Push-Location $scratch
    try { $o = & $dcc -Q -NSSystem "-U$lib" 'basic.pas' 2>&1 | Out-String; Check 'fixed unit compiles (dcc64)' ($o -match 'lines,' -and $o -notmatch 'Error') } finally { Pop-Location }
  } else { Write-Host 'SKIP compile gate: dcc64 not found' }
} finally {
  if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
if ($fail -gt 0) { Write-Host "FAIL ($fail)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
