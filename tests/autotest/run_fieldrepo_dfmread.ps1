#Requires -Version 7.3
<#
  run_fieldrepo_dfmread.ps1 -- TT-DFMREAD (1.54): `repo read-dfm`, the DFM -> field repository change set.

  PART 1  builds and runs tests\fieldrepo\DfmReadTests.dpr (selection rules, SELECT reader, handler slices + macros).
  PART 2  the built engine on tests\fixtures\fieldrepo\dfmread (TTable, TQuery, TFDQuery, TFDMemTable; every field kind):
    D1  dry run: kinds, tables, unresolved datasets and fields, header counts, no byte written; inherited fields reported
    D2  calc bodies with component macros, another field's statement left out, IsNull
    D3  lookups: same form, data module of the same folder, unresolved dataset + multi-field key BLOCKED
    D4  OnGetText -> ONGETTEXT_BODY, an empty handler is reported; a value too long for its column BLOCKED
    D5  two datasets that disagree = unchecked alternatives
    D6  a binary DFM gives the same change set as its text form
    D7  --dataset reads one dataset; an unknown one exits 1
    D8  usage: no --direction / a wrong one / no --dfm / unknown --select id = exit 2, nothing written; --dry-run wins
    D9  --apply writes the checked changes; `repo check` sees consistent kinds; a second read has no checked change left
    D10 --select: both alternatives refused, one applied; an update without its row refused
    D11 a schema column is not turned into a calc field; a data field the schema does not have is blocked; non-PK lookup key warned
    D12 --json is one JSON object with the same counts
    D13 a second folder: lookup datasets come from the folder of each DFM; an unreadable DFM beside it is a warning
    D14 continued + quoted strings, two components of one field, an inline frame's dataset, a dataset without fields
    D15 apply is one transaction; repository columns the DFM does not state survive apply
    D16 the four TField events and the two DBTable column events -> their columns; Clear / IsNull bodies
    D17 grid column order: bound, twice bound, unbound, banded, data source of a data module, join; other views reported
    D18 apply, repo check, second read; a moved column = one update per index; a vanished column = unchecked delete
    D19 a schema-2 repository is refused until repo migrate; D20 two datasets + alignment: a new row has no ALIGNMENT -2
  Run: pwsh -File tests\autotest\run_fieldrepo_dfmread.ps1 [-Exe <drag-lint.exe>] [-SkipUnit]
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$SkipUnit)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $(if ($ok) { '' } else { $d })) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
Write-Host '== repo read-dfm ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-repo-dfm-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
function Run([string[]]$a) {
  $o = & $Exe @a 2>&1
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
function Dfm([string[]]$more, $dfm = $script:dfm, $r = $script:x) { Run (@('repo', 'read-dfm', '--repo', $r, '--dfm', $dfm, '--direction', 'dfm-to-repo') + $more) }
function NewRepo($name) { $p = Join-Path $work $name; $null = Run @('repo', 'init', '--repo', $p); $p }
function Has($r, $text) { $r.Out.Contains($text) }
try {
  # ---- part 1 ----
  if (-not $SkipUnit) {
    $bat = Join-Path $Repo 'build\_build_fieldrepo_dfmread_tests_local.bat'
    $blog = Join-Path $work 'build.log'
    Start-Process -FilePath cmd.exe -ArgumentList ('/c ""' + $bat + '" "' + $work + '" > "' + $blog + '" 2>&1"') -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    Check 'U0 the unit tests build' (($bl -match 'BUILD_EXITCODE=0') -and ($bl -notmatch 'Error: E\d+')) $blog
    $u = (& (Join-Path $work 'DfmReadTests.exe') 2>&1 | ForEach-Object { "$_" })
    $uc = $LASTEXITCODE
    $u | Where-Object { $_ -match '^FAIL' } | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    $sum = ($u | Where-Object { $_ -match '^Summary: ' } | Select-Object -Last 1)
    Check "U1 unit tests ($sum)" (($uc -eq 0) -and ($sum -match 'pass=[1-9]\d* fail=0$')) $sum
  }
  # ---- part 2 ----
  $fix = Join-Path $work 'forms'
  [IO.Directory]::CreateDirectory($fix) | Out-Null
  Get-ChildItem (Join-Path $Repo 'tests\fixtures\fieldrepo\dfmread') -File | ForEach-Object { [IO.File]::Copy($_.FullName, (Join-Path $fix $_.Name)) }
  $script:dfm = Join-Path $fix 'uOrders.dfm'
  $script:x = NewRepo 'x.dlrepo'
  $h0 = (Get-FileHash -LiteralPath $x).Hash
  $r = Dfm @()
  Check 'D1a kinds and table of a TTable' (Has $r 'tblOrders (TTable) -> ORDERS: 5 data, 3 calc, 3 lookup, 1 internal-calc, 1 aggregate') $r.Out
  Check 'D1b one-table SELECT; the computed column has no table column' ((Has $r 'qryTools2 (TFDQuery) -> TOOLS: 3 data') -and (Has $r "`n  no table column: Cnt`n")) $r.Out
  Check 'D1c join and TFDMemTable unresolved, named, never guessed' ((Has $r 'qryJoin (TQuery) -> UNRESOLVED (the SQL reads 2 tables: ORDERS TOOLS)') -and (Has $r 'memX (TFDMemTable) -> UNRESOLVED (no TableName and no SQL in the DFM)')) $r.Out
  Check 'D1d totals, header, dry run, no byte written' (($r.Code -eq 0) -and (Has $r 'total 6 datasets, 2 unresolved; 13 data, 4 calc, 3 lookup, 1 internal-calc, 1 aggregate; 3 without a table column') -and (Has $r 'direction dfm-to-repo, 21 changes, 4 blocked, 2 unchecked') -and (Has $r 'dry run: nothing written') -and ($h0 -eq (Get-FileHash -LiteralPath $x).Hash)) "exit=$($r.Code)`n$($r.Out)"
  $ri = Dfm @() (Join-Path $fix 'uChild.dfm')
  Check 'D1e inherited dataset and fields are reported, not guessed' ((Has $ri 'tblOrders (TTable) -> UNRESOLVED (no TableName and no SQL in the DFM (inherited: its own properties are in the ancestor''s DFM))') -and (Has $ri '1 inherited fields not read (FieldName is in the ancestor''s DFM): tblOrdersQTY')) $ri.Out
  Check 'D2a calc body with macros' (Has $r 'ORDERS|TOTAL:  -> FIELD_KIND=2; FIELD_AS_TYPE=AsFloat; VAR_TYPE=double; CALC_BODY={{TOTAL}}.Value := {{QTY}}.Value * {{PRICE}}.Value;') $r.Out
  Check 'D2b internal-calc body holds only its own statement' (Has $r "CALC_BODY=if {{TOTAL}}.Value > 100 then\r\n  {{BIG}}.AsString := 'yes'\r\nelse\r\n  {{BIG}}.AsString := 'no';`n") $r.Out
  Check 'D2c IsNull travels with the insert' (Has $r 'CALC_BODY={{LATE}}.Value := not {{PRICE}}.IsNull;') $r.Out
  Check 'D2d a calc field nobody assigns is reported' (Has $r 'tblOrdersORPHAN: no CALC_BODY: tblOrdersCalcFields does not assign it') $r.Out
  Check 'D2e aggregate expression' (Has $r 'ORDERS|SUMQ:  -> FIELD_KIND=5; CALC_BODY=SUM(Qty)') $r.Out
  Check 'D3a lookup wiring, dataset of the form' (Has $r 'SOURCEKEY=TOOLID; DESTKEY=ID; DESTVALUE=NAME; DESTTABLE=TOOLS') $r.Out
  Check 'D3b lookup dataset of a data module in the folder' (Has $r 'DESTKEY=CODE; DESTVALUE=TEXT; DESTTABLE=REASONS') $r.Out
  Check 'D3c unresolved dataset and multi-field key BLOCKED' ((Has $r "ORDERS|GONE SOURCEKEY:  -> A;B`n  BLOCKED: multi-field lookup key") -and (Has $r "ORDERS|GONE DESTTABLE:  -> dmNowhere.tblX`n  BLOCKED: unresolved lookup dataset dmNowhere.tblX")) $r.Out
  Check 'D4a OnGetText stored in its column' (($r.Out -match 'insert DL_FIELDS_INFO ORDERS\|QTY: [^\n]*ONGETTEXT_BODY=if \{\{LATE\}\}\.Value then\\r\\n  Text := ''!'' \+ Sender\.AsString;') -and -not (Has $r 'DL_LAYOUT_EVENTS')) $r.Out
  Check 'D4b an empty handler is reported' (Has $r 'tblOrdersQTY.OnValidate: not read: the handler is empty') $r.Out
  Check 'D4c too long for its column BLOCKED' (Has $r "ORDERS|NOTE DISPLAY_FORMAT:  -> a display format that is too long`n  BLOCKED: longer than DISPLAY_FORMAT(20)") $r.Out
  Check 'D5 disagreeing datasets: unchecked alternatives' ((Has $r "TOOLS|NAME DISPLAY_LABEL:  -> Tool name`n  (unchecked)") -and (Has $r "TOOLS|NAME DISPLAY_LABEL:  -> Other name`n  (unchecked)")) $r.Out
  # binary
  $bin = Join-Path $work 'bin'
  [IO.Directory]::CreateDirectory($bin) | Out-Null
  Get-ChildItem $fix -File | ForEach-Object { [IO.File]::Copy($_.FullName, (Join-Path $bin $_.Name)) }
  $conv = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\convert.exe'
  $null = & $conv -b -i (Join-Path $bin 'uOrders.dfm') 2>&1
  $first = [IO.File]::ReadAllBytes((Join-Path $bin 'uOrders.dfm'))[0]
  $rb = Dfm @() (Join-Path $bin 'uOrders.dfm')
  Check 'D6 a binary DFM gives the same output as its text form' (($first -in 0xFF, 0x54) -and ($rb.Code -eq 0) -and ($rb.Out -eq $r.Out)) "first byte $first`n$($rb.Out)"
  $rd = Dfm @('--dataset', 'TBLTOOLS')
  Check 'D7a --dataset reads one dataset' ((Has $rd 'total 1 datasets, 0 unresolved; 2 data') -and -not (Has $rd 'ORDERS|')) $rd.Out
  $rd = Dfm @('--dataset', 'nope')
  Check 'D7b an unknown dataset exits 1' (($rd.Code -eq 1) -and (Has $rd 'no dataset nope')) $rd.Out
  $sel = Join-Path $work 'sel.txt'
  [IO.File]::WriteAllText($sel, "999`n")
  $a = Run @('repo', 'read-dfm', '--repo', $x, '--dfm', $dfm, '--apply')
  $b = Run @('repo', 'read-dfm', '--repo', $x, '--dfm', $dfm, '--direction', 'repo-to-dfm', '--apply')
  $c = Run @('repo', 'read-dfm', '--repo', $x, '--direction', 'dfm-to-repo', '--apply')
  $d = Dfm @('--select', $sel)
  $e = Dfm @('--apply', '--dry-run')
  Check 'D8 usage errors exit 2, --dry-run wins, nothing written' ((($a.Code, $b.Code, $c.Code, $d.Code, $e.Code) -join ',') -eq '2,2,2,2,0' -and (Has $d 'unknown change id 999') -and ($h0 -eq (Get-FileHash -LiteralPath $x).Hash)) (($a.Code, $b.Code, $c.Code, $d.Code, $e.Code) -join ',')
  $r = Dfm @('--apply')
  Check 'D9a --apply writes the 15 checked changes, one log line each' (($r.Code -eq 0) -and (Has $r 'applied: 15 changes') -and ([regex]::Matches($r.Out, '(?m)^replacing ').Count -eq 15)) $r.Out
  $k = Run @('repo', 'check', '--repo', $x)
  Check 'D9b repo check: kinds and macros consistent (only the blocked lookup is incomplete)' ((-not (Has $k 'kind-flag-mismatch')) -and (-not (Has $k 'calc-')) -and (-not (Has $k 'layout-event')) -and (Has $k 'lookup-incomplete ORDERS.GONE')) $k.Out
  $r2 = Dfm @()
  Check 'D9c a second read: nothing checked is left' ((Has $r2 'direction dfm-to-repo, 6 changes, 4 blocked, 2 unchecked')) $r2.Out
  # select
  $ids = [regex]::Matches($r2.Out, '(?m)^\[(\d+)\] update DL_FIELDS_INFO TOOLS\|NAME DISPLAY_LABEL') | ForEach-Object { $_.Groups[1].Value }
  [IO.File]::WriteAllText($sel, ($ids -join "`n"))
  $s1 = Dfm @('--select', $sel)
  [IO.File]::WriteAllText($sel, $ids[1])
  $s2 = Dfm @('--select', $sel)
  Check 'D10a both alternatives refused, one applied' (($s1.Code -eq 1) -and (Has $s1 'set the same value') -and ($s2.Code -eq 0) -and (Has $s2 'applied: 1 changes')) "$($s1.Out)`n$($s2.Out)"
  $y = NewRepo 'y.dlrepo'
  $upd = [regex]::Match((Dfm @() $dfm $y).Out, '(?m)^\[(\d+)\] update DL_FIELDS_INFO TOOLS\|NAME DISPLAY_LABEL').Groups[1].Value
  [IO.File]::WriteAllText($sel, $upd)
  $s3 = Dfm @('--select', $sel) $dfm $y
  Check 'D10b an update without its row is refused, nothing written' (($s3.Code -eq 1) -and (Has $s3 'does not exist (select its insert too)') -and ((Run @('repo', 'info', '--json', '--repo', $y)).Out -match '"DL_FIELDS_INFO":0')) $s3.Out
  # schema facts
  $z = NewRepo 'z.dlrepo'
  $ddl = Join-Path $work 's.sql'
  [IO.File]::WriteAllText($ddl, "CREATE TABLE ORDERS (ID INTEGER NOT NULL, QTY INTEGER, TOTAL DOUBLE PRECISION, CONSTRAINT PK_O PRIMARY KEY (ID));`nCREATE TABLE TOOLS (TOOLNO INTEGER NOT NULL, ID INTEGER, NAME VARCHAR(20), CONSTRAINT PK_T PRIMARY KEY (TOOLNO));`n")
  $null = Run @('repo', 'seed-fb', '--ddl', $ddl, '--repo', $z, '--apply')
  $r = Dfm @() $dfm $z
  Check 'D11a a real column is not turned into a calc field' (Has $r "ORDERS|TOTAL FIELD_KIND: 1 -> 2`n  BLOCKED: TOTAL is a real column of ORDERS") $r.Out
  Check 'D11a2 its body is not a checked change' ($r.Out -match 'ORDERS\|TOTAL CALC_BODY: [^\n]*\n  \(unchecked\)') $r.Out
  Check 'D11b a data field the schema does not have is blocked' ($r.Out -match "insert DL_FIELDS_INFO ORDERS\|PRICE: [^\n]*\n  BLOCKED: not a column of ORDERS in the repository schema facts") $r.Out
  Check 'D11c the DFM wins on a hand-kept value, schema columns are not touched' ((Has $r 'update DL_FIELDS_INFO ORDERS|QTY DISPLAY_FORMAT:  -> #,##0') -and ($r.Out -notmatch '\] update [^\n]* (FIELD_AS_TYPE|VAR_TYPE|STRING_SIZE)')) $r.Out
  Check 'D11d a lookup key that is not the primary key is a warning' (Has $r 'lookup key ID is not the primary key of TOOLS (TOOLNO)') $r.Out
  # a second folder, odd DFM text
  $fix2 = Join-Path $work 'forms2'
  [IO.Directory]::CreateDirectory($fix2) | Out-Null
  [IO.File]::WriteAllText((Join-Path $fix2 'uOther2.dfm'), "object dmOther: TdmOther`r`n  object tblReason: TTable`r`n    TableName = 'Reasons2.db'`r`n  end`r`nend`r`n")
  [IO.File]::WriteAllBytes((Join-Path $fix2 'uJunk.dfm'), [byte[]](0xFF, 0x0A, 0x00, 0x41, 0x42))
  [IO.File]::WriteAllBytes((Join-Path $fix2 'uJunk2.dfm'), [byte[]](0x54, 0x50, 0x46, 0x30, 0x05, 0x54))
  [IO.File]::WriteAllText((Join-Path $fix2 'uTwo.dfm'), @'
object frmTwo: TfrmTwo
  object qryLong: TFDQuery
    SQL.Strings = (
      'SELECT T.ID, '#39'end'#39' AS MARK, T.CAPTION AS ' +
        'CAP'
      'FROM LONGTAB T -- end')
    object qryLongID: TIntegerField
      FieldName = 'ID'
    end
    object qryLongCAP: TStringField
      DisplayLabel = 'It'#39's' +
        ' "end"'
      FieldName = 'CAP'
      Size = 10
    end
    object qryLongCAP2: TStringField
      DisplayLabel = 'Other'
      FieldName = 'cap'
      Size = 10
    end
    object qryLongREASON: TStringField
      FieldKind = fkLookup
      FieldName = 'REASON'
      LookupDataSet = dmOther.tblReason
      LookupKeyFields = 'Code'
      LookupResultField = 'Text'
      KeyFields = 'ID'
      Lookup = True
    end
    object qryLongDEST: TStringField
      FieldKind = fkLookup
      FieldName = 'DESTNAME'
      LookupDataSet = qryDest
      LookupKeyFields = 'DNO'
      LookupResultField = 'FULLNAME'
      KeyFields = 'CAP'
      Lookup = True
    end
  end
  object qryDest: TFDQuery
    SQL.Strings = (
      'SELECT D.NO AS DNO, D.A || D.B AS FULLNAME FROM DEST D')
  end
  object tblNone: TTable
    TableName = 'NONE.DB'
  end
  inline Frame1: TFrame1
    inherited tblIn: TTable
      object tblInNEW: TIntegerField
        FieldName = 'NEWONE'
      end
    end
  end
end
'@.Replace("`r`n", "`n").Replace("`n", "`r`n"))
  $w = NewRepo 'w.dlrepo'
  $r = Dfm @() ($dfm + '; ' + (Join-Path $fix2 'uTwo.dfm')) $w
  Check 'D13a the data module of the second folder' (($r.Code -eq 0) -and ($r.Out -match 'LONGTAB\|REASON: [^\n]*DESTTABLE=REASONS2\n') -and ($r.Out -match 'ORDERS\|REASON: [^\n]*DESTTABLE=REASONS\n')) "exit=$($r.Code)`n$($r.Out)"
  Check 'D13b unreadable DFMs of the folder are warnings' (($r.Out -match 'warning: lookup datasets: [^\n]*uJunk\.dfm') -and ($r.Out -match 'warning: lookup datasets: [^\n]*uJunk2\.dfm')) $r.Out
  $rj = Dfm @() (Join-Path $fix2 'uJunk2.dfm') $w
  Check 'D13c an unreadable DFM asked for exits 1 with its name' (($rj.Code -eq 1) -and (Has $rj 'unreadable binary DFM')) $rj.Out
  Check 'D14a continued SQL and label' ((Has $r 'LONGTAB|CAPTION DISPLAY_LABEL:  -> It''s "end"') -and (Has $r 'qryLong (TFDQuery) -> LONGTAB: 3 data, 0 calc, 2 lookup')) $r.Out
  Check 'D14e lookup keys are columns, not the names the SQL gives them; a computed result is blocked' ((Has $r 'SOURCEKEY=CAPTION; DESTKEY=NO; DESTTABLE=DEST') -and (Has $r "LONGTAB|DESTNAME DESTVALUE:  -> FULLNAME`n  BLOCKED: FULLNAME is not a column of DEST (computed by the SQL)")) $r.Out
  Check 'D14b two components of one field: unchecked alternatives' (($r.Out -match 'LONGTAB\|CAPTION DISPLAY_LABEL:  -> Other\n  \(unchecked\)') -and ([regex]::Matches($r.Out, '(?m)^\[\d+\] insert DL_FIELDS_INFO LONGTAB\|CAPTION').Count -eq 1)) $r.Out
  Check 'D14c an inline dataset is reported, its new field gives no change' ((Has $r 'tblIn (TTable) -> UNRESOLVED (no TableName and no SQL in the DFM (inherited') -and -not (Has $r '|NEWONE')) $r.Out
  Check 'D14d a dataset without fields' (Has $r 'tblNone (TTable) -> NONE: 0 data') $r.Out
  # transaction + hand-kept columns
  [IO.File]::WriteAllText($sel, "1`n$upd")
  $hy = (Get-FileHash -LiteralPath $y).Hash
  $s4 = Dfm @('--select', $sel) $dfm $y
  Check 'D15a a failing change rolls the good one back' (($s4.Code -eq 1) -and ((Run @('repo', 'info', '--json', '--repo', $y)).Out -match '"DL_FIELDS_INFO":0')) "$hy $($s4.Out)"
  $s5 = Dfm @('--select', $sel, '--dry-run') $dfm $y
  Check 'D15b --select with --dry-run writes nothing' (($s5.Code -eq 0) -and (Has $s5 'dry run: nothing written')) $s5.Out
  $bk = Join-Path $work 'x.txt'
  $null = Run @('repo', 'backup', '--repo', $x, '--out', $bk)
  $bt = [IO.File]::ReadAllText($bk)
  $hand = $bt -replace '(\[DL_FIELDS_INFO ORDERS\|PRICE\]\r?\n(?:[^\[]*?\n)?DISPLAY_WIDTH=)0', '${1}77' -replace '(\[DL_FIELDS_INFO ORDERS\|QTY\][^\[]*?DISPLAY_FORMAT=)[^\r\n]*', '${1}HAND'
  Check 'D15c0 the fixture was edited' (($hand -ne $bt) -and $hand.Contains('HAND') -and $hand.Contains('=77'))
  [IO.File]::WriteAllText($bk, $hand)
  $v = Join-Path $work 'v.dlrepo'
  $null = Run @('repo', 'restore', '--repo', $v, '--in', $bk)
  $r = Dfm @('--apply') $dfm $v
  $null = Run @('repo', 'backup', '--repo', $v, '--out', (Join-Path $work 'v.txt'))
  $vt = [IO.File]::ReadAllText((Join-Path $work 'v.txt'))
  Check 'D15c a hand-kept column the DFM does not state survives apply' (($r.Code -eq 0) -and $vt.Contains('DISPLAY_WIDTH=77')) $r.Out
  Check 'D15d a hand-kept value the DFM contradicts is replaced and logged' ((Has $r 'replacing HAND with #,##0') -and (Has $r 'applied: 1 changes') -and -not $vt.Contains('HAND')) $r.Out
  # json
  $o = & $Exe repo read-dfm --repo $y --dfm $dfm --direction dfm-to-repo --json 2>$null
  $j = ($o -join "`n") | ConvertFrom-Json
  Check 'D12 --json: one object, same counts' (($j.totals.datasets -eq 6) -and ($j.totals.unresolved -eq 2) -and ($j.totals.fields.calc -eq 4) -and ($j.changeSet.count -eq 21) -and ($j.changeSet.blocked -eq 4) -and ($j.applied -eq 0) -and ($j.datasets.Count -eq 6)) ($o -join "`n")

  # ---- grid columns and event columns ----
  $g = Join-Path $fix 'uGrid.dfm'
  $q = NewRepo 'q.dlrepo'
  $r = Dfm @() $g $q
  Check 'D16a the four TField events' (Has $r 'ONGETTEXT_BODY=Text := Sender.AsString;; ONSETTEXT_BODY=Sender.AsString := Trim(Text);; ONVALIDATE_BODY=if Sender.AsInteger < 0 then\r\n  Abort;; ONCHANGE_BODY=') $r.Out
  Check 'D16b OnChange with the component itself' (Has $r 'ONCHANGE_BODY={{NOTE}}.AsString := ''q'' + DataSetOf(Sender, {{QTY}});') $r.Out
  Check 'D16c the DBTable column events, parameters renamed' ((Has $r 'GRID_DISPLAYTEXT_BODY=if {{QTY}}.IsNull then\r\n  AText := ''-'';') -and (Has $r 'GRID_DRAWCELL_BODY=ACanvas.Font.Color := clRed;')) $r.Out
  Check 'D16d a Clear branch' (Has $r 'CALC_BODY=if {{QTY}}.IsNull then\r\n  {{TOTAL}}.Clear\r\nelse\r\n  {{TOTAL}}.AsFloat := {{QTY}}.AsInteger * 2;') $r.Out
  Check 'D16e events of an unbound column and of a banded column are reported, not stored' ((Has $r 'uGrid.dfm colDraw.OnCustomDrawCell = colDrawCustomDrawCell: not stored (the column has no field)') -and (Has $r 'uGrid.dfm bandCode.OnCustomDrawCell = colDrawCustomDrawCell: not stored (a column event is stored for a TcxGridDBTableView only)')) $r.Out
  Check 'D16f an event of a column whose field has no row is reported, no row is made for it' ((Has $r 'ORDERS.GHOST GRID_DISPLAYTEXT_BODY: not stored: the repository has no row for the field (uGrid.dfm colGhost.OnGetDisplayText)') -and -not (Has $r 'DL_FIELDS_INFO ORDERS|GHOST')) $r.Out
  Check 'D17a order, a field bound twice, an unbound column' ((Has $r "] insert DL_GRID_COLUMNS frmGrid|view1|colTotal:  -> TABLE_NAME=ORDERS; FIELD_NAME=TOTAL; COLUMN_INDEX=0`n") -and (Has $r "] insert DL_GRID_COLUMNS frmGrid|view1|colQty:  -> TABLE_NAME=ORDERS; FIELD_NAME=QTY; COLUMN_INDEX=1`n") -and (Has $r "] insert DL_GRID_COLUMNS frmGrid|view1|colDraw:  -> COLUMN_INDEX=2`n") -and (Has $r "] insert DL_GRID_COLUMNS frmGrid|view1|colQty2:  -> TABLE_NAME=ORDERS; FIELD_NAME=QTY; COLUMN_INDEX=3`n")) $r.Out
  Check 'D17b banded view, data source of a data module' (Has $r "] insert DL_GRID_COLUMNS frmGrid|band1|bandCode:  -> TABLE_NAME=REASONS; FIELD_NAME=CODE; COLUMN_INDEX=0`n") $r.Out
  Check 'D17c a join: the column the SQL names, a computed one without table' ((Has $r "] insert DL_GRID_COLUMNS frmGrid|viewJ|jName:  -> TABLE_NAME=TOOLS; FIELD_NAME=NAME; COLUMN_INDEX=0`n") -and (Has $r "] insert DL_GRID_COLUMNS frmGrid|viewJ|jDbl:  -> FIELD_NAME=DBL; COLUMN_INDEX=1`n")) $r.Out
  Check 'D17d an unknown data source: stored without table, reported' ((Has $r "] insert DL_GRID_COLUMNS frmGrid|viewNone|nOne:  -> FIELD_NAME=ONE; COLUMN_INDEX=0`n") -and (Has $r 'uGrid.dfm viewNone: the dataset of its data source dsGone is not found: no table for its columns')) $r.Out
  Check 'D17e a card view and an inherited view are reported, not stored' ((Has $r 'uGrid.dfm card1 (TcxGridDBCardView): column order not read') -and (Has $r 'uGrid.dfm viewIn: inherited grid view not read (its own properties are in the ancestor''s DFM)') -and -not (Has $r '|card1|') -and -not (Has $r '|viewIn|')) $r.Out
  $rd = Dfm @('--dataset', 'qryJoin') $g $q
  Check 'D17f --dataset limits the views too' ((Has $rd '|viewJ|jName') -and -not (Has $rd '|view1|') -and -not (Has $rd '|viewNone|')) $rd.Out
  $r = Dfm @('--apply') $g $q
  $k = Run @('repo', 'check', '--repo', $q)
  Check 'D18a apply; check has no macro or cycle finding, and warns of grid columns without a field row' (($r.Code -eq 0) -and (Has $r 'applied: ') -and ($k.Out -cnotmatch 'calc-|event-|ERROR') -and (Has $k 'grid-column-unknown-field grid frmGrid.view1.colGhost')) "$($r.Out)`n$($k.Out)"
  $r = Dfm @() $g $q
  Check 'D18b a second read has no change' (Has $r 'direction dfm-to-repo, 0 changes, 0 blocked, 0 unchecked') $r.Out
  $gt = [IO.File]::ReadAllText($g)
  $blk = [regex]::Match($gt, '(?s)      object colTotal: .*?\r\n      end\r\n').Value
  $blkJ = [regex]::Match($gt, '(?s)      object jDbl: .*?\r\n      end\r\n').Value
  Check 'D18c0 the fixture blocks were found' (($blk.Length -gt 0) -and ($blkJ.Length -gt 0))
  [IO.File]::WriteAllText($g, $gt.Replace($blk, '').Replace('      object colDraw: ', $blk + '      object colDraw: ').Replace($blkJ, ''))
  $r = Dfm @() $g $q
  Check 'D18c two swapped columns: two updates of COLUMN_INDEX; a vanished column: an unchecked delete' ((Has $r 'direction dfm-to-repo, 3 changes, 0 blocked, 1 unchecked') -and (Has $r "] update DL_GRID_COLUMNS frmGrid|view1|colQty COLUMN_INDEX: 1 -> 0`n") -and (Has $r "] update DL_GRID_COLUMNS frmGrid|view1|colTotal COLUMN_INDEX: 0 -> 1`n") -and (Has $r "] delete DL_GRID_COLUMNS frmGrid|viewJ|jDbl: FIELD_NAME=DBL; COLUMN_INDEX=1 -> `n  (unchecked)")) $r.Out
  $r = Dfm @('--apply') $g $q
  $r2 = Dfm @() $g $q
  Check 'D18d apply leaves only the delete' (($r.Code -eq 0) -and (Has $r 'applied: 2 changes') -and (Has $r2 'direction dfm-to-repo, 1 changes, 0 blocked, 1 unchecked')) "$($r.Out)`n$($r2.Out)"
  [IO.File]::WriteAllText($sel, '1')
  $r = Dfm @('--select', $sel) $g $q
  Check 'D18e the delete by its id' (($r.Code -eq 0) -and (Has $r 'applied: 1 changes') -and (Has (Dfm @() $g $q) 'direction dfm-to-repo, 0 changes')) $r.Out
  $rd = Dfm @('--dataset', 'tblO') $g $q
  Check 'D18f --dataset proposes no delete for other views' (Has $rd 'direction dfm-to-repo, 0 changes') $rd.Out
  $v2 = Join-Path $work 'v2.dlrepo'
  $null = Run @('repo', 'restore', '--repo', $v2, '--in', (Join-Path $Repo 'tests\fixtures\fieldrepo\golden_v2.txt'))
  $r = Dfm @() $g $v2
  Check 'D19 a schema-2 repository: run repo migrate first (exit 1)' (($r.Code -eq 1) -and (Has $r 'the repository is schema 2: run repo migrate first')) $r.Out
  $null = Run @('repo', 'backup', '--repo', $x, '--output', (Join-Path $work 'x2.txt'))
  $xt = [IO.File]::ReadAllText((Join-Path $work 'x2.txt'))
  Check 'D20 ALIGNMENT: taCenter = 2, not stated = NULL' (([regex]::Matches($xt, '(?m)^ALIGNMENT=').Count -eq 1) -and ($xt -match '(?s)ORDERS\|QTY\][^\[]*ALIGNMENT=2')) $xt
}
finally {
  if ($env:DL_KEEP_WORKDIR -ne '1') { try { [IO.Directory]::Delete($work, $true) } catch { } }
}
if ($script:Failed) { Write-Host 'REPO READ-DFM: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'REPO READ-DFM: PASS' -ForegroundColor Green
exit 0
