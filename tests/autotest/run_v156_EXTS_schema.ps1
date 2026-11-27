<#
  run_v156_EXTS_schema.ps1 -- 1.56 lane EXT-S (S1): the store seam of the ONE 1.56 extractor bump.

  Indexes tests\fixtures\v156-exts (two Pascal units, four routine bodies) into scratch DBs and
  checks, through `sql --json` (rows are POSITIONAL arrays; mapped onto columns[].name below):
    T1  the nine 1.56 tables exist after a fresh index (Migrate created them), and the FTS5
        mirror concept_texts_fts.
    T2  their columns are exactly the spec's, in order (an empty SELECT * reports the list).
    T3  their indexes exist, and (EXT-S2) idx_refs_file_line on refs(file_id, start_line).
    T4  data_flows.val_class and symbol_facts.must_writes exist.
    T5  a plain index run (no emitter is registered in S1) leaves the six fact tables as the
        registered extraction hooks fill them; with -ExpectEmpty all six must hold 0 rows.
    T6  store round trip: with DRAGLINT_TEST_V156_STORE=1 the indexer seeds one row of every
        fact per routine body, writes them (PutExtFacts / PutDataFlows / PutSymbolFacts /
        ReplaceIndirectEdges) and reads them back through the Get* readers; a mismatch fails
        the file. Checked: exit 0, one `v156-store-selfcheck: ok` line per unit, the row counts
        (4 routines), val_class values, one indirect edge. The syx figure is >= the seeded count:
        the parser's own symbol_extras rows (parameters) ride along with the seed.
        symbol_facts.must_writes is NOT seeded (EXT-S2): the value the REAL analysis wrote is
        read back and pinned per routine (Fill = FTotal, the three functions = Result). Control:
        Fill is not 'Result' (the retired seed wrote 'Result' everywhere).
    T7  a SECOND seeded run over a touched unit REPLACES the rows (same counts, no duplicate)
        and the indirect-edges reader sees the edge of run 1.
    T8  (-BaseExe <older engine>) an index built by the older engine is read by this engine
        without DDL (tables still absent after a read verb), and a writer run adds them.
    T9  (EXT-S2) REAL emitters, no seed: an include parsed in two define contexts (hosts XsA with
        COMPILE1, XsB without; the fixture is written into the scratch folder) keeps the parser's
        facts of BOTH contexts -- the `out` parameter of the routine only context 0 declares (pA or
        pB) AND of the routine only context 1 declares each have their symbol_extras row, and the
        string literal of each context's call has its call_literal_args row, once.
        Controls: both context-only routines are indexed (two contexts were parsed); the `var`
        parameter of the routine both contexts declare has its row (the parser emitter is in
        this engine). An engine WITHOUT the parser emitter (a lane branch that has not merged
        EXT-A1) fails that control; pass -NoParserEmitter to skip T9 there, visibly.
  Positive control: run with -Exe <the 1.55 base engine> -- T1-T4, T6, T7 FAIL (no tables).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$BaseExe = '', [switch]$ExpectEmpty, [switch]$NoParserEmitter, [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v156_EXTS_schema: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_v156_EXTS_schema: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fxSrc = Join-Path $repo 'tests\fixtures\v156-exts'
$work  = Join-Path $env:TEMP ('dl-v156-exts-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}

# One SELECT -> array of PSCustomObject (columns by name). A failed query (e.g. no such table on
# an older engine) returns an EMPTY array.
function Lane-Sql([string]$Db, [string]$Query, [string]$With = $Exe) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $With sql --query $Query --db $Db --json 2>$null }
  if ($LASTEXITCODE -ne 0 -or -not $raw) { return }
  try { $j = ($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ } } catch { return }
  $cols = @($j.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($r in @($j.rows)) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $r[$i] }
    $out.Add([pscustomobject]$o)
  }
  return $out.ToArray()
}
# The column list of a table, in order ('' when the table is absent).
function Lane-Cols([string]$Db, [string]$Table) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe sql --query "SELECT * FROM $Table LIMIT 0" --db $Db --json 2>$null }
  if ($LASTEXITCODE -ne 0 -or -not $raw) { return '' }
  try { $j = ($raw -join "`n") | ConvertFrom-Json } catch { return '' }
  return (@($j.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } }) -join ',')
}
function Lane-Count([string]$Db, [string]$From) {
  $r = @(Lane-Sql $Db "SELECT COUNT(*) AS n FROM $From")
  if ($r.Count -eq 1) { return [int]$r[0].n }
  return -1
}
# Index a folder; returns @{ rc; log (text) }. $Seed = run with the store self-check.
function Lane-Index([string]$Dir, [string]$Db, [string]$LogName, [bool]$Seed, [string]$With = $Exe) {
  $log = Join-Path $work $LogName
  if ($Seed) { $env:DRAGLINT_TEST_V156_STORE = '1' }
  try { & { $ErrorActionPreference = 'Continue'; & $With index $Dir --db $Db *> $log } }
  finally { if ($Seed) { $env:DRAGLINT_TEST_V156_STORE = $null } }
  return @{ rc = $LASTEXITCODE; log = (Get-Content -Raw $log) }
}

$factTables    = 'symbol_extras', 'ds_field_accesses', 'loop_facts', 'call_literal_args', 'indirect_edges'
$conceptTables = 'repo_copy', 'concept_fields', 'concept_texts', 'concept_links'
$allTables     = $factTables + $conceptTables

Write-Host "run_v156_EXTS_schema: engine $Exe" -ForegroundColor Cyan

# ---- plain run ----------------------------------------------------------------
$fx1 = Join-Path $work 'plain'; Copy-Item -Recurse $fxSrc $fx1
$db1 = Join-Path $work 'plain.sqlite'
$r1  = Lane-Index $fx1 $db1 'index-plain.log' $false
$nFiles = Lane-Count $db1 'files'
Check 'VACUITY the fixture was indexed' (($r1.rc -eq 0) -and ($nFiles -ge 2)) "(rc $($r1.rc), files $nFiles)"

# ---- T1 -------------------------------------------------------------------------
$in   = ($allTables | ForEach-Object { "'$_'" }) -join ', '
$tabs = @(Lane-Sql $db1 "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ($in) ORDER BY name")
$got  = ($tabs | ForEach-Object name) -join ','
Check 'T1 the nine 1.56 tables exist' ($got -eq (($allTables | Sort-Object) -join ',')) "($got)"
$fts = @(Lane-Sql $db1 "SELECT name FROM sqlite_master WHERE name = 'concept_texts_fts'")
Check 'T1 concept_texts_fts exists (FTS5)' ($fts.Count -eq 1)

# ---- T2 -------------------------------------------------------------------------
$want = [ordered]@{
  'symbol_extras'     = 'symbol_id,file_id,noreturn,variant_part,variant_tag,param_mode,param_index'
  'ds_field_accesses' = 'file_id,symbol_id,ordinal,mode,line,col,shape,dataset_text,field_text,field_name,name_kind,name_text,accessor,root_kind,root_name,root_index,with_ctx,rhs_start_line,rhs_start_col,rhs_end_line,rhs_end_col,stmt_line,stmt_col'
  'loop_facts'        = 'file_id,symbol_id,ordinal,parent,kind,start_line,start_col,end_line,end_col,cond_start_line,cond_start_col,cond_end_line,cond_end_col'
  'call_literal_args' = 'file_id,ordinal,symbol_id,call_line,call_col,callee_name,receiver_text,arg_index,arg_count,lit_line,lit_col,lit_kind,value'
  'indirect_edges'    = 'id,ref_id,caller_symbol_id,target_symbol_id,kind,via_text,bind_file_id,bind_line,bind_col,confidence'
  'repo_copy'         = 'id,state,repo_path,repo_sha256,repo_size,repo_mtime_unix,repo_schema_version,copied_at_unix,checked_at_unix,copy_format,derived_format,derived_at_unix,last_error'
  'concept_fields'    = 'id,table_name,field_name,caption,type_text,field_kind,is_calculated,is_lookup,visible'
  'concept_texts'     = 'id,place,text_kind,table_name,field_name,text,uses'
  'concept_links'     = 'id,link_kind,confidence,table_name,field_name,file_id,line,col,form_name,form_class,component_name,dataset_name,symbol_id,enclosing_symbol_id,via,caption'
}
foreach ($t in $want.Keys) {
  $cols = Lane-Cols $db1 $t
  Check "T2 columns of $t" ($cols -eq $want[$t]) $(if ($cols -ne $want[$t]) { "(got: $cols)" } else { '' })
}

# ---- T3 -------------------------------------------------------------------------
$wantIdx = 'idx_symbol_extras_file', 'idx_ds_field_accesses_sym', 'idx_ds_field_accesses_pos', 'idx_loop_facts_sym',
  'idx_call_literal_args_call', 'idx_call_literal_args_sym', 'idx_call_literal_args_name', 'idx_indirect_edges_ref',
  'idx_indirect_edges_caller', 'idx_indirect_edges_target', 'idx_concept_texts_field', 'idx_concept_links_field',
  'idx_concept_links_file', 'idx_concept_links_symbol', 'idx_concept_links_encl'
$inIdx  = ($wantIdx | ForEach-Object { "'$_'" }) -join ', '
$idx    = @(Lane-Sql $db1 "SELECT name FROM sqlite_master WHERE type = 'index' AND name IN ($inIdx)")
$miss   = @($wantIdx | Where-Object { $_ -notin @($idx | ForEach-Object name) })
Check 'T3 the 15 indexes exist' ($miss.Count -eq 0) $(if ($miss.Count) { "(missing: $($miss -join ', '))" } else { '' })
$refsIdx = @(Lane-Sql $db1 "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'idx_refs_file_line'")
$refsSql = if ($refsIdx.Count -eq 1) { ([string]$refsIdx[0].sql) -replace '\s+', '' } else { '' }
Check 'T3 idx_refs_file_line is on refs(file_id, start_line)' ($refsSql -match 'ONrefs\(file_id,start_line\)$') "($refsSql)"

# ---- T4 -------------------------------------------------------------------------
Check 'T4 data_flows.val_class exists'      ((Lane-Cols $db1 'data_flows') -match '(^|,)val_class$')
Check 'T4 symbol_facts.must_writes exists'  ((Lane-Cols $db1 'symbol_facts') -match '(^|,)must_writes(,|$)')

# ---- T5 -------------------------------------------------------------------------
$plainCounts = @{}
foreach ($t in $factTables) { $plainCounts[$t] = Lane-Count $db1 $t }
$plainText = ($factTables | ForEach-Object { "$_=$($plainCounts[$_])" }) -join ' '
if ($ExpectEmpty) {
  Check 'T5 no emitter registered: the fact tables are empty' (@($factTables | Where-Object { $plainCounts[$_] -ne 0 }).Count -eq 0) "($plainText)"
} else {
  Check 'T5 the fact tables are readable after a plain run' (@($factTables | Where-Object { $plainCounts[$_] -lt 0 }).Count -eq 0) "($plainText)"
}

# ---- T6 store round trip -----------------------------------------------------------
$fx2 = Join-Path $work 'seed'; Copy-Item -Recurse $fxSrc $fx2
$db2 = Join-Path $work 'seed.sqlite'
$r2  = Lane-Index $fx2 $db2 'index-seed-1.log' $true
$okLines = @([regex]::Matches($r2.log, 'v156-store-selfcheck: ok file=(\S+) dfa=(\d+) loops=(\d+) cla=(\d+) syx=(\d+)'))
$perFile = @{}
$perSyx  = @{}
foreach ($m in $okLines) {
  $perFile[$m.Groups[1].Value] = "$($m.Groups[2].Value),$($m.Groups[3].Value),$($m.Groups[4].Value)"
  $perSyx[$m.Groups[1].Value]  = [int]$m.Groups[5].Value
}
# dfa / loops / cla = the seeded count exactly; syx >= it (the parser's parameter rows ride along).
function Seeded-Ok([string]$File, [int]$N) {
  return ($perFile[$File] -eq "$N,$N,$N") -and $perSyx.ContainsKey($File) -and ($perSyx[$File] -ge $N)
}
Check 'T6 seeded run ends with exit 0' ($r2.rc -eq 0) "(rc $($r2.rc))"
Check 'T6 uExtsA.pas read back 3 rows of each fact (syx >= 3)' (Seeded-Ok 'uExtsA.pas' 3) "($($perFile['uExtsA.pas']),$($perSyx['uExtsA.pas']))"
Check 'T6 uExtsB.pas read back 1 row of each fact (syx >= 1)'  (Seeded-Ok 'uExtsB.pas' 1) "($($perFile['uExtsB.pas']),$($perSyx['uExtsB.pas']))"
Check 'T6 no read-back difference reported' ($r2.log -notmatch 'reads back differently')
# must_writes: the REAL analysis, read back by the self-check and printed per routine.
$mustLines = @([regex]::Matches($r2.log, 'v156-store-selfcheck: must file=(\S+) routine=(\S+) must_writes=\[([^\]]*)\]'))
$mustGot   = (@($mustLines | ForEach-Object { "$($_.Groups[2].Value)=$($_.Groups[3].Value)" }) | Sort-Object) -join ' '
Check 'T6 must_writes read back as the real analysis wrote it' ($mustGot -eq 'Fill=FTotal SumTo=Result Total=Result Twice=Result') "($mustGot)"
function Seed-Counts([string]$Db) {
  return [ordered]@{
    dfa   = Lane-Count $Db 'ds_field_accesses'
    loops = Lane-Count $Db 'loop_facts'
    cla   = Lane-Count $Db "call_literal_args WHERE callee_name = 'SelfCheckCall'"
    syx   = Lane-Count $Db "symbol_extras WHERE noreturn = 1 AND param_mode = 'out'"
    flows = Lane-Count $Db "data_flows WHERE dst_kind = 'dsfield' AND src_kind = 'except' AND val_class = 'int'"
    must  = Lane-Count $Db "symbol_facts f JOIN symbols s ON s.id = f.symbol_id WHERE f.must_writes = CASE s.name WHEN 'Fill' THEN 'FTotal' ELSE 'Result' END"
    edges = Lane-Count $Db "indirect_edges WHERE kind = 'method-pointer' AND caller_symbol_id = target_symbol_id"
  }
}
$c2 = Seed-Counts $db2
$c2Text = ($c2.Keys | ForEach-Object { "$_=$($c2[$_])" }) -join ' '
Check 'T6 four rows of every per-file fact, one indirect edge' (($c2.dfa -eq 4) -and ($c2.loops -eq 4) -and ($c2.cla -eq 4) -and ($c2.syx -eq 4) -and ($c2.flows -eq 4) -and ($c2.must -eq 4) -and ($c2.edges -eq 1)) "($c2Text)"
$fillMust = @(Lane-Sql $db2 "SELECT f.must_writes AS m FROM symbol_facts f JOIN symbols s ON s.id = f.symbol_id WHERE s.name = 'Fill'")
Check 'T6 control: must_writes is not seeded (Fill stores FTotal, not Result)' (($fillMust.Count -eq 1) -and ($fillMust[0].m -eq 'FTotal')) "($(($fillMust | ForEach-Object m) -join ','))"
$names = @(Lane-Sql $db2 "SELECT a.field_name AS f, s.name AS n FROM ds_field_accesses a JOIN symbols s ON s.id = a.symbol_id ORDER BY a.file_id, a.ordinal")
Check 'T6 ds_field_accesses.symbol_id joins the routine that was seeded' (($names.Count -eq 4) -and (@($names | Where-Object { $_.f -ne $_.n }).Count -eq 0)) "($(($names | ForEach-Object f) -join ','))"
$ords = @(Lane-Sql $db2 "SELECT ordinal FROM ds_field_accesses a JOIN files f ON f.id = a.file_id WHERE f.path LIKE '%uExtsA.pas' ORDER BY ordinal")
Check 'T6 ordinals are 0..n-1 within the file' ((($ords | ForEach-Object ordinal) -join ',') -eq '0,1,2') "($(($ords | ForEach-Object ordinal) -join ','))"

# ---- T7 replace on re-index ----------------------------------------------------------
Add-Content -Path (Join-Path $fx2 'uExtsA.pas') -Value "// touched`r`n" -NoNewline -Encoding ascii
$r3 = Lane-Index $fx2 $db2 'index-seed-2.log' $true
$c3 = Seed-Counts $db2
$c3Text = ($c3.Keys | ForEach-Object { "$_=$($c3[$_])" }) -join ' '
Check 'T7 second seeded run ends with exit 0' ($r3.rc -eq 0) "(rc $($r3.rc))"
Check 'T7 the touched unit was re-emitted' ($r3.log -match 'v156-store-selfcheck: ok file=uExtsA\.pas dfa=3')
Check 'T7 rows are replaced, not added' (($c3Text -eq $c2Text) -and ($c3.dfa -eq 4)) "($c3Text)"
Check 'T7 GetIndirectEdges reads the edge of run 1' ($r3.log -match 'v156-store-selfcheck: indirect-read=1')

# ---- T8 read compat / upgrade ----------------------------------------------------------
if ($BaseExe -ne '') {
  $fx4 = Join-Path $work 'base'; Copy-Item -Recurse $fxSrc $fx4
  $db4 = Join-Path $work 'base.sqlite'
  $r4  = Lane-Index $fx4 $db4 'index-base.log' $false $BaseExe
  $before = @(Lane-Sql $db4 "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ($in)" $BaseExe).Count
  $q = & { $ErrorActionPreference = 'Continue'; & $Exe query --name SumTo --db $db4 2>&1 }
  $qrc = $LASTEXITCODE
  $after = @(Lane-Sql $db4 "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ($in)").Count
  Check 'T8 VACUITY the base engine built an index without the tables' (($r4.rc -eq 0) -and ($before -eq 0)) "(rc $($r4.rc), tables $before)"
  Check 'T8 this engine reads the older index' (($qrc -eq 0) -and (($q -join "`n") -match 'SumTo')) "(rc $qrc)"
  Check 'T8 a read verb issues no DDL' ($after -eq 0) "(tables $after)"
  Add-Content -Path (Join-Path $fx4 'uExtsB.pas') -Value "// touched`r`n" -NoNewline -Encoding ascii
  $r5 = Lane-Index $fx4 $db4 'index-base-upgrade.log' $true
  $c5 = Seed-Counts $db4
  $upg = @(Lane-Sql $db4 "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ($in)").Count
  Check 'T8 a writer run of this engine adds the nine tables' (($r5.rc -eq 0) -and ($upg -eq 9)) "(rc $($r5.rc), tables $upg)"
  Check 'T8 and writes the facts of the re-emitted units' (($c5.dfa -ge 1) -and ($c5.must -ge 1) -and ($c5.flows -ge 1)) "(dfa=$($c5.dfa) must=$($c5.must) flows=$($c5.flows))"
} else {
  Write-Host '  SKIP  T8 (no -BaseExe)' -ForegroundColor DarkGray
}

# ---- T9 include define contexts, REAL emitters (no seed) ----------------------------------
$fx9 = Join-Path $work 'inc'; New-Item -ItemType Directory -Force $fx9 | Out-Null
function Lane-Write([string]$Name, [string[]]$Lines) {
  [IO.File]::WriteAllText((Join-Path $fx9 $Name), (($Lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
}
foreach ($u in 'XsA', 'XsB') {
  Lane-Write "$u.pas" @("unit $u;", $(if ($u -eq 'XsA') { '{$DEFINE COMPILE1}' } else { '' }), 'interface',
    'function Tag(const pS: string): string;', 'implementation', 'function Tag(const pS: string): string;', 'begin',
    '  Result := pS;', 'end;', '{$I XsBody.inc}', 'end.')
}
Lane-Write 'XsBody.inc' @('{$IFDEF COMPILE1}', 'procedure OnlyOne(out pA: Integer);', 'begin', "  pA := Length(Tag('one'));", 'end;',
  '{$ELSE}', 'procedure OnlyTwo(out pB: Integer);', 'begin', "  pB := Length(Tag('two'));", 'end;', '{$ENDIF}',
  'procedure Both(var pC: Integer);', 'begin', "  pC := Length(Tag('both'));", 'end;')
Lane-Write 'XsProj.dpr' @('program XsProj;', 'uses', "  XsA in 'XsA.pas',", "  XsB in 'XsB.pas';", 'begin', 'end.')
$db9 = Join-Path $work 'inc.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index --project (Join-Path $fx9 'XsProj.dpr') --db $db9 --library-db none *> (Join-Path $work 'index-inc.log') }
$rc9 = $LASTEXITCODE
$incWhere = "JOIN files f ON f.id = s.file_id WHERE f.path LIKE '%XsBody.inc'"
$routines = (@(Lane-Sql $db9 "SELECT s.name AS n FROM symbols s $incWhere AND s.name IN ('OnlyOne', 'OnlyTwo', 'Both') ORDER BY s.name") | ForEach-Object n) -join ','
Check 'T9 VACUITY the include was parsed in both define contexts' (($rc9 -eq 0) -and ($routines -eq 'Both,OnlyOne,OnlyTwo')) "(rc $rc9, $routines)"
$modes = @{}
foreach ($r in @(Lane-Sql $db9 "SELECT s.name AS n, x.param_mode AS m FROM symbol_extras x JOIN symbols s ON s.id = x.symbol_id $incWhere AND s.name IN ('pA', 'pB', 'pC')")) { $modes[[string]$r.n] = [string]$r.m }
$modeText = (@($modes.Keys | Sort-Object | ForEach-Object { "$_=$($modes[$_])" })) -join ' '
if ($NoParserEmitter) {
  Check 'T9 -NoParserEmitter: this engine really has no parser emitter' ($modes.Count -eq 0) "($modeText)"
  Write-Host '  SKIP  T9 include-context facts (-NoParserEmitter: EXT-A1 is not in this engine)' -ForegroundColor Yellow
} else {
  Check 'T9 control: the parser emitter is in this engine (pC of Both is var)' ($modes['pC'] -eq 'var') "($modeText)"
  Check 'T9 symbol_extras of the context-only routines: pA and pB are both out' (($modes['pA'] -eq 'out') -and ($modes['pB'] -eq 'out')) "($modeText)"
  $lits = (@(Lane-Sql $db9 "SELECT c.value AS v FROM call_literal_args c JOIN files f ON f.id = c.file_id WHERE f.path LIKE '%XsBody.inc' AND c.callee_name = 'Tag' ORDER BY c.value") | ForEach-Object v) -join ','
  Check 'T9 call_literal_args of both contexts, each literal once' ($lits -eq 'both,one,two') "($lits)"
}

if (-not $KeepScratch) { try { [IO.Directory]::Delete($work, $true) } catch { } } else { Write-Host "scratch: $work" }
Write-Host ("run_v156_EXTS_schema: {0} pass, {1} fail" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $(if ($script:fail) { 1 } else { 0 })
