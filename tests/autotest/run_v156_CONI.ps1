#Requires -Version 7.3
<#
  run_v156_CONI.ps1 -- 1.56 lane CON-I: `index --project` copies the configured field repository into the project
  index (repo_copy, concept_fields, concept_texts) and derives the project's own caption texts and field links
  (concept_texts place = project, concept_links). Design: 2026-11-27-three-place-search-caption-concepts-design.md,
  part 2 (CC-1, CC-6); the query side (`query --concept`) is lane CON-Q's runner.

  Fixture tests\fixtures\v156\CONCEPT\app (copied to a temp folder; the repository is built with `repo restore`).
    I1  copy: `repository: copied 6 fields`, state copied, 6 field + 2 table rows | no repository: `not configured`, 0 rows
    I2  repository texts: caption, descriptions (white space collapsed), table description | placeholders are not copied
    I3  field facts: visible, is_calculated, type_text; a table row has no caption
    I4  display-label that differs is stored; one equal to the repository caption is not | its link still carries it
    I5  grid captions: `&` stripped, equal texts collapse with uses = 2, TDBGrid Title.Caption, hints
    I6  links: persistent field (sql / table-name / origin), grid column (dataset / repo-grid), edit control
    I7  the table of every grid column equals what `repo read-dfm` reports for the same DFM
    I8  concept_texts_fts answers a MATCH | a word that is nowhere finds nothing
    I9  CC-6 unchanged: second run `repository: unchanged` + `concepts: unchanged`, copied_at kept | checked_at moved
    I10 CC-6 changed: an edited repository is copied again, old caption gone | no source file was parsed
    I11 derived refresh: an edited DisplayLabel is found, the old one is not, `repository: unchanged`
    I12 code links from call_literal_args: resolved by the unit's own dataset | a parameter is by name only
    I13 repository removed from the config: repository rows gone | the links survive
    I14 unreadable repository: exit code of a clean run, `not readable`, previous copy kept, last_error set
    I15 missing repository: `not found`, repository rows gone
    I16 no extraction change: symbols / refs / call_edges equal with and without a repository
  Run: pwsh -File tests\autotest\run_v156_CONI.ps1 [-Exe <drag-lint.exe>] [-Keep]
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$Keep)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$ErrorActionPreference = 'Continue'
$script:Pass = 0
$script:Fail = 0
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $(if ($ok) { '' } else { $d })) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if ($ok) { $script:Pass++ } else { $script:Fail++ }
}
Write-Host '== v156 CON-I: field repository copy at index --project ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v156-coni-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
function Run([string[]]$a) {
  $o = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } }
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
# `sql --json` rows are positional arrays: map them onto columns[].name.
function Sql([string]$Db, [string]$Query) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe sql --query $Query --db $Db --json 2>$null }
  if ($LASTEXITCODE -ne 0 -or -not $raw) { return ,@() }
  $j = ($raw -join "`n") | ConvertFrom-Json
  $cols = @($j.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($r in @($j.rows)) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $r[$i] }
    $out.Add([pscustomobject]$o)
  }
  return ,$out.ToArray()
}
function One([string]$Db, [string]$Query) { $r = Sql $Db $Query; if ($r.Count -gt 0) { $r[0].PSObject.Properties.Value | Select-Object -First 1 } else { $null } }
function CopyTree([string]$From, [string]$To) {
  foreach ($d in @($From) + @(Get-ChildItem -LiteralPath $From -Recurse -Directory | ForEach-Object FullName)) {
    [IO.Directory]::CreateDirectory((Join-Path $To $d.Substring($From.Length).TrimStart('\'))) | Out-Null
  }
  foreach ($f in Get-ChildItem -LiteralPath $From -Recurse -File) { [IO.File]::Copy($f.FullName, (Join-Path $To $f.FullName.Substring($From.Length).TrimStart('\')), $true) }
}
function Index([string]$Proj, [string]$Db) { Run @('index', '--project', (Join-Path $Proj 'App.dproj'), '--db', $Db) }
function Edit([string]$File, [string]$Old, [string]$New) {
  $t = [IO.File]::ReadAllText($File)
  if (-not $t.Contains($Old)) { throw "fixture text not found in ${File}: $Old" }
  [IO.File]::WriteAllText($File, $t.Replace($Old, $New), [Text.Encoding]::ASCII)
}
try {
  $fix = Join-Path $Repo 'tests\fixtures\v156\CONCEPT\app'
  $app = Join-Path $work 'app'
  $nor = Join-Path $work 'norepo'
  CopyTree $fix $app
  CopyTree $fix $nor
  $cfg = Join-Path $app '_D-RAG\drag-lint-project.json'
  $cfgText = [IO.File]::ReadAllText($cfg)
  [IO.File]::WriteAllText((Join-Path $nor '_D-RAG\drag-lint-project.json'), "{ }`r`n", [Text.Encoding]::ASCII)
  $backup = Join-Path $app 'repo\App.txt'
  $dlrepo = Join-Path $app 'repo\App.dlrepo'
  $rr = Run @('repo', 'restore', '--in', $backup, '--repo', $dlrepo)
  if ($rr.Code -ne 0) { Write-Host "FATAL: repo restore failed: $($rr.Out)" -ForegroundColor Red; exit 2 }
  $db = Join-Path $work 'app.sqlite'
  $ndb = Join-Path $work 'norepo.sqlite'

  # ---- I1 ----
  $r = Index $app $db
  $n = Index $nor $ndb
  $fields = One $db "SELECT COUNT(*) FROM concept_fields WHERE field_name <> ''"
  $tables = One $db "SELECT COUNT(*) FROM concept_fields WHERE field_name = ''"
  Check 'I1a index prints the copy line' ($r.Out -match '(?m)^repository: copied 6 fields, \d+ texts from .*App\.dlrepo$') ($r.Out -split "`n" | Select-Object -Last 4)
  Check 'I1b repo_copy.state = copied, hash and format recorded' ((One $db 'SELECT state FROM repo_copy') -eq 'copied' -and (One $db 'SELECT length(repo_sha256) FROM repo_copy') -eq 64 -and (One $db 'SELECT copy_format FROM repo_copy') -ge 1) (Sql $db 'SELECT * FROM repo_copy' | Out-String)
  Check 'I1c 6 field rows + 2 table rows' ($fields -eq 6 -and $tables -eq 2) "fields=$fields tables=$tables"
  Check 'I1d control: no repository = not configured, 0 rows, state recorded' (($n.Out -match '(?m)^repository: not configured$') -and (One $ndb 'SELECT COUNT(*) FROM concept_fields') -eq 0 -and (One $ndb 'SELECT state FROM repo_copy') -eq 'not-configured') ($n.Out -split "`n" | Select-Object -Last 4)
  Check 'I1e the concepts line counts texts and links' ($r.Out -match '(?m)^concepts: \d+ project texts, \d+ links \(\d+ by name only\)$') ($r.Out -split "`n" | Select-Object -Last 4)

  # ---- I2 ----
  $rt = Sql $db "SELECT text_kind, table_name, field_name, text FROM concept_texts WHERE place = 'repository' ORDER BY table_name, field_name, text_kind, text"
  function HasText($rows, $kind, $t, $f, $text) { @($rows | Where-Object { $_.text_kind -eq $kind -and $_.table_name -eq $t -and $_.field_name -eq $f -and $_.text -ceq $text }).Count -eq 1 }
  Check 'I2a caption of CUSTOMERS.NAME' (HasText $rt 'caption' 'CUSTOMERS' 'NAME' 'Customer name') ($rt | Out-String)
  Check 'I2b descriptions, white space collapsed' ((HasText $rt 'description' 'CUSTOMERS' 'NAME' 'Legal name of the buyer') -and (HasText $rt 'description' 'CUSTOMERS' 'NAME' 'Printed on every invoice')) ($rt | Out-String)
  Check 'I2c table description on the table row' (HasText $rt 'table-description' 'CUSTOMERS' '' 'Buyers of the shop') ($rt | Out-String)
  $ph = @($rt | Where-Object { $_.text -match '(?i)^(summary|remarks) here$' }).Count
  Check 'I2d placeholders are not copied (control: NOTES itself is a field row)' ($ph -eq 0 -and (One $db "SELECT COUNT(*) FROM concept_fields WHERE table_name = 'CUSTOMERS' AND field_name = 'NOTES'") -eq 1) "placeholder rows=$ph"

  # ---- I3 ----
  $cf = Sql $db "SELECT table_name, field_name, caption, type_text, is_calculated, visible FROM concept_fields"
  function Fld($t, $f) { $cf | Where-Object { $_.table_name -eq $t -and $_.field_name -eq $f } }
  Check 'I3a visible / is_calculated / type_text' ((Fld 'CUSTOMERS' 'ID').visible -eq 0 -and (Fld 'CUSTOMERS' 'NAME').visible -eq 1 -and (Fld 'SUPPLIERS' 'NAME').is_calculated -eq 1 -and (Fld 'CUSTOMERS' 'NAME').is_calculated -eq 0 -and (Fld 'CUSTOMERS' 'NAME').type_text -eq 'string(40)') ($cf | Out-String)
  Check 'I3b the table row has no caption; the field row has one' ((Fld 'CUSTOMERS' '').caption -eq '' -and (Fld 'CUSTOMERS' 'NAME').caption -ceq 'Customer name') ($cf | Out-String)

  # ---- I4 / I5 ----
  $pt = Sql $db "SELECT text_kind, table_name, field_name, text, uses FROM concept_texts WHERE place = 'project' ORDER BY table_name, field_name, text_kind, text"
  $ln = Sql $db "SELECT link_kind, confidence, table_name, field_name, form_name, form_class, component_name, dataset_name, symbol_id, via, caption, line FROM concept_links"
  function Lnk($comp) { $ln | Where-Object { $_.component_name -eq $comp } }
  Check 'I4a a differing DisplayLabel is a project text' (HasText $pt 'display-label' 'CUSTOMERS' 'NAME' 'Client name') ($pt | Out-String)
  $cl = @(Sql $db "SELECT place, text_kind FROM concept_texts WHERE text = 'Credit limit'")
  Check 'I4b a DisplayLabel equal to the repository caption is stored once, as the caption' ($cl.Count -eq 1 -and $cl[0].place -eq 'repository' -and $cl[0].text_kind -eq 'caption') ($cl | Out-String)
  Check 'I4c control: the link of that field still carries the label' ((Lnk 'qryCustomersCREDIT_LIMIT').caption -ceq 'Credit limit') ((Lnk 'qryCustomersCREDIT_LIMIT') | Out-String)
  $gc = $pt | Where-Object { $_.text_kind -eq 'grid-caption' -and $_.table_name -eq 'CUSTOMERS' -and $_.field_name -eq 'NAME' }
  Check 'I5a `&` stripped and two columns with one caption collapse (uses = 2)' (@($gc).Count -eq 1 -and $gc.text -ceq 'Cust. name' -and $gc.uses -eq 2) ($pt | Out-String)
  $amp = One $db "SELECT COUNT(*) FROM concept_texts WHERE instr(text, char(38)) > 0"  # char(38) = the ampersand: sql --query runs through FireDAC, which reads a typed one as a macro
  Check 'I5b no stored text holds an accelerator (control: the fixture DFM has one)' ($amp -eq 0 -and (One $db 'SELECT COUNT(*) FROM concept_texts') -gt 0 -and [IO.File]::ReadAllText((Join-Path $app 'uMain.dfm')).Contains('Cust. &name')) "rows with &: $amp"
  Check 'I5c TDBGrid Title.Caption is a grid caption' (HasText $pt 'grid-caption' 'SUPPLIERS' 'NAME' 'Supplier (old grid)') ($pt | Out-String)
  Check 'I5d hints of a grid column (line break collapsed) and of an edit control' ((HasText $pt 'hint' 'CUSTOMERS' 'NAME' 'Name as printed on the invoice') -and (HasText $pt 'hint' 'CUSTOMERS' 'NAME' 'Type the legal name')) ($pt | Out-String)

  # ---- I6 ----
  $pf = Lnk 'qryCustomersNAME'
  Check 'I6a persistent field of a one-table SELECT' ($pf.link_kind -eq 'persistent-field' -and $pf.confidence -eq 'resolved' -and $pf.table_name -eq 'CUSTOMERS' -and $pf.field_name -eq 'NAME' -and $pf.via -eq 'sql' -and $pf.form_name -eq 'frmMain' -and $pf.form_class -eq 'TfrmMain' -and $pf.dataset_name -eq 'qryCustomers' -and $pf.symbol_id -gt 0 -and $pf.line -gt 0 -and $pf.caption -ceq 'Client name') ($pf | Out-String)
  Check 'I6b TableName and Origin resolve' ((Lnk 'tblSuppliersNAME').via -eq 'table-name' -and (Lnk 'tblSuppliersNAME').table_name -eq 'SUPPLIERS' -and (Lnk 'qryJoinNAME').via -eq 'origin' -and (Lnk 'qryJoinNAME').table_name -eq 'SUPPLIERS' -and (Lnk 'qryJoinNAME').field_name -eq 'NAME') (($ln | Where-Object link_kind -eq 'persistent-field') | Out-String)
  Check 'I6c an aliased join column resolves to its table column' ((Lnk 'qryJoinCUSTOMER_ID').table_name -eq 'CUSTOMERS' -and (Lnk 'qryJoinCUSTOMER_ID').field_name -eq 'ID') ((Lnk 'qryJoinCUSTOMER_ID') | Out-String)
  Check 'I6d grid column through its data source' ((Lnk 'colName').link_kind -eq 'grid-column' -and (Lnk 'colName').table_name -eq 'CUSTOMERS' -and (Lnk 'colName').dataset_name -eq 'qryCustomers' -and (Lnk 'colName').caption -ceq 'Cust. name') ((Lnk 'colName') | Out-String)
  Check 'I6e grid column the dataset cannot resolve: the repository binding wins (repo-grid)' ((Lnk 'colOther').via -eq 'repo-grid' -and (Lnk 'colOther').table_name -eq 'SUPPLIERS' -and (Lnk 'colOther').field_name -eq 'NAME' -and (Lnk 'colOther').confidence -eq 'resolved') ((Lnk 'colOther') | Out-String)
  Check 'I6f edit control and TDBGrid column' ((Lnk 'edtName').link_kind -eq 'edit-control' -and (Lnk 'edtName').table_name -eq 'CUSTOMERS' -and (Lnk 'edtName').field_name -eq 'NAME' -and (Lnk 'grdOld.Columns[0]').table_name -eq 'SUPPLIERS') (($ln | Where-Object link_kind -ne 'persistent-field') | Out-String)
  Check 'I6g control: without the repository colOther is by name only' ((One $ndb "SELECT confidence FROM concept_links WHERE component_name = 'colOther'") -eq 'by-name-only' -and (One $ndb "SELECT table_name FROM concept_links WHERE component_name = 'colOther'") -eq '') (Sql $ndb "SELECT * FROM concept_links WHERE component_name = 'colOther'" | Out-String)

  # ---- I7: one resolver, two callers ----
  $rd = Run @('repo', 'read-dfm', '--dfm', (Join-Path $nor 'uMain.dfm'), '--direction', 'dfm-to-repo', '--repo', $dlrepo)
  $seen = 0; $bad = @()
  foreach ($m in [regex]::Matches($rd.Out, 'DL_GRID_COLUMNS frmMain\|tvCustomers\|(\w+):\s+-> TABLE_NAME=(\w*); FIELD_NAME=(\w+)')) {
    $seen++
    $mine = Sql $ndb ("SELECT table_name, field_name FROM concept_links WHERE component_name = '" + $m.Groups[1].Value + "'")
    if ($mine.Count -ne 1 -or $mine[0].table_name -ne $m.Groups[2].Value -or ($m.Groups[2].Value -ne '' -and $mine[0].field_name -ne $m.Groups[3].Value)) { $bad += $m.Value }
  }
  Check 'I7 every grid column has the table repo read-dfm reports (3+ columns compared)' ($seen -ge 3 -and $bad.Count -eq 0) "seen=$seen bad=$($bad -join ' ; ')`n$($rd.Out)"

  # ---- I8 ----
  $hit = One $db "SELECT COUNT(*) FROM concept_texts_fts WHERE concept_texts_fts MATCH 'client'"
  $miss = One $db "SELECT COUNT(*) FROM concept_texts_fts WHERE concept_texts_fts MATCH 'zzznowhere'"
  Check 'I8 the FTS index answers (control: an absent word finds nothing)' ($hit -ge 1 -and $miss -eq 0) "hit=$hit miss=$miss"

  # ---- I9 ----
  $before = (Sql $db 'SELECT copied_at_unix, checked_at_unix, derived_at_unix FROM repo_copy')[0]
  Start-Sleep -Milliseconds 1200
  $r2 = Index $app $db
  $after = (Sql $db 'SELECT copied_at_unix, checked_at_unix, derived_at_unix FROM repo_copy')[0]
  Check 'I9a second run: repository unchanged, concepts unchanged' (($r2.Out -match '(?m)^repository: unchanged \(.*App\.dlrepo\)$') -and ($r2.Out -match '(?m)^concepts: unchanged$')) ($r2.Out -split "`n" | Select-Object -Last 4)
  Check 'I9b copied_at and derived_at kept (control: checked_at moved)' ($after.copied_at_unix -eq $before.copied_at_unix -and $after.derived_at_unix -eq $before.derived_at_unix -and $after.checked_at_unix -gt $before.checked_at_unix -and $before.copied_at_unix -gt 0) "before=$($before | ConvertTo-Json -Compress) after=$($after | ConvertTo-Json -Compress)"

  # ---- I10 ----
  Edit $backup 'DISPLAY_LABEL=Customer name' 'DISPLAY_LABEL=Buyer name'
  $rr = Run @('repo', 'restore', '--in', $backup, '--repo', $dlrepo, '--replace')
  $parsedBefore = One $db 'SELECT MAX(parsed_at) FROM files'
  Start-Sleep -Milliseconds 1200
  $r3 = Index $app $db
  $new = One $db "SELECT COUNT(*) FROM concept_texts WHERE text = 'Buyer name' AND place = 'repository'"
  $old = One $db "SELECT COUNT(*) FROM concept_texts WHERE text = 'Customer name'"
  Check 'I10a a changed repository is copied again; the old caption is gone' ($rr.Code -eq 0 -and ($r3.Out -match '(?m)^repository: copied 6 fields') -and $new -eq 1 -and $old -eq 0) "restore=$($rr.Code) new=$new old=$old`n$($r3.Out -split "`n" | Select-Object -Last 4)"
  Check 'I10b control: no source file was parsed for it; the derived part followed' ((One $db 'SELECT MAX(parsed_at) FROM files') -eq $parsedBefore -and ($r3.Out -match '(?m)^concepts: \d+ project texts')) ($r3.Out -split "`n" | Select-Object -Last 6)

  # ---- I11 ----
  Edit (Join-Path $app 'uMain.dfm') "DisplayLabel = 'Client name'" "DisplayLabel = 'Patron name'"
  $r4 = Index $app $db
  $new = One $db "SELECT COUNT(*) FROM concept_texts WHERE text = 'Patron name' AND place = 'project'"
  $old = One $db "SELECT COUNT(*) FROM concept_texts WHERE text = 'Client name'"
  Check 'I11 an edited DisplayLabel: repository unchanged, new label stored, old one gone' (($r4.Out -match '(?m)^repository: unchanged') -and ($r4.Out -match '(?m)^concepts: \d+ project texts') -and $new -eq 1 -and $old -eq 0) "new=$new old=$old`n$($r4.Out -split "`n" | Select-Object -Last 4)"

  # ---- I12: code links (call_literal_args; seeded when no emitter of this build filled it) ----
  $args0 = One $db "SELECT COUNT(*) FROM call_literal_args WHERE callee_name IN ('FieldByName', 'FindField')"
  if ($args0 -eq 0) {
    $py = Join-Path $work 'seed.py'
    [IO.File]::WriteAllText($py, @'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
def fid(name):
    return con.execute("SELECT id FROM files WHERE lower(path) LIKE ?", ('%' + name,)).fetchone()[0]
def sym(name):
    r = con.execute("SELECT id FROM symbols WHERE name = ? AND kind IN ('method', 'procedure', 'function') ORDER BY id", (name,)).fetchone()
    return r[0] if r else None
rows = [(fid('umain.pas'), 0, sym('CustomerNameChanged'), 40, 24, 'FieldByName', 'qryCustomers', 0, 1, 40, 36, 'string', 'NAME'),
        (fid('umain.pas'), 1, sym('CustomerNameChanged'), 42, 26, 'FindField', 'Self.tblSuppliers', 0, 1, 42, 36, 'string', 'NAME'),
        (fid('umain.pas'), 2, sym('CustomerNameChanged'), 43, 5, 'Locate', 'qryCustomers', 0, 3, 43, 12, 'string', 'NAME'),
        (fid('utools.pas'), 0, sym('CopyName'), 13, 7, 'FieldByName', 'pDs', 0, 1, 13, 19, 'string', 'NAME')]
con.executemany("INSERT INTO call_literal_args (file_id, ordinal, symbol_id, call_line, call_col, callee_name, receiver_text, arg_index, arg_count, lit_line, lit_col, lit_kind, value) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)
con.commit()
con.close()
'@, [Text.Encoding]::ASCII)
    & python $py $db 2>&1 | Out-Null
  }
  Edit (Join-Path $app 'uJoin.dfm') "Caption = 'Join'" "Caption = 'Join 2'"
  $r5 = Index $app $db
  $code = Sql $db "SELECT confidence, table_name, field_name, dataset_name, via, form_name, enclosing_symbol_id, line FROM concept_links WHERE link_kind = 'code' ORDER BY file_id, line"
  $c1 = $code | Where-Object { $_.dataset_name -eq 'qryCustomers' }
  $c2 = $code | Where-Object { $_.dataset_name -match 'tblSuppliers$' }
  $c3 = $code | Where-Object { $_.dataset_name -eq 'pDs' -and $_.field_name -eq 'NAME' }
  Check 'I12a FieldByName on the unit''s own dataset is resolved to its table' (@($c1).Count -eq 1 -and $c1.confidence -eq 'resolved' -and $c1.table_name -eq 'CUSTOMERS' -and $c1.field_name -eq 'NAME' -and $c1.via -eq 'FieldByName' -and $c1.form_name -eq 'frmMain' -and $c1.enclosing_symbol_id -gt 0) ($code | Out-String)
  Check 'I12b FindField through a qualified receiver' (@($c2).Count -eq 1 -and $c2.confidence -eq 'resolved' -and $c2.table_name -eq 'SUPPLIERS' -and $c2.via -eq 'FindField') ($code | Out-String)
  Check 'I12c control: a parameter receiver is by name only, with no table' (@($c3).Count -eq 1 -and $c3.confidence -eq 'by-name-only' -and $c3.table_name -eq '') ($code | Out-String)
  Check 'I12d only the name accessors make a link (no Locate row)' (@($code | Where-Object via -eq 'Locate').Count -eq 0 -and @($code).Count -ge 3) ($code | Out-String)

  # ---- I13 ----
  $links = One $db 'SELECT COUNT(*) FROM concept_links'
  [IO.File]::WriteAllText($cfg, "{ }`r`n", [Text.Encoding]::ASCII)
  $r6 = Index $app $db
  $repoRows = (One $db "SELECT COUNT(*) FROM concept_texts WHERE place = 'repository'") + (One $db 'SELECT COUNT(*) FROM concept_fields')
  Check 'I13a repository removed from the config: its rows are gone' (($r6.Out -match '(?m)^repository: not configured$') -and $repoRows -eq 0 -and (One $db 'SELECT state FROM repo_copy') -eq 'not-configured' -and (One $db 'SELECT repo_sha256 FROM repo_copy') -eq '') "rows=$repoRows`n$($r6.Out -split "`n" | Select-Object -Last 4)"
  Check 'I13b control: the links survive' ($links -gt 0 -and (One $db 'SELECT COUNT(*) FROM concept_links') -eq $links) "before=$links after=$(One $db 'SELECT COUNT(*) FROM concept_links')"

  # ---- I14 ----
  [IO.File]::WriteAllText($cfg, $cfgText, [Text.Encoding]::ASCII)
  $r7 = Index $app $db
  $clean = $r7.Code
  [IO.File]::WriteAllText($dlrepo, "this is not a repository`r`n", [Text.Encoding]::ASCII)
  $r8 = Index $app $db
  Check 'I14a unreadable: exit code of a clean run, the note, previous copy kept' ($r8.Code -eq $clean -and ($r7.Out -match '(?m)^repository: copied 6 fields') -and ($r8.Out -match '(?m)^repository: not readable: .*App\.dlrepo \(.+\); previous copy kept$') -and (One $db "SELECT COUNT(*) FROM concept_fields WHERE field_name <> ''") -eq 6) "code=$($r8.Code)/$clean`n$($r8.Out -split "`n" | Select-Object -Last 4)"
  Check 'I14b state unreadable, last_error set' ((One $db 'SELECT state FROM repo_copy') -eq 'unreadable' -and (One $db 'SELECT length(last_error) FROM repo_copy') -gt 0) (Sql $db 'SELECT state, last_error FROM repo_copy' | Out-String)

  # ---- I15 ----
  [IO.File]::Delete($dlrepo)
  $r9 = Index $app $db
  Check 'I15 missing: the note names the path, repository rows gone' (($r9.Out -match '(?m)^repository: not found: .*App\.dlrepo$') -and (One $db 'SELECT state FROM repo_copy') -eq 'missing' -and (One $db 'SELECT COUNT(*) FROM concept_fields') -eq 0) ($r9.Out -split "`n" | Select-Object -Last 4)

  # ---- I16 ----
  $nor2 = Join-Path $work 'norepo2'
  CopyTree $nor $nor2
  $app2 = Join-Path $work 'app2'
  CopyTree $fix $app2
  $null = Run @('repo', 'restore', '--in', (Join-Path $app2 'repo\App.txt'), '--repo', (Join-Path $app2 'repo\App.dlrepo'))
  $a2 = Index $app2 (Join-Path $work 'app2.sqlite')
  $n2 = Index $nor2 (Join-Path $work 'norepo2.sqlite')
  $q = "SELECT (SELECT COUNT(*) FROM symbols) || '/' || (SELECT COUNT(*) FROM refs) || '/' || (SELECT COUNT(*) FROM call_edges)"
  $ca = One (Join-Path $work 'app2.sqlite') $q
  $cn = One (Join-Path $work 'norepo2.sqlite') $q
  Check 'I16 symbols / refs / call_edges are the same with and without a repository (control: I1 ran the step)' ($ca -and $ca -eq $cn -and ($a2.Out -match 'repository: copied')) "with=$ca without=$cn"
}
finally {
  if (-not $Keep) { try { [IO.Directory]::Delete($work, $true) } catch { } } else { Write-Host "kept: $work" }
}
Write-Host ("Summary: pass={0} fail={1}" -f $script:Pass, $script:Fail)
exit ([int]($script:Fail -gt 0))
