<#
  run_doc_p3_emptytags.ps1 -- Auto-Document Phase 3, Task 3: omit-when-empty.
  <summary>/<param>/<returns> are emitted only when there is content; a
  managed-and-empty tag is dropped entirely (never a blank stub); a human's
  own empty tag (no marker) is preserved verbatim.

  Fixture fixtures\docp3\emptytags.pas:
    * NoDocs(AValue: Integer): Integer -- UNDOCUMENTED. Has a mined return
      case (Result := AValue) so it gets a real <returns>, but NOTHING to say
      for <summary>/<param> (no hand-written prose, no harvester yet) -- both
      must be entirely ABSENT from the fresh comment. It IS called from
      HumanBlanks, so it still gets a facts block (Called from:).
    * HumanBlanks(AValue: Integer): Integer -- ALREADY carries a HAND-WRITTEN
      but EMPTY <summary></summary> and <param name="AValue"></param> (no
      marker) -- a human holding the slot open. Both must survive byte-
      identical: unmarked-and-empty is preserved, not regenerated/dropped.

  Drives `index` -> `document --unit --apply` and asserts:
    1. NoDocs's emitted block has NO <summary> tag and NO <param> tag.
    2. NoDocs DOES get a <returns> (mined case), carrying AUTO_MARK.
    3. NoDocs still gets its facts block (Called from: -- proves suppression
       removed only the empty tags, not the whole comment).
    4. HumanBlanks's hand-written empty <summary></summary> and
       <param name="AValue"></param> are STILL present and carry NO marker.
    5. Idempotency: reindex + a second --apply is byte-identical.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\emptytags.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp3emptytags'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'emptytags.pas'
$db     = Join-Path $scratch 'docp3emptytags.sqlite'
Copy-Item $fixture $target -Force

# Returns the contiguous run of ///-prefixed lines immediately above the FIRST
# line matching $declPattern. $null if the declaration is not found. Same
# scan-upward idiom run_doc_p3_provenance.ps1 uses.
function Get-DocBlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $blockLines = @()
  $j = $idx - 1
  while ($j -ge 0 -and $lines[$j].TrimStart() -match '^///') { $blockLines = ,($lines[$j]) + $blockLines; $j-- }
  return ($blockLines -join "`n")
}

$MARK = '<!-- drag-lint:auto -->'

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  Check 'document --apply #1 exits 0' ($LASTEXITCODE -eq 0)

  $lines = [IO.File]::ReadAllLines($target)

  # --- NoDocs: fresh managed comment -- nothing to say for summary/param ---
  $noDocsBlock = Get-DocBlockAbove $lines '^function NoDocs\(AValue: Integer\): Integer;'
  Check 'NoDocs decl found' ($null -ne $noDocsBlock)

  Check '1. NoDocs has NO <summary> tag (nothing to say)' `
    ($null -eq $noDocsBlock -or (-not ($noDocsBlock -match '<summary>'))) $noDocsBlock
  # v(PHASE A3, ruling D-3) reverses v(ADP3 T3) here: STRUCTURE ALWAYS, MEANING
  # ONLY WHERE THE SOURCE CARRIES IT. The old rule -- no <param> unless a human
  # wrote a description -- was itself the defect: doc-drift reported those tags as
  # missing while `document` refused to write them, so the two halves could never
  # converge. The tag is now emitted, engine-marked, with an EMPTY body.
  Check '1. NoDocs HAS an engine-marked <param> tag with an EMPTY body' `
    (($null -ne $noDocsBlock) -and ($noDocsBlock -match [regex]::Escape('<param name="AValue"><!-- drag-lint:auto --></param>'))) $noDocsBlock

  $noDocsReturns = $null
  if ($null -ne $noDocsBlock) {
    $noDocsReturns = ($noDocsBlock -split "`n") | Where-Object { $_ -match '<returns>' } | Select-Object -First 1
  }
  Check '2. NoDocs <returns> line found (mined return case)' ($null -ne $noDocsReturns) $noDocsBlock
  if ($null -ne $noDocsReturns) {
    Check '2. NoDocs <returns> carries AUTO_MARK immediately after the opening tag' `
      ($noDocsReturns -match [regex]::Escape('<returns>' + $MARK)) $noDocsReturns
    Check '2. NoDocs <returns> carries the mined Observed case' `
      ($noDocsReturns -match 'Observed:\s*AValue\.') $noDocsReturns
  }

  Check '3. NoDocs still gets a facts block (Called from: -- proves the whole comment was not dropped)' `
    ($null -ne $noDocsBlock -and ($noDocsBlock -match '<!-- drag-lint:auto BEGIN -->') -and ($noDocsBlock -match 'Called from:.*emptytags\.HumanBlanks')) $noDocsBlock

  # --- HumanBlanks: hand-written EMPTY summary/param -- survive unmarked ---
  $humanBlock = Get-DocBlockAbove $lines '^function HumanBlanks\(AValue: Integer\): Integer;'
  Check 'HumanBlanks decl found' ($null -ne $humanBlock)

  # PHASE C B7 (user rulings 2026-08-09) INVERTS both of these, and the two tags
  # part company because the rulings treat them differently:
  #
  #   "Empty sections are omitted."  -> <summary> carries prose and nothing else,
  #   so an empty one is a blank DocInsight tooltip. It is REMOVED, and removed
  #   even though it is unmarked: an empty element has no content to preserve, so
  #   the ownership rule that protects hand prose has nothing to protect. This is
  #   what lets a regeneration finally clear tags an older engine emitted (39 of
  #   them on the YADF corpus, immortal until now).
  #
  #   "Autodocument has to produce the param section" -> <param> is STRUCTURAL,
  #   mirroring the signature, so the tag STAYS. What changes is that the empty
  #   one is regenerated (and therefore marked) rather than frozen, so a
  #   description mined later can fill it. The undocumented-ness is reported by
  #   the LINTER (doc-param-no-description, now warning), not by leaving a blank
  #   tag in the source.
  # Scoped to HumanBlanks's OWN block, not the whole file: NoDocs also declares
  # AValue, so a file-wide count of that tag is 2 and would fail for a reason
  # that has nothing to do with what is being asserted.
  Check '4. HumanBlanks empty <summary> is REMOVED (empty sections are omitted)' `
    ($humanBlock -notmatch '<summary>\s*</summary>') $humanBlock
  Check '4. HumanBlanks <param name="AValue"> STAYS (structure mirrors the signature)' `
    ($humanBlock -match '<param name="AValue">') $humanBlock
  Check '4. ... and it is now engine-marked, so a mined description can fill it' `
    ($humanBlock -match [regex]::Escape('<param name="AValue"><!-- drag-lint:auto --></param>')) $humanBlock
  # NOTE: HumanBlanks is a real function with a mined return case (Result :=
  # AValue) and NO pre-existing <returns> tag of its own, so it legitimately
  # GAINS a brand-new managed <returns> (Rule 3) -- the doc block as a whole
  # is NOT marker-free; only the two HAND-WRITTEN tags above must stay
  # unmarked, which the two byte-identical checks above already prove.

  # --- 5. Idempotency: reindex (facts are index-time) + re-apply -> no change ---
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $after = [IO.File]::ReadAllBytes($target)
  Check '5. idempotent: file byte-identical after reindex + 2nd apply' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
