<#
  run_compare_real.ps1 -- ONE real question through `drag-lint compare`, no stub.

  who-reads of Blueprint4.TfrmBlueprint4.FNoRecursion on the frozen CLIENT clone
  (charts\scratch\db\CLIENT-Micronite2027.sqlite -- never a live index). -Project cannot name
  a clone, so the old side is produced here with Ask-Report -DbPath <clone> -AllowStale
  -Plain, kept as a file, and then
      compare --old <that file> --command "who-reads -Target <t>" --db <clone>
  reruns the question through the real producer. The new run never accepts a stale index
  (C4), so the outcome is one of
      exit 0 / 1  the engine, producer, Ask-Report and the index agreed to the end  -> PASS
      exit 3      the frozen clone is stale against the sources on this machine; the
                  refusal itself is correct, but no diff happened                     -> SKIP, loudly
  SKIPs (never silently passes) when the clone, Ask-Report.ps1 or pwsh is missing.

  Run from any CWD, pwsh 7:  pwsh -File tests\autotest\run_compare_real.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [string]$Exe  = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Repo = "$PSScriptRoot\..\.."
)
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Skip($n,$why){ Write-Host ("[SKIP] {0}" -f $n) -ForegroundColor Yellow; Write-Host "      $why" -ForegroundColor DarkGray }

$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path $Repo).Path
$Clone = Join-Path $Repo 'charts\scratch\db\CLIENT-Micronite2027.sqlite'
$Ask   = Join-Path $Repo 'charts\src\Ask-Report.ps1'
$Pwsh  = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
$Target = 'Blueprint4.TfrmBlueprint4.FNoRecursion'

if (-not (Test-Path $Clone)) { Skip 'compare real question' "frozen clone missing: $Clone"; exit 0 }
if (-not (Test-Path $Ask))   { Skip 'compare real question' "Ask-Report.ps1 missing: $Ask"; exit 0 }
if (-not $Pwsh)              { Skip 'compare real question' 'pwsh 7 not on PATH'; exit 0 }

$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-compare-real-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $Work | Out-Null
try {
  Remove-Item Env:\DRAGLINT_ASK_REPORT -ErrorAction SilentlyContinue   # the REAL script, not the stub
  $old = Join-Path $Work 'old.txt'
  $txt = & $Pwsh -NoProfile -File $Ask -Question who-reads -Target $Target -DbPath $Clone -AllowStale -Plain -Engine $Exe | Out-String
  $made = $LASTEXITCODE -eq 0 -and $txt -match 'drag-lint report who-reads'
  Check 'old side produced by Ask-Report on the clone' $made "exit=$LASTEXITCODE first=[$(($txt -split "`r?`n")[0])]"
  if ($made) {
    [IO.File]::WriteAllText($old, $txt, [Text.UTF8Encoding]::new($false))
    $out = & $Exe compare --old $old --command "who-reads -Target $Target" --db $Clone 2>&1 | Out-String
    $code = $LASTEXITCODE
    if ($code -eq 3) {
      Skip 'compare reruns the question' "exit 3: the frozen clone is stale against the sources here (correct refusal, no diff). $($out.Trim())"
    } else {
      Check 'compare exit is 0 or 1' ($code -in 0,1) "exit=$code`n$out"
      Check 'compare prints a result line' ($out -match '(?m)^result: ') $out
    }
  }

  # feeds-from reads the SQL index too; compare passes only --db (R5), so the in-process producer
  # pairs it from report-pairs.json exactly as Ask-Report's step 2 does. A clone is in no pair, so
  # BOTH must refuse with exit 2 and the SAME message (before the fix compare said "feeds-from
  # needs -SqlDbPath", exit 1).
  $SqlClone = Join-Path $Repo 'charts\scratch\db\SQL-drag-lint-sql.sqlite'
  $FfTarget = 'frmCausFail.colREASON'
  if (-not (Test-Path $SqlClone)) { Skip 'compare pairs a reading question like Ask-Report' "frozen clone missing: $SqlClone" }
  else {
    $oldFf = Join-Path $Work 'old-ff.txt'
    $txt = & $Pwsh -NoProfile -File $Ask -Question feeds-from -Target $FfTarget -DbPath $Clone -SqlDbPath $SqlClone -AllowStale -Plain -Engine $Exe | Out-String
    $made = $LASTEXITCODE -eq 0 -and $txt -match 'drag-lint report feeds-from'
    Check 'feeds-from old side produced by Ask-Report on the clones' $made "exit=$LASTEXITCODE first=[$(($txt -split "`r?`n")[0])]"
    if ($made) {
      [IO.File]::WriteAllText($oldFf, $txt, [Text.UTF8Encoding]::new($false))
      $ps = & $Pwsh -NoProfile -File $Ask -Question feeds-from -Target $FfTarget -DbPath $Clone -AllowStale -Plain -Engine $Exe 2>&1 | Out-String
      $psCode = $LASTEXITCODE
      $psMsg = (($ps -split "`r?`n") | Where-Object { $_ -like 'ask-report: *' } | Select-Object -First 1) -replace '^ask-report: ', ''
      Check 'Ask-Report refuses the unpaired clone with exit 2' ($psCode -eq 2 -and $psMsg -match 'also reads the SQL-script index') "exit=$psCode`n$ps"
      $out = & $Exe compare --old $oldFf --command "feeds-from -Target $FfTarget" --db $Clone 2>&1 | Out-String
      $code = $LASTEXITCODE
      Check 'compare refuses it with exit 2' ($code -eq 2) "exit=$code`n$out"
      Check 'compare names Ask-Report''s pairing refusal verbatim' ($psMsg -and $out.Contains("the new run failed (exit 2): $psMsg")) "ask-report: $psMsg`ncompare: $out"
    }
  }

  # crosses-boundary: compare passes only --db, so the in-process producer pairs the counterpart
  # from report-pairs.json as Ask-Report's step 2 does. A clone is in no pair, so Ask-Report
  # proceeds with ONE side drawn (Ask-Report.ps1:262) and so must compare -- answered in-process,
  # no PowerShell fallback, same text.
  $CbTarget = 'Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation'
  $oldCb = Join-Path $Work 'old-cb.txt'
  $txt = & $Pwsh -NoProfile -File $Ask -Question crosses-boundary -Target $CbTarget -DbPath $Clone -AllowStale -Plain -Engine $Exe | Out-String
  $made = $LASTEXITCODE -eq 0 -and $txt -match 'drag-lint report crosses-boundary'
  Check 'crosses-boundary old side produced by Ask-Report on the clone (no pair)' $made "exit=$LASTEXITCODE first=[$(($txt -split "`r?`n")[0])]"
  if ($made) {
    [IO.File]::WriteAllText($oldCb, $txt, [Text.UTF8Encoding]::new($false))
    $out = & $Exe compare --old $oldCb --command "crosses-boundary -Target $CbTarget" --db $Clone 2>&1 | Out-String
    $code = $LASTEXITCODE
    if ($code -eq 3) {
      Skip 'compare answers crosses-boundary unpaired' "exit 3: the frozen clone is stale against the sources here. $($out.Trim())"
    } else {
      Check 'compare answers crosses-boundary without the fallback (exit 0 or 1)' ($code -in 0,1) "exit=$code`n$out"
    }
  }
}
finally {
  Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { Write-Host 'run_compare_real: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_compare_real: done' -ForegroundColor Green
exit 0
