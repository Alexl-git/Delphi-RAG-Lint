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
    check 3  NEG-BARE-SHADOW: a bare GLimit hidden by a local of that name does
             not bind to a unit var

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
  $null = (& $exePath index $scratch --db $db *>&1)

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
  $rows  = @(RefsAt (LineOf 'NEG-BARE-SHADOW') 'GLimit' | Where-Object { $_ })
  $wrong = @($rows | Where-Object { ($null -ne $_.symbol_id) -and ($unitVars -contains [int64]$_.symbol_id) })
  $det   = "refs=" + (($rows | ForEach-Object { "$($_.kind):sid=$($_.symbol_id)" }) -join ',')
  Check 'check 3  NEG-BARE-SHADOW: the ref exists and does not bind through the unit' (($rows.Count -ge 1) -and ($wrong.Count -eq 0)) $det
} finally {
  Pop-Location
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}

if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
