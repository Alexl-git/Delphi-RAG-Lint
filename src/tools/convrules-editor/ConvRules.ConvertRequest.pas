unit ConvRules.ConvertRequest;

/// <summary>Pure decisions for the IDE hand-off (job C12): the request file the
/// plugin writes, its validation against the editor's own project index, the
/// editor capabilities file, and (Task 2) the component scope a run gets.</summary>
/// <remarks>Contract: docs\superpowers\specs\2026-10-06-c12-ide-convert-menu-design.md,
/// "Hand-off contract". No VCL, no engine: the model tests cover every routine.</remarks>

interface

uses
  System.SysUtils
  ;

const
  /// <summary>The one request schema this editor reads.</summary>
  REQUEST_SCHEMA = 'convert-request/1';
  /// <summary>Schema of the file --write-capabilities produces.</summary>
  CAPABILITIES_SCHEMA = 'editor-capabilities/1';
  /// <summary>Version of the request contract this editor implements.</summary>
  CAPABILITY_CONVERT_REQUEST = 1;
  /// <summary>Refusal text for scope "project" (reserved in the contract).</summary>
  SCOPE_PROJECT_UNSUPPORTED = 'Project-wide scope is not supported by this editor version';

type
  /// <summary>The request's scope. rsProject is parsed so the refusal can name it.</summary>
  TRequestScope = (rsSelected, rsForm, rsProject);

  /// <summary>One component the IDE selected: name and bare class.</summary>
  TRequestComponent = record
    /// <summary>The component's Name on the form ("name"); never empty.</summary>
    Name    : string;
    /// <summary>The bare class as the IDE reports it ("type", e.g. TTable); never empty.</summary>
    TypeName: string;
  end;

  /// <summary>One unit of the request (exactly one for selected / form).</summary>
  TRequestUnit = record
    /// <summary>Absolute path of the unit's .pas ("pas"); never empty.</summary>
    Pas       : string;
    /// <summary>Absolute path of the unit's .dfm ("dfm"); '' when absent.</summary>
    Dfm       : string;
    /// <summary>The form / data module class ("form_class"); '' when absent.</summary>
    FormClass : string;
    /// <summary>The selected components ("components"); at least one.</summary>
    Components: TArray<TRequestComponent>;
  end;

  /// <summary>A parsed request. Unknown keys are dropped on read.</summary>
  TConvertRequest = record
    /// <summary>Always REQUEST_SCHEMA once parsed.</summary>
    Schema     : string;
    /// <summary>Write time as the plugin stamped it ("written"); informational.</summary>
    Written    : string;
    /// <summary>Who wrote the request ("source", e.g. ide-menu); informational.</summary>
    Source     : string;
    /// <summary>Process id of the IDE ("ide_pid"); 0 when absent.</summary>
    IdePid     : Integer;
    /// <summary>The request's scope; never rsProject in an accepted request.</summary>
    Scope      : TRequestScope;
    /// <summary>The IDE's active project file ("project_file"); required.</summary>
    ProjectFile: string;
    /// <summary>The project index the plugin resolved ("project_db"); required.</summary>
    ProjectDb  : string;
    /// <summary>The IDE's active platform ("platform"); '' when absent.</summary>
    Platform   : string;
    /// <summary>Absolute path of the folder holding the .rules books
    /// ("rules_folder"); OPTIONAL -- '' when absent, and the caller then falls back
    /// to its own rules folder.</summary>
    RulesFolder: string;
    /// <summary>The request's units ("units"); at least one.</summary>
    Units      : TArray<TRequestUnit>;
  end;

  /// <summary>ParseConvertRequest's answer: Ok with Request, or Error.</summary>
  TRequestOutcome = record
    /// <summary>True when the document is an acceptable request.</summary>
    Ok     : Boolean;
    /// <summary>The parsed request; meaningful only when Ok.</summary>
    Request: TConvertRequest;
    /// <summary>The first problem found; non-empty exactly when not Ok.</summary>
    Error  : string;
  end;

/// <summary>Reads a convert-request/1 document.</summary>
/// <param name="AJson">The file's text (UTF-8 already decoded).</param>
/// <returns>Ok=False with the first problem named: not a JSON object, wrong or
/// missing schema, unknown or project scope, a missing required key (project_file,
/// project_db, units, a unit's pas, its components, a component's name or type),
/// or a key of the wrong JSON type. Every refusal names the key.</returns>
/// <remarks>Never raises: every read is type-checked (no casts that can fail).
/// Unknown keys are ignored. Optional keys: written, source, ide_pid, platform,
/// rules_folder, a unit's dfm and form_class -- absent reads as ''/0, present with
/// the wrong JSON type is refused. Structural checks only; ValidateConvertRequest
/// does the ones that need the editor's own state.</remarks>
function ParseConvertRequest(const AJson: string): TRequestOutcome;

/// <summary>Checks a parsed request against the editor's project DB and project
/// file and the file system.</summary>
/// <param name="AReq">A request ParseConvertRequest accepted.</param>
/// <param name="AProjectDb">GEditorProjectDb.</param>
/// <param name="AProjectFile">ProjectFileForDb(GEditorProjectDb).</param>
/// <param name="AFileExists">File probe (injected for the tests).</param>
/// <returns>'' when valid; else the first problem, naming both paths on a mismatch.
/// Paths compare case-insensitively after ExpandFileName.</returns>
/// <remarks>A project_db other than the editor's is refused, never adopted: the
/// Convert run reindexes `index --project <file> --db <db>` and a foreign pair would
/// re-scope an index. A selected / form request must list exactly one unit.</remarks>
function ValidateConvertRequest(const AReq: TConvertRequest; const AProjectDb, AProjectFile: string;
  const AFileExists: TFunc<string, Boolean>): string;

/// <summary>The distinct bare types of every component, request order, first
/// spelling kept (compared case-insensitively).</summary>
/// <param name="AReq">The request.</param>
/// <returns>E.g. ['TLabel', 'TButton'].</returns>
function RequestedTypes(const AReq: TConvertRequest): TArray<string>;

/// <summary>The capabilities document, one line, no whitespace.</summary>
/// <returns>{"schema":"editor-capabilities/1","convert_request":1}</returns>
function CapabilitiesJson: string;

/// <summary>Writes CapabilitiesJson to APath (UTF-8, no BOM), creating the folder.</summary>
/// <param name="APath">Target file. A bare file name (no folder part) is written to
/// the current folder and no folder is created.</param>
/// <returns>0 written; 1 any failure (never raises).</returns>
function WriteCapabilitiesFile(const APath: string): Integer;

implementation

uses
  System.IOUtils
  , System.JSON
  , System.StrUtils
  ;

function Fail(const AText: string; out AError: string): Boolean;
begin
  AError:= AText;
  Result:= False;
end;

{ Reads AKey of AObj as a string. Absent or null: AValue = '' -- refused when
  ARequired. Present but not a JSON string: refused, naming the key. An empty
  string for a required key counts as missing. }
function ReadStr(AObj: TJSONObject; const AKey: string; ARequired: Boolean; out AValue, AError: string): Boolean;
var
  V: TJSONValue;
begin
  AValue:= '';
  AError:= '';
  V:= AObj.GetValue(AKey);
  if (V <> nil) and not (V is TJSONNull) then
  begin
    if not (V is TJSONString) then
      Exit(Fail(Format('"%s" is not a string', [AKey]), AError));
    AValue:= V.Value;
  end;
  if ARequired and (Trim(AValue) = '') then
    Exit(Fail(Format('"%s" is missing', [AKey]), AError));
  Result:= True;
end;

{ Reads AKey of AObj as a non-empty JSON array; refused (key named) when absent,
  of another type or empty. }
function ReadArray(AObj: TJSONObject; const AKey, AOwner: string; out AArr: TJSONArray; out AError: string): Boolean;
var
  V: TJSONValue;
begin
  AArr:= nil;
  AError:= '';
  V:= AObj.GetValue(AKey);
  if (V = nil) or (V is TJSONNull) then
    Exit(Fail(Format('%s has no "%s"', [AOwner, AKey]), AError));
  if not (V is TJSONArray) then
    Exit(Fail(Format('"%s" of %s is not an array', [AKey, AOwner]), AError));
  AArr:= TJSONArray(V);
  if AArr.Count = 0 then
    Exit(Fail(Format('%s lists no %s', [AOwner, AKey]), AError));
  Result:= True;
end;

function ParseScope(const AText: string; out AScope: TRequestScope): Boolean;
begin
  Result:= True;
  AScope:= rsSelected;
  if SameText(AText, 'form') then
    AScope:= rsForm
  else if SameText(AText, 'project') then
    AScope:= rsProject
  else if not SameText(AText, 'selected') then
    Result:= False;
end;

function ParseComponent(AValue: TJSONValue; out AComp: TRequestComponent; out AError: string): Boolean;
begin
  AComp:= Default(TRequestComponent);
  if not (AValue is TJSONObject) then
    Exit(Fail('a component entry is not an object', AError));
  if not ReadStr(TJSONObject(AValue), 'name', False, AComp.Name, AError)
    or not ReadStr(TJSONObject(AValue), 'type', False, AComp.TypeName, AError) then
    Exit(False);
  AComp.Name    := Trim(AComp.Name);
  AComp.TypeName:= Trim(AComp.TypeName);
  if AComp.Name = '' then
    Exit(Fail('a component has no "name"', AError));
  if AComp.TypeName = '' then
    Exit(Fail(Format('component %s has no "type"', [AComp.Name]), AError));
  Result:= True;
end;

function ParseUnit(AValue: TJSONValue; out AUnit: TRequestUnit; out AError: string): Boolean;
var
  Obj: TJSONObject;
  Arr: TJSONArray;
  C  : TRequestComponent;
begin
  AUnit:= Default(TRequestUnit);
  if not (AValue is TJSONObject) then
    Exit(Fail('a unit entry is not an object', AError));
  Obj:= TJSONObject(AValue);
  if not ReadStr(Obj, 'pas', True, AUnit.Pas, AError)
    or not ReadStr(Obj, 'dfm', False, AUnit.Dfm, AError)
    or not ReadStr(Obj, 'form_class', False, AUnit.FormClass, AError)
    or not ReadArray(Obj, 'components', 'unit ' + AUnit.Pas, Arr, AError) then
    Exit(False);
  for var Item: TJSONValue in Arr do
  begin
    if not ParseComponent(Item, C, AError) then
      Exit(False);
    AUnit.Components:= AUnit.Components + [C];
  end;
  Result:= True;
end;

{ Reads the optional integer "ide_pid": absent or null = 0; anything but an
  integral JSON number is refused. }
function ReadPid(AObj: TJSONObject; out APid: Integer; out AError: string): Boolean;
var
  V: TJSONValue;
begin
  APid:= 0;
  AError:= '';
  V:= AObj.GetValue('ide_pid');
  if (V = nil) or (V is TJSONNull) then
    Exit(True);
  if not (V is TJSONNumber) or not TryStrToInt(V.Value, APid) then
    Exit(Fail('"ide_pid" is not an integer', AError));
  Result:= True;
end;

{ Schema and scope: the checks that decide whether the rest is read at all. }
function ParseHeader(AObj: TJSONObject; var AReq: TConvertRequest; out AError: string): Boolean;
var
  ScopeText: string;
begin
  if not ReadStr(AObj, 'schema', True, AReq.Schema, AError) then
    Exit(False);
  if AReq.Schema <> REQUEST_SCHEMA then
    Exit(Fail(Format('unsupported request schema "%s" (this editor reads %s)', [AReq.Schema, REQUEST_SCHEMA]), AError));
  if not ReadStr(AObj, 'scope', True, ScopeText, AError) then
    Exit(False);
  if not ParseScope(ScopeText, AReq.Scope) then
    Exit(Fail(Format('unknown scope "%s" (selected or form)', [ScopeText]), AError));
  if AReq.Scope = rsProject then
    Exit(Fail(SCOPE_PROJECT_UNSUPPORTED, AError));
  Result:= True;
end;

{ The required project pair and the optional IDE pid. }
function ReadProjectKeys(AObj: TJSONObject; var AReq: TConvertRequest; out AError: string): Boolean;
begin
  Result:= ReadStr(AObj, 'project_file', True, AReq.ProjectFile, AError)
    and ReadStr(AObj, 'project_db', True, AReq.ProjectDb, AError)
    and ReadPid(AObj, AReq.IdePid, AError);
end;

{ The optional informational keys and rules_folder. }
function ReadInfoKeys(AObj: TJSONObject; var AReq: TConvertRequest; out AError: string): Boolean;
begin
  Result:= ReadStr(AObj, 'written', False, AReq.Written, AError)
    and ReadStr(AObj, 'source', False, AReq.Source, AError)
    and ReadStr(AObj, 'platform', False, AReq.Platform, AError)
    and ReadStr(AObj, 'rules_folder', False, AReq.RulesFolder, AError);
end;

{ "units": a non-empty array of unit objects. }
function ParseUnits(AObj: TJSONObject; out AUnits: TArray<TRequestUnit>; out AError: string): Boolean;
var
  Arr: TJSONArray;
  U  : TRequestUnit;
begin
  AUnits:= nil;
  if not ReadArray(AObj, 'units', 'the request', Arr, AError) then
    Exit(False);
  for var Item: TJSONValue in Arr do
  begin
    if not ParseUnit(Item, U, AError) then
      Exit(False);
    AUnits:= AUnits + [U];
  end;
  Result:= True;
end;

{ The body of ParseConvertRequest over a parsed root object. }
function ParseRequestObject(AObj: TJSONObject; out AReq: TConvertRequest; out AError: string): Boolean;
begin
  AReq:= Default(TConvertRequest);
  Result:= ParseHeader(AObj, AReq, AError)
    and ReadProjectKeys(AObj, AReq, AError)
    and ReadInfoKeys(AObj, AReq, AError)
    and ParseUnits(AObj, AReq.Units, AError);
end;

function ParseConvertRequest(const AJson: string): TRequestOutcome;
var
  Root: TJSONValue;
begin
  Result:= Default(TRequestOutcome);
  Root:= TJSONObject.ParseJSONValue(AJson);
  try
    if not (Root is TJSONObject) then
      Result.Error:= 'the request is not a JSON object'
    else
      Result.Ok:= ParseRequestObject(TJSONObject(Root), Result.Request, Result.Error);
  finally
    Root.Free;
  end;
end;

function ValidateConvertRequest(const AReq: TConvertRequest; const AProjectDb, AProjectFile: string;
  const AFileExists: TFunc<string, Boolean>): string;
begin
  Result:= '';
  if not SameText(ExpandFileName(AReq.ProjectDb), ExpandFileName(AProjectDb)) then
    Exit(Format('the request''s project index %s is not this editor''s (%s) -- launch the editor with --project-db for that project',
      [AReq.ProjectDb, AProjectDb]));
  if not SameText(ExpandFileName(AReq.ProjectFile), ExpandFileName(AProjectFile)) then
    Exit(Format('the request''s project file %s is not the one the project index belongs to (%s)', [AReq.ProjectFile, AProjectFile]));
  if Length(AReq.Units) <> 1 then
    Exit(Format('a %s request lists exactly one unit (got %d)', [if AReq.Scope = rsForm then 'form' else 'selected', Length(AReq.Units)]));
  if not AFileExists(AReq.Units[0].Pas) then
    Exit(Format('the unit %s does not exist', [AReq.Units[0].Pas]));
end;

function RequestedTypes(const AReq: TConvertRequest): TArray<string>;
begin
  Result:= nil;
  for var U: TRequestUnit in AReq.Units do
    for var C: TRequestComponent in U.Components do
      if not MatchText(C.TypeName, Result) then
        Result:= Result + [C.TypeName];
end;

function CapabilitiesJson: string;
begin
  Result:= Format('{"schema":"%s","convert_request":%d}', [CAPABILITIES_SCHEMA, CAPABILITY_CONVERT_REQUEST]);
end;

function WriteCapabilitiesFile(const APath: string): Integer;
var
  Dir: string;
begin
  try
    Dir:= ExtractFileDir(APath);
    if Dir <> '' then
      TDirectory.CreateDirectory(Dir);
    TFile.WriteAllBytes(APath, TEncoding.UTF8.GetBytes(CapabilitiesJson));
    Result:= 0;
  except
    on Exception do
      Result:= 1; // the exit code is the report; a GUI exe has no stderr to print to
  end;
end;

end.
