unit DRagLint.FieldRepo.Lineage;

{ drag-lint 1.56 -- lane LIN-1: the read-only lineage model of pre-calculated data fields (SPEC-LIN 2, 3.1, 5.2): per dataset field -> derived yes / no, kind, input fields, expression text. Writes nothing to a repository.
  First caller: DRagLint.FieldRepo.DfmReadDerived (lane LIN-2).

  The model reads a PROJECT INDEX (the B14 facts of the 1.56 extractor: ds_field_accesses, loop_facts and the
  data_flows rows of kind dsfield, beside refs, symbols and the dfm_* tables) through its own reader
  connection, and the unit's source file for the statement text. It answers per UNIT: owner answer DL-3 (only the
  unit paired with the DFM counts) is the caller's choice of unit. What it does NOT do: decide whether a field is
  a table column (the repository knows), choose a home table, write NOTES / DL_FIELD_INPUTS rows, rewrite field
  references to macros. Those are lane LIN-2's.

  Everything is syntactic, as the facts are: a persistent field component is resolved to its dataset and
  FieldName through the paired DFM of the SAME index; without one it stays a component name. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  FireDAC.Comp.Client;

const
  /// <summary>Kind of a field or write that is not derived.</summary>
  LINEAGE_KIND_NONE = '';
  /// <summary>DERIVED_KIND: every known input is read in the writing routine (owner answer DL-1 A).</summary>
  LINEAGE_KIND_DIRECT = 'direct';
  /// <summary>DERIVED_KIND: written in or after a loop over ANOTHER dataset (owner answer DL-2 A).</summary>
  LINEAGE_KIND_AGGREGATE = 'aggregate';
  /// <summary>DERIVED_KIND: written from something the model cannot follow, no input known (DL-6 A).</summary>
  LINEAGE_KIND_UNKNOWN = 'unknown';

  /// <summary>Reason: the field name is not a string literal (FieldByName(sName), Fields[i]).</summary>
  LINEAGE_REASON_RUNTIME_NAME = 'field name built at run time';
  /// <summary>Reason format: the value arrives through a parameter of the writing routine.</summary>
  LINEAGE_REASON_PARAM_FMT = 'value of parameter %s';
  /// <summary>Reason format: the value arrives through a class field that is no dataset field.</summary>
  LINEAGE_REASON_FIELD_FMT = 'value of field %s';
  /// <summary>Reason format: the value arrives through a unit variable.</summary>
  LINEAGE_REASON_GLOBAL_FMT = 'value of unit variable %s';
  /// <summary>Reason format: the value is the result (or a var / out argument) of a project routine.</summary>
  LINEAGE_REASON_CALL_FMT = 'result of %s (calls are not followed)';
  /// <summary>Reason: the value is a Lookup / VarArrayOf result.</summary>
  LINEAGE_REASON_VARIANT = 'through a Variant';
  /// <summary>Reason format: an unqualified access inside `with A, B do` naming several datasets.</summary>
  LINEAGE_REASON_WITH_FMT = 'inside with over %d datasets';
  /// <summary>Reason: the writing routine reached the extractor's per-routine flow row cap.</summary>
  LINEAGE_REASON_ROW_CAP = 'routine too large (flow row cap)';
  /// <summary>Reason format: the unit on disk is not the unit that was indexed.</summary>
  LINEAGE_REASON_STALE_FMT = 'index stale for %s';

  /// <summary>Longest expression text returned; a longer one is cut and ends in LINEAGE_EXPR_CUT.</summary>
  LINEAGE_EXPR_MAX = 400;
  /// <summary>Tail of a cut expression text.</summary>
  LINEAGE_EXPR_CUT = ' ...';
  /// <summary>Most defining statements of locals listed per write; one more entry '...' follows when cut.</summary>
  LINEAGE_VIA_MAX = 3;

type
  /// <summary>Raised when the index cannot answer at all: it does not open, or it has no B14 facts.</summary>
  ELineageError = class(Exception);

  /// <summary>One dataset field a written value is computed from.</summary>
  /// <remarks>Dataset + FieldName are set when the field is named in the source (FieldByName('F')) or its
  /// component is declared in the unit's DFM. A component of another module, or of an ancestor form, has only
  /// Component (as written, with its qualifier).</remarks>
  TLineageInput = record
    /// <summary>Dataset component as written ('qryCust'); '' when not known.</summary>
    Dataset: string;
    /// <summary>The field name of the dataset ('DISCOUNT'); '' when only the component is known.</summary>
    FieldName: string;
    /// <summary>Persistent field component as written ('tblOrdersQTY'); '' for a by-name access.</summary>
    Component: string;
    /// <summary>Line of the read; 0 when the fact carries no position.</summary>
    Line: Integer;
    /// <summary>Column of the read; 0 when the fact carries no position.</summary>
    Col: Integer;
    /// <summary>True when the value reaches the write through a local variable.</summary>
    ViaLocal: Boolean;
    /// <summary>'Dataset.FieldName' when both are known, else the component, else the bare field name.</summary>
    /// <returns>A display name; never ''.</returns>
    function DisplayName: string;
  end;

  /// <summary>One statement that writes a field from at least one input or untraceable value.</summary>
  TLineageWrite = record
    /// <summary>Qualified name of the writing routine ('uLinDirect.TfLinDirect.tblOrdersAfterOpen').</summary>
    Routine: string;
    /// <summary>Line of the write (the accessor, as the index has it).</summary>
    Line: Integer;
    /// <summary>Column of the write.</summary>
    Col: Integer;
    /// <summary>DFM bindings of the routine ('tblOrders.AfterOpen'; several: ', ' separated); '' = none.</summary>
    Event: string;
    /// <summary>LINEAGE_KIND_DIRECT / _AGGREGATE / _UNKNOWN.</summary>
    Kind: string;
    /// <summary>The known inputs, in source order; the written field itself is never one.</summary>
    Inputs: TArray<TLineageInput>;
    /// <summary>The writing statement as written, one line, ending in ';' (cut at LINEAGE_EXPR_MAX).</summary>
    ExprText: string;
    /// <summary>Defining statements of the locals on the path: 'text  (line n)'; at most LINEAGE_VIA_MAX.</summary>
    Via: TArray<string>;
    /// <summary>Kind aggregate: the loop head as written ('while not qryLines.Eof'); else ''.</summary>
    LoopText: string;
    /// <summary>Kind aggregate: the dataset the loop iterates ('qryLines'); else ''.</summary>
    LoopDataset: string;
    /// <summary>Why an input is not known (the LINEAGE_REASON_* texts), without duplicates.</summary>
    Unknown: TArray<string>;
  end;

  /// <summary>The answer for one dataset field of one unit.</summary>
  /// <remarks>A field no statement of the unit writes is not in TLineageUnit.Fields at all.</remarks>
  TLineageField = record
    /// <summary>Dataset component ('tblOrders'); '' when not known; 'B|A' for a write inside `with A, B do`.</summary>
    Dataset: string;
    /// <summary>Field name ('TOTAL'); '' when only the component is known.</summary>
    FieldName: string;
    /// <summary>Persistent field component the writes use ('tblOrdersTOTAL'); '' for by-name writes only.</summary>
    Component: string;
    /// <summary>True when at least one write has an input or an untraceable value.</summary>
    Derived: Boolean;
    /// <summary>aggregate when any write is, else direct when any write is, else unknown; '' = not derived.</summary>
    Kind: string;
    /// <summary>Union of the writes' inputs.</summary>
    Inputs: TArray<TLineageInput>;
    /// <summary>Union of the writes' reasons.</summary>
    Unknown: TArray<string>;
    /// <summary>The writes that make the field derived, in source order of the index.</summary>
    Writes: TArray<TLineageWrite>;
    /// <summary>Writes that take no dataset field and nothing untraceable (a literal, Now, a control):
    /// they do not mark the field (SPEC-LIN "written in code, no field input").</summary>
    WritesWithoutFieldInput: Integer;
  end;

  /// <summary>A write whose field name is built at run time: it marks NO named field (SPEC-LIN DL-6, U1).</summary>
  TLineageRuntimeWrite = record
    /// <summary>Dataset as written; '' when not known.</summary>
    Dataset: string;
    /// <summary>The name expression as written ('vName'); the index expression for Fields[i].</summary>
    NameText: string;
    /// <summary>Qualified name of the writing routine.</summary>
    Routine: string;
    /// <summary>Line of the write.</summary>
    Line: Integer;
  end;

  /// <summary>Everything the model knows about the field writes of one unit.</summary>
  TLineageUnit = record
    /// <summary>The unit's path as asked.</summary>
    UnitPath: string;
    /// <summary>False when the index has no file of that path: nothing else is set.</summary>
    Indexed: Boolean;
    /// <summary>True when the file on disk differs from the indexed one (SHA-256) or is gone: Fields and
    /// RuntimeNameWrites are EMPTY then, nothing is guessed.</summary>
    Stale: Boolean;
    /// <summary>LINEAGE_REASON_STALE_FMT with the unit name when Stale; else ''.</summary>
    StaleReason: string;
    /// <summary>One entry per written field, in order of the first write.</summary>
    Fields: TArray<TLineageField>;
    /// <summary>The writes with a field name built at run time.</summary>
    RuntimeNameWrites: TArray<TLineageRuntimeWrite>;
    /// <summary>Finds the entry of a field by dataset and field name (both case-insensitive).</summary>
    /// <param name="pDataset">Dataset component; an entry written inside `with A, B do` matches either.</param>
    /// <param name="pFieldName">Field name of the dataset.</param>
    /// <param name="pField">The entry when found; a not-derived record naming the field otherwise.</param>
    /// <returns>True when a statement of the unit writes the field.</returns>
    function Find(const pDataset, pFieldName: string; out pField: TLineageField): Boolean;
  end;

  /// <summary>Read-only lineage model over one project index.</summary>
  /// <remarks>Not thread-safe. Owns its connection (the engine's shared reader open, ConnectReadOnly of
  /// DRagLint.Storage.FileMembership, in Create; closed in Destroy). Unit
  /// answers are cached per path for the life of the object; create a new model after a reindex.</remarks>
  TFieldLineageModel = class
  private
    FConn: TFDConnection;
    FCache: TDictionary<string, TLineageUnit>;
    function FileIdOf(const pPath: string; out pSha: string): Int64;
  public
    /// <summary>Opens the index read-only.</summary>
    /// <param name="pIndexDb">Path of a project index (`resolve-dbs`); must exist.</param>
    /// <exception cref="ELineageError">The file is missing, does not open, or has no ds_field_accesses /
    /// loop_facts table (indexed by an engine older than 1.56).</exception>
    constructor Create(const pIndexDb: string);
    /// <summary>Closes the index.</summary>
    destructor Destroy; override;
    /// <summary>The written fields of one unit.</summary>
    /// <param name="pUnitPath">Full path of the .pas file, as indexed (case-insensitive).</param>
    /// <returns>See TLineageUnit: Indexed False for a unit the index does not hold, Stale True with no
    /// fields when the file changed after indexing.</returns>
    function ReadUnit(const pUnitPath: string): TLineageUnit;
    /// <summary>The answer for one field of one unit.</summary>
    /// <param name="pUnitPath">Full path of the .pas file.</param>
    /// <param name="pDataset">Dataset component name.</param>
    /// <param name="pFieldName">Field name of the dataset.</param>
    /// <returns>The field's entry; Derived False (Kind '') when the unit never writes it. For a stale unit:
    /// Derived False with the stale reason in Unknown.</returns>
    function FieldLineage(const pUnitPath, pDataset, pFieldName: string): TLineageField;
    /// <summary>Routines of OTHER units that write a persistent field component of this unit's form
    /// (`fLinWhere.tblOrdersX.AsFloat := ...`); they never mark the field (owner answer DL-3 A).</summary>
    /// <param name="pUnitPath">Full path of the unit that owns the component.</param>
    /// <param name="pComponent">The field component ('tblOrdersX').</param>
    /// <returns>Qualified routine names, sorted, without duplicates. When the unit has an indexed DFM the
    /// qualifier must be its root object name; without one every `X.pComponent` write counts.</returns>
    function ExternalWriters(const pUnitPath, pComponent: string): TArray<string>;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Math,
  System.Hash,
  System.RegularExpressions,
  Data.DB,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.DApt,
  DRagLint.Storage.FileMembership;

const
  { the extractor's DF_ROW_CAP (DRagLint.Core.Model); the FieldRepo units do not use the engine's model unit }
  FLOW_ROW_CAP = 4000;
  { ds_field_accesses and loop_facts: the tables only a 1.56 index has }
  B14_TABLE_COUNT = 2;
  COL_BITS = 20;
  WITH_SEP = '|';
  VIA_MORE = '...';
  SHAPE_ACCESSOR = 'accessor';
  NAME_LITERAL = 'literal';
  ROOT_PARAM = 'param';
  MODE_WRITE = 'write';
  LOOP_FOR = 'for';
  LOOP_FOR_IN = 'for-in';
  SRC_DSFIELD = 'dsfield';
  SRC_REF = 'ref';
  SRC_FIELD = 'field';
  SRC_PARAM = 'param';
  SRC_GLOBAL = 'global';
  SRC_ARGOUT = 'argout';
  REF_CALL = 'call';
  TYPE_FIELD_TAIL = 'Field';
  SELF_PREFIX = 'Self.';
  EXT_DFM = '.dfm';
  RX_IDENT_CHAIN = '^[A-Za-z_][\w.]*$';
  RX_EOF = '([A-Za-z_][\w.]*)\.Eof\b';
  RX_RECORD_COUNT = '([A-Za-z_][\w.]*)\.RecordCount\b';
  RX_NEXT_TAIL = '\.Next\b';
  RX_NEXT_OR_RECNO_TAIL = '\.(Next\b|RecNo\s*:=)';

type
  { column orders of the fact queries below: each enum is the SELECT list of its loader, in order }
  TAccCol = (acSymbolId, acMode, acLine, acCol, acShape, acDatasetText, acFieldText, acFieldName, acNameKind, acNameText,  // dl:ok enum-ordinal-persisted@9559 -- REVIEWED 2026-11-27 LIN-1: the ordinal is the column position in the loader's own SELECT list (Q.Fields[Ord(x)]), read in the same routine; no ordinal is stored anywhere
    acAccessor, acRootKind, acRootName, acWithCtx, acRhsStartLine, acRhsEndLine, acRhsEndCol, acStmtLine, acStmtCol);
  TFlowCol = (fcDstLine, fcDstCol, fcSrcKind, fcSrcLine, fcSrcCol, fcSrcName, fcViaLocal);  // dl:ok enum-ordinal-persisted@c674 -- REVIEWED 2026-11-27 LIN-1: the ordinal is the column position in the loader's own SELECT list (Q.Fields[Ord(x)]), read in the same routine; no ordinal is stored anywhere
  TLoopCol = (lcSymbolId, lcKind, lcStartLine, lcStartCol, lcEndLine, lcEndCol, lcCondStartLine, lcCondStartCol,  // dl:ok enum-ordinal-persisted@8f3a -- REVIEWED 2026-11-27 LIN-1: the ordinal is the column position in the loader's own SELECT list (Q.Fields[Ord(x)]), read in the same routine; no ordinal is stored anywhere
    lcCondEndLine, lcCondEndCol);
  TRefCol = (rcKind, rcName, rcLine, rcCol, rcSymbolId, rcReceiverText, rcReceiverType);  // dl:ok enum-ordinal-persisted@1e12 -- REVIEWED 2026-11-27 LIN-1: the ordinal is the column position in the loader's own SELECT list (Q.Fields[Ord(x)]), read in the same routine; no ordinal is stored anywhere

  TAccess = record
    SymbolId: Int64;
    IsWrite: Boolean;
    Line, Col: Integer;
    Shape, DatasetText, FieldText, FieldName, NameKind, NameText, Accessor, RootKind, RootName, WithCtx: string;
    RhsStartLine, RhsEndLine, RhsEndCol, StmtLine, StmtCol: Integer;
  end;

  TFlow = record
    SrcKind, SrcName: string;
    SrcLine, SrcCol: Integer;
    ViaLocal: Boolean;
  end;

  TLoop = record
    SymbolId: Int64;
    Kind: string;
    StartLine, StartCol, EndLine, EndCol: Integer;
    CondStartLine, CondStartCol, CondEndLine, CondEndCol: Integer;
  end;

  TRefInfo = record
    Name, ReceiverText, ReceiverType: string;
    ResolvedCall: Boolean;
  end;

  TDfmField = record
    Dataset, FieldName: string;
  end;

  TSymbolName = record
    Name, Qualified: string;
  end;

  { One unit's facts and the walk over its writes. Lives for one ReadUnit call. }
  TUnitReader = class  // dl:ok god-class@e372, high-response@e372 -- REVIEWED 2026-11-27 LIN-1: one private per-unit reader -- the fact tables of ONE unit and the walk over its writes share the lookups by design; it lives for one ReadUnit call; REVIEWED 2026-11-27 LIN-1: same private per-unit reader; most of the response set is the eight straight-line loaders
  private
    FConn: TFDConnection;
    FFileId: Int64;
    FLines: TArray<string>;
    FAccesses: TList<TAccess>;
    FAccByPos: TDictionary<Int64, Integer>;
    FFlows: TObjectDictionary<Int64, TList<TFlow>>;
    FLoops: TList<TLoop>;
    FRefs: TDictionary<Int64, TRefInfo>;
    FSymbols: TDictionary<Int64, TSymbolName>;
    FCapped: TDictionary<Int64, Boolean>;
    FDfmFields: TDictionary<string, TDfmField>;
    FDfmObjects: TDictionary<string, Boolean>;
    FEvents: TDictionary<string, string>;
    FRootName: string;
    FFieldIndex: TDictionary<string, Integer>;
    FFields: TList<TLineageField>;
    FRuntime: TList<TLineageRuntimeWrite>;
    procedure LoadAccesses;
    procedure LoadFlows;
    procedure LoadLoops;
    procedure LoadRefs;
    procedure LoadSymbols;
    procedure LoadDfm(pDfmFileId: Int64);
    function TextRange(pStartLine, pStartCol, pEndLine, pEndCol: Integer): string;
    function StatementAt(pLine, pCol: Integer): string;
    function LocalName(const pText: string): string;
    function DatasetOf(const pAcc: TAccess; out pWithCount: Integer): string;
    function IteratedDataset(const pLoop: TLoop): string;
    function AggregateLoop(const pAcc: TAccess; const pTarget: TLineageField; const pFlows: TList<TFlow>;
      out pLoop: TLoop; out pDataset: string): Boolean;
    procedure AddRefSource(const pFlow: TFlow; const pTargetKey: string; pSeen: TDictionary<string, Boolean>;
      var pWrite: TLineageWrite);
    procedure AddDsFieldSource(const pFlow: TFlow; const pTargetKey: string; var pWrite: TLineageWrite);
    procedure AddFieldSource(const pFlow: TFlow; const pTargetKey: string; pSeen: TDictionary<string, Boolean>;
      var pWrite: TLineageWrite);
    procedure AddVia(const pFlow: TFlow; const pAcc: TAccess; var pWrite: TLineageWrite);
    function BuildWrite(const pAcc: TAccess; const pTarget: TLineageField; pWithCount: Integer): TLineageWrite;
    procedure ProcessWrite(const pAcc: TAccess);
    procedure Summarise(var pField: TLineageField);
  public
    constructor Create(pConn: TFDConnection; pFileId, pDfmFileId: Int64; const pLines: TArray<string>);
    destructor Destroy; override;
    procedure Run(var pUnit: TLineageUnit);
  end;

{ ---------------------------------------------------------------------------------------------- helpers }

function PosKey(pLine, pCol: Integer): Int64;
begin
  Result := (Int64(pLine) shl COL_BITS) or pCol;
end;

function LastSegment(const pText: string): string;
begin
  Result := Copy(pText, LastDelimiter('.', pText) + 1, MaxInt);
end;

function FieldKey(const pDataset, pFieldName, pComponent: string): string;
begin
  Result := if pFieldName <> '' then LowerCase(pDataset) + WITH_SEP + LowerCase(pFieldName)
    else '#' + LowerCase(pComponent);
end;

function IsBefore(pLineA, pColA, pLineB, pColB: Integer): Boolean;
begin
  Result := (pLineA < pLineB) or ((pLineA = pLineB) and (pColA < pColB));
end;

function IsInside(pLine, pCol: Integer; const pLoop: TLoop): Boolean;
begin
  Result := not IsBefore(pLine, pCol, pLoop.StartLine, pLoop.StartCol) and
    IsBefore(pLine, pCol, pLoop.EndLine, pLoop.EndCol);
end;

procedure AddReason(var pReasons: TArray<string>; const pReason: string);
begin
  if IndexStr(pReason, pReasons) < 0 then
    pReasons := pReasons + [pReason];
end;

procedure AddInputTo(var pInputs: TArray<TLineageInput>; const pInput: TLineageInput);
var
  Key: string;
  I: Integer;
  Known: Boolean;
begin
  Key := FieldKey(pInput.Dataset, pInput.FieldName, pInput.Component);
  Known := False;
  for I := 0 to High(pInputs) do
    if FieldKey(pInputs[I].Dataset, pInputs[I].FieldName, pInputs[I].Component) = Key then
      Known := True;
  if not Known then
    pInputs := pInputs + [pInput];
end;

procedure AddInput(var pWrite: TLineageWrite; const pTargetKey, pDataset, pFieldName, pComponent: string;
  const pFlow: TFlow);
var
  Input: TLineageInput;
begin
  { the written field read in its own right-hand side (COUNT2 := COUNT2 + n) is not an input of itself }
  if FieldKey(pDataset, pFieldName, pComponent) = pTargetKey then
    Exit;
  Input := Default(TLineageInput);
  Input.Dataset := pDataset;
  Input.FieldName := pFieldName;
  Input.Component := pComponent;
  Input.Line := pFlow.SrcLine;
  Input.Col := pFlow.SrcCol;
  Input.ViaLocal := pFlow.ViaLocal;
  AddInputTo(pWrite.Inputs, Input);
end;

function OpenQuery(pConn: TFDConnection; const pSql: string; const pParams: array of Variant): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  try
    Result.Connection := pConn;
    Result.FetchOptions.Unidirectional := True;
    Result.Open(pSql, pParams);  // dl:ok dataset-open-without-close@1d69 -- REVIEWED 2026-11-27 LIN-1: a factory -- it returns the OPEN query; every caller frees it in a finally (Free closes the cursor)
  except
    Result.Free;
    raise;
  end;
end;

{ ---------------------------------------------------------------------------------------------- records }

function TLineageInput.DisplayName: string;
begin
  if (Dataset <> '') and (FieldName <> '') then
    Result := Dataset + '.' + FieldName
  else if Component <> '' then
    Result := Component
  else
    Result := FieldName;
end;

function TLineageUnit.Find(const pDataset, pFieldName: string; out pField: TLineageField): Boolean;
var
  I: Integer;
begin
  Result := False;
  pField := Default(TLineageField);
  pField.Dataset := pDataset;
  pField.FieldName := pFieldName;
  for I := 0 to High(Fields) do
    if not Result and SameText(Fields[I].FieldName, pFieldName) and
      (IndexText(pDataset, Fields[I].Dataset.Split([WITH_SEP])) >= 0) then
    begin
      pField := Fields[I];
      Result := True;
    end;
end;

{ ---------------------------------------------------------------------------------------------- TUnitReader }

constructor TUnitReader.Create(pConn: TFDConnection; pFileId, pDfmFileId: Int64; const pLines: TArray<string>);
begin
  inherited Create;
  FConn := pConn;
  FFileId := pFileId;
  FLines := pLines;
  FAccesses := TList<TAccess>.Create;
  FAccByPos := TDictionary<Int64, Integer>.Create;
  FFlows := TObjectDictionary<Int64, TList<TFlow>>.Create([doOwnsValues]);
  FLoops := TList<TLoop>.Create;
  FRefs := TDictionary<Int64, TRefInfo>.Create;
  FSymbols := TDictionary<Int64, TSymbolName>.Create;
  FCapped := TDictionary<Int64, Boolean>.Create;
  FDfmFields := TDictionary<string, TDfmField>.Create;
  FDfmObjects := TDictionary<string, Boolean>.Create;
  FEvents := TDictionary<string, string>.Create;
  FFieldIndex := TDictionary<string, Integer>.Create;
  FFields := TList<TLineageField>.Create;
  FRuntime := TList<TLineageRuntimeWrite>.Create;
  LoadAccesses;
  LoadFlows;
  LoadLoops;
  LoadRefs;
  LoadSymbols;
  if pDfmFileId > 0 then
    LoadDfm(pDfmFileId);
end;

destructor TUnitReader.Destroy;
begin
  FRuntime.Free;
  FFields.Free;
  FFieldIndex.Free;
  FEvents.Free;
  FDfmObjects.Free;
  FDfmFields.Free;
  FCapped.Free;
  FSymbols.Free;
  FRefs.Free;
  FLoops.Free;
  FFlows.Free;
  FAccByPos.Free;
  FAccesses.Free;
  inherited;
end;

procedure TUnitReader.LoadAccesses;
var
  Q: TFDQuery;
  A: TAccess;
begin
  Q := OpenQuery(FConn,
    'SELECT symbol_id, mode, line, col, shape, dataset_text, field_text, field_name, name_kind, name_text, ' +
    'accessor, root_kind, root_name, with_ctx, rhs_start_line, rhs_end_line, rhs_end_col, stmt_line, stmt_col ' +
    'FROM ds_field_accesses WHERE file_id = :f ORDER BY ordinal', [FFileId]);
  try
    while not Q.Eof do
    begin
      A := Default(TAccess);
      A.SymbolId := Q.Fields[Ord(acSymbolId)].AsLargeInt;
      A.IsWrite := SameText(Q.Fields[Ord(acMode)].AsString, MODE_WRITE);
      A.Line := Q.Fields[Ord(acLine)].AsInteger;
      A.Col := Q.Fields[Ord(acCol)].AsInteger;
      A.Shape := Q.Fields[Ord(acShape)].AsString;
      A.DatasetText := Q.Fields[Ord(acDatasetText)].AsString;
      A.FieldText := Q.Fields[Ord(acFieldText)].AsString;
      A.FieldName := Q.Fields[Ord(acFieldName)].AsString;
      A.NameKind := Q.Fields[Ord(acNameKind)].AsString;
      A.NameText := Q.Fields[Ord(acNameText)].AsString;
      A.Accessor := Q.Fields[Ord(acAccessor)].AsString;
      A.RootKind := Q.Fields[Ord(acRootKind)].AsString;
      A.RootName := Q.Fields[Ord(acRootName)].AsString;
      A.WithCtx := Q.Fields[Ord(acWithCtx)].AsString;
      A.RhsStartLine := Q.Fields[Ord(acRhsStartLine)].AsInteger;
      A.RhsEndLine := Q.Fields[Ord(acRhsEndLine)].AsInteger;
      A.RhsEndCol := Q.Fields[Ord(acRhsEndCol)].AsInteger;
      A.StmtLine := Q.Fields[Ord(acStmtLine)].AsInteger;
      A.StmtCol := Q.Fields[Ord(acStmtCol)].AsInteger;
      FAccByPos.AddOrSetValue(PosKey(A.Line, A.Col), FAccesses.Add(A));
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

procedure TUnitReader.LoadFlows;
var
  Q: TFDQuery;
  SymbolId: TField;
  F: TFlow;
  Key: Int64;
  Rows: TList<TFlow>;
begin
  { Reads BOTH data_flows row sets (the pre-1.56 rows and the 1.56 value rows; see TDataFlowRow.ValClass): a write
    from a scalar parameter / unit variable / call result exists only as a value row and is a lineage
    "unknown" reason. A numeric flow's '' row and its classed twin collapse in BuildWrite: inputs are keyed
    by field, reasons and via texts are sets. }
  { positioned sources first: the unpositioned 'field' twin of a component read is judged after its 'ref' }
  Q := OpenQuery(FConn,
    'SELECT dst_line, dst_col, src_kind, src_line, src_col, src_name, via_local FROM data_flows ' +
    'WHERE file_id = :f AND dst_kind IN (''write'', ''dsfield'') ' +
    'ORDER BY dst_line, dst_col, (src_line = 0), src_line, src_col, src_name', [FFileId]);
  try
    while not Q.Eof do
    begin
      F := Default(TFlow);
      F.SrcKind := Q.Fields[Ord(fcSrcKind)].AsString;
      F.SrcLine := Q.Fields[Ord(fcSrcLine)].AsInteger;
      F.SrcCol := Q.Fields[Ord(fcSrcCol)].AsInteger;
      F.SrcName := Q.Fields[Ord(fcSrcName)].AsString;
      F.ViaLocal := Q.Fields[Ord(fcViaLocal)].AsInteger <> 0;
      Key := PosKey(Q.Fields[Ord(fcDstLine)].AsInteger, Q.Fields[Ord(fcDstCol)].AsInteger);
      if not FFlows.TryGetValue(Key, Rows) then
      begin
        Rows := TList<TFlow>.Create;
        FFlows.Add(Key, Rows);
      end;
      Rows.Add(F);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
  Q := OpenQuery(FConn,
    'SELECT symbol_id, COUNT(*) AS n FROM data_flows WHERE file_id = :f GROUP BY symbol_id HAVING COUNT(*) >= :cap',
    [FFileId, FLOW_ROW_CAP]);
  try
    SymbolId := Q.FieldByName('symbol_id');
    while not Q.Eof do
    begin
      FCapped.AddOrSetValue(SymbolId.AsLargeInt, True);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

procedure TUnitReader.LoadLoops;
var
  Q: TFDQuery;
  L: TLoop;
begin
  Q := OpenQuery(FConn,
    'SELECT symbol_id, kind, start_line, start_col, end_line, end_col, cond_start_line, cond_start_col, ' +
    'cond_end_line, cond_end_col FROM loop_facts WHERE file_id = :f ORDER BY ordinal', [FFileId]);
  try
    while not Q.Eof do
    begin
      L := Default(TLoop);
      L.SymbolId := Q.Fields[Ord(lcSymbolId)].AsLargeInt;
      L.Kind := Q.Fields[Ord(lcKind)].AsString;
      L.StartLine := Q.Fields[Ord(lcStartLine)].AsInteger;
      L.StartCol := Q.Fields[Ord(lcStartCol)].AsInteger;
      L.EndLine := Q.Fields[Ord(lcEndLine)].AsInteger;
      L.EndCol := Q.Fields[Ord(lcEndCol)].AsInteger;
      L.CondStartLine := Q.Fields[Ord(lcCondStartLine)].AsInteger;
      L.CondStartCol := Q.Fields[Ord(lcCondStartCol)].AsInteger;
      L.CondEndLine := Q.Fields[Ord(lcCondEndLine)].AsInteger;
      L.CondEndCol := Q.Fields[Ord(lcCondEndCol)].AsInteger;
      FLoops.Add(L);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

procedure TUnitReader.LoadRefs;
var
  Q: TFDQuery;
  R: TRefInfo;
  Key: Int64;
begin
  { a call and its member-access share one position: the two rows are folded into one answer }
  Q := OpenQuery(FConn,
    'SELECT kind, name_text, start_line, start_col, symbol_id, receiver_text, receiver_type_text FROM refs ' +
    'WHERE file_id = :f AND kind IN (''call'', ''member-access'')', [FFileId]);
  try
    while not Q.Eof do
    begin
      Key := PosKey(Q.Fields[Ord(rcLine)].AsInteger, Q.Fields[Ord(rcCol)].AsInteger);
      if not FRefs.TryGetValue(Key, R) then
        R := Default(TRefInfo);
      R.Name := Q.Fields[Ord(rcName)].AsString;
      if Q.Fields[Ord(rcReceiverText)].AsString <> '' then
        R.ReceiverText := Q.Fields[Ord(rcReceiverText)].AsString;
      if Q.Fields[Ord(rcReceiverType)].AsString <> '' then
        R.ReceiverType := Q.Fields[Ord(rcReceiverType)].AsString;
      if SameText(Q.Fields[Ord(rcKind)].AsString, REF_CALL) and not Q.Fields[Ord(rcSymbolId)].IsNull then
        R.ResolvedCall := True;
      FRefs.AddOrSetValue(Key, R);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

procedure TUnitReader.LoadSymbols;
var
  Q: TFDQuery;
  Id, Name, Qualified: TField;
  S: TSymbolName;
begin
  Q := OpenQuery(FConn, 'SELECT id, name, qualified_name FROM symbols WHERE file_id = :f', [FFileId]);
  try
    Id := Q.FieldByName('id');
    Name := Q.FieldByName('name');
    Qualified := Q.FieldByName('qualified_name');
    while not Q.Eof do
    begin
      S.Name := Name.AsString;
      S.Qualified := Qualified.AsString;
      FSymbols.AddOrSetValue(Id.AsLargeInt, S);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

procedure TUnitReader.LoadDfm(pDfmFileId: Int64);
var
  Q: TFDQuery;
  Obj, Parent, Prop, Val, Depth: TField;
  F: TDfmField;
  Handler, Binding, Bound: string;
begin
  Q := OpenQuery(FConn, 'SELECT name, depth FROM dfm_objects WHERE file_id = :f ORDER BY ordinal', [pDfmFileId]);
  try
    Obj := Q.FieldByName('name');
    Depth := Q.FieldByName('depth');
    while not Q.Eof do
    begin
      if (Depth.AsInteger = 0) and (FRootName = '') then
        FRootName := Obj.AsString;
      FDfmObjects.AddOrSetValue(LowerCase(Obj.AsString), True);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
  Q := OpenQuery(FConn,
    'SELECT o.name AS obj, o.parent_name AS parent, p.name AS prop, p.value_text AS val ' +
    'FROM dfm_properties p JOIN dfm_objects o ON o.file_id = p.file_id AND o.ordinal = p.object_ordinal ' +
    'WHERE p.file_id = :f AND p.depth = 0 AND (p.name = ''FieldName'' OR p.value_kind = ''ident'') ' +
    'ORDER BY p.ordinal', [pDfmFileId]);
  try
    Obj := Q.FieldByName('obj');
    Parent := Q.FieldByName('parent');
    Prop := Q.FieldByName('prop');
    Val := Q.FieldByName('val');
    while not Q.Eof do
    begin
      if SameText(Prop.AsString, 'FieldName') then
      begin
        F.Dataset := Parent.AsString;
        F.FieldName := Val.AsString;
        FDfmFields.AddOrSetValue(LowerCase(Obj.AsString), F);
      end
      else
      begin
        { every identifier-valued property; only the ones naming a routine of the unit are ever looked up }
        Handler := LowerCase(Val.AsString);
        Binding := Obj.AsString + '.' + Prop.AsString;
        if FEvents.TryGetValue(Handler, Bound) then
          Binding := Bound + ', ' + Binding;
        FEvents.AddOrSetValue(Handler, Binding);
      end;
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

{ Source text of a range, as one line: the lines are trimmed and joined with one space. The end column is
  EXCLUSIVE, as in the facts. '' when the range is not inside the file. }
function TUnitReader.TextRange(pStartLine, pStartCol, pEndLine, pEndCol: Integer): string;
var
  L: Integer;
  Part: string;
begin
  Result := '';
  if (pStartLine >= 1) and (pEndLine <= Length(FLines)) then
    for L := pStartLine to pEndLine do
    begin
      Part := FLines[L - 1];
      if L = pEndLine then
        Part := Copy(Part, 1, pEndCol - 1);
      if L = pStartLine then
        Part := Copy(Part, pStartCol, MaxInt);
      Part := Trim(Part);
      if Part <> '' then
        Result := if Result = '' then Part else Result + ' ' + Part;
    end;
end;

{ The statement a position sits in, for display: its line up to the first ';' at or after the position. }
function TUnitReader.StatementAt(pLine, pCol: Integer): string;
var
  P: Integer;
begin
  Result := '';
  if InRange(pLine, 1, Length(FLines)) then
  begin
    Result := FLines[pLine - 1];
    P := PosEx(';', Result, pCol);
    if P > 0 then
      Result := Copy(Result, 1, P);
    Result := Trim(Result);
  end;
end;

{ `Self.tblX` and `<form variable>.tblX` name the unit's own component tblX; anything else stays as written. }
function TUnitReader.LocalName(const pText: string): string;
begin
  Result := pText;
  if StartsText(SELF_PREFIX, Result) then
    Result := Copy(Result, Length(SELF_PREFIX) + 1, MaxInt)
  else if (FRootName <> '') and StartsText(FRootName + '.', Result) then
    Result := Copy(Result, Length(FRootName) + 2, MaxInt);
end;

function TUnitReader.DatasetOf(const pAcc: TAccess; out pWithCount: Integer): string;
begin
  pWithCount := 0;
  Result := LocalName(pAcc.DatasetText);
  if (Result = '') and (pAcc.WithCtx <> '') then
  begin
    Result := pAcc.WithCtx;
    pWithCount := Length(pAcc.WithCtx.Split([WITH_SEP]));
  end;
end;

{ SPEC-LIN DL-2: the loop condition reads D.Eof and the body calls D.Next; or `for .. to D.RecordCount ..`
  with D.Next / D.RecNo := in the body. '' = the loop iterates no dataset the model can name. }
function TUnitReader.IteratedDataset(const pLoop: TLoop): string;
var
  Cond, Tail: string;
  M: TMatch;
begin
  Result := '';
  if not SameText(pLoop.Kind, LOOP_FOR_IN) then
  begin
    Cond := TextRange(pLoop.CondStartLine, pLoop.CondStartCol, pLoop.CondEndLine, pLoop.CondEndCol);
    if SameText(pLoop.Kind, LOOP_FOR) then
    begin
      M := TRegEx.Match(Cond, RX_RECORD_COUNT, [roIgnoreCase]);
      Tail := RX_NEXT_OR_RECNO_TAIL;
    end
    else
    begin
      M := TRegEx.Match(Cond, RX_EOF, [roIgnoreCase]);
      Tail := RX_NEXT_TAIL;
    end;
    if M.Success and TRegEx.IsMatch(TextRange(pLoop.StartLine, pLoop.StartCol, pLoop.EndLine, pLoop.EndCol),
      '\b' + TRegEx.Escape(M.Groups[1].Value) + Tail, [roIgnoreCase]) then
      Result := M.Groups[1].Value;
  end;
end;

{ True when the write is an aggregate: inside a loop over ANOTHER dataset (the innermost such loop wins), or
  after one with an input that reaches it through a local assigned inside that loop. A loop over the written
  field's own dataset (the "fill every row" loop) never counts. }
function TUnitReader.AggregateLoop(const pAcc: TAccess; const pTarget: TLineageField; const pFlows: TList<TFlow>;
  out pLoop: TLoop; out pDataset: string): Boolean;
var
  Lp: TLoop;
  Ds: string;
  F: TFlow;
  Hit, Own: Boolean;
begin
  Result := False;
  pLoop := Default(TLoop);
  pDataset := '';
  for Lp in FLoops do
  begin
    Ds := if Lp.SymbolId = pAcc.SymbolId then IteratedDataset(Lp) else '';
    if Ds = '' then
      Continue;
    { own dataset: by name when it is known, else by the component's name prefix (tblOrders + SEQ) }
    Own := if pTarget.Dataset <> '' then IndexText(LastSegment(Ds), pTarget.Dataset.Split([WITH_SEP])) >= 0
      else (pTarget.Component <> '') and StartsText(LastSegment(Ds), LastSegment(pTarget.Component));
    Hit := not Own and IsInside(pAcc.Line, pAcc.Col, Lp);
    if not Own and not Hit and IsBefore(Lp.EndLine, Lp.EndCol, pAcc.Line, pAcc.Col) and (pFlows <> nil) then
      for F in pFlows do
        if F.ViaLocal and (F.SrcLine > 0) and IsInside(F.SrcLine, F.SrcCol, Lp) then
          Hit := True;
    if Hit then
    begin
      Result := True;
      pLoop := Lp;
      pDataset := Ds;
    end;
  end;
end;

{ A positioned source that is no by-name access: a call, or a member read such as tblOrdersQTY.AsFloat. }
procedure TUnitReader.AddRefSource(const pFlow: TFlow; const pTargetKey: string; pSeen: TDictionary<string, Boolean>;
  var pWrite: TLineageWrite);
var
  R: TRefInfo;
  Receiver: string;
  F: TDfmField;
begin
  if not FRefs.TryGetValue(PosKey(pFlow.SrcLine, pFlow.SrcCol), R) then
    Exit;
  Receiver := LocalName(R.ReceiverText);
  if R.ResolvedCall then
    AddReason(pWrite.Unknown, Format(LINEAGE_REASON_CALL_FMT, [R.Name]))
  else if MatchText(R.Name, ['Lookup', 'VarArrayOf']) then
    AddReason(pWrite.Unknown, LINEAGE_REASON_VARIANT)
  else if FDfmFields.TryGetValue(LowerCase(Receiver), F) then
  begin
    pSeen.AddOrSetValue(LowerCase(Receiver), True);
    AddInput(pWrite, pTargetKey, F.Dataset, F.FieldName, Receiver, pFlow);
  end
  else if EndsText(TYPE_FIELD_TAIL, R.ReceiverType) and TRegEx.IsMatch(Receiver, RX_IDENT_CHAIN) then
  begin
    { a field component the unit's DFM does not declare: another module's, or an ancestor form's }
    pSeen.AddOrSetValue(LowerCase(Receiver), True);
    AddInput(pWrite, pTargetKey, '', '', Receiver, pFlow);
  end;
end;

{ A by-name / Fields[] / field-object read (B14-3). }
procedure TUnitReader.AddDsFieldSource(const pFlow: TFlow; const pTargetKey: string; var pWrite: TLineageWrite);
var
  Idx, WithCount: Integer;
  R: TAccess;
  Ds: string;
begin
  if not FAccByPos.TryGetValue(PosKey(pFlow.SrcLine, pFlow.SrcCol), Idx) then
  begin
    if pFlow.SrcName <> '' then
      AddInput(pWrite, pTargetKey, '', pFlow.SrcName, '', pFlow);
    Exit;
  end;
  R := FAccesses[Idx];
  if SameText(R.Shape, SHAPE_ACCESSOR) then
  begin
    { a field OBJECT in a parameter; one in a local carries its name on the FieldByName row that filled it }
    if SameText(R.RootKind, ROOT_PARAM) then
      AddReason(pWrite.Unknown, Format(LINEAGE_REASON_PARAM_FMT, [R.RootName]));
  end
  else if not SameText(R.NameKind, NAME_LITERAL) then
    AddReason(pWrite.Unknown, LINEAGE_REASON_RUNTIME_NAME)
  else
  begin
    Ds := DatasetOf(R, WithCount);
    if WithCount > 1 then
      AddReason(pWrite.Unknown, Format(LINEAGE_REASON_WITH_FMT, [WithCount]))
    else
      AddInput(pWrite, pTargetKey, Ds, R.FieldName, '', pFlow);
  end;
end;

{ An unpositioned class-field source: a field component (the twin of a 'ref' already taken), another DFM
  component (a control: no field input), or a plain class field (not followed, DL-1 A). }
procedure TUnitReader.AddFieldSource(const pFlow: TFlow; const pTargetKey: string; pSeen: TDictionary<string, Boolean>;
  var pWrite: TLineageWrite);
var
  Name: string;
  F: TDfmField;
begin
  Name := LowerCase(pFlow.SrcName);
  if FDfmFields.TryGetValue(Name, F) then
    AddInput(pWrite, pTargetKey, F.Dataset, F.FieldName, pFlow.SrcName, pFlow)
  else if not FDfmObjects.ContainsKey(Name) and not pSeen.ContainsKey(Name) then
    AddReason(pWrite.Unknown, Format(LINEAGE_REASON_FIELD_FMT, [pFlow.SrcName]));
end;

procedure TUnitReader.AddVia(const pFlow: TFlow; const pAcc: TAccess; var pWrite: TLineageWrite);
var
  Text: string;
begin
  if pFlow.ViaLocal and (pFlow.SrcLine > 0) and
    ((pFlow.SrcLine < pAcc.StmtLine) or (pFlow.SrcLine > pAcc.RhsEndLine)) then
  begin
    Text := Format('%s  (line %d)', [StatementAt(pFlow.SrcLine, pFlow.SrcCol), pFlow.SrcLine]);
    if IndexStr(Text, pWrite.Via) < 0 then
    begin
      if Length(pWrite.Via) < LINEAGE_VIA_MAX then
        pWrite.Via := pWrite.Via + [Text]
      else if Length(pWrite.Via) = LINEAGE_VIA_MAX then
        pWrite.Via := pWrite.Via + [VIA_MORE];
    end;
  end;
end;

function TUnitReader.BuildWrite(const pAcc: TAccess; const pTarget: TLineageField; pWithCount: Integer): TLineageWrite;
var
  Flows: TList<TFlow>;
  F: TFlow;
  Sym: TSymbolName;
  Seen: TDictionary<string, Boolean>;
  TargetKey: string;
  Lp: TLoop;
begin
  Result := Default(TLineageWrite);
  Result.Line := pAcc.Line;
  Result.Col := pAcc.Col;
  if FSymbols.TryGetValue(pAcc.SymbolId, Sym) then
  begin
    Result.Routine := Sym.Qualified;
    FEvents.TryGetValue(LowerCase(Sym.Name), Result.Event);
  end;
  Result.ExprText := TextRange(pAcc.StmtLine, pAcc.StmtCol, pAcc.RhsEndLine, pAcc.RhsEndCol) + ';';
  if Length(Result.ExprText) > LINEAGE_EXPR_MAX then
    Result.ExprText := Copy(Result.ExprText, 1, LINEAGE_EXPR_MAX) + LINEAGE_EXPR_CUT;
  if pWithCount > 1 then
    AddReason(Result.Unknown, Format(LINEAGE_REASON_WITH_FMT, [pWithCount]));
  if FCapped.ContainsKey(pAcc.SymbolId) then
    AddReason(Result.Unknown, LINEAGE_REASON_ROW_CAP);
  TargetKey := FieldKey(pTarget.Dataset, pTarget.FieldName, pTarget.Component);
  if not FFlows.TryGetValue(PosKey(pAcc.Line, pAcc.Col), Flows) then
    Flows := nil;
  Seen := TDictionary<string, Boolean>.Create;
  try
    if Flows <> nil then
      for F in Flows do
      begin
        if SameText(F.SrcKind, SRC_DSFIELD) then
          AddDsFieldSource(F, TargetKey, Result)
        else if SameText(F.SrcKind, SRC_REF) then
          AddRefSource(F, TargetKey, Seen, Result)
        else if SameText(F.SrcKind, SRC_FIELD) then
          AddFieldSource(F, TargetKey, Seen, Result)
        else if SameText(F.SrcKind, SRC_PARAM) then
          AddReason(Result.Unknown, Format(LINEAGE_REASON_PARAM_FMT, [F.SrcName]))
        else if SameText(F.SrcKind, SRC_GLOBAL) then
          AddReason(Result.Unknown, Format(LINEAGE_REASON_GLOBAL_FMT, [F.SrcName]))
        else if SameText(F.SrcKind, SRC_ARGOUT) then
          AddReason(Result.Unknown, Format(LINEAGE_REASON_CALL_FMT, [F.SrcName]));
        AddVia(F, pAcc, Result);
      end;
  finally
    Seen.Free;
  end;
  if Length(Result.Inputs) = 0 then
    Result.Kind := if Length(Result.Unknown) > 0 then LINEAGE_KIND_UNKNOWN else LINEAGE_KIND_NONE
  else if AggregateLoop(pAcc, pTarget, Flows, Lp, Result.LoopDataset) then
  begin
    Result.Kind := LINEAGE_KIND_AGGREGATE;
    Result.LoopText := Lp.Kind + ' ' +
      TextRange(Lp.CondStartLine, Lp.CondStartCol, Lp.CondEndLine, Lp.CondEndCol);
  end
  else
    Result.Kind := LINEAGE_KIND_DIRECT;
end;

procedure TUnitReader.ProcessWrite(const pAcc: TAccess);
var
  Target: TLineageField;
  F: TDfmField;
  Rt: TLineageRuntimeWrite;
  Sym: TSymbolName;
  WithCount, Idx: Integer;
  Key: string;
  W: TLineageWrite;
begin
  Target := Default(TLineageField);
  WithCount := 0;
  if SameText(pAcc.Shape, SHAPE_ACCESSOR) then
  begin
    Target.Component := LocalName(pAcc.FieldText);
    if FDfmFields.TryGetValue(LowerCase(Target.Component), F) then
    begin
      Target.Dataset := F.Dataset;
      Target.FieldName := F.FieldName;
    end;
  end
  else
  begin
    Target.Dataset := DatasetOf(pAcc, WithCount);
    Target.FieldName := pAcc.FieldName;
  end;
  if not SameText(pAcc.Shape, SHAPE_ACCESSOR) and not SameText(pAcc.NameKind, NAME_LITERAL) then
  begin
    { a name built at run time marks no named field: reported once per write, on the dataset }
    Rt := Default(TLineageRuntimeWrite);
    Rt.Dataset := Target.Dataset;
    Rt.NameText := pAcc.NameText;
    Rt.Line := pAcc.Line;
    if FSymbols.TryGetValue(pAcc.SymbolId, Sym) then
      Rt.Routine := Sym.Qualified;
    FRuntime.Add(Rt);
    Exit;
  end;
  Key := FieldKey(Target.Dataset, Target.FieldName, Target.Component);
  if FFieldIndex.TryGetValue(Key, Idx) then
    Target := FFields[Idx]
  else
  begin
    Idx := FFields.Add(Target);
    FFieldIndex.Add(Key, Idx);
  end;
  if (Target.Component = '') and SameText(pAcc.Shape, SHAPE_ACCESSOR) then
    Target.Component := LocalName(pAcc.FieldText);
  W := BuildWrite(pAcc, Target, WithCount);
  if W.Kind = LINEAGE_KIND_NONE then
    Inc(Target.WritesWithoutFieldInput)
  else
    Target.Writes := Target.Writes + [W];
  FFields[Idx] := Target;
end;

procedure TUnitReader.Summarise(var pField: TLineageField);
var
  W: TLineageWrite;
  Input: TLineageInput;
  Reason: string;
  Rank, Best: Integer;
begin
  Best := 0;
  for W in pField.Writes do
  begin
    for Input in W.Inputs do
      AddInputTo(pField.Inputs, Input);
    for Reason in W.Unknown do
      AddReason(pField.Unknown, Reason);
    Rank := IndexStr(W.Kind, [LINEAGE_KIND_NONE, LINEAGE_KIND_UNKNOWN, LINEAGE_KIND_DIRECT, LINEAGE_KIND_AGGREGATE]);
    if Rank > Best then
    begin
      Best := Rank;
      pField.Kind := W.Kind;
    end;
  end;
  pField.Derived := Length(pField.Writes) > 0;
end;

procedure TUnitReader.Run(var pUnit: TLineageUnit);
var
  A: TAccess;
  I: Integer;
  Field: TLineageField;
begin
  for A in FAccesses do
    { Clear and Assign write no computed value; a write row without a right-hand side has nothing to trace }
    if A.IsWrite and (A.RhsStartLine > 0) and not MatchText(A.Accessor, ['Clear', 'Assign']) then
      ProcessWrite(A);
  for I := 0 to FFields.Count - 1 do
  begin
    Field := FFields[I];
    Summarise(Field);
    FFields[I] := Field;
  end;
  pUnit.Fields := FFields.ToArray;
  pUnit.RuntimeNameWrites := FRuntime.ToArray;
end;

{ ---------------------------------------------------------------------------------------------- TFieldLineageModel }

constructor TFieldLineageModel.Create(const pIndexDb: string);
var
  Q: TFDQuery;
  Tables: Integer;
begin
  inherited Create;
  FCache := TDictionary<string, TLineageUnit>.Create;
  if not TFile.Exists(pIndexDb) then
    raise ELineageError.CreateFmt('lineage: no index at %s', [pIndexDb]);
  FConn := TFDConnection.Create(nil);
  try
    { the engine's one reader open: never creates, never converts the journal mode, query_only }
    ConnectReadOnly(FConn, pIndexDb);
    Q := OpenQuery(FConn, 'SELECT COUNT(*) AS n FROM sqlite_master WHERE type = ''table'' AND ' +
      'name IN (''ds_field_accesses'', ''loop_facts'')', []);
    try
      Tables := Q.FieldByName('n').AsInteger;
    finally
      Q.Free;
    end;
  except
    on E: EDatabaseError do
      raise ELineageError.CreateFmt('lineage: the index %s does not open: %s', [pIndexDb, E.Message]);
  end;
  if Tables < B14_TABLE_COUNT then
    raise ELineageError.CreateFmt(
      'lineage: the index %s has no field lineage facts (re-index it with drag-lint 1.56 or later)', [pIndexDb]);
end;

destructor TFieldLineageModel.Destroy;
begin
  FConn.Free;
  FCache.Free;
  inherited;
end;

function TFieldLineageModel.FileIdOf(const pPath: string; out pSha: string): Int64;
var
  Q: TFDQuery;
begin
  Result := 0;
  pSha := '';
  Q := OpenQuery(FConn, 'SELECT id, sha256 FROM files WHERE path = :p COLLATE NOCASE', [pPath]);
  try
    if not Q.Eof then
    begin
      Result := Q.FieldByName('id').AsLargeInt;
      pSha := Q.FieldByName('sha256').AsString;
    end;
  finally
    Q.Free;
  end;
end;

function TFieldLineageModel.ReadUnit(const pUnitPath: string): TLineageUnit;
var
  FileId: Int64;
  Sha, DfmSha: string;
  Reader: TUnitReader;
begin
  if FCache.TryGetValue(LowerCase(pUnitPath), Result) then
    Exit;
  Result := Default(TLineageUnit);
  Result.UnitPath := pUnitPath;
  FileId := FileIdOf(pUnitPath, Sha);
  Result.Indexed := FileId > 0;
  if Result.Indexed then
  begin
    Result.Stale := not TFile.Exists(pUnitPath) or
      not SameText(THashSHA2.GetHashStringFromFile(pUnitPath), Sha);
    if Result.Stale then
      Result.StaleReason := Format(LINEAGE_REASON_STALE_FMT, [TPath.GetFileNameWithoutExtension(pUnitPath)])
    else
    begin
      Reader := TUnitReader.Create(FConn, FileId, FileIdOf(ChangeFileExt(pUnitPath, EXT_DFM), DfmSha),
        TFile.ReadAllLines(pUnitPath));
      try
        Reader.Run(Result);
      finally
        Reader.Free;
      end;
    end;
  end;
  FCache.AddOrSetValue(LowerCase(pUnitPath), Result);
end;

function TFieldLineageModel.FieldLineage(const pUnitPath, pDataset, pFieldName: string): TLineageField;
var
  U: TLineageUnit;
begin
  U := ReadUnit(pUnitPath);
  U.Find(pDataset, pFieldName, Result);
  if U.Stale then
    Result.Unknown := [U.StaleReason];
end;

function TFieldLineageModel.ExternalWriters(const pUnitPath, pComponent: string): TArray<string>;
var
  FileId, DfmId: Int64;
  Sha, Root, Text, Qualifier: string;
  Q: TFDQuery;
  Routine, FieldText: TField;
begin
  Result := nil;
  FileId := FileIdOf(pUnitPath, Sha);
  DfmId := FileIdOf(ChangeFileExt(pUnitPath, EXT_DFM), Sha);
  Root := '';
  if DfmId > 0 then
  begin
    Q := OpenQuery(FConn, 'SELECT name FROM dfm_objects WHERE file_id = :f AND depth = 0 ORDER BY ordinal', [DfmId]);
    try
      if not Q.Eof then
        Root := Q.FieldByName('name').AsString;
    finally
      Q.Free;
    end;
  end;
  Q := OpenQuery(FConn,
    'SELECT DISTINCT s.qualified_name AS routine, a.field_text AS ft FROM ds_field_accesses a ' +
    'JOIN symbols s ON s.id = a.symbol_id WHERE a.mode = ''write'' AND a.shape = ''accessor'' AND ' +
    'a.file_id <> :f AND a.field_text LIKE :pat ORDER BY s.qualified_name', [FileId, '%.' + pComponent]);
  try
    Routine := Q.FieldByName('routine');
    FieldText := Q.FieldByName('ft');
    while not Q.Eof do
    begin
      Text := FieldText.AsString;
      Qualifier := Copy(Text, 1, Length(Text) - Length(pComponent) - 1);
      { LIKE also takes '_' as a wildcard: the tail is compared again, exactly }
      if EndsText('.' + pComponent, Text) and ((Root = '') or SameText(LastSegment(Qualifier), Root)) and
        (IndexStr(Routine.AsString, Result) < 0) then
        Result := Result + [Routine.AsString];
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

end.
