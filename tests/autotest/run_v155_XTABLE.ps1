<#
  run_v155_XTABLE.ps1 -- lane XTABLE slice X1 (1.55): cross-table fields, repository schema 4
  (design docs\superpowers\specs\2026-11-26-cross-table-fields-design.md section 2).
  Part A builds + runs tests\fieldrepo\CrossTableTests.dpr (schema 4, migrate 3 -> 4, #DLREPO 4, ALIAS.FIELD macros,
  dependency closure, repo check rules). Part B drives the engine: repo init (schema 4), restore of the clean fixture
  xtable_v4.txt checks clean, a planted copy names input-path-broken and input-alias-undeclared, a #DLREPO 3 file
  migrates to 4 (dry run changes no byte), the backup round trip is byte-identical.
  Slice X2 (design 3.2): Part C builds + runs tests\fieldrepo\RelationGraphTests.dpr (one path, ambiguous, stored /
  form / default rules, keyless parent, depth, roles, loader). Part D drives `repo paths` on
  xtable\xtable_paths_v4.txt and the MICRONITEV6A counts: on a COPY of -V6aRepo, else of a repository seeded
  read-only from -V6aConnection (skipped, and said so, when neither is reachable); the original is checked unchanged.
  Slice X3 (design 3.1, 3.2): Part E drives `repo read-dfm` on xtable\uXJoin.dfm + uXMem.dfm over the schema of
  xtable\xtable_schema.sql: ON / WHERE conditions choose the path (rule 2), child-end home, `{{ALIAS.F}}` bodies,
  no child end / a 1:1 pair / a table joined twice / OR = unresolved with the reason, an offered FORM relation
  (unchecked), FK relation rows, apply + repo check clean + a second read idempotent; AttachedTo (chain, cycle),
  AttachTable (array form not followed), CloneCursor / CopyDataSet / CopyData / AppendData / Data :=, two sources,
  a field written after a copy; gen-handlers / write-dfm refuse a foreign input cleanly; schema 3 refused.
  Run: pwsh -File tests\autotest\run_v155_XTABLE.ps1 [-Exe <drag-lint.exe>] [-SkipBuild] [-V6aRepo <file>]
       [-V6aConnection <Firebird connection string>]
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$SkipBuild, [string]$V6aRepo = '',
  [string]$V6aConnection = 'Database=C:\Projects\DB\SQL\MICRONITEV6A.FDB;User_Name=SYSDBA;Password=masterkey;DriverID=FB;Server=localhost')
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
Write-Host '== v1.55 XTABLE: cross-table fields, schema 4 + relation paths ==' -ForegroundColor Cyan
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-xtable-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
try {
  # ---- A: unit tests
  $bat = Join-Path $Repo 'build\_build_fieldrepo_xtable_tests_local.bat'
  $bin = Join-Path $Repo 'tests\fieldrepo\CrossTableTests.exe'
  if (-not $SkipBuild) {
    $blog = Join-Path $work 'build.log'
    Start-Process -FilePath cmd.exe -ArgumentList (('/c ' + [char]34 + [char]34 + $bat + [char]34 + ' > ' + [char]34 + $blog + [char]34 + ' 2>&1' + [char]34)) -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    Check 'A0 CrossTableTests build' (($bl -match 'BUILD_EXITCODE=0') -and ($bl -notmatch '\[dcc\w*\] Error|: error ')) $blog
  }
  $log = Join-Path $work 'run.log'
  & { $ErrorActionPreference = 'Continue'; & $bin *> $log }
  $code = $LASTEXITCODE
  Select-String -LiteralPath $log -Pattern '^FAIL' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
  $sum = Select-String -LiteralPath $log -Pattern '^SUMMARY ' | Select-Object -Last 1
  Check 'A1 CrossTableTests SUMMARY fail=0' (($code -eq 0) -and $sum -and ($sum.Line -match 'fail=0\b')) ($sum.Line)

  # ---- B: engine
  if (-not (Test-Path -LiteralPath $Exe)) { Check 'B0 engine exe exists' $false $Exe; throw 'no exe' }
  function Run([string[]]$a) {
    $o = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } }
    $out = ($o | ForEach-Object { "$_" }) -join "`n"
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
  }
  $fix = Join-Path $Repo 'tests\fixtures\fieldrepo'
  $clean = Join-Path $fix 'xtable\xtable_v4.txt'
  $x = Join-Path $work 'x.dlrepo'
  $r = Run @('repo', 'init', '--repo', $x)
  $info = (Run @('repo', 'info', '--repo', $x)).Out
  Check 'B1 repo init creates a current-schema (5) file with the three cross-table tables' (($r.Code -eq 0) -and ($info -match 'schema_version: 5') -and ($info -match 'DL_RELATIONS: 0 rows') -and ($info -match 'DL_RELATION_COLUMNS: 0 rows') -and ($info -match 'DL_FIELD_INPUTS: 0 rows')) $info
  $r = Run @('repo', 'restore', '--repo', $x, '--in', $clean)
  Check 'B2 restore of the clean fixture' ($r.Code -eq 0) $r.Out
  $r = Run @('repo', 'check', '--repo', $x)
  Check 'B3 positive control: the IPCHART -> INSPRSLT -> MSCLIST fixture checks clean' (($r.Code -eq 0) -and ($r.Out -match 'check: clean')) "exit=$($r.Code) $($r.Out)"
  $bk = Join-Path $work 'x.txt'
  $r = Run @('repo', 'backup', '--repo', $x, '--output', $bk)
  Check 'B4 backup of the restored #DLREPO 4 fixture differs only by the schema number (#DLREPO 5, schema_version 5)' (($r.Code -eq 0) -and ([IO.File]::ReadAllText($bk) -ceq [IO.File]::ReadAllText($clean).Replace('#DLREPO 4', '#DLREPO 5').Replace('META_VALUE=4', 'META_VALUE=5')) -and [IO.File]::ReadAllText($clean).StartsWith('#DLREPO 4')) $r.Out

  $bad = Join-Path $work 'bad.txt'
  $txt = [IO.File]::ReadAllText($clean)
  $planted = $txt.Replace('PATH=FK_IPCHART_INSP>FK_INSP_MSC', 'PATH=FK_INSP_MSC').Replace('{{MSC.DECIMALS}}', '{{X.DECIMALS}}')
  Check 'B5 the planted copy differs from the fixture (positive control of the plant)' ($planted -cne $txt)
  [IO.File]::WriteAllText($bad, $planted, [Text.Encoding]::ASCII)
  $y = Join-Path $work 'y.dlrepo'
  $null = Run @('repo', 'restore', '--repo', $y, '--in', $bad)
  $r = Run @('repo', 'check', '--repo', $y)
  Check 'B6 the planted copy: exit 1, input-path-broken and input-alias-undeclared named' (($r.Code -eq 1) -and ($r.Out -match 'ERROR input-path-broken input IPCHART\.FTRNAME MSC') -and ($r.Out -match 'ERROR input-alias-undeclared IPCHART\.FTRNAME')) "exit=$($r.Code)`n$($r.Out)"
  $r = Run @('repo', 'check', '--repo', $y, '--json')
  $j = $null; try { $j = $r.Out | ConvertFrom-Json | ForEach-Object { $_ } } catch { }
  Check 'B7 repo check --json lists both codes' (($r.Code -eq 1) -and $j -and (@($j.findings | Where-Object { $_.code -eq 'input-path-broken' }).Count -eq 1) -and (@($j.findings | Where-Object { $_.code -eq 'input-alias-undeclared' }).Count -eq 1)) "exit=$($r.Code)"

  # schema 3 -> 5
  $v3 = Join-Path $work 'v3.dlrepo'
  $r = Run @('repo', 'restore', '--repo', $v3, '--in', (Join-Path $fix 'golden_v3.txt'))
  Check 'B8 a #DLREPO 3 backup into a missing file creates schema 3' (($r.Code -eq 0) -and ((Run @('repo','info','--repo',$v3)).Out -match 'schema_version: 3')) $r.Out
  $h3 = (Get-FileHash -LiteralPath $v3).Hash
  $r = Run @('repo', 'migrate', '--repo', $v3)
  Check 'B9 v3 -> v5 dry run: the schema-5 columns, three CREATEs, nothing else, no byte changed' (($r.Code -eq 0) -and ($r.Out -match 'v3 -> v5: add DL_FIELDS_INFO\.NOTES, DERIVED_KIND, add DL_GRID_COLUMNS\.PROPERTIES_CLASS_NAME, PROPERTIES, create DL_RELATIONS, DL_RELATION_COLUMNS, DL_FIELD_INPUTS, ALIGNMENT -2 to NULL in 0 rows, user_version 5') -and ($h3 -eq (Get-FileHash -LiteralPath $v3).Hash)) $r.Out
  $r = Run @('repo', 'migrate', '--repo', $v3, '--apply')
  $b3 = @(Get-ChildItem $work -Filter 'v3.dlrepo.before-migrate-*.txt')
  Check 'B10 v3 -> v5 apply: schema 5, the backup is the schema-3 text, check clean' (($r.Code -eq 0) -and ((Run @('repo','info','--repo',$v3)).Out -match 'schema_version: 5') -and ($b3.Count -eq 1) -and ([IO.File]::ReadAllText($b3[0].FullName) -ceq [IO.File]::ReadAllText((Join-Path $fix 'golden_v3.txt'))) -and ((Run @('repo','check','--repo',$v3)).Out -match 'check: clean')) $r.Out
  $r = Run @('repo', 'migrate', '--repo', $v3, '--apply')
  Check 'B11 a second migrate says already at schema 5' (($r.Code -eq 0) -and ($r.Out -match 'already at schema 5')) $r.Out
  # ---- C: X2 unit tests (relation graph + path finder)
  $bat = Join-Path $Repo 'build\_build_fieldrepo_relgraph_tests_local.bat'
  $bin = Join-Path $Repo 'tests\fieldrepo\RelationGraphTests.exe'
  if (-not $SkipBuild) {
    $blog = Join-Path $work 'build-x2.log'
    Start-Process -FilePath cmd.exe -ArgumentList (('/c ' + [char]34 + [char]34 + $bat + [char]34 + ' > ' + [char]34 + $blog + [char]34 + ' 2>&1' + [char]34)) -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    Check 'C0 RelationGraphTests build' (($bl -match 'BUILD_EXITCODE=0') -and ($bl -notmatch '\[dcc\w*\] Error|: error | Error: ')) $blog
  }
  $log = Join-Path $work 'run-x2.log'
  & { $ErrorActionPreference = 'Continue'; & $bin *> $log }
  $code = $LASTEXITCODE
  Select-String -LiteralPath $log -Pattern '^FAIL' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
  $sum = Select-String -LiteralPath $log -Pattern '^SUMMARY ' | Select-Object -Last 1
  Check 'C1 RelationGraphTests SUMMARY fail=0' (($code -eq 0) -and $sum -and ($sum.Line -match 'fail=0\b')) ($sum.Line)

  # ---- D: repo paths
  $p = Join-Path $work 'p.dlrepo'
  $null = Run @('repo', 'restore', '--repo', $p, '--in', (Join-Path $fix 'xtable\xtable_paths_v4.txt'))
  $r = Run @('repo', 'paths', '--repo', $p, '--from', 'IPCHART', '--to', 'MSCLIST')
  Check 'D1 two paths IPCHART -> MSCLIST: listed with aliases MSCLIST / MSCLIST_2, ambiguous, exit 0' (($r.Code -eq 0) -and ($r.Out -match '\(depth 3\): 2 path\(s\)') -and ($r.Out -match '(?m)^  1 MSCLIST: IPCHART -\(FK_IPCHART_IINSP FK IINSPID=ID\)-> IINSP') -and ($r.Out -match '(?m)^  2 MSCLIST_2: IPCHART -\(FK_IPCHART_INSP ') -and ($r.Out -match 'choice: ambiguous')) "exit=$($r.Code)`n$($r.Out)"
  $r = Run @('repo', 'paths', '--repo', $p, '--from', 'IPCHART', '--to', 'INSPRSLT')
  Check 'D2 one path is taken: choice single' (($r.Code -eq 0) -and ($r.Out -match ': 1 path\(s\)') -and ($r.Out -match 'choice: single, path 1')) $r.Out
  $r = Run @('repo', 'paths', '--repo', $p, '--from', 'IPCHART', '--to', 'NOKEY')
  Check 'D3 an FK onto a parent with no key is no edge: 0 paths, exit 1' (($r.Code -eq 1) -and ($r.Out -match ': 0 path\(s\)') -and ($r.Out -match 'choice: none')) "exit=$($r.Code) $($r.Out)"
  $r = Run @('repo', 'paths', '--repo', $p, '--from', 'FOLDERS', '--to', 'OPTRLIST')
  Check 'D4 roles: the stored IS_DEFAULT (renamed FOLDERS_CLOSER) decides' (($r.Code -eq 0) -and ($r.Out -match 'FOLDERS_CLOSER FK CLOSEDBY=ID default') -and ($r.Out -match 'choice: default, path 2')) $r.Out
  $r = Run @('repo', 'paths', '--repo', $p, '--from', 'IPCHART', '--to', 'OPTRLIST')
  Check 'D5 a confirmed FORM relation is an edge (XQ6)' (($r.Code -eq 0) -and ($r.Out -match 'IPCHART_OPTRLIST FORM OPERID=ID')) $r.Out
  $r = Run @('repo', 'paths', '--repo', $p, '--from', 'IPCHART', '--to', 'MSCLIST', '--depth', '1')
  Check 'D6 depth limit: --depth 1 finds no 2-step path' (($r.Code -eq 1) -and ($r.Out -match '\(depth 1\): 0 path\(s\)')) "exit=$($r.Code) $($r.Out)"
  $r = Run @('repo', 'paths', '--repo', $p, '--from', 'IPCHART', '--to', 'MSCLIST', '--json')
  $j = $null; try { $j = ($r.Out -split "`n" | Where-Object { $_.StartsWith('{') }) | ConvertFrom-Json | ForEach-Object { $_ } } catch { }
  Check 'D7 --json: paths with alias, path and steps; choice ambiguous, chosen 0' (($r.Code -eq 0) -and $j -and (@($j.paths).Count -eq 2) -and ($j.paths[1].alias -eq 'MSCLIST_2') -and ($j.paths[1].path -eq 'FK_IPCHART_INSP>FK_INSP_MSC') -and ($j.paths[1].steps[0].parent_key -eq 'PK_INSPRSLT') -and ($j.choice -eq 'ambiguous') -and ($j.chosen -eq 0)) $r.Out
  $r = Run @('repo', 'paths', '--repo', $p, '--stats')
  Check 'D8 --stats on the fixture: 7 edges, 2 not edges, depth 2 = 7 pairs / 2 ambiguous' (($r.Code -eq 0) -and ($r.Out -match 'relations=7 not-edges=2') -and ($r.Out -match 'depth 2: pairs 7, more than one path 2')) $r.Out
  $r = Run @('repo', 'paths', '--repo', $p, '--from', 'IPCHART')
  Check 'D9 usage: --from without --to exits 2' ($r.Code -eq 2) "exit=$($r.Code) $($r.Out)"
  $r = Run @('repo', 'paths', '--repo', $p, '--stats', '--depth', '0')
  Check 'D10 usage: --depth 0 exits 2' ($r.Code -eq 2) "exit=$($r.Code) $($r.Out)"

  # ---- E: X3 read-dfm (design 3.1, 3.2): join conditions, child-end home, aliases + bindings, memtable links
  $xf = Join-Path $work 'xforms'
  [IO.Directory]::CreateDirectory($xf) | Out-Null
  foreach ($n in 'uXJoin.dfm', 'uXJoin.pas', 'uXMem.dfm', 'uXMem.pas') { [IO.File]::Copy((Join-Path $fix "xtable\$n"), (Join-Path $xf $n)) }
  $xr = Join-Path $work 'x3.dlrepo'
  $null = Run @('repo', 'init', '--repo', $xr)
  $s = Run @('repo', 'seed-fb', '--ddl', (Join-Path $fix 'xtable\xtable_schema.sql'), '--repo', $xr, '--apply')
  Check 'E0 the X3 fixture schema seeds (FKs, keys, a keyless table, a 1:1 pair)' ($s.Code -eq 0) $s.Out
  $dfms = (Join-Path $xf 'uXJoin.dfm') + ';' + (Join-Path $xf 'uXMem.dfm')
  function X3([string[]]$more = @(), $rp = $xr) { Run (@('repo', 'read-dfm', '--repo', $rp, '--dfm', $dfms, '--direction', 'dfm-to-repo') + $more) }
  $r = X3
  $o = $r.Out
  function Ch([string]$pat) { [regex]::IsMatch($o, $pat) }
  Check 'E1 calc over IPCHART + MSCLIST: home IPCHART (the child end), foreign input as {{MSCLIST.DECIMALS}}' (Ch '(?m)^\[\d+\] insert DL_FIELDS_INFO IPCHART\|FTRNAME: [^\n]*CALC_BODY=\{\{FTRNAME\}\}\.AsString := FloatToStr\(\{\{RVAL\}\}\.AsFloat\) \+ IntToStr\(\{\{MSCLIST\.DECIMALS\}\}\.AsInteger\);') $o
  Check 'E2 the ON conditions choose the path through INSPRSLT (rule 2, form); checked' ((Ch '(?m)^\[\d+\] insert DL_FIELD_INPUTS IPCHART\|FTRNAME\|\|MSCLIST:  -> PATH=FK_IPCHART_INSP>FK_INSP_MSC; TARGET_TABLE=MSCLIST \(rule form\)\r?\n\[') ) $o
  Check 'E3 WHERE equalities between two FROM tables choose the path through IINSP' (Ch '(?m)^\[\d+\] insert DL_FIELD_INPUTS IPCHART\|ALTNAME\|\|MSCLIST:  -> PATH=FK_IPCHART_IINSP>FK_IINSP_MSC; TARGET_TABLE=MSCLIST \(rule form\)') $o
  Check 'E4 a WHERE with OR gives no condition: two paths, unresolved, never picked' ((Ch 'no table: ORNAME: the calc code reads 2 tables: IPCHART MSCLIST; home IPCHART; 2 paths to MSCLIST, none chosen \(asked once\)') -and -not (Ch 'DL_FIELD_INPUTS IPCHART\|ORNAME')) $o
  Check 'E5 an input that is a calc field of the home table stays {{DOUBLED}}; NOTATION is {{MSCLIST.NOTATION}}' (Ch 'insert DL_FIELDS_INFO IPCHART\|LABELX: [^\n]*CALC_BODY=\{\{LABELX\}\}\.AsString := \{\{DOUBLED\}\}\.AsString \+ \{\{MSCLIST\.NOTATION\}\}\.AsString;') $o
  Check 'E6 a join on a parent key with no FK is OFFERED as a FORM relation (unchecked, XQ6); its input is unchecked' ((Ch '(?m)^\[\d+\] insert DL_RELATIONS IPCHART_TOOLGR:  -> IPCHART > TOOLGR; SOURCE=FORM; PARENT_KEY=PK_TOOLGR; IS_DEFAULT=False; COLUMNS=GRID=GRID\r?\n  \(unchecked\)') -and (Ch '(?m)^\[\d+\] insert DL_FIELD_INPUTS IPCHART\|GRTXT\|\|TOOLGR:  -> PATH=IPCHART_TOOLGR; TARGET_TABLE=TOOLGR \(rule form\)\r?\n  \(unchecked\)') -and (Ch '(?m)^\[\d+\] insert DL_FIELDS_INFO IPCHART\|GRTXT: [^\n]*\{\{TOOLGR\.GRNAME\}\}[^\n]*\r?\n  \(unchecked\)')) $o
  Check 'E7 a join onto a keyless table: no child end, unresolved with the reason' (Ch 'no table: NKTXT: the calc code reads 2 tables: IPCHART NOKEY; no table of IPCHART NOKEY reaches all the others') $o
  Check 'E8 a 1:1 pair: two child ends, unresolved (asked)' (Ch 'no table: PAIRTXT: the calc code reads 2 tables: PAIRA PAIRB; PAIRA PAIRB each reach all the others \(a 1:1 pair\)') $o
  Check 'E9 a table joined twice: unresolved, not merged' (Ch 'no table: TWOMSC: the calc code reads 2 tables: IPCHART MSCLIST; MSCLIST is in the FROM 2 times') $o
  $fkIns = @([regex]::Matches($o, '(?m)^\[\d+\] insert DL_RELATIONS (FK_\w+):  -> [^\n]*SOURCE=FK; CONSTRAINT_NAME=') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
  Check 'E10 the FK steps the bindings use are inserted once each (2.3: created when a binding first uses the step)' (($fkIns -join ',') -eq 'FK_IINSP_MSC,FK_INSP_MSC,FK_IPCHART_IINSP,FK_IPCHART_INSP') ($fkIns -join ',')
  Check 'E11 summary line of the cross-table calc fields' (Ch '(?m)^cross-table calc: 4 placed, 4 unresolved; 4 inputs; relations: 4 FK used, 1 offered') $o
  # memtable links (3.1)
  Check 'E12 AttachedTo (DFM) gives the source''s table; a calc field of the memtable is read into it' ((Ch 'dataset uXMem\.dfm memA \(TkbmMemTable\) -> IPCHART \(via AttachedTo tblChart\): 2 data, 1 calc') -and (Ch 'insert DL_FIELDS_INFO IPCHART\|HALF: [^\n]*CALC_BODY=\{\{HALF\}\}\.AsFloat := \{\{RVAL\}\}\.AsFloat / 2;')) $o
  Check 'E13 AttachedTo chain of two memtables' (Ch 'memB \(TkbmMemTable\) -> IPCHART \(via AttachedTo memA > AttachedTo tblChart\)') $o
  Check 'E14 an AttachedTo cycle is guarded and unresolved' (Ch 'memC1 \(TkbmMemTable\) -> UNRESOLVED \(the links memC1 > memC2 > memC1 are a cycle\)') $o
  Check 'E15 literal AttachTable followed; the array form not' ((Ch 'memD \(TkbmMemTable\) -> IPCHART \(via AttachTable tblChart\)') -and (Ch 'memE \(TkbmMemTable\) -> UNRESOLVED \(no TableName and no SQL in the DFM\)')) $o
  Check 'E16 CopyDataSet with a comment in the argument; a field written after the copy keeps no origin' ((Ch 'memF \(TFDMemTable\) -> IPCHART \(via CopyDataSet tblChart\): 2 data[^\n]*\n  no table column: RVAL') -and (Ch 'warning: uXMem\.dfm memF RVAL: no table: written in code after the copy \(uXMem\.pas:51\)')) $o
  Check 'E17 CloneCursor of a join: the memtable is that join' (Ch 'memG \(TFDMemTable\) -> JOIN IPCHART INSPRSLT MSCLIST \(via CloneCursor qryJ\)') $o
  Check 'E18 Data :=, CopyData, AppendData, Self.CloneCursor' ((Ch 'memH \(TFDMemTable\) -> IPCHART \(via Data tblChart\)') -and (Ch 'memI \(TFDMemTable\) -> IPCHART \(via CopyData tblChart\)') -and (Ch 'memJ \(TFDMemTable\) -> IPCHART \(via AppendData tblChart\)') -and (Ch 'memL \(TFDMemTable\) -> IPCHART \(via CloneCursor tblChart\)')) $o
  Check 'E19 two different sources for one target: reported, never picked' (Ch 'memK \(TFDMemTable\) -> UNRESOLVED \(linked to 2 sources: CopyDataSet tblChart \(uXMem\.pas:56\), CopyDataSet qryJ \(uXMem\.pas:57\)\)') $o
  Check 'E20 links summary line per source kind' (Ch '(?m)^links: 9 datasets got a source: AttachedTo 2, AttachTable 1, CloneCursor 2, CopyDataSet 1, CopyData 1, AppendData 1, Data 1; 3 unresolved') $o
  $j = X3 @('--json')
  $jo = $null; try { $jo = $j.Out.Substring($j.Out.IndexOf('{')) | ConvertFrom-Json | ForEach-Object { $_ } } catch { }
  $jm = if ($jo) { @($jo.datasets | Where-Object { $_.dataset -eq 'memB' })[0] } else { $null }
  Check 'E21 --json: via of a dataset, totals.crossTable and totals.links' (($null -ne $jm) -and ($jm.via -eq 'AttachedTo memA > AttachedTo tblChart') -and ($jo.totals.crossTable.placed -eq 4) -and ($jo.totals.crossTable.inputs -eq 4) -and ($jo.totals.links.AttachedTo -eq 2) -and ($jo.totals.links.unresolved -eq 3)) $j.Out
  # apply, check, idempotent
  $r = X3 @('--apply')
  $c = Run @('repo', 'check', '--repo', $xr)
  Check 'E22 apply the checked changes: repo check is clean (inputs, FK relations, field rows agree)' (($r.Code -eq 0) -and ($c.Code -eq 0) -and ($c.Out -match 'check: clean')) "$($r.Out)`n$($c.Out)"
  $info = (Run @('repo', 'info', '--repo', $xr)).Out
  Check 'E23 three inputs and four FK relations stored; the offered FORM relation is not' (($info -match 'DL_FIELD_INPUTS: 3 rows') -and ($info -match 'DL_RELATIONS: 4 rows') -and ($info -match 'DL_RELATION_COLUMNS: 4 rows')) $info
  $r = X3
  Check 'E24 a second read proposes no input or FK relation again (the stored binding, rule 1)' ((-not ($r.Out -match 'insert DL_FIELD_INPUTS IPCHART\|(FTRNAME|ALTNAME|LABELX)')) -and (-not ($r.Out -match 'insert DL_RELATIONS FK_')) -and ($r.Out -match 'insert DL_RELATIONS IPCHART_TOOLGR')) $r.Out
  # the generators refuse a foreign input cleanly (review nit)
  $g = Run @('repo', 'gen-handlers', '--repo', $xr, '--dfm', (Join-Path $xf 'uXMem.dfm'), '--dataset', 'tblCalc')
  Check 'E25 gen-handlers: a body with {{MSCLIST.DECIMALS}} is BLOCKED with the reason, no exception' (($g.Out -match 'FTRNAME: the code reads fields of other tables \(\{\{MSCLIST\.DECIMALS\}\}\): not generated before repo compose-sql') -and ($g.Out -notmatch 'Exception|reserved')) "exit=$($g.Code)`n$($g.Out)"
  $w = Run @('repo', 'write-dfm', '--repo', $xr, '--dfm', (Join-Path $xf 'uXMem.dfm'), '--direction', 'repo-to-dfm', '--dataset', 'tblChart', '--names', 'FTRNAME')
  Check 'E26 write-dfm: inserting that field is BLOCKED with the reason, no macro exception' (($w.Code -eq 0) -and ($w.Out -match 'BLOCKED: the code reads fields of other tables \(\{\{MSCLIST\.DECIMALS\}\}\): not written before repo compose-sql') -and ($w.Out -notmatch 'reserved')) "exit=$($w.Code)`n$($w.Out)"
  # schema 4 minimum
  $v3x = Join-Path $work 'v3x.dlrepo'
  $null = Run @('repo', 'restore', '--repo', $v3x, '--in', (Join-Path $fix 'golden_v3.txt'))
  $r = X3 @() $v3x
  $g = Run @('repo', 'gen-handlers', '--repo', $v3x, '--dfm', (Join-Path $xf 'uXMem.dfm'))
  Check 'E27 read-dfm and gen-handlers refuse schema 3 (run repo migrate)' (($r.Code -eq 1) -and ($r.Out -match 'the repository is schema 3: run repo migrate first') -and ($g.Code -ne 0) -and ($g.Out -match 'schema 3: run repo migrate first')) "$($r.Out)`n$($g.Out)"

  # MICRONITEV6A (design 3.2 measured check): the draft's pairs 274 / 1,089 / 1,653; more than one path 10 / 332 /
  # 1,165 with the two-column key FK_PROBLEMS12 counted ONCE (the draft's 11 / 334 / 1,168 counted it per column).
  $orig = $V6aRepo
  if (-not $orig) {
    $fdb = [regex]::Match($V6aConnection, 'Database=([^;]+)').Groups[1].Value
    if ($fdb -and (Test-Path -LiteralPath $fdb)) {
      $orig = Join-Path $work 'v6a.dlrepo'
      $null = Run @('repo', 'init', '--repo', $orig)
      $s = Run @('repo', 'seed-fb', '--connection', $V6aConnection, '--repo', $orig, '--apply')
      if ($s.Code -ne 0) { $orig = '' }
    }
  }
  if (-not $orig) { Write-Host '[SKIP] D11 MICRONITEV6A counts: no -V6aRepo and the database is not reachable' -ForegroundColor Yellow }
  else {
    $before = (Get-Item -LiteralPath $orig) | ForEach-Object { "$($_.Length) $($_.LastWriteTimeUtc.Ticks)" }
    $copy = Join-Path $work 'v6a-copy.dlrepo'
    Copy-Item -LiteralPath $orig -Destination $copy
    $r = Run @('repo', 'paths', '--repo', $copy, '--stats')
    Check 'D11 MICRONITEV6A: 297 relations; pairs 274 / 1089 / 1653; more than one path 10 / 332 / 1165' (($r.Code -eq 0) -and ($r.Out -match 'relations=297 not-edges=0') -and ($r.Out -match 'depth 1: pairs 274, more than one path 10\b') -and ($r.Out -match 'depth 2: pairs 1089, more than one path 332\b') -and ($r.Out -match 'depth 3: pairs 1653, more than one path 1165\b')) $r.Out
    $after = (Get-Item -LiteralPath $orig) | ForEach-Object { "$($_.Length) $($_.LastWriteTimeUtc.Ticks)" }
    Check 'D12 the original repository is unchanged (size + mtime)' ($before -eq $after) "$before / $after"
  }
} catch { Write-Host "ABORT: $_" -ForegroundColor Red; $script:Failed = $true }
finally { try { [IO.Directory]::Delete($work, $true) } catch { $null = $_ } }
if ($script:Failed) { Write-Host 'V155 XTABLE: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'V155 XTABLE: PASS' -ForegroundColor Green; exit 0
