<#
  compare-corpus.ps1 -A <tsv from the OLD grammar> -B <tsv from the NEW grammar>   (wave 150 DF2, DF-F1)
  Acceptance (all must hold, exit 0; else exit 1):
    1. B's failing set (errors > 0) is a SUBSET of A's failing set                     (no file regresses)
    2. both fixtures (tests\fixtures\dfm-nonascii) FAIL in A and PASS in B               (positive control: the right grammar loaded each time)
    3. the two TSVs cover the same files                                                  (a short run cannot pass vacuously)
  Prints totals, the fixed files and any regression (name + original path).
#>
param([Parameter(Mandatory)][string]$A, [Parameter(Mandatory)][string]$B)
$ErrorActionPreference = 'Stop'
function Load($p) { $h = @{}; foreach ($l in [IO.File]::ReadAllLines($p)) { $c = $l -split "`t"; $h[$c[0]] = [pscustomobject]@{ Err = [int]$c[1]; Path = $c[2] } }; return $h }
$ha = Load $A; $hb = Load $B
$ok = $true
function Fail($m) { Write-Host "FAIL: $m" -ForegroundColor Red; $script:ok = $false }
if ($ha.Count -ne $hb.Count -or (@($ha.Keys | Where-Object { -not $hb.ContainsKey($_) }).Count -gt 0)) { Fail "A ($($ha.Count)) and B ($($hb.Count)) do not cover the same files" }
$fa = @($ha.Keys | Where-Object { $ha[$_].Err -gt 0 } | Sort-Object)
$fb = @($hb.Keys | Where-Object { $hb[$_].Err -gt 0 } | Sort-Object)
Write-Host ("files={0}  A failing={1} (errors {2})  B failing={3} (errors {4})" -f $ha.Count, $fa.Count, (($ha.Values | Measure-Object Err -Sum).Sum), $fb.Count, (($hb.Values | Measure-Object Err -Sum).Sum))
$reg = @($fb | Where-Object { $ha[$_].Err -eq 0 })
foreach ($r in $reg) { Fail "regression (fails in B, passes in A): $r  $($hb[$r].Path)" }
$fixed = @($fa | Where-Object { $hb[$_].Err -eq 0 })
Write-Host "fixed by B: $($fixed.Count)"; $fixed | Select-Object -First 20 | ForEach-Object { Write-Host "  $_  $($ha[$_].Path)" }
$fx = @($ha.Keys | Where-Object { $ha[$_].Path -like '*\dfm-nonascii\*' })
if ($fx.Count -ne 2) { Fail "expected 2 fixture rows, found $($fx.Count)" }
foreach ($f in $fx) {
  if ($ha[$f].Err -eq 0) { Fail "fixture passes in A (control broken): $f" }
  if ($hb[$f].Err -ne 0) { Fail "fixture still fails in B: $f" }
}
if ($ok) { Write-Host 'PASS: B failing set is a subset of A; both fixtures FAIL in A and PASS in B' -ForegroundColor Green; exit 0 }
exit 1
