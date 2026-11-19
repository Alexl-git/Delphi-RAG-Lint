program CsvMemTableTests;

{$APPTYPE CONSOLE}

{ Lane TTCSV golden + negative tests for DRagLint.FieldRepo.CsvMemTable.
  Usage: CsvMemTableTests <fixture dir>   (exit code = number of failures) }

uses
  System.SysUtils,
  System.Classes,
  DRagLint.FieldRepo.CsvMemTable in '..\..\src\sql\DRagLint.FieldRepo.CsvMemTable.pas';

var
  gFail: Integer = 0;
  gDir: string;

procedure Check(pOk: Boolean; const pWhat: string);
begin
  if pOk then
    Writeln('PASS ', pWhat)
  else
  begin
    Writeln('FAIL ', pWhat);
    Inc(gFail);
  end;
end;

function Raises(const pCsv, pName: string): Boolean;
begin
  Result := False;
  try
    GenMemTableFromCsv(pCsv, pName);
  except
    on ECsvMemTableError do
      Result := True;
  end;
end;

function Slurp(const pFile: string): string;
var
  lList: TStringList;
begin
  lList := TStringList.Create;
  try
    lList.LoadFromFile(pFile);
    Result := lList.Text;
  finally
    lList.Free;
  end;
end;

var
  lOut, lGolden: string;
begin
  gDir := IncludeTrailingPathDelimiter(ParamStr(1));
  lGolden := Slurp(gDir + 'golden.pas.txt');
  lOut := GenMemTableFromCsvFile(gDir + 'sample.csv', 'Sample');
  Check(lOut = lGolden, 'golden: sample.csv equals stored wizard-equivalent output');
  Check(Pos('ftInteger', lOut) > 0, 'positive control: output contains ftInteger');
  Check(Pos('fkCalculated', lOut) > 0, 'positive control: calculated kind emitted');
  Check(Pos('FieldName', lOut) = 0, 'header row is not emitted as a field');
  Check(Raises('A,Bogus,,Data', 'X'), 'unknown field type raises');
  Check(not Raises('A,String,10,Data', 'X'), 'positive control: valid type does not raise');
  Check(Raises('A,String,10,Data', '1bad'), 'bad routine name raises');
  Check(Pos('Size', GenMemTableFromCsv('A,Integer,,Data', 'X')) = 0, 'empty size emits no Size line');
  Check(Pos('Size', GenMemTableFromCsv('A,String,7,Data', 'X')) > 0, 'positive control: size 7 emits Size');
  Check(Pos('''Z''', GenMemTableFromCsv('Z,Integer', 'X')) = 0, 'row with fewer than 4 columns skipped');
  Check(Pos('FindComponent(''Dict'')', GenMemTableFromCsv('L,Integer,,Lookup,Dict,K,LK,R', 'X')) > 0, 'lookup row emits dataset');
  ExitCode := gFail;
end.
