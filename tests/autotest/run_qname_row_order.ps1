<#
  run_qname_row_order.ps1 -- FindSymbolsByQualifiedName returns an ORDERED result,
  and Result[0] is the row a reader wants.

  THE BUG (ported from feat/autodoc-phase3, whose measurements were re-derived on
  this machine by tools/measure/phase1_verify.py against the shipped, read-only
  C:\Projects\.drag-lint\library-Win64.sqlite). The prepared query behind
  FindSymbolsByQualifiedName carried NO `ORDER BY` at all, so for a duplicated
  qualified name the FIRST row -- which ResolveTypeNameToClassEx, PropTree's
  ResolveClassByQName and `hover --qname` all reach for -- was whatever SQLite's
  scan happened to return. It is not a rare case: 71258 qualified names own more
  than one `symbols` row in library-Win64, 23664 of them of kind
  class/interface/record. Live symptom on that index: `hover --qname
  System.TObject` answered def_line 599, the `TObject = class;` FORWARD
  DECLARATION, while the real body starts at 680.

  THE ORDER NOW, most-useful first and then total:
    1. a real declaration BEFORE a forward-declaration stub -- the engine's own
       predicate, transcribed from IsStub (in ResolveTypeNameToClassEx) and
       Convert.PropTree's IsForwardDeclClass: class/interface, empty heritage,
       end_line <= start_line. Both of those hand-roll this preference AFTER the
       query returns; in the ORDER BY, every other consumer gets it too. It
       discriminates for 23511 of the 23664 duplicate type qnames.
    2. then a row carrying an implementation body. NARROW, and pinned as such: it
       decides only among ROUTINE rows, because a class/interface/record row never
       has an impl span. 398 of 71258 duplicates (0.56%), 0 of the 23664 type ones.
    3. then file_id, start_line, id -- three columns that cannot tie.

  WHAT EACH CHECK IS FOR. The two ASSERT checks below are `hover --qname`
  def_line, i.e. the engine's own answer through Result[0]. Each is preceded by a
  DE-VACUATOR that reads the tie-breakers-ALONE row order out of the DB and
  asserts the WRONG row sorts first under them: without that, an assertion could
  pass because the fixture happened to be ordered conveniently rather than because
  the new leading term did any work. Expected line numbers are read from the DB
  rather than hard-coded, so editing the fixture cannot silently make a check
  vacuous.

  NOT COVERED, deliberately: which of two duplicate FULL definitions in two
  different files is the right one. The order makes that choice deterministic
  (lowest file_id), not correct -- indexer-side path normalisation is the other
  half of that problem and is not done here.

  Usage: pwsh -File tests/autotest/run_qname_row_order.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-qname-row-order"
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

# Two NATURAL Delphi shapes, not contrivances -- both are ordinary in RTL/VCL
# source, which is why the population the measurement found is so large.
Write-Ascii (Join-Path $work 'OrdKit.pas') @'
unit OrdKit;

interface

type
  // SHAPE 1: a forward class declaration. The parser emits a SEPARATE class
  // symbol for it, in the SAME file, with empty heritage and end_line =
  // start_line -- so 'OrdKit.TFwd' owns two rows and this one is the stub. It is
  // declared FIRST, so under (file_id, start_line, id) alone it wins.
  TFwd = class;

  // Present only so the forward declaration has a reason to exist (a reader
  // deleting it would otherwise make the fixture look pointless).
  TOther = class(TObject)
  private
    FLink: TFwd;
  end;

  // ...and the real body, which is what a hover must report.
  TFwd = class(TObject)
  private
    FValue: Integer;
  public
    function Twice: Integer;
  end;

  // SHAPE 2: an overload pair sharing one qualified name, whose ABSTRACT member
  // is declared first and carries no implementation span. Only the impl term
  // separates these two, and it is the only shape it can separate -- a type row
  // never has an impl span at all.
  TOv = class(TObject)
  public
    procedure Go(A: Integer); overload; virtual; abstract;
    procedure Go(const A: string); overload;
  end;

implementation

function TFwd.Twice: Integer;
begin
  Result:= FValue * 2;
end;

procedure TOv.Go(const A: string);
begin
end;

end.
'@

$db = Join-Path $WorkDir 'ord.sqlite'
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
# def_line as the ENGINE answers it: `hover --qname` renders Result[0].
function HoverDefLine([string]$QName) {
  # ToString() rather than a String method: 2>&1 folds stderr in as ErrorRecord
  # objects, and calling .TrimStart() on one of those is a runtime error.
  $raw = @(& $Exe hover --qname $QName --db $db --format json 2>&1) |
           ForEach-Object { "$_" } | Where-Object { $_.TrimStart().StartsWith('{') }
  if (-not $raw) { return '<no json>' }
  return ([string]($raw | Select-Object -First 1) | ConvertFrom-Json).def_line
}
# The engine's own stub predicate, transcribed (see the suite header).
$stubTerm = "kind IN ('class','interface') AND COALESCE(TRIM(heritage),'')='' AND end_line<=start_line"

# --- SHAPE 1: a forward-declaration stub must never be Result[0]. -----------------
Write-Host ''
Write-Host 'SHAPE 1 -- a forward-declared class owns two rows; the BODY is the answer' -ForegroundColor Cyan

$fwdRows = Sql "SELECT COUNT(*) FROM symbols WHERE qualified_name='OrdKit.TFwd'"
Check 'precondition: OrdKit.TFwd owns exactly 2 symbols rows' ($fwdRows -eq '2') "rows=$fwdRows"

$fwdStubs = Sql "SELECT COUNT(*) FROM symbols WHERE qualified_name='OrdKit.TFwd' AND $stubTerm"
Check "precondition: exactly ONE of them is a stub by the engine's own predicate" ($fwdStubs -eq '1') `
  "stub rows=$fwdStubs -- if 0, the parser stopped emitting a symbol for a forward declaration and this whole shape is gone"

# The de-vacuator: under the tie-breakers ALONE the STUB sorts first, so the
# leading term is doing the work rather than agreeing with an accident.
$fwdTieFirst = Sql "SELECT CASE WHEN $stubTerm THEN 'STUB' ELSE 'BODY' END FROM symbols WHERE qualified_name='OrdKit.TFwd' ORDER BY file_id, start_line, id LIMIT 1"
Check 'de-vacuator: under (file_id, start_line, id) ALONE the STUB would be first' ($fwdTieFirst -eq 'STUB') `
  "tie-breakers-alone first row=$fwdTieFirst -- if this says BODY the next check passes for free"

$fwdBodyLine = Sql "SELECT start_line FROM symbols WHERE qualified_name='OrdKit.TFwd' AND NOT ($stubTerm)"
$fwdStubLine = Sql "SELECT start_line FROM symbols WHERE qualified_name='OrdKit.TFwd' AND $stubTerm"
$fwdHover    = HoverDefLine 'OrdKit.TFwd'
Check "ASSERT: hover --qname OrdKit.TFwd reports the BODY's line, not the stub's" ("$fwdHover" -eq "$fwdBodyLine") `
  "def_line=$fwdHover want=$fwdBodyLine (the stub is at line $fwdStubLine) -- this is exactly the System.TObject 599-vs-680 case"

# --- SHAPE 2: among ROUTINE rows, an implemented body beats an unimplemented one. --
Write-Host ''
Write-Host 'SHAPE 2 -- an overload pair; the row with an implementation is the answer' -ForegroundColor Cyan

$ovRows = Sql "SELECT COUNT(*) FROM symbols WHERE qualified_name='OrdKit.TOv.Go'"
Check 'precondition: OrdKit.TOv.Go owns exactly 2 symbols rows' ($ovRows -eq '2') "rows=$ovRows"

$ovImpl = Sql "SELECT COUNT(*) FROM symbols WHERE qualified_name='OrdKit.TOv.Go' AND impl_start_line IS NOT NULL AND impl_start_line>0"
Check 'precondition: exactly ONE of them carries an implementation span' ($ovImpl -eq '1') `
  "rows with an impl span=$ovImpl -- 2 or 0 and the impl term cannot discriminate here"

$ovTieFirst = Sql "SELECT CASE WHEN impl_start_line IS NOT NULL AND impl_start_line>0 THEN 'IMPL' ELSE 'ABSTRACT' END FROM symbols WHERE qualified_name='OrdKit.TOv.Go' ORDER BY file_id, start_line, id LIMIT 1"
Check 'de-vacuator: under (file_id, start_line, id) ALONE the ABSTRACT row would be first' ($ovTieFirst -eq 'ABSTRACT') `
  "tie-breakers-alone first row=$ovTieFirst -- if this says IMPL the next check passes for free"

$ovImplLine = Sql "SELECT start_line FROM symbols WHERE qualified_name='OrdKit.TOv.Go' AND impl_start_line IS NOT NULL AND impl_start_line>0"
$ovAbsLine  = Sql "SELECT start_line FROM symbols WHERE qualified_name='OrdKit.TOv.Go' AND (impl_start_line IS NULL OR impl_start_line<=0)"
$ovHover    = HoverDefLine 'OrdKit.TOv.Go'
Check "ASSERT: hover --qname OrdKit.TOv.Go reports the IMPLEMENTED overload's line" ("$ovHover" -eq "$ovImplLine") `
  "def_line=$ovHover want=$ovImplLine (the abstract one is at line $ovAbsLine)"

# --- Control: a name with ONE row is untouched, and the answer is repeatable. ------
Write-Host ''
Write-Host 'controls -- nothing else moved, and the answer is reproducible' -ForegroundColor Cyan

$otherRows = Sql "SELECT COUNT(*) FROM symbols WHERE qualified_name='OrdKit.TOther'"
Check 'precondition: OrdKit.TOther owns exactly 1 row (the control is a control)' ($otherRows -eq '1') "rows=$otherRows"
$otherLine  = Sql "SELECT start_line FROM symbols WHERE qualified_name='OrdKit.TOther'"
$otherHover = HoverDefLine 'OrdKit.TOther'
Check 'control: a single-row qname still reports its own line' ("$otherHover" -eq "$otherLine") "def_line=$otherHover want=$otherLine"

# Repeatability, deliberately compared against what the FIRST run OBSERVED rather
# than against what is expected -- so this check stays green under a mutation that
# reddens the two ASSERTs, and can only fail on a genuinely unstable answer. It is
# a smoke check, not a proof of totality: SQLite is deterministic for a given file,
# so no in-process repeat can demonstrate that the order cannot tie.
$again = "$(HoverDefLine 'OrdKit.TFwd')/$(HoverDefLine 'OrdKit.TOv.Go')"
Check 'smoke: a second hover of both names repeats the first run exactly' ($again -eq "$fwdHover/$ovHover") `
  "second run=$again first run=$fwdHover/$ovHover"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
