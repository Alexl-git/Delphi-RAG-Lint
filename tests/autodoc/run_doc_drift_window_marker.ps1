<#
  run_doc_drift_window_marker.ps1 -- a `(+N more)` window marker is not an
  entry, so a block whose marker-carrying last visible entry does not reappear
  verbatim in the fresh render stays auto-fixable when everything it loses is
  vouched for -- and is refused when entries hidden inside the stored window
  may have been lost.

  THE DEFECT (1.20.3 Task 3, measured 2026-09-29). doc-drift reported
  "managed facts block is out of date -- names facts in unit(s) this index
  does not hold; not auto-fixed" on 12 blocks in the convrules-editor and on
  DRagLint.Refactor.TextEdit.TTextEdit in drag-lint's own index. Five of those
  blocks were inspected. In two (BlockFile:30, TextEdit:24) only the window
  count changed:

    stored : Used by: A (X.pas), ..., E (X.pas) (+42 more)
    fresh  : Used by: A (X.pas), ..., E (X.pas) (+43 more)

  In the other three (MainForm:318, RuleCatalog:142, Model:76) the visible
  window also SHIFTED: the last visible entry changed, or visible entries left
  the window. The other seven were inferred from all twelve turning FIXABLE.
  The common trigger: the marker-carrying last visible entry did not reappear
  verbatim in the fresh render (a count change OR a window shift).

  TSharedFacts.RegenerationDropsUnvouchable split the inbound content WITHOUT
  WithoutMoreSuffix, so the last visible entry carried the marker, matched
  nothing in the fresh set, and was read as naming a unit called '+42 more'
  that no index holds. Every sibling reader (BlockHoldsUnvouchable,
  ReconcileContent, ReconcileDropsUnvouchable) already strips the marker.

  CASE-WINDOW  : an engine-written window whose count grows by one new
                 in-closure caller must be reported AND fixable. RED before the
                 fix.
  CONTROL-FOREIGN (positive control): the SAME window shape whose last visible
                 entry names a unit the closure does NOT hold (an uncertain
                 ' ?' entry, which keeps the block out of reconciliation) must
                 still be refused. A fix that simply ignored the windowed entry
                 would turn this red.
  CASE-SHIFT   : a new caller that sorts FIRST pushes the stored last visible
                 entry out of the window (S2..S6 (+1 more) -> S1..S5 (+2 more)).
                 The total grew and the one visible drop names a held unit, so
                 it is fixable (the MainForm:318 / RuleCatalog:142 shape).
  CASE-UNWINDOWED: a stored window whose fresh render is no longer windowed
                 because a VISIBLE in-closure caller left (U1..U5 (+1 more) ->
                 U2..U6). The shrink is exactly the visible, vouched drop, so
                 it is fixable.
  CASE-HIDDEN-LOSS (1.20.3 fix wave, M1): a stored window whose hidden count
                 is larger than what the fresh render can account for (H1..H5
                 (+2 more) -> H1..H5), with no visible drop. The two hidden
                 entries were never examined -- a block written from a wider
                 index can hide a foreign caller there -- so the fix must be
                 refused and --fix --apply must keep the window.
  CASE-PUSHED-OUT (M1): a new caller that sorts first pushes the stored last
                 visible entry INTO the fresh window while two hidden entries
                 leave (P2..P6 (+2 more) -> P1..P5 (+1 more)). P6 is missing
                 from the fresh visible list but sorts after its last entry, so
                 it may only be hidden -- not a proven drop -- and the net loss
                 of one is unaccounted for: refused. Counting P6 as a drop would
                 wrongly balance the loss and turn this red.

  Scratch folder + scratch DB only; the project index is built with
  `index --project` over a throwaway .dpr.

  Usage: pwsh -File tests\autodoc\run_doc_drift_window_marker.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

$W = Join-Path $env:TEMP ("drag-lint-window-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $W | Out-Null
$crlf = "`r`n"
function WriteAscii($path, $lines) {
  [IO.File]::WriteAllText($path, (($lines -join $crlf) + $crlf), (New-Object Text.ASCIIEncoding))
}
function Run([string[]]$xs) {
  $o = & $Exe @xs 2>&1 | Out-String
  [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE }
}
# The /// block directly above the first line matching $declPat, joined.
function BlockAbove([string]$path, [string]$declPat) {
  $ls = [IO.File]::ReadAllLines($path)
  $d = -1
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match $declPat) { $d = $i; break } }
  if ($d -lt 0) { return '' }
  $acc = @()
  for ($i = $d - 1; $i -ge 0; $i--) {
    if ($ls[$i] -notmatch '^\s*///') { break }
    $acc = , $ls[$i] + $acc
  }
  return ($acc -join "`n")
}
function CallerUnit([int]$n) {
  $ls = @('unit uCallers;', 'interface')
  for ($i = 1; $i -le $n; $i++) { $ls += "procedure C$i;" }
  $ls += 'procedure D1;'
  $ls += @('implementation', 'uses uTarget;')
  for ($i = 1; $i -le $n; $i++) { $ls += "procedure C$i; begin Target; end;" }
  $ls += 'procedure D1; begin Target2; end;'
  $ls += 'end.'
  return $ls
}
# uCallers2: each pair is @(callerName, targetName); an empty target means the
# caller calls nothing.
function CallerUnit2($pairs) {
  $ls = @('unit uCallers2;', 'interface')
  foreach ($p in $pairs) { $ls += "procedure $($p[0]);" }
  $ls += @('implementation', 'uses uTarget;')
  foreach ($p in $pairs) {
    if ($p[1]) { $ls += "procedure $($p[0]); begin $($p[1]); end;" }
    else { $ls += "procedure $($p[0]); begin end;" }
  }
  $ls += 'end.'
  return $ls
}
# Before: Target3 <- S2..S7, Target4 <- H1..H5, Target5 <- U1..U6.
#         Target6 <- P2..P8.
# After : Target3 gains S1, U1 stops calling Target5, the H callers are unchanged;
#         Target6 gains P1 and loses P7 and P8.
function Callers2Pairs([bool]$after) {
  $ps = @()
  if ($after) { $ps += , @('S1', 'Target3') }
  for ($i = 2; $i -le 7; $i++) { $ps += , @("S$i", 'Target3') }
  for ($i = 1; $i -le 5; $i++) { $ps += , @("H$i", 'Target4') }
  $ps += , @('U1', $(if ($after) { '' } else { 'Target5' }))
  for ($i = 2; $i -le 6; $i++) { $ps += , @("U$i", 'Target5') }
  if ($after) { $ps += , @('P1', 'Target6') }
  for ($i = 2; $i -le 8; $i++) {
    $ps += , @("P$i", $(if ($after -and $i -ge 7) { '' } else { 'Target6' }))
  }
  return , $ps
}

Push-Location $W
try {
  $tgt = Join-Path $W 'uTarget.pas'
  WriteAscii $tgt @(
    'unit uTarget;', 'interface',
    'procedure Target;', 'procedure Target2;',
    'procedure Target3;', 'procedure Target4;', 'procedure Target5;', 'procedure Target6;',
    'implementation',
    'procedure Target; begin end;', 'procedure Target2; begin end;',
    'procedure Target3; begin end;', 'procedure Target4; begin end;',
    'procedure Target5; begin end;', 'procedure Target6; begin end;',
    'end.')
  WriteAscii (Join-Path $W 'uCallers.pas') (CallerUnit 6)
  WriteAscii (Join-Path $W 'uCallers2.pas') (CallerUnit2 (Callers2Pairs $false))
  $dpr = Join-Path $W 'Prod.dpr'
  WriteAscii $dpr @('program Prod;',
    "uses uTarget in 'uTarget.pas', uCallers in 'uCallers.pas', uCallers2 in 'uCallers2.pas';",
    'begin', 'end.')
  $db = Join-Path $W 'prod.sqlite'

  $r = Run @('index', '--project', $dpr, '--db', $db)
  Check 'setup: project index built' ($r.Code -eq 0) "exit $($r.Code)"
  $r = Run @('document', '--unit', $tgt, '--db', $db, '--apply')
  Check 'setup: fact blocks written' ($r.Code -eq 0) "exit $($r.Code)"

  $blk = BlockAbove $tgt '^procedure Target;'
  Check 'FIXTURE: Target''s engine-written block carries a (+1 more) window' ($blk -match '\(\+1 more\)') $blk

  # Positive-control block: same window shape, but the last visible entry names
  # a unit this closure does not hold. The ' ?' keeps the block out of
  # reconciliation (BlockHoldsUnvouchable skips uncertain entries), so the
  # plain regeneration path -- the one under test -- decides it.
  $src = [IO.File]::ReadAllText($tgt)
  $src2 = [regex]::Replace($src,
    '(?m)^(///\s*<para>Called from: uCallers\.D1 \(uCallers\.pas\))(</para>)',
    '$1, uGone.Lost (uGone.pas) ? (+1 more)$2')
  Check 'FIXTURE: the foreign window landed in Target2''s block' ($src2 -ne $src)

  # CASE-HIDDEN-LOSS fixture: Target4's engine-written block is un-windowed
  # (five callers); a window of two hidden entries is added by hand, as a block
  # written from a wider index would carry it.
  $b4 = BlockAbove $tgt '^procedure Target4;'
  Check 'FIXTURE: Target4''s engine-written block is un-windowed' (($b4 -match 'uCallers2\.H5 \(uCallers2\.pas\)</para>') -and ($b4 -notmatch 'more\)')) $b4
  $src3 = [regex]::Replace($src2,
    '(?m)^(///\s*<para>Called from: uCallers2\.H1 [^<]*uCallers2\.H5 \(uCallers2\.pas\))(</para>)',
    '$1 (+2 more)$2')
  Check 'FIXTURE: the hidden window landed in Target4''s block' ($src3 -ne $src2)
  [IO.File]::WriteAllText($tgt, $src3, (New-Object Text.ASCIIEncoding))

  $b3 = BlockAbove $tgt '^procedure Target3;'
  Check 'FIXTURE: Target3''s stored window ends at S6 (+1 more)' ($b3 -match 'uCallers2\.S6 \(uCallers2\.pas\) \(\+1 more\)') $b3
  $b5 = BlockAbove $tgt '^procedure Target5;'
  Check 'FIXTURE: Target5''s stored window ends at U5 (+1 more)' ($b5 -match 'uCallers2\.U5 \(uCallers2\.pas\) \(\+1 more\)') $b5
  $b6 = BlockAbove $tgt '^procedure Target6;'
  Check 'FIXTURE: Target6''s stored window ends at P6 (+2 more)' ($b6 -match 'uCallers2\.P6 \(uCallers2\.pas\) \(\+2 more\)') $b6

  # One more in-closure caller: the fresh window grows to (+2 more) and the
  # five visible entries are unchanged (C7 sorts after C5). In uCallers2, S1
  # joins Target3's callers and U1 leaves Target5's.
  WriteAscii (Join-Path $W 'uCallers.pas') (CallerUnit 7)
  WriteAscii (Join-Path $W 'uCallers2.pas') (CallerUnit2 (Callers2Pairs $true))
  $r = Run @('index', '--project', $dpr, '--db', $db)
  Check 'setup: reindexed after the new caller' ($r.Code -eq 0) "exit $($r.Code)"

  $fresh = (Run @('document', '--qname', 'uTarget.Target', '--db', $db)).Out
  Check 'FIXTURE: the fresh render carries (+2 more)' ($fresh -match '\(\+2 more\)') ''
  Check 'FIXTURE: the fresh render keeps C5 as the last visible entry' ($fresh -match 'uCallers\.C5 \(uCallers\.pas\) \(\+2 more\)') ''
  $fresh3 = (Run @('document', '--qname', 'uTarget.Target3', '--db', $db)).Out
  Check 'FIXTURE: Target3''s fresh window shifted to S5 (+2 more)' ($fresh3 -match 'uCallers2\.S5 \(uCallers2\.pas\) \(\+2 more\)') ''
  $fresh5 = (Run @('document', '--qname', 'uTarget.Target5', '--db', $db)).Out
  Check 'FIXTURE: Target5''s fresh render is un-windowed and ends at U6' (($fresh5 -match 'uCallers2\.U6 \(uCallers2\.pas\)') -and ($fresh5 -notmatch 'more\)')) ''
  $fresh6 = (Run @('document', '--qname', 'uTarget.Target6', '--db', $db)).Out
  Check 'FIXTURE: Target6''s fresh window is P1..P5 (+1 more)' ($fresh6 -match 'uCallers2\.P5 \(uCallers2\.pas\) \(\+1 more\)') ''

  # --- CASE-WINDOW -----------------------------------------------------------
  $t = (Run @('doc-drift', '--qname', 'uTarget.Target', '--db', $db)).Out
  Check 'CASE-WINDOW a grown window is reported' ($t -match 'ddFactsBlockStale') $t.Trim()
  Check 'CASE-WINDOW a grown window is FIXABLE' ($t -match '\[FIXABLE\]') $t.Trim()
  Check 'CASE-WINDOW no "not auto-fixed" refusal' ($t -notmatch 'not auto-fixed') $t.Trim()

  # --- CONTROL-FOREIGN -------------------------------------------------------
  $t2 = (Run @('doc-drift', '--qname', 'uTarget.Target2', '--db', $db)).Out
  Check 'CONTROL-FOREIGN the foreign window is reported' ($t2 -match 'ddFactsBlockStale') $t2.Trim()
  Check 'CONTROL-FOREIGN the foreign window is NOT fixable' ($t2 -notmatch '\[FIXABLE\]') $t2.Trim()
  Check 'CONTROL-FOREIGN the refusal names the unheld unit' ($t2 -match 'not auto-fixed') $t2.Trim()

  # --- CASE-SHIFT ------------------------------------------------------------
  $t3 = (Run @('doc-drift', '--qname', 'uTarget.Target3', '--db', $db)).Out
  Check 'CASE-SHIFT a shifted window is reported' ($t3 -match 'ddFactsBlockStale') $t3.Trim()
  Check 'CASE-SHIFT a shifted window is FIXABLE' ($t3 -match '\[FIXABLE\]') $t3.Trim()
  Check 'CASE-SHIFT no "not auto-fixed" refusal' ($t3 -notmatch 'not auto-fixed') $t3.Trim()

  # --- CASE-UNWINDOWED -------------------------------------------------------
  $t5 = (Run @('doc-drift', '--qname', 'uTarget.Target5', '--db', $db)).Out
  Check 'CASE-UNWINDOWED a window that closed on a visible drop is reported' ($t5 -match 'ddFactsBlockStale') $t5.Trim()
  Check 'CASE-UNWINDOWED a window that closed on a visible drop is FIXABLE' ($t5 -match '\[FIXABLE\]') $t5.Trim()
  Check 'CASE-UNWINDOWED no "not auto-fixed" refusal' ($t5 -notmatch 'not auto-fixed') $t5.Trim()

  # --- CASE-HIDDEN-LOSS (M1) -------------------------------------------------
  $t4 = (Run @('doc-drift', '--qname', 'uTarget.Target4', '--db', $db)).Out
  Check 'CASE-HIDDEN-LOSS a shrunken hidden window is reported' ($t4 -match 'ddFactsBlockStale') $t4.Trim()
  Check 'CASE-HIDDEN-LOSS a shrunken hidden window is NOT fixable' ($t4 -notmatch '\[FIXABLE\]') $t4.Trim()
  Check 'CASE-HIDDEN-LOSS the fix is refused' ($t4 -match 'not auto-fixed') $t4.Trim()

  # --- CASE-PUSHED-OUT (M1) --------------------------------------------------
  $t6 = (Run @('doc-drift', '--qname', 'uTarget.Target6', '--db', $db)).Out
  Check 'CASE-PUSHED-OUT a pushed-out window with a hidden loss is reported' ($t6 -match 'ddFactsBlockStale') $t6.Trim()
  Check 'CASE-PUSHED-OUT a pushed-out window with a hidden loss is NOT fixable' ($t6 -notmatch '\[FIXABLE\]') $t6.Trim()
  Check 'CASE-PUSHED-OUT the fix is refused' ($t6 -match 'not auto-fixed') $t6.Trim()

  # --- end to end: --fix --apply repairs the vouched ones, preserves the rest -
  $null = Run @('lint-all', '--db', $db, '--rule', 'doc-drift', '--fix', '--apply')
  $after1 = BlockAbove $tgt '^procedure Target;'
  $after2 = BlockAbove $tgt '^procedure Target2;'
  $after3 = BlockAbove $tgt '^procedure Target3;'
  $after4 = BlockAbove $tgt '^procedure Target4;'
  $after5 = BlockAbove $tgt '^procedure Target5;'
  $after6 = BlockAbove $tgt '^procedure Target6;'
  Check 'FIX --fix --apply rewrote Target''s window to (+2 more)' ($after1 -match '\(\+2 more\)') $after1
  Check 'FIX --fix --apply kept the foreign entry in Target2''s block' ($after2 -match 'uGone\.Lost') $after2
  Check 'FIX --fix --apply shifted Target3''s window to S1..S5 (+2 more)' (($after3 -match 'uCallers2\.S1 ') -and ($after3 -match 'uCallers2\.S5 \(uCallers2\.pas\) \(\+2 more\)')) $after3
  Check 'FIX --fix --apply kept Target4''s hidden window' ($after4 -match 'uCallers2\.H5 \(uCallers2\.pas\) \(\+2 more\)') $after4
  Check 'FIX --fix --apply closed Target5''s window on U2..U6' (($after5 -match 'uCallers2\.U6 \(uCallers2\.pas\)</para>') -and ($after5 -notmatch 'uCallers2\.U1 ')) $after5
  Check 'FIX --fix --apply kept Target6''s stored window' ($after6 -match 'uCallers2\.P6 \(uCallers2\.pas\) \(\+2 more\)') $after6
}
finally {
  Pop-Location
  Remove-Item -Recurse -Force -LiteralPath $W -ErrorAction SilentlyContinue
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
