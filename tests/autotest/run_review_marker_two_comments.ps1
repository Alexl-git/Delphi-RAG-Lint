<#
  run_review_marker_two_comments.ps1 -- W5-B (INBOX-yadf-fp-layout-complexity-docs item 3).

  THE DEFECT (re-measured 2026-10-25 on 1.34.0-alpha). A line carrying TWO
  `// dl:ok` comments (`// dl:ok a -- one  // dl:ok b -- two`) honoured only the
  first: TReviewMarkers.Parse read everything after the first tag's `--` as its
  reason, so rule b was never suppressed and never reported unverifiable -- the
  second review was silently ignored.

  CONTRACT. Every `// dl:ok` comment on a line is a marker. A bare `dl:ok`
  inside a reason (no `//` of its own) stays prose.

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_marker_two_comments_$PID"
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

# Each `if` line trips BOTH magic-literal and large-magic-number at col 10.
#   line 10: two `//` comments, one rule each              (the defect)
#   line 11: one comment naming both rules                  (positive control)
#   line 12: no marker                                      (positive control)
#   line 13: second `dl:ok` WITHOUT its own `//` = prose    (negative control)
$u = "unit uTwo;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`n" +
     "function Lim(A: Integer): Integer;`r`nbegin`r`n  Result := 0;`r`n" +
     "  if A > 500 then Exit;  // dl:ok magic-literal -- one  // dl:ok large-magic-number -- two`r`n" +
     "  if A > 600 then Exit;  // dl:ok magic-literal, large-magic-number -- both`r`n" +
     "  if A > 700 then Exit;`r`n" +
     "  if A > 800 then Exit;  // dl:ok magic-literal -- the dl:ok large-magic-number note`r`n" +
     "end;`r`n`r`ninitialization`r`n  Lim(1);`r`nend.`r`n"
$pas = Join-Path $WorkDir 'uTwo.pas'
[IO.File]::WriteAllText($pas, $u, [Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'fx.sqlite'
& $exePath index $WorkDir --db $db 2>&1 | Out-Null

$all = @(& $exePath lint $pas --db $db --enable magic-literal --json 2>$null | ConvertFrom-Json)
function At($rule, $line) { @($all | Where-Object { $_.rule -eq $rule -and $_.start_line -eq $line }) }

# ---- positive controls ------------------------------------------------------------
Check 'P1 POSITIVE CONTROL unmarked line 12 reports both rules' `
      (((At 'magic-literal' 12).Count -eq 1) -and ((At 'large-magic-number' 12).Count -eq 1)) `
      'the fixture no longer trips both rules -- T1 would prove nothing'
Check 'P2 POSITIVE CONTROL one comment naming both rules suppresses both (line 11)' `
      (((At 'magic-literal' 11).Count -eq 0) -and ((At 'large-magic-number' 11).Count -eq 0))

# ---- T1/T2: the second comment is honoured ------------------------------------------
Check 'T1 first comment suppresses magic-literal on line 10' ((At 'magic-literal' 10).Count -eq 0)
Check 'T2 SECOND // dl:ok comment suppresses large-magic-number on line 10' `
      ((At 'large-magic-number' 10).Count -eq 0) (($all | Where-Object start_line -eq 10).message -join ' || ')
Check 'T3 the second marker is checked too (hashless -> review-marker-stale for large-magic-number)' `
      (@(At 'review-marker-stale' 10 | Where-Object { $_.message -match '"large-magic-number"' }).Count -eq 1)

# ---- negative control: prose dl:ok is not a marker -----------------------------------
Check 'N1 NEGATIVE CONTROL a dl:ok without its own // stays prose (line 13 still reports large-magic-number)' `
      ((At 'large-magic-number' 13).Count -eq 1)

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_marker_two_comments_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
