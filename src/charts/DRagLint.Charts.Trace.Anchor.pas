unit DRagLint.Charts.Trace.Anchor;

(* The round-trip ANCHOR (a port of charts\src\Trace.Walk.ps1 Part 1 -- lines 40-392 and 881-888 and
  1899-1923; the PS output is the reference). From a -Target to the data anchor (dataset field, column,
  table, TABLE.COLUMN), as graded trace steps.

  The four -Target forms (spec section 3), told apart by SHAPE and split from the RIGHT (P13), so a
  dotted unit resolves:
    <Form>.<Control>                  a DFM control: its field binding and DataSource, the datasource
                                      chain to the dataset (TChainWalker), the table literal beside the
                                      dataset and the column in the SQL index
    <Unit>.<TForm>.<Control>          the control's interface field: class -> DFM object is a NAMING
                                      convention (the T-less class name), so the result carries [by name]
                                      in Grades
    <Unit>.<TClass>.<TField variable> the dataset and column come from the lines that WRITE the variable
                                      (a bound write); FieldVarLineGrade says how far each line proves it
    TABLE.COLUMN                      the dataset fields whose unit names the table beside them: EXACTLY
                                      ONE dataset proceeds, several is a named stop (Review Focus 2)

  A selection that is not data-bound, or a chain that cannot reach a table, ends in Stop plus a
  StopAnchor and NO item for the stop itself -- the emitter writes ONE numbered STOPS from them, never an
  empty report (AC-13; ruling P3). A stale file on the way sets StaleFile and the emitter REFUSES
  (AC-14). A bad target SHAPE (RT16: no dots, not a class, no form, no component, several components)
  raises EChartsTrace with the PowerShell throw text; the question unit turns it into the chart error.

  Grades: a step is certain (Grade ''), [by name] or [inferred]. The FieldByName + bound rule: only a
  FieldByName on a BOUND dataset read proves the column (certain); an unbound one is [by name]; any other
  call shape is [inferred] -- that the call returns the dataset's field is an inference about the called
  routine.

  The calculated-field hook is NOT here (RT2): the question unit asks DRagLint.Charts.Trace.Calc after a
  column stop; this unit leaves Calc nil and the stop text is the plain '<TABLE.COLUMN>: <label>'.
  Event wiring (Get-EventWiring) reads the AfterPost-class handlers of the anchor dataset.

  PowerShell traps closed here: -eq / -ne comparisons are case-insensitive (SameText); a PCRE regex
  drops trailing optional groups (Grp in Trace.FormA is the reference); Sort-Object is stable and
  case-insensitive (SortUniqueNames, a stable insertion sort); the unary-comma array returns are plain
  arrays. *)

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Charts.Index  // dl:unit DRagLint.Charts.Index accepted -- the resolver reads the Delphi index directly; the SQL text escaper and TIndexRow travel with TChartsIndex
  , DRagLint.Charts.Source
  , DRagLint.Charts.Sql
  , DRagLint.Charts.Columns
  , DRagLint.Charts.Chain
  , DRagLint.Charts.Trace.FormA
  ;

const
  /// <summary>The events whose handlers write the anchor dataset back, as Get-EventWiring asks for them by default.</summary>
  RT_EVENTS: array[0..6] of string = ('AfterPost', 'AfterDelete', 'BeforePost', 'AfterInsert', 'OnUpdateRecord',
    'OnUpdateError', 'OnReconcileError');

type
  /// <summary>The anchor dataset field (the PS $Ds).</summary>
  TTraceDataSet = record
    /// <summary>The field's name.</summary>
    Name    : string;
    /// <summary>symbols.id.</summary>
    Id      : Integer;
    /// <summary>The declaring class's symbols.id.</summary>
    ClassId : Integer;
    /// <summary>The declaring file as indexed (the PS File).</summary>
    FileName: string;
    /// <summary>The file's files.id.</summary>
    Fid     : Integer;
    /// <summary>The declaration line.</summary>
    Line    : Integer;
    /// <summary>The declared type (the PS Type), trimmed.</summary>
    TypeName: string;
  end;

  /// <summary>What FieldVarLineGrade decided for one write line.</summary>
  TFieldVarGrade = record
    /// <summary>'' (certain), 'by name' or 'inferred'.</summary>
    Grade : string;
    /// <summary>The step note.</summary>
    Reason: string;
    /// <summary>The engine ask that would retire the grade; '' for none.</summary>
    Ask   : string;
  end;

  /// <summary>One write line of a TField variable, with what the line names. Port of a Get-FieldVarWriteRows row.</summary>
  TFieldVarWrite = record
    /// <summary>The variable's name.</summary>
    VarName : string;
    /// <summary>The variable's qualified name.</summary>
    VarQName: string;
    /// <summary>The write line.</summary>
    Line    : Integer;
    /// <summary>The file as indexed.</summary>
    Path    : string;
    /// <summary>The dataset fields the line names, comma separated; '' for none.</summary>
    Ds      : string;
    /// <summary>1 when a read ref of a dataset field on the line is bound; else 0.</summary>
    Bound   : Integer;
    /// <summary>How many FieldByName refs on the line have a dataset field receiver.</summary>
    Fbn     : Integer;
    /// <summary>The call names on the line, comma separated.</summary>
    Calls   : string;
    /// <summary>The string literals on the line, joined with '|'.</summary>
    Col     : string;
  end;

  /// <summary>The (dataset field, column literal) pairs of a variable's write rows.</summary>
  TFieldVarPairs = record
    /// <summary>The rows naming exactly ONE dataset field and ONE literal.</summary>
    Ok   : TArray<TFieldVarWrite>;
    /// <summary>The distinct 'DS|COL' strings, in Sort-Object -Unique order.</summary>
    Pairs: TArray<string>;
  end;

  /// <summary>One event of the anchor dataset wired to a handler. Port of a Get-EventWiring row.</summary>
  TEventWiring = record
    /// <summary>The wiring line.</summary>
    Line        : Integer;
    /// <summary>The event name as written.</summary>
    Event       : string;
    /// <summary>The handler method's name.</summary>
    Handler     : string;
    /// <summary>The handler's symbols.id.</summary>
    HandlerId   : Integer;
    /// <summary>The handler's short name (Class.Method).</summary>
    HandlerShort: string;
    /// <summary>The handler's implementation start line.</summary>
    HandlerImpl : Integer;
    /// <summary>The handler's file as indexed.</summary>
    HandlerPath : string;
    /// <summary>The routine that wires it (the last segment).</summary>
    Routine     : string;
    /// <summary>Always 'by name': the assignment is not bound (E3).</summary>
    Grade       : string;
  end;

  /// <summary>The anchor of one target: graded steps, the dataset, the column or the reason it stops.</summary>
  /// <remarks>Port of the New-AnchorResult object. Owns Items and Calc. Not thread-safe.</remarks>
  TAnchorResult = class
  public
    /// <summary>The graded steps, in order; the result owns them.</summary>
    Items      : TObjectList<TTraceItem>;
    /// <summary>The anchor dataset; valid when HasDataSet.</summary>
    DataSet    : TTraceDataSet;
    /// <summary>False for the PS $null dataset.</summary>
    HasDataSet : Boolean;
    /// <summary>The table; '' when none.</summary>
    Table      : string;
    /// <summary>The column, upper case; '' when none.</summary>
    Column     : string;
    /// <summary>TABLE.COLUMN; '' when the anchor stops before a column (a TABLE.COLUMN target keeps its asked text).</summary>
    TableColumn: string;
    /// <summary>The reason the anchor stops; '' when it reaches the column.</summary>
    Stop       : string;
    /// <summary>File.ext:line of the last step the stop hangs on.</summary>
    StopAnchor : string;
    /// <summary>'' or the indexed path that differs from the indexed copy (the emitter REFUSES).</summary>
    StaleFile  : string;
    /// <summary>'by name' once the class -> DFM object convention hop was taken.</summary>
    Grades     : TArray<string>;
    /// <summary>The calculated-field facts; nil unless the question unit asked DRagLint.Charts.Trace.Calc.
    /// Its runtime type is DRagLint.Charts.Trace.Calc.TCalcInfo, which this unit does not use. Owned by the result.</summary>
    Calc       : TObject;
    /// <summary>The column exactly as the selection names it (the PS $Col, before the upper-casing of Column): ''
    /// until the anchor reached a dataset. The question unit hands it to TCalcFactsReader.Apply.</summary>
    FieldName  : string;
    constructor Create;
    destructor Destroy; override;
  end;

  /// <summary>Resolves a -Target to its anchor over one Delphi index and one SQL catalogue.</summary>
  /// <remarks>Nothing passed in is owned: the index, reader, walker, catalogue and table set must outlive
  /// the resolver. Source overrides (a stale-file test) live on the reader. Not thread-safe.</remarks>
  TTraceAnchorResolver = class  // dl:ok high-response@b9dc -- REVIEWED 2026-10-17: the resolver IS the PS Part 1 family (Resolve-TraceAnchor .. Get-EventWiring); its response set is the SQL and formatting calls each form makes, already split into per-form private procedures
  private
    type
      /// <summary>The field a dataset property reads (Resolve-PropertyReadField's result).</summary>
      TPropField = record
        Found    : Boolean;
        Field    : TTraceDataSet;
        Accessor : string;
        Grade    : string;
        Reason   : string;
        StaleFile: string;
      end;
    var
    FIndex  : TChartsIndex;
    FReader : TSourceReader;
    FWalker : TChainWalker;
    FCatalog: TSqlCatalog;
    FSet    : TSqlTableSet;
    function PropertyReadField(const pProp: TTraceDataSet; const pAssignFile: string; pAssignLine: Integer): TPropField;
    procedure CompleteAnchorFromDataSet(pR: TAnchorResult; const pDs: TTraceDataSet; const pCol, pBindGrade, pBindNote: string);
    procedure AnchorFromControl(const pForm, pCtl: string; pR: TAnchorResult);
    procedure AnchorFromFieldVar(pMemId: Integer; const pMemPath: string; pMemLine: Integer; const pTarget, pName: string;
      pR: TAnchorResult);
    procedure AnchorFromColumn(const pTable, pCol: string; pR: TAnchorResult);
    procedure ResolveInto(const pTarget: string; pR: TAnchorResult);
    procedure FollowDirectChain(const pCh: TDataSourceChain; const pDsText: string; pS1: TTraceItem; pR: TAnchorResult;
      const pCol: string);
  public
    /// <summary>Constructor.</summary>
    /// <param name="pIndex">The Delphi (CLIENT) index; not owned.</param>
    /// <param name="pReader">A source reader over pIndex; not owned.</param>
    /// <param name="pWalker">A chain walker over the same index and catalogue; not owned.</param>
    /// <param name="pCatalog">The SQL catalogue (column states); not owned.</param>
    /// <param name="pSet">The SQL table set (the PS $SqlSet); not owned.</param>
    constructor Create(pIndex: TChartsIndex; pReader: TSourceReader; pWalker: TChainWalker; pCatalog: TSqlCatalog;
      pSet: TSqlTableSet);
    /// <summary>From a -Target to the data anchor.</summary>
    /// <param name="pTarget">One of the four -Target forms; trimmed.</param>
    /// <returns>The anchor; the caller frees it. Stop / StaleFile say why it stops.</returns>
    /// <exception cref="EChartsTrace">The target is not one of the four shapes, is not a class of the index, names
    /// no form, no component or several components (RT16). The texts are the PS throw texts.</exception>
    /// <remarks>Port of Resolve-TraceAnchor (Trace.Walk.ps1:364).</remarks>
    function ResolveTraceAnchor(const pTarget: string): TAnchorResult;
    /// <summary>The event handlers of the anchor dataset, in write preference order.</summary>
    /// <param name="pDs">The anchor dataset.</param>
    /// <param name="pEvents">The events to read; nil = RT_EVENTS.</param>
    /// <returns>AfterPost first, then BeforePost, AfterInsert, OnUpdateRecord, OnUpdateError, OnReconcileError,
    /// AfterDelete last; each event's by line (the WRITE direction starts at [0]).</returns>
    /// <remarks>Port of Get-EventWiring + Sort-RtWiring (Trace.Walk.ps1:881, 1899). A wiring whose handler is
    /// not exactly one method with an implementation in the dataset's class is skipped.</remarks>
    function EventWiring(const pDs: TTraceDataSet; const pEvents: TArray<string> = nil): TArray<TEventWiring>;
    /// <summary>The dataset fields whose unit names the table beside them.</summary>
    /// <param name="pTable">The table, upper case.</param>
    /// <returns>Rows id, name, q, sig, line, path, fid, pid by qualified name; the caller frees the list.</returns>
    /// <remarks>Port of Get-TableDataSetRows (Trace.Walk.ps1:349).</remarks>
    function TableDataSetRows(const pTable: string): TObjectList<TIndexRow>;
    /// <summary>The write lines of the TField variables of a class that a condition on the write ref selects.</summary>
    /// <param name="pClassId">The class's symbols.id.</param>
    /// <param name="pWhere">A condition on the write ref r (for example r.symbol_id = 5).</param>
    /// <returns>One row per write line, by line then ref id.</returns>
    /// <remarks>Port of Get-FieldVarWriteRows (Trace.Walk.ps1:293); the MATERIALIZED CTE verbatim. Shared by
    /// the TField-variable anchor and the calc-field check (Part 6).</remarks>
    function FieldVarWriteRows(pClassId: Integer; const pWhere: string): TArray<TFieldVarWrite>;
    /// <summary>The column fact note of a column step.</summary>
    /// <param name="pCs">The column state.</param>
    /// <param name="pSet">The SQL table set.</param>
    /// <returns>For an extracted column '&lt;COL&gt; is a column of the newest of N &lt;TABLE&gt; declarations (SQL
    /// index, FILE:LINE)'; any other state keeps the state's label, made safe for a note.</returns>
    /// <remarks>Port of Get-ColumnFactNote (Trace.Walk.ps1:54). Never truncated (T3-M2).</remarks>
    function ColumnFactNote(const pCs: TSqlColumnState; pSet: TSqlTableSet): string;
  end;

/// <summary>SQL: the symbol alias is declared with a dataset class type.</summary>
/// <param name="pAlias">The symbols alias.</param>
/// <returns>A SUFFIX match on the signature (LIKE 'T%Table' also took TcxGridDBTableView).</returns>
/// <remarks>Port of Get-DataSetTypeSql (Trace.Walk.ps1:40).</remarks>
function DataSetTypeSql(const pAlias: string = 's'): string;

/// <summary>The (dataset field, column literal) pairs of a variable's write rows.</summary>
/// <param name="pRows">FieldVarWriteRows output.</param>
/// <returns>Ok: rows naming exactly ONE dataset field and ONE literal; Pairs: the distinct 'DS|COL' strings.</returns>
/// <remarks>Port of Get-FieldVarPairs (Trace.Walk.ps1:322). Pure.</remarks>
function FieldVarPairs(const pRows: TArray<TFieldVarWrite>): TFieldVarPairs;

/// <summary>The grade of a TField-variable assignment line.</summary>
/// <param name="pFieldByName">The line is a FieldByName on the dataset.</param>
/// <param name="pBound">The dataset read on the line is bound to a symbol.</param>
/// <param name="pCalls">The call names on the line.</param>
/// <param name="pDsName">The dataset field's name.</param>
/// <returns>certain ('') only for FieldByName + bound; [by name] for FieldByName unbound; every other shape
/// [inferred], its reason naming the call(s); an unbound read asks in-class-field-reads.</returns>
/// <remarks>Port of Get-FieldVarLineGrade (Trace.Walk.ps1:247). Pure.</remarks>
function FieldVarLineGrade(pFieldByName, pBound: Boolean; const pCalls: TArray<string>; const pDsName: string): TFieldVarGrade;

/// <summary>FieldVarLineGrade over one write row.</summary>
/// <param name="pSite">A FieldVarWriteRows row.</param>
/// <param name="pDsName">The dataset field's name.</param>
/// <returns>The grade; FieldByName calls are not counted among the calls.</returns>
/// <remarks>Port of Get-FieldVarSiteGrade (Trace.Walk.ps1:328). Pure.</remarks>
function FieldVarSiteGrade(const pSite: TFieldVarWrite; const pDsName: string): TFieldVarGrade;

implementation

uses
  System.RegularExpressions
  , DRagLint.Charts.Text
  , DRagLint.Charts.Trace.Shim
  ;

const
  KIND_STEP = 'step';
  GRADE_BY_NAME = 'by name';
  GRADE_INFERRED = 'inferred';
  GRADE_DANGLING = 'dangling';
  GRADE_STALE = 'stale source';
  BIND_NOTE = 'the anchor dataset';
  ASK_IN_CLASS = 'in-class-field-reads';
  ASK_TYPE_USE = 'type-use-binding';
  ASK_COLUMN = 'E4';
  HOP_WORD_MAX = 90;
  RANK_UNLISTED = 99;
  MIN_UNIT_SEGMENTS = 3;
  UNKNOWN_ANCHOR = 'unknown:0';
  RE_TARGET = '^[A-Za-z_][A-Za-z0-9_$]*(\.[A-Za-z_][A-Za-z0-9_$]*)+$';
  RE_FIELD_SIG = '(?i)^T\w*Field$';
  RE_READ = '(?i)\bread\s+([A-Za-z_][A-Za-z0-9_]*)';
  RE_SELF = '(?i)^Self\.';
  RE_T_PREFIX = '(?i)^T';
  RE_BRACKET_PAIR = '\[([^\]]*)\]';
  SYM_COLS = 's.id AS id, s.name AS name, s.signature AS sig, s.start_line AS line, f.path AS path, s.file_id AS fid, s.parent_id AS pid';
  RT_WRITE_PREFERENCE: array[0..6] of string = ('AfterPost', 'BeforePost', 'AfterInsert', 'OnUpdateRecord', 'OnUpdateError',
    'OnReconcileError', 'AfterDelete');

function LastSegment(const pText: string): string;
begin
  Result:= Copy(pText, LastDelimiter('.', pText) + 1, MaxInt);
end;

{ a symbols row selected with SYM_COLS as the anchor dataset record }
function DataSetOfRow(pRow: TIndexRow): TTraceDataSet;
begin
  Result.Name:= pRow.S('name');
  Result.Id:= pRow.I('id');
  Result.ClassId:= pRow.I('pid');
  Result.FileName:= pRow.S('path');
  Result.Fid:= pRow.I('fid');
  Result.Line:= pRow.I('line');
  Result.TypeName:= Trim(pRow.S('sig'));
end;

function DataSetOfChain(const pDs: TChainDataSet): TTraceDataSet;
begin
  Result.Name:= pDs.Name;
  Result.Id:= pDs.Id;
  Result.ClassId:= pDs.ClassId;
  Result.FileName:= pDs.Path;
  Result.Fid:= pDs.Fid;
  Result.Line:= pDs.Line;
  Result.TypeName:= pDs.TypeName;
end;

function ChainOfDataSet(const pDs: TTraceDataSet): TChainDataSet;
begin
  Result.Present:= True;
  Result.Name:= pDs.Name;
  Result.Id:= pDs.Id;
  Result.ClassId:= pDs.ClassId;
  Result.Path:= pDs.FileName;
  Result.Fid:= pDs.Fid;
  Result.Line:= pDs.Line;
  Result.TypeName:= pDs.TypeName;
end;

function HopGrade(const pGrade: string): string;
begin
  Result:= if SameText(pGrade, GRADE_BY_NAME) or SameText(pGrade, GRADE_INFERRED) then pGrade else '';
end;

function RePointVerb(const pHop: string): string;
begin
  if SameText(pHop, 're-point') or SameText(pHop, 'dataset') then
    Result:= 'SETS'
  else if SameText(pHop, 'member') or SameText(pHop, 'field') then
    Result:= 'READS'
  else if SameText(pHop, 'accessor') then
    Result:= 'CALLS'
  else
    Result:= '';
end;

function ChainVerb(const pHop: string): string;
begin
  if SameText(pHop, 'dataset') then
    Result:= 'SETS'
  else if SameText(pHop, 'datasource') or SameText(pHop, 'rhs-type') then
    Result:= 'READS'
  else
    Result:= '';
end;

{ ---- TAnchorResult ---- }

constructor TAnchorResult.Create;
begin
  inherited Create;
  Items:= TObjectList<TTraceItem>.Create(True);
end;

destructor TAnchorResult.Destroy;
begin
  Calc.Free;
  Items.Free;
  inherited Destroy;
end;

{ ---- pure helpers ---- }

function DataSetTypeSql(const pAlias: string): string;
begin
  Result:= '(TRIM(' + pAlias + '.signature) LIKE ''T%MemTable'' OR TRIM(' + pAlias + '.signature) LIKE ''T%Query'' OR TRIM(' +
    pAlias + '.signature) LIKE ''T%Table'' OR TRIM(' + pAlias + '.signature) LIKE ''T%DataSet'')';
end;

function FieldVarPairs(const pRows: TArray<TFieldVarWrite>): TFieldVarPairs;
begin
  var Ok:= TList<TFieldVarWrite>.Create;
  try
    var Keys: TArray<string>:= [];
    for var W in pRows do
      if (W.Ds <> '') and (W.Col <> '') and (Pos(',', W.Ds) = 0) and (Pos('|', W.Col) = 0) then
      begin
        Ok.Add(W);
        Keys:= Keys + [W.Ds + '|' + W.Col];
      end;
    Result.Ok:= Ok.ToArray;
    Result.Pairs:= SortUniqueNames(Keys);
  finally
    Ok.Free;
  end;
end;

function FieldVarLineGrade(pFieldByName, pBound: Boolean; const pCalls: TArray<string>; const pDsName: string): TFieldVarGrade;
begin
  if pFieldByName then
  begin
    if pBound then
    begin
      Result.Grade:= '';
      Result.Reason:= 'the TField variable, by FieldByName on its dataset';
      Result.Ask:= '';
    end
    else
    begin
      Result.Grade:= GRADE_BY_NAME;
      Result.Reason:= 'the TField variable, by FieldByName on ' + pDsName + ', matched by name among the class''s dataset fields';
      Result.Ask:= ASK_IN_CLASS;
    end;
    Exit;
  end;
  var Named: TArray<string>:= [];
  for var C in pCalls do
    if C <> '' then
      Named:= Named + [C];
  var Cl:= SortUniqueNames(Named);
  var Via:= if Length(Cl) = 1 then 'via ' + Cl[0] + '(dataset, literal)'
    else if Length(Cl) > 1 then 'via one of ' + string.Join(', ', Cl)
    else 'with no call on the line';
  Result.Grade:= GRADE_INFERRED;
  Result.Reason:= 'the TField variable ' + Via + ', assumed to return the dataset''s field named by the literal';
  if not pBound then
    Result.Reason:= Result.Reason + ', and ' + pDsName + ' matched by name among the class''s dataset fields';
  Result.Ask:= if pBound then '' else ASK_IN_CLASS;
end;

function FieldVarSiteGrade(const pSite: TFieldVarWrite; const pDsName: string): TFieldVarGrade;
begin
  var Calls: TArray<string>:= [];
  for var C in pSite.Calls.Split([',']) do
    if (C <> '') and not SameText(C, 'FieldByName') then
      Calls:= Calls + [C];
  Result:= FieldVarLineGrade(pSite.Fbn > 0, pSite.Bound > 0, Calls, pDsName);
end;

{ stable: ties keep their order }
procedure SortWirings(var pList: TArray<TEventWiring>);
  function Rank(const pEvent: string): Integer;
  begin
    Result:= RANK_UNLISTED;
    for var K:= 0 to High(RT_WRITE_PREFERENCE) do
      if SameStr(RT_WRITE_PREFERENCE[K], pEvent) then
        Exit(K);
  end;
begin
  for var I:= 1 to High(pList) do
  begin
    var Cur:= pList[I];
    var J:= I - 1;
    while (J >= 0) and ((Rank(pList[J].Event) > Rank(Cur.Event)) or
      ((Rank(pList[J].Event) = Rank(Cur.Event)) and (pList[J].Line > Cur.Line))) do
    begin
      pList[J + 1]:= pList[J];
      Dec(J);
    end;
    pList[J + 1]:= Cur;
  end;
end;

{ ---- TTraceAnchorResolver ---- }

constructor TTraceAnchorResolver.Create(pIndex: TChartsIndex; pReader: TSourceReader; pWalker: TChainWalker; pCatalog: TSqlCatalog;
  pSet: TSqlTableSet);
begin
  inherited Create;
  FIndex:= pIndex;
  FReader:= pReader;
  FWalker:= pWalker;
  FCatalog:= pCatalog;
  FSet:= pSet;
end;

function TTraceAnchorResolver.ColumnFactNote(const pCs: TSqlColumnState; pSet: TSqlTableSet): string;
begin
  var At:= TraceAnchorText(pCs.Path, pCs.Line);
  if SameText(pCs.State, 'yes') then
  begin
    var N:= Length(pSet.Table(pCs.Table).Declarations);
    var Of_:= if N > 1 then Format('the newest of %d %s declarations', [N, pCs.Table]) else Format('the %s declaration', [pCs.Table]);
    Result:= Format('%s is a column of %s (SQL index, %s)', [pCs.Column, Of_, At]);
  end
  else
    Result:= TraceStopText(Format('%s of %s in the SQL scripts: %s', [pCs.Column, pCs.Table,
      TRegEx.Replace(pCs.Caption, RE_BRACKET_PAIR, '($1)')]));
end;

procedure TTraceAnchorResolver.CompleteAnchorFromDataSet(pR: TAnchorResult; const pDs: TTraceDataSet; const pCol, pBindGrade,
  pBindNote: string);
begin
  pR.DataSet:= pDs;
  pR.HasDataSet:= True;
  pR.FieldName:= pCol;
  pR.Items.Add(NewTraceStep(KIND_STEP, 'BINDS ' + pDs.Name + ' : ' + pDs.TypeName, TraceAnchorText(pDs.FileName, pDs.Line), pBindGrade,
    '', pBindNote));
  var Lit:= FWalker.DataSetTableLiterals(ChainOfDataSet(pDs));
  if Length(Lit) <> 1 then
  begin
    if Length(Lit) = 0 then
      pR.Stop:= Format('no upper-case table-name literal shares a line with %s in %s -- the table cannot be inferred',
        [pDs.Name, UnitNameOf(pDs.FileName)])
    else
    begin
      var Names: TArray<string>:= [];
      for var L in Lit do
        Names:= Names + [L.Table];
      pR.Stop:= Format('%d tables share a line with %s in %s (%s) -- cannot tell which', [Length(Lit), pDs.Name, UnitNameOf(pDs.FileName),
        string.Join(', ', Names)]);
    end;
    pR.StopAnchor:= TraceAnchorText(pDs.FileName, pDs.Line);
    Exit;
  end;
  pR.Table:= Lit[0].Table;
  var Routine:= '';
  var Encl:= FIndex.Query(Format('SELECT e.qualified_name AS q FROM refs r JOIN symbols e ON e.id = r.enclosing_symbol_id ' +
    'WHERE r.file_id = %d AND r.start_line = %d AND r.name_text = ''%s'' LIMIT 1', [pDs.Fid, Lit[0].Line, TChartsIndex.SqlText(pDs.Name)]));
  try
    if Encl.Count > 0 then
      Routine:= LastSegment(Encl[0].S('q'));
  finally
    Encl.Free;
  end;
  pR.Items.Add(NewTraceStep(KIND_STEP, 'READS ' + pR.Table, TraceAnchorText(pDs.FileName, Lit[0].Line), GRADE_INFERRED, Routine,
    Format('the table literal beside %s on %d line(s)', [pDs.Name, Lit[0].Lines])));
  if pCol = '' then
  begin
    pR.Stop:= pDs.Name + ' reaches ' + pR.Table + ' but the selection binds no column';
    pR.StopAnchor:= TraceAnchorText(pDs.FileName, pDs.Line);
    Exit;
  end;
  pR.Column:= UpperCase(pCol);
  pR.TableColumn:= pR.Table + '.' + pR.Column;
  var Cs:= SqlColumnState(FCatalog, FSet, pR.Table, pCol, TServerSqlHit.None, '');
  if Cs.IsColumn then
    pR.Items.Add(NewTraceStep(KIND_STEP, 'READS ' + pR.TableColumn, TraceAnchorText(Cs.Path, Cs.Line), GRADE_INFERRED, '',
      ColumnFactNote(Cs, FSet), ASK_COLUMN))
  else
  begin
    pR.Stop:= pR.TableColumn + ': ' + Cs.Caption;
    pR.StopAnchor:= pR.Items[pR.Items.Count - 1].Anchor;
    { calc-field brief: before this stop the question unit asks DRagLint.Charts.Trace.Calc whether the field is CALCULATED
      (Part 6, ApplyCalcFieldInfo); this unit leaves Calc nil (RT2). }
    pR.TableColumn:= '';
  end;
end;

function TTraceAnchorResolver.PropertyReadField(const pProp: TTraceDataSet; const pAssignFile: string; pAssignLine: Integer): TPropField;
begin
  Result:= Default(TPropField);
  var Ma:= FIndex.Query(Format('SELECT DISTINCT ma.accessor_symbol_id AS aid FROM member_accesses ma JOIN refs r ON r.id = ma.ref_id ' +
    'JOIN files f ON f.id = r.file_id WHERE f.path = ''%s'' AND r.start_line = %d AND ma.member_symbol_id = %d ' +
    'AND ma.accessor_kind = ''field'' AND ma.accessor_symbol_id IS NOT NULL',
    [TChartsIndex.SqlText(pAssignFile), pAssignLine, pProp.Id]));
  try
    if Ma.Count = 1 then
    begin
      var Fr:= FIndex.Query('SELECT ' + SYM_COLS + ' FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.id = ' +
        IntToStr(Ma[0].I('aid')) + ' AND s.kind = ''field''');
      try
        if Fr.Count = 1 then
        begin
          Result.Found:= True;
          Result.Field:= DataSetOfRow(Fr[0]);
          Result.Accessor:= Fr[0].S('name');
          { FW-R2: a bare :N would read as a line of the field's file when the assignment sits in another one }
          Result.Reason:= Format('the read accessor of %s, bound on the assignment line %s',
            [pProp.Name, TraceNoteLocator(Fr[0].S('path'), pAssignFile, pAssignLine)]);
          Exit;
        end;
      finally
        Fr.Free;
      end;
    end;
  finally
    Ma.Free;
  end;
  if not FReader.SourceFresh(pProp.FileName) then
  begin
    Result.StaleFile:= pProp.FileName;
    Result.Reason:= ExtractFileName(pProp.FileName) + ' differs from the indexed copy -- the property''s read accessor is not read';
    Exit;
  end;
  var Lines:= FReader.StrippedSourceLines(FReader.ReadPath(pProp.FileName));
  var Decl:= if (pProp.Line >= 1) and (pProp.Line <= Length(Lines)) then Lines[pProp.Line - 1] else '';
  var M:= TRegEx.Match(Decl, RE_READ);
  if not M.Success then
  begin
    Result.Reason:= Format('property %s at %s:%d has no read accessor on its declaration line', [pProp.Name, ExtractFileName(pProp.FileName),
      pProp.Line]);
    Exit;
  end;
  Result.Accessor:= M.Groups[1].Value;
  var Fr:= FIndex.Query('SELECT ' + SYM_COLS + ' FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.parent_id = ' +
    IntToStr(pProp.ClassId) + ' AND s.name = ''' + TChartsIndex.SqlText(Result.Accessor) + ''' AND s.kind = ''field''');
  try
    if Fr.Count <> 1 then
    begin
      Result.Reason:= Format('the read accessor %s of %s is not a field of its class (%d matches) -- a getter method is not followed',
        [Result.Accessor, pProp.Name, Fr.Count]);
      Exit;
    end;
    Result.Found:= True;
    Result.Field:= DataSetOfRow(Fr[0]);
    Result.Grade:= GRADE_BY_NAME;
    Result.Reason:= Format('the read accessor of %s, by name in its class', [pProp.Name]);
  finally
    Fr.Free;
  end;
end;

{ the datasource chain that did not dangle: its hops, then the dataset field named by the assignment's right-hand side }
procedure TTraceAnchorResolver.FollowDirectChain(const pCh: TDataSourceChain; const pDsText: string; pS1: TTraceItem; pR: TAnchorResult;
  const pCol: string);
begin
  if pCh.Grade = GRADE_STALE then
  begin
    { the file that differs is the one holding the DataSet sites -- the datasource's unit }
    pR.StaleFile:= pCh.PasFile;
    for var S in pCh.DataSetSites do
      if SameText(S.Kind, 'stale') then
      begin
        pR.StaleFile:= S.Path;
        Break;
      end;
    pR.Stop:= pCh.StopReason;
    pR.StopAnchor:= pS1.Anchor;
    Exit;
  end;
  var A0: TDataSetSite:= Default(TDataSetSite);
  var HasAssign:= False;
  for var S in pCh.DataSetSites do
    if SameText(S.Kind, 'assign') and not SameText(S.Rhs, 'nil') then
    begin
      A0:= S;
      HasAssign:= True;
      Break;
    end;
  if not HasAssign or not pCh.RhsType.Present or (pCh.RhsType.TypePath = '') then
  begin
    pR.Stop:= if pCh.StopReason <> '' then pCh.StopReason
      else Format('the datasource %s names no dataset field this index can follow (chain grade %s)', [pDsText, pCh.Grade]);
    pR.StopAnchor:= pS1.Anchor;
    Exit;
  end;
  for var H in pCh.Hops do
  begin
    if SameText(H.Hop, 'table') then
      Continue;     { the table is re-derived beside the DATASET, not from the unit's literals }
    var Grade:= HopGrade(H.Grade);
    { final-review M2: the ask that would retire THIS hop's grade, or none; rhs-type [by name] is matched to a class by NAME }
    var Ask:= if (Grade <> '') and SameText(H.Hop, 'rhs-type') then ASK_TYPE_USE else '';
    pR.Items.Add(NewTraceStep(KIND_STEP, ChainVerb(H.Hop) + ' ' + TraceWord(H.Caption, HOP_WORD_MAX), TraceAnchorText(H.Path, H.Line),
      Grade, '', TraceNoteText(H.Reason), Ask));
  end;
  var DsName:= LastSegment(TRegEx.Replace(A0.Rhs, RE_SELF, ''));
  var Tf:= FIndex.Query('SELECT s.id AS id FROM symbols s JOIN files f ON f.id = s.file_id WHERE f.path = ''' +
    TChartsIndex.SqlText(pCh.RhsType.TypePath) + ''' AND s.kind IN (''class'',''interface'') AND UPPER(s.name) = UPPER(''' +
    TChartsIndex.SqlText(pCh.RhsType.TypeName) + ''')');
  var TypeId:= if Tf.Count = 1 then Tf[0].I('id') else -1;
  Tf.Free;
  var DsRows: TObjectList<TIndexRow>:= nil;
  if TypeId >= 0 then
    DsRows:= FIndex.Query('SELECT ' + SYM_COLS + ', s.kind AS kind FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.parent_id = ' +
      IntToStr(TypeId) + ' AND s.name = ''' + TChartsIndex.SqlText(DsName) + ''' AND s.kind IN (''field'',''property'')');
  try
    if (DsRows = nil) or (DsRows.Count <> 1) then
    begin
      pR.Stop:= Format('the dataset %s (assigned at :%d) is not a field or property of %s in this index', [A0.Rhs, A0.Line,
        pCh.RhsType.TypeName]);
      pR.StopAnchor:= TraceAnchorText(A0.Path, A0.Line);
      Exit;
    end;
    var D:= DataSetOfRow(DsRows[0]);
    if DsRows[0].S('kind') <> 'property' then
    begin
      CompleteAnchorFromDataSet(pR, D, pCol, '', BIND_NOTE);
      Exit;
    end;
    { final-review I8: a PROPERTY is not the dataset -- its read accessor is. The wirings and the table literal sit on the FIELD
      behind it, so the anchor follows the accessor to that field and stops (if it must) on the field }
    var Pf:= PropertyReadField(D, A0.Path, A0.Line);
    var Note:= 'a property of ' + pCh.RhsType.TypeName;
    if Pf.Accessor <> '' then
      Note:= Note + ', read ' + Pf.Accessor;
    pR.Items.Add(NewTraceStep(KIND_STEP, 'READS ' + D.Name + ' : ' + D.TypeName, TraceAnchorText(D.FileName, D.Line), '', '', Note));
    if (Pf.StaleFile <> '') or not Pf.Found then
    begin
      pR.StaleFile:= Pf.StaleFile;
      pR.Stop:= Pf.Reason;
      pR.StopAnchor:= pR.Items[pR.Items.Count - 1].Anchor;
      Exit;
    end;
    CompleteAnchorFromDataSet(pR, Pf.Field, pCol, Pf.Grade, 'the anchor dataset, ' + Pf.Reason);
  finally
    DsRows.Free;
  end;
end;

procedure TTraceAnchorResolver.AnchorFromControl(const pForm, pCtl: string; pR: TAnchorResult);
begin
  var Fids: TArray<string>:= [];
  var Forms:= FIndex.Query('SELECT s.file_id AS fid, f.path AS path FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.kind = ''form'' ' +
    'AND UPPER(s.name) = UPPER(''' + TChartsIndex.SqlText(pForm) + ''')');
  try
    if Forms.Count = 0 then
      raise EChartsTrace.Create('round-trip: no form or data module named ' + pForm + ' in this index');
    for var F in Forms do
      Fids:= Fids + [IntToStr(F.I('fid'))];
  finally
    Forms.Free;
  end;
  var Cands:= FIndex.Query('SELECT c.id AS id, c.name AS name, c.qualified_name AS q, c.signature AS sig, c.parent_id AS pid, ' +
    'c.start_line AS line, c.file_id AS fid, f.path AS path FROM symbols c JOIN files f ON f.id = c.file_id WHERE c.kind = ''component'' ' +
    'AND c.file_id IN (' + string.Join(',', Fids) + ') AND UPPER(c.name) = UPPER(''' + TChartsIndex.SqlText(pCtl) + ''')');
  try
    if Cands.Count = 0 then
      raise EChartsTrace.Create('round-trip: no component named ' + pCtl + ' on ' + pForm);
    if Cands.Count > 1 then
    begin
      var Qs: TArray<string>:= [];
      for var C in Cands do
        Qs:= Qs + [C.S('q')];
      raise EChartsTrace.Create(Format('round-trip: %s.%s names %d components (%s)', [pForm, pCtl, Cands.Count, string.Join(', ', Qs)]));
    end;
    var Cid:= Cands[0].I('id');
    var Dfm:= Cands[0].S('path');
    var Fid:= Cands[0].I('fid');
    var Cpid:= Cands[0].I('pid');
    var Short:= pForm + '.' + Cands[0].S('name');
    var CtlLine:= Cands[0].I('line');
    var CtlName:= Cands[0].S('name');
    var CtlSig:= Cands[0].S('sig');
    var Fb:= FIndex.Query('SELECT owner_name AS prop, text AS col, start_line AS line FROM string_literals WHERE kind = ''dfm-prop'' ' +
      'AND symbol_id = ' + IntToStr(Cid) + ' AND owner_name IN (''DataBinding.FieldName'',''DataBinding.DataField'',''DataField'') ORDER BY start_line');
    var DsText:= '';
    var DsRow:= FIndex.Query('SELECT ' + ControlDataSourceSql('sl', 'c') + ' AS ds FROM symbols c JOIN (SELECT ' + IntToStr(Fid) +
      ' AS file_id) sl WHERE c.id = ' + IntToStr(Cid));
    try
      if DsRow.Count > 0 then
        DsText:= DsRow[0].S('ds');
      if (Fb.Count = 0) or (DsText = '') then
      begin
        var Why:= if (Fb.Count = 0) and (DsText = '') then 'no field binding and no DataSource'
          else if Fb.Count = 0 then 'no field binding' else 'no DataSource';
        pR.Stop:= Short + ' (' + CtlSig + ') is not data-bound: ' + Why + ' on it or its two enclosing components in the DFM';
        pR.StopAnchor:= TraceAnchorText(Dfm, CtlLine);
        Exit;
      end;
      var Col:= Fb[0].S('col');
      var FbProp:= Fb[0].S('prop');
      var FbLine:= Fb[0].I('line');
      var Own:= FIndex.Query('SELECT d.symbol_id AS sid, d.owner_name AS prop, d.start_line AS line, s.name AS owner FROM string_literals d ' +
        'JOIN symbols s ON s.id = d.symbol_id WHERE d.kind = ''dfm-prop'' AND d.file_id = ' + IntToStr(Fid) +
        ' AND d.owner_name IN (''DataSource'',''DataBinding.DataSource'',''DataController.DataSource'') AND d.text = ''' +
        TChartsIndex.SqlText(DsText) + ''' AND d.symbol_id IN (' + IntToStr(Cid) + ', ' + IntToStr(Cpid) +
        ', (SELECT g.parent_id FROM symbols g WHERE g.id = ' + IntToStr(Cpid) + ')) ORDER BY d.start_line');
      var PropSid := 0;
      var PropName := '';
      var PropLine := 0;
      var Owner := '';
      try
        { nearest first, as ControlDataSourceSql picked it: the control, its parent, its grandparent }
        var Best := MaxInt;
        for var O in Own do
        begin
          var Rank:= if O.I('sid') = Cid then 0 else if (Cpid <> 0) and (O.I('sid') = Cpid) then 1 else 2;
          if Rank < Best then
          begin
            Best:= Rank;
            PropSid:= O.I('sid');
            PropName:= O.S('prop');
            PropLine:= O.I('line');
            Owner:= O.S('owner');
          end;
        end;
      finally
        Own.Free;
      end;
      var S1:= NewTraceStep(KIND_STEP, 'BINDS ' + CtlName + ' : ' + CtlSig + ' ONTO ' + Col, TraceAnchorText(Dfm, FbLine), '', '', FbProp);
      pR.Items.Add(S1);
      var Ch:= FWalker.DataSourceChain(Dfm, DsText);
      var Via:= if PropSid <> Cid then Owner + '.' + PropName else PropName;
      var ViaNote:= if Ch.Dangling then 'dangling: module ' + Ch.Module + ' is declared nowhere in this index' else '';
      S1.Children.Add(NewTraceFacet('VIA', Via + ' = ' + DsText, TraceAnchorText(Dfm, PropLine), ViaNote));
      { the re-point rule (nil sites skipped, a stale form unit REFUSES, several different right-hand sides a named stop) is
        TChainWalker.RePointPick -- ONE copy, shared with feeds-from and lands-where }
      var Pk: TRePointPick:= Default(TRePointPick);
      if Ch.Grade = GRADE_DANGLING then
        Pk:= FWalker.RePointPick(Ch, Owner);
      if Pk.Status = 'stale' then
      begin
        pR.StaleFile:= Pk.StaleFile;
        pR.Stop:= Pk.Stop;
        pR.StopAnchor:= S1.Anchor;
        Exit;
      end;
      if Pk.Status = 'multi-rhs' then
      begin
        pR.Stop:= Pk.Stop;
        pR.StopAnchor:= S1.Anchor;
        Exit;
      end;
      if Pk.Status = 'follow' then
      begin
        var Rc:= FWalker.RePointChain(Pk.Rows[0]);
        for var H in Rc.Hops do
          pR.Items.Add(NewTraceStep(KIND_STEP, RePointVerb(H.Hop) + ' ' + TraceWord(H.Caption, HOP_WORD_MAX), TraceAnchorText(H.Path, H.Line),
            HopGrade(H.Grade), H.Routine, TraceNoteText(H.Reason), H.Ask));
        var Last:= pR.Items[pR.Items.Count - 1].Anchor;
        if Rc.StaleFile <> '' then
        begin
          pR.StaleFile:= Rc.StaleFile;
          pR.Stop:= Rc.StopReason;
          pR.StopAnchor:= Last;
        end
        else if Rc.StopReason <> '' then
        begin
          pR.Stop:= Rc.StopReason;
          pR.StopAnchor:= Last;
        end
        else
          CompleteAnchorFromDataSet(pR, DataSetOfChain(Rc.DataSet), Col, '', BIND_NOTE);
        Exit;
      end;
      FollowDirectChain(Ch, DsText, S1, pR, Col);
    finally
      DsRow.Free;
      Fb.Free;
    end;
  finally
    Cands.Free;
  end;
end;

function TTraceAnchorResolver.FieldVarWriteRows(pClassId: Integer; const pWhere: string): TArray<TFieldVarWrite>;
begin
  { calc-field fix round 2: ONE pass over the refs of the write lines (materialized), the class's dataset fields passed as IN-lists.
    The per-line correlated JOIN took ~9-10 s over one class's 133 write lines under load -- the engine's 10 s cap. }
  var Names: TArray<string>:= [];
  var Ids: TArray<string>:= [];
  var Dsf:= FIndex.Query('SELECT s.id AS id, s.name AS name FROM symbols s WHERE s.parent_id = ' + IntToStr(pClassId) +
    ' AND s.kind = ''field'' AND ' + DataSetTypeSql('s'));
  try
    for var D in Dsf do
    begin
      Names:= Names + [D.S('name')];
      Ids:= Ids + [IntToStr(D.I('id'))];
    end;
  finally
    Dsf.Free;
  end;
  var SelfNames: TArray<string>:= [];
  for var N in Names do
    SelfNames:= SelfNames + ['Self.' + N];
  var NameList:= if Length(Names) > 0 then TChartsIndex.SqlInList(Names) else 'NULL';
  var SelfList:= if Length(Names) > 0 then TChartsIndex.SqlInList(SelfNames) else 'NULL';
  var IdList:= if Length(Ids) > 0 then string.Join(',', Ids) else 'NULL';
  const Dk = '(lm.kind = ''read'' OR (lm.kind = ''member-access'' AND lm.nm = ''FieldByName''))';
  var Rows:= FIndex.AllRows(
    'WITH w AS MATERIALIZED (SELECT v.name AS var, v.qualified_name AS vq, r.start_line AS line, r.file_id AS fid, r.id AS rid ' +
    'FROM refs r JOIN symbols v ON v.id = r.symbol_id WHERE ' + pWhere + ' AND r.kind = ''write''), ' +
    'lm AS MATERIALIZED (SELECT m.file_id AS fid, m.start_line AS line, m.kind AS kind, m.name_text AS nm, m.receiver_text AS rc, ' +
    'm.symbol_id AS sid FROM refs m WHERE m.file_id IN (SELECT fid FROM w) AND m.start_line IN (SELECT line FROM w)), ' +
    'dsn AS MATERIALIZED (SELECT fid, line, nm AS x FROM lm WHERE ' + Dk + ' AND nm IN (' + NameList + ') ' +
    'UNION ALL SELECT fid, line, rc FROM lm WHERE ' + Dk + ' AND rc IN (' + NameList + ') ' +
    'UNION ALL SELECT fid, line, SUBSTR(rc, 6) FROM lm WHERE ' + Dk + ' AND rc IN (' + SelfList + ')) ' +
    'SELECT w.var AS var, w.vq AS vq, w.line AS line, f.path AS path, ' +
    '(SELECT GROUP_CONCAT(DISTINCT x) FROM dsn WHERE dsn.fid = w.fid AND dsn.line = w.line) AS ds, ' +
    '(SELECT MAX(lm.sid IS NOT NULL) FROM lm WHERE lm.fid = w.fid AND lm.line = w.line AND lm.kind = ''read'' AND lm.sid IN (' + IdList + ')) AS bound, ' +
    '(SELECT COUNT(*) FROM lm WHERE lm.fid = w.fid AND lm.line = w.line AND lm.kind = ''member-access'' AND lm.nm = ''FieldByName'' ' +
    'AND (lm.rc IN (' + NameList + ') OR lm.rc IN (' + SelfList + '))) AS fbn, ' +
    '(SELECT GROUP_CONCAT(DISTINCT lm.nm) FROM lm WHERE lm.fid = w.fid AND lm.line = w.line AND lm.kind = ''call'') AS calls, ' +
    '(SELECT GROUP_CONCAT(sl.text, ''|'') FROM string_literals sl WHERE sl.file_id = w.fid AND sl.start_line = w.line AND sl.kind = ''literal'') AS col ' +
    'FROM w JOIN files f ON f.id = w.fid', 'w.line, w.rid');
  try
    var Out_:= TList<TFieldVarWrite>.Create;
    try
      for var R in Rows do
      begin
        var W: TFieldVarWrite;
        W.VarName:= R.S('var');
        W.VarQName:= R.S('vq');
        W.Line:= R.I('line');
        W.Path:= R.S('path');
        W.Ds:= R.S('ds');
        W.Bound:= R.I('bound');
        W.Fbn:= R.I('fbn');
        W.Calls:= R.S('calls');
        W.Col:= R.S('col');
        Out_.Add(W);
      end;
      Result:= Out_.ToArray;
    finally
      Out_.Free;
    end;
  finally
    Rows.Free;
  end;
end;

procedure TTraceAnchorResolver.AnchorFromFieldVar(pMemId: Integer; const pMemPath: string; pMemLine: Integer; const pTarget, pName: string;
  pR: TAnchorResult);
begin
  var Cpid:= 0;
  var Cls:= FIndex.Query('SELECT s.parent_id AS pid FROM symbols s WHERE s.id = ' + IntToStr(pMemId));
  try
    if Cls.Count > 0 then
      Cpid:= Cls[0].I('pid');
  finally
    Cls.Free;
  end;
  var W:= FieldVarWriteRows(Cpid, 'r.symbol_id = ' + IntToStr(pMemId));
  { a pair only where the line names exactly ONE dataset field and ONE literal }
  var Fp:= FieldVarPairs(W);
  if Length(Fp.Pairs) <> 1 then
  begin
    var Shown: TArray<string>:= [];
    for var P in Fp.Pairs do
      Shown:= Shown + [StringReplace(P, '|', '.', [rfReplaceAll])];
    var Listed:= '';
    if Length(Shown) > 0 then
      Listed:= ' (' + string.Join(', ', Shown) + ')';
    pR.Stop:= Format('%s is written on %d line(s) naming %d (dataset field, column literal) pair(s)%s -- cannot tell which',
      [pTarget, Length(W), Length(Fp.Pairs), Listed]);
    pR.StopAnchor:= TraceAnchorText(pMemPath, pMemLine);
    Exit;
  end;
  var Bar:= Pos('|', Fp.Pairs[0]);
  var DsName:= Copy(Fp.Pairs[0], 1, Bar - 1);
  var Col:= Copy(Fp.Pairs[0], Bar + 1, MaxInt);
  var DsRow:= FIndex.Query('SELECT ' + SYM_COLS + ' FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.parent_id = ' + IntToStr(Cpid) +
    ' AND s.name = ''' + TChartsIndex.SqlText(DsName) + ''' AND s.kind = ''field''');
  try
    if DsRow.Count <> 1 then
    begin
      pR.Stop:= DsName + ' is not a field of the class declaring ' + pName;
      pR.StopAnchor:= TraceAnchorText(pMemPath, pMemLine);
      Exit;
    end;
    var Site:= Fp.Ok[0];
    var G:= FieldVarSiteGrade(Site, DsName);
    pR.Items.Add(NewTraceStep(KIND_STEP, 'SETS ' + pName + ' := ' + DsName + ' field ''' + Col + '''', TraceAnchorText(Site.Path, Site.Line),
      G.Grade, '', G.Reason, G.Ask));
    CompleteAnchorFromDataSet(pR, DataSetOfRow(DsRow[0]), Col, '', BIND_NOTE);
  finally
    DsRow.Free;
  end;
end;

function TTraceAnchorResolver.TableDataSetRows(const pTable: string): TObjectList<TIndexRow>;
begin
  Result:= FIndex.Query('SELECT DISTINCT s.id AS id, s.name AS name, s.qualified_name AS q, s.signature AS sig, s.start_line AS line, ' +
    'f.path AS path, s.file_id AS fid, s.parent_id AS pid FROM string_literals sl JOIN refs r ON r.file_id = sl.file_id ' +
    'AND r.start_line = sl.start_line AND r.kind = ''read'' JOIN symbols s ON s.name = r.name_text AND s.file_id = sl.file_id ' +
    'AND s.kind = ''field'' JOIN files f ON f.id = s.file_id WHERE sl.kind = ''literal'' AND sl.text = ''' + TChartsIndex.SqlText(pTable) +
    ''' AND ' + DataSetTypeSql('s') + ' ORDER BY s.qualified_name');
end;

procedure TTraceAnchorResolver.AnchorFromColumn(const pTable, pCol: string; pR: TAnchorResult);
begin
  var Cands:= TableDataSetRows(pTable);
  try
    if Cands.Count <> 1 then
    begin
      var Qs: TArray<string>:= [];
      for var C in Cands do
        Qs:= Qs + [C.S('q')];
      pR.Stop:= Format('%s.%s: %d datasets load %s in this index (%s) -- pass the control or the dataset field',
        [pTable, pCol, Cands.Count, pTable, string.Join(', ', Qs)]);
      if Cands.Count > 0 then
        pR.StopAnchor:= TraceAnchorText(Cands[0].S('path'), Cands[0].I('line'))
      else
        pR.StopAnchor:= TraceAnchorText(FSet.Table(pTable).Path, FSet.Table(pTable).Line);
      pR.TableColumn:= pTable + '.' + pCol;
      Exit;
    end;
    CompleteAnchorFromDataSet(pR, DataSetOfRow(Cands[0]), pCol, '', BIND_NOTE);
  finally
    Cands.Free;
  end;
end;

procedure TTraceAnchorResolver.ResolveInto(const pTarget: string; pR: TAnchorResult);
begin
  var Tgt:= Trim(pTarget);
  if not TRegEx.IsMatch(Tgt, RE_TARGET, [roIgnoreCase]) then
    raise EChartsTrace.Create('round-trip: -Target takes <Form>.<Control>, <Unit>.<TForm>.<Control>, <Unit>.<TClass>.<TField variable> ' +
      'or TABLE.COLUMN, got ''' + pTarget + '''');
  var Segs:= Tgt.Split(['.']);
  if (Length(Segs) = 2) and (FSet.Table(UpperCase(Segs[0])) <> nil) then
  begin
    AnchorFromColumn(UpperCase(Segs[0]), UpperCase(Segs[1]), pR);
    Exit;
  end;
  if Length(Segs) >= MIN_UNIT_SEGMENTS then
  begin
    var MemName:= Segs[High(Segs)];
    var ClsName:= Segs[High(Segs) - 1];
    var UnitName:= string.Join('.', Copy(Segs, 0, Length(Segs) - 2));
    var Cls:= FIndex.Query('SELECT s.id AS id FROM symbols s WHERE s.qualified_name = ''' + TChartsIndex.SqlText(UnitName + '.' + ClsName) +
      ''' AND s.kind = ''class''');
    var ClsCount:= Cls.Count;
    var ClsId:= if ClsCount > 0 then Cls[0].I('id') else 0;
    Cls.Free;
    if ClsCount <> 1 then
      raise EChartsTrace.Create(Format('round-trip: %s: %s.%s is not a class of this index (%d matches)', [Tgt, UnitName, ClsName, ClsCount]));
    var Mem:= FIndex.Query('SELECT s.id AS id, s.kind AS kind, s.signature AS sig, s.start_line AS line, f.path AS path FROM symbols s ' +
      'JOIN files f ON f.id = s.file_id WHERE s.parent_id = ' + IntToStr(ClsId) + ' AND s.name = ''' + TChartsIndex.SqlText(MemName) + '''');
    try
      if (Mem.Count = 1) and TRegEx.IsMatch(Trim(Mem[0].S('sig')), RE_FIELD_SIG) then
      begin
        AnchorFromFieldVar(Mem[0].I('id'), Mem[0].S('path'), Mem[0].I('line'), Tgt, MemName, pR);
        Exit;
      end;
      var FormName:= TRegEx.Replace(ClsName, RE_T_PREFIX, '');
      var Fm:= FIndex.Query('SELECT COUNT(*) AS n FROM symbols WHERE kind = ''form'' AND UPPER(name) = UPPER(''' + TChartsIndex.SqlText(FormName) + ''')');
      var FormCount:= Fm[0].I('n');
      Fm.Free;
      if FormCount <> 1 then
      begin
        pR.Stop:= Format('%s: %s is not a TField variable of %s and no DFM object is named %s (the T-less name is a convention)',
          [Tgt, MemName, ClsName, FormName]);
        pR.StopAnchor:= if Mem.Count > 0 then TraceAnchorText(Mem[0].S('path'), Mem[0].I('line')) else UNKNOWN_ANCHOR;
        Exit;
      end;
      pR.Grades:= pR.Grades + [GRADE_BY_NAME];     { the class -> DFM object hop is a naming convention }
      Segs:= [FormName, MemName];
    finally
      Mem.Free;
    end;
  end;
  if Length(Segs) <> 2 then
    raise EChartsTrace.Create('round-trip: ' + Tgt + ' is not <Form>.<Control>');
  AnchorFromControl(Segs[0], Segs[1], pR);
end;

function TTraceAnchorResolver.ResolveTraceAnchor(const pTarget: string): TAnchorResult;
begin
  Result:= TAnchorResult.Create;
  var Resolved:= False;
  try
    ResolveInto(pTarget, Result);
    Resolved:= True;
  finally
    if not Resolved then
      FreeAndNil(Result);
  end;
end;

function TTraceAnchorResolver.EventWiring(const pDs: TTraceDataSet; const pEvents: TArray<string>): TArray<TEventWiring>;
begin
  var Events: TArray<string>:= pEvents;
  if Length(Events) = 0 then
    for var E in RT_EVENTS do
      Events:= Events + [E];
  var Out_:= TList<TEventWiring>.Create;
  try
    var Rows:= FIndex.AllRows('SELECT r.start_line AS line, r.id AS rid, r.name_text AS ev, e.qualified_name AS routine, ' +
      '(SELECT h.name_text FROM refs h WHERE h.file_id = r.file_id AND h.start_line = r.start_line AND h.kind = ''read'' AND h.name_text <> ''' +
      TChartsIndex.SqlText(pDs.Name) + ''' AND h.name_text <> r.name_text ORDER BY h.start_col DESC LIMIT 1) AS handler ' +
      'FROM refs r LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id WHERE r.file_id = ' + IntToStr(pDs.Fid) +
      ' AND r.kind = ''member-access'' AND r.name_text IN (' + TChartsIndex.SqlInList(Events) + ') AND r.receiver_text = ''' +
      TChartsIndex.SqlText(pDs.Name) + '''', 'r.start_line, r.id');
    try
      for var R in Rows do
      begin
        if R.S('handler') = '' then
          Continue;
        var H:= FIndex.Query('SELECT s.id AS id, s.qualified_name AS q, s.impl_start_line AS istart, f.path AS path FROM symbols s ' +
          'JOIN files f ON f.id = s.file_id WHERE s.parent_id = ' + IntToStr(pDs.ClassId) + ' AND s.name = ''' + TChartsIndex.SqlText(R.S('handler')) +
          ''' AND s.kind = ''method'' AND s.impl_start_line > 0');
        try
          if H.Count <> 1 then
            Continue;
          var W: TEventWiring;
          W.Line:= R.I('line');
          W.Event:= R.S('ev');
          W.Handler:= R.S('handler');
          W.HandlerId:= H[0].I('id');
          W.HandlerShort:= ShortName(H[0].S('q'), UnitNameOf(H[0].S('path')));
          W.HandlerImpl:= H[0].I('istart');
          W.HandlerPath:= H[0].S('path');
          W.Routine:= LastSegment(R.S('routine'));
          W.Grade:= GRADE_BY_NAME;
          Out_.Add(W);
        finally
          H.Free;
        end;
      end;
    finally
      Rows.Free;
    end;
    Result:= Out_.ToArray;
  finally
    Out_.Free;
  end;
  { final-review I4: in write preference order (AfterPost first), not by line -- the WRITE direction starts at [0] }
  SortWirings(Result);
end;

end.
