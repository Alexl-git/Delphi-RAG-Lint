unit DRagLint.Index.PPUnitSource;

// Lane INC3 (2026-10-27): the used-unit half of the IF-directive symbol table.
// The preprocessor resolves a name in the constants of its own active text
// first; for a name it does not declare it asks the installed IPPUnitSource
// about each unit of the uses clause. This is that source.
//
// HOW A UNIT IS ANSWERED
//   1. A PROJECT unit (a file the closure listed, or a unit symbol of a project
//      DB) is SCANNED: preprocessed under the project's profile with the same
//      source installed, and its interface declarations kept. This is the
//      per-unit pre-pass that makes index ORDER irrelevant -- a unit's
//      constants are known before the unit itself is indexed, and the scan
//      honours that unit's own IF branches (a constant inside an inactive
//      branch of the used unit does not count either). One scan per unit per
//      run; a uses cycle answers 'unknown' for the unit already in progress.
//   2. Any other unit is asked of the LIBRARY DBs: a const symbol's stored
//      signature ('= <expr>' since extractor 1.6.0) is evaluated in that
//      unit's scope; '<type> = <v>' is a typed constant (declared, not a true
//      constant); every other kind is declared. An unqualified uses name
//      (SysUtils) matches its namespaced unit (System.SysUtils).
//
// THREAD-SAFETY: every lookup runs under one re-entrant lock (a scan recurses
// into LookupInUnit on the same thread).

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  DRagLint.Core.Interfaces,
  DRagLint.Preprocess.Types,
  DRagLint.Preprocess.Expr,
  DRagLint.Preprocess.Decls;

type
  /// <summary>1.52.3 INCRPP-LIMITS: the project files a unit's constants depend on, so a
  /// host whose IF read that unit can be re-parsed when one of them changes.</summary>
  /// <remarks>Implemented by TPPUnitSourceResolver; asked for through Supports.</remarks>
  IPPUnitDeps = interface
    ['{8533D028-07F6-4699-B842-C49E284F3F10}']
    /// <summary>The project file of AUnit plus the project file of every unit its scan
    /// asked a constant of, transitively (a constant defined through another unit's
    /// constant).</summary>
    /// <param name="AUnit">The unit name as the uses clause spells it.</param>
    /// <returns>Absolute paths, de-duplicated, AUnit's own first; library units are left
    /// out; empty when AUnit is not a project unit.</returns>
    function UnitFileClosure(const AUnit: string): TArray<string>;
  end;

  /// <summary>The IPPUnitSource the index and lint runs install (see the unit
  /// header for how each unit is answered).</summary>
  /// <remarks>
  /// Thread-safe. Opens its DBs read-only, lazily, on first need.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Index.PPUnitSource.pas) ?, DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas) ?, DRagLint.CLI.DoIndex (DRagLint.CLI.pas) ?, DRagLint.Index.PPUnitSource.InstallPPUnitSource (DRagLint.Index.PPUnitSource.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Index.PPUnitSource</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TPPUnitSourceResolver = class(TInterfacedObject, IPPUnitSource, IPPUnitFiles, IPPUnitDeps)  // dl:ok high-response@267d -- REVIEWED 2026-11-20: the resolver IS the per-run IF symbol table (IPPUnitSource + IPPUnitFiles + IPPUnitDeps over one lock and one scan cache); 1.52.3 INCRPP-LIMITS added UnitFileClosure, which must read the same scan cache under the same lock
  private type
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Used by: declaration (DRagLint.Index.PPUnitSource.pas) ?, DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AskLibrary (DRagLint.Index.PPUnitSource.pas), DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.Create (DRagLint.Index.PPUnitSource.pas) ?, DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.LookupInUnit (DRagLint.Index.PPUnitSource.pas) ?</para>
    /// <para>Used in units: DRagLint.Index.PPUnitSource</para>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AddUnitFiles"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AskLibrary"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.Create"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.Destroy"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.EvalInUnit"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    TAnswer = record
      Kind : TPPNameKind;
      Value: TPPValue;
    end;
  private
    FLock       : TCriticalSection;
    FProfile    : TDefineProfile;
    FSearchPaths: TArray<string>;
    FDefines    : TDictionary<string, Boolean>;
    FNumeric    : TDictionary<string, Integer>;
    FUnitFiles  : TDictionary<string, string>;
    FScanned    : TObjectDictionary<string, TDictionary<string, TPPDecl>>;
    FInProgress : TDictionary<string, Boolean>;
    { 1.52.3 INCRPP-LIMITS: the scans in progress, innermost last, and per scanned unit
      key the units its scan asked (lowercased) -- IPPUnitDeps.UnitFileClosure. }
    FScanStack  : TList<string>;
    FScanDeps   : TObjectDictionary<string, TList<string>>;
    FAnswers    : TDictionary<string, TAnswer>;
    FProjectDbs : TArray<string>;
    FLibraryDbs : TArray<string>;
    FProjStores : TArray<ISymbolStore>;
    FLibStores  : TArray<ISymbolStore>;
    FStoresOpen : Boolean;
    FDepth      : Integer;
    FUnknownAnswers: Integer;
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AskLibrary (DRagLint.Index.PPUnitSource.pas), DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.HasLibraryEvidence (DRagLint.Index.PPUnitSource.pas), DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.UnitFile (DRagLint.Index.PPUnitSource.pas)</para>
    /// <para>Calls: DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.OpenStores.OpenAll</para>
    /// <para>Reads: FStoresOpen, FProjectDbs, FLibraryDbs   Writes: FStoresOpen, FProjStores, FLibStores</para>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.OpenStores.OpenAll"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AddUnitFiles"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AskLibrary"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.Create"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure OpenStores;
    /// <summary><!-- drag-lint:auto sum -->The project source file of AUnit, or '' when
    /// it is not a project unit.</summary>
    /// <param name="AUnit"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: ''; S.GetFilePath(Sym.FileId).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.LookupInUnit (DRagLint.Index.PPUnitSource.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.OpenStores, LowerCase, SameText</para>
    /// <para>Reads: FUnitFiles, FProjStores</para>
    /// <para>Touches: file system</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.OpenStores"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AddUnitFiles"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AskLibrary"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function UnitFile(const AUnit: string): string;
    /// <param name="AKey"><!-- drag-lint:auto type -->const string</param>
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->TDictionary&lt;string, TPPDecl&gt; -- Observed:
    /// TDictionary&lt;string, TPPDecl&gt;.Create.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.LookupInUnit (DRagLint.Index.PPUnitSource.pas)</para>
    /// <para>Calls: DRagLint.Core.Encoding.EnsureUtf8Bytes, DRagLint.Preprocess.PreprocessReport, DRagLint.Preprocess.Types.TPPOptionsDefault, LowerCase</para>
    /// <para>Reads: FScanned, FInProgress, FProfile, FSearchPaths</para>
    /// <para>Owns returned: new (caller owns)</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <para>Touches: file system</para>
    /// <seealso cref="DRagLint.Core.Encoding.EnsureUtf8Bytes"/>
    /// <seealso cref="DRagLint.Preprocess.PreprocessReport"/>
    /// <seealso cref="DRagLint.Preprocess.Types.TPPOptionsDefault"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AddUnitFiles"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AskLibrary"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Scan(const AKey, APath: string): TDictionary<string, TPPDecl>;
    /// <param name="AUnit"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->TAnswer -- Observed: Default(TAnswer).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.LookupInUnit (DRagLint.Index.PPUnitSource.pas)</para>
    /// <para>Calls: Copy, Default, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName, DRagLint.Index.PPUnitSource.SafeByName, DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.EvalInUnit, DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.OpenStores, LowerCase, Pos, Trim</para>
    /// <para>Complexity: 13 (cyclomatic, outer body), 56 lines (full implementation)</para>
    /// <para>Reads: FLibStores, FDepth   Writes: FDepth</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.SafeByName"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.EvalInUnit"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.OpenStores"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AddUnitFiles"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function AskLibrary(const AUnit, AName: string): TAnswer;
    /// <summary><!-- drag-lint:auto sum -->Evaluates a library constant's expression in
    /// its own unit's scope: names resolve in AUnitQName, then System.</summary>
    /// <param name="AUnitQName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AExpr"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AValue"><!-- drag-lint:auto type -->out TPPValue</param>
    /// <returns><!-- drag-lint:auto type -->Boolean</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AskLibrary (DRagLint.Index.PPUnitSource.pas)</para>
    /// <para>Calls: DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.LookupInUnit, DRagLint.Preprocess.Expr.TryEvalPPConst, SameText</para>
    /// <para>Reads: FDefines, FNumeric</para>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.LookupInUnit"/>
    /// <seealso cref="DRagLint.Preprocess.Expr.TryEvalPPConst"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AddUnitFiles"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AskLibrary"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function EvalInUnit(const AUnitQName, AExpr: string; out AValue: TPPValue): Boolean;
  public
    /// <summary>Constructor: a source for one run.</summary>
    /// <param name="AProfile">The define profile project units are scanned under.</param>
    /// <param name="ASearchPaths">Include search paths for those scans.</param>
    /// <param name="AProjectDbs">Project DBs: their unit symbols locate project
    /// files to scan (missing files are skipped). May be empty.</param>
    /// <param name="ALibraryDbs">Library DBs answered from symbols. May be empty;
    /// paths that do not exist are ignored.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.PPUnitSource.InstallPPUnitSource (DRagLint.Index.PPUnitSource.pas)</para>
    /// <para>Calls: LowerCase</para>
    /// <para>constructor</para>
    /// <para>Reads: FDefines, FNumeric   Writes: FLock, FProfile, FSearchPaths, FProjectDbs, FLibraryDbs, FDefines, FNumeric, FUnitFiles (+3 more)</para>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AddUnitFiles"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AskLibrary"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.Destroy"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.EvalInUnit"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.HasLibraryEvidence"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(const AProfile: TDefineProfile; const ASearchPaths, AProjectDbs, ALibraryDbs: TArray<string>);
    /// <summary>Frees the caches and closes the DBs.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FAnswers, FInProgress, FScanned, FUnitFiles, FNumeric, FDefines, FLock   Writes: FProjStores, FLibStores</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AddUnitFiles"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AskLibrary"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.Create"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.EvalInUnit"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.HasLibraryEvidence"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>Registers project source files (unit name = file base name);
    /// non-.pas paths are ignored. Clears every cached answer.</summary>
    /// <param name="APaths">Absolute paths, e.g. a closure's file list.</param>
    /// <param name="ASearchPaths">Include search paths for the scans (replaces the earlier ones).</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas)</para>
    /// <para>Calls: ExtractFileExt, LowerCase, SameText</para>
    /// <para>Reads: FLock, FUnitFiles, FAnswers, FScanned   Writes: FSearchPaths, FUnknownAnswers</para>
    /// <para>Touches: file system</para>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AskLibrary"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.Create"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.Destroy"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.EvalInUnit"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.HasLibraryEvidence"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure AddUnitFiles(const APaths, ASearchPaths: TArray<string>);
    /// <summary>See IPPUnitSource.LookupInUnit.</summary>
    /// <param name="AUnit">The unit as the uses clause spells it.</param>
    /// <param name="AName">The bare symbol name.</param>
    /// <param name="AValue">The value when pnkConst is returned.</param>
    /// <returns>How AUnit declares AName.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.EvalInUnit (DRagLint.Index.PPUnitSource.pas)</para>
    /// <para>Calls: Default, DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AskLibrary, DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.Scan, DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.UnitFile, LowerCase</para>
    /// <para>Returns: pnkUnknown; pnkTypedConst; pnkDeclared; pnkConst; A.Kind</para>
    /// <para>Implements: DRagLint.Preprocess.Decls.IPPUnitSource.LookupInUnit</para>
    /// <para>Complexity: 11 (cyclomatic, outer body), 39 lines (full implementation)</para>
    /// <para>Reads: FLock, FInProgress, FAnswers   Writes: FUnknownAnswers</para>
    /// <para>Mutates: AValue (out)</para>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AskLibrary"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.Scan"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.UnitFile"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AddUnitFiles"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function LookupInUnit(const AUnit, AName: string; out AValue: TPPValue): TPPNameKind;
    /// <summary>See IPPUnitSource.HasLibraryEvidence.</summary>
    /// <returns>True when a library DB opened; opens them on first need.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Calls: DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.OpenStores</para>
    /// <para>Returns: Length(FLibStores) &gt; 0</para>
    /// <para>Implements: DRagLint.Preprocess.Decls.IPPUnitSource.HasLibraryEvidence</para>
    /// <para>Reads: FLock, FLibStores</para>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.OpenStores"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AddUnitFiles"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.AskLibrary"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.Create"/>
    /// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function HasLibraryEvidence: Boolean;
    /// <summary>INCRPP (IPPUnitFiles): the project source file AUnit is answered from.</summary>
    /// <param name="AUnit">The unit name as the uses clause spells it.</param>
    /// <returns>The absolute path, or '' for a library or unknown unit.</returns>
    /// <remarks>Thread-safe (the lookup lock).</remarks>
    function UnitFilePath(const AUnit: string): string;
    /// <summary>1.52.3 INCRPP-LIMITS (IPPUnitDeps): AUnit's project file and those of the
    /// units its scan read constants of, transitively.</summary>
    /// <param name="AUnit">The unit name as the uses clause spells it.</param>
    /// <returns>Absolute paths, AUnit's own first; empty for a library or unknown unit.</returns>
    /// <remarks>Thread-safe (the lookup lock). Only units scanned this run carry deps.</remarks>
    function UnitFileClosure(const AUnit: string): TArray<string>;
    /// <summary>How many lookups answered pnkUnknown since the last AddUnitFiles
    /// -- zero means no IF needed a unit the source could not see, so a second
    /// closure pass would decide nothing differently.</summary>
    property UnknownAnswers: Integer read FUnknownAnswers;
  end;

/// <summary>Creates a TPPUnitSourceResolver and installs it as the
/// process-wide PPUnitSource (replacing any earlier one).</summary>
/// <param name="AProfile">See TPPUnitSourceResolver.Create.</param>
/// <param name="AProjectDbs">See TPPUnitSourceResolver.Create.</param>
/// <param name="ALibraryDbs">See TPPUnitSourceResolver.Create.</param>
/// <returns>The installed resolver; the installation owns it (do not free).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.ConfigureLspLint (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.Create, DRagLint.Preprocess.Decls.PPSetUnitSource</para>
/// <para>Returns: TPPUnitSourceResolver.Create(AProfile, nil, AProjectDbs, ALibraryDbs)</para>
/// <para>Owns returned: new (caller owns)</para>
/// <seealso cref="DRagLint.Index.PPUnitSource.TPPUnitSourceResolver.Create"/>
/// <seealso cref="DRagLint.Preprocess.Decls.PPSetUnitSource"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function InstallPPUnitSource(const AProfile: TDefineProfile; const AProjectDbs, ALibraryDbs: TArray<string>): TPPUnitSourceResolver;

implementation

uses
  System.IOUtils,
  DRagLint.Core.Model,
  DRagLint.Core.Encoding,
  DRagLint.Storage.SQLite,
  DRagLint.Preprocess;

const
  // A library constant built from other constants nests its evaluation; this
  // bounds a pathological (or cyclic) chain.
  MAX_EVAL_DEPTH = 16;
  SYSTEM_UNIT = 'System';

constructor TPPUnitSourceResolver.Create(const AProfile: TDefineProfile; const ASearchPaths, AProjectDbs, ALibraryDbs: TArray<string>);
begin
  inherited Create;
  FLock       := TCriticalSection.Create;
  FProfile    := AProfile;
  FSearchPaths:= ASearchPaths;
  FProjectDbs := AProjectDbs;
  FLibraryDbs := ALibraryDbs;
  FDefines    := TDictionary<string, Boolean>.Create;
  FNumeric    := TDictionary<string, Integer>.Create;
  FUnitFiles  := TDictionary<string, string>.Create;
  FScanned    := TObjectDictionary<string, TDictionary<string, TPPDecl>>.Create([doOwnsValues]);
  FInProgress := TDictionary<string, Boolean>.Create;
  FScanStack  := TList<string>.Create;
  FScanDeps   := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  FAnswers    := TDictionary<string, TAnswer>.Create;
  for var D: string in AProfile.Defines do
    if D <> '' then FDefines.AddOrSetValue(LowerCase(D), True);
  for var P: TPair<string, Integer> in AProfile.NumericDefines do
    FNumeric.AddOrSetValue(LowerCase(P.Key), P.Value);
end;

destructor TPPUnitSourceResolver.Destroy;
begin
  FProjStores:= nil;
  FLibStores := nil;
  FAnswers.Free;
  FScanDeps.Free;
  FScanStack.Free;
  FInProgress.Free;
  FScanned.Free;
  FUnitFiles.Free;
  FNumeric.Free;
  FDefines.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TPPUnitSourceResolver.AddUnitFiles(const APaths, ASearchPaths: TArray<string>);
begin
  FLock.Enter;
  try
    FSearchPaths:= ASearchPaths;
    for var P: string in APaths do
      if SameText(ExtractFileExt(P), '.pas') then
        FUnitFiles.AddOrSetValue(LowerCase(TPath.GetFileNameWithoutExtension(P)), P);
    FAnswers.Clear;
    FScanned.Clear;
    FUnknownAnswers:= 0;
  finally
    FLock.Leave;
  end;
end;

procedure TPPUnitSourceResolver.OpenStores;

  function OpenAll(const ADbs: TArray<string>): TArray<ISymbolStore>;
  begin
    Result:= nil;
    { 150 SC: the schema read gate. A DB below SCHEMA_READ_MIN (or unopenable) answers
      nothing -- the lookup falls through to pp-unresolved-if -- instead of handing out
      a store whose prepared queries are nil (the 149 INT access-violation trap). }
    for var Db: string in ADbs do
    begin
      var Why: string;
      var Store: ISymbolStore:= TSQLiteSymbolStore.OpenReadable(Db, Why);
      if Store <> nil then Result:= Result + [Store];
    end;
  end;

begin
  if FStoresOpen then Exit;
  FStoresOpen:= True;
  FProjStores:= OpenAll(FProjectDbs);
  FLibStores := OpenAll(FLibraryDbs);
end;

// The project source file of AUnit, or '' when it is not a project unit.
function TPPUnitSourceResolver.UnitFile(const AUnit: string): string;
var
  Key: string;
begin
  Key:= LowerCase(AUnit);
  if FUnitFiles.TryGetValue(Key, Result) then Exit;
  Result:= '';
  OpenStores;
  for var S: ISymbolStore in FProjStores do
  begin
    for var Sym: TSymbol in S.FindSymbolsByQualifiedName(AUnit) do
      if (Sym.Kind = skUnit) and SameText(Sym.QualifiedName, AUnit) then
      begin
        Result:= S.GetFilePath(Sym.FileId);
        if (Result <> '') and TFile.Exists(Result) then Break;
        Result:= '';
      end;
    if Result <> '' then Break;
  end;
  FUnitFiles.AddOrSetValue(Key, Result); // '' = negative cache
end;

function TPPUnitSourceResolver.Scan(const AKey, APath: string): TDictionary<string, TPPDecl>;
var
  Opts  : TPPOptions;
  Report: TPPReport;
begin
  if FScanned.TryGetValue(AKey, Result) then Exit;
  Result:= TDictionary<string, TPPDecl>.Create;
  FInProgress.AddOrSetValue(AKey, True);
  FScanStack.Add(AKey); { INCRPP-LIMITS: lookups from here on are AKey's deps }
  try
    try
      Opts:= TPPOptionsDefault;
      Opts.Profile    := FProfile;
      Opts.IncludeMode:= 'defines-only';
      Opts.BaseDir    := TPath.GetDirectoryName(APath);
      Opts.SearchPaths:= FSearchPaths;
      PreprocessReport(EnsureUtf8Bytes(TFile.ReadAllBytes(APath)), Opts, Report);
      for var D: TPPDecl in Report.Exported do
        Result.AddOrSetValue(LowerCase(D.Name), D);
    except // dl:ok try-except-swallowed@e22c -- REVIEWED 2026-10-27 an unreadable unit declares nothing we can see; its names surface as pp-unresolved-if
      on E: Exception do Result.Clear;
    end;
  finally
    FScanStack.Delete(FScanStack.Count - 1);
    FInProgress.Remove(AKey);
  end;
  FScanned.Add(AKey, Result);
end;

// Evaluates a library constant's expression in its own unit's scope: names
// resolve in AUnitQName, then System.
function TPPUnitSourceResolver.EvalInUnit(const AUnitQName, AExpr: string; out AValue: TPPValue): Boolean;
var
  Me: TPPUnitSourceResolver;
begin
  Me:= Self;
  Result:= TryEvalPPConst(AExpr, FDefines, FNumeric,
    function(const AName: string; out AV: TPPValue): TPPNameKind
    begin
      Result:= Me.LookupInUnit(AUnitQName, AName, AV);
      if (Result = pnkUnknown) and not SameText(AUnitQName, SYSTEM_UNIT) then
        Result:= Me.LookupInUnit(SYSTEM_UNIT, AName, AV);
    end, AValue);
end;

// FindSymbolsByExactName that answers nothing when the DB is busy or locked.
function SafeByName(const AStore: ISymbolStore; const AName: string): TArray<TSymbol>;
begin
  try
    Result:= AStore.FindSymbolsByExactName(AName);
  except
    on Exception do Result:= nil;
  end;
end;

function TPPUnitSourceResolver.AskLibrary(const AUnit, AName: string): TAnswer;
var
  Want, UnitQ, Sig: string;
  Hits            : TArray<TSymbol>;
  Hit             : TSymbol;
  Found           : Boolean;
begin
  Result:= Default(TAnswer);
  Hit:= Default(TSymbol);
  OpenStores;
  Want:= AUnit + '.' + AName;
  Found:= False;
  for var S: ISymbolStore in FLibStores do
  begin
    try
      Hits:= S.FindSymbolsByQualifiedName(Want);
    except
      on Exception do Hits:= nil;
    end;
    // An unqualified uses name (SysUtils) matches a namespaced unit.
    if (Length(Hits) = 0) and (not AUnit.Contains('.')) then
      for var X: TSymbol in SafeByName(S, AName) do
        if X.QualifiedName.ToLower.EndsWith('.' + Want.ToLower) then Hits:= Hits + [X];
    for var X: TSymbol in Hits do
      if (X.Section <> 'implementation') and X.QualifiedName.ToLower.EndsWith(Want.ToLower) then
      begin
        Hit:= X;
        Found:= True;
        Break;
      end;
    if Found then Break;
  end;
  if not Found then Exit;
  Result.Kind:= pnkDeclared;
  if Hit.Kind <> skConstDecl then Exit;
  { The stored signature is '= <expr>' or, for a literal value, '<inferred type> = <v>'
    -- and a TYPED constant is stored the same way ('Integer = 3'). Since EXT-E4
    (extractor 1.26.0-alpha) the parser marks a typed constant with the
    'typed' modifier, so it is refused here like dcc does (E2026). A DB indexed
    before that has no modifier and still yields the value. }
  if (' ' + LowerCase(Hit.Modifiers) + ' ').Contains(' typed ') then
  begin
    Result.Kind:= pnkTypedConst;
    Exit;
  end;
  Sig:= Trim(Hit.Signature);
  if not Sig.Contains('=') then Exit;
  Sig:= Copy(Sig, Pos('=', Sig), MaxInt);
  UnitQ:= Copy(Hit.QualifiedName, 1, Length(Hit.QualifiedName) - Length(AName) - 1);
  if FDepth >= MAX_EVAL_DEPTH then Exit;
  Inc(FDepth);
  try
    if EvalInUnit(UnitQ, Trim(Copy(Sig, 2, MaxInt)), Result.Value) then Result.Kind:= pnkConst;
  finally
    Dec(FDepth);
  end;
end;

function TPPUnitSourceResolver.LookupInUnit(const AUnit, AName: string; out AValue: TPPValue): TPPNameKind;
var
  Key, Path: string;
  Decls    : TDictionary<string, TPPDecl>;
  D        : TPPDecl;
  A        : TAnswer;
begin
  AValue:= Default(TPPValue);
  Result:= pnkUnknown;
  if (AUnit = '') or (AName = '') then Exit;
  FLock.Enter;
  try
    Key:= LowerCase(AUnit);
    { INCRPP-LIMITS: a lookup made while a unit is being scanned is that unit's dependency. }
    if FScanStack.Count > 0 then
    begin
      var Scanning: string:= FScanStack[FScanStack.Count - 1];
      var Deps: TList<string>;
      if not FScanDeps.TryGetValue(Scanning, Deps) then
      begin
        Deps:= TList<string>.Create;
        FScanDeps.Add(Scanning, Deps);
      end;
      if (Key <> Scanning) and not Deps.Contains(Key) then Deps.Add(Key);
    end;
    Path:= UnitFile(AUnit);
    if Path <> '' then
    begin
      if FInProgress.ContainsKey(Key) then Exit; // a uses cycle: the unit is mid-scan
      Decls:= Scan(Key, Path);
      if not Decls.TryGetValue(LowerCase(AName), D) then Exit;
      if D.IsTypedConst then Result:= pnkTypedConst
      else if not (D.IsTrueConst and D.HasValue) then Result:= pnkDeclared
      else
      begin
        AValue:= D.Value;
        Result:= pnkConst;
      end;
      Exit;
    end;
    if not FAnswers.TryGetValue(Key + '.' + LowerCase(AName), A) then
    begin
      A:= AskLibrary(AUnit, AName);
      FAnswers.AddOrSetValue(Key + '.' + LowerCase(AName), A);
    end;
    AValue:= A.Value;
    Result:= A.Kind;
  finally
    if Result = pnkUnknown then Inc(FUnknownAnswers);
    FLock.Leave;
  end;
end;

function TPPUnitSourceResolver.HasLibraryEvidence: Boolean;
begin
  FLock.Enter;
  try
    OpenStores;
    Result:= Length(FLibStores) > 0;
  finally
    FLock.Leave;
  end;
end;

function TPPUnitSourceResolver.UnitFileClosure(const AUnit: string): TArray<string>;
var
  Todo : TList<string>;
  Seen : TDictionary<string, Boolean>;
  Deps : TList<string>;
  I    : Integer;
begin
  Result:= nil;
  FLock.Enter;
  Todo:= TList<string>.Create;
  Seen:= TDictionary<string, Boolean>.Create;
  try
    Todo.Add(LowerCase(AUnit));
    Seen.Add(LowerCase(AUnit), True);
    I:= 0;
    while I < Todo.Count do
    begin
      var P: string:= UnitFile(Todo[I]);
      if P <> '' then Result:= Result + [P];
      if FScanDeps.TryGetValue(Todo[I], Deps) then
        for var D: string in Deps do
          if not Seen.ContainsKey(D) then
          begin
            Seen.Add(D, True);
            Todo.Add(D);
          end;
      Inc(I);
    end;
  finally
    Seen.Free;
    Todo.Free;
    FLock.Leave;
  end;
end;

function TPPUnitSourceResolver.UnitFilePath(const AUnit: string): string;
begin
  FLock.Enter;
  try
    Result:= UnitFile(AUnit);
  finally
    FLock.Leave;
  end;
end;

function InstallPPUnitSource(const AProfile: TDefineProfile; const AProjectDbs, ALibraryDbs: TArray<string>): TPPUnitSourceResolver;
begin
  Result:= TPPUnitSourceResolver.Create(AProfile, nil, AProjectDbs, ALibraryDbs);
  PPSetUnitSource(Result);
end;

end.
