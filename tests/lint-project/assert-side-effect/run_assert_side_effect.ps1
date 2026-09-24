<#
  run_assert_side_effect.ps1 -- the `assert-with-side-effect` project lint rule
  (INBOX docs\INBOX-lint-rules-from-new-facts-2026-09-23.md section 4).

  Indexes tests\lint-project\assert-side-effect\uAssertFx.pas into a scratch DB
  beside this script (the `index` verb runs the `purity` resolve stage, so
  effect_free / effect_summary / effect_witness are populated) and runs
  lint-all TWICE -- the same pair as run_purity_rules.ps1, for the same reason:

    RUN 1  bare `lint-all`          -> ZERO findings for the id (OFF by default),
                                       and SOME findings overall (non-vacuity).
    RUN 2  `--enable <id>`          -> exactly the TRIGGER lines, none of the
                                       CONTROL lines.

  Every line number is READ FROM THE FIXTURE's TRIGGER-n / CONTROL-n markers,
  never hard-coded, so a fixture edit cannot turn an assertion vacuous.

  `lint --json` is a BARE ARRAY whose line key is `start_line`, never `line`.

  Usage: pwsh -File tests\lint-project\assert-side-effect\run_assert_side_effect.ps1
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$dir     = $PSScriptRoot
$fixture = Join-Path $dir 'uAssertFx.pas'
$db      = Join-Path $dir '_assert_side_effect_test.sqlite'
foreach ($x in @($db, "$db-shm", "$db-wal")) { if (Test-Path $x) { Remove-Item $x -Force } }

$Rule = 'assert-with-side-effect'

function Parse-Findings([string[]]$Raw) {
  $txt = ($Raw -join "`n"); $b = $txt.IndexOf('[')
  $out = @(); if ($b -ge 0) { try { $out = @($txt.Substring($b) | ConvertFrom-Json) } catch { $out = @() } }
  if ($null -eq $out) { $out = @() }
  return ,@($out)
}
function LineOf([string]$Marker) {
  $m = @(Select-String -LiteralPath $fixture -SimpleMatch -Pattern $Marker)
  if ($m.Count -ne 1) { throw "marker '$Marker' found $($m.Count) times in the fixture" }
  return [int]$m[0].LineNumber
}

Write-Host "Indexing fixture..."
& $exePath index $dir --db $db | Out-Null

$t1 = LineOf 'TRIGGER-1'; $t2 = LineOf 'TRIGGER-2'; $t3 = LineOf 'TRIGGER-3'; $t4 = LineOf 'TRIGGER-4'; $t5 = LineOf 'TRIGGER-5'
$controls = @(1..9 | ForEach-Object { LineOf "CONTROL-$_" })

Write-Host "RUN 1: bare lint-all (the rule must be OFF by default)..."
$f0 = Parse-Findings (& $exePath lint-all --db $db --format json 2>$null)
$off = @($f0 | Where-Object { $_.rule -eq $Rule }).Count
Write-Host ("  run 1: {0} finding(s) total; {1}={2}" -f $f0.Count, $Rule, $off)

Write-Host "RUN 2: lint-all --enable $Rule ..."
$f = Parse-Findings (& $exePath lint-all --db $db --format json --enable $Rule 2>$null)
$a = @($f | Where-Object { $_.rule -eq $Rule })
$a | ForEach-Object { Write-Host ("    {0}:{1} {2}" -f (Split-Path $_.file_path -Leaf), $_.start_line, $_.message) }
$lines = @($a | ForEach-Object { [int]$_.start_line })
function MsgAt([int]$L) { $m = @($a | Where-Object { [int]$_.start_line -eq $L }); if ($m.Count -eq 1) { return [string]$m[0].message }; return '' }

$c0  = ($off -eq 0)
$c0b = ($f0.Count -gt 0)                           # a crashed run also reports zero
# positive controls: one finding per trigger line, and nothing else
$c1  = ($a.Count -eq 5)
$c2  = ($lines -contains $t1) -and ((MsgAt $t1) -like '*Pop*') -and ((MsgAt $t1) -like '*p0*')
$c3  = ($lines -contains $t2) -and ((MsgAt $t2) -like '*Bump*') -and ((MsgAt $t2) -like "*'s'*")
$c4  = ($lines -contains $t3) -and ((MsgAt $t3) -like '*NextId*') -and ((MsgAt $t3) -like "*'g'*")
# the call sits on the SECOND line of a wrapped Assert, in the message argument
$c5  = ($lines -contains $t4) -and ((MsgAt $t4) -like '*Pop*')
# resolver 1.7.0-alpha: the PARENLESS call -- a 'read' ref that owns a call edge -- fires too
$c5b = ($lines -contains $t5) -and ((MsgAt $t5) -like '*NextId*') -and ((MsgAt $t5) -like "*'g'*")
# the witness travels with the finding (NextId's witness names the global)
$c6  = ((MsgAt $t3) -like '*GNext*')
# negative controls: none of the CONTROL lines fires
$hit = @($controls | Where-Object { $lines -contains $_ })
$c7  = ($hit.Count -eq 0)

$pass = $c0 -and $c0b -and $c1 -and $c2 -and $c3 -and $c4 -and $c5 -and $c5b -and $c6 -and $c7
if ($pass) {
  Write-Host "PASS  OFF by default (run 1); 5 triggers (p0, s, g, wrapped message, parenless g) fire with witness, 9 controls silent (run 2)"
  exit 0
} else {
  Write-Host ("FAIL  off={0} run1Real={1} count5={2} p0={3} s={4} g={5} wrapped={6} parenless={10} witness={7} controlsSilent={8} (controls hit: {9})" -f `
    $c0, $c0b, $c1, $c2, $c3, $c4, $c5, $c6, $c7, ($hit -join ','), $c5b)
  exit 1
}
