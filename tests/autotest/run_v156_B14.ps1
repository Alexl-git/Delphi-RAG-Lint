<#
  run_v156_B14.ps1 -- 1.56 lane EXT-B3 (B14): field lineage facts.
  Spec: docs\superpowers\specs\2026-11-27-derived-field-lineage-design.md sections 4.3, 6.1.

  Indexes tests\fixtures\b14 into a scratch DB and checks, through `sql --json` (rows are POSITIONAL
  arrays; mapped onto columns[].name below, a missing column THROWS):
    T1-T8   ds_field_accesses: by-name / find / values / default / index / accessor shapes, read and
            write, name kinds, roots (param / local / field / other), and the 'dsfield' flow rows at
            the SAME position.
    T9      loop_facts (while / for / for-in / repeat, parent) and a via-local source inside a loop.
    T10-T11 `with` bodies: access rows (6a) and the 'dsfield' flow rows (6b), every one cond 1.
    T12     through calls: parameter-rooted write, argument row with a 'dsfield' source.
    T13     (-BaseExe) the data_flows rows that have NO dsfield kind are EXACTLY the base engine's
            rows for the same fixture.
    T14     (-BaseExe) `lint` on the fixture gives the same findings as the base engine.
    T16     an incremental reindex of the edited fixture replaces its rows (no duplicate ordinals).
  Positive control: run with -Exe <an engine without lane EXT-B3> -- T1 FAILS (no rows at all).
  T15 (size / time on real projects) is lane EXT-BM's report, not a check here.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$BaseExe = '', [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v156_B14: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_v156_B14: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fxSrc = Join-Path $repo 'tests\fixtures\b14'
$work  = Join-Path $env:TEMP ('dl-v156-b14-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}

# rows as objects; $null when the query fails (a table that does not exist), @() when it has no row
function Lane-Sql([string]$Db, [string]$Query, [string]$With = $Exe) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $With sql --query $Query --db $Db --json 2>$null }
  if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
  try { $j = ($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ } } catch { return $null }
  $cols = @($j.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
  if ($cols.Count -eq 0) { throw "run_v156_B14: sql --json gave no columns for: $Query" }
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($r in @($j.rows)) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $r[$i] }
    $out.Add([pscustomobject]$o)
  }
  return ,$out.ToArray()
}
# as Lane-Sql, but always an array (empty when the query fails or has no row)
function Lane-Rows([string]$Db, [string]$Query, [string]$With = $Exe) {
  $r = Lane-Sql $Db $Query $With
  if ($null -eq $r) { return ,@() }
  return ,$r
}
function Lane-Index([string]$Dir, [string]$Db, [string]$LogName, [string]$With = $Exe) {
  $log = Join-Path $work $LogName
  & { $ErrorActionPreference = 'Continue'; & $With index $Dir --db $Db *> $log }
  return $LASTEXITCODE
}
$accSql  = "SELECT s.name AS routine, a.ordinal, a.mode, a.line, a.col, a.shape, a.dataset_text, a.field_text, a.field_name, " +
           "a.name_kind, a.name_text, a.accessor, a.root_kind, a.root_name, a.root_index, a.with_ctx, a.rhs_start_line, " +
           "a.rhs_start_col, a.rhs_end_line, a.rhs_end_col, a.stmt_line, a.stmt_col " +
           "FROM ds_field_accesses a JOIN symbols s ON s.id = a.symbol_id ORDER BY a.ordinal LIMIT 100000"
$loopSql = "SELECT s.name AS routine, l.ordinal, l.parent, l.kind, l.start_line, l.start_col, l.end_line, l.end_col, " +
           "l.cond_start_line, l.cond_start_col, l.cond_end_line, l.cond_end_col " +
           "FROM loop_facts l JOIN symbols s ON s.id = l.symbol_id ORDER BY l.ordinal LIMIT 100000"
$rowSql  = "SELECT s.name AS routine, d.dst_kind, d.dst_line, d.dst_col, d.dst_index, d.dst_name, d.dst_receiver, " +
           "d.src_kind, d.src_index, d.src_line, d.src_col, d.src_name, d.via_local, d.cond, d.val_class " +
           "FROM data_flows d JOIN symbols s ON s.id = d.symbol_id LIMIT 100000"
function Has($rs, [scriptblock]$p) { @($rs | Where-Object $p).Count -gt 0 }
function Cnt($rs, [scriptblock]$p) { @($rs | Where-Object $p).Count }
function Row-Key($r) { "$($r.routine)|$($r.dst_kind)|$($r.dst_line)|$($r.dst_col)|$($r.dst_index)|$($r.dst_name)|$($r.dst_receiver)|$($r.src_kind)|$($r.src_index)|$($r.src_line)|$($r.src_col)|$($r.src_name)|$($r.via_local)|$($r.cond)|$($r.val_class)" }
function Is-Old($r) { $r.dst_kind -ne 'dsfield' -and $r.src_kind -ne 'dsfield' }

try {
  $src = Join-Path $work 'src'
  Copy-Item $fxSrc $src -Recurse
  $probe = Join-Path $src 'uB14Facts.pas'
  $M = @{}
  $ln = 0
  foreach ($line in [IO.File]::ReadAllLines($probe)) {
    $ln++
    $hit = [regex]::Match($line, '\{ (M-[A-Z0-9-]+) \}')
    if ($hit.Success) { $M[$hit.Groups[1].Value] = $ln }
  }
  Check 'fixture markers found (fixture input)' ($M.Count -ge 30) "markers=$($M.Count)"

  $db = Join-Path $work 'a.sqlite'
  $rc = Lane-Index $src $db 'index-a.log'
  Check 'index exits 0' ($rc -eq 0) "rc=$rc"
  $flows = Lane-Sql $db $rowSql
  Check 'data_flows has rows at all (POSITIVE CONTROL for every negative below)' ($null -ne $flows -and $flows.Count -gt 0) "rows=$(if ($null -eq $flows) { 0 } else { $flows.Count })"
  $acc   = Lane-Sql $db $accSql
  $loops = Lane-Sql $db $loopSql
  Check 'ds_field_accesses has rows' ($null -ne $acc -and $acc.Count -gt 0) "rows=$(if ($null -eq $acc) { 0 } else { $acc.Count })"
  Check 'loop_facts has rows' ($null -ne $loops -and $loops.Count -gt 0) "rows=$(if ($null -eq $loops) { 0 } else { $loops.Count })"
  if ($null -eq $acc)   { $acc = @() }
  if ($null -eq $loops) { $loops = @() }
  if ($null -eq $flows) { $flows = @() }
  function A([string]$Routine) { @($acc | Where-Object { $_.routine -eq $Routine }) }
  function F([string]$Routine) { @($flows | Where-Object { $_.routine -eq $Routine }) }
  function FlowsAt($a) { @($flows | Where-Object { $_.routine -eq $a.routine -and $_.dst_line -eq $a.line -and $_.dst_col -eq $a.col }) }

  Write-Host 'T1 by-name reads' -ForegroundColor Cyan
  $t = @((A 'Direct') | Where-Object { $_.mode -eq 'read' -and $_.line -eq $M.'M-READ2' })
  Check 'T1 two read rows at the product line' ($t.Count -eq 2) "rows=$($t.Count)"
  Check 'T1 QTY: byname, literal, AsFloat, dataset qryO, root other' (Has $t { $_.shape -eq 'byname' -and $_.field_name -eq 'QTY' -and $_.name_kind -eq 'literal' -and $_.accessor -eq 'AsFloat' -and $_.dataset_text -eq 'qryO' -and $_.root_kind -eq 'other' -and $_.root_name -eq 'qryO' -and $_.root_index -eq -1 -and $_.name_text -eq '' })
  Check 'T1 PRICE: byname, literal, AsFloat' (Has $t { $_.shape -eq 'byname' -and $_.field_name -eq 'PRICE' -and $_.name_kind -eq 'literal' -and $_.accessor -eq 'AsFloat' })

  Write-Host 'T2 accessor write through a Double local' -ForegroundColor Cyan
  $w = @((A 'Direct') | Where-Object { $_.mode -eq 'write' -and $_.line -eq $M.'M-ACCW' })
  Check 'T2 write row: shape accessor, field_text tblMTOTAL, name_kind component' ($w.Count -eq 1 -and $w[0].shape -eq 'accessor' -and $w[0].field_text -eq 'tblMTOTAL' -and $w[0].name_kind -eq 'component' -and $w[0].accessor -eq 'AsFloat' -and $w[0].dataset_text -eq '')
  if ($w.Count -eq 1) {
    $fw = FlowsAt $w[0]
    Check 'T2 flow rows at the SAME position are of kind write (the walk''s own row), never dsfield' ((Cnt $fw { $_.dst_kind -eq 'write' }) -gt 0 -and (Cnt $fw { $_.dst_kind -eq 'dsfield' }) -eq 0)
    Check 'T2 dsfield source QTY, via local, class float' (Has $fw { $_.src_kind -eq 'dsfield' -and $_.src_name -eq 'QTY' -and $_.src_line -eq $M.'M-READ2' -and $_.via_local -eq 1 -and $_.val_class -eq 'float' })
    Check 'T2 dsfield source PRICE, via local' (Has $fw { $_.src_kind -eq 'dsfield' -and $_.src_name -eq 'PRICE' -and $_.src_line -eq $M.'M-READ2' -and $_.via_local -eq 1 })
    $rd = @((A 'Direct') | Where-Object { $_.mode -eq 'read' -and $_.field_name -eq 'QTY' })
    Check 'T2 the dsfield source sits at the read row''s position' ($rd.Count -eq 1 -and (Has $fw { $_.src_kind -eq 'dsfield' -and $_.src_name -eq 'QTY' -and $_.src_line -eq $rd[0].line -and $_.src_col -eq $rd[0].col }))
  }

  Write-Host 'T3 by-name write' -ForegroundColor Cyan
  $w = @((A 'Direct') | Where-Object { $_.mode -eq 'write' -and $_.line -eq $M.'M-BYNAMEW' })
  Check 'T3 write row: byname NOTE on tblM, AsString' ($w.Count -eq 1 -and $w[0].shape -eq 'byname' -and $w[0].field_name -eq 'NOTE' -and $w[0].dataset_text -eq 'tblM' -and $w[0].accessor -eq 'AsString')
  $t3 = @()
  if ($w.Count -eq 1) {
    $t3 = FlowsAt $w[0]
    Check 'T3 flow: dst dsfield NOTE / tblM <- src dsfield NAME, direct' (Has $t3 { $_.dst_kind -eq 'dsfield' -and $_.dst_name -eq 'NOTE' -and $_.dst_receiver -eq 'tblM' -and $_.src_kind -eq 'dsfield' -and $_.src_name -eq 'NAME' -and $_.via_local -eq 0 -and $_.cond -eq 0 })
    Check 'T3 no write-kind row at that site (never both kinds)' ((Cnt $t3 { $_.dst_kind -eq 'write' }) -eq 0)
    Check 'T3 rhs range starts at the right side' ($w[0].rhs_start_line -eq $M.'M-BYNAMEW' -and $w[0].rhs_start_col -gt $w[0].col -and $w[0].rhs_end_col -gt $w[0].rhs_start_col -and $w[0].stmt_line -eq $M.'M-BYNAMEW' -and $w[0].stmt_col -lt $w[0].col)
  }

  Write-Host 'T4 literal right side' -ForegroundColor Cyan
  $w = @((A 'Direct') | Where-Object { $_.mode -eq 'write' -and $_.line -eq $M.'M-LITERAL' })
  Check 'T4 write row: values FLAG, no accessor, rhs range 4 wide (True)' ($w.Count -eq 1 -and $w[0].shape -eq 'values' -and $w[0].field_name -eq 'FLAG' -and $w[0].accessor -eq '' -and ($w[0].rhs_end_col - $w[0].rhs_start_col) -eq 4)
  Check 'T4 no flow row at that position (positive control: T3 has one)' ($w.Count -eq 1 -and (FlowsAt $w[0]).Count -eq 0 -and $t3.Count -gt 0)

  Write-Host 'T5 name built at run time' -ForegroundColor Cyan
  $w = @((A 'Direct') | Where-Object { $_.mode -eq 'write' -and $_.line -eq $M.'M-EXPR' })
  Check 'T5 write row: field_name empty, name_text vName, name_kind expr (a local variable)' ($w.Count -eq 1 -and $w[0].field_name -eq '' -and $w[0].name_text -eq 'vName' -and $w[0].name_kind -eq 'expr')
  Check 'T5 flow row: dsfield with an empty dst_name' ($w.Count -eq 1 -and (Has (FlowsAt $w[0]) { $_.dst_kind -eq 'dsfield' -and $_.dst_name -eq '' -and $_.dst_receiver -eq 'tblM' -and $_.src_kind -eq 'dsfield' }))

  Write-Host 'T6-T8 roots: field / local / param' -ForegroundColor Cyan
  $vm = A 'ViewModel'
  $w = @($vm | Where-Object { $_.mode -eq 'write' -and $_.line -eq $M.'M-VM-FIELD' })
  Check 'T6 FTbl.FieldByName(''X'') write: root_kind field' ($w.Count -eq 1 -and $w[0].root_kind -eq 'field' -and $w[0].root_name -eq 'FTbl' -and $w[0].field_name -eq 'X')
  if ($w.Count -eq 1) {
    $fw = FlowsAt $w[0]
    Check 'T6 exactly one destination kind, with a dsfield source A from parameter 0' (@($fw | ForEach-Object { $_.dst_kind } | Sort-Object -Unique).Count -eq 1 -and (Has $fw { $_.dst_kind -eq 'dsfield' -and $_.src_kind -eq 'dsfield' -and $_.src_name -eq 'A' -and $_.src_index -eq 0 }))
  }
  Check 'T8 pSrc.FieldByName(''A'') read: root_kind param, root_index 0' (Has $vm { $_.mode -eq 'read' -and $_.field_name -eq 'A' -and $_.root_kind -eq 'param' -and $_.root_index -eq 0 -and $_.root_name -eq 'pSrc' })
  $w = @($vm | Where-Object { $_.mode -eq 'write' -and $_.line -eq $M.'M-VM-LOCAL' })
  Check 'T7 vT[''Y''] write: shape default, root_kind local' ($w.Count -eq 1 -and $w[0].shape -eq 'default' -and $w[0].root_kind -eq 'local' -and $w[0].field_name -eq 'Y' -and $w[0].dataset_text -eq 'vT')
  if ($w.Count -eq 1) {
    $fw = FlowsAt $w[0]
    Check 'T7 exactly one destination kind (dsfield), with a dsfield source X' (@($fw | ForEach-Object { $_.dst_kind } | Sort-Object -Unique).Count -eq 1 -and (Has $fw { $_.dst_kind -eq 'dsfield' -and $_.dst_name -eq 'Y' -and $_.src_kind -eq 'dsfield' -and $_.src_name -eq 'X' }))
  }

  Write-Host 'T8b other shapes' -ForegroundColor Cyan
  $sh = A 'Shapes'
  Check 'find: bare qryO.FindField(''QTY'') is a read row, shape find, no accessor' (Has $sh { $_.line -eq $M.'M-FIND' -and $_.mode -eq 'read' -and $_.shape -eq 'find' -and $_.field_name -eq 'QTY' -and $_.accessor -eq '' })
  Check 'accessor read on a local (vF.AsFloat): row with root_kind local' (Has $sh { $_.line -eq $M.'M-LOCALACC' -and $_.mode -eq 'read' -and $_.shape -eq 'accessor' -and $_.field_text -eq 'vF' -and $_.root_kind -eq 'local' })
  $w = @($sh | Where-Object { $_.line -eq $M.'M-LOCALACC' -and $_.mode -eq 'write' })
  Check 'the field object read by name reaches the write through the local (dsfield QTY, via local)' ($w.Count -eq 1 -and (Has (FlowsAt $w[0]) { $_.src_kind -eq 'dsfield' -and $_.src_name -eq 'QTY' -and $_.src_line -eq $M.'M-FIND' -and $_.via_local -eq 1 }))
  Check 'index: tblM.Fields[0] write and qryC.Fields[1] read, name_kind index' ((Has $sh { $_.line -eq $M.'M-INDEX' -and $_.mode -eq 'write' -and $_.shape -eq 'index' -and $_.name_kind -eq 'index' -and $_.name_text -eq '0' -and $_.dataset_text -eq 'tblM' }) -and (Has $sh { $_.line -eq $M.'M-INDEX' -and $_.mode -eq 'read' -and $_.shape -eq 'index' -and $_.name_text -eq '1' -and $_.dataset_text -eq 'qryC' }))
  Check 'Clear on a by-name field: write, accessor Clear, no rhs range' (Has $sh { $_.line -eq $M.'M-CLEAR' -and $_.mode -eq 'write' -and $_.shape -eq 'byname' -and $_.accessor -eq 'Clear' -and $_.field_name -eq 'NOTE' -and $_.rhs_start_line -eq 0 })
  Check 'exactly one row for the Clear site (the core is not reported a second time)' ((Cnt $sh { $_.line -eq $M.'M-CLEAR' }) -eq 1)
  Check 'Assign: write, shape accessor, rhs range = the argument' (Has $sh { $_.line -eq $M.'M-ASSIGN' -and $_.mode -eq 'write' -and $_.shape -eq 'accessor' -and $_.accessor -eq 'Assign' -and $_.field_text -eq 'tblMNOTE' -and $_.rhs_start_line -eq $M.'M-ASSIGN' })
  Check 'FieldValues read and default-property read' ((Has $sh { $_.line -eq $M.'M-VALREAD' -and $_.mode -eq 'read' -and $_.shape -eq 'values' -and $_.field_name -eq 'NAME' }) -and (Has $sh { $_.line -eq $M.'M-DEFREAD' -and $_.mode -eq 'read' -and $_.shape -eq 'default' -and $_.field_name -eq 'CITY' -and $_.dataset_text -eq 'qryC' }))
  $ar = @($sh | Where-Object { $_.line -eq $M.'M-ACCREAD' -and $_.mode -eq 'read' })
  Check 'accessor READ rows: the private field and the parameter, NOT the form component' ($ar.Count -eq 2 -and (Has $ar { $_.field_text -eq 'FItem' -and $_.root_kind -eq 'field' }) -and (Has $ar { $_.field_text -eq 'pFld' -and $_.root_kind -eq 'param' -and $_.root_index -eq 0 }))
  $w = @($sh | Where-Object { $_.line -eq $M.'M-VIAFLT' -and $_.mode -eq 'write' })
  if ($w.Count -eq 1) {
    $fw = FlowsAt $w[0]
    Check 'accessor read on a parameter gives a dsfield source (index 0); on the private field the walk''s own ref at the same position' ((Has $fw { $_.src_kind -eq 'dsfield' -and $_.src_index -eq 0 -and $_.src_line -eq $M.'M-ACCREAD' }) -and (Has $fw { $_.src_kind -eq 'ref' -and $_.src_name -eq 'AsFloat' -and $_.src_line -eq $M.'M-ACCREAD' }))
  } else { Check 'M-VIAFLT write row' $false "rows=$($w.Count)" }
  $w = @($sh | Where-Object { $_.line -eq $M.'M-VIASTR' -and $_.mode -eq 'write' })
  Check 'a string local carries the dsfield sources NAME and CITY to a by-name write' ($w.Count -eq 1 -and (Has (FlowsAt $w[0]) { $_.dst_kind -eq 'dsfield' -and $_.src_kind -eq 'dsfield' -and $_.src_name -eq 'CITY' -and $_.via_local -eq 1 }))

  Write-Host 'T9 loops' -ForegroundColor Cyan
  $l = @($loops | Where-Object { $_.routine -eq 'Sum' })
  Check 'T9 Sum: one while loop, whole statement range, no parent' ($l.Count -eq 1 -and $l[0].kind -eq 'while' -and $l[0].start_line -eq $M.'M-WHILE' -and $l[0].end_line -eq $M.'M-WHILE-END' -and $l[0].parent -eq -1)
  Check 'T9 condition range lies on the while line, after the keyword' ($l.Count -eq 1 -and $l[0].cond_start_line -eq $M.'M-WHILE' -and $l[0].cond_end_line -eq $M.'M-WHILE' -and $l[0].cond_start_col -gt $l[0].start_col -and ($l[0].cond_end_col - $l[0].cond_start_col) -eq 'not qryL.Eof'.Length)
  $w = @((A 'Sum') | Where-Object { $_.mode -eq 'write' -and $_.line -eq $M.'M-SUMW' })
  Check 'T9 the write after the loop has a dsfield source AMOUNT inside the loop range, via local' ($w.Count -eq 1 -and $l.Count -eq 1 -and (Has (FlowsAt $w[0]) { $_.src_kind -eq 'dsfield' -and $_.src_name -eq 'AMOUNT' -and $_.src_line -gt $l[0].start_line -and $_.src_line -lt $l[0].end_line -and $_.via_local -eq 1 }))
  Check 'T9 for loop (positive control for the kind column)' (Has $loops { $_.routine -eq 'Shapes' -and $_.kind -eq 'for' -and $_.start_line -eq $M.'M-FOR' -and $_.end_line -eq $M.'M-FORBODY' -and $_.cond_start_line -eq $M.'M-FOR' -and $_.cond_start_col -gt $_.start_col -and ($_.cond_end_col - $_.cond_start_col) -eq 'i := 0 to 9'.Length })
  $fi = @($loops | Where-Object { $_.routine -eq 'Nested' -and $_.kind -eq 'for-in' })
  $rp = @($loops | Where-Object { $_.routine -eq 'Nested' -and $_.kind -eq 'repeat' })
  Check 'T9 for-in + nested repeat: parent = the for-in''s ordinal; until condition range' ($fi.Count -eq 1 -and $rp.Count -eq 1 -and $rp[0].parent -eq $fi[0].ordinal -and $fi[0].parent -eq -1 -and $rp[0].cond_start_line -eq $M.'M-UNTIL' -and $fi[0].cond_start_line -eq $M.'M-FORIN')
  Check 'T9 ordinals are 0..n-1 in file order' ((@($loops | ForEach-Object { [int]$_.ordinal }) -join ',') -eq ((0..($loops.Count - 1)) -join ','))

  Write-Host 'T10-T11 with bodies' -ForegroundColor Cyan
  $iw = A 'InWith'
  $w = @($iw | Where-Object { $_.mode -eq 'write' -and $_.line -eq $M.'M-WITH' })
  Check 'T10 write row: root_kind with, with_ctx tblM, TOTAL, dataset_text empty' ($w.Count -eq 1 -and $w[0].root_kind -eq 'with' -and $w[0].with_ctx -eq 'tblM' -and $w[0].field_name -eq 'TOTAL' -and $w[0].dataset_text -eq '' -and $w[0].root_name -eq '')
  Check 'T10 the read row keeps dataset_text qryO and carries the with context' (Has $iw { $_.mode -eq 'read' -and $_.line -eq $M.'M-WITH' -and $_.dataset_text -eq 'qryO' -and $_.field_name -eq 'QTY' -and $_.with_ctx -eq 'tblM' -and $_.root_kind -eq 'other' })
  if ($w.Count -eq 1) {
    $fw = FlowsAt $w[0]
    Check 'T11 6b: dsfield row with source QTY, cond 1' (Has $fw { $_.dst_kind -eq 'dsfield' -and $_.dst_name -eq 'TOTAL' -and $_.src_kind -eq 'dsfield' -and $_.src_name -eq 'QTY' -and $_.cond -eq 1 })
    Check 'T11 6b: the parameter in the right side is a param source' (Has $fw { $_.dst_kind -eq 'dsfield' -and $_.src_kind -eq 'param' -and $_.src_index -eq 0 -and $_.cond -eq 1 })
  }
  $w2 = @($iw | Where-Object { $_.mode -eq 'write' -and $_.line -eq $M.'M-WITH2' })
  Check 'T10 two with entities: innermost first' ($w2.Count -eq 1 -and $w2[0].with_ctx -eq 'qryC|tblM' -and $w2[0].shape -eq 'values')
  Check 'T10 accessor read inside with: row emitted (private field)' (Has $iw { $_.mode -eq 'read' -and $_.line -eq $M.'M-WITH2' -and $_.shape -eq 'accessor' -and $_.field_text -eq 'FItem' })
  $inWith = @((F 'InWith') | Where-Object { $_.dst_line -eq $M.'M-WITH' -or $_.dst_line -eq $M.'M-WITH2' })
  Check 'T11 every flow row whose destination lies in a with body is a dsfield row with cond 1' ($inWith.Count -gt 0 -and (Cnt $inWith { $_.dst_kind -ne 'dsfield' -or $_.cond -ne 1 }) -eq 0) "rows=$($inWith.Count)"

  Write-Host 'T12 through calls' -ForegroundColor Cyan
  $w = @((A 'Fill') | Where-Object { $_.mode -eq 'write' -and $_.line -eq $M.'M-FILL' })
  Check 'T12 Fill: write row root_kind param, root_index 0' ($w.Count -eq 1 -and $w[0].root_kind -eq 'param' -and $w[0].root_index -eq 0 -and $w[0].field_name -eq 'T')
  Check 'T12 flow: dst dsfield, dst_index 0 <- src param 1' ($w.Count -eq 1 -and (Has (FlowsAt $w[0]) { $_.dst_kind -eq 'dsfield' -and $_.dst_index -eq 0 -and $_.dst_name -eq 'T' -and $_.dst_receiver -eq 'pDS' -and $_.src_kind -eq 'param' -and $_.src_index -eq 1 }))
  $c = @((F 'Caller') | Where-Object { $_.dst_kind -eq 'arg' -and $_.dst_name -eq 'Fill' -and $_.dst_line -eq $M.'M-CALL' })
  Check 'T12 caller: argument 1 has a dsfield source RATE; argument 0 has a row too' ((Has $c { $_.dst_index -eq 1 -and $_.src_kind -eq 'dsfield' -and $_.src_name -eq 'RATE' }) -and (Has $c { $_.dst_index -eq 0 }))

  Write-Host 'negatives' -ForegroundColor Cyan
  Check 'Plain (no dataset code): no access row, no dsfield flow (positive control: Direct has both)' ((A 'Plain').Count -eq 0 -and (Cnt (F 'Plain') { $_.dst_kind -eq 'dsfield' -or $_.src_kind -eq 'dsfield' }) -eq 0 -and (A 'Direct').Count -gt 0 -and (F 'Plain').Count -gt 0)
  Check 'access ordinals are 0..n-1 in file order' ($acc.Count -gt 0 -and (@($acc | ForEach-Object { [int]$_.ordinal }) -join ',') -eq ((0..($acc.Count - 1)) -join ','))
  $dupe = @($acc | Group-Object { "$($_.line)|$($_.col)|$($_.mode)" } | Where-Object { $_.Count -gt 1 })
  Check 'no two access rows share a position and mode' ($dupe.Count -eq 0) "dupes=$($dupe.Count)"
  $both = @($flows | Group-Object { "$($_.routine)|$($_.dst_line)|$($_.dst_col)" } | Where-Object { @($_.Group | ForEach-Object { $_.dst_kind } | Where-Object { $_ -in @('write', 'dsfield') } | Sort-Object -Unique).Count -gt 1 })
  Check 'never a write row and a dsfield row at one position' ($both.Count -eq 0) "sites=$($both.Count)"

  if ($BaseExe -ne '') {
    Write-Host 'T13 unchanged rows / T14 reader safety (against the base engine)' -ForegroundColor Cyan
    $dbBase = Join-Path $work 'base.sqlite'
    $rcB = Lane-Index $src $dbBase 'index-base.log' $BaseExe
    Check 'base engine indexes the fixture' ($rcB -eq 0) "rc=$rcB"
    $baseFlows = Lane-Rows $dbBase $rowSql $BaseExe
    $oldNow  = @($flows | Where-Object { Is-Old $_ } | ForEach-Object { Row-Key $_ } | Sort-Object)
    $oldBase = @($baseFlows | ForEach-Object { Row-Key $_ } | Sort-Object)
    $diff = @(Compare-Object $oldBase $oldNow)
    Check 'T13 the rows without a dsfield kind are EXACTLY the base engine''s rows' ($oldBase.Count -gt 0 -and $diff.Count -eq 0) "base=$($oldBase.Count) now=$($oldNow.Count) diff=$($diff.Count)"
    $ctl = @(Compare-Object $oldBase @($oldNow | Select-Object -Skip 1))
    Check 'T13 positive control: the comparison reports a removed row' ($ctl.Count -eq 1)
    Check 'T13 the base engine has no dsfield row (so every dsfield row is this lane''s)' ((Cnt $baseFlows { -not (Is-Old $_) }) -eq 0 -and (Cnt $flows { -not (Is-Old $_) }) -gt 0)
    $lintNow  = & { $ErrorActionPreference = 'Continue'; & $Exe lint $probe --db $db --format json 2>$null }
    $lintBase = & { $ErrorActionPreference = 'Continue'; & $BaseExe lint $probe --db $dbBase --format json 2>$null }
    $jn = @(($lintNow -join "`n") | ConvertFrom-Json | ForEach-Object { $_ } | ForEach-Object { "$($_.rule)|$($_.start_line)|$($_.message)" } | Sort-Object)
    $jb = @(($lintBase -join "`n") | ConvertFrom-Json | ForEach-Object { $_ } | ForEach-Object { "$($_.rule)|$($_.start_line)|$($_.message)" } | Sort-Object)
    Check 'T14 lint findings on the fixture equal the base engine''s (and there are some)' ($jb.Count -gt 0 -and @(Compare-Object $jb $jn).Count -eq 0) "base=$($jb.Count) now=$($jn.Count)"
  } else { Write-Host 'T13 / T14 skipped: pass -BaseExe <engine without lane EXT-B3>' -ForegroundColor Yellow }

  Write-Host 'T16 incremental reindex' -ForegroundColor Cyan
  $text = [IO.File]::ReadAllText($probe)
  $text = $text.Replace("  tblMTOTAL.AsFloat := s; { M-SUMW }", "  tblMTOTAL.AsFloat := s; { M-SUMW }`r`n  tblM.FieldByName('EXTRA').AsFloat := s;")
  [IO.File]::WriteAllText($probe, $text, [Text.Encoding]::ASCII)
  $rc = Lane-Index $src $db 'index-b.log'
  $acc2  = Lane-Rows $db $accSql
  $loop2 = Lane-Rows $db $loopSql
  $dbF = Join-Path $work 'fresh.sqlite'
  $rcF = Lane-Index $src $dbF 'index-fresh.log'
  $accF  = Lane-Rows $dbF $accSql
  $loopF = Lane-Rows $dbF $loopSql
  Check 'T16 reindex exits 0, the new write is there' ($rc -eq 0 -and $rcF -eq 0 -and (Has $acc2 { $_.field_name -eq 'EXTRA' -and $_.mode -eq 'write' }))
  Check 'T16 one more access row than before, ordinals still 0..n-1' ($acc.Count -gt 0 -and $acc2.Count -eq $acc.Count + 1 -and (@($acc2 | ForEach-Object { [int]$_.ordinal }) -join ',') -eq ((0..($acc2.Count - 1)) -join ','))
  Check 'T16 counts equal a fresh index' ($acc2.Count -eq $accF.Count -and $loop2.Count -eq $loopF.Count -and $loop2.Count -eq $loops.Count) "acc=$($acc2.Count)/$($accF.Count) loops=$($loop2.Count)/$($loopF.Count)"
}
finally {
  if (-not $KeepScratch) { try { [IO.Directory]::Delete($work, $true) } catch { } } else { Write-Host "scratch kept: $work" }
}

Write-Host ''
Write-Host "run_v156_B14: pass=$($script:pass) fail=$($script:fail)" -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
exit $(if ($script:fail -eq 0) { 0 } else { 1 })
