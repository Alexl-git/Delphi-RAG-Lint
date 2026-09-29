<#
  run_purity_rules.ps1 -- the two purity v2 lint rules (plan C6.1 Task 7; spec
  docs\superpowers\specs\2026-09-15-interprocedural-purity.md section 14):

    discarded-effect-free-result (14.1)
    query-name-with-effect       (14.2)

  Indexes tests\lint-project\purity-rules\uRules.pas into a scratch DB (the
  `index` verb runs the `purity` resolve stage, so effect_free / effect_summary
  / effect_witness are populated) and then runs lint-all THREE times.

  The runs are only meaningful together:

    RUN 1  bare `lint-all`            -> 14.1 fires ONCE (ON by default since
                                         1.20.1, owner ruling DEC-7); 14.2 ZERO.
    RUN 2  the same with `--enable`   -> the exact expected counts.
    RUN 3  `--disable` 14.1           -> ZERO for 14.1: ON is not "cannot be
                                         turned off".

  Run 1 is the default gate for BOTH ids -- ON for 14.1, OFF for 14.2. Run 2 is
  14.2's positive control: without it a rule that was never registered, never
  dispatched, or silently broken would satisfy run 1's zero perfectly. Run 1
  additionally asserts that the bare run produced SOME findings, because a
  lint-all that crashed and printed nothing also reports zero for 14.2.

  THE LINE-WRAP CONTROL (a7) IS THE EXPENSIVE ONE. `X := X +` newline
  `Twice(6);` trims to exactly the text a discarded call has, and the first
  shipped version of 14.1 reported it -- a false positive on a result that is
  USED. Reverting StartsNewStatement in ProjectRules.pas must make a7 FAIL.

  THE WITNESS-JOIN CONTROLS (a9, a10) pin the composition of
  symbol_facts.touches, which is the two-field wire string
  'resources|transactions' with the separator ALWAYS present. A one-sided
  value must not print the separator, and a two-sided one must be joined, not
  concatenated. Both are asserted through 14.2's message, which is where a
  user actually reads the witness.

  `lint --json` is a BARE ARRAY whose line key is `start_line`, never `line`.

  Usage: pwsh -File tests\lint-project\purity-rules\run_purity_rules.ps1
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
try {
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$dir     = $PSScriptRoot
$fixture = Join-Path $dir 'uRules.pas'
$db      = Join-Path $env:TEMP "purity_rules_test_$PID.sqlite"
if (Test-Path $db) { Remove-Item $db -Force }

$RuleDiscard = 'discarded-effect-free-result'
$RuleQuery   = 'query-name-with-effect'

function Parse-Findings([string[]]$Raw) {
  $txt = ($Raw -join "`n"); $b = $txt.IndexOf('[')
  $out = @(); if ($b -ge 0) { try { $out = @($txt.Substring($b) | ConvertFrom-Json) } catch { $out = @() } }
  if ($null -eq $out) { $out = @() }
  return ,@($out)
}
function MsgOf([object[]]$Findings, [string]$Needle) {
  $m = @($Findings | Where-Object { $_.message -like "*$Needle*" })
  if ($m.Count -eq 1) { return [string]$m[0].message }
  return ''
}

Write-Host "Indexing fixture..."
& $exePath index $dir --db $db | Out-Null

# Every line number is READ FROM THE FIXTURE, never hard-coded: a fixture edit
# must not silently turn an assertion vacuous.
$exprLine = (Select-String -LiteralPath $fixture -Pattern 'if Twice\(5\)'  | Select-Object -First 1).LineNumber
$stmtLine = (Select-String -LiteralPath $fixture -Pattern '^\s*Twice\(3\);' | Select-Object -First 1).LineNumber
$wrapLine = (Select-String -LiteralPath $fixture -Pattern '^\s*Twice\(6\);' | Select-Object -First 1).LineNumber

Write-Host "RUN 1: bare lint-all ($RuleDiscard ON by default, $RuleQuery OFF)..."
$f0 = Parse-Findings (& $exePath lint-all --db $db --format json 2>$null)
$d0   = @($f0 | Where-Object { $_.rule -eq $RuleDiscard })
$off1 = @($f0 | Where-Object { $_.rule -eq $RuleQuery   }).Count
Write-Host ("  run 1: {0} finding(s) total; {1}={2}, {3}={4}" -f $f0.Count, $RuleDiscard, $d0.Count, $RuleQuery, $off1)

Write-Host "RUN 3: lint-all --disable $RuleDiscard (the ON rule can still be turned off)..."
$f3 = Parse-Findings (& $exePath lint-all --db $db --format json --disable $RuleDiscard 2>$null)
$off3 = @($f3 | Where-Object { $_.rule -eq $RuleDiscard }).Count
Write-Host ("  run 3: {0} finding(s) total; {1}={2}" -f $f3.Count, $RuleDiscard, $off3)

Write-Host "RUN 2: lint-all --enable <both ids>..."
$f = Parse-Findings (& $exePath lint-all --db $db --format json --enable "$RuleDiscard,$RuleQuery" 2>$null)
$d = @($f | Where-Object { $_.rule -eq $RuleDiscard })
$q = @($f | Where-Object { $_.rule -eq $RuleQuery   })
Write-Host "  $RuleDiscard findings:"
$d | ForEach-Object { Write-Host ("    {0}:{1} {2}" -f $_.file_path, $_.start_line, $_.message) }
Write-Host "  $RuleQuery findings:"
$q | ForEach-Object { Write-Host ("    {0}:{1} {2}" -f $_.file_path, $_.start_line, $_.message) }

# --- run 1: the gate ---------------------------------------------------------
# DEC-7: a bare lint-all reports the statement-position call, and only it.
$onDiscard  = ($d0.Count -eq 1) -and ([int]$d0[0].start_line -eq [int]$stmtLine)
$offQuery   = ($off1 -eq 0)
# Non-vacuity control for run 1: a bare lint-all that produced NOTHING would
# satisfy offQuery while proving nothing at all.
$run1Real   = ($f0.Count -gt 0)
# Run 3: --disable wins over the ON default; the run itself must be real.
$offDisable = ($off3 -eq 0) -and ($f3.Count -gt 0)

# --- run 2: 14.1 -------------------------------------------------------------
# exactly one finding, on the statement-position call, naming Twice
$a1  = ($d.Count -eq 1) -and ($d[0].message -like '*Twice*')
$a1b = ($d.Count -eq 1) -and ([int]$d[0].start_line -eq [int]$stmtLine)
# not inside an expression
$a2  = @($d | Where-Object { [int]$_.start_line -eq [int]$exprLine }).Count -eq 0
# the SUMMARY decides, not "is a function": FillOut is p0, so it never fires
$a3  = @($d | Where-Object { $_.message -like '*FillOut*' }).Count -eq 0
# THE LINE-WRAP CONTROL: `X := X +` / newline / `Twice(6);` -- the result is USED
$a7  = @($d | Where-Object { [int]$_.start_line -eq [int]$wrapLine }).Count -eq 0
# the finding carries its evidence, the way 14.2 carries its witness
$a8  = ($d.Count -eq 1) -and ($d[0].message -like '*effect_free=1*')

# --- run 2: 14.2 -------------------------------------------------------------
$a4  = ($q.Count -eq 3) -and (@($q | Where-Object { $_.message -like '*GetAndBump*' }).Count -eq 1)
# a binding gap ('?') is not a proven effect
$a5  = @($q | Where-Object { $_.message -like '*IsReady*' }).Count -eq 0
# a proven getter is not an effect
$a6  = @($q | Where-Object { $_.message -like '*GetCount*' }).Count -eq 0
# THE WITNESS-JOIN CONTROLS. One-sided touches must print no separator...
$mPath = MsgOf $q 'GetPath'
$a9  = ($mPath -like '*touches file system*') -and ($mPath -notlike '*|*')
# ...and a two-sided one must be JOINED, not concatenated.
$mLog = MsgOf $q 'GetLog'
$a10 = ($mLog -like '*touches file system; transactions: starts, commits*') -and ($mLog -notlike '*|*')

$pass = $onDiscard -and $offQuery -and $run1Real -and $offDisable -and `
        $a1 -and $a1b -and $a2 -and $a3 -and $a7 -and $a8 -and `
        $a4 -and $a5 -and $a6 -and $a9 -and $a10

if ($pass) {
  Write-Host "PASS  $RuleDiscard ON / $RuleQuery OFF by default (run 1), --disable honoured (run 3), correct on --enable (run 2), line-wrap and witness-join controls hold"
  exit 0
} else {
  Write-Host ("FAIL  onDiscard={0} offQuery={1} run1Real={2} offDisable={3} a1={4} a1b={5} a2={6} a3={7} a7(wrap)={8} a8(evidence)={9} a4={10} a5={11} a6={12} a9(one-sided)={13} a10(joined)={14}" -f `
    $onDiscard, $offQuery, $run1Real, $offDisable, $a1, $a1b, $a2, $a3, $a7, $a8, $a4, $a5, $a6, $a9, $a10)
  Write-Host ("      stmtLine={0} exprLine={1} wrapLine={2}" -f $stmtLine, $exprLine, $wrapLine)
  Write-Host ("      GetPath msg = [{0}]" -f $mPath)
  Write-Host ("      GetLog  msg = [{0}]" -f $mLog)
  exit 1
}
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("$env:TEMP\purity_rules_test_$PID.sqlite", "$env:TEMP\purity_rules_test_$PID.sqlite-wal", "$env:TEMP\purity_rules_test_$PID.sqlite-shm")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
