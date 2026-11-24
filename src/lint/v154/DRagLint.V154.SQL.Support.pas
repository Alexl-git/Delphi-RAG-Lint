unit DRagLint.V154.SQL.Support;

{ Wave v154 lane SQL -- helpers of DRagLint.V154.SQL (private to the lane): the three checks over one TSqlTextScan.
    sql-param-mismatch     -- ParamByName of a name the one known SQL text does not have; a parameter never set
    query-in-loop          -- a query run per iteration, directly or through a call of at most two levels
    field-by-name-in-loop  -- host expansion: ParamByName looked up per iteration (option, OFF) }

interface

uses
  DRagLint.Core.Model
  , DRagLint.V151.Api
  , DRagLint.V154.SqlText
  ;

const
  RULE_SQL_PARAM = 'sql-param-mismatch';
  RULE_QUERY_LOOP = 'query-in-loop';
  RULE_FIELD_LOOP = 'field-by-name-in-loop';
  { lint config threshold: 1 = field-by-name-in-loop also reports ParamByName }
  OPT_PARAM_LOOP = 'field-by-name-in-loop.param_by_name';

/// <summary>True when the unit can hold anything the lane looks at.</summary>
/// <param name="AFile">The .pas file.</param>
/// <returns>False when no query member is named in it.</returns>
function MayUseSql(const AFile: string): Boolean;

/// <summary>sql-param-mismatch of one unit.</summary>
/// <param name="ACtx">The file.</param>
/// <param name="AScan">Its datasets.</param>
/// <returns>Findings; nil when none.</returns>
function CheckSqlParams(const ACtx: TV151FileCtx; const AScan: TSqlTextScan): TArray<TLintFinding>;

/// <summary>query-in-loop of one unit.</summary>
/// <param name="ACtx">The file; the call part needs its Store.</param>
/// <param name="AScan">Its datasets.</param>
/// <returns>Findings; nil when none.</returns>
function CheckQueryInLoop(const ACtx: TV151FileCtx; const AScan: TSqlTextScan): TArray<TLintFinding>;

/// <summary>ParamByName in a loop, reported as field-by-name-in-loop.</summary>
/// <param name="ACtx">The file.</param>
/// <param name="AScan">Its datasets.</param>
/// <returns>One finding per outermost loop; nil when none.</returns>
function CheckParamByNameInLoop(const ACtx: TV151FileCtx; const AScan: TSqlTextScan): TArray<TLintFinding>;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.Classes
  , System.Generics.Collections
  , System.RegularExpressions
  , FireDAC.Comp.Client
  , FireDAC.Stan.Param
  , TreeSitter
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Storage.SQLite
  ;

const
  SEVERITY_WARNING = 'warning';
  SEVERITY_HINT = 'hint';
  SMALL_BOUND = 10;          // a loop over at most this many literal steps is no row loop
  MAX_LISTED = 6;
  ROUTINE_NODES: array[0..1] of string = ('defProc', 'lambda');
  LOOP_NODES: array[0..3] of string = ('for', 'foreach', 'while', 'repeat');
  LIST_NODES: array[0..1] of string = ('block', 'statements');
  { classes whose run is a database round trip, besides the SQL classes }
  RUN_CLASSES: array[0..13] of string = ('TFDTable', 'TTable', 'TFDStoredProc', 'TStoredProc', 'TADOTable', 'TADOStoredProc', 'TADOCommand',
    'TADODataSet', 'TIBTable', 'TIBStoredProc', 'TFDConnection', 'TADOConnection', 'TSQLConnection', 'TSQLStoredProc');
  { Params members that read or fill values by position and create no parameter }
  VALUE_MEMBERS: array[0..8] of string = ('items', 'count', 'arraysize', 'bindmode', 'values', 'execute-array', 'mastersource', 'masterfields',
    'datasource');
  { condition words of a loop body that asks a cache first }
  CACHE_PATTERN = '\b(TryGetValue|ContainsKey|IndexOf|Find\w*|Contains|Active|State|Assigned)\b|\bnil\b';
  POLL_PATTERN = '\b(Terminated|Sleep|WaitFor)\b';
  RETRY_PATTERN = '(retr(y|ies)|attempt|tries|\bBreak\b|\bExit\b)';

{ ---- text and tree ---- }

function SourceText(const ANode: TTSNode; const ASrc: TBytes): string;
var
  First, Last: Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  First:= Integer(ANode.StartByte);
  Last := Integer(ANode.EndByte);
  if (Last > First) and (Last <= Length(ASrc)) then Result:= TEncoding.UTF8.GetString(ASrc, First, Last - First);
end;

function MayUseSql(const AFile: string): Boolean;
begin
  Result:= TRegEx.IsMatch(TEncoding.UTF8.GetString(TAstParseCache.Get(AFile).Src),
    '\b(SQL|CommandText|ParamByName|ExecSQL|ExecProc|Open|Execute|Active)\b', [roIgnoreCase]);
end;

{ The loops whose body ANode is in, innermost first; a routine or an anonymous method ends the search. }
function LoopsAround(const ANode: TTSNode): TArray<TTSNode>;
var
  Node, Child: TTSNode;
  I   : Integer;
  Body: Boolean;
begin
  Result:= nil;
  Node  := ANode.Parent;
  while (not Node.IsNull) and (not MatchStr(Node.NodeType, ROUTINE_NODES)) do
  begin
    if MatchStr(Node.NodeType, LOOP_NODES) then
    begin
      Body:= not MatchStr(Node.NodeType, ['for', 'foreach']);
      for I:= 0 to Node.NamedChildCount - 1 do
      begin
        Child:= Node.NamedChild(I);
        if (Child.NodeType = 'kDo') and (Child.EndByte <= ANode.StartByte) then Body:= True;
      end;
      if Body then Result:= Result + [Node];
    end;
    Node:= Node.Parent;
  end;
end;

{ The first identifier of a loop header: the control variable of for / for-in. }
function LoopVariable(const ALoop: TTSNode; const ASrc: TBytes): string;
var
  Node: TTSNode;
begin
  Result:= '';
  if (ALoop.NodeType <> 'for') and (ALoop.NodeType <> 'foreach') then Exit;
  Node:= ALoop.NamedChild(1);
  while (not Node.IsNull) and (Node.NodeType <> 'identifier') and (Node.NamedChildCount > 0) do
    Node:= Node.NamedChild(if Node.NodeType = 'varAssignDef' then 1 else 0);
  Result:= SourceText(Node, ASrc);
end;

{ The condition of while / repeat; null for a for loop. }
function LoopCondition(const ALoop: TTSNode): TTSNode;
begin
  Result:= Default(TTSNode);
  if ALoop.NodeType = 'while' then Result:= ALoop.NamedChild(1)
  else if ALoop.NodeType = 'repeat' then Result:= ALoop.NamedChild(ALoop.NamedChildCount - 1);
end;

{ for I := 0 to 3, for X in [A, B]: a handful of steps the source states. }
function SmallBound(const ALoop: TTSNode; const ASrc: TBytes): Boolean;
var
  First, Last, I: Integer;
  Node: TTSNode;
  Seen: Boolean;
begin
  Result:= False;
  if ALoop.NodeType = 'foreach' then
  begin
    for I:= 0 to ALoop.NamedChildCount - 1 do
      if (ALoop.NamedChild(I).NodeType = 'exprBrackets') and (ALoop.NamedChild(I).NamedChildCount <= SMALL_BOUND) then Exit(True);
    Exit;
  end;
  if ALoop.NodeType <> 'for' then Exit;
  Node:= ALoop.NamedChild(1);
  if (Node.NodeType <> 'assignment') or (not TryStrToInt(SourceText(Node.ChildByField('rhs'), ASrc), First)) then Exit;
  Seen:= False;
  for I:= 0 to ALoop.NamedChildCount - 1 do
  begin
    Node:= ALoop.NamedChild(I);
    if Seen then Exit(TryStrToInt(SourceText(Node, ASrc), Last) and (Abs(Last - First) < SMALL_BOUND));
    Seen:= MatchStr(Node.NodeType, ['kTo', 'kDownto']);
  end;
end;

function MentionsWord(const AText, AWord: string): Boolean;
begin
  Result:= (AWord <> '') and TRegEx.IsMatch(AText, '\b' + TRegEx.Escape(AWord) + '\b', [roIgnoreCase]);
end;

{ while not Terminated, while True, repeat .. until False, a body that sleeps: not one step per row. }
function Polls(const ALoop: TTSNode; const ASrc: TBytes): Boolean;
var
  Cond: TTSNode;
begin
  Cond:= LoopCondition(ALoop);
  if Cond.IsNull then Exit(False);
  Result:= MatchStr(Cond.NodeType, ['kTrue', 'kFalse']) or TRegEx.IsMatch(SourceText(ALoop, ASrc), POLL_PATTERN, [roIgnoreCase]);
end;

{ The call stands in the try part of a try .. except that the loop leaves on success, or counts attempts. }
function Retries(const ALoop, ASite: TTSNode; const ASrc: TBytes): Boolean;
var
  Node: TTSNode;
  I   : Integer;
begin
  Node:= ASite.Parent;
  while (not Node.IsNull) and (Node.StartByte >= ALoop.StartByte) and (Node.EndByte <= ALoop.EndByte) do
  begin
    if Node.NodeType = 'try' then
      for I:= 0 to Node.NamedChildCount - 1 do
        if (Node.NamedChild(I).NodeType = 'kExcept') and (Node.NamedChild(I).StartByte > ASite.StartByte) then
          Exit(TRegEx.IsMatch(SourceText(ALoop, ASrc), RETRY_PATTERN, [roIgnoreCase]));
    Node:= Node.Parent;
  end;
  Result:= False;
end;

{ One of the statement lists between the call and the loop ends by leaving the loop: the call runs once. }
function LeavesLoop(const ALoop, ASite: TTSNode; const ASrc: TBytes): Boolean;
var
  Node, Last: TTSNode;
  I: Integer;
begin
  Node:= ASite.Parent;
  while (not Node.IsNull) and (Node.StartByte >= ALoop.StartByte) and (Node.EndByte <= ALoop.EndByte) do
  begin
    if MatchStr(Node.NodeType, LIST_NODES) then
    begin
      Last:= Default(TTSNode);
      for I:= 0 to Node.NamedChildCount - 1 do
        if not MatchStr(Node.NamedChild(I).NodeType, ['kBegin', 'kEnd', 'comment']) then Last:= Node.NamedChild(I);
      if (not Last.IsNull) and TRegEx.IsMatch(SourceText(Last, ASrc), '^(Break|Exit\b.*|raise\b.*);?$', [roIgnoreCase, roSingleLine]) then Exit(True);
    end;
    Node:= Node.Parent;
  end;
  Result:= False;
end;

{ An if between the call and the loop asks a cache or the dataset's own state first. }
function Guarded(const ALoop, ASite: TTSNode; const ASrc: TBytes): Boolean;
var
  Node: TTSNode;
begin
  Node:= ASite.Parent;
  while (not Node.IsNull) and (Node.StartByte >= ALoop.StartByte) and (Node.EndByte <= ALoop.EndByte) do
  begin
    if MatchStr(Node.NodeType, ['if', 'ifElse']) and (Node.NamedChild(1).EndByte <= ASite.StartByte) and
       TRegEx.IsMatch(SourceText(Node.NamedChild(1), ASrc), CACHE_PATTERN, [roIgnoreCase]) then
      Exit(True);
    Node:= Node.Parent;
  end;
  Result:= False;
end;

{ The first loop around ANode that runs it once per step; null when none. ARecv is the receiver text, '' for a call. }
function RowLoop(const ANode: TTSNode; const ASrc: TBytes; const ARecv: string): TTSNode;
var
  Loop: TTSNode;
  Cond: string;
begin
  Result:= Default(TTSNode);
  for Loop in LoopsAround(ANode) do
  begin
    if SmallBound(Loop, ASrc) or Polls(Loop, ASrc) or Retries(Loop, ANode, ASrc) or LeavesLoop(Loop, ANode, ASrc) or
       Guarded(Loop, ANode, ASrc) then
      Continue;
    Cond:= SourceText(LoopCondition(Loop), ASrc);
    if (ARecv <> '') and (MentionsWord(ARecv, LoopVariable(Loop, ASrc)) or MentionsWord(Cond, ARecv)) then Exit(Default(TTSNode));
    Exit(Loop);
  end;
end;

function NewFinding(const ACtx: TV151FileCtx; const ARule, ASeverity, AMessage: string; const ASite: TSqlSite): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId   := ARule;
  Result.Severity := ASeverity;
  Result.Message  := AMessage;
  Result.FilePath := ACtx.Path;
  Result.StartLine:= ASite.Line;
  Result.StartCol := ASite.Col;
  Result.EndLine  := ASite.Line;
  Result.EndCol   := ASite.EndCol;
end;

{ ---- sql-param-mismatch ---- }

function NameList(const ANames: TArray<string>): string;
begin
  if Length(ANames) = 0 then Exit('the SQL has no parameters');
  Result:= 'the SQL has ' + string.Join(', ', Copy(ANames, 0, MAX_LISTED));
  if Length(ANames) > MAX_LISTED then Result:= Result + Format(', +%d more', [Length(ANames) - MAX_LISTED]);
end;

{ The dataset's parameter names are exactly those of its SQL. }
function ParamsFollowSql(const AScan: TSqlTextScan; const AData: TSqlDataset): Boolean;
var
  Site: TSqlSite;
begin
  Result:= IsSqlClass(AData.DataClass) and (AData.Reason = '') and (AData.Facts.Sql <> '') and (AData.Facts.ParamReason = '');
  if not Result then Exit;
  for Site in AData.Sites do
    if (Site.Kind = sskParamsOther) and (not MatchStr(Site.Member, VALUE_MEMBERS)) then Exit(False);
  Result:= AScan.OutsideReason(AData, False) = '';
end;

{ Every way to set a parameter is seen: only ParamByName with a literal, no positional values, no master. }
function SettersSeen(const AScan: TSqlTextScan; const AData: TSqlDataset): Boolean;
var
  Site: TSqlSite;
  Any : Boolean;
begin
  Any:= False;
  for Site in AData.Sites do
  begin
    if (Site.Kind = sskParamsOther) or ((Site.Kind = sskParam) and (not Site.Known)) then Exit(False);
    Any:= Any or (Site.Kind = sskParam);
  end;
  if AData.Facts.Verb in [svProcedure, svOther, svNone] then Exit(False);
  if AData.InDfm and AData.Dfm.HasMaster then Exit(False);
  Result:= (AData.Scope = ssLocal) or (Any and (AData.Scope = ssMember) and (AScan.OutsideReason(AData, True) = ''));
end;

function NeverSet(const AData: TSqlDataset): TArray<string>;
var
  Name : string;
  Site : TSqlSite;
  Found: Boolean;
begin
  Result:= nil;
  for Name in AData.Facts.ParamNames do
  begin
    Found:= MatchText(Name, AData.Dfm.ValuedParams) or TRegEx.IsMatch(AData.Facts.Sql, '\bINTO\s+:', [roIgnoreCase]);
    for Site in AData.Sites do
      Found:= Found or ((Site.Kind = sskParam) and SameText(Site.Text, Name));
    if not Found then Result:= Result + [Name];
  end;
end;

function CheckSqlParams(const ACtx: TV151FileCtx; const AScan: TSqlTextScan): TArray<TLintFinding>;
var
  Data   : TSqlDataset;
  Site   : TSqlSite;
  Missing: TArray<string>;
begin
  Result:= nil;
  for Data in AScan.Datasets do
  begin
    if (not Data.Has([sskParam, sskRun])) or (not ParamsFollowSql(AScan, Data)) then Continue;
    for Site in Data.Sites do
      if (Site.Kind = sskParam) and Site.Known and (Site.Member = 'parambyname') and (not Data.Facts.HasParam(Site.Text)) and
         (not Site.Text.Contains(';')) then
        Result:= Result + [NewFinding(ACtx, RULE_SQL_PARAM, SEVERITY_WARNING,
          Format('ParamByName(''%s''): %s has no such parameter -- %s', [Site.Text, Data.Name, NameList(Data.Facts.ParamNames)]), Site)];
    if not SettersSeen(AScan, Data) then Continue;
    Missing:= NeverSet(Data);
    if Length(Missing) = 0 then Continue;
    for Site in Data.Sites do
      if Site.Kind = sskRun then
      begin
        Result:= Result + [NewFinding(ACtx, RULE_SQL_PARAM, SEVERITY_WARNING,
          Format('%s runs with a parameter that is never set: %s', [Data.Name, string.Join(', ', Missing)]), Site)];
        Break;
      end;
  end;
end;

{ ---- query-in-loop ---- }

function RunsOnServer(const AClass: string): Boolean;
begin
  Result:= IsSqlClass(AClass) or MatchText(AClass, RUN_CLASSES);
end;

{ A whole statement taken from a variable or a list: each step runs another statement, nothing to lift out. }
function RunsOtherStatement(const AData: TSqlDataset; const ALoop: TTSNode; const ASrc: TBytes): Boolean;
var
  Site: TSqlSite;
  Node: TTSNode;
begin
  for Site in AData.Sites do
    if (Site.Kind = sskSqlSet) and (Site.Pos > ALoop.StartByte) and (Site.Pos < ALoop.EndByte) then
    begin
      if Site.Known then
      begin
        if ReadSqlText(Site.Text).Verb = svOther then Exit(True);
        Continue;
      end;
      { the enclosing call or assignment holds no literal: the text is not written here }
      Node:= Site.Node.Parent;
      while (not Node.IsNull) and (not MatchStr(Node.NodeType, ['exprCall', 'assignment', 'statement'])) do Node:= Node.Parent;
      if not SourceText(Node, ASrc).Contains('''') then Exit(True);
    end;
  Result:= False;
end;

{ The loop points the dataset at another database, table or procedure in each step: there is no set to read. }
function Repointed(const AData: TSqlDataset; const ALoop: TTSNode; const ASrc: TBytes): Boolean;
begin
  Result:= TRegEx.IsMatch(SourceText(ALoop, ASrc),
    '\b' + TRegEx.Escape(AData.Name) + '\s*\.\s*(DatabaseName|TableName|ConnectionName|StoredProcName)\s*:=', [roIgnoreCase]);
end;

{ The receiver is taken from somewhere else in the loop, or the dataset sends its rows as one array. }
function LoopOwnsDataset(const AData: TSqlDataset; const ALoop: TTSNode): Boolean;
var
  Site: TSqlSite;
begin
  for Site in AData.Sites do
  begin
    if (Site.Kind = sskCreated) and (not Site.Known) and (Site.Pos > ALoop.StartByte) and (Site.Pos < ALoop.EndByte) then Exit(True);
    if (Site.Kind = sskParamsOther) and MatchStr(Site.Member, ['arraysize', 'execute-array']) then Exit(True);
  end;
  Result:= False;
end;

type
  { The routines of the index that run SQL, at most two calls deep. One per file. }
  TCallFacts = class
  strict private
    FStore: TSQLiteSymbolStore;
    FRuns : TDictionary<Int64, string>;  // routine -> what runs the SQL, '' = none
    function Query(const ASql: string; AId: Int64): TFDQuery;
    function Direct(AId: Int64): string;
  public
    constructor Create(const AStore: TSQLiteSymbolStore);
    destructor Destroy; override;
    function Runs(AId: Int64): string;
  end;

constructor TCallFacts.Create(const AStore: TSQLiteSymbolStore);
begin
  inherited Create;
  FStore:= AStore;
  FRuns := TDictionary<Int64, string>.Create;
end;

destructor TCallFacts.Destroy;
begin
  FRuns.Free;
  inherited Destroy;
end;

function TCallFacts.Query(const ASql: string; AId: Int64): TFDQuery;
begin
  Result:= TFDQuery.Create(nil);
  Result.Connection:= FStore.GetConnection;
  Result.SQL.Text  := ASql;
  Result.ParamByName('i').AsLargeInt:= AId;
end;

{ The tables the routine's own SQL touches when it runs that SQL itself and asks no cache; '' otherwise. }
function TCallFacts.Direct(AId: Int64): string;
var
  Facts: TFDQuery;
begin
  Result:= '';
  Facts:= Query('SELECT COALESCE(f.sql_reads, f.sql_writes), ' +
    '(SELECT COUNT(*) FROM refs r WHERE r.enclosing_symbol_id = f.symbol_id AND r.name_text COLLATE NOCASE IN (''Open'', ''ExecSQL'', ''Execute'', ''ExecProc'')), ' +
    '(SELECT COUNT(*) FROM refs r WHERE r.enclosing_symbol_id = f.symbol_id AND r.name_text COLLATE NOCASE IN (''TryGetValue'', ''ContainsKey'', ''AddOrSetValue'')) ' +
    'FROM symbol_facts f WHERE f.symbol_id = :i', AId);
  try
    Facts.Open;
    if (not Facts.Eof) and (Facts.Fields[1].AsInteger > 0) and (Facts.Fields[2].AsInteger = 0) then Result:= Facts.Fields[0].AsString;
  finally
    Facts.Free;
  end;
end;

function TCallFacts.Runs(AId: Int64): string;
var
  Calls: TFDQuery;
  Table: string;
begin
  if FRuns.TryGetValue(AId, Result) then Exit;
  Result:= Direct(AId);
  if Result = '' then
  begin
    Calls:= Query('SELECT DISTINCT e.target_symbol_id, s.name FROM refs r JOIN call_edges e ON e.ref_id = r.id AND e.confidence = ''certain'' ' +
      'JOIN symbols s ON s.id = e.target_symbol_id WHERE r.enclosing_symbol_id = :i AND e.target_symbol_id <> :i ' +
      'AND NOT EXISTS (SELECT 1 FROM refs c WHERE c.enclosing_symbol_id = r.enclosing_symbol_id ' +
      'AND c.name_text COLLATE NOCASE IN (''TryGetValue'', ''ContainsKey'', ''AddOrSetValue''))', AId);
    try
      Calls.Open;
      while (Result = '') and (not Calls.Eof) do
      begin
        Table:= Direct(Calls.Fields[0].AsLargeInt);
        if Table <> '' then Result:= Format('%s through %s', [Table, Calls.Fields[1].AsString]);
        Calls.Next;
      end;
    finally
      Calls.Free;
    end;
  end;
  FRuns.Add(AId, Result);
end;

{ Every call name inside a loop of the tree, with its position. }
procedure CollectLoopCalls(const ANode: TTSNode; AInLoop: Boolean; AList: TList<TTSNode>);
var
  I   : Integer;
  Name: TTSNode;
begin
  if MatchStr(ANode.NodeType, LOOP_NODES) then AInLoop:= True
  else if MatchStr(ANode.NodeType, ROUTINE_NODES) then AInLoop:= False;
  if AInLoop and MatchStr(ANode.NodeType, ['exprCall', 'statement', 'exprDot']) then
  begin
    Name:= ANode;
    if Name.NodeType = 'statement' then Name:= Name.NamedChild(0);
    if (not Name.IsNull) and (Name.NodeType = 'exprCall') then Name:= Name.ChildByField('entity');
    if (not Name.IsNull) and (Name.NodeType = 'exprDot') then Name:= Name.ChildByField('rhs');
    if (not Name.IsNull) and (Name.NodeType = 'identifier') then AList.Add(Name);
  end;
  for I:= 0 to ANode.NamedChildCount - 1 do CollectLoopCalls(ANode.NamedChild(I), AInLoop, AList);
end;

function SiteKey(ALine, ACol: Integer): string;
begin
  Result:= Format('%d:%d', [ALine, ACol]);
end;

{ The certain call edges of the file: position -> called routine. }
procedure LoadEdges(const ACtx: TV151FileCtx; AEdges: TDictionary<string, TPair<Int64, string>>);
var
  Query: TFDQuery;
begin
  Query:= TFDQuery.Create(nil);
  try
    Query.Connection:= (ACtx.Store as TSQLiteSymbolStore).GetConnection;
    Query.SQL.Text  := 'SELECT r.start_line, r.start_col, e.target_symbol_id, s.name FROM refs r JOIN call_edges e ON e.ref_id = r.id ' +
      'AND e.confidence = ''certain'' JOIN symbols s ON s.id = e.target_symbol_id WHERE r.file_id = :f ' +
      'AND COALESCE(s.directives, '''') NOT LIKE ''%abstract%''';
    Query.ParamByName('f').AsLargeInt:= ACtx.FileId;
    Query.Open;
    while not Query.Eof do
    begin
      AEdges.AddOrSetValue(SiteKey(Query.Fields[0].AsInteger, Query.Fields[1].AsInteger),
        TPair<Int64, string>.Create(Query.Fields[2].AsLargeInt, Query.Fields[3].AsString));
      Query.Next;
    end;
  finally
    Query.Free;
  end;
end;

{ Calls in a loop of a routine that runs SQL. ADone holds the positions already reported. }
function CallsInLoop(const ACtx: TV151FileCtx; const ASrc: TBytes; const ARoot: TTSNode; ADone: TDictionary<string, Boolean>): TArray<TLintFinding>;
var
  Edges: TDictionary<string, TPair<Int64, string>>;
  Facts: TCallFacts;
  Names: TList<TTSNode>;
  Node : TTSNode;
  Edge : TPair<Int64, string>;
  Site : TSqlSite;
  Runs : string;
begin
  Result:= nil;
  if (ACtx.Store is not TSQLiteSymbolStore) or (ACtx.FileId = 0) then Exit;
  Edges:= TDictionary<string, TPair<Int64, string>>.Create;
  Facts:= TCallFacts.Create(ACtx.Store as TSQLiteSymbolStore);
  Names:= TList<TTSNode>.Create;
  try
    CollectLoopCalls(ARoot, False, Names);
    if Names.Count = 0 then Exit;
    LoadEdges(ACtx, Edges);
    for Node in Names do
    begin
      Site:= Default(TSqlSite);
      Site.Line  := Integer(Node.StartPoint.Row) + 1;
      Site.Col   := TAstParseCache.CharCol(ACtx.Path, Node.StartPoint);
      Site.EndCol:= TAstParseCache.CharCol(ACtx.Path, Node.EndPoint);
      if ADone.ContainsKey(SiteKey(Site.Line, Site.Col)) or (not Edges.TryGetValue(SiteKey(Site.Line, Site.Col), Edge)) then Continue;
      Runs:= Facts.Runs(Edge.Key);
      if (Runs = '') or RowLoop(Node, ASrc, '').IsNull then Continue;
      ADone.Add(SiteKey(Site.Line, Site.Col), True);
      Result:= Result + [NewFinding(ACtx, RULE_QUERY_LOOP, SEVERITY_HINT,
        Format('%s runs a query per iteration of this loop (%s) -- read or write the rows as one set', [Edge.Value, Runs]), Site)];
    end;
  finally
    Names.Free;
    Facts.Free;
    Edges.Free;
  end;
end;

function CheckQueryInLoop(const ACtx: TV151FileCtx; const AScan: TSqlTextScan): TArray<TLintFinding>;
var
  Parsed: TParsedFile;
  Data  : TSqlDataset;
  Site  : TSqlSite;
  Loop  : TTSNode;
  Done  : TDictionary<string, Boolean>;
begin
  Result:= nil;
  Parsed:= TAstParseCache.Get(ACtx.Path);
  if Parsed.Tree = nil then Exit;
  Done:= TDictionary<string, Boolean>.Create;
  try
    for Data in AScan.Datasets do
      if RunsOnServer(Data.DataClass) then
        for Site in Data.Sites do
        begin
          if (Site.Kind <> sskRun) or Done.ContainsKey(SiteKey(Site.Line, Site.Col)) then Continue;
          Loop:= RowLoop(Site.Node, Parsed.Src, Data.Name);
          if Loop.IsNull or LoopOwnsDataset(Data, Loop) or RunsOtherStatement(Data, Loop, Parsed.Src) or Repointed(Data, Loop, Parsed.Src) then
            Continue;
          Done.Add(SiteKey(Site.Line, Site.Col), True);
          Result:= Result + [NewFinding(ACtx, RULE_QUERY_LOOP, SEVERITY_HINT,
            Format('%s.%s runs a query per iteration of this loop -- read or write the rows as one set', [Data.Name, SourceText(Site.Node, Parsed.Src)]), Site)];
        end;
    Result:= Result + CallsInLoop(ACtx, Parsed.Src, Parsed.Tree.RootNode, Done);
  finally
    Done.Free;
  end;
end;

{ ---- ParamByName in a loop ---- }

{ The SQL is set or the dataset assigned in the loop, so its parameters are new objects in each step. }
function NewParamsInLoop(const AData: TSqlDataset; const ALoop: TTSNode): Boolean;
var
  Site: TSqlSite;
begin
  for Site in AData.Sites do
    if (Site.Kind in [sskSqlSet, sskSqlAdd, sskSqlClear, sskSqlOther, sskCreated, sskPassed]) and (Site.Pos > ALoop.StartByte) and
       (Site.Pos < ALoop.EndByte) then
      Exit(True);
  Result:= False;
end;

function CheckParamByNameInLoop(const ACtx: TV151FileCtx; const AScan: TSqlTextScan): TArray<TLintFinding>;
var
  Data : TSqlDataset;
  Site : TSqlSite;
  Loops: TArray<TTSNode>;
  Names: TDictionary<Cardinal, TStringList>;
  First: TDictionary<Cardinal, TSqlSite>;
  Outer: TTSNode;
  List : TStringList;
  Key  : Cardinal;
  Source: TBytes;
begin
  Result:= nil;
  Source:= TAstParseCache.Get(ACtx.Path).Src;
  Names:= TObjectDictionary<Cardinal, TStringList>.Create([doOwnsValues]);
  First:= TDictionary<Cardinal, TSqlSite>.Create;
  try
    for Data in AScan.Datasets do
      if IsSqlClass(Data.DataClass) then
        for Site in Data.Sites do
        begin
          if (Site.Kind <> sskParam) or (not Site.Known) then Continue;
          Loops:= LoopsAround(Site.Node);
          if Length(Loops) = 0 then Continue;
          Outer:= Loops[High(Loops)];
          { the FieldByName finding of the same loop carries the fix; two findings would offer its edit twice }
          if NewParamsInLoop(Data, Outer) or TRegEx.IsMatch(SourceText(Outer, Source), '\bFieldByName\s*\(', [roIgnoreCase]) then Continue;
          if not Names.TryGetValue(Outer.StartByte, List) then
          begin
            List:= TStringList.Create(dupIgnore, True, False);
            Names.Add(Outer.StartByte, List);
          end;
          List.Add(Site.Text);
          if (not First.ContainsKey(Outer.StartByte)) or (First[Outer.StartByte].Pos > Site.Pos) then First.AddOrSetValue(Outer.StartByte, Site);
        end;
    for Key in First.Keys do
      Result:= Result + [NewFinding(ACtx, RULE_FIELD_LOOP, SEVERITY_HINT,
        Format('ParamByName() looked up inside this loop (%s) -- keep the parameter reference(s) in locals before the loop',
          [string.Join(', ', Names[Key].ToStringArray)]), First[Key])];
  finally
    First.Free;
    Names.Free;
  end;
end;

end.
