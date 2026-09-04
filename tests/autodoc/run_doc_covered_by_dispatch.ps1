<#
  run_doc_covered_by_dispatch.ps1 -- a `Covered by:` fact that cannot be tied to
  THIS symbol must be MARKED unverified, not asserted and not dropped.

  THE DEFECT THIS PINS (T1):
    ComputeCoveredBy unions resolved callers with a BARE-NAME bucket, because a
    DUnitX test calling code in another unit never gets a call_edges row. The
    name bucket matches on the method's last segment, so when the call site
    records no receiver there is nothing tying the match to one of several
    same-named methods. Reported from DataCopyTests: eight symbols named
    TransferFile, and one DPP test attributed to all of them within three hops --
    `uMahrRoutines.pas:219` carried a `Covered by:` naming a test that never
    touches it.

  THE RULING (owner, 2026-09-03): KEEP the fact, MARK it unverified. Dropping was
    the recommendation and was not taken: an unverified fact is still a lead, and
    the underlying question -- how an interface-dispatched call should be
    attributed at all -- is to be brainstormed rather than pre-empted by a filter.
    See docs\INBOX-untypable-receivers-brainstorm.md. PLAN-SESSION-65-small-
    medium.md's guard assertion 3 was written for DROP and is REVERSED here.

  WHY THE FIXTURE IS SHAPED LIKE THIS -- read before changing it:
    The plan said a call NESTED IN AN ARGUMENT LIST yields receiver_text = ''.
    MEASURED HERE: it does not. `Chk(M.TransferFile('x'), 'alpha')` records
    receiver `M`, exactly as the brainstorm note's REFUTED hypothesis 1 says. A
    fixture built on that description would have been silent for the wrong
    reason and would have proved nothing -- the same trap that once had a defect
    reported as "already fixed".

    The shape that DOES reproduce it is `with A do TransferFile(...)`: ordinary
    Delphi, the only legal way to call a method with no receiver at the site, and
    deterministic. Verified on the fixture index before this guard was written.

  THE CONTROLS, and what each rules out:
    * TBeta carries BOTH a marked and an unmarked entry on the SAME line, so
      "mark everything" and "mark nothing" each fail;
    * PlainHelper, a FREE routine called with no receiver, is NOT marked --
      counting those as suspect is what inflated a real handful of untypable
      receivers into a reported 3,882;
    * Beta_direct, a receiver-anchored method call, is NOT marked;
    * the fixture's premise -- that the `with` site really recorded an empty
      receiver -- is asserted against the index before anything leans on it;
    * the documented file is byte-identical after a second apply, so the marking
      is idempotent and cannot fight doc-drift.

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ("draglint-dispatch-" + [Guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}

Write-Host '== Covered by: an unprovable attribution is marked, not asserted ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path $Exe).Path
$srcDir = (Resolve-Path "$PSScriptRoot\fixtures\dispatch").Path

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$fixDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force -Path $fixDir | Out-Null
Copy-Item (Join-Path $srcDir '*.pas') $fixDir
$db      = Join-Path $WorkDir 'dispatch.sqlite'
$target  = Join-Path $fixDir 'dispatch.pas'
$errFile = Join-Path $WorkDir 'stderr.txt'

& $Exe index $fixDir --db $db 2>$errFile | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host "FATAL: indexing the fixture failed ($LASTEXITCODE)" -ForegroundColor Red
  Write-Host (Get-Content -LiteralPath $errFile -Raw); exit 1
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- fixture premise: the `with` site really has no receiver' -ForegroundColor Cyan
$recv = (& $Exe sql --db $db --query "select r.start_line, coalesce(nullif(r.receiver_text,''),'<EMPTY>') as recv, s.qualified_name as encl from refs r left join symbols s on s.id=r.enclosing_symbol_id where r.name_text='TransferFile' order by r.start_line" 2>$errFile | Out-String)
Write-Host ($recv -split "`r?`n" | Where-Object { $_ -match 'TDispatchTests' } | ForEach-Object { "  $_" }) -ForegroundColor DarkGray
Check 'Alpha_with recorded an EMPTY receiver' `
  ($recv -match '<EMPTY>\s+dispatchtest\.TDispatchTests\.Alpha_with') ''
Check 'CONTROL: Beta_direct recorded receiver B (so "empty" is not universal)' `
  ($recv -match '\bB\s+dispatchtest\.TDispatchTests\.Beta_direct') ''
Check 'CONTROL: the nested-in-arguments call DID capture its receiver M' `
  ($recv -match '\bM\s+dispatchtest\.TDispatchTests\.Alpha_via_interface') `
  'the plan predicted EMPTY here; it is not -- see the header'

# ---------------------------------------------------------------------------
& $Exe document --unit $target --db $db --apply 2>$errFile | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host "FATAL: document --apply failed ($LASTEXITCODE)" -ForegroundColor Red
  Write-Host (Get-Content -LiteralPath $errFile -Raw); exit 1
}
$doc = (Get-Content -LiteralPath $target -Raw) -replace "`r`n", "`n"

# Each `Covered by:` line, tagged with the declaration it precedes.
$lines = $doc -split "`n"
function CoveredForDecl([string]$DeclPattern) {
  # Walk forward from each Covered by: line to the first declaration line.
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -notmatch 'Covered by:') { continue }
    for ($j = $i + 1; $j -lt [Math]::Min($i + 12, $lines.Count); $j++) {
      if ($lines[$j] -match '^\s*///') { continue }
      if ($lines[$j] -match $DeclPattern) { return ($lines[$i] -replace '.*Covered by:\s*', '' -replace '</para>.*', '').Trim() }
      break
    }
  }
  return $null
}
# The three TransferFile declarations are distinguished by what precedes them in
# the file, so anchor on the enclosing type instead of the (identical) signature.
function CoveredForType([string]$TypeName) {
  $inType = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^\s*$TypeName\s*=\s*(class|interface)") { $inType = $true; continue }
    if ($inType -and $lines[$i] -match '^\s*end;') { $inType = $false; continue }
    if ($inType -and $lines[$i] -match 'Covered by:') {
      return ($lines[$i] -replace '.*Covered by:\s*', '' -replace '</para>.*', '').Trim()
    }
  }
  return $null
}

Write-Host ''
Write-Host '-- the defect: an unprovable attribution' -ForegroundColor Cyan
$beta = CoveredForType 'TBeta'
Write-Host "  TBeta.TransferFile -> $beta" -ForegroundColor DarkGray
Check 'TBeta has a Covered by: line at all' ($null -ne $beta) ''
if ($null -ne $beta) {
  # Alpha_with never touches TBeta. The fact is KEPT per the ruling, and MARKED.
  Check 'the cross-attributed test IS listed (kept, per the ruling -- not dropped)' `
    ($beta -match 'Alpha_with') $beta
  Check 'and it is MARKED unverified' ($beta -match 'Alpha_with \(unverified\)') $beta
  # POSITIVE CONTROL on the same line: a real, receiver-anchored caller.
  Check 'CONTROL: the genuine caller Beta_direct is listed' ($beta -match 'Beta_direct') $beta
  Check 'CONTROL: and is NOT marked -- "mark everything" fails here' `
    ($beta -notmatch 'Beta_direct \(unverified\)') $beta
}

Write-Host ''
Write-Host '-- the real target is marked too: nothing PROVED it either' -ForegroundColor Cyan
$alpha = CoveredForType 'TAlpha'
Write-Host "  TAlpha.TransferFile -> $alpha" -ForegroundColor DarkGray
Check 'TAlpha lists Alpha_with' ($null -ne $alpha -and $alpha -match 'Alpha_with') "$alpha"
Check 'and marks it unverified -- being RIGHT is not the same as being PROVEN' `
  ($null -ne $alpha -and $alpha -match 'Alpha_with \(unverified\)') "$alpha"

Write-Host ''
Write-Host '-- NEGATIVE CONTROL: a free routine is never marked' -ForegroundColor Cyan
# An unqualified call to a routine in scope HAS no receiver. Counting those as
# suspect is what inflated a real handful into a reported 3,882.
$plainLine = @($lines | Where-Object { $_ -match 'Covered by:.*Helper_bare' }) | Select-Object -First 1
Check 'PlainHelper is covered by Helper_bare' ($null -ne $plainLine) ''
if ($null -ne $plainLine) {
  Check 'and is NOT marked unverified' ($plainLine -notmatch 'Helper_bare \(unverified\)') $plainLine.Trim()
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- idempotence: the marking must not fight doc-drift' -ForegroundColor Cyan
# Scoped to the `Covered by:` lines ON PURPOSE. A whole-file hash is NOT stable
# on this fixture, and the instability is in a DIFFERENT fact: `Called from:`
# lists its two callers in one order on the first apply and the other on the
# second. That is pre-existing and orthogonal -- docp2 never showed it because
# its fixture has a single caller per target -- and it is filed separately. A
# guard for the marking must not fail on it, and must not paper over it either.
$before = @(((Get-Content -LiteralPath $target -Raw) -replace "`r`n", "`n") -split "`n" | Where-Object { $_ -match 'Covered by:' })
& $Exe index $fixDir --db $db 2>$errFile | Out-Null
& $Exe document --unit $target --db $db --apply 2>$errFile | Out-Null
$after = @(((Get-Content -LiteralPath $target -Raw) -replace "`r`n", "`n") -split "`n" | Where-Object { $_ -match 'Covered by:' })
Check 'the Covered by: lines are non-empty (the check is not vacuous)' ($before.Count -ge 3) "count=$($before.Count)"
Check 'and identical after reindex + a second apply' `
  (($before -join '|') -eq ($after -join '|')) `
  ("before=" + ($before -join ' // ').Trim() + "  after=" + ($after -join ' // ').Trim())

Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
