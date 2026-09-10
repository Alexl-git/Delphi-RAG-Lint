unit DRagLint.Analysis.SurfaceFingerprint;

{ The canonical form of a unit's INTERFACE, and a hash of it.

  WHY THIS LIVES IN src\analysis AND NOT src\index. It is about symbols, so the
  obvious home looks like the indexer. It is not. `run_extractor_version_guard`
  hashes `src\parser`, `src\preprocess`, `src\index` and `Core.Indexer.pas`, and
  a change under any of those demands a DRAGLINT_EXTRACTOR_VERSION bump, which
  re-parses EVERY database -- measured at ~5 h. This unit only READS symbols that
  are already extracted, so putting it under a watched root would charge a
  five-hour re-parse for a read-only feature. src\analysis is not watched
  (verified 2026-09-10 against the guard's own $roots list).

  WHAT "CANONICAL" HAS TO MEAN HERE. The fingerprint gates the whole fan-out, so
  it has exactly one job: move when a DEPENDENT could care, and stay still
  otherwise. That makes two properties load-bearing and neither is negotiable:

    NO LINE NUMBERS, and no input ordering. Moving a declaration down a file, or
    reflowing whitespace, or the store handing symbols back in a different order,
    must all produce a byte-identical string -- otherwise every save fans out.

    ORDER-SENSITIVE interface `uses`. This is the one place order IS semantic:
    reordering a uses clause changes which unit wins a name collision, so it is
    preserved verbatim rather than sorted. Implementation `uses` is excluded
    entirely -- no dependent can see it.

  WHY BODIES APPEAR AT ALL. A body is normally invisible across a unit boundary,
  with two exceptions that are not: an `inline` routine is expanded into the
  CALLER, and a generic method is instantiated there. For those, an
  implementation edit really does change what dependents compile, so their body
  text is hashed in. `TSymbol.Directives` (schema v22) says WHICH routines those
  are; it does not say what their bodies contain, which is why the hash is still
  required and was not deleted when PLAN A shipped. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Hash,
  DRagLint.Core.Model;

type
  /// <summary>
  /// One expansion-visible routine body -- an `inline` routine or a generic
  /// method -- whose implementation text is part of the interface surface
  /// because the compiler reproduces it inside every dependent.
  /// </summary>
  /// <remarks>
  /// Plain (non-inline, non-generic) routines must NOT be supplied here: their
  /// bodies are invisible across a unit boundary, and including one would make
  /// every ordinary implementation edit fan out.
  /// </remarks>
  TInlineBody = record
    /// <summary>Fully qualified routine name, e.g. `uB.TWidget.DoThing`.</summary>
    QualifiedName: string;
    /// <summary>Verbatim implementation-span text; hashed, never stored.</summary>
    BodyText     : string;
  end;

/// <summary>
/// Renders the stable, order-independent canonical text of a unit's interface
/// surface. Two units with the same canonical text are indistinguishable to
/// any dependent.
/// </summary>
/// <param name="pSymbols">
/// Every symbol of the unit, from either side (the parser's in-memory output
/// for an unsaved buffer, or `FindSymbolsByFile` for the index). Non-interface
/// symbols, the unit symbol, parameters and local variables are filtered out
/// here, so the caller passes the whole set and does not pre-filter.
/// </param>
/// <param name="pUses">
/// Every uses entry of the unit. Implementation, program and package sections
/// are dropped; interface entries keep their DECLARATION ORDER, which is
/// semantic.
/// </param>
/// <param name="pInlineBodies">
/// Expansion-visible bodies only (see <see cref="TInlineBody"/>). May be empty.
/// </param>
/// <returns>
/// A newline-joined string. Deterministic for a given surface regardless of the
/// order the arrays arrive in, and free of line numbers.
/// </returns>
/// <remarks>Pure; allocates nothing the caller owns. Not thread-affine.</remarks>
function SurfaceCanonical(const pSymbols: TArray<TSymbol>;
                          const pUses: TArray<TUnitUse>;
                          const pInlineBodies: TArray<TInlineBody>): string;

/// <summary>
/// SHA-256 of <see cref="SurfaceCanonical"/>, lowercase hex -- the value the
/// fan-out compares against an edit-episode baseline.
/// </summary>
/// <param name="pSymbols">As <see cref="SurfaceCanonical"/>.</param>
/// <param name="pUses">As <see cref="SurfaceCanonical"/>.</param>
/// <param name="pInlineBodies">As <see cref="SurfaceCanonical"/>.</param>
/// <returns>64 lowercase hex characters.</returns>
/// <remarks>
/// Compare fingerprints only against a baseline captured from an index of the
/// SAME schema and extractor version. `directives` and `vis_explicit` read back
/// as `''`/True on a pre-v22 row, so a stale baseline would report every
/// routine as changed -- which is why the baseline file carries both stamps and
/// a mismatch is refused rather than diffed.
/// </remarks>
function SurfaceFingerprint(const pSymbols: TArray<TSymbol>;
                            const pUses: TArray<TUnitUse>;
                            const pInlineBodies: TArray<TInlineBody>): string;

implementation

const
  { A separator that cannot occur inside any field it separates. Using '|'
    alone would let a signature containing '|' forge a field boundary and make
    two different surfaces collide. }
  FIELD_SEP = '|';
  UNIT_SEP  = ',';

function BoolBit(const pValue: Boolean): string;
begin
  if pValue then
    Result:= '1'
  else
    Result:= '0';
end;

function IsSurfaceKind(const pKind: TSymbolKind): Boolean;
begin
  { The unit symbol names the file, not anything a dependent can reference;
    params and locals are interior detail that never crosses the boundary.
    MEASURED 2026-09-10: the unit symbol carries Section='' and locals carry
    'implementation', so the section filter alone would already drop them --
    this stays explicit so the contract does not depend on that coincidence. }
  Result:= not (pKind in [skUnit, skParam, skLocalVar]);
end;

function SymbolLine(const pSymbol: TSymbol): string;
begin
  Result:= string.Join(FIELD_SEP, [
    pSymbol.Kind.ToText,
    pSymbol.QualifiedName,
    pSymbol.Signature,
    pSymbol.Modifiers,
    pSymbol.Heritage,
    pSymbol.PropAccess,
    BoolBit(pSymbol.IsHelper),
    pSymbol.Directives
  ]);
end;

function CollectSymbolLines(const pSymbols: TArray<TSymbol>): TArray<string>;
var
  Kept: TList<TSymbol>;
  Sym : TSymbol;
  I   : Integer;
begin
  Kept:= TList<TSymbol>.Create;
  try
    for Sym in pSymbols do
      if SameText(Sym.Section, 'interface') and IsSurfaceKind(Sym.Kind) then
        Kept.Add(Sym);

    { Sorted by (qualified_name, kind, signature) so the store's row order and
      the parser's emission order cannot disagree. Overloads share a qualified
      name, which is why the signature is part of the key. }
    Kept.Sort(TComparer<TSymbol>.Construct(
      function(const A, B: TSymbol): Integer
      begin
        Result:= CompareStr(A.QualifiedName, B.QualifiedName);
        if Result = 0 then
          Result:= CompareStr(A.Kind.ToText, B.Kind.ToText);
        if Result = 0 then
          Result:= CompareStr(A.Signature, B.Signature);
      end));

    SetLength(Result, Kept.Count);
    for I:= 0 to Kept.Count - 1 do
      Result[I]:= SymbolLine(Kept[I]);
  finally
    Kept.Free;
  end;
end;

function InterfaceUsesLine(const pUses: TArray<TUnitUse>): string;
var
  Names: TStringList;
  Use  : TUnitUse;
begin
  Names:= TStringList.Create;
  try
    { NOT sorted: uses order decides which unit wins a name collision, so a
      reorder is a real interface change and must move the fingerprint. }
    Names.Sorted:= False;
    for Use in pUses do
      if Use.Section = uusInterface then
        Names.Add(LowerCase(Use.UnitName));
    Result:= 'uses' + FIELD_SEP + string.Join(UNIT_SEP, Names.ToStringArray);
  finally
    Names.Free;
  end;
end;

function CollectBodyLines(const pInlineBodies: TArray<TInlineBody>):
  TArray<string>;
var
  Sorted: TList<TInlineBody>;
  Body  : TInlineBody;
  I     : Integer;
begin
  Sorted:= TList<TInlineBody>.Create;
  try
    for Body in pInlineBodies do
      Sorted.Add(Body);

    Sorted.Sort(TComparer<TInlineBody>.Construct(
      function(const A, B: TInlineBody): Integer
      begin
        Result:= CompareStr(A.QualifiedName, B.QualifiedName);
      end));

    SetLength(Result, Sorted.Count);
    for I:= 0 to Sorted.Count - 1 do
      Result[I]:= string.Join(FIELD_SEP, [
        'body',
        Sorted[I].QualifiedName,
        { the TEXT is hashed rather than embedded: the canonical form stays
          bounded no matter how large a generic method's body is }
        LowerCase(THashSHA2.GetHashString(Sorted[I].BodyText))
      ]);
  finally
    Sorted.Free;
  end;
end;

function SurfaceCanonical(const pSymbols: TArray<TSymbol>;
                          const pUses: TArray<TUnitUse>;
                          const pInlineBodies: TArray<TInlineBody>): string;
var
  Lines: TArray<string>;
begin
  Lines:= CollectSymbolLines(pSymbols)
        + [InterfaceUsesLine(pUses)]
        + CollectBodyLines(pInlineBodies);
  Result:= string.Join(sLineBreak, Lines);
end;

function SurfaceFingerprint(const pSymbols: TArray<TSymbol>;
                            const pUses: TArray<TUnitUse>;
                            const pInlineBodies: TArray<TInlineBody>): string;
begin
  Result:= LowerCase(THashSHA2.GetHashString(
    SurfaceCanonical(pSymbols, pUses, pInlineBodies)));
end;

end.
