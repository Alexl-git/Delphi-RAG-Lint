unit DRagLint.Index.IndirectCalls;

/// <summary>1.56 B5 (lane EXT-C2): derives indirect_edges -- "this call through a method pointer /
/// event CAN run that routine" -- the edges the calls stage cannot express, because the callee of
/// `FOnChange(Self)` is a VALUE, not a name.</summary>
/// <remarks>
/// DERIVED from rows the parse and the calls stage already wrote (refs, symbols, member_accesses,
/// call_edges, type_ancestors, unit_uses, dfm_objects, dfm_properties) plus the source line of each
/// binding site. The pass only READS; ISymbolStore.ReplaceIndirectEdges replaces the table with
/// the rows it returns. It is installed through TIndexPassHooks.RegisterIndirectEdges from this
/// unit's initialization and run by TSQLiteSymbolStore.ResolveDispatch after dispatch_edges and
/// classref_args are committed.
///
/// A BINDING is one of
///   `Slot:= Routine` / `Slot:= @Routine`   (field, variable, parameter: IE_KIND_METHOD_POINTER;
///                                           property: IE_KIND_EVENT),
///   `Callee(.., Routine, ..)`               (the slot is the callee's parameter at that position:
///                                           IE_KIND_CALLBACK_ARG),
///   `OnClick = Button1Click` in a .dfm      (IE_KIND_DFM_EVENT; the target is the method of the
///                                           form class, the slot the event property of the
///                                           component's class when that class is in the index),
/// and every binding of a slot is paired with every CALL through that slot (`Slot(..)`): the fact
/// is flow- and instance-INSENSITIVE ("can run", never "does run"). A binding whose slot has no
/// call in this index (a library event such as TButton.OnClick, a slot that is only stored) still
/// yields ONE row with RefId = 0 and CallerId = 0, so "is this routine reachable through a
/// pointer" has an answer.
///
/// Not followed (declined, never guessed): a slot copied into another slot (`FA:= FB`,
/// `FOnX:= AParam`), a setter method behind an event property, anonymous methods, `with` scopes,
/// an assignment or argument list that spans more than one line.
/// </remarks>

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  FireDAC.Comp.Client,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces;

type
  /// <summary>Rows written, by kind, and every decline, by reason.</summary>
  TIndirectCounters = record
    /// <summary>indirect_edges rows of kind IE_KIND_METHOD_POINTER.</summary>
    MethodPointer: Integer;
    /// <summary>indirect_edges rows of kind IE_KIND_EVENT.</summary>
    Event        : Integer;
    /// <summary>indirect_edges rows of kind IE_KIND_DFM_EVENT.</summary>
    DfmEvent     : Integer;
    /// <summary>indirect_edges rows of kind IE_KIND_CALLBACK_ARG.</summary>
    CallbackArg  : Integer;
    /// <summary>Binding sites accepted (one site can yield several rows).</summary>
    Binds        : Integer;
    /// <summary>Accepted bindings whose slot is never called in this index (a RefId = 0 row).</summary>
    NoSite       : Integer;
    /// <summary>A routine name on the right-hand side that could be a paren-less CALL: the routine
    /// returns a value, there is no `@`, and the slot's type is not known to be procedural.</summary>
    Unproven     : Integer;
    /// <summary>A site whose left-hand side or argument list could not be read on its line.</summary>
    Unread       : Integer;
    /// <summary>A site in a file changed since it was indexed.</summary>
    Stale        : Integer;
  end;

  /// <summary>Builds the indirect_edges rows of one index in memory.</summary>
  /// <remarks>Maps are built once per Run. Not thread-safe. Owns nothing it is given: AStore,
  /// AConn and the connections of AExtraConns must outlive the instance. AConn must be the
  /// connection of AStore.</remarks>
  TIndirectCallResolver = class  // dl:ok high-response@738b -- the response set is the FireDAC / dictionary calls of one pass sharing its symbol, line and call-site caches
  strict private
    type
      { One symbols row, the columns the pass reads. }
      TSymInfo = record
        Id       : Int64;
        FileId   : Int64;
        ParentId : Int64;
        Kind     : string;
        Name     : string;
        Signature: string;
        Section  : string;
        Line     : Integer;
        EndLine  : Integer;
      end;
      { One ref of the file being read, by position. }
      TFileRef = record
        Id        : Int64;
        Kind      : string;
        SymbolId  : Int64;
        MemberId  : Int64; // member_accesses.member_symbol_id
        AccessorId: Int64; // member_accesses.accessor_symbol_id
      end;
      { A routine name read WITHOUT being called: the candidates of the pass. }
      TCandidate = record
        FileId  : Int64;
        Line    : Integer;
        Col     : Integer;
        Name    : string;
        TargetId: Int64;
      end;
      { An accepted binding site. }
      TBind = record
        SlotId  : Int64;  // the slot called through; 0 = not a symbol of this index
        TargetId: Int64;
        Kind    : string;
        Via     : string;
        FileId  : Int64;
        Line    : Integer;
        Col     : Integer;
        ByName  : Boolean;
      end;
      { A call ref `Name(..)` whose name is a slot, with the symbol the name means there. }
      TCallSite = record
        RefId   : Int64;
        CallerId: Int64;
        SlotId  : Int64;   // 0 = the name does not resolve to a symbol of this index
        ByName  : Boolean; // resolved across units by name only
      end;
    var
      FStore     : ISymbolStore;
      FConn      : TFDConnection;
      FExtraConns: TArray<TFDConnection>;
      FQueries   : TObjectDictionary<string, TFDQuery>;
      FSyms      : TDictionary<Int64, TSymInfo>;
      FLines     : TDictionary<Int64, TArray<string>>;
      FStaleFiles: TDictionary<Int64, Boolean>;
      FProcTypes : TDictionary<string, Boolean>;
      FRefFile   : Int64;
      FFileRefs  : TDictionary<Int64, TFileRef>;
      FCallsByName: TObjectDictionary<string, TList<TCallSite>>;
      FBinds     : TList<TBind>;
      FEdges     : TList<TIndirectEdgeRow>;
      FEdgeKeys  : TDictionary<string, Boolean>;
      FCounters  : TIndirectCounters;
      FHasMemberAccesses: Boolean;
      FHasDfmProperties : Boolean;
    function Query(const ASql: string): TFDQuery;
    function FirstId(AQuery: TFDQuery): Int64;
    function TableExists(const AName: string): Boolean;
    function Sym(AId: Int64): TSymInfo;
    function LinesOf(AFileId: Int64): TArray<string>;
    function IsProceduralType(const ATypeText: string; ADepth: Integer = 0): Boolean;
    function ProceduralInConn(AConn: TFDConnection; const AName: string; ADepth: Integer; out AFound: Boolean): Boolean;
    function RoutineHasResult(const ARoutine: TSymInfo): Boolean;
    function FileRefAt(AFileId: Int64; ALine, ACol: Integer; out ARef: TFileRef): Boolean;
    function FieldOfProperty(const AProp: TSymInfo): Int64;
    function CanonicalSlot(const ALhs: TFileRef; out AIsProperty: Boolean): Int64;
    function LocalNamed(ARoutineId: Int64; const AName: string): Int64;
    function MemberNamed(AClassId: Int64; const AName: string): Int64;
    function AncestorOf(AClassId: Int64): Int64;
    function ResolveName(AEnclosingId, AFileId: Int64; const AName: string; out AByName: Boolean): Int64;
    function CallsNamed(const AName: string): TList<TCallSite>;
    procedure SlotAliases(ASlotId: Int64; AIds: TList<Int64>; ANames: TList<string>);
    procedure LoadCandidates(ACands: TList<TCandidate>);
    procedure BindAssignment(const ACand: TCandidate; const ALine: string; AAssignAt: Integer; AHasAt: Boolean);
    procedure BindArgument(const ACand: TCandidate; const ALine: string; AArgAt: Integer; AHasAt: Boolean);
    procedure CollectBinds;
    function ClassNamed(const AName, APreferPath: string; out AByName: Boolean): Int64;
    function RoutineInChain(AClassId: Int64; const AName: string): Int64;
    function SlotOfComponentEvent(const AClassName, APropName: string): Int64;
    procedure CollectDfmBinds;
    procedure AddBind(const ABind: TBind);
    procedure AddEdge(const ABind: TBind; const ASite: TCallSite);
    procedure EmitBinds;
    function GetEdges: TArray<TIndirectEdgeRow>;
  public
    /// <summary>Binds the pass to one index.</summary>
    /// <param name="AStore">The project store; used for file paths and the staleness probe.</param>
    /// <param name="AConn">The connection of AStore; read only by this class.</param>
    /// <param name="AExtraConns">Connections of the library indexes of the run (procedural TYPE
    /// names declared outside the project are looked up there); may be nil.</param>
    constructor Create(const AStore: ISymbolStore; AConn: TFDConnection; const AExtraConns: TArray<TFDConnection>);
    /// <summary>Frees the caches; the store and the connections are not owned.</summary>
    destructor Destroy; override;
    /// <summary>Computes every row. Re-runnable: each call starts from empty results.</summary>
    /// <exception cref="EFDDBEngineException">A read of the index failed.</exception>
    procedure Run;
    /// <summary>The rows of the last Run, in the order they were derived (binding site order).</summary>
    property Edges: TArray<TIndirectEdgeRow> read GetEdges;
    /// <summary>Row and decline counts of the last Run.</summary>
    property Counters: TIndirectCounters read FCounters;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Hash,
  Data.DB,
  FireDAC.Stan.Param,
  DRagLint.Core.FileTime,
  DRagLint.Storage.SQLite; { TSQLiteSymbolStore.GetConnection -- the hook is handed the store only }

const
  CHAIN_MAX_DEPTH    = 64; // a deeper class / alias chain is a cycle in bad data
  ALIAS_MAX_DEPTH    = 4;  // `TMyEvent = TNotifyEvent` hops followed when typing a slot
  POS_COL_BITS       = 20; // FFileRefs key = line shl POS_COL_BITS or col
  INDIRECT_LOG_ENV   = 'DRAGLINT_INDIRECT_LOG';
  KIND_FIELD         = 'field';
  KIND_PROPERTY      = 'property';
  KIND_VAR           = 'var';
  KIND_LOCAL         = 'local_var';
  KIND_PARAM         = 'param';
  KIND_METHOD        = 'method';
  KIND_PROCEDURE     = 'procedure';
  KIND_FUNCTION      = 'function';
  KIND_CLASS         = 'class';
  KIND_CONSTRUCTOR   = 'constructor';
  KIND_DESTRUCTOR    = 'destructor';
  REF_MEMBER_ACCESS  = 'member-access';
  TABLE_MEMBER_ACCESSES = 'member_accesses';
  TABLE_DFM_PROPERTIES  = 'dfm_properties';
  TABLE_DFM_OBJECTS     = 'dfm_objects';
  PAS_EXT               = '.pas';
  QUOTE                 = '''';
  KIND_RECORD        = 'record';
  EVENT_PREFIX       = 'On'; // an unresolved bare left-hand side named On* is taken as an event
  SQL_SYMBOL =
    'SELECT file_id, parent_id, kind, name, signature, section, start_line, end_line FROM symbols WHERE id = :i';
  { Every routine name that is READ, not called: an address-of, or a paren-less call. }
  SQL_CANDIDATES =
    'SELECT r.file_id, r.start_line, r.start_col, r.name_text, s.id AS target_id FROM symbols s ' +
    'JOIN refs r ON r.symbol_id = s.id ' +
    'WHERE s.kind IN (''method'', ''procedure'', ''function'') AND r.kind = ''read'' ' +
    'ORDER BY r.file_id, r.start_line, r.start_col';
  SQL_FILE_REFS_MA =
    'SELECT r.id, r.kind, r.symbol_id, r.start_line, r.start_col, m.member_symbol_id, m.accessor_symbol_id ' +
    'FROM refs r LEFT JOIN member_accesses m ON m.ref_id = r.id ' +
    'WHERE r.file_id = :f AND r.kind IN (''write'', ''member-access'', ''call'') ORDER BY r.id';
  SQL_FILE_REFS =
    'SELECT r.id, r.kind, r.symbol_id, r.start_line, r.start_col, NULL AS member_symbol_id, NULL AS accessor_symbol_id ' +
    'FROM refs r WHERE r.file_id = :f AND r.kind IN (''write'', ''member-access'', ''call'') ORDER BY r.id';
  SQL_PROP_FIELD =
    'SELECT r.symbol_id FROM refs r JOIN symbols f ON f.id = r.symbol_id ' +
    'WHERE r.file_id = :f AND r.kind = ''property-spec'' AND r.start_line BETWEEN :a AND :b AND f.kind = ''field'' ' +
    'ORDER BY r.id';
  SQL_FIELD_PROPS =
    'SELECT p.id, p.name FROM refs r JOIN symbols p ON p.file_id = r.file_id AND p.kind = ''property'' ' +
    'AND r.start_line BETWEEN p.start_line AND p.end_line ' +
    'WHERE r.symbol_id = :s AND r.kind = ''property-spec'' AND p.parent_id = :c ORDER BY p.id';
  SQL_LOCAL_NAMED =
    'SELECT id FROM symbols WHERE parent_id = :p AND name = :n COLLATE NOCASE AND kind IN (''param'', ''local_var'') ' +
    'ORDER BY id';
  SQL_MEMBER_NAMED =
    'SELECT id FROM symbols WHERE parent_id = :p AND name = :n COLLATE NOCASE ORDER BY id';
  SQL_ANCESTOR =
    'SELECT ancestor_symbol_id FROM type_ancestors WHERE symbol_id = :s AND ancestor_symbol_id IS NOT NULL ORDER BY ordinal';
  SQL_UNIT_LEVEL =
    'SELECT s.id FROM symbols s JOIN symbols u ON u.id = s.parent_id ' +
    'WHERE s.file_id = :f AND s.name = :n COLLATE NOCASE AND u.parent_id IS NULL ORDER BY s.id';
  SQL_USED_VARS =
    'SELECT s.id FROM symbols s JOIN symbols u ON u.id = s.parent_id ' +
    'WHERE s.name = :n COLLATE NOCASE AND s.kind = ''var'' AND s.section = ''interface'' AND u.parent_id IS NULL ' +
    'AND s.file_id IN (SELECT target_file_id FROM unit_uses WHERE file_id = :f AND target_file_id IS NOT NULL) ' +
    'ORDER BY s.id';
  SQL_CALLS_NAMED =
    'SELECT id, file_id, symbol_id, enclosing_symbol_id FROM refs ' +
    'WHERE name_text = :n COLLATE NOCASE AND kind = ''call'' ORDER BY id';
  SQL_TYPE_NAMED =
    'SELECT signature FROM symbols WHERE name = :n COLLATE NOCASE AND kind = ''type'' ORDER BY id';
  SQL_CALL_TARGET =
    'SELECT target_symbol_id FROM call_edges WHERE ref_id = :r';
  SQL_PARAM_AT =
    'SELECT id FROM symbols WHERE parent_id = :p AND kind = ''param'' ORDER BY id LIMIT 1 OFFSET :o';
  { Every handler a .dfm names: the parser's event-binding refs. }
  SQL_DFM_EVENTS =
    'SELECT r.file_id, r.start_line, r.start_col, r.name_text FROM files f JOIN refs r ON r.file_id = f.id ' +
    'WHERE f.language = ''dfm'' AND r.kind = ''event-binding'' ORDER BY r.file_id, r.start_line, r.start_col';
  { The root object of a .dfm: its symbol carries the form class name as signature. }
  SQL_DFM_ROOT =
    'SELECT signature FROM symbols WHERE file_id = :f AND parent_id IS NULL ORDER BY id';
  SQL_DFM_PROPERTY =
    'SELECT o.name, p.name, o.class_name FROM dfm_properties p ' +
    'LEFT JOIN dfm_objects o ON o.file_id = p.file_id AND o.ordinal = p.object_ordinal ' +
    'WHERE p.file_id = :f AND p.start_line = :l AND p.value_text = :v COLLATE NOCASE ORDER BY p.ordinal';
  SQL_CLASS_NAMED =
    'SELECT s.id, f.path FROM symbols s JOIN files f ON f.id = s.file_id ' +
    'WHERE s.name = :n COLLATE NOCASE AND s.kind = ''class'' ORDER BY s.id';
  SQL_ROUTINE_NAMED =
    'SELECT id FROM symbols WHERE parent_id = :p AND name = :n COLLATE NOCASE ' +
    'AND kind IN (''method'', ''procedure'', ''function'') ORDER BY id';
  SQL_TABLE =
    'SELECT 1 FROM sqlite_master WHERE type = ''table'' AND name = :n';

  { Callees whose argument is an address being TESTED or converted, never a callback handed over. }
  NOT_A_CALLBACK_TAKER: array[0..5] of string = ('assigned', 'addr', 'pointer', 'tmethod', 'sizeof', 'typeinfo');

type
  { What stands around a routine name that is read without being called. }
  TSiteShape = (ssNone, ssAssign, ssArgument);

function IsIdentChar(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

function IsBlank(C: Char): Boolean;
begin
  Result:= CharInSet(C, [' ', #9]);
end;

{ True for the symbol kinds that own parameters and locals. }
function IsRoutineKind(const AKind: string): Boolean;
begin
  Result:= (AKind = KIND_METHOD) or (AKind = KIND_PROCEDURE) or (AKind = KIND_FUNCTION) or
           (AKind = KIND_CONSTRUCTOR) or (AKind = KIND_DESTRUCTOR);
end;

{ The index of the last non-blank character at or before AFrom; 0 when there is none. }
function SkipBlanksBack(const S: string; AFrom: Integer): Integer;
begin
  Result:= AFrom;
  while (Result >= 1) and IsBlank(S[Result]) do Dec(Result);
  if Result < 0 then Result:= 0;
end;

{ True when the text from AFrom on is the word AWord followed by a non-identifier character. }
function WordAt(const S: string; AFrom: Integer; const AWord: string): Boolean;
var
  After: Integer;
begin
  After:= AFrom + Length(AWord);
  Result:= SameText(Copy(S, AFrom, Length(AWord)), AWord) and ((After > Length(S)) or not IsIdentChar(S[After]));
end;

{ True when nothing of the statement follows position AFrom: end of line, `;`, a comment, or the
  keyword that closes the statement. }
function StatementEndsAt(const S: string; AFrom: Integer): Boolean;
var
  I: Integer;
begin
  I:= AFrom;
  while (I <= Length(S)) and IsBlank(S[I]) do Inc(I);
  if I > Length(S) then Exit(True);
  if (S[I] = ';') or (S[I] = '{') then Exit(True);
  if (I < Length(S)) and (((S[I] = '/') and (S[I + 1] = '/')) or ((S[I] = '(') and (S[I + 1] = '*'))) then Exit(True);
  Result:= WordAt(S, I, 'else') or WordAt(S, I, 'end') or WordAt(S, I, 'until');
end;

{ Classifies the surroundings of the routine name at [ACol, ACol + ANameLen) on line S.
  ssAssign: `<lhs> := [@][Qual.]Name <end of statement>`, AAt = index of the ':' of `:=`.
  ssArgument: `( | , [@][Qual.]Name ) | ,`, AAt = index of that opening '(' or ','. }
function ClassifySite(const S: string; ACol, ANameLen: Integer; out AHasAt: Boolean; out AAt: Integer): TSiteShape;
var
  J, After: Integer;
  Qualified: Boolean;
begin
  Result:= ssNone;
  AHasAt:= False;
  AAt   := 0;
  J:= SkipBlanksBack(S, ACol - 1);
  { the qualifier chain: Self.Name, Obj.Name, Unit.TType.Name }
  Qualified:= True;
  while Qualified and (J >= 1) and (S[J] = '.') do
  begin
    J:= SkipBlanksBack(S, J - 1);
    Qualified:= (J >= 1) and IsIdentChar(S[J]);
    while (J >= 1) and IsIdentChar(S[J]) do Dec(J);
    J:= SkipBlanksBack(S, J);
  end;
  if not Qualified then Exit; // a qualifier that is not a name: Foo(X).Handler
  if (J >= 1) and (S[J] = '@') then
  begin
    AHasAt:= True;
    J:= SkipBlanksBack(S, J - 1);
  end;
  After:= ACol + ANameLen;
  if (J >= 2) and (S[J] = '=') and (S[J - 1] = ':') then
  begin
    if StatementEndsAt(S, After) then
    begin
      AAt:= J - 1;
      Result:= ssAssign;
    end;
  end
  else if (J >= 1) and ((S[J] = '(') or (S[J] = ',')) then
  begin
    while (After <= Length(S)) and IsBlank(S[After]) do Inc(After);
    if (After <= Length(S)) and ((S[After] = ')') or (S[After] = ',')) then
    begin
      AAt:= J;
      Result:= ssArgument;
    end;
  end;
end;

{ The base name of a type text: generic arguments and a unit qualifier removed. }
function BareTypeName(const ATypeText: string): string;
var
  P: Integer;
begin
  Result:= Trim(ATypeText);
  P:= Pos('<', Result);
  if P > 0 then Result:= Trim(Copy(Result, 1, P - 1));
  P:= LastDelimiter('.', Result);
  if P > 0 then Result:= Copy(Result, P + 1, MaxInt);
end;

{ True for the text of a procedural type: `procedure(..)`, `function(..): T`, `reference to ..`. }
function IsProceduralText(const ATypeText: string): Boolean;
var
  T: string;
begin
  T:= TrimLeft(ATypeText);
  Result:= WordAt(T, 1, 'procedure') or WordAt(T, 1, 'function') or WordAt(T, 1, 'reference');
end;

{ TIndirectCallResolver }

constructor TIndirectCallResolver.Create(const AStore: ISymbolStore; AConn: TFDConnection;
  const AExtraConns: TArray<TFDConnection>);
begin
  inherited Create;
  FStore      := AStore;
  FConn       := AConn;
  FExtraConns := AExtraConns;
  FQueries    := TObjectDictionary<string, TFDQuery>.Create([doOwnsValues]);
  FSyms       := TDictionary<Int64, TSymInfo>.Create;
  FLines      := TDictionary<Int64, TArray<string>>.Create;
  FStaleFiles := TDictionary<Int64, Boolean>.Create;
  FProcTypes  := TDictionary<string, Boolean>.Create;
  FFileRefs   := TDictionary<Int64, TFileRef>.Create;
  FCallsByName:= TObjectDictionary<string, TList<TCallSite>>.Create([doOwnsValues]);
  FBinds      := TList<TBind>.Create;
  FEdges      := TList<TIndirectEdgeRow>.Create;
  FEdgeKeys   := TDictionary<string, Boolean>.Create;
end;

destructor TIndirectCallResolver.Destroy;
begin
  FEdgeKeys.Free;
  FEdges.Free;
  FBinds.Free;
  FCallsByName.Free;
  FFileRefs.Free;
  FProcTypes.Free;
  FStaleFiles.Free;
  FLines.Free;
  FSyms.Free;
  FQueries.Free;
  inherited Destroy;
end;

function TIndirectCallResolver.GetEdges: TArray<TIndirectEdgeRow>;
begin
  Result:= FEdges.ToArray;
end;

{ One prepared query per statement text, closed and ready for new parameters. Never hand the same
  statement to two loops that are open at once. }
function TIndirectCallResolver.Query(const ASql: string): TFDQuery;
begin
  if FQueries.TryGetValue(ASql, Result) then
  begin
    Result.Close;
    Exit;
  end;
  Result:= TFDQuery.Create(nil);
  FQueries.Add(ASql, Result);
  Result.Connection:= FConn;
  Result.SQL.Text  := ASql;
end;

{ Opens a prepared query and returns column 0 of its first row; 0 when it has none. }
function TIndirectCallResolver.FirstId(AQuery: TFDQuery): Int64;
begin
  Result:= 0;
  AQuery.Open;
  try
    if not AQuery.Eof then Result:= AQuery.Fields[0].AsLargeInt;
  finally
    AQuery.Close;
  end;
end;

function TIndirectCallResolver.TableExists(const AName: string): Boolean;
var
  Q: TFDQuery;
begin
  Q:= Query(SQL_TABLE);
  Q.ParamByName('n').AsWideString:= AName;
  Result:= FirstId(Q) <> 0;
end;

function TIndirectCallResolver.Sym(AId: Int64): TSymInfo;
var
  Q: TFDQuery;
begin
  if FSyms.TryGetValue(AId, Result) then Exit;
  Result:= Default(TSymInfo);
  if AId <> 0 then
  begin
    Q:= Query(SQL_SYMBOL);
    Q.ParamByName('i').AsLargeInt:= AId;
    Q.Open;
    try
      if not Q.Eof then
      begin
        Result.Id       := AId;
        Result.FileId   := Q.Fields[0].AsLargeInt;
        Result.ParentId := Q.Fields[1].AsLargeInt;
        Result.Kind     := Q.Fields[2].AsString;
        Result.Name     := Q.Fields[3].AsString;
        Result.Signature:= Q.Fields[4].AsString;
        Result.Section  := Q.Fields[5].AsString;
        Result.Line     := Q.Fields[6].AsInteger;
        Result.EndLine  := Q.Fields[7].AsInteger;
      end;
    finally
      Q.Close;
    end;
  end;
  FSyms.Add(AId, Result);
end;

{ The lines of an indexed file, or [] with the file recorded stale. Same probe as
  TDispatchResolver.LinesOf: line / col of the index are only valid for the bytes it parsed. }
function TIndirectCallResolver.LinesOf(AFileId: Int64): TArray<string>;
var
  Path: string;
  Txt : string;
  SL  : TStringList;
begin
  if FLines.TryGetValue(AFileId, Result) then Exit;
  Result:= [];
  FLines.Add(AFileId, Result);
  Path:= FStore.GetFilePath(AFileId);
  try
    if (Path = '') or not TFile.Exists(Path) then
    begin
      FStaleFiles.AddOrSetValue(AFileId, True);
      Exit;
    end;
    Txt:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(Path));
    if not FStore.FileIsUpToDate(Path, FileMTimeUnix(Path), THashSHA2.GetHashString(Txt)) then
      FStaleFiles.AddOrSetValue(AFileId, True)
    else
    begin
      SL:= TStringList.Create;
      try
        SL.Text:= Txt;
        Result := SL.ToStringArray;
      finally
        SL.Free;
      end;
      FLines.AddOrSetValue(AFileId, Result);
    end;
  except // dl:ok try-except-swallowed@c7b1 -- not swallowed: the file is RECORDED stale and every site in it is counted (Stale)
    on E: EInOutError do FStaleFiles.AddOrSetValue(AFileId, True);
    on E: EFOpenError do FStaleFiles.AddOrSetValue(AFileId, True);
  end;
end;

{ AFound = a type of that name exists in AConn; Result = one of them is procedural. }
function TIndirectCallResolver.ProceduralInConn(AConn: TFDConnection; const AName: string; ADepth: Integer;
  out AFound: Boolean): Boolean;
var
  Q   : TFDQuery;
  Sigs: TList<string>;
  S   : string;
begin
  Result:= False;
  AFound:= False;
  Sigs:= TList<string>.Create;
  try
    if AConn = FConn then Q:= Query(SQL_TYPE_NAMED)
    else
    begin
      Q:= TFDQuery.Create(nil);
      Q.Connection:= AConn;
      Q.SQL.Text  := SQL_TYPE_NAMED;
    end;
    try
      Q.ParamByName('n').AsWideString:= AName;
      Q.Open;
      try
        while not Q.Eof do
        begin
          Sigs.Add(Q.Fields[0].AsString);
          Q.Next;
        end;
      finally
        Q.Close;
      end;
    finally
      if AConn <> FConn then Q.Free;
    end;
    AFound:= Sigs.Count > 0;
    for S in Sigs do
      if IsProceduralText(S) or ((S <> '') and (ADepth < ALIAS_MAX_DEPTH) and IsProceduralType(S, ADepth + 1)) then
        Exit(True);
  finally
    Sigs.Free;
  end;
end;

{ True when ATypeText is, or names, a procedural type: its own text, a type symbol of this index,
  or a type symbol of a library index. An unknown name is NOT procedural (the caller declines). }
function TIndirectCallResolver.IsProceduralType(const ATypeText: string; ADepth: Integer): Boolean;
var
  Name, Key: string;
  Found    : Boolean;
  C        : TFDConnection;
begin
  if IsProceduralText(ATypeText) then Exit(True);
  Name:= BareTypeName(ATypeText);
  if Name = '' then Exit(False);
  Key:= LowerCase(Name);
  if FProcTypes.TryGetValue(Key, Result) then Exit;
  FProcTypes.Add(Key, False); // an alias cycle ends here
  Result:= ProceduralInConn(FConn, Name, ADepth, Found);
  if not Found then
    for C in FExtraConns do
    begin
      Result:= ProceduralInConn(C, Name, ADepth, Found);
      if Found then Break;
    end;
  FProcTypes.AddOrSetValue(Key, Result);
end;

{ A routine whose bare name can be an expression: a function. The index stores the signature as
  `(params): TResult` -- a result type is the ':' after the parameter list. }
function TIndirectCallResolver.RoutineHasResult(const ARoutine: TSymInfo): Boolean;
var
  S    : string;
  I    : Integer;
  Depth: Integer;
begin
  if ARoutine.Kind = KIND_FUNCTION then Exit(True);
  if ARoutine.Kind = KIND_PROCEDURE then Exit(False);
  S:= Trim(ARoutine.Signature);
  I:= 1;
  if (S <> '') and (S[1] = '(') then
  begin
    Depth:= 0;
    while I <= Length(S) do
    begin
      if S[I] = '(' then Inc(Depth)
      else if S[I] = ')' then
      begin
        Dec(Depth);
        if Depth = 0 then Break;
      end;
      Inc(I);
    end;
    Inc(I);
  end;
  while (I <= Length(S)) and IsBlank(S[I]) do Inc(I);
  Result:= (I <= Length(S)) and (S[I] = ':');
end;

{ The write / member-access / call ref that starts at a position of AFileId. One file is held. }
function TIndirectCallResolver.FileRefAt(AFileId: Int64; ALine, ACol: Integer; out ARef: TFileRef): Boolean;
var
  Q  : TFDQuery;
  R  : TFileRef;
  Key: Int64;
begin
  if AFileId <> FRefFile then
  begin
    FFileRefs.Clear;
    FRefFile:= AFileId;
    Q:= Query(if FHasMemberAccesses then SQL_FILE_REFS_MA else SQL_FILE_REFS);
    Q.ParamByName('f').AsLargeInt:= AFileId;
    Q.Open;
    try
      while not Q.Eof do
      begin
        R.Id        := Q.Fields[0].AsLargeInt;
        R.Kind      := Q.Fields[1].AsString;
        R.SymbolId  := Q.Fields[2].AsLargeInt;
        R.MemberId  := Q.Fields[5].AsLargeInt;
        R.AccessorId:= Q.Fields[6].AsLargeInt;
        Key:= (Int64(Q.Fields[3].AsInteger) shl POS_COL_BITS) or Q.Fields[4].AsInteger;
        { two refs at one position: keep the one that names a symbol }
        if (not FFileRefs.TryGetValue(Key, ARef)) or ((ARef.SymbolId = 0) and (ARef.MemberId = 0)) then
          FFileRefs.AddOrSetValue(Key, R);
        Q.Next;
      end;
    finally
      Q.Close;
    end;
  end;
  Result:= FFileRefs.TryGetValue((Int64(ALine) shl POS_COL_BITS) or ACol, ARef);
  if not Result then ARef:= Default(TFileRef);
end;

{ The field a property reads / writes directly (its `read F` / `write F` specifier); 0 when the
  property has accessor methods only. }
function TIndirectCallResolver.FieldOfProperty(const AProp: TSymInfo): Int64;
var
  Q: TFDQuery;
begin
  Result:= 0;
  Q:= Query(SQL_PROP_FIELD);
  Q.ParamByName('f').AsLargeInt:= AProp.FileId;
  Q.ParamByName('a').AsInteger := AProp.Line;
  Q.ParamByName('b').AsInteger := if AProp.EndLine >= AProp.Line then AProp.EndLine else AProp.Line;
  Result:= FirstId(Q);
end;

{ The slot a left-hand side stands for: the field behind a property when there is one (so the
  binding meets the calls of `FOnX(..)`), else the symbol itself; 0 = not a symbol of this index. }
function TIndirectCallResolver.CanonicalSlot(const ALhs: TFileRef; out AIsProperty: Boolean): Int64;
var
  S: TSymInfo;
begin
  AIsProperty:= False;
  Result:= if ALhs.SymbolId <> 0 then ALhs.SymbolId else ALhs.MemberId;
  if Result = 0 then Exit;
  S:= Sym(Result);
  if S.Kind <> KIND_PROPERTY then Exit;
  AIsProperty:= True;
  if (ALhs.AccessorId <> 0) and (Sym(ALhs.AccessorId).Kind = KIND_FIELD) then Exit(ALhs.AccessorId);
  var FieldId:= FieldOfProperty(S);
  if FieldId <> 0 then Result:= FieldId;
end;

function TIndirectCallResolver.LocalNamed(ARoutineId: Int64; const AName: string): Int64;
var
  Q: TFDQuery;
begin
  Result:= 0;
  Q:= Query(SQL_LOCAL_NAMED);
  Q.ParamByName('p').AsLargeInt  := ARoutineId;
  Q.ParamByName('n').AsWideString:= AName;
  Result:= FirstId(Q);
end;

function TIndirectCallResolver.MemberNamed(AClassId: Int64; const AName: string): Int64;
var
  Q: TFDQuery;
begin
  Result:= 0;
  Q:= Query(SQL_MEMBER_NAMED);
  Q.ParamByName('p').AsLargeInt  := AClassId;
  Q.ParamByName('n').AsWideString:= AName;
  Result:= FirstId(Q);
end;

{ The first ancestor of a class that is a symbol of this index; 0 at the end of the local chain. }
function TIndirectCallResolver.AncestorOf(AClassId: Int64): Int64;
var
  Q: TFDQuery;
begin
  Result:= 0;
  Q:= Query(SQL_ANCESTOR);
  Q.ParamByName('s').AsLargeInt:= AClassId;
  Q.Open;
  try
    while (Result = 0) and not Q.Eof do
    begin
      if Sym(Q.Fields[0].AsLargeInt).Kind = KIND_CLASS then Result:= Q.Fields[0].AsLargeInt;
      Q.Next;
    end;
  finally
    Q.Close;
  end;
end;

{ What the bare name AName means inside routine AEnclosingId of file AFileId, by Delphi scope
  order: parameters and locals of the routine and of the routines it is nested in, members of its
  class and of the class's ancestors in this index, unit-level symbols of the file, then an
  interface variable of a used unit (AByName: matched across units by name; 0 when two fit). }
function TIndirectCallResolver.ResolveName(AEnclosingId, AFileId: Int64; const AName: string;
  out AByName: Boolean): Int64;
var
  Q    : TFDQuery;
  Cur  : TSymInfo;
  Depth: Integer;
  Hits : Integer;
begin
  AByName:= False;
  Result := 0;
  Cur:= Sym(AEnclosingId);
  Depth:= 0;
  while (Cur.Id <> 0) and (Depth < CHAIN_MAX_DEPTH) and IsRoutineKind(Cur.Kind) do
  begin
    Result:= LocalNamed(Cur.Id, AName);
    if Result <> 0 then Exit;
    Cur:= Sym(Cur.ParentId);
    Inc(Depth);
  end;
  while (Cur.Id <> 0) and (Depth < CHAIN_MAX_DEPTH) and ((Cur.Kind = KIND_CLASS) or (Cur.Kind = KIND_RECORD)) do
  begin
    Result:= MemberNamed(Cur.Id, AName);
    if Result <> 0 then Exit;
    Cur:= Sym(AncestorOf(Cur.Id));
    Inc(Depth);
  end;
  Q:= Query(SQL_UNIT_LEVEL);
  Q.ParamByName('f').AsLargeInt  := AFileId;
  Q.ParamByName('n').AsWideString:= AName;
  Result:= FirstId(Q);
  if Result <> 0 then Exit;
  Q:= Query(SQL_USED_VARS);
  Q.ParamByName('f').AsLargeInt  := AFileId;
  Q.ParamByName('n').AsWideString:= AName;
  Q.Open;
  try
    Hits:= 0;
    while not Q.Eof do
    begin
      Result:= Q.Fields[0].AsLargeInt;
      Inc(Hits);
      Q.Next;
    end;
  finally
    Q.Close;
  end;
  if Hits = 1 then AByName:= True
  else Result:= 0;
end;

{ Every call ref `AName(..)` of the index with the symbol the name means at that site. Cached. }
function TIndirectCallResolver.CallsNamed(const AName: string): TList<TCallSite>;
var
  Q    : TFDQuery;
  Site : TCallSite;
  Files: TList<Int64>;
  I    : Integer;
begin
  if FCallsByName.TryGetValue(LowerCase(AName), Result) then Exit;
  Result:= TList<TCallSite>.Create;
  FCallsByName.Add(LowerCase(AName), Result);
  Files:= TList<Int64>.Create;
  try
    Q:= Query(SQL_CALLS_NAMED);
    Q.ParamByName('n').AsWideString:= AName;
    Q.Open;
    try
      while not Q.Eof do
      begin
        Site.RefId   := Q.Fields[0].AsLargeInt;
        Site.SlotId  := Q.Fields[2].AsLargeInt;
        Site.CallerId:= Q.Fields[3].AsLargeInt;
        Site.ByName  := False;
        Result.Add(Site);
        Files.Add(Q.Fields[1].AsLargeInt);
        Q.Next;
      end;
    finally
      Q.Close;
    end;
    for I:= 0 to Result.Count - 1 do
    begin
      Site:= Result[I];
      if Site.SlotId <> 0 then Continue; // the calls stage already bound the name
      Site.SlotId:= ResolveName(Site.CallerId, Files[I], AName, Site.ByName);
      Result[I]:= Site;
    end;
  finally
    Files.Free;
  end;
end;

{ The symbols a call can name to reach slot ASlotId: the slot, and -- for a field -- every
  property of its class that reads or writes it directly. }
procedure TIndirectCallResolver.SlotAliases(ASlotId: Int64; AIds: TList<Int64>; ANames: TList<string>);
var
  Q: TFDQuery;
  S: TSymInfo;
begin
  S:= Sym(ASlotId);
  AIds.Add(ASlotId);
  ANames.Add(S.Name);
  if S.Kind <> KIND_FIELD then Exit;
  Q:= Query(SQL_FIELD_PROPS);
  Q.ParamByName('s').AsLargeInt:= ASlotId;
  Q.ParamByName('c').AsLargeInt:= S.ParentId;
  Q.Open;
  try
    while not Q.Eof do
    begin
      if not AIds.Contains(Q.Fields[0].AsLargeInt) then
      begin
        AIds.Add(Q.Fields[0].AsLargeInt);
        if ANames.IndexOf(Q.Fields[1].AsString) < 0 then ANames.Add(Q.Fields[1].AsString);
      end;
      Q.Next;
    end;
  finally
    Q.Close;
  end;
end;

procedure TIndirectCallResolver.LoadCandidates(ACands: TList<TCandidate>);
var
  Q: TFDQuery;
  C: TCandidate;
begin
  Q:= Query(SQL_CANDIDATES);
  Q.Open;
  try
    while not Q.Eof do
    begin
      C.FileId  := Q.Fields[0].AsLargeInt;
      C.Line    := Q.Fields[1].AsInteger;
      C.Col     := Q.Fields[2].AsInteger;
      C.Name    := Q.Fields[3].AsString;
      C.TargetId:= Q.Fields[4].AsLargeInt;
      ACands.Add(C);
      Q.Next;
    end;
  finally
    Q.Close;
  end;
end;

procedure TIndirectCallResolver.AddBind(const ABind: TBind);
begin
  FBinds.Add(ABind);
  Inc(FCounters.Binds);
end;

{ `<lhs> := [@]Routine`: AAssignAt = index of the ':' on ALine. }
procedure TIndirectCallResolver.BindAssignment(const ACand: TCandidate; const ALine: string; AAssignAt: Integer;
  AHasAt: Boolean);
var
  E, K, V   : Integer;
  Lhs       : TFileRef;
  B         : TBind;
  IsProperty: Boolean;
  Slot      : TSymInfo;
  Proven    : Boolean;
begin
  E:= SkipBlanksBack(ALine, AAssignAt - 1);
  if (E < 1) or not IsIdentChar(ALine[E]) then
  begin
    Inc(FCounters.Unread); // an indexed or dereferenced target: Items[I]:= Handler
    Exit;
  end;
  K:= E;
  while (K >= 1) and IsIdentChar(ALine[K]) do Dec(K);
  V:= K;
  while (V >= 1) and (IsIdentChar(ALine[V]) or (ALine[V] = '.')) do Dec(V);
  B:= Default(TBind);
  B.Via:= Copy(ALine, V + 1, E - V);
  while (B.Via <> '') and (B.Via[1] = '.') do Delete(B.Via, 1, 1);
  B.TargetId:= ACand.TargetId;
  B.FileId  := ACand.FileId;
  B.Line    := ACand.Line;
  B.Col     := ACand.Col;
  FileRefAt(ACand.FileId, ACand.Line, K + 1, Lhs);
  B.SlotId:= CanonicalSlot(Lhs, IsProperty);
  Slot:= Sym(B.SlotId);
  if B.SlotId = 0 then
  begin
    { not a symbol of this index: a member of a library class, or an inherited / with-scoped name }
    B.Kind:= if (Lhs.Kind = REF_MEMBER_ACCESS) or B.Via.Contains('.') or
                (Copy(B.Via, 1, Length(EVENT_PREFIX)) = EVENT_PREFIX) then IE_KIND_EVENT else IE_KIND_METHOD_POINTER;
  end
  else if IsProperty then B.Kind:= IE_KIND_EVENT
  else if (Slot.Kind = KIND_FIELD) or (Slot.Kind = KIND_VAR) or (Slot.Kind = KIND_LOCAL) or (Slot.Kind = KIND_PARAM) then
    B.Kind:= IE_KIND_METHOD_POINTER
  else
  begin
    Inc(FCounters.Unread); // `FuncName:= Handler` and other targets that are not a slot
    Exit;
  end;
  Proven:= AHasAt or not RoutineHasResult(Sym(ACand.TargetId));
  if (not Proven) and (B.SlotId <> 0) then
    { the type as declared on the symbol that was written: a property carries it like a field }
    Proven:= IsProceduralType(Sym(if Lhs.SymbolId <> 0 then Lhs.SymbolId else Lhs.MemberId).Signature);
  if not Proven then
  begin
    Inc(FCounters.Unproven);
    Exit;
  end;
  AddBind(B);
end;

{ `Callee(.., [@]Routine, ..)`: AArgAt = index of the '(' or ',' before the argument on ALine. }
procedure TIndirectCallResolver.BindArgument(const ACand: TCandidate; const ALine: string; AArgAt: Integer;
  AHasAt: Boolean);
var
  I, E, K : Integer;
  Depth   : Integer;
  ArgIndex: Integer;
  Callee  : string;
  Skip    : string;
  CallRef : TFileRef;
  Q       : TFDQuery;
  Routine : Int64;
  ParamId : Int64;
  B       : TBind;
  Proven  : Boolean;
begin
  { back to the '(' that opens the argument list, counting the arguments before this one }
  I:= AArgAt;
  Depth:= 0;
  ArgIndex:= 0;
  while I >= 1 do
  begin
    if ALine[I] = QUOTE then
    begin
      Dec(I);
      while (I >= 1) and (ALine[I] <> QUOTE) do Dec(I);
    end
    else if (ALine[I] = ')') or (ALine[I] = ']') then Inc(Depth)
    else if (ALine[I] = '(') or (ALine[I] = '[') then
    begin
      if Depth = 0 then Break;
      Dec(Depth);
    end
    else if (ALine[I] = ',') and (Depth = 0) then Inc(ArgIndex);
    Dec(I);
  end;
  E:= if I >= 1 then SkipBlanksBack(ALine, I - 1) else 0;
  if (I < 1) or (ALine[I] <> '(') or (E < 1) or not IsIdentChar(ALine[E]) then
  begin
    Inc(FCounters.Unread); // the list opens on another line, or is not a call: [A, B], Foo<T>(..)
    Exit;
  end;
  K:= E;
  while (K >= 1) and IsIdentChar(ALine[K]) do Dec(K);
  Callee:= Copy(ALine, K + 1, E - K);
  for Skip in NOT_A_CALLBACK_TAKER do
    if SameText(Callee, Skip) then Exit;
  if not FileRefAt(ACand.FileId, ACand.Line, K + 1, CallRef) then Exit; // a cast or a keyword, not a call
  B:= Default(TBind);
  B.Kind    := IE_KIND_CALLBACK_ARG;
  B.Via     := Callee;
  B.TargetId:= ACand.TargetId;
  B.FileId  := ACand.FileId;
  B.Line    := ACand.Line;
  B.Col     := ACand.Col;
  Proven:= AHasAt or not RoutineHasResult(Sym(ACand.TargetId));
  Q:= Query(SQL_CALL_TARGET);
  Q.ParamByName('r').AsLargeInt:= CallRef.Id;
  Routine:= FirstId(Q);
  if Routine <> 0 then
  begin
    Q:= Query(SQL_PARAM_AT);
    Q.ParamByName('p').AsLargeInt:= Routine;
    Q.ParamByName('o').AsInteger := ArgIndex;
    ParamId:= FirstId(Q);
    if ParamId <> 0 then
    begin
      { the parameter is the slot: its calls inside the callee are the call sites }
      B.SlotId:= ParamId;
      B.Via   := Sym(ParamId).Name;
      if not Proven then Proven:= IsProceduralType(Sym(ParamId).Signature);
    end;
  end;
  if not Proven then
  begin
    Inc(FCounters.Unproven);
    Exit;
  end;
  AddBind(B);
end;

{ The class symbol named AName: the one declared in APreferPath when there is one, else the only
  one of the index (AByName); 0 when there is none or several. }
function TIndirectCallResolver.ClassNamed(const AName, APreferPath: string; out AByName: Boolean): Int64;
var
  Q   : TFDQuery;
  Hits: Integer;
  Only: Int64;
begin
  Result := 0;
  AByName:= False;
  if AName = '' then Exit;
  Hits:= 0;
  Only:= 0;
  Q:= Query(SQL_CLASS_NAMED);
  Q.ParamByName('n').AsWideString:= AName;
  Q.Open;
  try
    while (Result = 0) and not Q.Eof do
    begin
      Inc(Hits);
      Only:= Q.Fields[0].AsLargeInt;
      if (APreferPath <> '') and SameText(Q.Fields[1].AsString, APreferPath) then Result:= Only;
      Q.Next;
    end;
  finally
    Q.Close;
  end;
  if (Result = 0) and (Hits = 1) then
  begin
    Result := Only;
    AByName:= True;
  end;
end;

{ The routine AName of class AClassId or of its nearest ancestor in this index that declares it. }
function TIndirectCallResolver.RoutineInChain(AClassId: Int64; const AName: string): Int64;
var
  Q    : TFDQuery;
  Cls  : Int64;
  Depth: Integer;
begin
  Result:= 0;
  Cls   := AClassId;
  Depth := 0;
  while (Result = 0) and (Cls <> 0) and (Depth < CHAIN_MAX_DEPTH) do
  begin
    Q:= Query(SQL_ROUTINE_NAMED);
    Q.ParamByName('p').AsLargeInt  := Cls;
    Q.ParamByName('n').AsWideString:= AName;
    Result:= FirstId(Q);
    Cls:= AncestorOf(Cls);
    Inc(Depth);
  end;
end;

{ The slot behind event property APropName of the component class AClassName, when that class is
  the only class of that name in this index: the field the property reads / writes, else the
  property; 0 for a library component. }
function TIndirectCallResolver.SlotOfComponentEvent(const AClassName, APropName: string): Int64;
var
  Cls     : Int64;
  MemberId: Int64;
  Depth   : Integer;
  ByName  : Boolean;
  Member  : TSymInfo;
begin
  Result:= 0;
  if APropName = '' then Exit;
  Cls:= ClassNamed(AClassName, '', ByName);
  MemberId:= 0;
  Depth:= 0;
  while (MemberId = 0) and (Cls <> 0) and (Depth < CHAIN_MAX_DEPTH) do
  begin
    MemberId:= MemberNamed(Cls, APropName);
    Cls:= AncestorOf(Cls);
    Inc(Depth);
  end;
  Member:= Sym(MemberId);
  if Member.Kind <> KIND_PROPERTY then Exit;
  Result:= FieldOfProperty(Member);
  if Result = 0 then Result:= MemberId;
end;

{ `OnClick = Button1Click` in a .dfm: the handler is the method of the form class (the class the
  root object names, declared in the .pas beside the .dfm). The framework fires the event, so the
  row has no call site -- unless the component's class is in this index and calls the field behind
  that event property itself. }
procedure TIndirectCallResolver.CollectDfmBinds;
var
  Q         : TFDQuery;
  Cands     : TList<TCandidate>;
  C         : TCandidate;
  B         : TBind;
  FormFile  : Int64;
  FormClass : Int64;
  FormByName: Boolean;
  ObjName   : string;
  PropName  : string;
  OwnerClass: string;
begin
  Cands:= TList<TCandidate>.Create;
  try
    Q:= Query(SQL_DFM_EVENTS);
    Q.Open;
    try
      while not Q.Eof do
      begin
        C:= Default(TCandidate);
        C.FileId:= Q.Fields[0].AsLargeInt;
        C.Line  := Q.Fields[1].AsInteger;
        C.Col   := Q.Fields[2].AsInteger;
        C.Name  := Q.Fields[3].AsString;
        Cands.Add(C);
        Q.Next;
      end;
    finally
      Q.Close;
    end;
    FormFile  := 0;
    FormClass := 0;
    FormByName:= False;
    for C in Cands do
    begin
      if C.FileId <> FormFile then
      begin
        FormFile:= C.FileId;
        Q:= Query(SQL_DFM_ROOT);
        Q.ParamByName('f').AsLargeInt:= C.FileId;
        Q.Open;
        try
          OwnerClass:= if Q.Eof then '' else Q.Fields[0].AsString;
        finally
          Q.Close;
        end;
        FormClass:= ClassNamed(OwnerClass, TPath.ChangeExtension(FStore.GetFilePath(C.FileId), PAS_EXT), FormByName);
      end;
      B:= Default(TBind);
      B.TargetId:= RoutineInChain(FormClass, C.Name);
      if B.TargetId = 0 then
      begin
        Inc(FCounters.Unread); // no form class in this index, or the handler is inherited from a library class
        Continue;
      end;
      B.Kind  := IE_KIND_DFM_EVENT;
      B.FileId:= C.FileId;
      B.Line  := C.Line;
      B.Col   := C.Col;
      B.ByName:= FormByName;
      ObjName   := '';
      PropName  := '';
      OwnerClass:= '';
      if FHasDfmProperties then
      begin
        Q:= Query(SQL_DFM_PROPERTY);
        Q.ParamByName('f').AsLargeInt  := C.FileId;
        Q.ParamByName('l').AsInteger   := C.Line;
        Q.ParamByName('v').AsWideString:= C.Name;
        Q.Open;
        try
          if not Q.Eof then
          begin
            ObjName   := Q.Fields[0].AsString;
            PropName  := Q.Fields[1].AsString;
            OwnerClass:= Q.Fields[2].AsString;
          end;
        finally
          Q.Close;
        end;
      end;
      B.Via:= if ObjName <> '' then ObjName + '.' + PropName else PropName;
      { a component class of this index: the event property's field is a slot with call sites }
      B.SlotId:= SlotOfComponentEvent(OwnerClass, PropName);
      if B.SlotId <> 0 then B.ByName:= True; // the component class was found by its name
      AddBind(B);
    end;
  finally
    Cands.Free;
  end;
end;

procedure TIndirectCallResolver.CollectBinds;
var
  Cands: TList<TCandidate>;
  C    : TCandidate;
  Lines: TArray<string>;
  Line : string;
  HasAt: Boolean;
  At   : Integer;
begin
  Cands:= TList<TCandidate>.Create;
  try
    LoadCandidates(Cands);
    for C in Cands do
    begin
      Lines:= LinesOf(C.FileId);
      if FStaleFiles.ContainsKey(C.FileId) then
      begin
        Inc(FCounters.Stale);
        Continue;
      end;
      if (C.Line < 1) or (C.Line > Length(Lines)) then Continue;
      Line:= Lines[C.Line - 1];
      if not SameText(Copy(Line, C.Col, Length(C.Name)), C.Name) then Continue; // not the bytes that were indexed
      case ClassifySite(Line, C.Col, Length(C.Name), HasAt, At) of
        ssAssign  : BindAssignment(C, Line, At, HasAt);
        ssArgument: BindArgument(C, Line, At, HasAt);
      end;
    end;
  finally
    Cands.Free;
  end;
end;

procedure TIndirectCallResolver.AddEdge(const ABind: TBind; const ASite: TCallSite);
var
  E  : TIndirectEdgeRow;
  Key: string;
begin
  Key:= Format('%d|%d|%s|%d|%d|%d', [ASite.RefId, ABind.TargetId, ABind.Kind, ABind.FileId, ABind.Line, ABind.Col]);
  if FEdgeKeys.ContainsKey(Key) then Exit;
  FEdgeKeys.Add(Key, True);
  E:= Default(TIndirectEdgeRow);
  E.RefId     := ASite.RefId;
  E.CallerId  := ASite.CallerId;
  E.TargetId  := ABind.TargetId;
  E.Kind      := ABind.Kind;
  E.ViaText   := ABind.Via;
  E.BindFileId:= ABind.FileId;
  E.BindLine  := ABind.Line;
  E.BindCol   := ABind.Col;
  E.Confidence:= if ABind.ByName or ASite.ByName then IE_CONF_BY_NAME else IE_CONF_RESOLVED;
  FEdges.Add(E);
  if      ABind.Kind = IE_KIND_METHOD_POINTER then Inc(FCounters.MethodPointer)
  else if ABind.Kind = IE_KIND_EVENT          then Inc(FCounters.Event)
  else if ABind.Kind = IE_KIND_DFM_EVENT      then Inc(FCounters.DfmEvent)
  else if ABind.Kind = IE_KIND_CALLBACK_ARG   then Inc(FCounters.CallbackArg);
end;

{ Pairs every binding with every call through its slot; a binding without one yields the
  RefId = 0 row. }
procedure TIndirectCallResolver.EmitBinds;
var
  B     : TBind;
  Ids   : TList<Int64>;
  Names : TList<string>;
  Name  : string;
  Site  : TCallSite;
  NoSite: TCallSite;
  Before: Integer;
begin
  NoSite:= Default(TCallSite);
  Ids  := TList<Int64>.Create;
  Names:= TList<string>.Create;
  try
    for B in FBinds do
    begin
      Before:= FEdges.Count;
      if B.SlotId <> 0 then
      begin
        Ids.Clear;
        Names.Clear;
        SlotAliases(B.SlotId, Ids, Names);
        for Name in Names do
          for Site in CallsNamed(Name) do
            if (Site.SlotId <> 0) and Ids.Contains(Site.SlotId) then AddEdge(B, Site);
      end;
      if FEdges.Count = Before then
      begin
        Inc(FCounters.NoSite);
        AddEdge(B, NoSite);
      end;
    end;
  finally
    Names.Free;
    Ids.Free;
  end;
end;

procedure TIndirectCallResolver.Run;
begin
  FCounters:= Default(TIndirectCounters);
  FBinds.Clear;
  FEdges.Clear;
  FEdgeKeys.Clear;
  FRefFile:= 0;
  FFileRefs.Clear;
  FHasMemberAccesses:= TableExists(TABLE_MEMBER_ACCESSES);
  FHasDfmProperties := TableExists(TABLE_DFM_PROPERTIES) and TableExists(TABLE_DFM_OBJECTS);
  CollectBinds;
  CollectDfmBinds;
  EmitBinds;
end;

/// <summary>The TIndirectEdgesHook of this unit: runs TIndirectCallResolver over AStore.</summary>
/// <param name="AStore">The project store. Must be the SQLite store (TSQLiteSymbolStore); any other
/// implementation yields no rows.</param>
/// <param name="AExtraStores">The library stores of the run; may be nil. Non-SQLite entries are skipped.</param>
/// <returns>Every indirect edge of the index; empty when AStore is not a SQLite store.</returns>
/// <remarks>Registered with TIndexPassHooks.RegisterIndirectEdges by this unit's initialization.
/// Set the environment variable DRAGLINT_INDIRECT_LOG=1 to print the counters line to stdout.</remarks>
function CollectIndirectEdges(const AStore: ISymbolStore; const AExtraStores: TArray<ISymbolStore>): TArray<TIndirectEdgeRow>;
var
  Res  : TIndirectCallResolver;
  Extra: TList<TFDConnection>;
  St   : ISymbolStore;
  C    : TIndirectCounters;
begin
  Result:= nil;
  if (AStore as TObject) is not TSQLiteSymbolStore then Exit;
  Extra:= TList<TFDConnection>.Create;
  try
    for St in AExtraStores do
      if (St <> nil) and ((St as TObject) is TSQLiteSymbolStore) then
        Extra.Add(TSQLiteSymbolStore(St as TObject).GetConnection);
    Res:= TIndirectCallResolver.Create(AStore, TSQLiteSymbolStore(AStore as TObject).GetConnection, Extra.ToArray);
    try
      Res.Run;
      Result:= Res.Edges;
      if GetEnvironmentVariable(INDIRECT_LOG_ENV) = '1' then
      begin
        C:= Res.Counters;
        Writeln(Format('indirect: method-pointer=%d event=%d dfm-event=%d callback-arg=%d binds=%d ' +
          'declined: no-site=%d unproven=%d unread=%d stale=%d',
          [C.MethodPointer, C.Event, C.DfmEvent, C.CallbackArg, C.Binds, C.NoSite, C.Unproven, C.Unread, C.Stale]));
      end;
    finally
      Res.Free;
    end;
  finally
    Extra.Free;
  end;
end;

initialization
  TIndexPassHooks.RegisterIndirectEdges(CollectIndirectEdges);

end.
