unit DRagLint.Core.ForwardStub;

{ A forward declaration is not a class.

  `TFoo = class;` followed later in the same unit by `TFoo = class(TBar) ... end;`
  is extracted as TWO `class` rows with the same qualified name, and nothing on
  the stub row marks it as a stub: no modifier, no heritage, no members,
  start_line = end_line (measured 2026-09-17, spec section 1). Every reader that
  looks a type up by name therefore saw both, and hover/metrics/search picked
  whichever came first.

  This unit is the definition of "stub" (spec section 2) that every READER
  applies -- query, hover, completion, outline, ClassMetrics -- rather than the
  extractor: a marker would have cost an extractor bump and a multi-hour
  re-parse for a fact the join derives in memory. It is NOT the only stub test
  in the tree: the resolve pass's ResolveTypeNameToClass.IsStub in
  DRagLint.Storage.SQLite.pas keeps its narrower pre-existing filter (heritage
  empty AND end_line <= start_line; no children / same-file test) because it is
  on the resolver surface (tests\resolver-surface.txt); unifying the two is a
  resolver-surface change deferred to DRAGLINT_RESOLVER_VERSION 1.8.0 (it was
  1.6.0 until 2026-09-23, when the owner gave 1.6.0-alpha to the enum-value ref
  binding -- docs\superpowers\specs\2026-09-23-enum-value-ref-binding.md -- and
  then 1.7.0 until 1.7.0-alpha went to the parenless-call binding the same day).

  Design: docs\superpowers\specs\2026-09-17-forward-stub-is-not-a-class-design.md }

interface

uses
  System.SysUtils,
  DRagLint.Core.Model;

type
  /// <summary>Answers whether ASym owns any child symbol (fields, methods,
  /// properties). The store fold asks the database; the whole-file folds
  /// (outline, ClassMetrics) answer from the rows they already hold via
  /// HasChildInSet. nil means "no children known" and the row is treated as
  /// childless.</summary>
  THasChildrenFn = reference to function(const ASym: TSymbol): Boolean;

/// <summary>For every row of ARows, the index into ARows of the real
/// declaration it is a forward stub of, or -1. Row S is a stub of T iff:
/// S.Kind in [skClass, skInterface]; S.Heritage = ''; AHasChildren(S) is
/// False (or AHasChildren is nil); T.Kind = S.Kind, T.FileId = S.FileId,
/// SameText(T.QualifiedName, S.QualifiedName), T.StartLine &gt; S.StartLine; and T
/// is the row of those with the SMALLEST StartLine (spec section 2). A row with no
/// later twin -- a lone `TOnlyStub = class;` or an empty `TEmpty = class end;`
/// -- gets -1 and keeps counting as a class.</summary>
/// <param name="ARows">Any set of symbol rows, in any order. Rows from several
/// files may be mixed; pairing never crosses a file.</param>
/// <param name="AHasChildren">The children test; asked LAST, only for rows that
/// passed every other test, so a database-backed callback runs rarely.</param>
/// <returns>An array of the same length as ARows.</returns>
/// <remarks>Pure; O(n^2) over the rows of one lookup, which are few.</remarks>
function PairForwardStubs(const ARows: TArray<TSymbol>; const AHasChildren: THasChildrenFn): TArray<Integer>;

/// <summary>Drops every row PairForwardStubs pairs and stamps each target's
/// ForwardLine with its stub's StartLine (the first stub wins if there are
/// several). Rows that are not stubs are returned unchanged, in their original
/// order. The input array is not modified.</summary>
/// <param name="ARows">The result set of a by-name lookup or a whole-file listing.</param>
/// <param name="AHasChildren">See PairForwardStubs.</param>
/// <returns>A new array; Length(Result) = Length(ARows) - number of folded stubs.</returns>
function FoldForwardStubs(const ARows: TArray<TSymbol>; const AHasChildren: THasChildrenFn): TArray<TSymbol>;

/// <summary>A THasChildrenFn that answers from ARows itself: True when some row
/// in ARows has ParentId = ASym.Id. Correct only when ARows holds a whole file's
/// rows (FindSymbolsByFile), where every member of a type is present.</summary>
/// <param name="ARows">A whole-file row set.</param>
/// <returns>The closure; ARows is captured by reference (a dynamic array), so
/// callers must not mutate it while the closure is live.</returns>
function HasChildInSet(const ARows: TArray<TSymbol>): THasChildrenFn;

implementation

function PairForwardStubs(const ARows: TArray<TSymbol>; const AHasChildren: THasChildrenFn): TArray<Integer>;
var
  Best: Integer;
begin
  SetLength(Result, Length(ARows));
  for var i:= 0 to High(Result) do Result[i]:= -1;
  if Length(ARows) < 2 then Exit;
  for var i:= 0 to High(ARows) do
  begin
    if not (ARows[i].Kind in [skClass, skInterface]) then Continue;
    if ARows[i].Heritage <> '' then Continue;
    Best:= -1;
    for var j:= 0 to High(ARows) do
    begin
      if j = i then Continue;
      if ARows[j].Kind <> ARows[i].Kind then Continue;
      if ARows[j].FileId <> ARows[i].FileId then Continue;
      if ARows[j].StartLine <= ARows[i].StartLine then Continue;
      if not SameText(ARows[j].QualifiedName, ARows[i].QualifiedName) then Continue;
      if (Best < 0) or (ARows[j].StartLine < ARows[Best].StartLine) then Best:= j;
    end;
    if Best < 0 then Continue;
    { The children question last: it is the only test that may cost a query. }
    if Assigned(AHasChildren) and AHasChildren(ARows[i]) then Continue;
    Result[i]:= Best;
  end;
end;

function FoldForwardStubs(const ARows: TArray<TSymbol>; const AHasChildren: THasChildrenFn): TArray<TSymbol>;
var
  Pairs: TArray<Integer>;
  Rows : TArray<TSymbol>;
begin
  Result:= nil;
  if Length(ARows) = 0 then Exit;
  Pairs:= PairForwardStubs(ARows, AHasChildren);
  Rows := Copy(ARows);   { stamp a private copy; the caller's array stays as it was }
  for var i:= 0 to High(Rows) do
    if (Pairs[i] >= 0) and (Rows[Pairs[i]].ForwardLine = 0) then
      Rows[Pairs[i]].ForwardLine:= Rows[i].StartLine;
  for var i:= 0 to High(Rows) do
    if Pairs[i] < 0 then Result:= Result + [Rows[i]];
end;

function HasChildInSet(const ARows: TArray<TSymbol>): THasChildrenFn;
var
  Captured: TArray<TSymbol>;
begin
  Captured:= ARows;
  Result:= function(const ASym: TSymbol): Boolean
    begin
      Result:= False;
      for var R in Captured do
        if R.ParentId = ASym.Id then Exit(True);
    end;
end;

end.
