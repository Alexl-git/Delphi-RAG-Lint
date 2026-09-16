<#
  run_ancestors_alias_target_name.ps1 -- a LATE-RESOLVED type-alias ancestor must
  answer to BOTH names: the alias as WRITTEN in the heritage list, and the class
  the alias resolves to.

  THE DEFECT (docs\INBOX-late-resolved-alias-keeps-the-alias-name.md, found by
  session 93's X1 while writing run_descendants_alias_hop.ps1):

      query ancestors --name TcxButton --of TControl        -> True
      query ancestors --name TcxButton --of TCustomButton   -> False   (WRONG)

  GetTransitiveAncestors late-resolves an unresolved heritage edge through
  ResolveTypeNameToClass, which chases a TYPE ALIAS to its target class. It then
  stamps the row with the TARGET's symbol id, file id and kind -- but leaves
  `Name` as the ALIAS. The walk therefore DOES traverse the alias (the target's
  own edges are expanded, which is why `--of TControl` is True), while the
  target's OWN name never enters the closure. A naming defect in the accumulated
  row, not a traversal defect.

  WHY THIS GUARD ASSERTS BOTH DIRECTIONS. The obvious fix -- overwrite `Name`
  with the target's -- trades one wrong answer for another: every consumer that
  legitimately asks about the alias as the source WROTE it (`--of TAliasHop`,
  and PropTree's ScopeSymbolFor, which resolves A.Name in the declaring class's
  unit scope) would start answering False. A test that only checks the new True
  is half a test and would pass a regression. So the shipped contract is
  ADDITIVE: `Name` keeps the written alias, a new `ResolvedName` carries the
  target, and name matching consults both. CASE B is the half that pins it.

  It is also why this guard pins the ROW SHAPE (S1/S2). The other candidate fix
  -- appending a second row for the target -- would satisfy CASE A and CASE B
  both, and silently break CallResolver.LookupMethodOnType, which counts matches
  across ancestor rows and reads two candidates as AMBIGUOUS: a duplicate row
  for the same symbol id would double every inherited method and REMOVE resolved
  call edges. Row count is part of the contract.

  CASES
    precondition   the alias edge is indexed (kind='type' row owning a
                   type_ancestors edge) -- so this is a query-side gap, not an
                   extractor one.
    A (the defect) `--of TAliasRoot` (the alias TARGET) is True. RED pre-fix.
    A2             ...and from one level deeper, TAliasLeaf. RED pre-fix.
    B (the other   `--of TAliasHop` (the alias NAME, as written) STAYS True, and
      direction)   the JSON list still CONTAINS the name TAliasHop. Both PASS
                   pre-fix; they are here to fail a name-overwriting fix.
    P              POSITIVE CONTROL: `--of TAliasBase`, one hop ABOVE the
                   target, is True. Passes pre-fix -- proves the fixture, the
                   verb and the walk work and the target's NAME is the only
                   variable.
    N1             `--of TStrongHop` (`= type TAliasRoot`, a distinct type
                   carrying no heritage row) is False. Pins that the widened
                   match did not become "matches everything".
    N2             `--of TNoSuchAncestor` is False.
    S1             no name is listed TWICE -- the fix adds a field, not a row.
    S2             the TAliasHop row carries resolved_name=TAliasRoot, and a
                   plain resolved class row (TAliasBase) carries an EMPTY
                   resolved_name. The alias name did not move and the target is
                   reachable.

  RED SIGNATURE, expected against the pre-fix engine: CASE A, CASE A2 and S2
  FAIL; precondition, CASE B, P, N1, N2 and S1 PASS.

  Usage: pwsh -File tests/autotest/run_ancestors_alias_target_name.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-ancestors-alias-target"
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

# Deliberately the SAME shape as run_descendants_alias_hop.ps1's fixture: the two
# guards pin the two halves of one defect and must not disagree about the corpus.
Write-Ascii (Join-Path $work 'AliasHop.pas') @'
unit AliasHop;

interface

type
  TAliasBase = class(TPersistent)
  end;

  TAliasRoot = class(TAliasBase)
  private
    FRootMark: Integer;
  published
    property RootMark: Integer read FRootMark write FRootMark;
  end;

  // The cxButtons shape: `TcxBaseButton = TCustomButton;` then
  // `TcxCustomButton = class(TcxBaseButton, ...)`. A plain alias in heritage
  // position.
  TAliasHop = TAliasRoot;

  TAliasChild = class(TAliasHop)
  private
    FChildMark: Integer;
  published
    property ChildMark: Integer read FChildMark write FChildMark;
  end;

  TAliasLeaf = class(TAliasChild)
  end;

  // POSITIVE CONTROL: a direct class child, no alias anywhere.
  TDirectChild = class(TAliasRoot)
  end;

  // A STRONG alias is a distinct type; it carries no heritage row and is not a
  // class. Present only so N1 can pin that it never becomes an ancestor.
  TStrongHop = type TAliasRoot;

implementation

end.
'@

$db = Join-Path $WorkDir 'alias.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($indexOut -join ' | ')"

$script:PySql = Join-Path $WorkDir 'sql.py'
Write-Ascii $script:PySql @'
import sqlite3, sys
con = sqlite3.connect("file:%s?mode=ro" % sys.argv[1].replace("\\", "/"), uri=True)
print("\n".join("|".join("" if v is None else str(v) for v in r)
                for r in con.execute(sys.argv[2]).fetchall()))
con.close()
'@
function Sql([string]$Q) { return ((python $script:PySql $db $Q) -join "`n").Trim() }

# Captured into a variable FIRST -- an exit code read through a broken pipe
# (`| Select-Object -First N`) reports 2 and reads as an engine failure.
function JsonFrom([string[]]$Lines) {
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i].TrimStart().StartsWith('{')) { return ($Lines[$i..($Lines.Count - 1)] -join "`n") }
  }
  return ''
}
function Descends([string]$Name, [string]$Of) {
  $raw = @(& $Exe query ancestors --name $Name --of $Of --json --db $db 2>$null) | ForEach-Object { "$_" }
  $json = JsonFrom $raw
  if (-not $json) { return $null }
  return [bool](($json | ConvertFrom-Json).is_descendant)
}
function AncestorRows([string]$Name) {
  $raw = @(& $Exe query ancestors --name $Name --json --db $db 2>$null) | ForEach-Object { "$_" }
  $json = JsonFrom $raw
  if (-not $json) { return @() }
  return @(($json | ConvertFrom-Json).ancestors)
}

# --- precondition: the alias edge IS indexed, so this is a query-side gap -------
Write-Host ''
Write-Host 'precondition -- the alias edge is in the index' -ForegroundColor Cyan
$hopKind = Sql "SELECT kind FROM symbols WHERE name='TAliasHop'"
Check "precondition: TAliasHop is indexed as kind='type'" ($hopKind -eq 'type') "kind=$hopKind"
$hopEdge = Sql "SELECT ta.ancestor_name FROM type_ancestors ta JOIN symbols s ON s.id=ta.symbol_id WHERE s.name='TAliasHop'"
Check 'precondition: the alias row owns a type_ancestors edge to TAliasRoot' ($hopEdge -eq 'TAliasRoot') "edge=$hopEdge"

# --- CASE A: the alias TARGET is an ancestor -----------------------------------
Write-Host ''
Write-Host 'CASE A -- the alias TARGET answers --of' -ForegroundColor Cyan
$aRoot = Descends 'TAliasChild' 'TAliasRoot'
Check 'CASE A: TAliasChild --of TAliasRoot is True' ($aRoot -eq $true) `
  "is_descendant=$aRoot -- False means the late-resolved row still carries only the ALIAS name"
$aLeaf = Descends 'TAliasLeaf' 'TAliasRoot'
Check 'CASE A2: TAliasLeaf --of TAliasRoot is True (one level deeper)' ($aLeaf -eq $true) "is_descendant=$aLeaf"

# --- CASE B: the alias NAME did not vanish --------------------------------------
Write-Host ''
Write-Host 'CASE B -- the OTHER direction: the alias name as WRITTEN still answers' -ForegroundColor Cyan
$bHop = Descends 'TAliasChild' 'TAliasHop'
Check 'CASE B: TAliasChild --of TAliasHop STAYS True (the written alias name)' ($bHop -eq $true) `
  "is_descendant=$bHop -- False means the fix OVERWROTE Name instead of adding the target"
$rows = AncestorRows 'TAliasChild'
$names = @($rows | ForEach-Object { $_.name })
Check 'CASE B: the ancestor list still CONTAINS the name TAliasHop' ($names -contains 'TAliasHop') "got: [$($names -join ', ')]"

# --- P: positive control ---------------------------------------------------------
Write-Host ''
Write-Host 'P (positive control) -- one hop ABOVE the target, True pre-fix' -ForegroundColor Cyan
$pBase = Descends 'TAliasChild' 'TAliasBase'
Check 'P: TAliasChild --of TAliasBase is True' ($pBase -eq $true) "is_descendant=$pBase"

# --- N: the widened match did not become "matches everything" --------------------
Write-Host ''
Write-Host 'N (negative controls)' -ForegroundColor Cyan
$n1 = Descends 'TAliasChild' 'TStrongHop'
Check 'N1: TAliasChild --of TStrongHop is False (a strong alias is a distinct type)' ($n1 -eq $false) "is_descendant=$n1"
$n2 = Descends 'TAliasChild' 'TNoSuchAncestor'
Check 'N2: TAliasChild --of TNoSuchAncestor is False' ($n2 -eq $false) "is_descendant=$n2"

# --- S: the ROW SHAPE is part of the contract ------------------------------------
Write-Host ''
Write-Host 'S (row shape) -- a FIELD was added, not a ROW' -ForegroundColor Cyan
$dupes = @($names | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
Check 'S1: no ancestor name is listed twice' ($dupes.Count -eq 0) `
  "duplicates: [$($dupes -join ', ')] -- a second row for the alias TARGET would double every inherited method in CallResolver.LookupMethodOnType and read as AMBIGUOUS"
$hopRow  = @($rows | Where-Object { $_.name -eq 'TAliasHop'  })[0]
$baseRow = @($rows | Where-Object { $_.name -eq 'TAliasBase' })[0]
Check 'S2: the TAliasHop row carries resolved_name=TAliasRoot' `
  (($null -ne $hopRow) -and ($hopRow.resolved_name -eq 'TAliasRoot')) "resolved_name=$($hopRow.resolved_name)"
Check 'S2: a plain resolved class row carries an EMPTY resolved_name' `
  (($null -ne $baseRow) -and ([string]::IsNullOrEmpty($baseRow.resolved_name))) "resolved_name=$($baseRow.resolved_name)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
