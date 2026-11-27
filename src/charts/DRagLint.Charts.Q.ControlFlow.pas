unit DRagLint.Charts.Q.ControlFlow;

{ drag-lint 1.56 -- lane CHB-2: the chart question `control-flow` (`ask control-flow`).
  G-44: the control-flow graph of the target routine, with a node cap that says where it stops.
  The id, its menu caption and its two count labels are a row of V156_QUESTIONS in DRagLint.Charts.Question
  (written by W2FRAME; another wording is a request to INT).

  Data: the routine's own source. The index names the routine and its body line (symbols.impl_start_line); the
  file is parsed (the lint parse cache) and the defProc that starts on that line goes to TCfgBuilder.Build, the
  same builder the flow lint and the dataflow facts use. A block of that graph is a node, a successor edge is an
  edge; block 0 is the synthetic entry and block 1 the synthetic exit. The no-return oracle is not passed: a
  call to a routine the index stores as noreturn does not end its block here (raise, Halt and Abort do).
  Cap bounds the nodes drawn: nodes are taken breadth-first from the entry (unreachable blocks last), and the
  graph label says how many blocks and edges lie beyond the cap, so a cut graph is never read as the whole one.
  A routine with goto or asm is not graphed (the builder skips it) and the question says so. }

interface

const
  /// <summary>The registered question id.</summary>
  CONTROL_FLOW_ID = 'control-flow';

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.RegularExpressions,
  TreeSitter, DRagLint.Analysis.Cfg, DRagLint.Diagnostics.ParseCache,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot;

const
  DEFAULT_CAP = 40;
  LABEL_CHARS = 36;
  APOSTROPHE = #39;
  ENTRY_FILL = '#E2F1EF';
  EXIT_FILL = '#FEF6EC';
  NORETURN_FILL = '#FDE8E8';

// the first line of a node's source text, cut to LABEL_CHARS; '' for a null node
function SnippetOf(const pNode: TTSNode; const pSrc: TBytes): string;
begin
  Result:= '';
  if pNode.IsNull then
    Exit;
  var S:= Integer(pNode.StartByte);
  var E:= Integer(pNode.EndByte);
  if (S < 0) or (E > Length(pSrc)) or (E <= S) then
    Exit;
  Result:= TEncoding.UTF8.GetString(pSrc, S, E - S);
  var Nl:= Result.IndexOfAny([#13, #10]);
  if Nl >= 0 then
    Result:= Result.Substring(0, Nl);
  Result:= Result.Trim.Replace('"', APOSTROPHE).Replace('\', '/');
  if Result.Length > LABEL_CHARS then
    Result:= Result.Substring(0, LABEL_CHARS) + '...';
end;

function FindRoutineNode(const pRoot: TTSNode; pImplStart: Integer): TTSNode;
begin
  Result:= Default(TTSNode);
  for var P in CfgFindProcs(pRoot) do
    if Integer(P.StartPoint.Row) + 1 = pImplStart then
      Exit(P);
end;

// the blocks to draw, in draw order: breadth-first from the entry, then the unreachable ones by index
function DrawOrder(const pCfg: TCfg): TArray<Integer>;
begin
  Result:= [];
  var Seen:= TDictionary<Integer, Boolean>.Create;
  var Queue:= TQueue<Integer>.Create;
  try
    Queue.Enqueue(pCfg.EntryIdx);
    Seen.Add(pCfg.EntryIdx, True);
    while Queue.Count > 0 do
    begin
      var B:= Queue.Dequeue;
      Result:= Result + [B];
      for var S in pCfg.Blocks[B].Succ do
        if not Seen.ContainsKey(S) then
        begin
          Seen.Add(S, True);
          Queue.Enqueue(S);
        end;
    end;
    for var B:= 0 to pCfg.BlockCount - 1 do
      if not Seen.ContainsKey(B) then
        Result:= Result + [B];
  finally
    Queue.Free;
    Seen.Free;
  end;
end;

// the node caption, its fill attribute and its click attribute for one drawn block
procedure DescribeBlock(const pCfg: TCfg; pIdx: Integer; const pPath: string; out pCaption, pFill, pUrl: string;
  var pNoReturn: Integer);
begin
  var Blk:= pCfg.Blocks[pIdx];
  pFill:= '';
  pUrl:= '';
  if pIdx = pCfg.EntryIdx then
  begin
    pCaption:= 'entry';
    pFill:= Format(', fillcolor="%s"', [ENTRY_FILL]);
    Exit;
  end;
  if pIdx = pCfg.ExitIdx then
  begin
    pCaption:= 'exit';
    pFill:= Format(', fillcolor="%s"', [EXIT_FILL]);
    Exit;
  end;
  pCaption:= 'B' + pIdx.ToString;
  if Blk.Items.Count > 0 then
  begin
    pCaption:= pCaption + ': ' + SnippetOf(Blk.Items[0].Node, pCfg.Src);
    if Blk.Items.Count > 1 then
      pCaption:= pCaption + Format(' (+%d)', [Blk.Items.Count - 1]);
    pUrl:= Format(', URL="%s"', [RowHref(pPath, Integer(Blk.Items[0].Node.StartPoint.Row) + 1)]);
  end;
  if Blk.NoReturn then
  begin
    Inc(pNoReturn);
    pFill:= Format(', fillcolor="%s"', [NORETURN_FILL]);
    pCaption:= pCaption + ' [no return]';
  end;
end;

/// <summary>Answers `control-flow` for pArgs.Target: the routine's control-flow graph, capped.</summary>
/// <param name="pArgs">The question arguments; Target is a routine name (qualified or bare); Cap bounds the nodes drawn.</param>
/// <param name="pOutDir">Where dot, svg, plain, png and pdf are written.</param>
/// <returns>The chart result: LeftCount = nodes drawn, RightCount = edges drawn.</returns>
/// <exception cref="EChartsIndex">The name is not in the index, ambiguous, or not a routine.</exception>
/// <exception cref="EChartsQuestion">The routine has no body in the index, its file cannot be parsed, no defProc starts on its body line, or the builder skipped it (goto / asm).</exception>
/// <remarks>Read-only. Meta fields: Resolved, Nodes, Edges, TotalNodes, TotalEdges, HiddenNodes, HiddenEdges, NoReturnBlocks, ClickTargets, Expected, AllClickable.</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
var
  Found: Boolean;
begin
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  try
    var Sel:= Index.ResolveMemberSelection(pArgs.Target, ['method', 'procedure', 'function', 'constructor', 'destructor'],
      False, 'name a routine', Found);
    if Sel.ImplStart <= 0 then
      raise EChartsQuestion.Create(Sel.QName + ' has no body in this index');
    var PF: TParsedFile;
    try
      PF:= TAstParseCache.Get(Sel.Path);
    except
      on E: Exception do
        raise EChartsQuestion.Create('cannot read ' + Sel.Path + ': ' + E.Message);
    end;
    if PF.Tree = nil then
      raise EChartsQuestion.Create('cannot parse ' + Sel.Path);
    var Proc:= FindRoutineNode(PF.Tree.RootNode, Sel.ImplStart);
    if Proc.IsNull then
      raise EChartsQuestion.Create('no routine starts at ' + Sel.Path + ':' + Sel.ImplStart.ToString);
    var Cfg:= TCfgBuilder.Build(Proc, PF.Src, True);
    var Shown:= TDictionary<Integer, Boolean>.Create;
    var Sb:= TStringBuilder.Create;
    try
      if Cfg.Skipped or (Cfg.BlockCount <= 2) then
        raise EChartsQuestion.Create(Sel.QName + ' is not graphed: it uses goto / asm, or has no statements');
      var CapNodes:= if pArgs.Cap > 0 then pArgs.Cap else DEFAULT_CAP;
      var Order:= DrawOrder(Cfg);
      var TotalEdges:= 0;
      for var B in Cfg.Blocks do
        Inc(TotalEdges, B.Succ.Count);
      for var K:= 0 to High(Order) do
        if K < CapNodes then
          Shown.Add(Order[K], True);
      var Edges:= 0;
      for var Idx in Shown.Keys do
        for var S in Cfg.Blocks[Idx].Succ do
          if Shown.ContainsKey(S) then
            Inc(Edges);

      Sb.AppendLine('digraph controlflow {');
      Sb.AppendLine('  rankdir=TB; bgcolor="transparent"; nodesep=0.5; ranksep=0.45;');
      Sb.AppendLine('  node [fontname="Consolas", fontsize=12, shape=box, style="rounded,filled", fillcolor="#FFFFFF"]; edge [fontname="Consolas", fontsize=11];');
      if Shown.Count < Cfg.BlockCount then
        Sb.AppendLine(Format('  graph [label="stops at %d of %d blocks (cap %d): %d block(s) and %d edge(s) not shown", labelloc=b];',
          [Shown.Count, Cfg.BlockCount, CapNodes, Cfg.BlockCount - Shown.Count, TotalEdges - Edges]));
      var Anchored:= 0;
      var NoRet:= 0;
      for var Idx in Order do
        if Shown.ContainsKey(Idx) then
        begin
          var Caption, Fill, Url: string;
          DescribeBlock(Cfg, Idx, Sel.Path, Caption, Fill, Url, NoRet);
          if Url <> '' then
            Inc(Anchored);
          Sb.AppendLine(Format('  b%d [label="%s"%s%s];', [Idx, XmlText(Caption), Fill, Url]));
        end;
      for var Idx in Order do
        if Shown.ContainsKey(Idx) then
          for var S in Cfg.Blocks[Idx].Succ do
            if Shown.ContainsKey(S) then
              Sb.AppendLine(Format('  b%d -> b%d;', [Idx, S]));
      Sb.AppendLine('}');

      var Msgs: TArray<string>;
      var Base:= TRegEx.Replace(Sel.QName, '[^A-Za-z0-9]', '_') + '_control_flow';
      Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, Base, Msgs);
      Result.LeftCount:= Shown.Count;
      Result.RightCount:= Edges;
      Result.ClickTargets:= Result.Layout.Anchors;
      Result.AllClickable:= Result.Layout.Anchors >= Anchored;
      Result.Fields:= [TMetaField.Str('Resolved', Sel.QName), TMetaField.Int('Nodes', Shown.Count),
        TMetaField.Int('Edges', Edges), TMetaField.Int('TotalNodes', Cfg.BlockCount),
        TMetaField.Int('TotalEdges', TotalEdges), TMetaField.Int('HiddenNodes', Cfg.BlockCount - Shown.Count),
        TMetaField.Int('HiddenEdges', TotalEdges - Edges), TMetaField.Int('NoReturnBlocks', NoRet),
        TMetaField.Int('ClickTargets', Result.Layout.Anchors), TMetaField.Int('Expected', Anchored),
        TMetaField.Bool('AllClickable', Result.AllClickable)];
    finally
      Sb.Free;
      Shown.Free;
      Cfg.Free;
    end;
  finally
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(CONTROL_FLOW_ID, Emit);

end.
