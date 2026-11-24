unit DRagLint.FieldRepo.Handlers;

{ drag-lint 1.54 -- lane TT-HANDLERS: code generated from the repository into DLFR regions (design
  2026-11-22-field-repository-v2-design.md section 9).

  Handlers: the bodies of a dataset's calculated fields go into the OnCalcFields handler the DFM names, the stored code
  of a field event (OnGetText, OnSetText, OnValidate, OnChange) into the handler of that event. A macro names the field
  COMPONENT of the dataset; the body carries the member (QTY macro + .AsFloat, ID macro + .IsNull). A new region goes to
  the END of the handler; an existing one is replaced where it stands, so hand code before and after it survives. A
  handler is never created and an event never assigned: both are reported. Code the handler already holds by hand,
  statement for statement, is not generated again.

  MAXLEN: the declared lengths of a table's string columns go into region 2a of its interface unit, behind section 2.

  Every edit is checked on the resulting text (same methods, handler still parses, region intact, a second run changes
  nothing); an edit that fails the check is refused and the text stays as it was. }

interface

uses
  System.SysUtils,
  FireDAC.Comp.Client;

type
  /// <summary>A persistent field of the dataset a handler belongs to.</summary>
  TFrhField = record
    /// <summary>Repository FIELD_NAME; '' = not a field of the dataset's table.</summary>
    Column: string;
    /// <summary>Component name.</summary>
    CompName: string;
    /// <summary>True for calc and internal-calc fields.</summary>
    IsCalc: Boolean;
    /// <summary>CALC_BODY to generate; '' = nothing.</summary>
    Body: string;
  end;

  /// <summary>One stored body, wherever the repository keeps it.</summary>
  TFrhBody = record
    /// <summary>Field name.</summary>
    Field: string;
    /// <summary>OnCalcFields, OnGetText, OnSetText, OnValidate or OnChange.</summary>
    Event: string;
    /// <summary>Pascal statements with field macros.</summary>
    Body: string;
  end;

  /// <summary>One region to bring up to date in one method.</summary>
  TFrhJob = record
    /// <summary>Region id, e.g. tblOrders.OnCalcFields.</summary>
    RegionId: string;
    /// <summary>Qualified method, e.g. TfrmOrders.tblOrdersCalcFields.</summary>
    Method: string;
    /// <summary>Parameter names the stored code uses, in order.</summary>
    StdParams: TArray<string>;
    /// <summary>Lines of the region without the handler's indentation, CRLF; '' = the region has nothing to hold.</summary>
    Content: string;
    /// <summary>Components the content assigns: hand code that assigns one too is noted.</summary>
    Assigns: TArray<string>;
  end;

  /// <summary>What happens to one region.</summary>
  /// <remarks>fhsSkipped = the form or the repository does not ask for it; fhsRefused = it is wanted and not written.</remarks>
  TFrhState = (fhsUnchanged, fhsInserted, fhsUpdated, fhsSkipped, fhsRefused);

  /// <summary>One region of a plan.</summary>
  TFrhItem = record
    /// <summary>Region id.</summary>
    RegionId: string;
    /// <summary>Method or table the region belongs to.</summary>
    Target: string;
    /// <summary>What happens to it.</summary>
    State: TFrhState;
    /// <summary>Why, for skipped and refused.</summary>
    Reason: string;
    /// <summary>Facts to look at.</summary>
    Notes: TArray<string>;
  end;

  /// <summary>Declared length of a string column.</summary>
  TFrhLength = record
    /// <summary>Column name.</summary>
    Column: string;
    /// <summary>Characters.</summary>
    Length: Integer;
  end;

  /// <summary>The planned change of one unit.</summary>
  TFrhPlan = record
    /// <summary>Full path of the unit.</summary>
    FileName: string;
    /// <summary>Text as read; '' when the unit could not be read.</summary>
    OldText: string;
    /// <summary>Text to write; equal to OldText when nothing changes.</summary>
    NewText: string;
    /// <summary>One entry per region.</summary>
    Items: TArray<TFrhItem>;
  end;

const
  /// <summary>Region id of the MAXLEN constants.</summary>
  FRH_MAXLEN_ID = '2a';

/// <summary>Text of an OnCalcFields region: one block per field with a body, after the fields it reads.</summary>
/// <param name="pFields">Every persistent field of the dataset, in DFM order.</param>
/// <param name="pContent">Receives the lines (CRLF); '' when no field has a body.</param>
/// <param name="pReason">Receives why nothing can be generated.</param>
/// <returns>False for a dependency cycle, a field the dataset does not have or has twice, a body that is not ASCII,
/// holds a directive, or leaves a comment or string open.</returns>
/// <remarks>A field that reads itself is no cycle.</remarks>
function CalcRegionContent(const pFields: TArray<TFrhField>; out pContent, pReason: string): Boolean;  // dl:ok unused-public-symbol@2b43 -- REVIEWED 2026-11-23 TT-HANDLERS: pure part of the generator, asserted directly by tests/fieldrepo/HandlersTests.dpr; outside this project index

/// <summary>Text of a field-event region.</summary>
/// <param name="pFields">Persistent fields of the dataset.</param>
/// <param name="pBody">Stored code with field macros.</param>
/// <param name="pContent">Receives the lines (CRLF).</param>
/// <param name="pReason">Receives why nothing can be generated.</param>
/// <returns>False as CalcRegionContent.</returns>
function EventRegionContent(const pFields: TArray<TFrhField>; const pBody: string; out pContent, pReason: string): Boolean;  // dl:ok unused-public-symbol@2823 -- REVIEWED 2026-11-23 TT-HANDLERS: pure part of the generator, asserted directly by tests/fieldrepo/HandlersTests.dpr; outside this project index

/// <summary>The parameter names stored code of a field event uses.</summary>
/// <param name="pEvent">Event name.</param>
/// <returns>Comma-separated, in the order of the event type; '' for another event.</returns>
function FieldEventParams(const pEvent: string): string;  // dl:ok unused-public-symbol@57e8 -- REVIEWED 2026-11-23 TT-HANDLERS: pure part of the generator, asserted directly by tests/fieldrepo/HandlersTests.dpr; outside this project index

/// <summary>Tests whether a handler runs some code by hand.</summary>
/// <param name="pText">Unit text.</param>
/// <param name="pFile">Unit path.</param>
/// <param name="pJob">Names the handler and the region (the region itself is not hand code).</param>
/// <param name="pCode">Statements without macros.</param>
/// <returns>True when consecutive top-level statements of the handler are that code, blanks between words and comments
/// aside.</returns>
function HandlerHoldsCode(const pText, pFile: string; const pJob: TFrhJob; const pCode: string): Boolean;  // dl:ok unused-public-symbol@e9d0 -- REVIEWED 2026-11-23 TT-HANDLERS: pure part of the generator, asserted directly by tests/fieldrepo/HandlersTests.dpr; outside this project index

/// <summary>Brings one region of one handler up to date.</summary>
/// <param name="pText">Unit text.</param>
/// <param name="pFile">Unit path (what the preprocessor sees).</param>
/// <param name="pJob">What to write.</param>
/// <param name="pItem">Receives the outcome.</param>
/// <returns>The new text; pText itself unless the state is fhsInserted or fhsUpdated.</returns>
/// <remarks>Refused: a hand-edited region, a region outside its handler, a missing or repeated or conditional handler,
/// content that does not parse inside it, a unit that is not ASCII.</remarks>
function ApplyHandlerJob(const pText, pFile: string; const pJob: TFrhJob; out pItem: TFrhItem): string;  // dl:ok unused-public-symbol@bbd5 -- REVIEWED 2026-11-23 TT-HANDLERS: pure part of the generator, asserted directly by tests/fieldrepo/HandlersTests.dpr; outside this project index

/// <summary>Brings the MAXLEN region of an interface unit up to date.</summary>
/// <param name="pText">Unit text.</param>
/// <param name="pTable">Table name.</param>
/// <param name="pColumns">Its string columns, in the order to write.</param>
/// <param name="pItem">Receives the outcome; a constant the unit declares by hand is left out and noted when it differs.</param>
/// <returns>The new text; pText itself unless the state is fhsInserted or fhsUpdated.</returns>
function ApplyMaxLen(const pText, pTable: string; const pColumns: TArray<TFrhLength>; out pItem: TFrhItem): string;  // dl:ok unused-public-symbol@58b1 -- REVIEWED 2026-11-23 TT-HANDLERS: pure part of the generator, asserted directly by tests/fieldrepo/HandlersTests.dpr; outside this project index

/// <summary>Plans the handler regions of a form unit.</summary>
/// <param name="pRepo">Open repository, schema 3.</param>
/// <param name="pDfm">DFM path; the unit is the .pas beside it.</param>
/// <param name="pDataset">Dataset component to limit the plan to; '' = all.</param>
/// <returns>The plan; nothing is written.</returns>
/// <exception cref="EDfmReadError">The DFM cannot be read, or has no such dataset.</exception>
/// <exception cref="EDlfrError">The unit does not exist or is not ASCII.</exception>
/// <exception cref="ERepoError">The repository is schema 1 or 2.</exception>
function PlanHandlers(pRepo: TFDConnection; const pDfm, pDataset: string): TFrhPlan;

/// <summary>Plans the MAXLEN region of a table's interface unit.</summary>
/// <param name="pRepo">Open repository with schema facts.</param>
/// <param name="pFile">The interface unit.</param>
/// <param name="pTable">Table name.</param>
/// <returns>The plan; nothing is written.</returns>
/// <exception cref="EDlfrError">The unit does not exist or is not ASCII.</exception>
function PlanMaxLen(pRepo: TFDConnection; const pFile, pTable: string): TFrhPlan;

implementation

uses
  System.StrUtils,
  Data.DB,
  System.Generics.Collections,
  System.RegularExpressions,
  TreeSitter,
  DRagLint.LSP.SyntaxTree,
  DRagLint.FieldRepo.Kinds,
  DRagLint.FieldRepo.SchemaFacts,
  DRagLint.FieldRepo.DfmRead,
  DRagLint.FieldRepo.DfmReadSql,
  DRagLint.FieldRepo.DfmReadPlan,
  DRagLint.FieldRepo.HandlersRegions;

const
  LF = #10;
  CR = #13;
  INDENT = '  ';
  EMPTY_STATEMENT = ';';
  N_PROC = 'defProc';
  N_HEAD = 'declProc';
  N_NAME = 'genericDot';
  N_BLOCK = 'block';
  KW_BEGIN = 'begin';
  KW_END = 'end';
  EVENT_CALC = 'OnCalcFields';
  FIELD_EVENTS: array[0..3] of string = ('OnGetText', 'OnSetText', 'OnValidate', 'OnChange');
  EVENT_PARAMS: array[0..3] of string = ('Sender,Text,DisplayText', 'Sender,Text', 'Sender', 'Sender');
  COL_FIELD = 'FIELD_NAME';
  COL_CALC_BODY = 'CALC_BODY';
  PARAM_DATASET = 'DataSet';
  ORM_SECTION_2 = '2';
  PAS_EXT = '.pas';
  OPEN_DIRECTIVE = '{$';
  OPEN_PAREN_DIRECTIVE = '(*$';
  SAME_BY_HAND = ': the handler holds the same code by hand, not generated';
  NOTHING_LEFT = 'the repository has nothing for this region any more; it was left (delete it by hand)';
  SQL_BODIES = 'SELECT * FROM "DL_FIELDS_INFO" WHERE UPPER("TABLE_NAME") = UPPER(:T) ORDER BY "FIELD_NAME"';
  SQL_FIELDS = 'SELECT "FIELD_NAME" FROM "DL_FIELDS_INFO" WHERE UPPER("TABLE_NAME") = UPPER(:T) ORDER BY "FIELD_NAME"';
  PAT_NO_SEMICOLON_AFTER = '(?:;|\bbegin)$';
  PAT_EMPTY_FIRST_LINE = '^\s*;\s*\n';
  PAT_PARAM_MODE = '^\s*(?:const|var|out)\s+';
  PAT_AFTER_SECTION = '\G\s*end\s*;';
  PAT_NEXT_SECTION = '\G\s*(?:implementation|const|resourcestring|type|var|threadvar|procedure|function|exports)\b';

type
  { The implementation of a method; offsets are 1-based. }
  TMethodSpot = record
    First: Integer;
    BeginPos: Integer;
    EndPos: Integer;    // the 'end' of the body
    MethodCount: Integer; // implementations in the whole unit
    Params: TArray<string>;
  end;

  { The dependency order of the calculated fields. }
  TCalcOrder = class
  strict private
    FFields: TArray<TFrhField>;
    FOrdered: TArray<TFrhField>;
    FDone: TList<Integer>;
    FPath: TList<Integer>;
    FCycle: string;
    procedure Visit(pIndex: Integer);
    procedure NameCycle(pIndex: Integer);
  public
    constructor Create(const pFields: TArray<TFrhField>);
    destructor Destroy; override;
    { The fields with a body; '' or the cycle. }
    function Order(out pCycle: string): TArray<TFrhField>;
  end;

  { Everything PlanHandlers knows about one form. }
  TFormPlan = class
  strict private
    FRepo: TFDConnection;
    FForm: TDfmrForm;
    FPlan: TFrhPlan;
    FUses: TDictionary<string, Integer>;
    procedure CountUses;
    procedure Report(const pRegionId, pTarget: string; pState: TFrhState; const pReason: string);
    function Shared(const pRegionId, pHandler: string): Boolean;
    procedure Run(const pJob: TFrhJob; const pNotes: TArray<string>);
    procedure RunCalc(const pJob: TFrhJob; pFields: TArray<TFrhField>; pWanted: Integer);
    procedure PlanCalc(const pDataset: TDfmrDataset; pFields: TArray<TFrhField>; const pBodies: TArray<TFrhBody>);
    procedure ReportLeftover(const pRegionId: string);
    procedure PlanEvent(const pFields: TArray<TFrhField>; const pField: TDfmrField; const pBody: TFrhBody);
    procedure PlanDataset(const pDataset: TDfmrDataset; const pTable, pUnresolved: string);
  public
    constructor Create(pRepo: TFDConnection; const pDfm: string);
    destructor Destroy; override;
    function Execute(const pDataset: string): TFrhPlan;
  end;

function Rx(const pPattern: string): TRegEx;
begin
  Result := TRegEx.Create(pPattern, [roIgnoreCase]);
end;

function LinesOf(const pText: string): TArray<string>;
begin
  Result := pText.Replace(CR, '').TrimRight([LF]).Split([LF]);
end;

{ pText with every non-empty line indented. }
function IndentLines(const pText, pIndent, pEol: string): string;
var
  VLine: string;
  VOut: TArray<string>;
begin
  VOut := nil;
  for VLine in LinesOf(pText) do
    VOut := VOut + [(if Trim(VLine) = '' then '' else pIndent + VLine) + pEol];
  Result := string.Join('', VOut);
end;

{ ---- generated code ---- }

{ The component a macro stands for. }
function MacroTarget(const pFields: TArray<TFrhField>; const pName: string; out pTarget, pReason: string): Boolean;
var
  VField: TFrhField;
  VFound: Integer;
begin
  VFound := 0;
  pTarget := '';
  pReason := '';
  for VField in pFields do
    if SameText(VField.Column, pName) then
    begin
      Inc(VFound);
      pTarget := VField.CompName;
    end;
  if VFound = 0 then
    pReason := 'the dataset has no persistent field for ' + pName
  else if VFound > 1 then
    pReason := 'the dataset has more than one persistent field for ' + pName;
  Result := pReason = '';
end;

{ Why expanded code must not go into a region. }
function CodeProblem(const pCode: string): string;
var
  VScan: TPasScan;
begin
  VScan := ScanPascal(pCode);
  Result := VScan.Problem;
  if not IsAsciiText(pCode) then
    Result := 'the code is not 7-bit ASCII'
  else if (Result = '') and (VScan.OpenStrings > 0) then
    Result := 'a string has no closing quote'
  else if (Result = '') and (Length(VScan.Directives) > 0) then
    Result := 'the code holds a compiler directive: ' + VScan.Directives[0].Text;
end;

function ExpandBody(const pFields: TArray<TFrhField>; const pBody: string; out pCode, pReason: string): Boolean;
var
  VMacros: TArray<TFrMacro>;
  VI: Integer;
  VTarget: string;
begin
  pCode := pBody;
  pReason := '';
  try
    VMacros := ParseMacros(pBody);
  except
    on E: EFrKindError do
      pReason := E.Message;
  end;
  for VI := High(VMacros) downto 0 do
    if (pReason = '') and MacroTarget(pFields, VMacros[VI].Name, VTarget, pReason) then
      pCode := Copy(pCode, 1, VMacros[VI].Offset - 1) + VTarget + Copy(pCode, VMacros[VI].Offset + VMacros[VI].Len);
  if pReason = '' then
    pReason := CodeProblem(pCode);
  Result := pReason = '';
end;

{ The code in a block of its own: stored bodies declare their locals inline. }
function BlockText(const pCode, pTitle: string): string;
begin
  Result := KW_BEGIN + (if pTitle = '' then '' else ' // ' + pTitle) + DLFR_CRLF + IndentLines(pCode, INDENT, DLFR_CRLF) +
    KW_END + EMPTY_STATEMENT + DLFR_CRLF;
end;

{ TCalcOrder }

constructor TCalcOrder.Create(const pFields: TArray<TFrhField>);
begin
  inherited Create;
  FFields := pFields;
  FDone := TList<Integer>.Create;
  FPath := TList<Integer>.Create;
end;

destructor TCalcOrder.Destroy;
begin
  FPath.Free;
  FDone.Free;
  inherited;
end;

procedure TCalcOrder.NameCycle(pIndex: Integer);
var
  VI: Integer;
begin
  for VI := FPath.IndexOf(pIndex) to FPath.Count - 1 do
    FCycle := FCycle + FFields[FPath[VI]].Column + ' -> ';
  FCycle := FCycle + FFields[pIndex].Column;
end;

procedure TCalcOrder.Visit(pIndex: Integer);
var
  VMacro: TFrMacro;
  VI: Integer;
begin
  if (FCycle <> '') or FDone.Contains(pIndex) then
    Exit;
  if FPath.Contains(pIndex) then
  begin
    NameCycle(pIndex);
    Exit;
  end;
  FPath.Add(pIndex);
  for VMacro in ParseMacros(FFields[pIndex].Body) do
    for VI := 0 to High(FFields) do
      if (VI <> pIndex) and (FFields[VI].Body <> '') and SameText(FFields[VI].Column, VMacro.Name) then
        Visit(VI);
  FPath.Delete(FPath.Count - 1);
  FDone.Add(pIndex);
  FOrdered := FOrdered + [FFields[pIndex]];
end;

function TCalcOrder.Order(out pCycle: string): TArray<TFrhField>;
var
  VI: Integer;
begin
  for VI := 0 to High(FFields) do
    if FFields[VI].Body <> '' then
      Visit(VI);
  pCycle := FCycle;
  Result := FOrdered;
end;

function CalcRegionContent(const pFields: TArray<TFrhField>; out pContent, pReason: string): Boolean;
var
  VOrder: TCalcOrder;
  VOrdered: TArray<TFrhField>;
  VField: TFrhField;
  VBlocks: TArray<string>;
  VCode: string;
begin
  pContent := '';
  for VField in pFields do
    if (VField.Body <> '') and not ExpandBody(pFields, VField.Body, VCode, pReason) then
    begin
      pReason := VField.Column + ': ' + pReason;
      Exit(False);
    end;
  VOrder := TCalcOrder.Create(pFields);
  try
    VOrdered := VOrder.Order(pReason);
  finally
    VOrder.Free;
  end;
  if pReason <> '' then
  begin
    pReason := 'calc cycle ' + pReason;
    Exit(False);
  end;
  VBlocks := nil;
  for VField in VOrdered do
    if ExpandBody(pFields, VField.Body, VCode, pReason) then
      VBlocks := VBlocks + [BlockText(VCode, VField.Column)];
  pContent := string.Join('', VBlocks);
  Result := True;
end;

function EventRegionContent(const pFields: TArray<TFrhField>; const pBody: string; out pContent, pReason: string): Boolean;
var
  VCode: string;
begin
  pContent := '';
  Result := ExpandBody(pFields, pBody, VCode, pReason);
  if Result then
    pContent := BlockText(VCode, '');
end;

{ ---- stored bodies ---- }

function FieldEventParams(const pEvent: string): string;
var
  VIndex: Integer;
begin
  VIndex := IndexText(pEvent, FIELD_EVENTS);
  Result := if VIndex < 0 then '' else EVENT_PARAMS[VIndex];
end;

procedure AddBody(var pBodies: TArray<TFrhBody>; const pField, pEvent, pBody: string);
var
  VBody: TFrhBody;
begin
  if Trim(pBody) = '' then
    Exit;
  VBody.Field := pField;
  VBody.Event := pEvent;
  VBody.Body := pBody;
  pBodies := pBodies + [VBody];
end;

procedure AddRowBodies(pRow: TFDQuery; var pBodies: TArray<TFrhBody>);
var
  VEvent: TFrEventColumn;
begin
  AddBody(pBodies, pRow.FieldByName(COL_FIELD).AsString, EVENT_CALC, pRow.FieldByName(COL_CALC_BODY).AsString);
  for VEvent in FR_EVENT_COLUMNS do
    if not VEvent.IsGrid then
      AddBody(pBodies, pRow.FieldByName(COL_FIELD).AsString, VEvent.Event, pRow.FieldByName(VEvent.Column).AsString);
end;

{ The bodies the repository holds for a table: CALC_BODY and the TField event columns of DL_FIELDS_INFO. }
function RepositoryBodies(pRepo: TFDConnection; const pTable: string): TArray<TFrhBody>;
var
  VQuery: TFDQuery;
begin
  Result := nil;
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pRepo;
    VQuery.Open(SQL_BODIES, [pTable]);
    while not VQuery.Eof do
    begin
      AddRowBodies(VQuery, Result);
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

{ ---- methods of a unit ---- }
function NodeText(const pText: string; const pNode: TTSNode): string;
begin
  Result := Copy(pText, Integer(pNode.StartByte) + 1, Integer(pNode.EndByte) - Integer(pNode.StartByte));
end;

function ChildOfType(const pNode: TTSNode; const pType: string; out pChild: TTSNode): Boolean;
var
  VI: Integer;
begin
  Result := False;
  pChild := pNode;
  for VI := 0 to Integer(pNode.NamedChildCount) - 1 do
    if pNode.NamedChild(VI).NodeType = pType then
    begin
      pChild := pNode.NamedChild(VI);
      Result := True; // the last one: the block behind the declarations
    end;
end;

{ Every method implementation, the ones inside another left out. }
procedure CollectMethods(const pNode: TTSNode; pList: TList<TTSNode>);
var
  VI: Integer;
begin
  if pNode.NodeType = N_PROC then
    pList.Add(pNode)
  else
    for VI := 0 to Integer(pNode.NamedChildCount) - 1 do
      CollectMethods(pNode.NamedChild(VI), pList);
end;

function IsMethod(const pText: string; const pNode: TTSNode; const pMethod: string): Boolean;
var
  VHead, VName: TTSNode;
begin
  Result := ChildOfType(pNode, N_HEAD, VHead) and ChildOfType(VHead, N_NAME, VName) and
    SameText(NodeText(pText, VName).Replace(' ', ''), pMethod);
end;

{ Parameter names of a method header; pHead is blanked text. }
function ParamNames(const pHead: string): TArray<string>;
var
  VFirst, VLast: Integer;
  VGroup, VName: string;
begin
  Result := nil;
  VFirst := Pos('(', pHead);
  VLast := Pos(')', pHead);
  if (VFirst = 0) or (VLast < VFirst) then
    Exit;
  for VGroup in Copy(pHead, VFirst + 1, VLast - VFirst - 1).Split([';']) do
    for VName in Rx(PAT_PARAM_MODE).Replace(VGroup.Split([':'])[0], '').Split([',']) do
      Result := Result + [Trim(VName)];
end;

{ The one method node of that name; '' or why there is none. }
function OneMethod(const pText: string; pMethods: TList<TTSNode>; const pMethod: string; var pNode: TTSNode): string;
var
  VNode: TTSNode;
  VFound: Integer;
begin
  VFound := 0;
  for VNode in pMethods do
    if IsMethod(pText, VNode, pMethod) then
    begin
      Inc(VFound);
      pNode := VNode;
    end;
  Result := '';
  if VFound = 0 then
    Result := pMethod + ' is not in the unit'
  else if VFound > 1 then
    Result := pMethod + ' is in the unit more than once'
  else if pNode.HasError then
    Result := pMethod + ' does not parse';
end;

{ '' or why the method cannot take a region. }
function ReadSpot(const pText, pMethod: string; const pScan: TPasScan; const pNode: TTSNode; var pSpot: TMethodSpot): string;
var
  VBlock: TTSNode;
  VBody: string;
begin
  if not ChildOfType(pNode, N_BLOCK, VBlock) then
    Exit(pMethod + ' has no begin .. end body');
  VBody := NodeText(pText, VBlock).TrimRight([' ', EMPTY_STATEMENT, CR, LF]);
  if not (StartsText(KW_BEGIN, VBody) and EndsText(KW_END, VBody)) then
    Exit(pMethod + ' has no begin .. end body');
  pSpot.First := Integer(pNode.StartByte) + 1;
  pSpot.BeginPos := Integer(VBlock.StartByte) + 1;
  pSpot.EndPos := pSpot.BeginPos + Length(VBody) - Length(KW_END);
  pSpot.Params := ParamNames(Copy(pScan.Code, pSpot.First, pSpot.BeginPos - pSpot.First));
  Result := if (pScan.IfDepthAt(pSpot.First) > 0) or (pScan.IfDepthAt(pSpot.EndPos) > 0) then
    pMethod + ' is inside a conditional' else '';
end;

function FindMethodSpot(const pText, pFile, pMethod: string; const pScan: TPasScan; out pSpot: TMethodSpot): string;
var
  VTree: TTSTree;
  VMethods: TList<TTSNode>;
  VNode: TTSNode;
begin
  pSpot := Default(TMethodSpot);
  VTree := ParseDelphiUtf8(TEncoding.ASCII.GetBytes(pText), pFile);
  if VTree = nil then
    Exit('the unit does not parse');
  VMethods := TList<TTSNode>.Create;
  try
    CollectMethods(VTree.RootNode, VMethods);
    pSpot.MethodCount := VMethods.Count;
    Result := OneMethod(pText, VMethods, pMethod, VNode);
    if Result = '' then
      Result := ReadSpot(pText, pMethod, pScan, VNode, pSpot);
  finally
    VMethods.Free;
    VTree.Free;
  end;
end;

{ ---- one job ---- }

function LineIndent(const pText: string; pPos: Integer): string;
var
  VFirst, VLast: Integer;
begin
  VFirst := pPos;
  while (VFirst > 1) and (pText[VFirst - 1] <> LF) do
    Dec(VFirst);
  VLast := VFirst;
  while (VLast < pPos) and CharInSet(pText[VLast], [' ', #9]) do
    Inc(VLast);
  Result := Copy(pText, VFirst, VLast - VFirst);
end;

{ '' or the standard parameter the content uses under a name the handler does not have. }
function ParamProblem(const pJob: TFrhJob; const pSpot: TMethodSpot): string;
var
  VI: Integer;
  VCode: string;
begin
  Result := '';
  VCode := ScanPascal(pJob.Content).Code;
  for VI := 0 to High(pJob.StdParams) do
    if Rx('\b' + pJob.StdParams[VI] + '\b').IsMatch(VCode)
      and ((VI > High(pSpot.Params)) or not SameText(pSpot.Params[VI], pJob.StdParams[VI])) then
      Exit(Format('the code uses the parameter %s, which %s does not have under that name', [pJob.StdParams[VI], pJob.Method]));
end;

function InsertRegion(const pText: string; const pJob: TFrhJob; const pScan: TPasScan; const pSpot: TMethodSpot): string;
var
  VEol, VIndent, VContent: string;
  VPos: Integer;
begin
  VEol := EolOf(pText);
  VPos := pSpot.EndPos;
  VIndent := LineIndent(pText, VPos);
  VContent := IndentLines(pJob.Content, VIndent + INDENT, VEol);
  if not Rx(PAT_NO_SEMICOLON_AFTER).IsMatch(Copy(pScan.Code, pSpot.BeginPos, VPos - pSpot.BeginPos).TrimRight) then
    VContent := VIndent + INDENT + EMPTY_STATEMENT + VEol + VContent;
  VContent := RenderDlfrRegion(pJob.RegionId, VContent, VIndent + INDENT, VEol);
  if (VPos - Length(VIndent) > 1) and (pText[VPos - Length(VIndent) - 1] = LF) then
    Dec(VPos, Length(VIndent)) // the end stands alone on its line: the region goes above that line
  else
    VContent := VEol + VContent;
  Result := Copy(pText, 1, VPos - 1) + VContent + Copy(pText, VPos);
end;

function UpdateRegion(const pText: string; const pJob: TFrhJob; const pRegion: TDlfrRegion): string;
var
  VEol, VIndent, VContent: string;
begin
  VEol := EolOf(pText);
  VIndent := LineIndent(pText, pRegion.Start.Start);
  VContent := IndentLines(pJob.Content, VIndent, VEol);
  if Rx(PAT_EMPTY_FIRST_LINE).IsMatch(pRegion.Content(pText)) then
    VContent := VIndent + EMPTY_STATEMENT + VEol + VContent;
  Result := ReplaceDlfrContent(pText, pRegion, VContent);
end;

function IsInMethod(const pRegion: TDlfrRegion; const pSpot: TMethodSpot): Boolean;
begin
  Result := (pRegion.Start.Start > pSpot.BeginPos) and (pRegion.Finish.Finish <= pSpot.EndPos);
end;

{ '' or why the edited text must not be kept. }
function ResultProblem(const pNew, pFile: string; const pJob: TFrhJob; pMethodCount: Integer): string;
var
  VSpot: TMethodSpot;
  VRegion: TDlfrRegion;
begin
  Result := FindMethodSpot(pNew, pFile, pJob.Method, ScanPascal(pNew), VSpot);
  if Result <> '' then
    Exit;
  if FindDlfrRegion(pNew, pJob.RegionId, VRegion, Result) <> drsIntact then
    Exit(if Result = '' then 'the region is lost' else Result);
  if (VSpot.MethodCount <> pMethodCount) or not IsInMethod(VRegion, VSpot) then
    Result := 'the code does not stay inside the handler'
  else if UpdateRegion(pNew, pJob, VRegion) <> pNew then
    Result := 'a second run would write again';
end;

{ Hand code around the region that a reader should know of. }
function HandNotes(const pText: string; const pJob: TFrhJob; const pSpot: TMethodSpot; const pRegion: TDlfrRegion): TArray<string>;
var
  VCode, VName: string;
begin
  Result := nil;
  VCode := ScanPascal(pText).Code;
  VCode := Copy(VCode, pSpot.BeginPos, pRegion.Start.Start - pSpot.BeginPos);
  if Rx('\bExit\b').IsMatch(VCode) then
    Result := ['hand code can Exit before the region'];
  for VName in pJob.Assigns do
    if Rx('\b' + VName + '\s*\.\s*\w+\s*:=').IsMatch(VCode) then
      Result := Result + ['hand code before the region assigns ' + VName + ' too; the region runs after it'];
end;

{ Code without comments, every run of blanks outside a string one blank. Directives stay. }
function CanonicalCode(const pCode: string): string;
var
  VScan: TPasScan;
  VSpan: TPasSpan;
  VOpen: string;
  VOut: TArray<string>;
  VPos: Integer;
begin
  VScan := ScanPascal(pCode);
  VOut := nil;
  VPos := 1;
  for VSpan in VScan.Spans do
  begin
    VOut := VOut + [Rx('\s+').Replace(Copy(pCode, VPos, VSpan.First - VPos), ' ')];
    VOpen := Copy(pCode, VSpan.First, Length(OPEN_PAREN_DIRECTIVE));
    VOut := VOut + [if VOpen.StartsWith('''') or VOpen.StartsWith(OPEN_DIRECTIVE) or (VOpen = OPEN_PAREN_DIRECTIVE) then
      Copy(pCode, VSpan.First, VSpan.Last - VSpan.First) else ' '];
    VPos := VSpan.Last;
  end;
  Result := (string.Join('', VOut) + Rx('\s+').Replace(Copy(pCode, VPos), ' ')).Trim([' ', EMPTY_STATEMENT]);
end;

{ True when statements of the block that follow one another are pWanted. }
function BlockHolds(const pText: string; const pScan: TPasScan; const pBlock: TTSNode; const pWanted: string): Boolean;
var
  VFirst, VLast, VStart: Integer;
  VCode: string;
begin
  Result := False;
  for VFirst := 0 to Integer(pBlock.NamedChildCount) - 1 do
  begin
    VStart := Integer(pBlock.NamedChild(VFirst).StartByte) + 1;
    if pScan.IfDepthAt(VStart) = 0 then
      for VLast := VFirst to Integer(pBlock.NamedChildCount) - 1 do
      begin
        VCode := CanonicalCode(Copy(pText, VStart, Integer(pBlock.NamedChild(VLast).EndByte) + 1 - VStart));
        if VCode = pWanted then
          Exit(True);
        if Length(VCode) > Length(pWanted) then
          Break;
      end;
  end;
end;

function HandlerHoldsCode(const pText, pFile: string; const pJob: TFrhJob; const pCode: string): Boolean;
var
  VRegion: TDlfrRegion;
  VText, VReason: string;
  VTree: TTSTree;
  VMethods: TList<TTSNode>;
  VNode, VBlock: TTSNode;
begin
  Result := False;
  if Trim(pCode) = '' then
    Exit;
  VText := pText;
  if FindDlfrRegion(VText, pJob.RegionId, VRegion, VReason) = drsIntact then
    VText := Copy(VText, 1, VRegion.Start.Start - 1) + Copy(VText, VRegion.Finish.Finish);
  VTree := ParseDelphiUtf8(TEncoding.ASCII.GetBytes(VText), pFile);
  if VTree = nil then
    Exit;
  VMethods := TList<TTSNode>.Create;
  try
    CollectMethods(VTree.RootNode, VMethods);
    if (OneMethod(VText, VMethods, pJob.Method, VNode) = '') and ChildOfType(VNode, N_BLOCK, VBlock) then
      Result := BlockHolds(VText, ScanPascal(VText), VBlock, CanonicalCode(pCode));
  finally
    VMethods.Free;
    VTree.Free;
  end;
end;

{ The edited text, or '' with the reason. }function EditHandler(const pText, pFile: string; const pJob: TFrhJob; pState: TDlfrRegionState; const pRegion: TDlfrRegion;
  out pReason: string): string;
var
  VScan: TPasScan;
  VSpot: TMethodSpot;
begin
  Result := '';
  VScan := ScanPascal(pText);
  pReason := FindMethodSpot(pText, pFile, pJob.Method, VScan, VSpot);
  if pReason = '' then
    pReason := ParamProblem(pJob, VSpot);
  if (pReason = '') and (pState = drsIntact) and not IsInMethod(pRegion, VSpot) then
    pReason := 'the region is not inside ' + pJob.Method;
  if pReason <> '' then
    Exit;
  Result := if pState = drsIntact then UpdateRegion(pText, pJob, pRegion) else InsertRegion(pText, pJob, VScan, VSpot);
  pReason := ResultProblem(Result, pFile, pJob, VSpot.MethodCount);
end;

procedure FillNotes(const pText, pFile: string; const pJob: TFrhJob; var pItem: TFrhItem);
var
  VSpot: TMethodSpot;
  VRegion: TDlfrRegion;
  VReason: string;
begin
  if (FindDlfrRegion(pText, pJob.RegionId, VRegion, VReason) = drsIntact)
    and (FindMethodSpot(pText, pFile, pJob.Method, ScanPascal(pText), VSpot) = '') then
    pItem.Notes := HandNotes(pText, pJob, VSpot, VRegion);
end;

function ApplyHandlerJob(const pText, pFile: string; const pJob: TFrhJob; out pItem: TFrhItem): string;
var
  VRegion: TDlfrRegion;
  VState: TDlfrRegionState;
  VNew: string;
begin
  Result := pText;
  pItem := Default(TFrhItem);
  pItem.RegionId := pJob.RegionId;
  pItem.Target := pJob.Method;
  pItem.State := fhsRefused;
  VState := drsUnusable;
  if not IsAsciiText(pText) then
    pItem.Reason := 'the unit is not 7-bit ASCII'
  else
  begin
    VState := FindDlfrRegion(pText, pJob.RegionId, VRegion, pItem.Reason);
    if (pJob.Content = '') and (VState in [drsAbsent, drsUnusable]) then
    begin
      pItem.State := fhsUnchanged;
      pItem.Reason := '';
    end
    else if VState in [drsAbsent, drsIntact] then
      if pJob.Content = '' then
        pItem.Reason := NOTHING_LEFT
      else
        VNew := EditHandler(pText, pFile, pJob, VState, VRegion, pItem.Reason);
  end;
  if (pItem.Reason <> '') or (pJob.Content = '') then
    Exit;
  Result := VNew;
  pItem.State := if VNew = pText then fhsUnchanged else if VState = drsAbsent then fhsInserted else fhsUpdated;
  FillNotes(Result, pFile, pJob, pItem);
end;

{ ---- MAXLEN ---- }

function MaxLenName(const pTable, pColumn: string): string;
begin
  Result := (pTable + '_' + pColumn + '_MAXLEN').ToUpper.Replace('$', '_');
end;

{ The value of a constant declared by hand; False = not declared. }
function HandConstant(const pCode, pName: string; out pValue: string): Boolean;
var
  VMatch: TMatch;
begin
  VMatch := Rx('\b' + pName + '\b\s*(?::\s*\w+\s*)?=\s*([^;]*);').Match(pCode);
  Result := VMatch.Success;
  pValue := if Result then Trim(VMatch.Groups[1].Value) else '';
end;

{ pCode with the region blanked. }
function WithoutRegion(const pCode: string; const pRegion: TDlfrRegion): string;
begin
  Result := Copy(pCode, 1, pRegion.Start.Start - 1) + StringOfChar(' ', pRegion.Finish.Finish - pRegion.Start.Start) +
    Copy(pCode, pRegion.Finish.Finish);
end;

function MaxLenContent(const pCode, pTable, pEol: string; const pColumns: TArray<TFrhLength>; var pItem: TFrhItem): string;
var
  VColumn: TFrhLength;
  VName, VHand: string;
  VLines: TArray<string>;
begin
  VLines := nil;
  for VColumn in pColumns do
  begin
    VName := MaxLenName(pTable, VColumn.Column);
    if not IsValidIdent(VName) then
      pItem.Notes := pItem.Notes + [VName + ' is not an identifier: left out']
    else if not HandConstant(pCode, VName, VHand) then
      VLines := VLines + [Format('%s/// <summary>Declared length of %s.%s in characters.</summary>%s%s%s = %d;%s',
        [INDENT, pTable, VColumn.Column, pEol, INDENT, VName, VColumn.Length, pEol])]
    else if VHand <> IntToStr(VColumn.Length) then
      pItem.Notes := pItem.Notes + [Format('%s is declared by hand as %s, the repository says %d', [VName, VHand, VColumn.Length])];
  end;
  Result := if VLines = nil then '' else 'const' + pEol + string.Join('', VLines);
end;

{ Offset of the line behind the interface type that holds section 2; 0 with the reason. }
function MaxLenSpot(const pText: string; const pScan: TPasScan; out pReason: string): Integer;
var
  VSection: TDlfrRegion;
  VEnd: TMatch;
begin
  Result := 0;
  pReason := 'section 2 (DB-RAD 2 or DLFR 2) is not in the unit';
  if not FindOrmRegion(pText, ORM_SECTION_2, VSection) then
    Exit;
  pReason := 'section 2 is inside a conditional';
  if (VSection.Start.IfDepth > 0) or (VSection.Finish.IfDepth > 0) then
    Exit;
  pReason := 'section 2 is not the end of its type';
  VEnd := Rx(PAT_AFTER_SECTION).Match(pScan.Code, VSection.Finish.Finish);
  if not VEnd.Success then
    Exit;
  pReason := 'another declaration of the same section follows the type of section 2';
  if not Rx(PAT_NEXT_SECTION).IsMatch(pScan.Code, VEnd.Index + VEnd.Length) then
    Exit;
  Result := Pos(LF, pText, VEnd.Index + VEnd.Length);
  if (Result = 0) or pScan.IsInside(Result + 1) or (Trim(Copy(pScan.Code, VEnd.Index + VEnd.Length, Result - VEnd.Index - VEnd.Length)) <> '')
    or (pScan.IfDepthAt(Result + 1) > 0) then
  begin
    pReason := 'there is no free line behind the type of section 2';
    Exit(0);
  end;
  Inc(Result);
  pReason := '';
end;

{ The new text; pText with the reason in pItem when it is refused. }
function EditMaxLen(const pText, pContent: string; pState: TDlfrRegionState; const pRegion: TDlfrRegion; var pItem: TFrhItem): string;
var
  VPos: Integer;
  VCheck: TDlfrRegion;
  VReason: string;
begin
  Result := pText;
  if pState = drsIntact then
    Result := ReplaceDlfrContent(pText, pRegion, pContent)
  else
  begin
    VPos := MaxLenSpot(pText, ScanPascal(pText), pItem.Reason);
    if VPos = 0 then
      Exit;
    Result := Copy(pText, 1, VPos - 1) + RenderDlfrRegion(FRH_MAXLEN_ID, pContent, '', EolOf(pText)) + Copy(pText, VPos);
  end;
  if (FindDlfrRegion(Result, FRH_MAXLEN_ID, VCheck, VReason) = drsIntact) and (VCheck.Content(Result) = pContent) then
    pItem.State := if Result = pText then fhsUnchanged else if pState = drsIntact then fhsUpdated else fhsInserted
  else
  begin
    pItem.Reason := if VReason = '' then 'the region is lost' else VReason;
    Result := pText;
  end;
end;

function ApplyMaxLen(const pText, pTable: string; const pColumns: TArray<TFrhLength>; out pItem: TFrhItem): string;
var
  VRegion: TDlfrRegion;
  VState: TDlfrRegionState;
  VCode, VContent: string;
begin
  Result := pText;
  pItem := Default(TFrhItem);
  pItem.RegionId := FRH_MAXLEN_ID;
  pItem.Target := pTable;
  pItem.State := fhsRefused;
  if not IsAsciiText(pText) then
  begin
    pItem.Reason := 'the unit is not 7-bit ASCII';
    Exit;
  end;
  VState := FindDlfrRegion(pText, FRH_MAXLEN_ID, VRegion, pItem.Reason);
  if VState in [drsEdited, drsUnusable] then
    Exit;
  VCode := ScanPascal(pText).Code;
  if VState = drsIntact then
    VCode := WithoutRegion(VCode, VRegion);
  VContent := MaxLenContent(VCode, pTable, EolOf(pText), pColumns, pItem);
  if VContent <> '' then
    Result := EditMaxLen(pText, VContent, VState, VRegion, pItem)
  else if VState = drsAbsent then
    pItem.State := fhsUnchanged
  else
    pItem.Reason := NOTHING_LEFT;
end;

function PlanMaxLen(pRepo: TFDConnection; const pFile, pTable: string): TFrhPlan;
var
  VQuery: TFDQuery;
  VColumns: TArray<TFrhLength>;
  VColumn: TFrhLength;
  VItem: TFrhItem;
begin
  Result := Default(TFrhPlan);
  Result.FileName := pFile;
  Result.OldText := LoadAsciiUnit(pFile);
  VColumns := nil;
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pRepo;
    VQuery.Open(SQL_FIELDS, [pTable]);
    while not VQuery.Eof do
    begin
      VColumn.Column := VQuery.Fields[0].AsString;
      VColumn.Length := ColumnCharLength(pRepo, pTable, VColumn.Column);
      if VColumn.Length > 0 then
        VColumns := VColumns + [VColumn];
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
  Result.NewText := ApplyMaxLen(Result.OldText, pTable, VColumns, VItem);
  Result.Items := [VItem];
end;

{ The stored body of one event; Body '' = none. }
function BodyOf(const pBodies: TArray<TFrhBody>; const pField, pEvent: string): TFrhBody;
var
  VBody: TFrhBody;
begin
  Result := Default(TFrhBody);
  for VBody in pBodies do
    if SameText(VBody.Field, pField) and (VBody.Event = pEvent) then
      Exit(VBody);
end;

{ The persistent fields with the column each stands for (the rule of the DFM reader). }
function FieldsOf(const pDataset: TDfmrDataset; const pTable: string): TArray<TFrhField>;
var
  VSource: TDfmrSqlSource;
  VHasSql: Boolean;
  VField: TDfmrField;
  VOut: TFrhField;
  VTable, VReason: string;
begin
  Result := nil;
  VHasSql := (pDataset.TableName = '') and (pDataset.Sql <> '');
  if VHasSql then
    VSource := ReadSelectSource(pDataset.Sql);
  for VField in pDataset.Fields do
  begin
    VOut := Default(TFrhField);
    VOut.CompName := VField.CompName;
    VOut.IsCalc := VField.Kind in [frkCalc, frkInternalCalc];
    VOut.Column := UpperCase(Trim(VField.FieldName));
    if (VField.Kind = frkData) and VHasSql and (VSource.Reason = '')
      and not (SqlFieldColumn(VSource, VField.FieldName, VField.Origin, VTable, VOut.Column, VReason) and SameText(VTable, pTable)) then
      VOut.Column := '';
    Result := Result + [VOut];
  end;
end;

function HasRegion(const pText, pId: string): Boolean;
var
  VRegion: TDlfrRegion;
  VReason: string;
begin
  Result := FindDlfrRegion(pText, pId, VRegion, VReason) in [drsIntact, drsEdited];
end;

{ What the handler already does by hand is left out of the fields; the rest is what the region assigns. }
procedure SplitHandCode(const pText, pFile: string; var pFields: TArray<TFrhField>; var pJob: TFrhJob; out pNotes: TArray<string>);
var
  VCode, VReason: string;
  VI: Integer;
begin
  pNotes := nil;
  for VI := 0 to High(pFields) do
    if (pFields[VI].Body <> '') and ExpandBody(pFields, pFields[VI].Body, VCode, VReason) then
      if HandlerHoldsCode(pText, pFile, pJob, VCode) then
      begin
        pNotes := pNotes + [pFields[VI].Column + SAME_BY_HAND];
        pFields[VI].Body := '';
      end
      else
        pJob.Assigns := pJob.Assigns + [pFields[VI].CompName];
end;

{ TFormPlan }

{ A region the repository has no code for any more. }
procedure TFormPlan.ReportLeftover(const pRegionId: string);
begin
  if HasRegion(FPlan.OldText, pRegionId) then
    Report(pRegionId, ExtractFileName(FPlan.FileName), fhsRefused, NOTHING_LEFT);
end;
constructor TFormPlan.Create(pRepo: TFDConnection; const pDfm: string);
begin
  inherited Create;
  FRepo := pRepo;
  FUses := TDictionary<string, Integer>.Create;
  FForm := LoadDfmForm(pDfm);
  FPlan.FileName := ChangeFileExt(FForm.FileName, PAS_EXT);
  FPlan.OldText := LoadAsciiUnit(FPlan.FileName);
  FPlan.NewText := FPlan.OldText;
  CountUses;
end;

destructor TFormPlan.Destroy;
begin
  FUses.Free;
  inherited;
end;

{ How many events of the form each handler serves. }
procedure TFormPlan.CountUses;
var
  VDataset: TDfmrDataset;
  VField: TDfmrField;
  VEvent: TDfmrPair;

  procedure Count(const pHandler: string);
  var
    VUses: Integer;
  begin
    if not FUses.TryGetValue(pHandler.ToUpper, VUses) then
      VUses := 0;
    FUses.AddOrSetValue(pHandler.ToUpper, VUses + 1);
  end;

begin
  for VDataset in FForm.Datasets do
  begin
    Count(VDataset.OnCalcFields);
    for VField in VDataset.Fields do
      for VEvent in VField.Events do
        Count(VEvent.Value);
  end;
end;

procedure TFormPlan.Report(const pRegionId, pTarget: string; pState: TFrhState; const pReason: string);
var
  VItem: TFrhItem;
begin
  VItem := Default(TFrhItem);
  VItem.RegionId := pRegionId;
  VItem.Target := pTarget;
  VItem.State := pState;
  VItem.Reason := pReason;
  FPlan.Items := FPlan.Items + [VItem];
end;

{ One handler for several events: the code of one field would run for the others too. }
function TFormPlan.Shared(const pRegionId, pHandler: string): Boolean;
begin
  Result := FUses[pHandler.ToUpper] > 1;
  if Result then
    Report(pRegionId, pHandler, fhsRefused, 'the DFM uses this handler for more than one event');
end;

procedure TFormPlan.Run(const pJob: TFrhJob; const pNotes: TArray<string>);
var
  VItem: TFrhItem;
begin
  FPlan.NewText := ApplyHandlerJob(FPlan.NewText, FPlan.FileName, pJob, VItem);
  VItem.Notes := pNotes + VItem.Notes;
  FPlan.Items := FPlan.Items + [VItem];
end;

procedure TFormPlan.RunCalc(const pJob: TFrhJob; pFields: TArray<TFrhField>; pWanted: Integer);
var
  VJob: TFrhJob;
  VNotes: TArray<string>;
  VReason: string;
begin
  VJob := pJob;
  SplitHandCode(FPlan.OldText, FPlan.FileName, pFields, VJob, VNotes);
  if not CalcRegionContent(pFields, VJob.Content, VReason) then
    Report(VJob.RegionId, VJob.Method, fhsRefused, VReason)
  else if pWanted > 0 then
    Run(VJob, VNotes)
  else
    ReportLeftover(VJob.RegionId);
end;

procedure TFormPlan.PlanCalc(const pDataset: TDfmrDataset; pFields: TArray<TFrhField>; const pBodies: TArray<TFrhBody>);
var
  VBody: TFrhBody;
  VJob: TFrhJob;
  VI, VWanted: Integer;
begin
  VJob := Default(TFrhJob);
  VJob.RegionId := pDataset.Name + '.' + EVENT_CALC;
  VJob.Method := FForm.FormClass + '.' + pDataset.OnCalcFields;
  VJob.StdParams := [PARAM_DATASET];
  VWanted := 0;
  for VI := 0 to High(pFields) do
    for VBody in pBodies do
      if pFields[VI].IsCalc and (VBody.Event = EVENT_CALC) and SameText(VBody.Field, pFields[VI].Column) then
      begin
        pFields[VI].Body := VBody.Body;
        Inc(VWanted);
      end;
  if (VWanted > 0) and (pDataset.OnCalcFields = '') then
    Report(VJob.RegionId, pDataset.Name, fhsSkipped, 'the DFM assigns no OnCalcFields handler: assign one and run again');
  if (pDataset.OnCalcFields <> '') and not ((VWanted > 0) and Shared(VJob.RegionId, pDataset.OnCalcFields)) then
    RunCalc(VJob, pFields, VWanted);
end;

procedure TFormPlan.PlanEvent(const pFields: TArray<TFrhField>; const pField: TDfmrField; const pBody: TFrhBody);
var
  VEvent: TDfmrPair;
  VJob: TFrhJob;
  VHandler, VCode, VReason: string;
  VNotes: TArray<string>;
begin
  VHandler := '';
  for VEvent in pField.Events do
    if VEvent.Name = pBody.Event then
      VHandler := VEvent.Value;
  VJob := Default(TFrhJob);
  VJob.RegionId := pField.CompName + '.' + pBody.Event;
  VJob.Method := FForm.FormClass + '.' + VHandler;
  VJob.StdParams := FieldEventParams(pBody.Event).Split([',']);
  VNotes := nil;
  if VHandler = '' then
    Report(VJob.RegionId, pField.CompName, fhsSkipped, 'the DFM assigns no ' + pBody.Event + ' handler: assign one and run again')
  else if Shared(VJob.RegionId, VHandler) then
    Exit
  else if not EventRegionContent(pFields, pBody.Body, VJob.Content, VReason) then
    Report(VJob.RegionId, VJob.Method, fhsRefused, VReason)
  else
  begin
    if ExpandBody(pFields, pBody.Body, VCode, VReason) and HandlerHoldsCode(FPlan.OldText, FPlan.FileName, VJob, VCode) then
    begin
      VNotes := [pField.CompName + SAME_BY_HAND];
      VJob.Content := '';
    end;
    Run(VJob, VNotes);
  end;
end;

procedure TFormPlan.PlanDataset(const pDataset: TDfmrDataset; const pTable, pUnresolved: string);
var
  VFields: TArray<TFrhField>;
  VBodies: TArray<TFrhBody>;
  VBody: TFrhBody;
  VEvent: string;
  VI: Integer;
begin
  if pTable = '' then
  begin
    Report(pDataset.Name, pDataset.Name, fhsSkipped, 'no table: ' + pUnresolved);
    Exit;
  end;
  VFields := FieldsOf(pDataset, pTable);
  VBodies := RepositoryBodies(FRepo, pTable);
  PlanCalc(pDataset, Copy(VFields), VBodies);
  for VI := 0 to High(VFields) do
    for VEvent in FIELD_EVENTS do
    begin
      VBody := BodyOf(VBodies, VFields[VI].Column, VEvent);
      if VBody.Body <> '' then
        PlanEvent(VFields, pDataset.Fields[VI], VBody)
      else
        ReportLeftover(pDataset.Fields[VI].CompName + '.' + VEvent);
    end;
end;
function TFormPlan.Execute(const pDataset: string): TFrhPlan;
var
  VReport: TDfmrDatasetReport;
  VDataset: TDfmrDataset;
begin
  for VReport in PlanDfmRead(FRepo, [FForm.FileName], pDataset).Datasets do
    for VDataset in FForm.Datasets do
      if SameText(VDataset.Name, VReport.Dataset) then
        PlanDataset(VDataset, VReport.TableName, VReport.Unresolved);
  Result := FPlan;
end;

function PlanHandlers(pRepo: TFDConnection; const pDfm, pDataset: string): TFrhPlan;
var
  VPlan: TFormPlan;
begin
  VPlan := TFormPlan.Create(pRepo, pDfm);
  try
    Result := VPlan.Execute(pDataset);
  finally
    VPlan.Free;
  end;
end;

end.
