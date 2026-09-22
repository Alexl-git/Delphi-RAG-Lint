<#
  run_purity_stage.ps1 -- the `purity` resolve stage end to end (plan C6.1
  Task 3; spec docs\superpowers\specs\2026-09-15-interprocedural-purity.md).

  Indexes the four fixtures under tests\autotest\fixtures\purity into a scratch
  DB and asserts, per routine, the effect_free / effect_summary / effect_witness
  triple the stage must write. Every check names the spec acceptance number it
  encodes. POSITIVE CONTROLS: the not-proven fixtures (effect_free = 0 with an
  EXACT witness) fail if the stage is absent (columns stay NULL, Verdict reads
  -1) or if it wrote 1 for everything; the gate control drops local_var rows
  behind the engine's back and expects the verdict to FLIP; the stale-source
  control edits a file without reindexing and expects the verdict to flip to
  'source changed since indexing' and back after a real reindex.

  Deviations from the task brief (P9, pre-flight): the brief's check 19 used
  `with Self do FCount := 2`, whose own-field write already fills the witness
  slot, so `^with` could never be observed; the body now calls only a PROVEN
  method so `with` is the sole blocker. The brief's 20-control expected a
  'virtual' witness on a bare `inherited;` -- but `inherited;` is a STATIC
  call to the ancestor's implementation, judged by that method's own summary,
  so no virtual witness exists on that path; it is replaced by two controls:
  an ancestor that writes a global (child = g) and one that is proven (child
  proven). Run from a NEUTRAL CWD (C:\TEMP), pwsh 7. Needs python (sqlite3)
  for the gate control: `drag-lint sql` is read-only by design.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_purity_stage"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe      = (Resolve-Path $Exe).Path
$fixtures = (Resolve-Path "$PSScriptRoot\fixtures\purity").Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null
Copy-Item (Join-Path $fixtures '*.pas') $src
$db = Join-Path $WorkDir 's.sqlite'

function Run-Index([string[]]$extra) {
  Push-Location C:\TEMP
  try { return @(& $Exe index $src --db $db @extra 2>&1 | ForEach-Object { "$_" }) } finally { Pop-Location }
}
function Verdict([string]$qname) {
  # Bracket the two text columns in SQL so an EMPTY summary cannot shift the
  # witness into its slot when the text table is split, and match the data row
  # by shape so the trailing 'N row(s) in M ms' line can never be mistaken for it.
  $t = (& $Exe sql --db $db --format text --query "SELECT ifnull(f.effect_free,-1), '[' || ifnull(f.effect_summary,'') || ']', '[' || ifnull(f.effect_witness,'') || ']' FROM symbols s JOIN symbol_facts f ON f.symbol_id=s.id WHERE s.qualified_name='$qname'" 2>&1) -join "`n"
  $m = [regex]::Match($t, '(?m)^\s*(-?\d+)\s+\[(.*?)\]\s+\[(.*)\]\s*$')
  if (-not $m.Success) { return [pscustomobject]@{ ef = -2; es = '<norow>'; ew = '<norow>' } }
  return [pscustomobject]@{ ef = [int]$m.Groups[1].Value; es = $m.Groups[2].Value; ew = $m.Groups[3].Value }
}
function PurityLine([string[]]$o) { return @($o | Where-Object { $_ -match '^\s*resolve: purity -- ' }) -join "`n" }

$out = Run-Index @()
Check '0. fixture indexed' (Test-Path $db) $db

Write-Host 'THE STAGE RAN' -ForegroundColor Cyan
Check '10. one stage: purity -- done in line' ((@($out | Select-String 'stage: purity -- done in')).Count -eq 1) ''
$pl = PurityLine $out
Check '15. the resolve: purity line carries unbound count and top names' ($pl -match 'resolve: purity -- .*\d+ unbound call ref\(s\) \[top: ') $pl
Check '15. the top list names Trim, Free and SubString (the three unbound callees)' (($pl -match 'trim \(1\)') -and ($pl -match 'free \(1\)') -and ($pl -match 'substring \(1\)')) $pl
Check '7. the resolve: purity line carries the unlexable, stale, gated and pass counts' (($pl -match '\d+ unlexable call\(s\)') -and ($pl -match '0 stale file\(s\)') -and ($pl -match '0 gated') -and ($pl -match '\d+ pass\(es\)')) $pl

Write-Host 'SUMMARIES AND TRANSLATION (spec 3)' -ForegroundColor Cyan
$v = Verdict 'uEffects.WriteGlobal';        Check '1. WriteGlobal = g, witness names GCounter'   (($v.ef -eq 0) -and ($v.es -eq 'g') -and ($v.ew -eq 'writes GCounter (non-local)')) "$($v.es) | $($v.ew)"
$v = Verdict 'uEffects.CallsWriteGlobal';   Check '1. caller of a g routine is 0'           (($v.ef -eq 0) -and ($v.es -match 'g') -and ($v.ew -eq 'calls WriteGlobal (writes global state)')) "$($v.es) | $($v.ew)"
$v = Verdict 'uEffects.FillOut';            Check '2. FillOut = p0'                         (($v.ef -eq 0) -and ($v.es -eq 'p0') -and ($v.ew -eq 'writes through parameter #0 (AValue)')) "$($v.es) | $($v.ew)"
$v = Verdict 'uEffects.CallsFillOutLocal';  Check '3. p0 through a local: proven'           ($v.ef -eq 1) "$($v.es) | $($v.ew)"
$v = Verdict 'uEffects.CallsFillOutGlobal'; Check '4. p0 through a global: not proven, witness names FillOut, #0 and GCounter' (($v.ef -eq 0) -and ($v.ew -eq 'writes through FillOut(#0 = GCounter, not classified)')) "$($v.ew)"
$v = Verdict 'uEffects.TThing.GrowLocal';   Check '5. SetLength(LocalArr): proven'          ($v.ef -eq 1) "$($v.es) | $($v.ew)"
$v = Verdict 'uEffects.TThing.GrowField';   Check '5. SetLength(FBuffer): s'                (($v.ef -eq 0) -and ($v.es -eq 's') -and ($v.ew -eq 'writes through SetLength(#0 = FBuffer, a field)')) "$($v.es) | $($v.ew)"
$v = Verdict 'uEffects.AddUp';              Check '6. locals+Result only: empty summary, proven' (($v.ef -eq 1) -and ($v.es -eq '') -and ($v.ew -eq '')) "$($v.es)"
$v = Verdict 'uEffects.TThing.SetCount';    Check 'field setter = s'                        (($v.ef -eq 0) -and ($v.es -eq 's') -and ($v.ew -eq 'writes field FCount')) "$($v.es) | $($v.ew)"

Write-Host 'FIXPOINT (spec 4)' -ForegroundColor Cyan
$v = Verdict 'uCycle.IsEven'; $w = Verdict 'uCycle.IsOdd'
Check '8. mutually recursive pair with no effect: both proven' (($v.ef -eq 1) -and ($w.ef -eq 1)) "$($v.ew) | $($w.ew)"
$a = Verdict 'uCycle.A1'; $b = Verdict 'uCycle.B1'; $c = Verdict 'uCycle.C1'
Check '9. cycle reaching a global write: all three 0' (($a.ef -eq 0) -and ($b.ef -eq 0) -and ($c.ef -eq 0) -and ($a.es -eq 'g') -and ($b.es -eq 'g') -and ($c.es -eq 'g')) "$($a.es)/$($b.es)/$($c.es)"
Check '9. the witness is translated through the call chain' (($c.ew -eq 'writes GHit (non-local)') -and ($b.ew -eq 'calls C1 (writes global state)') -and ($a.ew -eq 'calls B1 (writes global state)')) "$($a.ew) | $($b.ew) | $($c.ew)"
$v = Verdict 'uCycle.SelfLoop';             Check '10. self-loop terminates and is proven'  ($v.ef -eq 1) "$($v.ew)"

Write-Host 'UNBOUND AND INTRINSICS (spec 5)' -ForegroundColor Cyan
$v = Verdict 'uUnbound.CallsTrim';          Check '11. unbound Trim: 0, witness calls Trim (unbound)' (($v.ef -eq 0) -and ($v.es -eq '?') -and ($v.ew -eq 'calls Trim (unbound)')) "$($v.es) | $($v.ew)"
$v = Verdict 'uUnbound.CallsSubString';     Check '11. unbound value-receiver call names the receiver' (($v.ef -eq 0) -and ($v.ew -eq 'calls SubString (unbound; receiver S)')) "$($v.ew)"
$v = Verdict 'uEffects.OnlyIntrinsics';     Check '12. Exit/Length/Ord alone: proven'       ($v.ef -eq 1) "$($v.ew)"
$v = Verdict 'uEffects.FreeIt';             Check '13. Dispose: h'                          (($v.ef -eq 0) -and ($v.es -eq 'h') -and ($v.ew -eq 'calls Dispose (frees storage)')) "$($v.es) | $($v.ew)"
$v = Verdict 'uEffects.NewLocal';           Check '14. New(LocalP) alone: proven'           ($v.ef -eq 1) "$($v.ew)"

Write-Host 'DISPATCH AND MEMBER ACCESS (spec 6, 7)' -ForegroundColor Cyan
$v = Verdict 'uEffects.TThing.CallsVirtual';  Check '16. virtual callee: 0'                  (($v.ef -eq 0) -and ($v.es -eq '?') -and ($v.ew -eq 'calls DoVirtual (virtual/interface dispatch)')) "$($v.es) | $($v.ew)"
$v = Verdict 'uEffects.TThing.MemberWrite';   Check '17. AOther.FCount := 1 (bound member write on a parameter): p0, witness names FCount' (($v.ef -eq 0) -and ($v.es -eq 'p0') -and ($v.ew -eq 'writes AOther.FCount (member)')) "$($v.es) | $($v.ew)"
$v = Verdict 'uEffects.TThing.UnboundMember'; Check '18. unbound member: 0'                  (($v.ef -eq 0) -and ($v.es -eq '?') -and ($v.ew -eq 'calls Free (unbound; receiver AList)')) "$($v.es) | $($v.ew)"
$v = Verdict 'uEffects.TThing.UseWith';       Check '19. with statement (the only blocker): 0, witness ^with' (($v.ef -eq 0) -and ($v.es -eq '?') -and ($v.ew -eq 'with statement')) "$($v.es) | $($v.ew)"
$v = Verdict 'uInherited.TChildOutside.AfterConstruction'; Check '20. inherited with the ancestor outside this DB: 0' (($v.ef -eq 0) -and ($v.es -eq '?') -and ($v.ew -eq 'inherited (ancestor method outside this DB)')) "$($v.es) | $($v.ew)"
$v = Verdict 'uInherited.TChildInDb.Run';     Check '20-control. inherited with the ancestor IN this DB is judged by the callee: ancestor writes a global -> g' (($v.ef -eq 0) -and ($v.es -eq 'g') -and ($v.ew -eq 'calls inherited Run (writes global state)')) "$($v.es) | $($v.ew)"
$v = Verdict 'uInherited.TChildInDb.Quiet';   Check '20-control. inherited with a PROVEN ancestor in this DB: proven' (($v.ef -eq 1) -and ($v.es -eq '')) "$($v.es) | $($v.ew)"
$v = Verdict 'uEffects.AddrEscape';           Check 'T2-ii. a local passed through Addr() escapes: FillOut(L) is not a local write' (($v.ef -eq 0) -and ($v.es -eq '?') -and ($v.ew -eq 'writes through FillOut(#0 = L, not classified)')) "$($v.es) | $($v.ew)"

Write-Host 'THE LOCAL-TABLE GATE (spec 7.3)' -ForegroundColor Cyan
$v = Verdict 'uEffects.TThing.WriteAncestor'; Check '22. ancestor field write is s, witness names TBase' (($v.ef -eq 0) -and ($v.es -eq 's') -and ($v.ew -eq 'writes field FInherited (declared on TBase)')) "$($v.es) | $($v.ew)"
$v = Verdict 'uEffects.TThing.Nested.Inner';  Check '21/23. nested routine with an extracted local is judged (GCounter write -> g), NOT gated' (($v.ef -eq 0) -and ($v.es -eq 'g') -and ($v.ew -eq 'writes GCounter (non-local)')) "$($v.es) | $($v.ew)"
$v = Verdict 'uEffects.TThing.Nested';        Check '21b. the OUTER routine is not gated by the nested routine''s var block: judged through Inner -> g' (($v.ef -eq 0) -and ($v.es -eq 'g') -and ($v.ew -eq 'calls Inner (writes global state)')) "$($v.es) | $($v.ew)"
# POSITIVE CONTROL for the gate: drop the nested routine's local_var rows behind
# the engine's back, re-run purity only, and the verdict must become ? with the
# incomplete-table witness. `drag-lint sql` is read-only, so python's sqlite3
# does the DELETE (the run_purity_storage.ps1 pattern).
$py = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $py) {
  Check '21. gate control: python (sqlite3) available to drop the local_var rows' $false 'python not on PATH'
} else {
  $del = "import sqlite3; c = sqlite3.connect(r'$db'); n = c.execute(""DELETE FROM symbols WHERE kind='local_var' AND parent_id=(SELECT id FROM symbols WHERE qualified_name='uEffects.TThing.Nested.Inner')"").rowcount; c.commit(); c.close(); print(n)"
  $pyOut = (& python -c $del 2>&1) -join "`n"
  Check '21. gate control precondition: exactly one local_var row was dropped' ($pyOut.Trim() -eq '1') $pyOut
  $ro = Run-Index @('--resolve-only')
  Check '21. --resolve-only runs the stage' (($ro -join "`n") -match 'stage: purity -- done in') ''
  $v = Verdict 'uEffects.TThing.Nested.Inner'
  Check '21. gate: var block + no local_var row -> unknown, witness says the local table is incomplete' (($v.ef -eq 0) -and ($v.es -eq '?') -and ($v.ew -eq 'local table incomplete (var declarations without local_var rows)')) "$($v.es) | $($v.ew)"
  $pl = PurityLine $ro
  Check '21. the resolve: purity line counts the gated routine' ($pl -match '1 gated') $pl
}

Write-Host 'PER-FILE REINDEX RESTORES THE COLUMNS (acceptance 28)' -ForegroundColor Cyan
# touch one file so the walk re-parses it (rows recreated with NULL columns), then assert nothing is NULL after the run
$f = Join-Path $src 'uEffects.pas'
[System.IO.File]::SetLastWriteTimeUtc($f, (Get-Date).ToUniversalTime().AddSeconds(5))
$out2 = Run-Index @()
$nulls = (& $Exe sql --db $db --format text --query "SELECT count(*) FROM symbol_facts WHERE ifnull(body_loc,0) > 0 AND effect_free IS NULL" 2>&1) -join "`n"
Check '28. after an incremental run every routine has a verdict again' ($nulls -match '(?m)^\s*0\s*$') $nulls
Check '28. the stage ran on that run' (($out2 -join "`n") -match 'stage: purity -- done in') ''
$v = Verdict 'uEffects.TThing.Nested.Inner'
Check '28. the re-parse restored the local_var row, so the gate no longer fires' (($v.ef -eq 0) -and ($v.es -eq 'g')) "$($v.es) | $($v.ew)"
$out3 = Run-Index @()
Check 'a no-change run SKIPS the stage and says so' (($out3 -join "`n") -match 'stage: purity -- skipped') ''
Check 'a no-change run prints no resolve: purity line' ((PurityLine $out3) -eq '') ''

Write-Host 'STALE SOURCE (plan ruling 7)' -ForegroundColor Cyan
# Edit a file WITHOUT reindexing it: a --resolve-only run must not trust the
# stored refs/lines for that file. Every routine in it becomes ? with the stale
# witness, the line counts one stale file, and a real reindex heals it.
$fc = Join-Path $src 'uCycle.pas'
[System.IO.File]::WriteAllText($fc, ([System.IO.File]::ReadAllText($fc) + "{ edited after indexing }`r`n"), [System.Text.Encoding]::ASCII)
[System.IO.File]::SetLastWriteTimeUtc($fc, (Get-Date).ToUniversalTime().AddSeconds(20))
$ro2 = Run-Index @('--resolve-only')
$v = Verdict 'uCycle.IsEven'
Check 'R7. a routine in a file edited since indexing is ? with the stale witness' (($v.ef -eq 0) -and ($v.es -eq '?') -and ($v.ew -eq 'source changed since indexing')) "$($v.es) | $($v.ew)"
$w = Verdict 'uEffects.AddUp'
Check 'R7. a routine in an UNCHANGED file keeps its verdict' ($w.ef -eq 1) "$($w.es) | $($w.ew)"
$pl = PurityLine $ro2
Check 'R7. the resolve: purity line counts one stale file' ($pl -match '1 stale file\(s\)') $pl
$out4 = Run-Index @()
$v = Verdict 'uCycle.IsEven'
Check 'R7. a real reindex of the edited file restores its verdict' ($v.ef -eq 1) "$($v.es) | $($v.ew)"
Check 'R7. and reports no stale file' ((PurityLine $out4) -match '0 stale file\(s\)') (PurityLine $out4)

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
