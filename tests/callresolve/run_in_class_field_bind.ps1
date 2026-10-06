<#
  run_in_class_field_bind.ps1 -- DEC-19 (owner ruled YES 2026-10-05), resolver
  1.12.0-alpha: a BARE read of a field of the enclosing class, or of one of its
  ANCESTORS, binds to that field.

  THE GAP. Since 1.8.0 a bare own-class PROPERTY read bound (D16a), a bare field
  WRITE bound (D13) and `Self.F` bound -- but a bare field READ declined with
  reason 'field', by design at the time. Measured 2026-09-28: 31,417 such reads
  on ORM3 SERVER, 21,137 on CLIENT. C8 N2a (the converter rewriting a
  descendant's code access sites on an ancestor's converted component) needs
  them bound: `with tblFtrs do` and `tblFtrs.Post` in a method of a class whose
  grand-ancestor declares tblFtrs. The receiver of `tblFtrs.Post` is its own
  `read` ref, so one rule covers all three spellings.

  THE RULE THIS PINS. Delphi's order, nearest first: a `with` target's member,
  then a local / parameter / nested routine of the routine or of the routines
  around it (a SHADOW: nothing binds), then the enclosing class and its
  resolved ancestors. A bound field read gets refs.symbol_id on the field and a
  member_accesses row (mode read, no accessor), and NO call edge.

  POSITIVE CONTROLS: F-SELF, F-PROP, F-WRITE are the spellings that already
  bound before 1.12.0 and must keep binding; a resolver that bound nothing
  would turn every shadow negative green and these red. NEGATIVES: F-SHADOW-*
  (param, local, outer routine's local, with member) and F-UNRELATED (a field
  of an unrelated class that merely shares the name).

  Every line number is READ FROM THE FIXTURE'S markers. `sql --json` rows are
  POSITIONAL arrays; Sql() maps them onto the column names.

  Usage: pwsh -File tests\callresolve\run_in_class_field_bind.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}

$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\infield')).Path
# A fresh directory per run, not a delete: a previous run's index must never
# answer this one.
$scratch = Join-Path (Join-Path C:\TEMP 'draglint_in_class_field_bind') ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
Copy-Item (Join-Path $fixDir '*') $scratch
$use = Join-Path $scratch 'uIfUse.pas'
$db  = Join-Path $scratch 'infield.sqlite'

function Sql([string]$Query) {
  $raw = (& $exePath sql --db $db --json --limit 1000 --query $Query 2>$null) -join "`n"
  $b = $raw.IndexOf('{')
  if ($b -lt 0) { throw "sql returned no JSON for: $Query" }
  $o = $raw.Substring($b) | ConvertFrom-Json
  $names = @($o.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in @($o.rows)) {
    $h = @{}
    for ($i = 0; $i -lt $names.Count; $i++) { $h[$names[$i]] = $r[$i] }
    $out += $h
  }
  return ,@($out)
}
function LineOf([string]$Marker, [string]$File = $use) {
  $m = @(Select-String -LiteralPath $File -Pattern ("// " + [regex]::Escape($Marker) + "\s*$"))
  if ($m.Count -ne 1) { throw "marker '$Marker' found $($m.Count) times in the fixture" }
  return [int]$m[0].LineNumber
}
# Every READ ref named $Name on the marker's line, with what it binds.
function ReadsAt([string]$Marker, [string]$Name, [string]$Unit = 'uIfUse') {
  $Line = LineOf $Marker (Join-Path $scratch "$Unit.pas")
  return Sql ("SELECT r.id, r.kind, s.qualified_name AS sq, s.kind AS sk, ma.mode AS mode, " +
              "ma.accessor_symbol_id AS acc, rt.qualified_name AS rtq, " +
              "(SELECT COUNT(*) FROM call_edges ce WHERE ce.ref_id = r.id) AS edges " +
              "FROM refs r JOIN files f ON f.id = r.file_id " +
              "LEFT JOIN symbols s ON s.id = r.symbol_id " +
              "LEFT JOIN member_accesses ma ON ma.ref_id = r.id " +
              "LEFT JOIN symbols rt ON rt.id = ma.receiver_type_symbol_id " +
              "WHERE f.path LIKE '%\$Unit.pas' AND r.start_line = $Line AND r.name_text = '$Name' " +
              "AND r.kind IN ('read', 'write')")
}
function Show($rows) { return (@($rows | ForEach-Object { "$($_.kind):sid=$($_.sq)/ma=$($_.mode)/rt=$($_.rtq)/edges=$($_.edges)" }) -join '; ') }

Push-Location C:\TEMP
try {
  $log = (& $exePath index $scratch --db $db *>&1) -join "`n"
  Check 'the fixture indexed' (Test-Path $db) ($log.Split("`n") | Select-Object -Last 3) 

  Write-Host '--- DEC-19: a bare field read binds the field on the enclosing class chain'
  $cases = @(
    @{ M = 'F-OWN';      N = 'FOwn';       Q = 'uIfUse.TIfLeaf.FOwn';        Why = 'own class' },
    @{ M = 'F-GETTER';   N = 'FP';         Q = 'uIfUse.TIfLeaf.FP';          Why = 'own class, inside a getter' },
    @{ M = 'F-ANC1';     N = 'FMid';       Q = 'uIfBase.TIfMiddle.FMid';     Why = 'parent, another unit' },
    @{ M = 'F-ANC2';     N = 'FBaseCount'; Q = 'uIfBase.TIfBase.FBaseCount'; Why = 'grand-parent' },
    @{ M = 'F-ANC-RCV';  N = 'tblFtrs';    Q = 'uIfBase.TIfBase.tblFtrs';    Why = 'grand-parent component, receiver of tblFtrs.State' },
    @{ M = 'F-ANC-CALL'; N = 'tblFtrs';    Q = 'uIfBase.TIfBase.tblFtrs';    Why = 'grand-parent component, receiver of tblFtrs.Post' },
    @{ M = 'F-ANC-WITH'; N = 'tblFtrs';    Q = 'uIfBase.TIfBase.tblFtrs';    Why = 'grand-parent component, a with target' },
    @{ M = 'F-NESTED';   N = 'FOwn';       Q = 'uIfUse.TIfLeaf.FOwn';        Why = 'read from a nested routine' })
  foreach ($c in $cases) {
    $r = ReadsAt $c.M $c.N
    $hit = @($r | Where-Object { $_.kind -eq 'read' -and $_.sq -eq $c.Q -and $_.sk -eq 'field' -and
                                 $_.mode -eq 'read' -and $null -eq $_.acc -and $_.rtq -eq 'uIfUse.TIfLeaf' -and
                                 [int]$_.edges -eq 0 })
    Check ("{0}  bare {1} binds {2} ({3}), mode read, no accessor, no call edge" -f $c.M, $c.N, $c.Q, $c.Why) `
      (($r.Count -eq 1) -and ($hit.Count -eq 1)) (Show $r)
  }

  Write-Host '--- a nearer declaration SHADOWS the field: nothing binds to it'
  $neg = @(
    @{ M = 'F-SHADOW-PARAM'; N = 'FOwn';       F = 'uIfUse.TIfLeaf.FOwn';        Why = 'a parameter' },
    @{ M = 'F-SHADOW-LOCAL'; N = 'FMid';       F = 'uIfBase.TIfMiddle.FMid';     Why = 'a local' },
    @{ M = 'F-NESTED';       N = 'FBaseCount'; F = 'uIfBase.TIfBase.FBaseCount'; Why = 'the OUTER routine''s local' },
    @{ M = 'F-UNRELATED';    N = 'FUnitLevel'; F = 'uIfUse.TIfOther.FUnitLevel'; Why = 'an UNRELATED class''s field (a unit var is meant)' })
  foreach ($c in $neg) {
    $r = ReadsAt $c.M $c.N
    $bad = @($r | Where-Object { $_.sk -eq 'field' })
    Check ("{0}  bare {1} under {2}: not bound to any field (esp. {3})" -f $c.M, $c.N, $c.Why, $c.F) `
      (($r.Count -ge 1) -and ($bad.Count -eq 0)) (Show $r)
  }
  $r = ReadsAt 'F-SHADOW-WITH' 'FOwn'
  Check 'F-SHADOW-WITH  bare FOwn inside with AOther binds the WITH member TIfOther.FOwn, not TIfLeaf.FOwn' `
    ((@($r | Where-Object { $_.sq -eq 'uIfUse.TIfOther.FOwn' }).Count -eq 1) -and
     (@($r | Where-Object { $_.sq -eq 'uIfUse.TIfLeaf.FOwn' }).Count -eq 0)) (Show $r)

  Write-Host '--- controls: spellings that bound before 1.12.0 still bind'
  $r = ReadsAt 'F-SELF' 'FOwn'
  Check 'F-SELF   Self.FOwn binds TIfLeaf.FOwn, mode read' `
    (@($r | Where-Object { $_.kind -eq 'read' -and $_.sq -eq 'uIfUse.TIfLeaf.FOwn' -and $_.mode -eq 'read' }).Count -eq 1) (Show $r)
  $r = ReadsAt 'F-PROP' 'P'
  Check 'F-PROP   bare P binds the PROPERTY TIfLeaf.P with its getter' `
    (@($r | Where-Object { $_.sq -eq 'uIfUse.TIfLeaf.P' -and $_.mode -eq 'read' -and $null -ne $_.acc }).Count -eq 1) (Show $r)
  $r = ReadsAt 'F-WRITE' 'FOwn'
  Check 'F-WRITE  bare FOwn:= N (a write) binds TIfLeaf.FOwn' `
    (@($r | Where-Object { $_.kind -eq 'write' -and $_.sq -eq 'uIfUse.TIfLeaf.FOwn' }).Count -eq 1) (Show $r)

  Write-Host '--- review round 1: the NEAREST member of the name answers, whatever its kind (uIfHide)'
  # TBaseH declares fields FHm, FHc, FHp, FHo; TMidH hides FHm with a METHOD,
  # FHc with a class CONST, FHp with a PROPERTY; TLeafH hides FHo with its OWN
  # field. Before the fix the first two bound TBaseH's field `certain`.
  $r = ReadsAt 'H-METHOD' 'FHm' 'uIfHide'
  Check 'H-METHOD  P:= FHm, a METHOD of TMidH hides TBaseH.FHm: not bound to the field' `
    (($r.Count -ge 1) -and (@($r | Where-Object { $_.sk -eq 'field' }).Count -eq 0)) (Show $r)
  $r = ReadsAt 'H-CONST' 'FHc' 'uIfHide'
  Check 'H-CONST   N:= FHc, a class CONST of TMidH hides TBaseH.FHc: not bound to the field' `
    (($r.Count -ge 1) -and (@($r | Where-Object { $_.sk -eq 'field' }).Count -eq 0)) (Show $r)
  $r = ReadsAt 'H-PROP' 'FHp' 'uIfHide'
  Check 'H-PROP    FHp: the PROPERTY TMidH.FHp hides TBaseH.FHp and binds' `
    ((@($r | Where-Object { $_.sq -eq 'uIfHide.TMidH.FHp' -and $_.mode -eq 'read' }).Count -eq 1) -and
     (@($r | Where-Object { $_.sk -eq 'field' }).Count -eq 0)) (Show $r)
  $r = ReadsAt 'H-OWN' 'FHo' 'uIfHide'
  Check 'H-OWN     FHo: the OWN field TLeafH.FHo hides TBaseH.FHo and binds' `
    (@($r | Where-Object { $_.sq -eq 'uIfHide.TLeafH.FHo' -and $_.mode -eq 'read' }).Count -eq 1) (Show $r)
  $r = ReadsAt 'H-GLOBAL' 'GShadow' 'uIfHide'
  Check 'H-GLOBAL  GShadow: the own FIELD wins over a unit var of the name' `
    (@($r | Where-Object { $_.sq -eq 'uIfHide.TLeafH.GShadow' }).Count -eq 1) (Show $r)
  $r = ReadsAt 'H-INTF' 'FIp' 'uIfHide'
  Check 'H-INTF    FIp: an implemented INTERFACE''s property is not in the class scope: not bound to it' `
    (($r.Count -ge 1) -and (@($r | Where-Object { $_.sq -eq 'uIfHide.IHasFIp.FIp' }).Count -eq 0)) (Show $r)

  Write-Host '--- review round 1: edge shapes bind correctly or decline, never a wrong bind'
  $r = ReadsAt 'H-CLASSVAR' 'FCv' 'uIfHide'
  Check 'H-CLASSVAR  FCv (a class var, kind var): no FIELD bind' `
    (($r.Count -ge 1) -and (@($r | Where-Object { $_.sk -eq 'field' }).Count -eq 0)) (Show $r)
  $r = ReadsAt 'H-AMBIG' 'FAmb' 'uIfHide'
  Check 'H-AMBIG   FAmb beyond an AMBIGUOUS (unresolved) ancestor TAmb: declines, never guesses' `
    (($r.Count -ge 1) -and (@($r | Where-Object { $null -ne $_.sq }).Count -eq 0)) (Show $r)
  foreach ($c in @(@{ M = 'H-NESTED';       N = 'FIn';   Q = 'uIfHide.TOuterN.TInnerN.FIn'; T = 'uIfHide.TOuterN.TInnerN' },
                   @{ M = 'H-RECORD';       N = 'FA';    Q = 'uIfHide.TRecR.FA';            T = 'uIfHide.TRecR' },
                   @{ M = 'H-GENERIC';      N = 'FItem'; Q = 'uIfHide.TBoxG.FItem';         T = 'uIfHide.TBoxG' },
                   @{ M = 'H-GENERIC-DESC'; N = 'FItem'; Q = 'uIfHide.TBoxG.FItem';         T = 'uIfHide.TIntBox' },
                   @{ M = 'H-HELPER';       N = 'FHo';   Q = 'uIfHide.TLeafH.FHo';          T = 'uIfHide.TLeafHHelper' })) {
    $r = ReadsAt $c.M $c.N 'uIfHide'
    Check ("{0}  {1} binds {2} (receiver type {3})" -f $c.M, $c.N, $c.Q, $c.T) `
      (($r.Count -eq 1) -and ($r[0].sq -eq $c.Q) -and ($r[0].mode -eq 'read') -and ($r[0].rtq -eq $c.T)) (Show $r)
  }

  Write-Host '--- the calls-stage log line'
  $ml = @($log.Split("`n") | Where-Object { $_ -match 'calls\s+member-reads: ' })
  Check 'the `member-reads:` counters line is printed' ($ml.Count -ge 1) ''
  Check 'it no longer carries a `field` decline reason (the reason is gone, not zero)' `
    (($ml.Count -ge 1) -and ($ml[0] -notmatch '\bfield \d')) ($ml -join ' | ')
}
finally {
  Pop-Location
}

if ($script:fail) { Write-Host 'FAIL  run_in_class_field_bind'; exit 1 }
Write-Host 'PASS  run_in_class_field_bind'
exit 0