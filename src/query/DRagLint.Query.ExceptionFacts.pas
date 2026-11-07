unit DRagLint.Query.ExceptionFacts;

{ The set question over the raise / handle facts: which routine raises and handles which
  exception type. Spec docs\superpowers\specs\2026-11-06-raise-handle-type-facts.md, sec. 3.3.
  Read-only over refs + symbols. No escape analysis: `ask exception-paths` walks the callers. }

interface

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
  end;

/// <summary>The exception facts of one routine, or of one type.</summary>
/// <param name="pDbPath">An existing index. Opened read-only.</param>
/// <param name="pRoutine">A routine, qualified or by its trailing part; '' to select by type.</param>
/// <param name="pTypeName">A type, bare or qualified; '' to select by routine. Exact, no ancestry:
/// `on E: Exception` is not listed under EFoo.</param>
/// <returns>The sites, by routine, line and column.</returns>
function ExceptionFactsOf(const pDbPath, pRoutine, pTypeName: string): TArray<TExceptionFact>;

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
  DRagLint.Core.Model,
  DRagLint.Charts.Index;

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

function ExceptionFactsOf(const pDbPath, pRoutine, pTypeName: string): TArray<TExceptionFact>;
var
  Where: string;
  Found: TList<TExceptionFact>;
  Fact : TExceptionFact;
begin
  Where:= '';
  if pRoutine <> '' then
    Where:= ' AND (e.qualified_name = ' + QuotedStr(pRoutine) + ' COLLATE NOCASE OR substr(e.qualified_name, -' +
      IntToStr(Length(pRoutine) + 1) + ') = ' + QuotedStr('.' + pRoutine) + ' COLLATE NOCASE)';
  Found:= TList<TExceptionFact>.Create;
  var Index:= TChartsIndex.Create(pDbPath);
  try
    var Rows:= Index.Query('SELECT r.kind AS kind, r.name_text AS nm, r.receiver_text AS rt, r.start_line AS line, r.start_col AS col, ' +
      'r.enclosing_symbol_id AS eid, e.qualified_name AS routine, f.path AS path, b.qualified_name AS bound FROM refs r ' +
      'JOIN files f ON f.id = r.file_id LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id ' +
      'LEFT JOIN symbols b ON b.id = r.symbol_id WHERE r.kind IN (' + ALL_KINDS + ')' + Where);
    try
      for var R in Rows do
      begin
        Fact:= Default(TExceptionFact);
        Fact.Action  := ActionOf(R.S('kind'));
        Fact.Routine := R.S('routine');
        Fact.FilePath:= R.S('path');
        Fact.Line    := R.I('line');
        Fact.Col     := R.I('col');
        { qualified `raise Unit.EFoo.Create`: the rows' receiver_text is the qualifier, never a
          stamp, so only a reraise / raise-expr reads it as the type. }
        FillType(Index, R.S('kind'), R.S('nm'), R.S('rt'), R.S('bound'), R.S('eid'), Fact);
        if (pTypeName = '') or MatchesType(Fact, pTypeName) then Found.Add(Fact);
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
    Index.Free;
    Found.Free;
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
