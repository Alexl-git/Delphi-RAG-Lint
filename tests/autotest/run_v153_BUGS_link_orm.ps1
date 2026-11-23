<#
  run_v153_BUGS_link_orm.ps1 -- the contract of `link-orm` with several --db values (v153 lane BUGS, item 3).

  CONTRACT (docs\wiki\link-orm.md, unit header of DRagLint.Sql.OrmLinker): every --db is a SOURCE,
  in any order; ONE orm_links table is written, in the LAST --db, because delphi_db_index /
  sql_db_index are positions in that run's --db list. stdout names the DB written.

  The three indexes are built the same way, so their symbol ids start at 1 in each: class ids collide
  ACROSS the databases. Before the fix the field lists were keyed by the bare class id, so the fields
  of TOrders (second index) were also linked as fields of TCustomers (first index).

    L1  control: class links from BOTH project indexes are found, each with its own db index
    L2  rows land in the LAST --db only (the first two keep zero rows)
    L3  a field is linked only to the table of its own class (no cross-database pairing)
    L4  each field is linked once
    L5  stdout names the database that was written
    L6  control: the real field links are there
    L7  the LAST --db is the output whatever it holds (SQL index first)

  Usage: pwsh -File tests\autotest\run_v153_BUGS_link_orm.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$WorkDir = "$env:TEMP\draglint-v153-linkorm-$PID")
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
$ErrorActionPreference = 'Continue'
$script:Fail = 0; $script:Pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  [PASS] $Name" -ForegroundColor Green }
  else     { $script:Fail++; Write-Host "  [FAIL] $Name -- $Detail" -ForegroundColor Red }
}
function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Invoke-Dl([string[]]$Arguments) { (& { $ErrorActionPreference = 'Continue'; & $Exe @Arguments 2>&1 | ForEach-Object { "$_" } } | ForEach-Object { "$_" }) -join "`n" }
function Get-Rows([string]$Db, [string]$Sql) {
  $j = (& { $ErrorActionPreference = 'Continue'; & $Exe sql --query $Sql --db $Db --json 2>$null }) -join "`n" | ConvertFrom-Json | ForEach-Object { $_ }
  return , @($j.rows | ForEach-Object { $_ -join '|' })
}
function New-Indexes([string]$Dir) {
  New-Item -ItemType Directory -Path $Dir | Out-Null
  foreach ($n in 'a\uCustomers.pas', 'b\uOrders.pas', 'sql\schema.sql') {
    $null = Invoke-Dl @('index', "$WorkDir\src\$n", '--db', "$Dir\$($n.Split('\')[0]).sqlite")
  }
}
try {
  foreach ($n in 'a', 'b', 'sql') { New-Item -ItemType Directory -Path "$WorkDir\src\$n" -Force | Out-Null }
  Write-Ascii "$WorkDir\src\a\uCustomers.pas" "unit uCustomers;`ninterface`ntype`n  TCustomers = class`n  private`n    FName: string;`n  end;`nimplementation`nend.`n"
  Write-Ascii "$WorkDir\src\b\uOrders.pas" "unit uOrders;`ninterface`ntype`n  TOrders = class`n  private`n    FTotal: Integer;`n  end;`nimplementation`nend.`n"
  # CUSTOMERS also has a TOTAL column and ORDERS a NAME column: the bait for the cross-database pairing.
  Write-Ascii "$WorkDir\src\sql\schema.sql" "CREATE TABLE CUSTOMERS (`n  NAME VARCHAR(20),`n  TOTAL INTEGER`n);`n`nCREATE TABLE ORDERS (`n  NAME VARCHAR(20),`n  TOTAL INTEGER`n);`n"
  $d = "$WorkDir\db"
  New-Indexes $d
  $out = Invoke-Dl @('link-orm', '--db', "$d\a.sqlite", '--db', "$d\b.sqlite", '--db', "$d\sql.sqlite")
  Write-Host "  raw: $out"
  $cls = Get-Rows "$d\sql.sqlite" "select delphi_db_index, sql_db_index from orm_links where link_kind = 'class_to_table' order by 1"
  Check 'L1 control: one class link per project index, db indexes = --db positions' (($cls -join ';') -eq '0|2;1|2') ($cls -join ';')
  $na = (Get-Rows "$d\a.sqlite" 'select count(*) from orm_links')[0]
  $nb = (Get-Rows "$d\b.sqlite" 'select count(*) from orm_links')[0]
  Check 'L2 only the LAST --db holds rows' (($na -eq '0') -and ($nb -eq '0')) "a=$na b=$nb"
  $fld = Get-Rows "$d\sql.sqlite" "select o.delphi_db_index, t.name, c.name from orm_links o join symbols c on c.id = o.sql_symbol_id join symbols t on t.id = c.parent_id where o.link_kind = 'field_to_column' order by 1, 2, 3"
  Write-Host "  raw fields: $($fld -join ';')"
  $bad = @($fld | Where-Object { $_ -notin @('0|CUSTOMERS|NAME', '1|ORDERS|TOTAL') })
  Check 'L3 no field of one index is linked through a class of another' ($bad.Count -eq 0) ($bad -join ';')
  Check 'L4 each field is linked once' ($fld.Count -eq 2) "$($fld.Count) rows"
  Check 'L5 stdout names the database written' ($out -match 'written to .*sql\.sqlite') $out
  Check 'L6 control: both real field links present' (('0|CUSTOMERS|NAME' -in $fld) -and ('1|ORDERS|TOTAL' -in $fld)) ($fld -join ';')

  $d2 = "$WorkDir\db2"
  New-Indexes $d2
  $null = Invoke-Dl @('link-orm', '--db', "$d2\sql.sqlite", '--db', "$d2\a.sqlite")
  $ra = Get-Rows "$d2\a.sqlite" "select link_kind, delphi_db_index, sql_db_index from orm_links order by 1"
  $rs = (Get-Rows "$d2\sql.sqlite" 'select count(*) from orm_links')[0]
  Check 'L7 SQL index first: the project index (last) is the output' ((($ra -join ';') -eq 'class_to_table|1|0;field_to_column|1|0') -and ($rs -eq '0')) "a=$($ra -join ';') sql=$rs"
}
finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
Write-Host "run_v153_BUGS_link_orm: $script:Pass pass, $script:Fail fail"
exit $(if ($script:Fail) { 1 } else { 0 })
