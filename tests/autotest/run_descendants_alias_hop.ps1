<#
  run_descendants_alias_hop.ps1 -- `query descendants` must traverse a TYPE
  ALIAS standing in heritage position, and must never EMIT the alias's name.

  REPORTED BY THE CONVERTER TEAM, 2026-09-14
  (docs\INBOX-forward-decl-shadows-real-class-declaration.md, symptom A):

      query descendants --of TControl --db library-Win64.sqlite
        -> 2918 names, TcxButton NOT among them

  The note blamed a forward-declaration stub. MEASURED on that index, the stub
  is not the cause of this symptom: the stub row owns no type_ancestors rows and
  the verb walks type_ancestors by NAME, so the stub is invisible to it. The
  chain actually breaks one hop higher:

      TcxButton        -> TcxCustomButton   (class,  resolved)
      TcxCustomButton  -> TcxBaseButton     (ancestor_kind '?')
      TcxBaseButton    = TCustomButton      (kind='type' -- a TYPE ALIAS, and it
                                             DOES own a type_ancestors row to
                                             TCustomButton since member C)
      TCustomButton    -> ... -> TControl

  FindDescendantNames' recursive CTE joined `symbols` with `s.kind = 'class'` at
  every hop, so the alias row could never enter the name set, and every class
  below it -- TcxCustomButton, TcxButton, and everything deriving from them --
  was silently absent. This is the note's ask 2, made observable.

  The fix walks class AND alias rows but EMITS only names reached as a class:
  an alias is not a class and must not appear in a class picker.

  CASES
    precondition  the index records the alias edge (TAliasHop -> TAliasRoot in
                  type_ancestors, on a kind='type' row) and TAliasChild's edge
                  names TAliasHop. Without those rows no query-time walk could
                  bridge the hop, and the fix would be an extractor change.
    P             POSITIVE CONTROL: TDirectChild (a plain class child) is
                  listed. Passes pre-fix -- proves the fixture and the verb work
                  and the alias hop is the only variable.
    A (the defect) TAliasChild and TAliasLeaf are listed. RED pre-fix.
    N1            TAliasHop itself is NOT listed -- an alias is not a class.
    N2            TStrongHop (`= type TAliasRoot`) is NOT listed either.
    A2            the two verbs agree: `query ancestors --name TAliasChild --of
                  TAliasBase` is True (already true pre-fix: GetTransitiveAncestors
                  late-resolves the alias and then expands the TARGET's own
                  edges) AND descendants lists TAliasChild.
    exit          found -> 0 (run_query_descendants_exitcode.ps1 owns the empty
                  case; not repeated here).

  WHY A2 IS ROOTED AT TAliasBase AND NOT AT TAliasRoot -- a SECOND defect,
  found while writing this guard and deliberately NOT pinned here:
  GetTransitiveAncestors' late resolution keeps the ALIAS name on the resolved
  row (`TAliasHop [class]`), so the alias TARGET's own name never enters the
  closure and `--of TAliasRoot` answers False while `--of TAliasBase` answers
  True. Same on the library index: `TcxButton --of TControl` True,
  `TcxButton --of TCustomButton` False. Filed as
  docs\INBOX-late-resolved-alias-keeps-the-alias-name.md; when that ships, add
  the `--of TAliasRoot` line here.

  RED SIGNATURE, observed against the pre-fix engine (drag-lint 1.12.0-alpha,
  third_party\dll-win64, 2026-09-14): the two CASE A lines and the descendants
  half of A2 FAIL; precondition, P, both N lines and the `--of` half of A2
  PASS.

  Usage: pwsh -File tests/autotest/run_descendants_alias_hop.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-descendants-alias-hop"
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

Write-Ascii (Join-Path $work 'AliasHop.pas') @'
unit AliasHop;

interface

type
  // One hop ABOVE the alias target: the root A2's agreement control is asked
  // about, because the alias target's own name is not reachable through
  // `--of` today (see the header).
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
  // class. Present only so N2 can pin that it is never emitted.
  TStrongHop = type TAliasRoot;

implementation

end.
'@

$db = Join-Path $WorkDir 'alias.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($indexOut -join ' | ')"

# --- Probes. ----------------------------------------------------------------------
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
# The engine pretty-prints its JSON over many lines, so take everything from
# the first line that opens an object to the end -- not just that one line.
function JsonFrom([string[]]$Lines) {
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i].TrimStart().StartsWith('{')) { return ($Lines[$i..($Lines.Count - 1)] -join "`n") }
  }
  return ''
}
function Descendants([string]$Of) {
  $raw = @(& $Exe query descendants --of $Of --json --db $db 2>$null) | ForEach-Object { "$_" }
  $code = $LASTEXITCODE
  $json = JsonFrom $raw
  $names = @()
  if ($json) { $names = @(($json | ConvertFrom-Json).descendants) }
  return @{ Code = $code; Names = $names }
}
function Descends([string]$Name, [string]$Of) {
  $raw = @(& $Exe query ancestors --name $Name --of $Of --json --db $db 2>$null) | ForEach-Object { "$_" }
  $json = JsonFrom $raw
  if (-not $json) { return $null }
  return [bool](($json | ConvertFrom-Json).is_descendant)
}

# --- preconditions: the index holds the rows a query-time walk needs -----------
Write-Host ''
Write-Host 'preconditions -- the alias edge IS indexed, so this is a query-side gap' -ForegroundColor Cyan
$hopKind = Sql "SELECT kind FROM symbols WHERE name='TAliasHop'"
Check "precondition: TAliasHop is indexed as kind='type' (a type alias, not a class)" ($hopKind -eq 'type') "kind=$hopKind"
$hopEdge = Sql "SELECT ta.ancestor_name FROM type_ancestors ta JOIN symbols s ON s.id=ta.symbol_id WHERE s.name='TAliasHop'"
Check 'precondition: the alias row owns a type_ancestors edge to TAliasRoot' ($hopEdge -eq 'TAliasRoot') "edge=$hopEdge -- absent means the fix is an EXTRACTOR change, not this one"
$childEdge = Sql "SELECT ta.ancestor_name FROM type_ancestors ta JOIN symbols s ON s.id=ta.symbol_id WHERE s.name='TAliasChild'"
Check "precondition: TAliasChild's edge names the ALIAS" ($childEdge -eq 'TAliasHop') "edge=$childEdge"
$strongEdges = Sql "SELECT COUNT(*) FROM type_ancestors ta JOIN symbols s ON s.id=ta.symbol_id WHERE s.name='TStrongHop'"
Check 'precondition: the strong alias owns NO heritage row (documented parser scope)' ($strongEdges -eq '0') "rows=$strongEdges"

# --- the walk ------------------------------------------------------------------
Write-Host ''
Write-Host 'query descendants --of TAliasRoot' -ForegroundColor Cyan
$d = Descendants 'TAliasRoot'
Check 'exit 0 (descendants found)' ($d.Code -eq 0) "exit=$($d.Code)"
Check 'P (positive control): TDirectChild is listed' ($d.Names -contains 'TDirectChild') "got: [$($d.Names -join ', ')]"
Check 'CASE A: TAliasChild is listed (the hop THROUGH the alias)' ($d.Names -contains 'TAliasChild') `
  ("got: [" + ($d.Names -join ', ') + "] -- ABSENT means the recursive CTE still joins kind='class' only and the alias row never enters the name set")
Check 'CASE A: TAliasLeaf is listed (everything below the hop)' ($d.Names -contains 'TAliasLeaf') "got: [$($d.Names -join ', ')]"
Check 'N1: TAliasHop is NOT listed (an alias is not a class)' (-not ($d.Names -contains 'TAliasHop')) "got: [$($d.Names -join ', ')]"
Check 'N2: TStrongHop is NOT listed' (-not ($d.Names -contains 'TStrongHop')) "got: [$($d.Names -join ', ')]"

# --- A2: the two verbs agree -------------------------------------------------------
Write-Host ''
Write-Host 'A2: `ancestors --of` (late-resolves the alias) and `descendants` agree' -ForegroundColor Cyan
$isDesc = Descends 'TAliasChild' 'TAliasBase'
Check 'A2: TAliasChild --of TAliasBase is True (already true pre-fix; see the header for why not TAliasRoot)' ($isDesc -eq $true) "is_descendant=$isDesc"
Check 'A2: ...and descendants lists TAliasChild (the half that was RED)' (($isDesc -eq $true) -and ($d.Names -contains 'TAliasChild')) "is_descendant=$isDesc listed=$($d.Names -contains 'TAliasChild')"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
