unit FeatureGen.Wiki;

{ The ported wiki outputs (spec 5.1), byte-identical to tools\FeatureRegistry.psm1
  (Get-RegistryModel, the two family importers, Render-* and Update-MarkedBlock),
  plus features\generated\cli-reference.md (spec 5.3).
  Entries and family children are held as canonical JSON objects (the shape the
  manifest writes), not as TFeatureEntry records: the manifest must reproduce the
  PowerShell key order and value shapes byte-for-byte.
  String comparisons follow the PowerShell operator used: -eq / -in / -contains are
  case-insensitive (SameText), Sort-ByOrdinalKey / Sort-OrdinalUnique are ordinal
  (CompareStr). The importers' validation that never changes an output (the chart
  ValidateSet and emitter-set drift checks, Test-FeatureEntry on children) stays in
  the PowerShell check and is not ported here. }

interface

uses
  System.SysUtils
  , System.JSON
  , FeatureGen.Output
  ;

/// <summary>The seven ported outputs of spec 5.1, repo-relative, in the PowerShell generator's order.</summary>
/// <returns>docs\wiki\Home.md, Features.md, Feature-Index.md, Quick-Help.md, README.md,
/// docs\AI-USAGE.md, features\generated\manifest.json.</returns>
function WikiOutputPaths: TArray<string>;

/// <summary>Renders every wiki output into pWriter.</summary>
/// <param name="pRepo">Repository root (holds features\, docs\, README.md).</param>
/// <param name="pWriter">Receives the seven outputs of WikiOutputPaths plus
/// features\generated\cli-reference.md; construct it with pOwnsRoot=False (the
/// outputs live among tracked files).</param>
/// <param name="pEngine">Full path of drag-lint.exe ("rules --json" and "--help");
/// '' = pRepo\third_party\dll-win64\drag-lint.exe, the PowerShell generator's default.</param>
/// <exception cref="EFeatureGen">A template, family definition, marker pair or
/// harvested source is missing or inconsistent, or the engine is not found.</exception>
/// <remarks>README.md and docs\AI-USAGE.md are read from pRepo and only their marked
/// block is replaced, also when pWriter's root is elsewhere.</remarks>
procedure BuildWiki(const pRepo: string; const pWriter: TOutputWriter; const pEngine: string = '');

/// <summary>Replaces the body of a dl:registry marked block (Update-MarkedBlock).</summary>
/// <param name="pText">Whole file text.</param>
/// <param name="pName">Block name; markers are &lt;!-- dl:registry:begin NAME --&gt; and &lt;!-- dl:registry:end NAME --&gt;.</param>
/// <param name="pBody">New body; it should end with CRLF.</param>
/// <returns>pText up to and including the begin marker, CRLF, pBody, then pText from the end marker on.</returns>
/// <exception cref="EFeatureGen">Either marker is absent, or end comes before begin (never appends blindly).</exception>
function UpdateMarkedBlock(const pText, pName, pBody: string): string;

/// <summary>The family children (rule.*, chart.*) the importers derive for a set of hand entries.</summary>
/// <param name="pRepo">Repository root (features\families, the plugin's ReportText.pas).</param>
/// <param name="pEntries">Hand entries; read only (cloned).</param>
/// <param name="pRules">The parsed "rules --json" output; read only (cloned).</param>
/// <param name="pKeyOrder">Canonical entry key order (entry.schema.json).</param>
/// <returns>New canonical child objects, lint-rules first then chart-questions, each in importer
/// order. The caller owns and must Free every element.</returns>
/// <exception cref="EFeatureGen">A family definition or harvested source is missing or inconsistent.</exception>
/// <remarks>Same derivation as the generator; the validation that never changes an output
/// (chart ValidateSet, emitter drift, child entry checks) is the caller's (FeatureGen.Check).</remarks>
function ImportFamilyChildren(const pRepo: string; const pEntries: TArray<TJSONObject>; const pRules: TJSONValue;
  const pKeyOrder: TArray<string>): TArray<TJSONObject>;

/// <summary>Reads a file that must be 7-bit ASCII.</summary>
/// <param name="pPath">File to read.</param>
/// <returns>The file text, unchanged.</returns>
/// <exception cref="EFeatureGen">A byte above 127; the message names the file and the 0-based byte offset.</exception>
/// <remarks>Never maps a non-ASCII byte to '?': README.md / AI-USAGE.md are rewritten from this text.</remarks>
function ReadAsciiStrict(const pPath: string): string;

implementation

uses
  System.Classes
  , System.IOUtils
  , System.RegularExpressions
  , System.StrUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  , FeatureGen.Json
  , FeatureGen.Model
  , FeatureGen.Live
  , FeatureGen.SiteFormat
  , FeatureGen.Site
  , FeatureGen.HelpText
  ;

const
  CRLF = #13#10;
  WIKI_URL = 'https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/';
  FAMILY_LINT = 'lint-rules';
  FAMILY_CHART = 'chart-questions';
  SUMMARY_MAX = 160;
  SUMMARY_MIN = 20;
  CHART_ID_PREFIX = 'chart.';
  ELLIPSIS = '...';
  ASCII_MAX = 127;
  RE_GROUP_KIND = 3; // (Id)(Caption)(Kind) in the REPORT_QUESTIONS row regex
  SECTION_CLI = 3; // index of 'CLI verbs' in the Feature-Index sections; it and later sections join with ', '
  GENERATED_BY = '*Generated by `featuregen build --all` from `features\`; do not edit by hand.*' + CRLF;

type
  TWikiModel = class
  public
    Entries: TObjectList<TJSONObject>;  // dl:ok public-field@3837 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    FamilyNames: TList<string>;  // dl:ok public-field@8c13 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    Children: TObjectDictionary<string, TObjectList<TJSONObject>>;  // dl:ok public-field@a649 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    GroupsRoot: TJSONValue;  // dl:ok public-field@5f52 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    Groups: TArray<TJSONObject>;  // dl:ok public-field@4fca -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    TeamsRoot: TJSONValue;  // dl:ok public-field@fdf5 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    RelatedRoot: TJSONValue;  // dl:ok public-field@4e9d -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    Rules: TJSONValue;  // dl:ok public-field@1bd0 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    Product, Extractor, Resolver, Schema: string;  // dl:ok public-field@bdb1 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    HomeIntro, FeaturesIntro, QuickIntro: string;  // dl:ok public-field@a9ad -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    constructor Create;
    destructor Destroy; override;
  end;

constructor TWikiModel.Create;
begin
  inherited Create;
  Entries := TObjectList<TJSONObject>.Create(True);
  FamilyNames := TList<string>.Create;
  Children := TObjectDictionary<string, TObjectList<TJSONObject>>.Create([doOwnsValues]);
end;

destructor TWikiModel.Destroy;
begin
  Rules.Free;
  RelatedRoot.Free;
  TeamsRoot.Free;
  GroupsRoot.Free;
  Children.Free;
  FamilyNames.Free;
  Entries.Free;
  inherited;  // dl:ok inherited-bare@246d -- REVIEWED 2026-10-19: the direct ancestor method is the intended one
end;

{ ---- JSON helpers ---- }

function Str(const pObj: TJSONValue; const pKey: string): string;
begin
  Result := Prop(pObj, pKey);
end;

function Has(const pObj: TJSONObject; const pKey: string): Boolean;
begin
  Result := pObj.GetValue(pKey) <> nil;
end;

function IsTrue(const pObj: TJSONValue; const pKey: string): Boolean;
var
  lV: TJSONValue;
begin
  Result := False;
  if pObj is TJSONObject then
  begin
    lV := TJSONObject(pObj).GetValue(pKey);
    Result := (lV is TJSONBool) and TJSONBool(lV).AsBoolean;
  end;
end;

{ Get-EntryList: an array's items; a scalar reads as one item; absent reads empty. }
function Items(const pObj: TJSONValue; const pKey: string): TArray<TJSONValue>;
var
  lV: TJSONValue;
  i: Integer;
begin
  Result := nil;
  if pObj is not TJSONObject then
    Exit;
  lV := TJSONObject(pObj).GetValue(pKey);
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

function Strings(const pObj: TJSONValue; const pKey: string): TArray<string>;
var
  lItems: TArray<TJSONValue>;
  i: Integer;
begin
  lItems := Items(pObj, pKey);
  SetLength(Result, Length(lItems));
  for i := 0 to High(lItems) do
    Result[i] := lItems[i].Value;
end;

function Objects(const pObj: TJSONValue; const pKey: string): TArray<TJSONObject>;
var
  lItem: TJSONValue;
  lList: TList<TJSONObject>;
begin
  lList := TList<TJSONObject>.Create;
  try
    for lItem in Items(pObj, pKey) do
      if lItem is TJSONObject then
        lList.Add(TJSONObject(lItem));
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function IsEmptyJson(const pV: TJSONValue): Boolean;
begin
  Result := (pV = nil) or (pV is TJSONNull)  // dl:ok boolean-expression-complexity@0115 -- REVIEWED 2026-10-19: ported predicate with one operand per source condition; splitting it would hide the 1:1 port the parity tests compare
    or ((pV is TJSONString) and (TJSONString(pV).Value = ''))
    or ((pV is TJSONArray) and (TJSONArray(pV).Count = 0));
end;

function ReadObject(const pPath: string): TJSONObject;
var
  lV: TJSONValue;
begin
  lV := ReadJsonFile(pPath);
  if lV is not TJSONObject then
  begin
    lV.Free;
    raise EFeatureGen.CreateFmt('%s: not a JSON object', [pPath]);
  end;
  Result := TJSONObject(lV);
end;

{ ConvertTo-CanonicalEntry, as a fresh object whose pair order is the canonical order. }
function Canonicalise(const pObj: TJSONValue; const pOrder: TArray<string>): TJSONObject;
var
  lV: TJSONValue;
begin
  lV := TJSONObject.ParseJSONValue(CanonicalJson(pObj, pOrder), False, True);
  Result := lV as TJSONObject;
end;

function ReadAsciiStrict(const pPath: string): string;
var
  lBytes: TBytes;
  i: Integer;
begin
  lBytes := TFile.ReadAllBytes(pPath);
  for i := 0 to High(lBytes) do
    if lBytes[i] > ASCII_MAX then
      raise EFeatureGen.CreateFmt('%s: non-ASCII byte 0x%.2X at byte offset %d', [pPath, lBytes[i], i]);
  Result := TEncoding.ASCII.GetString(lBytes);
end;

{ Sort-ByOrdinalKey: items reordered by their ordinal keys. }
function SortByKeys(const pItems: TArray<TJSONObject>; const pKeys: TArray<string>): TArray<TJSONObject>;
var
  lIdx: TArray<Integer>;
  lKeys: TArray<string>;
  i: Integer;
begin
  lKeys := pKeys;
  SetLength(lIdx, Length(pItems));  // dl:ok duplicate-code@4cf8 -- REVIEWED 2026-10-19: parallel ported renderers share a shape; extracting a helper would couple outputs that must stay independent
  for i := 0 to High(lIdx) do
    lIdx[i] := i;
  TArray.Sort<Integer>(lIdx, TComparer<Integer>.Construct(
    function(const pA, pB: Integer): Integer
    begin
      Result := CompareStr(lKeys[pA], lKeys[pB]);
      if Result = 0 then
        Result := pA - pB;
    end));
  SetLength(Result, Length(pItems));
  for i := 0 to High(lIdx) do
    Result[i] := pItems[lIdx[i]];
end;

{ Sort-OrdinalUnique. }
function SortedUnique(const pItems: TArray<string>): TArray<string>;
var
  lSet: TList<string>;
  lS: string;
begin
  lSet := TList<string>.Create;
  try
    for lS in pItems do
      if not lSet.Contains(lS) then
        lSet.Add(lS);
    Result := lSet.ToArray;
  finally
    lSet.Free;
  end;
  TArray.Sort<string>(Result, TStringComparer.Ordinal);
end;

function InList(const pValue: string; const pList: array of string): Boolean;
var
  lS: string;
begin
  Result := False;
  for lS in pList do
    if SameText(pValue, lS) then
      Exit(True);
end;

function Join(const pItems: TArray<string>; const pSep: string): string;
begin
  Result := string.Join(pSep, pItems);
end;

{ ---- model ---- }

function FirstGroup(const pRe: string; const pText: string): string;
var
  lM: TMatch;
begin
  lM := TRegEx.Match(pText, pRe);
  Result := (if lM.Success then lM.Groups[1].Value else '');
end;

{ Get-OverrideValue: the child override when non-empty, else the family default when non-empty, else nil. }
function OverrideValue(const pDef: TJSONObject; const pChildId, pKey: string): TJSONValue;
var
  lCh, lOv, lDf, lV: TJSONValue;
begin
  lCh := pDef.GetValue('children');
  if lCh is TJSONObject then
  begin
    lOv := TJSONObject(lCh).GetValue(pChildId);
    if lOv is TJSONObject then
    begin
      lV := TJSONObject(lOv).GetValue(pKey);
      if not IsEmptyJson(lV) then
        Exit(lV);
    end;
  end;
  lDf := pDef.GetValue('defaults');
  if lDf is TJSONObject then
  begin
    lV := TJSONObject(lDf).GetValue(pKey);
    if not IsEmptyJson(lV) then
      Exit(lV);
  end;
  Result := nil;
end;

function OverrideStr(const pDef: TJSONObject; const pChildId, pKey, pFallback: string): string;
var
  lV: TJSONValue;
begin
  lV := OverrideValue(pDef, pChildId, pKey);
  if lV = nil then
    Result := pFallback
  else
    Result := lV.Value;
end;

{ @(Get-OverrideValue ... @()) as a new array (scalar -> one element). }
function OverrideArray(const pDef: TJSONObject; const pChildId, pKey: string): TJSONArray;
var
  lV: TJSONValue;
  i: Integer;
begin
  Result := TJSONArray.Create;
  lV := OverrideValue(pDef, pChildId, pKey);
  if lV is TJSONArray then
  begin
    for i := 0 to TJSONArray(lV).Count - 1 do
      Result.AddElement(TJSONArray(lV).Items[i].Clone as TJSONValue);
  end
  else if lV <> nil then
    Result.AddElement(lV.Clone as TJSONValue);
end;

function ChildIds(const pDef: TJSONObject): TArray<string>;
var
  lCh: TJSONValue;
  i: Integer;
begin
  Result := nil;
  lCh := pDef.GetValue('children');
  if lCh is not TJSONObject then
    Exit;
  SetLength(Result, TJSONObject(lCh).Count);
  for i := 0 to TJSONObject(lCh).Count - 1 do
    Result[i] := TJSONObject(lCh).Pairs[i].JsonString.Value;
end;

function Surface(const pPairs: array of string): TJSONObject;
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

{ Limit-Summary. }
function LimitSummary(const pText, pSuffix: string): string;
var
  lT: string;
  lMax: Integer;
begin
  lT := pText.TrimRight(['.', ' ']);
  lMax := SUMMARY_MAX - Length(pSuffix);
  if Length(lT) > lMax then
    lT := Copy(lT, 1, lMax - Length(ELLIPSIS)).TrimRight + ELLIPSIS;
  Result := lT + pSuffix;
  if Length(Result) < SUMMARY_MIN then
    Result := Result + ' (lint rule)';
end;

function RuleList(const pM: TWikiModel): TArray<TJSONObject>;
begin
  Result := Objects(pM.Rules, 'rules');
end;

function RuleSummary(const pM: TWikiModel): TJSONValue;
begin
  Result := TJSONObject(pM.Rules).GetValue('summary');
end;

procedure ImportLintRules(const pM: TWikiModel; const pDef, pParent: TJSONObject; const pOrder: TArray<string>;
  const pKids: TObjectList<TJSONObject>);
var
  lRules: TArray<TJSONObject>;
  lById: TDictionary<string, TJSONObject>;
  lIds: TArray<string>;
  lR: TJSONObject;
  lC: TJSONObject;
  lSurfaces: TJSONArray;
  lId, lSuffix: string;
  i: Integer;
begin
  lRules := RuleList(pM);
  if Length(lRules) = 0 then
    raise EFeatureGen.Create('lint-rules importer: 0 rules harvested');
  if IntToStr(Length(lRules)) <> Str(RuleSummary(pM), 'total') then
    raise EFeatureGen.CreateFmt('lint-rules importer: %d rule rows vs summary.total %s', [Length(lRules), Str(RuleSummary(pM), 'total')]);
  lById := TDictionary<string, TJSONObject>.Create;
  try
    SetLength(lIds, Length(lRules));
    for i := 0 to High(lRules) do
    begin
      lIds[i] := Str(lRules[i], 'id');
      lById.AddOrSetValue(lIds[i], lRules[i]);
    end;
    for lId in ChildIds(pDef) do
      if not lById.ContainsKey(lId) then
        raise EFeatureGen.CreateFmt('lint-rules importer: override ''%s'' names a rule that no longer exists in rules --json', [lId]);
    for lId in SortedUnique(lIds) do
    begin
      lR := lById[lId];
      lSuffix := ' (' + Str(lR, 'category') + ', ' + Str(lR, 'default_severity') + (if IsTrue(lR, 'fixable') then ', fixable' else '') + ')';
      lC := TJSONObject.Create;
      try
        lC.AddPair('id', 'rule.' + lId);
        lC.AddPair('title', lId);
        lC.AddPair('group', 'linting');
        lC.AddPair('owner', Str(pParent, 'owner'));
        lC.AddPair('status', 'shipped');
        lC.AddPair('since', OverrideStr(pDef, lId, 'since', Str(pParent, 'since')));
        lC.AddPair('summary', LimitSummary(Str(lR, 'title'), lSuffix));
        lC.AddPair('wikiPage', OverrideStr(pDef, lId, 'wikiPage', 'rules'));
        lSurfaces := TJSONArray.Create;
        lSurfaces.AddElement(Surface(['type', 'cli', 'verb', 'lint', 'example', 'drag-lint lint <file.pas> --rule ' + lId]));
        lC.AddPair('surfaces', lSurfaces);
        lC.AddPair('audience', 'both');
        lC.AddPair('aliases', OverrideArray(pDef, lId, 'aliases'));
        lC.AddPair('related', OverrideArray(pDef, lId, 'related'));
        lC.AddPair('notes', OverrideStr(pDef, lId, 'notes', ''));
        lC.AddPair('parent', Str(pParent, 'id'));
        lC.AddPair('wikiAnchor', lId);
        pKids.Add(Canonicalise(lC, pOrder));
      finally
        lC.Free;
      end;
    end;
  finally
    lById.Free;
  end;
end;

procedure ImportChartQuestions(const pRepo: string; const pDef, pParent: TJSONObject; const pOrder: TArray<string>;
  const pKids: TObjectList<TJSONObject>);
var
  lRt, lQid, lCaption, lKind, lTitle, lEmitter, lSub, lPrefix, lElse: string;
  lMatches: TMatchCollection;
  lM: TMatch;
  lCaps: TDictionary<string, string>;
  lIds: TList<string>;
  lC: TJSONObject;
  lSurfaces: TJSONArray;
  lHome: TJSONValue;
  lCount: Integer;
begin
  lRt := TFile.ReadAllText(TPath.Combine(pRepo, 'src\delphi-plugin\DragLint.Plugin.ReportText.pas'));
  lMatches := TRegEx.Matches(lRt, '\(Id:\s*''([a-z-]+)''\s*;\s*Caption:\s*''([^'']+)''\s*;\s*Kind:\s*(rtk\w+)\s*\)');
  if lMatches.Count = 0 then
    raise EFeatureGen.Create('chart-questions importer: 0 questions harvested from REPORT_QUESTIONS');
  lCount := StrToIntDef(FirstGroup('REPORT_QUESTION_COUNT\s*=\s*(\d+)', lRt), -1);
  if lCount < 0 then
    raise EFeatureGen.Create('chart-questions importer: REPORT_QUESTION_COUNT not found');
  if lMatches.Count <> lCount then
    raise EFeatureGen.CreateFmt('chart-questions importer: %d catalog rows vs REPORT_QUESTION_COUNT = %d', [lMatches.Count, lCount]);
  lCaps := TDictionary<string, string>.Create;
  lIds := TList<string>.Create;
  try
    for lM in TRegEx.Matches(lRt, '\b(rtk\w+)\s*:\s*Result\s*:=\s*''([^'']+)''') do
      lCaps.AddOrSetValue(lM.Groups[1].Value, lM.Groups[2].Value.Replace('&&', '&'));
    lElse := FirstGroup('(?s)function ReportGroupCaption\b(?:(?!\b(?:function|procedure)\b).)*?\belse\s+Result\s*:=\s*''([^'']+)''\s*;\s*end;', lRt);
    for lM in lMatches do
    begin
      lIds.Add(lM.Groups[1].Value);
      if (lElse <> '') and not lCaps.ContainsKey(lM.Groups[RE_GROUP_KIND].Value) then
        lCaps.Add(lM.Groups[RE_GROUP_KIND].Value, lElse.Replace('&&', '&'));
    end;
    for lQid in ChildIds(pDef) do
      if not lIds.Contains(lQid) then
        raise EFeatureGen.CreateFmt('chart-questions importer: override ''%s'' names a question that no longer exists', [lQid]);
    for lM in lMatches do
    begin
      lQid := lM.Groups[1].Value;
      lCaption := lM.Groups[2].Value.Replace('&&', '&');
      lKind := lM.Groups[RE_GROUP_KIND].Value;
      lTitle := TRegEx.Replace(lCaption, '\.\.\.$', '').Trim;
      lEmitter := OverrideStr(pDef, lQid, 'emitter', '');
      if not lCaps.TryGetValue(lKind, lSub) then
        raise EFeatureGen.CreateFmt('chart-questions importer: no ReportGroupCaption for Kind %s', [lKind]);
      lPrefix := OverrideStr(pDef, lQid, 'menuPrefix', 'drag-lint > Reports');
      lC := TJSONObject.Create;
      try
        lC.AddPair('id', CHART_ID_PREFIX + lQid);
        lC.AddPair('title', lTitle);
        lC.AddPair('group', 'diagrams-charts');
        lC.AddPair('owner', 'CHARTS');
        lC.AddPair('status', 'shipped');
        lC.AddPair('since', OverrideStr(pDef, lQid, 'since', Str(pParent, 'since')));
        lC.AddPair('summary', lTitle + ' -- chart question (' + lSub + ')');
        lC.AddPair('wikiPage', OverrideStr(pDef, lQid, 'wikiPage', 'ask-' + lQid));
        lSurfaces := TJSONArray.Create;
        lSurfaces.AddElement(Surface(['type', 'ide-menu', 'path', lPrefix + ' > ' + lCaption]));
        lSurfaces.AddElement(Surface(['type', 'script', 'path', 'charts\src\Ask-Report.ps1', 'args', '-Question ' + lQid]));
        lSurfaces.AddElement(Surface(['type', 'script', 'path', 'charts\src\New-DiagramArtifact.ps1', 'args', '-Question ' + lQid]));
        lC.AddPair('surfaces', lSurfaces);
        lC.AddPair('audience', 'both');
        lC.AddPair('requires', OverrideArray(pDef, lQid, 'requires'));
        lC.AddPair('aliases', OverrideArray(pDef, lQid, 'aliases'));
        lC.AddPair('related', OverrideArray(pDef, lQid, 'related'));
        lC.AddPair('notes', OverrideStr(pDef, lQid, 'notes', ''));
        lC.AddPair('tests', OverrideArray(pDef, lQid, 'tests'));
        lC.AddPair('parent', Str(pParent, 'id'));
        lC.AddPair('subgroup', lSub);
        lC.AddPair('emitter', lEmitter);
        lHome := OverrideValue(pDef, lQid, 'homeOrder');
        if lHome <> nil then
          lC.AddPair('homeOrder', TJSONNumber.Create(StrToInt(lHome.Value)));
        pKids.Add(Canonicalise(lC, pOrder));
      finally
        lC.Free;
      end;
    end;
  finally
    lIds.Free;
    lCaps.Free;
  end;
end;

{ Get-RegistryChildren, minus the validation that never changes an output. }
procedure LoadChildren(const pRepo: string; const pM: TWikiModel; const pKeyOrder: TArray<string>);
var
  lDir, lFam, lFile: string;
  lDefs: TList<string>;
  lE, lParent: TJSONObject;
  lDef: TJSONObject;
  lOrder: TArray<string>;
  lKids: TObjectList<TJSONObject>;
  lFound: Integer;
begin
  if pM.Entries.Count = 0 then
    Exit;
  lOrder := pKeyOrder + ['parent', 'subgroup', 'emitter', 'wikiAnchor'];
  lDir := TPath.Combine(pRepo, 'features\families');
  lDefs := TList<string>.Create;
  try
    if TDirectory.Exists(lDir) then
      for lFile in TDirectory.GetFiles(lDir, '*.json') do
        lDefs.Add(TPath.GetFileNameWithoutExtension(lFile));
    for lE in pM.Entries do
      if Has(lE, 'family') and not lDefs.Contains(Str(lE, 'family')) then
        raise EFeatureGen.CreateFmt('family ''%s'' (entry ''%s'') has no features\families\%s.json', [Str(lE, 'family'), Str(lE, 'id'), Str(lE, 'family')]);
    for lFam in lDefs do
      if (lFam <> FAMILY_LINT) and (lFam <> FAMILY_CHART) then
        raise EFeatureGen.CreateFmt('features\families\%s.json has no importer (known: lint-rules, chart-questions)', [lFam]);
    for lFam in [FAMILY_LINT, FAMILY_CHART] do
    begin
      if not lDefs.Contains(lFam) then
        Continue;
      lDef := ReadObject(TPath.Combine(lDir, lFam + '.json'));
      try
        if Str(lDef, 'family') <> lFam then
          raise EFeatureGen.CreateFmt('features\families\%s.json declares family ''%s''; it must equal the file name', [lFam, Str(lDef, 'family')]);
        lParent := nil;
        lFound := 0;
        for lE in pM.Entries do
          if Has(lE, 'family') and (Str(lE, 'id') = Str(lDef, 'entry')) and (Str(lE, 'family') = lFam) then
          begin
            lParent := lE;
            Inc(lFound);
          end;
        if lFound <> 1 then
          raise EFeatureGen.CreateFmt('features\families\%s.json names entry ''%s'', but no hand entry with id ''%s'' and family ''%s'' exists',
            [lFam, Str(lDef, 'entry'), Str(lDef, 'entry'), lFam]);
        lKids := TObjectList<TJSONObject>.Create(True);
        pM.Children.Add(lFam, lKids);
        pM.FamilyNames.Add(lFam);
        if lFam = FAMILY_LINT then
          ImportLintRules(pM, lDef, lParent, lOrder, lKids)
        else
          ImportChartQuestions(pRepo, lDef, lParent, lOrder, lKids);
      finally
        lDef.Free;
      end;
    end;
  finally
    lDefs.Free;
  end;
end;

function ImportFamilyChildren(const pRepo: string; const pEntries: TArray<TJSONObject>; const pRules: TJSONValue;
  const pKeyOrder: TArray<string>): TArray<TJSONObject>;
var
  lM: TWikiModel;
  lE: TJSONObject;
  lFam: string;
  lList: TList<TJSONObject>;
begin
  lList := TList<TJSONObject>.Create;
  lM := TWikiModel.Create;
  try
    for lE in pEntries do
      lM.Entries.Add(lE.Clone as TJSONObject);
    if pRules <> nil then
      lM.Rules := pRules.Clone as TJSONValue;
    LoadChildren(pRepo, lM, pKeyOrder);
    for lFam in lM.FamilyNames do
      for lE in lM.Children[lFam] do
        lList.Add(lE.Clone as TJSONObject);
    Result := lList.ToArray;
  finally
    lM.Free;
    lList.Free;
  end;
end;

function GroupOrderOf(const pM: TWikiModel; const pGroup: string): Integer;
var
  lG: TJSONObject;
begin
  for lG in pM.Groups do
    if Str(lG, 'id') = pGroup then
      Exit(StrToInt(Str(lG, 'order')));
  raise EFeatureGen.CreateFmt('group "%s" is not in groups.json', [pGroup]);
end;

procedure LoadModel(const pRepo, pEngine: string; const pM: TWikiModel);
var
  lFeatures, lFile, lT, lCore, lSchemaPas, lRulesText: string;
  lKeyOrder, lKeys: TArray<string>;
  lFiles: TArray<string>;
  lV: TJSONValue;
  lAll, lSorted: TArray<TJSONObject>;
  lG: TJSONObject;
  i, j: Integer;
begin
  lFeatures := TPath.Combine(pRepo, 'features');
  for lT in ['Home.intro.md', 'Features.intro.md', 'Quick-Help.intro.md'] do
  begin
    lFile := TPath.Combine(lFeatures, 'templates\' + lT);
    if not TFile.Exists(lFile) then
      raise EFeatureGen.CreateFmt('template missing: %s', [lFile]);
    if lT = 'Home.intro.md' then
      pM.HomeIntro := ReadAsciiStrict(lFile)
    else if lT = 'Features.intro.md' then
      pM.FeaturesIntro := ReadAsciiStrict(lFile)
    else
      pM.QuickIntro := ReadAsciiStrict(lFile);
  end;
  if not TFile.Exists(pEngine) then
    raise EFeatureGen.CreateFmt('live surface: engine exe not found: %s', [pEngine]);
  lCore := TFile.ReadAllText(TPath.Combine(pRepo, 'src\core\DRagLint.Core.Model.pas'));
  lSchemaPas := TFile.ReadAllText(TPath.Combine(pRepo, 'src\storage\DRagLint.Storage.Schema.pas'));
  pM.Product := FirstGroup('DRAGLINT_VERSION\s*=\s*''([^'']+)''', lCore);
  pM.Extractor := FirstGroup('DRAGLINT_EXTRACTOR_VERSION\s*=\s*''([^'']+)''', lCore);
  pM.Resolver := FirstGroup('DRAGLINT_RESOLVER_VERSION\s*=\s*''([^'']+)''', lCore);
  pM.Schema := FirstGroup('SCHEMA_VERSION\s*=\s*(\d+)', lSchemaPas);
  if pM.Product = '' then
    raise EFeatureGen.Create('live surface: DRAGLINT_VERSION not found in DRagLint.Core.Model.pas');
  lRulesText := RunCapture(pEngine, 'rules --json');
  pM.Rules := TJSONObject.ParseJSONValue(lRulesText, False, False);
  if (pM.Rules is not TJSONObject) or (StrToIntDef(Str(RuleSummary(pM), 'total'), 0) <= 0) then
    raise EFeatureGen.Create('live surface: rules --json reports total 0');
  // groups: stable by order (Sort-Object { [int]$_.order })
  pM.GroupsRoot := ReadObject(TPath.Combine(lFeatures, 'groups.json'));
  pM.Groups := Objects(pM.GroupsRoot, 'groups');
  for i := 1 to High(pM.Groups) do
  begin
    lG := pM.Groups[i];
    j := i - 1;
    while (j >= 0) and (StrToInt(Str(pM.Groups[j], 'order')) > StrToInt(Str(lG, 'order'))) do
    begin
      pM.Groups[j + 1] := pM.Groups[j];
      Dec(j);
    end;
    pM.Groups[j + 1] := lG;
  end;
  pM.TeamsRoot := ReadObject(TPath.Combine(lFeatures, 'teams.json'));
  pM.RelatedRoot := ReadObject(TPath.Combine(lFeatures, 'related-projects.json'));
  // entries: canonical, sorted by group order | lower(title) | id, ordinal
  lKeyOrder := EntryKeyOrder(TPath.Combine(lFeatures, 'schema\entry.schema.json'));
  lFiles := TDirectory.GetFiles(TPath.Combine(lFeatures, 'entries'), '*.json');
  SetLength(lAll, Length(lFiles));
  SetLength(lKeys, Length(lFiles));
  for i := 0 to High(lFiles) do
  begin
    lV := ReadJsonFile(lFiles[i]);
    try
      lAll[i] := Canonicalise(lV, lKeyOrder);
    finally
      lV.Free;
    end;
    lKeys[i] := Format('%.6d|%s|%s', [GroupOrderOf(pM, Str(lAll[i], 'group')), LowerCase(Str(lAll[i], 'title')), Str(lAll[i], 'id')]);
  end;
  lSorted := SortByKeys(lAll, lKeys);
  for lG in lSorted do
    pM.Entries.Add(lG);
  LoadChildren(pRepo, pM, lKeyOrder);
end;

{ ---- renderers ---- }

function GroupRows(const pM: TWikiModel; const pGroup: TJSONObject): TArray<TJSONObject>;
var
  lE: TJSONObject;
  lList: TList<TJSONObject>;
begin
  lList := TList<TJSONObject>.Create;
  try
    for lE in pM.Entries do
      if SameText(Str(lE, 'group'), Str(pGroup, 'id')) then
        lList.Add(lE);
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function FixableCount(const pM: TWikiModel): Integer;
var
  lR: TJSONObject;
begin
  Result := 0;
  for lR in RuleList(pM) do
    if IsTrue(lR, 'fixable') then
      Inc(Result);
end;

function FamilyCountText(const pM: TWikiModel; const pEntry: TJSONObject): string;
var
  lFam: string;
  lKids: TObjectList<TJSONObject>;
begin
  lFam := Str(pEntry, 'family');
  if not pM.Children.TryGetValue(lFam, lKids) then
    Exit('');
  if SameText(lFam, FAMILY_LINT) then
    Result := Format('%d rules, %d fixable', [lKids.Count, FixableCount(pM)])
  else
    Result := Format('%d questions', [lKids.Count]);
end;

function CliSurface(const pS: TJSONObject): string;
begin
  Result := '`' + Str(pS, 'verb') + (if Has(pS, 'sub') then ' ' + Str(pS, 'sub') else '') + '`';
end;

function SurfaceCell(const pEntry: TJSONObject): string;
var
  lS: TJSONObject;
  lT: string;
  lParts: TList<string>;
begin
  lParts := TList<string>.Create;
  try
    for lS in Objects(pEntry, 'surfaces') do
    begin
      lT := Str(lS, 'type');
      if SameText(lT, 'cli') then
        lParts.Add(CliSurface(lS))
      else if SameText(lT, 'ide-menu') or SameText(lT, 'tool-window') then
        lParts.Add(Str(lS, 'path'))
      else if SameText(lT, 'ide-context') then
        lParts.Add(Str(lS, 'host') + ': ' + Str(lS, 'caption'))
      else if SameText(lT, 'ide-about') then
        lParts.Add('About window: ' + Str(lS, 'caption'))
      else if SameText(lT, 'shortcut') then
        lParts.Add('shortcut ' + Str(lS, 'keys'))
      else if SameText(lT, 'lsp') then
        lParts.Add('`lsp ' + Str(lS, 'method') + '`')
      else if SameText(lT, 'mcp') then
        lParts.Add('`mcp ' + Str(lS, 'tool') + '`')
      else if SameText(lT, 'script') then
        lParts.Add('`' + Str(lS, 'path') + (if Has(lS, 'args') then ' ' + Str(lS, 'args') else '') + '`')
      else if SameText(lT, 'exe') then
        lParts.Add('`' + Str(lS, 'name') + '`' + (if Has(lS, 'menu') then ' (' + Str(lS, 'menu') + ')' else ''))
      else if SameText(lT, 'workflow') then
        lParts.Add('procedure: `' + Str(lS, 'doc') + '`');
    end;
    Result := Join(lParts.ToArray, '; ');
  finally
    lParts.Free;
  end;
end;

function StatusCell(const pEntry: TJSONObject): string;
begin
  Result := (if SameText(Str(pEntry, 'status'), 'shipped') then '' else Str(pEntry, 'status'));
end;

function RenderHome(const pM: TWikiModel): string;
var
  lSb: TStringBuilder;
  lWith: TList<TJSONObject>;
  lKeys: TList<string>;
  lE: TJSONObject;
  lFam: string;
  lR: TJSONObject;
begin
  lSb := TStringBuilder.Create;
  lWith := TList<TJSONObject>.Create;
  lKeys := TList<string>.Create;
  try
    lSb.Append(pM.HomeIntro.TrimRight + CRLF + CRLF);
    lSb.Append('**Status: alpha** (current release v' + pM.Product + '; extractor ' + pM.Extractor + ', resolver ' + pM.Resolver
      + ', index schema ' + pM.Schema + '). Expect breaking changes. The index format is stable within a schema version; the CLI surface is not yet frozen.' + CRLF + CRLF);
    lSb.Append('## Start here' + CRLF + CRLF + '| Page | For |' + CRLF + '|---|---|' + CRLF);
    lSb.Append('| **[Features](Features)** | Everything it does, grouped |' + CRLF);
    lSb.Append('| **[Feature Index](Feature-Index)** | Every feature by the surface it is reached from |' + CRLF);
    lSb.Append('| **[Quick Help](Quick-Help)** | One line per feature, with the short help and the aliases people search for |' + CRLF);
    for lE in pM.Entries do
      if Has(lE, 'homeOrder') then
        lWith.Add(lE);
    for lFam in pM.FamilyNames do
      for lE in pM.Children[lFam] do
        if Has(lE, 'homeOrder') then
          lWith.Add(lE);
    for lE in lWith do
      lKeys.Add(Format('%.6d|%s', [StrToInt(Str(lE, 'homeOrder')), Str(lE, 'id')]));
    for lE in SortByKeys(lWith.ToArray, lKeys.ToArray) do
      lSb.Append('| **[' + Str(lE, 'title') + '](' + Str(lE, 'wikiPage') + ')** | ' + Str(lE, 'summary') + ' |' + CRLF);
    lSb.Append(CRLF + '## Related projects' + CRLF + CRLF);
    for lR in Objects(pM.RelatedRoot, 'projects') do
      lSb.Append('* **' + Str(lR, 'name') + '** -- ' + Str(lR, 'summary') + CRLF);
    lSb.Append(CRLF + '## Links' + CRLF + CRLF + '* [Issues](https://github.com/Alexl-git/Delphi-RAG-Lint/issues)' + CRLF
      + '* [Releases](https://github.com/Alexl-git/Delphi-RAG-Lint/releases)' + CRLF + '* `CHANGELOG.md` in the repository root' + CRLF + CRLF);
    lSb.Append(GENERATED_BY);
    Result := lSb.ToString;
  finally
    lKeys.Free;
    lWith.Free;
    lSb.Free;
  end;
end;

function RenderRuleStats(const pM: TWikiModel): string;
var
  lRules, lCats: TArray<TJSONObject>;
  lR, lC: TJSONObject;
  lKeys: TArray<string>;
  lTotal, lOn, lBuiltin, lScm, lFix, i: Integer;
begin
  lRules := RuleList(pM);
  lTotal := StrToInt(Str(RuleSummary(pM), 'total'));
  lOn := 0;
  lBuiltin := 0;
  lScm := 0;
  for lR in lRules do
  begin
    if IsTrue(lR, 'default_enabled') then
      Inc(lOn);
    if SameText(Str(lR, 'source'), 'builtin') then
      Inc(lBuiltin);
    if SameText(Str(lR, 'source'), 'scm') then
      Inc(lScm);
  end;
  Result := Format('**%d rules. %d have an auto-fix. %d are on by default.** %d are built-in checks; %d are external tree-sitter `.scm` rules you can read and extend in `rules\`. Run `drag-lint rules` for the always-current catalogue.',
    [lTotal, FixableCount(pM), lOn, lBuiltin, lScm]) + CRLF + CRLF;
  Result := Result + '| Category | Rules | With auto-fix |' + CRLF + '|---|---:|---:|' + CRLF;
  lCats := Objects(RuleSummary(pM), 'per_category');
  SetLength(lKeys, Length(lCats));
  for i := 0 to High(lCats) do
    lKeys[i] := Str(lCats[i], 'category');
  for lC in SortByKeys(lCats, lKeys) do
  begin
    lFix := 0;
    for lR in lRules do
      if SameText(Str(lR, 'category'), Str(lC, 'category')) and IsTrue(lR, 'fixable') then
        Inc(lFix);
    Result := Result + '| ' + Str(lC, 'category') + ' | ' + Str(lC, 'count') + ' | ' + (if lFix > 0 then IntToStr(lFix) else '-') + ' |' + CRLF;
  end;
  Result := Result + Format('| **Total** | **%d** | **%d** |', [lTotal, FixableCount(pM)]) + CRLF + CRLF;
end;

function WorkedExample(const pEntry: TJSONObject): string;
var
  lX: TJSONObject;
  lPath, lStem: string;
begin
  Result := '';
  for lX in Objects(pEntry, 'examples') do
  begin
    lPath := Str(lX, 'path');
    if SameText(Str(lX, 'kind'), 'file') and StartsText('docs\wiki\', lPath) and EndsText('.md', lPath) then
    begin
      lStem := TPath.GetFileNameWithoutExtension(lPath);
      Exit(' (worked example: [' + lStem.Replace('-', ' ') + '](' + lStem + '))');
    end;
  end;
end;

function RenderFeatures(const pM: TWikiModel): string;
var
  lSb: TStringBuilder;
  lG, lE: TJSONObject;
  lRows: TArray<TJSONObject>;
  lCell: string;
begin
  lSb := TStringBuilder.Create;
  try
    lSb.Append(pM.FeaturesIntro.TrimRight + CRLF + CRLF + '---' + CRLF + CRLF);
    for lG in pM.Groups do
    begin
      lSb.Append('## ' + Str(lG, 'title') + CRLF + CRLF + Str(lG, 'summary') + CRLF + CRLF);
      lRows := GroupRows(pM, lG);
      for lE in lRows do
        if Has(lE, 'family') and SameText(Str(lE, 'family'), FAMILY_LINT) then
          lSb.Append(RenderRuleStats(pM));
      lSb.Append('| Feature | Surfaces | Status |' + CRLF + '|---|---|---|' + CRLF);
      for lE in lRows do
      begin
        if Has(lE, 'family') then
          lCell := FamilyCountText(pM, lE) + '; ' + SurfaceCell(lE)
        else
          lCell := SurfaceCell(lE);
        lSb.Append('| [' + Str(lE, 'title') + '](' + Str(lE, 'wikiPage') + ')' + WorkedExample(lE) + ' | ' + lCell + ' | ' + StatusCell(lE) + ' |' + CRLF);
      end;
      lSb.Append(CRLF);
    end;
    lSb.Append('---' + CRLF + CRLF + '*Generated by `featuregen build --all` from `features\`; counts come from `drag-lint rules --json` at generation time. Do not edit by hand.*' + CRLF);
    Result := lSb.ToString;
  finally
    lSb.Free;
  end;
end;

function IndexLine(const pEntry: TJSONObject; const pDetail: string): string;
begin
  Result := '* [' + Str(pEntry, 'title') + '](' + Str(pEntry, 'wikiPage') + ')' + (if pDetail <> '' then ' -- ' + pDetail else '') + CRLF;
end;

function SurfacesOfTypes(const pEntry: TJSONObject; const pTypes: array of string): TArray<TJSONObject>;
var
  lS: TJSONObject;
  lList: TList<TJSONObject>;
begin
  lList := TList<TJSONObject>.Create;
  try
    for lS in Objects(pEntry, 'surfaces') do
      if InList(Str(lS, 'type'), pTypes) then
        lList.Add(lS);
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function IndexDetail(pSection: Integer; const pMine: TArray<TJSONObject>): string;
var
  lS: TJSONObject;
  lParts: TList<string>;
  lT: string;
begin
  lParts := TList<string>.Create;
  try
    for lS in pMine do
    begin
      lT := Str(lS, 'type');
      case pSection of
        0: lParts.Add((if SameText(lT, 'ide-about') then 'About window: ' + Str(lS, 'caption') else Str(lS, 'path')));  // dl:ok case-magic-numbers@3cc9 -- REVIEWED 2026-10-19: the case labels are the literal tag values of a ported dispatch; naming them adds nothing
        1: lParts.Add(Str(lS, 'host') + ': ' + Str(lS, 'caption'));  // dl:ok case-magic-numbers@1ea0 -- REVIEWED 2026-10-19: the case labels are the literal tag values of a ported dispatch; naming them adds nothing
        2: lParts.Add(Str(lS, 'path'));  // dl:ok case-magic-numbers@81ac -- REVIEWED 2026-10-19: the case labels are the literal tag values of a ported dispatch; naming them adds nothing
        SECTION_CLI: lParts.Add(CliSurface(lS));
      else
        if SameText(lT, 'script') then
          lParts.Add('`' + Str(lS, 'path') + '`')
        else if SameText(lT, 'exe') then
          lParts.Add('`' + Str(lS, 'name') + '`')
        else if SameText(lT, 'workflow') then
          lParts.Add('procedure');
      end;
    end;
    Result := Join(lParts.ToArray, (if pSection >= SECTION_CLI then ', ' else '; '));
  finally
    lParts.Free;
  end;
end;

function SectionTypes(pSection: Integer): TArray<string>;
begin
  case pSection of
    0: Result := ['ide-menu', 'ide-about'];  // dl:ok case-magic-numbers@c641 -- REVIEWED 2026-10-19: the case labels are the literal tag values of a ported dispatch; naming them adds nothing
    1: Result := ['ide-context'];  // dl:ok case-magic-numbers@ce42 -- REVIEWED 2026-10-19: the case labels are the literal tag values of a ported dispatch; naming them adds nothing
    2: Result := ['tool-window'];  // dl:ok case-magic-numbers@97a0 -- REVIEWED 2026-10-19: the case labels are the literal tag values of a ported dispatch; naming them adds nothing
    3: Result := ['cli'];  // dl:ok case-magic-numbers@be0b -- REVIEWED 2026-10-19: the case labels are the literal tag values of a ported dispatch; naming them adds nothing
  else
    Result := ['script', 'exe', 'workflow'];
  end;
end;

function RenderFeatureIndex(const pM: TWikiModel): string;
const
  SECTION_NAMES: array[0..4] of string = ('Main menu', 'Right-click menus', 'Tool windows', 'CLI verbs', 'Scripts and tools');
var
  lSb: TStringBuilder;
  lHand, lRows: TList<TJSONObject>;
  lKeys: TList<string>;
  lE, lC, lR: TJSONObject;
  lSec: Integer;
  lRules: TDictionary<string, TJSONObject>;
  lRid, lId: string;
begin
  lSb := TStringBuilder.Create;
  lHand := TList<TJSONObject>.Create;
  lRows := TList<TJSONObject>.Create;
  lKeys := TList<string>.Create;
  lRules := TDictionary<string, TJSONObject>.Create;
  try
    for lE in pM.Entries do
      if not InList(Str(lE, 'status'), ['planned', 'internal']) then
        lHand.Add(lE);
    lSb.Append('# Feature Index' + CRLF + CRLF + 'Every registered feature, by the surface it is reached from. Generated by `featuregen build --all` from `features\entries\*.json` and the two imported families; do not edit by hand. See also [Features](Features) for the grouped overview, [Quick Help](Quick-Help) for one line per feature, and [IDE Menu Reference](IDE-Menu-Reference) for the menu layout.' + CRLF + CRLF);
    for lSec := 0 to High(SECTION_NAMES) do
    begin
      lSb.Append('## ' + SECTION_NAMES[lSec] + CRLF + CRLF);
      lRows.Clear;
      lKeys.Clear;
      for lE in lHand do
        if Length(SurfacesOfTypes(lE, SectionTypes(lSec))) > 0 then
        begin
          lRows.Add(lE);
          lKeys.Add(LowerCase(Str(lE, 'title')) + '|' + Str(lE, 'id'));
        end;
      for lE in SortByKeys(lRows.ToArray, lKeys.ToArray) do
        lSb.Append(IndexLine(lE, IndexDetail(lSec, SurfacesOfTypes(lE, SectionTypes(lSec)))));
      lSb.Append(CRLF);
    end;
    lSb.Append('## Diagrams and charts' + CRLF + CRLF + 'Every chart question, by its **drag-lint > Reports** caption in RAD Studio. Outside the IDE ask the same question with `charts\src\Ask-Report.ps1 -Question <id>` -- see [Charts and the IDE](Charts-and-the-IDE). Script paths are relative to a repository clone in v1.' + CRLF + CRLF);
    if pM.Children.ContainsKey(FAMILY_CHART) then
      for lC in pM.Children[FAMILY_CHART] do
      begin
        lId := Str(lC, 'id');
        lSb.Append('* [' + Str(lC, 'title') + '](' + Str(lC, 'wikiPage') + ') -- `' + Copy(lId, Length(CHART_ID_PREFIX) + 1, MaxInt) + '` (' + Str(lC, 'subgroup') + ')' + CRLF);
      end;
    lSb.Append(CRLF + '## Lint rules' + CRLF + CRLF + 'One line per rule, linking the rule reference. Counts: see [Features](Features#linting).' + CRLF + CRLF);
    if pM.Children.ContainsKey(FAMILY_LINT) then
    begin
      for lR in RuleList(pM) do
        lRules.AddOrSetValue(Str(lR, 'id'), lR);
      for lC in pM.Children[FAMILY_LINT] do
      begin
        lRid := Str(lC, 'wikiAnchor');
        lR := nil;
        lRules.TryGetValue(lRid, lR);
        lSb.Append('* [' + lRid + '](' + Str(lC, 'wikiPage') + '#' + lRid + ') -- ' + Str(lR, 'category') + ', ' + Str(lR, 'default_severity')
          + (if IsTrue(lR, 'fixable') then ', fixable' else '') + CRLF);
      end;
    end;
    lSb.Append(CRLF);
    Result := lSb.ToString;
  finally
    lRules.Free;
    lKeys.Free;
    lRows.Free;
    lHand.Free;
    lSb.Free;
  end;
end;

function RenderQuickHelp(const pM: TWikiModel): string;
var
  lSb: TStringBuilder;
  lDeclared: TList<string>;
  lG, lE, lS: TJSONObject;
  lRows: TArray<TJSONObject>;
  lAliases: TArray<string>;
  lT, lTitle, lD: string;
begin
  lSb := TStringBuilder.Create;
  lDeclared := TList<string>.Create;
  try
    lSb.Append(pM.QuickIntro.TrimRight + CRLF + CRLF);
    for lG in pM.Groups do
    begin
      lRows := GroupRows(pM, lG);
      if Length(lRows) = 0 then
        Continue;
      lSb.Append('## ' + Str(lG, 'title') + CRLF + CRLF);
      for lE in lRows do
      begin
        lTitle := Str(lE, 'title');
        if Has(lE, 'family') then
          lSb.Append('* **' + lTitle + '** -- ' + FamilyCountText(pM, lE) + '. ' + Str(lE, 'summary') + '. [More](' + Str(lE, 'wikiPage') + ')' + CRLF)
        else
        begin
          lSb.Append('* **' + lTitle + '**' + (if not SameText(Str(lE, 'status'), 'shipped') then ' (' + Str(lE, 'status') + ')' else '')
            + ' -- ' + Str(lE, 'summary') + '.' + (if Has(lE, 'intro') then ' ' + Str(lE, 'intro') else '') + ' [More](' + Str(lE, 'wikiPage') + ')' + CRLF);
          lAliases := Strings(lE, 'aliases');
          if Length(lAliases) > 0 then
            lSb.Append('  aliases: ' + Join(lAliases, ', ') + CRLF);
        end;
        for lS in Objects(lE, 'surfaces') do
        begin
          lT := Str(lS, 'type');
          if SameText(lT, 'shortcut') then
            lDeclared.Add(lTitle + ': shortcut ' + Str(lS, 'keys'))
          else if SameText(lT, 'lsp') then
            lDeclared.Add(lTitle + ': lsp ' + Str(lS, 'method'))
          else if SameText(lT, 'workflow') then
            lDeclared.Add(lTitle + ': procedure ' + Str(lS, 'doc'))
          else if SameText(lT, 'ide-context') then
            lDeclared.Add(lTitle + ': host ''' + Str(lS, 'host') + ''' (the caption is verified, the host is declared)')
          else if SameText(lT, 'exe') and Has(lS, 'menu') then
            lDeclared.Add(lTitle + ': menu ''' + Str(lS, 'menu') + ''' inside ' + Str(lS, 'name'));
        end;
      end;
      lSb.Append(CRLF);
    end;
    lSb.Append('## Declared, not harvested' + CRLF + CRLF + 'The guard verifies CLI verbs, menu captions, MCP tools, scripts and pages. The surfaces below are declared by their entries and exercised only by the periodic review; a green battery does not prove them.' + CRLF + CRLF);
    for lD in SortedUnique(lDeclared.ToArray) do
      lSb.Append('* ' + lD + CRLF);
    lSb.Append(CRLF + GENERATED_BY);
    Result := lSb.ToString;
  finally
    lDeclared.Free;
    lSb.Free;
  end;
end;

function RenderAgentVerbs(const pM: TWikiModel): string;
var
  lLines, lKeys: TList<string>;
  lE, lS: TJSONObject;
  lVerb: string;
  lIdx: TArray<Integer>;
  lKeyArr: TArray<string>;
  i, lK: Integer;
begin
  lLines := TList<string>.Create;
  lKeys := TList<string>.Create;
  try
    for lE in pM.Entries do
    begin
      if not InList(Str(lE, 'audience'), ['agent', 'both']) then
        Continue;
      if SameText(Str(lE, 'status'), 'planned') then
        Continue;
      for lS in Objects(lE, 'surfaces') do
      begin
        if not SameText(Str(lS, 'type'), 'cli') then
          Continue;
        lVerb := Str(lS, 'verb') + (if Has(lS, 'sub') then ' ' + Str(lS, 'sub') else '');
        lKeys.Add(lVerb + '|' + Str(lE, 'id'));
        lLines.Add('| `' + lVerb + '` | [' + Str(lE, 'title') + '](' + WIKI_URL + Str(lE, 'wikiPage') + ') | ' + Str(lE, 'summary') + ' | '
          + Join(Strings(lE, 'requires'), ', ') + ' |');
      end;
    end;
    lKeyArr := lKeys.ToArray;
    SetLength(lIdx, lKeys.Count);
    for i := 0 to High(lIdx) do
      lIdx[i] := i;
    TArray.Sort<Integer>(lIdx, TComparer<Integer>.Construct(
      function(const pA, pB: Integer): Integer
      begin
        Result := CompareStr(lKeyArr[pA], lKeyArr[pB]);
        if Result = 0 then
          Result := pA - pB;
      end));
    Result := '| Verb | Feature | Summary | Requires |' + CRLF + '|---|---|---|---|' + CRLF;
    for lK in lIdx do
      Result := Result + lLines[lK] + CRLF;
  finally
    lKeys.Free;
    lLines.Free;
  end;
end;

function GroupAnchor(const pTitle: string): string;
begin
  Result := TRegEx.Replace(LowerCase(pTitle), '[^a-z0-9 -]', '').Replace(' ', '-');
end;

function RenderFeatureSummary(const pM: TWikiModel): string;
var
  lG, lE: TJSONObject;
  lRows: TArray<TJSONObject>;
  lExtra: TList<string>;
  lText, lAnchor: string;
begin
  Result := '| Group | Features | Wiki |' + CRLF + '|---|---:|---|' + CRLF;
  lExtra := TList<string>.Create;
  try
    for lG in pM.Groups do
    begin
      lRows := GroupRows(pM, lG);
      lExtra.Clear;
      for lE in lRows do
        if Has(lE, 'family') then
        begin
          lText := FamilyCountText(pM, lE);
          if lText <> '' then
            lExtra.Add(lText);
        end;
      lAnchor := GroupAnchor(Str(lG, 'title'));
      Result := Result + '| [' + Str(lG, 'title') + '](' + WIKI_URL + 'Features#' + lAnchor + ') | ' + IntToStr(Length(lRows))
        + (if lExtra.Count > 0 then ' (+ ' + Join(lExtra.ToArray, ', ') + ')' else '') + ' | [Quick Help](' + WIKI_URL + 'Quick-Help#' + lAnchor + ') |' + CRLF;
    end;
  finally
    lExtra.Free;
  end;
end;

{ A deep copy without lastVerified (Remove-ManifestVolatile). }
function ManifestCopy(const pObj: TJSONObject): TJSONObject;
begin
  Result := pObj.Clone as TJSONObject;
  Result.RemovePair('lastVerified').Free;
end;

function RenderManifest(const pM: TWikiModel): string;
var
  lM, lFamilies: TJSONObject;
  lArr: TJSONArray;
  lG, lE: TJSONObject;
  lFam: string;
begin
  lM := TJSONObject.Create;
  try
    lM.AddPair('product', pM.Product);
    lM.AddPair('extractor', pM.Extractor);
    lM.AddPair('resolver', pM.Resolver);
    lM.AddPair('schema', TJSONNumber.Create(StrToIntDef(pM.Schema, 0)));
    lArr := TJSONArray.Create;
    lM.AddPair('groups', lArr);
    for lG in pM.Groups do
      lArr.AddElement(lG.Clone as TJSONValue);
    lArr := TJSONArray.Create;
    lM.AddPair('teams', lArr);
    for lG in Objects(pM.TeamsRoot, 'teams') do
      lArr.AddElement(lG.Clone as TJSONValue);
    lArr := TJSONArray.Create;
    lM.AddPair('entries', lArr);
    for lE in pM.Entries do
      lArr.AddElement(ManifestCopy(lE));
    lFamilies := TJSONObject.Create;
    lM.AddPair('families', lFamilies);
    for lFam in pM.FamilyNames do
    begin
      lArr := TJSONArray.Create;
      lFamilies.AddPair(lFam, lArr);
      for lE in pM.Children[lFam] do
        lArr.AddElement(ManifestCopy(lE));
    end;
    Result := CanonicalJson(lM, nil);
  finally
    lM.Free;
  end;
end;

{ ---- public ---- }

function WikiOutputPaths: TArray<string>;
begin
  Result := ['docs\wiki\Home.md', 'docs\wiki\Features.md', 'docs\wiki\Feature-Index.md', 'docs\wiki\Quick-Help.md',
    'README.md', 'docs\AI-USAGE.md', 'features\generated\manifest.json'];
end;

function UpdateMarkedBlock(const pText, pName, pBody: string): string;
var
  lBegin, lEnd: string;
  lI, lJ: Integer;
begin
  lBegin := '<!-- dl:registry:begin ' + pName + ' -->';
  lEnd := '<!-- dl:registry:end ' + pName + ' -->';
  lI := Pos(lBegin, pText);
  lJ := Pos(lEnd, pText);
  if (lI = 0) or (lJ = 0) or (lJ < lI) then
    raise EFeatureGen.CreateFmt('markers absent: ''%s'' / ''%s'' must both exist, in that order -- the generator never appends blindly', [lBegin, lEnd]);
  Result := Copy(pText, 1, lI - 1 + Length(lBegin)) + CRLF + pBody + Copy(pText, lJ, MaxInt);
end;

procedure BuildWiki(const pRepo: string; const pWriter: TOutputWriter; const pEngine: string);
var
  lEngine: string;
  lM: TWikiModel;
  lFmt: TSiteFormat;
  lHelp: TLiveHelp;
  lReg: TRegistry;
  lUsage, lReadme: string;
  lAliases: TArray<TFlagAlias>;
begin
  lEngine := (if pEngine <> '' then pEngine else TPath.Combine(pRepo, 'third_party\dll-win64\drag-lint.exe'));
  lM := TWikiModel.Create;
  try
    LoadModel(pRepo, lEngine, lM);
    pWriter.Put('docs\wiki\Home.md', RenderHome(lM), 'docs\wiki\Home.md');
    pWriter.Put('docs\wiki\Features.md', RenderFeatures(lM), 'docs\wiki\Features.md');
    pWriter.Put('docs\wiki\Feature-Index.md', RenderFeatureIndex(lM), 'docs\wiki\Feature-Index.md');
    pWriter.Put('docs\wiki\Quick-Help.md', RenderQuickHelp(lM), 'docs\wiki\Quick-Help.md');
    lAliases := LoadFlagAliases(pRepo);
    lReadme := UpdateMarkedBlock(ReadAsciiStrict(TPath.Combine(pRepo, 'README.md')), 'feature-summary', RenderFeatureSummary(lM));
    lUsage := UpdateMarkedBlock(ReadAsciiStrict(TPath.Combine(pRepo, 'docs\AI-USAGE.md')), 'agent-verbs', RenderAgentVerbs(lM));
    { A root without an alias table (a test fixture) has no flag-aliases markers either; a root WITH one must carry them. }
    if Length(lAliases) > 0 then
    begin
      lReadme := UpdateMarkedBlock(lReadme, 'flag-aliases', FlagAliasesMarkdown(lAliases, False));
      lUsage := UpdateMarkedBlock(lUsage, 'flag-aliases', FlagAliasesMarkdown(lAliases, False));
    end;
    pWriter.Put('README.md', lReadme, 'README.md feature-summary + flag-aliases blocks');
    pWriter.Put('docs\AI-USAGE.md', lUsage, 'docs\AI-USAGE.md agent-verbs + flag-aliases blocks');
    pWriter.Put('features\generated\manifest.json', RenderManifest(lM), 'features\generated\manifest.json');
  finally
    lM.Free;
  end;
  lFmt := LoadSiteFormat(pRepo);
  lHelp := TLiveHelp.Create;
  lReg := TRegistry.Create;
  try
    lHelp.Load(lEngine);
    lFmt.Help := lHelp;
    lReg.Load(pRepo);
    pWriter.Put('features\generated\cli-reference.md', CliReferenceMd(lFmt, lReg, pRepo), 'features\generated\cli-reference.md');
    pWriter.Put(HELPTEXT_UNIT_PATH, RenderHelpTextUnit(lReg), HELPTEXT_UNIT_PATH);
  finally
    lReg.Free;
    lHelp.Free;
  end;
end;

end.
