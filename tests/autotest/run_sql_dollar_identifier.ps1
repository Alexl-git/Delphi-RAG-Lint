<#
  run_sql_dollar_identifier.ps1 -- symbol_facts.sql_reads / sql_writes cut a
  Firebird table name at '$' (FIB$ENUMVALUES -> FIB).

  THE DEFECT (docs\INBOX-sql-writes-dollar-identifier.md). Firebird allows
  A-Z 0-9 _ $ in an UNQUOTED identifier after the leading letter, and the
  FIBPlus metadata tables are all FIB$<NAME>. DRagLint.Doc.SymbolFacts'
  IsSqlIdentChar accepted letters/digits/underscore only, so ScanSqlIdent
  stopped at '$':
    * WRITES: 'UPDATE OR INSERT INTO FIB$ENUMVALUES ...' stored 'FIB' -- a
      table that does not exist (wrong fact).
    * READS: 'SELECT ... FROM FIB$ENUMVALUES WHERE ...' scanned 'FIB', then
      SelectFromIsSqlShaped's prose gate saw '$ENUMVALUES' after the table --
      neither a clause keyword nor punctuation -- and rejected the WHOLE
      assembled SELECT as English. sql_reads came out NULL. Same root cause,
      different symptom: this is the "PrepareLoadQuery has sql_reads NULL"
      half of the INBOX note, not a multi-Add assembly gap.
  Live: C:\Projects\DB\ORM3\SERVER\uFIB_ENUMVALUES_SERVER.PAS:100-128 (and the
  three sibling uFIB_*_SERVER units).

  CONTROLS (pass on the pre-fix engine): a plain multi-Add reader/writer with
  no '$', and a keyword glued to a '$' name ('XFROM' style) must not split.

  Run from a NEUTRAL CWD. pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}

$exePath = (Resolve-Path $Exe).Path
$work = Join-Path $env:TEMP ('draglint_sqldollar_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
$db = Join-Path $work 'sqldollar.sqlite'

$unit = @'
unit uSqlDollar;

interface

type
  TStrs = class
  public
    procedure Add(const S: string);
    procedure Clear;
  end;

  TQry = class
  public
    SQL: TStrs;
    CommandText: TStrs;
    procedure Prepare;
  end;

  TSvc = class
  public
    procedure PrepareLoadQuery(QRYLoad: TQry);
    procedure PrepareSaveQuery(QRYSave: TQry);
    procedure SingleLineDollar(Q: TQry);
    procedure DeleteDollar(Q: TQry);
    procedure UpdateDollar(Q: TQry);
    procedure JoinDollar(Q: TQry);
    procedure PlainControl(Q: TQry);
    procedure GluedKeyword(Q: TQry);
  end;

implementation

procedure TStrs.Add(const S: string);
begin
end;

procedure TStrs.Clear;
begin
end;

procedure TQry.Prepare;
begin
end;

procedure TSvc.PrepareLoadQuery(QRYLoad: TQry);
begin
  QRYLoad.SQL.Clear;
  {$REGION 'DB-RAD 8A'}
  QRYLoad.SQL.Add('SELECT ');
  QRYLoad.SQL.Add('  DOCUMENTATION AS DOCUMENTATION,  ENUMTYPE AS ENUMTYPE,  NAME AS NAME');
  QRYLoad.SQL.Add('FROM FIB$ENUMVALUES');
  QRYLoad.SQL.Add('  WHERE ( (ENUMTYPE = :ENUMTYPE)  AND  (EORDER = :EORDER)  )');
  QRYLoad.Prepare;
  {$ENDREGION 'DB-RAD 8A'}
end;

procedure TSvc.PrepareSaveQuery(QRYSave: TQry);
begin
  QRYSave.CommandText.Clear;
  {$REGION 'DB-RAD 9A'}
  QRYSave.CommandText.Add('UPDATE OR INSERT INTO FIB$ENUMVALUES'                       );
  QRYSave.CommandText.Add('  (DOCUMENTATION, ENUMTYPE, EORDER, ESTRING, EVALUE, NAME)' );
  QRYSave.CommandText.Add('  VALUES (:DOCUMENTATION, :ENUMTYPE, :EORDER, :ESTRING, :EVALUE, :NAME)');
  QRYSave.Prepare;
  {$ENDREGION 'DB-RAD 9A'}
end;

procedure TSvc.SingleLineDollar(Q: TQry);
begin
  Q.SQL.Add('SELECT * FROM RDB$RELATIONS r WHERE r.RDB$SYSTEM_FLAG = 0');
end;

procedure TSvc.DeleteDollar(Q: TQry);
begin
  Q.SQL.Add('DELETE FROM FIB$FIELDS_INFO WHERE ID = 1');
end;

procedure TSvc.UpdateDollar(Q: TQry);
begin
  Q.SQL.Add('UPDATE FIB$DATASETS_INFO SET X = 1');
end;

procedure TSvc.JoinDollar(Q: TQry);
begin
  Q.SQL.Add('SELECT a.ID FROM ORDERS a JOIN MON$ATTACHMENTS m ON m.ID = a.ID');
end;

procedure TSvc.PlainControl(Q: TQry);
begin
  Q.SQL.Add('SELECT ID');
  Q.SQL.Add('FROM PLAINTAB');
end;

procedure TSvc.GluedKeyword(Q: TQry);
begin
  Q.SQL.Add('SELECT X$FROM FROM GLUETAB');
end;

end.
'@
$norm = $unit -replace "`r`n", "`n" -replace "`n", "`r`n"
[IO.File]::WriteAllText((Join-Path $work 'uSqlDollar.pas'), $norm, [Text.Encoding]::ASCII)

Push-Location $env:TEMP
try {
  & $exePath index $work --db $db 2>&1 | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

  # sql --json rows are POSITIONAL arrays: [0]=name, [1]=reads, [2]=writes.
  $q = "select s.name, coalesce(f.sql_reads,''), coalesce(f.sql_writes,'') from symbol_facts f join symbols s on s.id = f.symbol_id where s.kind in ('method','procedure','function')"
  $j = (& $exePath sql --db $db --query $q --json 2>$null) -join "`n" | ConvertFrom-Json
  $facts = @{}
  foreach ($row in $j.rows) { $facts[[string]$row[0]] = @{ reads = [string]$row[1]; writes = [string]$row[2] } }
  Check 'facts were read for the fixture routines' ($facts.ContainsKey('PlainControl')) "rows=$($facts.Count)"

  function Expect($name, $reads, $writes) {
    $f = $facts[$name]
    $r = if ($f) { $f.reads } else { '' }
    $w = if ($f) { $f.writes } else { '' }
    Check "$name sql_reads = '$reads'"  ($r -eq $reads)  "actual='$r'"
    Check "$name sql_writes = '$writes'" ($w -eq $writes) "actual='$w'"
  }

  Write-Host 'CONTROLS (pass on the pre-fix engine):' -ForegroundColor Cyan
  Expect 'PlainControl' 'PLAINTAB' ''

  Write-Host 'DEFECT -- $ inside an unquoted Firebird identifier:' -ForegroundColor Cyan
  Expect 'PrepareSaveQuery' ''                         'FIB$ENUMVALUES'
  Expect 'PrepareLoadQuery' 'FIB$ENUMVALUES'           ''
  Expect 'SingleLineDollar' 'RDB$RELATIONS'            ''
  Expect 'DeleteDollar'     ''                         'FIB$FIELDS_INFO'
  Expect 'UpdateDollar'     ''                         'FIB$DATASETS_INFO'
  Expect 'JoinDollar'       'MON$ATTACHMENTS, ORDERS'  ''

  Write-Host 'OVER-CAPTURE GUARD -- a keyword glued to $ is not a keyword:' -ForegroundColor Cyan
  Expect 'GluedKeyword' 'GLUETAB' ''
} finally { Pop-Location; Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
