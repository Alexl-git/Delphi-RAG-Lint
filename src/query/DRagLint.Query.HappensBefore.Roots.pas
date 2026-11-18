unit DRagLint.Query.HappensBefore.Roots;

{ drag-lint 1.52 -- lane HBROOTS: where execution can start (spec 2026-11-17-happens-before-design.md 3 and 5.2).

  ORDERED roots: per program, the initialization sections in the computed unit order (ProgramInitOrders of
  DRagLint.Lint.InitSections -- the order init-order-hazard walks), then the program main block.
  ESCAPED routines (unordered roots, EntryDone = False): a routine the call graph cannot account for because
  something outside the code calls it -- a DFM event, the published section, a message handler, an interface
  method answer, a routine whose address is taken, an exported routine, a thread Execute, a class constructor /
  destructor, a finalization section -- or one with ZERO callers that is none of those.
  Overrides are not escaped: their callers are the callers of the base methods they override (dispatch_edges).

  Read-only; nothing is persisted (no extractor change).

  Blind spots (index shape, 1.52): a parameterless FUNCTION named without `@` on the right of `:=` gets the
  same read / member-access ref and certain call edge whether it is called or assigned as a method pointer,
  so it is taken as a call. A procedure in that position can only be a value and is address-taken. An
  `exports` clause entry is a refs row of kind REF_KIND_EXPORT bound to the routine (1.52 EXTGAPS2; no call edge). }

interface

uses
  System.Generics.Collections
, DRagLint.Core.Model
, DRagLint.Core.Interfaces
  ;

type
  /// <summary>What an ordered root is.</summary>
  THbRootKind = (hrkInitialization, hrkProgramBlock);

  /// <summary>One link of an ordered root chain.</summary>
  /// <remarks>SymbolId is the initialization section symbol (hrkInitialization) or the program symbol
  /// (hrkProgramBlock). UnitName is '' for the program block.</remarks>
  THbOrderedRoot = record
    Kind: THbRootKind;
    SymbolId: Int64;
    UnitName: string;
    FileId: Int64;
    /// <summary>Display name in run order: 'initialization of Boot' / 'program block of App.dpr'.</summary>
    Display: string;
  end;

  /// <summary>The ordered root chain of one program (spec 5.2).</summary>
  /// <remarks>Roots run first to last. A unit without an initialization section is not a link (it runs
  /// nothing); the program block is the last link when the program symbol is indexed. Unreliable: some uses
  /// entry that decides the order is conditional or include-borne (reason code unreliable-order); the
  /// chain is the order of the indexed configuration and UnreliableReason names the first such site.</remarks>
  THbRootChain = record
    ProgramFileId: Int64;
    ProgramName: string;
    Roots: TArray<THbOrderedRoot>;
    Unreliable: Boolean;
    UnreliableReason: string;
  end;

  /// <summary>Every ordered root chain of the index, one per program file.</summary>
  /// <remarks>Empty Chains: the index holds no program (a package or a unit set); every initialization
  /// section is then unordered and the solver must not rely on any order.</remarks>
  THbRoots = record
    Chains: TArray<THbRootChain>;
  end;

  /// <summary>Why a routine is an unordered root (spec 5.2). Literals: EscapeClassCode.</summary>
  /// <remarks>hecNone = not escaped: it runs only when its callers run (or it is an ordered root, or an
  /// override reached through its bases). The order is the order IsEscaped tests them; the first that holds
  /// is reported.</remarks>
  THbEscapeClass = (hecNone, hecFinalization, hecClassCtorDtor, hecDfmEvent, hecMessageHandler,
    hecThreadExecute, hecExported, hecInterfaceMethod, hecPublished, hecAddressTaken, hecZeroCallers);

  /// <summary>Classifies routines as escaped or not, caching what is shared between routines (the
  /// interface-answer set, the TThread descendants).</summary>
  /// <remarks>Read-only on the store. Not thread-safe; one instance per query. The store must outlive it.</remarks>
  THbEscapeClassifier = class  // dl:ok high-response@8273 -- REVIEWED 2026-11-17 v152 HBROOTS: one classifier, one escape class per question (spec 5.2 lists ten); its RFC is the store calls each class needs, splitting it would only spread the same calls
  strict private
    FStore: ISymbolStore;
    FAnswers: THashSet<Int64>;
    FThreadClasses: THashSet<string>;
    FAnswersLoaded: Boolean;
    FThreadsLoaded: Boolean;
    FFileIds: TDictionary<string, Int64>;
    procedure LoadAnswers;
    function IsThreadClass(const pName: string): Boolean;
    function ParentClassOf(const pSym: TSymbol): TSymbol;
    function FileIdOf(const pPath: string): Int64;
    function IsExportedByClause(const pSym: TSymbol): Boolean;
    function IsCallRefAt(const pSym: TSymbol; const pCaller: TResolvedCaller): Boolean;
    function ScanCallers(const pSym: TSymbol; out pAddressTaken, pExported: Boolean): Boolean;
    function DeclaredClassOf(const pSym: TSymbol): THbEscapeClass;
    function MemberClassOf(const pSym: TSymbol): THbEscapeClass;
  public
    /// <summary>Creates a classifier over pStore.</summary>
    /// <param name="pStore">The project index; must not be nil.</param>
    constructor Create(const pStore: ISymbolStore);
    /// <summary>Frees the caches.</summary>
    destructor Destroy; override;
    /// <summary>The escape class of one routine.</summary>
    /// <param name="pRoutineId">symbols.id of a routine, an initialization / finalization section or the
    /// program symbol.</param>
    /// <returns>hecNone for an ordered root (initialization, program block), an override with a base, a
    /// routine with at least one real call and no other escape, or an unknown id; else the first escape
    /// class that holds.</returns>
    /// <remarks>A routine passed as a value (call_edges confidence 'callback', a bound non-call ref such as
    /// `@Proc`, or a call edge whose ref is no `call` ref, as the index records `OnX := H.Handler`) is
    /// hecAddressTaken. A routine named in an `exports` clause (or carrying the `export` directive) is
    /// hecExported; the clause entry is its REF_KIND_EXPORT ref (1.52). The leading unlabelled section of a class is treated as
    /// published (under $M+ it is; the index cannot tell $M+), which can only add escapes, never hide one.</remarks>
    function ClassOf(pRoutineId: Int64): THbEscapeClass;
  end;

/// <summary>Loads the ordered root chains of every program in the index (spec 5.2).</summary>
/// <param name="pStore">The project index; nil yields no chains.</param>
/// <returns>One chain per program file, in ProgramInitOrders order; each chain lists the initialization
/// sections in the order init-order-hazard computes, then the program block.</returns>
/// <remarks>Read-only. Not thread-safe; reads the index once per call, nothing is cached.</remarks>
function LoadRoots(const pStore: ISymbolStore): THbRoots;  // dl:ok unused-public-symbol@a866 -- REVIEWED 2026-11-17 v152 HBROOTS: check-init roots API for lanes HBSOLVER / HBEVORD (merge after HBROOTS); today only tests\fixtures\happens-before\roots-harness\RootsHarness.dpr calls it

/// <summary>True when the routine is an unordered root (any escape class but hecNone).</summary>
/// <param name="pStore">The project index; must not be nil.</param>
/// <param name="pRoutineId">symbols.id of the routine.</param>
/// <returns>EscapeClassOf(...) &lt;&gt; hecNone.</returns>
/// <remarks>Builds a classifier per call; a caller judging many routines keeps one THbEscapeClassifier.</remarks>
function IsEscaped(const pStore: ISymbolStore; pRoutineId: Int64): Boolean;  // dl:ok unused-public-symbol@4d67 -- REVIEWED 2026-11-17 v152 HBROOTS: check-init roots API for lanes HBSOLVER / HBEVORD (merge after HBROOTS); today only tests\fixtures\happens-before\roots-harness\RootsHarness.dpr calls it

/// <summary>The escape class of one routine (see THbEscapeClassifier.ClassOf).</summary>
/// <param name="pStore">The project index; must not be nil.</param>
/// <param name="pRoutineId">symbols.id of the routine.</param>
/// <returns>The first escape class that holds, or hecNone.</returns>
function EscapeClassOf(const pStore: ISymbolStore; pRoutineId: Int64): THbEscapeClass;  // dl:ok unused-public-symbol@9889 -- REVIEWED 2026-11-17 v152 HBROOTS: check-init roots API for lanes HBSOLVER / HBEVORD (merge after HBROOTS); today only tests\fixtures\happens-before\roots-harness\RootsHarness.dpr calls it

/// <summary>The literal of an escape class: none, finalization, class-ctor-dtor, dfm-event,
/// message-handler, thread-execute, exported, interface-method, published, address-taken, zero-callers.</summary>
/// <param name="pClass">The escape class.</param>
/// <returns>The literal used in JSON and in --explain text.</returns>
function EscapeClassCode(pClass: THbEscapeClass): string;  // dl:ok unused-public-symbol@fe2b -- REVIEWED 2026-11-17 v152 HBROOTS: check-init roots API for lanes HBSOLVER / HBEVORD (merge after HBROOTS); today only tests\fixtures\happens-before\roots-harness\RootsHarness.dpr calls it

implementation

uses
  System.SysUtils
, DRagLint.Lint.InitSections
, DRagLint.Query.Implementors
  ;

const
  ESCAPE_CODES: array[THbEscapeClass] of string = ('none', 'finalization', 'class-ctor-dtor', 'dfm-event',
    'message-handler', 'thread-execute', 'exported', 'interface-method', 'published', 'address-taken',
    'zero-callers');
  THREAD_BASE = 'TThread';
  THREAD_ENTRY = 'Execute';
  CONFIDENCE_CALLBACK = 'callback';
  REF_KIND_CALL = 'call';

function EscapeClassCode(pClass: THbEscapeClass): string;
begin
  Result:= ESCAPE_CODES[pClass];
end;

function LoadRoots(const pStore: ISymbolStore): THbRoots;
begin
  Result:= Default(THbRoots);
  if pStore = nil then Exit;
  for var O: TProgramInitOrder in ProgramInitOrders(pStore) do
  begin
    var C:= Default(THbRootChain);
    C.ProgramFileId:= O.ProgramFileId;
    C.ProgramName:= O.ProgramName;
    C.Unreliable:= O.Unreliable;
    C.UnreliableReason:= O.UnreliableReason;
    for var U: TProgramInitUnit in O.Units do
    begin
      if U.InitId <= 0 then Continue;
      var R:= Default(THbOrderedRoot);
      R.Kind:= hrkInitialization;
      R.SymbolId:= U.InitId;
      R.UnitName:= U.Name;
      R.FileId:= U.FileId;
      R.Display:= 'initialization of ' + U.Name;
      C.Roots:= C.Roots + [R];
    end;
    if O.ProgramBlockId > 0 then
    begin
      var R:= Default(THbOrderedRoot);
      R.Kind:= hrkProgramBlock;
      R.SymbolId:= O.ProgramBlockId;
      R.FileId:= O.ProgramFileId;
      R.Display:= 'program block of ' + O.ProgramName;
      C.Roots:= C.Roots + [R];
    end;
    Result.Chains:= Result.Chains + [C];
  end;
end;

{ THbEscapeClassifier }

constructor THbEscapeClassifier.Create(const pStore: ISymbolStore);
begin
  inherited Create;
  FStore:= pStore;
  FAnswers:= THashSet<Int64>.Create;
  FThreadClasses:= THashSet<string>.Create;
  FFileIds:= TDictionary<string, Int64>.Create;
end;

destructor THbEscapeClassifier.Destroy;
begin
  FFileIds.Free;
  FThreadClasses.Free;
  FAnswers.Free;
  inherited Destroy;
end;

{ Every method that answers an interface method of an interface in the index: one pass over the
  interfaces, done on the first question that needs it. }
procedure THbEscapeClassifier.LoadAnswers;
begin
  if FAnswersLoaded then Exit;
  FAnswersLoaded:= True;
  for var Intf: TSymbol in FStore.FindSymbolsByKind('interface', False, MaxInt) do
    for var Member: TSymbol in FStore.FindAllChildSymbols(Intf.Id) do
      if Member.Kind in [skProcedure, skFunction, skMethod] then
        for var Answer: TSymbol in ImplementingMethodsOf(FStore, Member) do
          FAnswers.Add(Answer.Id);
end;

{ True when pName descends from TThread (the descendant set is loaded on the first question). }
function THbEscapeClassifier.IsThreadClass(const pName: string): Boolean;
begin
  if not FThreadsLoaded then
  begin
    FThreadsLoaded:= True;
    for var N: string in FStore.FindDescendantNames(THREAD_BASE) do
      FThreadClasses.Add(LowerCase(N));
  end;
  Result:= FThreadClasses.Contains(LowerCase(pName));
end;

function THbEscapeClassifier.ParentClassOf(const pSym: TSymbol): TSymbol;
begin
  Result:= Default(TSymbol);
  if pSym.ParentId <= 0 then Exit;
  var P:= FStore.GetSymbolById(pSym.ParentId);
  if P.Kind in [skClass, skForm] then Result:= P;
end;

{ files.id of an indexed path (0 when the index holds no symbol in it); cached per path. }
function THbEscapeClassifier.FileIdOf(const pPath: string): Int64;
begin
  var Key:= LowerCase(pPath);
  if FFileIds.TryGetValue(Key, Result) then Exit;
  Result:= 0;
  for var S: TSymbol in FStore.FindSymbolsByFile(pPath) do
  begin
    Result:= S.FileId;
    Break;
  end;
  FFileIds.Add(Key, Result);
end;

{ True when an `exports` clause names pSym: a REF_KIND_EXPORT ref bound to it (1.52 EXTGAPS2). Before 1.52
  the entry was a 'call' ref with a call edge and this read the clause back from the source text. }
function THbEscapeClassifier.IsExportedByClause(const pSym: TSymbol): Boolean;
begin
  Result:= False;
  for var R: TReference in FStore.FindReferencesTo(pSym.Id) do
    if SameText(R.Kind, REF_KIND_EXPORT) then Exit(True);
end;

{ True when pSym returns a value: a function, or a method whose signature ends in `: <type>` after its
  parameter list. }
function ReturnsValue(const pSym: TSymbol): Boolean;
begin
  if pSym.Kind = skFunction then Exit(True);
  var Tail:= pSym.Signature;
  var P:= LastDelimiter(')', Tail);
  if P > 0 then Tail:= Copy(Tail, P + 1, MaxInt);
  Result:= Tail.Contains(':');
end;

{ True when the edge at the call site is a real call of pSym: a `call` ref sits there, or pSym returns a
  value (a parameterless function named in an expression is a call; the index gives it a read /
  member-access ref, the same shape as a function named as a value -- see the unit's blind spots).
  False when a procedure's edge sits on another ref kind (it is named as a value, e.g.
  `H.OnEvt := H.Handler`) or when no ref is found there (unknown is not a proven call). }
function THbEscapeClassifier.IsCallRefAt(const pSym: TSymbol; const pCaller: TResolvedCaller): Boolean;
begin
  Result:= False;
  if ReturnsValue(pSym) then Exit(True);
  var Fid:= FileIdOf(pCaller.FullPath);
  if Fid <= 0 then Exit;
  for var R: TReference in FStore.FindRefsNamingInFiles([Fid], [LowerCase(pSym.Name)]) do
    if (R.StartLine = pCaller.CallSiteLine) and (R.StartCol = pCaller.CallSiteCol) and (R.SymbolId = pSym.Id)
      and SameText(R.Kind, REF_KIND_CALL) then Exit(True);
end;

{ True when some site calls pSym for real. pAddressTaken: some site names it as a value (a callback edge,
  a bound non-call ref, or an edge on a non-call ref). pExported: an `exports` clause names it. }
function THbEscapeClassifier.ScanCallers(const pSym: TSymbol; out pAddressTaken, pExported: Boolean): Boolean;
begin
  Result:= False;
  pAddressTaken:= False;
  pExported:= IsExportedByClause(pSym);
  for var R: TResolvedCaller in FStore.FindResolvedCallers(pSym.Id) do
    if (R.Mode <> '') or SameText(R.Confidence, CONFIDENCE_CALLBACK) then pAddressTaken:= True
    else if IsCallRefAt(pSym, R) then Result:= True
    else pAddressTaken:= True;
end;

function HasWord(const pList, pWord: string): Boolean;
begin
  Result:= False;
  for var W: string in pList.Split([' ']) do
    if SameText(W, pWord) then Exit(True);
end;

{ The classes that need only the symbol row and its facts: finalization, class ctor/dtor, DFM event,
  message handler, then MemberClassOf. }
function THbEscapeClassifier.DeclaredClassOf(const pSym: TSymbol): THbEscapeClass;
begin
  Result:= if pSym.Kind = skFinalization then hecFinalization
    else if pSym.IsClassMethod and (pSym.Kind in [skConstructor, skDestructor]) then hecClassCtorDtor
    else if FStore.GetSymbolFacts(pSym.Id).DfmEvent <> '' then hecDfmEvent
    else if HasWord(pSym.Directives, 'message') then hecMessageHandler
    else MemberClassOf(pSym);
end;

{ A plain routine: exported by directive or not escaped by declaration. A method: thread Execute,
  interface answer, published (the unlabelled leading section counts as published). }
function THbEscapeClassifier.MemberClassOf(const pSym: TSymbol): THbEscapeClass;
begin
  var Cls:= ParentClassOf(pSym);
  if Cls.Id <= 0 then Exit(if HasWord(pSym.Directives, 'export') then hecExported else hecNone);
  if SameText(pSym.Name, THREAD_ENTRY) and IsThreadClass(Cls.Name) then Exit(hecThreadExecute);
  LoadAnswers;
  Result:= if FAnswers.Contains(pSym.Id) then hecInterfaceMethod
    else if SameText(Trim(pSym.Modifiers), 'published') or not pSym.VisExplicit then hecPublished
    else hecNone;
end;

function THbEscapeClassifier.ClassOf(pRoutineId: Int64): THbEscapeClass;
var
  AddressTaken, Exported: Boolean;
begin
  Result:= hecNone;
  var S:= FStore.GetSymbolById(pRoutineId);
  if (S.Id <= 0) or (S.Kind not in [skFinalization, skProcedure, skFunction, skMethod, skConstructor, skDestructor]) then
    Exit;
  Result:= DeclaredClassOf(S);
  if Result <> hecNone then Exit;
  var Called:= ScanCallers(S, AddressTaken, Exported);
  if Exported then Result:= hecExported
  else if AddressTaken then Result:= hecAddressTaken
  { An override is reached through its bases' callers (spec 5.2): not a root of its own. }
  else if not Called and (Length(FStore.FindDispatchLinks(S.Id, {AToBases=}True)) = 0) then Result:= hecZeroCallers;
end;

function EscapeClassOf(const pStore: ISymbolStore; pRoutineId: Int64): THbEscapeClass;
begin
  var C:= THbEscapeClassifier.Create(pStore);
  try
    Result:= C.ClassOf(pRoutineId);
  finally
    C.Free;
  end;
end;

function IsEscaped(const pStore: ISymbolStore; pRoutineId: Int64): Boolean;
begin
  Result:= EscapeClassOf(pStore, pRoutineId) <> hecNone;
end;

end.
