unit DRagLint.Query.LockSites;

{ drag-lint 1.56 -- lane THR-S: S6, the lock sites of a project (which lock, where taken, where released),
  read by DRagLint.V156.THR (G-05 lock-order-inversion) and by the check-init preset lock-held-when (G-56).

  A LOCK SITE is one call that takes or releases a lock. It is read from the index only (refs,
  ref_receivers, symbols, files): nothing is parsed and nothing is persisted (no extractor change).
    * Which call counts is decided by the NAME of the call AND the declared TYPE of its receiver
      (refs.receiver_type_text): `FLock.Enter` on a TCriticalSection is a site, `Edit1.Enter` and
      `Form.Release` are not. A receiver whose type the index does not name is never a site.
    * Which lock it is (the IDENTITY) is the symbol the receiver ref resolves to. Two sites in two routines
      are the same lock only when both are EXACT: a field reached through Self, or a unit-level variable.
      A local, a parameter, a field of another object, a property or any other expression is kept, with
      its text, but its LockKey only means something inside its own routine.
    * Sites of one routine are in source order. An enter is paired with the next leave of the same key
      (innermost first); the pair is a REGION, the stretch of source the lock is held over. An enter
      with no leave gives an OPEN region up to the end of the routine.
  Limits: source order stands in for control flow (a leave in an `if` branch closes the region where it is
  written); a lock taken inside an anonymous method is listed under the routine that declares it; a
  `with` receiver is not followed. }

interface

uses
  DRagLint.Core.Interfaces
  ;

type
  /// <summary>What kind of lock a site works on, decided by the declared type of the lock.</summary>
  /// <remarks>lskCriticalSection: TCriticalSection and descendants. lskMonitor: TMonitor.Enter(Obj).
  /// lskWinapiCs: TRTLCriticalSection through EnterCriticalSection or its record helper.
  /// lskReadWrite: TMultiReadExclusiveWriteSynchronizer, TLightweightMREW, IReadWriteSync.
  /// lskMutex: TMutex. lskSpinLock: TSpinLock. lskThreadList: TThreadList.LockList.</remarks>
  TLockSiteKind = (lskCriticalSection, lskMonitor, lskWinapiCs, lskReadWrite, lskMutex, lskSpinLock, lskThreadList);

  /// <summary>What a site does to its lock.</summary>
  /// <remarks>lsoTryEnter takes the lock only when the call answers True; the region it opens is
  /// therefore conditional, and a caller that needs certainty skips it.</remarks>
  TLockSiteOp = (lsoEnter, lsoTryEnter, lsoLeave);

  /// <summary>How well the lock of a site is known.</summary>
  /// <remarks>liSelfField: a field of the routine's own object (no receiver, or Self). liGlobal: a
  /// unit-level variable. liSelf: the object itself (TMonitor.Enter(Self)). These three are EXACT.
  /// liOtherField: a field of another object. liLocal / liParam: a local variable / a parameter.
  /// liProperty: a property. liExpression: anything else, or a receiver the index did not resolve.</remarks>
  TLockIdentity = (liSelfField, liGlobal, liSelf, liOtherField, liLocal, liParam, liProperty, liExpression);

  /// <summary>One call that takes or releases a lock.</summary>
  /// <remarks>A plain value; no ownership. Line and Col are 1-based and point at the call name
  /// (`Enter` in `FLock.Enter`), as refs.start_line / start_col do.</remarks>
  TLockSite = record
    /// <summary>refs.id of the call; join call_edges / member_accesses on it.</summary>
    RefId: Int64;
    /// <summary>Line of the call name.</summary>
    Line: Integer;
    /// <summary>Column of the call name.</summary>
    Col: Integer;
    /// <summary>Kind of lock.</summary>
    Kind: TLockSiteKind;
    /// <summary>Enter, try-enter or leave.</summary>
    Op: TLockSiteOp;
    /// <summary>True for the shared (reader) side of a read-write lock: BeginRead / EndRead.</summary>
    Shared: Boolean;
    /// <summary>The call as written: Enter, Acquire, Leave, ...</summary>
    CallName: string;
    /// <summary>The lock as written: `FLock`, `Self.FLock`, `pOther.FLock`.</summary>
    LockText: string;
    /// <summary>Declared type of the lock as the index has it.</summary>
    TypeText: string;
    /// <summary>How the lock is known.</summary>
    Identity: TLockIdentity;
    /// <summary>symbols.id of the lock (field, variable, parameter, property), 0 when not resolved.</summary>
    LockSymbolId: Int64;
    /// <summary>Qualified name of LockSymbolId, '' when not resolved.</summary>
    LockQName: string;
    /// <summary>Identity as one string. Equal keys in ONE routine are the same lock; equal keys in two
    /// routines are the same lock only when Exact.</summary>
    LockKey: string;
    /// <summary>True for liSelfField, liGlobal and liSelf: the key holds across routines (the same
    /// class instance is assumed).</summary>
    Exact: Boolean;
    /// <summary>Index in TRoutineLockSites.Sites of the paired leave (for an enter) or enter (for a
    /// leave); -1 when the site has no partner in the routine.</summary>
    Mate: Integer;
  end;

  /// <summary>The stretch of one routine a lock is held over: from an enter to its leave.</summary>
  /// <remarks>Positions are those of the two call names. Open = no leave in the routine: the region
  /// then ends at the last line of the routine body.</remarks>
  TLockRegion = record
    /// <summary>LockKey of the enter site.</summary>
    LockKey: string;
    /// <summary>Exact of the enter site.</summary>
    Exact: Boolean;
    /// <summary>Index of the enter site in Sites.</summary>
    EnterSite: Integer;
    /// <summary>Index of the leave site in Sites; -1 when Open.</summary>
    LeaveSite: Integer;
    /// <summary>True when the routine never leaves the lock.</summary>
    Open: Boolean;
    /// <summary>Line of the enter call.</summary>
    StartLine: Integer;
    /// <summary>Column of the enter call.</summary>
    StartCol: Integer;
    /// <summary>Line of the leave call, or the last line of the routine when Open.</summary>
    EndLine: Integer;
    /// <summary>Column of the leave call, or MaxInt when Open.</summary>
    EndCol: Integer;
    /// <summary>True when the position lies after the enter call and before the leave call.</summary>
    /// <param name="pLine">1-based line.</param>
    /// <param name="pCol">1-based column.</param>
    /// <returns>False for the two call positions themselves.</returns>
    function Contains(pLine, pCol: Integer): Boolean;
  end;

  /// <summary>Every lock site of one routine, in source order, with the regions they form.</summary>
  /// <remarks>RoutineId is refs.enclosing_symbol_id of the sites; 0 for code outside any routine
  /// (a unit's initialization part).</remarks>
  TRoutineLockSites = record
    /// <summary>symbols.id of the routine.</summary>
    RoutineId: Int64;
    /// <summary>Qualified name of the routine.</summary>
    RoutineQName: string;
    /// <summary>files.id of the file holding the routine body.</summary>
    FileId: Int64;
    /// <summary>Path of that file as the index stores it.</summary>
    FilePath: string;
    /// <summary>The sites, by line then column.</summary>
    Sites: TArray<TLockSite>;
    /// <summary>The regions, in the order of their enter sites.</summary>
    Regions: TArray<TLockRegion>;
    /// <summary>The regions that hold at a position, outermost first.</summary>
    /// <param name="pLine">1-based line.</param>
    /// <param name="pCol">1-based column.</param>
    /// <returns>Indexes into Regions; nil when no lock is held there.</returns>
    function HeldAt(pLine, pCol: Integer): TArray<Integer>;
  end;

/// <summary>The lock sites of every routine in the index.</summary>
/// <param name="pStore">An open project index; nil or a store that is not SQLite answers nil.</param>
/// <returns>One entry per routine that has at least one site, by file path then first site.</returns>
/// <remarks>Read-only. One scan of refs; call it once per run and keep the result.</remarks>
function LockSitesOfProject(const pStore: ISymbolStore): TArray<TRoutineLockSites>;

/// <summary>The lock sites of the routines of one file.</summary>
/// <param name="pStore">An open project index; nil answers nil.</param>
/// <param name="pFileId">files.id.</param>
/// <returns>One entry per routine of the file that has at least one site, by first site.</returns>
/// <remarks>Read-only.</remarks>
function LockSitesOfFile(const pStore: ISymbolStore; pFileId: Int64): TArray<TRoutineLockSites>;

/// <summary>The lock sites of one routine.</summary>
/// <param name="pStore">An open project index; nil answers an empty record.</param>
/// <param name="pRoutineId">symbols.id of the routine (the id call_edges.target_symbol_id names).</param>
/// <returns>The routine's sites and regions; Sites = nil when it has none. RoutineId is always pRoutineId.</returns>
/// <remarks>Read-only.</remarks>
function LockSitesOfRoutine(const pStore: ISymbolStore; pRoutineId: Int64): TRoutineLockSites;

/// <summary>Renders lock sites as one JSON document: {"routines":[{routine, file, sites[], regions[]}]}.</summary>
/// <param name="pRoutines">Any result of the three queries.</param>
/// <returns>Compact JSON; enum values as lower-case words (LockSiteKindName and the others).</returns>
function LockSitesJson(const pRoutines: TArray<TRoutineLockSites>): string;

/// <summary>The word a lock kind is printed as: critical-section, monitor, winapi-cs, read-write, mutex, spin-lock, thread-list.</summary>
/// <param name="pKind">The kind.</param>
/// <returns>A lower-case word.</returns>
function LockSiteKindName(pKind: TLockSiteKind): string;

/// <summary>The word a site operation is printed as: enter, try-enter, leave.</summary>
/// <param name="pOp">The operation.</param>
/// <returns>A lower-case word.</returns>
function LockSiteOpName(pOp: TLockSiteOp): string;

/// <summary>The word an identity is printed as: self-field, global, self, other-field, local, param, property, expression.</summary>
/// <param name="pIdentity">The identity.</param>
/// <returns>A lower-case word.</returns>
function LockIdentityName(pIdentity: TLockIdentity): string;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , System.JSON
  , FireDAC.Comp.Client
  , DRagLint.Storage.SQLite
  ;

type
  { One row of the lock vocabulary: a call name on a receiver of one declared type. }
  TLockCall = record
    TypeLeaf: string;   // lower-case type name without unit and without generic arguments
    Call    : string;   // lower-case call name
    Kind    : TLockSiteKind;
    Op      : TLockSiteOp;
    Shared  : Boolean;
  end;

const
  KIND_NAMES    : array[TLockSiteKind] of string = ('critical-section', 'monitor', 'winapi-cs', 'read-write', 'mutex',
    'spin-lock', 'thread-list');
  OP_NAMES      : array[TLockSiteOp] of string = ('enter', 'try-enter', 'leave');
  IDENTITY_NAMES: array[TLockIdentity] of string = ('self-field', 'global', 'self', 'other-field', 'local', 'param',
    'property', 'expression');
  EXACT_IDENTITIES = [liSelfField, liGlobal, liSelf];
  NO_MATE   = -1;
  SELF_TEXT = 'Self';
  { LockKey shapes. Ids and lower-cased source text only. }
  KEY_SYMBOL     = 'sym:%d';
  KEY_SYMBOL_VIA = 'sym:%d@%s';
  KEY_TEXT       = 'text:%d:%s';
  { symbols.kind of the things a lock can be. }
  SYM_FIELD    = 'field';
  SYM_VAR      = 'var';
  SYM_LOCAL    = 'local_var';
  SYM_PARAM    = 'param';
  SYM_PROPERTY = 'property';
  T_CRITICAL_SECTION = 'tcriticalsection';

  LOCK_CALLS: array[0..4] of TLockCall = (
    (TypeLeaf: T_CRITICAL_SECTION; Call: 'enter';    Kind: lskCriticalSection; Op: lsoEnter;    Shared: False),
    (TypeLeaf: T_CRITICAL_SECTION; Call: 'acquire';  Kind: lskCriticalSection; Op: lsoEnter;    Shared: False),
    (TypeLeaf: T_CRITICAL_SECTION; Call: 'tryenter'; Kind: lskCriticalSection; Op: lsoTryEnter; Shared: False),
    (TypeLeaf: T_CRITICAL_SECTION; Call: 'leave';    Kind: lskCriticalSection; Op: lsoLeave;    Shared: False),
    (TypeLeaf: T_CRITICAL_SECTION; Call: 'release';  Kind: lskCriticalSection; Op: lsoLeave;    Shared: False)
  );

  { %0:s = the quoted call names of LOCK_CALLS, %1:s = '' or one more AND on ids. No user text reaches the SQL.
    A statement call is stored twice (call + member-access) and a call in an expression once (member-access):
    both kinds are read and the loader keeps one row per position. }
  SQL_SITES =
    'SELECT r.id, r.file_id, f.path, r.name_text, r.start_line, r.start_col, r.receiver_text, r.receiver_type_text, ' +
    'r.enclosing_symbol_id AS routine_id, e.qualified_name AS routine_qname, e.impl_end_line AS routine_end, ' +
    'x.symbol_id AS lock_id, x.receiver_text AS lock_receiver, s.kind AS lock_kind, s.qualified_name AS lock_qname ' +
    'FROM refs r JOIN files f ON f.id = r.file_id ' +
    'LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id ' +
    'LEFT JOIN ref_receivers rr ON rr.ref_id = r.id ' +
    'LEFT JOIN refs x ON x.id = rr.receiver_ref_id ' +
    'LEFT JOIN symbols s ON s.id = x.symbol_id ' +
    'WHERE r.kind IN (''call'', ''member-access'') AND r.name_text COLLATE NOCASE IN (%0:s)%1:s ' +
    'ORDER BY f.path, r.file_id, r.start_line, r.start_col, r.kind';
  { Column order of SQL_SITES. }
  COL_ID = 0;
  COL_FILE_ID = 1;
  COL_PATH = 2;
  COL_NAME_TEXT = 3;
  COL_START_LINE = 4;
  COL_START_COL = 5;
  COL_RECEIVER_TEXT = 6;
  COL_RECEIVER_TYPE_TEXT = 7;
  COL_ROUTINE_ID = 8;
  COL_ROUTINE_QNAME = 9;
  COL_ROUTINE_END = 10;
  COL_LOCK_ID = 11;
  COL_LOCK_RECEIVER = 12;
  COL_LOCK_KIND = 13;
  COL_LOCK_QNAME = 14;
  SCOPE_FILE    = ' AND r.file_id = %d';
  SCOPE_ROUTINE = ' AND r.enclosing_symbol_id = %d';

function LockSiteKindName(pKind: TLockSiteKind): string;
begin
  Result:= KIND_NAMES[pKind];
end;

function LockSiteOpName(pOp: TLockSiteOp): string;
begin
  Result:= OP_NAMES[pOp];
end;

function LockIdentityName(pIdentity: TLockIdentity): string;
begin
  Result:= IDENTITY_NAMES[pIdentity];
end;

{ True when A lies before B in the source. }
function Before(pLineA, pColA, pLineB, pColB: Integer): Boolean;
begin
  Result:= (pLineA < pLineB) or ((pLineA = pLineB) and (pColA < pColB));
end;

function TLockRegion.Contains(pLine, pCol: Integer): Boolean;
begin
  Result:= Before(StartLine, StartCol, pLine, pCol) and Before(pLine, pCol, EndLine, EndCol);
end;

function TRoutineLockSites.HeldAt(pLine, pCol: Integer): TArray<Integer>;
begin
  Result:= nil;
  for var I:= 0 to High(Regions) do
    if Regions[I].Contains(pLine, pCol) then Result:= Result + [I];
end;

{ `System.SyncObjs.TCriticalSection` / `TThreadList<Integer>` -> the bare lower-case type name. }
function TypeLeaf(const pTypeText: string): string;
begin
  Result:= LowerCase(Trim(pTypeText));
  var Cut:= Pos('<', Result);
  if Cut > 0 then Result:= Trim(Copy(Result, 1, Cut - 1));
  Result:= Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

function FindLockCall(const pTypeLeaf, pCall: string; out pFound: TLockCall): Boolean;
begin
  Result:= False;
  pFound:= Default(TLockCall);
  for var I:= Low(LOCK_CALLS) to High(LOCK_CALLS) do
    if (LOCK_CALLS[I].Call = pCall) and (LOCK_CALLS[I].TypeLeaf = pTypeLeaf) then
    begin
      pFound:= LOCK_CALLS[I];
      Exit(True);
    end;
end;

{ The call names of LOCK_CALLS as a SQL list, each once. }
function CallNameList: string;
begin
  Result:= '';
  var Seen:= TList<string>.Create;
  try
    for var I:= Low(LOCK_CALLS) to High(LOCK_CALLS) do
      if not Seen.Contains(QuotedStr(LOCK_CALLS[I].Call)) then
        Seen.Add(QuotedStr(LOCK_CALLS[I].Call));
    Result:= string.Join(', ', Seen.ToArray);
  finally
    Seen.Free;
  end;
end;

{ Fills Identity, Exact and LockKey from the symbol the lock resolves to (pSymbolKind = '' when it does not).
  pOuterReceiver is what the lock itself is reached through: '' or Self = the routine's own object. }
procedure SetIdentity(var pSite: TLockSite; const pSymbolKind, pOuterReceiver: string; pRoutineId: Int64);
begin
  var OnSelf:= (pOuterReceiver = '') or SameText(pOuterReceiver, SELF_TEXT);
  if pSite.LockSymbolId = 0 then pSite.Identity:= liExpression
  else if pSymbolKind = SYM_FIELD then pSite.Identity:= if OnSelf then liSelfField else liOtherField
  else if pSymbolKind = SYM_VAR then pSite.Identity:= liGlobal
  else if pSymbolKind = SYM_LOCAL then pSite.Identity:= liLocal
  else if pSymbolKind = SYM_PARAM then pSite.Identity:= liParam
  else if pSymbolKind = SYM_PROPERTY then pSite.Identity:= liProperty
  else pSite.Identity:= liExpression;
  pSite.Exact:= pSite.Identity in EXACT_IDENTITIES;
  case pSite.Identity of
    liSelfField, liGlobal, liLocal, liParam:
      pSite.LockKey:= Format(KEY_SYMBOL, [pSite.LockSymbolId]);
    liOtherField, liProperty:
      pSite.LockKey:= Format(KEY_SYMBOL_VIA, [pSite.LockSymbolId, LowerCase(pSite.LockText)]);
  else
    pSite.LockKey:= Format(KEY_TEXT, [pRoutineId, LowerCase(pSite.LockText)]);
  end;
end;

{ The current row as a site; False when the call is not a lock call for the type of its receiver. }
function ReadSite(const pQuery: TFDQuery; out pSite: TLockSite): Boolean;
var
  Call: TLockCall;
begin
  pSite:= Default(TLockSite);
  var TypeText:= pQuery.Fields[COL_RECEIVER_TYPE_TEXT].AsString;
  var CallName:= pQuery.Fields[COL_NAME_TEXT].AsString;
  Result:= FindLockCall(TypeLeaf(TypeText), LowerCase(CallName), Call);
  if not Result then Exit;
  pSite.RefId       := pQuery.Fields[COL_ID].AsLargeInt;
  pSite.Line        := pQuery.Fields[COL_START_LINE].AsInteger;
  pSite.Col         := pQuery.Fields[COL_START_COL].AsInteger;
  pSite.Kind        := Call.Kind;
  pSite.Op          := Call.Op;
  pSite.Shared      := Call.Shared;
  pSite.CallName    := CallName;
  pSite.LockText    := pQuery.Fields[COL_RECEIVER_TEXT].AsString;
  pSite.TypeText    := TypeText;
  pSite.LockSymbolId:= pQuery.Fields[COL_LOCK_ID].AsLargeInt;
  pSite.LockQName   := pQuery.Fields[COL_LOCK_QNAME].AsString;
  pSite.Mate        := NO_MATE;
  SetIdentity(pSite, pQuery.Fields[COL_LOCK_KIND].AsString, pQuery.Fields[COL_LOCK_RECEIVER].AsString,
    pQuery.Fields[COL_ROUTINE_ID].AsLargeInt);
end;

{ Opens a region at enter site pEnter; it stays open (to the end of the routine) until CloseRegion. }
function OpenRegion(var pRoutine: TRoutineLockSites; pEnter, pRoutineEnd: Integer): Integer;
var
  Region: TLockRegion;
begin
  Region:= Default(TLockRegion);
  Region.LockKey  := pRoutine.Sites[pEnter].LockKey;
  Region.Exact    := pRoutine.Sites[pEnter].Exact;
  Region.EnterSite:= pEnter;
  Region.LeaveSite:= NO_MATE;
  Region.Open     := True;
  Region.StartLine:= pRoutine.Sites[pEnter].Line;
  Region.StartCol := pRoutine.Sites[pEnter].Col;
  Region.EndLine  := if pRoutineEnd > 0 then pRoutineEnd else MaxInt;
  Region.EndCol   := MaxInt;
  pRoutine.Regions:= pRoutine.Regions + [Region];
  Result:= High(pRoutine.Regions);
end;

procedure CloseRegion(var pRoutine: TRoutineLockSites; pRegion, pLeave: Integer);
begin
  var Enter:= pRoutine.Regions[pRegion].EnterSite;
  pRoutine.Regions[pRegion].LeaveSite:= pLeave;
  pRoutine.Regions[pRegion].Open     := False;
  pRoutine.Regions[pRegion].EndLine  := pRoutine.Sites[pLeave].Line;
  pRoutine.Regions[pRegion].EndCol   := pRoutine.Sites[pLeave].Col;
  pRoutine.Sites[Enter].Mate := pLeave;
  pRoutine.Sites[pLeave].Mate:= Enter;
end;

{ Pairs every leave with the innermost open enter of the same lock (and the same side of a read-write lock). }
procedure BuildRegions(var pRoutine: TRoutineLockSites; pRoutineEnd: Integer);
begin
  var Open:= TList<Integer>.Create;
  try
    for var I:= 0 to High(pRoutine.Sites) do
    begin
      if pRoutine.Sites[I].Op <> lsoLeave then
      begin
        Open.Add(OpenRegion(pRoutine, I, pRoutineEnd));
        Continue;
      end;
      for var K:= Open.Count - 1 downto 0 do
      begin
        var Enter:= pRoutine.Regions[Open[K]].EnterSite;
        if (pRoutine.Sites[Enter].LockKey = pRoutine.Sites[I].LockKey)
          and (pRoutine.Sites[Enter].Shared = pRoutine.Sites[I].Shared) then
        begin
          CloseRegion(pRoutine, Open[K], I);
          Open.Delete(K);
          Break;
        end;
      end;
    end;
  finally
    Open.Free;
  end;
end;

{ Every lock site the scope admits, grouped by routine, regions built. pScope = '' or one AND on ids. }
function LoadSites(const pStore: ISymbolStore; const pScope: string): TArray<TRoutineLockSites>;
var
  Site: TLockSite;
  At  : Integer;
begin
  Result:= nil;
  if (pStore = nil) or (pStore is not TSQLiteSymbolStore) then Exit;
  var Ends: TArray<Integer>:= nil;
  var IndexOf:= TDictionary<string, Integer>.Create;
  var Query:= TFDQuery.Create(nil);
  try
    Query.Connection:= (pStore as TSQLiteSymbolStore).GetConnection;
    Query.SQL.Text  := Format(SQL_SITES, [CallNameList, pScope]);
    Query.Open;
    var LastPosition:= '';
    while not Query.Eof do
    begin
      var FileId:= Query.Fields[COL_FILE_ID].AsLargeInt;
      var Position:= Format('%d:%d:%d', [FileId, Query.Fields[COL_START_LINE].AsInteger,
        Query.Fields[COL_START_COL].AsInteger]);
      if (Position <> LastPosition) and ReadSite(Query, Site) then
      begin
        var RoutineId:= Query.Fields[COL_ROUTINE_ID].AsLargeInt;
        var Key:= Format('%d:%d', [FileId, RoutineId]);
        if not IndexOf.TryGetValue(Key, At) then
        begin
          At:= Length(Result);
          IndexOf.Add(Key, At);
          SetLength(Result, At + 1);
          Result[At].RoutineId   := RoutineId;
          Result[At].RoutineQName:= Query.Fields[COL_ROUTINE_QNAME].AsString;
          Result[At].FileId      := FileId;
          Result[At].FilePath    := Query.Fields[COL_PATH].AsString;
          Ends:= Ends + [Query.Fields[COL_ROUTINE_END].AsInteger];
        end;
        Result[At].Sites:= Result[At].Sites + [Site];
      end;
      LastPosition:= Position;
      Query.Next;
    end;
  finally
    Query.Free;
    IndexOf.Free;
  end;
  for var I:= 0 to High(Result) do BuildRegions(Result[I], Ends[I]);
end;

function LockSitesOfProject(const pStore: ISymbolStore): TArray<TRoutineLockSites>;
begin
  Result:= LoadSites(pStore, '');
end;

function LockSitesOfFile(const pStore: ISymbolStore; pFileId: Int64): TArray<TRoutineLockSites>;
begin
  Result:= LoadSites(pStore, Format(SCOPE_FILE, [pFileId]));
end;

function LockSitesOfRoutine(const pStore: ISymbolStore; pRoutineId: Int64): TRoutineLockSites;
begin
  Result:= Default(TRoutineLockSites);
  var Found:= LoadSites(pStore, Format(SCOPE_ROUTINE, [pRoutineId]));
  if Found <> nil then Result:= Found[0];
  Result.RoutineId:= pRoutineId;
end;

function SiteJson(const pSite: TLockSite): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('line', pSite.Line);
  Result.AddPair('col', pSite.Col);
  Result.AddPair('op', LockSiteOpName(pSite.Op));
  Result.AddPair('kind', LockSiteKindName(pSite.Kind));
  Result.AddPair('shared', pSite.Shared);
  Result.AddPair('call', pSite.CallName);
  Result.AddPair('lock', pSite.LockText);
  Result.AddPair('type', pSite.TypeText);
  Result.AddPair('identity', LockIdentityName(pSite.Identity));
  Result.AddPair('exact', pSite.Exact);
  Result.AddPair('lockSymbol', pSite.LockQName);
  Result.AddPair('key', pSite.LockKey);
  Result.AddPair('mate', pSite.Mate);
end;

function RegionJson(const pRegion: TLockRegion): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('key', pRegion.LockKey);
  Result.AddPair('exact', pRegion.Exact);
  Result.AddPair('enter', pRegion.EnterSite);
  Result.AddPair('leave', pRegion.LeaveSite);
  Result.AddPair('open', pRegion.Open);
  Result.AddPair('startLine', pRegion.StartLine);
  Result.AddPair('startCol', pRegion.StartCol);
  Result.AddPair('endLine', pRegion.EndLine);
  Result.AddPair('endCol', pRegion.EndCol);
end;

function LockSitesJson(const pRoutines: TArray<TRoutineLockSites>): string;
begin
  var Doc:= TJSONObject.Create;
  try
    var Routines:= TJSONArray.Create;
    Doc.AddPair('routines', Routines);
    for var I:= 0 to High(pRoutines) do
    begin
      var Entry:= TJSONObject.Create;
      Routines.AddElement(Entry);
      Entry.AddPair('routine', pRoutines[I].RoutineQName);
      Entry.AddPair('routineId', pRoutines[I].RoutineId);
      Entry.AddPair('file', pRoutines[I].FilePath);
      var Sites:= TJSONArray.Create;
      Entry.AddPair('sites', Sites);
      for var K:= 0 to High(pRoutines[I].Sites) do Sites.AddElement(SiteJson(pRoutines[I].Sites[K]));
      var Regions:= TJSONArray.Create;
      Entry.AddPair('regions', Regions);
      for var K:= 0 to High(pRoutines[I].Regions) do Regions.AddElement(RegionJson(pRoutines[I].Regions[K]));
    end;
    Result:= Doc.ToJSON;
  finally
    Doc.Free;
  end;
end;

end.
