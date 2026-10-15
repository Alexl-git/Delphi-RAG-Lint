<#
  run_sql_quoted_identifier.ps1 -- symbol_facts.sql_reads / sql_writes record
  NOTHING for a double-quoted Firebird identifier.

  THE DEFECT. DRagLint.Doc.SymbolFacts scans an UPPER-CASED copy of the SQL,
  and ScanSqlIdent required a letter/underscore first, so '"Mixed Case"'
  scanned as '' (absence): no read, no write. Worse, for a SELECT the prose
  gate (SelectFromIsSqlShaped) then saw '"' after FROM -- not a clause
  boundary -- and rejected the WHOLE statement as English. Firebird quoted
  identifiers are case-sensitive, so the fix records them VERBATIM, quotes
  stripped, '""' unescaped to '"', case preserved.

  CONTROLS (pass on the pre-fix engine): a plain unquoted reader, a '$'
  identifier, and a single-quoted string literal containing a '"' must not
  change. The '$' suite (run_sql_dollar_identifier.ps1) is the wider control.

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
$work = Join-Path $env:TEMP ('draglint_sqlquoted_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
$db = Join-Path $work 'sqlquoted.sqlite'

$unit = @'
unit uSqlQuoted;

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
    procedure Prepare;
  end;

  TSvc = class
  public
    procedure SelectMixed(Q: TQry);
    procedure InsertQuoted(Q: TQry);
    procedure UpdateQuoted(Q: TQry);
    procedure DeleteQuoted(Q: TQry);
    procedure UpsertQuotedDollar(Q: TQry);
    procedure MultiAddQuoted(Q: TQry);
    procedure EscapedQuote(Q: TQry);
    procedure PlainControl(Q: TQry);
    procedure DollarControl(Q: TQry);
    procedure LiteralWithQuote(Q: TQry);
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

procedure TSvc.SelectMixed(Q: TQry);
begin
  Q.SQL.Add('SELECT ID FROM "Mixed Case" WHERE ID = 1');
end;

procedure TSvc.InsertQuoted(Q: TQry);
begin
  Q.SQL.Add('INSERT INTO "T" (A) VALUES (1)');
end;

procedure TSvc.UpdateQuoted(Q: TQry);
begin
  Q.SQL.Add('UPDATE "UpdT" SET A = 1');
end;

procedure TSvc.DeleteQuoted(Q: TQry);
begin
  Q.SQL.Add('DELETE FROM "delT" WHERE A = 1');
end;

procedure TSvc.UpsertQuotedDollar(Q: TQry);
begin
  Q.SQL.Add('UPDATE OR INSERT INTO "FIB$X" (A) VALUES (1)');
end;

procedure TSvc.MultiAddQuoted(Q: TQry);
begin
  Q.SQL.Clear;
  Q.SQL.Add('SELECT a.ID');
  Q.SQL.Add('FROM "Order Lines" a');
  Q.SQL.Add('  WHERE a.ID = :ID');
  Q.Prepare;
end;

procedure TSvc.EscapedQuote(Q: TQry);
begin
  Q.SQL.Add('SELECT * FROM "He said ""hi""" WHERE 1 = 1');
end;

procedure TSvc.PlainControl(Q: TQry);
begin
  Q.SQL.Add('SELECT ID');
  Q.SQL.Add('FROM plaintab');
end;

procedure TSvc.DollarControl(Q: TQry);
begin
  Q.SQL.Add('DELETE FROM FIB$FIELDS_INFO WHERE ID = 1');
end;

procedure TSvc.LiteralWithQuote(Q: TQry);
begin
  Q.SQL.Add('SELECT ID FROM litq WHERE NOTE = ''say "x"''');
end;

end.
'@
$norm = $unit -replace "`r`n", "`n" -replace "`n", "`r`n"
[IO.File]::WriteAllText((Join-Path $work 'uSqlQuoted.pas'), $norm, [Text.Encoding]::ASCII)

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
    # -ceq: a quoted identifier is case-sensitive, so the comparison must be too.
    Check "$name sql_reads = '$reads'"  ($r -ceq $reads)  "actual='$r'"
    Check "$name sql_writes = '$writes'" ($w -ceq $writes) "actual='$w'"
  }

  Write-Host 'CONTROLS (pass on the pre-fix engine):' -ForegroundColor Cyan
  Expect 'PlainControl'     'PLAINTAB' ''
  Expect 'DollarControl'    ''         'FIB$FIELDS_INFO'
  Expect 'LiteralWithQuote' 'LITQ'     ''

  Write-Host 'DEFECT -- a double-quoted identifier is recorded verbatim, case preserved:' -ForegroundColor Cyan
  Expect 'SelectMixed'        'Mixed Case'   ''
  Expect 'InsertQuoted'       ''             'T'
  Expect 'UpdateQuoted'       ''             'UpdT'
  Expect 'DeleteQuoted'       ''             'delT'
  Expect 'UpsertQuotedDollar' ''             'FIB$X'
  Expect 'MultiAddQuoted'     'Order Lines'  ''
  Expect 'EscapedQuote'       'He said "hi"' ''
} finally { Pop-Location; Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
