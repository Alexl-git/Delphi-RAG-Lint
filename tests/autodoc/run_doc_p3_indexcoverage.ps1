<#
  run_doc_p3_indexcoverage.ps1 -- Auto-Document Phase 3, Task 3c: index
  doc-tag coverage. TParsedDoc.HasContent's OR-chain omits ExampleText/
  SeeAlso/SinceText, and DRagLint.Core.Indexer.pas only calls
  FStore.UpsertSymbolDoc when HasContent is True -- so a comment whose ONLY
  tag is <example>, <seealso cref>, or <since> produces NO symbol_docs row
  at all. The symbol then reads as entirely undocumented to the index,
  `context` bundles, MCP, and LSP hover/completion, even though the author
  wrote real documentation. <example> has 0 rows in this repo's own index
  before this fix (see docs\lint\URGENT-TODO-2026-07-26-index-doc-tag-
  coverage.md).

  Fixture fixtures\docp3\indexcoverage.pas: one symbol per affected shape,
  each carrying EXACTLY ONE of the three tags and nothing else (no summary,
  no returns tag, no params, no exception, not deprecated -- every OTHER
  HasContent disjunct stays False), plus a NoCommentControl with no doc
  comment at all.

  Asserts, after `index` (queried via Python stdlib sqlite3, read-only
  ?mode=ro -- no sqlite3 on PATH in this environment):
    1. A symbol_docs row EXISTS for each of ExampleOnlySymbol/
       SeeAlsoOnlySymbol/SinceOnlySymbol, with the tag's own column
       populated (example_text/seealso_json/since_text respectively).
    2. NO symbol_docs row exists for NoCommentControl -- proves "a row
       exists" is not vacuously true for every symbol regardless of
       content; a regression that made the indexer write a row
       unconditionally would still pass check 1 but would be caught here.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Py  = 'C:\Python314\python.exe'
)

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

if (-not (Test-Path $Py)) {
  Write-Host "[FAIL] python not found at $Py (needed to read symbol_docs directly)" -ForegroundColor Red
  exit 1
}

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\indexcoverage.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp3indexcoverage'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'indexcoverage.pas'
$db     = Join-Path $scratch 'indexcoverage.sqlite'
Copy-Item $fixture $target -Force

# query.py <db> <name> -> SYMFOUND=0|1  HASROW=0|1  EXAMPLE=...  SEEALSO=...  SINCE=...
# HASROW is "does a symbol_docs row exist for this symbol_id at all" (fetchone()
# None-vs-not), independent of which column the row's content lives in -- so a
# future row whose three tag columns all happened to be empty would still read
# HASROW=1 correctly (not conflated with "no row"), and the three positive
# checks below additionally require the tag's OWN text to be populated.
$queryPy = @'
import sqlite3, sys
db, name = sys.argv[1], sys.argv[2]
con = sqlite3.connect("file:{}?mode=ro".format(db.replace(chr(92), "/")), uri=True)
cur = con.cursor()
srow = cur.execute("SELECT id FROM symbols WHERE name = ?", (name,)).fetchone()
if srow is None:
    print("SYMFOUND=0")
    sys.exit(0)
print("SYMFOUND=1")
drow = cur.execute(
    "SELECT example_text, seealso_json, since_text FROM symbol_docs WHERE symbol_id = ?",
    (srow[0],)).fetchone()
if drow is None:
    print("HASROW=0")
    print("EXAMPLE=")
    print("SEEALSO=")
    print("SINCE=")
else:
    print("HASROW=1")
    example, seealso, since = drow
    print("EXAMPLE={}".format(example if example else ""))
    print("SEEALSO={}".format(seealso if seealso else ""))
    print("SINCE={}".format(since if since else ""))
'@
$queryPyPath = Join-Path $scratch 'query.py'
[System.IO.File]::WriteAllText($queryPyPath, $queryPy, [System.Text.Encoding]::ASCII)

function Get-Row([string]$name) {
  $out = & $Py $queryPyPath $db $name 2>$null
  $h = @{}
  foreach ($ln in $out) {
    $m = [regex]::Match($ln, '^(\w+)=(.*)$')
    if ($m.Success) { $h[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  return $h
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  $ex = Get-Row 'ExampleOnlySymbol'
  Check 'ExampleOnlySymbol: symbol found'          ($ex.SYMFOUND -eq '1')
  Check 'ExampleOnlySymbol: symbol_docs row EXISTS' ($ex.HASROW -eq '1') '(the Task 3c gap -- FAILS before the HasContent fix)'
  Check 'ExampleOnlySymbol: example_text populated' ($ex.EXAMPLE -match [regex]::Escape("WriteLn('example only');")) $ex.EXAMPLE

  $sa = Get-Row 'SeeAlsoOnlySymbol'
  Check 'SeeAlsoOnlySymbol: symbol found'          ($sa.SYMFOUND -eq '1')
  Check 'SeeAlsoOnlySymbol: symbol_docs row EXISTS' ($sa.HASROW -eq '1') '(the Task 3c gap -- FAILS before the HasContent fix)'
  Check 'SeeAlsoOnlySymbol: seealso_json populated' ($sa.SEEALSO -match [regex]::Escape('Other.RelatedThing')) $sa.SEEALSO

  $si = Get-Row 'SinceOnlySymbol'
  Check 'SinceOnlySymbol: symbol found'            ($si.SYMFOUND -eq '1')
  Check 'SinceOnlySymbol: symbol_docs row EXISTS'  ($si.HASROW -eq '1') '(the Task 3c gap -- FAILS before the HasContent fix)'
  Check 'SinceOnlySymbol: since_text populated'    ($si.SINCE -match [regex]::Escape('1.0')) $si.SINCE

  $nc = Get-Row 'NoCommentControl'
  Check 'NoCommentControl: symbol found'                 ($nc.SYMFOUND -eq '1')
  Check 'NoCommentControl: NO symbol_docs row (control)' ($nc.HASROW -eq '0')
} finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
