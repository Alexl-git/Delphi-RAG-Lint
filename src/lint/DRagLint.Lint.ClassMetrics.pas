unit DRagLint.Lint.ClassMetrics;

{ v0.78 CK class metrics (#6): DIT, NOC, CBO, RFC, LCOM4. v0.80 refactoring
  signal: middle-man. v0.81 coupling metrics: fan-out (Ce, aliases CBO) and
  fan-in (Ca, whole-project reverse aggregation). Store-backed, project-wide --
  runs only in lint-all (not lint-project, not the per-file LSP). Complements the
  coarse god-class rule with individually-tunable metrics. Stateless; reads an
  open store; never raises. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.Diagnostics { TStopwatch -- the phase-attribution counters below }
  , System.Generics.Collections
  , System.Generics.Defaults { TComparer -- the deterministic emit order below }
  , TreeSitter
  , TreeSitterLib
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  , DRagLint.Diagnostics.ParseCache
  ;

type
  /// <summary>Computes per-class design metrics over an indexed symbol store and
  /// returns 'info' findings for classes exceeding the configured threshold: the
  /// Chidamber-Kemerer suite (DIT/NOC/CBO/RFC/LCOM4), the coupling pair
  /// fan-out (Ce) / fan-in (Ca), and the middle-man delegation signal.</summary>
  /// <remarks>
  /// Stateless; project-wide -- invoke from the lint-all store path only
  /// (not lint-project or the per-file LSP). Reads the store read-only; never raises.
  /// </remarks>
  TClassMetrics = class
  public
    /// <summary>Computes the per-class metrics (CK: DIT/NOC/CBO/RFC/LCOM4; the
    /// coupling pair fan-out/fan-in; and middle-man) over AStore and returns
    /// findings for classes exceeding each rule's configured threshold. A nil
    /// store yields no findings. ARuleId, when non-empty, restricts evaluation
    /// to that one rule id.</summary>
    /// <param name="AStore">An open, migrated symbol store; nil -> empty result.</param>
    /// <param name="ACfg">Active lint config (supplies per-rule thresholds).</param>
    /// <param name="ARuleId">Single-rule filter for --rule; '' evaluates every metric.</param>
    /// <returns>'info' findings anchored at each offending class declaration.</returns>
    /// <remarks>
    /// Project-wide; call from lint-all only. Never raises.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
    /// <para>Calls: CollectDefProcNodes, CollectIdentifiers, CompareText, Connected, Copy, Default, DelegateBaseField, DelegationField, DRagLint.Diagnostics.ParseCache.TAstParseCache.Clear, DRagLint.Lint.ClassMetrics.TClassMetrics.Run.BuildInventory (+32 more)</para>
    /// <para>Returns: Roots.Count; Default(TMiddleManResult); nil; Findings.ToArray</para>
    /// <para>Complexity: 28 (cyclomatic, outer body), 1042 lines (full implementation)</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Clear"/>
    /// <seealso cref="DRagLint.Lint.ClassMetrics.TClassMetrics.Run.BuildInventory"/>
    /// <seealso cref="DRagLint.Lint.ClassMetrics.TClassMetrics.Run.BuildMemberMap"/>
    /// <seealso cref="DRagLint.Lint.ClassMetrics.TClassMetrics.Run.ComputeAllFanIn"/>
    /// <seealso cref="DRagLint.Lint.ClassMetrics.TClassMetrics.Run.ComputeCBO"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Run(const AStore: ISymbolStore; const ACfg: TLintConfig;
      const ARuleId: string = ''): TArray<TLintFinding>;
  end;

implementation

type
  { Result of the per-class middle-man delegation scan: how many body methods
    are pure one-line delegations to the dominant field, out of how many total,
    and that field's name. Flag = BestCount * 2 > Total (strict majority). }
  TMiddleManResult = record
    Total    : Integer; { body-bearing methods considered }
    BestCount: Integer; { methods delegating to the dominant field }
    BestField: string ; { the dominant delegate field's name }
  end;

  TClassInfo = record
    Id         : Int64          ;
    Name       : string         ;
    FileId     : Int64          ;
    Path       : string         ;
    DeclLine   : Integer        ;
    DeclCol    : Integer        ;
    DeclEndLine: Integer        ;
    Heritage   : string         ;
    Methods    : TArray<TSymbol>; { method-kind children }
    Fields     : TArray<TSymbol>; { skField children }
  end;

const
  { A class must have at least this many body-bearing methods before the
    middle-man ratio is meaningful (a 1-2 method wrapper is not a smell). }
  MIDDLE_MAN_MIN_METHODS = 3;

function IsMethodKind(AKind: TSymbolKind): Boolean;
begin
  Result:= AKind in [skMethod, skFunction, skProcedure, skConstructor, skDestructor];
end;

{ Raw source text of a tree-sitter node (empty on a null/out-of-range node). }
function NodeText(const N: TTSNode; const Src: TBytes): string;
var
  S, E, L: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
  if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
  Result:= TEncoding.UTF8.GetString(Src, S, L);
end;

{ SESSION 25 B1: ATTRIBUTION ONLY -- no optimisation is made on the strength of
  these numbers until they exist.

  `class-metrics` is 56-58 s of ORM3's `lint-all` and has never been looked at.
  Two candidates were proposed from reading the code, and reading the code is
  exactly what has already been wrong four times on the neighbouring
  `unresolved-name` bucket:

    1. ResolveTypeCategory, called per type_use ref per class with no memo, and
       running FindSymbolsByExactName underneath -- materialising every symbol
       that shares the name. That anti-pattern has been fixed three times in
       this codebase already.
    2. ComputeLCOM4 / ComputeMiddleMan, which re-parse method bodies.

  So: a timer AND A CALL COUNT for each, because "expensive per call" and
  "called far more often than anyone thought" are different defects with
  different fixes, and a bucket with no count cannot tell them apart. That
  mistake cost three sessions.

  GRtcSeen counts DISTINCT (lowercase name, file id) keys. It is not part of any
  fix -- it measures what the proposed memo's hit rate WOULD be, before the memo
  is written. Rows >> distinct keys means a memo pays; rows ~= distinct keys
  means it is pure overhead and candidate 1 is dead. The file id is in the key
  because it is the tie-break ResolveTypeCategory itself uses. }
var
  GBRtc, GBAnc, GBLcom, GBMm, GBCbo, GBRfc, GBFanInAll: Int64;
  GCRtc, GCAnc, GCLcom, GCMm, GCCbo, GCRfc           : Int64;
  GRtcSeen: TDictionary<string, Boolean>;

{ Split a heritage list ('TBar, IBaz') into trimmed names. }
function SplitHeritage(const AHeritage: string): TArray<string>;
var
  Parts: TArray<string>;
  I    : Integer       ;
begin
  Result:= nil;
  if Trim(AHeritage) = '' then Exit;
  Parts:= AHeritage.Split([',']);
  for I:= 0 to High(Parts) do
    if Trim(Parts[I]) <> '' then Result:= Result + [Trim(Parts[I])];
end;

class function TClassMetrics.Run(const AStore: ISymbolStore; const ACfg: TLintConfig;
  const ARuleId: string): TArray<TLintFinding>;
var
  Inv         : TDictionary<Int64, TClassInfo>   ;
  ByName      : TDictionary<string, TList<Int64>>;
  ParentOf    : TDictionary<Int64, Int64>        ;
  HasExtParent: TDictionary<Int64, Boolean>      ;
  NocCount    : TDictionary<Int64, Integer>      ;
  RefsCache   : TDictionary<Int64, TArray<TReference>>;
  { MEASURED, then written -- see RTC. LOCAL to this call, not a unit global,
    because the key carries a FILE ID and file ids are numbered per database: a
    process-lifetime memo would answer one store's question with another's. }
  RtcMemo     : TDictionary<string, TTypeCategory>;
  FanIn       : TDictionary<Int64, Integer>      ; { v0.81: target class id -> distinct inbound source count (Ca) }
  MemberToClass  : TDictionary<string, Int64>   ; { v0.82 feature-envy: LowerCase(method name) -> declaring class id }
  AmbiguousMember: TDictionary<string, Boolean> ; { v0.82 feature-envy: method names declared by >1 distinct class (excluded) }
  Findings    : TList<TLintFinding>              ;
  TNOC        : Integer                          ;
  TDIT        : Integer                          ;
  TRFC        : Integer                          ;
  TCBO        : Integer                          ;
  TLCOM       : Integer                          ;
  TFanOut     : Integer                          ;
  TFanIn      : Integer                          ;
  TFEnvy      : Integer                          ; { v0.82 feature-envy: minAccess floor }
  TInstPct    : Integer                          ; { v0.82 instability: I=Ce/(Ca+Ce) threshold, as a percent }
  TInstFloor  : Integer                          ; { v0.82 instability: noise floor on Ca+Ce (also guards div-by-zero) }
  CI          : TClassInfo                       ;

  function WantRule(const AId: string): Boolean;
  begin
    Result:= (ARuleId = '') or (ARuleId = AId);
  end;

  procedure Emit(const AId, AMsg: string; const AInfo: TClassInfo);
  var
    F: TLintFinding;
  begin
    F:= Default(TLintFinding);
    F.RuleId  := AId;
    F.Severity:= 'info';
    F.Message := AMsg;
    F.FilePath:= AInfo.Path;
    F.StartLine:= AInfo.DeclLine;
    F.StartCol := AInfo.DeclCol;
    F.EndLine  := AInfo.DeclLine;
    F.EndCol   := AInfo.DeclCol + Length(AInfo.Name);
    Findings.Add(F);
  end;

  { The ONE place this phase asks the store to classify a type name. It had three
    call sites; they are routed through here so the cost is measured once and, if
    a memo turns out to be warranted, there is a single place to put it.
    The distinct-key insert sits OUTSIDE the timed window on purpose -- it is
    instrumentation and must not be charged to the thing it is measuring. }
  function RTC(const AName: string; AFileId: Int64): TTypeCategory;
  begin
    Inc(GCRtc);
    var Key: string:= LowerCase(AName) + '|' + IntToStr(AFileId);
    GRtcSeen.AddOrSetValue(Key, True);
    var T0: Int64:= TStopwatch.GetTimeStamp;
    { MEMOISED on the measurement above, not on the code reading that proposed
      it: 266,715 calls over 7,568 DISTINCT (name, file) keys -- 97% of the calls
      re-ask a question already answered -- and this one routine was 40.99 s of
      the phase's 58.49 s. The other candidate the plan named (ComputeLCOM4 +
      ComputeMiddleMan re-parsing method bodies) measured 4.05 s combined and is
      not worth touching.

      The key is (LOWERCASE name, file id), matching what
      ResolveTypeCategory itself does: Delphi identifiers are case-insensitive,
      and the file id is its tie-break when several symbols share a name.

      Underneath, each miss still runs FindSymbolsByExactName, which
      materialises EVERY symbol sharing the name -- the same anti-pattern this
      codebase has now fixed four times. The memo removes the repetition; it does
      not fix that, and a bounded store-side query would still be the better
      long-term shape. }
    if not RtcMemo.TryGetValue(Key, Result) then
    begin
      Result:= AStore.ResolveTypeCategory(AName, AFileId);
      RtcMemo.AddOrSetValue(Key, Result);
    end;
    Inc(GBRtc, TStopwatch.GetTimeStamp - T0);
  end;

  function GetRefs(AFileId: Int64): TArray<TReference>;
  begin
    if not RefsCache.TryGetValue(AFileId, Result) then
    begin
      Result:= AStore.GetReferencesFromFile(AFileId);
      RefsCache.Add(AFileId, Result);
    end;
  end;

  { v0.82: exact ref-attribution -- True if AEnclId (a ref's EnclosingSymbolId, the
    innermost enclosing routine) is one of AInfo's own methods. Replaces the
    line-range InAnyMethodBody span test with precise enclosing-symbol membership. }
  function EnclosedByOwnMethod(const AInfo: TClassInfo; AEnclId: Int64): Boolean;
  var
    M: TSymbol;
  begin
    Result:= False;
    if AEnclId <= 0 then Exit;
    for M in AInfo.Methods do
      if M.Id = AEnclId then Exit(True);
  end;

  function InDeclSpan(const AInfo: TClassInfo; ALine: Integer): Boolean;
  begin
    Result:= (ALine >= AInfo.DeclLine) and (ALine <= AInfo.DeclEndLine);
  end;

  procedure BuildInventory;
  var
    Fid : Int64          ;
    Path: string         ;
    Syms: TArray<TSymbol>;
    Kids: TArray<TSymbol>;
    S, K: TSymbol        ;
    Info: TClassInfo     ;
    Low : string         ;
    Lst : TList<Int64>   ;
  begin
    for Fid in AStore.GetAllFileIds do
    begin
      Path:= AStore.GetFilePath(Fid);
      Syms:= AStore.FindSymbolsByFile(Path);
      for S in Syms do
        if S.Kind = skClass then
        begin
          Info:= Default(TClassInfo);
          Info.Id         := S.Id;
          Info.Name       := S.Name;
          Info.FileId     := Fid;
          Info.Path       := Path;
          Info.DeclLine   := S.StartLine;
          Info.DeclCol    := S.StartCol;
          Info.DeclEndLine:= S.EndLine;
          Info.Heritage   := S.Heritage;
          Kids:= AStore.FindAllChildSymbols(S.Id);
          for K in Kids do
            if IsMethodKind(K.Kind) then Info.Methods:= Info.Methods + [K]
            else if K.Kind = skField then Info.Fields:= Info.Fields + [K];
          if not Inv.ContainsKey(Info.Id) then
          begin
            Inv.Add(Info.Id, Info);
            Low:= LowerCase(Info.Name);
            if not ByName.TryGetValue(Low, Lst) then
            begin
              Lst:= TList<Int64>.Create;
              ByName.Add(Low, Lst);
            end;
            Lst.Add(Info.Id);
          end;
        end;
    end;
  end;

  { Resolve each class's direct class-parent (first heritage entry that resolves
    to a class). Internal parent -> ParentOf; external (RTL) parent -> HasExtParent. }
  procedure ResolveParents;
  var
    Info : TClassInfo    ;
    Names: TArray<string>;
    Nm   : string        ;
    Lst  : TList<Int64>  ;
  begin
    for Info in Inv.Values do
    begin
      Names:= SplitHeritage(Info.Heritage);
      for Nm in Names do
      begin
        if RTC(Nm, Info.FileId) <> tcClass then Continue;
        { first class-kind heritage entry is the parent }
        if ByName.TryGetValue(LowerCase(Nm), Lst) and (Lst.Count > 0) then
          ParentOf.AddOrSetValue(Info.Id, Lst[0])
        else
          HasExtParent.AddOrSetValue(Info.Id, True);
        Break;
      end;
    end;
  end;

  procedure ComputeNOC;
  var
    Pair: TPair<Int64, Int64>;
    Cur : Integer            ;
  begin
    for Pair in ParentOf do
    begin
      Cur:= 0;
      NocCount.TryGetValue(Pair.Value, Cur);
      NocCount.AddOrSetValue(Pair.Value, Cur + 1);
    end;
  end;

  { Depth of inheritance: hops up the internal parent chain; a known-but-unindexed
    (external/RTL) parent adds one final hop. Cycle-guarded, hard-capped at 32. }
  function ComputeDIT(AId: Int64): Integer;
  var
    Cur    : Int64            ;
    Depth  : Integer          ;
    Visited: TDictionary<Int64, Boolean>;
    P      : Int64            ;
  begin
    Depth:= 0;
    Cur:= AId;
    Visited:= TDictionary<Int64, Boolean>.Create;
    try
      while True do
      begin
        if Visited.ContainsKey(Cur) then Break;
        Visited.Add(Cur, True);
        if ParentOf.TryGetValue(Cur, P) then
        begin
          Inc(Depth);
          Cur:= P;
          if Depth >= 32 then Break;
        end
        else
        begin
          if HasExtParent.ContainsKey(Cur) then Inc(Depth);
          Break;
        end;
      end;
    finally
      Visited.Free;
    end;
    Result:= Depth;
  end;

  { Response for a class: own method count + distinct callee names invoked from
    within the class's method bodies (case-insensitive). }
  function ComputeRFC(const AInfo: TClassInfo): Integer;
  var
    Refs  : TArray<TReference>       ;
    R     : TReference              ;
    Called: TDictionary<string, Boolean>;
  begin
    Called:= TDictionary<string, Boolean>.Create;
    try
      Refs:= GetRefs(AInfo.FileId);
      for R in Refs do
        // v(ADP3 T3i review round 2): REF_KIND_CALL, not a literal -- same
        // "what kind is a call" question the shared declaration owns.
        if SameText(R.Kind, REF_KIND_CALL) and (R.NameText <> '') and EnclosedByOwnMethod(AInfo, R.EnclosingSymbolId) then
          Called.AddOrSetValue(LowerCase(R.NameText), True);
      Result:= Length(AInfo.Methods) + Called.Count;
    finally
      Called.Free;
    end;
  end;

  { Efferent coupling: distinct OTHER classes named (type_use) in the class's decl
    span or method bodies. Excludes self and the class's transitive ancestors. }
  function ComputeCBO(const AInfo: TClassInfo): Integer;
  var
    Coupled: TDictionary<string, Boolean>;
    Exclude: TDictionary<string, Boolean>;
    Anc    : TArray<TTypeAncestor>       ;
    A      : TTypeAncestor               ;
    Refs   : TArray<TReference>          ;
    R      : TReference                  ;
    Nm     : string                      ;
  begin
    Coupled:= TDictionary<string, Boolean>.Create;
    Exclude:= TDictionary<string, Boolean>.Create;
    try
      Exclude.AddOrSetValue(LowerCase(AInfo.Name), True);
      Inc(GCAnc); var TAnc: Int64:= TStopwatch.GetTimeStamp;
      Anc:= AStore.GetTransitiveAncestors(AInfo.Id);
      Inc(GBAnc, TStopwatch.GetTimeStamp - TAnc);
      for A in Anc do
        if A.Name <> '' then Exclude.AddOrSetValue(LowerCase(A.Name), True);
      Refs:= GetRefs(AInfo.FileId);
      for R in Refs do
      begin
        if not SameText(R.Kind, 'type_use') then Continue;
        if R.NameText = '' then Continue;
        if not (InDeclSpan(AInfo, R.StartLine) or EnclosedByOwnMethod(AInfo, R.EnclosingSymbolId)) then Continue;
        Nm:= LowerCase(R.NameText);
        if Exclude.ContainsKey(Nm) then Continue;
        if RTC(R.NameText, AInfo.FileId) = tcClass then
          Coupled.AddOrSetValue(Nm, True);
      end;
      Result:= Coupled.Count;
    finally
      Exclude.Free;
      Coupled.Free;
    end;
  end;

  { v0.81 -- afferent coupling (Ca / fan-in), whole-project reverse aggregation.
    Builds the FanIn dictionary ONCE (target class id -> count of distinct OTHER
    classes that reference it). Inverts ComputeCBO's efferent logic: for each
    source class Src, recompute its set of coupled class NAMES exactly as
    ComputeCBO does (type_use refs in Src's decl span or method bodies, excluding
    Src itself and Src's transitive ancestors, deduped into a name set); then for
    each coupled name resolve to target class id(s) via ByName and add +1. Because
    each source's names are deduped, a source contributes at most +1 per target,
    so FanIn[t] = the number of distinct OTHER classes referencing class t.
    Caveat (same as CBO): resolution is name-based, so a coupled name shared by
    two classes in different units increments BOTH -- a documented over-count the
    CK suite already tolerates. Adds no new store calls; reuses GetRefs + ByName. }
  procedure ComputeAllFanIn;
  var
    Src    : TClassInfo                  ;
    Coupled: TDictionary<string, Boolean>;
    Exclude: TDictionary<string, Boolean>;
    Anc    : TArray<TTypeAncestor>       ;
    A      : TTypeAncestor               ;
    Refs   : TArray<TReference>          ;
    R      : TReference                  ;
    Nm     : string                      ;
    Tgts   : TList<Int64>                ;
    Tid    : Int64                       ;
    Cur    : Integer                     ;
  begin
    for Src in Inv.Values do
    begin
      Coupled:= TDictionary<string, Boolean>.Create;
      Exclude:= TDictionary<string, Boolean>.Create;
      try
        Exclude.AddOrSetValue(LowerCase(Src.Name), True);
        Inc(GCAnc); var TAnc: Int64:= TStopwatch.GetTimeStamp;
        Anc:= AStore.GetTransitiveAncestors(Src.Id);
        Inc(GBAnc, TStopwatch.GetTimeStamp - TAnc);
        for A in Anc do
          if A.Name <> '' then Exclude.AddOrSetValue(LowerCase(A.Name), True);
        Refs:= GetRefs(Src.FileId);
        for R in Refs do
        begin
          if not SameText(R.Kind, 'type_use') then Continue;
          if R.NameText = '' then Continue;
          if not (InDeclSpan(Src, R.StartLine) or EnclosedByOwnMethod(Src, R.EnclosingSymbolId)) then Continue;
          Nm:= LowerCase(R.NameText);
          if Exclude.ContainsKey(Nm) then Continue;
          if RTC(R.NameText, Src.FileId) = tcClass then
            Coupled.AddOrSetValue(Nm, True);
        end;
        { each deduped coupled name contributes +1 to every class id it resolves to }
        for Nm in Coupled.Keys do
          if ByName.TryGetValue(Nm, Tgts) then
            for Tid in Tgts do
            begin
              Cur:= 0;
              FanIn.TryGetValue(Tid, Cur);
              FanIn.AddOrSetValue(Tid, Cur + 1);
            end;
      finally
        Exclude.Free;
        Coupled.Free;
      end;
    end;
  end;

  { LCOM4: connected components of the method graph. Nodes = body-bearing methods.
    Edge when two methods share an accessed field OR one calls the other. Field/
    call access is read from a complete AST re-walk of each method body. }
  function ComputeLCOM4(const AInfo: TClassInfo): Integer;
  var
    PF        : TParsedFile               ;
    BodyM     : TArray<TSymbol>           ;
    M         : TSymbol                   ;
    FieldNames: TDictionary<string, Boolean>;
    ProcByLine: TDictionary<Integer, TTSNode>;
    ProcNodes : TList<TTSNode>            ;
    IdSets    : TArray<TDictionary<string, Boolean>>;
    N, I, J   : Integer                   ;
    UF        : TArray<Integer>           ;
    Roots     : TDictionary<Integer, Boolean>;

    procedure CollectDefProcNodes(const ANode: TTSNode);
    var
      C  : Integer;
      Ln : Integer;
    begin
      if ANode.IsNull then Exit;
      if ANode.NodeType = 'defProc' then
      begin
        Ln:= Integer(ANode.StartPoint.row) + 1;
        if not ProcByLine.ContainsKey(Ln) then ProcByLine.Add(Ln, ANode);
        ProcNodes.Add(ANode);
      end;
      for C:= 0 to ANode.NamedChildCount - 1 do CollectDefProcNodes(ANode.NamedChild(C));
    end;

    { Collects identifiers under ARoot's own body, stopping at any NESTED
      defProc boundary (a local procedure/function) so its identifiers don't
      fold into the enclosing method's set -- same idiom as CloneChecks.
      CollectLeaves: recurse everywhere except into a non-root defProc. }
    procedure CollectIdentifiers(const ARoot, ANode: TTSNode; ADst: TDictionary<string, Boolean>);
    var
      C: Integer;
      T: string ;
    begin
      if ANode.IsNull then Exit;
      if (not (ANode = ARoot)) and (ANode.NodeType = 'defProc') then Exit; { nested routine excluded }
      if ANode.NodeType = 'identifier' then
      begin
        T:= LowerCase(NodeText(ANode, PF.Src));
        if T <> '' then ADst.AddOrSetValue(T, True);
      end;
      for C:= 0 to ANode.NamedChildCount - 1 do CollectIdentifiers(ARoot, ANode.NamedChild(C), ADst);
    end;

    { Fallback when no defProc starts exactly on ImplStartLine (line-numbering
      skew between the store and the parser): pick the defProc whose row range
      contains the target line. }
    function FindProcContainingLine(ALine: Integer): TTSNode;
    var
      P: TTSNode;
      S, E: Integer;
    begin
      Result:= Default(TTSNode);
      for P in ProcNodes do
      begin
        S:= Integer(P.StartPoint.row) + 1;
        E:= Integer(P.EndPoint.row) + 1;
        if (ALine >= S) and (ALine <= E) then Exit(P);
      end;
    end;

    function Find(X: Integer): Integer;
    begin
      while UF[X] <> X do
      begin
        UF[X]:= UF[UF[X]];
        X:= UF[X];
      end;
      Result:= X;
    end;

    procedure Union(X, Y: Integer);
    var
      Rx, Ry: Integer;
    begin
      Rx:= Find(X); Ry:= Find(Y);
      if Rx <> Ry then UF[Rx]:= Ry;
    end;

    function Connected(A, B: Integer): Boolean;
    var
      K: string;
    begin
      Result:= False;
      { shared field access }
      for K in IdSets[A].Keys do
        if FieldNames.ContainsKey(K) and IdSets[B].ContainsKey(K) then Exit(True);
      { A calls B or B calls A (by method name) }
      if IdSets[A].ContainsKey(LowerCase(BodyM[B].Name)) then Exit(True);
      if IdSets[B].ContainsKey(LowerCase(BodyM[A].Name)) then Exit(True);
    end;

  begin
    BodyM:= nil;
    for M in AInfo.Methods do
      if M.ImplStartLine > 0 then BodyM:= BodyM + [M];
    N:= Length(BodyM);
    if N <= 1 then Exit(N); { 0 or 1 body-method -> 0 or 1 component }

    PF:= TAstParseCache.Get(AInfo.Path);
    if PF.Tree = nil then Exit(1); { unparseable -> treat as cohesive }

    FieldNames:= TDictionary<string, Boolean>.Create;
    ProcByLine:= TDictionary<Integer, TTSNode>.Create;
    ProcNodes := TList<TTSNode>.Create;
    SetLength(IdSets, N);
    SetLength(UF, N);
    try
      for M in AInfo.Fields do FieldNames.AddOrSetValue(LowerCase(M.Name), True);
      CollectDefProcNodes(PF.Tree.RootNode);

      for I:= 0 to N - 1 do
      begin
        IdSets[I]:= TDictionary<string, Boolean>.Create;
        UF[I]:= I;
        var Node: TTSNode;
        if not ProcByLine.TryGetValue(BodyM[I].ImplStartLine, Node) then
          Node:= FindProcContainingLine(BodyM[I].ImplStartLine); { fallback: range containment }
        if not Node.IsNull then
          CollectIdentifiers(Node, Node, IdSets[I]);
      end;

      for I:= 0 to N - 2 do
        for J:= I + 1 to N - 1 do
          if Connected(I, J) then Union(I, J);

      Roots:= TDictionary<Integer, Boolean>.Create;
      try
        for I:= 0 to N - 1 do Roots.AddOrSetValue(Find(I), True);
        Result:= Roots.Count;
      finally
        Roots.Free;
      end;
    finally
      for I:= 0 to N - 1 do
        if IdSets[I] <> nil then IdSets[I].Free;
      ProcNodes.Free;
      ProcByLine.Free;
      FieldNames.Free;
    end;
  end;

  { Middle-man delegation scan (Fowler "Remove Middle Man"). For each body
    method, decides whether its body is a PURE single-statement delegation to a
    base FIELD of the class and, if so, to which field; then groups by target
    field and reports the dominant group. A method delegates when its body's one
    real statement (skipping begin/end) is EITHER an assignment 'Result :=
    <field>.X[(...)]' (lhs = Result or the method's own name) OR a bare void call
    '<field>.X[(...)];'. The delegate root must be a declared field (CI.Fields,
    case-insensitive) -- this both groups by "same object" and cuts false
    positives (delegation to a local/param/global is not a middle-man). The
    caller flags the class when Total >= MIDDLE_MAN_MIN_METHODS and the dominant
    group is a strict majority (BestCount * 2 > Total). }
  function ComputeMiddleMan(const AInfo: TClassInfo): TMiddleManResult;
  var
    PF        : TParsedFile               ;
    BodyM     : TArray<TSymbol>           ;
    M         : TSymbol                   ;
    FieldNames: TDictionary<string, Boolean>;
    ProcByLine: TDictionary<Integer, TTSNode>;
    ProcNodes : TList<TTSNode>            ;
    Groups    : TDictionary<string, Integer>;
    Display   : TDictionary<string, string> ; { lowercase field -> original casing }
    I         : Integer                   ;
    Field, Lo : string                    ;
    Cnt, Best : Integer                   ;
    Pair      : TPair<string, Integer>    ;

    procedure CollectDefProcNodes(const ANode: TTSNode);
    var
      C  : Integer;
      Ln : Integer;
    begin
      if ANode.IsNull then Exit;
      if ANode.NodeType = 'defProc' then
      begin
        Ln:= Integer(ANode.StartPoint.row) + 1;
        if not ProcByLine.ContainsKey(Ln) then ProcByLine.Add(Ln, ANode);
        ProcNodes.Add(ANode);
      end;
      for C:= 0 to ANode.NamedChildCount - 1 do CollectDefProcNodes(ANode.NamedChild(C));
    end;

    function FindProcContainingLine(ALine: Integer): TTSNode;
    var
      P: TTSNode;
      S, E: Integer;
    begin
      Result:= Default(TTSNode);
      for P in ProcNodes do
      begin
        S:= Integer(P.StartPoint.row) + 1;
        E:= Integer(P.EndPoint.row) + 1;
        if (ALine >= S) and (ALine <= E) then Exit(P);
      end;
    end;

    { The base (leftmost-rooted) identifier text of a delegate expression, or ''.
      Unwraps exprCall (entity: field), then walks the exprDot lhs: chain down to
      the deepest single identifier -- 'FImpl.X' -> 'FImpl', 'FA.FB.X' -> 'FA'. }
    function DelegateBaseField(ANode: TTSNode): string;
    var
      Cur, Lhs: TTSNode;
      Guard   : Integer;
    begin
      Result:= '';
      if ANode.IsNull then Exit;
      if ANode.NodeType = 'exprCall' then
        ANode:= ANode.ChildByField('entity');
      if ANode.IsNull then Exit;
      if ANode.NodeType <> 'exprDot' then Exit; { not a member access -> not a delegation }
      Cur:= ANode;
      Guard:= 0;
      while (not Cur.IsNull) and (Cur.NodeType = 'exprDot') and (Guard < 64) do
      begin
        Lhs:= Cur.ChildByField('lhs');
        if Lhs.IsNull then Exit;
        Cur:= Lhs;
        Inc(Guard);
      end;
      if (not Cur.IsNull) and (Cur.NodeType = 'identifier') then
        Result:= NodeText(Cur, PF.Src);
    end;

    { The single real statement of a block body (skips begin/end keyword nodes),
      or a null node when the body has zero or more than one real statement. }
    function SoleStatement(const ABlock: TTSNode): TTSNode;
    var
      C, RealN: Integer;
      Kid     : TTSNode;
    begin
      Result:= Default(TTSNode);
      RealN:= 0;
      for C:= 0 to ABlock.NamedChildCount - 1 do
      begin
        Kid:= ABlock.NamedChild(C);
        if Kid.IsNull then Continue;
        if Copy(Kid.NodeType, 1, 1) = 'k' then Continue; { kBegin / kEnd / kComment-ish keyword tokens }
        Inc(RealN);
        if RealN > 1 then Exit(Default(TTSNode)); { more than one statement -> not a delegation }
        Result:= Kid;
      end;
      if RealN <> 1 then Result:= Default(TTSNode);
    end;

    { The delegate field a defProc body forwards to, or '' if not a pure
      single-statement delegation. Recognises 'Result := <field>.X' assignments
      and bare '<field>.X;' void calls. AMethodName lets 'FnName := ...' (the
      old-style function-result assignment) count as a Result assignment. }
    function DelegationField(const ADefProc: TTSNode; const AMethodName: string): string;
    var
      Body, Stmt, Lhs, Rhs, Delegate: TTSNode;
      LhsTxt                        : string ;
    begin
      Result:= '';
      if ADefProc.IsNull then Exit;
      Body:= ADefProc.ChildByField('body');
      if Body.IsNull or (Body.NodeType <> 'block') then Exit;
      Stmt:= SoleStatement(Body);
      if Stmt.IsNull then Exit;

      Delegate:= Default(TTSNode);
      if Stmt.NodeType = 'assignment' then
      begin
        Lhs:= Stmt.ChildByField('lhs');
        if Lhs.IsNull or (Lhs.NodeType <> 'identifier') then Exit;
        LhsTxt:= NodeText(Lhs, PF.Src);
        if not (SameText(LhsTxt, 'Result') or SameText(LhsTxt, AMethodName)) then Exit;
        Rhs:= Stmt.ChildByField('rhs');
        if Rhs.IsNull then Exit;
        Delegate:= Rhs;
      end
      else if Stmt.NodeType = 'statement' then
      begin
        { bare void call is wrapped in a 'statement' node with one named child }
        if Stmt.NamedChildCount <> 1 then Exit;
        Delegate:= Stmt.NamedChild(0);
      end
      else if (Stmt.NodeType = 'exprCall') or (Stmt.NodeType = 'exprDot') then
        Delegate:= Stmt { defensive: an unwrapped bare expression }
      else
        Exit;

      if Delegate.IsNull then Exit;
      if not ((Delegate.NodeType = 'exprDot') or (Delegate.NodeType = 'exprCall')) then Exit;
      Result:= DelegateBaseField(Delegate);
    end;

  begin
    Result:= Default(TMiddleManResult);
    BodyM:= nil;
    for M in AInfo.Methods do
      if M.ImplStartLine > 0 then BodyM:= BodyM + [M];
    Result.Total:= Length(BodyM);
    if Result.Total < MIDDLE_MAN_MIN_METHODS then Exit;

    PF:= TAstParseCache.Get(AInfo.Path);
    if PF.Tree = nil then Exit; { unparseable -> no delegation signal }

    FieldNames:= TDictionary<string, Boolean>.Create;
    ProcByLine:= TDictionary<Integer, TTSNode>.Create;
    ProcNodes := TList<TTSNode>.Create;
    Groups    := TDictionary<string, Integer>.Create;
    Display   := TDictionary<string, string>.Create;
    try
      for M in AInfo.Fields do FieldNames.AddOrSetValue(LowerCase(M.Name), True);
      CollectDefProcNodes(PF.Tree.RootNode);

      for I:= 0 to High(BodyM) do
      begin
        var Node: TTSNode;
        if not ProcByLine.TryGetValue(BodyM[I].ImplStartLine, Node) then
          Node:= FindProcContainingLine(BodyM[I].ImplStartLine);
        if Node.IsNull then Continue;
        Field:= DelegationField(Node, BodyM[I].Name);
        if Field = '' then Continue;
        Lo:= LowerCase(Field);
        if not FieldNames.ContainsKey(Lo) then Continue; { delegate to a real field only }
        Groups.TryGetValue(Lo, Cnt);
        Groups.AddOrSetValue(Lo, Cnt + 1);
        if not Display.ContainsKey(Lo) then Display.Add(Lo, Field);
      end;

      Best:= 0;
      for Pair in Groups do
        if Pair.Value > Best then
        begin
          Best:= Pair.Value;
          if not Display.TryGetValue(Pair.Key, Result.BestField) then
            Result.BestField:= Pair.Key;
        end;
      Result.BestCount:= Best;
    finally
      Display.Free;
      Groups.Free;
      ProcNodes.Free;
      ProcByLine.Free;
      FieldNames.Free;
    end;
  end;

  { v0.82 feature-envy support -- build the method-name -> declaring-class-id map
    over the whole inventory. A method NAME (case-insensitive) maps to the id of
    the class that declares it; when the SAME name is declared by two DISTINCT
    classes it is marked AMBIGUOUS and later excluded from own/foreign resolution
    (a documented FP-avoidance: name-based resolution cannot pick between two
    classes that both declare 'Load'). RTL/unindexed classes are not in Inv, so
    calls to their members simply resolve to nothing and are ignored. }
  procedure BuildMemberMap;
  var
    Info: TClassInfo;
    M   : TSymbol   ;
    Low : string    ;
    Owner: Int64    ;
  begin
    for Info in Inv.Values do
      for M in Info.Methods do
      begin
        if M.Name = '' then Continue;
        Low:= LowerCase(M.Name);
        if AmbiguousMember.ContainsKey(Low) then Continue; { already poisoned }
        if MemberToClass.TryGetValue(Low, Owner) then
        begin
          if Owner <> Info.Id then
          begin
            { same name in a second, distinct class -> ambiguous; drop it }
            AmbiguousMember.AddOrSetValue(Low, True);
            MemberToClass.Remove(Low);
          end;
          { same class re-declaring (overload) -> keep the single mapping }
        end
        else
          MemberToClass.AddOrSetValue(Low, Info.Id);
      end;
  end;

  { v0.82 feature-envy (#14, category refactoring, info, OFF-by-default). For class
    C, group C's 'call' refs by their enclosing method M (EnclosingSymbolId, which
    must be one of C's own methods), then split each call by resolving the CALLED
    method name via MemberToClass: a call whose name declares in C is an 'own'
    access; a call resolving to another class X is a 'foreign' access to X;
    ambiguous/unresolved names are skipped. Flag M when the most-envied class X's
    foreign count strictly exceeds M's own-class count AND meets the minAccess
    floor. Emits at M's DECLARATION line so two envious methods of one class produce
    distinct findings. KEY LIMITATION: target-class resolution is name-based (no
    expression type inference), so the own/foreign split is heuristic and precision
    is bounded -> the rule ships OFF-by-default. }
  procedure ComputeFeatureEnvy(const AInfo: TClassInfo; AMinAccess: Integer);
  var
    Refs   : TArray<TReference>              ;
    R      : TReference                      ;
    Low    : string                          ;
    Tgt    : Int64                           ;
    Own    : TDictionary<Int64, Integer>     ; { method id -> own-class call count }
    Foreign: TDictionary<Int64, TDictionary<Int64, Integer>>; { method id -> (foreign class id -> count) }
    ForByX : TDictionary<Int64, Integer>     ;
    Cur    : Integer                         ;
    M      : TSymbol                          ;
    OwnC, MaxF: Integer                       ;
    EnviedX: Int64                           ;
    Pair   : TPair<Int64, Integer>           ;
    XInfo  : TClassInfo                      ;
    XName  : string                          ;
  begin
    Own    := TDictionary<Int64, Integer>.Create;
    Foreign:= TDictionary<Int64, TDictionary<Int64, Integer>>.Create;
    try
      Refs:= GetRefs(AInfo.FileId);
      for R in Refs do
      begin
        if not SameText(R.Kind, REF_KIND_CALL) then Continue; // v(ADP3 T3i r2): shared declaration
        if R.NameText = '' then Continue;
        if not EnclosedByOwnMethod(AInfo, R.EnclosingSymbolId) then Continue;
        Low:= LowerCase(R.NameText);
        if AmbiguousMember.ContainsKey(Low) then Continue;   { name declared by >1 class -> skip }
        if not MemberToClass.TryGetValue(Low, Tgt) then Continue; { RTL/unindexed -> ignore }
        if Tgt = AInfo.Id then
        begin
          Cur:= 0;
          Own.TryGetValue(R.EnclosingSymbolId, Cur);
          Own.AddOrSetValue(R.EnclosingSymbolId, Cur + 1);
        end
        else
        begin
          if not Foreign.TryGetValue(R.EnclosingSymbolId, ForByX) then
          begin
            ForByX:= TDictionary<Int64, Integer>.Create;
            Foreign.Add(R.EnclosingSymbolId, ForByX);
          end;
          Cur:= 0;
          ForByX.TryGetValue(Tgt, Cur);
          ForByX.AddOrSetValue(Tgt, Cur + 1);
        end;
      end;

      { evaluate each method M of C against its most-envied foreign class }
      for M in AInfo.Methods do
      begin
        if not Foreign.TryGetValue(M.Id, ForByX) then Continue; { no foreign access -> not envious }
        MaxF:= 0; EnviedX:= 0;
        for Pair in ForByX do
          if Pair.Value > MaxF then
          begin
            MaxF:= Pair.Value;
            EnviedX:= Pair.Key;
          end;
        OwnC:= 0;
        Own.TryGetValue(M.Id, OwnC);
        if (MaxF > OwnC) and (MaxF >= AMinAccess) then
        begin
          XName:= '?';
          if Inv.TryGetValue(EnviedX, XInfo) then XName:= XInfo.Name;
          var F: TLintFinding:= Default(TLintFinding);
          F.RuleId   := 'feature-envy';
          F.Severity := 'info';
          F.Message  := Format('Feature envy: %s.%s accesses %s %d times vs %d on its own class -- consider moving it there',
            [AInfo.Name, M.Name, XName, MaxF, OwnC]);
          F.FilePath := AInfo.Path;
          F.StartLine:= M.StartLine;
          F.StartCol := M.StartCol;
          F.EndLine  := M.StartLine;
          F.EndCol   := M.StartCol + Length(M.Name);
          Findings.Add(F);
        end;
      end;
    finally
      for var D in Foreign.Values do D.Free;
      Foreign.Free;
      Own.Free;
    end;
  end;

begin
  Result:= nil;
  if AStore = nil then Exit;

  Inv         := TDictionary<Int64, TClassInfo>.Create;
  ByName      := TDictionary<string, TList<Int64>>.Create;
  ParentOf    := TDictionary<Int64, Int64>.Create;
  HasExtParent:= TDictionary<Int64, Boolean>.Create;
  NocCount    := TDictionary<Int64, Integer>.Create;
  RefsCache   := TDictionary<Int64, TArray<TReference>>.Create;
  RtcMemo     := TDictionary<string, TTypeCategory>.Create;
  FanIn       := TDictionary<Int64, Integer>.Create;
  MemberToClass  := TDictionary<string, Int64>.Create;
  AmbiguousMember:= TDictionary<string, Boolean>.Create;
  Findings    := TList<TLintFinding>.Create;
  try
    TNOC:= ACfg.ThresholdFor('too-many-children', 10);
    TDIT:= ACfg.ThresholdFor('deep-inheritance', 6);
    TRFC:= ACfg.ThresholdFor('high-response', 50);
    TCBO:= ACfg.ThresholdFor('high-coupling', 20);
    TLCOM:= ACfg.ThresholdFor('low-cohesion', 26);
    TFanOut:= ACfg.ThresholdFor('fan-out', 20); { aliases CBO; field-tune }
    TFanIn := ACfg.ThresholdFor('fan-in', 20);  { field-tune }
    TFEnvy := ACfg.ThresholdFor('feature-envy', 3); { min foreign accesses to flag }
    TInstPct  := ACfg.ThresholdFor('instability', 80);       { percent form of I threshold (default 0.8) }
    TInstFloor:= ACfg.ThresholdFor('instability-floor', 5);  { noise floor on Ca+Ce; keeps Total > 0 }

    BuildInventory;
    ResolveParents;
    ComputeNOC;
    var TFI: Int64:= TStopwatch.GetTimeStamp;
    ComputeAllFanIn;
    Inc(GBFanInAll, TStopwatch.GetTimeStamp - TFI);
    if WantRule('feature-envy') then BuildMemberMap;

    { DETERMINISTIC EMIT ORDER, and it is a correctness property of the REPORT
      rather than a cosmetic one.

      This loop used to walk Inv.Values directly. Inv is a
      TDictionary<Int64, TClassInfo> keyed by SYMBOL ID, and dictionary
      enumeration follows the hash layout -- so the order depends on the ids,
      and a reindex reassigns ids. Measured 2026-08-17 on ORM3: reindexing the
      SAME sources moved 61 findings (58 high-response, 2 low-cohesion, 1
      too-many-children) to different positions. Same 14,764 findings, same
      2,161,951 bytes, identical line multiset when sorted -- a different file.

      Why that matters more than it looks: byte-identity of `lint-all` stdout is
      this project's primary verification gate for every performance change. An
      output order that moves when the index is rebuilt makes that gate valid
      only WITHIN one index state, silently, and makes any report-to-report diff
      across a reindex show churn that is not there.

      Sorted by (path, decl line, decl col, name): the file and position a
      reader is sent to, which is stable across reindexes because it comes from
      the SOURCE, not from the index's internal numbering. }
    var Ordered: TArray<TClassInfo>:= nil;
    for var CIv in Inv.Values do Ordered:= Ordered + [CIv];
    TArray.Sort<TClassInfo>(Ordered, TComparer<TClassInfo>.Construct(
      function(const L, R: TClassInfo): Integer
      begin
        Result:= CompareText(L.Path, R.Path);
        if Result = 0 then Result:= L.DeclLine - R.DeclLine;
        if Result = 0 then Result:= L.DeclCol  - R.DeclCol ;
        if Result = 0 then Result:= CompareText(L.Name, R.Name);
      end));

    for CI in Ordered do
    begin
      if WantRule('too-many-children') then
      begin
        var N: Integer:= 0;
        NocCount.TryGetValue(CI.Id, N);
        if N > TNOC then
          Emit('too-many-children',
            Format('High NOC: %s has %d direct subclasses (>%d) -- a wide, fragile base class', [CI.Name, N, TNOC]),
            CI);
      end;

      if WantRule('deep-inheritance') then
      begin
        var D: Integer:= ComputeDIT(CI.Id);
        if D > TDIT then
          Emit('deep-inheritance',
            Format('Deep inheritance: %s is %d levels deep (>%d) -- deep hierarchies are hard to follow', [CI.Name, D, TDIT]),
            CI);
      end;

      if WantRule('high-response') then
      begin
        Inc(GCRfc); var TR: Int64:= TStopwatch.GetTimeStamp;
        var Rfc: Integer:= ComputeRFC(CI);
        Inc(GBRfc, TStopwatch.GetTimeStamp - TR);
        if Rfc > TRFC then
          Emit('high-response',
            Format('High RFC: %s has a response set of %d (>%d) -- many methods and calls to test/understand', [CI.Name, Rfc, TRFC]),
            CI);
      end;

      if WantRule('high-coupling') then
      begin
        Inc(GCCbo); var TC: Int64:= TStopwatch.GetTimeStamp;
        var Cbo: Integer:= ComputeCBO(CI);
        Inc(GBCbo, TStopwatch.GetTimeStamp - TC);
        if Cbo > TCBO then
          Emit('high-coupling',
            Format('High CBO: %s is coupled to %d other classes (>%d) -- consider reducing dependencies', [CI.Name, Cbo, TCBO]),
            CI);
      end;

      if WantRule('low-cohesion') then
      begin
        Inc(GCLcom); var TL: Int64:= TStopwatch.GetTimeStamp;
        var Lc: Integer:= ComputeLCOM4(CI);
        Inc(GBLcom, TStopwatch.GetTimeStamp - TL);
        if Lc > TLCOM then
          Emit('low-cohesion',
            Format('Low cohesion: %s has LCOM4=%d (>%d) -- the class may combine unrelated responsibilities; consider splitting', [CI.Name, Lc, TLCOM]),
            CI);
      end;

      if WantRule('middle-man') then
      begin
        Inc(GCMm); var TM: Int64:= TStopwatch.GetTimeStamp;
        var MM: TMiddleManResult:= ComputeMiddleMan(CI);
        Inc(GBMm, TStopwatch.GetTimeStamp - TM);
        if (MM.Total >= MIDDLE_MAN_MIN_METHODS) and (MM.BestCount * 2 > MM.Total) then
          Emit('middle-man',
            Format('Middle man: %s forwards %d of %d methods to field ''%s'' -- consider removing the middle man (inline the delegate or expose it).', [CI.Name, MM.BestCount, MM.Total, MM.BestField]),
            CI);
      end;

      if WantRule('fan-out') then
      begin
        { efferent coupling (Ce); intentionally aliases high-coupling/CBO -- ships
          OFF by default so it does not double-fire with the ON high-coupling rule }
        var Ce: Integer:= ComputeCBO(CI);
        if Ce > TFanOut then
          Emit('fan-out',
            Format('High fan-out: %s depends on %d other classes (>%d) -- high efferent coupling; this class is fragile to changes in its dependencies', [CI.Name, Ce, TFanOut]),
            CI);
      end;

      if WantRule('fan-in') then
      begin
        { afferent coupling (Ca): distinct OTHER classes that reference this one }
        var Ca: Integer:= 0;
        FanIn.TryGetValue(CI.Id, Ca);
        if Ca > TFanIn then
          Emit('fan-in',
            Format('High fan-in: %s is referenced by %d other classes (>%d) -- a widely-depended-on hub; changes here ripple widely', [CI.Name, Ca, TFanIn]),
            CI);
      end;

      if WantRule('instability') then
      begin
        { v0.82 (#11): I = Ce/(Ca+Ce) as an integer percent, cross-multiplied to
          avoid floats/div-by-zero. Flag only near the unstable extreme (high Ce,
          low Ca) and only above the noise floor -- ignore trivially-coupled classes. }
        var Ce: Integer:= ComputeCBO(CI);
        var Ca: Integer:= 0;
        FanIn.TryGetValue(CI.Id, Ca);
        var Total: Integer:= Ca + Ce;
        if (Total >= TInstFloor) and (Ce * 100 >= TInstPct * Total) then
          Emit('instability',
            Format('Unstable: %s has instability I=%d%% (Ce=%d efferent, Ca=%d afferent, >=%d%%) -- depends on many, nothing depends on it; hard to change safely',
                   [CI.Name, (Ce * 100) div Total, Ce, Ca, TInstPct]),
            CI);
      end;

      if WantRule('feature-envy') then
        { OFF-by-default (#14): emits at the envious method's decl line, not CI's }
        ComputeFeatureEnvy(CI, TFEnvy);
    end;

    { SESSION 25 B1 attribution. Printed only under DRAGLINT_PROFILE, on stderr,
      beside the phase total the CLI already prints -- so the parts and the whole
      are read together and a large remainder is visible as a remainder. }
    if GetEnvironmentVariable('DRAGLINT_PROFILE') <> '' then
    begin
      Writeln(ErrOutput, Format('  CLASS-METRICS BREAKDOWN (%d class(es))', [Inv.Count]));
      Writeln(ErrOutput, Format('    %-26s %8.2f s (%d call(s), %d distinct (name,file) key(s))',
        ['ResolveTypeCategory', GBRtc / TStopwatch.Frequency, GCRtc, GRtcSeen.Count]));
      Writeln(ErrOutput, Format('    %-26s %8.2f s (%d call(s))', ['GetTransitiveAncestors', GBAnc  / TStopwatch.Frequency, GCAnc ]));
      Writeln(ErrOutput, Format('    %-26s %8.2f s (%d call(s))', ['ComputeCBO'            , GBCbo  / TStopwatch.Frequency, GCCbo ]));
      Writeln(ErrOutput, Format('    %-26s %8.2f s (%d call(s))', ['ComputeRFC'            , GBRfc  / TStopwatch.Frequency, GCRfc ]));
      Writeln(ErrOutput, Format('    %-26s %8.2f s (%d call(s))', ['ComputeLCOM4'          , GBLcom / TStopwatch.Frequency, GCLcom]));
      Writeln(ErrOutput, Format('    %-26s %8.2f s (%d call(s))', ['ComputeMiddleMan'      , GBMm   / TStopwatch.Frequency, GCMm  ]));
      Writeln(ErrOutput, Format('    %-26s %8.2f s', ['ComputeAllFanIn', GBFanInAll / TStopwatch.Frequency]));
      Writeln(ErrOutput, '    (ResolveTypeCategory is called from INSIDE ComputeCBO/ComputeAllFanIn,');
      Writeln(ErrOutput, '     so its time is also counted in theirs -- the rows are not disjoint.)');
      Flush(ErrOutput);
    end;
    Result:= Findings.ToArray;
  finally
    for var L in ByName.Values do L.Free;
    ByName.Free;
    Inv.Free;
    ParentOf.Free;
    HasExtParent.Free;
    NocCount.Free;
    RefsCache.Free;
    RtcMemo.Free;
    FanIn.Free;
    MemberToClass.Free;
    AmbiguousMember.Free;
    Findings.Free;
    TAstParseCache.Clear;
  end;
end;

initialization
  { Instrumentation only (see the counters' own note). Created once for the
    process; class-metrics runs once per lint-all, so there is nothing to reset
    between phases. }
  GRtcSeen:= TDictionary<string, Boolean>.Create;

finalization
  GRtcSeen.Free;

end.
