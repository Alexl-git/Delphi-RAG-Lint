<#
  run_cwd_stray_file_guard.ps1 -- 152 TESTS: a runner must leave NOTHING behind in the cwd it was started from
  (scratch belongs under $env:TEMP). Each runner is started from a fresh EMPTY directory with the engine under test;
  any file or folder in that directory afterwards is a stray and fails the guard.

  POSITIVE CONTROL: a fixture runner that drops a file into its cwd MUST be flagged; a clean fixture must not.
  Exit 0 = pass, 1 = a stray or a failed control, 2 = setup.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Exe,
  [string[]]$Runners = @(
    'run_v1511_RES_function_result_receiver.ps1', 'run_v1511_RES_library_reads.ps1', 'run_v1511_RES_parenless_library_call.ps1',
    'run_v151_TXT_chars.ps1')
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n, $d)
  if (-not $ok) { $script:fail = $true }
}
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe"; exit 2 }
$exeP = (Resolve-Path $Exe).Path
$base = Join-Path $env:TEMP "dl-cwdstray-$PID"
[IO.Directory]::CreateDirectory($base) | Out-Null

# Runs one script from a fresh empty cwd; returns the names left behind in that cwd.
function Get-Strays([string]$Script, [string[]]$ScriptArgs, [string]$Tag) {
  $cwd = Join-Path $base $Tag
  [IO.Directory]::CreateDirectory($cwd) | Out-Null
  Push-Location $cwd
  try { $null = & pwsh -NoProfile -NonInteractive -File $Script @ScriptArgs 2>&1 } finally { Pop-Location }
  return @(Get-ChildItem -LiteralPath $cwd -Force | ForEach-Object { $_.Name })
}

$dirty = Join-Path $base 'fixture-dirty.ps1'; $clean = Join-Path $base 'fixture-clean.ps1'
[IO.File]::WriteAllText($dirty, "'x' | Set-Content -Path stray.txt`r`n", [Text.Encoding]::ASCII)
[IO.File]::WriteAllText($clean, "`$null = 1`r`n", [Text.Encoding]::ASCII)
Check 'CONTROL: a runner that writes into its cwd is flagged' ((Get-Strays $dirty @() 'ctl-dirty') -contains 'stray.txt')
Check 'CONTROL: a clean runner is not flagged' ((Get-Strays $clean @() 'ctl-clean').Count -eq 0)

foreach ($r in $Runners) {
  $path = Join-Path $PSScriptRoot $r
  if (-not (Test-Path -LiteralPath $path)) { Check "$r exists" $false; continue }
  $s = Get-Strays $path @('-Exe', $exeP) ([IO.Path]::GetFileNameWithoutExtension($r))
  Check "$r leaves nothing in its cwd" ($s.Count -eq 0) ($s -join ',')
}
if ($script:fail) { Write-Host 'run_cwd_stray_file_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_cwd_stray_file_guard: PASS' -ForegroundColor Green; exit 0