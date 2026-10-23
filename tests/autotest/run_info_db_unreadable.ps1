<#
  run_info_db_unreadable.ps1 -- `info --db <not a database>` answers verdict
  "unreadable" instead of dying FATAL (INBOX-2026-09-29-engine-followups-from-1.20.4 item 3).

  THE DEFECT. ComputeInfoIndexVerdict opened the store with no try/except, so a
  --db naming a file of garbage bytes ended in "FATAL: ESQLiteNativeException
  ... file is not a database", exit 3 -- and every OTHER --db of the same call
  (here: a missing one) was never reported. The "unreadable" verdict existed but
  could not be reached.

    A. garbage + missing in ONE call -> exit 0, json has both indexes,
       garbage = unreadable, missing = missing; no FATAL.
    B. POSITIVE CONTROL: the missing --db alone reports "missing", so A's
       per-index array is the real shape and A2 is not vacuous.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-info-unreadable-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$garbage = Join-Path $WorkDir 'garbage.sqlite'
$missing = Join-Path $WorkDir 'missing.sqlite'
[IO.File]::WriteAllBytes($garbage, [byte[]](1..200))

function InfoJson([string[]]$Dbs) {
  Push-Location $WorkDir
  try {
    $a = @('info', '--json'); foreach ($d in $Dbs) { $a += @('--db', $d) }
    $out = & $Exe @a 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
  } finally { Pop-Location }
}
function Verdicts($r) {
  $i = $r.Out.IndexOf('{"schema"')
  if ($i -lt 0) { return @() }
  try { return @(($r.Out.Substring($i) | ConvertFrom-Json).indexes) } catch { return @() }
}

Write-Host 'B. CONTROL: a missing --db alone' -ForegroundColor Cyan
$b = InfoJson @($missing)
$bv = Verdicts $b
Check 'B1 one index, verdict missing' (($bv.Count -eq 1) -and ($bv[0].verdict -eq 'missing')) "exit=$($b.Code)"

Write-Host ''
Write-Host 'A. garbage + missing in one call' -ForegroundColor Cyan
$a = InfoJson @($garbage, $missing)
$av = Verdicts $a
Check 'A1 no FATAL, exit 0' ((-not ($a.Out -match 'FATAL')) -and ($a.Code -eq 0)) "exit=$($a.Code)"
Check 'A2 both indexes reported' ($av.Count -eq 2) "n=$($av.Count)"
$g = $av | Where-Object { $_.path -eq $garbage }
Check 'A3 garbage -> unreadable, present' (($g.verdict -eq 'unreadable') -and ($g.present -eq $true)) "verdict=$($g.verdict)"
$m = $av | Where-Object { $_.path -eq $missing }
Check 'A4 missing still -> missing' ($m.verdict -eq 'missing') "verdict=$($m.verdict)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\drag-lint-info-unreadable-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
