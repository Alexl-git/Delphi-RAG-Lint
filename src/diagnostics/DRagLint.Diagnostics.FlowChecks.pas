unit DRagLint.Diagnostics.FlowChecks;

{ Flow-sensitive lint checks (M2): runs the data-flow analyses per routine and
  maps results to TLintFinding. Mirrors the TAstChecker.CheckXxx integration
  (parse cache + optional ISymbolStore, nil-safe). Definite violations =
  warning, possible violations = info. }

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.Character,
  TreeSitter,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Diagnostics.ParseCache,
  DRagLint.Analysis.Cfg,
  DRagLint.Analysis.DataFlow,
  DRagLint.Analysis.Flow.Lattices;

type
  /// <summary>Flow-sensitive checks over a single file's routines.</summary>
  TFlowChecker = class
  public
    /// <summary>Run every flow check on AFile. AStore (optional, nil-safe)
    /// enables exact managed-type classification via M1 ResolveTypeCategory and
    /// (later) the interprocedural object-leak refinement.</summary>
    /// <param name="AFile">Path to the .pas/.inc file.</param>
    /// <param name="AStore">Optional symbol store; nil on the bare lint path.</param>
    /// <param name="AFileId">File id within AStore (0 when no store).</param>
    /// <returns>All flow findings for the file.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoCheckAst (DRagLint.CLI.pas), DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)
    /// Calls: alternatives, AssignmentBaseIndex, AssignmentTargetIndex, bail, CollectInterfaceDerefs, CollectReadsAndCallDefs, ConstructorTransfersOwnership, Copy, cycles, Default (+28 more)
    /// Returns: nil; True; not ParamClearlyNonOwning(DP, PName, CPF.Src); Findings.ToArray
    /// Complexity: 17 (cyclomatic, outer body), 567 lines (full implementation)
    /// Touches: file system
    /// <seealso cref="DRagLint.Analysis.Cfg.CfgFindProcs"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Diagnostics.FlowChecks.FindCalleeDefProc"/>
    /// <seealso cref="DRagLint.Diagnostics.FlowChecks.ParamClearlyNonOwning"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Check(const AFile: string; const AStore: ISymbolStore = nil;
      AFileId: Int64 = 0): TArray<TLintFinding>;
  end;

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

{ Managed (compiler zero-initialized) types are skipped by used-before /
  function-result-not-set, matching W1036. Store-exact when present, name
  heuristic otherwise. }
function IsManagedType(const ATypeText: string; const AStore: ISymbolStore; AFileId: Int64): Boolean;
var Cat: TTypeCategory; T: string;
begin
  if AStore <> nil then
  begin
    Cat := AStore.ResolveTypeCategory(ATypeText, AFileId);
    if Cat <> tcUnknown then
      Exit((Cat = tcString) or (Cat = tcInterface));
  end;
  T := LowerCase(Trim(ATypeText));
  if (T = 'string') or (T = 'unicodestring') or (T = 'ansistring') or (T = 'widestring')
     or (T = 'rawbytestring') or (T = 'variant') or (T = 'olevariant') then Exit(True);
  if (Pos('array of', T) > 0) or (Pos('tarray<', T) > 0) then Exit(True);
  { I-prefixed interface convention: 'I' + uppercase letter }
  if (Length(ATypeText) >= 2) and (ATypeText[1] = 'I') and ATypeText[2].IsUpper then Exit(True);
  Result := False;
end;

{ Interface-typed subset of IsManagedType, for not-assigned-interface: store-exact
  via ResolveTypeCategory = tcInterface when a store is present, else the same
  'I' + uppercase-letter naming-convention fallback used by IsManagedType. }
function IsInterfaceType(const ATypeText: string; const AStore: ISymbolStore; AFileId: Int64): Boolean;
var Cat: TTypeCategory; T: string;
begin
  if AStore <> nil then
  begin
    Cat := AStore.ResolveTypeCategory(ATypeText, AFileId);
    if Cat <> tcUnknown then Exit(Cat = tcInterface);
  end;
  T := Trim(ATypeText);
  Result := (Length(T) >= 2) and (T[1] = 'I') and T[2].IsUpper;
end;

/// <summary>Record-typed subset of the type-category family (IsManagedType /
/// IsInterfaceType): True only when a store is present and ATypeText resolves to
/// tcRecord.</summary>
/// <param name="ATypeText">The variable's declared type text, verbatim from the
/// routine var table.</param>
/// <param name="AStore">Symbol store used to resolve the type's KIND; nil
/// disables this check entirely (returns False).</param>
/// <param name="AFileId">File id scoping the resolution (0 when no store).</param>
/// <returns>True only when AStore resolves ATypeText to tcRecord.</returns>
/// <remarks>Deliberately carries NO naming-convention fallback, unlike
/// IsInterfaceType's 'I'+uppercase spelling convention -- a record has no
/// reliable name shape to guess from, and this predicate feeds the record-
/// method-call-defines-the-local seam in CollectReadsAndCallDefs (see
/// TRecordMethodDefPredicate). Guessing "this looks like a record" would risk
/// widening that used-before-assignment suppression to CLASS references that
/// merely look record-like, which is exactly the false negative the task's
/// hard constraint forbids: a method call on an uninitialised class reference
/// is a genuine nil-dereference bug and must keep being flagged. Without a
/// store this returns False, which is today's (pre-fix) behaviour, so the
/// store-free lint path cannot silently over-suppress.</remarks>
function IsRecordType(const ATypeText: string; const AStore: ISymbolStore; AFileId: Int64): Boolean;
begin
  Result := False;
  if AStore = nil then Exit;
  Result := AStore.ResolveTypeCategory(ATypeText, AFileId) = tcRecord;
end;

/// <summary>Tests whether AConstructorNode (an already-confirmed constructor
/// call/dot-expr per ExprIsConstructor) transfers ownership of the created
/// object to a VCL owner, per TComponent's owner-parenting contract: a
/// TComponent descendant constructed with a non-nil AOwner argument is
/// inserted into that owner's Components list and freed automatically when
/// the owner is destroyed, so the local holding the reference is NOT a leak
/// candidate even if never separately stored or freed. Requires a store
/// (ancestry needs the indexed type hierarchy) -- on the bare no-store lint
/// path this always returns False, leaving the current (conservative) leak
/// check in effect. Also False for Create(nil) (explicit nil owner: no
/// owner, so no transfer -- genuinely leak-checked) and for any type that
/// does not resolve as a TComponent descendant (e.g. TStringList.Create,
/// which has no AOwner parameter at all).</summary>
/// <param name="AConstructorNode">The constructor RHS expr node (exprCall or
/// exprDot), as passed to ExprIsConstructor.</param>
/// <param name="ASrc">The routine's source bytes (for node-text extraction).</param>
/// <param name="AStore">Optional symbol store; nil disables this check.</param>
/// <param name="AFileId">File id within AStore (0 when no store).</param>
/// <returns>True only when a store is present, the constructed type is a
/// TComponent descendant, and the first constructor argument is present and
/// is not the literal "nil".</returns>
/// <summary>True when ATypeText names a type that CANNOT leak, so a
/// "created but never freed" finding about it would be unfalsifiable: an
/// INTERFACE (reference-counted by the runtime -- freeing it manually is the
/// bug) or a RECORD / value type (never heap-allocated; there is no Free to
/// call).</summary>
/// <param name="ATypeText">The variable's declared type text, verbatim from the
/// routine var table. Generic arguments are ignored -- only the head name is
/// resolved, so IList&lt;TFoo&gt; is judged on IList.</param>
/// <param name="AStore">Symbol store used to resolve the type's KIND. When nil
/// or when the type is not indexed, falls back to the naming convention.</param>
/// <returns>True to SUPPRESS an object-leak finding for this variable.</returns>
/// <remarks>INDEX-GROUNDED FIRST, convention only as a fallback. Resolving the
/// kind through the store is what separates this from a name sniff: a CLASS
/// deliberately named <c>IniFile</c> would be misjudged by an "starts with I"
/// test, and that class CAN leak. The convention fallback is therefore
/// deliberately strict -- 'I' followed by an UPPERCASE letter -- and applies
/// only when the index cannot answer, which is the same absence-over-a-wrong-
/// verdict policy the ownership fact uses.</remarks>
function TypeIsRefCountedOrValue(const ATypeText: string;
  const AStore: ISymbolStore): Boolean;
var
  Head: string;
  P   : Integer;
  Syms: TArray<TSymbol>;
  S   : TSymbol;
begin
  Result:= False;
  Head:= Trim(ATypeText);
  if Head = '' then Exit;
  { Strip a generic argument list: IList<TFoo> -> IList. The head is what
    carries the kind; the argument is a different type entirely. }
  P:= Pos('<', Head);
  if P > 0 then Head:= Trim(Copy(Head, 1, P - 1));
  if Head = '' then Exit;

  { Index-grounded: an interface or a record cannot leak. }
  if AStore <> nil then
  begin
    Syms:= AStore.FindSymbolsByExactName(Head);
    for S in Syms do
      if S.Kind in [skInterface, skRecord] then Exit(True);
    { The type IS indexed and is not an interface/record -> it is a class or
      similar and CAN leak. Trust the index over the convention below. }
    if Length(Syms) > 0 then Exit(False);
  end;

  { Fallback: RTL/third-party value types the index does not cover, plus the
    'I'+uppercase interface convention. TRegEx is named explicitly because it is
    this rule's single most common false positive (a record constructor, four of
    twelve sampled findings) and lives in System.RegularExpressions, which a
    project index does not contain. }
  if SameText(Head, 'TRegEx') or SameText(Head, 'TMatch') or SameText(Head, 'TMatchCollection')
     or SameText(Head, 'TGUID') or SameText(Head, 'TPoint') or SameText(Head, 'TRect') then
    Exit(True);
  Result:= (Length(Head) >= 2) and (Head[1] = 'I') and CharInSet(Head[2], ['A'..'Z']);
end;

function ConstructorTransfersOwnership(const AConstructorNode: TTSNode; const ASrc: TBytes;
  const AStore: ISymbolStore; AFileId: Int64): Boolean;
var
  Ent, TypeNode, ArgsN, FirstArg: TTSNode;
  TypeName: string;
begin
  Result := False;
  if (AStore = nil) or AConstructorNode.IsNull then Exit;
  { Only the exprCall shape carries an args list (Create(Self) / Create(nil) /
    Create()); the bare exprDot shape (parameterless `TFoo.Create`) has no
    argument to inspect, so it can never be an owner-transfer. }
  if AConstructorNode.NodeType <> 'exprCall' then Exit;
  Ent := AConstructorNode.ChildByField('entity');
  if Ent.IsNull or (Ent.NodeType <> 'exprDot') then Exit;
  { The constructed type is the lhs of the `TType.Create` dot-expr; take the
    rightmost identifier segment so a qualified `Unit.TType.Create` still
    resolves the bare type name. Original-case text (NodeStr, NOT the
    lowercasing NodeText): the symbol store's exact-name lookup underlying
    IsDescendantOf is case-sensitive on the indexed declaration's casing. }
  TypeNode := Ent.ChildByField('lhs');
  if TypeNode.IsNull then Exit;
  if TypeNode.NodeType = 'exprDot' then TypeNode := TypeNode.ChildByField('rhs');
  TypeName := Trim(NodeStr(TypeNode, ASrc));
  if (TypeName = '') or (not AStore.IsDescendantOf(TypeName, 'TComponent', AFileId)) then Exit;
  ArgsN := AConstructorNode.ChildByField('args');
  if ArgsN.IsNull or (ArgsN.NamedChildCount = 0) then Exit; { no AOwner arg at all }
  FirstArg := ArgsN.NamedChild(0);
  if FirstArg.IsNull then Exit;
  { the nil-literal check IS case-insensitive (Pascal keyword) -- NodeText's
    lowercasing is correct and safe here, unlike for the type name above. }
  Result := NodeText(FirstArg, ASrc) <> 'nil';
end;

{ True for the Try-pattern: a FUNCTION whose name begins with `Try`.

  `TryXxx(const AInput; out AResult): Boolean` is a universal Delphi idiom in
  which AResult is defined ONLY when the function returns True. Leaving it
  unassigned on the False path is the contract being honoured, not a defect --
  and Delphi zero-initialises `out` parameters on entry regardless, so there is
  no uninitialised read to warn about either. All 7 `out-param-not-set` findings
  on YADF were this exact shape (`ARec`, across several TryParse* helpers).

  Name-based on purpose. The precise test would be "every path that leaves the
  parameter unassigned returns False", which needs the return VALUE tracked per
  path, not just assignment-reachability; the solver here answers the latter. The
  `Try` prefix IS the published contract for that behaviour, so it is the honest
  proxy rather than a heuristic standing in for something better.

  A `Try`-named PROCEDURE gets no exemption: with no Result there is no
  True/False contract for the caller to key off, so an unassigned `out` really is
  a defect. }
function IsTryStyleFunction(const AProc: TTSNode; const ASrc: TBytes): Boolean;
var
  Hdr, Nm: TTSNode;
  N      : string ;
  DotPos : Integer;
begin
  Result := False;
  if AProc.IsNull then Exit;
  Hdr := AProc.ChildByField('header');
  if Hdr.IsNull then Exit;
  Nm := Hdr.ChildByField('name');
  if Nm.IsNull then Exit;
  N := LowerCase(Trim(NodeStr(Nm, ASrc)));
  { A qualified implementation name (TFoo.TryParse) carries the class prefix. }
  DotPos := LastDelimiter('.', N);
  if DotPos > 0 then N := Copy(N, DotPos + 1, MaxInt);
  Result := (Length(N) > 3) and N.StartsWith('try');
end;

{ A single interface dereference site: the routine-var index of the base
  identifier plus the position of the dereferencing node (the `exprDot` /
  `as`-exprBinary itself, so the finding points at the member access, not the
  whole containing statement). }
type
  TIfaceDeref = record
    VarIdx: Integer;
    Row, Col: Integer;
  end;

{ Collect every interface-var dereference under ANode: an `exprDot` whose lhs
  base identifier resolves to an interface-typed routine var (`X.Member`), or
  an `as`-exprBinary (`operator` field text 'as') whose lhs base identifier
  resolves to one (`X as T`). Recurses into both sides so a chained/nested
  expression (`(X as IBar).Member`, call arguments, rhs of an assignment)
  still surfaces every base-var deref, not just the outermost one. Skips the
  member-name child of an exprDot (kDot rhs) since it is not itself a var read.
  Does not treat a bare identifier reference (a plain copy `Y := X`) as a
  dereference -- callers only see explicit exprDot/`as` nodes here.

  Sequencing within `and`/`or` chains: Delphi short-circuit evaluates left to
  right, so the common `Supports(Intf, IFoo, V) and V.Method` idiom assigns V
  (a call-arg def, see CollectReadsAndCallDefs) BEFORE the rhs dereferences it,
  even though both operands are one AST node / one CFG item. ALocallyAssigned
  accumulates such intra-item defs (identifiers whose text names a var made
  Must-assigned by an earlier operand in the SAME `and`/`or` chain) so the rhs
  walk does not re-flag them; it does not touch the caller's real May/Must
  arrays -- it is a same-item, left-to-right refinement only. }
procedure CollectInterfaceDerefs(const ANode: TTSNode; const ASrc: TBytes;
  AVars: TRoutineVarTable; const AStore: ISymbolStore; AFileId: Int64; AAcc: TList<TIfaceDeref>);
var
  LocallyAssigned: TList<Integer>;

  { Vars this subtree assigns via a call argument (e.g. Supports(.., V)) -- used
    to seed sequencing for the NEXT operand of an enclosing and/or chain. }
  procedure CollectLocalCallDefs(const N: TTSNode);
  var Reads, CallDefs: TList<Integer>; K: Integer;
  begin
    Reads := TList<Integer>.Create; CallDefs := TList<Integer>.Create;
    try
      CollectReadsAndCallDefs(N, ASrc, AVars, Reads, CallDefs);
      for K := 0 to CallDefs.Count - 1 do
        if LocallyAssigned.IndexOf(CallDefs[K]) < 0 then LocallyAssigned.Add(CallDefs[K]);
    finally
      Reads.Free; CallDefs.Free;
    end;
  end;

  procedure Walk(const N: TTSNode);
  var
    I, VarIdx: Integer; Op, L, R: TTSNode; D: TIfaceDeref; OpText: string;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'exprDot' then
    begin
      L := N.ChildByField('lhs');
      VarIdx := LeftmostBaseVar(L, ASrc, AVars);
      if (VarIdx >= 0) and (LocallyAssigned.IndexOf(VarIdx) < 0)
         and IsInterfaceType(AVars.Get(VarIdx).TypeText, AStore, AFileId) then
      begin
        D.VarIdx := VarIdx;
        D.Row := Integer(N.StartPoint.Row) + 1;
        D.Col := Integer(N.StartPoint.Column) + 1;
        AAcc.Add(D);
      end;
      Walk(L); { the lhs may itself contain other derefs / calls }
      Exit; { skip rhs: it's the member name, not a var read }
    end;
    if N.NodeType = 'exprBinary' then
    begin
      Op := N.ChildByField('operator');
      OpText := '';
      if not Op.IsNull then OpText := LowerCase(Trim(NodeStr(Op, ASrc)));
      if OpText = 'as' then
      begin
        L := N.ChildByField('lhs');
        VarIdx := LeftmostBaseVar(L, ASrc, AVars);
        if (VarIdx >= 0) and (LocallyAssigned.IndexOf(VarIdx) < 0)
           and IsInterfaceType(AVars.Get(VarIdx).TypeText, AStore, AFileId) then
        begin
          D.VarIdx := VarIdx;
          D.Row := Integer(N.StartPoint.Row) + 1;
          D.Col := Integer(N.StartPoint.Column) + 1;
          AAcc.Add(D);
        end;
        Walk(L);
        Exit; { rhs is a type reference, not a var read }
      end;
      if (OpText = 'and') or (OpText = 'or') then
      begin
        L := N.ChildByField('lhs');
        R := N.ChildByField('rhs');
        Walk(L);
        CollectLocalCallDefs(L); { seed rhs sequencing: Supports(.., V) and V.Method }
        Walk(R);
        Exit;
      end;
    end;
    for I := 0 to N.NamedChildCount - 1 do Walk(N.NamedChild(I));
  end;

begin
  LocallyAssigned := TList<Integer>.Create;
  try
    Walk(ANode);
  finally
    LocallyAssigned.Free;
  end;
end;

{ ===== interprocedural object-leak: callee-ownership helpers ===== }

{ Lowercased leftmost-identifier text of an expression (x / x.f / x[i] -> x). }
function BaseIdentText(const N: TTSNode; const ASrc: TBytes): string;
var Cur, Nxt: TTSNode; G: Integer;
begin
  Result := ''; Cur := N; G := 0;
  while (not Cur.IsNull) and (G < 32) do
  begin
    Inc(G);
    if Cur.NodeType = 'identifier' then Exit(LowerCase(Trim(NodeStr(Cur, ASrc))));
    Nxt := Cur.ChildByField('lhs');
    if Nxt.IsNull then Nxt := Cur.ChildByField('entity');
    if Nxt.IsNull and (Cur.NamedChildCount > 0) then Nxt := Cur.NamedChild(0);
    if Nxt.IsNull then Exit('');
    Cur := Nxt;
  end;
end;

{ True if the lowercased identifier AName appears anywhere in N. }
function ExprMentionsIdent(const N: TTSNode; const AName: string; const ASrc: TBytes): Boolean;
var I: Integer;
begin
  Result := False;
  if N.IsNull then Exit;
  if (N.NodeType = 'identifier') and (LowerCase(Trim(NodeStr(N, ASrc))) = AName) then Exit(True);
  for I := 0 to N.NamedChildCount - 1 do
    if ExprMentionsIdent(N.NamedChild(I), AName, ASrc) then Exit(True);
end;

{ The lowercased name of the AArgIdx-th parameter (flattening multi-name declArgs). }
function ParamNameAtIndex(const ADefProc: TTSNode; AArgIdx: Integer; const ASrc: TBytes): string;
var Hdr, Args, DA, NameId: TTSNode; I, J, Idx: Integer;
begin
  Result := '';
  Hdr := ADefProc.ChildByField('header');
  if Hdr.IsNull then Exit;
  Args := Hdr.ChildByField('args');
  if Args.IsNull then Exit;
  Idx := 0;
  for I := 0 to Args.NamedChildCount - 1 do
  begin
    DA := Args.NamedChild(I);
    if DA.NodeType <> 'declArg' then Continue;
    for J := 0 to DA.NamedChildCount - 1 do
    begin
      NameId := DA.NamedChild(J);
      if NameId.NodeType = 'identifier' then
      begin
        if Idx = AArgIdx then Exit(LowerCase(Trim(NodeStr(NameId, ASrc))));
        Inc(Idx);
      end;
    end;
  end;
end;

{ Find the implementation defProc named AName whose body spans AImplStartLine
  (falls back to the first same-named defProc). }
function FindCalleeDefProc(const ARoot: TTSNode; const AName: string;
  AImplStartLine: Integer; const ASrc: TBytes): TTSNode;
var Procs: TArray<TTSNode>; I, SR, ER: Integer; Hdr, Nm, Fallback: TTSNode;
begin
  Result := Default(TTSNode); Fallback := Default(TTSNode);
  Procs := CfgFindProcs(ARoot);
  for I := 0 to High(Procs) do
  begin
    Hdr := Procs[I].ChildByField('header');
    if Hdr.IsNull then Continue;
    Nm := Hdr.ChildByField('name');
    if Nm.IsNull or (LowerCase(Trim(NodeStr(Nm, ASrc))) <> LowerCase(AName)) then Continue;
    if Fallback.IsNull then Fallback := Procs[I];
    SR := Integer(Procs[I].StartPoint.Row) + 1; ER := Integer(Procs[I].EndPoint.Row) + 1;
    if (AImplStartLine >= SR) and (AImplStartLine <= ER) then Exit(Procs[I]);
  end;
  Result := Fallback;
end;

{ True ONLY when param APName is used purely as a read/receiver in the callee
  body -- never freed, never passed as a call argument, never on an assignment
  rhs (aliased/stored). Such a callee clearly does NOT take ownership. }
function ParamClearlyNonOwning(const ADefProc: TTSNode; const APName: string; const ASrc: TBytes): Boolean;
var Body: TTSNode; Bad: Boolean;
  procedure Walk(const N: TTSNode);
  var I: Integer; Args, Arg, Rhs: TTSNode; M: string;
  begin
    if N.IsNull or Bad then Exit;
    if N.NodeType = 'exprDot' then
    begin
      M := LowerCase(Trim(NodeStr(N.ChildByField('rhs'), ASrc)));
      if ((M = 'free') or (M = 'disposeof'))
         and (BaseIdentText(N.ChildByField('lhs'), ASrc) = APName) then
      begin Bad := True; Exit; end;
    end;
    if N.NodeType = 'exprCall' then
    begin
      Args := N.ChildByField('args');
      if not Args.IsNull then
        for I := 0 to Args.NamedChildCount - 1 do
        begin
          Arg := Args.NamedChild(I);
          if BaseIdentText(Arg, ASrc) = APName then begin Bad := True; Exit; end;
        end;
    end;
    if N.NodeType = 'assignment' then
    begin
      Rhs := N.ChildByField('rhs');
      if ExprMentionsIdent(Rhs, APName, ASrc) then begin Bad := True; Exit; end;
    end;
    for I := 0 to N.NamedChildCount - 1 do Walk(N.NamedChild(I));
  end;
begin
  Bad := False;
  Body := ADefProc.ChildByField('body');
  Walk(Body);
  Result := not Bad;
end;

class function TFlowChecker.Check(const AFile: string; const AStore: ISymbolStore;
  AFileId: Int64): TArray<TLintFinding>;
var
  PF: TParsedFile;
  Findings: TList<TLintFinding>;
  Procs: TArray<TTSNode>;
  PI: Integer;
  OwnCache: TDictionary<string, Boolean>;
  OwnsOracle: TCallArgOwns;
  RecMethodDef: TRecordMethodDefPredicate;

  procedure Emit(const ARule, ASev, AMsg: string; ALine, ACol: Integer);
  var F: TLintFinding;
  begin
    F := Default(TLintFinding);
    F.RuleId := ARule; F.Severity := ASev; F.Message := AMsg; F.FilePath := AFile;
    F.StartLine := ALine; F.StartCol := ACol; F.EndLine := ALine; F.EndCol := ACol + 1;
    Findings.Add(F);
  end;

  procedure CheckRoutine(const AProc: TTSNode);
  var
    Cfg: TCfg; Vars: TRoutineVarTable; Ana: IDataFlowAnalysis<TDefAsgnVal>;
    AIn, AOut: TArray<TDefAsgnVal>; ExitVal: TDefAsgnVal;
    B, I, J, ROW, COL, Tgt, Idx, RIx: Integer; It: TCfgItem; V: TRoutineVar;
    Reads, CallDefs: TList<Integer>;
    CurMust, CurMay: TArray<Boolean>;
    Derefs: TList<TIfaceDeref>; Dr: TIfaceDeref;
    LiveAna: IDataFlowAnalysis<TArray<Boolean>>;
    LIn, LOut: TArray<TArray<Boolean>>;
    ReadAny, AsgnAny, Live: TArray<Boolean>;
    EscAna: IDataFlowAnalysis<TArray<Boolean>>;
    EIn2, EOut2: TArray<TArray<Boolean>>;
    CreateRow, CreateCol: TArray<Integer>;
    FreedAna: IDataFlowAnalysis<TFreedVal>;
    FIn, FOut: TArray<TFreedVal>;
    CurFMust, CurFMay: TArray<Boolean>;
    FreedV: Integer; FKind: TFreeKind;
  begin
    Cfg := TCfgBuilder.Build(AProc, PF.Src);
    Vars := TRoutineVarTable.Build(AProc, PF.Src);
    try
      if Cfg.Skipped or (Vars.Count = 0) then Exit;
      Ana := TDefiniteAssignment.Create(Vars, PF.Src, RecMethodDef);
      if not TDataFlowSolver<TDefAsgnVal>.Solve(Cfg, Ana, AIn, AOut) then Exit;

      Reads := TList<Integer>.Create; CallDefs := TList<Integer>.Create;
      Derefs := TList<TIfaceDeref>.Create;
      try
        { ---- used-before-assignment: per-item replay of must/may within a block ---- }
        for B := 0 to Cfg.BlockCount - 1 do
        begin
          CurMust := Copy(AIn[B].Must); CurMay := Copy(AIn[B].May);
          { synthetic entry defs (foreach iterator) }
          for J := 0 to High(Cfg.Blocks[B].EntryDefs) do
          begin
            Idx := Vars.IndexOf(Cfg.Blocks[B].EntryDefs[J]);
            if Idx >= 0 then begin CurMust[Idx] := True; CurMay[Idx] := True; end;
          end;
          for I := 0 to Cfg.Blocks[B].Items.Count - 1 do
          begin
            It := Cfg.Blocks[B].Items[I];
            Reads.Clear; CallDefs.Clear;
            if It.Node.NodeType = 'assignment' then
              CollectReadsAndCallDefs(It.Node.ChildByField('rhs'), PF.Src, Vars, Reads, CallDefs, RecMethodDef)
            else
              CollectReadsAndCallDefs(It.Node, PF.Src, Vars, Reads, CallDefs, RecMethodDef);
            { flag reads of unmanaged locals not yet must-assigned (skip opaque with-bodies) }
            if not It.Opaque then
              for J := 0 to Reads.Count - 1 do
              begin
                RIx := Reads[J];
                V := Vars.Get(RIx);
                if V.Kind <> vkLocal then Continue;
                if IsManagedType(V.TypeText, AStore, AFileId) then Continue;
                if not CurMust[RIx] then
                begin
                  ROW := Integer(It.Node.StartPoint.Row) + 1;
                  COL := Integer(It.Node.StartPoint.Column) + 1;
                  if CurMay[RIx] then
                    Emit('used-before-assignment', 'info',
                      Format('Local "%s" may be used before it is assigned.', [V.Name]), ROW, COL)
                  else
                    Emit('used-before-assignment', 'warning',
                      Format('Local "%s" is used before it is assigned.', [V.Name]), ROW, COL);
                end;
              end;
            { ---- not-assigned-interface: interface-var dereferences (exprDot /
              `as`) not yet must-assigned at this point. Interfaces are managed
              (IsManagedType skips them above), so this fills that gap on the SAME
              replay state, before it is advanced past this item's own defs. Scans
              the whole item (both the assignment's rhs AND lhs, since a partial
              write `V.Prop := x` still dereferences V's base before the store). }
            if not It.Opaque then
            begin
              Derefs.Clear;
              CollectInterfaceDerefs(It.Node, PF.Src, Vars, AStore, AFileId, Derefs);
              for J := 0 to Derefs.Count - 1 do
              begin
                Dr := Derefs[J];
                V := Vars.Get(Dr.VarIdx);
                if V.Kind <> vkLocal then Continue;
                if not CurMust[Dr.VarIdx] then
                begin
                  if CurMay[Dr.VarIdx] then
                    Emit('not-assigned-interface', 'info',
                      Format('Interface variable "%s" may be used before it is assigned (nil dereference).', [V.Name]),
                      Dr.Row, Dr.Col)
                  else
                    Emit('not-assigned-interface', 'warning',
                      Format('Interface variable "%s" is used before it is assigned (nil dereference).', [V.Name]),
                      Dr.Row, Dr.Col);
                end;
              end;
            end;
            { advance must/may by this item's defs (reads already handled);
              a call arg / @x is treated as assigned (callee may be a var/out sink) }
            for J := 0 to CallDefs.Count - 1 do begin CurMust[CallDefs[J]] := True; CurMay[CallDefs[J]] := True; end;
            if It.Node.NodeType = 'assignment' then
            begin
              Tgt := AssignmentBaseIndex(It.Node, PF.Src, Vars);
              if Tgt >= 0 then begin CurMust[Tgt] := True; CurMay[Tgt] := True; end;
            end
            else if (It.Node.NodeType = 'exprCall')
                    and (NodeText(It.Node.ChildByField('entity'), PF.Src) = 'exit') then
            begin
              Idx := Vars.IndexOf('result');
              if Idx >= 0 then begin CurMust[Idx] := True; CurMay[Idx] := True; end;
            end;
          end;
        end;

        { ---- double-free: per-item replay of the freed/dangling must/may
          state within a block. Mirrors the used-before-assignment replay
          above but on the TFreedState lattice: at each free site (raw .Free/
          .DisposeOf OR FreeAndNil), check the IN-state BEFORE advancing --
          if the var may already be dangling here, this free is itself a
          double-free (freeing an already-dangling pointer, whichever kind of
          free it is). Then advance the state per the free's own kind. }
        FreedAna := TFreedState.Create(Vars, PF.Src);
        if TDataFlowSolver<TFreedVal>.Solve(Cfg, FreedAna, FIn, FOut) then
        begin
          for B := 0 to Cfg.BlockCount - 1 do
          begin
            CurFMust := Copy(FIn[B].Must); CurFMay := Copy(FIn[B].May);
            for I := 0 to Cfg.Blocks[B].Items.Count - 1 do
            begin
              It := Cfg.Blocks[B].Items[I];
              if It.Opaque then Continue; { with-body: conservative, skip }
              FreedV := DetectFreedVarKind(It.Node, PF.Src, Vars, FKind);
              if FreedV >= 0 then
              begin
                V := Vars.Get(FreedV);
                if CurFMay[FreedV] then
                begin
                  ROW := Integer(It.Node.StartPoint.Row) + 1;
                  COL := Integer(It.Node.StartPoint.Column) + 1;
                  if CurFMust[FreedV] then
                    Emit('double-free', 'warning',
                      Format('Object "%s" is freed twice (double free) -- reassign or FreeAndNil after the first Free.', [V.Name]),
                      ROW, COL)
                  else
                    Emit('double-free', 'info',
                      Format('Object "%s" may be freed twice (double free) -- reassign or FreeAndNil after the first Free.', [V.Name]),
                      ROW, COL);
                end;
                case FKind of
                  fkRawFree: begin CurFMust[FreedV] := True;  CurFMay[FreedV] := True;  end;
                  fkNiling:  begin CurFMust[FreedV] := False; CurFMay[FreedV] := False; end;
                end;
                Continue;
              end;
              if It.Node.NodeType = 'assignment' then
              begin
                Tgt := AssignmentTargetIndex(It.Node, PF.Src, Vars);
                if Tgt >= 0 then begin CurFMust[Tgt] := False; CurFMay[Tgt] := False; end;
              end;
            end;
          end;
        end;

        ExitVal := AIn[Cfg.ExitIdx];

        { ---- function-result-not-set ---- }
        Idx := Vars.IndexOf('result');
        if Idx >= 0 then
        begin
          V := Vars.Get(Idx);
          if (not ExitVal.Must[Idx]) and not IsManagedType(V.TypeText, AStore, AFileId) then
          begin
            ROW := Integer(AProc.ChildByField('header').StartPoint.Row) + 1;
            COL := Integer(AProc.ChildByField('header').StartPoint.Column) + 1;
            if ExitVal.May[Idx] then
              Emit('function-result-not-set', 'info',
                'Function Result is not assigned on every path.', ROW, COL)
            else
              Emit('function-result-not-set', 'warning',
                'Function Result is never assigned.', ROW, COL);
          end;
        end;

        { ---- out-param-not-set ---- }
        { The Try-pattern opts out: see IsTryStyleFunction. Requiring a Result
          here is what makes it "function", so a Try-named PROCEDURE is still
          checked -- it has no True/False contract to justify the omission. }
        var TryFn: Boolean := (Vars.IndexOf('result') >= 0) and IsTryStyleFunction(AProc, PF.Src);
        for I := 0 to Vars.Count - 1 do
        begin
          V := Vars.Get(I);
          if (V.Kind = vkParamOut) and (not ExitVal.Must[I]) and (not TryFn) then
          begin
            if ExitVal.May[I] then
              Emit('out-param-not-set', 'info',
                Format('Out parameter "%s" is not assigned on every path.', [V.Name]),
                V.DeclLine, V.DeclCol)
            else
              Emit('out-param-not-set', 'warning',
                Format('Out parameter "%s" is not assigned.', [V.Name]),
                V.DeclLine, V.DeclCol);
          end;
        end;

        { ============ liveness checks: overwrite-before-read + write-only-local ============ }
        LiveAna := TLiveness.Create(Vars, PF.Src);
        if TDataFlowSolver<TArray<Boolean>>.Solve(Cfg, LiveAna, LIn, LOut) then
        begin
          SetLength(ReadAny, Vars.Count); SetLength(AsgnAny, Vars.Count);
          for I := 0 to Vars.Count - 1 do begin ReadAny[I] := False; AsgnAny[I] := False; end;
          { precompute read-anywhere / assigned-anywhere over all blocks }
          for B := 0 to Cfg.BlockCount - 1 do
            for I := 0 to Cfg.Blocks[B].Items.Count - 1 do
            begin
              It := Cfg.Blocks[B].Items[I];
              Reads.Clear; CallDefs.Clear;
              if It.Node.NodeType = 'assignment' then
              begin
                CollectReadsAndCallDefs(It.Node.ChildByField('rhs'), PF.Src, Vars, Reads, CallDefs);
                Tgt := AssignmentTargetIndex(It.Node, PF.Src, Vars);
                if Tgt >= 0 then AsgnAny[Tgt] := True
                else
                begin
                  { partial write (a[i]:= / x.f:=): assigns AND reads the base }
                  Idx := AssignmentBaseIndex(It.Node, PF.Src, Vars);
                  if Idx >= 0 then begin AsgnAny[Idx] := True; ReadAny[Idx] := True; end;
                  CollectReadsAndCallDefs(It.Node.ChildByField('lhs'), PF.Src, Vars, Reads, CallDefs);
                end;
              end
              else
                CollectReadsAndCallDefs(It.Node, PF.Src, Vars, Reads, CallDefs);
              for J := 0 to Reads.Count - 1 do ReadAny[Reads[J]] := True;
              for J := 0 to CallDefs.Count - 1 do ReadAny[CallDefs[J]] := True; { call arg = use }
            end;

          { overwrite-before-read: a whole-var store to a local not live afterwards,
            where the local IS read somewhere (else it is write-only, reported below) }
          for B := 0 to Cfg.BlockCount - 1 do
          begin
            Live := Copy(LOut[B]);
            for I := Cfg.Blocks[B].Items.Count - 1 downto 0 do
            begin
              It := Cfg.Blocks[B].Items[I];
              if It.Opaque then
              begin
                for J := 0 to Vars.Count - 1 do
                  if Vars.Get(J).Kind = vkLocal then Live[J] := True;
                Continue;
              end;
              if It.Node.NodeType = 'assignment' then
              begin
                Tgt := AssignmentTargetIndex(It.Node, PF.Src, Vars); { whole-var only }
                if (Tgt >= 0) and (Vars.Get(Tgt).Kind = vkLocal)
                   and ReadAny[Tgt] and (not Live[Tgt]) then
                begin
                  ROW := Integer(It.Node.StartPoint.Row) + 1;
                  COL := Integer(It.Node.StartPoint.Column) + 1;
                  Emit('overwrite-before-read', 'info',
                    Format('Assignment to "%s" is overwritten before it is read (dead store).',
                      [Vars.Get(Tgt).Name]), ROW, COL);
                end;
                { backward transfer for this item (mirror TLiveness.Transfer) }
                Reads.Clear; CallDefs.Clear;
                if Tgt >= 0 then Live[Tgt] := False;
                CollectReadsAndCallDefs(It.Node.ChildByField('rhs'), PF.Src, Vars, Reads, CallDefs);
                for J := 0 to Reads.Count - 1 do Live[Reads[J]] := True;
                for J := 0 to CallDefs.Count - 1 do Live[CallDefs[J]] := True; { rhs call args are uses }
                if Tgt < 0 then
                begin
                  Reads.Clear; CallDefs.Clear;
                  CollectReadsAndCallDefs(It.Node.ChildByField('lhs'), PF.Src, Vars, Reads, CallDefs);
                  for J := 0 to Reads.Count - 1 do Live[Reads[J]] := True;
                  for J := 0 to CallDefs.Count - 1 do Live[CallDefs[J]] := True;
                end;
              end
              else
              begin
                Reads.Clear; CallDefs.Clear;
                CollectReadsAndCallDefs(It.Node, PF.Src, Vars, Reads, CallDefs);
                for J := 0 to Reads.Count - 1 do Live[Reads[J]] := True;
                for J := 0 to CallDefs.Count - 1 do Live[CallDefs[J]] := True;
              end;
            end;
          end;

          { write-only-local: a local assigned at least once but read nowhere }
          for I := 0 to Vars.Count - 1 do
          begin
            V := Vars.Get(I);
            { captured locals are read inside a nested routine/lambda -> not write-only }
            if (V.Kind = vkLocal) and AsgnAny[I] and (not ReadAny[I]) and (not V.Captured) then
              Emit('write-only-local', 'info',
                Format('Local "%s" is assigned but never read.', [V.Name]),
                V.DeclLine, V.DeclCol);
          end;

          { ============ split-variable (refactoring, OFF): a local reused for two
            UNRELATED purposes -- it has >=2 DISJOINT def-use lifetimes. Distinct
            from overwrite-before-read (a dead store whose value is NEVER read):
            split-variable requires the EARLIER lifetime to be def+read (its value
            IS consumed) AND the later whole-var def to start a SECOND live range
            whose value is also read. Two genuinely-used ranges share one local.

            Restricted to LINEAR routines (no branch/merge) to keep it low-FP and
            sound without a per-path forward lattice: a branch could make the two
            "lifetimes" mutually exclusive alternatives (one variable, one purpose
            per path) rather than a real sequential reuse. On any branching routine
            we bail (emit nothing) -- conservative, never a false positive. }
          if Cfg.BlockCount > 0 then
          begin
            var Linear := True;
            for B := 0 to Cfg.BlockCount - 1 do
              if (Cfg.Blocks[B].Succ.Count > 1) or (Cfg.Blocks[B].Pred.Count > 1) then
              begin Linear := False; Break; end;
            if Linear then
            begin
              { flatten items in execution order by following the single-succ chain
                from Entry; guard against cycles (a self-loop would not be linear
                anyway, but stay safe). }
              var Flat := TList<TCfgItem>.Create;
              var ChainSeen := TList<Integer>.Create;
              try
                var Cur := Cfg.EntryIdx;
                while (Cur >= 0) and (ChainSeen.IndexOf(Cur) < 0) do
                begin
                  ChainSeen.Add(Cur);
                  for I := 0 to Cfg.Blocks[Cur].Items.Count - 1 do
                    Flat.Add(Cfg.Blocks[Cur].Items[I]);
                  if Cfg.Blocks[Cur].Succ.Count = 1 then Cur := Cfg.Blocks[Cur].Succ[0]
                  else Cur := -1;
                end;

                { LiveAfter[k][v] = local v is read on the linear tail AFTER item k
                  before being wholly redefined. Single backward sweep. }
                var LiveNow: TArray<Boolean>; SetLength(LiveNow, Vars.Count);
                for J := 0 to Vars.Count - 1 do LiveNow[J] := False;
                var LiveAfter := TList<TArray<Boolean>>.Create;
                try
                  for J := 0 to Flat.Count - 1 do LiveAfter.Add(nil);
                  for I := Flat.Count - 1 downto 0 do
                  begin
                    LiveAfter[I] := Copy(LiveNow);
                    It := Flat[I];
                    if It.Opaque then
                    begin
                      for J := 0 to Vars.Count - 1 do
                        if Vars.Get(J).Kind = vkLocal then LiveNow[J] := True;
                      Continue;
                    end;
                    Reads.Clear; CallDefs.Clear;
                    if It.Node.NodeType = 'assignment' then
                    begin
                      Tgt := AssignmentTargetIndex(It.Node, PF.Src, Vars); { whole-var only }
                      if Tgt >= 0 then LiveNow[Tgt] := False; { killed by this store }
                      CollectReadsAndCallDefs(It.Node.ChildByField('rhs'), PF.Src, Vars, Reads, CallDefs);
                      if Tgt < 0 then { partial write reads its base }
                        CollectReadsAndCallDefs(It.Node.ChildByField('lhs'), PF.Src, Vars, Reads, CallDefs);
                    end
                    else
                      CollectReadsAndCallDefs(It.Node, PF.Src, Vars, Reads, CallDefs);
                    for J := 0 to Reads.Count - 1 do LiveNow[Reads[J]] := True;
                    for J := 0 to CallDefs.Count - 1 do LiveNow[CallDefs[J]] := True;
                  end;

                  { forward sweep: ReadSinceDef[v] = v has been read since its most
                    recent whole-var def. A whole-var store to a local that has been
                    read since its last def AND whose new value is live afterwards
                    starts a second used lifetime -> split-variable. }
                  var ReadSinceDef: TArray<Boolean>; SetLength(ReadSinceDef, Vars.Count);
                  for J := 0 to Vars.Count - 1 do ReadSinceDef[J] := False;
                  for I := 0 to Flat.Count - 1 do
                  begin
                    It := Flat[I];
                    if It.Opaque then Continue;
                    Reads.Clear; CallDefs.Clear;
                    if It.Node.NodeType = 'assignment' then
                    begin
                      Tgt := AssignmentTargetIndex(It.Node, PF.Src, Vars);
                      { reads on the rhs happen BEFORE the store: mark them first }
                      CollectReadsAndCallDefs(It.Node.ChildByField('rhs'), PF.Src, Vars, Reads, CallDefs);
                      if Tgt < 0 then
                        CollectReadsAndCallDefs(It.Node.ChildByField('lhs'), PF.Src, Vars, Reads, CallDefs);
                      for J := 0 to Reads.Count - 1 do ReadSinceDef[Reads[J]] := True;
                      for J := 0 to CallDefs.Count - 1 do ReadSinceDef[CallDefs[J]] := True;
                      if (Tgt >= 0) and (Vars.Get(Tgt).Kind = vkLocal) then
                      begin
                        { this store overwrites Tgt; if a prior used lifetime exists
                          and the new value will be read, the local serves two roles }
                        if ReadSinceDef[Tgt] and LiveAfter[I][Tgt] then
                        begin
                          ROW := Integer(It.Node.StartPoint.Row) + 1;
                          COL := Integer(It.Node.StartPoint.Column) + 1;
                          Emit('split-variable', 'info',
                            Format('Local "%s" is reused for two unrelated purposes (disjoint lifetimes); split it into two variables.',
                              [Vars.Get(Tgt).Name]), ROW, COL);
                        end;
                        ReadSinceDef[Tgt] := False; { new lifetime begins }
                      end;
                    end
                    else
                    begin
                      CollectReadsAndCallDefs(It.Node, PF.Src, Vars, Reads, CallDefs);
                      for J := 0 to Reads.Count - 1 do ReadSinceDef[Reads[J]] := True;
                      for J := 0 to CallDefs.Count - 1 do ReadSinceDef[CallDefs[J]] := True;
                    end;
                  end;
                finally
                  LiveAfter.Free;
                end;
              finally
                Flat.Free; ChainSeen.Free;
              end;
            end;
          end;
        end;

        { ============ loop-var-after-loop: a `for` control var read after the loop ============ }
        for I := 0 to Cfg.ForVars.Count - 1 do
        begin
          Idx := Vars.IndexOf(Cfg.ForVars[I].VarName);
          if Idx < 0 then Continue;
          { BFS over post-loop blocks; flag the first read of the loop var before
            it is reassigned (a whole-var def). Visited set guards cycles. }
          var Q := TQueue<Integer>.Create;
          var Seen := TList<Integer>.Create;
          try
            Q.Enqueue(Cfg.ForVars[I].FollowIdx);
            while Q.Count > 0 do
            begin
              B := Q.Dequeue;
              if Seen.IndexOf(B) >= 0 then Continue;
              Seen.Add(B);
              var StopPath := False;
              for J := 0 to Cfg.Blocks[B].Items.Count - 1 do
              begin
                It := Cfg.Blocks[B].Items[J];
                if It.Opaque then Continue;
                Reads.Clear; CallDefs.Clear;
                if It.Node.NodeType = 'assignment' then
                  CollectReadsAndCallDefs(It.Node.ChildByField('rhs'), PF.Src, Vars, Reads, CallDefs)
                else
                  CollectReadsAndCallDefs(It.Node, PF.Src, Vars, Reads, CallDefs);
                if Reads.IndexOf(Idx) >= 0 then { a genuine value read of the stale counter }
                begin
                  ROW := Integer(It.Node.StartPoint.Row) + 1;
                  COL := Integer(It.Node.StartPoint.Column) + 1;
                  Emit('loop-var-after-loop', 'warning',
                    Format('Loop variable "%s" is read after the loop; its value is undefined there.',
                      [Cfg.ForVars[I].VarName]), ROW, COL);
                  StopPath := True; Break;
                end;
                { passed to a call: may be an out/var param that REASSIGNS it
                  (e.g. TryGetValue(.., counter)); FP-safe -> treat as reassigned }
                if CallDefs.IndexOf(Idx) >= 0 then begin StopPath := True; Break; end;
                if (It.Node.NodeType = 'assignment')
                   and (AssignmentTargetIndex(It.Node, PF.Src, Vars) = Idx) then
                begin StopPath := True; Break; end; { reassigned -> safe on this path }
              end;
              if not StopPath then
                for RIx := 0 to Cfg.Blocks[B].Succ.Count - 1 do
                  Q.Enqueue(Cfg.Blocks[B].Succ[RIx]);
            end;
          finally Q.Free; Seen.Free; end;
        end;

        { ============ object-leak (store-free, conservative) ============ }
        EscAna := TEscape.Create(Vars, PF.Src, OwnsOracle);
        if TDataFlowSolver<TArray<Boolean>>.Solve(Cfg, EscAna, EIn2, EOut2) then
        begin
          SetLength(CreateRow, Vars.Count); SetLength(CreateCol, Vars.Count);
          for I := 0 to Vars.Count - 1 do begin CreateRow[I] := 0; CreateCol[I] := 0; end;
          { record each local's constructor-assignment site }
          for B := 0 to Cfg.BlockCount - 1 do
            for J := 0 to Cfg.Blocks[B].Items.Count - 1 do
            begin
              It := Cfg.Blocks[B].Items[J];
              if It.Node.NodeType <> 'assignment' then Continue;
              Tgt := AssignmentTargetIndex(It.Node, PF.Src, Vars);
              if (Tgt >= 0) and (Vars.Get(Tgt).Kind = vkLocal)
                 and ExprIsConstructor(It.Node.ChildByField('rhs'), PF.Src)
                 { a TComponent descendant constructed with a non-nil AOwner
                   transfers ownership to that owner (freed on its teardown) --
                   do NOT record it as a leak candidate. }
                 and not ConstructorTransfersOwnership(It.Node.ChildByField('rhs'), PF.Src, AStore, AFileId) then
              begin
                CreateRow[Tgt] := Integer(It.Node.StartPoint.Row) + 1;
                CreateCol[Tgt] := Integer(It.Node.StartPoint.Column) + 1;
              end;
            end;
          { a created local still may-open at the routine exit -> possible leak }
          { v(2026-08-10): NARROWED BY DECLARED TYPE. Sampled 12 of this rule's
            106 findings on drag-lint's own source: ZERO were leaks. The two
            dominant shapes are not "missed frees", they are constructs where a
            leak is IMPOSSIBLE, so no amount of flow analysis could ever clear
            them and the finding was unfalsifiable:

              * A VALUE TYPE. `Rx := TRegEx.Create(...)` is a RECORD
                constructor -- nothing is heap-allocated and there is no Free to
                call. Four of the twelve were TRegEx alone.
              * AN INTERFACE. `Store: ISymbolStore := TSQLiteStore.Create(...)`
                is reference-counted by the runtime; freeing it manually would
                be the bug. Three of the twelve.

            Both are decided from the DECLARED TYPE, which the routine var table
            already carries -- no new analysis, and no chance of hiding a real
            leak, because neither shape can leak by construction. }
          for I := 0 to Vars.Count - 1 do
            if (Vars.Get(I).Kind = vkLocal) and (CreateRow[I] > 0) and EIn2[Cfg.ExitIdx][I]
               and not TypeIsRefCountedOrValue(Vars.Get(I).TypeText, AStore) then
              Emit('object-leak', 'info',
                Format('Object "%s" may be leaked: created but not freed or transferred on some path.',
                  [Vars.Get(I).Name]), CreateRow[I], CreateCol[I]);
        end;

      finally Reads.Free; CallDefs.Free; Derefs.Free; end;
    finally Cfg.Free; Vars.Free; end;
  end;

begin
  Result := nil;
  PF := TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Findings := TList<TLintFinding>.Create;
  OwnCache := TDictionary<string, Boolean>.Create;
  { Interprocedural object-leak: with a store, the escape analysis asks this oracle
    whether a callee OWNS its argument. True (owns/unknown) keeps the conservative
    escape; False (clearly non-owning unit proc) lets a real leak surface. }
  if AStore <> nil then
    OwnsOracle :=
      function(const ACalleeName: string; AArgIdx: Integer): Boolean
      var
        Key, CPath, PName: string; B, Ambig, Have: Boolean; Syms: TArray<TSymbol>;
        RSym: TSymbol; I: Integer; FId: Int64; CPF: TParsedFile; DP: TTSNode;
      begin
        Result := True; { conservative default: owns/unknown -> escape }
        Key := ACalleeName + '#' + IntToStr(AArgIdx);
        if OwnCache.TryGetValue(Key, B) then Exit(B);
        OwnCache.AddOrSetValue(Key, True); { pre-seed (guards re-entry) }
        Syms := AStore.FindSymbolsByExactName(ACalleeName);
        { resolve to a single routine: an interface forward-decl + its impl share a
          file (fine); only routines spanning DIFFERENT files are truly ambiguous. }
        Have := False; Ambig := False; FId := -1; RSym := Default(TSymbol);
        for I := 0 to High(Syms) do
          if Syms[I].Kind in [skProcedure, skFunction, skMethod] then
          begin
            if not Have then begin FId := Syms[I].FileId; RSym := Syms[I]; Have := True; end
            else if Syms[I].FileId <> FId then Ambig := True;
            if Syms[I].ImplStartLine > 0 then RSym := Syms[I]; { prefer the bodied one }
          end;
        if (not Have) or Ambig then Exit; { unresolved / cross-file -> conservative }
        CPath := AStore.GetFilePath(RSym.FileId);
        if (CPath = '') or (not TFile.Exists(CPath)) then Exit;
        CPF := TAstParseCache.Get(CPath);
        if CPF.Tree = nil then Exit;
        DP := FindCalleeDefProc(CPF.Tree.RootNode, ACalleeName, RSym.ImplStartLine, CPF.Src);
        if DP.IsNull then Exit;
        PName := ParamNameAtIndex(DP, AArgIdx, CPF.Src);
        if PName = '' then Exit;
        Result := not ParamClearlyNonOwning(DP, PName, CPF.Src); { non-owning -> False (leak) }
        OwnCache.AddOrSetValue(Key, Result);
      end
  else
    OwnsOracle := nil;
  { used-before-assignment: with a store, a method call on a RECORD local (e.g.
    `St.Reset;`) counts as a definition of that local -- the idiomatic way a
    record establishes its own initial value, since it has no constructor. Gated
    on BOTH the receiver resolving to tcRecord (IsRecordType) AND the dot's rhs
    resolving to a callable member (CanBeCallTarget) of that record type, so a
    plain field access (`St.Total`) is left as an ordinary read and a genuinely
    uninitialised record field still flags. A CLASS reference never qualifies --
    IsRecordType has no naming-convention fallback, so a store-free receiver, or
    one that resolves to anything other than tcRecord, leaves this False and a
    method call on an uninitialised class reference keeps flagging as the
    nil-dereference bug it is.

    KNOWN TRADE-OFF: CanBeCallTarget accepts ANY callable member, not only a
    mutating one -- there is no effect analysis here to tell "St.Reset" (writes
    every field) from a pure query like "St.Peek" (reads Total, writes nothing).
    So a getter called first, before any real initialiser, is ALSO (wrongly)
    treated as establishing definite assignment, and a genuine "read of garbage
    record state" would go unreported. Accepted deliberately: the alternative
    is the 24 false positives this fix removes from YADF alone, and narrowing
    to "provably mutates Self" is not information this analysis has. }
  if AStore <> nil then
    RecMethodDef :=
      function(const ATypeText, AMemberName: string): Boolean
      var RecSym, MemSym: TSymbol;
      begin
        Result := False;
        if not IsRecordType(ATypeText, AStore, AFileId) then Exit;
        RecSym := AStore.ResolveTypeNameToClass(Trim(ATypeText), AFileId);
        if RecSym.Id <= 0 then Exit;
        { records have no ancestry (no class heritage), so a direct child lookup
          is the whole answer -- unlike ResolveMemberOnType's class ancestor
          climb, which does not apply here. }
        MemSym := AStore.FindChildSymbolByName(RecSym.Id, AMemberName);
        if MemSym.Id <= 0 then Exit;
        Result := CanBeCallTarget(MemSym.Kind);
      end
  else
    RecMethodDef := nil;
  try
    Procs := CfgFindProcs(PF.Tree.RootNode);
    for PI := 0 to High(Procs) do CheckRoutine(Procs[PI]);
    Result := Findings.ToArray;
  finally
    Findings.Free;
    OwnCache.Free;
  end;
end;

end.
