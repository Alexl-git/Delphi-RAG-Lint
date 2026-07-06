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

    /// <summary>Documents every public interface-section decl across the whole
    /// compile closure of AProjectFile (.dpr/.dproj). Resolves the project-local
    /// file set via TClosureResolver.Resolve, calls DocumentUnit per file, and
    /// aggregates the edits and DeclCount/DocCount sums. Library-path files are
    /// excluded by the closure. The same facts-only default applies per file
    /// (AOptions.Stubs gates it). Does not write files; the caller applies the
    /// per-file edits (each edit's file path identifies its target).</summary>
    /// <param name="AStore">Open symbol store to query; not owned. Must not be nil.</param>
    /// <param name="AProjectFile">Path to the .dpr or .dproj whose closure to document.</param>
    /// <param name="AOptions">Batch options; Stubs gates the facts-only filter.</param>
    /// <returns>Aggregated edits over the closure + summed DeclCount/DocCount.</returns>
    /// <remarks>Not thread-safe; call from the owning thread only.</remarks>
    class function DocumentProject(const AStore: ISymbolStore; const AProjectFile: string;
      const AOptions: TDocBatchOptions): TDocBatchResult;

    /// <summary>Documents every public interface-section decl across EVERY
    /// distinct file in the index (no project scope). Enumerates the store's
    /// file ids, resolves each to a path, calls DocumentUnit per file, and
    /// aggregates. Same facts-only default per file (AOptions.Stubs gates it).
    /// Does not write files; the caller applies the per-file edits.</summary>
    /// <param name="AStore">Open symbol store to query; not owned. Must not be nil.</param>
    /// <param name="AOptions">Batch options; Stubs gates the facts-only filter.</param>
    /// <returns>Aggregated edits over the whole index + summed DeclCount/DocCount.</returns>
    /// <remarks>Not thread-safe; call from the owning thread only.</remarks>
    class function DocumentAll(const AStore: ISymbolStore;
      const AOptions: TDocBatchOptions): TDocBatchResult;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults,
  DRagLint.Doc.Document, DRagLint.Doc.Regions,
  DRagLint.Index.Closure, DRagLint.Project.Resolver;

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

// Document each file in AFiles (via DocumentUnit) and aggregate the per-file
// edits + DeclCount/DocCount sums into one TDocBatchResult. Each edit already
// carries its own file path (edits target multiple files), so the aggregate
// Edits array simply concatenates them; the caller's TTextEditApplier groups
// and sorts per file at apply time.
function AggregateOverFiles(const AStore: ISymbolStore;
  const AFiles: TArray<string>; const AOptions: TDocBatchOptions): TDocBatchResult;
var
  F        : string;
  Sub      : TDocBatchResult;
  Collected: TList<TTextEdit>;
  E        : TTextEdit;
begin
  Result := Default(TDocBatchResult);
  Collected := TList<TTextEdit>.Create;
  try
    for F in AFiles do
    begin
      // Only Delphi sources carry documentable decls; skip include files and
      // any non-.pas closure member so DocumentUnit is not asked to parse them.
      if not SameText(ExtractFileExt(F), '.pas') then Continue;
      Sub := TDocBatch.DocumentUnit(AStore, F, AOptions);
      Inc(Result.DeclCount, Sub.DeclCount);
      Inc(Result.DocCount , Sub.DocCount );
      for E in Sub.Edits do Collected.Add(E);
    end;
    Result.Edits := Collected.ToArray;
  finally
    Collected.Free;
  end;
end;

class function TDocBatch.DocumentProject(const AStore: ISymbolStore;
  const AProjectFile: string; const AOptions: TDocBatchOptions): TDocBatchResult;
var
  ProjResolver: TProjectResolver;
  LibRoots    : TArray<string>  ;
  Resolver    : TClosureResolver;
  CR          : TClosureResult  ;
begin
  // Mirror the CLI's closure construction (selftest closure / lint-all): build
  // the library-root exclusion set from TProjectResolver, then resolve the
  // project-local compile closure. The default TClosureResolver keeps the
  // all-branch uses-scan (no per-config preprocessing needed to find the files
  // to document).
  ProjResolver := TProjectResolver.Create;
  try
    LibRoots := ProjResolver.ResolveLibraryPaths;
  finally
    ProjResolver.Free;
  end;

  Resolver := TClosureResolver.Create(LibRoots);
  try
    CR := Resolver.Resolve(AProjectFile, []);
  finally
    Resolver.Free;
  end;

  Result := AggregateOverFiles(AStore, CR.Files, AOptions);
end;

class function TDocBatch.DocumentAll(const AStore: ISymbolStore;
  const AOptions: TDocBatchOptions): TDocBatchResult;
var
  FileIds: TArray<Int64>;
  Id     : Int64        ;
  Path   : string       ;
  Paths  : TList<string>;
begin
  // Every distinct file in the index: enumerate file ids, resolve each to its
  // stored path (same idiom as the selftest files verb). No project scope.
  Paths := TList<string>.Create;
  try
    FileIds := AStore.GetAllFileIds;
    for Id in FileIds do
    begin
      Path := AStore.GetFilePath(Id);
      if Path <> '' then Paths.Add(Path);
    end;
    Result := AggregateOverFiles(AStore, Paths.ToArray, AOptions);
  finally
    Paths.Free;
  end;
end;

end.
