<#
  run_effect_rules.ps1 -- the three store-backed effect rules of backlog lane
  B-EFFECT (1.37.0): side-effect-in-short-circuit, property-getter-with-effect,
  ui-access-in-thread-transitive.

  Indexes tests\lint-project\effect-rules\*.pas into a scratch DB beside this
  script (the `index` verb runs the purity resolve stage and the facts pass, so
  effect_summary / effect_witness / ui_affinity are populated) and runs
  lint-all TWICE:

    RUN 1  bare `lint-all`             -> ZERO findings for the three ids (all
                                          OFF by default), SOME findings overall.
    RUN 2  `--enable <the three ids>`  -> per id, exactly its TRIGGER lines and
                                          none of its CONTROL lines.

  Every line number is READ FROM THE FIXTURE MARKERS (SC-, PG-, UT- prefixes),
  never hard-coded. `lint --json` is a BARE ARRAY keyed `start_line`.

  Usage: pwsh -File tests\lint-project\effect-rules\run_effect_rules.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$dir     = $PSScriptRoot
$db      = Join-Path $dir '_effect_rules_test.sqlite'
foreach ($x in @($db, "$db-shm", "$db-wal")) { if (Test-Path $x) { Remove-Item $x -Force } }

$Rules = @{ 'SC' = 'side-effect-in-short-circuit'; 'PG' = 'property-getter-with-effect'; 'UT' = 'ui-access-in-thread-transitive' }

function Parse-Findings([string[]]$Raw) {
  $txt = ($Raw -join "`n"); $b = $txt.IndexOf('[')
  $out = @(); if ($b -ge 0) { try { $out = @($txt.Substring($b) | ConvertFrom-Json) } catch { $out = @() } }
  if ($null -eq $out) { $out = @() }
  return ,@($out)
}
# Marker -> "file|line" keys; each marker must occur exactly once across the fixture set.
function Marks([string]$Pattern) {
  $m = @(Get-ChildItem $dir -Filter '*.pas' | Select-String -Pattern $Pattern)
  return ,@($m | ForEach-Object { '{0}|{1}' -f $_.Filename.ToLower(), $_.LineNumber })
}

Write-Host "Indexing fixtures..."
& $exePath index $dir --db $db | Out-Null

Write-Host "RUN 1: bare lint-all (the rules must be OFF by default)..."
$f0 = Parse-Findings (& $exePath lint-all --db $db --format json 2>$null)
$ids = @($Rules.Values)
$off = @($f0 | Where-Object { $ids -contains $_.rule }).Count
Write-Host ("  run 1: {0} finding(s) total; ours={1}" -f $f0.Count, $off)

Write-Host "RUN 2: lint-all --enable $($ids -join ',') ..."
$f = Parse-Findings (& $exePath lint-all --db $db --format json --enable ($ids -join ',') 2>$null)
$ok = ($off -eq 0) -and ($f0.Count -gt 0)
$detail = @("off=$($off -eq 0) run1Real=$($f0.Count -gt 0)")
foreach ($p in $Rules.Keys) {
  $id   = $Rules[$p]
  $a    = @($f | Where-Object { $_.rule -eq $id })
  $a | ForEach-Object { Write-Host ("    {0}:{1} {2}" -f (Split-Path $_.file_path -Leaf), $_.start_line, $_.message) }
  $got  = @($a | ForEach-Object { '{0}|{1}' -f (Split-Path $_.file_path -Leaf).ToLower(), $_.start_line })
  $trig = Marks "$p-TRIGGER-\d+"
  $ctl  = Marks "$p-CONTROL-\d+"
  $miss = @($trig | Where-Object { $got -notcontains $_ })
  $hit  = @($ctl  | Where-Object { $got -contains $_ })
  $xtra = @($got  | Where-Object { $trig -notcontains $_ })
  # the witness / path travels with the finding
  $msgOk = switch ($p) {
    'SC' { @($a | Where-Object { $_.message -like '*effect_summary*' }).Count -eq $a.Count }
    'PG' { @($a | Where-Object { $_.message -like '*Get*' }).Count -eq $a.Count }
    'UT' { @($a | Where-Object { $_.message -like '*->*' -and $_.message -like '*ShowText*' }).Count -eq $a.Count }
  }
  $r = ($trig.Count -gt 0) -and ($ctl.Count -gt 0) -and ($miss.Count -eq 0) -and ($hit.Count -eq 0) -and ($xtra.Count -eq 0) -and $msgOk
  $ok = $ok -and $r
  $detail += ("{0}: triggers={1} controls={2} missing=[{3}] controlsHit=[{4}] extra=[{5}] msg={6}" -f `
    $id, $trig.Count, $ctl.Count, ($miss -join ','), ($hit -join ','), ($xtra -join ','), $msgOk)
}
$detail | ForEach-Object { Write-Host "  $_" }
if ($ok) { Write-Host "PASS  three effect rules: OFF by default; every trigger fires, every control silent"; exit 0 }
Write-Host "FAIL"; exit 1
