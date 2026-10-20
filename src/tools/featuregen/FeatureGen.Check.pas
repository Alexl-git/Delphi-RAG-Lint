unit FeatureGen.Check;

{ The registry guard's checks A-E (port of Invoke-RegistryCheck and its helpers,
  tools\FeatureRegistry.psm1 M:300-1382):
    A  well-formed: groups/teams, canonical bytes, ASCII/CRLF files, family
       definitions, every entry field (Test-FeatureEntry), the seed backlog;
    B  live -> registry: every --help verb, subcommand, IDE caption, context-menu
       item, release exe and MCP tool is registered (or exempt with a reason);
    C  registry -> live: every registered surface still exists;
    D  generated outputs are current (a check-mode render of the wiki outputs);
    E  staleness: a note, never a failure.
  Finding texts and their hints (nearest candidates, entry skeleton) are the
  PowerShell texts, so a finding set can be compared with the PowerShell guard's.
  Two deliberate supersets of the PowerShell guard: B also asks for every live
  MCP tool (spec criterion 5), and the entry / groups schema is validated at
  every depth (Test-Json in the PowerShell guard reports nested violations as
  "not valid" with no error record, so they never became a finding).
  PowerShell's case-insensitive -eq / -contains / -like / hashtable lookups are
  mirrored with SameText; -ceq / HashSet[Ordinal] with ordinal compares. }

interface

uses
  System.SysUtils
  , System.JSON
  , System.Generics.Collections
  , FeatureGen.Model
  , FeatureGen.Live
  ;

const
  /// <summary>Marks a schema finding below the top level of the entry / groups document (a pointer
  /// with two or more segments). The PowerShell guard's Test-Json reports such violations as "not
  /// valid" with no error record, so they never became a PowerShell finding; parity tests exclude
  /// them by this marker and assert their count.</summary>
  NESTED_SCHEMA_MARK = 'nested schema (the PowerShell guard drops these): ';

type
  /// <summary>How much the check runs.</summary>
  /// <remarks>clWellFormed: check A only, no engine and no live harvest (what "add" validates with).
  /// clFull: A plus the family children, B, C, the seed backlog, D and the E note.</remarks>
  TCheckLevel = (clWellFormed, clFull);

  /// <summary>One check failure.</summary>
  TFinding = record
    /// <summary>The check letter, 'A'..'D'.</summary>
    Check: Char;
    /// <summary>The PowerShell guard's failure text after the "X: " prefix; may span lines (LF, skeleton lines CRLF).</summary>
    Text: string;
  end;

  /// <summary>One entry file as read from features\entries.</summary>
  TRawEntry = class
  public
    /// <summary>Full path of the file.</summary>
    Path: string;
    /// <summary>File name without extension.</summary>
    Stem: string;
    /// <summary>The file bytes as ASCII text.</summary>
    Raw: string;
    /// <summary>The parsed object; owned.</summary>
    Entry: TJSONObject;
    destructor Destroy; override;
  end;

  /// <summary>What the entry checks validate against (Get-RegistryContext).</summary>
  /// <remarks>Owns its entries and the parsed schema. Not thread-safe.</remarks>
  TCheckContext = class
  public
    /// <summary>Repository root.</summary>
    Repo: string;
    /// <summary>Canonical top-level key order (entry.schema.json properties).</summary>
    KeyOrder: TArray<string>;
    /// <summary>Parsed entry.schema.json; owned.</summary>
    EntrySchema: TJSONObject;
    /// <summary>Group ids in groups.json order-field order.</summary>
    GroupIds: TArray<string>;
    /// <summary>The order value of each GroupIds element.</summary>
    GroupOrders: TArray<Integer>;
    /// <summary>Team ids in teams.json order.</summary>
    TeamIds: TArray<string>;
    /// <summary>Versions that are a '## v..' heading in CHANGELOG.md.</summary>
    ChangelogVersions: TArray<string>;
    /// <summary>docs\wiki\*.md stems.</summary>
    WikiPages: TArray<string>;
    /// <summary>features\entries\*.json, sorted by file name.</summary>
    Entries: TObjectList<TRawEntry>;
    /// <summary>Every id a 'related' / 'supersededBy' may name: entry stems plus the extra ids given.</summary>
    KnownIds: TList<string>;
    /// <summary>Every id listed in seed-backlog.json, all teams.</summary>
    SeedBacklog: TArray<string>;
    /// <summary>exemptions.json verbs keys.</summary>
    ExemptVerbs: TArray<string>;
    /// <summary>exemptions.json captions keys.</summary>
    ExemptCaptions: TArray<string>;
    /// <summary>exemptions.json exes keys.</summary>
    ExemptExes: TArray<string>;
    /// <summary>Loads the context of pRepo.</summary>
    /// <param name="pRepo">Repository root holding features\, docs\wiki and CHANGELOG.md.</param>
    /// <param name="pExtraIds">Ids to add to KnownIds (family children, in-memory entries).</param>
    /// <exception cref="Exception">A registry file is missing, non-ASCII or not JSON (message names it).</exception>
    constructor Create(const pRepo: string; const pExtraIds: TArray<string>);
    destructor Destroy; override;
  end;

/// <summary>Validates one entry (Test-FeatureEntry).</summary>
/// <param name="pEntry">The entry object; not modified.</param>
/// <param name="pCtx">Context to validate against.</param>
/// <param name="pStem">File stem the id must equal (hand entries).</param>
/// <param name="pChild">An importer-generated family child: child-only keys allowed, the rule./chart. prefix
/// stripped before the schema, no stem / intro / lastVerified requirement.</param>
/// <param name="pSinceOverride">The child's since came from a per-child override: exempt from the CHANGELOG check.</param>
/// <returns>One "&lt;stem&gt;.json: ..." (or "child &lt;id&gt;: ...") text per problem; empty when valid.</returns>
function CheckEntry(const pEntry: TJSONObject; const pCtx: TCheckContext; const pStem: string; pChild: Boolean = False;
  pSinceOverride: Boolean = False): TArray<string>;

/// <summary>Runs checks A-E on the registry under pReg.Root.</summary>
/// <param name="pReg">A registry whose Load was called (only its Root is used: the checks read the raw files).</param>
/// <param name="pLive">The live surface; ignored at clWellFormed (nil allowed). At clFull a nil surface or one
/// with HarvestError set yields one B finding and stops, as the PowerShell guard does.</param>
/// <param name="pLevel">clWellFormed or clFull.</param>
/// <returns>Every failure, in check order; empty when the registry passes.</returns>
function RunChecks(const pReg: TRegistry; const pLive: TLiveSurface; pLevel: TCheckLevel): TArray<TFinding>; overload;

/// <summary>Runs checks A-E with in-memory extra entries and the notes returned.</summary>
/// <param name="pReg">As above.</param>
/// <param name="pLive">As above.</param>
/// <param name="pLevel">As above.</param>
/// <param name="pExtraEntries">Entries added to the run as if registered (positive controls, a new entry); read only.
/// At clWellFormed each is validated with its own id as stem; at clFull they join the hand entries.</param>
/// <param name="pSkipGenerated">True: skip check D (the render).</param>
/// <param name="pNotes">Receives the notes: exemptions, planned / removed entries, backlog per team, staleness.</param>
/// <returns>Every failure, in check order.</returns>
function RunChecks(const pReg: TRegistry; const pLive: TLiveSurface; pLevel: TCheckLevel; const pExtraEntries: TArray<TJSONObject>;
  pSkipGenerated: Boolean; out pNotes: TArray<string>): TArray<TFinding>; overload;

/// <summary>The "check" command: loads the registry, harvests the live surface (clFull) and runs every check.</summary>
/// <param name="pRepo">Repository root.</param>
/// <param name="pEngine">Full path of drag-lint.exe (clFull only).</param>
/// <param name="pLevel">clWellFormed or clFull.</param>
/// <param name="pNotes">Receives the notes.</param>
/// <returns>Every failure; a harvest failure is one B finding.</returns>
function RunCheckCommand(const pRepo, pEngine: string; pLevel: TCheckLevel; out pNotes: TArray<string>): TArray<TFinding>;

/// <summary>A finding as the PowerShell guard prints it.</summary>
/// <param name="pFinding">The finding.</param>
/// <returns>"X: text".</returns>
function FindingText(const pFinding: TFinding): string;

/// <summary>The pTop candidates closest to pValue (Get-NearestCandidates).</summary>
/// <param name="pValue">The value looked for.</param>
/// <param name="pCandidates">Candidates in any order.</param>
/// <param name="pTop">How many to return.</param>
/// <returns>Ordered by case-insensitive Levenshtein distance, then case-insensitively by text.</returns>
function NearestCandidates(const pValue: string; const pCandidates: TArray<string>; pTop: Integer = 3): TArray<string>;

implementation

uses
  System.Classes
  , System.IOUtils
  , System.Math
  , System.RegularExpressions
  , System.Generics.Defaults
  , FeatureGen.Json
  , FeatureGen.Output
  , FeatureGen.Wiki
  ;

const
  MIN_CAPTION_PREFIX = 12;
  STALE_DAYS = 90;
  NEAREST_POOL = 12;
  NEAREST_SHOWN = 3;
  ASCII_MAX = 127;
  BYTE_CR = 13;
  BYTE_LF = 10;
  UTF8_BOM: array[0..2] of Byte = ($EF, $BB, $BF);
  CHILD_ONLY_KEYS: array[0..3] of string = ('parent', 'subgroup', 'emitter', 'wikiAnchor');
  LAST_VERIFIED_KEYS: array[0..2] of string = ('date', 'by', 'build');
  CONTEXT_HOSTS: array[0..2] of string = ('Structure form', 'Project Manager', 'Editor');
  FAMILY_IMPORTERS: array[0..1] of string = ('lint-rules', 'chart-questions');
  SCHEMA_PREFIX = 'The JSON is not valid with the schema: ';

type
  TSurfaceRule = record
    Kind: string;
    Keys: TArray<string>;
    Required: TArray<string>;
  end;

function SurfaceRules: TArray<TSurfaceRule>;

  function R(const pKind: string; const pKeys, pReq: TArray<string>): TSurfaceRule;
  begin
    Result.Kind := pKind;
    Result.Keys := pKeys;
    Result.Required := pReq;
  end;

begin
  Result := [
    R('cli', ['type', 'verb', 'sub', 'example', 'usage', 'flags'], ['verb']),
    R('ide-menu', ['type', 'path', 'steps'], ['path']),
    R('ide-context', ['type', 'host', 'caption', 'steps'], ['host', 'caption']),
    R('ide-about', ['type', 'caption', 'steps'], ['caption']),
    R('tool-window', ['type', 'path', 'steps'], ['path']),
    R('shortcut', ['type', 'keys'], ['keys']),
    R('lsp', ['type', 'method'], ['method']),
    R('mcp', ['type', 'tool'], ['tool']),
    R('script', ['type', 'path', 'args'], ['path']),
    R('exe', ['type', 'name', 'menu'], ['name']),
    R('workflow', ['type', 'doc'], ['doc'])];
end;

{ ---- small helpers ---- }

function InCI(const pValue: string; const pList: array of string): Boolean;
var
  lS: string;
begin
  Result := False;
  for lS in pList do
    if SameText(pValue, lS) then
      Exit(True);
end;

function InOrd(const pValue: string; const pList: array of string): Boolean;
var
  lS: string;
begin
  Result := False;
  for lS in pList do
    if pValue = lS then
      Exit(True);
end;

function JoinS(const pItems: TArray<string>; const pSep: string): string;
begin
  Result := string.Join(pSep, pItems);
end;

function IsBlank(const pS: string): Boolean;
begin
  Result := Trim(pS) = '';
end;

{ A member by case-insensitive name (PowerShell hashtables are case-insensitive). }
function JVal(const pObj: TJSONValue; const pKey: string): TJSONValue;
var
  lP: TJSONPair;
begin
  Result := nil;
  if pObj is not TJSONObject then
    Exit;
  Result := TJSONObject(pObj).GetValue(pKey);
  if Result <> nil then
    Exit;
  for lP in TJSONObject(pObj) do
    if SameText(lP.JsonString.Value, pKey) then
      Exit(lP.JsonValue);
end;

function JHas(const pObj: TJSONValue; const pKey: string): Boolean;
begin
  Result := JVal(pObj, pKey) <> nil;
end;

{ [string]$obj[key]: '' for absent or null. }
function JS(const pObj: TJSONValue; const pKey: string): string;
var
  lV: TJSONValue;
begin
  lV := JVal(pObj, pKey);
  if (lV = nil) or (lV is TJSONNull) then
    Result := ''
  else if lV is TJSONBool then
    Result := (if TJSONBool(lV).AsBoolean then 'True' else 'False')
  else if (lV is TJSONObject) or (lV is TJSONArray) then
    Result := lV.ToString
  else
    Result := lV.Value;
end;

{ Get-EntryList: array items; a scalar is one item; absent / null is empty. }
function JItems(const pObj: TJSONValue; const pKey: string): TArray<TJSONValue>;
var
  lV: TJSONValue;
  i: Integer;
begin
  Result := nil;
  lV := JVal(pObj, pKey);
  if (lV = nil) or (lV is TJSONNull) then
    Exit;
  if lV is TJSONArray then
  begin
    SetLength(Result, TJSONArray(lV).Count);
    for i := 0 to TJSONArray(lV).Count - 1 do
      Result[i] := TJSONArray(lV).Items[i];
  end
  else
    Result := [lV];
end;

function ItemText(const pV: TJSONValue): string;
begin
  if (pV = nil) or (pV is TJSONNull) then
    Result := ''
  else if (pV is TJSONObject) or (pV is TJSONArray) then
    Result := pV.ToString
  else
    Result := pV.Value;
end;

function Indent3(const pText: string): string;
var
  lParts: TArray<string>;
  i: Integer;
begin
  lParts := pText.TrimRight.Split([#10]);
  for i := 0 to High(lParts) do
    lParts[i] := '   ' + lParts[i];
  Result := JoinS(lParts, #10);
end;

function Levenshtein(const pA, pB: string): Integer;
var
  lA, lB: string;
  lD: array of array of Integer;
  i, j, lCost: Integer;
begin
  lA := LowerCase(pA);
  lB := LowerCase(pB);
  SetLength(lD, Length(lA) + 1, Length(lB) + 1);
  for i := 0 to High(lD) do
    lD[i, 0] := i;
  for j := 0 to High(lD[0]) do
    lD[0, j] := j;
  for i := 1 to Length(lA) do
    for j := 1 to Length(lB) do
    begin
      lCost := (if lA[i] = lB[j] then 0 else 1);
      lD[i, j] := Min(Min(lD[i - 1, j] + 1, lD[i, j - 1] + 1), lD[i - 1, j - 1] + lCost);
    end;
  Result := lD[Length(lA), Length(lB)];
end;

function NearestCandidates(const pValue: string; const pCandidates: TArray<string>; pTop: Integer): TArray<string>;
var
  lIdx, lDist: TArray<Integer>;
  i, lN: Integer;
  lC: TArray<string>;
begin
  lC := pCandidates;
  SetLength(lIdx, Length(lC));
  SetLength(lDist, Length(lC));
  for i := 0 to High(lC) do
  begin
    lIdx[i] := i;
    lDist[i] := Levenshtein(pValue, lC[i]);
  end;
  TArray.Sort<Integer>(lIdx, TComparer<Integer>.Construct(
    function(const pA, pB: Integer): Integer
    begin
      Result := lDist[pA] - lDist[pB];
      if Result = 0 then
        Result := AnsiCompareText(lC[pA], lC[pB]);
      if Result = 0 then
        Result := pA - pB;
    end));
  lN := Length(lIdx);
  if lN > pTop then
    lN := pTop;
  SetLength(Result, lN);
  for i := 0 to lN - 1 do
    Result[i] := lC[lIdx[i]];
end;

function RepoRelativeExists(const pRepo, pRel: string): Boolean;
var
  lP: string;
begin
  if IsBlank(pRel) or TPath.IsPathRooted(pRel) then
    Exit(False);
  lP := TPath.Combine(pRepo, pRel);
  Result := TFile.Exists(lP) or TDirectory.Exists(lP);
end;

{ Test-AsciiCrlfFile: '' when the file is 7-bit ASCII with CRLF line ends and a trailing newline. }
function AsciiCrlfProblem(const pPath: string): string;
var
  lB: TBytes;
  i, lLine: Integer;
begin
  lB := TFile.ReadAllBytes(pPath);
  if (Length(lB) >= Length(UTF8_BOM)) and CompareMem(@lB[0], @UTF8_BOM[0], Length(UTF8_BOM)) then
    Exit(pPath + ': BOM');
  lLine := 1;
  for i := 0 to High(lB) do
  begin
    if lB[i] > ASCII_MAX then
      Exit(Format('%s:%d: non-ASCII byte 0x%.2X', [pPath, lLine, lB[i]]));
    if (lB[i] = BYTE_CR) and ((i + 1 > High(lB)) or (lB[i + 1] <> BYTE_LF)) then
      Exit(Format('%s: lone CR at line %d', [pPath, lLine]));
    if lB[i] = BYTE_LF then
    begin
      if (i = 0) or (lB[i - 1] <> BYTE_CR) then
        Exit(Format('%s: LF line ending at line %d', [pPath, lLine]));
      Inc(lLine);
    end;
  end;
  if (Length(lB) > 0) and (lB[High(lB)] <> BYTE_LF) then
    Exit(pPath + ': no trailing newline');
  Result := '';
end;

function ReadJsonObject(const pPath: string): TJSONObject;
var
  lV: TJSONValue;
begin
  lV := ReadJsonFile(pPath);
  if lV is not TJSONObject then
  begin
    lV.Free;
    raise EFeatureJson.CreateFmt('%s: not a JSON object', [pPath]);
  end;
  Result := TJSONObject(lV);
end;

function SortedFiles(const pDir, pMask: string): TArray<string>;
begin
  if not TDirectory.Exists(pDir) then
    Exit(nil);
  Result := TDirectory.GetFiles(pDir, pMask);
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const pA, pB: string): Integer
    begin
      Result := AnsiCompareText(ExtractFileName(pA), ExtractFileName(pB));
    end));
end;

function TodayText: string;
begin
  Result := FormatDateTime('yyyy-mm-dd', Date);
end;

function TryIsoDate(const pText: string; out pDate: TDateTime): Boolean;
var
  lFs: TFormatSettings;
begin
  lFs := TFormatSettings.Invariant;
  lFs.DateSeparator := '-';
  lFs.ShortDateFormat := 'yyyy-mm-dd';
  Result := TRegEx.IsMatch(pText, '^\d{4}-\d{2}-\d{2}$') and TryStrToDate(pText, pDate, lFs);
end;

{ ---- the JSON schema subset the registry schemas use ---- }

function JsonTypeName(const pV: TJSONValue): string;
begin
  if pV is TJSONObject then
    Result := 'object'
  else if pV is TJSONArray then
    Result := 'array'
  else if pV is TJSONNumber then
    Result := (if TRegEx.IsMatch(TJSONNumber(pV).ToString, '^-?\d+$') then 'integer' else 'number')
  else if pV is TJSONString then
    Result := 'string'
  else if pV is TJSONBool then
    Result := 'boolean'
  else
    Result := 'null';
end;

{ One schema message; a pointer of two or more segments ('/surfaces/0/...') carries
  NESTED_SCHEMA_MARK, a shallower one the JsonSchema.Net wording the PowerShell guard prints. }
function SchemaMessage(const pMsg, pPtr: string): string;
const
  NESTED_DEPTH = 2;
var
  lDepth: Integer;
  lCh: Char;
begin
  lDepth := 0;
  for lCh in pPtr do
    if lCh = '/' then
      Inc(lDepth);
  Result := (if lDepth >= NESTED_DEPTH then NESTED_SCHEMA_MARK else '') + SCHEMA_PREFIX + pMsg + ' at ''' + pPtr + '''';
end;

procedure ValidateNode(const pV: TJSONValue; const pS: TJSONObject; const pRoot: TJSONObject; const pPtr: string;
  const pOut: TList<string>);
var
  lRef, lType, lActual, lName: string;
  lDef, lProps, lItems, lAdd: TJSONValue;
  lEnum, lReq: TJSONValue;
  lMissing: TArray<string>;
  lOk: Boolean;
  i: Integer;
  lP: TJSONPair;

  procedure Add(const pMsg: string);
  begin
    pOut.Add(SchemaMessage(pMsg, pPtr));
  end;

  function IntOf(const pKey: string; out pN: Integer): Boolean;
  var
    lX: TJSONValue;
  begin
    lX := pS.GetValue(pKey);
    Result := lX is TJSONNumber;
    if Result then
      pN := TJSONNumber(lX).AsInt;
  end;

var
  lN: Integer;
  lStr: string;
begin
  lRef := Prop(pS, '$ref');
  if lRef.StartsWith('#/definitions/') then
  begin
    lDef := TJSONObject(pRoot.GetValue('definitions')).GetValue(Copy(lRef, Length('#/definitions/') + 1, MaxInt));
    if lDef is TJSONObject then
      ValidateNode(pV, TJSONObject(lDef), pRoot, pPtr, pOut);
    Exit;
  end;
  lType := Prop(pS, 'type');
  lActual := JsonTypeName(pV);
  if (lType <> '') and (lActual <> lType) and not ((lType = 'number') and (lActual = 'integer')) then
  begin
    Add('Value is "' + lActual + '" but should be "' + lType + '"');
    Exit;
  end;
  lEnum := pS.GetValue('enum');
  if lEnum is TJSONArray then
  begin
    lOk := False;
    for i := 0 to TJSONArray(lEnum).Count - 1 do
      if TJSONArray(lEnum).Items[i].ToString = pV.ToString then
        lOk := True;
    if not lOk then
      Add('Value should match one of the values specified by the enum');
  end;
  if lActual = 'string' then
  begin
    lStr := TJSONString(pV).Value;
    if (Prop(pS, 'pattern') <> '') and not TRegEx.IsMatch(lStr, Prop(pS, 'pattern')) then
      Add('The string value is not a match for the indicated regular expression "' + Prop(pS, 'pattern') + '"');
    if IntOf('minLength', lN) and (Length(lStr) < lN) then
      Add('Value should be at least ' + IntToStr(lN) + ' characters');
    if IntOf('maxLength', lN) and (Length(lStr) > lN) then
      Add('Value should be at most ' + IntToStr(lN) + ' characters');
  end;
  if (lActual = 'integer') and IntOf('minimum', lN) and (TJSONNumber(pV).AsInt64 < lN) then
    Add(TJSONNumber(pV).ToString + ' should be at least ' + IntToStr(lN));
  if lActual = 'array' then
  begin
    if IntOf('minItems', lN) and (TJSONArray(pV).Count < lN) then
      Add('Value should have at least ' + IntToStr(lN) + ' items');
    lItems := pS.GetValue('items');
    if lItems is TJSONObject then
      for i := 0 to TJSONArray(pV).Count - 1 do
        ValidateNode(TJSONArray(pV).Items[i], TJSONObject(lItems), pRoot, pPtr + '/' + IntToStr(i), pOut);
  end;
  if lActual = 'object' then
  begin
    lReq := pS.GetValue('required');
    lMissing := nil;
    if lReq is TJSONArray then
      for i := 0 to TJSONArray(lReq).Count - 1 do
        if TJSONObject(pV).GetValue(TJSONArray(lReq).Items[i].Value) = nil then
          lMissing := lMissing + ['"' + TJSONArray(lReq).Items[i].Value + '"'];
    if Length(lMissing) > 0 then
      Add('Required properties [' + JoinS(lMissing, ', ') + '] are not present');
    lProps := pS.GetValue('properties');
    if lProps is TJSONObject then
      for lP in TJSONObject(lProps) do
      begin
        lName := lP.JsonString.Value;
        if (TJSONObject(pV).GetValue(lName) <> nil) and (lP.JsonValue is TJSONObject) then
          ValidateNode(TJSONObject(pV).GetValue(lName), TJSONObject(lP.JsonValue), pRoot, pPtr + '/' + lName, pOut);
      end;
    lAdd := pS.GetValue('additionalProperties');
    if (lAdd is TJSONBool) and not TJSONBool(lAdd).AsBoolean then
      for lP in TJSONObject(pV) do
        if (lProps is not TJSONObject) or (TJSONObject(lProps).GetValue(lP.JsonString.Value) = nil) then
        begin
          lName := lP.JsonString.Value;
          pOut.Add(SchemaMessage('All values fail against the false schema', pPtr + '/' + lName));
        end;
  end;
end;

function ValidateSchema(const pV: TJSONValue; const pSchema: TJSONObject): TArray<string>;
var
  lOut: TList<string>;
begin
  lOut := TList<string>.Create;
  try
    ValidateNode(pV, pSchema, pSchema, '', lOut);
    Result := lOut.ToArray;
  finally
    lOut.Free;
  end;
end;

{ ---- context ---- }

destructor TRawEntry.Destroy;
begin
  Entry.Free;
  inherited;
end;

function ReadEntryFile(const pPath: string): TRawEntry;
var
  lB: TBytes;
  i: Integer;
  lV: TJSONValue;
begin
  lB := TFile.ReadAllBytes(pPath);
  for i := 0 to High(lB) do
    if lB[i] > ASCII_MAX then
      raise EFeatureJson.CreateFmt('%s: non-ASCII byte 0x%.2X at byte %d', [pPath, lB[i], i]);
  Result := TRawEntry.Create;
  try
    Result.Path := pPath;
    Result.Stem := TPath.GetFileNameWithoutExtension(pPath);
    Result.Raw := TEncoding.ASCII.GetString(lB);
    lV := TJSONObject.ParseJSONValue(Result.Raw, False, False);
    if lV is not TJSONObject then
    begin
      lV.Free;
      raise EFeatureJson.CreateFmt('%s: not a JSON object', [pPath]);
    end;
    Result.Entry := TJSONObject(lV);
  except
    Result.Free;
    raise;
  end;
end;

constructor TCheckContext.Create(const pRepo: string; const pExtraIds: TArray<string>);
var
  lF, lFeatures, lId: string;
  lRoot: TJSONObject;
  lRows: TArray<TJSONValue>;
  lIdx: TArray<Integer>;
  lOrders: TArray<Integer>;
  i, j, lPos: Integer;
  lM: TMatch;
  lV: TJSONValue;
  lP: TJSONPair;
  lList: TList<string>;

  function Keys(const pObj: TJSONValue; const pKind: string): TArray<string>;
  var
    lX: TJSONValue;
    lQ: TJSONPair;
  begin
    Result := nil;
    lX := JVal(pObj, pKind);
    if lX is TJSONObject then
      for lQ in TJSONObject(lX) do
        Result := Result + [lQ.JsonString.Value];
  end;

begin
  inherited Create;
  Entries := TObjectList<TRawEntry>.Create(True);
  KnownIds := TList<string>.Create;
  Repo := pRepo;
  lFeatures := TPath.Combine(pRepo, 'features');
  // groups, stable by order
  lRoot := ReadJsonObject(TPath.Combine(lFeatures, 'groups.json'));
  try
    lRows := JItems(lRoot, 'groups');
    SetLength(lIdx, Length(lRows));
    SetLength(lOrders, Length(lRows));
    for i := 0 to High(lRows) do
    begin
      lIdx[i] := i;
      lOrders[i] := StrToIntDef(JS(lRows[i], 'order'), 0);
    end;
    TArray.Sort<Integer>(lIdx, TComparer<Integer>.Construct(
      function(const pA, pB: Integer): Integer
      begin
        Result := lOrders[pA] - lOrders[pB];
        if Result = 0 then
          Result := pA - pB;
      end));
    for lPos in lIdx do
    begin
      lId := JS(lRows[lPos], 'id');
      j := 0;
      while (j < Length(GroupIds)) and not SameText(GroupIds[j], lId) do
        Inc(j);
      if j < Length(GroupIds) then
        GroupOrders[j] := lOrders[lPos]
      else
      begin
        GroupIds := GroupIds + [lId];
        GroupOrders := GroupOrders + [lOrders[lPos]];
      end;
    end;
  finally
    lRoot.Free;
  end;
  lRoot := ReadJsonObject(TPath.Combine(lFeatures, 'teams.json'));
  try
    for lV in JItems(lRoot, 'teams') do
      if not InOrd(JS(lV, 'id'), TeamIds) then
        TeamIds := TeamIds + [JS(lV, 'id')];
  finally
    lRoot.Free;
  end;
  for lM in TRegEx.Matches(TFile.ReadAllText(TPath.Combine(pRepo, 'CHANGELOG.md')), '(?m)^## v(\d+\.\d+\.\d+(?:-alpha)?)', [roMultiLine]) do
    if not InOrd(lM.Groups[1].Value, ChangelogVersions) then
      ChangelogVersions := ChangelogVersions + [lM.Groups[1].Value];
  for lF in SortedFiles(TPath.Combine(pRepo, 'docs\wiki'), '*.md') do
    WikiPages := WikiPages + [TPath.GetFileNameWithoutExtension(lF)];
  for lF in SortedFiles(TPath.Combine(lFeatures, 'entries'), '*.json') do
    Entries.Add(ReadEntryFile(lF));
  for i := 0 to Entries.Count - 1 do
    if not KnownIds.Contains(Entries[i].Stem) then
      KnownIds.Add(Entries[i].Stem);
  for lId in pExtraIds do
    if not KnownIds.Contains(lId) then
      KnownIds.Add(lId);
  lF := TPath.Combine(lFeatures, 'seed-backlog.json');
  if TFile.Exists(lF) then
  begin
    lRoot := ReadJsonObject(lF);
    lList := TList<string>.Create;
    try
      if JVal(lRoot, 'teams') is TJSONObject then
        for lP in TJSONObject(JVal(lRoot, 'teams')) do
          if lP.JsonValue is TJSONArray then
            for i := 0 to TJSONArray(lP.JsonValue).Count - 1 do
              lList.Add(ItemText(TJSONArray(lP.JsonValue).Items[i]));
      SeedBacklog := lList.ToArray;
    finally
      lList.Free;
      lRoot.Free;
    end;
  end;
  lF := TPath.Combine(lFeatures, 'exemptions.json');
  if TFile.Exists(lF) then
  begin
    lRoot := ReadJsonObject(lF);
    try
      ExemptVerbs := Keys(lRoot, 'verbs');
      ExemptCaptions := Keys(lRoot, 'captions');
      ExemptExes := Keys(lRoot, 'exes');
    finally
      lRoot.Free;
    end;
  end;
  KeyOrder := EntryKeyOrder(TPath.Combine(lFeatures, 'schema\entry.schema.json'));
  EntrySchema := ReadJsonObject(TPath.Combine(lFeatures, 'schema\entry.schema.json'));
end;

destructor TCheckContext.Destroy;
begin
  EntrySchema.Free;
  KnownIds.Free;
  Entries.Free;
  inherited;
end;

{ ---- Test-FeatureEntry ---- }

function LastVerifiedProblems(const pValue: TJSONValue; const pCtx: TCheckContext; const pTag: string): TArray<string>;
var
  lD: TDateTime;
  lDate, lBuild: string;
begin
  Result := nil;
  lDate := JS(pValue, 'date');
  lBuild := JS(pValue, 'build');
  if not TryIsoDate(lDate, lD) then
    Result := Result + [pTag + ': lastVerified.date ''' + lDate + ''' is not yyyy-MM-dd']
  else if lD > Date then
    Result := Result + [pTag + ': lastVerified.date ''' + lDate + ''' is in the future'];
  if not InOrd(lBuild, pCtx.ChangelogVersions) then
    Result := Result + [pTag + ': lastVerified.build ''' + lBuild + ''' is not a CHANGELOG version'];
end;

function CheckEntry(const pEntry: TJSONObject; const pCtx: TCheckContext; const pStem: string; pChild: Boolean;
  pSinceOverride: Boolean): TArray<string>;
var
  lP: TList<string>;
  lId, lTag, lGroup, lOwner, lStatus, lSince, lSummary, lPage, lT, lK, lRid, lKind: string;
  lAllowed: TArray<string>;
  lPair: TJSONPair;
  lProbe: TJSONObject;
  lM: TMatch;
  lS, lX: TJSONValue;
  lInBacklog, lFound: Boolean;
  lRule, lR: TSurfaceRule;
  lRules: TArray<TSurfaceRule>;
  lErr: string;
begin
  lP := TList<string>.Create;
  try
    lId := JS(pEntry, 'id');
    lTag := (if pChild then 'child ' + lId else pStem + '.json');
    lAllowed := pCtx.KeyOrder;
    if pChild then
      for lK in CHILD_ONLY_KEYS do
        lAllowed := lAllowed + [lK];
    for lPair in pEntry do
      if not InCI(lPair.JsonString.Value, lAllowed) then
        lP.Add(lTag + ': unknown key ''' + lPair.JsonString.Value + ''' (not in entry.schema.json)');
    lProbe := TJSONObject.Create;
    try
      for lPair in pEntry do
        if InCI(lPair.JsonString.Value, pCtx.KeyOrder) then
          lProbe.AddPair(lPair.JsonString.Value, lPair.JsonValue.Clone as TJSONValue);
      if pChild and (lProbe.GetValue('id') <> nil) then
      begin
        lM := TRegEx.Match(lId, '^(?:rule|chart)\.(.+)$', [roIgnoreCase]);
        if lM.Success then
        begin
          lProbe.RemovePair('id').Free;
          lProbe.AddPair('id', lM.Groups[1].Value);
        end
        else
          lP.Add(lTag + ': child id ''' + lId + ''' must be rule.<id> or chart.<id>');
      end;
      for lErr in ValidateSchema(lProbe, pCtx.EntrySchema) do
        lP.Add(lTag + ': schema: ' + TRegEx.Replace(lErr, '\s+', ' '));
    finally
      lProbe.Free;
    end;
    if not pChild then
    begin
      if not SameText(lId, pStem) then
        lP.Add(lTag + ': id ''' + lId + ''' must equal the filename stem ''' + pStem + '''');
      if Pos('.', lId) > 0 then
        lP.Add(lTag + ': id ''' + lId + ''' contains ''.''; importers own rule.<id> and chart.<id>, hand ids never contain a dot');
    end;
    lGroup := JS(pEntry, 'group');
    if not InCI(lGroup, pCtx.GroupIds) then
      lP.Add(lTag + ': group ''' + lGroup + ''' is not in groups.json (one of: ' + JoinS(pCtx.GroupIds, ' ') + ')');
    lOwner := JS(pEntry, 'owner');
    if not InOrd(lOwner, pCtx.TeamIds) then
      lP.Add(lTag + ': owner ''' + lOwner + ''' is not in teams.json (one of: ' + JoinS(pCtx.TeamIds, ' ')
        + '); add it with feature-registry.ps1 add -NewTeam');
    lStatus := JS(pEntry, 'status');
    lInBacklog := InOrd(lId, pCtx.SeedBacklog);
    lSince := JS(pEntry, 'since');
    if SameText(lStatus, 'shipped') and (lSince = '') then
      lP.Add(lTag + ': since is required for a shipped entry');
    if (lSince <> '') and not (pChild and pSinceOverride) and not InOrd(lSince, pCtx.ChangelogVersions) then
      if not (SameText(lSince, '0.0.0') and lInBacklog) then
        lP.Add(lTag + ': since ''' + lSince + ''' is not a ''## v<version>'' heading in CHANGELOG.md');
    lSummary := JS(pEntry, 'summary');
    if lSummary.EndsWith('.') then
      lP.Add(lTag + ': summary ends with a period; the Quick-Help line carries none');
    if not pChild and SameText(lStatus, 'shipped') and not lInBacklog and not JHas(pEntry, 'intro') then
      lP.Add(lTag + ': intro is required for a shipped entry (seeded entries are exempt while listed in seed-backlog.json)');
    lPage := JS(pEntry, 'wikiPage');
    if (lPage <> '') and not InOrd(lPage, pCtx.WikiPages) then
      lP.Add(lTag + ': wikiPage ''' + lPage + ''' -- no such page in docs\wiki (exact case; did you mean: '
        + JoinS(NearestCandidates(lPage, pCtx.WikiPages), ', ') + ')');
    if InCI(lStatus, ['shipped', 'experimental', 'internal', 'deprecated']) and (Length(JItems(pEntry, 'surfaces')) = 0) then
      lP.Add(lTag + ': surfaces must hold at least one surface for status ''' + lStatus + '''');
    lRules := SurfaceRules;
    for lS in JItems(pEntry, 'surfaces') do
    begin
      if lS is not TJSONObject then
      begin
        lP.Add(lTag + ': surfaces[] item is not an object');
        Continue;
      end;
      lT := JS(lS, 'type');
      lFound := False;
      lRule := Default(TSurfaceRule);
      for lR in lRules do
        if SameText(lR.Kind, lT) then
        begin
          lRule := lR;
          lFound := True;
          Break;
        end;
      if not lFound then
      begin
        lP.Add(lTag + ': surface type ''' + lT + ''' unknown');
        Continue;
      end;
      for lPair in TJSONObject(lS) do
        if not InCI(lPair.JsonString.Value, lRule.Keys) then
          lP.Add(lTag + ': surface ''' + lT + ''' has unknown key ''' + lPair.JsonString.Value + '''');
      for lK in lRule.Required do
        if not JHas(lS, lK) or IsBlank(JS(lS, lK)) then
          lP.Add(lTag + ': surface ''' + lT + ''' is missing required key ''' + lK + '''');
      if SameText(lT, 'cli') then
      begin
        if not TRegEx.IsMatch(JS(lS, 'verb'), '^[a-z][a-z0-9-]*$', [roIgnoreCase]) then
          lP.Add(lTag + ': cli verb ''' + JS(lS, 'verb') + ''' is not a verb token');
      end
      else if SameText(lT, 'ide-menu') then
      begin
        if not JS(lS, 'path').ToLower.StartsWith('drag-lint > ') then
          lP.Add(lTag + ': ide-menu path must start ''drag-lint > '' (full path, every level)');
      end
      else if SameText(lT, 'tool-window') then
      begin
        if not JS(lS, 'path').ToLower.StartsWith('view > tool windows > ') then
          lP.Add(lTag + ': tool-window path must start ''View > Tool Windows > ''');
      end
      else if SameText(lT, 'ide-context') then
      begin
        if not InCI(JS(lS, 'host'), CONTEXT_HOSTS) then
          lP.Add(lTag + ': ide-context host ''' + JS(lS, 'host') + ''' must be one of: ' + string.Join(', ', CONTEXT_HOSTS));
      end
      else if SameText(lT, 'script') then
      begin
        if not RepoRelativeExists(pCtx.Repo, JS(lS, 'path')) then
          lP.Add(lTag + ': script path ''' + JS(lS, 'path') + ''' does not exist (repo-relative)');
      end
      else if SameText(lT, 'workflow') then
      begin
        if not RepoRelativeExists(pCtx.Repo, JS(lS, 'doc')) then
          lP.Add(lTag + ': workflow doc ''' + JS(lS, 'doc') + ''' does not exist (repo-relative)');
      end
      else if SameText(lT, 'exe') then
      begin
        if not JS(lS, 'name').ToLower.EndsWith('.exe') then
          lP.Add(lTag + ': exe name ''' + JS(lS, 'name') + ''' must end in .exe');
      end;
    end;
    for lX in JItems(pEntry, 'examples') do
    begin
      if lX is not TJSONObject then
        Continue;
      lKind := JS(lX, 'kind');
      if SameText(lKind, 'command') and IsBlank(JS(lX, 'text')) then
        lP.Add(lTag + ': a command example needs ''text''');
      if InCI(lKind, ['file', 'image']) and not RepoRelativeExists(pCtx.Repo, JS(lX, 'path')) then
        lP.Add(lTag + ': example path ''' + JS(lX, 'path') + ''' does not exist (repo-relative)');
    end;
    for lX in JItems(pEntry, 'related') do
    begin
      lRid := ItemText(lX);
      if SameText(lRid, lId) then
        lP.Add(lTag + ': related names itself')
      else if not pCtx.KnownIds.Contains(lRid) then
        lP.Add(lTag + ': related ''' + lRid + ''' is not a registered id (did you mean: '
          + JoinS(NearestCandidates(lRid, pCtx.KnownIds.ToArray), ', ') + ')');
    end;
    if JHas(pEntry, 'supersededBy') and not SameText(lStatus, 'deprecated') then
      lP.Add(lTag + ': supersededBy is only valid with status deprecated');
    if JHas(pEntry, 'removedIn') and not SameText(lStatus, 'deprecated') then
      lP.Add(lTag + ': removedIn is only valid with status deprecated');
    if JHas(pEntry, 'supersededBy') and not pCtx.KnownIds.Contains(JS(pEntry, 'supersededBy')) then
      lP.Add(lTag + ': supersededBy ''' + JS(pEntry, 'supersededBy') + ''' is not a registered id');
    if JHas(pEntry, 'family') and not TFile.Exists(TPath.Combine(pCtx.Repo, 'features\families\' + JS(pEntry, 'family') + '.json')) then
      lP.Add(lTag + ': family ''' + JS(pEntry, 'family') + ''' has no features\families\<family>.json');
    if JHas(pEntry, 'lastVerified') then
      lP.AddRange(LastVerifiedProblems(JVal(pEntry, 'lastVerified'), pCtx, lTag))
    else if not pChild and SameText(lStatus, 'shipped') and not lInBacklog then
      lP.Add(lTag + ': lastVerified is required for a shipped entry (seeded entries are exempt while listed in seed-backlog.json)');
    for lX in JItems(pEntry, 'tests') do
      if not RepoRelativeExists(pCtx.Repo, ItemText(lX)) then
        lP.Add(lTag + ': tests path ''' + ItemText(lX) + ''' does not exist');
    Result := lP.ToArray;
  finally
    lP.Free;
  end;
end;

{ ---- the runner ---- }

type
  TFamilyDef = record
    Name: string;
    Path: string;
    Def: TJSONObject;
  end;

  TChecker = class
  strict private
    FRepo: string;
    FLive: TLiveSurface;
    FLevel: TCheckLevel;
    FExtra: TArray<TJSONObject>;
    FSkipGenerated: Boolean;
    FFail: TList<TFinding>;
    FNotes: TList<string>;
    FFamilies: TList<TFamilyDef>;
    FChildren: TObjectList<TJSONObject>;
    procedure Fail(pCheck: Char; const pText: string);
    function ReadFamilyDefinition(const pPath: string; const pCtx: TCheckContext): TJSONObject;
    function GroupsAndTeams(const pCtx: TCheckContext): TArray<string>;
    function Skeleton(const pId: string; const pSurface: TJSONObject; const pCtx: TCheckContext): string;
    function FamilyPrecheck(const pHand: TArray<TJSONObject>; const pCtx: TCheckContext; out pParents: TDictionary<string, string>): string;
    procedure ImportChildren(const pHand: TArray<TJSONObject>);
    procedure CheckLive(const pHand: TArray<TJSONObject>; const pCtx: TCheckContext);
    procedure CheckBacklog(const pCtx: TCheckContext);
    procedure CheckGenerated;
    procedure CheckStale(const pHand: TArray<TJSONObject>);
  public
    constructor Create(const pRepo: string; const pLive: TLiveSurface; pLevel: TCheckLevel; const pExtra: TArray<TJSONObject>;
      pSkipGenerated: Boolean);
    destructor Destroy; override;
    procedure Run;
    function Findings: TArray<TFinding>;
    function Notes: TArray<string>;
  end;

constructor TChecker.Create(const pRepo: string; const pLive: TLiveSurface; pLevel: TCheckLevel; const pExtra: TArray<TJSONObject>;
  pSkipGenerated: Boolean);
begin
  inherited Create;
  FRepo := pRepo;
  FLive := pLive;
  FLevel := pLevel;
  FExtra := pExtra;
  FSkipGenerated := pSkipGenerated;
  FFail := TList<TFinding>.Create;
  FNotes := TList<string>.Create;
  FFamilies := TList<TFamilyDef>.Create;
  FChildren := TObjectList<TJSONObject>.Create(True);
end;

destructor TChecker.Destroy;
var
  lF: TFamilyDef;
begin
  for lF in FFamilies do
    lF.Def.Free;
  FFamilies.Free;
  FChildren.Free;
  FNotes.Free;
  FFail.Free;
  inherited;
end;

procedure TChecker.Fail(pCheck: Char; const pText: string);
var
  lF: TFinding;
begin
  lF.Check := pCheck;
  lF.Text := pText;
  FFail.Add(lF);
end;

function TChecker.Findings: TArray<TFinding>;
begin
  Result := FFail.ToArray;
end;

function TChecker.Notes: TArray<string>;
begin
  Result := FNotes.ToArray;
end;

{ Read-FamilyDefinition: raises with the PowerShell text. }
function TChecker.ReadFamilyDefinition(const pPath: string; const pCtx: TCheckContext): TJSONObject;
var
  lAsc, lK: string;
  lLv: TJSONValue;
  lP: TJSONPair;
  lProblems: TArray<string>;
begin
  lAsc := AsciiCrlfProblem(pPath);
  if lAsc <> '' then
    raise EFeatureGen.Create('family definition: ' + lAsc);
  Result := ReadJsonObject(pPath);
  try
    for lK in ['family', 'entry', 'children', 'lastVerified'] do
      if not JHas(Result, lK) then
        raise EFeatureGen.CreateFmt('%s: family definition is missing ''%s''', [pPath, lK]);
    lLv := JVal(Result, 'lastVerified');
    if lLv is not TJSONObject then
      raise EFeatureGen.CreateFmt('%s: lastVerified must be an object { date, by, build }', [pPath]);
    for lP in TJSONObject(lLv) do
      if not InCI(lP.JsonString.Value, LAST_VERIFIED_KEYS) then
        raise EFeatureGen.CreateFmt('%s: lastVerified has unknown key ''%s'' (allowed: date, by, build)', [pPath, lP.JsonString.Value]);
    for lK in LAST_VERIFIED_KEYS do
      if IsBlank(JS(lLv, lK)) then
        raise EFeatureGen.CreateFmt('%s: lastVerified.%s is missing or empty', [pPath, lK]);
    lProblems := LastVerifiedProblems(lLv, pCtx, pPath);
    if Length(lProblems) > 0 then
      raise EFeatureGen.Create(JoinS(lProblems, #10));
  except
    Result.Free;
    raise;
  end;
end;

function TChecker.GroupsAndTeams(const pCtx: TCheckContext): TArray<string>;
var
  lP: TList<string>;
  lSchema, lRoot: TJSONObject;
  lFile, lAsc, lG, lErr: string;
  i, j, lCount: Integer;
  lE: TRawEntry;
begin
  lP := TList<string>.Create;
  try
    lSchema := ReadJsonObject(TPath.Combine(FRepo, 'features\schema\groups.schema.json'));
    try
      for lFile in [TPath.Combine(FRepo, 'features\groups.json'), TPath.Combine(FRepo, 'features\teams.json')] do
      begin
        lRoot := ReadJsonObject(lFile);
        try
          for lErr in ValidateSchema(lRoot, lSchema) do
            lP.Add(lFile + ': ' + TRegEx.Replace(lErr, '\s+', ' '));
        finally
          lRoot.Free;
        end;
        lAsc := AsciiCrlfProblem(lFile);
        if lAsc <> '' then
          lP.Add(lAsc);
      end;
    finally
      lSchema.Free;
    end;
    for i := 0 to High(pCtx.GroupOrders) do
      for j := i + 1 to High(pCtx.GroupOrders) do
        if pCtx.GroupOrders[i] = pCtx.GroupOrders[j] then
        begin
          if not lP.Contains('groups.json: duplicate group order') then
            lP.Add('groups.json: duplicate group order');
        end;
    for lG in pCtx.GroupIds do
      if not TRegEx.IsMatch(lG, '^[a-z][a-z0-9-]*$', [roIgnoreCase]) then
        lP.Add('groups.json: group id ''' + lG + ''' is not kebab-case');
    if (FLevel = clFull) and (pCtx.Entries.Count > 0) then
      for lG in pCtx.GroupIds do
      begin
        lCount := 0;
        for lE in pCtx.Entries do
          if SameText(JS(lE.Entry, 'group'), lG) then
            Inc(lCount);
        if lCount = 0 then
          lP.Add('groups.json: group ''' + lG + ''' has no entries -- a group is created by registering into it and deleted when it empties');
      end;
    Result := lP.ToArray;
  finally
    lP.Free;
  end;
end;

function SurfaceObj(const pPairs: array of string): TJSONObject;
var
  i: Integer;
begin
  Result := TJSONObject.Create;
  i := 0;
  while i < High(pPairs) do
  begin
    Result.AddPair(pPairs[i], pPairs[i + 1]);
    Inc(i, 2);
  end;
end;

{ Get-EntrySkeleton: a canonical entry with <placeholders>; pSurface is consumed. }
function TChecker.Skeleton(const pId: string; const pSurface: TJSONObject; const pCtx: TCheckContext): string;
var
  lPage, lW: string;
  lSk, lLv: TJSONObject;
  lArr: TJSONArray;
begin
  lPage := '<page stem under docs\wiki>';
  if InOrd(pId, pCtx.WikiPages) then
    lPage := pId
  else
    for lW in pCtx.WikiPages do
      if SameText(lW, pId) then
      begin
        lPage := lW;
        Break;
      end;
  lSk := TJSONObject.Create;
  try
    lSk.AddPair('id', pId);
    lSk.AddPair('title', '<the name a human says>');
    lSk.AddPair('group', '<one of: ' + JoinS(pCtx.GroupIds, ' ') + '>');
    lSk.AddPair('owner', '<one of: ' + JoinS(pCtx.TeamIds, ' ') + '>');
    lSk.AddPair('status', 'shipped');
    lSk.AddPair('since', FLive.ProductVersion);
    lSk.AddPair('summary', '<one line, 20..160 chars, no trailing period>');
    lSk.AddPair('intro', '<1..5 sentences: what it does, when to reach for it, what it needs>');
    lSk.AddPair('wikiPage', lPage);
    lArr := TJSONArray.Create;
    lArr.AddElement(pSurface);
    lSk.AddPair('surfaces', lArr);
    lSk.AddPair('audience', 'both');
    lLv := TJSONObject.Create;
    lLv.AddPair('date', TodayText);
    lLv.AddPair('by', '<you>');
    lLv.AddPair('build', FLive.ProductVersion);
    lSk.AddPair('lastVerified', lLv);
    Result := CanonicalJson(lSk, nil);
  finally
    lSk.Free;
  end;
end;

function OverrideText(const pDef: TJSONObject; const pChildId, pKey: string): string;
var
  lCh, lOv, lV: TJSONValue;
begin
  lCh := JVal(pDef, 'children');
  lOv := JVal(lCh, pChildId);
  lV := JVal(lOv, pKey);
  if (lV <> nil) and not (lV is TJSONNull) and (ItemText(lV) <> '') then
    Exit(ItemText(lV));
  lV := JVal(JVal(pDef, 'defaults'), pKey);
  if (lV <> nil) and not (lV is TJSONNull) and (ItemText(lV) <> '') then
    Exit(ItemText(lV));
  Result := '';
end;

function ObjectKeys(const pObj: TJSONValue): TArray<string>;
var
  lP: TJSONPair;
begin
  Result := nil;
  if pObj is TJSONObject then
    for lP in TJSONObject(pObj) do
      Result := Result + [lP.JsonString.Value];
end;

{ Get-RegistryChildren's own validation, in its order; '' when the import may run.
  pParents receives family -> parent since. }
function TChecker.FamilyPrecheck(const pHand: TArray<TJSONObject>; const pCtx: TCheckContext; out pParents: TDictionary<string, string>): string;
var
  lDefs, lIds, lMenuIds, lNoMenu, lNoScript, lUnnamed, lGhost, lNamed, lNamedSorted: TArray<string>;
  lF, lFam, lOv, lEmitter, lLeaf, lSub: string;
  lE, lParent: TJSONObject;
  lDef: TJSONObject;
  lCount: Integer;
  lRules: TArray<TJSONValue>;
  lV: TJSONValue;
  lQ: TReportQuestion;
begin
  Result := '';
  pParents := TDictionary<string, string>.Create;
  for lF in SortedFiles(TPath.Combine(FRepo, 'features\families'), '*.json') do
    lDefs := lDefs + [TPath.GetFileNameWithoutExtension(lF)];
  for lE in pHand do
    if JHas(lE, 'family') and not InOrd(JS(lE, 'family'), lDefs) then
      Exit(Format('family ''%s'' (entry ''%s'') has no features\families\%s.json', [JS(lE, 'family'), JS(lE, 'id'), JS(lE, 'family')]));
  for lFam in lDefs do
    if not InOrd(lFam, FAMILY_IMPORTERS) then
      Exit(Format('features\families\%s.json has no importer (known: lint-rules, chart-questions)', [lFam]));
  for lFam in FAMILY_IMPORTERS do
  begin
    if not InOrd(lFam, lDefs) then
      Continue;
    try
      lDef := ReadFamilyDefinition(TPath.Combine(FRepo, 'features\families\' + lFam + '.json'), pCtx);
    except
      on E: Exception do
        Exit(E.Message);
    end;
    try
      if JS(lDef, 'family') <> lFam then
        Exit(Format('features\families\%s.json declares family ''%s''; it must equal the file name', [lFam, JS(lDef, 'family')]));
      lCount := 0;
      lParent := nil;
      for lE in pHand do
        if JHas(lE, 'family') and (JS(lE, 'id') = JS(lDef, 'entry')) and (JS(lE, 'family') = lFam) then
        begin
          Inc(lCount);
          lParent := lE;
        end;
      if lCount <> 1 then
        Exit(Format('features\families\%s.json names entry ''%s'', but no hand entry with id ''%s'' and family ''%s'' exists',
          [lFam, JS(lDef, 'entry'), JS(lDef, 'entry'), lFam]));
      pParents.AddOrSetValue(lFam, JS(lParent, 'since'));
      if lFam = 'lint-rules' then
      begin
        lRules := JItems(FLive.RuleCatalog, 'rules');
        if Length(lRules) = 0 then
          Exit('lint-rules importer: 0 rules harvested');
        if IntToStr(Length(lRules)) <> JS(JVal(FLive.RuleCatalog, 'summary'), 'total') then
          Exit(Format('lint-rules importer: %d rule rows vs summary.total %s', [Length(lRules), JS(JVal(FLive.RuleCatalog, 'summary'), 'total')]));
        lIds := nil;
        for lV in lRules do
          lIds := lIds + [JS(lV, 'id')];
        for lOv in ObjectKeys(JVal(lDef, 'children')) do
          if not InOrd(lOv, lIds) then
            Exit('lint-rules importer: override ''' + lOv + ''' names a rule that no longer exists in rules --json (did you mean: '
              + JoinS(NearestCandidates(lOv, lIds), ', ') + ')');
      end
      else
      begin
        if Length(FLive.ReportQuestions) = 0 then
          Exit('chart-questions importer: 0 questions harvested from REPORT_QUESTIONS');
        if Length(FLive.ReportQuestions) <> FLive.ReportQuestionCount then
          Exit(Format('chart-questions importer: %d catalog rows vs REPORT_QUESTION_COUNT = %d', [Length(FLive.ReportQuestions), FLive.ReportQuestionCount]));
        lMenuIds := nil;
        for lQ in FLive.ReportQuestions do
          lMenuIds := lMenuIds + [lQ.Id];
        lNoMenu := nil;
        lNoScript := nil;
        for lSub in FLive.ChartValidateSet do
          if not InOrd(lSub, lMenuIds) then
            lNoMenu := lNoMenu + [lSub];
        for lSub in lMenuIds do
          if not InOrd(lSub, FLive.ChartValidateSet) then
            lNoScript := lNoScript + [lSub];
        if (Length(lNoMenu) > 0) or (Length(lNoScript) > 0) then
          Exit(Format('chart-questions importer: catalog and ValidateSet differ -- in New-DiagramArtifact.ps1 only: [%s]; in REPORT_QUESTIONS only: [%s]',
            [JoinS(lNoMenu, ' '), JoinS(lNoScript, ' ')]));
        for lOv in ObjectKeys(JVal(lDef, 'children')) do
          if not InOrd(lOv, lMenuIds) then
            Exit('chart-questions importer: override ''' + lOv + ''' names a question that no longer exists (did you mean: '
              + JoinS(NearestCandidates(lOv, lMenuIds), ', ') + ')');
        lNamed := nil;
        for lQ in FLive.ReportQuestions do
        begin
          lEmitter := OverrideText(lDef, lQ.Id, 'emitter');
          if lEmitter <> '' then
          begin
            if not RepoRelativeExists(FRepo, lEmitter) then
              Exit('chart-questions importer: emitter ''' + lEmitter + ''' for ''' + lQ.Id + ''' does not exist');
            lLeaf := ExtractFileName(lEmitter);
            if not InCI(lLeaf, lNamed) then
              lNamed := lNamed + [lLeaf];
          end;
          if not FLive.GroupCaptions.ContainsKey(lQ.Kind) then
            Exit('chart-questions importer: no ReportGroupCaption for Kind ' + lQ.Kind);
        end;
        lUnnamed := nil;
        for lSub in FLive.EmitterFiles do
          if not InCI(lSub, lNamed) then
            lUnnamed := lUnnamed + [lSub];
        lGhost := nil;
        lNamedSorted := SortUniqueText(lNamed);
        for lSub in lNamedSorted do
          if not InCI(lSub, FLive.EmitterFiles) then
            lGhost := lGhost + [lSub];
        if (Length(lUnnamed) > 0) or (Length(lGhost) > 0) then
          Exit(Format('chart-questions importer: emitter set drift -- on disk but no child names it: [%s]; named but not on disk: [%s]',
            [JoinS(lUnnamed, ' '), JoinS(lGhost, ' ')]));
      end;
    finally
      lDef.Free;
    end;
  end;
end;

procedure TChecker.ImportChildren(const pHand: TArray<TJSONObject>);
var
  lCtx: TCheckContext;
  lIds, lProblems: TArray<string>;
  lE, lC: TJSONObject;
  lKids: TArray<TJSONObject>;
  lParents: TDictionary<string, string>;
  lMsg, lFam, lParentSince: string;
  lLetter: Char;
begin
  lIds := nil;
  for lE in pHand do
    lIds := lIds + [JS(lE, 'id')];
  lParents := nil;
  lCtx := nil;
  try
    try
      lCtx := TCheckContext.Create(FRepo, lIds);
      lMsg := FamilyPrecheck(pHand, lCtx, lParents);
      if lMsg = '' then
      begin
        lKids := ImportFamilyChildren(FRepo, pHand, FLive.RuleCatalog, lCtx.KeyOrder);
        for lC in lKids do
          FChildren.Add(lC);
        for lC in FChildren do
          if not lCtx.KnownIds.Contains(JS(lC, 'id')) then
            lCtx.KnownIds.Add(JS(lC, 'id'));
        lProblems := nil;
        for lC in FChildren do
        begin
          lFam := (if JS(lC, 'id').StartsWith('rule.') then 'lint-rules' else 'chart-questions');
          if not lParents.TryGetValue(lFam, lParentSince) then
            lParentSince := '';
          lProblems := lProblems + CheckEntry(lC, lCtx, JS(lC, 'id'), True, JS(lC, 'since') <> lParentSince);
        end;
        if Length(lProblems) > 0 then
          lMsg := 'family children failed validation:'#10 + JoinS(lProblems, #10);
      end;
    except
      on E: Exception do
        lMsg := E.Message;
    end;
  finally
    lParents.Free;
    lCtx.Free;
  end;
  if lMsg <> '' then
  begin
    FChildren.Clear;
    if lMsg.ToLower.StartsWith('family children failed validation') then
      lLetter := 'A'
    else if Pos('override', lMsg.ToLower) > 0 then
      lLetter := 'C'
    else
      lLetter := 'B';
    Fail(lLetter, 'family import: ' + lMsg);
  end;
end;

{ Test-RegistryCaptionMatch: exact key, or a prefix either way when the shorter key is >= 12 chars. }
function RegistryCaptionMatch(const pKey: string; const pKeys: TArray<string>): Boolean;
var
  lK, lShort: string;
begin
  if pKey = '' then
    Exit(False);
  for lK in pKeys do
  begin
    if lK = '' then
      Continue;
    if lK = pKey then
      Exit(True);
    lShort := (if Length(lK) < Length(pKey) then lK else pKey);
    if Length(lShort) < MIN_CAPTION_PREFIX then
      Continue;
    if lK.StartsWith(pKey) or pKey.StartsWith(lK) then
      Exit(True);
  end;
  Result := False;
end;

{ Get-NearestCaption: candidates scored whole and cut to the key's length; the 3 nearest captions. }
function NearestCaption(const pKey: string; const pCaptions: TArray<string>): TArray<string>;
var
  lPool: TDictionary<string, string>;
  lOrder: TList<string>;
  lC, lCk, lCut, lN, lO: string;
  lSeen: TList<string>;
begin
  lPool := TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  lOrder := TList<string>.Create;
  lSeen := TList<string>.Create;
  try
    for lC in pCaptions do
    begin
      if not lPool.ContainsKey(lC) then
        lOrder.Add(lC);
      lPool.AddOrSetValue(lC, lC);
      lCk := CaptionKey(lC);
      if Length(lCk) > Length(pKey) then
      begin
        lCut := Copy(lCk, 1, Length(pKey));
        if not lPool.ContainsKey(lCut) then
        begin
          lPool.Add(lCut, lC);
          lOrder.Add(lCut);
        end;
      end;
    end;
    for lN in NearestCandidates(pKey, lOrder.ToArray, NEAREST_POOL) do
    begin
      lO := lPool[lN];
      if not lSeen.Contains(lO) then
        lSeen.Add(lO);
      if lSeen.Count >= NEAREST_SHOWN then
        Break;
    end;
    Result := lSeen.ToArray;
  finally
    lSeen.Free;
    lOrder.Free;
    lPool.Free;
  end;
end;

{ The caption key of an IDE surface's leaf (Get-LeafKey); '' for other surface types. }
function LeafKey(const pS: TJSONValue): string;
var
  lT: string;
  lParts: TArray<string>;
begin
  lT := JS(pS, 'type');
  if SameText(lT, 'ide-menu') or SameText(lT, 'tool-window') then
  begin
    lParts := TRegEx.Split(JS(pS, 'path'), '\s+>\s+');
    Result := CaptionKey(lParts[High(lParts)]);
  end
  else if SameText(lT, 'ide-context') or SameText(lT, 'ide-about') then
    Result := CaptionKey(JS(pS, 'caption'))
  else
    Result := '';
end;

function CaptionKeys(const pCaptions: TArray<string>): TArray<string>;
var
  lC, lK: string;
begin
  Result := nil;
  for lC in pCaptions do
  begin
    lK := CaptionKey(lC);
    if lK <> '' then
      Result := Result + [lK];
  end;
end;

procedure TChecker.CheckLive(const pHand: TArray<TJSONObject>; const pCtx: TCheckContext);
var
  lAll: TArray<TJSONObject>;
  lE: TJSONObject;
  lS: TJSONValue;
  lRegVerbs, lRegSubs, lRegExes, lRegMcp: TList<string>;
  lRegKeys, lLiveKeys, lAboutKeys, lHostKeys, lSubs: TArray<string>;
  lRegCtx: TDictionary<string, TArray<string>>;
  lV, lSub, lCap, lK, lSid, lH, lX, lId, lSt, lT, lWhere: string;
  lM: TMatch;
  lLiveOk, lInternal: Boolean;
  lHs: TJSONValue;
begin
  lAll := pHand;
  for lE in FChildren do
    lAll := lAll + [lE];
  lRegVerbs := TList<string>.Create;
  lRegSubs := TList<string>.Create;
  lRegExes := TList<string>.Create;
  lRegMcp := TList<string>.Create;
  lRegCtx := TDictionary<string, TArray<string>>.Create;
  try
    // ---- B. live -> registry
    lRegKeys := nil;
    for lE in lAll do
    begin
      if SameText(JS(lE, 'status'), 'planned') then
        Continue;
      for lS in JItems(lE, 'surfaces') do
      begin
        lT := JS(lS, 'type');
        if SameText(lT, 'cli') then
        begin
          lRegVerbs.Add(LowerCase(JS(lS, 'verb')));
          if JHas(lS, 'sub') then
            lRegSubs.Add(LowerCase(JS(lS, 'verb') + ' ' + JS(lS, 'sub')));
        end
        else if SameText(lT, 'exe') then
          lRegExes.Add(LowerCase(JS(lS, 'name')))
        else
        begin
          if SameText(lT, 'mcp') then
            lRegMcp.Add(LowerCase(JS(lS, 'tool')));
          lK := LeafKey(lS);
          if lK <> '' then
            lRegKeys := lRegKeys + [lK];
          if (lK <> '') and SameText(lT, 'ide-context') then
          begin
            lH := JS(lS, 'host');
            if not lRegCtx.ContainsKey(lH) then
              lRegCtx.Add(lH, nil);
            lRegCtx[lH] := lRegCtx[lH] + [lK];
          end;
        end;
      end;
    end;
    for lV in FLive.HelpVerbs do
    begin
      if lRegVerbs.Contains(LowerCase(lV)) or InCI(lV, pCtx.ExemptVerbs) then
        Continue;
      Fail('B', 'every --help verb is registered -- unregistered: ''' + lV + ''''#10'   ^ no entry claims it. Create features\entries\' + lV
        + '.json (tools\feature-registry.ps1 add -Id ' + lV + ' ...), then run tools\build-feature-pages.ps1 and commit the regenerated pages:'#10
        + Indent3(Skeleton(lV, SurfaceObj(['type', 'cli', 'verb', lV]), pCtx)));
    end;
    for lV in FLive.SubVerbs do
    begin
      lInternal := False;
      for lE in pHand do
        for lHs in JItems(lE, 'surfaces') do
          if SameText(JS(lHs, 'type'), 'cli') and SameText(JS(lHs, 'verb'), lV) then
          begin
            if SameText(JS(lE, 'status'), 'internal') then
              lInternal := True;
            Break;
          end;
      if lInternal then
        Continue;
      for lSub in FLive.SubMap[lV] do
      begin
        if lRegSubs.Contains(LowerCase(lV + ' ' + lSub)) or InCI(lV + ' ' + lSub, pCtx.ExemptVerbs) then
          Continue;
        Fail('B', 'every subcommand is registered -- unregistered: ''' + lV + ' ' + lSub + ''''#10'   ^ add { "type": "cli", "verb": "' + lV
          + '", "sub": "' + lSub + '" } to the entry that owns it, or create features\entries\' + lV + '-' + lSub + '.json:'#10
          + Indent3(Skeleton(lV + '-' + lSub, SurfaceObj(['type', 'cli', 'verb', lV, 'sub', lSub]), pCtx)));
      end;
    end;
    for lCap in FLive.Captions do
    begin
      lK := CaptionKey(lCap);
      if lK = '' then
        Continue;
      if RegistryCaptionMatch(lK, lRegKeys) or InCI(lCap, pCtx.ExemptCaptions) then
        Continue;
      lSid := TRegEx.Replace(LowerCase(lCap), '[^a-z0-9]+', '-').Trim(['-']);
      Fail('B', 'every live IDE caption is registered -- unregistered: ''' + lCap + ''''#10
        + '   ^ no ide-menu/ide-context/ide-about/tool-window surface matches it (exact, or a prefix of >= 12 characters; nearest registered: '
        + JoinS(NearestCandidates(lK, lRegKeys), ' | ')
        + '). Register it, or add it to features\exemptions.json captions WITH a reason if it is a container or header:'#10
        + Indent3(Skeleton(lSid, SurfaceObj(['type', 'ide-menu', 'path', 'drag-lint > <submenu> > ' + lCap]), pCtx)));
    end;
    for lH in FLive.ContextHosts do
    begin
      if not lRegCtx.TryGetValue(lH, lHostKeys) then
        lHostKeys := nil;
      for lCap in FLive.ContextCaptions[lH] do
      begin
        lK := CaptionKey(lCap);
        if (lK = '') or RegistryCaptionMatch(lK, lHostKeys) then
          Continue;
        lSid := TRegEx.Replace(LowerCase(lCap), '[^a-z0-9]+', '-').Trim(['-']);
        Fail('B', 'every context-menu item is registered -- unregistered: ''' + lCap + ''' (' + lH + ')'#10
          + '   ^ no ide-context surface with host ''' + lH + ''' matches it (exact, or a prefix of >= 12 characters). Add { "type": "ide-context", "host": "'
          + lH + '", "caption": "' + lCap + '" } to the entry that owns it, or create:'#10
          + Indent3(Skeleton(lSid, SurfaceObj(['type', 'ide-context', 'host', lH, 'caption', lCap]), pCtx)));
      end;
    end;
    for lX in FLive.PackExes do
      if not lRegExes.Contains(LowerCase(lX)) and not InCI(lX, pCtx.ExemptExes) then
        Fail('B', 'every release payload exe is registered -- ''' + lX + ''' is packed by build\pack-lint-release.ps1 and no entry has an exe surface for it (add { "type": "exe", "name": "'
          + lX + '" } to the entry that owns it, or exempt it in features\exemptions.json exes WITH a reason)');
    // Delphi-only (spec criterion 5): every live MCP tool is registered.
    for lX in FLive.McpTools do
      if not lRegMcp.Contains(LowerCase(lX)) then
        Fail('B', 'every MCP tool is registered -- unregistered: ''' + lX + ''''#10'   ^ no entry has an mcp surface for it. Add { "type": "mcp", "tool": "'
          + lX + '" } to the entry that owns it, or create features\entries\' + lX.Replace('_', '-') + '.json:'#10
          + Indent3(Skeleton(lX.Replace('_', '-'), SurfaceObj(['type', 'mcp', 'tool', lX]), pCtx)));
    // exemptions, both ways
    for lK in pCtx.ExemptVerbs do
    begin
      lM := TRegEx.Match(lK, '^(\S+) (\S+)$');
      if lM.Success then
        lLiveOk := InCI(lM.Groups[1].Value, FLive.SubVerbs) and InCI(lM.Groups[2].Value, FLive.SubMap[lM.Groups[1].Value])
      else
        lLiveOk := InCI(lK, FLive.HelpVerbs);
      if not lLiveOk then
      begin
        Fail('B', 'exemptions.json verbs: ''' + lK + ''' is no longer a --help verb or subcommand -- delete the exemption');
        Continue;
      end;
      if (lM.Success and lRegSubs.Contains(LowerCase(lK))) or (not lM.Success and lRegVerbs.Contains(LowerCase(lK))) then
        Fail('B', 'exemptions.json verbs: ''' + lK + ''' is registered after all -- delete the exemption');
    end;
    for lK in pCtx.ExemptCaptions do
      if not InOrd(lK, FLive.Captions) then
        Fail('B', 'exemptions.json captions: ''' + lK + ''' is no longer a live caption (nearest: ' + JoinS(NearestCandidates(lK, FLive.Captions), ' | ')
          + ') -- delete or correct the exemption')
      else if RegistryCaptionMatch(CaptionKey(lK), lRegKeys) then
        Fail('B', 'exemptions.json captions: ''' + lK + ''' is covered by a registered surface after all -- delete the exemption');
    for lK in pCtx.ExemptExes do
      if not InCI(lK, FLive.PackExes) then
        Fail('B', 'exemptions.json exes: ''' + lK + ''' is no longer packed -- delete the exemption');
    if Length(pCtx.ExemptVerbs) + Length(pCtx.ExemptCaptions) + Length(pCtx.ExemptExes) > 0 then
      FNotes.Add(Format('exempt with reason: %d verb(s), %d caption(s), %d exe(s) -- features\exemptions.json',
        [Length(pCtx.ExemptVerbs), Length(pCtx.ExemptCaptions), Length(pCtx.ExemptExes)]));
    // ---- C. registry -> live
    lLiveKeys := CaptionKeys(FLive.Captions);
    lAboutKeys := lLiveKeys + CaptionKeys(FLive.DialogButtons);
    for lE in lAll do
    begin
      lSt := JS(lE, 'status');
      lId := JS(lE, 'id');
      if SameText(lSt, 'planned') then
      begin
        FNotes.Add('planned, surfaces not checked: ' + lId);
        Continue;
      end;
      if SameText(lSt, 'deprecated') and JHas(lE, 'removedIn') then
      begin
        FNotes.Add('removed in ' + JS(lE, 'removedIn') + ', surfaces not checked: ' + lId);
        Continue;
      end;
      for lS in JItems(lE, 'surfaces') do
      begin
        lT := JS(lS, 'type');
        if SameText(lT, 'cli') then
        begin
          lV := JS(lS, 'verb');
          if SameText(lSt, 'internal') then
          begin
            if not InCI(lV, FLive.DispatchVerbs) then
              Fail('C', lId + ': internal verb ''' + lV + ''' is not dispatched by the CLI (nearest: ' + JoinS(NearestCandidates(lV, FLive.DispatchVerbs), ', ') + ')');
          end
          else if not InCI(lV, FLive.HelpVerbs) then
            Fail('C', lId + ': cli verb ''' + lV + ''' is not in --help (nearest: ' + JoinS(NearestCandidates(lV, FLive.HelpVerbs), ', ')
              + ') -- if it was retired, deprecate the entry with removedIn');
          if JHas(lS, 'sub') then
          begin
            lSubs := nil;
            if InCI(lV, FLive.SubVerbs) then
              lSubs := FLive.SubMap[lV];
            if not InCI(JS(lS, 'sub'), lSubs) then
              Fail('C', lId + ': subcommand ''' + lV + ' ' + JS(lS, 'sub') + ''' is not dispatched (nearest: ' + JoinS(NearestCandidates(JS(lS, 'sub'), lSubs), ', ') + ')');
          end;
        end
        else if SameText(lT, 'mcp') then
        begin
          if not InCI(JS(lS, 'tool'), FLive.McpTools) then
            Fail('C', lId + ': mcp tool ''' + JS(lS, 'tool') + ''' is not in HandleToolsList (nearest: ' + JoinS(NearestCandidates(JS(lS, 'tool'), FLive.McpTools), ', ') + ')');
        end
        else if SameText(lT, 'ide-context') then
        begin
          lH := JS(lS, 'host');
          lK := LeafKey(lS);
          if not FLive.ContextCaptions.ContainsKey(lH) then
            Fail('C', lId + ': ide-context host ''' + lH + ''' has no live harvest (harvested hosts: ' + JoinS(FLive.ContextHosts, ', ')
              + ') -- teach Get-LiveSurface to read that host''s menu before registering against it')
          else
          begin
            lHostKeys := nil;
            for lCap in FLive.ContextCaptions[lH] do
              lHostKeys := lHostKeys + [CaptionKey(lCap)];
            if not RegistryCaptionMatch(lK, lHostKeys) then
              Fail('C', lId + ': ide-context ''' + JS(lS, 'caption') + ''' is not on the ' + lH + ' context menu (nearest: '
                + JoinS(NearestCaption(lK, FLive.ContextCaptions[lH]), ' | ') + ') -- the usual cause is a renamed item: update the entry');
          end;
        end
        else if InCI(lT, ['ide-menu', 'ide-about', 'tool-window']) then
        begin
          lK := LeafKey(lS);
          if not RegistryCaptionMatch(lK, (if SameText(lT, 'ide-about') then lAboutKeys else lLiveKeys)) then
          begin
            lWhere := (if JHas(lS, 'path') then JS(lS, 'path') else JS(lS, 'caption'));
            Fail('C', lId + ': ' + lT + ' ''' + lWhere + ''' matches no live caption (nearest: ' + JoinS(NearestCaption(lK, FLive.Captions), ' | ')
              + ') -- the usual cause is a renamed or moved menu item: tools\feature-registry.ps1 move-menu, or update the entry');
          end;
        end;
      end;
    end;
  finally
    lRegCtx.Free;
    lRegMcp.Free;
    lRegExes.Free;
    lRegSubs.Free;
    lRegVerbs.Free;
  end;
end;

procedure TChecker.CheckBacklog(const pCtx: TCheckContext);
var
  lFile, lBid, lTeamName: string;
  lRoot: TJSONObject;
  lP: TJSONPair;
  lStems: TArray<string>;
  lE: TRawEntry;
  lBe: TJSONObject;
  lRemaining, i: Integer;
  lOwed: Boolean;
begin
  lFile := TPath.Combine(FRepo, 'features\seed-backlog.json');
  if not TFile.Exists(lFile) then
    Exit;
  lStems := nil;
  for lE in pCtx.Entries do
    lStems := lStems + [lE.Stem];
  lRoot := ReadJsonObject(lFile);
  try
    if JVal(lRoot, 'teams') is not TJSONObject then
      Exit;
    for lP in TJSONObject(JVal(lRoot, 'teams')) do
    begin
      lTeamName := lP.JsonString.Value;
      lRemaining := 0;
      if lP.JsonValue is TJSONArray then
        for i := 0 to TJSONArray(lP.JsonValue).Count - 1 do
        begin
          lBid := ItemText(TJSONArray(lP.JsonValue).Items[i]);
          lBe := nil;
          for lE in pCtx.Entries do
            if SameText(lE.Stem, lBid) then
              lBe := lE.Entry;
          if lBe = nil then
          begin
            Fail('A', 'seed-backlog.json: ''' + lBid + ''' (' + lTeamName + ') is not an entry (nearest: '
              + JoinS(NearestCandidates(lBid, lStems), ', ') + ') -- delete it from the backlog');
            Continue;
          end;
          lOwed := not JHas(lBe, 'intro') or not JHas(lBe, 'lastVerified') or (JS(lBe, 'since') = '0.0.0');
          if lOwed then
            Inc(lRemaining)
          else
            Fail('A', 'seed-backlog.json: ''' + lBid + ''' now has intro, lastVerified and a real since -- delete it from the backlog (the list is a debt, not a suppression)');
        end;
      FNotes.Add(Format('backlog: %s %d remaining (intro + lastVerified owed; deadline: %s)', [lTeamName, lRemaining, JS(lRoot, 'deadline')]));
    end;
  finally
    lRoot.Free;
  end;
end;

procedure TChecker.CheckGenerated;
var
  lW: TOutputWriter;
  lRes: TOutputResult;
  lC, lKey, lOld, lFile: string;
begin
  try
    lW := TOutputWriter.Create(FRepo, True, False);
    try
      BuildWiki(FRepo, lW, FLive.Engine);
      lRes := lW.Finish;
      for lC in lRes.Changed do
      begin
        lKey := lC.Split([#13#10])[0];
        // D covers the outputs the PowerShell generator owns (WikiOutputPaths);
        // cli-reference.md is guarded by "build --check".
        if not InCI(lKey, WikiOutputPaths) then
          Continue;
        lFile := TPath.Combine(FRepo, lKey);
        lOld := (if TFile.Exists(lFile) then TEncoding.ASCII.GetString(TFile.ReadAllBytes(lFile)) else '');
        Fail('D', lKey + ' differs from a fresh render -- run tools\build-feature-pages.ps1 and commit (or revert the hand edit)'#10
          + Indent3(DiffHead(lOld, lW.TextOf(lKey).Replace(#10, #13#10))));
      end;
    finally
      lW.Free;
    end;
  except
    on E: Exception do
      Fail('D', 'generator: ' + E.Message);
  end;
end;

procedure TChecker.CheckStale(const pHand: TArray<TJSONObject>);
var
  lE: TJSONObject;
  lF: TFamilyDef;
  lD, lOldest: TDateTime;
  lCount: Integer;
  lOldestId: string;

  procedure Consider(const pId: string; const pLv: TJSONValue);
  begin
    if not TryIsoDate(JS(pLv, 'date'), lD) then
      Exit;
    if Date - lD > STALE_DAYS then
    begin
      Inc(lCount);
      if (lOldestId = '') or (lD < lOldest) or ((Trunc(lD) = Trunc(lOldest)) and (AnsiCompareText(pId, lOldestId) < 0)) then
      begin
        lOldest := lD;
        lOldestId := pId;
      end;
    end;
  end;

begin
  lCount := 0;
  lOldestId := '';
  lOldest := 0;
  for lE in pHand do
    if JHas(lE, 'lastVerified') then
      Consider(JS(lE, 'id'), JVal(lE, 'lastVerified'));
  for lF in FFamilies do
    Consider('family:' + lF.Name, JVal(lF.Def, 'lastVerified'));
  if lCount > 0 then
    FNotes.Add(Format('stale: %d entries older than 90 days, oldest %s (%s) -- the periodic review''s input, not a failure',
      [lCount, lOldestId, FormatDateTime('yyyy-mm-dd', lOldest)]));
end;

procedure TChecker.Run;
var
  lCtx: TCheckContext;
  lE: TRawEntry;
  lHome: TDictionary<Integer, string>;
  lHo: Integer;
  lCanon, lAsc, lF, lPr, lOwner: string;
  lFiles: TArray<string>;
  lFam: TFamilyDef;
  lHand: TArray<TJSONObject>;
  lX: TJSONObject;
  lIds: TArray<string>;
  lC: TJSONObject;
  lFull: TCheckContext;
  lFirst: Integer;
  i: Integer;
begin
  // ---- A. well-formed
  if not TDirectory.Exists(TPath.Combine(FRepo, 'features\entries')) then
    Fail('A', TPath.Combine(FRepo, 'features\entries') + ' does not exist');
  try
    lCtx := TCheckContext.Create(FRepo, nil);
  except
    on E: Exception do
    begin
      Fail('A', 'cannot load the registry: ' + E.Message);
      Exit;
    end;
  end;
  try
    for lPr in GroupsAndTeams(lCtx) do
      Fail('A', lPr);
    lHome := TDictionary<Integer, string>.Create;
    try
      for lE in lCtx.Entries do
      begin
        lCanon := CanonicalJson(lE.Entry, lCtx.KeyOrder);
        if lCanon <> lE.Raw then
        begin
          lFirst := Min(Length(lCanon), Length(lE.Raw));
          for i := 1 to Min(Length(lCanon), Length(lE.Raw)) do
            if lCanon[i] <> lE.Raw[i] then
            begin
              lFirst := i - 1;
              Break;
            end;
          Fail('A', Format('%s: not canonical (first difference at byte %d); run tools\feature-registry.ps1 normalise', [lE.Path, lFirst]));
        end;
        if JHas(lE.Entry, 'homeOrder') then
        begin
          lHo := StrToIntDef(JS(lE.Entry, 'homeOrder'), 0);
          if lHome.TryGetValue(lHo, lOwner) then
            Fail('A', Format('%s.json: homeOrder %d is also used by %s', [lE.Stem, lHo, lOwner]))
          else
            lHome.Add(lHo, lE.Stem);
        end;
      end;
    finally
      lHome.Free;
    end;
    lFiles := SortedFiles(TPath.Combine(FRepo, 'features\templates'), '*')
      + [TPath.Combine(FRepo, 'features\related-projects.json'), TPath.Combine(FRepo, 'features\exemptions.json'), TPath.Combine(FRepo, 'features\seed-backlog.json')]
      + SortedFiles(TPath.Combine(FRepo, 'features\families'), '*.json');
    for lF in lFiles do
      if TFile.Exists(lF) then
      begin
        lAsc := AsciiCrlfProblem(lF);
        if lAsc <> '' then
          Fail('A', lAsc);
      end;
    for lF in SortedFiles(TPath.Combine(FRepo, 'features\families'), '*.json') do
      try
        lFam.Name := TPath.GetFileNameWithoutExtension(lF);
        lFam.Path := lF;
        lFam.Def := ReadFamilyDefinition(lF, lCtx);
        FFamilies.Add(lFam);
      except
        on E: Exception do
          Fail('A', E.Message);
      end;
    if FLevel = clWellFormed then
    begin
      for lE in lCtx.Entries do
        for lPr in CheckEntry(lE.Entry, lCtx, lE.Stem) do
          Fail('A', lPr);
      for lX in FExtra do
        for lPr in CheckEntry(lX, lCtx, JS(lX, 'id')) do
          Fail('A', lPr);
      Exit;
    end;
    // ---- Full: live surface + family children
    if FLive = nil then
    begin
      Fail('B', 'live surface: no live surface was harvested');
      Exit;
    end;
    if FLive.HarvestError <> '' then
    begin
      Fail('B', 'live surface: ' + FLive.HarvestError);
      Exit;
    end;
    lHand := nil;
    for lE in lCtx.Entries do
      lHand := lHand + [lE.Entry];
    lHand := lHand + FExtra;
    ImportChildren(lHand);
    lIds := nil;
    for lX in lHand do
      lIds := lIds + [JS(lX, 'id')];
    for lC in FChildren do
      lIds := lIds + [JS(lC, 'id')];
    lFull := TCheckContext.Create(FRepo, lIds);
    try
      for lX in lHand do
        for lPr in CheckEntry(lX, lFull, JS(lX, 'id')) do
          Fail('A', lPr);
      CheckLive(lHand, lFull);
      CheckBacklog(lFull);
    finally
      lFull.Free;
    end;
    if not FSkipGenerated then
      CheckGenerated;
    CheckStale(lHand);
  finally
    lCtx.Free;
  end;
end;

{ ---- public ---- }

function RunChecks(const pReg: TRegistry; const pLive: TLiveSurface; pLevel: TCheckLevel; const pExtraEntries: TArray<TJSONObject>;
  pSkipGenerated: Boolean; out pNotes: TArray<string>): TArray<TFinding>;
var
  lC: TChecker;
begin
  if (pReg = nil) or (pReg.Root = '') then
    raise EFeatureGen.Create('RunChecks: the registry has no root (call Load first)');
  lC := TChecker.Create(pReg.Root, pLive, pLevel, pExtraEntries, pSkipGenerated);
  try
    lC.Run;
    Result := lC.Findings;
    pNotes := lC.Notes;
  finally
    lC.Free;
  end;
end;

function RunChecks(const pReg: TRegistry; const pLive: TLiveSurface; pLevel: TCheckLevel): TArray<TFinding>;
var
  lNotes: TArray<string>;
begin
  Result := RunChecks(pReg, pLive, pLevel, nil, False, lNotes);
end;

function RunCheckCommand(const pRepo, pEngine: string; pLevel: TCheckLevel; out pNotes: TArray<string>): TArray<TFinding>;
var
  lReg: TRegistry;
  lLive: TLiveSurface;
begin
  lReg := TRegistry.Create;
  lLive := nil;
  try
    try
      lReg.Load(pRepo);
    except
      // reported as check A by the context load inside RunChecks
    end;
    if pLevel = clFull then
    begin
      lLive := TLiveSurface.Create;
      try
        lLive.Harvest(pRepo, pEngine);
      except
        on E: Exception do
          lLive.HarvestError := E.Message;
      end;
    end;
    Result := RunChecks(lReg, lLive, pLevel, nil, False, pNotes);
  finally
    lLive.Free;
    lReg.Free;
  end;
end;

function FindingText(const pFinding: TFinding): string;
begin
  Result := pFinding.Check + ': ' + pFinding.Text;
end;

end.
