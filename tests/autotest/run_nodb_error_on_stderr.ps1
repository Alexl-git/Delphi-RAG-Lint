<#
  run_nodb_error_on_stderr.ps1 -- B-21: the shared "no --db was given and no
  project database resolves here" refusal (NoDbResolved, 15 verbs) goes to
  STDERR, never stdout, and the exit code stays 2.

  THE DEFECT. `outline --file X` with no --db and no resolvable database exited
  2 and printed its ERROR to stdout only. A caller that parses stdout (the IDE
  plugin, a script piping --format json) reads the refusal as the verb's
  ANSWER; a caller that watches stderr sees nothing wrong but the exit code.

  CHECKS (outline, slice, impact -- three NoDbResolved callers)
    P  POSITIVE CONTROL: the refusal text appears on ONE of the two streams and
       the exit is 2 -- so the stream checks below cannot pass on a run that
       printed nothing at all
    S  the refusal is on stderr
    O  stdout carries no ERROR line
  Run from a fresh folder under C:\TEMP, which no manifest section covers.
#>
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:fail = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ("draglint_nodb_stderr-{0}" -f $PID)
if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory $scratch | Out-Null
$unit = Join-Path $scratch 'uX.pas'
[IO.File]::WriteAllText($unit, "unit uX;`r`ninterface`r`nimplementation`r`nend.`r`n", [Text.Encoding]::ASCII)
$oF = Join-Path $scratch 'o.txt'; $eF = Join-Path $scratch 'e.txt'
$msg = 'no --db was given and no project database resolves here'

try {
  $runs = [ordered]@{
    outline = @('outline', '--file', $unit)
    slice   = @('slice', '--qname', 'uX.Nothing')
    impact  = @('impact', '--qname', 'uX.Nothing')
  }
  foreach ($verb in $runs.Keys) {
    $p = Start-Process -FilePath $exePath -ArgumentList $runs[$verb] -WorkingDirectory $scratch -NoNewWindow -PassThru `
           -RedirectStandardOutput $oF -RedirectStandardError $eF
    if (-not $p.WaitForExit(60000)) { try { $p.Kill($true) } catch { }; Check "$verb finished" $false 'timed out'; continue }
    $o = (Get-Content -LiteralPath $oF -Raw -ErrorAction SilentlyContinue) + ''
    $e = (Get-Content -LiteralPath $eF -Raw -ErrorAction SilentlyContinue) + ''
    Write-Host "== $verb ==" -ForegroundColor Cyan
    Check "P $verb exit 2 and the refusal is printed somewhere" (($p.ExitCode -eq 2) -and (($o + $e).Contains($msg))) "exit=$($p.ExitCode) out=[$o] err=[$e]"
    Check "S $verb refusal is on stderr" ($e.Contains($msg)) "err=[$e]"
    Check "O $verb stdout has no ERROR line" (-not ($o -match '(?m)^ERROR')) "out=[$o]"
  }
}
finally {
  try { [IO.Directory]::Delete($scratch, $true) } catch { }
}
if ($script:fail) { Write-Host 'run_nodb_error_on_stderr: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_nodb_error_on_stderr: PASS' -ForegroundColor Green; exit 0
