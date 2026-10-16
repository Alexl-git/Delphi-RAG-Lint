unit DRagLint.Report.RCallTree;

interface

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  /// <summary>One node of the reverse (upward) call tree: a symbol, its call
  /// site into the child it calls (unit:line), the absolute file + line of
  /// that call site, a cycle marker, and its own callers. Root.Site is '';
  /// Root.SiteFile/SiteLine are likewise empty/0 (no call site). Callers is
  /// empty at the depth cap or when a node is a cycle re-encounter.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoButterfly.BuildNodeJson (DRagLint.CLI.pas), DRagLint.CLI.DoButterfly.RenderNodeText (DRagLint.CLI.pas), DRagLint.CLI.DoReverseCallTree.BuildNodeJson (DRagLint.CLI.pas), DRagLint.CLI.DoReverseCallTree.RenderNodeChart (DRagLint.CLI.pas), DRagLint.CLI.DoReverseCallTree.RenderNodeText (DRagLint.CLI.pas) (+4 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Report.RCallTree</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRCallNode = record
    QName   : string;
    Site    : string;            // unit:line of THIS node's call into its child; '' for root
    SiteFile: string;            // absolute source path of this node's own file (the call-site file); '' for root
    SiteLine: Integer;           // 1-based call-site line; 0 for root
    Cycle   : Boolean;           // True: already expanded elsewhere; Callers left empty
    Confidence: string;          // the edge into this node: 'certain' | 'ambiguous'; '' for root (Gitea drag-lint#13)
    Callers : TArray<TRCallNode>;
  end;

  /// <summary>Whole-tree totals.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Report.RCallTree.pas), DRagLint.Report.RCallTree.BuildForwardCallTree (DRagLint.Report.RCallTree.pas), DRagLint.Report.RCallTree.BuildReverseCallTree (DRagLint.Report.RCallTree.pas)</para>
  /// <para>Used in units: DRagLint.Report.RCallTree</para>
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
  /// <para>Used by: declaration (DRagLint.Report.RCallTree.pas), DRagLint.CLI.DoButterfly (DRagLint.CLI.pas), DRagLint.CLI.DoReverseCallTree (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Report.RCallTree</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRCallTree = record
    Root   : TRCallNode;
    Summary: TRCallSummary;
  end;

  /// <summary>Tuning knobs for BuildReverseCallTree.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Report.RCallTree.pas), DRagLint.CLI.DoButterfly (DRagLint.CLI.pas), DRagLint.CLI.DoReverseCallTree (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Report.RCallTree</para>
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
/// <para>Called from: DRagLint.CLI.DoButterfly (DRagLint.CLI.pas), DRagLint.CLI.DoReverseCallTree (DRagLint.CLI.pas)</para>
/// <para>Calls: Copy, Default, DRagLint.Report.RCallTree.BuildReverseCallTree.Expand, Format, LastDelimiter, StrToIntDef</para>
/// <para>Pure</para>
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
/// <para>Called from: DRagLint.CLI.DoButterfly (DRagLint.CLI.pas), DRagLint.CLI.DoReverseCallTree (DRagLint.CLI.pas)</para>
/// <para>Calls: Default, DRagLint.Report.RCallTree.BuildForwardCallTree.Expand</para>
/// <para>Pure</para>
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

  function Expand(AId: Int64; ADepth, ALevel: Integer; const ASite, AConfidence: string): TRCallNode;
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
    Result.Confidence:= AConfidence;
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
        if C.EnclosingSymbolId <= 0 then
        begin
          { A CALL WITH NO ROUTINE AROUND IT is still a caller (Gitea
            drag-lint#20): a program's begin..end. block, a unit's
            initialization/finalization. There is no symbol to name, so the
            node is the SITE -- a leaf that navigates to the call. It used to be
            dropped, and the tree said nobody called the routine from there. }
          var Leaf: TRCallNode:= Default(TRCallNode);
          Leaf.QName     := Format('(outside any routine) %s:%d', [C.Location, C.CallSiteLine]);
          Leaf.Site      := Format('%s:%d', [C.Location, C.CallSiteLine]);
          Leaf.SiteFile  := C.FullPath;
          Leaf.SiteLine  := C.CallSiteLine;
          Leaf.Confidence:= C.Confidence;
          Inc(Sum.NodeCount);
          Kids.Add(Leaf);
          Continue;
        end;
        Kids.Add(Expand(C.EnclosingSymbolId, ADepth - 1, ALevel + 1,
          Format('%s:%d', [C.Location, C.CallSiteLine]), C.Confidence));
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
    Result.Root := Expand(ARootId, AOpts.Depth, 0, '', '');
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

  function Expand(AId: Int64; ADepth, ALevel: Integer; const ASite, AConfidence: string): TRCallNode;
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
    { SITE IS THE CALL SITE, as in the callers tree (Gitea drag-lint#11): the
      parent's file and the line of its FIRST call to this node. It was '' --
      the edge carried no line -- so a "call tree with call sites" had none in
      this direction. SiteFile/SiteLine still navigate to the callee's own
      declaration: the IDE plugin's double-click reads them, and that target
      is a contract this fix does not move. }
    Result.Site      := ASite;
    Result.Confidence:= AConfidence;
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
      { One child per target: its FIRST call site, and 'certain' when ANY of the
        sibling edges to it is certain -- an ambiguous duplicate must not
        downgrade a target the resolver also bound for sure. }
      var FirstLine: TDictionary<Int64, Integer>:= TDictionary<Int64, Integer>.Create;
      var AnyCertain: TDictionary<Int64, Boolean>:= TDictionary<Int64, Boolean>.Create;
      try
        for E in Edges do
        begin
          if E.TargetSymbolId <= 0 then Continue;
          var L: Integer;
          if (not FirstLine.TryGetValue(E.TargetSymbolId, L)) or ((E.CallLine > 0) and (E.CallLine < L)) then
            FirstLine.AddOrSetValue(E.TargetSymbolId, E.CallLine);
          var C: Boolean;
          if not AnyCertain.TryGetValue(E.TargetSymbolId, C) then C:= False;
          AnyCertain.AddOrSetValue(E.TargetSymbolId, C or SameText(E.Confidence, 'certain'));
        end;
        var ParentFile: string:= TPath.GetFileName(AStore.GetFilePath(Sym.FileId));
        for E in Edges do
        begin
          if E.TargetSymbolId <= 0 then Continue;
          if SeenChild.ContainsKey(E.TargetSymbolId) then Continue; { dedup sibling edges }
          SeenChild.Add(E.TargetSymbolId, True);
          var KidLine: Integer:= FirstLine[E.TargetSymbolId];
          var KidSite: string:= '';
          if KidLine > 0 then KidSite:= Format('%s:%d', [ParentFile, KidLine]);
          var KidConf: string:= 'ambiguous';
          if AnyCertain[E.TargetSymbolId] then KidConf:= 'certain';
          Kids.Add(Expand(E.TargetSymbolId, ADepth - 1, ALevel + 1, KidSite, KidConf));
        end;
      finally
        AnyCertain.Free;
        FirstLine.Free;
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
    Result.Root := Expand(ARootId, AOpts.Depth, 0, '', '');
    Result.Summary := Sum;
  finally
    Visited.Free;
  end;
end;

end.
