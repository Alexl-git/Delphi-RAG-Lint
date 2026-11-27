unit DRagLint.CLI.RepoPaths;

{ drag-lint 1.55 -- lane XTABLE slice X2: `repo paths` (design
  docs\superpowers\specs\2026-11-26-cross-table-fields-design.md sections 3.2 and 8). Read-only. DRagLint.CLI.Repo
  resolves the repository path and dispatches here in ONE line; --from, --to, --depth and --stats are read from the
  command line (ParseArgs only has to accept them). }

interface

/// <summary>True for the sub-verb this unit runs: paths.</summary>
/// <param name="pSub">The `repo` sub-verb.</param>
/// <returns>True when RunRepoPathsVerb handles it.</returns>
function IsRepoPathsSub(const pSub: string): Boolean;

/// <summary>Runs `repo paths`: the relation paths from --from up to --to within --depth steps (default 3, ruling
/// XQ5), each with its default input alias (XQ2) and the rule of design 3.2 that chooses (or not); with --stats
/// instead, the reachable and ambiguous table pairs at depth 1..--depth over the whole graph.</summary>
/// <param name="pPath">The repository file (already resolved from --repo / --project).</param>
/// <param name="pJson">--json: one JSON object on stdout.</param>
/// <returns>0 = paths listed (or stats); 1 = no path, a missing file, or no relation and no schema facts;
/// 2 = usage.</returns>
/// <remarks>Reads the repository only. Not thread-safe.</remarks>
function RunRepoPathsVerb(const pPath: string; pJson: Boolean): Integer;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.SchemaFacts,
  DRagLint.FieldRepo.RelationGraph, // dl:unit DRagLint.FieldRepo.RelationGraph accepted -- path_depth_default is the default of --depth and travels with the path finder that applies it
  DRagLint.FieldRepo.RelationRepo;

const
  EXIT_OK = 0;
  EXIT_FAIL = 1;
  EXIT_USAGE = 2;
  SUB_PATHS = 'paths';
  MIN_DEPTH = 1;
  CHOICE_HINT: array[TFrPathRule] of string = (
    'no path within the depth',
    'the binding stored for the field',
    'the form''s joins',
    'the IS_DEFAULT relations',
    'exactly one path',
    'several paths: asked once in the dialog, the answer is stored as IS_DEFAULT of each step');

function FlagValue(const pFlag: string): string;
var
  VI: Integer;
begin
  Result := '';
  for VI := 1 to ParamCount - 1 do
    if SameText(ParamStr(VI), pFlag) then
      Exit(ParamStr(VI + 1));
end;

function HasFlag(const pFlag: string): Boolean;
var
  VI: Integer;
begin
  Result := False;
  for VI := 1 to ParamCount do
    if SameText(ParamStr(VI), pFlag) then
      Exit(True);
end;

function IsRepoPathsSub(const pSub: string): Boolean;
begin
  Result := SameText(pSub, SUB_PATHS);
end;

function PairText(const pStep: TFrRelation): string;
var
  VI: Integer;
begin
  Result := '';
  for VI := 0 to High(pStep.ChildColumns) do
    Result := Result + (if Result = '' then '' else ',') + pStep.ChildColumns[VI] + '=' + pStep.ParentColumns[VI];
end;

function StepText(const pStep: TFrRelation): string;
begin
  Result := ' -(' + pStep.Name + ' ' + pStep.Source + ' ' + PairText(pStep) +
    (if pStep.IsDefault then ' default' else '') + ')-> ' + pStep.ParentTable;
end;

function StepJson(const pStep: TFrRelation): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('relation', pStep.Name);
  Result.AddPair('child', pStep.ChildTable);
  Result.AddPair('parent', pStep.ParentTable);
  Result.AddPair('source', pStep.Source);
  Result.AddPair('parent_key', pStep.ParentKey);
  Result.AddPair('columns', PairText(pStep));
  Result.AddPair('default', TJSONBool.Create(pStep.IsDefault));
end;

function RunStats(pGraph: TFrRelationGraph; pDepth, pSkipped: Integer; pJson: Boolean): Integer;
var
  VD: Integer;
  VStats: TFrReachStats;
  VRoot: TJSONObject;
  VRows: TJSONArray;
  VRow: TJSONObject;
begin
  VRoot := TJSONObject.Create;
  try
    VRoot.AddPair('tables', TJSONNumber.Create(Length(pGraph.Tables)));
    VRoot.AddPair('relations', TJSONNumber.Create(pGraph.RelationCount));
    VRoot.AddPair('not_edges', TJSONNumber.Create(pSkipped));
    VRows := TJSONArray.Create;
    VRoot.AddPair('depths', VRows);
    if not pJson then
      Writeln(Format('repo paths --stats: tables=%d relations=%d not-edges=%d',
        [Length(pGraph.Tables), pGraph.RelationCount, pSkipped]));
    for VD := MIN_DEPTH to pDepth do
    begin
      VStats := pGraph.Stats(VD);
      VRow := TJSONObject.Create;
      VRow.AddPair('depth', TJSONNumber.Create(VD));
      VRow.AddPair('pairs', TJSONNumber.Create(VStats.Pairs));
      VRow.AddPair('more_than_one_path', TJSONNumber.Create(VStats.Ambiguous));
      VRows.AddElement(VRow);
      if not pJson then
        Writeln(Format('depth %d: pairs %d, more than one path %d', [VD, VStats.Pairs, VStats.Ambiguous]));
    end;
    if pJson then
      Writeln(VRoot.ToJSON);
  finally
    VRoot.Free;
  end;
  Result := EXIT_OK;
end;

function RunPaths(pGraph: TFrRelationGraph; const pFrom, pTo: string; pDepth: Integer; pJson: Boolean): Integer;
var
  VChoice: TFrPathChoice;
  VI: Integer;
  VLine: string;
  VParts: TArray<string>;
  VStep: TFrRelation;
  VRoot, VItem: TJSONObject;
  VList, VSteps: TJSONArray;
begin
  VChoice := pGraph.Choose(pFrom, pTo, '', nil, pDepth);
  VRoot := TJSONObject.Create;
  try
    VRoot.AddPair('from', pFrom);
    VRoot.AddPair('to', pTo);
    VRoot.AddPair('depth', TJSONNumber.Create(pDepth));
    VList := TJSONArray.Create;
    VRoot.AddPair('paths', VList);
    if not pJson then
      Writeln(Format('repo paths %s -> %s (depth %d): %d path(s)', [pFrom, pTo, pDepth, Length(VChoice.Paths)]));
    for VI := 0 to High(VChoice.Paths) do
    begin
      VItem := TJSONObject.Create;
      VList.AddElement(VItem);
      VItem.AddPair('alias', DefaultInputAlias(pTo, VI + 1));
      VItem.AddPair('path', VChoice.Paths[VI].Text);
      VSteps := TJSONArray.Create;
      VItem.AddPair('steps', VSteps);
      VParts := [pFrom];
      for VStep in VChoice.Paths[VI].Steps do
      begin
        VSteps.AddElement(StepJson(VStep));
        VParts := VParts + [StepText(VStep)];
      end;
      VLine := string.Join('', VParts);
      if not pJson then
        Writeln(Format('  %d %s: %s', [VI + 1, DefaultInputAlias(pTo, VI + 1), VLine]));
    end;
    VRoot.AddPair('choice', PathRuleName(VChoice.Rule));
    VRoot.AddPair('chosen', TJSONNumber.Create(VChoice.Chosen + 1));
    if pJson then
      Writeln(VRoot.ToJSON)
    else if VChoice.Chosen >= 0 then
      Writeln(Format('choice: %s, path %d (%s)', [PathRuleName(VChoice.Rule), VChoice.Chosen + 1,
        CHOICE_HINT[VChoice.Rule]]))
    else
      Writeln(Format('choice: %s (%s)', [PathRuleName(VChoice.Rule), CHOICE_HINT[VChoice.Rule]]));
  finally
    VRoot.Free;
  end;
  Result := if Length(VChoice.Paths) = 0 then EXIT_FAIL else EXIT_OK;
end;

function RunRepoPathsVerb(const pPath: string; pJson: Boolean): Integer;
var
  VConn: TFDConnection;
  VGraph: TFrRelationGraph;
  VSkipped: TArray<string>;
  VFrom, VTo: string;
  VDepth: Integer;
  VStats: Boolean;
begin
  VFrom := FlagValue('--from');
  VTo := FlagValue('--to');
  VStats := HasFlag('--stats');
  VDepth := StrToIntDef(FlagValue('--depth'), PATH_DEPTH_DEFAULT);
  if HasFlag('--depth') and (StrToIntDef(FlagValue('--depth'), 0) < MIN_DEPTH) then
  begin
    Writeln(ErrOutput, 'repo paths: --depth must be a whole number of at least 1');
    Exit(EXIT_USAGE);
  end;
  if not VStats and ((VFrom = '') or (VTo = '')) then
  begin
    Writeln(ErrOutput, 'repo paths: give --from <table> --to <table>, or --stats');
    Exit(EXIT_USAGE);
  end;
  if not TFile.Exists(pPath) then
  begin
    Writeln(ErrOutput, 'repo paths: the repository does not exist: ', pPath);
    Exit(EXIT_FAIL);
  end;
  VConn := OpenRepository(pPath, True);
  try
    VGraph := LoadRelationGraph(VConn, VSkipped);
    try
      if (VGraph.RelationCount = 0) and not HasSchema(VConn) then
      begin
        Writeln(ErrOutput, 'repo paths: the repository holds no schema facts (run repo seed-fb or refresh-schema)');
        Exit(EXIT_FAIL);
      end;
      Result := if VStats then RunStats(VGraph, VDepth, Length(VSkipped), pJson)
        else RunPaths(VGraph, VFrom, VTo, VDepth, pJson);
    finally
      VGraph.Free;
    end;
  finally
    VConn.Free;
  end;
end;

end.
