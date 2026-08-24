<#
  run_doc_p3_wiring.ps1 -- Auto-Document Phase 3, Task 14:
  the wiring fact -- 'Registered as: IFolderService (singleton)' and
  'Dataset: qryFolders -> FOLDERS (ID, NAME)'.

  NO NEW AST ANALYSIS. This fact is a pure JOIN over tables the index already
  carries: di_bindings for the DI half, orm_links -> fb_relations -> fb_columns
  for the dataset half.

  THE FIXTURE SHAPE WAS VERIFIED FIRST, as the plan demands: indexing wiring.pas
  really does produce a di_bindings row
  ('IFolderService', 'TFolderService', 'singleton'). Assertion 1 re-checks that
  on every run, because if the DI extractor ever stops recognising the shape,
  the interesting assertions below would fail for a reason that has nothing to
  do with this fact and the failure message should say so.

  THE DATASET HALF IS TESTED BY SEEDING, and that is only possible because the
  fact is computed at RENDER time. No index in this repo or on this machine has
  a single orm_links row -- ORM3, the SQL DB and the repo's own test DB all read
  zero -- so there was no corpus symbol to assert against, which is the SKIP the
  plan anticipated. Computing at render time (see ComputeWiring's header for why
  that was necessary anyway) turns it into a real test instead: seed one
  orm_links row plus its fb_relations/fb_columns rows straight into the scratch
  DB with python, then run `document` and assert the line. The seeded ids come
  from the freshly-indexed symbols table, so nothing is hardcoded.

  Runs from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
function Skip($n,$why){ Write-Host ("[SKIP] {0} -- {1}" -f $n,$why) -ForegroundColor Yellow }

$exePath = (Resolve-Path $Exe).Path
$fx      = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\wiring.pas')).Path

function Get-FileMd5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash }

function Get-BlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return '' }
  $acc = New-Object System.Collections.Generic.List[string]
  for ($j = $idx - 1; $j -ge 0; $j--) {
    if ($lines[$j] -notmatch '^\s*///') { break }
    $acc.Insert(0, $lines[$j].Trim())
  }
  return [string]::Join("`n", $acc.ToArray())
}

function Get-FactLine([string]$block, [string]$label) {
  foreach ($l in ($block -split "`n")) {
    $t = ($l -replace '^\s*///\s?','' -replace '</?para>','').Trim()
    if ($t -match "^$label`: (.*)$") { return $Matches[1].Trim() }
  }
  return ''
}

Push-Location C:\TEMP
try {

Write-Host ''
Write-Host '=== wiring.pas -- Registered as: / Dataset: ===' -ForegroundColor Cyan

$sc = Join-Path C:\TEMP 'draglint_docp3_wiring'
if (Test-Path $sc) { Remove-Item $sc -Recurse -Force }
New-Item -ItemType Directory -Path $sc | Out-Null
$tgt = Join-Path $sc 'wiring.pas'
$db  = Join-Path $sc 'w.sqlite'
Copy-Item $fx $tgt -Force

& $exePath index $sc --db $db 2>$null | Out-Null
Check 'index exits 0' ($LASTEXITCODE -eq 0)

# --- (1) the precondition the whole suite rests on. -------------------------
$diRow = ((python -c @"
import sqlite3
c = sqlite3.connect(r'$db')
r = c.execute('SELECT interface_name, impl_name, lifetime FROM di_bindings').fetchall()
print('|'.join(r[0]) if r else '<none>')
"@ 2>&1) -join ' ').Trim()
Check '1. PRECONDITION: the DI extractor produced a di_bindings row for the fixture shape' `
  ($diRow -eq 'IFolderService|TFolderService|singleton') "got=[$diRow]"

& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
Check 'apply exits 0' ($LASTEXITCODE -eq 0)
$md5Cycle1 = Get-FileMd5 $tgt
& $exePath index $sc --db $db 2>$null | Out-Null

$lines  = [IO.File]::ReadAllLines($tgt)
$blkSvc = Get-BlockAbove $lines '^\s*TFolderService = class\(TInterfacedObject, IFolderService\)'
$blkUnr = Get-BlockAbove $lines '^\s*TUnregistered = class$'

# --- (2) the registered class names its interface and lifetime. -------------
Check '2. de-vacuator: TFolderService got a doc block' ($blkSvc -ne '') ''
Check '2. TFolderService renders "Registered as: IFolderService (singleton)"' `
  ((Get-FactLine $blkSvc 'Registered as') -eq 'IFolderService (singleton)') `
  ("block=" + ($blkSvc -replace "`n",' | '))

# --- (3) a class with no binding gets no line. ------------------------------
Check '3. TUnregistered has NO "Registered as:" line' `
  ((Get-FactLine $blkUnr 'Registered as') -eq '') ("block=" + ($blkUnr -replace "`n",' | '))

# --- (4) idempotency. -------------------------------------------------------
& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
Check '4. a second apply after a reindex is byte-identical' `
  ((Get-FileMd5 $tgt) -eq $md5Cycle1) ("c1=$md5Cycle1 c2=" + (Get-FileMd5 $tgt))

# ===========================================================================
# (5) THE DATASET HALF -- seeded, because no corpus has orm_links rows.
# ===========================================================================
$seeded = ((python -c @"
import sqlite3, time
c = sqlite3.connect(r'$db')
row = c.execute("SELECT id FROM symbols WHERE name = 'TFolderService' AND kind = 'class'").fetchone()
if not row:
    print('<no-symbol>')
else:
    sid = row[0]
    now = int(time.time())
    # NO symbols ROW IS INSERTED for the SQL side. orm_links joins fb_relations
    # on sql_table_symbol_id, so the two only have to agree on ONE id -- the id
    # does not have to resolve to anything. The first version of this seed did
    # insert a stand-in symbol with kind='table' and it broke the engine
    # outright ('FATAL: Exception: Unknown symbol kind: "table"'), which the
    # batch path then swallowed into a silently unchanged doc block. A test
    # fixture must not teach the store a kind the store cannot read back.
    sqlsid = 999000001
    c.execute('INSERT INTO fb_relations(name, sql_table_symbol_id, owner, system_flag, description, snapshot_at) '
              "VALUES ('FOLDERS', ?, NULL, 0, NULL, ?)", (sqlsid, now))
    relid = c.execute('SELECT last_insert_rowid()').fetchone()[0]
    for i, col in enumerate(['ID', 'NAME', 'PARENT_ID']):
        c.execute('INSERT INTO fb_columns(relation_id, name, position, nullable, snapshot_at) VALUES (?, ?, ?, 1, ?)', (relid, col, i, now))
    c.execute('INSERT INTO orm_links(delphi_symbol_id, delphi_db_index, sql_symbol_id, sql_db_index, confidence, link_kind, evidence, computed_at) '
              "VALUES (?, 0, ?, 0, 100, 'table', 'seeded by run_doc_p3_wiring', ?)", (sid, sqlsid, now))
    c.commit()
    print('ok')
"@ 2>&1) -join ' ').Trim()

if ($seeded -ne 'ok') {
  Skip '5. Dataset: half' "could not seed orm_links/fb_relations/fb_columns into the scratch DB (python said: $seeded). The assertion is NOT silently dropped -- it did not run."
} else {
  # Just re-apply: the repair path regenerates the managed block in place, and
  # the fact is computed at RENDER time, so the seeded rows are visible
  # immediately with NO reindex. Both of those matter here --
  #   * a reindex would re-insert the Delphi symbols under NEW ids and orphan
  #     the seeded orm_links row (its delphi_symbol_id has no FK), and
  #   * a --strip first would shift every line in the file while the index still
  #     held the old numbers, so the following apply would resolve declarations
  #     to the wrong lines and write nothing. (Observed, not assumed: the first
  #     version of this block did exactly that and produced an empty doc block.)
  & $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
  $blkSvc2 = Get-BlockAbove ([IO.File]::ReadAllLines($tgt)) '^\s*TFolderService = class\(TInterfacedObject, IFolderService\)'
  $ds = Get-FactLine $blkSvc2 'Dataset'
  Check '5. TFolderService renders a "Dataset:" line from the seeded orm_links row' `
    ($ds -ne '') ("block=" + ($blkSvc2 -replace "`n",' | '))
  # '-&gt;', not '->': the arrow is XML-ESCAPED in the emitted block, as every
  # fact line's content is (EscXml). Asserting the raw '->' would be asserting
  # that the engine emits ill-formed DocInsight, so the escaped form is the
  # correct expectation and is pinned here deliberately.
  Check '5. it names the relation and its leading columns, in position order' `
    ($ds -match 'TFolderService -&gt; FOLDERS \(ID, NAME, PARENT_ID\)') "got=[$ds]"
  Check '5. the DI half is still rendered alongside it' `
    ((Get-FactLine $blkSvc2 'Registered as') -eq 'IFolderService (singleton)') `
    ("block=" + ($blkSvc2 -replace "`n",' | '))
}

# --- ENCODING. --------------------------------------------------------------
$bytes = [IO.File]::ReadAllBytes($tgt)
Check 'ENCODING: the applied file is strict 7-bit ASCII' `
  (@($bytes | Where-Object { $_ -ge 128 }).Count -eq 0) ''
Check 'ENCODING: the applied file has no bare LF (CRLF throughout)' `
  (([regex]::Matches([IO.File]::ReadAllText($tgt), "(?<!`r)`n")).Count -eq 0) ''

}
finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
