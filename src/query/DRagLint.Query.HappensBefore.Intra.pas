unit DRagLint.Query.HappensBefore.Intra;

{ drag-lint 1.52 -- lane HBINTRA: must-analysis inside one routine.
  Scaffold created EMPTY by lane FRAME (listed in drag-lint.dpr / .dproj); lane HBINTRA owns it.

  Plan docs\superpowers\plans\2026-11-17-happens-before-phase1.md, lane INTRA; spec
  docs\superpowers\specs\2026-11-17-happens-before-design.md sec. 5.3. Truth table:
  tests\autotest\run_check_init_intra.ps1 over tests\fixtures\happens-before\intra-shapes.

  VERIFIED (plan step 2, against DRagLint.Analysis.Cfg as of 1.52):
  * try..except: every handler block has an edge from the block BEFORE the try (B-30), from the try
    entry block and from every non-divert block of the try body (C1). With meet = AND, the state at a
    handler entry is therefore the try ENTRY state -- exactly the conservative rule of spec 5.3. A
    handler that falls through is wired to the follow block, so the state after try..except is
    AND(normal completion, handler exits); a diverting handler (raise / exit) is not wired. No extra
    edge needed.
  * try..finally: TCfg deliberately has NO exceptional edge into the finally (only normal completion,
    or the try entry when the body always diverts). The state AFTER the finally is right as it is (only
    a normal completion continues there), but a query INSIDE a finally body would read the
    normal-path state, which is unsound: the finally also runs when the body raised before its marks.
    Added here: a query inside the finally body of try T is ANDed with the state before T's first
    item (the try entry). Conservative cost: a mark INSIDE the same finally, before the query, is
    not credited (MAY, never a wrong SET).
  * raise / Halt / Abort blocks (TCfgBlock.NoReturn) keep an edge to Exit; they are left out of the
    meet at the normal exit.
  Other cuts: a Skipped CFG (goto / label / asm) answers False everywhere; an item inside a `with`
  (Opaque) never marks; a mark inside an anonymous-method body, the right operand of a short-circuit
  `and` / `or`, or a branch of an `if` EXPRESSION never marks (it may not run); a query inside an
  anonymous-method body is InClosure and False (judged as an escaped routine by the solver); an
  unreachable block reads False. Columns are CHARACTER columns, the index's (1.52 EXTGAPS2: node byte
  columns are mapped through Utf8ByteColToCharCol). }

interface

uses
  System.SysUtils
, TreeSitter
, DRagLint.Core.Interfaces
, DRagLint.Query.HappensBefore.Types
  ;

type
  /// <summary>The answer for one QUERY site of <see cref="SolveRoutine"/>.</summary>
  /// <remarks>
  /// Done is a MUST answer: False means "not proven", never "proven unset".
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Intra.pas) ?, declaration (DRagLint.Query.HappensBefore.pas) ?, DRagLint.Query.HappensBefore.TSolver.JudgeUse (DRagLint.Query.HappensBefore.pas) ?, DRagLint.Query.HappensBefore.TSolver.PrefixDone (DRagLint.Query.HappensBefore.pas) ?, DRagLint.Query.HappensBefore.TSolver.StateAt (DRagLint.Query.HappensBefore.pas)</para>
  /// <para>Used in units: DRagLint.Query.HappensBefore, DRagLint.Query.HappensBefore.Intra</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbQueryState = record
    /// <summary>The query site as passed in.</summary>
    Site: THbSite;
    /// <summary>True = "A has completed" on EVERY path that reaches the site, just BEFORE the CFG
    /// item that contains it (a mark in the same item does not count).</summary>
    Done: Boolean;
    /// <summary>False when no CFG item of the routine covers the site (Done is then False).</summary>
    Located: Boolean;
    /// <summary>True when the site lies inside an anonymous-method body: the enclosing routine does
    /// not execute it, so Done is False and the caller judges it as an escaped routine.</summary>
    InClosure: Boolean;
  end;

  /// <summary>Result of <see cref="SolveRoutine"/>: the bit before each query and at normal exit.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Query.HappensBefore.Fields.TFieldSolver.Solve (DRagLint.Query.HappensBefore.Fields.pas), DRagLint.Query.HappensBefore.Intra.SolveRoutine (DRagLint.Query.HappensBefore.Intra.pas), DRagLint.Query.HappensBefore.Receiver.TRecvSolver.Solve (DRagLint.Query.HappensBefore.Receiver.pas), DRagLint.Query.HappensBefore.TopLevelSolve (DRagLint.Query.HappensBefore.pas), DRagLint.Query.HappensBefore.TSolver.RawSolve (DRagLint.Query.HappensBefore.pas) (+9 more)</para>
  /// <para>Used in units: DRagLint.Query.HappensBefore, DRagLint.Query.HappensBefore.Fields, DRagLint.Query.HappensBefore.Intra, DRagLint.Query.HappensBefore.Receiver</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbRoutineState = record
    /// <summary>The routine asked about (symbols.id).</summary>
    RoutineId: Int64;
    /// <summary>False when the routine symbol, its file or its `defProc` could not be found; every
    /// other field is then False.</summary>
    Found: Boolean;
    /// <summary>True when the CFG builder refused the routine (goto / label / asm): every bit is
    /// False (reason code cfg-skipped).</summary>
    CfgSkipped: Boolean;
    /// <summary>One entry per QUERY, in the order of the pQueries argument.</summary>
    Queries: TArray<THbQueryState>;
    /// <summary>The bit at NORMAL exit (raise / Halt / Abort paths left out): MustA(routine) when
    /// solved with pEntryDone = False. False when ExitReachable is False.</summary>
    ExitDone: Boolean;
    /// <summary>False when no path reaches the normal exit (the routine always raises).</summary>
    ExitReachable: Boolean;
  end;

/// <summary>Forward must-analysis of "A has completed" inside one routine (spec 5.3): one boolean
/// per CFG block, meet = AND, entry = pEntryDone; a CFG item whose span contains a MARK sets the bit.</summary>
/// <param name="pStore">Open index; read only (symbol row and file path).</param>
/// <param name="pRoutineId">symbols.id of the routine (procedure, function or method).</param>
/// <param name="pMarks">Sites that perform A in this routine: a counting writer site, or a call site
/// whose callee has MustA. Sites outside the routine body match no item and are ignored.</param>
/// <param name="pQueries">Sites to judge (the use, or call sites on the way to the use).</param>
/// <param name="pEntryDone">The bit on routine entry (False = MustA question).</param>
/// <returns>The state just before each query and at normal exit; never raises for a missing
/// routine (Found = False).</returns>
/// <remarks>
/// Parses through TAstParseCache (the cache owns the tree; not thread-safe, like the cache).
/// Every doubt answers False: a wrong True is a wrong SET.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.Fields.TFieldSolver.Solve (DRagLint.Query.HappensBefore.Fields.pas), DRagLint.Query.HappensBefore.Receiver.TRecvSolver.Solve (DRagLint.Query.HappensBefore.Receiver.pas), DRagLint.Query.HappensBefore.TSolver.RawSolve (DRagLint.Query.HappensBefore.pas)</para>
/// <para>Calls: Default, DRagLint.Analysis.Cfg.TCfgBuilder.Build, DRagLint.Query.HappensBefore.Intra.LocateDefProc, DRagLint.Query.HappensBefore.Intra.TIntraSolver.Create, DRagLint.Query.HappensBefore.Intra.TIntraSolver.Run, TreeSitter.TTSNodeHelper.IsNull</para>
/// <para>Returns: Default(THbRoutineState)</para>
/// <seealso cref="DRagLint.Analysis.Cfg.TCfgBuilder.Build"/>
/// <seealso cref="DRagLint.Query.HappensBefore.Intra.LocateDefProc"/>
/// <seealso cref="DRagLint.Query.HappensBefore.Intra.TIntraSolver.Create"/>
/// <seealso cref="DRagLint.Query.HappensBefore.Intra.TIntraSolver.Run"/>
/// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SolveRoutine(const pStore: ISymbolStore; pRoutineId: Int64; const pMarks, pQueries: TArray<THbSite>;
  pEntryDone: Boolean): THbRoutineState;

/// <summary>True when the index's stored must-write fact of a routine (symbol_facts.must_writes,
/// 1.56 B5) lists pName: the routine assigns it on every path that returns normally.</summary>
/// <param name="pStore">Read-only store over the index.</param>
/// <param name="pRoutineId">symbols.id of the routine.</param>
/// <param name="pName">`Result`, a var / out parameter, or an OWN field of the routine's class, as
/// declared; compared without case.</param>
/// <returns>False when the fact does not list the name, the routine has no fact row, or the index was
/// written before 1.56. False is NOT a proof of the opposite: the fact leaves out a write through a
/// var / out argument, a partial write and an inherited field (a caller then solves the routine).</returns>
/// <remarks>The fact never lists a `:= nil` write, so it agrees with the engine's assign-nil rule
/// (ruling HB4). Read-only; one store read per call.</remarks>
function HbFactMustWrites(const pStore: ISymbolStore; pRoutineId: Int64; const pName: string): Boolean;

/// <summary>True when the source position pSite lies inside the span of pNode.</summary>
/// <param name="pSrc">The source bytes the tree was parsed from.</param>
/// <param name="pNode">Any tree-sitter node; a null node contains nothing useful (its span is 0..0).</param>
/// <param name="pSite">1-based line and column; Col &lt;= 0 means "the whole line": the node only has to
/// intersect that line.</param>
/// <returns>True when the site is at or after the node start and before its end.</returns>
/// <remarks>
/// pSrc = the bytes the tree was parsed from: node byte columns are mapped to the index's
/// CHARACTER columns (1.52 EXTGAPS2) before they are compared with pSite.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.Intra.TIntraSolver.ApplyMarks (DRagLint.Query.HappensBefore.Intra.pas), DRagLint.Query.HappensBefore.Intra.TIntraSolver.Occurrences (DRagLint.Query.HappensBefore.Intra.pas), DRagLint.Query.HappensBefore.Intra.TIntraSolver.Run (DRagLint.Query.HappensBefore.Intra.pas), DRagLint.Query.HappensBefore.Intra.WalkTo (DRagLint.Query.HappensBefore.Intra.pas), DRagLint.Query.HappensBefore.MarkIsMust (DRagLint.Query.HappensBefore.pas) (+1 more)</para>
/// <para>Calls: DRagLint.Core.Encoding.Utf8ByteColToCharCol, InRange, Integer, TreeSitter.TTSNodeHelper.EndByte, TreeSitter.TTSNodeHelper.EndPoint, TreeSitter.TTSNodeHelper.StartByte, TreeSitter.TTSNodeHelper.StartPoint</para>
/// <para>Returns: AfterStart and BeforeEnd</para>
/// <seealso cref="DRagLint.Core.Encoding.Utf8ByteColToCharCol"/>
/// <seealso cref="TreeSitter.TTSNodeHelper.EndByte"/>
/// <seealso cref="TreeSitter.TTSNodeHelper.EndPoint"/>
/// <seealso cref="TreeSitter.TTSNodeHelper.StartByte"/>
/// <seealso cref="TreeSitter.TTSNodeHelper.StartPoint"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HbNodeContains(const pSrc: TBytes; const pNode: TTSNode; const pSite: THbSite): Boolean;

/// <summary>Walks from pItem down to the node that holds pSite and tells whether the site runs every
/// time pItem runs.</summary>
/// <param name="pSrc">The source bytes the tree was parsed from (operator text is read from them).</param>
/// <param name="pItem">The statement / CFG item that contains the site.</param>
/// <param name="pSite">The site to reach (1-based line, column).</param>
/// <param name="pInLambda">Set to True when an anonymous-method body encloses the site; the walk stops
/// there.</param>
/// <returns>True when the site may NOT run when pItem runs: it sits under the right operand of a
/// short-circuit `and` / `or`, or under an if-expression branch.</returns>
/// <remarks>
/// Shared by the CFG solver (SolveRoutine) and the top-level solver of
/// DRagLint.Query.HappensBefore, so both apply the same cuts. Pure; no allocation beyond strings.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.Intra.TIntraSolver.PathTo (DRagLint.Query.HappensBefore.Intra.pas), DRagLint.Query.HappensBefore.MarkIsMust (DRagLint.Query.HappensBefore.pas), DRagLint.Query.HappensBefore.TopLevelSolve (DRagLint.Query.HappensBefore.pas)</para>
/// <para>Calls: Default, DRagLint.Query.HappensBefore.Intra.WalkTo</para>
/// <para>Returns: Path.Guarded</para>
/// <para>Mutates: pInLambda (out)</para>
/// <seealso cref="DRagLint.Query.HappensBefore.Intra.WalkTo"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HbSiteGuarded(const pSrc: TBytes; const pItem: TTSNode; const pSite: THbSite;
  out pInLambda: Boolean): Boolean;

implementation

uses
  System.Math
, DRagLint.Core.Encoding
, System.Generics.Collections
, DRagLint.Core.Model
, DRagLint.Analysis.Cfg
, DRagLint.Diagnostics.ParseCache
  ;

type
  /// <summary>One occurrence of a CFG item: block index + item index (an item can occur in several
  /// blocks when a finally body is copied onto an exit path).</summary>
  TItemRef = record
    Block: Integer;
    Item: Integer;
  end;

  /// <summary>What a walk from a CFG item down to a site met on the way.</summary>
  TSitePath = record
    /// <summary>An anonymous-method body encloses the site.</summary>
    InLambda: Boolean;
    /// <summary>The site may not run when the item runs (short-circuit rhs, if-expression branch).</summary>
    Guarded: Boolean;
  end;

  /// <summary>The solver for one routine CFG. Owns nothing: the CFG belongs to the caller.</summary>
  TIntraSolver = class
  strict private
    FCfg: TCfg;
    FSrc: TBytes;
    FEntryDone: Boolean;
    FReach: TArray<Boolean>;
    FIn: TArray<Boolean>;
    FOut: TArray<Boolean>;
    FMarked: TArray<TArray<Boolean>>;
    function PathTo(const pItem: TTSNode; const pSite: THbSite): TSitePath;
    procedure ComputeReach;
    procedure ApplyMarks(const pMarks: TArray<THbSite>);
    procedure Solve;
    function StateBefore(const pRef: TItemRef): Boolean;
    function Occurrences(const pSite: THbSite): TArray<TItemRef>;
    function TryEntryState(const pTryBody: TTSNode): Boolean;
    procedure CollectFinallys(const pNode: TTSNode; pList: TList<TPair<TTSNode, TTSNode>>);
  public
    constructor Create(pCfg: TCfg; pEntryDone: Boolean);
    procedure Run(const pMarks: TArray<THbSite>; var pState: THbRoutineState);
  end;

const
  NODE_LAMBDA = 'lambda';
  NODE_DEFPROC = 'defProc';

{ TIntraSolver }

constructor TIntraSolver.Create(pCfg: TCfg; pEntryDone: Boolean);
begin
  inherited Create;
  FCfg:= pCfg;
  FSrc:= pCfg.Src;
  FEntryDone:= pEntryDone;
end;

{ site walk (exported: HbNodeContains, HbSiteGuarded) }

function NodeText(const pSrc: TBytes; const pNode: TTSNode): string;
begin
  Result:= '';
  if pNode.IsNull or (Integer(pNode.EndByte) > Length(pSrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(pSrc, Integer(pNode.StartByte), Integer(pNode.EndByte - pNode.StartByte));
end;

function HbNodeContains(const pSrc: TBytes; const pNode: TTSNode; const pSite: THbSite): Boolean;
var
  Row, Col, SR, SC, ER, EC: Integer;
begin
  Row:= pSite.Line - 1;
  SR:= Integer(pNode.StartPoint.row);
  ER:= Integer(pNode.EndPoint.row);
  if pSite.Col <= 0 then Exit(InRange(Row, SR, ER));  { whole line: the node intersects it }
  Col:= pSite.Col - 1;
  SC:= Utf8ByteColToCharCol(pSrc, pNode.StartByte, pNode.StartPoint.column); { 1.52 EXTGAPS2: sites carry index CHARACTER columns }
  EC:= Utf8ByteColToCharCol(pSrc, pNode.EndByte, pNode.EndPoint.column);
  var AfterStart:= (Row > SR) or ((Row = SR) and (Col >= SC));
  var BeforeEnd:= (Row < ER) or ((Row = ER) and (Col < EC));
  Result:= AfterStart and BeforeEnd;
end;

function SameNode(const pLeft, pRight: TTSNode): Boolean;
begin
  Result:= (not pLeft.IsNull) and (not pRight.IsNull) and (pLeft.StartByte = pRight.StartByte)
    and (pLeft.EndByte = pRight.EndByte);
end;

function GuardedChild(const pSrc: TBytes; const pParent, pChild: TTSNode): Boolean;
begin
  Result:= False;
  if pParent.NodeType = 'exprBinary' then
  begin
    var Op:= Trim(NodeText(pSrc, pParent.ChildByField('operator')));
    if SameText(Op, 'and') or SameText(Op, 'or') then
      Result:= SameNode(pChild, pParent.ChildByField('rhs'));
  end
  else if pParent.NodeType = 'exprIf' then
    { only the condition always runs; no condition field -> every child is a branch (conservative) }
    Result:= not SameNode(pChild, pParent.ChildByField('condition'));
end;

procedure WalkTo(const pSrc: TBytes; const pNode: TTSNode; const pSite: THbSite; var pPath: TSitePath);
begin
  if pNode.NodeType = NODE_LAMBDA then
  begin
    pPath.InLambda:= True;
    Exit;
  end;
  for var I:= 0 to pNode.ChildCount - 1 do
  begin
    var C:= pNode.Child(I);
    if not HbNodeContains(pSrc, C, pSite) then Continue;
    if GuardedChild(pSrc, pNode, C) then pPath.Guarded:= True;
    WalkTo(pSrc, C, pSite, pPath);
  end;
end;

function HbSiteGuarded(const pSrc: TBytes; const pItem: TTSNode; const pSite: THbSite;
  out pInLambda: Boolean): Boolean;
begin
  var Path:= Default(TSitePath);
  WalkTo(pSrc, pItem, pSite, Path);
  pInLambda:= Path.InLambda;
  Result:= Path.Guarded;
end;

{ TIntraSolver }

function TIntraSolver.PathTo(const pItem: TTSNode; const pSite: THbSite): TSitePath;
begin
  Result:= Default(TSitePath);
  Result.Guarded:= HbSiteGuarded(FSrc, pItem, pSite, Result.InLambda);
end;

procedure TIntraSolver.ComputeReach;
begin
  SetLength(FReach, FCfg.Blocks.Count);
  var Work:= TStack<Integer>.Create;
  try
    FReach[FCfg.EntryIdx]:= True;
    Work.Push(FCfg.EntryIdx);
    while Work.Count > 0 do
      for var S in FCfg.Blocks[Work.Pop].Succ do
        if not FReach[S] then
        begin
          FReach[S]:= True;
          Work.Push(S);
        end;
  finally
    Work.Free;
  end;
end;

procedure TIntraSolver.ApplyMarks(const pMarks: TArray<THbSite>);
begin
  SetLength(FMarked, FCfg.Blocks.Count);
  for var B:= 0 to FCfg.Blocks.Count - 1 do
  begin
    var Blk:= FCfg.Blocks[B];
    SetLength(FMarked[B], Blk.Items.Count);
    for var I:= 0 to Blk.Items.Count - 1 do
    begin
      var It:= Blk.Items[I];
      if It.Opaque then Continue;  { inside `with`: the name may be a field of the with-entity }
      for var M in pMarks do
        if HbNodeContains(FSrc, It.Node, M) then
        begin
          var P:= PathTo(It.Node, M);
          if not (P.InLambda or P.Guarded) then
          begin
            FMarked[B][I]:= True;
            Break;
          end;
        end;
    end;
  end;
end;

procedure TIntraSolver.Solve;
begin
  var N:= FCfg.Blocks.Count;
  SetLength(FIn, N);
  SetLength(FOut, N);
  for var B:= 0 to N - 1 do
  begin
    FIn[B]:= FReach[B];   { greatest fixpoint: start at True on reachable blocks }
    FOut[B]:= FReach[B];
  end;
  var Changed:= True;
  while Changed do
  begin
    Changed:= False;
    for var B:= 0 to N - 1 do
    begin
      if not FReach[B] then Continue;
      var V: Boolean;
      if B = FCfg.EntryIdx then V:= FEntryDone
      else
      begin
        V:= True;
        for var P in FCfg.Blocks[B].Pred do
          if FReach[P] then V:= V and FOut[P];
      end;
      var O:= V;
      for var Mk in FMarked[B] do O:= O or Mk;
      if (V <> FIn[B]) or (O <> FOut[B]) then
      begin
        FIn[B]:= V;
        FOut[B]:= O;
        Changed:= True;
      end;
    end;
  end;
end;

function TIntraSolver.StateBefore(const pRef: TItemRef): Boolean;
begin
  if not FReach[pRef.Block] then Exit(False);
  Result:= FIn[pRef.Block];
  for var I:= 0 to pRef.Item - 1 do Result:= Result or FMarked[pRef.Block][I];
end;

function TIntraSolver.Occurrences(const pSite: THbSite): TArray<TItemRef>;
begin
  var L:= TList<TItemRef>.Create;
  try
    for var B:= 0 to FCfg.Blocks.Count - 1 do
      for var I:= 0 to FCfg.Blocks[B].Items.Count - 1 do
        if HbNodeContains(FSrc, FCfg.Blocks[B].Items[I].Node, pSite) then
        begin
          var R: TItemRef;
          R.Block:= B;
          R.Item:= I;
          L.Add(R);
        end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function TIntraSolver.TryEntryState(const pTryBody: TTSNode): Boolean;
var
  FirstByte: UInt32;
begin
  Result:= True;
  if pTryBody.IsNull then Exit;
  FirstByte:= High(UInt32);
  for var B:= 0 to FCfg.Blocks.Count - 1 do
    for var It in FCfg.Blocks[B].Items do
      if (It.Node.StartByte >= pTryBody.StartByte) and (It.Node.EndByte <= pTryBody.EndByte)
        and (It.Node.StartByte < FirstByte) then FirstByte:= It.Node.StartByte;
  if FirstByte = High(UInt32) then Exit;  { empty try body: the finally sees the pre-try state already }
  for var B:= 0 to FCfg.Blocks.Count - 1 do
    for var I:= 0 to FCfg.Blocks[B].Items.Count - 1 do
      if FCfg.Blocks[B].Items[I].Node.StartByte = FirstByte then
      begin
        var R: TItemRef;
        R.Block:= B;
        R.Item:= I;
        Result:= Result and StateBefore(R);
      end;
end;

procedure TIntraSolver.CollectFinallys(const pNode: TTSNode; pList: TList<TPair<TTSNode, TTSNode>>);
begin
  for var I:= 0 to pNode.NamedChildCount - 1 do
  begin
    var C:= pNode.NamedChild(I);
    if (C.NodeType = NODE_DEFPROC) or (C.NodeType = NODE_LAMBDA) then Continue;  { own routine }
    if C.NodeType = 'try' then
    begin
      var Seen:= False;
      for var J:= 0 to C.NamedChildCount - 1 do
        if C.NamedChild(J).NodeType = 'kFinally' then Seen:= True
        else if Seen and (C.NamedChild(J).NodeType = 'statements') then
        begin
          pList.Add(TPair<TTSNode, TTSNode>.Create(C.ChildByField('try'), C.NamedChild(J)));
          Break;
        end;
    end;
    CollectFinallys(C, pList);
  end;
end;

procedure TIntraSolver.Run(const pMarks: TArray<THbSite>; var pState: THbRoutineState);
begin
  ComputeReach;
  ApplyMarks(pMarks);
  Solve;
  var Body:= FCfg.RoutineNode.ChildByField('body');
  if Body.IsNull then Body:= FCfg.RoutineNode;
  var Finallys:= TList<TPair<TTSNode, TTSNode>>.Create;
  try
    CollectFinallys(Body, Finallys);
    for var Q:= 0 to High(pState.Queries) do
    begin
      var Site:= pState.Queries[Q].Site;
      var Refs:= Occurrences(Site);
      if Length(Refs) = 0 then Continue;  { Located stays False, Done False }
      pState.Queries[Q].Located:= True;
      var Done:= True;
      for var R in Refs do
      begin
        if PathTo(FCfg.Blocks[R.Block].Items[R.Item].Node, Site).InLambda then
          pState.Queries[Q].InClosure:= True;
        Done:= Done and StateBefore(R);
      end;
      for var F in Finallys do
        if HbNodeContains(FSrc, F.Value, Site) then Done:= Done and TryEntryState(F.Key);
      pState.Queries[Q].Done:= Done and not pState.Queries[Q].InClosure;
    end;
  finally
    Finallys.Free;
  end;
  var ExitDone:= True;
  var AnyExit:= False;
  for var P in FCfg.Blocks[FCfg.ExitIdx].Pred do
    if FReach[P] and not FCfg.Blocks[P].NoReturn then
    begin
      AnyExit:= True;
      ExitDone:= ExitDone and FOut[P];
    end;
  pState.ExitReachable:= AnyExit;
  pState.ExitDone:= AnyExit and ExitDone;
end;

{ The `defProc` of the routine: the one starting on its implementation line, else the innermost
  one whose rows cover that line. }
function FindDefProc(const pRoot: TTSNode; const pSym: TSymbol): TTSNode;
var
  Line, BestSpan: Integer;
begin
  Result:= Default(TTSNode);
  Line:= if pSym.ImplStartLine > 0 then pSym.ImplStartLine else pSym.StartLine;
  if Line <= 0 then Exit;
  BestSpan:= MaxInt;
  var Found:= False;
  for var P in CfgFindProcs(pRoot) do
  begin
    var SR:= Integer(P.StartPoint.row) + 1;
    var ER:= Integer(P.EndPoint.row) + 1;
    if SR = Line then Exit(P);
    if InRange(Line, SR, ER) and (ER - SR < BestSpan) then
    begin
      BestSpan:= ER - SR;
      Result:= P;
      Found:= True;
    end;
  end;
  if not Found then Result:= Default(TTSNode);
end;

{ The routine's `defProc` through the shared parse cache (pSrc = the parsed bytes); a null node when the
  symbol, its file or its body is missing. }
function LocateDefProc(const pStore: ISymbolStore; pRoutineId: Int64; out pSrc: TBytes): TTSNode;
begin
  Result:= Default(TTSNode);
  pSrc:= nil;
  if pStore = nil then Exit;
  var Sym:= pStore.GetSymbolById(pRoutineId);
  var Path:= if Sym.Id = 0 then '' else pStore.GetFilePath(Sym.FileId);
  if (Path = '') or not FileExists(Path) then Exit;
  var PF:= TAstParseCache.Get(Path);
  if PF.Tree = nil then Exit;
  pSrc:= PF.Src;
  Result:= FindDefProc(PF.Tree.RootNode, Sym);
end;

function SolveRoutine(const pStore: ISymbolStore; pRoutineId: Int64; const pMarks, pQueries: TArray<THbSite>;
  pEntryDone: Boolean): THbRoutineState;
begin
  Result:= Default(THbRoutineState);
  Result.RoutineId:= pRoutineId;
  SetLength(Result.Queries, Length(pQueries));
  for var I:= 0 to High(pQueries) do Result.Queries[I].Site:= pQueries[I];
  var Src: TBytes;
  var Proc:= LocateDefProc(pStore, pRoutineId, Src);
  if Proc.IsNull then Exit;
  Result.Found:= True;
  var Cfg:= TCfgBuilder.Build(Proc, Src, {APruneConstLoops=}True);
  try
    if Cfg.Skipped then
    begin
      Result.CfgSkipped:= True;
      Exit;
    end;
    var Solver:= TIntraSolver.Create(Cfg, pEntryDone);
    try
      Solver.Run(pMarks, Result);
    finally
      Solver.Free;
    end;
  finally
    Cfg.Free;
  end;
end;

function HbFactMustWrites(const pStore: ISymbolStore; pRoutineId: Int64; const pName: string): Boolean;
begin
  Result:= False;
  if (pRoutineId = 0) or (pName = '') then Exit;
  for var N: string in pStore.GetSymbolFacts(pRoutineId).MustWrites.Split([',']) do
    if SameText(Trim(N), pName) then Exit(True);
end;

end.
