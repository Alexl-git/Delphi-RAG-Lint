unit DRagLint.CLI.RepoFieldUsage;

{ drag-lint 1.56 -- lane FUSAGE: the `repo field-usage` sub-verb. It answers, for a list of field
  names, where the PROJECT index finds each one used (DFM control, grid column, lookup, code); the
  query itself is DRagLint.FieldRepo.FieldUsage.FieldUseKinds. It reads the project index, no field
  repository: DRagLint.CLI.Repo dispatches here before it resolves one. The Select Fields dialog of
  the IDE plugin runs it to draw the usage icons. }

interface

uses
  FireDAC.Comp.Client;

const
  /// <summary>This unit's part of the `repo` sub-verb list in the "use one of" message.</summary>
  REPO_FIELDUSAGE_SUBS = ', field-usage';

/// <summary>True for the sub-verb this unit runs.</summary>
/// <param name="pSub">The `repo` sub-verb.</param>
/// <returns>True for field-usage.</returns>
function IsRepoFieldUsageSub(const pSub: string): Boolean;

/// <summary>Runs `repo field-usage --fields "A,B,C" [--json] [--db file | --project file]`.</summary>
/// <param name="pSub">The sub-verb, IsRepoFieldUsageSub(pSub) is True.</param>
/// <param name="pProject">--project, '' when absent.</param>
/// <param name="pJson">--json; without it one line "FIELD: dfm, grid" per used field is printed.</param>
/// <returns>0 = ok; 1 = no project index or it cannot be opened; 2 = usage error (no --fields).</returns>
/// <remarks>The index is --db when given, else the one the manifest names for --project.</remarks>
function RunRepoFieldUsageVerb(const pSub, pProject: string; pJson: Boolean): Integer;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DRagLint.CLI.ConsumerDbs,
  DRagLint.CLI.Common,
  DRagLint.Index.Manifest,
  DRagLint.FieldRepo.FieldUsage;

const
  EXIT_OK    = 0;
  EXIT_FAIL  = 1;
  EXIT_USAGE = 2;
  SUB_VERB   = 'field-usage';
  KIND_WORDS: array[TFieldUseKind] of string = ('dfm', 'grid', 'lookup', 'code');

function CommandLineValue(const pFlag: string): string;
var
  VI: Integer;
begin
  Result:= '';
  for VI:= 1 to ParamCount - 1 do
    if SameText(ParamStr(VI), pFlag) then Exit(ParamStr(VI + 1));
end;

function IsRepoFieldUsageSub(const pSub: string): Boolean;
begin
  Result:= SameText(pSub, SUB_VERB);
end;

// --fields value -> names: comma separated, trimmed, upper-cased, no duplicates.
function SplitFieldNames(const pFields: string): TArray<string>;
var
  VList: TList<string>;
  VName: string;
begin
  VList:= TList<string>.Create;
  try
    for VName in pFields.Split([',']) do
      if (Trim(VName) <> '') and not VList.Contains(UpperCase(Trim(VName))) then
        VList.Add(UpperCase(Trim(VName)));
    Result:= VList.ToArray;
  finally
    VList.Free;
  end;
end;

function KindWords(pKinds: TFieldUseKinds): TArray<string>;
var
  VKind: TFieldUseKind;
begin
  Result:= nil;
  for VKind:= Low(TFieldUseKind) to High(TFieldUseKind) do
    if VKind in pKinds then Result:= Result + [KIND_WORDS[VKind]];
end;

function JsonString(const pText: string): string;
begin
  Result:= '"' + StringReplace(StringReplace(pText, '\', '\\', [rfReplaceAll]), '"', '\"', [rfReplaceAll]) + '"';
end;

// The one-line JSON answer (usage array of field + kinds); a field with no use is omitted.
function FieldUsageJson(pProjectDb: TFDConnection; const pFields: TArray<string>): string;
var
  VField: string;
  VKinds: TFieldUseKinds;
  VWord: string;
  VQuoted: TArray<string>;
  VItems: TArray<string>;
begin
  VItems:= nil;
  for VField in pFields do
  begin
    VKinds:= FieldUseKinds(pProjectDb, VField);
    if VKinds = [] then Continue;
    VQuoted:= nil;
    for VWord in KindWords(VKinds) do VQuoted:= VQuoted + [JsonString(VWord)];
    VItems:= VItems + ['{"field":' + JsonString(VField) + ',"kinds":[' + string.Join(',', VQuoted) + ']}'];
  end;
  Result:= '{"usage":[' + string.Join(',', VItems) + ']}';
end;

{ --db when given, else the project index the manifest names for --project; '' = none found. }
function ResolveUsageDb(const pProject: string): string;
var
  VManifest: TIndexManifest;
  VClaimants: TArray<string>;
begin
  Result:= CommandLineValue('--db');
  if (Result <> '') or (pProject = '') then Exit;
  VManifest:= LoadManifestForProject(ExtractFilePath(ParamStr(0)), pProject);
  if ResolveOwnProjectDb(VManifest, pProject, Result, VClaimants) <> pdmUnique then Result:= '';
end;

function RunRepoFieldUsageVerb(const pSub, pProject: string; pJson: Boolean): Integer;
var
  VFields: TArray<string>;
  VDbFile: string;
  VDb: TFDConnection;
  VLines: TStringList;
  VField: string;
  VKinds: TFieldUseKinds;
begin
  VFields:= SplitFieldNames(CommandLineValue('--fields'));
  if Length(VFields) = 0 then
  begin
    Writeln(ErrOutput, 'repo ', pSub, ': give --fields "A,B,C"');
    Exit(EXIT_USAGE);
  end;
  VDbFile:= ResolveUsageDb(pProject);
  if (VDbFile = '') or not FileExists(VDbFile) then
  begin
    Writeln(ErrOutput, 'repo ', pSub, ': no project index; give --db <file> or --project <project file> with an index');
    Exit(EXIT_FAIL);
  end;
  VDb:= TFDConnection.Create(nil);
  try
    VDb.DriverName:= 'SQLite';
    VDb.Params.Values['Database']:= VDbFile;
    { opened read-write on purpose (a WAL index cannot be opened SQLITE_OPEN_READONLY without its -shm); this unit only reads }
    VDb.LoginPrompt:= False;
    try
      VDb.Connected:= True;
    except
      on E: Exception do
      begin
        Writeln(ErrOutput, 'repo ', pSub, ': cannot open ', VDbFile, ': ', E.Message);
        Exit(EXIT_FAIL);
      end;
    end;
    if pJson then Writeln(FieldUsageJson(VDb, VFields))
    else
    begin
      VLines:= TStringList.Create;
      try
        for VField in VFields do
        begin
          VKinds:= FieldUseKinds(VDb, VField);
          if VKinds <> [] then VLines.Add(VField + ': ' + string.Join(', ', KindWords(VKinds)));
        end;
        Write(VLines.Text);
      finally
        VLines.Free;
      end;
    end;
    Result:= EXIT_OK;
  finally
    VDb.Free;
  end;
end;

end.
