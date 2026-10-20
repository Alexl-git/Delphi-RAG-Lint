unit DRagLint.CLI.CycleFix;

// ---------------------------------------------------------------------------
// `drag-lint cycles --fix` -- the dry run (E18 Task 8): pick ONE circular group,
// take the planner's plan for it (DRagLint.Report.CyclePlan.VisitCyclePlans),
// add the mechanisability gate (stale-file, outside-roots, manual-edit) and
// print the verdict as the playbook text or as `cycle-fix/1` JSON
// (docs\superpowers\plans\2026-10-10-auto-cycle-fix.md, contract 4.4).
// Writes NOTHING. Applying (--apply) arrives with Tasks 9-12.
// ---------------------------------------------------------------------------

interface

uses
  System.Generics.Collections,
  DRagLint.Core.Interfaces, DRagLint.Report.CyclePlan;

type
  /// <summary>The `cycles --fix` flags, as DoCycles parsed them.</summary>
  TCycleFixOptions = record
    /// <summary>--project: the .dproj (or .dpr) whose own roots bound the edit.</summary>
    Project: string;
    /// <summary>--db: the index of that project.</summary>
    Db: string;
    /// <summary>--platform, '' = win64; only echoed in the JSON.</summary>
    Platform: string;
    /// <summary>--apply (Tasks 9-12; refused with exit 2 today).</summary>
    Apply: Boolean;
    /// <summary>--no-backup (apply only).</summary>
    NoBackup: Boolean;
    /// <summary>--no-reindex (apply only).</summary>
    NoReindex: Boolean;
    /// <summary>--no-compile: skip the baseline build (the dry run has none yet).</summary>
    NoCompile: Boolean;
    /// <summary>--cycle: 1-based group; 0 = not given.</summary>
    CycleIndex: Integer;
    /// <summary>--unit: select the group holding this unit stem; '' = not given.</summary>
    UnitStem: string;
    /// <summary>--part: 'a', 'b', 'all' or '' (the group's default).</summary>
    Part: string;
    /// <summary>--format json.</summary>
    Json: Boolean;
  end;

/// <summary>The refusals the front end adds to the planner's own: outside-roots and manual-edit.</summary>
/// <param name="pView">The plan of one group.</param>
/// <param name="pOwnRoots">Absolute folders the project owns; empty = no restriction.</param>
/// <returns>One refusal per touched file outside every root, and one per manual edit the planner
/// did not already refuse.</returns>
/// <remarks>Pure: reads no file. stale-file needs the index and is added by RunCycleFix.</remarks>
function MechanisabilityGate(const pView: TCyclePlanView; const pOwnRoots: TArray<string>): TArray<TRefusal>;

/// <summary>Runs `cycles --fix` as a dry run and prints the result to stdout.</summary>
/// <param name="pOpts">The flags.</param>
/// <param name="pStore">Open index of the project; read only.</param>
/// <param name="pSccs">The circular groups, lower-case stems.</param>
/// <param name="pGraph">The uses graph the groups come from.</param>
/// <param name="pLibStore">Platform library index (read only) or nil.</param>
/// <returns>0 mechanical, 1 refused, 2 error (bad flags, no such group).</returns>
/// <remarks>Writes no file. The first mechanical group is chosen when neither --cycle nor --unit is given.</remarks>
function RunCycleFix(const pOpts: TCycleFixOptions; const pStore: ISymbolStore;
  const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph;
  const pLibStore: ISymbolStore = nil): Integer;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.DateUtils, System.Hash,
  System.StrUtils, DRagLint.Project.OwnRoots;

const
  CExitMechanical = 0;
  CExitRefused    = 1;
  CExitError      = 2;
  CDefaultPlatform = 'win64';
  CSchema          = 'cycle-fix/1';
  CNeedsProject    = 'ERROR: cycles --fix needs --project <X.dproj>';
  CVerdictOk       = 'Verdict: mechanical (dry run; add --apply to write)';
  CVerdictRefused  = 'Verdict: refused';

function NormDir(const pPath: string): string;
begin
  Result:= LowerCase(IncludeTrailingPathDelimiter(StringReplace(ExpandFileName(pPath), '/', '\', [rfReplaceAll])));
end;

function IsUnderRoots(const pFile: string; const pRoots: TArray<string>): Boolean;
begin
  var Norm:= LowerCase(StringReplace(ExpandFileName(pFile), '/', '\', [rfReplaceAll]));
  for var R in pRoots do
    if StartsStr(NormDir(R), Norm) then Exit(True);
  Result:= False;
end;

function MakeRefusal(const pKind, pSymbol, pFile, pReason: string; pLine: Integer): TRefusal;
begin
  Result.Kind    := pKind;
  Result.Symbol  := pSymbol;
  Result.FilePath:= pFile;
  Result.Reason  := pReason;
  Result.Line    := pLine;
end;

function MechanisabilityGate(const pView: TCyclePlanView; const pOwnRoots: TArray<string>): TArray<TRefusal>;
var
  L: TList<TRefusal>;

  function AlreadyRefused(const pFile: string; pLine: Integer): Boolean;
  begin
    for var R in pView.Refusals do
      if SameText(R.FilePath, pFile) and (R.Line = pLine) then Exit(True);
    Result:= False;
  end;

begin
  L:= TList<TRefusal>.Create;
  try
    if Length(pOwnRoots) > 0 then
      for var P in pView.TouchedPaths do
        if not IsUnderRoots(P, pOwnRoots) then
          L.Add(MakeRefusal('outside-roots', '', P, 'the plan edits a file outside the project''s own roots', 0));
    for var E in pView.Edits do
      if (E.Kind = 'manual') and not AlreadyRefused(E.FilePath, E.First) then
        L.Add(MakeRefusal('manual-edit', '', E.FilePath, 'this edit has to be made by hand', E.First));
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

// True when APath's on-disk (mtime, sha) is what the index recorded; the same basis as
// DRagLint.Core.Indexer.IndexFile (raw bytes, ANSI-decoded for the sha).
function FileStampIsCurrent(const pStore: ISymbolStore; const pPath: string): Boolean;
begin
  if not TFile.Exists(pPath) then Exit(False);
  var Sha  := THashSHA2.GetHashString(TEncoding.ANSI.GetString(TFile.ReadAllBytes(pPath)));
  var Mtime:= DateTimeToUnix(TFile.GetLastWriteTime(pPath), False);
  Result:= pStore.FileIsUpToDate(pPath, Mtime, Sha);
end;

function StaleRefusals(const pStore: ISymbolStore; const pView: TCyclePlanView): TArray<TRefusal>;
var
  L: TList<TRefusal>;
begin
  L:= TList<TRefusal>.Create;
  try
    for var P in pView.TouchedPaths do
      if MatchText(ExtractFileExt(P), ['.pas', '.dpr']) and not FileStampIsCurrent(pStore, P) then
        L.Add(MakeRefusal('stale-file', '', P,
          'the file changed after it was indexed; reindex the project (drag-lint index --project ...) and retry', 0));
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function IntfEdgeCount(const pUnits: TArray<string>; const pGraph: TCycleGraph; pIntfOnly: Boolean): Integer;
var
  Targets: TList<string>;
begin
  Result:= 0;
  for var A in pUnits do
    for var B in pUnits do
    begin
      if A = B then Continue;
      if pIntfOnly then
      begin
        if pGraph.IntfEdges.ContainsKey(A + '->' + B) then Inc(Result);
      end
      else if pGraph.Adj.TryGetValue(A, Targets) and Targets.Contains(B) then Inc(Result);
    end;
end;

function RefusalLine(const pR: TRefusal): string;
begin
  Result:= Format('  - %s: %s %s:%d -- %s', [pR.Kind, pR.Symbol, pR.FilePath, pR.Line, pR.Reason]);
end;

function StringsToJson(const pItems: TArray<string>): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var S in pItems do Result.Add(S);
end;

function CycleToJson(const pView: TCyclePlanView; const pRefusals: TArray<TRefusal>;
  const pGraph: TCycleGraph): TJSONObject;
var
  Arr: TJSONArray;
  O  : TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('n', TJSONNumber.Create(pView.CycleIndex));
  Result.AddPair('units', StringsToJson(pView.Units));
  Result.AddPair('interface_edges', TJSONNumber.Create(IntfEdgeCount(pView.Units, pGraph, True)));
  Result.AddPair('edges', TJSONNumber.Create(IntfEdgeCount(pView.Units, pGraph, False)));
  Result.AddPair('part', LowerCase(pView.Part));
  Result.AddPair('verdict', if Length(pRefusals) = 0 then 'mechanical' else 'refused');
  Result.AddPair('recipe', pView.Recipe);
  Result.AddPair('edge', pView.Edge);
  Arr:= TJSONArray.Create;
  for var R in pRefusals do
  begin
    O:= TJSONObject.Create;
    O.AddPair('kind', R.Kind);
    O.AddPair('symbol', R.Symbol);
    O.AddPair('file', R.FilePath);
    O.AddPair('line', TJSONNumber.Create(R.Line));
    O.AddPair('reason', R.Reason);
    Arr.AddElement(O);
  end;
  Result.AddPair('refusals', Arr);
  Arr:= TJSONArray.Create;
  for var M in pView.Moves do
  begin
    O:= TJSONObject.Create;
    O.AddPair('symbol', M.Symbol);
    O.AddPair('kind', M.Kind);
    O.AddPair('recipe', M.Recipe);
    O.AddPair('from', M.FromFile);
    O.AddPair('lines', TJSONArray.Create.Add(M.First).Add(M.Last));
    O.AddPair('to_unit', M.ToUnit);
    Arr.AddElement(O);
  end;
  Result.AddPair('moves', Arr);
  Arr:= TJSONArray.Create;
  for var U in pView.UseDecisions do
  begin
    O:= TJSONObject.Create;
    O.AddPair('file', U.FilePath);
    O.AddPair('unit', U.UnitName);
    O.AddPair('section', U.Section);
    O.AddPair('action', U.Action);
    Arr.AddElement(O);
  end;
  Result.AddPair('uses', Arr);
  Arr:= TJSONArray.Create;
  for var N in pView.NewUnits do
  begin
    O:= TJSONObject.Create;
    O.AddPair('unit', N.UnitName);
    O.AddPair('path', N.Path);
    Arr.AddElement(O);
  end;
  Result.AddPair('new_units', Arr);
  Arr:= TJSONArray.Create;
  for var E in pView.Edits do
  begin
    O:= TJSONObject.Create;
    O.AddPair('file', E.FilePath);
    O.AddPair('kind', E.Kind);
    O.AddPair('first', TJSONNumber.Create(E.First));
    O.AddPair('last', TJSONNumber.Create(E.Last));
    Arr.AddElement(O);
  end;
  Result.AddPair('edits', Arr);
  O:= TJSONObject.Create;
  O.AddPair('status', 'skipped');
  O.AddPair('files', TJSONNumber.Create(0));
  O.AddPair('errors', TJSONArray.Create);
  Result.AddPair('compile', O);
  O:= TJSONObject.Create;
  O.AddPair('status', 'skipped');
  O.AddPair('errors', TJSONArray.Create);
  Result.AddPair('baseline', O);
  Result.AddPair('repairs', TJSONArray.Create);
  Result.AddPair('written', TJSONArray.Create);
  Result.AddPair('backups', TJSONArray.Create);
  O:= TJSONObject.Create;
  O.AddPair('status', 'dry-run');
  O.AddPair('ms', TJSONNumber.Create(0));
  Result.AddPair('reindex', O);
  Result.AddPair('predicted', pView.Predicted);
  Result.AddPair('actual', '');
  Result.AddPair('verified', TJSONBool.Create(False));
end;

// The 1-based group holding pStem (with or without .pas), 0 when none does.
function GroupOfUnit(const pSccs: TList<TArray<string>>; const pStem: string): Integer;
begin
  var Stem:= LowerCase(ChangeFileExt(pStem, ''));
  for var I:= 0 to pSccs.Count - 1 do
    for var S in pSccs[I] do
      if S = Stem then Exit(I + 1);
  Result:= 0;
end;

// Checks the flags and resolves the group (0 = scan for the first mechanical one) and the
// project's own roots; returns the error text, '' when all is well.
function ResolveSelection(const pOpts: TCycleFixOptions; const pSccs: TList<TArray<string>>;
  out pRoots: TArray<string>; out pOnly: Integer): string;
var
  Own: TOwnRoots;
begin
  Result:= '';
  pOnly := 0;
  pRoots:= nil;
  if pOpts.Project = '' then Result:= CNeedsProject
  else if pOpts.Apply then
    Result:= 'ERROR: cycles --fix --apply is not available yet (E18 Tasks 9-12); the dry run needs no --apply'
  else if not MatchText(pOpts.Part, ['', 'a', 'b', 'all']) then
    Result:= 'ERROR: cycles --fix --part must be a, b or all'
  else if SameText(pOpts.Part, 'all') then
    Result:= 'ERROR: cycles --fix --part all is not available yet (E18 Task 12)';
  if Result <> '' then Exit;
  Own:= TOwnRoots.Load(ExtractFilePath(ExpandFileName(pOpts.Project)));
  if Own.Error <> '' then Exit('ERROR: ' + Own.Error);
  pRoots:= Own.Roots;
  if (Length(pRoots) = 0) and (Own.Anchor <> '') then pRoots:= [Own.Anchor];
  if pOpts.CycleIndex > 0 then pOnly:= pOpts.CycleIndex
  else if pOpts.UnitStem <> '' then
  begin
    pOnly:= GroupOfUnit(pSccs, pOpts.UnitStem);
    if pOnly = 0 then Exit('ERROR: cycles --fix: unit ' + pOpts.UnitStem + ' is in no circular group');
  end;
  if (pOnly > pSccs.Count) then
    Result:= Format('ERROR: cycles --fix: --cycle %d, but there are %d circular group(s)', [pOnly, pSccs.Count]);
end;

function RunCycleFix(const pOpts: TCycleFixOptions; const pStore: ISymbolStore;
  const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph; const pLibStore: ISymbolStore): Integer;
var
  Problem : string;
  Roots   : TArray<string>;
  Only    : Integer;
  Cycles  : TJSONArray;
  Playbook: TStringList;
  Summary : TStringList;
  Chosen  : Boolean;
  BadPart : string;
begin
  Problem:= ResolveSelection(pOpts, pSccs, Roots, Only);
  if Problem <> '' then
  begin
    Writeln(Problem);
    Exit(CExitError);
  end;

  Chosen  := False;
  BadPart := '';
  Cycles  := TJSONArray.Create;
  Playbook:= TStringList.Create;
  Summary := TStringList.Create;
  try
    VisitCyclePlans(pStore, pOpts.Db, pSccs, pGraph, pLibStore,
      function(const pView: TCyclePlanView; const pRender: TFunc<TArray<string>>): Boolean
      var
        All: TList<TRefusal>;
      begin
        All:= TList<TRefusal>.Create;
        try
          All.AddRange(pView.Refusals);
          All.AddRange(MechanisabilityGate(pView, Roots));
          All.AddRange(StaleRefusals(pStore, pView));
          var Verdict:= All.ToArray;
          var Wanted:= pOpts.Part;
          if (Wanted <> '') and not SameText(Wanted, string(pView.Part)) then
          begin
            BadPart:= Format('ERROR: cycles --fix: cycle %d is planned as part %s, not --part %s ' +
              '(the other part comes with --part all, E18 Task 12)', [pView.CycleIndex, LowerCase(pView.Part), Wanted]);
            Exit(False);
          end;
          Cycles.AddElement(CycleToJson(pView, Verdict, pGraph));
          Chosen:= Length(Verdict) = 0;
          if (not pOpts.Json) and ((Only > 0) or Chosen) then Playbook.AddStrings(pRender());
          if Chosen then
          begin
            if not pOpts.Json then Summary.Add(CVerdictOk);
          end
          else if Only > 0 then
          begin
            Summary.Add(CVerdictRefused);
            for var R in Verdict do Summary.Add(RefusalLine(R));
          end
          else
          begin
            Summary.Add(Format('Cycle %d: %s', [pView.CycleIndex, string.Join(' <-> ', pView.Units)]));
            Summary.Add(RefusalLine(Verdict[0]));
          end;
          Exit(not Chosen);
        finally
          All.Free;
        end;
      end, Only);
    if BadPart <> '' then
    begin
      Writeln(BadPart);
      Exit(CExitError);
    end;
    Result:= if Chosen or (pSccs.Count = 0) then CExitMechanical else CExitRefused;
    if pOpts.Json then
    begin
      var Doc:= TJSONObject.Create;
      try
        Doc.AddPair('schema', CSchema);
        Doc.AddPair('mode', 'dry-run');
        Doc.AddPair('project', pOpts.Project);
        Doc.AddPair('db', pOpts.Db);
        Doc.AddPair('platform', if pOpts.Platform = '' then CDefaultPlatform else LowerCase(pOpts.Platform));
        Doc.AddPair('cycles', Cycles);
        Cycles:= nil;
        Doc.AddPair('ok', TJSONBool.Create(Result = CExitMechanical));
        Doc.AddPair('exit_code', TJSONNumber.Create(Result));
        Writeln(Doc.ToJSON);
      finally
        Doc.Free;
      end;
    end
    else
    begin
      if pSccs.Count = 0 then Writeln(CCycleNone);
      for var Line in Playbook do Writeln(Line);
      for var Line in Summary do Writeln(Line);
      if (pSccs.Count > 0) and (Only = 0) and not Chosen then Writeln(CVerdictRefused);
    end;
  finally
    Summary.Free;
    Playbook.Free;
    Cycles.Free;
  end;
end;

end.
