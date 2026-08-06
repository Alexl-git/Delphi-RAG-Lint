unit DRagLint.Analysis.Cfg;

{ Per-routine control-flow graph for drag-lint's flow-sensitive analyses (M2).
  Analysis-agnostic: builds basic blocks + edges from a tree-sitter `defProc`
  node. Compound statements (if/while/for/case/try/repeat/with) are decomposed
  into edges; basic blocks hold only SIMPLE items (assignments, call/expression
  statements, and the condition expressions of branches/loops) so the data-flow
  transfer functions interpret one node at a time. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  TreeSitter;

type
  /// <summary>One element of a basic block: a simple-statement or condition AST
  /// node, plus an opacity flag.</summary>
  /// <remarks>Opaque items live inside a `with` statement; their identifier
  /// reads are not trusted (a `with` aliases fields), so definite-assignment
  /// ignores their uses and liveness treats them as using everything.</remarks>
  TCfgItem = record
    Node  : TTSNode;
    Opaque: Boolean;
  end;

  /// <summary>A `for`-loop control variable plus the index of the block control
  /// reaches after the loop, for the loop-var-after-loop check.</summary>
  TCfgForVar = record
    VarName  : string;
    FollowIdx: Integer;
  end;

  /// <summary>A maximal run of simple items with a single entry and single
  /// exit, plus its CFG successor/predecessor block indices.</summary>
  /// <remarks>Block 0 is the synthetic Entry, block 1 the synthetic Exit; both
  /// have empty `Items`. `EntryDefs` names vars defined unconditionally on
  /// entry to this block (used for the `foreach` iterator).</remarks>
  TCfgBlock = class
  public
    Index    : Integer;
    Items    : TList<TCfgItem>;
    EntryDefs: TArray<string>;
    Succ     : TList<Integer>;
    Pred     : TList<Integer>;
    constructor Create(AIndex: Integer);
    destructor Destroy; override;
    /// <summary>Append an item (an assignment / call / condition node).</summary>
    procedure AddItem(const ANode: TTSNode; AOpaque: Boolean);
    /// <summary>Record an edge from this block to block AToIdx (no duplicates).</summary>
    procedure AddSucc(AToIdx: Integer);
  end;

  /// <summary>The control-flow graph of one routine body.</summary>
  /// <remarks>Caller owns the instance and must Free it. When `Skipped` is True
  /// the routine contains `goto`/labels/`asm` and analyses must bail (return no
  /// findings) -- the graph would otherwise need unsound edges.</remarks>
  TCfg = class
  public
    Blocks     : TObjectList<TCfgBlock>;
    EntryIdx   : Integer;
    ExitIdx    : Integer;
    RoutineNode: TTSNode;
    Src        : TBytes;
    Skipped    : Boolean;
    ForVars    : TList<TCfgForVar>;
    constructor Create;
    destructor Destroy; override;
    /// <summary>Create a fresh empty block, append it, and return it.</summary>
    function NewBlock: TCfgBlock;
    function BlockCount: Integer;
    /// <summary>Fill every block's `Pred` list from the `Succ` lists. Call once
    /// after construction; required by backward analyses (liveness).</summary>
    procedure ComputePreds;
  end;

  /// <summary>Builds a <see cref="TCfg"/> from a `defProc` node.</summary>
  TCfgBuilder = class
  public
    /// <summary>Build the CFG of the routine AProc (a `defProc`). Returns a CFG
    /// whose Skipped is True for goto/asm routines.</summary>
    /// <param name="AProc">The `defProc` AST node.</param>
    /// <param name="ASrc">The unit's source bytes (for identifier text).</param>
    class function Build(const AProc: TTSNode; const ASrc: TBytes): TCfg;
  end;

/// <summary>Collect every `defProc` node anywhere under ARoot.</summary>
function CfgFindProcs(const ARoot: TTSNode): TArray<TTSNode>;

implementation

function NodeStr(const N: TTSNode; const ASrc: TBytes): string;
var S, E, L: Integer;
begin
  Result := '';
  if N.IsNull then Exit;
  S := Integer(N.StartByte); E := Integer(N.EndByte); L := E - S;
  if (L <= 0) or (S < 0) or (E > Length(ASrc)) then Exit;
  Result := TEncoding.UTF8.GetString(ASrc, S, L);
end;

function LowerText(const N: TTSNode; const ASrc: TBytes): string;
begin
  Result := LowerCase(Trim(NodeStr(N, ASrc)));
end;

{ True when a `for` loop provably runs its body AT LEAST ONCE -- both bounds are
  integer literals and the direction agrees with them.

  Why it matters: the CFG gives every for-loop a header->follow edge, so control
  may skip the body entirely, and nothing the body MUST-assigns survives to the
  code after the loop. For the overwhelmingly common
  `for I := 0 to 2 do Arr[I] := ...` that is simply false -- the loop always runs
  -- and every use of Arr afterwards was reported as possibly-used-before-
  assigned (29 such findings on one real project).

  Deliberately literal-only and direction-explicit: if the bounds are not
  literals (`0 to List.Count - 1`) the loop genuinely CAN run zero times and the
  warning is legitimate, and if the direction cannot be read from the source the
  optimisation is skipped rather than guessed. Both fallbacks keep today's
  behaviour, so this can only remove false positives, never create them.

  The direction is read from the loop HEADER text only -- ANode.StartByte up to
  the body -- so a nested `downto` inside the body cannot be mistaken for this
  loop's own. }
function ForLoopAlwaysExecutes(const ANode, AStartN, ABodyN: TTSNode; const ASrc: TBytes): Boolean;
var
  LowTxt, HighTxt: string;
  LowVal, HighVal, I: Integer;
  BoundN: TTSNode;
  IsDownto: Boolean;
begin
  Result := False;
  if AStartN.IsNull or ABodyN.IsNull then Exit;

  { low bound = the start assignment's rhs }
  LowTxt := LowerText(AStartN.ChildByField('rhs'), ASrc);
  if not TryStrToInt(LowTxt, LowVal) then Exit;

  { High bound = the named child that is neither start nor body AND is not a
    KEYWORD TOKEN. The grammar exposes `for` / `to` / `downto` / `do` as named
    children (kFor, kTo, kDownto, kDo -- the same 'k' prefix convention the try
    lowering already relies on for kFinally/kEnd), so "the first child that is
    not start or body" lands on the `for` keyword, not the bound. Direction
    comes from the same place: a kDownto child, which is exact where scanning
    the header text for the word would not be. }
  BoundN := Default(TTSNode);
  IsDownto := False;
  for I := 0 to ANode.NamedChildCount - 1 do
  begin
    if ANode.NamedChild(I) = AStartN then Continue;
    if ANode.NamedChild(I) = ABodyN then Continue;
    if SameText(ANode.NamedChild(I).NodeType, 'kDownto') then IsDownto := True;
    if SameText(Copy(ANode.NamedChild(I).NodeType, 1, 1), 'k') then Continue; { keyword token }
    if BoundN.IsNull then BoundN := ANode.NamedChild(I);
  end;
  if BoundN.IsNull then Exit;
  HighTxt := LowerText(BoundN, ASrc);
  if not TryStrToInt(HighTxt, HighVal) then Exit;

  if IsDownto then Result := LowVal >= HighVal
  else Result := LowVal <= HighVal;
end;

{ TCfgBlock }

constructor TCfgBlock.Create(AIndex: Integer);
begin
  inherited Create;
  Index := AIndex;
  Items := TList<TCfgItem>.Create;
  Succ  := TList<Integer>.Create;
  Pred  := TList<Integer>.Create;
end;

destructor TCfgBlock.Destroy;
begin
  Items.Free; Succ.Free; Pred.Free;
  inherited;
end;

procedure TCfgBlock.AddItem(const ANode: TTSNode; AOpaque: Boolean);
var It: TCfgItem;
begin
  It.Node := ANode; It.Opaque := AOpaque;
  Items.Add(It);
end;

procedure TCfgBlock.AddSucc(AToIdx: Integer);
begin
  if Succ.IndexOf(AToIdx) < 0 then Succ.Add(AToIdx);
end;

{ TCfg }

constructor TCfg.Create;
begin
  inherited Create;
  Blocks  := TObjectList<TCfgBlock>.Create(True);
  ForVars := TList<TCfgForVar>.Create;
end;

destructor TCfg.Destroy;
begin
  ForVars.Free;
  Blocks.Free;
  inherited;
end;

function TCfg.NewBlock: TCfgBlock;
begin
  Result := TCfgBlock.Create(Blocks.Count);
  Blocks.Add(Result);
end;

function TCfg.BlockCount: Integer;
begin
  Result := Blocks.Count;
end;

procedure TCfg.ComputePreds;
var B, S: Integer;
begin
  for B := 0 to Blocks.Count - 1 do Blocks[B].Pred.Clear;
  for B := 0 to Blocks.Count - 1 do
    for S := 0 to Blocks[B].Succ.Count - 1 do
      Blocks[Blocks[B].Succ[S]].Pred.Add(B);
end;

{ CfgFindProcs }

function CfgFindProcs(const ARoot: TTSNode): TArray<TTSNode>;
var
  Acc: TList<TTSNode>;
  procedure Walk(const N: TTSNode);
  var I: Integer;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then Acc.Add(N);
    for I := 0 to N.NamedChildCount - 1 do Walk(N.NamedChild(I));
  end;
begin
  Acc := TList<TTSNode>.Create;
  try
    Walk(ARoot);
    Result := Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

{ True if the routine contains a goto/label/asm node -- analyses must skip it. }
function RoutineHasGotoOrAsm(const N: TTSNode): Boolean;
var I: Integer; K: string;
begin
  Result := False;
  if N.IsNull then Exit;
  K := N.NodeType;
  if (K = 'goto') or (K = 'label') or (K = 'declLabels') or (Pos('asm', K) = 1) then
    Exit(True);
  for I := 0 to N.NamedChildCount - 1 do
    if RoutineHasGotoOrAsm(N.NamedChild(I)) then Exit(True);
end;

{ TBuilderState -- threads a "current" block through the routine body, emitting
  edges for control-flow constructs. EmitStmt returns the block where control
  continues, or -1 when control diverged (Exit/Break/Continue/raise). }
type
  TLoopCtx = record ContinueIdx, BreakIdx: Integer; end;

  TBuilderState = class
  public
    Cfg      : TCfg;
    Loops    : TStack<TLoopCtx>;
    WithDepth: Integer;
    constructor Create(ACfg: TCfg);
    destructor Destroy; override;
    function EmitStmt(ACur: Integer; const ANode: TTSNode): Integer;
    function EmitList(ACur: Integer; const AContainer: TTSNode): Integer;
  end;

constructor TBuilderState.Create(ACfg: TCfg);
begin
  inherited Create; Cfg := ACfg; Loops := TStack<TLoopCtx>.Create; WithDepth := 0;
end;

destructor TBuilderState.Destroy;
begin
  Loops.Free; inherited;
end;

function TBuilderState.EmitList(ACur: Integer; const AContainer: TTSNode): Integer;
var I, Cur: Integer;
begin
  Cur := ACur;
  if AContainer.IsNull then Exit(Cur);
  for I := 0 to AContainer.NamedChildCount - 1 do
  begin
    if Cur < 0 then Break; { unreachable tail }
    Cur := EmitStmt(Cur, AContainer.NamedChild(I));
  end;
  Result := Cur;
end;

function TBuilderState.EmitStmt(ACur: Integer; const ANode: TTSNode): Integer;
var
  K, EntTxt: string;
  Cond, ThenN, ElseN, BodyN, StartN, EntityN, IterN, LhsN: TTSNode;
  ThenAfter, ElseAfter, JoinIdx, HdrIdx, BodyIdx, FollowIdx, TestIdx, BodyAfter: Integer;
  TryN, FinN, TryAfter, FinAfter, ExcAfter: Integer;
  TryNode, FinNode: TTSNode;
  Ctx: TLoopCtx;
  Rec: TCfgForVar;
  I: Integer;
begin
  Result := ACur;
  if ANode.IsNull then Exit;
  K := ANode.NodeType;

  { ----- containers ----- }
  if (K = 'block') or (K = 'statements') then Exit(EmitList(ACur, ANode));

  { ----- conditionals ----- }
  if (K = 'if') or (K = 'ifElse') then
  begin
    Cond := ANode.ChildByField('condition');
    if not Cond.IsNull then Cfg.Blocks[ACur].AddItem(Cond, WithDepth > 0);
    ThenN := ANode.ChildByField('then');
    JoinIdx := Cfg.NewBlock.Index;
    BodyIdx := Cfg.NewBlock.Index;
    Cfg.Blocks[ACur].AddSucc(BodyIdx);
    ThenAfter := EmitStmt(BodyIdx, ThenN);
    if ThenAfter >= 0 then Cfg.Blocks[ThenAfter].AddSucc(JoinIdx);
    if K = 'ifElse' then
    begin
      ElseN := ANode.ChildByField('else');
      BodyIdx := Cfg.NewBlock.Index;
      Cfg.Blocks[ACur].AddSucc(BodyIdx);
      ElseAfter := EmitStmt(BodyIdx, ElseN);
      if ElseAfter >= 0 then Cfg.Blocks[ElseAfter].AddSucc(JoinIdx);
    end
    else
      Cfg.Blocks[ACur].AddSucc(JoinIdx); { no else -> false path skips to join }
    Exit(JoinIdx);
  end;

  if K = 'case' then
  begin
    for I := 0 to ANode.NamedChildCount - 1 do
      if ANode.NamedChild(I).NodeType <> 'caseCase' then
      begin
        Cfg.Blocks[ACur].AddItem(ANode.NamedChild(I), WithDepth > 0);
        Break;
      end;
    JoinIdx := Cfg.NewBlock.Index;
    for I := 0 to ANode.NamedChildCount - 1 do
      if ANode.NamedChild(I).NodeType = 'caseCase' then
      begin
        BodyIdx := Cfg.NewBlock.Index;
        Cfg.Blocks[ACur].AddSucc(BodyIdx);
        ThenAfter := EmitStmt(BodyIdx, ANode.NamedChild(I).ChildByField('body'));
        if ThenAfter >= 0 then Cfg.Blocks[ThenAfter].AddSucc(JoinIdx);
      end;
    Cfg.Blocks[ACur].AddSucc(JoinIdx); { else / no-match fall-through }
    Exit(JoinIdx);
  end;

  { ----- loops ----- }
  if K = 'while' then
  begin
    HdrIdx := Cfg.NewBlock.Index;
    Cfg.Blocks[ACur].AddSucc(HdrIdx);
    Cond := ANode.ChildByField('condition');
    if not Cond.IsNull then Cfg.Blocks[HdrIdx].AddItem(Cond, WithDepth > 0);
    FollowIdx := Cfg.NewBlock.Index;
    BodyIdx := Cfg.NewBlock.Index;
    Cfg.Blocks[HdrIdx].AddSucc(BodyIdx);
    Cfg.Blocks[HdrIdx].AddSucc(FollowIdx);
    Ctx.ContinueIdx := HdrIdx; Ctx.BreakIdx := FollowIdx; Loops.Push(Ctx);
    TestIdx := EmitStmt(BodyIdx, ANode.ChildByField('body'));
    if TestIdx >= 0 then Cfg.Blocks[TestIdx].AddSucc(HdrIdx); { back-edge }
    Loops.Pop;
    Exit(FollowIdx);
  end;

  if K = 'for' then
  begin
    StartN := ANode.ChildByField('start'); { assignment: defines the loop var }
    if not StartN.IsNull then Cfg.Blocks[ACur].AddItem(StartN, WithDepth > 0);
    { The BOUND expression is a read, and it was being dropped on the floor: only
      'start' and 'body' were ever emitted, so `for J := 1 to LCount` never
      recorded a read of LCount and write-only-local reported a variable the loop
      plainly consumes. Every named child that is neither start nor body is the
      bound (Delphi evaluates it ONCE, before the loop -- hence ACur, not the
      header). Same rule ExtractMethod already applies. }
    for I := 0 to ANode.NamedChildCount - 1 do
      if (not (ANode.NamedChild(I) = StartN)) and (not (ANode.NamedChild(I) = ANode.ChildByField('body'))) then
        Cfg.Blocks[ACur].AddItem(ANode.NamedChild(I), WithDepth > 0);
    HdrIdx := Cfg.NewBlock.Index;
    { The loop READS its control variable on every test/increment. Without this
      the variable is 'assigned' by start and read nowhere, so a counter whose
      body never mentions it -- `for J := 1 to N do <work not using J>` -- was
      reported as write-only. Emitting the start assignment's lhs identifier into
      the header block models that read exactly where it happens. }
    if not StartN.IsNull then
    begin
      LhsN := StartN.ChildByField('lhs');
      if not LhsN.IsNull then Cfg.Blocks[HdrIdx].AddItem(LhsN, WithDepth > 0);
    end;
    FollowIdx := Cfg.NewBlock.Index;
    BodyIdx := Cfg.NewBlock.Index;
    Cfg.Blocks[HdrIdx].AddSucc(BodyIdx);
    Cfg.Blocks[HdrIdx].AddSucc(FollowIdx);
    { ENTRY EDGE. A loop with literal bounds that provably runs at least once
      gets a DO-WHILE shape: fall straight into the body, and let the header
      decide only whether to go round AGAIN. The body then dominates the follow
      block, so whatever it must-assigns is still must-assigned afterwards.
      Without this, `for I := 0 to 2 do Arr[I] := ...` left Arr
      possibly-unassigned at every later use -- 29 such findings on one real
      project, none of them reachable. A loop we cannot prove keeps the ordinary
      zero-trip entry, where the warning is legitimate. }
    if ForLoopAlwaysExecutes(ANode, StartN, ANode.ChildByField('body'), Cfg.Src) then
      Cfg.Blocks[ACur].AddSucc(BodyIdx)
    else
      Cfg.Blocks[ACur].AddSucc(HdrIdx);
    Ctx.ContinueIdx := HdrIdx; Ctx.BreakIdx := FollowIdx; Loops.Push(Ctx);
    TestIdx := EmitStmt(BodyIdx, ANode.ChildByField('body'));
    if TestIdx >= 0 then Cfg.Blocks[TestIdx].AddSucc(HdrIdx);
    Loops.Pop;
    { record the control var (start assignment lhs) for loop-var-after-loop }
    if not StartN.IsNull then
    begin
      Rec.VarName := LowerText(StartN.ChildByField('lhs'), Cfg.Src);
      Rec.FollowIdx := FollowIdx;
      if Rec.VarName <> '' then Cfg.ForVars.Add(Rec);
    end;
    Exit(FollowIdx);
  end;

  if K = 'foreach' then
  begin
    EntityN := ANode.ChildByField('iterable');
    if not EntityN.IsNull then Cfg.Blocks[ACur].AddItem(EntityN, WithDepth > 0);
    HdrIdx := Cfg.NewBlock.Index;
    Cfg.Blocks[ACur].AddSucc(HdrIdx);
    FollowIdx := Cfg.NewBlock.Index;
    BodyIdx := Cfg.NewBlock.Index;
    IterN := ANode.ChildByField('iterator');
    { `for var X in` -> the iterator is a varAssignDef; use its identifier child }
    if (not IterN.IsNull) and (IterN.NodeType = 'varAssignDef') then
      for I := 0 to IterN.NamedChildCount - 1 do
        if IterN.NamedChild(I).NodeType = 'identifier' then
        begin IterN := IterN.NamedChild(I); Break; end;
    if not IterN.IsNull then Cfg.Blocks[BodyIdx].EntryDefs := [LowerText(IterN, Cfg.Src)];
    Cfg.Blocks[HdrIdx].AddSucc(BodyIdx);
    Cfg.Blocks[HdrIdx].AddSucc(FollowIdx);
    Ctx.ContinueIdx := HdrIdx; Ctx.BreakIdx := FollowIdx; Loops.Push(Ctx);
    TestIdx := EmitStmt(BodyIdx, ANode.ChildByField('body'));
    if TestIdx >= 0 then Cfg.Blocks[TestIdx].AddSucc(HdrIdx);
    Loops.Pop;
    Exit(FollowIdx);
  end;

  if K = 'repeat' then
  begin
    BodyIdx := Cfg.NewBlock.Index;
    Cfg.Blocks[ACur].AddSucc(BodyIdx);
    FollowIdx := Cfg.NewBlock.Index;
    TestIdx := Cfg.NewBlock.Index; { holds the until-condition }
    Cond := ANode.ChildByField('condition');
    if not Cond.IsNull then Cfg.Blocks[TestIdx].AddItem(Cond, WithDepth > 0);
    Cfg.Blocks[TestIdx].AddSucc(BodyIdx);   { loop continues }
    Cfg.Blocks[TestIdx].AddSucc(FollowIdx); { loop exits }
    Ctx.ContinueIdx := TestIdx; Ctx.BreakIdx := FollowIdx; Loops.Push(Ctx);
    BodyAfter := EmitStmt(BodyIdx, ANode.ChildByField('body'));
    if BodyAfter >= 0 then Cfg.Blocks[BodyAfter].AddSucc(TestIdx);
    Loops.Pop;
    Exit(FollowIdx);
  end;

  { ----- try ----- }
  if K = 'try' then
  begin
    TryNode := ANode.ChildByField('try');
    { the grammar labels BOTH the `kFinally` token and the finally statements with
      the field name 'finally', so ChildByField returns the token -- scan for the
      first non-kEnd child after kFinally to get the actual finally body. }
    FinNode := Default(TTSNode);
    var SeenFinally := False;
    for I := 0 to ANode.NamedChildCount - 1 do
      if ANode.NamedChild(I).NodeType = 'kFinally' then SeenFinally := True
      else if SeenFinally and (ANode.NamedChild(I).NodeType <> 'kEnd') then
      begin FinNode := ANode.NamedChild(I); Break; end;
    BodyIdx := Cfg.NewBlock.Index; { try region entry }
    Cfg.Blocks[ACur].AddSucc(BodyIdx);
    FollowIdx := Cfg.NewBlock.Index;
    TryAfter := EmitStmt(BodyIdx, TryNode);
    if not FinNode.IsNull then
    begin
      HdrIdx := Cfg.NewBlock.Index; { finally entry }
      { Normal completion flows try-body -> finally -> follow. We deliberately do
        NOT add an exceptional tryEntry->finally edge: it would route the
        "try-body assignments skipped" state into the normal post-finally exit and
        falsely flag function-result-not-set on routines that set Result in the
        try. FP policy: prefer missing a used-before INSIDE a finally over that FP. }
      if TryAfter >= 0 then Cfg.Blocks[TryAfter].AddSucc(HdrIdx)  { normal completion }
      else Cfg.Blocks[BodyIdx].AddSucc(HdrIdx);                   { try always diverts: keep finally reachable }
      FinAfter := EmitStmt(HdrIdx, FinNode);
      if FinAfter >= 0 then Cfg.Blocks[FinAfter].AddSucc(FollowIdx)
      else Cfg.Blocks[HdrIdx].AddSucc(FollowIdx);
      Exit(FollowIdx);
    end
    else
    begin
      if TryAfter >= 0 then Cfg.Blocks[TryAfter].AddSucc(FollowIdx); { normal completion }
      for I := 0 to ANode.NamedChildCount - 1 do
        if (ANode.NamedChild(I).NodeType = 'exceptionHandler')
           or ((ANode.NamedChild(I).NodeType = 'statements') and (I > 0)) then
        begin
          HdrIdx := Cfg.NewBlock.Index;
          Cfg.Blocks[BodyIdx].AddSucc(HdrIdx); { try entry -> handler (conservative) }
          if ANode.NamedChild(I).NodeType = 'exceptionHandler' then
            ExcAfter := EmitStmt(HdrIdx, ANode.NamedChild(I).ChildByField('body'))
          else
            ExcAfter := EmitStmt(HdrIdx, ANode.NamedChild(I));
          { A handler that DIVERTS (exit / raise / break / continue -> EmitStmt
            returns -1) has no fallthrough, and wiring its ENTRY to the follow
            block anyway re-created the very path that cannot happen: the
            "exception fired, so the try body's assignments never ran" state
            flowed past the handler into the code after the try, and every local
            assigned in the try body was reported as possibly-used-before-
            assignment. Measured on DataCopy uFileUtils.pas: SrcSize is assigned
            in the try and the handler ends with `exit`, yet its later use was
            flagged.

            Note this is NOT the same as the finally case above, where the
            equivalent edge is deliberate -- a finally block always runs. }
          if ExcAfter >= 0 then Cfg.Blocks[ExcAfter].AddSucc(FollowIdx);
        end;
      Exit(FollowIdx);
    end;
  end;

  { ----- with ----- }
  if K = 'with' then
  begin
    EntityN := ANode.ChildByField('entity');
    if not EntityN.IsNull then Cfg.Blocks[ACur].AddItem(EntityN, WithDepth > 0);
    Inc(WithDepth);
    try
      Result := EmitStmt(ACur, ANode.ChildByField('body'));
    finally
      Dec(WithDepth);
    end;
    Exit;
  end;

  { ----- simple statements ----- }
  if K = 'assignment' then
  begin
    Cfg.Blocks[ACur].AddItem(ANode, WithDepth > 0);
    Exit(ACur);
  end;

  if K = 'raise' then
  begin
    Cfg.Blocks[ACur].AddItem(ANode, WithDepth > 0);
    Cfg.Blocks[ACur].AddSucc(Cfg.ExitIdx);
    Exit(-1);
  end;

  if (K = 'statement') or (K = 'exprCall') or (K = 'exprDot') or (K = 'identifier') then
  begin
    if K = 'exprCall' then EntTxt := LowerText(ANode.ChildByField('entity'), Cfg.Src)
    else EntTxt := LowerText(ANode, Cfg.Src);
    Cfg.Blocks[ACur].AddItem(ANode, WithDepth > 0);
    if EntTxt = 'exit' then
    begin Cfg.Blocks[ACur].AddSucc(Cfg.ExitIdx); Exit(-1); end;
    if (EntTxt = 'break') and (Loops.Count > 0) then
    begin Cfg.Blocks[ACur].AddSucc(Loops.Peek.BreakIdx); Exit(-1); end;
    if (EntTxt = 'continue') and (Loops.Count > 0) then
    begin Cfg.Blocks[ACur].AddSucc(Loops.Peek.ContinueIdx); Exit(-1); end;
    Exit(ACur);
  end;

  { default: opaque statement, no control change }
  Cfg.Blocks[ACur].AddItem(ANode, WithDepth > 0);
  Result := ACur;
end;

{ TCfgBuilder }

class function TCfgBuilder.Build(const AProc: TTSNode; const ASrc: TBytes): TCfg;
var
  St: TBuilderState;
  Body: TTSNode;
  First, Last: Integer;
begin
  Result := TCfg.Create;
  Result.RoutineNode := AProc;
  Result.Src := ASrc;
  if AProc.IsNull or (AProc.NodeType <> 'defProc') then Exit;
  Body := AProc.ChildByField('body');
  if Body.IsNull then Exit;
  if RoutineHasGotoOrAsm(AProc) then begin Result.Skipped := True; Exit; end;

  Result.EntryIdx := Result.NewBlock.Index; { 0 = Entry }
  Result.ExitIdx  := Result.NewBlock.Index; { 1 = Exit }
  St := TBuilderState.Create(Result);
  try
    First := Result.NewBlock.Index;
    Result.Blocks[Result.EntryIdx].AddSucc(First);
    Last := St.EmitStmt(First, Body);
    if Last >= 0 then Result.Blocks[Last].AddSucc(Result.ExitIdx);
  finally
    St.Free;
  end;
  Result.ComputePreds;
end;

end.
