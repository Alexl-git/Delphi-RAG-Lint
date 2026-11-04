unit DRagLint.Lint.OpaqueToAnalysis;

{ opaque-to-analysis (1.42 lane opaque; INBOX-new-rules-from-graph-and-converter-facts C2,
  BACKLOG-AFTER-1.37.0 TRIAGE #34).

  A rule about the limits of our own analysis, not about style. A call that stays
  in the project has a call_edges row; a call that leaves it (RTL, VCL, a typed
  third-party receiver) cannot reach project code by name either. What remains is a
  call the index cannot place at all: a procedural value, a member of an untypable
  receiver, an overload the resolver declined. A routine made mostly of those is
  one where `impact`, call trees and dead-code detection see almost nothing.

  Project DBs carry no refs.external_target unless the section opts in with
  libraryResolve (measured 2026-11-04: 0 on ORM3 CLIENT / SERVER, YADF, DataCopy and
  the engine), so the library half is judged HERE, live, through TLibraryOracle --
  a pure reader that writes nothing. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>Rule id: a routine whose non-library calls are predominantly unresolvable.</summary>
  OPAQUE_TO_ANALYSIS_RULE = 'opaque-to-analysis';

/// <summary>Finds every routine whose calls that do not provably leave the project are
/// predominantly calls the index cannot resolve.</summary>
/// <param name="AStore">The project index; nil yields no findings.</param>
/// <param name="ALibStore">The platform library index. nil yields NO findings: without it
/// every RTL / VCL call would read as opaque.</param>
/// <param name="AOnlyFileId">Only routines of this file when positive (`lint file`), else all.</param>
/// <returns>One info finding per routine, at its implementation line (its declaration line
/// when it has no separate body), stating opaque count, the denominator and a sample of names.</returns>
/// <remarks>Fires at 3 or more opaque calls forming 60 percent or more of
/// (opaque + calls with a call_edges row). A call counts as OUTSIDE, in neither figure, when it
/// is a compiler intrinsic or a type cast, carries a stored external_target, has a receiver
/// typed by a name the project does not declare, has a project-typed receiver whose chain does
/// not declare the member, or the oracle binds it. An ambiguous call_edges row counts as
/// resolved. Read-only; never raises on an unknown name. Not thread-safe.</remarks>
function CollectOpaqueToAnalysis(const AStore, ALibStore: ISymbolStore;
  AOnlyFileId: Int64 = 0): TArray<TLintFinding>;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.Generics.Collections
  , DRagLint.Index.LibraryOracle
  ;

type
  TOpaqueKindSet = set of TSymbolKind;
  TCallVerdict   = (cvOutside, cvOpaque);

const
  { Picked from the distribution measured on real indexes (wiki page opaque-to-analysis): 3 calls
    keep a routine with two callback invocations out; 60 percent is a clear majority, not a tie. }
  OPAQUE_MIN_CALLS   = 3;
  OPAQUE_MIN_PERCENT = 60;
  PERCENT            = 100;
  MAX_NAMES_SHOWN    = 5;

  ROUTINE_KINDS: array[0..4] of string = ('method', 'function', 'procedure', 'constructor', 'destructor');
  TYPE_KINDS   : TOpaqueKindSet = [skClass, skInterface, skRecord, skTypeAlias, skEnum];
  ROUTINE_SKS  : TOpaqueKindSet = [skProcedure, skFunction];
  MEMBER_SKS   : TOpaqueKindSet = [skMethod, skConstructor, skDestructor, skProcedure, skFunction, skProperty, skField];
  STRUCT_KINDS : TOpaqueKindSet = [skClass, skInterface, skRecord];

  { Compiler magic and built-in type casts: System.pas declares none of these as routines the
    library index could answer, and all of them are written as a call. }
  INTRINSIC_CALLS: array[0..113] of string = (
    'abs', 'addr', 'ansichar', 'ansistring', 'append', 'arctan', 'assert', 'assigned',
    'assignfile', 'blockread', 'blockwrite', 'boolean', 'break', 'byte', 'cardinal', 'char',
    'chr', 'close', 'closefile', 'concat', 'continue', 'copy', 'cos', 'dec', 'default',
    'delete', 'dispose', 'double', 'eof', 'eoln', 'erase', 'exclude', 'exit', 'exp', 'extended',
    'filepos', 'filesize', 'fillchar', 'finalize', 'flush', 'frac', 'freemem', 'getdir',
    'getmem', 'halt', 'hi', 'high', 'inc', 'include', 'initialize', 'insert', 'int', 'int64',
    'integer', 'ioresult', 'length', 'ln', 'lo', 'longint', 'longword', 'low', 'mkdir', 'move',
    'nativeint', 'nativeuint', 'new', 'odd', 'ord', 'pansichar', 'pchar', 'pi', 'pointer',
    'pred', 'ptr', 'pwidechar', 'random', 'randomize', 'read', 'readln', 'reallocmem', 'rename',
    'reset', 'rewrite', 'rmdir', 'round', 'runerror', 'seek', 'setlength', 'shortint',
    'shortstring', 'sin', 'single', 'sizeof', 'slice', 'smallint', 'sqr', 'sqrt', 'str',
    'string', 'succ', 'swap', 'trunc', 'truncate', 'typeinfo', 'uint64', 'unicodestring',
    'upcase', 'val', 'variant', 'widechar', 'widestring', 'word', 'write', 'writeln');

type
  { One scan: per-name and per-file memos over one project + one library store. }
  TOpaqueScan = class  // dl:ok high-response@71f5 -- REVIEWED 2026-11-04 (lane opaque): one scan object, half its response set is memo accessors over two stores; splitting it would only pass the caches between classes.
  strict private
    FStore   : ISymbolStore;
    FLib     : ISymbolStore;
    FOracle  : TLibraryOracle;
    FByName  : TDictionary<string, TArray<TSymbol>>;
    FLibName : TDictionary<string, TArray<TSymbol>>;
    FById    : TDictionary<Int64, TSymbol>;
    FUses    : TDictionary<Int64, TArray<string>>;
    FScope   : TDictionary<Int64, string>;
    FIntr    : TDictionary<string, Boolean>;
    function Named(const AName: string): TArray<TSymbol>;
    function LibNamed(const AName: string): TArray<TSymbol>;
    function ById(AId: Int64): TSymbol;
    function UsedUnits(AFileId: Int64): TArray<string>;
    function ProjectType(const AName: string; out AType: TSymbol): Boolean;
    function LibHasKind(const AName: string; const AKinds: TOpaqueKindSet): Boolean;
    function EnclosingClass(const ARoutine: TSymbol; out AClass: TSymbol): Boolean;
    function ChainDeclares(const AType: TSymbol; const AMember: string): Boolean;
    function FirstOutsideAncestor(const AType: TSymbol): string;
    function ScopeTypeOf(const ARoutine: TSymbol): string;
    function VisibleProjectRoutine(const ARef: TReference; const ARoutine: TSymbol): Boolean;
    function JudgeBare(const ARef: TReference; const ARoutine: TSymbol): TCallVerdict;
    function JudgeTyped(const ARef: TReference): TCallVerdict;
    function JudgeHead(const ARef: TReference; const ARoutine: TSymbol): TCallVerdict;
  public
    constructor Create(const AStore, ALib: ISymbolStore);
    destructor Destroy; override;
    function Judge(const ARef: TReference; const ARoutine: TSymbol): TCallVerdict;
  end;

{ The first heritage entry of a type, generic arguments, unit qualifier and parentheses stripped. }
function FirstAncestorLeaf(const AHeritage: string): string;
var
  P: Integer;
begin
  Result:= Trim(AHeritage);
  if Result.StartsWith('(') then Result:= Copy(Result, 2, MaxInt);
  P:= Pos(',', Result);
  if P > 0 then Result:= Copy(Result, 1, P - 1);
  P:= Pos('<', Result);
  if P > 0 then Result:= Copy(Result, 1, P - 1);
  P:= Pos(')', Result);
  if P > 0 then Result:= Copy(Result, 1, P - 1);
  P:= LastDelimiter('.', Result);
  if P > 0 then Result:= Copy(Result, P + 1, MaxInt);
  Result:= Trim(Result);
end;

{ The receiver reduced to its dotted identifier chain: `TArray<Integer>` -> `TArray`; '' when it
  holds anything an identifier chain cannot (a call, an index, a cast). }
function PlainChain(const AReceiver: string): string;
var
  P: Integer;
begin
  Result:= Trim(AReceiver);
  P:= Pos('<', Result);
  if P > 0 then Result:= Copy(Result, 1, P - 1);
  for var C in Result do
    if not (CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '.'])) then Exit('');
end;

constructor TOpaqueScan.Create(const AStore, ALib: ISymbolStore);
begin
  inherited Create;
  FStore  := AStore;
  FLib    := ALib;
  FOracle := TLibraryOracle.Create([ALib]);
  FByName := TDictionary<string, TArray<TSymbol>>.Create;
  FLibName:= TDictionary<string, TArray<TSymbol>>.Create;
  FById   := TDictionary<Int64, TSymbol>.Create;
  FUses   := TDictionary<Int64, TArray<string>>.Create;
  FScope  := TDictionary<Int64, string>.Create;
  FIntr   := TDictionary<string, Boolean>.Create;
  for var S in INTRINSIC_CALLS do FIntr.Add(S, True);
end;

destructor TOpaqueScan.Destroy;
begin
  FIntr   .Free;
  FScope  .Free;
  FUses   .Free;
  FById   .Free;
  FLibName.Free;
  FByName .Free;
  FOracle .Free;
  inherited Destroy;
end;

function TOpaqueScan.Named(const AName: string): TArray<TSymbol>;
begin
  var Key:= LowerCase(AName);
  if FByName.TryGetValue(Key, Result) then Exit;
  Result:= FStore.FindSymbolsByExactName(AName);
  FByName.Add(Key, Result);
end;

function TOpaqueScan.LibNamed(const AName: string): TArray<TSymbol>;
begin
  var Key:= LowerCase(AName);
  if FLibName.TryGetValue(Key, Result) then Exit;
  Result:= FLib.FindSymbolsByExactName(AName);
  FLibName.Add(Key, Result);
end;

function TOpaqueScan.ById(AId: Int64): TSymbol;
begin
  if FById.TryGetValue(AId, Result) then Exit;
  Result:= FStore.GetSymbolById(AId);
  FById.Add(AId, Result);
end;

function TOpaqueScan.UsedUnits(AFileId: Int64): TArray<string>;
begin
  if FUses.TryGetValue(AFileId, Result) then Exit;
  Result:= nil;
  for var U in FStore.GetUnitUsesForFile(AFileId) do Result:= Result + [LowerCase(U.UnitName)];
  FUses.Add(AFileId, Result);
end;

function TOpaqueScan.ProjectType(const AName: string; out AType: TSymbol): Boolean;
begin
  Result:= False;
  AType := Default(TSymbol);
  for var S in Named(AName) do
    if S.Kind in TYPE_KINDS then
    begin
      AType:= ById(S.Id);
      Exit(True);
    end;
end;

function TOpaqueScan.LibHasKind(const AName: string; const AKinds: TOpaqueKindSet): Boolean;
begin
  Result:= False;
  for var S in LibNamed(AName) do
    if S.Kind in AKinds then Exit(True);
end;

{ The class a method (or a routine nested in one) belongs to. }
function TOpaqueScan.EnclosingClass(const ARoutine: TSymbol; out AClass: TSymbol): Boolean;
begin
  Result:= False;
  AClass:= Default(TSymbol);
  var Id:= ARoutine.ParentId;
  while Id > 0 do
  begin
    var P:= ById(Id);
    if P.Id = 0 then Exit;
    if P.Kind in STRUCT_KINDS then
    begin
      AClass:= P;
      Exit(True);
    end;
    Id:= P.ParentId;
  end;
end;

{ True when AType or a project ancestor declares AMember. Bounded by the seen-set: a corrupt
  or generic-erased heritage can name a type that names it back. }
function TOpaqueScan.ChainDeclares(const AType: TSymbol; const AMember: string): Boolean;
var
  Seen: TDictionary<Int64, Boolean>;
begin
  Result:= False;
  var Members:= Named(AMember);
  if Length(Members) = 0 then Exit;
  Seen:= TDictionary<Int64, Boolean>.Create;
  try
    var T:= AType;
    while (T.Id > 0) and not Seen.ContainsKey(T.Id) do
    begin
      Seen.Add(T.Id, True);
      for var M in Members do
        if (M.ParentId = T.Id) and (M.Kind in MEMBER_SKS) then Exit(True);
      var Next: TSymbol;
      if not ProjectType(FirstAncestorLeaf(T.Heritage), Next) then Exit;
      T:= Next;
    end;
  finally
    Seen.Free;
  end;
end;

{ The first ancestor of AType the project does not declare; '' when the chain ends inside it. }
function TOpaqueScan.FirstOutsideAncestor(const AType: TSymbol): string;
var
  Seen: TDictionary<Int64, Boolean>;
begin
  Result:= '';
  Seen:= TDictionary<Int64, Boolean>.Create;
  try
    var T:= AType;
    while (T.Id > 0) and not Seen.ContainsKey(T.Id) do
    begin
      Seen.Add(T.Id, True);
      var Anc := FirstAncestorLeaf(T.Heritage);
      var Next: TSymbol;
      if Anc = '' then Exit;
      if not ProjectType(Anc, Next) then Exit(Anc);
      T:= Next;
    end;
  finally
    Seen.Free;
  end;
end;

function TOpaqueScan.ScopeTypeOf(const ARoutine: TSymbol): string;
var
  Cls: TSymbol;
begin
  Result:= '';
  if not EnclosingClass(ARoutine, Cls) then Exit;
  if FScope.TryGetValue(Cls.Id, Result) then Exit;
  Result:= FirstOutsideAncestor(Cls);
  FScope.Add(Cls.Id, Result);
end;

{ A project routine of the name this file can see: its own unit or a used one. A same-named
  routine in a unit it does not use cannot be what it calls. }
function TOpaqueScan.VisibleProjectRoutine(const ARef: TReference; const ARoutine: TSymbol): Boolean;
var
  Cls: TSymbol;
begin
  Result:= False;
  if EnclosingClass(ARoutine, Cls) and ChainDeclares(Cls, ARef.NameText) then Exit(True);
  var Used:= UsedUnits(ARef.FileId);
  for var S in Named(ARef.NameText) do
    if S.Kind in ROUTINE_SKS then
    begin
      if S.FileId = ARef.FileId then Exit(True);
      if MatchText(ChangeFileExt(ExtractFileName(FStore.GetFilePath(S.FileId)), ''), Used) then Exit(True);
    end;
end;

function TOpaqueScan.JudgeBare(const ARef: TReference; const ARoutine: TSymbol): TCallVerdict;
var
  Reason: string;
  T     : TSymbol;
begin
  if VisibleProjectRoutine(ARef, ARoutine) then Exit(cvOpaque);
  if ProjectType(ARef.NameText, T) then Exit(cvOutside);
  if LibHasKind(ARef.NameText, TYPE_KINDS) then Exit(cvOutside);
  if FOracle.BindBare(ARef.NameText, UsedUnits(ARef.FileId), ScopeTypeOf(ARoutine), Reason) <> '' then Exit(cvOutside);
  { An overload set the oracle will not pick from is still the library's. }
  if LibHasKind(ARef.NameText, ROUTINE_SKS) then Exit(cvOutside);
  Result:= cvOpaque;
end;

function TOpaqueScan.JudgeTyped(const ARef: TReference): TCallVerdict;
var
  T: TSymbol;
begin
  var Dot    := Pos('.', ARef.ReceiverTypeText);
  var Head   := if Dot > 0 then Copy(ARef.ReceiverTypeText, 1, Dot - 1) else ARef.ReceiverTypeText;
  var Pending:= if Dot > 0 then Copy(ARef.ReceiverTypeText, Dot + 1, MaxInt) else '';
  if not ProjectType(Head.TrimLeft(['^']), T) then Exit(cvOutside);
  var First:= if Pending <> '' then Pending.Split(['.'])[0] else ARef.NameText;
  Result:= if ChainDeclares(T, First) then cvOpaque else cvOutside;
end;

function TOpaqueScan.JudgeHead(const ARef: TReference; const ARoutine: TSymbol): TCallVerdict;
var
  Reason, TypeText: string;
  T: TSymbol;
begin
  var Chain:= PlainChain(ARef.ReceiverText);
  if Chain = '' then Exit(cvOpaque);
  var Head:= Chain.Split(['.'])[0];
  if Named(Head) <> nil then
    for var S in Named(Head) do
      if S.Kind in [skVarDecl, skConstDecl] then Exit(cvOpaque);
  if ProjectType(Head, T) then Exit(if ChainDeclares(T, ARef.NameText) then cvOpaque else cvOutside);
  if FOracle.BindHead(Chain, ARef.NameText, ekCall, UsedUnits(ARef.FileId), ScopeTypeOf(ARoutine), Reason, TypeText) <> '' then
    Exit(cvOutside);
  { `TPath.X`, `System.SysUtils.Y`: a library type or unit named in the source, whatever the oracle
    made of the member. }
  if LibHasKind(Head, TYPE_KINDS) or LibHasKind(Chain, [skUnit]) or LibHasKind(Head, [skUnit]) then Exit(cvOutside);
  Result:= cvOpaque;
end;

function TOpaqueScan.Judge(const ARef: TReference; const ARoutine: TSymbol): TCallVerdict;
begin
  if ARef.ExternalTarget <> '' then Exit(cvOutside);
  if (ARef.ReceiverText = '') and FIntr.ContainsKey(LowerCase(ARef.NameText)) then Exit(cvOutside);
  if ARef.ReceiverText = '' then Exit(JudgeBare(ARef, ARoutine));
  if ARef.ReceiverTypeText <> '' then Exit(JudgeTyped(ARef));
  Result:= JudgeHead(ARef, ARoutine);
end;

function CollectOpaqueToAnalysis(const AStore, ALibStore: ISymbolStore;
  AOnlyFileId: Int64): TArray<TLintFinding>;
var
  Scan    : TOpaqueScan;
  Findings: TList<TLintFinding>;
begin
  Result:= nil;
  if (AStore = nil) or (ALibStore = nil) then Exit;
  Scan    := TOpaqueScan.Create(AStore, ALibStore);
  Findings:= TList<TLintFinding>.Create;
  try
    for var Kind in ROUTINE_KINDS do
      for var R in AStore.FindSymbolsByKind(Kind, False, MaxInt) do
      begin
        if (AOnlyFileId > 0) and (R.FileId <> AOnlyFileId) then Continue;
        var Calls:= AStore.GetUnresolvedCallsFromSymbol(R.Id);
        if Length(Calls) < OPAQUE_MIN_CALLS then Continue;
        var Opaque := 0;
        var Names: TArray<string>:= nil;
        for var C in Calls do
          if Scan.Judge(C, R) = cvOpaque then
          begin
            Inc(Opaque);
            if (Length(Names) < MAX_NAMES_SHOWN) and not MatchText(C.NameText, Names) then
              Names:= Names + [C.NameText];
          end;
        if Opaque < OPAQUE_MIN_CALLS then Continue;
        var Total:= Opaque + Length(AStore.GetCallEdgesFromSymbol(R.Id));
        if Opaque * PERCENT < OPAQUE_MIN_PERCENT * Total then Continue;

        var Line:= if R.ImplStartLine > 0 then R.ImplStartLine else R.StartLine;
        var F: TLintFinding:= Default(TLintFinding);
        F.RuleId   := OPAQUE_TO_ANALYSIS_RULE;
        F.Severity := 'info';
        F.FilePath := AStore.GetFilePath(R.FileId);
        F.StartLine:= Line;
        F.StartCol := 1;
        F.EndLine  := Line;
        F.EndCol   := 1;
        F.Message  := Format('%s: %d of %d calls that do not provably leave the project could not be ' +
                             'resolved (%s) -- impact analysis, call trees and dead-code detection are ' +
                             'blind inside this routine',
                             [R.QualifiedName, Opaque, Total, string.Join(', ', Names)]);
        Findings.Add(F);
      end;
    Result:= Findings.ToArray;
  finally
    Findings.Free;
    Scan    .Free;
  end;
end;

end.