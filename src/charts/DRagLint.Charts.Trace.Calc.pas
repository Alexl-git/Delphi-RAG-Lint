unit DRagLint.Charts.Trace.Calc;

(* The CALCULATED anchor field (a port of charts\src\Trace.Walk.ps1 Part 6, lines 2025-2530 -- calc-field
  brief, owner 2026-09-28; the PS output is the reference). A selection bound to a field that is not a column
  of its table stops at the anchor. When the field is CALCULATED -- its dataset has an OnCalcFields wiring
  (EventWiring: a same-line name match, E3) AND that handler WRITES the field, through a TField variable bound
  to the field's name (FieldVarWriteRows, the Task 3 rule) or through FieldByName('<name>') -- the STOPS says
  so, carries the handler's own guards as conditions (VERBATIM, the shim), and the emitter offers the SOURCE
  fields the computation reads, each with a ready command to trace it instead. Nothing here names a form, a
  dataset, a table or a field: the anchor parametrises every rule. Deeper computation inside a called routine
  is NOT walked, and the trace says so.

  Three layers, as in the PS: TCalcFactsReader.Facts reads the index and the FRESH source (a stale file
  refuses, AC-14); ResolveCalcField decides and lists the sources, PURE over those facts (synthetic facts test
  it); NewCalcFieldItems turns the result into Form A items, pure. Out of scope and NAMED, never offered: a
  field written only in another event's handler (AfterScroll, OnNewRecord, ...) and a field whose creating
  routine sets FieldKind fkLookup.

  PowerShell traps closed here: -eq / -in / -contains / -like / -match are case-INSENSITIVE (SameText, ci
  dictionaries, roIgnoreCase) and -cmatch / [regex]::Match are not; a hashtable and an [ordered] map are
  case-insensitive; Sort-Object is stable (StableSort); Select-Object -Unique on strings is case-SENSITIVE
  while Sort-Object -Unique is not; the unary-comma array returns are plain arrays. *)

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Charts.Index
  , DRagLint.Charts.Source
  , DRagLint.Charts.Sql
  , DRagLint.Charts.Trace.FormA
  , DRagLint.Charts.Trace.Anchor
  ;

const
  /// <summary>The FieldKind values the creating routine can set (the PS CalcFkKinds).</summary>
  CALC_FK_KINDS: array[0..4] of string = ('fkCalculated', 'fkLookup', 'fkInternalCalc', 'fkAggregate', 'fkData');
  /// <summary>The built-in types whose name is a typecast head (`Integer(x)`): a type, not a value.</summary>
  CALC_BUILTIN_TYPES: array[0..31] of string = ('Integer', 'Cardinal', 'ShortInt', 'SmallInt', 'LongInt', 'Int64', 'UInt64', 'Byte',
    'Word', 'LongWord', 'NativeInt', 'NativeUInt', 'Boolean', 'ByteBool', 'WordBool', 'LongBool', 'Char', 'AnsiChar', 'WideChar',
    'string', 'AnsiString', 'WideString', 'UnicodeString', 'Single', 'Double', 'Extended', 'Real', 'Currency', 'Comp', 'Variant',
    'Pointer', 'TDateTime');
  /// <summary>The kinds of a bound read that are a CONSTANT of the computation (an enum value, a type, a routine).</summary>
  CALC_CONST_KINDS: array[0..12] of string = ('const', 'constant', 'enum_value', 'enum', 'type', 'class', 'record', 'interface',
    'function', 'procedure', 'method', 'unit', 'resourcestring');
  /// <summary>TCalcInfo.Kind: an OnCalcFields handler writes the field.</summary>
  CALC_KIND_CALCULATED = 'calculated';
  /// <summary>TCalcInfo.Kind: only another event's handler writes the field.</summary>
  CALC_KIND_EVENT = 'event';
  /// <summary>TCalcInfo.Kind: the creating routine sets FieldKind fkLookup.</summary>
  CALC_KIND_LOOKUP = 'lookup';

type
  /// <summary>One ref of a handler (the PS $H.Refs row): a read, write, call or member access with its binding.</summary>
  TCalcRef = record
    /// <summary>read, write, call or member-access.</summary>
    Kind : string;
    /// <summary>The name text.</summary>
    Nm   : string;
    /// <summary>The receiver text; '' for none.</summary>
    Recv : string;
    /// <summary>1-based line.</summary>
    Line : Integer;
    /// <summary>1-based start column.</summary>
    Col  : Integer;
    /// <summary>1-based end column, exclusive.</summary>
    ECol : Integer;
    /// <summary>The bound target symbol's id; 0 for an unbound name.</summary>
    Tid  : Integer;
    /// <summary>The bound target's kind.</summary>
    TKind: string;
    /// <summary>The bound target's declaration line.</summary>
    TDecl: Integer;
    /// <summary>The bound target's file as indexed.</summary>
    TPath: string;
  end;

  /// <summary>One handler's facts: its refs, its locals and parameters and its FRESH source.</summary>
  /// <remarks>Owns Locals. Nested routines' refs are left out, as the PS Get-RoutineFacts does.</remarks>
  TCalcHandler = class
  public
    /// <summary>The handler method's name.</summary>
    Name     : string;
    /// <summary>The handler's file as indexed.</summary>
    Path     : string;
    /// <summary>The implementation start line.</summary>
    ImplStart: Integer;
    /// <summary>The implementation end line.</summary>
    ImplEnd  : Integer;
    /// <summary>The refs by line then column.</summary>
    Refs     : TArray<TCalcRef>;
    /// <summary>Name -> 'local_var' or 'param' (case-insensitive).</summary>
    Locals   : TDictionary<string, string>;
    /// <summary>The raw lines, 1-based line = index + 1.</summary>
    Raw      : TArray<string>;
    /// <summary>The comment/string-stripped lines with the same columns.</summary>
    Stripped : TArray<string>;
    /// <summary>Constructor.</summary>
    constructor Create;
    /// <summary>Frees Locals.</summary>
    destructor Destroy; override;
  end;

  /// <summary>One event wired on the dataset, with its handler's facts.</summary>
  /// <remarks>Owns H.</remarks>
  TCalcWiring = class
  public
    /// <summary>The event name as written.</summary>
    Event   : string;
    /// <summary>The wiring line.</summary>
    Line    : Integer;
    /// <summary>The handler method's name.</summary>
    Handler : string;
    /// <summary>The file that wires it.</summary>
    WirePath: string;
    /// <summary>The handler's facts.</summary>
    H       : TCalcHandler;
    /// <summary>Destructor.</summary>
    destructor Destroy; override;
  end;

  /// <summary>One TField variable's binding from its write rows.</summary>
  TCalcBinding = record
    /// <summary>The variable's name.</summary>
    VarName: string;
    /// <summary>'' when exactly one (dataset field, column literal) pair binds it, else what the rows name instead.</summary>
    Why    : string;
    /// <summary>The dataset field.</summary>
    DataSet: string;
    /// <summary>The column literal.</summary>
    Literal: string;
    /// <summary>The binding line.</summary>
    Line   : Integer;
    /// <summary>The file of the binding line as indexed.</summary>
    Path   : string;
    /// <summary>The variable's qualified name (the -Target that traces it).</summary>
    Qname  : string;
    /// <summary>The Task 3 grade of the binding line.</summary>
    Grade  : string;
    /// <summary>The Task 3 reason.</summary>
    Reason : string;
    /// <summary>The engine ask that would retire the grade.</summary>
    Ask    : string;
    /// <summary>`via FF` / `by FieldByName` / `via one of A, B` / `with no call on the line`.</summary>
    Via    : string;
  end;

  /// <summary>The line that CREATES the field: its name as a literal beside the dataset, its first call and the FieldKind that call sets.</summary>
  TCalcCreating = record
    /// <summary>False for the PS $null.</summary>
    Present : Boolean;
    /// <summary>The creating line.</summary>
    Line    : Integer;
    /// <summary>The file of the line.</summary>
    Path    : string;
    /// <summary>The first call on the line; '' for none.</summary>
    Call    : string;
    /// <summary>The FieldKind the call's body sets on exactly one line; '' when not proven.</summary>
    Kind    : string;
    /// <summary>The line that sets it.</summary>
    KindLine: Integer;
    /// <summary>The file of that line.</summary>
    KindPath: string;
  end;

  /// <summary>The facts ResolveCalcField decides on (read from the index and the fresh source, or synthetic).</summary>
  /// <remarks>Owns Bindings, ClassFields and Wirings. IsColumn is the SQL catalogue's column test for the anchor table.</remarks>
  TCalcFacts = class
  public
    /// <summary>The field as the selection names it.</summary>
    Field        : string;
    /// <summary>The anchor dataset field's name.</summary>
    DsName       : string;
    /// <summary>The anchor table.</summary>
    Table        : string;
    /// <summary>The dataset's class name.</summary>
    OwnerClass   : string;
    /// <summary>The TField variables bound to the field.</summary>
    Vars         : TArray<string>;
    /// <summary>Variable -> binding (case-insensitive).</summary>
    Bindings     : TDictionary<string, TCalcBinding>;
    /// <summary>Class field -> declared type (case-insensitive).</summary>
    ClassFields  : TDictionary<string, string>;
    /// <summary>The wired events: OnCalcFields first, then by line.</summary>
    Wirings      : TObjectList<TCalcWiring>;
    /// <summary>The creating line.</summary>
    Creating     : TCalcCreating;
    /// <summary>How many datasets load Table.</summary>
    TableDataSets: Integer;
    /// <summary>Whether a literal is a column of Table.</summary>
    IsColumn     : TFunc<string, Boolean>;
    /// <summary>Constructor.</summary>
    constructor Create;
    /// <summary>Frees what it owns.</summary>
    destructor Destroy; override;
  end;

  /// <summary>One guard or enclosing condition of the computation, VERBATIM.</summary>
  TCalcCond = record
    /// <summary>WHEN or UNLESS.</summary>
    Keyword  : string;
    /// <summary>The condition as written.</summary>
    Condition: string;
    /// <summary>The line of the if / exit guard.</summary>
    Line     : Integer;
    /// <summary>`else Exit at :N`, `around the write(s) at :N`, or ''.</summary>
    Note     : string;
  end;

  /// <summary>The call that computes the value.</summary>
  TCalcHeadCall = record
    /// <summary>False when no write's right-hand side starts with a call.</summary>
    Present: Boolean;
    /// <summary>The call's name.</summary>
    Name   : string;
    /// <summary>The call's anchor.</summary>
    Anchor : string;
    /// <summary>`computed by this call at :N, its body is not walked[, nor are those of ...]`.</summary>
    Note   : string;
  end;

  /// <summary>One offered source as row data.</summary>
  TCalcSource = record
    /// <summary>The row text (`FROM T.C VIA V`).</summary>
    Text    : string;
    /// <summary>The line of the read.</summary>
    Line    : Integer;
    /// <summary>'' (certain), 'by name' or 'inferred'.</summary>
    Grade   : string;
    /// <summary>The note without the binding reason.</summary>
    Note    : string;
    /// <summary>The binding's reason, which NewCalcFieldItems states ONCE when every row shares it.</summary>
    Reason  : string;
    /// <summary>The engine ask; '' for none.</summary>
    Ask     : string;
    /// <summary>The -Target that traces it instead; '' when there is none.</summary>
    Target  : string;
    /// <summary>A field (mapped or not), not an other value.</summary>
    IsField : Boolean;
    /// <summary>'' or `case at :N` / `if at :N`: the read picks the formula.</summary>
    Selector: string;
    /// <summary>The name read.</summary>
    Name    : string;
  end;

  /// <summary>What ResolveCalcField decided: self-contained, so the facts may be freed.</summary>
  TCalcInfo = class
  public
    /// <summary>CALC_KIND_CALCULATED, CALC_KIND_EVENT or CALC_KIND_LOOKUP.</summary>
    Kind       : string;
    /// <summary>The field as the selection names it.</summary>
    Field      : string;
    /// <summary>The dataset field's name.</summary>
    DsName     : string;
    /// <summary>The anchor table.</summary>
    Table      : string;
    /// <summary>The stop text replacing the plain column stop.</summary>
    StopText   : string;
    /// <summary>The stop's note ('' for event and lookup).</summary>
    StopNote   : string;
    /// <summary>The stop's anchor (File.ext:line).</summary>
    Anchor     : string;
    /// <summary>The handler method's name (calculated only).</summary>
    HandlerName: string;
    /// <summary>The handler's file as indexed (calculated only).</summary>
    HandlerPath: string;
    /// <summary>The guards and enclosing conditions (calculated only).</summary>
    Conds      : TArray<TCalcCond>;
    /// <summary>Generated reasons for shapes the shim cannot read (calculated only).</summary>
    CondUnknown: TArray<string>;
    /// <summary>The offered sources, in source order (calculated only).</summary>
    Sources    : TArray<TCalcSource>;
    /// <summary>The call that computes the value.</summary>
    HeadCall   : TCalcHeadCall;
  end;

  /// <summary>The Form A items of a calculated anchor.</summary>
  /// <remarks>The caller owns Stop and Rows.</remarks>
  TCalcFieldItems = record
    /// <summary>The STOPS step with its conditions and the VIA facet.</summary>
    Stop: TTraceItem;
    /// <summary>The DERIVED section's lead-in.</summary>
    Note: string;
    /// <summary>One numbered step per source, each with a REGENERATE facet when it has a target.</summary>
    Rows: TObjectList<TTraceItem>;
  end;

  /// <summary>Reads the calc-field facts of an anchor dataset over one Delphi index and decides on them.</summary>
  /// <remarks>Nothing passed in is owned; all must outlive the reader and any TCalcFacts it made. Not thread-safe.</remarks>
  TCalcFactsReader = class  // dl:ok high-response@b28b -- REVIEWED 2026-10-17: the reader IS the PS Get-CalcFieldFacts / Get-CalcHandler family; its response set is the index queries and the Part 1 resolver calls each fact needs, already split into per-fact private methods
  private
    FIndex   : TChartsIndex;
    FReader  : TSourceReader;
    FResolver: TTraceAnchorResolver;
    FCatalog : TSqlCatalog;
    FSet     : TSqlTableSet;
    function ReadHandler(const pW: TEventWiring): TCalcHandler;
    procedure ReadBindings(const pDs: TTraceDataSet; const pCol: string; pFacts: TCalcFacts);
    procedure ReadWirings(const pDs: TTraceDataSet; pFacts: TCalcFacts);
    procedure ReadCreating(const pDs: TTraceDataSet; const pCol: string; pFacts: TCalcFacts);
  public
    /// <summary>Constructor.</summary>
    /// <param name="pIndex">The Delphi (CLIENT) index.</param>
    /// <param name="pReader">A source reader over pIndex (its overrides apply).</param>
    /// <param name="pResolver">The anchor resolver (event wirings, write rows, table datasets).</param>
    /// <param name="pCatalog">The SQL catalogue (column states).</param>
    /// <param name="pSet">The SQL table set.</param>
    constructor Create(pIndex: TChartsIndex; pReader: TSourceReader; pResolver: TTraceAnchorResolver; pCatalog: TSqlCatalog;
      pSet: TSqlTableSet);
    /// <summary>The facts ResolveCalcField decides on.</summary>
    /// <param name="pDs">The anchor dataset field.</param>
    /// <param name="pCol">The field as the selection names it.</param>
    /// <param name="pTable">The anchor table.</param>
    /// <returns>The facts; the caller frees them.</returns>
    /// <remarks>Port of Get-CalcFieldFacts / Get-CalcHandler (Trace.Walk.ps1:2418-2496). A handler file that differs from the indexed
    /// copy is REFUSED by name: the handler read raises EChartsTrace with the PS text (AC-14), and so does Info / Apply.</remarks>
    function Facts(const pDs: TTraceDataSet; const pCol, pTable: string): TCalcFacts;
    /// <summary>Is the field calculated (or an event / lookup field)?</summary>
    /// <param name="pDs">The anchor dataset field.</param>
    /// <param name="pCol">The field as the selection names it.</param>
    /// <param name="pTable">The anchor table.</param>
    /// <returns>nil when not calculated; else the decision, which the caller owns.</returns>
    /// <remarks>Port of Get-CalcFieldInfo (Trace.Walk.ps1:2494).</remarks>
    function Info(const pDs: TTraceDataSet; const pCol, pTable: string): TCalcInfo;
    /// <summary>When the anchor stopped at a column the SQL index does not hold and the field is calculated, replace the stop.</summary>
    /// <param name="pResult">The anchor; Calc becomes the TCalcInfo, Stop its StopText and StopAnchor its Anchor.</param>
    /// <param name="pCol">The field as the selection names it.</param>
    /// <remarks>Port of Trace.Walk.ps1:106-108. Does nothing for an anchor without a dataset, without a column, without a stop,
    /// or with a reached column.</remarks>
    procedure Apply(pResult: TAnchorResult; const pCol: string);
  end;

/// <summary>The decision, PURE over the facts.</summary>
/// <param name="pFacts">The facts (index-read or synthetic); not owned.</param>
/// <returns>nil (not calculated: the caller keeps its stop) or the decision, which the caller owns. A calculated one carries the
/// handler, conditions, sources and head call.</returns>
/// <remarks>Port of Resolve-CalcField / New-CalcInfo and the helpers they call (Trace.Walk.ps1:2075-2341).</remarks>
function ResolveCalcField(pFacts: TCalcFacts): TCalcInfo;

/// <summary>The Form A items of a calculated anchor: the STOPS and the DERIVED rows.</summary>
/// <param name="pInfo">A decision of Kind calculated.</param>
/// <param name="pCmdFor">Target -> the command that traces it instead.</param>
/// <returns>The stop, the DERIVED lead-in note and the rows; the caller owns Stop and Rows.</returns>
/// <remarks>Port of New-CalcFieldItems (Trace.Walk.ps1:2497-2530). Pure. A binding reason every row shares is stated ONCE, in the note.</remarks>
function NewCalcFieldItems(pInfo: TCalcInfo; const pCmdFor: TFunc<string, string>): TCalcFieldItems;

implementation

uses
  System.Generics.Defaults
  , System.RegularExpressions
  , DRagLint.Charts.Columns
  , DRagLint.Charts.Trace.Shim
  ;

const
  ON_CALC_FIELDS = 'OnCalcFields';
  KIND_STEP = 'step';
  KIND_STOPS = 'stops';
  KIND_WRITE = 'write';
  KIND_READ = 'read';
  KIND_CALL = 'call';
  KIND_MEMBER = 'member-access';
  KIND_LOCAL = 'local';
  KIND_VAR = 'var';
  KIND_FBN = 'fbn';
  KIND_UNMAPPED = 'unmapped';
  LOCAL_VAR = 'local_var';
  LOCAL_PARAM = 'param';
  NAME_FIELDBYNAME = 'FieldByName';
  FORM_UNKNOWN = 'unknown';
  GRADE_BY_NAME = 'by name';
  GRADE_INFERRED = 'inferred';
  ASK_IN_CLASS = 'in-class-field-reads';
  ASK_E3 = 'E3';
  RE_FBN_READ = '^FieldByName\s*\(\s*''((?:[^'']|'''')*)''\s*\)';
  RE_FBN_TAIL = '\s*\.\s*[A-Za-z_]\w*\s*:=';
  RE_AHEAD_ASSIGN = '^\s*:=';
  RE_AHEAD_PAREN = '^\s*\(';
  RE_TFIELD = '^T\w*Field$';
  RE_TYPE_SHAPE = '^[TE][A-Z]\w*$';
  RE_REASON_LINE = '^the (\w+) at :(\d+) (.+)$';
  RE_EVENT_NAME = '^(On|After|Before)[A-Z]';
  RE_CASE_ARM = 'sits in a case arm';
  RE_NO_BRANCH = 'is not inside a branch';
  RE_PAREN_LABEL = ' \(';
  MAX_CHAIN = 16;
  POS_SCALE = 100000;
  ASSIGN_LEN = 2;
  FIELDKIND_LIMIT = 5;
  GRP_LINE = 2;
  GRP_REST = 3;
  SELECTOR_AT = ' at ';

type
  TCalcWrite = record
    Line: Integer;
    Col : Integer;
    Span: TStatementSpan;
  end;

  TCalcRead = record
    Kind    : string;
    Name    : string;
    VarName : string;
    Recv    : string;
    Literal : string;
    Why     : string;
    IsParam : Boolean;
    IsField : Boolean;
    SetLine : Integer;
  end;

  TCalcCaseSite = record
    L    : Integer;
    C    : Integer;
    E    : Integer;
    OfL  : Integer;
    OfC  : Integer;
    Lines: TArray<Integer>;
  end;

  TCalcAround = record
    Key  : string;
    E    : TShimResult;
    Lines: TArray<Integer>;
  end;

  TCalcConditions = record
    Conds  : TArray<TCalcCond>;
    Unknown: TArray<string>;
    Cases  : TArray<TCalcCaseSite>;
    Ifs    : TArray<TShimResult>;
  end;

  TCalcChooser = record
    Line: Integer;
    Word: string;
    Span: TStatementSpan;
  end;

function FieldTypeRx: TRegEx;
begin
  Result:= TRegEx.Create(RE_TFIELD, [roIgnoreCase]);
end;

type
  TStable = class sealed
    class procedure Sort<T>(var pList: TArray<T>; const pCmp: TComparison<T>); static;
  end;

{ stable: ties keep their order (Sort-Object) }
class procedure TStable.Sort<T>(var pList: TArray<T>; const pCmp: TComparison<T>);
begin
  for var I:= 1 to High(pList) do
  begin
    var Cur:= pList[I];
    var J:= I - 1;
    while (J >= 0) and (pCmp(pList[J], Cur) > 0) do
    begin
      pList[J + 1]:= pList[J];
      Dec(J);
    end;
    pList[J + 1]:= Cur;
  end;
end;

function InSet(const pValue: string; const pSet: array of string): Boolean;
begin
  Result:= False;
  for var S in pSet do
    if SameText(S, pValue) then
      Exit(True);
end;

function HasText(const pList: TArray<string>; const pValue: string): Boolean;
begin
  Result:= False;
  for var S in pList do
    if SameText(S, pValue) then
      Exit(True);
end;

function HasInt(const pList: TArray<Integer>; pValue: Integer): Boolean;
begin
  Result:= False;
  for var N in pList do
    if N = pValue then
      Exit(True);
end;

function IntsSorted(const pList: TArray<Integer>): TArray<Integer>;
begin
  Result:= Copy(pList);
  TStable.Sort<Integer>(Result, function(const pA, pB: Integer): Integer begin Result:= pA - pB; end);
end;

{ ":a, :b" of the sorted lines }
function LineList(const pLines: TArray<Integer>): string;
begin
  var Parts: TArray<string>:= [];
  for var N in IntsSorted(pLines) do
    Parts:= Parts + [':' + IntToStr(N)];
  Result:= string.Join(', ', Parts);
end;

function IsTFieldType(const pSig: string): Boolean;
begin
  Result:= FieldTypeRx.IsMatch(pSig);
end;

{ the refs of one kind, by line then column (a stable sort, as Sort-Object by line, then col) }
function RefsOfKind(pH: TCalcHandler; const pKind: string): TArray<TCalcRef>;
begin
  Result:= nil;
  for var R in pH.Refs do
    if SameText(R.Kind, pKind) then
      Result:= Result + [R];
  TStable.Sort<TCalcRef>(Result, function(const pA, pB: TCalcRef): Integer
    begin
      Result:= pA.Line - pB.Line;
      if Result = 0 then
        Result:= pA.Col - pB.Col;
    end);
end;

function InAnyRhs(const pWrites: TArray<TCalcWrite>; const pR: TCalcRef): Boolean;
begin
  Result:= False;
  for var W in pWrites do
    if InStatementRhs(W.Span, pR.Line, pR.Col - 1) then
      Exit(True);
end;

{ The statements of the handler that WRITE the field: `<Var>.<Member> :=` for a TField variable in pVars, or
  `<X>.FieldByName('<Field>').<Member> :=`. Port of Find-CalcWrites (Trace.Walk.ps1:2075). }
function FindCalcWrites(pH: TCalcHandler; const pVars: TArray<string>; const pField: string): TArray<TCalcWrite>;
begin
  Result:= nil;
  var Seen:= THashSet<string>.Create;
  try
    for var R in RefsOfKind(pH, KIND_MEMBER) do
    begin
      var Ln:= R.Line;
      if (Ln < pH.ImplStart) or (Ln > pH.ImplEnd) or (Ln > Length(pH.Stripped)) then
        Continue;
      var S:= pH.Stripped[Ln - 1];
      var C0:= R.Col - 1;
      var E:= R.ECol - 1;
      var Hit:= False;
      if (Length(pVars) > 0) and HasText(pVars, R.Recv) then
        Hit:= (E <= Length(S)) and TRegEx.IsMatch(Copy(S, E + 1, MaxInt), RE_AHEAD_ASSIGN)
      else if SameText(R.Nm, NAME_FIELDBYNAME) and (pField <> '') and (C0 >= 0) and (C0 < Length(pH.Raw[Ln - 1])) then
      begin
        var M:= TRegEx.Match(Copy(pH.Raw[Ln - 1], C0 + 1, MaxInt), RE_FBN_READ + RE_FBN_TAIL);
        Hit:= M.Success and SameText(M.Groups[1].Value.Replace('''''', ''''), pField) and (C0 + M.Length <= Length(S)) and
          (Copy(S, C0 + M.Length - ASSIGN_LEN + 1, ASSIGN_LEN) = ':=');
      end;
      if not Hit then
        Continue;
      var St:= ReceiverStart(S, C0);
      if St < 0 then
        Continue;
      if not Seen.Add(IntToStr(Ln) + '|' + IntToStr(St)) then
        Continue;
      var W: TCalcWrite;
      W.Line:= Ln;
      W.Col:= St;
      W.Span:= StatementSpan(pH.Stripped, Ln, St, pH.ImplEnd);
      Result:= Result + [W];
    end;
  finally
    Seen.Free;
  end;
end;

const
  OPENERS: array[0..4] of string = ('begin', 'try', 'case', 'record', 'repeat');
  CLOSERS: array[0..1] of string = ('end', 'until');

{ The `case` token that opens the case whose arm holds the statement at (pLine, 0-based pCol): back over balanced blocks to the
  first unclosed opener; False when that opener is not a case. Port of Find-EnclosingCase (Trace.Walk.ps1:2166). }
function FindEnclosingCase(const pTok: TArray<TShimToken>; pLine, pCol: Integer; out pCase: TShimToken): Boolean;
begin
  Result:= False;
  pCase:= Default(TShimToken);
  var D:= 0;
  for var Q:= High(pTok) downto 0 do
  begin
    var K:= pTok[Q];
    if (K.L > pLine) or ((K.L = pLine) and (K.E > pCol)) then
      Continue;
    if InSet(K.T, CLOSERS) then
    begin
      Inc(D);
      Continue;
    end;
    if InSet(K.T, OPENERS) then
    begin
      if D > 0 then
      begin
        Dec(D);
        Continue;
      end;
      { the `begin` of a begin-wrapped ARM is the arm's own block -- step past it to the case that owns the arm }
      if SameText(K.T, 'begin') and (Q > 0) and (SameText(pTok[Q - 1].T, ':') or SameText(pTok[Q - 1].T, 'else')) then
        Continue;
      if SameText(K.T, 'case') then
      begin
        pCase:= K;
        Result:= True;
      end;
      Exit;
    end;
  end;
end;

{ Unknown reasons that differ only in their line (`the statement at :N <rest>`) merged into one. Port of Join-CalcReasons. }
function JoinCalcReasons(const pReasons: TArray<string>): TArray<string>;
begin
  var Keys: TArray<string>:= [];
  var Lines: TArray<TArray<string>>:= [];
  var Other: TArray<string>:= [];
  for var R in pReasons do
  begin
    var M:= TRegEx.Match(R, RE_REASON_LINE, [roIgnoreCase]);
    if M.Success then
    begin
      var Key:= M.Groups[1].Value + '|' + M.Groups[GRP_REST].Value;
      var At:= -1;
      for var K:= 0 to High(Keys) do
        if SameText(Keys[K], Key) then
          At:= K;
      if At < 0 then
      begin
        Keys:= Keys + [Key];
        Lines:= Lines + [TArray<string>.Create()];
        At:= High(Keys);
      end;
      Lines[At]:= Lines[At] + [M.Groups[GRP_LINE].Value];
    end
    else if not HasText(Other, R) then
      Other:= Other + [R];
  end;
  Result:= nil;
  for var K:= 0 to High(Keys) do
  begin
    var P:= Keys[K].IndexOf('|');
    var W:= Keys[K].Substring(0, P);
    var Rest:= Keys[K].Substring(P + 1);
    var Ls: TArray<string>:= [];
    for var L in Lines[K] do
      if not TArray.Contains<string>(Ls, L) then
        Ls:= Ls + [L];
    if Length(Ls) > 1 then
    begin
      var Parts: TArray<string>:= [];
      for var L in Ls do
        Parts:= Parts + [':' + L];
      Result:= Result + ['the ' + W + 's at ' + string.Join(', ', Parts) + ' ' + TRegEx.Replace(Rest, '^sits ', 'sit ', [roIgnoreCase])];
    end
    else
      Result:= Result + ['the ' + W + ' at :' + Ls[0] + ' ' + Rest];
  end;
  Result:= Result + Other;
end;

{ The guards of the computation, VERBATIM (P16): every Exit of the handler before its first write, then each write's chain of
  enclosing ifs, read past a case. A shape the shim cannot read goes to Unknown. Port of Get-CalcConditions (Trace.Walk.ps1:2104). }
function CalcConditions(pH: TCalcHandler; const pWrites: TArray<TCalcWrite>): TCalcConditions;
var
  Conds: TList<TCalcCond>;
  Unk: TList<string>;
  Seen: THashSet<string>;
  Cases: TList<TCalcCaseSite>;
  Around: TList<TCalcAround>;
  Tok: TArray<TShimToken>;

  procedure AddCond(const pKw, pCond: string; pLine: Integer; const pNote: string);
  begin
    if Seen.Add(pKw + '|' + pCond + '|' + IntToStr(pLine)) then
    begin
      var C: TCalcCond;
      C.Keyword:= pKw;
      C.Condition:= pCond;
      C.Line:= pLine;
      C.Note:= pNote;
      Conds.Add(C);
    end;
  end;

  procedure AddCase(const pCt: TShimToken; pWl: Integer);
  begin
    var K:= -1;
    for var I:= 0 to Cases.Count - 1 do
      if (Cases[I].L = pCt.L) and (Cases[I].C = pCt.C) then
        K:= I;
    if K < 0 then
    begin
      var Site:= Default(TCalcCaseSite);
      Site.L:= pCt.L;
      Site.C:= pCt.C;
      Site.E:= pCt.E;
      for var Q in Tok do
        if ((Q.L > pCt.L) or ((Q.L = pCt.L) and (Q.C > pCt.C))) and SameText(Q.T, 'of') then
        begin
          Site.OfL:= Q.L;
          Site.OfC:= Q.C;
          Break;
        end;
      K:= Cases.Add(Site);
    end;
    var S:= Cases[K];
    if not HasInt(S.Lines, pWl) then
    begin
      S.Lines:= S.Lines + [pWl];
      Cases[K]:= S;
    end;
  end;

  procedure AddAround(const pE: TShimResult; pWl: Integer);
  begin
    var Key:= pE.Keyword + '|' + pE.Condition + '|' + IntToStr(pE.IfLine);
    var K:= -1;
    for var I:= 0 to Around.Count - 1 do
      if SameText(Around[I].Key, Key) then
        K:= I;
    if K < 0 then
    begin
      var A:= Default(TCalcAround);
      A.Key:= Key;
      A.E:= pE;
      K:= Around.Add(A);
    end;
    var Ar:= Around[K];
    if not HasInt(Ar.Lines, pWl) then
    begin
      Ar.Lines:= Ar.Lines + [pWl];
      Around[K]:= Ar;
    end;
  end;

  { one write's chain of enclosing statements, read OUTWARDS past a case }
  procedure ChainOf(const pW: TCalcWrite);
  begin
    var L:= pW.Line;
    var C:= pW.Col;
    for var I:= 0 to MAX_CHAIN - 1 do
    begin
      var E:= EnclosingConditionFromLines(pH.Raw, pH.Stripped, L, C, pH.ImplStart, Tok);
      if SameText(E.Form, FORM_UNKNOWN) then
      begin
        var Ct: TShimToken;
        if TRegEx.IsMatch(E.Reason, RE_CASE_ARM, [roIgnoreCase]) and FindEnclosingCase(Tok, L, C, Ct) then
        begin
          AddCase(Ct, pW.Line);
          L:= Ct.L;
          C:= Ct.C;
          Continue;
        end;
        if not TRegEx.IsMatch(E.Reason, RE_NO_BRANCH, [roIgnoreCase]) then
          Unk.Add(E.Reason);
        Break;
      end;
      if SameText(E.Form, 'case') then
      begin
        for var Q in Tok do
          if (Q.L = E.StmtLine) and (Q.C = E.StmtCol) and SameText(Q.T, 'case') then
          begin
            AddCase(Q, pW.Line);
            Break;
          end;
      end
      else if SameText(E.Form, 'inline') or SameText(E.Form, 'block') then
        AddAround(E, pW.Line);
      if (E.StmtLine = 0) or ((E.StmtLine = L) and (E.StmtCol >= C)) then
        Break;
      L:= E.StmtLine;
      C:= E.StmtCol;
    end;
  end;

begin
  Result:= Default(TCalcConditions);
  Conds:= TList<TCalcCond>.Create;
  Unk:= TList<string>.Create;
  Seen:= THashSet<string>.Create(TIStringComparer.Ordinal);
  Cases:= TList<TCalcCaseSite>.Create;
  Around:= TList<TCalcAround>.Create;
  try
    var First:= pWrites[0];
    var WLines: TArray<Integer>:= [];
    for var W in pWrites do
    begin
      if (W.Line < First.Line) or ((W.Line = First.Line) and (W.Col < First.Col)) then
        First:= W;
      if not HasInt(WLines, W.Line) then
        WLines:= WLines + [W.Line];
    end;
    var Exits: TArray<Integer>:= [];
    for var R in RefsOfKind(pH, KIND_CALL) do
      if SameText(R.Nm, 'Exit') and (R.Line >= pH.ImplStart) and (R.Line < First.Line) and not HasInt(Exits, R.Line) then
        Exits:= Exits + [R.Line];
    for var Xl in IntsSorted(Exits) do
    begin
      var G:= GuardConditionFromLines(pH.Raw, pH.Stripped, Xl, pH.ImplStart);
      if SameText(G.Form, FORM_UNKNOWN) then
        Unk.Add(G.Reason)
      else
        AddCond(G.Keyword, G.Condition, G.IfLine, 'else Exit at :' + IntToStr(Xl));
    end;
    Tok:= ShimTokens(pH.Stripped, pH.ImplStart, pH.ImplEnd);
    for var W in pWrites do
      ChainOf(W);
    for var A in Around do
    begin
      var Note:= '';
      if Length(A.Lines) < Length(WLines) then
        Note:= 'around the write' + (if Length(A.Lines) > 1 then 's' else '') + ' at ' + LineList(A.Lines);
      AddCond(A.E.Keyword, A.E.Condition, A.E.IfLine, Note);
    end;
    { every enclosing if-form: the reads in its condition CHOOSE the value exactly as a case selector does }
    var Ifs: TArray<TShimResult>:= [];
    var IfKeys: TArray<string>:= [];
    for var A in Around do
    begin
      var Key:= IntToStr(A.E.IfLine) + ':' + IntToStr(A.E.CondC1);
      if not HasText(IfKeys, Key) then
      begin
        IfKeys:= IfKeys + [Key];
        Ifs:= Ifs + [A.E];
      end;
    end;
    TStable.Sort<TShimResult>(Ifs, function(const pA, pB: TShimResult): Integer
      begin
        Result:= pA.IfLine - pB.IfLine;
        if Result = 0 then
          Result:= pA.CondC1 - pB.CondC1;
      end);
    Result.Conds:= Conds.ToArray;
    Result.Unknown:= Unk.ToArray;
    Result.Cases:= Cases.ToArray;
    TStable.Sort<TCalcCaseSite>(Result.Cases, function(const pA, pB: TCalcCaseSite): Integer
      begin
        Result:= pA.L - pB.L;
        if Result = 0 then
          Result:= pA.C - pB.C;
      end);
    Result.Ifs:= Ifs;
  finally
    Around.Free;
    Cases.Free;
    Seen.Free;
    Unk.Free;
    Conds.Free;
  end;
end;

{ What one read on a computation's right-hand side is. False: a constant (a bound enum value, type or routine, or by NAME SHAPE an
  unbound type or typecast head). Locals shadow class fields, as in Pascal. Port of Resolve-CalcRead (Trace.Walk.ps1:2201). }
function ResolveCalcRead(pF: TCalcFacts; pH: TCalcHandler; const pR: TCalcRef; out pX: TCalcRead): Boolean;  // dl:ok too-many-exit-points@afc5 -- REVIEWED 2026-10-17: one early return per shape Resolve-CalcRead names (Self, FieldByName read, parameter, local, class field, bound constant, type shape); each exit carries its own documented result, so folding them would hide the shapes

  function Unmapped(const pName, pWhy: string; pIsField: Boolean): TCalcRead;
  begin
    Result:= Default(TCalcRead);
    Result.Kind:= KIND_UNMAPPED;
    Result.Name:= pName;
    Result.Why:= pWhy;
    Result.IsField:= pIsField;
  end;

begin
  pX:= Default(TCalcRead);
  Result:= True;
  var Nm:= pR.Nm;
  var Ln:= pR.Line;
  if SameText(Nm, 'Self') then
    Exit(False);
  var Fb: TCalcRef;
  var HasFb:= False;
  for var M in RefsOfKind(pH, KIND_MEMBER) do
    if SameText(M.Nm, NAME_FIELDBYNAME) and SameText(M.Recv, Nm) and (M.Line = Ln) and (M.Col > pR.Col) then
    begin
      Fb:= M;
      HasFb:= True;
      Break;
    end;
  var LocalKind: string;
  var IsLocal:= pH.Locals.TryGetValue(Nm, LocalKind);
  if HasFb and ((IsLocal and SameText(LocalKind, LOCAL_PARAM)) or SameText(Nm, pF.DsName)) then
  begin
    var C0:= Fb.Col - 1;
    var Raw:= pH.Raw[Ln - 1];
    var M:= TRegEx.Match(Copy(Raw, C0 + 1, MaxInt), RE_FBN_READ);
    if (C0 >= Length(Raw)) or not M.Success then
    begin
      pX:= Unmapped(Nm + '.' + NAME_FIELDBYNAME, 'its argument is not a string literal', True);
      Exit;
    end;
    pX.Kind:= KIND_FBN;
    pX.Name:= Nm + '.' + NAME_FIELDBYNAME;
    pX.Recv:= Nm;
    pX.Literal:= M.Groups[1].Value.Replace('''''', '''');
    pX.IsParam:= not SameText(Nm, pF.DsName);
    pX.IsField:= True;
    Exit;
  end;
  if IsLocal then
  begin
    if not SameText(LocalKind, LOCAL_VAR) then
    begin
      pX:= Unmapped(Nm, 'a parameter of ' + pH.Name, False);
      Exit;
    end;
    var Pos_:= Ln * POS_SCALE + pR.Col;
    var Ws: TArray<TCalcRef>:= [];
    for var W in RefsOfKind(pH, KIND_WRITE) do
      if SameText(W.Nm, Nm) and (W.Line * POS_SCALE + W.Col < Pos_) then
        Ws:= Ws + [W];
    if Length(Ws) <> 1 then
    begin
      pX:= Unmapped(Nm, Format('a local of %s set at %d places before this read', [pH.Name, Length(Ws)]), False);
      Exit;
    end;
    var Sp:= StatementSpan(pH.Stripped, Ws[0].Line, Ws[0].Col - 1, pH.ImplEnd);
    var Vs: TArray<string>:= [];
    for var Rd in RefsOfKind(pH, KIND_READ) do
    begin
      var Sig: string;
      if InStatementRhs(Sp, Rd.Line, Rd.Col - 1) and not pH.Locals.ContainsKey(Rd.Nm) and pF.ClassFields.TryGetValue(Rd.Nm, Sig) and
        IsTFieldType(Sig) then
        Vs:= Vs + [Rd.Nm];
    end;
    Vs:= SortUniqueNames(Vs);
    if Length(Vs) <> 1 then
    begin
      pX:= Unmapped(Nm, Format('a local of %s set at :%d from %d TField variables', [pH.Name, Ws[0].Line, Length(Vs)]), False);
      Exit;
    end;
    pX.Kind:= KIND_LOCAL;
    pX.Name:= Nm;
    pX.VarName:= Vs[0];
    pX.SetLine:= Ws[0].Line;
    Exit;
  end;
  var FieldSig: string;
  if pF.ClassFields.TryGetValue(Nm, FieldSig) then
  begin
    if IsTFieldType(FieldSig) then
    begin
      pX.Kind:= KIND_VAR;
      pX.Name:= Nm;
      pX.VarName:= Nm;
    end
    else
      pX:= Unmapped(Nm, Format('a field of %s of type %s, not a TField variable', [pF.OwnerClass, FieldSig]), False);
    Exit;
  end;
  if pR.Tid <> 0 then
  begin
    if InSet(pR.TKind, CALC_CONST_KINDS) then
      Exit(False);
    pX:= Unmapped(Nm, Format('a %s outside %s, not a TField variable', [pR.TKind, pF.OwnerClass]), False);
    Exit;
  end;
  { only a TYPE is a constant by name -- the Delphi type shape, or a typecast head of a built-in type; a receiver is NOT one }
  var S:= pH.Stripped[Ln - 1];
  var E:= pR.ECol - 1;
  if TRegEx.IsMatch(Nm, RE_TYPE_SHAPE) then
    Exit(False);
  if InSet(Nm, CALC_BUILTIN_TYPES) and (E <= Length(S)) and TRegEx.IsMatch(Copy(S, E + 1, MaxInt), RE_AHEAD_PAREN) then
    Exit(False);
  pX:= Unmapped(Nm, 'not a field, local or parameter the walk can place', False);
end;

{ The label of a source column: `<TABLE>.<COL>`, `<lit> (calculated)` (marked, not expanded), `<lit> (not a column of <TABLE>)`, or
  `<lit> of <DataSet>` for another dataset's field. Port of Get-CalcColumnLabel (Trace.Walk.ps1:2316). }
function CalcColumnLabel(pF: TCalcFacts; pH: TCalcHandler; const pVars: TArray<string>; const pLit, pDataSet: string): string;
begin
  if not SameText(pDataSet, pF.DsName) then
    Exit(pLit + ' of ' + pDataSet);
  if Length(FindCalcWrites(pH, pVars, pLit)) > 0 then
    Exit(pLit + ' (calculated)');
  if pF.IsColumn(pLit) then
    Exit(pF.Table + '.' + UpperCase(pLit));
  Result:= pLit + ' (not a column of ' + pF.Table + ')';
end;

{ `<ds>.FieldByName('<lit>')` read on the right-hand side -- the canonical OnCalcFields idiom. Port of New-CalcFieldByNameRow. }
function CalcFieldByNameRow(pF: TCalcFacts; pH: TCalcHandler; const pR: TCalcRef; const pX: TCalcRead; const pSelText: string): TCalcSource;
begin
  Result:= Default(TCalcSource);
  Result.IsField:= True;
  Result.Line:= pR.Line;
  Result.Name:= pX.Name;
  var Bv: TArray<TCalcBinding>:= [];
  for var B in pF.Bindings.Values do
    if (B.Why = '') and SameText(B.DataSet, pF.DsName) and SameText(B.Literal, pX.Literal) then
      Bv:= Bv + [B];
  TStable.Sort<TCalcBinding>(Bv, function(const pA, pB: TCalcBinding): Integer begin Result:= CompareText(pA.VarName, pB.VarName); end);
  var Vars: TArray<string>:= [];
  for var B in Bv do
    Vars:= Vars + [B.VarName];
  var Label_:= CalcColumnLabel(pF, pH, Vars, pX.Literal, pF.DsName);
  Result.Text:= TraceStopText('FROM ' + Label_ + ' VIA ' + pX.Recv + '.' + NAME_FIELDBYNAME + pSelText);
  var Who:= if pX.IsParam then Format('%s is a parameter of %s, taken as %s', [pX.Recv, pH.Name, pF.DsName]) else 'on ' + pF.DsName;
  var How: string;
  if Length(Bv) > 0 then
  begin
    Result.Target:= Bv[0].Qname;
    How:= Format('traced through %s, bound at %s %s', [Bv[0].VarName, TraceNoteLocator(pH.Path, Bv[0].Path, Bv[0].Line), Bv[0].Via]);
  end
  else if not TRegEx.IsMatch(Label_, RE_PAREN_LABEL) and (pF.TableDataSets = 1) then
  begin
    Result.Target:= pF.Table + '.' + UpperCase(pX.Literal);
    How:= Format('traced as %s, the one dataset that loads %s', [Result.Target, pF.Table]);
  end
  else
    How:= Format('no -Target resolves to %s: %d datasets load %s and no TField variable is bound to ''%s''',
      [pF.DsName, pF.TableDataSets, pF.Table, pX.Literal]);
  Result.Note:= TraceNoteText(Who + ', ' + How);
  Result.Grade:= if pX.IsParam then GRADE_INFERRED else if pR.Tid = 0 then GRADE_BY_NAME else '';
  Result.Ask:= if (not pX.IsParam) and (pR.Tid = 0) then ASK_IN_CLASS else '';
end;

{ One offered source as row data. Port of New-CalcSourceRow (Trace.Walk.ps1:2342). }
function CalcSourceRow(pF: TCalcFacts; pH: TCalcHandler; const pR: TCalcRef; const pX: TCalcRead; const pSel: string): TCalcSource;
begin
  Result:= Default(TCalcSource);
  Result.IsField:= True;
  Result.Line:= pR.Line;
  Result.Selector:= pSel;
  Result.Name:= pX.Name;
  var SelText:= if pSel <> '' then ', chooses the value (' + pSel + ')' else '';
  if SameText(pX.Kind, KIND_UNMAPPED) then
  begin
    Result.IsField:= pX.IsField;
    Result.Text:= TraceStopText('FROM ' + pX.Name + ', not mapped: ' + pX.Why + SelText);
    Exit;
  end;
  if SameText(pX.Kind, KIND_FBN) then
    Exit(CalcFieldByNameRow(pF, pH, pR, pX, SelText));
  var B: TCalcBinding;
  if (not pF.Bindings.TryGetValue(pX.VarName, B)) or (B.Why <> '') then
  begin
    var Why:= if pF.Bindings.ContainsKey(pX.VarName) then B.Why else 'no binding line of it is in the index';
    Result.Text:= TraceStopText('FROM ' + pX.Name + ', not mapped: ' + pX.VarName + ' ' + Why + SelText);
    Exit;
  end;
  Result.Target:= B.Qname;
  var Label_:= CalcColumnLabel(pF, pH, [pX.VarName], B.Literal, B.DataSet);
  var IsLocal:= SameText(pX.Kind, KIND_LOCAL);
  var Via:= if IsLocal then pX.Name + ', set from ' + pX.VarName else pX.VarName;
  Result.Text:= TraceStopText('FROM ' + Label_ + ' VIA ' + Via + SelText);
  var Pre:= if IsLocal then Format('%s set at :%d, ', [pX.Name, pX.SetLine]) else '';
  var Calc:= if Label_.EndsWith(' (calculated)', True) then 'itself calculated in ' + pH.Name + ', not expanded, ' else '';
  Result.Note:= TraceNoteText(Format('%s%s%s bound at %s %s', [Calc, Pre, pX.VarName, TraceNoteLocator(pH.Path, B.Path, B.Line), B.Via]));
  Result.Reason:= TraceNoteText(B.Reason);
  { the read of an in-class field is unbound in this index: matched by name among the class's fields }
  var Unbound:= pR.Tid = 0;
  Result.Grade:= if B.Grade <> '' then B.Grade else if Unbound then GRADE_BY_NAME else '';
  Result.Ask:= if B.Ask <> '' then B.Ask else if Unbound then ASK_IN_CLASS else '';
end;

{ The call that computes the value: the first token of a right-hand side, when it is a call; the others named. }
function CalcHeadCall(pH: TCalcHandler; const pWrites: TArray<TCalcWrite>): TCalcHeadCall;
begin
  Result:= Default(TCalcHeadCall);
  var Calls: TArray<TCalcRef>:= [];
  for var R in RefsOfKind(pH, KIND_CALL) do
    if InAnyRhs(pWrites, R) then
      Calls:= Calls + [R];
  var Head: TCalcRef;
  var HasHead:= False;
  for var W in pWrites do
  begin
    var Sp:= W.Span;
    var Hc: TCalcRef;
    var Found:= False;
    for var C in Calls do
      if InStatementRhs(Sp, C.Line, C.Col - 1) then
      begin
        Hc:= C;
        Found:= True;
        Break;
      end;
    if not Found then
      Continue;
    { nothing but blanks between the := and the call }
    var Gap: string;
    var From:= Sp.AssignCol + ASSIGN_LEN;
    if Hc.Line = Sp.AssignLine then
      Gap:= Copy(pH.Stripped[Sp.AssignLine - 1], From + 1, Hc.Col - 1 - From)
    else
    begin
      var Pieces: TArray<string>:= [Copy(pH.Stripped[Sp.AssignLine - 1], From + 1, MaxInt)];
      for var L:= Sp.AssignLine + 1 to Hc.Line - 1 do
        Pieces:= Pieces + [pH.Stripped[L - 1]];
      Gap:= string.Join('', Pieces) + Copy(pH.Stripped[Hc.Line - 1], 1, Hc.Col - 1);
    end;
    if PsTrim(Gap) <> '' then
      Continue;
    Head:= Hc;
    HasHead:= True;
    Break;
  end;
  if not HasHead then
    Exit;
  var Others: TArray<string>:= [];
  for var C in Calls do
    if (not SameText(C.Nm, Head.Nm)) and not TArray.Contains<string>(Others, C.Nm) then
      Others:= Others + [C.Nm];
  Result.Present:= True;
  Result.Name:= Head.Nm;
  Result.Anchor:= if (Head.Tid <> 0) and (Head.TPath <> '') and (Head.TDecl > 0) then TraceAnchorText(Head.TPath, Head.TDecl)
    else TraceAnchorText(pH.Path, Head.Line);
  Result.Note:= Format('computed by this call at :%d, its body is not walked%s',
    [Head.Line, if Length(Others) > 0 then ', nor are those of ' + string.Join(', ', Others) else '']);
end;

{ A calculated decision. Port of New-CalcInfo (Trace.Walk.ps1:2268). }
function NewCalcInfo(pF: TCalcFacts; pWire: TCalcWiring; const pWrites: TArray<TCalcWrite>): TCalcInfo;
var
  Src: TList<TCalcSource>;
  Have: THashSet<string>;

  { one row per source -- a TField variable and a FieldByName read of the same column are one source, keyed by the column }
  procedure Take(const pR: TCalcRef; const pSel: string);
  begin
    if HasText(pF.Vars, pR.Nm) then
      Exit;
    var X: TCalcRead;
    if not ResolveCalcRead(pF, pWire.H, pR, X) then
      Exit;
    var B: TCalcBinding;
    var HasB:= SameText(X.Kind, KIND_VAR) or SameText(X.Kind, KIND_LOCAL);
    HasB:= HasB and pF.Bindings.TryGetValue(X.VarName, B);
    var Key: string;
    if SameText(X.Kind, KIND_UNMAPPED) then
      Key:= '?' + X.Name
    else if SameText(X.Kind, KIND_FBN) then
      Key:= '#' + UpperCase(X.Literal)
    else if HasB and (B.Why = '') and SameText(B.DataSet, pF.DsName) then
      Key:= '#' + UpperCase(B.Literal)
    else
      Key:= X.VarName;
    if Have.Add(Key) then
      Src.Add(CalcSourceRow(pF, pWire.H, pR, X, pSel));
  end;

begin
  var H:= pWire.H;
  var Cd:= CalcConditions(H, pWrites);
  Result:= TCalcInfo.Create;
  Src:= TList<TCalcSource>.Create;
  Have:= THashSet<string>.Create(TIStringComparer.Ordinal);
  try
    for var R in RefsOfKind(H, KIND_READ) do
      if InAnyRhs(pWrites, R) then
        Take(R, '');
    { the reads in every CHOOSER of the value -- a case selector or an enclosing if's condition -- in line order }
    var Choosers: TArray<TCalcChooser>:= [];
    for var Cs in Cd.Cases do
      if Cs.OfL <> 0 then
      begin
        var Ch: TCalcChooser;
        Ch.Line:= Cs.L;
        Ch.Word:= 'case';
        Ch.Span:= Default(TStatementSpan);
        Ch.Span.AssignLine:= Cs.L;
        Ch.Span.AssignCol:= Cs.E - ASSIGN_LEN;
        Ch.Span.L2:= Cs.OfL;
        Ch.Span.C2:= Cs.OfC;
        Choosers:= Choosers + [Ch];
      end;
    for var If_ in Cd.Ifs do
    begin
      var Ch: TCalcChooser;
      Ch.Line:= If_.IfLine;
      Ch.Word:= 'if';
      Ch.Span:= Default(TStatementSpan);
      Ch.Span.AssignLine:= If_.CondL1;
      Ch.Span.AssignCol:= If_.CondC1 - 1;
      Ch.Span.L2:= If_.CondL2;
      Ch.Span.C2:= If_.CondC2;
      Choosers:= Choosers + [Ch];
    end;
    TStable.Sort<TCalcChooser>(Choosers, function(const pA, pB: TCalcChooser): Integer
      begin
        Result:= pA.Line - pB.Line;
        if Result = 0 then
          Result:= CompareText(pA.Word, pB.Word);
      end);
    for var Ch in Choosers do
      for var R in RefsOfKind(H, KIND_READ) do
        if InStatementRhs(Ch.Span, R.Line, R.Col - 1) then
          Take(R, Ch.Word + ' at ' + TraceNoteLocator(H.Path, H.Path, Ch.Line));
    Result.Sources:= Src.ToArray;
  finally
    Have.Free;
    Src.Free;
  end;
  var First:= pWrites[0];
  for var W in pWrites do
    if (W.Line < First.Line) or ((W.Line = First.Line) and (W.Col < First.Col)) then
      First:= W;
  Result.HeadCall:= CalcHeadCall(H, pWrites);
  Result.Kind:= CALC_KIND_CALCULATED;
  Result.Field:= pF.Field;
  Result.DsName:= pF.DsName;
  Result.Table:= pF.Table;
  Result.HandlerName:= H.Name;
  Result.HandlerPath:= H.Path;
  Result.Anchor:= TraceAnchorText(H.Path, First.Line);
  Result.Conds:= Cd.Conds;
  Result.CondUnknown:= Cd.Unknown;
  { "created" only when the creating call's body sets FieldKind exactly once; otherwise the line only NAMES the field beside its dataset }
  var CLoc:= if pF.Creating.Present then TraceNoteLocator(H.Path, pF.Creating.Path, pF.Creating.Line) else '';
  var Created:= '';
  var KindNote:= '';
  if pF.Creating.Present then
  begin
    Created:= if pF.Creating.Kind <> '' then Format('created (FieldKind %s) at %s, ', [pF.Creating.Kind, CLoc])
      else Format('named at %s, ', [CLoc]);
    if pF.Creating.Kind <> '' then
      KindNote:= Format(', %s sets FieldKind %s at %s', [pF.Creating.Call, pF.Creating.Kind,
        TraceNoteLocator(H.Path, pF.Creating.KindPath, pF.Creating.KindLine)]);
  end;
  var UnkNote:= '';
  if Length(Cd.Unknown) > 0 then
  begin
    var Parts: TArray<string>:= [];
    for var Rs in JoinCalcReasons(Cd.Unknown) do
      Parts:= Parts + [TraceNoteText(Rs)];
    UnkNote:= ', not read as a guard: ' + string.Join(', ', Parts);
  end;
  { the cases that pick the formula are not guards -- say which writes each picks among }
  var CaseNote:= '';
  if Length(Cd.Cases) > 0 then
  begin
    var Parts: TArray<string>:= [];
    for var Cs in Cd.Cases do
      Parts:= Parts + [Format('the case at %s (writes at %s)', [TraceNoteLocator(H.Path, H.Path, Cs.L), LineList(Cs.Lines)])];
    CaseNote:= ', the formula is chosen by ' + string.Join(' and ', Parts) + ', ' +
      (if Length(Cd.Cases) > 1 then 'their selectors are' else 'its selector is') + ' offered below';
  end;
  Result.StopText := Format('%s is a calculated field of %s (%scomputed in %s at %s-%d), not a column of %s in the SQL index',
    [pF.Field, pF.DsName, Created, pWire.Handler, TraceNoteLocator(H.Path, H.Path, H.ImplStart), H.ImplEnd, pF.Table]);
  Result.StopNote := Format('wired as %s.%s at %s, the handler matched by name%s%s%s',
    [pF.DsName, ON_CALC_FIELDS, TraceNoteLocator(H.Path, pWire.WirePath, pWire.Line), KindNote, CaseNote, UnkNote]);
end;

function ResolveCalcField(pFacts: TCalcFacts): TCalcInfo;
begin
  Result:= nil;
  for var W in pFacts.Wirings do
    if SameText(W.Event, ON_CALC_FIELDS) then
    begin
      var Ws:= FindCalcWrites(W.H, pFacts.Vars, pFacts.Field);
      if Length(Ws) > 0 then
        Exit(NewCalcInfo(pFacts, W, Ws));
    end;
  for var W in pFacts.Wirings do
    if not SameText(W.Event, ON_CALC_FIELDS) then
    begin
      var Ws:= FindCalcWrites(W.H, pFacts.Vars, pFacts.Field);
      if Length(Ws) = 0 then
        Continue;
      Result:= TCalcInfo.Create;
      Result.Kind:= CALC_KIND_EVENT;
      Result.Field:= pFacts.Field;
      Result.DsName:= pFacts.DsName;
      Result.Table:= pFacts.Table;
      Result.Anchor:= TraceAnchorText(W.H.Path, Ws[0].Line);
      Result.StopText:= Format('%s is not a column of %s in the SQL index: it is set in %s, wired as %s.%s at %s, not in an OnCalcFields ' +
        'handler, so no source fields are offered', [pFacts.Field, pFacts.Table, W.Handler, pFacts.DsName, W.Event,
        TraceNoteLocator(W.H.Path, W.WirePath, W.Line)]);
      Exit;
    end;
  if pFacts.Creating.Present and SameText(pFacts.Creating.Kind, 'fkLookup') then
  begin
    var C:= pFacts.Creating;
    Result:= TCalcInfo.Create;
    Result.Kind:= CALC_KIND_LOOKUP;
    Result.Field:= pFacts.Field;
    Result.DsName:= pFacts.DsName;
    Result.Table:= pFacts.Table;
    Result.Anchor:= TraceAnchorText(C.Path, C.Line);
    Result.StopText:= Format('%s is a lookup field of %s: %s sets FieldKind fkLookup at %s, not a column of %s in the SQL index, so no ' +
      'source fields are offered', [pFacts.Field, pFacts.DsName, C.Call, TraceNoteLocator(C.Path, C.KindPath, C.KindLine), pFacts.Table]);
  end;
end;

function NewCalcFieldItems(pInfo: TCalcInfo; const pCmdFor: TFunc<string, string>): TCalcFieldItems;
begin
  Result.Stop:= NewTraceStep(KIND_STOPS, TraceStopText(pInfo.StopText), pInfo.Anchor, '', pInfo.HandlerName, TraceNoteText(pInfo.StopNote),
    ASK_E3);
  for var C in pInfo.Conds do
    Result.Stop.Children.Add(NewTraceCond(C.Keyword, C.Condition, TraceAnchorText(pInfo.HandlerPath, C.Line), C.Note));
  if pInfo.HeadCall.Present then
    Result.Stop.Children.Add(NewTraceFacet('VIA', pInfo.HeadCall.Name, pInfo.HeadCall.Anchor, pInfo.HeadCall.Note));
  { a binding reason every row shares is stated ONCE, in the note; a row keeps `bound at :N via FF` }
  var Rs: TArray<string>:= [];
  for var S in pInfo.Sources do
    if (S.Reason <> '') and not TArray.Contains<string>(Rs, S.Reason) then
      Rs:= Rs + [S.Reason];
  var Shared:= if Length(Rs) = 1 then Rs[0] else '';
  Result.Rows:= TObjectList<TTraceItem>.Create;
  var N:= 0;
  var SelN:= 0;
  var U:= 0;
  var Cmd:= 0;
  var Nb:= 0;
  var ChWords: TArray<string>:= [];
  var ChAts: TArray<TArray<string>>:= [];
  for var S in pInfo.Sources do
  begin
    var Nt:= if (S.Reason <> '') and (Shared = '') then S.Note + ': ' + S.Reason else S.Note;
    var St:= NewTraceStep(KIND_STEP, S.Text, TraceAnchorText(pInfo.HandlerPath, S.Line), S.Grade, pInfo.HandlerName, Nt, S.Ask);
    if S.Target <> '' then
      St.Children.Add(NewTraceFacet('REGENERATE', pCmdFor(S.Target)));
    Result.Rows.Add(St);
    if S.Selector <> '' then
    begin
      Inc(SelN);
      var P:= S.Selector.IndexOf(SELECTOR_AT);
      var W:= S.Selector.Substring(0, P);
      var At:= S.Selector.Substring(P + Length(SELECTOR_AT));
      var K:= -1;
      for var I:= 0 to High(ChWords) do
        if SameText(ChWords[I], W) then
          K:= I;
      if K < 0 then
      begin
        ChWords:= ChWords + [W];
        ChAts:= ChAts + [TArray<string>.Create()];
        K:= High(ChWords);
      end;
      if not TArray.Contains<string>(ChAts[K], At) then
        ChAts[K]:= ChAts[K] + [At];
    end
    else if S.IsField then
      Inc(N)
    else
      Inc(U);
    if S.Target <> '' then
      Inc(Cmd);
    if S.Reason <> '' then
      Inc(Nb);
  end;
  { the choosers -- case selectors AND enclosing if conditions -- by word, in line order: `if at :1106, :1110, case at :1043` }
  var LocParts: TArray<string>:= [];
  for var I:= 0 to High(ChWords) do
    LocParts:= LocParts + [ChWords[I] + ' at ' + string.Join(', ', ChAts[I])];
  var Loc:= string.Join(', ', LocParts);
  var Lead:= pInfo.Field + ' is calculated from ' + (if N > 0 then IntToStr(N) + ' field' + (if N <> 1 then 's' else '') else 'no field');
  if SelN > 0 then
    Lead:= Lead + (if N > 0 then Format(', and the value is chosen by %d more (%s)', [SelN, Loc])
      else Format(', but its value is chosen by %d (%s)', [SelN, Loc]));
  if U > 0 then
    Lead:= Lead + Format(', and %d other value%s the walk cannot map', [U, if U <> 1 then 's' else '']);
  var Tail:= if Cmd = 0 then ' -- nothing to trace instead' else if Cmd = 1 then ' -- trace it instead' else ' -- trace one of them instead';
  if Cmd = 0 then
    Result.Note:= Lead + Tail
  else
    Result.Note:= Lead + Tail + (if Shared <> '' then Format(' (%s below: %s)', [if Nb = 1 then 'the binding' else 'every binding', Shared])
      else '') + ':';
end;

{ ---- TCalcHandler / TCalcWiring / TCalcFacts ---- }

constructor TCalcHandler.Create;
begin
  inherited Create;
  Locals:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
end;

destructor TCalcHandler.Destroy;
begin
  Locals.Free;
  inherited Destroy;
end;

destructor TCalcWiring.Destroy;
begin
  H.Free;
  inherited Destroy;
end;

constructor TCalcFacts.Create;
begin
  inherited Create;
  Bindings:= TDictionary<string, TCalcBinding>.Create(TIStringComparer.Ordinal);
  ClassFields:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  Wirings:= TObjectList<TCalcWiring>.Create;
end;

destructor TCalcFacts.Destroy;
begin
  Wirings.Free;
  ClassFields.Free;
  Bindings.Free;
  inherited Destroy;
end;

{ ---- TCalcFactsReader ---- }

constructor TCalcFactsReader.Create(pIndex: TChartsIndex; pReader: TSourceReader; pResolver: TTraceAnchorResolver; pCatalog: TSqlCatalog;
  pSet: TSqlTableSet);
begin
  inherited Create;
  FIndex:= pIndex;
  FReader:= pReader;
  FResolver:= pResolver;
  FCatalog:= pCatalog;
  FSet:= pSet;
end;

{ One handler's facts: its refs (nested routines' left out), its locals and parameters, and its FRESH source (a stale file refuses).
  Port of Get-CalcHandler + Get-TraceSource (Trace.Walk.ps1:794, 2418). }
function TCalcFactsReader.ReadHandler(const pW: TEventWiring): TCalcHandler;
begin
  Result:= TCalcHandler.Create;
  var Done:= False;
  try
    var S:= FIndex.Query('SELECT s.name AS name, s.impl_start_line AS istart, s.impl_end_line AS iend, s.file_id AS fid, f.path AS path ' +
      'FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.id = ' + IntToStr(pW.HandlerId));
    var Fid: Integer;
    try
      Result.Name:= S[0].S('name');
      Result.Path:= S[0].S('path');
      Result.ImplStart:= S[0].I('istart');
      Result.ImplEnd:= S[0].I('iend');
      Fid:= S[0].I('fid');
    finally
      S.Free;
    end;
    var Rows:= FIndex.AllRows('SELECT r.id AS rid, r.kind AS kind, r.name_text AS nm, r.receiver_text AS recv, r.start_line AS line, ' +
      'r.start_col AS col, r.end_col AS ecol, t.id AS tid, t.kind AS tkind, t.qualified_name AS tq, t.start_line AS tdecl, tf.path AS tpath ' +
      'FROM refs r LEFT JOIN symbols t ON t.id = COALESCE((SELECT ce.target_symbol_id FROM call_edges ce WHERE ce.ref_id = r.id), r.symbol_id) ' +
      'LEFT JOIN files tf ON tf.id = t.file_id WHERE r.file_id = ' + IntToStr(Fid) + ' AND r.start_line BETWEEN ' +
      IntToStr(Result.ImplStart) + ' AND ' + IntToStr(Result.ImplEnd) + ' AND (r.enclosing_symbol_id = ' + IntToStr(pW.HandlerId) +
      ' OR r.enclosing_symbol_id IS NULL)', 'r.start_line, r.start_col, r.id');
    try
      for var R in Rows do
      begin
        var C: TCalcRef;
        C.Kind:= R.S('kind');
        C.Nm:= R.S('nm');
        C.Recv:= R.S('recv');
        C.Line:= R.I('line');
        C.Col:= R.I('col');
        C.ECol:= R.I('ecol');
        C.Tid:= R.I('tid');
        C.TKind:= R.S('tkind');
        C.TDecl:= R.I('tdecl');
        C.TPath:= R.S('tpath');
        Result.Refs:= Result.Refs + [C];
      end;
    finally
      Rows.Free;
    end;
    var Loc:= FIndex.Query('SELECT name AS name, kind AS kind FROM symbols WHERE parent_id = ' + IntToStr(pW.HandlerId) +
      ' AND kind IN (''local_var'', ''param'')');
    try
      for var L in Loc do
        Result.Locals.AddOrSetValue(L.S('name'), L.S('kind'));
    finally
      Loc.Free;
    end;
    if not FReader.SourceFresh(Result.Path) then
      raise EChartsTrace.Create('round-trip: ' + ExtractFileName(Result.Path) +
        ' differs from the indexed copy (sha256) -- refusing to read it. Reindex the project, then re-run.');
    var Read:= FReader.ReadPath(Result.Path);
    Result.Stripped:= FReader.StrippedSourceLines(Read);
    Result.Raw:= SplitLines(ReadLatin1(Read));
    Done:= True;
  finally
    if not Done then
      FreeAndNil(Result);
  end;
end;

{ Every TField variable of the class bound by exactly one (dataset field, column literal) pair. Port of Get-CalcBinding (Trace.Walk.ps1:2400). }
procedure TCalcFactsReader.ReadBindings(const pDs: TTraceDataSet; const pCol: string; pFacts: TCalcFacts);
begin
  var Rows:= FResolver.FieldVarWriteRows(pDs.ClassId, Format('v.parent_id = %d AND v.kind = ''field'' AND TRIM(v.signature) LIKE ''T%%Field''',
    [pDs.ClassId]));
  var Names: TArray<string>:= [];
  var Groups: TDictionary<string, TArray<TFieldVarWrite>>:= TDictionary<string, TArray<TFieldVarWrite>>.Create(TIStringComparer.Ordinal);
  try
    for var W in Rows do
    begin
      var G: TArray<TFieldVarWrite>;
      if not Groups.TryGetValue(W.VarName, G) then
        Names:= Names + [W.VarName];
      Groups.AddOrSetValue(W.VarName, G + [W]);
    end;
    for var N in Names do
    begin
      var Grp:= Groups[N];
      var B: TCalcBinding;
      B:= Default(TCalcBinding);
      B.VarName:= N;
      var Fp:= FieldVarPairs(Grp);
      if Length(Fp.Pairs) <> 1 then
        B.Why:= Format('is written on %d line(s) naming %d (dataset field, column literal) pairs', [Length(Grp), Length(Fp.Pairs)])
      else
      begin
        var P:= Fp.Pairs[0].Split(['|']);
        B.DataSet:= P[0];
        B.Literal:= P[1];
        var Site:= Fp.Ok[0];
        var G:= FieldVarSiteGrade(Site, B.DataSet);
        var Cl: TArray<string>:= [];
        for var C in Site.Calls.Split([',']) do
          if (C <> '') and not SameText(C, NAME_FIELDBYNAME) then
            Cl:= Cl + [C];
        Cl:= SortUniqueNames(Cl);
        B.Via:= if Site.Fbn > 0 then 'by FieldByName' else if Length(Cl) = 1 then 'via ' + Cl[0]
          else if Length(Cl) > 1 then 'via one of ' + string.Join(', ', Cl) else 'with no call on the line';
        B.Line:= Site.Line;
        B.Path:= Site.Path;
        B.Qname:= Site.VarQName;
        B.Grade:= G.Grade;
        B.Reason:= G.Reason;
        B.Ask:= G.Ask;
        if SameText(B.DataSet, pDs.Name) and SameText(B.Literal, pCol) then
          pFacts.Vars:= pFacts.Vars + [N];
      end;
      pFacts.Bindings.AddOrSetValue(N, B);
    end;
  finally
    Groups.Free;
  end;
end;

{ Every event wired on the dataset: OnCalcFields decides; any other On* / After* / Before* names a field set there. }
procedure TCalcFactsReader.ReadWirings(const pDs: TTraceDataSet; pFacts: TCalcFacts);
begin
  var Events: TArray<string>:= [];
  var Ev:= FIndex.Query('SELECT DISTINCT r.name_text AS ev FROM refs r WHERE r.file_id = ' + IntToStr(pDs.Fid) +
    ' AND r.kind = ''member-access'' AND r.receiver_text = ''' + TChartsIndex.SqlText(pDs.Name) + ''' AND (r.name_text LIKE ''On%'' ' +
    'OR r.name_text LIKE ''After%'' OR r.name_text LIKE ''Before%'')');
  try
    for var R in Ev do
      if TRegEx.IsMatch(R.S('ev'), RE_EVENT_NAME) then
        Events:= Events + [R.S('ev')];
  finally
    Ev.Free;
  end;
  if Length(Events) = 0 then
    Exit;
  var Wl:= FResolver.EventWiring(pDs, Events);
  TStable.Sort<TEventWiring>(Wl, function(const pA, pB: TEventWiring): Integer
    begin
      Result:= Ord(not SameText(pA.Event, ON_CALC_FIELDS)) - Ord(not SameText(pB.Event, ON_CALC_FIELDS));
      if Result = 0 then
        Result:= pA.Line - pB.Line;
    end);
  for var W in Wl do
  begin
    var Wi:= TCalcWiring.Create;
    pFacts.Wirings.Add(Wi);
    Wi.Event:= W.Event;
    Wi.Line:= W.Line;
    Wi.Handler:= W.Handler;
    Wi.WirePath:= pDs.FileName;
    Wi.H:= ReadHandler(W);
  end;
end;

{ The line that CREATES the field: its name as a literal beside the dataset on a line that writes no variable; its first call, and the
  FieldKind that call's body sets. }
procedure TCalcFactsReader.ReadCreating(const pDs: TTraceDataSet; const pCol: string; pFacts: TCalcFacts);
begin
  var Cl:= FIndex.Query('SELECT sl.start_line AS line FROM string_literals sl WHERE sl.file_id = ' + IntToStr(pDs.Fid) +
    ' AND sl.kind = ''literal'' AND UPPER(sl.text) = UPPER(''' + TChartsIndex.SqlText(pCol) + ''') AND EXISTS (SELECT 1 FROM refs d ' +
    'WHERE d.file_id = sl.file_id AND d.start_line = sl.start_line AND d.kind = ''read'' AND d.name_text = ''' +
    TChartsIndex.SqlText(pDs.Name) + ''') AND NOT EXISTS (SELECT 1 FROM refs w WHERE w.file_id = sl.file_id AND ' +
    'w.start_line = sl.start_line AND w.kind = ''write'') ORDER BY sl.start_line LIMIT 1');
  try
    if Cl.Count = 0 then
      Exit;
    var C:= Default(TCalcCreating);
    C.Present:= True;
    C.Line:= Cl[0].I('line');
    C.Path:= pDs.FileName;
    pFacts.Creating:= C;
  finally
    Cl.Free;
  end;
  var FkKinds: TArray<string>:= [];
  for var K in CALC_FK_KINDS do
    FkKinds:= FkKinds + [K];
  var Call:= FIndex.Query('SELECT r.name_text AS nm, COALESCE((SELECT ce.target_symbol_id FROM call_edges ce WHERE ce.ref_id = r.id), ' +
    'r.symbol_id) AS tid FROM refs r WHERE r.file_id = ' + IntToStr(pDs.Fid) + ' AND r.start_line = ' + IntToStr(pFacts.Creating.Line) +
    ' AND r.kind = ''call'' ORDER BY r.start_col LIMIT 1');
  try
    if Call.Count = 0 then
      Exit;
    pFacts.Creating.Call:= Call[0].S('nm');
    if Call[0].I('tid') = 0 then
      Exit;
    { the kind only when the body sets FieldKind on exactly ONE line (a helper that sets it on several, by branch, proves no kind) }
    var Fk:= FIndex.Query('SELECT r.name_text AS k, r.start_line AS line, f.path AS path FROM refs r JOIN files f ON f.id = r.file_id ' +
      'WHERE r.enclosing_symbol_id = ' + IntToStr(Call[0].I('tid')) + ' AND r.kind = ''read'' AND r.name_text IN (' +
      TChartsIndex.SqlInList(FkKinds) + ') AND EXISTS (SELECT 1 FROM refs m WHERE m.file_id = r.file_id AND ' +
      'm.start_line = r.start_line AND m.kind = ''member-access'' AND m.name_text = ''FieldKind'') ORDER BY r.start_line LIMIT ' +
      IntToStr(FIELDKIND_LIMIT));
    try
      if Fk.Count = 1 then
      begin
        pFacts.Creating.Kind:= Fk[0].S('k');
        pFacts.Creating.KindLine:= Fk[0].I('line');
        pFacts.Creating.KindPath:= Fk[0].S('path');
      end;
    finally
      Fk.Free;
    end;
  finally
    Call.Free;
  end;
end;

function TCalcFactsReader.Facts(const pDs: TTraceDataSet; const pCol, pTable: string): TCalcFacts;
begin
  Result:= TCalcFacts.Create;
  var Done:= False;
  try
    Result.Field:= pCol;
    Result.DsName:= pDs.Name;
    Result.Table:= pTable;
    var Cls:= FIndex.Query('SELECT name AS name FROM symbols WHERE id = ' + IntToStr(pDs.ClassId));
    try
      Result.OwnerClass:= if Cls.Count > 0 then Cls[0].S('name') else '';
    finally
      Cls.Free;
    end;
    var Cf:= FIndex.AllRows('SELECT s.id AS id, s.name AS name, s.signature AS sig FROM symbols s WHERE s.parent_id = ' +
      IntToStr(pDs.ClassId) + ' AND s.kind = ''field''', 's.id');
    try
      for var F in Cf do
        Result.ClassFields.AddOrSetValue(F.S('name'), Trim(F.S('sig')));
    finally
      Cf.Free;
    end;
    ReadBindings(pDs, pCol, Result);
    ReadWirings(pDs, Result);
    ReadCreating(pDs, pCol, Result);
    var Tds:= FResolver.TableDataSetRows(pTable);
    try
      Result.TableDataSets:= Tds.Count;
    finally
      Tds.Free;
    end;
    var Catalog:= FCatalog;
    var Set_:= FSet;
    var Table:= pTable;
    Result.IsColumn:= function(pLit: string): Boolean
      begin
        Result:= SqlColumnState(Catalog, Set_, Table, pLit, TServerSqlHit.None, '').IsColumn;
      end;
    Done:= True;
  finally
    if not Done then
      FreeAndNil(Result);
  end;
end;

function TCalcFactsReader.Info(const pDs: TTraceDataSet; const pCol, pTable: string): TCalcInfo;
begin
  var F:= Facts(pDs, pCol, pTable);
  try
    Result:= ResolveCalcField(F);
  finally
    F.Free;
  end;
end;

procedure TCalcFactsReader.Apply(pResult: TAnchorResult; const pCol: string);
begin
  if (not pResult.HasDataSet) or (pResult.Column = '') or (pResult.Stop = '') or (pResult.TableColumn <> '') or (pResult.Calc <> nil) then
    Exit;
  var Cf:= Info(pResult.DataSet, pCol, pResult.Table);
  if Cf = nil then
    Exit;
  pResult.Calc:= Cf;
  pResult.Stop:= Cf.StopText;
  pResult.StopAnchor:= Cf.Anchor;
end;

end.
