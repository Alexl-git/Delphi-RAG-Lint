<#
  run_review_marker_stale_all_rules.ps1 -- N-12 (INBOX-yadf-fp-markers-leftovers item 3).

  THE DEFECT (re-measured 2026-10-23 on 1.33.0-alpha). One `// dl:ok` line carrying
  stale hashes for TWO rules (`deep-nesting@abcd, cyclomatic-complexity@abcd`)
  produced ONE review-marker-stale per lint run. After `allow` refreshed the first,
  the next lint-all surfaced the second -- "the loop never converges", one rule
  per pass. Cause: ApplyLineMarkers.EmitHint dedups on (hint rule, file, line),
  so the second rule's stale hint on the same line was dropped as a duplicate.

  CONTRACT. Every stale rule of a marker is reported in the same pass; the
  one-hint-per-marker dedup still holds for findings that share a rule.

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_marker_stale_all_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# 6 nesting levels (deep-nesting, max 5) and 32 decisions (cyclomatic, max 30).
$ifs = (1..25 | ForEach-Object { "  if A = $_ then Inc(R);" }) -join "`r`n"
$u = "unit uM;`r`n`r`ninterface`r`n`r`nfunction Deep(A: Integer): Integer;`r`n`r`nimplementation`r`n`r`n" +
     "function Deep(A: Integer): Integer;  // dl:ok deep-nesting@abcd, cyclomatic-complexity@abcd -- review`r`n" +
     "var R: Integer;`r`nbegin`r`n  R:= 0;`r`n  if A > 0 then`r`n    if A > 1 then`r`n      if A > 2 then`r`n" +
     "        if A > 3 then`r`n          if A > 4 then`r`n            if A > 5 then`r`n              Inc(R);`r`n" +
     "$ifs`r`n  Result:= R;`r`nend;`r`n`r`nend.`r`n"
[IO.File]::WriteAllText((Join-Path $WorkDir 'uM.pas'), $u, [Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'fx.sqlite'
& $exePath index $WorkDir --db $db 2>&1 | Out-Null

$all   = @(& $exePath lint-all --db $db --json 2>$null | ConvertFrom-Json)
$stale = @($all | Where-Object { $_.rule -eq 'review-marker-stale' -and $_.start_line -eq 9 })

# ---- P1/P2 POSITIVE CONTROLS -----------------------------------------------------
Check 'P1 POSITIVE CONTROL both metric findings fire on line 9' `
      ((@($all | Where-Object { $_.rule -eq 'deep-nesting' -and $_.start_line -eq 9 }).Count -eq 1) -and
       (@($all | Where-Object { $_.rule -eq 'cyclomatic-complexity' -and $_.start_line -eq 9 }).Count -eq 1)) `
      'the fixture no longer trips both rules -- T1 would prove nothing'
Check 'P2 POSITIVE CONTROL at least one stale hint is reported' ($stale.Count -ge 1) 'no review-marker-stale at all'

# ---- T1/T2: every stale rule in ONE pass -----------------------------------------
Check 'T1 the deep-nesting marker is reported stale' (@($stale | Where-Object { $_.message -match '"deep-nesting"' }).Count -eq 1) `
      ($stale.message -join ' || ')
Check 'T2 the cyclomatic-complexity marker is reported stale in the SAME pass' `
      (@($stale | Where-Object { $_.message -match '"cyclomatic-complexity"' }).Count -eq 1) `
      "only $($stale.Count) stale hint(s): $($stale.message -join ' || ')"

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_marker_stale_all_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
