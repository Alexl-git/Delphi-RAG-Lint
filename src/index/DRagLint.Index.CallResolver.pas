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
  System.Generics.Collections,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces;

type
  /// <summary>v14 (D5): a set of symbol kinds -- lets the resolver's child scans
  /// filter by "any method-shaped kind" / "any type-defining kind" in one test.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind (DRagLint.Index.CallResolver.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSymbolKindSet = set of TSymbolKind;

  /// <summary>v14 (D5): receiver-typing + method-chain call resolver. Prepare
  /// once (Create builds the name-candidate + file-scope maps from the whole DB),
  /// then call ResolveOne per call-site ref.</summary>
  /// <remarks>
  /// Not thread-safe; single owning thread only. Holds the ISymbolStore
  /// for the resolver's lifetime -- the store must outlive the resolver.
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.Storage.SQLite.TSQLiteSymbolStore.ResolveCallTargets (DRagLint.Storage.SQLite.pas)
  /// Used in units: DRagLint.Storage.SQLite
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCallResolver = class
  strict private
    FStore      : ISymbolStore;
    // Lowercased simple type name -> candidate class/interface/record symbols.
    FNameToCands: TObjectDictionary<string, TList<TSymbol>>;
    // Option 4: lowercased routine name -> candidate UNIT-LEVEL routines (free
    // procedures/functions). Deliberately separate from FNameToCands: that map
    // holds TYPES for receiver typing, and a bare call resolves against
    // routines, so merging them would make every lookup filter by kind.
    FNameToRoutines: TObjectDictionary<string, TList<TSymbol>>;
    // Declaring file id -> the resolved target file ids it can see (uses graph).
    FFileScope  : TObjectDictionary<Int64, TList<Int64>>;
    // Cache of a routine/type symbol's direct children, keyed by symbol id, so a
    // per-ref field/method scan does not re-hit the DB for the same enclosing
    // symbol repeatedly across a whole-DB pass.
    FChildCache : TObjectDictionary<Int64, TList<TSymbol>>;
    // Cache: source file id -> its lines (0-based array). A single whole-DB pass
    // touches many refs in the same file; read each file at most once.
    FLineCache  : TObjectDictionary<Int64, TStringList>;

    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Index.CallResolver.TCallResolver.Create (DRagLint.Index.CallResolver.pas)
    /// Calls: LowerCase
    /// Reads: FStore, FNameToCands, FNameToRoutines, FFileScope
    /// Pure
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Create"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Destroy"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure BuildMaps;
    /// <summary>True when a candidate declared in ACandFile is visible from
    /// ADeclFile (same file, or in ADeclFile's resolved uses scope).</summary>
    /// <param name="ADeclFile"><!-- drag-lint:auto type -->Int64</param>
    /// <param name="ACandFile"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto -->Observed: (ADeclFile = ACandFile);
    /// L.IndexOf(ACandFile) &gt;= 0.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Index.CallResolver.TCallResolver.LookupUnitLevelRoutine (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveTypeNameToSymbol (DRagLint.Index.CallResolver.pas)
    /// Reads: FFileScope
    /// Pure
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Create"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Destroy"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function CandInScope(ADeclFile, ACandFile: Int64): Boolean;
    /// <summary>Resolve a raw type text (a param/field/local Signature) to a
    /// defining class/interface/record symbol id, in scope of ADeclFileId. 0 when
    /// unresolvable OR ambiguous (FP-conservative, mirrors ResolveAncestry).</summary>
    /// <param name="ATypeText"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ADeclFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto -->Observed: 0; Cands[InScopeIdx].Id; Cands[0].Id.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Index.CallResolver.TCallResolver.TypeReceiver (DRagLint.Index.CallResolver.pas)
    /// Calls: Copy, DRagLint.Index.CallResolver.TCallResolver.CandInScope, LowerCase, Pos, Trim
    /// Complexity: 11 (cyclomatic, outer body), 35 lines (full implementation)
    /// Reads: FNameToCands
    /// Pure
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Create"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ResolveTypeNameToSymbol(const ATypeText: string; ADeclFileId: Int64): Int64;
    /// <summary>Direct children of AParentId (cached). Empty when none / 0.</summary>
    /// <param name="AParentId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto -->Observed: TList&lt;TSymbol&gt;.Create.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LookupInLexicalScopes (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LookupMethodOnType (DRagLint.Index.CallResolver.pas)
    /// Calls: DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols
    /// Reads: FChildCache, FStore
    /// Pure
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
    /// <returns><!-- drag-lint:auto -->Observed: TStringList.Create.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)
    /// Calls: DRagLint.Core.Interfaces.ISymbolStore.GetFilePath
    /// Reads: FLineCache, FStore
    /// Touches: file system
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function LinesOf(AFileId: Int64): TStringList;
    /// <summary>Find a direct child of AParentId whose Name matches AName (case-
    /// insensitively) and whose Kind is in AKinds. Default(TSymbol) (Id=0) when
    /// none.</summary>
    /// <param name="AParentId"><!-- drag-lint:auto type -->Int64</param>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AKinds"><!-- drag-lint:auto type -->const TSymbolKindSet</param>
    /// <returns><!-- drag-lint:auto -->Observed: Default(TSymbol).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Index.CallResolver.TCallResolver.TypeReceiver (DRagLint.Index.CallResolver.pas)
    /// Calls: Default, DRagLint.Index.CallResolver.TCallResolver.ChildrenOf, SameText
    /// Pure
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Create"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindChildOfKind(AParentId: Int64; const AName: string; const AKinds: TSymbolKindSet): TSymbol;
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
    /// <returns><!-- drag-lint:auto -->Observed: 0; AMatches[0].Id; Fit[0].Id.</returns>
    /// <remarks>
    /// Arity NARROWS an existing name match and never widens one: when
    /// it cannot decide -- several candidates of one arity, or none that fits --
    /// the answer is the pre-arity one, still marked uncertain. Shared by the
    /// method-chain and unit-level rungs so the two cannot drift apart on how a
    /// tie is broken.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Index.CallResolver.TCallResolver.LookupMethodOnType (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LookupUnitLevelRoutine (DRagLint.Index.CallResolver.pas)
    /// Calls: DRagLint.Index.CallResolver.SignatureArityRange
    /// Complexity: 10 (cyclomatic, outer body), 52 lines (full implementation)
    /// Mutates: AConfidence (out)
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
    /// <returns><!-- drag-lint:auto -->Observed: 0; PickFromMatches(Matches, AArgCount,
    /// AArgsKnown, AConfidence).</returns>
    /// <remarks>
    /// Arity NARROWS an existing name match; it never widens one. When
    /// it cannot decide -- several candidates of the same arity, or none that
    /// fits -- the result is exactly what it was before B1, so a call that used
    /// to resolve still resolves.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)
    /// Calls: DRagLint.Core.Interfaces.ISymbolStore.GetTransitiveAncestors, DRagLint.Index.CallResolver.TCallResolver.ChildrenOf, DRagLint.Index.CallResolver.TCallResolver.PickFromMatches, SameText
    /// Complexity: 10 (cyclomatic, outer body), 36 lines (full implementation)
    /// Reads: FStore
    /// Mutates: AConfidence (out)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetTransitiveAncestors"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.PickFromMatches"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function LookupMethodOnType(ATypeSymbolId: Int64; const AMethodName: string;
      AArgCount: Integer; AArgsKnown: Boolean; out AConfidence: string): Int64;
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
    /// Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)
    /// Calls: DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, DRagLint.Index.CallResolver.TCallResolver.ChildrenOf, SameText
    /// Returns: 0; Matches[0].Id
    /// Complexity: 14 (cyclomatic, outer body), 55 lines (full implementation)
    /// Reads: FStore
    /// Mutates: AConfidence (out)
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
    /// Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)
    /// Calls: DRagLint.Index.CallResolver.TCallResolver.CandInScope, DRagLint.Index.CallResolver.TCallResolver.PickFromMatches, LowerCase, SameText
    /// Returns: 0; PickFromMatches(Matches, AArgCount, AArgsKnown, AConfidence)
    /// Reads: FNameToRoutines
    /// Mutates: AConfidence (out)
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
    /// <returns><!-- drag-lint:auto -->Observed: 0; Encl.ParentId;
    /// ResolveTypeNameToSymbol(CastType, ACallRef.FileId);
    /// ResolveTypeNameToSymbol(Member.Signature, ACallRef.FileId);
    /// ResolveTypeNameToSymbol(AReceiverExpr, ACallRef.FileId).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)
    /// Calls: DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, DRagLint.Index.CallResolver.IsIdentPart, DRagLint.Index.CallResolver.IsIdentStart, DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind, DRagLint.Index.CallResolver.TCallResolver.ResolveTypeNameToSymbol, DRagLint.Index.CallResolver.TryParseCastTarget, SameText
    /// Complexity: 12 (cyclomatic, outer body), 77 lines (full implementation)
    /// Reads: FStore
    /// Pure
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById"/>
    /// <seealso cref="DRagLint.Index.CallResolver.IsIdentPart"/>
    /// <seealso cref="DRagLint.Index.CallResolver.IsIdentStart"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ResolveTypeNameToSymbol"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function TypeReceiver(const ACallRef: TReference; const AReceiverExpr: string): Int64;
  public
    /// <summary>Builds the whole-DB name/scope maps from AStore. Call once.</summary>
    /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Index.CallResolver.TCallResolver.Create (DRagLint.Index.CallResolver.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.ResolveCallTargets (DRagLint.Storage.SQLite.pas), DRagLint.CLI.PrintReferences (DRagLint.CLI.pas) ?, DRagLint.CLI.PrintReferencesWithContext (DRagLint.CLI.pas) ?, DRagLint.CLI.PlanToJson (DRagLint.CLI.pas) ? (+155 more)
    /// Calls: DRagLint.Index.CallResolver.TCallResolver.BuildMaps, DRagLint.Index.CallResolver.TCallResolver.Create
    /// Writes: FStore, FNameToCands, FNameToRoutines, FFileScope, FChildCache, FLineCache
    /// Recursive
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Destroy"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(const AStore: ISymbolStore);
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Reads: FLineCache, FChildCache, FFileScope, FNameToRoutines, FNameToCands   Writes: FStore
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.Create"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;

    /// <summary>Resolve one call-site ref to a call edge. RefId is copied from
    /// ACallRef; TargetSymbolId=0 means NO edge (unresolved / unhandled shape).
    /// ReceiverTypeSymbolId is set whenever the receiver type resolved (even if
    /// the method was not found on it); Confidence is 'certain' | 'ambiguous'
    /// (only meaningful when TargetSymbolId>0).</summary>
    /// <param name="ACallRef"><!-- drag-lint:auto type -->const TReference</param>
    /// <returns><!-- drag-lint:auto -->Observed: Default(TCallEdge).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Storage.SQLite.TSQLiteSymbolStore.ResolveCallTargets (DRagLint.Storage.SQLite.pas)
    /// Calls: Default, DRagLint.Index.CallResolver.CountCallArgs, DRagLint.Index.CallResolver.ExtractReceiverExpr, DRagLint.Index.CallResolver.TCallResolver.LinesOf, DRagLint.Index.CallResolver.TCallResolver.LookupInLexicalScopes, DRagLint.Index.CallResolver.TCallResolver.LookupMethodOnType, DRagLint.Index.CallResolver.TCallResolver.LookupUnitLevelRoutine, DRagLint.Index.CallResolver.TCallResolver.TypeReceiver
    /// Complexity: 11 (cyclomatic, outer body), 103 lines (full implementation)
    /// Pure
    /// <seealso cref="DRagLint.Index.CallResolver.CountCallArgs"/>
    /// <seealso cref="DRagLint.Index.CallResolver.ExtractReceiverExpr"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.LinesOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.LookupInLexicalScopes"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.LookupMethodOnType"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ResolveOne(const ACallRef: TReference): TCallEdge;
  end;

  /// <summary>Extract the receiver expression immediately left of a dotted call.
  /// ARefCol is the 1-based column of the called method name's first char (the
  /// ref position the parser stores for X.M -> col of M). Returns the receiver
  /// text ('FBar', 'Self', 'A.B', '(X as TBar)', 'GetFoo') or '' for a bare /
  /// non-dotted call. Pure over ASourceLine; unit-tested via
  /// TCallResolver's own trace.</summary>
  /// <param name="ASourceLine"><!-- drag-lint:auto type -->const string</param>
  /// <param name="ARefCol"><!-- drag-lint:auto type -->Integer</param>
  /// <returns><!-- drag-lint:auto -->Observed: ''; Trim(Copy(Line, StopL, ARefCol - 1 -
  /// StopL)).</returns>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)
  /// Calls: Copy, DRagLint.Index.CallResolver.IsIdentPart, Trim
  /// Complexity: 26 (cyclomatic, outer body), 65 lines (full implementation)
  /// Pure
  /// <seealso cref="DRagLint.Index.CallResolver.IsIdentPart"/>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  function ExtractReceiverExpr(const ASourceLine: string; ARefCol: Integer): string;

  /// <summary>True when ATypeText, normalized, is a hard cast prefix shape
  /// '(EXPR as TName)' or 'TName(EXPR)'; if so ATypeName receives the target
  /// type name TName. Used by receiver kind 6 (cast). False otherwise.</summary>
  /// <param name="AReceiverExpr"><!-- drag-lint:auto type -->const string</param>
  /// <param name="ATypeName"><!-- drag-lint:auto type -->out string</param>
  /// <returns><!-- drag-lint:auto -->Observed: False.</returns>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Called from: DRagLint.Index.CallResolver.TCallResolver.TypeReceiver (DRagLint.Index.CallResolver.pas)
  /// Calls: Copy, DRagLint.Index.CallResolver.IsIdentPart, DRagLint.Index.CallResolver.IsIdentStart, SameText, Trim
  /// Complexity: 32 (cyclomatic, outer body), 69 lines (full implementation)
  /// Mutates: ATypeName (out)
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
  /// Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)
  /// Calls: DRagLint.Index.CallResolver.IsIdentPart, M
  /// Returns: 0; Commas + 1
  /// Complexity: 57 (cyclomatic, outer body), 152 lines (full implementation)
  /// Mutates: AKnown (out)
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
  /// Called from: DRagLint.Doc.Facts.OverloadArityTag (DRagLint.Doc.Facts.pas), DRagLint.Index.CallResolver.TCallResolver.PickFromMatches (DRagLint.Index.CallResolver.pas)
  /// Calls: Copy, parens, Pos, SplitString, StartsText, Trim
  /// Returns: False; True
  /// Complexity: 25 (cyclomatic, outer body), 103 lines (full implementation)
  /// Mutates: AMin (out), AMax (out)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  function SignatureArityRange(const ASignature: string; out AMin, AMax: Integer): Boolean;

implementation

uses
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
    if (Ch = ')') or (Ch = ']') then
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

constructor TCallResolver.Create(const AStore: ISymbolStore);
begin
  inherited Create;
  FStore      := AStore;
  FNameToCands:= TObjectDictionary<string, TList<TSymbol>>.Create([doOwnsValues]);
  FNameToRoutines:= TObjectDictionary<string, TList<TSymbol>>.Create([doOwnsValues]);
  FFileScope  := TObjectDictionary<Int64, TList<Int64>>.Create([doOwnsValues]);
  FChildCache := TObjectDictionary<Int64, TList<TSymbol>>.Create([doOwnsValues]);
  FLineCache  := TObjectDictionary<Int64, TStringList>.Create([doOwnsValues]);
  BuildMaps;
end;

destructor TCallResolver.Destroy;
begin
  FLineCache .Free;
  FChildCache.Free;
  FFileScope .Free;
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
  Path: string;
begin
  if AFileId <= 0 then Exit(nil);
  if FLineCache.TryGetValue(AFileId, Result) then Exit;
  Result:= TStringList.Create;
  Path  := FStore.GetFilePath(AFileId);
  if Path <> '' then
    try
      // ANSI: source files are strict 7-bit ASCII / CP125x, matching Doc.Facts.
      Result.Text:= TFile.ReadAllText(Path, TEncoding.ANSI);
    except
      // A missing / locked / unreadable source file is not fatal to the whole-DB
      // pass: leave the line list empty so this ref's receiver stays unresolved
      // (Target=0) rather than aborting resolution for every other ref.
      Result.Clear;
    end;
  FLineCache.Add(AFileId, Result);
end;

function TCallResolver.FindChildOfKind(AParentId: Int64; const AName: string; const AKinds: TSymbolKindSet): TSymbol;
var
  Kids: TList<TSymbol>;
  S   : TSymbol       ;
begin
  Result:= Default(TSymbol);
  Kids  := ChildrenOf(AParentId);
  if Kids = nil then Exit;
  for S in Kids do
    if (S.Kind in AKinds) and SameText(S.Name, AName) then Exit(S);
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

  // The remaining handled kinds require a simple identifier receiver.
  if not IsIdentStart(AReceiverExpr[1]) then Exit; // dotted / complex -> unhandled
  for var i:= 1 to Length(AReceiverExpr) do
    if not IsIdentPart(AReceiverExpr[i]) then Exit; // e.g. 'A.B' chain -> unhandled

  // --- Kind 4: typed LOCAL var 'L.M' -> local's declared type.
  //     Kind 5: PARAM 'AFoo.M' -> param's declared type.
  // Both are children of the enclosing ROUTINE. Try them first (an inner name
  // shadows a field), then fall back to the class fields/properties.
  Member:= FindChildOfKind(ACallRef.EnclosingSymbolId, AReceiverExpr, [skLocalVar, skParam]);
  if Member.Id > 0 then
    Exit(ResolveTypeNameToSymbol(Member.Signature, ACallRef.FileId));

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
end;

end.
