<#
  run_query_case_insensitive.ps1 -- `query --name` / `--qname` match
  case-INSENSITIVELY, `--case-sensitive` restores byte-exact matching, and the
  JSON says which kind of match it is.

  THE BUG (conversion team, INBOX 2.10). `query --name TFDRDBMSDataSet` returned
  `[]` and exit 1 against an index that provably held the symbol -- its real
  declared spelling is `TFDRdbmsDataSet`. Exit 1 ALSO means "no such symbol", so a
  caller who gets the case wrong is handed a confident, indistinguishable "does
  not exist". That is not strictness: **Delphi identifiers are case-insensitive**,
  so an index answering differently for TEdit / tEdit / tedit is answering a
  question the language does not ask.

  THE SECOND HALF, and the one that actually misled a machine consumer. The TEXT
  output has always prefixed a fuzzy result with '(no exact match for "X" -
  closest matches:)'. That banner is printed ONLY when --json is absent, so a JSON
  consumer got a near-miss in the same shape as a hit. The reported symptom was
  'ANotifyEvent' appearing to resolve: the fuzzy fallback is trigram +
  Levenshtein, TNotifyEvent is 13 chars so FuzzyMaxDistanceFor allows 3, and the
  two differ by 1. `match_kind` now says 'exact' or 'fuzzy' on every row.

  WHY THE INDEX CHECK IS HERE. SQLite cannot serve a `COLLATE NOCASE` comparison
  from a BINARY index, so making the lookup insensitive WITHOUT adding
  idx_symbols_name_nocase silently turns every `query --name` into a full scan --
  ~1.5M rows on the shipped library index. Correct, and unusably slow, and no
  behavioural assertion in this file would notice. So the plan is asserted
  directly: a check that reads EXPLAIN QUERY PLAN and fails if the lookup is not
  index-served. It is deliberately NOT a timing check -- a timing threshold on a
  60-symbol fixture would be noise.

  Usage: pwsh -File tests/autotest/run_query_case_insensitive.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-case-insensitive"
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

# A single MIXED-CASE declared name. Mixed on purpose: with an all-lower or
# all-upper name, half the case variants below would coincide with the stored
# spelling and the checks would pass without the collation doing anything.
Write-Ascii (Join-Path $work 'CaseKit.pas') @'
unit CaseKit;

interface

type
  TFDRdbmsDataSet = class(TObject)
  public
    procedure Go;
  end;

implementation

procedure TFDRdbmsDataSet.Go;
begin
end;

end.
'@

$db = Join-Path $WorkDir 'case.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($indexOut -join ' | ')"

# --- probes ------------------------------------------------------------------
$script:PySql = Join-Path $WorkDir 'sql.py'
Write-Ascii $script:PySql @'
import sqlite3, sys
con = sqlite3.connect("file:%s?mode=ro" % sys.argv[1].replace("\\", "/"), uri=True)
print("\n".join("|".join("" if v is None else str(v) for v in r)
                for r in con.execute(sys.argv[2]).fetchall()))
con.close()
'@
function Sql([string]$Q) { return ((python $script:PySql $db $Q) -join "`n").Trim() }

# Rows for one --name spelling, as objects. Returns @() on no match.
function QName([string]$Name, [switch]$CaseSensitive) {
  $a = @('query', '--name', $Name, '--db', $db, '--json')
  if ($CaseSensitive) { $a += '--case-sensitive' }
  $raw = @(& $Exe @a 2>&1) | ForEach-Object { "$_" } | Where-Object { $_ -notmatch 'loaded defaults' }
  $txt = ($raw -join "`n").Trim()
  if (-not $txt.StartsWith('[')) { return @() }
  return @($txt | ConvertFrom-Json)
}
function QQName([string]$Q) {
  $raw = @(& $Exe query --qname $Q --db $db --json 2>&1) | ForEach-Object { "$_" } |
           Where-Object { $_ -notmatch 'loaded defaults' }
  $txt = ($raw -join "`n").Trim()
  if (-not $txt.StartsWith('[')) { return @() }
  return @($txt | ConvertFrom-Json)
}

# --- DE-VACUATOR: the name is stored in exactly ONE spelling ------------------
# Without this, every case-insensitive check below could be passing because the
# index happens to hold several rows in several cases, which would make the
# collation irrelevant and the suite meaningless.
Write-Host ''
Write-Host 'PRECONDITION -- one row, one stored spelling' -ForegroundColor Cyan
$spellings = Sql "SELECT DISTINCT name FROM symbols WHERE name LIKE 'TFDRdbmsDataSet'"
Check 'exactly one stored spelling of the class name' ($spellings -eq 'TFDRdbmsDataSet') "stored='$spellings'"
$rowCount = Sql "SELECT COUNT(*) FROM symbols WHERE name='TFDRdbmsDataSet'"
Check 'exactly one symbols row carries it' ($rowCount -eq '1') "rows=$rowCount"

# --- 1. --name is case-insensitive BY DEFAULT ---------------------------------
Write-Host ''
Write-Host '1 -- --name matches in any case, and returns the SAME row' -ForegroundColor Cyan
$baseline = QName 'TFDRdbmsDataSet'
Check 'the exact spelling finds it' ($baseline.Count -eq 1) "rows=$($baseline.Count)"
$baseId = if ($baseline.Count -eq 1) { $baseline[0].id } else { -1 }

foreach ($variant in 'TFDRDBMSDataSet', 'tfdrdbmsdataset', 'TFDRDBMSDATASET', 'tFdRdBmSdAtAsEt') {
  $rows = QName $variant
  Check "'$variant' finds it" ($rows.Count -eq 1) "rows=$($rows.Count)"
  if ($rows.Count -eq 1) {
    Check "'$variant' returns the SAME row (id $baseId)" ($rows[0].id -eq $baseId) "id=$($rows[0].id)"
    Check "'$variant' is reported as an EXACT match" ($rows[0].match_kind -eq 'exact') "match_kind=$($rows[0].match_kind)"
  }
}

# The reporter's own case, verbatim from INBOX 2.10.
$reported = QName 'TFDRDBMSDataSet'
Check "INBOX 2.10's exact reported query no longer returns []" ($reported.Count -eq 1) "rows=$($reported.Count)"

# --- 2. --qname is case-insensitive too ---------------------------------------
Write-Host ''
Write-Host '2 -- --qname matches in any case' -ForegroundColor Cyan
Check '--qname exact spelling'  ((QQName 'CaseKit.TFDRdbmsDataSet').Count -eq 1)
Check '--qname wrong-case type' ((QQName 'CaseKit.TFDRDBMSDATASET').Count -eq 1)
Check '--qname wrong-case unit' ((QQName 'casekit.TFDRdbmsDataSet').Count -eq 1)

# --- 3. --case-sensitive restores byte-exact matching -------------------------
# A wrong-case spelling must NOT come back as an exact hit. It may still come back
# as a FUZZY suggestion -- that fallback fires whenever the exact lookup finds
# nothing, and it is allowed to -- so the assertion is on match_kind, not on the
# row count. Asserting "0 rows" would be asserting the fallback away.
Write-Host ''
Write-Host '3 -- --case-sensitive is byte-exact' -ForegroundColor Cyan
$csExact = QName 'TFDRdbmsDataSet' -CaseSensitive
Check '--case-sensitive: the exact spelling still matches EXACTLY' `
  (($csExact.Count -eq 1) -and ($csExact[0].match_kind -eq 'exact')) `
  "rows=$($csExact.Count) match_kind=$($csExact[0].match_kind)"

$csWrong = QName 'TFDRDBMSDataSet' -CaseSensitive
$wrongIsExact = ($csWrong.Count -gt 0) -and ($csWrong[0].match_kind -eq 'exact')
Check '--case-sensitive: a wrong-case spelling is NOT an exact match' (-not $wrongIsExact) `
  "rows=$($csWrong.Count) match_kind=$(if ($csWrong.Count) { $csWrong[0].match_kind } else { '<none>' })"

# --- 4. match_kind marks the fuzzy fallback (INBOX 2.10, second half) ---------
Write-Host ''
Write-Host '4 -- the fuzzy fallback is LABELLED in JSON, not just in text' -ForegroundColor Cyan
if ($csWrong.Count -gt 0) {
  Check 'the fuzzy suggestion is labelled match_kind=fuzzy' ($csWrong[0].match_kind -eq 'fuzzy') `
    "match_kind=$($csWrong[0].match_kind)"
  # -cne, NOT -ne. PowerShell's plain -ne is CASE-INSENSITIVE, so it calls
  # 'TFDRdbmsDataSet' and 'TFDRDBMSDataSet' equal -- which would make this check
  # assert the exact opposite of its name, and it did on first run. In a suite
  # about case sensitivity, every string comparison has to be the explicit one.
  Check 'the fuzzy row does NOT carry the requested spelling' ($csWrong[0].name -cne 'TFDRDBMSDataSet') `
    "name=$($csWrong[0].name)"
}
# A name far enough away that even the fuzzy fallback declines -- proves an
# absent symbol still reads as absent, and that check 3 is not passing merely
# because everything returns something.
$absent = QName 'ZzqxwvUnrelated'
Check 'a genuinely absent name returns no rows at all' ($absent.Count -eq 0) "rows=$($absent.Count)"

# --- 5. the NOCASE indexes exist AND are used --------------------------------
# The behavioural checks above pass just as well with a full table scan. This is
# the only thing standing between a correct answer and a 1.5M-row scan per query.
Write-Host ''
Write-Host '5 -- the lookup is INDEX-SERVED, not a full scan' -ForegroundColor Cyan
$idx = Sql "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE '%nocase%' ORDER BY name"
Check 'idx_symbols_name_nocase exists'  ($idx -match 'idx_symbols_name_nocase')  "found: $($idx -replace "`n", ' ')"
Check 'idx_symbols_qname_nocase exists' ($idx -match 'idx_symbols_qname_nocase')

$planName = Sql "EXPLAIN QUERY PLAN SELECT * FROM symbols WHERE name = 'x' COLLATE NOCASE"
Check '--name lookup uses the NOCASE index (no SCAN)' `
  (($planName -match 'idx_symbols_name_nocase') -and ($planName -notmatch 'SCAN symbols')) "$planName"

$planQName = Sql "EXPLAIN QUERY PLAN SELECT * FROM symbols WHERE qualified_name = 'x' COLLATE NOCASE"
Check '--qname lookup uses the NOCASE index (no SCAN)' `
  (($planQName -match 'idx_symbols_qname_nocase') -and ($planQName -notmatch 'SCAN symbols')) "$planQName"

Write-Host ''
if ($script:Failed) { Write-Host 'CASE-INSENSITIVE QUERY: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'CASE-INSENSITIVE QUERY: PASS' -ForegroundColor Green
exit 0
