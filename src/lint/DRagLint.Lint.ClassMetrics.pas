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
  , System.Generics.Collections
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
  /// <remarks>Stateless; project-wide -- invoke from the lint-all store path only
  /// (not lint-project or the per-file LSP). Reads the store read-only; never raises.</remarks>
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
    /// <remarks>Project-wide; call from lint-all only. Never raises.</remarks>
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
  FanIn       : TDictionary<Int64, Integer>      ; { v0.81: target class id -> distinct inbound source count (Ca) }
  Findings    : TList<TLintFinding>              ;
  TNOC        : Integer                          ;
  TDIT        : Integer                          ;
  TRFC        : Integer                          ;
  TCBO        : Integer                          ;
  TLCOM       : Integer                          ;
  TFanOut     : Integer                          ;
  TFanIn      : Integer                          ;
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
        if AStore.ResolveTypeCategory(Nm, Info.FileId) <> tcClass then Continue;
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
        if SameText(R.Kind, 'call') and (R.NameText <> '') and EnclosedByOwnMethod(AInfo, R.EnclosingSymbolId) then
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
      Anc:= AStore.GetTransitiveAncestors(AInfo.Id);
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
        if AStore.ResolveTypeCategory(R.NameText, AInfo.FileId) = tcClass then
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
        Anc:= AStore.GetTransitiveAncestors(Src.Id);
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
          if AStore.ResolveTypeCategory(R.NameText, Src.FileId) = tcClass then
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

begin
  Result:= nil;
  if AStore = nil then Exit;

  Inv         := TDictionary<Int64, TClassInfo>.Create;
  ByName      := TDictionary<string, TList<Int64>>.Create;
  ParentOf    := TDictionary<Int64, Int64>.Create;
  HasExtParent:= TDictionary<Int64, Boolean>.Create;
  NocCount    := TDictionary<Int64, Integer>.Create;
  RefsCache   := TDictionary<Int64, TArray<TReference>>.Create;
  FanIn       := TDictionary<Int64, Integer>.Create;
  Findings    := TList<TLintFinding>.Create;
  try
    TNOC:= ACfg.ThresholdFor('too-many-children', 10);
    TDIT:= ACfg.ThresholdFor('deep-inheritance', 6);
    TRFC:= ACfg.ThresholdFor('high-response', 50);
    TCBO:= ACfg.ThresholdFor('high-coupling', 20);
    TLCOM:= ACfg.ThresholdFor('low-cohesion', 26);
    TFanOut:= ACfg.ThresholdFor('fan-out', 20); { aliases CBO; field-tune }
    TFanIn := ACfg.ThresholdFor('fan-in', 20);  { field-tune }

    BuildInventory;
    ResolveParents;
    ComputeNOC;
    ComputeAllFanIn;

    for CI in Inv.Values do
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
        var Rfc: Integer:= ComputeRFC(CI);
        if Rfc > TRFC then
          Emit('high-response',
            Format('High RFC: %s has a response set of %d (>%d) -- many methods and calls to test/understand', [CI.Name, Rfc, TRFC]),
            CI);
      end;

      if WantRule('high-coupling') then
      begin
        var Cbo: Integer:= ComputeCBO(CI);
        if Cbo > TCBO then
          Emit('high-coupling',
            Format('High CBO: %s is coupled to %d other classes (>%d) -- consider reducing dependencies', [CI.Name, Cbo, TCBO]),
            CI);
      end;

      if WantRule('low-cohesion') then
      begin
        var Lc: Integer:= ComputeLCOM4(CI);
        if Lc > TLCOM then
          Emit('low-cohesion',
            Format('Low cohesion: %s has LCOM4=%d (>%d) -- the class may combine unrelated responsibilities; consider splitting', [CI.Name, Lc, TLCOM]),
            CI);
      end;

      if WantRule('middle-man') then
      begin
        var MM: TMiddleManResult:= ComputeMiddleMan(CI);
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
    FanIn.Free;
    Findings.Free;
    TAstParseCache.Clear;
  end;
end;

end.
