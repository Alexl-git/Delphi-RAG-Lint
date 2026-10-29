# run_taint_depth.ps1 -- taint lane gaps/taint-fld (2026-10-27): the taint walk must FINISH on
# any input. Regression for the lint-all EStackOverflow over the engine's own index: a loop-carried
# reassignment (`S := StringReplace(S, ...)` in a loop) makes data_flows say "arg 0 of the call at
# site S derives from the call at site S"; EvalRef -> propagator -> ArgRowsAt(S) -> the same row
# recursed without ever passing the memo.
#
# Fixture tests\lint-project\taint-deep\ (the engine's own extractor fills data_flows):
#   uLoop      loop-carried self-referencing site          -> finding at uLoop.pas:21
#   uMutual    mutual recursion MutA <-> MutB              -> finding at uMutual.pas:21
#   uFieldCyc  the field's writer reads the field (TFA.Grow) and a descendant writes the
#              INHERITED field from a source, then reads it (TFB.Run)  -> uFieldCyc.pas:33
#   uChain     a 300-deep parameter chain to ExecSQL: past max_depth (16) it is UNKNOWN, not a
#              finding; with max_depth 100000 it reaches the walk-depth guard
#              (TAINT_EVAL_DEPTH_CAP) -- the run still finishes and DRAGLINT_DEBUG says so.
# Every lint-all runs under a wall-clock limit; a hang or a crash fails the check by name.
#
# Usage: pwsh -File tests\autotest\run_taint_depth.ps1 [-Exe <drag-lint.exe>] [-TimeoutSec 120]
param([string]$Exe = '', [int]$TimeoutSec = 120)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
$exePath = (Resolve-Path $Exe).Path
$fx    = Join-Path $repo 'tests\lint-project\taint-deep'
$libFx = Join-Path $repo 'tests\lint-project\taint-lib\lib'
$tmp   = Join-Path $env:TEMP "taint_depth_$PID"
[void][IO.Directory]::CreateDirectory($tmp)
$db    = Join-Path $tmp 'fx.sqlite'
$lib   = Join-Path $tmp 'lib.sqlite'
$empty = Join-Path $tmp 'empty.json'
$deep  = Join-Path $tmp 'deep.json'
[IO.File]::WriteAllText($empty, '{}')
[IO.File]::WriteAllText($deep, '{"taint": {"max_depth": 100000}}')

$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name  $Detail"; $script:fail++ }
}
# One lint-all under the time limit. Returns @{ Done; Exit; Taint (findings); Err (stderr text) }.
function LintAll([string]$Tag, [string]$Config, [string[]]$Extra = @()) {
  $out = Join-Path $tmp "$Tag.json"; $err = Join-Path $tmp "$Tag.err"
  $psi = [Diagnostics.ProcessStartInfo]::new($exePath)
  foreach ($a in @('lint-all', '--db', $db, '--db', $lib, '--json', '--quiet', '--config', $Config) + $Extra) { $psi.ArgumentList.Add($a) }
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
  $psi.WorkingDirectory = $tmp
  $psi.Environment['DRAGLINT_DEBUG'] = '1'
  $p = [Diagnostics.Process]::Start($psi)
  $so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
  $done = $p.WaitForExit($TimeoutSec * 1000)
  if (-not $done) { $p.Kill($true); [void]$p.WaitForExit(10000) }
  $txt = $so.Result; $etx = $se.Result
  [IO.File]::WriteAllText($out, $txt); [IO.File]::WriteAllText($err, $etx)
  $all = @(); $b = $txt.IndexOf('[')
  if ($b -ge 0) { try { $all = @($txt.Substring($b) | ConvertFrom-Json) } catch { $all = @() } }
  return @{ Done = $done; Exit = $(if ($done) { $p.ExitCode } else { -1 }); Err = $etx;
            Taint = @($all | Where-Object { $_.rule -like 'taint-*' }) }
}
function At($List, [string]$Unit, [int]$Line) {
  return ,@($List | Where-Object { $_.rule -eq 'taint-sql-injection' -and (Split-Path $_.file_path -Leaf) -eq $Unit -and $_.start_line -eq $Line })
}

Push-Location $env:TEMP
try {
  & $exePath index $fx    --db $db  2>&1 | Out-Null
  & $exePath index $libFx --db $lib 2>&1 | Out-Null

  $r = LintAll 'default' $empty
  Check "default config: lint-all finishes within $TimeoutSec s" $r.Done
  Check 'default config: exit 0/1 (1 = findings), no FATAL' (($r.Exit -in 0, 1) -and ($r.Err -notmatch 'FATAL|EStackOverflow')) "exit $($r.Exit): $(($r.Err -split "`n" | Select-String 'FATAL') -join ' ')"
  $r.Taint | ForEach-Object { Write-Host ("  {0} {1}:{2} {3}" -f $_.rule, (Split-Path $_.file_path -Leaf), $_.start_line, $_.message) }
  Check 'hit  uLoop.pas:21 (loop-carried self-referencing site)' ((At $r.Taint 'uLoop.pas' 21).Count -eq 1) "got $((At $r.Taint 'uLoop.pas' 21).Count)"
  Check 'hit  uMutual.pas:21 (mutual recursion)' ((At $r.Taint 'uMutual.pas' 21).Count -eq 1) "got $((At $r.Taint 'uMutual.pas' 21).Count)"
  Check 'hit  uFieldCyc.pas:33 (cycle through an inherited field)' ((At $r.Taint 'uFieldCyc.pas' 33).Count -eq 1) "got $((At $r.Taint 'uFieldCyc.pas' 33).Count)"
  Check 'no  uChain.pas:1814 at max_depth 16 (unknown, not a finding)' ((At $r.Taint 'uChain.pas' 1814).Count -eq 0)
  Check 'default config: the stats line reports a partial key (the chain is unknown, not silent)' ($r.Err -match 'partial keys [1-9]') (($r.Err -split "`n" | Select-String '^taint: sinks') -join ' ')

  $d = LintAll 'deep' $deep
  Check "max_depth 100000: lint-all finishes within $TimeoutSec s" $d.Done
  Check 'max_depth 100000: exit 0/1, no FATAL' (($d.Exit -in 0, 1) -and ($d.Err -notmatch 'FATAL|EStackOverflow')) "exit $($d.Exit)"
  Check 'max_depth 100000: the walk-depth guard fired and said so (DRAGLINT_DEBUG)' (($d.Err -match 'taint: walk depth cap \d+ reached') -and ($d.Err -match 'depth caps [1-9]')) (($d.Err -split "`n" | Select-String '^taint:') -join ' | ')
  Check 'max_depth 100000: the default run did NOT hit the guard (positive control)' ($r.Err -match 'depth caps 0') (($r.Err -split "`n" | Select-String '^taint: sinks') -join ' ')
  # every taint rule disabled: the stage must not run at all (no stats line under DRAGLINT_DEBUG);
  # the default run above printed one, which is this check's positive control
  $x = LintAll 'disabled' $deep @('--disable', 'taint-sql-injection,taint-command-injection,taint-path-traversal')
  Check 'all taint rules disabled: lint-all finishes, exit 0/1' ($x.Done -and ($x.Exit -in 0, 1)) "exit $($x.Exit)"
  Check 'all taint rules disabled: the taint stage does not run (no stats line)' ($x.Err -notmatch '(?m)^taint: sinks') (($x.Err -split "`n" | Select-String '^taint:') -join ' | ')
  Check 'all taint rules disabled: no taint finding' ($x.Taint.Count -eq 0) "got $($x.Taint.Count)"
  Check 'default run printed the stats line (positive control for the skip)' ($r.Err -match '(?m)^taint: sinks')
}
finally {
  Pop-Location
}
if ($fail -eq 0) { Write-Host 'run_taint_depth: ALL PASS'; exit 0 }
Write-Host "run_taint_depth: $fail FAILED"; exit 1
