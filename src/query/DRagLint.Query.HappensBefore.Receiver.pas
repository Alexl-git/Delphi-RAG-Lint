unit DRagLint.Query.HappensBefore.Receiver;

{ drag-lint 1.52 -- lane HBRECV: receiver-aware order (ruling HB3).

  Spec docs\superpowers\specs\2026-11-17-happens-before-design.md sec. 1a (Q3 / HB3) and 5.6; acceptance
  tests\autotest\run_check_init_receiver.ps1 over tests\fixtures\happens-before\recv-*.

  The constructor model (DRagLint.Query.HappensBefore.Fields) answers MAY-BE-UNSET for the Init / Run
  pattern: no constructor writes F, a method W (Init) does. This unit re-judges such a use: it is SET when
  W ran ON THE SAME OBJECT before every call that reaches the use.

    * MustF(r): every normal completion of method r of F's class (or a descendant) has written F through
      Self -- the same least fixpoint as Fields (a counting Self write, or a certain Self call whose
      callee set, the callee unless abstract plus every override, is all MustF). A "writer call" on a
      receiver R is a certain call R.W whose callee set is all MustF.
    * The use's routine U: SET at once when U itself writes F before the use; else every call site of U
      (call edges plus dispatch fan-in, at least one, U not an unordered root of Roots) must be proven:
        - Self (no receiver, or `Self`): the caller P (a method of the family) runs a Self writer call or
          a Self write first, or every call site of P is proven in turn (depth HB_RECV_MAX_DEPTH, no
          cycles, never through a constructor or destructor);
        - a local variable or a value / const parameter R of P: a writer call R.W on every path before
          the site (Intra must-analysis); every write of R lies textually before the first writer call
          (structured code: a later write could undo it); every other reference of R is a receiver
          (anything else -- an argument, `@R`, a comparison, a nested routine -- counts as an escape);
          no reference of R inside an anonymous method; no unresolved reference named R in P;
        - a field G of Self (P a method of G's class O): every constructor declared in O (at least one,
          none `overload`, no descendant declaring its own) ends with a writer call on G after its last
          write of G and hands no bare Self out; every write of G sits in such a constructor, every
          other reference of G is a receiver through Self; and P is not reachable (callers, all
          confidences, plus dispatch fan-in) from any constructor, destructor or unordered root.
      Anything else -- a unit / program variable, a function result, an interface, a chained receiver,
      `with`, an uncertain call -- is not proven in 1.52.
  Proven uses become SET ("SET by receiver: ..."); every other eligible use keeps MAY-BE-UNSET and gains
  receiver-unproven, its why naming the first site that broke the proof. Only uses whose reasons are all
  constructor-model reasons (ctor-misses-field, no-declared-ctor, subclass-ctor-skips; soft-writer,
  nil-write-only and guarded-test are carried along) are eligible: every other reason stands.

  Read-only; nothing is persisted (no extractor change). Every doubt answers MAY-BE-UNSET. }

interface

uses
  DRagLint.Core.Interfaces
, DRagLint.Charts.Index
, DRagLint.Query.HappensBefore.Types
  ;

const
  /// <summary>Most call levels the Self-receiver proof climbs (Run called by Go called by Start ...).</summary>
  HB_RECV_MAX_DEPTH = 4;

  /// <summary>Prefix of the why text of a use proven SET by the receiver proof.</summary>
  HB_RECV_WHY_SET = 'SET by receiver: ';

  /// <summary>Marker inside the why text of an unproven use, followed by `<file>:<line>: <reason>`.</summary>
  HB_RECV_WHY_UNPROVEN = 'receiver-unproven: ';

/// <summary>Re-judges the Init / Run uses of an instance-field answer by the receiver (spec 5.6).</summary>
/// <param name="pIndex">Open index of the project the answer came from; caller owns it.</param>
/// <param name="pStore">Read-only store over the same DB (the CFG solver parses through it).</param>
/// <param name="pAnswer">CheckInstanceField's answer (Scope = instance); any other answer (program scope,
/// NEVER-SET, no target) is left untouched. Updated in place: eligible MAY uses become SET or gain
/// receiver-unproven; the headline, Proven, Summary and Budget follow.</param>
/// <param name="pMaxRoutines">Most routines solved (CFGs built) by the proof; &lt;= 0 means
/// HB_DEFAULT_MAX_ROUTINES. Running out answers receiver-unproven (budget), never SET.</param>
/// <returns>The number of uses turned SET.</returns>
/// <remarks>Read-only. Not thread-safe (the shared parse cache). Deterministic. Idempotent: a second call
/// changes nothing (proven uses are SET, unproven ones carry receiver-unproven and are no longer
/// eligible). SET is a proof under spec 6.1; use-after-free (`F := nil`, Free) stays out of scope as in
/// the constructor model.</remarks>
function ApplyReceiverProof(const pIndex: TChartsIndex; const pStore: ISymbolStore; var pAnswer: THbAnswer;
  pMaxRoutines: Integer): Integer;

implementation

uses
  System.SysUtils
, System.Generics.Collections
, System.Generics.Defaults
, DRagLint.Query.HappensBefore.Intra
, DRagLint.Query.HappensBefore.Roots
  ;

type
  TRows = TObjectList<TIndexRow>;

  /// <summary>The symbol row the proof needs (routine, variable, parameter, field or class).</summary>
  TRecvSym = record
    Id: Int64;
    ParentId: Int64;
    Kind: string;
    Name: string;
    QName: string;
    Signature: string;
    Directives: string;
    FilePath: string;
    Line: Integer;
    IsClassMethod: Boolean;
  end;

  /// <summary>One call site with its (single) receiver ref, if any.</summary>
  TRecvCall = record
    CallerId: Int64;
    CalleeId: Int64;
    FilePath: string;
    Line: Integer;
    Col: Integer;
    Certain: Boolean;
    /// <summary>`inherited X`: a static call of exactly the callee (no dispatch to overrides).</summary>
    IsInherited: Boolean;
    NRcv: Integer;
    RcvRefId: Int64;
    RcvSymId: Int64;
    RcvName: string;
  end;

  /// <summary>One reference of a receiver symbol: is it itself a receiver, and through what.</summary>
  TRecvRef = record
    EnclosingId: Int64;
    Kind: string;
    FilePath: string;
    Line: Integer;
    Col: Integer;
    IsReceiver: Boolean;
    NRcv: Integer;
    RcvName: string;
  end;

  /// <summary>The outcome of one proof step: Ok, or the site (file:line) and why it broke.</summary>
  TRecvResult = record
    Ok: Boolean;
    Site: string;
    Why: string;
  end;

  /// <summary>One ApplyReceiverProof call: index caches, MustF and the per-field invariants.</summary>
  TRecvSolver = class  // dl:ok god-class@c0c4, high-response@c0c4 -- REVIEWED 2026-11-18 v152 HBRECV: one proof = one object holding the call caches, MustF and the field invariants; its methods are the steps of spec 5.6, covered by 22 receiver cases
  strict private
    FIndex: TChartsIndex;
    FStore: ISymbolStore;
    FMax: Integer;
    FExhausted: Boolean;
    FFieldId: Int64;
    FFieldName: string;
    FFamilyMethods: TList<Int64>;
    FFamilyMethodSet: THashSet<Int64>;
    FSyms: TDictionary<Int64, TRecvSym>;
    FSelfWrites: TDictionary<Int64, TArray<THbSite>>;
    FMustF: THashSet<Int64>;
    FCalls: TDictionary<Int64, TArray<TRecvCall>>;
    FCallers: TDictionary<Int64, TArray<TRecvCall>>;
    FOverrides: TDictionary<Int64, TArray<Int64>>;
    FBases: TDictionary<Int64, TArray<Int64>>;
    FFieldProofs: TDictionary<Int64, TRecvResult>;
    FSolved: THashSet<Int64>;
    FVisiting: THashSet<Int64>;
    FEscape: THbEscapeClassifier;
    function Rows(const pSql: string): TRows;
    function IdClosure(pStart: Int64; const pSqlFmt: string): TArray<Int64>;
    function Sym(pId: Int64): TRecvSym;
    function ReadCalls(const pWhere: string): TArray<TRecvCall>;
    function CallsIn(pId: Int64): TArray<TRecvCall>;
    function CallersOf(pId: Int64): TArray<TRecvCall>;
    function OverridesOf(pId: Int64): TArray<Int64>;
    function BasesOf(pId: Int64): TArray<Int64>;
    function RefsOf(pSymId: Int64): TArray<TRecvRef>;
    function UnresolvedNamed(const pName: string; pEnclosingId: Int64; pWritesOnly: Boolean): Boolean;
    function BareSelfIn(pId: Int64; out pSite: THbSite): Boolean;
    function Solve(pId: Int64; const pMarks, pQueries: TArray<THbSite>; pEntryDone: Boolean): THbRoutineState;
    function CalleeSetMust(pCalleeId: Int64; pStatic: Boolean): Boolean;
    function SelfMarks(pId: Int64): TArray<THbSite>;
    procedure LoadFamily;
    procedure LoadSelfWrites(const pAnswer: THbAnswer);
    procedure ComputeMustF;
    function Fail(const pPath: string; pLine: Integer; const pWhy: string): TRecvResult;
    function FailAt(const pSym: TRecvSym; const pWhy: string): TRecvResult;
    function FailNotSolved: TRecvResult;
    function ProveCallers(const pRoutine: TRecvSym; pDepth: Integer): TRecvResult;
    function ProveSite(const pCall: TRecvCall; pDepth: Integer): TRecvResult;
    function ProveSelf(const pCall: TRecvCall; pDepth: Integer): TRecvResult;
    function ProveLocal(const pCall: TRecvCall; const pVar: TRecvSym): TRecvResult;
    function ProveField(const pCall: TRecvCall; const pField: TRecvSym): TRecvResult;
    function FieldInvariant(const pField: TRecvSym): TRecvResult;
    function CtorInitsField(pCtorId: Int64; const pField: TRecvSym; const pRefs: TArray<TRecvRef>): TRecvResult;
    function OnlyAfterConstruction(const pRoutine: TRecvSym): TRecvResult;
  public
    constructor Create(const pIndex: TChartsIndex; const pStore: ISymbolStore; pMax: Integer);
    destructor Destroy; override;
    /// <summary>Loads the family, the Self writes and MustF for the answer's field.</summary>
    procedure Prepare(const pAnswer: THbAnswer);
    /// <summary>Proves one judged use by the receiver; Ok = SET.</summary>
    function ProveUse(const pUse: THbUseAnswer): TRecvResult;
    /// <summary>True once the --max-routines budget ran out.</summary>
    property Exhausted: Boolean read FExhausted;
    /// <summary>The routines solved (CFGs built) so far.</summary>
    function SolvedCount: Integer;
  end;

const
  KIND_CTOR = 'constructor';
  KIND_DTOR = 'destructor';
  KIND_LOCAL = 'local_var';
  KIND_PARAM = 'param';
  KIND_FIELD = 'field';
  RECEIVER_SELF = 'self';
  RECEIVER_INHERITED = 'inherited';
  REF_WRITE = 'write';
  { what a backward caller walk may visit, as a multiple of --max-routines }
  WALK_FACTOR = 4;
  SUMMARY_SET = '(receiver-proven: every judged use runs after a writer method on the same object -- spec 5.6)';

function Id64(const pRow: TIndexRow; const pCol: string): Int64;
begin
  Result:= StrToInt64Def(pRow.S(pCol), 0);
end;

function IdList(const pIds: TArray<Int64>): string;
begin
  Result:= '';
  for var I in pIds do Result:= Result + (if Result = '' then '' else ',') + IntToStr(I);
  if Result = '' then Result:= '0';
end;

function SiteOf(const pPath: string; pLine, pCol: Integer): THbSite;
begin
  Result:= Default(THbSite);
  Result.FileName:= pPath;
  Result.Line:= pLine;
  Result.Col:= pCol;
end;

function Before(pLine1, pCol1, pLine2, pCol2: Integer): Boolean;
begin
  Result:= (pLine1 < pLine2) or ((pLine1 = pLine2) and (pCol1 < pCol2));
end;

procedure AddReason(var pList: TArray<THbReason>; pReason: THbReason);
begin
  for var R in pList do
    if R = pReason then Exit;
  pList:= pList + [pReason];
end;

function SortedReasons(const pList: TArray<THbReason>): TArray<THbReason>;
begin
  Result:= Copy(pList);
  TArray.Sort<THbReason>(Result, TComparer<THbReason>.Construct(
    function(const pL, pR: THbReason): Integer
    begin
      Result:= Ord(pL) - Ord(pR);
    end));
end;

function LastPart(const pQName: string): string;
begin
  Result:= Copy(pQName, LastDelimiter('.', pQName) + 1, MaxInt);
end;

function IsCtorOrDtor(const pSym: TRecvSym): Boolean;
begin
  Result:= (pSym.Kind = KIND_CTOR) or (pSym.Kind = KIND_DTOR);
end;

function IsSelfCall(const pCall: TRecvCall): Boolean;
begin
  Result:= (pCall.NRcv = 0) or ((pCall.NRcv = 1) and (pCall.RcvName = RECEIVER_SELF));
end;

function Ok(const pWhy: string): TRecvResult;
begin
  Result:= Default(TRecvResult);
  Result.Ok:= True;
  Result.Why:= pWhy;
end;

{ The passing mode of parameter pName in a routine signature `(a: T; var b, c: U): R`: 'value', 'const',
  'var', 'out', 'constref' or 'untyped'; '' when the name is not found. }
function ParamMode(const pSignature, pName: string): string;
const
  PARAM_MODES: array[0..3] of string = ('var ', 'out ', 'constref ', 'const ');
begin
  Result:= '';
  var Open:= Pos('(', pSignature);
  if Open = 0 then Exit;
  var Depth:= 0;
  var Close:= 0;
  for var I:= Open to Length(pSignature) do
  begin
    if (pSignature[I] = '(') or (pSignature[I] = '[') then Inc(Depth)
    else if (pSignature[I] = ')') or (pSignature[I] = ']') then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Close:= I;
        Break;
      end;
    end;
  end;
  if Close = 0 then Exit;
  var Inner:= Copy(pSignature, Open + 1, Close - Open - 1);
  for var Group in Inner.Split([';']) do
  begin
    var G:= Group.Trim.ToLower;
    var Mode:= 'value';
    if G.StartsWith('[ref]') then
    begin
      Mode:= 'constref';
      G:= G.Substring(Length('[ref]')).Trim;
    end;
    for var M in PARAM_MODES do
      if G.StartsWith(M) then
      begin
        if Mode = 'value' then Mode:= M.Trim;
        G:= G.Substring(Length(M)).Trim;
        Break;
      end;
    var Colon:= G.IndexOf(':');
    var Names:= if Colon < 0 then G else G.Substring(0, Colon);
    if Colon < 0 then Mode:= 'untyped';
    for var N in Names.Split([',']) do
      if SameText(N.Trim, pName) then Exit(Mode);
  end;
end;

{ TRecvSolver }

constructor TRecvSolver.Create(const pIndex: TChartsIndex; const pStore: ISymbolStore; pMax: Integer);
begin
  inherited Create;
  FIndex:= pIndex;
  FStore:= pStore;
  FMax:= pMax;
  FFamilyMethods:= TList<Int64>.Create;
  FFamilyMethodSet:= THashSet<Int64>.Create;
  FSyms:= TDictionary<Int64, TRecvSym>.Create;
  FSelfWrites:= TDictionary<Int64, TArray<THbSite>>.Create;
  FMustF:= THashSet<Int64>.Create;
  FCalls:= TDictionary<Int64, TArray<TRecvCall>>.Create;
  FCallers:= TDictionary<Int64, TArray<TRecvCall>>.Create;
  FOverrides:= TDictionary<Int64, TArray<Int64>>.Create;
  FBases:= TDictionary<Int64, TArray<Int64>>.Create;
  FFieldProofs:= TDictionary<Int64, TRecvResult>.Create;
  FSolved:= THashSet<Int64>.Create;
  FVisiting:= THashSet<Int64>.Create;
  FEscape:= THbEscapeClassifier.Create(pStore);
end;

destructor TRecvSolver.Destroy;
begin
  FEscape.Free;
  FVisiting.Free;
  FSolved.Free;
  FFieldProofs.Free;
  FBases.Free;
  FOverrides.Free;
  FCallers.Free;
  FCalls.Free;
  FMustF.Free;
  FSelfWrites.Free;
  FSyms.Free;
  FFamilyMethodSet.Free;
  FFamilyMethods.Free;
  inherited;
end;

function TRecvSolver.SolvedCount: Integer;
begin
  Result:= FSolved.Count;
end;

function TRecvSolver.Rows(const pSql: string): TRows;
begin
  Result:= FIndex.Query(pSql);
end;

{ The transitive closure of one id relation from pStart, sorted, pStart left out. pSqlFmt selects the next
  ids as column x and takes the current id as its one %d (ids only: no text reaches the SQL). }
function TRecvSolver.IdClosure(pStart: Int64; const pSqlFmt: string): TArray<Int64>;
begin
  Result:= nil;
  var Seen:= THashSet<Int64>.Create;
  try
    var Work:= [pStart];
    while Work <> nil do
    begin
      var Cur:= Work[High(Work)];
      SetLength(Work, Length(Work) - 1);
      var R:= Rows(Format(pSqlFmt, [Cur]));
      try
        for var Row in R do
        begin
          var X:= Id64(Row, 'x');
          if (X <> 0) and (X <> pStart) and Seen.Add(X) then
          begin
            Result:= Result + [X];
            Work:= Work + [X];
          end;
        end;
      finally
        R.Free;
      end;
    end;
  finally
    Seen.Free;
  end;
  TArray.Sort<Int64>(Result);
end;

function TRecvSolver.Sym(pId: Int64): TRecvSym;
begin
  if FSyms.TryGetValue(pId, Result) then Exit;
  Result:= Default(TRecvSym);
  var R:= Rows('SELECT s.id, COALESCE(s.parent_id, 0) AS pid, s.kind, s.name, s.qualified_name AS q, ' +
    'COALESCE(s.signature, '''') AS sig, LOWER(COALESCE(s.directives, '''')) AS dir, f.path, ' +
    'COALESCE(NULLIF(s.impl_start_line, 0), s.start_line) AS ln, COALESCE(s.is_class_method, 0) AS cm ' +
    'FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.id = ' + IntToStr(pId));
  try
    if R.Count > 0 then
    begin
      Result.Id:= Id64(R[0], 'id');
      Result.ParentId:= Id64(R[0], 'pid');
      Result.Kind:= R[0].S('kind');
      Result.Name:= R[0].S('name');
      Result.QName:= R[0].S('q');
      Result.Signature:= R[0].S('sig');
      Result.Directives:= R[0].S('dir');
      Result.FilePath:= R[0].S('path');
      Result.Line:= R[0].I('ln');
      Result.IsClassMethod:= R[0].I('cm') <> 0;
    end;
  finally
    R.Free;
  end;
  FSyms.Add(pId, Result);
end;

function TRecvSolver.ReadCalls(const pWhere: string): TArray<TRecvCall>;
begin
  Result:= nil;
  var R:= Rows('SELECT COALESCE(r.enclosing_symbol_id, (SELECT p.id FROM symbols p WHERE p.file_id = r.file_id ' +
    'AND p.kind IN (''program'', ''library'') ORDER BY p.id LIMIT 1), 0) AS caller, c.target_symbol_id AS callee, ' +
    'f.path, r.start_line AS ln, r.start_col AS col, c.confidence AS conf, ' +
    'LOWER(COALESCE(r.receiver_text, '''')) AS rtx, ' +
    '(SELECT COUNT(*) FROM ref_receivers rr WHERE rr.ref_id = r.id) AS nrcv, ' +
    'COALESCE((SELECT rv.id FROM ref_receivers rr JOIN refs rv ON rv.id = rr.receiver_ref_id ' +
    'WHERE rr.ref_id = r.id ORDER BY rv.id LIMIT 1), 0) AS rvid, ' +
    'COALESCE((SELECT rv.symbol_id FROM ref_receivers rr JOIN refs rv ON rv.id = rr.receiver_ref_id ' +
    'WHERE rr.ref_id = r.id ORDER BY rv.id LIMIT 1), 0) AS rvs, ' +
    'COALESCE((SELECT LOWER(rv.name_text) FROM ref_receivers rr JOIN refs rv ON rv.id = rr.receiver_ref_id ' +
    'WHERE rr.ref_id = r.id ORDER BY rv.id LIMIT 1), '''') AS rvn ' +
    'FROM refs r JOIN call_edges c ON c.ref_id = r.id JOIN files f ON f.id = r.file_id WHERE ' + pWhere +
    ' ORDER BY f.path, r.start_line, r.start_col, r.id');
  try
    for var Row in R do
    begin
      var C:= Default(TRecvCall);
      C.CallerId:= Id64(Row, 'caller');
      C.CalleeId:= Id64(Row, 'callee');
      C.FilePath:= Row.S('path');
      C.Line:= Row.I('ln');
      C.Col:= Row.I('col');
      C.Certain:= Row.S('conf') = 'certain';
      C.IsInherited:= Row.S('rtx') = RECEIVER_INHERITED;
      C.NRcv:= Row.I('nrcv');
      C.RcvRefId:= Id64(Row, 'rvid');
      C.RcvSymId:= Id64(Row, 'rvs');
      C.RcvName:= Row.S('rvn');
      Result:= Result + [C];
    end;
  finally
    R.Free;
  end;
end;

function TRecvSolver.CallsIn(pId: Int64): TArray<TRecvCall>;
begin
  if FCalls.TryGetValue(pId, Result) then Exit;
  Result:= ReadCalls(Format('r.enclosing_symbol_id = %d', [pId]));
  FCalls.Add(pId, Result);
end;

function TRecvSolver.BasesOf(pId: Int64): TArray<Int64>;
begin
  if FBases.TryGetValue(pId, Result) then Exit;
  Result:= IdClosure(pId, 'SELECT base_symbol_id AS x FROM dispatch_edges WHERE impl_symbol_id = %d ' +
    'ORDER BY base_symbol_id');
  FBases.Add(pId, Result);
end;

function TRecvSolver.OverridesOf(pId: Int64): TArray<Int64>;
begin
  if FOverrides.TryGetValue(pId, Result) then Exit;
  Result:= IdClosure(pId, 'SELECT impl_symbol_id AS x FROM dispatch_edges WHERE kind = ''override'' ' +
    'AND base_symbol_id = %d ORDER BY impl_symbol_id');
  FOverrides.Add(pId, Result);
end;

{ Every call that can reach pId: call edges to it and to every base it overrides (dispatch fan-in). }
function TRecvSolver.CallersOf(pId: Int64): TArray<TRecvCall>;
begin
  if FCallers.TryGetValue(pId, Result) then Exit;
  Result:= ReadCalls('c.target_symbol_id IN (' + IdList([pId] + BasesOf(pId)) + ')');
  FCallers.Add(pId, Result);
end;

function TRecvSolver.RefsOf(pSymId: Int64): TArray<TRecvRef>;
begin
  Result:= nil;
  var R:= Rows('SELECT COALESCE(r.enclosing_symbol_id, 0) AS enc, r.kind, f.path, r.start_line AS ln, ' +
    'r.start_col AS col, (SELECT COUNT(*) FROM ref_receivers x WHERE x.receiver_ref_id = r.id) AS isrcv, ' +
    '(SELECT COUNT(*) FROM ref_receivers rr WHERE rr.ref_id = r.id) AS nrcv, ' +
    'COALESCE((SELECT LOWER(rv.name_text) FROM ref_receivers rr JOIN refs rv ON rv.id = rr.receiver_ref_id ' +
    'WHERE rr.ref_id = r.id ORDER BY rv.id LIMIT 1), '''') AS rvn ' +
    'FROM refs r JOIN files f ON f.id = r.file_id WHERE r.symbol_id = ' + IntToStr(pSymId) +
    ' ORDER BY f.path, r.start_line, r.start_col, r.id');
  try
    for var Row in R do
    begin
      var X:= Default(TRecvRef);
      X.EnclosingId:= Id64(Row, 'enc');
      X.Kind:= Row.S('kind');
      X.FilePath:= Row.S('path');
      X.Line:= Row.I('ln');
      X.Col:= Row.I('col');
      X.IsReceiver:= Row.I('isrcv') > 0;
      X.NRcv:= Row.I('nrcv');
      X.RcvName:= Row.S('rvn');
      Result:= Result + [X];
    end;
  finally
    R.Free;
  end;
end;

{ An unresolved ref spelled like the receiver (a `with` block, an unknown overload) could be it. }
function TRecvSolver.UnresolvedNamed(const pName: string; pEnclosingId: Int64; pWritesOnly: Boolean): Boolean;
begin
  var Sql:= 'SELECT COUNT(*) AS n FROM refs r WHERE r.symbol_id IS NULL AND LOWER(r.name_text) = ''' +
    TChartsIndex.SqlText(pName.ToLower) + '''';
  if pEnclosingId <> 0 then Sql:= Sql + ' AND r.enclosing_symbol_id = ' + IntToStr(pEnclosingId);
  if pWritesOnly then Sql:= Sql + ' AND r.kind = ''' + REF_WRITE + '''';
  var R:= Rows(Sql);
  try
    Result:= (R.Count > 0) and (R[0].I('n') > 0);
  finally
    R.Free;
  end;
end;

{ A bare `Self` in pId: a Self ref that is not the receiver of another ref (handed out, compared, stored). }
function TRecvSolver.BareSelfIn(pId: Int64; out pSite: THbSite): Boolean;
begin
  pSite:= Default(THbSite);
  var R:= Rows('SELECT f.path, r.start_line AS ln, r.start_col AS col FROM refs r JOIN files f ON f.id = r.file_id ' +
    'WHERE r.enclosing_symbol_id = ' + IntToStr(pId) + ' AND LOWER(r.name_text) = ''' + RECEIVER_SELF + ''' ' +
    'AND NOT EXISTS (SELECT 1 FROM ref_receivers x WHERE x.receiver_ref_id = r.id) ' +
    'ORDER BY r.start_line, r.start_col, r.id LIMIT 1');
  try
    Result:= R.Count > 0;
    if Result then pSite:= SiteOf(R[0].S('path'), R[0].I('ln'), R[0].I('col'));
  finally
    R.Free;
  end;
end;

{ SolveRoutine under the --max-routines budget: a routine beyond it answers Found = False. }
function TRecvSolver.Solve(pId: Int64; const pMarks, pQueries: TArray<THbSite>; pEntryDone: Boolean):
  THbRoutineState;
begin
  Result:= Default(THbRoutineState);
  Result.RoutineId:= pId;
  if HbTimeUp then
  begin
    FExhausted:= True;
    Exit;
  end;
  if not FSolved.Contains(pId) then
  begin
    if FSolved.Count >= FMax then
    begin
      FExhausted:= True;
      Exit;
    end;
    FSolved.Add(pId);
  end;
  Result:= SolveRoutine(FStore, pId, pMarks, pQueries, pEntryDone);
end;

{ The callee set of a call: the callee unless abstract, plus every override unless the call is static
  (`inherited`); True when it is non-empty and all MustF. }
function TRecvSolver.CalleeSetMust(pCalleeId: Int64; pStatic: Boolean): Boolean;
begin
  var Callees: TArray<Int64>:= nil;
  if not Sym(pCalleeId).Directives.Contains('abstract') then Callees:= [pCalleeId];
  if not pStatic then Callees:= Callees + OverridesOf(pCalleeId);
  Result:= Callees <> nil;
  for var X in Callees do
    if not FMustF.Contains(X) then Exit(False);
end;

function TRecvSolver.SelfMarks(pId: Int64): TArray<THbSite>;
begin
  if not FSelfWrites.TryGetValue(pId, Result) then Result:= nil;
  for var C in CallsIn(pId) do
    if C.Certain and IsSelfCall(C) and CalleeSetMust(C.CalleeId, C.IsInherited) then
      Result:= Result + [SiteOf(C.FilePath, C.Line, C.Col)];
end;

procedure TRecvSolver.LoadFamily;
begin
  var ClassId:= Sym(FFieldId).ParentId;
  if ClassId = 0 then Exit;
  var Family:= [ClassId] + IdClosure(ClassId, 'SELECT symbol_id AS x FROM type_ancestors WHERE ' +
    'ancestor_symbol_id = %d AND ancestor_kind = ''class'' ORDER BY symbol_id');
  var R:= Rows('SELECT s.id FROM symbols s WHERE s.parent_id IN (' + IdList(Family) + ') AND s.kind IN (' +
    '''constructor'', ''destructor'', ''method'', ''procedure'', ''function'') ' +
    'AND COALESCE(s.is_class_method, 0) = 0 ORDER BY s.id');
  try
    for var Row in R do
    begin
      FFamilyMethods.Add(Id64(Row, 'id'));
      FFamilyMethodSet.Add(Id64(Row, 'id'));
    end;
  finally
    R.Free;
  end;
end;

{ Counting writes of F through Self per family method (writes through another object are left out). }
procedure TRecvSolver.LoadSelfWrites(const pAnswer: THbAnswer);
begin
  var Foreign:= TList<THbSite>.Create;
  try
    var R:= Rows('SELECT f.path, r.start_line AS ln, r.start_col AS col FROM refs r JOIN files f ON f.id = r.file_id ' +
      'JOIN ref_receivers rr ON rr.ref_id = r.id JOIN refs rv ON rv.id = rr.receiver_ref_id ' +
      'WHERE r.symbol_id = ' + IntToStr(FFieldId) + ' AND LOWER(rv.name_text) <> ''' + RECEIVER_SELF + '''');
    try
      for var Row in R do Foreign.Add(SiteOf(Row.S('path'), Row.I('ln'), Row.I('col')));
    finally
      R.Free;
    end;
    for var W in pAnswer.Writers do
    begin
      if not (W.Counts and W.Resolved and (W.How in [hwAssign, hwCreateInto, hwVarArg, hwOutArg])) then Continue;
      if not FFamilyMethodSet.Contains(W.Site.RoutineId) then Continue;
      var IsForeign:= False;
      for var F in Foreign do
        if (F.Line = W.Site.Line) and (F.Col = W.Site.Col) and SameText(F.FileName, W.Site.FileName) then
          IsForeign:= True;
      if IsForeign then Continue;
      var L: TArray<THbSite>;
      if not FSelfWrites.TryGetValue(W.Site.RoutineId, L) then L:= nil;
      FSelfWrites.AddOrSetValue(W.Site.RoutineId, L + [SiteOf(W.Site.FileName, W.Site.Line, W.Site.Col)]);
    end;
  finally
    Foreign.Free;
  end;
end;

procedure TRecvSolver.ComputeMustF;
begin
  { least fixpoint over the instance methods of F's class and its descendants, in id order }
  var Changed:= True;
  while Changed and not FExhausted do
  begin
    Changed:= False;
    for var Id in FFamilyMethods do
    begin
      if FMustF.Contains(Id) then Continue;
      var St:= Solve(Id, SelfMarks(Id), nil, False);
      if St.Found and St.ExitDone then
      begin
        FMustF.Add(Id);
        Changed:= True;
      end;
    end;
  end;
end;

procedure TRecvSolver.Prepare(const pAnswer: THbAnswer);
begin
  FFieldId:= pAnswer.Target.SymbolId;
  FFieldName:= LastPart(pAnswer.Target.QName);
  LoadFamily;
  LoadSelfWrites(pAnswer);
  ComputeMustF;
end;

function TRecvSolver.Fail(const pPath: string; pLine: Integer; const pWhy: string): TRecvResult;
begin
  Result:= Default(TRecvResult);
  Result.Site:= Format('%s:%d', [ExtractFileName(pPath), pLine]);
  Result.Why:= pWhy;
end;

function TRecvSolver.FailAt(const pSym: TRecvSym; const pWhy: string): TRecvResult;
begin
  Result:= Fail(pSym.FilePath, pSym.Line, pWhy);
end;

function TRecvSolver.FailNotSolved: TRecvResult;
begin
  Result:= Default(TRecvResult);
  Result.Site:= '-';
  Result.Why:= if FExhausted then HbBudgetWhy else 'the routine could not be parsed';
end;

function TRecvSolver.ProveUse(const pUse: THbUseAnswer): TRecvResult;
begin
  var U:= Sym(pUse.Site.RoutineId);
  if not FFamilyMethodSet.Contains(U.Id) or IsCtorOrDtor(U) then
    Exit(Fail(pUse.Site.FileName, pUse.Site.Line, 'the use is not in an ordinary method of the class'));
  var UseSite:= SiteOf(pUse.Site.FileName, pUse.Site.Line, pUse.Site.Col);
  var St:= Solve(U.Id, SelfMarks(U.Id), [UseSite], False);
  if not St.Found or (Length(St.Queries) <> 1) then Exit(FailNotSolved);
  if St.Queries[0].InClosure then
    Exit(Fail(pUse.Site.FileName, pUse.Site.Line, 'the use is inside an anonymous method'));
  if St.Queries[0].Located and St.Queries[0].Done then
    Exit(Ok(U.QName + ' sets ' + FFieldName + ' on Self before the use'));
  Result:= ProveCallers(U, 0);
end;

function TRecvSolver.ProveCallers(const pRoutine: TRecvSym; pDepth: Integer): TRecvResult;
begin
  if pDepth > HB_RECV_MAX_DEPTH then
    Exit(FailAt(pRoutine, Format('the call chain to %s is deeper than %d levels', [pRoutine.QName,
      HB_RECV_MAX_DEPTH])));
  var Esc:= FEscape.ClassOf(pRoutine.Id);
  if Esc <> hecNone then
    Exit(FailAt(pRoutine, pRoutine.QName + ' is an unordered root (' + EscapeClassCode(Esc) + ')'));
  if not FVisiting.Add(pRoutine.Id) then
    Exit(FailAt(pRoutine, pRoutine.QName + ' is reached recursively'));
  try
    var Calls:= CallersOf(pRoutine.Id);
    if Calls = nil then Exit(FailAt(pRoutine, pRoutine.QName + ' has no call site'));
    Result:= Default(TRecvResult);
    for var C in Calls do
    begin
      var R:= ProveSite(C, pDepth);
      if not R.Ok then Exit(R);
      if Result.Why = '' then Result:= R;
    end;
    if Length(Calls) > 1 then
      Result.Why:= Result.Why + Format(' (and %d more call sites)', [Length(Calls) - 1]);
  finally
    FVisiting.Remove(pRoutine.Id);
  end;
end;

function TRecvSolver.ProveSite(const pCall: TRecvCall; pDepth: Integer): TRecvResult;  // dl:ok too-many-exit-points@4ada -- REVIEWED 2026-11-18 v152 HBRECV: one guard clause per proof condition of the unit header (spec 5.6), the first failing one is the receiver-unproven site
begin
  if pCall.CallerId = 0 then Exit(Fail(pCall.FilePath, pCall.Line, 'the call is outside any routine'));
  if not pCall.Certain then
    Exit(Fail(pCall.FilePath, pCall.Line, 'the call is not certain (its target is a guess)'));
  if IsSelfCall(pCall) then Exit(ProveSelf(pCall, pDepth));
  if pCall.NRcv <> 1 then Exit(Fail(pCall.FilePath, pCall.Line, 'the receiver is a chain'));
  if pCall.RcvSymId = 0 then
    Exit(Fail(pCall.FilePath, pCall.Line, 'the receiver ' + pCall.RcvName + ' is not resolved'));
  var R:= Sym(pCall.RcvSymId);
  if ((R.Kind = KIND_LOCAL) or (R.Kind = KIND_PARAM)) and (R.ParentId = pCall.CallerId) then
    Exit(ProveLocal(pCall, R));
  if R.Kind = KIND_FIELD then Exit(ProveField(pCall, R));
  Result:= Fail(pCall.FilePath, pCall.Line, 'the receiver ' + R.Name + ' is a ' + R.Kind +
    ' (only a local, a value parameter, Self or a field of Self is tracked in 1.52)');
end;

function TRecvSolver.ProveSelf(const pCall: TRecvCall; pDepth: Integer): TRecvResult;  // dl:ok too-many-exit-points@e417 -- REVIEWED 2026-11-18 v152 HBRECV: one guard clause per proof condition of the unit header (spec 5.6), the first failing one is the receiver-unproven site
begin
  var P:= Sym(pCall.CallerId);
  if not FFamilyMethodSet.Contains(P.Id) then
    Exit(Fail(pCall.FilePath, pCall.Line, 'a Self call from ' + P.QName + ', outside the class'));
  var St:= Solve(P.Id, SelfMarks(P.Id), [SiteOf(pCall.FilePath, pCall.Line, pCall.Col)], False);
  if not St.Found or (Length(St.Queries) <> 1) then Exit(FailNotSolved);
  var Q:= St.Queries[0];
  if Q.InClosure then Exit(Fail(pCall.FilePath, pCall.Line, 'the call is inside an anonymous method'));
  if not Q.Located then Exit(Fail(pCall.FilePath, pCall.Line, 'the call site is not in the routine''s CFG'));
  if Q.Done then
    Exit(Ok(Format('%s sets %s on Self before the call at %s:%d', [P.QName, FFieldName,
      ExtractFileName(pCall.FilePath), pCall.Line])));
  if IsCtorOrDtor(P) then
    Exit(Fail(pCall.FilePath, pCall.Line, P.QName + ' calls on Self before it sets ' + FFieldName));
  Result:= ProveCallers(P, pDepth + 1);
end;

function TRecvSolver.ProveLocal(const pCall: TRecvCall; const pVar: TRecvSym): TRecvResult;  // dl:ok too-many-exit-points@56b1 -- REVIEWED 2026-11-18 v152 HBRECV: one guard clause per proof condition of the unit header (spec 5.6), the first failing one is the receiver-unproven site
begin
  var P:= Sym(pCall.CallerId);
  if pVar.Kind = KIND_PARAM then
  begin
    var Mode:= ParamMode(P.Signature, pVar.Name);
    if (Mode <> 'value') and (Mode <> 'const') then
      Exit(Fail(pCall.FilePath, pCall.Line, 'the receiver ' + pVar.Name + ' is a ' +
        (if Mode = '' then 'parameter of unknown mode' else Mode + ' parameter') +
        ' (it aliases the caller''s variable)'));
  end;
  if UnresolvedNamed(pVar.Name, P.Id, False) then
    Exit(Fail(pCall.FilePath, pCall.Line, 'an unresolved reference named ' + pVar.Name + ' in ' + P.QName));
  var Refs:= RefsOf(pVar.Id);
  for var X in Refs do
    if X.EnclosingId <> P.Id then
      Exit(Fail(X.FilePath, X.Line, pVar.Name + ' is used by a nested routine'));
  var Marks: TArray<THbSite>:= nil;
  var FirstLine:= MaxInt;
  var FirstCol:= MaxInt;
  var Writer:= '';
  for var K in CallsIn(P.Id) do
    if (K.NRcv = 1) and (K.RcvSymId = pVar.Id) and K.Certain and CalleeSetMust(K.CalleeId, False) then
    begin
      Marks:= Marks + [SiteOf(K.FilePath, K.Line, K.Col)];
      if Before(K.Line, K.Col, FirstLine, FirstCol) then
      begin
        FirstLine:= K.Line;
        FirstCol:= K.Col;
        Writer:= Sym(K.CalleeId).QName;
      end;
    end;
  if Marks = nil then
    Exit(Fail(pCall.FilePath, pCall.Line, 'no writer method of ' + FFieldName + ' runs on ' + pVar.Name +
      ' in ' + P.QName));
  var Queries:= [SiteOf(pCall.FilePath, pCall.Line, pCall.Col)];
  for var X in Refs do
  begin
    { every ref is a query: a write or a receiver inside an anonymous method runs at an unknown time }
    Queries:= Queries + [SiteOf(X.FilePath, X.Line, X.Col)];
    if X.IsReceiver then Continue;
    if X.Kind <> REF_WRITE then
      Exit(Fail(X.FilePath, X.Line, pVar.Name + ' escapes (passed on, compared or its address taken)'));
    if not Before(X.Line, X.Col, FirstLine, FirstCol) then
      Exit(Fail(X.FilePath, X.Line, pVar.Name + ' is re-assigned after the writer call'));
  end;
  var St:= Solve(P.Id, Marks, Queries, False);
  if not St.Found or (Length(St.Queries) <> Length(Queries)) then Exit(FailNotSolved);
  if St.CfgSkipped then Exit(FailAt(P, P.QName + ' has goto / asm (no CFG)'));
  for var Q in St.Queries do
    if Q.InClosure then
      Exit(Fail(Q.Site.FileName, Q.Site.Line, pVar.Name + ' is used inside an anonymous method'));
  if not (St.Queries[0].Located and St.Queries[0].Done) then
    Exit(Fail(pCall.FilePath, pCall.Line, 'the writer call on ' + pVar.Name +
      ' does not run on every path before this call'));
  Result:= Ok(Format('%s runs on %s before %s calls on it at %s:%d', [Writer, pVar.Name, P.QName,
    ExtractFileName(pCall.FilePath), pCall.Line]));
end;

function TRecvSolver.ProveField(const pCall: TRecvCall; const pField: TRecvSym): TRecvResult;  // dl:ok too-many-exit-points@51d2 -- REVIEWED 2026-11-18 v152 HBRECV: one guard clause per proof condition of the unit header (spec 5.6), the first failing one is the receiver-unproven site
begin
  { the receiver ref itself must be reached through Self }
  var R:= Rows('SELECT COUNT(*) AS n, COALESCE(MAX(LOWER(rv.name_text)), '''') AS nm FROM ref_receivers rr ' +
    'JOIN refs rv ON rv.id = rr.receiver_ref_id WHERE rr.ref_id = ' + IntToStr(pCall.RcvRefId));
  try
    if (R.Count > 0) and not ((R[0].I('n') = 0) or ((R[0].I('n') = 1) and (R[0].S('nm') = RECEIVER_SELF))) then
      Exit(Fail(pCall.FilePath, pCall.Line, pField.Name + ' is reached through another object'));
  finally
    R.Free;
  end;
  var P:= Sym(pCall.CallerId);
  if (P.ParentId <> pField.ParentId) or P.IsClassMethod or IsCtorOrDtor(P) then
    Exit(Fail(pCall.FilePath, pCall.Line, 'the call on ' + pField.Name + ' is not in an ordinary method of ' +
      Sym(pField.ParentId).QName));
  Result:= FieldInvariant(pField);
  if not Result.Ok then Exit;
  var St:= Solve(P.Id, nil, [SiteOf(pCall.FilePath, pCall.Line, pCall.Col)], True);
  if not St.Found or (Length(St.Queries) <> 1) then Exit(FailNotSolved);
  if St.Queries[0].InClosure then
    Exit(Fail(pCall.FilePath, pCall.Line, 'the call is inside an anonymous method'));
  if not St.Queries[0].Located then
    Exit(Fail(pCall.FilePath, pCall.Line, 'the call site is not in the routine''s CFG'));
  Result:= OnlyAfterConstruction(P);
  if not Result.Ok then Exit;
  Result:= Ok(Format('every constructor of %s runs a writer method of %s on %s, re-assigned nowhere else, ' +
    'before %s calls on it at %s:%d', [Sym(pField.ParentId).QName, FFieldName, pField.QName, P.QName,
    ExtractFileName(pCall.FilePath), pCall.Line]));
end;

{ Per field G of class O: after any constructor of O returns, G holds an object a writer method ran on. }
function TRecvSolver.FieldInvariant(const pField: TRecvSym): TRecvResult;
begin
  if FFieldProofs.TryGetValue(pField.Id, Result) then Exit;
  Result:= Ok('');
  var Owner:= Sym(pField.ParentId);
  var Ctors: TArray<Int64>:= nil;
  var R:= Rows('SELECT s.id FROM symbols s WHERE s.parent_id = ' + IntToStr(Owner.Id) + ' AND s.kind = ''' +
    KIND_CTOR + ''' AND COALESCE(s.is_class_method, 0) = 0 ORDER BY s.id');
  try
    for var Row in R do Ctors:= Ctors + [Id64(Row, 'id')];
  finally
    R.Free;
  end;
  if Ctors = nil then Result:= FailAt(Owner, Owner.QName + ' declares no constructor');
  for var K in Ctors do
    if Result.Ok and Sym(K).Directives.Contains('overload') then
      Result:= FailAt(Sym(K), Sym(K).QName + ' is declared overload: an inherited constructor stays callable');
  if Result.Ok then
    for var D in IdClosure(Owner.Id, 'SELECT symbol_id AS x FROM type_ancestors WHERE ancestor_symbol_id = %d ' +
      'AND ancestor_kind = ''class'' ORDER BY symbol_id') do
    begin
      var DR:= Rows('SELECT COUNT(*) AS n FROM symbols s WHERE s.parent_id = ' + IntToStr(D) + ' AND s.kind = ''' +
        KIND_CTOR + '''');
      try
        if (DR.Count > 0) and (DR[0].I('n') > 0) then
        begin
          Result:= FailAt(Sym(D), 'the descendant ' + Sym(D).QName + ' declares its own constructor');
          Break;
        end;
      finally
        DR.Free;
      end;
    end;
  var Refs:= RefsOf(pField.Id);
  if Result.Ok then
    for var X in Refs do
    begin
      if not ((X.NRcv = 0) or ((X.NRcv = 1) and (X.RcvName = RECEIVER_SELF))) then
        Result:= Fail(X.FilePath, X.Line, pField.Name + ' is reached through another object')
      else if X.Kind = REF_WRITE then
      begin
        if not TArray.Contains<Int64>(Ctors, X.EnclosingId) then
          Result:= Fail(X.FilePath, X.Line, pField.Name + ' is re-assigned outside a constructor of ' + Owner.QName);
      end
      else if not X.IsReceiver then
        Result:= Fail(X.FilePath, X.Line, pField.Name + ' escapes (passed on, compared or its address taken)');
      if not Result.Ok then Break;
    end;
  if Result.Ok and UnresolvedNamed(pField.Name, 0, True) then
    Result:= FailAt(Owner, 'an unresolved write named ' + pField.Name + ' exists');
  if Result.Ok then
    for var K in Ctors do
    begin
      Result:= CtorInitsField(K, pField, Refs);
      if not Result.Ok then Break;
    end;
  FFieldProofs.Add(pField.Id, Result);
end;

function TRecvSolver.CtorInitsField(pCtorId: Int64; const pField: TRecvSym; const pRefs: TArray<TRecvRef>):  // dl:ok too-many-exit-points@68cc -- REVIEWED 2026-11-18 v152 HBRECV: one guard clause per proof condition of the unit header (spec 5.6), the first failing one is the receiver-unproven site
  TRecvResult;
var
  SelfSite: THbSite;
begin
  var K:= Sym(pCtorId);
  if BareSelfIn(pCtorId, SelfSite) then
    Exit(Fail(SelfSite.FileName, SelfSite.Line, K.QName + ' hands Self out'));
  var Marks: TArray<THbSite>:= nil;
  var FirstLine:= MaxInt;
  var FirstCol:= MaxInt;
  for var C in CallsIn(pCtorId) do
    if (C.NRcv = 1) and (C.RcvSymId = pField.Id) and C.Certain and CalleeSetMust(C.CalleeId, False) then
    begin
      Marks:= Marks + [SiteOf(C.FilePath, C.Line, C.Col)];
      if Before(C.Line, C.Col, FirstLine, FirstCol) then
      begin
        FirstLine:= C.Line;
        FirstCol:= C.Col;
      end;
    end;
  if Marks = nil then
    Exit(FailAt(K, K.QName + ' does not call a writer method of ' + FFieldName + ' on ' + pField.Name));
  var Queries: TArray<THbSite>:= nil;
  for var X in pRefs do
  begin
    if X.EnclosingId <> pCtorId then Continue;
    if (X.Kind = REF_WRITE) and not Before(X.Line, X.Col, FirstLine, FirstCol) then
      Exit(Fail(X.FilePath, X.Line, pField.Name + ' is re-assigned after the writer call in ' + K.QName));
    Queries:= Queries + [SiteOf(X.FilePath, X.Line, X.Col)];
  end;
  var St:= Solve(pCtorId, Marks, Queries, False);
  if not St.Found then Exit(FailNotSolved);
  for var Q in St.Queries do
    if Q.InClosure then
      Exit(Fail(Q.Site.FileName, Q.Site.Line, pField.Name + ' is used inside an anonymous method'));
  if not St.ExitDone then
    Exit(FailAt(K, K.QName + ' does not call a writer method of ' + FFieldName + ' on ' + pField.Name +
      ' on every path'));
  Result:= Ok('');
end;

{ The caller P of a field-receiver call must not run while an object is being built or torn down: no
  constructor, destructor or unordered root reaches it (callers of any confidence, dispatch fan-in). }
function TRecvSolver.OnlyAfterConstruction(const pRoutine: TRecvSym): TRecvResult;
begin
  var Esc:= FEscape.ClassOf(pRoutine.Id);
  if Esc <> hecNone then
    Exit(FailAt(pRoutine, pRoutine.QName + ' is an unordered root (' + EscapeClassCode(Esc) + ')'));
  Result:= Ok('');
  var Seen:= THashSet<Int64>.Create;
  var Work:= TQueue<Int64>.Create;
  try
    Seen.Add(pRoutine.Id);
    Work.Enqueue(pRoutine.Id);
    while Work.Count > 0 do
    begin
      var Cur:= Work.Dequeue;
      for var C in CallersOf(Cur) do
      begin
        if C.CallerId = 0 then Exit(Fail(C.FilePath, C.Line, 'reached from outside any routine'));
        var X:= Sym(C.CallerId);
        if IsCtorOrDtor(X) then
          Exit(Fail(C.FilePath, C.Line, 'reached from the ' + X.Kind + ' ' + X.QName));
        if (X.Kind = 'program') or (X.Kind = 'library') or (X.Kind = 'initialization') then Continue;
        if not Seen.Add(X.Id) then Continue;
        Esc:= FEscape.ClassOf(X.Id);
        if Esc <> hecNone then
          Exit(FailAt(X, 'reached from ' + X.QName + ', an unordered root (' + EscapeClassCode(Esc) + ')'));
        if Seen.Count > FMax * WALK_FACTOR then
        begin
          FExhausted:= True;
          Exit(FailNotSolved);
        end;
        Work.Enqueue(X.Id);
      end;
    end;
  finally
    Work.Free;
    Seen.Free;
  end;
end;

{ ApplyReceiverProof }

function Eligible(const pUse: THbUseAnswer): Boolean;
begin
  Result:= False;
  if pUse.Verdict <> hvMayBeUnset then Exit;
  for var R in pUse.Reasons do
    if R in [hrCtorMissesField, hrNoDeclaredCtor, hrSubclassCtorSkips] then Result:= True
    else if R not in [hrSoftWriter, hrNilWriteOnly, hrGuardedTest] then Exit(False);
end;

function ApplyReceiverProof(const pIndex: TChartsIndex; const pStore: ISymbolStore; var pAnswer: THbAnswer;
  pMaxRoutines: Integer): Integer;
begin
  Result:= 0;
  if (pAnswer.Scope <> hsInstance) or (pAnswer.Target.Kind <> htkInstanceField) or
    (pAnswer.Target.SymbolId = 0) or (pAnswer.Verdict = hvNeverSet) then Exit;
  var Any:= False;
  for var U in pAnswer.JudgedUses do
    if Eligible(U) then Any:= True;
  if not Any then Exit;
  var Solver:= TRecvSolver.Create(pIndex, pStore, if pMaxRoutines > 0 then pMaxRoutines
    else HB_DEFAULT_MAX_ROUTINES);
  try
    Solver.Prepare(pAnswer);
    for var I:= 0 to High(pAnswer.JudgedUses) do
    begin
      if not Eligible(pAnswer.JudgedUses[I]) then Continue;
      var Res:= Solver.ProveUse(pAnswer.JudgedUses[I]);
      var Guarded:= TArray.Contains<THbReason>(pAnswer.JudgedUses[I].Reasons, hrGuardedTest);
      if Res.Ok then
      begin
        pAnswer.JudgedUses[I].Verdict:= hvSet;
        pAnswer.JudgedUses[I].Reasons:= if Guarded then [hrGuardedTest] else nil;
        pAnswer.JudgedUses[I].Witness:= nil;
        pAnswer.JudgedUses[I].Why:= HB_RECV_WHY_SET + Res.Why;
        Inc(Result);
      end
      else
      begin
        AddReason(pAnswer.JudgedUses[I].Reasons, hrReceiverUnproven);
        pAnswer.JudgedUses[I].Reasons:= SortedReasons(pAnswer.JudgedUses[I].Reasons);
        pAnswer.JudgedUses[I].Why:= pAnswer.JudgedUses[I].Why + ' -- ' + HB_RECV_WHY_UNPROVEN + Res.Site + ': ' +
          Res.Why;
      end;
    end;
    pAnswer.Budget.Routines:= pAnswer.Budget.Routines + Solver.SolvedCount;
    if Solver.Exhausted then
    begin
      pAnswer.Budget.Exhausted:= True;
      AddReason(pAnswer.Reasons, hrBudget);
      pAnswer.Reasons:= SortedReasons(pAnswer.Reasons);
    end;
  finally
    Solver.Free;
  end;
  if Result = 0 then Exit;
  { the headline as the constructor model counts it: the worst use, a guarded test only when alone }
  var Headline:= hvSet;
  var AnyCounted:= False;
  for var U in pAnswer.JudgedUses do
    if not TArray.Contains<THbReason>(U.Reasons, hrGuardedTest) or (Length(pAnswer.JudgedUses) = 1) then
    begin
      Headline:= HbWorseVerdict(Headline, U.Verdict);
      AnyCounted:= True;
    end;
  if not AnyCounted then Exit;
  pAnswer.Verdict:= Headline;
  pAnswer.Proven:= Headline = hvSet;
  if Headline = hvSet then pAnswer.Summary:= SUMMARY_SET;
end;

end.
