# v1511 lint phase budget: no lint phase may dominate a big unit. A v151 rule took 148-166 s on a 20k-line file.
# Usage: run_v1511_lint_phase_budget.ps1 [-Exe <drag-lint.exe>] [-Source <big .pas>] [-DbPath <index DB>]
#        [-MaxPhaseSeconds 15] [-MaxTotalSeconds 60]
# Runs `lint <copy of Source> --db <private copy of DbPath> --enable <slow rule set>` with DRAGLINT_PROFILE=1, prints the
# [lint-phase] table, FAILs when a phase or the total exceeds its budget. Positive control: with a 0.0001 s phase budget
# the same table must FAIL, proving the check can fail. Missing inputs SKIP (exit 77).
param(
  [string]$Exe = 'third_party\dll-win64\drag-lint.exe',
  [string]$Source = '',
  [string]$DbPath = $env:DL_V1511_DB,
  [double]$MaxPhaseSeconds = 15,
  [double]$MaxTotalSeconds = 60
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not [IO.Path]::IsPathRooted($Exe)) { $Exe = Join-Path $repo $Exe }
if (-not $Source) { $Source = Join-Path $repo 'src\storage\DRagLint.Storage.SQLite.pas' }
if (-not $DbPath) { Write-Host 'SKIP: no -DbPath and DL_V1511_DB unset'; exit 77 }
foreach ($p in @($Exe, $Source, $DbPath)) {
  if (-not (Test-Path -LiteralPath $p)) { Write-Host "SKIP: not found: $p"; exit 77 }
}
$work = Join-Path $env:TEMP ('phasebudget-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$fail = 0
try {
  $srcCopy = Join-Path $work 'Big.pas'
  $dbCopy = Join-Path $work 'idx.sqlite'
  Copy-Item -LiteralPath $Source -Destination $srcCopy
  Copy-Item -LiteralPath $DbPath -Destination $dbCopy
  $env:DRAGLINT_PROFILE = '1'
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $proc = Start-Process -FilePath $Exe -PassThru -NoNewWindow -RedirectStandardOutput "$work\o.txt" -RedirectStandardError "$work\e.txt" `
    -ArgumentList @('lint', $srcCopy, '--db', $dbCopy, '--enable', 'multiple-statements-per-line,magic-literal,commented-out-code,review-marker-stale,review-marker-unused'); $null = $proc.Handle
  $done = $proc.WaitForExit(600000)
  $sw.Stop()
  if (-not $done) { $proc.Kill(); $proc.WaitForExit(10000) | Out-Null }
  $total = [math]::Round($sw.Elapsed.TotalSeconds, 1)
  $phases = @()
  foreach ($l in (Get-Content "$work\e.txt")) {
    if ($l -match '\[lint-phase\]\s+(\S+)\s+([\d\.,]+) s') { $phases += [pscustomobject]@{ Phase = $Matches[1]; Seconds = [double]($Matches[2] -replace ',', '.') } }
  }
  $phases | Sort-Object Seconds -Descending | Format-Table -AutoSize | Out-String | Write-Host
  Write-Host "total wall: $total s"
  if ($phases.Count -eq 0) { Write-Host 'FAIL: no [lint-phase] lines (profile output missing)'; $fail++ }
  $slow = @($phases | Where-Object { $_.Seconds -gt $MaxPhaseSeconds })
  if ($slow.Count -gt 0 -or -not $done -or $total -gt $MaxTotalSeconds) {
    Write-Host "FAIL budget: phases over ${MaxPhaseSeconds} s: $(($slow | ForEach-Object { $_.Phase }) -join ', '); total ${total} s (limit $MaxTotalSeconds)"; $fail++
  } else { Write-Host "PASS budget: every phase <= ${MaxPhaseSeconds} s, total ${total} s <= $MaxTotalSeconds s" }
  # positive control: a tiny threshold must trip on the very same table
  $tripped = @($phases | Where-Object { $_.Seconds -gt 0.0001 }).Count -gt 0
  if ($tripped) { Write-Host 'PASS control: a 0.0001 s threshold fails the same table' }
  else { Write-Host 'FAIL control: a 0.0001 s threshold did not trip -- the check cannot fail'; $fail++ }
} finally {
  Remove-Item Env:\DRAGLINT_PROFILE -ErrorAction SilentlyContinue
  try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "note: scratch left at $work" }
}
if ($fail -gt 0) { Write-Host "RESULT: $fail FAIL"; exit 1 }
Write-Host 'RESULT: PASS'
