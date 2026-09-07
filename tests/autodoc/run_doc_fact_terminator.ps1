<#
  run_doc_fact_terminator.ps1 -- session 76.

  ONE runner for FOUR filed defects, because they are ONE bug plus one
  neighbour. Fixture: tests\autodoc\fixtures\factterm.

  THE ROOT CAUSE (D1, D2, D3). DRagLint.Doc.SharedFacts.ParseBlock ends a
  fact's content at the next LABEL only, never at the next TAG. LabelContent
  received exactly that missing clause; ParseBlock did not. The over-long slice
  reaches EntryUnitKey / UnitVouchable and reads as an entry this index "cannot
  vouch for", which switches foreign-entry participation ON where it should be
  OFF. Three symptoms follow:

    D1  a <para>Used in units: ...</para> swallows the sibling <seealso> tags
        below it, and GROWS by the whole set on every later apply -- x4, x8,
        x12 -- with no fixed point.
    D2  a decayed type's facts block is never reaped: the writer says
        "unchanged" for ever while doc-drift calls it fixable.
    D3  spurious participation switches SortedJoin on, so inbound lists are
        written in store order once and alphabetical order thereafter.

  THE NEIGHBOUR (D4). The stored-side parse is fed text OUTSIDE the fence, so a
  human's backticked MENTION of an inbound label is merged in as a real fact
  line. It reaches a FIXED POINT immediately, so it never heals on its own; it
  put three junk lines into this repo's own committed source (the b42a7e7
  sweep).

  WHY THE FIXTURE LOOKS THE WAY IT DOES -- three properties, each measured, each
  of which a "tidier" fixture silently destroys:

  * NO COMMENT SITS ABOVE A DECLARATION in Zed.Types.pas. A decl-adjacent
    comment is harvested into a <summary>; a decl that HAS a summary never
    produces an empty fresh render, and the empty-render branch is where D2
    lives. Measured: with summaries present the decayed blocks reap correctly
    and Section B goes GREEN against the unfixed engine. The rationale lives in
    this header for exactly that reason.
  * TInner is NESTED inside TOuter. <seealso> crefs for a type come from the
    sibling ROUTINES of the PARENT TYPE, so only a nested type renders crefs
    directly after its 'Used in units:' line -- and that adjacency IS D1's
    mechanism. A top-level class gets no siblings and cannot reproduce it.
  * THE UNIT NAMES ARE LOAD-BEARING. 'Echo' sorts before 'Zed' by FILE while
    'Echo.Client.Note' sorts AFTER 'declaration' by QUALIFIED NAME. A fixture
    whose two orders agree is byte-identical across cycles WITH the bug present
    and proves nothing (session 75 lost a pass to 'Alpha.Client' for this).

  Also load-bearing: TMode is the WORKING CONTROL. Its last inbound label takes
  parenthesised entries and EntryUnitKey reads the key out of the parentheses,
  so the trailing marker is ignored and it reaps TODAY. Without it, Section B
  could pass by the writer simply deleting nothing anywhere.

  RED TRANSCRIPT (frozen copy of 1.10.1-alpha, the shipped Win64 Debug build,
  measured 2026-09-07 before any source change). Every assertion below was RED
  except the ones marked CONTROL, which were green and must stay green:
    A1  apply 2 reports '2/12 decl(s) documented, 4 edit(s)'; files differ.
    A2  'Used in units: Zed.Types, Zed.Types' + 4 <seealso> inside the para
        after apply 2; 8 after apply 3.
    A4  doc-drift on a corrupted block -> fixable:false 'not auto-fixed';
        an apply GROWS it to 12.
    B5  document --qname -> "unchanged" for TInner AND TRep (want "removed").
    B7  doc-drift -> NO FINDING AT ALL for TInner; fixable:true for TRep that
        the apply never clears.
    C1  TRep 'Used by: Echo.Client.Note (...), declaration (...)' (store order).
    C2  TMode the same, and never canonicalised by any later run.
    C3  apply 2 is not byte-identical.
    D9  the human prose line gains a space inside its backticks.
    D10 two junk fact lines are inserted and a bare backtick entry is appended.

  Run from a NEUTRAL CWD (C:\TEMP). pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $(if ($d) { "  --  $d" } else { '' })) `
    -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:fail = $true }
}
function Section($t) { Write-Host ''; Write-Host "=== $t ===" -ForegroundColor Cyan }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\factterm')).Path
$BT      = [char]96   # a literal backtick, kept out of every PowerShell string literal

function WriteAscii([string]$p, [string]$t) {
  [IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}

# The /// lines immediately preceding the first declaration matching $rx, so an
# assertion can never bleed into a neighbouring declaration's comment.
function Get-Block([string]$file, [string]$rx) {
  $lines = [IO.File]::ReadAllLines($file)
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $rx) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $out = @()
  for ($i = $idx - 1; $i -ge 0; $i--) { if ($lines[$i] -notmatch '^\s*///') { break }; $out = , $lines[$i] + $out }
  return ($out -join "`n")
}

# A <seealso> that starts while a <para> is still open. Same shape the tree
# guard scans for; kept local so this runner stands alone.
function Get-SwallowCount([string]$block) {
  $n = 0
  foreach ($l in ($block -split "`n")) {
    if ($l.TrimStart() -notmatch '^///') { continue }
    $p = $l.IndexOf('<para>'); if ($p -lt 0) { continue }
    $close = $l.IndexOf('</para>', $p); $see = $l.IndexOf('<seealso', $p)
    if ($see -lt 0) { continue }
    if ($close -lt 0 -or $see -lt $close) { $n += ([regex]::Matches($l.Substring($p), '<seealso')).Count }
  }
  return $n
}

# The text strictly between AUTO_BEGIN and AUTO_END, i.e. the engine-owned
# region. Everything else in the block is the human's.
function Get-Fence([string]$block) {
  $lines = $block -split "`n"; $b = -1; $e = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($b -lt 0 -and $lines[$i] -match 'drag-lint:auto BEGIN') { $b = $i; continue }
    if ($b -ge 0 -and $lines[$i] -match 'drag-lint:auto END') { $e = $i; break }
  }
  if ($b -lt 0 -or $e -lt 0) { return '' }
  return (($lines[($b + 1)..($e - 1)]) -join "`n")
}

# Rewrites ONE line inside the /// block belonging to the declaration matching
# $rx. Seeds are edited BY POSITION, never by matching the entry text: the
# canonical-order fix legitimately changes what a Used by: line says, and a seed
# regex that encodes today's order silently stops seeding anything the moment it
# lands -- which reads as a defect in the fix. $edit receives the line and
# returns its replacement (or an array, to insert).
function Edit-BlockLine([string]$file, [string]$declRx, [string]$lineRx, [scriptblock]$edit) {
  $lines = [Collections.Generic.List[string]]::new()
  [IO.File]::ReadAllLines($file) | ForEach-Object { [void]$lines.Add($_) }
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declRx) { $idx = $i; break } }
  if ($idx -lt 0) { return $false }
  for ($i = $idx - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    if ($lines[$i] -match $lineRx) {
      $new = & $edit $lines[$i]
      $lines.RemoveAt($i)
      $lines.InsertRange($i, [string[]]@($new))
      WriteAscii $file ($lines -join "`r`n")
      return $true
    }
  }
  return $false
}

function New-Work([string]$name) {
  $w = Join-Path 'C:\TEMP' $name
  if (Test-Path $w) { Remove-Item $w -Recurse -Force }
  New-Item -ItemType Directory $w | Out-Null
  Copy-Item (Join-Path $fixture '*') $w -Force
  return $w
}
function Idx($w)   { & $exePath index --project (Join-Path $w 'factterm.dpr') --db (Join-Path $w 'f.sqlite') 2>&1 | Out-Null }
function Doc($w, $unit) { & $exePath document --unit (Join-Path $w $unit) --db (Join-Path $w 'f.sqlite') --apply 2>$null }

Push-Location C:\TEMP
try {

# ============================================================ A + C + D: apply 1
Section 'apply 1 -- inbound order (D3), human prose (D4), positive controls'

$w1  = New-Work 'draglint_factterm'
$zed = Join-Path $w1 'Zed.Types.pas'
$ech = Join-Path $w1 'Echo.Client.pas'
Idx $w1
Doc $w1 'Zed.Types.pas'  | Out-Null
Doc $w1 'Echo.Client.pas' | Out-Null
Check 'apply 1 exits 0' ($LASTEXITCODE -eq 0)

$bRep  = Get-Block $zed '^\s*TRep = record'
$bMode = Get-Block $zed '^\s*TMode = \('
$bWide = Get-Block $zed '^\s*TWide = record'
$bIn   = Get-Block $zed '^\s*TInner = record'
$bGam  = Get-Block $ech '^\s*procedure Gamma;'
Check 'all five fixture blocks were written' `
  (($bRep -and $bMode -and $bWide -and $bIn -and $bGam) -ne $false)

# --- C1/C2: canonical inbound order on the FIRST write -----------------------
Check 'C1 TRep Used by: is canonical on apply 1 (declaration before Echo.Client.Note)' `
  ($bRep -match '<para>Used by: declaration \(Zed\.Types\.pas\), Echo\.Client\.Note \(Echo\.Client\.pas\)</para>') `
  'RED today: Echo.Client.Note first (store order)'
Check 'C2 TMode Used by: is canonical on apply 1' `
  ($bMode -match '<para>Used by: declaration \(Zed\.Types\.pas\), Echo\.Client\.Note \(Echo\.Client\.pas\)</para>') `
  'RED today: reversed, and never canonicalised by any later run'

# --- C4 CONTROL: membership is unchanged by any ordering fix -----------------
Check 'C4 CONTROL: TRep Used in units: still names both units' `
  ($bRep -match '<para>Used in units: Echo\.Client, Zed\.Types</para>')
Check 'C4 CONTROL: TRep Used by: still has exactly 2 entries' `
  ((([regex]::Matches((($bRep -split "`n") | Where-Object { $_ -match 'Used by:' }) -join '', '\(\w')).Count) -eq 2)

# --- C8 CONTROL: the sort runs AFTER the cap, so the five shown do not move ---
# Under sort-BEFORE-cap this line would show Echo.Client.Note and drop W5.
Check 'C8 CONTROL: TWide truncated list is still W1..W5 (+3 more)' `
  ($bWide -match '<para>Used by: Echo\.Client\.W1 \(Echo\.Client\.pas\), Echo\.Client\.W2 \(Echo\.Client\.pas\), Echo\.Client\.W3 \(Echo\.Client\.pas\), Echo\.Client\.W4 \(Echo\.Client\.pas\), Echo\.Client\.W5 \(Echo\.Client\.pas\) \(\+3 more\)</para>') `
  'green today; sorting before the cap would change WHICH callers are shown'

# --- A3 CONTROL: the fix must not "stop swallowing" by dropping the crefs -----
Check 'A3 CONTROL: TInner fence still carries all four standalone <seealso> lines' `
  ((([regex]::Matches($bIn, '^\s*///\s*<seealso cref="Zed\.Types\.TOuter\.\w+"/>\s*$', 'Multiline')).Count) -eq 4)
Check 'A3 CONTROL: TInner Used by: still names Create, Ping and Pong' `
  (($bIn -match 'Zed\.Types\.TOuter\.Create') -and ($bIn -match 'Zed\.Types\.TOuter\.Ping') -and ($bIn -match 'Zed\.Types\.TOuter\.Pong'))
Check 'A3 CONTROL: TInner Used in units: line is exactly Zed.Types' `
  ($bIn -match '<para>Used in units: Zed\.Types</para>')

# --- D9/D10: a MENTION of a label in human prose is not a fact ---------------
$proseWanted = '/// <para>An INBOUND list (' + $BT + 'Called from:' + $BT + ', ' + $BT + 'Used by:' + $BT + ', ' + $BT + 'Used in units:' + $BT + ') is prose.</para>'
$proseLine   = (($bGam -split "`n") | Where-Object { $_ -match 'An INBOUND list' } | Select-Object -First 1)
Check 'D9 the human prose line is byte-identical after apply 1' `
  ($proseLine.Trim() -eq $proseWanted.Trim()) `
  ('RED today: a space appears inside the backticks. got: ' + $proseLine.Trim())

$fenceGam = Get-Fence $bGam
$junk = @(($fenceGam -split "`n") | Where-Object { $_ -match $BT })
Check 'D10 no fact line in Gamma''s fence contains a backtick' ($junk.Count -eq 0) `
  ('RED today: 2 inserted junk lines + a bare backtick entry. got: ' + (($junk | ForEach-Object { $_.Trim() }) -join ' || '))
Check 'D10 Gamma''s fence Called from: names exactly the real caller' `
  ($fenceGam -match '<para>Called from: Echo\.Client\.Note \(Echo\.Client\.pas\)</para>')

# --- D11 CONTROL: fence scoping must not leak into summary ownership ---------
Check 'D11 CONTROL: Gamma''s hand-written <summary> survives byte-identical' `
  ($bGam -match '(?m)^///\s*<summary>Gamma does a thing\.</summary>\s*$')
Check 'D11 CONTROL: exactly one AUTO_BEGIN/AUTO_END pair was added to Gamma' `
  ((([regex]::Matches($bGam, 'drag-lint:auto BEGIN')).Count -eq 1) -and (([regex]::Matches($bGam, 'drag-lint:auto END')).Count -eq 1))

# ============================================================ A + C: apply 2
Section 'apply 2 -- idempotency (D1 accumulation, D3 churn)'

$zedBefore = [IO.File]::ReadAllBytes($zed)
$echBefore = [IO.File]::ReadAllBytes($ech)
Idx $w1
$o2z = Doc $w1 'Zed.Types.pas'
Doc $w1 'Echo.Client.pas' | Out-Null
$zedAfter = [IO.File]::ReadAllBytes($zed)
$echAfter = [IO.File]::ReadAllBytes($ech)

Check 'A1/C3 Zed.Types.pas is BYTE-IDENTICAL after a reindexed second apply' `
  ([Linq.Enumerable]::SequenceEqual([byte[]]$zedBefore, [byte[]]$zedAfter)) `
  'RED today: 2/12 decl(s), 4 edit(s). An edit COUNT is worthless here -- assert bytes.'
Check 'A1/C3 Echo.Client.pas is BYTE-IDENTICAL after a reindexed second apply' `
  ([Linq.Enumerable]::SequenceEqual([byte[]]$echBefore, [byte[]]$echAfter))
Check 'A1 the second apply reports nothing to document for Zed.Types.pas' `
  ((($o2z -join ' ') -match 'nothing to document')) `
  (($o2z | Select-String 'decl|edit|nothing') -join ' | ')

$bIn2 = Get-Block $zed '^\s*TInner = record'
Check 'A2 no <seealso> is swallowed inside TInner''s <para> after apply 2' `
  ((Get-SwallowCount $bIn2) -eq 0) `
  ('RED today: 4 after apply 2, 8 after apply 3 -- it grows without a fixed point')
Check 'A2 TInner Used in units: does not duplicate the unit name' `
  ($bIn2 -notmatch 'Used in units: Zed\.Types, Zed\.Types')

# ============================================================ B: decay / reaping
Section 'decay -- a type nobody uses any more must be reaped (D2)'

$w2 = New-Work 'draglint_factterm_decay'
# Start from the well-formed apply-1 state, then remove every USE of TInner,
# TRep and TMode. The declarations stay; only their users go.
Copy-Item $zed (Join-Path $w2 'Zed.Types.pas') -Force
Copy-Item $ech (Join-Path $w2 'Echo.Client.pas') -Force
$dz = Join-Path $w2 'Zed.Types.pas'; $de = Join-Path $w2 'Echo.Client.pas'
$z = [IO.File]::ReadAllText($dz)
$z = $z -replace 'FItems: TList<TInner>;', 'FItems: TList<Integer>;'
$z = $z -replace 'function Pong: TInner;', 'function Pong: Integer;'
$z = $z -replace 'FItems := TList<TInner>\.Create;', 'FItems := TList<Integer>.Create;'
$z = $z -replace "var`r`n  R: TInner;`r`nbegin`r`n  R\.Verdict := 1;`r`n  FItems\.Add\(R\);", "begin`r`n  FItems.Add(1);"
$z = $z -replace 'function TOuter\.Pong: TInner;', 'function TOuter.Pong: Integer;'
$z = $z -replace 'function Probe\(AMax: Integer = 3\): TRep;', 'function Probe(AMax: Integer = 3): Integer;'
$z = $z -replace 'Result\.Verdict := AMax;', 'Result := AMax;'
$z = $z -replace 'function Mode\(AFlag: Boolean\): TMode;', 'function Mode(AFlag: Boolean): Integer;'
$z = $z -replace 'if AFlag then Result := mFast else Result := mSlow;', 'if AFlag then Result := 1 else Result := 0;'
WriteAscii $dz $z
$e = [IO.File]::ReadAllText($de)
$e = $e -replace 'Rep: TRep;', 'Rep: Integer;'
$e = $e -replace 'M: TMode;', 'M: Integer;'
$e = $e -replace 'Mode\(Rep\.Verdict > 0\)', 'Mode(Rep > 0)'
$e = $e -replace 'if \(M = mFast\) and \(V\.Verdict = 0\) then O\.Pong;', 'if (M = 1) and (V.Verdict = 0) then O.Pong;'
WriteAscii $de $e
Idx $w2

# The decay must actually have happened, or every assertion below is vacuous.
$refsLeft = 0
foreach ($n in 'TInner', 'TRep', 'TMode') {
  $r = (& $exePath sql --db (Join-Path $w2 'f.sqlite') --query "SELECT count(*) AS n FROM refs WHERE name='$n'" 2>$null) -join ' '
  if ($r -match '(\d+)') { $refsLeft += [int]$Matches[1] }
}
Check 'DECAY SANITY: no ref anywhere still names TInner, TRep or TMode' ($refsLeft -eq 0) "refs=$refsLeft"

function DocAction($w, $q) {
  $j = & $exePath document --qname $q --db (Join-Path $w 'f.sqlite') --json 2>$null
  $m = ($j | Select-String -Pattern '"action":"([a-z]+)"' | Select-Object -First 1)
  if ($m) { return $m.Matches[0].Groups[1].Value } else { return '(none)' }
}
function DriftOf($w, $q) { ((& $exePath doc-drift --qname $q --db (Join-Path $w 'f.sqlite') --json 2>$null) -join ' ').Trim() }

$aIn   = DocAction $w2 'Zed.Types.TOuter.TInner'
$aRep  = DocAction $w2 'Zed.Types.TRep'
$aMode = DocAction $w2 'Zed.Types.TMode'
Check 'B5 decayed NESTED type is removed' ($aIn  -eq 'removed') "RED today: $aIn"
Check 'B5 decayed RECORD is removed'      ($aRep -eq 'removed') "RED today: $aRep"
Check 'B6 CONTROL: decayed ENUM is removed (the reap path is alive)' ($aMode -eq 'removed') "got: $aMode"

$dIn  = DriftOf $w2 'Zed.Types.TOuter.TInner'
$dRep = DriftOf $w2 'Zed.Types.TRep'
Check 'B7 doc-drift REPORTS the phantom block on the nested type' `
  ($dIn -match 'ddFactsBlockStale') `
  'RED today: no finding at all -- an empty-render forgiveness hides it'
Check 'B7 doc-drift calls the nested phantom block fixable' ($dIn -match '"fixable":true') $dIn
Check 'B7 doc-drift calls the record phantom block fixable' ($dRep -match '"fixable":true') $dRep

& $exePath document --unit $dz --db (Join-Path $w2 'f.sqlite') --apply 2>$null | Out-Null
Check 'B5 after the apply, TInner''s block is GONE'  ((Get-Block $dz '^\s*TInner = record') -notmatch 'drag-lint:auto BEGIN')
Check 'B5 after the apply, TRep''s block is GONE'    ((Get-Block $dz '^\s*TRep = record')   -notmatch 'drag-lint:auto BEGIN')
Check 'B6 CONTROL: after the apply, TMode''s block is GONE' ((Get-Block $dz '^\s*TMode = \(') -notmatch 'drag-lint:auto BEGIN')

Idx $w2
# Once the block is reaped the declaration has no doc-comment at all, and the
# CLI says so in plain text rather than emitting a finding. What must be gone is
# the STALE-BLOCK finding, not all output.
Check 'B7 the checker agrees after the apply: no stale-block finding for TRep' `
  ((DriftOf $w2 'Zed.Types.TRep') -notmatch 'ddFactsBlockStale') `
  'RED today: fixable:true against a writer that refuses to fix it'

# ============================================================ A4: self-heal
Section 'self-heal -- an ALREADY corrupted block must repair, not just stop growing'

$w3 = New-Work 'draglint_factterm_heal'
Copy-Item $zed (Join-Path $w3 'Zed.Types.pas') -Force
Copy-Item $ech (Join-Path $w3 'Echo.Client.pas') -Force
$hz = Join-Path $w3 'Zed.Types.pas'
# Hand-seed the corrupted line from the RED transcript. Seeded BY HAND on
# purpose: after the fix the engine can no longer produce it, so a test that
# harvested it from a live run would quietly stop testing anything.
$corrupt = '<para>Used in units: Zed.Types, Zed.Types <seealso cref="Zed.Types.TOuter.Create"/> <seealso cref="Zed.Types.TOuter.Destroy"/> <seealso cref="Zed.Types.TOuter.Ping"/> <seealso cref="Zed.Types.TOuter.Pong"/></para>'
$h = [IO.File]::ReadAllText($hz)
$h = $h -replace '<para>Used in units: Zed\.Types</para>', $corrupt
WriteAscii $hz $h
Idx $w3
Check 'SEED SANITY: the corrupted shape really is in the file' `
  ((Get-SwallowCount (Get-Block $hz '^\s*TInner = record')) -eq 4)

$dHeal = DriftOf $w3 'Zed.Types.TOuter.TInner'
Check 'A4 doc-drift calls a corrupted block FIXABLE' `
  ($dHeal -match '"fixable":true') `
  ('RED today: fixable:false "names facts in unit(s) this index does not hold; not auto-fixed". got: ' + $dHeal)

& $exePath document --unit $hz --db (Join-Path $w3 'f.sqlite') --apply 2>$null | Out-Null
$bHeal = Get-Block $hz '^\s*TInner = record'
Check 'A4 the apply REPAIRS the corrupted block' ((Get-SwallowCount $bHeal) -eq 0) `
  ('RED today: it GROWS to 12. got swallowed=' + (Get-SwallowCount $bHeal))
Check 'A4 the repaired line is exactly Used in units: Zed.Types' `
  ($bHeal -match '<para>Used in units: Zed\.Types</para>')
Idx $w3
Check 'A4 the checker is quiet after the repair' ((DriftOf $w3 'Zed.Types.TOuter.TInner') -eq '')

# ============================================================ B8: foreign entry
Section 'foreign-entry control -- "parse the body" must not become "stop merging"'

$w4 = New-Work 'draglint_factterm_foreign'
Copy-Item $zed (Join-Path $w4 'Zed.Types.pas') -Force
Copy-Item $ech (Join-Path $w4 'Echo.Client.pas') -Force
$fz = Join-Path $w4 'Zed.Types.pas'
[void](Edit-BlockLine $fz '^\s*TRep = record' '<para>Used by:' {
  param($l) $l -replace '</para>\s*$', ', Foreign.Unit.Bar (Foreign.Unit.pas)</para>' })
Check 'SEED SANITY: the foreign entry really is in the file' `
  ((Get-Block $fz '^\s*TRep = record') -match 'Foreign\.Unit\.Bar')
Idx $w4
& $exePath document --unit $fz --db (Join-Path $w4 'f.sqlite') --apply 2>$null | Out-Null
Check 'B8 CONTROL: a PLAUSIBLE foreign entry is still preserved' `
  ((Get-Block $fz '^\s*TRep = record') -match 'Foreign\.Unit\.Bar \(Foreign\.Unit\.pas\)') `
  'green today; this is the assertion the junk-entry filter must not break'

# --- B8b: the forms an acceptance-whitelist filter gets WRONG ----------------
# A first cut of the junk filter spelled out the character set of a qualified
# name and so rejected the OVERLOAD form this repo renders in its own source
# ('...TDocDrift.Analyze/4 (...)'). A wrong REJECT deletes a caller only another
# project can see and nothing recovers it, so these two forms are pinned.
$w4b = New-Work 'draglint_factterm_foreign2'
Copy-Item $zed (Join-Path $w4b 'Zed.Types.pas') -Force
Copy-Item $ech (Join-Path $w4b 'Echo.Client.pas') -Force
$fz2 = Join-Path $w4b 'Zed.Types.pas'
[void](Edit-BlockLine $fz2 '^\s*TRep = record' '<para>Used by:' {
  param($l) $l -replace '</para>\s*$', ', Far.Unit.Baz/4 (Far.Unit.pas), Gen.Unit.Qux&lt;T&gt; (Gen.Unit.pas)</para>' })
Idx $w4b
& $exePath document --unit $fz2 --db (Join-Path $w4b 'f.sqlite') --apply 2>$null | Out-Null
$b4b = Get-Block $fz2 '^\s*TRep = record'
Check 'B8b CONTROL: an OVERLOAD-disambiguated foreign entry survives' `
  ($b4b -match 'Far\.Unit\.Baz/4 \(Far\.Unit\.pas\)') `
  'a name may carry /N; rejecting it would silently delete a real caller'
Check 'B8b CONTROL: an escaped GENERIC foreign entry survives' `
  ($b4b -match 'Gen\.Unit\.Qux&lt;T&gt; \(Gen\.Unit\.pas\)') `
  'entries are XML-escaped, so &lt; and &gt; are ordinary name characters here'

# ============================================================ D12: junk filter
Section 'junk-entry filter -- an entry that cannot be a name is not preserved'

$w5 = New-Work 'draglint_factterm_junk'
Copy-Item $zed (Join-Path $w5 'Zed.Types.pas') -Force
Copy-Item $ech (Join-Path $w5 'Echo.Client.pas') -Force
$jz = Join-Path $w5 'Zed.Types.pas'
# Seed a junk fact line INSIDE the fence -- the exact shape the b42a7e7 sweep
# left in this repo's own source. Fence scoping alone cannot remove it (it is
# already inside), so this pins the filter specifically.
[void](Edit-BlockLine $jz '^\s*TRep = record' '<para>Used in units:' {
  param($l)
  $indent = ($l -replace '^(\s*).*$', '$1')
  @(($indent + '/// Used by: ' + [char]96), $l) })
$seeded = Get-Block $jz '^\s*TRep = record'
Check 'SEED SANITY: the junk line really is inside the fence' `
  ((Get-Fence $seeded) -match $BT)
Idx $w5
& $exePath document --unit $jz --db (Join-Path $w5 'f.sqlite') --apply 2>$null | Out-Null
$bJunk = Get-Block $jz '^\s*TRep = record'
Check 'D12 the junk entry is DROPPED, not preserved as a foreign entry' `
  ((Get-Fence $bJunk) -notmatch $BT) `
  'a non-name cannot be a caller in any project, so dropping it destroys nothing'
$beforeJ = [IO.File]::ReadAllBytes($jz)
Idx $w5
& $exePath document --unit $jz --db (Join-Path $w5 'f.sqlite') --apply 2>$null | Out-Null
Check 'D12 and the file is at a fixed point on the next apply' `
  ([Linq.Enumerable]::SequenceEqual([byte[]]$beforeJ, [byte[]][IO.File]::ReadAllBytes($jz)))

} finally { Pop-Location }

Write-Host ''
if ($script:fail) { Write-Host 'DOC FACT TERMINATOR: FAIL' -ForegroundColor Red; exit 1 }
else              { Write-Host 'DOC FACT TERMINATOR: PASS' -ForegroundColor Green; exit 0 }
