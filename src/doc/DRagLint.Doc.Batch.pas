unit DRagLint.Doc.Batch;

{ AutoDocument -- whole-unit batch engine. Drives the single-declaration
  orchestrator (TDocumenter.BuildFor) across every PUBLIC (interface-section)
  documentable declaration in one unit, aggregating the per-declaration edits
  into one set the caller applies via TTextEditApplier.

  Facts-only default (AOptions.Stubs = False): a declaration that would produce
  ONLY a fresh all-TODO comment (no prior doc, no index-grounded facts) is
  SKIPPED, so batch documentation never floods a unit with empty TODO stubs.
  A declaration with a managed facts block (AUTO_BEGIN) -- or one that already
  had a doc-comment (daExtended) -- is kept. Set Stubs = True to keep every
  fresh TODO create as well (wired in a later task; the field gates the filter
  here). The IncludeSeeAlso / IncludeDeprecated / IncludeSince / BaseDir options
  are threaded for forward compatibility and are no-ops in this task. }

interface

uses
  DRagLint.Core.Model, DRagLint.Core.Interfaces,
  DRagLint.Refactor.TextEdit;

type
  /// <summary>Batch-documentation options. Stubs=False (default) is the
  /// facts-only policy: drop pure all-TODO creates, keep facts-backed or
  /// previously-documented decls. The remaining flags are threaded for later
  /// doc-source tasks and are inert here.</summary>
  TDocBatchOptions = record
    Stubs            : Boolean; // opt-in TODO summaries; default False = facts-only
    IncludeSeeAlso   : Boolean;
    IncludeDeprecated: Boolean;
    IncludeSince     : Boolean;
    BaseDir          : string ; // repo root for git <since>; '' = cwd
  end;

  /// <summary>Aggregated batch result. Edits is the union of every kept
  /// declaration's edits, ordered by line DESCENDING so applying an earlier
  /// edit does not shift a later declaration's line numbers. DeclCount is the
  /// number of public interface-section documentable declarations considered;
  /// DocCount is how many of them contributed at least one edit.</summary>
  TDocBatchResult = record
    Edits    : TArray<TTextEdit>;
    DeclCount: Integer;
    DocCount : Integer;
  end;

  TDocBatch = class
  public
    /// <summary>Documents every public (interface-section) declaration in
    /// AUnitFile: routines, methods, ctors/dtors and type declarations (private
    /// fields/consts are skipped). For each, computes the DocInsight edits via
    /// TDocumenter.BuildFor and, under the facts-only default
    /// (AOptions.Stubs=False), keeps the edit only when the merged comment
    /// carries a managed facts block or the declaration already had a
    /// doc-comment. Returns the aggregated, line-descending edit set plus the
    /// decl/doc counts. Does not write files; the caller applies the edits.</summary>
    /// <param name="AStore">Open symbol store to query; not owned. Must not be nil.</param>
    /// <param name="AUnitFile">Path (relative or absolute) to the unit's source file, as stored/resolvable in the index.</param>
    /// <param name="AOptions">Batch options; Stubs gates the facts-only filter.</param>
    /// <returns>Aggregated edits + DeclCount (public decls seen) + DocCount (decls contributing an edit).</returns>
    /// <remarks>Not thread-safe; call from the owning thread only.</remarks>
    class function DocumentUnit(const AStore: ISymbolStore; const AUnitFile: string;
      const AOptions: TDocBatchOptions): TDocBatchResult;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults,
  DRagLint.Doc.Document, DRagLint.Doc.Regions;

// A declaration whose doc-comment we generate: routines/methods/ctors/dtors and
// declared types. Fields, consts, vars, enum values, unit/program markers and
// SQL symbols are NOT documented in the whole-unit batch.
function IsDocumentableKind(AKind: TSymbolKind): Boolean;
begin
  Result := AKind in
    [skProcedure, skFunction, skMethod, skConstructor, skDestructor,
     skClass, skInterface, skRecord, skEnum, skTypeAlias];
end;

// True when the result's edits carry a managed facts block (AUTO_BEGIN appears
// in any insert-text) -- i.e. the merged comment has an index-grounded block,
// not a pure all-TODO create.
function HasManagedBlock(const ARes: TDocumentResult): Boolean;
var
  E: TTextEdit;
begin
  for E in ARes.Edits do
    if System.Pos(AUTO_BEGIN, E.Text) > 0 then Exit(True);
  Result := False;
end;

class function TDocBatch.DocumentUnit(const AStore: ISymbolStore;
  const AUnitFile: string; const AOptions: TDocBatchOptions): TDocBatchResult;
var
  Syms   : TArray<TSymbol>   ;
  Sym    : TSymbol           ;
  Res    : TDocumentResult   ;
  Collected: TList<TTextEdit>;
  Keep   : Boolean           ;
  Cmp    : IComparer<TTextEdit>;
  E      : TTextEdit         ;
begin
  Result := Default(TDocBatchResult);
  Syms := AStore.FindSymbolsByFile(AUnitFile);

  Collected := TList<TTextEdit>.Create;
  try
    for Sym in Syms do
    begin
      // Public surface = interface-section, documentable kind. The private
      // FLast-style fields (Section='implementation' / not interface) and
      // non-routine/type kinds are excluded from both DeclCount and the edits.
      if not SameText(Sym.Section, 'interface') then Continue;
      if not IsDocumentableKind(Sym.Kind) then Continue;

      Inc(Result.DeclCount);

      Res := TDocumenter.BuildFor(AStore, Sym.QualifiedName);
      if Length(Res.Edits) = 0 then Continue; // daUnchanged / daNotFound: nothing to do

      // Facts-only filter (Stubs=False, the default): keep the edit when the
      // merged comment has a managed facts block, OR the decl already had a
      // doc-comment (daExtended). Drop a pure fresh all-TODO-no-facts create.
      // Stubs=True keeps every create too (wired fully in a later task).
      if AOptions.Stubs then
        Keep := True
      else
        Keep := HasManagedBlock(Res) or (Res.Action = daExtended);

      if not Keep then Continue;

      Inc(Result.DocCount);
      for E in Res.Edits do Collected.Add(E);
    end;

    // Order aggregated edits by line DESCENDING so applying an earlier edit does
    // not shift a later declaration's line numbers. TTextEditApplier.Apply also
    // sorts back-to-front per file, so this is belt-and-suspenders determinism
    // (it also gives a stable dry-run order top-to-bottom of the file, reversed).
    Cmp := TComparer<TTextEdit>.Construct(
      function(const A, B: TTextEdit): Integer
      begin
        if A.Line < B.Line then Result := 1
        else if A.Line > B.Line then Result := -1
        else Result := 0;
      end);
    Collected.Sort(Cmp);

    Result.Edits := Collected.ToArray;
  finally
    Collected.Free;
  end;
end;

end.
