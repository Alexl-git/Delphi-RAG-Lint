unit DRagLint.Storage.SQLite;

interface

uses
  System.SysUtils
  , System.Classes
  , System.DateUtils
  , System.Generics.Collections
  , Data.DB
  , FireDAC.Comp.Client
  , FireDAC.Stan.Def
  , FireDAC.Stan.Async
  , FireDAC.Phys.SQLite
  , FireDAC.Stan.Param
  , FireDAC.DApt
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  TSQLiteSymbolStore = class(TInterfacedObject, ISymbolStore)
    strict private
      FConn                  : TFDConnection;
      FQInsertFile           : TFDQuery     ;
      FQUpsertFile           : TFDQuery     ;
      FQInsertSymbol         : TFDQuery     ;
      FQInsertTrigram        : TFDQuery     ;
      FQInsertRef            : TFDQuery     ;
      FQInsertCallEdge       : TFDQuery     ;
      FQDeleteFileSymbols    : TFDQuery     ;
      FQDeleteFileRefs       : TFDQuery     ;
      FQUpsertDiBinding          : TFDQuery     ;
      FQDeleteFileDiBindings     : TFDQuery     ;
      FQUpsertStringLiteral      : TFDQuery     ;
      FQDeleteFileStringLiterals : TFDQuery     ;
      FQFindByName           : TFDQuery     ;
      FQFindByQName          : TFDQuery     ;
      FQCountSymbols         : TFDQuery     ;
      FQCountFiles           : TFDQuery     ;
      FQUpsertSymbolDoc      : TFDQuery     ;
      FQDeleteFileDocs       : TFDQuery     ;
      FQGetSymbolDoc         : TFDQuery     ;
      FQFindByDocTag         : TFDQuery     ;
      FQFindUndocumented     : TFDQuery     ;
      FQFindByDocContains    : TFDQuery     ;
      FQListDocumentedSymbols: TFDQuery     ;
      FQFindContaining       : TFDQuery     ;
      FQFindFileId           : TFDQuery     ;
      FQFindChildByName      : TFDQuery     ;
      FQFindByPrefix         : TFDQuery     ;
      FQFindAllChildren      : TFDQuery     ;
      FQFindNoCallers        : TFDQuery     ;
      FQFindCompilerFindings : TFDQuery     ;
      FQInsertCompilerFinding: TFDQuery     ;
      FFts5Available         : Boolean     ; // set by Migrate; False when sqlite3.dll lacks fts5
      FReadOnly              : Boolean     ; // v0.86 Task 4: opened read-only (no DDL/writes)
      // v0.40.4: uses-clause persistence
      FQInsertUnitUse        : TFDQuery;
      FQDeleteFileUnitUses   : TFDQuery;
      FQGetFileUnitUses      : TFDQuery;
      FQFindUsersOfUnit      : TFDQuery;
      FQResolveUnitUseTargets: TFDQuery;
      procedure Connect(const ADbPath: string; AReadOnly: Boolean);
      procedure PrepareStatements;
      procedure EnsureTrigramTablePopulated;
      // v0.86 Task 4: read-only FTS5 detection -- does the string_fts virtual
      // table exist? (a SELECT on sqlite_master; issues no DDL). Used only on a
      // read-only open, where the write-path temp-table probe cannot run.
      function Fts5TableExists: Boolean;
    public
      /// <summary>Opens (or creates) the SQLite index at ADbPath.</summary>
      /// <param name="ADbPath">Full path to the .sqlite index file.</param>
      /// <param name="AReadOnly">When True the connection is opened
      ///  SQLITE_OPEN_READONLY and NO DDL/migration is performed: the caller must
      ///  NOT invoke Migrate or any Upsert/Delete/Insert method. Only the
      ///  read-safe init runs (connect + PrepareStatements), so query verbs never
      ///  issue DDL-on-read (which on a win32 sqlite3.dll silently DROPs the
      ///  string_literals sync triggers). Default False = today's write behavior,
      ///  byte-identical.</param>
      /// <remarks>Read-only callers should first check IsSchemaCurrent and emit
      ///  the actionable stale-schema message rather than run a query against a
      ///  pre-current schema. Not thread-safe; single owning thread only.</remarks>
      constructor Create(const ADbPath: string; AReadOnly: Boolean = False);
      destructor Destroy; override;

      procedure Migrate;

      /// <summary>Reads the stored schema_version and compares it to the engine's
      ///  SCHEMA_VERSION without mutating the DB (safe on a read-only open).</summary>
      /// <param name="AFound">Receives the DB's stored schema_version, or 0 when
      ///  the schema_meta row/table is absent (treated as pre-any-version).</param>
      /// <param name="AExpected">Receives SCHEMA_VERSION (the engine's current).</param>
      /// <returns>True when AFound &gt;= AExpected (current enough to read).</returns>
      function IsSchemaCurrent(out AFound, AExpected: Integer): Boolean;

      function FileIsUpToDate(const APath: string; AMtimeUnix: Int64; const ASha: string): Boolean                          ;
      function OpenFileTx(const APath: string; AMtimeUnix: Int64; const ASha: string; const ALanguage: string): TFileTxToken;
      function UpsertSymbol(const AToken: TFileTxToken; const ASymbol: TSymbol): Int64                                      ;
      procedure UpsertReference(const AToken: TFileTxToken; const ARef    : TReference   );
      procedure UpsertDiBinding(const AToken: TFileTxToken; const ABinding: TDiBindingRow);
      procedure DeleteDiBindingsForFile(AFileId: Int64);
      procedure UpsertStringLiteral(const AToken: TFileTxToken; const ALit: TStringLiteral);
      procedure DeleteStringLiteralsForFile(AFileId: Int64);
      function SearchText(const AQuery: string; AMode: string; const ASource: string; ALimit: Integer): TArray<TStringLitMatch>;
      // v14 (D5): resolved call-target edges (call_edges table).
      procedure UpsertCallEdge(const AToken: TFileTxToken; const AEdge: TCallEdge);
      procedure ClearCallEdges;
      function FindResolvedCallers(ATargetSymbolId: Int64): TArray<TResolvedCaller>;
      function FindUnresolvedNameCallers(const AName: string): TArray<TResolvedCaller>;
      function GetCallEdgesFromSymbol(AEnclosingSymbolId: Int64): TArray<TCallEdge>;
      function CountCallEdges: Int64;
      function PurgeLocals: Int64;
      function GetTypeCandidates: TArray<TSymbol>;
      function GetUnitScopeEdges: TArray<TFileScopeEdge>;
      function DumpAllCallEdges: TArray<TCallEdge>;
      function GetAmbiguousCalls(const AQName, AFilePath: string): TArray<TResolvedCaller>;
      function FindImplementationsOf( const AInterfaceName: string): TArray<TDiBindingRow>;
      function FindDiResolveSites   ( const AInterfaceName: string): TArray<TReference   >;
      function FindDiUnresolved: TArray<TReference>                                       ;
      function FindEventHandlersForForm( const AFormName: string): TArray<TReference>     ;
      procedure UpsertChunk(const AToken: TFileTxToken; const AChunk: TChunk);
      procedure CommitFileTx  (const AToken: TFileTxToken);
      procedure RollbackFileTx(const AToken: TFileTxToken);

      function FindSymbolsByExactName    (const AName : string): TArray<TSymbol>;
      function FindSymbolsByQualifiedName(const AQName: string): TArray<TSymbol>;
      function FindSymbolsByFile         (const APath : string): TArray<TSymbol>;
      function FindReferencesTo(ASymbolId: Int64): TArray<TReference>                        ;
      function FindCallersByName(const ACalleeName: string): TArray<TReference>              ;
      function FindSymbolsFuzzy(const APattern: string; ATopK: Integer = 10): TArray<TSymbol>;
      function GetFilePath(AFileId: Int64): string                                           ;
      function GetAllFileIds: TArray<Int64>                                                  ;
      function GetReferencesFromFile(AFileId: Int64): TArray<TReference>                     ;
      function CountSymbols   : Int64;
      function CountReferences: Int64;
      function CountFiles     : Int64;

      procedure UpsertSymbolDoc(const AToken: TFileTxToken; ASymbolId: Int64; const ADoc: TParsedDoc);
      function GetSymbolDoc(ASymbolId: Int64): TParsedDoc;

      // v0.40.4: uses-clause persistence + queries
      procedure UpsertUnitUse(const AToken: TFileTxToken; const AUse: TUnitUse);
      procedure DeleteUnitUsesForFile(AFileId: Int64);
      function GetUnitUsesForFile(AFileId: Int64): TArray<TUnitUse>          ;
      function FindUsersOfUnit(const AUnitNameNorm: string): TArray<TUnitUse>;
      procedure ResolveUnitUseTargets;
      // v11 (M1): type & hierarchy resolution (see ISymbolStore).
      procedure ResolveAncestry;
      // v14 (D5): whole-DB call-resolution pass (see ISymbolStore).
      procedure ResolveCallTargets;
      function GetTransitiveAncestors(ASymbolId: Int64): TArray<TTypeAncestor>;
      function IsDescendantOf(const AClassName, AAncestorName: string; AFileId: Int64): Boolean;
      function ImplementsInterface(const AClassName, AInterfaceName: string; AFileId: Int64): Boolean;
      function ResolveTypeCategory(const ATypeName: string; AFileId: Int64): TTypeCategory;
      function GetVirtualMethodsIncludingAncestors(const AClassName: string; AFileId: Int64): TArray<string>;

      { v0.40.4: leaf accessor for utilities that need raw SQL access
      (uses-report walks the whole files + unit_uses tables). Not part
      of ISymbolStore -- caller must know it's calling into the SQLite
      implementation. }
      function GetConnection: TFDConnection;

      function FindByDocTag(const ATag: string): TArray<TSymbol>                           ;
      function FindUndocumented(const AKind: string; APublicOnly: Boolean): TArray<TSymbol>;
      function FindByDocContains(const ASubstring: string): TArray<TSymbol>                ;
      procedure DeleteFileDocs(AFileId: Int64);

      // v0.18: bench-context
      function ListDocumentedSymbols(ALimit: Integer): TArray<TSymbol>;

      // v0.19: type-at-position helpers
      function FindContainingSymbol(AFileId: Int64; ALine: Integer): TSymbol        ;
      function GetSymbolById(AId: Int64): TSymbol                                   ;
      function FindFileIdByPath             (const APath: string): Int64;
      function FindSymbolByExactNameAnywhere(const AName: string): TSymbol;
      function FindChildSymbolByName(AParentId: Int64; const AName: string): TSymbol;

      // v0.20: completion helpers
      function FindSymbolsByPrefix(const APrefix: string; ALimit: Integer): TArray<TSymbol>;
      function FindAllChildSymbols(AParentId: Int64): TArray<TSymbol>                      ;

      // v0.25: dead-code finder
      function FindSymbolsWithNoCallers(const AKind: string; AIncludePrivate: Boolean): TArray<TSymbol>;

      // v0.26: compiler diagnostics
      function FindCompilerFindingsForFile(AFileId: Int64): TArray<TCompilerFinding>;
      procedure ClearCompilerFindings;
      procedure InsertCompilerFinding(const AFinding: TCompilerFinding);

      // v0.17: blast-radius pack
      function FindTransitiveCallers(const ASymbolName: string; ADepth: Integer): TArray<TImpactLevel>            ;
      function GetClassSurface(const AQName: string; AIncludeImpl, AAllVisibility: Boolean): TArray<TSurfaceLine> ;
      function GetSymbolSlice(const AQName: string): TArray<TSliceChunk>                                          ;
      function FindCallersByNameWithContext(const ACalleeName: string; AContextLines: Integer): TArray<TReference>;
    private
      // v0.42: path-tolerant file-id resolution for FindSymbolsByFile (outline)
      function ResolveFileIdTolerant(const APath: string): Int64;
      // v11 (M1): resolve a type name to its defining class/interface/record
      // symbol id, preferring a definition in AFileId. 0 if none.
      function ResolveTypeSymbolId(const AName: string; AFileId: Int64): Int64;
      // v11 (M1): depth-capped alias-chasing core of ResolveTypeCategory.
      function ResolveTypeCategoryDepth(const ATypeName: string; AFileId: Int64; ADepth: Integer): TTypeCategory;
      // v0.17 slice helpers
      function FindChildSymbols(AParentId: Int64): TArray<TSymbol>;
      // FindImplLine: searches ALines (0-based) for a line matching
      // "procedure|function|constructor|destructor ClassName.MethodName"
      // case-insensitively. Returns 0-based index, or -1 if not found.
      // NOTE: heuristic for v0.17 - may miss unusual formatting.
      class function FindImplLine(const ALines: TArray<string>; const APattern: string): Integer; static;
      // FindImplEnd: from AStartLine (0-based), scans forward to find the last
      // line of the implementation body. Stops at the next top-level
      // procedure/function/constructor/destructor/class procedure/class function
      // at column 0, or at a line ending 'end.' (unit footer). Returns 0-based
      // index of the last line included in the body.
      // NOTE: handles single-line "begin ... end;" bodies correctly.
      class function FindImplEnd(const ALines: TArray<string>; AStartLine: Integer): Integer; static;
  end;

implementation

uses
  System.Generics.Defaults
  , System.StrUtils
  , System.IOUtils
  , System.Math
  , DRagLint.Storage.Schema
  , DRagLint.Query  .Fuzzy
  , DRagLint.Index.CallResolver // v14 (D5): receiver-typing engine for ResolveCallTargets
  ;

{ TSQLiteSymbolStore }

constructor TSQLiteSymbolStore.Create(const ADbPath: string; AReadOnly: Boolean = False);
begin
  inherited Create;
  FReadOnly := AReadOnly;
  Connect(ADbPath, AReadOnly);
  { v0.86 Task 4: a read-only open still needs its SELECT queries built. In the
    write path PrepareStatements is Migrate's last step; read verbs never call
    Migrate, so build the statements here. PrepareStatements executes no SQL
    (FireDAC auto-prepares on first use) -- safe on a read-only connection. }
  if FReadOnly then
  begin
    { Only build the SELECT statements when the schema is current. On a pre-
      current DB some tables the queries reference may be absent, and the read
      verb will not run any query anyway -- it calls IsSchemaCurrent, sees False,
      prints the actionable stale-schema message, and exits. Preparing against a
      missing table would raise here (before the CLI can emit that message). }
    var RoFound, RoExpected: Integer;
    if IsSchemaCurrent(RoFound, RoExpected) then
    begin
      PrepareStatements;
      { The write path sets FFts5Available via a temp-table probe (a write). On a
        read-only open, detect FTS5 read-only: the string_fts virtual table
        exists in sqlite_master iff the index was built by an FTS5-capable
        engine. This lets SearchText (query --text) run; it never issues DDL. }
      FFts5Available := Fts5TableExists;
    end;
  end;
end;

function TSQLiteSymbolStore.Fts5TableExists: Boolean;
var
  Q: TFDQuery;
begin
  Result := False;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConn;
    Q.SQL.Text := 'SELECT 1 FROM sqlite_master ' +
                  'WHERE type = ''table'' AND name = ''string_fts'' LIMIT 1';
    try
      Q.Open;
      Result := not Q.IsEmpty;
    except
      Result := False;
    end;
  finally
    Q.Free;
  end;
end;

destructor TSQLiteSymbolStore.Destroy;
begin
  FQInsertFile.Free;
  FQUpsertFile.Free;
  FQInsertSymbol.Free;
  FQInsertTrigram.Free;
  FQInsertRef.Free;
  FQInsertCallEdge.Free;
  FQDeleteFileSymbols.Free;
  FQDeleteFileRefs.Free;
  FQUpsertDiBinding.Free;
  FQDeleteFileDiBindings.Free;
  FQUpsertStringLiteral.Free;
  FQDeleteFileStringLiterals.Free;
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
  FQListDocumentedSymbols.Free;
  FQFindContaining.Free;
  FQFindFileId.Free;
  FQFindChildByName.Free;
  FQFindByPrefix.Free;
  FQFindAllChildren.Free;
  FQFindNoCallers.Free;
  FQFindCompilerFindings.Free;
  FQInsertCompilerFinding.Free;
  FQInsertUnitUse.Free;
  FQDeleteFileUnitUses.Free;
  FQGetFileUnitUses.Free;
  FQFindUsersOfUnit.Free;
  FQResolveUnitUseTargets.Free;
  if Assigned(FConn) then
  begin
    if FConn.Connected then FConn.Close;
    FConn.Free;
  end;
  inherited;
end; // destructor

procedure TSQLiteSymbolStore.EnsureTrigramTablePopulated;
var
  CheckQ : TFDQuery      ;
  NameQ  : TFDQuery      ;
  InsertQ: TFDQuery      ;
  Grams  : TArray<string>;
  G      : string        ;
  SymId  : Int64         ;
  SymName: string        ;
begin
  { v0.86 Task 4: on a read-only open (query verbs' fuzzy fallback) the DB must
    not be written. A normally-indexed DB already has trigrams (populated in
    UpsertSymbol at index time), so the populate below is a no-op there; only a
    DB whose trigrams were never built would want it, and on a read-only handle
    the INSERT would fail. Skip it -- fuzzy simply matches fewer rows, never
    crashes. }
  if FReadOnly then Exit;
  // Check whether symbol_trigrams already has rows. If yes, we're good - the
  // table is kept in sync by triggers (next iteration); for now we just
  // populate-on-demand here. If empty, populate from symbols.
  CheckQ:= TFDQuery.Create(nil);
  try
    CheckQ.Connection:= FConn;
    CheckQ.SQL.Text:= 'SELECT 1 FROM symbol_trigrams LIMIT 1';
    CheckQ.Open;
    if not CheckQ.IsEmpty then Exit;
  finally
    CheckQ.Free;
  end;

  // Empty - build it. Per-batch transaction for speed.
  NameQ  := TFDQuery.Create(nil);
  InsertQ:= TFDQuery.Create(nil);
  try
    NameQ.Connection:= FConn;
    NameQ.SQL.Text:= 'SELECT id, name FROM symbols';
    NameQ.Open;
    InsertQ.Connection:= FConn;
    InsertQ.SQL.Text:= 'INSERT OR IGNORE INTO symbol_trigrams(trigram, symbol_id) ' + 'VALUES (:tg, :sid)';
    InsertQ.Params.ParamByName('tg' ).DataType:= ftString;
    InsertQ.Params.ParamByName('sid').DataType:= ftLargeint;
    FConn.StartTransaction;
    try
      while not NameQ.Eof do
      begin
        SymId  := NameQ.FieldByName('id'  ).AsLargeInt;
        SymName:= NameQ.FieldByName('name').AsString;
        Grams:= DRagLint.Query.Fuzzy.Trigrams(SymName);
        for G in Grams do
        begin
          InsertQ.ParamByName('tg' ).AsString  := G;
          InsertQ.ParamByName('sid').AsLargeInt:= SymId;
          InsertQ.ExecSQL;
        end;
        NameQ.Next;
      end;
      FConn.Commit;
    except
      FConn.Rollback;
      raise;
    end; // try
  finally
    NameQ.Free;
    InsertQ.Free;
  end; // try
end; // procedure

procedure TSQLiteSymbolStore.Connect(const ADbPath: string; AReadOnly: Boolean);
begin
  FConn:= TFDConnection.Create(nil);
  FConn.DriverName:= 'SQLite';
  FConn.Params.Values['Database'   ]:= ADbPath;
  if AReadOnly then
  begin
    { v0.86 Task 4: query verbs must never mutate the shared index. We do NOT use
      FireDAC OpenMode=ReadOnly (SQLITE_OPEN_READONLY): a WAL-mode DB cannot be
      opened that way without write access to its -shm wal-index file, which
      fails with "disk I/O error" (SQLite docs, wal.html: read-only WAL needs
      write privilege on -shm). Instead open with the SAME params as the write
      path -- so the -shm handling and WAL reads work normally -- then enforce
      no-writes with 'PRAGMA query_only = ON': every CREATE/DROP/INSERT/UPDATE/
      DELETE returns SQLITE_READONLY, so no DDL-on-read (no stamp, no FTS5 probe,
      no DROP TRIGGER) and no data change is possible. query_only is
      per-connection (does not disturb a concurrent LSP/writer). Journal mode is
      untouched, so the DB file's bytes are unchanged by a read verb. }
    FConn.Params.Values['LockingMode']:= 'Normal';
    FConn.Params.Values['JournalMode']:= 'WAL';
    FConn.Params.Values['Synchronous']:= 'Normal';
    FConn.LoginPrompt:= False;
    FConn.Connected  := True;
    FConn.ExecSQL('PRAGMA query_only = ON'); { reject every write on this handle }
    FConn.ExecSQL('PRAGMA busy_timeout = 5000');
    FConn.ExecSQL('PRAGMA cache_size = -262144'  ); { 256 MB page cache }
    FConn.ExecSQL('PRAGMA mmap_size = 1073741824'); { 1 GB read mmap }
    FConn.ExecSQL('PRAGMA temp_store = MEMORY'   );
    Exit;
  end;
  FConn.Params.Values['LockingMode']:= 'Normal';
  FConn.Params.Values['JournalMode']:= 'WAL';
  FConn.Params.Values['Synchronous']:= 'Normal';
  FConn.LoginPrompt:= False;
  FConn.Connected  := True;
  FConn.ExecSQL('PRAGMA foreign_keys = ON');
  { Give DDL ops (e.g. DROP TRIGGER) up to 5 s to acquire the exclusive WAL
    lock when a concurrent LSP reader holds the DB. Without this, any schema
    change races against the LSP server and silently fails (SQLITE_BUSY). }
  FConn.ExecSQL('PRAGMA busy_timeout = 5000');
  { v0.42 perf: per-file insert throughput collapses as the DB grows past ~1 GB
    (full C:\Projects scan ran at 0.55 s/file vs ~0.04 s/file historically). The
    cause is index B-tree maintenance (symbol_trigrams especially) thrashing
    against the default ~2 MB page cache. Give SQLite a large page cache + a
    big read mmap so the hot index pages stay resident instead of being
    re-read from disk on every insert; keep temp tables in memory. These are
    pure performance hints -- WAL + synchronous=Normal already guard durability. }
  FConn.ExecSQL('PRAGMA cache_size = -262144'  ); { 256 MB page cache }
  FConn.ExecSQL('PRAGMA mmap_size = 1073741824'); { 1 GB read mmap }
  FConn.ExecSQL('PRAGMA temp_store = MEMORY'   );
end;

procedure TSQLiteSymbolStore.Migrate;
var
  I: Integer;

  procedure TryExec(const ASql: string);
  begin
    { Idempotent ALTER: swallow the only expected failure ('duplicate column'
      on a fresh DB whose CREATE TABLE already added the column). }
    try FConn.ExecSQL(ASql); except end;
  end;

  procedure DropTriggerVerbose(const AName: string);
  begin
    try
      FConn.ExecSQL('DROP TRIGGER IF EXISTS ' + AName);
      Writeln('  DROP TRIGGER ', AName, ': OK');
    except on E: Exception do
      Writeln('  DROP TRIGGER ', AName, ': FAILED (', E.ClassName, ': ', E.Message, ')');
    end;
  end;

  function ProbeFts5: Boolean;
  begin
    { Use a TEMP virtual table as the probe so the result is independent of
      what tables already exist in the main DB. CREATE VIRTUAL TABLE IF NOT
      EXISTS on string_fts would short-circuit silently when the table already
      exists from a prior fts5-capable index run, masking the unavailability
      of the module on this SQLite build. }
    Result := True;
    try
      FConn.ExecSQL('CREATE VIRTUAL TABLE IF NOT EXISTS temp.fts5_probe USING fts5(x)');
      TryExec('DROP TABLE IF EXISTS temp.fts5_probe');
      Writeln(ErrOutput, '  FTS5 probe: AVAILABLE');
    except on E: Exception do
      if Pos('fts5', LowerCase(E.Message)) > 0 then
      begin
        Result := False;
        Writeln(ErrOutput, '  FTS5 probe: UNAVAILABLE (', E.Message, ')');
      end
      else
        raise;
    end;
  end;

  procedure PrintTriggerCount(const ALabel: string);
  var Q: TFDQuery;
  begin
    try
      Q := TFDQuery.Create(nil);
      try
        Q.Connection := FConn;
        Q.SQL.Text := 'SELECT COUNT(*) FROM sqlite_master ' +
                      'WHERE type=''trigger'' AND name LIKE ''string_literals%''';
        Q.Open;
        Writeln('  ', ALabel, ': ', Q.Fields[0].AsInteger);
      finally
        Q.Free;
      end;
    except on E: Exception do
      Writeln('  ', ALabel, ': query failed (', E.Message, ')');
    end;
  end;

begin
  FConn.StartTransaction;
  try
    // Core schema (no FTS5): required; any failure aborts the migration.
    for I := 0 to SCHEMA_DDL_FTS5_FIRST - 1 do FConn.ExecSQL(SCHEMA_DDL[I]);
    FConn.ExecSQL( 'INSERT OR REPLACE INTO schema_meta(key, value) VALUES (''schema_version'', ?)', [IntToStr(SCHEMA_VERSION)]);
    FConn.Commit;
  except
    FConn.Rollback;
    raise;
  end;
  { FTS5 virtual tables and sync triggers -- optional.
    Probe via a temp virtual table (bypasses IF NOT EXISTS masking when
    string_fts already exists from a prior fts5-capable index run).
    If unavailable: drop any leftover sync triggers so INSERTs into
    string_literals do not fire them and crash. }
  FFts5Available := ProbeFts5;
  if FFts5Available then
  begin
    for I := SCHEMA_DDL_FTS5_FIRST to High(SCHEMA_DDL) do TryExec(SCHEMA_DDL[I]);
  end
  else
  begin
    { Drop sync triggers so the string_literals ON DELETE CASCADE (fired when
      FQUpsertFile's ON CONFLICT DO UPDATE replaces a row, or when files are
      removed) cannot reach the fts5 tables. busy_timeout (set in Connect)
      gives each DROP up to 5 s to acquire the exclusive WAL lock against a
      concurrent LSP reader. }
    PrintTriggerCount('string_literals triggers before DROP');
    DropTriggerVerbose('string_literals_ai');
    DropTriggerVerbose('string_literals_ad');
    DropTriggerVerbose('string_literals_au');
    PrintTriggerCount('string_literals triggers after DROP');
    Writeln('WARNING: FTS5 unavailable in sqlite3.dll; ' +
            'text-search index (string_literals) will not be updated.');
  end;
  { v9: additive body-span columns for pre-v9 symbols tables. CREATE TABLE IF
    NOT EXISTS never adds columns to an existing table, so ALTER explicitly
    (after the commit so a swallowed duplicate-column error can't disturb the
    main schema transaction). }
  TryExec('ALTER TABLE symbols ADD COLUMN impl_start_line INTEGER');
  TryExec('ALTER TABLE symbols ADD COLUMN impl_end_line INTEGER'  );
  { v11 (M1): raw ancestor list text on class/interface symbols. Additive
    column; ALTER onto pre-v11 tables for the same reason as the v9 columns. }
  TryExec('ALTER TABLE symbols ADD COLUMN heritage TEXT');
  { v12 (M1): per-method virtual-dispatch flag (virtual/dynamic/override). }
  TryExec('ALTER TABLE symbols ADD COLUMN is_virtual INTEGER');
  { v13 (v0.82): per-ref enclosing-routine attribution. Additive column; ALTER
    onto pre-v13 refs tables for the same reason as the v9 body-span columns.
    Populated per-file in IndexFile; NULL when the ref is in no routine body.
    v0.83.1: this is the SOLE creation site of idx_refs_enclosing -- it must
    run after the ALTER. In SCHEMA_DDL (before the ALTER) it aborted the whole
    migration on every pre-v13 DB with "no such column: enclosing_symbol_id". }
  TryExec('ALTER TABLE refs ADD COLUMN enclosing_symbol_id INTEGER');
  TryExec('CREATE INDEX IF NOT EXISTS idx_refs_enclosing ON refs(enclosing_symbol_id)');
  { v11 (M1): direct ancestor edges (one row per heritage entry). Created here
    rather than in SCHEMA_DDL to avoid renumbering the FTS5 split index; it is
    plain DDL that must always exist (independent of FTS5 availability).
    ancestor_symbol_id NULL = unresolved (external/RTL/by-name only). The
    ON DELETE CASCADE clears a symbol's edges when its file is re-indexed;
    ResolveAncestry rebuilds the whole table each run. }
  TryExec('CREATE TABLE IF NOT EXISTS type_ancestors (' +
          '  symbol_id          INTEGER NOT NULL REFERENCES symbols(id) ON DELETE CASCADE,' +
          '  ordinal            INTEGER NOT NULL,' +
          '  ancestor_name      TEXT NOT NULL,' +
          '  ancestor_kind      TEXT,' +
          '  ancestor_symbol_id INTEGER,' +
          '  ancestor_file_id   INTEGER)');
  TryExec('CREATE INDEX IF NOT EXISTS idx_type_ancestors_symbol ON type_ancestors(symbol_id)');
  TryExec('CREATE INDEX IF NOT EXISTS idx_type_ancestors_name   ON type_ancestors(ancestor_name)');
  PrepareStatements;
end; // begin

function TSQLiteSymbolStore.IsSchemaCurrent(out AFound, AExpected: Integer): Boolean;
var
  Q: TFDQuery;
begin
  { Read-only, no-DDL schema probe. schema_meta always exists on any real index
    (it is SCHEMA_DDL[0]); a missing table/row is treated as 0 (pre-any-version)
    so a read verb reports the stale-schema message instead of a field error. }
  AExpected := SCHEMA_VERSION;
  AFound    := 0;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConn;
    Q.SQL.Text := 'SELECT value FROM schema_meta WHERE key = ''schema_version'' LIMIT 1';
    try
      Q.Open;
      if not Q.IsEmpty then AFound := StrToIntDef(Q.Fields[0].AsString, 0);
    except
      { table absent (pre-schema_meta DB) -> leave AFound = 0. }
      AFound := 0;
    end;
  finally
    Q.Free;
  end;
  Result := AFound >= AExpected;
end;

procedure TSQLiteSymbolStore.PrepareStatements;
  function NewQuery(const ASql: string): TFDQuery;
  begin
    Result:= TFDQuery.Create(nil);
    Result.Connection:= FConn;
    Result.SQL.Text:= ASql;
    // SQL.Text only -- no .Prepare here. FireDAC auto-prepares on first use, and
    // preparing/compiling a statement steps nothing, so building these query
    // objects is safe on a read-only (query_only) handle. Param types are
    // inferred from the first set of param values.
  end;
begin
  // v0.59.4: two-query upsert: UPDATE existing row, INSERT OR IGNORE for new files.
  // INSERT OR REPLACE deletes + re-inserts, which cascades to string_literals
  // and fires the FTS5 sync triggers even when FFts5Available=False. UPDATE
  // modifies the row in-place (no DELETE, no CASCADE, no trigger). File id is
  // preserved so FK children remain valid. INSERT OR IGNORE is safe because this
  // path is only reached when no row exists for the given path.
  // ON CONFLICT DO UPDATE is avoided -- Win32 Embarcadero sqlite3.dll is older
  // than 3.24 and rejects that syntax with "near ON: syntax error".
  FQUpsertFile:= NewQuery( 'UPDATE files SET mtime_unix=:mtime, sha256=:sha, ' +
    'parsed_at=:parsed, language=:lang WHERE path=:path');
  FQInsertFile:= NewQuery( 'INSERT OR IGNORE INTO files(path, mtime_unix, sha256, parsed_at, language) ' + 'VALUES (:path, :mtime, :sha, :parsed, :lang)');
  FQInsertSymbol:= NewQuery(
    'INSERT INTO symbols(file_id, parent_id, kind, name, qualified_name, ' + '  signature, modifiers, section, heritage, is_virtual, start_line, start_col, end_line, end_col, ' +
    '  impl_start_line, impl_end_line) ' + 'VALUES (:fid, :pid, :kind, :name, :qname, :sig, :mods, :sec, :her, :virt, ' + '  :sl, :sc, :el, :ec, :isl, :iel)');
  FQInsertTrigram:= NewQuery( 'INSERT OR IGNORE INTO symbol_trigrams(trigram, symbol_id) ' + 'VALUES (:tg, :sid)');
  FQInsertRef:= NewQuery(
    'INSERT INTO refs(symbol_id, file_id, kind, name_text, ' + '  start_line, start_col, end_line, end_col, enclosing_symbol_id) ' +
    'VALUES (:sid, :fid, :kind, :name, :sl, :sc, :el, :ec, :esid)');
  FQInsertCallEdge:= NewQuery(
    'INSERT OR REPLACE INTO call_edges(ref_id, target_symbol_id, confidence, receiver_type_symbol_id) ' +
    'VALUES (:rid, :tid, :conf, :rtid)');
  FQDeleteFileSymbols:= NewQuery('DELETE FROM symbols WHERE file_id = :fid');
  FQDeleteFileRefs   := NewQuery('DELETE FROM refs WHERE file_id = :fid'   );
  FQUpsertDiBinding:= NewQuery(
    'INSERT INTO di_bindings(file_id, interface_name, impl_name, lifetime, ' + '  start_line, start_col, end_line, end_col) ' +
    'VALUES (:fid, :intf, :impl, :life, :sl, :sc, :el, :ec)');
  FQDeleteFileDiBindings:= NewQuery( 'DELETE FROM di_bindings WHERE file_id = :fid'                    );
  FQUpsertStringLiteral:= NewQuery(
    'INSERT INTO string_literals(file_id, symbol_id, source, kind, owner_name, text, ' +
    '  start_line, start_col, end_line, end_col) ' +
    'VALUES (:fid, :sid, :src, :kind, :owner, :txt, :sl, :sc, :el, :ec)');
  FQDeleteFileStringLiterals:= NewQuery('DELETE FROM string_literals WHERE file_id = :fid');
  FQFindByName          := NewQuery( 'SELECT * FROM symbols WHERE name = :name ORDER BY qualified_name');
  FQFindByQName         := NewQuery( 'SELECT * FROM symbols WHERE qualified_name = :qname'             );
  FQCountSymbols        := NewQuery('SELECT COUNT(*) AS n FROM symbols'                                );
  FQCountFiles          := NewQuery('SELECT COUNT(*) AS n FROM files'                                  );

  FQUpsertSymbolDoc:= NewQuery(
    'INSERT OR REPLACE INTO symbol_docs ' + '(symbol_id, format, raw_block, summary, remarks, returns_text, ' +
    ' params_json, exceptions_json, example_text, seealso_json, since_text, ' + ' deprecated, start_line, end_line) ' +
    'VALUES (:sid, :fmt, :raw, :sum, :rem, :ret, :pj, :ej, :ex, :sj, :since, ' + ' :dep, :sl, :el)');
  // Pre-declare all param types before the first Prepare/Execute so FireDAC
  // does not re-infer types from run-time values. Without this, a param that
  // is NULL on one call and non-NULL on another raises [SQLite]-338.
  FQUpsertSymbolDoc.Params.ParamByName('sid'  ).DataType:= ftLargeint;
  FQUpsertSymbolDoc.Params.ParamByName('fmt'  ).DataType:= ftString;
  FQUpsertSymbolDoc.Params.ParamByName('raw'  ).DataType:= ftString;
  FQUpsertSymbolDoc.Params.ParamByName('sum'  ).DataType:= ftWideMemo;
  FQUpsertSymbolDoc.Params.ParamByName('rem'  ).DataType:= ftWideMemo;
  FQUpsertSymbolDoc.Params.ParamByName('ret'  ).DataType:= ftWideMemo;
  FQUpsertSymbolDoc.Params.ParamByName('pj'   ).DataType:= ftWideMemo;
  FQUpsertSymbolDoc.Params.ParamByName('ej'   ).DataType:= ftWideMemo;
  FQUpsertSymbolDoc.Params.ParamByName('ex'   ).DataType:= ftWideMemo;
  FQUpsertSymbolDoc.Params.ParamByName('sj'   ).DataType:= ftWideMemo;
  FQUpsertSymbolDoc.Params.ParamByName('since').DataType:= ftWideMemo;
  FQUpsertSymbolDoc.Params.ParamByName('dep'  ).DataType:= ftInteger;
  FQUpsertSymbolDoc.Params.ParamByName('sl'   ).DataType:= ftInteger;
  FQUpsertSymbolDoc.Params.ParamByName('el'   ).DataType:= ftInteger;
  FQUpsertSymbolDoc.Prepare;

  FQDeleteFileDocs:= NewQuery( 'DELETE FROM symbol_docs WHERE symbol_id IN ' + '(SELECT id FROM symbols WHERE file_id = :fid)');

  FQGetSymbolDoc:= NewQuery(
    'SELECT format, raw_block, summary, remarks, returns_text, ' + ' params_json, exceptions_json, example_text, seealso_json, since_text, ' +
    ' deprecated, start_line, end_line ' + 'FROM symbol_docs WHERE symbol_id = :sid');

  FQFindByDocTag:= NewQuery(
    'SELECT s.* FROM symbols s INNER JOIN symbol_docs d ON d.symbol_id = s.id ' + 'WHERE (:tag = ''deprecated'' AND d.deprecated = 1) ' +
    '   OR (:tag = ''since'' AND d.since_text IS NOT NULL)');

  FQFindUndocumented:= NewQuery(
    'SELECT s.* FROM symbols s ' + 'LEFT JOIN symbol_docs d ON d.symbol_id = s.id ' + 'WHERE d.symbol_id IS NULL ' + '  AND (:kind = '''' OR s.kind = :kind) ' +
    '  AND (:publicOnly = 0 OR (s.modifiers IS NULL ' + '       OR (s.modifiers NOT LIKE ''%private%'' AND ' + '           s.modifiers NOT LIKE ''%protected%'')))');

  FQFindByDocContains:= NewQuery(
    'SELECT s.* FROM symbols s INNER JOIN symbol_docs d ON d.symbol_id = s.id ' + 'WHERE d.summary LIKE :pat OR d.remarks LIKE :pat OR d.example_text LIKE :pat');

  FQListDocumentedSymbols:= NewQuery( 'SELECT s.* FROM symbols s ' + 'INNER JOIN symbol_docs d ON d.symbol_id = s.id ' + 'WHERE d.summary IS NOT NULL ' + 'LIMIT :lim');

  FQFindContaining:= NewQuery( 'SELECT * FROM symbols ' + 'WHERE file_id = :fid AND start_line <= :line AND end_line >= :line ' + 'ORDER BY start_line DESC LIMIT 1');

  FQFindFileId:= NewQuery( 'SELECT id FROM files ' + 'WHERE path = :p OR LOWER(path) = LOWER(:p) LIMIT 1');

  FQFindChildByName:= NewQuery( 'SELECT * FROM symbols WHERE parent_id = :pid AND name = :name LIMIT 1');

  // v0.20: completion helpers
  // LIKE pattern: escape _ and % in user input, then append %.
  // SQLite LIKE is case-insensitive for ASCII by default.
  FQFindByPrefix:= NewQuery( 'SELECT * FROM symbols WHERE name LIKE :prefixLike ORDER BY name LIMIT :lim');

  FQFindAllChildren:= NewQuery( 'SELECT * FROM symbols WHERE parent_id = :pid ORDER BY start_line');

  // v0.25: dead-code finder - symbols with no entry in refs.name_text
  FQFindNoCallers:= NewQuery(
    'SELECT s.* FROM symbols s ' + 'LEFT JOIN refs r ON r.name_text = s.name ' + 'WHERE r.id IS NULL ' + '  AND (:kind = '''' OR s.kind = :kind) ' +
    '  AND s.name NOT IN (''Main'', ''Register'', ''initialization'', ''finalization'') ' + '  AND s.kind NOT IN (''constructor'', ''destructor'') ' +
    '  AND (:includePrivate = 1 OR (s.modifiers IS NULL ' + '       OR s.modifiers NOT LIKE ''%private%''))');

  // v0.26: compiler findings helpers
  FQFindCompilerFindings:= NewQuery(
    'SELECT file_id, raw_path, code, severity, line_no, col_no, message ' + 'FROM compiler_findings ' + 'WHERE file_id = :fid ORDER BY line_no, col_no');

  FQInsertCompilerFinding:= NewQuery(
    'INSERT INTO compiler_findings ' + '(file_id, raw_path, code, severity, line_no, col_no, message, imported_at) ' + 'VALUES (:fid, :rp, :code, :sev, :lno, :cno, :msg, :iat)');
  FQInsertCompilerFinding.Params.ParamByName('fid' ).DataType:= ftLargeint;
  FQInsertCompilerFinding.Params.ParamByName('rp'  ).DataType:= ftString;
  FQInsertCompilerFinding.Params.ParamByName('code').DataType:= ftString;
  FQInsertCompilerFinding.Params.ParamByName('sev' ).DataType:= ftString;
  FQInsertCompilerFinding.Params.ParamByName('lno' ).DataType:= ftInteger;
  FQInsertCompilerFinding.Params.ParamByName('cno' ).DataType:= ftInteger;
  FQInsertCompilerFinding.Params.ParamByName('msg' ).DataType:= ftString;
  FQInsertCompilerFinding.Params.ParamByName('iat' ).DataType:= ftLargeint;
  FQInsertCompilerFinding.Prepare;

  // v0.40.4: uses-clause queries
  FQInsertUnitUse:= NewQuery(
    'INSERT INTO unit_uses ' + '(file_id, unit_name, unit_name_norm, section, in_path, ' + ' target_file_id, start_line, start_col, end_line, end_col) ' +
    'VALUES (:fid, :un, :unn, :sec, :inp, NULL, :sl, :sc, :el, :ec)');
  FQInsertUnitUse.Params.ParamByName('fid').DataType:= ftLargeint;
  FQInsertUnitUse.Params.ParamByName('un' ).DataType:= ftString;
  FQInsertUnitUse.Params.ParamByName('unn').DataType:= ftString;
  FQInsertUnitUse.Params.ParamByName('sec').DataType:= ftString;
  FQInsertUnitUse.Params.ParamByName('inp').DataType:= ftString;
  FQInsertUnitUse.Params.ParamByName('sl' ).DataType:= ftInteger;
  FQInsertUnitUse.Params.ParamByName('sc' ).DataType:= ftInteger;
  FQInsertUnitUse.Params.ParamByName('el' ).DataType:= ftInteger;
  FQInsertUnitUse.Params.ParamByName('ec' ).DataType:= ftInteger;
  FQInsertUnitUse.Prepare;

  FQDeleteFileUnitUses:= NewQuery( 'DELETE FROM unit_uses WHERE file_id = :fid');
  FQDeleteFileUnitUses.Params.ParamByName('fid').DataType:= ftLargeint;
  FQDeleteFileUnitUses.Prepare;

  FQGetFileUnitUses:= NewQuery(
    'SELECT unit_name, unit_name_norm, section, in_path, ' + '       target_file_id, start_line, start_col, end_line, end_col ' + 'FROM unit_uses WHERE file_id = :fid ' +
    'ORDER BY section, start_line, start_col');
  FQGetFileUnitUses.Params.ParamByName('fid').DataType:= ftLargeint;
  FQGetFileUnitUses.Prepare;

  FQFindUsersOfUnit:= NewQuery(
    'SELECT file_id, unit_name, unit_name_norm, section, in_path, ' + '       target_file_id, start_line, start_col, end_line, end_col ' +
    'FROM unit_uses WHERE unit_name_norm = :un');
  FQFindUsersOfUnit.Params.ParamByName('un').DataType:= ftString;
  FQFindUsersOfUnit.Prepare;

  // Resolves target_file_id for every unit_uses row whose unit_name_norm
  // matches the lower-cased basename (stem) of some files.path entry.
  // Run once after a full index pass; safe to re-run (UPDATE is idempotent).
  // Uses LOWER + substr math because sqlite's basename trick (replace ext)
  // would over-match. Path separators normalised to '/'.
  FQResolveUnitUseTargets:= NewQuery(
    'UPDATE unit_uses SET target_file_id = (' + '  SELECT f.id FROM files f ' + '  WHERE LOWER(' + '    REPLACE(' + '      SUBSTR(' +
    '        SUBSTR(f.path, 1 + LENGTH(f.path) - INSTR(' + '          REPLACE(REPLACE(f.path, ''\'', ''/''), ''/'', '''') || ''/'',' + '          ''/'')), 1)' +
    '      , ''.pas'', '''')' + '  ) = unit_uses.unit_name_norm ' + '  LIMIT 1) ' + 'WHERE target_file_id IS NULL');
  FQResolveUnitUseTargets.Prepare;
end; // begin

function TSQLiteSymbolStore.GetAllFileIds: TArray<Int64>;
var
  Q: TFDQuery    ;
  L: TList<Int64>;
begin
  L:= TList<Int64>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT id FROM files ORDER BY id';
    Q.Open;
    while not Q.Eof do
    begin
      L.Add(Q.FieldByName('id').AsLargeInt);
      Q.Next;
    end;
    Result:= L.ToArray;
  finally
    Q.Free;
    L.Free;
  end;
end; // function

function TSQLiteSymbolStore.FileIsUpToDate(const APath: string; AMtimeUnix: Int64; const ASha: string): Boolean;
var
  Q: TFDQuery;
begin
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT 1 FROM files WHERE path = :p AND mtime_unix = :m ' + 'AND sha256 = :s';
    { match the canonical stored form (see NormalizeStoredPath) }
    Q.ParamByName('p').AsString:= StringReplace(APath, '/', '\', [rfReplaceAll]);
    Q.ParamByName('m').AsLargeInt:= AMtimeUnix;
    Q.ParamByName('s').AsString  := ASha;
    Q.Open;
    Result:= not Q.IsEmpty;
  finally
    Q.Free;
  end;
end; // function

// v0.43: canonical stored-path form. The walker can produce mixed separators
// ('C:/root\sub\file.pas') when the index root is given with '/', which made
// re-indexing INSERT a duplicate files row (path is UNIQUE, so the differently-
// spelled path didn't REPLACE) and left stale unit_uses/refs behind. Collapse
// every spelling to one canonical all-backslash path at the store boundary.
function NormalizeStoredPath(const APath: string): string;
begin
  Result:= StringReplace(APath, '/', '\', [rfReplaceAll]);
end;

function TSQLiteSymbolStore.OpenFileTx(const APath: string; AMtimeUnix: Int64; const ASha: string; const ALanguage: string): TFileTxToken;
var
  Q : TFDQuery;
  NP: string  ;
begin
  NP:= NormalizeStoredPath(APath);
  FConn.StartTransaction;
  try
    { UPDATE existing row in-place (no DELETE -- no cascade -- no FTS5 trigger).
      If no row exists yet (new file) fall through to INSERT OR IGNORE. }
    FQUpsertFile.ParamByName('path'  ).AsString   := NP;
    FQUpsertFile.ParamByName('mtime' ).AsLargeInt := AMtimeUnix;
    FQUpsertFile.ParamByName('sha'   ).AsString   := ASha;
    FQUpsertFile.ParamByName('parsed').AsLargeInt := DateTimeToUnix(Now, False);
    FQUpsertFile.ParamByName('lang'  ).AsString   := ALanguage;
    FQUpsertFile.ExecSQL;
    if FQUpsertFile.RowsAffected = 0 then
    begin
      FQInsertFile.ParamByName('path'  ).AsString   := NP;
      FQInsertFile.ParamByName('mtime' ).AsLargeInt := AMtimeUnix;
      FQInsertFile.ParamByName('sha'   ).AsString   := ASha;
      FQInsertFile.ParamByName('parsed').AsLargeInt := DateTimeToUnix(Now, False);
      FQInsertFile.ParamByName('lang'  ).AsString   := ALanguage;
      FQInsertFile.ExecSQL;
    end;

    Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= FConn;
      Q.SQL.Text:= 'SELECT id FROM files WHERE path = :path';
      Q.ParamByName('path').AsString:= NP;
      Q.Open;
      if Q.IsEmpty then raise Exception.CreateFmt('File row not found after upsert: %s', [NP]);
      Result.FileId:= Q.Fields[0].AsLargeInt;
      Result.Path:= NP;
    finally
      Q.Free;
    end;

    // Phase 1: full re-emit semantics. Clear old symbols/refs for this file
    // before the caller starts emitting fresh records.
    FQDeleteFileRefs.ParamByName('fid').AsLargeInt:= Result.FileId;
    FQDeleteFileRefs.ExecSQL;
    FQDeleteFileDiBindings.ParamByName('fid').AsLargeInt:= Result.FileId;
    FQDeleteFileDiBindings.ExecSQL;
    FQDeleteFileSymbols.ParamByName('fid').AsLargeInt:= Result.FileId;
    FQDeleteFileSymbols.ExecSQL;
  except
    FConn.Rollback;
    raise;
  end; // try
end; // function

function TSQLiteSymbolStore.UpsertSymbol(const AToken: TFileTxToken; const ASymbol: TSymbol): Int64;
begin
  FQInsertSymbol.ParamByName('fid').AsLargeInt:= AToken.FileId;
  FQInsertSymbol.ParamByName('pid').DataType:= ftLargeint;
  if ASymbol.ParentId >= 0 then FQInsertSymbol.ParamByName('pid').AsLargeInt:= ASymbol.ParentId
  else FQInsertSymbol.ParamByName('pid').Clear;
  FQInsertSymbol.ParamByName('kind').AsString:= ASymbol.Kind.ToText;
  FQInsertSymbol.ParamByName('name' ).AsString := ASymbol.Name;
  FQInsertSymbol.ParamByName('qname').AsString := ASymbol.QualifiedName;
  FQInsertSymbol.ParamByName('sig'  ).AsString := ASymbol.Signature;
  FQInsertSymbol.ParamByName('mods' ).AsString := ASymbol.Modifiers;
  FQInsertSymbol.ParamByName('sec'  ).AsString := ASymbol.Section;
  { v11: NULL when no ancestors so non-class/interface rows stay clean. }
  FQInsertSymbol.ParamByName('her'  ).DataType := ftString;
  if ASymbol.Heritage <> '' then FQInsertSymbol.ParamByName('her').AsString:= ASymbol.Heritage
  else FQInsertSymbol.ParamByName('her').Clear;
  FQInsertSymbol.ParamByName('virt' ).AsInteger:= Ord(ASymbol.IsVirtual); { v12 }
  FQInsertSymbol.ParamByName('sl'   ).AsInteger:= ASymbol.StartLine;
  FQInsertSymbol.ParamByName('sc'   ).AsInteger:= ASymbol.StartCol;
  FQInsertSymbol.ParamByName('el'   ).AsInteger:= ASymbol.EndLine;
  FQInsertSymbol.ParamByName('ec'   ).AsInteger:= ASymbol.EndCol;
  FQInsertSymbol.ParamByName('isl'  ).AsInteger:= ASymbol.ImplStartLine; { v9 }
  FQInsertSymbol.ParamByName('iel'  ).AsInteger:= ASymbol.ImplEndLine; { v9 }
  FQInsertSymbol.ExecSQL;
  Result:= FConn.GetLastAutoGenValue('');
  // Populate trigram index alongside each symbol insert so fuzzy queries
  // are sub-second from the first call without any lazy build cost.
  var Grams:= DRagLint.Query.Fuzzy.Trigrams(ASymbol.Name);
  var G: string;
  for G in Grams do
  begin
    FQInsertTrigram.ParamByName('tg' ).AsString  := G;
    FQInsertTrigram.ParamByName('sid').AsLargeInt:= Result;
    FQInsertTrigram.ExecSQL;
  end;
end; // function

procedure TSQLiteSymbolStore.UpsertReference(const AToken: TFileTxToken; const ARef: TReference);
begin
  FQInsertRef.ParamByName('sid').DataType:= ftLargeint;
  if ARef.SymbolId > 0 then FQInsertRef.ParamByName('sid').AsLargeInt:= ARef.SymbolId
  else FQInsertRef.ParamByName('sid').Clear;
  FQInsertRef.ParamByName('fid' ).AsLargeInt:= AToken.FileId;
  FQInsertRef.ParamByName('kind').AsString  := ARef  .Kind;
  FQInsertRef.ParamByName('name').AsString  := ARef  .NameText;
  FQInsertRef.ParamByName('sl'  ).AsInteger := ARef  .StartLine;
  FQInsertRef.ParamByName('sc'  ).AsInteger := ARef  .StartCol;
  FQInsertRef.ParamByName('el'  ).AsInteger := ARef  .EndLine;
  FQInsertRef.ParamByName('ec'  ).AsInteger := ARef  .EndCol;
  { v13 (v0.82): enclosing routine id; NULL when the ref is in no routine body. }
  FQInsertRef.ParamByName('esid').DataType:= ftLargeint;
  if ARef.EnclosingSymbolId > 0 then FQInsertRef.ParamByName('esid').AsLargeInt:= ARef.EnclosingSymbolId
  else FQInsertRef.ParamByName('esid').Clear;
  FQInsertRef.ExecSQL;
end;

procedure TSQLiteSymbolStore.UpsertCallEdge(const AToken: TFileTxToken; const AEdge: TCallEdge);
begin
  FQInsertCallEdge.ParamByName('rid' ).AsLargeInt:= AEdge.RefId;
  FQInsertCallEdge.ParamByName('tid' ).AsLargeInt:= AEdge.TargetSymbolId;
  FQInsertCallEdge.ParamByName('conf').AsString  := AEdge.Confidence;
  { receiver_type_symbol_id is nullable (ON DELETE SET NULL); NULL it when unknown. }
  FQInsertCallEdge.ParamByName('rtid').DataType:= ftLargeint;
  if AEdge.ReceiverTypeSymbolId > 0 then FQInsertCallEdge.ParamByName('rtid').AsLargeInt:= AEdge.ReceiverTypeSymbolId
  else FQInsertCallEdge.ParamByName('rtid').Clear;
  FQInsertCallEdge.ExecSQL;
end;

procedure TSQLiteSymbolStore.ClearCallEdges;
begin
  FConn.ExecSQL('DELETE FROM call_edges');
end;

function TSQLiteSymbolStore.FindResolvedCallers(ATargetSymbolId: Int64): TArray<TResolvedCaller>;
var
  Q   : TFDQuery              ;
  List: TList<TResolvedCaller>;
  R   : TResolvedCaller       ;
begin
  List:= TList<TResolvedCaller>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:=
      'SELECT r.enclosing_symbol_id, s.qualified_name AS encl_qname, f.path AS file_path, r.start_line, ce.confidence ' +
      'FROM call_edges ce ' +
      'JOIN refs r ON r.id = ce.ref_id ' +
      'LEFT JOIN symbols s ON s.id = r.enclosing_symbol_id ' +
      'JOIN files f ON f.id = r.file_id ' +
      'WHERE ce.target_symbol_id = :x ' +
      // D5 fast-follow (T7): confidence is TEXT ('certain' | 'ambiguous'), and a
      // plain 'ORDER BY ce.confidence DESC' only puts 'certain' first because
      // 'c' > 'a' lexically -- an accident of English spelling, not an intended
      // ordinal. An explicit CASE mapping makes the ordering a deliberate choice:
      // 'certain' callers must sort before 'ambiguous' ones. If a THIRD confidence
      // value is ever introduced, it must be slotted into this CASE on purpose --
      // it will otherwise fall into the ELSE bucket (sorted last, alongside
      // 'ambiguous') rather than silently reordering the existing two.
      'ORDER BY CASE ce.confidence WHEN ''certain'' THEN 0 ELSE 1 END, s.qualified_name';
    Q.ParamByName('x').AsLargeInt:= ATargetSymbolId;
    Q.Open;
    while not Q.Eof do
    begin
      R:= Default(TResolvedCaller);
      if Q.FieldByName('enclosing_symbol_id').IsNull then R.EnclosingSymbolId:= 0
      else R.EnclosingSymbolId:= Q.FieldByName('enclosing_symbol_id').AsLargeInt;
      if Q.FieldByName('encl_qname').IsNull then R.EnclosingQName:= ''
      else R.EnclosingQName:= Q.FieldByName('encl_qname').AsString;
      R.Location  := ExtractFileName(Q.FieldByName('file_path').AsString);
      R.Confidence:= Q.FieldByName('confidence').AsString;
      List.Add(R);
      Q.Next;
    end; // while
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end; // try
end; // function

/// <summary>v14 (D5): the AutoDocument '?' bucket -- name-matching refs with NO
/// call_edges row (untypable receiver). Ordered by file path then start line to
/// mirror FindCallersByName's first-seen ordering. Each row -> a TResolvedCaller
/// with Confidence 'unverified'; Location is file-name-only; EnclosingQName is ''
/// when the ref has no enclosing routine.</summary>
function TSQLiteSymbolStore.FindUnresolvedNameCallers(const AName: string): TArray<TResolvedCaller>;
var
  Q   : TFDQuery              ;
  List: TList<TResolvedCaller>;
  R   : TResolvedCaller       ;
begin
  List:= TList<TResolvedCaller>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:=
      'SELECT r.enclosing_symbol_id, s.qualified_name AS encl_qname, f.path AS file_path, r.start_line ' +
      'FROM refs r ' +
      'LEFT JOIN symbols s ON s.id = r.enclosing_symbol_id ' +
      'JOIN files f ON f.id = r.file_id ' +
      'WHERE r.name_text = :n AND r.id NOT IN (SELECT ref_id FROM call_edges) ' +
      'ORDER BY f.path, r.start_line';
    Q.ParamByName('n').AsString:= AName;
    Q.Open;
    while not Q.Eof do
    begin
      R:= Default(TResolvedCaller);
      if Q.FieldByName('enclosing_symbol_id').IsNull then R.EnclosingSymbolId:= 0
      else R.EnclosingSymbolId:= Q.FieldByName('enclosing_symbol_id').AsLargeInt;
      if Q.FieldByName('encl_qname').IsNull then R.EnclosingQName:= ''
      else R.EnclosingQName:= Q.FieldByName('encl_qname').AsString;
      R.Location  := ExtractFileName(Q.FieldByName('file_path').AsString);
      R.Confidence:= 'unverified';
      List.Add(R);
      Q.Next;
    end; // while
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.GetCallEdgesFromSymbol(AEnclosingSymbolId: Int64): TArray<TCallEdge>;
var
  Q   : TFDQuery       ;
  List: TList<TCallEdge>;
  E   : TCallEdge       ;
begin
  List:= TList<TCallEdge>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:=
      'SELECT ce.ref_id, ce.target_symbol_id, ce.confidence, ce.receiver_type_symbol_id ' +
      'FROM call_edges ce ' +
      'JOIN refs r ON r.id = ce.ref_id ' +
      'WHERE r.enclosing_symbol_id = :x';
    Q.ParamByName('x').AsLargeInt:= AEnclosingSymbolId;
    Q.Open;
    while not Q.Eof do
    begin
      E:= Default(TCallEdge);
      E.RefId         := Q.FieldByName('ref_id'          ).AsLargeInt;
      E.TargetSymbolId:= Q.FieldByName('target_symbol_id').AsLargeInt;
      E.Confidence    := Q.FieldByName('confidence'       ).AsString;
      if Q.FieldByName('receiver_type_symbol_id').IsNull then E.ReceiverTypeSymbolId:= 0
      else E.ReceiverTypeSymbolId:= Q.FieldByName('receiver_type_symbol_id').AsLargeInt;
      List.Add(E);
      Q.Next;
    end; // while
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.CountCallEdges: Int64;
var
  Q: TFDQuery;
begin
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT COUNT(*) AS n FROM call_edges';
    Q.Open;
    Result:= Q.FieldByName('n').AsLargeInt;
  finally
    Q.Free;
  end;
end;

function TSQLiteSymbolStore.PurgeLocals: Int64;
{ v14 (D5): the size escape hatch. Count-then-DELETE the skLocalVar/skParam
  symbols, then VACUUM to reclaim the freed pages. call_edges references call
  TARGETS (methods, ON DELETE CASCADE) and receiver TYPES (classes, ON DELETE
  SET NULL) -- NEVER a local/param -- so this delete can never cascade-remove a
  call_edges row; the resolved call graph is byte-identical before and after.
  A ref that pointed at a purged local gets refs.symbol_id NULLed (SET NULL),
  the ref row survives, and call_edges.ref_id stays intact.
  VACUUM must run OUTSIDE a transaction: FireDAC's default TxOptions.AutoCommit
  is True, so the standalone ExecSQL('DELETE ...') commits before VACUUM runs.
  We defensively commit any straggler open tx first so VACUUM can never hit
  'cannot VACUUM from within a transaction'. }
var
  Q: TFDQuery;
begin
  { Count first so we can report exactly how many symbols were removed (also
    doubles as the idempotency signal: 0 on a second run). }
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT COUNT(*) AS n FROM symbols WHERE kind IN (''local_var'',''param'')';
    Q.Open;
    Result:= Q.FieldByName('n').AsLargeInt;
  finally
    Q.Free;
  end;

  FConn.ExecSQL('DELETE FROM symbols WHERE kind IN (''local_var'',''param'')');

  { VACUUM cannot run inside a transaction. AutoCommit already committed the
    DELETE above, but be defensive: if some straggler tx is open, commit it. }
  if FConn.InTransaction then FConn.Commit;
  FConn.ExecSQL('VACUUM');
end;

function TSQLiteSymbolStore.GetTypeCandidates: TArray<TSymbol>;
{ v14 (D5): every class/interface/record symbol, minimally populated (id,
  file_id, kind, name). Mirrors ResolveAncestry's candidate query, plus 'record'
  so record-typed receivers resolve. Backs TCallResolver's name-candidate map. }
var
  Q   : TFDQuery      ;
  List: TList<TSymbol>;
  S   : TSymbol       ;
begin
  List:= TList<TSymbol>.Create;
  Q   := TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text  := 'SELECT id, file_id, kind, name FROM symbols ' +
                   'WHERE kind IN (''class'',''interface'',''record'')';
    Q.Open;
    while not Q.Eof do
    begin
      S:= Default(TSymbol);
      S.Id    := Q.FieldByName('id'     ).AsLargeInt;
      S.FileId:= Q.FieldByName('file_id').AsLargeInt;
      S.Kind  := TSymbolKind.FromText(Q.FieldByName('kind').AsString);
      S.Name  := Q.FieldByName('name'   ).AsString;
      List.Add(S);
      Q.Next;
    end;
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.GetUnitScopeEdges: TArray<TFileScopeEdge>;
{ v14 (D5): resolved uses-scope edges (file_id -> target_file_id), the exact set
  ResolveAncestry loads inline for its FileScope map. Unresolved rows (NULL
  target_file_id) are excluded, so both ids are always > 0. }
var
  Q   : TFDQuery            ;
  List: TList<TFileScopeEdge>;
  E   : TFileScopeEdge      ;
begin
  List:= TList<TFileScopeEdge>.Create;
  Q   := TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text  := 'SELECT file_id, target_file_id FROM unit_uses ' +
                   'WHERE target_file_id IS NOT NULL';
    Q.Open;
    while not Q.Eof do
    begin
      E.FileId      := Q.FieldByName('file_id'       ).AsLargeInt;
      E.TargetFileId:= Q.FieldByName('target_file_id').AsLargeInt;
      List.Add(E);
      Q.Next;
    end;
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.DumpAllCallEdges: TArray<TCallEdge>;
{ v14 (D5): diagnostic dump of every call_edges row. Backs the dump-call-edges
  verb + tests; the CLI resolves target_symbol_id -> qname for display. }
var
  Q   : TFDQuery       ;
  List: TList<TCallEdge>;
  E   : TCallEdge       ;
begin
  List:= TList<TCallEdge>.Create;
  Q   := TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text  := 'SELECT ref_id, target_symbol_id, confidence, receiver_type_symbol_id ' +
                   'FROM call_edges ORDER BY ref_id';
    Q.Open;
    while not Q.Eof do
    begin
      E:= Default(TCallEdge);
      E.RefId         := Q.FieldByName('ref_id'          ).AsLargeInt;
      E.TargetSymbolId:= Q.FieldByName('target_symbol_id').AsLargeInt;
      E.Confidence    := Q.FieldByName('confidence'       ).AsString;
      if not Q.FieldByName('receiver_type_symbol_id').IsNull then
        E.ReceiverTypeSymbolId:= Q.FieldByName('receiver_type_symbol_id').AsLargeInt;
      List.Add(E);
      Q.Next;
    end;
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.GetAmbiguousCalls(const AQName, AFilePath: string): TArray<TResolvedCaller>;
{ v14 (D5 T9): resolver-coverage diagnostic. A ref counts as a "call" only when
  its name_text matches a KNOWN routine/method symbol name (the IN subquery on
  symbols.kind) -- without that filter every unresolved bare identifier would
  flood the output, not just call sites. Of those name-matching refs, a row
  qualifies when it is either NOT resolved at all (no call_edges row -- the
  FindUnresolvedNameCallers case, receiver untypable) or resolved but flagged
  'ambiguous' (multiple candidate targets, none certain). Confidence in the
  result is 'unverified' for the no-edge case and 'ambiguous' for the flagged
  case, mirroring FindUnresolvedNameCallers / FindResolvedCallers. Scope is
  optional: AQName<>'' filters to refs enclosed by that qualified routine name;
  AFilePath<>'' filters to refs in that file (matched by file name, tolerant of
  path differences like the other file-scoped verbs); both '' = whole-DB. }
var
  Q     : TFDQuery              ;
  List  : TList<TResolvedCaller>;
  R     : TResolvedCaller       ;
  SqlTxt: string                ;
begin
  List:= TList<TResolvedCaller>.Create;
  Q   := TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    SqlTxt:=
      'SELECT r.enclosing_symbol_id, s.qualified_name AS encl_qname, f.path AS file_path, ' +
      '  CASE WHEN ce.confidence = ''ambiguous'' THEN ''ambiguous'' ELSE ''unverified'' END AS conf ' +
      'FROM refs r ' +
      'LEFT JOIN symbols s ON s.id = r.enclosing_symbol_id ' +
      'JOIN files f ON f.id = r.file_id ' +
      'LEFT JOIN call_edges ce ON ce.ref_id = r.id ' +
      'WHERE r.name_text IN (SELECT name FROM symbols WHERE kind IN (''procedure'',''function'',''method'',''constructor'',''destructor'')) ' +
      '  AND (ce.ref_id IS NULL OR ce.confidence = ''ambiguous'') ';
    if AQName <> '' then SqlTxt:= SqlTxt + '  AND s.qualified_name = :qn ';
    if AFilePath <> '' then SqlTxt:= SqlTxt + '  AND f.path LIKE :fp ';
    SqlTxt:= SqlTxt + 'ORDER BY f.path, r.start_line';
    Q.SQL.Text:= SqlTxt;
    if AQName <> '' then Q.ParamByName('qn').AsString:= AQName;
    if AFilePath <> '' then Q.ParamByName('fp').AsString:= '%' + ExtractFileName(AFilePath);
    Q.Open;
    while not Q.Eof do
    begin
      R:= Default(TResolvedCaller);
      if Q.FieldByName('enclosing_symbol_id').IsNull then R.EnclosingSymbolId:= 0
      else R.EnclosingSymbolId:= Q.FieldByName('enclosing_symbol_id').AsLargeInt;
      if Q.FieldByName('encl_qname').IsNull then R.EnclosingQName:= ''
      else R.EnclosingQName:= Q.FieldByName('encl_qname').AsString;
      R.Location  := ExtractFileName(Q.FieldByName('file_path').AsString);
      R.Confidence:= Q.FieldByName('conf').AsString;
      List.Add(R);
      Q.Next;
    end; // while
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end; // try
end; // function

procedure TSQLiteSymbolStore.UpsertDiBinding(const AToken: TFileTxToken; const ABinding: TDiBindingRow);
begin
  FQUpsertDiBinding.ParamByName('fid' ).AsLargeInt:= AToken  .FileId;
  FQUpsertDiBinding.ParamByName('intf').AsString  := ABinding.InterfaceName;
  FQUpsertDiBinding.ParamByName('impl').AsString  := ABinding.ImplName;
  FQUpsertDiBinding.ParamByName('life').AsString  := ABinding.Lifetime;
  FQUpsertDiBinding.ParamByName('sl'  ).AsInteger := ABinding.StartLine;
  FQUpsertDiBinding.ParamByName('sc'  ).AsInteger := ABinding.StartCol;
  FQUpsertDiBinding.ParamByName('el'  ).AsInteger := ABinding.EndLine;
  FQUpsertDiBinding.ParamByName('ec'  ).AsInteger := ABinding.EndCol;
  FQUpsertDiBinding.ExecSQL;
end;

procedure TSQLiteSymbolStore.DeleteDiBindingsForFile(AFileId: Int64);
begin
  FQDeleteFileDiBindings.ParamByName('fid').AsLargeInt:= AFileId;
  FQDeleteFileDiBindings.ExecSQL;
end;

procedure TSQLiteSymbolStore.UpsertStringLiteral(const AToken: TFileTxToken; const ALit: TStringLiteral);
begin
  { Safety net: if FTS5 is unavailable the sync triggers were (hopefully)
    dropped in Migrate, but DROP TRIGGER can fail silently when the LSP holds
    a concurrent WAL read lock. Skip the INSERT entirely so a surviving trigger
    never fires and crashes with "no such module: fts5". }
  if not FFts5Available then Exit;
  FQUpsertStringLiteral.ParamByName('fid').AsLargeInt:= AToken.FileId;
  FQUpsertStringLiteral.ParamByName('sid').DataType:= ftLargeint;
  if ALit.SymbolId > 0 then FQUpsertStringLiteral.ParamByName('sid').AsLargeInt:= ALit.SymbolId
  else FQUpsertStringLiteral.ParamByName('sid').Clear;
  FQUpsertStringLiteral.ParamByName('src'  ).AsString  := ALit.Source;
  FQUpsertStringLiteral.ParamByName('kind' ).AsString  := ALit.Kind;
  FQUpsertStringLiteral.ParamByName('owner').AsString  := ALit.OwnerName;
  FQUpsertStringLiteral.ParamByName('txt'  ).AsString  := ALit.Text;
  FQUpsertStringLiteral.ParamByName('sl').AsInteger := ALit.StartLine;
  FQUpsertStringLiteral.ParamByName('sc').AsInteger := ALit.StartCol;
  FQUpsertStringLiteral.ParamByName('el').AsInteger := ALit.EndLine;
  FQUpsertStringLiteral.ParamByName('ec').AsInteger := ALit.EndCol;
  FQUpsertStringLiteral.ExecSQL;
end;

procedure TSQLiteSymbolStore.DeleteStringLiteralsForFile(AFileId: Int64);
begin
  if not FFts5Available then Exit; // same guard as UpsertStringLiteral
  FQDeleteFileStringLiterals.ParamByName('fid').AsLargeInt:= AFileId;
  FQDeleteFileStringLiterals.ExecSQL;  // triggers cascade the FTS 'delete'
end;

function TSQLiteSymbolStore.SearchText(const AQuery: string; AMode: string; const ASource: string; ALimit: Integer): TArray<TStringLitMatch>;
var
  Q   : TFDQuery              ;
  List: TList<TStringLitMatch>;
  M   : TStringLitMatch       ;
  FtsTable, MatchExpr, Sql: string;

  function QuotePhrase(const S: string): string;
  begin // FTS5: wrap in double quotes, doubling embedded quotes -> phrase match
    Result:= '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"';
  end;

begin
  if not FFts5Available then
    raise ENotSupportedException.Create(
      'Text search (--text) requires FTS5; the current sqlite3.dll was built ' +
      'without SQLITE_ENABLE_FTS5. Replace it with an FTS5-enabled build.');
  List:= TList<TStringLitMatch>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    if SameText(AMode, 'substring') then
    begin
      FtsTable := 'string_fts_tri';
      MatchExpr:= QuotePhrase(AQuery); // trigram: phrase-quote -> substring match
    end
    else if SameText(AMode, 'anyorder') then
    begin
      FtsTable := 'string_fts';
      MatchExpr:= '';
      for var Term in AQuery.Split([' ', #9, #10, #13], TStringSplitOptions.ExcludeEmpty) do
      begin
        if MatchExpr <> '' then MatchExpr := MatchExpr + ' ';
        MatchExpr := MatchExpr + QuotePhrase(Term);
      end;
      if MatchExpr = '' then MatchExpr := QuotePhrase(AQuery);
    end
    else
    begin
      FtsTable := 'string_fts';
      MatchExpr:= QuotePhrase(AQuery); // default: exact phrase, in order
    end;
    Sql:=
      'SELECT sl.text AS txt, sl.source AS src, sl.kind AS kind, sl.owner_name AS owner, ' +
      '  sl.start_line AS sl_, sl.start_col AS sc_, sl.end_line AS el_, sl.end_col AS ec_, ' +
      '  f.path AS fpath, s.qualified_name AS encl ' +
      'FROM ' + FtsTable + ' ft ' +
      'JOIN string_literals sl ON sl.id = ft.rowid ' +
      'JOIN files f ON f.id = sl.file_id ' +
      'LEFT JOIN symbols s ON s.id = sl.symbol_id ' +
      'WHERE ' + FtsTable + ' MATCH :q ';
    if ASource <> '' then Sql:= Sql + 'AND sl.source = :src ';
    Sql:= Sql + 'ORDER BY f.path, sl.start_line LIMIT :lim';
    Q.SQL.Text:= Sql;
    Q.ParamByName('q').AsString:= MatchExpr;
    if ASource <> '' then Q.ParamByName('src').AsString:= ASource;
    Q.ParamByName('lim').AsInteger:= ALimit;
    Q.Open;
    while not Q.Eof do
    begin
      M:= Default(TStringLitMatch);
      M.Text          := Q.FieldByName('txt'  ).AsString;
      M.Source        := Q.FieldByName('src'  ).AsString;
      M.Kind          := Q.FieldByName('kind' ).AsString;
      M.OwnerName     := Q.FieldByName('owner').AsString;
      M.FilePath      := Q.FieldByName('fpath').AsString;
      M.EnclosingQName:= Q.FieldByName('encl' ).AsString;
      M.StartLine:= Q.FieldByName('sl_').AsInteger; M.StartCol:= Q.FieldByName('sc_').AsInteger;
      M.EndLine  := Q.FieldByName('el_').AsInteger; M.EndCol  := Q.FieldByName('ec_').AsInteger;
      List.Add(M);
      Q.Next;
    end;
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

function TSQLiteSymbolStore.FindImplementationsOf( const AInterfaceName: string): TArray<TDiBindingRow>;
var
  Q   : TFDQuery            ;
  List: TList<TDiBindingRow>;
  B   : TDiBindingRow       ;
begin
  List:= TList<TDiBindingRow>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT * FROM di_bindings WHERE interface_name = :intf ' + 'ORDER BY file_id, start_line';
    Q.ParamByName('intf').AsString:= AInterfaceName;
    Q.Open;
    while not Q.Eof do
    begin
      B:= Default(TDiBindingRow);
      B.Id           := Q.FieldByName('id'            ).AsLargeInt;
      B.FileId       := Q.FieldByName('file_id'       ).AsLargeInt;
      B.InterfaceName:= Q.FieldByName('interface_name').AsString;
      B.ImplName     := Q.FieldByName('impl_name'     ).AsString;
      B.Lifetime     := Q.FieldByName('lifetime'      ).AsString;
      B.StartLine    := Q.FieldByName('start_line'    ).AsInteger;
      B.StartCol     := Q.FieldByName('start_col'     ).AsInteger;
      B.EndLine      := Q.FieldByName('end_line'      ).AsInteger;
      B.EndCol       := Q.FieldByName('end_col'       ).AsInteger;
      List.Add(B);
      Q.Next;
    end;
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.FindDiResolveSites( const AInterfaceName: string): TArray<TReference>;
var
  Q   : TFDQuery         ;
  List: TList<TReference>;
  R   : TReference       ;
begin
  List:= TList<TReference>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT * FROM refs WHERE kind = ''di-resolve'' AND name_text = :intf ' + 'ORDER BY file_id, start_line';
    Q.ParamByName('intf').AsString:= AInterfaceName;
    Q.Open;
    while not Q.Eof do
    begin
      R:= Default(TReference);
      R.Id:= Q.FieldByName('id').AsLargeInt;
      if Q.FieldByName('symbol_id').IsNull then R.SymbolId:= 0
      else R.SymbolId:= Q.FieldByName('symbol_id').AsLargeInt;
      R.FileId   := Q.FieldByName('file_id'   ).AsLargeInt;
      R.Kind     := Q.FieldByName('kind'      ).AsString;
      R.NameText := Q.FieldByName('name_text' ).AsString;
      R.StartLine:= Q.FieldByName('start_line').AsInteger;
      R.StartCol := Q.FieldByName('start_col' ).AsInteger;
      R.EndLine  := Q.FieldByName('end_line'  ).AsInteger;
      R.EndCol   := Q.FieldByName('end_col'   ).AsInteger;
      List.Add(R);
      Q.Next;
    end; // while
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.FindDiUnresolved: TArray<TReference>;
var
  Q   : TFDQuery         ;
  List: TList<TReference>;
  R   : TReference       ;
begin
  List:= TList<TReference>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT * FROM refs WHERE kind = ''di-unresolved'' ' + 'ORDER BY name_text, file_id, start_line';
    Q.Open;
    while not Q.Eof do
    begin
      R:= Default(TReference);
      R.Id:= Q.FieldByName('id').AsLargeInt;
      if Q.FieldByName('symbol_id').IsNull then R.SymbolId:= 0
      else R.SymbolId:= Q.FieldByName('symbol_id').AsLargeInt;
      R.FileId   := Q.FieldByName('file_id'   ).AsLargeInt;
      R.Kind     := Q.FieldByName('kind'      ).AsString;
      R.NameText := Q.FieldByName('name_text' ).AsString;
      R.StartLine:= Q.FieldByName('start_line').AsInteger;
      R.StartCol := Q.FieldByName('start_col' ).AsInteger;
      R.EndLine  := Q.FieldByName('end_line'  ).AsInteger;
      R.EndCol   := Q.FieldByName('end_col'   ).AsInteger;
      List.Add(R);
      Q.Next;
    end; // while
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.FindEventHandlersForForm( const AFormName: string): TArray<TReference>;
var
  FormSym : TSymbol          ;
  Child   : TSymbol          ;
  Children: TArray<TSymbol>  ;
  R       : TReference       ;
  H       : TReference       ;
  List    : TList<TReference>;
begin
  List:= TList<TReference>.Create;
  try
    FormSym:= FindSymbolByExactNameAnywhere(AFormName);
    if FormSym.Id > 0 then
    begin
      Children:= FindAllChildSymbols(FormSym.Id);
      for Child in Children do
        for R in FindCallersByName(Child.Name) do
          if R.Kind = 'event-binding' then
          begin
            H:= R;
            H.NameText:= Child.Name; // the handler method name
            List.Add(H);
          end;
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

procedure TSQLiteSymbolStore.UpsertChunk(const AToken: TFileTxToken; const AChunk: TChunk);
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
  Result:= Default(TSymbol);
  Result.Id    := AQ.FieldByName('id'     ).AsLargeInt;
  Result.FileId:= AQ.FieldByName('file_id').AsLargeInt;
  if AQ.FieldByName('parent_id').IsNull then Result.ParentId:= -1
  else Result.ParentId:= AQ.FieldByName('parent_id').AsLargeInt;
  Result.Kind:= TSymbolKind.FromText(AQ.FieldByName('kind').AsString);
  Result.Name         := AQ.FieldByName('name'          ).AsString;
  Result.QualifiedName:= AQ.FieldByName('qualified_name').AsString;
  Result.Signature    := AQ.FieldByName('signature'     ).AsString;
  Result.Modifiers    := AQ.FieldByName('modifiers'     ).AsString;
  if AQ.FindField('section') <> nil then { tolerate pre-v7 databases }
    Result.Section  := AQ.FieldByName('section'   ).AsString;
  if AQ.FindField('heritage') <> nil then { v11: tolerate pre-v11 databases }
    Result.Heritage := AQ.FieldByName('heritage'  ).AsString;
  if AQ.FindField('is_virtual') <> nil then { v12: tolerate pre-v12 databases }
    Result.IsVirtual := AQ.FieldByName('is_virtual').AsInteger <> 0;
  Result  .StartLine:= AQ.FieldByName('start_line').AsInteger;
  Result  .StartCol := AQ.FieldByName('start_col' ).AsInteger;
  Result  .EndLine  := AQ.FieldByName('end_line'  ).AsInteger;
  Result  .EndCol   := AQ.FieldByName('end_col'   ).AsInteger;
  if AQ.FindField('impl_start_line') <> nil then { tolerate pre-v9 databases }
  begin
    Result.ImplStartLine:= AQ.FieldByName('impl_start_line').AsInteger;
    Result.ImplEndLine  := AQ.FieldByName('impl_end_line'  ).AsInteger;
  end;
end; // function

function TSQLiteSymbolStore.FindSymbolsByExactName( const AName: string): TArray<TSymbol>;
var
  List: TList<TSymbol>;
begin
  List:= TList<TSymbol>.Create;
  try
    if FQFindByName.Active then FQFindByName.Close;
    FQFindByName.ParamByName('name').AsString:= AName;
    FQFindByName.Open;
    while not FQFindByName.Eof do
    begin
      List.Add(ReadSymbolFromQuery(FQFindByName));
      FQFindByName.Next;
    end;
    FQFindByName.Close;
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end; // function

function TSQLiteSymbolStore.FindSymbolsByQualifiedName( const AQName: string): TArray<TSymbol>;
var
  List: TList<TSymbol>;
begin
  List:= TList<TSymbol>.Create;
  try
    if FQFindByQName.Active then FQFindByQName.Close;
    FQFindByQName.ParamByName('qname').AsString:= AQName;
    FQFindByQName.Open;
    while not FQFindByQName.Eof do
    begin
      List.Add(ReadSymbolFromQuery(FQFindByQName));
      FQFindByQName.Next;
    end;
    FQFindByQName.Close;
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end; // function

function TSQLiteSymbolStore.ResolveFileIdTolerant(const APath: string): Int64;
{ Path matching is fragile: the indexer can bake un-normalized segments into
  files.path (e.g. "C:\repo\tests\..\src\Foo.pas") depending on how it was
  invoked, while the IDE hands us the fully-expanded path. Resolve in three
  escalating steps:
    1. exact (slash-tolerant) - the common case for clean indexes
    2. exact on the expanded caller path
    3. basename match: pull every file with the same leaf name, expand each
       stored path with TPath.GetFullPath, and accept the one whose canonical
       form equals the caller's. If exactly one candidate exists, accept it
       outright (a single open buffer almost never collides on basename). }
var
  Q        : TFDQuery;
  WantFull : string  ;
  Leaf     : string  ;
  CandFull : string  ;
  OnlyId   : Int64   ;
  MatchId  : Int64   ;
  CandCount: Integer ;
begin
  Result:= FindFileIdByPath(APath);
  if Result >= 0 then Exit;

  WantFull:= '';
  try WantFull:= TPath.GetFullPath(APath); except WantFull:= APath; end;
  if not SameText(WantFull, APath) then
  begin
    Result:= FindFileIdByPath(WantFull);
    if Result >= 0 then Exit;
  end;

  Leaf:= TPath.GetFileName(APath);
  if Leaf = '' then Exit(-1);

  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT id, path FROM files WHERE path LIKE :leaf';
    Q.ParamByName('leaf').AsString:= '%' + Leaf;
    Q.Open;
    CandCount:= 0;
    OnlyId := -1;
    MatchId:= -1;
    while not Q.Eof do
    begin
      { Endswith guard: LIKE '%Leaf' also matches "XYZFoo.pas" for "Foo.pas",
        so require a real path-separator boundary before the leaf. }
      var StoredPath: string:= Q.FieldByName('path').AsString;
      if SameText(TPath.GetFileName(StoredPath), Leaf) then
      begin
        Inc(CandCount);
        OnlyId:= Q.FieldByName('id').AsLargeInt;
        CandFull:= '';
        try CandFull:= TPath.GetFullPath(StoredPath); except CandFull:= StoredPath; end;
        if (MatchId < 0) and SameText(CandFull, WantFull) then MatchId:= OnlyId;
      end;
      Q.Next;
    end;
    Q.Close;
    if MatchId >= 0 then Result:= MatchId
    else if CandCount = 1 then Result:= OnlyId
    else Result:= -1;
  finally
    Q.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.FindSymbolsByFile( const APath: string): TArray<TSymbol>;
var
  Q     : TFDQuery      ;
  List  : TList<TSymbol>;
  FileId: Int64         ;
begin
  List:= TList<TSymbol>.Create;
  Q:= TFDQuery.Create(nil);
  try
    { Resolve the file id tolerantly (handles un-normalized stored paths),
      then pull every symbol on that file ordered by position. }
    FileId:= ResolveFileIdTolerant(APath);
    if FileId >= 0 then
    begin
      Q.Connection:= FConn;
      Q.SQL.Text:= 'SELECT * FROM symbols WHERE file_id = :fid ' + 'ORDER BY start_line, start_col';
      Q.ParamByName('fid').AsLargeInt:= FileId;
      Q.Open;
      while not Q.Eof do
      begin
        List.Add(ReadSymbolFromQuery(Q));
        Q.Next;
      end;
      Q.Close;
    end;
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.GetReferencesFromFile( AFileId: Int64): TArray<TReference>;
var
  Q   : TFDQuery         ;
  List: TList<TReference>;
  R   : TReference       ;
begin
  List:= TList<TReference>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT * FROM refs WHERE file_id = :fid ORDER BY start_line, start_col';
    Q.ParamByName('fid').AsLargeInt:= AFileId;
    Q.Open;
    while not Q.Eof do
    begin
      R:= Default(TReference);
      R.Id:= Q.FieldByName('id').AsLargeInt;
      if not Q.FieldByName('symbol_id').IsNull then R.SymbolId:= Q.FieldByName('symbol_id').AsLargeInt;
      R.FileId:= AFileId;
      R.Kind     := Q.FieldByName('kind'      ).AsString;
      R.NameText := Q.FieldByName('name_text' ).AsString;
      R.StartLine:= Q.FieldByName('start_line').AsInteger;
      R.StartCol := Q.FieldByName('start_col' ).AsInteger;
      R.EndLine  := Q.FieldByName('end_line'  ).AsInteger; // v0.82: pre-existing read gap
      R.EndCol   := Q.FieldByName('end_col'   ).AsInteger;
      if not Q.FieldByName('enclosing_symbol_id').IsNull then
        R.EnclosingSymbolId:= Q.FieldByName('enclosing_symbol_id').AsLargeInt; // v13
      List.Add(R);
      Q.Next;
    end;
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.FindReferencesTo( ASymbolId: Int64): TArray<TReference>;
var
  Q   : TFDQuery         ;
  List: TList<TReference>;
  R   : TReference       ;
begin
  List:= TList<TReference>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT * FROM refs WHERE symbol_id = :sid ORDER BY file_id, start_line';
    Q.ParamByName('sid').AsLargeInt:= ASymbolId;
    Q.Open;
    while not Q.Eof do
    begin
      R:= Default(TReference);
      R.Id:= Q.FieldByName('id').AsLargeInt;
      R.SymbolId:= ASymbolId;
      R.FileId   := Q.FieldByName('file_id'   ).AsLargeInt;
      R.Kind     := Q.FieldByName('kind'      ).AsString;
      R.NameText := Q.FieldByName('name_text' ).AsString;
      R.StartLine:= Q.FieldByName('start_line').AsInteger;
      R.StartCol := Q.FieldByName('start_col' ).AsInteger;
      R.EndLine  := Q.FieldByName('end_line'  ).AsInteger;
      R.EndCol   := Q.FieldByName('end_col'   ).AsInteger;
      if not Q.FieldByName('enclosing_symbol_id').IsNull then
        R.EnclosingSymbolId:= Q.FieldByName('enclosing_symbol_id').AsLargeInt; // v13
      List.Add(R);
      Q.Next;
    end;
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.FindSymbolsFuzzy(const APattern: string; ATopK: Integer): TArray<TSymbol>;
var
  Q              : TFDQuery                      ;
  Scored         : TList<TPair<Integer, TSymbol>>;
  D              : Integer                       ;
  MaxD           : Integer                       ;
  MinShared      : Integer                       ;
  PatLen         : Integer                       ;
  Grams          : TArray<string>                ;
  PlaceholderList: string                        ;
  i              : Integer                       ;
  Sym            : TSymbol                       ;
begin
  SetLength(Result, 0);
  EnsureTrigramTablePopulated;
  MaxD := DRagLint.Query.Fuzzy.FuzzyMaxDistanceFor(APattern);
  Grams:= DRagLint.Query.Fuzzy.Trigrams           (APattern);
  PatLen:= Length(APattern);

  Scored:= TList<TPair<Integer, TSymbol>>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    if Length(Grams) = 0 then
    begin
      // Pattern too short for trigrams - full scan (still fast for short pattern).
      Q.SQL.Text:= 'SELECT * FROM symbols';
    end
    else
    begin
      // Build placeholder list for IN clause: ?, ?, ?, ...
      PlaceholderList:= '';
      for i:= 0 to High(Grams) do
      begin
        if i > 0 then PlaceholderList:= PlaceholderList + ', ';
        PlaceholderList:= PlaceholderList + ':g' + IntToStr(i);
      end;
      // v0.42 perf: require a candidate to share at least HALF the pattern's
      // trigrams, not just one. The old ">=1 shared trigram" matched anything
      // containing a common gram (e.g. 'red'/'set'), so Levenshtein ran over a
      // huge set (~3.2 s on 1.5M symbols). HAVING COUNT >= minShared (served by
      // idx_symbol_trigrams_symbol) plus the length pre-filter below cut it to
      // the genuinely-similar candidates.
      MinShared:= (Length(Grams) + 1) div 2;
      if MinShared < 1 then MinShared:= 1;
      Q.SQL.Text:= 'SELECT s.* FROM symbols s ' + 'WHERE s.id IN (' + '  SELECT symbol_id FROM symbol_trigrams ' + '  WHERE trigram IN (' + PlaceholderList + ')' +
      '  GROUP BY symbol_id HAVING COUNT(*) >= ' + IntToStr(MinShared) + ')';
      for i:= 0 to High(Grams) do Q.ParamByName('g' + IntToStr(i)).AsString:= Grams[i];
    end; // else
    Q.Open;
    while not Q.Eof do
    begin
      Sym:= ReadSymbolFromQuery(Q);
      // Length pre-filter: Levenshtein(A,B) >= ||A|-|B||, so anything whose
      // name length differs from the pattern by more than MaxD can't qualify.
      if Abs(Length(Sym.Name) - PatLen) > MaxD then
      begin
        Q.Next;
        Continue;
      end;
      D:= DRagLint.Query.Fuzzy.LevenshteinDistance(APattern, Sym.Name);
      if D <= MaxD then Scored.Add(TPair<Integer, TSymbol>.Create(D, Sym));
      Q.Next;
    end;

    Scored.Sort(
      TComparer<TPair<Integer,
      TSymbol>>.Construct( function(const L, R: TPair<Integer, TSymbol>): Integer begin Result:= L.Key - R.Key; if Result = 0 then Result:= CompareText(L.Value.QualifiedName,
            R.Value.QualifiedName); end));
    if Scored.Count > ATopK then Scored.Count:= ATopK;
    SetLength(Result, Scored.Count);
    for i:= 0 to Scored.Count - 1 do Result[i]:= Scored[i].Value;
  finally
    Q.Free;
    Scored.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.FindCallersByName( const ACalleeName: string): TArray<TReference>;
var
  Q   : TFDQuery         ;
  List: TList<TReference>;
  R   : TReference       ;
begin
  List:= TList<TReference>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    // Match any reference kind (call, event-binding, type_use, ...). "callers"
    // is a slight misnomer - the semantic is "every site that references
    // this name" - but it's what users mean when they say find-callers.
    Q.SQL.Text:= 'SELECT * FROM refs WHERE name_text = :name ' + 'ORDER BY file_id, start_line';
    Q.ParamByName('name').AsString:= ACalleeName;
    Q.Open;
    while not Q.Eof do
    begin
      R:= Default(TReference);
      R.Id:= Q.FieldByName('id').AsLargeInt;
      if Q.FieldByName('symbol_id').IsNull then R.SymbolId:= 0
      else R.SymbolId:= Q.FieldByName('symbol_id').AsLargeInt;
      R.FileId   := Q.FieldByName('file_id'   ).AsLargeInt;
      R.Kind     := Q.FieldByName('kind'      ).AsString;
      R.NameText := Q.FieldByName('name_text' ).AsString;
      R.StartLine:= Q.FieldByName('start_line').AsInteger;
      R.StartCol := Q.FieldByName('start_col' ).AsInteger;
      R.EndLine  := Q.FieldByName('end_line'  ).AsInteger;
      R.EndCol   := Q.FieldByName('end_col'   ).AsInteger;
      if not Q.FieldByName('enclosing_symbol_id').IsNull then
        R.EnclosingSymbolId:= Q.FieldByName('enclosing_symbol_id').AsLargeInt; // v13
      R.ContextText:= ''; // v0.17: initialize context (unless set by FindCallersByNameWithContext)
      List.Add(R);
      Q.Next;
    end; // while
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.GetFilePath(AFileId: Int64): string;
var
  Q: TFDQuery;
begin
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT path FROM files WHERE id = :id';
    Q.ParamByName('id').AsLargeInt:= AFileId;
    Q.Open;
    if Q.IsEmpty then Result:= ''
    else Result:= Q.FieldByName('path').AsString;
  finally
    Q.Free;
  end;
end;

function TSQLiteSymbolStore.CountSymbols: Int64;
begin
  if FQCountSymbols.Active then FQCountSymbols.Close;
  FQCountSymbols.Open;
  Result:= FQCountSymbols.FieldByName('n').AsLargeInt;
  FQCountSymbols.Close;
end;

function TSQLiteSymbolStore.CountReferences: Int64;
var
  Q: TFDQuery;
begin
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT COUNT(*) AS n FROM refs';
    Q.Open;
    Result:= Q.FieldByName('n').AsLargeInt;
  finally
    Q.Free;
  end;
end;

function TSQLiteSymbolStore.CountFiles: Int64;
begin
  if FQCountFiles.Active then FQCountFiles.Close;
  FQCountFiles.Open;
  Result:= FQCountFiles.FieldByName('n').AsLargeInt;
  FQCountFiles.Close;
end;

procedure TSQLiteSymbolStore.UpsertSymbolDoc(const AToken: TFileTxToken; ASymbolId: Int64; const ADoc: TParsedDoc);
// Helper: assign a nullable text param without changing its pre-declared
// DataType. Using AsString would silently flip DataType to ftString and break
// the next call with [SQLite]-338 "Param type changed".
  procedure SetNullableText(const AParamName: string; const AValue: string);
  begin
    with FQUpsertSymbolDoc.ParamByName(AParamName) do
      if AValue = '' then Clear else Value:= AValue;
  end;
begin
  if not ADoc.HasContent then Exit;
  FQUpsertSymbolDoc.ParamByName('sid').AsLargeInt:= ASymbolId;
  FQUpsertSymbolDoc.ParamByName('fmt').AsString:= DocFormatToStr(ADoc.Format);
  FQUpsertSymbolDoc.ParamByName('raw').AsString:= ADoc.RawBlock;

  // Use Value := (not AsString :=) so DataType stays as pre-declared ftWideMemo.
  // AsString := implicitly changes DataType to ftString, which raises
  // [SQLite]-338 on subsequent calls once the query is Prepared.
  SetNullableText('sum', ADoc.Summary    );
  SetNullableText('rem', ADoc.Remarks    );
  SetNullableText('ret', ADoc.ReturnsText);
  if Length(ADoc.Params) = 0 then FQUpsertSymbolDoc.ParamByName('pj').Clear
  else FQUpsertSymbolDoc.ParamByName('pj').Value:= ParamsToJson(ADoc.Params);
  if Length(ADoc.Exceptions) = 0 then FQUpsertSymbolDoc.ParamByName('ej').Clear
  else FQUpsertSymbolDoc.ParamByName('ej').Value:= ExceptionsToJson(ADoc.Exceptions);
  SetNullableText('ex', ADoc.ExampleText);
  if Length(ADoc.SeeAlso) = 0 then FQUpsertSymbolDoc.ParamByName('sj').Clear
  else FQUpsertSymbolDoc.ParamByName('sj').Value:= SeeAlsoToJson(ADoc.SeeAlso);
  SetNullableText('since', ADoc.SinceText);

  FQUpsertSymbolDoc.ParamByName('dep').AsInteger:= Ord(ADoc.Deprecated);
  FQUpsertSymbolDoc.ParamByName('sl').AsInteger:= ADoc.StartLine;
  FQUpsertSymbolDoc.ParamByName('el').AsInteger:= ADoc.EndLine;
  FQUpsertSymbolDoc.ExecSQL;
end; // begin

function TSQLiteSymbolStore.GetSymbolDoc(ASymbolId: Int64): TParsedDoc;
begin
  FillChar(Result, SizeOf(Result), 0);
  if FQGetSymbolDoc.Active then FQGetSymbolDoc.Close;
  FQGetSymbolDoc.ParamByName('sid').AsLargeInt:= ASymbolId;
  FQGetSymbolDoc.Open;
  try
    if FQGetSymbolDoc.IsEmpty then Exit;
    case IndexStr(FQGetSymbolDoc.FieldByName('format').AsString, ['xmldoc', 'pasdoc', 'oneline', 'loose']) of
      0: Result.Format:= dfXmlDoc;
      1: Result.Format:= dfPasDoc;
      2: Result.Format:= dfOneline;
      3: Result.Format:= dfLoose;
    end;
    Result.RawBlock   := FQGetSymbolDoc.FieldByName('raw_block'   ).AsString;
    Result.Summary    := FQGetSymbolDoc.FieldByName('summary'     ).AsString;
    Result.Remarks    := FQGetSymbolDoc.FieldByName('remarks'     ).AsString;
    Result.ReturnsText:= FQGetSymbolDoc.FieldByName('returns_text').AsString;
    Result.ExampleText:= FQGetSymbolDoc.FieldByName('example_text').AsString;
    Result.SinceText  := FQGetSymbolDoc.FieldByName('since_text'  ).AsString;
    Result.Deprecated:= FQGetSymbolDoc.FieldByName('deprecated').AsInteger = 1;
    Result.StartLine:= FQGetSymbolDoc.FieldByName('start_line').AsInteger;
    Result.EndLine  := FQGetSymbolDoc.FieldByName('end_line'  ).AsInteger;
    // Raw JSON strings -- v0.16 renderers read these directly; v0.17 may parse.
    Result.ParamsJsonRaw    := FQGetSymbolDoc.FieldByName('params_json'    ).AsString;
    Result.ExceptionsJsonRaw:= FQGetSymbolDoc.FieldByName('exceptions_json').AsString;
    Result.SeeAlsoJsonRaw   := FQGetSymbolDoc.FieldByName('seealso_json'   ).AsString;
    Result.HasContent:= True;
  finally
    FQGetSymbolDoc.Close;
  end; // try
end; // function

function TSQLiteSymbolStore.FindByDocTag(const ATag: string): TArray<TSymbol>;
var
  Acc: TList<TSymbol>;
begin
  Acc:= TList<TSymbol>.Create;
  try
    if FQFindByDocTag.Active then FQFindByDocTag.Close;
    FQFindByDocTag.ParamByName('tag').AsString:= LowerCase(ATag);
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
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.FindUndocumented(const AKind: string; APublicOnly: Boolean): TArray<TSymbol>;
var
  Acc: TList<TSymbol>;
begin
  Acc:= TList<TSymbol>.Create;
  try
    if FQFindUndocumented.Active then FQFindUndocumented.Close;
    FQFindUndocumented.ParamByName('kind').AsString:= AKind;
    FQFindUndocumented.ParamByName('publicOnly').AsInteger:= Ord(APublicOnly);
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
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.FindByDocContains( const ASubstring: string): TArray<TSymbol>;
var
  Acc: TList<TSymbol>;
begin
  Acc:= TList<TSymbol>.Create;
  try
    if FQFindByDocContains.Active then FQFindByDocContains.Close;
    FQFindByDocContains.ParamByName('pat').AsString:= '%' + ASubstring + '%';
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
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end; // try
end; // function

procedure TSQLiteSymbolStore.DeleteFileDocs(AFileId: Int64);
begin
  FQDeleteFileDocs.ParamByName('fid').AsLargeInt:= AFileId;
  FQDeleteFileDocs.ExecSQL;
end;

// v0.18: bench-context

function TSQLiteSymbolStore.ListDocumentedSymbols(ALimit: Integer): TArray<TSymbol>;
var
  Acc: TList<TSymbol>;
begin
  Acc:= TList<TSymbol>.Create;
  try
    if FQListDocumentedSymbols.Active then FQListDocumentedSymbols.Close;
    FQListDocumentedSymbols.ParamByName('lim').AsInteger:= ALimit;
    FQListDocumentedSymbols.Open;
    try
      while not FQListDocumentedSymbols.Eof do
      begin
        Acc.Add(ReadSymbolFromQuery(FQListDocumentedSymbols));
        FQListDocumentedSymbols.Next;
      end;
    finally
      FQListDocumentedSymbols.Close;
    end;
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end; // try
end; // function

// v0.19: type-at-position helpers

function TSQLiteSymbolStore.FindContainingSymbol(AFileId: Int64; ALine: Integer): TSymbol;
begin
  Result:= Default(TSymbol);
  if FQFindContaining.Active then FQFindContaining.Close;
  FQFindContaining.ParamByName('fid' ).AsLargeInt:= AFileId;
  FQFindContaining.ParamByName('line').AsInteger := ALine;
  FQFindContaining.Open;
  try
    if not FQFindContaining.IsEmpty then Result:= ReadSymbolFromQuery(FQFindContaining);
  finally
    FQFindContaining.Close;
  end;
end;

function TSQLiteSymbolStore.GetSymbolById(AId: Int64): TSymbol;
var
  Q: TFDQuery;
begin
  Result:= Default(TSymbol);
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT * FROM symbols WHERE id = :id LIMIT 1';
    Q.ParamByName('id').AsLargeInt:= AId;
    Q.Open;
    if not Q.IsEmpty then Result:= ReadSymbolFromQuery(Q);
  finally
    Q.Free;
  end;
end;

function TSQLiteSymbolStore.FindFileIdByPath(const APath: string): Int64;
var
  NormPath: string;
begin
  Result:= -1;
  NormPath:= StringReplace(APath, '/', '\', [rfReplaceAll]);
  if FQFindFileId.Active then FQFindFileId.Close;
  FQFindFileId.ParamByName('p').AsString:= NormPath;
  FQFindFileId.Open;
  try
    if not FQFindFileId.IsEmpty then Result:= FQFindFileId.Fields[0].AsLargeInt;
  finally
    FQFindFileId.Close;
  end;
  if Result = -1 then
  begin
    // Try forward-slash normalised version
    NormPath:= StringReplace(APath, '\', '/', [rfReplaceAll]);
    if FQFindFileId.Active then FQFindFileId.Close;
    FQFindFileId.ParamByName('p').AsString:= NormPath;
    FQFindFileId.Open;
    try
      if not FQFindFileId.IsEmpty then Result:= FQFindFileId.Fields[0].AsLargeInt;
    finally
      FQFindFileId.Close;
    end;
  end;
end; // function

function TSQLiteSymbolStore.FindSymbolByExactNameAnywhere( const AName: string): TSymbol;
var
  Arr: TArray<TSymbol>;
begin
  Result:= Default               (TSymbol);
  Arr   := FindSymbolsByExactName(AName  );
  if Length(Arr) > 0 then Result:= Arr[0];
end;

function TSQLiteSymbolStore.FindChildSymbolByName(AParentId: Int64; const AName: string): TSymbol;
begin
  Result:= Default(TSymbol);
  if FQFindChildByName.Active then FQFindChildByName.Close;
  FQFindChildByName.ParamByName('pid' ).AsLargeInt:= AParentId;
  FQFindChildByName.ParamByName('name').AsString  := AName;
  FQFindChildByName.Open;
  try
    if not FQFindChildByName.IsEmpty then Result:= ReadSymbolFromQuery(FQFindChildByName);
  finally
    FQFindChildByName.Close;
  end;
end;

// v0.20: completion helpers

function TSQLiteSymbolStore.FindSymbolsByPrefix(const APrefix: string; ALimit: Integer): TArray<TSymbol>;
var
  List         : TList<TSymbol>;
  EscapedPrefix: string        ;
begin
  List:= TList<TSymbol>.Create;
  try
    // Escape LIKE meta-characters in the user-supplied prefix.
    EscapedPrefix:= StringReplace(APrefix      , '\', '\\', [rfReplaceAll]);
    EscapedPrefix:= StringReplace(EscapedPrefix, '%', '\%', [rfReplaceAll]);
    EscapedPrefix:= StringReplace(EscapedPrefix, '_', '\_', [rfReplaceAll]);
    EscapedPrefix:= EscapedPrefix + '%';
    if FQFindByPrefix.Active then FQFindByPrefix.Close;
    FQFindByPrefix.ParamByName('prefixLike').AsString := EscapedPrefix;
    FQFindByPrefix.ParamByName('lim'       ).AsInteger:= ALimit;
    FQFindByPrefix.Open;
    try
      while not FQFindByPrefix.Eof do
      begin
        List.Add(ReadSymbolFromQuery(FQFindByPrefix));
        FQFindByPrefix.Next;
      end;
    finally
      FQFindByPrefix.Close;
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.FindAllChildSymbols( AParentId: Int64): TArray<TSymbol>;
var
  List: TList<TSymbol>;
begin
  List:= TList<TSymbol>.Create;
  try
    if FQFindAllChildren.Active then FQFindAllChildren.Close;
    FQFindAllChildren.ParamByName('pid').AsLargeInt:= AParentId;
    FQFindAllChildren.Open;
    try
      while not FQFindAllChildren.Eof do
      begin
        List.Add(ReadSymbolFromQuery(FQFindAllChildren));
        FQFindAllChildren.Next;
      end;
    finally
      FQFindAllChildren.Close;
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

// v0.25: dead-code finder

function TSQLiteSymbolStore.FindSymbolsWithNoCallers(const AKind: string; AIncludePrivate: Boolean): TArray<TSymbol>;
var
  List: TList<TSymbol>;
begin
  List:= TList<TSymbol>.Create;
  try
    if FQFindNoCallers.Active then FQFindNoCallers.Close;
    FQFindNoCallers.ParamByName('kind').AsString:= AKind;
    FQFindNoCallers.ParamByName('includePrivate').AsInteger:= Ord(AIncludePrivate);
    FQFindNoCallers.Open;
    try
      while not FQFindNoCallers.Eof do
      begin
        List.Add(ReadSymbolFromQuery(FQFindNoCallers));
        FQFindNoCallers.Next;
      end;
    finally
      FQFindNoCallers.Close;
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

// v0.26: compiler diagnostics

function TSQLiteSymbolStore.FindCompilerFindingsForFile( AFileId: Int64): TArray<TCompilerFinding>;
var
  List: TList<TCompilerFinding>;
  F   : TCompilerFinding       ;
begin
  List:= TList<TCompilerFinding>.Create;
  try
    if FQFindCompilerFindings.Active then FQFindCompilerFindings.Close;
    FQFindCompilerFindings.ParamByName('fid').AsLargeInt:= AFileId;
    FQFindCompilerFindings.Open;
    try
      while not FQFindCompilerFindings.Eof do
      begin
        F:= Default(TCompilerFinding);
        if FQFindCompilerFindings.FieldByName('file_id').IsNull then F.FileId:= -1
        else F.FileId:= FQFindCompilerFindings.FieldByName('file_id').AsLargeInt;
        F.RawPath := FQFindCompilerFindings.FieldByName('raw_path').AsString;
        F.Code    := FQFindCompilerFindings.FieldByName('code'    ).AsString;
        F.Severity:= FQFindCompilerFindings.FieldByName('severity').AsString;
        F.LineNo  := FQFindCompilerFindings.FieldByName('line_no' ).AsInteger;
        F.ColNo   := FQFindCompilerFindings.FieldByName('col_no'  ).AsInteger;
        F.Message := FQFindCompilerFindings.FieldByName('message' ).AsString;
        List.Add(F);
        FQFindCompilerFindings.Next;
      end;
    finally
      FQFindCompilerFindings.Close;
    end; // try
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

procedure TSQLiteSymbolStore.ClearCompilerFindings;
begin
  FConn.ExecSQL('DELETE FROM compiler_findings');
end;

procedure TSQLiteSymbolStore.InsertCompilerFinding( const AFinding: TCompilerFinding);
begin
  if AFinding.FileId > 0 then FQInsertCompilerFinding.ParamByName('fid').AsLargeInt:= AFinding.FileId
  else FQInsertCompilerFinding.ParamByName('fid').Clear;
  FQInsertCompilerFinding.ParamByName('rp'  ).AsString := AFinding.RawPath;
  FQInsertCompilerFinding.ParamByName('code').AsString := AFinding.Code;
  FQInsertCompilerFinding.ParamByName('sev' ).AsString := AFinding.Severity;
  FQInsertCompilerFinding.ParamByName('lno' ).AsInteger:= AFinding.LineNo;
  FQInsertCompilerFinding.ParamByName('cno' ).AsInteger:= AFinding.ColNo;
  FQInsertCompilerFinding.ParamByName('msg' ).AsString := AFinding.Message;
  FQInsertCompilerFinding.ParamByName('iat').AsLargeInt:= System.DateUtils.DateTimeToUnix(Now, False);
  FQInsertCompilerFinding.ExecSQL;
end;

// v0.17: blast-radius pack

function TSQLiteSymbolStore.FindTransitiveCallers(const ASymbolName: string; ADepth: Integer): TArray<TImpactLevel>;
const
  CTE_SQL = 'WITH RECURSIVE caller_walk(level, caller_id, caller_name, file_id) AS (' + '  SELECT 1, s2.id, s2.name, s2.file_id ' +
  '    FROM refs r INNER JOIN symbols s2 ON s2.file_id = r.file_id ' + '      AND r.start_line BETWEEN s2.start_line AND s2.end_line ' + '    WHERE r.name_text = :targetName ' +
  '  UNION ' + '  SELECT cw.level + 1, s3.id, s3.name, s3.file_id ' + '    FROM caller_walk cw ' + '    INNER JOIN refs r2 ON r2.name_text = cw.caller_name ' +
  '    INNER JOIN symbols s3 ON s3.file_id = r2.file_id ' + '      AND r2.start_line BETWEEN s3.start_line AND s3.end_line ' + '    WHERE cw.level < :maxDepth' + ') ' +
  'SELECT level, COUNT(DISTINCT caller_id) AS callers, ' + '       COUNT(DISTINCT file_id) AS units ' + '  FROM caller_walk GROUP BY level ORDER BY level';
var
  Q     : TFDQuery           ;
  Levels: TList<TImpactLevel>;
  Lvl   : TImpactLevel       ;
begin
  Q:= TFDQuery.Create(nil);
  Levels:= TList<TImpactLevel>.Create;
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= CTE_SQL;
    Q.ParamByName('targetName').AsString := ASymbolName;
    Q.ParamByName('maxDepth'  ).AsInteger:= ADepth;
    Q.Open;
    while not Q.Eof do
    begin
      Lvl:= Default(TImpactLevel);
      Lvl.Depth      := Q.Fields[0].AsInteger;
      Lvl.CallerCount:= Q.Fields[1].AsInteger;
      Lvl.UnitCount  := Q.Fields[2].AsInteger;
      Levels.Add(Lvl);
      Q.Next;
    end;
    Result:= Levels.ToArray;
  finally
    Q.Free;
    Levels.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.GetClassSurface(const AQName: string; AIncludeImpl, AAllVisibility: Boolean): TArray<TSurfaceLine>;
// Returns the interface-section lines for the class declaration (start_line..
// end_line from the symbol record). This is the class body as declared in the
// interface section of a well-formed Delphi unit; implementation bodies are in
// a separate symbol block and are NOT included unless AIncludeImpl is set.
//
// Visibility filtering (AAllVisibility = False): skips lines whose trimmed
// text is exactly "private" or "strict private". This is a naive line-grep
// heuristic -- a proper implementation would walk child symbols and filter by
// their modifiers field. For v0.17 the simple approach is acceptable.
var
  Syms       : TArray<TSymbol>    ;
  Sym        : TSymbol            ;
  AllLines   : TArray<string>     ;
  i          : Integer            ;
  SurfLine   : TSurfaceLine       ;
  Acc        : TList<TSurfaceLine>;
  FilePath   : string             ;
  TrimmedText: string             ;
  InPrivate  : Boolean            ;
begin
  Result:= nil;
  Syms:= FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then Exit;
  Sym:= Syms[0];
  if not (Sym.Kind in [skClass, skRecord, skInterface]) then Exit;
  FilePath:= GetFilePath(Sym.FileId);
  if not TFile.Exists(FilePath) then Exit;

  // Source files are ANSI-encoded (strict project convention).
  AllLines:= TFile.ReadAllLines(FilePath, TEncoding.ANSI);
  Acc:= TList<TSurfaceLine>.Create;
  try
    InPrivate:= False;
    for i:= Sym.StartLine to Sym.EndLine do
    begin
      if (i < 1) or (i > Length(AllLines)) then Continue;
      TrimmedText:= Trim(AllLines[i - 1]);
      // Track whether we are inside a private/strict private section so that
      // the entire section body can be suppressed when AAllVisibility is False.
      if SameText(TrimmedText, 'private') or SameText(TrimmedText, 'strict private') then
      begin
        InPrivate:= True;
        if not AAllVisibility then Continue;
      end
      else if SameText(TrimmedText, 'public') or SameText(TrimmedText, 'strict public') or SameText(TrimmedText, 'protected') or SameText(TrimmedText, 'strict protected') or
      SameText(TrimmedText, 'published') then InPrivate:= False;

      if InPrivate and (not AAllVisibility) then Continue;

      SurfLine:= Default(TSurfaceLine);
      SurfLine.Kind:= 'source';
      SurfLine.Text:= AllLines[i - 1];
      SurfLine.StartLine:= i;
      SurfLine.EndLine  := i;
      Acc.Add(SurfLine);
    end; // for
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.FindChildSymbols( AParentId: Int64): TArray<TSymbol>;
var
  Q   : TFDQuery      ;
  List: TList<TSymbol>;
begin
  List:= TList<TSymbol>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT * FROM symbols WHERE parent_id = :pid ORDER BY start_line';
    Q.ParamByName('pid').AsLargeInt:= AParentId;
    Q.Open;
    while not Q.Eof do
    begin
      List.Add(ReadSymbolFromQuery(Q));
      Q.Next;
    end;
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end; // try
end; // function

class function TSQLiteSymbolStore.FindImplLine(const ALines: TArray<string>; const APattern: string): Integer;
// Searches for lines matching "procedure|function|constructor|destructor
// ClassName.MethodName" (case-insensitive). APattern should be "ClassName.MethodName".
// Returns the 0-based line index, or -1 if not found.
var
  i          : Integer              ;
  LTrimmed   : string               ;
  LUpper     : string               ;
  LPatUpper  : string               ;
  Prefixes   : array[0..5] of string;
  J          : Integer              ;
  PrefixedPat: string               ;
begin
  LPatUpper:= UpperCase(APattern);
  Prefixes[0]:= 'PROCEDURE ';
  Prefixes[1]:= 'FUNCTION ';
  Prefixes[2]:= 'CONSTRUCTOR ';
  Prefixes[3]:= 'DESTRUCTOR ';
  Prefixes[4]:= 'CLASS PROCEDURE ';
  Prefixes[5]:= 'CLASS FUNCTION ';
  for i:= 0 to High(ALines) do
  begin
    LTrimmed:= Trim(ALines[i]);
    if LTrimmed = '' then Continue;
    LUpper:= UpperCase(LTrimmed);
    for J:= 0 to High(Prefixes) do
    begin
      PrefixedPat:= Prefixes[J] + LPatUpper;
      // Match at start of trimmed line; allow "function TFoo.Bar(" or
      // "function TFoo.Bar;" - so just check that LUpper starts with
      // the prefixed pattern (which includes ClassName.MethodName).
      if Copy(LUpper, 1, Length(PrefixedPat)) = PrefixedPat then Exit(i);
    end;
  end;
  Result:= -1;
end; // function

class function TSQLiteSymbolStore.FindImplEnd(const ALines: TArray<string>; AStartLine: Integer): Integer;
// From AStartLine (0-based), scans forward to find the last line of the
// implementation body. The body ends just before the next top-level
// procedure/function/constructor/destructor/class procedure/class function
// declaration at column 0, or at/before the final "end." line.
//
// Special case: if the very start line itself contains "end;" or "end" at
// the end (single-line body like "begin Result := X; end;"), we return
// AStartLine immediately after scanning until the begin..end is closed.
//
// v0.17 limitation: the heuristic may include or exclude lines if the
// source uses unusual indentation or multiple begin..end blocks per line.
var
  i               : Integer              ;
  LTrimmed        : string               ;
  LUpper          : string               ;
  TopLevelPrefixes: array[0..5] of string;
  J               : Integer              ;
  IsTopLevel      : Boolean              ;
begin
  TopLevelPrefixes[0]:= 'PROCEDURE ';
  TopLevelPrefixes[1]:= 'FUNCTION ';
  TopLevelPrefixes[2]:= 'CONSTRUCTOR ';
  TopLevelPrefixes[3]:= 'DESTRUCTOR ';
  TopLevelPrefixes[4]:= 'CLASS PROCEDURE ';
  TopLevelPrefixes[5]:= 'CLASS FUNCTION ';

  // Scan from the line AFTER the header line (AStartLine itself is the decl).
  // Walk until we hit a top-level decl, "end.", or EOF.
  for i:= AStartLine + 1 to High(ALines) do
  begin
    LTrimmed:= Trim(ALines[i]);
    LUpper:= UpperCase(LTrimmed);

    // Check for unit footer "end."
    if LUpper = 'END.' then Exit(i - 1);

    // Check for next top-level declaration (starts at column 0, i.e. the
    // raw line has no leading whitespace before the keyword).
    if (Length(ALines[i]) > 0) and not CharInSet(ALines[i][1], [' ', #9]) then
    begin
      IsTopLevel:= False;
      for J:= 0 to High(TopLevelPrefixes) do
      begin
        if Copy(LUpper, 1, Length(TopLevelPrefixes[J])) = TopLevelPrefixes[J] then
        begin
          IsTopLevel:= True;
          Break;
        end;
      end;
      if IsTopLevel then Exit(i - 1);
    end;
  end; // for
  // Reached end of file
  if High(ALines) >= AStartLine then Result:= High(ALines)
  else Result:= AStartLine;
end; // function

function TSQLiteSymbolStore.GetSymbolSlice(const AQName: string): TArray<TSliceChunk>;
// Returns symbol-relevant chunks of the source unit:
//   1. unit-header: lines 1..interface-line
//   2. class-decl: class symbol's start_line..end_line
//   3. impl-method: implementation body for each method child of the class
//   4. unit-trailer: the "end." line
//
// Limitation: FindImplEnd uses a heuristic that may over- or under-include
// lines if source formatting is unusual. Acceptable for v0.17 on standard
// Delphi fixtures. Children with no matching impl (e.g. abstract methods)
// are silently skipped. Empty children list is handled gracefully.
var
  Syms         : TArray<TSymbol>   ;
  ClassSym     : TSymbol           ;
  AllLines     : TArray<string>    ;
  FilePath     : string            ;
  Chunks       : TList<TSliceChunk>;
  Chunk        : TSliceChunk       ;
  i            : Integer           ;
  InterfaceLine: Integer           ;
  Children     : TArray<TSymbol>   ;
  Child        : TSymbol           ;
  ImplPattern  : string            ;
  ImplLine     : Integer           ;
  ImplEndLine  : Integer           ;
  TrailerLine  : Integer           ;
  LineCount    : Integer           ;

  function JoinLines(AFrom, ATo: Integer): string;
  var
    Parts: TStringList;
    K    : Integer    ;
  begin
    Parts:= TStringList.Create;
    try
      for K:= AFrom to ATo do
        if (K >= 0) and (K <= High(AllLines)) then Parts.Add(AllLines[K]);
      Result:= Parts.Text;
      // TStringList.Text always appends a trailing CRLF; trim it.
      Result:= Result.TrimRight([#13, #10]);
    finally
      Parts.Free;
    end;
  end;

begin
  Result:= nil;
  Syms:= FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then Exit;
  ClassSym:= Syms[0];
  FilePath:= GetFilePath(ClassSym.FileId);
  if not TFile.Exists(FilePath) then Exit;

  AllLines:= TFile.ReadAllLines(FilePath, TEncoding.ANSI);
  LineCount:= Length(AllLines);
  if LineCount = 0 then Exit;

  Chunks:= TList<TSliceChunk>.Create;
  try
    // 1. Unit header: lines 0..(InterfaceLine) in 0-based; 1..(InterfaceLine+1) 1-based.
    //    Find the line that is exactly "interface" (trimmed, case-insensitive).
    InterfaceLine:= 0;
    for i:= 0 to High(AllLines) do
      if SameText(Trim(AllLines[i]), 'interface') then
      begin
        InterfaceLine:= i;
        Break;
      end;
    Chunk:= Default(TSliceChunk);
    Chunk.Kind     := 'unit-header';
    Chunk.StartLine:= 1;
    Chunk.EndLine:= InterfaceLine + 1;
    Chunk.Text:= JoinLines(0, InterfaceLine);
    Chunks.Add(Chunk);

    // 2. Class declaration: ClassSym.StartLine..EndLine (1-based in DB).
    Chunk:= Default(TSliceChunk);
    Chunk.Kind:= 'class-decl';
    Chunk.StartLine:= ClassSym.StartLine;
    Chunk.EndLine  := ClassSym.EndLine;
    Chunk.Text:= JoinLines(ClassSym.StartLine - 1, ClassSym.EndLine - 1);
    Chunks.Add(Chunk);

    // 3. Implementation bodies for each method child of the class.
    Children:= FindChildSymbols(ClassSym.Id);
    for Child in Children do
    begin
      if not (Child.Kind in [skMethod, skProcedure, skFunction, skConstructor, skDestructor]) then Continue;
      // Build pattern "ClassName.MethodName" for the impl finder.
      ImplPattern:= ClassSym.Name + '.' + Child.Name;
      ImplLine:= FindImplLine(AllLines, ImplPattern);
      if ImplLine < 0 then Continue;
      ImplEndLine:= FindImplEnd(AllLines, ImplLine);
      // Clamp to valid range
      if ImplEndLine < ImplLine then ImplEndLine:= ImplLine;
      if ImplEndLine >= LineCount then ImplEndLine:= LineCount - 1;
      Chunk:= Default(TSliceChunk);
      Chunk.Kind:= 'impl-method';
      Chunk.StartLine:= ImplLine    + 1;
      Chunk.EndLine  := ImplEndLine + 1;
      Chunk.Text:= JoinLines(ImplLine, ImplEndLine);
      Chunks.Add(Chunk);
    end; // for

    // 4. Unit trailer: find the "end." line (0-based search from the end).
    TrailerLine:= LineCount - 1;
    for i:= High(AllLines) downto 0 do
      if SameText(Trim(AllLines[i]), 'end.') then
      begin
        TrailerLine:= i;
        Break;
      end;
    Chunk:= Default(TSliceChunk);
    Chunk.Kind:= 'unit-trailer';
    Chunk.StartLine:= TrailerLine + 1;
    Chunk.EndLine  := TrailerLine + 1;
    Chunk.Text:= Trim(AllLines[TrailerLine]);
    Chunks.Add(Chunk);

    Result:= Chunks.ToArray;
  finally
    Chunks.Free;
  end; // try
end; // begin

function TSQLiteSymbolStore.FindCallersByNameWithContext(const ACalleeName: string; AContextLines: Integer): TArray<TReference>;
var
  Refs       : TArray<TReference>;
  i          : Integer           ;
  J          : Integer           ;
  FilePath   : string            ;
  StartIdx   : Integer           ;
  EndIdx     : Integer           ;
  CachedPath : string            ;
  CachedLines: TArray<string>    ;
  CtxBuilder : TStringBuilder    ;
begin
  // Get all callers first
  Refs:= FindCallersByName(ACalleeName);

  // If no context requested or no callers, return as-is
  if (AContextLines <= 0) or (Length(Refs) = 0) then
  begin
    Result:= Refs;
    Exit;
  end;

  // For each reference, read surrounding context lines
  CachedPath:= '';
  SetLength(CachedLines, 0);
  CtxBuilder:= TStringBuilder.Create;
  try
    for i:= Low(Refs) to High(Refs) do
    begin
      FilePath:= GetFilePath(Refs[i].FileId);

      // Cache: if we're reading a different file, re-read it
      if FilePath <> CachedPath then
      begin
        CachedPath:= FilePath;
        if TFile.Exists(FilePath) then CachedLines:= TFile.ReadAllLines(FilePath, TEncoding.ANSI)
        else SetLength(CachedLines, 0);
      end;

      // Extract context: (line - N) to (line + N), 1-indexed
      // Refs[I].StartLine is 1-indexed, array access is 0-indexed
      StartIdx:= Max(0, Refs[i].StartLine - AContextLines - 1);
      EndIdx:= Min(High(CachedLines), Refs[i].StartLine + AContextLines - 1);

      // Build context text with line numbers
      CtxBuilder.Clear;
      if (Length(CachedLines) > 0) and (StartIdx <= EndIdx) and (StartIdx <= High(CachedLines)) then
      begin
        for J:= StartIdx to EndIdx do
        begin
          if (J >= 0) and (J <= High(CachedLines)) then
          begin
            if CtxBuilder.Length > 0 then CtxBuilder.AppendLine;
            CtxBuilder.Append(Format('%5d: %s', [J + 1, CachedLines[J]]));
          end;
        end;
      end;

      // Store context in the reference
      Refs[i].ContextText:= CtxBuilder.ToString;
    end; // for
  finally
    CtxBuilder.Free;
  end; // try

  Result:= Refs;
end; // function

function TSQLiteSymbolStore.GetConnection: TFDConnection;
begin
  Result:= FConn;
end;

{ ---- v0.40.4: unit_uses ---------------------------------------------------- }

function UnitNameNorm(const AUnitName: string): string;
{ Returns the lowercased trailing dotted segment of a unit name. For
  'System.SysUtils' returns 'sysutils'. Used as the join key against the
  basename-stem of files.path so target resolution stays simple. }
var
  Dot: Integer;
begin
  Result:= AUnitName;
  Dot:= LastDelimiter('.', Result);
  if Dot > 0 then Result:= Copy(Result, Dot + 1, MaxInt);
  Result:= LowerCase(Result);
end;

procedure TSQLiteSymbolStore.UpsertUnitUse(const AToken: TFileTxToken; const AUse: TUnitUse);
begin
  FQInsertUnitUse.ParamByName('fid').AsLargeInt:= AToken.FileId;
  FQInsertUnitUse.ParamByName('un' ).AsString  := AUse  .UnitName;
  FQInsertUnitUse.ParamByName('unn').AsString:= UnitNameNorm       (AUse.UnitName);
  FQInsertUnitUse.ParamByName('sec').AsString:= UnitUseSectionToStr(AUse.Section );
  if AUse.InPath = '' then FQInsertUnitUse.ParamByName('inp').Clear
  else FQInsertUnitUse.ParamByName('inp').AsString:= AUse.InPath;
  FQInsertUnitUse.ParamByName('sl').AsInteger:= AUse.StartLine;
  FQInsertUnitUse.ParamByName('sc').AsInteger:= AUse.StartCol;
  FQInsertUnitUse.ParamByName('el').AsInteger:= AUse.EndLine;
  FQInsertUnitUse.ParamByName('ec').AsInteger:= AUse.EndCol;
  FQInsertUnitUse.ExecSQL;
end;

procedure TSQLiteSymbolStore.DeleteUnitUsesForFile(AFileId: Int64);
begin
  FQDeleteFileUnitUses.ParamByName('fid').AsLargeInt:= AFileId;
  FQDeleteFileUnitUses.ExecSQL;
end;

function TSQLiteSymbolStore.GetUnitUsesForFile( AFileId: Int64): TArray<TUnitUse>;
var
  List: TList<TUnitUse>;
  U   : TUnitUse       ;
begin
  List:= TList<TUnitUse>.Create;
  try
    FQGetFileUnitUses.ParamByName('fid').AsLargeInt:= AFileId;
    FQGetFileUnitUses.Open;
    try
      while not FQGetFileUnitUses.Eof do
      begin
        U.FileId:= AFileId;
        U.UnitName:= FQGetFileUnitUses.FieldByName('unit_name').AsString;
        U.Section:= StrToUnitUseSection( FQGetFileUnitUses.FieldByName('section').AsString);
        U.InPath   := FQGetFileUnitUses.FieldByName('in_path'   ).AsString;
        U.StartLine:= FQGetFileUnitUses.FieldByName('start_line').AsInteger;
        U.StartCol := FQGetFileUnitUses.FieldByName('start_col' ).AsInteger;
        U.EndLine  := FQGetFileUnitUses.FieldByName('end_line'  ).AsInteger;
        U.EndCol   := FQGetFileUnitUses.FieldByName('end_col'   ).AsInteger;
        List.Add(U);
        FQGetFileUnitUses.Next;
      end;
    finally
      FQGetFileUnitUses.Close;
    end; // try
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

function TSQLiteSymbolStore.FindUsersOfUnit( const AUnitNameNorm: string): TArray<TUnitUse>;
var
  List: TList<TUnitUse>;
  U   : TUnitUse       ;
begin
  List:= TList<TUnitUse>.Create;
  try
    FQFindUsersOfUnit.ParamByName('un').AsString:= LowerCase(AUnitNameNorm);
    FQFindUsersOfUnit.Open;
    try
      while not FQFindUsersOfUnit.Eof do
      begin
        U.FileId  := FQFindUsersOfUnit.FieldByName('file_id'  ).AsLargeInt;
        U.UnitName:= FQFindUsersOfUnit.FieldByName('unit_name').AsString;
        U.Section:= StrToUnitUseSection( FQFindUsersOfUnit.FieldByName('section').AsString);
        U.InPath   := FQFindUsersOfUnit.FieldByName('in_path'   ).AsString;
        U.StartLine:= FQFindUsersOfUnit.FieldByName('start_line').AsInteger;
        U.StartCol := FQFindUsersOfUnit.FieldByName('start_col' ).AsInteger;
        U.EndLine  := FQFindUsersOfUnit.FieldByName('end_line'  ).AsInteger;
        U.EndCol   := FQFindUsersOfUnit.FieldByName('end_col'   ).AsInteger;
        List.Add(U);
        FQFindUsersOfUnit.Next;
      end;
    finally
      FQFindUsersOfUnit.Close;
    end; // try
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

procedure TSQLiteSymbolStore.ResolveUnitUseTargets;
{ Drives target_file_id resolution in Pascal rather than SQL because the
  basename-extract is fiddly across sqlite dialects (Win32 FireDAC's
  bundled sqlite lacks some 3.24+ functions). We pull every (file_id, path),
  compute the lowercase stem, build a dictionary, then UPDATE per group. }
var
  QFiles      : TFDQuery                  ;
  QUpdate     : TFDQuery                  ;
  StemToFileId: TDictionary<string, Int64>;
  Path        : string                    ;
  Stem        : string                    ;
  Slash       : Integer                   ;
begin
  StemToFileId:= TDictionary<string, Int64>.Create;
  QFiles := TFDQuery.Create(nil);
  QUpdate:= TFDQuery.Create(nil);
  try
    QFiles.Connection:= FConn;
    QFiles.SQL.Text:= 'SELECT id, path FROM files';
    QFiles.Open;
    while not QFiles.Eof do
    begin
      Path:= QFiles.FieldByName('path').AsString;
      Slash:= Path.LastDelimiter('\/');
      if Slash >= 0 then Stem:= Copy(Path, Slash + 2, MaxInt)
      else Stem:= Path;
      Stem:= LowerCase(ChangeFileExt(Stem, ''));
      if Stem <> '' then StemToFileId.AddOrSetValue(Stem, QFiles.FieldByName('id').AsLargeInt);
      QFiles.Next;
    end;
    QFiles.Close;

    QUpdate.Connection:= FConn;
    QUpdate.SQL.Text:= 'UPDATE unit_uses SET target_file_id = :tid ' + 'WHERE unit_name_norm = :un AND target_file_id IS NULL';
    QUpdate.Params.ParamByName('tid').DataType:= ftLargeint;
    QUpdate.Params.ParamByName('un' ).DataType:= ftString;
    QUpdate.Prepare;
    for var Kvp in StemToFileId do
    begin
      QUpdate.ParamByName('tid').AsLargeInt:= Kvp.Value;
      QUpdate.ParamByName('un' ).AsString  := Kvp.Key;
      QUpdate.ExecSQL;
    end;
  finally
    QUpdate.Free;
    QFiles.Free;
    StemToFileId.Free;
  end; // try
end; // procedure

// v11 (M1): normalize one raw heritage ancestor token to a name comparable to
// symbols.name: trim, drop a generic argument list (TList<TFoo> -> TList) and
// take the dotted tail (System.Classes.TComponent -> TComponent).
function NormalizeAncestorName(const ARaw: string): string;
var
  S: string ;
  P: Integer;
begin
  S:= Trim(ARaw);
  P:= Pos('<', S);
  if P > 0 then S:= Trim(Copy(S, 1, P - 1));
  P:= LastDelimiter('.', S);
  if P > 0 then S:= Copy(S, P + 1, MaxInt);
  Result:= Trim(S);
end;

// v11 (M1): split a heritage list on top-level commas only, so a generic
// ancestor's own comma (TDictionary<string, Integer>) does not split it.
function SplitHeritageList(const AHeritage: string): TArray<string>;
var
  Parts: TList<string>;
  i    : Integer      ;
  Depth: Integer      ;
  Start: Integer      ;
  Ch   : Char         ;
begin
  Parts:= TList<string>.Create;
  try
    Depth:= 0;
    Start:= 1;
    for i:= 1 to Length(AHeritage) do
    begin
      Ch:= AHeritage[i];
      if Ch = '<' then Inc(Depth)
      else if Ch = '>' then Dec(Depth)
      else if (Ch = ',') and (Depth <= 0) then
      begin
        Parts.Add(Copy(AHeritage, Start, i - Start));
        Start:= i + 1;
      end;
    end;
    if Start <= Length(AHeritage) then Parts.Add(Copy(AHeritage, Start, MaxInt));
    Result:= Parts.ToArray;
  finally
    Parts.Free;
  end;
end;

// v11 (M1): map an intrinsic (RTL built-in) type name to its category, or
// tcUnknown when AName is not an intrinsic. P-prefixed names (PChar, PFoo) are
// treated as pointers, matching the win64-pointer-cast intrinsic set.
function IntrinsicCategory(const AName: string): TTypeCategory;
  function Eq(const A: string): Boolean;
  begin
    Result:= SameText(AName, A);
  end;
begin
  if Eq('Double') or Eq('Single') or Eq('Extended') or Eq('Real') or Eq('Real48') or Eq('Currency') or Eq('Comp') then Exit(tcFloat);
  if Eq('string') or Eq('AnsiString') or Eq('UnicodeString') or Eq('WideString') or Eq('ShortString') or Eq('RawByteString') or Eq('UTF8String') then Exit(tcString);
  if Eq('Char') or Eq('WideChar') or Eq('AnsiChar') or Eq('UCS2Char') or Eq('UCS4Char') then Exit(tcChar);
  if Eq('Boolean') or Eq('ByteBool') or Eq('WordBool') or Eq('LongBool') then Exit(tcBoolean);
  if Eq('Integer') or Eq('Cardinal') or Eq('Int64') or Eq('UInt64') or Eq('Byte') or Eq('Word') or Eq('SmallInt') or Eq('ShortInt') or Eq('LongInt') or Eq('LongWord') or
     Eq('NativeInt') or Eq('NativeUInt') or Eq('Int8') or Eq('Int16') or Eq('Int32') or Eq('UInt8') or Eq('UInt16') or Eq('UInt32') or Eq('FixedInt') or Eq('FixedUInt') then Exit(tcOrdinal);
  if Eq('Pointer') then Exit(tcPointer);
  if (Length(AName) >= 2) and CharInSet(AName[1], ['P', 'p']) and CharInSet(AName[2], ['A'..'Z']) then Exit(tcPointer);
  Result:= tcUnknown;
end;

procedure TSQLiteSymbolStore.ResolveAncestry;
{ Whole-DB pass: for each class/interface with heritage text, split it, resolve
  each ancestor to a defining class/interface symbol (preferring one in scope of
  the declaring file via the unit_uses graph), and rebuild type_ancestors.
  Mirrors ResolveUnitUseTargets: pull everything, resolve in memory, batch write. }
var
  Q          : TFDQuery                            ;
  QIns       : TFDQuery                            ;
  NameToCands: TObjectDictionary<string, TList<TSymbol>>;
  FileScope  : TObjectDictionary<Int64,  TList<Int64>>  ;
  Lc         : string                             ;
  Sym        : TSymbol                            ;

  function CandInScope(ADeclFile, ACandFile: Int64): Boolean;
  var L: TList<Int64>;
  begin
    Result:= (ADeclFile = ACandFile);
    if Result then Exit;
    if FileScope.TryGetValue(ADeclFile, L) then Result:= L.IndexOf(ACandFile) >= 0;
  end;

begin
  NameToCands:= TObjectDictionary<string, TList<TSymbol>>.Create([doOwnsValues]);
  FileScope  := TObjectDictionary<Int64,  TList<Int64>>.Create([doOwnsValues]);
  Q   := TFDQuery.Create(nil);
  QIns:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    { 1. candidate class/interface symbols, indexed by lowercased simple name. }
    Q.SQL.Text:= 'SELECT id, file_id, kind, name FROM symbols WHERE kind IN (''class'',''interface'')';
    Q.Open;
    while not Q.Eof do
    begin
      Sym:= Default(TSymbol);
      Sym.Id    := Q.FieldByName('id'     ).AsLargeInt;
      Sym.FileId:= Q.FieldByName('file_id').AsLargeInt;
      Sym.Kind  := TSymbolKind.FromText(Q.FieldByName('kind').AsString);
      Sym.Name  := Q.FieldByName('name'   ).AsString;
      Lc:= LowerCase(Sym.Name);
      if not NameToCands.ContainsKey(Lc) then NameToCands.Add(Lc, TList<TSymbol>.Create);
      NameToCands[Lc].Add(Sym);
      Q.Next;
    end;
    Q.Close;
    { 2. per-file in-scope set: the resolved target_file_id of each used unit. }
    Q.SQL.Text:= 'SELECT file_id, target_file_id FROM unit_uses WHERE target_file_id IS NOT NULL';
    Q.Open;
    while not Q.Eof do
    begin
      var Fid:= Q.FieldByName('file_id'       ).AsLargeInt;
      var Tid:= Q.FieldByName('target_file_id').AsLargeInt;
      if not FileScope.ContainsKey(Fid) then FileScope.Add(Fid, TList<Int64>.Create);
      FileScope[Fid].Add(Tid);
      Q.Next;
    end;
    Q.Close;
    { 3. rebuild edges from scratch (simple + correct; whole-DB). }
    QIns.Connection:= FConn;
    QIns.SQL.Text  := 'INSERT INTO type_ancestors(symbol_id, ordinal, ancestor_name, ' +
                      '  ancestor_kind, ancestor_symbol_id, ancestor_file_id) ' +
                      'VALUES (:sid, :ord, :an, :ak, :asid, :afid)';
    QIns.Params.ParamByName('asid').DataType:= ftLargeint;
    QIns.Params.ParamByName('afid').DataType:= ftLargeint;
    Q.SQL.Text:= 'SELECT id, file_id, heritage FROM symbols ' +
                 'WHERE kind IN (''class'',''interface'') AND heritage IS NOT NULL AND heritage <> ''''';
    FConn.StartTransaction;
    try
      FConn.ExecSQL('DELETE FROM type_ancestors');
      Q.Open;
      while not Q.Eof do
      begin
        var SymId  := Q.FieldByName('id'      ).AsLargeInt;
        var SymFile:= Q.FieldByName('file_id' ).AsLargeInt;
        var Tokens := SplitHeritageList(Q.FieldByName('heritage').AsString);
        for var Ord:= 0 to High(Tokens) do
        begin
          var AncName:= NormalizeAncestorName(Tokens[Ord]);
          if AncName = '' then Continue;
          var RSymId : Int64  := 0;
          var RFileId: Int64  := 0;
          var RKind  : string := '?';
          var Cands  : TList<TSymbol>;
          if NameToCands.TryGetValue(LowerCase(AncName), Cands) then
          begin
            var InScopeIdx  := -1;
            var InScopeCount:= 0;
            for var ci:= 0 to Cands.Count - 1 do
              if CandInScope(SymFile, Cands[ci].FileId) then
              begin
                Inc(InScopeCount);
                if InScopeIdx < 0 then InScopeIdx:= ci;
              end;
            { Resolve when unambiguous: exactly one in-scope candidate, or (none
              in scope) a single global definition. Otherwise leave unresolved
              (FP policy: when unsure, don't claim). }
            if InScopeCount = 1 then
            begin
              RSymId := Cands[InScopeIdx].Id;
              RFileId:= Cands[InScopeIdx].FileId;
              RKind  := Cands[InScopeIdx].Kind.ToText;
            end
            else if (InScopeCount = 0) and (Cands.Count = 1) then
            begin
              RSymId := Cands[0].Id;
              RFileId:= Cands[0].FileId;
              RKind  := Cands[0].Kind.ToText;
            end;
          end;
          QIns.ParamByName('sid').AsLargeInt:= SymId;
          QIns.ParamByName('ord').AsInteger := Ord;
          QIns.ParamByName('an' ).AsString  := AncName;
          QIns.ParamByName('ak' ).AsString  := RKind;
          if RSymId > 0 then
          begin
            QIns.ParamByName('asid').AsLargeInt:= RSymId;
            QIns.ParamByName('afid').AsLargeInt:= RFileId;
          end
          else
          begin
            QIns.ParamByName('asid').Clear;
            QIns.ParamByName('afid').Clear;
          end;
          QIns.ExecSQL;
        end;
        Q.Next;
      end;
      Q.Close;
      FConn.Commit;
    except
      FConn.Rollback;
      raise;
    end;
  finally
    QIns.Free;
    Q.Free;
    NameToCands.Free;
    FileScope.Free;
  end; // try
end; // procedure

procedure TSQLiteSymbolStore.ResolveCallTargets;
{ v14 (D5): whole-DB call-resolution pass. Mirrors ResolveAncestry's structure
  (wipe the table, resolve in memory, batch-write in one transaction). Builds one
  TCallResolver (its name/scope maps cost O(symbols) to build ONCE), then streams
  every 'call' ref through ResolveOne. Non-resolving sites (Edge.TargetSymbolId=0)
  get NO row -- the FP-conservative '?' bucket. UpsertCallEdge writes via the
  prepared FQInsertCallEdge; its AToken is unused (call_edges stores no file id),
  so a default token is passed. The whole loop runs in one transaction: thousands
  of refs at per-row autocommit would be pathologically slow. }
var
  Resolver: TCallResolver ;
  Q       : TFDQuery      ;
  Ref     : TReference    ;
  Edge    : TCallEdge     ;
  DummyTok: TFileTxToken  ;
  Written : Int64         ;
begin
  ClearCallEdges; // rebuild every edge each run (like ResolveAncestry's DELETE)
  DummyTok:= Default(TFileTxToken);
  Written := 0;
  Resolver:= TCallResolver.Create(Self); // prepare name/scope maps ONCE
  Q       := TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    { Only 'call'-kind refs are call sites (the parser emits kind='call' for every
      invocation, dotted or bare). Filtering here is faster + cleaner than letting
      ResolveOne return Target=0 for every non-call ref. }
    Q.SQL.Text:=
      'SELECT id, symbol_id, file_id, kind, name_text, start_line, start_col, ' +
      '  end_line, end_col, enclosing_symbol_id FROM refs WHERE kind = ''call''';
    FConn.StartTransaction;
    try
      Q.Open;
      while not Q.Eof do
      begin
        Ref:= Default(TReference);
        Ref.Id:= Q.FieldByName('id').AsLargeInt;
        if not Q.FieldByName('symbol_id').IsNull then Ref.SymbolId:= Q.FieldByName('symbol_id').AsLargeInt;
        Ref.FileId   := Q.FieldByName('file_id'   ).AsLargeInt;
        Ref.Kind     := Q.FieldByName('kind'      ).AsString;
        Ref.NameText := Q.FieldByName('name_text' ).AsString;
        Ref.StartLine:= Q.FieldByName('start_line').AsInteger;
        Ref.StartCol := Q.FieldByName('start_col' ).AsInteger;
        Ref.EndLine  := Q.FieldByName('end_line'  ).AsInteger;
        Ref.EndCol   := Q.FieldByName('end_col'   ).AsInteger;
        if not Q.FieldByName('enclosing_symbol_id').IsNull then
          Ref.EnclosingSymbolId:= Q.FieldByName('enclosing_symbol_id').AsLargeInt;

        Edge:= Resolver.ResolveOne(Ref);
        if Edge.TargetSymbolId > 0 then
        begin
          Edge.RefId:= Ref.Id; // ensure the natural key is the ref we resolved
          UpsertCallEdge(DummyTok, Edge);
          Inc(Written);
        end;
        Q.Next;
      end;
      Q.Close;
      FConn.Commit;
    except
      FConn.Rollback;
      raise;
    end;
  finally
    Q.Free;
    Resolver.Free;
  end; // try
end; // procedure

function TSQLiteSymbolStore.GetTransitiveAncestors(ASymbolId: Int64): TArray<TTypeAncestor>;
{ BFS over type_ancestors. Resolved edges are expanded (recurse into the
  ancestor's own edges); unresolved edges are name-only leaves. A per-name Seen
  set dedups + breaks cycles; a per-symbol expand set + hop cap bound the walk. }
var
  Acc      : TList<TTypeAncestor>      ;
  Seen     : TDictionary<string, Boolean>;
  Expanded : TDictionary<Int64, Boolean> ;
  Queue    : TQueue<Int64>             ;
  Q        : TFDQuery                  ;
  Hops     : Integer                   ;
begin
  Acc     := TList<TTypeAncestor>.Create;
  Seen    := TDictionary<string, Boolean>.Create;
  Expanded:= TDictionary<Int64, Boolean>.Create;
  Queue   := TQueue<Int64>.Create;
  Q       := TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text  := 'SELECT ordinal, ancestor_name, ancestor_kind, ancestor_symbol_id, ' +
                   '  ancestor_file_id FROM type_ancestors WHERE symbol_id = :sid ORDER BY ordinal';
    Queue.Enqueue(ASymbolId);
    Expanded.AddOrSetValue(ASymbolId, True);
    Hops:= 0;
    while (Queue.Count > 0) and (Hops < 64) do
    begin
      Inc(Hops);
      var Cur:= Queue.Dequeue;
      var Direct: TArray<TTypeAncestor>;
      SetLength(Direct, 0);
      Q.ParamByName('sid').AsLargeInt:= Cur;
      Q.Open;
      while not Q.Eof do
      begin
        var A: TTypeAncestor;
        A.Ordinal := Q.FieldByName('ordinal'      ).AsInteger;
        A.Name    := Q.FieldByName('ancestor_name').AsString;
        A.Kind    := Q.FieldByName('ancestor_kind').AsString;
        A.Resolved:= not Q.FieldByName('ancestor_symbol_id').IsNull;
        if A.Resolved then
        begin
          A.SymbolId:= Q.FieldByName('ancestor_symbol_id').AsLargeInt;
          A.FileId  := Q.FieldByName('ancestor_file_id'  ).AsLargeInt;
        end
        else
        begin
          A.SymbolId:= 0;
          A.FileId  := 0;
        end;
        Direct:= Direct + [A];
        Q.Next;
      end;
      Q.Close;
      for var A in Direct do
      begin
        var Key:= LowerCase(A.Name);
        if not Seen.ContainsKey(Key) then
        begin
          Seen.Add(Key, True);
          Acc.Add(A);
        end;
        if A.Resolved and (A.SymbolId > 0) and not Expanded.ContainsKey(A.SymbolId) then
        begin
          Expanded.Add(A.SymbolId, True);
          Queue.Enqueue(A.SymbolId);
        end;
      end;
    end; // while
    Result:= Acc.ToArray;
  finally
    Q.Free;
    Queue.Free;
    Expanded.Free;
    Seen.Free;
    Acc.Free;
  end; // try
end; // function

// Resolve a type name to its defining class/interface/record symbol id,
// preferring a definition in AFileId when given. 0 if none.
function TSQLiteSymbolStore.ResolveTypeSymbolId(const AName: string; AFileId: Int64): Int64;
var
  Cands: TArray<TSymbol>;
  S    : TSymbol        ;
begin
  Result:= 0;
  Cands := FindSymbolsByExactName(AName);
  for S in Cands do
    if S.Kind in [skClass, skInterface, skRecord] then
    begin
      if (AFileId > 0) and (S.FileId = AFileId) then Exit(S.Id);
      if Result = 0 then Result:= S.Id;
    end;
end;

function TSQLiteSymbolStore.IsDescendantOf(const AClassName, AAncestorName: string; AFileId: Int64): Boolean;
var
  StartId: Int64                ;
  A      : TTypeAncestor        ;
begin
  Result := False;
  StartId:= ResolveTypeSymbolId(AClassName, AFileId);
  if StartId <= 0 then Exit;
  for A in GetTransitiveAncestors(StartId) do
    if SameText(A.Name, AAncestorName) then Exit(True);
end;

function TSQLiteSymbolStore.ImplementsInterface(const AClassName, AInterfaceName: string; AFileId: Int64): Boolean;
var
  StartId: Int64                ;
  A      : TTypeAncestor        ;
begin
  Result := False;
  StartId:= ResolveTypeSymbolId(AClassName, AFileId);
  if StartId <= 0 then Exit;
  for A in GetTransitiveAncestors(StartId) do
    if SameText(A.Name, AInterfaceName) and SameText(A.Kind, 'interface') then Exit(True);
end;

function TSQLiteSymbolStore.ResolveTypeCategoryDepth(const ATypeName: string; AFileId: Int64; ADepth: Integer): TTypeCategory;
var
  N       : string        ;
  Best    : TSymbol       ;
  HaveBest: Boolean       ;
  S       : TSymbol       ;
begin
  Result:= tcUnknown;
  N:= NormalizeAncestorName(ATypeName);
  if N = '' then Exit;
  { 1. intrinsics first (cheap, authoritative). }
  Result:= IntrinsicCategory(N);
  if Result <> tcUnknown then Exit;
  { 2. declared type symbol; chase aliases (cap depth to avoid cycles). }
  if ADepth > 8 then Exit;
  HaveBest:= False;
  for S in FindSymbolsByExactName(N) do
    if S.Kind in [skClass, skInterface, skEnum, skRecord, skTypeAlias] then
    begin
      if (AFileId > 0) and (S.FileId = AFileId) then begin Best:= S; HaveBest:= True; Break; end;
      if not HaveBest then begin Best:= S; HaveBest:= True; end;
    end;
  if not HaveBest then Exit(tcUnknown);
  case Best.Kind of
    skClass    : Result:= tcClass;
    skInterface: Result:= tcInterface;
    skEnum     : Result:= tcEnum;
    skRecord   : Result:= tcRecord;
    skTypeAlias: Result:= ResolveTypeCategoryDepth(Best.Signature, AFileId, ADepth + 1);
  end;
end;

function TSQLiteSymbolStore.ResolveTypeCategory(const ATypeName: string; AFileId: Int64): TTypeCategory;
begin
  Result:= ResolveTypeCategoryDepth(ATypeName, AFileId, 0);
end;

function TSQLiteSymbolStore.GetVirtualMethodsIncludingAncestors(const AClassName: string; AFileId: Int64): TArray<string>;
var
  StartId: Int64                       ;
  Names  : TDictionary<string, Boolean>;
  Q      : TFDQuery                    ;
  A      : TTypeAncestor               ;

  procedure CollectFor(ASymId: Int64);
  begin
    if ASymId <= 0 then Exit;
    Q.ParamByName('pid').AsLargeInt:= ASymId;
    Q.Open;
    while not Q.Eof do
    begin
      Names.AddOrSetValue(LowerCase(Q.FieldByName('name').AsString), True);
      Q.Next;
    end;
    Q.Close;
  end;

begin
  Names:= TDictionary<string, Boolean>.Create;
  Q    := TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text  := 'SELECT name FROM symbols WHERE parent_id = :pid AND is_virtual = 1';
    StartId:= ResolveTypeSymbolId(AClassName, AFileId);
    if StartId > 0 then
    begin
      CollectFor(StartId);
      { GetTransitiveAncestors returns a fully-materialized array (its own cursor
        is closed), so reusing Q in CollectFor afterwards is safe. }
      for A in GetTransitiveAncestors(StartId) do
        if A.Resolved and (A.SymbolId > 0) then CollectFor(A.SymbolId);
    end;
    Result:= Names.Keys.ToArray;
  finally
    Q.Free;
    Names.Free;
  end;
end;

end.
