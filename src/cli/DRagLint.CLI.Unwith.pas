unit DRagLint.CLI.Unwith;

// ---------------------------------------------------------------------------
// The `unwith` verb's run and its output; the analysis and the rewrite are DRagLint.Refactor.Unwith.
// ---------------------------------------------------------------------------

interface

uses
  System.SysUtils,
  DRagLint.Core.Interfaces;

type
  /// <summary>What the `unwith` command line asks for.</summary>
  TUnwithRunOptions = record
    /// <summary>--in: one file; '' = every .pas / .dpr of the project index.</summary>
    InFile: string;
    /// <summary>--line: only the with on this line of --in; 0 = all.</summary>
    Line: Integer;
    /// <summary>--apply: write the candidates through the gate; False = --plan.</summary>
    Apply: Boolean;
    /// <summary>--project: the .dproj the gate builds (required with --apply).</summary>
    Project: string;
    /// <summary>--platform.</summary>
    Platform: string;
    /// <summary>--db.</summary>
    Db: string;
    /// <summary>--no-backup.</summary>
    NoBackup: Boolean;
    /// <summary>--json.</summary>
    Json: Boolean;
  end;

/// <summary>Runs `unwith`: the verdict on every with statement in scope, then (with Apply) the gated rewrite.</summary>
/// <param name="pOpts">The command line.</param>
/// <param name="pStore">The project index.</param>
/// <param name="pLib">The platform library; nil = ancestors outside the project refuse.</param>
/// <returns>0 = plan printed, or applied and proved. 1 = the with on --line refused, nothing to apply, or the gate or the
/// after-proof refused and rolled back. 2 = a rollback failed: the project may be PARTLY changed.</returns>
function RunUnwith(const pOpts: TUnwithRunOptions; const pStore, pLib: ISymbolStore): Integer;

implementation

uses
  System.StrUtils, System.Generics.Collections, System.IOUtils, System.JSON,
  DRagLint.Diagnostics.ParseCache, DRagLint.Refactor.Unwith;

function RunUnwith(const pOpts: TUnwithRunOptions; const pStore, pLib: ISymbolStore): Integer;
var
  Plans: TArray<TUnwithFilePlan>;
  ByKind: TDictionary<string, Integer>;
  Candidates, Refused: Integer;
  Detail: Boolean;

  procedure PrintSite(const pFile: string; const S: TUnwithSite);
  begin
    if S.Refusal <> '' then
      Writeln(Format('%s:%d: refused %s: %s', [pFile, S.Line, S.Refusal, S.Detail]))
    else
    begin
      var Pref:= 0;
      for var B: TUnwithBinding in S.Bindings do
        if B.Prefixed then Inc(Pref);
      Writeln(Format('%s:%d: candidate: with %s (%s): %d prefixed, %d left bare',
        [pFile, S.Line, S.Target, S.TargetType, Pref, Length(S.Bindings) - Pref]));
      if Detail then
        for var B: TUnwithBinding in S.Bindings do
          Writeln(Format('  %d:%d %s %s  -> %s', [B.Line, B.Col, if B.Prefixed then 'prefix' else 'keep  ', B.Name,
            if B.Before = '' then '(not bound by the index)' else B.Before]));
    end;
  end;

  function JsonOf(const pApply: TUnwithApplyResult; pApplied: Boolean): TJSONObject;
  begin
    Result:= TJSONObject.Create;
    Result.AddPair('schema', 'unwith/1');
    Result.AddPair('candidates', TJSONNumber.Create(Candidates));
    Result.AddPair('refused', TJSONNumber.Create(Refused));
    var Kinds:= TJSONObject.Create;
    for var K: TPair<string, Integer> in ByKind do Kinds.AddPair(K.Key, TJSONNumber.Create(K.Value));
    Result.AddPair('refused_by_kind', Kinds);
    var Sites:= TJSONArray.Create;
    for var P: TUnwithFilePlan in Plans do
      for var S: TUnwithSite in P.Sites do
      begin
        var O:= TJSONObject.Create;
        O.AddPair('file', P.FilePath);
        O.AddPair('line', TJSONNumber.Create(S.Line));
        O.AddPair('target', S.Target);
        O.AddPair('type', S.TargetType);
        O.AddPair('refusal', S.Refusal);
        O.AddPair('detail', S.Detail);
        var Bs:= TJSONArray.Create;
        for var B: TUnwithBinding in S.Bindings do
        begin
          var BO:= TJSONObject.Create;
          BO.AddPair('line', TJSONNumber.Create(B.Line));
          BO.AddPair('col', TJSONNumber.Create(B.Col));
          BO.AddPair('name', B.Name);
          BO.AddPair('prefixed', TJSONBool.Create(B.Prefixed));
          BO.AddPair('before', B.Before);
          Bs.AddElement(BO);
        end;
        O.AddPair('bindings', Bs);
        Sites.AddElement(O);
      end;
    Result.AddPair('sites', Sites);
    if pApplied then
    begin
      var A:= TJSONObject.Create;
      A.AddPair('applied', TJSONBool.Create(pApply.Applied));
      A.AddPair('refusal', pApply.Refusal);
      A.AddPair('detail', pApply.Detail);
      A.AddPair('proof_points', TJSONNumber.Create(pApply.ProofPoints));
      var Rb:= TJSONArray.Create;
      for var R: string in pApply.Rebinds do Rb.Add(R);
      A.AddPair('rebinds', Rb);
      Result.AddPair('apply', A);
    end;
  end;

begin
  Result:= 0;
  Detail:= pOpts.InFile <> '';
  Plans:= nil;
  Candidates:= 0;
  Refused:= 0;
  ByKind:= TDictionary<string, Integer>.Create;
  try
    var Files: TArray<string>:= nil;
    if pOpts.InFile <> '' then Files:= [ExpandFileName(pOpts.InFile)]
    else
      for var Id: Int64 in pStore.GetAllFileIds do
      begin
        var P:= pStore.GetFilePath(Id);
        if MatchText(ExtractFileExt(P), ['.pas', '.dpr']) and TFile.Exists(P) then Files:= Files + [P];
      end;
    for var F: string in Files do
    begin
      var Plan:= UnwithPlanFile(pStore, pLib, F, pOpts.Line);
      TAstParseCache.Clear;
      if Length(Plan.Sites) = 0 then Continue;
      Plans:= Plans + [Plan];
      for var S: TUnwithSite in Plan.Sites do
      begin
        if S.Refusal = '' then Inc(Candidates)
        else
        begin
          Inc(Refused);
          var N: Integer;
          if not ByKind.TryGetValue(S.Refusal, N) then N:= 0;
          ByKind.AddOrSetValue(S.Refusal, N + 1);
        end;
        if not pOpts.Json then PrintSite(F, S);
      end;
    end;
    if not pOpts.Json then
    begin
      Writeln(Format('unwith: %d with statement(s): %d candidate(s), %d refused', [Candidates + Refused, Candidates, Refused]));
      var Keys:= ByKind.Keys.ToArray;
      TArray.Sort<string>(Keys);
      for var K: string in Keys do Writeln(Format('  refused %-26s %d', [K, ByKind[K]]));
    end;
    var Applied: TUnwithApplyResult:= Default(TUnwithApplyResult);
    if pOpts.Apply then
    begin
      var AO: TUnwithApplyOptions:= Default(TUnwithApplyOptions);
      AO.Project:= pOpts.Project;
      AO.Platform:= pOpts.Platform;
      AO.Db:= pOpts.Db;
      AO.NoBackup:= pOpts.NoBackup;
      Applied:= UnwithApply(Plans, AO);
      if Applied.Applied then
      begin
        if not pOpts.Json then
          Writeln(Format('unwith: applied: %d file(s) written, the project builds, %d ref(s) bind as before. Reindex the project.',
            [Length(Applied.Written), Applied.ProofPoints]));
      end
      else
      begin
        Result:= if Applied.RollbackFailed then 2 else 1;
        if not pOpts.Json then
        begin
          Writeln(Format('unwith: refused %s: %s', [Applied.Refusal, Applied.Detail]));
          for var R: string in Applied.Rebinds do Writeln('  rebind ', R);
        end;
      end;
    end
    else if (pOpts.Line > 0) and (Refused > 0) then Result:= 1;
    if not pOpts.Json then
    begin
      if not pOpts.Apply then
        Writeln('unwith: --plan writes nothing and proves the BEFORE side only; --apply adds the build and the re-index that proves the after side.');
    end
    else
    begin
      var J:= JsonOf(Applied, pOpts.Apply);
      try
        Writeln(J.ToJSON);
      finally
        J.Free;
      end;
    end;
  finally
    ByKind.Free;
  end;
end;

end.