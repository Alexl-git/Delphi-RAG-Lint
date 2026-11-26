unit DRagLint.FieldRepo.DfmReadCalc;

{ drag-lint 1.54 -- lane TT-DFMREAD: event handler code of a form unit as repository text (design
  2026-11-22-field-repository-v2-design.md sections 4.3 and 9, plan 2026-11-23-fr-dfmread.md). The unit is parsed
  with the engine's Pascal grammar (DRagLint.LSP.SyntaxTree).

  One OnCalcFields handler computes many fields; CALC_BODY holds the statements of ONE. The body of field F is a
  slice of the handler: every top-level statement up to the last one that assigns F, except the statements whose
  only effect is another calculated field or a local variable F does not need. Inside a kept statement the
  assignments to other calculated fields are cut out, except one that also moves a dataset (Locate, FindKey, ...).
  Anything else (a call statement, a write to something unknown) is kept. A needed local that only a dropped statement
  may set (a var argument of a function), and a calculated field that changes after the body reads it, BLOCK the body.
  Side effects of other functions called in a dropped expression are not seen. Local variables / constants become
  inline declarations.

  A persistent field becomes a field macro; the macro names the field COMPONENT and the code keeps the member (ruling R3
  of 2026-11-23): tblQTY.IsNull is macro QTY + .IsNull, DataSet.FieldByName('QTY').Value and DataSet['QTY'] are macro QTY +
  .AsVariant. What a macro cannot express (a field of another table, `with`, Exit, conditional code, a calculated field's
  component handed to other code) BLOCKS the body with the reason; nothing is rewritten by guess. A top-level Exit guard
  (if C then Exit) becomes a block: if not (C) then begin ... end.

  The text of generated DLFR regions is blanked before the unit is parsed: it came from the repository. A field whose
  code is in a region of the handler, and an event handler with a region, are not read. }

interface

uses
  System.SysUtils,
  System.Classes,
  TreeSitter;

type
  /// <summary>A persistent field as the handler code sees it.</summary>
  TDfmrCodeField = record
    /// <summary>Component name, e.g. tblOrdersQTY.</summary>
    CompName: string;
    /// <summary>FieldName property (what FieldByName gets).</summary>
    DataName: string;
    /// <summary>Repository FIELD_NAME the macro names; '' = not a field of the dataset's table.</summary>
    MacroName: string;
    /// <summary>True for calc and internal-calc fields.</summary>
    IsCalc: Boolean;
  end;

  /// <summary>The dataset a handler body is read for.</summary>
  TDfmrCodeContext = record
    /// <summary>Form class, e.g. TfrmOrders.</summary>
    FormClass: string;
    /// <summary>Dataset component name.</summary>
    Dataset: string;
    /// <summary>The dataset's persistent fields.</summary>
    Fields: TArray<TDfmrCodeField>;
    /// <summary>Every component of the form (used to note form-specific code).</summary>
    Components: TArray<string>;
  end;

  /// <summary>One body read from a handler.</summary>
  TDfmrBody = record
    /// <summary>Pascal statements with macros (CRLF between lines); '' = nothing found.</summary>
    Text: string;
    /// <summary>Non-empty = the text must not be stored (or, with Text '', why there is none).</summary>
    Blocked: string;
    /// <summary>Form components the body names besides the dataset's own fields: it is not portable as is.</summary>
    FormNames: TArray<string>;
    /// <summary>Component names (lower case) of every field of the dataset the kept code names, read or written, in
    /// the order they occur; a join gives a calc field the one table of these (design 2026-11-26-join-field-origin).</summary>
    FieldsUsed: TArray<string>;
  end;

  /// <summary>The handlers of one form unit.</summary>
  /// <remarks>Read only; not thread-safe. Holds the parse tree until freed.</remarks>
  TDfmrUnit = class
  strict private
  type
    TGenerated = record
      Id: string;
      First: Integer; // byte offset
      Text: string;
    end;
  strict private
    FRaw: TBytes;
    FSource: TBytes;
    FTree: TTSTree;
    FRegions: TArray<TGenerated>;
    procedure BlankRegions;
    procedure Parse(const pFile: string);
    function GeneratedIn(const pNode: TTSNode; const pField: string): string;
    function FindHandler(const pContext: TDfmrCodeContext; const pHandler, pField: string; out pNode: TTSNode): string;
  public
    /// <summary>Reads and parses a unit.</summary>
    /// <param name="pFile">Path of the .pas. A file that cannot be read raises what TFile.ReadAllBytes raises.</param>
    constructor Create(const pFile: string);
    /// <summary>Parses unit text (tests).</summary>
    /// <param name="pText">Unit source.</param>
    /// <param name="pFileName">Name the preprocessor sees.</param>
    constructor CreateFromText(const pText, pFileName: string);
    destructor Destroy; override;
    /// <summary>The statements of an OnCalcFields handler that compute one field.</summary>
    /// <param name="pContext">Form and dataset.</param>
    /// <param name="pHandler">Handler method name.</param>
    /// <param name="pField">Component name of the calculated field.</param>
    /// <returns>The body; Text '' with Blocked '' = the handler does not assign the field. Text '' with a reason also when
    /// a generated region of the handler assigns it.</returns>
    function CalcBody(const pContext: TDfmrCodeContext; const pHandler, pField: string): TDfmrBody;
    /// <summary>The whole body of a TField event handler.</summary>
    /// <param name="pContext">Form and dataset.</param>
    /// <param name="pHandler">Handler method name.</param>
    /// <param name="pParams">Standard parameter names of the event, in order.</param>
    /// <returns>The body; Text '' with a reason when the handler holds a generated region.</returns>
    function EventBody(const pContext: TDfmrCodeContext; const pHandler: string;
      const pParams: TArray<string>): TDfmrBody;
  end;

implementation

uses
  System.StrUtils,
  System.IOUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  System.Generics.Defaults,
  DRagLint.Core.Encoding,
  DRagLint.Diagnostics.ParseCache,
  DRagLint.LSP.SyntaxTree,
  DRagLint.FieldRepo.HandlersRegions;

type
  TByteRange = record
    First: Integer;
    Last: Integer; // exclusive
  end;

  TTextEdit = record
    Range: TByteRange;
    NewText: string;
  end;

  { A local variable or constant of the handler. }
  TLocalDecl = record
    Names: TArray<string>;
    InlineText: string;
    Mentions: TArray<string>; // every identifier of the declaration, lower case
    IsConst: Boolean;
  end;

  { One top-level statement and what running it changes. }
  TStatement = record
    Node: TTSNode;
    Comments: string;         // comment lines right above it
    TrailingComment: string;  // comment on its last line
    Fields: TArray<string>;   // calculated field components it assigns, lower case
    Locals: TArray<string>;   // locals it assigns, lower case
    Mentions: TArray<string>; // locals it names, lower case
    Bare: TArray<string>;     // calculated field components it uses as a whole, lower case
    Other: Boolean;           // any effect not listed above
    IsInherited: Boolean;
    Kept: Boolean;            // part of the body being read
    IsGuard: Boolean;         // `if C then Exit;`: the rest of the handler runs only when C is False
  end;

  { One handler: the AST work of CalcBody / EventBody. }
  THandler = class  // dl:ok high-response@e935 -- REVIEWED 2026-11-23 TT-DFMREAD: one handler's slicer; its state (edits, cuts, locals) is shared by every step and the response set is AST and string helper calls
  strict private
    FSource: TBytes;
    FContext: TDfmrCodeContext;
    FNode: TTSNode;
    FParams: TArray<string>;
    FStdParams: TArray<string>;
    FLocals: TArray<TLocalDecl>;
    FStatements: TArray<TStatement>;
    FEdits: TList<TTextEdit>;
    FCuts: TList<TByteRange>;
    FProblems: TStringList;
    FFormNames: TStringList;
    FReads: TArray<string>; // calculated fields the scanned statement reads (or writes in an assignment kept whole)
    FUsed: TArray<string>;  // every dataset field the kept code names, lower case
    FDead: TList<TByteRange>; // conditions of an if whose branches are all cut: their fields compute nothing kept
    procedure ReadHeader;
    procedure ReadLocals(const pNode: TTSNode; const pKeyword: string);
    procedure ReadDeclarations;
    procedure ReadStatements(const pBlock: TTSNode);
    procedure ReadStatement(const pNode: TTSNode; const pComments: string);
    procedure CollectEffects(const pNode: TTSNode; var pStatement: TStatement);
    procedure AssignEffect(const pNode: TTSNode; var pStatement: TStatement);
    procedure CallEffect(const pNode: TTSNode; var pStatement: TStatement);
    procedure CollectMentions(const pNode: TTSNode; var pStatement: TStatement);
    procedure CollectBare(const pNode: TTSNode; var pStatement: TStatement);
    function FieldOf(const pNode: TTSNode; out pField: TDfmrCodeField): Boolean;
    function FindField(const pComp: string; out pField: TDfmrCodeField): Boolean;
    function FieldByDataName(const pName: string; out pField: TDfmrCodeField): Boolean;
    function ComponentOf(const pNode: TTSNode): string;
    function LastChildText(const pNode: TTSNode): string;
    function IsDatasetName(const pNode: TTSNode): Boolean;
    function LiteralArgument(const pNode: TTSNode; out pName: string): Boolean;
    function FieldNameArgument(const pNode: TTSNode; out pName: string): Boolean;
    function SubscriptField(const pNode: TTSNode; out pName: string): Boolean;
    function TargetField(const pNode: TTSNode): string;
    function IsLocal(const pName: string): Boolean;
    function HasExit(const pNode: TTSNode): Boolean;
    function MovesDataset(const pNode: TTSNode): Boolean;
    function ConditionOf(const pGuard: TTSNode): TTSNode;
    function IsExitGuard(const pNode: TTSNode): Boolean;
    function GuardCondition(const pNode: TTSNode): string;
    procedure Problem(const pText: string);
    procedure AddEdit(const pNode: TTSNode; const pText: string);
    procedure UseField(const pNode: TTSNode; const pField: TDfmrCodeField; const pMember: string = '');
    procedure UseByName(const pNode: TTSNode; const pName, pMember: string);
    procedure ScanDot(const pNode: TTSNode);
    procedure ScanIdentifier(const pNode: TTSNode);
    procedure Scan(const pNode: TTSNode);
    procedure CutOthers(const pNode: TTSNode; const pKeep: string);
    function IsCut(const pNode: TTSNode): Boolean;
    function IsDead(const pNode: TTSNode): Boolean;
    function InDead(const pNode: TTSNode): Boolean;
    function NodeEdited(const pNode: TTSNode): string;
    function EditedText(const pNode: TTSNode): string;
    function RenderStatement(const pStatement: TStatement; pGuards: Boolean): string;
    function Render(pGuards: Boolean): string;
    function InlineDecls: string;
    function Slice(const pField: string): Boolean;
    procedure CheckKept(pCalc: Boolean);
    procedure CheckBare(const pField: string);
    procedure CheckLocals;
    procedure CheckLaterWrites(pIndex: Integer; const pField: string);
    procedure CheckBraces;
    function Finish(const pText: string): TDfmrBody;
  public
    constructor Create(const pSource: TBytes; const pNode: TTSNode; const pContext: TDfmrCodeContext;
      const pStdParams: TArray<string>);
    destructor Destroy; override;
    procedure RefuseDirectives(const pRaw: TBytes);
    function CalcBody(const pField: string): TDfmrBody;
    function EventBody: TDfmrBody;
  end;

const
  CRLF = #13#10;
  INDENT = '  ';
  KEYWORD_CONST = 'const';
  MACRO_OPEN = '{{';
  MACRO_CLOSE = '}}';
  N_PROC = 'defProc';
  N_BLOCK = 'block';
  N_STATEMENT = 'statement';
  N_ASSIGNMENT = 'assignment';
  N_IDENT = 'identifier';
  N_DOT = 'exprDot';
  N_CALL = 'exprCall';
  N_ARGS = 'exprArgs';
  N_SUBSCRIPT = 'exprSubscript';
  N_STRING = 'literalString';
  N_COMMENT = 'comment';
  N_VAR_DEF = 'varAssignDef';
  N_INHERITED = 'inherited';
  N_WITH = 'with';
  N_IF = 'if';
  N_IF_ELSE = 'ifElse';
  KEYWORD_PREFIX = 'k'; // tree-sitter-delphi names keyword nodes kIf, kThen, kBegin, ...
  EXIT_ONLY = '^(exit|begin\s+exit\s*;?\s*end)\s*;?$';
  GUARD_CHILDREN = 4; // kIf, condition, kThen, statement
  PARAM_DATASET = 'DataSet';
  MEMBER_VALUE = 'Value';
  MEMBER_BY_NAME = 'FieldByName';
  MEMBER_VALUES = 'FieldValues';
  MEMBER_AS_VARIANT = 'AsVariant';
  BARE_USE = 'the field component %s itself is used';
  NO_FIELD = '%s has no persistent field';
  PAT_GENERATED = '^DLFR\s+(\S+)\s+hash=[0-9a-f]+$';
  PAT_WRITES = '\b%s\s*\.\s*(\w+\s*:=|Clear\b)';
  LATIN_1 = 28591; // one character per byte: offsets stay byte offsets
  { Functions that move the cursor of a dataset (the procedures that do are statements of their own). }
  MOVERS: array[0..9] of string = ('Locate', 'LocateEx', 'LocateNext', 'FindKey', 'FindFirst', 'FindNext', 'FindLast',
    'FindPrior', 'GotoKey', 'MoveBy');

function NodeText(const pSource: TBytes; const pNode: TTSNode): string;
begin
  Result := TEncoding.UTF8.GetString(pSource, pNode.StartByte, pNode.EndByte - pNode.StartByte);
end;

function FirstNamed(const pNode: TTSNode; const pType: string; out pFound: TTSNode): Boolean;
var
  VI: Integer;
begin
  Result := False;
  pFound := pNode;
  for VI := 0 to Integer(pNode.NamedChildCount) - 1 do
    if pNode.NamedChild(VI).NodeType = pType then
    begin
      pFound := pNode.NamedChild(VI);
      Exit(True);
    end;
end;

procedure AddName(var pList: TArray<string>; const pName: string);
begin
  if not MatchText(pName, pList) then
    pList := pList + [LowerCase(pName)];
end;

{ Names declared before the ':' of a declArg / declVar / declConst. }
function DeclaredNames(const pSource: TBytes; const pNode: TTSNode): TArray<string>;
var
  VI: Integer;
begin
  Result := nil;
  for VI := 0 to Integer(pNode.NamedChildCount) - 1 do
    if pNode.NamedChild(VI).NodeType = N_IDENT then
      Result := Result + [NodeText(pSource, pNode.NamedChild(VI))]
    else if pNode.NamedChild(VI).NodeType = 'type' then
      Break;
end;

{ Every identifier of a node. }
procedure AddIdentifiers(const pSource: TBytes; const pNode: TTSNode; var pList: TArray<string>);
var
  VI: Integer;
begin
  if pNode.NodeType = N_IDENT then
    AddName(pList, NodeText(pSource, pNode));
  for VI := 0 to Integer(pNode.NamedChildCount) - 1 do
    AddIdentifiers(pSource, pNode.NamedChild(VI), pList);
end;

{ THandler }

constructor THandler.Create(const pSource: TBytes; const pNode: TTSNode; const pContext: TDfmrCodeContext;
  const pStdParams: TArray<string>);
begin
  inherited Create;
  FSource := pSource;
  FNode := pNode;
  FContext := pContext;
  FStdParams := pStdParams;
  FEdits := TList<TTextEdit>.Create;
  FCuts := TList<TByteRange>.Create;
  FDead := TList<TByteRange>.Create;
  FProblems := TStringList.Create(dupIgnore, True, False);
  FFormNames := TStringList.Create(dupIgnore, True, False);
  ReadHeader;
  ReadDeclarations;
end;

destructor THandler.Destroy;
begin
  FFormNames.Free;
  FProblems.Free;
  FDead.Free;
  FCuts.Free;
  FEdits.Free;
  inherited;
end;

procedure THandler.Problem(const pText: string);
begin
  FProblems.Add(pText);
end;

{ Preprocessing keeps offsets; a directive blanked out of FSource still shows in the raw text. }
procedure THandler.RefuseDirectives(const pRaw: TBytes);
var
  VText: string;
begin
  if Length(pRaw) <> Length(FSource) then
    Problem('the unit changes length when preprocessed');
  VText := NodeText(if Length(pRaw) = Length(FSource) then pRaw else FSource, FNode);
  if VText.Contains('{$') or VText.Contains('(*$') then
    Problem('the handler holds compiler directives');
end;

procedure THandler.ReadHeader;
var
  VHead, VArgs: TTSNode;
  VI: Integer;
begin
  if (not FirstNamed(FNode, 'declProc', VHead)) or (not FirstNamed(VHead, 'declArgs', VArgs)) then
    Exit;
  for VI := 0 to Integer(VArgs.NamedChildCount) - 1 do
    FParams := FParams + DeclaredNames(FSource, VArgs.NamedChild(VI));
end;

procedure THandler.ReadLocals(const pNode: TTSNode; const pKeyword: string);
var
  VI: Integer;
  VDecl: TLocalDecl;
begin
  for VI := 0 to Integer(pNode.NamedChildCount) - 1 do
  begin
    VDecl.Names := DeclaredNames(FSource, pNode.NamedChild(VI));
    if Length(VDecl.Names) = 0 then
      Continue;
    VDecl.IsConst := pKeyword = KEYWORD_CONST;
    VDecl.Mentions := nil;
    AddIdentifiers(FSource, pNode.NamedChild(VI), VDecl.Mentions);
    VDecl.InlineText := pKeyword + ' ' + NodeText(FSource, pNode.NamedChild(VI)).Trim;
    if not VDecl.InlineText.EndsWith(';') then
      VDecl.InlineText := VDecl.InlineText + ';';
    FLocals := FLocals + [VDecl];
  end;
end;

procedure THandler.ReadDeclarations;
var
  VI: Integer;
  VChild: TTSNode;
begin
  for VI := 0 to Integer(FNode.NamedChildCount) - 1 do
  begin
    VChild := FNode.NamedChild(VI);
    if VChild.NodeType = 'declVars' then
      ReadLocals(VChild, 'var')
    else if VChild.NodeType = 'declConsts' then
      ReadLocals(VChild, KEYWORD_CONST)
    else if VChild.NodeType = N_BLOCK then
      ReadStatements(VChild)
    else if not MatchStr(VChild.NodeType, ['declProc', N_COMMENT]) then
      Problem('the handler declares ' + VChild.NodeType);
  end;
end;

procedure THandler.ReadStatement(const pNode: TTSNode; const pComments: string);
var
  VStatement: TStatement;
begin
  VStatement := Default(TStatement);
  VStatement.Node := pNode;
  VStatement.Comments := pComments;
  VStatement.IsInherited := (pNode.NodeType = N_INHERITED) or
    ((pNode.NodeType = N_STATEMENT) and (pNode.NamedChildCount > 0) and (pNode.NamedChild(0).NodeType = N_INHERITED));
  VStatement.IsGuard := IsExitGuard(pNode);
  CollectEffects(pNode, VStatement);
  CollectMentions(pNode, VStatement);
  CollectBare(pNode, VStatement);
  FStatements := FStatements + [VStatement];
end;

function THandler.HasExit(const pNode: TTSNode): Boolean;
var
  VI: Integer;
begin
  Result := (pNode.NodeType = N_IDENT) and SameText(NodeText(FSource, pNode), 'Exit');
  for VI := 0 to Integer(pNode.NamedChildCount) - 1 do
    Result := Result or HasExit(pNode.NamedChild(VI));
end;

{ True when the node calls a function that moves a dataset. }
function THandler.MovesDataset(const pNode: TTSNode): Boolean;
var
  VI: Integer;
begin
  Result := (pNode.NodeType = N_DOT) and MatchText(LastChildText(pNode), MOVERS);
  for VI := 0 to Integer(pNode.NamedChildCount) - 1 do
    Result := Result or MovesDataset(pNode.NamedChild(VI));
end;

{ `if C then Exit;` or `if C then begin Exit; end;` }
function THandler.IsExitGuard(const pNode: TTSNode): Boolean;
var
  VThen: TTSNode;
begin
  if (pNode.NodeType <> N_IF) or (pNode.NamedChildCount < GUARD_CHILDREN) then
    Exit(False);
  VThen := pNode.NamedChild(pNode.NamedChildCount - 1);
  Result := TRegEx.IsMatch(NodeText(FSource, VThen), EXIT_ONLY, [roIgnoreCase]);
end;

{ The condition of an `if`: the first child after the keyword that is no comment. }
function THandler.ConditionOf(const pGuard: TTSNode): TTSNode;
var
  VI: Integer;
begin
  Result := pGuard.NamedChild(1);
  for VI := 1 to Integer(pGuard.NamedChildCount) - 1 do
    if pGuard.NamedChild(VI).NodeType <> N_COMMENT then
      Exit(pGuard.NamedChild(VI));
end;

{ The condition of an Exit guard, edits applied; on one line unless a // comment may end a line of it. }
function THandler.GuardCondition(const pNode: TTSNode): string;
begin
  Result := NodeEdited(ConditionOf(pNode)).Replace(#13, '');
  Result := Result.Replace(#10, if Result.Contains('//') then CRLF else ' ');
end;

procedure THandler.ReadStatements(const pBlock: TTSNode);
var
  VI, VLast: Integer;
  VChild: TTSNode;
  VComments: string;
begin
  VComments := '';
  for VI := 0 to Integer(pBlock.NamedChildCount) - 1 do
  begin
    VChild := pBlock.NamedChild(VI);
    VLast := High(FStatements);
    if MatchStr(VChild.NodeType, ['kBegin', 'kEnd']) then
      Continue;
    if VChild.NodeType <> N_COMMENT then
    begin
      ReadStatement(VChild, VComments);
      VComments := '';
    end
    else if (VComments = '') and (VLast >= 0) and (FStatements[VLast].Node.EndPoint.row = VChild.StartPoint.row) then
      FStatements[VLast].TrailingComment := ' ' + NodeText(FSource, VChild).Trim
    else
      VComments := VComments + NodeText(FSource, VChild).Trim + CRLF;
  end;
end;

function THandler.IsLocal(const pName: string): Boolean;
var
  VDecl: TLocalDecl;
begin
  Result := False;
  for VDecl in FLocals do
    if MatchText(pName, VDecl.Names) then
      Exit(True);
end;

function THandler.FindField(const pComp: string; out pField: TDfmrCodeField): Boolean;
var
  VField: TDfmrCodeField;
begin
  pField := Default(TDfmrCodeField);
  Result := False;
  for VField in FContext.Fields do
    if (pComp <> '') and SameText(VField.CompName, pComp) then
    begin
      pField := VField;
      Exit(True);
    end;
end;

function THandler.FieldByDataName(const pName: string; out pField: TDfmrCodeField): Boolean;
var
  VField: TDfmrCodeField;
begin
  pField := Default(TDfmrCodeField);
  Result := False;
  for VField in FContext.Fields do
    if SameText(VField.DataName, pName) then
    begin
      pField := VField;
      Exit(True);
    end;
end;

function THandler.LastChildText(const pNode: TTSNode): string;
begin
  Result := NodeText(FSource, pNode.NamedChild(pNode.NamedChildCount - 1));
end;

{ Component name of `Comp` or `Self.Comp`, '' for anything else. }
function THandler.ComponentOf(const pNode: TTSNode): string;
begin
  Result := '';
  if pNode.NodeType = N_IDENT then
    Result := NodeText(FSource, pNode)
  else if (pNode.NodeType = N_DOT) and SameText(NodeText(FSource, pNode.NamedChild(0)), 'Self') then
    Result := LastChildText(pNode);
end;

function THandler.IsDatasetName(const pNode: TTSNode): Boolean;
var
  VName: string;
begin
  VName := ComponentOf(pNode);
  Result := (VName <> '') and SameText(VName, FContext.Dataset);
  if (not Result) and (VName <> '') and (Length(FParams) > 0) and (Length(FStdParams) > 0) then
    Result := SameText(FStdParams[0], PARAM_DATASET) and SameText(VName, FParams[0]);
end;

{ The one string literal argument of a call or a subscript. }
function THandler.LiteralArgument(const pNode: TTSNode; out pName: string): Boolean;
var
  VArgs: TTSNode;
begin
  pName := '';
  Result := FirstNamed(pNode, N_ARGS, VArgs) and (VArgs.NamedChildCount = 1)
    and (VArgs.NamedChild(0).NodeType = N_STRING);
  if Result then
    pName := NodeText(FSource, VArgs.NamedChild(0)).DeQuotedString;
end;

{ `DS.FieldByName('X')`: pName = X. }
function THandler.FieldNameArgument(const pNode: TTSNode; out pName: string): Boolean;
var
  VCallee: TTSNode;
begin
  pName := '';
  Result := (pNode.NodeType = N_CALL) and FirstNamed(pNode, N_DOT, VCallee)
    and SameText(LastChildText(VCallee), MEMBER_BY_NAME) and IsDatasetName(VCallee.NamedChild(0))
    and LiteralArgument(pNode, pName);
end;

{ `DS['X']` / `DS.FieldValues['X']`: pName = X. }
function THandler.SubscriptField(const pNode: TTSNode; out pName: string): Boolean;
var
  VBase: TTSNode;
begin
  pName := '';
  if (pNode.NodeType <> N_SUBSCRIPT) or (pNode.NamedChildCount = 0) then
    Exit(False);
  VBase := pNode.NamedChild(0);
  if (VBase.NodeType = N_DOT) and SameText(LastChildText(VBase), MEMBER_VALUES) then
    VBase := VBase.NamedChild(0);
  Result := IsDatasetName(VBase) and LiteralArgument(pNode, pName);
end;

{ Component name of the dataset field an assignment target (or the object of a Clear call) writes, '' = none. }
function THandler.TargetField(const pNode: TTSNode): string;
var
  VField: TDfmrCodeField;
  VName: string;
begin
  Result := '';
  if SubscriptField(pNode, VName) or ((pNode.NodeType = N_DOT) and FieldNameArgument(pNode.NamedChild(0), VName)) then
  begin
    if FieldByDataName(VName, VField) then
      Result := VField.CompName;
  end
  else if (pNode.NodeType = N_DOT) and FindField(ComponentOf(pNode.NamedChild(0)), VField) then
    Result := VField.CompName;
end;

procedure THandler.AssignEffect(const pNode: TTSNode; var pStatement: TStatement);
var
  VTarget, VIdent: TTSNode;
  VField: TDfmrCodeField;
  VDecl: TLocalDecl;
begin
  VTarget := pNode.NamedChild(0);
  if FindField(TargetField(VTarget), VField) and VField.IsCalc then
    AddName(pStatement.Fields, VField.CompName)
  else if VTarget.NodeType = N_VAR_DEF then
  begin
    { an inline variable: a local from here on, its declaration is the statement itself }
    if not FirstNamed(VTarget, N_IDENT, VIdent) then
      Exit;
    VDecl := Default(TLocalDecl);
    VDecl.Names := [NodeText(FSource, VIdent)];
    if not IsLocal(VDecl.Names[0]) then
      FLocals := FLocals + [VDecl];
    AddName(pStatement.Locals, VDecl.Names[0]);
  end
  else if (VTarget.NodeType = N_IDENT) and IsLocal(NodeText(FSource, VTarget)) then
    AddName(pStatement.Locals, NodeText(FSource, VTarget))
  else
    pStatement.Other := True;
end;

{ A call statement: a method of a calculated field (Clear, Assign, ...) writes that field, anything else is an unknown
  effect. }
procedure THandler.CallEffect(const pNode: TTSNode; var pStatement: TStatement);
var
  VCall: TTSNode;
  VField: TDfmrCodeField;
begin
  if pNode.NamedChildCount = 0 then
    Exit;
  VCall := pNode.NamedChild(0);
  if VCall.NodeType = N_CALL then
    VCall := VCall.NamedChild(0);
  if (VCall.NodeType = N_DOT) and FindField(TargetField(VCall), VField) and VField.IsCalc then
    AddName(pStatement.Fields, VField.CompName)
  else if not pStatement.IsInherited then
    pStatement.Other := True;
end;

procedure THandler.CollectEffects(const pNode: TTSNode; var pStatement: TStatement);
var
  VI: Integer;
begin
  if pNode.NodeType = N_ASSIGNMENT then
    AssignEffect(pNode, pStatement)
  else if pNode.NodeType = N_STATEMENT then
    CallEffect(pNode, pStatement)
  else if MatchStr(pNode.NodeType, ['raise', 'goto', 'label', 'asm', 'lambda'])
    or ((pNode.NodeType = N_DOT) and MatchText(LastChildText(pNode), MOVERS)) then
    pStatement.Other := True;
  for VI := 0 to Integer(pNode.NamedChildCount) - 1 do
    CollectEffects(pNode.NamedChild(VI), pStatement);
end;

procedure THandler.CollectMentions(const pNode: TTSNode; var pStatement: TStatement);
var
  VI: Integer;
begin
  if (pNode.NodeType = N_IDENT) and IsLocal(NodeText(FSource, pNode)) then
    AddName(pStatement.Mentions, NodeText(FSource, pNode));
  for VI := 0 to Integer(pNode.NamedChildCount) - 1 do
    CollectMentions(pNode.NamedChild(VI), pStatement);
end;

{ The field a node is as a whole: `Comp`, `Self.Comp` or `DS.FieldByName('X')`. }
function THandler.FieldOf(const pNode: TTSNode; out pField: TDfmrCodeField): Boolean;
var
  VName: string;
begin
  Result := if FieldNameArgument(pNode, VName) then FieldByDataName(VName, pField) else FindField(ComponentOf(pNode), pField);
end;

{ Calculated fields used as a whole: the code they are handed to may write them. }
procedure THandler.CollectBare(const pNode: TTSNode; var pStatement: TStatement);
var
  VI, VLast: Integer;
  VField: TDfmrCodeField;
begin
  if FieldOf(pNode, VField) then
  begin
    if VField.IsCalc then
      AddName(pStatement.Bare, VField.CompName);
    Exit;
  end;
  if (pNode.NodeType = N_DOT) and FieldOf(pNode.NamedChild(0), VField) then
    Exit;
  VLast := if pNode.NodeType = N_DOT then 0 else Integer(pNode.NamedChildCount) - 1;
  for VI := 0 to VLast do
    CollectBare(pNode.NamedChild(VI), pStatement);
end;

procedure THandler.AddEdit(const pNode: TTSNode; const pText: string);
var
  VEdit: TTextEdit;
begin
  VEdit.Range.First := pNode.StartByte;
  VEdit.Range.Last := pNode.EndByte;
  VEdit.NewText := pText;
  FEdits.Add(VEdit);
end;

function THandler.IsCut(const pNode: TTSNode): Boolean;
var
  VRange: TByteRange;
begin
  Result := False;
  for VRange in FCuts do
    if (Integer(pNode.StartByte) >= VRange.First) and (Integer(pNode.EndByte) <= VRange.Last) then
      Exit(True);
end;

{ Cuts the assignments to (and method calls on) calculated fields other than pKeep; the semicolon stays, so every
  construct around a cut stays well formed. }
procedure THandler.CutOthers(const pNode: TTSNode; const pKeep: string);
var
  VI: Integer;
  VRange: TByteRange;
  VEffect: TStatement;
  VCut: TTSNode;
begin
  VEffect := Default(TStatement);
  VCut := pNode;
  if pNode.NodeType = N_ASSIGNMENT then
    AssignEffect(pNode, VEffect)
  else if (pNode.NodeType = N_STATEMENT) and (pNode.NamedChildCount > 0) then
  begin
    CallEffect(pNode, VEffect);
    VCut := pNode.NamedChild(0);
  end;
  if (Length(VEffect.Fields) = 1) and (not SameText(VEffect.Fields[0], pKeep)) and (not MovesDataset(pNode)) then
  begin
    VRange.First := VCut.StartByte;
    VRange.Last := VCut.EndByte;
    FCuts.Add(VRange);
    AddEdit(VCut, '');
    Exit;
  end;
  for VI := 0 to Integer(pNode.NamedChildCount) - 1 do
    CutOthers(pNode.NamedChild(VI), pKeep);
  if MatchStr(pNode.NodeType, [N_IF, N_IF_ELSE]) and (pNode.NamedChildCount > 1) and IsDead(pNode) then
  begin
    VCut := ConditionOf(pNode);
    VRange.First := VCut.StartByte;
    VRange.Last := VCut.EndByte;
    FDead.Add(VRange);
  end;
end;

{ True when nothing of pNode is left to run: it is cut, a keyword or a comment, or all its parts are; an `if` whose
  branches are all dead is dead, whatever its condition. }
function THandler.IsDead(const pNode: TTSNode): Boolean;
var
  VI: Integer;
  VCondition: TTSNode;
  VIf: Boolean;
begin
  if IsCut(pNode) or (pNode.NodeType = N_COMMENT) or pNode.NodeType.StartsWith(KEYWORD_PREFIX) then
    Exit(True);
  if pNode.NamedChildCount = 0 then
    Exit(False);
  VIf := MatchStr(pNode.NodeType, [N_IF, N_IF_ELSE]);
  VCondition := if VIf then ConditionOf(pNode) else pNode;
  for VI := 0 to Integer(pNode.NamedChildCount) - 1 do
    if not (VIf and (pNode.NamedChild(VI).StartByte = VCondition.StartByte)) and (not IsDead(pNode.NamedChild(VI))) then
      Exit(False);
  Result := True;
end;

function THandler.InDead(const pNode: TTSNode): Boolean;
var
  VRange: TByteRange;
begin
  Result := False;
  for VRange in FDead do
    if (Integer(pNode.StartByte) >= VRange.First) and (Integer(pNode.EndByte) <= VRange.Last) then
      Exit(True);
end;

{ pNode is the field component; pMember is what the macro needs behind it to mean the same. }
procedure THandler.UseField(const pNode: TTSNode; const pField: TDfmrCodeField; const pMember: string);
begin
  if pField.IsCalc then
    AddName(FReads, pField.CompName);
  if not InDead(pNode) then
    AddName(FUsed, pField.CompName);
  if pField.MacroName = '' then
    Problem(pField.CompName + ' is not a field of the dataset''s table')
  else
    AddEdit(pNode, MACRO_OPEN + pField.MacroName + MACRO_CLOSE + (if pMember = '' then '' else '.' + pMember));
end;

procedure THandler.UseByName(const pNode: TTSNode; const pName, pMember: string);
var
  VField: TDfmrCodeField;
begin
  if FieldByDataName(pName, VField) then
    UseField(pNode, VField, pMember)
  else
    Problem(Format(NO_FIELD, [if pNode.NodeType = N_SUBSCRIPT then NodeText(FSource, pNode) else MEMBER_BY_NAME + '(''' + pName + ''')']));
end;

procedure THandler.ScanDot(const pNode: TTSNode);
var
  VBase: TTSNode;
  VField: TDfmrCodeField;
  VName: string;
begin
  VBase := pNode.NamedChild(0);
  { FieldByName gives a TField: its Value is a Variant, the Value of a typed component is not }
  if FieldNameArgument(VBase, VName) and SameText(LastChildText(pNode), MEMBER_VALUE) then
    UseByName(pNode, VName, MEMBER_AS_VARIANT)
  else if FindField(ComponentOf(pNode), VField) then
    UseField(pNode, VField)
  else if FindField(ComponentOf(VBase), VField) then
    UseField(VBase, VField)
  else if ComponentOf(pNode) <> '' then
    ScanIdentifier(pNode.NamedChild(pNode.NamedChildCount - 1))
  else
    Scan(VBase);
end;

procedure THandler.ScanIdentifier(const pNode: TTSNode);
var
  VField: TDfmrCodeField;
  VName: string;
  VI: Integer;
begin
  VName := NodeText(FSource, pNode);
  VI := IndexText(VName, FParams);
  if (VI >= 0) and (VI < Length(FStdParams)) and (not SameText(VName, FStdParams[VI])) then
    AddEdit(pNode, FStdParams[VI]);
  if (VI >= 0) or IsLocal(VName) then
    Exit;
  if FindField(VName, VField) then
    UseField(pNode, VField)
  else if MatchText(VName, FContext.Components) then
    FFormNames.Add(VName);
end;

procedure THandler.Scan(const pNode: TTSNode);
var
  VI: Integer;
  VName, VType: string;
begin
  VType := pNode.NodeType;
  if IsCut(pNode) or MatchStr(VType, [N_STRING, N_COMMENT]) then
    Exit;
  if VType = N_DOT then
    ScanDot(pNode)
  else if VType = N_IDENT then
    ScanIdentifier(pNode)
  else if SubscriptField(pNode, VName) then
    UseByName(pNode, VName, MEMBER_AS_VARIANT)
  else if FieldNameArgument(pNode, VName) then
    UseByName(pNode, VName, '')
  else
  begin
    if VType = N_WITH then
      Problem('a with statement');
    for VI := 0 to Integer(pNode.NamedChildCount) - 1 do
      Scan(pNode.NamedChild(VI));
  end;
end;

{ The source of a node with the edits inside it applied. }
function THandler.NodeEdited(const pNode: TTSNode): string;
var
  VPos, VLast: Integer;
  VEdit: TTextEdit;
begin
  VPos := pNode.StartByte;
  VLast := pNode.EndByte;
  Result := '';
  for VEdit in FEdits do
    if (VEdit.Range.First >= VPos) and (VEdit.Range.Last <= VLast) then
    begin
      Result := Result + TEncoding.UTF8.GetString(FSource, VPos, VEdit.Range.First - VPos) + VEdit.NewText;
      VPos := VEdit.Range.Last;
    end;
  Result := Result + TEncoding.UTF8.GetString(FSource, VPos, VLast - VPos);
end;

{ True for the lone semicolon a cut leaves behind a complete statement or a block opener. }
function IsCutRest(const pLine, pBefore: string): Boolean;
begin
  Result := (Trim(pLine) = ';') and (EndsText(';', TrimRight(pBefore)) or EndsText('begin', TrimRight(pBefore)));
end;

{ A statement as it stands in the body: edits applied, its own indentation taken off its continuation lines. }
function THandler.EditedText(const pNode: TTSNode): string;
var
  VLine, VBefore, VText: string;
  VLines: TStringList;
  VIndent: Integer;
begin
  VIndent := pNode.StartPoint.column;
  VLines := TStringList.Create;
  try
    VLines.LineBreak := CRLF;
    VBefore := '';
    for VLine in NodeEdited(pNode).Replace(#13, '').Split([#10]) do
    begin
      VText := VLine;
      if VLines.Count > 0 then
        VText := if Trim(Copy(VLine, 1, VIndent)) = '' then Copy(VLine, VIndent + 1, MaxInt) else TrimLeft(VLine);
      if not IsCutRest(VText, VBefore) then
        VLines.Add(VText);
      VBefore := VText;
    end;
    Result := TrimRight(VLines.Text);
  finally
    VLines.Free;
  end;
end;

function THandler.InlineDecls: string;
var
  VDecl: TLocalDecl;
  VStatement: TStatement;
  VName: string;
  VMentions: TArray<string>;
  VNeeded: Boolean;
  VI: Integer;
begin
  Result := '';
  VMentions := nil;
  for VStatement in FStatements do
    if VStatement.Kept then
      VMentions := VMentions + VStatement.Mentions;
  { backwards: a declaration may need the ones above it }
  for VI := High(FLocals) downto 0 do
  begin
    VDecl := FLocals[VI];
    VNeeded := False;
    for VName in VDecl.Names do
      VNeeded := VNeeded or MatchText(VName, VMentions);
    if VNeeded and (VDecl.InlineText <> '') then
    begin
      Result := VDecl.InlineText + CRLF + Result;
      VMentions := VMentions + VDecl.Mentions;
    end;
  end;
end;

{ One kept statement with its comments; an Exit guard opens a block that Render closes at the end. }
function THandler.RenderStatement(const pStatement: TStatement; pGuards: Boolean): string;
begin
  if pGuards and pStatement.IsGuard then
    Exit(pStatement.Comments + 'if not (' + GuardCondition(pStatement.Node) + ') then' + CRLF + 'begin' + pStatement.TrailingComment);
  Result := EditedText(pStatement.Node);
  if not Result.EndsWith(';') then
    Result := Result + ';';
  Result := pStatement.Comments + Result + pStatement.TrailingComment;
end;

function THandler.Render(pGuards: Boolean): string;
var
  VI, VDepth: Integer;
  VText: string;
begin
  FEdits.Sort(TComparer<TTextEdit>.Construct(
    function(const pLeft, pRight: TTextEdit): Integer
    begin
      Result := pLeft.Range.First - pRight.Range.First;
    end));
  Result := InlineDecls;
  VDepth := 0;
  for VI := 0 to High(FStatements) do
    if FStatements[VI].Kept then
    begin
      VText := RenderStatement(FStatements[VI], pGuards);
      Result := Result + DupeString(INDENT, VDepth) + VText.Replace(CRLF, CRLF + DupeString(INDENT, VDepth)) + CRLF;
      if pGuards and FStatements[VI].IsGuard then
        Inc(VDepth);
    end;
  for VI := VDepth - 1 downto 0 do
    Result := Result + DupeString(INDENT, VI) + 'end;' + CRLF;
  Result := TrimRight(Result);
end;

{ The top-level statements field pField needs, backwards from the last one that assigns it; False = none does. }
function THandler.Slice(const pField: string): Boolean;
var
  VI: Integer;
  VNeeded: TArray<string>;
  VName: string;
  VKeep: Boolean;
begin
  Result := False;
  VNeeded := nil;
  for VI := High(FStatements) downto 0 do
  begin
    VKeep := MatchText(pField, FStatements[VI].Fields);
    if Result and (not VKeep) then
    begin
      VKeep := FStatements[VI].Other;
      for VName in FStatements[VI].Locals do
        VKeep := VKeep or MatchText(VName, VNeeded);
    end;
    Result := Result or VKeep;
    FStatements[VI].Kept := VKeep;
    if VKeep then
      for VName in FStatements[VI].Mentions do
        AddName(VNeeded, VName);
  end;
end;

{ Statements that cannot stand in generated code; a top-level `inherited` is dropped. }
procedure THandler.CheckKept(pCalc: Boolean);
var
  VI: Integer;
begin
  for VI := 0 to High(FStatements) do
  begin
    FStatements[VI].Kept := FStatements[VI].Kept and (not FStatements[VI].IsInherited);
    if not FStatements[VI].Kept then
      Continue;
    if pCalc and (not FStatements[VI].IsGuard) and HasExit(FStatements[VI].Node) then
      Problem('Exit would skip the other generated calculations');
  end;
  if FNode.HasError then
    Problem('the handler does not parse');
end;

{ Refuses a calculated field's component that other code gets: that code may write the field. pField's own counts
  anywhere in the handler, another one's in the statements of the body. }
procedure THandler.CheckBare(const pField: string);
var
  VStatement: TStatement;
  VField: TDfmrCodeField;
  VName: string;
begin
  for VStatement in FStatements do
    for VName in VStatement.Bare do
      if (VStatement.Kept or SameText(VName, pField)) and FindField(VName, VField) then
        Problem(Format(BARE_USE, [VField.CompName]));
end;

{ Refuses a needed variable no kept statement sets while an earlier dropped one names it (a var argument). }
procedure THandler.CheckLocals;
var
  VDecl: TLocalDecl;
  VStatement: TStatement;
  VName: string;
  VNamed, VSet, VDropped: Boolean;
begin
  for VDecl in FLocals do
    for VName in VDecl.Names do
    begin
      VNamed := False;
      VSet := VDecl.IsConst;
      VDropped := False;
      for VStatement in FStatements do
        if not MatchText(VName, VStatement.Mentions) then
          Continue
        else if VStatement.Kept then
        begin
          VSet := VSet or MatchText(VName, VStatement.Locals) or ((not VNamed) and VStatement.Other);
          VNamed := True;
        end
        else
          VDropped := VDropped or (not VNamed);
      if VNamed and VDropped and (not VSet) then
        Problem('the local ' + VName + ' may be set by a statement left out');
    end;
end;

{ Refuses a calculated field that statement pIndex reads (FReads) and a later one assigns: the macro is its final value. }
procedure THandler.CheckLaterWrites(pIndex: Integer; const pField: string);
var
  VI: Integer;
  VName: string;
begin
  for VName in FReads do
    for VI := pIndex + 1 to High(FStatements) do
      if (not SameText(VName, pField)) and MatchText(VName, FStatements[VI].Fields) then
        Problem(UpperCase(VName) + ' changes after this body reads it');
end;

{ Refuses source text a reader of the body would take for a macro. }
procedure THandler.CheckBraces;
var
  VStatement: TStatement;
begin
  for VStatement in FStatements do
    if VStatement.Kept
      and (VStatement.Comments + NodeText(FSource, VStatement.Node) + VStatement.TrailingComment).Contains(MACRO_OPEN) then
      Problem('the code holds ' + MACRO_OPEN);
end;

function THandler.Finish(const pText: string): TDfmrBody;
begin
  CheckBraces;
  Result.Text := pText;
  Result.Blocked := string.Join('; ', FProblems.ToStringArray);
  Result.FormNames := FFormNames.ToStringArray;
  Result.FieldsUsed := FUsed;
end;

function THandler.CalcBody(const pField: string): TDfmrBody;
var
  VI: Integer;
begin
  if not Slice(pField) then
    Exit(Default(TDfmrBody));
  CheckKept(True);
  CheckBare(pField);
  CheckLocals;
  for VI := 0 to High(FStatements) do
    if FStatements[VI].Kept then
    begin
      FReads := nil;
      CutOthers(FStatements[VI].Node, pField);
      Scan(FStatements[VI].Node);
      CheckLaterWrites(VI, pField);
    end;
  Result := Finish(Render(True));
end;

function THandler.EventBody: TDfmrBody;
var
  VI: Integer;
  VStatement: TStatement;
begin
  for VI := 0 to High(FStatements) do
    FStatements[VI].Kept := True;
  CheckKept(False);
  for VStatement in FStatements do
    if VStatement.Kept then
      Scan(VStatement.Node);
  Result := Finish(Render(False));
end;

{ TDfmrUnit }

constructor TDfmrUnit.Create(const pFile: string);
begin
  inherited Create;
  FRaw := EnsureUtf8Bytes(TFile.ReadAllBytes(pFile));
  Parse(pFile);
end;

constructor TDfmrUnit.CreateFromText(const pText, pFileName: string);
begin
  inherited Create;
  FRaw := TEncoding.UTF8.GetBytes(pText);
  Parse(pFileName);
end;

destructor TDfmrUnit.Destroy;
begin
  FTree.Free;
  inherited;
end;

{ Blanks the generated regions: their code came from the repository. The semicolon a region starts with, which ends the
  hand code before it, stays. A region the engine cannot trust stays, and its
  directive blocks the handler around it. }
procedure TDfmrUnit.BlankRegions;
var
  VText, VReason: string;
  VDirective: TPasDirective;
  VMatch: TMatch;
  VRegion: TDlfrRegion;
  VItem: TGenerated;
  VI, VFirst: Integer;
  VLatin: TEncoding;
begin
  VLatin := TEncoding.GetEncoding(LATIN_1);
  try
    VText := VLatin.GetString(FRaw);
  finally
    VLatin.Free;
  end;
  if not VText.Contains('DLFR ') then
    Exit;
  for VDirective in ScanPascal(VText).Directives do
  begin
    VMatch := TRegEx.Match(VDirective.RegionName, PAT_GENERATED);
    if (not VMatch.Success) or (FindDlfrRegion(VText, VMatch.Groups[1].Value, VRegion, VReason) not in [drsIntact, drsEdited]) then
      Continue;
    VItem.Id := VRegion.Id;
    VItem.First := VRegion.Start.Start - 1;
    VItem.Text := Copy(VText, VRegion.Start.Start, VRegion.Finish.Finish - VRegion.Start.Start);
    FRegions := FRegions + [VItem];
    for VI := VRegion.Start.Start to VRegion.Finish.Finish - 1 do
      if not CharInSet(VText[VI], [#13, #10]) then
        FRaw[VI - 1] := Ord(' ');
    VFirst := VRegion.Body.First;
    while (VFirst < VRegion.Body.Last) and (VText[VFirst] <= ' ') do
      Inc(VFirst);
    if (VFirst < VRegion.Body.Last) and (VText[VFirst] = ';') then
      FRaw[VFirst - 1] := Ord(';');
  end;
end;

{ The region of a handler that holds the code of pField ('' = any region); '' = none. }
function TDfmrUnit.GeneratedIn(const pNode: TTSNode; const pField: string): string;
var
  VItem: TGenerated;
begin
  Result := '';
  for VItem in FRegions do
    if (VItem.First >= Integer(pNode.StartByte)) and (VItem.First < Integer(pNode.EndByte))
      and ((pField = '') or TRegEx.IsMatch(VItem.Text, Format(PAT_WRITES, [pField]), [roIgnoreCase])) then
      Exit('its code is in the generated region DLFR ' + VItem.Id);
end;

procedure TDfmrUnit.Parse(const pFile: string);
begin
  BlankRegions;
  FSource := TAstParseCache.ApplyPreprocess(FRaw, pFile);
  FTree := ParseDelphiUtf8(FSource, pFile);
end;

{ Every implementation of pQualified (`TForm.Method`). }
procedure FindMethods(const pSource: TBytes; const pNode: TTSNode; const pQualified: string; pList: TList<TTSNode>);
var
  VI: Integer;
  VHead, VName: TTSNode;
begin
  if pNode.NodeType = N_PROC then
  begin
    if FirstNamed(pNode, 'declProc', VHead) and FirstNamed(VHead, 'genericDot', VName)
      and SameText(NodeText(pSource, VName).Replace(' ', ''), pQualified) then
      pList.Add(pNode);
    Exit;
  end;
  for VI := 0 to Integer(pNode.NamedChildCount) - 1 do
    FindMethods(pSource, pNode.NamedChild(VI), pQualified, pList);
end;

{ '' and the handler, or the reason it is not read; pField as GeneratedIn. }
function TDfmrUnit.FindHandler(const pContext: TDfmrCodeContext; const pHandler, pField: string; out pNode: TTSNode): string;
var
  VList: TList<TTSNode>;
  VQualified: string;
begin
  VQualified := pContext.FormClass + '.' + pHandler;
  pNode := FTree.RootNode;
  VList := TList<TTSNode>.Create;
  try
    FindMethods(FSource, FTree.RootNode, VQualified, VList);
    if VList.Count <> 1 then
      Exit(VQualified + (if VList.Count = 0 then ' is not in the unit' else ' is in the unit more than once'));
    pNode := VList[0];
    Result := GeneratedIn(pNode, pField);
  finally
    VList.Free;
  end;
end;

function TDfmrUnit.CalcBody(const pContext: TDfmrCodeContext; const pHandler, pField: string): TDfmrBody;
var
  VHandler: THandler;
  VNode: TTSNode;
begin
  Result := Default(TDfmrBody);
  Result.Blocked := FindHandler(pContext, pHandler, pField, VNode);
  if Result.Blocked <> '' then
    Exit;
  VHandler := THandler.Create(FSource, VNode, pContext, [PARAM_DATASET]);
  try
    VHandler.RefuseDirectives(FRaw);
    Result := VHandler.CalcBody(pField);
  finally
    VHandler.Free;
  end;
end;

function TDfmrUnit.EventBody(const pContext: TDfmrCodeContext; const pHandler: string;
  const pParams: TArray<string>): TDfmrBody;
var
  VHandler: THandler;
  VNode: TTSNode;
begin
  Result := Default(TDfmrBody);
  Result.Blocked := FindHandler(pContext, pHandler, '', VNode);
  if Result.Blocked <> '' then
    Exit;
  VHandler := THandler.Create(FSource, VNode, pContext, pParams);
  try
    VHandler.RefuseDirectives(FRaw);
    Result := VHandler.EventBody;
  finally
    VHandler.Free;
  end;
end;

end.
