unit DRagLint.Analysis.Flow.Lattices;

{ Per-routine variable table + concrete data-flow analyses (M2). The variable
  table indexes a routine's locals, params and Result to 0..N-1; lattice values
  are bitsets over those indices. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  TreeSitter,
  DRagLint.Analysis.Cfg,
  DRagLint.Analysis.DataFlow;

type
  /// <summary>Storage class of a routine-scoped variable.</summary>
  TVarKind = (vkLocal, vkParamVar, vkParamOut, vkParamConst, vkParamValue, vkResult);

  /// <summary>A routine-scoped variable: name (lowercased), kind, declared-type
  /// text, declaration position, and whether it is captured by a nested routine.</summary>
  /// <remarks>v(ADP3 T11): Display carries the ORIGINAL-CASE spelling from the
  /// declaration, which Name deliberately does not -- Name is lowercased because
  /// every lookup here is case-insensitive (Pascal identifiers are). A consumer
  /// that RENDERS a variable to a human needs the spelling the author wrote, and
  /// recovering it from Name is impossible, so it is captured once at Build time
  /// beside it. Every existing consumer matches on Name and is unaffected;
  /// Display is set at every construction site, so it is never ''. Added for
  /// DRagLint.Doc.SymbolFacts' Mutates fact, which names var/out parameters.</remarks>
  TRoutineVar = record
    Name    : string;
    Display : string;
    Kind    : TVarKind;
    TypeText: string;
    DeclLine: Integer;
    DeclCol : Integer;
    Captured: Boolean;
  end;

  /// <summary>Maps a routine's locals/params/Result to dense indices 0..N-1.</summary>
  TRoutineVarTable = class
  strict private
    FVars  : TList<TRoutineVar>;
    FByName: TDictionary<string, Integer>;
  public
    constructor Create;
    destructor Destroy; override;
    function Count: Integer;
    /// <summary>Index of ALowerName, or -1 if not a routine-scoped var.</summary>
    function IndexOf(const ALowerName: string): Integer;
    function Get(AIdx: Integer): TRoutineVar;
    procedure Add(const AVar: TRoutineVar);
    /// <summary>Alias an extra lowercased name to an existing var index (e.g. the
    /// function name -> the Result slot for the `F := value` definition form).</summary>
    procedure Alias(const ALowerName: string; AIdx: Integer);
    /// <summary>Mark the var at AIdx as captured by a nested routine.</summary>
    procedure MarkCaptured(AIdx: Integer);
    /// <summary>Build from a `defProc` node: params (with var/out/const modes),
    /// the var sections, inline `var x` decls, an implicit Result for functions,
    /// and capture flags for outer vars referenced inside nested routines.</summary>
    class function Build(const AProc: TTSNode; const ASrc: TBytes): TRoutineVarTable;
  end;

  /// <summary>Definite-assignment lattice value: `Must`[i] = var i assigned on
  /// EVERY path here; `May`[i] = on SOME path.</summary>
  TDefAsgnVal = record
    Must: TArray<Boolean>;
    May : TArray<Boolean>;
  end;

  /// <summary>Forward must+may definite-assignment analysis.</summary>
  TDefiniteAssignment = class(TInterfacedObject, IDataFlowAnalysis<TDefAsgnVal>)
  strict private
    FVars: TRoutineVarTable;
    FSrc : TBytes;
  public
    constructor Create(AVars: TRoutineVarTable; const ASrc: TBytes);
    function Direction: TFlowDir;
    function Bottom: TDefAsgnVal;
    function Boundary: TDefAsgnVal;
    function Join(const A, B: TDefAsgnVal): TDefAsgnVal;
    function Transfer(const ABlock: TCfgBlock; const AIn: TDefAsgnVal): TDefAsgnVal;
    function Equals(const A, B: TDefAsgnVal): Boolean;
  end;

  /// <summary>Freed-var lattice value: `Must`[i] = var i is DANGLING (freed via
  /// a raw `.Free`/`.DisposeOf` and not since nil-ed or reassigned) on EVERY
  /// path here; `May`[i] = dangling on SOME path.</summary>
  TFreedVal = record
    Must: TArray<Boolean>;
    May : TArray<Boolean>;
  end;

  /// <summary>Forward must+may "dangling pointer" analysis for double-free
  /// detection. A raw `X.Free`/`X.DisposeOf` frees the object but leaves X
  /// non-nil (dangling); `FreeAndNil(X)` frees AND nils X (safe to re-Free);
  /// any whole-identifier assignment to X re-points it (safe). See
  /// `DetectFreedVarKind` for the free-site classification this Transfer
  /// consumes.</summary>
  /// <remarks>This lattice only tracks STATE (dangling or not) between CFG
  /// items; it does not itself emit findings -- the double-free rule replays
  /// items per block (mirroring TDefiniteAssignment's used-before-assignment
  /// replay) so it can check the IN-state at each free site BEFORE advancing,
  /// distinguishing "this free's own effect" from "a prior free's effect".</remarks>
  TFreedState = class(TInterfacedObject, IDataFlowAnalysis<TFreedVal>)
  strict private
    FVars: TRoutineVarTable;
    FSrc : TBytes;
  public
    constructor Create(AVars: TRoutineVarTable; const ASrc: TBytes);
    function Direction: TFlowDir;
    function Bottom: TFreedVal;
    function Boundary: TFreedVal;
    function Join(const A, B: TFreedVal): TFreedVal;
    function Transfer(const ABlock: TCfgBlock; const AIn: TFreedVal): TFreedVal;
    function Equals(const A, B: TFreedVal): Boolean;
  end;

  /// <summary>Backward may-live-variables analysis: `live`[i] = var i may be read
  /// on some path after this point before being reassigned. Powers dead-store
  /// (overwrite-before-read) and write-only-local detection.</summary>
  /// <remarks>Transfer receives the block's live-OUT and returns its live-IN.
  /// An opaque (`with`-body) item conservatively marks every local live.</remarks>
  TLiveness = class(TInterfacedObject, IDataFlowAnalysis<TArray<Boolean>>)
  strict private
    FVars: TRoutineVarTable;
    FSrc : TBytes;
  public
    constructor Create(AVars: TRoutineVarTable; const ASrc: TBytes);
    function Direction: TFlowDir;
    function Bottom: TArray<Boolean>;
    function Boundary: TArray<Boolean>;
    function Join(const A, B: TArray<Boolean>): TArray<Boolean>;
    function Transfer(const ABlock: TCfgBlock; const AIn: TArray<Boolean>): TArray<Boolean>;
    function Equals(const A, B: TArray<Boolean>): Boolean;
  end;

  /// <summary>Ownership oracle: returns True if a call to ACalleeName OWNS its
  /// argument at AArgIdx (the arg escapes), False if the callee is clearly
  /// non-owning (the arg may leak). Supplied by TFlowChecker when a store is
  /// present; nil => store-free (any pass-to-call escapes).</summary>
  TCallArgOwns = reference to function(const ACalleeName: string; AArgIdx: Integer): Boolean;

  /// <summary>A variable passed as a call argument: the callee's bare-identifier
  /// name (empty for method calls), the 0-based argument position, and the var.</summary>
  TCallArgRef = record CalleeName: string; ArgIdx, VarIdx: Integer; end;

  /// <summary>Forward "may-open" escape analysis for object-leak detection:
  /// `MaybeOpen`[i] = local i was assigned from a constructor and, on some path,
  /// has not since been freed (`x.Free`/`FreeAndNil`/`x.DisposeOf`) or escaped
  /// (returned via Result, stored in a field, passed to a call, or aliased).</summary>
  /// <remarks>Store-free default: ANY pass-to-call counts as escape. With an
  /// ownership oracle (store-backed), a pass to a clearly non-owning unit proc
  /// does NOT escape, so a genuine interprocedural leak surfaces.</remarks>
  TEscape = class(TInterfacedObject, IDataFlowAnalysis<TArray<Boolean>>)
  strict private
    FVars: TRoutineVarTable;
    FSrc : TBytes;
    FOwns: TCallArgOwns;
  public
    constructor Create(AVars: TRoutineVarTable; const ASrc: TBytes; AOwns: TCallArgOwns = nil);
    function Direction: TFlowDir;
    function Bottom: TArray<Boolean>;
    function Boundary: TArray<Boolean>;
    function Join(const A, B: TArray<Boolean>): TArray<Boolean>;
    function Transfer(const ABlock: TCfgBlock; const AIn: TArray<Boolean>): TArray<Boolean>;
    function Equals(const A, B: TArray<Boolean>): Boolean;
  end;

/// <summary>True if the expression subtree is a constructor call (`T.Create...`):
/// it contains an `exprDot` whose member identifier is `Create`.</summary>
function ExprIsConstructor(const N: TTSNode; const ASrc: TBytes): Boolean;

/// <summary>If ANode is `x.Free` / `x.DisposeOf` / `FreeAndNil(x)`, return the
/// freed local's index, else -1.</summary>
function DetectFreedVar(const ANode: TTSNode; const ASrc: TBytes; AVars: TRoutineVarTable): Integer;

/// <summary>Kind of free site: a raw `.Free`/`.DisposeOf` leaves the pointer
/// DANGLING (non-nil); `FreeAndNil` nils it (safe to re-Free afterwards).</summary>
type
  TFreeKind = (fkRawFree, fkNiling);

/// <summary>Same detection as `DetectFreedVar`, plus AKind telling the caller
/// whether the site is a raw free (`x.Free`/`x.DisposeOf`, dangling result) or
/// a nil-ing free (`FreeAndNil(x)`, safe result). Returns -1 (AKind undefined)
/// when ANode is not a free site.</summary>
function DetectFreedVarKind(const ANode: TTSNode; const ASrc: TBytes; AVars: TRoutineVarTable;
  out AKind: TFreeKind): Integer;

/// <summary>Collect every routine var passed as a call argument anywhere under
/// ANode, with the callee's bare-identifier name (empty for method calls) and
/// the 0-based argument position.</summary>
function CollectCallArgs(const ANode: TTSNode; const ASrc: TBytes;
  AVars: TRoutineVarTable): TArray<TCallArgRef>;

/// <summary>Lowercased identifier text of N, trimmed.</summary>
function NodeText(const N: TTSNode; const ASrc: TBytes): string;

/// <summary>Leftmost-identifier base var of an expression: `x`, `x.f`, `x[i]`,
/// `x.f.g` -> the routine-var index of `x`. Returns -1 when the base is not a
/// routine var (a literal, a type name, an unresolvable expression, ...).</summary>
function LeftmostBaseVar(const N: TTSNode; const ASrc: TBytes; AVars: TRoutineVarTable): Integer;

/// <summary>Collect lowercased identifier reads in an expression subtree that
/// resolve to a routine var. Skips the member-name child after a `.` (kDot) and
/// treats call arguments / `@x` as POSSIBLE defs (FP-safe), not reads -- so
/// AReads holds only genuine value reads, ACallDefs the indices possibly written
/// via a call argument or address-of.</summary>
procedure CollectReadsAndCallDefs(const ANode: TTSNode; const ASrc: TBytes;
  AVars: TRoutineVarTable; AReads, ACallDefs: TList<Integer>);

/// <summary>Index of the variable an `assignment` node defines as a WHOLE
/// (its plain lhs), or -1 when the lhs is an indexed/qualified write (a[i] / x.f)
/// rather than a whole-variable definition. Used by liveness (a partial write
/// must NOT kill the whole var).</summary>
function AssignmentTargetIndex(const ANode: TTSNode; const ASrc: TBytes;
  AVars: TRoutineVarTable): Integer;

/// <summary>Index of the routine var at the BASE of an assignment's lhs --
/// the leftmost identifier of `x`, `x.f`, `x[i]`, `x.f.g := ...`. For
/// definite-assignment a partial write (`Result.Must := ...`) still counts as
/// assigning the base (`Result`), preventing false function-result-not-set /
/// used-before findings. Returns -1 when the base is not a routine var.</summary>
function AssignmentBaseIndex(const ANode: TTSNode; const ASrc: TBytes;
  AVars: TRoutineVarTable): Integer;

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

function NodeText(const N: TTSNode; const ASrc: TBytes): string;
begin
  Result := LowerCase(Trim(NodeStr(N, ASrc)));
end;

{ The first `identifier` named child of N (e.g. the var name in a `varAssignDef`,
  whose first named child is the `kVar` keyword, not the identifier). }
function FirstIdentChild(const N: TTSNode): TTSNode;
var I: Integer;
begin
  Result := Default(TTSNode);
  for I := 0 to N.NamedChildCount - 1 do
    if N.NamedChild(I).NodeType = 'identifier' then Exit(N.NamedChild(I));
end;

{ ----- TRoutineVarTable ----- }

constructor TRoutineVarTable.Create;
begin
  inherited; FVars := TList<TRoutineVar>.Create;
  FByName := TDictionary<string, Integer>.Create;
end;

destructor TRoutineVarTable.Destroy;
begin FByName.Free; FVars.Free; inherited; end;

function TRoutineVarTable.Count: Integer; begin Result := FVars.Count; end;
function TRoutineVarTable.Get(AIdx: Integer): TRoutineVar; begin Result := FVars[AIdx]; end;

function TRoutineVarTable.IndexOf(const ALowerName: string): Integer;
begin if not FByName.TryGetValue(ALowerName, Result) then Result := -1; end;

procedure TRoutineVarTable.Add(const AVar: TRoutineVar);
begin
  if FByName.ContainsKey(AVar.Name) then Exit;
  FByName.Add(AVar.Name, FVars.Count);
  FVars.Add(AVar);
end;

procedure TRoutineVarTable.Alias(const ALowerName: string; AIdx: Integer);
begin
  if (ALowerName <> '') and not FByName.ContainsKey(ALowerName) then
    FByName.Add(ALowerName, AIdx);
end;

procedure TRoutineVarTable.MarkCaptured(AIdx: Integer);
var V: TRoutineVar;
begin
  if (AIdx < 0) or (AIdx >= FVars.Count) then Exit;
  V := FVars[AIdx]; V.Captured := True; FVars[AIdx] := V;
end;

class function TRoutineVarTable.Build(const AProc: TTSNode; const ASrc: TBytes): TRoutineVarTable;
var
  Tbl: TRoutineVarTable;
  Header, Args, Ret, NameN: TTSNode;
  I, ResultIdx: Integer;
  Sec: TTSNode;
  RV: TRoutineVar;

  procedure AddDeclVars(const ASection: TTSNode);
  var I, J, TypeStart: Integer; DV, TypeNode, NameId: TTSNode; R: TRoutineVar;
  begin
    if ASection.IsNull then Exit;
    for I := 0 to ASection.NamedChildCount - 1 do
    begin
      DV := ASection.NamedChild(I);
      if DV.NodeType <> 'declVar' then Continue;
      TypeNode := DV.ChildByField('type');
      TypeStart := MaxInt;
      if not TypeNode.IsNull then TypeStart := Integer(TypeNode.StartByte);
      for J := 0 to DV.NamedChildCount - 1 do
      begin
        NameId := DV.NamedChild(J);
        if (NameId.NodeType = 'identifier') and (Integer(NameId.StartByte) < TypeStart) then
        begin
          R := Default(TRoutineVar);
          R.Name := LowerCase(NodeStr(NameId, ASrc));
          R.Display := NodeStr(NameId, ASrc);
          R.Kind := vkLocal;
          R.TypeText := Trim(NodeStr(TypeNode, ASrc));
          R.DeclLine := Integer(NameId.StartPoint.Row) + 1;
          R.DeclCol  := Integer(NameId.StartPoint.Column) + 1;
          Tbl.Add(R);
        end;
      end;
    end;
  end;

  procedure AddArgs(const AArgs: TTSNode);
  var I, J: Integer; DA, TypeNode, NameId, Modi: TTSNode; R: TRoutineVar; Mode: TVarKind; MText: string;
  begin
    if AArgs.IsNull then Exit;
    for I := 0 to AArgs.NamedChildCount - 1 do
    begin
      DA := AArgs.NamedChild(I);
      if DA.NodeType <> 'declArg' then Continue;
      Mode := vkParamValue;
      for J := 0 to DA.ChildCount - 1 do
      begin
        Modi := DA.Child(J);
        MText := Modi.NodeType;
        if MText = 'kVar'   then Mode := vkParamVar;
        if MText = 'kOut'   then Mode := vkParamOut;
        if MText = 'kConst' then Mode := vkParamConst;
      end;
      TypeNode := DA.ChildByField('type');
      for J := 0 to DA.NamedChildCount - 1 do
      begin
        NameId := DA.NamedChild(J);
        if NameId.NodeType = 'identifier' then
        begin
          R := Default(TRoutineVar);
          R.Name := LowerCase(NodeStr(NameId, ASrc));
          R.Display := NodeStr(NameId, ASrc);
          R.Kind := Mode;
          R.TypeText := Trim(NodeStr(TypeNode, ASrc));
          R.DeclLine := Integer(NameId.StartPoint.Row) + 1;
          R.DeclCol  := Integer(NameId.StartPoint.Column) + 1;
          Tbl.Add(R);
        end;
      end;
    end;
  end;

  { inline `var x := e` / nested declVars in the body. }
  procedure AddInlineVars(const N: TTSNode);
  var I: Integer; Lhs, IdN: TTSNode; R: TRoutineVar;
  begin
    if N.IsNull then Exit;
    if (N.NodeType = 'defProc') or (N.NodeType = 'lambda') then Exit; { own scope }
    if N.NodeType = 'declVars' then AddDeclVars(N);
    if N.NodeType = 'foreach' then
    begin
      { `for var X in` declares an inline loop variable }
      var ItN := N.ChildByField('iterator');
      if (not ItN.IsNull) and (ItN.NodeType = 'varAssignDef') then
      begin
        IdN := FirstIdentChild(ItN);
        if not IdN.IsNull then
        begin
          R := Default(TRoutineVar);
          R.Name := LowerCase(NodeStr(IdN, ASrc)); R.Display := NodeStr(IdN, ASrc);
          R.Kind := vkLocal; R.TypeText := '';
          R.DeclLine := Integer(IdN.StartPoint.Row) + 1;
          R.DeclCol  := Integer(IdN.StartPoint.Column) + 1;
          Tbl.Add(R);
        end;
      end;
    end;
    if N.NodeType = 'assignment' then
    begin
      Lhs := N.ChildByField('lhs');
      if (not Lhs.IsNull) and (Lhs.NodeType = 'varAssignDef') then
      begin
        IdN := Lhs.ChildByField('name');
        if IdN.IsNull then IdN := FirstIdentChild(Lhs);
        if not IdN.IsNull then
        begin
          R := Default(TRoutineVar);
          R.Name := LowerCase(NodeStr(IdN, ASrc));
          R.Display := NodeStr(IdN, ASrc);
          R.Kind := vkLocal; R.TypeText := '';
          R.DeclLine := Integer(IdN.StartPoint.Row) + 1;
          R.DeclCol  := Integer(IdN.StartPoint.Column) + 1;
          Tbl.Add(R);
        end;
      end;
    end;
    for I := 0 to N.NamedChildCount - 1 do AddInlineVars(N.NamedChild(I));
  end;

  { mark outer vars referenced inside any nested defProc as captured. }
  procedure MarkCaptures(const N: TTSNode; ADepth: Integer);
  var I, Idx: Integer;
  begin
    if N.IsNull then Exit;
    if (N.NodeType = 'identifier') and (ADepth > 0) then
    begin
      Idx := Tbl.IndexOf(LowerCase(NodeStr(N, ASrc)));
      if Idx >= 0 then Tbl.MarkCaptured(Idx);
    end;
    for I := 0 to N.NamedChildCount - 1 do
      if (N.NamedChild(I).NodeType = 'defProc') or (N.NamedChild(I).NodeType = 'lambda') then
        MarkCaptures(N.NamedChild(I), ADepth + 1)
      else MarkCaptures(N.NamedChild(I), ADepth);
  end;

begin
  Tbl := TRoutineVarTable.Create;
  Header := AProc.ChildByField('header');
  if not Header.IsNull then
  begin
    Args := Header.ChildByField('args');
    AddArgs(Args);
    Ret := Header.ChildByField('type');
    if not Ret.IsNull then
    begin
      RV := Default(TRoutineVar);
      RV.Name := 'result'; RV.Display := 'Result'; RV.Kind := vkResult; RV.TypeText := Trim(NodeStr(Ret, ASrc));
      RV.DeclLine := Integer(Header.StartPoint.Row) + 1;
      RV.DeclCol  := Integer(Header.StartPoint.Column) + 1;
      Tbl.Add(RV);
      ResultIdx := Tbl.IndexOf('result');
      NameN := Header.ChildByField('name');
      if (not NameN.IsNull) and (ResultIdx >= 0) then
        Tbl.Alias(LowerCase(NodeStr(NameN, ASrc)), ResultIdx);
    end;
  end;
  for I := 0 to AProc.NamedChildCount - 1 do
  begin
    Sec := AProc.NamedChild(I);
    if Sec.NodeType = 'declVars' then AddDeclVars(Sec);
  end;
  AddInlineVars(AProc.ChildByField('body'));
  { nested routines are `local:` defProc siblings of the body (declared before
    `begin`), so walk the whole defProc -- not just the body -- to find captures. }
  MarkCaptures(AProc, 0);
  Result := Tbl;
end;

{ ----- read/def collection ----- }

{ Leftmost-identifier base var of an expression: `x`, `x.f`, `x[i]`, `x.f.g` -> x.
  Returns -1 when the base is not a routine var. }
function LeftmostBaseVar(const N: TTSNode; const ASrc: TBytes; AVars: TRoutineVarTable): Integer;
var Cur, Nxt, IdN: TTSNode; Guard: Integer;
begin
  Result := -1; Cur := N; Guard := 0;
  while (not Cur.IsNull) and (Guard < 32) do
  begin
    Inc(Guard);
    if Cur.NodeType = 'identifier' then
      Exit(AVars.IndexOf(LowerCase(NodeStr(Cur, ASrc))));
    if Cur.NodeType = 'varAssignDef' then
    begin
      IdN := Cur.ChildByField('name');
      if IdN.IsNull then IdN := FirstIdentChild(Cur);
      if IdN.IsNull then Exit(-1);
      Exit(AVars.IndexOf(LowerCase(NodeStr(IdN, ASrc))));
    end;
    Nxt := Cur.ChildByField('lhs');
    if Nxt.IsNull then Nxt := Cur.ChildByField('entity');
    if Nxt.IsNull and (Cur.NamedChildCount > 0) then Nxt := Cur.NamedChild(0);
    if Nxt.IsNull then Exit(-1);
    Cur := Nxt;
  end;
end;

procedure CollectReadsAndCallDefs(const ANode: TTSNode; const ASrc: TBytes;
  AVars: TRoutineVarTable; AReads, ACallDefs: TList<Integer>);

  procedure Walk(const N: TTSNode; AAfterDot: Boolean);
  var I, Idx: Integer; K: string; ArgsN, Arg: TTSNode;
  begin
    if N.IsNull then Exit;
    K := N.NodeType;
    if K = 'identifier' then
    begin
      if not AAfterDot then
      begin
        Idx := AVars.IndexOf(LowerCase(NodeStr(N, ASrc)));
        if (Idx >= 0) and (AReads.IndexOf(Idx) < 0) then AReads.Add(Idx);
      end;
      Exit;
    end;
    if K = 'exprDot' then
    begin
      Walk(N.ChildByField('lhs'), False);
      Walk(N.ChildByField('rhs'), True); { member name, not a var read }
      Exit;
    end;
    if K = 'exprCall' then
    begin
      ArgsN := N.ChildByField('args');
      if not ArgsN.IsNull then
        for I := 0 to ArgsN.NamedChildCount - 1 do
        begin
          Arg := ArgsN.NamedChild(I);
          { the arg's base var may be assigned by the callee (var/out param, e.g.
            SetLength(Result.Must,..) / SetLength(arr,..)) -> a possible def }
          Idx := LeftmostBaseVar(Arg, ASrc, AVars);
          if (Idx >= 0) and (ACallDefs.IndexOf(Idx) < 0) then ACallDefs.Add(Idx);
          { still walk non-identifier args for reads of OTHER vars (indices etc.) }
          if Arg.NodeType <> 'identifier' then Walk(Arg, False);
        end;
      Walk(N.ChildByField('entity'), False);
      Exit;
    end;
    for I := 0 to N.NamedChildCount - 1 do Walk(N.NamedChild(I), False);
  end;

begin
  Walk(ANode, False);
end;

function AssignmentTargetIndex(const ANode: TTSNode; const ASrc: TBytes;
  AVars: TRoutineVarTable): Integer;
var Lhs, IdN: TTSNode;
begin
  Result := -1;
  Lhs := ANode.ChildByField('lhs');
  if Lhs.IsNull then Exit;
  if Lhs.NodeType = 'identifier' then
    Result := AVars.IndexOf(LowerCase(NodeStr(Lhs, ASrc)))
  else if Lhs.NodeType = 'varAssignDef' then
  begin
    IdN := Lhs.ChildByField('name');
    if IdN.IsNull and (Lhs.NamedChildCount > 0) then IdN := Lhs.NamedChild(0);
    if not IdN.IsNull then Result := AVars.IndexOf(LowerCase(NodeStr(IdN, ASrc)));
  end;
  { indexed/qualified writes (a[i] := / x.f :=) are NOT whole-var definitions }
end;

function AssignmentBaseIndex(const ANode: TTSNode; const ASrc: TBytes;
  AVars: TRoutineVarTable): Integer;
begin
  Result := LeftmostBaseVar(ANode.ChildByField('lhs'), ASrc, AVars);
end;

{ ----- TDefiniteAssignment ----- }

constructor TDefiniteAssignment.Create(AVars: TRoutineVarTable; const ASrc: TBytes);
begin inherited Create; FVars := AVars; FSrc := ASrc; end;

function TDefiniteAssignment.Direction: TFlowDir; begin Result := fdForward; end;

function TDefiniteAssignment.Bottom: TDefAsgnVal;
var I: Integer;
begin
  { Bottom for MUST (intersection) is "all assigned"; MAY (union) is "none". }
  SetLength(Result.Must, FVars.Count); SetLength(Result.May, FVars.Count);
  for I := 0 to FVars.Count - 1 do begin Result.Must[I] := True; Result.May[I] := False; end;
end;

function TDefiniteAssignment.Boundary: TDefAsgnVal;
var I: Integer; V: TRoutineVar;
begin
  SetLength(Result.Must, FVars.Count); SetLength(Result.May, FVars.Count);
  for I := 0 to FVars.Count - 1 do
  begin
    V := FVars.Get(I);
    if V.Kind in [vkParamVar, vkParamConst, vkParamValue] then
    begin Result.Must[I] := True; Result.May[I] := True; end
    else begin Result.Must[I] := False; Result.May[I] := False; end;
    { captured-by-nested-routine locals: treated as assigned-on-entry (FP guard --
      a nested routine may assign them; prefer suppression over a false positive) }
    if V.Captured then begin Result.Must[I] := True; Result.May[I] := True; end;
  end;
end;

function TDefiniteAssignment.Join(const A, B: TDefAsgnVal): TDefAsgnVal;
var I: Integer;
begin
  SetLength(Result.Must, FVars.Count); SetLength(Result.May, FVars.Count);
  for I := 0 to FVars.Count - 1 do
  begin
    Result.Must[I] := A.Must[I] and B.Must[I]; { intersection }
    Result.May[I]  := A.May[I] or B.May[I];     { union }
  end;
end;

function TDefiniteAssignment.Transfer(const ABlock: TCfgBlock; const AIn: TDefAsgnVal): TDefAsgnVal;
var
  I, J, Tgt, Idx: Integer; It: TCfgItem; Reads, CallDefs: TList<Integer>;
begin
  SetLength(Result.Must, FVars.Count); SetLength(Result.May, FVars.Count);
  for I := 0 to FVars.Count - 1 do begin Result.Must[I] := AIn.Must[I]; Result.May[I] := AIn.May[I]; end;
  { synthetic entry defs (foreach iterator) }
  for J := 0 to High(ABlock.EntryDefs) do
  begin
    Idx := FVars.IndexOf(ABlock.EntryDefs[J]);
    if Idx >= 0 then begin Result.Must[Idx] := True; Result.May[Idx] := True; end;
  end;
  Reads := TList<Integer>.Create; CallDefs := TList<Integer>.Create;
  try
    for I := 0 to ABlock.Items.Count - 1 do
    begin
      It := ABlock.Items[I];
      Reads.Clear; CallDefs.Clear;
      if It.Node.NodeType = 'assignment' then
      begin
        { reads on the rhs happen BEFORE the def of the lhs }
        CollectReadsAndCallDefs(It.Node.ChildByField('rhs'), FSrc, FVars, Reads, CallDefs);
        { a var passed to a call (or @x) may be a var/out param the callee assigns
          (e.g. SetLength(Result,..)); treat as assigned to suppress the finding }
        for J := 0 to CallDefs.Count - 1 do begin Result.Must[CallDefs[J]] := True; Result.May[CallDefs[J]] := True; end;
        { base index: a partial write (Result.f := / a[i] :=) still defines the base }
        Tgt := AssignmentBaseIndex(It.Node, FSrc, FVars);
        if Tgt >= 0 then begin Result.Must[Tgt] := True; Result.May[Tgt] := True; end;
      end
      else
      begin
        CollectReadsAndCallDefs(It.Node, FSrc, FVars, Reads, CallDefs);
        { a var passed to a call (or @x) may be a var/out param the callee assigns
          (e.g. SetLength(Result,..)); treat as assigned to suppress the finding }
        for J := 0 to CallDefs.Count - 1 do begin Result.Must[CallDefs[J]] := True; Result.May[CallDefs[J]] := True; end;
        if (It.Node.NodeType = 'exprCall')
           and (NodeText(It.Node.ChildByField('entity'), FSrc) = 'exit') then
        begin
          Idx := FVars.IndexOf('result');
          if Idx >= 0 then begin Result.Must[Idx] := True; Result.May[Idx] := True; end;
        end;
      end;
    end;
  finally
    Reads.Free; CallDefs.Free;
  end;
end;

function TDefiniteAssignment.Equals(const A, B: TDefAsgnVal): Boolean;
var I: Integer;
begin
  Result := False;
  if (Length(A.Must) <> Length(B.Must)) or (Length(A.May) <> Length(B.May)) then Exit;
  for I := 0 to High(A.Must) do
    if (A.Must[I] <> B.Must[I]) or (A.May[I] <> B.May[I]) then Exit;
  Result := True;
end;

{ ----- TFreedState ----- }

constructor TFreedState.Create(AVars: TRoutineVarTable; const ASrc: TBytes);
begin inherited Create; FVars := AVars; FSrc := ASrc; end;

function TFreedState.Direction: TFlowDir; begin Result := fdForward; end;

function TFreedState.Bottom: TFreedVal;
var I: Integer;
begin
  { Bottom for MUST (intersection) is "all dangling"; MAY (union) is "none". }
  SetLength(Result.Must, FVars.Count); SetLength(Result.May, FVars.Count);
  for I := 0 to FVars.Count - 1 do begin Result.Must[I] := True; Result.May[I] := False; end;
end;

function TFreedState.Boundary: TFreedVal;
var I: Integer;
begin
  { on entry no var is dangling (params/locals start un-freed). }
  SetLength(Result.Must, FVars.Count); SetLength(Result.May, FVars.Count);
  for I := 0 to FVars.Count - 1 do begin Result.Must[I] := False; Result.May[I] := False; end;
end;

function TFreedState.Join(const A, B: TFreedVal): TFreedVal;
var I: Integer;
begin
  SetLength(Result.Must, FVars.Count); SetLength(Result.May, FVars.Count);
  for I := 0 to FVars.Count - 1 do
  begin
    Result.Must[I] := A.Must[I] and B.Must[I]; { dangling on EVERY incoming path }
    Result.May[I]  := A.May[I] or B.May[I];    { dangling on SOME incoming path }
  end;
end;

function TFreedState.Transfer(const ABlock: TCfgBlock; const AIn: TFreedVal): TFreedVal;
var
  I, Tgt, FreedV: Integer; It: TCfgItem; Kind: TFreeKind;
begin
  SetLength(Result.Must, FVars.Count); SetLength(Result.May, FVars.Count);
  for I := 0 to FVars.Count - 1 do begin Result.Must[I] := AIn.Must[I]; Result.May[I] := AIn.May[I]; end;
  for I := 0 to ABlock.Items.Count - 1 do
  begin
    It := ABlock.Items[I];
    if It.Opaque then Continue; { with-body: conservative, state unchanged }
    FreedV := DetectFreedVarKind(It.Node, FSrc, FVars, Kind);
    if FreedV >= 0 then
    begin
      case Kind of
        fkRawFree: begin Result.Must[FreedV] := True;  Result.May[FreedV] := True;  end;  { now dangling }
        fkNiling:  begin Result.Must[FreedV] := False; Result.May[FreedV] := False; end;  { nil-ed / safe }
      end;
      Continue; { a free site is not also a whole-var assignment }
    end;
    if It.Node.NodeType = 'assignment' then
    begin
      Tgt := AssignmentTargetIndex(It.Node, FSrc, FVars); { whole-identifier lhs only }
      if Tgt >= 0 then begin Result.Must[Tgt] := False; Result.May[Tgt] := False; end; { re-pointed }
    end;
  end;
end;

function TFreedState.Equals(const A, B: TFreedVal): Boolean;
var I: Integer;
begin
  Result := False;
  if (Length(A.Must) <> Length(B.Must)) or (Length(A.May) <> Length(B.May)) then Exit;
  for I := 0 to High(A.Must) do
    if (A.Must[I] <> B.Must[I]) or (A.May[I] <> B.May[I]) then Exit;
  Result := True;
end;

{ ----- TLiveness ----- }

constructor TLiveness.Create(AVars: TRoutineVarTable; const ASrc: TBytes);
begin inherited Create; FVars := AVars; FSrc := ASrc; end;

function TLiveness.Direction: TFlowDir; begin Result := fdBackward; end;

function TLiveness.Bottom: TArray<Boolean>;
var I: Integer;
begin
  SetLength(Result, FVars.Count);
  for I := 0 to FVars.Count - 1 do Result[I] := False;
end;

function TLiveness.Boundary: TArray<Boolean>;
var I: Integer; V: TRoutineVar;
begin
  SetLength(Result, FVars.Count);
  for I := 0 to FVars.Count - 1 do
  begin
    V := FVars.Get(I);
    { the caller observes out/var params and the function Result after return }
    Result[I] := V.Kind in [vkParamOut, vkParamVar, vkResult];
  end;
end;

function TLiveness.Join(const A, B: TArray<Boolean>): TArray<Boolean>;
var I: Integer;
begin
  SetLength(Result, FVars.Count);
  for I := 0 to FVars.Count - 1 do Result[I] := A[I] or B[I];
end;

function TLiveness.Transfer(const ABlock: TCfgBlock; const AIn: TArray<Boolean>): TArray<Boolean>;
var I, J, Tgt: Integer; It: TCfgItem; Reads, CallDefs: TList<Integer>;
begin
  Result := Copy(AIn); { AIn is the block's live-OUT; we return live-IN }
  Reads := TList<Integer>.Create; CallDefs := TList<Integer>.Create;
  try
    for I := ABlock.Items.Count - 1 downto 0 do
    begin
      It := ABlock.Items[I];
      if It.Opaque then
      begin
        for J := 0 to FVars.Count - 1 do
          if FVars.Get(J).Kind = vkLocal then Result[J] := True;
        Continue;
      end;
      Reads.Clear; CallDefs.Clear;
      if It.Node.NodeType = 'assignment' then
      begin
        Tgt := AssignmentTargetIndex(It.Node, FSrc, FVars); { whole-var def kills }
        if Tgt >= 0 then Result[Tgt] := False;
        CollectReadsAndCallDefs(It.Node.ChildByField('rhs'), FSrc, FVars, Reads, CallDefs);
        for J := 0 to Reads.Count - 1 do Result[Reads[J]] := True;     { gen reads }
        for J := 0 to CallDefs.Count - 1 do Result[CallDefs[J]] := True; { rhs call args are uses }
        { a partial write (a[i] := / x.f :=) reads its base + index -> live }
        if Tgt < 0 then
        begin
          Reads.Clear; CallDefs.Clear;
          CollectReadsAndCallDefs(It.Node.ChildByField('lhs'), FSrc, FVars, Reads, CallDefs);
          for J := 0 to Reads.Count - 1 do Result[Reads[J]] := True;
          for J := 0 to CallDefs.Count - 1 do Result[CallDefs[J]] := True;
        end;
      end
      else
      begin
        CollectReadsAndCallDefs(It.Node, FSrc, FVars, Reads, CallDefs);
        { for liveness a call argument IS a use (callee may read it) }
        for J := 0 to Reads.Count - 1 do Result[Reads[J]] := True;
        for J := 0 to CallDefs.Count - 1 do Result[CallDefs[J]] := True;
      end;
    end;
  finally Reads.Free; CallDefs.Free; end;
end;

function TLiveness.Equals(const A, B: TArray<Boolean>): Boolean;
var I: Integer;
begin
  Result := False;
  if Length(A) <> Length(B) then Exit;
  for I := 0 to High(A) do if A[I] <> B[I] then Exit;
  Result := True;
end;

{ ----- escape / object-leak helpers + TEscape ----- }

function ExprIsConstructor(const N: TTSNode; const ASrc: TBytes): Boolean;
var Ent: TTSNode;
begin
  Result := False;
  if N.IsNull then Exit;
  if N.NodeType = 'exprDot' then
    Exit(NodeText(N.ChildByField('rhs'), ASrc) = 'create');
  if N.NodeType = 'exprCall' then
  begin
    Ent := N.ChildByField('entity');
    if (not Ent.IsNull) and (Ent.NodeType = 'exprDot') then
      Exit(NodeText(Ent.ChildByField('rhs'), ASrc) = 'create');
  end;
end;

function DetectFreedVar(const ANode: TTSNode; const ASrc: TBytes; AVars: TRoutineVarTable): Integer;
var Inner, Ent, ArgsN: TTSNode; M: string;
begin
  Result := -1;
  if ANode.IsNull then Exit;
  Inner := ANode;
  if (Inner.NodeType = 'statement') and (Inner.NamedChildCount > 0) then Inner := Inner.NamedChild(0);
  if Inner.NodeType = 'exprDot' then
  begin
    M := NodeText(Inner.ChildByField('rhs'), ASrc);
    if (M = 'free') or (M = 'disposeof') then
      Exit(LeftmostBaseVar(Inner.ChildByField('lhs'), ASrc, AVars));
  end;
  if Inner.NodeType = 'exprCall' then
  begin
    Ent := Inner.ChildByField('entity');
    if (not Ent.IsNull) and (Ent.NodeType = 'exprDot') then
    begin
      M := NodeText(Ent.ChildByField('rhs'), ASrc);
      if (M = 'free') or (M = 'disposeof') then
        Exit(LeftmostBaseVar(Ent.ChildByField('lhs'), ASrc, AVars));
    end;
    if (not Ent.IsNull) and (Ent.NodeType = 'identifier') and (NodeText(Ent, ASrc) = 'freeandnil') then
    begin
      ArgsN := Inner.ChildByField('args');
      if (not ArgsN.IsNull) and (ArgsN.NamedChildCount > 0) then
        Exit(LeftmostBaseVar(ArgsN.NamedChild(0), ASrc, AVars));
    end;
  end;
end;

function DetectFreedVarKind(const ANode: TTSNode; const ASrc: TBytes; AVars: TRoutineVarTable;
  out AKind: TFreeKind): Integer;
var Inner, Ent, ArgsN: TTSNode; M: string;
begin
  Result := -1;
  AKind := fkRawFree;
  if ANode.IsNull then Exit;
  Inner := ANode;
  if (Inner.NodeType = 'statement') and (Inner.NamedChildCount > 0) then Inner := Inner.NamedChild(0);
  if Inner.NodeType = 'exprDot' then
  begin
    M := NodeText(Inner.ChildByField('rhs'), ASrc);
    if (M = 'free') or (M = 'disposeof') then
    begin
      AKind := fkRawFree; { raw .Free / .DisposeOf: object freed, pointer left dangling }
      Exit(LeftmostBaseVar(Inner.ChildByField('lhs'), ASrc, AVars));
    end;
  end;
  if Inner.NodeType = 'exprCall' then
  begin
    Ent := Inner.ChildByField('entity');
    if (not Ent.IsNull) and (Ent.NodeType = 'exprDot') then
    begin
      M := NodeText(Ent.ChildByField('rhs'), ASrc);
      if (M = 'free') or (M = 'disposeof') then
      begin
        AKind := fkRawFree;
        Exit(LeftmostBaseVar(Ent.ChildByField('lhs'), ASrc, AVars));
      end;
    end;
    if (not Ent.IsNull) and (Ent.NodeType = 'identifier') and (NodeText(Ent, ASrc) = 'freeandnil') then
    begin
      ArgsN := Inner.ChildByField('args');
      if (not ArgsN.IsNull) and (ArgsN.NamedChildCount > 0) then
      begin
        AKind := fkNiling; { FreeAndNil: object freed AND pointer nil-ed -> safe }
        Exit(LeftmostBaseVar(ArgsN.NamedChild(0), ASrc, AVars));
      end;
    end;
  end;
end;

function CollectCallArgs(const ANode: TTSNode; const ASrc: TBytes;
  AVars: TRoutineVarTable): TArray<TCallArgRef>;
var Acc: TList<TCallArgRef>;
  procedure Walk(const N: TTSNode);
  var I, VI: Integer; Ent, Args, Arg: TTSNode; Nm: string; Rec: TCallArgRef;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'exprCall' then
    begin
      Ent := N.ChildByField('entity');
      if (not Ent.IsNull) and (Ent.NodeType = 'identifier') then
        Nm := Trim(NodeStr(Ent, ASrc)) { original case: the store keys on it }
      else Nm := ''; { method call (exprDot entity) -> not resolvable by bare name }
      Args := N.ChildByField('args');
      if not Args.IsNull then
        for I := 0 to Args.NamedChildCount - 1 do
        begin
          Arg := Args.NamedChild(I);
          VI := LeftmostBaseVar(Arg, ASrc, AVars);
          if VI >= 0 then
          begin Rec.CalleeName := Nm; Rec.ArgIdx := I; Rec.VarIdx := VI; Acc.Add(Rec); end;
          Walk(Arg); { nested calls inside the argument }
        end;
      Walk(Ent);   { the receiver may itself contain a call }
      Exit;
    end;
    for I := 0 to N.NamedChildCount - 1 do Walk(N.NamedChild(I));
  end;
begin
  Acc := TList<TCallArgRef>.Create;
  try
    Walk(ANode);
    Result := Acc.ToArray;
  finally Acc.Free; end;
end;

constructor TEscape.Create(AVars: TRoutineVarTable; const ASrc: TBytes; AOwns: TCallArgOwns);
begin inherited Create; FVars := AVars; FSrc := ASrc; FOwns := AOwns; end;

function TEscape.Direction: TFlowDir; begin Result := fdForward; end;

function TEscape.Bottom: TArray<Boolean>;
var I: Integer;
begin SetLength(Result, FVars.Count); for I := 0 to FVars.Count - 1 do Result[I] := False; end;

function TEscape.Boundary: TArray<Boolean>;
begin Result := Bottom; end;

function TEscape.Join(const A, B: TArray<Boolean>): TArray<Boolean>;
var I: Integer;
begin
  SetLength(Result, FVars.Count);
  for I := 0 to FVars.Count - 1 do Result[I] := A[I] or B[I]; { may-open: union }
end;

function TEscape.Transfer(const ABlock: TCfgBlock; const AIn: TArray<Boolean>): TArray<Boolean>;
var
  I, Tgt, FreedV, SrcIdx: Integer; It: TCfgItem; Rhs: TTSNode;
  CA: TCallArgRef; Owns: Boolean;
begin
  Result := Copy(AIn);
  begin
    for I := 0 to ABlock.Items.Count - 1 do
    begin
      It := ABlock.Items[I];
      FreedV := DetectFreedVar(It.Node, FSrc, FVars);
      if FreedV >= 0 then Result[FreedV] := False;            { freed }
      { passed to a call -> escaped, UNLESS the oracle proves the callee non-owning }
      for CA in CollectCallArgs(It.Node, FSrc, FVars) do
      begin
        if CA.VarIdx = FreedV then Continue;
        Owns := True;
        if Assigned(FOwns) and (CA.CalleeName <> '') then Owns := FOwns(CA.CalleeName, CA.ArgIdx);
        if Owns then Result[CA.VarIdx] := False;
      end;
      if It.Node.NodeType = 'assignment' then
      begin
        Rhs := It.Node.ChildByField('rhs');
        Tgt := AssignmentTargetIndex(It.Node, FSrc, FVars);
        if (Tgt >= 0) and (FVars.Get(Tgt).Kind = vkLocal) then
        begin
          if ExprIsConstructor(Rhs, FSrc) then Result[Tgt] := True   { created }
          else if (not Rhs.IsNull) and (Rhs.NodeType = 'identifier') then
          begin
            SrcIdx := FVars.IndexOf(LowerCase(NodeStr(Rhs, FSrc)));
            if SrcIdx >= 0 then
            begin Result[Tgt] := Result[SrcIdx]; Result[SrcIdx] := False; end { alias: ownership moves }
            else Result[Tgt] := False;
          end
          else Result[Tgt] := False;                                { reassigned to other }
        end
        else if (not Rhs.IsNull) and (Rhs.NodeType = 'identifier') then
        begin
          { lhs is Result / a field / a partial write -> a bare local rhs escapes }
          SrcIdx := FVars.IndexOf(LowerCase(NodeStr(Rhs, FSrc)));
          if SrcIdx >= 0 then Result[SrcIdx] := False;
        end;
      end;
    end;
  end;
end;

function TEscape.Equals(const A, B: TArray<Boolean>): Boolean;
var I: Integer;
begin
  Result := False;
  if Length(A) <> Length(B) then Exit;
  for I := 0 to High(A) do if A[I] <> B[I] then Exit;
  Result := True;
end;

end.
