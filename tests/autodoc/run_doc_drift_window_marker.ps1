<#
  run_doc_drift_window_marker.ps1 -- a `(+N more)` window marker is not an
  entry, so a block whose only change is the window COUNT stays auto-fixable.

  THE DEFECT (1.20.3 Task 3, measured 2026-09-29). doc-drift reported
  "managed facts block is out of date -- names facts in unit(s) this index
  does not hold; not auto-fixed" on 12 blocks in the convrules-editor and on
  DRagLint.Refactor.TextEdit.TTextEdit in drag-lint's own index. In every
  measured case the stored and fresh blocks differed ONLY in the window count:

    stored : Used by: A (X.pas), ..., E (X.pas) (+42 more)
    fresh  : Used by: A (X.pas), ..., E (X.pas) (+43 more)

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

Push-Location $W
try {
  $tgt = Join-Path $W 'uTarget.pas'
  WriteAscii $tgt @(
    'unit uTarget;', 'interface',
    'procedure Target;', 'procedure Target2;',
    'implementation',
    'procedure Target; begin end;', 'procedure Target2; begin end;',
    'end.')
  WriteAscii (Join-Path $W 'uCallers.pas') (CallerUnit 6)
  $dpr = Join-Path $W 'Prod.dpr'
  WriteAscii $dpr @('program Prod;', "uses uTarget in 'uTarget.pas', uCallers in 'uCallers.pas';", 'begin', 'end.')
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
  [IO.File]::WriteAllText($tgt, $src2, (New-Object Text.ASCIIEncoding))

  # One more in-closure caller: the fresh window grows to (+2 more) and the
  # five visible entries are unchanged (C7 sorts after C5).
  WriteAscii (Join-Path $W 'uCallers.pas') (CallerUnit 7)
  $r = Run @('index', '--project', $dpr, '--db', $db)
  Check 'setup: reindexed after the new caller' ($r.Code -eq 0) "exit $($r.Code)"

  $fresh = (Run @('document', '--qname', 'uTarget.Target', '--db', $db)).Out
  Check 'FIXTURE: the fresh render carries (+2 more)' ($fresh -match '\(\+2 more\)') ''
  Check 'FIXTURE: the fresh render keeps C5 as the last visible entry' ($fresh -match 'uCallers\.C5 \(uCallers\.pas\) \(\+2 more\)') ''

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

  # --- end to end: --fix --apply repairs one, preserves the other -------------
  $null = Run @('lint-all', '--db', $db, '--rule', 'doc-drift', '--fix', '--apply')
  $after1 = BlockAbove $tgt '^procedure Target;'
  $after2 = BlockAbove $tgt '^procedure Target2;'
  Check 'FIX --fix --apply rewrote Target''s window to (+2 more)' ($after1 -match '\(\+2 more\)') $after1
  Check 'FIX --fix --apply kept the foreign entry in Target2''s block' ($after2 -match 'uGone\.Lost') $after2
}
finally {
  Pop-Location
  Remove-Item -Recurse -Force -LiteralPath $W -ErrorAction SilentlyContinue
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
