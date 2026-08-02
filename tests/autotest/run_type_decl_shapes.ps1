<#
  run_type_decl_shapes.ps1 -- EVERY named type declaration produces a row.

  THE BUG. TryWalkAlias accepts only a direct `typeref` target, and its comment
  said other shapes were "handled by the earlier TryWalk* dispatch (or left
  unemitted)". The parenthesis was doing the real work: measured on the fixture
  below, FOUR shapes produced NO declaration row at all --

      TAliasStr = string;              plain alias, KEYWORD target
      TRange    = 1..10;               subrange
      TArr      = array[0..3] of Byte;
      TSetOf    = set of Byte;

  -- so `query --name TRange` answered "does not exist" about a type declared in
  the file it had just indexed. Same false-negative class as INBOX 2.10: a
  confident, indistinguishable "no such symbol".

  THE ASYMMETRY THAT FOUND IT, and it is the sharpest check here:
  `TStrongStr = type string` WAS indexed while `TAliasStr = string` was NOT --
  identical target, differing only by the `type` keyword. INBOX 2.11 closed the
  strong form because that was the shape the conversion team reported; nobody
  measured the plain one. This suite pins BOTH so the pair cannot drift again.

  WHY A TOTAL COUNT IS ASSERTED, not just per-name lookups. A per-name check
  proves the names it names. The count proves nothing was dropped that this
  suite forgot to list -- it is what turns "the four I know about" into "all of
  them". It is derived from the fixture (declarations + enum values + the unit
  symbol), so editing the fixture without editing the count fails loudly rather
  than silently weakening the suite.

  Usage: pwsh -File tests/autotest/run_type_decl_shapes.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-type-decl-shapes"
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

Write-Ascii (Join-Path $work 'ShapeKit.pas') @'
unit ShapeKit;

interface

type
  TAliasIdent   = Integer;
  TAliasStr     = string;
  TAliasBool    = Boolean;
  TAliasPointer = Pointer;
  TStrongStr    = type string;
  TStrongInt    = type Integer;
  TRange        = 1..10;
  TEnum         = (eA, eB);
  TArr          = array[0..3] of Byte;
  TSetOf        = set of Byte;

implementation

end.
'@

$db = Join-Path $WorkDir 'shapes.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($indexOut -join ' | ')"

function Row([string]$Name) {
  $raw = @(& $Exe query --name $Name --db $db --json 2>&1) | ForEach-Object { "$_" } |
           Where-Object { $_ -notmatch 'loaded defaults' }
  $txt = ($raw -join "`n").Trim()
  if (-not $txt.StartsWith('[')) { return $null }
  # -ceq: the row must carry the spelling asked for. match_kind guards against the
  # FUZZY fallback answering for a name that does not exist -- without it, a
  # deleted declaration still "passes" via its nearest neighbour.
  $hit = @(@($txt | ConvertFrom-Json) | Where-Object { ($_.name -ceq $Name) -and ($_.match_kind -eq 'exact') })
  if ($hit.Count -eq 0) { return $null }
  return $hit[0]
}

# name -> the target text expected in `signature`. $null = present, text not asserted
# (an enum's members are its payload; it carries no target).
$expected = [ordered]@{
  'TAliasIdent'   = 'Integer'
  'TAliasStr'     = 'string'
  'TAliasBool'    = 'Boolean'
  'TAliasPointer' = 'Pointer'
  'TStrongStr'    = 'string'
  'TStrongInt'    = 'Integer'
  'TRange'        = '1..10'
  'TEnum'         = $null
  'TArr'          = 'array[0..3] of Byte'
  'TSetOf'        = 'set of Byte'
}

Write-Host ''
Write-Host 'every declared type produces a row' -ForegroundColor Cyan
foreach ($name in $expected.Keys) {
  $r = Row $name
  Check "$name is indexed" ($null -ne $r)
  if (($null -ne $r) -and ($null -ne $expected[$name])) {
    Check "$name carries its target text" ($r.signature -ceq $expected[$name]) `
      "signature='$($r.signature)' expected='$($expected[$name])'"
  }
}

# --- the regression that started this ----------------------------------------
Write-Host ''
Write-Host 'the plain/strong pair -- neither may index without the other' -ForegroundColor Cyan
$plain  = Row 'TAliasStr'
$strong = Row 'TStrongStr'
Check 'BOTH `= string` and `= type string` index' (($null -ne $plain) -and ($null -ne $strong)) `
  "plain=$($null -ne $plain) strong=$($null -ne $strong)"
if (($null -ne $plain) -and ($null -ne $strong)) {
  Check 'both resolve to the same target text' ($plain.signature -ceq $strong.signature) `
    "plain='$($plain.signature)' strong='$($strong.signature)'"
}

# --- nothing was dropped that this suite forgot to name -----------------------
Write-Host ''
Write-Host 'total count -- catches a shape this suite does not list' -ForegroundColor Cyan
$script:PySql = Join-Path $WorkDir 'sql.py'
Write-Ascii $script:PySql @'
import sqlite3, sys
con = sqlite3.connect("file:%s?mode=ro" % sys.argv[1].replace("\\", "/"), uri=True)
print("\n".join("|".join("" if v is None else str(v) for v in r)
                for r in con.execute(sys.argv[2]).fetchall()))
con.close()
'@
function Sql([string]$Q) { return ((python $script:PySql $db $Q) -join "`n").Trim() }

# 10 declarations, of which TEnum contributes 2 enum-value symbols, + 1 unit = 13.
$total = Sql "SELECT COUNT(*) FROM symbols"
Check 'the fixture indexes exactly 13 symbols' ($total -eq '13') `
  "got $total (10 type decls + 2 enum values + 1 unit; was 9 before the fix)"

# 9 of the 10 are skTypeAlias. TEnum is NOT: an enum gets its own kind='enum'
# (and its members kind='enum_value'), because it is a type with a payload rather
# than a name for another type. Asserted as 9-and-1 rather than 10, so that a
# future change collapsing enums into the alias kind fails here and has to be
# looked at, instead of passing under a laxer count.
$typeRows = Sql "SELECT COUNT(*) FROM symbols WHERE kind='type'"
Check '9 declarations carry kind=type' ($typeRows -eq '9') "got $typeRows"
$enumRows = Sql "SELECT COUNT(*) FROM symbols WHERE kind='enum'"
Check 'TEnum keeps its own kind=enum' ($enumRows -eq '1') "got $enumRows"

Write-Host ''
if ($script:Failed) { Write-Host 'TYPE DECL SHAPES: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'TYPE DECL SHAPES: PASS' -ForegroundColor Green
exit 0
