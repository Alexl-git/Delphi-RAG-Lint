<#
  run_generic_typeref_refs.ps1 -- generic type instantiations must emit refs.

  DEFECT (session 40, filed as docs\INBOX-generic-type-instantiation-emits-no-ref.md):
  `TList<T>` / `TDictionary<K,V>` emitted NO ref of any kind -- not for the base
  type name, not for the type arguments in a DECLARATION, and a construction
  site `TList<T>.Create` also lost its `Create` member-access. Measured: 3,878
  generic instantiation sites in drag-lint's own src\ produced 16 refs, and no
  ref anywhere in the index carried a '<' (so the name was not merely mangled).

  ROOT CAUSE, taken from the real tree-sitter tree, NOT from the source comment
  at EmitTypeUseReference -- which guessed the shape and guessed it wrong:

    declaration: (typeref (typerefTpl entity: (identifier)
                                      (kLt) args: (typerefArgs (identifier) ...) (kGt)))
    expression:  (exprDot lhs: (exprTpl entity: (identifier)
                                        (kLt) args: (typeref (identifier)) (kGt))
                          operator: (kDot) rhs: (identifier))

  1. EmitTypeUseReference knew only 'identifier' and 'genericDot' and fell to
     its `else Exit`, abandoning the WHOLE typeref -- which is why a generic
     declaration emitted nothing at all, not even its arguments.
  2. Walk's exprDot case gates every emission on lhs.NodeType = 'identifier',
     so an exprTpl lhs dropped both the receiver read and the member-access.

  THE CRITICAL GATE (over-capture guard): `TBox<T> = class` DECLARES a type
  parameter. That is a different node family -- genericTpl / genericArgs /
  genericArg -- and must stay untouched. If a fix reaches it, every generic
  class in the corpus starts emitting a bogus type_use for 'T'. Assertions (C)
  target exactly that risk.

  THE POSITIVE CONTROL is load-bearing, not decoration: TStringList exercises
  the identical three shapes WITHOUT type arguments and passes today. Without
  it, a guard that only asserted "the generic rows exist" would also pass
  against a build whose extractor emitted rows for everything.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-generic-typeref by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-generic-typeref"
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

$UBody = @'
unit u;

interface

uses
  System.Generics.Collections, System.Classes;

type
  TBox<T> = class
  private
    FMap: TDictionary<string, Boolean>;
  public
    procedure Go;
  end;

procedure Q;

implementation

procedure TBox<T>.Go;
begin
end;

procedure Q;
var
  L: TList<Integer>;
  P: TStringList;
begin
  L := TList<Integer>.Create;
  P := TStringList.Create;
  L.Free;
  P.Free;
end;

end.
'@

Write-Ascii (Join-Path $work 'u.pas') $UBody

$db = Join-Path $WorkDir 'genrefs.sqlite'

Write-Host 'Indexing fixture (deep usage refs on by default for a project index)' -ForegroundColor Cyan
$indexOut  = & $Exe index $work --db $db 2>&1
$indexExit = $LASTEXITCODE
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut -join ' | ')"

$py = Join-Path $WorkDir 'refquery.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
cur = c.execute(
    "SELECT name_text, kind, start_line, COALESCE(receiver_text,'') AS receiver_text "
    "FROM refs WHERE name_text = ? AND kind = ? ORDER BY start_line",
    (sys.argv[2], sys.argv[3])
)
cols = [d[0] for d in cur.description]
print(json.dumps([dict(zip(cols, r)) for r in cur.fetchall()]))
c.close()
'@ | Set-Content $py -Encoding ascii

function Get-Refs([string]$Name, [string]$Kind) {
  $raw = (python $py $db $Name $Kind) -join "`n"
  return @($raw | ConvertFrom-Json)
}

# 1-based line number of the fixture line matching $Pattern. Assertions below
# anchor on this rather than a hard-coded number so editing the fixture cannot
# quietly move an assertion onto a different construct.
$script:FixtureLines = $UBody -split "`r`n|`n"
function Line-Of([string]$Pattern) {
  for ($i = 0; $i -lt $script:FixtureLines.Count; $i++) {
    if ($script:FixtureLines[$i] -match $Pattern) { return $i + 1 }
  }
  return -1
}

# ---------------------------------------------------------------- (A) CONTROL
# The non-generic form of all three shapes. These pass BEFORE the fix; if any
# of them is red the assertions themselves are broken and nothing below means
# anything.
Write-Host ''
Write-Host '(A) POSITIVE CONTROL -- non-generic TStringList (passes before the fix)' -ForegroundColor Cyan
$c1 = Get-Refs 'TStringList' 'type_use'
Check 'control: type_use TStringList at its declaration' ($c1.Count -ge 1) ("rows=" + ($c1 | ConvertTo-Json -Compress))
$c2 = Get-Refs 'TStringList' 'read'
Check 'control: read TStringList at the construction site' ($c2.Count -ge 1) ("rows=" + ($c2 | ConvertTo-Json -Compress))
$c3 = @((Get-Refs 'Create' 'member-access') | Where-Object { $_.receiver_text -eq 'TStringList' })
Check 'control: member-access Create with receiver_text=TStringList' ($c3.Count -ge 1) ("rows=" + ($c3 | ConvertTo-Json -Compress))

# --------------------------------------------------------------- (B) THE FIX
Write-Host ''
Write-Host '(B) generic instantiations emit the SAME refs as the non-generic control' -ForegroundColor Cyan
$g1 = Get-Refs 'TDictionary' 'type_use'
Check 'field decl FMap: TDictionary<string, Boolean> emits type_use TDictionary' ($g1.Count -ge 1) ("rows=" + ($g1 | ConvertTo-Json -Compress))
$g2 = Get-Refs 'TList' 'type_use'
Check 'local decl L: TList<Integer> emits type_use TList' ($g2.Count -ge 1) ("rows=" + ($g2 | ConvertTo-Json -Compress))
$g3 = Get-Refs 'TList' 'read'
Check 'construction TList<Integer>.Create emits read TList' ($g3.Count -ge 1) ("rows=" + ($g3 | ConvertTo-Json -Compress))
# receiver_text is the LITERAL receiver EXPRESSION -- for `L.Free` it stores the
# variable `L`, so for `TList<Integer>.Create` it correctly stores the whole
# 'TList<Integer>'. Do NOT "fix" this to an equality against 'TList' by
# truncating receiver_text at write time: that would make one column mean two
# different things depending on whether the receiver happened to be generic.
# Stripping the type arguments is the CONSUMER's job (see DoQueryTypeUsage), and
# assertion (D) below is what proves the consumer does it.
$g4 = @((Get-Refs 'Create' 'member-access') | Where-Object { $_.receiver_text -match '^TList\b' })
Check 'construction emits member-access Create whose receiver_text names TList' ($g4.Count -ge 1) ("rows=" + ($g4 | ConvertTo-Json -Compress))
Check 'that receiver_text keeps its type arguments verbatim' (($g4.Count -ge 1) -and ($g4[0].receiver_text -eq 'TList<Integer>')) ("rows=" + ($g4 | ConvertTo-Json -Compress))

Write-Host ''
Write-Host '(B2) type ARGUMENTS of a DECLARATION are emitted too' -ForegroundColor Cyan
# These MUST be anchored to the declaration line. In the EXPRESSION form the
# arguments already arrive as plain `typeref` children and were emitted before
# the fix -- so an unanchored "is there an Integer type_use anywhere" assertion
# passes against the broken build off the construction site alone. That is the
# exact shape of a test that proves nothing.
$declFieldLine = Line-Of 'FMap:\s+TDictionary'
$declLocalLine = Line-Of 'L:\s+TList'
Check 'fixture line lookup resolved' (($declFieldLine -gt 0) -and ($declLocalLine -gt 0)) "field=$declFieldLine local=$declLocalLine"

$a1 = @((Get-Refs 'Boolean' 'type_use') | Where-Object { $_.start_line -eq $declFieldLine })
Check "TDictionary<string, Boolean> emits type_use Boolean ON THE DECLARATION LINE ($declFieldLine)" ($a1.Count -ge 1) ("rows=" + ($a1 | ConvertTo-Json -Compress))
$a2 = @((Get-Refs 'Integer' 'type_use') | Where-Object { $_.start_line -eq $declLocalLine })
Check "TList<Integer> emits type_use Integer ON THE DECLARATION LINE ($declLocalLine)" ($a2.Count -ge 1) ("rows=" + ($a2 | ConvertTo-Json -Compress))

# ------------------------------------------------ (C) OVER-CAPTURE NEGATIVES
Write-Host ''
Write-Host '(C) NEGATIVE -- a type PARAMETER declaration is not a type USE' -ForegroundColor Cyan
$n1 = Get-Refs 'T' 'type_use'
Check 'TBox<T> = class emits ZERO type_use rows for T' ($n1.Count -eq 0) ("rows=" + ($n1 | ConvertTo-Json -Compress))
$n2 = Get-Refs 'T' 'read'
Check 'TBox<T> = class emits ZERO read rows for T' ($n2.Count -eq 0) ("rows=" + ($n2 | ConvertTo-Json -Compress))
$n3 = @((Get-Refs 'TBox' 'type_use') | Where-Object { $_.start_line -le 9 })
Check 'the TBox declaration name is not itself a type_use' ($n3.Count -eq 0) ("rows=" + ($n3 | ConvertTo-Json -Compress))

# --------------------------------------------- (D) CONSUMER-FACING SURFACES
Write-Host ''
Write-Host '(D) the consumer surfaces see it, not just the refs table' -ForegroundColor Cyan
Push-Location $WorkDir
try {
  $tuRaw  = (& $Exe query type-usage --in (Join-Path $work 'u.pas') --names 'TList,TDictionary,TStringList' --db $db --json) -join "`n"
  $tuExit = $LASTEXITCODE
} finally {
  Pop-Location
}
Check 'query type-usage exits 0' ($tuExit -eq 0) "exit=$tuExit"
# NOT a substring match on the raw JSON: the verb echoes every requested name
# back with "referenced": false, so `-match 'TList'` is satisfied by the broken
# build's own negative answer. Assert the FLAG.
$tu = $null
try { $tu = $tuRaw | ConvertFrom-Json } catch { }
Check 'query type-usage --json parses' ($null -ne $tu) "raw=$tuRaw"
if ($null -ne $tu) {
  foreach ($n in @('TStringList', 'TList', 'TDictionary')) {
    $row = @($tu | Where-Object { $_.name -eq $n })
    Check "query type-usage reports $n as referenced=true" (($row.Count -eq 1) -and ($row[0].referenced -eq $true)) ("row=" + ($row | ConvertTo-Json -Compress))
  }
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
