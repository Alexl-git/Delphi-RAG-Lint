unit DRagLint.Charts.Q.ValueFlow;

(* The `value-origin` AND `value-use` questions (gap G-42; 1.56 lane FB-1): where the value of ONE field,
  unit variable, property, parameter or function result comes from, and where it goes, read from the
  data_flows facts -- the numeric / Boolean / date-time VALUE rows of 1.56 (B3, data_flows.val_class)
  included. Delphi-only: there is no Emit-*.ps1 for it. One unit registers both ids, as Q.MemberAccess
  does; the direction is read from the question id.

  WHAT IT DRAWS. The selection is the focus node. Step 1 is one row per data_flows row that ends in the
  selection (value-origin) or starts at it (value-use); step 2 explains every step-1 row the same way,
  and so on up to --depth (default 2). A row is anchored at the site where the value lands, names the
  routine, and carries the VALUE CLASS of the row in brackets: int, float, currency, datetime, bool.
  A row without a class is a pre-1.56 row (a string, an object, or a value the extractor could not
  class); it is NOT a claim that the value is text.

  THE TWO ROW SETS. The index holds two disjoint sets in one table: val_class = '' (the set every
  extractor since 1.26 writes) and val_class <> '' (the value rows only a 1.56 extractor writes). This
  unit names the set in every count: ValueRows counts val_class <> '' and nothing else, FlowRows counts
  val_class = '' and nothing else (VALUE_ROW / FLOW_ROW below are the ONE place the test is written).
  An index with no value row at all says so on the focus: numeric values are NOT tracked there, and a
  chart that shows no numeric source is silence, not proof.

  WHERE IT STOPS, AND SAYS SO. A literal or a constant writes no row (a field assigned only from
  literals has write sites and no source: the focus says it). A local variable is not a node: the row
  joins the two ends and is marked 'through a local'. A call on an object (`Obj.Total`) reports the
  OBJECT as its source, not the method's result. A var / out argument and a var / out parameter end the
  walk in this version. A source or destination the index does not bind is drawn by name and not
  followed. Rows beyond --cap in one step are counted, not drawn. *)

interface

const
  /// <summary>The registered question id of the backward walk: what feeds the selection.</summary>
  VALUE_ORIGIN_ID = 'value-origin';
  /// <summary>The registered question id of the forward walk: where the selection's value goes,
  /// answered by the same unit.</summary>
  VALUE_USE_ID = 'value-use';

implementation

uses
  System.SysUtils, System.StrUtils, System.Math, System.Generics.Collections, System.RegularExpressions,
  DRagLint.Core.Model // dl:unit DRagLint.Core.Model accepted -- the DF_* kind and value-class constants ARE the data_flows contract; this unit compares exactly those
  , DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot;

const
  { VALUE: its own palette role (indigo) -- not caller blue, callee amber, state cyan or db rose }
  VALUE_BORDER = '#4338CA';
  VALUE_FILL = '#EEF2FF';
  VALUE_HDR = '#4338CA';
  FOCUS_BORDER = '#0F766E';
  FOCUS_FILL = '#E2F1EF';
  FOCUS_HDR = '#0F766E';
  FOCUS_INK = '#0B3F39';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  { the symbol kinds of the index this unit tells apart }
  K_FIELD = 'field';
  K_VAR = 'var';
  K_PROPERTY = 'property';
  K_PARAM = 'param';
  K_FUNCTION = 'function';
  K_METHOD = 'method';
  K_PROCEDURE = 'procedure';
  { the two disjoint row sets of data_flows; %s is the val_class expression of this index }
  VALUE_ROW = '%s <> ''''';
  FLOW_ROW = '%s = ''''';
  { an index written before 1.56 has no val_class column: every row reads as the pre-1.56 set }
  NO_VAL_CLASS_EXPR = '''''';
  VAL_CLASS_EXPR = 'd.val_class';
  VAL_CLASS_COLUMN = 'val_class';
  { every hop query selects these columns, in this order of meaning }
  HOP_COLUMNS =
    'SELECT DISTINCT d.file_id AS file_id, d.symbol_id AS rid, d.dst_kind AS dst_kind, d.dst_line AS dst_line,' + sLineBreak +
    '       d.dst_col AS dst_col, d.dst_index AS dst_index, d.dst_name AS dst_name,' + sLineBreak +
    '       d.dst_receiver AS dst_receiver, d.src_kind AS src_kind, d.src_index AS src_index,' + sLineBreak +
    '       d.src_line AS src_line, d.src_col AS src_col, d.src_name AS src_name,' + sLineBreak +
    '       d.via_local AS via_local, d.cond AS cond, %s AS val_class,' + sLineBreak +
    '       f.path AS path, rs.qualified_name AS routine, rs.impl_start_line AS routine_line' + sLineBreak +
    '  FROM data_flows d' + sLineBreak +
    '  JOIN files f ON f.id = d.file_id' + sLineBreak +
    '  JOIN symbols rs ON rs.id = d.symbol_id' + sLineBreak;
  HOP_ORDER = ' ORDER BY f.path, d.dst_line, d.dst_col, d.src_line, d.src_col, d.src_name, d.src_index, d.dst_index';
  { the ref at one end of a row: refs holds the same line and column the row stores }
  BOUND_DST = '  JOIN refs br ON br.file_id = d.file_id AND br.start_line = d.dst_line AND br.start_col = d.dst_col' + sLineBreak;
  BOUND_SRC = '  JOIN refs br ON br.file_id = d.file_id AND br.start_line = d.src_line AND br.start_col = d.src_col' + sLineBreak;
  NOT_FOLLOWED = -1;
  FOCUS_PARENT = -1;
  FIRST_TIER = 1;
  CLASS_TAG = '  [%s]';
  CONDITIONAL_STYLE = 'dashed';
  SOLID_STYLE = 'solid';
  END_SRC = 'src';
  END_DST = 'dst';
  NOT_IN_INDEX = ' (not in this index)';

type
  /// <summary>What one end of a flow is.</summary>
  TNodeKind = (
    /// <summary>A field; Id is its symbols.id.</summary>
    nkField,
    /// <summary>A unit-level variable; Id is its symbols.id.</summary>
    nkGlobal,
    /// <summary>A property; Id is its symbols.id. Followed through its bound read and write refs only.</summary>
    nkProperty,
    /// <summary>The result of a routine; Id is the routine's symbols.id.</summary>
    nkResult,
    /// <summary>A parameter; Id is the ROUTINE's symbols.id, Index its 0-based position.</summary>
    nkParam,
    /// <summary>An end the walk does not follow: unbound, a var / out end, or a kind of a later lane.</summary>
    nkEnd);

  /// <summary>One end of a flow: the selection, or the far end of a row.</summary>
  TValueNode = record
    /// <summary>What the end is.</summary>
    Kind: TNodeKind;
    /// <summary>symbols.id (see TNodeKind); NOT_FOLLOWED for nkEnd.</summary>
    Id: Integer;
    /// <summary>The parameter position of nkParam, else NOT_FOLLOWED.</summary>
    Index: Integer;
    /// <summary>The leaf name as the rows write it (field, variable, parameter name).</summary>
    Name: string;
    /// <summary>What the row prints.</summary>
    Caption: string;
    /// <summary>An end that is not followed.</summary>
    /// <param name="pCaption">What the row prints.</param>
    /// <returns>The node, kind nkEnd.</returns>
    class function Stop(const pCaption: string): TValueNode; static;
    /// <summary>The identity of the end across the walk.</summary>
    /// <returns>'' for nkEnd (never visited twice by identity), else kind, id and index.</returns>
    function Key: string;
  end;

  /// <summary>The ref the index holds at one end of a row.</summary>
  TBoundRef = record
    /// <summary>The bound symbols.id; 0 when the ref is unbound or absent.</summary>
    Id: Integer;
    /// <summary>The bound symbol's kind; '' when unbound.</summary>
    Kind: string;
    /// <summary>The bound symbol's qualified name; '' when unbound.</summary>
    QName: string;
    /// <summary>The unit that declares the bound symbol; '' when unbound.</summary>
    UnitName: string;
    /// <summary>The ref as written, receiver included.</summary>
    Text: string;
  end;

  /// <summary>One drawn row: one data_flows row (or several identical ones) seen from the node it explains.</summary>
  THop = record
    /// <summary>The far end.</summary>
    Node: TValueNode;
    /// <summary>The index of the hop this row explains; FOCUS_PARENT for a step-1 row.</summary>
    Parent: Integer;
    /// <summary>1 = beside the selection.</summary>
    Tier: Integer;
    /// <summary>The routine the row was extracted from (qualified).</summary>
    Routine: string;
    /// <summary>The file of that routine.</summary>
    Path: string;
    /// <summary>The line where the value lands (the row's destination site; the routine when 0).</summary>
    Line: Integer;
    /// <summary>The row's value class; '' = a pre-1.56 row.</summary>
    ValClass: string;
    /// <summary>The value reached the destination through a local.</summary>
    ViaLocal: Boolean;
    /// <summary>The value reaches the destination on some paths only.</summary>
    Cond: Boolean;
    /// <summary>The far end was already explained by an earlier row: drawn, not followed again.</summary>
    Seen: Boolean;
    /// <summary>How many identical index rows this row stands for.</summary>
    Sites: Integer;
  end;

  /// <summary>Whether the index can answer for numeric values.</summary>
  TValueTracking = (
    /// <summary>data_flows has no val_class column: written by an extractor before 1.56.</summary>
    vtNoColumn,
    /// <summary>The column exists and no row carries a class: not re-parsed by a 1.56 extractor.</summary>
    vtNoRows,
    /// <summary>Value rows exist.</summary>
    vtTracked);

  /// <summary>One walk: the selection, the rows of every step, and what was left out.</summary>
  /// <remarks>Owns nothing but its lists; the index is the caller's. Not thread-safe.</remarks>
  TValueWalk = class
  strict private
    FIndex: TChartsIndex;
    FOrigin: Boolean;
    FCap: Integer;
    FDepth: Integer;
    FValExpr: string;
    FTracking: TValueTracking;
    FFocus: TValueNode;
    FSel: TMemberSelection;
    FHops: TList<THop>;
    FHidden: TList<Integer>;
    FVisited: TDictionary<string, Boolean>;
    FUnfollowed: Integer;
    function HopSql(const pNode: TValueNode): TArray<string>;
    function RowsOf(const pNode: TValueNode; pParent, pTier: Integer): TArray<THop>;
    procedure ProbeTracking;
    procedure ResolveFocus(const pTarget: string);
  public
    /// <summary>Resolves the selection and probes the index; walks nothing yet.</summary>
    /// <param name="pIndex">The open index; must not be nil. The caller owns it and must outlive the walk.</param>
    /// <param name="pTarget">The selection: a field, unit variable, property, parameter (Routine.pName) or function.</param>
    /// <param name="pOrigin">True = value-origin (backward), False = value-use (forward).</param>
    /// <param name="pCap">The most rows drawn in one step; at least 1.</param>
    /// <param name="pDepth">The number of steps; at least 1.</param>
    /// <exception cref="EChartsQuestion">The index has no data_flows table, or the selection is a kind
    /// that carries no value (a procedure asked for its origin, a local, a type).</exception>
    /// <exception cref="EChartsIndex">The selection is not in the index or is ambiguous.</exception>
    constructor Create(pIndex: TChartsIndex; const pTarget: string; pOrigin: Boolean; pCap, pDepth: Integer);
    /// <summary>Frees the lists.</summary>
    destructor Destroy; override;
    /// <summary>Walks step by step, breadth first, up to the depth.</summary>
    /// <remarks>An end is followed once: a second row reaching it is drawn and marked Seen. Each step
    /// draws at most the cap; the rest is counted in HiddenOf.</remarks>
    procedure Run;
    /// <summary>The rows of one step, in the order drawn.</summary>
    /// <param name="pTier">1-based step.</param>
    /// <returns>The indexes into Hops.</returns>
    function TierHops(pTier: Integer): TArray<Integer>;
    /// <summary>Rows of a step that the cap left out.</summary>
    /// <param name="pTier">1-based step.</param>
    /// <returns>The count; 0 for a step that was not reached.</returns>
    function HiddenOf(pTier: Integer): Integer;
    /// <summary>The write (value-origin) or read (value-use) refs the index binds to the selection.</summary>
    /// <returns>The count; 0 for a parameter or a result (their sites are not refs of the selection).</returns>
    function BoundSites: Integer;
    /// <summary>How many drawn rows carry (pValue True) or lack (False) a value class.</summary>
    /// <param name="pValue">True counts val_class &lt;&gt; '' rows ONLY; False counts val_class = '' rows ONLY.</param>
    /// <returns>The count over every drawn row.</returns>
    function CountRows(pValue: Boolean): Integer;
    /// <summary>How many drawn rows carry one value class.</summary>
    /// <param name="pClass">One of the DF_VAL_* constants.</param>
    /// <returns>The count.</returns>
    function CountClass(const pClass: string): Integer;
    /// <summary>The distinct routines over every drawn row.</summary>
    /// <returns>The count.</returns>
    function Routines: Integer;
    /// <summary>Every drawn row; a hop's Parent indexes this list.</summary>
    property Hops: TList<THop> read FHops;
    /// <summary>The selection as a node.</summary>
    property Focus: TValueNode read FFocus;
    /// <summary>The selection as the index resolved it.</summary>
    property Sel: TMemberSelection read FSel;
    /// <summary>Whether the index holds value rows.</summary>
    property Tracking: TValueTracking read FTracking;
    /// <summary>True for value-origin.</summary>
    property Origin: Boolean read FOrigin;
    /// <summary>The steps asked.</summary>
    property Depth: Integer read FDepth;
    /// <summary>Ends on the last step that could be followed with a larger depth.</summary>
    property Unfollowed: Integer read FUnfollowed;
  end;

{ ---- TValueNode ---- }

class function TValueNode.Stop(const pCaption: string): TValueNode;
begin
  Result:= Default(TValueNode);
  Result.Kind:= nkEnd;
  Result.Id:= NOT_FOLLOWED;
  Result.Index:= NOT_FOLLOWED;
  Result.Caption:= pCaption;
end;

function TValueNode.Key: string;
begin
  Result:= '';
  if Kind <> nkEnd then
    Result:= Format('%d:%d:%d', [Ord(Kind), Id, Index]);
end;

{ ---- the ends of a row ---- }

/// <summary>The node of a bound symbol.</summary>
/// <param name="pId">symbols.id.</param>
/// <param name="pKind">Its kind.</param>
/// <param name="pQName">Its qualified name.</param>
/// <param name="pUnit">The unit name to strip from the caption; '' keeps the qualified name.</param>
/// <returns>A followed node for a field, variable, property or routine; else an nkEnd naming the kind.</returns>
function NodeOfSymbol(pId: Integer; const pKind, pQName, pUnit: string): TValueNode;
begin
  Result:= Default(TValueNode);
  Result.Id:= pId;
  Result.Index:= NOT_FOLLOWED;
  Result.Caption:= ShortName(pQName, pUnit);
  if SameText(pKind, K_FIELD) then
    Result.Kind:= nkField
  else if SameText(pKind, K_VAR) then
    Result.Kind:= nkGlobal
  else if SameText(pKind, K_PROPERTY) then
    Result.Kind:= nkProperty
  else if SameText(pKind, K_FUNCTION) or SameText(pKind, K_METHOD) or SameText(pKind, K_PROCEDURE) then
  begin
    Result.Kind:= nkResult;
    Result.Caption:= 'result of ' + Result.Caption;
  end
  else
    Result:= TValueNode.Stop(Format('%s %s', [pKind, ShortName(pQName, pUnit)]));
end;

/// <summary>The ref the index stores at one position, a bound one first.</summary>
/// <param name="pIndex">The open index; must not be nil.</param>
/// <param name="pFileId">files.id.</param>
/// <param name="pLine">refs.start_line.</param>
/// <param name="pCol">refs.start_col.</param>
/// <returns>The ref; Id 0 and every text '' when the index holds no ref there.</returns>
function RefAt(pIndex: TChartsIndex; pFileId, pLine, pCol: Integer): TBoundRef;
begin
  Result:= Default(TBoundRef);
  var Rows:= pIndex.Query(Format(
    'SELECT COALESCE(r.symbol_id, 0) AS sid, s.kind AS kind, s.qualified_name AS qname,' + sLineBreak +
    '       r.name_text AS name_text, r.receiver_text AS receiver_text, f.path AS path' + sLineBreak +
    '  FROM refs r LEFT JOIN symbols s ON s.id = r.symbol_id LEFT JOIN files f ON f.id = s.file_id' + sLineBreak +
    ' WHERE r.file_id = %d AND r.start_line = %d AND r.start_col = %d' + sLineBreak +
    ' ORDER BY (r.symbol_id IS NULL), r.id LIMIT 1', [pFileId, pLine, pCol]));
  try
    if Rows.Count = 0 then
      Exit;
    Result.Id:= Rows[0].I('sid');
    Result.Kind:= Rows[0].S('kind');
    Result.QName:= Rows[0].S('qname');
    if Result.Id <> 0 then
      Result.UnitName:= UnitNameOf(Rows[0].S('path'));
    Result.Text:= Rows[0].S('name_text');
    if Rows[0].S('receiver_text') <> '' then
      Result.Text:= Rows[0].S('receiver_text') + '.' + Result.Text;
  finally
    Rows.Free;
  end;
end;

/// <summary>The ref a row stores at one of its ends.</summary>
/// <param name="pIndex">The open index; must not be nil.</param>
/// <param name="pRow">One HOP_COLUMNS row.</param>
/// <param name="pEnd">END_SRC or END_DST: the column prefix of the end.</param>
/// <returns>The ref; its Text is the row's own name when the index holds no ref there.</returns>
function RowRef(pIndex: TChartsIndex; pRow: TIndexRow; const pEnd: string): TBoundRef;
begin
  Result:= RefAt(pIndex, pRow.I('file_id'), pRow.I(pEnd + '_line'), pRow.I(pEnd + '_col'));
  if Result.Text = '' then
    Result.Text:= pRow.S(pEnd + '_name');
end;

/// <summary>The field or unit variable a row names inside one routine.</summary>
/// <param name="pIndex">The open index; must not be nil.</param>
/// <param name="pRoutineId">The routine the row belongs to.</param>
/// <param name="pName">The name as the row writes it.</param>
/// <param name="pKind">K_FIELD or K_VAR.</param>
/// <returns>The node of the symbol a ref of that name binds to in the routine; an nkEnd 'by name' when
/// no ref binds (the row is then not followed: a name is not an identity).</returns>
function NamedIn(pIndex: TChartsIndex; pRoutineId: Integer; const pName, pKind: string): TValueNode;
begin
  var Rows:= pIndex.Query(Format(
    'SELECT s.id AS id, s.qualified_name AS qname, f.path AS path' + sLineBreak +
    '  FROM refs r JOIN symbols s ON s.id = r.symbol_id JOIN files f ON f.id = s.file_id' + sLineBreak +
    ' WHERE r.enclosing_symbol_id = %d AND r.name_text = ''%s'' COLLATE NOCASE AND s.kind = ''%s''' + sLineBreak +
    ' ORDER BY s.id LIMIT 1', [pRoutineId, TChartsIndex.SqlText(pName), pKind]));
  try
    if Rows.Count = 0 then
      Exit(TValueNode.Stop(Format('%s %s (by name, not bound)', [pKind, pName])));
    Result:= NodeOfSymbol(Rows[0].I('id'), pKind, Rows[0].S('qname'), UnitNameOf(Rows[0].S('path')));
    Result.Name:= pName;
  finally
    Rows.Free;
  end;
end;

/// <summary>What a parameter row prints: the routine and the parameter's declared name.</summary>
/// <param name="pIndex">The open index; must not be nil.</param>
/// <param name="pRoutineId">The routine.</param>
/// <param name="pPosition">The 0-based position.</param>
/// <param name="pRoutine">The routine's caption.</param>
/// <returns>'Routine(pName)', or 'Routine(argument N)' (1-based) when the index holds no such parameter.</returns>
function ParamCaption(pIndex: TChartsIndex; pRoutineId, pPosition: Integer; const pRoutine: string): string;
begin
  Result:= Format('%s(argument %d)', [pRoutine, pPosition + 1]);
  var Rows:= pIndex.Query(Format(
    'SELECT p.name AS name FROM symbols p WHERE p.parent_id = %d AND p.kind = ''%s'' ORDER BY p.id LIMIT 1 OFFSET %d',
    [pRoutineId, K_PARAM, pPosition]));
  try
    if Rows.Count > 0 then
      Result:= Format('%s(%s)', [pRoutine, Rows[0].S('name')]);
  finally
    Rows.Free;
  end;
end;

/// <summary>The source end of a 'ref' or 'argout' row.</summary>
/// <param name="pIndex">The open index; must not be nil.</param>
/// <param name="pRow">One HOP_COLUMNS row whose src_kind is DF_SRC_REF or DF_SRC_ARGOUT.</param>
/// <returns>The node of the bound symbol; an nkEnd for a var / out argument or an unbound ref.</returns>
function RefSource(pIndex: TChartsIndex; pRow: TIndexRow): TValueNode;
begin
  var Ref:= RowRef(pIndex, pRow, END_SRC);
  if pRow.S('src_kind') = DF_SRC_ARGOUT then
    Exit(TValueNode.Stop(Format('var/out argument %d of %s', [pRow.I('src_index') + 1, Ref.Text])));
  if Ref.Id = 0 then
    Exit(TValueNode.Stop(Ref.Text + NOT_IN_INDEX));
  Result:= NodeOfSymbol(Ref.Id, Ref.Kind, Ref.QName, Ref.UnitName);
  Result.Name:= pRow.S('src_name');
end;

/// <summary>The source end of a row (value-origin's far end).</summary>
/// <param name="pIndex">The open index; must not be nil.</param>
/// <param name="pRow">One HOP_COLUMNS row.</param>
/// <returns>The node; an nkEnd for a var / out argument, an unbound ref, or a kind this unit does not know.</returns>
function SourceOf(pIndex: TChartsIndex; pRow: TIndexRow): TValueNode;
begin
  var Kind:= pRow.S('src_kind');
  if Kind = DF_SRC_FIELD then
    Exit(NamedIn(pIndex, pRow.I('rid'), pRow.S('src_name'), K_FIELD));
  if Kind = DF_SRC_GLOBAL then
    Exit(NamedIn(pIndex, pRow.I('rid'), pRow.S('src_name'), K_VAR));
  if (Kind = DF_SRC_REF) or (Kind = DF_SRC_ARGOUT) then
    Exit(RefSource(pIndex, pRow));
  if Kind <> DF_SRC_PARAM then
    Exit(TValueNode.Stop(Format('%s %s', [Kind, pRow.S('src_name')])));
  Result:= Default(TValueNode);
  Result.Kind:= nkParam;
  Result.Id:= pRow.I('rid');
  Result.Index:= pRow.I('src_index');
  Result.Name:= pRow.S('src_name');
  Result.Caption:= Format('%s(%s)', [ShortName(pRow.S('routine'), UnitNameOf(pRow.S('path'))), Result.Name]);
end;

/// <summary>The destination end of an 'arg', 'write', 'field' or 'global' row.</summary>
/// <param name="pIndex">The open index; must not be nil.</param>
/// <param name="pRow">One HOP_COLUMNS row of one of those kinds.</param>
/// <returns>The callee's parameter for a bound argument, the bound member or variable for a write; an
/// nkEnd, by name, when the index binds nothing at the site.</returns>
function RefDestination(pIndex: TChartsIndex; pRow: TIndexRow): TValueNode;
begin
  var Ref:= RowRef(pIndex, pRow, END_DST);
  var IsArg:= pRow.S('dst_kind') = DF_DST_ARG;
  if IsArg and (Ref.Id = 0) then
    Exit(TValueNode.Stop(Format('argument %d of %s', [pRow.I('dst_index') + 1, Ref.Text]) + NOT_IN_INDEX));
  if Ref.Id = 0 then
    Exit(TValueNode.Stop(Ref.Text + NOT_IN_INDEX));
  Result:= NodeOfSymbol(Ref.Id, Ref.Kind, Ref.QName, Ref.UnitName);
  Result.Name:= pRow.S('dst_name');
  if not IsArg then
    Exit;
  Result.Kind:= nkParam;
  Result.Index:= pRow.I('dst_index');
  Result.Name:= '';
  Result.Caption:= ParamCaption(pIndex, Ref.Id, Result.Index, ShortName(Ref.QName, Ref.UnitName));
end;

/// <summary>The destination end of a row (value-use's far end).</summary>
/// <param name="pIndex">The open index; must not be nil.</param>
/// <param name="pRow">One HOP_COLUMNS row.</param>
/// <returns>The node; an nkEnd for a var / out parameter, an unbound callee or member, or a kind this
/// unit does not know (the rows of a later lane are drawn by their kind, never dropped).</returns>
function DestinationOf(pIndex: TChartsIndex; pRow: TIndexRow): TValueNode;
begin
  var Kind:= pRow.S('dst_kind');
  var Unit_:= UnitNameOf(pRow.S('path'));
  if Kind = DF_DST_RESULT then
    Exit(NodeOfSymbol(pRow.I('rid'), K_FUNCTION, pRow.S('routine'), Unit_));
  if Kind = DF_DST_OUTPARAM then
    Exit(TValueNode.Stop(Format('var/out parameter %s of %s', [pRow.S('dst_name'), ShortName(pRow.S('routine'), Unit_)])));
  if (Kind = DF_DST_ARG) or (Kind = DF_DST_WRITE) or (Kind = DF_DST_FIELD) or (Kind = DF_DST_GLOBAL) then
    Exit(RefDestination(pIndex, pRow));
  Result:= TValueNode.Stop(Format('%s %s', [Kind, pRow.S('dst_name')]));
end;

{ ---- TValueWalk ---- }

constructor TValueWalk.Create(pIndex: TChartsIndex; const pTarget: string; pOrigin: Boolean; pCap, pDepth: Integer);
begin
  inherited Create;
  FIndex:= pIndex;
  FOrigin:= pOrigin;
  FCap:= if pCap < 1 then 1 else pCap;
  FDepth:= if pDepth < 1 then 1 else pDepth;
  FHops:= TList<THop>.Create;
  FHidden:= TList<Integer>.Create;
  FVisited:= TDictionary<string, Boolean>.Create;
  ProbeTracking;
  ResolveFocus(pTarget);
end;

destructor TValueWalk.Destroy;
begin
  FVisited.Free;
  FHidden.Free;
  FHops.Free;
  inherited;
end;

/// <summary>Reads what the index holds: the table, the val_class column, any value row.</summary>
/// <exception cref="EChartsQuestion">The index has no data_flows table.</exception>
procedure TValueWalk.ProbeTracking;
begin
  var Rows:= FIndex.Query('SELECT sql AS ddl FROM sqlite_master WHERE type = ''table'' AND name = ''data_flows''');
  try
    if Rows.Count = 0 then
      raise EChartsQuestion.Create('this index has no data_flows table (built before 1.26): re-index the project, then ask again');
    FTracking:= vtNoColumn;
    FValExpr:= NO_VAL_CLASS_EXPR;
    if not ContainsText(Rows[0].S('ddl'), VAL_CLASS_COLUMN) then
      Exit;
  finally
    Rows.Free;
  end;
  FValExpr:= VAL_CLASS_EXPR;
  FTracking:= vtNoRows;
  var Any:= FIndex.Query('SELECT 1 AS n FROM data_flows d WHERE ' + Format(VALUE_ROW, [FValExpr]) + ' LIMIT 1');
  try
    if Any.Count > 0 then
      FTracking:= vtTracked;
  finally
    Any.Free;
  end;
end;

/// <summary>Resolves the selection to a node.</summary>
/// <param name="pTarget">The selection as given.</param>
/// <exception cref="EChartsQuestion">A procedure asked for its origin.</exception>
/// <exception cref="EChartsIndex">Not in the index, ambiguous, or a kind that carries no value.</exception>
procedure TValueWalk.ResolveFocus(const pTarget: string);
begin
  var Found: Boolean;
  FSel:= FIndex.ResolveMemberSelection(pTarget, [K_FIELD, K_VAR, K_PROPERTY, K_PARAM, K_FUNCTION, K_METHOD, K_PROCEDURE],
    False, 'ask about a field, a unit variable, a property, a parameter (Routine.pName) or a function', Found);
  var Unit_:= UnitNameOf(FSel.Path);
  if SameText(FSel.Kind, K_PARAM) then
  begin
    var Rows:= FIndex.Query(Format(
      'SELECT p.parent_id AS rid, r.qualified_name AS routine,' + sLineBreak +
      '       (SELECT COUNT(*) FROM symbols o WHERE o.parent_id = p.parent_id AND o.kind = ''%s'' AND o.id < p.id) AS pos' + sLineBreak +
      '  FROM symbols p JOIN symbols r ON r.id = p.parent_id WHERE p.id = %d', [K_PARAM, FSel.Id]));
    try
      if Rows.Count = 0 then
        raise EChartsQuestion.CreateFmt('%s is a parameter with no routine in this index', [FSel.QName]);
      FFocus.Kind:= nkParam;
      FFocus.Id:= Rows[0].I('rid');
      FFocus.Index:= Rows[0].I('pos');
    finally
      Rows.Free;
    end;
    FFocus.Name:= FSel.Name;
    FFocus.Caption:= ShortName(FSel.QName, Unit_);
    Exit;
  end;
  if SameText(FSel.Kind, K_PROCEDURE) and FOrigin then
    raise EChartsQuestion.CreateFmt('%s is a procedure: it returns no value -- ask value-origin about one of its parameters (%s.pName), a field or a variable',
      [FSel.QName, FSel.QName]);
  FFocus:= NodeOfSymbol(FSel.Id, FSel.Kind, FSel.QName, Unit_);
  FFocus.Name:= FSel.Name;
end;

/// <summary>The queries whose rows end in (value-origin) or start at (value-use) one node.</summary>
/// <param name="pNode">A followed node.</param>
/// <returns>One or two complete SELECT texts; their rows are merged.</returns>
/// <remarks>BOUND queries join the ref the index stores at the row's own position, so the symbol is an
/// identity, not a name. A field or variable READ inside its routine has no position in the row
/// (src_line 0): that one query matches the name within the routines that hold a bound ref of the symbol.</remarks>
function TValueWalk.HopSql(const pNode: TValueNode): TArray<string>;
begin
  var Head:= Format(HOP_COLUMNS, [FValExpr]);
  if FOrigin then
  begin
    var Where: string;
    case pNode.Kind of
      nkResult:
        Where:= Format(' WHERE d.symbol_id = %d AND d.dst_kind = ''%s''', [pNode.Id, DF_DST_RESULT]);
      nkParam:
        Where:= BOUND_DST + Format(' WHERE br.symbol_id = %d AND d.dst_kind = ''%s'' AND d.dst_index = %d',
          [pNode.Id, DF_DST_ARG, pNode.Index]);
    else
      Where:= BOUND_DST + Format(' WHERE br.symbol_id = %d AND d.dst_kind IN (''%s'', ''%s'', ''%s'')',
        [pNode.Id, DF_DST_FIELD, DF_DST_GLOBAL, DF_DST_WRITE]);
    end;
    Result:= [Head + Where + HOP_ORDER];
    Exit;
  end;
  if pNode.Kind = nkParam then
  begin
    Result:= [Head + Format(' WHERE d.symbol_id = %d AND d.src_kind = ''%s'' AND d.src_index = %d',
      [pNode.Id, DF_SRC_PARAM, pNode.Index]) + HOP_ORDER];
    Exit;
  end;
  Result:= [Head + BOUND_SRC + Format(' WHERE br.symbol_id = %d AND d.src_kind = ''%s''', [pNode.Id, DF_SRC_REF]) + HOP_ORDER];
  if pNode.Kind in [nkField, nkGlobal] then
    Result:= Result + [Head + Format(
      ' WHERE d.src_kind = ''%s'' AND d.src_name = ''%s'' COLLATE NOCASE' + sLineBreak +
      '   AND d.symbol_id IN (SELECT r.enclosing_symbol_id FROM refs r WHERE r.symbol_id = %d)',
      [if pNode.Kind = nkField then DF_SRC_FIELD else DF_SRC_GLOBAL, TChartsIndex.SqlText(pNode.Name), pNode.Id]) + HOP_ORDER];
end;

{ v156 INT (request EXT-B1F -> FB-1): since EXT-B1F a flow of a typed scalar is stored twice -- the kept
  pre-1.56 row (val_class '') and its classed twin, same routine, line and far end. The chart shows the
  classed row only; a '' row with no twin stays (string, object or unclassed). }
function DropFlowTwins(const pHops: TArray<THop>): TArray<THop>;
const
  TWIN_KEY = '%s|%s|%s|%d';
begin
  Result:= [];
  var Classed:= TDictionary<string, Integer>.Create;
  try
    for var H in pHops do
      if H.ValClass <> '' then
        Classed.AddOrSetValue(Format(TWIN_KEY, [H.Node.Key, H.Node.Caption, H.Routine, H.Line]), 0);
    for var H in pHops do
      if (H.ValClass <> '') or not Classed.ContainsKey(Format(TWIN_KEY, [H.Node.Key, H.Node.Caption, H.Routine, H.Line])) then
        Result:= Result + [H];
  finally
    Classed.Free;
  end;
end;

/// <summary>Every row of one node, identical rows merged, far ends resolved.</summary>
/// <param name="pNode">A followed node.</param>
/// <param name="pParent">The hop the rows explain; FOCUS_PARENT for the selection.</param>
/// <param name="pTier">The step the rows belong to.</param>
/// <returns>The rows in index order.</returns>
function TValueWalk.RowsOf(const pNode: TValueNode; pParent, pTier: Integer): TArray<THop>;
begin
  Result:= [];
  var Seen:= TDictionary<string, Integer>.Create;
  try
    for var Sql in HopSql(pNode) do
    begin
      var Rows:= FIndex.Query(Sql);
      try
        for var R in Rows do
        begin
          var H:= Default(THop);
          H.Node:= if FOrigin then SourceOf(FIndex, R) else DestinationOf(FIndex, R);
          H.Parent:= pParent;
          H.Tier:= pTier;
          H.Routine:= R.S('routine');
          H.Path:= R.S('path');
          H.Line:= if R.I('dst_line') > 0 then R.I('dst_line') else R.I('routine_line');
          H.ValClass:= R.S('val_class');
          H.ViaLocal:= R.I('via_local') <> 0;
          H.Cond:= R.I('cond') <> 0;
          H.Sites:= 1;
          var Same:= Format('%s|%s|%s|%s|%d', [H.Node.Key, H.Node.Caption, H.Routine, H.ValClass, H.Line]);
          var At: Integer;
          if Seen.TryGetValue(Same, At) then
          begin
            Inc(Result[At].Sites);
            Continue;
          end;
          Seen.Add(Same, Length(Result));
          Result:= Result + [H];
        end;
      finally
        Rows.Free;
      end;
    end;
  finally
    Seen.Free;
  end;
  Result:= DropFlowTwins(Result);
end;

procedure TValueWalk.Run;
begin
  FVisited.AddOrSetValue(FFocus.Key, True);
  { the nodes of the step being explained: the hop index (FOCUS_PARENT = the selection) }
  var Frontier: TArray<Integer>:= [FOCUS_PARENT];
  for var Tier:= FIRST_TIER to FDepth do
  begin
    var Next: TArray<Integer>:= [];
    var Drawn:= 0;
    var Hidden:= 0;
    for var P in Frontier do
    begin
      var Node:= if P = FOCUS_PARENT then FFocus else FHops[P].Node;
      for var H in RowsOf(Node, P, Tier) do
      begin
        if Drawn >= FCap then
        begin
          Inc(Hidden);
          Continue;
        end;
        Inc(Drawn);
        var Hop:= H;
        var Key:= Hop.Node.Key;
        if Key <> '' then
        begin
          Hop.Seen:= FVisited.ContainsKey(Key);
          FVisited.AddOrSetValue(Key, True);
        end;
        FHops.Add(Hop);
        if (Key <> '') and not Hop.Seen then
          Next:= Next + [FHops.Count - 1];
      end;
    end;
    FHidden.Add(Hidden);
    Frontier:= Next;
    if Length(Frontier) = 0 then
      Break;
  end;
  FUnfollowed:= Length(Frontier);
end;

function TValueWalk.TierHops(pTier: Integer): TArray<Integer>;
begin
  Result:= [];
  for var K:= 0 to FHops.Count - 1 do
    if FHops[K].Tier = pTier then
      Result:= Result + [K];
end;

function TValueWalk.HiddenOf(pTier: Integer): Integer;
begin
  Result:= 0;
  if InRange(pTier, FIRST_TIER, FHidden.Count) then
    Result:= FHidden[pTier - 1];
end;

function TValueWalk.BoundSites: Integer;
begin
  Result:= 0;
  if FFocus.Kind not in [nkField, nkGlobal, nkProperty] then
    Exit;
  var Rows:= FIndex.Query(Format('SELECT COUNT(*) AS n FROM refs r WHERE r.symbol_id = %d AND r.kind %s ''write''',
    [FFocus.Id, if FOrigin then '=' else '<>']));
  try
    if Rows.Count > 0 then
      Result:= Rows[0].I('n');
  finally
    Rows.Free;
  end;
end;

function TValueWalk.CountRows(pValue: Boolean): Integer;
begin
  Result:= 0;
  for var H in FHops do
    if (H.ValClass <> '') = pValue then
      Inc(Result);
end;

function TValueWalk.CountClass(const pClass: string): Integer;
begin
  Result:= 0;
  for var H in FHops do
    if H.ValClass = pClass then
      Inc(Result);
end;

function TValueWalk.Routines: Integer;
begin
  var Names:= TDictionary<string, Boolean>.Create;
  try
    for var H in FHops do
      Names.AddOrSetValue(H.Routine, True);
    Result:= Names.Count;
  finally
    Names.Free;
  end;
end;

{ ---- drawing ---- }

/// <summary>The plural s of a count.</summary>
/// <param name="pN">The count.</param>
/// <returns>'' for exactly 1, else 's'.</returns>
function PluralS(pN: Integer): string;
begin
  Result:= if pN = 1 then '' else 's';
end;

/// <summary>One drawn row.</summary>
/// <param name="pHop">The hop.</param>
/// <returns>An anchored row: the far end and its value class, the routine and what qualifies the flow as
/// the note, the whole sentence as the tooltip.</returns>
function HopRow(const pHop: THop): TDotRow;
begin
  var Caption:= pHop.Node.Caption;
  if pHop.ValClass <> '' then
    Caption:= Caption + Format(CLASS_TAG, [pHop.ValClass]);
  var Routine:= ShortName(pHop.Routine, UnitNameOf(pHop.Path));
  var Notes: TArray<string>:= ['in ' + Routine];
  if pHop.ViaLocal then
    Notes:= Notes + ['through a local'];
  if pHop.Cond then
    Notes:= Notes + ['on some paths'];
  if pHop.Sites > 1 then
    Notes:= Notes + [Format('%d rows', [pHop.Sites])];
  if pHop.Seen then
    Notes:= Notes + ['shown above, not followed again'];
  if pHop.Node.Kind = nkEnd then
    Notes:= Notes + ['not followed'];
  var ClassText:= if pHop.ValClass <> '' then 'value class ' + pHop.ValClass else 'no value class (a pre-1.56 row: string, object or unclassed)';
  Result:= TDotRow.Anchored(Caption, pHop.Line, RowHref(pHop.Path, pHop.Line),
    Format('%s -- %s:%d -- %s -- %s', [pHop.Node.Caption, FileNameOf(pHop.Path), pHop.Line, ClassText, string.Join(', ', Notes)]),
    string.Join(', ', Notes));
end;

/// <summary>What the focus says when step 1 is empty.</summary>
/// <param name="pWalk">The finished walk.</param>
/// <returns>The sentence: sites the index binds and no row (literals / constants; on an index without
/// value rows the sentence says the silence is not evidence), or no site at all.</returns>
function ZeroNote(pWalk: TValueWalk): string;
begin
  var Sites:= pWalk.BoundSites;
  if pWalk.Origin then
  begin
    if (Sites > 0) and (pWalk.Tracking <> vtTracked) then
      Exit(Format('no source row: %d write site%s in the index -- not evidence here, this index does not track numeric values',
        [Sites, PluralS(Sites)]));
    if Sites > 0 then
      Exit(Format('no source row: %d write site%s in the index, none fed by a tracked value (a literal or a constant writes no row)',
        [Sites, PluralS(Sites)]));
    Exit('no source row and no write site in this index');
  end;
  if Sites > 0 then
    Exit(Format('no destination row: %d read site%s in the index, none reaching a tracked destination (a condition or a local-only use writes no row)',
      [Sites, PluralS(Sites)]));
  Result:= 'no destination row and no read site in this index';
end;

/// <summary>What the focus says about numeric values in this index.</summary>
/// <param name="pTracking">What the probe found.</param>
/// <returns>'' when value rows exist, else the sentence that numeric values are not tracked.</returns>
function TrackingNote(pTracking: TValueTracking): string;
begin
  Result:= '';
  if pTracking = vtNoColumn then
    Result:= 'numeric, Boolean and date-time values are NOT tracked in this index (built before 1.56): string and object flows only -- re-index the project'
  else if pTracking = vtNoRows then
    Result:= 'numeric, Boolean and date-time values are NOT tracked in this index (no value row: not re-parsed by 1.56): string and object flows only -- re-index the project';
end;

/// <summary>The focus node's HTML-label table: the selection, then every disclosure the chart owes.</summary>
/// <param name="pWalk">The finished walk.</param>
/// <returns>The complete TABLE text (without the node wrapper).</returns>
function FocusTable(pWalk: TValueWalk): string;
begin
  var Sel:= pWalk.Sel;
  var Unit_:= UnitNameOf(Sel.Path);
  var Tbl:= TStringBuilder.Create;
  try
    Tbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="7">');
    Tbl.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s &#183; %s </B></FONT></TD></TR>',
      [FOCUS_HDR, FONT_SANS, XmlText(Unit_), XmlText(Sel.Kind)]));
    Tbl.Append(Format('<TR><TD HREF="%s" TITLE="%s"><FONT COLOR="%s" POINT-SIZE="18"><B>%s</B></FONT></TD></TR>',
      [RowHref(Sel.Path, Sel.FocusLine), XmlText(Format('%s  --  %s:%d', [Sel.QName, FileNameOf(Sel.Path), Sel.FocusLine])),
       FOCUS_INK, XmlText(pWalk.Focus.Caption)]));
    if Length(pWalk.TierHops(FIRST_TIER)) = 0 then
      AddDisclosureRow(Tbl, ZeroNote(pWalk), LINE_INK);
    AddDisclosureRow(Tbl, TrackingNote(pWalk.Tracking), LINE_INK);
    if pWalk.Focus.Kind = nkProperty then
      AddDisclosureRow(Tbl, 'through the property only -- ask about its backing field for the accesses that bypass it', LINE_INK);
    if pWalk.Unfollowed > 0 then
      AddDisclosureRow(Tbl, Format('stopped after %d step%s: %d end%s not followed -- ask again with a larger --depth',
        [pWalk.Depth, PluralS(pWalk.Depth), pWalk.Unfollowed, PluralS(pWalk.Unfollowed)]), LINE_INK);
    Tbl.Append('</TABLE>');
    Result:= Tbl.ToString;
  finally
    Tbl.Free;
  end;
end;

/// <summary>Appends the whole DOT text: header, one cluster per step, the focus, the edges.</summary>
/// <param name="pSb">The DOT text being built; must not be nil.</param>
/// <param name="pWalk">The finished walk.</param>
/// <returns>The number of anchored rows drawn (the focus not counted).</returns>
/// <remarks>An edge points the way the value flows: far end to near end for value-origin, near end to
/// far end for value-use. A flow on some paths only is dashed. The 'more rows' line of a step is a note
/// row and gets no edge.</remarks>
function BuildDot(pSb: TStringBuilder; pWalk: TValueWalk): Integer;
begin
  Result:= 0;
  pSb.AppendLine('digraph valueflow {');
  pSb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
  pSb.AppendLine('  nodesep=0.35; ranksep=1.3; splines=spline;');
  pSb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
  pSb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
  pSb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.5, arrowsize=0.8];', [FONT_MONO, LINE_INK]));
  pSb.AppendLine('');
  var Style:= TClusterStyle.Make(VALUE_BORDER, VALUE_FILL, VALUE_HDR);
  Style.RowInk:= ROW_INK;
  Style.LineInk:= LINE_INK;
  Style.FontSans:= FONT_SANS;
  pSb.AppendLine('  subgraph cluster_focus {');
  pSb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=3;', [FOCUS_BORDER, FOCUS_FILL]));
  pSb.AppendLine('    label=""; margin=12;');
  pSb.AppendLine(Format('    focus [label=<%s>];', [FocusTable(pWalk)]));
  pSb.AppendLine('  }');
  var Ports:= TDictionary<Integer, string>.Create;
  try
    for var Tier:= FIRST_TIER to pWalk.Depth do
    begin
      var Idx:= pWalk.TierHops(Tier);
      if Length(Idx) = 0 then
        Break;
      var Rows: TArray<TDotRow>:= [];
      for var K in Idx do
        Rows:= Rows + [HopRow(pWalk.Hops[K])];
      Inc(Result, Length(Rows));
      var Hidden:= pWalk.HiddenOf(Tier);
      if Hidden > 0 then
        Rows:= Rows + [NoteRow(Format('+%d more row%s not drawn -- ask again with a larger --cap', [Hidden, PluralS(Hidden)]))];
      var Title:= if pWalk.Origin then 'sources' else 'destinations';
      var TierPorts:= AddRowCluster(pSb, Format('cluster_t%d', [Tier]), Format('t%d', [Tier]), Format('%s, step %d', [Title, Tier]),
        Format('%d row%s', [Length(Idx), PluralS(Length(Idx))]), Rows, Style);
      for var K:= 0 to High(Idx) do
        Ports.Add(Idx[K], TierPorts[K]);
    end;
    pSb.AppendLine('');
    for var K:= 0 to pWalk.Hops.Count - 1 do
    begin
      var H:= pWalk.Hops[K];
      var Near:= if H.Parent = FOCUS_PARENT then 'focus' else Ports[H.Parent];
      var Far:= Ports[K];
      var EdgeStyle:= if H.Cond then CONDITIONAL_STYLE else SOLID_STYLE;
      if pWalk.Origin then
        pSb.AppendLine(Format('  %s -> %s [color="%s", style=%s];', [Far, Near, VALUE_BORDER, EdgeStyle]))
      else
        pSb.AppendLine(Format('  %s -> %s [color="%s", style=%s];', [Near, Far, VALUE_BORDER, EdgeStyle]));
    end;
  finally
    Ports.Free;
  end;
  pSb.AppendLine('}');
end;

/// <summary>Answers value-origin or value-use for pArgs.Target.</summary>
/// <param name="pArgs">The question; Question picks the direction, Target is a field, unit variable,
/// property, parameter (Routine.pName) or function, Cap bounds the rows of one step, Depth the steps.</param>
/// <param name="pOutDir">The bundle folder the layout files go to.</param>
/// <returns>The chart: LeftCount the step-1 rows (sources or destinations, the hidden ones included),
/// RightCount the distinct routines over every drawn row. The fields name the two row sets apart:
/// ValueRows = drawn rows with a value class, FlowRows = drawn rows without one.</returns>
/// <exception cref="EChartsQuestion">The index has no data_flows table, or the selection carries no value.</exception>
/// <exception cref="EChartsIndex">The selection is not in the index or is ambiguous.</exception>
/// <remarks>Read-only on the index. An index without value rows is answered, with the focus saying
/// that numeric values are not tracked (ValueTracking False in the fields).</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  var Origin:= SameText(pArgs.Question, VALUE_ORIGIN_ID);
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  try
    var Walk:= TValueWalk.Create(Index, pArgs.Target, Origin, pArgs.Cap, pArgs.Depth);
    try
      Walk.Run;
      var Anchored: Integer;
      var Sb:= TStringBuilder.Create;
      try
        Anchored:= BuildDot(Sb, Walk);
        var Msgs: TArray<string>;
        var Base:= TRegEx.Replace(Walk.Sel.QName, '[^A-Za-z0-9]', '_') + '_' + pArgs.Question.Replace('-', '_');
        Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, Base, Msgs);
      finally
        Sb.Free;
      end;
      var Expected:= Anchored + 1;
      var Hidden:= 0;
      for var Tier:= FIRST_TIER to Walk.Depth do
        Inc(Hidden, Walk.HiddenOf(Tier));
      Result.ClickTargets:= Result.Layout.Anchors;
      Result.AllClickable:= Result.Layout.Anchors >= Expected;
      Result.LeftCount:= Length(Walk.TierHops(FIRST_TIER)) + Walk.HiddenOf(FIRST_TIER);
      Result.RightCount:= Walk.Routines;
      Result.Fields:= [TMetaField.Str('Question', pArgs.Question), TMetaField.Str('Kind', Walk.Sel.Kind),
        TMetaField.Str('Resolved', Walk.Sel.QName), TMetaField.Int('Depth', Walk.Depth),
        TMetaField.Int('Step1', Result.LeftCount), TMetaField.Int('Rows', Walk.Hops.Count),
        TMetaField.Int('ValueRows', Walk.CountRows(True)), TMetaField.Int('FlowRows', Walk.CountRows(False)),
        TMetaField.Int('IntRows', Walk.CountClass(DF_VAL_INT)), TMetaField.Int('FloatRows', Walk.CountClass(DF_VAL_FLOAT)),
        TMetaField.Int('CurrencyRows', Walk.CountClass(DF_VAL_CURRENCY)),
        TMetaField.Int('DateTimeRows', Walk.CountClass(DF_VAL_DATETIME)), TMetaField.Int('BoolRows', Walk.CountClass(DF_VAL_BOOL)),
        TMetaField.Int('Routines', Walk.Routines), TMetaField.Int('Hidden', Hidden),
        TMetaField.Int('Unfollowed', Walk.Unfollowed), TMetaField.Bool('ValueTracking', Walk.Tracking = vtTracked),
        TMetaField.Int('ClickTargets', Result.Layout.Anchors), TMetaField.Int('Expected', Expected),
        TMetaField.Bool('AllClickable', Result.AllClickable)];
    finally
      Walk.Free;
    end;
  finally
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(VALUE_ORIGIN_ID, Emit);
  RegisterChartQuestion(VALUE_USE_ID, Emit);

end.
