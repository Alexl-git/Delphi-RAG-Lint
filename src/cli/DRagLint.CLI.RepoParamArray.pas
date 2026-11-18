unit DRagLint.CLI.RepoParamArray;

{ drag-lint 1.52 -- `repo gen-param-array` (lane GENPAIMPL; spec
  docs\superpowers\specs\2026-11-18-gen-param-array-design.md).
  The CLI adapter of the TTPA engine (DRagLint.FieldRepo.ParamArray): flags, unit discovery,
  the collecting compile gate, ONE gated write per run, and the text / --json output.
  The block is inserted as a braced COMMENT before the unit's final `end.` (live code is 1.52.1). }

interface

/// <summary>Runs `drag-lint repo gen-param-array`: generates the FireDAC Array-DML loop from a
/// unit's DFM (one unit with --in, every eligible unit of a project with --project ... --all).</summary>
/// <param name="pProject">--project value (a .dproj), '' when absent. Needed by --apply and --all.</param>
/// <param name="pInFile">--in value (a unit .pas), '' when absent.</param>
/// <param name="pJson">--json: one JSON object on stdout instead of the text lines.</param>
/// <returns>0 = every processed unit planned / applied; 1 = a unit refused, no block in single
/// mode, or the gate rolled back; 2 = bad flags, write failure, or a baseline that does not build.</returns>
/// <remarks>The other flags are read from the command line here (the dispatch signature is FRAME's):
/// --dfm, --query, --table, --step-size, --progress-form, --prepare-queries, --plan, --apply, --all,
/// --only, --no-backup, --platform, --rsvars, --build-timeout. No flag: the block is printed to stdout.
/// --plan prints the unified diff and writes nothing; --apply writes through the compile gate
/// (ApplyGated, once for the whole run, one retry without the units dcc names). Never needs --repo.
/// --prepare-queries first does the IDE assistant's query preparation (PAPrepareQueries: each SELECT
/// TFDQuery, or only --query, gets its update object's INSERT SQL, ParamData and ObjectView False; the
/// update object / schema adapter are renamed ZZZ*, persistent fields removed, the unit's component
/// declarations edited to match). --plan then shows the .dfm and .pas diffs and --apply writes both
/// files through the same gate; without --plan / --apply nothing is written.
/// Not thread-safe; main thread only (it opens the gate's control channel).</remarks>
function RunGenParamArray(const pProject, pInFile: string; pJson: Boolean): Integer;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.JSON,
  DRagLint.FieldRepo.ParamArray,
  DRagLint.FieldRepo.ParamArray.Prepare,
  DRagLint.Refactor.TextEdit,
  DRagLint.Refactor.CompileGate,
  DRagLint.Lint.ProjectChecks.Parse;

const
  EXIT_OK    = 0;
  EXIT_FAIL  = 1;
  EXIT_USAGE = 2;
  VERB       = 'repo gen-param-array';
  DEFAULT_STEP = 20000;
  MSEC_PER_SEC = 1000;
  ST_APPLIED   = 'applied';
  ST_PLANNED   = 'planned';
  ST_REFUSED   = 'refused-by-gate';
  ST_NO_INSERT = 'no-insert-point';
  ST_NO_BLOCK  = 'no-block';
  ST_EXCLUDED  = 'excluded';
  ST_BINARY    = 'binary-dfm';
  ST_MISSING   = 'missing-dfm';
  BINARY_MAGIC = 'TPF0';
  REGION_PAIRS  = 0;
  REGION_PARAMS = 1;
  REGION_FIELDS = 2;
  REGION_DONE   = 3;

type
  TGpaOptions = record
    InFile: string;
    DfmFile: string;
    Query: string;
    Table: string;
    Project: string;
    Only: string;
    Emit: TPAOptions;
    Plan: Boolean;
    Apply: Boolean;
    Prepare: Boolean;
    All: Boolean;
    NoBackup: Boolean;
    Json: Boolean;
    Platform: string;
    RsVars: string;
    BuildTimeout: string;
  end;

  TGpaUnit = record
    Name: string;
    PasPath: string;
    DfmPath: string;
    Status: string;
    Query: string;
    Table: string;
    Block: string;
    Plan: string;
    Error: string;
    NewBytes: TBytes;
    NewDfmBytes: TBytes;
    Prep: TPAPrepareResult;
    Matched: Integer;
    Mismatch: Integer;
    MissParams: Integer;
    MissFields: Integer;
  end;

  TGpaGate = record
    Ran: Boolean;
    Applied: Boolean;
    Refusal: string;
    Detail: string;
    RolledBack: Boolean;
    Lines: TArray<string>;
  end;

function CommandLineFlag(const pFlag: string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  for I:= 1 to ParamCount do
    if SameText(ParamStr(I), pFlag) then Exit(True);
end;

function CommandLineValue(const pFlag: string): string;
var
  I: Integer;
begin
  Result:= '';
  for I:= 1 to ParamCount - 1 do
    if SameText(ParamStr(I), pFlag) then Exit(ParamStr(I + 1));
end;

function ReadOptions(const pProject, pInFile: string; pJson: Boolean; out pO: TGpaOptions): Boolean;
var
  Step: string;
begin
  Result:= False;
  pO:= Default(TGpaOptions);
  pO.InFile:= pInFile;
  pO.Project:= pProject;
  pO.Json:= pJson;
  pO.DfmFile:= CommandLineValue('--dfm');
  pO.Query:= CommandLineValue('--query');
  pO.Table:= CommandLineValue('--table');
  pO.Only:= CommandLineValue('--only');
  pO.Platform:= CommandLineValue('--platform');
  pO.RsVars:= CommandLineValue('--rsvars');
  pO.BuildTimeout:= CommandLineValue('--build-timeout');
  pO.Plan:= CommandLineFlag('--plan');
  pO.Apply:= CommandLineFlag('--apply');
  pO.Prepare:= CommandLineFlag('--prepare-queries');
  pO.All:= CommandLineFlag('--all');
  pO.NoBackup:= CommandLineFlag('--no-backup');
  pO.Emit:= PADefaultOptions;
  pO.Emit.ProgressForm:= CommandLineValue('--progress-form');
  Step:= CommandLineValue('--step-size');
  if Step <> '' then
  begin
    pO.Emit.StepSize:= StrToIntDef(Step, 0);
    if pO.Emit.StepSize <= 0 then
    begin
      Writeln(ErrOutput, VERB, ': --step-size must be a positive whole number, got: ', Step);
      Exit;
    end;
  end;
  if pO.Plan and pO.Apply then
    Writeln(ErrOutput, VERB, ': --plan and --apply exclude each other')
  else if (pO.InFile <> '') and pO.All then
    Writeln(ErrOutput, VERB, ': give --in <unit> or --project <proj> --all, not both')
  else if (pO.InFile = '') and not (pO.All and (pO.Project <> '')) then
    Writeln(ErrOutput, VERB, ': give --in <unit.pas>, or --project <X.dproj> --all')
  else if pO.Apply and (pO.Project = '') then
    Writeln(ErrOutput, VERB, ': --apply needs --project <X.dproj> (the compile gate builds it)')
  else
    Result:= True;
end;

{ ---- unit discovery and analysis ---- }

function OnlyContains(const pOnly, pName: string): Boolean;
var
  Part: string;
begin
  Result:= pOnly = '';
  for Part in pOnly.Split([',']) do
    if SameText(Trim(Part), pName) then Exit(True);
end;

function NewUnit(const pPas: string): TGpaUnit;
begin
  Result:= Default(TGpaUnit);
  Result.PasPath:= pPas;
  Result.Name:= TPath.GetFileNameWithoutExtension(pPas);
  Result.DfmPath:= ChangeFileExt(pPas, '.dfm');
end;

function CollectUnits(const pO: TGpaOptions): TArray<TGpaUnit>;
var
  Units: TList<TGpaUnit>;
  Ref, Dir: string;
  U: TGpaUnit;
begin
  Units:= TList<TGpaUnit>.Create;
  try
    if pO.InFile <> '' then
    begin
      U:= NewUnit(TPath.GetFullPath(pO.InFile));
      if pO.DfmFile <> '' then U.DfmPath:= TPath.GetFullPath(pO.DfmFile);
      Units.Add(U);
    end
    else
    begin
      Dir:= ExtractFilePath(TPath.GetFullPath(pO.Project));
      for Ref in ReadDCCReferences(TPath.GetFullPath(pO.Project)) do
      begin
        if not SameText(ExtractFileExt(Ref), '.pas') then Continue;
        U:= NewUnit(TPath.GetFullPath(TPath.Combine(Dir, Ref)));
        if not OnlyContains(pO.Only, U.Name) then Continue;
        if not PAProjectEligible(U.Name) then U.Status:= ST_EXCLUDED;
        Units.Add(U);
      end;
    end;
    Result:= Units.ToArray;
  finally
    Units.Free;
  end;
end;

{ Counts the block's lines by kind: the matched pairs, the type mismatches, the missing params / fields. }
procedure CountBlock(var pU: TGpaUnit);
var
  Lines: TStringList;
  S, T: string;
  Region: Integer;
begin
  Region:= REGION_PAIRS;
  Lines:= TStringList.Create;
  try
    Lines.Text:= pU.Block;
    for S in Lines do
    begin
      T:= Trim(S);
      if StartsStr('##### TYPE MISMATCH', T) then Inc(pU.Mismatch)
      else if T = '// MISSING PARAMS' then Region:= REGION_PARAMS
      else if StartsStr('#### MISSING FIELDS', T) then Region:= REGION_FIELDS
      else if Region = REGION_FIELDS then
      begin
        if T = '' then Region:= REGION_DONE
        else if T <> '//' then Inc(pU.MissFields);
      end
      else if Region = REGION_PARAMS then
      begin
        if ContainsStr(T, '.Params[') then Inc(pU.MissParams);
      end
      else if (Region = REGION_PAIRS) and not StartsStr('//', T) and ContainsStr(T, '.Params[par') and ContainsStr(T, '[I]') then
        Inc(pU.Matched);
    end;
  finally
    Lines.Free;
  end;
end;

{ Analyses one unit: DFM -> block -> plan -> candidate through the collecting gate. Sets Status. }
procedure AnalyseUnit(var pU: TGpaUnit; const pO: TGpaOptions);
var
  Bytes: TBytes;
  Dfm, Source, NewSource, Candidate, Block, OrigDfm, OrigSource: string;
  Src, Dst: TPAColumns;
  Fmt, DfmFmt: TTextFileFormat;
  Gate: TPAGate;
  Status: TPAStatus;
begin
  if not TFile.Exists(pU.DfmPath) then
  begin
    pU.Status:= ST_MISSING;
    pU.Error:= 'no DFM: ' + pU.DfmPath;
    Exit;
  end;
  Bytes:= TFile.ReadAllBytes(pU.DfmPath);
  if (Length(Bytes) >= Length(BINARY_MAGIC)) and (Bytes[0] = Ord('T')) and (Bytes[1] = Ord('P'))
     and (Bytes[2] = Ord('F')) and (Bytes[3] = Ord('0')) then
  begin
    pU.Status:= ST_BINARY;
    pU.Error:= 'binary DFM (save it as text): ' + pU.DfmPath;
    Exit;
  end;
  DfmFmt:= TTextFileFormat.ReadFile(pU.DfmPath, Dfm);
  if not TFile.Exists(pU.PasPath) then
  begin
    pU.Status:= ST_NO_BLOCK;
    pU.Error:= 'source file missing: ' + pU.PasPath;
    Exit;
  end;
  Fmt:= TTextFileFormat.ReadFile(pU.PasPath, Source);
  OrigDfm:= Dfm;
  OrigSource:= Source;
  if pO.Prepare then
  begin
    // the IDE assistant prepared the queries BEFORE it read the params: discovery and the block see the result
    pU.Prep:= PAPrepareQueries(Dfm, Source, pO.Query);
    Dfm:= pU.Prep.Dfm;
    Source:= pU.Prep.Pas;
  end;
  if not PADiscoverNamed(Dfm, pO.Query, pO.Table, pU.Query, pU.Table, Src, Dst) then
  begin
    pU.Status:= ST_NO_BLOCK;
    pU.Error:= if (pO.Query <> '') or (pO.Table <> '') then
      'the named table / query is not in the DFM' else 'no TTable and parameterised TFDQuery in the DFM';
    Exit;
  end;
  if not PABuildBlock(pU.Query, pU.Table, Src, Dst, pO.Emit, Block, pU.Error) then
  begin
    pU.Status:= ST_NO_BLOCK;
    Exit;
  end;
  pU.Block:= Block;
  CountBlock(pU);
  pU.Plan:= PABuildPlan(pU.Name, Source, Block);
  Candidate:= '';
  // collecting gate: a block holding a closing brace would end the comment early; otherwise the candidate
  // is kept for the ONE project build (the compile happens in ApplyGated, not here)
  Gate:= function(const pUnitText: string): Boolean
    begin
      Result:= not ContainsStr(Block, '}');
      if Result then Candidate:= pUnitText;
    end;
  Status:= PAApplyPlan(Source, Block, Gate, NewSource);
  case Status of
    pasApplied:
      begin
        pU.Status:= ST_PLANNED;
        pU.NewBytes:= Fmt.Encode(Candidate);
        if pO.Prepare then
        begin
          // one diff per file against the bytes on disk (the block diff alone would number lines of the prepared text)
          pU.Plan:= PAUnifiedDiff(ExtractFileName(pU.DfmPath), OrigDfm, Dfm) +
            PAUnifiedDiff(ExtractFileName(pU.PasPath), OrigSource, Candidate);
          if Dfm <> OrigDfm then pU.NewDfmBytes:= DfmFmt.Encode(Dfm);
        end;
      end;
    pasRefusedByGate:
      begin
        pU.Status:= ST_REFUSED;
        pU.Error:= 'the block contains "}", which would end the comment early';
      end;
  else
    pU.Status:= ST_NO_INSERT;
    pU.Error:= 'no final "end." to insert before';
  end;
end;

{ ---- the gated write ---- }

function RunGate(const pO: TGpaOptions; const pUnits: TArray<TGpaUnit>; const pIdx: TArray<Integer>): TGateOutcome;
var
  Req: TGateRequest;
  GF: TGateFile;
  I, Secs: Integer;
begin
  Req:= Default(TGateRequest);
  for I in pIdx do
  begin
    GF.Path:= pUnits[I].PasPath;
    GF.Bytes:= pUnits[I].NewBytes;
    Req.Files:= Req.Files + [GF];
    if pUnits[I].NewDfmBytes <> nil then
    begin
      GF.Path:= pUnits[I].DfmPath;
      GF.Bytes:= pUnits[I].NewDfmBytes;
      Req.Files:= Req.Files + [GF];
    end;
  end;
  if pO.RsVars <> '' then Req.RsVars:= ExpandFileName(pO.RsVars);
  Secs:= StrToIntDef(pO.BuildTimeout, 0);
  GBuildTimeoutMs:= if Secs <= 0 then INFINITE else Cardinal(Secs) * MSEC_PER_SEC;
  GGateVerb:= VERB;
  Req.Project:= ExpandFileName(pO.Project);
  Req.Platform:= pO.Platform;
  Req.Verb:= VERB;
  Req.NoBackup:= pO.NoBackup;
  Req.Header:= Format('[%s] %s --apply: %d unit(s)', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), VERB, Length(pIdx)]);
  Req.LogDir:= FreshScratchName('_build');
  Result:= ApplyGated(Req);
  try
    if not GScratchCited and TDirectory.Exists(Req.LogDir) then TDirectory.Delete(Req.LogDir, True); // LogDir is FreshScratchName's: a folder this run made under C:\TEMP
  except
    on EInOutError do Writeln(ErrOutput, 'drag-lint: note: scratch not deleted: ', Req.LogDir);  // best effort: a locked log must not change the result
  end;
end;

function PlannedIndices(const pUnits: TArray<TGpaUnit>): TArray<Integer>;
var
  I: Integer;
begin
  Result:= nil;
  for I:= 0 to High(pUnits) do
    if pUnits[I].Status = ST_PLANNED then Result:= Result + [I];
end;

{ Marks the planned units whose file a dcc error line names as refused; returns how many. }
function RefuseNamedUnits(var pUnits: TArray<TGpaUnit>; const pErrors: TArray<string>): Integer;
var
  Line: string;
  Dcc: TDccLine;
  I: Integer;
begin
  Result:= 0;
  for Line in pErrors do
  begin
    if not ParseDccLine(Line, Dcc) then Continue;
    for I:= 0 to High(pUnits) do
      if (pUnits[I].Status = ST_PLANNED) and (SameText(ExtractFileName(Dcc.FileName), ExtractFileName(pUnits[I].PasPath))
        or ((pUnits[I].NewDfmBytes <> nil) and SameText(ExtractFileName(Dcc.FileName), ExtractFileName(pUnits[I].DfmPath)))) then
      begin
        pUnits[I].Status:= ST_REFUSED;
        pUnits[I].Error:= 'dcc: ' + Line;
        Inc(Result);
      end;
  end;
end;

procedure RefuseAllPlanned(var pUnits: TArray<TGpaUnit>; const pWhy: string);
var
  I: Integer;
begin
  for I:= 0 to High(pUnits) do
    if pUnits[I].Status = ST_PLANNED then
    begin
      pUnits[I].Status:= ST_REFUSED;
      pUnits[I].Error:= pWhy;
    end;
end;

procedure NoteGate(var pGate: TGpaGate; const pOut: TGateOutcome);
begin
  pGate.Ran:= True;
  pGate.Applied:= pOut.Applied;
  pGate.Refusal:= pOut.Refusal;
  pGate.Detail:= pOut.Detail;
  pGate.RolledBack:= pOut.RolledBack;
  pGate.Lines:= GateMessageReport(pOut);
end;

{ One ApplyGated for every planned unit; on a compile error one retry without the units dcc names. }
procedure ApplyAll(const pO: TGpaOptions; var pUnits: TArray<TGpaUnit>; var pGate: TGpaGate);
var
  Idx: TArray<Integer>;
  Outcome: TGateOutcome;
  I: Integer;
begin
  Idx:= PlannedIndices(pUnits);
  if Length(Idx) = 0 then Exit;
  Outcome:= RunGate(pO, pUnits, Idx);
  NoteGate(pGate, Outcome);
  if (not Outcome.Applied) and (Outcome.Refusal = CGateCompileError) then
  begin
    if RefuseNamedUnits(pUnits, Outcome.After.Errors) > 0 then
    begin
      Idx:= PlannedIndices(pUnits);
      if Length(Idx) > 0 then
      begin
        Outcome:= RunGate(pO, pUnits, Idx);
        NoteGate(pGate, Outcome);
      end
      else Exit;
    end;
  end;
  if Outcome.Applied then
  begin
    for I in Idx do pUnits[I].Status:= ST_APPLIED;
  end
  else
    RefuseAllPlanned(pUnits, Outcome.Refusal + ': ' + Outcome.Detail);
end;

{ ---- output ---- }

function StatusLine(const pU: TGpaUnit): string;
begin
  Result:= Format('%s: %s (%d matched, %d mismatch, %d missing params, %d missing fields)',
    [pU.Name, pU.Status, pU.Matched, pU.Mismatch, pU.MissParams, pU.MissFields]);
  if pU.Error <> '' then Result:= Result + ' -- ' + pU.Error;
end;

{ --prepare-queries: what the preparation did to one unit, one line each ('' list when nothing). }
function PrepareLines(const pU: TGpaUnit): TArray<string>;
var
  W: string;
begin
  Result:= nil;
  if pU.Prep.Queries <> nil then
    Result:= Result + [Format('%s: prepare-queries: %s; renamed %s; %d persistent field(s) removed',
      [pU.Name, string.Join(', ', pU.Prep.Queries), if pU.Prep.Renamed = nil then 'nothing' else string.Join(', ', pU.Prep.Renamed),
       Length(pU.Prep.RemovedFields)])];
  for W in pU.Prep.Warnings do Result:= Result + [pU.Name + ': prepare-queries warning: ' + W];
end;

function JsonStrings(const pItems: TArray<string>): TJSONArray;
var
  S: string;
begin
  Result:= TJSONArray.Create;
  for S in pItems do Result.Add(S);
end;

function ModeName(const pO: TGpaOptions): string;
begin
  Result:= if pO.Apply then 'apply' else if pO.Plan then 'plan' else 'print';
end;

procedure PrintJson(const pO: TGpaOptions; const pUnits: TArray<TGpaUnit>; const pGate: TGpaGate);
var
  Root, Item, G: TJSONObject;
  Arr: TJSONArray;
  U: TGpaUnit;
begin
  Root:= TJSONObject.Create;
  try
    Root.AddPair('mode', ModeName(pO));
    Arr:= TJSONArray.Create;
    Root.AddPair('units', Arr);
    for U in pUnits do
    begin
      Item:= TJSONObject.Create;
      Item.AddPair('unit', U.Name);
      Item.AddPair('status', U.Status);
      Item.AddPair('query', U.Query);
      Item.AddPair('table', U.Table);
      Item.AddPair('matched', TJSONNumber.Create(U.Matched));
      Item.AddPair('type_mismatch', TJSONNumber.Create(U.Mismatch));
      Item.AddPair('missing_params', TJSONNumber.Create(U.MissParams));
      Item.AddPair('missing_fields', TJSONNumber.Create(U.MissFields));
      if (U.Status = ST_PLANNED) or (U.Status = ST_APPLIED) then
      begin
        Item.AddPair('plan', U.Plan);
        Item.AddPair('block', U.Block);
      end;
      if U.Error <> '' then Item.AddPair('error', U.Error);
      if pO.Prepare then
      begin
        G:= TJSONObject.Create;
        G.AddPair('queries', JsonStrings(U.Prep.Queries));
        G.AddPair('renamed', JsonStrings(U.Prep.Renamed));
        G.AddPair('removed_fields', JsonStrings(U.Prep.RemovedFields));
        G.AddPair('warnings', JsonStrings(U.Prep.Warnings));
        Item.AddPair('prepare', G);
      end;
      Arr.Add(Item);
    end;
    if pGate.Ran then
    begin
      G:= TJSONObject.Create;
      G.AddPair('applied', TJSONBool.Create(pGate.Applied));
      G.AddPair('refusal', pGate.Refusal);
      G.AddPair('detail', pGate.Detail);
      G.AddPair('rolled_back', TJSONBool.Create(pGate.RolledBack));
      Root.AddPair('gate', G);
    end;
    Writeln(Root.ToJSON);
  finally
    Root.Free;
  end;
end;

{ print: the block(s), what the IDE assistant put on the clipboard; plan: the diff; both with the
  status lines on stderr so stdout stays the payload. apply: the status lines are the output. }
procedure PrintText(const pO: TGpaOptions; const pUnits: TArray<TGpaUnit>; const pGate: TGpaGate);
var
  U: TGpaUnit;
  Line: string;
  Shown, Excluded: Integer;
begin
  Excluded:= 0;
  Shown:= 0;
  for U in pUnits do
  begin
    if U.Status = ST_EXCLUDED then
    begin
      Inc(Excluded);
      Continue;
    end;
    Inc(Shown);
    if pO.Apply then Writeln(StatusLine(U)) else Writeln(ErrOutput, StatusLine(U));
    for Line in PrepareLines(U) do
      if pO.Apply then Writeln(Line) else Writeln(ErrOutput, Line);
    if U.Status <> ST_PLANNED then Continue;
    if pO.Plan then Write(U.Plan)
    else if not pO.Apply then
    begin
      if pO.InFile = '' then Writeln('// unit: ', U.Name);
      Write(U.Block);
      if not EndsStr(#10, U.Block) then Writeln;
    end;
  end;
  if (pO.InFile = '') and (Excluded > 0) then
    Writeln(ErrOutput, Format('%d unit(s) not processed (name does not start with u, or on the exclusion list)', [Excluded]));
  for Line in pGate.Lines do Writeln(ErrOutput, Line);
  if pGate.Ran and not pGate.Applied then
    Writeln(ErrOutput, 'REFUSED (', pGate.Refusal, '): ', VERB, ': ', pGate.Detail);
  if Shown = 0 then Writeln(ErrOutput, VERB, ': no unit to process');
end;

function ExitCodeOf(const pO: TGpaOptions; const pUnits: TArray<TGpaUnit>; const pGate: TGpaGate): Integer;
var
  U: TGpaUnit;
begin
  Result:= EXIT_OK;
  if pGate.Ran and not pGate.Applied then
  begin
    if MatchStr(pGate.Refusal, [CGateDirtyBaseline, CGateWriteFailed, CGateCompilerUnavailable]) then Exit(EXIT_USAGE);
    Exit(EXIT_FAIL);
  end;
  for U in pUnits do
    if (U.Status = ST_REFUSED) or (U.Status = ST_NO_INSERT) then Exit(EXIT_FAIL)
    else if (pO.InFile <> '') and (U.Status <> ST_PLANNED) and (U.Status <> ST_APPLIED) then Exit(EXIT_FAIL);
end;

function RunGenParamArray(const pProject, pInFile: string; pJson: Boolean): Integer;
var
  O: TGpaOptions;
  Units: TArray<TGpaUnit>;
  Gate: TGpaGate;
  I: Integer;
begin
  if not ReadOptions(pProject, pInFile, pJson, O) then Exit(EXIT_USAGE);
  Gate:= Default(TGpaGate);
  try
    Units:= CollectUnits(O);
    for I:= 0 to High(Units) do
      if Units[I].Status = '' then AnalyseUnit(Units[I], O);
    if O.Apply then
    begin
      OpenGateStandDown(VERB, '');
      try
        ApplyAll(O, Units, Gate);
      finally
        CloseGateStandDown;
      end;
    end;
    if O.Json then PrintJson(O, Units, Gate) else PrintText(O, Units, Gate);
    Result:= ExitCodeOf(O, Units, Gate);
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, VERB, ': ', E.Message);
      Result:= EXIT_USAGE;
    end;
  end;
end;

end.
