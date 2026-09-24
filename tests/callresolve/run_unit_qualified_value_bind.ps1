<#
  run_unit_qualified_value_bind.ps1 -- a UNIT-QUALIFIED var / const binds
  refs.symbol_id (D22, resolver 1.9.0-alpha).

  THE DEFECT. `uStyles.SkipRefresh := True` names a unit-level VARIABLE through
  its unit. The extractor emits a `member-access` ref (receiver `uStyles`) for
  both the read and the write shape -- never a `write` ref -- so the site reaches
  TCallResolver.ResolveOne. The receiver is a UNIT, so receiver typing answers 0;
  rung 3c binds `Unit.value` only for ENUM values and rung 4b (ENG-16) only for
  ROUTINES, and the ref kept refs.symbol_id NULL. Measured on ORM3 CLIENT at
  resolver 1.8.0-alpha: 4 sites, all writes (uStyles.SkipRefresh,
  uAutoTest.AutoTest_ExtraScenarios, uPLANLIST.PlanEditFormHook x2).

  THE FIX: rung 3d in ResolveOne, the value twin of rung 4b -- for a
  member-access ref whose receiver did not type, resolve the receiver to ONE
  unit's file that nothing nearer shadows, take the unit-level var / const
  declarations of that name in that file (interface section, or either section
  when the unit IS the referencing file), and bind ValueOnly when exactly one
  survives.

  WHAT THIS GUARD PINS
    check 1  MARK-*: a var read, a const read, a var write and a single-segment
             unit write each bind refs.symbol_id to the unit's declaration and
             own NO call_edges row (a value is not a call target)
    check 2  NEG-VALUE-*: a local spelled like the unit -- typed, of an unknown
             type, or a with target that cannot be typed -- is what the compiler
             reads; the ref must not bind to either unit's GLimit
    check 3  POS-BARE-UNIT / NEG-BARE-SHADOW: a bare WRITE of GSole (one used
             unit declares it) binds to the unit var, and the same write hidden
             by a local binds to the local instead (a D13 control kept here)
    check 5  READ vs WRITE (ruling R15): each MARK-* site owns one
             member_accesses row with the right mode (the const: read), and
             `find-callers --resolved` reports MARK-WRITE / MARK-SIMPLE-UNIT as
             `write`, MARK-READ / MARK-CONST as `read`
    check 4  THE CALLS LOG counts what it claims to (ruling R13). Rung 3d's
             bindings are ValueOnly writes like rung 3c's enum values, and the
             store used to count EVERY ValueOnly write as an enum "qualified
             bound (Shape B)" -- so a unit var inflated the enum count and the
             enum reconciliation printed a false WARNING. Pinned: the enum line
             reports 0 qualified (this fixture has no enum), its reconciliation
             line is NOT the WARNING form, and a separate `unit-values:` line
             reports the MARK-* count with resolver and store agreeing.

  POSITIVE CONTROL. Check 2 is what makes check 1 mean anything: binding every
  `<UnitName>.<Value>` by text turns check 1 green AND check 2 red, because
  uQualHelp declares a GLimit for the shadowed sites to be (wrongly) bound to.
  Each negative first asserts its ref EXISTS, so an extractor change that stops
  emitting it cannot pass the check vacuously. Every line number is read from
  the fixture's markers.

  Usage: pwsh -File tests\callresolve\run_unit_qualified_value_bind.ps1 [-Exe <drag-lint.exe>]
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
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\unitqual')).Path
$scratch = Join-Path C:\TEMP "draglint_unitqual_value_$PID"
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
$use = Join-Path $scratch 'uQualUse.pas'
$db  = Join-Path $scratch 'unitqual.sqlite'

# `sql --json` rows are POSITIONAL arrays: map each onto the column names.
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
function LineOf([string]$Marker) {
  $m = @(Select-String -LiteralPath $use -SimpleMatch -Pattern "// $Marker")
  if ($m.Count -ne 1) { throw "marker '$Marker' found $($m.Count) times in the fixture" }
  return [int]$m[0].LineNumber
}
function SymbolId([string]$QName) {
  $rows = @(Sql "SELECT id FROM symbols WHERE qualified_name = '$QName'" | Where-Object { $_ })
  if ($rows.Count -ne 1) { throw "expected ONE symbol '$QName', found $($rows.Count)" }
  return [int64]$rows[0].id
}
# Every ref named $Name on line $Line of the use unit, with its edge count.
function RefsAt([int]$Line, [string]$Name) {
  return Sql ("SELECT r.id, r.kind, r.symbol_id, " +
              "(SELECT COUNT(*) FROM call_edges ce WHERE ce.ref_id = r.id) AS edges " +
              "FROM refs r JOIN files f ON f.id = r.file_id " +
              "WHERE f.path LIKE '%uQualUse.pas' AND r.start_line = $Line AND r.name_text = '$Name'")
}

Push-Location C:\TEMP
try {
  Copy-Item (Join-Path $fixDir '*.pas') $scratch
  $idxOut = ((& $exePath index $scratch --db $db *>&1) | ForEach-Object { "$_" }) -join "`n"

  $libLimit  = SymbolId 'Qual.Lib.GLimit'
  $libMax    = SymbolId 'Qual.Lib.CMax'
  $helpLimit = SymbolId 'uQualHelp.GLimit'
  $unitVars  = @($libLimit, $helpLimit)

  # --- check 1: positives ---------------------------------------------------------
  $pos = @(
    @{ M = 'MARK-READ';        N = 'GLimit'; Id = $libLimit;  Q = 'Qual.Lib.GLimit'  },
    @{ M = 'MARK-CONST';       N = 'CMax';   Id = $libMax;    Q = 'Qual.Lib.CMax'    },
    @{ M = 'MARK-WRITE';       N = 'GLimit'; Id = $libLimit;  Q = 'Qual.Lib.GLimit'  },
    @{ M = 'MARK-SIMPLE-UNIT'; N = 'GLimit'; Id = $helpLimit; Q = 'uQualHelp.GLimit' })
  foreach ($p in $pos) {
    $rows = @(RefsAt (LineOf $p.M) $p.N | Where-Object { $_ })
    $ma   = @($rows | Where-Object { $_.kind -eq 'member-access' })
    $ok   = ($ma.Count -eq 1) -and ([int64]$ma[0].symbol_id -eq $p.Id) -and ([int]$ma[0].edges -eq 0)
    $det  = "refs=" + (($rows | ForEach-Object { "$($_.kind):sid=$($_.symbol_id):edges=$($_.edges)" }) -join ',')
    Check ("check 1  {0}: the member-access binds to {1} (id {2}), no call edge" -f $p.M, $p.Q, $p.Id) $ok $det
  }

  # --- check 2: a local spelled like the unit is what the compiler reads ------------
  foreach ($m in @('NEG-VALUE-TYPED', 'NEG-VALUE-UNTYPED', 'NEG-VALUE-WITH')) {
    $rows  = @(RefsAt (LineOf $m) 'GLimit' | Where-Object { $_ })
    $wrong = @($rows | Where-Object { ($null -ne $_.symbol_id) -and ($unitVars -contains [int64]$_.symbol_id) })
    $det   = "refs=" + (($rows | ForEach-Object { "$($_.kind):sid=$($_.symbol_id)" }) -join ',')
    Check ("check 2  {0}: the ref exists and binds to no unit-level GLimit" -f $m) (($rows.Count -ge 1) -and ($wrong.Count -eq 0)) $det
  }

  # --- check 3: a bare name shadowed by a local ------------------------------------
  # GSole is declared by ONE used unit, so the unshadowed bare write binds to it
  # (POS-BARE-UNIT, the reachability control). Only then can the shadowed write
  # fail for the stated reason -- binding to the unit var instead of the local.
  # (Bare WRITES, not reads: no pass binds a bare read to a unit var, so a read
  # here could not fail at all -- the defect of the check this replaces.)
  $sole     = SymbolId 'Qual.Lib.GSole'
  $soleLoc  = SymbolId 'uQualUse.DriverValuesBareShadow.GSole'
  $rows     = @(RefsAt (LineOf 'POS-BARE-UNIT') 'GSole' | Where-Object { $_ -and $_.kind -eq 'write' })
  Check 'check 3  POS-BARE-UNIT: the unshadowed bare write binds to Qual.Lib.GSole (reachability control)' (($rows.Count -eq 1) -and ([int64]$rows[0].symbol_id -eq $sole)) ("refs=" + (($rows | ForEach-Object { "$($_.kind):sid=$($_.symbol_id)" }) -join ','))
  $rows     = @(RefsAt (LineOf 'NEG-BARE-SHADOW') 'GSole' | Where-Object { $_ -and $_.kind -eq 'write' })
  Check 'check 3  NEG-BARE-SHADOW: the shadowed bare write binds to the LOCAL, not Qual.Lib.GSole' (($rows.Count -eq 1) -and ([int64]$rows[0].symbol_id -eq $soleLoc)) ("refs=" + (($rows | ForEach-Object { "$($_.kind):sid=$($_.symbol_id)" }) -join ',') + " local=$soleLoc unit=$sole")

  # --- check 4: the calls log (R13) --------------------------------------------------
  # -1, never 0, when a label is absent: a renamed counter must redden, not pass.
  function LogNum([string]$Text, [string]$Pattern) { if ($Text -match $Pattern) { return [int]$Matches[1] }; return -1 }
  $logLines = @($idxOut -split "`n")
  $enumLine = (@($logLines | Where-Object { $_ -match 'enum-values:' -and $_ -match 'bare read' }) -join ' | ')
  $enumRec  = @($logLines | Where-Object { $_ -match 'enum-values:' -and ($_ -match 'total bound' -or $_ -match 'WARNING') })
  $uvLines  = @($logLines | Where-Object { $_ -match 'unit-values:' })
  $expUnit  = $pos.Count
  $gotQual  = LogNum $enumLine '(\d+) qualified bound'
  Check 'check 4  enum-values: 0 qualified bound (Shape B) -- a unit var is not an enum value' ($gotQual -eq 0) "qualified=$gotQual line=$enumLine"
  Check 'check 4  the enum reconciliation line is present and is NOT the WARNING form' (($enumRec.Count -eq 1) -and (($enumRec -join ' ') -notmatch 'WARNING')) ($enumRec -join ' | ')
  $uvText   = ($uvLines -join ' ')
  $gotUnit  = LogNum $uvText '(\d+) unit-qualified var/const ref\(s\) bound'
  Check ("check 4  unit-values: {0} unit-qualified var/const ref(s) bound, resolver and store agree" -f $expUnit) `
        (($uvLines.Count -eq 1) -and ($gotUnit -eq $expUnit) -and ($uvText -match 'resolver and store agree') -and ($uvText -notmatch 'WARNING')) "got=$gotUnit line=$uvText"
  Check 'check 4  no "resolver counted ... but the store wrote" WARNING anywhere in the calls log' `
        (@($logLines | Where-Object { $_ -match 'resolver counted .* but the store wrote' }).Count -eq 0) ''

  # --- check 5: READ vs WRITE (ruling R15) -------------------------------------------
  # A unit-qualified value is bound the way a dotted field/property is: refs.symbol_id
  # AND a member_accesses row carrying the mode, so `find-callers --resolved` says
  # `write` for `Qual.Lib.GLimit:= 1` instead of calling it a read. A const can only
  # be read. `find-callers --json` is a bare ARRAY of rows keyed by `line` and `mode`.
  $modes = @(
    @{ M = 'MARK-READ';        Id = $libLimit;  Mode = 'read'  },
    @{ M = 'MARK-CONST';       Id = $libMax;    Mode = 'read'  },
    @{ M = 'MARK-WRITE';       Id = $libLimit;  Mode = 'write' },
    @{ M = 'MARK-SIMPLE-UNIT'; Id = $helpLimit; Mode = 'write' })
  foreach ($x in $modes) {
    $ln = LineOf $x.M
    $ma = @(Sql ("SELECT ma.mode, ma.member_symbol_id AS mid, ma.accessor_symbol_id AS aid FROM member_accesses ma " +
                 "JOIN refs r ON r.id = ma.ref_id JOIN files f ON f.id = r.file_id " +
                 "WHERE f.path LIKE '%uQualUse.pas' AND r.start_line = $ln") | Where-Object { $_ })
    Check ("check 5  {0}: one member_accesses row, member = id {1}, mode {2}, no accessor" -f $x.M, $x.Id, $x.Mode) `
          (($ma.Count -eq 1) -and ([int64]$ma[0].mid -eq $x.Id) -and ($ma[0].mode -eq $x.Mode) -and ($null -eq $ma[0].aid)) `
          ("rows=" + (($ma | ForEach-Object { "mid=$($_.mid):mode=$($_.mode):aid=$($_.aid)" }) -join ','))
  }
  foreach ($nm in @('GLimit', 'CMax')) {
    $raw = (& $exePath query find-callers --name $nm --resolved --json --db $db 2>$null) -join "`n"
    Write-Host "   raw find-callers --name $nm --resolved --json: $(($raw -replace '\s+', ' '))"
    $fc  = @()
    try { $fc = @($raw | ConvertFrom-Json) } catch { $fc = @() }
    foreach ($x in @($modes | Where-Object { ($_.M -eq 'MARK-CONST') -eq ($nm -eq 'CMax') })) {
      $ln  = LineOf $x.M
      $hit = @($fc | Where-Object { [int]$_.line -eq $ln })
      Check ("check 5  find-callers {0}: {1} (line {2}) is ONE row with mode {3}" -f $nm, $x.M, $ln, $x.Mode) `
            (($hit.Count -eq 1) -and ($hit[0].mode -eq $x.Mode)) ("rows=" + (($hit | ForEach-Object { "mode=$($_.mode)" }) -join ','))
    }
  }
} finally {
  Pop-Location
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}

if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
