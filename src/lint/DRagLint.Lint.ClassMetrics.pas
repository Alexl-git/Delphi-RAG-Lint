unit DRagLint.Lint.ClassMetrics;

{ v0.78 CK class metrics (#6): DIT, NOC, CBO, RFC, LCOM4. Store-backed,
  project-wide -- runs only in lint-all / lint-project (not the per-file LSP).
  Complements the coarse god-class rule with individually-tunable metrics.
  Stateless; reads an open store; never raises. }

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
  /// <summary>Computes the five Chidamber and Kemerer class metrics
  /// (DIT/NOC/CBO/RFC/LCOM4) over an indexed symbol store and returns 'info'
  /// findings for classes whose value exceeds the configured threshold.</summary>
  /// <remarks>Stateless; project-wide -- invoke from the lint-all / lint-project
  /// store path only, never the per-file LSP. Reads the store read-only; never raises.</remarks>
  TClassMetrics = class
  public
    /// <summary>Computes the five CK class metrics (DIT/NOC/CBO/RFC/LCOM4) over
    /// AStore and returns findings for classes exceeding each rule's configured
    /// threshold. A nil store yields no findings. ARuleId, when non-empty,
    /// restricts evaluation to that one rule id.</summary>
    /// <param name="AStore">An open, migrated symbol store; nil -> empty result.</param>
    /// <param name="ACfg">Active lint config (supplies per-rule thresholds).</param>
    /// <param name="ARuleId">Single-rule filter for --rule; '' evaluates all five.</param>
    /// <returns>'info' findings anchored at each offending class declaration.</returns>
    /// <remarks>Project-wide; call from lint-all / lint-project only. Never raises.</remarks>
    class function Run(const AStore: ISymbolStore; const ACfg: TLintConfig;
      const ARuleId: string = ''): TArray<TLintFinding>;
  end;

implementation

type
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
  Findings    : TList<TLintFinding>              ;
  TNOC        : Integer                          ;
  TDIT        : Integer                          ;
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

  function InAnyMethodBody(const AInfo: TClassInfo; ALine: Integer): Boolean;
  var
    M: TSymbol;
  begin
    for M in AInfo.Methods do
      if (M.ImplStartLine > 0) and (ALine >= M.ImplStartLine) and (ALine <= M.ImplEndLine) then
        Exit(True);
    Result:= False;
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

begin
  Result:= nil;
  if AStore = nil then Exit;

  Inv         := TDictionary<Int64, TClassInfo>.Create;
  ByName      := TDictionary<string, TList<Int64>>.Create;
  ParentOf    := TDictionary<Int64, Int64>.Create;
  HasExtParent:= TDictionary<Int64, Boolean>.Create;
  NocCount    := TDictionary<Int64, Integer>.Create;
  RefsCache   := TDictionary<Int64, TArray<TReference>>.Create;
  Findings    := TList<TLintFinding>.Create;
  try
    TNOC:= ACfg.ThresholdFor('too-many-children', 10);
    TDIT:= ACfg.ThresholdFor('deep-inheritance', 6);

    BuildInventory;
    ResolveParents;
    ComputeNOC;

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
    Findings.Free;
    TAstParseCache.Clear;
  end;
end;

end.
