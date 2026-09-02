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
  /// <remarks>
  /// Opaque items live inside a `with` statement; their identifier
  /// reads are not trusted (a `with` aliases fields), so definite-assignment
  /// ignores their uses and liveness treats them as using everything.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.TCfgBlock.Create (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.TCfgBlock.AddItem (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Flow.Lattices.TDefiniteAssignment.Transfer (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Analysis.Flow.Lattices.TFreedState.Transfer (DRagLint.Analysis.Flow.Lattices.pas) (+3 more)</para>
  /// <para>Used in units: DRagLint.Analysis.Cfg, DRagLint.Analysis.Flow.Lattices, DRagLint.Diagnostics.FlowChecks</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCfgItem = record
    Node  : TTSNode;
    Opaque: Boolean;
  end;

  /// <summary>A `for`-loop control variable plus the index of the block control
  /// reaches after the loop, for the loop-var-after-loop check.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.TCfg.Create (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.TBuilderState.EmitStmt (DRagLint.Analysis.Cfg.pas)</para>
  /// <para>Used in units: DRagLint.Analysis.Cfg</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCfgForVar = record
    VarName  : string;
    FollowIdx: Integer;
  end;

  /// <summary>A maximal run of simple items with a single entry and single
  /// exit, plus its CFG successor/predecessor block indices.</summary>
  /// <remarks>
  /// Block 0 is the synthetic Entry, block 1 the synthetic Exit; both
  /// have empty `Items`. `EntryDefs` names vars defined unconditionally on
  /// entry to this block (used for the `foreach` iterator).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.TCfg.Create (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.TCfg.NewBlock (DRagLint.Analysis.Cfg.pas), declaration (DRagLint.Analysis.DataFlow.pas), declaration (DRagLint.Analysis.Flow.Lattices.pas) (+6 more)</para>
  /// <para>Used in units: DRagLint.Analysis.Cfg, DRagLint.Analysis.DataFlow, DRagLint.Analysis.Flow.Lattices, DRagLint.Analysis.Liveness, DRagLint.Refactor.ExtractMethod</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCfgBlock = class
  public
    Index    : Integer;
    Items    : TList<TCfgItem>;
    EntryDefs: TArray<string>;
    Succ     : TList<Integer>;
    Pred     : TList<Integer>;
    /// <summary><!-- drag-lint:auto -->TCfgBlock</summary>
    /// <param name="AIndex"><!-- drag-lint:auto type -->Integer</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Analysis.Cfg.TCfg.NewBlock (DRagLint.Analysis.Cfg.pas)</para>
    /// <para>constructor</para>
    /// <para>Writes: Index, Items, Succ, Pred</para>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfgBlock.AddItem"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfgBlock.AddSucc"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfgBlock.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(AIndex: Integer);
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: Items, Succ, Pred</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfgBlock.AddItem"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfgBlock.AddSucc"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfgBlock.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>Append an item (an assignment / call / condition node).</summary>
    /// <param name="ANode"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <param name="AOpaque"><!-- drag-lint:auto type -->Boolean</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: Items</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfgBlock.AddSucc"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfgBlock.Create"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfgBlock.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure AddItem(const ANode: TTSNode; AOpaque: Boolean);
    /// <summary>Record an edge from this block to block AToIdx (no duplicates).</summary>
    /// <param name="AToIdx"><!-- drag-lint:auto type -->Integer</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: Succ</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfgBlock.AddItem"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfgBlock.Create"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfgBlock.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure AddSucc(AToIdx: Integer);
  end;

  /// <summary>The control-flow graph of one routine body.</summary>
  /// <remarks>
  /// Caller owns the instance and must Free it. When `Skipped` is True
  /// the routine contains `goto`/labels/`asm` and analyses must bail (return no
  /// findings) -- the graph would otherwise need unsound edges.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.TBuilderState.Create (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.TCfgBuilder.Build (DRagLint.Analysis.Cfg.pas), declaration (DRagLint.Analysis.DataFlow.pas), DRagLint.Analysis.DataFlow.TDataFlowSolver&lt;TValue&gt;.Solve (DRagLint.Analysis.DataFlow.pas) (+5 more)</para>
  /// <para>Used in units: DRagLint.Analysis.Cfg, DRagLint.Analysis.DataFlow, DRagLint.Analysis.Liveness, DRagLint.Refactor.ExtractMethod</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCfg = class
  public
    Blocks     : TObjectList<TCfgBlock>;
    EntryIdx   : Integer;
    ExitIdx    : Integer;
    RoutineNode: TTSNode;
    Src        : TBytes;
    Skipped    : Boolean;
    ForVars    : TList<TCfgForVar>;
    /// <summary><!-- drag-lint:auto -->TCfg</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Analysis.Cfg.TCfgBuilder.Build (DRagLint.Analysis.Cfg.pas)</para>
    /// <para>constructor</para>
    /// <para>Writes: Blocks, ForVars</para>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.BlockCount"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.ComputePreds"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.Destroy"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.NewBlock"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create;
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: ForVars, Blocks</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.BlockCount"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.ComputePreds"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.Create"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.NewBlock"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>Create a fresh empty block, append it, and return it.</summary>
    /// <returns><!-- drag-lint:auto -->TCfgBlock -- Observed:
    /// TCfgBlock.Create(Blocks.Count).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Analysis.Cfg.TBuilderState.DivertVia (DRagLint.Analysis.Cfg.pas), DRagLint.Analysis.Cfg.TBuilderState.EmitStmt (DRagLint.Analysis.Cfg.pas)</para>
    /// <para>Calls: DRagLint.Analysis.Cfg.TCfgBlock.Create</para>
    /// <para>Reads: Blocks</para>
    /// <para>Owns returned: new (caller owns)</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfgBlock.Create"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.BlockCount"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.ComputePreds"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.Create"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function NewBlock: TCfgBlock;
    /// <returns><!-- drag-lint:auto -->Integer -- Observed: Blocks.Count.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Analysis.DataFlow.TDataFlowSolver&lt;TValue&gt;.Solve (DRagLint.Analysis.DataFlow.pas), DRagLint.Analysis.Liveness.LiveAtBoundary (DRagLint.Analysis.Liveness.pas), DRagLint.Refactor.ExtractMethod.LiveOutOfRun (DRagLint.Refactor.ExtractMethod.pas)</para>
    /// <para>Reads: Blocks</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.ComputePreds"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.Create"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.Destroy"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.NewBlock"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function BlockCount: Integer;
    /// <summary>Fill every block's `Pred` list from the `Succ` lists. Call once
    /// after construction; required by backward analyses (liveness).</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Refactor.ExtractMethod.ResolveExtractSelection (DRagLint.Refactor.ExtractMethod.pas), DRagLint.Refactor.ExtractMethod.TExtractMethodRefactoring.Build (DRagLint.Refactor.ExtractMethod.pas)</para>
    /// <para>Reads: Blocks</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.BlockCount"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.Create"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.Destroy"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.NewBlock"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure ComputePreds;
  end;

  /// <summary>Builds a <see cref="TCfg"/> from a `defProc` node.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Diagnostics.FlowChecks.TFlowChecker.Check.CheckRoutine (DRagLint.Diagnostics.FlowChecks.pas), DRagLint.Refactor.ExtractMethod.ResolveExtractSelection (DRagLint.Refactor.ExtractMethod.pas), DRagLint.Refactor.ExtractMethod.TExtractMethodRefactoring.Build (DRagLint.Refactor.ExtractMethod.pas)</para>
  /// <para>Used in units: DRagLint.Diagnostics.FlowChecks, DRagLint.Refactor.ExtractMethod</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCfgBuilder = class
  public
    /// <summary>Build the CFG of the routine AProc (a `defProc`). Returns a CFG
    /// whose Skipped is True for goto/asm routines.</summary>
    /// <param name="AProc">The `defProc` AST node.</param>
    /// <param name="ASrc">The unit's source bytes (for identifier text).</param>
    /// <returns><!-- drag-lint:auto -->TCfg -- Observed: TCfg.Create.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Diagnostics.FlowChecks.TFlowChecker.Check.CheckRoutine (DRagLint.Diagnostics.FlowChecks.pas), DRagLint.Refactor.ExtractMethod.ResolveExtractSelection (DRagLint.Refactor.ExtractMethod.pas), DRagLint.Refactor.ExtractMethod.TExtractMethodRefactoring.Build (DRagLint.Refactor.ExtractMethod.pas)</para>
    /// <para>Calls: DRagLint.Analysis.Cfg.RoutineHasGotoOrAsm, DRagLint.Analysis.Cfg.TBuilderState.Create, DRagLint.Analysis.Cfg.TBuilderState.EmitStmt, DRagLint.Analysis.Cfg.TCfg.Create</para>
    /// <para>Owns returned: new (caller owns)</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Analysis.Cfg.RoutineHasGotoOrAsm"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TBuilderState.Create"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TBuilderState.EmitStmt"/>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Build(const AProc: TTSNode; const ASrc: TBytes): TCfg;
  end;

/// <summary>Collect every `defProc` node anywhere under ARoot.</summary>
/// <param name="ARoot"><!-- drag-lint:auto type -->const TTSNode</param>
/// <returns><!-- drag-lint:auto -->TArray&lt;TTSNode&gt; -- Observed: Acc.ToArray.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Diagnostics.FlowChecks.FindCalleeDefProc (DRagLint.Diagnostics.FlowChecks.pas), DRagLint.Diagnostics.FlowChecks.TFlowChecker.Check (DRagLint.Diagnostics.FlowChecks.pas), DRagLint.Doc.SymbolFacts.ProcsForFile (DRagLint.Doc.SymbolFacts.pas)</para>
/// <para>Calls: DRagLint.Analysis.Cfg.CfgFindProcs.Walk</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Analysis.Cfg.CfgFindProcs.Walk"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CfgFindProcs(const ARoot: TTSNode): TArray<TTSNode>;

/// <summary>True when ANode is a VALUED exit -- `exit(v)` -- which assigns
/// Result. A bare `exit;` is False: it leaves Result as it stands.</summary>
/// <param name="ANode">Either the `exprCall` itself or the `statement` node
/// wrapping it. Both shapes are accepted deliberately -- see the remarks.</param>
/// <param name="ASrc">The unit's source bytes.</param>
/// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; (not A.IsNull) and
/// (A.NamedChildCount &gt; 0).</returns>
/// <remarks>
/// THE SINGLE SOURCE for this question, because asking it in one place
/// and answering it in another is exactly how it broke. TDefiniteAssignment
/// carried its own copy that tested `NodeType = 'exprCall'`, but a CFG block
/// stores the STATEMENT node, so the copy never fired once and every `exit(v)`
/// looked like it left Result unset. It was invisible only because `exit` did
/// not divert either, so no path ever reached the routine exit through one.
/// Fixing the divert made it visible immediately, on three real routines.
/// <para>The name test is case-INSENSITIVE: Delphi identifiers are, and `Exit`
/// is written both ways in the same file.</para>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Analysis.Flow.Lattices.TDefiniteAssignment.Transfer (DRagLint.Analysis.Flow.Lattices.pas)</para>
/// <para>Calls: DRagLint.Analysis.Cfg.LowerText</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Analysis.Cfg.LowerText"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsValuedExit(const ANode: TTSNode; const ASrc: TBytes): Boolean;

/// <summary>The leading identifier of a <c>statement</c> node, lowercased, or
/// '' when the statement does not begin with one.</summary>
/// <param name="ANode">The statement node to inspect.</param>
/// <param name="ASrc">Source bytes backing the node.</param>
/// <returns>'exit', 'break', 'continue', 'halt', any other leading identifier,
/// or '' when the statement does not start with a plain identifier.</returns>
/// <remarks>
/// <para>EXPORTED so that the ONE definition serves every caller. Its
/// implementation comment records why the obvious version is wrong (a statement
/// node includes its terminating semicolon, so comparing whole text against
/// 'exit' is always false, and 'exit(0)' never resembles 'exit' at all); a
/// second hand-rolled copy elsewhere would re-derive exactly that bug, which is
/// what IsValuedExit above already had to be fixed for.</para>
/// <para>Callers outside the CFG use it to ask whether a block of statements
/// FALLS THROUGH -- see OverwrittenInsideFollowingTry in
/// DRagLint.Diagnostics.FlowChecks, where an except handler ending in
/// <c>Continue</c> means the code after the try is unreachable on the exception
/// path.</para>
/// </remarks>
function StatementKeyword(const ANode: TTSNode; const ASrc: TBytes): string;

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

{ The leading identifier of a `statement` node, lowercased -- '' when it does not
  begin with one.

  B9. EmitStmt used to ask "is this a divert?" by comparing the statement's WHOLE
  TEXT against 'exit'. A statement node INCLUDES its terminating semicolon, so
  that comparison read 'exit;' = 'exit' and was always false: no bare `exit;`,
  `exit(v);`, `break;` or `continue;` had ever left the flow. Each fell through
  to whatever followed it.

  It stayed invisible because a guard clause's join block normally holds the very
  assignment the fall-through would have skipped, so the wrong edge changed no
  answer. It became visible where the assignment sits BEYOND the join -- DataCopy
  CopyFileVerified, where an `except` handler ending in `exit` let the "exception
  fired before SrcSize was set" state reach the code after the try and produced
  used-before-assignment on a variable that is plainly set.

  Reading the leading child rather than stripping the semicolon is what also
  fixes `exit(0);`, whose text never resembled 'exit' at all. An entity that is
  not a plain identifier -- `obj.Exit;` -- yields '' and correctly does not
  divert. }
function StatementKeyword(const ANode: TTSNode; const ASrc: TBytes): string;
var
  C: TTSNode;
begin
  Result := '';
  if ANode.NamedChildCount = 0 then Exit;
  C := ANode.NamedChild(0);
  if C.NodeType      = 'identifier' then Result := LowerText(C, ASrc)
  else if C.NodeType = 'exprCall' then
  begin
    C := C.ChildByField('entity');
    if (not C.IsNull) and (C.NodeType = 'identifier') then Result := LowerText(C, ASrc);
  end;
end;

function IsValuedExit(const ANode: TTSNode; const ASrc: TBytes): Boolean;
var
  C, E, A: TTSNode;
begin
  Result := False;
  if ANode.IsNull then Exit;
  C := ANode;
  { accept the statement wrapper as well as the bare call -- a CFG block stores
    the statement, every other caller has the call }
  if C.NodeType = 'statement' then
  begin
    if C.NamedChildCount = 0 then Exit;
    C := C.NamedChild(0);
  end;
  if C.NodeType <> 'exprCall' then Exit;
  E := C.ChildByField('entity');
  if E.IsNull or (E.NodeType <> 'identifier') or (LowerText(E, ASrc) <> 'exit') then Exit;
  A := C.ChildByField('args');
  Result := (not A.IsNull) and (A.NamedChildCount > 0);
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
{ `Fn(Arg)` with exactly one bare-identifier argument -> Arg, lowercased.
  Anything else (a different callee, no args, two args, an expression argument)
  returns ''. Shape, from the real tree:
    (exprCall entity: (identifier "Low") args: (exprArgs (identifier "TGrade"))) }
function SingleIdentArgOf(const ANode: TTSNode; const AFnName: string; const ASrc: TBytes): string;
var
  Ent, Args: TTSNode;
begin
  Result := '';
  if ANode.IsNull then Exit;
  if not SameText(ANode.NodeType, 'exprCall') then Exit;
  Ent := ANode.ChildByField('entity');
  if Ent.IsNull or (not SameText(Ent.NodeType, 'identifier')) then Exit;
  if LowerText(Ent, ASrc) <> LowerCase(AFnName) then Exit;
  Args := ANode.ChildByField('args');
  if Args.IsNull or (not SameText(Args.NodeType, 'exprArgs')) then Exit;
  if Args.NamedChildCount <> 1 then Exit;
  if not SameText(Args.NamedChild(0).NodeType, 'identifier') then Exit;
  Result := LowerText(Args.NamedChild(0), ASrc);
end;

{ The declared type name of a local var or parameter of ARoutine, lowercased,
  or '' when it cannot be determined.

  Deliberately does NOT descend into a nested routine: a nested procedure may
  declare its own variable of the same name with a different type, and answering
  from that one would be worse than answering nothing -- '' simply means "do not
  widen", which is the safe direction here.

  A multi-name declaration (`G, H: TGrade`) exposes only its first `name` field,
  so asking about H returns '' and no widening happens. Also the safe direction. }
function DeclaredTypeOfVar(const ARoutine: TTSNode; const AVarNameLower: string; const ASrc: TBytes): string;

  function TyperefNameOf(const ATypeField: TTSNode): string;
  var
    Tr: TTSNode;
  begin
    Result := '';
    if ATypeField.IsNull or (ATypeField.NamedChildCount = 0) then Exit;
    Tr := ATypeField.NamedChild(0);
    if not SameText(Tr.NodeType, 'typeref') then Exit;
    if Tr.NamedChildCount = 0 then Exit;
    if not SameText(Tr.NamedChild(0).NodeType, 'identifier') then Exit;
    Result := LowerText(Tr.NamedChild(0), ASrc);
  end;

  function Visit(const N: TTSNode): string;
  var
    I: Integer;
  begin
    Result := '';
    if N.IsNull then Exit;
    if SameText(N.NodeType, 'defProc') and (not (N = ARoutine)) then Exit;
    if SameText(N.NodeType, 'declVar') or SameText(N.NodeType, 'declArg') then
      if LowerText(N.ChildByField('name'), ASrc) = AVarNameLower then
        Exit(TyperefNameOf(N.ChildByField('type')));
    for I := 0 to N.NamedChildCount - 1 do
    begin
      Result := Visit(N.NamedChild(I));
      if Result <> '' then Exit;
    end;
  end;

begin
  Result := Visit(ARoutine);
end;

function ForLoopAlwaysExecutes(const ANode, AStartN, ABodyN, ARoutineN: TTSNode; const ASrc: TBytes): Boolean;
var
  LowTxt, HighTxt: string;
  LowVal, HighVal, I: Integer;
  LowN, BoundN: TTSNode;
  IsDownto: Boolean;
  ArgA, ArgB, CtrlVar, DeclTy: string;
begin
  Result := False;
  if AStartN.IsNull or ABodyN.IsNull then Exit;

  { low bound = the start assignment's rhs }
  LowN   := AStartN.ChildByField('rhs');
  LowTxt := LowerText(LowN, ASrc);

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

  { 1. Both bounds are integer literals -- the original rule, unchanged. }
  if TryStrToInt(LowTxt, LowVal) and TryStrToInt(HighTxt, HighVal) then
  begin
    if IsDownto then Result := LowVal >= HighVal
    else Result := LowVal <= HighVal;
    Exit;
  end;

  { 2. `for G := Low(T) to High(T)` (or the downto mirror) where T is the control
    variable's own declared type.

    This is a theorem, not a heuristic: Low(T) <= High(T) holds for every ordinal
    type in the language, so the range is never empty and the body runs at least
    once. Without it every such loop got the zero-trip shape, its body's writes
    were may-defs, and a following read was reported "may be used before
    assigned" -- seven times in DRagLint.Report.Deps.pas alone, all of the form
    `for G:= Low(TDepsGroup) to High(TDepsGroup) do ProjUnitsPerGroup[G]:= nil`.

    WHY THE CONTROL-VARIABLE'S-DECLARED-TYPE CLAUSE IS LOAD-BEARING. The unsound
    neighbour is `Low(V) to High(V)` where V is a dynamic array, open array or
    string VARIABLE: High(V) is -1 when V is empty, so that loop CAN run zero
    times. Widening to it would SUPPRESS true positives -- the wrong failure
    direction. Requiring the argument to be the control variable's declared type
    settles it without a symbol table, because `Low(T)`/`High(T)` on a
    dynamic-array or string TYPE is not legal Delphi (those need an instance):
    if the unit compiles and T is a variable's declared type, T is ordinal.
    run_for_over_ordinal_type_executes.ps1 pins both arms. }
  if IsDownto then
  begin
    ArgA := SingleIdentArgOf(LowN  , 'High', ASrc);
    ArgB := SingleIdentArgOf(BoundN, 'Low' , ASrc);
  end
  else
  begin
    ArgA := SingleIdentArgOf(LowN  , 'Low' , ASrc);
    ArgB := SingleIdentArgOf(BoundN, 'High', ASrc);
  end;
  if (ArgA = '') or (ArgA <> ArgB) then Exit;

  CtrlVar := LowerText(AStartN.ChildByField('lhs'), ASrc);
  if CtrlVar = '' then Exit;
  DeclTy := DeclaredTypeOfVar(ARoutineN, CtrlVar, ASrc);
  Result := (DeclTy <> '') and (DeclTy = ArgA);
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
  { FinallyDepth = how many try..finally blocks enclosed the statement that
    opened this loop. A break/continue replays only the finallys ABOVE that mark
    -- the ones inside the loop. A try..finally wrapping the whole loop is below
    it and must NOT run when the loop merely breaks. }
  TLoopCtx = record ContinueIdx, BreakIdx, FinallyDepth: Integer; end;

  TBuilderState = class
  public
    Cfg      : TCfg;
    Loops    : TStack<TLoopCtx>;
    WithDepth: Integer;
    { Finally BODIES of the try..finally blocks currently enclosing the statement
      being emitted, outermost first. See DivertVia. }
    Finallys : TList<TTSNode>;
    { >0 while emitting an exit-path copy of a finally body, which suspends the
      list so a divert INSIDE a finally cannot recurse into itself forever. }
    CopyDepth: Integer;
    { C1: every block DivertVia emitted as an exit-path COPY of a finally body.
      Those blocks sit inside the try body's index range but are NOT part of its
      normal statement flow, and an exception raised in one is not caught by the
      try's own handler -- the divert has already left the region. The
      body->handler edges added for C1 must skip them, or the handler becomes
      reachable from the inlined finally and the finally's statements are
      analysed twice on ONE path (measured: 5 phantom double-frees on DataCopy
      CSVRoutines.pas, where each object is freed exactly once). }
    DivertBlocks: TDictionary<Integer, Boolean>;
    constructor Create(ACfg: TCfg);
    destructor Destroy; override;
    function EmitStmt(ACur: Integer; const ANode: TTSNode): Integer;
    function EmitList(ACur: Integer; const AContainer: TTSNode): Integer;
    /// <summary>The block a divert should jump to, running every enclosing
    /// finally on the way.</summary>
    function DivertVia(ATarget, AFromDepth: Integer): Integer;
  end;

constructor TBuilderState.Create(ACfg: TCfg);
begin
  inherited Create; Cfg := ACfg; Loops := TStack<TLoopCtx>.Create; WithDepth := 0;
  Finallys := TList<TTSNode>.Create; CopyDepth := 0;
  DivertBlocks := TDictionary<Integer, Boolean>.Create;
end;

destructor TBuilderState.Destroy;
begin
  DivertBlocks.Free;
  Finallys.Free;
  Loops.Free;
  inherited;
end;

{ Delphi runs every enclosing finally before an exit/break/continue leaves the
  region, so the CFG has to as well -- otherwise the resource a finally releases
  looks unreleased on the divert path. Making `exit` divert at all (B9) is what
  exposed this: on DataCopy it turned one CSVRoutines guard clause into a phantom
  object-leak, because the exit reached the routine exit without passing the
  finally that frees the list.

  A COPY of the finally body is emitted on the divert path rather than an edge
  into the block the normal path uses. Sharing that block would let the divert
  state flow onward into the code AFTER the try -- the very fall-through this
  change removes, reintroduced one level up. The copy is on a DIFFERENT path, so
  it is not the duplicate-on-one-path defect that B1 was.

  AFromDepth is where replay STOPS: 0 for exit (every enclosing finally runs),
  and the loop's own mark for break/continue (only the finallys inside the loop
  run -- one wrapping the loop keeps running afterwards). }
function TBuilderState.DivertVia(ATarget, AFromDepth: Integer): Integer;
var
  I, First, Cur, Nxt: Integer;
begin
  Result := ATarget;
  if (Finallys.Count <= AFromDepth) or (CopyDepth > 0) then Exit;
  First := -1; Cur := -1;
  Inc(CopyDepth);
  var CopyFrom: Integer := Cfg.Blocks.Count;
  try
    for I := Finallys.Count - 1 downto AFromDepth do { innermost first }
    begin
      Nxt := Cfg.NewBlock.Index;
      if First < 0 then First := Nxt else Cfg.Blocks[Cur].AddSucc(Nxt);
      Cur := EmitStmt(Nxt, Finallys[I]);
      { the finally body itself diverts -- it never reaches ATarget }
      if Cur < 0 then Exit(First);
    end;
  finally
    Dec(CopyDepth);
    { C1: register everything emitted above as divert-copy, INCLUDING the blocks
      EmitStmt created for the copied body's own control flow. Registered in a
      finally so the `Exit(First)` above -- a finally body that itself diverts --
      cannot leave a half-registered range behind. }
    for var DIdx: Integer := CopyFrom to Cfg.Blocks.Count - 1 do
      DivertBlocks.AddOrSetValue(DIdx, True);
  end;
  Cfg.Blocks[Cur].AddSucc(ATarget);
  Result := First;
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
  Cond, ThenN, ElseN, StartN, EntityN, IterN, LhsN: TTSNode;
  ThenAfter, ElseAfter, JoinIdx, HdrIdx, BodyIdx, FollowIdx, TestIdx, BodyAfter: Integer;
  ElseIdx: Integer; { index of a case's kElse among its named children, -1 = none }
  TryAfter, FinAfter, ExcAfter: Integer;
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

  { A single-statement branch body arrives wrapped in a `statement` node. For a
    LEAF that is harmless -- the wrapper becomes the block item, exactly as
    before -- but a nested if/else is not a leaf, and the grammar does not type
    that one `ifElse`. For the DANGLING ELSE

      if A then if B then S1 else S2

    tree-sitter-delphi13 emits statement(exprIf(...)). Verified with
    tools\dumpnode, not assumed -- see the `case` arm below for what assuming a
    node shape costs in this file.

    Neither 'statement' nor 'exprIf' had an arm here, so the WHOLE nested
    construct fell through to the opaque-item path at the end of this routine
    and every dataflow rule saw one indivisible statement. That is how
    used-before-assignment came to report an `out` argument DEFINED in the inner
    condition as read-before-assignment in a branch that the condition
    dominates: DataCopy uZeissRoutines.pas:1375 and :1675, where the line the
    finding pointed at is a WRITE. Bisected over 13 variants
    (tests\autotest\run_dangling_else_cfg.ps1); an if/else nested in a `for`,
    `while`, `case` or `begin..end` is a plain `ifElse` and always came through
    here correctly, which is why only this one shape was ever wrong. }
  if (K = 'statement') and (ANode.NamedChildCount = 1)
     and (ANode.NamedChild(0).NodeType = 'exprIf') then
    Exit(EmitStmt(ACur, ANode.NamedChild(0)));

  { ----- conditionals ----- }
  if (K = 'if') or (K = 'ifElse') or (K = 'exprIf') then
  begin
    Cond := ANode.ChildByField('condition');
    ThenN := ANode.ChildByField('then');
    ElseN := ANode.ChildByField('else');
    { `exprIf` carries the same kIf / cond / kThen / then [/ kElse / else] child
      sequence as `ifElse`, but it is not guaranteed to DECLARE those fields, so
      resolve positionally whenever the fields come back null. The keywords are
      NAMED children here -- the same trap the `case` arm documents -- so they
      have to be skipped by type rather than by index. }
    if Cond.IsNull or ThenN.IsNull then
      for I := 0 to ANode.NamedChildCount - 1 do
      begin
        EntTxt := ANode.NamedChild(I).NodeType;
        if (EntTxt = 'kIf') or (EntTxt = 'kThen') or (EntTxt = 'kElse') then Continue;
        if Cond.IsNull then Cond := ANode.NamedChild(I)
        else if ThenN.IsNull then ThenN := ANode.NamedChild(I)
        else if ElseN.IsNull then ElseN := ANode.NamedChild(I);
      end;
    if not Cond.IsNull then Cfg.Blocks[ACur].AddItem(Cond, WithDepth > 0);
    JoinIdx := Cfg.NewBlock.Index;
    BodyIdx := Cfg.NewBlock.Index;
    Cfg.Blocks[ACur].AddSucc(BodyIdx);
    ThenAfter := EmitStmt(BodyIdx, ThenN);
    if ThenAfter >= 0 then Cfg.Blocks[ThenAfter].AddSucc(JoinIdx);
    { Branch on the PRESENCE of an else, not on the node's type name: `ifElse`
      always has one, `if` never does, and `exprIf` may go either way. }
    if not ElseN.IsNull then
    begin
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
    { The named-child shape, verified against tree-sitter-delphi13 rather than
      assumed. Both bugs below came from assuming it, so the probe that settled
      it is checked in: tools\dumpcase\dumpcase.dpr prints the named children of
      every `case` node in any file. The shape is:

        kCase, <selector>, kOf, caseCase*, [ kElse, <else statement>* ,] kEnd

      Two things about it are easy to get wrong, and both were:
        - KEYWORDS ARE NAMED NODES here (kCase/kOf/kElse/kEnd), so "the first
          named child" is the `case` keyword, not the selector.
        - THE ELSE ARM IS NOT A NODE and not a field. Unlike `ifElse`, which
          answers ChildByField('else'), a case's else body is a run of BARE
          SIBLINGS between kElse and kEnd. }

    { SELECTOR -- a READ of everything it names. This used to be "the first
      named child that is not a caseCase", which is kCase: the keyword was
      recorded as the block item and the selector expression was never added at
      all. Every read that happens in a case selector was therefore invisible to
      the data-flow rules -- write-only-local called CurLineLast "assigned but
      never read" at YADF.Layout.pas:3325 while line 3512 reads it as
      `case CurLineLast of`. Take what sits between kCase and kOf. }
    for I := 0 to ANode.NamedChildCount - 1 do
    begin
      { Either terminator ends the selector. kOf is the real one; caseCase is a
        guard for a malformed/partially-parsed case, so a missing kOf cannot
        turn this into "add every arm as an item". }
      if (ANode.NamedChild(I).NodeType = 'kOf') or (ANode.NamedChild(I).NodeType = 'caseCase') then Break;
      if ANode.NamedChild(I).NodeType = 'kCase' then Continue;
      Cfg.Blocks[ACur].AddItem(ANode.NamedChild(I), WithDepth > 0);
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

    { ELSE ARM. This used to be a single `AddSucc(JoinIdx)` -- a fall-through
      edge and nothing else -- so the else BODY was never emitted. Two bugs in
      one line: assignments inside `case..else` were invisible, and the CFG
      carried a path through the case that assigns nothing. That path is what
      made function-result-not-set fire on YADF.Options.pas:593 EncodingOf,
      whose every arm (else included) sets Result.
      The correct shape is the `if` handler above: emit the body as its own
      block and join it. }
    ElseIdx := -1;
    for I := 0 to ANode.NamedChildCount - 1 do
      if ANode.NamedChild(I).NodeType = 'kElse' then begin ElseIdx := I; Break; end;

    if ElseIdx >= 0 then
    begin
      BodyIdx := Cfg.NewBlock.Index;
      Cfg.Blocks[ACur].AddSucc(BodyIdx);
      ElseAfter := BodyIdx;
      for I := ElseIdx + 1 to ANode.NamedChildCount - 1 do
      begin
        if ANode.NamedChild(I).NodeType = 'kEnd' then Break;
        if ElseAfter < 0 then Break; { unreachable tail -- same rule as EmitList }
        ElseAfter := EmitStmt(ElseAfter, ANode.NamedChild(I));
      end;
      if ElseAfter >= 0 then Cfg.Blocks[ElseAfter].AddSucc(JoinIdx);
      { NO direct ACur -> JoinIdx edge here: a case WITH an else is exhaustive.
        Leaving it would keep exactly the assigns-nothing path this fix exists
        to remove, and function-result-not-set would go on firing. }
    end
    else
      Cfg.Blocks[ACur].AddSucc(JoinIdx); { no else -> an unmatched selector skips to the join }
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
    Ctx.ContinueIdx := HdrIdx; Ctx.BreakIdx := FollowIdx; Ctx.FinallyDepth := Finallys.Count; Loops.Push(Ctx);
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
    if ForLoopAlwaysExecutes(ANode, StartN, ANode.ChildByField('body'), Cfg.RoutineNode, Cfg.Src) then
      Cfg.Blocks[ACur].AddSucc(BodyIdx)
    else
      Cfg.Blocks[ACur].AddSucc(HdrIdx);
    Ctx.ContinueIdx := HdrIdx; Ctx.BreakIdx := FollowIdx; Ctx.FinallyDepth := Finallys.Count; Loops.Push(Ctx);
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
    Ctx.ContinueIdx := HdrIdx; Ctx.BreakIdx := FollowIdx; Ctx.FinallyDepth := Finallys.Count; Loops.Push(Ctx);
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
    Ctx.ContinueIdx := TestIdx; Ctx.BreakIdx := FollowIdx; Ctx.FinallyDepth := Finallys.Count; Loops.Push(Ctx);
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
    { While the TRY BODY is being emitted, this finally is in scope for any
      exit/break/continue inside it -- see DivertVia. Pushed only around the
      body: a divert in the FINALLY itself does not re-run it. }
    { C1: remember which blocks the TRY BODY occupies, so the handler edges
      below can come from all of them and not only from the region entry. Every
      block created while the body is emitted belongs to the body -- BodyIdx and
      FollowIdx both already exist, so neither is caught by this range. }
    var BodyFirst: Integer := Cfg.Blocks.Count;
    if FinNode.IsNull then TryAfter := EmitStmt(BodyIdx, TryNode)
    else
    begin
      Finallys.Add(FinNode);
      try
        TryAfter := EmitStmt(BodyIdx, TryNode);
      finally
        Finallys.Delete(Finallys.Count - 1);
      end;
    end;
    var BodyLast: Integer := Cfg.Blocks.Count - 1;
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
      { THE HANDLERS BEGIN AFTER kExcept, and nothing before it is one.

        The scan used to accept any 'statements' child at index > 0. The try
        node's children are (kTry) (statements = the TRY BODY) (kExcept)
        (statements = the handler) (kEnd), so index 1 -- the try body itself --
        satisfied that test. EVERY try..except therefore emitted its try body
        into the CFG a SECOND time, as a pseudo-handler wired from the try
        entry and on into the follow block. One statement was analysed as two
        on a single path: a lone `X.Free;` inside a try body was reported as a
        double free (DataCopy DPPRoutines 302-303), and the duplicate reached
        the follow block, which is the second merge route that survived the
        earlier fix to the diverting-handler edge below.

        It was never conditional on what the handler does -- the bare-handler,
        fall-through and `on E: ... do` shapes were all wrong, and all three are
        pinned in tests/lint/double-free.pas (P7-P9) with the genuine double
        frees kept as controls (P10-P11) so a fix that simply stopped analysing
        try bodies fails instead of shipping.

        Tracking the token, rather than skipping index 1, is what makes this
        structural: it says what the grammar means. If kExcept is somehow absent
        no handler is emitted at all, which loses handler analysis but cannot
        invent a path -- the safe direction. }
      var SeenExcept := False;
      for I := 0 to ANode.NamedChildCount - 1 do
      begin
        if ANode.NamedChild(I).NodeType = 'kExcept' then
        begin
          SeenExcept := True;
          Continue;
        end;
        if SeenExcept and ((ANode.NamedChild(I).NodeType = 'exceptionHandler')
                           or (ANode.NamedChild(I).NodeType = 'statements')) then
        begin
          HdrIdx := Cfg.NewBlock.Index;
          Cfg.Blocks[BodyIdx].AddSucc(HdrIdx); { try entry -> handler (conservative) }

          { C1: AN EXCEPTION CAN BE RAISED AT ANY STATEMENT IN THE BODY, NOT ONLY
            BEFORE THE FIRST ONE. The entry edge above models "it threw before
            anything ran", which is the right MOST-CONSERVATIVE state but is not
            the only one, and on its own it makes every assignment in a later
            basic block unable to reach the handler at all. A local assigned
            after a branch and read ONLY by the handler therefore looked dead:

              LOpened := False;   // later block, because of an earlier if/exit
              ...
              except on E: Exception do
                if LOpened and (not RollBackOutput) then ...   // the reader

            Measured on DataCopy: 7 such findings when this note was written,
            11 today (uMahrRoutines.pas, DPPRoutines.pas and the newer
            uMarpossRoutines.pas), every one of them a FALSE POSITIVE on a store
            the handler genuinely consumes -- and a dangerous class of FP,
            because acting on it deletes the assignment the error path depends
            on.

            Adding the remaining body blocks can only make MORE reads reachable
            from an assignment; it never removes an assignment from a path. So
            it cannot manufacture a used-before-assignment: the "nothing in the
            body ran" state still arrives via the entry edge above and remains
            the dominating one for that rule.

            NOT extended to `finally` -- that edge is refused deliberately just
            above, and for a different reason (it would route the skipped-body
            state into the normal post-finally exit and fire
            function-result-not-set on routines that set Result in the try). }
          for var BIdx := BodyFirst to BodyLast do
            if not DivertBlocks.ContainsKey(BIdx) then
              Cfg.Blocks[BIdx].AddSucc(HdrIdx);
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
        end; { if -- this child is a handler }
      end; { for }
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
    if K      = 'exprCall'  then EntTxt := LowerText(ANode.ChildByField('entity'), Cfg.Src)
    else if K = 'statement' then EntTxt := StatementKeyword(ANode, Cfg.Src) { B9 -- see its header }
    else EntTxt := LowerText(ANode, Cfg.Src);
    Cfg.Blocks[ACur].AddItem(ANode, WithDepth > 0);
    { DivertVia, not a bare edge: every enclosing finally runs before control
      leaves. exit replays them all (depth 0); break/continue replay only those
      opened INSIDE their loop. }
    if EntTxt = 'exit' then
    begin Cfg.Blocks[ACur].AddSucc(DivertVia(Cfg.ExitIdx, 0)); Exit(-1); end;
    if (EntTxt = 'break') and (Loops.Count > 0) then
    begin Cfg.Blocks[ACur].AddSucc(DivertVia(Loops.Peek.BreakIdx, Loops.Peek.FinallyDepth)); Exit(-1); end;
    if (EntTxt = 'continue') and (Loops.Count > 0) then
    begin Cfg.Blocks[ACur].AddSucc(DivertVia(Loops.Peek.ContinueIdx, Loops.Peek.FinallyDepth)); Exit(-1); end;
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
