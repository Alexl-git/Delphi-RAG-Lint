unit DRagLint.Lint.InitSections;

{ The project rules on index fact F2 (1.44 lane rulesf2): references inside a unit's initialization or
  finalization section belong to the section symbol, so a section is a node of the call graph.

  THE COMPUTED ORDER. Nothing stores the order units initialize in, and it is not needed: it follows
  from the stored `uses` clauses. It is a depth-first post-order from the .dpr's uses list (unit_uses
  section 'program', in source order), each unit visiting its interface uses, then its implementation
  uses, then taking its place; a unit already being visited is skipped, which is what decides the
  order inside a cycle. Checked against the Win64 compiler on a program with four overlapping
  implementation-uses cycles: the printed order matched this model exactly.

  WHAT FOLLOWS. A unit that uses another without a cycle always initializes after it, so an inversion
  needs a uses cycle. Finalization runs in reverse, so "B initializes after A" is also "B is finalized
  before A". A .dpk has no computed order here: only programs are roots, and a unit no program reaches
  has no position and stays silent. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  INIT_ORDER_HAZARD_RULE = 'init-order-hazard';
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  FINALIZATION_AFTER_DEPENDENCY_RULE = 'finalization-after-dependency';

/// <summary>An initialization section reaches a global variable of a unit that initializes LATER in
/// the computed order, and that unit's own initialization is what sets the variable: the read sees
/// the value from before it was set.</summary>
/// <param name="AStore">The project index; nil yields no findings.</param>
/// <returns>One 'init-order-hazard' warning per (section's unit, later unit, variable), anchored at
/// the call or the reference in the section that starts the path.</returns>
/// <remarks>Not thread-safe. Follows call_edges rows of confidence 'certain' only, so virtual dispatch
/// and callbacks are not walked. A routine that also assigns the variable (lazy creation) or tests it
/// against nil stays silent. An index holding no .dpr has no root and yields nothing.</remarks>
function CollectInitOrderHazard(const AStore: ISymbolStore): TArray<TLintFinding>;

/// <summary>A finalization section reaches a global variable of a unit that is finalized EARLIER, and
/// that unit's own finalization tears the variable down: the read sees a freed object. Finalization runs
/// in reverse, so "finalized earlier" is "initializes later" in the computed order.</summary>
/// <param name="AStore">The project index; nil yields no findings.</param>
/// <returns>One 'finalization-after-dependency' warning per (section's unit, earlier unit, variable),
/// anchored at the call or the reference in the section that starts the path.</returns>
/// <remarks>Not thread-safe. The same walk and the same silences as init-order-hazard: certain call
/// edges only; a routine that assigns the variable or tests it against nil stays silent, which covers
/// the FreeAndNil + Assigned idiom. An index holding no .dpr yields nothing.</remarks>
function CollectFinalizationAfterDependency(const AStore: ISymbolStore): TArray<TLintFinding>;

implementation

uses
  System.SysUtils
  , System.IOUtils
  , System.StrUtils
  , System.RegularExpressions
  , System.Generics.Collections
  , System.Generics.Defaults
  ;

const
  KIND_UNIT  = 'unit';
  REF_WRITE  = 'write';
  REF_CALL   = 'call';
  ALLOCATING_INTRINSICS: array[0..2] of string = ('New', 'GetMem', 'SetLength');
  CONFIDENCE_CERTAIN = 'certain';
  SEVERITY_WARNING = 'warning';

type
  TUnitNode = record
    Name   : string;
    FileId : Int64;
    UnitId : Int64;
    InitId : Int64;  { the initialization section symbol, 0 when the unit has none }
    FinalId: Int64;  { the finalization section symbol, 0 when the unit has none }
  end;

  { A unit-level variable a section gives its state to. }
  TStateVar = record
    UnitKey: string;
    VarName: string;
  end;

  TSectionKind = (skiInit, skiFinal);

  { The index read once, for the rules of this unit: units, uses, refs by enclosing symbol, call edges. }
  TInitGraph = class
  private
    FStore     : ISymbolStore;
    FUnits     : TDictionary<string, TUnitNode>;
    FAmbiguous : TDictionary<string, Boolean>;
    FByFile    : TDictionary<Int64, string>;
    FUses      : TDictionary<Int64, TArray<string>>;
    FRefsLoaded: TDictionary<Int64, Boolean>;
    FRefs      : TObjectDictionary<Int64, TList<TReference>>;
    FEdges     : TDictionary<Int64, TArray<TCallEdge>>;
    FSymbols   : TDictionary<Int64, TSymbol>;
    FLines     : TDictionary<Int64, TArray<string>>;
    FOwnNames  : TObjectDictionary<Int64, TDictionary<string, Boolean>>;
    procedure LoadUnits;
    function UsesOfFile(AFileId: Int64): TArray<string>;
    procedure LoadRefsOfFile(AFileId: Int64);
  public
    constructor Create(const AStore: ISymbolStore);
    destructor Destroy; override;
    /// <summary>The files whose uses clause is a program's.</summary>
    function ProgramFiles: TArray<Int64>;
    /// <summary>Lower-case unit name -> position in the order AProgram initializes its units.</summary>
    /// <remarks>The caller owns the result.</remarks>
    function ComputeOrder(AProgram: Int64): TDictionary<string, Integer>;
    /// <summary>The refs enclosed by ASym; empty when none.</summary>
    function RefsOf(const ASym: TSymbol): TArray<TReference>;
    /// <summary>The certain, resolved call edges out of ASymbolId.</summary>
    function EdgesOf(ASymbolId: Int64): TArray<TCallEdge>;
    /// <summary>The symbol row, read once.</summary>
    function Symbol(AId: Int64): TSymbol;
    /// <summary>Does AFileId's source declare a symbol of this lower-case name?</summary>
    function FileDeclares(AFileId: Int64; const ALowerName: string): Boolean;
    /// <summary>Does AFileId's uses clause name this lower-case unit?</summary>
    function FileUses(AFileId: Int64; const ALowerUnit: string): Boolean;
    /// <summary>The body of ASym, joined; '' when the source cannot be read.</summary>
    function BodyText(const ASym: TSymbol): string;
    property Units: TDictionary<string, TUnitNode> read FUnits;
    property ByFile: TDictionary<Int64, string> read FByFile;
    property Store: ISymbolStore read FStore;
  end;

constructor TInitGraph.Create(const AStore: ISymbolStore);
begin
  inherited Create;
  FStore     := AStore;
  FUnits     := TDictionary<string, TUnitNode>.Create;
  FAmbiguous := TDictionary<string, Boolean>.Create;
  FByFile    := TDictionary<Int64, string>.Create;
  FUses      := TDictionary<Int64, TArray<string>>.Create;
  FRefsLoaded:= TDictionary<Int64, Boolean>.Create;
  FRefs      := TObjectDictionary<Int64, TList<TReference>>.Create([doOwnsValues]);
  FEdges     := TDictionary<Int64, TArray<TCallEdge>>.Create;
  FSymbols   := TDictionary<Int64, TSymbol>.Create;
  FLines     := TDictionary<Int64, TArray<string>>.Create;
  FOwnNames  := TObjectDictionary<Int64, TDictionary<string, Boolean>>.Create([doOwnsValues]);
  LoadUnits;
end;

destructor TInitGraph.Destroy;
begin
  FOwnNames.Free;
  FLines.Free;
  FSymbols.Free;
  FEdges.Free;
  FRefs.Free;
  FRefsLoaded.Free;
  FUses.Free;
  FByFile.Free;
  FAmbiguous.Free;
  FUnits.Free;
  inherited;
end;

{ A name two units of the index share (a directory index over several projects) has no one position:
  neither stays a node, so such a unit is silent rather than placed by a guess. }
procedure TInitGraph.LoadUnits;
begin
  for var U in FStore.FindSymbolsByKind(KIND_UNIT, False, MaxInt) do
  begin
    var Key: string:= LowerCase(U.Name);
    if FUnits.ContainsKey(Key) then
    begin
      FAmbiguous.AddOrSetValue(Key, True);
      Continue;
    end;
    var Node: TUnitNode:= Default(TUnitNode);
    Node.Name  := U.Name;
    Node.FileId:= U.FileId;
    Node.UnitId:= U.Id;
    for var Ch in FStore.FindAllChildSymbols(U.Id) do
    begin
      if Ch.Kind = skInitialization then Node.InitId:= Ch.Id;
      if Ch.Kind = skFinalization then Node.FinalId:= Ch.Id;
    end;
    FUnits.Add(Key, Node);
    FByFile.AddOrSetValue(U.FileId, Key);
  end;
  for var Key in FAmbiguous.Keys do
  begin
    FByFile.Remove(FUnits[Key].FileId);
    FUnits.Remove(Key);
  end;
end;

{ Interface uses first, then implementation uses, each in source order: the order the compiler visits. }
function TInitGraph.UsesOfFile(AFileId: Int64): TArray<string>;
begin
  if FUses.TryGetValue(AFileId, Result) then Exit;
  var Rows: TArray<TUnitUse>:= FStore.GetUnitUsesForFile(AFileId);
  TArray.Sort<TUnitUse>(Rows, TComparer<TUnitUse>.Construct(
    function(const A, B: TUnitUse): Integer
    begin
      Result:= (Ord(A.Section) - Ord(B.Section));
      if Result = 0 then Result:= A.HostLine - B.HostLine;
      if Result = 0 then Result:= A.HostCol - B.HostCol;
    end));
  Result:= nil;
  for var R in Rows do Result:= Result + [LowerCase(R.UnitName)];
  FUses.Add(AFileId, Result);
end;

function TInitGraph.ProgramFiles: TArray<Int64>;
begin
  Result:= nil;
  for var Fid in FStore.GetAllFileIds do
    for var R in FStore.GetUnitUsesForFile(Fid) do
      if R.Section = uusProgram then
      begin
        Result:= Result + [Fid];
        Break;
      end;
end;

function TInitGraph.ComputeOrder(AProgram: Int64): TDictionary<string, Integer>;
var
  Visited: TDictionary<string, Boolean>;
  Order  : TDictionary<string, Integer>;

  procedure Visit(const AKey: string);
  var
    Node: TUnitNode;
  begin
    if Visited.ContainsKey(AKey) or not FUnits.TryGetValue(AKey, Node) then Exit;
    Visited.Add(AKey, True);
    for var Dep in UsesOfFile(Node.FileId) do Visit(Dep);
    Order.Add(AKey, Order.Count);
  end;

begin
  Order:= TDictionary<string, Integer>.Create;
  Visited:= TDictionary<string, Boolean>.Create;
  try
    for var Root in UsesOfFile(AProgram) do Visit(Root);
  finally
    Visited.Free;
  end;
  Result:= Order;
end;

procedure TInitGraph.LoadRefsOfFile(AFileId: Int64);
begin
  if FRefsLoaded.ContainsKey(AFileId) then Exit;
  FRefsLoaded.Add(AFileId, True);
  for var R in FStore.GetReferencesFromFile(AFileId) do
  begin
    if R.EnclosingSymbolId = 0 then Continue;
    var L: TList<TReference>;
    if not FRefs.TryGetValue(R.EnclosingSymbolId, L) then
    begin
      L:= TList<TReference>.Create;
      FRefs.Add(R.EnclosingSymbolId, L);
    end;
    L.Add(R);
  end;
end;

function TInitGraph.RefsOf(const ASym: TSymbol): TArray<TReference>;
begin
  LoadRefsOfFile(ASym.FileId);
  var L: TList<TReference>;
  if FRefs.TryGetValue(ASym.Id, L) then Result:= L.ToArray else Result:= nil;
end;

function TInitGraph.EdgesOf(ASymbolId: Int64): TArray<TCallEdge>;
begin
  if FEdges.TryGetValue(ASymbolId, Result) then Exit;
  Result:= nil;
  for var E in FStore.GetCallEdgesFromSymbol(ASymbolId) do
    if (E.TargetSymbolId > 0) and (E.Confidence = CONFIDENCE_CERTAIN) then Result:= Result + [E];
  FEdges.Add(ASymbolId, Result);
end;

function TInitGraph.Symbol(AId: Int64): TSymbol;
begin
  if FSymbols.TryGetValue(AId, Result) then Exit;
  Result:= FStore.GetSymbolById(AId);
  FSymbols.Add(AId, Result);
end;

function TInitGraph.FileDeclares(AFileId: Int64; const ALowerName: string): Boolean;
var
  Names: TDictionary<string, Boolean>;
begin
  if not FOwnNames.TryGetValue(AFileId, Names) then
  begin
    Names:= TDictionary<string, Boolean>.Create;
    FOwnNames.Add(AFileId, Names);
    for var S in FStore.FindSymbolsByFile(FStore.GetFilePath(AFileId)) do
      Names.AddOrSetValue(LowerCase(S.Name), True);
  end;
  Result:= Names.ContainsKey(ALowerName);
end;

function TInitGraph.FileUses(AFileId: Int64; const ALowerUnit: string): Boolean;
begin
  Result:= False;
  for var U in UsesOfFile(AFileId) do
    if U = ALowerUnit then Exit(True);
end;

function TInitGraph.BodyText(const ASym: TSymbol): string;
var
  Lines: TArray<string>;
begin
  if not FLines.TryGetValue(ASym.FileId, Lines) then
  begin
    Lines:= nil;
    var Path: string:= FStore.GetFilePath(ASym.FileId);
    if (Path <> '') and TFile.Exists(Path) then
      try
        Lines:= TFile.ReadAllLines(Path);
      except
        on EInOutError do Lines:= nil;
        on EEncodingError do Lines:= nil;
      end;
    FLines.Add(ASym.FileId, Lines);
  end;
  var First: Integer:= if ASym.ImplStartLine > 0 then ASym.ImplStartLine else ASym.StartLine;
  var Last : Integer:= if ASym.ImplEndLine > 0 then ASym.ImplEndLine else ASym.EndLine;
  Result:= '';
  for var I:= First to Last do
    if (I >= 1) and (I <= Length(Lines)) then Result:= Result + Lines[I - 1] + sLineBreak;
end;

{ --------------------------------------------------------------------------------------------- }

{ The part of a receiver text a variable can be: `G.List.Add` gives G; `G[1].X` and `G(y).X` give G. }
function ReceiverHead(const AReceiver: string): string;
begin
  var Stop: Integer:= Length(AReceiver) + 1;
  for var I:= 1 to Length(AReceiver) do
    if CharInSet(AReceiver[I], ['.', '[', '(', '^']) then
    begin
      Stop:= I;
      Break;
    end;
  Result:= LowerCase(Copy(AReceiver, 1, Stop - 1));
end;

{ The body tests the variable against nil, or asks Assigned of it: it knows the variable may be unset. }
function BodyGuardsVariable(const ABody, AVarName: string): Boolean;
begin
  var N: string:= TRegEx.Escape(AVarName);
  Result:= TRegEx.IsMatch(ABody, '\bAssigned\s*\(\s*' + N + '\s*\)|\b' + N + '\s*(<>|=)\s*nil\b|\bnil\s*(<>|=)\s*' + N + '\b',
    [roIgnoreCase]);
end;

type
  { The state one section gives its unit's variables, and the walk that finds who reaches it. }
  TOrderWalk = class
  private
    FGraph   : TInitGraph;
    FKind    : TSectionKind;
    FState   : TDictionary<string, TArray<TStateVar>>;  { lower var name -> the units whose section sets it }
    FFindings: TList<TLintFinding>;
    FSeen    : TDictionary<string, Boolean>;
    function SectionOf(const ANode: TUnitNode): Int64;
    procedure LoadStateOfUnit(const AKey: string; const ANode: TUnitNode);
    function MentionKey(const AReference: TReference): string;
    function IsVisible(const ASym: TSymbol; const AState: TStateVar; const ALowerName: string): Boolean;
    procedure WalkFrom(const AKey: string; const ANode: TUnitNode; const AProgramName: string;
      AOrder: TDictionary<string, Integer>);
    procedure CheckBody(const AKey: string; const ASym: TSymbol; const AAnchor: TReference; AHasAnchor: Boolean;
      const AProgramName: string; AOrder: TDictionary<string, Integer>);
    procedure AddFinding(const AKey: string; const AState: TStateVar; const AVia: TSymbol; const AAnchor: TReference;
      const AProgramName: string);
  public
    constructor Create(AGraph: TInitGraph; AKind: TSectionKind);
    destructor Destroy; override;
    function Run: TArray<TLintFinding>;
  end;

constructor TOrderWalk.Create(AGraph: TInitGraph; AKind: TSectionKind);
begin
  inherited Create;
  FGraph   := AGraph;
  FKind    := AKind;
  FState   := TDictionary<string, TArray<TStateVar>>.Create;
  FFindings:= TList<TLintFinding>.Create;
  FSeen    := TDictionary<string, Boolean>.Create;
end;

destructor TOrderWalk.Destroy;
begin
  FSeen.Free;
  FFindings.Free;
  FState.Free;
  inherited;
end;

function TOrderWalk.SectionOf(const ANode: TUnitNode): Int64;
begin
  Result:= if FKind = skiInit then ANode.InitId else ANode.FinalId;
end;

{ Which of this unit's own variables its section gives state to: walked from the section through the
  unit's OWN routines only, because `InitUnit;` from a section is the same section by another name.
  Initialization counts a bare write and New(G) / GetMem(G) / SetLength(G); finalization counts any
  mention, since a finalization that names a global is tearing it down. }
procedure TOrderWalk.LoadStateOfUnit(const AKey: string; const ANode: TUnitNode);
begin
  var SecId: Int64:= SectionOf(ANode);
  if SecId = 0 then Exit;
  var Vars: TDictionary<string, string>:= TDictionary<string, string>.Create;
  var Done: TDictionary<Int64, Boolean>:= TDictionary<Int64, Boolean>.Create;
  var Queue: TQueue<Int64>:= TQueue<Int64>.Create;
  var Marked: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
  try
    for var Ch in FGraph.Store.FindAllChildSymbols(ANode.UnitId) do
      if Ch.Kind = skVarDecl then Vars.AddOrSetValue(LowerCase(Ch.Name), Ch.Name);
    Queue.Enqueue(SecId);
    Done.Add(SecId, True);
    while Queue.Count > 0 do
    begin
      var Sym: TSymbol:= FGraph.Symbol(Queue.Dequeue);
      var AllocLines: TDictionary<Integer, Boolean>:= TDictionary<Integer, Boolean>.Create;
      try
        for var R in FGraph.RefsOf(Sym) do
          if (R.Kind = REF_CALL) and (R.ReceiverText = '') and MatchText(R.NameText, ALLOCATING_INTRINSICS) then
            AllocLines.AddOrSetValue(R.StartLine, True);
        for var R in FGraph.RefsOf(Sym) do
        begin
          var Name: string:= if R.ReceiverText = '' then LowerCase(R.NameText) else ReceiverHead(R.ReceiverText);
          var Counts: Boolean:= if FKind = skiInit then (R.ReceiverText = '') and ((R.Kind = REF_WRITE) or AllocLines.ContainsKey(R.StartLine)) else True;
          if Counts and Vars.ContainsKey(Name) then Marked.AddOrSetValue(Name, True);
        end;
      finally
        AllocLines.Free;
      end;
      for var E in FGraph.EdgesOf(Sym.Id) do
        if (not Done.ContainsKey(E.TargetSymbolId)) and (FGraph.Symbol(E.TargetSymbolId).FileId = ANode.FileId) then
        begin
          Done.Add(E.TargetSymbolId, True);
          Queue.Enqueue(E.TargetSymbolId);
        end;
    end;
    for var Name in Marked.Keys do
    begin
      var S: TStateVar:= Default(TStateVar);
      S.UnitKey:= AKey;
      S.VarName:= Vars[Name];
      var List: TArray<TStateVar>;
      if not FState.TryGetValue(Name, List) then List:= nil;
      FState.AddOrSetValue(Name, List + [S]);
    end;
  finally
    Marked.Free;
    Queue.Free;
    Done.Free;
    Vars.Free;
  end;
end;

{ The lower-case name this ref can be a global by, or '': bare, or at the head of a receiver, or qualified
  by a unit name (`uB.GList`). }
function TOrderWalk.MentionKey(const AReference: TReference): string;
begin
  if AReference.ReceiverText = '' then Exit(LowerCase(AReference.NameText));
  var Head: string:= ReceiverHead(AReference.ReceiverText);
  Result:= if FGraph.Units.ContainsKey(Head) then LowerCase(AReference.NameText) else Head;
end;

{ Scope, by the name alone (a read ref carries no symbol id): inside the unit itself a local or a parameter
  of the routine wins, and so does a member of its class; from another unit the file must use the unit and
  declare nothing of that name. }
function TOrderWalk.IsVisible(const ASym: TSymbol; const AState: TStateVar; const ALowerName: string): Boolean;
begin
  var Owner: string;
  if not FGraph.ByFile.TryGetValue(ASym.FileId, Owner) then Owner:= '';
  if Owner <> AState.UnitKey then
    Exit(FGraph.FileUses(ASym.FileId, AState.UnitKey) and not FGraph.FileDeclares(ASym.FileId, ALowerName));
  Result:= True;
  for var Ch in FGraph.Store.FindAllChildSymbols(ASym.Id) do
    if LowerCase(Ch.Name) = ALowerName then Exit(False);
  var Parent: TSymbol:= FGraph.Symbol(ASym.ParentId);
  if Parent.Kind in [skClass, skRecord] then
    for var Ch in FGraph.Store.FindAllChildSymbols(Parent.Id) do
      if LowerCase(Ch.Name) = ALowerName then Exit(False);
end;

procedure TOrderWalk.AddFinding(const AKey: string; const AState: TStateVar; const AVia: TSymbol;
  const AAnchor: TReference; const AProgramName: string);
begin
  var DedupKey: string:= AKey + '|' + AState.UnitKey + '|' + LowerCase(AState.VarName);
  if FSeen.ContainsKey(DedupKey) then Exit;
  FSeen.Add(DedupKey, True);
  var Later: string:= FGraph.Units[AState.UnitKey].Name;
  var Own  : string:= FGraph.Units[AKey].Name;
  var F: TLintFinding:= Default(TLintFinding);
  F.RuleId    := if FKind = skiInit then INIT_ORDER_HAZARD_RULE else FINALIZATION_AFTER_DEPENDENCY_RULE;

  F.Severity  := SEVERITY_WARNING;
  F.FileId    := FGraph.Units[AKey].FileId;
  F.FilePath  := FGraph.Store.GetFilePath(F.FileId);
  F.StartLine := AAnchor.StartLine;
  F.StartCol  := AAnchor.StartCol;
  F.EndLine   := AAnchor.EndLine;
  F.EndCol    := AAnchor.EndCol;
  F.SymbolName:= AState.VarName;
  if FKind = skiInit then
    F.Message:= Format('The initialization of %s reaches %s.%s through %s, but %s initializes after %s in %s: '
      + 'its own initialization has not set the variable yet. Break the uses cycle, or move the call out of the section.',
      [Own, Later, AState.VarName, AVia.QualifiedName, Later, Own, AProgramName])
  else
    F.Message:= Format('The finalization of %s reaches %s.%s through %s, but %s is finalized before %s in %s: '
      + 'its own finalization has already torn the variable down. Break the uses cycle, or test the variable first.',
      [Own, Later, AState.VarName, AVia.QualifiedName, Later, Own, AProgramName]);
  FFindings.Add(F);
end;

procedure TOrderWalk.CheckBody(const AKey: string; const ASym: TSymbol; const AAnchor: TReference; AHasAnchor: Boolean;
  const AProgramName: string; AOrder: TDictionary<string, Integer>);
begin
  var Body: string:= '';
  for var R in FGraph.RefsOf(ASym) do
  begin
    var Name: string:= MentionKey(R);
    var States: TArray<TStateVar>;
    if not FState.TryGetValue(Name, States) then Continue;
    for var S in States do
    begin
      var PosA, PosB: Integer;
      if not (AOrder.TryGetValue(AKey, PosA) and AOrder.TryGetValue(S.UnitKey, PosB) and (PosB > PosA)) then Continue;
      if not IsVisible(ASym, S, Name) then Continue;
      if Body = '' then Body:= FGraph.BodyText(ASym);
      if BodyGuardsVariable(Body, S.VarName) then Continue;
      var WritesIt: Boolean:= False;
      for var W in FGraph.RefsOf(ASym) do
        if (W.Kind = REF_WRITE) and (W.ReceiverText = '') and (LowerCase(W.NameText) = Name) then WritesIt:= True;
      if WritesIt then Continue;
      AddFinding(AKey, S, ASym, if AHasAnchor then AAnchor else R, AProgramName);
    end;
  end;
end;

procedure TOrderWalk.WalkFrom(const AKey: string; const ANode: TUnitNode; const AProgramName: string;
  AOrder: TDictionary<string, Integer>);
begin
  var SecId: Int64:= SectionOf(ANode);
  var Section: TSymbol:= FGraph.Symbol(SecId);
  var ById: TDictionary<Int64, TReference>:= TDictionary<Int64, TReference>.Create;
  var Done: TDictionary<Int64, Boolean>:= TDictionary<Int64, Boolean>.Create;
  var Queue: TQueue<TPair<Int64, TReference>>:= TQueue<TPair<Int64, TReference>>.Create;
  try
    for var R in FGraph.RefsOf(Section) do ById.AddOrSetValue(R.Id, R);
    CheckBody(AKey, Section, Default(TReference), False, AProgramName, AOrder);
    Done.Add(SecId, True);
    for var E in FGraph.EdgesOf(SecId) do
    begin
      var R: TReference;
      if (not Done.ContainsKey(E.TargetSymbolId)) and ById.TryGetValue(E.RefId, R) then
      begin
        Done.Add(E.TargetSymbolId, True);
        Queue.Enqueue(TPair<Int64, TReference>.Create(E.TargetSymbolId, R));
      end;
    end;
    while Queue.Count > 0 do
    begin
      var Item: TPair<Int64, TReference>:= Queue.Dequeue;
      CheckBody(AKey, FGraph.Symbol(Item.Key), Item.Value, True, AProgramName, AOrder);
      for var E in FGraph.EdgesOf(Item.Key) do
        if not Done.ContainsKey(E.TargetSymbolId) then
        begin
          Done.Add(E.TargetSymbolId, True);
          Queue.Enqueue(TPair<Int64, TReference>.Create(E.TargetSymbolId, Item.Value));
        end;
    end;
  finally
    Queue.Free;
    Done.Free;
    ById.Free;
  end;
end;

function TOrderWalk.Run: TArray<TLintFinding>;
begin
  for var Pair in FGraph.Units do LoadStateOfUnit(Pair.Key, Pair.Value);
  if FState.Count > 0 then
    for var Prog in FGraph.ProgramFiles do
    begin
      var ProgName: string:= TPath.GetFileName(FGraph.Store.GetFilePath(Prog));
      var Order: TDictionary<string, Integer>:= FGraph.ComputeOrder(Prog);
      try
        for var Pair in FGraph.Units do
          if (SectionOf(Pair.Value) <> 0) and Order.ContainsKey(Pair.Key) then
            WalkFrom(Pair.Key, Pair.Value, ProgName, Order);
      finally
        Order.Free;
      end;
    end;
  Result:= FFindings.ToArray;
end;

function RunOrderWalk(const AStore: ISymbolStore; AKind: TSectionKind): TArray<TLintFinding>;
begin
  Result:= nil;
  if AStore = nil then Exit;
  var Graph: TInitGraph:= TInitGraph.Create(AStore);
  try
    var Walk: TOrderWalk:= TOrderWalk.Create(Graph, AKind);
    try
      Result:= Walk.Run;
    finally
      Walk.Free;
    end;
  finally
    Graph.Free;
  end;
end;

function CollectInitOrderHazard(const AStore: ISymbolStore): TArray<TLintFinding>;
begin
  Result:= RunOrderWalk(AStore, skiInit);
end;

function CollectFinalizationAfterDependency(const AStore: ISymbolStore): TArray<TLintFinding>;
begin
  Result:= RunOrderWalk(AStore, skiFinal);
end;

end.
