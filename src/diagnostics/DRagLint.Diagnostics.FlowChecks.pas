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
    /// interprocedural object-leak refinement. ALibStore (optional, nil-safe)
    /// supplements AStore for library-only symbols (e.g., VCL TComponent)
    /// when checking ownership transfer.</summary>
    /// <param name="AFile">Path to the .pas/.inc file.</param>
    /// <param name="AStore">Optional symbol store; nil on the bare lint path.</param>
    /// <param name="AFileId">File id within AStore (0 when no store).</param>
    /// <param name="ALibStore">Optional library symbol store for cross-DB lookups; nil disables.</param>
    /// <returns>All flow findings for the file.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoCheckAst (DRagLint.CLI.pas), DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
    /// <para>Calls: ApplyEntryDefs, AssignedUnderSameGuard, AssignmentBaseIndex, AssignmentTargetIndex, CollectAndOrLeftDefs, CollectInterfaceDerefs, CollectReadsAndCallDefs, CollectThenGuards, ConstructedTypeText, ConstructorTransfersOwnership (+28 more)</para>
    /// <para>Returns: nil; True; not ParamClearlyNonOwning(DP, PName, CPF.Src); False; CanBeCallTarget(MemSym.Kind); Findings.ToArray</para>
    /// <para>Complexity: 21 (cyclomatic, outer body), 712 lines (full implementation)</para>
    /// <para>Touches: file system</para>
    /// <seealso cref="DRagLint.Analysis.Cfg.CfgFindProcs"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindChildSymbolByName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ResolveTypeNameToClass"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Check(const AFile: string; const AStore: ISymbolStore = nil;
      AFileId: Int64 = 0; const ALibStore: ISymbolStore = nil): TArray<TLintFinding>;
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
  { A STATIC array is managed iff its ELEMENT type is. `array[0..2] of string`
    is zero-initialised by the compiler exactly as a bare string local is, so
    reading an element before any write yields '' -- defined behaviour, and not
    something used-before-assignment can describe as a defect.

    The dynamic-array test above misses it: 'array of' is not a substring of
    'array[0..2] of'. That gap produced all three surviving
    used-before-assignment findings on DataCopy (uZeissRoutines LRestore/LBackup,
    both `array[0..2] of string`), and the rule was already declining to report
    the ANALOGOUS scalar case -- a bare `string` local, and even an uninitialised
    `Integer` -- so reporting the array was inconsistent with its own bar.

    Recurse rather than assume: `array[0..2] of Integer` is NOT zero-initialised
    on the stack and stays reportable. Split on the LAST ' of ' so nested
    `array[..] of array[..] of string` resolves to the innermost element.
    See docs\INBOX-used-before-assignment-array-local-never-counted-as-defined.md. }
  if T.StartsWith('array') then
  begin
    var OfPos: Integer := T.LastIndexOf(' of ');
    if OfPos > 0 then
      Exit(IsManagedType(Trim(Copy(T, OfPos + 5, MaxInt)), AStore, AFileId));
  end;
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

{ The type a constructor expression names, bare: `TRegEx.Create(..)` -> TRegEx,
  `System.RegularExpressions.TRegEx.Create(..)` -> TRegEx. Empty when ANode is
  not one of the two constructor shapes ExprIsConstructor accepts.

  This exists ONLY to give TypeIsRefCountedOrValue something to decide on for an
  inline `var X := T.Create(..)`, which carries no declared type. It is not a
  general type inference and must not be used as one: it reports what the source
  WROTE at the call, which for a class-reference variable or a virtual
  constructor is not the runtime type. That is safe here because the only
  question asked of it is "is this a record/interface, which cannot leak" -- a
  question about the named type itself. }
function ConstructedTypeText(const ANode: TTSNode; const ASrc: TBytes): string;
var Recv, Ent: TTSNode; P: Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  Recv:= Default(TTSNode);
  if ANode.NodeType = 'exprDot' then
    Recv:= ANode.ChildByField('lhs')
  else if ANode.NodeType = 'exprCall' then
  begin
    Ent:= ANode.ChildByField('entity');
    if (not Ent.IsNull) and (Ent.NodeType = 'exprDot') then Recv:= Ent.ChildByField('lhs');
  end;
  if Recv.IsNull then Exit;
  Result:= Trim(NodeStr(Recv, ASrc));
  { keep the last dotted segment -- the unit qualification is not the type }
  P:= LastDelimiter('.', Result);
  if P > 0 then Result:= Trim(Copy(Result, P + 1, MaxInt));
end;

{ True when the assignment's TARGET variable also appears among the constructor
  call's arguments -- `Cur := TNode.Create(Cur)`. See the call site for why that
  is a structure-linking idiom rather than an owned allocation. Reuses
  CollectCallArgs so this agrees with the escape lattice by construction instead
  of by a second parse of the same node. }
function SelfLinkedConstruction(const AAssignNode: TTSNode; const ASrc: TBytes;
  const AVars: TRoutineVarTable; ATargetIdx: Integer): Boolean;
var
  CA: TCallArgRef;
begin
  Result := False;
  if ATargetIdx < 0 then Exit;
  for CA in CollectCallArgs(AAssignNode, ASrc, AVars) do
    if CA.VarIdx = ATargetIdx then Exit(True);
end;

function ConstructorTransfersOwnership(const AConstructorNode: TTSNode; const ASrc: TBytes;
  const AStore: ISymbolStore; AFileId: Int64; const ALibStore: ISymbolStore = nil): Boolean;
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
  if TypeName = '' then Exit;
  { Is it a TComponent? Ask the PROJECT store first, then the LIBRARY store.

    Both are needed, and neither alone is enough. A project-local component
    (`TMyPanel = class(TPanel)`) is only in the project index; TTimer, TButton and
    every other stock VCL component is only in the library index. Asking the
    project store alone -- which is what this did until 2026-08-13 -- meant
    IsDescendantOf returned False for the entire VCL, ownership was never
    detected, and `Timer := TTimer.Create(Self)` was reported as a leak. That is
    the owner's two-DB model in miniature: the question needs both databases and
    this call site only had one.

    AFileId is meaningful only for the project store (it scopes the lookup to the
    file's own resolution context); the library store is asked with 0, since a
    project file id names nothing in it. }
  if not (AStore.IsDescendantOf(TypeName, 'TComponent', AFileId)
          or ((ALibStore <> nil) and ALibStore.IsDescendantOf(TypeName, 'TComponent', 0))) then Exit;
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

{ True when S contains AWhat at an IDENTIFIER BOUNDARY -- 'l.free' must not be
  found inside 'xl.free'. Cheap left-boundary check; the right side is already
  pinned by the '.' or '(' the caller appends. }
{ Removes whitespace that merely pads punctuation, so a literal match for
  `x.free` survives the column-aligned `x  .Free` style used throughout this
  codebase. Whitespace is dropped only when the run abuts a '.' on either side,
  or directly follows '(' -- never between two identifier characters, so no two
  tokens can be merged into one. See FreedInFinallyBlock for the measurement. }
function TightenPunct(const S: string): string;
var
  I, J   : Integer      ;
  B      : TStringBuilder;
  PrevCh : Char         ;
  NextCh : Char         ;
begin
  B:= TStringBuilder.Create;
  try
    I:= 1;
    while I <= Length(S) do
    begin
      if CharInSet(S[I], [' ', #9]) then
      begin
        J:= I;
        while (J <= Length(S)) and CharInSet(S[J], [' ', #9]) do Inc(J);
        PrevCh:= #0;
        if B.Length > 0 then PrevCh:= B.Chars[B.Length - 1];
        NextCh:= #0;
        if J <= Length(S) then NextCh:= S[J];
        { Drop the run only where it is pure padding around punctuation. }
        if (NextCh <> '.') and (PrevCh <> '.') and (PrevCh <> '(') then
          B.Append(' ');
        I:= J;
      end
      else
      begin
        B.Append(S[I]);
        Inc(I);
      end;
    end;
    Result:= B.ToString;
  finally
    B.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  SAME-PREDICATE SUPPRESSION for used-before-assignment.

  The narrow, deliberately-minimal case (INBOX-used-before-assignment...):

      if Profiled then TMark := TStopwatch.GetTimeStamp;
      ...
      if Profiled then Inc(AccRes, TStopwatch.GetTimeStamp - TMark);

  The read of TMark is guarded by the SAME predicate that guarded its
  assignment, so it cannot execute unassigned -- but the lattice carries no
  predicate at all (TDefAsgnVal is just Must/May bit arrays) and the CFG models
  branching purely as edges, so the correlation is invisible to the analysis.
  This is therefore a syntactic AST check at EMISSION time, not a lattice
  extension; the latter would be path-sensitivity.

  SCOPE, AND WHY IT IS THIS SMALL. Only a BARE LOCAL IDENTIFIER predicate is
  honoured, and only when the assignment sits under a textually identical one.
  That is the measured shape and nothing more. Deliberately NOT handled:

    * witness-flag pairs (`if C then begin X := ..; HaveX := True end;
      if HaveX then Use(X)`) -- the predicates differ, so proving that one
      implies the other needs a pairing argument, and ANY GAP in that argument
      SUPPRESSES A TRUE POSITIVE. Wrong failure direction for this rule.
    * `if not F` forms, else-arms, case, and loop-crossing guards.
    * arrays/records only ever element-written -- a granularity problem that no
      predicate check can reach.

  A compound or call-bearing predicate is rejected outright: `if Ready(X) then`
  twice is not a guarantee that the second call returns what the first did.
  --------------------------------------------------------------------------- }

{ The bare local identifier a THEN-branch is guarded by, '' for anything else.
  Anything with a call, a dot, an index or an operator is refused -- only a
  simple identifier can be compared textually and still mean the same thing at
  two different points in the routine. }
function ThenGuardName(const AIf, AChild: TTSNode; const ASrc: TBytes): string;
var
  I, CondIx, ThenIx, ElseIx: Integer;
  C, Cond                  : TTSNode;
begin
  Result := '';
  if AIf.IsNull then Exit;
  if (AIf.NodeType <> 'if') and (AIf.NodeType <> 'exprIf') then Exit;
  { Children are POSITIONAL (kIf, cond, kThen, then, kElse, else) -- exprIf
    exposes no 'then'/'else' fields, which is why this indexes rather than
    calling ChildByField. Same lesson as MaxNest in AstChecks. }
  CondIx := -1; ThenIx := -1; ElseIx := -1;
  for I := 0 to AIf.ChildCount - 1 do
  begin
    C := AIf.Child(I);
    if      C.NodeType = 'kIf'   then CondIx := I + 1
    else if C.NodeType = 'kThen' then ThenIx := I + 1
    else if C.NodeType = 'kElse' then ElseIx := I + 1;
  end;
  if (CondIx < 0) or (ThenIx < 0) or (CondIx >= AIf.ChildCount) or (ThenIx >= AIf.ChildCount) then Exit;
  { The child must be the THEN arm. An else-arm read is guarded by the NEGATION
    and must never match. }
  if AIf.Child(ThenIx).StartByte <> AChild.StartByte then
  begin
    { AChild may be nested deeper than the arm itself -- compare by containment. }
    if (AChild.StartByte < AIf.Child(ThenIx).StartByte) or
       (AChild.EndByte   > AIf.Child(ThenIx).EndByte  ) then Exit;
  end;
  if (ElseIx >= 0) and (ElseIx < AIf.ChildCount) then
    if (AChild.StartByte >= AIf.Child(ElseIx).StartByte) and
       (AChild.EndByte   <= AIf.Child(ElseIx).EndByte  ) then Exit;
  Cond := AIf.Child(CondIx);
  if Cond.IsNull then Exit;
  if Cond.NodeType <> 'identifier' then Exit; { compound / call / not -> refuse }
  Result := LowerCase(Trim(NodeStr(Cond, ASrc)));
end;

{ Collects the bare-identifier THEN-guards governing ANode, innermost first,
  stopping at ARoutine. }
procedure CollectThenGuards(const ANode, ARoutine: TTSNode; const ASrc: TBytes;
  AAcc: TList<string>);
var
  Cur, Par: TTSNode;
  G       : string ;
begin
  Cur := ANode;
  while True do
  begin
    Par := Cur.Parent;
    if Par.IsNull then Break;
    G := ThenGuardName(Par, Cur, ASrc);
    if G <> '' then AAcc.Add(G);
    if Par.StartByte = ARoutine.StartByte then Break;
    Cur := Par;
  end;
end;

{ True when AName is assigned anywhere in the byte range (AFrom, ATo). Used to
  refuse the suppression when the predicate variable itself is rewritten between
  the guarded assignment and the guarded read -- the one way two textually equal
  predicates can denote different values. }
function AssignedInRange(const ANode: TTSNode; const ASrc: TBytes;
  const AName: string; AFrom, ATo: Integer): Boolean;
var
  I  : Integer;
  Lhs: TTSNode;
begin
  Result := False;
  if ANode.IsNull then Exit;
  if ANode.NodeType = 'assignment' then
  begin
    Lhs := ANode.ChildByField('lhs');
    if (not Lhs.IsNull)
       and (Integer(ANode.StartByte) > AFrom) and (Integer(ANode.StartByte) < ATo)
       and SameText(Trim(NodeStr(Lhs, ASrc)), AName) then Exit(True);
  end;
  for I := 0 to ANode.NamedChildCount - 1 do
    if AssignedInRange(ANode.NamedChild(I), ASrc, AName, AFrom, ATo) then Exit(True);
end;

{ True when AVar has an assignment EARLIER in the routine that is governed by
  exactly one of AGuards, and that guard variable is not rewritten in between. }
function AssignedUnderSameGuard(const ANode, ARoutine: TTSNode; const ASrc: TBytes;
  const AVar: string; AReadStart: Integer; AGuards: TList<string>): Boolean;
var
  I    : Integer    ;
  Lhs  : TTSNode    ;
  Own  : TList<string>;
  K    : Integer    ;
begin
  Result := False;
  if ANode.IsNull then Exit;
  if ANode.NodeType = 'assignment' then
  begin
    Lhs := ANode.ChildByField('lhs');
    if (not Lhs.IsNull) and (Integer(ANode.StartByte) < AReadStart)
       and SameText(Trim(NodeStr(Lhs, ASrc)), AVar) then
    begin
      Own := TList<string>.Create;
      try
        CollectThenGuards(ANode, ARoutine, ASrc, Own);
        for K := 0 to Own.Count - 1 do
          if (AGuards.IndexOf(Own[K]) >= 0)
             and (not AssignedInRange(ARoutine, ASrc, Own[K],
                                      Integer(ANode.EndByte), AReadStart)) then
            Exit(True);
      finally
        Own.Free;
      end;
    end;
  end;
  for I := 0 to ANode.NamedChildCount - 1 do
    if AssignedUnderSameGuard(ANode.NamedChild(I), ARoutine, ASrc, AVar, AReadStart, AGuards) then Exit(True);
end;

function ContainsAtIdentBoundary(const S, AWhat: string): Boolean;
var P: Integer; Ch: Char;
begin
  Result := False;
  P := Pos(AWhat, S);
  while P > 0 do
  begin
    if P = 1 then Exit(True);
    Ch := S[P - 1];
    if not (CharInSet(Ch, ['a'..'z', '0'..'9', '_'])) then Exit(True);
    P := Pos(AWhat, S, P + 1);   { 3-arg System.Pos -- no StrUtils dependency }
  end;
end;

{ True when the routine frees AName inside a `finally` block.

  v(2026-08-13): this suppresses an object-leak FALSE POSITIVE whose cause is a
  deliberate CFG edge, and it is deliberately a syntactic guard rather than a
  change to that edge.

  MEASURED shape (probe): a create guarded by `try..finally X.Free` is reported
  as a leak the moment ANY enclosing `try..except` exists -- and only for
  except, never for finally:

      A  X := T.Create; try .. finally X.Free end;                  silent  (correct)
      B  try X := T.Create; try .. finally X.Free end; except .. end  FIRES  (wrong)
      C  X := T.Create; <never freed>                                FIRES  (correct)

  Cause: `try..except` wires tryEntry -> handler, modelling "the exception fired
  before the body ran". On that edge the inner finally never executes, so X
  reaches the exit still open. That edge is NOT a bug -- used-before-assignment
  depends on exactly the "try body's assignments never ran" state it carries,
  and the comment on it records that it was tuned twice. Rerouting it through
  nested finallys would perturb every dataflow rule at once.

  So the fix is scoped to the rule that is wrong: if the routine hands this
  variable to a `finally`, the standard Delphi ownership idiom is present and
  the remaining "leak" is the modelling artifact above. Real leaks (case C) have
  no such finally and still fire.

  Known, accepted narrowness: a variable created on a second path that the
  finally does not protect is no longer reported. That is the FP-safe direction
  for an `info` rule already recorded as majority-false
  (INBOX-group-E-dataflow-rules-are-majority-false.md). }
function FreedInFinallyBlock(const AProc: TTSNode; const AName: string; const ASrc: TBytes): Boolean;
var
  Found: Boolean;
  Nm   : string;

  procedure Walk(const N: TTSNode);
  var I: Integer; C: TTSNode; SeenFinally: Boolean; S: string;
  begin
    if Found or N.IsNull then Exit;
    if N.NodeType = 'try' then
    begin
      SeenFinally := False;
      for I := 0 to N.ChildCount - 1 do
      begin
        C := N.Child(I);
        if C.NodeType = 'kFinally' then SeenFinally := True
        else if SeenFinally then
        begin
          if C.NodeType = 'kEnd' then Break;
          { TightenPunct, not the raw text. The match is literal, so a
            COLUMN-ALIGNED free -- `Rows  .Free;`, which is ordinary style in
            this codebase -- did not match `rows.free` and the object was
            reported as leaked despite being freed two lines away.

            Natural experiment in one finally block of Storage.SQLite.pas:
            padded `Rows  .Free;` fired, unpadded `Winner.Free;` did not; the
            longest name in each aligned column is the one that happens to be
            unpadded, which is why this looked arbitrary. Unpadding `Rows` by
            hand took that unit from 7 object-leak findings to 6, removing
            exactly `rows`. 9 findings on the self-index came from this. }
          S := TightenPunct(LowerCase(NodeStr(C, ASrc)));
          if ContainsAtIdentBoundary(S, Nm + '.free')
             or ContainsAtIdentBoundary(S, Nm + '.disposeof')
             or ContainsAtIdentBoundary(S, 'freeandnil(' + Nm) then
          begin
            Found := True;
            Exit;
          end;
        end;
      end;
    end;
    for I := 0 to N.NamedChildCount - 1 do
    begin
      Walk(N.NamedChild(I));
      if Found then Exit;
    end;
  end;

begin
  Found := False;
  Nm    := LowerCase(Trim(AName));
  if Nm <> '' then Walk(AProc);
  Result := Found;
end;

{ Vars that an EARLIER operand of an `and`/`or` chain assigns via a call argument,
  and which a LATER operand of the same chain may therefore read safely.

  Delphi short-circuits left to right, so

      if VerQueryValue(Pointer(Buf), '\', Pointer(Fixed), Len) and (Fixed <> nil)

  assigns Fixed in the left operand BEFORE the right one reads it -- but both
  operands are ONE AST node and therefore ONE CFG item, and the per-item replay
  tests every read against the state from BEFORE the item's own defs are applied.
  So the read of Fixed was reported as a use before assignment.

  CollectInterfaceDerefs already carries exactly this refinement for
  `not-assigned-interface` (its `LocallyAssigned` + `CollectLocalCallDefs`, and its
  header explains the `Supports(Intf, IFoo, V) and V.Method` idiom). The plain read
  check never had it. This is that same left-to-right refinement, extracted so the
  two checks cannot disagree about the same idiom.

  WHY HERE AND NOT INSIDE CollectReadsAndCallDefs: that function feeds liveness and
  several other rules, and dropping a read there would change what they see. This
  is consumed by the used-before-assignment read check only.

  WHY THIS SURFACED NOW: the shape above sits inside `if A then if B then ...`,
  and until the dangling-else `exprIf` arm was added to Cfg.pas.EmitStmt the whole
  nested `if` was ONE OPAQUE ITEM -- and opaque items are skipped by the read check
  entirely. Decomposing the nest correctly exposed this latent defect; the fix for
  one bug made a second one visible, which is the honest description of what
  happened rather than a new regression in the analysis itself. }
procedure CollectAndOrLeftDefs(const ANode: TTSNode; const ASrc: TBytes;
  AVars: TRoutineVarTable; AAcc: TList<Integer>);

  procedure Walk(const N: TTSNode);
  var
    I, K  : Integer;
    Op, L, R: TTSNode;
    OpText: string;
    Reads, CallDefs: TList<Integer>;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'exprBinary' then
    begin
      Op := N.ChildByField('operator');
      OpText := '';
      if not Op.IsNull then OpText := LowerCase(Trim(NodeStr(Op, ASrc)));
      if (OpText = 'and') or (OpText = 'or') then
      begin
        L := N.ChildByField('lhs');
        R := N.ChildByField('rhs');
        Reads := TList<Integer>.Create; CallDefs := TList<Integer>.Create;
        try
          CollectReadsAndCallDefs(L, ASrc, AVars, Reads, CallDefs);
          for K := 0 to CallDefs.Count - 1 do
            if AAcc.IndexOf(CallDefs[K]) < 0 then AAcc.Add(CallDefs[K]);
        finally
          Reads.Free; CallDefs.Free;
        end;
        Walk(L);
        Walk(R);
        Exit;
      end;
    end;
    for I := 0 to N.NamedChildCount - 1 do Walk(N.NamedChild(I));
  end;

begin
  Walk(ANode);
end;

{ True when S contains AWhat as a WHOLE identifier -- BOTH boundaries checked.

  ContainsAtIdentBoundary above checks only the left side, because its callers pin
  the right one by appending '.' or '(' to the name. A bare variable name cannot
  do that, so it needs its own test: without a right-boundary check, `Edges` would
  be found inside `EdgeList` and a store would be called protected by a handler
  that never mentions it. }
function ContainsWholeIdent(const S, AWhat: string): Boolean;
var P, L, N: Integer;
begin
  Result := False;
  L := Length(AWhat);
  N := Length(S);
  if (L = 0) or (N < L) then Exit;
  P := Pos(AWhat, S);
  while P > 0 do
  begin
    if ((P = 1) or (not CharInSet(S[P - 1], ['a'..'z', '0'..'9', '_'])))
       and ((P + L > N) or (not CharInSet(S[P + L], ['a'..'z', '0'..'9', '_']))) then Exit(True);
    P := Pos(AWhat, S, P + 1);   { 3-arg System.Pos -- no StrUtils dependency }
  end;
end;

{ True when the store AAsg is the (possibly not last) member of a run of
  assignments immediately preceding a `try` whose except/finally MENTIONS AName.

  WHY: overwrite-before-read reported the nil-initialisation before a `try` as a
  dead store, and ITS ADVICE WAS WRONG -- deleting that store leaves an
  uninitialised variable to be tested or freed on the exception path, so
  following the finding converts correct code into a crash. Measured on this
  repo's own source at 56 findings, majority of this shape:

      Bindings := nil;                        <- reported as a dead store
      try
        Bindings := ExtractDfmEventBindings(...);
      except
        Bindings := nil;
      end;

  Liveness is right about the CFG and wrong about the code. `try..except` wires
  the handler edge from the END of the try body (Cfg.pas), modelling "the
  exception fired after the body's assignments ran", so the pre-try store is
  killed before any exception-path use is seen. That edge is deliberate and
  tuned -- used-before-assignment depends on the state it carries -- which is
  exactly the reasoning FreedInFinallyBlock above records for object-leak's
  identical cause. So this is again a SYNTACTIC guard scoped to the one wrong
  rule, not a change to the edge.

  THE RUN MATTERS. Five nil-inits before one shared `try` is the common form, so
  the walk skips over consecutive sibling assignments: protection covers every
  variable initialised between the previous statement and the `try`, not just the
  closest one. (object-leak's Cause A needs the same shape.)

  WHY "MENTIONS" AND NOT "READS": an assignment in the handler
  (`Bindings := nil` again) is itself a use for a managed type -- it releases the
  old value -- and a `finally` typically FREES rather than reads. Testing for any
  occurrence covers read, free and re-assign without having to classify them, and
  is the FP-safe direction for an `info` rule already recorded as majority-false.

  DELIBERATELY NOT the cheap version ("a try merely follows"): that suppresses a
  genuine dead store sitting before an unrelated try, which is the banned failure
  mode for this whole rule family -- the cheap fix for every one of these rules
  is to stop reporting near a `try`. A store before a try whose handler never
  names it STILL FIRES, and the guard test asserts exactly that. }
function ProtectedByFollowingTry(const AAsg: TTSNode; const AName: string; const ASrc: TBytes): Boolean;
var
  Cur, C: TTSNode;
  Nm, S : string;
  I     : Integer;
  Guard : Integer;
  SeenHandler: Boolean;

  { A single statement can arrive wrapped in a `statement` node -- the same
    wrapper the dangling-else fix had to unwrap in Cfg.pas.EmitStmt. }
  function Unwrap(const N: TTSNode): TTSNode;
  begin
    Result := N;
    if (not Result.IsNull) and (Result.NodeType = 'statement')
       and (Result.NamedChildCount = 1) then Result := Result.NamedChild(0);
  end;

begin
  Result := False;
  Nm := LowerCase(Trim(AName));
  if Nm = '' then Exit;

  Cur   := Unwrap(AAsg.NextNamedSibling);
  Guard := 0;
  while (not Cur.IsNull) and (Cur.NodeType = 'assignment') and (Guard < 64) do
  begin
    Cur := Unwrap(Cur.NextNamedSibling);
    Inc(Guard);
  end;
  if Cur.IsNull or (Cur.NodeType <> 'try') then Exit;

  SeenHandler := False;
  for I := 0 to Cur.ChildCount - 1 do
  begin
    C := Cur.Child(I);
    { KEYWORDS ARE NAMED NODES in this grammar, so the handler section is found by
      walking children and watching for the keyword -- not by a field lookup. }
    if (C.NodeType = 'kExcept') or (C.NodeType = 'kFinally') then SeenHandler := True
    else if SeenHandler then
    begin
      if C.NodeType = 'kEnd' then Break;
      S := LowerCase(NodeStr(C, ASrc));
      if ContainsWholeIdent(S, Nm) then Exit(True);
    end;
  end;
end;

/// <summary>True when AAsg assigns the literal <c>nil</c> to a local whose
/// declared type is an interface -- i.e. the store RELEASES a reference rather
/// than producing a value.</summary>
/// <param name="AAsg">The assignment node under test.</param>
/// <param name="ASrc">Source bytes backing the node.</param>
/// <param name="ATypeText">The target's declared type text, verbatim from the
/// routine var table.</param>
/// <param name="AStore">Symbol store used to resolve the type's kind; may be
/// nil, in which case IsInterfaceType falls back to the 'I'+uppercase spelling
/// convention.</param>
/// <param name="AFileId">File id scoping the resolution (0 when no store).</param>
/// <returns>True when the store is a release and must not be reported as dead.</returns>
/// <remarks>
/// <para>Sibling of ProtectedByFollowingTry, and open for the same reason: the
/// rule was not merely noisy, ITS ADVICE WAS WRONG. For an interface variable
/// <c>X := nil</c> drops a reference, which for the last reference runs
/// _Release and therefore the destructor -- an observable side effect liveness
/// cannot see, because liveness models a store as producing a VALUE. Reported
/// 2026-08-25 against DataCopy, where TConfigurationService writes its INI file
/// in its destructor, so deleting the flagged line does not tidy the code, it
/// stops the file being written.</para>
/// <para>Deliberately narrow: ONLY the nil literal. A store of a non-nil
/// interface value that is overwritten before any read is still a genuine dead
/// store and still fires -- <c>X := nil</c> is the only shape that can have no
/// value purpose whatsoever, so the release is the only thing it can be for.
/// Exempting every <c>:= nil</c> instead would silence class references, where
/// there is no refcount and nothing observable happens.</para>
/// </remarks>
function ReleasesInterfaceRef(const AAsg: TTSNode; const ASrc: TBytes;
  const ATypeText: string; const AStore: ISymbolStore; AFileId: Int64): Boolean;
var
  Rhs: TTSNode;
begin
  Result := False;
  Rhs := AAsg.ChildByField('rhs');
  if Rhs.IsNull then Exit;
  if not SameText(Trim(NodeStr(Rhs, ASrc)), 'nil') then Exit;
  Result := IsInterfaceType(ATypeText, AStore, AFileId);
end;

/// <summary>True when a store the liveness lattice calls DEAD carries a side
/// effect the lattice cannot see, so reporting it would give wrong advice.</summary>
/// <param name="AAsg">The assignment node under test.</param>
/// <param name="AName">The target local's name (for the try-handler scan).</param>
/// <param name="ATypeText">The target's declared type text.</param>
/// <param name="ASrc">Source bytes backing the node.</param>
/// <param name="AStore">Symbol store for type resolution; may be nil.</param>
/// <param name="AFileId">File id scoping the resolution (0 when no store).</param>
/// <returns>True when the store must NOT be reported as a dead store.</returns>
/// <remarks>Names the one thing ProtectedByFollowingTry and ReleasesInterfaceRef
/// have in common, which is the whole reason both exist: liveness models a store
/// as producing a VALUE, and in Delphi a store can also produce an OBSERVABLE
/// EFFECT -- making an exception path safe, or dropping the last reference to an
/// interface and running its destructor. Both were reported as false positives
/// whose advice, followed, breaks working code. A third shape belongs here, not
/// in a fifth conjunct at the call site.</remarks>
function StoreHasEffectLivenessCannotSee(const AAsg: TTSNode;
  const AName, ATypeText: string; const ASrc: TBytes;
  const AStore: ISymbolStore; AFileId: Int64): Boolean;
begin
  Result := ProtectedByFollowingTry(AAsg, AName, ASrc)
         or ReleasesInterfaceRef(AAsg, ASrc, ATypeText, AStore, AFileId);
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
  AFileId: Int64; const ALibStore: ISymbolStore): TArray<TLintFinding>;
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
    SeqDefs: TList<Integer>; { and/or left-operand defs -- see CollectAndOrLeftDefs }
    CurMust, CurMay: TArray<Boolean>;
    Derefs: TList<TIfaceDeref>; Dr: TIfaceDeref;
    LiveAna: IDataFlowAnalysis<TArray<Boolean>>;
    LIn, LOut: TArray<TArray<Boolean>>;
    ReadAny, AsgnAny, Live: TArray<Boolean>;
    EscAna: IDataFlowAnalysis<TArray<Boolean>>;
    EIn2, EOut2: TArray<TArray<Boolean>>;
    CreateRow, CreateCol: TArray<Integer>;
    { The type NAME the constructor names, for locals with no declared type
      (`var Re := TRegEx.Create(..)`). TypeIsRefCountedOrValue decides from the
      DECLARED type, which an inline var does not have. }
    CreateType: TArray<string>;
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
      SeqDefs := TList<Integer>.Create;
      Derefs := TList<TIfaceDeref>.Create;
      try
        { ---- used-before-assignment: per-item replay of must/may within a block ---- }
        for B := 0 to Cfg.BlockCount - 1 do
        begin
          CurMust := Copy(AIn[B].Must); CurMay := Copy(AIn[B].May);
          { synthetic entry defs (foreach iterator) }
          ApplyEntryDefs(Cfg.Blocks[B], Vars, CurMust, CurMay, True);
          for I := 0 to Cfg.Blocks[B].Items.Count - 1 do
          begin
            It := Cfg.Blocks[B].Items[I];
            Reads.Clear; CallDefs.Clear;
            if It.Node.NodeType = 'assignment' then
              CollectReadsAndCallDefs(It.Node.ChildByField('rhs'), PF.Src, Vars, Reads, CallDefs, RecMethodDef)
            else
              CollectReadsAndCallDefs(It.Node, PF.Src, Vars, Reads, CallDefs, RecMethodDef);
            { flag reads of unmanaged locals not yet must-assigned (skip opaque with-bodies) }
            { Left-to-right sequencing inside this item's own and/or chains, so
              `Supports(.., V) and V.Method` and
              `VerQueryValue(.., Pointer(Fixed), ..) and (Fixed <> nil)` are not
              reported as reads before assignment. See CollectAndOrLeftDefs. }
            SeqDefs.Clear;
            if not It.Opaque then CollectAndOrLeftDefs(It.Node, PF.Src, Vars, SeqDefs);
            if not It.Opaque then
              for J := 0 to Reads.Count - 1 do
              begin
                RIx := Reads[J];
                if SeqDefs.IndexOf(RIx) >= 0 then Continue;
                V := Vars.Get(RIx);
                if V.Kind <> vkLocal then Continue;
                if IsManagedType(V.TypeText, AStore, AFileId) then Continue;
                if not CurMust[RIx] then
                begin
                  ROW := Integer(It.Node.StartPoint.Row) + 1;
                  COL := Integer(It.Node.StartPoint.Column) + 1;
                  { SAME-PREDICATE SUPPRESSION -- see ThenGuardName above.

                    Applied ONLY in the `may` (info) arm. A `must` finding says
                    the variable is unassigned on EVERY path, which no guard
                    correlation can excuse, so the warning arm is deliberately
                    left alone: this can downgrade noise, never hide a certain
                    use-before-assignment. }
                  if CurMay[RIx] then
                  begin
                    var Guards: TList<string> := TList<string>.Create;
                    try
                      CollectThenGuards(It.Node, Cfg.RoutineNode, PF.Src, Guards);
                      if (Guards.Count > 0)
                         and AssignedUnderSameGuard(Cfg.RoutineNode, Cfg.RoutineNode,
                               PF.Src, V.Name, Integer(It.Node.StartByte), Guards) then
                        Continue;
                    finally
                      Guards.Free;
                    end;
                  end;
                  { OWNER RULING 2026-08-26: raise this rule to error. Reading an
                    unassigned local is a defect, not advice, and it sat at info/
                    warning where nobody saw it.

                    BOTH levels move up ONE step; the two are not collapsed. The
                    MAY case is a genuine maybe -- the variable is assigned on
                    some paths and not others, and the checker cannot prove which
                    path runs -- so calling it an error would assert something not
                    known. Definite -> error, may -> warning keeps the certainty
                    distinction the analysis actually computes. }
                  if CurMay[RIx] then
                    Emit('used-before-assignment', 'warning',
                      Format('Local "%s" may be used before it is assigned.', [V.Name]), ROW, COL)
                  else
                    Emit('used-before-assignment', 'error',
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
            { Mirror TFreedState.Transfer's EntryDefs kill. FIn[B] is the JOIN of
              the predecessors, so it still carries the back-edge's dangling
              state; the replay must rebind the foreach iterator before it walks
              the items or `for L in List do L.Free` reports itself. }
            ApplyEntryDefs(Cfg.Blocks[B], Vars, CurFMust, CurFMay, False);
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
                   and ReadAny[Tgt] and (not Live[Tgt])
                   { Two shapes liveness calls dead that are not: a nil-init
                     guarding an exception path (deleting it CRASHES), and
                     `X := nil` on an interface local (that store IS the release,
                     and the destructor it runs is routinely the point of the
                     line). See StoreHasEffectLivenessCannotSee. }
                   and (not StoreHasEffectLivenessCannotSee(It.Node, Vars.Get(Tgt).Name,
                              Vars.Get(Tgt).TypeText, PF.Src, AStore, AFileId)) then
                begin
                  ROW := Integer(It.Node.StartPoint.Row) + 1;
                  COL := Integer(It.Node.StartPoint.Column) + 1;
                  { OWNER RULING 2026-08-26: warning, not info. This is the same
                    fact a compiler reports as "value assigned ... never used"
                    (H2077), and compilers do not whisper it. }
                  Emit('overwrite-before-read', 'warning',
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
          SetLength(CreateType, Vars.Count);
          for I := 0 to Vars.Count - 1 do begin CreateRow[I] := 0; CreateCol[I] := 0; CreateType[I] := ''; end;
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
                 and not ConstructorTransfersOwnership(It.Node.ChildByField('rhs'), PF.Src, AStore, AFileId, ALibStore)
                 { SELF-LINKING CONSTRUCTION IS NOT A LEAK CANDIDATE.
                   `Cur := TGroup.Create(kind, i, k, Cur)` passes the variable
                   being assigned as an ARGUMENT to its own constructor: the new
                   node takes the old one as its parent, links itself into the
                   structure, and is reachable from the root the routine returns
                   -- so it is freed with that structure. This is the surviving
                   cause in INBOX-object-leak-is-systematically-false, described
                   there as "a tree cursor whose nodes escape via the returned
                   root".

                   The guard is needed HERE as well as in TEscape.Transfer: the
                   lattice computes block state, but THIS replay is what records
                   the reportable site, so fixing only the lattice changed
                   nothing observable. Narrow on purpose -- it fires only when
                   the assignment target itself is among the arguments, so
                   `A := T.Create(B)` is untouched. }
                 and not SelfLinkedConstruction(It.Node, PF.Src, Vars, Tgt) then
              begin
                CreateRow[Tgt] := Integer(It.Node.StartPoint.Row) + 1;
                CreateCol[Tgt] := Integer(It.Node.StartPoint.Column) + 1;
                CreateType[Tgt] := ConstructedTypeText(It.Node.ChildByField('rhs'), PF.Src);
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
               { An inline `var X := T.Create(..)` has NO declared type, so the
                 value/interface narrowing below had nothing to read and every
                 such local was a leak candidate regardless of its kind. Fall
                 back to the type the constructor names. (Latent until inline
                 vars started registering as assignment targets at all -- see
                 AssignmentTargetIndex's varAssignDef fix.) }
               and not TypeIsRefCountedOrValue(
                     if Trim(Vars.Get(I).TypeText) <> '' then Vars.Get(I).TypeText else CreateType[I],
                     AStore)
               { the variable is handed to a `finally` -- see FreedInFinallyBlock:
                 what remains open at the exit is the try..except modelling edge,
                 not a missed Free. }
               and not FreedInFinallyBlock(AProc, Vars.Get(I).Name, PF.Src) then
              Emit('object-leak', 'info',
                Format('Object "%s" may be leaked: created but not freed or transferred on some path.',
                  [Vars.Get(I).Name]), CreateRow[I], CreateCol[I]);
        end;

      finally Reads.Free; CallDefs.Free; SeqDefs.Free; Derefs.Free; end;
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
