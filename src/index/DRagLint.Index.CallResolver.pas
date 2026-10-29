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
  DRagLint.Core.Interfaces,
  DRagLint.Index.LibraryOracle;

type
  /// <summary>v14 (D5): a set of symbol kinds -- lets the resolver's child scans
  /// filter by "any method-shaped kind" / "any type-defining kind" in one test.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.EnclosingClassChainDeclares (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LexicalParenlessLookup (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LexicalScopeDeclaresValue (DRagLint.Index.CallResolver.pas) (+8 more)</para>
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

  /// <summary>2026-09-23 (with scope, resolver 1.8.0-alpha): how a `with`
  /// entity expression names its target, as far as the resolver types it.</summary>
  /// <remarks>whName is a bare identifier followed by zero or more member
  /// steps (`A`, `A.B.C`); whSelf is `Self`; whTypeCast is `X as T` or `T(X)`;
  /// whCreate is `T.Create(...)`; whUnknown is anything else, and a whUnknown
  /// target can never be typed, so every bare name under it is undecided.</remarks>
  TWithHeadKind = (whUnknown, whName, whSelf, whTypeCast, whCreate);

  /// <summary>One entity of a `with` statement: its source span and the parsed
  /// shape its type is derived from, plus the lazily computed type.</summary>
  /// <remarks>Positions are 1-based line/column in the same coordinates the
  /// index stores refs in (UTF-8 bytes, lone CR normalised). State is 0 while
  /// untyped, 1 while being typed (a cycle guard) and 2 once TypeId is final;
  /// TypeId 0 means the target could not be typed.</remarks>
  TWithEntity = record
    /// <summary>First line of the entity expression.</summary>
    Line    : Integer;
    /// <summary>First column of the entity expression.</summary>
    Col     : Integer;
    /// <summary>Line just past the entity expression's end.</summary>
    EndLine : Integer;
    /// <summary>Column just past the entity expression's end (exclusive).</summary>
    EndCol  : Integer;
    /// <summary>The shape of the expression.</summary>
    HeadKind: TWithHeadKind;
    /// <summary>The head identifier, or the type name of a cast / Create.</summary>
    Head    : string;
    /// <summary>Member names applied after the head, in source order.</summary>
    Steps   : TArray<string>;
    /// <summary>0 untyped, 1 typing in progress, 2 typed.</summary>
    State   : Integer;
    /// <summary>The target's class/record/interface symbol id, 0 when unknown.</summary>
    TypeId  : Int64;
  end;

  /// <summary>One `with` statement of a source file: the span its body covers
  /// and its entities in source order (`with A, B do` is A then B).</summary>
  TWithStatement = record
    /// <summary>First line of the body statement.</summary>
    BodyLine   : Integer;
    /// <summary>First column of the body statement.</summary>
    BodyCol    : Integer;
    /// <summary>Line just past the body's end.</summary>
    BodyEndLine: Integer;
    /// <summary>Column just past the body's end (exclusive).</summary>
    BodyEndCol : Integer;
    /// <summary>The entities, in source order.</summary>
    Entities   : TArray<TWithEntity>;
  end;

  /// <summary>What the `with` scope says about a bare name at one position.</summary>
  /// <remarks>wvNone: no enclosing with target can supply the name -- ordinary
  /// scoping applies. wvMember: the innermost target that declares it is known.
  /// wvUndecided: a target at or inside the winning one could not be typed, or
  /// its surface is incomplete, so the name may be its member; bind nothing.</remarks>
  TWithVerdict = (wvNone, wvMember, wvUndecided);

  /// <summary>What a with target's type declares under one name.</summary>
  /// <remarks>wmValue: a property or field. wmRoutine: a method (own, inherited
  /// or from a helper). wmOther: a class const/var or nested type -- a value no
  /// stream binds. wmUnknown: the answer is not knowable (a TObject/IInterface
  /// member the index does not hold, a member invisible from the ref's unit, or
  /// a value and a routine on one level).</remarks>
  TWithMemberKind = (wmNone, wmValue, wmRoutine, wmOther, wmUnknown);

  /// <summary>2026-09-23 (resolver 1.8.0-alpha): per-run counters of the
  /// with scope, printed on the calls stage's `with-scope:` ResolveLog line.</summary>
  /// <remarks>The scope only ever REMOVES or RETARGETS a binding the ordinary
  /// rungs would have made, so its declines are as important to see as its
  /// bindings. Files counts the sources parsed for their with statements.</remarks>
  TWithScopeStats = record
    /// <summary>Bare call refs bound to a with target's method.</summary>
    CallBound       : Int64;
    /// <summary>Bare call refs left unbound because the with scope was undecided
    /// or named a non-routine / ambiguous member.</summary>
    CallDeclined    : Int64;
    /// <summary>Receivers typed through a with target's member.</summary>
    ReceiverTyped   : Int64;
    /// <summary>Receivers left untyped because the with scope was undecided.</summary>
    ReceiverDeclined: Int64;
    /// <summary>Source files parsed for their with statements.</summary>
    Files           : Int64;
    /// <summary>With statements found in them.</summary>
    Statements      : Int64;
  end;

  /// <summary>2026-09-23 (resolver 1.8.0-alpha, D14 + D16a): per-run counters of
  /// the bare member-read pass, printed on the `member-reads:` ResolveLog line.</summary>
  /// <remarks>Bound + every decline = the refs the pass was asked about.</remarks>
  TMemberReadStats = record
    /// <summary>Bound to a with target's property or field.</summary>
    BoundWith : Int64;
    /// <summary>Bound to a member of the enclosing class or an ancestor: a
    /// property (D16a) or field (DEC-19, resolver 1.12.0-alpha) read bare, or
    /// either read as `Self.X`.</summary>
    BoundOwn  : Int64;
    /// <summary>Declined: the with scope was undecided.</summary>
    WithScope : Int64;
    /// <summary>Declined: the with member is a routine or a const, not a property/field.</summary>
    NotMember : Int64;
    /// <summary>Declined: a local, parameter or nested routine shadows the name.</summary>
    Shadowed  : Int64;
    /// <summary>Declined: no property or field of the name on the class chain.</summary>
    NotFound  : Int64;
    /// <summary>Declined: the NEAREST member of the name on the class chain is
    /// a method, class const/var or nested type, which hides any farther field
    /// (E5 review, resolver 1.12.0-alpha).</summary>
    Hidden    : Int64;
    /// <summary>Declined: a receiver other than Self qualifies the name.</summary>
    Qualified : Int64;
    /// <summary>Declined: the source line could not be read, or the file is stale.</summary>
    Unreadable: Int64;
  end;

  /// <summary>2026-09-23 (resolver 1.8.0-alpha): the with scope's state for one
  /// resolver run, grouped so the resolver's own field list stays readable.</summary>
  /// <remarks>Owned by TCallResolver: created in its constructor, freed in its
  /// destructor. Not thread-safe, like the resolver.</remarks>
  TWithScopeState = record
    /// <summary>Source file id -> its `with` statements, parsed once per file
    /// per run. A file whose text holds no `with` keyword maps to an empty
    /// array and is never parsed. The arrays are shared references, so an
    /// entity's lazily computed type is cached in place.</summary>
    Statements     : TDictionary<Int64, TArray<TWithStatement>>;
    /// <summary>Type symbol id -> True when every ancestor of it is in this
    /// index (or is TObject / IInterface), so a name missing from its surface
    /// is really missing. The same target is asked about many names.</summary>
    SurfaceComplete: TDictionary<Int64, Boolean>;
    /// <summary>The run's counters.</summary>
    Stats          : TWithScopeStats;
  end;

  /// <summary>2026-09-23 (resolver 1.8.0-alpha): symbol rows and transitive
  /// ancestor lists, read from the store once per run.</summary>
  /// <remarks>Sound because the calls stage writes call_edges, refs.symbol_id
  /// and member_accesses and never a symbol or an ancestry row, so neither can
  /// change under the pass. The with scope and the member-read stream consult
  /// both per ref; uncached, they took the stage on ORM3 CLIENT from 276 s to
  /// 474 s -- cached, it runs in 69 s. Owned by TCallResolver.</remarks>
  TResolverRowCache = record
    /// <summary>Symbol id -> its row (Default(TSymbol) when absent).</summary>
    Symbols  : TDictionary<Int64, TSymbol>;
    /// <summary>Type symbol id -> GetTransitiveAncestors' answer.</summary>
    Ancestors: TDictionary<Int64, TArray<TTypeAncestor>>;
  end;

  /// <summary>D13 (resolver 1.8.0-alpha): per-run counters of the write-ref
  /// pass, printed on the calls stage's `writes:` ResolveLog line.</summary>
  /// <remarks>
  /// Every DECLINE is counted by reason, for the reason the parenless counters
  /// give: a declined write stores nothing, so these numbers are its only
  /// trace. Bound + the seven declines = the write refs the pass was asked about.
  /// </remarks>
  TWriteResolveStats = record
    /// <summary>Writes whose refs.symbol_id was set.</summary>
    Bound     : Int64;
    /// <summary>Declined: `Result:=` -- an implicit variable with no symbol row.</summary>
    ResultVar : Int64;
    /// <summary>Declined: the name of the enclosing function, or of a function
    /// around it -- a result assignment, which has no symbol row either.</summary>
    OwnName   : Int64;
    /// <summary>Declined: an enclosing `with` target may supply the name -- it
    /// cannot be typed, its surface leaves the index, or its member of the name
    /// is a class const/var or nested type.</summary>
    WithScope : Int64;
    /// <summary>Declined: two or more declarations are equally near (two used
    /// units, or a value and a routine/type of one name in one scope).</summary>
    Ambiguous : Int64;
    /// <summary>Declined: nothing of the name is visible in this index -- an
    /// RTL/VCL global, or a unit the project index does not hold.</summary>
    NotFound  : Int64;
    /// <summary>Declined: the nearest declaration is a routine, type or enum
    /// value, never a variable.</summary>
    Routine   : Int64;
    /// <summary>Declined: the source line could not be read, or the file no
    /// longer matches the index.</summary>
    Unreadable: Int64;
  end;

  /// <summary>B-28: per-run counters of the bare value-read pass, printed on the
  /// calls stage's `value-reads:` ResolveLog line.</summary>
  /// <remarks>
  /// Every DECLINE is counted by reason: a declined read stores nothing, so
  /// these numbers are its only trace. Bound + the nine declines = the read
  /// refs the pass was asked about.
  /// </remarks>
  TValueReadStats = record
    /// <summary>Reads whose refs.symbol_id was set to a local, param, const or var.</summary>
    Bound     : Int64;
    /// <summary>Declined: `Result` -- an implicit variable with no symbol row.</summary>
    ResultVar : Int64;
    /// <summary>Declined: the name of an enclosing function (its result).</summary>
    OwnName   : Int64;
    /// <summary>Declined: an enclosing `with` target may supply the name.</summary>
    WithScope : Int64;
    /// <summary>Declined: the name is a property or field -- the member-read
    /// stream's binding, which also writes the member_accesses row.</summary>
    Member    : Int64;
    /// <summary>Declined: two or more declarations are equally near.</summary>
    Ambiguous : Int64;
    /// <summary>Declined: nothing of the name is visible in this index.</summary>
    NotFound  : Int64;
    /// <summary>Declined: the nearest declaration is a routine, type or enum value.</summary>
    Routine   : Int64;
    /// <summary>Declined: a receiver qualifies the read (`A.X`, `Self.X`).</summary>
    Qualified : Int64;
    /// <summary>Declined: the scope walk answered from the class or unit, but an
    /// enclosing routine's text declares the name in a way the index does not
    /// list (a local or inline const, an inline var).</summary>
    Unlisted  : Int64;
    /// <summary>Declined: the source line could not be read, or the file no
    /// longer matches the index.</summary>
    Unreadable: Int64;
  end;

  /// <summary>B-31: per-run counters of the type_use pass, printed on the calls
  /// stage's `type-uses:` ResolveLog line.</summary>
  /// <remarks>Bound + the six declines = the type_use refs the pass was asked about.</remarks>
  TTypeUseStats = record
    /// <summary>type_use refs whose refs.symbol_id was set.</summary>
    Bound     : Int64;
    /// <summary>Declined: a generic parameter of an enclosing type or routine.</summary>
    Generic   : Int64;
    /// <summary>Declined: the name is qualified (`Unit.TType`, `TOuter.TInner`).</summary>
    Qualified : Int64;
    /// <summary>Declined: an enclosing routine's text declares the name as a
    /// local type, which the index does not list.</summary>
    Unlisted  : Int64;
    /// <summary>Declined: two or more used units declare the name.</summary>
    Ambiguous : Int64;
    /// <summary>Declined: no visible type of the name is in this index (an RTL
    /// type, or a unit the index does not hold).</summary>
    NotFound  : Int64;
    /// <summary>Declined: the source line could not be read, or the file no
    /// longer matches the index.</summary>
    Unreadable: Int64;
  end;

  /// <summary>Lane rb5-ovl: what an argument at a call site IS, as far as the
  /// overload narrowing can tell without a type checker -- a literal or
  /// constructor of a fixed kind, or a plain identifier whose declared type is
  /// a built-in scalar or string type.</summary>
  /// <remarks>asUnknown is every other expression (a call, an operator, a cast,
  /// an identifier of a type the narrowing does not classify); it never rules a
  /// candidate out. The *Var shapes are identifiers typed through
  /// TypeReceiver.</remarks>
  TArgShape = (asUnknown, asIntLit, asFloatLit, asStrLit, asCharLit, asBoolLit,
    asNilLit, asSetLit, asIntVar, asFloatVar, asStrVar, asCharVar, asBoolVar);

  /// <summary>Item 4 (resolver 1.16.0-alpha, spec 2026-10-28-untypable-receivers
  /// s.4.1): the receiver's declared type as TEXT, as far as the ladder reached
  /// it -- whether or not that type has a symbol in this index.</summary>
  /// <remarks>Text is leaf-normalised (NormalizeTypeLeaf). Pending holds the
  /// chain segments after Text the ladder could not step. Head is set instead
  /// when no project rung could type the receiver's HEAD identifier and the
  /// receiver is a plain identifier chain: the chain itself, for the library
  /// oracle to read as a type, a global or a unit-qualified type.</remarks>
  TRcvTypeText = record
    /// <summary>The declared type the ladder reached, leaf-normalised; '' none.</summary>
    Text   : string;
    /// <summary>Dot-joined segments after Text that could not be stepped; ''.</summary>
    Pending: string;
    /// <summary>An identifier-chain receiver whose head no project rung typed; ''.</summary>
    Head   : string;
  end;

  /// <summary>Item 4: per-run receiver counters, printed on the calls stage's
  /// `receivers:` ResolveLog line.</summary>
  /// <remarks>Only qualified sites (a receiver other than '' / Self) count.
  /// TypedLocal + TypedByNameOnly + Untyped = the qualified sites resolved.</remarks>
  TReceiverStats = record
    /// <summary>The receiver typed to a symbol of THIS index.</summary>
    TypedLocal     : Int64;
    /// <summary>The receiver's type is known by NAME only (no symbol here).</summary>
    TypedByNameOnly: Int64;
    /// <summary>Neither: '' was recorded.</summary>
    Untyped        : Int64;
  end;

  /// <summary>v14 (D5): receiver-typing + method-chain call resolver. Prepare  /// once (Create builds the name-candidate + file-scope maps from the whole DB),
  /// then call ResolveOne per call-site ref.</summary>
  /// <remarks>
  /// Not thread-safe; single owning thread only. Holds the ISymbolStore
  /// for the resolver's lifetime -- the store must outlive the resolver.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.ResolveEnumValueRefs (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.ResolveMemberReadRefs (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.ResolveParenlessCallRefs (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.ResolveWriteRefs (DRagLint.Storage.SQLite.pas) (+3 more)</para>
  /// <para>Used in units: DRagLint.Storage.SQLite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCallResolver = class
  strict private type
    /// <summary>D13: the scope facts of ONE enclosing routine that the write
    /// pass consults for every write inside it, computed once per pass.</summary>
    /// <remarks>Chain is the routine and the routines around it, innermost
    /// first; FnNames the lowercased names of the functions/methods on it as
    /// '|a|b|'; ClassChain the owning type then its resolved ancestors, nearest
    /// first. Cached because building it costs a store round-trip per lexical
    /// level and a type_ancestors walk, and a routine holds many writes. (The
    /// routine's first line, which the pre-merge "any `with` above" scan read,
    /// went with that scan: the with scope is WithScopeAt's, per position.)</remarks>
    TWriteScope = record
      Chain     : TArray<Int64>;
      FnNames   : string;
      ClassChain: TArray<Int64>;
    end;
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
    // SHADOW set of the enum-value pass's rule R3(c) -- a hit there makes that
    // pass DECLINE -- and the CANDIDATE set of the bare write pass's unit rungs
    // (D13, UnitScopeWriteTarget) and of rung 3d (D22, LookupUnitQualifiedValue).
    FNameToUnitValues: TObjectDictionary<string, TList<TSymbol>>;
    // 2026-09-23: per-run counters of the enum-value pass. Every decline is
    // counted by reason, because a pass that answers `certain` or nothing leaves
    // no other trace of what it refused.
    FEnumStats       : TEnumResolveStats;
    // 2026-09-24 (D22, ruling R13): rung 3d bindings, counted APART from
    // FEnumStats.Bound because a unit var/const is not an enum value -- the
    // calls stage reconciles each against what it wrote.
    FUnitValueBound  : Int64;
    // 2026-09-24 (D22, R14 review): rung 3c `Unit.enumValue` refs the
    // UnshadowedUnitFile gate declined although the receiver names one unit.
    FEnumUnitGateDeclined: Int64;
    // 2026-09-23: per-run counters of the parenless-call pass, same reason.
    FParenlessStats  : TParenlessResolveStats;
    // 2026-09-23 (D13): per-run counters of the write-ref pass, same reason.
    FWriteStats      : TWriteResolveStats;
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
    // 2026-09-23 (resolver 1.8.0-alpha): the with scope's per-run state -- see
    // TWithScopeState.
    FWith           : TWithScopeState;
    // rb5-ovl: the call site ResolveOne is resolving, so PickFromMatches can read
    // its argument SHAPES lazily -- only when arity leaves a tie. FSiteLines is
    // nil outside ResolveOne's site (and FSiteArgCount -1 when arity is
    // unknown); FSiteShapesState is 0 = not read yet, 1 = read, 2 = unreadable.
    FSiteRef        : TReference;
    FSiteLines      : TStringList;
    FSiteArgCount   : Integer;
    FSiteShapes     : TArray<TArgShape>;
    FSiteShapesState: Integer;
    // Per-run counters of the bare member-read pass.
    FMemberReadStats: TMemberReadStats;
    // 1.8.0: symbol rows and ancestor lists, read once per run -- see
    // TResolverRowCache.
    FRows           : TResolverRowCache;
    // ENG-16: lowercased receiver text -> UnitNameToFileId's answer, so rung 4b
    // asks the store once per distinct receiver rather than once per call site.
    FUnitFileOf : TDictionary<string, Int64>;
    // D13: enclosing routine id -> its TWriteScope, built on first use.
    FWriteScopes: TDictionary<Int64, TWriteScope>;
    // B-28: counters of the bare value-read pass.
    FValueReadStats: TValueReadStats;
    // B-28: routine id -> '|name|...|' its text declares as a const or an
    // inline const/var, lowercased; built on first use (LocalDeclNamesOf).
    FLocalDecls: TDictionary<Int64, string>;
    // B-31: counters of the type_use pass.
    FTypeUseStats: TTypeUseStats;
    // B-31: file id -> its type symbols and its root (unit/program) symbol.
    FFileTypes: TDictionary<Int64, TArray<TSymbol>>;
    { Item 4: the library oracle over FExtraStores (no stores -> every Bind is no-store), the
      receiver counters, and the lower-cased uses list per file (+ the .dpr's, loaded once). }
    FOracle   : TLibraryOracle;
    FReceiverStats : TReceiverStats;
    FFileUses : TDictionary<Int64, TArray<string>>;
    FDprUses  : TArray<string>;
    FDprLoaded: Boolean;

    /// <summary>The type a bare type name at ARef names, by Delphi's scope order;
    /// the shared lookup behind ResolveTypeUse and ResolveEnumCast.</summary>
    /// <param name="ARef">The ref naming the type; FileId, NameText, StartLine, StartCol and
    /// EnclosingSymbolId are consulted.</param>
    /// <param name="AReason">OUT: '' when found; otherwise 'unreadable' | 'qualified' |
    /// 'generic' | 'unlisted' | 'ambiguous' | 'not-found'.</param>
    /// <returns>The class / interface / record / type / enum id, or 0.</returns>
    /// <remarks>Counts nothing: each public caller keeps its own counters.</remarks>
    function LookupTypeName(const ARef: TReference; out AReason: string): Int64;

    /// <summary>The names ARoutineId's implementation text declares in a const
    /// or type section, or as an inline const / var -- declarations the extractor
    /// does not emit as symbols -- as '|name|...|', lowercased and cached.</summary>
    /// <param name="ARoutineId">A routine symbol; its ImplStartLine..ImplEndLine
    /// is scanned, nested routines included (a wider set only declines more).</param>
    /// <param name="AFileId">The file holding that implementation.</param>
    /// <returns>'|' when nothing is declared or the text cannot be read.</returns>
    function LocalDeclNamesOf(ARoutineId, AFileId: Int64): string;
    /// <summary>Review 2026-10-23: whether the scope of ADecl, a local
    /// variable or parameter, covers position (ALine, ACol).</summary>
    /// <param name="ADecl">A local_var or param symbol of the routine at the site.</param>
    /// <param name="AFileId">The file holding the site and the declaration.</param>
    /// <param name="ALine">The site's line.</param>
    /// <param name="ACol">The site's column.</param>
    /// <returns>True for a parameter; for a var-section variable declared at or
    /// before the site (an anonymous method's var section can follow it). For an INLINE `var` it is True only when the declaration lies
    /// at or before the site and the block it sits in -- a `for var` loop's body,
    /// else the enclosing begin/try/case/repeat block -- has not closed before
    /// the site. False when the text cannot be read.</returns>
    /// <remarks>Text-based, conservative: a block shape it does not model reads
    /// as closed, which only declines.</remarks>
    function LocalScopeCovers(const ADecl: TSymbol; AFileId: Int64; ALine, ACol: Integer): Boolean;
    /// <summary>Review 2026-10-23 (W5-res2): the local or parameter named AName
    /// of ARef's enclosing routine that ARef's site sees -- the nearest
    /// declaration at or before the site whose block covers it, the rule
    /// ScopeWriteTarget applies to value reads and writes. Used to type a
    /// receiver, so two same-name inline vars never type it from the first.</summary>
    /// <param name="ARef">EnclosingSymbolId, FileId, StartLine and StartCol are
    /// consulted.</param>
    /// <param name="AName">The identifier, matched case-insensitively.</param>
    /// <param name="ADeclared">True when the routine declares a local or
    /// parameter of that name at all, whether or not it covers the site.</param>
    /// <returns>The declaration in scope at the site; a zero-Id symbol when none
    /// is declared or none covers the site.</returns>
    /// <remarks>ADeclared with a zero-Id result is 'ambiguous': the caller
    /// declines, and the name still shadows fields, unit values and types.</remarks>
    function LocalInScopeAt(const ARef: TReference; const AName: string; out ADeclared: Boolean): TSymbol;
    /// <summary>Review 2026-10-23 (N-07, W5-res2): whether ARef sits inside an
    /// anonymous method's body within its enclosing routine, and the declared
    /// return type of the innermost one.</summary>
    /// <param name="ARef">FileId, StartLine, StartCol and EnclosingSymbolId are
    /// consulted.</param>
    /// <param name="AReturnType">The innermost open anonymous method's return
    /// type text, lowercased with blanks removed (`tlist<tjob>`); '' for an
    /// anonymous procedure, outside one, or when it cannot be read.</param>
    /// <returns>True inside an anonymous `function` / `procedure` body (or its
    /// header), and when the routine's text cannot be read; False otherwise.</returns>
    /// <remarks>An anonymous method is a `function` / `procedure` keyword right
    /// after `:=`, `(`, `,` or `[`; its body runs from its `begin` to the
    /// matching `end`.</remarks>
    function InsideAnonymousMethod(const ARef: TReference; out AReturnType: string): Boolean;
    /// <summary>Review 2026-10-23 (W5-res2): the type of the implicit `Result`
    /// at ARef -- the enclosing routine's declared return type, unless ARef sits
    /// in an anonymous method whose own return type is not textually the same
    /// (then that `Result` is the anonymous method's, of another type).</summary>
    /// <param name="ARef">FileId, StartLine, StartCol and EnclosingSymbolId are
    /// consulted.</param>
    /// <param name="ADeclined">True when ARef is inside an anonymous method
    /// whose return type cannot be shown equal to the routine's.</param>
    /// <returns>The return type text; '' when declined, for a procedure, or
    /// for a signature shape SignatureReturnType does not read.</returns>
    /// <remarks>Equality is on text after StripUnitQualifiers (case, blanks and
    /// unit qualification ignored): `uX.TFoo` equals `TFoo` and
    /// `System.Integer` equals `Integer`; a qualified OTHER type still
    /// declines.</remarks>
    function ResultTypeAt(const ARef: TReference; out ADeclined: Boolean): string;
    /// <summary>B-35 lane R (W5-res2 residue): ATypeText lowercased, blanks
    /// removed, and every dotted identifier chain stripped of its longest
    /// leading run of segments that names a unit.</summary>
    /// <param name="ATypeText">A type spelling, e.g. `uX.TList<System.Integer>`.</param>
    /// <returns>The normalised text, e.g. `tlist<integer>`.</returns>
    /// <remarks>A prefix is a unit when UnitNameToFileId finds exactly one unit
    /// of that name, or it is `System` (always in scope). A nested-type prefix
    /// (`TOuter.TInner`) names no unit and is kept, so two different nested
    /// types never compare equal.</remarks>
    function StripUnitQualifiers(const ATypeText: string): string;

    /// <summary>The type symbols of AFileId and its root symbol (the one with no
    /// parent), read once per file and cached.</summary>
    /// <param name="AFileId">An indexed file.</param>
    /// <returns>An empty array when the file has no symbols.</returns>
    function FileTypesOf(AFileId: Int64): TArray<TSymbol>;
    /// <summary>The scope a ref sits in: its enclosing symbol, else the
    /// innermost type of its file whose lines span it, else the file's root.</summary>
    /// <param name="ARef">FileId, StartLine and EnclosingSymbolId are consulted.</param>
    /// <returns>Default(TSymbol) when the file has no symbols.</returns>
    function ScopeSymbolAt(const ARef: TReference): TSymbol;

    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.Create (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetEnumValueSymbols, DRagLint.Core.Interfaces.ISymbolStore.GetTypeCandidates, DRagLint.Core.Interfaces.ISymbolStore.GetUnitLevelRoutines, DRagLint.Core.Interfaces.ISymbolStore.GetUnitLevelValueDecls, DRagLint.Core.Interfaces.ISymbolStore.GetUnitScopeEdges, LowerCase</para>
    /// <para>Complexity: 10 (cyclomatic, outer body), 52 lines (full implementation)</para>
    /// <para>Reads: FStore, FNameToCands, FNameToRoutines, FNameToEnumValues, FNameToUnitValues, FFileScope</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetEnumValueSymbols"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetTypeCandidates"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetUnitLevelRoutines"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetUnitLevelValueDecls"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetUnitScopeEdges"/>
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
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.AddVisibleUnitRoutines (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.AssignedTypeText (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LookupUnitLevelRoutine (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveTypeNameToSymbol (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveTypeUse (DRagLint.Index.CallResolver.pas) (+6 more)</para>
    /// <para>Reads: FFileScope</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddMethodsOnTypeChain"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddVisibleUnitRoutines"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AncestorsOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AssignedTypeText"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BareCallInNearScopes"/>
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
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.IsProceduralTypeText (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.TypeOfMember (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.TypeOfOrdinaryName (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.TypeReceiver (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.WithEntityType (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: Copy, DRagLint.Index.CallResolver.TCallResolver.CandInScope, LowerCase, Pos, Trim</para>
    /// <para>Complexity: 11 (cyclomatic, outer body), 35 lines (full implementation)</para>
    /// <para>Reads: FNameToCands</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.CandInScope"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddMethodsOnTypeChain"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddVisibleUnitRoutines"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AncestorsOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AssignedTypeText"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ResolveTypeNameToSymbol(const ATypeText: string; ADeclFileId: Int64): Int64;
    /// <summary>Item 4 (replaces v21's ResolveExternally): offers a site the
    /// primary index could not bind to the library oracle, and answers with a
    /// QUALIFIED NAME or ''. The type text the oracle gets: the receiver's
    /// type text; for a PROJECT type, its first library ancestor's name (only
    /// when the project chain declares no member of the name); for an untyped
    /// identifier-chain head, the chain (BindHead); for a bare call, the
    /// enclosing class's library ancestor, then a library routine.</summary>
    /// <param name="ACallRef">The site.</param>
    /// <param name="AReceiver">Its receiver text ('' bare).</param>
    /// <param name="ATypeId">The receiver's type id in this index, 0 when untyped.</param>
    /// <param name="AText">The receiver's type text; BindHead may fill Text.</param>
    /// <returns>The qualified name of the library member, or ''.</returns>
    function BindExternally(const ACallRef: TReference; const AReceiver: string; ATypeId: Int64;
      var AText: TRcvTypeText): string;
    /// <summary>Item 4: the name of the FIRST ancestor of ATypeId (transitive,
    /// breadth-first) this index could not resolve -- a class-position (ordinal
    /// 0) edge before any other.</summary>
    /// <param name="ATypeId">A project type id.</param>
    /// <returns>The ancestor name as written, or '' when every ancestor resolved.</returns>
    function FirstUnresolvedAncestorName(ATypeId: Int64): string;
    /// <summary>Item 4: True when ATypeId or a resolved ancestor declares a
    /// member spelled AName -- the project's own answer, which an external
    /// name must never override.</summary>
    /// <param name="ATypeId">A project type id.</param>
    /// <param name="AName">The member name.</param>
    /// <returns>True when some type on the project chain declares it.</returns>
    function ChainDeclaresName(ATypeId: Int64; const AName: string): Boolean;
    /// <summary>Item 4: lower-cased unit names AFileId uses (both sections)
    /// plus the uses of every .dpr in the index; cached per file.</summary>
    /// <param name="AFileId">The referencing file.</param>
    /// <returns>The names, lower-cased.</returns>
    function FileUsesUnits(AFileId: Int64): TArray<string>;    /// <summary>Direct children of AParentId (cached). Empty when none / 0.</summary>
    /// <param name="AParentId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto -->TList&lt;TSymbol&gt; -- Observed:
    /// TList&lt;TSymbol&gt;.Create.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LevelMemberKind (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LexicalParenlessLookup (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LexicalScopeDeclaresValue (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LocalInScopeAt (DRagLint.Index.CallResolver.pas) (+6 more)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols</para>
    /// <para>Reads: FChildCache, FStore</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddMethodsOnTypeChain"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddVisibleUnitRoutines"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AncestorsOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AssignedTypeText"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ChildrenOf(AParentId: Int64): TList<TSymbol>;
    /// <summary>The source lines of the file AFileId (cached, ANSI). Nil-safe.</summary>
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto -->TStringList -- Observed: TStringList.Create.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.BareReadSite (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.FileIsStaleProbe (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.InsideAnonymousMethod (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LocalDeclNamesOf (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LocalScopeCovers (DRagLint.Index.CallResolver.pas) (+5 more)</para>
    /// <para>Calls: DateTimeToUnix, DRagLint.Core.Interfaces.ISymbolStore.FileIsUpToDate, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath</para>
    /// <para>Reads: FLineCache, FStore, FStaleFiles</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <para>Touches: file system</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FileIsUpToDate"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddMethodsOnTypeChain"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddVisibleUnitRoutines"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AncestorsOf"/>
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
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.BareReadSite (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.FileIsStaleProbe (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveAccessor (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveWriteRef (DRagLint.Index.CallResolver.pas) (+1 more)</para>
    /// <para>Reads: FStaleFiles</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddMethodsOnTypeChain"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddVisibleUnitRoutines"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AncestorsOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AssignedTypeText"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BareCallInNearScopes"/>
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
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.ClassChainParenlessLookup (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.EnclosingClassChainDeclares (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LookupMemberOnType (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.NearestClassMember (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.QualifiedValueTarget (DRagLint.Index.CallResolver.pas) (+3 more)</para>
    /// <para>Calls: Default, DRagLint.Index.CallResolver.TCallResolver.ChildrenOf, SameText</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddMethodsOnTypeChain"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddVisibleUnitRoutines"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AncestorsOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AssignedTypeText"/>
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
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.LookupMethodOnType (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LookupUnitLevelRoutine (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.LookupUnitQualifiedRoutine (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveParenlessRead (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: DRagLint.Index.CallResolver.SignatureArityRange</para>
    /// <para>Complexity: 10 (cyclomatic, outer body), 52 lines (full implementation)</para>
    /// <para>Mutates: AConfidence (out)</para>
    /// <seealso cref="DRagLint.Index.CallResolver.SignatureArityRange"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddMethodsOnTypeChain"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddVisibleUnitRoutines"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AncestorsOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AssignedTypeText"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function PickFromMatches(AMatches: TList<TSymbol>; AArgCount: Integer;
      AArgsKnown: Boolean; out AConfidence: string): Int64;
    /// <summary>rb5-ovl: drops from AFit every candidate that some argument at
    /// the current call site cannot be passed to (ArgFitsParam answers no).</summary>
    /// <param name="AFit">Candidates that already fit by arity; narrowed in place.</param>
    /// <param name="AArgCount">The site's argument count; the site's own lexed
    /// list must agree with it or nothing is narrowed.</param>
    /// <remarks>NARROWING ONLY: AFit changes only when at least one candidate
    /// survives and at least one is dropped. A candidate whose parameter groups
    /// do not agree with its arity range is never dropped.</remarks>
    procedure NarrowByArgShapes(AFit: TList<TSymbol>; AArgCount: Integer);
    /// <summary>rb5-ovl: the argument shapes of the site ResolveOne is on, read
    /// once per site with LexCallArguments.</summary>
    /// <param name="AArgCount">The count arity was decided on.</param>
    /// <param name="AShapes">Out: one shape per argument.</param>
    /// <returns>False outside ResolveOne, for a site that does not lex, or when
    /// the lexed count differs from AArgCount.</returns>
    function SiteArgShapes(AArgCount: Integer; out AShapes: TArray<TArgShape>): Boolean;
    /// <summary>rb5-ovl: the shape of a bare-identifier argument, from its
    /// declared type as TypeReceiver reads it at the current site.</summary>
    /// <param name="AName">The identifier.</param>
    /// <returns>An *Var shape for a built-in scalar or string type; asUnknown
    /// otherwise.</returns>
    /// <remarks>Restores the with-scope counters TypeReceiver bumps, so the
    /// run's statistics are not inflated by these probes.</remarks>
    function VariableArgShape(const AName: string): TArgShape;
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
    /// <para>X2 (resolver 1.14.0-alpha, owner ruling 2026-09-16): on a CLASS or
    /// RECORD, the interfaces its heritage names are NOT searched while the
    /// type's own chain declares the method -- an implemented interface's method
    /// is not a member of the class, so `C.M` with `C: TImpl` binds TImpl.M
    /// 'certain' instead of 'ambiguous' against IFoo.M. Only when the class chain
    /// declares nothing (the implementation lives in an unindexed ancestor) do
    /// those interfaces answer, as before. An INTERFACE receiver searches its
    /// interface ancestors as always, so an interface-dispatched call binds the
    /// interface method and never an implementor. Pinned by
    /// tests\callresolve\run_interface_dispatch_bind.ps1.</para>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.BareCallInNearScopes (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.TypeOfMember (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.WithMemberKind (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: DRagLint.Index.CallResolver.TCallResolver.AncestorsOf, DRagLint.Index.CallResolver.TCallResolver.ChildrenOf, DRagLint.Index.CallResolver.TCallResolver.LookupMethodOnType.AddHelperMethods, DRagLint.Index.CallResolver.TCallResolver.PickFromMatches, SameText</para>
    /// <para>Complexity: 14 (cyclomatic, outer body), 100 lines (full implementation)</para>
    /// <para>Mutates: AConfidence (out)</para>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AncestorsOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.LookupMethodOnType.AddHelperMethods"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.PickFromMatches"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddMethodsOnTypeChain"/>
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
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.AssignedTypeText (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ClassChainParenlessLookup (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.EnclosingClassChainDeclares (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveBareMemberRead (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas) (+4 more)</para>
    /// <para>Calls: Default, DRagLint.Index.CallResolver.TCallResolver.AncestorsOf, DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AncestorsOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddMethodsOnTypeChain"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddVisibleUnitRoutines"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AssignedTypeText"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function LookupMemberOnType(ATypeSymbolId: Int64; const AMemberName: string): TSymbol;
    /// <summary>E5 review (resolver 1.12.0-alpha): the declaration a bare name
    /// inside AClassId's methods meets FIRST on the class chain -- the type
    /// itself, then its CLASS parent (the ordinal-0 heritage edge), then that
    /// one's, nearest first -- of ANY member kind: field, property, method,
    /// class const / var, nested type.</summary>
    /// <param name="AClassId">The enclosing class, record or helper.</param>
    /// <param name="AName">The bare name, compared case-insensitively.</param>
    /// <returns>The nearest declaration, or an empty TSymbol (Id = 0) when the
    /// chain declares no member of the name, or when the walk reaches an
    /// ancestor it cannot resolve before finding one.</returns>
    /// <remarks>Delphi's nearest member HIDES every farther one whatever their
    /// kinds, so a caller binds only when the returned member is itself a value
    /// it can bind -- a method or const of the name in TMid hides a field in
    /// TBase. An unresolved (or ambiguous) parent ENDS the walk: it may declare
    /// the name itself, so nothing beyond it is offered. Interfaces in the
    /// heritage list are never walked -- their members are not in the class's
    /// scope. Pure over the resolver's cached rows.</remarks>
    function NearestClassMember(AClassId: Int64; const AName: string): TSymbol;
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
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddMethodsOnTypeChain"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddVisibleUnitRoutines"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AncestorsOf"/>
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
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddMethodsOnTypeChain"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddVisibleUnitRoutines"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AncestorsOf"/>
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
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.ResolveBareMemberRead (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: Default, DRagLint.Index.CallResolver.AccessorIdentAfter, DRagLint.Index.CallResolver.PropertyIndexArity, DRagLint.Index.CallResolver.TCallResolver.AncestorsOf, DRagLint.Index.CallResolver.TCallResolver.FileIsStale, DRagLint.Index.CallResolver.TCallResolver.LinesOf, DRagLint.Index.CallResolver.TCallResolver.PickAccessor, Min</para>
    /// <para>Complexity: 17 (cyclomatic, outer body), 42 lines (full implementation)</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Index.CallResolver.AccessorIdentAfter"/>
    /// <seealso cref="DRagLint.Index.CallResolver.PropertyIndexArity"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AncestorsOf"/>
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
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.BareCallInNearScopes (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: DRagLint.Index.CallResolver.TCallResolver.ChildrenOf, DRagLint.Index.CallResolver.TCallResolver.SymbolById, SameText</para>
    /// <para>Returns: 0; Matches[0].Id</para>
    /// <para>Complexity: 14 (cyclomatic, outer body), 55 lines (full implementation)</para>
    /// <para>Mutates: AConfidence (out)</para>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.ChildrenOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.SymbolById"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddMethodsOnTypeChain"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddVisibleUnitRoutines"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AncestorsOf"/>
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
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddMethodsOnTypeChain"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddVisibleUnitRoutines"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AncestorsOf"/>
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
    /// <returns><!-- drag-lint:auto -->Int64 -- Observed: 0;
    /// TypeReceiverThroughWith(ACallRef, AReceiverExpr, WithHandled); Encl.ParentId;
    /// ResolveTypeNameToSymbol(CastType, ACallRef.FileId);
    /// ResolveTypeNameToSymbol(Segs[High(Segs)], ACallRef.FileId);
    /// ResolveTypeNameToSymbol(Member.Signature, ACallRef.FileId);
    /// TypeOfOrdinaryName(ACallRef, AReceiverExpr).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.AssignedTypeText (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.CalleeTakesProcedural (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.TypeReceiver (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: DRagLint.Index.CallResolver.IsIdentChain, DRagLint.Index.CallResolver.IsIdentPart, DRagLint.Index.CallResolver.IsIdentStart, DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind, DRagLint.Index.CallResolver.TCallResolver.LocalInScopeAt, DRagLint.Index.CallResolver.TCallResolver.LookupMemberOnType, DRagLint.Index.CallResolver.TCallResolver.ResolveTypeNameToSymbol, DRagLint.Index.CallResolver.TCallResolver.ResultTypeAt, DRagLint.Index.CallResolver.TCallResolver.SymbolById, DRagLint.Index.CallResolver.TCallResolver.TypeOfOrdinaryName, DRagLint.Index.CallResolver.TCallResolver.TypeReceiver, DRagLint.Index.CallResolver.TCallResolver.TypeReceiverThroughWith, DRagLint.Index.CallResolver.TryParseCastTarget, Pos, SameText</para>
    /// <para>Complexity: 24 (cyclomatic, outer body), 164 lines (full implementation)</para>
    /// <para>Pure</para>
    /// <para>Recursive</para>
    /// <seealso cref="DRagLint.Index.CallResolver.IsIdentChain"/>
    /// <seealso cref="DRagLint.Index.CallResolver.IsIdentPart"/>
    /// <seealso cref="DRagLint.Index.CallResolver.IsIdentStart"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.FindChildOfKind"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.LocalInScopeAt"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function TypeReceiver(const ACallRef: TReference; const AReceiverExpr: string): Int64; overload;
    /// <summary>Item 4: TypeReceiver that also hands back the receiver's
    /// declared type TEXT, which survives when the type has no symbol here.</summary>
    /// <param name="ACallRef">The ref whose receiver is typed.</param>
    /// <param name="AReceiverExpr">The receiver text.</param>
    /// <param name="AText">The type text (spec s.4.1); empty fields when untyped.</param>
    /// <returns>The receiver type id, or 0.</returns>
    function TypeReceiver(const ACallRef: TReference; const AReceiverExpr: string;
      out AText: TRcvTypeText): Int64; overload;
    /// <summary>X1: the rungs of TypeReceiver, before the implicit pointer
    /// dereference TypeReceiver applies to their answer.</summary>
    /// <param name="ACallRef">The ref whose receiver is typed; supplies the file and enclosing routine.</param>
    /// <param name="AReceiverExpr">The receiver text, as ExtractReceiverExpr returns it.</param>
    /// <param name="AText">Item 4: the declared type text each rung reads before it
    /// resolves the name; it survives when the id is 0.</param>
    /// <returns>The receiver type id, or 0 when no rung can type it.</returns>
    function TypeReceiverCore(const ACallRef: TReference; const AReceiverExpr: string;
      out AText: TRcvTypeText): Int64;
    /// <summary>X1: Delphi's implicit dereference -- `p.K` with p: PRec = ^TRec
    /// reaches TRec.K. Answers the pointee type when ATypeId is a type alias
    /// spelled `^T` and T resolves; otherwise ATypeId unchanged (a pointer type
    /// has no members, so nothing that bound before can change).</summary>
    /// <param name="ATypeId">A type symbol id; 0 or less is returned unchanged.</param>
    /// <returns>The pointee type id, or ATypeId when it is not a resolvable `^T` alias.</returns>
    function DerefPointerAlias(ATypeId: Int64): Int64;
    /// <summary>X1: type a receiver with SELECTORS -- an array element or a
    /// pointer dereference: `A[0]`, `R.Arr[1]`, `pM[X]`, `P^`, `A[0].Inner`.
    /// The head identifier is typed as a value (local / param / Result / own
    /// field or property / the ordinary-name walk), then each `[..]` takes the
    /// element type of an `array [..] of T`, `array of T` or `TArray&lt;T&gt;`
    /// (through type aliases), each `^` the pointee of `^T`, and each `.M` the
    /// declared type of member M.</summary>
    /// <param name="ACallRef">The ref whose receiver is typed; supplies the file and enclosing routine.</param>
    /// <param name="AReceiverExpr">The receiver text holding at least one '[' or '^'.</param>
    /// <returns>The receiver type id, or 0 when any step cannot be read (a
    /// call or cast inside the chain, a subscript on a non-array such as an
    /// indexed property or a string, an untypable head).</returns>
    function TypeOfSelectorChain(const ACallRef: TReference; const AReceiverExpr: string;
      out AText: TRcvTypeText): Int64;
    /// <summary>T-11 kind 12: types a receiver whose chain holds a CALL or a
    /// parenthesised segment -- `O.Mk('a').Leaf`, `(O as TInner).Leaf`,
    /// `SB.Append(x)` -- by typing everything left of the LAST top-level dot
    /// through the full ladder (TypeReceiver, so the head may be any receiver
    /// the ladder reads) and then stepping the last segment as a member of
    /// that type: a field / property to its declared type, a method (with or
    /// without an argument list) to its declared return type.</summary>
    /// <param name="ACallRef">The ref whose receiver is typed (scope, file).</param>
    /// <param name="AReceiverExpr">The receiver text.</param>
    /// <param name="AHandled">True when the receiver has that shape -- the
    /// answer is then final, 0 included; False leaves it to the other rungs.</param>
    /// <returns>The receiver type id, or 0 when any step cannot be typed: an
    /// untyped prefix, an empty segment (a line-scan fragment such as
    /// `.Mk(1).L`), a method that is overloaded or missing, a procedure, a
    /// subscript segment. Never a guess.</returns>
    function TypeOfCallChain(const ACallRef: TReference; const AReceiverExpr: string; out AHandled: Boolean;
      out AText: TRcvTypeText): Int64;
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
    /// <summary>True when a unit-level const/var named ALc -- a VALUE, not a
    /// type or enum value -- is visible from ARefFileId: the own unit (either
    /// section), or the interface of a unit it uses.</summary>
    /// <param name="ARefFileId">The referencing file.</param>
    /// <param name="ALc">The lowercased identifier.</param>
    /// <returns>True when such a value is visible.</returns>
    /// <remarks>RB-4's gate in UnshadowedUnitFile: a value spelled like a unit
    /// is what the compiler reads for `Name.X`, ahead of the unit.</remarks>
    function UnitLevelValueVisible(ARefFileId: Int64; const ALc: string): Boolean;
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
    /// <summary>The symbol row AId, read from the store once per run.</summary>
    /// <param name="AId">A symbols.id of the primary store.</param>
    /// <returns>The row; Default(TSymbol) when there is none.</returns>
    function SymbolById(AId: Int64): TSymbol;
    /// <summary>The transitive ancestors of ATypeId, read from the store once per run.</summary>
    /// <param name="ATypeId">A type symbol id of the primary store.</param>
    /// <returns>The store's GetTransitiveAncestors answer, unchanged.</returns>
    function AncestorsOf(ATypeId: Int64): TArray<TTypeAncestor>;

    { ---- 2026-09-23: the `with` scope (resolver 1.8.0-alpha, D14). ---- }

    /// <summary>The `with` statements of AFileId, parsed once and cached.</summary>
    /// <param name="AFileId">A files.id of the primary store.</param>
    /// <returns>The statements in pre-order (an outer with before the withs
    /// nested in it); empty when the file's text holds no `with` keyword.</returns>
    /// <remarks>A file that names `with` but cannot be read or parsed yields one
    /// statement spanning the whole file with an untypable entity, so every
    /// bare name in it is UNDECIDED -- a missing with table must never read as
    /// "no with here", which would bind names a target may own.</remarks>
    function WithStatementsOf(AFileId: Int64): TArray<TWithStatement>;
    /// <summary>The target type of entity AEnt of statement AStmt, typed on
    /// first use and cached in the shared array.</summary>
    /// <param name="ARef">Supplies the file and the enclosing routine the
    /// entity expression is typed in.</param>
    /// <param name="AStmts">The file's statements, from WithStatementsOf.</param>
    /// <param name="AStmt">Index of the statement.</param>
    /// <param name="AEnt">Index of the entity.</param>
    /// <returns>A class/record/interface symbol id, or 0 when untypable.</returns>
    function WithEntityType(const ARef: TReference; const AStmts: TArray<TWithStatement>;
      AStmt, AEnt: Integer): Int64;
    /// <summary>The type of the member AName of ATypeId: a property's or field's
    /// declared type, or a certain zero-argument function's return type.</summary>
    /// <param name="ATypeId">The owning type.</param>
    /// <param name="AName">The member name.</param>
    /// <returns>The member's type symbol id, or 0.</returns>
    function TypeOfMember(ATypeId: Int64; const AName: string): Int64;
    /// <summary>The type of a bare identifier written at ALine/ACol inside
    /// ARef's enclosing routine: a with member, a local or parameter, a member of
    /// the enclosing class, a visible unit-level var, or a type name.</summary>
    /// <param name="ARef">Supplies the file and the enclosing routine.</param>
    /// <param name="ALine">The identifier's line.</param>
    /// <param name="ACol">The identifier's column.</param>
    /// <param name="AName">The identifier.</param>
    /// <returns>A type symbol id, or 0 when unknown or undecided.</returns>
    function TypeOfBareName(const ARef: TReference; ALine, ACol: Integer; const AName: string): Int64;
    /// <summary>TypeOfBareName's ordinary rungs, once no with target claims the
    /// name: a local or parameter, a member of the enclosing class, a visible
    /// unit-level var, then the name as a type.</summary>
    /// <param name="ARef">Supplies the file and the enclosing routine.</param>
    /// <param name="AName">The identifier.</param>
    /// <returns>A type symbol id, or 0.</returns>
    function TypeOfOrdinaryName(const ARef: TReference; const AName: string): Int64; overload;
    /// <summary>Item 4: TypeOfOrdinaryName that also hands back the RAW declared
    /// type text of the value it found (a local's, a member's, the one unit-level
    /// var's), or the name itself when it resolved as a type.</summary>
    /// <param name="ARef">Supplies the file and the enclosing routine.</param>
    /// <param name="AName">The identifier.</param>
    /// <param name="ATypeText">The raw declaration text, '' when nothing was found.</param>
    /// <returns>A type symbol id, or 0.</returns>
    function TypeOfOrdinaryName(const ARef: TReference; const AName: string; out ATypeText: string): Int64; overload;    /// <summary>X2 (resolver 1.14.0-alpha): the declared RETURN type of the
    /// function a receiver names -- `GetCopy.M`, `MakeCopy.M`,
    /// `MakeCopy().M`.</summary>
    /// <param name="ARef">The call or member ref; supplies the file and the
    /// enclosing routine.</param>
    /// <param name="AName">The function name as written, without its argument
    /// list.</param>
    /// <returns>A type symbol id, or 0 when no routine of the name is visible, a
    /// value of the name shadows it, or the visible candidates lack or disagree
    /// on a return type.</returns>
    /// <remarks>Candidates come from FindParenlessCandidates -- lexical scopes,
    /// the enclosing class chain, then the unit and the interfaces of used units
    /// -- so the shadowing rules are the parenless-call pass's. EVERY candidate
    /// must declare the same return type text, so an overload set types only
    /// when the choice cannot matter. Pinned by
    /// tests\callresolve\run_interface_dispatch_bind.ps1 (IF6-IF8,
    /// CLS3-CLS4).</remarks>
    function TypeOfFunctionResult(const ARef: TReference; const AName: string): Int64; overload;
    /// <summary>Item 4: TypeOfFunctionResult that also hands back the return
    /// type TEXT every candidate agrees on, even when it resolves to nothing here.</summary>
    /// <param name="ARef">As for the overload without ARetText.</param>
    /// <param name="AName">As for the overload without ARetText.</param>
    /// <param name="ARetText">The agreed return type text, leaf-normalised; ''.</param>
    /// <returns>As for the overload without ARetText.</returns>
    function TypeOfFunctionResult(const ARef: TReference; const AName: string; out ARetText: string): Int64; overload;    /// <summary>X2: True when ancestor AAncestor is an INTERFACE named in the
    /// heritage of AOwnerId and AOwnerId is not itself an interface.</summary>
    /// <param name="AOwnerId">The type whose ancestors are walked.</param>
    /// <param name="AAncestor">A resolved ancestor row of AOwnerId.</param>
    /// <returns>True for an implemented interface of a class or record.</returns>
    function IsImplementedInterface(AOwnerId: Int64; const AAncestor: TTypeAncestor): Boolean;
    /// <summary>What ATypeId declares under AName, nearest declaring level first.</summary>
    /// <param name="ATypeId">A with target's type.</param>
    /// <param name="AName">The bare name.</param>
    /// <param name="ARefFileId">The referencing file, for member visibility.</param>
    /// <returns>See TWithMemberKind.</returns>
    function WithMemberKind(ATypeId: Int64; const AName: string; ARefFileId: Int64): TWithMemberKind;
    /// <summary>What ONE declaring level -- a type or one of its ancestors --
    /// declares under AName, visibility from ARefFileId included.</summary>
    /// <param name="ALevelId">The type symbol whose direct children are read.</param>
    /// <param name="AName">The bare name.</param>
    /// <param name="ARefFileId">The referencing file.</param>
    /// <returns>wmNone when the level does not declare the name.</returns>
    function LevelMemberKind(ALevelId: Int64; const AName: string; ARefFileId: Int64): TWithMemberKind;
    /// <summary>True when every ancestor of ATypeId is resolved in this index,
    /// TObject / IInterface excepted, so a name missing from it is missing.</summary>
    /// <param name="ATypeId">A with target's type.</param>
    /// <returns>True for a complete surface.</returns>
    function SurfaceComplete(ATypeId: Int64): Boolean;
    /// <summary>The with scope's verdict on the bare name AName written at
    /// ALine/ACol of ARef's file: targets innermost first, and within one
    /// statement the LAST-listed entity first, exactly as Delphi binds.</summary>
    /// <param name="ARef">Supplies the file and the enclosing routine.</param>
    /// <param name="ALine">The name's line.</param>
    /// <param name="ACol">The name's column.</param>
    /// <param name="AName">The bare name.</param>
    /// <param name="ALayerType">Out: the winning target's type for wvMember.</param>
    /// <param name="AKind">Out: what that target declares under AName.</param>
    /// <returns>See TWithVerdict.</returns>
    function WithScopeAt(const ARef: TReference; ALine, ACol: Integer; const AName: string;
      out ALayerType: Int64; out AKind: TWithMemberKind): TWithVerdict;
    /// <summary>One with layer's verdict on AName: its target untypable or the
    /// answer unknowable (undecided), the name its member (member), or absent
    /// from a COMPLETE surface (none -- the next layer out is asked).</summary>
    /// <param name="ARef">Supplies the file and the enclosing routine.</param>
    /// <param name="AStmts">The file's statements.</param>
    /// <param name="AStmt">The statement.</param>
    /// <param name="AEnt">The entity -- the layer.</param>
    /// <param name="AName">The bare name.</param>
    /// <param name="ALayerType">Out: the layer's type for wvMember, else 0.</param>
    /// <param name="AKind">Out: what the layer declares under AName.</param>
    /// <returns>See TWithVerdict.</returns>
    function LayerVerdict(const ARef: TReference; const AStmts: TArray<TWithStatement>;
      AStmt, AEnt: Integer; const AName: string; out ALayerType: Int64;
      out AKind: TWithMemberKind): TWithVerdict;
    /// <summary>TypeReceiver's with rung: a receiver whose LEADING identifier a
    /// with target supplies is typed through that target's members.</summary>
    /// <param name="ACallRef">The call or member-access ref.</param>
    /// <param name="AReceiverExpr">The receiver text, e.g. 'Inner' or 'A.B'.</param>
    /// <param name="AHandled">Out: True when the with scope decided the
    /// receiver (typed or undecided) and the ordinary rungs must not run.</param>
    /// <returns>The receiver type, or 0.</returns>
    function TypeReceiverThroughWith(const ACallRef: TReference; const AReceiverExpr: string;
      out AHandled: Boolean): Int64;
    /// <summary>ResolveOne's two NEAREST rungs for a BARE call: the with scope
    /// (a routine member of the innermost target that declares the name,
    /// certain only), then the lexical chain of nested routines.</summary>
    /// <param name="ACallRef">The bare call ref.</param>
    /// <param name="AArgCount">The call site's argument count.</param>
    /// <param name="AArgsKnown">False when the site could not be read.</param>
    /// <param name="AEdge">Receives target, confidence and receiver type on a
    /// binding; untouched otherwise.</param>
    /// <returns>True when either rung DECIDED the call -- bound, or (the with
    /// scope only) declined for an undecided target, a non-routine member or
    /// an overload tie -- so no farther rung may run for it; False when neither
    /// claims the name.</returns>
    function BareCallInNearScopes(const ACallRef: TReference; AArgCount: Integer;
      AArgsKnown: Boolean; var AEdge: TCallEdge): Boolean;
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
    /// <param name="ALine">The site's text up to the ref -- since 1.8.0 possibly several
    /// source lines joined (D16c); ALhs is a prefix of it.</param>
    /// <param name="ALhs">ALine up to (not including) the `:=`.</param>
    /// <returns>The type text, or ''.</returns>
    function AssignedTypeText(const ARef: TReference; const ALine, ALhs: string): string;
    /// <summary>True when the routine called at AOpenCol's `(` declares a
    /// procedural parameter at AArgIndex, in ANY of its visible candidates.</summary>
    /// <param name="ARef">The read ref standing as that whole argument.</param>
    /// <param name="ALine">The site's text up to the ref (several lines joined since
    /// 1.8.0, D16c); AOpenCol is a column in it.</param>
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
    /// <param name="ALines">Its source file. The text before and after the name
    /// is read ACROSS lines (D16c): an argument list or an assignment split over
    /// several lines is one site, and reading only the ref's own line made
    /// `RegisterGen(` + newline + `NextId)` look like no argument at all.</param>
    /// <param name="AReceiver">'' or 'Self'.</param>
    /// <param name="AResultType">The target's return type text.</param>
    /// <returns>True when the read is (or may be) a procedure value.</returns>
    function ParenlessIsProcValue(const ARef: TReference; ALines: TStringList; const AReceiver,
      AResultType: string): Boolean;
    /// <summary>The shared first step of the two `read` passes that read the
    /// site's text: the ref's source lines and the receiver written before it.</summary>
    /// <param name="ARef">The candidate read ref.</param>
    /// <param name="ALines">Out: the ref's file lines (nil when unreadable).</param>
    /// <param name="AReceiver">Out: the receiver text, '' for a bare name.</param>
    /// <returns>'' when the site can be judged; 'unreadable' for a missing or
    /// STALE line (a guess, not a fact); 'qualified' for a receiver other
    /// than Self (a member-access the main stream owns).</returns>
    function BareReadSite(const ARef: TReference; out ALines: TStringList;
      out AReceiver: string): string;
    /// <summary>Counts one outcome of ResolveParenlessRead into FParenlessStats.</summary>
    /// <param name="AReason">'' for a binding, else the decline reason.</param>
    procedure TallyParenless(const AReason: string);

    { ---- 2026-09-23: ENG-16 and D13 (resolver 1.8.0-alpha). ---- }

    /// <summary>Rung 4b (ENG-16): the routine a UNIT-QUALIFIED call names --
    /// `Pipes.Commands.DispatchCommand(...)`, `uHelp.DoIt`.</summary>
    /// <param name="ACallRef">The call or member-access ref; FileId, NameText
    /// and EnclosingSymbolId are consulted.</param>
    /// <param name="AReceiver">The receiver text verbatim, dotted unit names
    /// included; '' answers 0.</param>
    /// <param name="AReceiverTypeId">What receiver typing answered for it; any
    /// value but 0 answers 0 -- a receiver that typed is a value, not a unit.</param>
    /// <param name="AArgCount">Arguments counted at the site.</param>
    /// <param name="AArgsKnown">False when the count could not be taken.</param>
    /// <param name="AConfidence">OUT: 'certain' or 'ambiguous', as PickFromMatches.</param>
    /// <returns>The routine id, or 0 when the receiver's first segment names a
    /// nearer value (a local, parameter or class member spelled like the unit),
    /// an enclosing `with` target owns or may own that segment (WithScopeAt
    /// answers anything but wvNone), the receiver names no unit or two, or that
    /// unit declares no visible routine of the name.</returns>
    /// <remarks>Visible means the unit's INTERFACE, or either section when the
    /// unit is the calling file itself -- the rule rung 3c applies to `Unit.value`.
    /// An overload set is narrowed by arity exactly as the bare-call rung does.</remarks>
    function LookupUnitQualifiedRoutine(const ACallRef: TReference; const AReceiver: string;
      AReceiverTypeId: Int64; AArgCount: Integer; AArgsKnown: Boolean; out AConfidence: string): Int64;

    { ---- 2026-09-24: D22 (resolver 1.9.0-alpha). ---- }

    /// <summary>The file of the unit a qualified receiver names, provided
    /// nothing nearer than that unit claims the receiver's first segment -- the
    /// shared gate of rung 3c's unit branch, rung 3d and rung 4b.</summary>
    /// <param name="ARef">The ref; FileId, StartLine, StartCol and
    /// EnclosingSymbolId are consulted.</param>
    /// <param name="AReceiver">The receiver text verbatim, dotted unit names
    /// included.</param>
    /// <returns>The unit's file id, or 0 when the first segment names a nearer
    /// value (a local, parameter or class member spelled like the unit), an
    /// enclosing `with` target owns or may own it, or the receiver names no unit
    /// or two.</returns>
    /// <remarks>Does NOT test receiver typing: the callers do, first, because a
    /// receiver that typed is a value and never reaches a unit rung. Unit
    /// lookups are cached in FUnitFileOf for the pass.</remarks>
    function UnshadowedUnitFile(const ARef: TReference; const AReceiver: string): Int64;
    /// <summary>Rung 3d (D22): the unit-level var or const a UNIT-QUALIFIED
    /// member-access names -- `uStyles.SkipRefresh`, read or written.</summary>
    /// <param name="ARef">The member-access ref.</param>
    /// <param name="AReceiver">The receiver text verbatim; '' answers 0.</param>
    /// <param name="AReceiverTypeId">What receiver typing answered; any value
    /// but 0 answers 0 -- a receiver that typed is a value, not a unit.</param>
    /// <returns>The declaration's symbol id, or 0 when UnshadowedUnitFile
    /// declines or when not exactly ONE unit-level var/const of the name is
    /// visible in that unit.</returns>
    /// <remarks>Visible means the unit's INTERFACE, or either section when the
    /// unit is the referencing file itself -- the rule of rungs 3c and 4b. The
    /// candidates are FNameToUnitValues (GetUnitLevelValueDecls): consts and
    /// vars parented directly by a unit, so class constants and record fields
    /// are never candidates.</remarks>
    function LookupUnitQualifiedValue(const ARef: TReference; const AReceiver: string;
      AReceiverTypeId: Int64): Int64;
    /// <summary>Rungs 3c and 3d of ResolveOne: the VALUE a qualified
    /// member-access names -- an enum value through its enum type or unit
    /// (3c), else a unit-level var/const through its unit (3d).</summary>
    /// <param name="ACallRef">The member-access ref.</param>
    /// <param name="AReceiver">The receiver text verbatim; the caller has
    /// already refused ''.</param>
    /// <param name="AReceiverTypeId">What receiver typing answered: an enum
    /// type for `TEnum.value`, 0 for a unit receiver.</param>
    /// <returns>The enum_value, var or const symbol id, or 0 when neither
    /// rung binds -- including when a nearer value (a local spelled like the
    /// unit, a `with` target) claims a unit receiver, for BOTH rungs.</returns>
    /// <remarks>Counts a 3c binding into FEnumStats.Bound and a 3d binding into
    /// FUnitValueBound -- never both, because a unit var is not an enum value.
    /// A third counter, FEnumUnitGateDeclined, is moved by rung 3c alone: the
    /// name is a known enum value, the receiver names one unit, and
    /// UnshadowedUnitFile still declined it (a nearer value or a `with` target
    /// claims the receiver) -- the only trace such a decline leaves. Rung 3d's
    /// own gate declines are not counted.</remarks>
    function QualifiedValueTarget(const ACallRef: TReference; const AReceiver: string;
      AReceiverTypeId: Int64): Int64;
    /// <summary>The TWriteScope of AEnclosingSymbolId, built on first use and
    /// cached for the rest of the pass.</summary>
    /// <param name="AEnclosingSymbolId">A ref's enclosing symbol; 0 gives an
    /// empty scope.</param>
    /// <returns>The routine chain, the enclosing functions' names, the class
    /// chain and the routine's first line.</returns>
    function WriteScopeOf(AEnclosingSymbolId: Int64): TWriteScope;
    /// <summary>The routine and class rungs of a bare write: the nearest
    /// lexical level, then the enclosing function names, then the class chain
    /// nearest first.</summary>
    /// <param name="AScope">The write's enclosing scope.</param>
    /// <param name="AName">The identifier as written.</param>
    /// <param name="AFileId">The file of the site.</param>
    /// <param name="ALine">The site's line.</param>
    /// <param name="ACol">The site's column.</param>
    /// <param name="AReason">OUT: '' when bound or when nothing here declares
    /// the name (the unit rung decides then); 'routine', 'own-name' or
    /// 'ambiguous' for a decline.</param>
    /// <returns>The local / parameter / const / var / field / property id, or 0.</returns>
    /// <remarks>Review 2026-10-23: a level may hold several value declarations
    /// of the name (`for var i` twice). The NEAREST one at or before the site
    /// whose scope covers it answers (LocalScopeCovers); when none covers it
    /// the level declines 'ambiguous' rather than fall back to the first.</remarks>
    function ScopeWriteTarget(const AScope: TWriteScope; const AName: string;
      AFileId: Int64; ALine, ACol: Integer; out AReason: string): Int64;
    /// <summary>The unit rung of a bare write: the unit-level var/const named
    /// ALc declared in ARefFileId itself or, when it declares nothing of that
    /// name, in the interface of a unit it uses.</summary>
    /// <param name="ARefFileId">The writing file.</param>
    /// <param name="ALc">The lowercased identifier.</param>
    /// <param name="AReason">OUT: '' on a binding, else 'ambiguous' |
    /// 'routine' | 'not-found'.</param>
    /// <returns>The declaration's id, or 0.</returns>
    /// <remarks>A rung ANSWERS when anything of the name lives there: exactly one
    /// value and nothing else binds; two values, or a value beside a routine /
    /// type / enum value, is 'ambiguous'; only non-values is 'routine'.</remarks>
    function UnitScopeWriteTarget(ARefFileId: Int64; const ALc: string; out AReason: string): Int64;
    /// <summary>Counts one outcome of ResolveWriteRef into FWriteStats.</summary>
    /// <param name="AReason">'' for a binding, else the decline reason.</param>
    procedure TallyWrite(const AReason: string);
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
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddMethodsOnTypeChain"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddVisibleUnitRoutines"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AncestorsOf"/>
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
    /// <para>Calls: Default, DRagLint.Index.CallResolver.TCallResolver.BuildMaps</para>
    /// <para>constructor</para>
    /// <para>Reads: FWith, FRows   Writes: FStore, FExtraStores, FNameToCands, FNameToRoutines, FNameToEnumValues, FNameToUnitValues, FEnumStats, FParenlessStats (+10 more)</para>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BuildMaps"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddMethodsOnTypeChain"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddVisibleUnitRoutines"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AncestorsOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AssignedTypeText"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(const AStore: ISymbolStore;
      const AExtraStores: TArray<ISymbolStore> = nil);
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FRows, FWith, FLineCache, FUnitFileOf, FFileTypes, FLocalDecls, FWriteScopes, FStaleFiles (+6 more)   Writes: FStore</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddMethodsOnTypeChain"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AddVisibleUnitRoutines"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AncestorsOf"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.AssignedTypeText"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BareCallInNearScopes"/>
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
    /// <para>Calls: Default, DRagLint.Index.CallResolver.CountCallArgs, DRagLint.Index.CallResolver.ExtractReceiverExpr, DRagLint.Index.CallResolver.TCallResolver.BareCallInNearScopes, DRagLint.Index.CallResolver.TCallResolver.FileIsStale, DRagLint.Index.CallResolver.TCallResolver.LinesOf, DRagLint.Index.CallResolver.TCallResolver.LookupMemberOnType, DRagLint.Index.CallResolver.TCallResolver.LookupMethodOnType, DRagLint.Index.CallResolver.TCallResolver.LookupUnitLevelRoutine, DRagLint.Index.CallResolver.TCallResolver.LookupUnitQualifiedRoutine (+6 more)</para>
    /// <para>Complexity: 23 (cyclomatic, outer body), 212 lines (full implementation)</para>
    /// <para>Reads: FUnitValueBound, FExtraStores</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Index.CallResolver.CountCallArgs"/>
    /// <seealso cref="DRagLint.Index.CallResolver.ExtractReceiverExpr"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.BareCallInNearScopes"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.FileIsStale"/>
    /// <seealso cref="DRagLint.Index.CallResolver.TCallResolver.LinesOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ResolveOne(const ACallRef: TReference): TCallEdge;

    /// <summary>Shape A (2026-09-23, enum-value-ref-binding): resolve a bare
    /// `read` ref that names an enum value, by NAME and SCOPE only -- rules
    /// R1-R4 of the spec. Answers `certain` or nothing; there is no ambiguous
    /// value binding.</summary>
    /// <param name="ARef">The candidate read ref. FileId, NameText, StartLine,
    /// StartCol and EnclosingSymbolId are consulted.</param>
    /// <param name="AReason">OUT: '' when the ref bound OR when its name is not
    /// an enum-value name at all; otherwise the decline reason --
    /// 'with-member' | 'scoped' | 'not-visible' | 'ambiguous' | 'shadowed'.</param>
    /// <returns>The enum_value symbol id, or 0 for every decline.</returns>
    /// <remarks>
    /// READS NO SOURCE LINE for the value rules themselves: R1-R4 are a pure
    /// function of the symbol table. Since 1.8.0 the `with` scope is consulted
    /// FIRST (R7): when an enclosing with target declares the name, the read
    /// names that member and this pass declines ('with-member', counted in
    /// EnumStats.WithMember) -- the member-read pass binds it instead. When a
    /// target cannot be typed the pass keeps its pre-1.8 answer and counts it
    /// in EnumStats.WithUndecided: an enum value almost never collides with a
    /// library object's member, and enum-read-inside-with -- which reads the
    /// library index too -- reports the collisions that do exist.
    ///
    /// E14: a value of an enum declared under SCOPEDENUMS ON (the X4 fact,
    /// TEnumValueDecl.Scoped) is never a candidate for the bare form. When the
    /// only R1-visible candidates are such values the pass declines 'scoped'
    /// (EnumStats.Scoped), so a same-named const or var can bind instead.
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

    /// <summary>Rung 3d bindings so far: unit-qualified var/const member-access
    /// refs ResolveOne bound, each with a MemberMode (D22, rulings R13/R15).</summary>
    /// <remarks>Cumulative over the resolver's lifetime; one resolver serves one
    /// pass. NOT part of EnumStats.Bound. A member-access edge is a unit value
    /// exactly when this counter moved during its ResolveOne call, which is how
    /// the calls stage counts it apart from property/field accesses.</remarks>
    property UnitValueBound: Int64 read FUnitValueBound;

    /// <summary>Rung 3c declines of a `Unit.enumValue` whose receiver names
    /// exactly one unit but is claimed by something nearer -- a local, parameter
    /// or class member spelled like the unit, or a `with` target that owns or
    /// may own that name (ruling R14).</summary>
    /// <remarks>Cumulative over the resolver's lifetime. Printed on the calls
    /// stage's enum-values line; a decline writes nothing, so this is its only
    /// trace.</remarks>
    property EnumUnitGateDeclined: Int64 read FEnumUnitGateDeclined;

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
    /// Since 1.8.0 the `with` scope decides a bare name first: a with target's
    /// ROUTINE member is the candidate set (and binds with the target as the
    /// receiver type, certain only); a property/field member is a value and
    /// declines ('shadowed'); a target that cannot be typed, or whose surface
    /// leaves the index, declines ('with-scope'). A receiver other than Self
    /// declines ('qualified' -- a qualified parenless call is a `member-access`
    /// ref and the main stream owns it).
    /// Counted into ParenlessStats, one outcome per call.
    /// </remarks>
    function ResolveParenlessRead(const ARef: TReference; out AReason: string): TCallEdge;

    /// <summary>Per-run counters of the parenless-call pass. Read by the calls
    /// stage for its ResolveLog line.</summary>
    /// <remarks>Cumulative over the resolver's lifetime; one resolver serves one
    /// pass.</remarks>
    property ParenlessStats: TParenlessResolveStats read FParenlessStats;

    /// <summary>D14 + D16a (2026-09-23, resolver 1.8.0-alpha) + DEC-19 (resolver
    /// 1.12.0-alpha): decide whether a bare `read` ref names a PROPERTY or FIELD,
    /// and if so which -- a member of an enclosing `with` target, or a member of
    /// the enclosing class or one of its resolved ancestors.</summary>
    /// <param name="ARef">The candidate read ref. FileId, NameText, StartLine,
    /// StartCol and EnclosingSymbolId are consulted.</param>
    /// <param name="AReason">OUT: '' when the ref bound; otherwise the decline
    /// reason -- 'unreadable' | 'qualified' | 'with-scope' | 'not-member' |
    /// 'shadowed' | 'not-found' | 'hidden'.</param>
    /// <returns>An edge whose TargetSymbolId is the property/field, MemberMode
    /// 'read', the accessor when the property names one, and
    /// ReceiverTypeSymbolId the with target's (or the class's) type; or
    /// TargetSymbolId = 0 for every decline.</returns>
    /// <remarks>
    /// Order is Delphi's: the with scope first (a member it names wins over
    /// every local), then a local/parameter/nested routine of the name (a
    /// shadow), then the enclosing class and its ancestors. A with target that
    /// cannot be typed, or whose surface is incomplete, declines.
    ///
    /// A FIELD of the enclosing class or of an ancestor read BARE binds, exactly
    /// as a property does but with no accessor (DEC-19, owner ruling
    /// 2026-10-05; until 1.12.0 it declined 'field' by design): `if FConnected`,
    /// `with tblFtrs do` and the receiver `tblFtrs` of `tblFtrs.Post` -- its own
    /// `read` ref -- where a grand-ancestor declares tblFtrs. A field of a WITH
    /// target is bound too.
    ///
    /// The class chain is walked NEAREST first (NearestClassMember): the first
    /// class declaring ANY member of the name answers, and only a property or
    /// field binds -- a nearer method, class const/var or nested type hides a
    /// farther field ('hidden'). An unresolved parent ends the walk, and an
    /// implemented interface's members are not in scope.
    ///
    /// An explicit `Self.X` (a `read` ref whose receiver is Self -- the
    /// extractor's shape for it) binds a property OR a field exactly as `Obj.X`
    /// does, and is never declined for a same-named local: the local cannot be
    /// what `Self.X` names.
    /// Counted into MemberReadStats, one outcome per call.
    /// </remarks>
    function ResolveBareMemberRead(const ARef: TReference; out AReason: string): TCallEdge;

    /// <summary>Per-run counters of the bare member-read pass.</summary>
    /// <remarks>Cumulative over the resolver's lifetime.</remarks>
    property MemberReadStats: TMemberReadStats read FMemberReadStats;

    /// <summary>Per-run counters of the `with` scope, across every stream.</summary>
    /// <remarks>Cumulative over the resolver's lifetime.</remarks>
    property WithStats: TWithScopeStats read FWith.Stats;

    /// <summary>D13 (2026-09-23, resolver 1.8.0-alpha): the declaration a bare
    /// `write` ref (`X:= ...`) assigns, by name and scope -- certain or nothing.</summary>
    /// <param name="ARef">The write ref. FileId, NameText, StartLine, StartCol
    /// and EnclosingSymbolId are consulted.</param>
    /// <param name="AReason">OUT: '' when the ref bound; otherwise 'unreadable' |
    /// 'result' | 'with-scope' | 'own-name' | 'routine' | 'ambiguous' |
    /// 'not-found'.</param>
    /// <returns>The local / parameter / field / property / class var / unit-level
    /// var or const id, or 0 for every decline.</returns>
    /// <remarks>
    /// Delphi's own lookup order, nearest first: the enclosing `with` targets at
    /// the site (innermost first; a property/field of one binds), the lexical scopes (locals,
    /// parameters, consts and vars of the routine and of the routines around
    /// it), then the enclosing class and its resolved ancestors (fields,
    /// properties, class vars), then the own unit (both sections), then the
    /// interfaces of the units it uses. The first scope that declares the name
    /// ANSWERS -- a nearer declaration always shadows a farther one -- and it
    /// must answer with exactly one variable-like declaration.
    ///
    /// A `with` target that cannot be typed, or whose surface leaves the index,
    /// declines ('with-scope'): it may supply the name ahead of every scope
    /// above. A write outside every with body is untouched by the with scope.
    /// (Before the merge with D14 any `with` earlier in the routine declined.)
    /// `Result` and the
    /// name of an enclosing function are result assignments with no symbol row
    /// to bind. Delphi settles a clash between two used units by uses-clause
    /// ORDER, which this engine does not model, so that is 'ambiguous'.
    /// An explicit `Self.X := v` (resolver 1.10.0-alpha) skips the with scope and
    /// the lexical scopes: it binds X on the enclosing class chain or declines
    /// 'not-found', exactly as ResolveBareMemberRead treats a `Self.X` read.
    /// Counted into WriteStats, one outcome per call.
    /// </remarks>
    function ResolveWriteRef(const ARef: TReference; out AReason: string): Int64;

    /// <summary>Per-run counters of the write-ref pass. Read by the calls stage
    /// for its ResolveLog line.</summary>
    /// <remarks>Cumulative over the resolver's lifetime; one resolver serves one
    /// pass.</remarks>
    property WriteStats: TWriteResolveStats read FWriteStats;

    /// <summary>B-28 (2026-10-23): the local / parameter / const / var a bare
    /// `read` ref names, by the scope walk of a bare write -- certain or nothing.</summary>
    /// <param name="ARef">The read ref. FileId, NameText, StartLine, StartCol and
    /// EnclosingSymbolId are consulted.</param>
    /// <param name="AReason">OUT: '' when the ref bound; otherwise 'unreadable' |
    /// 'qualified' | 'result' | 'with-scope' | 'member' | 'own-name' | 'routine'
    /// | 'ambiguous' | 'not-found' | 'unlisted'.</param>
    /// <returns>The local_var / param / const / var id, or 0 for every decline.</returns>
    /// <remarks>
    /// The lookup order is ResolveWriteRef's: the `with` scope at the site (a
    /// member of a typed target is the member-read stream's, 'member'; an
    /// undecidable target declines 'with-scope'), the lexical levels of the
    /// routine and the routines around it, the enclosing class chain, the own
    /// unit, the interfaces of the used units. The first scope that declares the
    /// name answers. Only a value kind binds: a property or field is declined
    /// 'member' (ResolveBareMemberRead binds it and writes its member_accesses
    /// row), a routine / type / enum value 'routine'. A receiver-qualified read,
    /// `Self.X` included, is 'qualified'. The extractor emits no symbol for a
    /// routine's local const or an inline const, so a binding is declined
    /// 'unlisted' when a routine NEARER than the answering scope -- every
    /// enclosing routine when the class or unit answered, the inner levels when
    /// an outer routine did -- declares the name that way in its text
    /// (LocalDeclNamesOf). Identity only -- the caller writes
    /// refs.symbol_id and nothing else. Counted into ValueReadStats.
    /// </remarks>
    function ResolveBareValueRead(const ARef: TReference; out AReason: string): Int64;

    /// <summary>Per-run counters of the value-read pass.</summary>
    /// <remarks>Cumulative over the resolver's lifetime.</remarks>
    property ValueReadStats: TValueReadStats read FValueReadStats;

    /// <summary>B-31 (2026-10-23): the type a `type_use` ref names -- certain or
    /// nothing.</summary>
    /// <param name="ARef">The type_use ref. FileId, NameText, StartLine, StartCol
    /// and EnclosingSymbolId are consulted.</param>
    /// <param name="AReason">OUT: '' when the ref bound; otherwise 'unreadable' |
    /// 'qualified' | 'generic' | 'unlisted' | 'ambiguous' | 'not-found'.</param>
    /// <returns>The class / interface / record / type / enum id, or 0.</returns>
    /// <remarks>
    /// Delphi's order. From the ref's scope (ScopeSymbolAt) outwards: a generic
    /// parameter of the level declines, a routine whose text declares the name
    /// as a local type declines ('unlisted' -- the index lists no local types),
    /// a type child of the level binds (a nested type -- of the level's
    /// resolved ancestors too, nearest first -- then the own unit's types). Then the used units: exactly one TOP-LEVEL INTERFACE type of a
    /// unit in scope binds; two are 'ambiguous' (uses-clause order is not
    /// modelled). A qualified name is declined rather than guessed. Identity
    /// only. Counted into TypeUseStats.
    /// </remarks>
    function ResolveTypeUse(const ARef: TReference; out AReason: string): Int64;

    /// <summary>X6 / gap G1 (2026-10-25): the ENUM type a hard cast `TEnum(x)`
    /// names -- certain or nothing.</summary>
    /// <param name="ARef">The `call` ref the cast was extracted as (name_text =
    /// the type name). FileId, NameText, StartLine, StartCol and
    /// EnclosingSymbolId are consulted.</param>
    /// <param name="AReason">OUT: '' when the ref bound; 'not-enum' when the name
    /// resolves to a type that is not an enum; otherwise ResolveTypeUse's decline
    /// reasons ('qualified', 'ambiguous', 'not-found', ...).</param>
    /// <returns>The enum type's symbol id, or 0.</returns>
    /// <remarks>
    /// Same scope order as ResolveTypeUse (it shares the lookup) but does NOT
    /// count into TypeUseStats. Only an enum binds: a class / record cast stays
    /// unbound, so find-callers and the call graph never see a type as a callee.
    /// Identity only -- the caller writes refs.symbol_id and no call_edges row.
    /// </remarks>
    function ResolveEnumCast(const ARef: TReference; out AReason: string): Int64;

    /// <summary>Per-run counters of the type_use pass.</summary>
    /// <remarks>Cumulative over the resolver's lifetime.</remarks>
    property TypeUseStats: TTypeUseStats read FTypeUseStats;

    /// <summary>Item 4: per-run receiver counters (qualified sites only).</summary>
    /// <remarks>Cumulative over the resolver's lifetime.</remarks>
    property ReceiverStats: TReceiverStats read FReceiverStats;
    /// <summary>Item 4: the library oracle's outcome counters; no-store counts
    /// every site that would have been offered to a library had one been open.</summary>
    /// <returns>A copy of TLibraryOracle.Stats.</returns>
    /// <remarks>Cumulative over the resolver's lifetime.</remarks>
    function OracleStats: TOracleStats;
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
  /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.AssignedTypeText (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.BareReadSite (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.CalleeTakesProcedural (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveOne (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.ResolveWriteRef (DRagLint.Index.CallResolver.pas)</para>
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
  /// <para>Calls: DRagLint.Index.CallResolver.CountCallArgs.Next, DRagLint.Index.CallResolver.IsIdentPart</para>
  /// <para>Returns: 0; Commas + 1</para>
  /// <para>Complexity: 57 (cyclomatic, outer body), 152 lines (full implementation)</para>
  /// <para>Mutates: AKnown (out)</para>
  /// <seealso cref="DRagLint.Index.CallResolver.CountCallArgs.Next"/>
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
  /// <para>Called from: DRagLint.Doc.Facts.OverloadArityTag (DRagLint.Doc.Facts.pas), DRagLint.Index.CallResolver.IsParenlessCallable (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.PropertyIndexArity (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.PickAccessor (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.PickFromMatches (DRagLint.Index.CallResolver.pas)</para>
  /// <para>Calls: Copy, Pos, SplitString, StartsText, Trim</para>
  /// <para>Returns: False; True</para>
  /// <para>Complexity: 25 (cyclomatic, outer body), 103 lines (full implementation)</para>
  /// <para>Mutates: AMin (out), AMax (out)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  function SignatureArityRange(const ASignature: string; out AMin, AMax: Integer): Boolean;

  /// <summary>The parameter part of a routine signature as a comparable key:
  /// per parameter, its modifier and declared type, lower-case, without names,
  /// default values or whitespace. `(var A: Integer; const B, C: string = 'x')`
  /// gives `var:integer;const:string;const:string;`.</summary>
  /// <param name="ASignature">A stored symbol Signature.</param>
  /// <returns>One `modifier:type;` group per declared parameter; '' when the
  /// signature has no parameter list.</returns>
  /// <remarks>Only the text inside the first top-level parentheses counts, so the
  /// return type never takes part (Delphi overloads cannot differ by it). An
  /// untyped parameter (`var ABuffer`) has an empty type. Parentheses, brackets
  /// and angle brackets nest, so a `;` inside them never splits a group; a `;`
  /// inside a quoted default value DOES split one, so a caller that maps groups
  /// to argument positions must check the group count against
  /// SignatureArityRange. Shared by DispatchResolver (implements ties, rb5-gen)
  /// and the call-side overload narrowing (rb5-ovl).</remarks>
  function ParamTypeKey(const ASignature: string): string;

implementation

uses
  System.Math,     // Min -- ResolveAccessor's declaring-line range
  System.StrUtils, // B1: StartsText / SplitString, used by SignatureArityRange
  System.RegularExpressions, // rb5-ovl: ArgShapeOfText's number literals
  TreeSitter,      // 1.8.0: the with scope parses a file's `with` statements
  TreeSitterLib,
  DRagLint.Core.Encoding,    // EnsureUtf8Bytes -- the indexer's own transcoding
  DRagLint.Analysis.Purity,  // LexCallArguments -- the shared argument lexer (rb5-ovl)
  DRagLint.Preprocess.Types; // NormalizeLoneCR -- the indexer's own row counting

{ Declared HERE, in the implementation, for the reason DRagLint.Diagnostics.
  ParseCache gives: DRagLint.Parser.Delphi13 exports the same import from its
  interface, and a second interface export would make any unit using both pick
  whichever came last in its uses clause. }
function TreeSitterDelphi13: PTSLanguage; cdecl; external 'tree-sitter-delphi13' name 'tree_sitter_delphi13';

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
      // X1: `LCaps [LRole].Style` -- Delphi allows blanks before a subscript.
      // Only for '[': a blank before '(' may separate a keyword from a group.
      if (I >= 1) and (Line[I] = ' ') and (Line[StopL] = '[') then
      begin
        var J: Integer:= I;
        while (J >= 1) and (Line[J] = ' ') do Dec(J);
        if (J >= 1) and IsIdentPart(Line[J]) then I:= J;
      end;
      while (I >= 1) and IsIdentPart(Line[I]) do begin StopL:= I; Dec(I); end;
    end
    else if IsIdentPart(Ch) then
    begin
      while (I >= 1) and IsIdentPart(Line[I]) do begin StopL:= I; Dec(I); end;
    end
    else if Ch = '^' then
    begin
      // X1: a POSTFIX DEREFERENCE -- `P^.K`, `A[i]^.K`. Keep the '^' and consume
      // the operand to its left as the same selector segment. Before this the
      // scan broke here and returned '' -- the value a BARE call yields -- so
      // `P^.Ping;` resolved as a bare call on the enclosing class.
      StopL:= I;
      Dec(I);
      Continue;
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
  FWith.Statements     := TDictionary<Int64, TArray<TWithStatement>>.Create;
  FWith.SurfaceComplete:= TDictionary<Int64, Boolean>.Create;
  FRows.Symbols        := TDictionary<Int64, TSymbol>.Create;
  FRows.Ancestors      := TDictionary<Int64, TArray<TTypeAncestor>>.Create;
  FWith.Stats          := Default(TWithScopeStats);
  FMemberReadStats:= Default(TMemberReadStats);
  FUnitFileOf := TDictionary<string, Int64>.Create;
  FWriteScopes:= TDictionary<Int64, TWriteScope>.Create;
  FLocalDecls := TDictionary<Int64, string>.Create;
  FFileTypes  := TDictionary<Int64, TArray<TSymbol>>.Create;
  FWriteStats := Default(TWriteResolveStats);
  FOracle    := TLibraryOracle.Create(AExtraStores);
  FReceiverStats  := Default(TReceiverStats);
  FFileUses  := TDictionary<Int64, TArray<string>>.Create;
  FDprUses   := [];
  FDprLoaded := False;
  BuildMaps;
end;

destructor TCallResolver.Destroy;
begin
  FFileUses.Free;
  FOracle.Free;
  FRows.Ancestors     .Free;
  FRows.Symbols       .Free;
  FWith.SurfaceComplete.Free;
  FWith.Statements    .Free;
  FLineCache .Free;
  FUnitFileOf.Free;
  FFileTypes.Free;
  FLocalDecls.Free;
  FWriteScopes.Free;
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

function TCallResolver.SymbolById(AId: Int64): TSymbol;
begin
  if FRows.Symbols.TryGetValue(AId, Result) then Exit;
  Result:= FStore.GetSymbolById(AId);
  FRows.Symbols.Add(AId, Result);
end;

function TCallResolver.AncestorsOf(ATypeId: Int64): TArray<TTypeAncestor>;
begin
  if FRows.Ancestors.TryGetValue(ATypeId, Result) then Exit;
  Result:= FStore.GetTransitiveAncestors(ATypeId);
  FRows.Ancestors.Add(ATypeId, Result);
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

{ Declared in the interface (DocInsight there); moved here from DispatchResolver by rb5-ovl. }
function ParamTypeKey(const ASignature: string): string;
var
  Depth, Open, Close, Start: Integer;
  Inner, Names, TypeText, Modifier: string;
  Groups: TList<string>;
begin
  Result:= '';
  Open:= Pos('(', ASignature);
  if Open = 0 then Exit;
  Depth:= 0;
  Close:= 0;
  for var i:= Open to Length(ASignature) do
  begin
    if CharInSet(ASignature[i], ['(', '[', '<']) then Inc(Depth)
    else if CharInSet(ASignature[i], [')', ']', '>']) then Dec(Depth);
    if Depth = 0 then
    begin
      Close:= i;
      Break;
    end;
  end;
  if Close = 0 then Exit;
  Inner:= Copy(ASignature, Open + 1, Close - Open - 1);
  Groups:= TList<string>.Create;
  try
    Depth:= 0;
    Start:= 1;
    for var i:= 1 to Length(Inner) + 1 do
    begin
      if (i > Length(Inner)) or ((Depth = 0) and (Inner[i] = ';')) then
      begin
        Groups.Add(Trim(Copy(Inner, Start, i - Start)));
        Start:= i + 1;
      end
      else if CharInSet(Inner[i], ['(', '[', '<']) then Inc(Depth)
      else if CharInSet(Inner[i], [')', ']', '>']) then Dec(Depth);
    end;
    for var G in Groups do
    begin
      if G = '' then Continue;
      var Decl:= G;
      var Eq:= Pos('=', Decl);
      if Eq > 0 then Decl:= Trim(Copy(Decl, 1, Eq - 1));
      var Colon:= Pos(':', Decl);
      Names   := Trim(if Colon > 0 then Copy(Decl, 1, Colon - 1) else Decl);
      TypeText:= if Colon > 0 then Copy(Decl, Colon + 1, MaxInt) else '';
      Modifier:= '';
      var Sp:= Pos(' ', Names);
      if Sp > 0 then
      begin
        var W:= LowerCase(Copy(Names, 1, Sp - 1));
        if MatchStr(W, ['const', 'var', 'out', 'constref']) then
        begin
          Modifier:= W;
          Names:= Trim(Copy(Names, Sp + 1, MaxInt));
        end;
      end;
      TypeText:= LowerCase(StringReplace(StringReplace(TypeText, ' ', '', [rfReplaceAll]), #9, '', [rfReplaceAll]));
      for var k:= 1 to Length(Names.Split([','])) do
        Result:= Result + Modifier + ':' + TypeText + ';';
    end;
  finally
    Groups.Free;
  end;
end;

type
  { rb5-ovl: the declared-type families the overload narrowing can reason about.
    pfOther is any type it cannot classify (an enum, an alias, a record, a
    class, a procedural type, a generic T) and never rules a candidate out. }
  TParamFamily = (pfOther, pfUntyped, pfInt, pfFloat, pfString, pfChar, pfPChar,
    pfBool, pfVariant, pfOpenArray, pfPointer);
  { yes = the argument can be passed; no = the compiler would reject it;
    maybe = the narrowing cannot tell. Only `no` removes a candidate. }
  TArgFit = (afMaybe, afYes, afNo);

const
  { rb5-ovl: may an argument of this shape be passed to a VALUE / const
    parameter of this family? Every afNo is a compile error in Delphi (an
    integer literal for an open array or a string, `[..]` for an Integer, a
    float for an integer type, a string for a Boolean, ...). Anything the
    narrowing is not sure of is afMaybe -- notably every pfPointer / pfPChar
    pairing but the trivially legal ones, and every string-to-open-array one.
    Columns: Other Untyped Int Float String Char PChar Bool Variant OpenArray Pointer. }
  ARG_FIT: array[TArgShape, TParamFamily] of TArgFit = (
    {asUnknown } (afMaybe, afMaybe, afMaybe, afMaybe, afMaybe, afMaybe, afMaybe, afMaybe, afMaybe, afMaybe, afMaybe),
    {asIntLit  } (afMaybe, afMaybe, afYes,   afYes,   afNo,    afNo,    afMaybe, afNo,    afYes,   afNo,    afMaybe),
    {asFloatLit} (afMaybe, afMaybe, afNo,    afYes,   afNo,    afNo,    afMaybe, afNo,    afYes,   afNo,    afMaybe),
    {asStrLit  } (afMaybe, afMaybe, afNo,    afNo,    afYes,   afNo,    afYes,   afNo,    afYes,   afMaybe, afMaybe),
    {asCharLit } (afMaybe, afMaybe, afNo,    afNo,    afYes,   afYes,   afMaybe, afNo,    afYes,   afMaybe, afMaybe),
    {asBoolLit } (afMaybe, afMaybe, afNo,    afNo,    afNo,    afNo,    afMaybe, afYes,   afYes,   afNo,    afMaybe),
    {asNilLit  } (afMaybe, afMaybe, afNo,    afNo,    afMaybe, afNo,    afYes,   afNo,    afMaybe, afMaybe, afYes),
    {asSetLit  } (afMaybe, afMaybe, afNo,    afNo,    afNo,    afNo,    afMaybe, afNo,    afMaybe, afYes,   afMaybe),
    {asIntVar  } (afMaybe, afMaybe, afYes,   afYes,   afNo,    afNo,    afMaybe, afNo,    afYes,   afNo,    afMaybe),
    {asFloatVar} (afMaybe, afMaybe, afNo,    afYes,   afNo,    afNo,    afMaybe, afNo,    afYes,   afNo,    afMaybe),
    {asStrVar  } (afMaybe, afMaybe, afNo,    afNo,    afYes,   afNo,    afMaybe, afNo,    afYes,   afMaybe, afMaybe),
    {asCharVar } (afMaybe, afMaybe, afNo,    afNo,    afYes,   afYes,   afMaybe, afNo,    afYes,   afMaybe, afMaybe),
    {asBoolVar } (afMaybe, afMaybe, afNo,    afNo,    afNo,    afNo,    afMaybe, afYes,   afYes,   afNo,    afMaybe));

  { ParamTypeKey strips blanks, so `array of X` arrives as `arrayofx`. }
  OPEN_ARRAY_PREFIX = 'arrayof';

  LITERAL_SHAPES = [asIntLit, asFloatLit, asStrLit, asCharLit, asBoolLit, asNilLit, asSetLit];

{ rb5-ovl: the family of one ParamTypeKey type (lower-case, no blanks). A unit
  qualifier (`system.integer`) is dropped; `string[20]` is a short string. }
const
  { rb5-ovl: the built-in type names of each family, comma-delimited. }
  FAMILY_NAMES: array[pfInt..pfPointer] of string = (
    ',integer,cardinal,shortint,smallint,longint,int64,byte,word,longword,uint64,nativeint,nativeuint,' +
      'int8,int16,int32,uint8,uint16,uint32,dword,fixedint,fixeduint,',
    ',single,double,extended,real,real48,currency,comp,',
    ',string,ansistring,widestring,unicodestring,shortstring,rawbytestring,utf8string,',
    ',char,ansichar,widechar,',
    ',pchar,pansichar,pwidechar,',
    ',boolean,bytebool,wordbool,longbool,',
    ',variant,olevariant,',
    '',
    ',pointer,');

function ParamFamily(const ATypeKey: string): TParamFamily;
var
  Leaf: string;
begin
  Result:= pfOther;
  if ATypeKey = '' then Exit(pfUntyped);
  if StartsStr(OPEN_ARRAY_PREFIX, ATypeKey) then Exit(pfOpenArray);
  if StartsStr('string[', ATypeKey) then Exit(pfString);
  Leaf:= ',' + Copy(ATypeKey, LastDelimiter('.', ATypeKey) + 1, MaxInt) + ',';
  for var F:= Low(FAMILY_NAMES) to High(FAMILY_NAMES) do
    if FAMILY_NAMES[F].Contains(Leaf) then Exit(F);
end;

{ rb5-ovl: the number of characters a string-literal expression denotes --
  quoted runs (`''` is one quote) and `#nn` / `#$hh` codes, juxtaposed with no
  operator -- or -1 when AArg is not wholly such a literal. }
function StringLiteralLength(const AArg: string): Integer;
var
  i, Start: Integer;
begin
  Result:= 0;
  i:= 1;
  if AArg = '' then Exit(-1);
  while i <= Length(AArg) do
  begin
    if AArg[i] = '''' then
    begin
      Inc(i);
      while True do
      begin
        if i > Length(AArg) then Exit(-1);
        if AArg[i] = '''' then
        begin
          if (i < Length(AArg)) and (AArg[i + 1] = '''') then
          begin
            Inc(Result);
            Inc(i, 2);
            Continue;
          end;
          Inc(i);
          Break;
        end;
        Inc(Result);
        Inc(i);
      end;
    end
    else if AArg[i] = '#' then
    begin
      Inc(i);
      if (i <= Length(AArg)) and (AArg[i] = '$') then Inc(i);
      Start:= i;
      while (i <= Length(AArg)) and CharInSet(AArg[i], ['0'..'9', 'a'..'f', 'A'..'F']) do Inc(i);
      if i = Start then Exit(-1);
      Inc(Result);
    end
    else Exit(-1);
  end;
end;

{ rb5-ovl: True when AArg is one bracketed constructor `[ ... ]` -- the `]`
  that closes the first `[` is the last character. Quoted text is skipped. }
function IsSetConstructor(const AArg: string): Boolean;
var
  Depth: Integer;
  InStr: Boolean;
begin
  Result:= False;
  if (Length(AArg) < 2) or (AArg[1] <> '[') or (AArg[Length(AArg)] <> ']') then Exit;
  Depth:= 0;
  InStr:= False;
  for var i:= 1 to Length(AArg) do
  begin
    if AArg[i] = '''' then InStr:= not InStr;
    if InStr then Continue;
    if AArg[i] = '[' then Inc(Depth)
    else if AArg[i] = ']' then
    begin
      Dec(Depth);
      if (Depth = 0) and (i < Length(AArg)) then Exit;
    end;
  end;
  Result:= (Depth = 0) and not InStr;
end;

{ rb5-ovl: the shape of one argument's TEXT, as LexCallArguments returns it.
  Literals and constructors only; a bare identifier is asUnknown here and is
  typed by TCallResolver.VariableArgShape. Numbers: [sign] ( $hex | digits
  [. digits] [e [sign] digits] ) -- anything after them makes an expression. }
function ArgShapeOfText(const AArg: string): TArgShape;
var
  Len: Integer;
begin
  Len:= StringLiteralLength(AArg);
  Result:=
    if AArg = '' then asUnknown
    else if SameText(AArg, 'nil') then asNilLit
    else if SameText(AArg, 'True') or SameText(AArg, 'False') then asBoolLit
    else if IsSetConstructor(AArg) then asSetLit
    else if Len = 1 then asCharLit
    else if Len >= 0 then asStrLit
    else if TRegEx.IsMatch(AArg, '^[+-]?(\d+|\$[0-9A-Fa-f]+)$') then asIntLit
    else if TRegEx.IsMatch(AArg, '^[+-]?\d+(\.\d+([eE][+-]?\d+)?|[eE][+-]?\d+)$') then asFloatLit
    else asUnknown;
end;
{ rb5-ovl: True when AArg is one plain identifier (no dot, call, selector or operator). }
function IsPlainIdent(const AArg: string): Boolean;
begin
  if (AArg = '') or not IsIdentStart(AArg[1]) then Exit(False);
  for var i:= 2 to Length(AArg) do
    if not IsIdentPart(AArg[i]) then Exit(False);
  Result:= True;
end;

{ rb5-ovl: may an argument of shape AShape be passed to the parameter whose
  ParamTypeKey group is AParamKey (`modifier:type`)? A literal or constructor
  can never be passed to a var / out parameter; a VARIABLE to one needs its
  exact type, which the shape does not carry, so that is afMaybe. }
function ArgFitsParam(AShape: TArgShape; const AParamKey: string): TArgFit;
var
  Colon   : Integer;
  Modifier: string;
  TypeKey : string;
begin
  if AShape = asUnknown then Exit(afMaybe);
  Colon:= Pos(':', AParamKey);
  if Colon = 0 then Exit(afMaybe);
  Modifier:= Copy(AParamKey, 1, Colon - 1);
  if (Modifier = 'var') or (Modifier = 'out') then
    Exit(if AShape in LITERAL_SHAPES then afNo else afMaybe);
  TypeKey:= Copy(AParamKey, Colon + 1, MaxInt);
  Result := ARG_FIT[AShape, ParamFamily(TypeKey)];
  { A string or char for an OPEN ARRAY is afMaybe in the table because of
    `array of Char`; for any other known element type (`array of const`,
    `array of Integer`, `array of string`) it needs a `[..]` constructor. }
  if (Result = afMaybe) and (ParamFamily(TypeKey) = pfOpenArray)
     and (AShape in [asStrLit, asCharLit, asStrVar, asCharVar]) then
  begin
    var Element: string:= Copy(TypeKey, Length(OPEN_ARRAY_PREFIX) + 1, MaxInt);
    if (Element = 'const') or (ParamFamily(Element) in [pfInt, pfFloat, pfString, pfBool, pfVariant, pfPChar, pfPointer]) then
      Result:= afNo;
  end;
end;

function TCallResolver.VariableArgShape(const AName: string): TArgShape;
var
  Txt  : TRcvTypeText;
  Saved: TWithScopeStats;
begin
  Result:= asUnknown;
  if (AName = '') or SameText(AName, 'Self') or SameText(AName, 'Result') then Exit;
  Saved:= FWith.Stats;
  TypeReceiver(FSiteRef, AName, Txt);
  FWith.Stats:= Saved;
  if (Txt.Pending <> '') or (Txt.Text = '') then Exit;
  case ParamFamily(LowerCase(StringReplace(Txt.Text, ' ', '', [rfReplaceAll]))) of
    pfInt   : Result:= asIntVar;
    pfFloat : Result:= asFloatVar;
    pfString: Result:= asStrVar;
    pfChar  : Result:= asCharVar;
    pfBool  : Result:= asBoolVar;
  end;
end;

function TCallResolver.SiteArgShapes(AArgCount: Integer; out AShapes: TArray<TArgShape>): Boolean;
var
  Line, Col, N: Integer;
  Name        : string;
  Slice, Args : TArray<string>;
begin
  AShapes:= nil;
  if (FSiteLines = nil) or (AArgCount <= 0) or (AArgCount <> FSiteArgCount) then Exit(False);
  if FSiteShapesState = 0 then
  begin
    FSiteShapesState:= 2;
    Line:= FSiteRef.StartLine;
    Col := FSiteRef.StartCol;
    Name:= FSiteRef.NameText;
    { The ref must point AT its name, or the column after it is not where the
      argument list starts. }
    if (Line < 1) or (Line > FSiteLines.Count) or (Col < 1) or (Name = '')
       or not SameText(Copy(FSiteLines[Line - 1], Col, Length(Name)), Name) then Exit(False);
    N:= Min(FSiteLines.Count - Line + 1, CMaxArgListLines + 1);
    SetLength(Slice, N);
    for var i:= 0 to N - 1 do Slice[i]:= FSiteLines[Line - 1 + i];
    if not LexCallArguments(Slice, 1, Col + Length(Name), Args) or (Length(Args) <> AArgCount) then Exit(False);
    SetLength(FSiteShapes, Length(Args));
    for var i:= 0 to High(Args) do
    begin
      FSiteShapes[i]:= ArgShapeOfText(Args[i]);
      if (FSiteShapes[i] = asUnknown) and IsPlainIdent(Args[i]) then
        FSiteShapes[i]:= VariableArgShape(Args[i]);
    end;
    FSiteShapesState:= 1;
  end;
  Result:= (FSiteShapesState = 1) and (Length(FSiteShapes) = AArgCount);
  if Result then AShapes:= FSiteShapes;
end;

procedure TCallResolver.NarrowByArgShapes(AFit: TList<TSymbol>; AArgCount: Integer);
var
  Shapes  : TArray<TArgShape>;
  Keep    : TList<TSymbol>;
  Params  : TArray<string>;
  Lo, Hi  : Integer;
  Rejected: Boolean;
begin
  { Same-arity overloads that differ only by parameter TYPE (ORM3's
    IABZLoggingSys.LogMessage: `array of const` vs `cardinal` in position 3,
    159 ambiguous sites on CLIENT). Delphi's own overload resolution ranks
    conversions; this does not -- it only DROPS a candidate the compiler could
    not have chosen, so an Integer-vs-Double tie on a literal 5 stays a tie. }
  if AFit.Count < 2 then Exit;
  if not SiteArgShapes(AArgCount, Shapes) then Exit;
  Keep:= TList<TSymbol>.Create;
  try
    for var S in AFit do
    begin
      Params  := ParamTypeKey(S.Signature).Split([';'], TStringSplitOptions.ExcludeEmpty);
      Rejected:= False;
      { A group count that disagrees with the arity range (a `;` inside a quoted
        default value) would misalign argument and parameter: keep it. }
      if SignatureArityRange(S.Signature, Lo, Hi) and (Length(Params) = Hi) and (AArgCount <= Hi) then
        for var i:= 0 to AArgCount - 1 do
          if ArgFitsParam(Shapes[i], Params[i]) = afNo then
          begin
            Rejected:= True;
            Break;
          end;
      if not Rejected then Keep.Add(S);
    end;
    if (Keep.Count > 0) and (Keep.Count < AFit.Count) then
    begin
      AFit.Clear;
      AFit.AddRange(Keep);
    end;
  finally
    Keep.Free;
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

    { rb5-ovl: a same-arity tie is narrowed by the argument SHAPES -- only a
      candidate no argument could be passed to is dropped. }
    if AArgsKnown and (Fit.Count > 1) then NarrowByArgShapes(Fit, AArgCount);

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
    // X2: a class's IMPLEMENTED interfaces are not on its member chain; they
    // answer only below, when the chain declared nothing.
    for A in AncestorsOf(ATypeSymbolId) do
    begin
      if not A.Resolved or (A.SymbolId <= 0) or IsImplementedInterface(ATypeSymbolId, A) then Continue;
      Kids:= ChildrenOf(A.SymbolId);
      if Kids = nil then Continue;
      for S in Kids do
        if (S.Kind in METHOD_KINDS) and SameText(S.Name, AMethodName) then Matches.Add(S);
    end;
    // 2b. X2: the implemented interfaces, as a fallback only -- the method is
    // then implemented in an ancestor the index does not hold, and the
    // interface method is the nearest declaration it has (the pre-X2 answer).
    if Matches.Count = 0 then
      for A in AncestorsOf(ATypeSymbolId) do
      begin
        if not A.Resolved or (A.SymbolId <= 0) or not IsImplementedInterface(ATypeSymbolId, A) then Continue;
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
        for A in AncestorsOf(ATypeSymbolId) do
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
      Scope:= SymbolById(ScopeId);
      if (Scope.Id <= 0) or (Scope.ParentId <= 0) then Exit;
      Parent:= SymbolById(Scope.ParentId);
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
    Scope:= SymbolById(ScopeId);
    if (Scope.Id <= 0) or (Scope.ParentId <= 0) then Exit;
    Parent:= SymbolById(Scope.ParentId);
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
    Scope:= SymbolById(ScopeId);
    if (Scope.Id <= 0) or (Scope.ParentId <= 0) then Exit;
    Parent:= SymbolById(Scope.ParentId);
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
  for A in AncestorsOf(AClassId) do
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

function TCallResolver.ResolveEnumValueRead(const ARef: TReference; out AReason: string): Int64;  // dl:ok too-many-exit-points@b863 -- REVIEWED 2026-10-26 (E14 added the scoped exit; first reviewed 2026-09-23): each exit is a DISTINCT outcome the caller and the counters must tell apart -- not a candidate name, a with member (1.8.0, R7), scoped (E14), not visible, ambiguous, shadowed (a/b), shadowed (c), bound. Every one sets AReason and increments its own counter before leaving; merging them behind a single exit would put six reasons through one assignment and is exactly how a decline becomes unauditable.

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

  { W5-ext (N-04): True when ARoutineId is the ref's enclosing routine or one it
    is nested in. A routine-local enum's values are in scope only there; the
    climb stops at the first non-routine parent, as LexicalScopeDeclaresValue's. }
  function RoutineOnChain(ARoutineId: Int64): Boolean;
  var
    ScopeId: Int64  ;
    Scope  : TSymbol;
    Depth  : Integer;
  begin
    Result := False;
    ScopeId:= ARef.EnclosingSymbolId;
    Depth  := 0;
    while (ScopeId > 0) and (Depth < MAX_LEXICAL_DEPTH) do
    begin
      if ScopeId = ARoutineId then Exit(True);
      Inc(Depth);
      Scope:= SymbolById(ScopeId);
      if (Scope.Id <= 0) or (Scope.ParentId <= 0) then Exit;
      if not (SymbolById(Scope.ParentId).Kind in METHOD_KINDS) then Exit;
      ScopeId:= Scope.ParentId;
    end;
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

  { --- R7 (1.8.0): the `with` scope is nearer than anything below. A target that
    declares the name makes the read a read of THAT member -- decline, and the
    member-read pass binds the member. An untypable target keeps the pre-1.8
    answer (counted, see ResolveEnumValueRead's remarks). }
  var WithType: Int64;
  var WithKind: TWithMemberKind;
  var Verdict : TWithVerdict:= WithScopeAt(ARef, ARef.StartLine, ARef.StartCol,
                                            ARef.NameText, WithType, WithKind);
  if Verdict = wvMember then
  begin
    AReason:= 'with-member';
    Inc(FEnumStats.WithMember);
    Exit;
  end;

  { The enclosing class is needed TWICE -- by the nested-enum visibility test
    below and by R3(b) -- and finding it costs two GetSymbolById per lexical
    level, so it is walked once here and both answers kept. }
  ClassShadows:= EnclosingClassChainDeclares(ARef.EnclosingSymbolId, ARef.NameText, ClassId);

  { --- R1 visibility, plus the nested-enum rule (plan ruling 4). A value whose
    enum is declared INSIDE a type is reachable by its BARE name only from that
    type or a descendant of it; treating such a value as unit-scoped is how a
    bare identifier binds to a declaration the compiler would not have seen. }
  Visible:= nil;
  var ScopedOnly: Boolean:= False;
  for var C: TEnumValueDecl in Cands do
  begin
    if not VisibleHere(C.FileId, C.Section) then Continue;
    if C.OwnerTypeId > 0 then
    begin
      OwnerOk:= (ClassId > 0) and (ClassId = C.OwnerTypeId);
      if not OwnerOk and (ClassId > 0) then
        for A in AncestorsOf(ClassId) do
          if A.Resolved and (A.SymbolId = C.OwnerTypeId) then
          begin
            OwnerOk:= True;
            Break;
          end;
      if not OwnerOk then Continue;
    end;
    if (C.OwnerRoutineId > 0) and not RoutineOnChain(C.OwnerRoutineId) then Continue;
    { E14: a value of a SCOPEDENUMS enum is in scope here but not under its BARE
      name -- only TEnum.Value reaches it -- so it is no candidate at all. }
    if C.Scoped then
    begin
      ScopedOnly:= True;
      Continue;
    end;
    Visible:= Visible + [C];
  end;
  { A routine-local value in scope is NEARER than any unit-level one of the
    same name (the compiler resolves innermost first), so it alone competes. }
  var LocalOnly: TArray<TEnumValueDecl>:= nil;
  for var C: TEnumValueDecl in Visible do
    if C.OwnerRoutineId > 0 then LocalOnly:= LocalOnly + [C];
  if Length(LocalOnly) > 0 then Visible:= LocalOnly;

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
  if (Length(Visible) = 0) and ScopedOnly then
  begin
    AReason:= 'scoped';
    Inc(FEnumStats.Scoped);
    Exit;
  end;
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
  if Verdict = wvUndecided then Inc(FEnumStats.WithUndecided);
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
  statement there: nothing, `;`, a comment, or a keyword that closes a block. }
function EndsStatement(const AAfter: string): Boolean;
const
  BLOCK_CLOSERS: array[0..4] of string = ('end', 'else', 'until', 'except', 'finally');
var
  L: string;
begin
  L     := LowerCase(AAfter);
  Result:= (L = '') or StartsStr(';', L) or StartsStr('//', L) or StartsStr('{', L) or StartsStr('(*', L);
  { 1.8.0: the text after a name can now come from the NEXT line (D16c), where a
    statement left without its `;` is closed by any block keyword. }
  for var W: string in BLOCK_CLOSERS do
    Result:= Result or StartsWithWord(L, W);
end;

{ ALine without a trailing `//` comment -- one outside a string literal. }
function StripLineComment(const ALine: string): string;
var
  K    : Integer;
  InStr: Boolean;
begin
  Result:= ALine;
  InStr := False;
  for K:= 1 to Length(ALine) - 1 do
    if ALine[K] = '''' then InStr:= not InStr
    else if not InStr and (ALine[K] = '/') and (ALine[K + 1] = '/') then Exit(Copy(ALine, 1, K - 1));
end;

{ True when a declaration's type text is itself a procedural type.

  D16b (1.8.0): the generic zero-argument function types the PROJECT index
  never holds -- System.SysUtils' `TFunc<T>` and Spring4D's `Func<T>` -- are
  recognised by NAME, and a UNIT-QUALIFIED spelling (`System.SysUtils.TFunc<T>`)
  by its last segment. Before, the qualified spelling fell through to
  ResolveTypeNameToSymbol, found nothing, and the parenless read BOUND as a call
  where the source passed the routine as a value. A library ALIAS of such a type
  (`TIntFunc = TFunc<Integer>` declared in a library unit) is still not seen:
  that stays the pass's documented blind spot. }
function IsProceduralText(const AText: string): Boolean;
var
  L   : string ;
  Lt  : Integer;
  Base: string ;
begin
  L:= LowerCase(Trim(AText));
  Result:= StartsWithWord(L, 'procedure') or StartsWithWord(L, 'function')
           or StartsStr('reference to', L);
  if Result then Exit;
  Lt:= Pos('<', L);
  if Lt = 0 then Exit;
  Base:= Trim(Copy(L, 1, Lt - 1));
  if LastDelimiter('.', Base) > 0 then Base:= Copy(Base, LastDelimiter('.', Base) + 1, MaxInt);
  Result:= (Base = 'tfunc') or (Base = 'func');
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

type
  { One code token of a routine's text: a lowercased identifier, keyword or
    number, `:=`, or one punctuation character. }
  TCodeTok = record
    Text: string ;
    Line: Integer;
    Col : Integer;
  end;

{ Review 2026-10-23: the code tokens of ALines (1-based lines and columns) from
  (AFromLine, AFromCol) up to, not including, (AToLine, AToCol). Comments --
  braces, paren-star, `//` -- and string literals are skipped; the start is
  assumed to lie outside a comment. }
function CodeTokens(ALines: TStringList; AFromLine, AFromCol, AToLine, AToCol: Integer): TArray<TCodeTok>;
var
  Toks   : TList<TCodeTok>;
  S      : string         ;
  K      : Integer        ;
  Ln     : Integer        ;
  InBrace: Boolean        ;
  InStar : Boolean        ;

  { True when S[K] opens the two-character token ATwo. }
  function OpensPair(const ATwo: string): Boolean;
  begin
    Result:= (K < Length(S)) and (S[K] = ATwo[1]) and (S[K + 1] = ATwo[2]);
  end;

  { Consumes S[K] when it is comment, string or blank text, or opens a comment
    or string, advancing K past what it consumed. False leaves K untouched. }
  function SkipNonCode: Boolean;
  begin
    Result:= True;
    if InBrace then
      InBrace:= S[K] <> '}'
    else if InStar then
    begin
      InStar:= not OpensPair('*)');
      if not InStar then Inc(K);
    end
    else if S[K] = '{' then
      InBrace:= True
    else if OpensPair('(*') then
    begin
      InStar:= True;
      Inc(K);
    end
    else if S[K] = '''' then
    begin
      Inc(K);
      while (K <= Length(S)) and (S[K] <> '''') do Inc(K);
    end
    else
      Result:= CharInSet(S[K], [' ', #9]);
    if Result then Inc(K);
  end;

  { Adds the token at S[K] -- an identifier or number, `:=`, or one character. }
  procedure TakeToken;
  var
    Tok: TCodeTok;
    W  : Integer ;
  begin
    W:= K;
    if IsIdentPart(S[K]) then
      while (K <= Length(S)) and IsIdentPart(S[K]) do Inc(K)
    else if OpensPair(':=') then
      Inc(K, 2)
    else
      Inc(K);
    Tok.Text:= LowerCase(Copy(S, W, K - W));
    Tok.Line:= Ln;
    Tok.Col := W;
    Toks.Add(Tok);
  end;

begin
  Toks   := TList<TCodeTok>.Create;
  InBrace:= False;
  InStar := False;
  try
    for Ln:= Max(AFromLine, 1) to Min(AToLine, ALines.Count) do
    begin
      S:= ALines[Ln - 1];
      K:= (if Ln = AFromLine then Max(AFromCol, 1) else 1);
      while (K <= Length(S)) and ((Ln < AToLine) or (K < AToCol)) do
        if SkipNonCode then Continue
        else if OpensPair('//') then Break
        else TakeToken;
    end;
    Result:= Toks.ToArray;
  finally
    Toks.Free;
  end;
end;

{ Review 2026-10-23: the block-depth change a statement-level token makes --
  +1 for a token that opens a block closed by `end` / `until`, -1 for those. }
function BlockDelta(const ATok: string): Integer;
begin
  if Pos('|' + ATok + '|', '|begin|try|case|repeat|asm|record|') > 0 then Result:= 1
  else if Pos('|' + ATok + '|', '|end|until|') > 0 then Result:= -1
  else Result:= 0;
end;

{ Review 2026-10-23: whether the local declared at (ALine, ACol) is an INLINE
  `var` -- `var` right before its name, past earlier names of the same list
  (`var A, B: T`). AIsFor: it is a `for var` loop variable. }
function InlineVarAt(ALines: TStringList; ALine, ACol: Integer; out AIsFor: Boolean): Boolean;
var
  Head: TArray<TCodeTok>;
  K   : Integer         ;
begin
  Head:= CodeTokens(ALines, ALine, 1, ALine, ACol);
  K   := High(Head);
  while (K >= 1) and (Head[K].Text = ',') do Dec(K, 2);
  Result:= (K >= 0) and (Head[K].Text = 'var');
  AIsFor:= Result and (K >= 1) and (Head[K - 1].Text = 'for');
end;

{ Review 2026-10-23: whether the block an inline declaration sits in is still
  open after AToks -- the tokens from the declaration to a site. A `for var`
  loop's scope is its body: the begin..end after `do`, or the one statement up
  to its `;`. Any other inline var lives to the end of its enclosing block. }
function InlineScopeOpen(const AToks: TArray<TCodeTok>; AIsFor: Boolean): Boolean;
var
  K     : Integer;
  T     : string ;
  InBody: Boolean;
  Single: Boolean;
  Depth : Integer;
  Paren : Integer;
begin
  Result:= True;
  InBody:= not AIsFor;
  Single:= False;
  Depth := 0;
  Paren := 0;
  for K:= 0 to High(AToks) do
  begin
    T:= AToks[K].Text;
    if (T = '(') or (T = '[') then Inc(Paren)
    else if (T = ')') or (T = ']') then Dec(Paren);
    if not InBody then
    begin
      { The loop header: the body starts after its `do`. }
      InBody:= (T = 'do') and (Paren = 0);
      Single:= InBody and (K < High(AToks)) and (AToks[K + 1].Text <> 'begin');
      Continue;
    end;
    Inc(Depth, BlockDelta(T));
    if (Depth < 0) or (AIsFor and (Depth = 0) and (if Single then (T = ';') and (Paren = 0) else T = 'end')) then
      Exit(False);
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
      Scope:= SymbolById(ScopeId);
      ScopeId:= 0;
      if (Scope.Id > 0) and (Scope.ParentId > 0)
         and (SymbolById(Scope.ParentId).Kind in METHOD_KINDS) then ScopeId:= Scope.ParentId;
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
  var Before: Integer:= AMatches.Count;
  AddFrom(ATypeId);
  { X2: a class's implemented interfaces answer only when its own chain
    declares nothing -- the LookupMethodOnType rule. }
  for A in AncestorsOf(ATypeId) do
    if A.Resolved and (A.SymbolId > 0) and not IsImplementedInterface(ATypeId, A) then AddFrom(A.SymbolId);
  if AMatches.Count = Before then
    for A in AncestorsOf(ATypeId) do
      if A.Resolved and (A.SymbolId > 0) and IsImplementedInterface(ATypeId, A) then AddFrom(A.SymbolId);
end;

function TCallResolver.IsImplementedInterface(AOwnerId: Int64; const AAncestor: TTypeAncestor): Boolean;
begin
  Result:= (AAncestor.SymbolId > 0) and (SymbolById(AAncestor.SymbolId).Kind = skInterface)
    and (SymbolById(AOwnerId).Kind <> skInterface);
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
    for A in AncestorsOf(AClassId) do
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
    for V in E do Result:= Result or (not V.Scoped and Visible(V.FileId, V.Section));  { E14: a scoped value shadows nothing }
end;

function TCallResolver.UnitLevelValueVisible(ARefFileId: Int64; const ALc: string): Boolean;
var
  L: TList<TSymbol>;
  S: TSymbol       ;
begin
  Result:= False;
  if not FNameToUnitValues.TryGetValue(ALc, L) then Exit;
  for S in L do
    if (S.FileId = ARefFileId)
       or (SameText(S.Section, 'interface') and CandInScope(ARefFileId, S.FileId)) then Exit(True);
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

{ ---- 2026-09-23: the `with` scope (resolver 1.8.0-alpha, defect D14). ----

  Delphi resolves a bare identifier inside `with A, B do S` against the members
  of B's type, then A's, then the targets of every enclosing with (innermost
  first) -- and only THEN against the ordinary scope, locals included. The
  resolver had no with scope, so a bare call in a with body bound to the
  enclosing class's same-named method (the declaration the compiler does not
  pick), a member access whose receiver was a with member never typed (0 of 283
  on ORM3 CLIENT), and a bare read naming a with member bound to an enum value
  of that name (R7).

  THE TABLE COMES FROM THE SOURCE, NOT THE INDEX. The index stores neither with
  spans nor with targets, and storing them would be an EXTRACTOR change -- a
  re-parse of every database. So the file is parsed here, with the grammar and
  the byte transform the indexer itself applies (EnsureUtf8Bytes, then
  NormalizeLoneCR), which puts a with body's line/column in exactly the
  coordinates refs are stored in. The indexer's IFDEF preprocessing blanks
  bytes without moving them, so positions agree; the grammar keeps the FIRST
  branch of an IFDEF on its own, which is the one residual (a with that exists
  only in a taken ELSE branch is not in this table). Only files whose text
  holds the keyword are parsed at all.

  THE POSTURE is the unit's: bind the member the compiler binds, or NOTHING. A
  target whose type cannot be resolved, or whose ancestry leaves the index, may
  declare any name, so every bare name under it is UNDECIDED and binds nothing
  -- the one documented exception being the enum-value pass (see
  ResolveEnumValueRead). }

{ True when line/column (AL1, AC1) is at or before (AL2, AC2). }
function PosAtOrBefore(AL1, AC1, AL2, AC2: Integer): Boolean;
begin
  Result:= (AL1 < AL2) or ((AL1 = AL2) and (AC1 <= AC2));
end;

{ The UTF-8 text of ANode in ASrc; '' for a null or out-of-range node. }
function WithNodeText(const ANode: TTSNode; const ASrc: TBytes): string;
begin
  Result:= '';
  if ANode.IsNull or (ANode.EndByte <= ANode.StartByte)
     or (Integer(ANode.EndByte) > Length(ASrc)) then Exit;
  Result:= Trim(TEncoding.UTF8.GetString(ASrc, Integer(ANode.StartByte),
                                         Integer(ANode.EndByte - ANode.StartByte)));
end;

{ Fills AEnt's shape from one with ENTITY expression. Anything not recognised
  leaves HeadKind = whUnknown, which types to 0 and so makes every bare name
  under the target undecided. Node names are the grammar's own, as
  TAstChecker.CheckWithHiding already reads them. }
procedure ReadWithEntity(const ANode: TTSNode; const ASrc: TBytes; var AEnt: TWithEntity);
var
  N     : TTSNode;
  Callee: TTSNode;
  Args  : TTSNode;
  Rhs   : string ;
begin
  N:= ANode;
  while (not N.IsNull) and (N.NodeType = 'exprParens') and (N.NamedChildCount = 1) do N:= N.NamedChild(0);
  if N.IsNull then Exit;
  if N.NodeType = 'identifier' then
  begin
    AEnt.Head    := WithNodeText(N, ASrc);
    AEnt.HeadKind:= (if SameText(AEnt.Head, 'Self') then whSelf else whName);
  end
  else if N.NodeType = 'exprBinary' then
  begin
    { `X as T` -- the target is T whatever X is. }
    if SameText(WithNodeText(N.ChildByField('operator'), ASrc), 'as') then
    begin
      AEnt.HeadKind:= whTypeCast;
      AEnt.Head    := WithNodeText(N.ChildByField('rhs'), ASrc);
    end;
  end
  else if N.NodeType = 'exprDot' then
  begin
    Rhs:= WithNodeText(N.ChildByField('rhs'), ASrc);
    if (Rhs = '') or (N.ChildByField('rhs').NodeType <> 'identifier') then Exit;
    if SameText(Rhs, 'Create') then
    begin
      AEnt.HeadKind:= whCreate;
      AEnt.Head    := WithNodeText(N.ChildByField('lhs'), ASrc);
      Exit;
    end;
    ReadWithEntity(N.ChildByField('lhs'), ASrc, AEnt);
    if AEnt.HeadKind <> whUnknown then AEnt.Steps:= AEnt.Steps + [Rhs];
  end
  else if N.NodeType = 'exprCall' then
  begin
    Callee:= N.ChildByField('entity');
    Args  := N.ChildByField('args');
    if Callee.IsNull then Exit;
    if (Callee.NodeType = 'exprDot')
       and SameText(WithNodeText(Callee.ChildByField('rhs'), ASrc), 'Create') then
    begin
      AEnt.HeadKind:= whCreate;
      AEnt.Head    := WithNodeText(Callee.ChildByField('lhs'), ASrc);
    end
    else if (Callee.NodeType = 'identifier') and (not Args.IsNull) and (Args.NamedChildCount = 1) then
    begin
      { `T(X)` -- a hard cast when T names a type. Typing decides; a function
        call of the same shape names no type and so types to 0. }
      AEnt.HeadKind:= whTypeCast;
      AEnt.Head    := WithNodeText(Callee, ASrc);
    end;
  end;
end;

{ Appends every `with` statement under ANode to AList, in PRE-ORDER: an outer
  with lands before the withs nested in its body, which is what lets
  WithScopeAt read the array backwards as innermost-first. }
procedure CollectWithStatements(const ANode: TTSNode; const ASrc: TBytes;
  AList: TList<TWithStatement>);
var
  I   : Integer       ;
  C   : TTSNode       ;
  Body: TTSNode       ;
  St  : TWithStatement;
  E   : TWithEntity   ;
  T   : string        ;
begin
  if ANode.IsNull then Exit;
  if ANode.NodeType = 'with' then
  begin
    St  := Default(TWithStatement);
    Body:= ANode.ChildByField('body');
    if not Body.IsNull then
    begin
      St.BodyLine   := Integer(Body.StartPoint.row) + 1;
      St.BodyCol    := Integer(Body.StartPoint.column) + 1;
      St.BodyEndLine:= Integer(Body.EndPoint.row) + 1;
      St.BodyEndCol := Integer(Body.EndPoint.column) + 1;
    end;
    { The entities are the named children that are neither the body nor a
      keyword/comment -- `with A, B do` is ONE node with REPEATED entity
      fields, and kWith / kDo are named children of it. }
    for I:= 0 to ANode.NamedChildCount - 1 do
    begin
      C:= ANode.NamedChild(I);
      if (not Body.IsNull) and (C.StartByte = Body.StartByte) and (C.EndByte = Body.EndByte) then Continue;
      T:= C.NodeType;
      if (T = 'comment') or ((Length(T) > 1) and (T[1] = 'k') and CharInSet(T[2], ['A'..'Z'])) then Continue;
      E        := Default(TWithEntity);
      E.Line   := Integer(C.StartPoint.row) + 1;
      E.Col    := Integer(C.StartPoint.column) + 1;
      E.EndLine:= Integer(C.EndPoint.row) + 1;
      E.EndCol := Integer(C.EndPoint.column) + 1;
      ReadWithEntity(C, ASrc, E);
      St.Entities:= St.Entities + [E];
    end;
    AList.Add(St);
  end;
  for I:= 0 to ANode.NamedChildCount - 1 do
    CollectWithStatements(ANode.NamedChild(I), ASrc, AList);
end;

function TCallResolver.WithStatementsOf(AFileId: Int64): TArray<TWithStatement>;
var
  Lines  : TStringList;
  InBrace: Boolean    ;
  InStar : Boolean    ;
  Found  : Boolean    ;
  I      : Integer    ;
  Src    : TBytes     ;
  Parser : TTSParser  ;
  Tree   : TTSTree    ;
  List   : TList<TWithStatement>;
  Whole  : TWithStatement;
begin
  if FWith.Statements.TryGetValue(AFileId, Result) then Exit;
  Result := nil;
  Lines  := LinesOf(AFileId);
  Found  := False;
  InBrace:= False;
  InStar := False;
  if Lines <> nil then
    for I:= 0 to Lines.Count - 1 do
      if LineHasWithKeyword(Lines[I], InBrace, InStar) then
      begin
        Found:= True;
        Break;
      end;
  if Found then
  begin
    List:= TList<TWithStatement>.Create;
    try
      try
        Src   := NormalizeLoneCR(EnsureUtf8Bytes(TFile.ReadAllBytes(FStore.GetFilePath(AFileId))));
        Parser:= TTSParser.Create;
        try
          Parser.Language:= TreeSitterDelphi13;
          Tree:= Parser.Parse(
            function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
            var Remaining: Integer;
            begin
              Remaining:= Max(0, Length(Src) - Integer(AByteIndex));
              SetLength(Result, Remaining);
              if Remaining > 0 then Move(Src[AByteIndex], Result[0], Remaining);
              ABytesRead:= Remaining;
            end, TTSInputEncoding.TSInputEncodingUTF8);
        finally
          Parser.Free;
        end;
        if Tree = nil then raise EInOutError.Create('with scope: the parse produced no tree');
        try
          CollectWithStatements(Tree.RootNode, Src, List);
        finally
          Tree.Free;
        end;
        Result:= List.ToArray;
        Inc(FWith.Stats.Files);
        Inc(FWith.Stats.Statements, List.Count);
      except
        on Exception do
        begin
          { The keyword is there and the statements could not be read: one
            whole-file statement with an untypable target makes every bare name
            in the file UNDECIDED. Never "no with here". }
          Whole            := Default(TWithStatement);
          Whole.BodyLine   := 1;
          Whole.BodyCol    := 1;
          Whole.BodyEndLine:= MaxInt;
          Whole.BodyEndCol := MaxInt;
          SetLength(Whole.Entities, 1);
          Whole.Entities[0].State:= 2;
          Result:= [Whole];
        end;
      end;
    finally
      List.Free;
    end;
  end;
  FWith.Statements.Add(AFileId, Result);
end;

function TCallResolver.TypeOfMember(ATypeId: Int64; const AName: string): Int64;
var
  M     : TSymbol;
  R     : TSymbol;
  Conf  : string ;
  Target: Int64  ;
begin
  Result:= 0;
  if ATypeId <= 0 then Exit;
  M:= LookupMemberOnType(ATypeId, AName);
  if M.Id > 0 then Exit(ResolveTypeNameToSymbol(M.Signature, M.FileId));
  { A zero-argument function member stands for its result: `with Obj.Current do`. }
  Target:= LookupMethodOnType(ATypeId, AName, 0, True, Conf);
  if (Target <= 0) or (Conf <> 'certain') then Exit;
  R:= SymbolById(Target);
  if IsParenlessCallable(R) then Result:= ResolveTypeNameToSymbol(SignatureReturnType(R.Signature), R.FileId);
end;

function TCallResolver.TypeOfBareName(const ARef: TReference; ALine, ACol: Integer;
  const AName: string): Int64;
var
  LT     : Int64          ;
  K      : TWithMemberKind;
  ClassId: Int64          ;
begin
  Result:= 0;
  { An outer with target is nearer than any local -- the name is typed through
    it, or not at all when it is undecided. }
  case WithScopeAt(ARef, ALine, ACol, AName, LT, K) of
    wvMember: if K in [wmValue, wmRoutine] then Result:= TypeOfMember(LT, AName);
    wvNone:
      if SameText(AName, 'Self') then
      begin
        EnclosingClassChainDeclares(ARef.EnclosingSymbolId, '', ClassId);
        Result:= ClassId;
      end
      else
        Result:= TypeOfOrdinaryName(ARef, AName);
  end;
end;

function TCallResolver.TypeOfOrdinaryName(const ARef: TReference; const AName: string): Int64;
var
  Ignored: string;
begin
  Result:= TypeOfOrdinaryName(ARef, AName, Ignored);
end;

function TCallResolver.TypeOfOrdinaryName(const ARef: TReference; const AName: string; out ATypeText: string): Int64;
var
  M      : TSymbol       ;
  ClassId: Int64         ;
  L      : TList<TSymbol>;
  S      : TSymbol       ;
  Hits   : Integer       ;
  Declared: Boolean      ;
begin
  ATypeText:= '';
  { A local or parameter: the nearest declaration covering the site. One that
    covers nothing here types to nothing, and still shadows everything below. }
  M:= LocalInScopeAt(ARef, AName, Declared);
  ATypeText:= Trim(M.Signature);
  if M.Id > 0 then Exit(ResolveTypeNameToSymbol(M.Signature, ARef.FileId));
  if Declared then Exit(0);
  EnclosingClassChainDeclares(ARef.EnclosingSymbolId, '', ClassId);
  M:= LookupMemberOnType(ClassId, AName);
  ATypeText:= Trim(M.Signature);
  if M.Id > 0 then Exit(ResolveTypeNameToSymbol(M.Signature, M.FileId));
  { A unit-level var visible from here: exactly one, or nothing. }
  Hits:= 0;
  if FNameToUnitValues.TryGetValue(LowerCase(AName), L) then
    for S in L do
      if (S.Kind = skVarDecl) and ((S.FileId = ARef.FileId)
         or (SameText(S.Section, 'interface') and CandInScope(ARef.FileId, S.FileId))) then
      begin
        Inc(Hits);
        M:= S;
      end;
  { Last: the name IS a type -- `with TFoo do` reaches its class members. }
  if Hits = 0 then
  begin
    Result:= ResolveTypeNameToSymbol(AName, ARef.FileId);
    if Result > 0 then ATypeText:= AName;
  end
  else if Hits = 1 then
  begin
    ATypeText:= Trim(M.Signature);
    Result:= ResolveTypeNameToSymbol(M.Signature, M.FileId);
  end
  else Result:= 0;
end;

function TCallResolver.TypeOfFunctionResult(const ARef: TReference; const AName: string): Int64;
var
  Ignored: string;
begin
  Result:= TypeOfFunctionResult(ARef, AName, Ignored);
end;

function TCallResolver.TypeOfFunctionResult(const ARef: TReference; const AName: string; out ARetText: string): Int64;
var
  Probe  : TReference    ;
  Matches: TList<TSymbol>;
  S      : TSymbol       ;
  RetType: string        ;
  TypeId : Int64         ;
begin
  Result  := 0;
  ARetText:= '';
  if AName = '' then Exit;
  Probe         := ARef;
  Probe.NameText:= AName;
  Matches       := TList<TSymbol>.Create;
  try
    if FindParenlessCandidates(Probe, '', Matches) <> '' then Exit;
    { Item 4: the return type TEXT, when every candidate writes the same leaf
      -- known even when the type is a library one. }
    for S in Matches do
    begin
      RetType:= NormalizeTypeLeaf(SignatureReturnType(S.Signature));
      if (RetType = '') or ((ARetText <> '') and not SameText(RetType, ARetText)) then
      begin
        ARetText:= '';
        Break;
      end;
      ARetText:= RetType;
    end;
    { Every candidate must be a function, and all must name ONE type: the
      return type is resolved in the DECLARING unit's scope, where it is
      written. }
    for S in Matches do
    begin
      RetType:= SignatureReturnType(S.Signature);
      TypeId := if RetType = '' then 0 else ResolveTypeNameToSymbol(RetType, S.FileId);
      if (TypeId = 0) or ((Result > 0) and (TypeId <> Result)) then Exit(0);
      Result:= TypeId;
    end;
  finally
    Matches.Free;
  end;
end;

function TCallResolver.WithEntityType(const ARef: TReference; const AStmts: TArray<TWithStatement>;
  AStmt, AEnt: Integer): Int64;
var
  E: TWithEntity;
  T: Int64      ;
  K: Integer    ;
begin
  E:= AStmts[AStmt].Entities[AEnt];
  if E.State = 2 then Exit(E.TypeId);
  if E.State = 1 then Exit(0); { a cycle -- cannot happen for well-formed nesting }
  AStmts[AStmt].Entities[AEnt].State:= 1;
  T:= 0;
  case E.HeadKind of
    whSelf               : EnclosingClassChainDeclares(ARef.EnclosingSymbolId, '', T);
    whTypeCast, whCreate : T:= ResolveTypeNameToSymbol(E.Head, ARef.FileId);
    whName               : T:= TypeOfBareName(ARef, E.Line, E.Col, E.Head);
  end;
  for K:= 0 to High(E.Steps) do
    if T > 0 then T:= TypeOfMember(T, E.Steps[K]);
  if (T > 0) and not (SymbolById(T).Kind in TYPE_KINDS) then T:= 0;
  AStmts[AStmt].Entities[AEnt].TypeId:= T;
  AStmts[AStmt].Entities[AEnt].State := 2;
  Result:= T;
end;

{ True when AName is a member every class (TObject) or every interface
  (IInterface) has, which the PROJECT index never holds. A with target always
  has them, so a bare `Free` under one names the target's Free -- which cannot
  be bound here, and must not fall through to a same-named routine outside.
  The class list is TAstChecker.CheckWithHiding's floor. }
function IsFloorMember(AOwnerKind: TSymbolKind; const AName: string): Boolean;
const
  OBJECT_FLOOR: array[0..24] of string = (
    'Free', 'Create', 'Destroy', 'ClassName', 'ClassType', 'ClassParent',
    'ClassInfo', 'InstanceSize', 'InheritsFrom', 'ToString', 'Equals',
    'GetHashCode', 'DisposeOf', 'FieldAddress', 'GetInterface',
    'GetInterfaceEntry', 'GetInterfaceTable', 'UnitName', 'QualifiedClassName',
    'SafeCallException', 'AfterConstruction', 'BeforeDestruction', 'Dispatch',
    'DefaultHandler', 'NewInstance');
  INTF_FLOOR: array[0..2] of string = ('QueryInterface', '_AddRef', '_Release');
begin
  Result:= False;
  if AOwnerKind = skClass then
  begin
    for var F: string in OBJECT_FLOOR do
      Result:= Result or SameText(F, AName);
  end
  else if AOwnerKind = skInterface then
    for var F: string in INTF_FLOOR do
      Result:= Result or SameText(F, AName);
end;

function TCallResolver.LevelMemberKind(ALevelId: Int64; const AName: string;
  ARefFileId: Int64): TWithMemberKind;
var
  Kids      : TList<TSymbol>;
  S         : TSymbol       ;
  HasValue  : Boolean       ;
  HasRoutine: Boolean       ;
  HasOther  : Boolean       ;
  Hidden    : Boolean       ;
begin
  HasValue  := False;
  HasRoutine:= False;
  HasOther  := False;
  Hidden    := False;
  Kids      := ChildrenOf(ALevelId);
  if Kids <> nil then
    for S in Kids do
      if SameText(S.Name, AName) and not (S.Kind in [skLocalVar, skParam]) then
      begin
        { A private or protected member of a type declared in ANOTHER unit is
          not in scope from here, so the name would fall through to an outer
          scope -- which this cannot confirm. Undecided, not "absent". }
        if (S.FileId <> ARefFileId)
           and (ContainsText(S.Modifiers, 'private') or ContainsText(S.Modifiers, 'protected')) then
          Hidden:= True
        else if S.Kind in [skProperty, skField] then HasValue:= True
        else if S.Kind in METHOD_KINDS then HasRoutine:= True
        else HasOther:= True;
      end;
  if Hidden or (HasValue and HasRoutine) then Result:= wmUnknown
  else if HasValue then Result:= wmValue
  else if HasRoutine then Result:= wmRoutine
  else if HasOther then Result:= wmOther
  else Result:= wmNone;
end;

function TCallResolver.WithMemberKind(ATypeId: Int64; const AName: string;
  ARefFileId: Int64): TWithMemberKind;
var
  A   : TTypeAncestor;
  Conf: string       ;
begin
  { The NEAREST declaring level decides, as in Delphi's own member lookup: the
    type itself, then each resolved ancestor in order. }
  Result:= LevelMemberKind(ATypeId, AName, ARefFileId);
  if Result = wmNone then
    for A in AncestorsOf(ATypeId) do
      if (Result = wmNone) and A.Resolved and (A.SymbolId > 0) then
        Result:= LevelMemberKind(A.SymbolId, AName, ARefFileId);
  { A class or record HELPER's method is in the with scope too. }
  if (Result = wmNone) and (LookupMethodOnType(ATypeId, AName, 0, False, Conf) > 0) then Result:= wmRoutine;
  if (Result = wmNone) and IsFloorMember(SymbolById(ATypeId).Kind, AName) then Result:= wmUnknown;
end;
function TCallResolver.SurfaceComplete(ATypeId: Int64): Boolean;
var
  A: TTypeAncestor;
  N: string       ;
begin
  if FWith.SurfaceComplete.TryGetValue(ATypeId, Result) then Exit;
  Result:= True;
  for A in AncestorsOf(ATypeId) do
    if not A.Resolved or (A.SymbolId <= 0) then
    begin
      N:= LowerCase(A.Name);
      if LastDelimiter('.', N) > 0 then N:= Copy(N, LastDelimiter('.', N) + 1, MaxInt);
      { TObject / IInterface are the floor WithMemberKind already answers for;
        any other ancestor outside this index may declare anything. }
      if (N <> 'tobject') and (N <> 'iinterface') and (N <> 'iunknown') then Result:= False;
    end;
  FWith.SurfaceComplete.Add(ATypeId, Result);
end;

function TCallResolver.LayerVerdict(const ARef: TReference; const AStmts: TArray<TWithStatement>;
  AStmt, AEnt: Integer; const AName: string; out ALayerType: Int64;
  out AKind: TWithMemberKind): TWithVerdict;
var
  LT: Int64;
begin
  ALayerType:= 0;
  AKind     := wmNone;
  LT        := WithEntityType(ARef, AStmts, AStmt, AEnt);
  if LT > 0 then AKind:= WithMemberKind(LT, AName, ARef.FileId);
  if (LT <= 0) or (AKind = wmUnknown) then Result:= wvUndecided
  else if AKind <> wmNone then
  begin
    Result    := wvMember;
    ALayerType:= LT;
  end
  { Absent from a surface that leaves the index is not absent. }
  else if SurfaceComplete(LT) then Result:= wvNone
  else Result:= wvUndecided;
end;

function TCallResolver.WithScopeAt(const ARef: TReference; ALine, ACol: Integer;
  const AName: string; out ALayerType: Int64; out AKind: TWithMemberKind): TWithVerdict;
var
  Stmts: TArray<TWithStatement>;
  I, J : Integer;
  Hi   : Integer;
begin
  Result    := wvNone;
  ALayerType:= 0;
  AKind     := wmNone;
  Stmts     := nil;
  if (AName <> '') and (ALine >= 1) and (ARef.FileId > 0) then Stmts:= WithStatementsOf(ARef.FileId);
  { A file edited since it was indexed: its with spans no longer line up with
    the stored positions, so nothing here can be decided. }
  if (Length(Stmts) > 0) and FileIsStale(ARef.FileId) then Exit(wvUndecided);
  I:= High(Stmts);
  while (I >= 0) and (Result = wvNone) do
  begin
    { Inside the BODY every entity is a layer. Inside entity J (J >= 1) only
      the entities BEFORE it are: `with A, B do` is `with A do with B do`. }
    Hi:= -1;
    if PosAtOrBefore(Stmts[I].BodyLine, Stmts[I].BodyCol, ALine, ACol)
       and not PosAtOrBefore(Stmts[I].BodyEndLine, Stmts[I].BodyEndCol, ALine, ACol) then
      Hi:= High(Stmts[I].Entities)
    else
      for J:= High(Stmts[I].Entities) downto 1 do
        if (Hi < 0) and PosAtOrBefore(Stmts[I].Entities[J].Line, Stmts[I].Entities[J].Col, ALine, ACol)
           and not PosAtOrBefore(Stmts[I].Entities[J].EndLine, Stmts[I].Entities[J].EndCol, ALine, ACol) then
          Hi:= J - 1;
    { LAST-listed entity first; the first layer with an answer decides. }
    J:= Hi;
    while (J >= 0) and (Result = wvNone) do
    begin
      Result:= LayerVerdict(ARef, Stmts, I, J, AName, ALayerType, AKind);
      Dec(J);
    end;
    Dec(I);
  end;
end;
{ True when ASegs is a non-empty chain of plain identifiers -- `A`, `A.B.C`. }
function IsIdentChain(const ASegs: TArray<string>): Boolean;
var
  Seg: string ;
  J  : Integer;
begin
  Result:= Length(ASegs) > 0;
  for Seg in ASegs do
  begin
    Result:= Result and (Seg <> '') and IsIdentStart(Seg[1]);
    for J:= 2 to Length(Seg) do
      Result:= Result and IsIdentPart(Seg[J]);
  end;
end;

function TCallResolver.TypeReceiverThroughWith(const ACallRef: TReference;
  const AReceiverExpr: string; out AHandled: Boolean): Int64;
var
  Segs   : TArray<string> ;
  J      : Integer        ;
  LT     : Int64          ;
  MK     : TWithMemberKind;
  Verdict: TWithVerdict   ;
begin
  Result  := 0;
  AHandled:= False;
  { Only a plain identifier chain has a LEADING identifier the with scope can
    supply; a cast, a call or an indexer is typed by the ordinary rungs, and an
    explicit Self is never a with member. }
  Segs:= AReceiverExpr.Split(['.']);
  if not IsIdentChain(Segs) or SameText(Segs[0], 'Self') then Exit;
  Verdict := WithScopeAt(ACallRef, ACallRef.StartLine, ACallRef.StartCol, Segs[0], LT, MK);
  AHandled:= Verdict <> wvNone;
  if (Verdict = wvMember) and (MK in [wmValue, wmRoutine]) then
  begin
    Result:= TypeOfMember(LT, Segs[0]);
    for J:= 1 to High(Segs) do
      if Result > 0 then Result:= TypeOfMember(Result, Segs[J]);
  end;
  if Result > 0 then Inc(FWith.Stats.ReceiverTyped)
  else if AHandled then Inc(FWith.Stats.ReceiverDeclined);
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
  S     := SymbolById(Id);
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
  begin
    { Review 2026-10-23 (W5-res2): inside an anonymous method Result is ITS
      result -- '' unless its return type is the routine's. }
    var AnonDeclined: Boolean;
    Result:= ResultTypeAt(ARef, AnonDeclined);
  end
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

function TCallResolver.ParenlessIsProcValue(const ARef: TReference; ALines: TStringList; const AReceiver,
  AResultType: string): Boolean;
var
  Line    : string ;
  Prev    : string ;
  Before  : string ;
  After   : string ;
  LhsType : string ;
  OpenCol : Integer;
  ArgIndex: Integer;
  WholeArg: Boolean;
  Ln      : Integer;
begin
  Line  := ALines[ARef.StartLine - 1];
  Before:= TrimRight(Copy(Line, 1, ARef.StartCol - 1));
  if AReceiver <> '' then
  begin
    { `Self.Name`: the expression starts at the receiver. }
    if EndsStr('.', Before) then Before:= TrimRight(Copy(Before, 1, Length(Before) - 1));
    if EndsText(AReceiver, Before) then Before:= TrimRight(Copy(Before, 1, Length(Before) - Length(AReceiver)));
  end;
  { D16c (1.8.0): the site's text is read ACROSS LINES. `RegisterGen(` on one
    line and `NextId);` on the next is one argument, and reading only the ref's
    own line saw no argument list at all, so the read BOUND as a call where the
    source passed the routine as a value. The lines above are prepended until a
    completed statement (`;` at the end) -- an argument list or an assignment
    never spans one -- within the argument scan's own budget. Line comments are
    dropped so a `(` in one cannot pose as the list's opening bracket. }
  Ln:= ARef.StartLine - 1;
  while (Ln >= 1) and (ARef.StartLine - Ln <= ARGSCAN_MAX_LINES) do
  begin
    Prev:= Trim(StripLineComment(ALines[Ln - 1]));
    if EndsStr(';', Prev) then Break;
    Before:= TrimRight(Prev + ' ' + Before);
    Dec(Ln);
  end;
  { ...and the text AFTER the name continues on the next non-empty line. }
  After:= TrimLeft(StripLineComment(Copy(Line, ARef.StartCol + Length(ARef.NameText), MaxInt)));
  Ln   := ARef.StartLine + 1;
  while (After = '') and (Ln <= ALines.Count) and (Ln - ARef.StartLine <= ARGSCAN_MAX_LINES) do
  begin
    After:= TrimLeft(StripLineComment(ALines[Ln - 1]));
    Inc(Ln);
  end;

  if EndsStr('@', Before) then
    Result:= True { the ADDRESS of the routine }
  else if EndsStr(':=', Before) and EndsStatement(After) then
  begin
    { The WHOLE right side of an assignment: a call when the target holds a
      value, the routine's address when the target is procedural. A target of
      exactly the routine's return type takes the result, even when that type
      is itself procedural. }
    LhsType:= AssignedTypeText(ARef, Before, Copy(Before, 1, Length(Before) - 2));
    Result := (LhsType <> '') and not SameText(LhsType, AResultType)
              and IsProceduralTypeText(LhsType, ARef.FileId);
  end
  else
  begin
    { A WHOLE argument: the callee's parameter type decides the same way. }
    WholeArg:= (EndsStr('(', Before) or EndsStr(',', Before))
               and (StartsStr(')', After) or StartsStr(',', After));
    Result  := WholeArg and FindArgumentListOpen(Before, OpenCol, ArgIndex)
               and CalleeTakesProcedural(ARef, Before, OpenCol, ArgIndex, AResultType);
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

function TCallResolver.BareReadSite(const ARef: TReference; out ALines: TStringList;
  out AReceiver: string): string;
begin
  Result   := '';
  AReceiver:= '';
  ALines   := LinesOf(ARef.FileId);
  if (ALines = nil) or FileIsStale(ARef.FileId) or (ARef.NameText = '')
     or (ARef.StartLine < 1) or (ARef.StartLine > ALines.Count) then
    Result:= 'unreadable'
  else
  begin
    { T-11: the parse fact first (N-05 `Self`), the line scan only without it. }
    AReceiver:= if ARef.ReceiverText <> '' then ARef.ReceiverText
                else ExtractReceiverExpr(ALines[ARef.StartLine - 1], ARef.StartCol);
    if (AReceiver <> '') and not SameText(AReceiver, 'Self') then Result:= 'qualified';
  end;
end;

function TCallResolver.ResolveParenlessRead(const ARef: TReference; out AReason: string): TCallEdge;
var
  Lines  : TStringList   ;
  Rcv    : string        ;
  Matches: TList<TSymbol>;
  S      : TSymbol       ;
  Conf   : string        ;
  Target : Int64         ;
  RetType: string        ;
  WithType: Int64          ;
  WithKind: TWithMemberKind;
  ByWith  : Boolean        ;
begin
  Result      := Default(TCallEdge);
  Result.RefId:= ARef.Id;
  { The site's own text decides three of the rules, so a line that does not
    match the index is a decline, not a guess -- the stale-file rule every other
    rung of this unit follows. }
  AReason := BareReadSite(ARef, Lines, Rcv);
  WithType:= 0;
  ByWith  := False;
  Matches := TList<TSymbol>.Create;
  try
    { 1.8.0 (D14): the with scope first, and its answer is final. A target that
      declares a ROUTINE of the name supplies the candidate set; one that
      declares a value shadows; an undecided target declines. This replaced the
      1.7.0 rule "any `with` earlier in the routine declines". }
    if (AReason = '') and (Rcv = '') then
      case WithScopeAt(ARef, ARef.StartLine, ARef.StartCol, ARef.NameText, WithType, WithKind) of
        wvUndecided: AReason:= 'with-scope';
        wvMember:
          begin
            ByWith:= True;
            if WithKind = wmRoutine then AddMethodsOnTypeChain(WithType, ARef.NameText, Matches)
            else AReason:= 'shadowed';
            { a helper-only method is a routine AddMethodsOnTypeChain cannot list }
            if (AReason = '') and (Matches.Count = 0) then AReason:= 'with-scope';
          end;
      end;
    if (AReason = '') and not ByWith then AReason:= FindParenlessCandidates(ARef, Rcv, Matches);
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
      if ByWith and (Conf <> 'certain') then AReason:= 'with-scope'
      else if ParenlessIsProcValue(ARef, Lines, Rcv, RetType) then AReason:= 'proc-value'
      else
      begin
        { ReceiverTypeSymbolId stays 0, as on the lexical and unit rungs of
          ResolveOne: a bare call has no receiver the source wrote -- except
          under a with, whose header DID write it. }
        Result.TargetSymbolId      := Target;
        Result.Confidence          := Conf;
        Result.ReceiverTypeSymbolId:= WithType;
      end;
    end;
  finally
    Matches.Free;
  end;
  TallyParenless(AReason);
end;

{ D14 + D16a (2026-09-23, resolver 1.8.0-alpha): the bare member-read pass.
  A `read` ref that names a property or field had no binder at all unless a
  receiver qualified it (the main stream's member-access rung). Two shapes are
  bound here: a member of an enclosing `with` target -- the with body is where
  0 of 283 accesses bound on ORM3 CLIENT, and where R7's enum collision lives --
  and a PROPERTY of the enclosing class (`N := Total`, D16a). The contract is on
  the declaration. }
function TCallResolver.ResolveBareMemberRead(const ARef: TReference; out AReason: string): TCallEdge;
var
  Lines  : TStringList    ;
  Rcv    : string         ;
  WType  : Int64          ;
  WKind  : TWithMemberKind;
  ClassId: Int64          ;
  M      : TSymbol        ;
  V      : TSymbol        ;
  Acc    : TSymbol        ;
  Scratch: TList<TSymbol> ;
  ByWith : Boolean        ;
begin
  Result      := Default(TCallEdge);
  Result.RefId:= ARef.Id;
  WType       := 0;
  ByWith      := False;
  M           := Default(TSymbol);
  AReason     := BareReadSite(ARef, Lines, Rcv);
  { 1. The with scope, nearer than every local. }
  if (AReason = '') and (Rcv = '') then
    case WithScopeAt(ARef, ARef.StartLine, ARef.StartCol, ARef.NameText, WType, WKind) of
      wvUndecided: AReason:= 'with-scope';
      wvMember:
        begin
          ByWith:= True;
          if WKind = wmValue then M:= LookupMemberOnType(WType, ARef.NameText)
          else AReason:= 'not-member';
          if (AReason = '') and (M.Id <= 0) then AReason:= 'with-scope';
        end;
    end;
  { 2. A local, parameter, const/var or nested routine of the name is nearer
    than the class. `Self.Name` names the member whatever is local. }
  if (AReason = '') and not ByWith and (Rcv = '') then
  begin
    Scratch:= TList<TSymbol>.Create;
    try
      if LexicalParenlessLookup(ARef.EnclosingSymbolId, ARef.NameText, Scratch, V)
         or (Scratch.Count > 0) then AReason:= 'shadowed';
    finally
      Scratch.Free;
    end;
  end;
  { 3. The enclosing class and its ancestors, NEAREST member first: a PROPERTY
    (D16a) or a FIELD (DEC-19) binds, bare or as `Self.X`; any other member
    of the name -- method, class const/var, nested type -- HIDES every
    farther one, so the read declines 'hidden' rather than binding a farther
    field. Step 2 never ran for `Self.X`: a local of the name cannot be what
    it names. }
  if (AReason = '') and not ByWith then
  begin
    EnclosingClassChainDeclares(ARef.EnclosingSymbolId, '', ClassId);
    M:= NearestClassMember(ClassId, ARef.NameText);
    if M.Id <= 0 then AReason:= 'not-found'
    else if not (M.Kind in [skProperty, skField]) then AReason:= 'hidden'
    else WType:= ClassId;
  end;
  if AReason = '' then
  begin
    Result.TargetSymbolId      := M.Id;
    Result.Confidence          := 'certain';
    Result.MemberMode          := 'read';
    Result.ReceiverTypeSymbolId:= WType;
    if M.Kind = skProperty then
    begin
      Acc:= ResolveAccessor(M, 'read');
      if Acc.Id > 0 then
      begin
        Result.AccessorSymbolId:= Acc.Id;
        Result.AccessorKind    := (if Acc.Kind = skField then 'field' else 'method');
      end;
    end;
    if ByWith then Inc(FMemberReadStats.BoundWith) else Inc(FMemberReadStats.BoundOwn);
  end
  else if AReason = 'with-scope' then Inc(FMemberReadStats.WithScope)
  else if AReason = 'not-member' then Inc(FMemberReadStats.NotMember)
  else if AReason = 'shadowed' then Inc(FMemberReadStats.Shadowed)
  else if AReason = 'not-found' then Inc(FMemberReadStats.NotFound)
  else if AReason = 'hidden' then Inc(FMemberReadStats.Hidden)
  else if AReason = 'qualified' then Inc(FMemberReadStats.Qualified)
  else Inc(FMemberReadStats.Unreadable);
end;

{ X1: the ELEMENT type text of an array type text, or '' when ATypeText is not
  one this pass reads. `array[0..1] of T` / `packed array of T` / `array of T`
  / `TArray<T>` -> `T`. A multi-dimensional `array[a, b] of T` and
  `array of const` answer '' (one subscript does not reach a T we can name). }
function ArrayElementTypeText(const ATypeText: string): string;
const
  TARRAY_OPEN = 'TArray<';
  KW_PACKED   = 'packed ';
  KW_ARRAY    = 'array';
  KW_OF       = 'of ';
var
  T    : string ;
  Depth: Integer;
  i    : Integer;
begin
  Result:= '';
  T:= Trim(ATypeText);
  if T.StartsWith(TARRAY_OPEN, True) and T.EndsWith('>') then
    Exit(Trim(Copy(T, Length(TARRAY_OPEN) + 1, Length(T) - Length(TARRAY_OPEN) - 1)));
  if T.StartsWith(KW_PACKED, True) then T:= Trim(Copy(T, Length(KW_PACKED) + 1, MaxInt));
  if not T.StartsWith(KW_ARRAY, True) then Exit;
  T:= Trim(Copy(T, Length(KW_ARRAY) + 1, MaxInt));
  if T.StartsWith('[') then
  begin
    Depth:= 0;
    for i:= 1 to Length(T) do
    begin
      if T[i] = '[' then Inc(Depth)
      else if (T[i] = ',') and (Depth = 1) then Exit // multi-dimensional
      else if T[i] = ']' then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          T:= Trim(Copy(T, i + 1, MaxInt));
          Break;
        end;
      end;
    end;
  end;
  if not T.StartsWith(KW_OF, True) then Exit;
  Result:= Trim(Copy(T, Length(KW_OF) + 1, MaxInt));
  if SameText(Result, 'const') then Result:= '';
end;

function TCallResolver.DerefPointerAlias(ATypeId: Int64): Int64;
begin
  Result:= ATypeId;
  if ATypeId <= 0 then Exit;
  var S: TSymbol:= SymbolById(ATypeId);
  var Sig: string:= Trim(S.Signature);
  if (S.Kind <> skTypeAlias) or (not Sig.StartsWith('^')) then Exit;
  var Pointee: Int64:= ResolveTypeNameToSymbol(Copy(Sig, 2, MaxInt), S.FileId);
  if Pointee > 0 then Result:= Pointee;
end;

{ X1: split a receiver at its TOP-LEVEL dots only -- `A[I.J].K` is the two
  segments `A[I.J]` and `K`. False when the brackets do not balance. }
function SplitTopLevelDots(const AText: string; out ASegs: TArray<string>): Boolean;
var
  Parts: TList<string>;
  Depth: Integer;
  Start: Integer;
  i    : Integer;
begin
  Parts:= TList<string>.Create;
  try
    Depth:= 0;
    Start:= 1;
    for i:= 1 to Length(AText) do
    begin
      if AText[i] = '[' then Inc(Depth)
      else if AText[i] = ']' then Dec(Depth)
      else if (AText[i] = '.') and (Depth = 0) then
      begin
        Parts.Add(Trim(Copy(AText, Start, i - Start)));
        Start:= i + 1;
      end;
    end;
    Parts.Add(Trim(Copy(AText, Start, MaxInt)));
    ASegs := Parts.ToArray;
    Result:= Depth = 0;
  finally
    Parts.Free;
  end;
end;

{ X1: one receiver segment -> its leading identifier and its SELECTORS, one
  char per selector: '[' for a `[..]` group, '^' for a dereference (blanks
  between them are skipped). `A[0]^` -> 'A', '[^'. False when the segment does
  not start with an identifier or holds anything else -- a call, a cast, an
  operator. }
function SplitSelectorSegment(const ASeg: string; out AName, ASelectors: string): Boolean;
var
  P, Depth: Integer;
  Sels    : TStringBuilder;
begin
  AName     := '';
  ASelectors:= '';
  P:= 1;
  while (P <= Length(ASeg)) and IsIdentPart(ASeg[P]) do Inc(P);
  Result:= (P > 1) and IsIdentStart(ASeg[1]);
  if not Result then Exit;
  AName:= Copy(ASeg, 1, P - 1);
  Sels := TStringBuilder.Create;
  try
    while Result and (P <= Length(ASeg)) do
    begin
      if ASeg[P] = '[' then
      begin
        Sels.Append('[');
        Depth:= 0;
        repeat
          if ASeg[P] = '[' then Inc(Depth)
          else if ASeg[P] = ']' then Dec(Depth);
          Inc(P);
        until (Depth = 0) or (P > Length(ASeg));
      end
      else
      begin
        if ASeg[P] = '^' then Sels.Append('^')
        else Result:= ASeg[P] = ' ';
        Inc(P);
      end;
    end;
    ASelectors:= Sels.ToString;
  finally
    Sels.Free;
  end;
end;

function TCallResolver.TypeOfSelectorChain(const ACallRef: TReference; const AReceiverExpr: string;
  out AText: TRcvTypeText): Int64;
const
  MAX_ALIAS_HOPS = 4; // `TMsgs = TArray<TMsg>` is one; a longer alias chain declines
var
  Segs    : TArray<string>;
  Name    : string ;
  Sels    : string ;
  Ok      : Boolean;
  SegIx   : Integer;
  TypeText: string ; // the current value's declared type TEXT, or '' when TypeId holds it
  TypeId  : Int64  ;
  PrevText: string ; // item 4: the type text before the step that failed

  { Step the current type through one selector: '[' (element) or '^' (pointee).
    A type text this cannot read directly is resolved as a NAMED type and, when
    that is an alias, read again through its signature. }
  function ApplySelector(ASel: Char): Boolean;
  begin
    Result:= False;
    for var Hop:= 0 to MAX_ALIAS_HOPS do
    begin
      if TypeText = '' then
      begin
        if TypeId <= 0 then Exit;
        if SymbolById(TypeId).Kind <> skTypeAlias then Exit; // a class / record: no default property model
        var Alias: TSymbol:= SymbolById(TypeId);
        TypeText:= Trim(Alias.Signature);
        TypeId  := 0;
      end;
      var Next: string:= if ASel = '^' then (if TypeText.StartsWith('^') then Trim(Copy(TypeText, 2, MaxInt)) else '')
                         else ArrayElementTypeText(TypeText);
      if Next <> '' then
      begin
        TypeText:= Next;
        Exit(True);
      end;
      TypeId  := ResolveTypeNameToSymbol(TypeText, ACallRef.FileId);
      TypeText:= '';
    end;
  end;

  { The current value's type as a symbol id, implicitly dereferenced. }
  function CurrentTypeId: Int64;
  begin
    Result:= TypeId;
    if TypeText <> '' then
      Result:= if TypeText.StartsWith('^') or (ArrayElementTypeText(TypeText) <> '') then 0 // no members
               else ResolveTypeNameToSymbol(TypeText, ACallRef.FileId);
    Result:= DerefPointerAlias(Result);
  end;

  { Type the HEAD identifier as a value, in the order TypeReceiverCore uses. }
  function TypeHead(const AName: string): Boolean;
  var
    Declared, AnonDeclined: Boolean;
  begin
    TypeText:= '';
    TypeId  := 0;
    var Encl: TSymbol:= SymbolById(ACallRef.EnclosingSymbolId);
    var Decl: TSymbol:= LocalInScopeAt(ACallRef, AName, Declared);
    if (Decl.Id <= 0) and (not Declared) and (Encl.ParentId > 0) and not SameText(AName, 'Result') then
      Decl:= FindChildOfKind(Encl.ParentId, AName, [skField, skProperty]);
    if Decl.Id > 0 then
      TypeText:= Trim(Decl.Signature)
    else if Declared then
      Exit(False) // a local of that name exists but none covers the site
    else if SameText(AName, 'Result') and (Encl.Kind in [skFunction, skMethod]) then
    begin
      TypeText:= ResultTypeAt(ACallRef, AnonDeclined);
      if AnonDeclined then TypeText:= '';
    end
    else
    begin
      var OrdText: string;
      TypeId:= TypeOfOrdinaryName(ACallRef, AName, OrdText);
      { Item 4 (f): a unit-level (or inherited) value of an ARRAY type answers
        no id -- its text is `array [0 .. 64] of TfrmGageport2` -- so read the
        TEXT and let the selector take the element type. Only when the id path
        had nothing, so no edge that bound before can move. }
      if (TypeId = 0) and (ArrayElementTypeText(OrdText) <> '') then TypeText:= OrdText;
    end;
    Result:= (TypeText <> '') or (TypeId > 0);
  end;

  { Type member AName of the current type. }
  function TypeMember(const AName: string): Boolean;
  begin
    var Owner: Int64:= CurrentTypeId;
    var Member: TSymbol:= if Owner > 0 then LookupMemberOnType(Owner, AName) else Default(TSymbol);
    TypeText:= Trim(Member.Signature);
    TypeId  := 0;
    Result  := (Member.Id > 0) and (TypeText <> '');
  end;

  { Item 4: the text a chain stopped at, when every segment from the failing
    member on is a plain name the oracle can step: `T.Panels` yes, `T.Items[0]` no. }
  procedure StopAt(AFailIx: Integer);
  var
    Names: TArray<string>;
  begin
    Names:= [];
    for var K:= AFailIx to High(Segs) do
    begin
      if not SplitSelectorSegment(Segs[K], Name, Sels) or (Sels <> '') then Exit;
      Names:= Names + [Name];
    end;
    AText.Text   := NormalizeTypeLeaf(PrevText);
    AText.Pending:= if AText.Text = '' then '' else string.Join('.', Names);
  end;

begin
  AText   := Default(TRcvTypeText);
  TypeText:= '';
  TypeId  := 0;
  Ok      := SplitTopLevelDots(AReceiverExpr, Segs);
  SegIx   := 0;
  while Ok and (SegIx <= High(Segs)) do
  begin
    PrevText:= if TypeText <> '' then TypeText else if TypeId > 0 then SymbolById(TypeId).Name else '';
    Ok:= SplitSelectorSegment(Segs[SegIx], Name, Sels)
         and (if SegIx = 0 then TypeHead(Name) else TypeMember(Name));
    if (not Ok) and (SegIx > 0) and (PrevText <> '') then StopAt(SegIx);
    for var Sel: Char in Sels do Ok:= Ok and ApplySelector(Sel);
    Inc(SegIx);
  end;
  Result:= if Ok then CurrentTypeId else 0;
  if Ok then
    AText.Text:= if TypeText <> '' then NormalizeTypeLeaf(TypeText)
                 else if TypeId > 0 then SymbolById(TypeId).Name else '';
end;

{ T-11: split a receiver at its TOP-LEVEL dots -- outside ( ) and [ ] groups
  and '...' literals, so `O.Mk('a.b').Leaf` is `O`, `Mk('a.b')`, `Leaf`.
  AHasParen: some segment holds a '(' outside any group (a call, a cast, a
  parenthesised head). False when the groups or literals do not balance. }
function SplitChainSegments(const AText: string; out ASegs: TArray<string>; out AHasParen: Boolean): Boolean;
var
  Parts: TList<string>;
  Depth: Integer;
  Start: Integer;
  InLit: Boolean;
  i    : Integer;
begin
  AHasParen:= False;
  Parts:= TList<string>.Create;
  try
    Depth:= 0;
    Start:= 1;
    InLit:= False;
    for i:= 1 to Length(AText) do
    begin
      if AText[i] = '''' then InLit:= not InLit
      else if InLit then Continue
      else if CharInSet(AText[i], ['(', '[']) then
      begin
        if (AText[i] = '(') and (Depth = 0) then AHasParen:= True;
        Inc(Depth);
      end
      else if CharInSet(AText[i], [')', ']']) then Dec(Depth)
      else if (AText[i] = '.') and (Depth = 0) then
      begin
        Parts.Add(Trim(Copy(AText, Start, i - Start)));
        Start:= i + 1;
      end;
    end;
    Parts.Add(Trim(Copy(AText, Start, MaxInt)));
    ASegs := Parts.ToArray;
    Result:= (Depth = 0) and not InLit;
  finally
    Parts.Free;
  end;
end;

{ T-11: True when AText is exactly ONE balanced `( .. )` group (literals
  skipped) -- the argument list of a call segment. }
function IsOneParenGroup(const AText: string): Boolean;
var
  Depth: Integer;
  InLit: Boolean;
  i    : Integer;
begin
  Result:= (AText <> '') and (AText[1] = '(');
  Depth := 0;
  InLit := False;
  i     := 1;
  while Result and (i <= Length(AText)) do
  begin
    if AText[i] = '''' then InLit:= not InLit
    else if not InLit then
    begin
      if AText[i] = '(' then Inc(Depth)
      else if AText[i] = ')' then
      begin
        Dec(Depth);
        if Depth = 0 then Exit(i = Length(AText));
      end;
    end;
    Inc(i);
  end;
  Result:= False;
end;

function TCallResolver.TypeOfCallChain(const ACallRef: TReference; const AReceiverExpr: string;
  out AHandled: Boolean; out AText: TRcvTypeText): Int64;
var
  Segs     : TArray<string>;
  HasParen : Boolean;
  HasEmpty : Boolean;
  OwnerType: Int64  ;
  OwnerText: TRcvTypeText;
  StepName : string ;
  Found    : Boolean;

  { The type the LAST segment ASeg yields as a member of AOwner. Item 4: AStepText
    is the member's declared type text / the method's return type text; AFound
    False when the owner's chain has no such member (an inherited library one). }
  function ChainStep(AOwner: Int64; const ASeg: string; out AStepText: string): Int64;
  var
    P   : Integer;
    Conf: string ;
  begin
    Result   := 0;
    AStepText:= '';
    Found    := False;
    P:= 1;
    while (P <= Length(ASeg)) and IsIdentPart(ASeg[P]) do Inc(P);
    if (P = 1) or not IsIdentStart(ASeg[1]) then Exit;
    var Name: string:= Copy(ASeg, 1, P - 1);
    var Args: string:= Trim(Copy(ASeg, P, MaxInt));
    if Args = '' then
    begin
      var Member: TSymbol:= LookupMemberOnType(AOwner, Name);
      if Member.Id > 0 then
      begin
        Found    := True;
        AStepText:= NormalizeTypeLeaf(Member.Signature);
        Exit(DerefPointerAlias(ResolveTypeNameToSymbol(Member.Signature, Member.FileId)));
      end;
    end
    else if not IsOneParenGroup(Args) then
    begin
      Found:= True; // `Items[0]`, `F(x)[1]`: a subscript step is not modelled here
      Exit;
    end;
    { A method -- `Mk('a')`, or the parenless `Leaf` -- types to its declared
      return type. Exactly one candidate on the type's chain ('certain'): an
      overload set or an override pair may disagree on the return type. }
    var Target: Int64:= LookupMethodOnType(AOwner, Name, 0, False, Conf);
    Found:= Target > 0;
    if (Target <= 0) or (Conf <> 'certain') then Exit;
    var Method: TSymbol:= SymbolById(Target);
    var RetType: string:= SignatureReturnType(Method.Signature);
    AStepText:= NormalizeTypeLeaf(RetType);
    if RetType <> '' then
      Result:= DerefPointerAlias(ResolveTypeNameToSymbol(RetType, Method.FileId));
  end;

  { Item 4: the last segment's plain name -- `Mk` of `Mk('a')` -- or '' for a
    subscript / cast segment the oracle cannot step. }
  function SegName(const ASeg: string): string;
  var
    P: Integer;
  begin
    P:= 1;
    while (P <= Length(ASeg)) and IsIdentPart(ASeg[P]) do Inc(P);
    Result:= Copy(ASeg, 1, P - 1);
    if (Result = '') or not IsIdentStart(Result[1]) then Exit('');
    var Args: string:= Trim(Copy(ASeg, P, MaxInt));
    if (Args <> '') and not IsOneParenGroup(Args) then Result:= '';
  end;

  function Join(const A, B: string): string;
  begin
    Result:= if A = '' then B else A + '.' + B;
  end;

begin
  Result  := 0;
  AText   := Default(TRcvTypeText);
  AHandled:= SplitChainSegments(AReceiverExpr, Segs, HasParen) and HasParen and (Length(Segs) >= 2);
  { An empty segment is a line-scan fragment (`.Mk(1).L`): never typed, and
    above all never from the enclosing class, which is what '' would mean. }
  HasEmpty:= False;
  for var Seg: string in Segs do HasEmpty:= HasEmpty or (Seg = '');
  if (not AHandled) or HasEmpty then Exit;
  OwnerType:= TypeReceiver(ACallRef, string.Join('.', Segs, 0, High(Segs)), OwnerText); // shorter text -> the recursion ends
  StepName := SegName(Segs[High(Segs)]);
  if OwnerType > 0 then
  begin
    Result:= ChainStep(OwnerType, Segs[High(Segs)], AText.Text);
    { Not on the project chain: the owner's text with this segment pending,
      for the oracle to step through the owner's library ancestors. }
    if (not Found) and (StepName <> '') then
    begin
      AText.Text   := if OwnerText.Text <> '' then OwnerText.Text else SymbolById(OwnerType).Name;
      AText.Pending:= Join(OwnerText.Pending, StepName);
    end;
  end
  else if StepName <> '' then
  begin
    if OwnerText.Text <> '' then
    begin
      AText.Text   := OwnerText.Text;
      AText.Pending:= Join(OwnerText.Pending, StepName);
    end
    else if OwnerText.Head <> '' then
      AText.Head:= Join(OwnerText.Head, StepName);
  end;
end;

function TCallResolver.TypeReceiver(const ACallRef: TReference; const AReceiverExpr: string): Int64;
var
  Ignored: TRcvTypeText;
begin
  Result:= DerefPointerAlias(TypeReceiverCore(ACallRef, AReceiverExpr, Ignored));
end;

function TCallResolver.TypeReceiver(const ACallRef: TReference; const AReceiverExpr: string;
  out AText: TRcvTypeText): Int64;
begin
  Result:= DerefPointerAlias(TypeReceiverCore(ACallRef, AReceiverExpr, AText));
end;

function TCallResolver.TypeReceiverCore(const ACallRef: TReference; const AReceiverExpr: string;  // dl:ok too-many-exit-points@72ca, cyclomatic-complexity@3450 -- REVIEWED 2026-10-28 (item 4, lane R4R: the out AText adds no rung and changes no answer -- each existing rung writes the type text it already read before resolving it, and the added branches are that bookkeeping in kinds 6 and 10; the rung order is still the contract. Earlier: 2026-10-26 whole-branch review extract-136: T-11 added kind 12, the call-chain rung, two more exits and complexity 32 over the 30 bound; first reviewed 2026-10-25 at X1/X2): the exits are the receiver-kind LADDER -- each rung (Self, cast, selector chain, unit-qualified type, local/field/Result, function result, ordinary name, ...) answers and leaves; the body is the old TypeReceiver unchanged, renamed so TypeReceiver can apply the implicit dereference once. One exit would thread a found flag through a dozen rungs whose order IS the contract.
  out AText: TRcvTypeText): Int64;
var
  Encl    : TSymbol;
  ClassId : Int64  ;
  Member  : TSymbol;
  CastType: string ;
  RetType : string ;
begin
  Result:= 0;
  AText := Default(TRcvTypeText); { item 4: '' for bare / Self / with-typed / untyped }
  if ACallRef.EnclosingSymbolId <= 0 then Exit; // no enclosing routine -> give up
  Encl:= SymbolById(ACallRef.EnclosingSymbolId);

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
  //
  // --- Kind 0 (1.8.0, D14): a receiver whose LEADING identifier a `with` target
  //     supplies -- `with AObj do Inner.Ping` -- is typed through that target,
  //     and an undecided with scope leaves it untyped. Ahead of every identifier
  //     rung because a with member is nearer than any local, field or type. It
  //     never handles '' or Self, so kind 1 keeps its answer.
  var WithHandled: Boolean;
  Result:= TypeReceiverThroughWith(ACallRef, AReceiverExpr, WithHandled);
  if WithHandled or (AReceiverExpr = '') or SameText(AReceiverExpr, 'Self') then
  begin
    if not WithHandled then Result:= Encl.ParentId;
    Exit;
  end;

  ClassId:= Encl.ParentId; // the enclosing routine's owning class (for kinds 2/3)

  // --- Kind 6: cast '(X as TBar).M' / 'TBar(X).M' -> the cast target type.
  //     Kind 11 (X2, resolver 1.14.0-alpha): 'F(...)' / 'F()' whose F is not a
  //     type is a CALL -- typed from F's declared return type.
  var ChainHandled: Boolean;
  if TryParseCastTarget(AReceiverExpr, CastType) then
  begin
    Result:= ResolveTypeNameToSymbol(CastType, ACallRef.FileId);
    AText.Text:= if Result > 0 then NormalizeTypeLeaf(CastType) else '';
    if (Result = 0) and AReceiverExpr.StartsWith(CastType + '(', True) and IsIdentChain([CastType]) then
      Result:= TypeOfFunctionResult(ACallRef, CastType, AText.Text);
    { T-11: `O.Mk('a')` also reads as a cast to `O.Mk`; when that names no type
      and no function, kind 12 below types it as a call on O. }
    if Result > 0 then Exit;
    var FnText: string:= AText.Text;
    Result:= TypeOfCallChain(ACallRef, AReceiverExpr, ChainHandled, AText);
    { Item 4: a cast to a type this index does not hold (`TFDQuery(DS).Open`,
      `(S as TStringList).Add`) still names that type; a function of the name
      wrote its return type above. }
    if not ChainHandled then
      AText.Text:= if FnText <> '' then FnText else NormalizeTypeLeaf(CastType);
    Exit;
  end;

  // --- Kind 12 (T-11, resolver 1.15.0): a chain with a CALL or parenthesised
  //     segment -- `O.Mk('a').Mk('b').Leaf`, `(O as TInner).Leaf`,
  //     `SB.Append(x)`. The receiver text is a parse fact now, so a fluent
  //     chain continued over several lines arrives whole; no rung below typed a
  //     `Name(...)` segment in chain position. The prefix goes through this
  //     ladder again, the last segment is a member / method lookup on its type;
  //     any untyped step answers 0. Pinned by
  //     tests\callresolve\run_receiver_cst_capture.ps1.
  Result:= TypeOfCallChain(ACallRef, AReceiverExpr, ChainHandled, AText);
  if ChainHandled then Exit;

  // --- Kind 11 (X1, 2026-10-25): a receiver with SELECTORS -- an array element
  //     or a pointer dereference: `A[0].K`, `R.Arr[1].K`, `pM[X].Sev`, `P^.K`.
  //     Before this rung any '[' fell through to the "real expression" floor
  //     below and the member stayed unbound, and `P^` never got here at all
  //     (ExtractReceiverExpr stopped at '^'). A chain this cannot read answers
  //     0 -- the same floor as before. Pinned by
  //     tests\callresolve\run_local_read_chain_bind.ps1.
  if (Pos('[', AReceiverExpr) > 0) or (Pos('^', AReceiverExpr) > 0) then
    Exit(TypeOfSelectorChain(ACallRef, AReceiverExpr, AText));

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
  if (Pos('.', AReceiverExpr) > 0) and IsIdentChain(AReceiverExpr.Split(['.'])) then
  begin
    var Segs: TArray<string>:= AReceiverExpr.Split(['.']);
    // --- Kind 10 (2026-10-23): a CHAINED VALUE receiver, 'R.Inner' in
    //     `R.Inner.K := 1`. The head is typed by the single-identifier rungs
    //     (this function, one segment), then each following segment as a field /
    //     property of the previous segment's type (ancestors included). A segment
    //     that cannot be typed ends the walk with NO answer from this rung, and
    //     the unit-qualified rung below runs exactly as it did before -- so
    //     'Unit.TType' (an untypable head) is unchanged. Pinned by
    //     tests\callresolve\run_chained_receiver_bind.ps1.
    { Item 4: CurText follows the walk -- the head's text, then each stepped
      member's declared type; StopIx is the first segment NOT stepped. }
    var HeadText: TRcvTypeText;
    var ChainType: Int64:= TypeReceiver(ACallRef, Segs[0], HeadText);
    var CurText: string:= HeadText.Text;
    var StopIx: Integer:= 1;
    var SegIx: Integer:= 1;
    while (ChainType > 0) and (SegIx <= High(Segs)) do
    begin
      var SegMember: TSymbol:= LookupMemberOnType(ChainType, Segs[SegIx]);
      if CurText = '' then CurText:= SymbolById(ChainType).Name;
      if SegMember.Id > 0 then
      begin
        CurText:= NormalizeTypeLeaf(SegMember.Signature);
        StopIx := SegIx + 1;
      end;
      ChainType:= if SegMember.Id > 0 then DerefPointerAlias(ResolveTypeNameToSymbol(SegMember.Signature, ACallRef.FileId)) else 0;
      Inc(SegIx);
    end;
    if ChainType > 0 then
    begin
      AText.Text:= if CurText <> '' then CurText else SymbolById(ChainType).Name;
      Exit(ChainType);
    end;
    Result:= ResolveTypeNameToSymbol(Segs[High(Segs)], ACallRef.FileId);
    if Result > 0 then AText.Text:= NormalizeTypeLeaf(Segs[High(Segs)])
    else if CurText <> '' then
    begin
      AText.Text   := CurText;
      AText.Pending:= if StopIx <= High(Segs) then string.Join('.', Segs, StopIx, Length(Segs) - StopIx) else '';
    end
    else if HeadText.Head <> '' then
      AText.Head:= AReceiverExpr;
    Exit;
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
  // qualified name. Review 2026-10-23 (W5-res2): the receiver is typed from the
  // nearest declaration at or before the site whose block covers it (the value
  // read/write rule), never from the first child of that name; when none covers
  // the site it declines (the honest untyped floor). The local still SHADOWS any
  // same-named field or type, so a declined local ends the search here.
  var Declared: Boolean;
  Member:= LocalInScopeAt(ACallRef, AReceiverExpr, Declared);
  if Member.Id > 0 then
  begin
    AText.Text:= NormalizeTypeLeaf(Member.Signature);
    Exit(ResolveTypeNameToSymbol(Member.Signature, ACallRef.FileId));
  end;
  if Declared then
    Exit; // a local/param of that name exists but none covers the site -> 0

  // --- Kind 9 (N-07, 2026-10-23): the implicit `Result` of the enclosing
  //     FUNCTION -- `Result:= TJob.Create; Result.Streaming:= False;`. Typed
  //     from the routine's declared return type. No symbol row exists for
  //     Result, so a local or parameter named Result (only legal outside a
  //     function) was already answered above; a routine with no return type
  //     falls through to the field rung.
  if SameText(AReceiverExpr, 'Result') and (Encl.Kind in [skFunction, skMethod]) then
  begin
    { Review 2026-10-23: inside an anonymous method Result is ITS result --
      typed only when its return type is the routine's (W5-res2). }
    var AnonDeclined: Boolean;
    RetType:= ResultTypeAt(ACallRef, AnonDeclined);
    if AnonDeclined then Exit;
    AText.Text:= NormalizeTypeLeaf(RetType);
    if RetType <> '' then Exit(ResolveTypeNameToSymbol(RetType, ACallRef.FileId));
  end;

  // --- Kind 2: FIELD 'FBar.M' / Kind 3: PROPERTY 'Prop.M' -> member's type.
  //     Members are children of the enclosing class.
  if ClassId > 0 then
  begin
    Member:= FindChildOfKind(ClassId, AReceiverExpr, [skField, skProperty]);
    if Member.Id > 0 then
    begin
      AText.Text:= NormalizeTypeLeaf(Member.Signature);
      Exit(ResolveTypeNameToSymbol(Member.Signature, ACallRef.FileId));
    end;
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
  //
  // --- Kind 8 (resolver 1.11.0-alpha, RB-1): a VALUE the rungs above do not
  //     see -- a field or property of an ANCESTOR class, or a UNIT-LEVEL var
  //     (the own unit, or a used unit's interface): `GDatasetsDef.GetTable(...)`
  //     on ORM3 SERVER. Those calls were unbound with no edge, and the charts
  //     traced them by name. TypeOfOrdinaryName is the scope walk the `with`
  //     scope already types through, in Delphi's order: the class chain, then
  //     exactly ONE visible unit-level var (two -> nothing, uses-clause order is
  //     not modelled), and only then the name as a TYPE -- so the kind-7 type
  //     rung is still the last word when no value of the name is in scope. Pinned by
  //     tests\callresolve\run_unit_var_receiver_bind.ps1.
  var OrdText: string;
  Result:= TypeOfOrdinaryName(ACallRef, AReceiverExpr, OrdText);
  AText.Text:= NormalizeTypeLeaf(OrdText);
  if Result > 0 then Exit;

  // --- Kind 11 (X2, resolver 1.14.0-alpha): a PARENLESS FUNCTION CALL as the
  //     receiver -- `GetCopy.TransferFile(...)`, `MakeCopy.Run`. Last: every
  //     value and type rung above had its say, so a value or type of the name
  //     already answered. Known gap: a unit-level var of the name found by
  //     TypeOfOrdinaryName wins over a nearer class METHOD of the name.
  var FnText: string;
  Result:= TypeOfFunctionResult(ACallRef, AReceiverExpr, FnText);
  if (Result > 0) or ((AText.Text = '') and (FnText <> '')) then AText.Text:= FnText;
  if Result > 0 then Exit;

  // Unresolved receiver identifier (unknown local/param/field, and not a type we
  // can name) -> Result stays 0 (leave unresolved). Item 4: when nothing in this
  // index even names its type, the identifier goes to the library oracle as a
  // HEAD -- a library type, global, or inherited member.
  if AText.Text = '' then AText.Head:= AReceiverExpr;
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
  for A in AncestorsOf(ATypeSymbolId) do
  begin
    if not A.Resolved or (A.SymbolId <= 0) then Continue;
    Result:= FindChildOfKind(A.SymbolId, AMemberName, MEMBER_KINDS);
    if Result.Id > 0 then Exit;
  end;
end;

function TCallResolver.NearestClassMember(AClassId: Int64; const AName: string): TSymbol;
var
  AnyMember: TSymbolKindSet       ;
  Cur      : Int64                ;
  Depth    : Integer              ;
  Anc      : TArray<TTypeAncestor>;
begin
  { Typed constants cannot be combined in a const expression, hence a local. }
  AnyMember:= METHOD_KINDS + TYPE_KINDS + [skProperty, skField, skVarDecl, skConstDecl, skTypeAlias, skEnum];
  Result:= Default(TSymbol);
  Cur   := AClassId;
  Depth := 0;
  while (Cur > 0) and (Depth < MAX_LEXICAL_DEPTH) do
  begin
    Inc(Depth);
    Result:= FindChildOfKind(Cur, AName, AnyMember);
    if Result.Id > 0 then Exit;
    { AncestorsOf is the transitive BFS, so its FIRST row is Cur's own
      ordinal-0 heritage edge -- the class parent, when there is one. }
    Anc:= AncestorsOf(Cur);
    Cur:= 0;
    if (Length(Anc) > 0) and (Anc[0].Ordinal = 0) and Anc[0].Resolved and (Anc[0].SymbolId > 0)
       and (SymbolById(Anc[0].SymbolId).Kind <> skInterface) then Cur:= Anc[0].SymbolId;
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
    for A in AncestorsOf(AProp.ParentId) do
    begin
      if not A.Resolved or (A.SymbolId <= 0) then Continue;
      Result:= PickAccessor(A.SymbolId, Ident, WantArity, ACCESSOR_KINDS, Found);
      if Found then Break;
    end;
end;

function TCallResolver.BareCallInNearScopes(const ACallRef: TReference; AArgCount: Integer;
  AArgsKnown: Boolean; var AEdge: TCallEdge): Boolean;
var
  WType : Int64          ;
  WKind : TWithMemberKind;
  Target: Int64          ;
  Conf  : string         ;
begin
  Result:= True;
  case WithScopeAt(ACallRef, ACallRef.StartLine, ACallRef.StartCol, ACallRef.NameText, WType, WKind) of
    wvNone: Result:= False;
    wvMember:
      begin
        Target:= 0;
        if WKind = wmRoutine then
          Target:= LookupMethodOnType(WType, ACallRef.NameText, AArgCount, AArgsKnown, Conf);
        { Certain only: an overload tie or a non-routine member writes nothing. }
        if (Target > 0) and (Conf = 'certain') then
        begin
          AEdge.TargetSymbolId      := Target;
          AEdge.Confidence          := Conf;
          AEdge.ReceiverTypeSymbolId:= WType; { the target the with header names }
          Inc(FWith.Stats.CallBound);
        end
        else
          Inc(FWith.Stats.CallDeclined);
      end;
  else
    Inc(FWith.Stats.CallDeclined); { undecided: the target may own the name }
  end;
  if Result then Exit;
  { Then Delphi's lexical chain. ReceiverTypeSymbolId stays 0: a lexical hit has
    no receiver TYPE. The field means "the type the receiver was typed to", and
    inventing the enclosing routine's class here would be a false claim about a
    call that has no receiver at all. }
  Target:= LookupInLexicalScopes(ACallRef.EnclosingSymbolId, ACallRef.NameText, Conf);
  Result:= Target > 0;
  if Result then
  begin
    AEdge.TargetSymbolId:= Target;
    AEdge.Confidence    := Conf;
  end;
end;

{ 2026-09-23 (resolver 1.8.0-alpha) -- ENG-16's rung 4b and D13's write pass.

  Both follow the posture of the enum and parenless passes above: an answer the
  compiler would give, or NOTHING, with every refusal counted by reason. }

function TCallResolver.LookupUnitQualifiedRoutine(const ACallRef: TReference;
  const AReceiver: string; AReceiverTypeId: Int64; AArgCount: Integer; AArgsKnown: Boolean;
  out AConfidence: string): Int64;
var
  Cands   : TList<TSymbol>;
  Matches : TList<TSymbol>;
  S       : TSymbol       ;
  UnitFile: Int64         ;
begin
  Result     := 0;
  AConfidence:= '';
  { A receiver that TYPED is a value; cheapest test next: no free routine of
    the name anywhere, no answer. }
  if (AReceiverTypeId <> 0) or (AReceiver = '')
     or not FNameToRoutines.TryGetValue(LowerCase(ACallRef.NameText), Cands) then Exit;
  UnitFile:= UnshadowedUnitFile(ACallRef, AReceiver);
  if UnitFile <= 0 then Exit;
  Matches:= TList<TSymbol>.Create;
  try
    for S in Cands do
      if (S.FileId = UnitFile)
         and (SameText(S.Section, 'interface') or (UnitFile = ACallRef.FileId)) then Matches.Add(S);
    Result:= PickFromMatches(Matches, AArgCount, AArgsKnown, AConfidence);
  finally
    Matches.Free;
  end;
end;

function TCallResolver.UnshadowedUnitFile(const ARef: TReference; const AReceiver: string): Int64;
var
  First   : string         ;
  Key     : string         ;
  ClassId : Int64          ;
  WithType: Int64          ;
  WithKind: TWithMemberKind;
begin
  Result:= 0;
  { A nearer VALUE spelled like the unit's first segment is what the compiler
    reads -- a local of an unindexed type reaches here with TypeId = 0 all the
    same, and binding its member to the unit's declaration would be a wrong fact. }
  First:= AReceiver;
  if Pos('.', First) > 0 then First:= Copy(First, 1, Pos('.', First) - 1);
  if LexicalScopeDeclaresValue(ARef.EnclosingSymbolId, First)
     or EnclosingClassChainDeclares(ARef.EnclosingSymbolId, First, ClassId) then Exit;
  { RB-4 (resolver 1.11.0-alpha): a UNIT-LEVEL var/const spelled like the unit
    is nearer than the unit name too -- the own unit's, or one a used unit's
    interface exports. Its type may be one the index cannot see, which answers
    TypeId 0 exactly as a unit receiver does. Values only: a type or enum value
    of the name is not what `uLib.Go` reads. Pinned by N3 in
    tests\callresolve\run_unit_var_receiver_bind.ps1. }
  if UnitLevelValueVisible(ARef.FileId, LowerCase(First)) then Exit;
  { A with target is nearer still (D14). TypeReceiver answers 0 for a receiver
    the with scope left UNDECIDED, which is exactly the TypeId the unit rungs
    take, so without this test an untypable target's member spelled like a unit
    would be bound to that unit's declaration. }
  if WithScopeAt(ARef, ARef.StartLine, ARef.StartCol, First, WithType, WithKind) <> wvNone then Exit;
  Key:= LowerCase(AReceiver);
  if not FUnitFileOf.TryGetValue(Key, Result) then
  begin
    Result:= UnitNameToFileId(AReceiver);
    FUnitFileOf.Add(Key, Result);
  end;
end;

function TCallResolver.LookupUnitQualifiedValue(const ARef: TReference; const AReceiver: string;
  AReceiverTypeId: Int64): Int64;
var
  Cands   : TList<TSymbol>;
  S       : TSymbol       ;
  UnitFile: Int64         ;
  Visible : Integer       ;
  Found   : Int64         ;
begin
  Result:= 0;
  { Same gate order as rung 4b: a receiver that TYPED is a value, then the
    cheapest test -- no unit-level value of the name anywhere, no answer. }
  if (AReceiverTypeId <> 0) or (AReceiver = '')
     or not FNameToUnitValues.TryGetValue(LowerCase(ARef.NameText), Cands) then Exit;
  UnitFile:= UnshadowedUnitFile(ARef, AReceiver);
  if UnitFile <= 0 then Exit;
  Visible:= 0;
  Found  := 0;
  for S in Cands do
    if (S.FileId = UnitFile)
       and (SameText(S.Section, 'interface') or (UnitFile = ARef.FileId)) then
    begin
      Inc(Visible);
      Found:= S.Id;
    end;
  { Two declarations of one name in one unit is conditional compilation the
    index parsed both branches of: absence beats a guess. }
  if Visible = 1 then Result:= Found;
end;

function TCallResolver.QualifiedValueTarget(const ACallRef: TReference; const AReceiver: string;
  AReceiverTypeId: Int64): Int64;
var
  Enums   : TList<TEnumValueDecl>;
  C       : TEnumValueDecl       ;
  InUnit  : TArray<TEnumValueDecl>;
  UnitFile: Int64                ;
begin
  Result:= 0;
  { 3c. Gated on the name map first, so the common case costs one dictionary miss. }
  if FNameToEnumValues.TryGetValue(LowerCase(ACallRef.NameText), Enums) then
  begin
    if (AReceiverTypeId > 0) and (SymbolById(AReceiverTypeId).Kind = skEnum) then
      Result:= FindChildOfKind(AReceiverTypeId, ACallRef.NameText, [skEnumValue], False).Id
    else if AReceiverTypeId = 0 then
    begin
      { A UNIT-name receiver: `Pipes.Protocol.cmdDelta`. Narrow the candidates to
        that unit's file -- its interface section, or either section when the
        unit IS this file -- and bind only when exactly one survives. The
        source qualified the NAME, so R3 does not apply to it -- but the
        RECEIVER can still be shadowed: a local of an unindexed type spelled
        like the unit also answers TypeId = 0, and the compiler reads the local
        (ruling R14, 1.9.0-alpha). Hence rung 3d's gate, not a bare unit lookup. }
      UnitFile:= UnshadowedUnitFile(ACallRef, AReceiver);
      if UnitFile > 0 then
      begin
        InUnit:= nil;
        for C in Enums do
          if (C.FileId = UnitFile) and (C.OwnerRoutineId = 0)   { W5-ext: a routine-local value has no Unit.value form }
             and not C.Scoped                                   { E14: nor has a scoped one -- only Unit.TEnum.Value }
             and (SameText(C.Section, 'interface') or (UnitFile = ACallRef.FileId)) then
            InUnit:= InUnit + [C];
        InUnit:= CollapseIdenticalEnumCopies(InUnit, ACallRef.FileId);
        if Length(InUnit) = 1 then Result:= InUnit[0].Id;
      end
      { The receiver DOES name one unit, so only the gate declined it: count it,
        because a decline writes nothing and this is its only trace. }
      else if UnitNameToFileId(AReceiver) > 0 then Inc(FEnumUnitGateDeclined);
    end;
    if Result > 0 then
    begin
      Inc(FEnumStats.Bound);
      Exit;
    end;
  end;
  { 3d. Not an enum value of that receiver: a unit-level var or const. }
  Result:= LookupUnitQualifiedValue(ACallRef, AReceiver, AReceiverTypeId);
  if Result > 0 then Inc(FUnitValueBound);
end;

function TCallResolver.WriteScopeOf(AEnclosingSymbolId: Int64): TWriteScope;
var
  S    : TSymbol      ;
  A    : TTypeAncestor;
  Depth: Integer      ;
begin
  if FWriteScopes.TryGetValue(AEnclosingSymbolId, Result) then Exit;
  Result:= Default(TWriteScope);
  if AEnclosingSymbolId > 0 then
  begin
    S:= FStore.GetSymbolById(AEnclosingSymbolId);
    { The routine and the routines around it -- the levels LexicalParenlessLookup
      climbs, and the function names whose RESULT a write may assign. The walk ends at
      the first non-routine parent, which is the owning type when there is one
      (EnclosingClassChainDeclares' outermost-routine rule). }
    Depth:= 0;
    while (S.Id > 0) and (S.Kind in METHOD_KINDS) and (Depth < MAX_LEXICAL_DEPTH) do
    begin
      Inc(Depth);
      Result.Chain:= Result.Chain + [S.Id];
      if S.Kind in [skFunction, skMethod] then Result.FnNames:= Result.FnNames + '|' + LowerCase(S.Name);
      if S.ParentId <= 0 then S:= Default(TSymbol)
      else S:= FStore.GetSymbolById(S.ParentId);
    end;
    Result.FnNames:= Result.FnNames + '|';
    if (S.Id > 0) and (S.Kind in TYPE_KINDS) then
    begin
      Result.ClassChain:= [S.Id];
      for A in FStore.GetTransitiveAncestors(S.Id) do
        if A.Resolved and (A.SymbolId > 0) then Result.ClassChain:= Result.ClassChain + [A.SymbolId];
    end;
  end;
  FWriteScopes.Add(AEnclosingSymbolId, Result);
end;

{ Inserts AValue into AValues kept NEAREST-LAST-DECLARED first: before the first
  declaration that starts earlier. }
procedure InsertNearestFirst(var AValues: TArray<TSymbol>; const AValue: TSymbol);
var
  K: Integer;
begin
  K:= 0;
  while (K < Length(AValues)) and ((AValues[K].StartLine > AValue.StartLine)
         or ((AValues[K].StartLine = AValue.StartLine) and (AValues[K].StartCol > AValue.StartCol))) do Inc(K);
  Insert(AValue, AValues, K);
end;

function TCallResolver.ScopeWriteTarget(const AScope: TWriteScope; const AName: string;
  AFileId: Int64; ALine, ACol: Integer; out AReason: string): Int64;
var
  Kids   : TList<TSymbol>;
  S      : TSymbol       ;
  Id     : Int64         ;
  Routine: Boolean       ;
  Values : TArray<TSymbol>;
begin
  Result := 0;
  AReason:= '';
  { 1. Lexical levels, innermost first; the first level that declares the name
    answers. A routine there is a nested routine's name -- not a variable. }
  for Id in AScope.Chain do
  begin
    Kids:= ChildrenOf(Id);
    if Kids = nil then Continue;
    Routine:= False;
    Values := [];
    for S in Kids do
      if SameText(S.Name, AName) then
      begin
        if S.Kind in [skLocalVar, skParam, skConstDecl, skVarDecl] then InsertNearestFirst(Values, S);
        Routine:= Routine or (S.Kind in METHOD_KINDS);
      end;
    { Review 2026-10-23: the NEAREST declaration at or before the site whose
      scope covers it -- two `for var i` loops declare two i's. }
    if Length(Values) > 0 then
    begin
      for S in Values do
        if LocalScopeCovers(S, AFileId, ALine, ACol) then Exit(S.Id);
      AReason:= 'ambiguous';
      Exit;
    end;
    if Routine then
    begin
      AReason:= 'routine';
      Exit;
    end;
  end;
  { 2. The name of the enclosing function or of one around it: its RESULT. }
  if Pos('|' + LowerCase(AName) + '|', AScope.FnNames) > 0 then
  begin
    AReason:= 'own-name';
    Exit;
  end;
  { 3. The owning type, then its ancestors, NEAREST FIRST whatever the member
    kind: a field of the class hides a property of the same name further up. }
  for Id in AScope.ClassChain do
  begin
    S:= FindChildOfKind(Id, AName, [skProperty, skField, skVarDecl, skConstDecl], False);
    if S.Id > 0 then Exit(S.Id);
    if FindChildOfKind(Id, AName, METHOD_KINDS, False).Id > 0 then
    begin
      AReason:= 'routine';
      Exit;
    end;
  end;
end;

function TCallResolver.UnitScopeWriteTarget(ARefFileId: Int64; const ALc: string;
  out AReason: string): Int64;

  { Whether a declaration in AFileId / ASection belongs to rung ARung: 1 is the
    writing file itself (both sections), 2 the interface of a unit it uses. }
  function OnRung(ARung: Integer; AFileId: Int64; const ASection: string): Boolean;
  begin
    if ARung = 1 then Result:= AFileId = ARefFileId
    else Result:= (AFileId <> ARefFileId) and SameText(ASection, 'interface')
                  and CandInScope(ARefFileId, AFileId);
  end;

  { Non-value declarations of the name on rung ARung: routines, types, enum values. }
  function OthersOnRung(ARung: Integer): Integer;
  var
    L: TList<TSymbol>       ;
    E: TList<TEnumValueDecl>;
    S: TSymbol              ;
    V: TEnumValueDecl       ;
  begin
    Result:= 0;
    if FNameToRoutines.TryGetValue(ALc, L) then
      for S in L do
        if OnRung(ARung, S.FileId, S.Section) then Inc(Result);
    if FNameToCands.TryGetValue(ALc, L) then
      for S in L do
        if OnRung(ARung, S.FileId, S.Section) then Inc(Result);
    if FNameToEnumValues.TryGetValue(ALc, E) then
      for V in E do
        if not V.Scoped and OnRung(ARung, V.FileId, V.Section) then Inc(Result);  { E14: a scoped value competes with nothing }
  end;

var
  Rung   : Integer       ;
  L      : TList<TSymbol>;
  S      : TSymbol       ;
  Values : Integer       ;
  Others : Integer       ;
  Found  : Int64         ;
begin
  Result := 0;
  AReason:= 'not-found';
  for Rung:= 1 to 2 do
  begin
    Values:= 0;
    Found := 0;
    if FNameToUnitValues.TryGetValue(ALc, L) then
      for S in L do
        if OnRung(Rung, S.FileId, S.Section) then
        begin
          Inc(Values);
          Found:= S.Id;
        end;
    Others:= OthersOnRung(Rung);
    if Values + Others = 0 then Continue;       { nothing here: look farther out }
    if (Values = 1) and (Others = 0) then
    begin
      AReason:= '';
      Exit(Found);
    end;
    if Values = 0 then AReason:= 'routine' else AReason:= 'ambiguous';
    Exit;                                         { the nearest rung ANSWERS }
  end;
end;

procedure TCallResolver.TallyWrite(const AReason: string);
begin
  if AReason = '' then Inc(FWriteStats.Bound)
  else if AReason = 'result' then Inc(FWriteStats.ResultVar)
  else if AReason = 'own-name' then Inc(FWriteStats.OwnName)
  else if AReason = 'with-scope' then Inc(FWriteStats.WithScope)
  else if AReason = 'ambiguous' then Inc(FWriteStats.Ambiguous)
  else if AReason = 'not-found' then Inc(FWriteStats.NotFound)
  else if AReason = 'routine' then Inc(FWriteStats.Routine)
  else Inc(FWriteStats.Unreadable);
end;

function TCallResolver.ResolveWriteRef(const ARef: TReference; out AReason: string): Int64;
var
  Lines  : TStringList    ;
  Scope  : TWriteScope    ;
  WType  : Int64          ;
  WKind  : TWithMemberKind;
  Verd   : TWithVerdict   ;
  ClassId: Int64          ;
  ViaSelf: Boolean        ;
begin
  Result := 0;
  AReason:= '';
  Verd   := wvNone;
  WType  := 0;
  WKind  := wmNone;
  ViaSelf:= False;
  Lines  := LinesOf(ARef.FileId);
  Scope  := WriteScopeOf(ARef.EnclosingSymbolId);
  { The `with` scope reads the file's text, so a line that no longer matches
    the index is a decline, never a guess -- the rule every rung here follows. }
  if (Lines = nil) or FileIsStale(ARef.FileId) or (ARef.NameText = '')
     or (ARef.StartLine < 1) or (ARef.StartLine > Lines.Count) then
    AReason:= 'unreadable'
  else if SameText(ARef.NameText, 'Result') then
    AReason:= 'result'
  else if SameText(if ARef.ReceiverText <> '' then ARef.ReceiverText    { T-11: parse fact first }
                   else ExtractReceiverExpr(Lines[ARef.StartLine - 1], ARef.StartCol), 'Self') then
  begin
    { `Self.X := v` (2026-09-28): the explicit qualifier names the member of the
      enclosing class whatever a local or a `with` target declares -- the rule
      ResolveBareMemberRead already applies to `Self.X` reads. Neither the with
      scope nor the lexical rungs run for it. }
    ViaSelf:= True;
    EnclosingClassChainDeclares(ARef.EnclosingSymbolId, '', ClassId);
    Result:= LookupMemberOnType(ClassId, ARef.NameText).Id;
    if Result <= 0 then
    begin
      Result := 0;
      AReason:= 'not-found';
    end;
  end
  else
    { Merge of D13 with D14: the with scope at THIS position, nearer than every
      scope below, replaces the pre-merge "any `with` above the site in the
      routine declines". A property/field of the target binds; a method is not
      assignable ('routine'); a class const/var or nested type, a target that
      cannot be typed, or one whose surface leaves the index declines. }
    Verd:= WithScopeAt(ARef, ARef.StartLine, ARef.StartCol, ARef.NameText, WType, WKind);
  if Verd = wvUndecided then AReason:= 'with-scope'
  else if Verd = wvMember then
  begin
    if WKind = wmValue then Result:= LookupMemberOnType(WType, ARef.NameText).Id;
    if Result <= 0 then
    begin
      Result := 0;
      AReason:= (if WKind = wmRoutine then 'routine' else 'with-scope');
    end;
  end
  else if (AReason = '') and not ViaSelf then
  begin
    Result:= ScopeWriteTarget(Scope, ARef.NameText, ARef.FileId, ARef.StartLine, ARef.StartCol, AReason);
    { Nothing nearer declares the name: the unit, then the units it uses. }
    if (Result = 0) and (AReason = '') then
      Result:= UnitScopeWriteTarget(ARef.FileId, LowerCase(ARef.NameText), AReason);
  end;
  TallyWrite(AReason);
end;

function TCallResolver.LocalScopeCovers(const ADecl: TSymbol; AFileId: Int64; ALine, ACol: Integer): Boolean;
var
  Lines: TStringList;
  IsFor: Boolean    ;
begin
  if ADecl.Kind <> skLocalVar then Exit(True);
  Lines:= LinesOf(AFileId);
  if (Lines = nil) or (ADecl.StartLine < 1) or (ADecl.StartLine > Lines.Count) then Exit(False);
  { Never a declaration after the site -- an anonymous method's var section
    can follow it. A var-section variable then covers the rest of its routine. }
  Result:= (ADecl.StartLine < ALine) or ((ADecl.StartLine = ALine) and (ADecl.StartCol <= ACol));
  if Result and InlineVarAt(Lines, ADecl.StartLine, ADecl.StartCol, IsFor) then
    Result:= InlineScopeOpen(CodeTokens(Lines, ADecl.StartLine, ADecl.StartCol, ALine, ACol), IsFor)
  { Item 4 (extractor 1.27.0): `on E: T do` declares E for its handler clause
    only -- the local_var's range IS the clause, so a site past its end (a
    sibling handler's E, a routine-level E after the try) is not covered. }
  else if Result and SameText(Copy(Lines[ADecl.StartLine - 1], ADecl.StartCol, 2), 'on')
          and (Length(Lines[ADecl.StartLine - 1]) >= ADecl.StartCol + 2)
          and CharInSet(Lines[ADecl.StartLine - 1][ADecl.StartCol + 2], [' ', #9]) then
    Result:= PosAtOrBefore(ALine, ACol, ADecl.EndLine, ADecl.EndCol);
end;

function TCallResolver.LocalInScopeAt(const ARef: TReference; const AName: string;
  out ADeclared: Boolean): TSymbol;
var
  Kids  : TList<TSymbol>  ;
  S     : TSymbol         ;
  Values: TArray<TSymbol> ;
begin
  Result   := Default(TSymbol);
  ADeclared:= False;
  Kids     := ChildrenOf(ARef.EnclosingSymbolId);
  if Kids = nil then Exit;
  Values:= [];
  for S in Kids do
    if (S.Kind in [skLocalVar, skParam]) and SameText(S.Name, AName) then InsertNearestFirst(Values, S);
  ADeclared:= Length(Values) > 0;
  for S in Values do
    if LocalScopeCovers(S, ARef.FileId, ARef.StartLine, ARef.StartCol) then Exit(S);
end;

{ The return type text of the anonymous method whose `function` keyword is
  AToks[AHeader]: the tokens after the optional parameter list's `:` up to the
  body or a declaration section, joined (already lowercased, so `tlist<tjob>`).
  '' for a procedure or a header this does not read. }
function AnonReturnType(const AToks: TArray<TCodeTok>; AHeader: Integer): string;
const
  BODY_START = '|begin|var|const|type|label|';
var
  K    : Integer;
  Depth: Integer;
  Parts: TArray<string>;
begin
  Result:= '';
  K     := AHeader + 1;
  Depth := 0;
  while (K <= High(AToks)) and ((Depth > 0) or (AToks[K].Text = '(')) do
  begin
    if AToks[K].Text = '(' then Inc(Depth)
    else if AToks[K].Text = ')' then Dec(Depth);
    Inc(K);
  end;
  if (K > High(AToks)) or (AToks[K].Text <> ':') then Exit;
  Parts:= [];
  Inc(K);
  while (K <= High(AToks)) and (Pos('|' + AToks[K].Text + '|', BODY_START) = 0) do
  begin
    Parts:= Parts + [AToks[K].Text];
    Inc(K);
  end;
  Result:= string.Join('', Parts);
end;

function TCallResolver.InsideAnonymousMethod(const ARef: TReference; out AReturnType: string): Boolean;
var
  Encl   : TSymbol         ;
  Lines  : TStringList     ;
  Toks   : TArray<TCodeTok>;
  K      : Integer         ;
  T      : string          ;
  P      : string          ;
  Depth  : Integer         ;
  Headers: TArray<Integer> ;
  Opened : TArray<Integer> ;
  OpenHdr: TArray<Integer> ;
begin
  AReturnType:= '';
  Encl := SymbolById(ARef.EnclosingSymbolId);
  Lines:= LinesOf(ARef.FileId);
  if (Lines = nil) or (Encl.ImplStartLine <= 0) then Exit(True);
  Toks   := CodeTokens(Lines, Encl.ImplStartLine, 1, ARef.StartLine, ARef.StartCol);
  Depth  := 0;
  Headers:= [];
  Opened := [];
  OpenHdr:= [];
  for K:= 0 to High(Toks) do
  begin
    T:= Toks[K].Text;
    P:= (if K > 0 then Toks[K - 1].Text else '');
    if ((T = 'function') or (T = 'procedure')) and (Pos('|' + P + '|', '|:=|(|,|[|') > 0) then
      Headers:= Headers + [K]                       { an anonymous method's header }
    else if (T = 'begin') and (Length(Headers) > 0) then
    begin
      Opened := Opened + [Depth];                   { its body: closes back at Depth }
      OpenHdr:= OpenHdr + [Headers[High(Headers)]];
      SetLength(Headers, Length(Headers) - 1);
      Inc(Depth);
    end
    else
    begin
      Inc(Depth, BlockDelta(T));
      if (Length(Opened) > 0) and (Depth = Opened[High(Opened)]) then
      begin
        SetLength(Opened, Length(Opened) - 1);
        SetLength(OpenHdr, Length(OpenHdr) - 1);
      end;
    end;
  end;
  Result:= (Length(Opened) > 0) or (Length(Headers) > 0);
  if (Length(Headers) = 0) and (Length(OpenHdr) > 0) then
    AReturnType:= AnonReturnType(Toks, OpenHdr[High(OpenHdr)]);
end;

function TCallResolver.ResultTypeAt(const ARef: TReference; out ADeclined: Boolean): string;
var
  AnonType: string;
begin
  Result    := SignatureReturnType(SymbolById(ARef.EnclosingSymbolId).Signature);
  ADeclined := InsideAnonymousMethod(ARef, AnonType)
               and ((AnonType = '') or (StripUnitQualifiers(AnonType) <> StripUnitQualifiers(Result)));
  if ADeclined then Result:= '';
end;

function TCallResolver.StripUnitQualifiers(const ATypeText: string): string;
var
  K     : Integer;
  J     : Integer;
  Chain : string ;
  Segs  : TArray<string>;
  Cut   : Integer;
  Prefix: string ;
  Out   : TStringBuilder;
begin
  Out:= TStringBuilder.Create;
  try
    K:= 1;
    while K <= Length(ATypeText) do
    begin
      if not (CharInSet(ATypeText[K], ['A'..'Z', 'a'..'z', '_', '&'])) then
      begin
        if ATypeText[K] > ' ' then Out.Append(LowerCase(ATypeText[K]));
        Inc(K);
        Continue;
      end;
      J:= K;
      while (J <= Length(ATypeText)) and CharInSet(ATypeText[J], ['A'..'Z', 'a'..'z', '0'..'9', '_', '&', '.']) do Inc(J);
      Chain:= LowerCase(Copy(ATypeText, K, J - K));
      K    := J;
      Segs := Chain.Split(['.']);
      { The longest leading run of segments that names a unit is dropped; `System`
        is always in scope, so it counts without an index row. }
      for Cut:= High(Segs) downto 1 do
      begin
        Prefix:= string.Join('.', Segs, 0, Cut);
        if (Prefix = 'system') or (UnitNameToFileId(Prefix) <> 0) then
        begin
          Chain:= string.Join('.', Segs, Cut, Length(Segs) - Cut);
          Break;
        end;
      end;
      Out.Append(Chain);
    end;
    Result:= Out.ToString;
  finally
    Out.Free;
  end;
end;

function TCallResolver.LocalDeclNamesOf(ARoutineId, AFileId: Int64): string;  // dl:ok cognitive-complexity@01b6 -- REVIEWED 2026-10-24 (lint sweep b0bad3cf..HEAD): 69 against 65; the resolve pass reads this, so restructuring it is resolve surface (re-pin), out of scope for a behaviour-identical sweep
var
  Toks: TArray<TCodeTok>;

  { True when token AIdx exists and is an identifier. }
  function IsName(AIdx: Integer): Boolean;
  begin
    Result:= (AIdx <= High(Toks)) and IsIdentStart(Toks[AIdx].Text[1]);
  end;

  { True when token AIdx exists and is a declaration's `=` or `:`. }
  function IsDeclMark(AIdx: Integer): Boolean;
  begin
    Result:= (AIdx <= High(Toks)) and ((Toks[AIdx].Text = '=') or (Toks[AIdx].Text = ':'));
  end;

const
  { After a `;`, one of these ends a const / type section. }
  SECTION_END = '|var|begin|procedure|function|constructor|destructor|label|asm|threadvar|';
var
  S     : TSymbol    ;
  Lines : TStringList;
  K, J  : Integer    ;
  T     : string     ;
  Names : string     ;
  Paren : Integer    ;
  InSect: Boolean    ;
begin
  if FLocalDecls.TryGetValue(ARoutineId, Result) then Exit;
  Result:= '|';
  S     := SymbolById(ARoutineId);
  Lines := LinesOf(AFileId);
  if (Lines <> nil) and (S.ImplStartLine > 0) then
  begin
    { Review 2026-10-23: tokens, not line starts -- `begin const X = 1;` declares
      X mid-line; a parameter list's `const A` (inside parentheses) does not. }
    Toks  := CodeTokens(Lines, S.ImplStartLine, 1, Min(S.ImplEndLine, Lines.Count) + 1, 1);
    Paren := 0;
    InSect:= False;
    for K:= 0 to High(Toks) do
    begin
      T:= Toks[K].Text;
      if T = '(' then Inc(Paren)
      else if T = ')' then Dec(Paren)
      else if Paren <> 0 then Continue
      else if (T = 'const') or (T = 'var') or (T = 'type') then
      begin
        { The name list after the keyword: `const X = 1`, `var A, B: T`, `var X := F`. }
        InSect:= T <> 'var';
        Names := '';
        J     := K + 1;
        while IsName(J) do
        begin
          Names:= Names + Toks[J].Text + '|';
          Inc(J);
          if (J <= High(Toks)) and (Toks[J].Text = ',') then Inc(J) else Break;
        end;
        if (Names <> '') and (IsDeclMark(J) or ((J <= High(Toks)) and (Toks[J].Text = ':='))) then
          Result:= Result + Names;  // dl:ok concat-in-loop@e316 -- REVIEWED 2026-10-23: a routine declares a handful of local names; the cached string stays tiny.
      end
      else if InSect and (T = ';') and IsName(K + 1) then
      begin
        { A const / type section goes on with `Name = ..` / `Name: T = ..`; a
          record's closing `end` keeps it open; anything else ends it. }
        if Pos('|' + Toks[K + 1].Text + '|', SECTION_END) > 0 then InSect:= False
        else if IsDeclMark(K + 2) then Result:= Result + Toks[K + 1].Text + '|'
        else InSect:= Toks[K + 1].Text = 'end';
      end;
    end;
  end;
  FLocalDecls.Add(ARoutineId, Result);
end;

function TCallResolver.FileTypesOf(AFileId: Int64): TArray<TSymbol>;
const
  TYPE_LIKE: TSymbolKindSet = [skClass, skInterface, skRecord, skTypeAlias, skEnum];
var
  S: TSymbol;
begin
  if FFileTypes.TryGetValue(AFileId, Result) then Exit;
  Result:= [];
  for S in FStore.FindSymbolsByFile(FStore.GetFilePath(AFileId)) do
    if (S.Kind in TYPE_LIKE) or (S.ParentId <= 0) then Result:= Result + [S];
  FFileTypes.Add(AFileId, Result);
end;

function TCallResolver.ScopeSymbolAt(const ARef: TReference): TSymbol;
var
  S   : TSymbol;
  Root: TSymbol;
begin
  if ARef.EnclosingSymbolId > 0 then Exit(SymbolById(ARef.EnclosingSymbolId));
  Result:= Default(TSymbol);
  Root  := Default(TSymbol);
  for S in FileTypesOf(ARef.FileId) do
    if S.ParentId <= 0 then Root:= S
    else if (S.StartLine <= ARef.StartLine) and (ARef.StartLine <= S.EndLine)
            and (S.StartLine >= Result.StartLine) then Result:= S;
  if Result.Id <= 0 then Result:= Root;
end;

function TCallResolver.ResolveTypeUse(const ARef: TReference; out AReason: string): Int64;
begin
  Result:= LookupTypeName(ARef, AReason);
  if AReason = '' then Inc(FTypeUseStats.Bound)
  else if AReason = 'generic' then Inc(FTypeUseStats.Generic)
  else if AReason = 'qualified' then Inc(FTypeUseStats.Qualified)
  else if AReason = 'unlisted' then Inc(FTypeUseStats.Unlisted)
  else if AReason = 'ambiguous' then Inc(FTypeUseStats.Ambiguous)
  else if AReason = 'not-found' then Inc(FTypeUseStats.NotFound)
  else Inc(FTypeUseStats.Unreadable);
end;

function TCallResolver.ResolveEnumCast(const ARef: TReference; out AReason: string): Int64;
begin
  Result:= LookupTypeName(ARef, AReason);
  if (Result > 0) and (SymbolById(Result).Kind <> skEnum) then
  begin
    Result := 0;
    AReason:= 'not-enum';
  end;
end;

function TCallResolver.LookupTypeName(const ARef: TReference; out AReason: string): Int64;
const
  TYPE_LIKE: TSymbolKindSet = [skClass, skInterface, skRecord, skTypeAlias, skEnum];

  { True when AParams -- a level's generic parameter list as indexed, e.g.
    'K, V: class' -- names ALc. }
  function NamesGenericParam(const AParams, ALc: string): Boolean;
  var
    Tok: string;
  begin
    Result:= False;
    for Tok in LowerCase(AParams).Split([',', ';', ':', ' ', '<', '>', '(', ')'], TStringSplitOptions.ExcludeEmpty) do
      if Tok = ALc then Exit(True);
  end;

var
  Lines: TStringList     ;
  Rcv  : string          ;
  Lc   : string          ;
  Cur  : TSymbol         ;
  Depth: Integer         ;
  Cands: TList<TSymbol>  ;
  S    : TSymbol         ;
  Full : TSymbol         ;
  Count: Integer         ;
  Anc  : TTypeAncestor   ;
begin
  Result := 0;
  AReason:= BareReadSite(ARef, Lines, Rcv);
  if (AReason = '') and (Rcv <> '') then AReason:= 'qualified';
  Lc:= LowerCase(ARef.NameText);
  { 1. The ref's scope outwards: enclosing routines, types, the own unit. }
  Cur  := ScopeSymbolAt(ARef);
  Depth:= 0;
  while (AReason = '') and (Result = 0) and (Cur.Id > 0) and (Depth < MAX_LEXICAL_DEPTH) do
  begin
    Inc(Depth);
    if NamesGenericParam(Cur.GenericParams, Lc) then AReason:= 'generic'
    else if (Cur.Kind in METHOD_KINDS) and (Pos('|' + Lc + '|', LocalDeclNamesOf(Cur.Id, ARef.FileId)) > 0) then
      AReason:= 'unlisted'
    else
    begin
      Result:= FindChildOfKind(Cur.Id, ARef.NameText, TYPE_LIKE, False).Id;
      { Review 2026-10-23: an ancestor's nested type is in scope too, nearest
        ancestor first, before any enclosing or used-unit type. }
      if (Result = 0) and (Cur.Kind in [skClass, skRecord, skInterface]) then
        for Anc in AncestorsOf(Cur.Id) do
          if Anc.Resolved and (Anc.SymbolId > 0) then
          begin
            Result:= FindChildOfKind(Anc.SymbolId, ARef.NameText, TYPE_LIKE, False).Id;
            if Result > 0 then Break;
          end;
      if Cur.ParentId <= 0 then Cur:= Default(TSymbol)
      else Cur:= SymbolById(Cur.ParentId);
    end;
  end;
  { 2. The used units: exactly one top-level interface type of the name. }
  if (AReason = '') and (Result = 0) then
  begin
    Count:= 0;
    if FNameToCands.TryGetValue(Lc, Cands) then
      for S in Cands do
        if (S.FileId <> ARef.FileId) and CandInScope(ARef.FileId, S.FileId) then
        begin
          Full:= SymbolById(S.Id);
          if SameText(Full.Section, 'interface') and (Full.ParentId > 0)
             and (SymbolById(Full.ParentId).ParentId <= 0) then
          begin
            Inc(Count);
            Result:= S.Id;
          end;
        end;
    if Count = 0 then AReason:= 'not-found'
    else if Count > 1 then
    begin
      Result := 0;
      AReason:= 'ambiguous';
    end;
  end;
end;

function TCallResolver.ResolveBareValueRead(const ARef: TReference; out AReason: string): Int64;
const
  VALUE_KINDS: TSymbolKindSet = [skLocalVar, skParam, skConstDecl, skVarDecl];
var
  Lines: TStringList    ;
  Rcv  : string         ;
  WType: Int64          ;
  WKind: TWithMemberKind;
  Scope: TWriteScope    ;
  Id     : Int64          ;
  Lc     : string         ;
  Parent : Int64          ;
begin
  Result := 0;
  AReason:= BareReadSite(ARef, Lines, Rcv);
  if (AReason = '') and (Rcv <> '') then AReason:= 'qualified'
  else if (AReason = '') and SameText(ARef.NameText, 'Result') then AReason:= 'result';
  if AReason = '' then
    case WithScopeAt(ARef, ARef.StartLine, ARef.StartCol, ARef.NameText, WType, WKind) of
      wvUndecided: AReason:= 'with-scope';
      wvMember   : AReason:= 'member';
    end;
  if AReason = '' then
  begin
    Scope := WriteScopeOf(ARef.EnclosingSymbolId);
    Lc    := LowerCase(ARef.NameText);
    Result:= ScopeWriteTarget(Scope, ARef.NameText, ARef.FileId, ARef.StartLine, ARef.StartCol, AReason);
    if (Result = 0) and (AReason = '') then
      Result:= UnitScopeWriteTarget(ARef.FileId, Lc, AReason);
    if (Result > 0) and not (SymbolById(Result).Kind in VALUE_KINDS) then
    begin
      Result := 0;
      AReason:= 'member';
    end;
    { A local const or inline declaration the index does not list is nearer
      than the scope that answered when a routine INSIDE that scope declares
      it: every lexical level below the answering one (all of them when the
      class or unit answered) must not declare the name in its text. Review
      2026-10-23: a nested routine's const hides the outer routine's param. }
    if Result > 0 then
    begin
      Parent:= SymbolById(Result).ParentId;
      for Id in Scope.Chain do
      begin
        if Id = Parent then Break;
        if Pos('|' + Lc + '|', LocalDeclNamesOf(Id, ARef.FileId)) > 0 then
        begin
          Result := 0;
          AReason:= 'unlisted';
          Break;
        end;
      end;
    end;
  end;
  if AReason = '' then Inc(FValueReadStats.Bound)
  else if AReason = 'result' then Inc(FValueReadStats.ResultVar)
  else if AReason = 'own-name' then Inc(FValueReadStats.OwnName)
  else if AReason = 'with-scope' then Inc(FValueReadStats.WithScope)
  else if AReason = 'member' then Inc(FValueReadStats.Member)
  else if AReason = 'ambiguous' then Inc(FValueReadStats.Ambiguous)
  else if AReason = 'not-found' then Inc(FValueReadStats.NotFound)
  else if AReason = 'routine' then Inc(FValueReadStats.Routine)
  else if AReason = 'qualified' then Inc(FValueReadStats.Qualified)
  else if AReason = 'unlisted' then Inc(FValueReadStats.Unlisted)
  else Inc(FValueReadStats.Unreadable);
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
  RcvType : TRcvTypeText;
begin
  Result:= Default(TCallEdge);
  Result.RefId:= ACallRef.Id;
  Result.TargetSymbolId      := 0;
  Result.ReceiverTypeSymbolId:= 0;
  Result.Confidence          := '';
  { rb5-ovl: no site until the arguments are counted below. }
  FSiteLines      := nil;
  FSiteShapesState:= 0;

  if ACallRef.NameText = '' then Exit;

  // 1. the receiver expression left of '.M'. T-11 (extractor 1.25.0): the
  // parser records it from the CST in refs.receiver_text, which is the FACT --
  // whole across line breaks and true for the parse even when the file has
  // changed since. Only a row without it (a bare call, a pre-1.25 parse) falls
  // back to reading the source line.
  Rcv  := ACallRef.ReceiverText;
  Lines:= LinesOf(ACallRef.FileId);
  if (Rcv = '') and (Lines <> nil) and (ACallRef.StartLine >= 1) and (ACallRef.StartLine <= Lines.Count) then
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
  Result.ReceiverUnknown:= (ACallRef.ReceiverText = '') and FileIsStale(ACallRef.FileId); { T-11: a parse fact is never a guess }

  // 1b. B1: count the arguments at this site, from the same cached lines. Unlike
  // the receiver scan -- which reads LEFT and cannot leave the line -- an
  // argument list reads RIGHT and legitimately spans lines, so this is given the
  // whole file rather than the single line.
  ArgCount:= CountCallArgs(Lines, ACallRef.StartLine, ACallRef.StartCol, ArgsKnown);
  FSiteRef     := ACallRef;
  FSiteLines   := Lines;
  FSiteArgCount:= if ArgsKnown then ArgCount else -1;

  // 1c. NESTED-CALL RESOLUTION: a BARE call is resolved by Delphi's lexical
  // scope chain BEFORE any receiver typing, because the innermost declaration
  // wins outright -- a nested routine shadows a same-named method of the
  // enclosing class, so consulting the class first would answer the wrong one.
  // Falls through untouched when no scope on the chain declares the name, which
  // is the common case (an intrinsic, an RTL call, a unit-level routine).
  if Rcv = '' then
  begin
    { 1b'. THE WITH SCOPE (1.8.0, D14) is nearer still: inside `with A do`, a
      bare M that A's type declares IS A.M, whatever the lexical chain, the
      class or the unit say. Before this rung a bare call in a with body bound
      to the ENCLOSING class's same-named method -- the one the compiler does
      not pick. When the with scope decides (bound, or declined), nothing below
      may run for the call. }
    if BareCallInNearScopes(ACallRef, ArgCount, ArgsKnown, Result) then Exit;
  end;

  // 2. type the receiver -> a class/interface/record symbol id.
  TypeId:= TypeReceiver(ACallRef, Rcv, RcvType);
  Result.ReceiverTypeSymbolId:= TypeId; // 0 when the receiver type is unknown
  { Item 4: the declared type TEXT, set here so every exit below carries it
    (spec s.4.1): '' for a bare / Self receiver and for one nothing types. }
  Result.ReceiverTypeText:= RcvType.Text + (if (RcvType.Text <> '') and (RcvType.Pending <> '') then '.' + RcvType.Pending else '');
  if (Rcv <> '') and not SameText(Rcv, 'Self') then
    if TypeId > 0 then Inc(FReceiverStats.TypedLocal)
    else if RcvType.Text <> '' then Inc(FReceiverStats.TypedByNameOnly)
    else Inc(FReceiverStats.Untyped);

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
    value carries no mode and no accessor to record).

    3d. UNIT-QUALIFIED VAR / CONST (2026-09-24, D22, resolver 1.9.0-alpha), the
    rest of `Unit.value` and the value twin of rung 4b: `uStyles.SkipRefresh`,
    read or written -- the extractor emits the write as a member-access too, with
    no separate `write` ref. 4 unbound sites on ORM3 CLIENT at 1.8.0, all writes.
    NOT ValueOnly (ruling R15): a unit variable IS read or written, and an
    identity-only binding made `find-callers --resolved` call every write a
    read. It carries a MemberMode exactly as 3b's dotted field/property does, so
    the store writes refs.symbol_id AND a member_accesses row (mode, no
    accessor, no call edge). Both rungs live in QualifiedValueTarget, 3c first;
    FUnitValueBound moving is how 3d's answer is told from 3c's. }
  if SameText(ACallRef.Kind, 'member-access') and (Rcv <> '') then
  begin
    var UnitValuesBefore: Int64:= FUnitValueBound;
    Target:= QualifiedValueTarget(ACallRef, Rcv, TypeId);
    if Target > 0 then
    begin
      Result.TargetSymbolId:= Target;
      Result.Confidence    := 'certain';
      if FUnitValueBound > UnitValuesBefore then
      begin
        Result.MemberMode:= MemberAccessMode(ACallRef);
        if Result.MemberMode = '' then Result.MemberMode:= 'read';
      end
      else
        Result.ValueOnly:= True;
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
  //
  // 4b. UNIT-QUALIFIED FREE ROUTINE (2026-09-23, ENG-16, resolver 1.8.0-alpha),
  // the one dotted shape this rung does take. `Pipes.Commands.DispatchCommand(...)`
  // names a routine THROUGH ITS UNIT: the receiver is a unit, not a value, so it
  // never types, rung 3c is for enum values only, and until now these sites fell
  // out unbound -- 6 sites on ORM3 CLIENT at 1.7.0. The routine twin of 3c's
  // `Unit.value` half; LookupUnitQualifiedRoutine declines unless receiver
  // typing answered 0 (a receiver that TYPED is a value, and a routine missing
  // from its type must not be looked up in a unit instead) and unless the
  // receiver resolves to exactly one unit that nothing nearer shadows.
  if Rcv = '' then
    Target:= LookupUnitLevelRoutine(ACallRef.FileId, ACallRef.NameText, ArgCount, ArgsKnown, Conf)
  else
    Target:= LookupUnitQualifiedRoutine(ACallRef, Rcv, TypeId, ArgCount, ArgsKnown, Conf);
  if Target > 0 then
  begin
    // ReceiverTypeSymbolId is CLEARED, matching the lexical rung above. For a
    // bare call inside a method, TypeReceiver returns the enclosing class --
    // the implicit Self, not a receiver the source wrote. Leaving it set would
    // record "this call went through a TFoo receiver" for a call that has no
    // receiver at all, and the two bare-call rungs would disagree about the
    // same field. A unit receiver has no type either.
    Result.ReceiverTypeSymbolId:= 0;
    Result.TargetSymbolId:= Target;
    Result.Confidence    := Conf;
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
  //
  // Item 4 (resolver 1.16.0-alpha): through the library oracle, for a VALUE
  // receiver typed by name too, and called with no store open as well -- the
  // oracle then counts the site as no-store at once, which is the number the
  // `receivers:` line exists to print.
  if Result.TargetSymbolId = 0 then
  begin
    Result.ExternalTarget:= BindExternally(ACallRef, Rcv, TypeId, RcvType);
    { BindHead typed a head the project could not: that text is the fact now. }
    if (Result.ReceiverTypeText = '') and (RcvType.Text <> '') then
      Result.ReceiverTypeText:= RcvType.Text;
  end;
end;

function TCallResolver.OracleStats: TOracleStats;
begin
  Result:= FOracle.Stats;
end;

function TCallResolver.FirstUnresolvedAncestorName(ATypeId: Int64): string;
begin
  Result:= '';
  for var A: TTypeAncestor in AncestorsOf(ATypeId) do
    if not A.Resolved and (A.Ordinal = 0) then Exit(A.Name);
  for var A: TTypeAncestor in AncestorsOf(ATypeId) do
    if not A.Resolved then Exit(A.Name);
end;

function TCallResolver.ChainDeclaresName(ATypeId: Int64; const AName: string): Boolean;
var
  AnyMember: TSymbolKindSet;
begin
  AnyMember:= METHOD_KINDS + [skProperty, skField, skVarDecl, skConstDecl];
  Result:= FindChildOfKind(ATypeId, AName, AnyMember).Id > 0;
  if Result then Exit;
  for var A: TTypeAncestor in AncestorsOf(ATypeId) do
    if A.Resolved and (A.SymbolId > 0) and (FindChildOfKind(A.SymbolId, AName, AnyMember).Id > 0) then Exit(True);
end;

function TCallResolver.FileUsesUnits(AFileId: Int64): TArray<string>;
begin
  if FFileUses.TryGetValue(AFileId, Result) then Exit;
  if not FDprLoaded then
  begin
    FDprLoaded:= True;
    for var Id: Int64 in FStore.GetAllFileIds do
      if SameText(ExtractFileExt(FStore.GetFilePath(Id)), '.dpr') then
        for var U: TUnitUse in FStore.GetUnitUsesForFile(Id) do FDprUses:= FDprUses + [LowerCase(U.UnitName)];
  end;
  Result:= FDprUses;
  for var U: TUnitUse in FStore.GetUnitUsesForFile(AFileId) do Result:= Result + [LowerCase(U.UnitName)];
  FFileUses.Add(AFileId, Result);
end;

{ Item 4. A wrong external name is a wrong FACT rendered in documentation, so
  every path below hands the oracle something THIS index could not answer and
  never overrides what it could:
    * a PROJECT type (typed receiver, or a type text naming one): only when no
      type on its project chain declares the member -- then the oracle starts at
      the first ancestor this index did not resolve (`AStream.Position`,
      TABZMemoryStream -> TStream);
    * a type known by name only (`FMemTable.Post`): the oracle as is;
    * an untyped identifier chain (`Application.ProcessMessages`): BindHead,
      unless the head names a type or a unit-level value of THIS index (a
      duplicated project type declines here, it is not a library one);
    * a bare call: unless a local / parameter of the name is in scope (a
      procedural value) or the project declares a routine / class member of
      the name, BindBare -- the enclosing class's library ancestor,
      then a library routine of a used unit. }
function TCallResolver.BindExternally(const ACallRef: TReference; const AReceiver: string; ATypeId: Int64;  // dl:ok too-many-exit-points@0825 -- REVIEWED 2026-10-28 (item 4, lane R4R): one exit per receiver shape -- bare, project type, by-name type, untyped head -- plus the declines that keep a library name from overriding the project's own declaration; each is a distinct outcome the comment above lists in order.
  var AText: TRcvTypeText): string;
var
  Reason  : string;
  Kind    : TExternalKind;
  ProjId  : Int64 ;
  Declared: Boolean;
  HeadText: string;

  function ScopeType: string;
  var
    ClassId: Int64;
  begin
    EnclosingClassChainDeclares(ACallRef.EnclosingSymbolId, '', ClassId);
    Result:= if ClassId > 0 then FirstUnresolvedAncestorName(ClassId) else '';
  end;

begin
  Result:= '';
  if AReceiver = '' then
  begin
    LocalInScopeAt(ACallRef, ACallRef.NameText, Declared);
    var ClassId: Int64;
    { A routine of the name in THIS index (unit level, or on the enclosing class
      chain) that local resolution declined -- arity, an overload tie -- is still
      the project's: never answer it from a library. }
    if Declared or FNameToRoutines.ContainsKey(LowerCase(ACallRef.NameText))
       or EnclosingClassChainDeclares(ACallRef.EnclosingSymbolId, ACallRef.NameText, ClassId) then Exit;
    Exit(FOracle.BindBare(ACallRef.NameText, FileUsesUnits(ACallRef.FileId), ScopeType, Reason));
  end;
  Kind:= if SameText(ACallRef.Kind, 'member-access') then ekMemberAccess else ekCall;
  ProjId:= 0;
  if AText.Text <> '' then
    ProjId:= if (ATypeId > 0) and (AText.Pending = '') then ATypeId else ResolveTypeNameToSymbol(AText.Text, ACallRef.FileId)
  else if ATypeId > 0 then
    ProjId:= ATypeId; // Self, a with target
  if ProjId > 0 then
  begin
    var First: string:= if AText.Pending <> '' then AText.Pending.Split(['.'])[0] else ACallRef.NameText;
    var Anc: string:= FirstUnresolvedAncestorName(ProjId);
    if (Anc = '') or ChainDeclaresName(ProjId, First) then Exit;
    Exit(FOracle.Bind(Anc, AText.Pending, ACallRef.NameText, Kind, FileUsesUnits(ACallRef.FileId), Reason));
  end;
  if AText.Text <> '' then
    Exit(FOracle.Bind(AText.Text, AText.Pending, ACallRef.NameText, Kind, FileUsesUnits(ACallRef.FileId), Reason));
  if AText.Head = '' then Exit;
  var HeadLc: string:= LowerCase(Trim(AText.Head.Split(['.'])[0]));
  if FNameToCands.ContainsKey(HeadLc) or FNameToUnitValues.ContainsKey(HeadLc) then Exit;
  Result:= FOracle.BindHead(AText.Head, ACallRef.NameText, Kind, FileUsesUnits(ACallRef.FileId), ScopeType,
    Reason, HeadText);
  if HeadText <> '' then AText.Text:= HeadText;
end;

end.
