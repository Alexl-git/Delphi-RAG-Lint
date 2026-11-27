unit DRagLint.Query.HappensBefore.Events;

{ drag-lint 1.52 -- lane HBEVENTS: the events of check-init (spec 5.1, rulings HB2 + HB4).

  For one target (unit variable, class var or instance field) this unit collects
    * WRITERS: every site that writes it (a `write` ref, or a member access in write mode:
      `Other.F := x`, `TC.ClassVar := x`, `UnitName.GVar := x` -- INT H-F1), with `how` (assign, assign-nil, var-arg, out-arg,
      create-into, dfm-stream) and the soft writers (unresolved, with-opaque, address-of);
      each row carries its enclosing routine and, for a DFM-bound handler, `fired_by`
      (Form.Control.Event), else the routine's callers (count + top 3);
    * USES: every read / member-access of it (or the one use at --at), with `guarded-test`
      for `Assigned(T)`, `T = nil`, `T <> nil`;
    * the NEVER-SET preconditions of spec 6.2 that the events decide.
  Read-only; reads the index (refs, symbols, data_flows, unit_uses, call_edges) and the source
  text on disk (the right side of `:=`, `@`, `with`, `absolute`, DFM event names).
  Plan docs\superpowers\plans\2026-11-17-happens-before-phase1.md, lane EVENTS. }

interface

uses
  DRagLint.Charts.Index
, DRagLint.Query.HappensBefore.Types
  ;

type
  /// <summary>One use of the target (a read or member access).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Events.pas) ?, declaration (DRagLint.Query.HappensBefore.Fields.pas) ?, DRagLint.Query.HappensBefore.Events.TCollector.Collect (DRagLint.Query.HappensBefore.Events.pas), DRagLint.Query.HappensBefore.Fields.TFieldSolver.LoadWrites (DRagLint.Query.HappensBefore.Fields.pas) ?, DRagLint.Query.HappensBefore.Fields.TFieldSolver.ReachBeforeWrite (DRagLint.Query.HappensBefore.Fields.pas) ? (+3 more)</para>
  /// <para>Used in units: DRagLint.Query.HappensBefore, DRagLint.Query.HappensBefore.Events, DRagLint.Query.HappensBefore.Fields</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbUse = record
    Site: THbSite;
    /// <summary>True for `Assigned(T)`, `T = nil`, `T &lt;&gt; nil` (and `nil = T`): the use tests
    /// the zero value itself, so it is reported, not judged as a hazard (spec 5.1 step 3).</summary>
    GuardedTest: Boolean;
  end;

  /// <summary>Everything check-init knows about one target before ordering: the target, its writers
  /// and its uses.</summary>
  /// <remarks>
  /// Writers are sorted by file, line, column; so are UseSites. A writer row with
  /// Counts = False never helps to prove SET (assign-nil and every soft writer).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Events.pas) ?, DRagLint.Query.HappensBefore.Events.TCollector.Collect (DRagLint.Query.HappensBefore.Events.pas), DRagLint.Query.HappensBefore.Events.TCollector.CollectDfmStream (DRagLint.Query.HappensBefore.Events.pas) ?, DRagLint.Query.HappensBefore.Events.TCollector.LoadTarget (DRagLint.Query.HappensBefore.Events.pas) ?, DRagLint.Query.HappensBefore.Events.TCollector.ResolveTarget (DRagLint.Query.HappensBefore.Events.pas) ? (+12 more)</para>
  /// <para>Used in units: DRagLint.Query.HappensBefore, DRagLint.Query.HappensBefore.Events, DRagLint.Query.HappensBefore.Fields</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbEvents = record
    Target: THbTarget;
    Writers: TArray<THbWriter>;
    /// <summary>The judged uses: every read / member access of the target, or only the use at
    /// --at when --at names one.</summary>
    UseSites: TArray<THbUse>;
    /// <summary>The target can be written from outside the code: a published field, or a field of
    /// a class that has a form file (DFM / RTTI streaming).</summary>
    IsPublished: Boolean;
    /// <summary>The target itself is declared `absolute` over another variable.</summary>
    AbsoluteOverlay: Boolean;
  end;

/// <summary>Resolves the target and collects its writers and uses (spec 5.1).</summary>
/// <param name="pIndex">An open index; must not be nil. Caller owns it.</param>
/// <param name="pTarget">QName (`Unit.GVar`, `Unit.TFoo.FBar`) or a unique trailing part of one
/// (`GVar`, `TFoo.FBar`); '' when only pAt names the target.</param>
/// <param name="pAt">The --at site (FileName '' when absent). File matched by full path or by
/// trailing path, Col = 0 means "the one variable on that line".</param>
/// <returns>The target, its writers and its uses.</returns>
/// <exception cref="EHbUsage">Unknown target; ambiguous target (Candidates lists each QName with
/// file:line); a target that is not a unit variable, class var or instance field (local, parameter,
/// record field, property, constant: one-line reason); --at naming no variable, several, or a
/// different one than pTarget.</exception>
/// <remarks>
/// Read-only. A member access in write mode (`Other.F := x`, `TC.ClassVar := x`,
/// `UnitName.GVar := x`) is a writer, never a use. `:= nil` and `FreeAndNil(T)` are how = assign-nil and never count (HB4: nil
/// is the zero value of every type that accepts it). A var / out argument counts (as dcc's W1036
/// does); the parameter mode comes from the callee's signature through the data_flows `arg` row,
/// or from a list of RTL intrinsics for an unresolved callee; any other unresolved callee is a
/// soft writer. A DFM-bound handler gets FiredBy (all bindings, ', '-joined) and CallerCount 0.
/// v152 HBFIX: a property whose accessor IS the target field stands for the field -- `Obj.P := x`
/// through `write F` is a counting writer, a read of P through `read F` is a use; an unresolved member
/// write `X.F := ..` / `X.P := ..` (receiver type unknown) is a soft writer.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.CheckInit (DRagLint.Query.HappensBefore.pas)</para>
/// <para>Calls: DRagLint.Query.HappensBefore.Events.TCollector.Collect, DRagLint.Query.HappensBefore.Events.TCollector.Create</para>
/// <para>Returns: C.Collect(pTarget, pAt)</para>
/// <seealso cref="DRagLint.Query.HappensBefore.Events.TCollector.Collect"/>
/// <seealso cref="DRagLint.Query.HappensBefore.Events.TCollector.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CollectEvents(const pIndex: TChartsIndex; const pTarget: string; const pAt: THbSite): THbEvents;

/// <summary>Whether the events allow the verdict NEVER-SET (spec 6.2, the parts the events decide).</summary>
/// <param name="pEvents">CollectEvents' result.</param>
/// <param name="pBlockers">Why not, when some writer exists: soft-writer (a soft writer, a published /
/// form-streamed field or an `absolute` overlay), nil-write-only (only assign-nil writers). Empty
/// when the answer is True or a counting writer exists.</param>
/// <returns>True when no writer of any kind exists and the target is neither published nor an
/// overlay. Index completeness is the solver's check, not this one.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.CheckInit (DRagLint.Query.HappensBefore.pas), DRagLint.Query.HappensBefore.Fields.TFieldSolver.Run (DRagLint.Query.HappensBefore.Fields.pas)</para>
/// <para>Returns: (Length(pEvents.Writers) = 0) and not pEvents.IsPublished and not pEvents.AbsoluteOverlay</para>
/// <para>Complexity: 10 (cyclomatic, outer body), 14 lines (full implementation)</para>
/// <para>Mutates: pBlockers (out)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HbIsNeverSet(const pEvents: THbEvents; out pBlockers: TArray<THbReason>): Boolean;

implementation

uses
  System.SysUtils
, System.Classes
, System.IOUtils
, System.StrUtils
, System.Math
, System.RegularExpressions
, System.Generics.Collections
, System.Generics.Defaults
  ;

type
  TRows = TObjectList<TIndexRow>;

  /// <summary>One read of the target, before it is sorted into uses and writer sites.</summary>
  TReadRef = record
    RefId: Int64;
    FileId: Int64;
    Path: string;
    Line, Col, EndCol: Integer;
    EnclosingId: Int64;
    Enclosing: string;
    Consumed: Boolean;
    { True once an argument rule looked at this read (it is classified once) }
    ArgHandled: Boolean;
  end;

  TCollector = class  // dl:ok high-response@dfb5 -- REVIEWED 2026-11-17 v152 HBEVENTS: one private collector per query, its methods are the steps of spec 5.1
  private
    FIndex: TChartsIndex;
    FLines: TDictionary<string, TArray<string>>;
    FBlockNames: TDictionary<Int64, string>;
    FTargetId: Int64;
    FTargetName: string;
    FTargetFileId: Int64;
    FTargetKind: string;
    FParentKind: string;
    FParentName: string;
    FParentQName: string;
    FAtRefId: Int64;
    FReads: TList<TReadRef>;
    FWriters: TList<THbWriter>;
    function Rows(const pSql: string): TRows;
    function SourceLine(const pPath: string; pLine: Integer): string;
    function BlockName(pFileId: Int64): string;
    function CandidateText(pRow: TIndexRow): string;
    procedure ResolveTarget(const pTarget: string; const pAt: THbSite; var pEvents: THbEvents);
    function ResolveName(const pTarget: string): Int64;
    function ResolveAt(const pAt: THbSite): Int64;
    procedure LoadTarget(var pEvents: THbEvents);
    function MakeSite(const pPath: string; pLine, pCol: Integer; pEnclosingId: Int64;
      const pEnclosing: string; pFileId: Int64): THbSite;
    procedure AddWriter(const pSite: THbSite; pHow: THbWriterHow; pResolved, pCounts: Boolean);
    procedure LoadReads;
    procedure CollectAssignments(pSymbolId: Int64; pAsAlias: Boolean);
    procedure ClassifyArgument(pHit, pLine, pNameCol: Integer; const pName: string; pIndex: Integer);
    function ArgumentPosition(const pRead: TReadRef; out pName: string; out pNameCol, pIndex: Integer): Boolean;
    procedure CollectArguments;
    procedure CollectAddressAndAbsolute;
    procedure CollectUnresolved;
    procedure AddSoftWriterRow(const pRow: TIndexRow);
    function WriteNames: TArray<string>;
    procedure CollectUnresolvedMemberWrites(const pUnitName: string);
    procedure CollectPropertyWrites;
    procedure CollectDfmStream(var pEvents: THbEvents);
    procedure FillFiredByAndCallers;
    function FiredByOf(pRoutineId: Int64): string;
    procedure CallersOf(pRoutineId: Int64; var pWriter: THbWriter);
    function AssignHow(const pPath: string; pLine, pEndCol: Integer): THbWriterHow;
    function IsInsideWith(const pPath: string; pFromLine, pLine: Integer): Boolean;
    function IsGuarded(const pRead: TReadRef): Boolean;
  public
    constructor Create(const pIndex: TChartsIndex);
    destructor Destroy; override;
    function Collect(const pTarget: string; const pAt: THbSite): THbEvents;
  end;

const
  { INT H-F1: ref `r` is a member access that WRITES its member (`Other.F := x`, `TC.ClassVar := x`,
    `UnitName.GVar := x`): a writer row, never a use. }
  MEMBER_WRITE_SQL = 'EXISTS (SELECT 1 FROM member_accesses m WHERE m.ref_id = r.id ' +
    'AND m.member_symbol_id = r.symbol_id AND m.mode = ''write'')';
  { Parameter positions an RTL intrinsic or VCL routine WRITES (var / out), for an unresolved callee;
    CreateForm:1 is TApplication.CreateForm(InstanceClass, var Reference). An unresolved callee with a
    position not listed here is a soft writer unless it is in VALUE_ONLY. }
  VAR_INTRINSICS: array[0..15] of string = ('CreateForm:1', 'Inc:0', 'Dec:0', 'Include:0', 'Exclude:0', 'SetLength:0',
    'Initialize:0', 'Finalize:0', 'FillChar:0', 'Move:1', 'Str:1', 'Val:1', 'Val:2', 'Insert:1', 'Delete:0',
    'AssignFile:0');
  { Unresolved callees that only read their arguments (intrinsics and the commonest RTL helpers). }
  VALUE_ONLY: array[0..29] of string = ('Assigned', 'Length', 'High', 'Low', 'SizeOf', 'Ord', 'Chr', 'Pred',
    'Succ', 'Abs', 'Odd', 'Trunc', 'Round', 'Exit', 'IntToStr', 'FloatToStr', 'BoolToStr', 'Format', 'Write',
    'Writeln', 'ShowMessage', 'Trim', 'UpperCase', 'LowerCase', 'SameText', 'CompareText', 'Copy', 'Pos',
    'StrToInt', 'StrToIntDef');
  { An unresolved callee that writes nil into its argument. }
  NIL_SETTER = 'FreeAndNil';
  VAR_LIKE_KINDS = '''var'',''field'',''local_var'',''param'',''const'',''property''';
  ARG_LOOKAHEAD_LINES = 10;
  WITH_LOOKBACK_LINES = 30;
  RHS_MAX_LINES = 3;
  ZERO_NIL = 'nil';
  MAX_TOP_CALLERS = 3;

{ ---- small helpers ---- }

function Id64(pRow: TIndexRow; const pCol: string): Int64;
begin
  Result:= StrToInt64Def(pRow.S(pCol), 0);
end;

function Sq(const pS: string): string;
begin
  Result:= '''' + TChartsIndex.SqlText(pS) + '''';
end;

function LastSegment(const pQName: string): string;
begin
  var P:= LastDelimiter('.', pQName);
  Result:= Copy(pQName, P + 1, MaxInt);
end;

function InList(const pName: string; const pList: array of string): Boolean;
begin
  for var S in pList do
    if SameText(S, pName) then Exit(True);
  Result:= False;
end;

{ The mode word ('var', 'out', 'const', 'constref' or '') of the pIndex-th (0-based) parameter in a
  signature like `(const A, B: Integer; var C: string): Boolean`; '?' when there is no such one. }
function ParamMode(const pSignature: string; pIndex: Integer): string;
begin
  Result:= '?';
  var Open:= Pos('(', pSignature);
  if Open = 0 then Exit;
  var Depth:= 0;
  var Close:= 0;
  for var K:= Open to Length(pSignature) do
  begin
    if pSignature[K] = '(' then Inc(Depth)
    else if pSignature[K] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Close:= K;
        Break;
      end;
    end;
  end;
  if Close = 0 then Exit;
  var N:= 0;
  for var Group in Copy(pSignature, Open + 1, Close - Open - 1).Split([';']) do
  begin
    var G:= Trim(Group);
    var Colon:= Pos(':', G);
    var Names:= if Colon > 0 then Copy(G, 1, Colon - 1) else G;
    var Mode:= '';
    var Words:= Trim(Names).Split([' '], TStringSplitOptions.ExcludeEmpty);
    if (Length(Words) > 1) and InList(Words[0], ['var', 'out', 'const', 'constref']) then
    begin
      Mode:= LowerCase(Words[0]);
      Names:= Copy(Trim(Names), Length(Words[0]) + 1, MaxInt);
    end;
    for var Nm in Names.Split([',']) do
    begin
      if Trim(Nm) = '' then Continue;
      if N = pIndex then Exit(Mode);
      Inc(N);
    end;
  end;
end;

{ True when pText starts with one of pPrefixes. }
function StartsWithAny(const pText: string; const pPrefixes: array of string): Boolean;
begin
  for var P in pPrefixes do
    if pText.StartsWith(P) then Exit(True);
  Result:= False;
end;

const
  { declared-type spellings (lower case) whose zero value is nil }
  NIL_TYPE_PREFIXES: array[0..5] of string = ('^', 'procedure', 'function', 'reference to', 'array of', 'class of');

{ The zero value of a type the index declares: nil for a class, interface or reference-like type,
  '(first enum value)' for an enum, '(zero-filled)' otherwise or when the index does not hold it. }
function IndexedZeroValue(const pIndex: TChartsIndex; const pType: string): string;
begin
  Result:= '(zero-filled)';
  var R:= pIndex.Query('SELECT kind, signature AS sig FROM symbols WHERE name = ' + Sq(LastSegment(pType)) +
    ' COLLATE NOCASE AND kind IN (''class'', ''interface'', ''record'', ''enum'', ''type'') LIMIT 1');
  try
    if R.Count = 0 then Exit;
    var K:= R[0].S('kind');
    var IsRef:= (K = 'class') or (K = 'interface');
    if IsRef or StartsWithAny(LowerCase(Trim(R[0].S('sig'))), NIL_TYPE_PREFIXES) then Result:= ZERO_NIL
    else if K = 'enum' then Result:= '(first enum value)';
  finally
    R.Free;
  end;
end;

{ The zero value a variable of this declared type holds until set (spec 3). }
function ZeroValueOf(const pIndex: TChartsIndex; const pType: string): string;
const
  STRINGS: array[0..7] of string = ('string', 'ansistring', 'unicodestring', 'widestring', 'shortstring',
    'rawbytestring', 'utf8string', 'tfilename');
  BOOLS: array[0..3] of string = ('boolean', 'bytebool', 'wordbool', 'longbool');
  CHARS: array[0..2] of string = ('char', 'widechar', 'ansichar');
  NUMBERS: array[0..22] of string = ('integer', 'cardinal', 'int64', 'uint64', 'nativeint', 'nativeuint',
    'byte', 'word', 'longint', 'longword', 'shortint', 'smallint', 'single', 'double', 'extended', 'currency',
    'real', 'tdatetime', 'tdate', 'ttime', 'comp', 'fixedint', 'fixeduint');
  NILS: array[0..4] of string = ('pointer', 'tobject', 'iinterface', 'iunknown', 'tclass');
begin
  var T:= Trim(pType);
  var L:= LowerCase(T);
  { PFoo / IFoo: the Delphi naming of pointer and interface types }
  var PrefixedRef:= (Length(T) > 1) and CharInSet(T[1], ['P', 'I']) and CharInSet(T[2], ['A'..'Z']);
  Result:= if InList(L, STRINGS) or L.StartsWith('string[') then ''''''
    else if InList(L, BOOLS) then 'False'
    else if InList(L, CHARS) then '#0'
    else if InList(L, NUMBERS) then '0'
    else if InList(L, NILS) or StartsWithAny(L, NIL_TYPE_PREFIXES) or PrefixedRef then ZERO_NIL
    else if T = '' then '(zero-filled)'
    else IndexedZeroValue(pIndex, T);
end;

{ ---- TCollector ---- }

constructor TCollector.Create(const pIndex: TChartsIndex);
begin
  inherited Create;
  FIndex:= pIndex;
  FLines:= TDictionary<string, TArray<string>>.Create;
  FBlockNames:= TDictionary<Int64, string>.Create;
  FReads:= TList<TReadRef>.Create;
  FWriters:= TList<THbWriter>.Create;
end;

destructor TCollector.Destroy;
begin
  FWriters.Free;
  FReads.Free;
  FBlockNames.Free;
  FLines.Free;
  inherited Destroy;
end;

function TCollector.Rows(const pSql: string): TRows;
begin
  Result:= FIndex.Query(pSql);
end;

function TCollector.SourceLine(const pPath: string; pLine: Integer): string;
var
  Lines: TArray<string>;
begin
  Result:= '';
  var Key:= LowerCase(pPath);
  if not FLines.TryGetValue(Key, Lines) then
  begin
    Lines:= [];
    try
      if TFile.Exists(pPath) then Lines:= TFile.ReadAllLines(pPath);
    except
      on EStreamError do Lines:= [];
      on EEncodingError do Lines:= [];
      on EInOutError do Lines:= [];
    end;
    FLines.Add(Key, Lines);
  end;
  if InRange(pLine, 1, Length(Lines)) then Result:= Lines[pLine - 1];
end;

{ The routine name of code outside every routine: the program (or library) block, else the unit. }
function TCollector.BlockName(pFileId: Int64): string;
begin
  if FBlockNames.TryGetValue(pFileId, Result) then Exit;
  Result:= '';
  var R:= Rows('SELECT kind, qualified_name AS q FROM symbols WHERE file_id = ' + IntToStr(pFileId) +
    ' AND kind IN (''program'', ''library'', ''package'', ''unit'') ORDER BY start_line LIMIT 1');
  try
    if R.Count > 0 then
      Result:= if R[0].S('kind') = 'unit' then R[0].S('q') + ' (unit block)' else R[0].S('q');
  finally
    R.Free;
  end;
  FBlockNames.Add(pFileId, Result);
end;

function TCollector.CandidateText(pRow: TIndexRow): string;
begin
  Result:= Format('%s (%s, %s:%d)', [pRow.S('q'), pRow.S('kind'), ExtractFileName(pRow.S('path')), pRow.I('ln')]);
end;

{ Why a resolved symbol of this kind is not a check-init target; '' when it is one. }
function UnsupportedReason(const pKind, pParentKind: string): string;
const
  VAR_PARENTS: array[0..5] of string = ('unit', 'program', 'library', 'package', 'class', 'record');
begin
  var Supported:= ((pKind = 'var') and InList(pParentKind, VAR_PARENTS)) or ((pKind = 'field') and (pParentKind <> 'record'));
  Result:= if Supported then ''
    else if pKind = 'local_var' then 'a local variable'
    else if pKind = 'param' then 'a parameter'
    else if pKind = 'const' then 'a constant'
    else if pKind = 'property' then 'a property (ask about its backing field)'
    else if pKind = 'field' then 'a record field (ask about the record variable)'
    else 'a ' + pKind;
end;

const
  TARGET_SELECT = 'SELECT s.id, s.kind, s.qualified_name AS q, s.start_line AS ln, f.path, ' +
    'COALESCE(p.kind, '''') AS pk FROM symbols s JOIN files f ON f.id = s.file_id ' +
    'LEFT JOIN symbols p ON p.id = s.parent_id ';

function TCollector.ResolveName(const pTarget: string): Int64;
begin
  var R:= Rows(TARGET_SELECT + 'WHERE s.name = ' + Sq(LastSegment(pTarget)) + ' COLLATE NOCASE AND s.kind IN (' +
    VAR_LIKE_KINDS + ') ORDER BY s.qualified_name, s.id');
  try
    var Exact:= TList<TIndexRow>.Create;
    var Pool:= TList<TIndexRow>.Create;
    var Supported:= TList<TIndexRow>.Create;
    try
      for var Row in R do
      begin
        var Q:= Row.S('q');
        if SameText(Q, pTarget) then Exact.Add(Row);
        if SameText(Q, pTarget) or EndsText('.' + pTarget, Q) then
        begin
          Pool.Add(Row);
          if UnsupportedReason(Row.S('kind'), Row.S('pk')) = '' then Supported.Add(Row);
        end;
      end;
      var Pick: TIndexRow:= nil;
      if Exact.Count = 1 then Pick:= Exact[0]
      else if Supported.Count = 1 then Pick:= Supported[0]
      else if (Supported.Count = 0) and (Pool.Count = 1) then Pick:= Pool[0];
      if Pick = nil then
      begin
        var Cands: TArray<string>:= [];
        var From:= if Supported.Count > 0 then Supported else Pool;
        for var Row in From do Cands:= Cands + [CandidateText(Row)];
        if Pool.Count = 0 then
          raise EHbUsage.CreateCandidates(Format('unknown target "%s": no variable or field of that name ' +
            'is in the index', [pTarget]), [])
        else
          raise EHbUsage.CreateCandidates(Format('ambiguous target "%s": %d candidates, name one by its ' +
            'qualified name', [pTarget, From.Count]), Cands);
      end;
      var Why:= UnsupportedReason(Pick.S('kind'), Pick.S('pk'));
      if Why <> '' then
        raise EHbUsage.CreateCandidates(Format('%s is %s: check-init judges unit variables, class vars ' +
          'and instance fields', [Pick.S('q'), Why]), []);
      Result:= Id64(Pick, 'id');
    finally
      Supported.Free;
      Pool.Free;
      Exact.Free;
    end;
  finally
    R.Free;
  end;
end;

function TCollector.ResolveAt(const pAt: THbSite): Int64;
begin
  var Want:= StringReplace(pAt.FileName, '/', '\', [rfReplaceAll]);
  var FileId: Int64:= 0;
  var Files:= Rows('SELECT id, path FROM files WHERE path LIKE ' + Sq('%' + ExtractFileName(Want)) +
    ' ORDER BY path');
  try
    var Hits: TArray<string>:= [];
    for var Row in Files do
    begin
      var P:= Row.S('path');
      if SameText(P, Want) then
      begin
        FileId:= Id64(Row, 'id');
        Hits:= [P];
        Break;
      end;
      if EndsText('\' + Want, P) or SameText(ExtractFileName(P), Want) then
      begin
        FileId:= Id64(Row, 'id');
        Hits:= Hits + [P];
      end;
    end;
    if Length(Hits) = 0 then
      raise EHbUsage.CreateCandidates(Format('--at: no indexed file matches "%s"', [pAt.FileName]), []);
    if Length(Hits) > 1 then
      raise EHbUsage.CreateCandidates(Format('--at: "%s" matches %d indexed files, give more of the path',
        [pAt.FileName, Length(Hits)]), Hits);
  finally
    Files.Free;
  end;
  var ColCond:= if pAt.Col > 0 then
    Format(' AND r.start_col <= %d AND r.end_col > %d', [pAt.Col, pAt.Col]) else '';
  var DeclCond:= if pAt.Col > 0 then
    Format(' AND s.start_col <= %d AND s.start_col + LENGTH(s.name) > %d', [pAt.Col, pAt.Col]) else '';
  var R:= Rows('SELECT DISTINCT s.id, s.kind, s.qualified_name AS q, s.start_line AS ln, f.path, ' +
    'COALESCE(p.kind, '''') AS pk, r.id AS rid, r.kind AS rk FROM refs r JOIN symbols s ON s.id = r.symbol_id ' +
    'JOIN files f ON f.id = s.file_id LEFT JOIN symbols p ON p.id = s.parent_id WHERE r.file_id = ' +
    IntToStr(FileId) + ' AND r.start_line = ' + IntToStr(pAt.Line) + ColCond + ' AND s.kind IN (' +
    VAR_LIKE_KINDS + ') UNION ' + 'SELECT s.id, s.kind, s.qualified_name, s.start_line, f.path, ' +
    'COALESCE(p.kind, ''''), 0, ''decl'' FROM symbols s JOIN files f ON f.id = s.file_id ' +
    'LEFT JOIN symbols p ON p.id = s.parent_id WHERE s.file_id = ' + IntToStr(FileId) +
    ' AND s.start_line = ' + IntToStr(pAt.Line) + DeclCond + ' AND s.kind IN (' + VAR_LIKE_KINDS + ')');
  try
    var Ids:= TList<Int64>.Create;
    try
      var Cands: TArray<string>:= [];
      for var Row in R do
        if not Ids.Contains(Id64(Row, 'id')) then
        begin
          Ids.Add(Id64(Row, 'id'));
          Cands:= Cands + [CandidateText(Row)];
        end;
      if Ids.Count = 0 then
        raise EHbUsage.CreateCandidates(Format('--at %s:%d%s names no variable or field',
          [pAt.FileName, pAt.Line, if pAt.Col > 0 then ':' + IntToStr(pAt.Col) else '']), []);
      if Ids.Count > 1 then
        raise EHbUsage.CreateCandidates(Format('--at %s:%d names %d variables; add the column',
          [pAt.FileName, pAt.Line, Ids.Count]), Cands);
      for var Row in R do
      begin
        var Why:= UnsupportedReason(Row.S('kind'), Row.S('pk'));
        if Why <> '' then
          raise EHbUsage.CreateCandidates(Format('%s is %s: check-init judges unit variables, class vars ' +
            'and instance fields', [Row.S('q'), Why]), []);
        var RK:= Row.S('rk');
        if (RK = 'read') or (RK = 'member-access') then FAtRefId:= Id64(Row, 'rid');
      end;
      Result:= Ids[0];
    finally
      Ids.Free;
    end;
  finally
    R.Free;
  end;
end;

procedure TCollector.ResolveTarget(const pTarget: string; const pAt: THbSite; var pEvents: THbEvents);
begin
  var ByName: Int64:= 0;
  var ByAt: Int64:= 0;
  if pTarget <> '' then ByName:= ResolveName(pTarget);
  if pAt.FileName <> '' then ByAt:= ResolveAt(pAt);
  if (ByName <> 0) and (ByAt <> 0) and (ByName <> ByAt) then
  begin
    var R:= Rows('SELECT qualified_name AS q FROM symbols WHERE id = ' + IntToStr(ByAt));
    try
      raise EHbUsage.CreateCandidates(Format('--at names %s, not %s', [R[0].S('q'), pTarget]), []);
    finally
      R.Free;
    end;
  end;
  FTargetId:= if ByName <> 0 then ByName else ByAt;
  LoadTarget(pEvents);
end;

procedure TCollector.LoadTarget(var pEvents: THbEvents);
begin
  var R:= Rows('SELECT s.kind, s.name, s.qualified_name AS q, s.signature AS sig, s.modifiers AS md, ' +
    's.section AS sec, s.vis_explicit AS vx, s.start_line AS ln, s.file_id AS fid, f.path, ' +
    'COALESCE(p.kind, '''') AS pk, COALESCE(p.name, '''') AS pn, COALESCE(p.qualified_name, '''') AS pq ' +
    'FROM symbols s JOIN files f ON f.id = s.file_id LEFT JOIN symbols p ON p.id = s.parent_id ' +
    'WHERE s.id = ' + IntToStr(FTargetId));
  try
    var Row:= R[0];
    FTargetName:= Row.S('name');
    FTargetFileId:= Id64(Row, 'fid');
    FTargetKind:= Row.S('kind');
    FParentKind:= Row.S('pk');
    FParentName:= Row.S('pn');
    FParentQName:= Row.S('pq');
    pEvents.Target.QName:= Row.S('q');
    pEvents.Target.SymbolId:= FTargetId;
    pEvents.Target.FileName:= Row.S('path');
    pEvents.Target.Line:= Row.I('ln');
    pEvents.Target.Kind:= if FTargetKind = 'field' then htkInstanceField
      else if (FParentKind = 'class') or (FParentKind = 'record') then htkClassVar
      else htkUnitVar;
    pEvents.Target.TypeName:= Trim(Row.S('sig'));
    pEvents.Target.ZeroValue:= ZeroValueOf(FIndex, pEvents.Target.TypeName);
    pEvents.IsPublished:= ContainsText(Row.S('md'), 'published') or SameText(Row.S('sec'), 'published');
    pEvents.AbsoluteOverlay:= TRegEx.IsMatch(SourceLine(Row.S('path'), Row.I('ln')),
      '\b' + FTargetName + '\b[^;]*\babsolute\b', [roIgnoreCase]);
    if (FTargetKind = 'field') and (Row.I('vx') = 0) then
    begin
      { a field before the first visibility word of a form class is published (DFM streams it) }
      var F:= Rows('SELECT COUNT(*) AS n FROM symbols WHERE kind = ''form'' AND signature = ' +
        Sq(FParentName) + ' COLLATE NOCASE');
      try
        if F[0].I('n') > 0 then pEvents.IsPublished:= True;
      finally
        F.Free;
      end;
    end;
  finally
    R.Free;
  end;
end;

function TCollector.MakeSite(const pPath: string; pLine, pCol: Integer; pEnclosingId: Int64;
  const pEnclosing: string; pFileId: Int64): THbSite;
begin
  Result:= Default(THbSite);
  Result.FileName:= pPath;
  Result.Line:= pLine;
  Result.Col:= pCol;
  Result.RoutineId:= pEnclosingId;
  Result.Routine:= if pEnclosingId <> 0 then pEnclosing else BlockName(pFileId);
end;

procedure TCollector.AddWriter(const pSite: THbSite; pHow: THbWriterHow; pResolved, pCounts: Boolean);
begin
  var W:= Default(THbWriter);
  W.Site:= pSite;
  W.How:= pHow;
  W.Resolved:= pResolved;
  W.Counts:= pCounts;
  FWriters.Add(W);
end;

{ assign-nil when the right side of the `:=` after the target is the literal nil, create-into for
  `TX.Create`, else assign. Reads at most RHS_MAX_LINES lines from the end of the target name. }
function TCollector.AssignHow(const pPath: string; pLine, pEndCol: Integer): THbWriterHow;
begin
  Result:= hwAssign;
  var Text:= Copy(SourceLine(pPath, pLine), pEndCol, MaxInt);
  for var K:= 1 to RHS_MAX_LINES - 1 do Text:= Text + ' ' + SourceLine(pPath, pLine + K);
  var M:= TRegEx.Match(Text, '^\s*:=\s*(.*)$', [roIgnoreCase, roSingleLine]);
  if not M.Success then Exit;
  var Rhs:= M.Groups[1].Value;
  if TRegEx.IsMatch(Rhs, '^nil\s*(;|$|end\b|else\b|//|\{|\(\*)', [roIgnoreCase]) then Result:= hwAssignNil
  else if TRegEx.IsMatch(Rhs, '^[A-Za-z_][\w.]*(<[^>]*>)?\.Create\b', [roIgnoreCase]) then Result:= hwCreateInto;
end;

procedure TCollector.LoadReads;
begin
  var R:= Rows('SELECT r.id, r.file_id AS fid, f.path, r.start_line AS ln, r.start_col AS col, ' +
    'r.end_col AS ecol, COALESCE(r.enclosing_symbol_id, 0) AS enc, COALESCE(e.qualified_name, '''') AS encq, ' +
    'CASE WHEN r.symbol_id = ' + IntToStr(FTargetId) + ' THEN 0 ELSE 1 END AS isprop ' +
    'FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id ' +
    'WHERE (r.symbol_id = ' + IntToStr(FTargetId) + ' AND r.kind IN (''read'', ''member-access'') ' +
    'AND NOT ' + MEMBER_WRITE_SQL + ') ' +
    { v152 HBFIX: a read of a `read <field>` property reads the target }
    'OR r.id IN (SELECT pa.ref_id FROM member_accesses pa WHERE pa.accessor_symbol_id = ' + IntToStr(FTargetId) +
    ' AND pa.accessor_kind = ''field'' AND pa.mode = ''read'' AND pa.member_symbol_id <> ' + IntToStr(FTargetId) +
    ') ORDER BY f.path, r.start_line, r.start_col, r.id');
  try
    for var Row in R do
    begin
      var Rd:= Default(TReadRef);
      Rd.RefId:= Id64(Row, 'id');
      Rd.FileId:= Id64(Row, 'fid');
      Rd.Path:= Row.S('path');
      Rd.Line:= Row.I('ln');
      Rd.Col:= Row.I('col');
      Rd.EndCol:= Row.I('ecol');
      Rd.EnclosingId:= Id64(Row, 'enc');
      Rd.Enclosing:= Row.S('encq');
      { v152 HBFIX: a property cannot be a var / out argument, so a property read is never one }
      Rd.ArgHandled:= Row.I('isprop') <> 0;
      { one row per position: a read and a member-access of the same name are one use }
      var Dup:= False;
      for var Prev in FReads do
        if (Prev.FileId = Rd.FileId) and (Prev.Line = Rd.Line) and (Prev.Col = Rd.Col) then Dup:= True;
      if not Dup then FReads.Add(Rd);
    end;
  finally
    R.Free;
  end;
end;

procedure TCollector.CollectAssignments(pSymbolId: Int64; pAsAlias: Boolean);
begin
  var R:= Rows('SELECT r.file_id AS fid, f.path, r.start_line AS ln, r.start_col AS col, ' +
    'r.end_line AS eln, r.end_col AS ecol, COALESCE(r.enclosing_symbol_id, 0) AS enc, ' +
    'COALESCE(e.qualified_name, '''') AS encq FROM refs r JOIN files f ON f.id = r.file_id ' +
    'LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id WHERE r.symbol_id = ' + IntToStr(pSymbolId) +
    ' AND (r.kind = ''write'' OR ' + MEMBER_WRITE_SQL + ')');
  try
    for var Row in R do
    begin
      var Site:= MakeSite(Row.S('path'), Row.I('ln'), Row.I('col'), Id64(Row, 'enc'), Row.S('encq'), Id64(Row, 'fid'));
      if pAsAlias then
        AddWriter(Site, hwAddressOf, False, False)
      else
      begin
        var How:= AssignHow(Row.S('path'), Row.I('eln'), Row.I('ecol'));
        AddWriter(Site, How, True, How <> hwAssignNil);
      end;
    end;
  finally
    R.Free;
  end;
end;

{ Classifies FReads[pHit] as argument pIndex (0-based) of the call named pName at pLine:pNameCol:
  a var / out parameter, FreeAndNil or a writing intrinsic adds a writer and consumes the read (it
  is no use); an unresolved callee that is not a known value-only one adds a soft writer and the
  read stays a use. }
procedure TCollector.ClassifyArgument(pHit, pLine, pNameCol: Integer; const pName: string; pIndex: Integer);
begin
  var Rd:= FReads[pHit];
  Rd.ArgHandled:= True;
  var Callee:= Rows('SELECT COALESCE(s.signature, s2.signature, '''') AS sig, ' +
    'COALESCE(r.symbol_id, c.target_symbol_id, 0) AS sid FROM refs r LEFT JOIN symbols s ON s.id = r.symbol_id ' +
    'LEFT JOIN call_edges c ON c.ref_id = r.id LEFT JOIN symbols s2 ON s2.id = c.target_symbol_id ' +
    'WHERE r.file_id = ' + IntToStr(Rd.FileId) + ' AND r.kind = ''call'' AND r.start_line = ' + IntToStr(pLine) +
    ' AND r.name_text = ' + Sq(pName) + ' COLLATE NOCASE ORDER BY ABS(r.start_col - ' + IntToStr(pNameCol) +
    ') LIMIT 1');
  try
    if Callee.Count = 0 then
    begin
      FReads[pHit]:= Rd;
      Exit; { not a call (a typecast, a set or array constructor): the read stays a use }
    end;
    var Site:= MakeSite(Rd.Path, Rd.Line, Rd.Col, Rd.EnclosingId, Rd.Enclosing, Rd.FileId);
    var Resolved:= Id64(Callee[0], 'sid') <> 0;
    var Mode:= if Resolved then ParamMode(Callee[0].S('sig'), pIndex) else '';
    if SameText(pName, NIL_SETTER) then AddWriter(Site, hwAssignNil, True, False)
    else if Resolved and (Mode = 'var') then AddWriter(Site, hwVarArg, True, True)
    else if Resolved and (Mode = 'out') then AddWriter(Site, hwOutArg, True, True)
    else if (not Resolved) and InList(pName + ':' + IntToStr(pIndex), VAR_INTRINSICS) then
      AddWriter(Site, hwVarArg, True, True)
    else
    begin
      if not Resolved and not InList(pName, VALUE_ONLY) then AddWriter(Site, hwUnresolved, False, False);
      FReads[pHit]:= Rd;
      Exit;
    end;
    Rd.Consumed:= True;
    FReads[pHit]:= Rd;
  finally
    Callee.Free;
  end;
end;

{ Whether the read is a bare argument `F(.., T, ..)` on its own line; pName / pNameCol name the
  callee spelling before the `(`, pIndex is the argument's 0-based position. }
function TCollector.ArgumentPosition(const pRead: TReadRef; out pName: string; out pNameCol, pIndex: Integer): Boolean;
begin
  Result:= False;
  pName:= '';
  pNameCol:= 0;
  pIndex:= 0;
  var Line:= SourceLine(pRead.Path, pRead.Line);
  var Before:= Copy(Line, 1, pRead.Col - 1);
  if not TRegEx.IsMatch(Before, '[(,]\s*$') then Exit;
  if not TRegEx.IsMatch(Copy(Line, pRead.EndCol, MaxInt), '^\s*[,)]') then Exit;
  var Depth:= 0;
  var Open:= 0;
  for var K:= Length(Before) downto 1 do
  begin
    var C:= Before[K];
    if C = ')' then Inc(Depth)
    else if C = '(' then
    begin
      if Depth = 0 then
      begin
        Open:= K;
        Break;
      end;
      Dec(Depth);
    end
    else if (C = ',') and (Depth = 0) then Inc(pIndex);
  end;
  if Open = 0 then Exit;
  var M:= TRegEx.Match(Copy(Before, 1, Open - 1), '([A-Za-z_]\w*)\s*$');
  if not M.Success then Exit;
  pName:= M.Groups[1].Value;
  pNameCol:= M.Groups[1].Index;
  Result:= True;
end;

{ var / out arguments, FreeAndNil, unresolved callees: from the data_flows `arg` rows of the target's
  name, then from the source text for every read that is a bare argument no row covered (the
  program block and some routines carry no data_flows rows).

  1.56 FB-2 (REQUESTS line 47, EXT-B1): since B3 the index also holds VALUE rows (val_class int / float /
  currency / datetime / bool). They are left out here, deliberately: the rows with val_class '' are
  exactly the pre-1.56 row set, so a numeric target is classified by the source-text pass below as it
  was in 1.55. Read without the condition, one call site can return two rows for one argument, and the
  second row takes the NEXT read of the target for an argument of the same call -- a plain read then
  becomes a var-arg writer. An index written before 1.56 has no such column and no such rows.
  For the same reason the 1.56 source kinds `dsfield` (a dataset field, lane EXT-B3) and `except` (a
  caught exception, lane EXT-B2) are left out: such a source is no read of the target, even when it
  carries the target's name. With the dst_kind = 'arg' condition this is the pre-1.56 row set. }
procedure TCollector.CollectArguments;
begin
  var Probe:= Rows('SELECT COUNT(*) AS n FROM sqlite_master WHERE type = ''table'' AND name = ''data_flows'' ' +
    'AND sql LIKE ''%val_class%''');
  var OnlyFlowRows:= '';
  try
    if (Probe.Count > 0) and (Probe[0].I('n') > 0) then OnlyFlowRows:= ' AND d.val_class = ''''';
  finally
    Probe.Free;
  end;
  var R:= Rows('SELECT d.file_id AS fid, d.symbol_id AS enc, d.dst_line AS dl, d.dst_col AS dc, ' +
    'd.dst_index AS di, d.dst_name AS dn FROM data_flows d WHERE d.dst_kind = ''arg'' AND d.src_name = ' +
    Sq(FTargetName) + ' COLLATE NOCASE AND d.src_kind NOT IN (''dsfield'', ''except'')' + OnlyFlowRows +
    ' ORDER BY d.file_id, d.dst_line, d.dst_col, d.dst_index');
  try
    for var Row in R do
    begin
      var FileId:= Id64(Row, 'fid');
      var Enc:= Id64(Row, 'enc');
      var DLine:= Row.I('dl');
      var DCol:= Row.I('dc');
      { the read of the target that is this argument: the first unhandled one after the call }
      for var K:= 0 to FReads.Count - 1 do
      begin
        var Rd:= FReads[K];
        if Rd.ArgHandled or (Rd.FileId <> FileId) or ((Rd.EnclosingId <> Enc) and (Rd.EnclosingId <> 0)) then Continue;
        if (Rd.Line < DLine) or ((Rd.Line = DLine) and (Rd.Col <= DCol)) or (Rd.Line > DLine + ARG_LOOKAHEAD_LINES) then
          Continue;
        ClassifyArgument(K, DLine, DCol, Row.S('dn'), Row.I('di'));
        Break;
      end;
    end;
  finally
    R.Free;
  end;
  for var K:= 0 to FReads.Count - 1 do
  begin
    var Name: string;
    var NameCol, Index: Integer;
    if not FReads[K].ArgHandled and ArgumentPosition(FReads[K], Name, NameCol, Index) then
      ClassifyArgument(K, FReads[K].Line, NameCol, Name, Index);
  end;
end;

{ `@T` / `Addr(T)` reads are address-of soft writers; a read on an `X: T absolute Target` line names an
  alias whose writes are soft writers of the target. }
procedure TCollector.CollectAddressAndAbsolute;
begin
  for var K:= 0 to FReads.Count - 1 do
  begin
    var Rd:= FReads[K];
    if Rd.Consumed then Continue;
    var Line:= SourceLine(Rd.Path, Rd.Line);
    var Before:= Copy(Line, 1, Rd.Col - 1);
    if TRegEx.IsMatch(Before, '(@|\bAddr\s*\()\s*$', [roIgnoreCase]) then
    begin
      AddWriter(MakeSite(Rd.Path, Rd.Line, Rd.Col, Rd.EnclosingId, Rd.Enclosing, Rd.FileId), hwAddressOf, False, False);
      Rd.Consumed:= True;
      FReads[K]:= Rd;
      Continue;
    end;
    if (Rd.EnclosingId <> 0) or not TRegEx.IsMatch(Before, '\babsolute\s*$', [roIgnoreCase]) then Continue;
    var A:= Rows('SELECT id FROM symbols WHERE file_id = ' + IntToStr(Rd.FileId) + ' AND start_line = ' +
      IntToStr(Rd.Line) + ' AND kind = ''var'' AND id <> ' + IntToStr(FTargetId) + ' ORDER BY start_col');
    try
      for var Alias in A do CollectAssignments(Id64(Alias, 'id'), True);
    finally
      A.Free;
    end;
    Rd.Consumed:= True;
    FReads[K]:= Rd;
  end;
end;

function TCollector.IsInsideWith(const pPath: string; pFromLine, pLine: Integer): Boolean;
begin
  Result:= False;
  var From:= if pFromLine > 0 then pFromLine else pLine - WITH_LOOKBACK_LINES;
  if From < 1 then From:= 1;
  for var L:= From to pLine do
    if TRegEx.IsMatch(SourceLine(pPath, L), '\bwith\b', [roIgnoreCase]) then Exit(True);
end;

{ A soft writer from a row with path, ln, col, enc, encq, fid, ist: with-opaque inside a with, else unresolved. }
procedure TCollector.AddSoftWriterRow(const pRow: TIndexRow);
begin
  var How:= if IsInsideWith(pRow.S('path'), pRow.I('ist'), pRow.I('ln')) then hwWithOpaque else hwUnresolved;
  AddWriter(MakeSite(pRow.S('path'), pRow.I('ln'), pRow.I('col'), Id64(pRow, 'enc'), pRow.S('encq'), Id64(pRow, 'fid')),
    How, False, False);
end;

{ Writes of the target's NAME that resolved to no symbol, in its own file or a file that uses its unit. }
procedure TCollector.CollectUnresolved;
begin
  var UnitName:= '';
  var U:= Rows('SELECT qualified_name AS q FROM symbols WHERE file_id = ' + IntToStr(FTargetFileId) +
    ' AND kind IN (''unit'', ''program'', ''library'', ''package'') LIMIT 1');
  try
    if U.Count > 0 then UnitName:= U[0].S('q');
  finally
    U.Free;
  end;
  var R:= Rows('SELECT r.file_id AS fid, f.path, r.start_line AS ln, r.start_col AS col, ' +
    'COALESCE(r.enclosing_symbol_id, 0) AS enc, COALESCE(e.qualified_name, '''') AS encq, ' +
    'COALESCE(e.impl_start_line, e.start_line, 0) AS ist FROM refs r JOIN files f ON f.id = r.file_id ' +
    'LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id WHERE r.kind = ''write'' AND r.symbol_id IS NULL ' +
    'AND r.name_text = ' + Sq(FTargetName) + ' COLLATE NOCASE AND (r.file_id = ' + IntToStr(FTargetFileId) +
    ' OR r.file_id IN (SELECT file_id FROM unit_uses WHERE target_file_id = ' + IntToStr(FTargetFileId) +
    ' OR unit_name = ' + Sq(UnitName) + ' COLLATE NOCASE)) ORDER BY f.path, r.start_line, r.start_col');
  try
    for var Row in R do AddSoftWriterRow(Row);
  finally
    R.Free;
  end;
  if FTargetKind = 'field' then CollectUnresolvedMemberWrites(UnitName);
end;

{ v152 HBFIX H1: the names a member write of the target can carry -- the field's own name and every
  property of its class whose `write` accessor is the field (read from the property-spec refs). }
function TCollector.WriteNames: TArray<string>;
begin
  Result:= [FTargetName];
  var R:= Rows('SELECT p.name AS pn, f.path, r.start_line AS ln, r.start_col AS col FROM refs r ' +
    'JOIN symbols p ON p.file_id = r.file_id AND p.kind = ''property'' AND r.start_line BETWEEN p.start_line AND ' +
    'p.end_line JOIN files f ON f.id = r.file_id WHERE r.kind = ''property-spec'' AND r.symbol_id = ' +
    IntToStr(FTargetId) + ' ORDER BY p.id, r.start_col');
  try
    for var Row in R do
    begin
      var Before:= Copy(SourceLine(Row.S('path'), Row.I('ln')), 1, Row.I('col') - 1);
      if TRegEx.IsMatch(Before, '\bwrite\s+$', [roIgnoreCase]) and
        not TArray.Contains<string>(Result, Row.S('pn')) then Result:= Result + [Row.S('pn')];
    end;
  finally
    R.Free;
  end;
end;

{ v152 HBFIX H1: `X.Name := ..` whose member did not resolve (the receiver's type is unknown), Name being
  the field or a `write <field>` property: it may write the target, so it is a soft writer (forbids
  NEVER-SET, never helps prove SET). The `:=` is read from the source after the member name. }
procedure TCollector.CollectUnresolvedMemberWrites(const pUnitName: string);
begin
  var Names:= '';
  for var N in WriteNames do Names:= Names + (if Names = '' then '' else ', ') + Sq(N);
  var R:= Rows('SELECT r.file_id AS fid, f.path, r.start_line AS ln, r.start_col AS col, r.end_line AS eln, ' +
    'r.end_col AS ecol, COALESCE(r.enclosing_symbol_id, 0) AS enc, COALESCE(e.qualified_name, '''') AS encq, ' +
    'COALESCE(e.impl_start_line, e.start_line, 0) AS ist FROM refs r JOIN files f ON f.id = r.file_id ' +
    'LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id WHERE r.kind = ''member-access'' AND ' +
    'r.symbol_id IS NULL AND r.name_text COLLATE NOCASE IN (' + Names + ') AND (r.file_id = ' +
    IntToStr(FTargetFileId) + ' OR r.file_id IN (SELECT file_id FROM unit_uses WHERE target_file_id = ' +
    IntToStr(FTargetFileId) + ' OR unit_name = ' + Sq(pUnitName) + ' COLLATE NOCASE)) ' +
    'ORDER BY f.path, r.start_line, r.start_col');
  try
    for var Row in R do
    begin
      var After:= Copy(SourceLine(Row.S('path'), Row.I('eln')), Row.I('ecol'), MaxInt);
      if TRegEx.IsMatch(After, '^\s*:=') then AddSoftWriterRow(Row);
    end;
  finally
    R.Free;
  end;
end;

{ v152 HBFIX H1: a write of a property whose write accessor IS the target field (`property P read F
  write F`; `Obj.P:= ..` or `P:= ..`) writes the target. The ref names the property, so
  CollectAssignments never sees it. A setter METHOD needs nothing here: the call edge to the setter
  carries the write. }
procedure TCollector.CollectPropertyWrites;
begin
  var R:= Rows('SELECT r.file_id AS fid, f.path, r.start_line AS ln, r.start_col AS col, ' +
    'r.end_line AS eln, r.end_col AS ecol, COALESCE(r.enclosing_symbol_id, 0) AS enc, ' +
    'COALESCE(e.qualified_name, '''') AS encq FROM member_accesses m JOIN refs r ON r.id = m.ref_id ' +
    'JOIN files f ON f.id = r.file_id LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id ' +
    'WHERE m.accessor_symbol_id = ' + IntToStr(FTargetId) + ' AND m.accessor_kind = ''field'' ' +
    'AND m.mode = ''write'' AND m.member_symbol_id <> ' + IntToStr(FTargetId) +
    ' ORDER BY f.path, r.start_line, r.start_col, r.id');
  try
    for var Row in R do
    begin
      var Site:= MakeSite(Row.S('path'), Row.I('ln'), Row.I('col'), Id64(Row, 'enc'), Row.S('encq'), Id64(Row, 'fid'));
      var How:= AssignHow(Row.S('path'), Row.I('eln'), Row.I('ecol'));
      AddWriter(Site, How, True, How <> hwAssignNil);
    end;
  finally
    R.Free;
  end;
end;

{ A field of a form class with a component of the same name in the form file is set by DFM
  streaming (inside the constructor, before OnCreate). }
procedure TCollector.CollectDfmStream(var pEvents: THbEvents);
begin
  if FTargetKind <> 'field' then Exit;
  var R:= Rows('SELECT c.start_line AS ln, c.start_col AS col, c.file_id AS fid, f.path, fm.name AS form ' +
    'FROM symbols fm JOIN symbols c ON c.file_id = fm.file_id AND c.kind = ''component'' ' +
    'JOIN files f ON f.id = fm.file_id WHERE fm.kind = ''form'' AND fm.signature = ' + Sq(FParentName) +
    ' COLLATE NOCASE AND c.name = ' + Sq(FTargetName) + ' COLLATE NOCASE ORDER BY f.path, c.start_line');
  try
    for var Row in R do
    begin
      var Site:= MakeSite(Row.S('path'), Row.I('ln'), Row.I('col'), 0, '', Id64(Row, 'fid'));
      Site.Routine:= FParentQName + ' (DFM streaming of ' + Row.S('form') + ')';
      AddWriter(Site, hwDfmStream, True, True);
      pEvents.IsPublished:= True;
      pEvents.Target.ZeroValue:= ZERO_NIL; { a streamed component field holds an object reference }
    end;
  finally
    R.Free;
  end;
end;

{ `Form.Control.Event` for every DFM binding of a handler method, ', '-joined; '' for none. }
function TCollector.FiredByOf(pRoutineId: Int64): string;
begin
  Result:= '';
  var M:= Rows('SELECT s.name, COALESCE(p.name, '''') AS pn, COALESCE(p.kind, '''') AS pk FROM symbols s ' +
    'LEFT JOIN symbols p ON p.id = s.parent_id WHERE s.id = ' + IntToStr(pRoutineId));
  try
    if (M.Count = 0) or (M[0].S('pk') <> 'class') then Exit;
    var B:= Rows('SELECT fm.name AS form, b.start_line AS ln, b.start_col AS col, f.path, ' +
      '(SELECT c.name FROM symbols c WHERE c.file_id = fm.file_id AND c.kind = ''component'' AND ' +
      'c.start_line <= b.start_line AND c.end_line >= b.start_line ORDER BY c.start_line DESC LIMIT 1) AS ctl ' +
      'FROM symbols fm JOIN refs b ON b.file_id = fm.file_id AND b.kind = ''event-binding'' ' +
      'JOIN files f ON f.id = fm.file_id WHERE fm.kind = ''form'' AND fm.signature = ' + Sq(M[0].S('pn')) +
      ' COLLATE NOCASE AND b.name_text = ' + Sq(M[0].S('name')) + ' COLLATE NOCASE ORDER BY f.path, b.start_line');
    try
      for var Row in B do
      begin
        var Ev:= Trim(Copy(SourceLine(Row.S('path'), Row.I('ln')), 1, Row.I('col') - 1));
        if Ev.EndsWith('=') then Ev:= Trim(Copy(Ev, 1, Length(Ev) - 1));
        if Ev = '' then Ev:= '?';
        var Ctl:= Row.S('ctl');
        var One:= Row.S('form') + '.' + (if Ctl <> '' then Ctl + '.' else '') + Ev;
        Result:= if Result = '' then One else Result + ', ' + One;
      end;
    finally
      B.Free;
    end;
  finally
    M.Free;
  end;
end;

procedure TCollector.CallersOf(pRoutineId: Int64; var pWriter: THbWriter);
begin
  var Id:= IntToStr(pRoutineId);
  var R:= Rows('SELECT enc, fid, COALESCE(encq, '''') AS encq, COUNT(*) AS n FROM (' +
    'SELECT COALESCE(r.enclosing_symbol_id, 0) AS enc, r.file_id AS fid, e.qualified_name AS encq FROM refs r ' +
    'LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id WHERE r.kind = ''call'' AND r.symbol_id = ' + Id +
    ' UNION ALL SELECT COALESCE(r.enclosing_symbol_id, 0), r.file_id, e.qualified_name FROM call_edges c ' +
    'JOIN refs r ON r.id = c.ref_id LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id ' +
    'WHERE c.target_symbol_id = ' + Id + ' AND (r.symbol_id IS NULL OR r.symbol_id <> ' + Id + ')) ' +
    'GROUP BY enc, CASE WHEN enc = 0 THEN fid ELSE 0 END');
  try
    var Names:= TList<TPair<string, Integer>>.Create;
    try
      for var Row in R do
      begin
        var Nm:= if Id64(Row, 'enc') <> 0 then Row.S('encq') else BlockName(Id64(Row, 'fid'));
        Names.Add(TPair<string, Integer>.Create(Nm, Row.I('n')));
      end;
      Names.Sort(TComparer<TPair<string, Integer>>.Construct(
        function(const pL, pR: TPair<string, Integer>): Integer
        begin
          Result:= pR.Value - pL.Value;
          if Result = 0 then Result:= CompareText(pL.Key, pR.Key);
        end));
      pWriter.CallerCount:= Names.Count;
      pWriter.TopCallers:= [];
      for var K:= 0 to Names.Count - 1 do
        if K < MAX_TOP_CALLERS then pWriter.TopCallers:= pWriter.TopCallers + [Names[K].Key];
    finally
      Names.Free;
    end;
  finally
    R.Free;
  end;
end;

procedure TCollector.FillFiredByAndCallers;
begin
  var Fired:= TDictionary<Int64, string>.Create;
  try
    for var K:= 0 to FWriters.Count - 1 do
    begin
      var W:= FWriters[K];
      if W.Site.RoutineId = 0 then Continue;
      var F: string;
      if not Fired.TryGetValue(W.Site.RoutineId, F) then
      begin
        F:= FiredByOf(W.Site.RoutineId);
        Fired.Add(W.Site.RoutineId, F);
      end;
      W.FiredBy:= F;
      if F = '' then CallersOf(W.Site.RoutineId, W);
      FWriters[K]:= W;
    end;
  finally
    Fired.Free;
  end;
end;

function TCollector.IsGuarded(const pRead: TReadRef): Boolean;
begin
  var Line:= SourceLine(pRead.Path, pRead.Line);
  var Before:= Copy(Line, 1, pRead.Col - 1);
  var After:= Copy(Line, pRead.EndCol, MaxInt);
  Result:= TRegEx.IsMatch(Before, '\bAssigned\s*\(\s*$', [roIgnoreCase])
    or TRegEx.IsMatch(After, '^\s*(=|<>)\s*nil\b', [roIgnoreCase])
    or TRegEx.IsMatch(Before, '\bnil\s*(=|<>)\s*$', [roIgnoreCase]);
end;

function CompareSites(const pL, pR: THbSite): Integer;
begin
  Result:= CompareText(pL.FileName, pR.FileName);
  if Result = 0 then Result:= pL.Line - pR.Line;
  if Result = 0 then Result:= pL.Col - pR.Col;
end;

function TCollector.Collect(const pTarget: string; const pAt: THbSite): THbEvents;
begin
  Result:= Default(THbEvents);
  ResolveTarget(pTarget, pAt, Result);
  LoadReads;
  CollectAssignments(FTargetId, False);
  CollectArguments;
  CollectAddressAndAbsolute;
  CollectUnresolved;
  CollectPropertyWrites;
  CollectDfmStream(Result);
  FillFiredByAndCallers;
  FWriters.Sort(TComparer<THbWriter>.Construct(
    function(const pL, pR: THbWriter): Integer
    begin
      Result:= CompareSites(pL.Site, pR.Site);
    end));
  Result.Writers:= FWriters.ToArray;
  for var Rd in FReads do
  begin
    if Rd.Consumed then Continue;
    if (FAtRefId <> 0) and (Rd.RefId <> FAtRefId) then Continue;
    var U:= Default(THbUse);
    U.Site:= MakeSite(Rd.Path, Rd.Line, Rd.Col, Rd.EnclosingId, Rd.Enclosing, Rd.FileId);
    U.GuardedTest:= IsGuarded(Rd);
    Result.UseSites:= Result.UseSites + [U];
  end;
end;

{ ---- public ---- }

function CollectEvents(const pIndex: TChartsIndex; const pTarget: string; const pAt: THbSite): THbEvents;
begin
  var C:= TCollector.Create(pIndex);
  try
    Result:= C.Collect(pTarget, pAt);
  finally
    C.Free;
  end;
end;

function HbIsNeverSet(const pEvents: THbEvents; out pBlockers: TArray<THbReason>): Boolean;
begin
  pBlockers:= [];
  var Counting:= False;
  var NilOnly:= False;
  var Soft:= pEvents.IsPublished or pEvents.AbsoluteOverlay;
  for var W in pEvents.Writers do
    if W.Counts then Counting:= True
    else if W.Resolved then NilOnly:= True
    else Soft:= True;
  if Soft then pBlockers:= pBlockers + [hrSoftWriter];
  if NilOnly and not Counting then pBlockers:= pBlockers + [hrNilWriteOnly];
  if Counting then pBlockers:= [];
  Result:= (Length(pEvents.Writers) = 0) and not pEvents.IsPublished and not pEvents.AbsoluteOverlay;
end;

end.
