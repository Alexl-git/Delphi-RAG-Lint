<#
  run_file_facts_v25_tables.ps1 -- wave 151 lane ST: the two additive file-fact
  tables dfm_properties and comment_facts (spec
  docs\superpowers\specs\2026-11-11-dfm-props-and-comment-facts.md).

  Indexes tests\fixtures\file-facts-149\facts (Pascal units + text .dfm files)
  into a scratch DB and checks, through `sql --json` (rows are POSITIONAL arrays;
  mapped onto columns[].name below):
    T1  both tables exist after a fresh index (Migrate created them).
    T2  their columns are exactly the spec's, in order (PRAGMA table_info).
    T3  their indexes exist (file_id lead + the anchor FK child index).
    T4  a SECOND index run over a touched file (PutFileFacts delete + insert on
        the tables) ends with exit 0 and the files are still all there.
    T5  anchor_symbol_id is ON DELETE SET NULL to symbols, file_id CASCADE.
    -ExpectEmpty  (the ST stub producers) both tables hold 0 rows; without the
        switch the row counts are only printed (Y2 / W1 fill them).
  Positive control: run with -Exe <the 1.49.0-alpha base engine> -- T1-T5 FAIL
  (no tables).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$ExpectEmpty)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_file_facts_v25_tables: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_file_facts_v25_tables: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fxSrc = Join-Path $repo 'tests\fixtures\file-facts-149\facts'
$work  = Join-Path $env:TEMP ('dl-file-facts-v25-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null
$fx = Join-Path $work 'facts'
Copy-Item -Recurse $fxSrc $fx
$db = Join-Path $work 'facts.sqlite'

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}

# One SELECT -> array of PSCustomObject (columns by name). A failed query
# (e.g. no such table on an older engine) returns an EMPTY array.
function Lane-Sql([string]$Db, [string]$Query) {
  $raw = & $Exe sql --query $Query --db $Db --json 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $raw) { return }
  try { $j = ($raw -join "`n") | ConvertFrom-Json } catch { return }
  $cols = @($j.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($r in @($j.rows)) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $r[$i] }
    $out.Add([pscustomobject]$o)
  }
  return $out.ToArray()
}

Write-Host "run_file_facts_v25_tables: engine $Exe" -ForegroundColor Cyan
& $Exe index $fx --db $db *> (Join-Path $work 'index-1.log')
$rc1 = $LASTEXITCODE
$files1 = @(Lane-Sql $db "SELECT COUNT(*) AS n FROM files")
Check 'VACUITY the fixture was indexed' (($rc1 -eq 0) -and ($files1.Count -eq 1) -and ($files1[0].n -ge 5)) "(rc $rc1, files $(if ($files1.Count) { $files1[0].n } else { '?' }))"

# ---- T1 ---------------------------------------------------------------------
$tabs = @(Lane-Sql $db "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('dfm_properties', 'comment_facts') ORDER BY name")
Check 'T1 dfm_properties and comment_facts exist' ((($tabs | ForEach-Object name) -join ',') -eq 'comment_facts,dfm_properties') "($(($tabs | ForEach-Object name) -join ','))"

# ---- T2 ---------------------------------------------------------------------
$want = @{
  'dfm_properties' = 'file_id,ordinal,object_ordinal,parent,depth,name,value_text,value_kind,start_line,start_col,end_line,end_col'
  'comment_facts'  = 'file_id,ordinal,start_offset,end_offset,line,col,end_line,kind,text,anchor_kind,anchor_symbol_id'
}
foreach ($t in 'dfm_properties', 'comment_facts') {
  # `sql` refuses PRAGMA: an empty SELECT * still reports the column list, in order.
  $raw  = & $Exe sql --query "SELECT * FROM $t LIMIT 0" --db $db --json 2>$null
  $got  = ''
  try { $got = (@((($raw -join "`n") | ConvertFrom-Json).columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })) -join ',' } catch { }
  Check "T2 $t columns match the spec" ($got -eq $want[$t]) "($got)"
}

# ---- T3 ---------------------------------------------------------------------
$idx = @(Lane-Sql $db "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name IN ('dfm_properties', 'comment_facts') ORDER BY name")
$idxText = ($idx | ForEach-Object name) -join ','
Check 'T3 the five indexes exist' ($idxText -eq 'idx_comment_facts_anchor,idx_comment_facts_file,idx_dfm_properties_file,idx_dfm_properties_name,idx_dfm_properties_object') "($idxText)"

# ---- T5 ---------------------------------------------------------------------
# `sql` refuses PRAGMA foreign_key_list: read the stored CREATE text instead.
$ddl = @(Lane-Sql $db "SELECT name, sql FROM sqlite_master WHERE type = 'table' AND name IN ('dfm_properties', 'comment_facts') ORDER BY name")
$ddlText = ($ddl | ForEach-Object { "$($_.name)=$($_.sql -replace '\s+', ' ')" }) -join ' | '
Check 'T5 comment_facts: file_id CASCADE, anchor_symbol_id SET NULL' `
  (($ddlText -match 'comment_facts=.*file_id INTEGER NOT NULL REFERENCES files\(id\) ON DELETE CASCADE') -and
   ($ddlText -match 'comment_facts=.*anchor_symbol_id INTEGER REFERENCES symbols\(id\) ON DELETE SET NULL')) "($ddlText)"
Check 'T5 dfm_properties: file_id CASCADE' ($ddlText -match 'dfm_properties=.*file_id INTEGER NOT NULL REFERENCES files\(id\) ON DELETE CASCADE') ''

# ---- T4 ---------------------------------------------------------------------
$touch = Get-ChildItem $fx -Recurse -Include *.pas, *.dfm | Select-Object -First 3
foreach ($f in $touch) { [IO.File]::SetLastWriteTime($f.FullName, (Get-Date)); [IO.File]::AppendAllText($f.FullName, "`r`n") }
& $Exe index $fx --db $db *> (Join-Path $work 'index-2.log')
$rc2 = $LASTEXITCODE
$files2 = @(Lane-Sql $db "SELECT COUNT(*) AS n FROM files")
$log2 = Get-Content (Join-Path $work 'index-2.log') -Raw
Check 'T4 re-index of touched files exits 0, no exception, same file count' (($rc2 -eq 0) -and ($files2.Count -eq 1) -and ($files2[0].n -eq $files1[0].n) -and ($log2 -notmatch '(?im)no such table|access violation|^\s*ERROR\b')) "(rc $rc2, files $(if ($files2.Count) { $files2[0].n } else { '?' }))"

# ---- rows ---------------------------------------------------------------------
foreach ($t in 'dfm_properties', 'comment_facts') {
  $n = @(Lane-Sql $db "SELECT COUNT(*) AS n FROM $t")
  $cnt = if ($n.Count) { $n[0].n } else { 'no table' }
  if ($ExpectEmpty) { Check "STUB $t holds 0 rows" (($n.Count -eq 1) -and ($n[0].n -eq 0)) "($cnt)" }
  else { Write-Host "  INFO  $t rows: $cnt" }
}

try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "  (scratch $work left: $($_.Exception.Message))" }
Write-Host ("run_file_facts_v25_tables: {0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $(if ($script:fail) { 1 } else { 0 })
