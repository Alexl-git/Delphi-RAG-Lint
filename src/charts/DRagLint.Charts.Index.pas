unit DRagLint.Charts.Index;

{ In-process index queries for the ported chart emitters (spec P1, P5). Each
  routine ports the named function in charts\src\Emit-Common.ps1 (line numbers of
  2026-10-10). The PowerShell asked the engine's `sql` verb for every answer; this
  unit runs the same SQL on the engine's own FireDAC connection instead, so an
  emitter never starts the engine executable (P5) -- and because nothing crosses
  a JSON boundary, the 200-row cap and the 180-row paging the PS carried are gone.
  The exception texts are the PS `throw` texts, verbatim. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  , DRagLint.Storage.SQLite
  ;

const
  /// <summary>The PS default of Resolve-MemberSelection -Hint.</summary>
  RESOLVE_HINT_DEFAULT = 'ask who-calls instead';
  /// <summary>The PS default of Get-EdgelessFiles -MinCallRefs.</summary>
  EDGELESS_MIN_CALL_REFS = 50;

type
  /// <summary>One result row, read by column name the way the PS read a pscustomobject.</summary>
  /// <remarks>Port of the row objects Invoke-IndexQuery (Emit-Common.ps1:336) zipped from
  /// sql/1 columns and positional rows. PS traps closed: property access is case-insensitive
  /// (SameText lookup); `[string]$null` is '' and `[int]$null` is 0. Immutable once built.</remarks>
  TIndexRow = class
  private
    FNames : TArray<string>;
    FValues: TArray<string>;
    FNulls : TArray<Boolean>;
    function IndexOf(const pCol: string): Integer;
  public
    /// <summary>Builds a row from parallel column arrays.</summary>
    /// <param name="pNames">Column names, in select order.</param>
    /// <param name="pValues">Text of each value; ignored where pNulls is True.</param>
    /// <param name="pNulls">True where the column is SQL NULL.</param>
    constructor Create(const pNames, pValues: TArray<string>; const pNulls: TArray<Boolean>);
    /// <summary>A column as text.</summary>
    /// <param name="pCol">Column name, any case.</param>
    /// <returns>The value's text; '' for NULL or an absent column.</returns>
    function S(const pCol: string): string;
    /// <summary>A column as an integer.</summary>
    /// <param name="pCol">Column name, any case.</param>
    /// <returns>The value; 0 for NULL, an absent column or non-integer text.</returns>
    function I(const pCol: string): Integer;
    /// <summary>Whether the row has the column at all (NULL or not).</summary>
    /// <param name="pCol">Column name, any case.</param>
    /// <returns>True when the select list named it.</returns>
    /// <remarks>The PS `$row.PSObject.Properties.Name -contains $name`, case-insensitive.</remarks>
    function Has(const pCol: string): Boolean;
  end;

  /// <summary>Where a symbol is, preferring its body. Port of the Get-SymbolLocation result.</summary>
  TSymbolLocation = record
    /// <summary>symbols.id.</summary>
    Id       : Integer;
    /// <summary>symbols.kind.</summary>
    Kind     : string;
    /// <summary>files.path of the declaring file.</summary>
    Path     : string;
    /// <summary>symbols.start_line (the declaration).</summary>
    DeclLine : Integer;
    /// <summary>symbols.impl_start_line, 0 when there is none.</summary>
    ImplStart: Integer;
    /// <summary>symbols.impl_end_line, 0 when there is none.</summary>
    ImplEnd  : Integer;
    /// <summary>ImplStart when set, else DeclLine: the line a caller should open.</summary>
    FocusLine: Integer;
  end;

  /// <summary>One resolved member. Port of the Resolve-MemberSelection result.</summary>
  TMemberSelection = record
    /// <summary>symbols.id.</summary>
    Id        : Integer;
    /// <summary>symbols.kind.</summary>
    Kind      : string;
    /// <summary>files.path of the declaring file.</summary>
    Path      : string;
    /// <summary>symbols.qualified_name.</summary>
    QName     : string;
    /// <summary>symbols.name.</summary>
    Name      : string;
    /// <summary>symbols.prop_access, '' when NULL.</summary>
    PropAccess: string;
    /// <summary>symbols.start_line.</summary>
    DeclLine  : Integer;
    /// <summary>symbols.impl_start_line, 0 when there is none.</summary>
    ImplStart : Integer;
    /// <summary>symbols.impl_end_line, 0 when there is none.</summary>
    ImplEnd   : Integer;
    /// <summary>ImplStart when set, else DeclLine.</summary>
    FocusLine : Integer;
  end;

  /// <summary>A refused index question; the message is the PS `throw` text, verbatim.</summary>
  EChartsIndex = class(Exception);

  /// <summary>Read-only, in-process access to one drag-lint index for the chart emitters.</summary>
  /// <remarks>Owns a TSQLiteSymbolStore opened read-only and runs SQL on its FireDAC
  /// connection (spec P5: no process is started). Not thread-safe; one owning thread.
  /// Lines the PS wrote with Write-Host '  NOTE: ...' are collected in Notes instead.</remarks>
  TChartsIndex = class
  private
    FStore: TSQLiteSymbolStore;
    FNotes: TStrings;
  public
    /// <summary>Opens the index read-only.</summary>
    /// <param name="pDbPath">Path of an existing .sqlite index.</param>
    /// <remarks>The store is owned and freed by Destroy. Errors opening it propagate.</remarks>
    constructor Create(const pDbPath: string);
    /// <summary>Frees the store and the notes.</summary>
    destructor Destroy; override;
    /// <summary>Runs one SELECT and returns every row.</summary>
    /// <param name="pSql">The statement; it may carry its own ORDER BY / LIMIT.</param>
    /// <returns>A new list the caller frees; it owns its rows. Empty for zero rows.</returns>
    /// <remarks>Port of Invoke-IndexQuery (Emit-Common.ps1:336). The PS row cap (200),
    /// -FailOnTruncate and the truncation NOTE have no counterpart: FetchOptions.Mode is fmAll,
    /// so nothing is cut. PS trap closed: the unary-comma contract (a 0- or 1-row result must
    /// stay an array) does not exist here -- a list is always a list.</remarks>
    function Query(const pSql: string): TObjectList<TIndexRow>;
    /// <summary>Every row of a population query in a total order.</summary>
    /// <param name="pSql">The statement WITHOUT its own ORDER BY / LIMIT.</param>
    /// <param name="pOrderKey">ORDER BY expression; end it in a unique column.</param>
    /// <returns>A new owning list the caller frees.</returns>
    /// <remarks>Port of Get-AllIndexRows (Emit-Common.ps1:384): ' ORDER BY &lt;key&gt;' is
    /// appended exactly as the PS did; its LIMIT 180 OFFSET paging is dropped (no cap here).</remarks>
    function AllRows(const pSql, pOrderKey: string): TObjectList<TIndexRow>;
    /// <summary>Doubles single quotes for an SQL string literal.</summary>
    /// <param name="pS">Raw text.</param>
    /// <returns>pS with every ' doubled.</returns>
    /// <remarks>Port of ConvertTo-SqlText (Emit-Common.ps1:375).</remarks>
    class function SqlText(const pS: string): string;
    /// <summary>"'a','b','c'" for an SQL IN-list.</summary>
    /// <param name="pValues">Raw values.</param>
    /// <returns>The quoted, comma-joined list; '' for no values.</returns>
    /// <remarks>Port of ConvertTo-SqlInList (Emit-Common.ps1:400).</remarks>
    class function SqlInList(const pValues: TArray<string>): string;
    /// <summary>Collapses a type's forward declarations to its one real declaration row.</summary>
    /// <param name="pRows">Symbol rows carrying qualified_name, generic_params, start_line and end_line.</param>
    /// <returns>A new list the caller frees; it BORROWS its rows from pRows (pRows must outlive it).
    /// One row per (qualified_name, generic_params) group, case-insensitively: the widest
    /// end_line - start_line span, then the smallest start_line, then the first seen.</returns>
    /// <remarks>Port of Select-DeclarationRows (Emit-Common.ps1:448). The groups come out
    /// SORTED BY KEY, not in first-seen order -- see the implementation note.</remarks>
    class function SelectDeclarationRows(const pRows: TObjectList<TIndexRow>): TList<TIndexRow>;
    /// <summary>Where a qualified name lives, preferring the body line.</summary>
    /// <param name="pQName">Exact qualified name (SQL '=' -- case-sensitive, as in the PS).</param>
    /// <returns>The first matching symbol's location.</returns>
    /// <exception cref="EChartsIndex">'&lt;name&gt; is not in this index' when nothing matches.</exception>
    /// <remarks>Port of Get-SymbolLocation (Emit-Common.ps1:405). First row wins; more than
    /// one adds a NOTE line to Notes. PS trap closed: `[int]$null` is 0, so a NULL
    /// impl_start_line yields ImplStart 0 and FocusLine = DeclLine (I returns 0).</remarks>
    function SymbolLocation(const pQName: string): TSymbolLocation;
    /// <summary>Resolves a member selection, REFUSING an ambiguous name.</summary>
    /// <param name="pQName">A qualified or bare name.</param>
    /// <param name="pKinds">Acceptable kinds, any case; empty accepts every kind.</param>
    /// <param name="pAllowMissing">When True, nothing matching returns with pFound False
    /// instead of raising; ambiguity still raises.</param>
    /// <param name="pHint">Advice appended to the wrong-kind refusal (RESOLVE_HINT_DEFAULT is the PS default).</param>
    /// <param name="pFound">False only for the allowed-missing case.</param>
    /// <returns>The one member; Default(TMemberSelection) when pFound is False.</returns>
    /// <exception cref="EChartsIndex">Not in this index; ambiguous (with up to six candidates
    /// and '; +N more'); or the wrong kind (with pHint).</exception>
    /// <remarks>Port of Resolve-MemberSelection (Emit-Common.ps1:486) and Select-DeclarationRows
    /// (:448). PS traps closed: Group-Object on "qualified_name|generic_params" is
    /// case-insensitive (TIStringComparer.Ordinal dictionary), and Group-Object sorts its groups by key,
    /// case-insensitively (ICU root order, not first-seen -- so the six named candidates match);
    /// `-eq` for the exact qualified hit and `-contains` / `-notcontains` for kinds are
    /// case-insensitive (SameText); the qualified-name grouping behind "they share a
    /// qualified name" is case-insensitive too.</remarks>
    function ResolveMemberSelection(const pQName: string; const pKinds: TArray<string>; pAllowMissing: Boolean;
      const pHint: string; out pFound: Boolean): TMemberSelection;
    /// <summary>Files that hold at least pMinCallRefs call references and no call edge.</summary>
    /// <param name="pMinCallRefs">Threshold on call references.</param>
    /// <returns>(path, call-ref count) pairs, most references first, then by path.</returns>
    /// <remarks>Port of Get-EdgelessFiles (Emit-Common.ps1:634); SQL and order key verbatim.
    /// A heuristic, not a cause -- see Get-EdgelessDisclosure.</remarks>
    function EdgelessFiles(pMinCallRefs: Integer = EDGELESS_MIN_CALL_REFS): TArray<TPair<string, Integer>>;
    /// <summary>The one sentence every chart prints for EdgelessFiles.</summary>
    /// <param name="pRows">EdgelessFiles' result.</param>
    /// <returns>The disclosure naming up to three files and '+N more', or '' when empty.</returns>
    /// <remarks>Port of Get-EdgelessDisclosure (Emit-Common.ps1:658). States the observation,
    /// not the cause. PS trap closed: `$null` / an empty list read as healthy ('').</remarks>
    class function EdgelessDisclosure(const pRows: TArray<TPair<string, Integer>>): string;
    /// <summary>The JOIN that maps a refs row to its enclosing routine.</summary>
    /// <param name="pRefAlias">Alias of the refs (or member_accesses) table in the query.</param>
    /// <param name="pJoinAlias">Alias for the joined symbols row.</param>
    /// <returns>'LEFT JOIN symbols &lt;j&gt; ON &lt;j&gt;.id = &lt;r&gt;.enclosing_symbol_id'.</returns>
    /// <remarks>Port of the Join half of Get-EnclosingRoutineSql (Emit-Common.ps1:697); its
    /// Select half is just '&lt;j&gt;.qualified_name'.</remarks>
    class function EnclosingRoutineJoin(const pRefAlias: string; const pJoinAlias: string = 'encl'): string;
    /// <summary>The NOTE lines the PS wrote to the host, oldest first.</summary>
    property Notes: TStrings read FNotes;
  end;

/// <summary>PowerShell's Group-Object / Sort-Object key order for text: case-insensitive,
/// culture-aware (ICU root), weight by weight, then the shorter key first.</summary>
/// <param name="pA">First key.</param>
/// <param name="pB">Second key.</param>
/// <returns>Negative, zero or positive, as pA sorts before, with or after pB.</returns>
/// <remarks>Zero only for keys equal ignoring ASCII case. Exact for 7-bit ASCII (measured on
/// 160k index keys); an approximation beyond it (see GROUP_KEY_ORDER). Public since step 2:
/// every `Sort-Object` / `Sort-Object -Unique` over names the SQL helpers port sorts with it.</remarks>
function CompareGroupKeys(const pA, pB: string): Integer;

implementation

uses
  System.Generics.Defaults
  , FireDAC.Stan.Option
  , FireDAC.Comp.Client
  , DRagLint.Charts.Text
  ;

const
  { Select-Object -First 6 in the ambiguity refusal }
  CANDIDATE_CAP = 6;
  { Select-Object -First 3 in Get-EdgelessDisclosure }
  EDGELESS_NAMED = 3;

{ ---- TIndexRow ---- }

constructor TIndexRow.Create(const pNames, pValues: TArray<string>; const pNulls: TArray<Boolean>);
begin
  inherited Create;
  FNames:= pNames;
  FValues:= pValues;
  FNulls:= pNulls;
end;

function TIndexRow.IndexOf(const pCol: string): Integer;
begin
  for var K:= 0 to High(FNames) do
    if SameText(FNames[K], pCol) then
      Exit(K);
  Result:= -1;
end;

function TIndexRow.S(const pCol: string): string;
begin
  var K:= IndexOf(pCol);
  Result:= if (K < 0) or FNulls[K] then '' else FValues[K];
end;

function TIndexRow.I(const pCol: string): Integer;
begin
  Result:= StrToIntDef(S(pCol), 0);
end;

function TIndexRow.Has(const pCol: string): Boolean;
begin
  Result:= IndexOf(pCol) >= 0;
end;

{ ---- TChartsIndex ---- }

constructor TChartsIndex.Create(const pDbPath: string);
begin
  inherited Create;
  FNotes:= TStringList.Create;
  FStore:= TSQLiteSymbolStore.Create(pDbPath, True);
end;

destructor TChartsIndex.Destroy;
begin
  FStore.Free;
  FNotes.Free;
  inherited Destroy;
end;

function TChartsIndex.Query(const pSql: string): TObjectList<TIndexRow>;
var
  Q: TFDQuery;
begin
  Result:= TObjectList<TIndexRow>.Create(True);
  try
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= FStore.GetConnection;
      Q.FetchOptions.Mode:= fmAll;
      Q.SQL.Text:= pSql;
      Q.Open;
      var Names: TArray<string>;
      SetLength(Names, Q.FieldCount);
      for var K:= 0 to Q.FieldCount - 1 do
        Names[K]:= Q.Fields[K].FieldName;
      while not Q.Eof do
      begin
        var Values: TArray<string>;
        var Nulls: TArray<Boolean>;
        SetLength(Values, Q.FieldCount);
        SetLength(Nulls, Q.FieldCount);
        for var K:= 0 to Q.FieldCount - 1 do
        begin
          Nulls[K]:= Q.Fields[K].IsNull;
          Values[K]:= if Nulls[K] then '' else Q.Fields[K].AsString;
        end;
        Result.Add(TIndexRow.Create(Names, Values, Nulls));
        Q.Next;
      end;
    finally
      Q.Free;
    end;
  except // dl:ok bare-except@041e -- frees the half-built result list and re-raises; nothing is swallowed
    Result.Free;
    raise;
  end;
end;

function TChartsIndex.AllRows(const pSql, pOrderKey: string): TObjectList<TIndexRow>;
begin
  Result:= Query(pSql + ' ORDER BY ' + pOrderKey);
end;

class function TChartsIndex.SqlText(const pS: string): string;
begin
  Result:= StringReplace(pS, '''', '''''', [rfReplaceAll]);
end;

class function TChartsIndex.SqlInList(const pValues: TArray<string>): string;
var
  Quoted: TArray<string>;
begin
  SetLength(Quoted, Length(pValues));
  for var K:= 0 to High(pValues) do
    Quoted[K]:= '''' + SqlText(pValues[K]) + '''';
  Result:= string.Join(',', Quoted);
end;

function TChartsIndex.SymbolLocation(const pQName: string): TSymbolLocation;
begin
  Result:= Default(TSymbolLocation);
  var Rows:= Query(
    'SELECT s.id AS id, s.kind AS kind, s.start_line AS start_line,' + sLineBreak +
    '       s.impl_start_line AS impl_start_line, s.impl_end_line AS impl_end_line,' + sLineBreak +
    '       f.path AS path' + sLineBreak +
    '  FROM symbols s JOIN files f ON f.id = s.file_id' + sLineBreak +
    ' WHERE s.qualified_name = ''' + SqlText(pQName) + '''');
  try
    if Rows.Count = 0 then
      raise EChartsIndex.Create(pQName + ' is not in this index');
    var R:= Rows[0];
    if Rows.Count > 1 then
      FNotes.Add(Format('NOTE: %s resolves to %d symbols; using the first (id %s)', [pQName, Rows.Count, R.S('id')]));
    Result.Id:= R.I('id');
    Result.Kind:= R.S('kind');
    Result.Path:= R.S('path');
    Result.DeclLine:= R.I('start_line');
    Result.ImplStart:= R.I('impl_start_line');
    Result.ImplEnd:= R.I('impl_end_line');
    Result.FocusLine:= if Result.ImplStart <> 0 then Result.ImplStart else Result.DeclLine;
  finally
    Rows.Free;
  end;
end;

const
  { Group-Object's key order for 7-bit ASCII. PS TRAP: Group-Object SORTS ITS GROUPS BY KEY,
    case-insensitively and culture-aware (String.Compare with CurrentCulture + IgnoreCase,
    which on .NET 5+ is ICU root collation) -- it does NOT keep first-seen order. ICU root is
    neither ordinal nor CompareText nor Windows NLS (AnsiCompareText): '_' sorts before '.',
    and every punctuation mark and '|' before the digits and letters. This string is that
    order for printable ASCII, letters case-folded; measured 2026-10-11 by sorting 0x20..0x7E
    with [string]::Compare(a, b, en-US, IgnoreCase) under pwsh 7.6, and verified to reproduce
    Group-Object's order exactly on all 160k (qualified_name|generic_params) keys of the nine
    charts\scratch\db clones (OrdinalIgnoreCase disagreed on 38k of CLIENT's). }
  GROUP_KEY_ORDER = ' _-,;:!?.''"()[]{}@*/\&#%`^+<=>|~$0123456789abcdefghijklmnopqrstuvwxyz';
  { Weight base for any character outside GROUP_KEY_ORDER above the control range: after
    every ASCII weight, by code point. An approximation of ICU for non-ASCII -- index keys
    are identifiers and none of the 160k measured carried one. }
  GROUP_KEY_OTHER_BASE = 1000;

{ The ICU-root primary weight of one character, case-folded (see GROUP_KEY_ORDER).
  Control characters weigh their code point, below the space. }
function GroupKeyWeight(const pC: Char): Integer;
begin
  if Ord(pC) < Ord(' ') then
    Exit(Ord(pC));
  var C:= if CharInSet(pC, ['A'..'Z']) then Chr(Ord(pC) + (Ord('a') - Ord('A'))) else pC;
  var At:= Pos(C, GROUP_KEY_ORDER);
  Result:= if At > 0 then Ord(' ') + At else GROUP_KEY_OTHER_BASE + Ord(pC);
end;

function CompareGroupKeys(const pA, pB: string): Integer;
begin
  var N:= if Length(pA) < Length(pB) then Length(pA) else Length(pB);
  for var K:= 1 to N do
  begin
    Result:= GroupKeyWeight(pA[K]) - GroupKeyWeight(pB[K]);
    if Result <> 0 then
      Exit;
  end;
  Result:= Length(pA) - Length(pB);
end;

{ The Select-DeclarationRows group key: "qualified_name|generic_params". }
function DeclGroupKey(const pRow: TIndexRow): string;
begin
  Result:= pRow.S('qualified_name') + '|' + pRow.S('generic_params');
end;

{ Select-DeclarationRows (Emit-Common.ps1:448): per (qualified_name, generic_params) group
  -- case-insensitive, as Group-Object is -- the row with the widest end_line - start_line
  span, then the smallest start_line. A linear pick of that minimum keeps the first of
  equal rows, exactly what [0] of the PS's stable two-key Sort-Object returns (a group's
  members stay in input order). The groups are then SORTED BY KEY with CompareGroupKeys,
  because Group-Object sorts its groups by key, case-insensitively -- NOT first-seen order,
  which here would be the SQL's binary ORDER BY (uppercase before lowercase) and put e.g.
  MSCTYPES.ID ahead of abc.ID in the ambiguity refusal's six named candidates. Keys are
  unique per group, so the unstable TList.Sort cannot reorder ties. Rows are borrowed
  from pRows, not copied. }
class function TChartsIndex.SelectDeclarationRows(const pRows: TObjectList<TIndexRow>): TList<TIndexRow>;
var
  Slot: TDictionary<string, Integer>;
begin
  Result:= TList<TIndexRow>.Create;
  Slot:= TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  try
    for var R in pRows do
    begin
      var Key:= DeclGroupKey(R);
      var At: Integer;
      if not Slot.TryGetValue(Key, At) then
      begin
        Slot.Add(Key, Result.Count);
        Result.Add(R);
        Continue;
      end;
      var Best:= Result[At];
      var Span:= R.I('end_line') - R.I('start_line');
      var BestSpan:= Best.I('end_line') - Best.I('start_line');
      if (Span > BestSpan) or ((Span = BestSpan) and (R.I('start_line') < Best.I('start_line'))) then
        Result[At]:= R;
    end;
    Result.Sort(TComparer<TIndexRow>.Construct(
      function(const pLeft, pRight: TIndexRow): Integer
      begin
        Result:= CompareGroupKeys(DeclGroupKey(pLeft), DeclGroupKey(pRight));
      end));
  finally
    Slot.Free;
  end;
end;

function HasKind(const pKinds: TArray<string>; const pKind: string): Boolean;
begin
  { PS -contains is case-insensitive }
  for var K in pKinds do
    if SameText(K, pKind) then
      Exit(True);
  Result:= False;
end;

function DistinctQNames(const pRows: TList<TIndexRow>): Integer;
var
  Seen: THashSet<string>;
begin
  { PS Group-Object on qualified_name is case-insensitive }
  Seen:= THashSet<string>.Create(TIStringComparer.Ordinal);
  try
    for var R in pRows do
      Seen.Add(R.S('qualified_name'));
    Result:= Seen.Count;
  finally
    Seen.Free;
  end;
end;

function AmbiguityText(const pQName: string; const pCand: TList<TIndexRow>): string;
var
  Head: TArray<string>;
begin
  SetLength(Head, 0);
  for var K:= 0 to pCand.Count - 1 do
  begin
    if K >= CANDIDATE_CAP then
      Break;
    var R:= pCand[K];
    var G:= R.S('generic_params');
    Head:= Head + [R.S('qualified_name') + (if G <> '' then '<' + G + '>' else '') + ' at ' +
      FileNameOf(R.S('path')) + ':' + R.S('start_line')];
  end;
  var Tail:= if pCand.Count > CANDIDATE_CAP then Format('; +%d more', [pCand.Count - CANDIDATE_CAP]) else '';
  var Advice:= if DistinctQNames(pCand) = 1 then
    'They share a qualified name, so qualifying will not separate them -- they differ by generic parameters.'
  else
    'Pass a fully qualified name.';
  Result:= Format('%s is ambiguous -- %d symbols share that name: %s%s. %s',
    [pQName, pCand.Count, string.Join('; ', Head), Tail, Advice]);
end;

function TChartsIndex.ResolveMemberSelection(const pQName: string; const pKinds: TArray<string>;
  pAllowMissing: Boolean; const pHint: string; out pFound: Boolean): TMemberSelection;
begin
  pFound:= False;
  Result:= Default(TMemberSelection);
  var Q:= SqlText(pQName);
  var Rows:= Query(
    'SELECT s.id AS id, s.kind AS kind, s.qualified_name AS qualified_name,' + sLineBreak +
    '       s.name AS name, s.start_line AS start_line, s.end_line AS end_line,' + sLineBreak +
    '       s.impl_start_line AS impl_start_line, s.impl_end_line AS impl_end_line,' + sLineBreak +
    '       s.prop_access AS prop_access, s.generic_params AS generic_params,' + sLineBreak +
    '       f.path AS path' + sLineBreak +
    '  FROM symbols s JOIN files f ON f.id = s.file_id' + sLineBreak +
    ' WHERE s.qualified_name = ''' + Q + ''' OR s.name = ''' + Q + '''' + sLineBreak +
    ' ORDER BY s.qualified_name');
  try
    if Rows.Count = 0 then
    begin
      if pAllowMissing then
        Exit;
      raise EChartsIndex.Create(pQName + ' is not in this index');
    end;
    { forward declarations are not alternatives to choose between }
    var Decls:= SelectDeclarationRows(Rows);
    var Exact:= TList<TIndexRow>.Create;
    var Cand:= TList<TIndexRow>.Create;
    try
      { PS -eq: an exact QUALIFIED hit wins, compared case-insensitively }
      for var R in Decls do
        if SameText(R.S('qualified_name'), pQName) then
          Exact.Add(R);
      Cand.AddRange(if Exact.Count > 0 then Exact else Decls);
      { narrow a BARE name to the asked kinds, only when that leaves something }
      if (Exact.Count = 0) and (Length(pKinds) > 0) then
      begin
        var OfKind:= TList<TIndexRow>.Create;
        try
          for var R in Cand do
            if HasKind(pKinds, R.S('kind')) then
              OfKind.Add(R);
          if OfKind.Count > 0 then
          begin
            Cand.Clear;
            Cand.AddRange(OfKind);
          end;
        finally
          OfKind.Free;
        end;
      end;
      if Cand.Count > 1 then
        raise EChartsIndex.Create(AmbiguityText(pQName, Cand));
      var R:= Cand[0];
      if (Length(pKinds) > 0) and not HasKind(pKinds, R.S('kind')) then
        raise EChartsIndex.CreateFmt('%s is a %s, not a %s -- %s',
          [R.S('qualified_name'), R.S('kind'), string.Join(' or ', pKinds), pHint]);
      Result.Id:= R.I('id');
      Result.Kind:= R.S('kind');
      Result.Path:= R.S('path');
      Result.QName:= R.S('qualified_name');
      Result.Name:= R.S('name');
      Result.PropAccess:= R.S('prop_access');
      Result.DeclLine:= R.I('start_line');
      Result.ImplStart:= R.I('impl_start_line');
      Result.ImplEnd:= R.I('impl_end_line');
      Result.FocusLine:= if Result.ImplStart <> 0 then Result.ImplStart else Result.DeclLine;
      pFound:= True;
    finally
      Cand.Free;
      Exact.Free;
      Decls.Free;
    end;
  finally
    Rows.Free;
  end;
end;

function TChartsIndex.EdgelessFiles(pMinCallRefs: Integer): TArray<TPair<string, Integer>>;
begin
  var Rows:= AllRows(
    'SELECT p, n FROM (' + sLineBreak + // dl:ok sql-injection-concat@ffea -- the only value spliced in is the Integer pMinCallRefs via IntToStr; no text reaches the SQL
    '  SELECT f.path AS p,' + sLineBreak +
    '         (SELECT COUNT(*) FROM refs r WHERE r.file_id = f.id AND r.kind = ''call'') AS n,' + sLineBreak +
    '         (SELECT COUNT(*) FROM call_edges ce JOIN refs r2 ON r2.id = ce.ref_id' + sLineBreak +
    '           WHERE r2.file_id = f.id) AS e' + sLineBreak +
    '    FROM files f)' + sLineBreak +
    ' WHERE n >= ' + IntToStr(pMinCallRefs) + ' AND e = 0', 'n DESC, p');
  try
    SetLength(Result, Rows.Count);
    for var K:= 0 to Rows.Count - 1 do
      Result[K]:= TPair<string, Integer>.Create(Rows[K].S('p'), Rows[K].I('n'));
  finally
    Rows.Free;
  end;
end;

class function TChartsIndex.EdgelessDisclosure(const pRows: TArray<TPair<string, Integer>>): string;
var
  Names: TArray<string>;
begin
  if Length(pRows) = 0 then
    Exit('');
  SetLength(Names, 0);
  for var K:= 0 to High(pRows) do
  begin
    if K >= EDGELESS_NAMED then
      Break;
    Names:= Names + [FileNameOf(pRows[K].Key)];
  end;
  var More:= if Length(pRows) > EDGELESS_NAMED then Format(' +%d more', [Length(pRows) - EDGELESS_NAMED]) else '';
  Result:= Format('%d file(s) here have call references but NO call edges (%s%s) -- either their calls all ' +
    'target code outside this index, or a partial resolve cleared them; either way, edges out of symbols in ' +
    'those files are missing', [Length(pRows), string.Join(', ', Names), More]);
end;

class function TChartsIndex.EnclosingRoutineJoin(const pRefAlias, pJoinAlias: string): string;
begin
  Result:= Format('LEFT JOIN symbols %s ON %s.id = %s.enclosing_symbol_id', [pJoinAlias, pJoinAlias, pRefAlias]);
end;

end.
