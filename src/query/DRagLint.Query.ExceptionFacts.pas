unit DRagLint.Query.ExceptionFacts;

{ The set question over the raise / handle facts: which routine raises and handles which
  exception type. Spec docs\superpowers\specs\2026-11-06-raise-handle-type-facts.md, sec. 3.3.
  Read-only over refs + symbols. No escape analysis: `ask exception-paths` walks the callers. }

interface

uses
  DRagLint.Charts.Index;  { 151 CF: ExceptionFactsOfIndex takes an index the caller keeps open }

type
  /// <summary>One raise or handler site, with the type it names.</summary>
  /// <remarks>Via says how the type is known: 'bound' (the row's symbol_id), 'handler' (the
  /// enclosing on..do), 'local' (a local var or param of the routine), 'name' (a unique indexed
  /// type of that spelling), 'spelled' (the source names it, the DB does not hold it),
  /// 'unknown' (`raise MakeError(..)`, a `raise;` under a bare except), '' on handles-all.</remarks>
  TExceptionFact = record
    Action   : string ;
    TypeName : string ;
    TypeQName: string ;
    Via      : string ;
    Routine  : string ;
    FilePath : string ;
    Line     : Integer;
    Col      : Integer;
    /// <summary>The 1-based start line of the enclosing routine's symbol row (its declaration;
    /// the code lens anchor). 0 when the site has no enclosing symbol. Not in the JSON.</summary>
    RoutineLine: Integer;
  end;

/// <summary>The exception facts of one routine, or of one type.</summary>
/// <param name="pDbPath">An existing index. Opened read-only.</param>
/// <param name="pRoutine">A routine, qualified or by its trailing part; '' to select by type.</param>
/// <param name="pTypeName">A type, bare or qualified; '' to select by routine. Exact, no ancestry:
/// `on E: Exception` is not listed under EFoo.</param>
/// <returns>The sites, by routine, line and column.</returns>
function ExceptionFactsOf(const pDbPath, pRoutine, pTypeName: string): TArray<TExceptionFact>;

/// <summary>ExceptionFactsOf over an index the CALLER keeps open: same query, same type rules,
/// same order, without opening the database per call.</summary>
/// <param name="pIndex">An open index; must not be nil. Caller owns it.</param>
/// <param name="pRoutine">As ExceptionFactsOf.</param>
/// <param name="pTypeName">As ExceptionFactsOf.</param>
/// <returns>As ExceptionFactsOf -- the same rows for the same database.</returns>
/// <remarks>151 CF (LX-5 hover cost): the LSP hover asks this for every routine it shows, and
/// opening the store (TChartsIndex.Create) per hover was most of ~9 ms per call on a CLIENT copy.
/// One caller thread per index.</remarks>
function ExceptionFactsOfIndex(const pIndex: TChartsIndex; const pRoutine, pTypeName: string): TArray<TExceptionFact>;

/// <summary>The exception facts of every routine in one file: the raise / handle sites whose
/// ref row is in that file, sorted like ExceptionFactsOf.</summary>
/// <param name="pDbPath">An existing index. Opened read-only.</param>
/// <param name="pFilePath">The file as the index stores it; compared without case.</param>
/// <returns>The sites; empty for a file the index does not hold.</returns>
/// <remarks>The editor surfaces (LSP code lens) read this; same query, same type rules as
/// ExceptionFactsOf, so the lens and `exception-facts --target cannot disagree.</remarks>
function ExceptionFactsOfFile(const pDbPath, pFilePath: string): TArray<TExceptionFact>;

/// <summary>The hover fact line of one routine: 'Raises: EFoo (bound), EBar (spelled)'.</summary>
/// <param name="pFacts">The routine's facts (ExceptionFactsOf with a routine).</param>
/// <returns>One line naming each raised type once (raise, raise-expr and reraise sites), in
/// source order, each with the Via of its first site; a site whose type is not known reads
/// 'unknown'. '' when the routine raises nothing.</returns>
function ExceptionRaisesLine(const pFacts: TArray<TExceptionFact>): string;

/// <summary>The code lens title of one routine: 'raises 2 types, handles 1 type'.</summary>
/// <param name="pFacts">The facts of ONE routine.</param>
/// <returns>Distinct raised types and distinct handled types (a bare except counts as one),
/// either part omitted when zero; '' when both are zero.</returns>
function ExceptionLensTitle(const pFacts: TArray<TExceptionFact>): string;

/// <summary>The facts as JSON: {"facts":[...],"count":N}.</summary>
/// <param name="pFacts">The rows to render.</param>
/// <returns>The JSON text.</returns>
function ExceptionFactsJson(const pFacts: TArray<TExceptionFact>): string;

/// <summary>Prints one line per fact, then a count.</summary>
/// <param name="pFacts">The rows to print.</param>
procedure WriteExceptionFacts(const pFacts: TArray<TExceptionFact>);

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  DRagLint.Core.Model;  // dl:ok uses-global-census@1abd -- the one spelling of a ref kind the parser writes (146 int)

const
  ALL_KINDS = '''' + REF_KIND_RAISE + ''',''' + REF_KIND_RAISE_EXPR + ''',''' + REF_KIND_RERAISE + ''',''' +
              REF_KIND_HANDLE + ''',''' + REF_KIND_HANDLE_ALL + '''';
  TYPE_KINDS = '''class'',''interface'',''record'',''type'',''enum''';
  VIA_BOUND   = 'bound';
  VIA_HANDLER = 'handler';
  VIA_LOCAL   = 'local';
  VIA_NAME    = 'name';
  VIA_SPELLED = 'spelled';
  VIA_UNKNOWN = 'unknown';

function ActionOf(const pKind: string): string;
begin
  Result:= if pKind = REF_KIND_RAISE then 'raises'
           else if pKind = REF_KIND_RAISE_EXPR then 'raises-expr'
           else if pKind = REF_KIND_RERAISE then 'reraises'
           else if pKind = REF_KIND_HANDLE then 'handles'
           else 'handles-all';
end;

{ The one indexed type of this spelling, '' for none or several. }
function UniqueTypeQName(const pIndex: TChartsIndex; const pName: string): string;
begin
  Result:= '';
  var Rows:= pIndex.Query('SELECT qualified_name AS q FROM symbols WHERE name = ' + QuotedStr(pName) +
    ' COLLATE NOCASE AND kind IN (' + TYPE_KINDS + ') LIMIT 2');
  try
    if Rows.Count = 1 then Result:= Rows[0].S('q');
  finally
    Rows.Free;
  end;
end;

{ The type of a local var or param of the routine; '' unless every declaration of that
  name in the routine agrees (two handlers may each declare an E of their own). }
function LocalTypeOf(const pIndex: TChartsIndex; const pEnclosingId, pName: string): string;
begin
  Result:= '';
  if pEnclosingId = '' then Exit;
  var Rows:= pIndex.Query('SELECT DISTINCT signature AS sig FROM symbols WHERE parent_id = ' + pEnclosingId +  // dl:ok sql-injection-concat@e90f -- pEnclosingId is an integer column this query read, pName goes through QuotedStr; TChartsIndex.Query takes no parameters
    ' AND name = ' + QuotedStr(pName) + ' COLLATE NOCASE AND kind IN (''local_var'', ''param'')');
  try
    if Rows.Count = 1 then Result:= Rows[0].S('sig').Trim;
  finally
    Rows.Free;
  end;
end;

procedure FillType(const pIndex: TChartsIndex; const pKind, pName, pReceiver, pBound, pEnclosingId: string; var pFact: TExceptionFact);
begin
  if pKind = REF_KIND_HANDLE_ALL then Exit;
  if (pKind = REF_KIND_RAISE) or (pKind = REF_KIND_HANDLE) then
  begin
    pFact.TypeName:= pName;
    pFact.TypeQName:= pBound;
    if pBound <> '' then pFact.Via:= VIA_BOUND
    else
    begin
      pFact.TypeQName:= UniqueTypeQName(pIndex, pName);
      pFact.Via:= if pFact.TypeQName <> '' then VIA_NAME else VIA_SPELLED;
    end;
  end
  else if pReceiver <> '' then
  begin
    pFact.TypeName:= pReceiver;
    pFact.TypeQName:= UniqueTypeQName(pIndex, pReceiver);
    pFact.Via:= VIA_HANDLER;
  end
  else
  begin
    pFact.Via:= VIA_UNKNOWN;
    if pKind = REF_KIND_RAISE_EXPR then
    begin
      pFact.TypeName:= LocalTypeOf(pIndex, pEnclosingId, pName);
      if pFact.TypeName <> '' then
      begin
        pFact.TypeQName:= UniqueTypeQName(pIndex, pFact.TypeName);
        pFact.Via:= VIA_LOCAL;
      end;
    end;
  end;
end;

function MatchesType(const pFact: TExceptionFact; const pTypeName: string): Boolean;
begin
  Result:= SameText(if pTypeName.Contains('.') then pFact.TypeQName else pFact.TypeName, pTypeName);
end;

{ The one query behind every surface: pWhere narrows the refs (routine or file). }
function FactsWhereIn(const Index: TChartsIndex; const pWhere, pTypeName: string): TArray<TExceptionFact>;
var
  Found: TList<TExceptionFact>;
  Fact : TExceptionFact;
begin
  Found:= TList<TExceptionFact>.Create;
  try
    var Rows:= Index.Query('SELECT r.kind AS kind, r.name_text AS nm, r.receiver_text AS rt, r.start_line AS line, r.start_col AS col, ' +
      'r.enclosing_symbol_id AS eid, e.qualified_name AS routine, e.start_line AS rline, f.path AS path, b.qualified_name AS bound FROM refs r ' +
      'JOIN files f ON f.id = r.file_id LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id ' +
      'LEFT JOIN symbols b ON b.id = r.symbol_id WHERE r.kind IN (' + ALL_KINDS + ')' + pWhere);
    try
      for var R in Rows do
      begin
        Fact:= Default(TExceptionFact);
        Fact.Action  := ActionOf(R.S('kind'));
        Fact.Routine := R.S('routine');
        Fact.FilePath:= R.S('path');
        Fact.Line    := R.I('line');
        Fact.Col     := R.I('col');
        Fact.RoutineLine:= R.I('rline');
        { qualified `raise Unit.EFoo.Create`: the rows' receiver_text is the qualifier, never a
          stamp, so only a reraise / raise-expr reads it as the type. }
        FillType(Index, R.S('kind'), R.S('nm'), R.S('rt'), R.S('bound'), R.S('eid'), Fact);
        if (pTypeName = '') or MatchesType(Fact, pTypeName) then Found.Add(Fact);  // dl:ok duplicate-code@7e37 -- the sort comparer shape two unrelated report units share; 95 tokens, no shared owner (146 int)
      end;
    finally
      Rows.Free;
    end;
    Found.Sort(TComparer<TExceptionFact>.Construct(
      function(const pL, pR: TExceptionFact): Integer
      begin
        Result:= CompareText(pL.Routine, pR.Routine);
        if Result = 0 then Result:= pL.Line - pR.Line;
        if Result = 0 then Result:= pL.Col - pR.Col;
      end));
    Result:= Found.ToArray;
  finally
    Found.Free;
  end;
end;

function FactsWhere(const pDbPath, pWhere, pTypeName: string): TArray<TExceptionFact>;
begin
  var Index:= TChartsIndex.Create(pDbPath);
  try
    Result:= FactsWhereIn(Index, pWhere, pTypeName);
  finally
    Index.Free;
  end;
end;

function RoutineWhere(const pRoutine: string): string;
var
  Where: string;
begin
  Where:= '';
  { The enclosing routine, by qualified name or trailing part, found through the symbols
    indexes first (refs has no kind index: a filter on e.qualified_name scanned every ref,
    ~280 ms on a 520k-ref DB, too slow for a hover). symbols.name is the last segment. }
  if pRoutine <> '' then
    Where:= ' AND r.enclosing_symbol_id IN (SELECT s.id FROM symbols s WHERE s.qualified_name = ' + QuotedStr(pRoutine) +
      ' COLLATE NOCASE OR (s.name = ' + QuotedStr(pRoutine.Substring(pRoutine.LastIndexOf('.') + 1)) +
      ' COLLATE NOCASE AND substr(s.qualified_name, -' + IntToStr(Length(pRoutine) + 1) + ') = ' +
      QuotedStr('.' + pRoutine) + ' COLLATE NOCASE))';
  Result:= Where;
end;

function ExceptionFactsOf(const pDbPath, pRoutine, pTypeName: string): TArray<TExceptionFact>;
begin
  Result:= FactsWhere(pDbPath, RoutineWhere(pRoutine), pTypeName);
end;

function ExceptionFactsOfIndex(const pIndex: TChartsIndex; const pRoutine, pTypeName: string): TArray<TExceptionFact>;
begin
  Result:= FactsWhereIn(pIndex, RoutineWhere(pRoutine), pTypeName);
end;

function ExceptionFactsOfFile(const pDbPath, pFilePath: string): TArray<TExceptionFact>;
begin
  Result:= FactsWhere(pDbPath, ' AND r.file_id IN (SELECT id FROM files WHERE LOWER(path) = LOWER(' + QuotedStr(pFilePath) + '))', '');
end;

function IsRaiseAction(const pAction: string): Boolean;
begin
  Result:= (pAction = 'raises') or (pAction = 'raises-expr') or (pAction = 'reraises');
end;

{ The key one type is counted / named under: the qualified name when known, else the spelling. }
function TypeKey(const pFact: TExceptionFact): string;
begin
  Result:= LowerCase(if pFact.TypeQName <> '' then pFact.TypeQName else pFact.TypeName);
end;

function ExceptionRaisesLine(const pFacts: TArray<TExceptionFact>): string;
var
  Seen : TDictionary<string, Byte>;
  Parts: TList<string>;
begin
  Seen := TDictionary<string, Byte>.Create;
  Parts:= TList<string>.Create;
  try
    for var F in pFacts do
    begin
      if (not IsRaiseAction(F.Action)) or Seen.ContainsKey(TypeKey(F)) then Continue;
      Seen.Add(TypeKey(F), 0);
      Parts.Add(if F.TypeName = '' then VIA_UNKNOWN else F.TypeName + ' (' + F.Via + ')');
    end;
    Result:= if Parts.Count = 0 then '' else 'Raises: ' + string.Join(', ', Parts.ToArray);
  finally
    Parts.Free;
    Seen.Free;
  end;
end;

function ExceptionLensTitle(const pFacts: TArray<TExceptionFact>): string;

  function Counted(pCount: Integer; const pVerb: string): string;
  begin
    Result:= Format('%s %d %s', [pVerb, pCount, if pCount = 1 then 'type' else 'types']);
  end;

var
  Raised, Handled: TDictionary<string, Byte>;
begin
  Raised := TDictionary<string, Byte>.Create;
  Handled:= TDictionary<string, Byte>.Create;
  try
    for var F in pFacts do
      if IsRaiseAction(F.Action) then Raised.AddOrSetValue(TypeKey(F), 0)
      else Handled.AddOrSetValue(if F.Action = 'handles-all' then '*' else TypeKey(F), 0);
    Result:= '';
    if Raised.Count > 0 then Result:= Counted(Raised.Count, 'raises');
    if Handled.Count > 0 then
      Result:= (if Result = '' then '' else Result + ', ') + Counted(Handled.Count, 'handles');
  finally
    Handled.Free;
    Raised.Free;
  end;
end;

function ExceptionFactsJson(const pFacts: TArray<TExceptionFact>): string;
begin
  var Root:= TJSONObject.Create;
  try
    var Arr:= TJSONArray.Create;
    Root.AddPair('facts', Arr);
    for var F in pFacts do
    begin
      var O:= TJSONObject.Create;
      Arr.AddElement(O);
      O.AddPair('action', F.Action);
      O.AddPair('type', F.TypeName);
      O.AddPair('type_qname', F.TypeQName);
      O.AddPair('via', F.Via);
      O.AddPair('routine', F.Routine);
      O.AddPair('file', F.FilePath);
      O.AddPair('line', TJSONNumber.Create(F.Line));
      O.AddPair('col', TJSONNumber.Create(F.Col));
    end;
    Root.AddPair('count', TJSONNumber.Create(Length(pFacts)));
    Result:= Root.ToJSON;
  finally
    Root.Free;
  end;
end;

procedure WriteExceptionFacts(const pFacts: TArray<TExceptionFact>);
begin
  for var F in pFacts do
    Writeln(Format('  %-11s  %-24s  %-9s  %s  (%s:%d:%d)', [F.Action, if F.TypeQName <> '' then F.TypeQName else F.TypeName, F.Via, F.Routine, F.FilePath, F.Line, F.Col]));
  Writeln(Format('%d exception fact(s)', [Length(pFacts)]));
end;

end.
