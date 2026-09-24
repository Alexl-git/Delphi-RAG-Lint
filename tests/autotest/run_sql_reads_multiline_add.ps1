<#
  run_sql_reads_multiline_add.ps1 -- D18: symbol_facts.sql_reads misses SQL
  assembled across several `Q.SQL.Add(...)` statements.

  THE DEFECT. DRagLint.Doc.SymbolFacts.WalkSqlLiterals classifies every
  string-literal RUN on its own. The FireDAC/DB-RAD pattern that dominates the
  ORM3 SERVER (938 `.SQL.Add(` / `.CommandText.Add(` calls in 134 units) puts
  one clause per statement:

      QRYLoad.SQL.Add('SELECT ');
      QRYLoad.SQL.Add('  ID AS ID, REASON AS REASON');
      QRYLoad.SQL.Add('FROM CAUSFAIL');

  'SELECT ' alone has no FROM, so the prose gate rejects it; 'FROM CAUSFAIL'
  does not start with a verb, so it is never considered. The reader is lost.
  Writers mostly survive only because 'UPDATE OR INSERT INTO T' carries its
  table on the FIRST line. Measured on the SERVER index (1.18.0-alpha):
  19 routines with sql_reads vs 148 with sql_writes.

  THE FIX. Consecutive `<recv>.Add(<literal run>)` statements of ONE
  statement list are concatenated per receiver (recv = a dataset's SQL-text
  property: SQL, CommandText, SelectSQL, InsertSQL, ModifySQL, DeleteSQL,
  RefreshSQL) in statement order, and the assembled text goes through the
  SAME ClassifySqlText + ExtractSqlTables pipeline. Any other statement ends
  every open run (Clear, Open, ExecSQL, an if ...); a compiler directive or
  comment between two Adds does not. A non-literal Add argument poisons its
  receiver's run (absence over a wrong fact).

  CONTROLS. `SingleLine` and `WriterFirstLine` must PASS on the pre-fix
  engine: they prove the query path and the per-literal extractor work, so a
  FAIL elsewhere is about the multi-statement assembly, not the harness.
  `DynamicMiddle`, `BrokenByExec` and `MemoLines` are over-capture guards.

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
$work = Join-Path $env:TEMP ('draglint_sqlreads_multiadd_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
$db = Join-Path $work 'sqladd.sqlite'

$unit = @'
unit uSqlAdd;

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
    procedure Open;
    procedure ExecSQL;
  end;

  TMemo = class
  public
    Lines: TStrs;
  end;

  TRunner = class
  private
    FTable: string;
  public
    procedure LoadMulti(Q: TQry);
    procedure JoinMulti(C: TQry);
    procedure WriterFirstLine(C: TQry);
    procedure SingleLine(Q: TQry);
    procedure Interleaved(A, B: TQry);
    procedure InTry(Q: TQry);
    procedure DynamicMiddle(Q: TQry);
    procedure BrokenByExec(Q: TQry);
    procedure MemoLines(M: TMemo);
  end;

implementation

procedure TStrs.Add(const S: string);
begin
end;

procedure TStrs.Clear;
begin
end;

procedure TQry.Open;
begin
end;

procedure TQry.ExecSQL;
begin
end;

procedure TRunner.LoadMulti(Q: TQry);
begin
  Q.SQL.Clear;
  {$REGION 'DB-RAD 8A'}
  Q.SQL.Add('SELECT '                          );
  Q.SQL.Add('  ID AS ID,  REASON AS REASON'     );
  Q.SQL.Add('FROM CAUSFAIL'                    );
  Q.SQL.Add('  WHERE ( (ID = :ID)  )'          );
  {$ENDREGION 'DB-RAD 8A'}
  Q.Open;
end;

procedure TRunner.JoinMulti(C: TQry);
begin
  C.CommandText.Add('SELECT o.ID, l.QTY');
  // a comment between two lines keeps the run open
  C.CommandText.Add('FROM ORDERS o');
  C.CommandText.Add('JOIN ORDLINES l ON l.ORD_ID = o.ID');
end;

procedure TRunner.WriterFirstLine(C: TQry);
begin
  C.CommandText.Add('UPDATE OR INSERT INTO CAUSLOG');
  C.CommandText.Add('  (ID, MSG)');
  C.CommandText.Add('  VALUES (:ID, :MSG)');
end;

procedure TRunner.SingleLine(Q: TQry);
begin
  Q.SQL.Add('SELECT * FROM SINGLETAB WHERE ID = 1');
end;

procedure TRunner.Interleaved(A, B: TQry);
begin
  A.SQL.Add('SELECT *');
  B.SQL.Add('SELECT *');
  A.SQL.Add('FROM LEFTTAB');
  B.SQL.Add('FROM RIGHTTAB');
end;

procedure TRunner.InTry(Q: TQry);
begin
  try
    Q.SQL.Add('SELECT X');
    Q.SQL.Add('FROM TRYTAB');
    Q.Open;
  finally
  end;
end;

procedure TRunner.DynamicMiddle(Q: TQry);
begin
  Q.SQL.Add('SELECT *');
  Q.SQL.Add('FROM ' + FTable);
  Q.SQL.Add('WHERE ID = 1');
end;

procedure TRunner.BrokenByExec(Q: TQry);
begin
  Q.SQL.Add('DELETE FROM TMPROWS');
  Q.ExecSQL;
  Q.SQL.Clear;
  Q.SQL.Add('SELECT *');
  Q.SQL.Add('FROM REALREAD');
  Q.Open;
end;

procedure TRunner.MemoLines(M: TMemo);
begin
  M.Lines.Add('Select a report');
  M.Lines.Add('from MEMOTAB listing');
end;

end.
'@
$norm = $unit -replace "`r`n", "`n" -replace "`n", "`r`n"
[IO.File]::WriteAllText((Join-Path $work 'uSqlAdd.pas'), $norm, [Text.Encoding]::ASCII)

Push-Location $env:TEMP
try {
  & $exePath index $work --db $db 2>&1 | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

  $q = "select s.name, coalesce(f.sql_reads,''), coalesce(f.sql_writes,'') from symbol_facts f join symbols s on s.id = f.symbol_id where s.kind in ('method','procedure','function')"
  $j = (& $exePath sql --db $db --query $q --json 2>$null) -join "`n" | ConvertFrom-Json
  $facts = @{}
  foreach ($row in $j.rows) { $facts[[string]$row[0]] = @{ reads = [string]$row[1]; writes = [string]$row[2] } }
  # A routine with no fact of any kind may have no symbol_facts row; that reads as ''/''.
  Check 'facts were read for the fixture routines' ($facts.ContainsKey('SingleLine')) "rows=$($facts.Count)"

  function Expect($name, $reads, $writes) {
    $f = $facts[$name]
    $r = if ($f) { $f.reads } else { '' }
    $w = if ($f) { $f.writes } else { '' }
    Check "$name sql_reads = '$reads'"  ($r -eq $reads)  "actual='$r'"
    Check "$name sql_writes = '$writes'" ($w -eq $writes) "actual='$w'"
  }

  Write-Host 'CONTROLS (pass on the pre-fix engine):' -ForegroundColor Cyan
  Expect 'SingleLine'      'SINGLETAB' ''
  Expect 'WriterFirstLine' ''          'CAUSLOG'

  Write-Host 'D18 -- multi-statement SQL.Add assembly:' -ForegroundColor Cyan
  Expect 'LoadMulti'   'CAUSFAIL'          ''
  Expect 'JoinMulti'   'ORDERS, ORDLINES'  ''
  Expect 'Interleaved' 'LEFTTAB, RIGHTTAB' ''
  Expect 'InTry'       'TRYTAB'            ''

  Write-Host 'OVER-CAPTURE GUARDS:' -ForegroundColor Cyan
  Expect 'DynamicMiddle' ''         ''
  Expect 'BrokenByExec'  'REALREAD' 'TMPROWS'
  Expect 'MemoLines'     ''         ''
} finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
