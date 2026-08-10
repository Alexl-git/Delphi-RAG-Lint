unit DRagLint.Report.RCallTree;

interface

uses
  System.SysUtils, System.Generics.Collections,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  /// <summary>One node of the reverse (upward) call tree: a symbol, its call
  /// site into the child it calls (unit:line), the absolute file + line of
  /// that call site, a cycle marker, and its own callers. Root.Site is '';
  /// Root.SiteFile/SiteLine are likewise empty/0 (no call site). Callers is
  /// empty at the depth cap or when a node is a cycle re-encounter.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (DRagLint.Report.RCallTree.pas), DRagLint.Report.RCallTree.BuildReverseCallTree.Expand (DRagLint.Report.RCallTree.pas), DRagLint.Report.RCallTree.BuildForwardCallTree.Expand (DRagLint.Report.RCallTree.pas)
  /// Used in units: DRagLint.Report.RCallTree
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRCallNode = record
    QName   : string;
    Site    : string;            // unit:line of THIS node's call into its child; '' for root
    SiteFile: string;            // absolute source path of this node's own file (the call-site file); '' for root
    SiteLine: Integer;           // 1-based call-site line; 0 for root
    Cycle   : Boolean;           // True: already expanded elsewhere; Callers left empty
    Callers : TArray<TRCallNode>;
  end;

  /// <summary>Whole-tree totals.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (DRagLint.Report.RCallTree.pas), DRagLint.Report.RCallTree.BuildReverseCallTree (DRagLint.Report.RCallTree.pas), DRagLint.Report.RCallTree.BuildForwardCallTree (DRagLint.Report.RCallTree.pas)
  /// Used in units: DRagLint.Report.RCallTree
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRCallSummary = record
    NodeCount      : Integer;
    MaxDepthReached: Integer;
    CycleCount     : Integer;
    Truncated      : Boolean;   // True when the depth cap stopped a non-cyclic expansion
  end;

  /// <summary>The reverse call tree rooted at a symbol, plus summary totals.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoReverseCallTree (DRagLint.CLI.pas), DRagLint.CLI.DoButterfly (DRagLint.CLI.pas), declaration (DRagLint.Report.RCallTree.pas)
  /// Used in units: DRagLint.CLI, DRagLint.Report.RCallTree
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRCallTree = record
    Root   : TRCallNode;
    Summary: TRCallSummary;
  end;

  /// <summary>Tuning knobs for BuildReverseCallTree.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoReverseCallTree (DRagLint.CLI.pas), DRagLint.CLI.DoButterfly (DRagLint.CLI.pas), declaration (DRagLint.Report.RCallTree.pas)
  /// Used in units: DRagLint.CLI, DRagLint.Report.RCallTree
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.DoButterfly (DRagLint.CLI.pas), DRagLint.CLI.DoReverseCallTree (DRagLint.CLI.pas)
/// Calls: Copy, Default, DRagLint.Report.RCallTree.BuildReverseCallTree.Expand, Format, LastDelimiter, StrToIntDef
/// Pure
/// <seealso cref="DRagLint.Report.RCallTree.BuildReverseCallTree.Expand"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BuildReverseCallTree(const AStore: ISymbolStore; ARootId: Int64;
  const AOpts: TRCallOptions): TRCallTree;

/// <summary>Builds the N-deep FORWARD call tree rooted at ARootId: what the root
/// calls, what those call, ... The mirror of BuildReverseCallTree over
/// ISymbolStore.GetCallEdgesFromSymbol (outgoing edges). Same TRCallTree shape,
/// same global-visited cycle policy, same depth cap. For a callee node, Site is
/// '' , SiteFile is the callee's own declaring file (full path) and SiteLine is
/// the callee's declaration line (TCallEdge carries no call-site line, so
/// navigation targets the callee's definition). The record's Callers field holds
/// the CALLEES here (field name kept for record reuse). Borrows AStore; no I/O.</summary>
/// <param name="AStore">Open store (ids are per-DB).</param>
/// <param name="ARootId">Symbol id of the tree root.</param>
/// <param name="AOpts">Depth cap.</param>
/// <returns>The tree + summary. Root.Site is ''.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.DoButterfly (DRagLint.CLI.pas), DRagLint.CLI.DoReverseCallTree (DRagLint.CLI.pas)
/// Calls: Default, DRagLint.Report.RCallTree.BuildForwardCallTree.Expand
/// Pure
/// <seealso cref="DRagLint.Report.RCallTree.BuildForwardCallTree.Expand"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BuildForwardCallTree(const AStore: ISymbolStore; ARootId: Int64;
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
    Sym    : TSymbol;
    CPos   : Integer;
  begin
    Result := Default(TRCallNode);
    Sym := AStore.GetSymbolById(AId);
    Result.QName := Sym.QualifiedName;
    Result.Site  := ASite;
    { The call site lives in THIS node's own file (it is the caller). SiteFile =
      the symbol's declaring file (full path); SiteLine parsed from ASite's :N. }
    Result.SiteFile := AStore.GetFilePath(Sym.FileId);
    if ASite <> '' then
    begin
      CPos := LastDelimiter(':', ASite);
      if CPos > 0 then Result.SiteLine := StrToIntDef(Copy(ASite, CPos + 1, MaxInt), 0);
    end;
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

function BuildForwardCallTree(const AStore: ISymbolStore; ARootId: Int64;
  const AOpts: TRCallOptions): TRCallTree;
var
  Visited: TDictionary<Int64, Boolean>;
  Sum    : TRCallSummary;

  function Expand(AId: Int64; ADepth, ALevel: Integer): TRCallNode;
  var
    Edges : TArray<TCallEdge>;
    E     : TCallEdge;
    Kids  : TList<TRCallNode>;
    Sym    : TSymbol;
    SeenChild: TDictionary<Int64, Boolean>;
  begin
    Result := Default(TRCallNode);
    Sym := AStore.GetSymbolById(AId);
    Result.QName    := Sym.QualifiedName;
    Result.Site     := '';
    { Callee node navigates to the callee's OWN declaration (no call-site line on
      the edge). SiteFile = declaring file; SiteLine = decl line. }
    Result.SiteFile := AStore.GetFilePath(Sym.FileId);
    Result.SiteLine := Sym.StartLine;
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
    Edges := AStore.GetCallEdgesFromSymbol(AId);
    if Length(Edges) = 0 then Exit;
    Kids := TList<TRCallNode>.Create;
    SeenChild := TDictionary<Int64, Boolean>.Create;
    try
      if ADepth = 1 then Sum.Truncated := True;
      for E in Edges do
      begin
        if E.TargetSymbolId <= 0 then Continue;
        if SeenChild.ContainsKey(E.TargetSymbolId) then Continue; { dedup sibling edges }
        SeenChild.Add(E.TargetSymbolId, True);
        Kids.Add(Expand(E.TargetSymbolId, ADepth - 1, ALevel + 1));
      end;
      Result.Callers := Kids.ToArray;
    finally
      SeenChild.Free;
      Kids.Free;
    end;
  end;

begin
  Sum := Default(TRCallSummary);
  Visited := TDictionary<Int64, Boolean>.Create;
  try
    Result.Root := Expand(ARootId, AOpts.Depth, 0);
    Result.Summary := Sum;
  finally
    Visited.Free;
  end;
end;

end.
