unit DRagLint.Diagnostics.FlowChecks;

{ Flow-sensitive lint checks (M2): runs the data-flow analyses per routine and
  maps results to TLintFinding. Mirrors the TAstChecker.CheckXxx integration
  (parse cache + optional ISymbolStore, nil-safe). Definite violations =
  warning, possible violations = info. }

interface

uses
  System.SysUtils,
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

class function TFlowChecker.Check(const AFile: string; const AStore: ISymbolStore;
  AFileId: Int64): TArray<TLintFinding>;
var
  PF: TParsedFile;
  Findings: TList<TLintFinding>;
  Procs: TArray<TTSNode>;
  PI: Integer;

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
    LiveAna: IDataFlowAnalysis<TArray<Boolean>>;
    LIn, LOut: TArray<TArray<Boolean>>;
    ReadAny, AsgnAny, Live: TArray<Boolean>;
  begin
    Cfg := TCfgBuilder.Build(AProc, PF.Src);
    Vars := TRoutineVarTable.Build(AProc, PF.Src);
    try
      if Cfg.Skipped or (Vars.Count = 0) then Exit;
      Ana := TDefiniteAssignment.Create(Vars, PF.Src);
      if not TDataFlowSolver<TDefAsgnVal>.Solve(Cfg, Ana, AIn, AOut) then Exit;

      Reads := TList<Integer>.Create; CallDefs := TList<Integer>.Create;
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
            if (V.Kind = vkLocal) and AsgnAny[I] and (not ReadAny[I]) then
              Emit('write-only-local', 'info',
                Format('Local "%s" is assigned but never read.', [V.Name]),
                V.DeclLine, V.DeclCol);
          end;
        end;

      finally Reads.Free; CallDefs.Free; end;
    finally Cfg.Free; Vars.Free; end;
  end;

begin
  Result := nil;
  PF := TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Findings := TList<TLintFinding>.Create;
  try
    Procs := CfgFindProcs(PF.Tree.RootNode);
    for PI := 0 to High(Procs) do CheckRoutine(Procs[PI]);
    Result := Findings.ToArray;
  finally
    Findings.Free;
  end;
end;

end.
