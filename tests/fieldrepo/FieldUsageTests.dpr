program FieldUsageTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.56 lane UI-M -- console tests for DRagLint.FieldRepo.FieldUsage over a hand-built project index DB (the
  tables files / dfm_objects / dfm_properties as the indexer writes them). Output: PASS / FAIL lines, then
  "SUMMARY pass=N fail=M"; exit code 0 only when fail=0. }

uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Stan.ExprFuncs,
  FireDAC.ConsoleUI.Wait,
  FireDAC.Stan.Param,
  FireDAC.DatS,
  FireDAC.DApt.Intf,
  FireDAC.DApt,
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.FieldUsage in '..\..\src\sql\DRagLint.FieldRepo.FieldUsage.pas';

var
  GPass: Integer = 0;
  GFail: Integer = 0;
  GSeq: Integer = 0;
  GDir: string;

procedure Check(const pName: string; pCond: Boolean; const pDetail: string = '');
begin
  if pCond then
  begin
    Inc(GPass);
    Writeln('PASS ', pName);
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL ', pName, ' ', pDetail);
  end;
end;

{ Project DB with the files table and, when asked, the two DFM tables (an index older than schema 25 has none). }
function NewProjectDb(pWithDfmTables: Boolean): TFDConnection;
begin
  Inc(GSeq);
  Result := TFDConnection.Create(nil);
  Result.DriverName := 'SQLite';
  Result.Params.Values['Database'] := TPath.Combine(GDir, 'p' + IntToStr(GSeq) + '.sqlite');
  Result.LoginPrompt := False;
  Result.Connected := True;
  Result.ExecSQL('CREATE TABLE files (id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE, mtime_unix INTEGER NOT NULL DEFAULT 0, ' +
    'sha256 TEXT NOT NULL DEFAULT '''', parsed_at INTEGER NOT NULL DEFAULT 0, language TEXT NOT NULL DEFAULT '''')');
  if not pWithDfmTables then
    Exit;
  Result.ExecSQL('CREATE TABLE dfm_objects (file_id INTEGER NOT NULL, ordinal INTEGER NOT NULL, symbol_id INTEGER, name TEXT NOT NULL, ' +
    'class_name TEXT NOT NULL, parent_name TEXT NOT NULL, obj_kind TEXT NOT NULL, depth INTEGER NOT NULL, start_line INTEGER NOT NULL, ' +
    'start_col INTEGER NOT NULL, end_line INTEGER NOT NULL, end_col INTEGER NOT NULL)');
  Result.ExecSQL('CREATE TABLE dfm_properties (file_id INTEGER NOT NULL, ordinal INTEGER NOT NULL, object_ordinal INTEGER NOT NULL, ' +
    'parent INTEGER NOT NULL, depth INTEGER NOT NULL, name TEXT NOT NULL, value_text TEXT NOT NULL, value_kind TEXT NOT NULL, ' +
    'start_line INTEGER NOT NULL, start_col INTEGER NOT NULL, end_line INTEGER NOT NULL, end_col INTEGER NOT NULL)');
end;

procedure AddObject(pDb: TFDConnection; pFile, pOrd: Integer; const pName, pClass: string);
begin
  pDb.ExecSQL(Format('INSERT INTO dfm_objects VALUES (%d,%d,NULL,%s,%s,'''',''object'',1,%d,1,%d,1)',
    [pFile, pOrd, QuotedStr(pName), QuotedStr(pClass), pOrd * 10, pOrd * 10 + 5]));
end;

procedure AddProp(pDb: TFDConnection; pFile, pObj, pOrd: Integer; const pName, pValue: string; pLine: Integer);
begin
  pDb.ExecSQL(Format('INSERT INTO dfm_properties VALUES (%d,%d,%d,-1,0,%s,%s,''string'',%d,1,%d,1)',
    [pFile, pOrd, pObj, QuotedStr(pName), QuotedStr(pValue), pLine, pLine]));
end;

procedure TestDfmControl;
var
  vDb: TFDConnection;
  vUses: TArray<TFieldUse>;
begin
  vDb := NewProjectDb(True);
  try
    vDb.ExecSQL('INSERT INTO files(id, path) VALUES (1, ''C:\p\Main.dfm'')');
    AddObject(vDb, 1, 0, 'edName', 'TDBEdit');
    AddProp(vDb, 1, 0, 0, 'DataField', 'CUSTNAME', 12);
    AddObject(vDb, 1, 1, 'edCity', 'TcxDBTextEdit');
    AddProp(vDb, 1, 1, 1, 'DataField', 'CITY', 20);
    AddObject(vDb, 1, 2, 'colName', 'TcxGridDBColumn');
    AddProp(vDb, 1, 2, 2, 'DataBinding.FieldName', 'CUSTNAME', 30);
    vUses := FindFieldUses(vDb, 'custname');
    Check('M1 a DataField control is one fukDfmControl use (case-insensitive)',
      (Length(vUses) = 1) and (vUses[0].Kind = fukDfmControl), 'n=' + IntToStr(Length(vUses)));
    if Length(vUses) = 1 then
    begin
      Check('M2 use carries component, class, file and line',
        (vUses[0].Component = 'edName') and (vUses[0].ComponentClass = 'TDBEdit') and (vUses[0].FilePath = 'C:\p\Main.dfm') and
        (vUses[0].Line = 12), vUses[0].Component + '/' + vUses[0].ComponentClass + '/' + vUses[0].FilePath + '/' + IntToStr(vUses[0].Line));
      Check('M3 FieldName as written at the use site', vUses[0].FieldName = 'CUSTNAME');
    end
    else
      Check('M2/M3 skipped: no use returned', False);
    Check('M4 FieldUseKinds = [fukDfmControl]', FieldUseKinds(vDb, 'CUSTNAME') = [fukDfmControl]);
    Check('M5 an unused field has no kind', FieldUseKinds(vDb, 'NOSUCH') = []);
    Check('M6 an empty name has no use', Length(FindFieldUses(vDb, '')) = 0);
  finally
    vDb.Free;
  end;
end;

procedure TestOldIndex;
var
  vDb: TFDConnection;
begin
  vDb := NewProjectDb(False);
  try
    Check('M7 a DB without the DFM tables returns no use and does not raise', Length(FindFieldUses(vDb, 'CUSTNAME')) = 0);
  finally
    vDb.Free;
  end;
end;

begin
  GDir := TPath.Combine(TPath.GetTempPath, 'dl-fieldusage-' + IntToStr(GetCurrentProcessId));
  ForceDirectories(GDir);
  try
    try
      TestDfmControl;
      TestOldIndex;
    except
      on E: Exception do
      begin
        Inc(GFail);
        Writeln('FAIL unhandled ', E.ClassName, ': ', E.Message);
      end;
    end;
  finally
    try
      TDirectory.Delete(GDir, True);
    except
      on EInOutError do
        Writeln('NOTE temp dir not removed: ', GDir);
    end;
  end;
  Writeln('SUMMARY pass=', GPass, ' fail=', GFail);
  if GFail > 0 then
    ExitCode := 1;
end.
