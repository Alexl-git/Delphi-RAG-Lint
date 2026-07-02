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
  begin
    Cfg := TCfgBuilder.Build(AProc, PF.Src);
    Vars := TRoutineVarTable.Build(AProc, PF.Src);
    try
      if Cfg.Skipped or (Vars.Count = 0) then Exit;
      Ana := TDefiniteAssignment.Create(Vars, PF.Src);
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
              CollectReadsAndCallDefs(It.Node.ChildByField('rhs'), PF.Src, Vars, Reads, CallDefs)
            else
              CollectReadsAndCallDefs(It.Node, PF.Src, Vars, Reads, CallDefs);
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
        for I := 0 to Vars.Count - 1 do
        begin
          V := Vars.Get(I);
          if (V.Kind = vkParamOut) and (not ExitVal.Must[I]) then
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
                 and ExprIsConstructor(It.Node.ChildByField('rhs'), PF.Src) then
              begin
                CreateRow[Tgt] := Integer(It.Node.StartPoint.Row) + 1;
                CreateCol[Tgt] := Integer(It.Node.StartPoint.Column) + 1;
              end;
            end;
          { a created local still may-open at the routine exit -> possible leak }
          for I := 0 to Vars.Count - 1 do
            if (Vars.Get(I).Kind = vkLocal) and (CreateRow[I] > 0) and EIn2[Cfg.ExitIdx][I] then
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
