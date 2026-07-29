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
      // v(ADP2 T1): symbol_facts (index-time analysis facts) storage.
      FQPutSymbolFacts       : TFDQuery     ;
      FQGetSymbolFacts       : TFDQuery     ;
      FQFindByDocTag         : TFDQuery     ;
      FQFindUndocumented     : TFDQuery     ;
      FQFindByDocContains    : TFDQuery     ;
      FQListDocumentedSymbols: TFDQuery     ;
      FQFindContaining       : TFDQuery     ;
      FQFindFileId           : TFDQuery     ;
      FQFindChildByName      : TFDQuery     ;
      FQFindEnclRoutine      : TFDQuery     ;
      FQFindByPrefix         : TFDQuery     ;
      FQFindAllChildren      : TFDQuery     ;
      FQFindNoCallers        : TFDQuery     ;
      FQFindCompilerFindings : TFDQuery     ;
      FQInsertCompilerFinding: TFDQuery     ;
      FFts5Available         : Boolean     ; // set by Migrate; False when sqlite3.dll lacks fts5
      FReadOnly              : Boolean     ; // v0.86 Task 4: opened read-only (no DDL/writes)
      FStatementsPrepared    : Boolean     ; // guard: PrepareStatements is idempotent (constructor may prepare a schema-current DB before Migrate)
      // v0.40.4: uses-clause persistence
      FQInsertUnitUse        : TFDQuery;
      FQDeleteFileUnitUses   : TFDQuery;
      FQGetFileUnitUses      : TFDQuery;
      FQFindUsersOfUnit      : TFDQuery;
      // Task 3c: ancestry-derived GUI-framework anchor (see
      // FrameworkAnchorForFile). Pure derivations of what is already in the
      // index -- no writes, so --no-write-back is unaffected.
      FAnchorCache           : TDictionary<Int64, string>; // file id -> '' | 'Vcl' | 'FMX'
      FDerivingAnchor        : Boolean;                    // re-entrancy guard
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

      // v(ADP2 T1): symbol_facts (index-time analysis facts) -- see ISymbolStore.
      function GetSymbolFacts(ASymbolId: Int64): TSymbolFacts;
      procedure PutSymbolFacts(const AFacts: TSymbolFacts);

      // v0.40.4: uses-clause persistence + queries
      procedure UpsertUnitUse(const AToken: TFileTxToken; const AUse: TUnitUse);
      procedure DeleteUnitUsesForFile(AFileId: Int64);
      function GetUnitUsesForFile(AFileId: Int64): TArray<TUnitUse>          ;
      function FindUsersOfUnit(const AUnitNameNorm: string): TArray<TUnitUse>;
      procedure ResolveUnitUseTargets;
      // v11 (M1): type & hierarchy resolution (see ISymbolStore).
      procedure ResolveAncestry;
      /// <summary>v15: populate the type_helpers table (record/class helper targets).
      /// Analogous to ResolveAncestry (resolves each helper's target type name
      /// cross-unit via the in-scope uses graph). Run after ResolveAncestry.</summary>
      procedure ResolveHelpers;
      // v14 (D5): whole-DB call-resolution pass (see ISymbolStore).
      procedure ResolveCallTargets;
      function GetTransitiveAncestors(ASymbolId: Int64): TArray<TTypeAncestor>;
      function IsDescendantOf(const AClassName, AAncestorName: string; AFileId: Int64): Boolean;
      function FindDescendantNames(const AAncestorName: string): TArray<string>;
      function ImplementsInterface(const AClassName, AInterfaceName: string; AFileId: Int64): Boolean;
      function ResolveTypeCategory(const ATypeName: string; AFileId: Int64): TTypeCategory;
      function GetVirtualMethodsIncludingAncestors(const AClassName: string; AFileId: Int64): TArray<string>;
      /// <summary>v15: all helpers (record/class) whose target type name matches
      /// ATargetName (whole-DB). Empty when no helper targets that type.
      /// NAME-ONLY match: two unrelated same-named types in different units
      /// (e.g. two distinct `TColor` enums) are indistinguishable to this call
      /// -- prefer FindHelpersOfTypeSymbol when the candidate's own symbol id
      /// is known, to avoid cross-linking unrelated same-named types.</summary>
      function FindHelpersOfType(const ATargetName: string): TArray<THelperEdge>;
      /// <summary>Task 9b (FP fix): all helpers (record/class) whose edge
      /// resolved its target to the EXACT symbol ATargetSymbolId (identity
      /// match via type_helpers.target_symbol_id, not the target's bare name).
      /// Only edges with a RESOLVED target_symbol_id can match -- an edge whose
      /// target never resolved at index time (heritage name didn't uniquely
      /// resolve in scope) is excluded, since it cannot be proven to target
      /// ATargetSymbolId rather than some other same-named type. Use this
      /// instead of FindHelpersOfType(name) whenever the candidate type's own
      /// symbol id is known and false cross-links between same-named types in
      /// different units must be avoided (enum-helper-separate-units lint rule,
      /// enum-helper generator's existing-helper guard).</summary>
      function FindHelpersOfTypeSymbol(ATargetSymbolId: Int64): TArray<THelperEdge>;

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
      // proptree lazy ancestry-bridge (scope-aware, alias-following resolver) +
      // its write-back memoization. See interface DocInsight for the contract.
      function ResolveTypeNameToClass(const ATypeName: string; AScopeFileId: Int64): TSymbol;
      function MemoizePropertyType(ASymbolId: Int64; const ATypeName: string): Boolean;
      function FindEnclosingRoutineByImpl(AFileId: Int64; ALine: Integer): TSymbol;

      // v0.20: completion helpers
      function FindSymbolsByPrefix(const APrefix: string; ALimit: Integer): TArray<TSymbol>;
      function FindAllChildSymbols(AParentId: Int64): TArray<TSymbol>                      ;

      // v0.25: dead-code finder
      function FindSymbolsWithNoCallers(const AKind: string; AIncludePrivate: Boolean): TArray<TSymbol>;

      // v0.26: compiler diagnostics
      function FindCompilerFindingsForFile(AFileId: Int64): TArray<TCompilerFinding>;
      procedure ClearCompilerFindings;
      procedure InsertCompilerFinding(const AFinding: TCompilerFinding);
      procedure ClearCompilerFindingsForFile(AFileId: Int64);
      procedure SetFileCompiledAt(AFileId: Int64; AUnix: Int64);
      function GetFileCompiledAt(AFileId: Int64): Int64;
      function GetFileMTime(AFileId: Int64): Int64;
      function GetStaleFileIds: TArray<Int64>;

      // v0.17: blast-radius pack
      function FindTransitiveCallers(const ASymbolName: string; ADepth: Integer): TArray<TImpactLevel>            ;
      function GetClassSurface(const AQName: string; AIncludeImpl, AAllVisibility: Boolean): TArray<TSurfaceLine> ;
      function GetSymbolSlice(const AQName: string): TArray<TSliceChunk>                                          ;
      function FindCallersByNameWithContext(const ACalleeName: string; AContextLines: Integer): TArray<TReference>;
    private
      /// <summary>Task 3c: the GUI framework (exactly 'Vcl' or 'FMX') that the
      ///  classes declared in AFileId demonstrably inherit FROM, or '' when the
      ///  index shows no such evidence or shows BOTH. Used as rule 3's scope
      ///  segment in PickAncestorCandidateByScope when -- and only when -- the
      ///  scope unit's OWN name carries no dotted namespace segment, i.e. for a
      ///  legacy pre-namespace unit ('Abcbtn', 'cxButtons').</summary>
      /// <param name="AFileId">The scope file. &lt;= 0 yields ''.</param>
      /// <returns>'Vcl', 'FMX', or '' -- and '' is the common, CORRECT answer:
      ///  no evidence and conflicting evidence are deliberately indistinguishable
      ///  to the caller, because both must lead to the same decline.</returns>
      /// <remarks>
      ///  GUARANTEE, stated narrowly: the segment returned is the NEAREST GUI
      ///  hop of an ALREADY-RESOLVED (index-time) ancestor edge chain from at
      ///  least one class declared in AFileId, and no chain from that file has
      ///  a DIFFERENT nearest GUI hop. Each climb stops at its nearest GUI hop
      ///  and never looks above it, so this says nothing about what lies
      ///  further up -- "no chain reaches the other framework" would be a
      ///  stronger claim than the code makes. It is NOT a claim about the
      ///  file's project, its
      ///  .dproj &lt;FrameworkType&gt;, or its .dfm/.fmx sibling -- none of which
      ///  the library index records (see docs/TODO-URGENT-framework-type-record.md).
      ///  It is FILE-level, not class-level: a file mixing a Vcl-rooted and an
      ///  FMX-rooted class yields '' for BOTH.
      ///  NO RECURSION INTO NAME RESOLUTION -- the load-bearing property. The
      ///  climb follows ONLY type_ancestors rows whose ancestor_symbol_id the
      ///  indexer already resolved, read straight out of the DB by id; it never
      ///  calls ResolveTypeNameToClass / PickAncestorCandidateByScope, which is
      ///  what stops "resolve a name -> derive an anchor -> resolve a name" from
      ///  closing a loop, since the resolver is the only caller. FDerivingAnchor
      ///  additionally makes any FUTURE re-entrant edit degrade to '' (decline)
      ///  instead of recursing. Cached per file id (FAnchorCache) and cleared by
      ///  ResolveAncestry, whose rebuild is the only thing that can invalidate it.
      ///  Pure read; a --no-write-back / read-only handle is unaffected.
      /// </remarks>
      function FrameworkAnchorForFile(AFileId: Int64): string;
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
  FReadOnly      := AReadOnly;
  FAnchorCache   := TDictionary<Int64, string>.Create; // Task 3c; see FrameworkAnchorForFile
  FDerivingAnchor:= False;
  Connect(ADbPath, AReadOnly);
  { v0.86 Task 4: a read-only open still needs its SELECT queries built. In the
    write path PrepareStatements is Migrate's last step; read verbs never call
    Migrate, so build the statements here. PrepareStatements executes no SQL
    (FireDAC auto-prepares on first use) -- safe on a read-only connection. }
  { Build the SELECT/UPSERT statements when the schema is current. Needed by any
    open that will run queries WITHOUT first calling Migrate: every read-only verb,
    AND a writable open that skips Migrate (proptree --write-back). On a pre-current
    DB some referenced tables may be absent, so guard on IsSchemaCurrent -- a stale
    read verb calls IsSchemaCurrent, sees False, prints the actionable message, and
    exits; the index/write path (also pre-current on a fresh DB) skips here and lets
    Migrate build the schema then prepare. PrepareStatements is idempotent
    (FStatementsPrepared), so Migrate's later call is a safe no-op after this. }
  var LFound, LExpected: Integer;
  if IsSchemaCurrent(LFound, LExpected) then
  begin
    PrepareStatements;
    { The write path sets FFts5Available via a temp-table probe (a write). Without
      Migrate, detect FTS5 read-only: the string_fts virtual table exists in
      sqlite_master iff the index was built by an FTS5-capable engine. This lets
      SearchText (query --text) run; it never issues DDL. }
    if FReadOnly then FFts5Available := Fts5TableExists;
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
  FQPutSymbolFacts.Free;
  FQGetSymbolFacts.Free;
  FQFindByDocTag.Free;
  FQFindUndocumented.Free;
  FQFindByDocContains.Free;
  FQListDocumentedSymbols.Free;
  FQFindContaining.Free;
  FQFindFileId.Free;
  FQFindChildByName.Free;
  FQFindEnclRoutine.Free;
  FQFindByPrefix.Free;
  FQFindAllChildren.Free;
  FQFindNoCallers.Free;
  FQFindCompilerFindings.Free;
  FQInsertCompilerFinding.Free;
  FQInsertUnitUse.Free;
  FQDeleteFileUnitUses.Free;
  FQGetFileUnitUses.Free;
  FQFindUsersOfUnit.Free;
  FAnchorCache.Free;
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
  { v15: per-symbol record/class-helper flag (True for a declHelper-shaped
    declaration). Additive column; ALTER onto pre-v15 tables for the same
    reason as the v9/v11/v12 columns above. ResolveHelpers filters on it. }
  TryExec('ALTER TABLE symbols ADD COLUMN is_helper INTEGER');
  { v13 (v0.82): per-ref enclosing-routine attribution. Additive column; ALTER
    onto pre-v13 refs tables for the same reason as the v9 body-span columns.
    Populated per-file in IndexFile; NULL when the ref is in no routine body.
    v0.83.1: this is the SOLE creation site of idx_refs_enclosing -- it must
    run after the ALTER. In SCHEMA_DDL (before the ALTER) it aborted the whole
    migration on every pre-v13 DB with "no such column: enclosing_symbol_id". }
  TryExec('ALTER TABLE refs ADD COLUMN enclosing_symbol_id INTEGER');
  TryExec('CREATE INDEX IF NOT EXISTS idx_refs_enclosing ON refs(enclosing_symbol_id)');
  { v16: per-file last-successful-compile timestamp (Unix seconds). NULL = never
    compiled. Additive column; ALTER onto pre-v16 files tables for the same
    reason as the symbols/refs columns above. Read by the freshness engine to
    decide staleness (stale iff last_compiled_unix IS NULL OR < mtime_unix). }
  TryExec('ALTER TABLE files ADD COLUMN last_compiled_unix INTEGER');
  { v17: proptree assignability engine. Additive column; ALTER onto pre-v17
    symbols tables for the same reason as the v9/v11/v12/v13 columns above.
    Populated ('ro'/'rw'/'wo') during property extraction (Task 6); NULL for a
    pre-v17 DB row until it is re-indexed with the v17 engine. }
  TryExec('ALTER TABLE symbols ADD COLUMN prop_access TEXT');
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
  { v15: first-class helper-target edges. Similar to type_ancestors, one row
    per helper declaration (record/class helper for T) linked to its target type.
    Populated by the indexer during the resolve pass (like type_ancestors);
    ON DELETE CASCADE clears edges when a helper's file is re-indexed. }
  TryExec('CREATE TABLE IF NOT EXISTS type_helpers (' +
          '  helper_symbol_id INTEGER NOT NULL REFERENCES symbols(id) ON DELETE CASCADE,' +
          '  target_name      TEXT NOT NULL,' +
          '  target_symbol_id INTEGER REFERENCES symbols(id) ON DELETE SET NULL,' +
          '  target_file_id   INTEGER,' +
          '  helper_kind      TEXT NOT NULL)');
  TryExec('CREATE INDEX IF NOT EXISTS idx_type_helpers_helper ON type_helpers(helper_symbol_id)');
  TryExec('CREATE INDEX IF NOT EXISTS idx_type_helpers_target ON type_helpers(target_name)');
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
  // Idempotent: the constructor may prepare a schema-current DB and Migrate then
  // calls this again on the write path. Re-running would leak the first query set,
  // so bail if already built.
  if FStatementsPrepared then Exit;
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
    'INSERT INTO symbols(file_id, parent_id, kind, name, qualified_name, ' + '  signature, modifiers, section, heritage, is_virtual, is_helper, start_line, start_col, end_line, end_col, ' +
    '  impl_start_line, impl_end_line, prop_access) ' + 'VALUES (:fid, :pid, :kind, :name, :qname, :sig, :mods, :sec, :her, :virt, :ish, ' + '  :sl, :sc, :el, :ec, :isl, :iel, :pa)');
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

  // v(ADP2 T1): symbol_facts UPSERT (keyed on symbol_id) + read-back.
  FQPutSymbolFacts:= NewQuery(
    'INSERT OR REPLACE INTO symbol_facts ' + '(symbol_id, reads_fields, writes_fields, returns_owner, cyclomatic, ' +
    ' body_loc, dfm_event, sql_reads, sql_writes, covered_by) ' +
    'VALUES (:sid, :reads, :writes, :ret, :cyc, :loc, :dfm, :sqlr, :sqlw, :cov)');
  FQPutSymbolFacts.Params.ParamByName('sid'  ).DataType:= ftLargeint;
  FQPutSymbolFacts.Params.ParamByName('reads' ).DataType:= ftWideMemo;
  FQPutSymbolFacts.Params.ParamByName('writes').DataType:= ftWideMemo;
  FQPutSymbolFacts.Params.ParamByName('ret'   ).DataType:= ftWideMemo;
  FQPutSymbolFacts.Params.ParamByName('cyc'   ).DataType:= ftInteger;
  FQPutSymbolFacts.Params.ParamByName('loc'   ).DataType:= ftInteger;
  FQPutSymbolFacts.Params.ParamByName('dfm'   ).DataType:= ftWideMemo;
  FQPutSymbolFacts.Params.ParamByName('sqlr'  ).DataType:= ftWideMemo;
  FQPutSymbolFacts.Params.ParamByName('sqlw'  ).DataType:= ftWideMemo;
  FQPutSymbolFacts.Params.ParamByName('cov'   ).DataType:= ftWideMemo;
  FQPutSymbolFacts.Prepare;

  FQGetSymbolFacts:= NewQuery(
    'SELECT reads_fields, writes_fields, returns_owner, cyclomatic, body_loc, ' +
    ' dfm_event, sql_reads, sql_writes, covered_by ' + 'FROM symbol_facts WHERE symbol_id = :sid');

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

  // v0.94 (hover scope fix): innermost routine whose IMPL BODY span contains
  // the cursor line -- ORDER BY impl_start_line DESC so a nested routine
  // (innermost) wins over its enclosing one.
  FQFindEnclRoutine:= NewQuery(
    'SELECT * FROM symbols ' +
    'WHERE file_id = :fid AND impl_start_line IS NOT NULL AND impl_start_line > 0 ' +
    '  AND impl_start_line <= :line AND impl_end_line >= :line ' +
    '  AND kind IN (''procedure'',''function'',''method'',''constructor'',''destructor'') ' +
    'ORDER BY impl_start_line DESC LIMIT 1');

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

  // (An all-SQL FQResolveUnitUseTargets used to be prepared here. It was never
  // executed -- ResolveUnitUseTargets builds its own queries -- and it encoded
  // the unit_name_norm-vs-full-stem comparison that was the criterion-12 bug,
  // so it was removed rather than left as a second, wrong copy of the rule.)
  FStatementsPrepared:= True;
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
  FQInsertSymbol.ParamByName('ish'  ).AsInteger:= Ord(ASymbol.IsHelper); { v15 }
  FQInsertSymbol.ParamByName('sl'   ).AsInteger:= ASymbol.StartLine;
  FQInsertSymbol.ParamByName('sc'   ).AsInteger:= ASymbol.StartCol;
  FQInsertSymbol.ParamByName('el'   ).AsInteger:= ASymbol.EndLine;
  FQInsertSymbol.ParamByName('ec'   ).AsInteger:= ASymbol.EndCol;
  FQInsertSymbol.ParamByName('isl'  ).AsInteger:= ASymbol.ImplStartLine; { v9 }
  FQInsertSymbol.ParamByName('iel'  ).AsInteger:= ASymbol.ImplEndLine; { v9 }
  { v17 (Task 6/R1): a property's read/write accessor shape (ro/rw/wo). Stored
    NULL when '' -- both for every non-property symbol AND for a bare
    property redeclaration -- so an un-re-indexed pre-v17 row and a bare
    redeclaration both read back NULL, which proptree treats as writable/
    inherit-up-tree. Mirrors the heritage NULL-when-empty pattern above. }
  FQInsertSymbol.ParamByName('pa'   ).DataType := ftString;
  if ASymbol.PropAccess <> '' then FQInsertSymbol.ParamByName('pa').AsString:= ASymbol.PropAccess
  else FQInsertSymbol.ParamByName('pa').Clear;
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
      if Q.FieldByName('start_line').IsNull then R.CallSiteLine := 0
      else R.CallSiteLine := Q.FieldByName('start_line').AsInteger;
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
/// when the ref has no enclosing routine.
/// (ADP1 Bug C fix): EXCLUDES a class's own method-header self-reference. A
/// qualified impl header ('function TThing.Add(...)') emits a type_use ref of
/// name_text='TThing' whose enclosing_symbol_id is the METHOD ITSELF
/// (TThing.Add) -- s.parent_id is then TThing's own id. When AName matches
/// that SAME type's name (and kind is a type-like kind), the ref is a
/// self-reference, not an external caller, and is dropped.
/// (ADP1 Bug C fix2, CRITICAL regression fix): the WHERE clause explicitly
/// short-circuits on 's.parent_id IS NULL' before testing membership in the
/// same-named-type subquery. This matters because of SQL three-valued logic:
/// a ref whose enclosing routine is NULL (a unit-scope reference OUTSIDE any
/// routine body, e.g. a top-level 'var G: TThing;', or the LEFT JOIN simply
/// finding no symbols row) makes 's.parent_id' NULL, and 'NULL IN (...)' /
/// 'NOT (NULL IN (...))' both evaluate to NULL rather than TRUE or FALSE --
/// a WHERE predicate of NULL excludes the row just like FALSE does. An
/// earlier form of this clause ('AND NOT (s.parent_id IN (...))') had no
/// NULL short-circuit, so it silently dropped EVERY NULL-enclosing
/// reference, not just self-references -- a real regression for unit-scope
/// facts. The current form keeps such rows via the explicit
/// 's.parent_id IS NULL' branch. A ref enclosed by a member of the SAME
/// named type is still excluded (self-reference, both branches false). A
/// ref enclosed by a routine belonging to a DIFFERENT type (or no type at
/// all, e.g. a plain top-level routine) is kept: s.parent_id is either a
/// non-matching id or NULL, either of which satisfies the OR.</summary>
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
      '  AND (s.parent_id IS NULL OR s.parent_id NOT IN (' +
      '        SELECT id FROM symbols WHERE name = :n2 AND kind IN (''class'',''interface'',''record'',''type''))) ' +
      'ORDER BY f.path, r.start_line';
    Q.ParamByName('n').AsString:= AName;
    Q.ParamByName('n2').AsString:= AName;
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
  ResolveHelpers loads inline for its FileScope map. Unresolved rows (NULL
  target_file_id) are excluded, so both ids are always > 0.
  Task 4: ResolveAncestry no longer uses this shape at all -- it scopes
  candidates from the TEXTUAL uses names instead, so it does not depend on
  target_file_id ever having been resolved. }
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
  if AQ.FindField('is_helper') <> nil then { v15: tolerate pre-v15 databases }
    Result.IsHelper := AQ.FieldByName('is_helper').AsInteger <> 0;
  if AQ.FindField('prop_access') <> nil then { v17 (Task 6/R1): tolerate pre-v17 databases }
    Result.PropAccess := AQ.FieldByName('prop_access').AsString; { NULL -> '' -> writable/inherit }
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

procedure TSQLiteSymbolStore.PutSymbolFacts(const AFacts: TSymbolFacts);
// Helper: assign a nullable text param without changing its pre-declared
// DataType (mirrors UpsertSymbolDoc.SetNullableText -- AsString would
// silently flip DataType to ftString and break the next call with
// [SQLite]-338 "Param type changed").
  procedure SetNullableText(const AParamName: string; const AValue: string);
  begin
    with FQPutSymbolFacts.ParamByName(AParamName) do
      if AValue = '' then Clear else Value:= AValue;
  end;
begin
  FQPutSymbolFacts.ParamByName('sid').AsLargeInt:= AFacts.SymbolId;
  SetNullableText('reads' , AFacts.ReadsFields );
  SetNullableText('writes', AFacts.WritesFields);
  SetNullableText('ret'   , AFacts.ReturnsOwner);
  FQPutSymbolFacts.ParamByName('cyc').AsInteger:= AFacts.Cyclomatic;
  FQPutSymbolFacts.ParamByName('loc').AsInteger:= AFacts.BodyLoc;
  SetNullableText('dfm' , AFacts.DfmEvent );
  SetNullableText('sqlr', AFacts.SqlReads );
  SetNullableText('sqlw', AFacts.SqlWrites);
  SetNullableText('cov' , AFacts.CoveredBy);
  FQPutSymbolFacts.ExecSQL;
end; // procedure

function TSQLiteSymbolStore.GetSymbolFacts(ASymbolId: Int64): TSymbolFacts;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.SymbolId:= ASymbolId;
  if FQGetSymbolFacts.Active then FQGetSymbolFacts.Close;
  FQGetSymbolFacts.ParamByName('sid').AsLargeInt:= ASymbolId;
  FQGetSymbolFacts.Open;
  try
    if FQGetSymbolFacts.IsEmpty then Exit; // Present stays False (FillChar zeroed it)
    Result.ReadsFields := FQGetSymbolFacts.FieldByName('reads_fields' ).AsString;
    Result.WritesFields:= FQGetSymbolFacts.FieldByName('writes_fields').AsString;
    Result.ReturnsOwner:= FQGetSymbolFacts.FieldByName('returns_owner').AsString;
    Result.Cyclomatic  := FQGetSymbolFacts.FieldByName('cyclomatic'   ).AsInteger;
    Result.BodyLoc     := FQGetSymbolFacts.FieldByName('body_loc'     ).AsInteger;
    Result.DfmEvent    := FQGetSymbolFacts.FieldByName('dfm_event'    ).AsString;
    Result.SqlReads    := FQGetSymbolFacts.FieldByName('sql_reads'    ).AsString;
    Result.SqlWrites   := FQGetSymbolFacts.FieldByName('sql_writes'   ).AsString;
    Result.CoveredBy   := FQGetSymbolFacts.FieldByName('covered_by'   ).AsString;
    Result.Present     := True;
  finally
    FQGetSymbolFacts.Close;
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

// Parse the first bare type token out of a symbol signature: strip a single
// leading ':' + whitespace, then take up to the first whitespace / ';'. Mirrors
// DRagLint.Convert.PropTree.ParseTypeToken (kept local -- that one is unit-private)
// so a type-alias target ('TCustomButton') can be pulled from the alias Signature.
function ParseFirstTypeToken(const ASignature: string): string;
var
  S  : string ;
  P  : Integer;
begin
  Result:= '';
  S:= Trim(ASignature);
  if S = '' then Exit;
  if S[1] = ':' then S:= Trim(Copy(S, 2, MaxInt));
  for P:= 1 to Length(S) do
  begin
    if CharInSet(S[P], [' ', #9, #13, #10, ';', '=']) then Break;
    Result:= Result + S[P];
  end;
end;

// DeclaringUnitOfQName ("which unit declares this candidate") and
// UnitFrameworkPrefix (the leading dotted namespace segment) moved to
// DRagLint.Core.Model, so this SELECT-side rule and the proptree ancestor
// climb's REFUSE-side cross-namespace guard share ONE definition of the notion
// rather than each carrying its own copy. Semantics are unchanged.

/// <summary>
///  Shared ancestor/type-candidate disambiguation rule: given several
///  same-named class/interface/record/type-alias candidates, picks the one
///  a referencing unit actually means, in strict precedence order --
///  (1) a candidate declared in the SAME unit (file) as the referencing
///  class; (2a) a candidate whose declaring unit is textually named in the
///  referencing unit's `uses` clause (either the interface or the
///  implementation section -- plain membership, so it works even when
///  `unit_uses.target_file_id` was never resolved), but ONLY when that
///  narrows the field to EXACTLY ONE candidate; (2b) failing that, and only
///  when 2a matched NOTHING at all, the same test against the candidate
///  unit's LAST dotted segment ('Vcl.Graphics' counts as `uses Graphics`),
///  again only when EXACTLY ONE candidate qualifies; (3) a candidate whose
///  declaring unit shares the referencing unit's first DOTTED NAMESPACE
///  SEGMENT (the substring before the first '.' -- see
///  UnitFrameworkPrefix), or, when the referencing unit's own name has no
///  such segment, shares AScopeFrameworkAnchor instead; again ONLY when
///  that narrows the field to EXACTLY ONE candidate; (4) decline. Each rule
///  short-circuits: the first rule that narrows the field to exactly one
///  candidate decides the result without consulting the next rule. A rule
///  that finds 2+ qualifying candidates does NOT pick one by array/insertion
///  order -- that would be exactly as arbitrary as guessing -- it falls
///  through to the next rule instead.
/// </summary>
/// <param name="ACandidates">Same-named candidates, already reduced to real
///  bodies by the caller (forward-declaration stubs dropped -- see
///  IsStub).</param>
/// <param name="AScopeFileId">FileId of the class/unit doing the
///  referencing. Callers walking a multi-hop ancestry chain must pass the
///  FileId of the class actually inheriting at THAT hop, not the FileId of
///  the root class the walk started from. AScopeFileId <= 0 means
///  "unknown" and skips rule 1 outright (never a wildcard match against a
///  candidate's own possibly-unset FileId).</param>
/// <param name="AScopeUnitName">The scope unit's own name (e.g.
///  'Vcl.StdCtrls'), used only to derive its leading dotted-namespace
///  segment for rule 3. Pass '' when unknown -- rule 3 is then skipped
///  outright, never treated as a wildcard match.</param>
/// <param name="AScopeUsesNames">Lowercased unit names textually present in
///  the scope unit's `uses` clause (either section). Membership test only;
///  does not require `unit_uses.target_file_id` to be populated. May be nil
///  (rule 2 is then skipped).</param>
/// <param name="AScopeFrameworkAnchor">The GUI framework segment ('Vcl' or
///  'FMX') the scope unit's own class ancestry demonstrably belongs to, for
///  a LEGACY PRE-NAMESPACE scope unit whose name yields no segment of its
///  own; '' when unknown, contradictory, or simply not derived. Read ONLY
///  where UnitFrameworkPrefix(AScopeUnitName) = '', and in both places for
///  the same purpose -- to stand in for the segment the unit does not have:
///  rule 3 SELECTS by it, and rule 2b's guard requires a GUI-namespace hit
///  to agree with it. A DOTTED scope unit therefore ignores this parameter
///  entirely and behaves exactly as it did before the parameter existed.
///  Never consulted by rules 1 or 2a, which rest on what the unit
///  explicitly states. In rule 2b the anchor acts through
///  WeakHitFrameworkUnconfirmed, which only ever REMOVES entries from that
///  pass's hit set and adds none. Two consequences, both real, and neither
///  is "the anchor cannot change the outcome":
///    * 2b returns only when EXACTLY ONE hit survives, so a removal can turn
///      a tie into a decision -- the guard CAN convert a decline into a pick.
///    * the anchor is what CONFIRMS a GUI-namespace hit, so supplying one is
///      precisely what lets 2b return a GUI candidate at all; an UNANCHORED
///      undotted unit has every GUI hit dropped instead.
///  What no anchor can do is make 2b return a GUI candidate it does NOT
///  confirm, or override rules 1 or 2a. See
///  TSQLiteSymbolStore.FrameworkAnchorForFile.</param>
/// <returns>The chosen candidate, or a default(TSymbol) (Id = 0) when no
///  rule narrows the field to one.</returns>
/// <remarks>
///  Declining (Id = 0) is a CORRECT outcome, not a failure -- "when unsure,
///  don't claim" -- callers must never guess further on a decline. Rule 3's
///  segment compare is exact ('VclKit' has no dot, so UnitFrameworkPrefix
///  returns '' for it and it can never match 'Vcl.Controls' -- an undotted
///  unit name never participates; for such a unit rule 3 runs only if an
///  ANCHOR was supplied). Rule 3 is written generically (matches ANY shared
///  first dotted segment, not a hardcoded allowlist) so it also
///  disambiguates project/third-party namespaces, not just the RTL; 'Vcl.*'
///  vs 'FMX.*' vs 'Winapi.*' are the motivating cases, not the whole rule.
///  The anchor, by contrast, is only ever 'Vcl' or 'FMX' -- it is evidence
///  about the two conflicting GUI frameworks specifically.
///  CROSS-FRAMEWORK GUARANTEE, stated exactly. Define the scope's EFFECTIVE
///  FRAMEWORK as its own leading segment, or -- when it has none -- the
///  ancestry anchor. Neither rule 2b nor rule 3 can then return a candidate
///  from a GUI framework namespace that disagrees with it: rule 3 selects BY
///  that segment, and rule 2b drops any GUI-namespace hit that segment does
///  not confirm. An UNKNOWN effective framework (an undotted unit with no
///  anchor) is not confirmation -- rule 3 is skipped and rule 2b drops EVERY
///  GUI-namespace hit, so such a unit can never take a GUI candidate. It does
///  NOT follow that it always declines: dropping a GUI hit can leave exactly
///  one surviving NON-GUI hit where there had been a tie, and pass 2b then
///  returns that one. The guarantee is about WHICH NAMESPACES can come back,
///  not about declining. Non-GUI candidates ('System.*', 'Winapi.*', undotted,
///  project namespaces) are never dropped by either rule; they are not
///  competing frameworks.
///  Rules 1 and 2a deliberately CAN cross, and rank above both: a unit that
///  is in the same file as a candidate, or that explicitly `uses` exactly
///  one FMX.* unit declaring the name, has STATED which one it means. An
///  explicit declaration outranks every inference here. Nothing in this
///  function ever settles a tie by array order.
///  This is the ONE decision procedure shared by the query-time resolver
///  (ResolveTypeNameToClass / PickCandidate, below) and the index-time
///  resolver (ResolveAncestry) -- change the precedence HERE, not by
///  re-implementing it in either caller. Both callers reach it the same way:
///  a name with a SINGLE candidate short-circuits before this function is
///  entered, and everything ambiguous comes here. Both gather AScopeUnitName
///  and AScopeUsesNames from the same two sources (the scope file's own `unit`
///  symbols, then its unit_uses.unit_name entries, lowercased) -- query time
///  per file on demand, index time in one bulk pass. Two differences in that
///  gathering are known and recorded so nobody has to re-derive them.
///  (a) Index time skips empty names and file ids &lt;= 0; query time inserts
///  LowerCase('') unguarded. An empty key can only ever match a candidate
///  whose QualifiedName carries NO DOT, since that is the only input for which
///  DeclaringUnitOfQName returns ''. Pass 2a performs that lookup UNGUARDED,
///  so at query time an empty unit_name row together with such a candidate CAN
///  produce a spurious single 2a hit; pass 2b already guards exactly this
///  ('if CandUnit = '' then Continue'), 2a does not. Narrow, and unreachable
///  on the index side -- but NOT vacuous. Do not restate it as "an empty key
///  matches nothing".
///  (b) Index time orders the scope file's `unit` symbols by id; query time
///  takes the first row the engine returns. Observable only for a file that
///  declares two `unit` symbols, which is malformed.
///  WHAT IS SHARED IS THE RULE, NOT THE CANDIDATE SET. The query-time caller
///  offers class, interface, record AND type-alias symbols and chases an alias
///  to its target; ResolveAncestry offers class and interface only. So the two
///  can be handed DIFFERENT fields for the same name, and a name that is
///  ambiguous on one side may be a single candidate (or none) on the other.
///  That difference predates this function and is not something it arbitrates.
///  ONE INPUT DIFFERS, deliberately: ResolveAncestry always passes
///  AScopeFrameworkAnchor = '', because it is REBUILDING type_ancestors and
///  FrameworkAnchorForFile derives the anchor by climbing that same table. The
///  consequence is bounded and stated in full: rules 1, 2a and 3-for-a-dotted-
///  unit are identical on both sides; a LEGACY UNDOTTED scope unit gets no
///  rule 3 and an unconfirmed (therefore dropped) rule 2b GUI hit at index
///  time, so it DECLINES there and is resolved later by the query-time climb,
///  which does supply an anchor. Index time is never the more permissive of
///  the two.
/// </remarks>
function PickAncestorCandidateByScope(const ACandidates: TArray<TSymbol>;
  AScopeFileId: Int64; const AScopeUnitName: string;
  AScopeUsesNames: TDictionary<string, Boolean>;
  const AScopeFrameworkAnchor: string): TSymbol;
var
  S          : TSymbol;
  ScopePrefix: string ;
  UsesHit    : TSymbol;
  UsesHits   : Integer;
  PrefixHit  : TSymbol;
  PrefixHits : Integer;
  CandUnit   : string ;

  // The LAST dotted segment of a unit name ('Vcl.Graphics' -> 'Graphics'),
  // or the whole name when it carries no dot. Delphi's own unit-scope-names
  // resolution in reverse: with 'Vcl' among the project's unit scope names,
  // a bare `uses Graphics` denotes the unit whose full name is
  // 'Vcl.Graphics'. Note the undotted case returns the name unchanged, so a
  // candidate in an undotted unit matches identically in both passes and
  // pass 2 can never reach one that pass 1 missed.
  function LastUnitSegment(const AUnitName: string): string;
  var P: Integer;
  begin
    Result:= AUnitName;
    P:= LastDelimiter('.', AUnitName);
    if P > 0 then Result:= Copy(AUnitName, P + 1, MaxInt);
  end;

  // Criterion 5 for pass 2b ONLY, stated POSITIVELY: a weak hit that lands in
  // a GUI framework namespace must be CONFIRMED by the scope's own effective
  // framework. Unknown is not confirmation -- an unconfirmed GUI hit is
  // dropped, and pass 2b then finds nothing rather than something plausible.
  //
  // The first cut of this asked the opposite question ("do the two segments
  // CROSS?") and was inert exactly where it was needed: an undotted legacy
  // unit's own segment is '', which is not a GUI framework, so nothing was
  // ever refused for the very population pass 2b targets. MEASURED on
  // library-Win64.sqlite: 'AdFax.TApdAbstractFaxStatus.Position' and
  // 'AdProtcl.TApdAbstractStatus.Position' -- undotted Async Professional
  // units, `uses ... Types ...` bare, no anchor -- took FMX.Types.TPosition on
  // a unique last-segment hit and grew 11 FireMonkey leaves each. Both had
  // DECLINED before pass 2b existed, and the proptree refuse side could not
  // catch it (CrossesGuiFramework needs BOTH prefixes to be GUI, and the
  // inheritor's is ''). It also exceeded pass 2b's own justification: a bare
  // `uses Types` denotes 'Vcl.*' or 'System.*' under a VCL project's unit
  // scope names -- 'FMX' is never among them.
  //
  // The scope's effective framework is its own leading segment, or -- by the
  // SAME substitution rule 3 makes, for the same reason -- the ancestry anchor
  // when it has no segment of its own.
  //
  // WHAT THIS GUARD CAN AND CANNOT DO, stated exactly, because the obvious
  // summary is wrong. Mechanically it only ever REMOVES entries from pass 2b's
  // hit set: it adds nothing and selects nothing. It does NOT follow that "it
  // cannot change what 2b returns" -- that reading is FALSE, and it stood in
  // this comment for several revisions. Pass 2b returns only when EXACTLY ONE
  // hit survives, so removing a candidate can turn a tie into a decision.
  //   Worked counter-example. Candidates 'Vcl.X.TFoo' and 'System.Y.TFoo', an
  //   undotted scope unit with NO anchor, `uses` carrying the bare names 'x'
  //   and 'y'. WITH the guard the Vcl hit is unconfirmed and dropped, exactly
  //   one hit survives, and 2b returns 'System.Y.TFoo'. WITHOUT it both hit,
  //   UsesHits = 2, and the rule falls through to rule 3 -- which has no
  //   segment to match and DECLINES. The guard turned a decline into a pick.
  // Symmetrically, the ANCHOR is what confirms a GUI hit, so supplying one is
  // exactly what lets 2b return a GUI candidate at all (case A of
  // tests/autotest/run_proptree_framework_anchor.ps1): unanchored, every GUI
  // hit is dropped and the unit declines.
  //
  // The two properties that ARE absolute, and the only ones worth asserting:
  //   * 2b can never return a GUI-namespaced candidate that the scope's
  //     effective framework does not CONFIRM -- that is precisely what is
  //     removed here;
  //   * this guard never runs before, or overrides, rules 1 or 2a.
  //
  // Non-GUI candidates ('System.*', 'Winapi.*', undotted, project namespaces)
  // are never dropped, so pass 2b keeps its purpose. The named trade-off: a
  // DOTTED but NON-GUI scope unit ('Data.*', a project namespace) writing a
  // bare `uses` now declines instead of taking a GUI candidate -- strictly
  // more conservative, and pinned by case I of
  // tests/autotest/run_proptree_framework_anchor.ps1.
  function WeakHitFrameworkUnconfirmed(const ACandUnit: string): Boolean;
  var
    ScopeSeg: string;
    CandSeg : string;
  begin
    ScopeSeg:= UnitFrameworkPrefix(AScopeUnitName);
    if ScopeSeg = '' then ScopeSeg:= AScopeFrameworkAnchor;
    CandSeg := UnitFrameworkPrefix(ACandUnit);
    Result  := IsGuiFrameworkPrefix(CandSeg) and not SameText(ScopeSeg, CandSeg);
  end;

begin
  Result:= Default(TSymbol);
  // Rule 1: same unit as the referencing class.
  if AScopeFileId > 0 then
    for S in ACandidates do
      if S.FileId = AScopeFileId then Exit(S);
  // Rule 2: candidate's declaring unit is named in the referencing unit's
  // uses -- only when it narrows the field to exactly one. Two-or-more
  // uses-named candidates are exactly as indistinguishable as two
  // same-prefix candidates in rule 3 below; picking the first by array
  // order here could hand back an FMX.* candidate for a Vcl.*-rooted class
  // (or vice versa) whenever the scope unit uses both frameworks, so this
  // must fall through to rule 3 -- never settle by order.
  if Assigned(AScopeUsesNames) then
  begin
    // Pass 2a (STRONG): the uses clause names the candidate's declaring
    // unit by its FULL name.
    UsesHits:= 0;
    UsesHit := Default(TSymbol);
    for S in ACandidates do
      if AScopeUsesNames.ContainsKey(LowerCase(DeclaringUnitOfQName(S.QualifiedName))) then
      begin
        Inc(UsesHits);
        if UsesHits = 1 then UsesHit:= S;
      end;
    if UsesHits = 1 then Exit(UsesHit);
    // Pass 2b (WEAK, Task 3c): a PRE-NAMESPACE uses clause writes bare unit
    // names -- 'Abcbtn' has `uses Graphics, Menus, ImgList` while the units
    // are indexed as 'Vcl.Graphics', 'Vcl.Menus', 'Vcl.ImgList' -- so pass
    // 2a scores zero and every such reference used to decline. Retry
    // against the candidate unit's LAST segment.
    // ONLY when pass 2a matched NOTHING: 2+ exact hits is a genuine
    // ambiguity that a weaker test has no standing to resolve, and it must
    // keep falling through to rule 3 exactly as before. A dotted uses entry
    // ('vcl.graphics') can never equal a bare last segment ('graphics'), so
    // a unit that writes fully-qualified uses names -- every RTL unit --
    // cannot gain a hit here that it did not already have.
    // A hit landing in a GUI framework namespace must additionally be
    // CONFIRMED by the scope's effective framework -- see
    // WeakHitFrameworkUnconfirmed, and read its comment before touching this:
    // the first cut asked "do they cross?" instead, which was inert for the
    // undotted units this pass exists for and put FireMonkey types on legacy
    // VCL classes.
    if UsesHits = 0 then
    begin
      UsesHit:= Default(TSymbol);
      for S in ACandidates do
      begin
        CandUnit:= DeclaringUnitOfQName(S.QualifiedName);
        if CandUnit = '' then Continue;
        if not AScopeUsesNames.ContainsKey(LowerCase(LastUnitSegment(CandUnit))) then Continue;
        if WeakHitFrameworkUnconfirmed(CandUnit) then Continue;
        Inc(UsesHits);
        if UsesHits = 1 then UsesHit:= S;
      end;
      if UsesHits = 1 then Exit(UsesHit);
    end;
  end;
  // Rule 3: candidate's declaring unit shares the referencing unit's first
  // dotted namespace segment -- only when it narrows the field to exactly
  // one.
  ScopePrefix:= UnitFrameworkPrefix(AScopeUnitName);
  // Task 3c: a LEGACY PRE-NAMESPACE scope unit has no segment of its own,
  // so rule 3 could never run for it and the whole rule collapsed to a
  // decline. Substitute the ancestry-derived GUI framework anchor -- what
  // the unit's own classes demonstrably inherit from. Strictly a
  // substitution for the MISSING segment: when the scope unit IS dotted the
  // anchor is not even read, and '' (no evidence, or evidence of both)
  // leaves rule 3 skipped exactly as it was.
  if ScopePrefix = '' then ScopePrefix:= AScopeFrameworkAnchor;
  if ScopePrefix <> '' then
  begin
    PrefixHits:= 0;
    PrefixHit := Default(TSymbol);
    for S in ACandidates do
      if SameText(UnitFrameworkPrefix(DeclaringUnitOfQName(S.QualifiedName)), ScopePrefix) then
      begin
        Inc(PrefixHits);
        if PrefixHits = 1 then PrefixHit:= S;
      end;
    if PrefixHits = 1 then Exit(PrefixHit);
  end;
  // Rule 4: ambiguous -- decline rather than guess.
end;

const
  // Hop cap for ONE class's anchor climb. Belt-and-braces next to the
  // per-climb visited-id set (which alone already terminates it, since every
  // hop must be an id not yet seen on this climb): a self-referential or
  // cyclic index must not be able to spin. Matches CMaxBridgedChainDepth
  // (DRagLint.Convert.PropTree) and GetTransitiveAncestors' own 64-hop bound;
  // no real Object Pascal hierarchy is anywhere near this deep.
  CMaxAnchorClimbHops = 64;

function TSQLiteSymbolStore.FrameworkAnchorForFile(AFileId: Int64): string;
var
  QCls     : TFDQuery           ;
  QAnc     : TFDQuery           ;
  StartIds : TList<Int64 >      ;
  StartQNs : TList<string>      ;
  Seen     : TDictionary<Int64, Boolean>; // visited class ids on the CURRENT climb
  Found    : string             ;         // the single GUI segment seen so far
  Mixed    : Boolean            ;         // both frameworks reached -> no anchor
  Seg      : string             ;
  CurId    : Int64              ;
  CurQName : string             ;
  Hops     : Integer            ;
  i        : Integer            ;
begin
  Result:= '';
  if AFileId <= 0 then Exit;
  if FAnchorCache.TryGetValue(AFileId, Result) then Exit;
  // Re-entrancy guard. Today it can never fire -- the climb below reads
  // type_ancestors/symbols directly and calls no resolver -- and that is
  // precisely the invariant it exists to protect: should anyone ever make the
  // derivation resolve a NAME, the resolver would call back in here and the
  // pair would recurse. Degrade to '' (decline), never recurse, and never
  // cache that guarded '' as if it were evidence.
  if FDerivingAnchor then Exit;
  FDerivingAnchor:= True;
  try
    Found   := '';
    Mixed   := False;
    QCls    := TFDQuery.Create(nil);
    QAnc    := TFDQuery.Create(nil);
    StartIds:= TList<Int64 >.Create;
    StartQNs:= TList<string>.Create;
    Seen    := TDictionary<Int64, Boolean>.Create;
    try
      // Every class declared in the scope file is a starting point: the file
      // is the unit of resolution, and a legacy unit's classes are its own
      // best evidence of which framework it was written against. Read the
      // whole list up front so the per-hop query can reuse the connection.
      QCls.Connection:= FConn;
      QCls.SQL.Text  := 'SELECT id, qualified_name FROM symbols ' +
                        'WHERE file_id = :fid AND kind = ''class'' ORDER BY id';
      QCls.ParamByName('fid').AsLargeInt:= AFileId;
      QCls.Open;
      while not QCls.Eof do
      begin
        StartIds.Add(QCls.Fields[0].AsLargeInt);
        StartQNs.Add(QCls.Fields[1].AsString  );
        QCls.Next;
      end;
      QCls.Close;
      // One hop UP: the nearest ancestor the INDEXER already resolved to a
      // real class symbol. 'ancestor_symbol_id IS NOT NULL' is what keeps
      // this a pure table read -- an unresolved edge is simply the end of
      // this climb, never a name handed to the resolver. It is written out
      // even though today's INNER JOIN already implies it, so that a later
      // change to a LEFT JOIN cannot silently break that invariant.
      // kind='class' skips implemented interfaces in the same heritage list;
      // ORDER BY ordinal then makes the base class the row taken.
      // KNOWN IMPRECISION: because the JOIN drops an UNRESOLVED row rather
      // than stopping at it, a class whose base class did not resolve but
      // whose implemented interface did -- and whose interface happens to be
      // indexed as kind='class' -- yields that lower-priority heritage slot
      // as "the nearest ancestor". Marginal, and it can only ever add
      // evidence that is then subject to the same nearest-hop and
      // both-frameworks-decline rules; it is recorded rather than fixed.
      QAnc.Connection:= FConn;
      QAnc.SQL.Text  := 'SELECT s.id, s.qualified_name FROM type_ancestors ta ' +
                        'JOIN symbols s ON s.id = ta.ancestor_symbol_id ' +
                        'WHERE ta.symbol_id = :sid AND ta.ancestor_symbol_id IS NOT NULL ' +
                        'AND s.kind = ''class'' ' +
                        'ORDER BY ta.ordinal LIMIT 1';
      for i:= 0 to StartIds.Count - 1 do
      begin
        if Mixed then Break;
        CurId   := StartIds[i];
        CurQName:= StartQNs[i];
        Hops    := 0;
        Seen.Clear;
        while (CurId > 0) and (Hops < CMaxAnchorClimbHops) do
        begin
          Inc(Hops);
          if Seen.ContainsKey(CurId) then Break;
          Seen.Add(CurId, True);
          Seg:= UnitFrameworkPrefix(DeclaringUnitOfQName(CurQName));
          if IsGuiFrameworkPrefix(Seg) then
          begin
            // NEAREST hop wins for this class, and we stop: anything above a
            // Vcl./FMX. class is that framework's own business.
            if Found = '' then Found:= Seg
            else if not SameText(Found, Seg) then Mixed:= True;
            Break;
          end;
          if QAnc.Active then QAnc.Close;
          QAnc.ParamByName('sid').AsLargeInt:= CurId;
          QAnc.Open;
          if QAnc.Eof then CurId:= 0
          else
          begin
            CurId   := QAnc.Fields[0].AsLargeInt;
            CurQName:= QAnc.Fields[1].AsString  ;
          end;
          QAnc.Close;
        end;
      end;
      // Evidence of BOTH frameworks is evidence of neither: a file that
      // declares a Vcl-rooted and an FMX-rooted class cannot anchor, and
      // must decline exactly as a file with no evidence at all does.
      if Mixed then Result:= '' else Result:= Found;
      FAnchorCache.AddOrSetValue(AFileId, Result);
    finally
      Seen    .Free;
      StartQNs.Free;
      StartIds.Free;
      QAnc    .Free;
      QCls    .Free;
    end;
  finally
    FDerivingAnchor:= False;
  end;
end;

function TSQLiteSymbolStore.ResolveTypeNameToClass(const ATypeName: string; AScopeFileId: Int64): TSymbol;
var
  UsesNames       : TDictionary<string, Boolean>; // lowercased unit names in scope (own + used)
  SeenAlias       : TDictionary<string, Boolean>; // alias-chain cycle guard (lowercased names)
  CurScopeFileId  : Int64 ; // FileId LoadScopeNames was last called with
  CurScopeUnitName: string; // that file's own unit name (for the framework-prefix rule)

  procedure LoadScopeNames(AFileId: Int64);
  var
    Q: TFDQuery;
  begin
    UsesNames.Clear;
    CurScopeFileId  := AFileId;
    CurScopeUnitName:= '';
    if AFileId <= 0 then Exit;
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= FConn;
      // the file's own unit name(s) -- a same-file type is always in scope.
      Q.SQL.Text:= 'SELECT name FROM symbols WHERE file_id = :fid AND kind = ''unit''';
      Q.ParamByName('fid').AsLargeInt:= AFileId;
      Q.Open;
      while not Q.Eof do
      begin
        if CurScopeUnitName = '' then CurScopeUnitName:= Q.Fields[0].AsString;
        UsesNames.AddOrSetValue(LowerCase(Q.Fields[0].AsString), True);
        Q.Next;
      end;
      Q.Close;
      // used unit names (textual; resolved target_file_id NOT required).
      Q.SQL.Text:= 'SELECT unit_name FROM unit_uses WHERE file_id = :fid';
      Q.ParamByName('fid').AsLargeInt:= AFileId;
      Q.Open;
      while not Q.Eof do
      begin
        UsesNames.AddOrSetValue(LowerCase(Q.Fields[0].AsString), True);
        Q.Next;
      end;
      Q.Close;
    finally
      Q.Free;
    end;
  end;

  // True when a class/interface candidate is a forward-declaration stub
  // ('TFoo = class;' -- empty heritage, single line). Type aliases are never
  // stubs (their target lives in Signature, heritage is legitimately empty).
  function IsStub(const S: TSymbol): Boolean;
  begin
    Result:= (S.Kind in [skClass, skInterface]) and
             (S.Heritage.Trim = '') and (S.EndLine <= S.StartLine);
  end;

  // Best type candidate for a bare name: the single global definition when
  // unambiguous, else the shared scope rule (PickAncestorCandidateByScope --
  // same unit -> uses -> framework prefix -> decline). Id=0 when it declines.
  function PickCandidate(const AName: string): TSymbol;
  var
    Raw    : TArray<TSymbol>;
    Types  : TArray<TSymbol>;
    HasBody: Boolean         ;
    S      : TSymbol         ;
    Anchor : string          ;
  begin
    Result:= Default(TSymbol);
    Raw:= FindSymbolsByExactName(AName);
    // keep only the type-declaring kinds we can resolve/chase.
    SetLength(Types, 0);
    for S in Raw do
      if S.Kind in [skClass, skInterface, skRecord, skTypeAlias] then
        Types:= Types + [S];
    if Length(Types) = 0 then Exit;
    // drop forward-decl stubs when a real class/interface body of the name exists.
    HasBody:= False;
    for S in Types do
      if (S.Kind in [skClass, skInterface]) and not IsStub(S) then HasBody:= True;
    if HasBody then
    begin
      var Kept: TArray<TSymbol>;
      SetLength(Kept, 0);
      for S in Types do
        if not IsStub(S) then Kept:= Kept + [S];
      Types:= Kept;
    end;
    if Length(Types) = 0 then Exit;
    if Length(Types) = 1 then Exit(Types[0]);        // single global definition
    // ambiguous (2+ same-named candidates) -- apply the shared scope rule.
    // The ancestry anchor is derived HERE, lazily, and only for a scope unit
    // whose own name carries no namespace segment: it costs an ancestor climb
    // (cached per file), and rule 3 would not look at it for a dotted unit
    // anyway. Deriving it before the Length(Types) = 1 short-circuit above
    // would pay that cost on every unambiguous name for nothing.
    Anchor:= '';
    if UnitFrameworkPrefix(CurScopeUnitName) = '' then
      Anchor:= FrameworkAnchorForFile(CurScopeFileId);
    Result:= PickAncestorCandidateByScope(Types, CurScopeFileId, CurScopeUnitName,
                                          UsesNames, Anchor);
  end;

var
  Name: string ;
  Hops: Integer;
  Cand: TSymbol;
  Tgt : string ;
begin
  Result:= Default(TSymbol);
  if Trim(ATypeName) = '' then Exit;
  UsesNames:= TDictionary<string, Boolean>.Create;
  SeenAlias:= TDictionary<string, Boolean>.Create;
  try
    LoadScopeNames(AScopeFileId);
    Name:= Trim(ATypeName);
    Hops:= 0;
    while (Name <> '') and (Hops < 32) do
    begin
      Inc(Hops);
      if SeenAlias.ContainsKey(LowerCase(Name)) then Break; // alias cycle
      SeenAlias.Add(LowerCase(Name), True);
      Cand:= PickCandidate(Name);
      if Cand.Id <= 0 then Break;
      if Cand.Kind in [skClass, skInterface, skRecord] then Exit(Cand);
      if Cand.Kind = skTypeAlias then
      begin
        Tgt:= ParseFirstTypeToken(Cand.Signature);
        if Tgt = '' then Break;
        // resolve the alias TARGET in the alias's own unit scope (a nearest-first
        // re-scope: the target is written in terms of what the alias file uses).
        LoadScopeNames(Cand.FileId);
        Name:= Tgt;
        Continue;
      end;
      Break; // some other kind -- not chaseable
    end;
  finally
    SeenAlias.Free;
    UsesNames.Free;
  end;
end;

function TSQLiteSymbolStore.MemoizePropertyType(ASymbolId: Int64; const ATypeName: string): Boolean;
var
  Q: TFDQuery;
begin
  Result:= False;
  // Never mutate a read-only (query_only) handle, and never write garbage.
  if FReadOnly or (ASymbolId <= 0) or (Trim(ATypeName) = '') then Exit;
  Q:= TFDQuery.Create(nil);
  try
    try
      Q.Connection:= FConn;
      Q.SQL.Text  := 'UPDATE symbols SET signature = :sig WHERE id = :id AND kind = ''property''';
      Q.ParamByName('sig').AsString  := ': ' + Trim(ATypeName);
      Q.ParamByName('id' ).AsLargeInt:= ASymbolId;
      Q.ExecSQL;
      Result:= Q.RowsAffected > 0;
    except
      Result:= False; // best-effort memoization: a query must never fail on write error
    end;
  finally
    Q.Free;
  end;
end;

function TSQLiteSymbolStore.FindEnclosingRoutineByImpl(AFileId: Int64; ALine: Integer): TSymbol;
begin
  Result:= Default(TSymbol);
  if FQFindEnclRoutine.Active then FQFindEnclRoutine.Close;
  FQFindEnclRoutine.ParamByName('fid' ).AsLargeInt:= AFileId;
  FQFindEnclRoutine.ParamByName('line').AsInteger := ALine;
  FQFindEnclRoutine.Open;
  try
    if not FQFindEnclRoutine.IsEmpty then Result:= ReadSymbolFromQuery(FQFindEnclRoutine);
  finally
    FQFindEnclRoutine.Close;
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

procedure TSQLiteSymbolStore.ClearCompilerFindingsForFile(AFileId: Int64);
begin
  FConn.ExecSQL('DELETE FROM compiler_findings WHERE file_id = ?', [AFileId]);
end;

procedure TSQLiteSymbolStore.SetFileCompiledAt(AFileId: Int64; AUnix: Int64);
begin
  FConn.ExecSQL('UPDATE files SET last_compiled_unix = ? WHERE id = ?', [AUnix, AFileId]);
end;

function TSQLiteSymbolStore.GetFileCompiledAt(AFileId: Int64): Int64;
var Q: TFDQuery;
begin
  Result:= 0;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT last_compiled_unix FROM files WHERE id = ?';
    Q.Params[0].AsLargeInt:= AFileId;
    Q.Open;
    if (not Q.Eof) and (not Q.Fields[0].IsNull) then Result:= Q.Fields[0].AsLargeInt;
    Q.Close;
  finally
    Q.Free;
  end;
end;

function TSQLiteSymbolStore.GetFileMTime(AFileId: Int64): Int64;
var Q: TFDQuery;
begin
  Result:= 0;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT mtime_unix FROM files WHERE id = ?';
    Q.Params[0].AsLargeInt:= AFileId;
    Q.Open;
    if (not Q.Eof) and (not Q.Fields[0].IsNull) then Result:= Q.Fields[0].AsLargeInt;
    Q.Close;
  finally
    Q.Free;
  end;
end;

function TSQLiteSymbolStore.GetStaleFileIds: TArray<Int64>;
var Q: TFDQuery; L: TList<Int64>;
begin
  L:= TList<Int64>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    { BUGFIX (fresh compiler findings Task 4): the indexer's Pascal parser
      (TDelphi13Parser.LanguageName) records files.language = 'delphi13', never
      'pascal' -- the original WHERE language = 'pascal' matched zero rows, so
      GetStaleFileIds always returned empty. Match on file extension instead
      (.pas/.dpr/.dpk), which is what "Pascal source files only" in this
      method's doc-comment actually means and is independent of whichever
      string a given parser reports as its language name. }
    Q.SQL.Text:=
      'SELECT id FROM files ' +
      'WHERE (LOWER(path) LIKE ''%.pas'' OR LOWER(path) LIKE ''%.dpr'' OR LOWER(path) LIKE ''%.dpk'') ' +
      '  AND (last_compiled_unix IS NULL OR last_compiled_unix < mtime_unix)';
    Q.Open;
    while not Q.Eof do begin L.Add(Q.Fields[0].AsLargeInt); Q.Next; end;
    Q.Close;
    Result:= L.ToArray;
  finally
    Q.Free; L.Free;
  end;
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

// Sentinel stored in the last-segment map for a segment that 2+ DISTINCT file
// stems share ('controls' <- both 'vcl.controls' and 'fmx.controls'). Not a
// legal file stem (a stem is a lowercased basename), so it can never collide
// with a real one. Its presence makes rule B below decline that segment.
const
  CStemAmbiguous = '?';

procedure TSQLiteSymbolStore.ResolveUnitUseTargets;
{ Drives target_file_id resolution in Pascal rather than SQL because the
  basename-extract is fiddly across sqlite dialects (Win32 FireDAC's
  bundled sqlite lacks some 3.24+ functions). We pull every (file_id, path),
  compute the lowercase stem, build the two maps below, then UPDATE per
  distinct used-unit name.

  THE BUG THIS REPLACES (design doc criterion 12, measured on
  library-Win64.sqlite): the previous pass matched unit_uses.UNIT_NAME_NORM --
  which UnitNameNorm() defines as the LAST dotted segment, so 'Vcl.Controls'
  is stored as 'controls' -- against the FULL basename stem 'vcl.controls'.
  Those two can never be equal for a dotted unit name, so EVERY dotted `uses`
  row stayed NULL: 122 of 38512 resolved. Worse, the 122 that did resolve were
  WRONG -- they were dotted names landing on an unrelated file that happened to
  be named after their last segment ('uses Fmx.Editor.MaskEdit' -> FMX.MaskEdit.pas).

  Resolution rules, in order (first hit wins; no hit leaves the row NULL):
   A. EXACT: the lowercased used-unit name equals a file's lowercased basename
      stem. 'Vcl.Controls' -> Vcl.Controls.pas; 'Abcbtn' -> Abcbtn.pas. This is
      a NAME EQUALITY, not an inference, and it is what criterion 12 asks for.
   B. UNIT SCOPE NAMES, bare names only, never into a GUI namespace: a used
      name with NO dot may match a DOTTED stem by its last segment --
      'uses Grids' -> Data.Grids.pas -- but only when exactly one distinct stem
      carries that segment AND that stem's leading segment is not one of the
      two GUI frameworks (see IsGuiFrameworkPrefix). This is Delphi's own
      unit-scope-names resolution, in the only direction Delphi performs it.
      Three restrictions, each load-bearing and each independently pinned by
      tests/autotest/run_unit_uses_targets.ps1:
        * BARE ONLY. 'uses Zeta.Alpha' with no Zeta.Alpha.pas indexed stays
          NULL rather than seizing Ns.Alpha.pas. That direction is what
          produced both measured wrong-namespace matches.
        * UNIQUE STEM. 2+ stems carrying the segment means decline.
        * NEVER GUI. See the long comment at the call site: uniqueness is a
          property of what happens to be INDEXED, so it cannot by itself keep
          criterion 5. Refusing GUI-namespaced targets outright makes that a
          property of the rule.

  Measured effect on library-Win64.sqlite (85157 rows): 41.8% -> 91.0%
  resolved -- rule A 73652 rows, rule B 3871 rows across 106 bare names, none
  of them in a GUI namespace.

  NOT GUARANTEED: that a resolved target is the unit the Delphi compiler would
  have picked. Two indexed copies of the same unit (two source trees) collide
  on one stem and the LAST one read wins arbitrarily -- unchanged from before,
  and harmless because both copies declare the same unit. Nothing downstream
  may treat target_file_id as proof of anything beyond "some indexed file is
  named after this used unit".

  ANCESTOR RESOLUTION DOES NOT DEPEND ON THIS. ResolveAncestry scopes
  candidates from the TEXTUAL uses names (PickAncestorCandidateByScope), so a
  database whose target_file_id is entirely NULL -- every index built before
  this fix -- still resolves ancestors correctly without a re-index. The
  consumers that do read the column are ResolveHelpers, TCallResolver and the
  deps report. }
var
  QFiles      : TFDQuery                   ;
  QNames      : TFDQuery                   ;
  QUpdate     : TFDQuery                   ;
  StemToFileId: TDictionary<string, Int64> ;
  SegToStem   : TDictionary<string, string>; // last segment -> its ONLY stem, or CStemAmbiguous
  UsedNorms   : TList<string>              ; // parallel arrays: one entry per
  UsedFulls   : TList<string>              ; //   distinct (norm, lowercased name)
  Path        : string                     ;
  Stem        : string                     ;
  Seg         : string                     ;
  Seen        : string                     ;
  Slash       : Integer                    ;
  Dot         : Integer                    ;
  i           : Integer                    ;
  Fid         : Int64                      ;
begin
  StemToFileId:= TDictionary<string, Int64> .Create;
  SegToStem   := TDictionary<string, string>.Create;
  UsedNorms   := TList<string>.Create;
  UsedFulls   := TList<string>.Create;
  QFiles := TFDQuery.Create(nil);
  QNames := TFDQuery.Create(nil);
  QUpdate:= TFDQuery.Create(nil);
  try
    QFiles.Connection:= FConn;
    QFiles.SQL.Text:= 'SELECT id, path FROM files';
    QFiles.Open;
    while not QFiles.Eof do
    begin
      Path:= QFiles.FieldByName('path').AsString;
      // TWO DIFFERENT LastDelimiters live in this procedure, eight lines apart.
      // This one is TStringHelper.LastDelimiter -- a METHOD on Path, ZERO-based,
      // returning -1 for "absent", hence '>= 0' and the +2 to land one char past
      // the separator. The one just below is the GLOBAL System.SysUtils
      // LastDelimiter -- ONE-based, returning 0 for "absent", hence '> 0' and
      // +1. Both are correct; neither may be copied onto the other.
      Slash:= Path.LastDelimiter('\/');
      if Slash >= 0 then Stem:= Copy(Path, Slash + 2, MaxInt)
      else Stem:= Path;
      Stem:= LowerCase(ChangeFileExt(Stem, ''));
      if Stem <> '' then
      begin
        StemToFileId.AddOrSetValue(Stem, QFiles.FieldByName('id').AsLargeInt);
        Seg:= Stem;
        Dot:= LastDelimiter('.', Seg);          // GLOBAL, 1-based -- see above
        if Dot > 0 then Seg:= Copy(Seg, Dot + 1, MaxInt);
        // Distinct STEMS, not distinct files: two indexed copies of
        // Vcl.Controls.pas are one candidate unit, not an ambiguity.
        if not SegToStem.TryGetValue(Seg, Seen) then SegToStem.Add(Seg, Stem)
        else if (Seen <> CStemAmbiguous) and (Seen <> Stem) then SegToStem[Seg]:= CStemAmbiguous;
      end;
      QFiles.Next;
    end;
    QFiles.Close;

    { Pull the distinct used-unit names first and close the cursor: the UPDATE
      below writes the very table this reads. Mirrors ResolveAncestry's
      pull-everything-then-write idiom. }
    QNames.Connection:= FConn;
    QNames.SQL.Text:= 'SELECT DISTINCT unit_name_norm, LOWER(unit_name) AS un_lc ' +
                      'FROM unit_uses';
    QNames.Open;
    while not QNames.Eof do
    begin
      UsedNorms.Add(QNames.Fields[0].AsString);
      UsedFulls.Add(QNames.Fields[1].AsString);
      QNames.Next;
    end;
    QNames.Close;

    { Both keys are used: unit_name_norm hits idx_unit_uses_unit_norm so the
      UPDATE is an index seek rather than a scan of the whole table, and the
      LOWER(unit_name) equality is what actually selects the rows -- two units
      sharing a last segment ('Vcl.Controls' and 'FMX.Controls') share a norm
      and must NOT be updated together. }
    QUpdate.Connection:= FConn;
    QUpdate.SQL.Text:= 'UPDATE unit_uses SET target_file_id = :tid ' +
                       'WHERE unit_name_norm = :un AND LOWER(unit_name) = :full';
    QUpdate.Params.ParamByName('tid' ).DataType:= ftLargeint;
    QUpdate.Params.ParamByName('un'  ).DataType:= ftString;
    QUpdate.Params.ParamByName('full').DataType:= ftString;
    QUpdate.Prepare;
    FConn.StartTransaction;
    try
      { RECOMPUTE, don't top up. Filling only NULL rows made the pass unable to
        REPAIR a wrong value: on an incremental re-index a file that is not
        re-parsed keeps its unit_uses rows, so the 122 measured wrong dotted
        targets would have survived this fix forever. Clearing first makes the
        repair total, and the pass stays idempotent because the rules below are
        a pure function of (files, unit_uses.unit_name). Nothing else in the
        codebase ever writes this column -- UpsertUnitUse always inserts NULL --
        so no other producer's work is being discarded. The transaction is what
        makes the clear safe: a failure rolls back to the previous values rather
        than leaving the column empty. }
      FConn.ExecSQL('UPDATE unit_uses SET target_file_id = NULL');
      for i:= 0 to UsedFulls.Count - 1 do
      begin
        Stem:= UsedFulls[i];
        if Stem = '' then Continue;
        if not StemToFileId.ContainsKey(Stem) then           // rule A missed
        begin
          if Pos('.', Stem) > 0 then Continue;               // rule B is bare-only
          if not SegToStem.TryGetValue(Stem, Seen) then Continue;
          if Seen = CStemAmbiguous then Continue;            // 2+ stems -- decline
          { CRITERION 5, STRUCTURALLY. Rule B is an INFERENCE -- the used name
            does not name this file, Delphi's unit scope names do -- and an
            inference must never be able to hand a unit one GUI framework's
            code when it meant the other's. Uniqueness alone does not prevent
            that: it is a property of what happens to be INDEXED, so an index
            carrying FMX.Types.pas but not System.Types.pas would make a bare
            `uses Types` uniquely FireMonkey. Refusing every GUI-namespaced
            target makes the guarantee a property of the RULE instead.
            The obvious alternative -- accept a GUI target when the REFERENCING
            unit's own leading segment confirms it, the shape rule 2b uses --
            was measured on library-Win64.sqlite and is exactly equivalent
            here: of the 678 rows rule B would resolve into a GUI namespace,
            ZERO are written by a unit whose own segment is 'Vcl' or 'FMX'
            (they are undotted legacy units, plus a handful of 'dunitx' and
            'spring' ones). Fully-qualified `uses` is universal inside both
            frameworks, so a confirming case barely exists. This keeps 3871 of
            rule B's 4549 rows and costs the corpus-dependent 678.
            Rule A is deliberately NOT guarded: `uses Vcl.Controls` naming
            Vcl.Controls.pas is a name equality the unit itself stated, not an
            inference, and rules 1/2a of the ancestor scope rule cross for the
            same reason. }
          if IsGuiFrameworkPrefix(UnitFrameworkPrefix(Seen)) then Continue;
          Stem:= Seen;                                       // rule B hit
        end;
        if not StemToFileId.TryGetValue(Stem, Fid) then Continue;
        QUpdate.ParamByName('tid' ).AsLargeInt:= Fid;
        QUpdate.ParamByName('un'  ).AsString  := UsedNorms[i];
        QUpdate.ParamByName('full').AsString  := UsedFulls[i];
        QUpdate.ExecSQL;
      end;
      FConn.Commit;
    except
      FConn.Rollback;
      raise;
    end;
  finally
    QUpdate    .Free;
    QNames     .Free;
    QFiles     .Free;
    UsedFulls  .Free;
    UsedNorms  .Free;
    SegToStem  .Free;
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
  each ancestor to a defining class/interface symbol in the scope of the
  declaring unit, and rebuild type_ancestors.
  Mirrors ResolveUnitUseTargets: pull everything, resolve in memory, batch write.

  Task 4: the disambiguation is PickAncestorCandidateByScope -- the same
  function the query-time resolver (ResolveTypeNameToClass.PickCandidate)
  calls, gathering the same scope facts the same way. It used to be a private
  nested CandInScope over unit_uses.target_file_id, which had two consequences
  worth remembering:
    * it tested the RESOLVED uses graph, and that column was NULL for every
      dotted `uses` row (the criterion-12 bug, see ResolveUnitUseTargets), so
      whole namespaces had NO scope at all and every ambiguous ancestor in
      them was declined -- Vcl.StdCtrls.TCustomEdit's 'TWinControl' edge was
      written as ancestor_kind='?' for exactly this reason;
    * the two sides could drift apart, because the precedence lived twice.
  Now the precedence lives once, and the scope test is TEXTUAL, so it needs no
  re-index to be correct on databases already on disk.

  THE ANCHOR IS DELIBERATELY NOT SUPPLIED HERE (the '' passed as
  AScopeFrameworkAnchor below). FrameworkAnchorForFile derives its answer by
  climbing type_ancestors -- the very table this pass DELETEs and rebuilds --
  so mid-rebuild it would read a half-written table and its answer would
  depend on row order. '' is within that parameter's contract ("not derived")
  and costs only rule 3 for a LEGACY UNDOTTED scope unit, which the query-time
  climb still rescues with a real anchor once this pass has committed. A
  DOTTED scope unit derives rule 3's segment from its own name and is
  unaffected. This is also why FAnchorCache.Clear below stays sufficient:
  nothing inside this pass can populate that cache. }
var
  Q          : TFDQuery                            ;
  QIns       : TFDQuery                            ;
  NameToCands: TObjectDictionary<string, TList<TSymbol>>;
  { Scope facts per file, gathered exactly as ResolveTypeNameToClass's
    LoadScopeNames gathers them for one file: the file's own unit name, and
    the lowercased union of its own unit names with the textual
    unit_uses.unit_name entries. }
  FileUnit   : TDictionary<Int64, string>          ;
  FileUses   : TObjectDictionary<Int64, TDictionary<string, Boolean>>;
  Lc         : string                             ;
  Sym        : TSymbol                            ;
  Chosen     : TSymbol                            ; // the scope rule's pick, Id = 0 on a decline
  ScopeUnit  : string                             ; // inheriting file's own unit name ('' if none)
  ScopeUses  : TDictionary<string, Boolean>       ; // its scope-name set (nil if none)

  procedure NoteScopeName(AFileId: Int64; const AName: string);
  var D: TDictionary<string, Boolean>;
  begin
    if (AFileId <= 0) or (AName = '') then Exit;
    if not FileUses.TryGetValue(AFileId, D) then
    begin
      D:= TDictionary<string, Boolean>.Create;
      FileUses.Add(AFileId, D);
    end;
    D.AddOrSetValue(LowerCase(AName), True);
  end;

begin
  { Task 3c: FrameworkAnchorForFile's answers are derived from type_ancestors,
    which this pass is about to DELETE and rebuild -- drop them before the
    rebuild rather than serve a pre-rebuild anchor afterwards. Matters only when
    one process both indexes and queries through the same store instance; on a
    query-only open the cache is simply empty here. Nothing in this pass calls
    FrameworkAnchorForFile (see the header note on the '' anchor), so the cache
    cannot be re-poisoned between here and the commit. }
  FAnchorCache.Clear;
  NameToCands:= TObjectDictionary<string, TList<TSymbol>>.Create([doOwnsValues]);
  FileUnit   := TDictionary<Int64, string>.Create;
  FileUses   := TObjectDictionary<Int64, TDictionary<string, Boolean>>.Create([doOwnsValues]);
  Q   := TFDQuery.Create(nil);
  QIns:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    { 1. candidate class/interface symbols, indexed by lowercased simple name.
      qualified_name is load-bearing: PickAncestorCandidateByScope derives each
      candidate's DECLARING UNIT from it (DeclaringUnitOfQName) for rules 2
      and 3. Without it every candidate looks unit-less and both rules go
      silent. }
    Q.SQL.Text:= 'SELECT id, file_id, kind, name, qualified_name, heritage, start_line, end_line ' +
                 'FROM symbols WHERE kind IN (''class'',''interface'')';
    Q.Open;
    while not Q.Eof do
    begin
      Sym:= Default(TSymbol);
      Sym.Id           := Q.FieldByName('id'            ).AsLargeInt;
      Sym.FileId       := Q.FieldByName('file_id'       ).AsLargeInt;
      Sym.Kind         := TSymbolKind.FromText(Q.FieldByName('kind').AsString);
      Sym.Name         := Q.FieldByName('name'          ).AsString;
      Sym.QualifiedName:= Q.FieldByName('qualified_name').AsString;
      Sym.Heritage     := Q.FieldByName('heritage'      ).AsString;
      Sym.StartLine    := Q.FieldByName('start_line'    ).AsInteger;
      Sym.EndLine      := Q.FieldByName('end_line'      ).AsInteger;
      Lc:= LowerCase(Sym.Name);
      if not NameToCands.ContainsKey(Lc) then NameToCands.Add(Lc, TList<TSymbol>.Create);
      NameToCands[Lc].Add(Sym);
      Q.Next;
    end;
    Q.Close;
    { 1b. Drop forward-declaration stubs ('TFoo = class;' -- empty heritage,
      single line, no body) from any name that ALSO has a real definition. The
      parser emits a separate skClass symbol for a forward decl; leaving it in
      makes a same-file ancestor look like TWO in-scope candidates, so the
      unambiguous-resolution rule below bails and the ancestry edge is lost.
      Keep a lone stub (no body indexed) so a purely-external class still has a
      by-name row. }
    for var Cl in NameToCands.Values do
      if Cl.Count > 1 then
      begin
        var HasBody:= False;
        for var CI:= 0 to Cl.Count - 1 do
          if not ((Cl[CI].Heritage.Trim = '') and (Cl[CI].EndLine <= Cl[CI].StartLine)) then
          begin
            HasBody:= True;
            Break;
          end;
        if HasBody then
          for var CI:= Cl.Count - 1 downto 0 do
            if (Cl[CI].Heritage.Trim = '') and (Cl[CI].EndLine <= Cl[CI].StartLine) then
              Cl.Delete(CI);
      end;
    { 2. per-file SCOPE FACTS. Deliberately TEXTUAL, and deliberately the same
      two queries LoadScopeNames runs per file at query time -- the file's own
      unit name(s), then every unit_uses.unit_name as written. Nothing here
      reads target_file_id, so an index whose uses graph was never resolved
      (every index built before the criterion-12 fix) resolves ancestors just
      as well as a freshly built one; a re-index is an improvement to the
      OTHER consumers of that column, not a precondition for correct ancestry.
      ORDER BY id makes "the file's own unit name" the lowest-id unit symbol in
      the file, matching LoadScopeNames' first row for that file. }
    Q.SQL.Text:= 'SELECT file_id, name FROM symbols WHERE kind = ''unit'' ORDER BY id';
    Q.Open;
    while not Q.Eof do
    begin
      var Fid  := Q.Fields[0].AsLargeInt;
      var UName:= Q.Fields[1].AsString  ;
      if (Fid > 0) and (UName <> '') and not FileUnit.ContainsKey(Fid) then FileUnit.Add(Fid, UName);
      NoteScopeName(Fid, UName);
      Q.Next;
    end;
    Q.Close;
    Q.SQL.Text:= 'SELECT file_id, unit_name FROM unit_uses';
    Q.Open;
    while not Q.Eof do
    begin
      NoteScopeName(Q.Fields[0].AsLargeInt, Q.Fields[1].AsString);
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
            { A single global definition needs no disambiguation -- the same
              short-circuit PickCandidate makes at query time, and the reason
              the stub filter in step 1b matters so much. Otherwise hand the
              field to the ONE shared scope rule. It declines (Id = 0) when no
              rule narrows the field to one, and a decline is written out as
              ancestor_kind='?' exactly as before: when unsure, don't claim. }
            if Cands.Count = 1 then Chosen:= Cands[0]
            else
            begin
              ScopeUnit:= '' ;
              ScopeUses:= nil;
              FileUnit.TryGetValue(SymFile, ScopeUnit);
              FileUses.TryGetValue(SymFile, ScopeUses);
              { '' anchor: see this procedure's header -- type_ancestors is
                mid-rebuild here, so no anchor can honestly be derived. }
              Chosen:= PickAncestorCandidateByScope(Cands.ToArray, SymFile, ScopeUnit, ScopeUses, '');
            end;
            if Chosen.Id > 0 then
            begin
              RSymId := Chosen.Id;
              RFileId:= Chosen.FileId;
              RKind  := Chosen.Kind.ToText;
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
    FileUses.Free;
    FileUnit.Free;
  end; // try
end; // procedure

procedure TSQLiteSymbolStore.ResolveHelpers;
{ v15: whole-DB pass: for each record/class helper (symbols.is_helper = 1, set
  by TryWalkHelper for a declHelper-shaped declaration -- see the Task 0 probe
  finding in DRagLint.Parser.Delphi13.pas), identify its target type (stored
  verbatim in heritage, reusing that column's slot since a genuine helper has
  no ordinary ancestor list) and populate type_helpers edges. Mirrors
  ResolveAncestry's structure: candidates indexed by name, per-file in-scope
  resolution, batch write in one transaction.
  NOTE: filtering on "kind IN ('record','class') AND heritage <> ''" alone
  (without is_helper) would silently match nothing -- a plain record/class
  never has heritage text (Delphi disallows record ancestors, and TryWalkHelper
  is the ONLY emitter that ever populates Heritage on a helper-shaped symbol),
  so is_helper is the load-bearing predicate here, not a redundant filter. }
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
    { 1. candidate type symbols (all, any kind), indexed by lowercased simple name. }
    Q.SQL.Text:= 'SELECT id, file_id, kind, name FROM symbols WHERE kind IS NOT NULL';
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
    { 3. rebuild helper edges from scratch. }
    QIns.Connection:= FConn;
    QIns.SQL.Text  := 'INSERT INTO type_helpers(helper_symbol_id, target_name, ' +
                      '  target_symbol_id, target_file_id, helper_kind) ' +
                      'VALUES (:hsid, :tn, :tsid, :tfid, :hk)';
    QIns.Params.ParamByName('tsid').DataType:= ftLargeint;
    QIns.Params.ParamByName('tfid').DataType:= ftLargeint;
    Q.SQL.Text:= 'SELECT id, file_id, kind, heritage FROM symbols ' +
                 'WHERE is_helper = 1 AND heritage IS NOT NULL AND heritage <> ''''';
    FConn.StartTransaction;
    try
      FConn.ExecSQL('DELETE FROM type_helpers');
      Q.Open;
      while not Q.Eof do
      begin
        var HelperId  := Q.FieldByName('id'      ).AsLargeInt;
        var HelperFile:= Q.FieldByName('file_id' ).AsLargeInt;
        var HelperKind:= Q.FieldByName('kind'    ).AsString;
        var TargetName:= SplitHeritageList(Q.FieldByName('heritage').AsString);
        { A helper has exactly one target (the single heritage entry).
          We ignore multiple targets (malformed, but graceful degradation). }
        if Length(TargetName) > 0 then
        begin
          var TName   := NormalizeAncestorName(TargetName[0]);
          if TName <> '' then
          begin
            var TSymId : Int64  := 0;
            var TFileId: Int64  := 0;
            var Cands  : TList<TSymbol>;
            if NameToCands.TryGetValue(LowerCase(TName), Cands) then
            begin
              var InScopeIdx  := -1;
              var InScopeCount:= 0;
              for var ci:= 0 to Cands.Count - 1 do
                if CandInScope(HelperFile, Cands[ci].FileId) then
                begin
                  Inc(InScopeCount);
                  if InScopeIdx < 0 then InScopeIdx:= ci;
                end;
              { Resolve when unambiguous: exactly one in-scope candidate, or
                (none in scope) a single global definition. Otherwise leave
                unresolved. }
              if InScopeCount = 1 then
              begin
                TSymId := Cands[InScopeIdx].Id;
                TFileId:= Cands[InScopeIdx].FileId;
              end
              else if (InScopeCount = 0) and (Cands.Count = 1) then
              begin
                TSymId := Cands[0].Id;
                TFileId:= Cands[0].FileId;
              end;
            end;
            QIns.ParamByName('hsid').AsLargeInt:= HelperId;
            QIns.ParamByName('tn'  ).AsString  := TName;
            QIns.ParamByName('hk'  ).AsString  := HelperKind;
            if TSymId > 0 then
            begin
              QIns.ParamByName('tsid').AsLargeInt:= TSymId;
              QIns.ParamByName('tfid').AsLargeInt:= TFileId;
            end
            else
            begin
              QIns.ParamByName('tsid').Clear;
              QIns.ParamByName('tfid').Clear;
            end;
            QIns.ExecSQL;
          end;
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

function TSQLiteSymbolStore.FindDescendantNames(const AAncestorName: string): TArray<string>;
{ Reverse of IsDescendantOf: every class whose TRANSITIVE ancestor closure includes
  AAncestorName. type_ancestors stores DIRECT parent edges (child symbol_id ->
  ancestor_name), so transitivity needs a recursive walk. A SQLite recursive CTE
  seeds from classes directly deriving AAncestorName, then repeatedly finds classes
  whose direct ancestor is any already-found class (matched by name). Bounded by
  SQLite's cycle handling on the CTE + a UNION (not UNION ALL) to dedupe. Returns
  distinct class names, sorted. Backs "list every TControl descendant" for the
  conversion editor's class pickers. }
var
  Q   : TFDQuery   ;
  List: TStringList;
begin
  List:= TStringList.Create;
  Q   := TFDQuery.Create(nil);
  try
    List.Sorted:= True; List.Duplicates:= dupIgnore; List.CaseSensitive:= False;
    Q.Connection:= FConn;
    Q.SQL.Text  :=
      'WITH RECURSIVE desc_names(name) AS ( ' +
      '  SELECT DISTINCT s.name ' +
      '    FROM type_ancestors ta JOIN symbols s ON s.id = ta.symbol_id ' +
      '   WHERE ta.ancestor_name = :anc COLLATE NOCASE AND s.kind = ''class'' ' +
      '  UNION ' +
      '  SELECT DISTINCT s.name ' +
      '    FROM type_ancestors ta ' +
      '    JOIN symbols s   ON s.id = ta.symbol_id AND s.kind = ''class'' ' +
      '    JOIN desc_names d ON ta.ancestor_name = d.name COLLATE NOCASE ' +
      ') ' +
      'SELECT name FROM desc_names ORDER BY name';
    Q.ParamByName('anc').AsString:= AAncestorName;
    Q.Open;
    while not Q.Eof do
    begin
      if Trim(Q.Fields[0].AsString) <> '' then List.Add(Q.Fields[0].AsString);
      Q.Next;
    end;
    Q.Close;
    Result:= List.ToStringArray;
  finally
    Q.Free;
    List.Free;
  end;
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

{ Shared row-mapper for both FindHelpersOfType(name) and
  FindHelpersOfTypeSymbol(id): both queries select the same th.* + s.kind
  column set, only the WHERE clause differs. }
procedure ReadHelperEdges(Q: TFDQuery; List: TList<THelperEdge>);
var
  Edge: THelperEdge;
begin
  while not Q.Eof do
  begin
    Edge:= Default(THelperEdge);
    Edge.HelperSymbolId := Q.FieldByName('helper_symbol_id').AsLargeInt;
    Edge.TargetName     := Q.FieldByName('target_name').AsString;
    if not Q.FieldByName('target_symbol_id').IsNull then
      Edge.TargetSymbolId:= Q.FieldByName('target_symbol_id').AsLargeInt;
    if not Q.FieldByName('target_file_id').IsNull then
      Edge.TargetFileId  := Q.FieldByName('target_file_id').AsLargeInt;
    Edge.HelperKind     := Q.FieldByName('helper_kind').AsString;
    List.Add(Edge);
    Q.Next;
  end;
  Q.Close;
end;

function TSQLiteSymbolStore.FindHelpersOfType(const ATargetName: string): TArray<THelperEdge>;
var
  Q   : TFDQuery           ;
  List: TList<THelperEdge>;
begin
  List:= TList<THelperEdge>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT th.*, s.kind FROM type_helpers th ' +
                 'JOIN symbols s ON s.id = th.helper_symbol_id ' +
                 'WHERE th.target_name = :target_name';
    Q.ParamByName('target_name').AsString:= ATargetName;
    Q.Open;
    ReadHelperEdges(Q, List);
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

function TSQLiteSymbolStore.FindHelpersOfTypeSymbol(ATargetSymbolId: Int64): TArray<THelperEdge>;
{ Task 9b (FP fix): identity match on type_helpers.target_symbol_id. Rows
  with a NULL target_symbol_id (heritage name did not uniquely resolve at
  index time) never match ANY id, including ATargetSymbolId -- deliberate:
  an unresolved edge cannot be proven to target this specific symbol rather
  than some other same-named type, so treating it as a match would just
  reintroduce the false-cross-link risk this method exists to remove. }
var
  Q   : TFDQuery           ;
  List: TList<THelperEdge>;
begin
  List:= TList<THelperEdge>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT th.*, s.kind FROM type_helpers th ' +
                 'JOIN symbols s ON s.id = th.helper_symbol_id ' +
                 'WHERE th.target_symbol_id = :target_symbol_id';
    Q.ParamByName('target_symbol_id').AsLargeInt:= ATargetSymbolId;
    Q.Open;
    ReadHelperEdges(Q, List);
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

end.
