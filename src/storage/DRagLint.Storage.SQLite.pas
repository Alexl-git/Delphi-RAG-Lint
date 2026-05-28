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
    FQInsertTrigram: TFDQuery;
    FQInsertRef: TFDQuery;
    FQDeleteFileSymbols: TFDQuery;
    FQDeleteFileRefs: TFDQuery;
    FQFindByName: TFDQuery;
    FQFindByQName: TFDQuery;
    FQCountSymbols: TFDQuery;
    FQCountFiles: TFDQuery;
    FQUpsertSymbolDoc: TFDQuery;
    FQDeleteFileDocs: TFDQuery;
    FQGetSymbolDoc: TFDQuery;
    FQFindByDocTag: TFDQuery;
    FQFindUndocumented: TFDQuery;
    FQFindByDocContains: TFDQuery;
    procedure Connect(const ADbPath: string);
    procedure PrepareStatements;
    procedure EnsureTrigramTablePopulated;
  public
    constructor Create(const ADbPath: string);
    destructor Destroy; override;

    procedure Migrate;

    function FileIsUpToDate(const APath: string; AMtimeUnix: Int64;
      const ASha: string): Boolean;
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
    function FindSymbolsFuzzy(const APattern: string; ATopK: Integer = 10): TArray<TSymbol>;
    function GetFilePath(AFileId: Int64): string;
    function CountSymbols: Int64;
    function CountReferences: Int64;
    function CountFiles: Int64;

    procedure UpsertSymbolDoc(const AToken: TFileTxToken;
      ASymbolId: Int64; const ADoc: TParsedDoc);
    function GetSymbolDoc(ASymbolId: Int64): TParsedDoc;
    function FindByDocTag(const ATag: string): TArray<TSymbol>;
    function FindUndocumented(const AKind: string;
      APublicOnly: Boolean): TArray<TSymbol>;
    function FindByDocContains(const ASubstring: string): TArray<TSymbol>;
    procedure DeleteFileDocs(AFileId: Int64);
  end;

implementation

uses
  System.Generics.Defaults,
  System.StrUtils,
  DRagLint.Storage.Schema,
  DRagLint.Query.Fuzzy;

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
  FQInsertTrigram.Free;
  FQInsertRef.Free;
  FQDeleteFileSymbols.Free;
  FQDeleteFileRefs.Free;
  FQFindByName.Free;
  FQFindByQName.Free;
  FQCountSymbols.Free;
  FQCountFiles.Free;
  FQUpsertSymbolDoc.Free;
  FQDeleteFileDocs.Free;
  FQGetSymbolDoc.Free;
  FQFindByDocTag.Free;
  FQFindUndocumented.Free;
  FQFindByDocContains.Free;
  if Assigned(FConn) then
  begin
    if FConn.Connected then
      FConn.Close;
    FConn.Free;
  end;
  inherited;
end;

procedure TSQLiteSymbolStore.EnsureTrigramTablePopulated;
var
  CheckQ, NameQ, InsertQ: TFDQuery;
  Grams: TArray<string>;
  G: string;
  SymId: Int64;
  SymName: string;
begin
  // Check whether symbol_trigrams already has rows. If yes, we're good - the
  // table is kept in sync by triggers (next iteration); for now we just
  // populate-on-demand here. If empty, populate from symbols.
  CheckQ := TFDQuery.Create(nil);
  try
    CheckQ.Connection := FConn;
    CheckQ.SQL.Text := 'SELECT 1 FROM symbol_trigrams LIMIT 1';
    CheckQ.Open;
    if not CheckQ.IsEmpty then
      Exit;
  finally
    CheckQ.Free;
  end;

  // Empty - build it. Per-batch transaction for speed.
  NameQ := TFDQuery.Create(nil);
  InsertQ := TFDQuery.Create(nil);
  try
    NameQ.Connection := FConn;
    NameQ.SQL.Text := 'SELECT id, name FROM symbols';
    NameQ.Open;
    InsertQ.Connection := FConn;
    InsertQ.SQL.Text :=
      'INSERT OR IGNORE INTO symbol_trigrams(trigram, symbol_id) ' +
      'VALUES (:tg, :sid)';
    InsertQ.Params.ParamByName('tg').DataType := ftString;
    InsertQ.Params.ParamByName('sid').DataType := ftLargeint;
    FConn.StartTransaction;
    try
      while not NameQ.Eof do
      begin
        SymId := NameQ.FieldByName('id').AsLargeInt;
        SymName := NameQ.FieldByName('name').AsString;
        Grams := DRagLint.Query.Fuzzy.Trigrams(SymName);
        for G in Grams do
        begin
          InsertQ.ParamByName('tg').AsString := G;
          InsertQ.ParamByName('sid').AsLargeInt := SymId;
          InsertQ.ExecSQL;
        end;
        NameQ.Next;
      end;
      FConn.Commit;
    except
      FConn.Rollback;
      raise;
    end;
  finally
    NameQ.Free;
    InsertQ.Free;
  end;
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
  FQInsertTrigram := NewQuery(
    'INSERT OR IGNORE INTO symbol_trigrams(trigram, symbol_id) ' +
    'VALUES (:tg, :sid)');
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

  FQUpsertSymbolDoc := NewQuery(
    'INSERT OR REPLACE INTO symbol_docs ' +
    '(symbol_id, format, raw_block, summary, remarks, returns_text, ' +
    ' params_json, exceptions_json, example_text, seealso_json, since_text, ' +
    ' deprecated, start_line, end_line) ' +
    'VALUES (:sid, :fmt, :raw, :sum, :rem, :ret, :pj, :ej, :ex, :sj, :since, ' +
    ' :dep, :sl, :el)');
  // Pre-declare all param types before the first Prepare/Execute so FireDAC
  // does not re-infer types from run-time values. Without this, a param that
  // is NULL on one call and non-NULL on another raises [SQLite]-338.
  FQUpsertSymbolDoc.Params.ParamByName('sid').DataType := ftLargeint;
  FQUpsertSymbolDoc.Params.ParamByName('fmt').DataType := ftString;
  FQUpsertSymbolDoc.Params.ParamByName('raw').DataType := ftString;
  FQUpsertSymbolDoc.Params.ParamByName('sum').DataType := ftWideMemo;
  FQUpsertSymbolDoc.Params.ParamByName('rem').DataType := ftWideMemo;
  FQUpsertSymbolDoc.Params.ParamByName('ret').DataType := ftWideMemo;
  FQUpsertSymbolDoc.Params.ParamByName('pj').DataType := ftWideMemo;
  FQUpsertSymbolDoc.Params.ParamByName('ej').DataType := ftWideMemo;
  FQUpsertSymbolDoc.Params.ParamByName('ex').DataType := ftWideMemo;
  FQUpsertSymbolDoc.Params.ParamByName('sj').DataType := ftWideMemo;
  FQUpsertSymbolDoc.Params.ParamByName('since').DataType := ftWideMemo;
  FQUpsertSymbolDoc.Params.ParamByName('dep').DataType := ftInteger;
  FQUpsertSymbolDoc.Params.ParamByName('sl').DataType := ftInteger;
  FQUpsertSymbolDoc.Params.ParamByName('el').DataType := ftInteger;
  FQUpsertSymbolDoc.Prepare;

  FQDeleteFileDocs := NewQuery(
    'DELETE FROM symbol_docs WHERE symbol_id IN ' +
    '(SELECT id FROM symbols WHERE file_id = :fid)');

  FQGetSymbolDoc := NewQuery(
    'SELECT format, raw_block, summary, remarks, returns_text, ' +
    ' params_json, exceptions_json, example_text, seealso_json, since_text, ' +
    ' deprecated, start_line, end_line ' +
    'FROM symbol_docs WHERE symbol_id = :sid');

  FQFindByDocTag := NewQuery(
    'SELECT s.* FROM symbols s INNER JOIN symbol_docs d ON d.symbol_id = s.id ' +
    'WHERE (:tag = ''deprecated'' AND d.deprecated = 1) ' +
    '   OR (:tag = ''since'' AND d.since_text IS NOT NULL)');

  FQFindUndocumented := NewQuery(
    'SELECT s.* FROM symbols s ' +
    'LEFT JOIN symbol_docs d ON d.symbol_id = s.id ' +
    'WHERE d.symbol_id IS NULL ' +
    '  AND (:kind = '''' OR s.kind = :kind) ' +
    '  AND (:publicOnly = 0 OR (s.modifiers IS NULL ' +
    '       OR (s.modifiers NOT LIKE ''%private%'' AND ' +
    '           s.modifiers NOT LIKE ''%protected%'')))');

  FQFindByDocContains := NewQuery(
    'SELECT s.* FROM symbols s INNER JOIN symbol_docs d ON d.symbol_id = s.id ' +
    'WHERE d.summary LIKE :pat OR d.remarks LIKE :pat OR d.example_text LIKE :pat');
end;

function TSQLiteSymbolStore.FileIsUpToDate(const APath: string;
  AMtimeUnix: Int64; const ASha: string): Boolean;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConn;
    Q.SQL.Text :=
      'SELECT 1 FROM files WHERE path = :p AND mtime_unix = :m ' +
      'AND sha256 = :s';
    Q.ParamByName('p').AsString := APath;
    Q.ParamByName('m').AsLargeInt := AMtimeUnix;
    Q.ParamByName('s').AsString := ASha;
    Q.Open;
    Result := not Q.IsEmpty;
  finally
    Q.Free;
  end;
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
  // Populate trigram index alongside each symbol insert so fuzzy queries
  // are sub-second from the first call without any lazy build cost.
  var Grams := DRagLint.Query.Fuzzy.Trigrams(ASymbol.Name);
  var G: string;
  for G in Grams do
  begin
    FQInsertTrigram.ParamByName('tg').AsString := G;
    FQInsertTrigram.ParamByName('sid').AsLargeInt := Result;
    FQInsertTrigram.ExecSQL;
  end;
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

function TSQLiteSymbolStore.FindSymbolsFuzzy(const APattern: string;
  ATopK: Integer): TArray<TSymbol>;
var
  Q: TFDQuery;
  Scored: TList<TPair<Integer, TSymbol>>;
  D, MaxD: Integer;
  Grams: TArray<string>;
  PlaceholderList: string;
  i: Integer;
  Sym: TSymbol;
begin
  SetLength(Result, 0);
  EnsureTrigramTablePopulated;
  MaxD := DRagLint.Query.Fuzzy.FuzzyMaxDistanceFor(APattern);
  Grams := DRagLint.Query.Fuzzy.Trigrams(APattern);

  Scored := TList<TPair<Integer, TSymbol>>.Create;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConn;
    if Length(Grams) = 0 then
    begin
      // Pattern too short for trigrams - full scan (still fast for short pattern).
      Q.SQL.Text := 'SELECT * FROM symbols';
    end
    else
    begin
      // Build placeholder list for IN clause: ?, ?, ?, ...
      PlaceholderList := '';
      for i := 0 to High(Grams) do
      begin
        if i > 0 then
          PlaceholderList := PlaceholderList + ', ';
        PlaceholderList := PlaceholderList + ':g' + IntToStr(i);
      end;
      Q.SQL.Text :=
        'SELECT s.* FROM symbols s ' +
        'WHERE s.id IN (' +
        '  SELECT DISTINCT symbol_id FROM symbol_trigrams ' +
        '  WHERE trigram IN (' + PlaceholderList + ')' +
        ')';
      for i := 0 to High(Grams) do
        Q.ParamByName('g' + IntToStr(i)).AsString := Grams[i];
    end;
    Q.Open;
    while not Q.Eof do
    begin
      Sym := ReadSymbolFromQuery(Q);
      D := DRagLint.Query.Fuzzy.LevenshteinDistance(APattern, Sym.Name);
      if D <= MaxD then
        Scored.Add(TPair<Integer, TSymbol>.Create(D, Sym));
      Q.Next;
    end;

    Scored.Sort(TComparer<TPair<Integer, TSymbol>>.Construct(
      function(const L, R: TPair<Integer, TSymbol>): Integer
      begin
        Result := L.Key - R.Key;
        if Result = 0 then
          Result := CompareText(L.Value.QualifiedName, R.Value.QualifiedName);
      end));
    if Scored.Count > ATopK then
      Scored.Count := ATopK;
    SetLength(Result, Scored.Count);
    for i := 0 to Scored.Count - 1 do
      Result[i] := Scored[i].Value;
  finally
    Q.Free;
    Scored.Free;
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
    // Match any reference kind (call, event-binding, type_use, ...). "callers"
    // is a slight misnomer - the semantic is "every site that references
    // this name" - but it's what users mean when they say find-callers.
    Q.SQL.Text :=
      'SELECT * FROM refs WHERE name_text = :name ' +
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

procedure TSQLiteSymbolStore.UpsertSymbolDoc(const AToken: TFileTxToken;
  ASymbolId: Int64; const ADoc: TParsedDoc);
// Helper: assign a nullable text param without changing its pre-declared
// DataType. Using AsString would silently flip DataType to ftString and break
// the next call with [SQLite]-338 "Param type changed".
  procedure SetNullableText(const AParamName: string; const AValue: string);
  begin
    with FQUpsertSymbolDoc.ParamByName(AParamName) do
      if AValue = '' then Clear else Value := AValue;
  end;
begin
  if not ADoc.HasContent then Exit;
  FQUpsertSymbolDoc.ParamByName('sid').AsLargeInt := ASymbolId;
  FQUpsertSymbolDoc.ParamByName('fmt').AsString := DocFormatToStr(ADoc.Format);
  FQUpsertSymbolDoc.ParamByName('raw').AsString := ADoc.RawBlock;

  // Use Value := (not AsString :=) so DataType stays as pre-declared ftWideMemo.
  // AsString := implicitly changes DataType to ftString, which raises
  // [SQLite]-338 on subsequent calls once the query is Prepared.
  SetNullableText('sum', ADoc.Summary);
  SetNullableText('rem', ADoc.Remarks);
  SetNullableText('ret', ADoc.ReturnsText);
  if Length(ADoc.Params) = 0 then
    FQUpsertSymbolDoc.ParamByName('pj').Clear
  else
    FQUpsertSymbolDoc.ParamByName('pj').Value := ParamsToJson(ADoc.Params);
  if Length(ADoc.Exceptions) = 0 then
    FQUpsertSymbolDoc.ParamByName('ej').Clear
  else
    FQUpsertSymbolDoc.ParamByName('ej').Value := ExceptionsToJson(ADoc.Exceptions);
  SetNullableText('ex', ADoc.ExampleText);
  if Length(ADoc.SeeAlso) = 0 then
    FQUpsertSymbolDoc.ParamByName('sj').Clear
  else
    FQUpsertSymbolDoc.ParamByName('sj').Value := SeeAlsoToJson(ADoc.SeeAlso);
  SetNullableText('since', ADoc.SinceText);

  FQUpsertSymbolDoc.ParamByName('dep').AsInteger := Ord(ADoc.Deprecated);
  FQUpsertSymbolDoc.ParamByName('sl').AsInteger := ADoc.StartLine;
  FQUpsertSymbolDoc.ParamByName('el').AsInteger := ADoc.EndLine;
  FQUpsertSymbolDoc.ExecSQL;
end;

function TSQLiteSymbolStore.GetSymbolDoc(ASymbolId: Int64): TParsedDoc;
begin
  FillChar(Result, SizeOf(Result), 0);
  if FQGetSymbolDoc.Active then
    FQGetSymbolDoc.Close;
  FQGetSymbolDoc.ParamByName('sid').AsLargeInt := ASymbolId;
  FQGetSymbolDoc.Open;
  try
    if FQGetSymbolDoc.IsEmpty then Exit;
    case IndexStr(FQGetSymbolDoc.FieldByName('format').AsString,
                  ['xmldoc', 'pasdoc', 'oneline', 'loose']) of
      0: Result.Format := dfXmlDoc;
      1: Result.Format := dfPasDoc;
      2: Result.Format := dfOneline;
      3: Result.Format := dfLoose;
    end;
    Result.RawBlock    := FQGetSymbolDoc.FieldByName('raw_block').AsString;
    Result.Summary     := FQGetSymbolDoc.FieldByName('summary').AsString;
    Result.Remarks     := FQGetSymbolDoc.FieldByName('remarks').AsString;
    Result.ReturnsText := FQGetSymbolDoc.FieldByName('returns_text').AsString;
    Result.ExampleText := FQGetSymbolDoc.FieldByName('example_text').AsString;
    Result.SinceText   := FQGetSymbolDoc.FieldByName('since_text').AsString;
    Result.Deprecated  := FQGetSymbolDoc.FieldByName('deprecated').AsInteger = 1;
    Result.StartLine   := FQGetSymbolDoc.FieldByName('start_line').AsInteger;
    Result.EndLine     := FQGetSymbolDoc.FieldByName('end_line').AsInteger;
    // Raw JSON strings — v0.16 renderers read these directly; v0.17 may parse.
    Result.ParamsJsonRaw     := FQGetSymbolDoc.FieldByName('params_json').AsString;
    Result.ExceptionsJsonRaw := FQGetSymbolDoc.FieldByName('exceptions_json').AsString;
    Result.SeeAlsoJsonRaw    := FQGetSymbolDoc.FieldByName('seealso_json').AsString;
    Result.HasContent  := True;
  finally
    FQGetSymbolDoc.Close;
  end;
end;

function TSQLiteSymbolStore.FindByDocTag(const ATag: string): TArray<TSymbol>;
var
  Acc: TList<TSymbol>;
begin
  Acc := TList<TSymbol>.Create;
  try
    if FQFindByDocTag.Active then
      FQFindByDocTag.Close;
    FQFindByDocTag.ParamByName('tag').AsString := LowerCase(ATag);
    FQFindByDocTag.Open;
    try
      while not FQFindByDocTag.Eof do
      begin
        Acc.Add(ReadSymbolFromQuery(FQFindByDocTag));
        FQFindByDocTag.Next;
      end;
    finally
      FQFindByDocTag.Close;
    end;
    Result := Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

function TSQLiteSymbolStore.FindUndocumented(const AKind: string;
  APublicOnly: Boolean): TArray<TSymbol>;
var
  Acc: TList<TSymbol>;
begin
  Acc := TList<TSymbol>.Create;
  try
    if FQFindUndocumented.Active then
      FQFindUndocumented.Close;
    FQFindUndocumented.ParamByName('kind').AsString := AKind;
    FQFindUndocumented.ParamByName('publicOnly').AsInteger := Ord(APublicOnly);
    FQFindUndocumented.Open;
    try
      while not FQFindUndocumented.Eof do
      begin
        Acc.Add(ReadSymbolFromQuery(FQFindUndocumented));
        FQFindUndocumented.Next;
      end;
    finally
      FQFindUndocumented.Close;
    end;
    Result := Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

function TSQLiteSymbolStore.FindByDocContains(
  const ASubstring: string): TArray<TSymbol>;
var
  Acc: TList<TSymbol>;
begin
  Acc := TList<TSymbol>.Create;
  try
    if FQFindByDocContains.Active then
      FQFindByDocContains.Close;
    FQFindByDocContains.ParamByName('pat').AsString := '%' + ASubstring + '%';
    FQFindByDocContains.Open;
    try
      while not FQFindByDocContains.Eof do
      begin
        Acc.Add(ReadSymbolFromQuery(FQFindByDocContains));
        FQFindByDocContains.Next;
      end;
    finally
      FQFindByDocContains.Close;
    end;
    Result := Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

procedure TSQLiteSymbolStore.DeleteFileDocs(AFileId: Int64);
begin
  FQDeleteFileDocs.ParamByName('fid').AsLargeInt := AFileId;
  FQDeleteFileDocs.ExecSQL;
end;

end.
