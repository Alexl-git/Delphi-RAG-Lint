unit DRagLint.Query.HappensBefore.Roots;

{ drag-lint 1.52 -- lane HBROOTS: where execution can start (spec 2026-11-17-happens-before-design.md 3 and 5.2).

  ORDERED roots: per program, the initialization sections in the computed unit order (ProgramInitOrders of
  DRagLint.Lint.InitSections -- the order init-order-hazard walks), then the program main block.
  ESCAPED routines (unordered roots, EntryDone = False): a routine the call graph cannot account for because
  something outside the code calls it -- a DFM event, the published section, a message handler, an interface
  method answer, a routine whose address is taken, an exported routine, a thread Execute, a class constructor /
  destructor, a finalization section -- or one with ZERO callers that is none of those.
  Overrides are not escaped: their callers are the callers of the base methods they override (dispatch_edges).

  Read-only; nothing is persisted (no extractor change).

  Blind spots (index shape, 1.52): a parameterless FUNCTION named without `@` on the right of `:=` gets the
  same read / member-access ref and certain call edge whether it is called or assigned as a method pointer,
  so it is taken as a call. A procedure in that position can only be a value and is address-taken. An
  `exports` clause entry is a refs row of kind REF_KIND_EXPORT bound to the routine (1.52 EXTGAPS2; no call edge). }

interface

uses
  System.SysUtils
, System.Generics.Collections
, DRagLint.Core.Model
, DRagLint.Core.Interfaces
, DRagLint.Lint.InitSections
  ;

type
  /// <summary>What an ordered root is.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Roots.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbRootKind = (hrkInitialization, hrkProgramBlock);

  /// <summary>One link of an ordered root chain.</summary>
  /// <remarks>
  /// SymbolId is the initialization section symbol (hrkInitialization) or the program symbol
  /// (hrkProgramBlock). UnitName is '' for the program block.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Roots.pas) ?, DRagLint.Query.HappensBefore.Roots.LoadRoots (DRagLint.Query.HappensBefore.Roots.pas)</para>
  /// <para>Used in units: DRagLint.Query.HappensBefore.Roots</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbOrderedRoot = record
    Kind: THbRootKind;
    SymbolId: Int64;
    UnitName: string;
    FileId: Int64;
    /// <summary>Display name in run order: 'initialization of Boot' / 'program block of App.dpr'.</summary>
    Display: string;
  end;

  /// <summary>The ordered root chain of one program (spec 5.2).</summary>
  /// <remarks>
  /// Roots run first to last. A unit without an initialization section is not a link (it runs
  /// nothing); the program block is the last link when the program symbol is indexed. Unreliable: some uses
  /// entry that decides the order is conditional or include-borne (reason code unreliable-order); the
  /// chain is the order of the indexed configuration and UnreliableReason names the first such site.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Roots.pas) ?, DRagLint.Query.HappensBefore.Roots.LoadRoots (DRagLint.Query.HappensBefore.Roots.pas)</para>
  /// <para>Used in units: DRagLint.Query.HappensBefore.Roots</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbRootChain = record
    ProgramFileId: Int64;
    ProgramName: string;
    Roots: TArray<THbOrderedRoot>;
    Unreliable: Boolean;
    UnreliableReason: string;
  end;

  /// <summary>Every ordered root chain of the index, one per program file.</summary>
  /// <remarks>
  /// Empty Chains: the index holds no program (a package or a unit set); every initialization
  /// section is then unordered and the solver must not rely on any order.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Roots.pas) ?, DRagLint.Query.HappensBefore.Roots.LoadRoots (DRagLint.Query.HappensBefore.Roots.pas)</para>
  /// <para>Used in units: DRagLint.Query.HappensBefore.Roots</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbRoots = record
    Chains: TArray<THbRootChain>;
  end;

  /// <summary>Why a routine is an unordered root (spec 5.2). Literals: EscapeClassCode.</summary>
  /// <remarks>
  /// hecNone = not escaped: it runs only when its callers run (or it is an ordered root, or an
  /// override reached through its bases). The order is the order IsEscaped tests them; the first that holds
  /// is reported.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Roots.pas), DRagLint.Query.HappensBefore.Roots.EscapeClassCode (DRagLint.Query.HappensBefore.Roots.pas), DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ClassOf (DRagLint.Query.HappensBefore.Roots.pas), DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.DeclaredClassOf (DRagLint.Query.HappensBefore.Roots.pas), DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.MemberClassOf (DRagLint.Query.HappensBefore.Roots.pas) (+1 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbEscapeClass = (hecNone, hecFinalization, hecClassCtorDtor, hecDfmEvent, hecMessageHandler,
    hecThreadExecute, hecExported, hecInterfaceMethod, hecPublished, hecAddressTaken, hecZeroCallers);

  /// <summary>Classifies routines as escaped or not, caching what is shared between routines (the
  /// interface-answer set, the TThread descendants).</summary>
  /// <remarks>Read-only on the store. Not thread-safe; one instance per query. The store must outlive it.
  /// v152 HOVERCACHE: a COMPLETE interface-answer set is also kept process-wide per index version
  /// (HbIndexVersionKey of the store's DbPath), so the next classifier over the same index skips the walk.</remarks>
  THbEscapeClassifier = class  // dl:ok high-response@8273 -- REVIEWED 2026-11-17 v152 HBROOTS: one classifier, one escape class per question (spec 5.2 lists ten); its RFC is the store calls each class needs, splitting it would only spread the same calls
  strict private
    FStore: ISymbolStore;
    FAnswers: THashSet<Int64>;
    FThreadClasses: THashSet<string>;
    FAnswersLoaded: Boolean;
    FThreadsLoaded: Boolean;
    FFileIds: TDictionary<string, Int64>;
    FStopCheck: TFunc<Boolean>;
    procedure LoadAnswers;
    /// <summary><!-- drag-lint:auto sum -->True when pName descends from TThread (the
    /// descendant set is loaded on the first question).</summary>
    /// <param name="pName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed:
    /// FThreadClasses.Contains(LowerCase(pName)).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.MemberClassOf (DRagLint.Query.HappensBefore.Roots.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindDescendantNames, LowerCase</para>
    /// <para>Reads: FThreadsLoaded, FStore, FThreadClasses   Writes: FThreadsLoaded</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindDescendantNames"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ClassOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.Create"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.DeclaredClassOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsThreadClass(const pName: string): Boolean;
    /// <param name="pSym"><!-- drag-lint:auto type -->const TSymbol</param>
    /// <returns><!-- drag-lint:auto -->TSymbol -- Observed: Default(TSymbol); P.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.MemberClassOf (DRagLint.Query.HappensBefore.Roots.pas)</para>
    /// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById</para>
    /// <para>Reads: FStore</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ClassOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.Create"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.DeclaredClassOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ParentClassOf(const pSym: TSymbol): TSymbol;
    /// <summary><!-- drag-lint:auto sum -->files.id of an indexed path (0 when the index
    /// holds no symbol in it); cached per path.</summary>
    /// <param name="pPath"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Int64 -- Observed: 0; S.FileId.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.IsCallRefAt (DRagLint.Query.HappensBefore.Roots.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile, LowerCase</para>
    /// <para>Reads: FFileIds, FStore</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ClassOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.Create"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.DeclaredClassOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FileIdOf(const pPath: string): Int64;
    /// <summary><!-- drag-lint:auto sum -->True when an `exports` clause names pSym: a
    /// REF_KIND_EXPORT ref bound to it (1.52 EXTGAPS2). Before 1.52 the entry was a
    /// 'call' ref with a call edge and this read the clause back from the source text.</summary>
    /// <param name="pSym"><!-- drag-lint:auto type -->const TSymbol</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ScanCallers (DRagLint.Query.HappensBefore.Roots.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindReferencesTo, SameText</para>
    /// <para>Reads: FStore</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindReferencesTo"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ClassOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.Create"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.DeclaredClassOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsExportedByClause(const pSym: TSymbol): Boolean;
    /// <param name="pSym"><!-- drag-lint:auto type -->const TSymbol</param>
    /// <param name="pCaller"><!-- drag-lint:auto type -->const TResolvedCaller</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ScanCallers (DRagLint.Query.HappensBefore.Roots.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindRefsNamingInFiles, DRagLint.Query.HappensBefore.Roots.ReturnsValue, DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.FileIdOf, LowerCase, SameText</para>
    /// <para>Reads: FStore</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindRefsNamingInFiles"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.ReturnsValue"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.FileIdOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ClassOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsCallRefAt(const pSym: TSymbol; const pCaller: TResolvedCaller): Boolean;
    /// <summary><!-- drag-lint:auto sum -->True when some site calls pSym for real.
    /// pAddressTaken: some site names it as a value (a callback edge, a bound non-call
    /// ref, or an edge on a non-call ref). pExported: an `exports` clause names it.</summary>
    /// <param name="pSym"><!-- drag-lint:auto type -->const TSymbol</param>
    /// <param name="pAddressTaken"><!-- drag-lint:auto type -->out Boolean</param>
    /// <param name="pExported"><!-- drag-lint:auto type -->out Boolean</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ClassOf (DRagLint.Query.HappensBefore.Roots.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindResolvedCallers, DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.IsCallRefAt, DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.IsExportedByClause, SameText</para>
    /// <para>Reads: FStore</para>
    /// <para>Mutates: pAddressTaken (out), pExported (out)</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindResolvedCallers"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.IsCallRefAt"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.IsExportedByClause"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ClassOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ScanCallers(const pSym: TSymbol; out pAddressTaken, pExported: Boolean): Boolean;
    /// <summary><!-- drag-lint:auto sum -->The classes that need only the symbol row and
    /// its facts: finalization, class ctor/dtor, DFM event, message handler, then
    /// MemberClassOf.</summary>
    /// <param name="pSym"><!-- drag-lint:auto type -->const TSymbol</param>
    /// <returns><!-- drag-lint:auto -->THbEscapeClass -- Observed: if pSym.Kind =
    /// skFinalization then hecFinalization.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ClassOf (DRagLint.Query.HappensBefore.Roots.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetSymbolFacts, DRagLint.Query.HappensBefore.Roots.HasWord, DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.MemberClassOf</para>
    /// <para>Reads: FStore</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolFacts"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.HasWord"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.MemberClassOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ClassOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function DeclaredClassOf(const pSym: TSymbol): THbEscapeClass;
    /// <summary><!-- drag-lint:auto sum -->A plain routine: exported by directive or not
    /// escaped by declaration. A method: thread Execute, interface answer, published (the
    /// unlabelled leading section counts as published).</summary>
    /// <param name="pSym"><!-- drag-lint:auto type -->const TSymbol</param>
    /// <returns><!-- drag-lint:auto -->THbEscapeClass -- Observed: if
    /// FAnswers.Contains(pSym.Id) then hecInterfaceMethod.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.DeclaredClassOf (DRagLint.Query.HappensBefore.Roots.pas)</para>
    /// <para>Calls: DRagLint.Query.HappensBefore.Roots.HasWord, DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.IsThreadClass, DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.LoadAnswers, DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ParentClassOf, SameText, Trim</para>
    /// <para>Reads: FAnswers</para>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.HasWord"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.IsThreadClass"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.LoadAnswers"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ParentClassOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ClassOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function MemberClassOf(const pSym: TSymbol): THbEscapeClass;
  public
    /// <summary>Creates a classifier over pStore.</summary>
    /// <param name="pStore">The project index; must not be nil.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.Receiver.TRecvSolver.Create (DRagLint.Query.HappensBefore.Receiver.pas), DRagLint.Query.HappensBefore.Roots.EscapeClassOf (DRagLint.Query.HappensBefore.Roots.pas), DRagLint.Query.HappensBefore.TSolver.Create (DRagLint.Query.HappensBefore.pas)</para>
    /// <para>constructor</para>
    /// <para>Writes: FStore, FAnswers, FThreadClasses, FFileIds</para>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ClassOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.DeclaredClassOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.Destroy"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.FileIdOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.IsCallRefAt"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(const pStore: ISymbolStore);
    /// <summary>Frees the caches.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FFileIds, FThreadClasses, FAnswers</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ClassOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.Create"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.DeclaredClassOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.FileIdOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.IsCallRefAt"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>v152 HOVERCAP: asked once per interface while the interface-answer set loads (the classifier's
    /// one whole-index walk, ~2.5 s on the drag-lint index); True ends the walk with the set PARTIAL.</summary>
    /// <remarks>nil (the default) never stops. check-init passes its wall-clock check (HbTimeUp) and discards
    /// every answer computed after it returned True, so a partial set never decides a verdict.</remarks>
    property StopCheck: TFunc<Boolean> read FStopCheck write FStopCheck;
    /// <summary>The escape class of one routine.</summary>
    /// <param name="pRoutineId">symbols.id of a routine, an initialization / finalization section or the
    /// program symbol.</param>
    /// <returns>hecNone for an ordered root (initialization, program block), an override with a base, a
    /// routine with at least one real call and no other escape, or an unknown id; else the first escape
    /// class that holds.</returns>
    /// <remarks>
    /// A routine passed as a value (call_edges confidence 'callback', a bound non-call ref such as
    /// `@Proc`, or a call edge whose ref is no `call` ref, as the index records `OnX := H.Handler`) is
    /// hecAddressTaken. A routine named in an `exports` clause (or carrying the `export` directive) is
    /// hecExported; the clause entry is its REF_KIND_EXPORT ref (1.52). The leading unlabelled section of a class is treated as
    /// published (under $M+ it is; the index cannot tell $M+), which can only add escapes, never hide one.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.Receiver.TRecvSolver.OnlyAfterConstruction (DRagLint.Query.HappensBefore.Receiver.pas), DRagLint.Query.HappensBefore.Receiver.TRecvSolver.ProveCallers (DRagLint.Query.HappensBefore.Receiver.pas), DRagLint.Query.HappensBefore.Roots.EscapeClassOf (DRagLint.Query.HappensBefore.Roots.pas), DRagLint.Query.HappensBefore.TSolver.IsRoot (DRagLint.Query.HappensBefore.pas), DRagLint.Query.HappensBefore.TSolver.JudgeUse (DRagLint.Query.HappensBefore.pas) (+1 more)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindDispatchLinks, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.DeclaredClassOf, DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ScanCallers</para>
    /// <para>Returns: hecNone; DeclaredClassOf(S); hecExported; hecAddressTaken; hecZeroCallers</para>
    /// <para>Reads: FStore</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindDispatchLinks"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.DeclaredClassOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ScanCallers"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ClassOf(pRoutineId: Int64): THbEscapeClass;
  end;

/// <summary>Loads the ordered root chains of every program in the index (spec 5.2).</summary>
/// <param name="pStore">The project index; nil yields no chains.</param>
/// <returns>One chain per program file, in ProgramInitOrders order; each chain lists the initialization
/// sections in the order init-order-hazard computes, then the program block.</returns>
/// <remarks>
/// Read-only. Not thread-safe; reads the index once per call, nothing is cached.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.TSolver.LoadPrograms (DRagLint.Query.HappensBefore.pas)</para>
/// <para>Calls: Default, DRagLint.Lint.InitSections.ProgramInitOrders</para>
/// <para>Returns: Default(THbRoots)</para>
/// <seealso cref="DRagLint.Lint.InitSections.ProgramInitOrders"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function LoadRoots(const pStore: ISymbolStore): THbRoots;  // dl:ok unused-public-symbol@a866 -- REVIEWED 2026-11-17 v152 HBROOTS: check-init roots API for lanes HBSOLVER / HBEVORD (merge after HBROOTS); today only tests\fixtures\happens-before\roots-harness\RootsHarness.dpr calls it

/// <summary>The ordered root chains of init orders a caller already holds (LoadRoots without the walk).</summary>
/// <param name="pOrders">ProgramInitOrders of the index; nil yields no chains.</param>
/// <returns>Exactly what LoadRoots returns for the index those orders came from.</returns>
/// <remarks>Pure. v152 HOVERCAP: check-init's solver needs the orders AND the chains; computing the orders
/// once halves its setup (~1.1 s on the drag-lint index).</remarks>
function RootsOfOrders(const pOrders: TArray<TProgramInitOrder>): THbRoots;


/// <summary>v152 HOVERCACHE: ProgramInitOrders of the index, cached per index version in this process.</summary>
/// <param name="pStore">The project index; its DbPath keys the cache (an in-memory store is never cached).</param>
/// <param name="pStop">As ProgramInitOrders' AStop. A walk it stopped is returned PARTIAL and never cached.</param>
/// <param name="pCached">True when the answer came from the cache.</param>
/// <returns>What ProgramInitOrders(pStore, pStop) returns for that index version.</returns>
/// <remarks>The whole-index walk costs ~1.1 s on the drag-lint index, on every check-init solve; a long-running
/// engine (LSP, serve) now pays it once per index version. Thread-safe: one lock guards the cache, the walk
/// runs outside it. Keeps at most HB_CACHE_VERSIONS versions (oldest dropped first).</remarks>
function HbCachedInitOrders(const pStore: ISymbolStore; const pStop: TFunc<Boolean>;
  out pCached: Boolean): TArray<TProgramInitOrder>;

/// <summary>True when the routine is an unordered root (any escape class but hecNone).</summary>
/// <param name="pStore">The project index; must not be nil.</param>
/// <param name="pRoutineId">symbols.id of the routine.</param>
/// <returns>EscapeClassOf(...) &lt;&gt; hecNone.</returns>
/// <remarks>
/// Builds a classifier per call; a caller judging many routines keeps one THbEscapeClassifier.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: DRagLint.Query.HappensBefore.Roots.EscapeClassOf</para>
/// <para>Returns: EscapeClassOf(pStore, pRoutineId) &lt;&gt; hecNone</para>
/// <seealso cref="DRagLint.Query.HappensBefore.Roots.EscapeClassOf"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsEscaped(const pStore: ISymbolStore; pRoutineId: Int64): Boolean;  // dl:ok unused-public-symbol@4d67 -- REVIEWED 2026-11-17 v152 HBROOTS: check-init roots API for lanes HBSOLVER / HBEVORD (merge after HBROOTS); today only tests\fixtures\happens-before\roots-harness\RootsHarness.dpr calls it

/// <summary>The escape class of one routine (see THbEscapeClassifier.ClassOf).</summary>
/// <param name="pStore">The project index; must not be nil.</param>
/// <param name="pRoutineId">symbols.id of the routine.</param>
/// <returns>The first escape class that holds, or hecNone.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.Roots.IsEscaped (DRagLint.Query.HappensBefore.Roots.pas)</para>
/// <para>Calls: DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ClassOf, DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.Create</para>
/// <para>Returns: C.ClassOf(pRoutineId)</para>
/// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.ClassOf"/>
/// <seealso cref="DRagLint.Query.HappensBefore.Roots.THbEscapeClassifier.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function EscapeClassOf(const pStore: ISymbolStore; pRoutineId: Int64): THbEscapeClass;  // dl:ok unused-public-symbol@9889 -- REVIEWED 2026-11-17 v152 HBROOTS: check-init roots API for lanes HBSOLVER / HBEVORD (merge after HBROOTS); today only tests\fixtures\happens-before\roots-harness\RootsHarness.dpr calls it

/// <summary>The literal of an escape class: none, finalization, class-ctor-dtor, dfm-event,
/// message-handler, thread-execute, exported, interface-method, published, address-taken, zero-callers.</summary>
/// <param name="pClass">The escape class.</param>
/// <returns>The literal used in JSON and in --explain text.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.Receiver.TRecvSolver.OnlyAfterConstruction (DRagLint.Query.HappensBefore.Receiver.pas), DRagLint.Query.HappensBefore.Receiver.TRecvSolver.ProveCallers (DRagLint.Query.HappensBefore.Receiver.pas), DRagLint.Query.HappensBefore.TSolver.IsRoot (DRagLint.Query.HappensBefore.pas), DRagLint.Query.HappensBefore.TSolver.RootReasons (DRagLint.Query.HappensBefore.pas)</para>
/// <para>Returns: ESCAPE_CODES[pClass]</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function EscapeClassCode(pClass: THbEscapeClass): string;  // dl:ok unused-public-symbol@fe2b -- REVIEWED 2026-11-17 v152 HBROOTS: check-init roots API for lanes HBSOLVER / HBEVORD (merge after HBROOTS); today only tests\fixtures\happens-before\roots-harness\RootsHarness.dpr calls it

implementation

uses
  Winapi.Windows
, System.Diagnostics
, DRagLint.Query.Implementors
, DRagLint.Query.HappensBefore.Types
  ;

const
  /// <summary>v152 HOVERCACHE: index versions each whole-index cache keeps before it is emptied.</summary>
  HB_CACHE_VERSIONS = 8;
  ESCAPE_CODES: array[THbEscapeClass] of string = ('none', 'finalization', 'class-ctor-dtor', 'dfm-event',
    'message-handler', 'thread-execute', 'exported', 'interface-method', 'published', 'address-taken',
    'zero-callers');
  THREAD_BASE = 'TThread';
  THREAD_ENTRY = 'Execute';
  CONFIDENCE_CALLBACK = 'callback';
  REF_KIND_CALL = 'call';

function EscapeClassCode(pClass: THbEscapeClass): string;
begin
  Result:= ESCAPE_CODES[pClass];
end;

function LoadRoots(const pStore: ISymbolStore): THbRoots;
begin
  Result:= Default(THbRoots);
  if pStore = nil then Exit;
  Result:= RootsOfOrders(ProgramInitOrders(pStore));
end;

function RootsOfOrders(const pOrders: TArray<TProgramInitOrder>): THbRoots;
begin
  Result:= Default(THbRoots);
  for var O: TProgramInitOrder in pOrders do
  begin
    var C:= Default(THbRootChain);
    C.ProgramFileId:= O.ProgramFileId;
    C.ProgramName:= O.ProgramName;
    C.Unreliable:= O.Unreliable;
    C.UnreliableReason:= O.UnreliableReason;
    for var U: TProgramInitUnit in O.Units do
    begin
      if U.InitId <= 0 then Continue;
      var R:= Default(THbOrderedRoot);
      R.Kind:= hrkInitialization;
      R.SymbolId:= U.InitId;
      R.UnitName:= U.Name;
      R.FileId:= U.FileId;
      R.Display:= 'initialization of ' + U.Name;
      C.Roots:= C.Roots + [R];
    end;
    if O.ProgramBlockId > 0 then
    begin
      var R:= Default(THbOrderedRoot);
      R.Kind:= hrkProgramBlock;
      R.SymbolId:= O.ProgramBlockId;
      R.FileId:= O.ProgramFileId;
      R.Display:= 'program block of ' + O.ProgramName;
      C.Roots:= C.Roots + [R];
    end;
    Result.Chains:= Result.Chains + [C];
  end;
end;

{ v152 HOVERCACHE: the per-index-version caches of the two whole-index loads of a check-init solve. }
var
  GHbCacheLock: TObject;
  GHbOrdersCache: TDictionary<string, TArray<TProgramInitOrder>>;
  GHbAnswersCache: TDictionary<string, TArray<Int64>>;

{ 'size:lastwrite' of one file, read through a handle; '' when it cannot be opened. }
function FileVersion(const pPath: string): string;
var
  Info: TByHandleFileInformation;
begin
  Result:= '';
  var H: THandle:= CreateFile(PChar(pPath), FILE_READ_ATTRIBUTES,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if H = INVALID_HANDLE_VALUE then Exit;
  try
    if GetFileInformationByHandle(H, Info) then
      Result:= Format('%d:%d:%d:%d', [Info.nFileSizeHigh, Info.nFileSizeLow, Info.ftLastWriteTime.dwHighDateTime,
        Info.ftLastWriteTime.dwLowDateTime]);
  finally
    CloseHandle(H);
  end;
end;

{ v152 HOVERCACHE: the identity of one version of an index file -- size and last write time of the .sqlite and
  of its -wal, read through a handle (NTFS updates the directory entry late for a file another process holds
  open). '' (do not cache) for '' or a missing file; else a key that changes when a writer commits (the WAL
  grows or is rewritten) or checkpoints (the main file changes). }
function HbIndexVersionKey(const pDbPath: string): string;
begin
  Result:= '';
  if pDbPath = '' then Exit;
  var Main:= FileVersion(pDbPath);
  if Main = '' then Exit;
  Result:= LowerCase(ExpandFileName(pDbPath)) + '|' + Main + '|' + FileVersion(pDbPath + '-wal');
end;

function HbCachedInitOrders(const pStore: ISymbolStore; const pStop: TFunc<Boolean>;
  out pCached: Boolean): TArray<TProgramInitOrder>;
begin
  pCached:= False;
  var Key:= if pStore = nil then '' else HbIndexVersionKey(pStore.DbPath);
  if Key <> '' then
  begin
    TMonitor.Enter(GHbCacheLock);
    try
      pCached:= GHbOrdersCache.TryGetValue(Key, Result);
    finally
      TMonitor.Exit(GHbCacheLock);
    end;
    if pCached then Exit;
  end;
  { a walk the stop callback ended is partial: returned, never cached }
  var Stopped:= False;
  var Stop: TFunc<Boolean>:= nil;
  if Assigned(pStop) then
    Stop:= function: Boolean
      begin
        Result:= pStop();
        if Result then Stopped:= True;
      end;
  Result:= ProgramInitOrders(pStore, Stop);
  if (Key = '') or Stopped then Exit;
  TMonitor.Enter(GHbCacheLock);
  try
    if GHbOrdersCache.Count >= HB_CACHE_VERSIONS then GHbOrdersCache.Clear;
    GHbOrdersCache.AddOrSetValue(Key, Result);
  finally
    TMonitor.Exit(GHbCacheLock);
  end;
end;

{ THbEscapeClassifier }

constructor THbEscapeClassifier.Create(const pStore: ISymbolStore);
begin
  inherited Create;
  FStore:= pStore;
  FAnswers:= THashSet<Int64>.Create;
  FThreadClasses:= THashSet<string>.Create;
  FFileIds:= TDictionary<string, Int64>.Create;
end;

destructor THbEscapeClassifier.Destroy;
begin
  FFileIds.Free;
  FThreadClasses.Free;
  FAnswers.Free;
  inherited Destroy;
end;

{ Every method that answers an interface method of an interface in the index: one pass over the
  interfaces, done on the first question that needs it. }
procedure THbEscapeClassifier.LoadAnswers;
begin
  if FAnswersLoaded then Exit;
  FAnswersLoaded:= True;
  var Watch:= TStopwatch.StartNew;
  { v152 HOVERCACHE: the set is a whole-index walk (2.5-3.2 s on the drag-lint index); a long-running engine
    keeps it per index version. Only a COMPLETE walk is cached. }
  var Key:= HbIndexVersionKey(FStore.DbPath);
  if Key <> '' then
  begin
    var Ids: TArray<Int64>;
    var Hit: Boolean;
    TMonitor.Enter(GHbCacheLock);
    try
      Hit:= GHbAnswersCache.TryGetValue(Key, Ids);
    finally
      TMonitor.Exit(GHbCacheLock);
    end;
    if Hit then
    begin
      for var Id in Ids do FAnswers.Add(Id);
      HbProfileAdd('interface-answers', Watch.ElapsedMilliseconds, 'cached');
      Exit;
    end;
  end;
  for var Intf: TSymbol in FStore.FindSymbolsByKind('interface', False, MaxInt) do
  begin
    for var Member: TSymbol in FStore.FindAllChildSymbols(Intf.Id) do
    begin
      { per member, not per interface: one interface of the drag-lint index (ISymbolStore) holds hundreds }
      if Assigned(FStopCheck) and FStopCheck() then
      begin
        HbProfileAdd('interface-answers', Watch.ElapsedMilliseconds, 'stopped');
        Exit;
      end;
      if Member.Kind in [skProcedure, skFunction, skMethod] then
        for var Answer: TSymbol in ImplementingMethodsOf(FStore, Member) do
          FAnswers.Add(Answer.Id);
    end;
  end;
  HbProfileAdd('interface-answers', Watch.ElapsedMilliseconds, 'computed');
  if Key = '' then Exit;
  TMonitor.Enter(GHbCacheLock);
  try
    if GHbAnswersCache.Count >= HB_CACHE_VERSIONS then GHbAnswersCache.Clear;
    GHbAnswersCache.AddOrSetValue(Key, FAnswers.ToArray);
  finally
    TMonitor.Exit(GHbCacheLock);
  end;
end;

{ True when pName descends from TThread (the descendant set is loaded on the first question). }
function THbEscapeClassifier.IsThreadClass(const pName: string): Boolean;
begin
  if not FThreadsLoaded then
  begin
    FThreadsLoaded:= True;
    for var N: string in FStore.FindDescendantNames(THREAD_BASE) do
      FThreadClasses.Add(LowerCase(N));
  end;
  Result:= FThreadClasses.Contains(LowerCase(pName));
end;

function THbEscapeClassifier.ParentClassOf(const pSym: TSymbol): TSymbol;
begin
  Result:= Default(TSymbol);
  if pSym.ParentId <= 0 then Exit;
  var P:= FStore.GetSymbolById(pSym.ParentId);
  if P.Kind in [skClass, skForm] then Result:= P;
end;

{ files.id of an indexed path (0 when the index holds no symbol in it); cached per path. }
function THbEscapeClassifier.FileIdOf(const pPath: string): Int64;
begin
  var Key:= LowerCase(pPath);
  if FFileIds.TryGetValue(Key, Result) then Exit;
  Result:= 0;
  for var S: TSymbol in FStore.FindSymbolsByFile(pPath) do
  begin
    Result:= S.FileId;
    Break;
  end;
  FFileIds.Add(Key, Result);
end;

{ True when an `exports` clause names pSym: a REF_KIND_EXPORT ref bound to it (1.52 EXTGAPS2). Before 1.52
  the entry was a 'call' ref with a call edge and this read the clause back from the source text. }
function THbEscapeClassifier.IsExportedByClause(const pSym: TSymbol): Boolean;
begin
  Result:= False;
  for var R: TReference in FStore.FindReferencesTo(pSym.Id) do
    if SameText(R.Kind, REF_KIND_EXPORT) then Exit(True);
end;

{ True when pSym returns a value: a function, or a method whose signature ends in `: <type>` after its
  parameter list. }
function ReturnsValue(const pSym: TSymbol): Boolean;
begin
  if pSym.Kind = skFunction then Exit(True);
  var Tail:= pSym.Signature;
  var P:= LastDelimiter(')', Tail);
  if P > 0 then Tail:= Copy(Tail, P + 1, MaxInt);
  Result:= Tail.Contains(':');
end;

{ True when the edge at the call site is a real call of pSym: a `call` ref sits there, or pSym returns a
  value (a parameterless function named in an expression is a call; the index gives it a read /
  member-access ref, the same shape as a function named as a value -- see the unit's blind spots).
  False when a procedure's edge sits on another ref kind (it is named as a value, e.g.
  `H.OnEvt := H.Handler`) or when no ref is found there (unknown is not a proven call). }
function THbEscapeClassifier.IsCallRefAt(const pSym: TSymbol; const pCaller: TResolvedCaller): Boolean;
begin
  Result:= False;
  if ReturnsValue(pSym) then Exit(True);
  var Fid:= FileIdOf(pCaller.FullPath);
  if Fid <= 0 then Exit;
  for var R: TReference in FStore.FindRefsNamingInFiles([Fid], [LowerCase(pSym.Name)]) do
    if (R.StartLine = pCaller.CallSiteLine) and (R.StartCol = pCaller.CallSiteCol) and (R.SymbolId = pSym.Id)
      and SameText(R.Kind, REF_KIND_CALL) then Exit(True);
end;

{ True when some site calls pSym for real. pAddressTaken: some site names it as a value (a callback edge,
  a bound non-call ref, or an edge on a non-call ref). pExported: an `exports` clause names it. }
function THbEscapeClassifier.ScanCallers(const pSym: TSymbol; out pAddressTaken, pExported: Boolean): Boolean;
begin
  Result:= False;
  pAddressTaken:= False;
  pExported:= IsExportedByClause(pSym);
  for var R: TResolvedCaller in FStore.FindResolvedCallers(pSym.Id) do
    if (R.Mode <> '') or SameText(R.Confidence, CONFIDENCE_CALLBACK) then pAddressTaken:= True
    else if IsCallRefAt(pSym, R) then Result:= True
    else pAddressTaken:= True;
end;

function HasWord(const pList, pWord: string): Boolean;
begin
  Result:= False;
  for var W: string in pList.Split([' ']) do
    if SameText(W, pWord) then Exit(True);
end;

{ The classes that need only the symbol row and its facts: finalization, class ctor/dtor, DFM event,
  message handler, then MemberClassOf. }
function THbEscapeClassifier.DeclaredClassOf(const pSym: TSymbol): THbEscapeClass;
begin
  Result:= if pSym.Kind = skFinalization then hecFinalization
    else if pSym.IsClassMethod and (pSym.Kind in [skConstructor, skDestructor]) then hecClassCtorDtor
    else if FStore.GetSymbolFacts(pSym.Id).DfmEvent <> '' then hecDfmEvent
    else if HasWord(pSym.Directives, 'message') then hecMessageHandler
    else MemberClassOf(pSym);
end;

{ A plain routine: exported by directive or not escaped by declaration. A method: thread Execute,
  interface answer, published (the unlabelled leading section counts as published). }
function THbEscapeClassifier.MemberClassOf(const pSym: TSymbol): THbEscapeClass;
begin
  var Cls:= ParentClassOf(pSym);
  if Cls.Id <= 0 then Exit(if HasWord(pSym.Directives, 'export') then hecExported else hecNone);
  if SameText(pSym.Name, THREAD_ENTRY) and IsThreadClass(Cls.Name) then Exit(hecThreadExecute);
  LoadAnswers;
  Result:= if FAnswers.Contains(pSym.Id) then hecInterfaceMethod
    else if SameText(Trim(pSym.Modifiers), 'published') or not pSym.VisExplicit then hecPublished
    else hecNone;
end;

function THbEscapeClassifier.ClassOf(pRoutineId: Int64): THbEscapeClass;
var
  AddressTaken, Exported: Boolean;
begin
  Result:= hecNone;
  var S:= FStore.GetSymbolById(pRoutineId);
  if (S.Id <= 0) or (S.Kind not in [skFinalization, skProcedure, skFunction, skMethod, skConstructor, skDestructor]) then
    Exit;
  Result:= DeclaredClassOf(S);
  if Result <> hecNone then Exit;
  var Called:= ScanCallers(S, AddressTaken, Exported);
  if Exported then Result:= hecExported
  else if AddressTaken then Result:= hecAddressTaken
  { An override is reached through its bases' callers (spec 5.2): not a root of its own. }
  else if not Called and (Length(FStore.FindDispatchLinks(S.Id, {AToBases=}True)) = 0) then Result:= hecZeroCallers;
end;

function EscapeClassOf(const pStore: ISymbolStore; pRoutineId: Int64): THbEscapeClass;
begin
  var C:= THbEscapeClassifier.Create(pStore);
  try
    Result:= C.ClassOf(pRoutineId);
  finally
    C.Free;
  end;
end;

function IsEscaped(const pStore: ISymbolStore; pRoutineId: Int64): Boolean;
begin
  Result:= EscapeClassOf(pStore, pRoutineId) <> hecNone;
end;

initialization
  GHbCacheLock:= TObject.Create;
  GHbOrdersCache:= TDictionary<string, TArray<TProgramInitOrder>>.Create;
  GHbAnswersCache:= TDictionary<string, TArray<Int64>>.Create;

finalization
  GHbAnswersCache.Free;
  GHbOrdersCache.Free;
  GHbCacheLock.Free;

end.
