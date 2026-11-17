# v1511 TLSPERF: rule tls-verification-disabled must not backtrack. The handler scan took 148-166 s on a 20k-line unit.
# Usage: run_v1511_TLSPERF.ps1 [-Exe <drag-lint.exe>] [-Source <big .pas>] [-DbPath <index DB>] [-MaxSeconds 10]
# (a) timing: `lint <copy of Source> --rule tls-verification-disabled --db <private copy of DbPath>` under -MaxSeconds.
# (b) behaviour: the tls-verification-disabled* fixtures of tests\lint stay green.
# Missing inputs SKIP (exit 77, battery-safe): the Source/DB are large and never guessed.
param(
  [string]$Exe = 'third_party\dll-win64\drag-lint.exe',
  [string]$Source = '',
  [string]$DbPath = $env:DL_V1511_DB,
  [double]$MaxSeconds = 10
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not [IO.Path]::IsPathRooted($Exe)) { $Exe = Join-Path $repo $Exe }
if (-not $Source) { $Source = Join-Path $repo 'src\storage\DRagLint.Storage.SQLite.pas' }
if (-not $DbPath) { Write-Host 'SKIP: no -DbPath and DL_V1511_DB unset'; exit 77 }
foreach ($p in @($Exe, $Source, $DbPath)) {
  if (-not (Test-Path -LiteralPath $p)) { Write-Host "SKIP: not found: $p"; exit 77 }
}
$fail = 0
$work = Join-Path $env:TEMP ('tlsperf-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
try {
  $srcCopy = Join-Path $work 'Big.pas'
  $dbCopy = Join-Path $work 'idx.sqlite'
  Copy-Item -LiteralPath $Source -Destination $srcCopy
  Copy-Item -LiteralPath $DbPath -Destination $dbCopy
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $proc = Start-Process -FilePath $Exe -ArgumentList @('lint', $srcCopy, '--rule', 'tls-verification-disabled', '--db', $dbCopy) `
    -PassThru -NoNewWindow -RedirectStandardOutput "$work\o.txt" -RedirectStandardError "$work\e.txt"
  $done = $proc.WaitForExit([int]($MaxSeconds * 1000) + 20000)
  $sw.Stop()
  if (-not $done) { $proc.Kill(); $proc.WaitForExit(10000) | Out-Null }
  $sec = [math]::Round($sw.Elapsed.TotalSeconds, 1)
  if ($done -and $sec -lt $MaxSeconds) { Write-Host "PASS timing: ${sec} s < $MaxSeconds s" }
  else { Write-Host "FAIL timing: $(if ($done) { "${sec} s" } else { "not finished after ${sec} s" }) >= $MaxSeconds s"; $fail++ }
  $out = & (Join-Path $repo 'tests\lint\run_lint_tests.ps1') -Exe $Exe -Filter 'tls-verification-disabled*' 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0 -and $out -notmatch 'FAIL') { Write-Host 'PASS behaviour: tls-verification-disabled fixtures' }
  else { Write-Host "FAIL behaviour: $($out.Trim() -replace '\s+', ' ')"; $fail++ }
} finally {
  try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "note: scratch left at $work" }
}
if ($fail -gt 0) { Write-Host "RESULT: $fail FAIL"; exit 1 }
Write-Host 'RESULT: PASS'
