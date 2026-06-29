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
  TRoutineVar = record
    Name    : string;
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

/// <summary>Lowercased identifier text of N, trimmed.</summary>
function NodeText(const N: TTSNode; const ASrc: TBytes): string;

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
    if N.NodeType = 'defProc' then Exit; { nested routine: own scope }
    if N.NodeType = 'declVars' then AddDeclVars(N);
    if N.NodeType = 'assignment' then
    begin
      Lhs := N.ChildByField('lhs');
      if (not Lhs.IsNull) and (Lhs.NodeType = 'varAssignDef') then
      begin
        IdN := Lhs.ChildByField('name');
        if IdN.IsNull and (Lhs.NamedChildCount > 0) then IdN := Lhs.NamedChild(0);
        if not IdN.IsNull then
        begin
          R := Default(TRoutineVar);
          R.Name := LowerCase(NodeStr(IdN, ASrc));
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
      if N.NamedChild(I).NodeType = 'defProc' then MarkCaptures(N.NamedChild(I), ADepth + 1)
      else MarkCaptures(N.NamedChild(I), ADepth);
  end;

begin
  Tbl := TRoutineVarTable.Create;
  ResultIdx := -1;
  Header := AProc.ChildByField('header');
  if not Header.IsNull then
  begin
    Args := Header.ChildByField('args');
    AddArgs(Args);
    Ret := Header.ChildByField('type');
    if not Ret.IsNull then
    begin
      RV := Default(TRoutineVar);
      RV.Name := 'result'; RV.Kind := vkResult; RV.TypeText := Trim(NodeStr(Ret, ASrc));
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
          if Arg.NodeType = 'identifier' then
          begin
            Idx := AVars.IndexOf(LowerCase(NodeStr(Arg, ASrc)));
            if (Idx >= 0) and (ACallDefs.IndexOf(Idx) < 0) then ACallDefs.Add(Idx);
          end
          else
            Walk(Arg, False);
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
var Cur, Nxt, IdN: TTSNode; Guard: Integer;
begin
  Result := -1;
  Cur := ANode.ChildByField('lhs');
  Guard := 0;
  while (not Cur.IsNull) and (Guard < 32) do
  begin
    Inc(Guard);
    if Cur.NodeType = 'identifier' then
      Exit(AVars.IndexOf(LowerCase(NodeStr(Cur, ASrc))));
    if Cur.NodeType = 'varAssignDef' then
    begin
      IdN := Cur.ChildByField('name');
      if IdN.IsNull and (Cur.NamedChildCount > 0) then IdN := Cur.NamedChild(0);
      if IdN.IsNull then Exit(-1);
      Exit(AVars.IndexOf(LowerCase(NodeStr(IdN, ASrc))));
    end;
    { exprDot / index / call: descend to the base (lhs, else entity, else child 0) }
    Nxt := Cur.ChildByField('lhs');
    if Nxt.IsNull then Nxt := Cur.ChildByField('entity');
    if Nxt.IsNull and (Cur.NamedChildCount > 0) then Nxt := Cur.NamedChild(0);
    if Nxt.IsNull then Exit(-1);
    Cur := Nxt;
  end;
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
        for J := 0 to CallDefs.Count - 1 do Result.May[CallDefs[J]] := True;
        { base index: a partial write (Result.f := / a[i] :=) still defines the base }
        Tgt := AssignmentBaseIndex(It.Node, FSrc, FVars);
        if Tgt >= 0 then begin Result.Must[Tgt] := True; Result.May[Tgt] := True; end;
      end
      else
      begin
        CollectReadsAndCallDefs(It.Node, FSrc, FVars, Reads, CallDefs);
        for J := 0 to CallDefs.Count - 1 do Result.May[CallDefs[J]] := True;
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

end.
