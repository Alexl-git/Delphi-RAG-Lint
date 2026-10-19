unit FeatureGen.SiteFormat;

{ The website format config: features\site-format.json. Every value of spec
  5.2 that WWW may still change lives there, not in code. }

interface

uses
  System.SysUtils
  , FeatureGen.Live
  , FeatureGen.Model
  ;

type
  /// <summary>Parsed features\site-format.json.</summary>
  /// <remarks>Help is set by the caller and is NOT owned; nil means usage falls back to "drag-lint verb".</remarks>
  TSiteFormat = record
    /// <summary>Website root, repo-relative.</summary>
    Root: string;
    Product: string;
    /// <summary>Front matter keys in output order.</summary>
    FrontMatterKeys: TArray<string>;
    IncludeStatuses: TArray<string>;
    ExcludeAudiences: TArray<string>;
    FenceDefaultLang: string;
    /// <summary>Opening Markdown sentence of index.md.</summary>
    MicroniteIndex: string;
    /// <summary>Opening Markdown sentence of whats-new.md.</summary>
    MicroniteWhatsNew: string;
    ImageDir: string;
    /// <summary>Repo-relative engine exe path.</summary>
    Engine: string;
    /// <summary>Repo-relative path of the docs-sync guard that lists $UndocumentedOnPurpose.</summary>
    UndocumentedSource: string;
    /// <summary>Cli verbs keyed in the $UndocumentedOnPurpose block of UndocumentedSource; an entry with such a verb is not on the site. Filled by LoadSiteFormat.</summary>
    ExcludedVerbs: TArray<string>;
    /// <summary>Wiki page names (no .md, any case) of GENERATED pages; an entry naming one has no wiki page of its own.</summary>
    GeneratedWikiPages: TArray<string>;
    Help: TLiveHelp;
  end;

/// <summary>Reads features\site-format.json.</summary>
/// <param name="pRepo">Repo root holding features\.</param>
/// <returns>The format; Help is nil; ExcludedVerbs is read from UndocumentedSource.</returns>
/// <exception cref="EFeatureJson">The file is missing or malformed.</exception>
/// <exception cref="EFeatureGen">undocumentedSource is missing, or its $UndocumentedOnPurpose block cannot be found or holds no key (never read as empty).</exception>
function LoadSiteFormat(const pRepo: string): TSiteFormat;

/// <summary>Reads the keys of the $UndocumentedOnPurpose = [ordered]@{ 'verb' = '...' } block of a PowerShell file.</summary>
/// <param name="pFile">Full path of the file.</param>
/// <returns>The keys, in file order.</returns>
/// <exception cref="EFeatureGen">The file is missing, the block is not found, or it holds no key.</exception>
function ReadUndocumentedVerbs(const pFile: string): TArray<string>;

/// <summary>True when an entry belongs on the site: SiteIncludes holds and none of its cli verbs is in ExcludedVerbs.</summary>
/// <param name="pFmt">Format.</param>
/// <param name="pEntry">The entry.</param>
/// <returns>Whether the entry gets a page and may be linked.</returns>
function EntryOnSite(const pFmt: TSiteFormat; const pEntry: TFeatureEntry): Boolean;

/// <summary>True when an entry belongs on the site.</summary>
/// <param name="pFmt">Format holding the include/exclude lists.</param>
/// <param name="pStatus">Entry status.</param>
/// <param name="pAudience">Entry audience ('' when absent).</param>
/// <returns>Status is in IncludeStatuses and audience is not in ExcludeAudiences.</returns>
function SiteIncludes(const pFmt: TSiteFormat; const pStatus, pAudience: string): Boolean;

/// <summary>True when a wikiPage value names a generated page (GeneratedWikiPages).</summary>
/// <param name="pFmt">Format.</param>
/// <param name="pPage">wikiPage value, with or without .md; '' is not generated.</param>
/// <returns>Case-insensitive match against GeneratedWikiPages; such an entry gets a leaf without Details and no wiki-map row.</returns>
function IsGeneratedWikiPage(const pFmt: TSiteFormat; const pPage: string): Boolean;

implementation

uses
  System.IOUtils
  , System.JSON
  , System.RegularExpressions
  , FeatureGen.Json
  , FeatureGen.Output
  ;

function Strs(pObj: TJSONValue; const pName: string): TArray<string>;
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
  for i := 0 to High(Result) do
    Result[i] := TJSONArray(lV).Items[i].Value;
end;

function ReadUndocumentedVerbs(const pFile: string): TArray<string>;
var
  lLine: string;
  lIn: Boolean;
  lM: TMatch;
begin
  if not TFile.Exists(pFile) then
    raise EFeatureGen.CreateFmt('undocumented-verb source not found: %s', [pFile]);
  lIn := False;
  SetLength(Result, 0);
  for lLine in TFile.ReadAllLines(pFile) do
  begin
    if not lIn then
    begin
      lIn := TRegEx.IsMatch(lLine, '^\$UndocumentedOnPurpose\s*=\s*\[ordered\]@\{');
      Continue;
    end;
    if TRegEx.IsMatch(lLine, '^\}') then
      Break;
    lM := TRegEx.Match(lLine, '^\s*''([^'']+)''\s*=');
    if lM.Success then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := lM.Groups[1].Value;
    end;
  end;
  if (not lIn) or (Length(Result) = 0) then
    raise EFeatureGen.CreateFmt('$UndocumentedOnPurpose block not found or empty in %s', [pFile]);
end;

function IsGeneratedWikiPage(const pFmt: TSiteFormat; const pPage: string): Boolean;
var
  lS, lName: string;
begin
  Result := False;
  lName := pPage;
  if SameText(ExtractFileExt(lName), '.md') then
    lName := Copy(lName, 1, Length(lName) - 3);
  if lName = '' then
    Exit;
  for lS in pFmt.GeneratedWikiPages do
    if SameText(lS, lName) then
      Result := True;
end;

function EntryOnSite(const pFmt: TSiteFormat; const pEntry: TFeatureEntry): Boolean;
var
  lS: TSurface;
  lV: string;
begin
  Result := SiteIncludes(pFmt, pEntry.Status, pEntry.Audience);
  for lS in pEntry.Surfaces do
    if lS.Kind = 'cli' then
      for lV in pFmt.ExcludedVerbs do
        if lV = lS.Verb then
          Result := False;
end;

function LoadSiteFormat(const pRepo: string): TSiteFormat;
var
  lRoot, lMic: TJSONValue;
begin
  Result := Default(TSiteFormat);
  lRoot := ReadJsonFile(TPath.Combine(pRepo, 'features\site-format.json'));
  try
    Result.Root := Prop(lRoot, 'root');
    Result.Product := Prop(lRoot, 'product');
    Result.FrontMatterKeys := Strs(lRoot, 'frontMatterKeys');
    Result.IncludeStatuses := Strs(lRoot, 'includeStatuses');
    Result.ExcludeAudiences := Strs(lRoot, 'excludeAudiences');
    Result.FenceDefaultLang := Prop(lRoot, 'fenceDefaultLang');
    lMic := nil;
    if lRoot is TJSONObject then
      lMic := TJSONObject(lRoot).GetValue('micronite');
    Result.MicroniteIndex := Prop(lMic, 'index');
    Result.MicroniteWhatsNew := Prop(lMic, 'whatsNew');
    Result.ImageDir := Prop(lRoot, 'imageDir');
    Result.Engine := Prop(lRoot, 'engine');
    Result.GeneratedWikiPages := Strs(lRoot, 'generatedWikiPages');
    Result.UndocumentedSource := Prop(lRoot, 'undocumentedSource');
    if Result.UndocumentedSource = '' then
      raise EFeatureGen.Create('site-format.json: undocumentedSource is missing');
    Result.ExcludedVerbs := ReadUndocumentedVerbs(TPath.Combine(pRepo, Result.UndocumentedSource));
  finally
    lRoot.Free;
  end;
end;

function SiteIncludes(const pFmt: TSiteFormat; const pStatus, pAudience: string): Boolean;
var
  lS: string;
begin
  Result := False;
  for lS in pFmt.IncludeStatuses do
    if lS = pStatus then
      Result := True;
  for lS in pFmt.ExcludeAudiences do
    if lS = pAudience then
      Result := False;
end;

end.
