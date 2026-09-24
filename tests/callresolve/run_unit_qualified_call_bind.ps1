<#
  run_unit_qualified_call_bind.ps1 -- a UNIT-QUALIFIED free-routine call binds
  (ENG-16, resolver 1.8.0-alpha).

  THE DEFECT. `Pipes.Commands.DispatchCommand(...)` names a free routine
  through its unit. The receiver `Pipes.Commands` is a UNIT, not a value, so
  receiver typing answers 0, rung 3c (the enum `Unit.value` arm) does not
  apply to a routine, and rung 4 is for BARE calls only -- the call ref kept
  refs.symbol_id NULL and owned no call_edges row, so find-callers,
  assert-with-side-effect, the purity callee walk and the who-calls charts all
  missed it. Measured on ORM3 CLIENT at resolver 1.7.0-alpha: 6 sites -- 5
  `call` refs and 1 parenless `member-access` -- with a unit receiver naming a
  routine of that unit, every one unbound.

  THE FIX: rung 4b in TCallResolver.ResolveOne, the routine twin of rung 3c --
  resolve the receiver text to ONE unit's file, take the routines of that name
  in that file (interface section, or either section when the unit IS the
  calling file), and let the ordinary arity pick decide.

  WHAT THIS GUARD PINS
    check 1  POS-*: six unit-qualified calls each own exactly ONE certain edge
             to the right routine, and refs.symbol_id equals the target
    check 2  POS-OVERLOAD: arity picks the two-argument overload
    check 3  SHADOW-TYPED: a local variable spelled like the unit wins and
             binds to its class's method (receiver typing, unchanged)
    check 4  NEG-*: a missing routine and a local of an UNKNOWN type spelled
             like the unit stay unbound -- the second is the shadowing control
             that a name join would fail

  POSITIVE CONTROL. Check 4's NEG-SHADOW-UNTYPED is what makes check 1 mean
  anything: binding every `<UnitName>.<Routine>` by text turns check 1 green AND
  check 4 red. Every line number is read from the fixture's markers.

  Usage: pwsh -File tests\callresolve\run_unit_qualified_call_bind.ps1 [-Exe <drag-lint.exe>]
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
$scratch = Join-Path C:\TEMP 'draglint_unitqual_bind'
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch
$use = Join-Path $scratch 'uQualUse.pas'
$db  = Join-Path $scratch 'unitqual.sqlite'

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
# Every ref named $Name on line $Line of the use unit that OWNS an edge.
function EdgesAt([int]$Line, [string]$Name) {
  return Sql ("SELECT r.id, r.kind, r.symbol_id, ce.target_symbol_id AS tid, ce.confidence AS conf, " +
              "t.qualified_name AS tq, t.signature AS tsig FROM refs r JOIN files f ON f.id = r.file_id " +
              "JOIN call_edges ce ON ce.ref_id = r.id JOIN symbols t ON t.id = ce.target_symbol_id " +
              "WHERE f.path LIKE '%uQualUse.pas' AND r.start_line = $Line AND r.name_text = '$Name'")
}

Push-Location C:\TEMP
try {
  $null = (& $exePath index $scratch --db $db *>&1)

  # --- check 1: positives ---------------------------------------------------------
  $pos = @(
    @{ M = 'POS-CALL';        N = 'DoIt';   Q = 'Qual.Lib.DoIt' },
    @{ M = 'POS-FUNC';        N = 'Twice';  Q = 'Qual.Lib.Twice' },
    @{ M = 'POS-PARENLESS';   N = 'Ready';  Q = 'Qual.Lib.Ready' },
    @{ M = 'POS-OVERLOAD';    N = 'Over';   Q = 'Qual.Lib.Over' },
    @{ M = 'POS-OWN-UNIT';    N = 'Helper'; Q = 'uQualUse.Helper' },
    @{ M = 'POS-SIMPLE-UNIT'; N = 'DoIt';   Q = 'uQualHelp.DoIt' })
  foreach ($p in $pos) {
    $rows = @(EdgesAt (LineOf $p.M) $p.N | Where-Object { $_ })
    $ok = ($rows.Count -eq 1) -and ($rows[0].tq -eq $p.Q) -and ($rows[0].conf -eq 'certain') -and
          ($rows[0].symbol_id -eq $rows[0].tid)
    $det = if ($rows.Count -eq 1) { "tq=$($rows[0].tq) conf=$($rows[0].conf) kind=$($rows[0].kind) sid=$($rows[0].symbol_id)" } else { "edges=$($rows.Count)" }
    Check ("check 1  {0}: exactly one certain edge to {1}" -f $p.M, $p.Q) $ok $det
  }

  # --- check 2: arity -------------------------------------------------------------
  $ov = @(EdgesAt (LineOf 'POS-OVERLOAD') 'Over' | Where-Object { $_ })
  Check 'check 2  POS-OVERLOAD: arity picks the (A, B) overload' (($ov.Count -eq 1) -and ([string]$ov[0].tsig -match 'A, B')) ("sig=" + $(if ($ov.Count -ge 1) { $ov[0].tsig } else { '' }))

  # --- check 3: a typed local spelled like the unit wins ----------------------------
  $sh = @(EdgesAt (LineOf 'SHADOW-TYPED') 'DoIt' | Where-Object { $_ })
  Check 'check 3  SHADOW-TYPED: the local of type TLocal wins -> TLocal.DoIt' (($sh.Count -eq 1) -and ([string]$sh[0].tq).EndsWith('TLocal.DoIt')) ("tq=" + $(if ($sh.Count -ge 1) { $sh[0].tq } else { '<none>' }))

  # --- check 4: negatives ---------------------------------------------------------
  foreach ($n in @(@{ M = 'NEG-MISSING'; N = 'Missing' }, @{ M = 'NEG-SHADOW-UNTYPED'; N = 'DoIt' })) {
    $rows = @(EdgesAt (LineOf $n.M) $n.N | Where-Object { $_ })
    $sid  = @(Sql ("SELECT r.symbol_id FROM refs r JOIN files f ON f.id = r.file_id WHERE f.path LIKE '%uQualUse.pas' " +
                   "AND r.start_line = $(LineOf $n.M) AND r.name_text = '$($n.N)' AND r.symbol_id IS NOT NULL") | Where-Object { $_ })
    Check ("check 4  {0}: no edge and no refs.symbol_id" -f $n.M) (($rows.Count -eq 0) -and ($sid.Count -eq 0)) "edges=$($rows.Count) bound=$($sid.Count)"
  }
} finally {
  Pop-Location
}

if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
