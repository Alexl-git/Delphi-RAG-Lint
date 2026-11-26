#Requires -Version 7.3
<#
  run_v1541_ORIGIN.ps1 -- 1.54.1 lane ORIGIN: `repo read-dfm` gives every field of a JOIN dataset its own table
  (design docs\superpowers\specs\2026-11-26-join-field-origin-design.md; survey step 1).

  Fixture tests\fixtures\fieldrepo\origin\uJoin.dfm / .pas, read with an empty repository and with schema facts:
    O1  data fields: alias, table name, quoted table qualifier; Origin "X.DB".COL, ALIAS."X.DB".COL, unquoted X.DB.COL
    O2  select list and Origin disagree = a conflict, reported, not picked (join and single table)
    O3  calc field whose code reads one table: read into that table, column macros
    O4  calc over two tables: unresolved with both tables
    O5  calc that reads another calc field: the fixpoint gives the table
    O6  calc with no code / no field read / a computed column / a cycle: unresolved with the reason
    O7  lookup: the table of its key field; key fields in two tables unresolved
    O8  star and unqualified columns: unresolved without schema facts; resolved, or ambiguous, with them
    O9  event code that reads a field of another table is BLOCKED; same table stored with macros
    O10 the JOIN dataset line, the joins summary line, --json
    O11 the old uOrders.dfm qryJoin is a join now, not unresolved
  Run: pwsh -File tests\autotest\run_v1541_ORIGIN.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '')
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$ErrorActionPreference = 'Continue'
$script:Failed = $false
$script:Pass = 0
$script:Fail = 0
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $(if ($ok) { '' } else { $d })) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if ($ok) { $script:Pass++ } else { $script:Fail++; $script:Failed = $true }
}
Write-Host '== repo read-dfm: join field origin ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-origin-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
function Run([string[]]$a) {
  $o = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } }
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
function Dfm([string]$dfm, [string]$r, [string[]]$more = @()) { Run (@('repo', 'read-dfm', '--repo', $r, '--dfm', $dfm, '--direction', 'dfm-to-repo') + $more) }
function NewRepo($name) { $p = Join-Path $work $name; $null = Run @('repo', 'init', '--repo', $p); $p }
function Has($r, $text) { $r.Out.Contains($text) }
function Ins($r, $key) { $r.Out -match ('(?m)^\[\d+\] insert DL_FIELDS_INFO ' + [regex]::Escape($key) + ':') }
try {
  $fix = Join-Path $work 'forms'
  [IO.Directory]::CreateDirectory($fix) | Out-Null
  Get-ChildItem (Join-Path $Repo 'tests\fixtures\fieldrepo\origin') -File | ForEach-Object { [IO.File]::Copy($_.FullName, (Join-Path $fix $_.Name)) }
  $dfm = Join-Path $fix 'uJoin.dfm'
  $x = NewRepo 'x.dlrepo'
  $r = Dfm $dfm $x

  # O1 data fields
  Check 'O1a alias and table qualifier' ((Ins $r 'ORDERS|ID') -and (Ins $r 'ORDERS|QTY') -and (Ins $r 'TOOLS|NAME') -and (Ins $r 'ORDERS|TOOLID')) $r.Out
  Check 'O1b quoted table name as qualifier ("Tools.DB".Price)' (Ins $r 'TOOLS|PRICE') $r.Out
  Check 'O1c Origin "X.DB".COL, ALIAS."X.DB".COL, X.DB.COL under a star: only Code, ID, Part lack a table' ($r.Out -match 'qryStar \(TQuery\) -> [^\n]*\n  no table column: Code, ID, Part\n') $r.Out
  Check 'O1d unquoted Origin X.DB.COL' (Ins $r 'ORDERS|NOTE') $r.Out
  Check 'O1f a repeated column name gets the suffix _1 in list order' ($r.Out -match 'qryDup \(TQuery\) -> JOIN ORDERS TOOLS: 2 data[^\n]*\ndataset ') $r.Out
  Check 'O1e a computed item has no table' (Has $r 'no table: Dbl: computed by the SQL') $r.Out
  # O2 conflict
  Check 'O2a join: select list vs Origin = conflict' (Has $r 'no table: TNo: conflict: the select list says TOOLS.ID, Origin says ORDERS.ID') $r.Out
  Check 'O2b single table: the conflict is reported too' (($r.Out -match 'qryOne \(TQuery\) -> TOOLS: [^\n]*\n  no table column: Name') -and (Has $r 'qryOne Name: conflict: the select list says TOOLS.NAME, Origin says TOOLS.TITLE')) $r.Out
  # O3 / O5 calc of one table
  Check 'O3a calc of one table, column macro' (Has $r 'ORDERS|TOTAL:  -> FIELD_KIND=2; FIELD_AS_TYPE=AsFloat; VAR_TYPE=double; CALC_BODY={{TOTAL}}.AsFloat := {{QTY}}.AsInteger * 1.5;') $r.Out
  Check 'O3b calc of the other table' (($r.Out -match 'insert DL_FIELDS_INFO TOOLS\|LABEL: [^\n]*CALC_BODY=\{\{LABEL\}\}\.AsString := \{\{NAME\}\}\.AsString \+ \{\{PRICE\}\}\.AsString;')) $r.Out
  Check 'O5 calc over another calc field: fixpoint' ($r.Out -match 'insert DL_FIELDS_INFO ORDERS\|TWICE: [^\n]*CALC_BODY=\{\{TWICE\}\}\.AsFloat := \{\{TOTAL\}\}\.AsFloat \* 2;') $r.Out
  # O4 / O6
  Check 'O4 calc over two tables unresolved' (Has $r 'no table: Mixed: the calc code reads 2 tables: ORDERS TOOLS') $r.Out
  Check 'O6a calc reading a computed column' (Has $r 'no table: Comp: the calc code reads Dbl, which has no table') $r.Out
  Check 'O6b calc nobody assigns' (Has $r 'no table: NoCode: no calc code: qryJCalcFields does not assign it') $r.Out
  Check 'O6c calc reading no field' (Has $r 'no table: Const: the calc code reads no field of the dataset') $r.Out
  Check 'O6d a cycle of calc fields that reads no table field' ((Has $r 'no table: Loop1: the calc code reads no table field, only calc fields: Loop2') -and (Has $r 'no table: Loop2: the calc code reads no table field, only calc fields: Loop1')) $r.Out
  Check 'O6g the condition of an if whose branches assign another field is not read' (($r.Out -match 'insert DL_FIELDS_INFO ORDERS\|SLICE: ') -and ($r.Out -match 'insert DL_FIELDS_INFO TOOLS\|OTHER: ')) $r.Out
  Check 'O6f a cycle of calc fields over ONE table: that table (survey: cycle guard)' (($r.Out -match 'insert DL_FIELDS_INFO ORDERS\|CYC1: ') -and ($r.Out -match 'insert DL_FIELDS_INFO ORDERS\|CYC2: ')) $r.Out
  Check 'O6e nothing unresolved is written' (-not ($r.Out -match 'DL_FIELDS_INFO [A-Z]*\|(MIXED|COMP|NOCODE|CONST|LOOP1|LOOP2|DBL|TNO|BOTH)[ :]')) $r.Out
  # O7 lookup
  Check 'O7a lookup in the table of its key field' (($r.Out -match 'insert DL_FIELDS_INFO ORDERS\|TOOLTXT: [^\n]*FIELD_KIND=3') -and ($r.Out -match 'SOURCEKEY=TOOLID; DESTKEY=ID; DESTVALUE=NAME; DESTTABLE=TOOLS')) $r.Out
  Check 'O7b key fields in two tables' (Has $r 'no table: Both: the key fields come from 2 tables: ORDERS TOOLS') $r.Out
  # O8 star / unqualified without schema facts
  Check 'O8a unqualified column, no schema facts' (Has $r 'no table: Part: not qualified and the repository has no schema facts for ORDERS TOOLS') $r.Out
  Check 'O8b star column without Origin, no schema facts' (Has $r 'no table: ID: not qualified and the repository has no schema facts for ORDERS TOOLS') $r.Out
  Check 'O8c bare Origin, no schema facts' (Has $r 'no table: Code: not qualified and the repository has no schema facts for ORDERS TOOLS') $r.Out
  # O9 events
  Check 'O9a event code of the same table stored with macros' ($r.Out -match 'ORDERS\|QTY: [^\n]*ONGETTEXT_BODY=Text := \{\{ID\}\}\.AsString \+ Sender\.AsString;') $r.Out
  Check 'O9b event code reading another table BLOCKED' ($r.Out -match 'TOOLS\|NAME ONGETTEXT_BODY: [^\n]*\n  BLOCKED: the code reads fields of another table: OQ \(ORDERS\)') $r.Out
  # O10 report
  Check 'O10a JOIN dataset line' ((Has $r 'dataset uJoin.dfm qryJ (TFDQuery) -> JOIN ORDERS TOOLS: 8 data, 13 calc, 2 lookup, 0 internal-calc, 0 aggregate') -and (Has $r 'dataset uJoin.dfm qryStar (TQuery) -> JOIN ORDERS TOOLS: 6 data')) $r.Out
  Check 'O10b a join is not unresolved' (Has $r 'total 5 datasets, 0 unresolved;') $r.Out
  Check 'O10c joins summary line' (Has $r 'joins: 3 datasets; 7 calc, 1 lookup, 10 data fields with a table; 13 without') $r.Out
  $j = Dfm $dfm $x @('--json')
  $o = $null
  try { $o = $j.Out.Substring($j.Out.IndexOf('{')) | ConvertFrom-Json } catch { }
  $jd = if ($o) { @($o.datasets | Where-Object { $_.dataset -eq 'qryJ' })[0] } else { $null }
  Check 'O10d --json: join tables, noTable reasons, totals' (($null -ne $jd) -and (($jd.join -join ' ') -eq 'ORDERS TOOLS') -and (@($jd.noTable | Where-Object { $_.field -eq 'Mixed' -and $_.why -like 'the calc code reads 2 tables*' }).Count -eq 1) -and ($o.totals.joins.datasets -eq 3) -and ($o.totals.joins.calc -eq 7) -and ($o.totals.joins.without -eq 13)) $j.Out
  # O8 with schema facts
  $z = NewRepo 'z.dlrepo'
  $ddl = Join-Path $work 's.sql'
  [IO.File]::WriteAllText($ddl, "CREATE TABLE ORDERS (ID INTEGER NOT NULL, QTY INTEGER, NOTE VARCHAR(80), PART VARCHAR(10), TOOLID INTEGER, CONSTRAINT PK_O PRIMARY KEY (ID));`nCREATE TABLE TOOLS (ID INTEGER NOT NULL, NAME VARCHAR(20), CODE VARCHAR(10), PRICE DOUBLE PRECISION, TITLE VARCHAR(20), CONSTRAINT PK_T PRIMARY KEY (ID));`n")
  $null = Run @('repo', 'seed-fb', '--ddl', $ddl, '--repo', $z, '--apply')
  $s = Dfm $dfm $z
  Check 'O8d unqualified column: the one FROM table that has it' ((-not (Has $s 'no table: Part:')) -and (Has $s "qryJ (TFDQuery) -> JOIN ORDERS TOOLS: 8 data, 13 calc, 2 lookup, 0 internal-calc, 0 aggregate`n  no table column: Dbl, TNo, Mixed,")) $s.Out
  Check 'O8e bare Origin and a star column: the one table that has it' ((-not (Has $s 'no table: Code:')) -and ($s.Out -match 'qryStar \(TQuery\) -> [^\n]*\n  no table column: ID\n')) $s.Out
  Check 'O8f a star column in two tables without Origin: ambiguous, not picked' (Has $s 'no table: ID: ID is in 2 tables of the FROM: ORDERS TOOLS') $s.Out
  # O11 the old fixture
  $old = Join-Path $work 'old'
  [IO.Directory]::CreateDirectory($old) | Out-Null
  Get-ChildItem (Join-Path $Repo 'tests\fixtures\fieldrepo\dfmread') -File | ForEach-Object { [IO.File]::Copy($_.FullName, (Join-Path $old $_.Name)) }
  $u = Dfm (Join-Path $old 'uOrders.dfm') (NewRepo 'u.dlrepo')
  Check 'O11 uOrders qryJoin is a JOIN; its calc field without code is reported' ((Has $u 'qryJoin (TQuery) -> JOIN ORDERS TOOLS: 1 data, 1 calc') -and (Has $u 'no table: Calc: no calc code: the dataset has no OnCalcFields') -and (Has $u 'total 6 datasets, 1 unresolved;')) $u.Out
  Check 'O12 dry run: exit 0' (($r.Code -eq 0) -and ($s.Code -eq 0) -and ($u.Code -eq 0)) "$($r.Code) $($s.Code) $($u.Code)"
}
finally {
  try { [IO.Directory]::Delete($work, $true) } catch { }
}
Write-Host ("Summary: pass={0} fail={1}" -f $script:Pass, $script:Fail)
if ($script:Failed) { exit 1 } else { exit 0 }
