unit DRagLint.Report.CycloneDx;

{ drag-lint 1.56 -- lane SBOM-1: the CycloneDX 1.6 JSON document of the `sbom` verb.
  Pure: no database, no clock, no file but the catalogue. DRagLint.CLI.Sbom reads the indexes into a
  TSbomModel (units + uses edges); this unit groups the units into components and renders the document.

  GROUPING (one component per unit group), in this order for each unit:
    1. a unit WITH a path: the first catalogue row one of whose `paths` masks matches the path;
    2. a unit WITHOUT a path (no source in any index): the first row one of whose `units` patterns matches
       the name -- name-only evidence, said so on the component (drag-lint:attribution = unit-name);
    3. a first-party unit (the caller's ruling, or a row with "firstParty": true): the application itself;
    4. any other unit with a path: one component per DIRECTORY, supplier "unknown supplier";
    5. any other unit without a path: one component per unit, supplier "unknown supplier".
  Nothing is dropped: every unit of the model lands in exactly one group.

  v1 slice (owner ruling Q2, 2026-11-27): source closure only. No MAP input, no BSI profile, no VEX.
  The document says so itself: lifecycle pre-build, a compositions entry "incomplete", and the
  drag-lint:sbom:* metadata properties. }

interface

uses
  System.JSON, System.Generics.Collections;

const
  /// <summary>The supplier name of a component no catalogue row describes.</summary>
  SBOM_UNKNOWN_SUPPLIER = 'unknown supplier';
  /// <summary>The CycloneDX specification version this unit writes.</summary>
  SBOM_SPEC_VERSION = '1.6';

type
  /// <summary>One row of the library catalogue (rules\sbom-libraries.json).</summary>
  /// <remarks>Paths are file masks matched anywhere in a unit's full path (case-insensitive, `*` and `?`).
  /// Units are unit-name patterns (a trailing `*` = prefix, else the whole name) and are consulted ONLY
  /// for a unit that has no path.</remarks>
  TSbomLibrary = record
    Key              : string;
    Name             : string;
    Supplier         : string;
    Version          : string;
    VersionFromPath  : string;
    LicenseId        : string;
    LicenseName      : string;
    LicenseExpression: string;
    Purl             : string;
    Cpe              : string;
    Paths            : TArray<string>;
    Units            : TArray<string>;
    FirstParty       : Boolean;
  end;

  /// <summary>The library catalogue: which supplier / name / version / licence a unit group carries.</summary>
  /// <remarks>Not thread-safe. Immutable after LoadFromFile.</remarks>
  TSbomCatalogue = class
  private
    FRows: TArray<TSbomLibrary>;
  public
    /// <summary>Reads and validates a catalogue file.</summary>
    /// <param name="pPath">The JSON file: an object with a "libraries" array.</param>
    /// <param name="pError">Receives the reason on False; '' on True.</param>
    /// <returns>False when the file is missing, is not JSON, has no "libraries" array, or a row has no
    /// "key" / "name", a duplicate key, an unknown member, or neither "paths" nor "units".</returns>
    function LoadFromFile(const pPath: string; out pError: string): Boolean;
    /// <summary>The first row whose `paths` match a full file path.</summary>
    /// <param name="pPath">A unit's full path.</param>
    /// <returns>The row index, or -1.</returns>
    function MatchPath(const pPath: string): Integer;
    /// <summary>The first row whose `units` match a unit name.</summary>
    /// <param name="pUnit">The unit name as written in a uses clause.</param>
    /// <returns>The row index, or -1.</returns>
    function MatchUnit(const pUnit: string): Integer;
    /// <summary>The rows in file order.</summary>
    property Rows: TArray<TSbomLibrary> read FRows;
  end;

  /// <summary>Where a unit of the closure was found.</summary>
  TSbomUnitOrigin = (
    /// <summary>A source file of the project index.</summary>
    suoProject,
    /// <summary>A source file of a library index.</summary>
    suoLibrary,
    /// <summary>Named in a uses clause, with no source in any index given.</summary>
    suoSourceless);

  /// <summary>One unit of the compile closure.</summary>
  TSbomUnit = record
    Name      : string;
    Path      : string;
    Origin    : TSbomUnitOrigin;
    FirstParty: Boolean;
  end;

  /// <summary>One uses edge between two units of the model, by unit index.</summary>
  TSbomEdge = record
    FromUnit: Integer;
    ToUnit  : Integer;
  end;

  /// <summary>What the `sbom` verb read: the application, its units and their uses edges.</summary>
  /// <remarks>Owns its lists. Not thread-safe.</remarks>
  TSbomModel = class
  private
    FUnits: TList<TSbomUnit>;
    FEdges: TList<TSbomEdge>;
    FAppName: string;
    FAppVersion: string;
    FExeName: string;
    FExeSha512: string;
    FToolVersion: string;
    FTimestamp: string;
    FSerialNumber: string;
    FLibraryIndexUsed: Boolean;
  public
    /// <summary>The application name (metadata.component.name).</summary>
    property AppName: string read FAppName write FAppName;
    /// <summary>The application version, or '' = not stated (the member is then left out).</summary>
    property AppVersion: string read FAppVersion write FAppVersion;
    /// <summary>File name of the delivered executable, or ''.</summary>
    property ExeName: string read FExeName write FExeName;
    /// <summary>Lower-case hex SHA-512 of the delivered executable, or ''.</summary>
    property ExeSha512: string read FExeSha512 write FExeSha512;
    /// <summary>The drag-lint version (metadata.tools).</summary>
    property ToolVersion: string read FToolVersion write FToolVersion;
    /// <summary>UTC time stamp, ISO 8601 (metadata.timestamp).</summary>
    property Timestamp: string read FTimestamp write FTimestamp;
    /// <summary>The document serial number, `urn:uuid:...`.</summary>
    property SerialNumber: string read FSerialNumber write FSerialNumber;
    /// <summary>True when a library index was read, so library units were walked transitively.</summary>
    property LibraryIndexUsed: Boolean read FLibraryIndexUsed write FLibraryIndexUsed;
    constructor Create;
    destructor Destroy; override;
    /// <summary>Adds one unit.</summary>
    /// <returns>Its index, for AddEdge.</returns>
    function AddUnit(const pName, pPath: string; pOrigin: TSbomUnitOrigin; pFirstParty: Boolean): Integer;
    /// <summary>Adds one uses edge between two units added before.</summary>
    procedure AddEdge(pFromUnit, pToUnit: Integer);
    /// <summary>The units, in the order added.</summary>
    property Units: TList<TSbomUnit> read FUnits;
    /// <summary>The uses edges.</summary>
    property Edges: TList<TSbomEdge> read FEdges;
  end;

/// <summary>Renders the CycloneDX 1.6 document of a model.</summary>
/// <param name="pModel">The closure. Not modified.</param>
/// <param name="pCatalogue">The loaded library catalogue.</param>
/// <param name="pUnknown">Receives one line per component that no catalogue row describes: the
/// component's bom-ref, a tab, and the directory (or, for a unit without source, the unit name).</param>
/// <returns>The document; the caller frees it. One component per unit group, every component with
/// a dependencies entry.</returns>
function BuildCycloneDx(const pModel: TSbomModel; const pCatalogue: TSbomCatalogue;
  out pUnknown: TArray<string>): TJSONObject;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Masks, System.RegularExpressions,
  System.Generics.Defaults;

const
  CNoRow = -1;
  CKeyApp = 'app';
  CRefApp = 'app:';
  CRefLib = 'lib:';
  CRefUnknownDir = 'unknown-dir:';
  CRefUnknownUnit = 'unknown-unit:';
  CTypeLibrary = 'library';
  CTypeApplication = 'application';
  CPropPrefix = 'drag-lint:';
  CJName = 'name';
  CJValue = 'value';
  CJVersion = 'version';
  CJType = 'type';
  CJBomRef = 'bom-ref';
  CJLicense = 'license';
  CJProperties = 'properties';
  CEvidenceSource = 'source';
  CEvidenceSourceless = 'sourceless';
  CEvidenceMixed = 'mixed';
  CAttributionPath = 'path';
  CAttributionUnitName = 'unit-name';
  CAttributionNone = 'none';
  CAttributionFirstParty = 'first-party';
  CScopeText = 'source closure of the project index; no MAP input: units linked from DCUs that no ' +
    'indexed source names, runtime packages and DLLs are not listed';
  CLibIndexYes = 'read: library units walked transitively';
  CLibIndexNo = 'none: direct uses only, library units attributed by name, their own uses not walked';
  CRowMembers: array[0..12] of string = ('key', 'name', 'supplier', 'version', 'versionFromPath',
    'licenseId', 'licenseName', 'licenseExpression', 'purl', 'cpe', 'paths', 'units', 'firstParty');

type
  TGroupKind = (gkApp, gkCatalogue, gkUnknownDir, gkUnknownUnit);

  { One component in the making. Owned by the builder's group list. }
  TSbomGroup = class
  private
    FKind         : TGroupKind;
    FRef          : string;
    FRow          : Integer;
    FDir          : string;
    FUnits        : TStringList;
    FPaths        : TStringList;
    FDeps         : TStringList;
    FHasSource    : Boolean;
    FHasSourceless: Boolean;
    FByUnitName   : Boolean;
  public
    constructor Create(pKind: TGroupKind; pRow: Integer);
    destructor Destroy; override;
    property Kind: TGroupKind read FKind;
    property Ref: string read FRef write FRef;
    property Row: Integer read FRow;
    property Dir: string read FDir write FDir;
    property Units: TStringList read FUnits;
    property Paths: TStringList read FPaths;
    property Deps: TStringList read FDeps;
    property HasSource: Boolean read FHasSource write FHasSource;
    property HasSourceless: Boolean read FHasSourceless write FHasSourceless;
    property ByUnitName: Boolean read FByUnitName write FByUnitName;
  end;

  { Groups the units of one model and renders the document. }
  TSbomBuilder = class
  private
    FModel    : TSbomModel;
    FCatalogue: TSbomCatalogue;
    FGroups   : TObjectList<TSbomGroup>;
    FByKey    : TDictionary<string, TSbomGroup>;
    FUnitGroup: TArray<TSbomGroup>;
    FUsedRefs : TDictionary<string, Boolean>;
    function GroupFor(const pKey: string; pKind: TGroupKind; pRow: Integer): TSbomGroup;
    function Classify(const pUnit: TSbomUnit): TSbomGroup;
    function UniqueRef(const pRef: string): string;
    procedure AssignRefs;
    procedure LinkDependencies;
    function GroupVersion(const pGroup: TSbomGroup): string;
    function ComponentJson(const pGroup: TSbomGroup): TJSONObject;
    function AppJson(const pGroup: TSbomGroup): TJSONObject;
    function MetadataJson(const pApp: TSbomGroup): TJSONObject;
  public
    constructor Create(const pModel: TSbomModel; const pCatalogue: TSbomCatalogue);
    destructor Destroy; override;
    function Build(out pUnknown: TArray<string>): TJSONObject;
  end;

{ ---- model ---- }

constructor TSbomModel.Create;
begin
  inherited Create;
  FUnits:= TList<TSbomUnit>.Create;
  FEdges:= TList<TSbomEdge>.Create;
end;

destructor TSbomModel.Destroy;
begin
  FEdges.Free;
  FUnits.Free;
  inherited;
end;

function TSbomModel.AddUnit(const pName, pPath: string; pOrigin: TSbomUnitOrigin; pFirstParty: Boolean): Integer;
var
  LUnit: TSbomUnit;
begin
  LUnit.Name:= pName;
  LUnit.Path:= pPath;
  LUnit.Origin:= pOrigin;
  LUnit.FirstParty:= pFirstParty;
  Result:= FUnits.Add(LUnit);
end;

procedure TSbomModel.AddEdge(pFromUnit, pToUnit: Integer);
var
  LEdge: TSbomEdge;
begin
  LEdge.FromUnit:= pFromUnit;
  LEdge.ToUnit:= pToUnit;
  FEdges.Add(LEdge);
end;

{ ---- catalogue ---- }

function StringMember(const pObj: TJSONObject; const pName: string): string;
var
  LValue: TJSONValue;
begin
  LValue:= pObj.GetValue(pName);
  Result:= if LValue is TJSONString then TJSONString(LValue).Value else '';
end;

{ The strings of an array member; False when the member exists and is not an array of strings. }
function StringArrayMember(const pObj: TJSONObject; const pName: string; out pItems: TArray<string>): Boolean;
var
  LValue, LItem: TJSONValue;
begin
  pItems:= nil;
  LValue:= pObj.GetValue(pName);
  if LValue = nil then
    Exit(True);
  if LValue is not TJSONArray then
    Exit(False);
  for LItem in TJSONArray(LValue) do
  begin
    if (LItem is not TJSONString) or (TJSONString(LItem).Value = '') then
      Exit(False);
    pItems:= pItems + [TJSONString(LItem).Value];
  end;
  Result:= True;
end;

function IsRowMember(const pName: string): Boolean;
var
  LKnown: string;
begin
  for LKnown in CRowMembers do
    if LKnown = pName then
      Exit(True);
  Result:= False;
end;

{ One catalogue row from its JSON object; False with pError set when the row is not usable. }
function ReadRow(const pObj: TJSONObject; out pRow: TSbomLibrary; out pError: string): Boolean;
var
  LPair: TJSONPair;
  LFirst: TJSONValue;
begin
  pRow:= Default(TSbomLibrary);
  pError:= '';
  for LPair in pObj do
    if not IsRowMember(LPair.JsonString.Value) then
    begin
      pError:= Format('row "%s" has an unknown member "%s"', [StringMember(pObj, 'key'), LPair.JsonString.Value]);
      Exit(False);
    end;
  pRow.Key:= StringMember(pObj, 'key');
  pRow.Name:= StringMember(pObj, CJName);
  if (pRow.Key = '') or (pRow.Name = '') then
  begin
    pError:= 'a row needs a "key" and a "name"';
    Exit(False);
  end;
  pRow.Supplier:= StringMember(pObj, 'supplier');
  pRow.Version:= StringMember(pObj, CJVersion);
  pRow.VersionFromPath:= StringMember(pObj, 'versionFromPath');
  pRow.LicenseId:= StringMember(pObj, 'licenseId');
  pRow.LicenseName:= StringMember(pObj, 'licenseName');
  pRow.LicenseExpression:= StringMember(pObj, 'licenseExpression');
  pRow.Purl:= StringMember(pObj, 'purl');
  pRow.Cpe:= StringMember(pObj, 'cpe');
  LFirst:= pObj.GetValue('firstParty');
  pRow.FirstParty:= LFirst is TJSONTrue;
  if not (StringArrayMember(pObj, 'paths', pRow.Paths) and StringArrayMember(pObj, 'units', pRow.Units)) then
  begin
    pError:= Format('row "%s": "paths" and "units" must be arrays of non-empty strings', [pRow.Key]);
    Exit(False);
  end;
  if (Length(pRow.Paths) = 0) and (Length(pRow.Units) = 0) then
  begin
    pError:= Format('row "%s" has neither "paths" nor "units": it can never match', [pRow.Key]);
    Exit(False);
  end;
  Result:= True;
end;

function TSbomCatalogue.LoadFromFile(const pPath: string; out pError: string): Boolean;
var
  LRoot, LLibs, LItem: TJSONValue;
  LRow: TSbomLibrary;
  LSeen: TDictionary<string, Boolean>;
begin
  FRows:= nil;
  pError:= '';
  if not FileExists(pPath) then
  begin
    pError:= 'library catalogue not found: ' + pPath;
    Exit(False);
  end;
  LRoot:= nil;
  try
    LRoot:= TJSONObject.ParseJSONValue(TFile.ReadAllText(pPath, TEncoding.UTF8));
  except
    on E: Exception do
      pError:= E.Message;
  end;
  if LRoot = nil then
  begin
    pError:= 'library catalogue is not valid JSON: ' + pPath + (if pError <> '' then ' (' + pError + ')' else '');
    Exit(False);
  end;
  LSeen:= TDictionary<string, Boolean>.Create;
  try
    LLibs:= if LRoot is TJSONObject then TJSONObject(LRoot).GetValue('libraries') else nil;
    if LLibs is not TJSONArray then
    begin
      pError:= 'library catalogue has no "libraries" array: ' + pPath;
      Exit(False);
    end;
    for LItem in TJSONArray(LLibs) do
    begin
      LRow:= Default(TSbomLibrary);
      if LItem is not TJSONObject then
        pError:= 'a "libraries" item is not an object'
      else if ReadRow(TJSONObject(LItem), LRow, pError) and LSeen.ContainsKey(LowerCase(LRow.Key)) then
        pError:= Format('duplicate row key "%s"', [LRow.Key]);
      if pError <> '' then
      begin
        pError:= 'library catalogue ' + pPath + ': ' + pError;
        FRows:= nil;
        Exit(False);
      end;
      LSeen.Add(LowerCase(LRow.Key), True);
      FRows:= FRows + [LRow];
    end;
    Result:= True;
  finally
    LSeen.Free;
    LRoot.Free;
  end;
end;

function TSbomCatalogue.MatchPath(const pPath: string): Integer;
var
  I: Integer;
  LMask: string;
begin
  for I:= 0 to High(FRows) do
    for LMask in FRows[I].Paths do
      if MatchesMask(pPath, '*' + LMask + '*') then
        Exit(I);
  Result:= CNoRow;
end;

function TSbomCatalogue.MatchUnit(const pUnit: string): Integer;
var
  I: Integer;
  LPattern: string;
begin
  for I:= 0 to High(FRows) do
    for LPattern in FRows[I].Units do
      if LPattern.EndsWith('*') then
      begin
        if pUnit.StartsWith(LPattern.Substring(0, LPattern.Length - 1), True) then
          Exit(I);
      end
      else if SameText(LPattern, pUnit) then
        Exit(I);
  Result:= CNoRow;
end;

{ ---- groups ---- }

constructor TSbomGroup.Create(pKind: TGroupKind; pRow: Integer);
begin
  inherited Create;
  FKind:= pKind;
  FRow:= pRow;
  FUnits:= TStringList.Create;
  FUnits.CaseSensitive:= False;
  FPaths:= TStringList.Create;
  FDeps:= TStringList.Create;
end;

destructor TSbomGroup.Destroy;
begin
  FDeps.Free;
  FPaths.Free;
  FUnits.Free;
  inherited;
end;

constructor TSbomBuilder.Create(const pModel: TSbomModel; const pCatalogue: TSbomCatalogue);
begin
  inherited Create;
  FModel:= pModel;
  FCatalogue:= pCatalogue;
  FGroups:= TObjectList<TSbomGroup>.Create(True);
  FByKey:= TDictionary<string, TSbomGroup>.Create;
  FUsedRefs:= TDictionary<string, Boolean>.Create;
end;

destructor TSbomBuilder.Destroy;
begin
  FUsedRefs.Free;
  FByKey.Free;
  FGroups.Free;
  inherited;
end;

function TSbomBuilder.GroupFor(const pKey: string; pKind: TGroupKind; pRow: Integer): TSbomGroup;
begin
  if not FByKey.TryGetValue(pKey, Result) then
  begin
    Result:= TSbomGroup.Create(pKind, pRow);
    FGroups.Add(Result);
    FByKey.Add(pKey, Result);
  end;
end;

function TSbomBuilder.Classify(const pUnit: TSbomUnit): TSbomGroup;
var
  LRow: Integer;
  LByName: Boolean;
begin
  LByName:= pUnit.Path = '';
  LRow:= if LByName then FCatalogue.MatchUnit(pUnit.Name) else FCatalogue.MatchPath(pUnit.Path);
  if (LRow <> CNoRow) and not FCatalogue.Rows[LRow].FirstParty then
  begin
    Result:= GroupFor('row:' + IntToStr(LRow), gkCatalogue, LRow);
    Result.ByUnitName:= Result.ByUnitName or LByName;
  end
  else if (LRow <> CNoRow) or pUnit.FirstParty then
    Result:= GroupFor(CKeyApp, gkApp, CNoRow)
  else if LByName then
    Result:= GroupFor('unit:' + LowerCase(pUnit.Name), gkUnknownUnit, CNoRow)
  else
  begin
    Result:= GroupFor('dir:' + LowerCase(ExtractFileDir(pUnit.Path)), gkUnknownDir, CNoRow);
    Result.Dir:= ExtractFileDir(pUnit.Path);
  end;
  Result.Units.Add(pUnit.Name);
  if LByName then
    Result.HasSourceless:= True
  else
  begin
    Result.HasSource:= True;
    Result.Paths.Add(pUnit.Path);
  end;
end;

function TSbomBuilder.UniqueRef(const pRef: string): string;
var
  LNext: Integer;
begin
  Result:= pRef;
  LNext:= 1;
  while FUsedRefs.ContainsKey(LowerCase(Result)) do
  begin
    Inc(LNext);
    Result:= pRef + '#' + IntToStr(LNext);
  end;
  FUsedRefs.Add(LowerCase(Result), True);
end;

{ The last two segments of a directory, '/'-joined: "AcmeWidgets/Source". }
function DirLabel(const pDir: string): string;
var
  LLeaf, LParent: string;
begin
  LLeaf:= ExtractFileName(pDir);
  LParent:= ExtractFileName(ExtractFileDir(pDir));
  Result:= if LParent <> '' then LParent + '/' + LLeaf else LLeaf;
end;

procedure TSbomBuilder.AssignRefs;
var
  LGroup: TSbomGroup;
begin
  { Sorted first, so a '#2' suffix lands on the same directory in every run. }
  FGroups.Sort(TComparer<TSbomGroup>.Construct(
    function(const pLeft, pRight: TSbomGroup): Integer
    begin
      Result:= Ord(pLeft.Kind) - Ord(pRight.Kind);
      if Result = 0 then
        Result:= pLeft.Row - pRight.Row;
      if Result = 0 then
        Result:= CompareText(pLeft.Dir, pRight.Dir);
      if (Result = 0) and (pLeft.Units.Count > 0) and (pRight.Units.Count > 0) then
        Result:= CompareText(pLeft.Units[0], pRight.Units[0]);
    end));
  for LGroup in FGroups do
  begin
    LGroup.Units.Sort;
    case LGroup.Kind of
      gkApp        : LGroup.Ref:= UniqueRef(CRefApp + FModel.AppName);
      gkCatalogue  : LGroup.Ref:= UniqueRef(CRefLib + FCatalogue.Rows[LGroup.Row].Key);
      gkUnknownDir : LGroup.Ref:= UniqueRef(CRefUnknownDir + DirLabel(LGroup.Dir));
      gkUnknownUnit: LGroup.Ref:= UniqueRef(CRefUnknownUnit + LGroup.Units[0]);
    end;
  end;
end;

procedure TSbomBuilder.LinkDependencies;
var
  LEdge: TSbomEdge;
  LFrom, LTo: TSbomGroup;
  LGroup: TSbomGroup;
begin
  for LGroup in FGroups do
  begin
    LGroup.Deps.Sorted:= True;
    LGroup.Deps.Duplicates:= dupIgnore;
  end;
  for LEdge in FModel.Edges do
  begin
    LFrom:= FUnitGroup[LEdge.FromUnit];
    LTo:= FUnitGroup[LEdge.ToUnit];
    if LFrom <> LTo then
      LFrom.Deps.Add(LTo.Ref);
  end;
end;

function TSbomBuilder.GroupVersion(const pGroup: TSbomGroup): string;
var
  LRow: TSbomLibrary;
  LPath, LFound: string;
  LMatch: TMatch;
begin
  Result:= '';
  if pGroup.Kind <> gkCatalogue then
    Exit;
  LRow:= FCatalogue.Rows[pGroup.Row];
  if LRow.Version <> '' then
    Exit(LRow.Version);
  if LRow.VersionFromPath = '' then
    Exit;
  { One version only when every path that states one states the same; two installs = no claim. }
  for LPath in pGroup.Paths do
  begin
    LMatch:= TRegEx.Match(LPath, LRow.VersionFromPath, [roIgnoreCase]);
    if LMatch.Success and (LMatch.Groups.Count > 1) then
    begin
      LFound:= LMatch.Groups[1].Value;
      if (Result <> '') and (Result <> LFound) then
        Exit('');
      Result:= LFound;
    end;
  end;
end;

function Prop(const pName, pValue: string): TJSONObject;
begin
  Result:= TJSONObject.Create.AddPair(CJName, CPropPrefix + pName).AddPair(CJValue, pValue);
end;

procedure AddUnitProps(const pProps: TJSONArray; const pGroup: TSbomGroup);
var
  LUnit: string;
begin
  pProps.Add(Prop('unitCount', IntToStr(pGroup.Units.Count)));
  for LUnit in pGroup.Units do
    pProps.Add(Prop('unit', LUnit));
end;

function EvidenceOf(const pGroup: TSbomGroup): string;
begin
  Result:= if pGroup.HasSource and pGroup.HasSourceless then CEvidenceMixed
    else if pGroup.HasSourceless then CEvidenceSourceless
    else CEvidenceSource;
end;

function LicensesJson(const pRow: TSbomLibrary): TJSONArray;
begin
  Result:= TJSONArray.Create;
  if pRow.LicenseExpression <> '' then
    Result.Add(TJSONObject.Create.AddPair('expression', pRow.LicenseExpression))
  else if pRow.LicenseId <> '' then
    Result.Add(TJSONObject.Create.AddPair(CJLicense, TJSONObject.Create.AddPair('id', pRow.LicenseId)))
  else
    Result.Add(TJSONObject.Create.AddPair(CJLicense, TJSONObject.Create.AddPair(CJName, pRow.LicenseName)));
end;

function TSbomBuilder.ComponentJson(const pGroup: TSbomGroup): TJSONObject;
var
  LRow: TSbomLibrary;
  LProps: TJSONArray;
  LVersion, LSupplier, LName, LAttribution: string;
begin
  LRow:= Default(TSbomLibrary);
  LAttribution:= CAttributionNone;
  case pGroup.Kind of
    gkCatalogue:
      begin
        LRow:= FCatalogue.Rows[pGroup.Row];
        LName:= LRow.Name;
        LAttribution:= if pGroup.ByUnitName and pGroup.HasSource then CAttributionPath + '+' + CAttributionUnitName
          else if pGroup.ByUnitName then CAttributionUnitName
          else CAttributionPath;
      end;
    gkUnknownDir: LName:= DirLabel(pGroup.Dir);
  else
    LName:= pGroup.Units[0];
  end;
  LSupplier:= if LRow.Supplier <> '' then LRow.Supplier else SBOM_UNKNOWN_SUPPLIER;
  Result:= TJSONObject.Create;
  Result.AddPair(CJType, CTypeLibrary).AddPair(CJBomRef, pGroup.Ref);
  Result.AddPair('supplier', TJSONObject.Create.AddPair(CJName, LSupplier));
  Result.AddPair(CJName, LName);
  LVersion:= GroupVersion(pGroup);
  if LVersion <> '' then
    Result.AddPair(CJVersion, LVersion);
  if (LRow.LicenseExpression <> '') or (LRow.LicenseId <> '') or (LRow.LicenseName <> '') then
    Result.AddPair('licenses', LicensesJson(LRow));
  if LRow.Cpe <> '' then
    Result.AddPair('cpe', LRow.Cpe);
  if LRow.Purl <> '' then
    Result.AddPair('purl', LRow.Purl);
  LProps:= TJSONArray.Create;
  Result.AddPair(CJProperties, LProps);
  LProps.Add(Prop('attribution', LAttribution));
  LProps.Add(Prop('evidence', EvidenceOf(pGroup)));
  AddUnitProps(LProps, pGroup);
end;

function TSbomBuilder.AppJson(const pGroup: TSbomGroup): TJSONObject;
var
  LProps: TJSONArray;
begin
  Result:= TJSONObject.Create;
  Result.AddPair(CJType, CTypeApplication).AddPair(CJBomRef, pGroup.Ref).AddPair(CJName, FModel.AppName);
  if FModel.AppVersion <> '' then
    Result.AddPair(CJVersion, FModel.AppVersion);
  if FModel.ExeSha512 <> '' then
    Result.AddPair('hashes', TJSONArray.Create.Add(
      TJSONObject.Create.AddPair('alg', 'SHA-512').AddPair('content', FModel.ExeSha512)));
  LProps:= TJSONArray.Create;
  Result.AddPair(CJProperties, LProps);
  LProps.Add(Prop('attribution', CAttributionFirstParty));
  if FModel.ExeName <> '' then
    LProps.Add(Prop('hashedFile', FModel.ExeName));
  AddUnitProps(LProps, pGroup);
end;

function TSbomBuilder.MetadataJson(const pApp: TSbomGroup): TJSONObject;
var
  LTool: TJSONObject;
begin
  LTool:= TJSONObject.Create.AddPair(CJType, CTypeApplication).AddPair(CJName, 'drag-lint')
    .AddPair(CJVersion, FModel.ToolVersion);
  Result:= TJSONObject.Create;
  Result.AddPair('timestamp', FModel.Timestamp);
  Result.AddPair('lifecycles', TJSONArray.Create.Add(TJSONObject.Create.AddPair('phase', 'pre-build')));
  Result.AddPair('tools', TJSONObject.Create.AddPair('components', TJSONArray.Create.Add(LTool)));
  Result.AddPair('component', AppJson(pApp));
  Result.AddPair(CJProperties, TJSONArray.Create
    .Add(Prop('sbom:slice', 'v1'))
    .Add(Prop('sbom:scope', CScopeText))
    .Add(Prop('sbom:libraryIndex', if FModel.LibraryIndexUsed then CLibIndexYes else CLibIndexNo)));
end;

function TSbomBuilder.Build(out pUnknown: TArray<string>): TJSONObject;
var
  I: Integer;
  LGroup, LApp: TSbomGroup;
  LComponents, LDependencies, LDependsOn: TJSONArray;
  LDep: string;
begin
  pUnknown:= nil;
  { The application exists even when no unit is first-party. }
  LApp:= GroupFor(CKeyApp, gkApp, CNoRow);
  SetLength(FUnitGroup, FModel.Units.Count);
  for I:= 0 to FModel.Units.Count - 1 do
    FUnitGroup[I]:= Classify(FModel.Units[I]);
  AssignRefs;
  LinkDependencies;
  LComponents:= TJSONArray.Create;
  LDependencies:= TJSONArray.Create;
  Result:= TJSONObject.Create;
  Result.AddPair('bomFormat', 'CycloneDX').AddPair('specVersion', SBOM_SPEC_VERSION);
  Result.AddPair('serialNumber', FModel.SerialNumber).AddPair(CJVersion, TJSONNumber.Create(1));
  Result.AddPair('metadata', MetadataJson(LApp));
  Result.AddPair('components', LComponents);
  Result.AddPair('dependencies', LDependencies);
  Result.AddPair('compositions', TJSONArray.Create.Add(TJSONObject.Create
    .AddPair('aggregate', 'incomplete')
    .AddPair('assemblies', TJSONArray.Create.Add(LApp.Ref))));
  for LGroup in FGroups do
  begin
    if LGroup.Kind <> gkApp then
      LComponents.Add(ComponentJson(LGroup));
    if LGroup.Kind = gkUnknownDir then
      pUnknown:= pUnknown + [LGroup.Ref + #9 + LGroup.Dir]
    else if LGroup.Kind = gkUnknownUnit then
      pUnknown:= pUnknown + [LGroup.Ref + #9 + LGroup.Units[0]];
    LDependsOn:= TJSONArray.Create;
    for LDep in LGroup.Deps do
      LDependsOn.Add(LDep);
    LDependencies.Add(TJSONObject.Create.AddPair('ref', LGroup.Ref).AddPair('dependsOn', LDependsOn));
  end;
end;

function BuildCycloneDx(const pModel: TSbomModel; const pCatalogue: TSbomCatalogue;
  out pUnknown: TArray<string>): TJSONObject;
var
  LBuilder: TSbomBuilder;
begin
  LBuilder:= TSbomBuilder.Create(pModel, pCatalogue);
  try
    Result:= LBuilder.Build(pUnknown);
  finally
    LBuilder.Free;
  end;
end;

end.
