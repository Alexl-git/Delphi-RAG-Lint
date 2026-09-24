<#
  run_with_scope_bind.ps1 -- `with` scope in the resolver (resolver 1.8.0-alpha,
  defects D14 and D16a).

  THE DEFECT (D14). Inside `with A, B do`, Delphi binds a bare name to a member of
  B's type first, then of A's, and only then to the ordinary scope (locals, the
  class, the unit). The resolver had no `with` scope at all: measured on ORM3
  CLIENT, 0 of 283 member accesses inside with bodies were bound (21.7% outside),
  and a bare call inside a with body bound to a same-named method of the
  ENCLOSING class -- the declaration the compiler does NOT pick. The enum-value
  binder had the same blind spot (risk R7): a bare read that names a with-target
  member was bound to an enum value of that name.

  THE RULE THIS PINS. A with target whose type is known and whose surface is
  complete is consulted first; a member it declares WINS (call edge, member
  access or refs.symbol_id on the member). A target whose type cannot be
  resolved, or whose ancestry leaves the index, may declare the name -- so the
  ref binds to NOTHING rather than to a guess. The one documented exception is
  an enum value read under an undecidable target: it keeps its pre-1.8 binding,
  and enum-read-inside-with is the reporter for that residual.

  Self.X (controller addition, 2026-09-23). An explicit `Self.X` read names the
  class member exactly as `Obj.X` does -- property OR field -- and a local of the
  same name cannot be what it names, so it never declines for one (SELF-*).

  D16a. A bare PROPERTY read inside its own class (`N := TotalP`) binds to the
  property (member access, mode read, getter edge). A bare FIELD read in its own
  class is deliberately left unbound (the population is every field read in the
  corpus; binding it is a separate decision) -- pinned by OWN-FIELD.

  POSITIVE CONTROLS: CTRL-OUTSIDE and CTRL-ENUM are the same names outside any
  with and keep their ordinary binding. A resolver that simply refused to bind
  anything near a with would turn the W-* negatives green and these red.

  Every line number is READ FROM THE FIXTURE'S markers. `sql --json` rows are
  POSITIONAL arrays; Sql() maps them onto the column names.

  Usage: pwsh -File tests\callresolve\run_with_scope_bind.ps1 [-Exe <drag-lint.exe>]
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
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\withscope')).Path
# A fresh directory per run, not a delete: a previous run's index must never
# answer this one.
$scratch = Join-Path (Join-Path C:\TEMP 'draglint_with_scope_bind') ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch
$use = Join-Path $scratch 'uWsUse.pas'
$db  = Join-Path $scratch 'withscope.sqlite'

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
  $m = @(Select-String -LiteralPath $use -Pattern ("// " + [regex]::Escape($Marker) + "\s*$"))
  if ($m.Count -ne 1) { throw "marker '$Marker' found $($m.Count) times in the fixture" }
  return [int]$m[0].LineNumber
}
# Every ref named $Name on the marker's line: its own binding, its call edge and
# its member access, each with the qualified name it points at.
function RefsAt([string]$Marker, [string]$Name) {
  $line = LineOf $Marker
  return Sql ("SELECT r.id, r.kind, s.qualified_name AS sq, s.kind AS sk, " +
              "t.qualified_name AS tq, ce.confidence AS conf, rt.qualified_name AS rtq, " +
              "ma.mode AS mode, acc.qualified_name AS aq " +
              "FROM refs r JOIN files f ON f.id = r.file_id " +
              "LEFT JOIN symbols s ON s.id = r.symbol_id " +
              "LEFT JOIN call_edges ce ON ce.ref_id = r.id LEFT JOIN symbols t ON t.id = ce.target_symbol_id " +
              "LEFT JOIN symbols rt ON rt.id = ce.receiver_type_symbol_id " +
              "LEFT JOIN member_accesses ma ON ma.ref_id = r.id LEFT JOIN symbols acc ON acc.id = ma.accessor_symbol_id " +
              "WHERE f.path LIKE '%uWsUse.pas' AND r.start_line = $line AND r.name_text = '$Name'")
}
function Edges($rows) { return ,@($rows | Where-Object { $null -ne $_.tq }) }
function Bound($rows) { return ,@($rows | Where-Object { ($null -ne $_.tq) -or ($null -ne $_.sq) }) }
function Show($rows) { return (@($rows | ForEach-Object { "$($_.kind):sid=$($_.sq)/edge=$($_.tq)/$($_.conf)/rt=$($_.rtq)/ma=$($_.mode)" }) -join '; ') }

Push-Location C:\TEMP
try {
  $log = (& $exePath index $scratch --db $db *>&1) -join "`n"

  Write-Host '--- controls: the same names OUTSIDE any with keep their ordinary binding'
  $r = RefsAt 'CTRL-OUTSIDE' 'Execute'
  Check 'CTRL-OUTSIDE  bare Execute outside a with binds TWsHost.Execute' `
    (@(Edges $r | Where-Object { $_.tq -eq 'uWsUse.TWsHost.Execute' }).Count -eq 1) (Show $r)
  $r = RefsAt 'CTRL-ENUM' 'Kind'
  Check 'CTRL-ENUM     bare Kind outside a with binds the enum value TWsMode.Kind' `
    (@($r | Where-Object { $_.sk -eq 'enum_value' -and $_.sq -like '*TWsMode.Kind' }).Count -eq 1) (Show $r)

  Write-Host '--- D14: a with member WINS over the ordinary scope'
  $cases = @(
    @{ M = 'W-CALL-OBJ';       N = 'Execute'; Q = 'uWsLib.TWsObj.Execute';   R = 'uWsLib.TWsObj' },
    @{ M = 'W-CALL-REC';       N = 'Reset';   Q = 'uWsLib.TWsRec.Reset';     R = 'uWsLib.TWsRec' },
    @{ M = 'W-NESTED';         N = 'Execute'; Q = 'uWsLib.TWsOther.Execute'; R = 'uWsLib.TWsOther' },
    @{ M = 'W-CREATE';         N = 'Execute'; Q = 'uWsLib.TWsObj.Execute';   R = 'uWsLib.TWsObj' },
    @{ M = 'W-INCOMPLETE-OWN'; N = 'Own';     Q = 'uWsLib.TWsDerived.Own';   R = 'uWsLib.TWsDerived' })
  foreach ($c in $cases) {
    $r = RefsAt $c.M $c.N
    $e = Edges $r
    $ok = ($e.Count -eq 1) -and ($e[0].tq -eq $c.Q) -and ($e[0].conf -eq 'certain') -and ($e[0].rtq -eq $c.R)
    Check ("{0}  bare {1} binds the with member {2} (receiver type {3})" -f $c.M, $c.N, $c.Q, $c.R) $ok (Show $r)
  }
  $r = RefsAt 'W-RCV' 'Ping'
  Check 'W-RCV  Inner.Ping: the receiver Inner is typed THROUGH the with target' `
    (@(Edges $r | Where-Object { $_.tq -eq 'uWsLib.TWsInner.Ping' }).Count -eq 1) (Show $r)
  $r = RefsAt 'W-PARENLESS' 'Total'
  Check 'W-PARENLESS  N := Total inside with ARec is a parenless call to TWsRec.Total' `
    (@(Edges $r | Where-Object { $_.tq -eq 'uWsLib.TWsRec.Total' -and $_.conf -eq 'certain' }).Count -eq 1) (Show $r)
  $r = RefsAt 'W-READ-FIELD' 'Count'
  Check 'W-READ-FIELD  N := Count inside with ARec binds the FIELD TWsRec.Count, mode read' `
    (@($r | Where-Object { $_.sq -eq 'uWsLib.TWsRec.Count' -and $_.mode -eq 'read' }).Count -eq 1) (Show $r)
  $r = RefsAt 'W-PROP' 'Size'
  Check 'W-PROP  N := Size inside with AObj binds the PROPERTY TWsObj.Size, its getter recorded' `
    (@($r | Where-Object { $_.sq -eq 'uWsLib.TWsObj.Size' -and $_.mode -eq 'read' -and $_.aq -eq 'uWsLib.TWsObj.GetSize' }).Count -eq 1) (Show $r)

  Write-Host '--- ordering: innermost target, LAST-listed entity first'
  $r = RefsAt 'W-ORDER' 'Count'
  Check 'W-ORDER   with AObj, ARec: Count is ARec''s field, not AObj''s function' `
    ((@($r | Where-Object { $_.sq -eq 'uWsLib.TWsRec.Count' }).Count -eq 1) -and ((Edges $r).Count -eq 0)) (Show $r)
  $r = RefsAt 'W-ORDER2' 'Count'
  Check 'W-ORDER2  with ARec, AObj: Count is AObj''s function (a parenless call)' `
    (@(Edges $r | Where-Object { $_.tq -eq 'uWsLib.TWsObj.Count' }).Count -eq 1) (Show $r)

  Write-Host '--- R7 closed: an enum-value read shadowed by a with member binds the MEMBER'
  $r = RefsAt 'W-ENUM' 'Kind'
  Check 'W-ENUM  M := Kind inside with ARec binds TWsRec.Kind, NOT the enum value TWsMode.Kind' `
    ((@($r | Where-Object { $_.sq -eq 'uWsLib.TWsRec.Kind' }).Count -eq 1) -and
     (@($r | Where-Object { $_.sk -eq 'enum_value' }).Count -eq 0)) (Show $r)
  $r = RefsAt 'W-ENUM-UNDECIDED' 'wmBeta'
  Check 'W-ENUM-UNDECIDED  under an unresolvable target the enum value keeps its binding (documented residual)' `
    (@($r | Where-Object { $_.sk -eq 'enum_value' }).Count -eq 1) (Show $r)

  Write-Host '--- undecidable targets bind NOTHING'
  foreach ($c in @(@{ M = 'W-UNKNOWN'; N = 'Execute' }, @{ M = 'W-INCOMPLETE'; N = 'Execute' }, @{ M = 'W-FREE'; N = 'Free' })) {
    $r = RefsAt $c.M $c.N
    Check ("{0}  bare {1} stays unbound (no edge, no symbol_id)" -f $c.M, $c.N) `
      (($r.Count -ge 1) -and ((Bound $r).Count -eq 0)) (Show $r)
  }

  Write-Host '--- D16a: a bare property read inside its own class'
  $r = RefsAt 'OWN-PROP' 'TotalP'
  Check 'OWN-PROP  N := TotalP binds TWsHost.TotalP, mode read, getter GetTotalP with a call edge' `
    (@($r | Where-Object { $_.sq -eq 'uWsUse.TWsHost.TotalP' -and $_.mode -eq 'read' -and
                          $_.aq -eq 'uWsUse.TWsHost.GetTotalP' -and $_.tq -eq 'uWsUse.TWsHost.GetTotalP' }).Count -eq 1) (Show $r)
  $r = RefsAt 'OWN-FIELD' 'FCountH'
  Check 'OWN-FIELD  a bare own-class FIELD read stays unbound (by design)' `
    (($r.Count -ge 1) -and (@($r | Where-Object { $_.kind -eq 'read' -and $null -ne $_.sq }).Count -eq 0)) (Show $r)
  $r = RefsAt 'OWN-SHADOW' 'TotalP'
  Check 'OWN-SHADOW  a local named TotalP shadows the property: unbound' `
    (($r.Count -ge 1) -and (@($r | Where-Object { $_.kind -eq 'read' -and $null -ne $_.sq }).Count -eq 0)) (Show $r)

  Write-Host '--- Self.X: the explicit qualifier names the class member, property OR field'
  foreach ($c in @(@{ M = 'SELF-FIELD';       N = 'FCountH'; Q = 'uWsUse.TWsHost.FCountH' },
                   @{ M = 'SELF-FIELD-LOCAL'; N = 'FCountH'; Q = 'uWsUse.TWsHost.FCountH' },
                   @{ M = 'SELF-PROP';        N = 'TotalP';  Q = 'uWsUse.TWsHost.TotalP' })) {
    $r = RefsAt $c.M $c.N
    Check ("{0}  Self.{1} binds {2}, mode read (a same-named LOCAL cannot be what Self.X names)" -f $c.M, $c.N, $c.Q) `
      (@($r | Where-Object { $_.kind -eq 'read' -and $_.sq -eq $c.Q -and $_.mode -eq 'read' }).Count -eq 1) (Show $r)
  }

  Write-Host '--- the calls-stage log lines'
  Check 'the `with-scope:` counters line is printed' ($log -match 'calls\s+with-scope: ') ''
  Check 'the `member-reads:` counters line is printed' ($log -match 'calls\s+member-reads: ') ''
}
finally {
  Pop-Location
}

if ($script:fail) { Write-Host 'FAIL  run_with_scope_bind'; exit 1 }
Write-Host 'PASS  run_with_scope_bind'
exit 0
