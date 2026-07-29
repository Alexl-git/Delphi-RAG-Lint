<#
  run_proptree_ancestor_climb.ps1 -- the QUERY-TIME ancestor-climb fallback in
  DRagLint.Convert.PropTree.ClassChain (design doc
  2026-07-29-proptree-ancestor-scope-design.md section 3.1, criteria 6-7).

  WHAT THIS COVERS THAT NOTHING ELSE DOES

  run_proptree_scope_rule.ps1 proves the shared scope rule itself
  (PickAncestorCandidateByScope), and run_proptree_ancestry_bridge.ps1 proves an
  unresolved edge is bridged at all -- but BOTH resolve the broken edge on the
  class the query was rooted at, i.e. SINGLE-HOP. A single-hop fixture cannot
  distinguish "resolved in the inheriting class's unit" from "resolved in the
  ROOT class's unit", because those are the same unit. That is exactly why the
  root-scope defect (PropTree.pas passing the ROOT's FileId at every hop, against
  ResolveTypeNameToClass's documented AScopeFileId contract) survived unnoticed.

  Design criterion 7: "THE fallback SHALL use the FileId of the class doing the
  inheriting, not the FileId of the root class the query started from."

  CASE A/B -- MULTI-UNIT, decisive for criterion 7 AND criterion 5.

    Zed.Root9.pas   TRoot9  = class(TMid9)     -- namespace prefix 'Zed'
                    TRootF9 = class(TMidF9)    -- namespace prefix 'Zed'
                    (deliberately NO uses clause)
    Vcl.Mid9.pas    TMid9   = class(TAmb9)     -- globally UNIQUE name, so the
                                                  TRoot9 -> TMid9 edge RESOLVES
                                                  at index time and the climb
                                                  genuinely reaches a second hop
                                                  in a DIFFERENT unit.
                                                  (deliberately NO uses clause)
    FMX.Mid9.pas    TMidF9  = class(TAmb9)     -- the mirror. Also no uses.
    Vcl.Cand9.pas   TAmb9   [property Marker: TMarkVcl9]
    FMX.Cand9.pas   TAmb9   [property Marker: TMarkFmx9]  <- same simple name,
                                                  so 'TAmb9' is AMBIGUOUS and
                                                  ResolveAncestry declines
                                                  (ancestor_kind='?'), the same
                                                  shape as the measured
                                                  real-library root cause.

    The root unit's prefix is 'Zed', which matches NEITHER candidate. So:
      * resolve 'TAmb9' in the ROOT's scope (the defect)   -> rule 3 finds no
        prefix match, the rule correctly DECLINES, the climb stops, and 'Marker'
        is ABSENT from both trees;
      * resolve it in the INHERITING class's scope (correct) -> Vcl.Mid9's 'Vcl'
        prefix picks Vcl.Cand9 and FMX.Mid9's 'FMX' prefix picks FMX.Cand9, so
        'Marker' is present and DIFFERENTLY TYPED in each direction.
    A wrong pick is therefore detectable (shows up as the other framework's enum),
    a decline is detectable (Marker absent), and passing for the wrong reason --
    one blanket scope that happens to suit both -- is impossible, because the two
    roots live in the SAME unit yet must reach OPPOSITE frameworks.

  CASE C -- CYCLE GUARD, made independently RED-able. A LINEAR cycle is not
  enough: the depth cap alone bounds it, and leaf-name dedup in CollectProps /
  CollectFields hides the repeated chain, so deleting the visited set changes no
  output at all. This case therefore uses a BRANCHING cycle --
  'TCycHub = class(TCycAliasL, TCycAliasR)' where BOTH aliases lead back to
  TCycHub. With the visited-class-id set each class is climbed at most once and
  the query is instant. WITHOUT it, every climb of the hub bridges both names
  again, so the recursion branches two ways per level and the depth cap bounds
  it at 2^64 -- it never returns. The assertion is a hard wall-clock bound on a
  fixture that is exponential without the guard, which is exactly the "a
  malformed or self-referential index must not spin" property the guard exists
  for. (A two-entry heritage whose second entry is a class is not something the
  Delphi compiler would accept. That is the point: the guard's job is to survive
  a MALFORMED index, and type_ancestors records a row per heritage token
  regardless of what the compiler would say.)

  CASE D -- DEPTH CAP, independently RED-able. A straight, ACYCLIC alias chain
  longer than CMaxBridgedChainDepth (64). The visited set can never fire here --
  every class in the chain is distinct -- so only the depth cap can stop the
  climb. A marker declared comfortably INSIDE the cap must be reachable; one
  declared BEYOND it must not be. Both directions are pinned, so removing the
  cap turns the second check red and shrinking it turns the first red.

  CASE E -- CRITERION 5 WHEN THE NAME HAS A SINGLE CANDIDATE: the gap the shared
  scope rule cannot close. ResolveTypeNameToClass -> PickCandidate
  short-circuits on a lone candidate ('if Length(Types) = 1 then Exit(Types[0])'),
  so PickAncestorCandidateByScope -- and with it rule 3 -- is never consulted.
  A Vcl-scoped class whose ancestor name is a type ALIAS to the ONE class of
  that name, and that class lives in an FMX unit, would therefore be bridged
  with NO scope check whatsoever and spliced straight into the class chain. The
  climb's own CrossesNamespace guard is what refuses it. Neither
  run_proptree_scope_rule.ps1 nor run_proptree_ancestry_bridge.ps1 can reach
  this: every ambiguous name in those fixtures has TWO candidates and so takes
  the scope-rule path instead.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-proptree-ancestor-climb"
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
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $work | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Ascii (Join-Path $work 'Vcl.Cand9.pas') @'
unit Vcl.Cand9;

interface

type
  TMarkVcl9 = (mv9None, mv9Full);

  // One of the two same-named candidates for the ambiguous ancestor 'TAmb9'.
  // Marker is typed DIFFERENTLY from the FMX twin so a wrong pick is visible.
  TAmb9 = class(TPersistent)
  private
    FMarker: TMarkVcl9;
  published
    property Marker: TMarkVcl9 read FMarker write FMarker;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'FMX.Cand9.pas') @'
unit FMX.Cand9;

interface

type
  TMarkFmx9 = (mf9None, mf9Full);

  // The mirror candidate. Same simple name 'TAmb9' as Vcl.Cand9's, which is
  // what makes the ancestor name globally AMBIGUOUS.
  TAmb9 = class(TPersistent)
  private
    FMarker: TMarkFmx9;
  published
    property Marker: TMarkFmx9 read FMarker write FMarker;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.Mid9.pas') @'
unit Vcl.Mid9;

interface

// Deliberately NO uses clause, so neither same-unit (rule 1) nor uses-based
// (rule 2) scoping can decide 'TAmb9' -- only this unit's 'Vcl' namespace
// prefix (rule 3) can. TMid9's own name is globally unique, so the
// TRoot9 -> TMid9 edge RESOLVES at index time; the break is one hop ABOVE the
// queried root, in THIS unit.

type
  TMid9 = class(TAmb9)
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'FMX.Mid9.pas') @'
unit FMX.Mid9;

interface

// The mirror of Vcl.Mid9 -- also no uses clause; only the 'FMX' prefix can
// decide. Criterion 5's "nor the reverse".

type
  TMidF9 = class(TAmb9)
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Zed.Root9.pas') @'
unit Zed.Root9;

interface

// The queried roots. This unit's namespace prefix is 'Zed', which matches
// NEITHER candidate unit for 'TAmb9' -- so if the climb resolved the broken
// edge in the ROOT's scope, rule 3 would find no prefix match, decline, and
// 'Marker' would be absent from BOTH trees below. Both roots live in THIS one
// unit yet must reach OPPOSITE frameworks, which no single blanket scope can
// achieve. Deliberately NO uses clause.

type
  TRoot9 = class(TMid9)
  end;

  TRootF9 = class(TMidF9)
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Cyc9.pas') @'
unit Cyc9;

interface

// BRANCHING CYCLE -- deliberately malformed, see the header. Both heritage
// entries of TCycHub are aliases that lead back to TCycHub, so each climb of
// the hub can bridge TWO names that each return to it. With the
// visited-class-id set every class is climbed at most once and this is
// instant; without it the recursion branches two ways per level and the depth
// cap bounds it at 2^64, i.e. it never returns.

type
  TCycAliasL = TCycLeft;
  TCycAliasR = TCycRight;
  TCycBack   = TCycHub;

  TCycHub = class(TCycAliasL, TCycAliasR)
  private
    FSelfMark: Integer;
  published
    property SelfMark: Integer read FSelfMark write FSelfMark;
  end;

  TCycLeft = class(TCycBack)
  end;

  TCycRight = class(TCycBack)
  end;

implementation

end.
'@

# --- CASE D fixture: a straight ACYCLIC alias chain LONGER than the depth cap. -----
#     Every hop is a distinct class reached through a type alias, so every edge is
#     unresolved and must be bridged; the visited set can never fire. TDeep9_000 is
#     the queried root and each TDeep9_NNN inherits TDeep9_(NNN+1) via an alias.
#     MarkNear is declared at hop 40 (inside the 64 cap) and MarkFar at hop 80
#     (beyond it).
$deepNear = 40
$deepFar  = 80
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('unit Deep9;')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('interface')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('type')
[void]$sb.AppendLine('  TMarkNear9 = (mn9None, mn9Full);')
[void]$sb.AppendLine('  TMarkFar9  = (mf9None, mf9Full);')
[void]$sb.AppendLine('')
for ($i = 0; $i -le $deepFar; $i++) {
  [void]$sb.AppendLine(('  TDeepAlias9_{0:000} = TDeep9_{0:000};' -f $i))
}
[void]$sb.AppendLine('')
for ($i = 0; $i -lt $deepFar; $i++) {
  [void]$sb.AppendLine(('  TDeep9_{0:000} = class(TDeepAlias9_{1:000})' -f $i, ($i + 1)))
  if ($i -eq $deepNear) {
    [void]$sb.AppendLine('  private')
    [void]$sb.AppendLine('    FMarkNear: TMarkNear9;')
    [void]$sb.AppendLine('  published')
    [void]$sb.AppendLine('    property MarkNear: TMarkNear9 read FMarkNear write FMarkNear;')
  }
  [void]$sb.AppendLine('  end;')
}
[void]$sb.AppendLine(('  TDeep9_{0:000} = class(TPersistent)' -f $deepFar))
[void]$sb.AppendLine('  private')
[void]$sb.AppendLine('    FMarkFar: TMarkFar9;')
[void]$sb.AppendLine('  published')
[void]$sb.AppendLine('    property MarkFar: TMarkFar9 read FMarkFar write FMarkFar;')
[void]$sb.AppendLine('  end;')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('implementation')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('end.')
Write-Ascii (Join-Path $work 'Deep9.pas') $sb.ToString()

# --- CASE E fixture: the ancestor name has exactly ONE candidate, in an FMX unit. --
Write-Ascii (Join-Path $work 'FMX.Sole9.pas') @'
unit FMX.Sole9;

interface

type
  TSoleFmxMark9 = (sf9None, sf9Full);

  // The ONLY class of this name anywhere in the fixture. Because it is unique,
  // ResolveTypeNameToClass's PickCandidate short-circuits on it and the shared
  // scope rule is never consulted -- so nothing but the climb's own
  // cross-namespace guard stands between it and a Vcl class's ancestor chain.
  TSoleOnlyInFmx9 = class(TPersistent)
  private
    FSoleMark: TSoleFmxMark9;
  published
    property SoleMark: TSoleFmxMark9 read FSoleMark write FSoleMark;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.Sole9.pas') @'
unit Vcl.Sole9;

interface

// A 'Vcl.*' class whose ancestor is an ALIAS to a class that exists ONLY in an
// 'FMX.*' unit. The alias makes ResolveAncestry leave the edge unresolved (its
// candidate set is class/interface only), and the alias target is globally
// unique, so PickCandidate short-circuits without ever running the scope rule.
// Criterion 5 must still hold: 'SoleMark' must NOT appear on TVclSole9.

type
  TSoleAlias9 = TSoleOnlyInFmx9;

  TVclSole9 = class(TSoleAlias9)
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.SoleOkTarget9.pas') @'
unit Vcl.SoleOkTarget9;

interface

type
  TSoleOkMark9 = (so9None, so9Full);

  // The CONTROL target: also globally unique, also reached through an alias
  // from another unit -- but that unit shares this one's 'Vcl' namespace, so
  // the cross-namespace guard must NOT refuse it.
  TSoleOnlyInVcl9 = class(TPersistent)
  private
    FOkMark: TSoleOkMark9;
  published
    property OkMark: TSoleOkMark9 read FOkMark write FOkMark;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.SoleOk9.pas') @'
unit Vcl.SoleOk9;

interface

// CONTROL for case E: structurally IDENTICAL to Vcl.Sole9 -- alias ancestor,
// unresolved edge, globally unique target, PickCandidate short-circuit -- but
// the target lives in a 'Vcl.*' unit. This must still bridge, which is what
// makes case E's refusal attributable to the namespace conflict rather than to
// the climb simply being unable to bridge a lone candidate.

type
  TSoleOkAlias9 = TSoleOnlyInVcl9;

  TVclSoleOk9 = class(TSoleOkAlias9)
  end;

implementation

end.
'@

$db = Join-Path $WorkDir 'climb.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>$null
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($indexOut -join ' | ')"

function Get-Tree([string]$QName) {
  Push-Location $WorkDir
  try {
    $raw = (& $Exe proptree --qname $QName --format json --db $db --no-write-back 2>$null) -join "`n"
  } finally { Pop-Location }
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  return ($raw | ConvertFrom-Json)
}

# --- Sanity: the fixture really does present an UNRESOLVED 'TAmb9' edge, i.e. -----
#     this test is exercising the fallback and not a happy index-time resolution.
$script:PyEdge = Join-Path $WorkDir 'read_edge.py'
Write-Ascii $script:PyEdge @'
import sqlite3, sys
con = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True); c = con.cursor()
r = c.execute(
    "SELECT ta.ancestor_kind, ta.ancestor_symbol_id FROM type_ancestors ta "
    "JOIN symbols s ON s.id = ta.symbol_id AND s.kind='class' AND s.name=? "
    "WHERE ta.ancestor_name=? LIMIT 1", (sys.argv[2], sys.argv[3])).fetchone()
print('NOROW' if r is None else "%s|%s" % (r[0] or '', 'NULL' if r[1] is None else 'SET'))
con.close()
'@
Write-Host ''
Write-Host 'fixture sanity: the break really is an UNRESOLVED edge' -ForegroundColor Cyan
$edgeMid  = (python $script:PyEdge $db 'TMid9'  'TAmb9').Trim()
$edgeRoot = (python $script:PyEdge $db 'TRoot9' 'TMid9').Trim()
Check "Vcl.Mid9.TMid9's 'TAmb9' edge is UNRESOLVED (the fallback is what must fix it)" ($edgeMid -eq '?|NULL') "edge=$edgeMid"
Check "Zed.Root9.TRoot9's 'TMid9' edge IS resolved (so the climb reaches a 2nd unit)" ($edgeRoot -like 'class|SET') "edge=$edgeRoot"

# --- CASE A: criterion 7 -- the break is resolved in Vcl.Mid9's scope, not Zed's. --
Write-Host ''
Write-Host 'Case A: multi-unit climb resolves the break in the INHERITING unit (criterion 7)' -ForegroundColor Cyan
$tA = Get-Tree 'Zed.Root9.TRoot9'
Check "fixture sanity: TRoot9 resolves as a class" ($null -ne $tA -and $tA.root_type -eq 'TRoot9') "root_type=$($tA.root_type)"
$mA = @($tA.properties) | Where-Object { $_.path -eq 'Marker' } | Select-Object -First 1
Check "TRoot9 reaches 'Marker' at all (the climb crossed the unresolved TAmb9 edge)" ($null -ne $mA) `
  ("paths=" + (@(@($tA.properties) | ForEach-Object { $_.path }) -join ', ') + " -- ABSENT means the break was resolved in the ROOT unit 'Zed.Root9', whose 'Zed' prefix matches no candidate, so rule 3 declined: that IS the criterion-7 defect")
Check "TRoot9.Marker resolves to the Vcl candidate 'TMarkVcl9'" ($mA.type -eq 'TMarkVcl9') "type=$($mA.type)"
Check "TRoot9.Marker is NOT the FMX decoy 'TMarkFmx9' (criterion 5)"  ($mA.type -ne 'TMarkFmx9') "type=$($mA.type)"
Check "TRoot9 climb reached Vcl.Cand9.TAmb9, not FMX.Cand9.TAmb9" ($mA.declared_in -eq 'Vcl.Cand9.TAmb9') "declared_in=$($mA.declared_in)"

# --- CASE B: the mirror, from the SAME root unit -- so no single blanket scope -----
#             can satisfy both, only a genuinely per-hop one.
Write-Host ''
Write-Host 'Case B: the mirror direction, from the SAME root unit (criterion 5 + 7)' -ForegroundColor Cyan
$tB = Get-Tree 'Zed.Root9.TRootF9'
Check "fixture sanity: TRootF9 resolves as a class" ($null -ne $tB -and $tB.root_type -eq 'TRootF9') "root_type=$($tB.root_type)"
$mB = @($tB.properties) | Where-Object { $_.path -eq 'Marker' } | Select-Object -First 1
Check "TRootF9 reaches 'Marker' at all" ($null -ne $mB) `
  ("paths=" + (@(@($tB.properties) | ForEach-Object { $_.path }) -join ', '))
Check "TRootF9.Marker resolves to the FMX candidate 'TMarkFmx9'" ($mB.type -eq 'TMarkFmx9') "type=$($mB.type)"
Check "TRootF9.Marker is NOT the Vcl decoy 'TMarkVcl9' (criterion 5, reverse)" ($mB.type -ne 'TMarkVcl9') "type=$($mB.type)"
Check "TRootF9 climb reached FMX.Cand9.TAmb9, not Vcl.Cand9.TAmb9" ($mB.declared_in -eq 'FMX.Cand9.TAmb9') "declared_in=$($mB.declared_in)"

# --- CASE C: BRANCHING cycle -- exponential without the visited-class-id set. ------
#     Run out-of-process with a hard timeout: without the guard this never returns,
#     so a wall-clock bound is the assertion. 60 s is ~500x the guarded runtime.
Write-Host ''
Write-Host 'Case C: branching cyclic ancestry terminates (visited-class-id set)' -ForegroundColor Cyan
$outC = Join-Path $WorkDir 'cyc.json'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$pC = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir `
      -ArgumentList @('proptree','--qname','Cyc9.TCycHub','--format','json','--db',$db,'--no-write-back') `
      -RedirectStandardOutput $outC -RedirectStandardError "$outC.err" -NoNewWindow -PassThru
$finC = $pC.WaitForExit(60000)
$sw.Stop()
if (-not $finC) { try { $pC.Kill() } catch {} }
Check "branching cycle: terminates within 60 s (RED without the visited set: 2^64 branching)" `
  $finC "elapsed=$([math]::Round($sw.Elapsed.TotalSeconds,2))s"
Check "branching cycle: exits 0 (no stack overflow)" ($finC -and $pC.ExitCode -eq 0) "exit=$(if($finC){$pC.ExitCode}else{'TIMEOUT'})"
$tC = $null
if ($finC -and (Test-Path $outC)) {
  $rawC = Get-Content $outC -Raw
  if (-not [string]::IsNullOrWhiteSpace($rawC)) { $tC = $rawC | ConvertFrom-Json }
}
Check "branching cycle: root_type='TCycHub'" ($null -ne $tC -and $tC.root_type -eq 'TCycHub') "root_type=$($tC.root_type)"
$selfMarks = @(@($tC.properties) | Where-Object { $_.path -eq 'SelfMark' })
Check "branching cycle: 'SelfMark' emitted exactly once" ($selfMarks.Count -eq 1) "count=$($selfMarks.Count)"

# --- CASE D: depth cap, on an ACYCLIC chain where the visited set cannot fire. -----
Write-Host ''
Write-Host "Case D: bridged-climb depth cap (chain of $deepFar alias hops, cap = 64)" -ForegroundColor Cyan
$tD = Get-Tree 'Deep9.TDeep9_000'
Check "fixture sanity: TDeep9_000 resolves as a class" ($null -ne $tD -and $tD.root_type -eq 'TDeep9_000') "root_type=$($tD.root_type)"
$near = @($tD.properties) | Where-Object { $_.path -eq 'MarkNear' } | Select-Object -First 1
$far  = @($tD.properties) | Where-Object { $_.path -eq 'MarkFar'  } | Select-Object -First 1
Check "depth cap: marker at hop $deepNear (INSIDE the cap) IS reached" ($null -ne $near) `
  "RED if the cap were shrunk below $deepNear -- pins the cap from going too low"
Check "depth cap: marker at hop $deepFar (BEYOND the cap) is NOT reached" ($null -eq $far) `
  "RED if the depth cap were removed -- this is the cap's only observable effect"

# --- CASE E: criterion 5 where the ancestor name has a SINGLE candidate. -----------
Write-Host ''
Write-Host 'Case E: single-candidate ancestor in another namespace is REFUSED (criterion 5)' -ForegroundColor Cyan
$edgeSole = (python $script:PyEdge $db 'TVclSole9' 'TSoleAlias9').Trim()
Check "fixture sanity: TVclSole9's alias edge is UNRESOLVED (so the fallback runs)" ($edgeSole -eq '?|NULL') "edge=$edgeSole"
$tE = Get-Tree 'Vcl.Sole9.TVclSole9'
Check "fixture sanity: TVclSole9 resolves as a class" ($null -ne $tE -and $tE.root_type -eq 'TVclSole9') "root_type=$($tE.root_type)"
$soleE = @($tE.properties) | Where-Object { $_.path -eq 'SoleMark' } | Select-Object -First 1
Check "Vcl.Sole9.TVclSole9 does NOT inherit the FMX-only ancestor's 'SoleMark' (criterion 5)" ($null -eq $soleE) `
  ("type=$($soleE.type) declared_in=$($soleE.declared_in) -- PRESENT means a Vcl class was given an FMX ancestor with no scope check at all, because PickCandidate short-circuits on the lone candidate")
# And prove the refusal is namespace-driven, not a blanket inability to bridge an
# alias to a unique target: same shape, same-namespace target, must SUCCEED.
$tE2 = Get-Tree 'Vcl.SoleOk9.TVclSoleOk9'
$okE = @($tE2.properties) | Where-Object { $_.path -eq 'OkMark' } | Select-Object -First 1
Check "control: the SAME shape with a same-namespace target still bridges (guard is not a blanket refusal)" `
  ($null -ne $okE -and $okE.type -eq 'TSoleOkMark9') "type=$($okE.type) declared_in=$($okE.declared_in)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
