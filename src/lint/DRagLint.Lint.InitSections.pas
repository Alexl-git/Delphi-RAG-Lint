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
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  HEAVY_INITIALIZATION_RULE = 'heavy-initialization';
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  GLOBAL_NEVER_FREED_RULE = 'global-set-in-initialization-never-freed';

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

/// <summary>An initialization section reaches the file system, the registry, the network, a database or
/// a dialog: work that can fail or block before the application has an exception handler or a window,
/// and that every process using the unit pays for at start.</summary>
/// <param name="AStore">The project index; nil yields no findings.</param>
/// <returns>One 'heavy-initialization' hint per section, anchored at the call or reference that starts
/// the first path; the message names each category and a routine that shows it.</returns>
/// <remarks>Not thread-safe. Evidence is positive only: the section's refs and the reached routines'
/// refs against the curated names below, plus symbol_facts.touches (registry, network, transactions)
/// and sql_reads / sql_writes of a reached routine. A path behind an `if` counts, because the index has
/// no branch conditions. TPath alone is not a file access. Certain call edges only.</remarks>
function CollectHeavyInitialization(const AStore: ISymbolStore): TArray<TLintFinding>;

/// <summary>A unit's initialization sets its own global variable to a new object (`G:= TFoo.Create`) and
/// no source that names the variable frees it, so the object lives to process exit and shows as a leak in
/// every leak report.</summary>
/// <param name="AStore">The project index; nil yields no findings.</param>
/// <param name="ALibraryStore">The platform library index, or nil. It proves a library type is a class:
/// a record has a Create too (TRegEx, TFormatSettings). Without it only project classes and a short list
/// of common RTL classes count, and any other type is silent.</param>
/// <returns>One 'global-set-in-initialization-never-freed' hint per variable, at the assignment.</returns>
/// <remarks>Not thread-safe. Counts a section's assignment and one in a routine of the unit the section
/// calls. Silent on an interface-typed variable, a type not proven a class, a factory call (only `.Create` proves a new
/// object), an owner argument, FreeOnTerminate, a variable handed to a container or a Register* call, and
/// any text that frees it: the check is lexical, so a free in a comment also silences it.</remarks>
function CollectGlobalNeverFreed(const AStore: ISymbolStore; const ALibraryStore: ISymbolStore = nil): TArray<TLintFinding>;

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
  SEVERITY_HINT = 'hint';
  CREATE_STATEMENT_LINES = 3;
  KNOWN_RTL_CLASSES: array[0..16] of string = ('TStringList', 'TList', 'TObjectList', 'TThreadList', 'TInterfaceList', 'TDictionary',
    'TObjectDictionary', 'TQueue', 'TStack', 'TMemoryStream', 'TFileStream', 'TCriticalSection', 'TEvent', 'TComponent',
    'TBitmap', 'TIniFile', 'TMemIniFile');
  NOT_AN_OWNER: array[0..2] of string = ('nil', 'True', 'False');
  COMMENT_LINE = '//';
  COMMENT_PAREN_OPEN = '(*';
  COMMENT_PAREN_CLOSE = '*)';
  ASSIGN_TOKEN = ':=';
  CLOSURE_OPENERS: array[0..3] of string = ('begin', 'case', 'try', 'asm');
  ROUTINE_KEYWORDS: array[0..1] of string = ('function', 'procedure');
  CLOSURE_PREDECESSORS: array[0..3] of string = ('(', ',', '[', ASSIGN_TOKEN);
  REF_MEMBER = 'member-access';
  TOUCH_SEPARATOR = '|';
  CATEGORY_FILE = 'file system';
  CATEGORY_REGISTRY = 'registry';
  CATEGORY_NETWORK = 'network';
  CATEGORY_DATABASE = 'database';
  CATEGORY_DIALOG = 'dialog';
  HEAVY_CATEGORY_ORDER: array[0..4] of string = (CATEGORY_DATABASE, CATEGORY_NETWORK, CATEGORY_FILE, CATEGORY_REGISTRY, CATEGORY_DIALOG);
  HEAVY_TYPES_FILE: array[0..5] of string = ('TFile', 'TDirectory', 'TStreamWriter', 'TFileStream', 'TIniFile', 'TMemIniFile');
  HEAVY_TYPES_REGISTRY: array[0..1] of string = ('TRegistry', 'TRegistryIniFile');
  HEAVY_TYPES_NETWORK: array[0..3] of string = ('THTTPClient', 'TIdHTTP', 'TNetHTTPClient', 'TIdTCPClient');
  HEAVY_BARE_FILE: array[0..3] of string = ('AssignFile', 'Rewrite', 'Reset', 'FindFirst');
  HEAVY_MEMBER_FILE: array[0..1] of string = ('LoadFromFile', 'SaveToFile');
  HEAVY_MEMBER_DB: array[0..3] of string = ('ExecSQL', 'StartTransaction', 'Commit', 'Rollback');
  HEAVY_BARE_DIALOG: array[0..3] of string = ('ShowMessage', 'MessageDlg', 'MessageBox', 'InputBox');

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

  { A span of source, 1-based lines. }
  TLineSpan = record
    FromLine, FromCol, ToLine, ToCol: Integer;
  end;

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
    FLiveRefs  : TDictionary<Int64, TArray<TReference>>;
    FClosureRef: TDictionary<Int64, Boolean>;
    procedure LoadUnits;
    function UsesOfFile(AFileId: Int64): TArray<string>;
    procedure LoadRefsOfFile(AFileId: Int64);
    function LinesOf(AFileId: Int64): TArray<string>;
  public
    constructor Create(const AStore: ISymbolStore);
    destructor Destroy; override;
    /// <summary>The files whose uses clause is a program's.</summary>
    function ProgramFiles: TArray<Int64>;
    /// <summary>Lower-case unit name -> position in the order AProgram initializes its units.</summary>
    /// <remarks>The caller owns the result.</remarks>
    function ComputeOrder(AProgram: Int64): TDictionary<string, Integer>;
    /// <summary>The refs enclosed by ASym that run when ASym runs: a reference inside an anonymous
    /// method's body is left out, since passing a closure does not call it.</summary>
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
    /// <summary>The whole source of AFileId; '' when it cannot be read.</summary>
    function FileText(AFileId: Int64): string;
    /// <summary>ACount lines of AFileId from the 1-based ALine, joined.</summary>
    function LineText(AFileId: Int64; ALine, ACount: Integer): string;
    /// <summary>Every routine reachable from ASectionId by certain call edges, breadth first, the section
    /// itself first (its anchor is empty); each with the ref in the section that starts its path.</summary>
    function Reach(ASectionId: Int64): TArray<TPair<TSymbol, TReference>>;
    property Units: TDictionary<string, TUnitNode> read FUnits;
    property ByFile: TDictionary<Int64, string> read FByFile;
    property Store: ISymbolStore read FStore;
  end;

function BodyFirstLine(const ASym: TSymbol): Integer;
begin
  Result:= if ASym.ImplStartLine > 0 then ASym.ImplStartLine else ASym.StartLine;
end;

{ The anonymous method bodies in a routine's text. Lexical, because the index keeps no symbol for one: a
  `function` or `procedure` keyword right after `(`, `,`, `[` or `:=` is an expression (`F: function` and
  `T = function` are types, and a named local routine is followed by its name after any other token), and
  its body runs to the `end` that balances the first `begin`. Comments and strings are skipped. }
function ClosureSpans(const AText: string; AFirstLine: Integer): TArray<TLineSpan>;
var
  I, Line, LineStart, Depth: Integer;
  Prev: string;
  InClosure: Boolean;
  Span: TLineSpan;

  function ColHere: Integer;
  begin
    Result:= I - LineStart;
  end;

  procedure SkipUntil(const AStop: string);
  begin
    while (I <= Length(AText)) and (Copy(AText, I, Length(AStop)) <> AStop) do
    begin
      if AText[I] = #10 then
      begin
        Inc(Line);
        LineStart:= I + 1;
      end;
      Inc(I);
    end;
    Inc(I, Length(AStop));
  end;

begin
  Result:= nil;
  I:= 1;
  Line:= AFirstLine;
  LineStart:= 1;
  Depth:= 0;
  Prev:= '';
  InClosure:= False;
  Span:= Default(TLineSpan);
  while I <= Length(AText) do
  begin
    var C: Char:= AText[I];
    if C = #10 then
    begin
      Inc(Line);
      LineStart:= I + 1;
      Inc(I);
    end
    else if CharInSet(C, [#9, #13, ' ']) then Inc(I)
    else if (C = '/') and (Copy(AText, I, Length(COMMENT_LINE)) = COMMENT_LINE) then
    begin
      while (I <= Length(AText)) and (AText[I] <> #10) do Inc(I);
    end
    else if C = '{' then SkipUntil('}')
    else if (C = '(') and (Copy(AText, I, Length(COMMENT_PAREN_OPEN)) = COMMENT_PAREN_OPEN) then SkipUntil(COMMENT_PAREN_CLOSE)
    else if C = '''' then
    begin
      Inc(I);
      while (I <= Length(AText)) and not CharInSet(AText[I], ['''', #10]) do Inc(I);
      Inc(I);
      Prev:= 'literal';
    end
    else if CharInSet(C, ['A'..'Z', 'a'..'z', '_']) then
    begin
      var From: Integer:= I;
      while (I <= Length(AText)) and CharInSet(AText[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(I);
      var Word: string:= LowerCase(Copy(AText, From, I - From));
      if InClosure then
      begin
        if MatchStr(Word, CLOSURE_OPENERS) then Inc(Depth)
        else if (Word = 'end') and (Depth > 0) then
        begin
          Dec(Depth);
          if Depth = 0 then
          begin
            Span.ToLine:= Line;
            Span.ToCol:= ColHere;
            Result:= Result + [Span];
            InClosure:= False;
          end;
        end;
      end
      else if MatchStr(Word, ROUTINE_KEYWORDS) and MatchStr(Prev, CLOSURE_PREDECESSORS) then
      begin
        InClosure:= True;
        Depth:= 0;
        Span.FromLine:= Line;
        Span.FromCol:= From - LineStart;
      end;
      Prev:= Word;
    end
    else
    begin
      Prev:= if Copy(AText, I, Length(ASSIGN_TOKEN)) = ASSIGN_TOKEN then ASSIGN_TOKEN else string(C);
      Inc(I, Length(Prev));
    end;
  end;
end;

function IsInsideSpan(const ASpans: TArray<TLineSpan>; ALine, ACol: Integer): Boolean;
begin
  Result:= False;
  for var S in ASpans do
    if ((ALine > S.FromLine) or ((ALine = S.FromLine) and (ACol > S.FromCol)))
      and ((ALine < S.ToLine) or ((ALine = S.ToLine) and (ACol <= S.ToCol))) then Exit(True);
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
  FLiveRefs  := TDictionary<Int64, TArray<TReference>>.Create;
  FClosureRef:= TDictionary<Int64, Boolean>.Create;
  LoadUnits;
end;

destructor TInitGraph.Destroy;
begin
  FClosureRef.Free;
  FLiveRefs.Free;
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
  if FLiveRefs.TryGetValue(ASym.Id, Result) then Exit;
  LoadRefsOfFile(ASym.FileId);
  var L: TList<TReference>;
  Result:= nil;
  if FRefs.TryGetValue(ASym.Id, L) then
  begin
    var Closures: TArray<TLineSpan>:= ClosureSpans(BodyText(ASym), BodyFirstLine(ASym));
    for var R in L do
      if IsInsideSpan(Closures, R.StartLine, R.StartCol) then FClosureRef.AddOrSetValue(R.Id, True)
      else Result:= Result + [R];
  end;
  FLiveRefs.Add(ASym.Id, Result);
end;

function TInitGraph.EdgesOf(ASymbolId: Int64): TArray<TCallEdge>;
begin
  if FEdges.TryGetValue(ASymbolId, Result) then Exit;
  RefsOf(Symbol(ASymbolId));
  Result:= nil;
  for var E in FStore.GetCallEdgesFromSymbol(ASymbolId) do
    if (E.TargetSymbolId > 0) and (E.Confidence = CONFIDENCE_CERTAIN) and not FClosureRef.ContainsKey(E.RefId) then
      Result:= Result + [E];
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

function TInitGraph.LinesOf(AFileId: Int64): TArray<string>;
begin
  if FLines.TryGetValue(AFileId, Result) then Exit;
  Result:= nil;
  var Path: string:= FStore.GetFilePath(AFileId);
  if (Path <> '') and TFile.Exists(Path) then
    try
      Result:= TFile.ReadAllLines(Path);
    except
      on EInOutError do Result:= nil;
      on EEncodingError do Result:= nil;
    end;
  FLines.Add(AFileId, Result);
end;

function TInitGraph.LineText(AFileId: Int64; ALine, ACount: Integer): string;
begin
  var Lines: TArray<string>:= LinesOf(AFileId);
  Result:= '';
  for var I:= ALine to ALine + ACount - 1 do
    if (I >= 1) and (I <= Length(Lines)) then Result:= Result + Lines[I - 1] + sLineBreak;
end;

function TInitGraph.FileText(AFileId: Int64): string;
begin
  Result:= string.Join(sLineBreak, LinesOf(AFileId));
end;

function TInitGraph.BodyText(const ASym: TSymbol): string;
begin
  var First: Integer:= BodyFirstLine(ASym);
  var Last : Integer:= if ASym.ImplEndLine > 0 then ASym.ImplEndLine else ASym.EndLine;
  Result:= LineText(ASym.FileId, First, Last - First + 1);
end;

function TInitGraph.Reach(ASectionId: Int64): TArray<TPair<TSymbol, TReference>>;
begin
  var Section: TSymbol:= Symbol(ASectionId);
  var ById: TDictionary<Int64, TReference>:= TDictionary<Int64, TReference>.Create;
  var Done: TDictionary<Int64, Boolean>:= TDictionary<Int64, Boolean>.Create;
  var Items: TList<TPair<TSymbol, TReference>>:= TList<TPair<TSymbol, TReference>>.Create;
  try
    for var R in RefsOf(Section) do ById.AddOrSetValue(R.Id, R);
    Done.Add(ASectionId, True);
    Items.Add(TPair<TSymbol, TReference>.Create(Section, Default(TReference)));
    var Head: Integer:= 0;
    while Head < Items.Count do
    begin
      var Item: TPair<TSymbol, TReference>:= Items[Head];
      Inc(Head);
      for var E in EdgesOf(Item.Key.Id) do
      begin
        var Anchor: TReference:= Item.Value;
        if Item.Key.Id = ASectionId then
          if not ById.TryGetValue(E.RefId, Anchor) then Continue;
        if not Done.ContainsKey(E.TargetSymbolId) then
        begin
          Done.Add(E.TargetSymbolId, True);
          Items.Add(TPair<TSymbol, TReference>.Create(Symbol(E.TargetSymbolId), Anchor));
        end;
      end;
    end;
    Result:= Items.ToArray;
  finally
    Items.Free;
    Done.Free;
    ById.Free;
  end;
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
  var IsSection: Boolean:= True;
  for var Item in FGraph.Reach(SectionOf(ANode)) do
  begin
    CheckBody(AKey, Item.Key, Item.Value, not IsSection, AProgramName, AOrder);
    IsSection:= False;
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

{ What one ref shows, or '' for nothing. TYPE names count anywhere, as a receiver or as the ref itself;
  a member name only as a member, a bare routine only with no receiver: `Reset` and `Commit` are ordinary
  names. TPath is not here: it computes strings. }
function HeavyCategoryOfRef(const AReference: TReference): string;
begin
  Result:= '';
  var Head: string:= ReceiverHead(AReference.ReceiverText);
  var Name: string:= AReference.NameText;
  if MatchText(Head, HEAVY_TYPES_FILE) or MatchText(Name, HEAVY_TYPES_FILE) then Exit(CATEGORY_FILE);
  if MatchText(Head, HEAVY_TYPES_REGISTRY) or MatchText(Name, HEAVY_TYPES_REGISTRY) then Exit(CATEGORY_REGISTRY);
  if MatchText(Head, HEAVY_TYPES_NETWORK) or MatchText(Name, HEAVY_TYPES_NETWORK) then Exit(CATEGORY_NETWORK);
  if AReference.Kind <> REF_CALL then
    if AReference.Kind <> REF_MEMBER then Exit;
  if AReference.ReceiverText = '' then
  begin
    if MatchText(Name, HEAVY_BARE_FILE) then Exit(CATEGORY_FILE);
    if MatchText(Name, HEAVY_BARE_DIALOG) then Exit(CATEGORY_DIALOG);
  end
  else
  begin
    if MatchText(Name, HEAVY_MEMBER_FILE) then Exit(CATEGORY_FILE);
    if MatchText(Name, HEAVY_MEMBER_DB) then Exit(CATEGORY_DATABASE);
    if MatchText(Name, HEAVY_BARE_DIALOG) then Exit(CATEGORY_DIALOG);
  end;
end;

function CollectHeavyInitialization(const AStore: ISymbolStore): TArray<TLintFinding>;
var
  Witness: TDictionary<string, string>;
  Anchor : TReference;

  procedure Note(const ACategory: string; const AVia: TSymbol; const AAt: TReference);
  begin
    if Witness.ContainsKey(ACategory) then Exit;
    Witness.Add(ACategory, AVia.QualifiedName);
    if Anchor.StartLine = 0 then Anchor:= AAt;
  end;

begin
  Result:= nil;
  if AStore = nil then Exit;
  var Graph: TInitGraph:= TInitGraph.Create(AStore);
  var Findings: TList<TLintFinding>:= TList<TLintFinding>.Create;
  Witness:= TDictionary<string, string>.Create;
  try
    for var Pair in Graph.Units do
    begin
      if Pair.Value.InitId = 0 then Continue;
      Witness.Clear;
      Anchor:= Default(TReference);
      var IsSection: Boolean:= True;
      for var Item in Graph.Reach(Pair.Value.InitId) do
      begin
        for var R in Graph.RefsOf(Item.Key) do
        begin
          var Category: string:= HeavyCategoryOfRef(R);
          if Category = '' then Continue;
          if IsSection then Note(Category, Item.Key, R) else Note(Category, Item.Key, Item.Value);
        end;
        if not IsSection then
        begin
          var Facts: TSymbolFacts:= AStore.GetSymbolFacts(Item.Key.Id);
          var Bar: Integer:= Pos(TOUCH_SEPARATOR, Facts.Touches);
          if (Facts.SqlReads <> '') or (Facts.SqlWrites <> '') or ((Bar > 0) and (Bar < Length(Facts.Touches))) then
            Note(CATEGORY_DATABASE, Item.Key, Item.Value);
          if ContainsText(Facts.Touches, CATEGORY_REGISTRY) then Note(CATEGORY_REGISTRY, Item.Key, Item.Value);
          if ContainsText(Facts.Touches, CATEGORY_NETWORK) then Note(CATEGORY_NETWORK, Item.Key, Item.Value);
        end;
        IsSection:= False;
      end;
      if Witness.Count = 0 then Continue;

      var Parts: TArray<string>:= nil;
      for var C in HEAVY_CATEGORY_ORDER do
      begin
        var Via: string;
        if Witness.TryGetValue(C, Via) then Parts:= Parts + [Format('%s (%s)', [C, Via])];
      end;
      var F: TLintFinding:= Default(TLintFinding);
      F.RuleId    := HEAVY_INITIALIZATION_RULE;
      F.Severity  := SEVERITY_HINT;
      F.FileId    := Pair.Value.FileId;
      F.FilePath  := AStore.GetFilePath(F.FileId);
      F.StartLine := Anchor.StartLine;
      F.StartCol  := Anchor.StartCol;
      F.EndLine   := Anchor.EndLine;
      F.EndCol    := Anchor.EndCol;
      F.SymbolName:= Pair.Value.Name;
      F.Message   := Format('The initialization of %s reaches %s: this runs before the application has an exception '
        + 'handler or a window, in every process that links the unit. Move it to an explicit start-up call.',
        [Pair.Value.Name, string.Join(', ', Parts)]);
      Findings.Add(F);
    end;
    Result:= Findings.ToArray;
  finally
    Witness.Free;
    Findings.Free;
    Graph.Free;
  end;
end;

{ Does anything prove this name is a class? A Create call proves nothing by itself: TRegEx.Create is a
  record's (12 false findings of 12 on the drag-lint index before this test). The stores answer for what
  they hold; KNOWN_RTL_CLASSES answers for the commonest classes when no library index is loaded. An
  unknown name is silent. }
function IsProvenClass(const AStore, ALibraryStore: ISymbolStore; const AType: string): Boolean;
begin
  if MatchText(AType, KNOWN_RTL_CLASSES) then Exit(True);
  for var S in AStore.FindSymbolsByExactName(AType) do
    if S.Kind = skClass then Exit(True);
  Result:= False;
  if ALibraryStore <> nil then
    for var S in ALibraryStore.FindSymbolsByExactName(AType) do
      if S.Kind = skClass then Exit(True);
end;

{ A declared type that holds a reference count, not an object reference. `IFoo` with no row in either store
  counts too: an unknown class is rarely spelled I + capital. }
function IsInterfaceTyped(const AStore, ALibraryStore: ISymbolStore; const ASignature: string): Boolean;
begin
  var T: string:= Trim(ASignature);
  if (Length(T) > 1) and (T[1] = 'I') and CharInSet(T[2], ['A'..'Z']) then Exit(True);
  for var S in AStore.FindSymbolsByExactName(T) do
    if S.Kind = skInterface then Exit(True);
  Result:= False;
  if ALibraryStore <> nil then
    for var S in ALibraryStore.FindSymbolsByExactName(T) do
      if S.Kind = skInterface then Exit(True);
end;

function TextFreesVariable(const AText, AVarName: string): Boolean;
begin
  var N: string:= TRegEx.Escape(AVarName);
  Result:= TRegEx.IsMatch(AText,
    '\b' + N + '\s*\.\s*(Free|Destroy|DisposeOf|Release|FreeOnTerminate)\b'    { a direct free }
    + '|\bFree\w*\s*\(\s*' + N + '\b'                                          { FreeAndNil(G), FreeObject(G) }
    + '|\b(Add|AddObject|Insert|Push|Enqueue|Register\w*)\s*\([^;]*\b' + N + '\b', { handed to an owner }
    [roIgnoreCase]);
end;

function CollectGlobalNeverFreed(const AStore, ALibraryStore: ISymbolStore): TArray<TLintFinding>;
begin
  Result:= nil;
  if AStore = nil then Exit;
  var Graph: TInitGraph:= TInitGraph.Create(AStore);
  var Findings: TList<TLintFinding>:= TList<TLintFinding>.Create;
  var AllFiles: TArray<Int64>:= AStore.GetAllFileIds;
  var Seen: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
  try
    for var Pair in Graph.Units do
    begin
      if Pair.Value.InitId = 0 then Continue;
      var Vars: TDictionary<string, TSymbol>:= TDictionary<string, TSymbol>.Create;
      try
        for var Ch in AStore.FindAllChildSymbols(Pair.Value.UnitId) do
          if Ch.Kind = skVarDecl then Vars.AddOrSetValue(LowerCase(Ch.Name), Ch);
        for var Item in Graph.Reach(Pair.Value.InitId) do
        begin
          if Item.Key.FileId <> Pair.Value.FileId then Continue;
          for var R in Graph.RefsOf(Item.Key) do
          begin
            var Key: string:= LowerCase(R.NameText);
            var V: TSymbol;
            if (R.Kind <> REF_WRITE) or (R.ReceiverText <> '') or not Vars.TryGetValue(Key, V) then Continue;
            if Seen.ContainsKey(Pair.Key + '|' + Key) then Continue;
            var Match: TMatch:= TRegEx.Match(Graph.LineText(Item.Key.FileId, R.StartLine, CREATE_STATEMENT_LINES),
              '\b' + TRegEx.Escape(R.NameText) + '\s*:=\s*([A-Za-z_][\w.]*(?:<[^>]*>)?)\s*\.\s*Create\b\s*(?:\(\s*([^,)]*))?',
              [roIgnoreCase]);
            if not Match.Success then Continue;
            var TypeName: string:= Match.Groups[1].Value;
            var Generic: Integer:= Pos('<', TypeName);
            if Generic > 0 then TypeName:= Copy(TypeName, 1, Generic - 1);
            var Arg: string:= if Match.Groups.Count > 2 then Trim(Match.Groups[2].Value) else '';
            if (not IsProvenClass(AStore, ALibraryStore, TypeName)) or IsInterfaceTyped(AStore, ALibraryStore, V.Signature) then Continue;
            { An owner argument: an identifier that is not a nil or a boolean. A literal is a plain parameter. }
            if TRegEx.IsMatch(Arg, '^[A-Za-z_]') and not MatchText(Arg, NOT_AN_OWNER) then Continue;
            Seen.Add(Pair.Key + '|' + Key, True);
            var Freed: Boolean:= False;
            var Named: TDictionary<Int64, Boolean>:= TDictionary<Int64, Boolean>.Create;
            try
              Named.AddOrSetValue(Pair.Value.FileId, True);
              for var Other in AStore.FindRefsNamingInFiles(AllFiles, [Key]) do Named.AddOrSetValue(Other.FileId, True);
              for var Fid in Named.Keys do
                if TextFreesVariable(Graph.FileText(Fid), V.Name) then
                begin
                  Freed:= True;
                  Break;
                end;
            finally
              Named.Free;
            end;
            if Freed then Continue;
            var F: TLintFinding:= Default(TLintFinding);
            F.RuleId    := GLOBAL_NEVER_FREED_RULE;
            F.Severity  := SEVERITY_HINT;
            F.FileId    := Pair.Value.FileId;
            F.FilePath  := AStore.GetFilePath(F.FileId);
            F.StartLine := R.StartLine;
            F.StartCol  := R.StartCol;
            F.EndLine   := R.EndLine;
            F.EndCol    := R.EndCol;
            F.SymbolName:= V.Name;
            F.Message   := Format('%s is set to a new %s by the initialization of %s, and no source that names it frees it: '
              + 'the object lives to process exit and shows in every leak report. Free it in the unit''s finalization.',
              [V.Name, TypeName, Pair.Value.Name]);
            Findings.Add(F);
          end;
        end;
      finally
        Vars.Free;
      end;
    end;
    Result:= Findings.ToArray;
  finally
    Seen.Free;
    Findings.Free;
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
