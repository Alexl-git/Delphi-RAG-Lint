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
  here). IncludeSeeAlso (ADF T4) and IncludeSince / BaseDir (ADF T5) are threaded
  into TDocumenter.BuildFor so the --seealso and --since opt-ins reach the facts
  builder (BaseDir is the git repo root for the <since> lookup). IncludeDeprecated
  is threaded for forward compatibility and is a no-op here.

  Trivial-accessor filter (ADP1 T2, ON BY DEFAULT): a Get*/Set* method whose
  impl body spans <= AOptions.AccessorTrivialMaxLines lines (default 2, from
  the manifest's docs.accessor_trivial_max_lines) is skipped entirely -- see
  IsTrivialAccessor -- so a one-line getter/setter does not clutter the unit
  with a doc comment. AOptions.IncludeAccessors (CLI --include-accessors)
  disables this for one run. This filter applies ONLY to the batch engine
  here; the single-symbol document --qname path (TDocumenter.BuildFor called
  directly by the CLI) never runs through this unit and is never filtered. }

interface

uses
  System.SysUtils, { TFunc, for TDocBatchOptions.IsExcluded }
  DRagLint.Core.Model, DRagLint.Core.Interfaces,
  DRagLint.Refactor.TextEdit;

type
  /// <summary>Batch-documentation options. Stubs=False (default) is the
  /// facts-only policy: drop pure all-TODO creates, keep facts-backed or
  /// previously-documented decls. The remaining flags are threaded for later
  /// doc-source tasks and are inert here.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoDocumentUnit (DRagLint.CLI.pas), DRagLint.CLI.DoDocumentProject (DRagLint.CLI.pas), DRagLint.CLI.DoDocumentAll (DRagLint.CLI.pas), declaration (DRagLint.Doc.Batch.pas), DRagLint.Doc.Batch.TDocBatch.DocumentUnit (DRagLint.Doc.Batch.pas) (+2 more)
  /// Used in units: DRagLint.CLI, DRagLint.Doc.Batch
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocBatchOptions = record
    Stubs            : Boolean; // opt-in TODO summaries; default False = facts-only
    /// <summary>v(ADP3 T2): --strip. When True the batch REMOVES engine output
    /// (every AUTO_MARK-carrying tag and every AUTO_BEGIN..AUTO_END region)
    /// instead of generating it. Hand-written tags, code and ordinary comments
    /// are untouched. Mutually exclusive with Stubs.</summary>
    Strip: Boolean;
    IncludeSeeAlso   : Boolean;
    IncludeDeprecated: Boolean;
    IncludeSince     : Boolean;
    BaseDir          : string ; // repo root for git <since>; '' = cwd
    /// <summary>Additional open index stores searched (name-based only) for
    /// Called-from/Used-in facts, alongside the primary AStore. Nil/empty
    /// preserves single-store behavior.</summary>
    ExtraStores      : TArray<ISymbolStore>;
    /// <summary>Cap on mined &lt;returns&gt; enumeration cases, forwarded to
    /// BuildFor/TDocFactsBuilder.Build. NOTE: Default(TDocBatchOptions) zero-fills
    /// this to 0 (enumeration disabled) -- every caller MUST set it explicitly
    /// (from the manifest's Docs.MaxReturnCases, default 20) rather than relying
    /// on the record default.</summary>
    MaxReturnCases   : Integer;
    /// <summary>Cap on the "Called from:" list, forwarded to
    /// BuildFor/TDocFactsBuilder.Build (v(ADP1 T1)). NOTE: Default(TDocBatchOptions)
    /// zero-fills this to 0 (no callers shown) -- every caller MUST set it
    /// explicitly (from the manifest's Docs.MaxCallers, default 5) rather than
    /// relying on the record default.</summary>
    MaxCallers       : Integer;
    /// <summary>ADP1 T2: threshold (impl body line count) at or under which a
    /// Get*/Set* method is skipped as a trivial property accessor (see
    /// IsTrivialAccessor). NOTE: Default(TDocBatchOptions) zero-fills this to
    /// 0 -- every caller MUST set it explicitly (from the manifest's
    /// Docs.AccessorTrivialMaxLines, default 2 -- the filter is ON BY
    /// DEFAULT, unlike MaxReturnCases/MaxCallers) rather than relying on the
    /// record default.</summary>
    AccessorTrivialMaxLines: Integer;
    /// <summary>ADP1 T2: --include-accessors. True disables the trivial-
    /// accessor skip for this run (every accessor is documented like any
    /// other public method, regardless of AccessorTrivialMaxLines).</summary>
    IncludeAccessors: Boolean;
    /// <summary>v(ADP2 T3): threshold for the 'Complexity:' render line,
    /// forwarded to BuildForSymbol/TDocRegions.RenderFactsBlock as-is (docs.
    /// complexity_min, default 10). NOTE: Default(TDocBatchOptions) zero-fills
    /// this to 0 -- every caller MUST set it explicitly (from the manifest's
    /// Docs.ComplexityMin) rather than relying on the record default, same
    /// discipline as MaxReturnCases/MaxCallers above. UNLIKE those two, a
    /// stray 0 here is still SAFE (RenderFactsBlock's own Cyclomatic &gt; 0
    /// guard means threshold 0 shows every real routine's complexity rather
    /// than mis-rendering an absent fact -- see its remarks), but callers
    /// should still set the real configured value for the intended default
    /// (10, not "show everything").</summary>
    ComplexityMin: Integer;
    /// <summary>True documents the project's WHOLE compile closure, including
    /// vendored third-party source. False (the default, and what
    /// Default(TDocBatchOptions) gives) restricts DocumentProject to the roots
    /// the project declares as its own.</summary>
    /// <remarks>`document --project` used to write wherever the closure reached.
    /// On 2026-08-12 a YADF run applied its only two edits to
    /// C:\Projects\DelphiAST -- a vendored parser in its own repository -- for a
    /// 4,287-line diff, while nothing under the project changed. `lint-all`
    /// already refuses to REPORT on code a project does not own; writing to it
    /// is strictly worse than reporting on it, so the same declaration governs
    /// both. Mirrors --lint-third-party as --document-third-party.</remarks>
    DocumentThirdParty: Boolean;
    /// <summary>"Is this file excluded from all drag-lint processing?" --
    /// normally TLintConfig.IsPathExcluded, supplied by the caller. Nil means no
    /// exclusions, which is what Default(TDocBatchOptions) gives.</summary>
    /// <remarks>OWNERSHIP IS TWO SETTINGS AND ONLY ONE WAS THREADED HERE. On
    /// 2026-08-14 an autodoc pass over drag-lint's OWN source left 2,300
    /// generated lines in third_party\delphi-tree-sitter, vendored upstream
    /// bindings the repo explicitly declines to restyle. Its ownRoots is the
    /// REPO ROOT on purpose (the .dproj sits in src\cli, so defaulting to the
    /// project folder would classify the rest of the repo as third-party), and
    /// the vendored-code exclusion therefore lives entirely in
    /// drag-lint-lint.json's exclude_paths -- which was a LINT-ONLY concept.
    /// TOwnRoots reached the writers; its neighbour did not. The two checks sit
    /// on ADJACENT LINES in lint-all's file loop (DRagLint.CLI.pas, around the
    /// Cfg.IsPathExcluded / Own.IsOurs pair) and only the second was propagated.
    ///
    /// Passed as a PREDICATE rather than as the glob list, so the one
    /// implementation of the match answers for both commands instead of a second
    /// copy of the glob logic drifting from the first. Passed rather than loaded
    /// here for two reasons: TOwnRoots is deliberately standalone (its own header
    /// explains that the LSP and the IDE plugin must not drag in the lint
    /// configuration machinery), and config DISCOVERY is CWD-sensitive -- the
    /// caller already resolved --config correctly, and re-deriving it here from
    /// the current directory would silently find nothing on exactly the runs
    /// that matter.
    ///
    /// Applied UNCONDITIONALLY, before the DocumentThirdParty escape hatch,
    /// mirroring lint-all: exclude_paths means "never touch these", while
    /// ownRoots means "mine versus third-party" and is what the flag opens up.
    /// --lint-third-party does not defeat exclude_paths, so
    /// --document-third-party must not either.</remarks>
    IsExcluded: TFunc<string, Boolean>;
  end;

  /// <summary>Aggregated batch result. Edits is the union of every kept
  /// declaration's edits, ordered by line DESCENDING so applying an earlier
  /// edit does not shift a later declaration's line numbers. DeclCount is the
  /// number of public interface-section documentable declarations considered;
  /// DocCount is how many of them contributed at least one edit.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoDocumentUnit (DRagLint.CLI.pas), DRagLint.CLI.DoDocumentProject (DRagLint.CLI.pas), DRagLint.CLI.DoDocumentAll (DRagLint.CLI.pas), declaration (DRagLint.Doc.Batch.pas), DRagLint.Doc.Batch.TDocBatch.DocumentUnit (DRagLint.Doc.Batch.pas) (+3 more)
  /// Used in units: DRagLint.CLI, DRagLint.Doc.Batch
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocBatchResult = record
    Edits    : TArray<TTextEdit>;
    DeclCount: Integer;
    DocCount : Integer;
    /// <summary>ADP1 T2: count of public Get*/Set* methods skipped as trivial
    /// property accessors (not counted in DeclCount -- see IsTrivialAccessor).
    /// Always 0 when AOptions.IncludeAccessors was True for the run.</summary>
    AccessorsSkipped: Integer;
    /// <summary>v(ADP3 T2): --strip. Count of marked tags dropped
    /// (TDocStripper.TagsRemoved, summed across every file the batch
    /// touched). 0 unless AOptions.Strip was True for this run.</summary>
    TagsRemoved: Integer;
    /// <summary>v(ADP3 T2): --strip. Count of AUTO_BEGIN..AUTO_END facts
    /// regions dropped (TDocStripper.BlocksRemoved, summed across every file
    /// the batch touched). 0 unless AOptions.Strip was True for this
    /// run.</summary>
    BlocksRemoved: Integer;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoDocumentUnit (DRagLint.CLI.pas), DRagLint.CLI.DoDocumentProject (DRagLint.CLI.pas), DRagLint.CLI.DoDocumentAll (DRagLint.CLI.pas), DRagLint.Doc.Batch.AggregateOverFiles (DRagLint.Doc.Batch.pas)
  /// Used in units: DRagLint.CLI, DRagLint.Doc.Batch
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocBatch = class
  public
    /// <summary>Documents every public (interface-section) declaration in
    /// AUnitFile: routines, methods, ctors/dtors and type declarations (private
    /// fields/consts are skipped). ADP1 T2: a Get*/Set* method whose impl body
    /// spans &lt;= AOptions.AccessorTrivialMaxLines lines is also skipped as a
    /// trivial property accessor (see IsTrivialAccessor), unless
    /// AOptions.IncludeAccessors is True. For each remaining decl, computes
    /// the DocInsight edits via TDocumenter.BuildFor and, under the facts-only
    /// default (AOptions.Stubs=False), keeps the edit only when the merged
    /// comment carries a managed facts block or the declaration already had a
    /// doc-comment. Returns the aggregated, line-descending edit set plus the
    /// decl/doc/accessors-skipped counts. Does not write files; the caller
    /// applies the edits.</summary>
    /// <param name="AStore">Open symbol store to query; not owned. Must not be nil.</param>
    /// <param name="AUnitFile">Path (relative or absolute) to the unit's source file, as stored/resolvable in the index.</param>
    /// <param name="AOptions">Batch options; Stubs gates the facts-only filter, AccessorTrivialMaxLines/IncludeAccessors gate the trivial-accessor filter.</param>
    /// <returns>Aggregated edits + DeclCount (public decls seen, after the accessor filter) + DocCount (decls contributing an edit) + AccessorsSkipped.</returns>
    /// <remarks>
    /// Not thread-safe; call from the owning thread only.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoDocumentUnit (DRagLint.CLI.pas), DRagLint.Doc.Batch.AggregateOverFiles (DRagLint.Doc.Batch.pas)
    /// Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile, DRagLint.Doc.Batch.HasManagedBlock, DRagLint.Doc.Batch.IsDocumentableKind, DRagLint.Doc.Batch.IsTrivialAccessor, DRagLint.Doc.Document.TDocumenter.BuildForSymbol, DRagLint.Doc.Strip.TDocStripper.StripFile, Format, SameText, Writeln
    /// Returns: Default(TDocBatchResult)
    /// Complexity: 14 (cyclomatic, outer body), 126 lines (full implementation)
    /// Pure
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile"/>
    /// <seealso cref="DRagLint.Doc.Batch.HasManagedBlock"/>
    /// <seealso cref="DRagLint.Doc.Batch.IsDocumentableKind"/>
    /// <seealso cref="DRagLint.Doc.Batch.IsTrivialAccessor"/>
    /// <seealso cref="DRagLint.Doc.Document.TDocumenter.BuildForSymbol"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
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
    /// <remarks>
    /// Not thread-safe; call from the owning thread only.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoDocumentProject (DRagLint.CLI.pas)
    /// Calls: DRagLint.Doc.Batch.AggregateOverFiles, DRagLint.Doc.Batch.FilterToOwnRoots, DRagLint.Index.Closure.TClosureResolver.Create, DRagLint.Index.Closure.TClosureResolver.Resolve, DRagLint.Project.Resolver.TProjectResolver.Create, DRagLint.Project.Resolver.TProjectResolver.ResolveLibraryPaths
    /// Returns: AggregateOverFiles(AStore, FilterToOwnRoots(CR.Files, AProjectFile, AOptions), AOptions)
    /// Pure
    /// <seealso cref="DRagLint.Doc.Batch.AggregateOverFiles"/>
    /// <seealso cref="DRagLint.Doc.Batch.FilterToOwnRoots"/>
    /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.Create"/>
    /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.Resolve"/>
    /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
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
    /// <remarks>
    /// Not thread-safe; call from the owning thread only.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoDocumentAll (DRagLint.CLI.pas)
    /// Calls: DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Doc.Batch.AggregateOverFiles
    /// Returns: AggregateOverFiles(AStore, Paths.ToArray, AOptions)
    /// Pure
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Doc.Batch.AggregateOverFiles"/>
    /// <seealso cref="DRagLint.Doc.Batch.TDocBatch.DocumentProject"/>
    /// <seealso cref="DRagLint.Doc.Batch.TDocBatch.DocumentUnit"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function DocumentAll(const AStore: ISymbolStore;
      const AOptions: TDocBatchOptions): TDocBatchResult;
  end;

implementation

uses
  { System.SysUtils is in the INTERFACE uses now -- TDocBatchOptions.IsExcluded
    needs TFunc there -- so repeating it here is E2004. }
  System.StrUtils, System.Generics.Collections, System.Generics.Defaults,
  DRagLint.Doc.Document, DRagLint.Doc.Regions, DRagLint.Doc.Strip,
  DRagLint.Index.Closure, DRagLint.Project.Resolver,
  { Ownership for DocumentProject -- the same declaration lint-all reads, so the
    two commands cannot disagree about which files belong to the project. }
  DRagLint.Project.OwnRoots;

// A declaration whose doc-comment we generate: routines/methods/ctors/dtors and
// declared types. Fields, consts, vars, enum values, unit/program markers and
// SQL symbols are NOT documented in the whole-unit batch.
function IsDocumentableKind(AKind: TSymbolKind): Boolean;
begin
  Result := AKind in
    [skProcedure, skFunction, skMethod, skConstructor, skDestructor,
     skClass, skInterface, skRecord, skEnum, skTypeAlias];
end;

// True when the result's edits carry INDEX-GROUNDED content -- something mined
// from the code, as opposed to a pure all-TODO create.
//
// The facts fence (AUTO_BEGIN) was the only thing this looked for, which was
// complete only while the fence was the ONLY place mined content could appear.
// It no longer is: a mined raise becomes an engine-owned <exception cref>, and
// a mined return becomes an engine-owned <returns>, both of which sit OUTSIDE
// the fence. A routine whose one fact was a raise therefore produced a perfectly
// good comment and had it dropped here -- invisible in `document --unit` and
// `--project` while `--qname` emitted it, which is the same
// two-halves-disagree shape this file has been bitten by before.
//
// <param> is deliberately NOT counted even though it carries the same ownership
// marker. It is emitted STRUCTURALLY for every parameter of every routine (ruling
// D-3) and mines nothing, so counting it would admit exactly the empty-skeleton
// create this gate exists to drop -- and would do it for nearly every routine in
// a codebase.
function HasManagedBlock(const ARes: TDocumentResult): Boolean;
var
  E: TTextEdit;
begin
  for E in ARes.Edits do
  begin
    if System.Pos(AUTO_BEGIN, E.Text) > 0 then Exit(True);
    if System.Pos('<exception cref="', E.Text) > 0 then Exit(True);
    if System.Pos('<returns>' + AUTO_MARK, E.Text) > 0 then Exit(True);
  end;
  Result := False;
end;

// ADP1 T2: is ASym a TRIVIAL property accessor? The index does not store a
// method<->property linkage (a property's stored PropAccess is its ro/rw/wo
// MODE, not the read/write accessor's method id -- see the task report for
// the schema check), so this is a deliberate, spec-sanctioned FALLBACK
// heuristic: a class method (Kind = skMethod; free skProcedure/skFunction
// routines are never accessors) whose Name starts with 'Get' or 'Set' AND
// whose recorded impl body span (ImplEndLine - ImplStartLine) is <=
// AMaxLines. KNOWN LIMITATION: a trivial non-accessor method that happens to
// be named Get*/Set* (e.g. a one-line 'procedure SetupDefaults;' -- 'Set'
// prefix) is also skipped in batch modes; --include-accessors and
// document --qname both bypass this filter entirely.
function IsTrivialAccessor(const ASym: TSymbol; AMaxLines: Integer): Boolean;
begin
  Result := False;
  if ASym.Kind <> skMethod then Exit;
  if not (StartsText('Get', ASym.Name) or StartsText('Set', ASym.Name)) then Exit;
  if ASym.ImplStartLine <= 0 then Exit; // no recorded body span (abstract/interface method) -- never trivial
  Result := (ASym.ImplEndLine - ASym.ImplStartLine) <= AMaxLines;
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

  { THE ONE PLACE exclude_paths is enforced, because this is the one place every
    entry point funnels through: `document --project` and `document-all` arrive
    via AggregateOverFiles, and `document --unit` calls straight in here, never
    touching AggregateOverFiles or FilterToOwnRoots. Putting the check beside
    ownRoots -- the intuitive home -- would have missed --unit and would have
    been defeated by --document-third-party, which is exactly the "fixed it per
    COMMAND" mistake this defect's own predecessor note closed with.
    Before --strip too: stripping engine output from vendored source is still
    writing to it.
    AggregateOverFiles counts these and reports once for the batch, so the
    message below is only reached on the direct --unit path. }
  if Assigned(AOptions.IsExcluded) and AOptions.IsExcluded(AUnitFile) then
  begin
    Writeln(ErrOutput, Format('doc: %s skipped by exclude_paths.', [AUnitFile]));
    Exit;
  end;

  // v(ADP3 T2): --strip bypasses the whole per-symbol facts pipeline below --
  // it never queries AStore at all, just scans AUnitFile's raw lines for
  // engine-owned markers and computes their removal (TDocStripper.StripFile
  // works on raw source, not the parsed doc model, and does not depend on
  // the file being indexed). Mutually exclusive with Stubs; the CLI rejects
  // that combination before either reaches here.
  if AOptions.Strip then
  begin
    var StripRes: TStripResult := TDocStripper.StripFile(AUnitFile);
    Result.Edits        := StripRes.Edits;
    Result.TagsRemoved  := StripRes.TagsRemoved;
    Result.BlocksRemoved:= StripRes.BlocksRemoved;
    Exit;
  end;

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

      // ADP1 T2: batch modes (document --unit/--project, document-all) skip
      // TRIVIAL property accessors -- see IsTrivialAccessor. Not counted in
      // DeclCount (treated as never a candidate, like a private field or a
      // non-documentable kind above), counted separately in AccessorsSkipped
      // for the run summary. --include-accessors (AOptions.IncludeAccessors)
      // disables this for the whole run. document --qname (BuildFor, called
      // directly by the CLI) never goes through this loop, so it is
      // unaffected by this filter.
      if (not AOptions.IncludeAccessors) and IsTrivialAccessor(Sym, AOptions.AccessorTrivialMaxLines) then
      begin
        Inc(Result.AccessorsSkipped);
        Continue;
      end;

      Inc(Result.DeclCount);

      // Pass the ROW's own resolved Sym (not just its qualified_name) so an
      // overloaded method -- multiple TSymbol rows sharing one qualified_name
      // -- documents each row's OWN declaration. BuildFor(Sym.QualifiedName)
      // would re-resolve every call to Syms[0], stacking duplicate blocks
      // above the first overload and never documenting the others (Bug A).
      Res := TDocumenter.BuildForSymbol(AStore, Sym, AOptions.IncludeSeeAlso,
        AOptions.IncludeSince, AOptions.BaseDir, AOptions.ExtraStores, AOptions.MaxReturnCases,
        AOptions.MaxCallers, AOptions.ComplexityMin);
      if Length(Res.Edits) = 0 then Continue; // daUnchanged / daNotFound: nothing to do

      // Facts-only filter (Stubs=False, the default): keep the edit when the
      // merged comment has a managed facts block, OR the decl already had a
      // doc-comment (daExtended / daRemoved). Drop a pure fresh
      // all-TODO-no-facts create.
      // Stubs=True keeps every create too (wired fully in a later task).
      //
      // v(ADP3 T3k, register D1): daRemoved MUST be admitted here and it is not
      // cosmetic. It is the pure-deletion action, which used to be reported as
      // daExtended -- so before D1 this test caught it by accident. A deletion
      // edit carries NO text, hence no AUTO_BEGIN fence, so HasManagedBlock is
      // False for it; had daRemoved been added without touching this line, a
      // project-wide `document --project --apply` would have silently STOPPED
      // removing decayed engine blocks while --qname kept doing it. Splitting an
      // enum value is only safe when every site that tested the old value is
      // re-decided, and this was the site where "no change needed" was wrong.
      if AOptions.Stubs then
        Keep := True
      else
        Keep := HasManagedBlock(Res) or (Res.Action in [daExtended, daRemoved]);

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
  F            : string;
  Sub          : TDocBatchResult;
  Collected    : TList<TTextEdit>;
  E            : TTextEdit;
  ExcludedCount: Integer;
begin
  Result := Default(TDocBatchResult);
  Collected := TList<TTextEdit>.Create;
  ExcludedCount := 0;
  try
    for F in AFiles do
    begin
      // Only Delphi sources carry documentable decls; skip include files and
      // any non-.pas closure member so DocumentUnit is not asked to parse them.
      if not SameText(ExtractFileExt(F), '.pas') then Continue;
      { Counted and reported ONCE for the batch. DocumentUnit refuses an excluded
        file on its own too -- that is the guarantee, and it covers `document
        --unit`, which never comes through here -- but its per-file message would
        repeat a hundred times on a whole-project run. }
      if Assigned(AOptions.IsExcluded) and AOptions.IsExcluded(F) then
      begin
        Inc(ExcludedCount);
        Continue;
      end;
      Sub := TDocBatch.DocumentUnit(AStore, F, AOptions);
      Inc(Result.DeclCount, Sub.DeclCount);
      Inc(Result.DocCount , Sub.DocCount );
      Inc(Result.AccessorsSkipped, Sub.AccessorsSkipped); // ADP1 T2
      Inc(Result.TagsRemoved  , Sub.TagsRemoved  ); // v(ADP3 T2): --strip
      Inc(Result.BlocksRemoved, Sub.BlocksRemoved); // v(ADP3 T2): --strip
      for E in Sub.Edits do Collected.Add(E);
    end;
    Result.Edits := Collected.ToArray;
    { Named, not silent, for the same reason FilterToOwnRoots names its skipped
      roots: a silent drop is indistinguishable from "there was nothing there",
      which is exactly how 2,300 generated lines reached vendored source without
      anyone noticing. }
    if ExcludedCount > 0 then
      Writeln(ErrOutput, Format('doc: %d file(s) skipped by exclude_paths.', [ExcludedCount]));
  finally
    Collected.Free;
  end;
end;

{ Keeps only the files the project declares as its own, and NAMES what it drops.
  A silent drop is indistinguishable from "there was nothing there", which is the
  failure shape that let the DelphiAST writes go unnoticed across several
  sessions -- so the skipped roots are reported with their file counts, exactly
  as lint-all reports them. Returns AFiles unchanged when the caller opted into
  third-party or when no declaration is active (an undeclared project keeps the
  pre-existing behaviour of its own folder, via TOwnRoots.Load's default). }
function FilterToOwnRoots(const AFiles: TArray<string>; const AProjectFile: string;
  const AOptions: TDocBatchOptions): TArray<string>;
var
  Own    : TOwnRoots               ;
  Kept   : TList<string>           ;
  Skipped: TDictionary<string, Integer>;
  Root, F: string                  ;
  N      : Integer                 ;
begin
  Result:= AFiles;
  if AOptions.DocumentThirdParty then Exit;

  Own:= TOwnRoots.Load(ExtractFilePath(AProjectFile));
  if not Own.Active then Exit;

  { exclude_paths is deliberately NOT checked here. It is not an ownership
    question and it must hold even when this filter bails out early (under
    --document-third-party, or with no declaration active), so it lives at the
    one place every entry point funnels through -- DocumentUnit -- rather than
    beside ownRoots. See TDocBatchOptions.IsExcluded. }
  Kept   := TList<string>.Create;
  Skipped:= TDictionary<string, Integer>.Create;
  try
    for F in AFiles do
      if Own.IsOurs(F) then
        Kept.Add(F)
      else
      begin
        { Group by the immediate parent directory so the report names a place a
          reader recognises ("C:\Projects\DelphiAST\Source -- 8 file(s)") rather
          than listing every file. }
        Root:= ExcludeTrailingPathDelimiter(ExtractFilePath(F));
        if not Skipped.TryGetValue(Root, N) then N:= 0;
        Skipped.AddOrSetValue(Root, N + 1);
      end;

    for Root in Skipped.Keys do
      Writeln(ErrOutput, Format('doc: skipped third-party root %s -- %d file(s). Use --document-third-party to include it.',
        [Root, Skipped[Root]]));

    Result:= Kept.ToArray;
  finally
    Skipped.Free;
    Kept.Free;
  end; // try
end; // function

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

  { OWNERSHIP, not just closure. The closure is the right answer to "what does
    this project compile" and the WRONG answer to "what may this command
    rewrite": it legitimately contains vendored third-party source. The library
    path already removes dependencies installed as libraries, but a vendored
    checkout that is merely `uses`d is not on it, so it stays in the closure and
    was being edited. `lint-all` refuses to REPORT on such code; writing to it is
    strictly worse, so both read the same declaration. }
  Result := AggregateOverFiles(AStore, FilterToOwnRoots(CR.Files, AProjectFile, AOptions), AOptions);
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
