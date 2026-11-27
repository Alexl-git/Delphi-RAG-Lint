<#
  run_v156_CONQ_e2e.ps1 -- drag-lint 1.56 lanes CON-I + CON-Q end to end: `index --project` (the
  repository copy pass of src\index\DRagLint.Index.RepoCopy.pas) fills the concept tables of a
  scratch DB from a REAL fixture, and `query --concept` (src\query\DRagLint.Query.ConceptRepo.pas)
  answers from them. Nothing is hand-filled, except E-B3 (see there). Design:
  docs\superpowers\specs\2026-11-27-three-place-search-caption-concepts-design.md.

  Fixture tests\fixtures\v156\CONCEPT\app (lane CON-I's), copied to a work folder; the repository
  file is built with `repo restore`.

  E-A  caption tiers (CC-4): repository caption, DFM DisplayLabel, grid caption with `&`, TDBGrid
       Title.Caption, description, table description, FIELD_NAME; tiers never go down
  E-B  field links (CC-5): persistent fields (sql / table-name / origin), grid columns (dataset /
       repo-grid / TDBGrid), edit control, forms; code and by-name-only links
  E-C  place on every hit, text and JSON; places[]; --place; a library DB
  E-D  the copy's life: fresh (no stale note: the STAT contract of the two lanes), changed
       repository = stale note, re-index = new caption found; no repository; a directory-scan
       index and a project index made before 1.56 each get their own note

  Positive control of the whole script: -Exe <an engine whose index has no copy pass> (lane CON-Q
  before the merge of CON-I): every check on a repository hit, a link or a caption tier FAILS.
  Run from a NEUTRAL CWD, pwsh 7. Needs python (sqlite3) on PATH for E-B3 and E-D6.
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$Work = '', [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v156_CONQ_e2e: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') { $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "run_v156_CONQ_e2e: no engine at $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
if ($Work -eq '') { $Work = $env:TEMP }
$work = Join-Path $Work ('dl-v156-conq-e2e-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($work) | Out-Null

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}
function Run([string[]]$Argv) {
  $o = & { $ErrorActionPreference = 'Continue'; & $Exe @Argv 2>&1 | ForEach-Object { "$_" } }
  return @{ rc = $LASTEXITCODE; out = (@($o) -join "`n") }
}
# One `query --concept` run: exit code, stdout lines, stderr text, parsed JSON ($null in text mode).
function Run-Concept([string]$Db, [string]$Words, [string[]]$More = @(), [switch]$Text) {
  $errFile = Join-Path $work 'stderr.txt'
  $argv = @('query', '--concept', $Words, '--db', $Db) + $More
  if (-not $Text) { $argv += '--json' }
  $out = & { $ErrorActionPreference = 'Continue'; & $Exe @argv 2>$errFile }
  $rc = $LASTEXITCODE
  $json = $null
  if (-not $Text) { try { $json = ($out -join "`n") | ConvertFrom-Json } catch { $json = $null } }
  $hits = @()
  if ($json -and $json.hits) { $hits = @($json.hits) }
  $errText = ''
  if (Test-Path -LiteralPath $errFile) { $errText = '' + [IO.File]::ReadAllText($errFile) }
  return @{ rc = $rc; out = @($out); err = $errText; json = $json; hits = $hits }
}
function Hit-Of($Run, [string]$QName) { return @($Run.hits | Where-Object { $_.qname -eq $QName }) | Select-Object -First 1 }
function First-Hit($Run) { return $Run.hits | Select-Object -First 1 }
function Tiers-Sorted($Run) {
  $t = @($Run.hits | ForEach-Object { [int]$_.tier })
  for ($i = 1; $i -lt $t.Count; $i++) { if ($t[$i] -lt $t[$i - 1]) { return $false } }
  return ($t.Count -gt 0)
}
function Line-Of([string]$File, [string]$Marker) {
  $n = 0
  foreach ($l in [IO.File]::ReadAllLines($File)) { $n++; if ($l.Contains($Marker)) { return $n } }
  return -1
}
function Copy-Tree([string]$From, [string]$To) {
  foreach ($d in @($From) + @(Get-ChildItem -LiteralPath $From -Recurse -Directory | ForEach-Object FullName)) {
    [IO.Directory]::CreateDirectory((Join-Path $To $d.Substring($From.Length).TrimStart('\'))) | Out-Null
  }
  foreach ($f in Get-ChildItem -LiteralPath $From -Recurse -File) { [IO.File]::Copy($f.FullName, (Join-Path $To $f.FullName.Substring($From.Length).TrimStart('\')), $true) }
}
function Edit-File([string]$File, [string]$Old, [string]$New) {
  $t = [IO.File]::ReadAllText($File)
  if (-not $t.Contains($Old)) { throw "fixture text not found in ${File}: $Old" }
  [IO.File]::WriteAllText($File, $t.Replace($Old, $New), [Text.Encoding]::ASCII)
}
function Run-Py([string]$Code, [string[]]$Argv) {
  $py = Join-Path $work 'step.py'
  [IO.File]::WriteAllText($py, $Code, [Text.Encoding]::ASCII)
  $o = & { $ErrorActionPreference = 'Continue'; & python.exe -I $py @Argv 2>&1 | ForEach-Object { "$_" } }
  return @{ rc = $LASTEXITCODE; out = (@($o) -join ' ') }
}

Write-Host '== v156 CON-I + CON-Q end to end: index --project, then query --concept ==' -ForegroundColor Cyan

# ---- setup: a real project index with the repository copy ---------------------------------
$fix = Join-Path $repo 'tests\fixtures\v156\CONCEPT\app'
$app = Join-Path $work 'app'
$nor = Join-Path $work 'norepo'
Copy-Tree $fix $app
Copy-Tree $fix $nor
[IO.File]::WriteAllText((Join-Path $nor '_D-RAG\drag-lint-project.json'), "{ }`r`n", [Text.Encoding]::ASCII)
$backup = Join-Path $app 'repo\App.txt'
$dlrepo = Join-Path $app 'repo\App.dlrepo'
$dproj  = Join-Path $app 'App.dproj'
$mainDfm = Join-Path $app 'uMain.dfm'
$rr = Run @('repo', 'restore', '--in', $backup, '--repo', $dlrepo)
Check 'setup: repo restore builds the repository file' (($rr.rc -eq 0) -and (Test-Path -LiteralPath $dlrepo)) "(rc $($rr.rc)) $($rr.out)"
$A = Join-Path $work 'app.sqlite'
$N = Join-Path $work 'norepo.sqlite'
$ix = Run @('index', '--project', $dproj, '--db', $A)
Check 'setup: index --project exits 0 and prints "repository: copied 6 fields"' (($ix.rc -eq 0) -and ($ix.out -match '(?m)^repository: copied 6 fields')) "(rc $($ix.rc)) $(($ix.out -split "`n" | Select-Object -Last 4) -join ' | ')"
$nx = Run @('index', '--project', (Join-Path $nor 'App.dproj'), '--db', $N)
Check 'setup: the project with no repository indexes and says "repository: not configured"' (($nx.rc -eq 0) -and ($nx.out -match '(?m)^repository: not configured')) "(rc $($nx.rc))"

# ---- E-A caption tiers --------------------------------------------------------------------
$r = Run-Concept $A 'customer name'
$h = First-Hit $r
Check 'E-A1 "customer name" (the repository caption): rank 1 = repo-field CUSTOMERS.NAME, place repository, tier 2, matched caption' (($r.rc -eq 0) -and $h -and ($h.qname -eq 'CUSTOMERS.NAME') -and ($h.kind -eq 'repo-field') -and ($h.place -eq 'repository') -and ($h.tier -eq 2) -and (@($h.matched) -contains 'caption') -and ($h.score -eq 0)) "(rc $($r.rc), first $($h.qname) place $($h.place) tier $($h.tier))"
$sym = @($r.hits | Where-Object { $_.qname -like '*CustomerNameChanged' }) | Select-Object -First 1
Check 'E-A1 the method CustomerNameChanged follows it: place project, tier 3' ($sym -and ($sym.place -eq 'project') -and ($sym.tier -eq 3) -and ($sym.rank -gt $h.rank)) "(tier $($sym.tier) place $($sym.place))"
Check 'E-A1 the field carries the repository facts (caption, type string(40), visible)' ($h -and ($h.field.caption -ceq 'Customer name') -and ($h.field.type -eq 'string(40)') -and ($h.field.visible -eq $true) -and ($h.file -eq $dlrepo))
$r = Run-Concept $A 'client name'
$h = First-Hit $r
Check 'E-A2 "client name" (a DisplayLabel of uMain.dfm): CUSTOMERS.NAME, tier 2, matched display-label; field.caption stays the repository caption' ($h -and ($h.qname -eq 'CUSTOMERS.NAME') -and ($h.tier -eq 2) -and ($h.place -eq 'repository') -and (@($h.matched) -contains 'display-label') -and ($h.field.caption -ceq 'Customer name')) "(first $($h.qname) tier $($h.tier) matched $(@($h.matched) -join ','))"
$r = Run-Concept $A 'cust name'
$h = Hit-Of $r 'CUSTOMERS.NAME'
Check 'E-A3 "cust name" (grid caption "Cust. &name", the & dropped at index time): tier 2, matched grid-caption' ($h -and ($h.tier -eq 2) -and (@($h.matched) -contains 'grid-caption') -and (@($h.texts | Where-Object { ($_.kind -eq 'grid-caption') -and ($_.text -ceq 'Cust. name') -and ($_.uses -eq 2) -and ($_.place -eq 'project') }).Count -eq 1)) "(tier $($h.tier) matched $(@($h.matched) -join ','))"
$r = Run-Concept $A 'supplier old grid'
$h = First-Hit $r
Check 'E-A4 "supplier old grid" (TDBGrid Title.Caption): SUPPLIERS.NAME, tier 2, matched grid-caption' ($h -and ($h.qname -eq 'SUPPLIERS.NAME') -and ($h.tier -eq 2) -and (@($h.matched) -contains 'grid-caption')) "(first $($h.qname) tier $($h.tier))"
$r = Run-Concept $A 'legal name buyer'
$h = Hit-Of $r 'CUSTOMERS.NAME'
Check 'E-A5 "legal name buyer" (words of the description only): tier 3, matched description, allTerms' ($h -and ($h.tier -eq 3) -and (@($h.matched) -contains 'description') -and ($h.allTerms -eq $true) -and ($h.score -gt 0)) "(tier $($h.tier) matched $(@($h.matched) -join ','))"
$r = Run-Concept $A 'buyers shop'
$h = First-Hit $r
Check 'E-A6 "buyers shop" (the table description): repo-table CUSTOMERS, place repository, tier 3, no links key' ($h -and ($h.qname -eq 'CUSTOMERS') -and ($h.kind -eq 'repo-table') -and ($h.place -eq 'repository') -and ($h.tier -eq 3) -and (@($h.matched) -contains 'table-description') -and ($h.PSObject.Properties.Name -notcontains 'links')) "(first $($h.qname) kind $($h.kind) tier $($h.tier))"
$r = Run-Concept $A 'credit_limit'
$h = First-Hit $r
Check 'E-A7 "credit_limit" (a FIELD_NAME): tier 1, matched name' ($h -and ($h.qname -eq 'CUSTOMERS.CREDIT_LIMIT') -and ($h.tier -eq 1) -and (@($h.matched) -contains 'name')) "(first $($h.qname) tier $($h.tier))"
$r = Run-Concept $A 'name'
$t1 = @($r.hits | Where-Object { $_.tier -eq 1 } | ForEach-Object { $_.qname + '@' + $_.place })
Check 'E-A8 "name": tier 1 = the symbol Name (project), then both fields named NAME (repository)' (($t1.Count -eq 3) -and ($t1[0] -eq 'uMain.TfrmMain.Name@project') -and ($t1[1] -eq 'CUSTOMERS.NAME@repository') -and ($t1[2] -eq 'SUPPLIERS.NAME@repository')) "($($t1 -join ' | '))"
$r = Run-Concept $A 'supplier name'
$h = First-Hit $r
$other = Hit-Of $r 'CUSTOMERS.NAME'
Check 'E-A9 control: "supplier name" ranks SUPPLIERS.NAME first in tier 2; CUSTOMERS.NAME is not a caption-tier hit' ($h -and ($h.qname -eq 'SUPPLIERS.NAME') -and ($h.tier -eq 2) -and ((-not $other) -or ($other.tier -gt 2))) "(first $($h.qname), other tier $($other.tier))"
$r = Run-Concept $A 'summary here'
Check 'E-A10 control: a placeholder text of the repository ("Summary here") is no hit' (@($r.hits | Where-Object { $_.place -eq 'repository' }).Count -eq 0) "(hits $($r.hits.Count))"
$sortedAll = $true
foreach ($q in 'customer name', 'name', 'limit', 'supplier old grid', 'legal name buyer') { if (-not (Tiers-Sorted (Run-Concept $A $q))) { $sortedAll = $false } }
Check 'E-A11 tiers never go down in five queries' $sortedAll

# ---- E-B links ----------------------------------------------------------------------------
$r = Run-Concept $A 'name' @('--kind', 'repo-field')
$c = Hit-Of $r 'CUSTOMERS.NAME'
$s = Hit-Of $r 'SUPPLIERS.NAME'
$cl = if ($c) { $c.links } else { $null }
$sl = if ($s) { $s.links } else { $null }
$pf = if ($cl) { @($cl.persistentFields.rows) | Select-Object -First 1 } else { $null }
Check 'E-B1 CUSTOMERS.NAME: 1 persistent field = frmMain.qryCustomersNAME of qryCustomers, via sql, caption "Client name", at its DFM line' ($cl -and ($cl.persistentFields.count -eq 1) -and $pf -and ($pf.component -eq 'qryCustomersNAME') -and ($pf.form -eq 'frmMain') -and ($pf.dataset -eq 'qryCustomers') -and ($pf.via -eq 'sql') -and ($pf.caption -ceq 'Client name') -and ($pf.file -eq $mainDfm) -and ($pf.line -eq (Line-Of $mainDfm 'object qryCustomersNAME'))) "(count $($cl.persistentFields.count) line $($pf.line))"
$gc = if ($cl) { @($cl.gridColumns.rows | ForEach-Object { $_.component }) } else { @() }
Check 'E-B1 2 grid columns (colName, colName2), 1 edit control (edtName), 1 form (TfrmMain)' ($cl -and ($cl.gridColumns.count -eq 2) -and ($gc -contains 'colName') -and ($gc -contains 'colName2') -and ($cl.editControls.count -eq 1) -and ($cl.editControls.rows[0].component -eq 'edtName') -and ($cl.forms.count -eq 1) -and ($cl.forms.rows[0].class -eq 'TfrmMain')) "(grid $($gc -join ',') edit $($cl.editControls.count) forms $($cl.forms.count))"
$vias = if ($sl) { @($sl.persistentFields.rows | ForEach-Object { $_.component + ':' + $_.via }) } else { @() }
$sg = if ($sl) { @($sl.gridColumns.rows | ForEach-Object { $_.component + ':' + $_.via }) } else { @() }
Check 'E-B2 SUPPLIERS.NAME: persistent fields via origin (frmJoin) and table-name (frmMain); 2 forms' ($sl -and ($sl.persistentFields.count -eq 2) -and ($vias -contains 'qryJoinNAME:origin') -and ($vias -contains 'tblSuppliersNAME:table-name') -and ($sl.forms.count -eq 2)) "($($vias -join ' | '))"
Check 'E-B2 its grid columns: colOther through the repository grid row, the TDBGrid column through TableName; no edit control' ($sl -and ($sl.gridColumns.count -eq 2) -and ($sg -contains 'colOther:repo-grid') -and ($sg -contains 'grdOld.Columns[0]:table-name') -and ($sl.editControls.count -eq 0)) "($($sg -join ' | '))"
Check 'E-B2 control: no link of one field stands under the other' ((@($cl.persistentFields.rows | Where-Object { $_.component -like '*Suppliers*' }).Count -eq 0) -and (@($sl.gridColumns.rows | Where-Object { $_.component -like 'colName*' }).Count -eq 0))
$r0 = Run-Concept $A 'customer name' @('--links', '0')
$h0 = Hit-Of $r0 'CUSTOMERS.NAME'
Check 'E-B4 --links 0: the counts stay, no rows' ($h0 -and ($h0.links.gridColumns.count -eq 2) -and (@($h0.links.gridColumns.rows).Count -eq 0) -and (@($h0.links.persistentFields.rows).Count -eq 0))

# ---- E-C place on every hit ---------------------------------------------------------------
$places = 'project', 'repository', 'library'
$total = 0
$bad = 0
foreach ($q in 'customer name', 'name', 'limit', 'vendor', 'buyers shop') {
  $rq = Run-Concept $A $q
  foreach ($x in $rq.hits) { $total++; if (($places -notcontains $x.place) -or ($x.tier -lt 1) -or ($x.tier -gt 4)) { $bad++ } }
}
Check 'E-C1 JSON: every hit of five queries has place and tier 1..4' (($total -ge 20) -and ($bad -eq 0)) "($total hits, $bad without)"
$t = Run-Concept $A 'customer name' -Text
$hitLines = @($t.out | Where-Object { $_ -match '^  \d+  \d+[.,]\d\d  ' })
$noPlace = @($hitLines | Where-Object { $_ -notmatch ' place=(project|repository|library)$' })
$said = if ($t.out.Count -and ($t.out[0] -match '^concept "customer name": (\d+) hit\(s\)')) { [int]$Matches[1] } else { -1 }
Check 'E-C2 text: every hit line ends with " place=<p>"; the lines are as many as the header says' (($hitLines.Count -gt 5) -and ($noPlace.Count -eq 0) -and ($hitLines.Count -eq $said)) "($($hitLines.Count) lines, $($noPlace.Count) without, header $said)"
Check 'E-C2 text: both places are there' ((@($hitLines | Where-Object { $_ -match ' place=repository$' }).Count -ge 1) -and (@($hitLines | Where-Object { $_ -match ' place=project$' }).Count -ge 1))
$r = Run-Concept $A 'customer name'
$pp = @($r.json.places | Where-Object { $_.place -eq 'project' }) | Select-Object -First 1
$rp = @($r.json.places | Where-Object { $_.place -eq 'repository' }) | Select-Object -First 1
$lp = @($r.json.places | Where-Object { $_.place -eq 'library' }) | Select-Object -First 1
Check 'E-C3 places[]: project ok, repository copied with the path of the file index --project read, library not-configured' ($pp -and $rp -and $lp -and ($pp.state -eq 'ok') -and ($rp.state -eq 'copied') -and ($rp.path -eq $dlrepo) -and ($lp.state -eq 'not-configured')) "(repository $($rp.state) $($rp.path))"
$r = Run-Concept $A 'customer name' @('--place', 'project')
Check 'E-C4 --place project: no repository hit, the method still there' ((@($r.hits | Where-Object { $_.place -ne 'project' }).Count -eq 0) -and (@($r.hits | Where-Object { $_.qname -like '*CustomerNameChanged' }).Count -eq 1)) "(hits $($r.hits.Count))"
$r = Run-Concept $A 'customer name' @('--place', 'repository')
Check 'E-C4 --place repository: only repository hits, CUSTOMERS.NAME first' (($r.hits.Count -ge 1) -and (@($r.hits | Where-Object { $_.place -ne 'repository' }).Count -eq 0) -and ((First-Hit $r).qname -eq 'CUSTOMERS.NAME')) "(hits $($r.hits.Count))"
$libDir = Join-Path $work 'lib'
[IO.Directory]::CreateDirectory($libDir) | Out-Null
$libDb = Join-Path $libDir 'library-Win64.sqlite'
[IO.File]::Copy($N, $libDb, $true)
$r = Run-Concept $A 'customer name' @('--db', $libDb)
$pi = @($r.hits | ForEach-Object { $_.qname + '@' + $_.place })
Check 'E-C5 with a library DB: the same method is a hit of place library, after the project one' (($pi.IndexOf('uMain.TfrmMain.CustomerNameChanged@project') -ge 0) -and ($pi.IndexOf('uMain.TfrmMain.CustomerNameChanged@library') -gt $pi.IndexOf('uMain.TfrmMain.CustomerNameChanged@project')) -and ($r.err -notmatch 'library:')) "(err: $($r.err.Trim()))"

# ---- E-D the life of the copy -------------------------------------------------------------
$r = Run-Concept $A 'customer name' @('--project', $dproj)
$rp = @($r.json.places | Where-Object { $_.place -eq 'repository' }) | Select-Object -First 1
Check 'E-D1 right after index --project the copy is NOT stale (size and mtime as the index stored them)' (($r.err -match '(?m)^repository: copy from \d{4}-\d\d-\d\d \d\d:\d\d of ') -and ($r.err -notmatch 'is stale') -and $rp -and ($rp.stale -eq $false)) "(err: $($r.err.Trim()))"
$r = Run-Concept $N 'client name'
$h = Hit-Of $r 'CUSTOMERS.NAME'
Check 'E-D2 no repository: exit 0, stderr "repository: not configured", no repository hit' (($r.rc -eq 0) -and ($r.err -match '(?m)^repository: not configured') -and (@($r.hits | Where-Object { $_.place -eq 'repository' }).Count -eq 0)) "(rc $($r.rc); err: $($r.err.Trim()))"
Check 'E-D2 the DisplayLabel still finds the field as a dfm-caption hit: place project, tier 2, its DFM file, its link' ($h -and ($h.kind -eq 'dfm-caption') -and ($h.place -eq 'project') -and ($h.tier -eq 2) -and ($h.file -like '*uMain.dfm') -and ($h.line -gt 0) -and ($h.links.persistentFields.count -eq 1)) "(kind $($h.kind) place $($h.place) file $($h.file))"

# E-B3 code links. They are derived from call_literal_args, which only an engine with the 1.56
# literal-argument emitter (lane EXT-A1) fills. Without it the three rows are seeded here, as
# run_v156_CONI.ps1 I12 does, and the DERIVATION + the query are what is proven.
$seed = @'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
have = con.execute("SELECT COUNT(*) FROM call_literal_args WHERE callee_name IN ('FieldByName', 'FindField')").fetchone()[0]
if have == 0:
    def fid(name):
        return con.execute("SELECT id FROM files WHERE lower(path) LIKE ?", ('%' + name,)).fetchone()[0]
    def sym(name):
        return con.execute("SELECT id FROM symbols WHERE name = ? AND kind IN ('method', 'procedure', 'function') ORDER BY id", (name,)).fetchone()[0]
    rows = [(fid('umain.pas'), 0, sym('CustomerNameChanged'), 40, 24, 'FieldByName', 'qryCustomers', 1, 1, 40, 36, 'string', 'NAME'),
            (fid('umain.pas'), 1, sym('CustomerNameChanged'), 42, 26, 'FindField', 'tblSuppliers', 1, 1, 42, 36, 'string', 'NAME'),
            (fid('utools.pas'), 0, sym('CopyName'), 13, 7, 'FieldByName', 'pDs', 1, 1, 13, 19, 'string', 'NAME')]
    con.executemany("INSERT INTO call_literal_args (file_id, ordinal, symbol_id, call_line, call_col, callee_name, receiver_text, arg_index, arg_count, lit_line, lit_col, lit_kind, value) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)
    con.commit()
print('seeded' if have == 0 else 'emitted')
con.close()
'@
$sd = Run-Py $seed @($A)
$how = $sd.out.Trim()
Check "E-B3 setup: call_literal_args has the FieldByName rows ($how)" (($sd.rc -eq 0) -and ($how -in 'seeded', 'emitted')) "($($sd.out))"
Edit-File (Join-Path $app 'uJoin.dfm') "Caption = 'Join'" "Caption = 'Join 2'"
$ix2 = Run @('index', '--project', $dproj, '--db', $A)
Check 'E-B3 setup: the re-index derives the links again and leaves the repository copy alone' (($ix2.rc -eq 0) -and ($ix2.out -match '(?m)^concepts: \d+ project texts') -and ($ix2.out -match '(?m)^repository: unchanged')) "$(($ix2.out -split "`n" | Select-Object -Last 4) -join ' | ')"
$r = Run-Concept $A 'name' @('--kind', 'repo-field')
$c = Hit-Of $r 'CUSTOMERS.NAME'
$s = Hit-Of $r 'SUPPLIERS.NAME'
$cc = if ($c) { @($c.links.code.rows | Where-Object { $_.via -eq 'FieldByName' }) } else { @() }
$sc = if ($s) { @($s.links.code.rows | Where-Object { $_.via -eq 'FindField' }) } else { @() }
Check "E-B3 code ($how): qryCustomers.FieldByName(NAME) is under CUSTOMERS.NAME, in TfrmMain.CustomerNameChanged of uMain.pas" (($cc.Count -eq 1) -and ($cc[0].in -like '*TfrmMain.CustomerNameChanged') -and ($cc[0].file -like '*uMain.pas') -and ($cc[0].line -gt 0)) "(rows $($cc.Count); code.count $($c.links.code.count))"
Check "E-B3 code ($how): tblSuppliers.FindField(NAME) is under SUPPLIERS.NAME and not under CUSTOMERS.NAME" (($sc.Count -eq 1) -and (@($c.links.code.rows | Where-Object { $_.via -eq 'FindField' }).Count -eq 0) -and (@($s.links.code.rows | Where-Object { $_.via -eq 'FieldByName' }).Count -eq 0)) "(rows $($sc.Count))"
$cb = if ($c) { $c.links.codeByNameOnly } else { $null }
$sb = if ($s) { $s.links.codeByNameOnly } else { $null }
Check "E-B3 by name only ($how): pDs.FieldByName(NAME) of uTools.CopyName stands under BOTH NAME fields, candidateTables 2, in neither code list" ($cb -and $sb -and ($cb.count -eq 1) -and ($sb.count -eq 1) -and ($cb.candidateTables -eq 2) -and ($cb.rows[0].receiver -eq 'pDs') -and ($cb.rows[0].in -like '*CopyName') -and (@($c.links.code.rows | Where-Object { $_.file -like '*uTools.pas' }).Count -eq 0)) "(c $($cb.count) s $($sb.count) tables $($cb.candidateTables))"
$t = Run-Concept $A 'customer name' -Text
$all = $t.out -join "`n"
Check 'E-B3 text: the counts line and the code / by name only rows' (($all -match '(?m)^       persistent fields 1, grid columns 2, edit controls 1, forms 1, code \d+, by name only 1 \(2 tables\)$') -and ($all -match '(?m)^         code              uMain\.TfrmMain\.CustomerNameChanged   .+uMain\.pas:\d+   FieldByName$') -and ($all -match '(?m)^         by name only      uTools\.CopyName   .+uTools\.pas:\d+   pDs\.FieldByName$'))

# E-D3..D5: the repository changes after the copy.
Start-Sleep -Milliseconds 1200
Edit-File $backup 'DISPLAY_LABEL=Customer name' 'DISPLAY_LABEL=Buyer name'
$rr = Run @('repo', 'restore', '--in', $backup, '--repo', $dlrepo, '--replace')
$r = Run-Concept $A 'customer name' @('--project', $dproj)
$rp = @($r.json.places | Where-Object { $_.place -eq 'repository' }) | Select-Object -First 1
Check 'E-D3 changed repository file: ONE stderr note "repository: copy from <when> is stale (<path> changed since); refresh: drag-lint index --project <dproj> --db <db>"' (($rr.rc -eq 0) -and ($r.err.Contains("is stale ($dlrepo changed since); refresh: drag-lint index --project $dproj --db $A")) -and (@($r.err -split "`n" | Where-Object { $_ -like 'repository:*' }).Count -eq 1) -and $rp -and ($rp.stale -eq $true)) "(restore $($rr.rc); err: $($r.err.Trim()))"
Check 'E-D3 the stale copy still answers with the OLD caption' (((First-Hit $r).qname -eq 'CUSTOMERS.NAME') -and ((First-Hit $r).field.caption -ceq 'Customer name'))
$r = Run-Concept $A 'buyer name'
$h = Hit-Of $r 'CUSTOMERS.NAME'
Check 'E-D4 control: before the re-index the NEW caption "buyer name" is not a caption-tier hit' ((-not $h) -or ($h.tier -gt 2)) "(tier $($h.tier))"
$ix3 = Run @('index', '--project', $dproj, '--db', $A)
$r = Run-Concept $A 'buyer name'
$h = First-Hit $r
Check 'E-D5 after index --project: copied again, "buyer name" finds CUSTOMERS.NAME in tier 2 by caption, no stale note' (($ix3.out -match '(?m)^repository: copied 6 fields') -and $h -and ($h.qname -eq 'CUSTOMERS.NAME') -and ($h.tier -eq 2) -and (@($h.matched) -contains 'caption') -and ($h.field.caption -ceq 'Buyer name') -and ($r.err -notmatch 'is stale')) "(first $($h.qname) tier $($h.tier); err: $($r.err.Trim()))"
$r = Run-Concept $A 'customer name'
$h = Hit-Of $r 'CUSTOMERS.NAME'
Check 'E-D5 and "customer name" is no caption-tier hit any more (the old caption is gone from the copy)' ((-not $h) -or (($h.tier -gt 2) -and ($h.field.caption -ceq 'Buyer name'))) "(tier $($h.tier) caption $($h.field.caption))"

# E-D6 / E-D7: an index with no repo_copy row. Two different causes, two different notes.
$D = Join-Path $work 'dirscan.sqlite'
$dx = Run @('index', $nor, '--db', $D)
$r = Run-Concept $D 'customer name' @('--project', $dproj)
$rp = @($r.json.places | Where-Object { $_.place -eq 'repository' }) | Select-Object -First 1
Check 'E-D6 directory-scan index: note "repository: not copied (this index was made by a directory scan ...)", state not-copied-yet, symbol hits answer' (($dx.rc -eq 0) -and ($r.rc -eq 0) -and ($r.err -match '(?m)^repository: not copied \(this index was made by a directory scan and has no project file\); repository hits need a project index: drag-lint index --project ') -and $rp -and ($rp.state -eq 'not-copied-yet') -and (@($r.hits | Where-Object { $_.place -eq 'project' }).Count -ge 1)) "(index rc $($dx.rc); err: $($r.err.Trim()))"
Check 'E-D6 it neither says "made before 1.56" nor tells the user to run index --project INTO the directory-scan DB' (($r.err -notmatch 'made before 1\.56') -and (-not $r.err.Contains("--db $D")) -and ($rp.note -notmatch '--db')) "(err: $($r.err.Trim()))"
$O = Join-Path $work 'pre156.sqlite'
[IO.File]::Copy($N, $O, $true)
$del = Run-Py "import sqlite3, sys`ncon = sqlite3.connect(sys.argv[1])`ncon.execute('DELETE FROM repo_copy')`ncon.commit()`nprint(con.execute('SELECT COUNT(*) FROM repo_copy').fetchone()[0])`ncon.close()`n" @($O)
$r = Run-Concept $O 'customer name' @('--project', $dproj)
Check 'E-D7 control: a PROJECT index with no repo_copy row keeps the 1.56 note and its index --project --db advice' (($del.rc -eq 0) -and ($del.out.Trim() -eq '0') -and ($r.err.Contains("repository: not copied yet (index made before 1.56); run: drag-lint index --project $dproj --db $O"))) "(py $($del.out); err: $($r.err.Trim()))"

if (-not $KeepScratch) { try { [IO.Directory]::Delete($work, $true) } catch { } } else { Write-Host "scratch: $work" }
Write-Host ("run_v156_CONQ_e2e: {0} pass, {1} fail" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $(if ($script:fail) { 1 } else { 0 })
