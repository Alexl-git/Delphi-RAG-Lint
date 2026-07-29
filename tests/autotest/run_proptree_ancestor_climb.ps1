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

  CASE C -- CYCLE GUARD. 'TSelfAlias9 = TSelfCyc9;' with
  'TSelfCyc9 = class(TSelfAlias9)' is a self-referential ancestry: the alias
  ancestor bridges straight back to the class that declares it. ClassChain must
  place/climb each class at most once (visited-class-id set) and cap bridged
  recursion, so this terminates with a one-class chain instead of spinning.
  HONEST SCOPE OF THIS CASE: what it observes is that the query TERMINATES,
  exits 0, and emits the class's own property exactly once -- it does not, and
  cannot from the CLI, distinguish which of the two guards (visited set or depth
  cap) stopped it. It is a live-fire regression guard against a hang/stack
  overflow on a malformed or self-referential index, not a unit test of the
  visited set in isolation.
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

// CYCLE: the alias ancestor resolves straight back to the class that declares
// it, so bridging it hands the climb a class it has already placed. The climb
// must terminate (visited-class-id set + bridged-depth cap), not spin.

type
  TSelfAlias9 = TSelfCyc9;

  TSelfCyc9 = class(TSelfAlias9)
  private
    FSelfMark: Integer;
  published
    property SelfMark: Integer read FSelfMark write FSelfMark;
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

# --- CASE C: cyclic ancestry must terminate, not spin. -----------------------------
Write-Host ''
Write-Host 'Case C: self-referential ancestry terminates (cycle + depth guards)' -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$rawC = $null
Push-Location $WorkDir
try { $rawC = (& $Exe proptree --qname Cyc9.TSelfCyc9 --format json --db $db --no-write-back 2>$null) -join "`n" } finally { Pop-Location }
$ecC = $LASTEXITCODE
$sw.Stop()
Check "cyclic ancestry: proptree exits 0 (no hang, no stack overflow)" ($ecC -eq 0) "exit=$ecC elapsed=$([math]::Round($sw.Elapsed.TotalSeconds,2))s"
$tC = if ([string]::IsNullOrWhiteSpace($rawC)) { $null } else { $rawC | ConvertFrom-Json }
Check "cyclic ancestry: root_type='TSelfCyc9'" ($null -ne $tC -and $tC.root_type -eq 'TSelfCyc9') "root_type=$($tC.root_type)"
$selfMarks = @(@($tC.properties) | Where-Object { $_.path -eq 'SelfMark' })
Check "cyclic ancestry: 'SelfMark' emitted exactly once (chain not walked twice)" ($selfMarks.Count -eq 1) "count=$($selfMarks.Count)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
