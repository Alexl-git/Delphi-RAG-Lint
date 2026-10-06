unit ConvRules.ConvertRequest;

/// <summary>Pure decisions for the IDE hand-off (job C12): the request file the
/// plugin writes, its validation against the editor's own project index, the
/// editor capabilities file, and (Task 2) the component scope a run gets.</summary>
/// <remarks>Contract: docs\superpowers\specs\2026-10-06-c12-ide-convert-menu-design.md,
/// "Hand-off contract". No VCL, no engine: the model tests cover every routine.</remarks>

interface

uses
  System.SysUtils
  , ConvRules.Inheritance
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
  /// <summary>The Scope line when no request scope is in force (spec E4).</summary>
  WHOLE_UNIT_SCOPE_TEXT = 'Scope: whole unit';

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

  /// <summary>What a Convert run is restricted to: the whole unit (no request), the
  /// selected components, or every instance of the requested types on the form.</summary>
  TScopeKind = (skWholeUnit, skSelected, skForm);

  /// <summary>A request resolved against the unit's .dfm text (BuildScope).
  /// Default(TConvertScope) is the whole-unit scope.</summary>
  /// <remarks>The scope binds UnitPas ONLY: every other unit of a run is converted
  /// whole (ScopeMatchesUnits refuses a source list that is not exactly UnitPas).</remarks>
  TConvertScope = record
    /// <summary>skWholeUnit when no request scope is in force.</summary>
    Kind     : TScopeKind;
    /// <summary>The request's unit (.pas path, as the request wrote it).</summary>
    UnitPas  : string;
    /// <summary>The requested bare types (RequestedTypes), request order.</summary>
    Types    : TArray<string>;
    /// <summary>The components in scope with their .dfm types and openers: request
    /// order for skSelected, .dfm order for skForm. Never the root.</summary>
    Instances: TArray<TDfmInstance>;
    /// <summary>skSelected only: requested names the .dfm does not open below the
    /// root, request order. They never reach the engine.</summary>
    NotFound : TArray<string>;
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

/// <summary>Resolves a validated request against its unit's .dfm text (spec E6-E8).</summary>
/// <param name="AReq">A request ValidateConvertRequest accepted (exactly one unit).</param>
/// <param name="ADfmText">The text of the unit's .dfm; '' when the file is missing
/// or could not be read.</param>
/// <param name="AError">'' on success; else the refusal, naming the .dfm (the
/// request's "dfm", else the .pas with DFM_EXT).</param>
/// <returns>skSelected: each requested name the .dfm opens below the root, request
/// order, with the .dfm's own type and opener; the rest in NotFound. skForm: every
/// .dfm object below the root whose bare type equals a requested type (case-
/// insensitive), at any depth (panels, inline frames' children), .dfm order. On a
/// refusal: no instances.</returns>
/// <remarks>A binary .dfm (TPF0) and a missing / header-less one are refused for
/// BOTH scopes: neither can say which components exist, and resolving against
/// nothing would silently report every name not found. The root (Depth 0) is never an
/// instance, whatever its name or class. A request that does not list exactly one unit
/// is refused (AError), never read past its end. A name selected more than once (any
/// case) is listed once, in Instances or NotFound.</remarks>
function BuildScope(const AReq: TConvertRequest; const ADfmText: string; out AError: string): TConvertScope;

/// <summary>The scope's instance names one book converts (spec E6): those whose bare
/// .dfm type is the From type of a pair with a To type.</summary>
/// <param name="AScope">The resolved scope.</param>
/// <param name="APairs">The book's pairs (TypePairsOfText).</param>
/// <returns>Names in AScope.Instances order; [] when the book converts none of them
/// (the runner then skips the book without an engine call).</returns>
function ScopedNamesForBook(const AScope: TConvertScope; const APairs: TArray<TTypePair>): TArray<string>;

/// <summary>True when a book has a #convert pair with a To type whose From type is one
/// of ATypes (exact bare name, case-insensitive; an ancestor class does not match).</summary>
/// <param name="ARulesText">The .rules text.</param>
/// <param name="ATypes">Bare class names (RequestedTypes).</param>
/// <returns>True when the book converts at least one requested type.</returns>
function BookMatchesTypes(const ARulesText: string; const ATypes: TArray<string>): Boolean;

/// <summary>The Convert tab's Scope line (spec E4), with the 'Scope: ' prefix.</summary>
/// <param name="AScope">The scope; Default(TConvertScope) for none.</param>
/// <returns>WHOLE_UNIT_SCOPE_TEXT; 'Scope: N selected component(s) on U: a (T), ...'
/// plus '; not found on the form: x, y' when names were not found; or 'Scope: all
/// T1, T2 instances on U (N found)'. U is the unit's file name without extension.</returns>
function ScopeText(const AScope: TConvertScope): string;

/// <summary>The status line after a request was applied (spec E5).</summary>
/// <param name="AScope">The resolved scope.</param>
/// <param name="AMatchingBooks">How many books were checked for it.</param>
/// <returns>'Request from the IDE: convert &lt;ScopeText without its prefix&gt; with N
/// matching book(s) -- review and press Convert.'</returns>
function ScopeStatusText(const AScope: TConvertScope; AMatchingBooks: Integer): string;

/// <summary>The error status when no book converts a requested type (spec E3).</summary>
/// <param name="ARulesFolder">The folder holding the books.</param>
/// <param name="ATypes">The requested types.</param>
/// <returns>'No book in &lt;folder&gt; converts T1, T2 -- pick the From class on the
/// Classes tab and choose Conversion &gt; New Conversion'</returns>
function NoBookText(const ARulesFolder: string; const ATypes: TArray<string>): string;

/// <summary>Checks that a scoped run's source list is exactly the scope's unit.</summary>
/// <param name="AScope">The scope.</param>
/// <param name="AUnits">The Convert tab's source units.</param>
/// <returns>'' for skWholeUnit, or when AUnits is the one unit UnitPas (paths
/// compared case-insensitively after ExpandFileName); else the refusal, naming
/// UnitPas and the list's size.</returns>
function ScopeMatchesUnits(const AScope: TConvertScope; const AUnits: TArray<string>): string;

/// <summary>The runner's scope decision for one unit x book (spec E9; ruling B5: the
/// scope binds the request's unit ONLY).</summary>
/// <param name="AScope">The run's scope; Default(TConvertScope) for none.</param>
/// <param name="AUnitPas">The unit about to be converted.</param>
/// <param name="ARulesText">The book's text ('' when it could not be read).</param>
/// <param name="ANames">The instance names to pass as --only (ScopedNamesForBook);
/// [] when the result is False.</param>
/// <returns>True = scoped: AUnitPas is AScope.UnitPas (case-insensitive after
/// ExpandFileName) and AScope is not skWholeUnit; ANames may then be [] (the book
/// converts no instance in scope, and the runner skips it). False = convert the
/// unit whole, with no --only.</returns>
function ScopedNamesForUnit(const AScope: TConvertScope; const AUnitPas, ARulesText: string; out ANames: TArray<string>): Boolean;

/// <summary>The E10 hint appended to the engine's --only refusal.</summary>
/// <param name="AReason">The apply/1 reason.</param>
/// <returns>' -- convert all &lt;Type&gt; instances on this form, or remove the #unuse /
/// #useswap from the book' when AReason holds 'unconverted instance(s) of &lt;Type&gt;';
/// else ''.</returns>
function RefusalHint(const AReason: string): string;

/// <summary>The converted row's note for a scoped run (spec E11).</summary>
/// <param name="AOnly">The names passed as --only, in order.</param>
/// <param name="AConvertedNote">The unscoped note (ConvertedRowNote: '&lt;edits&gt;
/// edit(s), &lt;k&gt; remaining for manual work' and any C8 tail).</param>
/// <returns>'converted N of N scoped instance(s): a, b; ' + AConvertedNote.</returns>
/// <remarks>Both numbers are the REQUEST count: the engine does not report per-name
/// outcomes yet (engine ask N3, only_matched[]), so the note says what was asked.</remarks>
function ScopedConvertedNote(const AOnly: TArray<string>; const AConvertedNote: string): string;

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

const
  SCOPE_PREFIX       = 'Scope: ';
  SCOPE_SELECTED_FMT = SCOPE_PREFIX + '%d selected component(s) on %s: %s';
  SCOPE_NOT_FOUND    = '; not found on the form: ';
  SCOPE_FORM_FMT     = SCOPE_PREFIX + 'all %s instances on %s (%d found)';
  SCOPE_ITEM_FMT     = '%s (%s)';
  LIST_SEP           = ', ';
  STATUS_HEAD        = 'Request from the IDE: convert ';
  STATUS_TAIL_FMT    = ' with %d matching book(s) -- review and press Convert.';
  NO_BOOK_FMT        = 'No book in %s converts %s -- pick the From class on the Classes tab and choose Conversion > New Conversion';
  UNITS_MISMATCH_FMT = 'the scope names %s but the source list holds %d unit(s) -- clear the scope or list only that unit';
  DFM_BINARY_FMT     = 'the .dfm %s is binary -- convert it to text in the IDE first';
  DFM_MISSING_FMT    = 'the .dfm %s is missing, unreadable or has no object header -- the component scope cannot be resolved';
  UNIT_COUNT_FMT     = 'a %s request lists exactly one unit (got %d)';
  REFUSAL_MARK       = 'unconverted instance(s) of ';
  REFUSAL_HINT_FMT   = ' -- convert all %s instances on this form, or remove the #unuse / #useswap from the book';
  SCOPED_NOTE_FMT    = 'converted %d of %d scoped instance(s): %s; ';

{ The scope's word in a refusal: 'form' or 'selected'. }
function ScopeWord(AScope: TRequestScope): string;
begin
  Result:= if AScope = rsForm then 'form' else 'selected';
end;

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
    Exit(Format(UNIT_COUNT_FMT, [ScopeWord(AReq.Scope), Length(AReq.Units)]));
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

{ The request unit's .dfm path, for refusal texts: its "dfm", else beside the .pas. }
function DfmPathOf(const AUnit: TRequestUnit): string;
begin
  Result:= if AUnit.Dfm <> '' then AUnit.Dfm else ChangeFileExt(AUnit.Pas, DFM_EXT);
end;

{ The first header below the root that AName opens (case-insensitive); False when none. }
function FindBelowRoot(const AAll: TArray<TDfmInstance>; const AName: string; out AInst: TDfmInstance): Boolean;
begin
  AInst:= Default(TDfmInstance);
  for var I: TDfmInstance in AAll do
    if (I.Depth > 0) and SameText(I.Name, AName) then
    begin
      AInst:= I;
      Exit(True);
    end;
  Result:= False;
end;

{ True when AName (case-insensitive) is already one of AScope's instances or not-found names. }
function InScopeAlready(const AScope: TConvertScope; const AName: string): Boolean;
begin
  for var I: TDfmInstance in AScope.Instances do
    if SameText(I.Name, AName) then
      Exit(True);
  Result:= MatchText(AName, AScope.NotFound);
end;

function BuildScope(const AReq: TConvertRequest; const ADfmText: string; out AError: string): TConvertScope;
var
  All : TArray<TDfmInstance>;
  Inst: TDfmInstance;
begin
  AError:= '';
  Result:= Default(TConvertScope);
  if Length(AReq.Units) <> 1 then
  begin
    AError:= Format(UNIT_COUNT_FMT, [ScopeWord(AReq.Scope), Length(AReq.Units)]);
    Exit;
  end;
  Result.UnitPas:= AReq.Units[0].Pas;
  Result.Types  := RequestedTypes(AReq);
  if ADfmText.StartsWith(BINARY_DFM_SIGNATURE) then
  begin
    AError:= Format(DFM_BINARY_FMT, [DfmPathOf(AReq.Units[0])]);
    Exit;
  end;
  All:= ListDfmInstances(ADfmText);
  if Length(All) = 0 then
  begin
    AError:= Format(DFM_MISSING_FMT, [DfmPathOf(AReq.Units[0])]);
    Exit;
  end;
  if AReq.Scope = rsForm then
  begin
    Result.Kind:= skForm;
    for var I: TDfmInstance in All do
      if (I.Depth > 0) and MatchText(BareType(I.TypeName), Result.Types) then
        Result.Instances:= Result.Instances + [I];
    Exit;
  end;
  Result.Kind:= skSelected;
  for var C: TRequestComponent in AReq.Units[0].Components do
    if InScopeAlready(Result, C.Name) then
      Continue // a name selected twice (any case) is listed once
    else if FindBelowRoot(All, C.Name, Inst) then
      Result.Instances:= Result.Instances + [Inst] // the .dfm's own type and opener win over the request's
    else
      Result.NotFound:= Result.NotFound + [C.Name];
end;

function ScopedNamesForBook(const AScope: TConvertScope; const APairs: TArray<TTypePair>): TArray<string>;
begin
  Result:= nil;
  for var I: TDfmInstance in AScope.Instances do
    for var P: TTypePair in APairs do
      if (P.ToType <> '') and SameText(BareType(I.TypeName), P.FromType) then
      begin
        Result:= Result + [I.Name];
        Break;
      end;
end;

function BookMatchesTypes(const ARulesText: string; const ATypes: TArray<string>): Boolean;
begin
  for var P: TTypePair in TypePairsOfText(ARulesText) do
    if (P.ToType <> '') and MatchText(P.FromType, ATypes) then
      Exit(True);
  Result:= False;
end;

function ScopeText(const AScope: TConvertScope): string;
var
  UnitBase: string;
  Items   : TArray<string>;
begin
  UnitBase:= ChangeFileExt(ExtractFileName(AScope.UnitPas), '');
  case AScope.Kind of
    skSelected:
      begin
        Items:= nil;
        for var I: TDfmInstance in AScope.Instances do
          Items:= Items + [Format(SCOPE_ITEM_FMT, [I.Name, I.TypeName])];
        Result:= Format(SCOPE_SELECTED_FMT, [Length(AScope.Instances), UnitBase, string.Join(LIST_SEP, Items)]);
        if Length(AScope.NotFound) > 0 then
          Result:= Result + SCOPE_NOT_FOUND + string.Join(LIST_SEP, AScope.NotFound);
      end;
    skForm:
      Result:= Format(SCOPE_FORM_FMT, [string.Join(LIST_SEP, AScope.Types), UnitBase, Length(AScope.Instances)]);
    else
      Result:= WHOLE_UNIT_SCOPE_TEXT;
  end; // case
end;

function ScopeStatusText(const AScope: TConvertScope; AMatchingBooks: Integer): string;
begin
  Result:= STATUS_HEAD + Copy(ScopeText(AScope), Length(SCOPE_PREFIX) + 1, MaxInt) + Format(STATUS_TAIL_FMT, [AMatchingBooks]);
end;

function NoBookText(const ARulesFolder: string; const ATypes: TArray<string>): string;
begin
  Result:= Format(NO_BOOK_FMT, [ARulesFolder, string.Join(LIST_SEP, ATypes)]);
end;

function ScopeMatchesUnits(const AScope: TConvertScope; const AUnits: TArray<string>): string;
begin
  Result:= '';
  if AScope.Kind = skWholeUnit then
    Exit;
  if (Length(AUnits) = 1) and SameText(ExpandFileName(AUnits[0]), ExpandFileName(AScope.UnitPas)) then
    Exit;
  Result:= Format(UNITS_MISMATCH_FMT, [AScope.UnitPas, Length(AUnits)]);
end;

function ScopedNamesForUnit(const AScope: TConvertScope; const AUnitPas, ARulesText: string; out ANames: TArray<string>): Boolean;
begin
  ANames:= nil;
  Result:= (AScope.Kind <> skWholeUnit) and SameText(ExpandFileName(AUnitPas), ExpandFileName(AScope.UnitPas));
  if Result then
    ANames:= ScopedNamesForBook(AScope, TypePairsOfText(ARulesText));
end;

function RefusalHint(const AReason: string): string;
var
  P, Q: Integer;
begin
  Result:= '';
  P:= Pos(REFUSAL_MARK, AReason);
  if P = 0 then
    Exit;
  P:= P + Length(REFUSAL_MARK);
  Q:= P;
  while (Q <= Length(AReason)) and (AReason[Q] <> ' ') do
    Inc(Q);
  Result:= Format(REFUSAL_HINT_FMT, [Copy(AReason, P, Q - P)]);
end;

function ScopedConvertedNote(const AOnly: TArray<string>; const AConvertedNote: string): string;
begin
  Result:= Format(SCOPED_NOTE_FMT, [Length(AOnly), Length(AOnly), string.Join(LIST_SEP, AOnly)]) + AConvertedNote;
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
