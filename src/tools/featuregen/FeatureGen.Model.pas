unit FeatureGen.Model;

{ The feature registry read model: features\entries\*.json, groups.json and
  teams.json. Field set mirrors entry.schema.json; an absent optional field
  reads '' (0 for HomeOrder, empty array for lists). }

interface

uses
  System.SysUtils
  ;

type
  /// <summary>One flag of a cli surface (schema v2 flags[]).</summary>
  TFlag = record
    Name: string;
    Arg: string;
    Summary: string;
    /// <summary>The flag's default value; '' when none.</summary>
    DefaultValue: string;
  end;

  /// <summary>One "I want to ..." question of an entry (schema v2 questions[]).</summary>
  TQuestion = record
    Ask: string;
    Command: string;
  end;

  /// <summary>One entry surface (a cli verb, a menu path, a shortcut ...).</summary>
  /// <remarks>Only the members of this surface's Kind are filled; the rest read ''. Args is the JSON text of a non-string value.</remarks>
  TSurface = record
    Kind: string;
    Verb: string;
    Sub: string;
    Example: string;
    Path: string;
    Host: string;
    Caption: string;
    Keys: string;
    Name: string;
    Method: string;
    Tool: string;
    Args: string;
    Menu: string;
    Doc: string;
    /// <summary>cli: synopsis line (schema v2); '' when absent.</summary>
    Usage: string;
    /// <summary>cli: every flag the verb accepts (schema v2).</summary>
    Flags: TArray<TFlag>;
    /// <summary>cli: position of this surface's block in the --help verb reference (1-based); 0 when it has none (P7).</summary>
    HelpOrder: Integer;
    /// <summary>cli: the verbatim --help lines of this surface's block, first line (the usage line, original spacing) included (P7).</summary>
    Help: TArray<string>;
    /// <summary>ide-menu / ide-context / ide-about / tool-window: click-by-click steps (schema v2).</summary>
    Steps: TArray<string>;
  end;

  /// <summary>One example row of an entry.</summary>
  TExample = record
    Kind: string;
    Text: string;
    Path: string;
    Note: string;
  end;

  /// <summary>One group or team row (groups.json / teams.json).</summary>
  TNamedRow = record
    Id: string;
    Title: string;
    Order: Integer;
    Summary: string;
  end;

  /// <summary>One registry entry.</summary>
  TFeatureEntry = record
    Id: string;
    Title: string;
    Group: string;
    /// <summary>Title of Group from groups.json; '' when the group is unknown.</summary>
    GroupTitle: string;
    Owner: string;
    Status: string;
    Since: string;
    Summary: string;
    Intro: string;
    WikiPage: string;
    Audience: string;
    Notes: string;
    /// <summary>Review record for an entry with no IDE surface: cli-only, repo-tooling or standalone-app; empty = not reviewed.</summary>
    Access: string;
    SupersededBy: string;
    RemovedIn: string;
    Family: string;
    LastVerifiedDate: string;
    LastVerifiedBy: string;
    LastVerifiedBuild: string;
    /// <summary>helpContext (schema v2); defaults to Id when absent.</summary>
    HelpContext: string;
    /// <summary>verified.* (schema v2, tool-written); '' when absent.</summary>
    VerifiedDate: string;
    VerifiedBy: string;
    VerifiedBuild: string;
    VerifiedSurfaceHash: string;
    /// <summary>0 when absent.</summary>
    HomeOrder: Integer;
    Surfaces: TArray<TSurface>;
    Requires: TArray<string>;
    Aliases: TArray<string>;
    Related: TArray<string>;
    Tests: TArray<string>;
    Examples: TArray<TExample>;
    Pitfalls: TArray<string>;
    Questions: TArray<TQuestion>;
  end;

  /// <summary>The loaded registry of one repo (or fixture) root.</summary>
  TRegistry = class
  strict private
    FEntries: TArray<TFeatureEntry>;
    FGroups: TArray<TNamedRow>;
    FTeams: TArray<TNamedRow>;
    FRoot: string;
  public
    /// <summary>Loads features\entries\*.json, features\groups.json and features\teams.json under pRepo, replacing any earlier load.</summary>
    /// <param name="pRepo">Root holding a features folder.</param>
    /// <exception cref="EFeatureJson">A file is missing or malformed (message names the file).</exception>
    procedure Load(const pRepo: string);
    /// <summary>Entries sorted ordinal by Id.</summary>
    property Entries: TArray<TFeatureEntry> read FEntries;
    /// <summary>Groups in groups.json order.</summary>
    property Groups: TArray<TNamedRow> read FGroups;
    /// <summary>Teams in teams.json order.</summary>
    property Teams: TArray<TNamedRow> read FTeams;
    /// <summary>The root given to the last Load ('' before any load); the registry checks read the raw files under it.</summary>
    property Root: string read FRoot;
  end;

implementation

uses
  System.Classes
  , System.IOUtils
  , System.JSON
  , System.Generics.Collections
  , System.Generics.Defaults
  , FeatureGen.Json
  ;

function StrList(pObj: TJSONValue; const pName: string): TArray<string>;
var
  lV: TJSONValue;
  i: Integer;
begin
  SetLength(Result, 0);
  if pObj is not TJSONObject then
    Exit;
  lV := TJSONObject(pObj).GetValue(pName);
  if lV is not TJSONArray then
    Exit;
  SetLength(Result, TJSONArray(lV).Count);
  for i := 0 to TJSONArray(lV).Count - 1 do
    Result[i] := TJSONArray(lV).Items[i].Value;
end;

function ObjList(pObj: TJSONValue; const pName: string): TArray<TJSONValue>;  // dl:ok duplicate-code@0666 -- REVIEWED 2026-10-19: parallel ported renderers share a shape; extracting a helper would couple outputs that must stay independent
var
  lV: TJSONValue;
  i: Integer;
begin
  SetLength(Result, 0);
  if pObj is not TJSONObject then
    Exit;
  lV := TJSONObject(pObj).GetValue(pName);
  if lV is not TJSONArray then
    Exit;
  SetLength(Result, TJSONArray(lV).Count);
  for i := 0 to TJSONArray(lV).Count - 1 do
    Result[i] := TJSONArray(lV).Items[i];
end;

function ArgsText(pObj: TJSONValue): string;
var
  lV: TJSONValue;
begin
  Result := '';
  if pObj is not TJSONObject then
    Exit;
  lV := TJSONObject(pObj).GetValue('args');
  if lV is TJSONString then
    Result := TJSONString(lV).Value
  else if lV <> nil then
    Result := lV.ToString;
end;

function ToSurface(pObj: TJSONValue): TSurface;
var
  lItems: TArray<TJSONValue>;
  i: Integer;
begin
  Result.Kind := Prop(pObj, 'type');
  Result.Verb := Prop(pObj, 'verb');
  Result.Sub := Prop(pObj, 'sub');
  Result.Example := Prop(pObj, 'example');
  Result.Path := Prop(pObj, 'path');
  Result.Host := Prop(pObj, 'host');
  Result.Caption := Prop(pObj, 'caption');
  Result.Keys := Prop(pObj, 'keys');
  Result.Name := Prop(pObj, 'name');
  Result.Method := Prop(pObj, 'method');
  Result.Tool := Prop(pObj, 'tool');
  Result.Args := ArgsText(pObj);
  Result.Menu := Prop(pObj, 'menu');
  Result.Doc := Prop(pObj, 'doc');
  Result.Usage := Prop(pObj, 'usage');
  Result.Steps := StrList(pObj, 'steps');
  Result.Help := StrList(pObj, 'help');
  Result.HelpOrder := StrToIntDef(Prop(pObj, 'helpOrder'), 0);
  lItems := ObjList(pObj, 'flags');
  SetLength(Result.Flags, Length(lItems));
  for i := 0 to High(lItems) do
  begin
    Result.Flags[i].Name := Prop(lItems[i], 'name');
    Result.Flags[i].Arg := Prop(lItems[i], 'arg');
    Result.Flags[i].Summary := Prop(lItems[i], 'summary');
    Result.Flags[i].DefaultValue := Prop(lItems[i], 'default');
  end;
end;

function ToEntry(pObj: TJSONValue): TFeatureEntry;
var
  lLv, lVer: TJSONValue;
  lItems: TArray<TJSONValue>;
  i: Integer;
begin
  Result := Default(TFeatureEntry);
  Result.Id := Prop(pObj, 'id');
  Result.Title := Prop(pObj, 'title');
  Result.Group := Prop(pObj, 'group');
  Result.Owner := Prop(pObj, 'owner');
  Result.Status := Prop(pObj, 'status');
  Result.Since := Prop(pObj, 'since');
  Result.Summary := Prop(pObj, 'summary');
  Result.Intro := Prop(pObj, 'intro');
  Result.WikiPage := Prop(pObj, 'wikiPage');
  Result.Audience := Prop(pObj, 'audience');
  Result.Notes := Prop(pObj, 'notes');
  Result.Access := Prop(pObj, 'access');
  Result.SupersededBy := Prop(pObj, 'supersededBy');
  Result.RemovedIn := Prop(pObj, 'removedIn');
  Result.Family := Prop(pObj, 'family');
  Result.HomeOrder := StrToIntDef(Prop(pObj, 'homeOrder'), 0);
  lLv := TJSONObject(pObj).GetValue('lastVerified');
  Result.LastVerifiedDate := Prop(lLv, 'date');
  Result.LastVerifiedBy := Prop(lLv, 'by');
  Result.LastVerifiedBuild := Prop(lLv, 'build');
  Result.HelpContext := Prop(pObj, 'helpContext');
  if Result.HelpContext = '' then
    Result.HelpContext := Result.Id;
  lVer := TJSONObject(pObj).GetValue('verified');
  Result.VerifiedDate := Prop(lVer, 'date');
  Result.VerifiedBy := Prop(lVer, 'by');
  Result.VerifiedBuild := Prop(lVer, 'build');
  Result.VerifiedSurfaceHash := Prop(lVer, 'surfaceHash');
  Result.Pitfalls := StrList(pObj, 'pitfalls');
  lItems := ObjList(pObj, 'questions');
  SetLength(Result.Questions, Length(lItems));
  for i := 0 to High(lItems) do
  begin
    Result.Questions[i].Ask := Prop(lItems[i], 'ask');
    Result.Questions[i].Command := Prop(lItems[i], 'command');
  end;
  Result.Requires := StrList(pObj, 'requires');
  Result.Aliases := StrList(pObj, 'aliases');
  Result.Related := StrList(pObj, 'related');
  Result.Tests := StrList(pObj, 'tests');
  lItems := ObjList(pObj, 'surfaces');
  SetLength(Result.Surfaces, Length(lItems));
  for i := 0 to High(lItems) do
    Result.Surfaces[i] := ToSurface(lItems[i]);
  lItems := ObjList(pObj, 'examples');
  SetLength(Result.Examples, Length(lItems));
  for i := 0 to High(lItems) do
  begin
    Result.Examples[i].Kind := Prop(lItems[i], 'kind');
    Result.Examples[i].Text := Prop(lItems[i], 'text');
    Result.Examples[i].Path := Prop(lItems[i], 'path');
    Result.Examples[i].Note := Prop(lItems[i], 'note');
  end;
end;

function LoadRows(const pPath, pArrayName: string): TArray<TNamedRow>;
var
  lRoot: TJSONValue;
  lItems: TArray<TJSONValue>;
  i: Integer;
begin
  lRoot := ReadJsonFile(pPath);
  try
    lItems := ObjList(lRoot, pArrayName);
    SetLength(Result, Length(lItems));
    for i := 0 to High(lItems) do
    begin
      Result[i].Id := Prop(lItems[i], 'id');
      Result[i].Title := Prop(lItems[i], 'title');
      Result[i].Order := StrToIntDef(Prop(lItems[i], 'order'), 0);
      Result[i].Summary := Prop(lItems[i], 'summary');
    end;
  finally
    lRoot.Free;
  end;
end;

procedure TRegistry.Load(const pRepo: string);
var
  lFiles: TArray<string>;
  lFile: string;
  lRoot: TJSONValue;
  lList: TList<TFeatureEntry>;
  lE: TFeatureEntry;
  lRow: TNamedRow;
  i: Integer;
begin
  FRoot := pRepo;
  FGroups := LoadRows(TPath.Combine(pRepo, 'features\groups.json'), 'groups');
  FTeams := LoadRows(TPath.Combine(pRepo, 'features\teams.json'), 'teams');
  lFiles := TDirectory.GetFiles(TPath.Combine(pRepo, 'features\entries'), '*.json');
  lList := TList<TFeatureEntry>.Create;
  try
    for lFile in lFiles do
    begin
      lRoot := ReadJsonFile(lFile);
      try
        if lRoot is not TJSONObject then
          raise EFeatureJson.CreateFmt('Entry is not a JSON object: %s', [lFile]);
        lE := ToEntry(lRoot);
      finally
        lRoot.Free;
      end;
      for lRow in FGroups do
        if lRow.Id = lE.Group then
          lE.GroupTitle := lRow.Title;
      lList.Add(lE);
    end;
    lList.Sort(TComparer<TFeatureEntry>.Construct(
      function(const pA, pB: TFeatureEntry): Integer
      begin
        Result := CompareStr(pA.Id, pB.Id);
      end));
    SetLength(FEntries, lList.Count);
    for i := 0 to lList.Count - 1 do
      FEntries[i] := lList[i];
  finally
    lList.Free;
  end;
end;

end.
