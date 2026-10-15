<#
  run_allow_metric_late_routine.ps1 -- `allow` can record a whole-routine
  metric review on a routine that sits late in a big file (backlog #21,
  2026-10-14).

  THE DEFECT. `allow --fix-rule deep-nesting` (and the other six routine-metric
  rules) re-measures the routine to bind the marker to the value. It called the
  checkers with every threshold at 1 so "every routine reports" -- but each
  checker stops walking the tree after 200 findings, a cap meant for lint output.
  At threshold 1 a routine yields up to four findings, so in a big file the walk
  stopped around the 50th routine and every routine below it "produced no
  finding": `allow` refused ("no routine at ... produces one") on a line `lint`
  anchored the finding on. Seen on TCallResolver.ResolveOneAt, line ~5900 of a
  6,000-line unit; a method early in the same file worked, which made it look
  like a methods-vs-functions problem.

  THE FIXTURE: 220 small routines (each with 2 parameters, 2 locals, nesting 2,
  several lines -- so the old all-thresholds-at-1 call emits 4 findings apiece)
  and, last, one routine nested 6 deep. 220 matters for C: one cyclomatic finding
  per routine needs more than 200 routines to reach the cap.

  CASES, all dry-run (nothing is written):
    D   allow --fix-rule deep-nesting on the last routine -> a marker is shown   <- FIX
    C   the same for cyclomatic-complexity                                        <- FIX
    K   CONTROL: lint reports deep-nesting on that routine's header
    E   CONTROL: allow on the FIRST routine works on both builds
  RED-CHECK: on the pre-fix exe D and C fail; K and E pass on both.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_allow_late_$PID"
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

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$pas = Join-Path $WorkDir 'uMany.pas'

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('unit uMany;')
[void]$sb.AppendLine('interface')
[void]$sb.AppendLine('implementation')
for ($i = 1; $i -le 220; $i++) {
  [void]$sb.AppendLine("function F$($i)(A, B: Integer): Integer;")
  [void]$sb.AppendLine('var')
  [void]$sb.AppendLine('  X, Y: Integer;')
  [void]$sb.AppendLine('begin')
  [void]$sb.AppendLine('  X:= A;')
  [void]$sb.AppendLine('  Y:= B;')
  [void]$sb.AppendLine('  if X > 0 then')
  [void]$sb.AppendLine('    if Y > 0 then')
  [void]$sb.AppendLine('      X:= Y;')
  [void]$sb.AppendLine('  Result:= X;')
  [void]$sb.AppendLine('end;')
}
$deepLine = ($sb.ToString() -split "`r?`n").Count
[void]$sb.AppendLine('procedure Deep(A: Integer);')
[void]$sb.AppendLine('begin')
[void]$sb.AppendLine('  if A > 0 then')
[void]$sb.AppendLine('    if A > 1 then')
[void]$sb.AppendLine('      if A > 2 then')
[void]$sb.AppendLine('        if A > 3 then')
[void]$sb.AppendLine('          if A > 4 then')
[void]$sb.AppendLine('            if A > 5 then')
[void]$sb.AppendLine('              A:= 0;')
[void]$sb.AppendLine('end;')
[void]$sb.AppendLine('end.')
[System.IO.File]::WriteAllText($pas, ($sb.ToString() -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)

function Run([string[]]$argv) {
  Push-Location C:\TEMP
  try {
    $out = & $Exe @argv 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
  } finally { Pop-Location }
}

Write-Host ''
Write-Host 'run_allow_metric_late_routine -- a metric review on routine #221 of 221' -ForegroundColor Cyan

$k = Run @('lint', $pas, '--enable', 'deep-nesting')
Check "K lint anchors deep-nesting on Deep's header (line $deepLine)" ($k.Text -match ("uMany\.pas:$($deepLine):\d+\s+\[\w+\]\s+deep-nesting: Routine Deep")) $k.Text

$d = Run @('allow', $pas, '--fix-line', "$deepLine", '--fix-rule', 'deep-nesting')
Check 'D allow deep-nesting on the last routine shows a marker' (($d.Code -eq 0) -and ($d.Text -match 'dl:ok deep-nesting@')) $d.Text

$c = Run @('allow', $pas, '--fix-line', "$deepLine", '--fix-rule', 'cyclomatic-complexity')
Check 'C allow cyclomatic-complexity on the last routine shows a marker' (($c.Code -eq 0) -and ($c.Text -match 'dl:ok cyclomatic-complexity@')) $c.Text

$e = Run @('allow', $pas, '--fix-line', '4', '--fix-rule', 'too-many-parameters')
Check 'E CONTROL: allow too-many-parameters on the first routine' (($e.Code -eq 0) -and ($e.Text -match 'dl:ok too-many-parameters@')) $e.Text

Check 'the fixture was not modified (dry-run only)' (-not ((Get-Content $pas -Raw) -match 'dl:ok')) ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up.
  foreach ($d23 in @("C:\TEMP\draglint_allow_late_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
