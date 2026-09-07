<#
  run_doc_exception_transitive_writer.ps1 -- the WRITER half of the transitive
  <exception cref> story (INBOX-exception-cref-transitive-raise, gap 2).

  THE GAP THIS PINS
  -----------------
  doc-drift has walked ONE hop since session 47: a routine whose body only
  delegates, documented with an <exception cref> the CALLEE justifies, is
  accepted rather than reported as drift (Drift.pas CalleeRaisesType, pinned by
  run_doc_exception_transitive.ps1).

  The WRITER never learned the same fact. `document` mined the routine's OWN
  body and nothing else, so it would never WRITE the tag the checker was
  already willing to ACCEPT. The two halves of one feature disagreed, and the
  disagreement was invisible because each half's guard only tested its own half.

  WHY A SEPARATE FIXTURE. transitive.pas cannot show this: every declaration
  there is hand-documented, and the writer's contract is that a hand-written
  cref is PRESERVED VERBATIM (assertion 13 below pins exactly that). Session 75
  proposed ViaHelper there as the RED case; measured, it can never go red.
  transitive_writer.pas exists so the writer can be tested on UNDOCUMENTED
  declarations, and transitive.pas stays byte-identical so its six assertions
  keep meaning what its header says.

  RED, MEASURED ON THE DEPLOYED ENGINE BEFORE ANY src\ CHANGE (2026-09-07).
  `document --unit transitive_writer.pas --apply` wrote exactly four exception
  tags, all of them own-body:

      HelperRaise      <exception cref="EBoom">...-->boom</exception>
      OtherRaise       <exception cref="EOther">...-->other</exception>
      NoDocOwnAndVia   <exception cref="EBoom">...-->mine</exception>
      NoDocRecursive   <exception cref="EBoom">...-->rec</exception>

  and NOTHING for NoDocDelegates, NoDocMulti, NoDocTwoVia or NoDocFanOut.
  The full RED baseline, run end-to-end on the deployed engine:

      RED    1, 2b, 6, 7, 8, 9a, 11
      GREEN  2a, 3, 4, 5, 10b, 12, 13a, 13b, 13c
      GREEN BUT VACUOUS  9b and 10a -- doc-drift cannot report a tag that was
                         never written, and a via cannot be reaped if none
                         exists. Each is paired with a companion (9a, 10b)
                         precisely so it cannot pass for that reason later.

  3, 4 and 5 being green BEFORE the fix is the point: they are what stops the
  fix from being "tag everything that calls something".

  All 13 call edges in the fixture resolve `certain` (verified with `sql`), so
  a missing tag is a writer gap and not a resolution gap.

  TWO PROBE TRAPS, both hit while writing this and both worth keeping in mind:
    * `document --qname` RENDERS AN EDIT. Once a declaration is fully
      documented there is no edit, so it returns EMPTY -- it is the right probe
      before an --apply and the wrong one after. Assertions that read applied
      output use ExcBodiesInFile.
    * an --apply moves every declaration's line number, so a render against the
      pre-apply index also returns nothing. Re-index after every apply.

  Usage: pwsh -File tests\autodoc\run_doc_exception_transitive_writer.ps1
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Fixture = "$PSScriptRoot\fixtures\docdrift\transitive_writer.pas",
  [string]$Human   = "$PSScriptRoot\fixtures\docdrift\transitive.pas"
)

$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]), $n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if (-not $ok -and $d) { Write-Host "        $d" -ForegroundColor DarkGray }
  if (-not $ok) { $script:fail = $true }
}

$exePath = (Resolve-Path $Exe).Path
$fixPath = (Resolve-Path $Fixture).Path
$humPath = (Resolve-Path $Human).Path

# A scratch name of this runner's own. Two runners sharing one fixed scratch
# directory is a real defect this repo has already shipped once -- see
# run_battery_jobs_guard.ps1's uniqueness check, which polices this name.
$scratch = Join-Path C:\TEMP 'draglint_doc_exc_transitive_writer'
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
$srcDir = Join-Path $scratch 'src'
New-Item -ItemType Directory -Path $srcDir | Out-Null

# The after-image lives OUTSIDE the indexed folder. Dropping a copy INSIDE it
# adds a second unit with the same declarations to the index, which makes every
# call edge ambiguous and quietly changes the answer.
$afterDir = Join-Path $scratch 'after'
New-Item -ItemType Directory -Path $afterDir | Out-Null

$target = Join-Path $srcDir 'transitive_writer.pas'
$db     = Join-Path $scratch 'w.sqlite'

function ResetFixture {
  Copy-Item $fixPath $target -Force
  & $exePath index $srcDir --db $db 2>$null | Out-Null
}
# `document --qname` RENDERS the block without writing it. That is the right
# probe for "what does the emitter produce", and it keeps the phases below
# independent of rewrite round-tripping (run_doc_idempotent owns that).
function DocFor([string]$QName) {
  return (& $exePath document --qname $QName --db $db 2>$null | Out-String)
}
# The emitter wraps a long tag body across `/// ` continuation lines, so a via
# attribution can be split mid-name. Flatten before asserting on content.
function Flat([string]$Doc) {
  return (($Doc -replace "`r?`n\s*///\s?", ' ') -replace '\s+', ' ')
}
# Reading a tag back out of an APPLIED FILE, which is not the same probe as
# rendering. `document --qname` prints an edit; once a declaration is fully
# documented there is no edit to print and it returns EMPTY. Using the renderer
# after an --apply therefore reports "no tag" for a declaration whose tag is
# sitting right there in the file -- which is exactly how 10b first failed.
function ExcBodiesInFile([string]$FileText, [string]$DeclName) {
  $i = $FileText.IndexOf($DeclName + ';')
  if ($i -lt 0) { return @() }
  $before = $FileText.Substring(0, $i)
  # The doc block is the trailing run of `///` lines immediately above the decl.
  $lines = @($before -split "`r?`n")
  # $before ends mid-line (immediately before the declaration keyword), so the
  # split leaves a trailing EMPTY element. Walking back from it stops at once
  # and reports an empty doc block for a declaration that has one.
  while ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -eq '') {
    $lines = $lines[0..($lines.Count - 2)]
  }
  $blk = New-Object System.Collections.Generic.List[string]
  for ($k = $lines.Count - 1; $k -ge 0; $k--) {
    if ($lines[$k] -match '^\s*///') { $blk.Insert(0, $lines[$k]) } else { break }
  }
  return (ExcBodies ($blk -join "`r`n"))
}
# Every exception tag body, flattened, for one rendered declaration.
function ExcBodies([string]$Doc) {
  $f = Flat $Doc
  return @([regex]::Matches($f, '<exception cref="([^"]+)">(.*?)</exception>') | ForEach-Object {
    [pscustomobject]@{ Cls = $_.Groups[1].Value; Body = ($_.Groups[2].Value -replace '<!--.*?-->', '').Trim() }
  })
}

Write-Host '== doc exception: transitive WRITER ==' -ForegroundColor Cyan

Push-Location C:\TEMP
try {
  ResetFixture
  Check 'fixture indexed' (Test-Path $db) $db

  # ---------------------------------------------------------------------
  # PHASE 1 -- what the emitter renders
  # ---------------------------------------------------------------------
  Write-Host ''
  Write-Host 'PHASE 1: rendering' -ForegroundColor Cyan

  $delegates = ExcBodies (DocFor 'transitive_writer.NoDocDelegates')
  $helper    = ExcBodies (DocFor 'transitive_writer.HelperRaise')
  $ownAndVia = ExcBodies (DocFor 'transitive_writer.NoDocOwnAndVia')
  $twoHops   = ExcBodies (DocFor 'transitive_writer.NoDocTwoHops')
  $rtlOnly   = ExcBodies (DocFor 'transitive_writer.NoDocRtlOnly')
  $recursive = ExcBodies (DocFor 'transitive_writer.NoDocRecursive')
  $multi     = ExcBodies (DocFor 'transitive_writer.NoDocMulti')
  $twoVia    = ExcBodies (DocFor 'transitive_writer.NoDocTwoVia')
  $fanOut    = ExcBodies (DocFor 'transitive_writer.NoDocFanOut')

  # 1 -- THE FIX.
  Check '1 NoDocDelegates gets an EBoom tag attributed to its callee' `
    ($delegates.Count -eq 1 -and $delegates[0].Cls -eq 'EBoom' -and
     $delegates[0].Body -eq 'via transitive_writer.HelperRaise: boom') `
    ("got: " + (($delegates | ForEach-Object { "$($_.Cls)='$($_.Body)'" }) -join ' | '))

  # 2 -- POSITIVE CONTROL. An own raise still leads, and is still attributed to
  #      nobody. Without this, assertion 1 passes for a writer that tags blindly.
  Check '2a HelperRaise still carries its OWN message, unattributed' `
    ($helper.Count -eq 1 -and $helper[0].Cls -eq 'EBoom' -and $helper[0].Body -eq 'boom') `
    ("got: " + (($helper | ForEach-Object { "$($_.Cls)='$($_.Body)'" }) -join ' | '))
  Check '2b NoDocOwnAndVia puts its OWN message first, then the via' `
    ($ownAndVia.Count -eq 1 -and $ownAndVia[0].Cls -eq 'EBoom' -and
     $ownAndVia[0].Body -eq 'mine; via transitive_writer.HelperRaise: boom') `
    ("got: " + (($ownAndVia | ForEach-Object { "$($_.Cls)='$($_.Body)'" }) -join ' | '))

  # 3 -- DEPTH PIN. Mirrors CONTROL-4 in the checker's guard. Both sides read
  #      ONE constant; if the writer ever walks deeper than the checker accepts,
  #      it emits tags the checker cannot clear -- permanently unfixable findings.
  Check '3 NoDocTwoHops gets NO tag (one hop is the bound, both sides)' `
    ($twoHops.Count -eq 0) `
    ("got: " + (($twoHops | ForEach-Object { "$($_.Cls)='$($_.Body)'" }) -join ' | '))

  # 4 -- FAIL-SAFE. An unresolved callee is absence of information.
  Check '4 NoDocRtlOnly gets NO tag (unresolved callee is not evidence)' `
    ($rtlOnly.Count -eq 0) `
    ("got: " + (($rtlOnly | ForEach-Object { "$($_.Cls)='$($_.Body)'" }) -join ' | '))

  # 5 -- RECURSION. The self-edge must contribute nothing.
  Check '5 NoDocRecursive is exactly its own message, with no self-attribution' `
    ($recursive.Count -eq 1 -and $recursive[0].Body -eq 'rec') `
    ("got: " + (($recursive | ForEach-Object { "$($_.Cls)='$($_.Body)'" }) -join ' | '))

  # 6 -- TWO CLASSES, each via its own callee, in class order.
  Check '6 NoDocMulti gets EBoom then EOther, each via its own callee' `
    ($multi.Count -eq 2 -and
     $multi[0].Cls -eq 'EBoom'  -and $multi[0].Body -eq 'via transitive_writer.HelperRaise: boom' -and
     $multi[1].Cls -eq 'EOther' -and $multi[1].Body -eq 'via transitive_writer.OtherRaise: other') `
    ("got: " + (($multi | ForEach-Object { "$($_.Cls)='$($_.Body)'" }) -join ' | '))

  # 7 -- ORDER. GetCallEdgesFromSymbol has no ORDER BY, so without an explicit
  #      sort this alternates between runs and the emitted doc churns.
  #      The fixture calls Zz FIRST so file order and alpha order disagree.
  Check '7 NoDocTwoVia lists its callees in name order, not edge-row order' `
    ($twoVia.Count -eq 1 -and
     $twoVia[0].Body -eq 'via transitive_writer.AaRaise: aa; via transitive_writer.ZzRaise: zz') `
    ("got: " + (($twoVia | ForEach-Object { "$($_.Cls)='$($_.Body)'" }) -join ' | '))

  # 8 -- CAP. Four callees, three named, then the remainder counted.
  Check '8 NoDocFanOut names three callees then counts the rest' `
    ($fanOut.Count -eq 1 -and
     $fanOut[0].Body -eq 'via transitive_writer.FanA: a; via transitive_writer.FanB: b; via transitive_writer.FanC: c (+1 more)') `
    ("got: " + (($fanOut | ForEach-Object { "$($_.Cls)='$($_.Body)'" }) -join ' | '))

  # ---------------------------------------------------------------------
  # PHASE 2 -- writer and checker must AGREE, and the write must settle
  # ---------------------------------------------------------------------
  Write-Host ''
  Write-Host 'PHASE 2: agreement with doc-drift, and idempotence' -ForegroundColor Cyan

  & $exePath document --unit $target --db $db --apply --no-backup 2>$null | Out-Null
  & $exePath index $srcDir --db $db 2>$null | Out-Null
  Copy-Item $target (Join-Path $afterDir 'pass1.pas') -Force
  $applied = Get-Content -LiteralPath $target -Raw

  # 9 -- AGREEMENT. Both halves, or the check is vacuous: a doc-drift that is
  #      silent because no tag was written proves nothing at all.
  $drift = (& $exePath doc-drift --qname 'transitive_writer.NoDocDelegates' --db $db --json 2>$null | Out-String)
  Check '9a the tag assertion 1 wanted is actually IN the file' `
    ($applied -match 'via transitive_writer\.HelperRaise: boom') `
    'without this, 9b is silent-because-empty'
  Check '9b doc-drift does not report the tag the writer just wrote' `
    ($drift -notmatch 'ddExceptionNotRaised') `
    'writer and checker disagree -- the exact defect this feature exists to remove'

  # 12 -- BYTE IDENTITY. A second apply on an unchanged tree must change nothing.
  $h1 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
  & $exePath document --unit $target --db $db --apply --no-backup 2>$null | Out-Null
  $h2 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
  Check '12 a second --apply leaves the file byte-identical' ($h1 -eq $h2) `
    "sha256 $h1 -> $h2"

  # ---------------------------------------------------------------------
  # PHASE 3 -- OWNERSHIP: an engine-written via must be REAPED when the
  # evidence for it goes away, or the doc rots in the opposite direction.
  # ---------------------------------------------------------------------
  Write-Host ''
  Write-Host 'PHASE 3: reaping' -ForegroundColor Cyan

  $txt = Get-Content -LiteralPath $target -Raw
  $txt = $txt.Replace("raise EBoom.Create('boom');", "WriteLn('boom');")
  [System.IO.File]::WriteAllText($target, $txt, [System.Text.Encoding]::ASCII)
  & $exePath index $srcDir --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply --no-backup 2>$null | Out-Null
  # Re-index after the apply, exactly as phase 2 does. An apply moves every
  # declaration's line number, so rendering against the pre-apply index returns
  # NOTHING -- which looks like "the tag was reaped" and would have made 10b
  # fail for a reason that has nothing to do with reaping.
  & $exePath index $srcDir --db $db 2>$null | Out-Null
  Copy-Item $target (Join-Path $afterDir 'reaped.pas') -Force
  $reaped = Get-Content -LiteralPath $target -Raw

  Check '10a the via tag is GONE once the callee stops raising' `
    ($reaped -notmatch 'via transitive_writer\.HelperRaise') `
    'an engine-owned attribution that survives its evidence is doc rot'
  # POSITIVE CONTROL for 10a: the own half must SURVIVE the same reap, or 10a
  # passes for a writer that simply deleted everything.
  $ownAfter = ExcBodiesInFile $reaped 'procedure NoDocOwnAndVia'
  Check '10b NoDocOwnAndVia keeps its OWN message through the reap' `
    ($ownAfter.Count -eq 1 -and $ownAfter[0].Body -eq 'mine') `
    ("got: " + (($ownAfter | ForEach-Object { "$($_.Cls)='$($_.Body)'" }) -join ' | '))

  # ---------------------------------------------------------------------
  # PHASE 4 -- a RENAMED callee must be re-attributed by the writer.
  # (doc-drift staying silent here is a documented limitation, not a bug:
  #  it does not grade exception description text at all.)
  # ---------------------------------------------------------------------
  Write-Host ''
  Write-Host 'PHASE 4: rename' -ForegroundColor Cyan

  ResetFixture
  & $exePath document --unit $target --db $db --apply --no-backup 2>$null | Out-Null
  # Rename the CODE only. A blanket regex over the whole file also rewrites the
  # `via transitive_writer.HelperRaise` sitting in the doc comment -- which
  # leaves the doc already correct, gives the dry run nothing to say, and turns
  # this into an assertion about the test's own sed. Ask the question properly:
  # the code moves, the doc does not, and the writer must notice.
  $renamed = @(Get-Content -LiteralPath $target | ForEach-Object {
    if ($_ -match '^\s*///') { $_ } else { $_ -replace '\bHelperRaise\b', 'HelperRaise2' }
  })
  [System.IO.File]::WriteAllText($target, (($renamed -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
  & $exePath index $srcDir --db $db 2>$null | Out-Null
  $dry = (& $exePath document --unit $target --db $db 2>$null | Out-String)
  # Anchored on the VIA text, not merely on the new name. The managed remarks
  # block also carries `<para>Calls: ... HelperRaise</para>`, so a bare
  # `-match 'HelperRaise2'` passes on an engine that never emitted a via at all
  # -- it would have been satisfied by the Calls line alone.
  Check '11 a dry run after renaming the callee re-attributes the via' `
    ((Flat $dry) -match 'via transitive_writer\.HelperRaise2') `
    'the writer owns this text, so a stale callee name must be rewritten'

  # ---------------------------------------------------------------------
  # PHASE 5 -- THE LINE THIS FEATURE MUST NOT CROSS.
  # Emitting a via is not licence to touch what a human wrote.
  # ---------------------------------------------------------------------
  Write-Host ''
  Write-Host 'PHASE 5: a human tag is still untouchable' -ForegroundColor Cyan

  $hDir = Join-Path $scratch 'human'
  New-Item -ItemType Directory -Path $hDir | Out-Null
  $hTarget = Join-Path $hDir 'transitive.pas'
  $hDb     = Join-Path $scratch 'h.sqlite'
  Copy-Item $humPath $hTarget -Force
  & $exePath index $hDir --db $hDb 2>$null | Out-Null
  & $exePath document --unit $hTarget --db $hDb --apply --no-backup 2>$null | Out-Null
  Copy-Item $hTarget (Join-Path $afterDir 'human.pas') -Force
  $hAfter = Get-Content -LiteralPath $hTarget -Raw

  Check '13a ViaHelper keeps the human sentence verbatim' `
    ($hAfter -match '<exception cref="EBoom">Raised by the helper\.</exception>') `
    'the writer preserves a hand-written cref -- this is the ownership contract'
  Check '13b and did NOT stamp it as engine-owned' `
    ($hAfter -notmatch 'Raised by the helper\.[\s\S]{0,40}drag-lint:auto exc') `
    'an AUTO_EXC marker on a human sentence means the engine claimed it'
  & $exePath index $hDir --db $hDb 2>$null | Out-Null
  $hDrift = (& $exePath doc-drift --qname 'transitive.StillWrong' --db $hDb --json 2>$null | Out-String)
  Check '13c StillWrong is STILL reported (the rule was not weakened)' `
    ($hDrift -match 'ddExceptionNotRaised') `
    'if emitting a via silences ENever, the checker lost its teeth'
}
finally {
  Pop-Location
}

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
