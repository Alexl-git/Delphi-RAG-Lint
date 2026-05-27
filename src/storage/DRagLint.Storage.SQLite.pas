unit DRagLint.Storage.SQLite;

interface

uses
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  System.Generics.Collections,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Phys.SQLite,
  FireDAC.Stan.Param,
  FireDAC.DApt,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces;

type
  TSQLiteSymbolStore = class(TInterfacedObject, ISymbolStore)
  strict private
    FConn: TFDConnection;
    FQInsertFile: TFDQuery;
    FQUpsertFile: TFDQuery;
    FQInsertSymbol: TFDQuery;
    FQInsertRef: TFDQuery;
    FQDeleteFileSymbols: TFDQuery;
    FQDeleteFileRefs: TFDQuery;
    FQFindByName: TFDQuery;
    FQFindByQName: TFDQuery;
    FQCountSymbols: TFDQuery;
    FQCountFiles: TFDQuery;
    procedure Connect(const ADbPath: string);
    procedure PrepareStatements;
  public
    constructor Create(const ADbPath: string);
    destructor Destroy; override;

    procedure Migrate;

    function OpenFileTx(const APath: string; AMtimeUnix: Int64;
      const ASha: string; const ALanguage: string): TFileTxToken;
    function UpsertSymbol(const AToken: TFileTxToken;
      const ASymbol: TSymbol): Int64;
    procedure UpsertReference(const AToken: TFileTxToken;
      const ARef: TReference);
    procedure UpsertChunk(const AToken: TFileTxToken; const AChunk: TChunk);
    procedure CommitFileTx(const AToken: TFileTxToken);
    procedure RollbackFileTx(const AToken: TFileTxToken);

    function FindSymbolsByExactName(const AName: string): TArray<TSymbol>;
    function FindSymbolsByQualifiedName(const AQName: string): TArray<TSymbol>;
    function FindReferencesTo(ASymbolId: Int64): TArray<TReference>;
    function FindCallersByName(const ACalleeName: string): TArray<TReference>;
    function GetFilePath(AFileId: Int64): string;
    function CountSymbols: Int64;
    function CountReferences: Int64;
    function CountFiles: Int64;
  end;

implementation

uses
  DRagLint.Storage.Schema;

{ TSQLiteSymbolStore }

constructor TSQLiteSymbolStore.Create(const ADbPath: string);
begin
  inherited Create;
  Connect(ADbPath);
end;

destructor TSQLiteSymbolStore.Destroy;
begin
  FQInsertFile.Free;
  FQUpsertFile.Free;
  FQInsertSymbol.Free;
  FQInsertRef.Free;
  FQDeleteFileSymbols.Free;
  FQDeleteFileRefs.Free;
  FQFindByName.Free;
  FQFindByQName.Free;
  FQCountSymbols.Free;
  FQCountFiles.Free;
  if Assigned(FConn) then
  begin
    if FConn.Connected then
      FConn.Close;
    FConn.Free;
  end;
  inherited;
end;

procedure TSQLiteSymbolStore.Connect(const ADbPath: string);
begin
  FConn := TFDConnection.Create(nil);
  FConn.DriverName := 'SQLite';
  FConn.Params.Values['Database'] := ADbPath;
  FConn.Params.Values['LockingMode'] := 'Normal';
  FConn.Params.Values['JournalMode'] := 'WAL';
  FConn.Params.Values['Synchronous'] := 'Normal';
  FConn.LoginPrompt := False;
  FConn.Connected := True;
  FConn.ExecSQL('PRAGMA foreign_keys = ON');
end;

procedure TSQLiteSymbolStore.Migrate;
var
  Stmt: string;
begin
  FConn.StartTransaction;
  try
    for Stmt in SCHEMA_DDL do
      FConn.ExecSQL(Stmt);
    FConn.ExecSQL(
      'INSERT OR REPLACE INTO schema_meta(key, value) VALUES (''schema_version'', ?)',
      [IntToStr(SCHEMA_VERSION)]);
    FConn.Commit;
  except
    FConn.Rollback;
    raise;
  end;
  PrepareStatements;
end;

procedure TSQLiteSymbolStore.PrepareStatements;
  function NewQuery(const ASQL: string): TFDQuery;
  begin
    Result := TFDQuery.Create(nil);
    Result.Connection := FConn;
    Result.SQL.Text := ASQL;
    // FireDAC auto-prepares on first execution; param types are inferred from
    // the first set of param values, so do NOT call Prepare here.
  end;
begin
  FQInsertFile := NewQuery(
    'INSERT INTO files(path, mtime_unix, sha256, parsed_at, language) ' +
    'VALUES (:path, :mtime, :sha, :parsed, :lang)');
  FQUpsertFile := NewQuery(
    'INSERT INTO files(path, mtime_unix, sha256, parsed_at, language) ' +
    'VALUES (:path, :mtime, :sha, :parsed, :lang) ' +
    'ON CONFLICT(path) DO UPDATE SET ' +
    '  mtime_unix=excluded.mtime_unix, ' +
    '  sha256=excluded.sha256, ' +
    '  parsed_at=excluded.parsed_at, ' +
    '  language=excluded.language');
  FQInsertSymbol := NewQuery(
    'INSERT INTO symbols(file_id, parent_id, kind, name, qualified_name, ' +
    '  signature, modifiers, start_line, start_col, end_line, end_col) ' +
    'VALUES (:fid, :pid, :kind, :name, :qname, :sig, :mods, ' +
    '  :sl, :sc, :el, :ec)');
  FQInsertRef := NewQuery(
    'INSERT INTO refs(symbol_id, file_id, kind, name_text, ' +
    '  start_line, start_col, end_line, end_col) ' +
    'VALUES (:sid, :fid, :kind, :name, :sl, :sc, :el, :ec)');
  FQDeleteFileSymbols := NewQuery('DELETE FROM symbols WHERE file_id = :fid');
  FQDeleteFileRefs := NewQuery('DELETE FROM refs WHERE file_id = :fid');
  FQFindByName := NewQuery(
    'SELECT * FROM symbols WHERE name = :name ORDER BY qualified_name');
  FQFindByQName := NewQuery(
    'SELECT * FROM symbols WHERE qualified_name = :qname');
  FQCountSymbols := NewQuery('SELECT COUNT(*) AS n FROM symbols');
  FQCountFiles := NewQuery('SELECT COUNT(*) AS n FROM files');
end;

function TSQLiteSymbolStore.OpenFileTx(const APath: string;
  AMtimeUnix: Int64; const ASha: string;
  const ALanguage: string): TFileTxToken;
var
  Q: TFDQuery;
begin
  FConn.StartTransaction;
  try
    FQUpsertFile.ParamByName('path').AsString := APath;
    FQUpsertFile.ParamByName('mtime').AsLargeInt := AMtimeUnix;
    FQUpsertFile.ParamByName('sha').AsString := ASha;
    FQUpsertFile.ParamByName('parsed').AsLargeInt :=
      DateTimeToUnix(Now, False);
    FQUpsertFile.ParamByName('lang').AsString := ALanguage;
    FQUpsertFile.ExecSQL;

    Q := TFDQuery.Create(nil);
    try
      Q.Connection := FConn;
      Q.SQL.Text := 'SELECT id FROM files WHERE path = :path';
      Q.ParamByName('path').AsString := APath;
      Q.Open;
      if Q.IsEmpty then
        raise Exception.CreateFmt('File row not found after upsert: %s', [APath]);
      Result.FileId := Q.Fields[0].AsLargeInt;
      Result.Path := APath;
    finally
      Q.Free;
    end;

    // Phase 1: full re-emit semantics. Clear old symbols/refs for this file
    // before the caller starts emitting fresh records.
    FQDeleteFileRefs.ParamByName('fid').AsLargeInt := Result.FileId;
    FQDeleteFileRefs.ExecSQL;
    FQDeleteFileSymbols.ParamByName('fid').AsLargeInt := Result.FileId;
    FQDeleteFileSymbols.ExecSQL;
  except
    FConn.Rollback;
    raise;
  end;
end;

function TSQLiteSymbolStore.UpsertSymbol(const AToken: TFileTxToken;
  const ASymbol: TSymbol): Int64;
begin
  FQInsertSymbol.ParamByName('fid').AsLargeInt := AToken.FileId;
  FQInsertSymbol.ParamByName('pid').DataType := ftLargeint;
  if ASymbol.ParentId >= 0 then
    FQInsertSymbol.ParamByName('pid').AsLargeInt := ASymbol.ParentId
  else
    FQInsertSymbol.ParamByName('pid').Clear;
  FQInsertSymbol.ParamByName('kind').AsString := ASymbol.Kind.ToText;
  FQInsertSymbol.ParamByName('name').AsString := ASymbol.Name;
  FQInsertSymbol.ParamByName('qname').AsString := ASymbol.QualifiedName;
  FQInsertSymbol.ParamByName('sig').AsString := ASymbol.Signature;
  FQInsertSymbol.ParamByName('mods').AsString := ASymbol.Modifiers;
  FQInsertSymbol.ParamByName('sl').AsInteger := ASymbol.StartLine;
  FQInsertSymbol.ParamByName('sc').AsInteger := ASymbol.StartCol;
  FQInsertSymbol.ParamByName('el').AsInteger := ASymbol.EndLine;
  FQInsertSymbol.ParamByName('ec').AsInteger := ASymbol.EndCol;
  FQInsertSymbol.ExecSQL;
  Result := FConn.GetLastAutoGenValue('');
end;

procedure TSQLiteSymbolStore.UpsertReference(const AToken: TFileTxToken;
  const ARef: TReference);
begin
  FQInsertRef.ParamByName('sid').DataType := ftLargeint;
  if ARef.SymbolId > 0 then
    FQInsertRef.ParamByName('sid').AsLargeInt := ARef.SymbolId
  else
    FQInsertRef.ParamByName('sid').Clear;
  FQInsertRef.ParamByName('fid').AsLargeInt := AToken.FileId;
  FQInsertRef.ParamByName('kind').AsString := ARef.Kind;
  FQInsertRef.ParamByName('name').AsString := ARef.NameText;
  FQInsertRef.ParamByName('sl').AsInteger := ARef.StartLine;
  FQInsertRef.ParamByName('sc').AsInteger := ARef.StartCol;
  FQInsertRef.ParamByName('el').AsInteger := ARef.EndLine;
  FQInsertRef.ParamByName('ec').AsInteger := ARef.EndCol;
  FQInsertRef.ExecSQL;
end;

procedure TSQLiteSymbolStore.UpsertChunk(const AToken: TFileTxToken;
  const AChunk: TChunk);
begin
  // Phase 1 omits chunk storage.
end;

procedure TSQLiteSymbolStore.CommitFileTx(const AToken: TFileTxToken);
begin
  FConn.Commit;
end;

procedure TSQLiteSymbolStore.RollbackFileTx(const AToken: TFileTxToken);
begin
  FConn.Rollback;
end;

function ReadSymbolFromQuery(AQ: TFDQuery): TSymbol;
begin
  Result := Default(TSymbol);
  Result.Id := AQ.FieldByName('id').AsLargeInt;
  Result.FileId := AQ.FieldByName('file_id').AsLargeInt;
  if AQ.FieldByName('parent_id').IsNull then
    Result.ParentId := -1
  else
    Result.ParentId := AQ.FieldByName('parent_id').AsLargeInt;
  Result.Kind := TSymbolKind.FromText(AQ.FieldByName('kind').AsString);
  Result.Name := AQ.FieldByName('name').AsString;
  Result.QualifiedName := AQ.FieldByName('qualified_name').AsString;
  Result.Signature := AQ.FieldByName('signature').AsString;
  Result.Modifiers := AQ.FieldByName('modifiers').AsString;
  Result.StartLine := AQ.FieldByName('start_line').AsInteger;
  Result.StartCol := AQ.FieldByName('start_col').AsInteger;
  Result.EndLine := AQ.FieldByName('end_line').AsInteger;
  Result.EndCol := AQ.FieldByName('end_col').AsInteger;
end;

function TSQLiteSymbolStore.FindSymbolsByExactName(
  const AName: string): TArray<TSymbol>;
var
  List: TList<TSymbol>;
begin
  List := TList<TSymbol>.Create;
  try
    if FQFindByName.Active then
      FQFindByName.Close;
    FQFindByName.ParamByName('name').AsString := AName;
    FQFindByName.Open;
    while not FQFindByName.Eof do
    begin
      List.Add(ReadSymbolFromQuery(FQFindByName));
      FQFindByName.Next;
    end;
    FQFindByName.Close;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TSQLiteSymbolStore.FindSymbolsByQualifiedName(
  const AQName: string): TArray<TSymbol>;
var
  List: TList<TSymbol>;
begin
  List := TList<TSymbol>.Create;
  try
    if FQFindByQName.Active then
      FQFindByQName.Close;
    FQFindByQName.ParamByName('qname').AsString := AQName;
    FQFindByQName.Open;
    while not FQFindByQName.Eof do
    begin
      List.Add(ReadSymbolFromQuery(FQFindByQName));
      FQFindByQName.Next;
    end;
    FQFindByQName.Close;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TSQLiteSymbolStore.FindReferencesTo(
  ASymbolId: Int64): TArray<TReference>;
var
  Q: TFDQuery;
  List: TList<TReference>;
  R: TReference;
begin
  List := TList<TReference>.Create;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConn;
    Q.SQL.Text :=
      'SELECT * FROM refs WHERE symbol_id = :sid ORDER BY file_id, start_line';
    Q.ParamByName('sid').AsLargeInt := ASymbolId;
    Q.Open;
    while not Q.Eof do
    begin
      R := Default(TReference);
      R.Id := Q.FieldByName('id').AsLargeInt;
      R.SymbolId := ASymbolId;
      R.FileId := Q.FieldByName('file_id').AsLargeInt;
      R.Kind := Q.FieldByName('kind').AsString;
      R.NameText := Q.FieldByName('name_text').AsString;
      R.StartLine := Q.FieldByName('start_line').AsInteger;
      R.StartCol := Q.FieldByName('start_col').AsInteger;
      R.EndLine := Q.FieldByName('end_line').AsInteger;
      R.EndCol := Q.FieldByName('end_col').AsInteger;
      List.Add(R);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

function TSQLiteSymbolStore.FindCallersByName(
  const ACalleeName: string): TArray<TReference>;
var
  Q: TFDQuery;
  List: TList<TReference>;
  R: TReference;
begin
  List := TList<TReference>.Create;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConn;
    Q.SQL.Text :=
      'SELECT * FROM refs WHERE kind = ''call'' AND name_text = :name ' +
      'ORDER BY file_id, start_line';
    Q.ParamByName('name').AsString := ACalleeName;
    Q.Open;
    while not Q.Eof do
    begin
      R := Default(TReference);
      R.Id := Q.FieldByName('id').AsLargeInt;
      if Q.FieldByName('symbol_id').IsNull then
        R.SymbolId := 0
      else
        R.SymbolId := Q.FieldByName('symbol_id').AsLargeInt;
      R.FileId := Q.FieldByName('file_id').AsLargeInt;
      R.Kind := Q.FieldByName('kind').AsString;
      R.NameText := Q.FieldByName('name_text').AsString;
      R.StartLine := Q.FieldByName('start_line').AsInteger;
      R.StartCol := Q.FieldByName('start_col').AsInteger;
      R.EndLine := Q.FieldByName('end_line').AsInteger;
      R.EndCol := Q.FieldByName('end_col').AsInteger;
      List.Add(R);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

function TSQLiteSymbolStore.GetFilePath(AFileId: Int64): string;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConn;
    Q.SQL.Text := 'SELECT path FROM files WHERE id = :id';
    Q.ParamByName('id').AsLargeInt := AFileId;
    Q.Open;
    if Q.IsEmpty then
      Result := ''
    else
      Result := Q.FieldByName('path').AsString;
  finally
    Q.Free;
  end;
end;

function TSQLiteSymbolStore.CountSymbols: Int64;
begin
  if FQCountSymbols.Active then
    FQCountSymbols.Close;
  FQCountSymbols.Open;
  Result := FQCountSymbols.FieldByName('n').AsLargeInt;
  FQCountSymbols.Close;
end;

function TSQLiteSymbolStore.CountReferences: Int64;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConn;
    Q.SQL.Text := 'SELECT COUNT(*) AS n FROM refs';
    Q.Open;
    Result := Q.FieldByName('n').AsLargeInt;
  finally
    Q.Free;
  end;
end;

function TSQLiteSymbolStore.CountFiles: Int64;
begin
  if FQCountFiles.Active then
    FQCountFiles.Close;
  FQCountFiles.Open;
  Result := FQCountFiles.FieldByName('n').AsLargeInt;
  FQCountFiles.Close;
end;

end.
