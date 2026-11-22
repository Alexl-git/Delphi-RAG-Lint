/// <summary>Purity v2: the `purity` resolve stage. Computes one effect summary
/// per routine with a body from rows the index already holds plus the source
/// text it points at, runs the greatest-fixpoint worklist over call_edges, and
/// writes symbol_facts.effect_free / effect_summary / effect_witness.</summary>
/// <remarks>Resolve surface (tests\resolver-surface.txt): changing anything
/// here changes what is WRITTEN and bills DRAGLINT_RESOLVER_VERSION, never the
/// extractor. Whole-DB, except after call-target passes that all ran SCOPED on
/// the same store instance (1.52.1 INCR18 step 4): then only the routines those
/// passes can have moved, and their transitive callers, are re-derived, and
/// every other stored verdict is a constant of the fixpoint (DetermineScope).
/// DRAGLINT_NO_SCOPED_PURITY=1 forces the whole pass. A witness is canonical:
/// re-derived per strongly connected component after the fixpoint, so it is the
/// same text whole or scoped (CanonicalWitnesses).
/// Source is read at most once per file. Prints `resolve: purity -- ...` on
/// stdout (and `resolve: purity scope -- ...` when a scope was offered), the
/// per-phase split on stderr under DRAGLINT_PROFILE.
/// The lattice, the axiom and built-in tables, the argument lexer, the body
/// scanner and the callee -> caller translation live in
/// DRagLint.Analysis.Purity; this unit only drives them against the store.</remarks>
unit DRagLint.Analysis.PurityStage;  // dl:ok unit-too-large@becf -- measured 2361 lines (limit 2000); a unit split changes the uses graph, outside the mechanical SLZ batch -- SLZ-S10 2026-11-22

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DRagLint.Core.Interfaces;

type
  /// <summary>What one run counted -- printed on the `resolve: purity` line and
  /// returned for tests.</summary>
  /// <remarks>
  /// <c>Rounds</c> is the number of worklist PASSES: the visits the
  /// fixpoint made divided by the routine count, rounded up. <c>TopUnbound</c>
  /// holds the ten commonest unbound callee names as <c>'name (count)'</c>,
  /// lowercased, commonest first.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Analysis.PurityStage.pas) ?, DRagLint.Analysis.PurityStage.TPurityRun.Execute (DRagLint.Analysis.PurityStage.pas), DRagLint.Analysis.PurityStage.TPurityStage.Run (DRagLint.Analysis.PurityStage.pas) ?</para>
  /// <para>Used in units: DRagLint.Analysis.PurityStage</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TPurityStats = record
    Routines       : Integer;
    EffectFree     : Integer;
    UnboundCalls   : Integer;   // non-axiom, non-built-in call refs with no call_edges row
    UnlexableCalls : Integer;   // spec 3.4: argument list could not be lexed with confidence
    StaleFiles     : Integer;   // on-disk mtime <> files.mtime_unix
    GatedIncomplete: Integer;   // spec 7.3 gate fired
    Rounds         : Integer;   // worklist passes until stable
    TopUnbound     : TArray<string>;   // 'name (count)', ten commonest
  end;

  /// <summary>The stage. Stateless from the caller's side: Run builds what it
  /// needs, writes, and frees.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Analysis.PurityStage.TPurityRun.CallRef (DRagLint.Analysis.PurityStage.pas), DRagLint.Analysis.PurityStage.TPurityRun.LibCallee (DRagLint.Analysis.PurityStage.pas), DRagLint.Analysis.PurityStage.TPurityRun.Report (DRagLint.Analysis.PurityStage.pas), DRagLint.CLI.RunPurityStage (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.Analysis.PurityStage, DRagLint.CLI</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TPurityStage = class
  public
    /// <summary>Runs the purity pass -- scoped to what the scoped call-target
    /// passes on AStore can have moved (ISymbolStore.LastCallsScope), else
    /// whole-DB -- and persists the verdicts.</summary>
    /// <param name="AStore">An open, migrated, writable store. PutEffectFacts
    /// opens its own transaction, so no file transaction may be open.</param>
    /// <returns>Counts for the summary line.</returns>
    /// <exception cref="EInvalidOperation">Propagated from PutEffectFacts when
    /// the store has no effect_* columns (a read-only open).</exception>
    /// <remarks>
    /// Every routine that owns a symbol_facts row with body_loc &gt; 0
    /// receives a verdict; a routine in a file whose on-disk mtime no longer
    /// matches files.mtime_unix is `?` with the witness
    /// <c>source changed since indexing</c> (plan ruling 7); a routine in a file
    /// that holds no read/write/member-access ref at all (a shallow parse:
    /// library mode or --shallow) is `?` with the witness
    /// <c>no usage facts (shallow parse)</c> unless an earlier witness already
    /// names a concrete effect (146 g1). Complexity: one
    /// pass over the refs of every file plus the fixpoint, which visits each
    /// routine once per change of a callee it depends on.
    /// A scoped run re-derives the routines of the rewritten files, the
    /// routines around a ref whose binding moved, the methods of a class whose
    /// own or inherited members can have moved, routines with no verdict, and
    /// every transitive caller of those; it writes only their rows. It is taken
    /// only when schema_meta <c>purity_inputs</c> equals this run's stamp of the
    /// inputs no scope describes (the procedural type names, the library
    /// effects store); the stamp is written after every run. A file outside the
    /// scope is not stamped against the disk.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas) ?, DRagLint.CLI.RunPurityStage (DRagLint.CLI.pas)</para>
    /// <para>Calls: DRagLint.Analysis.PurityStage.TPurityRun.Create, DRagLint.Analysis.PurityStage.TPurityRun.Execute</para>
    /// <para>Returns: R.Execute</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Analysis.PurityStage.TPurityRun.Create"/>
    /// <seealso cref="DRagLint.Analysis.PurityStage.TPurityRun.Execute"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Run(const AStore: ISymbolStore): TPurityStats; static;
    /// <summary>E-BIND-LIB-EFFECTS: the library store whose summaries library-bound calls take.
    /// nil means a library-bound call is an unbound `?`. Set, a call whose stored external_target
    /// names a non-virtual library routine takes that routine's stored summary, `h` excluded
    /// (a library routine freeing its own temporaries is not an effect on the caller).</summary>
    /// <remarks>Every library summary also keeps `?`, unless LibraryEffectsTrustFree: the
    /// library is parsed shallow (no read/write refs), so its effect_free = 1 proves nothing and
    /// a project routine never becomes effect-free through a library callee. A virtual or
    /// interface member stays `?` (the override is not the body we see). The CLI sets it before
    /// each Run (by default from the DB's external_stores) and clears it after; read-only use of
    /// the store, same thread. Measured on four project DBs: no rule count changed
    /// (tests\autotest\run_v151_LIBFX_lib_effects.ps1 holds the behaviour).</remarks>
    class var LibraryEffects: ISymbolStore;
    /// <summary>Takes a library verdict at face value, effect_free = 1 included. Measurement
    /// only: it is unsound on a shallow library (TDataSet.Open reads effect-free).</summary>
    class var LibraryEffectsTrustFree: Boolean;
    /// <summary>INCR18 step 4: identifies LibraryEffects for the scoped run's input stamp --
    /// the caller's choice of text (the CLI: path, size and write time of the library file and
    /// its -wal). '' when no library is attached. A different text between two runs sends the
    /// later one to the whole database.</summary>
    class var LibraryEffectsStamp: string;
  end;

implementation

uses
  DRagLint.Core.Model,
  DRagLint.Analysis.Purity,
  System.Diagnostics,
  System.Generics.Defaults,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  System.Hash,
  DRagLint.Core.ControlChannel, { BeatStep / BeatProgress: the stage's progress }
  DRagLint.Core.FileTime,
  DRagLint.Index.LibraryOracle; { EXTERNAL_KIND_PARENLESS_CALL (1.51.1 B04) }

const
  KIND_TEXT_TYPE      = 'type';
  /// <summary>How many unbound callee names the summary line lists.</summary>
  TOP_UNBOUND_COUNT = 10;
  PERCENT_SCALE     = 100;
  /// <summary>Budget for the cached source lines, in CHARACTERS (so ~64 MB of
  /// UTF-16). The scan reads each file once and the lazy lex re-reads a file
  /// that has since been evicted; the budget bounds a structure that otherwise
  /// grows with the corpus's total SOURCE SIZE -- measured at ~800 MB of a
  /// 2.9 GB peak on the 7,001-file Win64 library index.</summary>
  BYTES_PER_MB            = 1024 * 1024;
  PURITY_LINE_CACHE_CHARS = 32 * BYTES_PER_MB;

  KIND_TEXT_PARAM     = 'param';
  KIND_TEXT_LOCAL_VAR = 'local_var';
  REF_KIND_READ       = 'read';
  REF_KIND_WRITE      = 'write';
  REF_KIND_MEMBER     = 'member-access';
  MEMBER_MODE_WRITE   = 'write';
  MEMBER_MODE_READ    = 'read';
  ANCESTOR_INTERFACE  = 'interface';
  NAME_RESULT         = 'result';
  NAME_SELF           = 'Self';
  NAME_ADDR           = 'Addr';
  WORD_INHERITED      = 'inherited';
  TOP_NONE            = 'none';
  { INCR18 step 4: set to anything, the stage re-derives every routine even after scoped
    call-target passes -- the A/B switch the scoped-equals-whole test runs on. }
  ENV_NO_SCOPED_PURITY = 'DRAGLINT_NO_SCOPED_PURITY';
  { TEST SEAM (INCR18 step 4): = 1, a scoped run re-derives its seeds only and does NOT close
    them over their callers -- a deliberately WRONG scope, the positive control of
    tests\autotest\run_v1521_INCR18.ps1 (a caller keeps a stale verdict). Never a shipping value. }
  ENV_TEST_SEEDS_ONLY  = 'DRAGLINT_TEST_PURITY_SEEDS_ONLY';
  { schema_meta key: the stamp of the inputs no call-target scope describes (InputsStamp). }
  META_PURITY_INPUTS   = 'purity_inputs';
  { CollectContextSymbols: above this many enclosing-routine parents, read both kinds whole
    instead of one child query per parent. }
  CONTEXT_PARENTS_BULK = 2000;
  { DetermineScope: past this many per-routine caller lookups, read the whole reverse call
    graph once instead. }
  CALLERS_BULK_AFTER   = 1000;

  WITNESS_STALE           = 'source changed since indexing';
  WITNESS_WITH            = 'with statement';
  WITNESS_GATED           = 'local table incomplete (var declarations without local_var rows)';
  WITNESS_INHERITED_OUT   = 'inherited (ancestor method outside this DB)';
  WITNESS_MUTATES_CAPPED  = 'mutates more parameters than recorded';
  WITNESS_NO_FACTS        = 'no facts for callee';
  WITNESS_VIRTUAL         = 'virtual/interface dispatch';
  WITNESS_NOT_ROUTINE     = 'target is not a routine';
  /// <summary>146 g1: the file holds no read/write/member-access refs at all,
  /// the mark of a shallow (library-mode / --shallow) parse. Its bodies were
  /// never recorded, so no routine in it can be proven effect-free.</summary>
  WITNESS_SHALLOW         = 'no usage facts (shallow parse)';

  ROUTINE_KINDS = [skProcedure, skFunction, skMethod, skConstructor, skDestructor];
  CAST_KINDS    = [skClass, skInterface, skRecord, skEnum, skTypeAlias];
  CLASS_KINDS   = [skClass, skRecord, skInterface, skForm];
  FIELD_KINDS   = [skField, skComponent];

type
  /// <summary>One library routine as E-BIND-LIB-EFFECTS sees it: its joined verdict.</summary>
  TLibCallee = record
    Usable   : Boolean;
    IsMember : Boolean;
    IsCtor   : Boolean;
    OwnerName: string;
    Sum      : TEffectSummary;
  end;

  /// <summary>One call site of a caller that the fixpoint folds in: a bound
  /// routine (TargetId) or a built-in (IsBuiltin). Arguments are lexed LAZILY,
  /// the first time the callee's summary carries a p&lt;k&gt; (P7), and cached.</summary>
  TCalleeUse = record
    TargetId : Int64;
    IsBuiltin: Boolean;
    Builtin  : TEffectSummary;
    Name     : string;
    Receiver : TArgInfo;
    FileId   : Int64;
    Line     : Integer;    // 0 = nothing to lex (bare inherited; args already known)
    ColAfter : Integer;
    ArgsLexed: Boolean;
    ArgsKnown: Boolean;
    Args     : TArray<TArgInfo>;
  end;

  /// <summary>The caller-side names one routine classifies against. The sets
  /// are owned by TPurityRun (FOwnedSets / FOwnedMaps), never by this record.</summary>
  TRoutineCtx = record
    Locals    : TNameSet;         // own + enclosing routines' locals (classification)
    OwnLocals : TNameSet;         // own rows only (the spec 7.3 gate)
    Params    : TParamMap;
    ParamNames: TArray<string>;   // by ordinal, as declared
    Fields    : TNameSet;         // own class + ancestors; the empty set for a free routine
    Props     : TNameSet;         // own class + ancestors
    Escaping  : TNameSet;         // nil until the first escaping local
    ClassId   : Int64;
  end;
  TPurityRun = class  // dl:ok god-class@13c7, high-response@13c7 -- REVIEWED 2026-09-22: the fields ARE the loaded index tables (routines, facts, edges, members, params, locals, fields, stamps, the bounded line cache) and the methods are the five phases of ONE pass over them: load, contexts, scan, fixpoint, write. Splitting them would give the fixpoint a second owner of the same tables for no behavioural gain, and the model (lattice, lexer, body scanner) already lives in DRagLint.Analysis.Purity.
  private
    FStore       : ISymbolStore;
    FRoutines    : TArray<TSymbol>;
    FIndexOf     : TDictionary<Int64, Integer>;
    FChildrenOf  : TDictionary<Int64, TList<Integer>>;   // routine id -> nested routine indexes
    FFacts       : TDictionary<Int64, TSymbolFacts>;
    FEdges       : TDictionary<Int64, TCallEdge>;
    FMembers     : TDictionary<Int64, TCallEdge>;
    FParamsOf    : TDictionary<Int64, TParamMap>;
    FParamNames  : TDictionary<Int64, TArray<string>>;
    FLocalsOf    : TDictionary<Int64, TNameSet>;
    FFieldsOf    : TDictionary<Int64, TNameSet>;
    FOwnFieldsOf : TDictionary<Int64, TNameSet>;
    FPropsOf     : TDictionary<Int64, TNameSet>;
    FAncestorsOf : TDictionary<Int64, TArray<TTypeAncestor>>;
    FKidFields   : TDictionary<Int64, TArray<string>>;   // ClassMemberNames: own field names per class
    FKidProps    : TDictionary<Int64, TArray<string>>;   // ClassMemberNames: own property names per class
    FStamps      : TDictionary<string, Int64>;
    { The line cache is BOUNDED (PURITY_LINE_CACHE_CHARS). Holding every file's
      lines for the whole run cost ~800 MB of the 2.9 GB peak measured on the
      7,001-file Win64 library index (295 MB of source, one Delphi string per
      line); the stage reads each file once during the scan and needs it again
      only for the lazy argument lex, which re-reads on a miss. }
    FLines       : TDictionary<Int64, TArray<string>>;
    FLineOrder   : TQueue<Int64>;
    FLineChars   : Int64;
    FLineReReads : Integer;
    FSymCache    : TDictionary<Int64, TSymbol>;
    FOwnedSets   : TObjectList<TNameSet>;
    FOwnedMaps   : TObjectList<TParamMap>;
    FEmptySet    : TNameSet;
    FEmptyMap    : TParamMap;
    FCtx         : TArray<TRoutineCtx>;
    FLocal       : TArray<TEffectSummary>;
    FSummary     : TArray<TEffectSummary>;
    FUses        : TArray<TArray<TCalleeUse>>;
    FUnbound     : TDictionary<string, Integer>;
    FLibCallees  : TDictionary<string, TLibCallee>;
    FLibBound    : Integer;
    FLibRoutine  : Int64;
    FLibTargets  : TDictionary<Int64, string>;
    FProcTypes   : TNameSet;   // lower-case names of plain procedural types, not reference-to
    { INCR18 step 4: the routines this run re-derives. Every routine when the run is not
      scoped; otherwise the closure DetermineScope computes, and every other routine keeps its
      stored verdict as a constant of the fixpoint. }
    FScoped      : Boolean;
    FScopeNote   : string;                     // why a scope that was offered was not taken; '' otherwise
    FInScope     : TArray<Boolean>;
    FScopeCount  : Integer;
    FScopeFiles  : Integer;
    FClassOf     : TArray<Int64>;              // ClassIdOf, per routine index
    FComp        : TArray<Integer>;            // CanonicalWitnesses: component per routine
    FContrib     : TArray<TArray<Boolean>>;    // CanonicalWitnesses: the use adds anything
    FRank        : TArray<Integer>;            // CanonicalWitnesses: distance to a source
    FInputsNow   : string;                     // InputsStamp of this run
    FStats       : TPurityStats;
    FVisits      : Integer;
    FLexTicks    : Int64;
    FTkFile, FTkRefs, FTkBody, FTkEsc, FTkRefLoop, FTkSym, FSymMiss, FSymLookups, FTkPreload, FPreloadRows: Int64;   { scan sub-phases, DRAGLINT_PROFILE only }
    function  NewSet: TNameSet;
    function  NewMap: TParamMap;
    function  SymbolById(AId: Int64): TSymbol;
    function  ClassIdOf(const ASym: TSymbol): Int64;
    function  AncestorsOf(AClassId: Int64): TArray<TTypeAncestor>;
    procedure ClassMemberNames(AClassId: Int64; out AFields, AProps: TArray<string>);
    function  FieldsOfClass(AClassId: Int64): TNameSet;
    function  PropsOfClass(AClassId: Int64): TNameSet;
    function  DeclaringAncestorOfField(AClassId: Int64; const AName: string): string;
    function  ReadFileLines(AFileId: Int64; out ALines: TArray<string>): Boolean;
    procedure CacheLines(AFileId: Int64; const ALines: TArray<string>);
    function  LinesOf(AFileId: Int64; out ALines: TArray<string>): Boolean;
    function  IsBound(const ARef: TReference): Boolean;
    function  IsProcTypedTarget(ATargetId: Int64): Boolean;
    function  IsImplicitProcCall(const ALines: TArray<string>; const ARef: TReference): Boolean;
    function  Classify(AIndex: Integer; const AText: string): TArgInfo;
    function  SelfReceiver: TArgInfo;
    function  ReceiverOf(AIndex: Integer; const AText: string; const ATarget: TSymbol; AIsInherited: Boolean): TArgInfo;
    function  PrecededByInherited(const ALines: TArray<string>; const ARef: TReference): Boolean;
    function  EnclosingCall(const ALine: string; ACol: Integer; ACalls: TList<TReference>; ALineNo: Integer): Integer;
    procedure MarkEscaping(AIndex: Integer; const AName: string);
    procedure Load;
    function  InputsStamp: string;
    procedure DetermineScope;
    function  StoredSummary(AIndex: Integer): TEffectSummary;
    procedure ApplyUse(AIndex, AUse: Integer; var ASum: TEffectSummary; var AChanged: Boolean);
    function  InScopeTarget(AIndex, AUse: Integer; out ATarget: Integer): Boolean;
    function  SameComp(AIndex, AUse: Integer): Boolean;
    procedure ComputeComponents;
    procedure ComputeSourceRanks;
    function  CanonicalSummaryOf(AIndex: Integer): TEffectSummary;
    procedure CanonicalWitnesses;
    procedure LoadBindings;
    procedure CollectContextSymbols(out AParams, ALocals: TArray<TSymbol>);
    procedure BuildContexts;
    procedure ScanFiles;
    procedure ScanRoutine(AIndex: Integer; const ALines: TArray<string>; ARefs: TList<TReference>; AShallow: Boolean);
    function  ScanBody(AIndex: Integer; const ALines: TArray<string>): TBodyScan;
    procedure ApplyFacts(AIndex: Integer; const AFacts: TSymbolFacts; var ASum: TEffectSummary; var AChanged: Boolean);
    procedure AddInheritedUse(AIndex: Integer; var ASum: TEffectSummary; var AChanged: Boolean; AUses: TList<TCalleeUse>);
    procedure CollectEscapes(AIndex: Integer; const ALines: TArray<string>; ARefs: TList<TReference>);
    function  IsResultByName(AIndex: Integer; const AKey: string): Boolean;
    procedure NonLocalWrite(AIndex: Integer; const ARef: TReference; var ASum: TEffectSummary; var AChanged: Boolean);
    procedure BoundCall(AIndex: Integer; const ARef: TReference; ATargetId: Int64; const ALines: TArray<string>;
      var ASum: TEffectSummary; var AChanged: Boolean; AUses: TList<TCalleeUse>);
      function LibCallee(const AQName: string): TLibCallee;
    function LibraryCall(AIndex: Integer; const ARef: TReference; AUses: TList<TCalleeUse>): Boolean;
    procedure CallRef(AIndex: Integer; const ARef: TReference; const ALines: TArray<string>;
      var ASum: TEffectSummary; var AChanged: Boolean; AUses: TList<TCalleeUse>);
    procedure MemberRef(AIndex: Integer; const ARef: TReference; const ALines: TArray<string>;
      var ASum: TEffectSummary; var AChanged: Boolean; AUses: TList<TCalleeUse>);
    procedure MemberWrite(AIndex: Integer; const AReceiver, AName: string; var ASum: TEffectSummary; var AChanged: Boolean);
    procedure LexUse(AIndex, AUse: Integer);
    procedure FixPoint;
    procedure WriteVerdicts;
    procedure Report(ALoad, AScope, AScan, AFix, AWrite: Double);
  public
    constructor Create(const AStore: ISymbolStore);
    destructor Destroy; override;
    function Execute: TPurityStats;
  end;

{ -------------------------------------------------------------- small helpers }

function LowerKey(const AName: string): string;
begin
  Result:= LowerCase(Trim(AName));
end;

function SecondsOf(const ASw: TStopwatch): Double;
begin
  Result:= ASw.ElapsedMilliseconds / MSecsPerSec;
end;

{ ---------------------------------------------------------------- TPurityRun }

constructor TPurityRun.Create(const AStore: ISymbolStore);
begin
  inherited Create;
  FStore      := AStore;
  FIndexOf    := TDictionary<Int64, Integer>.Create;
  FChildrenOf := TObjectDictionary<Int64, TList<Integer>>.Create([doOwnsValues]);
  FFacts      := TDictionary<Int64, TSymbolFacts>.Create;
  FEdges      := TDictionary<Int64, TCallEdge>.Create;
  FMembers    := TDictionary<Int64, TCallEdge>.Create;
  FParamsOf   := TDictionary<Int64, TParamMap>.Create;
  FParamNames := TDictionary<Int64, TArray<string>>.Create;
  FLocalsOf   := TDictionary<Int64, TNameSet>.Create;
  FFieldsOf   := TDictionary<Int64, TNameSet>.Create;
  FOwnFieldsOf:= TDictionary<Int64, TNameSet>.Create;
  FPropsOf    := TDictionary<Int64, TNameSet>.Create;
  FAncestorsOf:= TDictionary<Int64, TArray<TTypeAncestor>>.Create;
  FKidFields  := TDictionary<Int64, TArray<string>>.Create;
  FKidProps   := TDictionary<Int64, TArray<string>>.Create;
  FStamps     := TDictionary<string, Int64>.Create(TIStringComparer.Ordinal);
  FLines      := TDictionary<Int64, TArray<string>>.Create;
  FLineOrder  := TQueue<Int64>.Create;
  FSymCache   := TDictionary<Int64, TSymbol>.Create;
  FOwnedSets  := TObjectList<TNameSet>.Create(True);
  FOwnedMaps  := TObjectList<TParamMap>.Create(True);
  FUnbound    := TDictionary<string, Integer>.Create;
  FLibCallees := TDictionary<string, TLibCallee>.Create;
  FLibTargets := TDictionary<Int64, string>.Create;
  FProcTypes  := NewSet;
  FEmptySet   := NewSet;
  FEmptyMap   := NewMap;
end;

destructor TPurityRun.Destroy;
begin
  FProcTypes := nil;
  FLibTargets.Free;
  FLibCallees.Free;
  FUnbound.Free;
  FOwnedMaps.Free;
  FOwnedSets.Free;
  FSymCache.Free;
  FLineOrder.Free;
  FLines.Free;
  FStamps.Free;
  FKidProps.Free;
  FKidFields.Free;
  FAncestorsOf.Free;
  FPropsOf.Free;
  FOwnFieldsOf.Free;
  FFieldsOf.Free;
  FLocalsOf.Free;
  FParamNames.Free;
  FParamsOf.Free;
  FMembers.Free;
  FEdges.Free;
  FFacts.Free;
  FChildrenOf.Free;
  FIndexOf.Free;
  inherited Destroy;
end;

function TPurityRun.NewSet: TNameSet;
begin
  Result:= TNameSet.Create;
  FOwnedSets.Add(Result);
end;

function TPurityRun.NewMap: TParamMap;
begin
  Result:= TParamMap.Create;
  FOwnedMaps.Add(Result);
end;

function TPurityRun.SymbolById(AId: Int64): TSymbol;
begin
  if AId = 0 then Exit(Default(TSymbol));
  Inc(FSymLookups);
  if not FSymCache.TryGetValue(AId, Result) then
  begin
    var Tk0: Int64:= TStopwatch.GetTimeStamp;
    Result:= FStore.GetSymbolById(AId);
    FSymCache.Add(AId, Result);
    Inc(FTkSym, TStopwatch.GetTimeStamp - Tk0);
    Inc(FSymMiss);
  end;
end;

{ The class a routine belongs to: its parent, or -- for a nested routine -- the
  first non-routine ancestor. 0 for a free routine. }
function TPurityRun.ClassIdOf(const ASym: TSymbol): Int64;
var
  P: TSymbol;
begin
  Result:= 0;
  P:= SymbolById(ASym.ParentId);
  while (P.Id > 0) and (P.Kind in ROUTINE_KINDS) do
    P:= SymbolById(P.ParentId);
  if (P.Id > 0) and (P.Kind in CLASS_KINDS) then Result:= P.Id;
end;

function TPurityRun.AncestorsOf(AClassId: Int64): TArray<TTypeAncestor>;
begin
  if not FAncestorsOf.TryGetValue(AClassId, Result) then
  begin
    Result:= FStore.GetTransitiveAncestors(AClassId);
    FAncestorsOf.Add(AClassId, Result);
  end;
end;

{ A class's own field and property names, read ONCE per class (IDXPERF P2 PURITYLOAD).
  FieldsOfClass and PropsOfClass each walk the class AND every resolved ancestor, so without
  this the store was asked for one base class's children twice per descendant -- on a library
  index (every VCL control under TControl) that is the 8 of 11.5 minutes the stage spent in
  "purity load". Only the lowercased names are kept, not the rows: the sets built from them
  are the same sets as before. }
procedure TPurityRun.ClassMemberNames(AClassId: Int64; out AFields, AProps: TArray<string>);
var
  F, P: TList<string>;
begin
  if FKidFields.TryGetValue(AClassId, AFields) then
  begin
    if not FKidProps.TryGetValue(AClassId, AProps) then AProps:= nil;   { both are added together below }
    Exit;
  end;
  F:= TList<string>.Create;
  P:= TList<string>.Create;
  try
    for var C in FStore.FindAllChildSymbols(AClassId) do
      if C.Kind in FIELD_KINDS then F.Add(LowerKey(C.Name))
      else if C.Kind = skProperty then P.Add(LowerKey(C.Name));
    AFields:= F.ToArray;
    AProps := P.ToArray;
  finally
    P.Free;
    F.Free;
  end;
  FKidFields.Add(AClassId, AFields);
  FKidProps.Add(AClassId, AProps);
end;

{ Own fields plus every resolved ancestor's, cached per class. }
function TPurityRun.FieldsOfClass(AClassId: Int64): TNameSet;
var
  Own          : TNameSet;
  Fields, Props: TArray<string>;
begin
  if AClassId = 0 then Exit(FEmptySet);
  if FFieldsOf.TryGetValue(AClassId, Result) then Exit;
  ClassMemberNames(AClassId, Fields, Props);
  Own:= NewSet;
  for var K in Fields do Own.AddOrSetValue(K, True);
  FOwnFieldsOf.Add(AClassId, Own);
  Result:= NewSet;
  for var K in Fields do Result.AddOrSetValue(K, True);
  for var Anc in AncestorsOf(AClassId) do
    if Anc.Resolved then
    begin
      ClassMemberNames(Anc.SymbolId, Fields, Props);
      for var K in Fields do Result.AddOrSetValue(K, True);
    end;
  FFieldsOf.Add(AClassId, Result);
end;

function TPurityRun.PropsOfClass(AClassId: Int64): TNameSet;
var
  Fields, Props: TArray<string>;
begin
  if AClassId = 0 then Exit(FEmptySet);
  if FPropsOf.TryGetValue(AClassId, Result) then Exit;
  ClassMemberNames(AClassId, Fields, Props);
  Result:= NewSet;
  for var K in Props do Result.AddOrSetValue(K, True);
  for var Anc in AncestorsOf(AClassId) do
    if Anc.Resolved then
    begin
      ClassMemberNames(Anc.SymbolId, Fields, Props);
      for var K in Props do Result.AddOrSetValue(K, True);
    end;
  FPropsOf.Add(AClassId, Result);
end;

{ '' when AName is one of the class's OWN fields (or nothing is known);
  otherwise the name of the ancestor that declares it (acceptance 22). }
function TPurityRun.DeclaringAncestorOfField(AClassId: Int64; const AName: string): string;
var
  Own: TNameSet;
  S  : TSymbol;
begin
  Result:= '';
  if AClassId = 0 then Exit;
  FieldsOfClass(AClassId);   { fills FOwnFieldsOf as a side effect }
  if FOwnFieldsOf.TryGetValue(AClassId, Own) and Own.ContainsKey(LowerKey(AName)) then Exit;
  for var Anc in AncestorsOf(AClassId) do
    if Anc.Resolved then
    begin
      S:= FStore.FindChildSymbolByName(Anc.SymbolId, AName);
      if (S.Id > 0) and (S.Kind in FIELD_KINDS) then
        Exit(if Anc.ResolvedName <> '' then Anc.ResolvedName else Anc.Name);
    end;
end;

{ Reads one indexed file's lines. False when it cannot be read -- the caller
  decides what that means (the scan treats it as stale; the lexer as unlexable). }
function TPurityRun.ReadFileLines(AFileId: Int64; out ALines: TArray<string>): Boolean;
begin
  ALines:= nil;
  try
    ALines:= TFile.ReadAllLines(FStore.GetFilePath(AFileId), TEncoding.ANSI);
    Result:= True;
  except
    { Both callers have a defined answer for "could not read" -- the scan treats
      the file as stale, the lexer as unlexable -- and each RECORDS it, so the
      condition is reported rather than swallowed; re-raising would fail a
      whole-DB pass over one unreadable file. }
    on E: Exception do Result:= False;
  end;
end;

{ Caches one file's lines and evicts the OLDEST entries until the character
  budget holds. The newest entry is never evicted: the scan is mid-file in it. }
procedure TPurityRun.CacheLines(AFileId: Int64; const ALines: TArray<string>);
var
  Chars: Int64;
  Old  : Int64;
  Gone : TArray<string>;
begin
  if FLines.ContainsKey(AFileId) then Exit;
  Chars:= 0;
  for var L in ALines do Inc(Chars, Length(L));
  FLines.Add(AFileId, ALines);
  FLineOrder.Enqueue(AFileId);
  Inc(FLineChars, Chars);
  while (FLineChars > PURITY_LINE_CACHE_CHARS) and (FLineOrder.Count > 1) do
  begin
    Old:= FLineOrder.Dequeue;
    if FLines.TryGetValue(Old, Gone) then
    begin
      for var L in Gone do Dec(FLineChars, Length(L));
      FLines.Remove(Old);
    end;
  end;
end;

{ The lines of AFileId, from the cache or re-read from disk. }
function TPurityRun.LinesOf(AFileId: Int64; out ALines: TArray<string>): Boolean;
begin
  if FLines.TryGetValue(AFileId, ALines) then Exit(True);
  Result:= ReadFileLines(AFileId, ALines);
  if Result then
  begin
    Inc(FLineReReads);
    CacheLines(AFileId, ALines);
  end;
end;

{ True for a type signature that declares a PLAIN procedural type or method
  pointer (procedure, function: Integer, procedure of object). A "reference to"
  anonymous method is excluded: it needs explicit parens to run, so a paren-less
  read of one is a value, not a call (a parenthesised call already has its own
  call ref). }
function IsProcTypeSignature(const ASignature: string): Boolean;
var
  S: string;
begin
  S:= LowerCase(Trim(ASignature));
  Result:= S.StartsWith('procedure') or S.StartsWith('function');
end;

{ True when the symbol a read ref binds to is a variable, parameter or field
  whose declared type is a plain procedural type (named, or written inline). }
function TPurityRun.IsProcTypedTarget(ATargetId: Int64): Boolean;
var
  T: TSymbol;
begin
  Result:= False;
  if ATargetId <= 0 then Exit;
  T:= SymbolById(ATargetId);
  if (T.Kind not in [skVarDecl, skField]) and (T.Kind.ToText <> KIND_TEXT_LOCAL_VAR) and (T.Kind.ToText <> KIND_TEXT_PARAM) then Exit;
  Result:= IsProcTypeSignature(T.Signature) or FProcTypes.ContainsKey(LowerKey(Trim(T.Signature)));
end;

{ A paren-less read of a procedural-type value RUNS it (Result := F;,
  P;). Not a call: @P, Assigned(P), P = nil, P <> nil. }
function TPurityRun.IsImplicitProcCall(const ALines: TArray<string>; const ARef: TReference): Boolean;
var
  Line, Before, After: string;
begin
  Result:= True;
  if (ARef.StartLine < 1) or (ARef.StartLine > Length(ALines)) then Exit;
  Line:= MaskLinePreservingColumns(ALines[ARef.StartLine - 1]);
  Before:= LowerCase(TrimRight(Copy(Line, 1, ARef.StartCol - 1)));
  After:= TrimLeft(Copy(Line, ARef.StartCol + Length(ARef.NameText), MaxInt));
  if Before.EndsWith('@') or Before.EndsWith('assigned(') then Exit(False);
  if After.StartsWith('=') or After.StartsWith('<>') then Exit(False);
end;

function TPurityRun.IsBound(const ARef: TReference): Boolean;
var
  E: TCallEdge;
begin
  Result:= FEdges.TryGetValue(ARef.Id, E) and (E.TargetSymbolId <> 0);
end;

{ ClassifyArgument against the caller's own names, plus one caller-side rule:
  a BARE `Result` is the routine's own storage, so it is treated like a
  non-escaping local (the spec's reference-typed-local approximation applies
  to it exactly as to any local). `Result.X` keeps ClassifyArgument's verdict. }
function TPurityRun.Classify(AIndex: Integer; const AText: string): TArgInfo;
begin
  Result:= ClassifyArgument(AText, FCtx[AIndex].Locals, FCtx[AIndex].Params, FCtx[AIndex].Fields, FCtx[AIndex].Escaping);
  if (Result.Cls = acUnknown) and SameText(Result.Text, NAME_RESULT) then Result.Cls:= acLocal;
  { A by-value scalar is the routine's own copy: Inc(AIdx) reaches nothing of the caller's. }
  if (Result.Cls = acParam) and IsByValueScalarParam(FRoutines[AIndex].Signature, Result.ParamOrdinal) then
    Result.Cls:= acLocal;
end;

function TPurityRun.SelfReceiver: TArgInfo;
begin
  Result:= Default(TArgInfo);
  Result.Cls:= acSelfOrField;
  Result.ParamOrdinal:= -1;
  Result.RootName:= NAME_SELF;
  Result.Text:= NAME_SELF;
end;

{ The receiver a bound callee's `s` translates through. A bare call (or an
  `inherited X`) on a method is a call on Self; a constructor invoked on its
  own class name builds a FRESH object, whose field writes reach nothing of
  the caller's, so it is classed like a non-escaping local. }
function TPurityRun.ReceiverOf(AIndex: Integer; const AText: string; const ATarget: TSymbol; AIsInherited: Boolean): TArgInfo;
var
  Owner: TSymbol;
begin
  if AIsInherited or (Trim(AText) = '') then
  begin
    if ClassIdOf(ATarget) <> 0 then Exit(SelfReceiver);
    Result:= Default(TArgInfo);
    Result.Cls:= acUnknown;
    Result.ParamOrdinal:= -1;
    Exit;
  end;
  Result:= Classify(AIndex, AText);
  if (Result.Cls = acUnknown) and (ATarget.Kind = skConstructor) then
  begin
    Owner:= SymbolById(ATarget.ParentId);
    if (Owner.Id > 0) and (SameText(AText, Owner.Name) or EndsText('.' + Owner.Name, AText)) then
      Result.Cls:= acLocal;
  end;
end;

{ `inherited Foo(...)` is a STATIC call to the ancestor's implementation: the
  virtual-dispatch rule must not fire on it. }
function TPurityRun.PrecededByInherited(const ALines: TArray<string>; const ARef: TReference): Boolean;
var
  Before: string;
begin
  Result:= False;
  if (ARef.StartLine < 1) or (ARef.StartLine > Length(ALines)) then Exit;
  Before:= TrimRight(Copy(MaskLinePreservingColumns(ALines[ARef.StartLine - 1]), 1, ARef.StartCol - 1));
  Result:= EndsText(WORD_INHERITED, Before) and
    ((Length(Before) = Length(WORD_INHERITED)) or
     not CharInSet(Before[Length(Before) - Length(WORD_INHERITED)], ['A'..'Z', 'a'..'z', '0'..'9', '_']));
end;

{ Which call ref on ALineNo owns the parenthesis that is still open at ACol:
  walk left to the unmatched `(`, then take the call whose name ends right
  before it (blanks allowed). -1 when the paren belongs to no call ref (a
  grouping, an indexer-free cast without a ref, ...). }
function TPurityRun.EnclosingCall(const ALine: string; ACol: Integer; ACalls: TList<TReference>; ALineNo: Integer): Integer;
var
  Masked   : string;
  Depth, P : Integer;
  NameEnd  : Integer;
begin
  Result:= -1;
  Masked:= MaskLinePreservingColumns(ALine);
  Depth:= 0;
  P:= 0;
  for var I:= Min(ACol - 1, Length(Masked)) downto 1 do
    if Masked[I] = ')' then Inc(Depth)
    else if Masked[I] = '(' then
    begin
      if Depth = 0 then
      begin
        P:= I;
        Break;
      end;
      Dec(Depth);
    end;
  if P = 0 then Exit;
  for var I:= 0 to ACalls.Count - 1 do
  begin
    if ACalls[I].StartLine <> ALineNo then Continue;
    NameEnd:= ACalls[I].StartCol + Length(ACalls[I].NameText);
    if ((NameEnd <= P) and (Trim(Copy(Masked, NameEnd, P - NameEnd)) = '')) and ((Result < 0) or (ACalls[I].StartCol > ACalls[Result].StartCol)) then Result:= I;
  end;
end;

procedure TPurityRun.MarkEscaping(AIndex: Integer; const AName: string);
begin
  if FCtx[AIndex].Escaping = nil then FCtx[AIndex].Escaping:= NewSet;
  FCtx[AIndex].Escaping.AddOrSetValue(LowerKey(AName), True);
end;

{ ---------------------------------------------------------------------- load }

procedure TPurityRun.Load;
var
  List: TList<Integer>;
begin
  FRoutines:= FStore.FindSymbolsWithFacts;
  SetLength(FCtx, Length(FRoutines));
  SetLength(FLocal, Length(FRoutines));
  SetLength(FSummary, Length(FRoutines));
  SetLength(FUses, Length(FRoutines));
  for var I:= 0 to High(FRoutines) do
    FIndexOf.AddOrSetValue(FRoutines[I].Id, I);
  for var I:= 0 to High(FRoutines) do
    if FIndexOf.ContainsKey(FRoutines[I].ParentId) then
    begin
      if not FChildrenOf.TryGetValue(FRoutines[I].ParentId, List) then
      begin
        List:= TList<Integer>.Create;
        FChildrenOf.Add(FRoutines[I].ParentId, List);
      end;
      List.Add(I);
    end;
  for var F in FStore.GetAllSymbolFacts do FFacts.AddOrSetValue(F.SymbolId, F);
  for var S in FStore.GetAllFileStamps do FStamps.AddOrSetValue(S.Path, S.MTimeUnix);
  for var T in FStore.FindSymbolsByKind(KIND_TEXT_TYPE, False, MaxInt) do
    if IsProcTypeSignature(T.Signature) then FProcTypes.AddOrSetValue(LowerKey(T.Name), True);
  FInputsNow:= InputsStamp;
end;

{ INCR18 step 4: THE INPUTS NO CALL-TARGET SCOPE DESCRIBES. A routine's verdict also depends
  on (a) the set of procedural type NAMES in the whole database -- a paren-less read of a
  variable declared with one is an implicit call (IsProcTypedTarget), and the variable's own
  row does not move when the type is declared or withdrawn elsewhere -- and (b) the library
  effects store and how it is trusted. Neither is a ref binding, so no scope names the
  routines they reach; a scoped run is taken only when this stamp equals the one the last run
  stored (schema_meta purity_inputs). }
function TPurityRun.InputsStamp: string;
var
  Names: TArray<string>;
begin
  Names:= FProcTypes.Keys.ToArray;
  TArray.Sort<string>(Names, TStringComparer.Ordinal);
  Result:= THashSHA1.GetHashString(string.Join(',', Names) + '|' +
    (if TPurityStage.LibraryEffects <> nil then 'lib:' + TPurityStage.LibraryEffectsStamp else 'nolib') + '|' +
    (if TPurityStage.LibraryEffectsTrustFree then 'trust' else 'shallow'));
end;

{ A heritage name reduced to what the scope names hold: the bare, lowercased
  type name -- no unit prefix ('Vcl.Forms.TForm'), no type arguments. }
function BareTypeKey(const AName: string): string;
var
  P: Integer;
begin
  Result:= AName;
  P:= Pos('<', Result);
  if P > 0 then Result:= Copy(Result, 1, P - 1);
  P:= LastDelimiter('.', Result);
  if P > 0 then Result:= Copy(Result, P + 1, MaxInt);
  Result:= LowerKey(Result);
end;

{ INCR18 step 4: WHICH ROUTINES THIS RUN RE-DERIVES.

  Measured motive (PLAN.md of the lane, C4): a one-file incremental index of this repo's own
  project spent 19-32 s here, all but 0.2 s of it loading and scanning every routine, while
  the routines whose verdict CAN move are the edited file's and their callers.

  Only when every call-target pass since the last purity write ran SCOPED on this store
  instance (ISymbolStore.LastCallsScope) and the unscoped inputs are unchanged (InputsStamp).
  Then every verdict input outside what follows is the previous run's. Seeds:
    - every routine of a file a pass rewrote;
    - every routine around a ref whose binding a pass CHANGED, or that was bound into a
      rewritten file before the rewrite (TCallsScope.EnclosingIds) -- not every ref a pass
      re-read: a reparse re-adds every name its file declares, so a pass re-reads each
      Create / Free in the corpus and binds almost all of them as before;
    - every routine with no verdict yet;
    - every method of a class whose own file, or ANY ancestor's file or NAME, is in the
      scope: inherited fields and properties decide how an identifier is classified, a bare
      `inherited;` binds to the nearest ancestor that declares the name, and a REMOVED base
      class leaves no resolved link to a scope file -- only its name in the scope names.
  Closed over the reverse call graph (a caller's verdict folds its callees'), and, because a
  bare `inherited;` reaches the ancestor's method WITHOUT a call_edges row, over the
  same-named methods of every descendant class. A property accessor is reached through a
  call_edges row as well (member_accesses carries the mode only), so the call graph is the
  whole of FUses. Everything outside keeps its stored verdict, which the fixpoint reads as a
  constant. Proof: tests\autotest\run_v1521_INCR18.ps1 (scoped = whole = full reindex over
  symbol_facts, 0 diff rows, and the seeds-only positive control). }
procedure TPurityRun.DetermineScope;  // dl:ok cyclomatic-complexity@d5fb -- REVIEWED 2026-11-19 (INCR18 step 4): one decision (which routines to re-derive) told in order -- gates, seeds, the caller source, the heirs, the closure; the steps share seven local sets, so splitting them would pass those around for no reader's benefit
var
  Scope    : TCallsScope;
  ScopeFile: TDictionary<Int64, Boolean>;
  ScopeName: TDictionary<string, Boolean>;
  Touched  : TDictionary<Int64, Boolean>;
  Desc     : TObjectDictionary<Int64, TList<Int64>>;
  OfClass  : TObjectDictionary<Int64, TList<Integer>>;
  CallersOf: TObjectDictionary<Int64, TList<Int64>>;
  Queue    : TQueue<Integer>;
  I, K     : Integer;
  F        : TSymbolFacts;
  IdList   : TList<Int64>;
  IxList   : TList<Integer>;

  procedure Mark(AIndex: Integer);
  begin
    if FInScope[AIndex] then Exit;  // dl:ok index-possibly-out-of-range@c083 -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
    FInScope[AIndex]:= True;
    Inc(FScopeCount);
    Queue.Enqueue(AIndex);
  end;

  function ClassTouched(AClassId: Int64): Boolean;
  begin
    if Touched.TryGetValue(AClassId, Result) then Exit;
    Result:= ScopeFile.ContainsKey(SymbolById(AClassId).FileId);
    if not Result then
      for var Anc in AncestorsOf(AClassId) do
        if (Anc.Resolved and ScopeFile.ContainsKey(Anc.FileId)) or ScopeName.ContainsKey(BareTypeKey(Anc.Name))
           or ((Anc.ResolvedName <> '') and ScopeName.ContainsKey(BareTypeKey(Anc.ResolvedName))) then
        begin
          Result:= True;
          Break;
        end;
    Touched.Add(AClassId, Result);
  end;

begin
  FScoped:= False;
  FScopeNote:= '';
  FScopeCount:= 0;
  SetLength(FInScope, Length(FRoutines));
  SetLength(FClassOf, Length(FRoutines));
  for I:= 0 to High(FRoutines) do FClassOf[I]:= ClassIdOf(FRoutines[I]);  // dl:ok index-possibly-out-of-range@751c -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
  var HasScope: Boolean:= FStore.LastCallsScope(Scope);
  if HasScope and (GetEnvironmentVariable(ENV_NO_SCOPED_PURITY) <> '') then
  begin
    HasScope:= False;
    FScopeNote:= ENV_NO_SCOPED_PURITY + ' is set';
  end;
  if HasScope and (FStore.GetMetaValue(META_PURITY_INPUTS) <> FInputsNow) then
  begin
    HasScope:= False;
    FScopeNote:= 'the procedural type names or the library effects store differ from the last run''s (or none was recorded)';
  end;
  if not HasScope then
  begin
    for I:= 0 to High(FRoutines) do FInScope[I]:= True;  // dl:ok index-possibly-out-of-range@bed5 -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
    FScopeCount:= Length(FRoutines);
    Exit;
  end;
  FScoped:= True;
  ScopeFile:= TDictionary<Int64, Boolean>.Create;
  ScopeName:= TDictionary<string, Boolean>.Create;
  Touched  := TDictionary<Int64, Boolean>.Create;
  Desc     := TObjectDictionary<Int64, TList<Int64>>.Create([doOwnsValues]);
  OfClass  := TObjectDictionary<Int64, TList<Integer>>.Create([doOwnsValues]);
  CallersOf:= TObjectDictionary<Int64, TList<Int64>>.Create([doOwnsValues]);
  Queue    := TQueue<Integer>.Create;
  try
    for var Fid in Scope.FileIds do ScopeFile.AddOrSetValue(Fid, True);
    for var N in Scope.Names do ScopeName.AddOrSetValue(LowerKey(N), True);
    for I:= 0 to High(FRoutines) do  // dl:ok index-possibly-out-of-range@68a2 -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
      if ScopeFile.ContainsKey(FRoutines[I].FileId) then Mark(I)
      else if (not FFacts.TryGetValue(FRoutines[I].Id, F)) or (F.EffectFree < 0) then Mark(I)
      else if (FClassOf[I] <> 0) and ClassTouched(FClassOf[I]) then Mark(I);
    for var Id in Scope.EnclosingIds do
      if FIndexOf.TryGetValue(Id, K) then Mark(K);
    if GetEnvironmentVariable(ENV_TEST_SEEDS_ONLY) = '1' then
    begin
      FScopeNote:= 'TEST SEAM ' + ENV_TEST_SEEDS_ONLY + ': seeds only, callers NOT followed (a WRONG scope)';
      Exit;
    end;

    { THE REVERSE CALL GRAPH, ASKED FOR WHAT THE CLOSURE VISITS. The closure below asks per
      routine it dequeues, and only past CALLERS_BULK_AFTER asks does it read the whole graph.
      The set it marks is the same either way: Mark is idempotent and order-free. }
    var CallerAsks: Integer:= 0;
    var CallersBulk: Boolean:= False;
    var CallersOfRoutine: TFunc<Int64, TList<Int64>>:= function(AId: Int64): TList<Int64>
      begin
        if CallersOf.TryGetValue(AId, Result) then Exit;
        if CallersBulk then Exit(nil);
        Inc(CallerAsks);
        if CallerAsks > CALLERS_BULK_AFTER then
        begin
          CallersOf.Clear;
          for var CT in FStore.DumpCallerTargets do
          begin
            if not CallersOf.TryGetValue(CT.TargetId, Result) then
            begin
              Result:= TList<Int64>.Create;
              CallersOf.Add(CT.TargetId, Result);
            end;
            Result.Add(CT.CallerId);
          end;
          CallersBulk:= True;
          if not CallersOf.TryGetValue(AId, Result) then Result:= nil;
          Exit;
        end;
        Result:= TList<Int64>.Create;
        Result.AddRange(FStore.CallerRoutinesOf(AId));
        CallersOf.Add(AId, Result);
      end;
    for I:= 0 to High(FRoutines) do  // dl:ok index-possibly-out-of-range@68a2 -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
      if FClassOf[I] <> 0 then
      begin
        if not OfClass.TryGetValue(FClassOf[I], IxList) then
        begin
          IxList:= TList<Integer>.Create;
          OfClass.Add(FClassOf[I], IxList);
        end;
        IxList.Add(I);
      end;
    for var C in OfClass.Keys do
      for var Anc in AncestorsOf(C) do
        if Anc.Resolved then
        begin
          if not Desc.TryGetValue(Anc.SymbolId, IdList) then
          begin
            IdList:= TList<Int64>.Create;
            Desc.Add(Anc.SymbolId, IdList);
          end;
          IdList.Add(C);
        end;

    while Queue.Count > 0 do
    begin
      I:= Queue.Dequeue;  // dl:ok index-possibly-out-of-range@761b -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
      IdList:= CallersOfRoutine(FRoutines[I].Id);
      if IdList <> nil then
        for var C in IdList do
          if FIndexOf.TryGetValue(C, K) then Mark(K);
      if (FClassOf[I] <> 0) and Desc.TryGetValue(FClassOf[I], IdList) then
        for var D in IdList do
          if OfClass.TryGetValue(D, IxList) then
            for var R in IxList do
              if SameText(FRoutines[R].Name, FRoutines[I].Name) then Mark(R);
    end;
  finally
    Queue.Free;
    CallersOf.Free;
    OfClass.Free;
    Desc.Free;
    Touched.Free;
    ScopeName.Free;
    ScopeFile.Free;
  end;
end;

{ The verdict a routine OUTSIDE the scope already carries, as the fixpoint's
  constant for it. DetermineScope admits only routines with a computed verdict
  to the outside, so effect_summary is set. }
function TPurityRun.StoredSummary(AIndex: Integer): TEffectSummary;
var
  F: TSymbolFacts;
begin
  if not FFacts.TryGetValue(FRoutines[AIndex].Id, F) then Exit(Default(TEffectSummary));  // dl:ok index-possibly-out-of-range@d195 -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
  Result:= TEffectSummary.Decode(F.EffectSummary);
  Result.Witness:= F.EffectWitness;
end;

{ The call edges and member accesses of the refs the scan will read. Only the
  routines in scope are scanned, and only the refs of their files, so a scoped
  run reads those files' rows instead of both whole tables. A whole run reads all. }
procedure TPurityRun.LoadBindings;
var
  Edges, Members: TArray<TCallEdge>;
  FileIds       : TArray<Int64>;
begin
  if FScoped then
  begin
    var Files: TDictionary<Int64, Boolean>:= TDictionary<Int64, Boolean>.Create;
    try
      for var I:= 0 to High(FRoutines) do  // dl:ok index-possibly-out-of-range@0be8 -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
        if FInScope[I] then Files.AddOrSetValue(FRoutines[I].FileId, True);
      FileIds:= Files.Keys.ToArray;
    finally
      Files.Free;
    end;
    Edges  := FStore.DumpCallEdgesInFiles(FileIds);
    Members:= FStore.DumpMemberAccessesInFiles(FileIds);
  end
  else
  begin
    Edges  := FStore.DumpAllCallEdges;
    Members:= FStore.DumpAllMemberAccesses;
  end;
  for var E in Edges do FEdges.AddOrSetValue(E.RefId, E);
  for var M in Members do FMembers.AddOrSetValue(M.RefId, M);
end;

{ The param and local_var symbols BuildContexts needs. A context is built only
  for a routine in scope, from its own params and locals and those of the
  routines enclosing it; a scoped run with few of them asks for exactly those
  parents' children instead of every row of both kinds. Past
  CONTEXT_PARENTS_BULK parents the two bulk reads are cheaper. }
procedure TPurityRun.CollectContextSymbols(out AParams, ALocals: TArray<TSymbol>);
var
  Parents: TDictionary<Int64, Boolean>;
  P, L   : TList<TSymbol>;
begin
  Parents:= TDictionary<Int64, Boolean>.Create;
  P:= TList<TSymbol>.Create;
  L:= TList<TSymbol>.Create;
  try
    if FScoped then
      for var I:= 0 to High(FRoutines) do  // dl:ok index-possibly-out-of-range@0be8 -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
        if FInScope[I] then
        begin
          var Up: TSymbol:= FRoutines[I];
          while (Up.Id > 0) and (Up.Kind in ROUTINE_KINDS) and not Parents.ContainsKey(Up.Id) do
          begin
            Parents.Add(Up.Id, True);
            Up:= SymbolById(Up.ParentId);
          end;
        end;
    if (not FScoped) or (Parents.Count > CONTEXT_PARENTS_BULK) then
    begin
      AParams:= FStore.FindSymbolsByKind(KIND_TEXT_PARAM, False, MaxInt);
      ALocals:= FStore.FindSymbolsByKind(KIND_TEXT_LOCAL_VAR, False, MaxInt);
      Exit;
    end;
    for var Id in Parents.Keys do
      for var C in FStore.FindAllChildSymbols(Id) do
        if C.Kind.ToText = KIND_TEXT_PARAM then P.Add(C)
        else if C.Kind.ToText = KIND_TEXT_LOCAL_VAR then L.Add(C);
    AParams:= P.ToArray;
    ALocals:= L.ToArray;
  finally
    L.Free;
    P.Free;
    Parents.Free;
  end;
end;

{ Params (ordered by declaration position -> ordinal) and locals per routine,
  then the per-routine classification context. }
procedure TPurityRun.BuildContexts;
var
  ByParent: TObjectDictionary<Int64, TList<TSymbol>>;
  List    : TList<TSymbol>;
  Map     : TParamMap;
  Names   : TArray<string>;
  Own     : TNameSet;
  Merged  : TNameSet;
  Up      : TSymbol;
  UpSet   : TNameSet;
  ParamSyms, LocalSyms: TArray<TSymbol>;
begin
  CollectContextSymbols(ParamSyms, LocalSyms);
  ByParent:= TObjectDictionary<Int64, TList<TSymbol>>.Create([doOwnsValues]);
  try
    for var P in ParamSyms do
    begin
      if not ByParent.TryGetValue(P.ParentId, List) then
      begin
        List:= TList<TSymbol>.Create;
        ByParent.Add(P.ParentId, List);
      end;
      List.Add(P);
    end;
    for var Pair in ByParent do
    begin
      Pair.Value.Sort(TComparer<TSymbol>.Construct(
        function(const L, R: TSymbol): Integer
        begin
          Result:= L.StartLine - R.StartLine;
          if Result = 0 then Result:= L.StartCol - R.StartCol;
        end));
      Map:= NewMap;
      SetLength(Names, Pair.Value.Count);
      for var K:= 0 to Pair.Value.Count - 1 do
      begin
        Map.AddOrSetValue(LowerKey(Pair.Value[K].Name), K);
        Names[K]:= Pair.Value[K].Name;
      end;
      FParamsOf.Add(Pair.Key, Map);
      FParamNames.Add(Pair.Key, Names);
    end;
  finally
    ByParent.Free;
  end;
  for var L in LocalSyms do
  begin
    if not FLocalsOf.TryGetValue(L.ParentId, Own) then
    begin
      Own:= NewSet;
      FLocalsOf.Add(L.ParentId, Own);
    end;
    Own.AddOrSetValue(LowerKey(L.Name), True);
  end;
  for var I:= 0 to High(FRoutines) do
  begin
    if not FInScope[I] then Continue;   { INCR18 step 4: an outside routine is never scanned }
    if not FLocalsOf.TryGetValue(FRoutines[I].Id, Own) then Own:= FEmptySet;
    FCtx[I].OwnLocals:= Own;
    { A nested routine writes the enclosing routine's locals as a matter of
      course; those writes stay in the enclosing frame, so they are locals for
      classification -- but NOT for the gate, which asks about this routine's
      own rows. }
    Merged:= Own;
    Up:= SymbolById(FRoutines[I].ParentId);
    while (Up.Id > 0) and (Up.Kind in ROUTINE_KINDS) do
    begin
      if FLocalsOf.TryGetValue(Up.Id, UpSet) and (UpSet.Count > 0) then
      begin
        if Merged = Own then
        begin
          Merged:= NewSet;
          for var K in Own.Keys do Merged.AddOrSetValue(K, True);
        end;
        for var K in UpSet.Keys do Merged.AddOrSetValue(K, True);
      end;
      Up:= SymbolById(Up.ParentId);
    end;
    FCtx[I].Locals:= Merged;
    if not FParamsOf.TryGetValue(FRoutines[I].Id, FCtx[I].Params) then FCtx[I].Params:= FEmptyMap;
    if not FParamNames.TryGetValue(FRoutines[I].Id, FCtx[I].ParamNames) then FCtx[I].ParamNames:= nil;
    FCtx[I].ClassId:= FClassOf[I];
    FCtx[I].Fields:= FieldsOfClass(FCtx[I].ClassId);
    FCtx[I].Props:= PropsOfClass(FCtx[I].ClassId);
    FCtx[I].Escaping:= nil;
  end;
end;

{ ---------------------------------------------------------------------- scan }

procedure TPurityRun.ScanFiles;
var
  I, J     : Integer;
  FileId   : Int64;
  Path     : string;
  DiskUnix : Int64;
  Stored   : Int64;
  Stale    : Boolean;
  Lines    : TArray<string>;
  ByRoutine: TObjectDictionary<Int64, TList<TReference>>;
  RefList  : TList<TReference>;
  Changed  : Boolean;
  Shallow  : Boolean;
begin
  I:= 0;
  while I <= High(FRoutines) do
  begin
    BeatProgress(I); { one report per file; N counts routines }
    FileId:= FRoutines[I].FileId;
    J:= I;
    while (J <= High(FRoutines)) and (FRoutines[J].FileId = FileId) do Inc(J);
    { [I, J) is this file's routines (FindSymbolsWithFacts orders by file). }
    { INCR18 step 4: a file with no routine in the scope is neither stamped, read nor
      scanned -- that read is what the scope exists to save. }
    var AnyInScope: Boolean:= False;
    for var K:= I to J - 1 do
      if FInScope[K] then
      begin
        AnyInScope:= True;
        Break;
      end;
    if not AnyInScope then
    begin
      I:= J;
      Continue;
    end;
    Inc(FScopeFiles);
    var Tk0: Int64:= TStopwatch.GetTimeStamp;
    Path:= FStore.GetFilePath(FileId);
    { ONE query for the file's symbols instead of one per ref target. The refs
      below bind mostly to this file's own locals, params and routines, and
      SymbolById fetched each of them singly: 55,693 single-row queries, 30.7 s
      of a 40 s stage on this repo's own project, paid on every index run that
      wrote a file (run_purity_symbol_lookup_cost.ps1). Same rows, same mapper
      (SELECT * FROM symbols + ReadSymbolFromQuery), so the cache holds exactly
      what SymbolById would have fetched; TryAdd keeps an entry already there. }
    var TkP: Int64:= TStopwatch.GetTimeStamp;
    for var S in FStore.FindSymbolsByFile(Path) do
    begin
      FSymCache.TryAdd(S.Id, S);
      Inc(FPreloadRows);
    end;
    Inc(FTkPreload, TStopwatch.GetTimeStamp - TkP);
    Stale:= not (TryGetFileMTimeUnix(Path, DiskUnix) and FStamps.TryGetValue(Path, Stored) and (DiskUnix = Stored));
    { An unreadable file IS the stale case (ruling 7): every routine in it is
      marked unknown with the stale witness below, which is the report. }
    if not Stale then Stale:= not ReadFileLines(FileId, Lines);
    if Stale then
    begin
      Inc(FStats.StaleFiles);
      for var K:= I to J - 1 do
      begin
        if not FInScope[K] then Continue;
        Changed:= False;
        FLocal[K]:= Default(TEffectSummary);
        FLocal[K].AddFlag(efUnknown, WITNESS_STALE, Changed);
        FUses[K]:= nil;
      end;
      I:= J;
      Continue;
    end;
    CacheLines(FileId, Lines);
    Inc(FTkFile, TStopwatch.GetTimeStamp - Tk0);
    Tk0:= TStopwatch.GetTimeStamp;
    ByRoutine:= TObjectDictionary<Int64, TList<TReference>>.Create([doOwnsValues]);
    { 146 g1: a file with NO usage ref anywhere was parsed shallow (library
      mode, --shallow): only its calls were recorded, so an empty ref list
      proves nothing about a body. Counted over the whole file, not per
      routine, so a deep routine that merely reads nothing is unaffected. }
    Shallow:= True;
    try
      for var R in FStore.GetReferencesFromFile(FileId) do
      begin
        if (R.Kind = REF_KIND_READ) or (R.Kind = REF_KIND_WRITE) or (R.Kind = REF_KIND_MEMBER) then Shallow:= False;
        if R.EnclosingSymbolId = 0 then Continue;
        if not ((R.Kind = REF_KIND_CALL) or (R.Kind = REF_KIND_READ) or (R.Kind = REF_KIND_WRITE) or (R.Kind = REF_KIND_MEMBER)) then Continue;
        if not ByRoutine.TryGetValue(R.EnclosingSymbolId, RefList) then
        begin
          RefList:= TList<TReference>.Create;
          ByRoutine.Add(R.EnclosingSymbolId, RefList);
        end;
        RefList.Add(R);
      end;
      Inc(FTkRefs, TStopwatch.GetTimeStamp - Tk0);
      for var K:= I to J - 1 do
      begin
        if not FInScope[K] then Continue;
        if ByRoutine.TryGetValue(FRoutines[K].Id, RefList) then
          RefList.Sort(TComparer<TReference>.Construct(
            function(const L, R: TReference): Integer
            begin
              Result:= L.StartLine - R.StartLine;
              if Result = 0 then Result:= L.StartCol - R.StartCol;
              if Result = 0 then Result:= CompareStr(L.Kind, R.Kind);   { 'call' sorts before 'member-access' }
            end))
        else
          RefList:= nil;
        ScanRoutine(K, Lines, RefList, Shallow);
      end;
    finally
      ByRoutine.Free;
    end;
    I:= J;
  end;
end;

{ The body scan of a routine EXCLUDING the spans of its nested routines: a
  nested routine's `var` block would otherwise fire the gate on the enclosing
  routine, which owns no local_var row for those names. Each segment is
  scanned on its own; a segment that starts after a nested routine opens with
  the enclosing routine's own `begin` (or a late `var` block), which is exactly
  the state ScanRoutineBody expects. }
function TPurityRun.ScanBody(AIndex: Integer; const ALines: TArray<string>): TBodyScan;
  procedure Merge(var AInto: TBodyScan; const AFrom: TBodyScan);
  begin
    AInto.HasWith:= AInto.HasWith or AFrom.HasWith;
    AInto.HasBareInherited:= AInto.HasBareInherited or AFrom.HasBareInherited;
    AInto.HasVarBlock:= AInto.HasVarBlock or AFrom.HasVarBlock;
    AInto.HasInlineVar:= AInto.HasInlineVar or AFrom.HasInlineVar;
  end;
var
  R       : TSymbol;
  Children: TList<Integer>;
  Nested  : TList<TSymbol>;
  Cur     : Integer;
begin
  Result:= Default(TBodyScan);
  R:= FRoutines[AIndex];
  if not FChildrenOf.TryGetValue(R.Id, Children) then
    Exit(ScanRoutineBody(ALines, R.ImplStartLine, R.ImplEndLine));
  Nested:= TList<TSymbol>.Create;
  try
    for var C in Children do
      if FRoutines[C].ImplStartLine > 0 then Nested.Add(FRoutines[C]);
    Nested.Sort(TComparer<TSymbol>.Construct(
      function(const L, R: TSymbol): Integer
      begin
        Result:= L.ImplStartLine - R.ImplStartLine;
      end));
    Cur:= R.ImplStartLine;
    for var N in Nested do
    begin
      if N.ImplStartLine > Cur then Merge(Result, ScanRoutineBody(ALines, Cur, N.ImplStartLine - 1));
      Cur:= Max(Cur, N.ImplEndLine + 1);
    end;
    if Cur <= R.ImplEndLine then Merge(Result, ScanRoutineBody(ALines, Cur, R.ImplEndLine));
  finally
    Nested.Free;
  end;
end;

{ symbol_facts.touches is a TWO-FIELD wire string, 'resources|transactions',
  and EITHER SIDE MAY BE EMPTY with the separator always present -- so the
  stored value is routinely 'file system|' or '|starts, commits' (measured on
  this repo's own index: 308 rows of 'file system|', 13 of
  '|starts, commits, rolls back'). Concatenating it into a sentence therefore
  prints the separator: 'touches file system|'. It reached a user, in 14.2's
  message and in the stored witness.

  This splits it the way DRagLint.Doc.Regions already renders it -- omit an
  empty side -- and labels the transaction half, because 'touches starts,
  commits' is not English. Both sides populated reads
  'touches file system; transactions: starts, commits'. }
function TouchesWitness(const ATouches: string): string;
var
  Parts: TArray<string>;
  Res  : string        ;
  Txn  : string        ;
begin
  Parts:= ATouches.Split(['|']);
  Res:= if Length(Parts) > 0 then Trim(Parts[0]) else '';
  Txn:= if Length(Parts) > 1 then Trim(Parts[1]) else '';
  Result:= '';
  if Res <> '' then Result:= 'touches ' + Res;
  if Txn <> '' then
  begin
    if Result <> '' then Result:= Result + '; ';
    Result:= Result + 'transactions: ' + Txn;
  end;
  { A value this cannot split is still better reported verbatim than dropped --
    an empty witness would read as "proven", which is the opposite of true. }
  if Result = '' then Result:= 'touches ' + ATouches;
end;

procedure TPurityRun.ApplyFacts(AIndex: Integer; const AFacts: TSymbolFacts; var ASum: TEffectSummary; var AChanged: Boolean);
var
  Names  : TArray<string>;
  Capped : Boolean;
  Witness: string;
  Decl   : string;
  K      : Integer;
begin
  if AFacts.Touches <> '' then ASum.AddFlag(efGlobal, TouchesWitness(AFacts.Touches), AChanged);
  if AFacts.SqlWrites <> '' then ASum.AddFlag(efGlobal, 'writes SQL ' + AFacts.SqlWrites, AChanged);
  if AFacts.SqlReads <> '' then ASum.AddFlag(efGlobal, 'reads SQL ' + AFacts.SqlReads, AChanged);
  if AFacts.WritesFields <> '' then
  begin
    { The same display grammar as mutates_params (', '-joined, capped with
      ' (+N more)'); only the first name is needed for the witness. }
    Names:= ParseMutatedParamNames(AFacts.WritesFields, Capped);
    Witness:= 'writes field ' + (if Length(Names) > 0 then Names[0] else AFacts.WritesFields);
    if Length(Names) > 0 then
    begin
      Decl:= DeclaringAncestorOfField(FCtx[AIndex].ClassId, Names[0]);
      if Decl <> '' then Witness:= Witness + ' (declared on ' + Decl + ')';
    end;
    ASum.AddFlag(efSelfFields, Witness, AChanged);
  end;
  if AFacts.MutatesParams <> '' then
  begin
    Names:= ParseMutatedParamNames(AFacts.MutatesParams, Capped);
    if Capped then ASum.AddFlag(efUnknown, WITNESS_MUTATES_CAPPED, AChanged);
    for var Name in Names do
      { Ordinals come from the routine's OWN param rows, so k < ParamCount by
        construction (spec 3.3 / P3); a name the table does not know cannot be
        placed and is unknown. }
      if FCtx[AIndex].Params.TryGetValue(LowerKey(Name), K) then
      begin
        if not IsByValueScalarParam(FRoutines[AIndex].Signature, K) then
          ASum.AddParam(K, 'writes through parameter #' + IntToStr(K) + ' (' + Name + ')', AChanged);
      end
      else
        ASum.AddFlag(efUnknown, 'writes through parameter ' + Name + ' (not in the parameter table)', AChanged);
  end;
end;

{ A bare `inherited;` calls the ancestor's implementation of THIS method with
  the same arguments: the first resolved, non-interface ancestor that declares
  a routine of the same name is the callee; Self is the receiver; each of the
  caller's parameters is passed in its own position. }
procedure TPurityRun.AddInheritedUse(AIndex: Integer; var ASum: TEffectSummary; var AChanged: Boolean; AUses: TList<TCalleeUse>);
var
  R     : TSymbol;
  S     : TSymbol;
  Target: Int64;
  U     : TCalleeUse;
begin
  R:= FRoutines[AIndex];
  Target:= 0;
  if FCtx[AIndex].ClassId <> 0 then
    for var Anc in AncestorsOf(FCtx[AIndex].ClassId) do
      if Anc.Resolved and (Anc.Kind <> ANCESTOR_INTERFACE) then
      begin
        S:= FStore.FindChildSymbolByName(Anc.SymbolId, R.Name);
        if (S.Id > 0) and (S.Kind in ROUTINE_KINDS) then
        begin
          Target:= S.Id;
          Break;
        end;
      end;
  if Target = 0 then
  begin
    ASum.AddFlag(efUnknown, WITNESS_INHERITED_OUT, AChanged);
    Exit;
  end;
  U:= Default(TCalleeUse);
  U.Name:= WORD_INHERITED + ' ' + R.Name;
  if not FIndexOf.ContainsKey(Target) then
  begin
    ASum.AddFlag(efUnknown, 'calls ' + U.Name + ' (' + WITNESS_NO_FACTS + ')', AChanged);
    Exit;
  end;
  U.TargetId:= Target;
  U.Receiver:= SelfReceiver;
  U.FileId:= R.FileId;
  U.ArgsLexed:= True;
  U.ArgsKnown:= True;
  SetLength(U.Args, Length(FCtx[AIndex].ParamNames));
  for var K:= 0 to High(U.Args) do
  begin
    U.Args[K]:= Default(TArgInfo);
    U.Args[K].Cls:= acParam;
    U.Args[K].ParamOrdinal:= K;
    U.Args[K].RootName:= FCtx[AIndex].ParamNames[K];
    U.Args[K].Text:= FCtx[AIndex].ParamNames[K];
  end;
  AUses.Add(U);
end;

{ Ruling 8: a local whose value escapes (assigned away, address taken, or
  passed to a call this DB cannot see into -- Addr included, T2-ii) is never
  classed as a non-escaping local afterwards. }
procedure TPurityRun.CollectEscapes(AIndex: Integer; const ALines: TArray<string>; ARefs: TList<TReference>);
var
  Calls : TList<TReference>;
  Inside: Boolean;
  CIdx  : Integer;
  Line  : string;
begin
  Calls:= TList<TReference>.Create;
  try
    for var R in ARefs do
      if R.Kind = REF_KIND_CALL then Calls.Add(R);
    for var R in ARefs do
    begin
      if R.Kind <> REF_KIND_READ then Continue;
      if not FCtx[AIndex].Locals.ContainsKey(LowerKey(R.NameText)) then Continue;
      if (R.StartLine < 1) or (R.StartLine > Length(ALines)) then Continue;
      Line:= ALines[R.StartLine - 1];
      if ReadEscapesOnLine(Line, R.StartCol, Length(R.NameText), Inside) then
      begin
        MarkEscaping(AIndex, R.NameText);
        Continue;
      end;
      if not Inside then Continue;
      CIdx:= EnclosingCall(Line, R.StartCol, Calls, R.StartLine);
      if CIdx < 0 then Continue;
      if SameText(Calls[CIdx].NameText, NAME_ADDR) then
        MarkEscaping(AIndex, R.NameText)
      else if not IsBound(Calls[CIdx]) and not IsPurityAxiom(Calls[CIdx].NameText) then
      begin
        var B: TEffectSummary;
        if not BuiltinSummary(Calls[CIdx].NameText, B) then MarkEscaping(AIndex, R.NameText);
      end;
    end;
  finally
    Calls.Free;
  end;
end;

{ D12 (resolver 1.8.0-alpha). Pascal lets a function assign its result through
  its OWN NAME -- `Greater:= X > Y;` is `Result:= X > Y;` -- and a nested
  routine may assign the result of the function around it the same way. Such a
  write lands in a frame the routine owns (or, for a nested routine, in the
  enclosing frame, exactly like an outer local), so it is not an effect. It was
  scored `g`: 34 routines on ORM3 CLIENT, and all 4 assert-with-side-effect
  findings there. Only a FUNCTION or METHOD name counts: a procedure's name is
  not assignable, so a match there cannot be this shape. The caller has already
  let a local, a parameter or a field of that name win. }
function TPurityRun.IsResultByName(AIndex: Integer; const AKey: string): Boolean;
var
  S: TSymbol;
begin
  Result:= False;
  S:= FRoutines[AIndex];
  while (S.Id > 0) and (S.Kind in ROUTINE_KINDS) do
  begin
    if (S.Kind in [skFunction, skMethod]) and (LowerKey(S.Name) = AKey) then Exit(True);
    S:= SymbolById(S.ParentId);
  end;
end;

procedure TPurityRun.NonLocalWrite(AIndex: Integer; const ARef: TReference; var ASum: TEffectSummary; var AChanged: Boolean);
var
  Key: string;
begin
  if Trim(ARef.ReceiverText) <> '' then
  begin
    MemberWrite(AIndex, ARef.ReceiverText, ARef.NameText, ASum, AChanged);
    Exit;
  end;
  Key:= LowerKey(ARef.NameText);
  if Key = NAME_RESULT then Exit;
  if FCtx[AIndex].Locals.ContainsKey(Key) or FCtx[AIndex].Params.ContainsKey(Key) or FCtx[AIndex].Fields.ContainsKey(Key) then Exit;
  if IsResultByName(AIndex, Key) then Exit;
  if FCtx[AIndex].Props.ContainsKey(Key) then
  begin
    ASum.AddFlag(efUnknown, 'writes property ' + ARef.NameText + ' (setter not followed)', AChanged);
    Exit;
  end;
  ASum.AddFlag(efGlobal, 'writes ' + ARef.NameText + ' (non-local)', AChanged);
end;

{ A call ref (or a paren-less member-access ref) bound by call_edges. }
procedure TPurityRun.BoundCall(AIndex: Integer; const ARef: TReference; ATargetId: Int64; const ALines: TArray<string>;
  var ASum: TEffectSummary; var AChanged: Boolean; AUses: TList<TCalleeUse>);
var
  T    : TSymbol;
  IsInh: Boolean;
  U    : TCalleeUse;
begin
  T:= SymbolById(ATargetId);
  if T.Kind in CAST_KINDS then Exit;   { TFoo(X): a cast, not a call }
  if (T.Kind not in ROUTINE_KINDS) then
  begin
    ASum.AddFlag(efUnknown, 'calls ' + ARef.NameText + ' (' + WITNESS_NOT_ROUTINE + ')', AChanged);
    Exit;
  end;
  IsInh:= PrecededByInherited(ALines, ARef);
  if (not IsInh) and (T.IsVirtual or (SymbolById(T.ParentId).Kind = skInterface)) then
  begin
    ASum.AddFlag(efUnknown, 'calls ' + T.Name + ' (' + WITNESS_VIRTUAL + ')', AChanged);
    Exit;
  end;
  if not FIndexOf.ContainsKey(T.Id) then
  begin
    ASum.AddFlag(efUnknown, 'calls ' + T.Name + ' (' + WITNESS_NO_FACTS + ')', AChanged);
    Exit;
  end;
  U:= Default(TCalleeUse);
  U.TargetId:= T.Id;
  U.Name:= (if IsInh then WORD_INHERITED + ' ' else '') + ARef.NameText;
  U.Receiver:= ReceiverOf(AIndex, ARef.ReceiverText, T, IsInh);
  U.FileId:= FRoutines[AIndex].FileId;
  U.Line:= ARef.StartLine;
  U.ColAfter:= ARef.StartCol + Length(ARef.NameText);
  AUses.Add(U);
end;

{ E-BIND-LIB-EFFECTS: one library target's joined verdict, cached by name. Overloads join
  (flags and params union). A virtual or interface member, or a name with no verdict row, is
  not Usable: the caller then keeps today's unbound `?`. }
function TPurityRun.LibCallee(const AQName: string): TLibCallee;
var
  Changed: Boolean;
begin
  if FLibCallees.TryGetValue(LowerKey(AQName), Result) then Exit;
  Result:= Default(TLibCallee);
  var Lib: ISymbolStore:= TPurityStage.LibraryEffects;
  var Virt: Boolean:= False;
  var Seen: Boolean:= False;
  Changed:= False;
  for var S: TSymbol in Lib.FindSymbolsByQualifiedName(AQName) do
  begin
    if S.Kind not in ROUTINE_KINDS then Continue;
    if S.IsVirtual or (Lib.GetSymbolById(S.ParentId).Kind = skInterface) then Virt:= True;
    Result.IsMember:= Result.IsMember or (S.ParentId > 0);
    if S.Kind = skConstructor then
    begin
      Result.IsCtor:= True;
      Result.OwnerName:= Lib.GetSymbolById(S.ParentId).Name;
    end;
    var F: TSymbolFacts:= Lib.GetSymbolFacts(S.Id);
    if (not F.Present) or (F.BodyLoc <= 0) then Continue;
    Seen:= True;
    var D: TEffectSummary:= TEffectSummary.Decode(F.EffectSummary);
    for var Flag:= Low(TEffectFlag) to High(TEffectFlag) do
      { h stays out: a library routine's own temporaries read as "frees storage" and every caller
        then reads as having an effect (IsCweId calls TRegEx.IsMatch). Measured: spec section 5. }
      if (Flag in D.Flags) and ((Flag <> efHeap) or TPurityStage.LibraryEffectsTrustFree) then Result.Sum.AddFlag(Flag, 'library ' + AQName, Changed);
    for var K in D.Params do Result.Sum.AddParam(K, 'library ' + AQName, Changed);
  end;
  Result.Usable:= Seen and not Virt;
  if not TPurityStage.LibraryEffectsTrustFree then
    Result.Sum.AddFlag(efUnknown, 'library ' + AQName + ' (shallow parse)', Changed);
  FLibCallees.Add(LowerKey(AQName), Result);
end;

{ True when ARef was taken over as a library use. The use rides the built-in path of the
  fixpoint: TranslateCallee moves s through the receiver and p<k> through the lexed args. }
function TPurityRun.LibraryCall(AIndex: Integer; const ARef: TReference; AUses: TList<TCalleeUse>): Boolean;
var
  U: TCalleeUse;
begin
  { GetReferencesFromFile does not carry external_target; the unresolved-call reader does.
    One query per routine that reaches this point, so an OFF run never pays it. }
  var Id: Int64:= FRoutines[AIndex].Id;
  if FLibRoutine <> Id then
  begin
    FLibRoutine:= Id;
    FLibTargets.Clear;
    for var R: TReference in FStore.GetUnresolvedCallsFromSymbol(Id) do
      if R.ExternalTarget <> '' then FLibTargets.AddOrSetValue(R.Id, R.ExternalTarget);
  end;
  var Target: string;
  if not FLibTargets.TryGetValue(ARef.Id, Target) then
  begin
    { 1.51.1 B04: a paren-less library call is a `read` ref; it carries its own target. }
    if ARef.ExternalKind <> EXTERNAL_KIND_PARENLESS_CALL then Exit(False);
    Target:= ARef.ExternalTarget;
  end;
  var C: TLibCallee:= LibCallee(Target);
  Result:= C.Usable;
  if not Result then Exit;
  U:= Default(TCalleeUse);
  U.IsBuiltin:= True;
  U.Builtin:= C.Sum;
  U.Name:= ARef.NameText;
  if Trim(ARef.ReceiverText) = '' then
  begin
    if C.IsMember then U.Receiver:= SelfReceiver
    else
    begin
      U.Receiver:= Default(TArgInfo);
      U.Receiver.Cls:= acUnknown;
      U.Receiver.ParamOrdinal:= -1;
    end;
  end
  else
  begin
    U.Receiver:= Classify(AIndex, ARef.ReceiverText);
    if (U.Receiver.Cls = acUnknown) and C.IsCtor and
       (SameText(ARef.ReceiverText, C.OwnerName) or EndsText('.' + C.OwnerName, ARef.ReceiverText)) then
      U.Receiver.Cls:= acLocal;
  end;
  U.FileId:= FRoutines[AIndex].FileId;
  U.Line:= ARef.StartLine;
  U.ColAfter:= ARef.StartCol + Length(ARef.NameText);
  AUses.Add(U);
  Inc(FLibBound);
end;

procedure TPurityRun.CallRef(AIndex: Integer; const ARef: TReference; const ALines: TArray<string>;
  var ASum: TEffectSummary; var AChanged: Boolean; AUses: TList<TCalleeUse>);
var
  E      : TCallEdge;
  B      : TEffectSummary;
  U      : TCalleeUse;
  Witness: string;
  Key    : string;
  N      : Integer;
begin
  if FEdges.TryGetValue(ARef.Id, E) and (E.TargetSymbolId <> 0) then
  begin
    BoundCall(AIndex, ARef, E.TargetSymbolId, ALines, ASum, AChanged, AUses);
    Exit;
  end;
  if IsPurityAxiom(ARef.NameText) then Exit;
  if BuiltinSummary(ARef.NameText, B) then
  begin
    U:= Default(TCalleeUse);
    U.IsBuiltin:= True;
    U.Builtin:= B;
    U.Name:= ARef.NameText;
    U.Receiver:= Default(TArgInfo);
    U.Receiver.Cls:= acUnknown;
    U.Receiver.ParamOrdinal:= -1;
    U.FileId:= FRoutines[AIndex].FileId;
    U.Line:= ARef.StartLine;
    U.ColAfter:= ARef.StartCol + Length(ARef.NameText);
    AUses.Add(U);
    Exit;
  end;
  if (TPurityStage.LibraryEffects <> nil) and LibraryCall(AIndex, ARef, AUses) then Exit;
  Witness:= 'calls ' + ARef.NameText + ' (unbound';
  if Trim(ARef.ReceiverText) <> '' then Witness:= Witness + '; receiver ' + ARef.ReceiverText;
  ASum.AddFlag(efUnknown, Witness + ')', AChanged);
  Inc(FStats.UnboundCalls);
  Key:= LowerKey(ARef.NameText);
  if FUnbound.TryGetValue(Key, N) then FUnbound[Key]:= N + 1 else FUnbound.Add(Key, 1);
end;

procedure TPurityRun.MemberWrite(AIndex: Integer; const AReceiver, AName: string; var ASum: TEffectSummary; var AChanged: Boolean);
var
  Rcv    : TArgInfo;
  Witness: string;
begin
  Rcv:= Classify(AIndex, AReceiver);
  Witness:= 'writes ' + AReceiver + '.' + AName + ' (member)';
  case Rcv.Cls of
    acSelfOrField: ASum.AddFlag(efSelfFields, Witness, AChanged);
    acParam      : ASum.AddParam(Rcv.ParamOrdinal, Witness, AChanged);   { ordinal from the caller's own map (P3) }
    acLocal      : ;   { a non-escaping local: the write stays inside the caller }
  else
    ASum.AddFlag(efUnknown, Witness + ', receiver not classified', AChanged);
  end;
end;

procedure TPurityRun.MemberRef(AIndex: Integer; const ARef: TReference; const ALines: TArray<string>;
  var ASum: TEffectSummary; var AChanged: Boolean; AUses: TList<TCalleeUse>);
var
  E, M: TCallEdge;
begin
  { A paren-less method or constructor call (`TFoo.Create`, `List.Clear`) is a
    member-access ref carrying the call_edges row itself. }
  if FEdges.TryGetValue(ARef.Id, E) and (E.TargetSymbolId <> 0) then
  begin
    BoundCall(AIndex, ARef, E.TargetSymbolId, ALines, ASum, AChanged, AUses);
    Exit;
  end;
  if FMembers.TryGetValue(ARef.Id, M) then
  begin
    { FIX-3 (resolver 1.11.0-alpha): `uVars.GFlag := True` -- D22 binds a
      unit-qualified var, and the receiver is a UNIT, which Classify cannot
      place, so the write scored '?' "receiver not classified" while the same
      write spelled bare (`GFlag := True`) scored 'g'. A bound target that is
      a unit-level var/const is a global write, whatever names its unit. }
    if (M.MemberMode = MEMBER_MODE_WRITE) and (M.TargetSymbolId > 0) then
    begin
      var T: TSymbol:= SymbolById(M.TargetSymbolId);
      if (T.Kind in [skVarDecl, skConstDecl]) and (SymbolById(T.ParentId).Kind = skUnit) then
      begin
        ASum.AddFlag(efGlobal, 'writes ' + ARef.ReceiverText + '.' + ARef.NameText + ' (unit-level)', AChanged);
        Exit;
      end;
    end;
    if M.MemberMode = MEMBER_MODE_WRITE then MemberWrite(AIndex, ARef.ReceiverText, ARef.NameText, ASum, AChanged)
    else if (M.MemberMode = MEMBER_MODE_READ) and IsProcTypedTarget(M.TargetSymbolId) and IsImplicitProcCall(ALines, ARef) then
      ASum.AddFlag(efUnknown, 'reads procedural member ' + ARef.ReceiverText + '.' + ARef.NameText + ' (implicit call, target not followed)', AChanged);
    Exit;
  end;
  ASum.AddFlag(efUnknown, 'accesses ' + ARef.ReceiverText + '.' + ARef.NameText + ' (unbound member)', AChanged);
end;

procedure TPurityRun.ScanRoutine(AIndex: Integer; const ALines: TArray<string>; ARefs: TList<TReference>; AShallow: Boolean);
var
  Sum      : TEffectSummary;
  Changed  : Boolean;
  Facts    : TSymbolFacts;
  Scan     : TBodyScan;
  Gated    : Boolean;
  UseList  : TList<TCalleeUse>;
  CallLine : Integer;
  CallCol  : Integer;
begin
  Sum:= Default(TEffectSummary);
  Changed:= False;
  UseList:= TList<TCalleeUse>.Create;
  try
    if FFacts.TryGetValue(FRoutines[AIndex].Id, Facts) then ApplyFacts(AIndex, Facts, Sum, Changed);
    var Tk0: Int64:= TStopwatch.GetTimeStamp;
    Scan:= ScanBody(AIndex, ALines);
    Inc(FTkBody, TStopwatch.GetTimeStamp - Tk0);
    if Scan.HasWith then Sum.AddFlag(efUnknown, WITNESS_WITH, Changed);
    Gated:= (Scan.HasVarBlock or Scan.HasInlineVar) and (FCtx[AIndex].OwnLocals.Count = 0);
    if Gated then
    begin
      Sum.AddFlag(efUnknown, WITNESS_GATED, Changed);
      Inc(FStats.GatedIncomplete);
    end;
    if Scan.HasBareInherited then AddInheritedUse(AIndex, Sum, Changed, UseList);
    if ARefs <> nil then
    begin
      Tk0:= TStopwatch.GetTimeStamp;
      CollectEscapes(AIndex, ALines, ARefs);
      Inc(FTkEsc, TStopwatch.GetTimeStamp - Tk0);
      Tk0:= TStopwatch.GetTimeStamp;
      CallLine:= 0;
      CallCol:= 0;
      for var R in ARefs do
        if R.Kind = REF_KIND_WRITE then
        begin
          { Under the gate a name absent from the local table proves nothing. }
          if not Gated then NonLocalWrite(AIndex, R, Sum, Changed);
        end
        else if R.Kind = REF_KIND_CALL then
        begin
          CallLine:= R.StartLine;
          CallCol:= R.StartCol;
          CallRef(AIndex, R, ALines, Sum, Changed, UseList);
        end
        else if R.Kind = REF_KIND_READ then
        begin
          { 1.51.1 B04: a bare read the index bound to a LIBRARY function as a paren-less call
            (`if AFlag and BumpCounter then`) is a call -- the library summary, or unbound `?`. }
          if R.ExternalKind = EXTERNAL_KIND_PARENLESS_CALL then
            CallRef(AIndex, R, ALines, Sum, Changed, UseList)
          { FIX-3 part 2: a paren-less read of a procedural-type variable runs
            whatever it holds -- an unknown callee. }
          else if IsProcTypedTarget(R.SymbolId) and IsImplicitProcCall(ALines, R) then
            Sum.AddFlag(efUnknown, 'reads procedural variable ' + R.NameText + ' (implicit call, target not followed)', Changed);
        end
        else if R.Kind = REF_KIND_MEMBER then
        begin
          { `X.Foo(...)` is a call ref AND a member-access ref at one position;
            the call ref carries the binding, the twin carries nothing. }
          if (R.StartLine = CallLine) and (R.StartCol = CallCol) then Continue;
          MemberRef(AIndex, R, ALines, Sum, Changed, UseList);
        end;
      Inc(FTkRefLoop, TStopwatch.GetTimeStamp - Tk0);
    end;
    { Last, so a concrete witness found above (a field write from the facts)
      keeps the witness slot; the flag alone already makes the verdict '?'. }
    if AShallow then Sum.AddFlag(efUnknown, WITNESS_SHALLOW, Changed);
    FLocal[AIndex]:= Sum;
    FUses[AIndex]:= UseList.ToArray;
  finally
    UseList.Free;
  end;
end;

{ ------------------------------------------------------------------ fixpoint }

{ Lexes one call site's arguments on first need (P7) and classifies them
  against the CALLER's names; cached on the use so a line is lexed once. }
procedure TPurityRun.LexUse(AIndex, AUse: Integer);
var
  U    : TCalleeUse;
  Lines: TArray<string>;
  Texts: TArray<string>;
  T0   : Int64;
begin
  T0:= TStopwatch.GetTimeStamp;
  U:= FUses[AIndex][AUse];
  if LinesOf(U.FileId, Lines) and LexCallArguments(Lines, U.Line, U.ColAfter, Texts) then
  begin
    SetLength(U.Args, Length(Texts));
    for var K:= 0 to High(Texts) do U.Args[K]:= Classify(AIndex, Texts[K]);
    U.ArgsKnown:= True;
  end
  else
  begin
    U.Args:= nil;
    U.ArgsKnown:= False;
    Inc(FStats.UnlexableCalls);
  end;
  U.ArgsLexed:= True;
  FUses[AIndex][AUse]:= U;
  Inc(FLexTicks, TStopwatch.GetTimeStamp - T0);
end;

{ Folds use AUse of routine AIndex into ASum: the callee's CURRENT summary,
  translated through the call site. The one place both the fixpoint and the
  witness pass apply a use, so the two cannot disagree on what a use adds. }
procedure TPurityRun.ApplyUse(AIndex, AUse: Integer; var ASum: TEffectSummary; var AChanged: Boolean);
var
  T        : Integer;
  CalleeSum: TEffectSummary;
begin
  if FUses[AIndex][AUse].IsBuiltin then CalleeSum:= FUses[AIndex][AUse].Builtin  // dl:ok index-possibly-out-of-range@adbb -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
  else if FIndexOf.TryGetValue(FUses[AIndex][AUse].TargetId, T) then CalleeSum:= FSummary[T]
  else
  begin
    { BoundCall and AddInheritedUse both admit only targets that own a
      facts row, so this is unreachable today -- and it FAILS CLOSED
      anyway. Skipping the use would drop the callee's effects and move
      the caller TOWARDS proven, which is the one direction a purity
      verdict must never drift on its own. }
    ASum.AddFlag(efUnknown,
      'calls ' + FUses[AIndex][AUse].Name + ' (callee lost its facts row between load and fixpoint)', AChanged);
    Exit;
  end;
  if (Length(CalleeSum.Params) > 0) and not FUses[AIndex][AUse].ArgsLexed then LexUse(AIndex, AUse);
  TranslateCallee(CalleeSum, FUses[AIndex][AUse].Name, FUses[AIndex][AUse].Args, FUses[AIndex][AUse].ArgsKnown,
    FUses[AIndex][AUse].Receiver, ASum, AChanged);
end;

procedure TPurityRun.FixPoint;
var
  CallersOf: TObjectDictionary<Int64, TList<Integer>>;
  Callers  : TList<Integer>;
  Queue    : TQueue<Integer>;
  InQueue  : TArray<Boolean>;
  I        : Integer;
  Changed  : Boolean;
begin
  CallersOf:= TObjectDictionary<Int64, TList<Integer>>.Create([doOwnsValues]);
  Queue:= TQueue<Integer>.Create;
  try
    SetLength(InQueue, Length(FRoutines));
    for I:= 0 to High(FRoutines) do
    begin
      { INCR18 step 4: outside the scope the stored verdict is a CONSTANT -- never queued,
        never a caller of anything queued, read by the uses that target it. }
      if not FInScope[I] then
      begin
        FSummary[I]:= StoredSummary(I);
        Continue;
      end;
      FSummary[I]:= FLocal[I];
      FSummary[I].Params:= Copy(FLocal[I].Params);   { the witness pass reads FLocal again: no shared array }
      for var U in FUses[I] do
        if U.TargetId <> 0 then
        begin
          if not CallersOf.TryGetValue(U.TargetId, Callers) then
          begin
            Callers:= TList<Integer>.Create;
            CallersOf.Add(U.TargetId, Callers);
          end;
          Callers.Add(I);
        end;
      Queue.Enqueue(I);
      InQueue[I]:= True;
    end;
    FVisits:= 0;
    { Monotone over a finite lattice: each visit can only ADD flags or
      ordinals to FSummary[I] (ordinals are bounded by the caller's own
      parameter count, P3), and a caller is re-queued only when its callee
      actually changed -- so the queue drains. }
    while Queue.Count > 0 do
    begin
      I:= Queue.Dequeue;
      InQueue[I]:= False;
      Inc(FVisits);
      Changed:= False;
      for var J:= 0 to High(FUses[I]) do ApplyUse(I, J, FSummary[I], Changed);
      if Changed and CallersOf.TryGetValue(FRoutines[I].Id, Callers) then
        for var C in Callers do
          if not InQueue[C] then
          begin
            Queue.Enqueue(C);
            InQueue[C]:= True;
          end;
    end;
    if FScopeCount > 0 then FStats.Rounds:= (FVisits + FScopeCount - 1) div FScopeCount;
  finally
    Queue.Free;
    CallersOf.Free;
  end;
end;

{ INCR18 step 4: THE WITNESS IS A FUNCTION OF THE FIXPOINT, NOT OF THE QUEUE ORDER.
  AddFlag / AddParam keep the FIRST change as the witness, and inside the
  fixpoint that is whichever callee happened to have grown when the caller was
  visited -- so a scoped run, whose outside callees enter already final, would
  name a different first blocker than a whole run on the same database, for
  the same verdict. Re-deriving each witness here from the routine's own local
  summary plus its callees' FINAL summaries makes it depend on the answer
  alone. The flags are the fixpoint equation itself, so they come out
  unchanged; only the witness is replaced, and only when they agree.

  WHICH USE NAMES THE BLOCKER. Call order alone is not enough: inside a cycle
  it can make every member point at another member (A1 -> "calls B1", B1 ->
  "calls A1") and the chain of witnesses never reaches the write that caused
  them -- run_purity_stage check 9 is exactly that shape. So, per strongly
  connected component of the call graph:
    1. the routine's own LOCAL effect, when it has one;
    2. else a contributing use whose callee is OUTSIDE the component (or a
       built-in), in call order -- such a routine is a source of the component;
    3. else the contributing in-component callee NEAREST a source (BFS over
       the component's contributing edges), ties in call order.
  The witness chain then strictly descends and always ends at a real write.
  A component that holds a routine of the scope lies wholly inside it (its
  members are each other's transitive callers), so the components, and with
  them every witness, are the same in a scoped and a whole run.
  This is what changes symbol_facts.effect_witness on a database written by an
  earlier engine, and why the change bills DRAGLINT_RESOLVER_VERSION. }

{ True when use AUse of AIndex calls a routine of the scope; ATarget is it. }
function TPurityRun.InScopeTarget(AIndex, AUse: Integer; out ATarget: Integer): Boolean;
begin
  Result:= (not FUses[AIndex][AUse].IsBuiltin) and FIndexOf.TryGetValue(FUses[AIndex][AUse].TargetId, ATarget)  // dl:ok index-possibly-out-of-range@1ff3 -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
           and FInScope[ATarget];  // dl:ok index-possibly-out-of-range@9d48 -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
end;

{ True when use AUse of AIndex stays inside AIndex's own component. }
function TPurityRun.SameComp(AIndex, AUse: Integer): Boolean;
var
  T: Integer;
begin
  Result:= InScopeTarget(AIndex, AUse, T) and (FComp[T] = FComp[AIndex]);  // dl:ok index-possibly-out-of-range@8945 -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
end;

{ Strongly connected components of the scope's call graph (Tarjan, iterative:
  a recursive walk would overflow on a deep call chain). FComp[I] is the
  component id, -1 outside the scope. }
procedure TPurityRun.ComputeComponents;
var
  Low, Num: TArray<Integer>;
  OnStack : TArray<Boolean>;
  Stack   : TStack<Integer>;
  Work    : TStack<TPair<Integer, Integer>>;   // (routine, next use to try)
  Counter : Integer;
  NComp   : Integer;
  V, J, T : Integer;

  { Advances V's frame from use J: descends into the first unvisited target
    (True), or lowers V's link over the visited ones and reports done. }
  function Descend: Boolean;
  begin
    Result:= False;
    while J <= High(FUses[V]) do
    begin
      if InScopeTarget(V, J, T) then
      begin
        if Num[T] < 0 then
        begin
          Work.Push(TPair<Integer, Integer>.Create(V, J + 1));
          Work.Push(TPair<Integer, Integer>.Create(T, 0));
          Exit(True);
        end;
        if OnStack[T] then Low[V]:= Min(Low[V], Num[T]);
      end;
      Inc(J);
    end;
  end;

  procedure CloseComponent;
  begin
    repeat
      T:= Stack.Pop;
      OnStack[T]:= False;
      FComp[T]:= NComp;
    until T = V;
    Inc(NComp);
  end;

begin
  SetLength(FComp, Length(FRoutines));
  SetLength(Low, Length(FRoutines));
  SetLength(Num, Length(FRoutines));
  SetLength(OnStack, Length(FRoutines));
  for var I:= 0 to High(FRoutines) do  // dl:ok index-possibly-out-of-range@0be8 -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
  begin
    FComp[I]:= -1;
    Num[I]:= -1;
  end;
  Counter:= 0;
  NComp:= 0;
  Stack:= TStack<Integer>.Create;
  Work := TStack<TPair<Integer, Integer>>.Create;
  try
    for var Root:= 0 to High(FRoutines) do  // dl:ok index-possibly-out-of-range@57a1 -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
    begin
      if (not FInScope[Root]) or (Num[Root] >= 0) then Continue;
      Work.Push(TPair<Integer, Integer>.Create(Root, 0));
      while Work.Count > 0 do
      begin
        V:= Work.Peek.Key;
        J:= Work.Pop.Value;
        if J = 0 then
        begin
          Num[V]:= Counter;
          Low[V]:= Counter;
          Inc(Counter);
          Stack.Push(V);
          OnStack[V]:= True;
        end;
        if Descend then Continue;
        if Low[V] = Num[V] then CloseComponent;
        { Back in the parent (its resume frame is next): a child still on the
          stack shares the parent's component and lowers its link. }
        if (Work.Count > 0) and OnStack[V] then Low[Work.Peek.Key]:= Min(Low[Work.Peek.Key], Low[V]);
      end;
    end;
  finally
    Work.Free;
    Stack.Free;
  end;
end;

{ FContrib[I][J]: use J adds anything at all. FRank[I]: 0 for a SOURCE of its
  component (a local effect, or a contributing use that leaves the component or
  is a built-in), else the BFS distance to one over contributing in-component
  uses; MaxInt when it has no effect. }
procedure TPurityRun.ComputeSourceRanks;
var
  RevIn  : TObjectDictionary<Integer, TList<Integer>>;
  Queue  : TQueue<Integer>;
  Probe  : TEffectSummary;
  Changed: Boolean;
  Source : Boolean;
  T      : Integer;
  L      : TList<Integer>;
begin
  SetLength(FContrib, Length(FRoutines));
  SetLength(FRank, Length(FRoutines));
  RevIn:= TObjectDictionary<Integer, TList<Integer>>.Create([doOwnsValues]);
  Queue:= TQueue<Integer>.Create;
  try
    for var I:= 0 to High(FRoutines) do  // dl:ok index-possibly-out-of-range@0be8 -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
    begin
      FRank[I]:= MaxInt;
      if not FInScope[I] then Continue;
      SetLength(FContrib[I], Length(FUses[I]));
      Source:= not FLocal[I].IsEffectFree;
      for var J:= 0 to High(FUses[I]) do
      begin
        Probe:= Default(TEffectSummary);
        Changed:= False;
        ApplyUse(I, J, Probe, Changed);
        FContrib[I][J]:= Changed;
        if not Changed then Continue;
        if not SameComp(I, J) then
        begin
          Source:= True;
          Continue;
        end;
        InScopeTarget(I, J, T);
        if not RevIn.TryGetValue(T, L) then
        begin
          L:= TList<Integer>.Create;
          RevIn.Add(T, L);
        end;
        L.Add(I);
      end;
      if Source then
      begin
        FRank[I]:= 0;
        Queue.Enqueue(I);
      end;
    end;
    while Queue.Count > 0 do
    begin
      T:= Queue.Dequeue;  // dl:ok index-possibly-out-of-range@aab4 -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
      if not RevIn.TryGetValue(T, L) then Continue;
      for var C in L do
        if FRank[C] = MaxInt then
        begin
          FRank[C]:= FRank[T] + 1;
          Queue.Enqueue(C);
        end;
    end;
  finally
    Queue.Free;
    RevIn.Free;
  end;
end;

{ AIndex's summary rebuilt in WITNESS order -- local, then the uses that leave
  the component in call order, then the in-component uses nearest a source --
  and finally every use, so the flags are complete. }
function TPurityRun.CanonicalSummaryOf(AIndex: Integer): TEffectSummary;
var
  Changed: Boolean;
  Best   : Integer;
  T      : Integer;
begin
  Result:= FLocal[AIndex];  // dl:ok index-possibly-out-of-range@e89d -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
  Result.Params:= Copy(FLocal[AIndex].Params);   { AddParam must not write through to FLocal }
  Changed:= False;
  for var J:= 0 to High(FUses[AIndex]) do
    if FContrib[AIndex][J] and not SameComp(AIndex, J) then ApplyUse(AIndex, J, Result, Changed);
  if Result.Witness = '' then
  begin
    Best:= MaxInt;
    for var J:= 0 to High(FUses[AIndex]) do
      if FContrib[AIndex][J] and SameComp(AIndex, J) and InScopeTarget(AIndex, J, T) then Best:= Min(Best, FRank[T]);
    for var J:= 0 to High(FUses[AIndex]) do
      if FContrib[AIndex][J] and SameComp(AIndex, J) and InScopeTarget(AIndex, J, T) and (FRank[T] = Best) then
        ApplyUse(AIndex, J, Result, Changed);
  end;
  for var J:= 0 to High(FUses[AIndex]) do ApplyUse(AIndex, J, Result, Changed);
end;

procedure TPurityRun.CanonicalWitnesses;
var
  W: TEffectSummary;
begin
  ComputeComponents;
  ComputeSourceRanks;
  for var I:= 0 to High(FRoutines) do  // dl:ok index-possibly-out-of-range@0be8 -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
  begin
    if not FInScope[I] then Continue;
    W:= CanonicalSummaryOf(I);
    if W.Encode = FSummary[I].Encode then FSummary[I].Witness:= W.Witness;
  end;
end;

{ --------------------------------------------------------------------- write }

procedure TPurityRun.WriteVerdicts;
var
  Rows: TList<TEffectFactRow>;
  Row : TEffectFactRow;
begin
  FStats.Routines:= Length(FRoutines);
  FStats.EffectFree:= 0;
  Rows:= TList<TEffectFactRow>.Create;
  try
    for var I:= 0 to High(FRoutines) do  // dl:ok index-possibly-out-of-range@0be8 -- REVIEWED 2026-11-19 (INCR18 step 4): a per-routine parallel array, SetLength'd to Length(FRoutines) (Load, DetermineScope, ComputeComponents, ComputeSourceRanks) before any index over FRoutines reaches it
    begin
      { Counted over EVERY routine, so the summary line means the same thing
        on a scoped run; written for the scope only -- an outside row already
        holds exactly this value. }
      if FSummary[I].IsEffectFree then Inc(FStats.EffectFree);
      if not FInScope[I] then Continue;
      Row.SymbolId:= FRoutines[I].Id;
      Row.EffectFree:= Ord(FSummary[I].IsEffectFree);
      Row.Summary:= FSummary[I].Encode;
      Row.Witness:= FSummary[I].Witness;
      Rows.Add(Row);
    end;
    FStore.PutEffectFacts(Rows.ToArray);
  finally
    Rows.Free;
  end;
  { The stamp the NEXT run compares before it takes a scope (InputsStamp). }
  if FStore.GetMetaValue(META_PURITY_INPUTS) <> FInputsNow then FStore.SetMetaValue(META_PURITY_INPUTS, FInputsNow);
end;

procedure TPurityRun.Report(ALoad, AScope, AScan, AFix, AWrite: Double);
var
  Tally  : TList<TPair<string, Integer>>;
  Top    : string;
  Percent: Integer;
begin
  Tally:= TList<TPair<string, Integer>>.Create;
  try
    for var P in FUnbound do Tally.Add(P);
    Tally.Sort(TComparer<TPair<string, Integer>>.Construct(
      function(const L, R: TPair<string, Integer>): Integer
      begin
        Result:= R.Value - L.Value;
        if Result = 0 then Result:= CompareStr(L.Key, R.Key);
      end));
    SetLength(FStats.TopUnbound, Min(TOP_UNBOUND_COUNT, Tally.Count));
    for var I:= 0 to High(FStats.TopUnbound) do
      FStats.TopUnbound[I]:= Tally[I].Key + ' (' + IntToStr(Tally[I].Value) + ')';
  finally
    Tally.Free;
  end;
  Top:= if Length(FStats.TopUnbound) > 0 then string.Join(', ', FStats.TopUnbound) else TOP_NONE;
  Percent:= if FStats.Routines > 0 then Round(FStats.EffectFree * PERCENT_SCALE / FStats.Routines) else 0;
  Writeln(Format('resolve: purity -- %d routine(s), %d effect-free (%d%%), %d unbound call ref(s) [top: %s], ' +
                 '%d unlexable call(s), %d stale file(s), %d gated (local table incomplete), %d pass(es)',
    [FStats.Routines, FStats.EffectFree, Percent, FStats.UnboundCalls, Top,
     FStats.UnlexableCalls, FStats.StaleFiles, FStats.GatedIncomplete, FStats.Rounds]));
  { INCR18 step 4: its own line, so the line above keeps its shape. On a scoped run the
    unbound / unlexable / stale / gated counts and the passes above are the SCOPE's -- the
    routines this run re-derived; routines and effect-free always count every routine. }
  if FScoped then
    Writeln(Format('resolve: purity scope -- %d of %d routine(s) re-derived in %d file(s)%s',
      [FScopeCount, Length(FRoutines), FScopeFiles, (if FScopeNote <> '' then '; ' + FScopeNote else '')]))
  else if FScopeNote <> '' then
    Writeln('resolve: purity scope -- whole database: ' + FScopeNote);
  Flush(Output);
  if TPurityStage.LibraryEffects <> nil then Writeln(Format('resolve: purity library effects -- %d call ref(s) took a library summary, %d distinct target(s)', [FLibBound, FLibCallees.Count]));
  if GetEnvironmentVariable('DRAGLINT_PROFILE') <> '' then
    Writeln(ErrOutput, Format('purity: load %.1fs (scope %.1fs)  scan %.1fs  lex %.1fs  fixpoint %.1fs  write %.1fs  ' +
                              '(%d visit(s); lex is part of fixpoint; %d file re-read(s) after a line-cache eviction, %d MB cached at the end)',
      [ALoad, AScope, AScan, FLexTicks / TStopwatch.Frequency, AFix, AWrite, FVisits, FLineReReads,
       Round(FLineChars * SizeOf(Char) / BYTES_PER_MB)]));
  if GetEnvironmentVariable('DRAGLINT_PROFILE') <> '' then
    Writeln(ErrOutput, Format('purity: scan = file %.1fs  refs %.1fs  body %.1fs  escapes %.1fs  ref-loop %.1fs; symbol lookups %d: single-row fetches %d in %.2fs, per-file preload %d row(s) in %.2fs',  // dl:ok locale-sensitive-conversion@39b2 -- diagnostic / batch text, not data; locale formatting is harmless here -- SLZ-S10 2026-11-22
      [FTkFile / TStopwatch.Frequency, FTkRefs / TStopwatch.Frequency, FTkBody / TStopwatch.Frequency,
       FTkEsc / TStopwatch.Frequency, FTkRefLoop / TStopwatch.Frequency,
       FSymLookups, FSymMiss, FTkSym / TStopwatch.Frequency, FPreloadRows, FTkPreload / TStopwatch.Frequency]));
end;

function TPurityRun.Execute: TPurityStats;
var
  Sw                       : TStopwatch;
  TLoad, TScope, TScan, TFix, TWrite: Double;
begin
  FStats:= Default(TPurityStats);
  Sw:= TStopwatch.StartNew;
  BeatStep('purity load');
  Load;
  var SwScope: TStopwatch:= TStopwatch.StartNew;
  DetermineScope;
  TScope:= SecondsOf(SwScope);
  LoadBindings;
  BuildContexts;
  TLoad:= SecondsOf(Sw);
  Sw:= TStopwatch.StartNew;
  BeatStep('purity scan', Length(FRoutines));
  ScanFiles;
  TScan:= SecondsOf(Sw);
  Sw:= TStopwatch.StartNew;
  BeatStep('purity fixpoint');
  FixPoint;
  CanonicalWitnesses;
  TFix:= SecondsOf(Sw);
  Sw:= TStopwatch.StartNew;
  BeatStep('purity write', Length(FRoutines));
  WriteVerdicts;
  TWrite:= SecondsOf(Sw);
  Report(TLoad, TScope, TScan, TFix, TWrite);
  Result:= FStats;
end;

{ -------------------------------------------------------------- TPurityStage }

class function TPurityStage.Run(const AStore: ISymbolStore): TPurityStats;
var
  R: TPurityRun;
begin
  R:= TPurityRun.Create(AStore);
  try
    Result:= R.Execute;
  finally
    R.Free;
  end;
end;

end.
