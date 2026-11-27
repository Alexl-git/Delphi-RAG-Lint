unit DRagLint.V156.FACTA.Support;

{ Wave v156 lane FA-1 -- helpers of DRagLint.V156.FACTA (noreturn-contract, G-13).
    TNoReturnFacts -- the stored noreturn fact (symbol_extras.noreturn, 1.56 B1) as the flow graph
                      asks for it: "does this call statement never return". It is the oracle of
                      TCfgBuilder.Build; any caller of the builder that has the index may use it.
    TNoReturnRun   -- one run of the rule over one parsed unit:
                      code after a call to a noreturn routine (warning), and a routine that never
                      returns on any path and is not declared noreturn (hint).
  What the rule leaves to the compiler (measured with dcc64 37.0 on
  tests\fixtures\v156-fa1\compiler-probe): a noreturn routine that can return is W1080 in every
  shape tried; an override or an interface implementation that drops the directive is E2037 / E2211.
  A question the source and the index do not answer completely is answered "no finding". }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Core.Model  // dl:ok uses-global-census@64a5 -- the named constants are the whole contract this unit draws; the unit pair travels together
  , DRagLint.Core.Interfaces
  , DRagLint.V151.Api
  , DRagLint.Analysis.Cfg
  ;

const
  /// <summary>Rule id of G-13.</summary>
  RULE_NORETURN_CONTRACT = 'noreturn-contract';

type
  /// <summary>The stored noreturn fact of the index, asked per call statement of one file.</summary>
  /// <remarks>Create once per parsed file, hand <see cref="Oracle"/> to TCfgBuilder.Build, Free
  /// after the last graph is built: the oracle holds this object, it does not own it. Not
  /// thread-safe. Answers False whenever the callee is not known for certain: with no store, for a
  /// callee the index did not resolve whose name is not exclusively a noreturn routine, and for
  /// anything but a plain or dotted call statement.</remarks>
  TNoReturnFacts = class
  strict private
    FStore   : ISymbolStore;
    FLibStore: ISymbolStore;
    FFileId  : Int64;
    FPath    : string;
    FSrc     : TBytes;
    FEdges   : TDictionary<string, Int64>;
    FById    : TDictionary<Int64, Boolean>;
    FByName  : TDictionary<string, Boolean>;
    FHits    : TList<TTSNode>;
    procedure LoadEdges;
    function Callee(const AStatement: TTSNode; out AName: TTSNode; out AOwner: string): Boolean;
    function SymbolNeverReturns(AId: Int64): Boolean;
    function NameNeverReturns(const AName: string): Boolean;
    procedure AddHit(const AStatement: TTSNode);
  public
    /// <summary>Binds the facts to one file.</summary>
    /// <param name="AStore">Project index; nil = every answer is False.</param>
    /// <param name="ALibStore">Platform library index, or nil.</param>
    /// <param name="AFileId">files.id of APath in AStore; 0 = the file is not indexed (callees are then matched by name only).</param>
    /// <param name="APath">The .pas the nodes come from (for character columns).</param>
    /// <param name="ASrc">The parsed bytes of APath (TParsedFile.Src).</param>
    constructor Create(const AStore, ALibStore: ISymbolStore; AFileId: Int64; const APath: string; const ASrc: TBytes);
    destructor Destroy; override;
    /// <summary>True when the call statement never returns to its caller.</summary>
    /// <param name="AStatement">A statement / exprCall / exprDot / identifier node in statement position.</param>
    /// <returns>True when the exact callee (a certain call edge) carries the noreturn fact, or --
    /// with no certain edge, for a bare or RTL-unit-qualified name -- when every symbol of that name
    /// in both stores is a routine carrying it. A True answer is also recorded in <see cref="Hits"/>.</returns>
    function CallNeverReturns(const AStatement: TTSNode): Boolean;
    /// <summary>CallNeverReturns as the oracle TCfgBuilder.Build takes.</summary>
    /// <returns>A reference that is valid until this object is freed.</returns>
    function Oracle: TCfgNoReturnCall;
    /// <summary>The callee of a call statement as written, '' when it is not a plain or dotted call.</summary>
    /// <param name="AStatement">As for CallNeverReturns.</param>
    /// <returns>The last name of the callee, e.g. 'Fail' for <c>UOther.Fail('x');</c>.</returns>
    function CalleeText(const AStatement: TTSNode): string;
    /// <summary>Every statement CallNeverReturns answered True for since the list was last cleared, once each, in asking order.</summary>
    /// <remarks>Owned by this object; the caller may Clear it between routines.</remarks>
    property Hits: TList<TTSNode> read FHits;
  end;

  /// <summary>One run of noreturn-contract over one parsed unit.</summary>
  /// <remarks>Create, Check, read Findings, Free. Not thread-safe. Silent without a project index.</remarks>
  TNoReturnRun = class  // dl:ok high-response@7dba -- REVIEWED 2026-11-26 v156 FA-1: one walker per file run; its two checks share the tree helpers and the facts
  strict private
    FCtx     : TV151FileCtx;
    FSrc     : TBytes;
    FRoot    : TTSNode;
    FParsed  : Boolean;
    FFacts   : TNoReturnFacts;
    FFindings: TList<TLintFinding>;
    FDirectiveKnown: Integer;
    procedure Emit(const ASeverity, AMessage, ASymbolName: string; const ANode: TTSNode);
    function Text(const ANode: TTSNode): string;
    function NextStatement(const AStatement: TTSNode; out ANext: TTSNode): Boolean;
    function KeepsCompilerQuiet(const ANext: TTSNode; const ARoutineName: string): Boolean;
    function NeverReturns(ACfg: TCfg): Boolean;
    function CompilerKnowsDirective: Boolean;
    function HasInterfaces(AClassId: Int64): Boolean;
    function MayBeMarked(const ARoutine: TTSNode; out AName: TTSNode): Boolean;
    procedure CheckRoutine(const ARoutine: TTSNode);
  public
    /// <summary>Parses nothing itself: takes the tree of ACtx.Path from the parse cache.</summary>
    /// <param name="ACtx">The file being linted.</param>
    constructor Create(const ACtx: TV151FileCtx);
    destructor Destroy; override;
    /// <summary>Checks every routine of the unit.</summary>
    procedure Check;
    /// <summary>The findings of Check.</summary>
    /// <returns>Empty when there are none.</returns>
    function Findings: TArray<TLintFinding>;
  end;

implementation

uses
  System.StrUtils
  , FireDAC.Comp.Client
  , FireDAC.Stan.Param
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Storage.SQLite
  ;

const
  SEVERITY_WARNING = 'warning';
  SEVERITY_HINT = 'hint';
  NODE_STATEMENT = 'statement';
  NODE_CALL = 'exprCall';
  NODE_DOT = 'exprDot';
  NODE_IDENTIFIER = 'identifier';
  NODE_ASSIGNMENT = 'assignment';
  NODE_COMMENT = 'comment';
  NODE_PREFIX_PP = 'pp';
  LIST_NODES: array[0..1] of string = ('block', 'statements');
  FIELD_ENTITY = 'entity';
  FIELD_LHS = 'lhs';
  FIELD_RHS = 'rhs';
  FIELD_HEADER = 'header';
  FIELD_NAME = 'name';
  RESULT_NAME = 'result';
  EXIT_NAME = 'exit';
  { a call qualified by one of these is the RTL routine of that name }
  RTL_OWNERS: array[0..3] of string = ('system', 'sysutils', 'system.sysutils', 'winapi.windows');
  { a routine with one of these directives has a signature somebody else dictates }
  FIXED_DIRECTIVES: array[0..5] of string = ('virtual', 'dynamic', 'override', 'abstract', 'message', 'external');
  NO_RETURN_DIRECTIVE = 'noreturn';
  { the RTL routine whose declaration tells whether the indexed compiler has the directive }
  PROBE_ROUTINE = 'Abort';
  EVENT_PARAM = '(sender:';
  KNOWN_NO = 1;
  KNOWN_YES = 2;
  EDGE_SQL = 'SELECT r.start_line, r.start_col, e.target_symbol_id FROM refs r JOIN call_edges e ON e.ref_id = r.id ' +
    'AND e.confidence = ''certain'' WHERE r.file_id = :f';
  MSG_AFTER = 'Code after the call to "%s" is never reached: "%s" is a noreturn routine';
  MSG_UNMARKED = 'Routine "%s" never returns (every path ends in raise, Halt, Abort or a call to a noreturn routine) ' +
    'but is not declared noreturn; add the noreturn directive to its declaration';

function NodeText(const ANode: TTSNode; const ASrc: TBytes): string;
var
  First, Last: Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  First:= Integer(ANode.StartByte);
  Last := Integer(ANode.EndByte);
  if (Last > First) and (Last <= Length(ASrc)) then Result:= TEncoding.UTF8.GetString(ASrc, First, Last - First);
end;

{ Lower case without any blank. }
function FlatText(const AText: string): string;
begin
  Result:= string.Join('', LowerCase(AText).Split([' ', #9, #10, #13], TStringSplitOptions.ExcludeEmpty));
end;

{ TFoo<T>.Bar -> Bar }
function LastName(const AName: string): string;
begin
  Result:= Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

function IsInterfaceName(const AName: string): Boolean;
begin
  Result:= (Length(AName) > 1) and (AName[1] = 'I') and CharInSet(AName[2], ['A'..'Z']);
end;

function SiteKey(ALine, ACol: Integer): string;
begin
  Result:= Format('%d:%d', [ALine, ACol]);
end;

{ A named node of a statement list that is not a statement: a comment, a directive, or a keyword
  such as the list's own kEnd. }
function IsNoCode(const ANodeType: string): Boolean;
begin
  Result:= (ANodeType = NODE_COMMENT) or StartsStr(NODE_PREFIX_PP, ANodeType) or
    ((Length(ANodeType) > 1) and (ANodeType[1] = 'k') and CharInSet(ANodeType[2], ['A'..'Z']));
end;

{ One of the directives is one somebody else dictates. }
function AnyFixed(const ADirectives: TArray<string>): Boolean;
var
  Directive: string;
begin
  Result:= False;
  for Directive in ADirectives do
    Result:= Result or MatchStr(Directive, FIXED_DIRECTIVES);
end;

{ The statement itself, without the wrapper that carries its semicolon. }
function Unwrapped(const AStatement: TTSNode): TTSNode;
begin
  Result:= AStatement;
  if (Result.NodeType = NODE_STATEMENT) and (Result.NamedChildCount > 0) then Result:= Result.NamedChild(0);
end;

{ TNoReturnFacts }

constructor TNoReturnFacts.Create(const AStore, ALibStore: ISymbolStore; AFileId: Int64; const APath: string; const ASrc: TBytes);
begin
  inherited Create;
  FStore   := AStore;
  FLibStore:= ALibStore;
  FFileId  := if AStore <> nil then AFileId else 0;
  FPath    := APath;
  FSrc     := ASrc;
  FById    := TDictionary<Int64, Boolean>.Create;
  FByName  := TDictionary<string, Boolean>.Create;
  FHits    := TList<TTSNode>.Create;
end;

destructor TNoReturnFacts.Destroy;
begin
  FHits.Free;
  FByName.Free;
  FById.Free;
  FEdges.Free;
  inherited;
end;

{ The certain call edges of the file, read once: call site -> callee. }
procedure TNoReturnFacts.LoadEdges;
var
  Query: TFDQuery;
begin
  if FEdges <> nil then Exit;
  FEdges:= TDictionary<string, Int64>.Create;
  if (FStore is not TSQLiteSymbolStore) or (FFileId = 0) then Exit;
  Query:= TFDQuery.Create(nil);
  try
    Query.Connection:= (FStore as TSQLiteSymbolStore).GetConnection;
    Query.SQL.Text  := EDGE_SQL;
    Query.ParamByName('f').AsLargeInt:= FFileId;
    Query.Open;
    while not Query.Eof do
    begin
      FEdges.AddOrSetValue(SiteKey(Query.Fields[0].AsInteger, Query.Fields[1].AsInteger), Query.Fields[2].AsLargeInt);
      Query.Next;
    end;
  finally
    Query.Free;
  end;
end;

{ The name node of the callee and, for a dotted call, what stands before the last dot. }
function TNoReturnFacts.Callee(const AStatement: TTSNode; out AName: TTSNode; out AOwner: string): Boolean;
var
  Node: TTSNode;
begin
  AOwner:= '';
  AName := AStatement;
  if AStatement.IsNull then Exit(False);
  Node:= Unwrapped(AStatement);
  if Node.NodeType = NODE_CALL then Node:= Node.ChildByField(FIELD_ENTITY);
  if Node.IsNull then Exit(False);
  if Node.NodeType = NODE_DOT then
  begin
    AOwner:= FlatText(NodeText(Node.ChildByField(FIELD_LHS), FSrc));
    Node  := Node.ChildByField(FIELD_RHS);
    if Node.IsNull or (AOwner = '') then Exit(False);
  end;
  AName := Node;
  Result:= Node.NodeType = NODE_IDENTIFIER;
end;

function TNoReturnFacts.SymbolNeverReturns(AId: Int64): Boolean;
begin
  if FById.TryGetValue(AId, Result) then Exit;
  Result:= FStore.GetSymbolExtra(AId).NoReturn <> NORETURN_NONE;
  FById.Add(AId, Result);
end;

{ Every symbol of the name, in both indexes, is a routine that carries the fact: a variable, a
  field or a routine that returns under the same name makes the answer False. }
function TNoReturnFacts.NameNeverReturns(const AName: string): Boolean;
var
  Stores: TArray<ISymbolStore>;
  Store : ISymbolStore;
  Symbol: TSymbol;
  Found : Boolean;
begin
  if FByName.TryGetValue(LowerCase(AName), Result) then Exit;
  Found := False;
  Result:= True;
  Stores:= [FStore, FLibStore];
  for Store in Stores do
    if Result and (Store <> nil) then
      for Symbol in Store.FindSymbolsByExactName(AName) do
      begin
        Found := True;
        Result:= (Symbol.Kind in [skProcedure, skFunction, skMethod]) and (Store.GetSymbolExtra(Symbol.Id).NoReturn <> NORETURN_NONE);
        if not Result then Break;
      end;
  Result:= Result and Found;
  FByName.Add(LowerCase(AName), Result);
end;

{ A finally body is emitted once per way out of its try, so one statement can be asked about twice. }
procedure TNoReturnFacts.AddHit(const AStatement: TTSNode);
var
  Seen: TTSNode;
begin
  for Seen in FHits do
    if Seen.StartByte = AStatement.StartByte then Exit;
  FHits.Add(AStatement);
end;

function TNoReturnFacts.CallNeverReturns(const AStatement: TTSNode): Boolean;
var
  Name : TTSNode;
  Owner: string;
  Id   : Int64;
begin
  Result:= False;
  if (FStore = nil) or not Callee(AStatement, Name, Owner) then Exit;
  LoadEdges;
  if FEdges.TryGetValue(SiteKey(Integer(Name.StartPoint.Row) + 1, TAstParseCache.CharCol(FPath, Name.StartPoint)), Id) then
    Result:= SymbolNeverReturns(Id)
  else if (Owner = '') or MatchStr(Owner, RTL_OWNERS) then
    Result:= NameNeverReturns(NodeText(Name, FSrc));
  if Result then AddHit(AStatement);
end;

function TNoReturnFacts.Oracle: TCfgNoReturnCall;
begin
  Result:= function(const AStatement: TTSNode): Boolean
    begin
      Result:= CallNeverReturns(AStatement);
    end;
end;

function TNoReturnFacts.CalleeText(const AStatement: TTSNode): string;
var
  Name : TTSNode;
  Owner: string;
begin
  Result:= if Callee(AStatement, Name, Owner) then NodeText(Name, FSrc) else '';
end;

{ TNoReturnRun }

constructor TNoReturnRun.Create(const ACtx: TV151FileCtx);
var
  Parsed: TParsedFile;
begin
  inherited Create;
  FCtx     := ACtx;
  FFindings:= TList<TLintFinding>.Create;
  Parsed   := TAstParseCache.Get(ACtx.Path);
  FParsed  := Parsed.Tree <> nil;
  if not FParsed then Exit;
  FSrc  := Parsed.Src;
  FRoot := Parsed.Tree.RootNode;
  FFacts:= TNoReturnFacts.Create(ACtx.Store, ACtx.LibStore, ACtx.FileId, ACtx.Path, FSrc);
end;

destructor TNoReturnRun.Destroy;
begin
  FFacts.Free;
  FFindings.Free;
  inherited;
end;

function TNoReturnRun.Findings: TArray<TLintFinding>;
begin
  Result:= FFindings.ToArray;
end;

procedure TNoReturnRun.Emit(const ASeverity, AMessage, ASymbolName: string; const ANode: TTSNode);
var
  Finding: TLintFinding;
begin
  Finding:= Default(TLintFinding);
  Finding.RuleId    := RULE_NORETURN_CONTRACT;
  Finding.Severity  := ASeverity;
  Finding.Message   := AMessage;
  Finding.FilePath  := FCtx.Path;
  Finding.StartLine := Integer(ANode.StartPoint.Row) + 1;
  Finding.StartCol  := TAstParseCache.CharCol(FCtx.Path, ANode.StartPoint);
  Finding.EndLine   := Integer(ANode.EndPoint.Row) + 1;
  Finding.EndCol    := TAstParseCache.CharCol(FCtx.Path, ANode.EndPoint);
  Finding.SymbolName:= ASymbolName;
  FFindings.Add(Finding);
end;

function TNoReturnRun.Text(const ANode: TTSNode): string;
begin
  Result:= NodeText(ANode, FSrc);
end;

{ The statement that follows AStatement in the same statement list. }
function TNoReturnRun.NextStatement(const AStatement: TTSNode; out ANext: TTSNode): Boolean;
var
  List: TTSNode;
  I   : Integer;
  Past: Boolean;
begin
  ANext:= AStatement;
  List := AStatement.Parent;
  if List.IsNull or not MatchStr(List.NodeType, LIST_NODES) then Exit(False);
  Past:= False;
  for I:= 0 to List.NamedChildCount - 1 do
  begin
    ANext:= List.NamedChild(I);
    if Past and not IsNoCode(ANext.NodeType) then Exit(True);
    Past:= Past or (ANext.StartByte = AStatement.StartByte);
  end;
  Result:= False;
end;

{ `Result := X`, `<function name> := X` and `Exit` after a call that never returns are written to
  keep a compiler quiet that does not know the callee; the Delphi 13 compiler reports the
  assignment itself (H2077). }
function TNoReturnRun.KeepsCompilerQuiet(const ANext: TTSNode; const ARoutineName: string): Boolean;
var
  Node  : TTSNode;
  Target: string;
begin
  Node:= Unwrapped(ANext);
  if Node.NodeType <> NODE_ASSIGNMENT then Exit(StatementKeyword(ANext, FSrc) = EXIT_NAME);
  Target:= FlatText(Text(Node.ChildByField(FIELD_LHS)));
  Result:= (Target = RESULT_NAME) or (Target = LowerCase(ARoutineName));
end;

{ Something reachable leaves the routine, and everything that does is a raise, Halt, Abort or a
  call that never returns. A routine that only loops forever has no way out at all: False. }
function TNoReturnRun.NeverReturns(ACfg: TCfg): Boolean;
var
  Seen: TList<Integer>;
  I, Next: Integer;
begin
  Result:= False;
  Seen  := TList<Integer>.Create;
  try
    Seen.Add(ACfg.EntryIdx);
    I:= 0;
    while I < Seen.Count do
    begin
      for Next in ACfg.Blocks[Seen[I]].Succ do
        if Next = ACfg.ExitIdx then
        begin
          if not ACfg.Blocks[Seen[I]].NoReturn then Exit(False);
          Result:= True;
        end
        else if not Seen.Contains(Next) then Seen.Add(Next);
      Inc(I);
    end;
  finally
    Seen.Free;
  end;
end;

{ The indexed RTL declares Abort with the directive: the code base is compiled by a compiler
  that has it (Delphi 13). Asked once per run. }
function TNoReturnRun.CompilerKnowsDirective: Boolean;
var
  Stores: TArray<ISymbolStore>;
  Store : ISymbolStore;
  Symbol: TSymbol;
begin
  if FDirectiveKnown = 0 then
  begin
    FDirectiveKnown:= KNOWN_NO;
    Stores:= [FCtx.LibStore, FCtx.Store];
    for Store in Stores do
      if Store <> nil then
        for Symbol in Store.FindSymbolsByExactName(PROBE_ROUTINE) do
          if (Symbol.Kind = skProcedure) and (Store.GetSymbolExtra(Symbol.Id).NoReturn = NORETURN_DIRECTIVE) then
            FDirectiveKnown:= KNOWN_YES;
  end;
  Result:= FDirectiveKnown = KNOWN_YES;
end;

{ The class, or one of its ancestors, lists an interface: a method may implement an interface
  method, and then the interface dictates its directives (E2211). }
function TNoReturnRun.HasInterfaces(AClassId: Int64): Boolean;
var
  Ancestor: TTypeAncestor;
  Part    : string;
begin
  Result:= False;
  for Part in FCtx.Store.GetSymbolById(AClassId).Heritage.Split([',']) do
    if IsInterfaceName(LastName(Trim(Part))) then Exit(True);
  for Ancestor in FCtx.Store.GetTransitiveAncestors(AClassId) do
    if IsInterfaceName(LastName(Ancestor.Name)) or not Ancestor.Resolved then Exit(True);
end;

{ The routine is one whose declaration its author is free to change: the index knows it, it does
  not carry the directive yet, and no ancestor, interface, form file or event type dictates it. }
function TNoReturnRun.MayBeMarked(const ARoutine: TTSNode; out AName: TTSNode): Boolean;
var
  Header: TTSNode;
  Symbol: TSymbol;
  Words : TArray<string>;
begin
  Result:= False;
  Header:= ARoutine.ChildByField(FIELD_HEADER);
  AName := ARoutine;
  if Header.IsNull or (FCtx.Store = nil) or (FCtx.FileId = 0) then Exit;
  AName:= Header.ChildByField(FIELD_NAME);
  if AName.IsNull then Exit;
  Symbol:= FCtx.Store.FindEnclosingRoutineByImpl(FCtx.FileId, Integer(ARoutine.StartPoint.Row) + 1);
  if (Symbol.Id <= 0) or (not SameText(LastName(Text(AName)), Symbol.Name)) or (Symbol.Kind not in [skProcedure, skFunction, skMethod]) then Exit;
  Words := SplitString(LowerCase(Symbol.Directives), ' ');
  Result:= not (Symbol.IsVirtual or MatchStr(NO_RETURN_DIRECTIVE, Words) or AnyFixed(Words) or ContainsStr(FlatText(Text(Header)), EVENT_PARAM));
  Result:= Result and (FCtx.Store.GetSymbolExtra(Symbol.Id).NoReturn = NORETURN_NONE);
  Result:= Result and ((Symbol.Kind <> skMethod) or (Symbol.ParentId <= 0) or not HasInterfaces(Symbol.ParentId));
end;

procedure TNoReturnRun.CheckRoutine(const ARoutine: TTSNode);
var
  Cfg : TCfg;
  Hit, Next, Name: TTSNode;
  Own, Called: string;
begin
  FFacts.Hits.Clear;
  Cfg:= TCfgBuilder.Build(ARoutine, FSrc, True, FFacts.Oracle());
  try
    if Cfg.Skipped or (Cfg.Blocks.Count = 0) then Exit;
    Own:= LastName(Text(ARoutine.ChildByField(FIELD_HEADER).ChildByField(FIELD_NAME)));
    for Hit in FFacts.Hits.ToArray do
      if NextStatement(Hit, Next) and not KeepsCompilerQuiet(Next, Own) then
      begin
        Called:= FFacts.CalleeText(Hit);
        Emit(SEVERITY_WARNING, Format(MSG_AFTER, [Called, Called]), '', Next);
      end;
    if NeverReturns(Cfg) and CompilerKnowsDirective and MayBeMarked(ARoutine, Name) then
      Emit(SEVERITY_HINT, Format(MSG_UNMARKED, [Text(Name)]), LastName(Text(Name)), Name);
  finally
    Cfg.Free;
  end;
end;

procedure TNoReturnRun.Check;
var
  Routine: TTSNode;
begin
  if (not FParsed) or (FCtx.Store = nil) then Exit;
  for Routine in CfgFindProcs(FRoot) do
    if not Routine.ChildByField(FIELD_HEADER).IsNull then CheckRoutine(Routine);
end;

end.
