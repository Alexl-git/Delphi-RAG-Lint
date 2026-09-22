/// <summary>Purity v2: the `purity` resolve stage. Computes one effect summary
/// per routine with a body from rows the index already holds plus the source
/// text it points at, runs the greatest-fixpoint worklist over call_edges, and
/// writes symbol_facts.effect_free / effect_summary / effect_witness.</summary>
/// <remarks>Resolve surface (tests\resolver-surface.txt): changing anything
/// here changes what is WRITTEN and bills DRAGLINT_RESOLVER_VERSION, never the
/// extractor. Whole-DB every run (the fixpoint is sub-second on a project DB);
/// source is read at most once per file. Prints `resolve: purity -- ...` on
/// stdout, the per-phase split on stderr under DRAGLINT_PROFILE.
/// The lattice, the axiom and built-in tables, the argument lexer, the body
/// scanner and the callee -> caller translation live in
/// DRagLint.Analysis.Purity; this unit only drives them against the store.</remarks>
unit DRagLint.Analysis.PurityStage;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Analysis.Purity;

type
  /// <summary>What one run counted -- printed on the `resolve: purity` line and
  /// returned for tests.</summary>
  /// <remarks><c>Rounds</c> is the number of worklist PASSES: the visits the
  /// fixpoint made divided by the routine count, rounded up. <c>TopUnbound</c>
  /// holds the ten commonest unbound callee names as <c>'name (count)'</c>,
  /// lowercased, commonest first.</remarks>
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
  TPurityStage = class
  public
    /// <summary>Runs the whole-DB purity pass and persists the verdicts.</summary>
    /// <param name="AStore">An open, migrated, writable store. PutEffectFacts
    /// opens its own transaction, so no file transaction may be open.</param>
    /// <returns>Counts for the summary line.</returns>
    /// <exception cref="EInvalidOperation">Propagated from PutEffectFacts when
    /// the store has no effect_* columns (a read-only open).</exception>
    /// <remarks>Every routine that owns a symbol_facts row with body_loc &gt; 0
    /// receives a verdict; a routine in a file whose on-disk mtime no longer
    /// matches files.mtime_unix is `?` with the witness
    /// <c>source changed since indexing</c> (plan ruling 7). Complexity: one
    /// pass over the refs of every file plus the fixpoint, which visits each
    /// routine once per change of a callee it depends on.</remarks>
    class function Run(const AStore: ISymbolStore): TPurityStats; static;
  end;

implementation

uses
  System.Diagnostics,
  System.Generics.Defaults,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  DRagLint.Core.FileTime;

const
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
  ANCESTOR_INTERFACE  = 'interface';
  NAME_RESULT         = 'result';
  NAME_SELF           = 'Self';
  NAME_ADDR           = 'Addr';
  WORD_INHERITED      = 'inherited';
  TOP_NONE            = 'none';

  WITNESS_STALE           = 'source changed since indexing';
  WITNESS_WITH            = 'with statement';
  WITNESS_GATED           = 'local table incomplete (var declarations without local_var rows)';
  WITNESS_INHERITED_OUT   = 'inherited (ancestor method outside this DB)';
  WITNESS_MUTATES_CAPPED  = 'mutates more parameters than recorded';
  WITNESS_NO_FACTS        = 'no facts for callee';
  WITNESS_VIRTUAL         = 'virtual/interface dispatch';
  WITNESS_NOT_ROUTINE     = 'target is not a routine';

  ROUTINE_KINDS = [skProcedure, skFunction, skMethod, skConstructor, skDestructor];
  CAST_KINDS    = [skClass, skInterface, skRecord, skEnum, skTypeAlias];
  CLASS_KINDS   = [skClass, skRecord, skInterface, skForm];
  FIELD_KINDS   = [skField, skComponent];

type
  TSymbolKinds = set of TSymbolKind;

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
  // dl:ok god-class@e3b0, high-response@e3b0 -- REVIEWED 2026-09-22: the fields ARE the loaded index tables (routines, facts, edges, members, params, locals, fields, stamps, the bounded line cache) and the methods are the five phases of ONE pass over them: load, contexts, scan, fixpoint, write. Splitting them would give the fixpoint a second owner of the same tables for no behavioural gain, and the model (lattice, lexer, body scanner) already lives in DRagLint.Analysis.Purity.
  TPurityRun = class
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
    FStats       : TPurityStats;
    FVisits      : Integer;
    FLexTicks    : Int64;
    function  NewSet: TNameSet;
    function  NewMap: TParamMap;
    function  SymbolById(AId: Int64): TSymbol;
    function  ClassIdOf(const ASym: TSymbol): Int64;
    function  AncestorsOf(AClassId: Int64): TArray<TTypeAncestor>;
    function  OwnMembersOf(AClassId: Int64; const AKinds: TSymbolKinds): TNameSet;
    function  FieldsOfClass(AClassId: Int64): TNameSet;
    function  PropsOfClass(AClassId: Int64): TNameSet;
    function  DeclaringAncestorOfField(AClassId: Int64; const AName: string): string;
    function  ReadFileLines(AFileId: Int64; out ALines: TArray<string>): Boolean;
    procedure CacheLines(AFileId: Int64; const ALines: TArray<string>);
    function  LinesOf(AFileId: Int64; out ALines: TArray<string>): Boolean;
    function  IsBound(const ARef: TReference): Boolean;
    function  Classify(AIndex: Integer; const AText: string): TArgInfo;
    function  SelfReceiver: TArgInfo;
    function  ReceiverOf(AIndex: Integer; const AText: string; const ATarget: TSymbol; AIsInherited: Boolean): TArgInfo;
    function  PrecededByInherited(const ALines: TArray<string>; const ARef: TReference): Boolean;
    function  EnclosingCall(const ALine: string; ACol: Integer; ACalls: TList<TReference>; ALineNo: Integer): Integer;
    procedure MarkEscaping(AIndex: Integer; const AName: string);
    procedure Load;
    procedure BuildContexts;
    procedure ScanFiles;
    procedure ScanRoutine(AIndex: Integer; const ALines: TArray<string>; ARefs: TList<TReference>);
    function  ScanBody(AIndex: Integer; const ALines: TArray<string>): TBodyScan;
    procedure ApplyFacts(AIndex: Integer; const AFacts: TSymbolFacts; var ASum: TEffectSummary; var AChanged: Boolean);
    procedure AddInheritedUse(AIndex: Integer; var ASum: TEffectSummary; var AChanged: Boolean; AUses: TList<TCalleeUse>);
    procedure CollectEscapes(AIndex: Integer; const ALines: TArray<string>; ARefs: TList<TReference>);
    procedure NonLocalWrite(AIndex: Integer; const ARef: TReference; var ASum: TEffectSummary; var AChanged: Boolean);
    procedure BoundCall(AIndex: Integer; const ARef: TReference; ATargetId: Int64; const ALines: TArray<string>;
      var ASum: TEffectSummary; var AChanged: Boolean; AUses: TList<TCalleeUse>);
    procedure CallRef(AIndex: Integer; const ARef: TReference; const ALines: TArray<string>;
      var ASum: TEffectSummary; var AChanged: Boolean; AUses: TList<TCalleeUse>);
    procedure MemberRef(AIndex: Integer; const ARef: TReference; const ALines: TArray<string>;
      var ASum: TEffectSummary; var AChanged: Boolean; AUses: TList<TCalleeUse>);
    procedure MemberWrite(AIndex: Integer; const AReceiver, AName: string; var ASum: TEffectSummary; var AChanged: Boolean);
    procedure LexUse(AIndex, AUse: Integer);
    procedure FixPoint;
    procedure WriteVerdicts;
    procedure Report(ALoad, AScan, AFix, AWrite: Double);
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
  FStamps     := TDictionary<string, Int64>.Create(TIStringComparer.Ordinal);
  FLines      := TDictionary<Int64, TArray<string>>.Create;
  FLineOrder  := TQueue<Int64>.Create;
  FSymCache   := TDictionary<Int64, TSymbol>.Create;
  FOwnedSets  := TObjectList<TNameSet>.Create(True);
  FOwnedMaps  := TObjectList<TParamMap>.Create(True);
  FUnbound    := TDictionary<string, Integer>.Create;
  FEmptySet   := NewSet;
  FEmptyMap   := NewMap;
end;

destructor TPurityRun.Destroy;
begin
  FUnbound.Free;
  FOwnedMaps.Free;
  FOwnedSets.Free;
  FSymCache.Free;
  FLineOrder.Free;
  FLines.Free;
  FStamps.Free;
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
  if not FSymCache.TryGetValue(AId, Result) then
  begin
    Result:= FStore.GetSymbolById(AId);
    FSymCache.Add(AId, Result);
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

function TPurityRun.OwnMembersOf(AClassId: Int64; const AKinds: TSymbolKinds): TNameSet;
begin
  Result:= NewSet;
  for var C in FStore.FindAllChildSymbols(AClassId) do
    if C.Kind in AKinds then Result.AddOrSetValue(LowerKey(C.Name), True);
end;

{ Own fields plus every resolved ancestor's, cached per class. }
function TPurityRun.FieldsOfClass(AClassId: Int64): TNameSet;
var
  Own: TNameSet;
begin
  if AClassId = 0 then Exit(FEmptySet);
  if FFieldsOf.TryGetValue(AClassId, Result) then Exit;
  Own:= OwnMembersOf(AClassId, FIELD_KINDS);
  FOwnFieldsOf.Add(AClassId, Own);
  Result:= NewSet;
  for var K in Own.Keys do Result.AddOrSetValue(K, True);
  for var Anc in AncestorsOf(AClassId) do
    if Anc.Resolved then
      for var C in FStore.FindAllChildSymbols(Anc.SymbolId) do
        if C.Kind in FIELD_KINDS then Result.AddOrSetValue(LowerKey(C.Name), True);
  FFieldsOf.Add(AClassId, Result);
end;

function TPurityRun.PropsOfClass(AClassId: Int64): TNameSet;
begin
  if AClassId = 0 then Exit(FEmptySet);
  if FPropsOf.TryGetValue(AClassId, Result) then Exit;
  Result:= OwnMembersOf(AClassId, [skProperty]);
  for var Anc in AncestorsOf(AClassId) do
    if Anc.Resolved then
      for var C in FStore.FindAllChildSymbols(Anc.SymbolId) do
        if C.Kind = skProperty then Result.AddOrSetValue(LowerKey(C.Name), True);
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
    if (NameEnd <= P) and (Trim(Copy(Masked, NameEnd, P - NameEnd)) = '') then
      if (Result < 0) or (ACalls[I].StartCol > ACalls[Result].StartCol) then Result:= I;
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
  for var E in FStore.DumpAllCallEdges do FEdges.AddOrSetValue(E.RefId, E);
  for var M in FStore.DumpAllMemberAccesses do FMembers.AddOrSetValue(M.RefId, M);
  for var S in FStore.GetAllFileStamps do FStamps.AddOrSetValue(S.Path, S.MTimeUnix);
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
begin
  ByParent:= TObjectDictionary<Int64, TList<TSymbol>>.Create([doOwnsValues]);
  try
    for var P in FStore.FindSymbolsByKind(KIND_TEXT_PARAM, False, MaxInt) do
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
  for var L in FStore.FindSymbolsByKind(KIND_TEXT_LOCAL_VAR, False, MaxInt) do
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
    FCtx[I].ClassId:= ClassIdOf(FRoutines[I]);
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
begin
  I:= 0;
  while I <= High(FRoutines) do
  begin
    FileId:= FRoutines[I].FileId;
    J:= I;
    while (J <= High(FRoutines)) and (FRoutines[J].FileId = FileId) do Inc(J);
    { [I, J) is this file's routines (FindSymbolsWithFacts orders by file). }
    Path:= FStore.GetFilePath(FileId);
    Stale:= not (TryGetFileMTimeUnix(Path, DiskUnix) and FStamps.TryGetValue(Path, Stored) and (DiskUnix = Stored));
    { An unreadable file IS the stale case (ruling 7): every routine in it is
      marked unknown with the stale witness below, which is the report. }
    if not Stale then Stale:= not ReadFileLines(FileId, Lines);
    if Stale then
    begin
      Inc(FStats.StaleFiles);
      for var K:= I to J - 1 do
      begin
        Changed:= False;
        FLocal[K]:= Default(TEffectSummary);
        FLocal[K].AddFlag(efUnknown, WITNESS_STALE, Changed);
        FUses[K]:= nil;
      end;
      I:= J;
      Continue;
    end;
    CacheLines(FileId, Lines);
    ByRoutine:= TObjectDictionary<Int64, TList<TReference>>.Create([doOwnsValues]);
    try
      for var R in FStore.GetReferencesFromFile(FileId) do
      begin
        if R.EnclosingSymbolId = 0 then Continue;
        if not ((R.Kind = REF_KIND_CALL) or (R.Kind = REF_KIND_READ) or (R.Kind = REF_KIND_WRITE) or (R.Kind = REF_KIND_MEMBER)) then Continue;
        if not ByRoutine.TryGetValue(R.EnclosingSymbolId, RefList) then
        begin
          RefList:= TList<TReference>.Create;
          ByRoutine.Add(R.EnclosingSymbolId, RefList);
        end;
        RefList.Add(R);
      end;
      for var K:= I to J - 1 do
      begin
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
        ScanRoutine(K, Lines, RefList);
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
        ASum.AddParam(K, 'writes through parameter #' + IntToStr(K) + ' (' + Name + ')', AChanged)
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
  if not (T.Kind in ROUTINE_KINDS) then
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
    if M.MemberMode = MEMBER_MODE_WRITE then MemberWrite(AIndex, ARef.ReceiverText, ARef.NameText, ASum, AChanged);
    Exit;
  end;
  ASum.AddFlag(efUnknown, 'accesses ' + ARef.ReceiverText + '.' + ARef.NameText + ' (unbound member)', AChanged);
end;

procedure TPurityRun.ScanRoutine(AIndex: Integer; const ALines: TArray<string>; ARefs: TList<TReference>);
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
    Scan:= ScanBody(AIndex, ALines);
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
      CollectEscapes(AIndex, ALines, ARefs);
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
        else if R.Kind = REF_KIND_MEMBER then
        begin
          { `X.Foo(...)` is a call ref AND a member-access ref at one position;
            the call ref carries the binding, the twin carries nothing. }
          if (R.StartLine = CallLine) and (R.StartCol = CallCol) then Continue;
          MemberRef(AIndex, R, ALines, Sum, Changed, UseList);
        end;
    end;
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

procedure TPurityRun.FixPoint;
var
  CallersOf: TObjectDictionary<Int64, TList<Integer>>;
  Callers  : TList<Integer>;
  Queue    : TQueue<Integer>;
  InQueue  : TArray<Boolean>;
  I, T     : Integer;
  Changed  : Boolean;
  CalleeSum: TEffectSummary;
begin
  CallersOf:= TObjectDictionary<Int64, TList<Integer>>.Create([doOwnsValues]);
  Queue:= TQueue<Integer>.Create;
  try
    SetLength(InQueue, Length(FRoutines));
    for I:= 0 to High(FRoutines) do
    begin
      FSummary[I]:= FLocal[I];
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
      for var J:= 0 to High(FUses[I]) do
      begin
        if FUses[I][J].IsBuiltin then CalleeSum:= FUses[I][J].Builtin
        else if FIndexOf.TryGetValue(FUses[I][J].TargetId, T) then CalleeSum:= FSummary[T]
        else
        begin
          { BoundCall and AddInheritedUse both admit only targets that own a
            facts row, so this is unreachable today -- and it FAILS CLOSED
            anyway. Skipping the use would drop the callee's effects and move
            the caller TOWARDS proven, which is the one direction a purity
            verdict must never drift on its own. }
          FSummary[I].AddFlag(efUnknown,
            'calls ' + FUses[I][J].Name + ' (callee lost its facts row between load and fixpoint)', Changed);
          Continue;
        end;
        if (Length(CalleeSum.Params) > 0) and not FUses[I][J].ArgsLexed then LexUse(I, J);
        TranslateCallee(CalleeSum, FUses[I][J].Name, FUses[I][J].Args, FUses[I][J].ArgsKnown,
          FUses[I][J].Receiver, FSummary[I], Changed);
      end;
      if Changed and CallersOf.TryGetValue(FRoutines[I].Id, Callers) then
        for var C in Callers do
          if not InQueue[C] then
          begin
            Queue.Enqueue(C);
            InQueue[C]:= True;
          end;
    end;
    if Length(FRoutines) > 0 then FStats.Rounds:= (FVisits + High(FRoutines)) div Length(FRoutines);
  finally
    Queue.Free;
    CallersOf.Free;
  end;
end;

{ --------------------------------------------------------------------- write }

procedure TPurityRun.WriteVerdicts;
var
  Rows: TArray<TEffectFactRow>;
begin
  SetLength(Rows, Length(FRoutines));
  FStats.Routines:= Length(FRoutines);
  FStats.EffectFree:= 0;
  for var I:= 0 to High(FRoutines) do
  begin
    Rows[I].SymbolId:= FRoutines[I].Id;
    Rows[I].EffectFree:= Ord(FSummary[I].IsEffectFree);
    Rows[I].Summary:= FSummary[I].Encode;
    Rows[I].Witness:= FSummary[I].Witness;
    Inc(FStats.EffectFree, Rows[I].EffectFree);
  end;
  FStore.PutEffectFacts(Rows);
end;

procedure TPurityRun.Report(ALoad, AScan, AFix, AWrite: Double);
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
  Flush(Output);
  if GetEnvironmentVariable('DRAGLINT_PROFILE') <> '' then
    Writeln(ErrOutput, Format('purity: load %.1fs  scan %.1fs  lex %.1fs  fixpoint %.1fs  write %.1fs  ' +
                              '(%d visit(s); lex is part of fixpoint; %d file re-read(s) after a line-cache eviction, %d MB cached at the end)',
      [ALoad, AScan, FLexTicks / TStopwatch.Frequency, AFix, AWrite, FVisits, FLineReReads,
       Round(FLineChars * SizeOf(Char) / BYTES_PER_MB)]));
end;

function TPurityRun.Execute: TPurityStats;
var
  Sw                       : TStopwatch;
  TLoad, TScan, TFix, TWrite: Double;
begin
  FStats:= Default(TPurityStats);
  Sw:= TStopwatch.StartNew;
  Load;
  BuildContexts;
  TLoad:= SecondsOf(Sw);
  Sw:= TStopwatch.StartNew;
  ScanFiles;
  TScan:= SecondsOf(Sw);
  Sw:= TStopwatch.StartNew;
  FixPoint;
  TFix:= SecondsOf(Sw);
  Sw:= TStopwatch.StartNew;
  WriteVerdicts;
  TWrite:= SecondsOf(Sw);
  Report(TLoad, TScan, TFix, TWrite);
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
