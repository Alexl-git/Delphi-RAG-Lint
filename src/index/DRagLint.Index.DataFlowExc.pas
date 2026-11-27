unit DRagLint.Index.DataFlowExc;

/// <summary>1.56 B4 (lane EXT-B2): data flows through `raise` and through except handlers,
/// as data_flows rows. The unit has no public surface: its initialization registers one
/// statement hook and three expression hooks with TDataFlowFacts
/// (DRagLint.Index.DataFlowFacts, the EXT-B1 seam), which calls them during the per-routine
/// data-flow walk.</summary>
/// <remarks>
/// RAISE side (dst_kind DF_DST_RAISE, position = the `raise` statement):
///   `raise T.Create*(a0, a1)`   one row per source of each argument: dst_name = T as
///                               written, dst_receiver = the unit qualifier of `U.T` (else
///                               ''), dst_index = the argument position;
///   `raise;`                    dst_name '', dst_index -1, source = the exception object of
///                               the enclosing except context (below);
///   `raise X` (anything else)   dst_index -1, source = the value of X; dst_name = the
///                               handled class when X is the handler variable, else ''.
/// A literal argument has no source and makes no row.
/// HANDLE side (src_kind DF_SRC_EXCEPT, src_index -1, val_class ''): inside `on E: T do`
/// every read rooted at E (`E`, `E.Message`, `E.ToString()`, `(E as T2).Code`, `T2(E).Code`)
/// gets the source src_name = T (the unit qualifier dropped), position = the `on` clause.
/// Inside any except part (handler, bare `except .. end`, `else`) a read rooted at
/// `ExceptObject` gets the source of the innermost context: a handler as above, otherwise
/// src_name '' at the `except` keyword. The source is ADDED to what the walk computed, so
/// every pre-1.56 row is still emitted unchanged; the new rows are those with dst_kind
/// 'raise' or src_kind 'except'.
/// The two sides are NOT joined here: a consumer (taint through exceptions, lane FA-2)
/// joins a raise row to an except source by class name, inside one routine or across
/// routines, with the class hierarchy it has and this extractor has not.
/// LIMITS: `AcquireExceptionObject` is not a source; a handler variable captured by an
/// anonymous method declared INSIDE the handler is found, one whose name a lambda
/// parameter shadows is still read as the handler variable; `raise` in a `with` body is
/// not walked, and neither is the `else` part of an except block (the walk's own limits:
/// DRagLint.Analysis.Cfg emits no item for either).
/// State: one process-wide cache of the except contexts of the routine being walked
/// (GCache), keyed on the WALK (TDataFlowSite.WalkId) and the routine's byte range. A walk
/// id is never reused in a process, so the memo cannot outlive the tree it was built from
/// (FIXR-B, REV-1 #2: the earlier key -- tree address, node id, range -- matched a later
/// parse whose tree reused the address, and then served that parse the contexts and the
/// nodes of a freed tree). NOT thread-safe, like the walk it serves (the indexer's
/// per-file loop is single-threaded).
/// This unit is under src\index: any change to it is an extractor change. All .pas
/// source: strict 7-bit ASCII, CRLF, no BOM.
/// </remarks>

interface

implementation

uses
  System.SysUtils
  , System.StrUtils
  , TreeSitter
  , TreeSitterLib
  , DRagLint.Core.Model  // dl:ok uses-global-census@64a5 -- the named constants are the whole contract this unit draws; the unit pair travels together
  , DRagLint.Index.DataFlowFacts
  ;

const
  DFX_NT_RAISE      = 'raise';
  DFX_NT_TRY        = 'try';
  DFX_NT_HANDLER    = 'exceptionHandler';
  DFX_NT_EXCEPT_KW  = 'kExcept';
  DFX_NT_ROUTINE    = 'defProc';
  DFX_NT_IDENT      = 'identifier';
  DFX_NT_DOT        = 'exprDot';
  DFX_NT_CALL       = 'exprCall';
  DFX_NT_SUBSCRIPT  = 'exprSubscript';
  DFX_NT_TPL        = 'exprTpl';
  DFX_NT_PARENS     = 'exprParens';
  DFX_NT_BINARY     = 'exprBinary';
  DFX_F_EXCEPTION   = 'exception';
  DFX_F_VARIABLE    = 'variable';
  DFX_F_LHS         = 'lhs';
  DFX_F_RHS         = 'rhs';
  DFX_F_ENTITY      = 'entity';
  DFX_F_ARGS        = 'args';
  DFX_F_OPERATOR    = 'operator';
  DFX_OP_AS         = 'as';
  DFX_EXCEPT_WORD   = 'except';
  DFX_EXCEPT_OBJECT = 'exceptobject';
  DFX_ROOT_CLASS    = 'exception';
  DFX_CTOR_PREFIX   = 'Create';
  DFX_UNIT_DOT      = '.';
  DFX_GENERIC_OPEN  = '<';
  { dst_index / src_index of "the object itself" (DF_DST_RAISE, DF_SRC_EXCEPT) }
  DFX_NO_INDEX      = -1;
  { a bound on a malformed tree only: real receiver chains stay in single digits }
  DFX_CHAIN_DEPTH   = 32;
  { `EFoo(X)` / `TFoo(X)`: the shortest name that reads as a hard cast }
  DFX_CAST_MIN_LEN  = 2;
  DFX_CAST_SECOND   = 2;

type
  { One except context of the cached routine: the byte range in which its exception
    object is live. }
  TExcCtx = record
    StartByte: UInt32;
    EndByte  : UInt32;
    { the handler variable, lower-case; '' = none (`on T do`, bare except, else part) }
    VarLower : string;
    { the handled class as written, unit qualifier dropped; '' = any }
    ClassName: string;
    { the `on` clause, or the `except` keyword of a bare except / else part }
    Pos      : TTSNode;
  end;

  { The except contexts of ONE routine (TopId .. the innermost defProc holding the node
    the cache was built for, or the tree root for a program's main block), in document
    order: an enclosing context comes before the contexts inside it. }
  TExcCache = record
    Valid   : Boolean;
    { the walk the contexts were collected for; its tree is alive while that walk runs }
    WalkId  : UInt64;
    TopStart: UInt32;
    TopEnd  : UInt32;
    Ctxs    : TArray<TExcCtx>;
  end;

var
  GCache: TExcCache;

{ ---- the cache -------------------------------------------------------------- }

{ The innermost routine node holding pNode: one descent from the root (a Parent chain
  costs one such descent PER ancestor). The root itself for a main block. }
function RoutineOf(const pNode: TTSNode): TTSNode;
var
  Cur : TTSTreeCursor;
  Goal: UInt32;
  Kid : TTSNode;
begin
  Result:= ts_tree_root_node(pNode.tree);
  Goal:= pNode.StartByte;
  Cur:= TTSTreeCursor.Create(Result);
  try
    while Cur.GotoFirstChildForGoal(Goal) >= 0 do
    begin
      Kid:= Cur.CurrentNode;
      if Kid.StartByte > Goal then Break;
      if Kid.NodeType = DFX_NT_ROUTINE then Result:= Kid;
    end;
  finally
    Cur.Free;
  end;
end;

function SimpleClassName(const pTypeText: string): string;
begin
  Result:= Trim(pTypeText);
  if not Result.Contains(DFX_GENERIC_OPEN) then
    Result:= Copy(Result, LastDelimiter(DFX_UNIT_DOT, Result) + 1, MaxInt);
end;

procedure AddCtx(const pCtx: TExcCtx);
begin
  GCache.Ctxs:= GCache.Ctxs + [pCtx];
end;

{ `try .. except <here> end`: the bare / else context, from the keyword to the end }
procedure AddTryCtx(const pTry: TTSNode);
var
  I  : Integer;
  Kid: TTSNode;
  Ctx: TExcCtx;
begin
  for I:= 0 to pTry.NamedChildCount - 1 do
  begin
    Kid:= pTry.NamedChild(I);
    if Kid.NodeType <> DFX_NT_EXCEPT_KW then Continue;
    Ctx:= Default(TExcCtx);
    Ctx.StartByte:= Kid.StartByte;
    Ctx.EndByte  := pTry.EndByte;
    Ctx.Pos      := Kid;
    AddCtx(Ctx);
    Exit;
  end;
end;

procedure AddHandlerCtx(pSite: TDataFlowSite; const pHandler: TTSNode);
var
  Ctx: TExcCtx;
begin
  Ctx:= Default(TExcCtx);
  Ctx.StartByte:= pHandler.StartByte;
  Ctx.EndByte  := pHandler.EndByte;
  Ctx.VarLower := LowerCase(Trim(pSite.NodeText(pHandler.ChildByField(DFX_F_VARIABLE))));
  Ctx.ClassName:= SimpleClassName(pSite.NodeText(pHandler.ChildByField(DFX_F_EXCEPTION)));
  Ctx.Pos      := pHandler;
  AddCtx(Ctx);
end;

{ Pre-order over the routine's subtree, so an enclosing context is added first. }
procedure CollectCtxs(pSite: TDataFlowSite; const pTop: TTSNode);
var
  Cur : TTSTreeCursor;
  N   : TTSNode;
  NT  : string;
  Done: Boolean;
begin
  Cur:= TTSTreeCursor.Create(pTop);
  try
    Done:= False;
    while not Done do
    begin
      N:= Cur.CurrentNode;
      if N.IsNamed then
      begin
        NT:= N.NodeType;
        if NT = DFX_NT_TRY then AddTryCtx(N)
        else if NT = DFX_NT_HANDLER then AddHandlerCtx(pSite, N);
      end;
      if Cur.GotoFirstChild then Continue;
      while (not Done) and (not Cur.GotoNextSibling) do
        Done:= not Cur.GotoParent;
    end;
  finally
    Cur.Free;
  end;
end;

procedure Rebuild(pSite: TDataFlowSite; const pTop: TTSNode);
begin
  GCache.Valid   := True;
  GCache.WalkId  := pSite.WalkId;
  GCache.TopStart:= pTop.StartByte;
  GCache.TopEnd  := pTop.EndByte;
  GCache.Ctxs    := nil;
  { most routines have no except at all: one text scan spares them the tree walk }
  if ContainsText(pSite.NodeText(pTop), DFX_EXCEPT_WORD) then CollectCtxs(pSite, pTop);
end;

{ Makes GCache describe the routine pNode is in. The memo is good for ONE walk: another
  walk (the next routine, the next file, a second parse of this file) has another WalkId
  and rebuilds, whatever addresses its tree landed on. Inside one walk a node outside the
  cached range is another routine (a main block next to its nested routines).
  Returns False when the routine has no except context (the common case, kept cheap). }
function Ensure(pSite: TDataFlowSite; const pNode: TTSNode): Boolean;
var
  At: UInt32;
begin
  At:= pNode.StartByte;
  if not (GCache.Valid and (GCache.WalkId = pSite.WalkId) and (At >= GCache.TopStart) and (At < GCache.TopEnd)) then
    Rebuild(pSite, RoutineOf(pNode));
  Result:= GCache.Ctxs <> nil;
end;

{ The innermost cached context holding byte pAt; with pNeedVar, the innermost one that
  declares the variable pVarLower (an inner `on T do` does not hide an outer E). }
function FindCtx(pAt: UInt32; const pVarLower: string; pNeedVar: Boolean; out pCtx: TExcCtx): Boolean;
var
  I: Integer;
begin
  for I:= High(GCache.Ctxs) downto 0 do
  begin
    if (pAt < GCache.Ctxs[I].StartByte) or (pAt >= GCache.Ctxs[I].EndByte) then Continue;
    if pNeedVar and (GCache.Ctxs[I].VarLower <> pVarLower) then Continue;
    pCtx:= GCache.Ctxs[I];
    Exit(True);
  end;
  pCtx:= Default(TExcCtx);
  Result:= False;
end;

{ ---- shapes ------------------------------------------------------------------- }

{ `Exception(X)`, `EFoo(X)`, `TFoo(X)`: a one-argument call of a type-like bare name }
function IsCastLike(pSite: TDataFlowSite; const pCall: TTSNode): Boolean;
var
  Ent, Args: TTSNode;
  Nm       : string;
begin
  Result:= False;
  Ent := pCall.ChildByField(DFX_F_ENTITY);
  Args:= pCall.ChildByField(DFX_F_ARGS);
  if Ent.IsNull or (Ent.NodeType <> DFX_NT_IDENT) or Args.IsNull or (Args.NamedChildCount <> 1) then Exit;
  Nm:= pSite.NodeText(Ent);
  if SameText(Nm, DFX_ROOT_CLASS) then Exit(True);
  Result:= (Length(Nm) >= DFX_CAST_MIN_LEN) and CharInSet(Nm[1], ['E', 'T']) and CharInSet(Nm[DFX_CAST_SECOND], ['A'..'Z']);
end;

{ The identifier an expression is rooted at: `E` -> E, `E.Message` -> E, `E.ToString()`
  -> E, `(E as T).Code` -> E, `T(E).Code` -> E; `Sink(E)` -> Sink. Null when the root is
  no identifier. }
function ChainRoot(pSite: TDataFlowSite; const pExpr: TTSNode): TTSNode;
var
  N    : TTSNode;
  NT   : string;
  Guard: Integer;
begin
  N:= pExpr;
  for Guard:= 1 to DFX_CHAIN_DEPTH do
  begin
    if N.IsNull then Break;
    NT:= N.NodeType;
    if NT = DFX_NT_IDENT then Exit(N);
    if NT = DFX_NT_DOT then N:= N.ChildByField(DFX_F_LHS)
    else if (NT = DFX_NT_CALL) and IsCastLike(pSite, N) then N:= N.ChildByField(DFX_F_ARGS).NamedChild(0)
    else if (NT = DFX_NT_CALL) or (NT = DFX_NT_SUBSCRIPT) or (NT = DFX_NT_TPL) then N:= N.ChildByField(DFX_F_ENTITY)
    else if (NT = DFX_NT_PARENS) and (N.NamedChildCount = 1) then N:= N.NamedChild(0)
    else if (NT = DFX_NT_BINARY) and SameText(Trim(pSite.NodeText(N.ChildByField(DFX_F_OPERATOR))), DFX_OP_AS) then
      N:= N.ChildByField(DFX_F_LHS)
    else Break;
  end;
  Result:= Default(TTSNode);
end;

{ True when identifier pIdent reads an exception object: the handler variable of an
  enclosing `on E: T do`, or ExceptObject inside any except part. }
function ExceptionObjectAt(pSite: TDataFlowSite; const pIdent: TTSNode; out pCtx: TExcCtx): Boolean;
var
  Nm: string;
begin
  pCtx:= Default(TExcCtx);
  if pIdent.IsNull then Exit(False);
  Nm:= LowerCase(pSite.NodeText(pIdent));
  Result:= if Nm = DFX_EXCEPT_OBJECT then FindCtx(pIdent.StartByte, '', False, pCtx)
           else (Nm <> '') and FindCtx(pIdent.StartByte, Nm, True, pCtx);
end;

function CtxSource(pSite: TDataFlowSite; const pCtx: TExcCtx): TDataFlowValue;
begin
  Result:= pSite.NewSource(DF_SRC_EXCEPT, DFX_NO_INDEX, pCtx.Pos, pCtx.ClassName, '');
end;

{ `T.Create*(..)`, `U.T.Create*(..)` and the paren-less `T.Create`: a construction of T
  (the same shape DRagLint.Parser.Delphi13.EmitRaiseReference reads as a raise ref). }
function CtorShape(pSite: TDataFlowSite; const pExpr: TTSNode; out pClass, pUnit: string; out pArgs: TTSNode): Boolean;
var
  Callee, Ctor, TypeN: TTSNode;
begin
  pClass:= '';
  pUnit := '';
  pArgs := Default(TTSNode);
  Callee:= pExpr;
  if Callee.NodeType = DFX_NT_CALL then
  begin
    pArgs := Callee.ChildByField(DFX_F_ARGS);
    Callee:= Callee.ChildByField(DFX_F_ENTITY);
  end;
  if Callee.IsNull or (Callee.NodeType <> DFX_NT_DOT) then Exit(False);
  Ctor := Callee.ChildByField(DFX_F_RHS);
  TypeN:= Callee.ChildByField(DFX_F_LHS);
  if (not TypeN.IsNull) and (TypeN.NodeType = DFX_NT_DOT) then
  begin
    pUnit:= Trim(pSite.NodeText(TypeN.ChildByField(DFX_F_LHS)));
    TypeN:= TypeN.ChildByField(DFX_F_RHS);
  end;
  Result:= (not Ctor.IsNull) and (Ctor.NodeType = DFX_NT_IDENT)
           and StartsText(DFX_CTOR_PREFIX, pSite.NodeText(Ctor))
           and (not TypeN.IsNull) and (TypeN.NodeType = DFX_NT_IDENT);
  if Result then pClass:= pSite.NodeText(TypeN);
end;

{ ---- the hooks ---------------------------------------------------------------- }

{ `raise ..`: the rows of the RAISE side (unit remarks). Rows are written on the recording
  pass only, and the walk evaluates the statement itself right after this hook, so the
  earlier passes need nothing from here. }
procedure RaiseStmtHook(pSite: TDataFlowSite; const pNode: TTSNode);
var
  Expr, Args : TTSNode;
  Cls, UnitNm: string;
  Ctx        : TExcCtx;
  HasCtx     : Boolean;
  I          : Integer;
begin
  HasCtx:= Ensure(pSite, pNode);
  if not pSite.IsRecording then Exit;
  Expr:= pNode.ChildByField(DFX_F_EXCEPTION);
  if Expr.IsNull then
  begin
    if HasCtx and FindCtx(pNode.StartByte, '', False, Ctx) then
      pSite.EmitRow(DF_DST_RAISE, pNode, DFX_NO_INDEX, '', '', CtxSource(pSite, Ctx));
    Exit;
  end;
  if CtorShape(pSite, Expr, Cls, UnitNm, Args) then
  begin
    if Args.IsNull then Exit;
    for I:= 0 to Args.NamedChildCount - 1 do
      pSite.EmitRow(DF_DST_RAISE, pNode, I, Cls, UnitNm, pSite.ValueOf(Args.NamedChild(I)));
    Exit;
  end;
  Cls:= '';
  if HasCtx and (Expr.NodeType = DFX_NT_IDENT) and ExceptionObjectAt(pSite, Expr, Ctx) then Cls:= Ctx.ClassName;
  pSite.EmitRow(DF_DST_RAISE, pNode, DFX_NO_INDEX, Cls, '', pSite.ValueOf(Expr));
end;

{ An identifier, a member chain or a call: when it is rooted at an exception object, that
  object's source is added to its value (the HANDLE side, unit remarks). }
procedure ExceptReadHook(pSite: TDataFlowSite; const pNode: TTSNode; var pValue: TDataFlowValue);
var
  Ctx: TExcCtx;
begin
  if not Ensure(pSite, pNode) then Exit;
  { outside every except part nothing can match: no text is read }
  if not FindCtx(pNode.StartByte, '', False, Ctx) then Exit;
  if ExceptionObjectAt(pSite, ChainRoot(pSite, pNode), Ctx) then
    pValue:= pSite.Merge(pValue, CtxSource(pSite, Ctx));
end;

initialization
  TDataFlowFacts.RegisterStmtHook(DFX_NT_RAISE, RaiseStmtHook);
  TDataFlowFacts.RegisterExprHook(DFX_NT_IDENT, ExceptReadHook);
  TDataFlowFacts.RegisterExprHook(DFX_NT_DOT, ExceptReadHook);
  TDataFlowFacts.RegisterExprHook(DFX_NT_CALL, ExceptReadHook);

end.
