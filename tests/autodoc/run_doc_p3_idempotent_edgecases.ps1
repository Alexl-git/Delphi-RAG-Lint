<#
  run_doc_p3_idempotent_edgecases.ps1 -- Auto-Document Phase 3, Task 3 (review
  follow-up, Finding 1 -- coordinator's reversal, round 2): the two concrete
  reproductions that showed WHY an exact-string compare against freshly
  generated text (the earlier, since-reverted attempt at preserving a marked
  <returns> with content) is wrong -- both must now pass, since <returns>
  reverted to "marked = engine-owned, refill from ObservedSuffix, regardless
  of content".

  SCENARIO A -- whitespace normalization. `Result := AValue  +  1;` (TWO
  spaces) mines to a raw Observed case carrying the same two spaces, written
  into the file verbatim by the fresh <returns> refill. On re-parse, the doc
  comment parser's CollapseWhitespace normalizes that to ONE space -- so the
  RAW file text (two spaces) and what the parser reads BACK (one space)
  disagree. An exact-string compare between "the existing marked body" and "a
  freshly recomputed ObservedSuffix" would therefore NEVER match on a second
  run, misclassifying the engine's own untouched output as human-edited,
  stripping its marker, and permanently disabling future refresh -- a
  zero-byte-diff (idempotency) violation. Asserts: apply, reindex, apply
  again -- byte-identical, action=unchanged, edits=0, and the marker is still
  present (not stripped).

  SCENARIO B -- legitimate drift. A function with ONE `Result :=` site is
  documented (one mined Observed case). A SECOND `Result :=` site is then
  added (simulating real code evolution) and the file is reindexed. Because
  marked <returns> is engine-owned regardless of content, `document --apply`
  must REFRESH the tag to include BOTH mined cases, not freeze on the first
  -- "absence over a wrong verdict" cuts both ways: staying silently wrong
  forever is exactly what the content-keyed exact-compare would have done
  (the old body would never again equal a freshly recomputed value once it
  included a second case), whereas the marker-keyed rule refreshes correctly.
  Asserts: after the drift + reindex + apply, the tag carries BOTH cases, and
  a further reindex + apply is byte-identical (idempotent at the new fixed
  point too).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$MARK = '<!-- drag-lint:auto -->'

function Write-Ansi([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Push-Location C:\TEMP
try {
  # ==== Scenario A: whitespace normalization ================================
  Write-Host 'Scenario A: whitespace normalization (Result := AValue  +  1;)' -ForegroundColor Cyan
  $scratchA = Join-Path C:\TEMP 'draglint_docp3idemws'
  if (Test-Path $scratchA) { Remove-Item $scratchA -Recurse -Force }
  New-Item -ItemType Directory -Path $scratchA | Out-Null
  $targetA = Join-Path $scratchA 'ws.pas'
  $dbA     = Join-Path $scratchA 'ws.sqlite'
  Write-Ansi $targetA @'
unit ws;

interface

function Add1(AValue: Integer): Integer;

implementation

function Add1(AValue: Integer): Integer;
begin
  Result := AValue  +  1;
end;

end.
'@

  & $exePath index $scratchA --db $dbA 2>$null | Out-Null
  Check 'A: index exits 0' ($LASTEXITCODE -eq 0)

  & $exePath document --qname ws.Add1 --db $dbA --apply --json 2>$null | Out-Null
  Check 'A: apply #1 exits 0' ($LASTEXITCODE -eq 0)
  $afterFirst = [IO.File]::ReadAllBytes($targetA)
  $textFirst  = [IO.File]::ReadAllText($targetA)
  Check 'A: fresh <returns> carries the two-space mined case, marked' `
    ($textFirst -match [regex]::Escape('<returns>' + $MARK) + 'Observed:\s*AValue {2}\+ {2}1\.') $textFirst

  & $exePath index $scratchA --db $dbA 2>$null | Out-Null
  $reApplyJsonA = (& $exePath document --qname ws.Add1 --db $dbA --apply --json 2>$null) -join "`n"
  Check 'A: 2nd apply action=unchanged (marker NOT misclassified as hand-edited by whitespace drift)' `
    ($reApplyJsonA -match '"action":"unchanged"') $reApplyJsonA
  Check 'A: 2nd apply edits=0' ($reApplyJsonA -match '"edits":0') $reApplyJsonA
  $afterSecond = [IO.File]::ReadAllBytes($targetA)
  Check 'A: byte-identical after reindex + 2nd apply' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterFirst,[byte[]]$afterSecond))
  $textSecond = [IO.File]::ReadAllText($targetA)
  Check 'A: marker still present (NOT stripped) after the 2nd apply' `
    ($textSecond -match [regex]::Escape('<returns>' + $MARK)) $textSecond

  # ==== Scenario B: legitimate drift (a second Result:= site appears) =======
  Write-Host ''
  Write-Host 'Scenario B: legitimate drift (a second Result:= site is added)' -ForegroundColor Cyan
  $scratchB = Join-Path C:\TEMP 'draglint_docp3idemdrift'
  if (Test-Path $scratchB) { Remove-Item $scratchB -Recurse -Force }
  New-Item -ItemType Directory -Path $scratchB | Out-Null
  $targetB = Join-Path $scratchB 'dr.pas'
  $dbB     = Join-Path $scratchB 'dr.sqlite'
  Write-Ansi $targetB @'
unit dr;

interface

function Pick(AValue: Integer): Integer;

implementation

function Pick(AValue: Integer): Integer;
begin
  Result := AValue;
end;

end.
'@

  & $exePath index $scratchB --db $dbB 2>$null | Out-Null
  Check 'B: index exits 0' ($LASTEXITCODE -eq 0)

  & $exePath document --qname dr.Pick --db $dbB --apply --json 2>$null | Out-Null
  Check 'B: apply #1 exits 0' ($LASTEXITCODE -eq 0)
  $textBefore = [IO.File]::ReadAllText($targetB)
  Check 'B: fresh <returns> carries ONE mined case (AValue only)' `
    ($textBefore -match [regex]::Escape('<returns>' + $MARK) + 'Observed:\s*AValue\.</returns>') $textBefore

  # Simulate real code drift: a second Result:= site appears.
  $drifted = (Get-Content -Raw $targetB) -replace `
    "begin\r\n  Result := AValue;\r\nend;", `
    "begin`r`n  if AValue > 0 then`r`n    Result := AValue`r`n  else`r`n    Result := 0;`r`nend;"
  [System.IO.File]::WriteAllText($targetB, $drifted, [System.Text.Encoding]::ASCII)

  & $exePath index $scratchB --db $dbB 2>$null | Out-Null
  $driftApplyJson = (& $exePath document --qname dr.Pick --db $dbB --apply --json 2>$null) -join "`n"
  Check 'B: post-drift apply exits 0' ($LASTEXITCODE -eq 0)
  Check 'B: post-drift apply actually changed the file (action=extended)' `
    ($driftApplyJson -match '"action":"extended"') $driftApplyJson
  $textAfterDrift = [IO.File]::ReadAllText($targetB)
  Check 'B: <returns> REFRESHED to carry BOTH mined cases (AValue; 0), marker intact' `
    ($textAfterDrift -match [regex]::Escape('<returns>' + $MARK) + 'Observed:\s*AValue;\s*0\.</returns>') $textAfterDrift

  # Idempotent at the NEW fixed point too.
  $afterDriftBytes = [IO.File]::ReadAllBytes($targetB)
  & $exePath index $scratchB --db $dbB 2>$null | Out-Null
  $reApplyJsonB = (& $exePath document --qname dr.Pick --db $dbB --apply --json 2>$null) -join "`n"
  Check 'B: 3rd apply (post-drift) action=unchanged' ($reApplyJsonB -match '"action":"unchanged"') $reApplyJsonB
  Check 'B: 3rd apply edits=0' ($reApplyJsonB -match '"edits":0') $reApplyJsonB
  $afterThirdBytes = [IO.File]::ReadAllBytes($targetB)
  Check 'B: byte-identical after the post-drift reindex + 3rd apply' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterDriftBytes,[byte[]]$afterThirdBytes))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
