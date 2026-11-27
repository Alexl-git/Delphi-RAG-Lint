<#
  run_v156_CONQ.ps1 -- drag-lint 1.56 lane CON-Q: `query --concept` over three places
  (src\query\DRagLint.Query.ConceptRepo.pas; design
  docs\superpowers\specs\2026-11-27-three-place-search-caption-concepts-design.md 1.3-1.6, 2.6-2.8).

  The fixture tests\fixtures\v156\CON-Q\app is indexed into a scratch DB; fill_concept.py then
  HAND-FILLS repo_copy / concept_fields / concept_texts / concept_links (the copy step of lane
  CON-I is not needed), in the variants app, norepo, manyid, missing.

  Q1  caption words rank a repository field first: place, tier 2, matched (A2)   + --place control
  Q2  a project display label finds the repository field (CC-2, A3)             + other-table control
  Q3  grid caption (A4)          Q4  prose text = tier 3 (A5 control)
  Q5  tier order: exact identifier, caption words, all words elsewhere (CC-4, A7) + inverted control
  Q6  the whole query is a FIELD_NAME / TABLE_NAME = tier 1
  Q7  links of a field (CC-5, A8) + control on the other table
  Q8  by name only (A9)          Q9  by-name row cap and --links (A10)
  Q10 stale copy note + places[].stale (A14) + fresh control
  Q11 no repository: note, exit 0, dfm-caption hit (TS-5, A15)
  Q12 1.55 keys and the 1.55 text line survive (A18)
  Q13 --place usage error / narrowing (A19)     Q14 library place and its note (A20)
  Q15 --kind with the new kinds                 Q16 text detail lines
  Q17 notes: not copied (directory scan), not found at index time; the pre-1.56 note: run_v156_CONQ_e2e.ps1 E-D7
  Q18 unresolved table = ?.FIELD

  Positive control of the whole script: run with -Exe <an engine whose ConceptRepo is the FRAME-1
  stub> -- every check on place / tier / repository hits FAILS.
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7. Needs python (sqlite3 with FTS5) on PATH.
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v156_CONQ: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') { $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path $Exe)) { Write-Host "run_v156_CONQ: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fxSrc = Join-Path $repo 'tests\fixtures\v156\CON-Q'
$work  = Join-Path $env:TEMP ('dl-v156-conq-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}

# One `query --concept` run: exit code, stdout lines, stderr text, parsed JSON ($null in text mode).
function Run-Concept([string]$Db, [string]$Words, [string[]]$More = @(), [switch]$Text) {
  $errFile = Join-Path $work 'stderr.txt'
  $argv = @('query', '--concept', $Words, '--db', $Db) + $More
  if (-not $Text) { $argv += '--json' }
  $out = & { $ErrorActionPreference = 'Continue'; & $Exe @argv 2>$errFile }
  $rc = $LASTEXITCODE
  $json = $null
  if (-not $Text) { try { $json = ($out -join "`n") | ConvertFrom-Json | ForEach-Object { $_ } } catch { $json = $null } }
  $hits = @()
  if ($json -and $json.hits) { $hits = @($json.hits) }
  $errText = ''
  if (Test-Path -LiteralPath $errFile) { $errText = '' + [IO.File]::ReadAllText($errFile) }
  return @{ rc = $rc; out = @($out); err = $errText; json = $json; hits = $hits }
}
function Hit-Of($Run, [string]$QName) { return @($Run.hits | Where-Object { $_.qname -eq $QName }) | Select-Object -First 1 }
function Has-Prop($Obj, [string]$Name) { return ($null -ne $Obj) -and ($Obj.PSObject.Properties.Name -contains $Name) }
# True when the tiers of the hits never go down and the three named hits stand in the given order.
function In-Order($Hits, [string]$First, [string]$Second, [string]$Third) {
  $names = @($Hits | ForEach-Object { $_.qname })
  $a = $names.IndexOf($First); $b = $names.IndexOf($Second); $c = $names.IndexOf($Third)
  return ($a -ge 0) -and ($b -gt $a) -and ($c -gt $b)
}

# ---- build the databases -------------------------------------------------------------------
$app = Join-Path $work 'app'
Copy-Item -Recurse -Force (Join-Path $fxSrc 'app') $app
$base = Join-Path $work 'base.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $app --db $base *> (Join-Path $work 'index.log') }
Check 'setup: the fixture indexes' (($LASTEXITCODE -eq 0) -and (Test-Path $base)) "(rc $LASTEXITCODE)"
$repoFile = Join-Path $work 'App.dlrepo'
[IO.File]::WriteAllText($repoFile, 'stand-in for the repository file: a query only STATs it')
$dbs = @{}
foreach ($v in 'app', 'norepo', 'manyid', 'missing') {
  $dbs[$v] = Join-Path $work "$v.sqlite"
  Copy-Item -Force $base $dbs[$v]
  $fill = & { $ErrorActionPreference = 'Continue'; & python -I (Join-Path $fxSrc 'fill_concept.py') $dbs[$v] $repoFile $v 2>&1 | ForEach-Object { "$_" } }
  Check "setup: variant $v filled" ($LASTEXITCODE -eq 0) "($fill)"
}
$libDir = Join-Path $work 'lib'
New-Item -ItemType Directory -Force $libDir | Out-Null
$libDb = Join-Path $libDir 'library-Win64.sqlite'
Copy-Item -Force $base $libDb
$A = $dbs['app']

# ---- Q1 ------------------------------------------------------------------------------------
$r = Run-Concept $A 'customer name'
$h = $r.hits | Select-Object -First 1
Check 'Q1 "customer name": rank 1 is the repository field CUSTOMERS.NAME' (($r.rc -eq 0) -and $h -and ($h.qname -eq 'CUSTOMERS.NAME') -and ($h.kind -eq 'repo-field')) "(rc $($r.rc), first $($h.qname))"
Check 'Q1 it carries place = repository, tier = 2, matched has caption' ($h -and ($h.place -eq 'repository') -and ($h.tier -eq 2) -and (@($h.matched) -contains 'caption')) "(place $($h.place) tier $($h.tier) matched $(@($h.matched) -join ','))"
Check 'Q1 the symbol hit CustomerNameChanged follows with place = project, tier 3' ([bool](@($r.hits | Where-Object { ($_.qname -like '*CustomerNameChanged') -and ($_.place -eq 'project') -and ($_.tier -eq 3) }).Count))
$r2 = Run-Concept $A 'customer name' @('--place', 'project,library')
Check 'Q1 control: --place project,library has no repo-field hit and still has CustomerNameChanged' ((@($r2.hits | Where-Object { $_.kind -eq 'repo-field' }).Count -eq 0) -and (@($r2.hits | Where-Object { $_.qname -like '*CustomerNameChanged' }).Count -eq 1)) "(hits $($r2.hits.Count))"

# ---- Q2 ------------------------------------------------------------------------------------
$r = Run-Concept $A 'client name'
$h = $r.hits | Select-Object -First 1
Check 'Q2 "client name" finds CUSTOMERS.NAME through display-label; field.caption is the repository caption' ($h -and ($h.qname -eq 'CUSTOMERS.NAME') -and (@($h.matched) -contains 'display-label') -and ($h.field.caption -eq 'Customer name') -and ($h.place -eq 'repository')) "(first $($h.qname), matched $(@($h.matched) -join ','))"
$r = Run-Concept $A 'supplier name'
$h = $r.hits | Select-Object -First 1
$other = Hit-Of $r 'CUSTOMERS.NAME'
Check 'Q2 control: "supplier name" ranks SUPPLIERS.NAME first; CUSTOMERS.NAME is not a caption-tier hit' ($h -and ($h.qname -eq 'SUPPLIERS.NAME') -and ($h.tier -eq 2) -and ((-not $other) -or ($other.tier -gt 2))) "(first $($h.qname), other tier $($other.tier))"

# ---- Q3 / Q4 -------------------------------------------------------------------------------
$r = Run-Concept $A 'cust name'
$h = Hit-Of $r 'CUSTOMERS.NAME'
Check 'Q3 "cust name" finds CUSTOMERS.NAME in tier 2 through grid-caption' ($h -and ($h.tier -eq 2) -and (@($h.matched) -contains 'grid-caption')) "(tier $($h.tier), matched $(@($h.matched) -join ','))"
$r = Run-Concept $A 'legal name buyer'
$h = Hit-Of $r 'CUSTOMERS.NAME'
Check 'Q4 "legal name buyer" finds CUSTOMERS.NAME in tier 3 through description; allTerms true' ($h -and ($h.tier -eq 3) -and (@($h.matched) -contains 'description') -and ($h.allTerms -eq $true)) "(tier $($h.tier), matched $(@($h.matched) -join ','))"

# ---- Q5 ------------------------------------------------------------------------------------
$r = Run-Concept $A 'limit'
$tiers = @($r.hits | ForEach-Object { [int]$_.tier })
$sorted = $true
for ($i = 1; $i -lt $tiers.Count; $i++) { if ($tiers[$i] -lt $tiers[$i - 1]) { $sorted = $false } }
$exact = @($r.hits | Where-Object { $_.qname -like '*TfrmMain.Limit' }) | Select-Object -First 1
$cap = Hit-Of $r 'CUSTOMERS.CREDIT_LIMIT'
$fuzzy = @($r.hits | Where-Object { $_.qname -like '*CreditLimitChanged' }) | Select-Object -First 1
Check 'Q5 "limit": the symbol named Limit is tier 1, the caption hit tier 2, CreditLimitChanged tier 3' ($exact -and $cap -and $fuzzy -and ($exact.tier -eq 1) -and ($exact.place -eq 'project') -and ($cap.tier -eq 2) -and ($fuzzy.tier -eq 3)) "(tiers $($exact.tier),$($cap.tier),$($fuzzy.tier))"
Check 'Q5 tiers never go down; exact identifier < caption hit < fuzzy identifier' ($sorted -and ($tiers.Count -ge 3) -and (In-Order $r.hits 'uMain.TfrmMain.Limit' 'CUSTOMERS.CREDIT_LIMIT' 'uMain.TfrmMain.CreditLimitChanged')) "(tiers $($tiers -join ','))"
Check 'Q5 control: the same check with the expected order inverted is RED' (-not (In-Order $r.hits 'uMain.TfrmMain.CreditLimitChanged' 'CUSTOMERS.CREDIT_LIMIT' 'uMain.TfrmMain.Limit'))
Check 'Q5 a hit appears once (the tier-1 symbol is not repeated in tier 3)' (@($r.hits | Where-Object { $_.qname -like '*TfrmMain.Limit' }).Count -eq 1)
Check 'Q5 count / allTermsCount agree with the hits; tier 1 and 2 have score 0' (($r.json.count -eq $r.hits.Count) -and ($r.json.allTermsCount -eq @($r.hits | Where-Object { $_.tier -le 3 }).Count) -and ($exact.score -eq 0) -and ($cap.score -eq 0) -and ($fuzzy.score -gt 0))
$r = Run-Concept $A 'name'
$t1 = @($r.hits | Where-Object { $_.tier -eq 1 } | ForEach-Object { $_.qname })
Check 'Q5 "name": tier 1 = the symbol Name (project), then the fields NAMED name (repository), by qname' (($t1.Count -eq 3) -and ($t1[0] -eq 'uMain.TfrmMain.Name') -and ($t1[1] -eq 'CUSTOMERS.NAME') -and ($t1[2] -eq 'SUPPLIERS.NAME')) "($($t1 -join ' | '))"
$r = Run-Concept $A 'credit limit' @('--kind', 'repo-field')
$t2 = @($r.hits | Where-Object { $_.tier -eq 2 } | ForEach-Object { $_.qname })
Check 'Q5 tier-2 sub-order: the caption that IS the query stands before one holding the words in any order' (($t2.Count -eq 2) -and ($t2[0] -eq 'CUSTOMERS.CREDIT_LIMIT') -and ($t2[1] -eq 'ACCOUNTS.MAX_CREDIT')) "($($t2 -join ' | '))"
$r = Run-Concept $A 'legal name'
$h = Hit-Of $r 'CUSTOMERS.NAME'
Check 'Q5 words spread over prose only: "legal name" is tier 3 (description + hint hold both words), never tier 2' ($h -and ($h.tier -eq 3))

# ---- Q6 ------------------------------------------------------------------------------------
$r = Run-Concept $A 'credit_limit'
$h = $r.hits | Select-Object -First 1
Check 'Q6 "credit_limit" (a FIELD_NAME): tier 1 repo-field, matched has name' ($h -and ($h.qname -eq 'CUSTOMERS.CREDIT_LIMIT') -and ($h.tier -eq 1) -and (@($h.matched) -contains 'name') -and ($h.score -eq 0)) "(first $($h.qname) tier $($h.tier))"
$r = Run-Concept $A 'customers'
$h = Hit-Of $r 'CUSTOMERS'
Check 'Q6 "customers" (a TABLE_NAME): tier 1 repo-table, no links key' ($h -and ($h.kind -eq 'repo-table') -and ($h.tier -eq 1) -and -not (Has-Prop $h 'links')) "(kind $($h.kind) tier $($h.tier))"

# ---- Q7 / Q8 -------------------------------------------------------------------------------
$r = Run-Concept $A 'name' @('--kind', 'repo-field')
$c = Hit-Of $r 'CUSTOMERS.NAME'
$s = Hit-Of $r 'SUPPLIERS.NAME'
$cl = $c.links
Check 'Q7 links of CUSTOMERS.NAME: 1 persistent field, 1 grid column, 1 edit control, 1 form' ($cl -and ($cl.persistentFields.count -eq 1) -and ($cl.gridColumns.count -eq 1) -and ($cl.editControls.count -eq 1) -and ($cl.forms.count -eq 1) -and ($cl.forms.rows[0].class -eq 'TfrmMain')) "(pf $($cl.persistentFields.count) grid $($cl.gridColumns.count) edit $($cl.editControls.count) forms $($cl.forms.count))"
$vias = @($cl.code.rows | ForEach-Object { $_.via })
Check 'Q7 code holds the FieldByName row and the persistent-field row, both in TfrmMain.Save' (($vias -contains 'FieldByName') -and ($vias -contains 'persistent-field') -and (@($cl.code.rows | Where-Object { $_.in -notlike '*TfrmMain.Save' }).Count -eq 0)) "(vias $($vias -join ','); count $($cl.code.count))"
Check 'Q7 the persistent-field row names form, component, dataset, caption, via' ($cl -and ($cl.persistentFields.rows[0].component -eq 'qryCustomersNAME') -and ($cl.persistentFields.rows[0].form -eq 'frmMain') -and ($cl.persistentFields.rows[0].dataset -eq 'qryCustomers') -and ($cl.persistentFields.rows[0].caption -eq 'Client name') -and ($cl.persistentFields.rows[0].via -eq 'sql') -and ($cl.persistentFields.rows[0].line -gt 0))
Check 'Q7 control: SUPPLIERS.NAME has code.count 0 and 1 persistent field via origin' ($s -and ($s.links.code.count -eq 0) -and ($s.links.persistentFields.count -eq 1) -and ($s.links.persistentFields.rows[0].via -eq 'origin'))
$cb = $cl.codeByNameOnly
$sb = $s.links.codeByNameOnly
Check 'Q8 pDs.FieldByName(NAME) is by name only under BOTH NAME fields, candidateTables 2' ($cb -and $sb -and ($cb.count -eq 1) -and ($sb.count -eq 1) -and ($cb.candidateTables -eq 2) -and ($cb.rows[0].receiver -eq 'pDs') -and ($cb.rows[0].in -like '*CopyName') -and ($sb.rows[0].file -like '*uTools.pas')) "(c $($cb.count) s $($sb.count) tables $($cb.candidateTables))"
Check 'Q8 and it is in neither code list' ((@($cl.code.rows | Where-Object { $_.file -like '*uTools.pas' }).Count -eq 0) -and (@($s.links.code.rows).Count -eq 0))
Check 'Q8 texts[] lists the repository caption first, then the project texts with uses' ($c -and ($c.texts[0].kind -eq 'caption') -and ($c.texts[0].place -eq 'repository') -and (@($c.texts | Where-Object { ($_.kind -eq 'display-label') -and ($_.uses -eq 2) -and ($_.place -eq 'project') }).Count -eq 1))

# ---- Q9 ------------------------------------------------------------------------------------
$M = $dbs['manyid']
$r = Run-Concept $M 'id' @('--kind', 'repo-field')
$h = Hit-Of $r 'CUSTOMERS.ID'
Check 'Q9 ID is in 8 tables: by name only shows the count 4 and rows []' ($h -and ($h.links.codeByNameOnly.count -eq 4) -and ($h.links.codeByNameOnly.candidateTables -eq 8) -and (@($h.links.codeByNameOnly.rows).Count -eq 0)) "(count $($h.links.codeByNameOnly.count) tables $($h.links.codeByNameOnly.candidateTables) rows $(@($h.links.codeByNameOnly.rows).Count))"
$r = Run-Concept $M 'id' @('--kind', 'repo-field', '--links', '3')
$h = Hit-Of $r 'CUSTOMERS.ID'
Check 'Q9 control: --links 3 prints 3 of the 4 rows' ($h -and (@($h.links.codeByNameOnly.rows).Count -eq 3) -and ($h.links.codeByNameOnly.count -eq 4))
$r = Run-Concept $A 'customer name' @('--links', '0')
$h = Hit-Of $r 'CUSTOMERS.NAME'
Check 'Q9 --links 0 = counts only' ($h -and ($h.links.persistentFields.count -eq 1) -and (@($h.links.persistentFields.rows).Count -eq 0) -and (@($h.links.code.rows).Count -eq 0) -and ($h.links.code.count -eq 2))
$r = Run-Concept $A 'customer name' @('--links', 'x')
Check 'Q9 --links x is a usage error (exit 2)' (($r.rc -eq 2) -and (($r.out -join ' ') -match 'ERROR: --links'))

# ---- Q10 (changes the stand-in repository file: keep it after the queries that need a fresh copy) ----
$r = Run-Concept $A 'customer name'
$rp = @($r.json.places | Where-Object { $_.place -eq 'repository' }) | Select-Object -First 1
Check 'Q10 control: fresh copy -- note "repository: copy from <when> of <path>", stale false, no "is stale"' (($r.err -match '(?m)^repository: copy from \d{4}-\d\d-\d\d \d\d:\d\d of ') -and ($r.err -notmatch 'is stale') -and $rp -and ($rp.stale -eq $false) -and ($rp.state -eq 'copied') -and ($rp.path -eq $repoFile) -and (($rp.copiedAt -is [datetime]) -or ($rp.copiedAt -match '^\d{4}-\d\d-\d\dT'))) "(err: $($r.err.Trim()))"
Check 'Q10 the JSON on stdout carries no note line' (($r.out -join "`n") -notmatch '(?m)^repository:')
$libNote = Run-Concept $A 'customer name' @('--place', 'project')
Check 'Q10 a place narrowed out prints no note and reads state skipped' (($libNote.err -notmatch 'repository:') -and ($libNote.err -notmatch 'library:') -and (@($libNote.json.places | Where-Object { $_.state -eq 'skipped' }).Count -eq 2)) "(err: $($libNote.err))"

# ---- Q12 (1.55 shape) ----------------------------------------------------------------------
$keys155 = 'rank', 'qname', 'kind', 'file', 'line', 'score', 'matched', 'allTerms'
$sym = @($r.hits | Where-Object { $_.qname -like '*CustomerNameChanged' }) | Select-Object -First 1
$missing = @($keys155 | Where-Object { -not (Has-Prop $sym $_) })
Check 'Q12 every 1.55 key of a hit is present with its type' ($sym -and ($missing.Count -eq 0) -and ($sym.rank -is [long] -or $sym.rank -is [int]) -and ($sym.qname -is [string]) -and ($sym.matched -is [array]) -and ($sym.allTerms -is [bool]) -and (Has-Prop $r.json 'query') -and (Has-Prop $r.json 'count') -and (Has-Prop $r.json 'allTermsCount')) "(missing: $($missing -join ','))"
$t = Run-Concept $A 'customer name' -Text
$symLine = @($t.out | Where-Object { $_ -like '*CustomerNameChanged*' }) | Select-Object -First 1
$re155 = '^  \d+  \d+[.,]\d\d  \S+\s+\S+   .+:\d+   \[[a-z,]+\]$'
Check 'Q12 the text line of a symbol hit ends with " place=project"' ([bool]($symLine -match ' place=project$')) "($symLine)"
Check 'Q12 and matches the 1.55 line once that token is removed' ([bool](($symLine -replace ' place=project$', '') -match $re155))
Check 'Q12 the header line is the 1.55 one' ([bool]($t.out[0] -match '^concept "customer name": \d+ hit\(s\) \(\d+ match every word\)$')) "($($t.out[0]))"

# ---- Q16 (text detail lines) ---------------------------------------------------------------
$all = $t.out -join "`n"
Check 'Q16 text: the repo-field line and its caption line' (($all -match '(?m)^  1  0[.,]00  repo-field CUSTOMERS\.NAME   .+App\.dlrepo:0   \[caption,.*\] place=repository$') -and ($all -match '(?m)^       caption "Customer name"  VARCHAR\(40\)   also shown as: "Client name" \(2\), "Cust\. name" \(1\)$'))
Check 'Q16 text: the counts line' ([bool]($all -match '(?m)^       persistent fields 1, grid columns 1, edit controls 1, forms 1, code 2, by name only 1 \(2 tables\)$'))
Check 'Q16 text: link rows (persistent-field, grid-column, code, by name only)' (($all -match '(?m)^         persistent-field  frmMain\.qryCustomersNAME   .+uMain\.dfm:\d+$') -and ($all -match '(?m)^         grid-column       frmMain\.colName   ') -and ($all -match '(?m)^         code              uMain\.TfrmMain\.Save   .+uMain\.pas:\d+   FieldByName$') -and ($all -match '(?m)^         by name only      uTools\.CopyName   .+uTools\.pas:\d+   pDs\.FieldByName$'))

# ---- Q13 -----------------------------------------------------------------------------------
$r = Run-Concept $A 'customer name' @('--place', 'bogus')
Check 'Q13 --place bogus: exit 2 and the usage error' (($r.rc -eq 2) -and (($r.out -join ' ') -match 'ERROR: --place accepts library, project, repository')) "(rc $($r.rc))"
$r = Run-Concept $A 'name' @('--place', 'repository')
Check 'Q13 control: --place repository exits 0 with only place = repository hits' (($r.rc -eq 0) -and ($r.hits.Count -ge 2) -and (@($r.hits | Where-Object { $_.place -ne 'repository' }).Count -eq 0)) "(hits $($r.hits.Count))"

# ---- Q14 -----------------------------------------------------------------------------------
$r = Run-Concept $A 'customer name' @('--db', $libDb)
$lp = @($r.json.places | Where-Object { $_.place -eq 'library' }) | Select-Object -First 1
Check 'Q14 with a library DB a symbol hit from it has place = library; places[] reads ok' ((@($r.hits | Where-Object { ($_.place -eq 'library') -and ($_.qname -like '*CustomerNameChanged') }).Count -eq 1) -and $lp -and ($lp.state -eq 'ok') -and ($lp.db -eq $libDb) -and ($r.err -notmatch 'library:')) "(err: $($r.err.Trim()))"
$pi = @($r.hits | ForEach-Object { $_.qname + '@' + $_.place })
Check 'Q14 tie-break: the project hit stands before the library hit of the same name' ($pi.IndexOf('uMain.TfrmMain.CustomerNameChanged@project') -lt $pi.IndexOf('uMain.TfrmMain.CustomerNameChanged@library') -and ($pi.IndexOf('uMain.TfrmMain.CustomerNameChanged@project') -ge 0))
$r = Run-Concept $A 'customer name'
$lp = @($r.json.places | Where-Object { $_.place -eq 'library' }) | Select-Object -First 1
Check 'Q14 with none: stderr "library: not configured", state not-configured, no library hit' (($r.err -match '(?m)^library: not configured') -and $lp -and ($lp.state -eq 'not-configured') -and (@($r.hits | Where-Object { $_.place -eq 'library' }).Count -eq 0))

# ---- Q15 -----------------------------------------------------------------------------------
$r = Run-Concept $A 'name' @('--kind', 'repo-field')
Check 'Q15 --kind repo-field: only repo-field hits' (($r.hits.Count -ge 2) -and (@($r.hits | Where-Object { $_.kind -ne 'repo-field' }).Count -eq 0))
$r = Run-Concept $A 'customer name' @('--kind', 'method')
Check 'Q15 control: --kind method has CustomerNameChanged and no repository hit' ((@($r.hits | Where-Object { $_.qname -like '*CustomerNameChanged' }).Count -eq 1) -and (@($r.hits | Where-Object { $_.place -eq 'repository' }).Count -eq 0))

# ---- Q11 / Q18 -----------------------------------------------------------------------------
$N = $dbs['norepo']
$r = Run-Concept $N 'client name'
$h = Hit-Of $r 'CUSTOMERS.NAME'
Check 'Q11 no repository: stderr "repository: not configured", exit 0' (($r.rc -eq 0) -and ($r.err -match '(?m)^repository: not configured'))
Check 'Q11 the caption is a dfm-caption hit with place = project, tier 2, and its DFM file' ($h -and ($h.kind -eq 'dfm-caption') -and ($h.place -eq 'project') -and ($h.tier -eq 2) -and ($h.file -like '*uMain.dfm') -and ($h.line -gt 0) -and ($h.links.persistentFields.count -eq 1)) "(kind $($h.kind) place $($h.place) file $($h.file))"
$r = Run-Concept $A 'client name'
Check 'Q11 control: the same query on app has no "not configured" repository line' ($r.err -notmatch 'repository: not configured')
$r = Run-Concept $A 'phone number'
$h = $r.hits | Select-Object -First 1
Check 'Q18 a caption whose table is not resolved is ?.PHONE, dfm-caption, place project, with its by-name link' ($h -and ($h.qname -eq '?.PHONE') -and ($h.kind -eq 'dfm-caption') -and ($h.place -eq 'project') -and ($h.links.persistentFields.count -eq 1)) "(first $($h.qname))"
$r = Run-Concept $A 'summary remarks'
Check 'Q18 words no text holds give no repository hit' (@($r.hits | Where-Object { $_.place -eq 'repository' }).Count -eq 0)

# ---- Q17 -----------------------------------------------------------------------------------
$r = Run-Concept $base 'customer name'
$rp = @($r.json.places | Where-Object { $_.place -eq 'repository' }) | Select-Object -First 1
Check 'Q17 no repo_copy row in a directory-scan index: "repository: not copied (this index was made by a directory scan ...", state not-copied-yet, symbol hits still answer' (($r.rc -eq 0) -and ($r.err -match '(?m)^repository: not copied \(this index was made by a directory scan and has no project file\); repository hits need a project index: drag-lint index --project ') -and ($r.err -notmatch 'made before 1\.56') -and $rp -and ($rp.state -eq 'not-copied-yet') -and (@($r.hits | Where-Object { $_.place -eq 'project' }).Count -ge 1)) "(err: $($r.err.Trim()))"
$r = Run-Concept $dbs['missing'] 'customer name'
Check 'Q17 state missing: "repository: not found at index time: <path>"' ([bool]($r.err -match '(?m)^repository: not found at index time: .+App\.dlrepo'))
$r = Run-Concept $A 'zzzqqq nothing'
Check 'Q17 no hit anywhere: exit 1, count 0' (($r.rc -eq 1) -and ($r.json.count -eq 0))

# ---- Q10 stale (last: it changes the stand-in repository file) -----------------------------
[IO.File]::AppendAllText($repoFile, ' -- changed after the copy')
$r = Run-Concept $A 'customer name' @('--project', 'C:\P\App.dproj')
$rp = @($r.json.places | Where-Object { $_.place -eq 'repository' }) | Select-Object -First 1
Check 'Q10 changed file: stderr "repository: copy from ... is stale ...; refresh: drag-lint index --project C:\P\App.dproj --db <db>"' (($r.err -match '(?m)^repository: copy from .+ is stale \(.+App\.dlrepo changed since\); refresh: drag-lint index --project C:\\P\\App\.dproj --db ') -and $rp -and ($rp.stale -eq $true) -and ($rp.note -like 'repository: copy from*is stale*')) "(err: $($r.err.Trim()))"
Check 'Q10 the stale copy still answers' ((($r.hits | Select-Object -First 1).qname) -eq 'CUSTOMERS.NAME')
Check 'Q10 exactly one repository note line' (@($r.err -split "`n" | Where-Object { $_ -like 'repository:*' }).Count -eq 1)
[IO.File]::Delete($repoFile)
$r = Run-Concept $A 'customer name'
Check 'Q10 file gone: "repository: copy from <when>; <path> no longer exists"' ([bool]($r.err -match '(?m)^repository: copy from .+; .+App\.dlrepo no longer exists'))

if (-not $KeepScratch) { try { [IO.Directory]::Delete($work, $true) } catch { } } else { Write-Host "scratch: $work" }
Write-Host ("run_v156_CONQ: {0} pass, {1} fail" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $(if ($script:fail) { 1 } else { 0 })
