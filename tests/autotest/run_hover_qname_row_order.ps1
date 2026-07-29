# drag-lint `hover --qname` ROW-SELECTION test (register K29, Task 4f fix round 1).
#
# WHAT IS UNDER TEST
# ------------------
# One qualified name legitimately owns SEVERAL `symbols` rows, and every caller
# of FindSymbolsByQualifiedName -- hover, surface, context, document, rename,
# proptree -- takes Syms[0]. Which row that is, is decided by the ORDER BY in
# FQFindByQName (src/storage/DRagLint.Storage.SQLite.pas). Until Task 4f there
# was none at all, so the answer was whatever the query planner emitted first
# and could move on a rebuild or a VACUUM with no line of code changing.
#
# The FIRST fix (commit 64383ce) ordered by "impl_start_line > 0 first", and its
# comment claimed that put "a row with an implementation body before a
# forward-declaration stub". That claim was FALSE for the entire type
# population: a class/interface/record row never carries an impl span, so the
# CASE takes one value for every candidate and decides nothing. Measured on
# C:\Projects\.drag-lint\library-Win64.sqlite --
#   command   : sqlite over the shipped index
#   unit      : DISTINCT qualified_name owning more than one `symbols` row
#   classifier: the ORDER BY term takes BOTH values inside the group, i.e. it
#               actually discriminates
#   71258 duplicate qnames, the impl term discriminates for 398 (0.56%);
#   23664 of kind class/interface/record, the impl term discriminates for 0.
# Live proof of the harm, same index: `hover --qname System.TObject` answered
# def_line 599 -- the `TObject = class;` forward stub -- while the real body
# starts at 680.
#
# The ordering now leads with the ENGINE'S OWN stub predicate, the one
# TSQLiteSymbolStore's IsStub and Convert.PropTree's IsForwardDeclClass already
# spell in Pascal: kind is class/interface, heritage empty, end_line <=
# start_line. On the same index that term discriminates for 23511 of the 23664
# duplicate class/interface/record qnames -- forward declarations are ordinary
# in RTL/VCL source, and each one gives its class a second row IN THE SAME FILE.
#
# THE FIXTURE IS TWO NATURAL DELPHI SHAPES, NOT A DOCTORED INDEX
# --------------------------------------------------------------
#   Shape 1  a FORWARD-DECLARED class. Two rows; the STUB has the lower line, so
#            file order reaches it first and the reader gets a declaration with
#            no members, no ancestors and no facts.
#   Shape 2  an OVERLOAD PAIR whose ABSTRACT member is declared FIRST. Two rows;
#            the abstract one has no implementation (impl_start_line = 0) and is
#            the row file order reaches first. This is what the impl term is
#            for, and it is asserted so that the term is not carried on prose.
#
# Both scenarios assert the TIE-BREAKERS ALONE (file_id, start_line, id) reach
# the WRONG row first, read straight out of the DB. Without that, "hover
# returns the body" would pass on any index whose rows happened to be stored in
# the convenient order, and the check would prove nothing.
#
# RED EVIDENCE (Task 4f fix round 1): against the engine at dc4cc70 -- the
# impl-term-only ORDER BY -- this file failed on ONE check, `def_line=7 want=16
# stub=7`: the stub. Every precondition was green, so the red named the
# assertion and not a broken fixture. Shape 2 was ALREADY green there and is
# kept as the control on the term that fix must not drop.
#
# Usage: pwsh -File tests/autotest/run_hover_qname_row_order.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-hover-qname-row-order"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $s = if ($Ok) {'PASS'} else {'FAIL'}
    $c = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
    if (-not $Ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir | Out-Null
$pas = Join-Path $srcDir 'qrowfix.pas'
$db  = Join-Path $WorkDir 'q.sqlite'

# The fixture. Line numbers are NEVER hardcoded below -- every expected line is
# read back off this text by regex, so an edit here cannot silently turn a
# check into an assertion about the wrong line.
@'
unit qrowfix;

interface

type
  // Shape 1 -- a FORWARD-DECLARED class. The stub comes first in file order.
  TThing = class;

  THolder = class
  private
    FThing: TThing;
  public
    property Thing: TThing read FThing;
  end;

  TThing = class(TObject)
  private
    FValue: Integer;
  public
    // Shape 2 -- an OVERLOAD PAIR whose ABSTRACT member is declared FIRST, so
    // the row with no implementation is the one file order reaches first.
    function Doubled(A: Integer): Integer; overload; virtual; abstract;
    function Doubled: Integer; overload;
    property Value: Integer read FValue write FValue;
  end;

implementation

function TThing.Doubled: Integer;
begin
  Result := FValue * 2;
end;

end.
'@ | Set-Content -LiteralPath $pas -Encoding ascii

& $exePath index $srcDir --db $db 2>&1 | Out-Null

# --- read rows straight out of the DB -------------------------------------
# The DB is the only place the ROW SET is visible; the CLI shows one row by
# construction, which is the thing under test.
$rowPy = Join-Path $WorkDir 'rows.py'
@'
import sqlite3, sys, json
con = sqlite3.connect(sys.argv[1])
rows = [dict(id=r[0], file_id=r[1], kind=r[2], heritage=(r[3] or ''),
             start_line=r[4], end_line=r[5], impl=(r[6] or 0))
        for r in con.execute(
            "SELECT id, file_id, kind, heritage, start_line, end_line, impl_start_line "
            "FROM symbols WHERE qualified_name = ? "
            "ORDER BY file_id, start_line, id", (sys.argv[2],))]
print(json.dumps(rows))
'@ | Set-Content -LiteralPath $rowPy -Encoding ascii

function Get-Rows([string]$qname) {
    $j = (& python $rowPy $db $qname) -join ''
    if ([string]::IsNullOrWhiteSpace($j)) { return @() }
    return @($j | ConvertFrom-Json)
}
function Get-HoverDefLine([string]$qname) {
    $raw = (& $exePath hover --qname $qname --db $db --format json 2>$null) -join ''
    $o = $null
    try { $o = ($raw -replace '\s*FTS5 probe:.*$','') | ConvertFrom-Json } catch { return -1 }
    if ($null -eq $o) { return -1 }
    return [int]$o.def_line
}

$src = [IO.File]::ReadAllLines($pas)
function Line-Of([string]$rx) {
    for ($i = 0; $i -lt $src.Count; $i++) { if ($src[$i] -match $rx) { return $i + 1 } }
    return 0
}

Write-Host ''
Write-Host '=== Shape 1: a forward-declared class ===' -ForegroundColor Cyan

$stubLine = Line-Of '^\s*TThing = class;\s*$'
$bodyLine = Line-Of '^\s*TThing = class\(TObject\)\s*$'
Check 'PRECONDITION: the fixture spells the stub ABOVE the body' `
  (($stubLine -gt 0) -and ($bodyLine -gt $stubLine)) "stub=$stubLine body=$bodyLine"

$tRows = Get-Rows 'qrowfix.TThing'
Check 'PRECONDITION: the index holds exactly TWO rows for qrowfix.TThing' `
  ($tRows.Count -eq 2) ("rows=" + (($tRows | ForEach-Object { "$($_.start_line)..$($_.end_line)" }) -join ' '))

# The engine's own IsStub predicate, restated here over the raw columns. This is
# the REQUIREMENT ("a forward-declaration stub loses to a real declaration"),
# not the SQL's spelling of it: it is written against the fixture's shape, so a
# future ORDER BY that satisfies it some other way still passes.
$stubRows = @($tRows | Where-Object { $_.heritage.Trim() -eq '' -and $_.end_line -le $_.start_line })
$realRows = @($tRows | Where-Object { -not ($_.heritage.Trim() -eq '' -and $_.end_line -le $_.start_line) })
Check 'PRECONDITION: exactly ONE of those rows is a forward-declaration stub (empty heritage, single line) and ONE is a real declaration' `
  (($stubRows.Count -eq 1) -and ($realRows.Count -eq 1)) `
  ("stub=" + ($stubRows | ForEach-Object { "$($_.start_line)..$($_.end_line)" }) + " real=" + ($realRows | ForEach-Object { "$($_.start_line)..$($_.end_line)" }))
Check 'PRECONDITION: the stub row is the one the fixture declares first, and the real row is the body' `
  (($stubRows.Count -eq 1) -and ($stubRows[0].start_line -eq $stubLine) -and `
   ($realRows.Count -eq 1) -and ($realRows[0].start_line -eq $bodyLine)) `
  ("stubRow=$($stubRows[0].start_line) bodyRow=$($realRows[0].start_line)")

# THE DE-VACUATOR. Get-Rows orders by the tie-breakers ALONE -- exactly the
# ordering that remains once the leading predicate is removed. If the stub were
# not first here, "hover returns the body" would be satisfied by an engine with
# no ordering at all and this file would assert nothing.
Check 'PRECONDITION: the TIE-BREAKERS ALONE (file_id, start_line, id) reach the STUB first -- so the leading predicate is what decides' `
  (($tRows.Count -eq 2) -and ($tRows[0].start_line -eq $stubLine)) `
  ("first=" + $tRows[0].start_line)

$tDef = Get-HoverDefLine 'qrowfix.TThing'
Check 'K29: hover --qname on a forward-declared class answers the REAL declaration, not the stub' `
  ($tDef -eq $bodyLine) ("def_line=$tDef want=$bodyLine stub=$stubLine")

Write-Host ''
Write-Host '=== Shape 2: an overload pair whose abstract member comes first ===' -ForegroundColor Cyan

$absLine  = Line-Of '^\s*function Doubled\(A: Integer\): Integer; overload; virtual; abstract;'
$implLine = Line-Of '^\s*function Doubled: Integer; overload;'
Check 'PRECONDITION: the fixture declares the ABSTRACT overload above the implemented one' `
  (($absLine -gt 0) -and ($implLine -gt $absLine)) "abstract=$absLine implemented=$implLine"

$dRows = Get-Rows 'qrowfix.TThing.Doubled'
Check 'PRECONDITION: the index holds exactly TWO rows for qrowfix.TThing.Doubled' `
  ($dRows.Count -eq 2) ("rows=" + (($dRows | ForEach-Object { "$($_.start_line)/impl=$($_.impl)" }) -join ' '))
$noBody = @($dRows | Where-Object { $_.impl -le 0 })
$hasBody = @($dRows | Where-Object { $_.impl -gt 0 })
Check 'PRECONDITION: exactly ONE of them carries an implementation span and ONE does not' `
  (($noBody.Count -eq 1) -and ($hasBody.Count -eq 1)) `
  ("noBody=" + ($noBody | ForEach-Object { $_.start_line }) + " hasBody=" + ($hasBody | ForEach-Object { $_.start_line }))
Check 'PRECONDITION: the TIE-BREAKERS ALONE reach the BODYLESS row first -- so the impl term is what decides' `
  (($dRows.Count -eq 2) -and ($dRows[0].impl -le 0)) ("first impl=" + $dRows[0].impl)

$dDef = Get-HoverDefLine 'qrowfix.TThing.Doubled'
Check 'K29: hover --qname on an overload pair answers the row that HAS a body' `
  (($hasBody.Count -eq 1) -and ($dDef -eq $hasBody[0].start_line)) `
  ("def_line=$dDef want=" + ($hasBody | ForEach-Object { $_.start_line }))

# ... and the body-first ordering is only useful if the body's facts come with
# it. A row with no impl span mines no return value at all, so this separates
# "the right row" from "a row".
$dRaw = (& $exePath hover --qname 'qrowfix.TThing.Doubled' --db $db --format json 2>$null) -join ''
$dObj = $null
try { $dObj = ($dRaw -replace '\s*FTS5 probe:.*$','') | ConvertFrom-Json } catch {}
Check 'K29: that row brings its body''s facts with it -- the mined return is "FValue * 2"' `
  (($null -ne $dObj) -and (@($dObj.returns).Count -eq 1) -and (@($dObj.returns)[0] -eq 'FValue * 2')) $dRaw

Write-Host ''
Write-Host '=== Control: an ordinary single-row symbol still answers ===' -ForegroundColor Cyan

# Non-vacuity for the whole file: an ORDER BY that returned nothing, or a hover
# that failed on every qname, would satisfy nothing above but must be told apart
# from a working engine all the same.
$hRows = Get-Rows 'qrowfix.THolder'
Check 'PRECONDITION: qrowfix.THolder owns exactly ONE row (no ordering to do)' ($hRows.Count -eq 1) `
  ("rows=" + $hRows.Count)
$hDef = Get-HoverDefLine 'qrowfix.THolder'
Check 'CONTROL: hover --qname still answers a symbol that owns a single row' `
  (($hRows.Count -eq 1) -and ($hDef -eq $hRows[0].start_line)) ("def_line=$hDef want=" + $hRows[0].start_line)

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
