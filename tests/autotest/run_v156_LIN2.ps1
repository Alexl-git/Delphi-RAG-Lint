#Requires -Version 7.3
<#
  run_v156_LIN2.ps1 -- 1.56 lane LIN-2: `repo read-dfm --db <index>` marks a field derived and proposes its
  DL_FIELD_INPUTS rows as UNCHECKED change-set rows (src\sql\DRagLint.FieldRepo.DfmReadDerived.pas; design
  2026-11-27-derived-field-lineage-design.md sections 3.1, 3.2, 3.3; acceptance shape of its 6.3).

  Copies tests\fixtures\v156\LIN2 to a scratch folder, indexes the COPY with the engine under test, seeds a repository
  from lin2_schema.sql and drives `repo read-dfm`:
    N   no --db: the one line `lineage: skipped (no index)`, no derived row
    A   dry run: TOTAL derived(direct) with its DL_FIELD_INPUTS row, NET (home table only: no input row), SUMQ
        aggregate (no path: unplaced), all UNCHECKED; RATE2 unknown = a warning and no row; STAMP / IDLE / QTY not
        marked; no byte of the repository written; --json carries checked=false
    B   --apply writes the planner's checked rows and NONE of the derived ones; --select of their ids writes them
        (DERIVED_KIND, the NOTES lineage block, the input row); repo check clean; a SECOND read plans nothing; the
        sources are untouched
    C   a unit changed after indexing: `index stale`, nothing proposed; a unit the index does not hold: one line
    D   an input whose FK relation is neither stored nor planned: the field is proposed, the input is not, with the
        reason; once the relation is stored the input row is proposed
    E   an index that does not open: one `lineage: skipped (...)` line, exit 0
    W   write-dfm does not write a derived row into another dataset
  Positive controls: every "no row / not marked" check sits beside A1 (same form, same read); C1 beside A1 (same
  index before the edit); D1 beside D2. An engine without the lane (the base) fails N1, A1-A5, B2-B5, C, D, E.
  A MISSING engine is a FAIL, never a skip. Run: pwsh -File tests\autotest\run_v156_LIN2.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$KeepScratch)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$ErrorActionPreference = 'Continue'
$script:Pass = 0
$script:Fail = 0
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $(if ($ok) { '' } else { $d })) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if ($ok) { $script:Pass++ } else { $script:Fail++ }
}
Write-Host '== v156 LIN-2: read-dfm marks derived fields, proposes their inputs unchecked ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "V156 LIN2: FAIL -- no engine at $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v156-lin2-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($work) | Out-Null
function Run([string[]]$a) {
  $out = (& { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
}
function CopyFlat($from, $to, [string[]]$names) {
  [IO.Directory]::CreateDirectory($to) | Out-Null
  foreach ($n in $names) { [IO.File]::Copy((Join-Path $from $n), (Join-Path $to $n), $true) }
}
function NewRepo($path, $ddl) {
  $null = Run @('repo', 'init', '--repo', $path)
  Run @('repo', 'seed-fb', '--ddl', $ddl, '--repo', $path, '--apply')
}
function ReadDfm($repoFile, $dfm, [string[]]$more = @()) {
  Run (@('repo', 'read-dfm', '--repo', $repoFile, '--dfm', $dfm, '--direction', 'dfm-to-repo') + $more)
}
function Has($text, $pattern) { [regex]::IsMatch($text, $pattern) }
function TreeHash($dir) {
  (Get-ChildItem -LiteralPath $dir -File | Sort-Object Name | ForEach-Object { $_.Name + '=' + (Get-FileHash -LiteralPath $_.FullName).Hash }) -join ';'
}
try {
  $fixSrc = Join-Path $Repo 'tests\fixtures\v156\LIN2'
  $fx = Join-Path $work 'fx'
  CopyFlat $fixSrc $fx @('uLin2.pas', 'uLin2.dfm', 'uLin2b.pas', 'uLin2b.dfm', 'lin2_schema.sql')
  $ddl = Join-Path $fx 'lin2_schema.sql'
  $db = Join-Path $work 'idx.sqlite'
  $ix = Run @('index', $fx, '--db', $db)
  Check 'S0 the fixture copy indexes' (($ix.Code -eq 0) -and (Test-Path -LiteralPath $db)) $ix.Out
  $x = Join-Path $work 'x.dlrepo'
  $s = NewRepo $x $ddl
  Check 'S1 the fixture schema seeds (ORDERS -> CUSTOMERS by one FK)' ($s.Code -eq 0) $s.Out
  $dfm = Join-Path $fx 'uLin2.dfm'
  $withDb = @('--db', $db)
  $h0 = (Get-FileHash -LiteralPath $x).Hash
  $src0 = TreeHash $fx

  # ---- N: no index ----
  $n = ReadDfm $x $dfm
  Check 'N1 without --db: the one line "lineage: skipped (no index)" and no derived row' (($n.Code -eq 0) -and (Has $n.Out '(?m)^warning: lineage: skipped \(no index\)\r?$') -and -not (Has $n.Out 'derived\(')) $n.Out

  # ---- A: dry run ----
  $a = ReadDfm $x $dfm $withDb
  $o = $a.Out
  Check 'A0 the read runs' ($a.Code -eq 0) "exit=$($a.Code)`n$o"
  Check 'A1 TOTAL: insert derived(direct) with its inputs as macros, UNCHECKED' (Has $o '(?m)^\[\d+\] insert DL_FIELDS_INFO ORDERS\|TOTAL:  -> derived\(direct\); inputs \{\{QTY\}\}, \{\{PRICE\}\}, \{\{CUSTOMERS\.DISCOUNT\}\}\r?\n  \(unchecked\)') $o
  Check 'A2 TOTAL: its DL_FIELD_INPUTS row (alias CUSTOMERS, the one path), UNCHECKED' (Has $o '(?m)^\[\d+\] insert DL_FIELD_INPUTS ORDERS\|TOTAL\|\|CUSTOMERS:  -> PATH=FK_ORDERS_CUST; TARGET_TABLE=CUSTOMERS \(rule single\)\r?\n  \(unchecked\)') $o
  Check 'A3 NET: derived(direct) from the home table only: marked UNCHECKED, no input row' ((Has $o '(?m)^\[\d+\] insert DL_FIELDS_INFO ORDERS\|NET:  -> derived\(direct\); inputs \{\{QTY\}\}, \{\{PRICE\}\}\r?\n  \(unchecked\)') -and -not (Has $o 'DL_FIELD_INPUTS ORDERS\|NET')) $o
  Check 'A4 SUMQ: derived(aggregate) UNCHECKED; no path ORDERS -> ORDER_LINES = unplaced, no input row' ((Has $o '(?m)^\[\d+\] insert DL_FIELDS_INFO ORDERS\|SUMQ:  -> derived\(aggregate\); inputs -\r?\n  \(unchecked\)') -and (Has $o 'warning: ORDERS\.SUMQ input qryLines\.AMOUNT: no path ORDERS -> ORDER_LINES: no DL_FIELD_INPUTS row proposed') -and -not (Has $o 'DL_FIELD_INPUTS ORDERS\|SUMQ')) $o
  Check 'A5 RATE2: unknown lineage = a warning with the reason, NO row' ((Has $o 'warning: [^\n]*uLin2\.dfm tblOrders RATE2: derived\(unknown\): result of CalcRate \(calls are not followed\): nothing proposed') -and -not (Has $o '(?m)^\[\d+\] \w+ \S+ ORDERS\|RATE2')) $o
  Check 'A6 STAMP (:= Now) and IDLE (never written) are not marked; STAMP says why' ((Has $o 'warning: [^\n]*uLin2\.dfm tblOrders STAMP: no table: written in code, no field input') -and -not (Has $o '(?m)^\[\d+\] \w+ \S+ ORDERS\|(STAMP|IDLE)') -and -not (Has $o 'warning: [^\n]*IDLE')) $o
  Check 'A7 a non-derived field is unchanged: QTY (a real column code overwrites) and PRICE get no change' (-not (Has $o '(?m)^\[\d+\] \w+ \S+ ORDERS\|(QTY|PRICE)\b')) $o
  Check 'A8 the dry run writes no byte' ((Has $o 'dry run: nothing written') -and ($h0 -eq (Get-FileHash -LiteralPath $x).Hash)) $o
  $j = ReadDfm $x $dfm ($withDb + '--json')
  $jo = $null; try { $jo = $j.Out.Substring($j.Out.IndexOf('{')) | ConvertFrom-Json | ForEach-Object { $_ } } catch { }
  $jt = if ($jo) { @($jo.changeSet.changes | Where-Object { $_.target -eq 'DL_FIELDS_INFO ORDERS|TOTAL' }) } else { @() }
  $ji = if ($jo) { @($jo.changeSet.changes | Where-Object { $_.target -eq 'DL_FIELD_INPUTS ORDERS|TOTAL||CUSTOMERS' }) } else { @() }
  Check 'A9 --json: the derived row and its input are in the change set with checked = false' (($jt.Count -eq 1) -and ($jt[0].checked -eq $false) -and ($jt[0].op -eq 'insert') -and ($ji.Count -eq 1) -and ($ji[0].checked -eq $false)) $j.Out

  # ---- B: apply ----
  $b = ReadDfm $x $dfm ($withDb + '--apply')
  $bk = Join-Path $work 'bk1.txt'
  $null = Run @('repo', 'backup', '--repo', $x, '--out', $bk)
  $t1 = if (Test-Path -LiteralPath $bk) { [IO.File]::ReadAllText($bk) } else { '' }
  Check 'B1 --apply writes the checked rows only: the calc field and its input are stored, no derived row is' (($b.Code -eq 0) -and $t1.Contains('[DL_FIELD_INPUTS ORDERS|CALCD||CUSTOMERS]') -and -not $t1.Contains('[DL_FIELDS_INFO ORDERS|TOTAL]') -and -not $t1.Contains('[DL_FIELD_INPUTS ORDERS|TOTAL||CUSTOMERS]') -and -not $t1.Contains('dl:lineage')) $b.Out
  $a2 = ReadDfm $x $dfm $withDb
  $ids = @([regex]::Matches($a2.Out, '(?m)^\[(\d+)\] insert (DL_FIELDS_INFO ORDERS\|(TOTAL|NET|SUMQ)|DL_FIELD_INPUTS ORDERS\|TOTAL\|\|CUSTOMERS):') | ForEach-Object { $_.Groups[1].Value })
  $sel = Join-Path $work 'sel.txt'
  [IO.File]::WriteAllLines($sel, [string[]]$ids)
  $b2 = ReadDfm $x $dfm ($withDb + @('--select', $sel))
  Check 'B2 --select of the four derived ids applies them' (($ids.Count -eq 4) -and ($b2.Code -eq 0) -and (Has $b2.Out '(?m)^applied: 4 changes')) "ids=$($ids -join ',')`n$($b2.Out)"
  $bk2 = Join-Path $work 'bk2.txt'
  $null = Run @('repo', 'backup', '--repo', $x, '--out', $bk2)
  $t2 = if (Test-Path -LiteralPath $bk2) { [IO.File]::ReadAllText($bk2) } else { '' }
  $rowAt = $t2.IndexOf('[DL_FIELDS_INFO ORDERS|TOTAL]')
  $row = if ($rowAt -ge 0) { $t2.Substring($rowAt, [Math]::Min(1600, $t2.Length - $rowAt)) } else { '' }
  $row = if (($row.Length -gt 1) -and ($row.IndexOf("`n[", 1) -gt 0)) { $row.Substring(0, $row.IndexOf("`n[", 1)) } else { $row }
  Check 'B3a TOTAL is stored: FIELD_KIND 1, DERIVED_KIND direct, no CALC_BODY' ((Has $row '(?m)^FIELD_KIND=1\r?$') -and (Has $row '(?m)^DERIVED_KIND=direct\r?$') -and -not (Has $row '(?m)^CALC_BODY')) $row
  Check 'B3b its NOTES hold the lineage block: kind, home, write + event, inputs, expr with macros, via' ((Has $row '\[dl:lineage 1\]') -and (Has $row 'kind: direct') -and (Has $row 'home: ORDERS by dataset fLin2\.tblOrders') -and (Has $row 'write: uLin2\.TfLin2\.tblOrdersAfterOpen:\d+ event tblOrders\.AfterOpen') -and (Has $row 'inputs: \{\{QTY\}\}, \{\{PRICE\}\}, \{\{CUSTOMERS\.DISCOUNT\}\}') -and (Has $row 'expr: \{\{TOTAL\}\}\.AsFloat := d \* \(1 - qryCust\.FieldByName\(''DISCOUNT''\)\.AsFloat\);') -and (Has $row 'via: d := \{\{QTY\}\}\.AsFloat \* \{\{PRICE\}\}\.AsFloat;') -and (Has $row '\[/dl:lineage\]')) $row
  Check 'B3c the input row is stored with its path; SUMQ is stored as aggregate with its loop' ((Has $t2 '\[DL_FIELD_INPUTS ORDERS\|TOTAL\|\|CUSTOMERS\]\r?\nPATH=FK_ORDERS_CUST\r?\nTARGET_TABLE=CUSTOMERS') -and (Has $t2 '(?m)^DERIVED_KIND=aggregate\r?$') -and (Has $t2 'loop: while not qryLines\.Eof \(ORDER_LINES\)')) $t2.Substring([Math]::Max(0, $t2.Length - 1200))
  $c = Run @('repo', 'check', '--repo', $x)
  Check 'B4 repo check is clean after the apply' (($c.Code -eq 0) -and ($c.Out -match 'check: clean')) $c.Out
  $a3 = ReadDfm $x $dfm $withDb
  Check 'B5 a SECOND read plans nothing (fixpoint)' (($a3.Code -eq 0) -and (Has $a3.Out '(?m)^direction dfm-to-repo, 0 changes, 0 blocked, 0 unchecked')) $a3.Out
  Check 'B6 no source file of the fixture changed' ($src0 -eq (TreeHash $fx)) ''

  # ---- W: write-dfm ----
  $w = Run @('repo', 'write-dfm', '--repo', $x, '--dfm', (Join-Path $fx 'uLin2b.dfm'), '--direction', 'repo-to-dfm', '--dataset', 'tblOrders', '--names', 'NET')
  Check 'W1 write-dfm does not write a derived row into another dataset (its insert is blocked)' (($w.Code -eq 0) -and (Has $w.Out '(?m)^\[\d+\] insert uLin2b\.dfm tblOrdersNET:[^\n]*\r?\n  BLOCKED: ')) $w.Out

  # ---- D: the relation of the path is not stored ----
  $z = Join-Path $work 'z.dlrepo'
  $null = NewRepo $z $ddl
  $dfmB = Join-Path $fx 'uLin2b.dfm'
  $d = ReadDfm $z $dfmB $withDb
  Check 'D1 relation neither stored nor planned: the field, the relation (LIN-3) and the input are proposed, all UNCHECKED, no warning' ((Has $d.Out '(?m)^\[\d+\] insert DL_FIELDS_INFO ORDERS\|REBATE:  -> derived\(direct\); inputs \{\{QTY\}\}, \{\{CUSTOMERS\.DISCOUNT\}\}\r?\n  \(unchecked\)') -and (Has $d.Out '(?m)^\[\d+\] insert DL_RELATIONS FK_ORDERS_CUST:[^\n]*\r?\n  \(unchecked\)') -and (Has $d.Out '(?m)^\[\d+\] insert DL_FIELD_INPUTS ORDERS\|REBATE\|\|CUSTOMERS:[^\n]*\r?\n  \(unchecked\)') -and -not (Has $d.Out 'neither stored')) $d.Out
  $null = ReadDfm $z $dfm @('--apply')
  $d2 = ReadDfm $z $dfmB $withDb
  Check 'D2 once the relation is stored the input row is proposed, UNCHECKED' ((Has $d2.Out '(?m)^\[\d+\] insert DL_FIELDS_INFO ORDERS\|REBATE:  -> derived\(direct\); inputs \{\{QTY\}\}, \{\{CUSTOMERS\.DISCOUNT\}\}\r?\n  \(unchecked\)') -and (Has $d2.Out '(?m)^\[\d+\] insert DL_FIELD_INPUTS ORDERS\|REBATE\|\|CUSTOMERS:  -> PATH=FK_ORDERS_CUST; TARGET_TABLE=CUSTOMERS \(rule single\)\r?\n  \(unchecked\)')) $d2.Out

  # ---- E: an index that does not open ----
  $bad = Join-Path $work 'bad.sqlite'
  [IO.File]::WriteAllText($bad, 'not a database')
  $e = ReadDfm $z $dfmB @('--db', $bad)
  Check 'E1 an index that does not open: one "lineage: skipped (...)" line, exit 0, no derived row' (($e.Code -eq 0) -and (Has $e.Out '(?m)^warning: lineage: skipped \((?!no index)[^\n]+\)\r?$') -and -not (Has $e.Out 'derived\(')) $e.Out

  # ---- C: stale / not indexed (LAST: it edits the fixture copy) ----
  $other = Join-Path $work 'other'
  CopyFlat $fixSrc $other @('uLin2b.pas', 'uLin2b.dfm')
  $y = Join-Path $work 'y.dlrepo'
  $null = NewRepo $y $ddl
  $c2 = ReadDfm $y (Join-Path $other 'uLin2b.dfm') $withDb
  Check 'C2 a unit the index does not hold: one line, nothing proposed' (($c2.Code -eq 0) -and (Has $c2.Out 'warning: lineage: uLin2b\.pas is not in the index: its 1 fields without a table column are not looked at') -and -not (Has $c2.Out 'derived\(')) $c2.Out
  $c0 = ReadDfm $y $dfm $withDb
  [IO.File]::AppendAllText((Join-Path $fx 'uLin2.pas'), "{ edited after indexing }`r`n")
  $c1 = ReadDfm $y $dfm $withDb
  Check 'C1 a unit changed after indexing: "index stale", nothing proposed (control: the same read before the edit proposes TOTAL)' ((Has $c0.Out 'insert DL_FIELDS_INFO ORDERS\|TOTAL:  -> derived\(direct\)') -and ($c1.Code -eq 0) -and (Has $c1.Out 'warning: lineage: index stale for uLin2[^\n]*: nothing proposed for its 6 fields without a table column \(reindex, then read again\)') -and -not (Has $c1.Out 'derived\(') -and -not (Has $c1.Out 'DL_FIELD_INPUTS ORDERS\|TOTAL')) $c1.Out
}
catch {
  Check 'X0 the runner ran to its end' $false ("$_")
}
finally {
  if (-not $KeepScratch) { try { [IO.Directory]::Delete($work, $true) } catch { } }
}
Write-Host ("Summary: pass={0} fail={1}" -f $script:Pass, $script:Fail)
if (($script:Fail -gt 0) -or ($script:Pass -eq 0)) { Write-Host 'V156 LIN2: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'V156 LIN2: PASS' -ForegroundColor Green
exit 0
