unit DRagLint.Report.RCallTree;

interface

uses
  System.SysUtils, System.Generics.Collections,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  /// <summary>One node of the reverse (upward) call tree: a symbol, its call
  /// site into the child it calls (unit:line), a cycle marker, and its own
  /// callers. Root.Site is ''. Callers is empty at the depth cap or when a
  /// node is a cycle re-encounter.</summary>
  TRCallNode = record
    QName  : string;
    Site   : string;            // unit:line of THIS node's call into its child; '' for root
    Cycle  : Boolean;           // True: already expanded elsewhere; Callers left empty
    Callers: TArray<TRCallNode>;
  end;

  /// <summary>Whole-tree totals.</summary>
  TRCallSummary = record
    NodeCount      : Integer;
    MaxDepthReached: Integer;
    CycleCount     : Integer;
    Truncated      : Boolean;   // True when the depth cap stopped a non-cyclic expansion
  end;

  /// <summary>The reverse call tree rooted at a symbol, plus summary totals.</summary>
  TRCallTree = record
    Root   : TRCallNode;
    Summary: TRCallSummary;
  end;

  /// <summary>Tuning knobs for BuildReverseCallTree.</summary>
  TRCallOptions = record
    Depth: Integer;             // remaining levels of callers to expand; default 3
  end;

/// <summary>Builds the N-deep REVERSE call tree rooted at ARootId: who calls the
/// root, who calls them, ... Reuses ISymbolStore.FindResolvedCallers. Bounded by
/// AOpts.Depth AND a global-visited set so recursive cycles terminate: a
/// re-encountered symbol yields a node with Cycle=True and no further expansion
/// (same policy as callgraph). Borrows AStore; no I/O.</summary>
/// <param name="AStore">Open store (ids are per-DB).</param>
/// <param name="ARootId">Symbol id of the tree root.</param>
/// <param name="AOpts">Depth cap.</param>
/// <returns>The tree + summary. Root.Site is ''.</returns>
function BuildReverseCallTree(const AStore: ISymbolStore; ARootId: Int64;
  const AOpts: TRCallOptions): TRCallTree;

implementation

function BuildReverseCallTree(const AStore: ISymbolStore; ARootId: Int64;
  const AOpts: TRCallOptions): TRCallTree;
var
  Visited: TDictionary<Int64, Boolean>;
  Sum    : TRCallSummary;

  function Expand(AId: Int64; ADepth, ALevel: Integer; const ASite: string): TRCallNode;
  var
    Callers: TArray<TResolvedCaller>;
    C      : TResolvedCaller;
    Kids   : TList<TRCallNode>;
  begin
    Result := Default(TRCallNode);
    Result.QName := AStore.GetSymbolById(AId).QualifiedName;
    Result.Site  := ASite;
    Inc(Sum.NodeCount);
    if ALevel > Sum.MaxDepthReached then Sum.MaxDepthReached := ALevel;
    if Visited.ContainsKey(AId) then
    begin
      Result.Cycle := True;
      Inc(Sum.CycleCount);
      Exit;
    end;
    Visited.Add(AId, True);
    if ADepth <= 0 then Exit;
    Callers := AStore.FindResolvedCallers(AId);
    if Length(Callers) = 0 then Exit;
    Kids := TList<TRCallNode>.Create;
    try
      // ADepth >= 1 here (ADepth <= 0 returned above). At ADepth = 1 the children
      // are expanded but THEIR callers are cut by the depth cap -> mark truncated
      // whenever a child itself has callers we won't reach.
      if (ADepth = 1) and (Length(Callers) > 0) then Sum.Truncated := True;
      for C in Callers do
      begin
        if C.EnclosingSymbolId <= 0 then Continue;
        Kids.Add(Expand(C.EnclosingSymbolId, ADepth - 1, ALevel + 1,
          Format('%s:%d', [C.Location, C.CallSiteLine])));
      end;
      Result.Callers := Kids.ToArray;
    finally
      Kids.Free;
    end;
  end;

begin
  Sum := Default(TRCallSummary);
  Visited := TDictionary<Int64, Boolean>.Create;
  try
    Result.Root := Expand(ARootId, AOpts.Depth, 0, '');
    Result.Summary := Sum;
  finally
    Visited.Free;
  end;
end;

end.
