unit DRagLint.Index.CallResolver;

// v14 (D5): the receiver-typing engine. Given one call-site reference (X.M),
// type the receiver X to a concrete class/interface/record symbol, look M up on
// that type's own methods + its type_ancestors chain, and return a TCallEdge
// carrying the resolved target + a confidence ('certain' | 'ambiguous'), or
// TargetSymbolId=0 when the receiver / method cannot be resolved (the '?' /
// no-edge bucket). FP policy: when unsure, return 0 -- a wrong 'certain' is
// worse than no edge.
//
// PREPARE-ONCE DESIGN: Task 6 runs ResolveOne over EVERY call ref in the DB, so
// the two name/scope maps that drive type-name resolution (mirroring the store's
// ResolveAncestry NameToCands + FileScope) are built ONCE in the constructor and
// reused. Create the resolver once, then call ResolveOne in a loop.

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Hash,      { THashSHA2 -- the staleness probe in LinesOf }
  System.DateUtils, { DateTimeToUnix -- same }
  System.Generics.Collections,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces;

type
  /// <summary>v14 (D5): a set of symbol kinds -- lets the resolver's child scans
  /// filter by "any method-shaped kind" / "any type-defining kind" in one test.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.PickAccessor (DRagLint.Index.CallResolver.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSymbolKindSet = set of TSymbolKind;

  /// <summary>2026-09-23 (parenless-call binding, resolver 1.7.0-alpha): per-run
  /// counters of the parenless-call pass, printed on the calls stage's
  /// `parenless:` ResolveLog line.</summary>
  /// <remarks>
  /// Every DECLINE is counted by reason. A declined ref writes nothing, so
  /// these counters are the only trace of what the pass refused, and the only
  /// way to tell an over-strict rule from a corpus that has nothing to bind.
  /// Bound + the seven declines = the refs the pass was asked about.
  /// </remarks>
  TParenlessResolveStats = record
    /// <summary>Refs that earned a call edge.</summary>
    Bound      : Int64;
    /// <summary>Declined: no routine of the name is visible from the ref.</summary>
    NotFound   : Int64;
    /// <summary>Declined: a nearer or same-scope VALUE of the name (local,
    /// parameter, field, property, const, var, type, enum value) wins.</summary>
    Shadowed   : Int64;
    /// <summary>Declined: the routine the name reaches is a procedure, needs an
    /// argument, or shares its name with an overload that does.</summary>
    NotCallable: Int64;
    /// <summary>Declined: the site takes the routine as a VALUE -- `@F`, or the
    /// whole right side of an assignment / a whole argument whose declared type
    /// is procedural.</summary>
    ProcValue  : Int64;
    /// <summary>Declined: the enclosing routine contains a `with`, whose
    /// subject may supply the name.</summary>
    WithScope  : Int64;
    /// <summary>Declined: a receiver other than Self qualifies the name.</summary>
    Qualified  : Int64;
    /// <summary>Declined: the ref's source line could not be read, or the file
    /// no longer matches the index.</summary>
    Unreadable : Int64;
  end;

  /// <summary>v14 (D5): receiver-typing + method-chain call resolver. Prepare
  /// once (Create builds the name-candidate + file-scope maps from the whole DB),
  /// then call ResolveOne per call-site ref.</summary>
  /// <remarks>
  /// Not thread-safe; single owning thread only. Holds the ISymbolStore
  /// for the resolver's lifetime -- the store must outlive the resolver.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Storage.SQLite.TSQLiteSymbolStore.ResolveCallTargets (DRagLint.Storage.SQLite.pas)</para>
  /// <para>Used in units: DRagLint.Storage.SQLite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCallResolver = class
  strict private
    FStore      : ISymbolStore;
    { v21: consulted ONLY on primary-store miss; see the constructor's param doc. }
    FExtraStores: TArray<ISymbolStore>;
    // Lowercased simple type name -> candidate class/interface/record symbols.
    FNameToCands: TObjectDictionary<string, TList<TSymbol>>;
    // Option 4: lowercased routine name -> candidate UNIT-LEVEL routines (free
    // procedures/functions). Deliberately separate from FNameToCands: that map
    // holds TYPES for receiver typing, and a bare call resolves against
    // routines, so merging them would make every lookup filter by kind.
    FNameToRoutines: TObjectDictionary<string, TList<TSymbol>>;
    // 2026-09-23 (enum-value-ref-binding): lowercased enum-value name -> every
    // enum_value declaration of that name in the index. The CANDIDATE set of the
    // enum-value pass; R1/R2/R3 narrow it per ref. A third map rather than a
    // wider FNameToCands for the reason that map's own comment gives: this one
    // holds VALUES, FNameToCands holds TYPES for receiver typing, and merging
    // them would make every receiver lookup filter by kind.
    FNameToEnumValues: TObjectDictionary<string, TList<TEnumValueDecl>>;
    // 2026-09-23: lowercased name -> unit-level const/var declarations. The
    // SHADOW set of rule R3(c), never a candidate set -- a hit here makes the
    // pass DECLINE.
    FNameToUnitValues: TObjectDictionary<string, TList<TSymbol>>;
    // 2026-09-23: per-run counters of the enum-value pass. Every decline is
    // counted by reason, because a pass that answers `certain` or nothing leaves
    // no other trace of what it refused.
    FEnumStats       : TEnumResolveStats;
    // 2026-09-23: per-run counters of the parenless-call pass, same reason.
    FParenlessStats  : TParenlessResolveStats;
    // Declaring file id -> the resolved target file ids it can see (uses graph).
    FFileScope  : TObjectDictionary<Int64, TList<Int64>>;
    // Cache of a routine/type symbol's direct children, keyed by symbol id, so a
    // per-ref field/method scan does not re-hit the DB for the same enclosing
    // symbol repeatedly across a whole-DB pass.
    FChildCache : TObjectDictionary<Int64, TList<TSymbol>>;
    // Cache: source file id -> its lines (0-based array). A single whole-DB pass
    // touches many refs in the same file; read each file at most once.
    FLineCache  : TObjectDictionary<Int64, TStringList>;
    // File ids whose ON-DISK content no longer matches what the index recorded
    // (or which could not be read at all). Populated by LinesOf, one probe per
    // file per run. See LinesOf for why this exists.
    FStaleFiles : TDictionary<Int64, Boolean>;

    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.Create (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetTypeCandidates, DRagLint.Core.Interfaces.ISymbolStore.GetUnitLevelRoutines, DRagLint.Core.Interfaces.ISymbolStore.GetUnitScopeEdges, LowerCase</para>
    /// <para>Reads: FStore, FNameToCands, FNameToRoutines, FFileScope</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetTypeCandidates"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetUnitLevelRoutines"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetUnitScopeEdges"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure BuildMaps;
    /// <summary>True when a candidate declared in ACandFile is visible from
    /// ADeclFile (same file, or in ADeclFile's resolved uses scope).</summary>
    /// <param name="ADeclFile"><!-- drag-lint:auto type -->Int64</param>
    /// <param name="ACandFile"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: (ADeclFile = ACandFile);
    /// L.IndexOf(ACandFile) &gt;= 0.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.LookupUnitLevelRoutine (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveTypeNameToSymbol (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Reads: FFileScope</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Create"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Destroy"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.FileIsStale"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function CandInScope(ADeclFile, ACandFile: Int64): Boolean;
    /// <summary>Resolve a raw type text (a param/field/local Signature) to a
    /// defining class/interface/record symbol id, in scope of ADeclFileId. 0 when
    /// unresolvable OR ambiguous (FP-conservative, mirrors ResolveAncestry).</summary>
    /// <param name="ATypeText"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ADeclFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto -->Int64 -- Observed: 0; Cands[InScopeIdx].Id;
    /// Cands[0].Id.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.TypeReceiver (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: Copy, DRagLint.Index.CallResolver.TCallResolver.CandInScope, LowerCase, Pos, Trim</para>
    /// <para>Complexity: 11 (cyclomatic, outer body), 35 lines (full implementation)</para>
    /// <para>Reads: FNameToCands</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Create"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ResolveTypeNameToSymbol(const ATypeText: string; ADeclFileId: Int64): Int64;
    /// <summary>v21: resolves a call the primary index could not, against the
    /// extra (library) stores, answering with a QUALIFIED NAME. '' when it
    /// cannot answer unambiguously. See the implementation for why it is
    /// deliberately narrow.</summary>
    /// <param name="AReceiver"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ACallName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: ''.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.Core.Model.CanBeCallTarget, Pos, SameText, Trim</para>
    /// <para>Complexity: 14 (cyclomatic, outer body), 53 lines (full implementation)</para>
    /// <para>Reads: FExtraStores</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
    /// <seealso cref="DRagLint.Core.Model.CanBeCallTarget"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ResolveExternally(const AReceiver, ACallName: string): string;
    /// <summary>Direct children of AParentId (cached). Empty when none / 0.</summary>
    /// <param name="AParentId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto -->TList&lt;TSymbol&gt; -- Observed:
    /// TList&lt;TSymbol&gt;.Create.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LookupInLexicalScopes (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LookupMethodOnType (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LookupMethodOnType.AddHelperMethods (DRagLint.Index.CallResolver.pas) ?, DRagLint.Index.CallResolver.TCallResolver.PickAccessor (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols</para>
    /// <para>Reads: FChildCache, FStore</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Create"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ChildrenOf(AParentId: Int64): TList<TSymbol>;
    /// <summary>The source lines of the file AFileId (cached, ANSI). Nil-safe.</summary>
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto -->TStringList -- Observed: TStringList.Create.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.FileIsStaleProbe (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.MemberAccessMode (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveAccessor (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: DateTimeToUnix, DRagLint.Core.Interfaces.ISymbolStore.FileIsUpToDate, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath</para>
    /// <para>Reads: FLineCache, FStore, FStaleFiles</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <para>Touches: file system</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FileIsUpToDate"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function LinesOf(AFileId: Int64): TStringList;
    { True when AFileId's on-disk content no longer matches what the index
      recorded, or it could not be read. Only meaningful AFTER LinesOf has been
      called for that file -- the probe happens there, once per file per run. }
    /// <summary><!-- drag-lint:auto sum -->True when AFileId's on-disk content no longer
    /// matches what the index recorded, or it could not be read. Only meaningful AFTER
    /// LinesOf has been called for that file -- the probe happens there, once per file
    /// per run.</summary>
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed:
    /// FStaleFiles.ContainsKey(AFileId).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.FileIsStaleProbe (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveAccessor (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Reads: FStaleFiles</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Create"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FileIsStale(AFileId: Int64): Boolean;
    /// <summary>Find a direct child of AParentId whose Name matches AName (case-
    /// insensitively) and whose Kind is in AKinds. Default(TSymbol) (Id=0) when
    /// none. With ADeclineOnConflict, two or more matching children whose
    /// Signatures DIFFER also yield Default(TSymbol): two sibling
    /// 'for var Item in A' / 'for var Item in B' loops share one qualified
    /// name, and typing the receiver from whichever row came first would be a
    /// guess. Same-signature duplicates still match (they type the same).</summary>
    /// <param name="AParentId"><!-- drag-lint:auto type -->Int64</param>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AKinds"><!-- drag-lint:auto type -->const TSymbolKindSet</param>
    /// <param name="ADeclineOnConflict">True: decline on same-named children
    /// of differing Signature instead of returning the first (v23 local/param
    /// receiver typing). False (default): first match, the pre-v23 contract.</param>
    /// <returns><!-- drag-lint:auto -->TSymbol -- Observed: Default(TSymbol); S.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.LookupMemberOnType (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.TypeReceiver (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: Default, DRagLint.Index.CallResolver.TCallResolver.ChildrenOf, SameText</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Create"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindChildOfKind(AParentId: Int64; const AName: string; const AKinds: TSymbolKindSet;
      ADeclineOnConflict: Boolean = False): TSymbol;
    /// <summary>Choose one target from a set of same-named candidates, narrowing
    /// by argument count when the set is an overload set. Sets AConfidence
    /// ('certain' | 'ambiguous') and returns the chosen symbol id, or 0 when
    /// AMatches is empty.</summary>
    /// <param name="AMatches">Candidates already filtered by name and scope.
    /// Not modified. Nil is treated as empty.</param>
    /// <param name="AArgCount"><!-- drag-lint:auto type -->Integer</param>
    /// <param name="AArgsKnown">False when the call site could not be read, in
    /// which case arity is not consulted and the first candidate answers.</param>
    /// <param name="AConfidence"><!-- drag-lint:auto type -->out string</param>
    /// <returns><!-- drag-lint:auto -->Int64 -- Observed: 0; AMatches[0].Id; Fit[0].Id.</returns>
    /// <remarks>
    /// Arity NARROWS an existing name match and never widens one: when
    /// it cannot decide -- several candidates of one arity, or none that fits --
    /// the answer is the pre-arity one, still marked uncertain. Shared by the
    /// method-chain and unit-level rungs so the two cannot drift apart on how a
    /// tie is broken.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.LookupMethodOnType (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LookupUnitLevelRoutine (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: DRagLint.Index.CallResolver.SignatureArityRange</para>
    /// <para>Complexity: 10 (cyclomatic, outer body), 52 lines (full implementation)</para>
    /// <para>Mutates: AConfidence (out)</para>
    /// <seealso cref="DRagLint.Index.CallResolver.SignatureArityRange"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function PickFromMatches(AMatches: TList<TSymbol>; AArgCount: Integer;
      AArgsKnown: Boolean; out AConfidence: string): Int64;
    /// <summary>Given a resolved receiver TYPE symbol id, look up a method named
    /// AMethodName on the type's own children + its transitive ancestors. Sets
    /// AConfidence ('certain' one surviving candidate | 'ambiguous' >1) and
    /// returns the target method id, or 0 (method not found on the chain).</summary>
    /// <param name="ATypeSymbolId"><!-- drag-lint:auto type -->Int64</param>
    /// <param name="AMethodName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AArgCount">Number of arguments at the call site, used to
    /// separate OVERLOADS when the name alone matches several (B1). Ignored
    /// unless AArgsKnown.</param>
    /// <param name="AArgsKnown">False when the call site could not be read (an
    /// unreadable source file), in which case arity is not consulted at all and
    /// the pre-B1 name-only behaviour stands.</param>
    /// <param name="AConfidence"><!-- drag-lint:auto type -->out string</param>
    /// <returns><!-- drag-lint:auto -->Int64 -- Observed: 0; PickFromMatches(Matches,
    /// AArgCount, AArgsKnown, AConfidence).</returns>
    /// <remarks>
    /// Arity NARROWS an existing name match; it never widens one. When
    /// it cannot decide -- several candidates of the same arity, or none that
    /// fits -- the result is exactly what it was before B1, so a call that used
    /// to resolve still resolves.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetTransitiveAncestors, DRagLint.Index.CallResolver.TCallResolver.ChildrenOf, DRagLint.Index.CallResolver.TCallResolver.LookupMethodOnType.AddHelperMethods, DRagLint.Index.CallResolver.TCallResolver.PickFromMatches, SameText</para>
    /// <para>Complexity: 14 (cyclomatic, outer body), 100 lines (full implementation)</para>
    /// <para>Reads: FStore</para>
    /// <para>Mutates: AConfidence (out)</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetTransitiveAncestors"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.LookupMethodOnType.AddHelperMethods"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.PickFromMatches"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function LookupMethodOnType(ATypeSymbolId: Int64; const AMethodName: string;
      AArgCount: Integer; AArgsKnown: Boolean; out AConfidence: string): Int64;
    /// <summary>2026-09-16 (property-refs-resolve): the PROPERTY or FIELD named
    /// AMemberName on ATypeSymbolId or the nearest ancestor declaring it.
    /// Default(TSymbol) (Id = 0) when none.</summary>
    /// <param name="ATypeSymbolId"><!-- drag-lint:auto type -->Int64</param>
    /// <param name="AMemberName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->TSymbol -- Observed: Default(TSymbol);
    /// FindChildOfKind(ATypeSymbolId, AMemberName, MEMBER_KINDS);
    /// FindChildOfKind(A.SymbolId, AMemberName, MEMBER_KINDS).</returns>
    /// <remarks>
    /// Own members first, then the transitive ancestor chain in order,
    /// so a re-published `property X;` on a descendant wins over the ancestor's
    /// declaration -- the nearest declaration is the one the source names. No
    /// arity to pick by, so no ambiguity: the first hit is the answer.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.GetTransitiveAncestors, DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind</para>
    /// <para>Reads: FStore</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetTransitiveAncestors"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function LookupMemberOnType(ATypeSymbolId: Int64; const AMemberName: string): TSymbol;
    /// <summary>E3: 'write' when the source after the member name (past any
    /// `[...]` indexer) is `:=`, else 'read'. '' when the line is unavailable.</summary>
    /// <param name="ARef"><!-- drag-lint:auto type -->const TReference</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: ''; 'read'; 'write'.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: DRagLint.Index.CallResolver.IsIdentPart, DRagLint.Index.CallResolver.TCallResolver.LinesOf, Max</para>
    /// <para>Complexity: 18 (cyclomatic, outer body), 41 lines (full implementation)</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Index.CallResolver.IsIdentPart"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.LinesOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function MemberAccessMode(const ARef: TReference): string;
    /// <summary>The one child of AParentId named AName (of a kind in AKinds)
    /// that a property accessor clause can mean. One candidate, or several
    /// with one signature, is that candidate (first-match, as before). An
    /// OVERLOAD SET -- several with different signatures -- is narrowed to
    /// the candidates whose arity range contains AArity; a unique survivor is
    /// the answer, anything else DECLINES (Id = 0) rather than guess.</summary>
    /// <param name="AParentId">The class whose direct children are searched.</param>
    /// <param name="AName">The accessor identifier after `read` / `write`.</param>
    /// <param name="AArity">The argument count the accessor must accept: the
    /// property's index-parameter count, plus one for a setter. Negative when
    /// the property's declaration could not be read, in which case an overload
    /// set always declines.</param>
    /// <param name="AKinds">Kinds admitted as an accessor (methods, fields).</param>
    /// <param name="AFound">True when at least one child carried the name --
    /// even if the answer declined -- so a caller stops at this class instead
    /// of walking to an ancestor that the same-named members shadow.</param>
    /// <returns>The chosen accessor, or Default(TSymbol) when none or declined.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveAccessor (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: Default, DRagLint.Index.CallResolver.SignatureArityRange, DRagLint.Index.CallResolver.TCallResolver.ChildrenOf, SameText</para>
    /// <para>Returns: Default(TSymbol); S</para>
    /// <para>Complexity: 14 (cyclomatic, outer body), 46 lines (full implementation)</para>
    /// <para>Mutates: AFound (out)</para>
    /// <seealso cref="DRagLint.Index.CallResolver.SignatureArityRange"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function PickAccessor(AParentId: Int64; const AName: string; AArity: Integer;
      const AKinds: TSymbolKindSet; out AFound: Boolean): TSymbol;
    /// <summary>The accessor a property's AMode resolves to: the identifier
    /// after `read` / `write` on the declaring lines, looked up as a METHOD or
    /// FIELD on the declaring class or its ancestors. Id = 0 when the clause is
    /// absent, names a path (`FRec.X`), resolves to nothing, or names an
    /// OVERLOAD SET that the property's own arity cannot narrow to one
    /// (see PickAccessor) -- no edge over a wrong one.</summary>
    /// <param name="AProp"><!-- drag-lint:auto type -->const TSymbol</param>
    /// <param name="AMode"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->TSymbol -- Observed: Default(TSymbol);
    /// PickAccessor(AProp.ParentId, Ident, WantArity, ACCESSOR_KINDS, Found);
    /// PickAccessor(A.SymbolId, Ident, WantArity, ACCESSOR_KINDS, Found).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.GetTransitiveAncestors, DRagLint.Index.CallResolver.AccessorIdentAfter, DRagLint.Index.CallResolver.PropertyIndexArity, DRagLint.Index.CallResolver.TCallResolver.FileIsStale, DRagLint.Index.CallResolver.TCallResolver.LinesOf, DRagLint.Index.CallResolver.TCallResolver.PickAccessor, Min</para>
    /// <para>Complexity: 17 (cyclomatic, outer body), 42 lines (full implementation)</para>
    /// <para>Reads: FStore</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetTransitiveAncestors"/>
    /// <seealso cref="DRagLint.Index.CallResolver.AccessorIdentAfter"/>
    /// <seealso cref="DRagLint.Index.CallResolver.PropertyIndexArity"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.FileIsStale"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.LinesOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ResolveAccessor(const AProp: TSymbol; const AMode: string): TSymbol;
    /// <summary>Delphi's INNERMOST-FIRST lexical scope walk for a BARE call.
    /// Starts at the call site's own enclosing routine, looks for a nested
    /// routine named AName among its direct children, and climbs one lexical
    /// level at a time while the enclosing scope is itself a routine. Returns
    /// the target symbol id, or 0 when no scope on the chain declares the
    /// name.</summary>
    /// <param name="AEnclosingSymbolId">refs.enclosing_symbol_id of the call
    /// site. Since nested routines became symbols this is the NESTED routine
    /// for a call written inside one, which is what makes the walk possible.</param>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AConfidence"><!-- drag-lint:auto type -->out string</param>
    /// <returns>0 when the name is not declared anywhere on the lexical chain --
    /// the caller then falls through to receiver typing exactly as before.</returns>
    /// <remarks>
    /// The walk STOPS at the first level that declares the name, which
    /// is the whole semantics: a nested routine SHADOWS a same-named method of
    /// the enclosing class, and two routines each nesting their own `Twin` are
    /// two distinct targets that only the call site's position can separate.
    /// It also stops climbing at a class / record / unit parent -- those scopes
    /// belong to the receiver-typed and unit-level lookups, which this must
    /// neither duplicate nor pre-empt.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, DRagLint.Index.CallResolver.TCallResolver.ChildrenOf, SameText</para>
    /// <para>Returns: 0; Matches[0].Id</para>
    /// <para>Complexity: 14 (cyclomatic, outer body), 55 lines (full implementation)</para>
    /// <para>Reads: FStore</para>
    /// <para>Mutates: AConfidence (out)</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function LookupInLexicalScopes(AEnclosingSymbolId: Int64; const AName: string;
      out AConfidence: string): Int64;
    /// <summary>Option 4: the UNIT-LEVEL rung of Delphi's bare-call chain. Looks
    /// for a free routine named AName, first in the call site's OWN unit (either
    /// section), then in the units it USES (interface section only). Returns the
    /// target symbol id, or 0 when no unit in scope declares the name.</summary>
    /// <param name="ACallFileId">refs.file_id of the call site -- the file whose
    /// uses clause defines what is visible.</param>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AArgCount">Argument count at the call site, used only to
    /// narrow an overload set, exactly as LookupMethodOnType does.</param>
    /// <param name="AArgsKnown">False when the call site could not be read; arity
    /// is then not consulted at all.</param>
    /// <param name="AConfidence"><!-- drag-lint:auto type -->out string</param>
    /// <returns>0 when the name is declared by no unit in scope -- the caller
    /// leaves the ref unresolved, which is the right answer for an intrinsic or
    /// an RTL routine living in the separate library index.</returns>
    /// <remarks>
    /// Runs AFTER the lexical walk and after the enclosing class's own
    /// methods, because that is the order the compiler binds in: a nested
    /// routine shadows a method, and a method shadows a free routine of the same
    /// name. Running it earlier would silently retarget correct edges.
    /// OWN UNIT WINS OUTRIGHT over any used unit, and the search stops at the
    /// first rung that matches -- a used unit is never consulted for a name the
    /// call's own unit declares. The implementation-section filter on the second
    /// rung is the visibility check that keeps this honest: without it a bare
    /// call binds to routines it could not actually see, which measured as 41
    /// WRONG edges when the yield was first estimated without one.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: DRagLint.Index.CallResolver.TCallResolver.CandInScope, DRagLint.Index.CallResolver.TCallResolver.PickFromMatches, LowerCase, SameText</para>
    /// <para>Returns: 0; PickFromMatches(Matches, AArgCount, AArgsKnown, AConfidence)</para>
    /// <para>Reads: FNameToRoutines</para>
    /// <para>Mutates: AConfidence (out)</para>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.PickFromMatches"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function LookupUnitLevelRoutine(ACallFileId: Int64; const AName: string;
      AArgCount: Integer; AArgsKnown: Boolean; out AConfidence: string): Int64;
    /// <summary>Type the receiver expression left of the call. Returns the
    /// receiver TYPE symbol id (0 when the receiver kind is unhandled or its type
    /// is unresolvable). AReceiverExpr is '' for a bare / Self call, in which case
    /// the enclosing routine's owning class is used.</summary>
    /// <param name="ACallRef"><!-- drag-lint:auto type -->const TReference</param>
    /// <param name="AReceiverExpr"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Int64 -- Observed: 0; Encl.ParentId;
    /// ResolveTypeNameToSymbol(CastType, ACallRef.FileId);
    /// ResolveTypeNameToSymbol(Segs[High(Segs)], ACallRef.FileId);
    /// ResolveTypeNameToSymbol(Member.Signature, ACallRef.FileId);
    /// ResolveTypeNameToSymbol(AReceiverExpr, ACallRef.FileId).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, DRagLint.Index.CallResolver.IsIdentPart, DRagLint.Index.CallResolver.IsIdentStart, DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind, DRagLint.Index.CallResolver.TCallResolver.ResolveTypeNameToSymbol, DRagLint.Index.CallResolver.TryParseCastTarget, Pos, SameText</para>
    /// <para>Complexity: 20 (cyclomatic, outer body), 117 lines (full implementation)</para>
    /// <para>Reads: FStore</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById"/>
    /// <seealso cref="DRagLint.Index.CallResolver.IsIdentPart"/>
    /// <seealso cref="DRagLint.Index.CallResolver.IsIdentStart"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ResolveTypeNameToSymbol"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function TypeReceiver(const ACallRef: TReference; const AReceiverExpr: string): Int64;
    /// <summary>R3(a): True when the enclosing routine, or any routine on its
    /// lexical chain, declares a local, parameter, const, var or nested routine
    /// spelled AName -- i.e. something NEARER than the enum's unit scope.</summary>
    /// <param name="AEnclosingSymbolId">The ref's enclosing routine; 0 makes the
    /// rule vacuous (R4) and answers False.</param>
    /// <param name="AName">The bare identifier, matched case-insensitively.</param>
    /// <returns>True on the first hit; the climb stops at the first non-routine
    /// parent, exactly as LookupInLexicalScopes does.</returns>
    /// <remarks>Unlike LookupInLexicalScopes this does not care WHICH symbol won
    /// or whether the scope is unambiguous: any same-named declaration on the
    /// chain is a reason to decline, so the first hit ends the walk.</remarks>
    function LexicalScopeDeclaresValue(AEnclosingSymbolId: Int64; const AName: string): Boolean;
    /// <summary>R3(b): True when the enclosing routine's owning class/record/
    /// interface -- or any resolved transitive ancestor of it -- declares a
    /// member spelled AName.</summary>
    /// <param name="AEnclosingSymbolId">The ref's enclosing routine; 0 makes the
    /// rule vacuous (R4).</param>
    /// <param name="AName">The bare identifier, matched case-insensitively.</param>
    /// <param name="AClassId">OUT: the OUTERMOST enclosing routine's owning type,
    /// or 0 when the ref is not inside a method. Set whatever the result, because
    /// the nested-enum visibility test needs it even when nothing is shadowed.</param>
    /// <returns>True on the first hit; False when AClassId is 0.</returns>
    function EnclosingClassChainDeclares(AEnclosingSymbolId: Int64; const AName: string;
      out AClassId: Int64): Boolean;
    /// <summary>Shape B: the files.id of the unit AReceiver names, or 0.</summary>
    /// <param name="AReceiver">The receiver text verbatim, dotted unit names
    /// included ('DRagLint.Doc.Document').</param>
    /// <returns>The file id when EXACTLY ONE unit symbol carries that name; 0
    /// otherwise. Two units of one name is a decline, not a pick.</returns>
    function UnitNameToFileId(const AReceiver: string): Int64;
    /// <summary>Rule 0 (owner ruling 4, 2026-09-23): fold groups of
    /// content-identical duplicate declarations down to one representative, so
    /// one declaration the index holds twice does not read as an R2 ambiguity.</summary>
    /// <param name="AVisible">The R1-visible candidates, in reader order.</param>
    /// <param name="ARefFileId">The referencing file, for the representative
    /// choice.</param>
    /// <returns>AVisible with each collapsible group reduced to one member, in
    /// the input's original order. A group whose members genuinely DIFFER is
    /// returned intact, so a real ambiguity still declines.</returns>
    /// <remarks>The representative is chosen SCOPE-AWARE -- own-file copy, then a
    /// copy this file can see, then the lowest id -- and that ordering differs
    /// deliberately from CollapseIdenticalCopies' own-file-then-lowest-id.
    /// This rule feeds a visibility test built on FILE-ID uses edges rather than
    /// textual uses names, so a lowest-id twin that is not the uses target would
    /// be carried forward and then wrongly declined.
    /// Increments FEnumStats.DupGroupsCollapsed once per collapsed group, and
    /// FEnumStats.CollapseDecisive once per CALL in which the fold turned more
    /// than one candidate into exactly one. Decisive is counted here rather than
    /// at a call site so that every caller -- the bare-read path and rung 3c's
    /// `Unit.value` path alike -- contributes to it; see the body.</remarks>
    function CollapseIdenticalEnumCopies(const AVisible: TArray<TEnumValueDecl>;
      ARefFileId: Int64): TArray<TEnumValueDecl>;

    { ---- 2026-09-23: the parenless-call pass (resolver 1.7.0-alpha). ---- }

    /// <summary>Walks the lexical scopes of AEnclosingSymbolId outward and stops
    /// at the FIRST level that declares AName: its routines go into AMatches;
    /// a local, parameter, const or var of the name answers True instead.</summary>
    /// <param name="AEnclosingSymbolId">The ref's enclosing routine; 0 is vacuous.</param>
    /// <param name="AName">The identifier as written.</param>
    /// <param name="AMatches">Receives the routines of the nearest declaring
    /// level; left untouched when the walk finds a value or nothing.</param>
    /// <param name="AValue">Out: the shadowing value symbol, Default when none.</param>
    /// <returns>True when a VALUE of the name is the nearest declaration.</returns>
    function LexicalParenlessLookup(AEnclosingSymbolId: Int64; const AName: string;
      AMatches: TList<TSymbol>; out AValue: TSymbol): Boolean;
    /// <summary>Adds every routine named AName that ATypeId or one of its resolved
    /// ancestors declares to AMatches. No-op for ATypeId &lt;= 0.</summary>
    /// <param name="ATypeId">A class/record/interface symbol id.</param>
    /// <param name="AName">The member name.</param>
    /// <param name="AMatches">Appended to; never cleared.</param>
    procedure AddMethodsOnTypeChain(ATypeId: Int64; const AName: string; AMatches: TList<TSymbol>);
    /// <summary>The class-scope rung: True when AClassId or an ancestor declares
    /// a property, field, const or var named AName (a shadow); otherwise its
    /// methods of that name are added to AMatches.</summary>
    /// <param name="AClassId">The ref's enclosing class.</param>
    /// <param name="AName">The identifier as written.</param>
    /// <param name="AMatches">Appended to when nothing shadows.</param>
    /// <returns>True when a value member shadows the name.</returns>
    function ClassChainParenlessLookup(AClassId: Int64; const AName: string;
      AMatches: TList<TSymbol>): Boolean;
    /// <summary>True when a unit-level const/var, a type, or an enum value named
    /// ALc is visible from ARefFileId (own unit, or the interface of a used unit).</summary>
    /// <param name="ARefFileId">The referencing file.</param>
    /// <param name="ALc">The lowercased identifier.</param>
    /// <returns>True when such a declaration is visible.</returns>
    function UnitScopeDeclaresValue(ARefFileId: Int64; const ALc: string): Boolean;
    /// <summary>The unit rung of a bare name: the routines named ALc declared in
    /// ARefFileId itself or, when it has none, in the interface of a unit it
    /// uses. Same two rungs as LookupUnitLevelRoutine.</summary>
    /// <param name="ARefFileId">The referencing file.</param>
    /// <param name="ALc">The lowercased identifier.</param>
    /// <param name="AMatches">Appended to; never cleared.</param>
    procedure AddVisibleUnitRoutines(ARefFileId: Int64; const ALc: string; AMatches: TList<TSymbol>);
    /// <summary>Collects the routines a parenless `read` of ARef.NameText can
    /// reach, nearest scope first: lexical, then the enclosing class chain, then
    /// the unit and the units it uses.</summary>
    /// <param name="ARef">The candidate read ref.</param>
    /// <param name="AReceiver">'' for a bare name, 'Self' for `Self.Name`.</param>
    /// <param name="AMatches">Receives the routines of the answering scope.</param>
    /// <returns>'' when AMatches holds the answer; otherwise the decline reason,
    /// 'shadowed' or 'not-found'.</returns>
    function FindParenlessCandidates(const ARef: TReference; const AReceiver: string;
      AMatches: TList<TSymbol>): string;
    /// <summary>True when the enclosing routine's text, from its first line up
    /// to the ref, contains the keyword `with` outside comments and strings.</summary>
    /// <param name="ARef">The candidate read ref.</param>
    /// <param name="ALines">The ref's source file.</param>
    /// <returns>True when a `with` may supply the name.</returns>
    /// <remarks>Deliberately coarse: any `with` earlier in the routine declines,
    /// whether or not its statement encloses the ref. A false decline loses an
    /// edge; a missed `with` would write a wrong one.</remarks>
    function EnclosingBodyUsesWith(const ARef: TReference; ALines: TStringList): Boolean;
    /// <summary>True when ATypeText names a PROCEDURAL type: written inline
    /// (`function: Integer`, `reference to ...`, `TFunc&lt;...&gt;`), or a type
    /// alias in this index whose declaration is one.</summary>
    /// <param name="ATypeText">A stored declaration's type text.</param>
    /// <param name="AFileId">The file whose scope the type name is resolved in.</param>
    /// <returns>True for a procedural type; False for any other or unknown type.</returns>
    function IsProceduralTypeText(const ATypeText: string; AFileId: Int64): Boolean;
    /// <summary>The declared type text of the target of `ALhs :=` on ALine: a
    /// local, parameter, `Result`, class member, unit-level var, or a member of a
    /// typed receiver. '' when it cannot be typed.</summary>
    /// <param name="ARef">The read ref on the assignment's right side.</param>
    /// <param name="ALine">The ref's source line.</param>
    /// <param name="ALhs">ALine up to (not including) the `:=`.</param>
    /// <returns>The type text, or ''.</returns>
    function AssignedTypeText(const ARef: TReference; const ALine, ALhs: string): string;
    /// <summary>True when the routine called at AOpenCol's `(` declares a
    /// procedural parameter at AArgIndex, in ANY of its visible candidates.</summary>
    /// <param name="ARef">The read ref standing as that whole argument.</param>
    /// <param name="ALine">The ref's source line.</param>
    /// <param name="AOpenCol">1-based column of the argument list's `(`.</param>
    /// <param name="AArgIndex">0-based argument position of the ref.</param>
    /// <param name="AResultType">The parenless target's return type; a
    /// parameter of exactly that type takes the CALL's result.</param>
    /// <returns>True when the argument may be a procedure value.</returns>
    function CalleeTakesProcedural(const ARef: TReference; const ALine: string;
      AOpenCol, AArgIndex: Integer; const AResultType: string): Boolean;
    /// <summary>True when the site hands the routine over as a VALUE rather than
    /// calling it: `@Name`, or Name as the whole right side of an assignment /
    /// a whole argument whose declared type is procedural.</summary>
    /// <param name="ARef">The candidate read ref.</param>
    /// <param name="ALine">Its source line.</param>
    /// <param name="AReceiver">'' or 'Self'.</param>
    /// <param name="AResultType">The target's return type text.</param>
    /// <returns>True when the read is (or may be) a procedure value.</returns>
    function ParenlessIsProcValue(const ARef: TReference; const ALine, AReceiver,
      AResultType: string): Boolean;
    /// <summary>Counts one outcome of ResolveParenlessRead into FParenlessStats.</summary>
    /// <param name="AReason">'' for a binding, else the decline reason.</param>
    procedure TallyParenless(const AReason: string);
  public
    { Probes AFileId (reading + caching it if not already read) and reports
      whether its on-disk content still matches what the index recorded. Called
      by ResolveCallTargets BEFORE it deletes anything, so a stale file's
      existing call edges and receivers can be excluded from both the delete and
      the resolve stream rather than rebuilt from source that no longer lines up.
      See LinesOf and INBOX-whole-db-resolve-degrades-a-stale-index. }
    /// <summary><!-- drag-lint:auto sum -->Probes AFileId (reading + caching it if not
    /// already read) and reports whether its on-disk content still matches what the index
    /// recorded. Called by ResolveCallTargets BEFORE it deletes anything, so a stale
    /// file's existing call edges and receivers can be excluded from both the delete and
    /// the resolve stream rather than rebuilt from source that no longer lines up. See
    /// LinesOf and INBOX-whole-db-resolve-degrades-a-stale-index.</summary>
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: FileIsStale(AFileId).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Storage.SQLite.TSQLiteSymbolStore.ResolveCallTargets (DRagLint.Storage.SQLite.pas)</para>
    /// <para>Calls: DRagLint.Index.CallResolver.TCallResolver.FileIsStale, DRagLint.Index.CallResolver.TCallResolver.LinesOf</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.FileIsStale"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.LinesOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FileIsStaleProbe(AFileId: Int64): Boolean;

    /// <summary>Builds the whole-DB name/scope maps from AStore. Call once.</summary>
    /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
    /// <param name="AExtraStores">v21: other open indexes -- in practice the
    /// platform LIBRARY db -- consulted ONLY when the primary store cannot
    /// resolve a type. Their symbol ids are meaningless here (ids are per-DB),
    /// so a hit is recorded as a qualified NAME on the ref
    /// (refs.external_target), never as a call_edges row.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Storage.SQLite.TSQLiteSymbolStore.ResolveCallTargets (DRagLint.Storage.SQLite.pas)</para>
    /// <para>Calls: DRagLint.Index.CallResolver.TCallResolver.BuildMaps</para>
    /// <para>constructor</para>
    /// <para>Writes: FStore, FExtraStores, FNameToCands, FNameToRoutines, FFileScope, FChildCache, FLineCache, FStaleFiles</para>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Destroy"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.FileIsStale"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(const AStore: ISymbolStore;
      const AExtraStores: TArray<ISymbolStore> = nil);
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FLineCache, FStaleFiles, FChildCache, FFileScope, FNameToRoutines, FNameToCands   Writes: FStore</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Create"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.FileIsStale"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;

    /// <summary>Resolve one call-site ref to a call edge. RefId is copied from
    /// ACallRef; TargetSymbolId=0 means NO edge (unresolved / unhandled shape).
    /// ReceiverTypeSymbolId is set whenever the receiver type resolved (even if
    /// the method was not found on it); Confidence is 'certain' | 'ambiguous'
    /// (only meaningful when TargetSymbolId>0).</summary>
    /// <param name="ACallRef"><!-- drag-lint:auto type -->const TReference</param>
    /// <returns><!-- drag-lint:auto -->TCallEdge -- Observed: Default(TCallEdge).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Storage.SQLite.TSQLiteSymbolStore.ResolveCallTargets (DRagLint.Storage.SQLite.pas)</para>
    /// <para>Calls: Default, DRagLint.Index.CallResolver.CountCallArgs, DRagLint.Index.CallResolver.ExtractReceiverExpr, DRagLint.Index.CallResolver.TCallResolver.FileIsStale, DRagLint.Index.CallResolver.TCallResolver.LinesOf, DRagLint.Index.CallResolver.TCallResolver.LookupInLexicalScopes, DRagLint.Index.CallResolver.TCallResolver.LookupMemberOnType, DRagLint.Index.CallResolver.TCallResolver.LookupMethodOnType, DRagLint.Index.CallResolver.TCallResolver.LookupUnitLevelRoutine, DRagLint.Index.CallResolver.TCallResolver.MemberAccessMode, DRagLint.Index.CallResolver.TCallResolver.ResolveAccessor, DRagLint.Index.CallResolver.TCallResolver.ResolveExternally, DRagLint.Index.CallResolver.TCallResolver.TypeReceiver, SameText</para>
    /// <para>Complexity: 18 (cyclomatic, outer body), 158 lines (full implementation)</para>
    /// <para>Reads: FExtraStores</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Index.CallResolver.CountCallArgs"/>
    /// <seealso cref="DRagLint.Index.CallResolver.ExtractReceiverExpr"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.FileIsStale"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.LinesOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.LookupInLexicalScopes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ResolveOne(const ACallRef: TReference): TCallEdge;

    /// <summary>Shape A (2026-09-23, enum-value-ref-binding): resolve a bare
    /// `read` ref that names an enum value, by NAME and SCOPE only -- rules
    /// R1-R4 of the spec. Answers `certain` or nothing; there is no ambiguous
    /// value binding.</summary>
    /// <param name="ARef">The candidate read ref. FileId, NameText and
    /// EnclosingSymbolId are the only fields consulted.</param>
    /// <param name="AReason">OUT: '' when the ref bound OR when its name is not
    /// an enum-value name at all; otherwise the decline reason --
    /// 'not-visible' | 'ambiguous' | 'shadowed'.</param>
    /// <returns>The enum_value symbol id, or 0 for every decline.</returns>
    /// <remarks>
    /// READS NO SOURCE LINE, deliberately. Every other rung of this resolver
    /// starts by reading the ref's line to recover a receiver, which is why they
    /// need the stale-file withholding in ResolveOne; with no line read there is
    /// nothing here for staleness to withhold, and the answer is a pure function
    /// of the symbol table.
    ///
    /// Not counted as a decline when the name matches no enum value: the store's
    /// candidate SQL already filtered the stream to enum-value names, so such a
    /// call is the caller asking about a ref that was never a candidate.
    /// </remarks>
    function ResolveEnumValueRead(const ARef: TReference; out AReason: string): Int64;

    /// <summary>Per-run counters of the enum-value pass -- bindings, and every
    /// decline by reason. Read by the calls stage for its ResolveLog line.</summary>
    /// <remarks>Cumulative over the resolver's lifetime; one resolver serves one
    /// pass, so these are that pass's totals.</remarks>
    property EnumStats: TEnumResolveStats read FEnumStats;

    /// <summary>D1 (2026-09-23, resolver 1.7.0-alpha): decide whether a `read`
    /// ref is a PARENLESS CALL -- a routine with no required parameters named
    /// without parentheses in an expression (`Assert(NextId &gt; 0)`,
    /// `N := NextId`, a bare `Tick` inside its class) -- and if so, to what.</summary>
    /// <param name="ARef">The candidate read ref. FileId, NameText, StartLine,
    /// StartCol and EnclosingSymbolId are consulted.</param>
    /// <param name="AReason">OUT: '' when the ref bound; otherwise the decline
    /// reason -- 'unreadable' | 'qualified' | 'with-scope' | 'shadowed' |
    /// 'not-found' | 'not-callable' | 'proc-value'.</param>
    /// <returns>An edge whose TargetSymbolId is the called routine and whose
    /// Confidence is 'certain' or 'ambiguous' (an override or duplicate set, the
    /// same policy as a `call` ref), or TargetSymbolId = 0 for every decline.</returns>
    /// <remarks>
    /// The NEAREST declaration of the name decides, exactly as the compiler's
    /// scoping does: lexical scopes, then the enclosing class and its ancestors,
    /// then the own unit, then the interfaces of the units it uses. When that
    /// declaration is a VALUE (local, parameter, field, property, const, var,
    /// type, enum value) the read is not a call -- 'shadowed'. When it is a
    /// routine set, every member must return a value and accept zero arguments,
    /// or the read may be a procedure VALUE -- 'not-callable'.
    ///
    /// A procedure value is also refused by SITE: `@Name`, or Name as the whole
    /// right side of an assignment or a whole argument whose declared type is
    /// procedural. A target type the index cannot see (an RTL `TFunc&lt;T&gt;`
    /// named through an alias it does not hold, a property of a class outside the
    /// index) is not detected, and the read binds -- recorded as the pass's known
    /// blind spot.
    ///
    /// Any `with` earlier in the enclosing routine declines ('with-scope'); a
    /// receiver other than Self declines ('qualified' -- a qualified parenless
    /// call is a `member-access` ref and the main stream owns it).
    /// Counted into ParenlessStats, one outcome per call.
    /// </remarks>
    function ResolveParenlessRead(const ARef: TReference; out AReason: string): TCallEdge;

    /// <summary>Per-run counters of the parenless-call pass. Read by the calls
    /// stage for its ResolveLog line.</summary>
    /// <remarks>Cumulative over the resolver's lifetime; one resolver serves one
    /// pass.</remarks>
    property ParenlessStats: TParenlessResolveStats read FParenlessStats;
  end;

  /// <summary>Extract the receiver expression immediately left of a dotted call.
  /// ARefCol is the 1-based column of the called method name's first char (the
  /// ref position the parser stores for X.M -> col of M). Returns the receiver
  /// text ('FBar', 'Self', 'A.B', '(X as TBar)', 'GetFoo') or '' for a bare /
  /// non-dotted call. Pure over ASourceLine; unit-tested via
  /// TCallResolver's own trace.</summary>
  /// <param name="ASourceLine"><!-- drag-lint:auto type -->const string</param>
  /// <param name="ARefCol"><!-- drag-lint:auto type -->Integer</param>
  /// <returns><!-- drag-lint:auto -->string -- Observed: ''; Trim(Copy(Line, StopL,
  /// ARefCol - 1 - StopL)).</returns>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)</para>
  /// <para>Calls: Copy, DRagLint.Index.CallResolver.IsIdentPart, Trim</para>
  /// <para>Complexity: 34 (cyclomatic, outer body), 96 lines (full implementation)</para>
  /// <para>Pure</para>
  /// <seealso cref="DRagLint.Index.CallResolver.IsIdentPart"/>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  function ExtractReceiverExpr(const ASourceLine: string; ARefCol: Integer): string;

  /// <summary>True when ATypeText, normalized, is a hard cast prefix shape
  /// '(EXPR as TName)' or 'TName(EXPR)'; if so ATypeName receives the target
  /// type name TName. Used by receiver kind 6 (cast). False otherwise.</summary>
  /// <param name="AReceiverExpr"><!-- drag-lint:auto type -->const string</param>
  /// <param name="ATypeName"><!-- drag-lint:auto type -->out string</param>
  /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.TypeReceiver (DRagLint.Index.CallResolver.pas)</para>
  /// <para>Calls: Copy, DRagLint.Index.CallResolver.IsIdentPart, DRagLint.Index.CallResolver.IsIdentStart, SameText, Trim</para>
  /// <para>Complexity: 32 (cyclomatic, outer body), 69 lines (full implementation)</para>
  /// <para>Mutates: ATypeName (out)</para>
  /// <seealso cref="DRagLint.Index.CallResolver.IsIdentPart"/>
  /// <seealso cref="DRagLint.Index.CallResolver.IsIdentStart"/>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  function TryParseCastTarget(const AReceiverExpr: string; out ATypeName: string): Boolean;

  /// <summary>B1: counts the arguments passed at a call site. ALine/ACol are
  /// 1-based and ACol is the column of the CALLEE NAME's first character --
  /// exactly what refs.start_col stores, for both `M(...)` and `Obj.M(...)`.</summary>
  /// <param name="ALines">The callee's source file. Nil / out-of-range yields
  /// AKnown=False.</param>
  /// <param name="ALine"><!-- drag-lint:auto type -->Integer</param>
  /// <param name="ACol"><!-- drag-lint:auto type -->Integer</param>
  /// <param name="AKnown">False when the site could not be read, or when its
  /// argument list never closes within the scan budget. Callers must not
  /// consult the count in that case.</param>
  /// <returns>Top-level argument count; 0 for `M` and for `M()`.</returns>
  /// <remarks>
  /// Scans forward across LINES -- a call whose arguments are spread
  /// over several lines is one call. Nested (), [] and string literals do not
  /// contribute separators. Pure over ALines.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)</para>
  /// <para>Calls: DRagLint.Index.CallResolver.IsIdentPart</para>
  /// <para>Returns: 0; Commas + 1</para>
  /// <para>Complexity: 57 (cyclomatic, outer body), 152 lines (full implementation)</para>
  /// <para>Mutates: AKnown (out)</para>
  /// <seealso cref="DRagLint.Index.CallResolver.IsIdentPart"/>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  function CountCallArgs(ALines: TStrings; ALine, ACol: Integer; out AKnown: Boolean): Integer;

  /// <summary>B1: the range of argument counts a signature accepts. A parameter
  /// with a DEFAULT is optional, so the range is [required..declared] and a
  /// signature is not a single number.</summary>
  /// <param name="ASignature">A stored symbol Signature, e.g.
  /// '(const A: string; const B: Integer = 0): string'.</param>
  /// <param name="AMin"><!-- drag-lint:auto type -->out Integer</param>
  /// <param name="AMax"><!-- drag-lint:auto type -->out Integer</param>
  /// <returns>False when ASignature is not shaped like a parameter list, in
  /// which case the caller must not filter on it.</returns>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Called from: DRagLint.Doc.Facts.OverloadArityTag (DRagLint.Doc.Facts.pas), DRagLint.Index.CallResolver.PropertyIndexArity (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.PickAccessor (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.PickFromMatches (DRagLint.Index.CallResolver.pas)</para>
  /// <para>Calls: Copy, Pos, SplitString, StartsText, Trim</para>
  /// <para>Returns: False; True</para>
  /// <para>Complexity: 25 (cyclomatic, outer body), 103 lines (full implementation)</para>
  /// <para>Mutates: AMin (out), AMax (out)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  function SignatureArityRange(const ASignature: string; out AMin, AMax: Integer): Boolean;

implementation

uses
  System.Math,     // Min -- ResolveAccessor's declaring-line range
  System.StrUtils; // B1: StartsText / SplitString, used by SignatureArityRange

const
  // The set of type-defining kinds a receiver can be typed to.
  TYPE_KINDS: TSymbolKindSet = [skClass, skInterface, skRecord];
  // Method-shaped children we accept as a call target on a resolved type.
  METHOD_KINDS: TSymbolKindSet = [skMethod, skProcedure, skFunction, skConstructor, skDestructor];

// True when C can start / continue a Pascal identifier.
function IsIdentStart(C: Char): Boolean; inline;
begin
  Result:= (C = '_') or ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z'));
end;

function IsIdentPart(C: Char): Boolean; inline;
begin
  Result:= IsIdentStart(C) or ((C >= '0') and (C <= '9'));
end;

// v14 (D5): walk left from the dot preceding a call to capture the receiver.
// Handles: dotted identifier chains (A.B.C), a bracket-balanced trailing group
// ((expr) / [idx]) for cast / index / function-return receivers. Stops at the
// first boundary that cannot be part of a primary expression.
function ExtractReceiverExpr(const ASourceLine: string; ARefCol: Integer): string;
var
  Line : string ;
  I    : Integer;
  StopL: Integer; // leftmost captured index (inclusive)
  Depth: Integer;
  Ch   : Char   ;
begin
  Result:= '';
  Line  := ASourceLine;
  // ARefCol is 1-based at the method name; the char just before it must be '.'
  // for this to be a dotted call. Guard the bounds first.
  if (ARefCol <= 1) or (ARefCol > Length(Line) + 1) then Exit;
  I:= ARefCol - 1; // index of the char immediately before the method name
  if (I < 1) or (I > Length(Line)) or (Line[I] <> '.') then Exit; // bare / non-dotted
  // Now capture the primary expression ending at I-1 (just left of the dot),
  // skipping whitespace between the receiver and the dot.
  I:= I - 1;
  while (I >= 1) and (Line[I] = ' ') do Dec(I);
  if I < 1 then Exit;
  StopL:= I + 1; // will be overwritten as we consume tokens
  // Loop: consume a selector segment (identifier or bracket group), then if the
  // next char left is a '.', consume the dot and keep going (dotted chain).
  while I >= 1 do
  begin
    Ch:= Line[I];
    if Ch = '>' then
    begin
      // GENERIC ARGUMENT LIST: 'TArray<string>.Create', 'TPair<string,
      // Integer>.Create'. Without this the scan breaks on '>' and returns '',
      // which is the SAME value a bare call yields -- so every generic
      // construction looked unqualified and was offered as a caller of every
      // symbol sharing its leaf name. Measured on this repo: the three residual
      // false callers left on TQueryRule.Create after the v20 receiver filter
      // were all TArray<>/TPair<> constructions.
      //
      // Safe against '>' the COMPARISON operator, because this scan only ever
      // looks at the character immediately left of the receiver's dot: in
      // 'X > Y.Foo' that character is 'Y', and in '(A > B).Foo' it is ')'. A '>'
      // can land here only as the close of a generic argument list.
      Depth:= 0;
      while I >= 1 do
      begin
        if Line[I] = '>' then Inc(Depth)
        else if Line[I] = '<' then
        begin
          Dec(Depth);
          if Depth = 0 then Break;
        end;
        Dec(I);
      end;
      if Depth <> 0 then Exit; // unbalanced -> give up (return '')
      StopL:= I;
      // The '<' group is preceded by the generic type's own name: TArray<...>.
      Dec(I);
      while (I >= 1) and IsIdentPart(Line[I]) do begin StopL:= I; Dec(I); end;
    end
    else if (Ch = ')') or (Ch = ']') then
    begin
      // Balanced bracket group: walk left to its matching opener.
      Depth:= 0;
      while I >= 1 do
      begin
        if (Line[I] = ')') or (Line[I] = ']') then Inc(Depth)
        else if (Line[I] = '(') or (Line[I] = '[') then
        begin
          Dec(Depth);
          if Depth = 0 then Break;
        end;
        Dec(I);
      end;
      if Depth <> 0 then Exit; // unbalanced -> give up (return '')
      StopL:= I;
      // A '(' or '[' group may be preceded by an identifier: TName(expr) or Arr[i].
      Dec(I);
      while (I >= 1) and IsIdentPart(Line[I]) do begin StopL:= I; Dec(I); end;
    end
    else if IsIdentPart(Ch) then
    begin
      while (I >= 1) and IsIdentPart(Line[I]) do begin StopL:= I; Dec(I); end;
    end
    else
      Break; // not part of a primary expression
    // Continue a dotted chain only when a '.' immediately precedes (allowing no
    // spaces -- dotted member access is written tight in practice).
    if (I >= 1) and (Line[I] = '.') then
    begin
      StopL:= I;
      Dec(I);
    end
    else
      Break;
  end;
  Result:= Trim(Copy(Line, StopL, ARefCol - 1 - StopL));
  // Copy above spans [StopL .. (ARefCol-2)] i.e. everything up to but excluding
  // the '.' before the method name. Length = (ARefCol-1) - StopL.
end;

// v14 (D5): recognize the two hard-cast receiver shapes so kind 6 can take the
// cast TARGET type directly. '(EXPR as TName)' -> TName; 'TName(EXPR)' -> TName.
// Only fires on an outermost single cast; nested / chained shapes return False.
function TryParseCastTarget(const AReceiverExpr: string; out ATypeName: string): Boolean;
var
  S      : string ;
  P, Q   : Integer;
  AsPos  : Integer;
  Inner  : string ;
  TypeTok: string ;
  I      : Integer;
begin
  Result  := False;
  ATypeName:= '';
  S:= Trim(AReceiverExpr);
  if S = '' then Exit;
  // Shape A: '(EXPR as TName)' -- outermost parens, a top-level ' as ' inside.
  if (S[1] = '(') and (S[Length(S)] = ')') then
  begin
    Inner:= Copy(S, 2, Length(S) - 2);
    // Find a top-level ' as ' (depth 0) in Inner.
    var Depth: Integer:= 0;
    AsPos:= 0;
    I:= 1;
    while I <= Length(Inner) - 3 do
    begin
      case Inner[I] of
        '(', '[': Inc(Depth);
        ')', ']': Dec(Depth);
      end;
      if (Depth = 0) and (I > 1) and (Inner[I] = ' ') and
         SameText(Copy(Inner, I + 1, 2), 'as') and (I + 3 <= Length(Inner)) and
         (Inner[I + 3] = ' ') then
      begin
        AsPos:= I;
        Break;
      end;
      Inc(I);
    end;
    if AsPos > 0 then
    begin
      TypeTok:= Trim(Copy(Inner, AsPos + 4, MaxInt));
      // TypeTok should be a (possibly dotted) type name -- take its leading token.
      P:= 1;
      while (P <= Length(TypeTok)) and (IsIdentPart(TypeTok[P]) or (TypeTok[P] = '.')) do Inc(P);
      TypeTok:= Copy(TypeTok, 1, P - 1);
      if TypeTok <> '' then begin ATypeName:= TypeTok; Exit(True); end;
    end;
  end;
  // Shape B: 'TName(EXPR)' -- leading identifier then a balanced paren to the end.
  if (Length(S) >= 3) and IsIdentStart(S[1]) then
  begin
    P:= 1;
    while (P <= Length(S)) and (IsIdentPart(S[P]) or (S[P] = '.')) do Inc(P);
    if (P <= Length(S)) and (S[P] = '(') and (S[Length(S)] = ')') then
    begin
      TypeTok:= Copy(S, 1, P - 1);
      // Ensure the paren that opens at P matches the final ')' (single outer cast).
      var Depth2: Integer:= 0;
      Q:= 0;
      for I:= P to Length(S) do
      begin
        if S[I] = '(' then Inc(Depth2)
        else if S[I] = ')' then
        begin
          Dec(Depth2);
          if Depth2 = 0 then begin Q:= I; Break; end;
        end;
      end;
      if (Q = Length(S)) and (TypeTok <> '') then begin ATypeName:= TypeTok; Exit(True); end;
    end;
  end;
end;

// B1 -------------------------------------------------------------------------
// Overload separation by argument count. Both helpers are PURE (no store, no
// cache) so they can be reasoned about on their own; the policy that uses them
// lives in LookupMethodOnType, which states when they are allowed to decide.

const
  // A single call's argument list may span lines, but not arbitrarily many. The
  // budget bounds the damage when a source file is mis-lexed (an unterminated
  // string, a preprocessor construct we do not model): rather than walking to
  // EOF for every unbalanced site in a large corpus, give up and report the
  // count as unknown, which falls back to pre-B1 behaviour.
  ARGSCAN_MAX_LINES = 60;

function CountCallArgs(ALines: TStrings; ALine, ACol: Integer; out AKnown: Boolean): Integer;
var
  Li, Ci  : Integer;
  Depth   : Integer;
  Commas  : Integer;
  Scanned : Integer;
  InStr   : Boolean;
  InBrace : Boolean; // { ... }
  InParStar: Boolean; // (* ... *)
  Cur     : string ;
  C       : Char   ;
  SawArg  : Boolean;

  { Advance one character, crossing to the next line when the current one runs
    out. False when the budget is spent or the file ends. }
  function Next: Boolean;
  begin
    Inc(Ci);
    while Ci > Length(Cur) do
    begin
      Inc(Li);
      Inc(Scanned);
      if (Li >= ALines.Count) or (Scanned > ARGSCAN_MAX_LINES) then Exit(False);
      Cur:= ALines[Li];
      Ci := 1;
      { A line comment ends AT the newline, so crossing a line clears it. }
      if Ci <= Length(Cur) then Break;
    end;
    Result:= True;
  end;

begin
  AKnown := False;
  Result := 0;
  if (ALines = nil) or (ALine < 1) or (ALine > ALines.Count) or (ACol < 1) then Exit;

  Li := ALine - 1;
  Cur:= ALines[Li];
  Ci := ACol;
  if Ci > Length(Cur) then Exit;
  Scanned:= 0;

  { 1. step over the callee identifier itself. }
  while (Ci <= Length(Cur)) and IsIdentPart(Cur[Ci]) do Inc(Ci);

  { 2. skip whitespace and comments to the first significant character -- a call
       may legally carry a brace comment between the name and its arguments. }
  InBrace  := False;
  InParStar:= False;
  while True do
  begin
    if Ci > Length(Cur) then
    begin
      if not Next then Exit; { ran out before finding anything significant }
      Continue;
    end;
    C:= Cur[Ci];
    if InBrace then
    begin
      if C = '}' then InBrace:= False;
      Inc(Ci);
      Continue;
    end;
    if InParStar then
    begin
      if (C = '*') and (Ci < Length(Cur)) and (Cur[Ci + 1] = ')') then begin InParStar:= False; Inc(Ci); end;
      Inc(Ci);
      Continue;
    end;
    if C = '{' then begin InBrace:= True; Inc(Ci); Continue; end;
    if (C = '(') and (Ci < Length(Cur)) and (Cur[Ci + 1] = '*') then
    begin InParStar:= True; Inc(Ci, 2); Continue; end;
    if (C = '/') and (Ci < Length(Cur)) and (Cur[Ci + 1] = '/') then
    begin { line comment: jump to the next line } Ci:= Length(Cur) + 1; Continue; end;
    if (C = ' ') or (C = #9) then begin Inc(Ci); Continue; end;
    Break;
  end;

  { 3. No '(' means a PAREN-LESS call -- legal in Pascal, and it passes nothing. }
  if Cur[Ci] <> '(' then
  begin
    AKnown:= True;
    Exit(0);
  end;

  { 4. Walk the argument list, counting separators at depth 1 only. '[' shares
       the depth counter because a comma inside an index expression is not an
       argument separator either. }
  Depth := 0;
  Commas:= 0;
  InStr := False;
  SawArg:= False;
  while True do
  begin
    if Ci > Length(Cur) then
    begin
      if not Next then Exit; { never closed -> AKnown stays False }
      { a line comment and a string literal both end at the newline }
      InStr:= False;
      Continue;
    end;
    C:= Cur[Ci];

    if InStr then
    begin
      { '' inside a literal is an escaped quote; toggling twice handles it. }
      if C = '''' then InStr:= False;
      Inc(Ci);
      Continue;
    end;
    if InBrace then
    begin
      if C = '}' then InBrace:= False;
      Inc(Ci);
      Continue;
    end;
    if InParStar then
    begin
      if (C = '*') and (Ci < Length(Cur)) and (Cur[Ci + 1] = ')') then begin InParStar:= False; Inc(Ci); end;
      Inc(Ci);
      Continue;
    end;

    case C of
      '''': InStr:= True;
      '{' : InBrace:= True;
      '(' :
        if (Ci < Length(Cur)) and (Cur[Ci + 1] = '*') then begin InParStar:= True; Inc(Ci); end
        else Inc(Depth);
      '[' : Inc(Depth);
      ']' : Dec(Depth);
      ')' :
        begin
          Dec(Depth);
          if Depth = 0 then
          begin
            AKnown:= True;
            if SawArg then Result:= Commas + 1 else Result:= 0;
            Exit;
          end;
        end;
      ',' : if Depth = 1 then Inc(Commas);
      '/' : if (Ci < Length(Cur)) and (Cur[Ci + 1] = '/') then
            begin Ci:= Length(Cur); { skip to EOL; the += 1 below lands past it } end;
    end;

    { Anything that is not whitespace, and not the opening paren itself, proves
      the list is non-empty -- so `M()` counts 0 while `M( X )` counts 1. }
    if (Depth >= 1) and (C <> '(') and (C <> ' ') and (C <> #9) then SawArg:= True;

    Inc(Ci);
  end;
end;

function SignatureArityRange(const ASignature: string; out AMin, AMax: Integer): Boolean;
var
  I, Depth, Start: Integer;
  Inner : string ;
  Groups: TStringList;
  G, Names: string;
  InStr : Boolean;
  HasDefault: Boolean;
  N, K  : Integer;
  Part  : string ;
begin
  AMin  := 0;
  AMax  := 0;
  Result:= False;

  { A routine with NO parameter list has no parens at all ('': Integer' or ''),
    and accepts exactly zero arguments -- a real answer, not a parse failure. }
  I:= Pos('(', ASignature);
  if I = 0 then Exit(True);

  { Balanced extract of the parameter list. A default value can itself contain
    parens ('= TFoo.Create'), so counting is the only safe way to find the end. }
  Depth := 0;
  InStr := False;
  Start := I + 1;
  Inner := '';
  for K:= I to Length(ASignature) do
  begin
    if InStr then
    begin
      if ASignature[K] = '''' then InStr:= False;
      Continue;
    end;
    case ASignature[K] of
      '''': InStr:= True;
      '(' : Inc(Depth);
      ')' :
        begin
          Dec(Depth);
          if Depth = 0 then
          begin
            Inner:= Copy(ASignature, Start, K - Start);
            Break;
          end;
        end;
    end;
  end;
  if Depth <> 0 then Exit; { unbalanced -> refuse to answer }
  if Trim(Inner) = '' then Exit(True); { '()' -> zero parameters }

  { Split at TOP-LEVEL ';' -- one group per declared parameter clause. }
  Groups:= TStringList.Create;
  try
    Depth := 0;
    InStr := False;
    Start := 1;
    for K:= 1 to Length(Inner) do
    begin
      if InStr then
      begin
        if Inner[K] = '''' then InStr:= False;
        Continue;
      end;
      case Inner[K] of
        '''': InStr:= True;
        '(', '[': Inc(Depth);
        ')', ']': Dec(Depth);
        ';': if Depth = 0 then
             begin
               Groups.Add(Copy(Inner, Start, K - Start));
               Start:= K + 1;
             end;
      end;
    end;
    Groups.Add(Copy(Inner, Start, Length(Inner) - Start + 1));

    for G in Groups do
    begin
      if Trim(G) = '' then Continue;
      HasDefault:= Pos('=', G) > 0;
      { Names are everything left of the first ':'. An untyped 'var X' group has
        no colon at all, in which case the whole group is names. }
      K:= Pos(':', G);
      if K > 0 then Names:= Copy(G, 1, K - 1) else Names:= G;
      Names:= Trim(Names);
      { Drop one leading parameter modifier. }
      for Part in TArray<string>.Create('const ', 'var ', 'out ') do
        if StartsText(Part, Names) then
        begin
          Names:= Trim(Copy(Names, Length(Part) + 1, MaxInt));
          Break;
        end;
      N:= 0;
      for Part in SplitString(Names, ',') do
        if Trim(Part) <> '' then Inc(N);
      if N = 0 then Continue;
      Inc(AMax, N);
      if not HasDefault then Inc(AMin, N);
    end;
  finally
    Groups.Free;
  end;
  Result:= True;
end;

{ TCallResolver }

constructor TCallResolver.Create(const AStore: ISymbolStore;
  const AExtraStores: TArray<ISymbolStore>);
begin
  inherited Create;
  FStore      := AStore;
  FExtraStores:= AExtraStores;
  FNameToCands:= TObjectDictionary<string, TList<TSymbol>>.Create([doOwnsValues]);
  FNameToRoutines:= TObjectDictionary<string, TList<TSymbol>>.Create([doOwnsValues]);
  FNameToEnumValues:= TObjectDictionary<string, TList<TEnumValueDecl>>.Create([doOwnsValues]);
  FNameToUnitValues:= TObjectDictionary<string, TList<TSymbol>>.Create([doOwnsValues]);
  FEnumStats  := Default(TEnumResolveStats);
  FParenlessStats:= Default(TParenlessResolveStats);
  FFileScope  := TObjectDictionary<Int64, TList<Int64>>.Create([doOwnsValues]);
  FChildCache := TObjectDictionary<Int64, TList<TSymbol>>.Create([doOwnsValues]);
  FLineCache  := TObjectDictionary<Int64, TStringList>.Create([doOwnsValues]);
  FStaleFiles := TDictionary<Int64, Boolean>.Create;
  BuildMaps;
end;

destructor TCallResolver.Destroy;
begin
  FLineCache .Free;
  FStaleFiles.Free;
  FChildCache.Free;
  FFileScope .Free;
  FNameToUnitValues.Free;
  FNameToEnumValues.Free;
  FNameToRoutines.Free;
  FNameToCands.Free;
  FStore:= nil;
  inherited;
end;

procedure TCallResolver.BuildMaps;
var
  Cands: TArray<TSymbol>;
  Edges: TArray<TFileScopeEdge>;
  S    : TSymbol   ;
  Lc   : string    ;
  E    : TFileScopeEdge;
begin
  // 1. candidate type symbols by lowercased simple name.
  Cands:= FStore.GetTypeCandidates;
  for S in Cands do
  begin
    Lc:= LowerCase(S.Name);
    if Lc = '' then Continue;
    if not FNameToCands.ContainsKey(Lc) then FNameToCands.Add(Lc, TList<TSymbol>.Create);
    FNameToCands[Lc].Add(S);
  end;
  // 1b. Option 4: candidate UNIT-LEVEL routines by lowercased name. Same shape
  // as the type map above, and built in the same single pass over the DB so the
  // resolver still costs two bulk reads rather than a query per call site.
  for S in FStore.GetUnitLevelRoutines do
  begin
    Lc:= LowerCase(S.Name);
    if Lc = '' then Continue;
    if not FNameToRoutines.ContainsKey(Lc) then FNameToRoutines.Add(Lc, TList<TSymbol>.Create);
    FNameToRoutines[Lc].Add(S);
  end;
  // 1c. 2026-09-23 (enum-value-ref-binding): the enum-value CANDIDATE map and
  // the unit-level const/var SHADOW map, built in the same single pass for the
  // same reason -- the enum-value rules are consulted per candidate ref over a
  // whole-DB stream, so both sets are bulk-read once here or paid for per ref.
  for var EV: TEnumValueDecl in FStore.GetEnumValueSymbols do  // dl:ok duplicate-code@3a9a -- REVIEWED 2026-09-23: the four-line "append to a name-keyed list map" idiom, now written over THREE element types (TSymbol twice, TEnumValueDecl once). Collapsing it needs a generic helper method, and two of the three loops are pre-existing code this change does not own -- so the de-duplication would rewrite BuildMaps, and with it the resolver surface hash, for a token-count heuristic rather than for behaviour.
  begin
    Lc:= LowerCase(EV.Name);
    if Lc = '' then Continue;
    if not FNameToEnumValues.ContainsKey(Lc) then FNameToEnumValues.Add(Lc, TList<TEnumValueDecl>.Create);
    FNameToEnumValues[Lc].Add(EV);
  end;
  for S in FStore.GetUnitLevelValueDecls do
  begin
    Lc:= LowerCase(S.Name);
    if Lc = '' then Continue;
    if not FNameToUnitValues.ContainsKey(Lc) then FNameToUnitValues.Add(Lc, TList<TSymbol>.Create);
    FNameToUnitValues[Lc].Add(S);
  end;
  // 2. per-file in-scope target file ids from the uses graph.
  Edges:= FStore.GetUnitScopeEdges;
  for E in Edges do
  begin
    if not FFileScope.ContainsKey(E.FileId) then FFileScope.Add(E.FileId, TList<Int64>.Create);
    FFileScope[E.FileId].Add(E.TargetFileId);
  end;
end;

function TCallResolver.CandInScope(ADeclFile, ACandFile: Int64): Boolean;
var
  L: TList<Int64>;
begin
  Result:= (ADeclFile = ACandFile);
  if Result then Exit;
  if FFileScope.TryGetValue(ADeclFile, L) then Result:= L.IndexOf(ACandFile) >= 0;
end;

function TCallResolver.ResolveTypeNameToSymbol(const ATypeText: string; ADeclFileId: Int64): Int64;
var
  N    : string        ;
  Cands: TList<TSymbol>;
  InScopeIdx, InScopeCount: Integer;
  ci   : Integer       ;
begin
  Result:= 0;
  // Normalize the same way ResolveAncestry does: strip generics + dotted qualifier.
  N:= ATypeText;
  // inline of NormalizeAncestorName (kept local to avoid a storage-unit dep):
  N:= Trim(N);
  var LtPos: Integer:= Pos('<', N);
  if LtPos > 0 then N:= Trim(Copy(N, 1, LtPos - 1));
  // DotPos is 0-based (TStringHelper.LastDelimiter, NOT the 1-based global
  // LastDelimiter that ResolveAncestry uses), hence Copy from DotPos + 2 to land
  // one char PAST the dot. A future "switch to 1-based" edit must also drop the +1.
  var DotPos: Integer:= N.LastDelimiter('.');
  if DotPos >= 0 then N:= Trim(Copy(N, DotPos + 2, MaxInt));
  if N = '' then Exit;
  if not FNameToCands.TryGetValue(LowerCase(N), Cands) then Exit;
  InScopeIdx  := -1;
  InScopeCount:= 0;
  for ci:= 0 to Cands.Count - 1 do
    if CandInScope(ADeclFileId, Cands[ci].FileId) then
    begin
      Inc(InScopeCount);
      if InScopeIdx < 0 then InScopeIdx:= ci;
    end;
  // Resolve only when unambiguous (mirrors ResolveAncestry's FP policy):
  //   exactly one in-scope candidate, OR (none in scope) a single global def.
  if InScopeCount = 1 then
    Result:= Cands[InScopeIdx].Id
  else if (InScopeCount = 0) and (Cands.Count = 1) then
    Result:= Cands[0].Id;
end;

function TCallResolver.ChildrenOf(AParentId: Int64): TList<TSymbol>;
var
  Arr: TArray<TSymbol>;
  S  : TSymbol        ;
begin
  if AParentId <= 0 then Exit(nil);
  if FChildCache.TryGetValue(AParentId, Result) then Exit;
  Result:= TList<TSymbol>.Create;
  Arr   := FStore.FindAllChildSymbols(AParentId);
  for S in Arr do Result.Add(S);
  FChildCache.Add(AParentId, Result);
end;

function TCallResolver.LinesOf(AFileId: Int64): TStringList;
var
  Path : string;
  Bytes: TBytes;
  Txt  : string;
begin
  if AFileId <= 0 then Exit(nil);
  if FLineCache.TryGetValue(AFileId, Result) then Exit;
  Result:= TStringList.Create;
  Path  := FStore.GetFilePath(AFileId);
  if Path <> '' then
    try
      { STALENESS PROBE (INBOX-whole-db-resolve-degrades-a-stale-index).

        This reads the file as it is on disk NOW, while Ref.StartLine /
        Ref.StartCol are where the ref was when that file was last INDEXED. For
        any file edited since it was indexed the two disagree, so the caller
        reads an unrelated line at an unrelated column and derives a receiver
        from it. The pass then WRITES that over the good stored value -- not a
        failed refresh that leaves the old answer alone, but a successful write
        of a wrong one. Measured: one `index <single file>` run over a stale
        DragLint-Cli destroyed 11,008 receivers and 464 call edges.

        Losing receiver_text silently restores the exact fabrication it was
        added to prevent (a bare `Create` attributed to every constructor in the
        index), and nothing errors -- counts only go down.

        So: probe with the SAME inputs the indexer used to decide a file was up
        to date (raw bytes -> ANSI string -> SHA2, plus the file mtime), and
        record a mismatch. ResolveOne turns that into ReceiverUnknown, and the
        persistence step then LEAVES the stored receiver alone instead of
        overwriting it with a guess.

        Deliberately NOT "skip the file": resolution still runs, because a
        name-based rung can still be right. Only the receiver WRITE is withheld,
        which is the part that destroys information. }
      Bytes:= TFile.ReadAllBytes(Path);
      // ANSI: source files are strict 7-bit ASCII / CP125x, matching Doc.Facts.
      Txt  := TEncoding.ANSI.GetString(Bytes);
      if not FStore.FileIsUpToDate(Path,
               DateTimeToUnix(TFile.GetLastWriteTime(Path), False),
               THashSHA2.GetHashString(Txt)) then
        FStaleFiles.AddOrSetValue(AFileId, True);
      Result.Text:= Txt;
    except
      // A missing / locked / unreadable source file is not fatal to the whole-DB
      // pass: leave the line list empty so this ref's receiver stays unresolved
      // (Target=0) rather than aborting resolution for every other ref.
      //
      // It IS however "unknown", not "no receiver" -- an unreadable file must
      // not be allowed to blank every receiver in it, which is the same damage
      // the staleness probe above exists to prevent.
      Result.Clear;
      FStaleFiles.AddOrSetValue(AFileId, True);
    end;
  FLineCache.Add(AFileId, Result);
end;

function TCallResolver.FileIsStale(AFileId: Int64): Boolean;
begin
  Result:= FStaleFiles.ContainsKey(AFileId);
end;

function TCallResolver.FileIsStaleProbe(AFileId: Int64): Boolean;
begin
  LinesOf(AFileId); { performs the probe once, then caches both lines and verdict }
  Result:= FileIsStale(AFileId);
end;

function TCallResolver.FindChildOfKind(AParentId: Int64; const AName: string; const AKinds: TSymbolKindSet;
  ADeclineOnConflict: Boolean): TSymbol;
var
  Kids: TList<TSymbol>;
  S   : TSymbol       ;
begin
  Result:= Default(TSymbol);
  Kids  := ChildrenOf(AParentId);
  if Kids = nil then Exit;
  for S in Kids do
    if (S.Kind in AKinds) and SameText(S.Name, AName) then
    begin
      if not ADeclineOnConflict then Exit(S);
      if Result.Id = 0 then Result:= S
      else if Result.Signature <> S.Signature then Exit(Default(TSymbol));
    end;
end;

function TCallResolver.PickFromMatches(AMatches: TList<TSymbol>; AArgCount: Integer;
  AArgsKnown: Boolean; out AConfidence: string): Int64;
var
  Fit   : TList<TSymbol>;
  S     : TSymbol       ;
  Lo, Hi: Integer       ;
begin
  Result     := 0;
  AConfidence:= '';
  if (AMatches = nil) or (AMatches.Count = 0) then Exit; // not found -> 0 / '?'
  if AMatches.Count = 1 then
  begin
    Result     := AMatches[0].Id;
    AConfidence:= 'certain';
    Exit;
  end;

  // B1: several candidates share the name -- an OVERLOAD SET, or a class and an
  // ancestor both declaring the method. Argument count separates the first kind
  // and says nothing about the second, which is exactly the intended reach:
  // before this, `First` won, so for an overload set the LOWEST-id declaration
  // answered every call site. In YADF that made a 2-arg delegator whose body
  // calls the 3-arg implementation resolve to ITSELF, documenting a phantom
  // self-recursion while the real 603-line function recorded no callers at all.
  //
  // A default parameter makes a candidate accept a RANGE, so the test is
  // containment, not equality.
  Fit:= TList<TSymbol>.Create;
  try
    if AArgsKnown then
      for S in AMatches do
        if SignatureArityRange(S.Signature, Lo, Hi) and (AArgCount >= Lo) and (AArgCount <= Hi) then
          Fit.Add(S);

    if Fit.Count = 1 then
    begin
      Result     := Fit[0].Id;
      AConfidence:= 'certain';
      Exit;
    end;

    // Arity did not settle it. NARROWING ONLY: when several candidates fit, the
    // first of THOSE is a better guess than the first overall; when none fits
    // (an unreadable call site, a shape the counter does not model, a signature
    // it declined to parse) fall back to the pre-B1 answer exactly. Either way
    // the site still resolves and is still marked uncertain -- arity may improve
    // an answer, never remove one.
    if Fit.Count > 1 then Result:= Fit[0].Id else Result:= AMatches[0].Id;
    AConfidence:= 'ambiguous';
  finally
    Fit.Free;
  end;
end;

function TCallResolver.LookupMethodOnType(ATypeSymbolId: Int64; const AMethodName: string;
  AArgCount: Integer; AArgsKnown: Boolean; out AConfidence: string): Int64;
var
  Matches: TList<TSymbol>;
  Kids   : TList<TSymbol>;
  S      : TSymbol       ;
  A      : TTypeAncestor ;

  { Methods contributed by a record/class HELPER registered for AForTypeId.
    The store already has the edges -- `type_helpers` is populated by the
    resolve pass -- and this resolver simply never asked for them: before this,
    the unit contained no reference to type_helpers at all, so EVERY helper call
    in every index resolved to nothing.

    Measured cost of that, on the live indexes: 1,029 helper-member call refs in
    this repo's own index resolved 0; ORM3 CLIENT 18 of 1,644; SERVER 18 of
    1,745. `ChildByField` alone was 523 refs and 0 edges, which made
    find-callers answer "nothing calls this" for a method used on nearly every
    line of the parser. }
  procedure AddHelperMethods(AForTypeId: Int64);
  var
    HE: THelperEdge     ;
    HK: TList<TSymbol>  ;
    HS: TSymbol         ;
  begin
    if AForTypeId <= 0 then Exit;
    for HE in FStore.FindHelpersOfTypeSymbol(AForTypeId) do
    begin
      if HE.HelperSymbolId <= 0 then Continue;
      HK:= ChildrenOf(HE.HelperSymbolId);
      if HK = nil then Continue;
      for HS in HK do
        if (HS.Kind in METHOD_KINDS) and SameText(HS.Name, AMethodName) then Matches.Add(HS);
    end;
  end;

begin
  Result     := 0;
  AConfidence:= '';
  if ATypeSymbolId <= 0 then Exit;

  Matches:= TList<TSymbol>.Create;
  try
    // 1. the type's own methods.
    Kids:= ChildrenOf(ATypeSymbolId);
    if Kids <> nil then
      for S in Kids do
        if (S.Kind in METHOD_KINDS) and SameText(S.Name, AMethodName) then Matches.Add(S);
    // 2. inherited methods along the transitive ancestor chain. A method defined
    // on an ancestor counts too; overrides on the type itself already counted in
    // step 1 (so a class + its base each declaring M yields 2 matches ->
    // ambiguous, correctly flagging that the concrete target is uncertain).
    for A in FStore.GetTransitiveAncestors(ATypeSymbolId) do
    begin
      if not A.Resolved or (A.SymbolId <= 0) then Continue;
      Kids:= ChildrenOf(A.SymbolId);
      if Kids = nil then Continue;
      for S in Kids do
        if (S.Kind in METHOD_KINDS) and SameText(S.Name, AMethodName) then Matches.Add(S);
    end;

    { 3. HELPER methods -- but ONLY when steps 1 and 2 found nothing.

      Delphi's real rule is that a helper method HIDES a same-named method of
      the type it helps, so a full implementation would give the helper
      PRECEDENCE. This deliberately does not: it consults helpers only as a
      fallback.

      Why the weaker rule is the right v1. Adding helper matches unconditionally
      would put a second candidate alongside an already-resolved one, and
      PickFromMatches reads two candidates as AMBIGUOUS -- so a call that
      resolves today would stop resolving, or drop confidence. That is a
      REMOVED edge, which is the one outcome a resolution change must never
      produce. As a fallback it is additive by construction: every edge that
      existed before still exists, unchanged.

      The measured population needs nothing more -- the helper-backed calls that
      resolve to nothing today (TTSNodeHelper.ChildByField and friends) are
      methods the underlying type does NOT declare, so steps 1 and 2 are empty
      for them anyway. The hiding case is real Delphi but is not what is broken;
      it can be taken separately, with its own fixture, if it ever shows up. }
    if Matches.Count = 0 then
    begin
      AddHelperMethods(ATypeSymbolId);
      { A helper for an ANCESTOR is in scope for a descendant-typed receiver
        too, and this is also the path that makes an ALIAS-typed receiver work:
        member C of the extractor batch gives the alias an ordinal-0 ancestor
        row pointing at the real type, and the helper hangs off that. The two
        fixes are coupled -- member C produced 0 new edges on three corpora
        precisely because the aliases people call methods through are
        helper-backed. }
      if Matches.Count = 0 then
        for A in FStore.GetTransitiveAncestors(ATypeSymbolId) do
          if A.Resolved and (A.SymbolId > 0) then AddHelperMethods(A.SymbolId);
    end;

    Result:= PickFromMatches(Matches, AArgCount, AArgsKnown, AConfidence);
  finally
    Matches.Free;
  end;
end;

const
  // A lexical nesting chain deeper than this is not real Delphi. The bound is a
  // backstop against a corrupt parent link in the symbol table turning the climb
  // into an infinite loop over a whole-DB pass, not a modelling limit.
  MAX_LEXICAL_DEPTH = 32;

function TCallResolver.LookupInLexicalScopes(AEnclosingSymbolId: Int64;
  const AName: string; out AConfidence: string): Int64;
var
  ScopeId: Int64          ;
  Scope  : TSymbol        ;
  Parent : TSymbol        ;
  Kids   : TList<TSymbol> ;
  S      : TSymbol        ;
  Matches: TList<TSymbol> ;
  Depth  : Integer        ;
begin
  Result     := 0;
  AConfidence:= '';
  if (AEnclosingSymbolId <= 0) or (AName = '') then Exit;

  ScopeId:= AEnclosingSymbolId;
  Depth  := 0;
  Matches:= TList<TSymbol>.Create;
  try
    while (ScopeId > 0) and (Depth < MAX_LEXICAL_DEPTH) do
    begin
      Inc(Depth);
      Matches.Clear;
      Kids:= ChildrenOf(ScopeId);
      if Kids <> nil then
        for S in Kids do
          if (S.Kind in METHOD_KINDS) and SameText(S.Name, AName) then Matches.Add(S);

      if Matches.Count > 0 then
      begin
        // INNERMOST WINS -- and the walk stops here. Climbing past a level that
        // declares the name is exactly what the compiler does not do, and doing
        // it would make the four YADF.Layout StartsWordCI routines
        // indistinguishable again.
        Result:= Matches[0].Id;
        // Two routine children of ONE scope sharing a name needs `overload` on a
        // local routine. Arity is deliberately not consulted to separate them:
        // B1's arity narrowing is the receiver-typed path's policy, earns its
        // keep on class overload sets, and has no measured case here. One edge,
        // marked uncertain, keeps this narrow until such a case turns up.
        if Matches.Count = 1 then AConfidence:= 'certain' else AConfidence:= 'ambiguous';
        Exit;
      end;

      // Climb one lexical level, but only while the enclosing scope is itself a
      // ROUTINE. A class / record / unit parent ends the chain.
      Scope:= FStore.GetSymbolById(ScopeId);
      if (Scope.Id <= 0) or (Scope.ParentId <= 0) then Exit;
      Parent:= FStore.GetSymbolById(Scope.ParentId);
      if (Parent.Id <= 0) or not (Parent.Kind in METHOD_KINDS) then Exit;
      ScopeId:= Parent.Id;
    end;
  finally
    Matches.Free;
  end;
end;

function TCallResolver.LookupUnitLevelRoutine(ACallFileId: Int64; const AName: string;
  AArgCount: Integer; AArgsKnown: Boolean; out AConfidence: string): Int64;
var
  Cands  : TList<TSymbol>;
  Matches: TList<TSymbol>;
  S      : TSymbol       ;
begin
  Result     := 0;
  AConfidence:= '';
  if (ACallFileId <= 0) or (AName = '') then Exit;
  if not FNameToRoutines.TryGetValue(LowerCase(AName), Cands) then Exit;

  Matches:= TList<TSymbol>.Create;
  try
    // RUNG 1 -- the call's OWN unit. Both sections are visible from inside the
    // unit, and a routine declared here shadows any same-named routine a used
    // unit exports, so this rung answers alone whenever it matches at all.
    for S in Cands do
      if S.FileId = ACallFileId then Matches.Add(S);
    if Matches.Count > 0 then
      Exit(PickFromMatches(Matches, AArgCount, AArgsKnown, AConfidence));

    // RUNG 2 -- units this file USES. Only the INTERFACE section is reachable
    // from another unit; an implementation-section routine is private to its own
    // unit no matter what the uses clause says. CandInScope supplies the uses
    // relation itself, from the same resolved edges receiver typing uses, so a
    // unit that is merely present in the index but not used is never consulted.
    for S in Cands do
      if (S.FileId <> ACallFileId) and SameText(S.Section, 'interface')
         and CandInScope(ACallFileId, S.FileId) then Matches.Add(S);
    Result:= PickFromMatches(Matches, AArgCount, AArgsKnown, AConfidence);
  finally
    Matches.Free;
  end;
end;

{ 2026-09-23 (enum-value-ref-binding) -- the enum-value pass, Shape A.

  Five routines, and they exist because an enum value is the ONE value kind whose
  resolution is purely lexical: a unit scope plus a shadowing rule. That is why a
  targeted pass can be exact where a general `read` resolver -- locals, params,
  fields, globals, `with` scopes, type flow -- could only guess.

  The posture throughout is the resolver's existing one, stated once here rather
  than at every Exit: the answer is `certain` or NOTHING. There is no ambiguous
  value binding, because a wrong refs.symbol_id is exactly the name-match failure
  this binding exists to replace. Losing an edge is the safe direction; every
  decline is counted by reason so that the loss is auditable rather than silent. }

function TCallResolver.LexicalScopeDeclaresValue(AEnclosingSymbolId: Int64;
  const AName: string): Boolean;
var
  Kinds  : TSymbolKindSet;
  ScopeId: Int64         ;
  Scope  : TSymbol       ;
  Parent : TSymbol       ;
  Kids   : TList<TSymbol>;
  S      : TSymbol       ;
  Depth  : Integer       ;
begin
  Result:= False;
  { R4: a ref with no enclosing routine -- unit-level initialisation, a const
    initialiser -- makes this rule vacuous. It is NOT excluded from the pass. }
  if (AEnclosingSymbolId <= 0) or (AName = '') then Exit;
  { METHOD_KINDS is a TYPED constant, so this union cannot itself be a const.
    Computing it once per call keeps METHOD_KINDS the single source of truth
    without paying for the union on every child. }
  Kinds  := METHOD_KINDS + [skLocalVar, skParam, skConstDecl, skVarDecl];
  ScopeId:= AEnclosingSymbolId;
  Depth  := 0;
  while (ScopeId > 0) and (Depth < MAX_LEXICAL_DEPTH) do
  begin
    Inc(Depth);
    Kids:= ChildrenOf(ScopeId);
    if Kids <> nil then
      for S in Kids do
        { Unlike LookupInLexicalScopes this does not care WHICH declaration wins
          or whether the scope is unambiguous -- any same-named one is a reason
          to decline -- so the first hit ends the walk. }
        if (S.Kind in Kinds) and SameText(S.Name, AName) then Exit(True);

    { Climb one lexical level, and only while the enclosing scope is itself a
      ROUTINE. A class / record / unit parent ends the chain -- the same stop
      condition LookupInLexicalScopes uses, and for the same reason: beyond it
      the scope is no longer nearer than the unit. }
    Scope:= FStore.GetSymbolById(ScopeId);
    if (Scope.Id <= 0) or (Scope.ParentId <= 0) then Exit;
    Parent:= FStore.GetSymbolById(Scope.ParentId);
    if (Parent.Id <= 0) or not (Parent.Kind in METHOD_KINDS) then Exit;
    ScopeId:= Parent.Id;
  end;
end;

function TCallResolver.EnclosingClassChainDeclares(AEnclosingSymbolId: Int64;  // dl:ok too-many-exit-points@8c65 -- REVIEWED 2026-09-23: all seven exits ARE the guard clauses the rule's own remedy asks for. Three end the climb (no symbol, no parent, no owning type) and four are independent shadow hits -- member, own const/var/method, ancestor const/var/method. Routing them through one exit needs a result variable plus a found flag, which is precisely what makes a decline path unreadable in a routine whose whole job is to decline.
  const AName: string; out AClassId: Int64): Boolean;
var
  Kinds  : TSymbolKindSet;
  ScopeId: Int64         ;
  Scope  : TSymbol       ;
  Parent : TSymbol       ;
  Depth  : Integer       ;
  A      : TTypeAncestor ;
begin
  Result  := False;
  AClassId:= 0;
  if AEnclosingSymbolId <= 0 then Exit; // R4: vacuous

  { Climb to the OUTERMOST enclosing routine and take ITS owner. TypeReceiver's
    kind-1 logic takes the enclosing symbol's ParentId in one hop, which is right
    for a method but answers a ROUTINE -- not a class -- for any ref inside a
    nested routine, and those refs are in scope of the owning class all the same. }
  ScopeId:= AEnclosingSymbolId;
  Depth  := 0;
  while Depth < MAX_LEXICAL_DEPTH do
  begin
    Inc(Depth);
    Scope:= FStore.GetSymbolById(ScopeId);
    if (Scope.Id <= 0) or (Scope.ParentId <= 0) then Exit;
    Parent:= FStore.GetSymbolById(Scope.ParentId);
    if Parent.Id <= 0 then Exit;
    if not (Parent.Kind in METHOD_KINDS) then
    begin
      if Parent.Kind in TYPE_KINDS then AClassId:= Parent.Id;
      Break;
    end;
    ScopeId:= Parent.Id;
  end;
  { AClassId is set whatever the answer below: the nested-enum visibility test in
    ResolveEnumValueRead needs the class even when nothing is shadowed. }
  if (AClassId <= 0) or (AName = '') then Exit;

  // Properties and fields, own type then resolved ancestors, in one call.
  if LookupMemberOnType(AClassId, AName).Id > 0 then Exit(True);
  // Class constants, class vars and methods, which LookupMemberOnType excludes.
  Kinds:= METHOD_KINDS + [skConstDecl, skVarDecl];
  if FindChildOfKind(AClassId, AName, Kinds, False).Id > 0 then Exit(True);
  for A in FStore.GetTransitiveAncestors(AClassId) do
    if A.Resolved and (A.SymbolId > 0)
       and (FindChildOfKind(A.SymbolId, AName, Kinds, False).Id > 0) then Exit(True);
end;

function TCallResolver.UnitNameToFileId(const AReceiver: string): Int64;
var
  S    : TSymbol;
  Found: Int64  ;
  Hits : Integer;
begin
  Result:= 0;
  if AReceiver = '' then Exit;
  Found := 0;
  Hits  := 0;
  { FindSymbolsByExactName already handles a DOTTED unit name verbatim -- a
    unit's symbols.name carries its dots -- so 'DRagLint.Doc.Document' matches
    without being split. Two units of one name is a decline, not a pick: the
    whole point of this rung is that the source qualified the value, and a
    receiver that names two units qualifies nothing. }
  for S in FStore.FindSymbolsByExactName(AReceiver) do
    if S.Kind = skUnit then
    begin
      Inc(Hits);
      Found:= S.FileId;
    end;
  if Hits = 1 then Result:= Found;
end;

function TCallResolver.CollapseIdenticalEnumCopies(const AVisible: TArray<TEnumValueDecl>;
  ARefFileId: Int64): TArray<TEnumValueDecl>;

  { 0 = the referencing file's own copy, 1 = a copy that file can see through the
    uses graph, 2 = neither. Lower wins; ties go to the lowest id, so the choice
    is stable across runs rather than dependent on row order.

    This ordering differs DELIBERATELY from CollapseIdenticalCopies' own-file-
    then-lowest-id. That rule feeds candidate scoring over textual uses names;
    this one feeds a visibility test built on FILE-ID uses edges, so a lowest-id
    twin that is not the uses target would be carried forward and then declined
    as not visible -- losing an edge the index plainly holds. }
  function Rank(const AE: TEnumValueDecl): Integer;
  begin
    if ARefFileId <= 0 then Exit(2);
    if AE.FileId = ARefFileId then Exit(0);
    if CandInScope(ARefFileId, AE.FileId) then Exit(1);
    Result:= 2;
  end;

var
  Groups : TObjectDictionary<string, TList<Integer>>;
  Keep   : TList<Integer>;
  Grp    : TList<Integer>;
  Key    : string        ;
  I, J   : Integer       ;
  Same   : Boolean       ;
  Rep    : Integer       ;
  RepRank: Integer       ;
  R      : Integer       ;
begin
  Result:= AVisible;
  if Length(AVisible) < 2 then Exit;
  Groups:= TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  Keep  := TList<Integer>.Create;
  try
    for I:= 0 to High(AVisible) do
    begin
      Key:= LowerCase(AVisible[I].QualifiedName);
      if not Groups.TryGetValue(Key, Grp) then
      begin
        Grp:= TList<Integer>.Create;
        Groups.Add(Key, Grp);
      end;
      Grp.Add(I);
    end;
    for Grp in Groups.Values do
    begin
      if Grp.Count = 1 then
      begin
        Keep.Add(Grp[0]);
        Continue;
      end;
      { THE DISCRIMINATOR IS CONTENT, NOT IDENTITY -- the same rule
        CollapseIdenticalCopies applies to types. Identical spans mean one
        declaration the index reached by two paths; anything else is two
        declarations that happen to share a qualified name. }
      Same:= True;
      for J:= 1 to Grp.Count - 1 do
        if (AVisible[Grp[J]].StartLine <> AVisible[Grp[0]].StartLine)
           or (AVisible[Grp[J]].EndLine <> AVisible[Grp[0]].EndLine) then
        begin
          Same:= False;
          Break;
        end;
      if not Same then
      begin
        { Keep every member, so R2 still sees the real ambiguity and declines.
          This is what stops rule 0 degrading into "take the first candidate". }
        for J:= 0 to Grp.Count - 1 do Keep.Add(Grp[J]);
        Continue;
      end;
      Rep    := Grp[0];
      RepRank:= Rank(AVisible[Rep]);
      for J:= 1 to Grp.Count - 1 do
      begin
        R:= Rank(AVisible[Grp[J]]);
        if (R < RepRank) or ((R = RepRank) and (AVisible[Grp[J]].Id < AVisible[Rep].Id)) then
        begin
          Rep    := Grp[J];
          RepRank:= R;
        end;
      end;
      Keep.Add(Rep);
      Inc(FEnumStats.DupGroupsCollapsed);
    end;
    { DECISIVE IS COUNTED HERE, NOT AT A CALL SITE, and that is a fix rather than
      a preference. It was incremented only on the bare-read path while THIS
      routine -- which rung 3c also calls for a `Unit.value` receiver --
      incremented DupGroupsCollapsed for both. A 3c fold that turned two
      identical copies into one and produced a binding therefore counted as
      collapsed but not as decisive, which made TEnumResolveStats' documented
      meaning ("the folds that turned >1 candidate into exactly 1") untrue for
      that path. Owner ruling 4 made these counters the AUDIT of a decision taken
      WITHOUT measuring first, so a counter that is wrong across shapes defeats
      the ruling. One site, every caller, cannot drift apart again. }
    if (Length(AVisible) > 1) and (Keep.Count = 1) then Inc(FEnumStats.CollapseDecisive);
    { Restore the caller's original ordering. Nothing downstream settles a tie by
      order, but a stable output keeps the counters and logs comparable run to
      run. }
    Keep.Sort;
    SetLength(Result, Keep.Count);
    for I:= 0 to Keep.Count - 1 do Result[I]:= AVisible[Keep[I]];
  finally
    Keep.Free;
    Groups.Free;
  end;
end;

function TCallResolver.ResolveEnumValueRead(const ARef: TReference; out AReason: string): Int64;  // dl:ok too-many-exit-points@5ca2 -- REVIEWED 2026-09-23: each exit is a DISTINCT outcome the caller and the counters must tell apart -- not a candidate name, not visible, ambiguous, shadowed (a/b), shadowed (c), bound. Every one sets AReason and increments its own counter before leaving; merging them behind a single exit would put six reasons through one assignment and is exactly how a decline becomes unauditable.

  { R1: a value declared in AFileId / ASection is visible from ARef's file when
    it is the SAME file (both sections of one's own unit are in scope), or it is
    an INTERFACE declaration of a unit this file directly uses. An
    implementation-section declaration of another unit is never visible.
    CandInScope supplies the uses relation from the same resolved edges receiver
    typing uses, so a unit merely present in the index is never consulted. }
  function VisibleHere(AFileId: Int64; const ASection: string): Boolean;
  begin
    Result:= (AFileId = ARef.FileId)
             or (SameText(ASection, 'interface') and CandInScope(ARef.FileId, AFileId));
  end;

  { R3(c) over one shadow map: True when ANY same-named symbol in it is visible
    under the same R1 rule. Both shadow arms therefore apply ONE visibility rule
    rather than two that can drift apart. }
  function AnyVisibleIn(AMap: TObjectDictionary<string, TList<TSymbol>>;
    const ALc: string): Boolean;
  var
    L: TList<TSymbol>;
    S: TSymbol       ;
  begin
    Result:= False;
    if not AMap.TryGetValue(ALc, L) then Exit;
    for S in L do
      if VisibleHere(S.FileId, S.Section) then Exit(True);
  end;

var
  Lc          : string                 ;
  Cands       : TList<TEnumValueDecl>  ;
  Visible     : TArray<TEnumValueDecl> ;
  E           : TEnumValueDecl         ;
  A           : TTypeAncestor          ;
  ClassId     : Int64                  ;
  ClassShadows: Boolean                ;
  OwnerOk     : Boolean                ;
begin
  Result := 0;
  AReason:= '';
  if ARef.NameText = '' then Exit;
  Lc:= LowerCase(ARef.NameText);
  { Not a candidate name, and NOT counted as a decline: the store's candidate SQL
    already filtered the stream to enum-value names, so reaching here means the
    caller asked about a ref that was never a candidate. }
  if not FNameToEnumValues.TryGetValue(Lc, Cands) then Exit;

  { The enclosing class is needed TWICE -- by the nested-enum visibility test
    below and by R3(b) -- and finding it costs two GetSymbolById per lexical
    level, so it is walked once here and both answers kept. }
  ClassShadows:= EnclosingClassChainDeclares(ARef.EnclosingSymbolId, ARef.NameText, ClassId);

  { --- R1 visibility, plus the nested-enum rule (plan ruling 4). A value whose
    enum is declared INSIDE a type is reachable by its BARE name only from that
    type or a descendant of it; treating such a value as unit-scoped is how a
    bare identifier binds to a declaration the compiler would not have seen. }
  Visible:= nil;
  for var C: TEnumValueDecl in Cands do
  begin
    if not VisibleHere(C.FileId, C.Section) then Continue;
    if C.OwnerTypeId > 0 then
    begin
      OwnerOk:= (ClassId > 0) and (ClassId = C.OwnerTypeId);
      if not OwnerOk and (ClassId > 0) then
        for A in FStore.GetTransitiveAncestors(ClassId) do
          if A.Resolved and (A.SymbolId = C.OwnerTypeId) then
          begin
            OwnerOk:= True;
            Break;
          end;
      if not OwnerOk then Continue;
    end;
    Visible:= Visible + [C];
  end;

  { --- rule 0 (owner ruling 4, 2026-09-23). One declaration the index holds
    twice is not an ambiguity, and declining it would lose a real edge for an
    artefact of indexing. Counted rather than silent so the ruling -- taken
    without a prior measurement, by the owner's own note -- stays auditable. }
  Visible:= CollapseIdenticalEnumCopies(Visible, ARef.FileId);

  { --- R2 uniqueness. Zero and many are both declines, counted APART: an
    over-strict visibility rule and a genuine name clash are different defects
    and would otherwise be indistinguishable from the totals. Delphi settles a
    tie between two used units by uses-clause ORDER; this engine does not model
    that order and must not pretend to. }
  if Length(Visible) = 0 then
  begin
    AReason:= 'not-visible';
    Inc(FEnumStats.NotVisible);
    Exit;
  end;
  if Length(Visible) > 1 then
  begin
    AReason:= 'ambiguous';
    Inc(FEnumStats.Ambiguous);
    Exit;
  end;
  E:= Visible[0];

  { --- R3 shadowing. ANY same-named declaration in a nearer or the SAME scope
    ends it: the compiler resolves the identifier to that declaration, not to the
    enum value, so binding here would write a wrong `certain` fact. }
  if LexicalScopeDeclaresValue(ARef.EnclosingSymbolId, ARef.NameText) { (a) }
     or ClassShadows then                                            { (b) }
  begin
    AReason:= 'shadowed';
    Inc(FEnumStats.Shadowed);
    Exit;
  end;
  { (c) unit scope: a unit-level const/var, a free routine, or a TYPE spelled
    like the value. FNameToCands holds class/interface/record/type/enum symbols
    and never enum_value (GetTypeCandidates' own WHERE), so a value can never
    shadow ITSELF here. A type ALIAS spelled like the value does decline, and
    that is intended -- the identifier is genuinely ambiguous to a reader. }
  if AnyVisibleIn(FNameToUnitValues, Lc)
     or AnyVisibleIn(FNameToRoutines, Lc)
     or AnyVisibleIn(FNameToCands   , Lc) then
  begin
    AReason:= 'shadowed';
    Inc(FEnumStats.Shadowed);
    Exit;
  end;

  Result:= E.Id;
  Inc(FEnumStats.Bound);
end;

{ 2026-09-23 (parenless-call binding, resolver 1.7.0-alpha) -- defect D1.

  Delphi lets a routine with no required parameters be called WITHOUT
  parentheses. In statement position (`NextId;`) the parser records a `call` ref
  and the main stream resolves it. In EXPRESSION position -- `Assert(NextId > 0)`,
  `N := NextId`, `Consume(NextId)`, a bare `Tick` inside its own class -- it
  records a `read` ref, and until this pass the calls stage never looked at one.
  So none of those sites owned a call_edges row, and every call-based consumer
  (assert-with-side-effect, the purity callee walk, find-callers --resolved, the
  who-calls charts) missed them. Measured on ORM3 CLIENT at resolver 1.6.0:
  1,715 such unbound reads over 59 routine names.

  The layer is the RESOLVER, not the extractor: the ref already carries its name,
  position and enclosing routine. What was missing is the decision "is this read
  a call?", and these routines make it with the posture the rest of this unit
  takes -- an edge, or NOTHING, with every refusal counted by reason. }

{ The RETURN type text of a stored routine signature: the text after the colon
  that follows the (optional) parameter list. '' for a procedure, a constructor,
  or a shape this does not recognise. }
function SignatureReturnType(const ASignature: string): string;
var
  Rest : string ;
  Depth: Integer;
  K    : Integer;
  InStr: Boolean;
begin
  Result:= '';
  Rest  := TrimLeft(ASignature);
  if (Rest <> '') and (Rest[1] = '(') then
  begin
    Depth:= 0;
    InStr:= False;
    for K:= 1 to Length(Rest) do
    begin
      if InStr then
        InStr:= Rest[K] <> ''''
      else if Rest[K] = '''' then
        InStr:= True
      else if Rest[K] = '(' then
        Inc(Depth)
      else if Rest[K] = ')' then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          Rest:= TrimLeft(Copy(Rest, K + 1, MaxInt));
          Break;
        end;
      end;
    end;
    if Depth <> 0 then Exit;
  end;
  if (Rest = '') or (Rest[1] <> ':') then Exit;
  Rest:= Trim(Copy(Rest, 2, MaxInt));
  K   := Pos(';', Rest);
  if K > 0 then Rest:= Trim(Copy(Rest, 1, K - 1));
  Result:= Rest;
end;

{ The declared TYPE text of the AIndex-th (0-based) parameter of a stored
  signature. '' when there is no such parameter, it is untyped, or the
  signature has no parameter list. Groups are split at top-level ';', names at
  ','; the type is the text after the group's ':' up to any default. }
function ParamTypeAt(const ASignature: string; AIndex: Integer): string;
var
  Open  : Integer;
  Depth : Integer;
  K     : Integer;
  Start : Integer;
  InStr : Boolean;
  Group : string ;
  Colon : Integer;
  Count : Integer;
  Remain: Integer;

  { One parameter group: consume its names from Remain; when the wanted index
    falls inside it, answer the group's type. }
  function TakeGroup(const AGroup: string): Boolean;
  var
    TypeText: string ;
    Eq      : Integer;
  begin
    Colon:= Pos(':', AGroup);
    if Colon > 0 then Count:= Length(SplitString(Copy(AGroup, 1, Colon - 1), ','))
    else Count:= Length(SplitString(AGroup, ','));
    Result:= Remain < Count;
    if not Result then
    begin
      Dec(Remain, Count);
      Exit;
    end;
    if Colon = 0 then Exit;
    TypeText:= Copy(AGroup, Colon + 1, MaxInt);
    Eq      := Pos('=', TypeText);
    if Eq > 0 then TypeText:= Copy(TypeText, 1, Eq - 1);
    ParamTypeAt:= Trim(TypeText);
  end;

begin
  Result:= '';
  Open  := Pos('(', ASignature);
  if (Open = 0) or (AIndex < 0) then Exit;
  Remain:= AIndex;
  Depth := 0;
  InStr := False;
  Start := Open + 1;
  for K:= Open to Length(ASignature) do
  begin
    if InStr then
    begin
      InStr:= ASignature[K] <> '''';
      Continue;
    end;
    case ASignature[K] of
      '''': InStr:= True;
      '(', '[': Inc(Depth);
      ']': Dec(Depth);
      ')', ';':
        begin
          if ASignature[K] = ')' then Dec(Depth);
          if (Depth = 0) or ((Depth = 1) and (ASignature[K] = ';')) then
          begin
            Group:= Copy(ASignature, Start, K - Start);
            Start:= K + 1;
            if (Trim(Group) <> '') and TakeGroup(Group) then Exit;
            if Depth = 0 then Exit;
          end;
        end;
    end;
  end;
end;

{ True for a routine a parenless read may CALL: a function (unit-level or a
  method with a return type) that accepts zero arguments. A procedure named
  bare in an expression cannot be a call, and a routine that needs an argument
  can only be a procedure value there. }
function IsParenlessCallable(const ASym: TSymbol): Boolean;
var
  Lo, Hi: Integer;
begin
  Result:= (ASym.Kind in [skFunction, skMethod])
           and (SignatureReturnType(ASym.Signature) <> '')
           and SignatureArityRange(ASym.Signature, Lo, Hi)
           and (Lo = 0);
end;

{ True when AText begins with the keyword AWord followed by a non-identifier
  character or the end -- so 'function: Integer' matches 'function' and
  'FunctionList' does not. AText must already be lowercased. }
function StartsWithWord(const AText, AWord: string): Boolean;
begin
  Result:= StartsStr(AWord, AText)
           and ((Length(AText) = Length(AWord)) or not IsIdentPart(AText[Length(AWord) + 1]));
end;

{ True when AAfter -- the rest of a line after an identifier -- ends the
  statement there: nothing, `;`, a comment, or `end` / `else`. }
function EndsStatement(const AAfter: string): Boolean;
var
  L: string;
begin
  L     := LowerCase(AAfter);
  Result:= (L = '') or StartsStr(';', L) or StartsStr('//', L) or StartsStr('{', L) or StartsStr('(*', L);
  Result:= Result or StartsWithWord(L, 'end') or StartsWithWord(L, 'else');
end;

{ True when a declaration's type text is itself a procedural type. }
function IsProceduralText(const AText: string): Boolean;
var
  L: string;
begin
  L:= LowerCase(Trim(AText));
  Result:= StartsWithWord(L, 'procedure') or StartsWithWord(L, 'function')
           or StartsStr('reference to', L) or StartsStr('tfunc<', L);
end;

// One line of a `with` scan. AInBrace / AInStar carry an open brace or
// paren-star comment across lines; a // comment ends the line; string literals
// are skipped. True when the keyword `with` occurs outside all of them.
function LineHasWithKeyword(const ALine: string; var AInBrace, AInStar: Boolean): Boolean;

  { True when ALine[K] opens the two-character token ATwo. }
  function OpensPair(K: Integer; const ATwo: string): Boolean;
  begin
    Result:= (K < Length(ALine)) and (ALine[K] = ATwo[1]) and (ALine[K + 1] = ATwo[2]);
  end;

  { Consumes ALine[K] when it is comment or string text, or opens either,
    advancing K past what it consumed. False leaves K untouched. }
  function SkipNonCode(var K: Integer): Boolean;
  begin
    Result:= True;
    if AInBrace then
      AInBrace:= ALine[K] <> '}'
    else if AInStar then
    begin
      AInStar:= not OpensPair(K, '*)');
      if not AInStar then Inc(K);
    end
    else if ALine[K] = '{' then
      AInBrace:= True
    else if OpensPair(K, '(*') then
    begin
      AInStar:= True;
      Inc(K);
    end
    else if ALine[K] = '''' then
    begin
      Inc(K);
      while (K <= Length(ALine)) and (ALine[K] <> '''') do Inc(K);
    end
    else
      Result:= False;
    if Result then Inc(K);
  end;

var
  K, W: Integer;
begin
  Result:= False;
  K     := 1;
  while (K <= Length(ALine)) and not Result and not OpensPair(K, '//') do
    if not SkipNonCode(K) then
    begin
      W:= K;
      while (K <= Length(ALine)) and IsIdentPart(ALine[K]) do Inc(K);
      if K = W then
        Inc(K) { not an identifier character: step over it }
      else
        Result:= IsIdentStart(ALine[W]) and SameText(Copy(ALine, W, K - W), 'with');
    end;
end;

{ Scans ABefore -- a line up to a read ref standing as a whole argument --
  right to left for the bracket that opens its argument list. AOpenCol receives
  that bracket's 1-based column and AArgIndex the ref's 0-based argument
  position. False when no bracket opens on this line, or when it is a `[`: a set
  or open-array constructor takes values, never procedures. }
function FindArgumentListOpen(const ABefore: string; out AOpenCol, AArgIndex: Integer): Boolean;
var
  K, Depth: Integer;
begin
  Result   := False;
  AOpenCol := 0;
  AArgIndex:= 0;
  Depth    := 0;
  K        := Length(ABefore);
  while (K >= 1) and (AOpenCol = 0) do
  begin
    case ABefore[K] of
      '''':
        begin
          Dec(K);
          while (K >= 1) and (ABefore[K] <> '''') do Dec(K);
        end;
      ')', ']': Inc(Depth);
      '(', '[':
        if Depth > 0 then Dec(Depth)
        else
        begin
          AOpenCol:= K;
          Result  := ABefore[K] = '(';
        end;
      ',': if Depth = 0 then Inc(AArgIndex);
    end;
    Dec(K);
  end;
end;

function TCallResolver.LexicalParenlessLookup(AEnclosingSymbolId: Int64;
  const AName: string; AMatches: TList<TSymbol>; out AValue: TSymbol): Boolean;
var
  ValueKinds: TSymbolKindSet;
  Found     : TList<TSymbol>;
  ScopeId   : Int64         ;
  Scope     : TSymbol       ;
  Kids      : TList<TSymbol>;
  S         : TSymbol       ;
  Depth     : Integer       ;
begin
  AValue    := Default(TSymbol);
  ValueKinds:= [skLocalVar, skParam, skConstDecl, skVarDecl];
  ScopeId   := AEnclosingSymbolId;
  Depth     := 0;
  Found     := TList<TSymbol>.Create;
  try
    while (ScopeId > 0) and (Depth < MAX_LEXICAL_DEPTH) and (Found.Count = 0) and (AValue.Id = 0) do
    begin
      Inc(Depth);
      Kids:= ChildrenOf(ScopeId);
      if Kids <> nil then
        for S in Kids do
          if SameText(S.Name, AName) and (S.Kind in ValueKinds) then AValue:= S
          else if SameText(S.Name, AName) and (S.Kind in METHOD_KINDS) then Found.Add(S);
      { Climb only while the enclosing scope is itself a routine -- the stop
        condition LookupInLexicalScopes uses. }
      Scope:= FStore.GetSymbolById(ScopeId);
      ScopeId:= 0;
      if (Scope.Id > 0) and (Scope.ParentId > 0)
         and (FStore.GetSymbolById(Scope.ParentId).Kind in METHOD_KINDS) then ScopeId:= Scope.ParentId;
    end;
    { A level declaring BOTH a value and a routine of one name is not legal
      Delphi; should the index say so anyway, the value wins and nothing is
      offered as a call target. }
    Result:= AValue.Id > 0;
    if not Result then AMatches.AddRange(Found);
  finally
    Found.Free;
  end;
end;

procedure TCallResolver.AddMethodsOnTypeChain(ATypeId: Int64; const AName: string;
  AMatches: TList<TSymbol>);
var
  A: TTypeAncestor;

  procedure AddFrom(AOwnerId: Int64);
  var
    Kids: TList<TSymbol>;
    S   : TSymbol       ;
  begin
    Kids:= ChildrenOf(AOwnerId);
    if Kids <> nil then
      for S in Kids do
        if (S.Kind in METHOD_KINDS) and SameText(S.Name, AName) then AMatches.Add(S);
  end;

begin
  if ATypeId <= 0 then Exit;
  AddFrom(ATypeId);
  for A in FStore.GetTransitiveAncestors(ATypeId) do
    if A.Resolved and (A.SymbolId > 0) then AddFrom(A.SymbolId);
end;

function TCallResolver.ClassChainParenlessLookup(AClassId: Int64; const AName: string;
  AMatches: TList<TSymbol>): Boolean;
var
  Kinds: TSymbolKindSet;
  A    : TTypeAncestor ;
begin
  Kinds := [skConstDecl, skVarDecl];
  { Properties and fields, own type then ancestors, in one call; then class
    constants and class vars, which LookupMemberOnType excludes. }
  Result:= (LookupMemberOnType(AClassId, AName).Id > 0)
           or (FindChildOfKind(AClassId, AName, Kinds, False).Id > 0);
  if not Result then
    for A in FStore.GetTransitiveAncestors(AClassId) do
      if A.Resolved and (A.SymbolId > 0)
         and (FindChildOfKind(A.SymbolId, AName, Kinds, False).Id > 0) then Result:= True;
  if not Result then AddMethodsOnTypeChain(AClassId, AName, AMatches);
end;

function TCallResolver.UnitScopeDeclaresValue(ARefFileId: Int64; const ALc: string): Boolean;

  { R1 of the enum binding, verbatim: the own unit sees both sections, another
    unit only its interface, and only when this file uses it. }
  function Visible(AFileId: Int64; const ASection: string): Boolean;
  begin
    Result:= (AFileId = ARefFileId)
             or (SameText(ASection, 'interface') and CandInScope(ARefFileId, AFileId));
  end;

var
  L: TList<TSymbol>       ;
  E: TList<TEnumValueDecl>;
  S: TSymbol              ;
  V: TEnumValueDecl       ;
begin
  Result:= False;
  if FNameToUnitValues.TryGetValue(ALc, L) then
    for S in L do Result:= Result or Visible(S.FileId, S.Section);
  if not Result and FNameToCands.TryGetValue(ALc, L) then
    for S in L do Result:= Result or Visible(S.FileId, S.Section);
  if not Result and FNameToEnumValues.TryGetValue(ALc, E) then
    for V in E do Result:= Result or Visible(V.FileId, V.Section);
end;

procedure TCallResolver.AddVisibleUnitRoutines(ARefFileId: Int64; const ALc: string;
  AMatches: TList<TSymbol>);
var
  Cands : TList<TSymbol>;
  S     : TSymbol       ;
  Before: Integer       ;
begin
  if not FNameToRoutines.TryGetValue(ALc, Cands) then Exit;
  Before:= AMatches.Count;
  { RUNG 1 -- the ref's own unit, which shadows anything a used unit exports. }
  for S in Cands do
    if S.FileId = ARefFileId then AMatches.Add(S);
  if AMatches.Count > Before then Exit;
  { RUNG 2 -- the interface of a unit this file uses. }
  for S in Cands do
    if SameText(S.Section, 'interface') and CandInScope(ARefFileId, S.FileId) then AMatches.Add(S);
end;

function TCallResolver.FindParenlessCandidates(const ARef: TReference; const AReceiver: string;
  AMatches: TList<TSymbol>): string;
var
  ClassId: Int64  ;
  Value  : TSymbol;
  Lc     : string ;
begin
  Result:= '';
  Lc    := LowerCase(ARef.NameText);
  { 1. Lexical scopes -- a bare name only; `Self.Name` names a member. }
  if (AReceiver = '') and LexicalParenlessLookup(ARef.EnclosingSymbolId, ARef.NameText, AMatches, Value) then
    Result:= 'shadowed';
  { 2. The enclosing class and its ancestors (the outermost routine's owner, so
    a nested routine inside a method is in the class's scope too). }
  if (Result = '') and (AMatches.Count = 0) then
  begin
    EnclosingClassChainDeclares(ARef.EnclosingSymbolId, '', ClassId);
    if (ClassId > 0) and ClassChainParenlessLookup(ClassId, ARef.NameText, AMatches) then
      Result:= 'shadowed';
  end;
  { 3. The unit, then the interfaces of the units it uses. A value spelled like
    the routine anywhere visible declines -- Delphi settles such a clash by
    uses-clause ORDER, which this engine does not model. }
  if (Result = '') and (AMatches.Count = 0) then
  begin
    if AReceiver <> '' then Result:= 'not-found'
    else if UnitScopeDeclaresValue(ARef.FileId, Lc) then Result:= 'shadowed'
    else AddVisibleUnitRoutines(ARef.FileId, Lc, AMatches);
  end;
  if (Result = '') and (AMatches.Count = 0) then Result:= 'not-found';
end;

function TCallResolver.EnclosingBodyUsesWith(const ARef: TReference; ALines: TStringList): Boolean;
const
  { When the routine's own first line is unknown, scan this far back instead --
    a bound, not a model: a longer routine can only produce a false decline. }
  FALLBACK_SCAN_LINES = 400;
var
  Encl   : TSymbol;
  From   : Integer;
  Ln     : Integer;
  S      : string ;
  InBrace: Boolean;
  InStar : Boolean;
begin
  Result:= False;
  if ARef.EnclosingSymbolId <= 0 then Exit;
  Encl:= FStore.GetSymbolById(ARef.EnclosingSymbolId);
  From:= (if Encl.ImplStartLine > 0 then Encl.ImplStartLine else Encl.StartLine);
  if (From <= 0) or (From > ARef.StartLine) then From:= Max(1, ARef.StartLine - FALLBACK_SCAN_LINES);
  InBrace:= False;
  InStar := False;
  Ln     := From;
  while (Ln <= ARef.StartLine) and (Ln <= ALines.Count) and not Result do
  begin
    S:= ALines[Ln - 1];
    if Ln = ARef.StartLine then S:= Copy(S, 1, ARef.StartCol - 1);
    Result:= LineHasWithKeyword(S, InBrace, InStar);
    Inc(Ln);
  end;
end;

function TCallResolver.IsProceduralTypeText(const ATypeText: string; AFileId: Int64): Boolean;
var
  Id: Int64;
  S : TSymbol;
begin
  Result:= IsProceduralText(ATypeText);
  if Result or (Trim(ATypeText) = '') then Exit;
  Id:= ResolveTypeNameToSymbol(ATypeText, AFileId);
  if Id <= 0 then Exit;
  S     := FStore.GetSymbolById(Id);
  Result:= (S.Kind = skTypeAlias) and IsProceduralText(S.Signature);
end;

function TCallResolver.AssignedTypeText(const ARef: TReference; const ALine, ALhs: string): string;
var
  Lhs      : string ;
  LeafStart: Integer;
  Leaf     : string ;
  Rcv      : string ;
  ClassId  : Int64  ;
  S        : TSymbol;
  Scratch  : TList<TSymbol>;
begin
  Result   := '';
  Lhs      := TrimRight(ALhs);
  LeafStart:= Length(Lhs);
  while (LeafStart >= 1) and IsIdentPart(Lhs[LeafStart]) do Dec(LeafStart);
  Inc(LeafStart);
  Leaf:= Copy(Lhs, LeafStart, MaxInt);
  if (Leaf = '') or not IsIdentStart(Leaf[1]) then Exit;
  { Lhs is a prefix of ALine, so LeafStart is the leaf's column in ALine too. }
  Rcv:= ExtractReceiverExpr(ALine, LeafStart);
  if Rcv <> '' then
    Result:= LookupMemberOnType(TypeReceiver(ARef, Rcv), Leaf).Signature
  else if SameText(Leaf, 'Result') then
    Result:= SignatureReturnType(FStore.GetSymbolById(ARef.EnclosingSymbolId).Signature)
  else
  begin
    Scratch:= TList<TSymbol>.Create;
    try
      if LexicalParenlessLookup(ARef.EnclosingSymbolId, Leaf, Scratch, S) then Result:= S.Signature;
    finally
      Scratch.Free;
    end;
    if Result = '' then
    begin
      EnclosingClassChainDeclares(ARef.EnclosingSymbolId, '', ClassId);
      if ClassId > 0 then Result:= LookupMemberOnType(ClassId, Leaf).Signature;
    end;
    if (Result = '') and FNameToUnitValues.ContainsKey(LowerCase(Leaf)) then
      for S in FNameToUnitValues[LowerCase(Leaf)] do
        if (Result = '') and ((S.FileId = ARef.FileId)
           or (SameText(S.Section, 'interface') and CandInScope(ARef.FileId, S.FileId))) then
          Result:= S.Signature;
  end;
end;

function TCallResolver.CalleeTakesProcedural(const ARef: TReference; const ALine: string;
  AOpenCol, AArgIndex: Integer; const AResultType: string): Boolean;
var
  NameEnd  : Integer;
  NameStart: Integer;
  Callee   : string ;
  Rcv      : string ;
  ClassId  : Int64  ;
  Cands    : TList<TSymbol>;
  Value    : TSymbol;
  C        : TSymbol;
  PType    : string ;
begin
  Result := False;
  NameEnd:= AOpenCol - 1;
  while (NameEnd >= 1) and CharInSet(ALine[NameEnd], [' ', #9]) do Dec(NameEnd);
  NameStart:= NameEnd;
  while (NameStart >= 1) and IsIdentPart(ALine[NameStart]) do Dec(NameStart);
  Inc(NameStart);
  Callee:= Copy(ALine, NameStart, NameEnd - NameStart + 1);
  { A keyword or a bare `(` groups an expression; nothing here is a callee, and
    no routine in the index is named `if`, so the lookup below finds nothing. }
  if (Callee = '') or not IsIdentStart(Callee[1]) then Exit;
  Rcv  := ExtractReceiverExpr(ALine, NameStart);
  Cands:= TList<TSymbol>.Create;
  try
    { EVERY candidate the name could reach, not just the one a call ref would
      pick: one procedural parameter among an overload set is enough doubt. }
    if Rcv = '' then
    begin
      LexicalParenlessLookup(ARef.EnclosingSymbolId, Callee, Cands, Value);
      EnclosingClassChainDeclares(ARef.EnclosingSymbolId, '', ClassId);
      AddMethodsOnTypeChain(ClassId, Callee, Cands);
      AddVisibleUnitRoutines(ARef.FileId, LowerCase(Callee), Cands);
    end
    else
      AddMethodsOnTypeChain(TypeReceiver(ARef, Rcv), Callee, Cands);
    for C in Cands do
    begin
      PType:= ParamTypeAt(C.Signature, AArgIndex);
      if (PType <> '') and not SameText(PType, AResultType)
         and IsProceduralTypeText(PType, C.FileId) then Result:= True;
    end;
  finally
    Cands.Free;
  end;
end;

function TCallResolver.ParenlessIsProcValue(const ARef: TReference; const ALine, AReceiver,
  AResultType: string): Boolean;
var
  Before  : string ;
  After   : string ;
  LhsType : string ;
  OpenCol : Integer;
  ArgIndex: Integer;
  WholeArg: Boolean;
begin
  Before:= TrimRight(Copy(ALine, 1, ARef.StartCol - 1));
  if AReceiver <> '' then
  begin
    { `Self.Name`: the expression starts at the receiver. }
    if EndsStr('.', Before) then Before:= TrimRight(Copy(Before, 1, Length(Before) - 1));
    if EndsText(AReceiver, Before) then Before:= TrimRight(Copy(Before, 1, Length(Before) - Length(AReceiver)));
  end;
  After:= TrimLeft(Copy(ALine, ARef.StartCol + Length(ARef.NameText), MaxInt));

  if EndsStr('@', Before) then
    Result:= True { the ADDRESS of the routine }
  else if EndsStr(':=', Before) and EndsStatement(After) then
  begin
    { The WHOLE right side of an assignment: a call when the target holds a
      value, the routine's address when the target is procedural. A target of
      exactly the routine's return type takes the result, even when that type
      is itself procedural. }
    LhsType:= AssignedTypeText(ARef, ALine, Copy(Before, 1, Length(Before) - 2));
    Result := (LhsType <> '') and not SameText(LhsType, AResultType)
              and IsProceduralTypeText(LhsType, ARef.FileId);
  end
  else
  begin
    { A WHOLE argument: the callee's parameter type decides the same way. }
    WholeArg:= (EndsStr('(', Before) or EndsStr(',', Before))
               and (StartsStr(')', After) or StartsStr(',', After));
    Result  := WholeArg and FindArgumentListOpen(Before, OpenCol, ArgIndex)
               and CalleeTakesProcedural(ARef, ALine, OpenCol, ArgIndex, AResultType);
  end;
end;

procedure TCallResolver.TallyParenless(const AReason: string);
begin
  if AReason = '' then Inc(FParenlessStats.Bound)
  else if AReason = 'not-found' then Inc(FParenlessStats.NotFound)
  else if AReason = 'shadowed' then Inc(FParenlessStats.Shadowed)
  else if AReason = 'not-callable' then Inc(FParenlessStats.NotCallable)
  else if AReason = 'proc-value' then Inc(FParenlessStats.ProcValue)
  else if AReason = 'with-scope' then Inc(FParenlessStats.WithScope)
  else if AReason = 'qualified' then Inc(FParenlessStats.Qualified)
  else Inc(FParenlessStats.Unreadable);
end;

function TCallResolver.ResolveParenlessRead(const ARef: TReference; out AReason: string): TCallEdge;
var
  Lines  : TStringList   ;
  Line   : string        ;
  Rcv    : string        ;
  Matches: TList<TSymbol>;
  S      : TSymbol       ;
  Conf   : string        ;
  Target : Int64         ;
  RetType: string        ;
begin
  Result      := Default(TCallEdge);
  Result.RefId:= ARef.Id;
  AReason     := '';
  Line        := '';
  Rcv         := '';
  Lines       := LinesOf(ARef.FileId);
  { The site's own text decides three of the rules, so a line that does not
    match the index is a decline, not a guess -- the stale-file rule every other
    rung of this unit follows. }
  if (Lines = nil) or FileIsStale(ARef.FileId) or (ARef.NameText = '')
     or (ARef.StartLine < 1) or (ARef.StartLine > Lines.Count) then
    AReason:= 'unreadable'
  else
  begin
    Line:= Lines[ARef.StartLine - 1];
    Rcv := ExtractReceiverExpr(Line, ARef.StartCol);
    if (Rcv <> '') and not SameText(Rcv, 'Self') then AReason:= 'qualified'
    else if (Rcv = '') and EnclosingBodyUsesWith(ARef, Lines) then AReason:= 'with-scope';
  end;
  Matches:= TList<TSymbol>.Create;
  try
    if AReason = '' then AReason:= FindParenlessCandidates(ARef, Rcv, Matches);
    { EVERY member of the answering set must be callable bare. One that needs
      an argument means the name may stand for a procedure value here. }
    if AReason = '' then
      for S in Matches do
        if not IsParenlessCallable(S) then AReason:= 'not-callable';
    if AReason = '' then
    begin
      Target := PickFromMatches(Matches, 0, True, Conf);
      RetType:= '';
      for S in Matches do
        if S.Id = Target then RetType:= SignatureReturnType(S.Signature);
      if ParenlessIsProcValue(ARef, Line, Rcv, RetType) then AReason:= 'proc-value'
      else
      begin
        { ReceiverTypeSymbolId stays 0, as on the lexical and unit rungs of
          ResolveOne: a bare call has no receiver the source wrote. }
        Result.TargetSymbolId:= Target;
        Result.Confidence    := Conf;
      end;
    end;
  finally
    Matches.Free;
  end;
  TallyParenless(AReason);
end;

function TCallResolver.TypeReceiver(const ACallRef: TReference; const AReceiverExpr: string): Int64;
var
  Encl    : TSymbol;
  ClassId : Int64  ;
  Member  : TSymbol;
  CastType: string ;
begin
  Result:= 0;
  if ACallRef.EnclosingSymbolId <= 0 then Exit; // no enclosing routine -> give up
  Encl:= FStore.GetSymbolById(ACallRef.EnclosingSymbolId);

  // --- Kind 1: bare M / Self.M -> the enclosing routine's owning class.
  // NOTE on `inherited M`: it never arrives here at all. MEASURED, because the
  // lexical scope walk added above would otherwise have a real hazard -- a
  // nested routine named M is lexically nearer than the ancestor's M, and
  // binding `inherited M` to it would be flatly wrong. The parser emits NO call
  // ref for either `inherited M;` or `inherited M(Args);` (verified on the
  // run_nested_call_resolution fixture: zero refs named Ping/Pong, which are
  // reached only through `inherited`), so no guard is needed on either path.
  // An earlier version of this comment claimed `inherited M` reached here as a
  // bare kind-1 call and resolved on the ancestor chain. It does not.
  if (AReceiverExpr = '') or SameText(AReceiverExpr, 'Self') then
    Exit(Encl.ParentId);

  ClassId:= Encl.ParentId; // the enclosing routine's owning class (for kinds 2/3)

  // --- Kind 6: cast '(X as TBar).M' / 'TBar(X).M' -> the cast target type.
  if TryParseCastTarget(AReceiverExpr, CastType) then
    Exit(ResolveTypeNameToSymbol(CastType, ACallRef.FileId));

  // --- Kind 7 (v20b): a UNIT-QUALIFIED TYPE receiver, 'Unit.TType.M' /
  //     'System.JSON.TJSONArray.Create'. Mandatory Delphi whenever two used units
  //     export the same type name -- exactly when a developer reaches for it --
  //     so it is idiomatic, not exotic.
  //
  //     Before this rung the loop below exited on the FIRST '.', so such a site
  //     never reached the type-name rung and formed no edge at all. It surfaced
  //     only through the unresolved-name bucket, i.e. a REAL caller presented as
  //     uncertain (' ?').
  //
  //     Handled by taking the LAST segment as the type name: the leading segments
  //     are a unit qualifier, and ResolveTypeNameToSymbol is already file-scoped
  //     and FP-conservative (one certain candidate or nothing), so a wrong unit
  //     cannot silently bind. Only fires when EVERY segment is a plain
  //     identifier -- a real expression ('Arr[i].Foo', a cast) still falls
  //     through to the guard below, which is where it belongs.
  if Pos('.', AReceiverExpr) > 0 then
  begin
    var AllIdent: Boolean:= True;
    for var Seg in AReceiverExpr.Split(['.']) do
    begin
      if (Seg = '') or (not IsIdentStart(Seg[1])) then begin AllIdent:= False; Break; end;
      for var j:= 1 to Length(Seg) do
        if not IsIdentPart(Seg[j]) then begin AllIdent:= False; Break; end;
      if not AllIdent then Break;
    end;
    if AllIdent then
    begin
      var Segs: TArray<string>:= AReceiverExpr.Split(['.']);
      Exit(ResolveTypeNameToSymbol(Segs[High(Segs)], ACallRef.FileId));
    end;
  end;

  // The remaining handled kinds require a simple identifier receiver.
  if not IsIdentStart(AReceiverExpr[1]) then Exit; // dotted / complex -> unhandled
  for var i:= 1 to Length(AReceiverExpr) do
    if not IsIdentPart(AReceiverExpr[i]) then Exit; // e.g. 'A.B' chain -> unhandled

  // --- Kind 4: typed LOCAL var 'L.M' -> local's declared type.
  //     Kind 5: PARAM 'AFoo.M' -> param's declared type.
  // Both are children of the enclosing ROUTINE. Try them first (an inner name
  // shadows a field), then fall back to the class fields/properties.
  // v23: sibling for-var loops can declare the SAME local name twice under one
  // qualified name; when their declared types differ the receiver is not typed
  // from either (decline -> the honest untyped floor), not from the first. The
  // local still SHADOWS any same-named field or type, so a declined local ends
  // the search here rather than falling through to the rungs below.
  Member:= FindChildOfKind(ACallRef.EnclosingSymbolId, AReceiverExpr, [skLocalVar, skParam], True);
  if Member.Id > 0 then
    Exit(ResolveTypeNameToSymbol(Member.Signature, ACallRef.FileId));
  if FindChildOfKind(ACallRef.EnclosingSymbolId, AReceiverExpr, [skLocalVar, skParam]).Id > 0 then
    Exit; // a local/param of that name exists but its type is ambiguous -> 0

  // --- Kind 2: FIELD 'FBar.M' / Kind 3: PROPERTY 'Prop.M' -> member's type.
  //     Members are children of the enclosing class.
  if ClassId > 0 then
  begin
    Member:= FindChildOfKind(ClassId, AReceiverExpr, [skField, skProperty]);
    if Member.Id > 0 then
      Exit(ResolveTypeNameToSymbol(Member.Signature, ACallRef.FileId));
  end;

  // --- Kind 7: the receiver IS A TYPE -- 'TFoo.Create(...)', 'TFoo.ClassMethod'.
  //
  // This rung was missing entirely, and it is the shape EVERY Delphi constructor
  // call has. The consequence was not a quiet loss of coverage: because the call
  // did not resolve, the documentation's caller list fell through to its
  // unresolved-NAME bucket, and for a constructor that bucket is keyed on the
  // leaf name `Create` -- shared by 35 symbols in this index alone. So
  // TQueryRule.Create, constructed in exactly ONE place, documented itself with
  // 107 callers, none of them real.
  //
  // Last of the identifier rungs on purpose. A local, parameter, field or
  // property whose name happens to match a type name SHADOWS the type in Delphi,
  // and each of those was already tried above, so this can only fire when the
  // identifier is not a value in scope.
  //
  // ResolveTypeNameToSymbol is the same FP-conservative resolver the cast rung
  // uses: it answers only when exactly one candidate is in scope (or exactly one
  // exists globally), so an ambiguous type name still yields 0 rather than a
  // guess. Class METHODS and constructors are ordinary children of the type
  // symbol, so LookupMethodOnType needs no change to find them.
  Result:= ResolveTypeNameToSymbol(AReceiverExpr, ACallRef.FileId);
  if Result > 0 then Exit;

  // Unresolved receiver identifier (unknown local/param/field, and not a type we
  // can name) -> Result stays 0 (leave unresolved).
end;

function TCallResolver.LookupMemberOnType(ATypeSymbolId: Int64; const AMemberName: string): TSymbol;
const
  MEMBER_KINDS: TSymbolKindSet = [skProperty, skField];
var
  A: TTypeAncestor;
begin
  Result:= Default(TSymbol);
  if ATypeSymbolId <= 0 then Exit;
  Result:= FindChildOfKind(ATypeSymbolId, AMemberName, MEMBER_KINDS);
  if Result.Id > 0 then Exit;
  for A in FStore.GetTransitiveAncestors(ATypeSymbolId) do
  begin
    if not A.Resolved or (A.SymbolId <= 0) then Continue;
    Result:= FindChildOfKind(A.SymbolId, AMemberName, MEMBER_KINDS);
    if Result.Id > 0 then Exit;
  end;
end;

function TCallResolver.MemberAccessMode(const ARef: TReference): string;
var
  Lines: TStringList;
  Line : string;
  P    : Integer;
  Depth: Integer;
begin
  Result:= '';
  Lines:= LinesOf(ARef.FileId);
  if (Lines = nil) or (ARef.EndLine < 1) or (ARef.EndLine > Lines.Count) then Exit;
  Line:= Lines[ARef.EndLine - 1];
  { Start just past the name. Whether EndCol is inclusive or exclusive in a
    given index, skipping the remaining identifier characters lands on the
    first character AFTER the member, which is the only position that matters. }
  P:= ARef.StartCol + Length(ARef.NameText);
  if (ARef.EndLine <> ARef.StartLine) or (P < 1) then P:= Max(ARef.EndCol, 1);
  while (P <= Length(Line)) and IsIdentPart(Line[P]) do Inc(P);
  Result:= 'read';
  while P <= Length(Line) do
  begin
    case Line[P] of
      ' ', #9: Inc(P);
      '[':
        begin
          { skip one balanced indexer -- `Items[0] := x` writes Items }
          Depth:= 0;
          repeat
            if Line[P] = '[' then Inc(Depth)
            else if Line[P] = ']' then Dec(Depth);
            Inc(P);
          until (Depth = 0) or (P > Length(Line));
        end;
      ':':
        begin
          if (P < Length(Line)) and (Line[P + 1] = '=') then Result:= 'write';
          Exit;
        end;
    else
      Exit;
    end;
  end;
end;

// The position just past the first STANDALONE occurrence of the keyword AKey
// in ADecl, or 0 when absent. Standalone means not part of a longer
// identifier: `read` inside `FReadOnly` is a name, not the keyword. Shared by
// AccessorIdentAfter (`read` / `write`) and PropertyIndexArity (`property`).
function PosAfterKeyword(const ADecl, AKey: string): Integer;
var
  I, J: Integer;
begin
  Result:= 0;
  I:= 1;
  while I <= Length(ADecl) do
  begin
    if not (IsIdentStart(ADecl[I]) and ((I = 1) or not IsIdentPart(ADecl[I - 1]))) then
    begin
      Inc(I);
      Continue;
    end;
    J:= I;
    while (J <= Length(ADecl)) and IsIdentPart(ADecl[J]) do Inc(J);
    if SameText(Copy(ADecl, I, J - I), AKey) then Exit(J);
    I:= J;
  end;
end;

// The identifier after the standalone keyword AKey (`read` / `write`) on a
// property's declaring text, or '' when absent or a dotted path (`FRec.X` is a
// record field access, not an accessor this resolver can name).
function AccessorIdentAfter(const ADecl, AKey: string): string;
var
  I, J: Integer;
begin
  Result:= '';
  J:= PosAfterKeyword(ADecl, AKey);
  if J = 0 then Exit;
  while (J <= Length(ADecl)) and (ADecl[J] = ' ') do Inc(J);
  I:= J;
  while (J <= Length(ADecl)) and IsIdentPart(ADecl[J]) do Inc(J);
  Result:= Copy(ADecl, I, J - I);
  if (J <= Length(ADecl)) and (ADecl[J] = '.') then Result:= '';
end;

// The number of INDEX parameters the property APropName declares on its
// declaring text: `property Items[I, J: Integer; const Key: string]` is 3,
// `property Flag: Boolean` is 0. The index list is not in the symbol row (its
// signature holds only the type), so it is read off ADecl like the accessor
// names are. -1 when the declaration cannot be read (`property` + name not
// found, an unbalanced bracket) -- an unknown, not a zero.
function PropertyIndexArity(const ADecl, APropName: string): Integer;
var
  I, J, Depth: Integer;
  Lo, Hi     : Integer;
begin
  Result:= -1;
  J:= PosAfterKeyword(ADecl, 'property');
  if J = 0 then Exit;
  while (J <= Length(ADecl)) and (ADecl[J] = ' ') do Inc(J);
  I:= J;
  while (J <= Length(ADecl)) and IsIdentPart(ADecl[J]) do Inc(J);
  if not SameText(Copy(ADecl, I, J - I), APropName) then Exit;
  while (J <= Length(ADecl)) and (ADecl[J] = ' ') do Inc(J);
  if (J > Length(ADecl)) or (ADecl[J] <> '[') then Exit(0);
  { Balanced extract of `[...]`, then count it the way a parameter list is
    counted -- SignatureArityRange already splits groups at top-level ';' and
    names at ','; an index parameter has no default, so Lo = Hi. }
  Depth:= 0;
  I    := J;
  while J <= Length(ADecl) do
  begin
    case ADecl[J] of
      '[': Inc(Depth);
      ']': Dec(Depth);
    end;
    if Depth = 0 then Break;
    Inc(J);
  end;
  if Depth <> 0 then Exit;
  if SignatureArityRange('(' + Copy(ADecl, I + 1, J - I - 1) + ')', Lo, Hi) then Exit(Hi);
end;

function TCallResolver.PickAccessor(AParentId: Int64; const AName: string; AArity: Integer;
  const AKinds: TSymbolKindSet; out AFound: Boolean): TSymbol;
var
  Kids   : TList<TSymbol>;
  S      : TSymbol       ;
  Lo, Hi : Integer       ;
  FitN   : Integer       ;
  Overld : Boolean       ;
begin
  Result:= Default(TSymbol);
  AFound:= False;
  Kids  := ChildrenOf(AParentId);
  if Kids = nil then Exit;
  { Pass 1: the first-match answer, and whether the name is an OVERLOAD SET
    (a second candidate with a DIFFERENT signature -- same-signature twins are
    the first-match case, exactly as FindChildOfKind treats them). }
  Overld:= False;
  for S in Kids do
    if (S.Kind in AKinds) and SameText(S.Name, AName) then
    begin
      if not AFound then
      begin
        Result:= S;
        AFound:= True;
      end
      else if S.Signature <> Result.Signature then Overld:= True;
    end;
  if not Overld then Exit;
  { Pass 2 (batch residue R1): `read GetItem` beside two GetItem declarations
    used to bind the FIRST one -- a coin toss recorded as certain. The
    property's own shape narrows it: a getter takes exactly the index
    parameters and a setter those plus the value, so an overload whose arity
    range does not contain that count cannot be the accessor. A unique
    survivor answers; several (same count, types only) or none DECLINE, on
    the unit's FP policy -- no edge over a wrong one. }
  FitN  := 0;
  Result:= Default(TSymbol);
  if AArity < 0 then Exit;
  for S in Kids do
    if (S.Kind in AKinds) and SameText(S.Name, AName)
       and SignatureArityRange(S.Signature, Lo, Hi) and (AArity >= Lo) and (AArity <= Hi) then
    begin
      Inc(FitN);
      Result:= S;
    end;
  if FitN <> 1 then Result:= Default(TSymbol);
end;

function TCallResolver.ResolveAccessor(const AProp: TSymbol; const AMode: string): TSymbol;
const
  ACCESSOR_KINDS: TSymbolKindSet = [skMethod, skProcedure, skFunction, skField];
var
  Lines    : TStringList;
  Decl     : string;
  I        : Integer;
  Ident    : string;
  A        : TTypeAncestor;
  WantArity: Integer;
  Found    : Boolean;
begin
  Result:= Default(TSymbol);
  { Guards, consolidated: a member with no parent, an unknown mode, or a stale
    file (S1 -- the accessor names live on the declaring line(s), which the
    index does not store, so they are read from the cached source exactly as
    the receiver text is, and a stale line is a guess, not a fact). }
  if (AProp.Id <= 0) or (AProp.ParentId <= 0) or ((AMode <> 'read') and (AMode <> 'write'))
     or FileIsStale(AProp.FileId) then Exit;
  Lines:= LinesOf(AProp.FileId);
  if (Lines = nil) or (AProp.StartLine < 1) or (AProp.StartLine > Lines.Count) then Exit;
  Decl:= ' ' + Lines[AProp.StartLine - 1];
  for I:= AProp.StartLine + 1 to Min(AProp.EndLine, Lines.Count) do
    Decl:= Decl + ' ' + Lines[I - 1];
  Ident:= AccessorIdentAfter(Decl, AMode);
  if Ident = '' then Exit;
  { The count an overloaded accessor must accept (PickAccessor): a getter takes
    the index parameters, a setter takes them plus the value. -1 propagates an
    unreadable declaration so an overload set declines instead of guessing. }
  WantArity:= PropertyIndexArity(Decl, AProp.Name);
  if (WantArity >= 0) and (AMode = 'write') then Inc(WantArity);
  { A same-named member on the declaring class SHADOWS every ancestor's, so a
    declined overload set there ends the search -- Found says the name was
    seen even when the answer is 0. }
  Result:= PickAccessor(AProp.ParentId, Ident, WantArity, ACCESSOR_KINDS, Found);
  if not Found then
    for A in FStore.GetTransitiveAncestors(AProp.ParentId) do
    begin
      if not A.Resolved or (A.SymbolId <= 0) then Continue;
      Result:= PickAccessor(A.SymbolId, Ident, WantArity, ACCESSOR_KINDS, Found);
      if Found then Break;
    end;
end;

function TCallResolver.ResolveOne(const ACallRef: TReference): TCallEdge;
var
  Lines   : TStringList;
  Line    : string     ;
  Rcv     : string     ;
  TypeId  : Int64      ;
  Conf    : string     ;
  Target  : Int64      ;
  ArgCount: Integer    ;
  ArgsKnown: Boolean   ;
begin
  Result:= Default(TCallEdge);
  Result.RefId:= ACallRef.Id;
  Result.TargetSymbolId      := 0;
  Result.ReceiverTypeSymbolId:= 0;
  Result.Confidence          := '';

  if ACallRef.NameText = '' then Exit;

  // 1. read the source line and extract the receiver expression left of '.M'.
  Line := '';
  Rcv  := '';
  Lines:= LinesOf(ACallRef.FileId);
  if (Lines <> nil) and (ACallRef.StartLine >= 1) and (ACallRef.StartLine <= Lines.Count) then
  begin
    Line:= Lines[ACallRef.StartLine - 1];
    Rcv := ExtractReceiverExpr(Line, ACallRef.StartCol);
  end;
  { v20: hand the receiver text back so ResolveCallTargets can persist it. Set
    HERE, immediately after it is computed and before any of the resolution
    rungs can Exit, so every return path carries it -- a path that leaves
    earlier legitimately has '' (no name, or no readable source line). This is a
    pure record write; the value was already being computed and dropped. }
  Result.ReceiverText:= Rcv;
  { A receiver derived from a line that no longer corresponds to this ref is a
    GUESS, not a fact. Flag it so ResolveCallTargets withholds the write and the
    stored value -- computed against the source that actually produced the ref --
    survives. Resolution below still runs: a name-based rung can be right even
    when the source line is unusable. }
  Result.ReceiverUnknown:= FileIsStale(ACallRef.FileId);

  // 1b. B1: count the arguments at this site, from the same cached lines. Unlike
  // the receiver scan -- which reads LEFT and cannot leave the line -- an
  // argument list reads RIGHT and legitimately spans lines, so this is given the
  // whole file rather than the single line.
  ArgCount:= CountCallArgs(Lines, ACallRef.StartLine, ACallRef.StartCol, ArgsKnown);

  // 1c. NESTED-CALL RESOLUTION: a BARE call is resolved by Delphi's lexical
  // scope chain BEFORE any receiver typing, because the innermost declaration
  // wins outright -- a nested routine shadows a same-named method of the
  // enclosing class, so consulting the class first would answer the wrong one.
  // Falls through untouched when no scope on the chain declares the name, which
  // is the common case (an intrinsic, an RTL call, a unit-level routine).
  if Rcv = '' then
  begin
    Target:= LookupInLexicalScopes(ACallRef.EnclosingSymbolId, ACallRef.NameText, Conf);
    if Target > 0 then
    begin
      // ReceiverTypeSymbolId stays 0: a lexical hit has no receiver TYPE. The
      // field means "the type the receiver was typed to", and inventing the
      // enclosing routine's class here would be a false claim about a call that
      // has no receiver at all.
      Result.TargetSymbolId:= Target;
      Result.Confidence    := Conf;
      Exit;
    end;
  end;

  // 2. type the receiver -> a class/interface/record symbol id.
  TypeId:= TypeReceiver(ACallRef, Rcv);
  Result.ReceiverTypeSymbolId:= TypeId; // 0 when the receiver type is unknown

  // 3. look the method up on the resolved type + its ancestor chain.
  if TypeId > 0 then
  begin
    Target:= LookupMethodOnType(TypeId, ACallRef.NameText, ArgCount, ArgsKnown, Conf);
    if Target > 0 then
    begin
      Result.TargetSymbolId:= Target;
      Result.Confidence    := Conf;
      Exit;
    end;
    { 3b. PROPERTY / FIELD (2026-09-16, property-refs-resolve). A member-access
      ref that names no routine on the typed receiver may name a property or
      field, and until now that was the end of it: the ref stayed unbound and a
      public property with 207 dependents reported "0 place(s)" when removed.
      Only for member-access refs -- a 'call' ref naming a property would be a
      parse oddity, not a call -- and only with a typed receiver: a bare name
      inside the class is a 'read'/'write' ref, out of scope here. The owner's
      ruling: a READ is also a call to the getter, a WRITE to the setter; a
      field-backed accessor is a use of that field. The mode and accessor ride
      on the edge; ResolveCallTargets decides what each earns. }
    if SameText(ACallRef.Kind, 'member-access') then
    begin
      var Member: TSymbol:= LookupMemberOnType(TypeId, ACallRef.NameText);
      if Member.Id > 0 then
      begin
        Result.TargetSymbolId:= Member.Id;
        Result.Confidence    := 'certain';
        Result.MemberMode    := MemberAccessMode(ACallRef);
        if Result.MemberMode = '' then Result.MemberMode:= 'read';
        if Member.Kind = skProperty then
        begin
          var Acc: TSymbol:= ResolveAccessor(Member, Result.MemberMode);
          if Acc.Id > 0 then
          begin
            Result.AccessorSymbolId:= Acc.Id;
            Result.AccessorKind    := (if Acc.Kind = skField then 'field' else 'method');
          end;
        end;
        Exit;
      end;
    end;
  end;

  { 3c. ENUM VALUE through a qualified receiver (2026-09-23,
    enum-value-ref-binding, spec rule R6). `TEnum.value` types its receiver to
    the enum -- enums joined GetTypeCandidates on 2026-08-30 -- then finds no
    routine and no property/field, and until now fell out unbound; the store's
    routine branch then refused it (QIsRoutine) and wrote NOTHING, so
    refs.symbol_id stayed NULL. `Unit.value` never types at all.

    Placed AFTER 3b and BEFORE rung 4 on purpose: a routine or a property on the
    receiver still wins, and rungs 4/5 still see the ref when this does not fire.
    Gated on the name map first, so the common case costs one dictionary miss.

    `Rcv <> ''` is load-bearing rather than tidiness: TypeReceiver returns the
    ENCLOSING CLASS for a bare or `Self` receiver, so without it a bare call
    could reach this rung carrying a receiver the source never wrote.

    Marks the edge ValueOnly -- refs.symbol_id and nothing else: no call_edges
    row (CanBeCallTarget stays routine-only) and no member_accesses row (an enum
    value carries no mode and no accessor to record). }
  if SameText(ACallRef.Kind, 'member-access') and (Rcv <> '')
     and FNameToEnumValues.ContainsKey(LowerCase(ACallRef.NameText)) then
  begin
    var V: Int64:= 0;
    if (TypeId > 0) and (FStore.GetSymbolById(TypeId).Kind = skEnum) then
      V:= FindChildOfKind(TypeId, ACallRef.NameText, [skEnumValue], False).Id
    else if TypeId = 0 then
    begin
      { A UNIT-name receiver: `Pipes.Protocol.cmdDelta`. Narrow the candidates to
        that unit's file -- its interface section, or either section when the
        unit IS this file -- and bind only when exactly one survives. R3 is moot
        here: the source qualified the name itself, so nothing shadows it. }
      var UnitFile: Int64:= UnitNameToFileId(Rcv);
      if UnitFile > 0 then
      begin
        var InUnit: TArray<TEnumValueDecl>:= nil;
        for var C: TEnumValueDecl in FNameToEnumValues[LowerCase(ACallRef.NameText)] do
          if (C.FileId = UnitFile)
             and (SameText(C.Section, 'interface') or (UnitFile = ACallRef.FileId)) then
            InUnit:= InUnit + [C];
        InUnit:= CollapseIdenticalEnumCopies(InUnit, ACallRef.FileId);
        if Length(InUnit) = 1 then V:= InUnit[0].Id;
      end;
    end;
    if V > 0 then
    begin
      Result.TargetSymbolId:= V;
      Result.Confidence    := 'certain';
      Result.ValueOnly     := True;
      Inc(FEnumStats.Bound);
      Exit;
    end;
  end;

  // 4. OPTION 4 -- the UNIT-LEVEL rung, and the LAST one. Reached only for a
  // BARE call that no nearer scope claimed: not a nested routine, and not a
  // method of the enclosing class or its ancestors. That ordering is the whole
  // correctness argument -- running this earlier would rebind calls that today
  // resolve correctly to a method.
  //
  // A DOTTED call is excluded outright. `Obj.Format` names a member of Obj and
  // must never bind to a free `Format`, so the guard is Rcv = '' and not merely
  // "the receiver failed to type": an unresolvable receiver is unknown, not
  // absent, and treating the two alike is how a resolver invents edges.
  //
  // Note this is now also the path for a bare call whose receiver typing yielded
  // nothing at all (TypeId = 0) -- previously an early Exit. A free routine
  // calling another free routine in a unit it uses has no receiver to type, and
  // that shape was the larger half of what this rung recovers.
  if Rcv = '' then
  begin
    Target:= LookupUnitLevelRoutine(ACallRef.FileId, ACallRef.NameText, ArgCount, ArgsKnown, Conf);
    if Target > 0 then
    begin
      // ReceiverTypeSymbolId is CLEARED, matching the lexical rung above. For a
      // bare call inside a method, TypeReceiver returns the enclosing class --
      // the implicit Self, not a receiver the source wrote. Leaving it set would
      // record "this call went through a TFoo receiver" for a call that has no
      // receiver at all, and the two bare-call rungs would disagree about the
      // same field.
      Result.ReceiverTypeSymbolId:= 0;
      Result.TargetSymbolId:= Target;
      Result.Confidence    := Conf;
    end;
  end;

  // 5. v21 CROSS-DB, and it runs LAST for a reason: only a call this index could
  // not resolve locally is offered to another index. A local answer always wins,
  // so adding a library store can never change an edge that already existed.
  //
  // The answer is a qualified NAME, not an id. call_edges.target_symbol_id is a
  // NOT NULL FK into THIS db's symbols, so an edge to a library symbol cannot be
  // written at all; the name lands on refs.external_target instead. See the v21
  // note in Migrate for why the alternative (nullable FK + target_qname) was
  // rejected.
  if (Result.TargetSymbolId = 0) and (Length(FExtraStores) > 0) then
    Result.ExternalTarget:= ResolveExternally(Rcv, ACallRef.NameText);
end;

{ v21. Consults the extra (library) stores for a call the primary index could not
  resolve, and answers with a QUALIFIED NAME.

  Deliberately narrow, because a wrong external name is a wrong FACT rendered in
  documentation, and this runs with no uses-scope filter at all:
    * a TYPE-NAME receiver only. A value receiver ('Q.Open') would need the
      variable's type, which lives in the PRIMARY index and already failed to
      resolve there -- guessing across a library would be inventing.
    * the type leaf must name exactly ONE type in that store, and it must own
      exactly ONE member with this call's name. Two candidates means the answer
      is a guess, and absence beats a wrong name -- the same FP-conservative
      posture ResolveTypeNameToSymbol takes locally.
  Returns '' whenever any of that fails, which is the common case and is fine:
  the ref simply stays unresolved, exactly as it was before v21. }
function TCallResolver.ResolveExternally(const AReceiver, ACallName: string): string;
var
  Store  : ISymbolStore ;
  Leaf   : string       ;
  Cands  : TArray<TSymbol>;
  S, M   : TSymbol      ;
  TypeSym: TSymbol      ;
  Found  : Integer      ;
  Members: TArray<TSymbol>;
  Hit    : TSymbol      ;
  MemHits: Integer      ;
begin
  Result:= '';
  if (Trim(AReceiver) = '') or (Trim(ACallName) = '') then Exit;
  if SameText(AReceiver, 'Self') then Exit; { the enclosing class is a LOCAL question }

  { A dotted receiver contributes its LAST segment -- 'System.JSON.TJSONArray'
    names TJSONArray; the leading segments are a unit qualifier. }
  Leaf:= AReceiver;
  if Pos('.', Leaf) > 0 then
  begin
    var Segs: TArray<string>:= Leaf.Split(['.']);
    Leaf:= Segs[High(Segs)];
  end;
  if Leaf = '' then Exit;

  for Store in FExtraStores do
  begin
    if Store = nil then Continue;
    Cands:= Store.FindSymbolsByExactName(Leaf);
    Found:= 0;
    TypeSym:= Default(TSymbol);
    for S in Cands do
      if S.Kind in [skClass, skInterface, skRecord] then
      begin
        Inc(Found);
        if Found > 1 then Break;
        TypeSym:= S;
      end;
    if Found <> 1 then Continue;          { absent or ambiguous -> no answer }

    Members:= Store.FindAllChildSymbols(TypeSym.Id);
    MemHits:= 0;
    Hit:= Default(TSymbol);
    for M in Members do
      if SameText(M.Name, ACallName) and CanBeCallTarget(M.Kind) then
      begin
        Inc(MemHits);
        if MemHits > 1 then Break;
        Hit:= M;
      end;
    if MemHits = 1 then Exit(Hit.QualifiedName);
  end;
end;

end.
